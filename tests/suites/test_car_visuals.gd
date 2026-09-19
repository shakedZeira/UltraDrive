# tests/suites/test_car_visuals.gd
extends GdUnitTestSuite

## CarVisuals runtime paint-override coverage: DEFAULT_PAINT sanity, the
## recursive tree walk across a two-level hierarchy, per-part matching
## (paint/glass/rim/tire/trim/graphite), rally clearcoat forcing and unknown
## materials left untouched. Fully manual node construction — no scene or GLB
## instantiation (fast, deterministic, leak-free).

var _managed_nodes: Array = []

func before_test() -> void:
	_managed_nodes.clear()

func after_test() -> void:
	for node in _managed_nodes:
		if is_instance_valid(node):
			node.free()
	_managed_nodes.clear()

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

func test_apply_paint_on_two_level_tree_applies_clearcoat_paint_and_glass() -> void:
	var root := _new_root()
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(1.0, 0.2, 0.2, 1.0)
	var body_mi := _new_mesh_instance(paint, "Paint")
	root.add_child(body_mi)
	var sub := Node3D.new()
	root.add_child(sub)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.8, 0.9, 1.0, 0.5)
	var glass_mi := _new_mesh_instance(glass, "Glass")
	sub.add_child(glass_mi)

	CarVisuals.apply_paint(root, CarVisuals.DEFAULT_PAINT)

	var paint_override: StandardMaterial3D = body_mi.get_surface_override_material(0) as StandardMaterial3D
	assert_that(paint_override).is_not_null()
	assert_that(paint_override.metallic).is_equal_approx(0.92, 0.001)
	assert_that(paint_override.roughness).is_equal_approx(0.35, 0.001)
	assert_that(paint_override.clearcoat).is_equal_approx(1.0, 0.001)
	assert_that(paint_override.clearcoat_roughness).is_equal_approx(0.03, 0.001)
	assert_that(paint_override.clearcoat_enabled).is_true()
	assert_that(paint_override.albedo_color).is_equal(Color(1.0, 0.2, 0.2, 1.0))

	var glass_override: StandardMaterial3D = glass_mi.get_surface_override_material(0) as StandardMaterial3D
	assert_that(glass_override).is_not_null()
	assert_that(glass_override.roughness).is_equal_approx(0.1, 0.001)
	assert_that(glass_override.refraction_enabled).is_true()
	assert_that(glass_override.refraction_scale).is_equal_approx(0.05, 0.001)
	assert_that(glass_override.albedo_color).is_equal(Color(0.8, 0.9, 1.0, 0.5))

func test_apply_paint_matches_rim_tire_trim_and_graphite() -> void:
	var root := _new_root()
	var rim_mi := _new_mesh_instance(StandardMaterial3D.new(), "Rim")
	root.add_child(rim_mi)
	var rim_gunmetal_mi := _new_mesh_instance(StandardMaterial3D.new(), "RimGunmetal")
	root.add_child(rim_gunmetal_mi)
	var tire_mi := _new_mesh_instance(StandardMaterial3D.new(), "Tire")
	root.add_child(tire_mi)
	var trim_mi := _new_mesh_instance(StandardMaterial3D.new(), "Trim")
	root.add_child(trim_mi)
	var graphite_mi := _new_mesh_instance(StandardMaterial3D.new(), "Graphite")
	root.add_child(graphite_mi)
	var graphite_trim_mi := _new_mesh_instance(StandardMaterial3D.new(), "GraphiteTrim")
	root.add_child(graphite_trim_mi)

	CarVisuals.apply_paint(root, CarVisuals.DEFAULT_PAINT)

	var rim: StandardMaterial3D = rim_mi.get_surface_override_material(0) as StandardMaterial3D
	assert_that(rim.metallic).is_equal_approx(0.9, 0.001)
	assert_that(rim.roughness).is_equal_approx(0.15, 0.001)
	var rim_gunmetal: StandardMaterial3D = rim_gunmetal_mi.get_surface_override_material(0) as StandardMaterial3D
	assert_that(rim_gunmetal.metallic).is_equal_approx(0.9, 0.001)
	var tire: StandardMaterial3D = tire_mi.get_surface_override_material(0) as StandardMaterial3D
	assert_that(tire.metallic).is_equal_approx(0.0, 0.001)
	assert_that(tire.roughness).is_equal_approx(0.95, 0.001)
	var trim: StandardMaterial3D = trim_mi.get_surface_override_material(0) as StandardMaterial3D
	assert_that(trim.metallic).is_equal_approx(0.85, 0.001)
	assert_that(trim.roughness).is_equal_approx(0.45, 0.001)
	var graphite: StandardMaterial3D = graphite_mi.get_surface_override_material(0) as StandardMaterial3D
	assert_that(graphite.metallic).is_equal_approx(0.85, 0.001)
	var graphite_trim: StandardMaterial3D = graphite_trim_mi.get_surface_override_material(0) as StandardMaterial3D
	assert_that(graphite_trim.metallic).is_equal_approx(0.85, 0.001)
	assert_that(graphite_trim.roughness).is_equal_approx(0.45, 0.001)

