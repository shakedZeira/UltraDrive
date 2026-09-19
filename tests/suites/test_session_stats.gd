# tests/suites/test_session_stats.gd
extends GdUnitTestSuite

## S3 gate: pure SessionStats math (no scene). Distance accumulates
## monotonically, top speed keeps the session max, max G clamps to the cap,
## drift time sums only drifting frames, clean laps require zero impacts in the
## lap, best lap is the session minimum, reset() zeroes every counter and
## identical tick sequences are deterministic. Instances are lightweight
## RefCounted locals — nothing to leak.

func test_distance_accumulates_monotonically() -> void:
	var stats := SessionStats.new()
	stats.tick(0.5, 36.0, 0.0, false)
	stats.tick(0.5, 36.0, 0.0, false)
	stats.tick(1.0, 36.0, 0.0, false)
	assert_that(stats.get_distance_m()).is_equal_approx(20.0, 0.0001)
	assert_that(stats.get_distance_km()).is_equal_approx(0.02, 0.0001)
	var before := stats.get_distance_m()
	stats.tick(2.0, 72.0, 0.0, false)
	assert_that(stats.get_distance_m()).is_greater(before)

func test_top_speed_keeps_session_maximum() -> void:
	var stats := SessionStats.new()
	stats.tick(0.1, 40.0, 0.0, false)
	stats.tick(0.1, 120.0, 0.0, false)
	stats.tick(0.1, 80.0, 0.0, false)
	assert_that(stats.get_top_speed_kmh()).is_equal(120.0)

func test_max_g_clamps_to_cap() -> void:
	var stats := SessionStats.new()
	stats.tick(1.0, 60.0, 1.5, false)
	stats.tick(1.0, 60.0, SessionStats.MAX_G * 2.0, false)
	stats.tick(1.0, 60.0, 3.1, false)
	assert_that(stats.get_max_g()).is_equal(SessionStats.MAX_G)
	assert_that(stats.get_max_g()).is_equal(6.0)

func test_max_g_absorbs_negative_sign() -> void:
	var stats := SessionStats.new()
	stats.tick(1.0, 60.0, -2.5, false)
	assert_that(stats.get_max_g()).is_equal(2.5)

func test_drift_time_sums_only_drifting_frames() -> void:
	var stats := SessionStats.new()
	stats.tick(1.0, 80.0, 0.0, true)
	stats.tick(2.0, 80.0, 0.0, false)
	stats.tick(0.5, 80.0, 0.0, true)
	stats.tick(0.25, 80.0, 0.0, false)
	assert_that(stats.get_drift_time()).is_equal_approx(1.5, 0.0001)

func test_clean_lap_requires_zero_impacts_in_the_lap() -> void:
	var stats := SessionStats.new()
	stats.start_lap()
	stats.end_lap(60.0)
	assert_that(stats.last_lap_was_clean()).is_true()
	assert_that(stats.get_clean_laps()).is_equal(1)
	assert_that(stats.get_total_laps()).is_equal(1)

	stats.start_lap()
	stats.note_impact()
	stats.end_lap(61.0)
	assert_that(stats.last_lap_was_clean()).is_false()
	assert_that(stats.get_clean_laps()).is_equal(1)
	assert_that(stats.get_total_laps()).is_equal(2)

	stats.start_lap()
	stats.note_impact()
	stats.note_impact()
	stats.end_lap(62.0)
	assert_that(stats.last_lap_was_clean()).is_false()
	assert_that(stats.get_clean_laps()).is_equal(1)

func test_impact_counter_resets_on_start_lap() -> void:
	var stats := SessionStats.new()
	stats.start_lap()
	stats.note_impact()
	stats.note_impact()
	assert_that(stats.get_lap_impacts()).is_equal(2)
	stats.start_lap()
	assert_that(stats.get_lap_impacts()).is_equal(0)
	stats.end_lap(30.0)
	assert_that(stats.last_lap_was_clean()).is_true()

func test_best_lap_is_the_session_minimum() -> void:
	var stats := SessionStats.new()
	stats.start_lap()
	stats.end_lap(95.0)
	stats.start_lap()
	stats.end_lap(88.5)
	stats.start_lap()
	stats.end_lap(92.0)
	assert_that(stats.get_best_lap()).is_equal_approx(88.5, 0.0001)

func test_reset_zeroes_every_counter() -> void:
	var stats := SessionStats.new()
	stats.tick(1.0, 120.0, 3.0, true)
	stats.start_lap()
	stats.note_impact()
	stats.end_lap(45.0)
	stats.reset()
	assert_that(stats.get_distance_m()).is_equal(0.0)
	assert_that(stats.get_top_speed_kmh()).is_equal(0.0)
	assert_that(stats.get_max_g()).is_equal(0.0)
	assert_that(stats.get_drift_time()).is_equal(0.0)
	assert_that(stats.get_total_laps()).is_equal(0)
	assert_that(stats.get_clean_laps()).is_equal(0)
	assert_that(stats.get_best_lap()).is_equal(0.0)
	assert_that(stats.get_lap_impacts()).is_equal(0)
	assert_that(stats.last_lap_was_clean()).is_false()

func test_identical_tick_sequences_are_deterministic() -> void:
	var a := SessionStats.new()
	var b := SessionStats.new()
	for i in range(24):
		var speed := 15.0 + float(i) * 7.0
		var max_g := float(i % 5) * 0.8
		var drifting := i % 3 == 0
		a.tick(0.016, speed, max_g, drifting)
		b.tick(0.016, speed, max_g, drifting)
	assert_that(a.get_distance_m()).is_greater(0.0)
	assert_that(a.get_distance_m()).is_equal_approx(b.get_distance_m(), 0.0001)
	assert_that(a.get_top_speed_kmh()).is_equal(b.get_top_speed_kmh())
	assert_that(a.get_max_g()).is_equal(b.get_max_g())
	assert_that(a.get_drift_time()).is_equal_approx(b.get_drift_time(), 0.0001)
	assert_that(a.get_total_laps()).is_equal(b.get_total_laps())
	assert_that(a.get_best_lap()).is_equal(b.get_best_lap())