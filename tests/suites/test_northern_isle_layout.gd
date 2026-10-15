# tests/suites/test_northern_isle_layout.gd
extends GdUnitTestSuite

## P0 gate for Northern Isle Speedway geometry
## (scripts/track/northern_isle_layout.gd — see docs/plans/track_northern_isle_speedway.md P0).
##
## The layout is the single source of truth every later phase reads: the road
## mesh and its trimesh collision (P1/P2), the bank-aware terrain bake (P3) and
## the dressing placement (P4) all derive from these two builders. So this is a
## PURE-MATH suite — no scene, no engine state, no wall clock — and every
## assertion is about a documented constant or invariant from the plan's
## section 2 table.
##
## What is pinned here:
##   * perimeter ~900 m and the derived span table (2L + 2*pi*R == PERIMETER);
##   * a 304-point, closed, uniform-arc-length chain whose every LEFT (infield)
##     edge rides at exactly ROAD_BASE_Y — the invariant that keeps the road in
##     contact with the flat infield and grounds the banked cross-section;
##   * the signed bank profile: 0.0 on every straight, -18 deg at both turn
##     apexes, sine-eased AND monotone through each 40 m transition, never
##     positive (left turns only);
##   * direction is CCW/left in the exact sign space TrackBuilder._frame uses
##     (cross(t1, t2).y > 0 -> negative signed bank angle);
##   * the checkpoint / lap-line contract (8 stride-38 checkpoints, the line on
##     the front straight ~18 m past the T4 exit) and the 4 ordered corners;
##   * determinism of both builders;
##   * the road frame (center / forward / cross) the mesh and dressing consume.

const POSITION_EPS := 0.001
const ANGLE_EPS := 0.0001

## True when `arc` is on a straight (or exactly on a straight/turn boundary,
## where the bank is analytically 0.0). Mirrors the documented span table,
## which test_perimeter_and_span_constants pins independently.
func _is_straight_arc(arc: float) -> bool:
	if arc <= NorthernIsleLayout.SPAN_A_END:
		return true
	if arc >= NorthernIsleLayout.SPAN_B_END and arc <= NorthernIsleLayout.SPAN_C_END:
		return true
	return arc >= NorthernIsleLayout.SPAN_D_END

## Indices strictly INSIDE a turn and clear of both tangent points (10 m of
## margin), so the discrete cross-product direction test is unambiguous.
func _turn_sample_indices() -> Array[int]:
	var out: Array[int] = []
	var margin := 10.0
	for i in NorthernIsleLayout.TOTAL_POINTS:
		var arc := NorthernIsleLayout.arc_of_index(i)
		var in_turn_a := arc >= NorthernIsleLayout.SPAN_A_END + margin and arc <= NorthernIsleLayout.SPAN_B_END - margin
		var in_turn_b := arc >= NorthernIsleLayout.SPAN_C_END + margin and arc <= NorthernIsleLayout.SPAN_D_END - margin
		if in_turn_a or in_turn_b:
			out.append(i)
	return out

