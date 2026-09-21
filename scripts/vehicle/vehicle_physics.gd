class_name VehiclePhysics
extends RigidBody3D

## Main vehicle physics controller.
## Attach to a RigidBody3D with 4 WheelPhysics children.

## Sharp-deceleration collision spike: emitted once when the linear-velocity
## delta between physics ticks clears IMPACT_ACCEL_THRESHOLD. Feeds the
## VehicleFX sparks burst and the S3 clean-lap counter
## (GameState.session_stats.note_impact()).
signal impact(strength: float)

# --- Thresholds ---
## Velocity-delta acceleration (m/s^2) that counts as a collision impact.
const IMPACT_ACCEL_THRESHOLD := 320.0
## Minimum speed (km/h) before the car can be considered drifting.
const DRIFT_MIN_SPEED_KMH := 30.0
## Steer input fraction required for input-driven drift smoke.
const DRIFT_STEER_FRACTION := 0.4
## Minimum rear-wheel lateral slip (deg) for slip-driven drift smoke.
const DRIFT_MIN_SLIP_DEG := 6.0
## Global scale on the longitudinal (Pacejka traction) force. 1.0 ships the
## magic-formula math straight; can be nudged below 1.0 later to soften
## launches/threshold-brake without touching the curve shapes the tests gate.
const LONGITUDINAL_EFFECTIVENESS := 1.0

# --- Configuration ---
@export var config: CarConfig

## Analog response curve for the player's triggers (simcade input-feel). Raw
## [0,1] trigger input is mapped through apply_analog_response() so the low end
## is finer - trail-braking and throttle feathering get more resolution where it
## matters. Power 2.0 + deadzone 0.02 is the shipped feel; a power of 1.0 with a
## deadzone of 0.0 reproduces the exact linear read (identity), so the curve can
## be disabled without touching anything else.
const ANALOG_RESPONSE_POWER := 2.0
const ANALOG_RESPONSE_DEADZONE := 0.02

## Tuneable per scene/tests; defaults mirror the consts above.
@export var analog_response_power: float = ANALOG_RESPONSE_POWER
@export var analog_response_deadzone: float = ANALOG_RESPONSE_DEADZONE

## Settable surface provider: Callable(pos: Vector3) -> Dictionary with optional
## keys { surface_key, lateral, longitudinal }. Unset or empty result falls back
## to asphalt (1.0/1.0). Defaults in _ready to the SurfaceRegistry classifier
## bound to the local RoadNetwork when one exists (headless-safe otherwise).
var surface_provider: Callable = Callable()

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
var _last_surface_key: String = SurfaceRegistry.ASPHALT

# --- Input state (exposed via get_drive_info) ---
var _throttle_input: float = 0.0
var _brake_input: float = 0.0
var _steer_input: float = 0.0

# --- Internal ---
var _drivetrain: Drivetrain
var _wheels: Array[WheelPhysics]
var _spawn_point: Vector3
var _prev_linear_velocity := Vector3.ZERO
var _impact_active := false
var _handbrake_input := false
var _last_lateral_slip_deg := 0.0
var _awaiting_ground := true
var _last_valid_position: Vector3
var _last_valid_basis: Basis
var _last_valid_velocity: Vector3
var _last_valid_angular_velocity: Vector3

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
    _snap_last_valid()
    _prev_linear_velocity = linear_velocity
    freeze = true

    if not surface_provider.is_valid():
        surface_provider = SurfaceRegistry.build_classifier(
            SurfaceRegistry.default_road_tier_provider(self), Callable()
        )

func set_input_override(value: Vector2) -> void:
    input_override = value

# --- Ground-release latch ---
## Wait frozen at the spawn point while the terrain region under the car is
## still baking, and release the body only once ground below is proven.
## Prevents the open-world cold-start void fall (no collision yet while
## TerrainSeeder runs its sync bake) without touching the physics math.
func _release_when_grounded(delta: float) -> void:
    var grounded := false
    for wheel in _wheels:
        if wheel.process_wheel(delta, config, false)["is_grounded"]:
            grounded = true
            break
    if not grounded and _ground_exists_below():
        grounded = true
    if grounded:
        freeze = false
        _awaiting_ground = false

