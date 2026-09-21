# tests/suites/test_car_audio.gd
extends GdUnitTestSuite

## Deterministic static-function coverage for CarAudio's narrow-band multi-bed
## synthesis (Task 7): bed construction constraints, equal-power crossfade
## weights, on-load/off-load shaping, and WAV sanity. Pure static calls only —
## no playback, no nodes created, suite stays orphan-free.

const SPORT := CarAudio.PROFILES["sport"]
const MUSCLE := CarAudio.PROFILES["muscle"]
const RALLY := CarAudio.PROFILES["rally"]
const CROSS := CarAudio.CROSSFADE_CENTERS

func before_test() -> void:
	pass

func after_test() -> void:
	pass

func test_build_beds_returns_three_beds_for_every_profile() -> void:
	for profile: Dictionary in [SPORT, MUSCLE, RALLY]:
		var beds := CarAudio.build_beds(profile)
		assert_that(beds.size()).is_equal(3)

func test_build_beds_pitch_band_tracks_profile_sweep() -> void:
	for profile: Dictionary in [SPORT, MUSCLE, RALLY]:
		var beds := CarAudio.build_beds(profile)
		for bed: Dictionary in beds:
			assert_that(float(bed["pitch_min"])).is_equal_approx(float(profile["base_pitch"]), 0.001)
			assert_that(float(bed["pitch_max"])).is_equal_approx(float(profile["redline_pitch"]), 0.001)
			assert_that(float(bed["pitch_min"])).is_less(float(bed["pitch_max"]))
			assert_that(float(bed["pitch_max"])).is_greater(1.5)

func test_build_beds_center_ratios_climb() -> void:
	for profile: Dictionary in [SPORT, MUSCLE, RALLY]:
		var beds := CarAudio.build_beds(profile)
		for i in range(1, beds.size()):
			assert_that(float(beds[i]["center_ratio"])).is_greater(float(beds[i - 1]["center_ratio"]))

