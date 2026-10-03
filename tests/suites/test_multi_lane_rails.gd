extends GdUnitTestSuite

## The four access ramps that run a merge lane alongside the highway ring.
const ACCESS_RAMP_IDS := [
	"pass-highway-ramp", "coast-highway-ramp", "touge-highway-ramp", "spawn-highway-ramp",
]

var _managed: Array[Node] = []

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	for node in _managed:
		if is_instance_valid(node):
			node.free()
	_managed.clear()

## Master-plan lookup by human id, or null. Never index defs[] positionally: the
## planner appends corridors, so a plan position is not a handle for a road.
func _def_by_id(defs: Array[RoadDef], id: String) -> RoadDef:
	for d in defs:
		if d.id == id:
			return d
	return null

## The highway ring centreline, resolved by id.
func _ring_points(defs: Array[RoadDef]) -> Array[Vector3]:
	var ring := _def_by_id(defs, "highway-ring")
	return ring.points if ring != null else ([] as Array[Vector3])

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

## The first rail mesh a builder actually emitted, or null. A road can carry
## only ONE of its two rails, so "the" reference rail mesh is whichever slot its
## mask kept -- reading RoadRailRight unconditionally reports 0 triangles on a
## road that legitimately dropped that side.
func _first_rail_mesh(builder: TrackBuilder) -> MeshInstance3D:
	var right := builder.get_node_or_null("RoadRailRight") as MeshInstance3D
	if right != null:
		return right
	return builder.get_node_or_null("RoadRailLeft") as MeshInstance3D

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
##
## The per-side rail mask only changes HOW MANY rails a road carries, never
## whether it takes part: every count below is def.rail_side_count(), so the four
## access ramps and the two-sided corridors are checked by the same loop. Those
## four keep rail_sides == BOTH and suppress the carriageway-facing side per
## index instead (RoadDef.rail_open_ranges), so they carry two rails like any
## other ARTERIAL and their junction may already sit inside an open range.
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
		full_rail_triangles.append(_mesh_triangle_count(_first_rail_mesh(builder)))
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
		var def: RoadDef = defs[i]
		var collisions := _rail_collision_bodies(builder)
		if not def.rails_enabled():
			# COASTAL / DIRT and the hub-access merge point: no rail mesh, no
			# collision body, 4 children.
			assert_int(_child_named_count(builder, "RoadRail")).is_equal(0)
			assert_int(collisions.size()).is_equal(0)
			assert_int(builder.get_child_count()).is_equal(4)
			continue
		rail_enabled += 1
		var sides := def.rail_side_count()
		assert_int(sides).is_greater_equal(1)
		assert_int(_child_named_count(builder, "RoadRail")).is_equal(sides)
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
			# surface + 2 edges + (lanes - 1) + rails + 1 road collision.
			assert_int(builder.get_child_count()).is_equal(4 + sides)
			continue
		gapped += 1
		assert_int(collisions.size()).is_equal(sides)
		# A gap is normally a hole, so the rail mesh must lose triangles. The
		# exception is a road that declares per-index open ranges whose junction
		# sits INSIDE one: the stretch was already rail-free, so cutting a gap
		# there legitimately removes nothing more. Every access ramp lands on a
		# ring vertex inside its own open merge range, which is exactly that case.
		# Hole geometry itself is asserted for open ranges by
		# test_open_range_removes_rail_geometry_on_only_the_named_side.
		var strict_hole := def.rail_open_ranges.is_empty()
		for body in collisions:
			assert_int(body.get_child_count()).is_equal(1)
			var collision := body.get_child(0) as CollisionShape3D
			var shape := collision.shape as ConcavePolygonShape3D
			assert_that(shape).is_not_null()
			if shape != null:
				if strict_hole:
					assert_int(_shape_triangle_count(shape)).is_less(full_rail_triangles[i])
				else:
					assert_int(_shape_triangle_count(shape)).is_less_equal(full_rail_triangles[i])
		if strict_hole:
			assert_int(_mesh_triangle_count(_first_rail_mesh(builder))).is_less(full_rail_triangles[i])
		else:
			assert_int(_mesh_triangle_count(_first_rail_mesh(builder))).is_less_equal(full_rail_triangles[i])
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