## Ground-existence probe: a downward ray well past the terrain clamp range
## proves there is a body under the spawn point, so the latch can drop this
## frozen car onto it. True for meshed circuits from the first physics frame
## and for the open world as soon as the region under the player is baked -
## while the bake runs there is no collision, the ray misses, and the car keeps
## freeze protection. Spawn floats above real ground (track circuits, open
## world) release immediately; a true void never does.
func _ground_exists_below() -> bool:
    var space := get_world_3d().direct_space_state
    if space == null:
        return false
    var query := PhysicsRayQueryParameters3D.create(
        global_position + Vector3.UP,
        global_position + Vector3.DOWN * 30.0,
        0xFFFFFFFF,
        [get_rid()]
    )
    return not space.intersect_ray(query).is_empty()

func release_ground_lock() -> void:
    if _awaiting_ground:
        _awaiting_ground = false
        freeze = false
    _snap_last_valid()

func _physics_process(delta: float) -> void:
    if config == null:
        return

    if _awaiting_ground:
        _release_when_grounded(delta)
        return
    # NaN guard: a corrupted body state (NaN velocity or position) would poison
    # slip math, drag, drift and driveshafts for the whole frame, so restore the
    # last valid snapshot and skip the frame instead.
    if not linear_velocity.is_finite() or not angular_velocity.is_finite() or not global_position.is_finite():
        _restore_last_valid()
        return
    # Arcade limiter: keep forward speed inside [-reverse cap, top speed] so the
    # HUD, drift and wheels all agree on a bounded state (simulation untouched).
    if handling_mode == "arcade":
        linear_velocity = clamp_arcade_speed(
            linear_velocity,
            -global_basis.z,
            config.get_max_speed() * float(config.arcade_mode.get("max_speed_modifier", 1.0)),
            config.max_reverse_speed_kmh / 3.6
        )
    _last_lateral_slip_deg = 0.0
    _detect_impact(delta)

    if global_position.y < -20.0:
        respawn_at(_spawn_point)
        return

    var controls_locked := RaceManager.controls_locked()
    var throttle := 0.0
    var brake_input := 0.0
    var steer_input := 0.0
    var handbrake := false
    if not controls_locked:
        throttle = InputManager.get_throttle() if input_override == Vector2.ZERO else clampf(input_override.y, -1.0, 1.0)
        brake_input = InputManager.get_brake() if input_override == Vector2.ZERO else maxf(-input_override.y, 0.0)
        steer_input = InputManager.get_steer() if input_override == Vector2.ZERO else clampf(input_override.x, -1.0, 1.0)
        handbrake = InputManager.is_handbrake()
        # Player-only analog response curve. Applied to the raw trigger read, and
        # deliberately NOT to scripted input - rivals/traffic drive through
        # input_override (signed y) and must keep their exact values. Keyboard
        # keys read exactly 0.0/1.0, which the curve maps to itself, so the
        # digital fallback is untouched.
        if input_override == Vector2.ZERO:
            throttle = apply_analog_response(throttle, analog_response_power, analog_response_deadzone)
            brake_input = apply_analog_response(brake_input, analog_response_power, analog_response_deadzone)
    _throttle_input = clampf(throttle, 0.0, 1.0)
    _brake_input = clampf(brake_input, 0.0, 1.0)
    _steer_input = clampf(steer_input, -1.0, 1.0)
    _handbrake_input = handbrake

    # --- Reset car ---
    if not controls_locked and InputManager.is_reset():
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
    if controls_locked:
        _drivetrain.rpm_override = RaceManager.rev_override()
    else:
        _drivetrain.rpm_override = -1.0
    if input_override == Vector2.ZERO and _drivetrain.manual_mode and not controls_locked:
        if InputManager.is_shift_up_just_pressed():
            _drivetrain.shift_up(config)
        elif InputManager.is_shift_down_just_pressed():
            _drivetrain.shift_down(config)
    var drive_info := _drivetrain.update(delta, throttle, config)
    # Brake/drive direction runs through the gearbox: reverse flips it.
    var gear_dir := -1.0 if _drivetrain.current_gear < 0 else 1.0

    # --- Tire Forces ---
    var grip_mult: float = config.arcade_mode["grip_multiplier"] if handling_mode == "arcade" else config.simulation_mode["grip_multiplier"]
    var weather_factor := WeatherManager.get_road_grip_factor()
    var surface_factors := resolve_surface_factors()
    var grip_mult_lateral := grip_mult * float(surface_factors["lateral"]) * weather_factor

    # Process each wheel
    for i in range(4):
        var wheel := _wheels[i]
        var wheel_info := wheel.process_wheel(delta, config, handbrake)

        # --- Per-wheel axle torque ---
        # Drive torque flows through the existing Drivetrain (gear/ratio math)
        # unchanged, split across the driven axle. Brake torque keeps the same
        # gear_dir sign convention as the old drive_force -= brake_force path, so
        # reverse braking still acts as travel opposing. Fronts get brake only.
        var drive_axle_torque := 0.0
        if i >= 2:  # rear wheels get drive (RWD for now)
            drive_axle_torque = drive_info["drive_torque"] / 2.0
        var brake_torque := gear_dir * brake_input * config.max_brake_torque

        # --- Tire forces (only when the wheel bears weight) ---
        var lon_force := 0.0
        var slip_ratio := 0.0
        var wheel_forward_speed := 0.0
        if wheel_info["is_grounded"]:
            # --- Slip Angle ---
            var wheel_forward := -wheel.global_basis.z
            var wheel_vel := linear_velocity + angular_velocity.cross(wheel.global_position - global_position)
            var slip_angle := TireModel.calculate_slip_angle(wheel_forward, wheel_vel)
            _last_lateral_slip_deg = maxf(_last_lateral_slip_deg, rad_to_deg(absf(slip_angle)))

            # --- Longitudinal slip: real tire spin vs. contact road speed ---
            # wheel_angular_velocity is integrated per-frame by
            # wheel.step_wheel_spin() from the axle torques minus the tire's
            # ground reaction, so this is a true slip ratio (0 = pure rolling,
            # > 0 = wheelspin, < 0 = lockup), not a scripted one.
            wheel_forward_speed = wheel_forward.dot(wheel_vel)
            slip_ratio = TireModel.calculate_slip_ratio(
                wheel.wheel_angular_velocity, wheel_forward_speed, WheelPhysics.WHEEL_RADIUS
            )

            # --- Lateral Force (grip) ---
            var lat_force := TireModel.calculate_lateral_force(
                slip_angle, wheel_info["normal_force"], config, grip_mult_lateral
            )

            # Handbrake reduces rear grip
            if handbrake and i >= 2:  # rear wheels
                lat_force *= config.handbrake_grip_reduction

            # --- Longitudinal Force through the magic formula ---
            # The Pacejka D-term (normal force * tire_D * grip * surface+weather)
            # scales the pull/brake by how much grip the LOADED tire still has.
            # Peak is at ~20-25% slip for the shipped tires (the E-term moves it
            # past the textbook 10-15%), so a launch wheelspin keeps us inside
            # 90-100% of peak torque rather than an unbounded raw force; a
            # locked brake falls off the far side as grip is lost.
            lon_force = TireModel.calculate_longitudinal_force(
                slip_ratio, wheel_info["normal_force"], config, grip_mult,
                float(surface_factors["longitudinal"]) * weather_factor
            )
            lon_force *= LONGITUDINAL_EFFECTIVENESS

            # --- Friction circle: longitudinal load eats lateral grip ---
            # While longitudinal force consumes the normal-load mu budget, the
            # lateral peak shrinks (sqrt(1 - k^2)) - that is what makes power-on
            # corner exit step out and threshold braking swing the nose. The
            # fleet that understeers off the road through the arcade grip boost
            # stays untouched at zero longitudinal (fade = 1).
            var lon_capacity: float = wheel_info["normal_force"] * config.tire_D * grip_mult \
                * float(surface_factors["longitudinal"]) * weather_factor * 0.95
            var lon_fraction := absf(lon_force) / maxf(lon_capacity, 1.0)
            var lateral_fade := sqrt(maxf(0.0, 1.0 - clampf(lon_fraction, 0.0, 1.0) * clampf(lon_fraction, 0.0, 1.0)))
            lat_force *= lateral_fade

            # --- Apply lateral force (unchanged torque arm / 0.5 gain) ---
            apply_force(wheel.global_basis.x * lat_force * 0.5, wheel.global_position - global_position)
            # --- Apply longitudinal force at the CONTACT PATCH so the drive
            # acts below the COM (real pitch/squat torque on accel & brake) ---
            apply_force(wheel_forward * lon_force, wheel.contact_point - global_position)
            wheel.apply_longitudinal_force(lon_force)
        else:
            wheel.apply_longitudinal_force(0.0)

        # --- Integrate wheel spin (grounded AND airborne) ---
        # A wheel off the ground loses its ground reaction instantly (tire force
        # contributes nothing), so the drive axle spins it up freely and the slip
        # blows out - when it lands the Pacejka force starts near peak traction,
        # exactly like a real launch or a hop over a crest.
        wheel.step_wheel_spin(
            delta,
            drive_axle_torque,
            brake_torque,
            lon_force,
            wheel_forward_speed,
            wheel_info["is_grounded"],
            TireModel.calculate_longitudinal_stiffness(
                slip_ratio,
                wheel_info["normal_force"], config, grip_mult,
                float(surface_factors["longitudinal"]) * weather_factor
            )
        )

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
    _prev_linear_velocity = linear_velocity
    _snap_last_valid()

