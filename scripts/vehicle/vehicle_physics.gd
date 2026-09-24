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

# --- High-speed stability (aero downforce + yaw assist) ---
## Air density (kg/m^3); mirrors the 1.225 the drag term inlines so the aero
## downforce formula reads the same physics.
const AIR_DENSITY := 1.225
## Fraction of the aero downforce applied per wheel (even split keeps the
## front/rear balance neutral so cornering character is unchanged, only the
## grip envelope grows).
const AERO_WHEEL_SPLIT := 4.0
## Yaw assist ramps in above this speed (km/h). Below it the arcade low-speed
## drift feel is byte-for-byte untouched.
const COUNTERSTEER_RAMP_START_KMH := 70.0
## Speed (km/h) at which the yaw assist reaches full strength.
const COUNTERSTEER_RAMP_END_KMH := 140.0

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

## Legacy steering falloff curve: full lock at standstill falling to 30% of the
## config max (the floor) at/above STEER_FALLOFF_SPEED_KMH. Preserved exactly
## above the low-speed taper so high-speed steer amount is unchanged.
const STEER_FALLOFF_SPEED_KMH := 200.0
const STEER_FALLOFF_FLOOR := 0.7

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
    # Speed-sensitive lock: the low-speed arcade boost lifts the steer lock at
    # parking speeds for a tighter turning radius, then blends onto the legacy
    # falloff so high-speed steer amount (and stability) is unchanged.
    var target_steer := deg_to_rad(steer_lock_deg(current_speed_kmh, config)) * steer_input
    steer_angle = move_toward(steer_angle, target_steer, config.steer_speed * delta)

    wheel_fl.rotation.y = steer_angle
    wheel_fr.rotation.y = steer_angle

    # --- Drivetrain ---
    var forward_speed := -global_basis.z.dot(linear_velocity)
    _drivetrain.set_wheel_speed(forward_speed)
    var axle_speed := 0.0
    if _wheels.size() >= 3:
        axle_speed = (_wheels[2].wheel_angular_velocity + _wheels[3].wheel_angular_velocity) \
            * 0.5 * WheelPhysics.WHEEL_RADIUS
    _drivetrain.set_axle_speed(axle_speed)
    _drivetrain.set_lateral_g(lateral_g_for_shift_veto(angular_velocity.y, forward_speed))
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

    # --- Surface & grip context (resolved BEFORE the high-speed blocks that
    # need the same grip envelope the tires use later in the frame) ---
    var grip_mult: float = config.arcade_mode["grip_multiplier"] if handling_mode == "arcade" else config.simulation_mode["grip_multiplier"]
    var weather_factor := WeatherManager.get_road_grip_factor()
    var surface_factors := resolve_surface_factors()
    var grip_mult_lateral := grip_mult * float(surface_factors["lateral"]) * weather_factor

    # --- High-speed stability ---
    # (a) Aero downforce (v^2): mirrors the drag formula (0.5 * rho * Cl * A *
    # v^2) over the HORIZONTAL speed so `downforce_coefficient` reads as a real
    # lift coefficient. The load is split across the wheels and injected into the
    # Pacejka D term via wheel.aero_normal_load in the loop below (high-speed
    # grip margin), and the SAME force is applied as a chassis push-down. Zero at
    # rest/creep, so the parking-lot and low-speed arcade feel is untouched.
    var horizontal_speed := Vector2(linear_velocity.x, linear_velocity.z).length()
    var aero_load := compute_aero_load(horizontal_speed, config)
    var aero_load_per_wheel := aero_load / AERO_WHEEL_SPLIT

    # (b) Countersteer/stability yaw assist: damps angular_velocity toward the
    # GRIP-LIMITED yaw-rate target. The kinematic rate v*tan(steer)/wheelbase
    # demands far more rotation at speed than the tires can actually sustain
    # (Pacejka saturates), and chasing that unachievable target pushed the body
    # to over-rotate past the grip envelope - the "no stability" feel. The
    # target is now clamped into the achievable envelope mu*g/v, so the assist
    # guides the car up to the cornering yaw its tires CAN hold and only ever
    # damps yaw beyond it (the actual countersteer function). Speed-tapered
    # (ramps in above COUNTERSTEER_RAMP_START_KMH, full by
    # COUNTERSTEER_RAMP_END_KMH), OFF while handbraking, and clamped to the
    # config torque (Nm) so a committed drift is only guided, never fought.
    var yaw_taper := 0.0
    if config.countersteer_assist > 0.0 and not handbrake:
        yaw_taper = yaw_assist_taper(forward_speed, current_speed_kmh)
        if yaw_taper > 0.0:
            var lateral_grip := config.tire_D * grip_mult * float(surface_factors["lateral"]) * weather_factor
            var yaw_target := compute_stability_yaw_target(
                forward_speed, steer_angle, config.wheelbase, lateral_grip
            )
            var yaw_torque := stability_yaw_torque(
                yaw_target, angular_velocity.y, config.countersteer_assist
            )
            apply_torque(Vector3.UP * yaw_torque * yaw_taper)

    # --- Tire Forces ---

    # Process each wheel
    for i in range(4):
        var wheel := _wheels[i]
        wheel.aero_normal_load = aero_load_per_wheel
        var wheel_info := wheel.process_wheel(delta, config, handbrake)

        # --- Per-wheel axle torque ---
        # Drive torque flows through the existing Drivetrain (gear/ratio math)
        # unchanged, split across the driven axle. Brake torque opposes the
        # direction of TRAVEL (sign via brake_torque_for), so braking always
        # slows the car whether it rolls forward or backward, regardless of the
        # selected gear. Fronts get brake only.
        var drive_axle_torque := 0.0
        if i >= 2:  # rear wheels get drive (RWD for now)
            drive_axle_torque = drive_info["drive_torque"] / 2.0
        var brake_torque := brake_torque_for(
            forward_speed, _drivetrain.current_gear, brake_input, config.max_brake_torque
        )

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

    # --- Air Resistance + aero chassis push-down ---
    # The aero load is injected into the tire D terms above AND applied here as
    # a single central force combined with drag (RigidBody3D.apply_central_force
    # replaces the accumulator in Godot 4, so one call carries both). When
    # aero_load is 0 (stationary, or a car with downforce_coefficient 0.0) this
    # reduces to the exact pre-existing drag behaviour.
    var drag_magnitude := 0.5 * 1.225 * config.drag_coefficient * config.frontal_area * linear_velocity.length_squared()
    var aero_force := Vector3.ZERO
    if linear_velocity.length() > 0.1:
        aero_force = -linear_velocity.normalized() * drag_magnitude
    if aero_load > 0.0:
        aero_force += Vector3.DOWN * aero_load
    if aero_force != Vector3.ZERO:
        apply_central_force(aero_force)

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
        "slip": clampf(_last_lateral_slip_deg / 40.0, 0.0, 1.0),
        "handbrake": _handbrake_input,
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

