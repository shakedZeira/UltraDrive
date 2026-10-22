# scripts/world/road_network.gd
class_name RoadNetwork
extends Node

## Manages all roads in the open world.
## Roads are TrackBuilders placed in the world; their RoadDefs feed the
## RoadGraph topology (adjacency, junctions, routing).

const LINK_THRESHOLD := 15.0

## Uniform-grid cell size (m) of the nearest-road acceleration index. Small
## enough that a cell holds a handful of segments even on the densest circuit
## (Le Mans: 4,800 points at 2.84 m spacing -> ~11 segments per 32 m cell), so a
## query only projects the segments in its own cell (and its neighbours when the
## query sits near a cell edge) instead of the whole network. See
## `nearest_road_lookup`.
const NEAREST_CELL_M := 32.0

var _roads: Array[Array] = []  # each: Array[Vector3] of spline points
var _road_defs: Array[RoadDef] = []
var _builders: Array[TrackBuilder] = []
var _topology: Dictionary = {}
var _topology_dirty := true
var _closed_tiers: Dictionary = {}  # tier -> true while seasonally closed

## Nearest-road acceleration index: { Vector2i cell -> PackedInt32Array } where
## each packed value encodes one segment as `road_index * _near_stride + seg`.
## A segment is registered in EVERY cell its XZ AABB touches (conservative, so a
## long sparse segment is found from any cell it spans). `seg` is the forward
## segment index j in [0, count-2]; a closed road's wrap segment uses
## `count-1`; a single-point road uses 0. Rebuilt lazily on the first lookup
## after any `add_road_def`. Exact: the ring search below reproduces
## `nearest_road_lookup`'s original (road index, then segment) tie-break, so a
## grid answer is bit-identical to the old full-network scan.
var _near_index: Dictionary = {}
var _near_min := Vector2i.ZERO
var _near_max := Vector2i.ZERO
var _near_stride := 1
var _near_dirty := true
var _near_scratch := PackedInt32Array()

func _ready() -> void:
    # Lets minimaps/maps find the road source without knowing the scene layout.
    add_to_group("road_network")
    if not _road_defs.is_empty():
        recompute_rails()

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
    _builders.append(builder)
    _road_defs.append(def)
    _roads.append(def.points)
    _topology_dirty = true
    _near_dirty = true
    return _road_defs.size() - 1

func get_road_defs() -> Array[RoadDef]:
    return _road_defs.duplicate()

## The RoadDef at `index` (the id nearest_road_lookup returns), null when out of
## range. No array copy, unlike get_road_defs().
func get_road_def(index: int) -> RoadDef:
    if index < 0 or index >= _road_defs.size():
        return null
    return _road_defs[index]

## Widest carriageway in the network (0 when empty): the bound a clearance
## query needs so a bounded nearest_road_lookup never misses a road it cares about.
func max_road_width() -> float:
    var widest := 0.0
    for def: RoadDef in _road_defs:
        widest = maxf(widest, def.width)
    return widest

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

func recompute_rails() -> void:
    if _road_defs.is_empty():
        return
    _ensure_topology()
    var junctions: Array = _topology["junctions"]
    for road_id in _road_defs.size():
        var def := _road_defs[road_id]
        if not def.rails_enabled() or road_id >= _builders.size():
            continue
        var gaps: Array = []
        var pts := _roads[road_id]
        var N := pts.size()
        
        # Simple overlap detection: for each junction, gap the rails of this road
        # where they're close (within merge distance)
        for junction: Dictionary in junctions:
            var road_a := int(junction["road_a"])
            var road_b := int(junction["road_b"])
            if road_a == road_id or road_b == road_id:
                var point: Vector3 = junction["point"]
                var other_id := road_b if road_a == road_id else road_a
                if other_id >= 0 and other_id < _road_defs.size():
                    var other_def := _road_defs[other_id]
                    # Tier table only, NOT the merge veto: a merge-point road has
                    # no rails of its own, but the receiving road's rail still has
                    # to be cleared where the merge lands on it.
                    if RoadDef.has_rails(other_def.tier) and other_id < _builders.size():
                        # Closest point index on THIS road at the junction.
                        var idx_a := _find_closest_point_index(pts, point)

                        # Gap ~14 points (≈168m) of this road's rail around the
                        # junction. The geometry always comes from this road's own
                        # points: a gap built from the OTHER road's coordinates
                        # describes a different arc length, so it would be cut in
                        # the wrong place (and the merge side would keep its
                        # rails). The merge side needs no gap of its own -
                        # RoadDef.rails_enabled() is merge-gated, so the loop above
                        # already skipped it and it has no rail to clear.
                        const MERGE_POINTS := 14
                        var start_idx := (idx_a - MERGE_POINTS) % N
                        if start_idx < 0:
                            start_idx += N
                        gaps.append({"start": pts[start_idx], "end": pts[idx_a]})
        _builders[road_id].configure_rails(gaps)

