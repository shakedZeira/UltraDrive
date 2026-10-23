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

## --- Streamed geometry (open world; open_world_status.md section 9) -------
## Off (the default): every add_road_def() builds one TrackBuilder child for the
## whole road, as the circuits (Le Mans, Barcelona RX, Northern Isle) expect.
## On: add_road_def() only registers the RoadDef (topology, nearest-road index,
## maps, discovery and the terrain carve all read the defs, never the meshes);
## the geometry is cut into `stream_cell_size` cells by RoadChunkMesher and the
## cells within `stream_radius` (Chebyshev, in cells) of the position passed to
## sync_player_pos() are built on WorkerThreadPool and added here, cells past
## `stream_keep_radius` are freed. The player's own cell is built synchronously
## when it is missing (spawn, fast travel), so the car never lands on a cell
## without collision. A single far-LOD mesh of the whole network (surface + edge
## colours, no collision, no shadow) keeps roads on the horizon.
@export var stream_geometry := false
@export var stream_cell_size := 256.0
@export var stream_radius := 2
@export var stream_keep_radius := 3
@export var stream_far_lod := true
## Main-thread budget per frame for adding finished cells (at least one cell is
## always added per frame when one is ready).
@export var stream_apply_budget_ms := 2.0
## Whether the painted lines (edge lines, lane dashes) cast shadows.
## TrackBuilder keeps them on; paint 12-14 mm over the carriageway casts
## nothing visible, so the stream turns them off. The carriageway (an overpass
## shades the road under it) and the rails always cast.
@export var stream_flat_shadows := false
const STREAM_MAX_IN_FLIGHT := 2
const STREAM_FREES_PER_FRAME := 2

class _CellJob extends RefCounted:
    var cell: Vector2i
    var tables: Array
    var entries: Array
    var result: Dictionary = {}
    var task_id := -1
    func run() -> void:
        result = RoadChunkMesher.build_cell(tables, entries)

var _stream_rail_gaps: Array = []  # per road: the gaps recompute_rails computed
var _stream_dirty := true
var _stream_tables: Array = []
var _stream_index: Dictionary = {}  # Vector2i cell -> [[road, PackedInt32Array segs], ...]
var _stream_loaded: Dictionary = {}  # Vector2i -> Node3D
var _stream_jobs: Dictionary = {}  # Vector2i -> _CellJob (in flight)
var _stream_ready_jobs: Array = []  # finished _CellJob waiting for the main thread
var _stream_queue: Array[Vector2i] = []
var _stream_free_queue: Array[Node] = []
var _stream_player_cell := Vector2i(-2147483647, -2147483647)
var _stream_has_player := false
var _stream_far: MeshInstance3D = null
var _stream_warm: Node3D = null
var _stream_stats := {
    "applied": 0, "sync_builds": 0, "freed": 0, "dropped": 0,
    "max_apply_ms": 0.0, "max_frame_apply_ms": 0.0, "max_sync_ms": 0.0,
    "max_job_ms": 0.0, "prepare_ms": 0.0, "far_ms": 0.0, "far_tris": 0,
}

func _ready() -> void:
    # Lets minimaps/maps find the road source without knowing the scene layout.
    add_to_group("road_network")
    set_process(stream_geometry)
    if not _road_defs.is_empty():
        recompute_rails()

func _exit_tree() -> void:
    _stream_wait_all()

## Legacy convenience shim: wraps the old signature into an ARTERIAL RoadDef.
func add_road(points: Array[Vector3], width: float = 8.0, closed: bool = true) -> int:
    var def := RoadDef.make(RoadDef.Tier.ARTERIAL, points, "", closed, width, -1)
    return add_road_def(def)

func add_road_def(def: RoadDef) -> int:
    if def.id.is_empty():
        def.id = "road_%d" % _road_defs.size()
    if stream_geometry:
        _stream_rail_gaps.append([])
        _stream_dirty = true
    else:
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
        if not def.rails_enabled() or not _has_geometry(road_id):
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
                    if RoadDef.has_rails(other_def.tier) and _has_geometry(other_id):
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
                        # A merge lane that runs alongside on the FORWARD side of
                        # the junction (higher indices, e.g. the spawn on-ramp,
                        # which travels the ring in decreasing index) gets its gap
                        # there instead, spanning exactly the stretch it runs beside.
                        var ahead := _forward_merge_span(pts, _roads[other_id], idx_a, def.closed,
                            (def.width + other_def.width) * 0.5 + 1.0)
                        if ahead > 0:
                            var end_idx := (idx_a + ahead) % N if def.closed else mini(idx_a + ahead, N - 1)
                            gaps.append({"start": pts[idx_a], "end": pts[end_idx]})
                            continue
                        var start_idx := (idx_a - MERGE_POINTS) % N
                        if start_idx < 0:
                            start_idx += N
                        gaps.append({"start": pts[start_idx], "end": pts[idx_a]})
        if stream_geometry:
            # Same rule as TrackBuilder.configure_rails: an empty list leaves the
            # rails as first built (no gaps, no rail collision).
            if not gaps.is_empty():
                _stream_rail_gaps[road_id] = gaps
                _stream_dirty = true
        else:
            _builders[road_id].configure_rails(gaps)

