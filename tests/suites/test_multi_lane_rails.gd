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

## Index of an exact centreline vertex, or -1 when the point is not on this
## road. Pins which road a rail gap's geometry was taken from.
func _index_of_point(points: Array[Vector3], target: Vector3) -> int:
	for i in points.size():
		if points[i].distance_to(target) < 0.001:
			return i
	return -1

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
	# build_track() emits, in order: RoadSurface, RoadEdgeRight/Left, one
	# LaneDivider per extra lane (lane_count - 1), then RoadRailRight/Left when
	# RoadDef.rails_enabled() (HIGHWAY, ARTERIAL and TOUGE are; COASTAL and DIRT
	# are not), then CollisionBody. Rail collisions only appear once
	# configure_rails() supplies gaps, so they are absent at build time.
	# HIGHWAY w24 -> 4 lanes: 1 + 2 + 3 + 2 + 1 = 9 children, 8 of them meshes.
	assert_int(highway_builder.get_child_count()).is_equal(9)
	# ARTERIAL w10 -> 1 lane: 1 + 2 + 0 + 2 + 1 = 6 children, 5 of them meshes.
	assert_int(one_lane_builder.get_child_count()).is_equal(6)
	assert_int(_child_named_count(highway_builder, "LaneDivider")).is_equal(3)
	assert_int(_child_named_count(highway_builder, "RoadRail")).is_equal(2)
	assert_int(_child_named_count(one_lane_builder, "LaneDivider")).is_equal(0)
	assert_int(_child_named_count(one_lane_builder, "RoadRail")).is_equal(2)
	assert_int(_mesh_count(highway_builder)).is_equal(8)
	assert_int(_mesh_count(one_lane_builder)).is_equal(5)

func test_rails_are_gated_by_tier() -> void:
	var highway := _build(RoadDef.make(RoadDef.Tier.HIGHWAY, _square_points()))
	var arterial := _build(RoadDef.make(RoadDef.Tier.ARTERIAL, _square_points()))
	var touge := _build(RoadDef.make(RoadDef.Tier.TOUGE, _square_points()))
	var coastal := _build(RoadDef.make(RoadDef.Tier.COASTAL, _square_points()))
	var dirt := _build(RoadDef.make(RoadDef.Tier.DIRT, _square_points()))
	# RoadDef.ROADS_WITH_RAILS: HIGHWAY, ARTERIAL and TOUGE carry rails;
	# COASTAL and DIRT never do.
	assert_int(_child_named_count(highway, "RoadRail")).is_equal(2)
	assert_int(_child_named_count(arterial, "RoadRail")).is_equal(2)
	assert_int(_child_named_count(touge, "RoadRail")).is_equal(2)
	assert_int(_child_named_count(coastal, "RoadRail")).is_equal(0)
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