func _find_closest_point_index(points: Array[Vector3], target: Vector3) -> int:
    var best_idx := 0
    var best_dist := INF
    for i in range(points.size()):
        var dist := points[i].distance_squared_to(target)
        if dist < best_dist:
            best_dist = dist
            best_idx = i
    return best_idx

## XZ-plane distance from `query` to the segment a->b in metres. The query is
## projected onto the segment in 2D and clamped to the endpoints, so a point
## mid-span is measured to the CENTERLINE, not to the nearest sparse polyline
## vertex (the 25 km perimeter highway has ~130 m between its 192 vertices, so a
## vertex distance reports 60+ m for a car driving straight down the middle).
## Y is deliberately ignored: the road surface Y is the terrain's business, and
## a bridge/overpass must still read as ON the road below. Pure, headless-safe.
static func point_to_segment_xz(query: Vector3, a: Vector3, b: Vector3) -> float:
    var ab_x := b.x - a.x
    var ab_z := b.z - a.z
    var px := query.x - a.x
    var pz := query.z - a.z
    var len_sq := ab_x * ab_x + ab_z * ab_z
    if len_sq <= 0.000001:
        return Vector2(px, pz).length()
    var t := clampf((px * ab_x + pz * ab_z) / len_sq, 0.0, 1.0)
    return Vector2(px - ab_x * t, pz - ab_z * t).length()

## Closest point to `query` on the segment a->b in XZ, carrying the segment's
## linearly interpolated Y so the result sits ON the road surface.
static func closest_point_on_segment_xz(query: Vector3, a: Vector3, b: Vector3) -> Vector3:
    var ab_x := b.x - a.x
    var ab_z := b.z - a.z
    var len_sq := ab_x * ab_x + ab_z * ab_z
    var t := 0.0
    if len_sq > 0.000001:
        t = clampf(((query.x - a.x) * ab_x + (query.z - a.z) * ab_z) / len_sq, 0.0, 1.0)
    return Vector3(a.x + ab_x * t, a.y + (b.y - a.y) * t, a.z + ab_z * t)

