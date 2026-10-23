# scripts/world/terrain_seeder.gd
class_name TerrainSeeder
extends Node

## Owns the Terrain3D node and region lifetime. sync_player_pos() keeps a 3x3
## ring of regions baked around the player. Physics ticks are pure bookkeeping:
## only the region directly under the car touches Terrain3D synchronously
## (ground must exist under the car instantly). Everything else on a ring
## change - removals, the other eight ring regions - is deferred to an idle
## _process pass that issues exactly one rebuild for the whole batch. Region
## bakes run on a background Thread using the same pure TerrainBaker math (no
## Terrain3D calls off the main thread) and are applied on the main thread as
## they finish, a bounded handful per frame so physics never stalls for the
## backlog. Baked images stay cached in memory so a region removed and then
## re-entered skips the rebuild, and regions that fall out of the ring are
## removed but keep their cached image. Beyond the ring, a prefetch ring
## (±PREFETCH_RADIUS) pre-bakes the incoming band on the worker as cached
## Images only — no Terrain3D regions are added — so the first step into a
## fresh ring writes a cached bake instead of stalling on a sync bake.

const REGION_SIZE := 256.0
const RING_RADIUS := 1  # 3x3 = 9 regions live around the player (+-256m); wider rings superlinear (see memo)
const PREFETCH_RADIUS := 2  # async pre-bake band outside the live ring (ring + 1)
const MAX_RING_ADD_PER_FRAME := 1  # live-ring blank adds per idle frame (Jolt heightfield build)
const MAX_APPLY_PER_TICK := 2  # finished async regions drained per main-thread tick
const PRIORITY_LIVE := 0  # live-ring/frontier bakes, served first
const PRIORITY_CORRIDOR := 1  # known-road corridor pre-bake, served next
const PRIORITY_PREFETCH := 2  # prefetch band, served last
const CORRIDOR_MARGIN := 1  # region locs pre-baked around each road point

## Corridor pre-bake budget bounds (P7). The per-network cap is now a *budget*
## derived by the pure corridor_budget_locs() from driveable kilometres
## (km -> region-locs math, directly unit-tested) -- never an arbitrary
## constant -- so the ~100 km classified ring (~190 region-locs) saturates the
## worker instead of being capped at the old small number. MAX_CORRIDOR_LOCS
## keeps its historical role as the ceiling of that budget; CORRIDOR_BUDGET_FLOOR
## keeps small/legacy networks at the historical 48-loc behaviour bit-for-bit.
## PRIORITY_LIVE (0) still wins over this Corridor priority everywhere, so the
## player-region sync bake is never starved by the bigger warm-up queue.
const MAX_CORRIDOR_LOCS := 190
const CORRIDOR_BUDGET_FLOOR := 48
## Region-locs of corridor warm-up claimed per network kilometre. Derivation:
## 1000 m per km / 1024 m per region = 0.977 region-lengths per km of road;
## each claims a (2*CORRIDOR_MARGIN+1)-wide neighbourhood whose adjacent cells
## share ~1/3 of their band, summing to ~1.9 distinct region-locs/km -- the plan
## figure: a 100 km ring touches ~190 regions.
const CORRIDOR_BUDGET_KM_FACTOR := 1.9
const SPAWN_REGION := Vector2i(0, 0)  # region under the (128, 128) spawn
## Terrain3D only allows region locations -16..15 (a 32 x 32 region map), so
## with 256 m regions a live Terrain3D region can exist only inside
## [-4096, 4096) on both axes. add_region_blankp() past that logs "Location
## (x, y) out of bounds" and returns null, thousands of errors per second while
## the car is there. The drivable world reaches ~9.7 km. A ring location outside
## this window is therefore a *virtual* region: baked and cached like any other
## (dressing reads the cache), announced through region_entered/region_left,
## but never added to Terrain3D. Its ground is the collision-bearing far
## terrain (TerrainVista, docs/plans/open_world_status.md section 8).
const LOC_MIN := -16
const LOC_MAX := 15

@export var terrain: Terrain3D
@export var bake_scale: float = 1.0
## Bake a Terrain3D control map (ground texture ids, TerrainBaker
## .bake_region_control) next to height + colour for every region.
@export var bake_ground_control: bool = true
## Give the Terrain3D node the ground texture set + material in _ready
## (TerrainTexturing.apply). Off by default so unit tests that build a bare
## seeder do not load 16 textures; the open-world scene turns it on.
@export var apply_ground_textures: bool = false
## TerrainTexturing.QUALITY_LITE (default, ~+1 ms GPU) or QUALITY_FULL.
@export var ground_texture_quality: int = TerrainTexturing.QUALITY_LITE

## Region-lifetime callbacks (P7). Emitted exactly once per transition: when a
## region's bake enters the live ring (fresh async apply on the main thread, or
## a cached re-entry write) and when a region leaves the ring
## (_remove_far_regions eviction). The RegionDresser observes these so dressing
## rises with the ground, persists through the prefetch band and frees exactly
## when the ring drops a region -- never a frame early or late, and never
## guessing the sync/async difference.
signal region_entered(loc: Vector2i)
signal region_left(loc: Vector2i)

## True when Terrain3D can hold a region at this location (see LOC_MIN).
static func loc_in_terrain_bounds(loc: Vector2i) -> bool:
	return loc.x >= LOC_MIN and loc.x <= LOC_MAX and loc.y >= LOC_MIN and loc.y <= LOC_MAX

## Key Vector2i (region location) -> {"image": Image (FORMAT_RF),
## "color": Image (FORMAT_RGBA8), "control": Image (FORMAT_RF control bits),
## "height_min": float, "height_max": float}, cached forever. The color and
## control images are optional: missing/null records are tolerated and write
## height-only, exactly as before the color bake.
var _baked: Dictionary = {}
var _baker := TerrainBaker.new()
var _roads: Array = []
var _road_defs: Array = []
## Carriageway width per entry of _roads (from the RoadDefs, ROAD_WIDTH-default
## when absent), so the control bake puts the gravel shoulder at each road edge.
var _road_widths := PackedFloat32Array()
## loc -> [control Image, its raw bytes] for baked_region_control().
var _control_bytes: Dictionary = {}