func test_build_beds_wav_sanity() -> void:
	var beds := CarAudio.build_beds(SPORT)
	for bed: Dictionary in beds:
		var wav: AudioStreamWAV = bed["wav"]
		assert_that(wav.format).is_equal(AudioStreamWAV.FORMAT_16_BITS)
		assert_that(wav.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
		assert_that(wav.loop_begin).is_equal(0)
		assert_that(wav.loop_end).is_equal(int(wav.data.size() / 2.0))
		assert_that(wav.data.size() > 0).is_true()

func test_build_beds_is_deterministic() -> void:
	var beds_a := CarAudio.build_beds(RALLY)
	var beds_b := CarAudio.build_beds(RALLY)
	for i in range(beds_a.size()):
		var wa: AudioStreamWAV = beds_a[i]["wav"]
		var wb: AudioStreamWAV = beds_b[i]["wav"]
		assert_that(wa.data.size()).is_equal(wb.data.size())
		assert_that(wa.data.decode_s16(0)).is_equal(wb.data.decode_s16(0))
		assert_that(wa.data.decode_s16(wa.data.size() - 2)).is_equal(wb.data.decode_s16(wb.data.size() - 2))

func test_crossfade_weights_idle_bed_owns_zero_rpm() -> void:
	var weights := CarAudio.crossfade_weights(0.0, CROSS)
	assert_that(weights.size()).is_equal(3)
	assert_that(weights[0]).is_equal_approx(1.0, 0.001)
	assert_that(weights[1]).is_equal_approx(0.0, 0.001)
	assert_that(weights[2]).is_equal_approx(0.0, 0.001)

func test_crossfade_weights_top_bed_owns_redline() -> void:
	var weights := CarAudio.crossfade_weights(1.0, CROSS)
	assert_that(weights[0]).is_equal_approx(0.0, 0.001)
	assert_that(weights[1]).is_equal_approx(0.0, 0.001)
	assert_that(weights[2]).is_equal_approx(1.0, 0.001)

func test_crossfade_weights_midpoint_blends_adjacent_beds() -> void:
	var weights := CarAudio.crossfade_weights(0.25, CROSS)
	assert_that(weights[0]).is_equal_approx(0.5, 0.01)
	assert_that(weights[1]).is_equal_approx(0.5, 0.01)
	assert_that(weights[2]).is_equal_approx(0.0, 0.001)

func test_crossfade_weights_sum_to_one_across_sweep() -> void:
	for i in range(11):
		var t := float(i) / 10.0
		var weights := CarAudio.crossfade_weights(t, CROSS)
		var total := weights[0] + weights[1] + weights[2]
		assert_that(total).is_between(0.98, 1.02)

func test_crossfade_weights_stay_in_unit_range() -> void:
	for t: float in [0.0, 0.1, 0.25, 0.33, 0.5, 0.66, 0.75, 0.9, 1.0]:
		var weights := CarAudio.crossfade_weights(t, CROSS)
		for w: float in weights:
			assert_that(w).is_between(0.0, 1.0)

func test_layer_weights_off_load_keeps_bass_bed() -> void:
	var weights := CarAudio.layer_weights(0.5, 0.0)
	assert_that(weights.size()).is_equal(3)
	assert_that(weights[0]).is_between(0.2, 0.4)
	assert_that(weights[1]).is_greater(weights[0])
	assert_that(weights[2]).is_less(weights[1])
	assert_that(weights[0] + weights[1] + weights[2]).is_between(0.98, 1.02)

func test_layer_weights_bass_bleed_recedes_with_load() -> void:
	var coast := CarAudio.layer_weights(0.5, 0.0)
	var loaded := CarAudio.layer_weights(0.5, 1.0)
	assert_that(coast[0]).is_greater(loaded[0])
	assert_that(coast[0] + coast[1] + coast[2]).is_between(0.98, 1.02)
	assert_that(loaded[0] + loaded[1] + loaded[2]).is_between(0.98, 1.02)

func test_layer_weights_on_load_matches_crossfade() -> void:
	for t: float in [0.0, 0.1, 0.25, 0.5, 0.75, 1.0]:
		var expected := CarAudio.crossfade_weights(t, CROSS)
		var got := CarAudio.layer_weights(t, 1.0)
		for i in range(expected.size()):
			assert_that(got[i]).is_equal_approx(expected[i], 0.001)
		assert_that(got[0] + got[1] + got[2]).is_between(0.98, 1.02)

func test_pulse_env_is_periodic() -> void:
	var period := 4410
	var a := CarAudio._pulse_env(0, period, 4)
	var b := CarAudio._pulse_env(period, period, 4)
	assert_that(a).is_equal_approx(b, 0.000001)
	assert_that(a).is_greater(0.0)

func test_load_shaping_off_load_is_minimal() -> void:
	var shaping := CarAudio.load_shaping(0.0)
	assert_that(float(shaping["gain_db"])).is_equal_approx(0.0, 0.001)
	assert_that(float(shaping["lpf_hz"])).is_equal_approx(CarAudio.LPF_OFF_HZ, 0.001)

func test_load_shaping_on_load_is_boosted() -> void:
	var shaping := CarAudio.load_shaping(1.0)
	assert_that(float(shaping["gain_db"])).is_equal_approx(CarAudio.LOAD_GAIN_DB, 0.001)
	assert_that(float(shaping["lpf_hz"])).is_equal_approx(CarAudio.LPF_ON_HZ, 0.001)

func test_load_shaping_is_monotonic() -> void:
	var low := CarAudio.load_shaping(0.0)
	var high := CarAudio.load_shaping(1.0)
	assert_that(float(high["gain_db"])).is_greater(float(low["gain_db"]))
	assert_that(float(high["lpf_hz"])).is_greater(float(low["lpf_hz"]))

func test_traffic_audio_range_is_positive() -> void:
	assert_that(CarAudio.TRAFFIC_AUDIO_RANGE).is_greater(0.0)