# scripts/world/traffic_spawner.gd
class_name TrafficSpawner
extends Node

## Spawns and manages traffic vehicles that follow roads.

@export var vehicle_scene: PackedScene
@export var max_traffic: int = 15
@export var spawn_radius: float = 300.0
@export var road_network: RoadNetwork

var _traffic: Array[VehiclePhysics] = []

func update(player_pos: Vector3) -> void:
    # Remove far traffic
    for vehicle in _traffic.duplicate():
        if vehicle.global_position.distance_to(player_pos) > spawn_radius + 100:
            vehicle.queue_free()
            _traffic.erase(vehicle)

    # Distance-cull engine audio so distant cars don't each run a full
    # multi-bed loop (see CarAudio.TRAFFIC_AUDIO_RANGE).
    for vehicle in _traffic:
        var audio := vehicle.get_node_or_null("CarAudio") as CarAudio
        if audio != null:
            audio.cull_by_distance(player_pos, CarAudio.TRAFFIC_AUDIO_RANGE)

    # Spawn new traffic if under max
    if _traffic.size() < max_traffic:
        _spawn_vehicle(player_pos)

func _spawn_vehicle(player_pos: Vector3) -> void:
    if vehicle_scene == null:
        return
    var spawn_pos := player_pos
    if road_network == null:
        spawn_pos = player_pos + _random_offset()
    else:
        var placed := false
        for _attempt in 8:
            var candidate := player_pos + _random_offset()
            if road_network.is_on_road(candidate, 10.0):
                spawn_pos = road_network.get_nearest_road_pos(candidate)
                placed = true
                break
        if not placed:
            return
    var vehicle := vehicle_scene.instantiate() as VehiclePhysics
    vehicle.global_position = spawn_pos
    add_child(vehicle)
    _traffic.append(vehicle)

func _random_offset() -> Vector3:
    return Vector3(
        randf_range(-spawn_radius, spawn_radius),
        0,
        randf_range(-spawn_radius, spawn_radius))