func test_perimeter_and_span_constants() -> void:
	# --- the plan's section 2 number table, verbatim -----------------------
	assert_float(NorthernIsleLayout.TURN_RADIUS).is_equal_approx(60.0, 0.0001)
	assert_float(NorthernIsleLayout.STRAIGHT_LENGTH).is_equal_approx(261.5, 0.0001)
	assert_float(NorthernIsleLayout.WIDTH).is_equal_approx(16.0, 0.0001)
	assert_float(NorthernIsleLayout.BANK_MAX_DEG).is_equal_approx(18.0, 0.0001)
	assert_float(NorthernIsleLayout.TRANSITION_ARC).is_equal_approx(40.0, 0.0001)
	assert_float(NorthernIsleLayout.ROAD_BASE_Y).is_equal_approx(0.15, 0.0001)
	assert_float(NorthernIsleLayout.PLAIN_Y).is_equal_approx(-0.25, 0.0001)
	assert_float(NorthernIsleLayout.SHOULDER_RUN).is_equal_approx(6.0, 0.0001)
	assert_float(NorthernIsleLayout.EMBANK_RUN).is_equal_approx(22.0, 0.0001)
	assert_int(NorthernIsleLayout.TOTAL_POINTS).is_equal(304)
	assert_int(NorthernIsleLayout.CHECKPOINT_COUNT).is_equal(8)
	assert_int(NorthernIsleLayout.CP_STRIDE).is_equal(38)
	assert_int(NorthernIsleLayout.START_LINE_INDEX).is_equal(7)

	# --- perimeter: 2 straights + 2 x 180 deg turns -----------------------
	var perimeter := NorthernIsleLayout.perimeter()
	assert_float(perimeter).is_greater_equal(895.0)
	assert_float(perimeter).is_less_equal(905.0)
	assert_float(perimeter).is_equal_approx(899.99, 0.01)
	assert_float(NorthernIsleLayout.PERIMETER).is_equal_approx(
		2.0 * NorthernIsleLayout.STRAIGHT_LENGTH + TAU * NorthernIsleLayout.TURN_RADIUS, ANGLE_EPS)

	# --- the derived span table -------------------------------------------
	assert_float(NorthernIsleLayout.HALF_STRAIGHT).is_equal_approx(
		NorthernIsleLayout.STRAIGHT_LENGTH * 0.5, ANGLE_EPS)
	assert_float(NorthernIsleLayout.HALF_TURN_ARC).is_equal_approx(
		PI * NorthernIsleLayout.TURN_RADIUS, ANGLE_EPS)
	assert_float(NorthernIsleLayout.SPAN_A_END).is_equal_approx(NorthernIsleLayout.HALF_STRAIGHT, ANGLE_EPS)
	assert_float(NorthernIsleLayout.SPAN_B_END).is_equal_approx(
		NorthernIsleLayout.SPAN_A_END + NorthernIsleLayout.HALF_TURN_ARC, ANGLE_EPS)
	assert_float(NorthernIsleLayout.SPAN_C_END).is_equal_approx(
		NorthernIsleLayout.SPAN_B_END + NorthernIsleLayout.STRAIGHT_LENGTH, ANGLE_EPS)
	assert_float(NorthernIsleLayout.SPAN_D_END).is_equal_approx(
		NorthernIsleLayout.SPAN_C_END + NorthernIsleLayout.HALF_TURN_ARC, ANGLE_EPS)
	# The header comment's documented span boundaries (used by later phases).
	assert_float(NorthernIsleLayout.SPAN_A_END).is_equal_approx(130.75, 0.001)
	assert_float(NorthernIsleLayout.SPAN_B_END).is_equal_approx(319.25, 0.01)
	assert_float(NorthernIsleLayout.SPAN_C_END).is_equal_approx(580.75, 0.01)
	assert_float(NorthernIsleLayout.SPAN_D_END).is_equal_approx(769.24, 0.01)

	# --- the five span boundaries (plus 0 and PERIMETER) are monotone ------
	var boundaries: Array[float] = [
		0.0,
		NorthernIsleLayout.SPAN_A_END,
		NorthernIsleLayout.SPAN_B_END,
		NorthernIsleLayout.SPAN_C_END,
		NorthernIsleLayout.SPAN_D_END,
		perimeter,
	]
	for i in range(1, boundaries.size()):
		assert_float(boundaries[i]).is_greater(boundaries[i - 1])

	# --- uniform arc-length spacing ---------------------------------------
	assert_float(NorthernIsleLayout.spacing()).is_equal_approx(perimeter / 304.0, ANGLE_EPS)
	assert_float(NorthernIsleLayout.spacing()).is_equal_approx(2.9605, 0.001)
	assert_float(NorthernIsleLayout.arc_of_index(0)).is_equal_approx(0.0, ANGLE_EPS)
	assert_float(NorthernIsleLayout.arc_of_index(303)).is_equal_approx(
		303.0 * NorthernIsleLayout.spacing(), ANGLE_EPS)

