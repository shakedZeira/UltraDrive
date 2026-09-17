# scripts/world/road_network.gd
class_name RoadNetwork
extends Node

## Manages all roads in the open world.
## Roads are TrackBuilders placed in the world; their RoadDefs feed the
## RoadGraph topology (adjacency, junctions, routing).

const LINK_THRESHOLD := 15.0

var _roads: Array[Array] = []  # each: Array[Vector3] of spline points
var _road_defs: Array[RoadDef] = []
var _topology: Dictionary = {}
var _topology_dirty := true

func _ready() -> void:
    # Lets minimaps/maps find the road source without knowing the scene layout.
    add_to_group("road_network")

## Legacy convenience shim: wraps the old signature into an ARTERIAL RoadDef.
func add_road(points: Array[Vector3], width: float = 8.0, closed: bool = true) -> int:
    var def := RoadDef.make(RoadDef.Tier.ARTERIAL, points, "", closed, width, -1)
    return add_road_def(def)

func add_road_def(def: RoadDef) -> int:
    if def.id.is_empty():
        def.id = "road_%d" % _road_defs.size()
    var builder := TrackBuilder.new()
    builder.road_width = def.width
    builder.build_track(def.points, def.closed, def)
    add_child(builder)
    _road_defs.append(def)
    _roads.append(def.points)
    _topology_dirty = true
    return _road_defs.size() - 1

func get_road_defs() -> Array[RoadDef]:
    return _road_defs.duplicate()

func _ensure_topology() -> void:
    if not _topology_dirty:
        return
    if _road_defs.is_empty():
        _topology = {"adjacency": {}, "junctions": []}
    else:
        _topology = RoadGraph.build_topology(_road_defs, LINK_THRESHOLD)
    _topology_dirty = false

func get_adjacency() -> Dictionary:
    _ensure_topology()
    var adj: Dictionary = _topology["adjacency"]
    return adj

func get_junctions() -> Array:
    _ensure_topology()
    var junctions: Array = _topology["junctions"]
    return junctions

func nearest_road_id(pos: Vector3) -> int:
    var best_id := -1
    var best_dist := INF
    for i in _roads.size():
        var road := _roads[i]
        for point in road:
            var d: float = point.distance_to(pos)
            if d < best_dist:
                best_dist = d
                best_id = i
    return best_id

func neighbor_roads(road_id: int) -> PackedInt32Array:
    _ensure_topology()
    var adj: Dictionary = _topology["adjacency"]
    if adj.has(road_id):
        return adj[road_id]
    return PackedInt32Array()

func route(from_id: int, to_id: int) -> PackedInt32Array:
    _ensure_topology()
    var adj: Dictionary = _topology["adjacency"]
    return RoadGraph.route(adj, from_id, to_id)

func get_roads() -> Array[Array]:
    return _roads

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