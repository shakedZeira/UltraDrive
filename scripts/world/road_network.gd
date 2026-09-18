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
var _closed_tiers: Dictionary = {}  # tier -> true while seasonally closed

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
    var adj := _routing_adjacency()
    if adj.has(road_id):
        return adj[road_id]
    return PackedInt32Array()

func route(from_id: int, to_id: int) -> PackedInt32Array:
    return RoadGraph.route(_routing_adjacency(), from_id, to_id)

## Adjacency filtered by seasonal tier closures. When no tiers are closed this
## is a plain reference to the cached topology (no allocation); otherwise a
## copy is built with closed roads pruned from both keys and neighbor lists so
## routing and neighbor queries honor the closure without mutating RoadGraph.
func _routing_adjacency() -> Dictionary:
    _ensure_topology()
    if _closed_tiers.is_empty():
        return _topology["adjacency"]
    var filtered := {}
    var adj: Dictionary = _topology["adjacency"]
    for road_id: int in adj:
        if _road_tier_closed(road_id):
            continue
        var kept := PackedInt32Array()
        for neighbor in adj[road_id]:
            if not _road_tier_closed(neighbor):
                kept.append(neighbor)
        filtered[road_id] = kept
    return filtered

func _road_tier_closed(road_id: int) -> bool:
    if road_id < 0 or road_id >= _road_defs.size():
        return false
    return _closed_tiers.has(_road_defs[road_id].tier)

## Closes every road of the given tiers (RoadDef.Tier ids) for routing.
func set_closed_tiers(tiers: Array[int]) -> void:
    _closed_tiers.clear()
    for tier in tiers:
        _closed_tiers[tier] = true

func get_closed_tiers() -> Array[int]:
    var out: Array[int] = []
    for tier: int in _closed_tiers:
        out.append(tier)
    return out

func clear_seasonal_closures() -> void:
    _closed_tiers.clear()

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