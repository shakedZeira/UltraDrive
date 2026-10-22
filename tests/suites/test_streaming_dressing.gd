# tests/suites/test_streaming_dressing.gd
extends GdUnitTestSuite

## P7 region-streamed dressing (mirrors tests/suites/test_terrain_seeder_streaming.gd).
## Pins the pure corridor km -> region-loc budget ladder, the seeder's cached
## bake-height read, the RegionDresser ring mirror (spawn/free budgeting, band
## density, distance-banded visible culling), the shared whole-map road network
## handed to every region's scatterer and the roadside share of its props, and
## bit-identical per-region placement across eviction + re-entry and across two
## dresser instances with the same master seed. Headless-safe: all dressing math
## is main-thread; the only worker the suite starts is stopped before the test
## returns. Dressing nodes are created under the suite and freed in after_test
## so the run stays orphan-free.

const MASTER_TEST := 82731408
const REGION_CELL := 256.0
const SPAWN := Vector3(128.0, 0.0, 128.0)
## Region foliage counts come from the dresser's per-zone table
## (RegionDresser.ZONE_FOLIAGE; the spawn regions are "lowlands"), so live
## density is exactly grass + trees and prefetch (0.5) is half of that.
## Re-pinned 2026-10-22 when region grass dropped from the Foliage export
## default (700) to the zone table (deliberate: spawn-cost budget).
const LIVE_FOLIAGE_GRAPHICS := 350 + 40
const PREFETCH_FOLIAGE_GRAPHICS := 175 + 20

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

## Drains spawns, frees AND the deferred grass batches (one per idle drain).
func _drain_all(dresser: RegionDresser) -> void:
	for _i in range(128):
		dresser.drain_pending()
		if dresser.pending_spawn_count() == 0 and dresser.pending_free_count() == 0 and dresser.pending_grass_count() == 0:
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

## The shared map-wide RoadNetwork is handed to EVERY region's scatterer whole
## (never a region-local subset), so roadside dressing can be sampled from any
## corridor the map has, and each region still dresses its own patch.
func _props_of(dresser: RegionDresser, loc: Vector2i) -> PropScatterer:
	var node: Node3D = dresser.region_node(loc)
	if node == null:
		return null
	return node.get_node_or_null(RegionDresser.PROPS_CHILD_NAME) as PropScatterer

func _road_network() -> RoadNetwork:
	var network := RoadNetwork.new()
	network.add_road_def(RoadDef.make(RoadDef.Tier.HIGHWAY, _corridor_points(SPAWN.z), "hw", false))
	network.add_road_def(RoadDef.make(RoadDef.Tier.DIRT, _corridor_points(SPAWN.z + 400.0), "dirt", false))
	add_child(network)
	_tracked_nodes.append(network)
	return network

## A corridor running straight through the spawn region (a real corridor is
## bounded, not a world-spanning line, so the roadside sampler can reach it).
func _corridor_points(z: float) -> Array[Vector3]:
	return [Vector3(SPAWN.x - 400.0, 0.0, z), Vector3(SPAWN.x + 700.0, 0.0, z)]

## test (j): every dressed region gets the SHARED whole-map network, and its
## scatterer samples roadside dressing from the full corridor set.
func test_dressed_scatterers_receive_the_shared_road_network() -> void:
	var roads := _road_network()
	var dresser := _make_dresser(8)
	dresser.road_network = roads
	dresser.sync_player_pos(SPAWN)
	_drain_all(dresser)
	assert_that(dresser.dressed_region_count()).is_equal(25)
	for loc: Vector2i in _ring_locs(Vector2i(0, 0)):
		var props := _props_of(dresser, loc)
		assert_object(props).is_not_null()
		if props == null:
			continue
		assert_that(props.road_network).is_equal(roads)
		assert_int(props.roadside_road_count()).is_equal(roads.get_road_defs().size())
		assert_float(props.roadside_fraction).is_greater(0.0)

## test (k): with a corridor under the spawn, a live region's props land partly
## ALONGSIDE the road instead of only in the open annulus, and every single prop
## still clears the carriageway (half-width + margin).
func test_dressed_props_cluster_along_the_road() -> void:
	var roads := _road_network()
	var dresser := _make_dresser(8)
	dresser.road_network = roads
	dresser.sync_player_pos(SPAWN)
	_drain_all(dresser)
	var props := _props_of(dresser, Vector2i(0, 0))
	assert_object(props).is_not_null()
	if props == null:
		return
	var defs: Array[RoadDef] = roads.get_road_defs()
	var placed: PackedVector3Array = props.get_instance_positions()
	assert_int(placed.size()).is_greater(0)
	var roadside := 0
	for local_pos: Vector3 in placed:
		var world: Vector3 = props.to_global(local_pos)
		var info := PropScatterer.road_clearance_info(world, defs)
		var distance := float(info["distance"])
		assert_that(distance).is_greater_equal(float(info["half_width"]) + PropScatterer.ROAD_CLEARANCE_MARGIN - 0.001)
		if distance <= props.roadside_max_dist + 0.001:
			roadside += 1
	assert_int(roadside).is_greater(placed.size() / 4)


