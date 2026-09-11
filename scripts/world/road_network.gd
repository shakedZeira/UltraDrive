# scripts/world/road_network.gd
class_name RoadNetwork
extends Node

## Manages all roads in the open world.
## Roads are simply TrackBuilders placed in the world.

var _roads: Array[Array] = []  # each: Array[Vector3] of spline points

func add_road(points: Array[Vector3], width: float = 8.0) -> void:
    var builder := TrackBuilder.new()
    builder.road_width = width
    builder.build_track(points)
    add_child(builder)
    _roads.append(points)

func get_nearest_road_pos(pos: Vector3) -> Vector3:
    var best := pos
    var best_dist := INF
    for road in _roads:
        for point in road:
            var d: float = point.distance_to(pos)
            if d < best_dist:
                best_dist = d
                best = point
    return best

func is_on_road(pos: Vector3, threshold: float = 6.0) -> bool:
    return pos.distance_to(get_nearest_road_pos(pos)) < threshold
