class_name WheelPhysics
extends Node3D

## Simulates a single wheel with raycast suspension.
## Add as child of VehiclePhysics RigidBody3D.

# --- Configuration ---
@export var wheel_position: Vector3 = Vector3(0.0, -0.3, 0.5)  # local offset from car body

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

        normal_force = maxf(spring_force + damper_force, 0.0)
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

func get_speed_along_heading(car_velocity: Vector3) -> float:
    ## Returns the component of car velocity along the wheel's forward direction.
    return global_basis.z.dot(car_velocity)