## Region locations whose finished bake was written into the terrain this
## session. Cleared when the region is removed so a re-entry rewrites it.
var _applied: Dictionary = {}

## Async bake pipeline. The worker Thread only runs pure TerrainBaker math and
## hands finished Image records back under _lock; every Terrain3D call happens
## on the main thread when a finished record is drained.
var _worker: Thread
var _worker_running := false
var _lock := Mutex.new()
var _sem := Semaphore.new()
var _work_queue: Array = []
var _pending: Array = []
## loc (Vector2i) -> roads generation it was queued with. Guards against ever
## queueing the same region twice and tags stale results after set_roads().
var _queued: Dictionary = {}
var _exit_requested := false
var _roads_generation := 0
var _player_region := Vector2i(1 << 30, 1 << 30)
## Last region the ring was synced around; the invalid sentinel forces the
## first sync_player_pos (and any post-set_roads pass) to re-prime prefetch.
var _ring_sig := Vector2i(1 << 30, 1 << 30)
## The ring changed since the last idle pass; set on the physics tick, consumed
## and reset by _apply_ring_pass() so region removals/adds batch into one
## Terrain3D rebuild instead of running inline on the physics tick.
var _ring_pass_dirty := false
## The ring mutated since the last full Terrain3D rebuild; the single
## update_maps() is issued on its own idle frame once the pass work is done.
var _ring_update_due := false
var _hitch := OS.get_environment("HITCH_TIMING") != ""
var _hitch_max: Dictionary = {}
var _player_pos := Vector3.ZERO

## Test-visible counters: sync bakes happen inline on the main thread while
## async bakes complete on the worker and are applied during the drain.
var sync_bake_count: int = 0
var async_completed_count: int = 0
var async_apply_count: int = 0

## Stores the road centerlines the baker should conform to and invalidates the
## bake cache so regions re-bake (and pick the roads up) on their next entry.
## Any in-flight or queued async results are dropped via the generation stamp.
## The optional road_defs array enables tier-aware corridor pre-bake priority
## (highway first, dirt last) when present; when absent the legacy
## spawn-distance fallback is preserved bit-for-bit.
func set_roads(roads: Array, road_defs: Array = []) -> void:
	_lock.lock()
	_roads_generation += 1
	_queued.clear()
	_pending.clear()
	_work_queue.clear()
	_lock.unlock()
	_roads = roads
	_road_defs = road_defs
	_road_widths = PackedFloat32Array()
	for def in road_defs:
		_road_widths.append(float(def.width) if def != null else TerrainBaker.ROAD_WIDTH)
	_baked.clear()
	_control_bytes.clear()
	_ring_sig = Vector2i(1 << 30, 1 << 30)
	_prebake_corridor(roads)

func _ready() -> void:
	if terrain == null:
		terrain = get_node_or_null("../Terrain3D") as Terrain3D
	if terrain == null:
		return
	terrain.collision_mode = 3
	terrain.region_size = Terrain3D.SIZE_256
	if apply_ground_textures:
		TerrainTexturing.apply(terrain, ground_texture_quality)

## Queues cached-only bakes (PRIORITY_CORRIDOR) for every region the known road
## network touches plus a CORRIDOR_MARGIN border, capped at a *budget* derived
## by corridor_budget_locs() from the network's driveable kilometres (km ->
## region-locs math, clipped to [CORRIDOR_BUDGET_FLOOR, MAX_CORRIDOR_LOCS]).
## When road_defs were passed to set_roads() the cap is ordered by tier priority
## (HIGHWAY ring first -> ARTERIAL -> TOUGE/COASTAL -> DIRT last) so the 100 km
## classified network still pre-bakes ahead of the player without flooding the
## worker; when no defs are present the legacy spawn-closest ordering is kept
## bit-for-bit. PRIORITY_LIVE (0) stays the winner over this Corridor priority
## everywhere. On-road frontier crossings hit the fast cached-write path instead
## of a placeholder wipe or a sync bake. Like _prefetch_ring this only warms the
## bake cache: it never adds a Terrain3D region. Called from set_roads() after
## the cache/generation reset.
func _prebake_corridor(roads: Array) -> void:
	if roads.is_empty():
		return
	var tiered := _road_defs.size() > 0
	var loc_set := {}
	var loc_tier: Dictionary = {}
	for i in roads.size():
		var road = roads[i]
		var tier: int = RoadDef.Tier.ARTERIAL
		if tiered and i < _road_defs.size():
			tier = _road_defs[i].tier
		for point in road:
			var p: Vector3 = point
			var base := Vector2i(floori(p.x / REGION_SIZE), floori(p.z / REGION_SIZE))
			for dx in range(-CORRIDOR_MARGIN, CORRIDOR_MARGIN + 1):
				for dz in range(-CORRIDOR_MARGIN, CORRIDOR_MARGIN + 1):
					var loc := base + Vector2i(dx, dz)
					loc_set[loc] = true
					if tiered:
						if not loc_tier.has(loc) or tier < loc_tier[loc]:
							loc_tier[loc] = tier
	loc_set.erase(SPAWN_REGION)
	var locs: Array = loc_set.keys()
	if tiered:
		locs.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var ta: int = loc_tier.get(a, RoadDef.Tier.DIRT)
			var tb: int = loc_tier.get(b, RoadDef.Tier.DIRT)
			if ta != tb:
				return ta < tb
			return _corridor_sort(a, b)
		)
	else:
		locs.sort_custom(_corridor_sort)
	var budget: int = corridor_budget_locs(_network_km(roads))
	for i in mini(locs.size(), budget):
		var loc: Vector2i = locs[i]
		if not _baked.has(loc) and not _applied.has(loc) and _queued_get(loc) == -1:
			_queue_bake(loc, int(REGION_SIZE), PRIORITY_CORRIDOR)

