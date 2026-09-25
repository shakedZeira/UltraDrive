extends GdUnitTestSuite

const ALL_PROP_TYPES := [
	"racing_barrier_red",
	"racing_pylon",
	"racing_grandstand",
	"racing_rail_double",
	"racing_flag_checkers",
	"racing_tent",
]

const HIGHLAND_PROP_TYPES := [
	"racing_barrier_red",
	"racing_pylon",
	"racing_grandstand",
	"racing_rail_double",
]

func test_racing_builders_load_native_prop_meshes() -> void:
	var scatterer := auto_free(PropScatterer.new()) as PropScatterer
	scatterer.configure(_custom_preset(1, 8.0))
	scatterer.generate()
	for prop_type: String in ALL_PROP_TYPES:
		var mmi := scatterer.get_node_or_null("%sMMI" % prop_type) as MultiMeshInstance3D
		assert_object(mmi).is_not_null()
		if mmi == null:
			continue
		var mesh := mmi.multimesh.mesh
		assert_object(mesh).is_not_null()
		assert_int(mesh.get_surface_count()).is_greater(0)
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		assert_int(vertices.size()).is_greater(0)

func test_racing_props_stay_clear_of_roads() -> void:
	var roads := auto_free(_straight_road(12.0)) as RoadNetwork
	var scatterer := auto_free(PropScatterer.new()) as PropScatterer
	scatterer.road_network = roads
	scatterer.position = Vector3(128.0, 0.0, 128.0)
	scatterer.configure(_custom_preset(6, 4.0))
	add_child(scatterer)
	scatterer.generate()
	for prop_type: String in ALL_PROP_TYPES:
		var placed := scatterer.get_instance_transforms(prop_type)
		assert_int(placed.size()).is_greater(0)
		for local_pos: Vector3 in placed:
			assert_that(PropScatterer.is_clear_of_road(scatterer.to_global(local_pos), roads, 6.0)).is_true()

func test_racing_presets_are_wired_and_deterministic() -> void:
	var festival := _configured_scatterer(PropScatterer.default_preset("festival"))
	for prop_type: String in ALL_PROP_TYPES:
		assert_object(festival.get_node_or_null("%sMMI" % prop_type)).is_not_null()
	var highlands := _configured_scatterer(PropScatterer.default_preset("highlands"))
	for prop_type: String in HIGHLAND_PROP_TYPES:
		assert_object(highlands.get_node_or_null("%sMMI" % prop_type)).is_not_null()
	var repeat := _configured_scatterer(PropScatterer.default_preset("festival"))
	for prop_type: String in ALL_PROP_TYPES:
		assert_that(repeat.get_instance_transforms(prop_type)).is_equal(festival.get_instance_transforms(prop_type))

func _configured_scatterer(preset: Dictionary) -> PropScatterer:
	var scatterer := auto_free(PropScatterer.new()) as PropScatterer
	scatterer.configure(preset)
	scatterer.generate()
	return scatterer

func _custom_preset(count: int, min_spacing: float) -> Dictionary:
	var props: Dictionary = {}
	for prop_type: String in ALL_PROP_TYPES:
		props[prop_type] = {"count": count, "min_spacing": min_spacing}
	return {
		"radius": 120.0,
		"inner_clear_radius": 0.0,
		"seed": 31415,
		"road_threshold": 6.0,
		"placement_attempts": 64,
		"props": props,
	}

func _straight_road(width: float) -> RoadNetwork:
	var roads := RoadNetwork.new()
	roads.add_road([Vector3(-300.0, 0.0, 0.0), Vector3(300.0, 0.0, 0.0)], width, false)
	return roads
