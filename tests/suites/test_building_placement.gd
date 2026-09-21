# tests/suites/test_building_placement.gd
extends GdUnitTestSuite

## P3/P2/P4 gate: imported CC0 real-mesh dressing (Kenney Racing Kit pit
## buildings + track props, Quaternius rocks) flows through the same generic
## PropScatterer the open-world RegionDresser drives, so placing a building
## preset proves: bounded, road-clear placement; every real-mesh type drawing
## its actual GLB mesh (not a fused primitive); and bit-identical placement on
## re-entry. Headless-safe: all loading + MultiMesh building is synchronous.

const ROAD_START := Vector3(-500.0, 0.0, -500.0)
const ROAD_END := Vector3(500.0, 0.0, 500.0)

func _roads() -> RoadNetwork:
	var roads := RoadNetwork.new()
	var pts: Array[Vector3] = []
	for i in range(17):
		var t := float(i) / 16.0
		pts.append(ROAD_START.lerp(ROAD_END, t))
	roads.add_road(pts, 12.0, false)
	return roads

func _building_preset() -> Dictionary:
	return {
		"radius": 300.0,
		"inner_clear_radius": 60.0,
		"seed": 5555,
		"road_threshold": 8.0,
		"props": {
			"pit_garage": {"count": 6, "min_spacing": 40.0, "scale": Vector2(6.0, 6.5)},
			"pit_office": {"count": 4, "min_spacing": 40.0, "scale": Vector2(6.0, 6.5)},
			"grandstand": {"count": 2, "min_spacing": 80.0, "scale": Vector2(8.0, 10.0)},
		},
	}

## Every imported real-mesh type, for the identity-vs-GLB-mesh gate.
func _all_types_preset() -> Dictionary:
	return {
		"radius": 200.0,
		"inner_clear_radius": 0.0,
		"seed": 999,
		"props": {
			"pit_garage": {"count": 3, "min_spacing": 40.0, "scale": Vector2(6.0, 6.5)},
			"pit_office": {"count": 3, "min_spacing": 40.0, "scale": Vector2(6.0, 6.5)},
			"grandstand": {"count": 2, "min_spacing": 60.0, "scale": Vector2(8.0, 10.0)},
			"track_barrier": {"count": 4, "min_spacing": 14.0, "scale": Vector2(4.0, 4.5)},
			"track_cone": {"count": 4, "min_spacing": 12.0, "scale": Vector2(4.0, 5.0)},
			"track_rail": {"count": 4, "min_spacing": 16.0, "scale": Vector2(2.5, 3.5)},
			"light_pole": {"count": 3, "min_spacing": 30.0, "scale": Vector2(6.0, 7.0)},
			"finish_gantry": {"count": 2, "min_spacing": 60.0, "scale": Vector2(5.0, 6.0)},
			"rock": {"count": 8, "min_spacing": 8.0, "scale": Vector2(0.8, 1.6)},
			"guardrail": {"count": 4, "min_spacing": 16.0, "scale": Vector2(1.0, 1.0)},
		},
	}

func test_buildings_place_bounded_and_clear_of_road() -> void:
	var roads := auto_free(_roads()) as RoadNetwork
	var scatterer := auto_free(PropScatterer.new()) as PropScatterer
	scatterer.road_network = roads
	scatterer.configure(_building_preset())
	add_child(scatterer)
	scatterer.generate()
	for prop_type: String in ["pit_garage", "pit_office", "grandstand"]:
		var placed := scatterer.get_instance_transforms(prop_type)
		assert_that(placed.size()).is_greater(0)
		assert_that(placed.size()).is_less_equal(int(_building_preset()["props"][prop_type]["count"]))
		for p: Vector3 in placed:
			assert_that(PropScatterer.is_clear_of_road(scatterer.to_global(p), roads, 8.0)).is_true()

## Real GLB meshes, not primitives: every imported MMI must carry native surface
## materials (preserved through the bake), the multi-part buildings/stands keep
## more than one surface, and the fused-primitive guardrail flagrantly has none.
func test_buildings_and_track_props_use_real_glb_meshes() -> void:
	var scatterer := auto_free(PropScatterer.new()) as PropScatterer
	scatterer.configure(_all_types_preset())
	scatterer.generate()
	var imported_types: Array[String] = [
		"pit_garage", "pit_office", "grandstand", "track_barrier",
		"track_cone", "track_rail", "light_pole", "finish_gantry", "rock",
	]
	for prop_type: String in imported_types:
		var child := scatterer.get_node_or_null("%sMMI" % prop_type) as MultiMeshInstance3D
		assert_that(child).is_not_null()
		var mesh: ArrayMesh = child.multimesh.mesh as ArrayMesh
		assert_that(mesh).is_not_null()
		assert_that(mesh.get_surface_count()).is_greater(0)
		assert_that(mesh.surface_get_material(0)).is_not_null()
	var multi_surface: Array[String] = ["pit_garage", "pit_office", "grandstand", "light_pole"]
	for prop_type: String in multi_surface:
		var child := scatterer.get_node_or_null("%sMMI" % prop_type) as MultiMeshInstance3D
		var mesh: ArrayMesh = child.multimesh.mesh as ArrayMesh
		assert_that(mesh.get_surface_count()).is_greater(1)
	# Negative control: the primitive guardrail mesh ships no surface material.
	var guardrail := scatterer.get_node_or_null("guardrailMMI") as MultiMeshInstance3D
	assert_that(guardrail).is_not_null()
	assert_that((guardrail.multimesh.mesh as ArrayMesh).surface_get_material(0)).is_null()

func test_buildings_reentry_is_bit_identical() -> void:
	var preset := _building_preset()
	var first := auto_free(PropScatterer.new()) as PropScatterer
	first.configure(preset)
	first.generate()
	var second := auto_free(PropScatterer.new()) as PropScatterer
	second.configure(preset)
	second.generate()
	for prop_type: String in ["pit_garage", "pit_office", "grandstand"]:
		assert_that(first.get_instance_transforms(prop_type)).is_equal(second.get_instance_transforms(prop_type))