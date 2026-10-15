# tests/suites/test_track_bank_profile.gd
extends GdUnitTestSuite

## P1 gate for the Northern Isle Speedway plan
## (docs/plans/track_northern_isle_speedway.md, §4 "P1"): the shared
## RoadDef.bank_angles / RoadDef.show_lane_dividers capability.
##
## The bank profile is a per-point, SIGNED angle array (radians) in
## TrackBuilder._frame's sign space (negative = left turn => LEFT edge lower,
## RIGHT edge higher). It must OVERRIDE the legacy banking x curvature path,
## work on a straight road (spacing/curvature independent), be ignored when its
## size does not match the point count (legacy byte-identical), and reach the
## trimesh collision through the one _frame branch. show_lane_dividers = false
## must remove ONLY the dashed divider meshes.
##
## Sign-space reference: the existing right-turn test
## `test_road_graph.gd > test_track_builder_banking_lowers_right_edge_on_right_turn`.
## For an OPEN 3-point road the surface strip emits one vertex pair per point, so
## the apex (path point 1) pair lives at indices 2 (LEFT, `center - cross*w/2`)
## and 3 (RIGHT, `center + cross*w/2`). With `cross = right*cos(a) - UP*sin(a)`:
##   left.y  - center.y ==  (w/2) * sin(a)
##   right.y - center.y == -(w/2) * sin(a)

const PROFILE_ANGLE := -0.31  # radians; negative == left turn
const BANK_TEST_WIDTH := 16.0

var _managed: Array[Node] = []

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	for node in _managed:
		if is_instance_valid(node):
			node.free()
	_managed.clear()

func _track(node: Node) -> void:
	_managed.append(node)

## A LEFT-turn arc: travel +X then turn to -Z. `_frame` derives a NEGATIVE
## signed angle here, so a negative profile matches the turn's own sense.
func _left_arc_points() -> Array[Vector3]:
	return [
		Vector3(0, 0, 0),
		Vector3(100, 0, 0),
		Vector3(100, 0, -100),
	]

## A straight 3-point road (no curvature at all) -- the case the legacy path
## structurally cannot bank.
func _straight_points() -> Array[Vector3]:
	return [
		Vector3(0, 0, 0),
		Vector3(100, 0, 0),
		Vector3(200, 0, 0),
	]

## A closed 4-point square (motorway: width 16 => 2 lanes => one divider).
func _square_points() -> Array[Vector3]:
	return [
		Vector3(0, 0, 0),
		Vector3(100, 0, 0),
		Vector3(100, 0, 100),
		Vector3(0, 0, 100),
	]

func _first_surface_vertices(builder: TrackBuilder) -> PackedVector3Array:
	var mesh_instance := builder.get_child(0) as MeshInstance3D
	if mesh_instance == null:
		return PackedVector3Array()
	var mesh := mesh_instance.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return PackedVector3Array()
	var arrays := mesh.surface_get_arrays(0)
	return arrays[Mesh.ARRAY_VERTEX]

func _child_named_count(builder: TrackBuilder, prefix: String) -> int:
	var count := 0
	for child in builder.get_children():
		if String(child.name).begins_with(prefix):
			count += 1
	return count

