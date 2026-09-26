extends GdUnitTestSuite

var _managed: Array[Node] = []

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	for node in _managed:
		if is_instance_valid(node):
			node.free()
	_managed.clear()

func _square_points() -> Array[Vector3]:
	return [
		Vector3(0, 0, 0),
		Vector3(100, 0, 0),
		Vector3(100, 0, 100),
		Vector3(0, 0, 100),
	]

func _build(def: RoadDef) -> TrackBuilder:
	var builder := TrackBuilder.new()
	add_child(builder)
	_managed.append(builder)
	builder.build_track(_square_points(), true, def)
	return builder

func _mesh_count(builder: TrackBuilder) -> int:
	var count := 0
	for child in builder.get_children():
		if child is MeshInstance3D:
			count += 1
	return count

func _child_named_count(builder: TrackBuilder, prefix: String) -> int:
	var count := 0
	for child in builder.get_children():
		if child.name.begins_with(prefix):
			count += 1
	return count

func _static_body_count(builder: TrackBuilder) -> int:
	var count := 0
	for child in builder.get_children():
		if child is StaticBody3D:
			count += 1
	return count

func _rail_collision_bodies(builder: TrackBuilder) -> Array[StaticBody3D]:
	var out: Array[StaticBody3D] = []
	for child in builder.get_children():
		if child is StaticBody3D and String(child.name).begins_with("RailCollision"):
			out.append(child as StaticBody3D)
	return out