## Corridor fallback sort: squared region-coordinate distance to the spawn
## region, then x, then y (deterministic tie-break). Used alone for legacy
## one-arg set_roads(); used as the intra-tier tie-break when road_defs are
## present inside the tier-priority lambda.
func _corridor_sort(a: Vector2i, b: Vector2i) -> bool:
	var da := a.x * a.x + a.y * a.y
	var db := b.x * b.x + b.y * b.y
	if da != db:
		return da < db
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y

## Pure km -> region-locs budget for the corridor pre-bake (P7), unit-tested
## with no engine state. road_km is the total driveable network length; the
## budget scales linearly with it through CORRIDOR_BUDGET_KM_FACTOR (the plan
## figure: a 100 km classified ring touches ~190 region-locs), clipped into
## [floor_locs, max_locs] ([CORRIDOR_BUDGET_FLOOR=48, MAX_CORRIDOR_LOCS=190] by
## default) so small/legacy networks keep the historical 48-loc bound and the
## worker saturates at scale. corridor_margin widens the touch set the same way
## the neighbourhood fill does, so CORRIDOR_MARGIN stays the knob that trades
## pre-bake breadth against worker pressure. Monotone in road_km; static so a
## test can pin the ladder without an instance.
static func corridor_budget_locs(road_km: float, corridor_margin: int = CORRIDOR_MARGIN,
		max_locs: int = MAX_CORRIDOR_LOCS, floor_locs: int = CORRIDOR_BUDGET_FLOOR) -> int:
	if road_km <= 0.0:
		return floor_locs
	var raw := road_km * CORRIDOR_BUDGET_KM_FACTOR * (float(2 * corridor_margin + 1) / 3.0)
	return clampi(ceili(raw), floor_locs, max_locs)

## Total driveable network length in kilometres, summed over every corridor as
## pure per-segment distance math (main thread only -- the set_roads() path --
## and touches no Terrain3D). Feeds corridor_budget_locs() during
## _prebake_corridor so the budget stays derived, never hard-coded.
func _network_km(roads: Array) -> float:
	var total_m := 0.0
	for road in roads:
		var pts: Array = road
		for i in range(1, pts.size()):
			var a: Vector3 = pts[i - 1]
			var b: Vector3 = pts[i]
			total_m += a.distance_to(b)
	return total_m / 1000.0

## Ground height at a world XZ position, resolved from the *cached* bake of
## `loc` (the prefetch ring keeps that cache warm before a region goes live, so
## the RegionDresser's prefetch-band dressing sits on the real surface instead
## of flat ground). Returns 0.0 when the region has no cached bake or the XZ
## lies outside the region. Main-thread only: reads _baked directly, which is
## exactly why it is safe for the dressing path -- the dresser never reads
## Terrain3D from a worker. Region-anchored: the cache write is a grid-aligned
## per-region set_map, so sampling the frame-local pixel is inherently scaled
## and anchored (no import_images snap to reason about on this path).
## Whether `loc` has a cached bake (main thread; the RegionDresser waits for it
## before dressing a region so props sit on the real carved ground).
func has_baked_region(loc: Vector2i) -> bool:
	return _baked.has(loc)

## Raw control bits (TerrainTexturing.encode_control layout) of the cached
## control bake of `loc` at a world XZ, or -1 when the region has no cached
## control map or the XZ lies outside it. Main thread only, like
## baked_region_height: the dresser asks it which ground texture a grass tuft
## would stand on.
func baked_region_control(loc: Vector2i, world_pos: Vector3) -> int:
	if not _baked.has(loc):
		return -1
	var cached: Variant = (_baked[loc] as Dictionary).get("control", null)
	if not cached is Image:
		return -1
	var img: Image = cached
	var fx := (world_pos.x - loc.x * REGION_SIZE) / REGION_SIZE
	var fz := (world_pos.z - loc.y * REGION_SIZE) / REGION_SIZE
	if fx < 0.0 or fx >= 1.0 or fz < 0.0 or fz >= 1.0:
		return -1
	var w := img.get_width()
	var ix := clampi(int(floorf(fx * float(w))), 0, w - 1)
	var iz := clampi(int(floorf(fz * float(w))), 0, w - 1)
	# Image.get_data() copies the whole map, so the raw bytes are kept per
	# cached image (keyed by loc, validated by image identity so a re-bake
	# that replaced the record is never read stale).
	var entry: Array = _control_bytes.get(loc, [])
	if entry.is_empty() or entry[0] != img:
		if _control_bytes.size() >= 36:
			_control_bytes.clear()  # bounded: ~ the dresser band, 256 KB each
		entry = [img, img.get_data()]
		_control_bytes[loc] = entry
	var bytes: PackedByteArray = entry[1]
	return bytes.decode_u32((iz * w + ix) * 4)

## Read-only copies of a cached region bake for bulk main-thread reads (the
## Flora placer reads thousands of texels per region): {"height":
## PackedFloat32Array, "control": PackedByteArray (raw uint32 control bits),
## "width": int}. Empty when the region has no cached bake or no control map.
func baked_region_maps(loc: Vector2i) -> Dictionary:
	if not _baked.has(loc):
		return {}
	var rec: Dictionary = _baked[loc]
	var img: Variant = rec.get("image", null)
	var ctl: Variant = rec.get("control", null)
	if not img is Image or not ctl is Image:
		return {}
	var w := (img as Image).get_width()
	if (ctl as Image).get_width() != w:
		return {}
	return {"height": (img as Image).get_data().to_float32_array(), "control": (ctl as Image).get_data(), "width": w}