func test_apply_paint_forces_clearcoat_on_rally_paint() -> void:
	var paint := StandardMaterial3D.new()
	paint.clearcoat_enabled = false
	var paint_mi := _new_mesh_instance(paint, "PaintWhite")
	var root := _new_root()
	root.add_child(paint_mi)

	CarVisuals.apply_paint(root, CarVisuals.DEFAULT_PAINT)

	var override: StandardMaterial3D = paint_mi.get_surface_override_material(0) as StandardMaterial3D
	assert_that(override).is_not_null()
	assert_that(override.clearcoat_enabled).is_true()
	assert_that(override.clearcoat).is_equal_approx(1.0, 0.001)
	assert_that(override.metallic).is_equal_approx(0.92, 0.001)
	assert_that(paint.clearcoat_enabled).is_false()

func test_apply_paint_leaves_unknown_materials_untouched() -> void:
	var carpet_mi := _new_mesh_instance(StandardMaterial3D.new(), "Carpet")
	var root := _new_root()
	root.add_child(carpet_mi)

	CarVisuals.apply_paint(root, CarVisuals.DEFAULT_PAINT)

	assert_that(carpet_mi.get_surface_override_material(0)).is_null()

func test_apply_paint_paints_colormap_cc0_body_and_dark_wheels() -> void:
	var root := _new_root()
	var body_mi := _new_mesh_instance(StandardMaterial3D.new(), "colormap")
	body_mi.name = "body"
	root.add_child(body_mi)
	var spoiler_mi := _new_mesh_instance(StandardMaterial3D.new(), "colormap")
	spoiler_mi.name = "spoiler"
	root.add_child(spoiler_mi)
	var wheel_mi := _new_mesh_instance(StandardMaterial3D.new(), "colormap")
	wheel_mi.name = "wheel-front-left"
	root.add_child(wheel_mi)

	CarVisuals.apply_paint(root, CarVisuals.paint_profile_for("cc0_sedan_sports"))

	var body_override: StandardMaterial3D = body_mi.get_surface_override_material(0) as StandardMaterial3D
	assert_that(body_override).is_not_null()
	assert_that(body_override.albedo_color).is_equal(CarVisuals.PAINT_COLORS["cc0_sedan_sports"])
	assert_that(body_override.metallic).is_equal_approx(0.92, 0.001)
	assert_that(body_override.clearcoat_enabled).is_true()

	var spoiler_override: StandardMaterial3D = spoiler_mi.get_surface_override_material(0) as StandardMaterial3D
	assert_that(spoiler_override).is_not_null()
	assert_that(spoiler_override.albedo_color).is_equal(CarVisuals.PAINT_COLORS["cc0_sedan_sports"])

	var wheel_override: StandardMaterial3D = wheel_mi.get_surface_override_material(0) as StandardMaterial3D
	assert_that(wheel_override).is_not_null()
	assert_that(wheel_override.albedo_color).is_equal(CarVisuals.CC0_WHEEL_COLOR)
	assert_that(wheel_override.metallic).is_equal_approx(0.25, 0.001)
	assert_that(wheel_override.roughness).is_equal_approx(0.6, 0.001)

