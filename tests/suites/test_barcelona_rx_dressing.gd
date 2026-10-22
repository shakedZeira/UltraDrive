# tests/suites/test_barcelona_rx_dressing.gd
extends GdUnitTestSuite

## P3 gate for the Circuit de Barcelona-Catalunya — Rallycross dressing
## (scripts/track/rx_dressing.gd — docs/plans/track_barcelona_rallycross.md §3.4,
## §5 suite 3). Mirrors `test_northern_isle_dressing.gd`'s structure.
##
## `RxDressing` is a deterministic, scene-free polyline builder: `configure()` it
## with the SAME centerline / bank profile the road mesh consumes, call
## `build()`, then read the placed transforms back through its query helpers.
## This suite pins exactly that contract, from the plan's P3 gate bullets:
##
##   * every referenced GLB loads with > 0 vertices (the `test_track_props`
##     loader assertion) and nothing is silently DROPPED (`dropped_kinds()`);
##   * the S/F gantry straddles the 12 m road (span >= WIDTH) and is centred on
##     the start/finish line; the S/F paint is a flat quad over that line;
##   * the barrier line runs the `barrier_arc_ranges()` (T1/T2/T6) at
##     `W/2 + BARRIER_OFFSET` on the OUTFIELD side, one instance per
##     `BARRIER_SPACING` m of arc;
##   * the apex cones sit just INSIDE the road edge (one short run per corner) and
##     are deliberately excluded from the corridor gate; the start flag sits
##     outfield of the barrier line;
##   * no ground-bound item (barrier / flag) overlaps the road corridor;
##   * a configured terrain callable is HONOURED (barrier + flag sit on it);
##   * two builds — and a re-build of the SAME object — are identical;
##   * the builder works with no scene and an empty bank profile.
##
## No scene, no RNG, no wall clock: the dressing is created under the suite and
## freed by `auto_free`, and every height is asserted either from a stub callable
## or the layout's own frame math, so it runs headless in ~1 s.

## Re-measured from the barrier GLB at `RxDressing.BARRIER_SCALE`; restated here
## (like the barrier gate restates it) so loosening the script cannot loosen the
## gate.
const RED_BARRIER_VISUAL_TOP := 1.57

func _make_dressing(terrain: Callable = Callable()) -> RxDressing:
	var dressing := auto_free(RxDressing.new()) as RxDressing
	dressing.configure(
		BarcelonaRxLayout.build_centerline(),
		BarcelonaRxLayout.build_bank_profile(),
		BarcelonaRxLayout.WIDTH,
		terrain)
	dressing.build()
	return dressing

## A flat ground stub: everything sits on Y 0. Passing it in proves the dressing
## actually calls the configured `terrain_height` (the fallback would put the
## banked turns' base heights well above 0).
func _flat_terrain(_pos: Vector3) -> float:
	return 0.0

## A one-road network carrying the circuit centerline, so the suite can reuse the
## shared `PropScatterer` clearance contract instead of re-deriving half-widths.
func _circuit_roads() -> RoadNetwork:
	var roads := auto_free(RoadNetwork.new()) as RoadNetwork
	roads.add_road(BarcelonaRxLayout.build_centerline(), BarcelonaRxLayout.WIDTH, true)
	return roads

func _centerline_distance(pos: Vector3, defs: Array[RoadDef]) -> float:
	return float(PropScatterer.road_clearance_info(pos, defs)["distance"])

## One instance per `BARRIER_SPACING` m step across every barrier arc.
func _expected_barrier_count() -> int:
	var total := 0
	for r: Vector2 in BarcelonaRxLayout.barrier_arc_ranges():
		total += int(ceil((r.y - r.x) / RxDressing.BARRIER_SPACING))
	return total

## --- most diagnostic first: if a GLB cannot load, every placement is moot ----

func test_referenced_glbs_load_with_vertices() -> void:
	var dressing := _make_dressing()
	var kinds: Array[String] = [
		RxDressing.KIND_BARRIER,
		RxDressing.KIND_GANTRY,
		RxDressing.KIND_CONE,
		RxDressing.KIND_FLAG,
	]
	var paths: Array[String] = [
		RxDressing.PATH_BARRIER,
		RxDressing.PATH_GANTRY,
		RxDressing.PATH_CONE,
		RxDressing.PATH_FLAG,
	]
	assert_int(kinds.size()).is_equal(paths.size())
	var loaded := dressing.referenced_glb_paths()
	for i in kinds.size():
		var mesh := dressing.prop_mesh(kinds[i])
		assert_object(mesh).is_not_null()
		if mesh == null:
			continue
		assert_int(mesh.get_surface_count()).is_greater(0)
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		assert_int(vertices.size()).is_greater(0)
		assert_bool(loaded.has(paths[i])).is_true()
	# Nothing was dropped: every kind in the plan's list is present.
	assert_bool(dressing.dropped_kinds().is_empty()).is_true()