## The per-side mask is the whole point of the change, so it is pinned from
## three directions: the RoadDef arithmetic (a bit field, additive, with BOTH as
## the default so nothing authored earlier changes), the builder (exactly the
## masked slots are emitted), and the mask SURVIVING a gap recompute rather than
## being resurrected as two rails.
func test_rail_side_mask_selects_slots_and_defaults_to_both() -> void:
	# Default and explicit BOTH are the same road, and BOTH is additive so the
	# old "both rails" corridors keep both without touching the tier table.
	var by_default := RoadDef.make(RoadDef.Tier.ARTERIAL, _square_points(), "both-default")
	var both := RoadDef.make(RoadDef.Tier.ARTERIAL, _square_points(), "both", true, -1, -1,
		RoadDef.RailSide.BOTH)
	assert_int(by_default.rail_sides).is_equal(RoadDef.RailSide.BOTH)
	assert_int(both.rail_sides).is_equal(RoadDef.RailSide.BOTH)
	assert_int(by_default.rail_side_count()).is_equal(2)
	assert_bool(by_default.rail_on_right()).is_true()
	assert_bool(by_default.rail_on_left()).is_true()
	# Masking is subtraction from BOTH, so the surviving side is named, not the
	# dropped one: RIGHT suppressed -> LEFT, LEFT suppressed -> RIGHT.
	assert_int(RoadDef.RailSide.BOTH & ~RoadDef.RailSide.RIGHT).is_equal(RoadDef.RailSide.LEFT)
	assert_int(RoadDef.RailSide.BOTH & ~RoadDef.RailSide.LEFT).is_equal(RoadDef.RailSide.RIGHT)
	# NONE is a real answer, and the two vetoes both reach it.
	var none := RoadDef.make(RoadDef.Tier.ARTERIAL, _square_points(), "none", true, -1, -1,
		RoadDef.RailSide.NONE)
	assert_bool(none.rails_enabled()).is_true()
	assert_int(none.rail_side_count()).is_equal(0)
	assert_int(none.rail_sides_mask()).is_equal(RoadDef.RailSide.NONE)
	assert_bool(none.rail_on_right()).is_false()
	assert_bool(none.rail_on_left()).is_false()
	# A non-rail tier and a merge point both mask to NONE even when they ask
	# for both sides, so the two gates compose instead of overriding.
	var coastal := RoadDef.make(RoadDef.Tier.COASTAL, _square_points(), "coastal")
	var merge := RoadDef.make(RoadDef.Tier.ARTERIAL, _square_points(), "hub-access-ramp")
	assert_int(coastal.rail_side_count()).is_equal(0)
	assert_int(merge.rail_side_count()).is_equal(0)
	assert_bool(RoadDef.has_rails(coastal.tier)).is_false()
	assert_bool(RoadDef.has_rails(merge.tier)).is_true()

	# The builder emits exactly the masked slots, at build time...
	var left_only := RoadDef.make(RoadDef.Tier.ARTERIAL, _square_points(), "left-only", true, -1, -1,
		RoadDef.RailSide.LEFT)
	var right_only := RoadDef.make(RoadDef.Tier.ARTERIAL, _square_points(), "right-only", true, -1, -1,
		RoadDef.RailSide.RIGHT)
	var none_builder := _build(none)
	var left_builder := _build(left_only)
	var right_builder := _build(right_only)
	assert_int(_child_named_count(none_builder, "RoadRail")).is_equal(0)
	assert_int(_child_named_count(left_builder, "RoadRail")).is_equal(1)
	assert_int(_child_named_count(right_builder, "RoadRail")).is_equal(1)
	assert_that(left_builder.get_node_or_null("RoadRailLeft")).is_not_null()
	assert_that(left_builder.get_node_or_null("RoadRailRight")).is_null()
	assert_that(right_builder.get_node_or_null("RoadRailRight")).is_not_null()
	assert_that(right_builder.get_node_or_null("RoadRailLeft")).is_null()
	assert_that(_first_rail_mesh(left_builder)).is_not_null()

	# ...and keeps exactly that through a gap recompute, with one collision per
	# surviving side and none for the dropped one. A masked side must never be
	# rebuilt by configure_rails.
	for builder: TrackBuilder in [left_builder, right_builder]:
		builder.configure_rails([Vector3(50.0, 0.0, 0.0)])
		assert_int(_child_named_count(builder, "RoadRail")).is_equal(1)
		assert_int(_rail_collision_bodies(builder).size()).is_equal(1)
		assert_int(_static_body_count(builder)).is_equal(2)
	# NONE stays silent through a recompute as well.
	none_builder.configure_rails([Vector3(50.0, 0.0, 0.0)])
	assert_int(_child_named_count(none_builder, "RoadRail")).is_equal(0)
	assert_int(_rail_collision_bodies(none_builder).size()).is_equal(0)