func test_centerline_is_closed_uniform_and_anchored_on_the_grid() -> void:
	var points := NorthernIsleLayout.build_centerline()
	assert_int(points.size()).is_equal(NorthernIsleLayout.TOTAL_POINTS)
	if points.size() != NorthernIsleLayout.TOTAL_POINTS:
		return

	# The grid sits mid front straight at the documented anchor.
	assert_that(points[0]).is_equal_approx(Vector3(0.0, 0.15, 60.0), Vector3(0.01, 0.01, 0.01))
	assert_float(points[0].y).is_equal_approx(NorthernIsleLayout.ROAD_BASE_Y, ANGLE_EPS)

	# The chain closes: the wrap segment (last -> first) is one spacing long.
	assert_float(points[0].distance_to(points[points.size() - 1])).is_equal_approx(
		NorthernIsleLayout.spacing(), POSITION_EPS)

	# Uniform arc-length spacing, INCLUDING the closing segment: the worst
	# segment is the arc chord (2R*sin(ds/2R)) vs the straight chord (ds), a
	# ~0.005 % difference, far inside the 2 % band the plan asks for.
	var min_length := INF
	var max_length := 0.0
	for i in points.size():
		var next: Vector3 = points[(i + 1) % points.size()]
		var length := points[i].distance_to(next)
		min_length = minf(min_length, length)
		max_length = maxf(max_length, length)
	assert_float(max_length / min_length).is_less_equal(1.02)
	assert_float(min_length).is_greater(2.95)
	assert_float(max_length).is_less(2.98)

	# Footprint: a 380.75 x 120 m stadium oval (turn apexes at +-190.75, straights at +-60).
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p: Vector3 in points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	assert_float(max_x).is_equal_approx(190.75, 0.05)
	assert_float(min_x).is_equal_approx(-190.75, 0.05)
	assert_float(max_z).is_equal_approx(60.0, POSITION_EPS)
	assert_float(min_z).is_equal_approx(-60.0, POSITION_EPS)
	assert_float(max_x - min_x).is_equal_approx(
		2.0 * (NorthernIsleLayout.HALF_STRAIGHT + NorthernIsleLayout.TURN_RADIUS), 0.1)

func test_every_left_edge_rides_at_road_base_y() -> void:
	# THE load-bearing invariant (plan section 6 risk 2): the centerline lift is
	# derived from the SAME bank array the mesh consumes, so the left/infield
	# edge lands exactly on ROAD_BASE_Y and the infield stays flush with the
	# ground. Hand-editing either side alone breaks road/ground contact.
	var points := NorthernIsleLayout.build_centerline()
	var half_width := NorthernIsleLayout.WIDTH * 0.5
	var banked_points := 0
	for i in points.size():
		var arc := NorthernIsleLayout.arc_of_index(i)
		var bank := NorthernIsleLayout.bank_rad_at_arc(arc)
		var edge_lift := half_width * absf(sin(bank))
		assert_float(points[i].y - edge_lift).is_equal_approx(NorthernIsleLayout.ROAD_BASE_Y, POSITION_EPS)
		if not is_zero_approx(bank):
			banked_points += 1
	# The invariant is only meaningful where the road is actually banked.
	assert_int(banked_points).is_greater(0)
	assert_int(banked_points).is_less(points.size())

	# Apex lift is WIDTH * |sin(18 deg)| ~= 4.94 m on the outfield edge, so the
	# centerline sits ~2.47 m above the base at the apex.
	var max_bank := -deg_to_rad(NorthernIsleLayout.BANK_MAX_DEG)
	var apex_center_y := NorthernIsleLayout.ROAD_BASE_Y + (NorthernIsleLayout.WIDTH * 0.5) * absf(sin(max_bank))
	assert_float(NorthernIsleLayout.WIDTH * absf(sin(max_bank))).is_equal_approx(4.94, 0.05)
	assert_float(apex_center_y).is_equal_approx(2.622, 0.01)