## --- items 1/2: S/F gantry + paint ------------------------------------------

func test_gantry_is_centred_on_the_start_line_and_spans_the_road() -> void:
	var dressing := _make_dressing()
	assert_bool(dressing.gantry_ok()).is_true()
	var line_point := BarcelonaRxLayout.point_at_arc(BarcelonaRxLayout.start_line_arc())
	var center := dressing.gantry_center()
	var xz := Vector2(center.x - line_point.x, center.z - line_point.z).length()
	assert_that(xz).is_less_equal(2.0)
	assert_that(dressing.gantry_span()).is_greater_equal(BarcelonaRxLayout.WIDTH)
	# The beam straddles the road: its long axis is the road's horizontal cross
	# direction, so it is perpendicular to the tangent at the line.
	var frame := BarcelonaRxLayout.frame_at_arc(BarcelonaRxLayout.start_line_arc())
	var forward: Vector3 = frame["forward"]
	var right: Vector3 = frame["right"]
	var beam := dressing.gantry_transform().basis.x.normalized()
	assert_that(absf(beam.dot(Vector3(forward.x, 0.0, forward.z).normalized()))).is_less_equal(0.05)
	assert_that(absf(beam.dot(Vector3(right.x, 0.0, right.z).normalized()))).is_greater_equal(0.99)

func test_start_finish_paint_is_flat_over_the_line() -> void:
	var dressing := _make_dressing()
	assert_bool(dressing.checker_ok()).is_true()
	var line_point := BarcelonaRxLayout.point_at_arc(BarcelonaRxLayout.start_line_arc())
	var paint := dressing.checker_transform()
	var xz := Vector2(paint.origin.x - line_point.x, paint.origin.z - line_point.z).length()
	assert_that(xz).is_less_equal(0.5)
	# Flat (the line is on the start straight, bank 0) and only a hair above the
	# dirt surface.
	assert_that(paint.basis.y.dot(Vector3.UP)).is_equal_approx(1.0, 0.001)
	assert_that(paint.origin.y - line_point.y).is_between(-0.001, RxDressing.CHECKER_LIFT + 0.001)

## --- item 3: barrier line ----------------------------------------------------

func test_barrier_line_rides_the_outfield_edge_along_the_arcs() -> void:
	var dressing := _make_dressing()
	var barriers := dressing.barrier_transforms()
	assert_int(barriers.size()).is_equal(_expected_barrier_count())
	assert_int(dressing.count_of(RxDressing.KIND_BARRIER)).is_equal(barriers.size())

	var roads := _circuit_roads()
	var defs := roads.get_road_defs()
	var expected_line := BarcelonaRxLayout.WIDTH * 0.5 + RxDressing.BARRIER_OFFSET
	for barrier: Transform3D in barriers:
		var d := _centerline_distance(barrier.origin, defs)
		# On the banked cross-section the XZ offset is `line * cos(bank)`; only
		# T2/T6 berm (7 deg), so the whole set lands well inside +-0.5 m.
		assert_that(d).is_between(expected_line - 0.5, expected_line + 0.5)
		# Outfield of the carriageway: a right-hand turn's outside is the LEFT of
		# travel, and the line sits 1.6 m beyond the road edge. It is deliberately
		# INSIDE `PropScatterer`'s `half + ROAD_CLEARANCE_MARGIN` (9 m) scatter
		# margin -- that margin is for scattered props, not the barrier line.
		assert_that(d).is_greater(BarcelonaRxLayout.WIDTH * 0.5)

func test_barrier_line_count_matches_the_barrier_arc_length() -> void:
	# ceil(barrier arc-length / 4) != the per-arc ceil sum, so assert both are
	# within one box of each other and the total is sane for T1/T2/T6.
	var dressing := _make_dressing()
	var count := dressing.barrier_transforms().size()
	var coarse := int(ceil(BarcelonaRxLayout.barrier_arc_length() / RxDressing.BARRIER_SPACING))
	assert_that(count).is_between(coarse - 3, coarse + 3)
	assert_float(BarcelonaRxLayout.barrier_arc_length()).is_greater(150.0)
	assert_float(BarcelonaRxLayout.barrier_arc_length()).is_less(180.0)

## --- item 4: apex cones ------------------------------------------------------