func test_paint_profile_for_adds_color_only_for_known_cc0_cars() -> void:
	var cc0: Dictionary = CarVisuals.paint_profile_for("cc0_race")
	assert_that(cc0.has("color")).is_true()
	assert_that(cc0["color"]).is_equal(CarVisuals.PAINT_COLORS["cc0_race"])
	assert_that(cc0.has("glass_color")).is_true()
	assert_that(cc0["metallic"]).is_equal_approx(0.92, 0.001)
	var ai: Dictionary = CarVisuals.paint_profile_for("starter_car")
	assert_that(ai.has("color")).is_false()
	assert_that(ai.has("glass_color")).is_false()
	assert_that(CarVisuals.DEFAULT_PAINT.has("color")).is_false()

func test_default_paint_profile_values_are_sane() -> void:
	var profile: Dictionary = CarVisuals.DEFAULT_PAINT
	assert_that(profile["metallic"]).is_between(0.9, 0.95)
	assert_that(profile["roughness"]).is_between(0.3, 0.4)
	assert_that(profile["clearcoat"]).is_equal_approx(1.0, 0.001)
	assert_that(profile["clearcoat_roughness"]).is_less_equal(0.05)
	assert_that(profile["glass_roughness"]).is_equal_approx(0.1, 0.001)
	assert_that(profile["glass_refraction_scale"]).is_between(0.02, 0.1)
	assert_that(profile["tail_emission_strength"]).is_greater_equal(5.0)

func test_paint_surface_count_reports_set_overrides() -> void:
	var root := _new_root()
	var names: Array[String] = ["Paint", "Glass", "Rim", "Tire", "Trim"]
	for material_name in names:
		root.add_child(_new_mesh_instance(StandardMaterial3D.new(), material_name))
	var carpet_mi := _new_mesh_instance(StandardMaterial3D.new(), "Carpet")
	root.add_child(carpet_mi)

	assert_that(CarVisuals.paint_surface_count(root)).is_equal(0)

	CarVisuals.apply_paint(root, CarVisuals.DEFAULT_PAINT)

	assert_that(CarVisuals.paint_surface_count(root)).is_equal(5)
	assert_that(carpet_mi.get_surface_override_material(0)).is_null()

func test_wheel_groups_define_all_four_corners_for_every_car() -> void:
	for car_id: Variant in ["starter_car", "muscle_car", "rally_hatch", "cc0_sedan_sports", "cc0_hatchback_sports", "cc0_race"]:
		var corner_names: Dictionary = CarVisuals.WHEEL_GROUPS.get(car_id, {})
		for corner: Variant in ["fl", "fr", "rl", "rr"]:
			assert_that(corner_names.has(corner)).is_true()

func test_wheel_spin_rate_scales_speed_over_circumference() -> void:
	assert_that(CarVisuals.wheel_spin_rate(36.0, 0.33)).is_equal_approx(30.303, 0.01)
	assert_that(CarVisuals.wheel_spin_rate(0.0, 0.33)).is_equal(0.0)
	assert_that(CarVisuals.wheel_spin_rate(36.0, 0.0)).is_equal(0.0)

func _add_wheel(parent_node: Node3D, wheel_name: String) -> Node3D:
	var wheel_node := Node3D.new()
	wheel_node.name = wheel_name
	parent_node.add_child(wheel_node)
	_managed_nodes.append(wheel_node)
	return wheel_node

func test_resolve_wheel_nodes_returns_single_nodes_for_coupe() -> void:
	var root := _new_root()
	_add_wheel(root, "Wheel_FL")
	_add_wheel(root, "Wheel_FR")
	_add_wheel(root, "Wheel_RL")
	_add_wheel(root, "Wheel_RR")
	var wheels: Dictionary = CarVisuals.resolve_wheel_nodes(root, "starter_car")
	assert_that(wheels.size()).is_equal(4)
	assert_that((wheels.get("fl") as Array[Node3D]).size()).is_equal(1)
	assert_that((wheels.get("rr") as Array[Node3D]).size()).is_equal(1)

