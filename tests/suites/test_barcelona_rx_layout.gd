# tests/suites/test_barcelona_rx_layout.gd
extends GdUnitTestSuite

## P0 gate for Circuit de Barcelona-Catalunya — Rallycross geometry
## (scripts/track/barcelona_rx_layout.gd — see
## docs/plans/track_barcelona_rallycross.md P0).
##
## The layout is the single source of truth every later phase reads: the road
## mesh and its trimesh collision (P1/P2), the bake (P2) and the dressing /
## barrier colliders (P3) all derive from these builders. So this is a PURE-MATH
## suite — no scene, no engine state, no wall clock — and every assertion is
## about a documented constant or invariant from the plan.
##
## What is pinned here:
##   * the constant table (perimeter target, width, the 400-point / 8-checkpoint
##     contract, the generation offset, the berm/jump/barrier tables);
##   * a 400-point, closed, uniform-arc-length chain whose footprint stays inside
##     the +-240 m terrain pane;
##   * the inner-edge invariant `y = ROAD_BASE_Y + (W/2)|sin(bank)| + jump_lift`
##     (the mirror of build #1's left-edge invariant, generalized for the jump);
##   * the signed bank profile: 0.0 outside every berm, +7 deg at both bermed
##     apexes, sine-eased AND monotone through each ramp, never negative;
##   * direction is CW/right in the exact sign space TrackBuilder._frame uses
##     (cross(t1, t2).y < 0 -> POSITIVE signed bank angle);
##   * two jump crests (1.0 / 0.8 m), ramp slope <= 20 deg, zero lift outside
##     both arcs and on the straights the line/grid sit on;
##   * the checkpoint / lap-line contract (8 stride-50 checkpoints, the line on
##     index 7) and the 7 ordered corners;
##   * determinism of both builders, the frame contract and the closed wrap.

const POSITION_EPS := 0.001
const ANGLE_EPS := 0.0001

## True when `arc` sits inside a BANK_REGIONS berm window (bank may be non-zero
## there; everywhere else the road is flat).
func _in_berm(arc: float) -> bool:
	for r in BarcelonaRxLayout.BANK_REGIONS:
		var apex := BarcelonaRxLayout.corner_apex_arc(int(r["corner"]))
		var half: float = r["half_arc"]
		if arc >= apex - half and arc <= apex + half:
			return true
	return false

## Indices strictly inside a corner arc and clear of both tangent points (6 m of
## margin), so the discrete cross-product direction test is unambiguous.
func _corner_sample_indices() -> Array[int]:
	var out: Array[int] = []
	var margin := 6.0
	for r in BarcelonaRxLayout.corner_arc_ranges():
		for i in BarcelonaRxLayout.TOTAL_POINTS:
			var arc := BarcelonaRxLayout.arc_of_index(i)
			if arc >= r.x + margin and arc <= r.y - margin:
				out.append(i)
	return out