## How many of THIS road's vertices past `idx_a` (the junction vertex) the other
## road runs alongside, i.e. with its centreline within `band` of this road's
## centreline. Returns 0 unless the other road is alongside ONLY on the forward
## side (no point alongside behind the junction) for at least two segments:
## crossings, T-joins, radial joins and every
## backward merge keep the legacy 14-point backward gap. Only points within
## 800 m of the junction and vertices within +-20 of it are examined.
func _forward_merge_span(pts: Array[Vector3], other: Array[Vector3], idx_a: int, closed: bool, band: float) -> int:
    var n := pts.size()
    if n < 2 or other.is_empty():
        return 0
    const WINDOW := 20
    var junction := pts[idx_a]
    var max_ahead := 0
    var behind := false
    for q in other:
        var r2 := Vector2(q.x - junction.x, q.z - junction.z).length_squared()
        # The landing itself sits on the junction vertex: it has no side.
        if r2 > 640000.0 or r2 < 1.0:
            continue
        var best_d := INF
        var best_k := 0
        for k in range(-WINDOW, WINDOW):
            var ia := idx_a + k
            var ib := ia + 1
            if not closed and (ia < 0 or ib >= n):
                continue
            var a := pts[posmod(ia, n)]
            var b := pts[posmod(ib, n)]
            var d := point_to_segment_xz(q, a, b)
            if d < best_d:
                best_d = d
                # The segment's far end in the direction away from the junction.
                best_k = k + 1 if k >= 0 else k
        if best_d >= band:
            continue
        if best_k > 0:
            max_ahead = maxi(max_ahead, best_k)
        elif best_k < 0:
            behind = true
    # A single segment is a perpendicular join seen from one side, not a lane.
    return 0 if behind or max_ahead < 2 else max_ahead

## Whether road `road_id` has (or will stream) geometry that rails can be cut on.
func _has_geometry(road_id: int) -> bool:
    if stream_geometry:
        return road_id >= 0 and road_id < _road_defs.size()
    return road_id < _builders.size()

## Rail gaps recompute_rails() stored for a streamed road (empty when none).
func stream_rail_gaps(road_id: int) -> Array:
    if road_id < 0 or road_id >= _stream_rail_gaps.size():
        return []
    return _stream_rail_gaps[road_id]

# --- Streaming ----------------------------------------------------------------

## Cell of a world position in the streaming grid.
func stream_cell_of(pos: Vector3) -> Vector2i:
    return RoadChunkMesher.cell_of(pos, stream_cell_size)

func is_cell_loaded(cell: Vector2i) -> bool:
    return _stream_loaded.has(cell)

## Whether any road segment belongs to `cell` (empty cells are never built).
func cell_has_roads(cell: Vector2i) -> bool:
    _stream_prepare()
    return _stream_index.has(cell)

func loaded_cells() -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for c: Vector2i in _stream_loaded:
        out.append(c)
    return out

## The node of a loaded cell (null when not loaded).
func cell_node(cell: Vector2i) -> Node3D:
    return _stream_loaded.get(cell, null)

func far_lod_node() -> MeshInstance3D:
    return _stream_far

func stream_stats() -> Dictionary:
    var out := _stream_stats.duplicate()
    out["loaded"] = _stream_loaded.size()
    out["in_flight"] = _stream_jobs.size()
    out["queued"] = _stream_queue.size()
    out["cells_with_roads"] = _stream_index.size()
    return out

