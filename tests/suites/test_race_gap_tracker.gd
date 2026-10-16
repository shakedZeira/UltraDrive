# tests/suites/test_race_gap_tracker.gd
extends GdUnitTestSuite

## Gate for the live standings gap ("virtual checkpoints"). Pure math, no scene:
## a dense circle stands in for the racing line, two plain Objects for the cars,
## and each is fed a constant-speed sample stream so the expected gap is
## analytic. The deltas must be smooth/continuous (interpolated between the
## fixed virtual-checkpoint grid) and signed (+ behind, - ahead).

const RADIUS := 100.0
const PATH_POINTS := 1440
const DT := 1.0 / 60.0

func _circle_path(radius: float, count: int) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for i in range(count):
		var a := float(i) / float(count) * TAU
		pts.append(Vector3(cos(a) * radius, 0.0, sin(a) * radius))
	return pts

func _arc_pos(radius: float, s: float) -> Vector3:
	var a := s / radius
	return Vector3(cos(a) * radius, 0.0, sin(a) * radius)

func _new_tracker() -> RaceGapTracker:
	var tracker := RaceGapTracker.new()
	tracker.configure(_circle_path(RADIUS, PATH_POINTS), 5.0)
	return tracker

# --- configuration guards ---------------------------------------------------

func test_configure_rejects_degenerate_paths() -> void:
	var tracker := RaceGapTracker.new()
	tracker.configure([] as Array[Vector3])
	assert_that(tracker.is_active()).is_false()
	tracker.configure([Vector3.ZERO, Vector3(1, 0, 0)])
	assert_that(tracker.is_active()).is_false()
	# Zero spacing is unusable.
	tracker.configure(_circle_path(10.0, 64), 0.0)
	assert_that(tracker.is_active()).is_false()
	# Coincident points sweep no arc.
	var same: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	tracker.configure(same)
	assert_that(tracker.is_active()).is_false()
	assert_that(is_nan(tracker.gap_seconds(Object.new(), Object.new()))).is_true()

func test_configure_builds_virtual_checkpoint_grid() -> void:
	var tracker := _new_tracker()
	assert_that(tracker.is_active()).is_true()
	assert_float(tracker.path_length()).is_equal_approx(TAU * RADIUS, 1.0)
	# ~5 m spacing over the circumference.
	assert_int(tracker.vcp_count()).is_equal(int(ceil(TAU * RADIUS / 5.0)))
	# Reconfigure clears samples.
	tracker.configure(_circle_path(RADIUS, PATH_POINTS), 5.0)
	assert_that(tracker.is_active()).is_true()

func test_progress_wraps_at_the_path_seam() -> void:
	var tracker := _new_tracker()
	var total := tracker.path_length()
	var near := tracker.progress_of(_arc_pos(RADIUS, total - 1.0))
	assert_float(near).is_greater(total - 5.0)
	var start := tracker.progress_of(_arc_pos(RADIUS, 0.0))
	assert_float(start).is_less(5.0)

# --- gap math ---------------------------------------------------------------

func test_identical_samples_report_zero_gap() -> void:
	var tracker := _new_tracker()
	var player := Object.new()
	var rival := Object.new()
	for i in range(120):
		var t := float(i) * DT
		var pos := _arc_pos(RADIUS, 30.0 * t)
		tracker.sample(player, pos, t)
		tracker.sample(rival, pos, t)
	assert_float(tracker.gap_seconds(rival, player)).is_equal_approx(0.0, 0.001)

func test_faster_rival_reads_ahead_with_negative_gap() -> void:
	var tracker := _new_tracker()
	var player := Object.new()
	var rival := Object.new()
	var v_p := 20.0
	var v_r := 25.0
	var s_p := 0.0
	var s_r := 0.0
	var t := 0.0
	for _i in range(180):
		tracker.sample(player, _arc_pos(RADIUS, s_p), t)
		tracker.sample(rival, _arc_pos(RADIUS, s_r), t)
		s_p += v_p * DT
		s_r += v_r * DT
		t += DT
	# The player is at s_p; the rival passed that point EARLIER than the player.
	var expected := s_p / v_r - s_p / v_p
	var gap := tracker.gap_seconds(rival, player)
	assert_that(gap).is_less(0.0)
	assert_float(gap).is_equal_approx(expected, 0.05)