## Nearest road to `pos`, measured as a true XZ point-to-CENTERLINE distance:
## every polyline segment is projected (including the closing segment of a
## closed ring) and the closest one wins. Distances tie-break to the lowest road
## index, then the earliest segment, exactly like the old vertex walk.
## Returns { "pos": closest centerline point (road Y), "id": road index or -1,
## "distance": XZ metres (INF when the network is empty) }.
##
## The scan is accelerated by a lazily built uniform grid (`_near_index`): only
## the segments registered in the query's cell -- plus expanding Chebyshev rings
## while an unscanned segment could still be closer -- are projected, with the
## SAME ordered tie-break rule the old full-network loop used. The result is
## bit-identical to scanning every segment, but a near-road query (a car, a
## prop) projects a handful of segments instead of the whole network. On the
## 4,800-point Le Mans loop a full scan cost ~3.2 ms per call and runs once per
## car per physics frame; the grid takes that to well under 0.1 ms.
##
## `max_dist` bounds the ring search: once every unscanned cell is at least
## `max_dist` away the search stops, so a road closer than `max_dist` is always
## found exactly, while a far-from-road query (open countryside) costs a few
## rings instead of walking the whole grid. With a finite bound, a returned
## distance >= max_dist only means "nothing closer than max_dist".
func nearest_road_lookup(pos: Vector3, max_dist: float = INF) -> Dictionary:
    var best_pos := pos
    var best_id := -1
    var best_seg := -1
    var best_dist := INF
    _ensure_near_index()
    if _near_index.is_empty():
        # No roads at all, or only empty ones: the original loop also found
        # nothing to project.
        return {"pos": best_pos, "id": best_id, "distance": best_dist}

    var q := Vector2(pos.x, pos.z)
    var base := _near_cell_of(q)
    var max_ring := maxi(
        maxi(_near_max.x - base.x, base.x - _near_min.x),
        maxi(_near_max.y - base.y, base.y - _near_min.y)) + 1
    var ring := 0
    while ring <= max_ring:
        _near_gather_ring(base, ring)
        for encoded: int in _near_scratch:
            var i := encoded / _near_stride
            var j := encoded - i * _near_stride
            var road: Array = _roads[i]
            var count := road.size()
            var a: Vector3
            var b: Vector3
            if j >= count - 1:
                # Wrap segment (closed ring) or the lone point of a 1-point road.
                a = road[count - 1]
                b = road[0]
            else:
                a = road[j]
                b = road[j + 1]
            var d := point_to_segment_xz(pos, a, b)
            # Same ordered rule as the old loop: strict improvement, or an exact
            # tie on a (lower road index, then earlier segment) candidate.
            if d < best_dist or (d == best_dist and (i < best_id or (i == best_id and j < best_seg))):
                best_dist = d
                best_id = i
                best_seg = j
                best_pos = a if a == b else closest_point_on_segment_xz(pos, a, b)
        # Every unscanned cell lies outside the square we have covered; nothing
        # there can beat `best_dist` once it is no further than the square edge.
        var inner := _near_ring_inner_dist(q, base, ring)
        if best_dist <= inner or inner >= max_dist:
            break
        ring += 1
    # "seg" = the nearest segment's index j (the one starting at point j; a
    # closed road's wrap segment is count-1): SurfaceRegistry reads a mixed
    # road's per-segment surface (RoadDef.point_surfaces) with it.
    return {"pos": best_pos, "id": best_id, "distance": best_dist, "seg": best_seg}

## Builds `_near_index` from `_roads` if it is stale. Cheap and one-shot: the
## circuit/open-world road set is static once the scene has bootstrapped.
func _ensure_near_index() -> void:
    if not _near_dirty:
        return
    _near_dirty = false
    _near_index.clear()
    if _roads.is_empty():
        return
    var lo := Vector2(INF, INF)
    var hi := Vector2(-INF, -INF)
    var any := false
    var max_count := 0
    for road: Array in _roads:
        max_count = maxi(max_count, road.size())
        for p: Vector3 in road:
            lo.x = minf(lo.x, p.x)
            lo.y = minf(lo.y, p.z)
            hi.x = maxf(hi.x, p.x)
            hi.y = maxf(hi.y, p.z)
            any = true
    if not any:
        return
    _near_stride = max_count + 1
    _near_min = Vector2i(floori(lo.x / NEAREST_CELL_M), floori(lo.y / NEAREST_CELL_M)) - Vector2i.ONE
    _near_max = Vector2i(floori(hi.x / NEAREST_CELL_M), floori(hi.y / NEAREST_CELL_M)) + Vector2i.ONE
    for i in _roads.size():
        var road: Array = _roads[i]
        var count := road.size()
        if count <= 0:
            continue
        if count == 1:
            _near_add_segment(i, 0, road[0], road[0])
            continue
        for j in range(count - 1):
            _near_add_segment(i, j, road[j], road[j + 1])
        if _road_is_closed(i) and count > 2:
            _near_add_segment(i, count - 1, road[count - 1], road[0])