func baked_region_height(loc: Vector2i, world_pos: Vector3) -> float:
	if not _baked.has(loc):
		return 0.0
	var rec: Dictionary = _baked[loc]
	var cached: Variant = rec.get("image", null)
	if not cached is Image:
		return 0.0
	var img: Image = cached
	var fx := (world_pos.x - loc.x * REGION_SIZE) / REGION_SIZE
	var fz := (world_pos.z - loc.y * REGION_SIZE) / REGION_SIZE
	if fx < 0.0 or fx >= 1.0 or fz < 0.0 or fz >= 1.0:
		return 0.0
	var w := img.get_width()
	var ix := clampi(int(floorf(fx * float(w))), 0, w - 1)
	var iz := clampi(int(floorf(fz * float(w))), 0, w - 1)
	return float(img.get_pixel(ix, iz).r)

func _exit_tree() -> void:
	_stop_worker()

## Runs the ring pass first (a bounded removal/add slice, then its Terrain3D
## rebuild on the following idle frame), then drains finished async bakes a
## bounded handful per frame so physics is never stalled by the region backlog.
## Does not run while idle (both paths are cheap flag/lock checks).
func _process(_delta: float) -> void:
	if terrain == null:
		return
	_apply_ring_pass(terrain.data)
	_drain_pending(terrain.data, MAX_APPLY_PER_TICK)

## Ensures the region ring around the player exists and is baked. This is the
## physics-tick hot path: beyond bookkeeping it only touches Terrain3D for the
## player's own region (ground under the car), so a ring change can never stall
## physics with a removal or rebuild. Removals and the other eight regions come
## in the following idle pass.
func sync_player_pos(player_pos: Vector3) -> void:
	if terrain == null:
		return
	var _t_start := _ht()
	_player_pos = player_pos
	var player_region := Vector2i(floori(player_pos.x / REGION_SIZE), floori(player_pos.z / REGION_SIZE))
	_player_region = player_region
	var data: Terrain3DData = terrain.data
	_ensure_region(data, player_region)
	if player_region != _ring_sig:
		_ring_sig = player_region
		_ring_pass_dirty = true
		_prefetch_ring(player_region)
	_hm("sync_total", _t_start)

## Idle-timeslice of ring changes: removes regions that fell out of the ring and
## grows the rest of the ring in a bounded slice per frame (1 frontier region
## write and 1 removal), then rebuilds the Terrain3D maps for that slice on the
## next idle frame, alternating work and rebuild so a full column shift never
## batches into a single multi-hundred-ms update. A region map rebuild, collision
## rebuild and texture regeneration never run inline on the physics tick.
func _apply_ring_pass(data: Terrain3DData) -> void:
	if not _ring_pass_dirty and not _ring_update_due:
		return
	var _t_start := _ht()
	if _ring_update_due:
		data.update_maps()
		_ring_update_due = false
		_hm("ring_batched_umap", _t_start)
		return
	_ring_pass_dirty = false
	var changed := _remove_far_regions(data, _player_region, 1)
	changed = _ensure_ring_regions(data, MAX_RING_ADD_PER_FRAME) or changed
	_ring_pass_dirty = _region_work_pending(data)
	if changed:
		_ring_update_due = true
	_hm("apply_ring_pass", _t_start)

## Ensures up to max_regions of the RING_RADIUS ring regions around the player
## still needing work this frame, nearest shell first. The player's own region is
## ensured on the physics tick, so this safely covers the other ring regions;
## cached bakes are written immediately (deferred to the pass's next rebuild) and
## everything else is queued on the worker. Returns true when any region was
## added or written so the caller can defer the rebuild.
func _ensure_ring_regions(data: Terrain3DData, max_regions: int) -> bool:
	var _t_start := _ht()
	var changed := false
	var count := 0
	var offsets: Array = []
	for dx in range(-RING_RADIUS, RING_RADIUS + 1):
		for dz in range(-RING_RADIUS, RING_RADIUS + 1):
			if dx == 0 and dz == 0:
				continue
			offsets.append(Vector2i(dx, dz))
	offsets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ra := maxi(absi(a.x), absi(a.y))
		var rb := maxi(absi(b.x), absi(b.y))
		if ra != rb:
			return ra < rb
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y
	)
	for off: Vector2i in offsets:
		var loc := _player_region + off
		if _ring_region_settled(data, loc):
			continue
		if count >= max_regions:
			_hm("ring_ensure", _t_start)
			return changed
		changed = _ensure_region(data, loc, false) or changed
		count += 1
	_hm("ring_ensure", _t_start)
	return changed

## Removes up to max_removals regions outside the live ring for the player.
## Removal defers the Terrain3D rebuild to the batched pass: remove_regionp(loc,
## false) only marks the region deleted and dirties the region map, and the RID
## bookkeeping is freed in the pass's single update. Returns true when any
## region was removed so the pass issues exactly one rebuild. Fires
## region_left(loc) once per evicted region so dressing mirrors the frees at
## the same cadence.
func _remove_far_regions(data: Terrain3DData, player_region: Vector2i, max_removals: int) -> bool:
	var _t_start := _ht()
	var active: Array = data.get_region_locations()
	var removed := false
	var count := 0
	for loc in active:
		if abs(loc.x - player_region.x) > RING_RADIUS or abs(loc.y - player_region.y) > RING_RADIUS:
			data.remove_regionp(_region_center(loc), false)
			_applied.erase(loc)
			region_left.emit(loc)
			removed = true
			count += 1
			if count >= max_removals:
				break
	# Virtual regions (outside Terrain3D's location window) have no Terrain3D
	# state to remove; evict them the moment they leave the ring.
	for loc: Vector2i in _applied.keys():
		if loc_in_terrain_bounds(loc):
			continue
		if abs(loc.x - player_region.x) > RING_RADIUS or abs(loc.y - player_region.y) > RING_RADIUS:
			_applied.erase(loc)
			region_left.emit(loc)
	_hm("ring_remove", _t_start)
	return removed

