# tests/suites/test_music_crossfade_math.gd
extends GdUnitTestSuite

func test_equal_power_sums_to_constant_power() -> void:
	for i in range(0, 21):
		var t := float(i) / 20.0
		var o := CrossfadeMath.out_gain(t)
		var n := CrossfadeMath.in_gain(t)
		assert_that(o * o + n * n).is_equal_approx(1.0, 0.0001)

func test_curve_endpoints_and_clamping() -> void:
	assert_that(CrossfadeMath.out_gain(0.0)).is_equal_approx(1.0, 0.0001)
	assert_that(CrossfadeMath.in_gain(0.0)).is_equal_approx(0.0, 0.0001)
	assert_that(CrossfadeMath.out_gain(1.0)).is_equal_approx(0.0, 0.0001)
	assert_that(CrossfadeMath.in_gain(1.0)).is_equal_approx(1.0, 0.0001)
	assert_that(CrossfadeMath.out_gain(-3.0)).is_equal_approx(1.0, 0.0001)
	assert_that(CrossfadeMath.in_gain(7.0)).is_equal_approx(1.0, 0.0001)

func test_gain_to_db_floors_at_silence() -> void:
	assert_that(CrossfadeMath.gain_to_db(1.0)).is_equal_approx(0.0, 0.001)
	assert_that(CrossfadeMath.gain_to_db(0.5)).is_equal_approx(-6.02, 0.05)
	assert_that(CrossfadeMath.gain_to_db(0.0)).is_equal(CrossfadeMath.SILENCE_DB)
	assert_that(CrossfadeMath.gain_to_db(0.0001)).is_equal(CrossfadeMath.SILENCE_DB)

func test_fade_zero_or_negative_disables() -> void:
	assert_that(CrossfadeMath.window_for(0.0, 200.0)).is_equal(0.0)
	assert_that(CrossfadeMath.window_for(-1.0, 200.0)).is_equal(0.0)

func test_unknown_length_never_pre_empts() -> void:
	assert_that(CrossfadeMath.window_for(2.5, 0.0)).is_equal(0.0)
	assert_that(CrossfadeMath.should_start_next(0.0, 100.0, 0.0, 2.5)).is_false()
	assert_that(CrossfadeMath.should_start_next(-1.0, 0.0, 0.0, 2.5)).is_false()

func test_short_track_window_shrinks_to_half_length() -> void:
	assert_that(CrossfadeMath.window_for(2.5, 3.0)).is_equal_approx(1.5, 0.0001)
	assert_that(CrossfadeMath.window_for(2.5, 200.0)).is_equal_approx(2.5, 0.0001)

func test_start_next_triggers_inside_the_window_only() -> void:
	assert_that(CrossfadeMath.should_start_next(100.0, 90.0, 0.0, 2.5)).is_false()
	assert_that(CrossfadeMath.should_start_next(100.0, 97.4, 0.0, 2.5)).is_false()
	assert_that(CrossfadeMath.should_start_next(100.0, 97.5, 0.0, 2.5)).is_true()
	# time-since-last-mix compensates the quantised playback position
	assert_that(CrossfadeMath.should_start_next(100.0, 97.0, 0.6, 2.5)).is_true()
	assert_that(CrossfadeMath.should_start_next(100.0, 100.0, 0.0, 0.0)).is_true()

func test_advance_t_clamps_and_completes_instantly_for_zero_length() -> void:
	assert_that(CrossfadeMath.advance_t(0.0, 0.5, 2.0)).is_equal_approx(0.25, 0.0001)
	assert_that(CrossfadeMath.advance_t(0.9, 5.0, 2.0)).is_equal(1.0)
	assert_that(CrossfadeMath.advance_t(0.0, 0.1, 0.0)).is_equal(1.0)