func _near_add_segment(road_index: int, seg: int, a: Vector3, b: Vector3) -> void:
    var encoded := road_index * _near_stride + seg
    var lo := _near_cell_of(Vector2(minf(a.x, b.x), minf(a.z, b.z)))
    var hi := _near_cell_of(Vector2(maxf(a.x, b.x), maxf(a.z, b.z)))
    lo.x = maxi(lo.x, _near_min.x)
    lo.y = maxi(lo.y, _near_min.y)
    hi.x = mini(hi.x, _near_max.x)
    hi.y = mini(hi.y, _near_max.y)
    for cy in range(lo.y, hi.y + 1):
        for cx in range(lo.x, hi.x + 1):
            var key := Vector2i(cx, cy)
            var bucket: PackedInt32Array = _near_index.get(key, PackedInt32Array())
            bucket.append(encoded)
            _near_index[key] = bucket

func _near_cell_of(p: Vector2) -> Vector2i:
    return Vector2i(floori(p.x / NEAREST_CELL_M), floori(p.y / NEAREST_CELL_M))

## Appends the encoded segments of every cell on Chebyshev ring `k` around
## `base`, clipped to the grid bounds, into `_near_scratch`. Ring 0 is just the
## base cell; each outer ring is the square perimeter at that radius, so cells
## are never visited twice across rings.
func _near_gather_ring(base: Vector2i, k: int) -> void:
    _near_scratch.resize(0)
    if k == 0:
        _near_gather_cell(base)
        return
    var min_x := base.x - k
    var max_x := base.x + k
    var min_y := base.y - k
    var max_y := base.y + k
    if max_x < _near_min.x or min_x > _near_max.x or max_y < _near_min.y or min_y > _near_max.y:
        return
    var x0 := maxi(min_x, _near_min.x)
    var x1 := mini(max_x, _near_max.x)
    var y0 := maxi(min_y, _near_min.y)
    var y1 := mini(max_y, _near_max.y)
    # Top and bottom rows of the ring (full width).
    for cx in range(x0, x1 + 1):
        _near_gather_cell(Vector2i(cx, y0))
        if y1 != y0:
            _near_gather_cell(Vector2i(cx, y1))
    # Left and right columns of the ring (interior rows only; corners already
    # covered by the row pass).
    for cy in range(y0 + 1, y1):
        _near_gather_cell(Vector2i(x0, cy))
        if x1 != x0:
            _near_gather_cell(Vector2i(x1, cy))

func _near_gather_cell(key: Vector2i) -> void:
    if _near_index.has(key):
        _near_scratch.append_array(_near_index[key] as PackedInt32Array)

## Lower bound (m) on the distance from `q` to any cell NOT yet scanned when the
## covered square spans Chebyshev radius `k` around `base`. `q` always lies
## inside its own base cell, so this is the distance to the nearest edge of the
## covered square -- 0 would mean the square has no interior margin left and the
## search must expand.
func _near_ring_inner_dist(q: Vector2, base: Vector2i, k: int) -> float:
    var x_min := float(base.x - k) * NEAREST_CELL_M
    var x_max := float(base.x + k + 1) * NEAREST_CELL_M
    var y_min := float(base.y - k) * NEAREST_CELL_M
    var y_max := float(base.y + k + 1) * NEAREST_CELL_M
    return minf(
        minf(q.x - x_min, x_max - q.x),
        minf(q.y - y_min, y_max - q.y))

## XZ metres from `pos` to the nearest road centerline (INF when empty).
func nearest_road_distance(pos: Vector3) -> float:
    return float(nearest_road_lookup(pos)["distance"])

func nearest_road_id(pos: Vector3) -> int:
    return int(nearest_road_lookup(pos)["id"])

## Whether road `index` closes back on its first point (the extra segment the
## lookup, the props and the graph all walk). False without a RoadDef.
func _road_is_closed(index: int) -> bool:
    if index < 0 or index >= _road_defs.size():
        return false
    return _road_defs[index].closed

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
    var lookup := nearest_road_lookup(pos)
    var nearest: Vector3 = lookup["pos"]
    return nearest

## XZ centerline distance test (see nearest_road_lookup): the same number the
## surface classifier sees, so dressing/props/grip agree on what "on the road"
## means. An empty network is never on the road (INF).
func is_on_road(pos: Vector3, threshold: float = 6.0) -> bool:
    return float(nearest_road_lookup(pos)["distance"]) < threshold