## (Re)builds the per-road tables, the cell index and the far LOD from the
## current defs. Called lazily; any loaded cell is dropped (the geometry it was
## built from is stale).
func _stream_prepare() -> void:
    if not stream_geometry or not _stream_dirty:
        return
    _stream_dirty = false
    _stream_wait_all()
    for cell: Vector2i in _stream_loaded:
        var node: Node = _stream_loaded[cell]
        if is_instance_valid(node):
            node.queue_free()
    _stream_loaded.clear()
    _stream_queue.clear()
    _stream_ready_jobs.clear()
    var t0 := Time.get_ticks_usec()
    _stream_tables.clear()
    _stream_index.clear()
    for i in _road_defs.size():
        var table := RoadChunkMesher.prepare_road(i, _road_defs[i], stream_rail_gaps(i))
        _stream_tables.append(table)
        var cells := RoadChunkMesher.cell_segments(table, stream_cell_size)
        for cell: Vector2i in cells:
            var list: Array = _stream_index.get(cell, [])
            list.append([i, cells[cell]])
            _stream_index[cell] = list
    _stream_stats["prepare_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
    var tm := Time.get_ticks_usec()
    _stream_stats["materials"] = RoadChunkMesher.warm_materials(_stream_tables)
    if _stream_warm != null and is_instance_valid(_stream_warm):
        _stream_warm.queue_free()
    _stream_warm = RoadChunkMesher.warm_instances(_stream_tables, stream_flat_shadows)
    add_child(_stream_warm)
    _stream_stats["materials_ms"] = (Time.get_ticks_usec() - tm) / 1000.0
    if _stream_far != null and is_instance_valid(_stream_far):
        _stream_far.queue_free()
    _stream_far = null
    if stream_far_lod:
        var tf := Time.get_ticks_usec()
        var far := RoadChunkMesher.build_far(_stream_tables)
        _stream_far = RoadChunkMesher.instantiate_far(far)
        add_child(_stream_far)
        _stream_stats["far_ms"] = (Time.get_ticks_usec() - tf) / 1000.0
        _stream_stats["far_tris"] = (far["idx"] as PackedInt32Array).size() / 3
    _stream_has_player = false

## Cells around the car that must exist at all times (Chebyshev radius). A
## segment belongs to the cell of its midpoint and the sparse highway ring has
## ~150 m segments, so the road under the car can belong to a neighbouring cell.
const STREAM_GUARANTEED_RADIUS := 1

## Feeds the streaming centre (the player car). Cheap when the cell did not
## change (nine dictionary lookups). Any cell of the 3x3 block around the car
## that is still missing (spawn, fast travel, a car outrunning the worker) is
## built synchronously right here, so the car never reaches a road without
## collision.
func sync_player_pos(pos: Vector3) -> void:
    if not stream_geometry:
        return
    _stream_prepare()
    var cell := stream_cell_of(pos)
    var batch_t0 := -1
    for dz in range(-STREAM_GUARANTEED_RADIUS, STREAM_GUARANTEED_RADIUS + 1):
        for dx in range(-STREAM_GUARANTEED_RADIUS, STREAM_GUARANTEED_RADIUS + 1):
            var c := cell + Vector2i(dx, dz)
            if not _stream_loaded.has(c) and _stream_index.has(c):
                if batch_t0 < 0:
                    batch_t0 = Time.get_ticks_usec()
                _stream_build_sync(c)
    if batch_t0 >= 0:
        var batch_ms := (Time.get_ticks_usec() - batch_t0) / 1000.0
        _stream_stats["last_sync_batch_ms"] = batch_ms
        _stream_stats["max_sync_batch_ms"] = maxf(float(_stream_stats.get("max_sync_batch_ms", 0.0)), batch_ms)
    if _stream_has_player and cell == _stream_player_cell:
        return
    _stream_has_player = true
    _stream_player_cell = cell
    _stream_update_wanted()

## Builds every cell within stream_radius of `pos` right now (load time).
func prime_stream(pos: Vector3) -> void:
    if not stream_geometry:
        return
    _stream_prepare()
    var centre := stream_cell_of(pos)
    for cell in _stream_cells_around(centre, stream_radius):
        if not _stream_loaded.has(cell):
            _stream_build_sync(cell)
    sync_player_pos(pos)

func _stream_cells_around(centre: Vector2i, radius: int) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for dz in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            var c := centre + Vector2i(dx, dz)
            if _stream_index.has(c):
                out.append(c)
    out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
        return (a - centre).length_squared() < (b - centre).length_squared())
    return out

static func _cheb(a: Vector2i, b: Vector2i) -> int:
    return maxi(absi(a.x - b.x), absi(a.y - b.y))

func _stream_update_wanted() -> void:
    var centre := _stream_player_cell
    # Free what is past the keep radius (hysteresis: no thrash on a border).
    for cell: Vector2i in _stream_loaded.keys():
        if _cheb(cell, centre) > stream_keep_radius:
            _stream_free_queue.append(_stream_loaded[cell])
            _stream_loaded.erase(cell)
    var queue: Array[Vector2i] = []
    for cell in _stream_cells_around(centre, stream_radius):
        if not _stream_loaded.has(cell) and not _stream_jobs.has(cell):
            queue.append(cell)
    _stream_queue = queue