# --- Public API ---

func set_simulation_enabled(enabled: bool) -> void:
    set_physics_process(enabled)
    if _wheels == null:
        return
    for wheel in _wheels:
        if wheel != null:
            wheel.set_simulation_enabled(enabled)

func is_awaiting_ground() -> bool:
    return _awaiting_ground

func get_speed_kmh() -> float:
    return current_speed_kmh

func get_rpm() -> float:
    return _drivetrain.engine_rpm

func get_gear() -> int:
    return _drivetrain.current_gear

func get_steer_angle() -> float:
    return rad_to_deg(steer_angle)

func get_throttle() -> float:
    return _throttle_input

func get_handbrake() -> bool:
    return _handbrake_input

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
        "throttle": _throttle_input,
        "brake": clampf(_brake_input, 0.0, 1.0),
        "steer": clampf(_steer_input, -1.0, 1.0),
        "surface": _last_surface_key,
    }

## Sets the per-frame surface resolver; empty Callable restores the default
## SurfaceRegistry classifier bound to the local RoadNetwork.
func set_surface_provider(provider: Callable) -> void:
    surface_provider = provider

## Resolves the current surface factors for global_position. One sample per
## frame; no raycast. Returns { lateral, longitudinal, surface_key }.
func resolve_surface_factors() -> Dictionary:
    if surface_provider.is_valid():
        var result: Variant = surface_provider.call(global_position)
        if result is Dictionary and not (result as Dictionary).is_empty():
            var dict := result as Dictionary
            _last_surface_key = dict.get("surface_key", SurfaceRegistry.ASPHALT)
            return {
                "lateral": float(dict.get("lateral", 1.0)),
                "longitudinal": float(dict.get("longitudinal", 1.0)),
                "surface_key": _last_surface_key,
            }
    var asphalt: Dictionary = SurfaceRegistry.SURFACE_GRIP[SurfaceRegistry.ASPHALT] as Dictionary
    _last_surface_key = SurfaceRegistry.ASPHALT
    return {
        "lateral": asphalt["lateral"],
        "longitudinal": asphalt["longitudinal"],
        "surface_key": _last_surface_key,
    }