## The shipped access ramps are the reason per-index suppression exists: each
## runs a merge lane PARALLEL to the highway ring, so a rail on the
## carriageway-facing side is a wall across the join.
##
## The side is NOT constant along a ramp, which is why this is per index rather
## than one road-wide mask. The merge lane advances with increasing ring index,
## but the APPROACH reaches it by wrapping the ring the opposite way and so meets
## the carriageway on the other side. On the shipped spawn ramp (MASTER_SEED) the
## ring lies to the ramp's LEFT for the whole approach and to its RIGHT for the
## merge lane; masking either side statically walls off the other end.
##
## So the invariant asserted here is not a constant mask but a per-index one:
## everywhere the ramp runs alongside the ring, the ring-facing side carries NO
## rail. The ramps keep rail_sides == BOTH (field side guarded the whole way),
## and every other corridor is untouched.
func test_access_ramps_open_the_ring_facing_side_every_alongside_index() -> void:
	var defs := CorridorPlanner.plan(CorridorPlanner.MASTER_SEED)
	var ring := _ring_points(defs)
	assert_that(ring).is_not_empty()
	if ring.is_empty():
		return
	var ramps := 0
	for def in defs:
		if def.id not in ACCESS_RAMP_IDS:
			continue
		ramps += 1
		var n := def.points.size()
		# Non-vacuity: the ramp must actually declare at least one open range,
		# otherwise the per-index loop below never runs and this test is a
		# tautology that would stay green with the defect reintroduced.
		assert_int(def.rail_open_ranges.size()).append_failure_message(def.id).is_greater_equal(1)
		var alongside := 0
		for i in n:
			var st := CorridorPlanner._ring_station(ring, def.points[i])
			if float(st["d"]) > CorridorPlanner.MERGE_BAND_M:
				continue
			alongside += 1
			var open_side := CorridorPlanner._open_rail_side_at(def.points, i, ring)
			assert_int(open_side).append_failure_message("%s idx %d" % [def.id, i]) \
				.is_not_equal(RoadDef.RailSide.NONE)
			var walled := def.rail_sides_mask_at(i) & open_side
			assert_int(walled).append_failure_message(
				"%s idx %d still has a rail on the ring-facing side" % [def.id, i]).is_equal(0)
			# ...and the FIELD side must survive: a merge lane with no rail at all
			# would let a car off the 24 m roadbed, so exactly one side remains.
			var remaining := def.rail_sides_mask_at(i)
			assert_int(remaining).append_failure_message(
				"%s idx %d dropped both rails" % [def.id, i]).is_equal(
					RoadDef.RailSide.BOTH & ~open_side)
		assert_int(alongside).append_failure_message(def.id).is_greater_equal(1)
	assert_int(ramps).is_equal(ACCESS_RAMP_IDS.size())