func test_constant_table() -> void:
	assert_float(BarcelonaRxLayout.TARGET_PERIMETER).is_equal_approx(1133.0, 0.0001)
	assert_float(BarcelonaRxLayout.WIDTH).is_equal_approx(12.0, 0.0001)
	assert_float(BarcelonaRxLayout.ROAD_BASE_Y).is_equal_approx(0.15, 0.0001)
	assert_float(BarcelonaRxLayout.PLAIN_Y).is_equal_approx(-0.25, 0.0001)
	assert_float(BarcelonaRxLayout.BLEND_RUN).is_equal_approx(18.0, 0.0001)
	assert_float(BarcelonaRxLayout.EDGE_DROP).is_equal_approx(0.10, 0.0001)
	assert_float(BarcelonaRxLayout.BANK_MAX_DEG).is_equal_approx(7.0, 0.0001)
	assert_float(BarcelonaRxLayout.OFF).is_equal_approx(160.0, 0.0001)
	assert_float(BarcelonaRxLayout.OUTFIELD_SIDE).is_equal_approx(-1.0, 0.0001)
	assert_int(BarcelonaRxLayout.TOTAL_POINTS).is_equal(400)
	assert_int(BarcelonaRxLayout.CHECKPOINT_COUNT).is_equal(8)
	assert_int(BarcelonaRxLayout.CP_STRIDE).is_equal(50)
	assert_int(BarcelonaRxLayout.START_LINE_INDEX).is_equal(7)

	# Generation tables.
	assert_int(BarcelonaRxLayout.VERTICES.size()).is_equal(7)
	assert_int(BarcelonaRxLayout.TFRAC.size()).is_equal(7)
	assert_int(BarcelonaRxLayout.BANK_REGIONS.size()).is_equal(2)
	assert_int(BarcelonaRxLayout.JUMP_REGIONS.size()).is_equal(2)
	assert_that(BarcelonaRxLayout.BARRIER_CORNERS).is_equal(PackedInt32Array([1, 2, 6]))

	# Perimeter target and derived spacing.
	assert_float(BarcelonaRxLayout.perimeter()).is_equal_approx(1133.0, 0.0001)
	assert_float(BarcelonaRxLayout.perimeter()).is_greater_equal(1123.0)
	assert_float(BarcelonaRxLayout.perimeter()).is_less_equal(1143.0)
	assert_float(BarcelonaRxLayout.spacing()).is_equal_approx(1133.0 / 400.0, ANGLE_EPS)
	assert_float(BarcelonaRxLayout.arc_of_index(0)).is_equal_approx(0.0, ANGLE_EPS)
	assert_float(BarcelonaRxLayout.arc_of_index(399)).is_equal_approx(399.0 * BarcelonaRxLayout.spacing(), ANGLE_EPS)

	# 8 * 50 == 400: every checkpoint lands exactly on a point.
	assert_int(BarcelonaRxLayout.CHECKPOINT_COUNT * BarcelonaRxLayout.CP_STRIDE).is_equal(
		BarcelonaRxLayout.TOTAL_POINTS)

func test_centerline_is_closed_uniform_and_inside_the_pane() -> void:
	var points := BarcelonaRxLayout.build_centerline()
	assert_int(points.size()).is_equal(BarcelonaRxLayout.TOTAL_POINTS)
	if points.size() != BarcelonaRxLayout.TOTAL_POINTS:
		return

	# The chain closes: the wrap segment (last -> first) is one spacing long.
	assert_float(points[0].distance_to(points[points.size() - 1])).is_equal_approx(
		BarcelonaRxLayout.spacing(), 0.05)

	# Uniform arc-length spacing, INCLUDING the closing segment: the worst
	# segment is the arc chord vs the straight chord, far inside the 2 % band.
	var min_length := INF
	var max_length := 0.0
	for i in points.size():
		var next: Vector3 = points[(i + 1) % points.size()]
		var length := points[i].distance_to(next)
		min_length = minf(min_length, length)
		max_length = maxf(max_length, length)
	assert_float(max_length / min_length).is_less_equal(1.02)
	assert_float(min_length).is_greater(2.7)
	assert_float(max_length).is_less(2.95)

	# Footprint: comfortably inside the +-240 m terrain pane (the import_images
	# snap margin the scene bake relies on).
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p: Vector3 in points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	assert_float(absf(min_x)).is_less(240.0)
	assert_float(absf(max_x)).is_less(240.0)
	assert_float(absf(min_z)).is_less(240.0)
	assert_float(absf(max_z)).is_less(240.0)
	# The whole loop is a single contiguous circuit, not a folded curve: a
	# plausible rallycross footprint (assert the order of magnitude, not a
	# hardcoded number that tuning would break).
	assert_float(max_x - min_x).is_greater(200.0)
	assert_float(max_z - min_z).is_greater(200.0)

