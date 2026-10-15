# tests/suites/test_northern_isle_dressing.gd
extends GdUnitTestSuite

## P4 gate for the Northern Isle Speedway dressing
## (scripts/track/oval_dressing.gd — docs/plans/track_northern_isle_speedway.md §4 P4).
##
## `OvalDressing` is a deterministic, scene-free polyline builder: `configure()`
## it with the SAME centerline / bank profile the road mesh consumes, call
## `build()`, then read the placed transforms back through its query helpers.
## This suite pins exactly that contract, from the plan's P4 gate bullets:
##
##   * every referenced GLB loads with > 0 vertices (the `test_track_props`
##     loader assertion) and nothing is silently DROPPED (`dropped_kinds()`);
##   * the catch-fence run is `ceil(perimeter / 4)` posts, each riding the OUTER
##     road edge (`W/2 + 0.6`) in XZ and the banked road-edge height in Y —
##     checked BOTH with no terrain callable (the frame-math fallback) and with a
##     flat-0 stub callable (proving the callable is honoured);
##   * grandstands (>= 4) are each >= 11 m clear of the road
##     (`PropScatterer.is_clear_of_road`), billboards (>= 8) sit beyond the fence
##     radius, the gantry is centred on checkpoint 7 with a span >= the track
##     width, and the S/F paint is flat at cp7;
##   * no ground-bound item overlaps the road corridor (every origin >= W/2 from
##     the centerline);
##   * two builds — and a re-build of the SAME object — are identical.
##
## No scene, no RNG, no wall clock: the dressing is created under the suite and
## freed by `auto_free`, and every height is asserted either from a stub callable
## or the layout's own frame math, so it runs headless in ~1 s.

func _make_dressing(terrain: Callable = Callable()) -> OvalDressing:
	var dressing := auto_free(OvalDressing.new()) as OvalDressing
	dressing.configure(
		NorthernIsleLayout.build_centerline(),
		NorthernIsleLayout.build_bank_profile(),
		NorthernIsleLayout.WIDTH,
		terrain)
	dressing.build()
	return dressing

## A flat ground stub: everything sits on Y 0. Passing it in proves the dressing
## actually calls the configured `terrain_height` (the fallback would put the
## banked turns' edge/base heights well above 0).
func _flat_terrain(_pos: Vector3) -> float:
	return 0.0

## A one-road network carrying the oval centerline, so the suite can reuse the
## shared `PropScatterer` clearance contract instead of re-deriving half-widths.
func _oval_roads() -> RoadNetwork:
	var roads := auto_free(RoadNetwork.new()) as RoadNetwork
	roads.add_road(NorthernIsleLayout.build_centerline(), NorthernIsleLayout.WIDTH, true)
	return roads

func _centerline_distance(pos: Vector3, defs: Array[RoadDef]) -> float:
	return float(PropScatterer.road_clearance_info(pos, defs)["distance"])

## --- most diagnostic first: if a GLB cannot load, every placement is moot ----