## The spawn ramp is the case that motivates per-index suppression: its open side
## FLIPS part-way (LEFT across the approach, RIGHT on the merge lane). A static
## mask cannot express that, so assert the flip exists and is measured from
## geometry, which also pins the specific regression: the approach used to keep
## LEFT -- the ring-facing side -- and was walled along its entire length.
func test_spawn_ramp_merge_open_side_flips_between_approach_and_lane() -> void:
	var defs := CorridorPlanner.plan(CorridorPlanner.MASTER_SEED)
	var ring := _ring_points(defs)
	var spawn := _def_by_id(defs, "spawn-highway-ramp")
	assert_that(spawn).is_not_null()
	if spawn == null or ring.is_empty():
		return
	var n := spawn.points.size()
	var sides: Array[int] = []
	for i in n:
		sides.append(CorridorPlanner._open_rail_side_at(spawn.points, i, ring))
	# Alongside indices collapse into at most two contiguous runs. Assert the run
	# STRUCTURE rather than bucketing indices into guessed windows: the flip sits
	# at the merge-lane boundary, and any window that guesses that boundary wrong
	# silently reads whichever side happens to be written last.
	var first := -1
	var last := -1
	var runs: Array[Dictionary] = []
	for i in n:
		if sides[i] == RoadDef.RailSide.NONE:
			continue
		if first < 0:
			first = i
		last = i
		if runs.is_empty() or int(runs[runs.size() - 1]["side"]) != sides[i]:
			runs.append({"side": sides[i], "from": i, "to": i})
		else:
			runs[runs.size() - 1]["to"] = i
	assert_int(runs.size()).override_failure_message(
		"expected exactly one approach run and one merge-lane run, got %d: %s"
		% [runs.size(), str(runs)]).is_equal(2)
	if runs.size() != 2:
		return
	assert_int(int(runs[0]["side"])).override_failure_message(
		"the whole approach meets the carriageway on the ramp's %s, so that is the side that must be open"
		% ("RIGHT" if int(runs[0]["side"]) == RoadDef.RailSide.RIGHT else "LEFT")
	).is_equal(RoadDef.RailSide.LEFT)
	assert_int(int(runs[1]["side"])).override_failure_message(
		"the merge lane must open the opposite side from the approach"
	).is_equal(RoadDef.RailSide.RIGHT)
	# The runs must tile the alongside stretch with no gap: any index left railed
	# between them is a segment of barrier across the merge.
	assert_int(int(runs[1]["from"])).is_equal(int(runs[0]["to"]) + 1)
	assert_int(int(runs[0]["from"])).is_equal(first)
	# The merge-lane run has to reach the final point. The landing sits exactly ON
	# a ring vertex, so its direction to the carriageway is undefined and the side
	# is inherited from behind; if that inheritance failed, the run would stop one
	# point short and leave a rail stub across the merge itself.
	assert_int(int(runs[1]["to"])).override_failure_message(
		"merge-lane open range stops at %d of %d, leaving the landing railed"
		% [int(runs[1]["to"]), n - 1]).is_equal(n - 1)
	assert_int(last).is_equal(n - 1)

