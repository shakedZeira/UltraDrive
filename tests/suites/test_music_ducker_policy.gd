# tests/suites/test_music_ducker_policy.gd
extends GdUnitTestSuite

const FR := MusicPolicy.Context.FREE_ROAM

func test_crash_duck_scales_with_strength_and_has_a_threshold() -> void:
	assert_that(MusicDucker.crash_duck_db(10.0)).is_equal(0.0)
	assert_that(MusicDucker.crash_duck_db(MusicDucker.CRASH_THRESHOLD)).is_equal_approx(-6.0, 0.001)
	assert_that(MusicDucker.crash_duck_db(MusicDucker.CRASH_THRESHOLD * 3.0)).is_equal_approx(-12.0, 0.001)
	assert_that(MusicDucker.crash_duck_db(99999.0)).is_equal_approx(-12.0, 0.001)
	assert_that(MusicDucker.crash_duck_db(MusicDucker.CRASH_THRESHOLD * 2.0)).is_less(-6.0)

func test_overlapping_ducks_take_the_deepest_not_the_sum() -> void:
	assert_that(MusicDucker.combine([-6.0, -5.0, -8.0])).is_equal(-8.0)
	assert_that(MusicDucker.combine([])).is_equal(0.0)

func test_combined_duck_is_clamped_to_minus_18() -> void:
	assert_that(MusicDucker.combine([-30.0, -12.0])).is_equal(MusicDucker.MAX_DUCK_DB)
	assert_that(MusicDucker.MAX_DUCK_DB).is_equal(-18.0)

func test_attack_is_fast_and_release_is_slow() -> void:
	# Full range (18 dB): attack 0.15 s, release 1.2 s.
	var down := MusicDucker.slew_db(0.0, -18.0, 0.075)
	assert_that(down).is_equal_approx(-9.0, 0.001)
	assert_that(MusicDucker.slew_db(0.0, -18.0, 1.0)).is_equal(-18.0)
	var up := MusicDucker.slew_db(-18.0, 0.0, 0.6)
	assert_that(up).is_equal_approx(-9.0, 0.001)
	assert_that(MusicDucker.slew_db(-18.0, 0.0, 5.0)).is_equal(0.0)
	assert_that(MusicDucker.slew_db(-5.0, -5.0, 1.0)).is_equal(-5.0)

func test_one_shot_hold_then_linear_release_with_fake_time() -> void:
	var d := MusicDucker.new()
	d.trigger("crash", -10.0, 0.8, 1.5)
	assert_that(d.target_db()).is_equal(-10.0)
	d.advance(0.8)
	assert_that(d.target_db()).is_equal(-10.0) # end of hold
	d.advance(0.75) # half the release
	assert_that(d.target_db()).is_equal_approx(-5.0, 0.01)
	d.advance(0.8) # past hold + release
	assert_that(d.target_db()).is_equal(0.0)
	assert_that(d.is_active()).is_false()

func test_sources_overlap_by_deepest_and_weaker_trigger_does_not_replace() -> void:
	var d := MusicDucker.new()
	d.trigger("crash", -12.0, 0.8, 1.5)
	d.trigger("trap", MusicDucker.SPEED_TRAP_DB, MusicDucker.SPEED_TRAP_HOLD_S)
	assert_that(d.target_db()).is_equal(-12.0)
	d.trigger("crash", -6.0, 0.8, 1.5) # weaker than the running one: ignored
	assert_that(d.target_db()).is_equal(-12.0)
	d.trigger("crash", -15.0, 0.8, 1.5) # deeper: replaces
	assert_that(d.target_db()).is_equal(-15.0)

func test_sustained_hold_lasts_until_cleared() -> void:
	var d := MusicDucker.new()
	d.hold("context", -8.0)
	d.advance(100.0)
	assert_that(d.target_db()).is_equal(-8.0)
	d.hold("context", 0.0) # zero clears
	assert_that(d.target_db()).is_equal(0.0)

# --- policy ---------------------------------------------------------------

func test_policy_plays_only_in_free_roam() -> void:
	var s := MusicSettings.defaults()
	assert_that(MusicPolicy.policy_for(FR, s)["play"]).is_true()
	for ctx in [MusicPolicy.Context.NONE, MusicPolicy.Context.RACE, MusicPolicy.Context.GARAGE, MusicPolicy.Context.MENU]:
		var p := MusicPolicy.policy_for(ctx, s)
		assert_that(p["play"]).is_false()
		assert_that(p["fade_s"]).is_equal(MusicPolicy.FADE_OUT_S)

func test_policy_free_roam_fades_in_over_one_second() -> void:
	assert_that(MusicPolicy.policy_for(FR, MusicSettings.defaults())["fade_s"]).is_equal(1.0)

func test_policy_pause_menu_ducks_and_muffles() -> void:
	var p := MusicPolicy.policy_for(FR, MusicSettings.defaults(), {"paused": true})
	assert_that(p["play"]).is_true()
	assert_that(p["duck_db"]).is_equal(-8.0)
	assert_that(p["lpf_hz"]).is_equal(MusicPolicy.PAUSE_LPF_HZ)
	var open := MusicPolicy.policy_for(FR, MusicSettings.defaults())
	assert_that(open["lpf_hz"]).is_equal(MusicPolicy.LPF_OPEN_HZ)
	assert_that(open["duck_db"]).is_equal(0.0)

func test_policy_photo_mode_ducks_lightly() -> void:
	var p := MusicPolicy.policy_for(FR, MusicSettings.defaults(), {"photo": true})
	assert_that(p["duck_db"]).is_equal(-4.0)
	assert_that(p["lpf_hz"]).is_equal(MusicPolicy.LPF_OPEN_HZ)

func test_policy_disabled_or_streamer_safe_is_silent_everywhere() -> void:
	var off := MusicSettings.defaults()
	off["enabled"] = false
	assert_that(MusicPolicy.policy_for(FR, off)["play"]).is_false()
	var streamer := MusicSettings.defaults()
	streamer["streamer_safe"] = true
	assert_that(MusicPolicy.policy_for(FR, streamer)["play"]).is_false()
