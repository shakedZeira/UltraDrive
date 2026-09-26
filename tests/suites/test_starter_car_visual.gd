# tests/suites/test_starter_car_visual.gd
extends GdUnitTestSuite

## Roadmap #1: the starter Striker (resources/cars/starter_car.tres) ships NO
## visual_path, so the player controller falls back to its DEFAULT_VISUAL
## constant. If that constant ever pointed at a missing/empty resource the
## first launch would render an INVISIBLE car with no error -- this gate locks
## both halves: the resolver never returns an empty string, and the resource it
## resolves to actually loads, instantiates and carries real geometry.
## Headless-stable: the GLB is loaded + instantiated with no scene tree (same
## collision-safe pattern as tests/suites/test_cc0_cars.gd).

const PlayerCarScript: GDScript = preload("res://scripts/player/player_car_controller.gd")

const STARTER_RESOURCE := "res://resources/cars/starter_car.tres"
const SPORTS_COUPE_VISUAL := "res://assets/cars/sports_coupe.glb"

var _managed_nodes: Array = []

func before_test() -> void:
	_managed_nodes.clear()

func after_test() -> void:
	for node in _managed_nodes:
		if is_instance_valid(node):
			node.free()
	_managed_nodes.clear()

func _instantiate(path: String) -> Node3D:
	var scene := load(path) as PackedScene
	assert_that(scene).is_not_null()
	var instance: Node3D = scene.instantiate() as Node3D
	assert_that(instance).is_not_null()
	_managed_nodes.append(instance)
	return instance

func _mesh_instance_count(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		count += 1
	for child: Node in node.get_children():
		count += _mesh_instance_count(child)
	return count

func _car_config_paths() -> Array[String]:
	var dir := DirAccess.open("res://resources/cars")
	var paths: Array[String] = []
	if dir == null:
		return paths
	for name: String in dir.get_files():
		if name.ends_with(".tres"):
			paths.append("res://resources/cars/" + name)
	paths.sort()
	return paths

func test_default_visual_constant_is_the_sports_coupe_glb() -> void:
	assert_that(PlayerCarScript.default_visual_path()).is_equal(SPORTS_COUPE_VISUAL)
	assert_bool(ResourceLoader.exists(PlayerCarScript.default_visual_path())).is_true()

func test_default_visual_loads_and_instantiates_with_real_geometry() -> void:
	# The whole point of the fallback: whatever it names must be a loadable
	# PackedScene that instantiates to something visible under the chase cam.
	var visual_path: String = PlayerCarScript.default_visual_path()
	var scene := load(visual_path)
	assert_that(scene).is_not_null()
	assert_that(scene is PackedScene).is_true()
	var instance := _instantiate(visual_path)
	assert_that(_mesh_instance_count(instance)).is_greater(0)
	CarVisuals.apply_paint(instance, CarVisuals.DEFAULT_PAINT)
	assert_int(CarVisuals.paint_surface_count(instance)).is_greater(0)

func test_empty_visual_path_falls_back_instead_of_rendering_nothing() -> void:
	var empty_config := CarConfig.new()
	empty_config.visual_path = ""
	var from_empty: String = PlayerCarScript.resolve_visual_path(empty_config)
	var from_null: String = PlayerCarScript.resolve_visual_path(null)
	var fallback: String = PlayerCarScript.default_visual_path()
	assert_that(from_empty).is_equal(fallback)
	assert_that(from_null).is_equal(fallback)
	assert_that(fallback).is_not_empty()

func test_starter_striker_resolves_to_a_loadable_visual() -> void:
	var starter := load(STARTER_RESOURCE) as CarConfig
	assert_that(starter).is_not_null()
	var resolved: String = PlayerCarScript.resolve_visual_path(starter)
	assert_that(resolved).is_not_empty()
	assert_bool(ResourceLoader.exists(resolved)).is_true()
	var scene := load(resolved) as PackedScene
	assert_that(scene).is_not_null()
	var instance := _instantiate(resolved)
	assert_that(_mesh_instance_count(instance)).is_greater(0)

func test_every_shipped_car_tres_resolves_to_an_existing_visual() -> void:
	# Guards the whole garage, not just the starter: a config whose resolved
	# visual path is empty or missing is an invisible car waiting to happen.
	var paths := _car_config_paths()
	assert_int(paths.size()).is_greater_equal(6)
	for path: String in paths:
		var config := load(path) as CarConfig
		assert_that(config).is_not_null()
		var resolved: String = PlayerCarScript.resolve_visual_path(config)
		assert_that(resolved).is_not_empty()
		assert_bool(ResourceLoader.exists(resolved)).is_true()

func test_visual_path_override_still_wins_over_the_fallback() -> void:
	var custom := CarConfig.new()
	custom.visual_path = "res://assets/cars/muscle_car.glb"
	var resolved: String = PlayerCarScript.resolve_visual_path(custom)
	assert_that(resolved).is_equal("res://assets/cars/muscle_car.glb")
	assert_bool(ResourceLoader.exists(resolved)).is_true()