func test_slower_rival_reads_behind_with_positive_gap() -> void:
	var tracker := _new_tracker()
	var player := Object.new()
	var rival := Object.new()
	var v_p := 25.0
	var v_r := 20.0
	var s_p := 0.0
	var s_r := 0.0
	var t := 0.0
	var last_s_r := 0.0
	for _i in range(180):
		tracker.sample(player, _arc_pos(RADIUS, s_p), t)
		tracker.sample(rival, _arc_pos(RADIUS, s_r), t)
		last_s_r = s_r
		s_p += v_p * DT
		s_r += v_r * DT
		t += DT
	# The rival has not reached the player's point yet: positive = behind. The
	# common point is the rival's (trailing) S, which the player already passed.
	var expected := last_s_r / v_r - last_s_r / v_p
	var gap := tracker.gap_seconds(rival, player)
	assert_that(gap).is_greater(0.0)
	assert_float(gap).is_equal_approx(expected, 0.05)

func test_gap_is_smooth_across_a_virtual_checkpoint() -> void:
	# Walk the rival in 0.2 m steps across several 5 m virtual checkpoints; the
	# reported gap must never jump by more than a frame's worth of movement (a
	# big jump would mean the gap only updates per checkpoint).
	var tracker := _new_tracker()
	var player := Object.new()
	var rival := Object.new()
	# Player sits still at S=0 with a steady clock; the rival approaches S=0 the
	# long way round. Sample the player first so both share the clock.
	var prev := NAN
	var max_step := 0.0
	var s_r := 0.0
	for i in range(200):
		var t := float(i) * DT
		tracker.sample(player, _arc_pos(RADIUS, 0.0), t)
		tracker.sample(rival, _arc_pos(RADIUS, s_r), t)
		var gap := tracker.gap_seconds(rival, player)
		if not is_nan(gap) and not is_nan(prev):
			max_step = maxf(max_step, absf(gap - prev))
		prev = gap
		s_r += 0.2
	assert_float(max_step).is_less(0.02)

func test_different_laps_report_nan() -> void:
	var tracker := RaceGapTracker.new()
	tracker.configure(_circle_path(20.0, PATH_POINTS), 5.0)
	var player := Object.new()
	var rival := Object.new()
	# The player never leaves the line; the rival laps the loop. Radius 20 gives a
	# ~125.7 m circumference, so 20 m/s over 800 frames (~13.3 s) is ~266 m, i.e.
	# the rival is genuinely on lap 2 while the player is still on lap 0.
	var s_r := 0.0
	for i in range(800):
		var t := float(i) * DT
		tracker.sample(player, _arc_pos(20.0, 0.0), t)
		tracker.sample(rival, _arc_pos(20.0, s_r), t)
		s_r += 20.0 * DT
	assert_that(is_nan(tracker.gap_seconds(rival, player))).is_true()

func test_unknown_car_reports_nan() -> void:
	var tracker := _new_tracker()
	var player := Object.new()
	tracker.sample(player, _arc_pos(RADIUS, 5.0), 0.0)
	assert_that(is_nan(tracker.gap_seconds(Object.new(), player))).is_true()
	assert_that(is_nan(tracker.gap_seconds(player, player))).is_true()

# --- formatting -------------------------------------------------------------

func test_format_gap_seconds() -> void:
	assert_that(RaceUI.format_gap_seconds(0.42)).is_equal("+0.42")
	assert_that(RaceUI.format_gap_seconds(-0.37)).is_equal("-0.37")
	assert_that(RaceUI.format_gap_seconds(0.0)).is_equal("+0.00")
	assert_that(RaceUI.format_gap_seconds(0.004)).is_equal("+0.00")
	assert_that(RaceUI.format_gap_seconds(12.34)).is_equal("+12.3")
	assert_that(RaceUI.format_gap_seconds(-25.0)).is_equal("-25.0")
	assert_that(RaceUI.format_gap_seconds(NAN)).is_equal("")