## test (l): zones follow the biome map (natural centre height + coast weight)
## with the same thresholds as the ground texture bake; never "festival".
func test_region_zone_follows_biomes() -> void:
	assert_str(RegionDresser.region_zone(MASTER_TEST, Vector2i(0, 0))).is_equal("lowlands")
	var peak: Vector2 = TerrainBaker.DOME_FAMILY[0]["center"]
	assert_str(RegionDresser.region_zone(MASTER_TEST, Vector2i(floori(peak.x / REGION_CELL), floori(peak.y / REGION_CELL)))).is_equal("alpine")
	var coast := TerrainBaker.BIOME_COAST_CENTER
	assert_str(RegionDresser.region_zone(MASTER_TEST, Vector2i(floori(coast.x / REGION_CELL), floori(coast.y / REGION_CELL)))).is_equal("coast")
	for dx in range(0, 40, 3):
		for dz in range(-12, 34, 3):
			assert_str(RegionDresser.region_zone(MASTER_TEST, Vector2i(dx, dz))).is_not_equal("festival")

## test (m): region kits are natural props only (no racing kit in the
## countryside) and tile the region cell as a square.
func test_region_preset_is_natural_and_square() -> void:
	for zone in ["lowlands", "coast", "highlands", "alpine"]:
		var preset: Dictionary = RegionDresser.region_preset(zone)
		assert_float(float(preset["square_half_extent"])).is_equal(REGION_CELL * 0.5)
		var props: Dictionary = preset["props"]
		assert_int(props.size()).is_greater(0)
		for key: String in props.keys():
			assert_array(["rock", "power_pole"]).contains([key])

## test (n): every dressed instance stays inside its own 256 m cell (square
## placement, no overlap with the neighbours), and the live zone counts apply.
func test_region_kit_stays_inside_its_cell() -> void:
	var dresser := _make_dresser(8)
	dresser.sync_player_pos(SPAWN)
	_drain_all(dresser)
	var half := REGION_CELL * 0.5 + 0.001
	for loc: Vector2i in [Vector2i(0, 0), Vector2i(1, -1), Vector2i(-2, 2)]:
		var positions := _positions_of(dresser, loc)
		assert_int(positions.size()).is_greater(0)
		for p: Vector3 in positions:
			assert_float(absf(p.x)).is_less_equal(half)
			assert_float(absf(p.z)).is_less_equal(half)

## test (o): with a seeder attached, a region is only dressed once its terrain
## bake is cached (props sit on the real carved ground); the other queued
## regions keep waiting without stalling the queue.
func test_spawn_waits_for_the_seeder_bake() -> void:
	var seeder := _make_seeder()
	var dresser := RegionDresser.new()
	dresser.terrain_seeder = seeder
	dresser.max_dresses_per_frame = 4
	add_child(dresser)
	dresser.set_process(false)
	_tracked_nodes.append(dresser)
	dresser.sync_player_pos(SPAWN)
	dresser.drain_pending()
	assert_int(dresser.dressed_region_count()).is_equal(0)
	assert_int(dresser.pending_spawn_count()).is_equal(25)
	var img: Image = TerrainBaker.new().bake_region(Vector2i(1, 0), 1.0, 32, [])
	seeder._baked[Vector2i(1, 0)] = {"image": img, "color": null, "height_min": 0.0, "height_max": 1.0}
	dresser.drain_pending()
	assert_int(dresser.dressed_region_count()).is_equal(1)
	assert_bool(dresser.is_dressed(Vector2i(1, 0))).is_true()
	assert_int(dresser.pending_spawn_count()).is_equal(24)

## test (p): dressing heights come from the cached bake of whichever region
## contains the point, and fall back to the natural height when uncached.
func test_ground_height_uses_the_containing_region_bake() -> void:
	var seeder := _make_seeder()
	var dresser := _make_dresser(2)
	dresser.terrain_seeder = seeder
	var loc := Vector2i(1, 0)
	var img: Image = TerrainBaker.new().bake_region(loc, 1.0, 256, [])
	seeder._baked[loc] = {"image": img, "color": null, "height_min": 0.0, "height_max": 1.0}
	var wx := REGION_CELL + 40.5
	var wz := 100.5
	assert_float(dresser.ground_height_at(wx, wz)).is_equal(float(img.get_pixel(40, 100).r))
	var far_x := REGION_CELL * 9.0 + 10.0
	assert_float(dresser.ground_height_at(far_x, wz)).is_equal_approx(TerrainBaker.new().natural_height_at(far_x, wz), 0.0001)

## test (q): foliage never grows in a landmark clearing, above the treeline or
## on beach sand; open lowland is allowed.
func test_foliage_filter_clearings_treeline_and_beach() -> void:
	var dresser := _make_dresser(2)
	var zones: Array[Vector3] = [Vector3(128.0, 128.0, 150.0)]
	dresser.clear_zones = zones
	assert_bool(dresser.foliage_allowed_at(130.0, 120.0)).is_false()
	assert_bool(dresser.foliage_allowed_at(900.0, 600.0)).is_true()
	var peak: Vector2 = TerrainBaker.DOME_FAMILY[0]["center"]
	assert_bool(dresser.foliage_allowed_at(peak.x, peak.y)).is_false()
	var coast := TerrainBaker.BIOME_COAST_CENTER
	assert_bool(dresser.foliage_allowed_at(coast.x, coast.y)).is_false()

