# scripts/ai/ai_controller.gd
class_name AIController
extends Node

## Drives a VehiclePhysics car along waypoints.
## Attach as sibling of VehiclePhysics.

@onready var car: VehiclePhysics = get_parent() as VehiclePhysics

var waypoints: Array[Vector3] = []
var _current_target: int = 0
var _speed_multiplier: float = 1.0

func _physics_process(delta: float) -> void:
    if car == null or waypoints.size() < 2:
        return

    # --- Follow waypoints ---
    var target := waypoints[_current_target]
    var to_target := target - car.global_position
    to_target.y = 0

    # Find direction to target relative to car
    var car_forward := -car.global_basis.z
    var steer_input := -car_forward.cross(to_target).y

    # Throttle: full unless close to target or turning hard
    var throttle := 1.0
    var turning_fraction := clampf(absf(steer_input), 0.0, 1.0)
    throttle *= (1.0 - turning_fraction * 0.7)

    # Brake when cornering hard
    var braking := 0.0
    if turning_fraction > 0.6:
        braking = turning_fraction - 0.6

    # --- Waypoint progression ---
    if to_target.length() < 8.0:
        _current_target = (_current_target + 1) % waypoints.size()

    # --- Rubber-banding via speed multiplier ---
    _apply_control(steer_input, throttle, braking, delta)

func _apply_control(steer: float, throttle: float, braking: float, delta: float) -> void:
    # Throttle/brake are scaled by rubber-banding multiplier
    var adj_throttle := throttle * _speed_multiplier
    _simulate_input(steer, adj_throttle, braking)

func _simulate_input(steer: float, throttle: float, braking: float) -> void:
    ## Drives the car by re-routing input through the physics controller.
    ## This bypasses InputManager (which is player-only).
    ## (Placeholder — Phase 6 will refactor VehiclePhysics to accept external input.)
    car.set_input_override(Vector2(steer, throttle - braking))

func set_waypoints(points: Array[Vector3]) -> void:
    waypoints = points.duplicate()
    _current_target = 0

func set_speed_multiplier(mult: float) -> void:
    _speed_multiplier = clampf(mult, 0.5, 1.5)