func test_referenced_glbs_load_with_vertices() -> void:
	var dressing := _make_dressing()
	var kinds: Array[String] = [
		OvalDressing.KIND_BARRIER,
		OvalDressing.KIND_GRANDSTAND,
		OvalDressing.KIND_RACING_GRANDSTAND,
		OvalDressing.KIND_GANTRY,
		OvalDressing.KIND_LIGHT_POLE,
		OvalDressing.KIND_TENT,
		OvalDressing.KIND_GARAGE,
	]
	var paths: Array[String] = [
		OvalDressing.PATH_BARRIER,
		OvalDressing.PATH_GRANDSTAND,
		OvalDressing.PATH_RACING_GRANDSTAND,
		OvalDressing.PATH_GANTRY,
		OvalDressing.PATH_LIGHT_POLE,
		OvalDressing.PATH_TENT,
		OvalDressing.PATH_GARAGE,
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

## --- item 1: catch fence -----------------------------------------------------

func test_fence_posts_ride_the_outer_road_edge() -> void:
	var dressing := _make_dressing()  # no terrain callable: frame-math fallback
	var posts := dressing.fence_posts()
	var offset := NorthernIsleLayout.WIDTH * 0.5 + OvalDressing.FENCE_OFFSET
	var expected := int(ceil(NorthernIsleLayout.perimeter() / OvalDressing.FENCE_POST_SPACING))
	assert_that(posts.size()).is_between(expected - 1, expected + 1)
	assert_int(dressing.count_of(OvalDressing.KIND_FENCE_POST)).is_equal(posts.size())
	for i in posts.size():
		var arc := float(i) * OvalDressing.FENCE_POST_SPACING
		var frame := NorthernIsleLayout.frame_at_arc(arc)
		var center: Vector3 = frame["center"]
		var cross: Vector3 = frame["cross"]
		var delta := posts[i].origin - center
		# Outer (outfield) side: the signed offset along the horizontal cross
		# direction is the fence offset (the bank only shrinks its XZ length).
		var cross_h := Vector3(cross.x, 0.0, cross.z).normalized()
		assert_that(delta.dot(cross_h)).is_between(offset - 0.5, offset + 0.5)
		# The plan's ± 0.5 m XZ band around W/2 + 0.6.
		assert_that(absf(Vector2(delta.x, delta.z).length() - offset)).is_less_equal(0.5)
		# Y is the banked road-edge height from the SAME frame math the mesh uses.
		assert_that(posts[i].origin.y).is_between(center.y + cross.y * offset - 0.05, \
			center.y + cross.y * offset + 0.05)

func test_fence_post_count_tolerates_the_measured_perimeter() -> void:
	# ceil(895..905 / 4) == 225 for the analytic perimeter; a chain measured from
	# the configured 304-point centerline lands within ±1 of that (chord vs arc).
	var dressing := _make_dressing()
	var posts := dressing.fence_posts()
	assert_that(posts.size()).is_greater_equal(224)
	assert_that(posts.size()).is_less_equal(226)
	assert_int(dressing.count_of(OvalDressing.KIND_FENCE_POST)).is_equal(posts.size())
	assert_int(dressing.barrier_transforms().size()).is_equal(posts.size())

func test_fence_panel_is_a_single_continuous_strip() -> void:
	var dressing := _make_dressing()
	assert_object(dressing.get_node_or_null("FencePanel")).is_not_null()
	assert_object(dressing.get_node_or_null("FencePosts")).is_not_null()
	var panel := dressing.prop_mesh(OvalDressing.KIND_FENCE_PANEL)
	assert_object(panel).is_not_null()
	if panel == null:
		return
	var arrays := panel.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# One quad (6 vertices) per fence segment: a continuous strip, not a gap.
	assert_int(vertices.size()).is_equal(dressing.fence_posts().size() * 6)

func test_fence_and_infield_follow_the_terrain_callable() -> void:
	# A configured terrain callable must be HONOURED: with a flat-0 stub, every
	# ground-bound piece sits on Y 0 (the no-callable fallback would lift the
	# banked turns' fence/base well above it).
	var dressing := _make_dressing(Callable(self, "_flat_terrain"))
	var posts := dressing.fence_posts()
	assert_int(posts.size()).is_greater(0)
	for post: Transform3D in posts:
		assert_that(post.origin.y).is_between(-0.001, 0.001)
	for barrier: Transform3D in dressing.barrier_transforms():
		assert_that(barrier.origin.y).is_between(-0.001, 0.001)
	for pole: Transform3D in dressing.light_pole_transforms():
		assert_that(pole.origin.y).is_between(-0.001, 0.001)
	for tent: Transform3D in dressing.tent_transforms():
		assert_that(tent.origin.y).is_between(-0.001, 0.001)
	for row: Transform3D in dressing.grandstand_transforms():
		assert_that(row.origin.y).is_between(-0.001, 0.001)
	# Billboards are lifted a fixed height above the ground datum.
	for board: Transform3D in dressing.billboard_transforms():
		assert_that(board.origin.y).is_between(OvalDressing.BILLBOARD_HEIGHT - 0.001, \
			OvalDressing.BILLBOARD_HEIGHT + 0.001)

## --- item 3: grandstands -----------------------------------------------------

func test_grandstands_are_placed_and_clear_of_the_road() -> void:
	var dressing := _make_dressing()
	var rows := dressing.grandstand_transforms()
	assert_that(rows.size()).is_greater_equal(4)
	assert_int(dressing.count_of(OvalDressing.KIND_GRANDSTAND)).is_equal(3)
	assert_int(dressing.count_of(OvalDressing.KIND_RACING_GRANDSTAND)).is_equal(1)
	var roads := _oval_roads()
	var defs := roads.get_road_defs()
	for row: Transform3D in rows:
		# The shared contract: half-width (8 m) + 3 m margin == 11 m.
		assert_bool(PropScatterer.is_clear_of_road(row.origin, roads)).is_true()
		assert_that(_centerline_distance(row.origin, defs)).is_greater_equal(11.0)

## --- item 4/5: S/F gantry + paint -------------------------------------------

func test_gantry_is_centred_on_checkpoint_seven_and_spans_the_road() -> void:
	var dressing := _make_dressing()
	assert_bool(dressing.gantry_ok()).is_true()
	var cp7 := NorthernIsleLayout.point_at_arc(NorthernIsleLayout.start_line_arc())
	var center := dressing.gantry_center()
	var xz := Vector2(center.x - cp7.x, center.z - cp7.z).length()
	assert_that(xz).is_less_equal(2.0)
	assert_that(dressing.gantry_span()).is_greater_equal(NorthernIsleLayout.WIDTH)
	# The beam straddles the road: its long axis is the road's horizontal cross
	# direction, so it is perpendicular to the tangent at cp7.
	var frame := NorthernIsleLayout.frame_at_arc(NorthernIsleLayout.start_line_arc())
	var forward: Vector3 = frame["forward"]
	var right: Vector3 = frame["right"]
	var beam := dressing.gantry_transform().basis.x.normalized()
	assert_that(absf(beam.dot(Vector3(forward.x, 0.0, forward.z).normalized()))).is_less_equal(0.05)
	assert_that(absf(beam.dot(Vector3(right.x, 0.0, right.z).normalized()))).is_greater_equal(0.99)

func test_start_finish_paint_is_flat_over_the_line() -> void:
	var dressing := _make_dressing()
	assert_bool(dressing.checker_ok()).is_true()
	var cp7 := NorthernIsleLayout.point_at_arc(NorthernIsleLayout.start_line_arc())
	var paint := dressing.checker_transform()
	var xz := Vector2(paint.origin.x - cp7.x, paint.origin.z - cp7.z).length()
	assert_that(xz).is_less_equal(0.5)
	# Flat (θ = 0 at cp7) and only a hair above the road surface.
	assert_that(paint.basis.y.dot(Vector3.UP)).is_equal_approx(1.0, 0.001)
	assert_that(paint.origin.y - cp7.y).is_between(-0.001, OvalDressing.CHECKER_LIFT + 0.001)

## --- item 6: billboards ------------------------------------------------------

func test_billboards_are_sponsor_boards_beyond_the_fence() -> void:
	var dressing := _make_dressing()
	var boards := dressing.billboard_transforms()
	var labels := dressing.billboard_labels()
	assert_that(boards.size()).is_greater_equal(8)
	assert_int(boards.size()).is_equal(OvalDressing.BILLBOARD_PER_STRAIGHT * 2)
	assert_int(labels.size()).is_equal(boards.size())
	for i in labels.size():
		assert_that(labels[i]).is_equal(OvalDressing.BILLBOARD_TEXTS[i])
	var roads := _oval_roads()
	var defs := roads.get_road_defs()
	for board: Transform3D in boards:
		assert_that(_centerline_distance(board.origin, defs)).is_greater(dressing.fence_offset())
	# Both straights carry a row, on opposite sides of the oval.
	var front := 0
	var back := 0
	for board: Transform3D in boards:
		if board.origin.z > 0.0:
			front += 1
		else:
			back += 1
	assert_int(front).is_equal(OvalDressing.BILLBOARD_PER_STRAIGHT)
	assert_int(back).is_equal(OvalDressing.BILLBOARD_PER_STRAIGHT)

## --- item 7: infield + light poles -------------------------------------------

func test_infield_and_light_poles_are_placed() -> void:
	var dressing := _make_dressing()
	assert_int(dressing.count_of(OvalDressing.KIND_TENT)).is_equal(2)
	assert_int(dressing.count_of(OvalDressing.KIND_GARAGE)).is_equal(1)
	assert_int(dressing.count_of(OvalDressing.KIND_LIGHT_POLE)).is_equal(OvalDressing.LIGHT_POLE_COUNT)
	var roads := _oval_roads()
	var defs := roads.get_road_defs()
	for tent: Transform3D in dressing.tent_transforms():
		assert_bool(PropScatterer.is_clear_of_road(tent.origin, roads)).is_true()
	for garage: Transform3D in dressing.garage_transforms():
		assert_bool(PropScatterer.is_clear_of_road(garage.origin, roads)).is_true()
	# Light poles ring the plain, well outside the fence.
	for pole: Transform3D in dressing.light_pole_transforms():
		assert_that(_centerline_distance(pole.origin, defs)).is_greater_equal(30.0)

## --- the road-corridor gate --------------------------------------------------

func test_no_ground_dressing_overlaps_the_road_corridor() -> void:
	var dressing := _make_dressing()
	var ground := dressing.ground_transforms()
	var expected := dressing.count_of(OvalDressing.KIND_FENCE_POST) \
		+ dressing.count_of(OvalDressing.KIND_BARRIER) \
		+ dressing.grandstand_transforms().size() \
		+ dressing.count_of(OvalDressing.KIND_BILLBOARD) \
		+ dressing.count_of(OvalDressing.KIND_LIGHT_POLE) \
		+ dressing.count_of(OvalDressing.KIND_TENT) \
		+ dressing.count_of(OvalDressing.KIND_GARAGE)
	assert_int(ground.size()).is_equal(expected)
	# The gantry (over the road) and the paint quad (on it) are deliberately
	# excluded from this list; everything else must be outside the carriageway.
	var defs := _oval_roads().get_road_defs()
	var half := NorthernIsleLayout.WIDTH * 0.5
	for item: Transform3D in ground:
		assert_that(_centerline_distance(item.origin, defs)).is_greater(half)

## --- determinism -------------------------------------------------------------

func test_two_builds_and_a_rebuild_are_identical() -> void:
	var a := _make_dressing()
	var b := _make_dressing()
	assert_int(a.signature().size()).is_greater(400)
	assert_bool(a.signature() == b.signature()).is_true()
	# Per-kind transform sets agree element-wise, too.
	assert_bool(a.fence_posts() == b.fence_posts()).is_true()
	assert_bool(a.barrier_transforms() == b.barrier_transforms()).is_true()
	assert_bool(a.grandstand_transforms() == b.grandstand_transforms()).is_true()
	assert_bool(a.billboard_transforms() == b.billboard_transforms()).is_true()
	assert_bool(a.light_pole_transforms() == b.light_pole_transforms()).is_true()
	# Re-building the SAME object is idempotent (children are cleared first).
	var first := a.signature()
	a.build()
	assert_bool(a.signature() == first).is_true()

## --- the "usable with no scene" contract -------------------------------------

func test_builds_with_no_scene_and_an_empty_bank_profile() -> void:
	# No terrain callable AND an empty bank profile (the caller may not have one
	# yet) — the dressing falls back to the layout's continuous bank query and
	# still produces the full set.
	var dressing := auto_free(OvalDressing.new()) as OvalDressing
	assert_bool(dressing.is_built()).is_false()
	dressing.configure(
		NorthernIsleLayout.build_centerline(),
		PackedFloat32Array(),
		NorthernIsleLayout.WIDTH)
	dressing.build()
	assert_bool(dressing.is_built()).is_true()
	var expected := int(ceil(NorthernIsleLayout.perimeter() / OvalDressing.FENCE_POST_SPACING))
	assert_that(dressing.fence_posts().size()).is_between(expected - 1, expected + 1)
	assert_bool(dressing.gantry_ok()).is_true()
	assert_bool(dressing.dropped_kinds().is_empty()).is_true()
