# tests/suites/test_cc0_cars.gd
extends GdUnitTestSuite

## CC0 (Kenney Car Kit) handcrafted car gate: every new car id resolves to a
## CarConfig resource whose visual GLB loads and instantiates, faces forward
## (+Z nose, front wheels Z>0 rear Z<0), carries four named wheel meshes that
## CarVisuals resolves per corner, and the garage owns all three immediately.

## collision-safe instantiation (no scene tree) + managed-node freeing so the
## suite is leak-free and headless (no frames).

const CC0_CARS := {
	"cc0_sedan_sports": {
		"resource": "res://resources/cars/cc0_sedan_sports.tres",
		"visual": "res://assets/cars/cc0_sedan_sports.glb",
		"car_class": "C",
		"timbre": "sport",
	},
	"cc0_hatchback_sports": {
		"resource": "res://resources/cars/cc0_hatchback_sports.tres",
		"visual": "res://assets/cars/cc0_hatchback_sports.glb",
		"car_class": "B",
		"timbre": "rally",
	},
	"cc0_race": {
		"resource": "res://resources/cars/cc0_race.tres",
		"visual": "res://assets/cars/cc0_race.glb",
		"car_class": "A",
		"timbre": "sport",
	},
}

const CC0_WHEEL_NODES := ["wheel-front-left", "wheel-front-right", "wheel-back-left", "wheel-back-right"]

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

func test_every_cc0_id_resolves_to_a_configured_car() -> void:
	for car_id: Variant in CC0_CARS.keys():
		var entry: Dictionary = CC0_CARS[car_id]
		var config := load(String(entry["resource"])) as CarConfig
		assert_that(config).is_not_null()
		assert_that(config.car_name).is_not_empty()
		assert_that(config.car_class).is_equal(entry["car_class"])
		assert_that(config.visual_path).is_equal(entry["visual"])
		assert_that(FileAccess.file_exists(config.visual_path)).is_true()
		assert_that(config.engine_timbre).is_equal(entry["timbre"])

func test_every_cc0_visual_instantiates_with_four_named_wheels() -> void:
	for car_id: Variant in CC0_CARS.keys():
		var entry: Dictionary = CC0_CARS[car_id]
		var instance := _instantiate(String(entry["visual"]))
		for wheel_name in CC0_WHEEL_NODES:
			var wheel := instance.get_node_or_null(wheel_name) as MeshInstance3D
			assert_that(wheel).is_not_null()
			assert_that(wheel.mesh).is_not_null()

func test_every_cc0_car_faces_forward_in_glb_space() -> void:
	for car_id: Variant in CC0_CARS.keys():
		var entry: Dictionary = CC0_CARS[car_id]
		var instance := _instantiate(String(entry["visual"]))
		var fl := instance.get_node_or_null("wheel-front-left") as MeshInstance3D
		var rl := instance.get_node_or_null("wheel-back-left") as MeshInstance3D
		assert_that(fl.transform.origin.z).is_greater(0.0)
		assert_that(rl.transform.origin.z).is_less(0.0)

func test_resolve_wheel_nodes_finds_four_corners_on_cc0_glb() -> void:
	for car_id: Variant in CC0_CARS.keys():
		var entry: Dictionary = CC0_CARS[car_id]
		var instance := _instantiate(String(entry["visual"]))
		var wheels: Dictionary = CarVisuals.resolve_wheel_nodes(instance, String(car_id))
		assert_that(wheels.size()).is_equal(4)
		for corner: Variant in ["fl", "fr", "rl", "rr"]:
			assert_that(wheels.has(corner)).is_true()
			assert_that((wheels.get(corner) as Array[Node3D]).size()).is_equal(1)

func test_garage_starts_with_all_cc0_cars() -> void:
	for car_id: Variant in CC0_CARS.keys():
		assert_that(Array(Garage.STARTER_CARS).has(car_id)).is_true()

func test_every_cc0_visual_paints_body_with_profile_color_and_dark_wheels() -> void:
	for car_id: Variant in CC0_CARS.keys():
		var entry: Dictionary = CC0_CARS[car_id]
		var instance := _instantiate(String(entry["visual"]))
		CarVisuals.apply_paint(instance, CarVisuals.paint_profile_for(String(car_id)))
		var body := instance.get_node_or_null("body") as MeshInstance3D
		assert_that(body).is_not_null()
		var body_paint: StandardMaterial3D = body.get_surface_override_material(0) as StandardMaterial3D
		assert_that(body_paint).is_not_null()
		assert_that(body_paint.albedo_color).is_equal(CarVisuals.PAINT_COLORS[car_id])
		assert_that(body_paint.clearcoat_enabled).is_true()
		assert_that(body_paint.metallic).is_equal_approx(0.92, 0.001)
		for wheel_name in CC0_WHEEL_NODES:
			var wheel := instance.get_node_or_null(wheel_name) as MeshInstance3D
			assert_that(wheel).is_not_null()
			var wheel_material: StandardMaterial3D = wheel.get_surface_override_material(0) as StandardMaterial3D
			assert_that(wheel_material).is_not_null()
			assert_that(wheel_material.albedo_color).is_equal(CarVisuals.CC0_WHEEL_COLOR)