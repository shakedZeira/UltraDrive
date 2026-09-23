# tests/suites/test_full_world_height.gd
extends GdUnitTestSuite

## No-pop-in preload for the pause map: the map must read heights from
## TerrainBaker's deterministic full-world field (bake_full_height_image /
## natural_height_at) so mountains are visible across the whole driveable world
## with an empty streamed ring. The streamed ring returns 0.0 for unbaked
## regions (terra_seeder.baked_region_height -> 0.0), which used to paint the
## map water-blue until the player drove close enough to stream/bake them.

const WORLD_MAP_SCRIPT := "res://scripts/ui/world_map.gd"
const CELLS := 64

func test_natural_height_at_is_deterministic_and_clamped() -> void:
	var baker := TerrainBaker.new()
	var a := baker.natural_height_at(7800.0, 6400.0)
	var b := baker.natural_height_at(7800.0, 6400.0)
	assert_float(a).is_equal_approx(b, 0.0001)
	assert_that(is_finite(a)).is_true()
	assert_float(a).is_between(TerrainBaker.HEIGHT_MIN, TerrainBaker.HEIGHT_MAX)

## Distant alpine dome (7800, 6400) must read > 700 (snow band on the map) even
## though it is far outside any streamed ring -- the preload's whole point.
func test_natural_height_at_reads_distant_mountains() -> void:
	var baker := TerrainBaker.new()
	assert_float(baker.natural_height_at(7800.0, 6400.0)).is_greater(700.0)

func test_full_height_image_is_deterministic() -> void:
	var baker := TerrainBaker.new()
	var world_min := Vector2(-512.0, -1024.0)
	var world_max := Vector2(9716.0, 8612.0)
	var img_a := baker.bake_full_height_image(world_min, world_max, 32, 32)
	var img_b := baker.bake_full_height_image(world_min, world_max, 32, 32)
	assert_that(img_a.get_data()).is_equal(img_b.get_data())

func test_full_height_image_covers_extents_and_matches_natural_sampler() -> void:
	var world_min := Vector2(-512.0, -1024.0)
	var world_max := Vector2(9716.0, 8612.0)
	var baker := TerrainBaker.new()
	var img := baker.bake_full_height_image(world_min, world_max, 32, 32)
	assert_that(img.get_format()).is_equal(Image.FORMAT_RF)
	assert_that(img.get_width()).is_equal(32)
	assert_that(img.get_height()).is_equal(32)
	var span := world_max - world_min
	var texel := Vector2(span.x / 32.0, span.y / 32.0)
	for iy in 32:
		var wz := world_min.y + (float(iy) + 0.5) * texel.y
		for ix in 32:
			var wx := world_min.x + (float(ix) + 0.5) * texel.x
			var from_img := img.get_pixel(ix, iy).r
			var from_field := baker.natural_height_at(wx, wz)
			assert_float(from_img).is_equal_approx(from_field, 0.001)

## The preloaded field must agree with the RING bake (bake_region, no roads)
## at shared world points: both sample the same canonical biome/dome/fBm field,
## so the only differences are the ring's coarse bilerp + 3x3 blur -- well
## inside the pause map's ~2 m elevation tolerance.
func test_full_height_image_matches_ring_bake_away_from_roads() -> void:
	var baker := TerrainBaker.new()
	var loc := Vector2i(5, 3)
	var origin := Vector2(loc.x * 256.0, loc.y * 256.0)
	var ring := baker.bake_region(loc, 1.0, 256, [])
	var full := baker.bake_full_height_image(origin, origin + Vector2(256.0, 256.0), 256, 256)
	var ring_f := ring.get_data().to_float32_array()
	var full_f := full.get_data().to_float32_array()
	var max_diff := 0.0
	for i in ring_f.size():
		max_diff = maxf(max_diff, absf(ring_f[i] - full_f[i]))
	assert_float(max_diff).is_less_equal(2.0)

func test_height_from_image_reads_texels_and_edge_clamps() -> void:
	var baker := TerrainBaker.new()
	var world_min := Vector2(512.0, 512.0)
	var img := baker.bake_full_height_image(world_min, world_min + Vector2(256.0, 256.0), 4, 4)
	var texel := Vector2(64.0, 64.0)
	var provider := MapRoads.height_from_image(img, world_min, texel)
	assert_that(provider.is_valid()).is_true()
	# A texel-centre sample returns the exact baked texel value.
	var centre := world_min + Vector2(0.5, 0.5) * 64.0
	var direct := img.get_pixel(0, 0).r
	assert_float(float(provider.call(centre))).is_equal_approx(direct, 0.001)
	# Far out of range: edge-clamped to a texel, never an error.
	var out := float(provider.call(world_min - Vector2(20000.0, 20000.0)))
	assert_that(is_finite(out)).is_true()

## Regression for the reported bug: with a TerrainSeeder present but NOTHING
## cached (every baked_region_height returns 0.0 -- exactly the "empty ring"
## the player sees before approaching), the pause map must still render the
## distant alpine dome in the snow band instead of flat water blue.
func test_preloaded_map_shows_mountains_with_empty_ring_cache() -> void:
	VehicleManager.player_car = null
	var root := Node.new()
	root.name = "MapPreloadRoot"
	add_child(root)

	var seeder_script := GDScript.new()
	seeder_script.source_code = "extends Node\n\nfunc baked_region_height(_loc: Vector2i, _world_pos: Vector3) -> float:\n\treturn 0.0\n"
	seeder_script.reload()
	var empty_seeder := Node.new()
	empty_seeder.name = "EmptySeeder"
	empty_seeder.set_script(seeder_script)
	root.add_child(empty_seeder)

	var network := RoadNetwork.new()
	network.name = "RoadNetwork"
	network.add_road([
		Vector3(6000.0, 0.0, 6400.0),
		Vector3(8400.0, 0.0, 6400.0),
	], 8.0, false)
	root.add_child(network)

	var map := Control.new()
	map.name = "WorldMap"
	map.size = Vector2(512.0, 512.0)
	map.set_script(load(WORLD_MAP_SCRIPT))
	root.add_child(map)
	await await_idle_frame()
	map._rebuild()

	assert_that(map._terrain_cells.size()).is_equal(CELLS * CELLS)
	var brightest := 0.0
	for cell in map._terrain_cells:
		var c: Color = cell["color"]
		brightest = maxf(brightest, c.r + c.g + c.b)
	# Snow/rock band (>= ~700 m) is far brighter than the water blue / lowland
	# green the broken streamed reader painted for the emptiest parts of the map.
	assert_float(brightest).is_greater_equal(1.6)
	root.free()