## test (r): a cleared spawn region drops its foliage instead of piling it
## onto the hub, while the uncleared neighbours keep theirs.
func test_clear_zone_empties_the_hub_region_foliage() -> void:
	var dresser := _make_dresser(8)
	var zones: Array[Vector3] = [Vector3(128.0, 128.0, 400.0)]
	dresser.clear_zones = zones
	dresser.sync_player_pos(SPAWN)
	_drain_all(dresser)
	assert_int(_foliage_count(dresser, Vector2i(0, 0))).is_equal(0)
	assert_int(_foliage_count(dresser, Vector2i(2, 2))).is_greater(0)

## test (s): every dressed batch has a draw distance (grass shortest), so the
## 25-region band only submits the batches near the camera.
func test_dressed_batches_have_draw_distances() -> void:
	var dresser := _make_dresser(8)
	dresser.sync_player_pos(SPAWN)
	_drain_all(dresser)
	var node: Node3D = dresser.region_node(Vector2i(0, 0))
	assert_object(node).is_not_null()
	if node == null:
		return
	var seen := 0
	for holder: Node in node.get_children():
		for child in holder.get_children():
			var gi := child as GeometryInstance3D
			if gi == null:
				continue
			seen += 1
			assert_float(gi.visibility_range_end).is_greater(0.0)
			if String(gi.name) == "GrassMMI":
				assert_float(gi.visibility_range_end).is_equal(RegionDresser.GRASS_DRAW_DISTANCE)
	assert_int(seen).is_greater(1)

## test (t): grass is deferred to a later drain that dressed nothing else, so
## a region's props + trees and its grass never cost the same frame; nearest
## regions get theirs first.
func test_grass_is_built_on_a_later_idle_drain() -> void:
	var dresser := _make_dresser(1)
	dresser.sync_player_pos(SPAWN)
	dresser.drain_pending()
	var node: Node3D = dresser.region_node(Vector2i(0, 0))
	assert_object(node).is_not_null()
	if node == null:
		return
	var foliage: Foliage = node.get_node_or_null(RegionDresser.FOLIAGE_CHILD_NAME) as Foliage
	assert_bool(foliage.has_grass_batch()).is_false()
	assert_int(dresser.pending_grass_count()).is_equal(1)
	for _i in range(24):
		dresser.drain_pending()
	assert_int(dresser.pending_spawn_count()).is_equal(0)
	assert_bool(foliage.has_grass_batch()).is_false()
	assert_int(dresser.pending_grass_count()).is_equal(25)
	# Time-sliced: a live lowland region needs ceil(grass / grass_tufts_per_frame)
	# idle drains, never all of it in one frame.
	var grass: int = int(RegionDresser.ZONE_FOLIAGE["lowlands"]["grass"])
	var slices := ceili(float(grass) / float(dresser.grass_tufts_per_frame))
	assert_int(slices).is_greater(1)
	for _i in range(slices - 1):
		dresser.drain_pending()
		assert_bool(foliage.has_grass_batch()).is_false()
	dresser.drain_pending()
	assert_bool(foliage.has_grass_batch()).is_true()
	assert_int(dresser.pending_grass_count()).is_equal(24)
	# Sliced or not, the batch is identical to a one-shot build of the same stream.
	var sliced := foliage.get_batch_positions("GrassMMI")
	foliage.build_grass()
	assert_that(foliage.get_batch_positions("GrassMMI")).is_equal(sliced)

## test (u): with a seeder, only live-ring dressing is drawn (terrain exists
## only there; prefetch trees would float over the flat background), while the
## prefetch band stays generated. Without a seeder everything is drawn.
func test_only_live_ring_dressing_is_shown_with_a_seeder() -> void:
	var seeder := _make_seeder()
	var dresser := RegionDresser.new()
	dresser.terrain_seeder = seeder
	dresser.max_dresses_per_frame = 8
	add_child(dresser)
	dresser.set_process(false)
	_tracked_nodes.append(dresser)
	for loc: Vector2i in [Vector2i(0, 0), Vector2i(2, 0)]:
		var img: Image = TerrainBaker.new().bake_region(loc, 1.0, 32, [])
		seeder._baked[loc] = {"image": img, "color": null, "height_min": 0.0, "height_max": 1.0}
	dresser.sync_player_pos(SPAWN)
	dresser.drain_pending()
	var live: Node3D = dresser.region_node(Vector2i(0, 0))
	var pref: Node3D = dresser.region_node(Vector2i(2, 0))
	assert_object(live).is_not_null()
	assert_object(pref).is_not_null()
	if live == null or pref == null:
		return
	assert_bool(live.visible).is_true()
	assert_bool(pref.visible).is_false()
	assert_int(pref.get_child_count()).is_equal(2)
	assert_bool(_make_dresser(1).band_shown(RegionDresser.BAND_PREFETCH)).is_true()