## Returns true while the current ring pass still has removals or unprocessed
## ring regions left, so _apply_ring_pass keeps the pass dirty until it drains.
func _region_work_pending(data: Terrain3DData) -> bool:
	var active: Array = data.get_region_locations()
	for loc in active:
		if abs(loc.x - _player_region.x) > RING_RADIUS or abs(loc.y - _player_region.y) > RING_RADIUS:
			return true
	for loc: Vector2i in _applied.keys():
		if not loc_in_terrain_bounds(loc) and (abs(loc.x - _player_region.x) > RING_RADIUS or abs(loc.y - _player_region.y) > RING_RADIUS):
			return true
	for dx in range(-RING_RADIUS, RING_RADIUS + 1):
		for dz in range(-RING_RADIUS, RING_RADIUS + 1):
			var loc := _player_region + Vector2i(dx, dz)
			if loc == _player_region:
				continue
			if loc_in_terrain_bounds(loc) and not data.has_regionp(_region_center(loc)):
				return true
			if not _applied.has(loc) and _queued_get(loc) == -1:
				return true
	return false

## True when the ring has nothing left to do for loc: a real region that exists
## and is applied or queued, or a virtual region that is applied or queued.
func _ring_region_settled(data: Terrain3DData, loc: Vector2i) -> bool:
	if loc_in_terrain_bounds(loc) and not data.has_regionp(_region_center(loc)):
		return false
	return _applied.has(loc) or _queued_get(loc) != -1

## Adds + bakes a region on first entry; on re-entry a cached image is written
## straight into the freshly re-added blank region. The player's own region is
## never left hollow: a cached bake (from the prefetch ring or an earlier pass)
## is written immediately, a queued bake is bridged by a nearby cached
## placeholder, and only a first-ever, never-baked/never-queued region bakes
## synchronously; every other region is queued on the worker thread and applied
## by the drain when it finishes. with_update=false defers the GPU/rebuild work
## to the batched ring pass. Returns true when the terrain was mutated (region
## added or image written) so the pass can skip a redundant rebuild.
func _ensure_region(data: Terrain3DData, loc: Vector2i, with_update: bool = true) -> bool:
	var _t_start := _ht()
	if not loc_in_terrain_bounds(loc):
		return _ensure_virtual_region(loc)
	var center := _region_center(loc)
	var is_player := loc == _player_region
	var region: Terrain3DRegion = data.get_regionp(center) if data.has_regionp(center) else null
	if region != null:
		if _applied.has(loc):
			_hm("ensure_applied", _t_start)
			return false
		if is_player:
			_bake_player_region(data, region, loc)
			region_entered.emit(loc)
			_hm("ensure_player2", _t_start)
			return true
		if _queued_get(loc) == -1:
			_queue_bake(loc, _map_width(region), PRIORITY_LIVE)
		_hm("ensure_queued", _t_start)
		return false
	var _t_add := _ht()
	region = data.add_region_blankp(center, false)
	_hm("ensure_add_blank", _t_add)
	if region == null:
		return false
	if _baked.has(loc):
		var rec: Variant = _baked[loc]
		var image: Image = rec["image"]
		if image != null:
			var _t_wr := _ht()
			_write_region(data, region, loc, image, rec["height_min"], rec["height_max"], with_update, rec.get("color"), rec.get("control"))
			_hm("ensure_write", _t_wr)
			_applied[loc] = true
			region_entered.emit(loc)
			_hm("ensure_cached", _t_start)
			return true
	if is_player:
		_bake_player_region(data, region, loc)
		region_entered.emit(loc)
		_hm("ensure_bake", _t_start)
		return true
	_queue_bake(loc, _map_width(region), PRIORITY_LIVE)
	_hm("ensure_blank", _t_start)
	return true

## Ring bookkeeping for a location Terrain3D cannot hold (see LOC_MIN): serve
## it from the bake cache when it is ready, else queue the bake at live
## priority; _apply_record announces it when the worker lands it. Nothing is
## written to Terrain3D and nothing is rebuilt, so this never reports a change.
func _ensure_virtual_region(loc: Vector2i) -> bool:
	if _applied.has(loc):
		return false
	if _baked.has(loc):
		_applied[loc] = true
		region_entered.emit(loc)
		return false
	if _queued_get(loc) == -1:
		_queue_bake(loc, int(REGION_SIZE), PRIORITY_LIVE)
	else:
		_promote_live(loc)
	return false

## Player-region entry: prefer the cached image (fast write, no stall). If the
## bake is already queued or in flight, the crossing writes the nearest cached
## bake as a fast placeholder (blank stays flat if none is cached) and bumps
## that job to the front of the worker queue; only a never-baked, never-queued
## region falls back to a synchronous bake on the physics tick.
func _bake_player_region(data: Terrain3DData, region: Terrain3DRegion, loc: Vector2i) -> void:
	var _t_start := _ht()
	if _baked.has(loc):
		var rec: Variant = _baked[loc]
		var image: Image = rec["image"]
		var color: Image = rec.get("color")
		var control: Image = rec.get("control")
		if image != null:
			if color == null:
				color = _baker.bake_region_color(loc, bake_scale, image.get_width(), _roads)
			if control == null:
				control = _bake_control(_baker, loc, image)
			_write_region(data, region, loc, image, rec["height_min"], rec["height_max"], true, color, control)
			_applied[loc] = true
			_hm("bake_player", _t_start)
			return
	if _queued_get(loc) == -1:
		_bake_sync(data, region, loc)
		_hm("bake_player", _t_start)
		return
	_requeue_front(loc)
	var near_rec := _nearest_cached_record(loc)
	if not near_rec.is_empty():
		var near_image: Image = near_rec["image"]
		var near_color: Image = near_rec.get("color")
		if near_image != null:
			if near_color == null:
				near_color = _baker.bake_region_color(loc, bake_scale, near_image.get_width(), _roads)
			_write_region(data, region, loc, near_image, near_rec["height_min"], near_rec["height_max"], true, near_color, near_rec.get("control"))
	_applied[loc] = true
	_hm("bake_player", _t_start)

