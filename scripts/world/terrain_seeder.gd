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

const REGION_SIZE := 1024.0
const RING_RADIUS := 1  # 3x3 = 9 regions live around the player
const PREFETCH_RADIUS := 2  # async pre-bake band outside the live ring
const MAX_APPLY_PER_TICK := 2  # finished async regions drained per main-thread tick
const PRIORITY_LIVE := 0  # live-ring/frontier bakes, served first
const PRIORITY_CORRIDOR := 1  # known-road corridor pre-bake, served next
const PRIORITY_PREFETCH := 2  # prefetch band, served last
const CORRIDOR_MARGIN := 1  # region locs pre-baked around each road point
const MAX_CORRIDOR_LOCS := 40  # corridor pre-bake cap, spawn-closest first
const SPAWN_REGION := Vector2i(0, 0)  # region under the (128, 128) spawn

@export var terrain: Terrain3D
@export var bake_scale: float = 1.0

## Key Vector2i (region location) -> {"image": Image (FORMAT_RF),
## "height_min": float, "height_max": float}, cached forever.
var _baked: Dictionary = {}
var _baker := TerrainBaker.new()
var _roads: Array = []

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

## Test-visible counters: sync bakes happen inline on the main thread while
## async bakes complete on the worker and are applied during the drain.
var sync_bake_count: int = 0
var async_completed_count: int = 0
var async_apply_count: int = 0

## Stores the road centerlines the baker should conform to and invalidates the
## bake cache so regions re-bake (and pick the roads up) on their next entry.
## Any in-flight or queued async results are dropped via the generation stamp.
func set_roads(roads: Array) -> void:
	_lock.lock()
	_roads_generation += 1
	_queued.clear()
	_pending.clear()
	_work_queue.clear()
	_lock.unlock()
	_roads = roads
	_baked.clear()
	_ring_sig = Vector2i(1 << 30, 1 << 30)
	_prebake_corridor(roads)

func _ready() -> void:
	if terrain == null:
		terrain = get_node_or_null("../Terrain3D") as Terrain3D
	if terrain == null:
		return
	terrain.collision_mode = 3
	terrain.region_size = Terrain3D.SIZE_1024

## Queues cached-only bakes (PRIORITY_CORRIDOR) for every region the known road
## network touches plus a CORRIDOR_MARGIN border, capped at MAX_CORRIDOR_LOCS
## (spawn-closest first), so the whole driveable route pre-bakes on the worker
## in the background right after bootstrap. On-road frontier crossings then hit
## the fast cached-write path instead of a placeholder wipe or a sync bake.
## Like _prefetch_ring this only warms the bake cache: it never adds a
## Terrain3D region. Called from set_roads() after the cache/generation reset.
func _prebake_corridor(roads: Array) -> void:
	if roads.is_empty():
		return
	var loc_set := {}
	for road in roads:
		for point in road:
			var p: Vector3 = point
			var base := Vector2i(floori(p.x / REGION_SIZE), floori(p.z / REGION_SIZE))
			for dx in range(-CORRIDOR_MARGIN, CORRIDOR_MARGIN + 1):
				for dz in range(-CORRIDOR_MARGIN, CORRIDOR_MARGIN + 1):
					loc_set[base + Vector2i(dx, dz)] = true
	loc_set.erase(SPAWN_REGION)
	var locs = loc_set.keys()
	locs.sort_custom(_corridor_sort)
	for i in mini(locs.size(), MAX_CORRIDOR_LOCS):
		var loc: Vector2i = locs[i]
		if not _baked.has(loc) and not _applied.has(loc) and _queued_get(loc) == -1:
			_queue_bake(loc, int(REGION_SIZE), PRIORITY_CORRIDOR)

## Corridor cap sort: squared region-coordinate distance to the spawn region,
## then x, then y (deterministic tie-break).
func _corridor_sort(a: Vector2i, b: Vector2i) -> bool:
	var da := a.x * a.x + a.y * a.y
	var db := b.x * b.x + b.y * b.y
	if da != db:
		return da < db
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y

func _exit_tree() -> void:
	_stop_worker()

## Runs the batched ring pass first (removals + new-ring regions in a single
## Terrain3D rebuild), then drains finished async bakes a bounded handful per
## frame so physics is never stalled by the region backlog. Does not run while
## idle (both paths are cheap flag/lock checks).
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
	var player_region := Vector2i(floori(player_pos.x / REGION_SIZE), floori(player_pos.z / REGION_SIZE))
	_player_region = player_region
	var data: Terrain3DData = terrain.data
	_ensure_region(data, player_region)
	if player_region != _ring_sig:
		_ring_sig = player_region
		_ring_pass_dirty = true
		_prefetch_ring(player_region)

