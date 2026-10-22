# tests/suites/test_car_paint_materials.gd
extends GdUnitTestSuite

## Graphics-gap plan item 5 gate: GT7/FH6-style clearcoat paint response. Pins the
## retuned CarVisuals paint band (metallic 0.40-0.60, roughness 0.20-0.30 primary
## panel band, clearcoat, raised metallic_specular fresnel, albedo-tinted rim
## highlight), the tinted transparent glass response
## (DEFAULT_GLASS_COLOR tint, metallic 0.0 / roughness 0.05, TRANSPARENCY_ALPHA,
## refraction-free), taillight resolution preservation, and that rivals inherit the same tuned paint
## through both the rival_car.tscn RivalCarVisual GLB body and the GridSpawner
## tier-color builder. Pure material inspection, fully manual node construction —
## headless-safe, no frames.

const RIVAL_SCENE := "res://scenes/vehicle/rival_car.tscn"

var _managed_nodes: Array = []

func before_test() -> void:
	_managed_nodes.clear()
	RaceManager.rival_roster = []
	RaceManager.rival_centerline = []
	RaceManager.rival_vehicle_scene = null
	RaceManager.rival_spawner = Callable()
	RaceManager._spawned_rivals = []
	RaceManager.consume_pending_race()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

func after_test() -> void:
	for node in _managed_nodes:
		if is_instance_valid(node):
			node.free()
	_managed_nodes.clear()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

func _new_root() -> Node3D:
	var root := Node3D.new()
	_managed_nodes.append(root)
	return root

func _new_mesh_instance(material: StandardMaterial3D, material_name: String) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	material.resource_name = material_name
	mesh.surface_set_material(0, material)
	mesh_instance.mesh = mesh
	_managed_nodes.append(mesh_instance)
	return mesh_instance

## Total MeshInstance3D descendants under a node (0 for null). Proves the rival
## CarBody actually instanced real GLB geometry, not an empty box.
func _count_meshes(root: Node) -> int:
	if root == null:
		return 0
	var count := 0
	if root is MeshInstance3D:
		count += 1
	for child in root.get_children():
		count += _count_meshes(child)
	return count

func test_paint_carries_swatch_color_in_the_clearcoat_metallic_band() -> void:
	var root := _new_root()
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.78, 0.12, 0.16, 1.0)
	var paint_mi := _new_mesh_instance(paint, "Paint")
	root.add_child(paint_mi)

	CarVisuals.apply_paint(root, CarVisuals.paint_profile_for("cc0_sedan_sports"))

	var override: StandardMaterial3D = paint_mi.get_surface_override_material(0) as StandardMaterial3D
	assert_that(override).is_not_null()
	assert_that(override.albedo_color).is_equal(CarVisuals.PAINT_COLORS["cc0_sedan_sports"])
	assert_that(override.metallic).is_between(0.4, 0.6)
	assert_that(override.roughness).is_between(0.2, 0.3)
	assert_that(override.metallic_specular).is_equal_approx(0.75, 0.001)
	assert_that(override.clearcoat_enabled).is_true()
	assert_that(override.clearcoat).is_equal_approx(1.0, 0.001)
	assert_that(override.clearcoat_roughness).is_less_equal(0.05)

func test_paint_rim_highlight_is_enabled_and_tinted_with_the_swatch() -> void:
	var root := _new_root()
	var paint_mi := _new_mesh_instance(StandardMaterial3D.new(), "PaintWhite")
	root.add_child(paint_mi)

	CarVisuals.apply_paint(root, CarVisuals.DEFAULT_PAINT)

	var override: StandardMaterial3D = paint_mi.get_surface_override_material(0) as StandardMaterial3D
	assert_that(override.rim_enabled).is_true()
	assert_that(override.rim).is_equal_approx(0.22, 0.001)
	assert_that(override.rim_tint).is_equal_approx(0.6, 0.001)

func test_window_and_windshield_names_get_the_tinted_transparent_glass_response() -> void:
	var root := _new_root()
	var windshield_mi := _new_mesh_instance(StandardMaterial3D.new(), "Windshield")
	root.add_child(windshield_mi)
	var window_mi := _new_mesh_instance(StandardMaterial3D.new(), "Window")
	root.add_child(window_mi)

	CarVisuals.apply_paint(root, CarVisuals.DEFAULT_PAINT)

	var windshield_override: StandardMaterial3D = windshield_mi.get_surface_override_material(0) as StandardMaterial3D
	assert_that(windshield_override).is_not_null()
	assert_that(windshield_override.metallic).is_equal_approx(0.0, 0.001)
	assert_that(windshield_override.roughness).is_equal_approx(0.05, 0.001)
	assert_that(windshield_override.refraction_enabled).is_false()
	assert_that(windshield_override.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)
	# TRANSPARENCY_ALPHA only transmits while albedo alpha < 1 — a pane at
	# alpha 1.0 would silently render opaque again.
	assert_that(windshield_override.albedo_color.a).is_less(1.0)

	var window_override: StandardMaterial3D = window_mi.get_surface_override_material(0) as StandardMaterial3D
	assert_that(window_override).is_not_null()
	assert_that(window_override.metallic).is_equal_approx(0.0, 0.001)
	assert_that(window_override.roughness).is_equal_approx(0.05, 0.001)