## Suppression has to remove actual RAIL GEOMETRY, not just flip a mask the
## builder ignores. Build the same square with and without an open range and
## compare triangle counts on the affected side: fewer triangles on the gapped
## side, and the SAME count on the side that was not named.
func test_open_range_removes_rail_geometry_on_only_the_named_side() -> void:
	var plain := _build(RoadDef.make(RoadDef.Tier.ARTERIAL, _square_points(), "plain", true, -1, -1,
		RoadDef.RailSide.BOTH))
	var ranged := RoadDef.make(RoadDef.Tier.ARTERIAL, _square_points(), "ranged", true, -1, -1,
		RoadDef.RailSide.BOTH)
	# Open LEFT across chain indices 1..2 of the 4-point square.
	ranged.rail_open_ranges = [{"from": 1, "to": 2, "side": RoadDef.RailSide.LEFT}]
	var built := _build(ranged)

	var plain_left := plain.get_node_or_null("RoadRailLeft") as MeshInstance3D
	var ranged_left := built.get_node_or_null("RoadRailLeft") as MeshInstance3D
	var plain_right := plain.get_node_or_null("RoadRailRight") as MeshInstance3D
	var ranged_right := built.get_node_or_null("RoadRailRight") as MeshInstance3D
	# Both rails still EXIST as nodes -- a range is a hole in the mesh, not a
	# dropped side, so the field-side mesh and its collider are never renumbered.
	assert_that(ranged_left).is_not_null()
	assert_that(ranged_right).is_not_null()
	assert_int(_mesh_triangle_count(ranged_left)).is_less(
		_mesh_triangle_count(plain_left))
	assert_int(_mesh_triangle_count(ranged_right)).is_equal(
		_mesh_triangle_count(plain_right))
	# The named side is still meshed outside the range: 4-point closed square has
	# 4 segments, indices 1..2 cover two of them, so 2 survive.
	assert_int(_mesh_triangle_count(ranged_left)).is_greater(0)

## A range naming a side the road never carries must be inert, and out-of-bounds
## indices must clamp instead of indexing off the end of the chain.
func test_open_range_is_inert_for_an_absent_side_and_clamps() -> void:
	var left_only := RoadDef.make(RoadDef.Tier.ARTERIAL, _square_points(), "left-only", true, -1, -1,
		RoadDef.RailSide.LEFT)
	# RIGHT is absent from this road, so a RIGHT range changes nothing.
	left_only.rail_open_ranges = [{"from": 0, "to": 3, "side": RoadDef.RailSide.RIGHT}]
	assert_int(left_only.rail_sides_mask_at(0)).is_equal(RoadDef.RailSide.LEFT)
	assert_int(left_only.rail_sides_mask_at(3)).is_equal(RoadDef.RailSide.LEFT)
	var built := _build(left_only)
	var rail := built.get_node_or_null("RoadRailLeft") as MeshInstance3D
	assert_that(rail).is_not_null()
	assert_int(_mesh_triangle_count(rail)).is_greater(0)

	var clamped := RoadDef.make(RoadDef.Tier.ARTERIAL, _square_points(), "clamped", true, -1, -1,
		RoadDef.RailSide.BOTH)
	# from/to far past the 4-point chain, and reversed: both must clamp, not throw.
	clamped.rail_open_ranges = [{"from": 99, "to": -5, "side": RoadDef.RailSide.LEFT}]
	var out := clamped.rail_open_ranges_for(RoadDef.RailSide.LEFT)
	assert_int(out.size()).is_equal(1)
	assert_int(int(out[0][0])).is_equal(0)
	assert_int(int(out[0][1])).is_equal(3)
	var built_clamped := _build(clamped)
	var cl := built_clamped.get_node_or_null("RoadRailLeft") as MeshInstance3D
	var cr := built_clamped.get_node_or_null("RoadRailRight") as MeshInstance3D
	assert_int(_mesh_triangle_count(cl)).is_equal(0)
	assert_int(_mesh_triangle_count(cr)).is_greater(0)