func test_inner_edge_rides_at_road_base_y() -> void:
	# THE load-bearing invariant, generalized for the jump: the centerline lift
	# is the bank lift PLUS the jump lift, both derived from the same profile the
	# mesh consumes, so the inner/right edge lands on ROAD_BASE_Y wherever the
	# jump is flat. Hand-editing either side alone breaks road/ground contact.
	var points := BarcelonaRxLayout.build_centerline()
	var half_width := BarcelonaRxLayout.WIDTH * 0.5
	var banked := 0
	var lifted := 0
	for i in points.size():
		var arc := BarcelonaRxLayout.arc_of_index(i)
		var bank := BarcelonaRxLayout.bank_rad_at_arc(arc)
		var lift := BarcelonaRxLayout.jump_lift(arc)
		var expected := BarcelonaRxLayout.ROAD_BASE_Y + half_width * absf(sin(bank)) + lift
		assert_float(points[i].y).is_equal_approx(expected, POSITION_EPS)
		# Where there is no jump lift the inner edge is exactly ROAD_BASE_Y.
		if is_zero_approx(lift):
			assert_float(points[i].y - half_width * absf(sin(bank))).is_equal_approx(
				BarcelonaRxLayout.ROAD_BASE_Y, POSITION_EPS)
		else:
			lifted += 1
		if not is_zero_approx(bank):
			banked += 1
	assert_int(banked).is_greater(0)
	assert_int(banked).is_less(points.size())
	# The jump lift really is present on the sampled chain.
	assert_int(lifted).is_greater(0)

	# Bermed-apex centre lift is (W/2) * sin(7 deg) ~= 0.731 m above base.
	var apex_bank := deg_to_rad(BarcelonaRxLayout.BANK_MAX_DEG)
	assert_float(half_width * absf(sin(apex_bank))).is_equal_approx(0.731, 0.01)

func test_bank_profile_is_flat_outside_berms_and_max_at_the_apexes() -> void:
	var profile := BarcelonaRxLayout.build_bank_profile()
	assert_int(profile.size()).is_equal(BarcelonaRxLayout.TOTAL_POINTS)
	var max_bank := deg_to_rad(BarcelonaRxLayout.BANK_MAX_DEG)
	for i in profile.size():
		var arc := BarcelonaRxLayout.arc_of_index(i)
		# The profile array and the public arc query are the same function.
		assert_float(profile[i]).is_equal_approx(BarcelonaRxLayout.bank_rad_at_arc(arc), ANGLE_EPS)
		# Right turns only: the signed bank is never negative.
		assert_float(profile[i]).is_greater_equal(-1.0e-9)
		assert_float(profile[i]).is_less_equal(max_bank + 1.0e-6)
		if not _in_berm(arc):
			assert_float(profile[i]).is_equal_approx(0.0, 1.0e-9)

	# Both bermed apexes carry exactly +7 deg (continuous query).
	for corner: int in [2, 6]:
		var apex := BarcelonaRxLayout.corner_apex_arc(corner)
		assert_float(BarcelonaRxLayout.bank_rad_at_arc(apex)).is_equal_approx(max_bank, ANGLE_EPS)
		# Inside the corner arc (a berm sits on a corner, not a straight).
		var r: Vector2 = BarcelonaRxLayout.corner_arc_ranges()[corner - 1]
		assert_float(apex).is_greater(r.x)
		assert_float(apex).is_less(r.y)

func test_bank_is_never_negative_anywhere_on_the_loop() -> void:
	# Dense scan of the continuous bank query (not just the 400 sample points):
	# the sign convention must hold everywhere, not merely where an index lands.
	var max_bank := deg_to_rad(BarcelonaRxLayout.BANK_MAX_DEG)
	var s := 0.0
	while s < BarcelonaRxLayout.perimeter():
		var bank := BarcelonaRxLayout.bank_rad_at_arc(s)
		assert_float(bank).is_greater_equal(-1.0e-9)
		assert_float(bank).is_less_equal(max_bank + 1.0e-6)
		if not _in_berm(s):
			assert_float(bank).is_equal_approx(0.0, 1.0e-9)
		s += 1.0
	# Well inside each berm the bank is strictly positive (the boundary samples
	# ease to 0, which the monotone-ramp test proves separately).
	for r in BarcelonaRxLayout.BANK_REGIONS:
		var apex := BarcelonaRxLayout.corner_apex_arc(int(r["corner"]))
		assert_float(BarcelonaRxLayout.bank_rad_at_arc(apex - 10.0)).is_greater(0.0)
		assert_float(BarcelonaRxLayout.bank_rad_at_arc(apex + 10.0)).is_greater(0.0)