## Speed-sensitive steer lock (degrees) for the player steering path. The
## legacy 200 km/h falloff curve (full lock at standstill -> 30% of max at
## 140+ km/h) is preserved EXACTLY above `low_speed_steer_taper_kmh`; below it,
## an arcade boost lifts the lock from `max_steer_angle` at the taper to
## `low_speed_steer_angle` at standstill, shrinking the low-speed turning radius
## without touching high-speed steer or stability. Pure and headless-safe.
static func steer_lock_deg(speed_kmh: float, config: CarConfig) -> float:
    var legacy := config.max_steer_angle * (1.0 - clampf(speed_kmh / STEER_FALLOFF_SPEED_KMH, 0.0, STEER_FALLOFF_FLOOR))
    var boost: float = maxf(config.low_speed_steer_angle - config.max_steer_angle, 0.0)
    var taper := 1.0 - clampf(speed_kmh / maxf(config.low_speed_steer_taper_kmh, 1.0), 0.0, 1.0)
    return legacy + boost * taper

## Signed brake torque (N*m) feeding step_wheel_spin's `net_torque = drive -
## brake - tire*R`. The sign opposes the DIRECTION OF TRAVEL so braking always
## decelerates the car whatever gear is selected and whichever way it rolls: a
## positive sign slows forward travel, a negative sign slows backward travel.
## Inside the ABS parked-hold band (|travel| <= PARKED_HOLD_SPEED) the hold
## pins the wheel regardless of sign, so the legacy gear-keyed sign (behind
## the band's) is kept there. Pure and headless-safe.
static func brake_torque_for(travel_speed: float, gear: int, brake_input: float, max_brake_torque: float) -> float:
    if brake_input <= 0.0:
        return 0.0
    var magnitude := brake_input * max_brake_torque
    var sign: float
    if travel_speed > WheelPhysics.PARKED_HOLD_SPEED:
        sign = 1.0
    elif travel_speed < -WheelPhysics.PARKED_HOLD_SPEED:
        sign = -1.0
    else:
        sign = -1.0 if gear < 0 else 1.0
    return sign * magnitude