## The surviving field-side rail must sit on a roadbed that is actually at
## highway grade where it runs beside the highway, and the lane must meet the
## ring at the landing vertex rather than stopping short of it. A rail built off a
## lane that had drifted above or below the ring would float or sink at the merge
## even with the right side picked.
## Only the MERGE LANE is at ring grade: the approach ahead of it climbs from the
## hub basin, so the check runs over the tail of the chain (the lane plus the
## extra constant-offset run), never the whole ramp.
func test_spawn_ramp_keeps_its_rail_at_highway_grade() -> void:
	var defs := CorridorPlanner.plan(CorridorPlanner.MASTER_SEED)
	var ramp: RoadDef = null
	var ring: Array[Vector3] = []
	for def in defs:
		if def.id == "spawn-highway-ramp":
			ramp = def
		elif def.id == "highway-ring":
			ring = def.points
	assert_that(ramp).is_not_null()
	assert_int(ring.size()).is_greater(0)
	if ramp == null or ring.is_empty():
		return
	# This ramp no longer collapses to one static side: it keeps rail_sides BOTH
	# and suppresses the carriageway-facing side per index, so the merge is open
	# while the field side stays walled. A one-rail mask cannot express a side
	# that flips mid-chain, and the grade assertions below only describe a lane
	# that is actually reachable.
	assert_int(ramp.rail_side_count()).is_equal(2)
	var suppressed := 0
	for i in ramp.points.size():
		if ramp.rail_sides_mask_at(i) != ramp.rail_sides_mask():
			suppressed += 1
	assert_int(suppressed).override_failure_message(
		"no chain index has a rail suppressed, so the merge is still walled").is_greater(0)
	# The lane is the tail of the chain by contract: 14 tapering ring vertices +
	# the landing + the extra constant-offset run this change added. The approach
	# ahead of it climbs from the hub basin, so it is deliberately excluded.
	# 0.5 m is the project's ramp at-grade tolerance: the extra run interpolates
	# ring Y BETWEEN vertices, and the ring is banked, so its grade matches the
	# nearest ring VERTEX only to within that.
	const GRADE_TOL := 0.5
	const LANE_POINTS := 17
	var lane_start := ramp.points.size() - LANE_POINTS
	assert_int(lane_start).is_greater_equal(0)
	for i in range(lane_start, ramp.points.size()):
		var nearest := _nearest_ring_y(ring, ramp.points[i])
		assert_float(absf(ramp.points[i].y - nearest)).is_less_equal(GRADE_TOL)
	# The lane runs at a constant ring offset through its extra run, so it is
	# parallel to the highway rather than drifting toward or away from it.
	var first_off := _ring_signed_offset(Vector2(ramp.points[lane_start].x, ramp.points[lane_start].z))
	var last_off := _ring_signed_offset(Vector2(ramp.points[lane_start + 1].x, ramp.points[lane_start + 1].z))
	assert_float(absf(absf(first_off) - absf(last_off))).is_less_equal(GRADE_TOL)
	# And the lane lands ON the ring vertex, so the kept rail has the ring to
	# merge into rather than ending in the field next to it.
	var end: Vector3 = ramp.points[ramp.points.size() - 1]
	assert_int(_index_of_point(ring, end)).is_equal(96)