func test_taillight_material_still_resolves_and_emits_after_paint() -> void:
	var root := _new_root()
	var taillight := StandardMaterial3D.new()
	root.add_child(_new_mesh_instance(taillight, "Taillight"))

	CarVisuals.apply_paint(root, CarVisuals.DEFAULT_PAINT)

	var found := CarVisuals.find_named_material(root, "taillight")
	assert_that(found).is_not_null()
	var light_override: StandardMaterial3D = root.get_child(0).get_surface_override_material(0) as StandardMaterial3D
	assert_that(light_override.metallic).is_equal_approx(0.0, 0.001)
	assert_that(light_override.roughness).is_equal_approx(0.12, 0.001)
	CarVisuals.apply_brake_glow(found, 1.0)
	assert_that(found.emission_enabled).is_true()
	assert_that(found.emission_energy_multiplier).is_equal_approx(CarVisuals.BRAKE_GLOW_MAX, 0.001)

	# Two-node rear cluster (the R35 shape): the plural collector ramps BOTH
	# clones through the same seam.
	var tail_l := _new_mesh_instance(StandardMaterial3D.new(), "Taillight")
	tail_l.name = "Taillight_L"
	root.add_child(tail_l)
	var tail_r := _new_mesh_instance(StandardMaterial3D.new(), "Taillight")
	tail_r.name = "Taillight_R"
	root.add_child(tail_r)
	CarVisuals.apply_paint(root, CarVisuals.DEFAULT_PAINT)
	var all := CarVisuals.find_named_materials(root, "taillight")
	assert_that(all.size()).is_equal(3)
	CarVisuals.apply_brake_glow_all(all, 1.0)
	for material: Variant in all:
		assert_that((material as StandardMaterial3D).emission_energy_multiplier).is_equal_approx(CarVisuals.BRAKE_GLOW_MAX, 0.001)

func test_cc0_wheel_already_painted_keeps_its_glossy_wheel_response() -> void:
	var root := _new_root()
	var wheel_mi := _new_mesh_instance(StandardMaterial3D.new(), "colormap")
	wheel_mi.name = "wheel-front-left"
	root.add_child(wheel_mi)

	CarVisuals.apply_paint(root, CarVisuals.paint_profile_for("cc0_hatchback_sports"))

	var override: StandardMaterial3D = wheel_mi.get_surface_override_material(0) as StandardMaterial3D
	assert_that(override).is_not_null()
	assert_that(override.albedo_color).is_equal(CarVisuals.CC0_WHEEL_COLOR)
	assert_that(override.metallic).is_equal_approx(0.5, 0.001)
	assert_that(override.roughness).is_equal_approx(0.32, 0.001)
	assert_that(override.clearcoat_enabled).is_true()
	assert_that(override.clearcoat).is_equal_approx(0.85, 0.001)

func test_rival_car_scene_hosts_a_real_glb_visual_not_a_box() -> void:
	var rival := (load(RIVAL_SCENE) as PackedScene).instantiate() as VehiclePhysics
	_managed_nodes.append(rival)
	add_child(rival)
	var body := rival.get_node_or_null("CarBody") as RivalCarVisual
	assert_that(body).is_not_null()
	if body == null:
		return
	# The placeholder BoxMesh is gone: CarBody instanced a real car GLB under
	# CAR_ORIENT with the shared tuned clearcoat paint profile applied.
	assert_that(body.visual_root()).is_not_null()
	assert_that(_count_meshes(body.visual_root())).is_greater(0)
	var profile := body.paint_profile()
	assert_that(float(profile["metallic"])).is_equal_approx(0.5, 0.001)
	assert_that(float(profile["roughness"])).is_equal_approx(0.25, 0.001)
	assert_that(float(profile["clearcoat"])).is_equal_approx(1.0, 0.001)
	assert_that(float(profile["clearcoat_roughness"])).is_equal_approx(0.04, 0.001)
	# Rear-light seam is wired on the rival too (the change makes rivals share the
	# player's brake-glow + reverse path): the default sports_coupe visual has one
	# taillight node, so one brake-ramp material that also carries the white reverse
	# cue. No reverse geometry is built any more.
	var tails := body.taillight_materials()
	assert_that(tails.size()).is_equal(1)
	if tails.is_empty():
		return
	var base: Color = tails[0].emission
	CarVisuals.apply_reverse_glow(tails, true)
	assert_that(tails[0].emission).is_equal(CarVisuals.REVERSE_LIGHT_COLOR)
	CarVisuals.apply_reverse_glow(tails, false)
	assert_that(tails[0].emission).is_equal(base)

func test_grid_spawner_paints_rivals_with_the_tuned_paint_response() -> void:
	var spawner := GridSpawner.new()
	_managed_nodes.append(spawner)
	add_child(spawner)
	var player := (load(RIVAL_SCENE) as PackedScene).instantiate() as VehiclePhysics
	_managed_nodes.append(player)
	add_child(player)

	var specs: Array[Dictionary] = [
		GridSpawner.build_spec(load("res://resources/cars/rally_hatch.tres") as CarConfig, "Expert"),
	]
	var centerline: Array[Vector3] = []
	var cars := spawner.build_grid(player, specs, centerline)
	assert_that(cars.size()).is_equal(1)
	if cars.is_empty():
		return
	var body := cars[0].get_node_or_null("CarBody") as RivalCarVisual
	assert_that(body).is_not_null()
	if body == null:
		return
	# The tier color now rides the GLB visual's paint profile (CarBody is a
	# RivalCarVisual, not a MeshInstance3D with material_override).
	assert_that(body.visual_root()).is_not_null()
	var profile := body.paint_profile()
	assert_that(profile["color"]).is_equal(CarVisuals.RIVAL_PALETTE["Expert"])
	assert_that(float(profile["metallic"])).is_equal_approx(0.5, 0.001)
	assert_that(float(profile["roughness"])).is_equal_approx(0.25, 0.001)
	assert_that(float(profile["clearcoat"])).is_equal_approx(1.0, 0.001)
	assert_that(float(profile["clearcoat_roughness"])).is_equal_approx(0.04, 0.001)