## recompute_rails() must cut a gap on every rail-enabled corridor that touches
## another rail-enabled corridor, and must leave the rest alone. Rail tiers are
## HIGHWAY, ARTERIAL and TOUGE, so this is no longer a highway-only effect: of
## the 19 planned corridors 15 are rail-enabled by tier, and hub-access-ramp is
## the one merge point, so 14 actually carry rails and 13 of those touch another
## rail-carrying corridor. touge-b is the one rail-carrying corridor with no
## rail-carrying neighbour: configure_rails([]) is a no-op, so it keeps its
## build-time rails and gains no collision bodies. A merge point is never in that
## 14: it is skipped entirely, and the road it lands on (the hub ring) still
## clears its own rail at that junction.
func test_recompute_rails_gaps_every_rail_enabled_road() -> void:
	var network := RoadNetwork.new()
	add_child(network)
	_managed.append(network)
	var defs := CorridorPlanner.plan(CorridorPlanner.MASTER_SEED)
	for def in defs:
		network.add_road_def(def)
	var builders: Array[TrackBuilder] = []
	var full_rail_triangles: Array[int] = []
	var highway_idx := -1
	for i in defs.size():
		var builder := network.get_children()[i] as TrackBuilder
		builders.append(builder)
		full_rail_triangles.append(
			_mesh_triangle_count(builder.get_node_or_null("RoadRailRight") as MeshInstance3D))
		if defs[i].id == "highway-ring":
			highway_idx = i
	assert_int(highway_idx).is_greater_equal(0)
	if highway_idx < 0:
		return
	# The 192-vertex perimeter ring is the reference rail mesh: 1152 triangles
	# per rail before any gap is cut.
	assert_int(full_rail_triangles[highway_idx]).is_equal(1152)
	network.recompute_rails()
	var adj := network.get_adjacency()
	var rail_enabled := 0
	var gapped := 0
	for i in defs.size():
		var builder := builders[i]
		var collisions := _rail_collision_bodies(builder)
		if not defs[i].rails_enabled():
			# COASTAL / DIRT and the hub-access merge point: no rail mesh, no
			# collision body, 4 children.
			assert_int(_child_named_count(builder, "RoadRail")).is_equal(0)
			assert_int(collisions.size()).is_equal(0)
			assert_int(builder.get_child_count()).is_equal(4)
			continue
		rail_enabled += 1
		assert_int(_child_named_count(builder, "RoadRail")).is_equal(2)
		var neighbours: PackedInt32Array = adj[i]
		var touches_rails := false
		for other in neighbours:
			# Un-gated tier table: a merge-point neighbour carries no rail of
			# its own, but the road it lands on still has to clear its rail.
			if RoadDef.has_rails(defs[other].tier):
				touches_rails = true
				break
		if not touches_rails:
			assert_int(collisions.size()).is_equal(0)
			assert_int(builder.get_child_count()).is_equal(6)
			continue
		gapped += 1
		assert_int(collisions.size()).is_equal(2)
		for body in collisions:
			assert_int(body.get_child_count()).is_equal(1)
			var collision := body.get_child(0) as CollisionShape3D
			var shape := collision.shape as ConcavePolygonShape3D
			assert_that(shape).is_not_null()
			if shape != null:
				assert_int(_shape_triangle_count(shape)).is_less(full_rail_triangles[i])
		# A gap is a hole: the rail mesh must lose triangles.
		assert_int(_mesh_triangle_count(
			builder.get_node("RoadRailRight") as MeshInstance3D)).is_less(full_rail_triangles[i])
	# hub-access-ramp is a merge point, so it is one of the 15 rail TIER roads
	# that never carries a rail mesh: 14 rail-carrying corridors, 13 of them
	# touching another rail-carrying corridor.
	assert_int(rail_enabled).is_equal(14)
	assert_int(gapped).is_equal(13)
	# The ring takes one gap per rail TIER corridor it touches: 10 neighbours,
	# but dirt-a and dirt-b are DIRT tier. Mirrors recompute_rails(), which asks
	# has_rails() (not the merge-gated answer) about the other side.
	var ring_gaps := 0
	for j in network.get_junctions():
		var road_a := int(j["road_a"])
		var road_b := int(j["road_b"])
		var other := -1
		if road_a == highway_idx:
			other = road_b
		elif road_b == highway_idx:
			other = road_a
		if other >= 0 and RoadDef.has_rails(defs[other].tier):
			ring_gaps += 1
	assert_int(ring_gaps).is_equal(8)
	assert_int(builders[highway_idx]._rail_gaps.size()).is_equal(ring_gaps)

## The merge-point policy gates RAILS, not tiers. A merge-point road emits no
## rail meshes and no rail collision bodies at all - that is what keeps the merge
## side of the junction open - while a plain road of the same tier is untouched,
## and configure_rails() must not resurrect the merge road's rails either. The
## un-gated answer still has to exist: has_rails() is the tier question that
## RoadNetwork.recompute_rails asks about the other side of a junction, so a
## merge point still makes the receiving road clear its rail.
func test_merge_point_road_carries_no_rails() -> void:
	var merge := RoadDef.make(RoadDef.Tier.ARTERIAL, _square_points(), "hub-access-ramp")
	var plain := RoadDef.make(RoadDef.Tier.ARTERIAL, _square_points(), "hub-ring")
	assert_bool(RoadDef.is_merge_point(merge.id)).is_true()
	assert_bool(RoadDef.is_merge_point(plain.id)).is_false()
	assert_bool(RoadDef.has_rails(merge.tier)).is_true()
	assert_bool(merge.rails_enabled()).is_false()
	assert_bool(plain.rails_enabled()).is_true()
	var merge_builder := _build(merge)
	var plain_builder := _build(plain)
	assert_int(_child_named_count(merge_builder, "RoadRail")).is_equal(0)
	assert_int(_rail_collision_bodies(merge_builder).size()).is_equal(0)
	assert_int(_child_named_count(plain_builder, "RoadRail")).is_equal(2)
	# A late rail gap cannot force rails onto a merge point.
	merge_builder.configure_rails([Vector3(50.0, 0.0, 0.0)])
	assert_int(_child_named_count(merge_builder, "RoadRail")).is_equal(0)
	assert_int(_rail_collision_bodies(merge_builder).size()).is_equal(0)

