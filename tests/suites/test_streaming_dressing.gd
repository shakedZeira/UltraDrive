# tests/suites/test_streaming_dressing.gd
extends GdUnitTestSuite

## P7 region-streamed dressing (mirrors tests/suites/test_terrain_seeder_streaming.gd).
## Pins the pure corridor km -> region-loc budget ladder, the seeder's cached
## bake-height read, the RegionDresser ring mirror (spawn/free budgeting, band
## density, distance-banded visible culling), and bit-identical per-region
## placement across eviction + re-entry and across two dresser instances with
## the same master seed. Headless-safe: all dressing math is main-thread; the
## only worker the suite starts is stopped before the test returns. Dressing
## nodes are created under the suite and freed in after_test so the run stays
## orphan-free.

const MASTER_TEST := 82731408
const REGION_CELL := 1024.0
const SPAWN := Vector3(128.0, 0.0, 128.0)
## Foliage counts are zone-independent (exports only), so live density is
## exactly grass_count + tree_count and prefetch (0.5) is half of that.
const LIVE_FOLIAGE_GRAPHICS := 700 + 40
const PREFETCH_FOLIAGE_GRAPHICS := 350 + 20

var _tracked_nodes: Array[Node] = []
var _tracked_seeders: Array[TerrainSeeder] = []

func before_test() -> void:
	_tracked_nodes.clear()
	_tracked_seeders.clear()

func after_test() -> void:
	for seeder in _tracked_seeders:
		if is_instance_valid(seeder):
			seeder._stop_worker()
	for node in _tracked_nodes:
		if is_instance_valid(node) and node.get_parent() != null:
			node.free()
	_tracked_seeders.clear()
	_tracked_nodes.clear()