func _stream_build_sync(cell: Vector2i) -> void:
    var t0 := Time.get_ticks_usec()
    var result := RoadChunkMesher.build_cell(_stream_tables, _stream_index[cell])
    var t1 := Time.get_ticks_usec()
    _stream_add_cell(cell, result)
    var ms := (Time.get_ticks_usec() - t0) / 1000.0
    _stream_stats["max_sync_build_ms"] = maxf(float(_stream_stats.get("max_sync_build_ms", 0.0)), (t1 - t0) / 1000.0)
    _stream_stats["max_sync_add_ms"] = maxf(float(_stream_stats.get("max_sync_add_ms", 0.0)), (Time.get_ticks_usec() - t1) / 1000.0)
    _stream_stats["sync_builds"] = int(_stream_stats["sync_builds"]) + 1
    _stream_stats["max_sync_ms"] = maxf(float(_stream_stats["max_sync_ms"]), ms)

func _stream_add_cell(cell: Vector2i, result: Dictionary) -> void:
    var node := RoadChunkMesher.instantiate_cell(cell, result, stream_flat_shadows)
    add_child(node)
    _stream_loaded[cell] = node
    _stream_queue.erase(cell)

func _process(_delta: float) -> void:
    if not stream_geometry:
        return
    # 1. Collect finished worker builds.
    for cell: Vector2i in _stream_jobs.keys():
        var job: _CellJob = _stream_jobs[cell]
        if WorkerThreadPool.is_task_completed(job.task_id):
            WorkerThreadPool.wait_for_task_completion(job.task_id)
            _stream_jobs.erase(cell)
            _stream_ready_jobs.append(job)
            _stream_stats["max_job_ms"] = maxf(float(_stream_stats["max_job_ms"]), float(job.result.get("usec", 0)) / 1000.0)
    # 2. Add finished cells, nearest first, within the frame budget.
    if not _stream_ready_jobs.is_empty():
        var centre := _stream_player_cell
        _stream_ready_jobs.sort_custom(func(a: _CellJob, b: _CellJob) -> bool:
            return (a.cell - centre).length_squared() < (b.cell - centre).length_squared())
        var frame_t0 := Time.get_ticks_usec()
        var applied := 0
        while not _stream_ready_jobs.is_empty():
            if applied > 0 and (Time.get_ticks_usec() - frame_t0) / 1000.0 >= stream_apply_budget_ms:
                break
            var job: _CellJob = _stream_ready_jobs.pop_front()
            if _stream_loaded.has(job.cell) or _cheb(job.cell, centre) > stream_keep_radius:
                _stream_stats["dropped"] = int(_stream_stats["dropped"]) + 1
                continue
            var t0 := Time.get_ticks_usec()
            _stream_add_cell(job.cell, job.result)
            applied += 1
            _stream_stats["applied"] = int(_stream_stats["applied"]) + 1
            _stream_stats["max_apply_ms"] = maxf(float(_stream_stats["max_apply_ms"]), (Time.get_ticks_usec() - t0) / 1000.0)
        _stream_stats["max_frame_apply_ms"] = maxf(float(_stream_stats["max_frame_apply_ms"]), (Time.get_ticks_usec() - frame_t0) / 1000.0)
    # 3. Free a bounded number of cells that left the keep radius.
    var frees := 0
    while frees < STREAM_FREES_PER_FRAME and not _stream_free_queue.is_empty():
        var node: Node = _stream_free_queue.pop_front()
        if is_instance_valid(node):
            node.queue_free()
            _stream_stats["freed"] = int(_stream_stats["freed"]) + 1
        frees += 1
    # 4. Start new worker builds, nearest first.
    while _stream_jobs.size() < STREAM_MAX_IN_FLIGHT and not _stream_queue.is_empty():
        var cell: Vector2i = _stream_queue.pop_front()
        if _stream_loaded.has(cell) or _stream_jobs.has(cell) or not _stream_index.has(cell):
            continue
        var job := _CellJob.new()
        job.cell = cell
        job.tables = _stream_tables
        job.entries = _stream_index[cell]
        job.task_id = WorkerThreadPool.add_task(job.run, false, "RoadCell")
        _stream_jobs[cell] = job

## Blocks until every in-flight build is done (scene exit, re-prepare).
func _stream_wait_all() -> void:
    for cell: Vector2i in _stream_jobs.keys():
        var job: _CellJob = _stream_jobs[cell]
        WorkerThreadPool.wait_for_task_completion(job.task_id)
    _stream_jobs.clear()

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