func test_bank_profile_is_flat_on_straights_and_18_deg_at_the_apexes() -> void:
	var profile := NorthernIsleLayout.build_bank_profile()
	assert_int(profile.size()).is_equal(NorthernIsleLayout.TOTAL_POINTS)
	var max_bank := -deg_to_rad(NorthernIsleLayout.BANK_MAX_DEG)
	for i in profile.size():
		var arc := NorthernIsleLayout.arc_of_index(i)
		# The profile array and the public arc query are the same function.
		assert_float(profile[i]).is_equal_approx(NorthernIsleLayout.bank_rad_at_arc(arc), ANGLE_EPS)
		# Left turns only: the signed bank is never positive.
		assert_float(profile[i]).is_less_equal(1.0e-9)
		if _is_straight_arc(arc):
			assert_float(profile[i]).is_equal_approx(0.0, 1.0e-9)
		else:
			assert_float(profile[i]).is_less(0.0)

	# Both 180 deg turn midpoints are exactly the max bank: -18 deg.
	var apex_a := NorthernIsleLayout.SPAN_A_END + NorthernIsleLayout.HALF_TURN_ARC * 0.5
	var apex_b := NorthernIsleLayout.SPAN_C_END + NorthernIsleLayout.HALF_TURN_ARC * 0.5
	assert_float(NorthernIsleLayout.bank_rad_at_arc(apex_a)).is_equal_approx(max_bank, ANGLE_EPS)
	assert_float(NorthernIsleLayout.bank_rad_at_arc(apex_b)).is_equal_approx(max_bank, ANGLE_EPS)
	assert_float(NorthernIsleLayout.bank_rad_at_arc(apex_a)).is_equal_approx(-0.31416, 0.005)
	assert_float(NorthernIsleLayout.bank_rad_at_arc(apex_b)).is_equal_approx(-0.31416, 0.005)

	# The apexes land exactly on checkpoint 2 and checkpoint 6, and the profile
	# carries the exact max there (float32 storage included).
	var indices := NorthernIsleLayout.checkpoint_indices()
	assert_float(NorthernIsleLayout.arc_of_index(indices[2])).is_equal_approx(apex_a, POSITION_EPS)
	assert_float(NorthernIsleLayout.arc_of_index(indices[6])).is_equal_approx(apex_b, POSITION_EPS)
	assert_float(profile[indices[2]]).is_equal_approx(max_bank, ANGLE_EPS)
	assert_float(profile[indices[6]]).is_equal_approx(max_bank, ANGLE_EPS)
	var points := NorthernIsleLayout.build_centerline()
	assert_float(points[indices[2]].y).is_equal_approx(
		NorthernIsleLayout.ROAD_BASE_Y + (NorthernIsleLayout.WIDTH * 0.5) * absf(sin(max_bank)), POSITION_EPS)
	assert_float(points[indices[6]].y).is_equal_approx(points[indices[2]].y, POSITION_EPS)

func test_bank_is_never_positive_anywhere_on_the_loop() -> void:
	# Dense scan of the continuous bank query (not just the 304 sample points):
	# the sign convention must hold everywhere, not merely where an index lands.
	var max_bank := -deg_to_rad(NorthernIsleLayout.BANK_MAX_DEG)
	var s := 0.0
	while s < NorthernIsleLayout.perimeter():
		var bank := NorthernIsleLayout.bank_rad_at_arc(s)
		assert_float(bank).is_less_equal(1.0e-9)
		assert_float(bank).is_greater_equal(max_bank - 1.0e-6)
		if _is_straight_arc(s):
			assert_float(bank).is_equal_approx(0.0, 1.0e-9)
		else:
			assert_float(bank).is_less(0.0)
		s += 1.0

func test_bank_ramp_is_monotone_through_each_transition() -> void:
	# Each 180 deg turn eases 0 -> 18 deg over TRANSITION_ARC at its entry and
	# 18 -> 0 over TRANSITION_ARC at its exit (sine smoothstep), and holds a
	# constant plateau between them.
	_assert_ramp_monotone(NorthernIsleLayout.SPAN_A_END, NorthernIsleLayout.SPAN_B_END)
	_assert_ramp_monotone(NorthernIsleLayout.SPAN_C_END, NorthernIsleLayout.SPAN_D_END)

