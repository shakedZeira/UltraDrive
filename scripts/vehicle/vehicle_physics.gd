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

# --- Internal ---
var _drivetrain: Drivetrain
var _wheels: Array[WheelPhysics]
var _prev_position: Vector3

func _ready() -> void:
    if config == null:
        config = load("res://resources/cars/starter_car.tres") as CarConfig

    _drivetrain = Drivetrain.new()
    _wheels = [wheel_fl, wheel_fr, wheel_rl, wheel_rr]

    # Configure RigidBody3D
    mass = config.mass_kg
    center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
    center_of_mass = config.center_of_mass_offset
    linear_damp = 0.0  # we handle air resistance ourselves
    angular_damp = 0.5

    _prev_position = global_position

func _physics_process(delta: float) -> void:
    if config == null:
        return

    var throttle := InputManager.get_throttle()
    var brake_input := InputManager.get_brake()
    var steer_input := InputManager.get_steer()
    var handbrake := InputManager.is_handbrake()

    # --- Reset car ---
    if InputManager.is_reset():
        reset_car()
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
    var drive_info := _drivetrain.update(delta, throttle, config)

    # --- Tire Forces ---
    var grip_mult := config.arcade_mode["grip_multiplier"] if handling_mode == "arcade" else config.simulation_mode["grip_multiplier"]

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
            var brake_force := brake_input * config.max_brake_torque / (0.33 * 2.0)
            if i < 2:  # front wheels get AC drive no drive, only brake
                drive_force = 0.0
            drive_force -= brake_force

            # --- Apply forces to RigidBody3D ---
            apply_central_force(-global_basis.z * drive_force * 0.5)
            apply_central_force(wheel.global_basis.x * lat_force * 0.5)

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
    _prev_position = global_position

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
    return {
        "rpm": _drivetrain.engine_rpm,
        "gear": _drivetrain.current_gear,
        "speed_kmh": current_speed_kmh,
        "handling_mode": handling_mode,
    }

func set_handling_mode(mode: String) -> void:
    if mode in ["arcade", "simulation"]:
        handling_mode = mode

func reset_car() -> void:
    linear_velocity = Vector3.ZERO
    angular_velocity = Vector3.ZERO
    _drivetrain.reset()
    global_position.y += 1.0  # lift slightly above ground