func test_resolve_wheel_nodes_builds_rim_and_tire_groups() -> void:
	var root := _new_root()
	_add_wheel(root, "Rim_LF")
	_add_wheel(root, "Tire_LF")
	_add_wheel(root, "Rim_RF")
	_add_wheel(root, "Tire_RF")
	_add_wheel(root, "Rim_LR")
	_add_wheel(root, "Tire_LR")
	_add_wheel(root, "Rim_RR")
	_add_wheel(root, "Tire_RR")
	var wheels: Dictionary = CarVisuals.resolve_wheel_nodes(root, "rally_hatch")
	assert_that(wheels.size()).is_equal(4)
	assert_that((wheels.get("fl") as Array[Node3D]).size()).is_equal(2)
	assert_that((wheels.get("rl") as Array[Node3D]).size()).is_equal(2)

func test_resolve_wheel_nodes_ignores_missing_and_unknown() -> void:
	var root := _new_root()
	_add_wheel(root, "Wheel_FL")
	var known: Dictionary = CarVisuals.resolve_wheel_nodes(root, "starter_car")
	assert_that(known.size()).is_equal(1)
	var unknown: Dictionary = CarVisuals.resolve_wheel_nodes(root, "unknown_car")
	assert_that(unknown.is_empty()).is_true()
	var empty_root: Dictionary = CarVisuals.resolve_wheel_nodes(null, "starter_car")
	assert_that(empty_root.is_empty()).is_true()

func test_apply_wheel_visuals_spins_all_and_steers_front_pair() -> void:
	var root := _new_root()
	var fl := _add_wheel(root, "Wheel_FL")
	var fr := _add_wheel(root, "Wheel_FR")
	var rl := _add_wheel(root, "Wheel_RL")
	var rr := _add_wheel(root, "Wheel_RR")
	var wheels: Dictionary = CarVisuals.resolve_wheel_nodes(root, "starter_car")
	CarVisuals.apply_wheel_visuals(wheels, 1.0, 0.5)
	assert_that(fl.rotation.x).is_equal_approx(-0.5, 0.001)
	assert_that(rl.rotation.x).is_equal_approx(-0.5, 0.001)
	assert_that(rr.rotation.x).is_equal_approx(-0.5, 0.001)
	assert_that(fl.rotation.y).is_equal_approx(CarVisuals.STEER_VISUAL_MAX_RAD, 0.001)
	assert_that(fr.rotation.y).is_equal_approx(CarVisuals.STEER_VISUAL_MAX_RAD, 0.001)
	assert_that(rl.rotation.y).is_equal(0.0)
	CarVisuals.apply_wheel_visuals(wheels, -1.0, -0.25)
	assert_that(fl.rotation.y).is_equal_approx(-CarVisuals.STEER_VISUAL_MAX_RAD, 0.001)
	assert_that(fl.rotation.x).is_equal_approx(0.25, 0.001)

func test_find_named_material_locates_taillight_on_tree() -> void:
	var root := _new_root()
	var material := StandardMaterial3D.new()
	root.add_child(_new_mesh_instance(material, "Taillight"))
	var found := CarVisuals.find_named_material(root, "taillight")
	assert_that(found).is_not_null()
	assert_that(found.resource_name).is_equal("Taillight")

func test_find_named_material_returns_null_when_absent() -> void:
	var root := _new_root()
	root.add_child(_new_mesh_instance(StandardMaterial3D.new(), "Paint"))
	assert_that(CarVisuals.find_named_material(root, "taillight")).is_null()

func test_apply_brake_glow_ramps_emission_energy_with_brake() -> void:
	var material := StandardMaterial3D.new()
	material.resource_name = "Taillight"
	material.emission_enabled = false
	CarVisuals.apply_brake_glow(material, 1.0)
	assert_that(material.emission_enabled).is_true()
	assert_that(material.emission_energy_multiplier).is_equal_approx(CarVisuals.BRAKE_GLOW_MAX, 0.001)
	CarVisuals.apply_brake_glow(material, 0.0)
	assert_that(material.emission_energy_multiplier).is_equal_approx(CarVisuals.BRAKE_GLOW_MIN, 0.001)