## Pre-bakes the PREFETCH_RADIUS band around the player (including the live
## ring whose cache a set_roads() clear just dropped) on the worker thread.
## Prefetch only caches baked Images: it never adds a Terrain3D region, so the
## live ring still trims to +-1 and _remove_far_regions never strips a
## prefetch-only region. Regions already cached, already applied, or already
## queued are left untouched (_queue_bake guards a loc being queued twice).
func _prefetch_ring(player_region: Vector2i) -> void:
	var offsets: Array = []
	for dx in range(-PREFETCH_RADIUS, PREFETCH_RADIUS + 1):
		for dz in range(-PREFETCH_RADIUS, PREFETCH_RADIUS + 1):
			offsets.append(Vector2i(dx, dz))
	offsets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ra := maxi(absi(a.x), absi(a.y))
		var rb := maxi(absi(b.x), absi(b.y))
		if ra != rb:
			return ra < rb
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y
	)
	for off: Vector2i in offsets:
		var loc := player_region + off
		if _baked.has(loc) or _applied.has(loc):
			continue
		# The live ring itself is PRIORITY_LIVE, and a ring region already queued
		# at corridor/prefetch priority is promoted. Before 2026-10-22 the whole
		# band went in at PRIORITY_PREFETCH and _ensure_region never re-queued an
		# already-queued loc, so live-ring regions sat blank and flat behind the
		# ~150-loc corridor pre-bake for tens of seconds after spawn.
		var in_ring := maxi(absi(off.x), absi(off.y)) <= RING_RADIUS
		if _queued_get(loc) == -1:
			_queue_bake(loc, int(REGION_SIZE), PRIORITY_LIVE if in_ring else PRIORITY_PREFETCH)
		elif in_ring:
			_promote_live(loc)

## Synchronous bake + apply, reserved for the region under the player. Any
## async job already in flight for the same region is superseded: its record is
## dropped on arrival because _baked is already populated.
func _bake_sync(data: Terrain3DData, region: Terrain3DRegion, loc: Vector2i) -> void:
	var _t_start := _ht()
	var map := region.get_map(Terrain3DRegion.TYPE_HEIGHT)
	if map == null:
		return
	var image := _baker.bake_region(loc, bake_scale, map.get_width(), _roads)
	var color := _baker.bake_region_color(loc, bake_scale, map.get_width(), _roads)
	var control := _bake_control(_baker, loc, image)
	var range := _scan_height_range(image)
	_baked[loc] = {"image": image, "color": color, "control": control, "height_min": range.x, "height_max": range.y}
	sync_bake_count += 1
	_write_region(data, region, loc, image, range.x, range.y, true, color, control)
	_applied[loc] = true
	_hm("bake_sync", _t_start)

## Writes the baked height image into the region as its full-resolution map,
## plus the optional RGBA8 color map as a TYPE_COLOR sibling, grows the region
## AABB, then regenerates the changed regions' maps. Callers pass a
## cached/worker-computed min/max so the main thread never rescans the image;
## the scan fallback only exists for the sync cold-start path. When with_update
## is false the GPU regeneration is deferred to the batched ring pass, which
## updates every changed region in a single update_maps() call. A null color is
## tolerated and keeps the region height-only, exactly as before the color bake.
func _write_region(data: Terrain3DData, region: Terrain3DRegion, loc: Vector2i, image: Image, height_min: float = INF, height_max: float = -INF, with_update: bool = true, color: Image = null, control: Image = null) -> void:
	var _t_start := _ht()
	var _t_sub := _ht()
	region.set_map(Terrain3DRegion.TYPE_HEIGHT, image)
	_hm("wr_set_height", _t_sub)
	if color != null:
		var _t_col := _ht()
		region.set_map(Terrain3DRegion.TYPE_COLOR, color)
		_hm("wr_set_color", _t_col)
	if control != null:
		region.set_map(Terrain3DRegion.TYPE_CONTROL, control)
	if height_min == INF:
		var range := _scan_height_range(image)
		height_min = range.x
		height_max = range.y
	region.update_height(height_min)
	region.update_height(height_max)
	region.set_edited(true)
	if with_update:
		var _t_um := _ht()
		data.update_maps(Terrain3DRegion.TYPE_HEIGHT, false)
		if color != null:
			data.update_maps(Terrain3DRegion.TYPE_COLOR, false)
		if control != null:
			data.update_maps(Terrain3DRegion.TYPE_CONTROL, false)
		_hm("wr_update_maps", _t_um)
	region.set_edited(false)
	_hm("umap_inline", _t_start)

## Main-thread control bake for the sync paths (player region, cold start,
## colour re-bake); null when bake_ground_control is off.
func _bake_control(baker: TerrainBaker, loc: Vector2i, height_image: Image) -> Image:
	if not bake_ground_control:
		return null
	return baker.bake_region_control(loc, bake_scale, height_image.get_width(), _roads, height_image, _road_widths)

func _scan_height_range(image: Image) -> Vector2:
	var height_min := INF
	var height_max := -INF
	if image.get_format() == Image.FORMAT_RF:
		var floats := image.get_data().to_float32_array()
		for y in floats:
			height_min = minf(height_min, y)
			height_max = maxf(height_max, y)
	else:
		for iz in image.get_height():
			for ix in image.get_width():
				var y := image.get_pixel(ix, iz).r
				height_min = minf(height_min, y)
				height_max = maxf(height_max, y)
	return Vector2(height_min, height_max)

