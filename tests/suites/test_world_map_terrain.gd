# tests/suites/test_world_map_terrain.gd
extends GdUnitTestSuite

## Graphics-gap item 9: the pause map's terrain composite. All terrain math
## lives in MapRoads as pure/deterministic statics so the exact channel
## orderings can be asserted headlessly (no Terrain3D required). Map-level tests
## inject a fake height provider and never touch the streamed open world, so the
## suite is leak-free and deterministic.

const WORLD_MAP_SCRIPT := "res://scripts/ui/world_map.gd"
const CELLS := 64

func _fake_height_provider(constant: float) -> Callable:
	return func(xz: Vector2) -> float:
		return constant

func test_biome_color_water_below_level_is_blue() -> void:
	var c := MapRoads.biome_color(-4.0)
	assert_that(c.b).is_greater(c.g)
	assert_that(c.g).is_greater(c.r)
	# Deeper water is darker but stays in the blue family.
	assert_that(MapRoads.biome_color(-6.0).b).is_less(c.b)

func test_biome_color_vegetated_band_is_green() -> void:
	var c := MapRoads.biome_color(25.0)
	assert_that(c.g).is_greater(c.r)
	assert_that(c.g).is_greater(c.b)

func test_biome_color_highland_above_alpine_is_brown() -> void:
	# Brown/grey alpine band: red dominant, and greener energy has faded out of
	# the vegetated band below it.
	var alpine := MapRoads.biome_color(400.0)
	assert_that(alpine.r).is_greater_equal(alpine.g)
	assert_that(alpine.g).is_greater(alpine.b)
	assert_that(alpine.g).is_less(MapRoads.biome_color(25.0).g)
	var rock := MapRoads.biome_color(600.0)
	assert_that(rock.r).is_greater(rock.g)
	assert_that(rock.g).is_greater(rock.b)
	# Snow cap near-white at the top of the ladder.
	var snow := MapRoads.biome_color(800.0)
	assert_that(snow.r).is_greater(0.7)
	assert_that(snow.g).is_greater(0.7)
	assert_that(snow.b).is_greater(0.7)

func test_biome_color_gradient_is_smooth_across_bands() -> void:
	var a := MapRoads.biome_color(5.0)
	var b := MapRoads.biome_color(5.01)
	assert_float(a.r - b.r).is_between(-0.001, 0.001)
	assert_float(a.g - b.g).is_between(-0.001, 0.001)
	assert_float(a.b - b.b).is_between(-0.001, 0.001)

func test_hillshade_energy_positive_and_monotonic_in_slope() -> void:
	# Flat ground keeps the color unchanged.
	assert_float(MapRoads.hillshade_energy(0.0, 0.0)).is_equal_approx(1.0, 0.001)
	# Never negative for any slope; bounded by the strength.
	assert_that(MapRoads.hillshade_energy(1000.0, 0.0)).is_greater(0.0)
	assert_that(MapRoads.hillshade_energy(-1000.0, 0.0)).is_greater(0.0)
	assert_float(MapRoads.hillshade_energy(1000.0, 0.0)).is_equal_approx(1.0 - MapRoads.HILLSHADE_STRENGTH, 0.001)
	# Monotonic: falling away from the NW light darkens, rising toward it brightens.
	assert_that(MapRoads.hillshade_energy(5.0, 0.0)).is_less(MapRoads.hillshade_energy(0.0, 0.0))
	assert_that(MapRoads.hillshade_energy(0.0, -5.0)).is_greater(MapRoads.hillshade_energy(5.0, 0.0))
	assert_that(MapRoads.hillshade_energy(5.0, 5.0)).is_less(MapRoads.hillshade_energy(-5.0, -5.0))

func test_height_provider_resolves_duck_typed_terrain_data() -> void:
	var root := Node.new()
	root.name = "TerrainResolverRoot"
	add_child(root)

	var data_script := GDScript.new()
	data_script.source_code = "extends RefCounted\n\nfunc get_height(p: Vector3) -> float:\n\treturn p.x * 2.0\n"
	data_script.reload()
	var data := RefCounted.new()
	data.set_script(data_script)

	var terrain_script := GDScript.new()
	terrain_script.source_code = "extends Node\n\nvar data = null\n"
	terrain_script.reload()
	var terrain := Node.new()
	terrain.name = "Terrain3D"
	terrain.set_script(terrain_script)
	terrain.set("data", data)
	root.add_child(terrain)

	var provider := MapRoads.height_from_terrain(root)
	assert_that(provider.is_valid()).is_true()
	if provider.is_valid():
		assert_float(float(provider.call(Vector2(10.0, 4.0)))).is_equal_approx(20.0, 0.001)
	root.free()

