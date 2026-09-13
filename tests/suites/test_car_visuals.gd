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