## Queues a region bake for the worker. Never queues a region twice: _queued is
## authoritative until the drain consumes (or drops) the finished record.
func _queue_bake(loc: Vector2i, width: int, priority: int = 0) -> void:
	var gen := _roads_generation
	_lock.lock()
	if _queued.has(loc):
		_lock.unlock()
		return
	_queued[loc] = gen
	_work_queue.append(_make_job(loc, width, gen, priority))
	_lock.unlock()
	_start_worker()
	_sem.post()

func _make_job(loc: Vector2i, width: int, gen: int, priority: int = 0) -> Dictionary:
	return {
		"loc": loc,
		"width": width,
		"gen": gen,
		"scale": bake_scale,
		"roads": _roads.duplicate(),
		"widths": _road_widths.duplicate(),
		"control": bake_ground_control,
		"priority": priority,
	}

func _start_worker() -> void:
	if _worker != null and _worker_running:
		return
	_worker = Thread.new()
	_worker_running = true
	_exit_requested = false
	_worker.start(Callable(self, "_worker_process"))

## Worker entry point: pure TerrainBaker math only, no Terrain3D calls. Pops the
## lowest-priority job first (stable FIFO within a priority: the linear scan
## keeps the first/oldest of the min-priority set). Finished records are pushed
## under _lock for the main thread to drain.
func _worker_process() -> void:
	var worker_baker := TerrainBaker.new()
	while true:
		_lock.lock()
		var exit := _exit_requested
		var job: Variant = null
		if not _work_queue.is_empty():
			var best_idx := 0
			var best_priority := int(_work_queue[0].get("priority", 0))
			for i in range(1, _work_queue.size()):
				var p: int = _work_queue[i].get("priority", 0)
				if p < best_priority:
					best_priority = p
					best_idx = i
			job = _work_queue.pop_at(best_idx)
		_lock.unlock()
		if exit:
			return
		if job == null:
			_sem.wait()
			continue
		var record := _worker_bake(worker_baker, job)
		_lock.lock()
		_pending.append(record)
		async_completed_count += 1
		_lock.unlock()

func _worker_bake(worker_baker: TerrainBaker, job: Dictionary) -> Dictionary:
	var loc: Vector2i = job["loc"]
	var width: int = job["width"]
	var gen: int = job["gen"]
	var scale: float = job["scale"]
	var roads: Array = job["roads"]
	var image: Image = worker_baker.bake_region(loc, scale, width, roads)
	var color: Image = worker_baker.bake_region_color(loc, scale, width, roads)
	var control: Image = null
	if bool(job.get("control", false)):
		control = worker_baker.bake_region_control(loc, scale, width, roads, image, job.get("widths", PackedFloat32Array()))
	var range := _scan_height_range(image)
	return {
		"loc": loc,
		"gen": gen,
		"image": image,
		"color": color,
		"control": control,
		"height_min": range.x,
		"height_max": range.y,
	}

## Applies finished async bakes on the main thread, a bounded handful per tick.
## Records for regions that left the ring, were already baked (player sync
## priority), or were invalidated by a roads change are dropped/cached without
## touching the terrain. Applied regions are also cached for instant re-entry.
func _drain_pending(data: Terrain3DData, max_jobs: int) -> void:
	var _t_start := _ht()
	if max_jobs <= 0:
		return
	_lock.lock()
	var available := _pending.size()
	if available == 0:
		_lock.unlock()
		_hm("drain_total", _t_start)
		return
	var take := mini(available, max_jobs)
	var ready: Array = _pending.slice(0, take)
	if take >= available:
		_pending.clear()
	else:
		_pending = _pending.slice(take)
	_lock.unlock()
	for record in ready:
		_apply_record(record, data)
	_hm("drain_total", _t_start)

func _apply_record(record: Dictionary, data: Terrain3DData) -> void:
	var _t_start := _ht()
	var loc: Vector2i = record["loc"]
	var gen: int = record["gen"]
	if gen != _roads_generation:
		_clear_queued_if_matching(loc, gen)
		_hm("apply_record", _t_start)
		return
	var image: Image = record["image"]
	var color: Image = record.get("color")
	var control: Image = record.get("control")
	var center := _region_center(loc)
	var already_cached := _baked.has(loc)
	_baked[loc] = {
		"image": image,
		"color": color,
		"control": control,
		"height_min": record["height_min"],
		"height_max": record["height_max"],
	}
	if not already_cached and not loc_in_terrain_bounds(loc):
		# Virtual region: nothing to write, just announce it to the dresser.
		if _ring_contains(loc) and not _applied.has(loc):
			_applied[loc] = true
			async_apply_count += 1
			region_entered.emit(loc)
	elif not already_cached and data != null and _ring_contains(loc):
		var region: Terrain3DRegion = data.get_regionp(center) if data.has_regionp(center) else null
		if region != null:
			_write_region(data, region, loc, image, record["height_min"], record["height_max"], false, color, control)
			_applied[loc] = true
			async_apply_count += 1
			_ring_update_due = true
			region_entered.emit(loc)
	_clear_queued_if_matching(loc, gen)
	_hm("apply_record", _t_start)

func _clear_queued_if_matching(loc: Vector2i, gen: int) -> void:
	_lock.lock()
	if _queued.get(loc, -1) == gen:
		_queued.erase(loc)
	_lock.unlock()

## Chooses the cached bake (XZ distance) nearest loc for use as a placeholder
## image while loc's own bake is still queued. Returns {} when nothing is cached.
func _nearest_cached_record(loc: Vector2i) -> Dictionary:
	var best_rec: Dictionary = {}
	var best_dist := INF
	for src in _baked:
		var src_loc: Vector2i = src
		var dx := src_loc.x - loc.x
		var dz := src_loc.y - loc.y
		var dist := dx * dx + dz * dz
		if dist < best_dist:
			best_dist = dist
			best_rec = _baked[src]
	return best_rec

