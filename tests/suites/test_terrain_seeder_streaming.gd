# tests/suites/test_terrain_seeder_streaming.gd
extends GdUnitTestSuite

## Covers the TerrainSeeder async bake pipeline: the worker must produce
## byte-identical height images to the sync baker, the same region must never
## be queued twice, and the region under the player must always bake
## synchronously before any async result is applied.

const IMAGE_WIDTH := 1024
const REGION_SIZE := 1024.0
const SPAWN := Vector3(128.0, 2.2, 128.0)
const PLAYER_REGION := Vector2i(0, 0)
const NEIGHBOR_REGION := Vector2i(1, 0)

func _center_of(loc: Vector2i) -> Vector3:
	return Vector3(loc.x * REGION_SIZE + REGION_SIZE * 0.5, 0.0, loc.y * REGION_SIZE + REGION_SIZE * 0.5)

func _bake_direct(loc: Vector2i, width: int = IMAGE_WIDTH) -> Image:
	return TerrainBaker.new().bake_region(loc, 1.0, width, [])

## Sync color reference: bake_region_color at scale 1.0, the exact call the
## worker job mirrors (scale defaults to the seeder's bake_scale = 1.0).
func _color_direct(loc: Vector2i, width: int = IMAGE_WIDTH) -> Image:
	return TerrainBaker.new().bake_region_color(loc, 1.0, width, [])

## Awaits a wall-clock condition with no busy loop; caps out and returns false
## so tests fail with a clear assert rather than hanging the suite.
func _await_until(condition: Callable, timeout_s: float) -> bool:
	var loops := int(timeout_s / 0.1)
	for _i in loops:
		if condition.call():
			return true
		await get_tree().create_timer(0.1).timeout
	return condition.call()

## test (a): the threaded produce of a region is byte-identical to the sync
## TerrainBaker produce of the same region, and the drain releases the guard.
func test_worker_streamed_bake_matches_sync_baker() -> void:
	var seeder := TerrainSeeder.new()
	var target := Vector2i(2, 1)
	seeder._queue_bake(target, IMAGE_WIDTH)
	var landed := await _await_until(func() -> bool: return seeder._pending_count() > 0, 30.0)
	assert_that(landed).is_true()
	seeder._drain_pending(null, 100)
	var cached: Variant = seeder._baked.get(target)
	var baked: Image = (cached as Dictionary).get("image") as Image if cached is Dictionary else null
	assert_that(baked).is_not_null()
	if baked == null:
		return
	var reference: Image = _bake_direct(target, IMAGE_WIDTH)
	assert_that(baked.get_width()).is_equal(reference.get_width())
	assert_that(baked.get_height()).is_equal(reference.get_height())
	assert_that(baked.get_data()).is_equal(reference.get_data())
	assert_that(seeder._async_completed()).is_greater_equal(1)
	assert_that(seeder._bake_queued(target)).is_false()
	seeder._stop_worker()

## test (a2): the worker's streamed bake carries a deterministic RGBA8 color map
## as a "color" sibling of the height image, sized like the height map and
## byte-identical to the sync TerrainBaker color produce (same region/scale/
## width/roads), mirroring the height equivalence test above.
func test_worker_streamed_bake_carries_color() -> void:
	var seeder := TerrainSeeder.new()
	var target := Vector2i(4, 3)
	seeder._queue_bake(target, IMAGE_WIDTH)
	var landed := await _await_until(func() -> bool: return seeder._pending_count() > 0, 30.0)
	assert_that(landed).is_true()
	seeder._drain_pending(null, 100)
	var cached: Variant = seeder._baked.get(target)
	var color: Image = (cached as Dictionary).get("color") as Image if cached is Dictionary else null
	assert_that(color).is_not_null()
	if color == null:
		return
	var height: Image = (cached as Dictionary).get("image") as Image if cached is Dictionary else null
	assert_that(height).is_not_null()
	assert_that(color.get_width()).is_equal(height.get_width())
	assert_that(color.get_height()).is_equal(height.get_height())
	assert_that(color.get_format()).is_equal(Image.FORMAT_RGBA8)
	var reference: Image = _color_direct(target, IMAGE_WIDTH)
	assert_that(color.get_data()).is_equal(reference.get_data())
	assert_that(seeder._bake_queued(target)).is_false()
	seeder._stop_worker()

## test (b): requesting the same out-of-player region twice yields a single
## queued job, and the guard releases only once the drain consumes the result.
func test_same_region_is_never_queued_twice_and_guard_releases() -> void:
	var seeder := TerrainSeeder.new()
	var target := Vector2i(3, 2)
	seeder._queue_bake(target, 8)
	seeder._queue_bake(target, 8)
	assert_that(seeder._bake_queued(target)).is_true()
	assert_that(seeder._queued_count()).is_equal(1)
	var landed := await _await_until(func() -> bool: return seeder._pending_count() >= 1, 30.0)
	assert_that(landed).is_true()
	seeder._drain_pending(null, 100)
	assert_that(seeder._queued_count()).is_equal(0)
	assert_that(seeder._bake_queued(target)).is_false()
	seeder._queue_bake(target, 8)
	assert_that(seeder._bake_queued(target)).is_true()
	assert_that(seeder._queued_count()).is_equal(1)
	seeder._stop_worker()