## recompute_rails() must decide, per junction, which roads get their rail
## cleared, and every gap it cuts must belong to the road that is being
## processed - built from that road's OWN centreline, never from the neighbour's
## coordinates (a neighbour's points describe a different arc length, so the
## window would be cut in the wrong place).
## Two spurs land on a ring here. A plain rail spur takes part in rail gaps by
## TIER, so the RING has to clear its rail where the merge lands on it, and the
## merge side itself is skipped (it has no rails) - which is exactly what the old
## merge-gated neighbour test prevented: the ring kept a rail straight through
## the merge. The plain spur gaps its own rail at its own junction.
func test_recompute_rails_attributes_each_gap_to_its_own_road() -> void:
	var ring_pts: Array[Vector3] = []
	for i in 24:
		var ang := TAU * float(i) / 24.0
		ring_pts.append(Vector3(cos(ang) * 100.0, 0.0, sin(ang) * 100.0))
	var merge_spur: Array[Vector3] = [
		Vector3(0.0, 0.0, 40.0), Vector3(50.0, 0.0, 20.0), ring_pts[0],
	]
	var plain_spur: Array[Vector3] = [
		Vector3(-130.0, 0.0, 0.0), Vector3(-115.0, 0.0, 0.0), ring_pts[12],
	]
	var network := RoadNetwork.new()
	add_child(network)
	_managed.append(network)
	network.add_road_def(RoadDef.make(RoadDef.Tier.ARTERIAL, ring_pts, "hub-ring", true, 12.0))
	network.add_road_def(RoadDef.make(RoadDef.Tier.ARTERIAL, merge_spur, "hub-access-ramp", false))
	network.add_road_def(RoadDef.make(RoadDef.Tier.ARTERIAL, plain_spur, "hub-coast", false))
	var ring_builder := network.get_children()[0] as TrackBuilder
	var merge_builder := network.get_children()[1] as TrackBuilder
	var plain_builder := network.get_children()[2] as TrackBuilder
	# Exactly two junctions, both flush: each spur's last point IS a ring vertex.
	var adj := network.get_adjacency()
	var ring_row: PackedInt32Array = adj[0]
	var merge_row: PackedInt32Array = adj[1]
	var plain_row: PackedInt32Array = adj[2]
	assert_int(ring_row.size()).is_equal(2)
	assert_int(merge_row.size()).is_equal(1)
	assert_int(plain_row.size()).is_equal(1)
	assert_int(merge_row[0]).is_equal(0)
	assert_int(plain_row[0]).is_equal(0)
	var full_rail_triangles := _mesh_triangle_count(
		ring_builder.get_node("RoadRailRight") as MeshInstance3D)
	assert_int(full_rail_triangles).is_greater(0)
	network.recompute_rails()
	# The receiving ring keeps both rails and gains exactly one gap per
	# junction, each cut from its own vertices MERGE_POINTS (14) back from that
	# junction: (0 - 14) % 24 = 10 and (12 - 14) % 24 = 22.
	assert_int(_child_named_count(ring_builder, "RoadRail")).is_equal(2)
	assert_int(ring_builder._rail_gaps.size()).is_equal(2)
	var ring_gap_starts: Array[int] = []
	var ring_gap_ends: Array[int] = []
	for g in ring_builder._rail_gaps:
		var gap: Dictionary = g
		var start: Vector3 = gap["start"]
		var end: Vector3 = gap["end"]
		var start_idx := _index_of_point(ring_pts, start)
		var end_idx := _index_of_point(ring_pts, end)
		# Both endpoints are ring vertices, so the window was cut against the
		# ring's arc length, never against a spur's.
		assert_int(start_idx).is_greater_equal(0)
		assert_int(end_idx).is_greater_equal(0)
		ring_gap_starts.append(start_idx)
		ring_gap_ends.append(end_idx)
	ring_gap_starts.sort()
	ring_gap_ends.sort()
	assert_int(ring_gap_starts[0]).is_equal(10)
	assert_int(ring_gap_starts[1]).is_equal(22)
	assert_int(ring_gap_ends[0]).is_equal(0)
	assert_int(ring_gap_ends[1]).is_equal(12)
	assert_int(_mesh_triangle_count(
		ring_builder.get_node("RoadRailRight") as MeshInstance3D)).is_less(full_rail_triangles)
	assert_int(_rail_collision_bodies(ring_builder).size()).is_equal(2)
	# The merge side is skipped: no gap of its own, and no rails at all.
	assert_int(merge_builder._rail_gaps.size()).is_equal(0)
	assert_int(_child_named_count(merge_builder, "RoadRail")).is_equal(0)
	assert_int(_rail_collision_bodies(merge_builder).size()).is_equal(0)
	# A plain rail spur still gaps its own rail at its own junction, from its
	# own centreline: 3 points, junction at the last one, (2 - 14) % 3 = 0.
	assert_int(plain_builder._rail_gaps.size()).is_equal(1)
	var plain_gap: Dictionary = plain_builder._rail_gaps[0]
	var plain_start: Vector3 = plain_gap["start"]
	var plain_end: Vector3 = plain_gap["end"]
	assert_int(_index_of_point(plain_spur, plain_start)).is_equal(0)
	assert_int(_index_of_point(plain_spur, plain_end)).is_equal(2)
	assert_int(_child_named_count(plain_builder, "RoadRail")).is_equal(2)
	assert_int(_rail_collision_bodies(plain_builder).size()).is_equal(2)
