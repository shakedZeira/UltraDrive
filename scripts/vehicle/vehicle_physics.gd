class_name VehiclePhysics
extends RigidBody3D

## Main vehicle physics controller.
## Attach to a RigidBody3D with 4 WheelPhysics children.

# --- Configuration ---
@export var config: CarConfig

# --- Child References (assign in scene or auto-discover) ---
@onready var wheel_fl: WheelPhysics = $WheelFL
@onready var wheel_fr: WheelPhysics = $WheelFR
@onready var wheel_rl: WheelPhysics = $WheelRL
@onready var wheel_rr: WheelPhysics = $WheelRR

# --- State ---
var current_speed_kmh: float = 0.0
var steer_angle: float = 0.0
var handling_mode: String = "arcade"  # "arcade" or "simulation"
var input_override: Vector2 = Vector2.ZERO  # (steer, throttle-brake)

# --- Input state (exposed via get_drive_info) ---
var _brake_input: float = 0.0
var _steer_input: float = 0.0

# --- Internal ---
var _drivetrain: Drivetrain
var _wheels: Array[WheelPhysics]
var _spawn_point: Vector3

func _ready() -> void:
    if config == null:
        config = load("res://resources/cars/starter_car.tres") as CarConfig

    _drivetrain = Drivetrain.new()
    _wheels = [wheel_fl, wheel_fr, wheel_rl, wheel_rr]

    # Configure RigidBody3D
    mass = config.mass_kg
    center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
    center_of_mass = config.center_of_mass_offset
    linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
    linear_damp = 0.0  # we handle air resistance ourselves
    angular_damp = 0.5

    # Low-friction contact material; traction comes from the virtual tire model.
    var contact_mat := PhysicsMaterial.new()
    contact_mat.friction = 0.0
    physics_material_override = contact_mat

    _spawn_point = global_position

func set_input_override(value: Vector2) -> void:
    input_override = value