func test_apex_cones_sit_just_inside_the_road_edge() -> void:
	var dressing := _make_dressing()
	var cones := dressing.cone_transforms()
	# 7 corners, one short arc run each: `2 * max(1, int(CONE_ARC_HALF / CONE_SPACING)) + 1`.
	var steps := maxi(1, int(RxDressing.CONE_ARC_HALF / RxDressing.CONE_SPACING))
	var expected := BarcelonaRxLayout.corner_names().size() * (2 * steps + 1)
	assert_int(cones.size()).is_equal(expected)
	assert_int(dressing.count_of(RxDressing.KIND_CONE)).is_equal(cones.size())

	var roads := _circuit_roads()
	var defs := roads.get_road_defs()
	var inner_line := BarcelonaRxLayout.WIDTH * 0.5 - RxDressing.CONE_INSET
	for cone: Transform3D in cones:
		var d := _centerline_distance(cone.origin, defs)
		assert_that(d).is_between(inner_line - 0.6, inner_line + 0.6)
		# By design a cone sits INSIDE the carriageway band, so it is excluded
		# from `ground_transforms()`.
		assert_that(d).is_less(BarcelonaRxLayout.WIDTH * 0.5)

## --- item 5: start flag ------------------------------------------------------

func test_start_flag_sits_outfield_of_the_barrier_line() -> void:
	var dressing := _make_dressing()
	var flags := dressing.flag_transforms()
	assert_int(flags.size()).is_equal(1)
	assert_int(dressing.count_of(RxDressing.KIND_FLAG)).is_equal(1)
	var roads := _circuit_roads()
	var defs := roads.get_road_defs()
	var expected_line := BarcelonaRxLayout.WIDTH * 0.5 + RxDressing.FLAG_OFFSET
	for flag: Transform3D in flags:
		var d := _centerline_distance(flag.origin, defs)
		assert_that(d).is_between(expected_line - 0.5, expected_line + 0.5)

## --- callable honoured -------------------------------------------------------

func test_ground_dressing_follows_the_terrain_callable() -> void:
	# A configured terrain callable must be HONOURED: with a flat-0 stub the
	# barrier + flag bases sit on Y 0 (the no-callable fallback would lift the
	# bermed turns' bases well above it). Cones read the frame math on purpose,
	# so they are excluded here.
	var dressing := _make_dressing(Callable(self, "_flat_terrain"))
	var barriers := dressing.barrier_transforms()
	assert_int(barriers.size()).is_greater(0)
	for barrier: Transform3D in barriers:
		assert_that(barrier.origin.y).is_between(-0.001, 0.001)
	for flag: Transform3D in dressing.flag_transforms():
		assert_that(flag.origin.y).is_between(-0.001, 0.001)

## --- the road-corridor gate --------------------------------------------------

func test_no_ground_dressing_overlaps_the_road_corridor() -> void:
	var dressing := _make_dressing()
	var ground := dressing.ground_transforms()
	var expected := dressing.count_of(RxDressing.KIND_BARRIER) \
		+ dressing.count_of(RxDressing.KIND_FLAG)
	assert_int(ground.size()).is_equal(expected)
	# The gantry (over the road), the paint quad (on it) and the apex cones (on
	# the dirt) are deliberately excluded; everything else must be outside the
	# carriageway.
	var defs := _circuit_roads().get_road_defs()
	var half := BarcelonaRxLayout.WIDTH * 0.5
	for item: Transform3D in ground:
		assert_that(_centerline_distance(item.origin, defs)).is_greater(half)

## --- determinism -------------------------------------------------------------

func test_two_builds_and_a_rebuild_are_identical() -> void:
	var a := _make_dressing()
	var b := _make_dressing()
	assert_int(a.signature().size()).is_greater(30)
	assert_bool(a.signature() == b.signature()).is_true()
	# Per-kind transform sets agree element-wise, too.
	assert_bool(a.barrier_transforms() == b.barrier_transforms()).is_true()
	assert_bool(a.cone_transforms() == b.cone_transforms()).is_true()
	assert_bool(a.flag_transforms() == b.flag_transforms()).is_true()
	assert_bool(a.gantry_transform() == b.gantry_transform()).is_true()
	# Re-building the SAME object is idempotent (children are cleared first).
	var first := a.signature()
	a.build()
	assert_bool(a.signature() == first).is_true()

## --- the "usable with no scene" contract -------------------------------------

func test_builds_with_no_scene_and_an_empty_bank_profile() -> void:
	# No terrain callable AND an empty bank profile (the caller may not have one
	# yet) — the dressing falls back to the layout's continuous bank query and
	# still produces the full set.
	var dressing := auto_free(RxDressing.new()) as RxDressing
	assert_bool(dressing.is_built()).is_false()
	dressing.configure(
		BarcelonaRxLayout.build_centerline(),
		PackedFloat32Array(),
		BarcelonaRxLayout.WIDTH)
	dressing.build()
	assert_bool(dressing.is_built()).is_true()
	assert_int(dressing.barrier_transforms().size()).is_equal(_expected_barrier_count())
	assert_bool(dressing.gantry_ok()).is_true()
	assert_bool(dressing.checker_ok()).is_true()
	assert_bool(dressing.dropped_kinds().is_empty()).is_true()
	# The measured chain length is the layout's ~1133 m perimeter (chord sum, so
	# a hair short).
	assert_float(dressing.perimeter()).is_between(1100.0, 1160.0)