func test_terrain_cells_align_with_world_to_screen_fit() -> void:
	var content: Array = [Vector3(0.0, 0.0, 0.0), Vector3(800.0, 0.0, 600.0)]
	var fit := MapRoads.compute_fit(content, Vector3(400.0, 0.0, 300.0), Vector2(256.0, 256.0), 16.0)
	var provider := _fake_height_provider(10.0)
	var cells := MapRoads.terrain_cells(fit, provider, 8, 6)
	assert_that(cells.size()).is_equal(48)

	var screen_center: Vector2 = MapRoads.world_to_screen(Vector3(400.0, 0.0, 300.0), fit)
	var found := {}
	for cell in cells:
		if (cell["rect"] as Rect2).has_point(screen_center):
			found = cell
			break
	assert_that(found.is_empty()).is_false()
	if not found.is_empty():
		# Flat height: shade==1.0, so the cell must be the exact biome color.
		var cell_color: Color = found["color"]
		var expected: Color = MapRoads.biome_color(10.0)
		assert_float(cell_color.r).is_equal_approx(expected.r, 0.001)
		assert_float(cell_color.g).is_equal_approx(expected.g, 0.001)
		assert_float(cell_color.b).is_equal_approx(expected.b, 0.001)

func test_map_without_height_source_keeps_roads() -> void:
	VehicleManager.player_car = null
	var root := Node.new()
	root.name = "MapNoTerrainRoot"
	add_child(root)
	var network := RoadNetwork.new()
	network.name = "RoadNetwork"
	network.add_road([
		Vector3(0.0, 0.0, 0.0),
		Vector3(300.0, 0.0, 0.0),
		Vector3(300.0, 0.0, 300.0),
	], 8.0, false)
	root.add_child(network)

	var map := Control.new()
	map.name = "WorldMap"
	map.size = Vector2(512.0, 384.0)
	map.set_script(load(WORLD_MAP_SCRIPT))
	root.add_child(map)
	await await_idle_frame()
	map._rebuild()

	# No terrain source anywhere -> composite is skipped, roads still resolve.
	assert_that(MapRoads.height_from_terrain(map).is_valid()).is_false()
	assert_that(map._terrain_cells.is_empty()).is_true()
	assert_that(map._paths.size()).is_greater_equal(1)
	root.free()

func test_map_draws_terrain_cells_under_roads_with_provider() -> void:
	VehicleManager.player_car = null
	var root := Node.new()
	root.name = "MapTerrainRoot"
	add_child(root)
	var network := RoadNetwork.new()
	network.name = "RoadNetwork"
	network.add_road([
		Vector3(0.0, 0.0, 0.0),
		Vector3(300.0, 0.0, 0.0),
		Vector3(300.0, 0.0, 300.0),
	], 8.0, false)
	root.add_child(network)

	var map := Control.new()
	map.name = "WorldMap"
	map.size = Vector2(512.0, 384.0)
	map.set_script(load(WORLD_MAP_SCRIPT))
	map.height_provider = _fake_height_provider(12.0)
	root.add_child(map)
	await await_idle_frame()
	map._rebuild()

	assert_that(map._terrain_cells.size()).is_equal(CELLS * CELLS)
	assert_that(map._paths.size()).is_greater_equal(1)
	# Constant height -> flat ground -> every cell is exactly the biome color.
	var cell_color: Color = map._terrain_cells[0]["color"]
	var expected: Color = MapRoads.biome_color(12.0)
	assert_float(cell_color.r).is_equal_approx(expected.r, 0.001)
	assert_float(cell_color.g).is_equal_approx(expected.g, 0.001)
	assert_float(cell_color.b).is_equal_approx(expected.b, 0.001)
	root.free()