func _ring_locs(center: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			out.append(center + Vector2i(dx, dz))
	return out

func _make_dresser(max_dresses: int, max_frees: int = 2) -> RegionDresser:
	var dresser := RegionDresser.new()
	dresser.max_dresses_per_frame = max_dresses
	dresser.max_frees_per_frame = max_frees
	add_child(dresser)
	dresser.set_process(false)
	_tracked_nodes.append(dresser)
	return dresser

func _make_seeder() -> TerrainSeeder:
	var seeder := TerrainSeeder.new()
	_tracked_seeders.append(seeder)
	return seeder

func _drain_all(dresser: RegionDresser) -> void:
	for _i in range(64):
		dresser.drain_pending()
		if dresser.pending_spawn_count() == 0 and dresser.pending_free_count() == 0:
			return

func _positions_of(dresser: RegionDresser, loc: Vector2i) -> PackedVector3Array:
	var node: Node3D = dresser.region_node(loc)
	var result := PackedVector3Array()
	if node == null:
		return result
	var props: PropScatterer = node.get_node_or_null(RegionDresser.PROPS_CHILD_NAME) as PropScatterer
	var foliage: Foliage = node.get_node_or_null(RegionDresser.FOLIAGE_CHILD_NAME) as Foliage
	if props != null:
		result.append_array(props.get_instance_positions())
	if foliage != null:
		result.append_array(foliage.get_instance_positions())
	return result

func _foliage_count(dresser: RegionDresser, loc: Vector2i) -> int:
	var node: Node3D = dresser.region_node(loc)
	if node == null:
		return -1
	var foliage: Foliage = node.get_node_or_null(RegionDresser.FOLIAGE_CHILD_NAME) as Foliage
	return foliage.get_instance_count() if foliage != null else -1

func _visible_count(dresser: RegionDresser, loc: Vector2i) -> int:
	var node: Node3D = dresser.region_node(loc)
	if node == null:
		return -1
	var foliage: Foliage = node.get_node_or_null(RegionDresser.FOLIAGE_CHILD_NAME) as Foliage
	return foliage.get_visible_instance_count() if foliage != null else -1

func _child_count(dresser: RegionDresser, loc: Vector2i) -> int:
	var node: Node3D = dresser.region_node(loc)
	return node.get_child_count() if node != null else -1

## test (a): the pure corridor km -> region-loc budget ladder. 100 km saturates
## at MAX_CORRIDOR_LOCS (the plan figure), the historical floor holds for tiny
## networks, the ladder is monotone, and town crippling small inputs stay inside
## [floor, max].
func test_corridor_budget_locs_pure_ladder() -> void:
	assert_that(TerrainSeeder.MAX_CORRIDOR_LOCS).is_equal(190)
	assert_that(TerrainSeeder.CORRIDOR_BUDGET_FLOOR).is_equal(48)
	assert_that(TerrainSeeder.corridor_budget_locs(100.0)).is_equal(190)
	assert_that(TerrainSeeder.corridor_budget_locs(60.0)).is_equal(114)
	assert_that(TerrainSeeder.corridor_budget_locs(6.4)).is_equal(48)
	assert_that(TerrainSeeder.corridor_budget_locs(500.0)).is_equal(190)
	assert_that(TerrainSeeder.corridor_budget_locs(0.0)).is_equal(48)
	assert_that(TerrainSeeder.corridor_budget_locs(0.01)).is_equal(48)
	assert_that(TerrainSeeder.corridor_budget_locs(30.0)).is_less(TerrainSeeder.corridor_budget_locs(60.0))
	assert_that(TerrainSeeder.corridor_budget_locs(100.0, 2)).is_equal(190)
	assert_that(TerrainSeeder.corridor_budget_locs(60.0, 1)).is_equal(114)

## test (b): a real ~66 km road claims exactly the derived budget's worth of
## corridor pre-bake and never exceeds the MAX cap (set_roads -> _prebake_corridor
## feeds corridor_budget_locs).
func test_corridor_prebake_shrinks_to_66km_budget() -> void:
	var seeder := _make_seeder()
	var road: Array[Vector3] = []
	for i in range(65):
		road.append(Vector3(float(i) * REGION_CELL, 0.0, 0.0))
	seeder.set_roads([road])
	assert_that(seeder._road_defs.is_empty()).is_true()
	seeder._lock.lock()
	var q: Array = seeder._work_queue.duplicate()
	seeder._lock.unlock()
	var predicted: int = TerrainSeeder.corridor_budget_locs(64.0 * REGION_CELL / 1000.0)
	assert_that(q.size()).is_greater(0)
	assert_that(q.size()).is_less_equal(predicted)
	assert_that(predicted).is_less_equal(seeder.MAX_CORRIDOR_LOCS)
	assert_that(predicted).is_greater_equal(seeder.CORRIDOR_BUDGET_FLOOR)

## test (c): baked_region_height resolves a cached bake's own pixel (region
## center on a known bake) and returns 0.0 when the region has no cached bake or
## the XZ lies outside the region. No worker is started here, so no join is
## needed.
func test_baked_region_height_reads_cached_pixel_or_zero() -> void:
	var seeder := _make_seeder()
	var loc := Vector2i(0, 0)
	var img: Image = TerrainBaker.new().bake_region(loc, 1.0, 8, [])
	seeder._baked[loc] = {"image": img, "color": null, "height_min": 0.0, "height_max": 1.0}
	var world_center := Vector3(REGION_CELL * 0.5, 0.0, REGION_CELL * 0.5)
	var got: float = seeder.baked_region_height(loc, world_center)
	var expect: float = float(img.get_pixel(4, 4).r)
	assert_that(got).is_equal(expect)
	assert_that(seeder.baked_region_height(loc, Vector3(REGION_CELL * 1.5, 0.0, REGION_CELL * 0.5))).is_equal(0.0)
	assert_that(seeder.baked_region_height(Vector2i(9, 9), world_center)).is_equal(0.0)

## test (d): region_seed / region_zone are pure and deterministic and the zone
## always lands inside the dresser's preset set.
func test_region_seed_and_zone_deterministic_and_valid() -> void:
	var loc := Vector2i(-3, 5)
	assert_that(RegionDresser.region_seed(MASTER_TEST, loc)).is_equal(RegionDresser.region_seed(MASTER_TEST, loc))
	assert_that(RegionDresser.region_seed(MASTER_TEST, Vector2i(0, 0))).is_not_equal(RegionDresser.region_seed(MASTER_TEST, loc))
	var zones := ["festival", "lowlands", "coast", "highlands", "alpine"]
	for dx in range(-6, 7):
		for dz in range(-6, 7):
			var z: String = RegionDresser.region_zone(MASTER_TEST, Vector2i(dx, dz))
			assert_that(zones).contains(z)

## test (e): sync_player_pos mirrors the 5x5 band (25 locs = 9 live + 16
## prefetch), and drain_pending is bounded at max_dresses_per_frame per call.
## The dressed set stays exactly 25 with no duplicate dressing anywhere.
func test_ring_mirror_and_bounded_drain() -> void:
	var dresser := _make_dresser(2)
	dresser.sync_player_pos(SPAWN)
	assert_that(dresser.pending_spawn_count()).is_equal(25)
	dresser.drain_pending()
	assert_that(dresser.pending_spawn_count()).is_equal(23)
	assert_that(dresser.dressed_region_count()).is_equal(2)
	for _i in range(14):
		dresser.drain_pending()
	assert_that(dresser.pending_spawn_count()).is_equal(0)
	assert_that(dresser.dressed_region_count()).is_equal(25)
	var live := 0
	for loc: Vector2i in _ring_locs(Vector2i(0, 0)):
		assert_that(dresser.is_dressed(loc)).is_true()
		assert_that(dresser.region_band(loc)).is_equal(RegionDresser.BAND_LIVE if maxi(absi(loc.x), absi(loc.y)) <= 1 else RegionDresser.BAND_PREFETCH)
		if maxi(absi(loc.x), absi(loc.y)) <= 1:
			live += 1
	assert_that(live).is_equal(9)

## test (f): eviction frees the far band, the dressed set never exceeds the band
## size while shifting, and re-entering a freed region is bit-identical
## placement (same seed) with exactly one Props + one Foliage child per region.
func test_eviction_frees_and_reentry_is_bit_identical() -> void:
	var dresser := _make_dresser(2)
	dresser.sync_player_pos(SPAWN)
	_drain_all(dresser)
	assert_that(dresser.dressed_region_count()).is_equal(25)
	var first_pos: PackedVector3Array = _positions_of(dresser, Vector2i(0, 0))
	assert_that(first_pos.size()).is_greater(0)
	dresser.sync_player_pos(Vector3(SPAWN.x + 3.0 * REGION_CELL, 0.0, SPAWN.z))
	assert_that(dresser.pending_free_count()).is_equal(15)
	assert_that(dresser.pending_spawn_count()).is_equal(15)
	for _i in range(4):
		dresser.drain_pending()
		assert_that(dresser.dressed_region_count()).is_less_equal(25)
	_drain_all(dresser)
	assert_that(dresser.dressed_region_count()).is_equal(25)
	assert_that(dresser.region_band(Vector2i(0, 0))).is_equal(-1)
	assert_that(dresser.region_band(Vector2i(3, 0))).is_equal(RegionDresser.BAND_LIVE)
	dresser.sync_player_pos(SPAWN)
	assert_that(dresser.pending_free_count()).is_equal(15)
	_drain_all(dresser)
	assert_that(dresser.dressed_region_count()).is_equal(25)
	assert_that(dresser.region_band(Vector2i(0, 0))).is_equal(RegionDresser.BAND_LIVE)
	var reentry_pos: PackedVector3Array = _positions_of(dresser, Vector2i(0, 0))
	assert_that(reentry_pos).is_equal(first_pos)
	assert_that(_child_count(dresser, Vector2i(0, 0))).is_equal(2)

## test (g): the prefetch band generates at reduced density AND draws only a
## clamped fraction of its placed set via visible_instance_count (band culling),
## while the live ring always draws every placed instance. The prefetch visible
## figure is zone-dependent (props join the culling budget), so assert the
## relationships, not one literal; the pure fraction is pinned in test (i).
func test_prefetch_band_density_and_visibility() -> void:
	var dresser := _make_dresser(2)
	dresser.sync_player_pos(SPAWN)
	_drain_all(dresser)
	var live_loc := Vector2i(0, 0)
	var pref_loc := Vector2i(0, 2)
	assert_that(_foliage_count(dresser, live_loc)).is_equal(LIVE_FOLIAGE_GRAPHICS)
	assert_that(_foliage_count(dresser, pref_loc)).is_equal(PREFETCH_FOLIAGE_GRAPHICS)
	assert_that(_visible_count(dresser, live_loc)).is_equal(LIVE_FOLIAGE_GRAPHICS)
	var pref_vis: int = _visible_count(dresser, pref_loc)
	assert_that(pref_vis).is_greater(0)
	assert_that(pref_vis).is_less_equal(PREFETCH_FOLIAGE_GRAPHICS)
	assert_that(pref_vis).is_less(_foliage_count(dresser, live_loc))
	assert_that(pref_vis).is_less_equal(_visible_count(dresser, live_loc))

## test (h): two dressers over the same master seed produce byte-identical
## placements for the same regions (determinism is a pure function of the seed,
## never shared instance state).
func test_two_dressers_same_master_seed_identical_placement() -> void:
	var dresser_a := _make_dresser(2)
	var dresser_b := _make_dresser(2)
	dresser_a.sync_player_pos(SPAWN)
	dresser_b.sync_player_pos(SPAWN)
	_drain_all(dresser_a)
	_drain_all(dresser_b)
	assert_that(dresser_a.dressed_region_count()).is_equal(25)
	assert_that(dresser_b.dressed_region_count()).is_equal(25)
	for loc: Vector2i in _ring_locs(Vector2i(0, 0)):
		assert_that(_positions_of(dresser_a, loc)).is_equal(_positions_of(dresser_b, loc))

## test (i): the dresser's band LOD knobs are pure functions of the prefetch
## density export, with live always full density / visibility.
func test_band_density_and_visibility_math() -> void:
	var dresser := _make_dresser(2)
	assert_that(dresser.band_density(RegionDresser.BAND_LIVE)).is_equal(1.0)
	assert_that(dresser.band_density(RegionDresser.BAND_PREFETCH)).is_equal(0.5)
	assert_that(dresser.band_visibility(RegionDresser.BAND_LIVE)).is_equal(1.0)
	assert_that(dresser.band_visibility(RegionDresser.BAND_PREFETCH)).is_equal(0.625)
	dresser.prefetch_density = 0.2
	assert_that(dresser.band_visibility(RegionDresser.BAND_PREFETCH)).is_equal(0.25)
	dresser.prefetch_density = 0.05
	assert_that(dresser.band_visibility(RegionDresser.BAND_PREFETCH)).is_equal(0.2)