func test_bank_ramp_is_monotone_through_each_berm() -> void:
	for r in BarcelonaRxLayout.BANK_REGIONS:
		var apex := BarcelonaRxLayout.corner_apex_arc(int(r["corner"]))
		var half: float = r["half_arc"]
		# Sample the ramp densely and check it rises monotonically to the apex
		# then falls monotonically away from it.
		var max_bank := deg_to_rad(float(r["deg"]))
		var step := 2.0
		var prev := 0.0
		var s := apex - half
		while s <= apex + 0.001:
			var m := absf(BarcelonaRxLayout.bank_rad_at_arc(s))
			assert_float(m).is_greater_equal(prev - 1.0e-6)
			prev = m
			s += step
		assert_float(prev).is_equal_approx(max_bank, 0.02)
		var falling := prev
		s = apex
		while s <= apex + half + 0.001:
			var m := absf(BarcelonaRxLayout.bank_rad_at_arc(s))
			assert_float(m).is_less_equal(falling + 1.0e-6)
			falling = m
			s += step
		assert_float(falling).is_less_equal(0.02)
		# The ramp really spans the full berm (both ends ease to zero).
		assert_float(BarcelonaRxLayout.bank_rad_at_arc(apex - half)).is_equal_approx(0.0, 1.0e-6)
		assert_float(BarcelonaRxLayout.bank_rad_at_arc(apex + half)).is_equal_approx(0.0, 1.0e-6)

func test_every_turn_is_a_right_turn() -> void:
	var points := BarcelonaRxLayout.build_centerline()
	var sampled := _corner_sample_indices()
	assert_int(sampled.size()).is_greater(0)
	for i: int in sampled:
		var prev: Vector3 = points[(i - 1 + points.size()) % points.size()]
		var next: Vector3 = points[(i + 1) % points.size()]
		var t1 := (points[i] - prev).normalized()
		var t2 := (next - points[i]).normalized()
		# The exact sign space TrackBuilder._frame uses: cross.y < 0 is a RIGHT
		# turn and yields a POSITIVE signed angle there (outfield/left edge
		# rises, inner/right edge stays at ROAD_BASE_Y).
		assert_float(t1.cross(t2).y).is_less(0.0)
	# Of the seven right-hand corners only T2 and T6 carry a berm; the bank is
	# positive there and exactly zero elsewhere.
	for corner: int in [1, 3, 4, 5, 7]:
		var mid: Vector2 = BarcelonaRxLayout.corner_arc_ranges()[corner - 1]
		assert_float(BarcelonaRxLayout.bank_rad_at_arc((mid.x + mid.y) * 0.5)).is_equal_approx(0.0, 1.0e-9)
	for corner: int in [2, 6]:
		var mid: Vector2 = BarcelonaRxLayout.corner_arc_ranges()[corner - 1]
		assert_float(BarcelonaRxLayout.bank_rad_at_arc((mid.x + mid.y) * 0.5)).is_greater(0.0)

func test_checkpoint_indices_are_stride_spaced_and_in_travel_order() -> void:
	var indices := BarcelonaRxLayout.checkpoint_indices()
	assert_that(indices).is_equal(PackedInt32Array([0, 50, 100, 150, 200, 250, 300, 350]))
	assert_int(indices.size()).is_equal(BarcelonaRxLayout.CHECKPOINT_COUNT)
	for i in range(1, indices.size()):
		assert_int(indices[i] - indices[i - 1]).is_equal(BarcelonaRxLayout.CP_STRIDE)
		assert_int(indices[i]).is_greater(indices[i - 1])
	# The start/finish line is the LAST checkpoint (the LapCounter contract).
	assert_int(BarcelonaRxLayout.START_LINE_INDEX).is_equal(indices.size() - 1)
	assert_int(indices[BarcelonaRxLayout.START_LINE_INDEX]).is_equal(350)

func test_start_line_arc_is_on_a_straight_past_the_grid() -> void:
	var line := BarcelonaRxLayout.start_line_arc()
	assert_float(line).is_equal_approx(991.375, 0.01)
	assert_float(line).is_less(BarcelonaRxLayout.perimeter())
	assert_float(line).is_equal_approx(BarcelonaRxLayout.arc_of_index(350), POSITION_EPS)
	# Flat and jump-free there, so the S/F paint/gantry sit on a level surface.
	assert_float(BarcelonaRxLayout.bank_rad_at_arc(line)).is_equal_approx(0.0, 1.0e-9)
	assert_float(BarcelonaRxLayout.jump_lift(line)).is_equal_approx(0.0, 1.0e-9)
	assert_float(BarcelonaRxLayout.point_at_arc(line).y).is_equal_approx(
		BarcelonaRxLayout.ROAD_BASE_Y, POSITION_EPS)
	# The grid (arc 0) is likewise flat and jump-free.
	assert_float(BarcelonaRxLayout.bank_rad_at_arc(0.0)).is_equal_approx(0.0, 1.0e-9)
	assert_float(BarcelonaRxLayout.jump_lift(0.0)).is_equal_approx(0.0, 1.0e-9)

