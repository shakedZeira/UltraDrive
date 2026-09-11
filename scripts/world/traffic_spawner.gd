# scripts/world/traffic_spawner.gd
class_name TrafficSpawner
extends Node

## Spawns and manages traffic vehicles that follow roads.

@export var vehicle_scene: PackedScene
@export var max_traffic: int = 15
@export var spawn_radius: float = 300.0

var _traffic: Array[VehiclePhysics] = []

func update(player_pos: Vector3) -> void:
    # Remove far traffic
    for vehicle in _traffic.duplicate():
        if vehicle.global_position.distance_to(player_pos) > spawn_radius + 100:
            vehicle.queue_free()
            _traffic.erase(vehicle)

    # Spawn new traffic if under max
    if _traffic.size() < max_traffic:
        _spawn_vehicle(player_pos)

func _spawn_vehicle(player_pos: Vector3) -> void:
    if vehicle_scene == null:
        return
    var offset := Vector3(randf_range(-spawn_radius, spawn_radius), 0, randf_range(-spawn_radius, spawn_radius))
    var spawn_pos := player_pos + offset
    var vehicle := vehicle_scene.instantiate() as VehiclePhysics
    vehicle.global_position = spawn_pos
    add_child(vehicle)
    _traffic.append(vehicle)