func _assert_ramp_monotone(turn_start: float, turn_end: float) -> void:
	var profile := NorthernIsleLayout.build_bank_profile()
	var max_bank := absf(-deg_to_rad(NorthernIsleLayout.BANK_MAX_DEG))
	var entry: Array[float] = []
	var plateau: Array[float] = []
	var exit_ramp: Array[float] = []
	for i in profile.size():
		var arc := NorthernIsleLayout.arc_of_index(i)
		if arc < turn_start or arc > turn_end:
			continue
		var magnitude := absf(profile[i])
		if arc <= turn_start + NorthernIsleLayout.TRANSITION_ARC:
			entry.append(magnitude)
		elif arc >= turn_end - NorthernIsleLayout.TRANSITION_ARC:
			exit_ramp.append(magnitude)
		else:
			plateau.append(magnitude)
	# 40 m of ramp at ~2.96 m spacing is 13-14 samples; a sparse window would
	# make the monotonicity claim vacuous.
	assert_int(entry.size()).is_greater(5)
	assert_int(exit_ramp.size()).is_greater(5)
	assert_int(plateau.size()).is_greater(5)
	for i in range(1, entry.size()):
		assert_float(entry[i]).is_greater_equal(entry[i - 1])
	for i in range(1, exit_ramp.size()):
		assert_float(exit_ramp[i]).is_less_equal(exit_ramp[i - 1])
	for magnitude: float in plateau:
		assert_float(magnitude).is_equal_approx(max_bank, ANGLE_EPS)
	# The ramps really reach the plateau (not merely a shallow slope).
	assert_float(entry[entry.size() - 1]).is_greater(max_bank * 0.9)
	assert_float(exit_ramp[0]).is_greater(max_bank * 0.9)

func test_every_turn_is_a_left_turn() -> void:
	var points := NorthernIsleLayout.build_centerline()
	var sampled := _turn_sample_indices()
	assert_int(sampled.size()).is_greater(0)
	for i: int in sampled:
		var prev: Vector3 = points[(i - 1 + points.size()) % points.size()]
		var next: Vector3 = points[(i + 1) % points.size()]
		var t1 := (points[i] - prev).normalized()
		var t2 := (next - points[i]).normalized()
		# The exact sign space TrackBuilder._frame uses: curvature =
		# -t1.cross(t2).y, so a positive cross.y is a LEFT turn and yields a
		# NEGATIVE signed angle there (infield/left edge drops, outfield rises).
		assert_float(t1.cross(t2).y).is_greater(0.0)
		# ... which is what the layout's own bank stores.
		assert_float(NorthernIsleLayout.bank_rad_at_arc(NorthernIsleLayout.arc_of_index(i))).is_less(0.0)

func test_checkpoint_indices_are_stride_spaced_and_in_travel_order() -> void:
	var indices := NorthernIsleLayout.checkpoint_indices()
	assert_that(indices).is_equal(PackedInt32Array([0, 38, 76, 114, 152, 190, 228, 266]))
	assert_int(indices.size()).is_equal(NorthernIsleLayout.CHECKPOINT_COUNT)
	# 8 * 38 == 304, so every checkpoint lands exactly on a point.
	assert_int(NorthernIsleLayout.CHECKPOINT_COUNT * NorthernIsleLayout.CP_STRIDE).is_equal(
		NorthernIsleLayout.TOTAL_POINTS)
	for i in range(1, indices.size()):
		assert_int(indices[i] - indices[i - 1]).is_equal(NorthernIsleLayout.CP_STRIDE)
		assert_int(indices[i]).is_greater(indices[i - 1])
	# The start/finish line is the LAST checkpoint (the LapCounter contract).
	assert_int(NorthernIsleLayout.START_LINE_INDEX).is_equal(indices.size() - 1)
	assert_int(indices[NorthernIsleLayout.START_LINE_INDEX]).is_equal(266)