func get_surface_key() -> String:
    return _last_surface_key

## Pure impact arithmetic: the linear-velocity delta between physics ticks
## expressed as an acceleration (m/s^2). Positive for any change (speed-ups
## included); gated upstream against IMPACT_ACCEL_THRESHOLD so only sharp
## decelerations count as collisions.
static func impact_strength(velocity_before: Vector3, velocity_after: Vector3, delta: float) -> float:
    if delta <= 0.0:
        return 0.0
    return velocity_before.distance_to(velocity_after) / delta

## Threshold gate used by _detect_impact; exposed for pure-headless tests.
static func is_impact_strength(strength: float) -> bool:
    return strength >= IMPACT_ACCEL_THRESHOLD

## Pure analog response curve for the player triggers (this script owns the
## player input seam). Maps raw x in [0,1] to a curved output: x=0 -> 0, x=1 ->
## 1, monotonic non-decreasing, below the diagonal for power > 1.0 so the low
## end is finer. Input at or below `deadzone` reads as fully off so a resting
## trigger cannot creep. Keyboard keys read exactly 0.0/1.0 and both endpoints
## are fixed points, so digital key input is untouched by construction.
## Deterministic and dimensionless (no timestep). power 1.0 + deadzone 0.0
## returns x unchanged - byte-identical to the pre-curve linear read.
static func apply_analog_response(value: float, power: float = ANALOG_RESPONSE_POWER, deadzone: float = ANALOG_RESPONSE_DEADZONE) -> float:
    if value <= 0.0:
        return 0.0
    var x := clampf(value, 0.0, 1.0)
    if x <= deadzone:
        return 0.0
    if power == 1.0:
        return x
    return pow(x, power)

