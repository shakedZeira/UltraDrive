class_name WheelPhysics
extends Node3D

## Simulates a single wheel with raycast suspension.
## Add as child of VehiclePhysics RigidBody3D.

# --- Configuration ---
@export var wheel_position: Vector3 = Vector3(0.0, -0.3, 0.5)  # local offset from car body

# --- Wheel-spin constants ---
## Tire radius (m). Shared by the slip-ratio math, the drivetrain gear/RPM
## conversion and the drive-axis torque arm, so a freely integrating wheel
## settles at the same rolling match the rest of the car derives from.
const WHEEL_RADIUS := 0.33
## Effective polar moment of inertia (kg*m^2) at the wheel axle. The raw wheel
## carries only ~1 kg*m^2; the rest folds engine/gearbox/axle inertia through
## the drivetrain ratio, which is what makes the real thing feel "heavy" and
## hold a committed spin. Kept moderate so a grip-exceeding launch still spins
## the driven axle up in a couple of frames instead of a slow float.
const WHEEL_SPIN_INERTIA := 3.5
## Body speed (m/s) below which a braking wheel is treated as an ABS-style
## static hold: instead of letting the brake build reverse slip against a
## STOPPED car, the hold pins the wheel to its rolling match so a car resting
## on the pedal never creeps or slides at zero road speed.
const PARKED_HOLD_SPEED := 0.25
## Max angular rate (rad/s^2) at which the parked-hold may unwind an already
## spinning wheel down to the rolling match.
const PARKED_HOLD_SPIN_RATE := 80.0

# --- State ---
var suspension_length: float = 0.1
var normal_force: float = 0.0
var contact_point: Vector3 = Vector3.ZERO
var is_in_contact: bool = false
var wheel_angular_velocity: float = 0.0  # rad/s
var lateral_force: float = 0.0
var longitudinal_force: float = 0.0

# --- Internal ---
var _raycast: RayCast3D
var _prev_suspension_length: float = 0.1

func _ready() -> void:
    _raycast = RayCast3D.new()
    _raycast.target_position = Vector3(0, -suspension_travel_max, 0)
    _raycast.enabled = true
    add_child(_raycast)

const suspension_travel_max := 0.5  # total raycast length for ground detection

func process_wheel(delta: float, config: CarConfig, handbrake: bool) -> Dictionary:
    ## Main wheel update. Call every physics frame.
    ## Returns: { normal_force, lateral_force, longitudinal_force, is_grounded }

    _prev_suspension_length = suspension_length

    # --- Raycast to detect ground ---
    _raycast.force_raycast_update()
    is_in_contact = _raycast.is_colliding()

    if is_in_contact:
        contact_point = _raycast.get_collision_point()
        suspension_length = (global_position - contact_point).length()

        # Clamp to max travel
        suspension_length = clampf(suspension_length, 0.0, config.suspension_travel)

        # --- Spring-Damper Suspension ---
        var spring_compression := config.suspension_travel - suspension_length
        var spring_force := config.spring_rate * spring_compression

        # Damper (velocity-dependent)
        var suspension_velocity := (_prev_suspension_length - suspension_length) / delta
        var damper_force := config.damper_compression * maxf(suspension_velocity, 0.0) \
                          + config.damper_rebound * minf(suspension_velocity, 0.0)

        normal_force = maxf(spring_force + damper_force, config.mass_kg * 9.8 / 4.0)
    else:
        normal_force = 0.0
        suspension_length = config.suspension_travel

    return {
        "normal_force": normal_force,
        "lateral_force": lateral_force,
        "longitudinal_force": longitudinal_force,
        "is_grounded": is_in_contact,
    }

func apply_lateral_force(force: float) -> void:
    lateral_force = force

func apply_longitudinal_force(force: float) -> void:
    longitudinal_force = force

func step_wheel_spin(
    delta: float,
    drive_axle_torque: float,
    brake_torque: float,
    tire_force: float,
    forward_speed: float,
    grounded: bool,
    tire_stiffness: float
) -> float:
    ## Integrates wheel_angular_velocity (rad/s) from the axle torques minus the
    ## tire's ground reaction (tire_force * radius). Call AFTER the tire force
    ## for the frame has been computed so the reaction belongs to this step; the
    ## slip fed to that force used the PREVIOUS frame's spin - matching how a
    ## real chassis integrates (prev wheel speed -> slip -> force -> new spin).
    ## Returns the NEW wheel_angular_velocity so the value can be folded into
    ## pure unit tests without mutating a scene node.
    ##
    ## Positive torque spins the wheel forward (top of the tire rolling toward
    ## the nose). drive_axle_torque is signed (negative in reverse); brake_torque
    ## uses the same signed convention (reverse flips it via gear_dir) so braking
    ## always opposes the direction of travel, not the spin.
    ##
    ## ABS-style static hold: with the car AT REST, brake at the pedal and the
    ## wheel grounded, the axle is pinned to the rolling match (forward_speed /
    ## radius) and the torque integration is skipped entirely - otherwise a full
    ## brake torque would free-wheel the wheel backward against a stopped road
    ## and build reverse slip the tire cannot answer. Pins only when actually
    ## braked (|brake| > 1 N*m) and only hard enough to unwind residual spin,
    ## so damage/creep and driver brake-feather at standstill are both covered.

    var parked := grounded and absf(brake_torque) > 1.0 and absf(forward_speed) <= PARKED_HOLD_SPEED
    if parked:
        wheel_angular_velocity = move_toward(
            wheel_angular_velocity,
            forward_speed / WHEEL_RADIUS,
            PARKED_HOLD_SPIN_RATE * delta
        )
        return wheel_angular_velocity

    var net_torque := drive_axle_torque - brake_torque - tire_force * WHEEL_RADIUS

    # Slip-ratio denominator seen by the tire (how fast slip changes per rad/s
    # of spin). Floor at 1 rad/s so a standstill launch gets a finite, honest
    # damped response instead of a divide-by-zero blowup.
    var slip_denominator := maxf(absf(forward_speed) / WHEEL_RADIUS, 1.0)
    var stiffness_factor := tire_stiffness * WHEEL_RADIUS / (WHEEL_SPIN_INERTIA * slip_denominator)
    # Semi-implicit factor capped into (0, 1]: a large positive slope (stiff
    # tire near pure rolling) damps the next-step reaction hard, while the
    # NEGATIVE slope past the grip peak falls back to the plain explicit
    # update - that region is naturally spin-away and the naive 1/(1-k)
    # continuation would blow up sign-flipping frames. Never exceeds 1, so the
    # integrator can only shrink (or pass through) each step's torque change.
    var kd := clampf(stiffness_factor * delta, -0.9, 2000.0)
    var damping := clampf(1.0 / (1.0 + kd), 0.0, 1.0)

    wheel_angular_velocity += net_torque * delta / WHEEL_SPIN_INERTIA * damping
    return wheel_angular_velocity

func get_speed_along_heading(car_velocity: Vector3) -> float:
    ## Returns the component of car velocity along the wheel's forward direction.
    return global_basis.z.dot(car_velocity)