## Moves a still-queued region's job to the front of the worker queue and bumps
## it to PRIORITY_LIVE so its bake lands as soon as possible (used when the
## player crosses onto a region whose bake is pending). Safe no-op when the job
## already left the queue.
func _requeue_front(loc: Vector2i) -> void:
	_lock.lock()
	if not _queued.has(loc):
		_lock.unlock()
		return
	for i in range(_work_queue.size()):
		var job: Dictionary = _work_queue[i]
		if job["loc"] == loc:
			job["priority"] = PRIORITY_LIVE
			_work_queue.remove_at(i)
			_work_queue.push_front(job)
			break
	_lock.unlock()

## Raises a still-queued job for `loc` to PRIORITY_LIVE in place (the worker
## always pops the lowest priority value first). No-op when not queued or
## already live; unlike _requeue_front it keeps FIFO order among live jobs.
func _promote_live(loc: Vector2i) -> void:
	_lock.lock()
	for job: Dictionary in _work_queue:
		if job["loc"] == loc:
			if int(job.get("priority", PRIORITY_LIVE)) > PRIORITY_LIVE:
				job["priority"] = PRIORITY_LIVE
			break
	_lock.unlock()

## Priority of the queued job for `loc`, -1 when it is not waiting in the
## worker queue (test/diagnostic helper).
func _queued_priority(loc: Vector2i) -> int:
	var p := -1
	_lock.lock()
	for job: Dictionary in _work_queue:
		if job["loc"] == loc:
			p = int(job.get("priority", PRIORITY_LIVE))
			break
	_lock.unlock()
	return p

func _ring_contains(loc: Vector2i) -> bool:
	return abs(loc.x - _player_region.x) <= RING_RADIUS and abs(loc.y - _player_region.y) <= RING_RADIUS

## Stops the worker thread and clears the pipeline. Safe to call twice (the
## running flag under _lock prevents a double join); called from _exit_tree.
func _stop_worker() -> void:
	var should_join := false
	_lock.lock()
	if _worker_running:
		_exit_requested = true
		_worker_running = false
		should_join = true
	_lock.unlock()
	if should_join and _worker != null:
		_sem.post()
		_worker.wait_to_finish()
		_worker = null
	_lock.lock()
	_pending.clear()
	_queued.clear()
	_work_queue.clear()
	_lock.unlock()

## Forces an immediate synchronous grass color bake for the player region.
## Called after set_roads() clears the cache to ensure grass is visible on spawn.
func force_player_region_color_bake() -> void:
	if terrain == null:
		return
	var data: Terrain3DData = terrain.data
	if data == null:
		return
	if not loc_in_terrain_bounds(_player_region):
		return
	var center := _region_center(_player_region)
	var region: Terrain3DRegion = data.get_regionp(center) if data.has_regionp(center) else null
	if region == null:
		return
	var map := region.get_map(Terrain3DRegion.TYPE_HEIGHT)
	if map == null:
		return
	var image: Image = _baker.bake_region(_player_region, bake_scale, map.get_width(), _roads)
	var color: Image = _baker.bake_region_color(_player_region, bake_scale, map.get_width(), _roads)
	var control := _bake_control(_baker, _player_region, image)
	var range := _scan_height_range(image)
	_baked[_player_region] = {"image": image, "color": color, "control": control, "height_min": range.x, "height_max": range.y}
	_write_region(data, region, _player_region, image, range.x, range.y, true, color, control)
	_applied[_player_region] = true

## Internal pipeline state, exposed for the streaming tests.
func _bake_queued(loc: Vector2i) -> bool:
	return _queued_get(loc) != -1

func _queued_count() -> int:
	var n := 0
	_lock.lock()
	n = _queued.size()
	_lock.unlock()
	return n

func _pending_count() -> int:
	var n := 0
	_lock.lock()
	n = _pending.size()
	_lock.unlock()
	return n

func _async_completed() -> int:
	var n := 0
	_lock.lock()
	n = async_completed_count
	_lock.unlock()
	return n

func _queued_get(loc: Vector2i) -> int:
	var gen := -1
	_lock.lock()
	if _queued.has(loc):
		gen = _queued[loc]
	_lock.unlock()
	return gen

## Width of a region's height map, falling back to the full region resolution.
func _map_width(region: Terrain3DRegion) -> int:
	var map := region.get_map(Terrain3DRegion.TYPE_HEIGHT)
	return map.get_width() if map != null else int(REGION_SIZE)

## World XZ center of a region location (y is irrelevant to region math).
func _region_center(loc: Vector2i) -> Vector3:
	return Vector3(loc.x * REGION_SIZE + REGION_SIZE * 0.5, 0.0, loc.y * REGION_SIZE + REGION_SIZE * 0.5)

## Env-gated hitch instrumentation (HITCH_TIMING=1). _ht() starts a stopwatch,
## _hm(key, start) folds the elapsed usec into _hitch_max; accessors let a probe
## read and reset the per-section worst-case timings. All keys are strings and
## the helpers are no-ops when the env flag is unset, so the cost is one branch.
func _ht() -> float:
	return Time.get_ticks_usec() if _hitch else 0.0

func _hm(key: String, start: float) -> void:
	if not _hitch:
		return
	var el := Time.get_ticks_usec() - start
	var cur: Variant = _hitch_max.get(key, 0)
	if el > cur:
		_hitch_max[key] = el

func reset_hitch() -> void:
	_hitch_max.clear()

func hitch_active() -> bool:
	return _hitch

func hitch_max_ms() -> Dictionary:
	var out: Dictionary = {}
	for key in _hitch_max:
		out[key] = float(_hitch_max[key]) / 1000.0
	return out