## Arcade speed limiter: rescales a velocity whose signed forward component ran
## past top_speed (m/s) or the reverse cap (m/s) back onto the bound while
## keeping its direction. Pure and headless-safe; wired into _physics_process
## when handling_mode == "arcade" so HUD speed, drift and wheels all agree.
static func clamp_arcade_speed(velocity: Vector3, forward: Vector3, top_speed: float, reverse_cap: float) -> Vector3:
    if top_speed <= 0.0 or reverse_cap <= 0.0:
        return velocity
    var signed_speed := velocity.dot(forward)
    if signed_speed > top_speed:
        return velocity * (top_speed / signed_speed)
    if signed_speed < -reverse_cap:
        return velocity * (-reverse_cap / signed_speed)
    return velocity

## Drift state for the FX smoke emitter: needs speed plus either a handbrake
## slide or committed steer with real wheel slip. No SceneTree dependency and
## cheap enough to poll per frame.
func is_drifting() -> bool:
    if current_speed_kmh < DRIFT_MIN_SPEED_KMH:
        return false
    if _handbrake_input:
        return true
    return absf(_steer_input) >= DRIFT_STEER_FRACTION and _last_lateral_slip_deg >= DRIFT_MIN_SLIP_DEG

## Rising-edge impact gate: a sustained pin against an obstacle stays above
## the threshold for many ticks but emits exactly ONE impact per collision
## spike; the edge re-arms once the delta drops back below the threshold.
func _detect_impact(delta: float) -> void:
    var strength := impact_strength(_prev_linear_velocity, linear_velocity, delta)
    if strength >= IMPACT_ACCEL_THRESHOLD:
        if not _impact_active:
            _impact_active = true
            impact.emit(strength)
            GameState.session_stats.note_impact()
    else:
        _impact_active = false

func set_handling_mode(mode: String) -> void:
    if mode in ["arcade", "simulation"]:
        handling_mode = mode

func reset_car() -> void:
    linear_velocity = Vector3.ZERO
    angular_velocity = Vector3.ZERO
    _prev_linear_velocity = Vector3.ZERO
    _drivetrain.reset()
    global_position.y += 1.0  # lift slightly above ground

func respawn_at(pos: Vector3) -> void:
    linear_velocity = Vector3.ZERO
    angular_velocity = Vector3.ZERO
    _prev_linear_velocity = Vector3.ZERO
    _drivetrain.reset()
    # Teleport through the physics server so Jolt accepts the new transform
    # as authoritative instead of fighting the direct setter mid-step.
    # Keep the car yaw but level out any roll/pitch so we never respawn
    # on our roof after tumbling through the void.
    var yaw := global_basis.get_euler().y
    var tfm := Transform3D(Basis(Vector3.UP, yaw), pos + Vector3.UP * 1.0)
    sleeping = false
    PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, tfm)
    _last_valid_position = tfm.origin
    _last_valid_basis = tfm.basis
    _last_valid_velocity = Vector3.ZERO
    _last_valid_angular_velocity = Vector3.ZERO

func _snap_last_valid() -> void:
    if not is_inside_tree():
        return
    _last_valid_position = global_position
    _last_valid_basis = global_basis
    _last_valid_velocity = linear_velocity
    _last_valid_angular_velocity = angular_velocity

func _restore_last_valid() -> void:
    linear_velocity = _last_valid_velocity
    angular_velocity = _last_valid_angular_velocity
    _prev_linear_velocity = _last_valid_velocity
    current_speed_kmh = _last_valid_velocity.length() * 3.6
    _drivetrain.reset()
    var tfm := Transform3D(_last_valid_basis, _last_valid_position)
    global_transform = tfm
    sleeping = false
    PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, tfm)