func test_corner_names_and_arc_ranges() -> void:
	var names := BarcelonaRxLayout.corner_names()
	assert_int(names.size()).is_equal(7)
	for i in names.size():
		assert_that(names[i]).is_equal("T%d" % (i + 1))

	var ranges := BarcelonaRxLayout.corner_arc_ranges()
	assert_int(ranges.size()).is_equal(7)
	if ranges.size() != 7:
		return
	# Every range is non-empty, ordered and non-overlapping (none wrap the grid).
	for i in ranges.size():
		var span: Vector2 = ranges[i]
		assert_float(span.x).is_less(span.y)
		assert_float(span.x).is_greater_equal(0.0)
		assert_float(span.y).is_less_equal(BarcelonaRxLayout.perimeter())
		if i > 0:
			assert_float(span.x).is_greater_equal(ranges[i - 1].y)
	# Every corner midpoint is banked inside a corner only where a berm exists;
	# the corner arcs themselves all carry the loop's curvature.
	for i in ranges.size():
		var span: Vector2 = ranges[i]
		var mid := (span.x + span.y) * 0.5
		assert_float(span.y - span.x).is_greater(20.0)

	# T1 is the tightest corner (V0) and the barrier set is T1/T2/T6.
	assert_float(ranges[0].y - ranges[0].x).is_less(ranges[5].y - ranges[5].x)

func test_barrier_arc_ranges_cover_the_barrier_corners() -> void:
	var all := BarcelonaRxLayout.corner_arc_ranges()
	var barriers := BarcelonaRxLayout.barrier_arc_ranges()
	assert_int(barriers.size()).is_equal(BarcelonaRxLayout.BARRIER_CORNERS.size())
	for i in barriers.size():
		var corner: int = BarcelonaRxLayout.BARRIER_CORNERS[i]
		assert_that(barriers[i]).is_equal(all[corner - 1])
	assert_float(BarcelonaRxLayout.barrier_arc_length()).is_greater(150.0)
	assert_float(BarcelonaRxLayout.barrier_arc_length()).is_less(180.0)

func test_jumps_crest_zero_outside_and_slope_bound() -> void:
	var ranges := BarcelonaRxLayout.jump_arc_ranges()
	assert_int(ranges.size()).is_equal(2)
	assert_that(ranges[0]).is_equal(Vector2(12.0, 40.0))
	assert_that(ranges[1]).is_equal(Vector2(108.0, 130.0))

	# Crest heights (region midpoints): table-top 1.0, single crest 0.8.
	assert_float(BarcelonaRxLayout.jump_lift(26.0)).is_equal_approx(1.0, 0.05)
	assert_float(BarcelonaRxLayout.jump_lift(119.0)).is_equal_approx(0.8, 0.05)
	# The table is flat across its middle.
	assert_float(BarcelonaRxLayout.jump_lift(24.0)).is_equal_approx(1.0, 0.05)
	assert_float(BarcelonaRxLayout.jump_lift(28.0)).is_equal_approx(1.0, 0.05)

	# Zero lift outside both arcs, including the line and grid.
	for arc: float in [0.0, 5.0, 45.0, 100.0, 135.0, 500.0, 991.375]:
		assert_float(BarcelonaRxLayout.jump_lift(arc)).is_equal_approx(0.0, 1.0e-9)
	# Both jumps sit on flat ground (no berm under them).
	for r: Vector2 in ranges:
		assert_float(BarcelonaRxLayout.bank_rad_at_arc(r.x)).is_equal_approx(0.0, 1.0e-9)
		assert_float(BarcelonaRxLayout.bank_rad_at_arc(r.y)).is_equal_approx(0.0, 1.0e-9)

	# Ramp slope <= tan(20 deg) everywhere (fine scan), and the chain's own
	# adjacent-point step stays under a documented 0.60 m continuity bound.
	var slope_limit := tan(deg_to_rad(20.0))
	var s := 0.0
	var step := 0.25
	var max_slope := 0.0
	while s < BarcelonaRxLayout.perimeter() - step:
		var d := absf(BarcelonaRxLayout.jump_lift(s + step) - BarcelonaRxLayout.jump_lift(s))
		max_slope = maxf(max_slope, d / step)
		s += step
	assert_float(max_slope).is_less_equal(slope_limit)

	var points := BarcelonaRxLayout.build_centerline()
	var max_step := 0.0
	for i in points.size():
		var a := BarcelonaRxLayout.arc_of_index(i)
		var b := BarcelonaRxLayout.arc_of_index((i + 1) % points.size())
		max_step = maxf(max_step, absf(BarcelonaRxLayout.jump_lift(b) - BarcelonaRxLayout.jump_lift(a)))
	assert_float(max_step).is_less_equal(0.60)