## The extra run is a real LENGTH gain, not a reshuffle. Measured differentially:
## the same ramp built with and without the extra, so the difference is exactly
## what the extra run contributed and cannot be confused with the ring's own
## varying segment lengths (a tail-length comparison against the other ramps is
## not, because their tapers sit at different points on the ellipse).
## "Roughly 200 m" is a design target: the extra run follows the ring's curved
## segments and its last step is a partial one, so it lands slightly over.
func test_spawn_merge_run_adds_its_length_and_nothing_else() -> void:
	var defs := CorridorPlanner.plan(CorridorPlanner.MASTER_SEED)
	var ring: Array[Vector3] = []
	for def in defs:
		if def.id == "highway-ring":
			ring = def.points
	assert_int(ring.size()).is_greater(96)
	if ring.size() <= 96:
		return
	var source := Vector3(128.0, 2.2, 128.0)
	var bulge := Vector2(60.0, -16.0)
	var plain: Array[Vector3] = CorridorPlanner._access_ramp(source, ring, 96, bulge)
	var extended: Array[Vector3] = CorridorPlanner._access_ramp(source, ring, 96, bulge,
		CorridorPlanner.SPAWN_MERGE_RUN_M)
	# The base lane is the tapering run plus the landing; the extended lane is
	# that same run with the extra constant-offset points prepended to it. Both
	# are tails of their chain, so the two lanes are compared tail-to-tail.
	const BASE_LANE := 15
	# The extra run PREPENDS to the lane and changes nothing else: the tapering tail
	# and the landing are point-for-point identical, aligned from the END (both
	# chains land on the same ring vertex, so the tails line up backwards).
	var shared := mini(BASE_LANE, mini(plain.size(), extended.size()))
	assert_int(shared).is_equal(BASE_LANE)
	for i in shared:
		var e: Vector3 = extended[extended.size() - 1 - i]
		var p: Vector3 = plain[plain.size() - 1 - i]
		assert_that(e).append_failure_message("shared lane point %d from the end" % i) \
			.is_equal_approx(p, Vector3(0.001, 0.001, 0.001))
	# The lane grew, so the chain grew: the approach has to reach the new outer end.
	assert_int(extended.size()).is_greater(plain.size())
	# How far the lane's outer end moved is the length actually gained, measured
	# directly rather than inferred from the chain (which also grew, by the stretch
	# of approach needed to reach the new end). "Roughly 200 m" is a design target;
	# the run follows the ring's curved segments, so it lands a little over.
	var plain_outer: Vector3 = plain[plain.size() - BASE_LANE]
	var ext_outer := _lane_outer(extended)
	assert_float(_xz_distance(ext_outer, plain_outer)).append_failure_message("extra run length") \
		.is_greater_equal(CorridorPlanner.SPAWN_MERGE_RUN_M * 0.9)
	assert_float(_xz_distance(ext_outer, plain_outer)).append_failure_message("extra run length") \
		.is_less_equal(CorridorPlanner.SPAWN_MERGE_RUN_M * 1.1)
	# The landing is untouched: still the ring vertex verbatim.
	var end: Vector3 = extended[extended.size() - 1]
	assert_that(end).is_equal_approx(ring[96], Vector3(0.001, 0.001, 0.001))
	# Every point of the constant-offset run the extra added is on the ring's own
	# grade and at the lane offset, so the kept rail has one continuous roadbed.
	for i in range(extended.size() - 1, _lane_outer_index(extended) - 1, -1):
		var p: Vector3 = extended[i]
		assert_float(absf(p.y - _nearest_ring_y(ring, p))).is_less_equal(0.5)

## The outer end of a chain's constant-offset merge run, found by step LENGTH:
## the run is resampled from whole ring segments (~130 m apart), while the taper
## steps in metres and the approach is resampled every ~12 m. The offset alone
## cannot identify it, because the approach also sits clear of the carriageway.
func _lane_outer(points: Array[Vector3]) -> Vector3:
	return points[_lane_outer_index(points)]

func _lane_outer_index(points: Array[Vector3]) -> int:
	var i := points.size() - 1
	while i > 0 and _offset_at(points, i) < _offset_at(points, i - 1):
		i -= 1
	while i > 0 and _xz_distance(points[i], points[i - 1]) > 60.0:
		i -= 1
	return i

func _offset_at(points: Array[Vector3], i: int) -> float:
	return absf(_ring_signed_offset(Vector2(points[i].x, points[i].z)))

func _xz_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _chain_xz_length(points: Array[Vector3]) -> float:
	var total := 0.0
	for i in points.size() - 1:
		total += Vector2(points[i + 1].x - points[i].x, points[i + 1].z - points[i].z).length()
	return total

## Signed metres from `p2d` to the perimeter highway ellipse along its own ray
## out of the ring centre: positive outside the carriageway, negative inside.
func _ring_signed_offset(p2d: Vector2) -> float:
	const CENTER := Vector2(4400.0, 2250.0)
	const AXIS_X := 4600.0
	const AXIS_Z := 3550.0
	var radial := p2d - CENTER
	var radial_len := radial.length()
	if radial_len < 0.0001:
		return 0.0
	var ray := radial / radial_len
	var locus := 1.0 / sqrt(pow(ray.x / AXIS_X, 2.0) + pow(ray.y / AXIS_Z, 2.0))
	return radial_len - locus

func _nearest_ring_y(ring: Array[Vector3], p: Vector3) -> float:
	var best := INF
	var y := 0.0
	for r in ring:
		var d := Vector2(r.x - p.x, r.z - p.z).length_squared()
		if d < best:
			best = d
			y = r.y
	return y