## Yaw-assist envelope (0..1) for stability_yaw_torque. Forward travel keeps
## the existing 70->140 km/h ramp EXACTLY (arcade low-speed drift feel is
## byte-for-byte untouched); backward travel - which the legacy gate excluded
## entirely - gets full assist so a reverse-roll spin is damped and steerable.
## Reverse speeds are arcade-capped at 25 km/h, so this branch can never
## overlap the high-speed envelope. Zero at exact standstill. Pure and
## headless-safe.
static func yaw_assist_taper(forward_speed: float, speed_kmh: float) -> float:
    if forward_speed > 0.0:
        return clampf(
            (speed_kmh - COUNTERSTEER_RAMP_START_KMH)
            / (COUNTERSTEER_RAMP_END_KMH - COUNTERSTEER_RAMP_START_KMH),
            0.0, 1.0
        )
    if forward_speed < 0.0:
        return 1.0
    return 0.0

## Aero downforce load (N) at the given HORIZONTAL speed (m/s): the textbook
## 0.5 * rho * Cl * A * v^2. Zero at rest/creep so the low-speed arcade feel is
## untouched; quadratic in speed so the high-speed grip margin grows exactly
## where stability is scarce. Mirrors the drag formula so `downforce_coefficient`
## reads as a real lift coefficient. Pure and headless-safe.
static func compute_aero_load(horizontal_speed: float, config: CarConfig) -> float:
    return 0.5 * AIR_DENSITY * config.downforce_coefficient * config.frontal_area \
        * horizontal_speed * horizontal_speed

## Grip-limited peak yaw rate (rad/s) the tires can sustain: the lateral
## acceleration the grip envelope can hold (tire_D * lateral-grip * g) divided
## by forward speed. At speed this is FAR below the kinematic v*tan(steer)/L
## rate, so any yaw demand above it is physically unachievable - and chasing it
## was what over-rotated the car. Floored so a near-stop never divides by zero.
static func max_achievable_yaw_rate(forward_speed: float, lateral_grip: float) -> float:
    return maxf(lateral_grip, 0.0) * 9.8 / maxf(forward_speed, 1.0)

## Lateral acceleration (G) felt by the body: the centripetal yaw_rate * speed,
## normalized by g. A committed corner at speed reads > 1.0 G (feeds
## Drivetrain.lateral_g for the forced-downshift veto); rest and straight-line
## read 0.0. Pure and headless-safe.
static func lateral_g_for_shift_veto(yaw_rate: float, forward_speed: float) -> float:
    return absf(yaw_rate * forward_speed) / 9.8

## Stability-assist yaw target (rad/s): the kinematic ideal v*tan(steer)/L
## clamped into the physically achievable yaw envelope. Below the grip cap it
## is the plain kinematic rate, so mid/low-speed cornering assistance is
## unchanged; above it the demand is flattened so the assist can never push the
## body to rotate faster than its tires can hold.
static func compute_stability_yaw_target(
    forward_speed: float, steer_angle: float, wheelbase: float, lateral_grip: float
) -> float:
    var kinematic := forward_speed * tan(steer_angle) / maxf(wheelbase, 0.5)
    var cap := max_achievable_yaw_rate(forward_speed, lateral_grip)
    return clampf(kinematic, -cap, cap)

## Stability-assist torque (N*m): proportional yaw-rate error toward the
## grip-limited target, clamped to +/- `assist_torque`. While the car rotates
## no faster than the target, the torque guides it UP to the achievable
## cornering yaw (entry assistance); any yaw beyond what the tires can produce
## (a spin) is opposed - which is the actual countersteer function.
static func stability_yaw_torque(yaw_target: float, current_yaw: float, assist_torque: float) -> float:
    return clampf(assist_torque * (yaw_target - current_yaw), -assist_torque, assist_torque)

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