func test_builders_are_deterministic() -> void:
	var first_points := BarcelonaRxLayout.build_centerline()
	var second_points := BarcelonaRxLayout.build_centerline()
	assert_int(first_points.size()).is_equal(second_points.size())
	if first_points.size() != second_points.size():
		return
	for i in first_points.size():
		assert_that(first_points[i]).is_equal(second_points[i])

	var first_bank := BarcelonaRxLayout.build_bank_profile()
	var second_bank := BarcelonaRxLayout.build_bank_profile()
	assert_int(first_bank.size()).is_equal(second_bank.size())
	if first_bank.size() != second_bank.size():
		return
	for i in first_bank.size():
		assert_float(first_bank[i]).is_equal(second_bank[i])

func test_point_at_arc_wraps_the_closed_loop() -> void:
	var perimeter := BarcelonaRxLayout.perimeter()
	assert_that(BarcelonaRxLayout.point_at_arc(0.0)).is_equal_approx(
		BarcelonaRxLayout.point_at_arc(perimeter), Vector3(POSITION_EPS, POSITION_EPS, POSITION_EPS))
	assert_that(BarcelonaRxLayout.point_at_arc(perimeter + 5.0)).is_equal_approx(
		BarcelonaRxLayout.point_at_arc(5.0), Vector3(POSITION_EPS, POSITION_EPS, POSITION_EPS))
	assert_that(BarcelonaRxLayout.point_at_arc(-5.0)).is_equal_approx(
		BarcelonaRxLayout.point_at_arc(perimeter - 5.0), Vector3(POSITION_EPS, POSITION_EPS, POSITION_EPS))
	# point_at_arc agrees with the sampled chain wherever an index lands.
	var points := BarcelonaRxLayout.build_centerline()
	for i in points.size():
		assert_that(BarcelonaRxLayout.point_at_arc(BarcelonaRxLayout.arc_of_index(i))).is_equal_approx(
			points[i], Vector3(POSITION_EPS, POSITION_EPS, POSITION_EPS))

func test_frame_at_arc_matches_the_centerline_and_the_bank() -> void:
	var samples: Array[float] = [
		0.0,
		90.0,
		BarcelonaRxLayout.start_line_arc(),
		BarcelonaRxLayout.corner_apex_arc(1),
		BarcelonaRxLayout.corner_apex_arc(2),
		BarcelonaRxLayout.corner_apex_arc(6),
		500.0,
	]
	for s: float in samples:
		var frame := BarcelonaRxLayout.frame_at_arc(s)
		var center: Vector3 = frame["center"]
		var forward: Vector3 = frame["forward"]
		var cross: Vector3 = frame["cross"]
		var bank := float(frame["bank"])
		assert_that(center).is_equal_approx(
			BarcelonaRxLayout.point_at_arc(s), Vector3(POSITION_EPS, POSITION_EPS, POSITION_EPS))
		assert_float(forward.length()).is_equal_approx(1.0, POSITION_EPS)
		assert_float(cross.length()).is_equal_approx(1.0, POSITION_EPS)
		# TrackBuilder._frame's convention: cross = right*cos(a) - UP*sin(a).
		assert_float(cross.y).is_equal_approx(-sin(bank), POSITION_EPS)
		assert_float(bank).is_equal_approx(BarcelonaRxLayout.bank_rad_at_arc(s), ANGLE_EPS)
	# A right-hand berm raises the outfield (left/cross-negative) edge: at a
	# bermed apex the inner/right side is the LOW one.
	var apex_frame := BarcelonaRxLayout.frame_at_arc(BarcelonaRxLayout.corner_apex_arc(2))
	var apex_cross: Vector3 = apex_frame["cross"]
	assert_float(apex_cross.y).is_less(0.0)