func test_start_line_arc_is_on_the_front_straight_past_t4() -> void:
	var line := NorthernIsleLayout.start_line_arc()
	assert_float(line).is_equal_approx(787.5, 0.5)
	# Span E (front straight, after the T4 exit) holds the line.
	assert_float(line).is_greater_equal(NorthernIsleLayout.SPAN_D_END)
	assert_float(line).is_less(NorthernIsleLayout.PERIMETER)
	assert_float(line).is_equal_approx(NorthernIsleLayout.arc_of_index(266), POSITION_EPS)
	# ~18 m after the T4 tangent point (the plan's "15-25 m past" band).
	assert_float(line - NorthernIsleLayout.SPAN_D_END).is_greater_equal(15.0)
	assert_float(line - NorthernIsleLayout.SPAN_D_END).is_less_equal(25.0)
	assert_float(line - NorthernIsleLayout.SPAN_D_END).is_equal_approx(18.25, 0.05)
	# On the front straight: mid straight in Z, well inside the straights' X span.
	var point := NorthernIsleLayout.point_at_arc(line)
	assert_float(point.z).is_equal_approx(60.0, POSITION_EPS)
	assert_float(absf(point.x)).is_less(130.75)
	assert_float(point.y).is_equal_approx(NorthernIsleLayout.ROAD_BASE_Y, POSITION_EPS)
	# Flat there (theta = 0), so the S/F paint/gantry sit on a level surface.
	assert_float(NorthernIsleLayout.bank_rad_at_arc(line)).is_equal_approx(0.0, 1.0e-9)
	var frame := NorthernIsleLayout.frame_at_arc(line)
	var forward: Vector3 = frame["forward"]
	assert_that(forward).is_equal_approx(Vector3(1.0, 0.0, 0.0), Vector3(POSITION_EPS, POSITION_EPS, POSITION_EPS))

func test_corner_names_and_arc_ranges() -> void:
	var names := NorthernIsleLayout.corner_names()
	assert_int(names.size()).is_equal(4)
	assert_that(names[0]).is_equal("T1")
	assert_that(names[1]).is_equal("T2")
	assert_that(names[2]).is_equal("T3")
	assert_that(names[3]).is_equal("T4")

	var ranges := NorthernIsleLayout.corner_arc_ranges()
	assert_int(ranges.size()).is_equal(4)
	if ranges.size() != 4:
		return
	# Every range is non-empty and the four are ordered / non-overlapping (the
	# back straight separates T2's end from T3's start).
	for i in ranges.size():
		var span: Vector2 = ranges[i]
		assert_float(span.x).is_less(span.y)
		if i > 0:
			assert_float(span.x).is_greater_equal(ranges[i - 1].y)
	assert_float(ranges[1].y).is_less(ranges[2].x)
	# T1/T2 tile turn A contiguously, T3/T4 tile turn B contiguously.
	assert_float(ranges[0].x).is_equal_approx(NorthernIsleLayout.SPAN_A_END, ANGLE_EPS)
	assert_float(ranges[1].x).is_equal_approx(ranges[0].y, ANGLE_EPS)
	assert_float(ranges[1].y).is_equal_approx(NorthernIsleLayout.SPAN_B_END, ANGLE_EPS)
	assert_float(ranges[2].x).is_equal_approx(NorthernIsleLayout.SPAN_C_END, ANGLE_EPS)
	assert_float(ranges[3].x).is_equal_approx(ranges[2].y, ANGLE_EPS)
	assert_float(ranges[3].y).is_equal_approx(NorthernIsleLayout.SPAN_D_END, ANGLE_EPS)
	# Every corner midpoint is inside a banked turn.
	for span: Vector2 in ranges:
		var mid := (span.x + span.y) * 0.5
		assert_float(NorthernIsleLayout.bank_rad_at_arc(mid)).is_less(0.0)
		assert_bool(_is_straight_arc(mid)).is_false()

func test_builders_are_deterministic() -> void:
	var first_points := NorthernIsleLayout.build_centerline()
	var second_points := NorthernIsleLayout.build_centerline()
	assert_int(first_points.size()).is_equal(second_points.size())
	if first_points.size() != second_points.size():
		return
	for i in first_points.size():
		assert_that(first_points[i]).is_equal(second_points[i])

	var first_bank := NorthernIsleLayout.build_bank_profile()
	var second_bank := NorthernIsleLayout.build_bank_profile()
	assert_int(first_bank.size()).is_equal(second_bank.size())
	if first_bank.size() != second_bank.size():
		return
	for i in first_bank.size():
		assert_float(first_bank[i]).is_equal(second_bank[i])