## The two surface vertices of path point `i` for an open strip: (left, right).
func _edge_pair(vertices: PackedVector3Array, i: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	out.append(vertices[i * 2])
	out.append(vertices[i * 2 + 1])
	return out

func test_profile_overrides_curvature_on_a_left_arc() -> void:
	var points := _left_arc_points()
	var def := RoadDef.make(RoadDef.Tier.ARTERIAL, points, "", false)
	# banking == 0.0 => the legacy path would build a perfectly FLAT strip. Any
	# bank we measure therefore came from the profile, not from curvature.
	def.banking = 0.0
	def.bank_angles = PackedFloat32Array([0.0, PROFILE_ANGLE, 0.0])

	var builder := TrackBuilder.new()
	add_child(builder)
	_track(builder)
	builder.build_track(points, false, def)

	# The profile is stored verbatim (it sized exactly to the point count).
	assert_int(builder._bank_angles.size()).is_equal(points.size())

	# ARTERIAL is rail-enabled => surface + 2 edges + 2 rails + CollisionBody.
	assert_int(builder.get_child_count()).is_equal(6)

	var vertices := _first_surface_vertices(builder)
	assert_that(vertices.size() >= 4).is_true()
	if vertices.size() < 4:
		return

	var pair := _edge_pair(vertices, 1)
	var v_left: Vector3 = pair[0]
	var v_right: Vector3 = pair[1]
	var width: float = def.width
	var half_sin: float = (width * 0.5) * sin(PROFILE_ANGLE)

	# LEFT edge lower than RIGHT edge (mirror of the right-turn curvature test).
	assert_float(v_left.y).is_less(v_right.y)
	# Analytic offsets: left = +(w/2)*sin(a), right = -(w/2)*sin(a). Both are
	# ~-1.525 m / +1.525 m at width 10 and a = -0.31 rad.
	assert_float(v_left.y).is_equal_approx(half_sin, 0.001)
	assert_float(v_right.y).is_equal_approx(-half_sin, 0.001)
	# Profile really tilted the strip: |left| == |right| != 0.
	assert_float(v_left.y).is_less(-0.5)
	assert_float(v_right.y).is_greater(0.5)

	# Sanity: the two endpoints got the profile's zero entries => flat there.
	var end_pair := _edge_pair(vertices, 0)
	assert_float(end_pair[0].y).is_equal_approx(end_pair[1].y, 0.0001)

func test_profile_banks_a_straight_road() -> void:
	# A constant profile on a road with NO curvature: legacy banking cannot do
	# this (curvature is 0 on every point), so a bank here proves the profile is
	# independent of curvature and point spacing.
	var points := _straight_points()
	var def := RoadDef.make(RoadDef.Tier.ARTERIAL, points, "", false)
	def.banking = 0.0
	def.bank_angles = PackedFloat32Array([PROFILE_ANGLE, PROFILE_ANGLE, PROFILE_ANGLE])

	var builder := TrackBuilder.new()
	add_child(builder)
	_track(builder)
	builder.build_track(points, false, def)

	var vertices := _first_surface_vertices(builder)
	assert_that(vertices.size() >= 4).is_true()
	if vertices.size() < 4:
		return
	var pair := _edge_pair(vertices, 1)
	var half_sin: float = (def.width * 0.5) * sin(PROFILE_ANGLE)
	assert_float(pair[0].y).is_less(pair[1].y)
	assert_float(pair[0].y).is_equal_approx(half_sin, 0.001)
	assert_float(pair[1].y).is_equal_approx(-half_sin, 0.001)

	# The same straight with a banking multiplier and NO profile stays flat --
	# the legacy path's structural limitation the profile exists to lift.
	var flat_def := RoadDef.make(RoadDef.Tier.ARTERIAL, points, "", false)
	flat_def.banking = 0.4
	var flat := TrackBuilder.new()
	add_child(flat)
	_track(flat)
	flat.build_track(points, false, flat_def)
	assert_int(flat._bank_angles.size()).is_equal(0)
	var flat_vertices := _first_surface_vertices(flat)
	assert_that(flat_vertices.size() >= 4).is_true()
	if flat_vertices.size() < 4:
		return
	assert_float(flat_vertices[2].y).is_equal_approx(flat_vertices[3].y, 0.0001)

func test_zeroed_profile_keeps_strip_flat() -> void:
	var points := _left_arc_points()
	var def := RoadDef.make(RoadDef.Tier.ARTERIAL, points, "", false)
	def.banking = 0.0
	# Sizes exactly to the point count, so it IS the profile path (angle 0), not
	# an ignored array.
	def.bank_angles = PackedFloat32Array([0.0, 0.0, 0.0])

	var builder := TrackBuilder.new()
	add_child(builder)
	_track(builder)
	builder.build_track(points, false, def)
	assert_int(builder._bank_angles.size()).is_equal(points.size())

	var vertices := _first_surface_vertices(builder)
	assert_that(vertices.size() >= 6).is_true()
	if vertices.size() < 6:
		return
	for i in range(points.size()):
		var pair := _edge_pair(vertices, i)
		assert_float(pair[0].y).is_equal_approx(pair[1].y, 0.0001)

func test_wrong_sized_profile_falls_back_to_legacy_curvature() -> void:
	# One entry short of the point count: build_track must ignore it entirely and
	# leave _bank_angles empty, so the legacy curvature math runs unmasked.
	var points := _left_arc_points()
	var wrong_def := RoadDef.make(RoadDef.Tier.ARTERIAL, points, "", false)
	wrong_def.banking = 0.4
	wrong_def.bank_angles = PackedFloat32Array([PROFILE_ANGLE, PROFILE_ANGLE])

	var plain_def := RoadDef.make(RoadDef.Tier.ARTERIAL, points, "", false)
	plain_def.banking = 0.4

	var wrong := TrackBuilder.new()
	add_child(wrong)
	_track(wrong)
	wrong.build_track(points, false, wrong_def)
	var plain := TrackBuilder.new()
	add_child(plain)
	_track(plain)
	plain.build_track(points, false, plain_def)

	assert_int(wrong._bank_angles.size()).is_equal(0)
	assert_int(plain._bank_angles.size()).is_equal(0)

	var wrong_vertices := _first_surface_vertices(wrong)
	var plain_vertices := _first_surface_vertices(plain)
	assert_int(wrong_vertices.size()).is_equal(plain_vertices.size())
	if wrong_vertices.size() != plain_vertices.size():
		return
	var max_delta := 0.0
	for i in range(wrong_vertices.size()):
		max_delta = maxf(max_delta, wrong_vertices[i].distance_to(plain_vertices[i]))
	assert_float(max_delta).is_less(0.00001)

func test_show_lane_dividers_false_suppresses_only_divider_meshes() -> void:
	var points := _square_points()
	# Width 16 => lane_count_for == 2 => exactly one divider boundary.
	assert_int(RoadDef.lane_count_for(BANK_TEST_WIDTH)).is_equal(2)
	var expected_dividers := RoadDef.lane_count_for(BANK_TEST_WIDTH) - 1

	var shown_def := RoadDef.make(RoadDef.Tier.ARTERIAL, points, "", true, BANK_TEST_WIDTH)
	assert_bool(shown_def.show_lane_dividers).is_true()
	var shown := TrackBuilder.new()
	add_child(shown)
	_track(shown)
	shown.build_track(points, true, shown_def)

	var hidden_def := RoadDef.make(RoadDef.Tier.ARTERIAL, points, "", true, BANK_TEST_WIDTH)
	hidden_def.show_lane_dividers = false
	var hidden := TrackBuilder.new()
	add_child(hidden)
	_track(hidden)
	hidden.build_track(points, true, hidden_def)

	# Default keeps the divider(s); false removes them all.
	assert_int(_child_named_count(shown, "LaneDivider")).is_equal(expected_dividers)
	assert_int(_child_named_count(hidden, "LaneDivider")).is_equal(0)

	# Everything else is untouched: surface, both edge meshes and both rails.
	assert_int(_child_named_count(shown, "RoadSurface")).is_equal(1)
	assert_int(_child_named_count(hidden, "RoadSurface")).is_equal(1)
	assert_int(_child_named_count(shown, "RoadEdge")).is_equal(2)
	assert_int(_child_named_count(hidden, "RoadEdge")).is_equal(2)
	assert_int(_child_named_count(shown, "RoadRail")).is_equal(2)
	assert_int(_child_named_count(hidden, "RoadRail")).is_equal(2)
	assert_int(_child_named_count(shown, "CollisionBody")).is_equal(1)
	assert_int(_child_named_count(hidden, "CollisionBody")).is_equal(1)
	# The only child-count difference is the divider itself.
	assert_int(shown.get_child_count() - hidden.get_child_count()).is_equal(expected_dividers)

func test_profile_reaches_collision_and_rail_rebuild() -> void:
	var points := _left_arc_points()
	var def := RoadDef.make(RoadDef.Tier.ARTERIAL, points, "", false)
	def.banking = 0.0
	def.bank_angles = PackedFloat32Array([0.0, PROFILE_ANGLE, 0.0])

	var builder := TrackBuilder.new()
	add_child(builder)
	_track(builder)
	builder.build_track(points, false, def)

	# The collision surface is built from the same _frame as the visual strip, so
	# the profile flows into it too -- assert the body and its trimesh exist.
	var body := builder.get_node_or_null("CollisionBody") as StaticBody3D
	assert_that(body).is_not_null()
	if body == null:
		return
	assert_int(body.get_child_count()).is_equal(1)
	if body.get_child_count() < 1:
		return
	var shape_node := body.get_child(0) as CollisionShape3D
	assert_that(shape_node).is_not_null()
	if shape_node == null:
		return
	assert_that(shape_node.shape is ConcavePolygonShape3D).is_true()

	# configure_rails() rebuilds from the same members: the profile must survive
	# the rail rebuild (it re-reads _bank_angles, so the rails stay banked too).
	# A 6-point road so the gapped rail mesh still has segments -- a FULLY gapped
	# rail mesh is empty and Godot logs index-array errors (pre-existing behaviour
	# that test_multi_lane_rails also triggers).
	var long_points: Array[Vector3] = []
	for k in range(6):
		long_points.append(Vector3(float(k) * 100.0, 0, 0))
	var long_def := RoadDef.make(RoadDef.Tier.ARTERIAL, long_points, "", false)
	long_def.banking = 0.0
	long_def.bank_angles = PackedFloat32Array([
		PROFILE_ANGLE, PROFILE_ANGLE, PROFILE_ANGLE,
		PROFILE_ANGLE, PROFILE_ANGLE, PROFILE_ANGLE,
	])
	var rebuild := TrackBuilder.new()
	add_child(rebuild)
	_track(rebuild)
	rebuild.build_track(long_points, false, long_def)
	assert_int(rebuild._bank_angles.size()).is_equal(long_points.size())
	rebuild.configure_rails([long_points[3]] as Array)
	assert_int(rebuild._bank_angles.size()).is_equal(long_points.size())
	assert_int(_child_named_count(rebuild, "RoadRail")).is_equal(2)
	assert_int(_child_named_count(rebuild, "CollisionBody")).is_equal(1)