# --- mixed surface (DIRT_SECTIONS) --------------------------------------------

## The loose share matches the real venue (~60 % asphalt / ~40 % loose), every
## section lies inside the loop, sections do not overlap, and the landmarks sit
## where the layout says: grid, S/F line, table-top jump and T1 on asphalt; the
## single-crest jump, the T2 berm, T3 and T4 on the dirt; T5-T7 on asphalt.
func test_dirt_sections_share_and_landmarks() -> void:
	var total := BarcelonaRxLayout.dirt_arc_length()
	assert_float(total / BarcelonaRxLayout.TARGET_PERIMETER).is_between(0.38, 0.42)
	var prev_end := -1.0
	for r in BarcelonaRxLayout.DIRT_SECTIONS:
		assert_float(r.x).is_greater_equal(0.0)
		assert_float(r.y).is_less_equal(BarcelonaRxLayout.TARGET_PERIMETER)
		assert_float(r.y).is_greater(r.x)
		assert_float(r.x).is_greater(prev_end)
		prev_end = r.y
	assert_bool(BarcelonaRxLayout.is_loose_at_arc(0.0)).is_false()
	assert_bool(BarcelonaRxLayout.is_loose_at_arc(BarcelonaRxLayout.start_line_arc())).is_false()
	var jumps := BarcelonaRxLayout.jump_arc_ranges()
	assert_bool(BarcelonaRxLayout.is_loose_at_arc((jumps[0].x + jumps[0].y) * 0.5)).is_false()
	assert_bool(BarcelonaRxLayout.is_loose_at_arc((jumps[1].x + jumps[1].y) * 0.5)).is_true()
	var expected_loose: Array[bool] = [false, true, true, true, false, false, false]
	for c in 7:
		assert_bool(BarcelonaRxLayout.is_loose_at_arc(BarcelonaRxLayout.corner_apex_arc(c + 1))) \
			.override_failure_message("T%d surface" % (c + 1)).is_equal(expected_loose[c])
	# The loose section starts at the T1 exit and ends at the T4 exit.
	var corners := BarcelonaRxLayout.corner_arc_ranges()
	assert_float(BarcelonaRxLayout.DIRT_SECTIONS[0].x).is_equal_approx(corners[0].y, 1.0)
	assert_float(BarcelonaRxLayout.DIRT_SECTIONS[0].y).is_equal_approx(corners[3].y, 3.0)
	# Wrapping: arc and arc + perimeter agree.
	assert_bool(BarcelonaRxLayout.is_loose_at_arc(150.0 + BarcelonaRxLayout.TARGET_PERIMETER)).is_true()
	assert_str(BarcelonaRxLayout.surface_key_at_arc(150.0)).is_equal(SurfaceRegistry.GRAVEL)
	assert_str(BarcelonaRxLayout.surface_key_at_arc(800.0)).is_equal(SurfaceRegistry.ASPHALT)

## The per-point profile (RoadDef.point_surfaces) is one entry per centerline
## point, equals the chainage table at every segment midpoint, has exactly two
## surface changes round the loop, and is deterministic.
func test_surface_profile_matches_the_table_and_is_deterministic() -> void:
	var profile := BarcelonaRxLayout.build_surface_profile()
	assert_int(profile.size()).is_equal(BarcelonaRxLayout.TOTAL_POINTS)
	var changes := 0
	var loose := 0
	for i in profile.size():
		var mid := (float(i) + 0.5) * BarcelonaRxLayout.spacing()
		assert_int(int(profile[i])).is_equal(BarcelonaRxLayout.surface_at_arc(mid))
		if profile[i] != profile[(i + 1) % profile.size()]:
			changes += 1
		if int(profile[i]) == RoadDef.Surface.GRAVEL:
			loose += 1
	assert_int(changes).is_equal(2 * BarcelonaRxLayout.DIRT_SECTIONS.size())
	assert_float(float(loose) * BarcelonaRxLayout.spacing()).is_equal_approx(
		BarcelonaRxLayout.dirt_arc_length(), BarcelonaRxLayout.spacing())
	assert_that(BarcelonaRxLayout.build_surface_profile()).is_equal(profile)