func test_point_at_arc_wraps_the_closed_loop() -> void:
	var perimeter := NorthernIsleLayout.perimeter()
	assert_that(NorthernIsleLayout.point_at_arc(0.0)).is_equal_approx(
		NorthernIsleLayout.point_at_arc(perimeter), Vector3(POSITION_EPS, POSITION_EPS, POSITION_EPS))
	assert_that(NorthernIsleLayout.point_at_arc(perimeter + 5.0)).is_equal_approx(
		NorthernIsleLayout.point_at_arc(5.0), Vector3(POSITION_EPS, POSITION_EPS, POSITION_EPS))
	assert_that(NorthernIsleLayout.point_at_arc(-5.0)).is_equal_approx(
		NorthernIsleLayout.point_at_arc(perimeter - 5.0), Vector3(POSITION_EPS, POSITION_EPS, POSITION_EPS))
	# point_at_arc agrees with the sampled chain wherever an index lands.
	var points := NorthernIsleLayout.build_centerline()
	assert_that(NorthernIsleLayout.point_at_arc(NorthernIsleLayout.arc_of_index(303))).is_equal_approx(
		points[303], Vector3(POSITION_EPS, POSITION_EPS, POSITION_EPS))
	# The point behind the grid is one spacing back on the front straight.
	assert_float(points[303].x).is_equal_approx(-2.9605, 0.001)
	assert_float(points[303].z).is_equal_approx(60.0, POSITION_EPS)

func test_frame_at_arc_matches_the_centerline_and_the_bank() -> void:
	var samples: Array[float] = [
		0.0,
		60.0,
		NorthernIsleLayout.SPAN_A_END - 0.5,
		NorthernIsleLayout.SPAN_A_END + 30.0,
		NorthernIsleLayout.SPAN_A_END + NorthernIsleLayout.HALF_TURN_ARC * 0.5,
		NorthernIsleLayout.SPAN_B_END - 10.0,
		400.0,
		NorthernIsleLayout.SPAN_C_END + 30.0,
		NorthernIsleLayout.SPAN_C_END + NorthernIsleLayout.HALF_TURN_ARC * 0.5,
		NorthernIsleLayout.SPAN_D_END + 5.0,
		NorthernIsleLayout.start_line_arc(),
	]
	for s: float in samples:
		var frame := NorthernIsleLayout.frame_at_arc(s)
		var center: Vector3 = frame["center"]
		var forward: Vector3 = frame["forward"]
		var cross: Vector3 = frame["cross"]
		var bank := float(frame["bank"])
		assert_that(center).is_equal_approx(
			NorthernIsleLayout.point_at_arc(s), Vector3(POSITION_EPS, POSITION_EPS, POSITION_EPS))
		assert_float(forward.length()).is_equal_approx(1.0, POSITION_EPS)
		assert_float(cross.length()).is_equal_approx(1.0, POSITION_EPS)
		# TrackBuilder._frame's convention: cross = right*cos(a) - UP*sin(a).
		assert_float(cross.y).is_equal_approx(-sin(bank), POSITION_EPS)
		assert_float(bank).is_equal_approx(NorthernIsleLayout.bank_rad_at_arc(s), ANGLE_EPS)

	# Forward at the grid is +X — the travel direction the ordered checkpoints
	# and the 180 deg nose orientation assume.
	var start_forward: Vector3 = NorthernIsleLayout.frame_at_arc(0.0)["forward"]
	assert_that(start_forward).is_equal_approx(Vector3(1.0, 0.0, 0.0), Vector3(POSITION_EPS, POSITION_EPS, POSITION_EPS))
	# ... and it is neither degenerate nor flipped mid-turn (turn A's rightmost
	# point heads -Z: left/CCW travel).
	var apex_forward: Vector3 = NorthernIsleLayout.frame_at_arc(
		NorthernIsleLayout.SPAN_A_END + NorthernIsleLayout.HALF_TURN_ARC * 0.5)["forward"]
	assert_float(apex_forward.z).is_less(-0.9)
	assert_float(apex_forward.x).is_equal_approx(0.0, POSITION_EPS)
