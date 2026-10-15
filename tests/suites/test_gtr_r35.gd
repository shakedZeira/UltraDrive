# tests/suites/test_gtr_r35.gd
extends GdUnitTestSuite

## Nissan GT-R R35 2017 — the first builder-generated car wired into the game.
## Locks the wiring contract: the config resolves and points at the GLB, the
## GLB faces +Z (nose) with Wheel_* hub empties exported at identity rotation
## on the correct corners (the game overwrites hub.rotation every frame), all
## four corners resolve through CarVisuals, the garage seeds the car, and the
## paint keeps the embedded Bayside Blue under the bare DEFAULT_PAINT profile.
## Headless/collision-safe: GLB loaded + instantiated with no scene tree (the
## test_cc0_cars.gd pattern), managed nodes freed in after_test.

const CAR_ID := "nissan_gt_r35_2017"
const CONFIG_PATH := "res://resources/cars/nissan_gt_r35_2017.tres"
const VISUAL_PATH := "res://assets/cars/nissan_gt-r_r35_2017.glb"
const HUB_NAMES: Array[String] = ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]

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

func test_config_is_valid_and_points_at_the_glb() -> void:
	var config := load(CONFIG_PATH) as CarConfig
	assert_that(config).is_not_null()
	assert_that(config.car_name).is_not_empty()
	assert_that(config.car_class).is_equal("A")
	assert_that(config.visual_path).is_equal(VISUAL_PATH)
	assert_bool(FileAccess.file_exists(config.visual_path)).is_true()
	assert_that(config.engine_timbre).is_equal("gtr")
	assert_that(config.engine_bed_set).is_equal("gtr")
	assert_that(config.get_engine_bed_set()).is_equal("gtr")
	assert_that(config.turbo_max_boost_bar).is_equal(1.8)
	assert_that(config.turbo_spool_time).is_equal(0.85)
	assert_that(config.turbo_blowdown_time).is_equal(0.35)
	assert_that(config.turbo_whine_gain).is_equal(1.0)
	assert_that(config.turbo_has_wastegate).is_true()

func test_glb_faces_forward_with_identity_wheel_hubs() -> void:
	var instance := _instantiate(VISUAL_PATH)
	var mesh_count := 0
	for hub_name: String in HUB_NAMES:
		var hub := instance.get_node_or_null(hub_name) as Node3D
		assert_that(hub).is_not_null()
		# apply_wheel_visuals assigns hub.rotation outright, so a non-identity
		# base rotation in the GLB would be silently destroyed at runtime.
		assert_that(hub.rotation).is_equal(Vector3.ZERO)
	var fl := instance.get_node_or_null("Wheel_FL") as Node3D
	var fr := instance.get_node_or_null("Wheel_FR") as Node3D
	var rl := instance.get_node_or_null("Wheel_RL") as Node3D
	var rr := instance.get_node_or_null("Wheel_RR") as Node3D
	# nose +Z => front hubs z > 0, rear hubs z < 0
	assert_that(fl.transform.origin.z).is_greater(0.0)
	assert_that(fr.transform.origin.z).is_greater(0.0)
	assert_that(rl.transform.origin.z).is_less(0.0)
	assert_that(rr.transform.origin.z).is_less(0.0)
	# nose +Z, up +Y => car's left is +X
	assert_that(fl.transform.origin.x).is_greater(0.0)
	assert_that(rl.transform.origin.x).is_greater(0.0)
	assert_that(fr.transform.origin.x).is_less(0.0)
	assert_that(rr.transform.origin.x).is_less(0.0)
	var headlight := instance.get_node_or_null("Headlight_L") as Node3D
	assert_that(headlight).is_not_null()
	assert_that(headlight.transform.origin.z).is_greater(0.0)
	var intake := instance.get_node_or_null("FrontIntake") as Node3D
	assert_that(intake).is_not_null()
	assert_that(intake.transform.origin.z).is_greater(0.0)
	for child: Node in instance.get_children():
		if child is MeshInstance3D:
			mesh_count += 1
	assert_that(mesh_count).is_greater(0)

func test_resolve_wheel_nodes_finds_four_corners() -> void:
	var instance := _instantiate(VISUAL_PATH)
	var wheels: Dictionary = CarVisuals.resolve_wheel_nodes(instance, CAR_ID)
	assert_that(wheels.size()).is_equal(4)
	for corner: Variant in ["fl", "fr", "rl", "rr"]:
		assert_that(wheels.has(corner)).is_true()
		assert_that((wheels.get(corner) as Array[Node3D]).size()).is_equal(1)

func test_garage_seeds_the_gt_r() -> void:
	assert_that(Array(Garage.STARTER_CARS).has(CAR_ID)).is_true()
	assert_that(Garage.get_price(CAR_ID)).is_equal(98000)

func test_paint_keeps_embedded_bayside_blue() -> void:
	# Unknown id => bare DEFAULT_PAINT clone: metallic/roughness/clearcoat are
	# profile-driven, the embedded GLB albedo survives (no profile "color").
	var instance := _instantiate(VISUAL_PATH)
	CarVisuals.apply_paint(instance, CarVisuals.paint_profile_for(CAR_ID))
	var body := instance.get_node_or_null("Body") as MeshInstance3D
	assert_that(body).is_not_null()
	var paint: StandardMaterial3D = body.get_surface_override_material(0) as StandardMaterial3D
	assert_that(paint).is_not_null()
	assert_that(paint.albedo_color.b).is_greater(paint.albedo_color.r)
	assert_that(paint.clearcoat_enabled).is_true()
	assert_that(paint.metallic).is_equal_approx(0.5, 0.001)
	assert_that(paint.roughness).is_equal_approx(0.25, 0.001)
	assert_that(paint.clearcoat_roughness).is_equal_approx(0.04, 0.001)
	assert_that(paint.metallic_specular).is_equal_approx(0.75, 0.001)