## Idle-timeslice of ring changes: removes regions that fell out of the ring and
## grows the rest of the ring in a bounded slice per frame (at most 2 frontier
## region writes and 1 removal), then issues the single full Terrain3D rebuild
## on its own idle frame once the pass work is done. A region map rebuild,
## collision rebuild and texture regeneration happen once per pass, never inline
## on the physics tick.
func _apply_ring_pass(data: Terrain3DData) -> void:
	if not _ring_pass_dirty and not _ring_update_due:
		return
	if not _ring_pass_dirty:
		data.update_maps()
		_ring_update_due = false
		return
	_ring_pass_dirty = false
	var changed := _remove_far_regions(data, _player_region, 1)
	changed = _ensure_ring_regions(data, 2) or changed
	_ring_pass_dirty = _region_work_pending(data)
	if changed:
		_ring_update_due = true

## Ensures up to max_regions of the 3x3 ring regions around the player still
## needing work this frame. The player's own region is ensured on the physics
## tick, so this safely covers the other eight; cached bakes are written
## immediately (deferred to the pass's single update) and everything else is
## queued on the worker. Returns true when any region was added or written so
## the caller can defer the rebuild.
func _ensure_ring_regions(data: Terrain3DData, max_regions: int) -> bool:
	var changed := false
	var count := 0
	for dx in range(-RING_RADIUS, RING_RADIUS + 1):
		for dz in range(-RING_RADIUS, RING_RADIUS + 1):
			var loc := _player_region + Vector2i(dx, dz)
			if loc == _player_region:
				continue
			var center := _region_center(loc)
			if data.has_regionp(center) and (_applied.has(loc) or _queued_get(loc) != -1):
				continue
			if count >= max_regions:
				return changed
			changed = _ensure_region(data, loc, false) or changed
			count += 1
	return changed

## Removes up to max_removals regions outside the live ring for the player.
## Removal defers the Terrain3D rebuild to the batched pass: remove_regionp(loc,
## false) only marks the region deleted and dirties the region map, and the RID
## bookkeeping is freed in the pass's single update. Returns true when any
## region was removed so the pass issues exactly one rebuild.
func _remove_far_regions(data: Terrain3DData, player_region: Vector2i, max_removals: int) -> bool:
	var active: Array = data.get_region_locations()
	var removed := false
	var count := 0
	for loc in active:
		if abs(loc.x - player_region.x) > RING_RADIUS or abs(loc.y - player_region.y) > RING_RADIUS:
			data.remove_regionp(_region_center(loc), false)
			_applied.erase(loc)
			removed = true
			count += 1
			if count >= max_removals:
				break
	return removed

## Returns true while the current ring pass still has removals or unprocessed
## ring regions left, so _apply_ring_pass keeps the pass dirty until it drains.
func _region_work_pending(data: Terrain3DData) -> bool:
	var active: Array = data.get_region_locations()
	for loc in active:
		if abs(loc.x - _player_region.x) > RING_RADIUS or abs(loc.y - _player_region.y) > RING_RADIUS:
			return true
	for dx in range(-RING_RADIUS, RING_RADIUS + 1):
		for dz in range(-RING_RADIUS, RING_RADIUS + 1):
			var loc := _player_region + Vector2i(dx, dz)
			if loc == _player_region:
				continue
			var center := _region_center(loc)
			if not data.has_regionp(center):
				return true
			if not _applied.has(loc) and _queued_get(loc) == -1:
				return true
	return false

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
	var center := _region_center(loc)
	var is_player := loc == _player_region
	var region: Terrain3DRegion = data.get_regionp(center) if data.has_regionp(center) else null
	if region != null:
		if _applied.has(loc):
			return false
		if is_player:
			_bake_player_region(data, region, loc)
			return true
		if _queued_get(loc) == -1:
			_queue_bake(loc, _map_width(region), PRIORITY_LIVE)
		return false
	region = data.add_region_blankp(center, false)
	if region == null:
		return false
	if _baked.has(loc):
		var rec: Variant = _baked[loc]
		var image: Image = rec["image"]
		if image != null:
			_write_region(data, region, loc, image, rec["height_min"], rec["height_max"], with_update)
			_applied[loc] = true
			return true
	if is_player:
		_bake_player_region(data, region, loc)
		return true
	_queue_bake(loc, _map_width(region), PRIORITY_LIVE)
	return true