## test (c): when the player's own region is un-baked it bakes synchronously
## (guard flags: sync bake counter fires, zero async applies) while the ring
## neighbors are handed to the worker; the async apply only lands afterwards.
func test_player_region_sync_bakes_before_any_async_apply() -> void:
	var terrain := Terrain3D.new()
	add_child(terrain)
	var seeder := TerrainSeeder.new()
	seeder.terrain = terrain
	add_child(seeder)
	await get_tree().create_timer(0.3).timeout
	seeder._player_region = PLAYER_REGION
	var data: Terrain3DData = terrain.data
	assert_that(data).is_not_null()
	if data == null:
		return
	seeder._ensure_region(data, PLAYER_REGION)
	assert_that(seeder.sync_bake_count).is_equal(1)
	assert_that(seeder.async_apply_count).is_equal(0)
	assert_that(seeder._baked.has(PLAYER_REGION)).is_true()
	assert_that(seeder._applied.has(PLAYER_REGION)).is_true()
	assert_that(data.has_regionp(_center_of(PLAYER_REGION))).is_true()
	seeder._ensure_region(data, NEIGHBOR_REGION)
	assert_that(seeder._bake_queued(NEIGHBOR_REGION)).is_true()
	assert_that(seeder.async_apply_count).is_equal(0)
	var applied := await _await_until(func() -> bool: return seeder.async_apply_count > 0, 30.0)
	assert_that(applied).is_true()
	assert_that(seeder._baked.has(NEIGHBOR_REGION)).is_true()
	assert_that(seeder._applied.has(NEIGHBOR_REGION)).is_true()
	seeder._stop_worker()

## test (d): set_roads() with road_defs queues HIGHWAY-tier corridor locations
## before DIRT-tier locations (tier-priority ordering), and never floods the
## worker beyond the bounded MAX_CORRIDOR_LOCS budget.
func test_set_roads_with_defs_respects_tier_priority_order() -> void:
	var seeder := TerrainSeeder.new()
	var hw_pts: Array[Vector3] = [Vector3(1100.0, 0.0, 100.0)]
	var dt_pts: Array[Vector3] = [Vector3(20000.0, 0.0, 20000.0)]
	var hw_def := RoadDef.make(RoadDef.Tier.HIGHWAY, hw_pts)
	var dt_def := RoadDef.make(RoadDef.Tier.DIRT, dt_pts)
	seeder.set_roads([hw_pts, dt_pts], [hw_def, dt_def])
	seeder._lock.lock()
	var q: Array = seeder._work_queue.duplicate()
	seeder._lock.unlock()
	assert_that(q.size()).is_greater(0)
	assert_that(q.size()).is_less_equal(seeder.MAX_CORRIDOR_LOCS)
	# Highway at (1100,100) spreads over regions y=-1..1; dirt at (20000,20000)
	# over y=18..20. Every HIGHWAY-tier entry must precede the first DIRT entry.
	var first_dirt_idx := q.size()
	for i in q.size():
		if q[i]["loc"].y >= 18:
			first_dirt_idx = mini(first_dirt_idx, i)
			break
	for i in first_dirt_idx:
		assert_that(q[i]["loc"].y).is_less(2)
	seeder._stop_worker()

## test (e): the legacy one-arg set_roads(roads) still works — no defs are
## stored and the spawn-distance fallback ordering is preserved.
func test_legacy_set_roads_one_arg_still_works() -> void:
	var seeder := TerrainSeeder.new()
	var roads: Array = [[Vector3(1100.0, 0.0, 100.0)]]
	seeder.set_roads(roads)
	assert_that(seeder._road_defs.is_empty()).is_true()
	seeder._lock.lock()
	var q: Array = seeder._work_queue.duplicate()
	seeder._lock.unlock()
	assert_that(q.size()).is_greater(0)
	assert_that(q.size()).is_less_equal(seeder.MAX_CORRIDOR_LOCS)
	seeder._stop_worker()

## test (f): corridor pre-bake is bounded — a road spanning dozens of regions
## never queues more than MAX_CORRIDOR_LOCS jobs.
func test_corridor_prebake_bounded_by_max_locs() -> void:
	var seeder := TerrainSeeder.new()
	var long_road: Array[Vector3] = []
	for i in range(20, 80):
		long_road.append(Vector3(float(i) * 1100.0, 0.0, 0.0))
	seeder.set_roads([long_road])
	assert_that(seeder._road_defs.is_empty()).is_true()
	seeder._lock.lock()
	var q: Array = seeder._work_queue.duplicate()
	seeder._lock.unlock()
	assert_that(q.size()).is_less_equal(seeder.MAX_CORRIDOR_LOCS)
	seeder._stop_worker()