func _mesh_triangle_count(instance: MeshInstance3D) -> int:
	if instance == null or instance.mesh == null or instance.mesh.get_surface_count() == 0:
		return 0
	var arrays := instance.mesh.surface_get_arrays(0)
	return (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3

func _shape_triangle_count(shape: Shape3D) -> int:
	var trimesh := shape as ConcavePolygonShape3D
	if trimesh == null:
		return 0
	return trimesh.get_faces().size() / 3

func test_lane_count_thresholds_are_deterministic() -> void:
	var highway := RoadDef.new()
	highway.width = 24.0
	var arterial := RoadDef.new()
	arterial.width = 10.0
	var multilane := RoadDef.new()
	multilane.width = 18.0
	assert_that(highway.has_method("lane_count")).is_true()
	if not highway.has_method("lane_count"):
		return
	assert_int(highway.call("lane_count")).is_equal(4)
	assert_int(arterial.call("lane_count")).is_equal(1)
	assert_int(multilane.call("lane_count")).is_equal(2)
	assert_int(highway.call("lane_count")).is_equal(4)

func test_highway_emits_lane_dividers_and_rails() -> void:
	var highway := RoadDef.make(RoadDef.Tier.HIGHWAY, _square_points(), "highway")
	highway.width = 24.0
	var one_lane := RoadDef.make(RoadDef.Tier.ARTERIAL, _square_points(), "one-lane")
	one_lane.width = 10.0
	var highway_builder := _build(highway)
	var one_lane_builder := _build(one_lane)
	assert_int(highway_builder.get_child_count()).is_equal(9)
	assert_int(one_lane_builder.get_child_count()).is_equal(4)
	assert_int(_child_named_count(highway_builder, "LaneDivider")).is_equal(3)
	assert_int(_child_named_count(highway_builder, "RoadRail")).is_equal(2)
	assert_int(_mesh_count(highway_builder)).is_equal(8)
	assert_int(_mesh_count(one_lane_builder)).is_equal(3)

func test_rails_are_gated_by_tier() -> void:
	var highway := _build(RoadDef.make(RoadDef.Tier.HIGHWAY, _square_points()))
	var dirt := _build(RoadDef.make(RoadDef.Tier.DIRT, _square_points()))
	assert_int(_child_named_count(highway, "RoadRail")).is_equal(2)
	assert_int(_child_named_count(dirt, "RoadRail")).is_equal(0)

func test_builder_mesh_counts_are_deterministic() -> void:
	var highway := RoadDef.make(RoadDef.Tier.HIGHWAY, _square_points())
	var first := _build(highway)
	var second := _build(highway)
	assert_int(first.get_child_count()).is_equal(second.get_child_count())
	assert_int(_mesh_count(first)).is_equal(_mesh_count(second))
	assert_int(first.get_child(0).get_child_count()).is_equal(second.get_child(0).get_child_count())

func test_configure_rails_cuts_gap_and_adds_two_valid_rail_collisions() -> void:
	var builder := _build(RoadDef.make(RoadDef.Tier.HIGHWAY, _square_points()))
	var full_mesh := builder.get_node("RoadRailRight") as MeshInstance3D
	var full_triangles := _mesh_triangle_count(full_mesh)
	builder.configure_rails([Vector3(50.0, 0.0, 0.0)])
	var gapped_mesh := builder.get_node("RoadRailRight") as MeshInstance3D
	assert_int(_mesh_triangle_count(gapped_mesh)).is_less(full_triangles)
	var collisions := _rail_collision_bodies(builder)
	assert_int(collisions.size()).is_equal(2)
	for body in collisions:
		assert_int(body.get_child_count()).is_equal(1)
		var collision := body.get_child(0) as CollisionShape3D
		assert_that(collision).is_not_null()
		if collision == null:
			continue
		var shape := collision.shape as ConcavePolygonShape3D
		assert_that(shape).is_not_null()
		if shape != null:
			assert_int(_shape_triangle_count(shape)).is_less(full_triangles)

func test_configure_rails_empty_is_noop_and_rebuilds_do_not_duplicate_bodies() -> void:
	var builder := _build(RoadDef.make(RoadDef.Tier.HIGHWAY, _square_points()))
	var initial_children := builder.get_child_count()
	var initial_bodies := _static_body_count(builder)
	builder.configure_rails([])
	assert_int(builder.get_child_count()).is_equal(initial_children)
	assert_int(_static_body_count(builder)).is_equal(initial_bodies)
	builder.configure_rails([Vector3(50.0, 0.0, 0.0)])
	var after_gap_bodies := _static_body_count(builder)
	builder.configure_rails([Vector3(50.0, 0.0, 0.0)])
	assert_int(_static_body_count(builder)).is_equal(after_gap_bodies)
	assert_int(_rail_collision_bodies(builder).size()).is_equal(2)

func test_recompute_rails_only_adds_gapped_collision_to_highway_network_builder() -> void:
	var network := RoadNetwork.new()
	add_child(network)
	_managed.append(network)
	for def in CorridorPlanner.plan(CorridorPlanner.MASTER_SEED):
		network.add_road_def(def)
	var full_highway_triangles := 0
	for child in network.get_children():
		var builder_before := child as TrackBuilder
		if builder_before != null and builder_before.has_node("RoadRailRight"):
			full_highway_triangles = _mesh_triangle_count(builder_before.get_node("RoadRailRight") as MeshInstance3D)
	assert_int(full_highway_triangles).is_equal(1152)
	network.recompute_rails()
	var rail_builders := 0
	for child in network.get_children():
		if not child is TrackBuilder:
			continue
		var builder := child as TrackBuilder
		var collisions := _rail_collision_bodies(builder)
		if collisions.is_empty():
			assert_int(builder.get_child_count()).is_equal(4)
			continue
		rail_builders += 1
		assert_int(collisions.size()).is_equal(2)
		var gapped_triangles := _mesh_triangle_count(builder.get_node("RoadRailRight") as MeshInstance3D)
		assert_int(gapped_triangles).is_equal(972)
		for body in collisions:
			var collision := body.get_child(0) as CollisionShape3D
			var shape := collision.shape as ConcavePolygonShape3D
			assert_that(shape).is_not_null()
			if shape != null:
				assert_int(_shape_triangle_count(shape)).is_equal(972)
	assert_int(rail_builders).is_equal(1)