## Player-region entry: prefer the cached image (fast write, no stall). If the
## bake is already queued or in flight, the crossing writes the nearest cached
## bake as a fast placeholder (blank stays flat if none is cached) and bumps
## that job to the front of the worker queue; only a never-baked, never-queued
## region falls back to a synchronous bake on the physics tick.
func _bake_player_region(data: Terrain3DData, region: Terrain3DRegion, loc: Vector2i) -> void:
	if _baked.has(loc):
		var rec: Variant = _baked[loc]
		var image: Image = rec["image"]
		if image != null:
			_write_region(data, region, loc, image, rec["height_min"], rec["height_max"])
			_applied[loc] = true
			return
	if _queued_get(loc) == -1:
		_bake_sync(data, region, loc)
		return
	_requeue_front(loc)
	var near_rec := _nearest_cached_record(loc)
	if not near_rec.is_empty():
		var near_image: Image = near_rec["image"]
		if near_image != null:
			_write_region(data, region, loc, near_image, near_rec["height_min"], near_rec["height_max"])
	_applied[loc] = true

## Pre-bakes the PREFETCH_RADIUS band around the player (including the live
## ring whose cache a set_roads() clear just dropped) on the worker thread.
## Prefetch only caches baked Images: it never adds a Terrain3D region, so the
## live ring still trims to +-1 and _remove_far_regions never strips a
## prefetch-only region. Regions already cached, already applied, or already
## queued are left untouched (_queue_bake guards a loc being queued twice).
func _prefetch_ring(player_region: Vector2i) -> void:
	for dx in range(-PREFETCH_RADIUS, PREFETCH_RADIUS + 1):
		for dz in range(-PREFETCH_RADIUS, PREFETCH_RADIUS + 1):
			var loc := player_region + Vector2i(dx, dz)
			if _baked.has(loc) or _applied.has(loc):
				continue
			if _queued_get(loc) == -1:
				_queue_bake(loc, int(REGION_SIZE), PRIORITY_PREFETCH)

## Synchronous bake + apply, reserved for the region under the player. Any
## async job already in flight for the same region is superseded: its record is
## dropped on arrival because _baked is already populated.
func _bake_sync(data: Terrain3DData, region: Terrain3DRegion, loc: Vector2i) -> void:
	var map := region.get_map(Terrain3DRegion.TYPE_HEIGHT)
	if map == null:
		return
	var image := _baker.bake_region(loc, bake_scale, map.get_width(), _roads)
	var range := _scan_height_range(image)
	_baked[loc] = {"image": image, "height_min": range.x, "height_max": range.y}
	sync_bake_count += 1
	_write_region(data, region, loc, image, range.x, range.y)
	_applied[loc] = true

## Writes the baked height image into the region as its full-resolution map,
## grows the region AABB, then regenerates the changed regions' maps. Callers
## pass a cached/worker-computed min/max so the main thread never rescans the
## image; the scan fallback only exists for the sync cold-start path. When
## with_update is false the GPU regeneration is deferred to the batched ring
## pass, which updates every changed region in a single update_maps() call.
func _write_region(data: Terrain3DData, region: Terrain3DRegion, loc: Vector2i, image: Image, height_min: float = INF, height_max: float = -INF, with_update: bool = true) -> void:
	region.set_map(Terrain3DRegion.TYPE_HEIGHT, image)
	if height_min == INF:
		var range := _scan_height_range(image)
		height_min = range.x
		height_max = range.y
	region.update_height(height_min)
	region.update_height(height_max)
	region.set_edited(true)
	if with_update:
		data.update_maps(Terrain3DRegion.TYPE_HEIGHT, false)
	region.set_edited(false)

func _scan_height_range(image: Image) -> Vector2:
	var height_min := INF
	var height_max := -INF
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
	var range := _scan_height_range(image)
	return {
		"loc": loc,
		"gen": gen,
		"image": image,
		"height_min": range.x,
		"height_max": range.y,
	}

## Applies finished async bakes on the main thread, a bounded handful per tick.
## Records for regions that left the ring, were already baked (player sync
## priority), or were invalidated by a roads change are dropped/cached without
## touching the terrain. Applied regions are also cached for instant re-entry.
func _drain_pending(data: Terrain3DData, max_jobs: int) -> void:
	if max_jobs <= 0:
		return
	_lock.lock()
	var available := _pending.size()
	if available == 0:
		_lock.unlock()
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

func _apply_record(record: Dictionary, data: Terrain3DData) -> void:
	var loc: Vector2i = record["loc"]
	var gen: int = record["gen"]
	if gen != _roads_generation:
		_clear_queued_if_matching(loc, gen)
		return
	var image: Image = record["image"]
	var center := _region_center(loc)
	var already_cached := _baked.has(loc)
	_baked[loc] = {
		"image": image,
		"height_min": record["height_min"],
		"height_max": record["height_max"],
	}
	if not already_cached and data != null and _ring_contains(loc):
		var region: Terrain3DRegion = data.get_regionp(center) if data.has_regionp(center) else null
		if region != null:
			_write_region(data, region, loc, image, record["height_min"], record["height_max"])
			_applied[loc] = true
			async_apply_count += 1
	_clear_queued_if_matching(loc, gen)

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