func _physics_process(delta: float) -> void:
    if config == null:
        return

    if global_position.y < -20.0:
        respawn_at(_spawn_point)
        return

    var throttle := InputManager.get_throttle() if input_override == Vector2.ZERO else clampf(input_override.y, -1.0, 1.0)
    var brake_input := InputManager.get_brake() if input_override == Vector2.ZERO else maxf(-input_override.y, 0.0)
    var steer_input := InputManager.get_steer() if input_override == Vector2.ZERO else clampf(input_override.x, -1.0, 1.0)
    var handbrake := InputManager.is_handbrake()
    _brake_input = clampf(brake_input, 0.0, 1.0)
    _steer_input = clampf(steer_input, -1.0, 1.0)

    # --- Reset car ---
    if InputManager.is_reset():
        respawn_at(_spawn_point)
        return

    # --- Steering ---
    var speed_factor := 1.0 - clampf(current_speed_kmh / 200.0, 0.0, 0.7)
    var target_steer := deg_to_rad(config.max_steer_angle) * steer_input * speed_factor
    steer_angle = move_toward(steer_angle, target_steer, config.steer_speed * delta)

    wheel_fl.rotation.y = steer_angle
    wheel_fr.rotation.y = steer_angle

    # --- Drivetrain ---
    var forward_speed := -global_basis.z.dot(linear_velocity)
    _drivetrain.set_wheel_speed(forward_speed)
    _drivetrain.manual_mode = GameState.transmission_mode == GameState.TransmissionMode.MANUAL
    if input_override == Vector2.ZERO and _drivetrain.manual_mode:
        if InputManager.is_shift_up_just_pressed():
            _drivetrain.shift_up(config)
        elif InputManager.is_shift_down_just_pressed():
            _drivetrain.shift_down(config)
    var drive_info := _drivetrain.update(delta, throttle, config)
    # Brake/drive direction runs through the gearbox: reverse flips it.
    var gear_dir := -1.0 if _drivetrain.current_gear < 0 else 1.0

    # --- Tire Forces ---
    var grip_mult: float = config.arcade_mode["grip_multiplier"] if handling_mode == "arcade" else config.simulation_mode["grip_multiplier"]
    grip_mult *= WeatherManager.get_road_grip_factor()

    # Process each wheel
    for i in range(4):
        var wheel := _wheels[i]
        var wheel_info := wheel.process_wheel(delta, config, handbrake)

        if wheel_info["is_grounded"]:
            # --- Slip Angle ---
            var wheel_forward := -wheel.global_basis.z
            var wheel_vel := linear_velocity + angular_velocity.cross(wheel.global_position - global_position)
            var slip_angle := TireModel.calculate_slip_angle(wheel_forward, wheel_vel)

            # --- Lateral Force (grip) ---
            var lat_force := TireModel.calculate_lateral_force(
                slip_angle, wheel_info["normal_force"], config, grip_mult
            )

            # Handbrake reduces rear grip
            if handbrake and i >= 2:  # rear wheels
                lat_force *= config.handbrake_grip_reduction

            # --- Longitudinal Force (drive/brake) ---
            var drive_force := 0.0
            if i >= 2:  # rear wheels get drive (RWD for now)
                drive_force = drive_info["drive_torque"] / (0.33 * 2.0)

            # Braking
            var brake_force := gear_dir * brake_input * config.max_brake_torque / (0.33 * 2.0)
            if i < 2:  # front wheels do not drive, only brake
                drive_force = 0.0
            drive_force -= brake_force

            # --- Apply forces to RigidBody3D ---
            apply_central_force(-global_basis.z * drive_force * 0.5)
            apply_force(wheel.global_basis.x * lat_force * 0.5, wheel.global_position - global_position)

    # --- Air Resistance ---
    var drag_magnitude := 0.5 * 1.225 * config.drag_coefficient * config.frontal_area * linear_velocity.length_squared()
    if linear_velocity.length() > 0.1:
        apply_central_force(-linear_velocity.normalized() * drag_magnitude)

    # --- Anti-flip (arcade mode only) ---
    if handling_mode == "arcade" and config.arcade_mode.get("anti_flip", false):
        var current_up := global_basis.y
        if current_up.y < 0.8:
            var correction := Vector3.UP.cross(current_up) * 50.0
            apply_torque(correction)

    # --- Update speed ---
    current_speed_kmh = linear_velocity.length() * 3.6

# --- Public API ---

func get_speed_kmh() -> float:
    return current_speed_kmh

func get_rpm() -> float:
    return _drivetrain.engine_rpm

func get_gear() -> int:
    return _drivetrain.current_gear

func get_steer_angle() -> float:
    return rad_to_deg(steer_angle)

func get_drive_info() -> Dictionary:
    var rpm := 0.0
    var gear := 0
    if _drivetrain != null:
        rpm = _drivetrain.engine_rpm
        gear = _drivetrain.current_gear
    return {
        "rpm": rpm,
        "gear": gear,
        "speed_kmh": current_speed_kmh,
        "handling_mode": handling_mode,
        "brake": clampf(_brake_input, 0.0, 1.0),
        "steer": clampf(_steer_input, -1.0, 1.0),
    }

func set_handling_mode(mode: String) -> void:
    if mode in ["arcade", "simulation"]:
        handling_mode = mode

func reset_car() -> void:
    linear_velocity = Vector3.ZERO
    angular_velocity = Vector3.ZERO
    _drivetrain.reset()
    global_position.y += 1.0  # lift slightly above ground

func respawn_at(pos: Vector3) -> void:
    linear_velocity = Vector3.ZERO
    angular_velocity = Vector3.ZERO
    _drivetrain.reset()
    # Teleport through the physics server so Jolt accepts the new transform
    # as authoritative instead of fighting the direct setter mid-step.
    # Keep the car yaw but level out any roll/pitch so we never respawn
    # on our roof after tumbling through the void.
    var yaw := global_basis.get_euler().y
    var tfm := Transform3D(Basis(Vector3.UP, yaw), pos + Vector3.UP * 1.0)
    sleeping = false
    PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, tfm)
