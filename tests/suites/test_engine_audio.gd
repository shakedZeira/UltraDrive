# tests/suites/test_engine_audio.gd
extends GdUnitTestSuite

## Deterministic coverage for EngineAudio's HYBRID engine audio: real V10
## sample beds (enginesound -- see LICENSES.md) with CONTINUOUS per-band pitch
## tracking, the equal-power RPM crossfade, Curve resources that reproduce it,
## load blend + gain/LPF shaping, gear-shift and lift-off transients, and a
## scene-free node probe. All static calls + one auto_freed node; no
## AudioServer, no real-clock waits. Each bed is authored at its exact RPM
## (BAND_RPMS) but is pitch-shifted every frame (band_pitch_scale = live/bed,
## clamped PITCH_MIN..PITCH_MAX) so the crossfade hands off TIMBRE while the
## mix pitch stays continuous -- the old static-ladder claim that "nothing is
## ever pitch-shifted" is obsolete and covered instead by the pitch-tracking
## tests below. REMOVED from the pre-rewrite suite by design: the old pitch
## sweep (_pitch_for / BASE_PITCH / REDLINE_PITCH), the 4-bed BED_* mapping
## and the wot one-shot clip.

func before_test() -> void:
	pass

func after_test() -> void:
	pass

func test_load_beds_returns_five_beds_in_ladder_order() -> void:
	var beds := EngineAudio.load_beds()
	assert_that(beds.size()).is_equal(5)
	for i in range(EngineAudio.BAND_ORDER.size()):
		assert_that(String(beds[i]["name"])).is_equal(EngineAudio.BAND_ORDER[i])

func test_load_beds_bed_names_map_to_filenames() -> void:
	for name: String in EngineAudio.BAND_ORDER:
		var path: String = EngineAudio.BAND_FILES[name]
		assert_that(path.ends_with("engine_%s.wav" % name)).is_true()

func test_load_beds_band_rpms_are_the_authored_engine_rpms() -> void:
	var expected: Array[float] = [800.0, 2000.0, 3500.0, 5500.0, 6900.0]
	assert_that(EngineAudio.BAND_RPMS).has_size(5)
	for i in range(expected.size()):
		assert_that(EngineAudio.BAND_RPMS[i]).is_equal_approx(expected[i], 0.001)

func test_load_beds_all_streams_resolve() -> void:
	var beds := EngineAudio.load_beds()
	for bed: Dictionary in beds:
		assert_that(bed.get("stream") is AudioStream).is_true()

func test_load_beds_all_five_are_loop_forward_wavs() -> void:
	var beds := EngineAudio.load_beds()
	for bed: Dictionary in beds:
		var wav := bed["stream"] as AudioStreamWAV
		assert_that(wav).is_not_null()
		assert_that(wav.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)

func test_load_beds_loop_end_is_explicit_stream_length() -> void:
	## Regression gate: the imported beds are QOA-compressed (4.7 importer
	## default), and Godot's QOA playback path silently fails to START when
	## loop_end is the -1 "whole sample" sentinel. Each bed must carry an
	## explicit positive loop_end equal to its frame count so the playback both
	## begins and loops.
	var beds := EngineAudio.load_beds()
	for bed: Dictionary in beds:
		var wav := bed["stream"] as AudioStreamWAV
		assert_that(wav).is_not_null()
		assert_that(wav.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
		assert_that(wav.loop_begin).is_equal(0)
		assert_that(wav.loop_end).is_greater(0)
		var expected := int(round(wav.get_length() * wav.mix_rate)) - 1
		assert_that(wav.loop_end).is_equal(maxi(expected, 1))

func test_load_beds_all_five_are_audibly_sized() -> void:
	## Belt-and-suspenders for the same regression: beds must be > 1 frame and
	## under 60 s so a silent/truncated import cannot sneak in.
	var beds := EngineAudio.load_beds()
	for bed: Dictionary in beds:
		var wav := bed["stream"] as AudioStreamWAV
		assert_that(wav).is_not_null()
		assert_that(wav.get_length()).is_greater(0.001)
		assert_that(wav.get_length()).is_less(60.0)

func test_load_beds_has_no_wot_shot() -> void:
	var beds := EngineAudio.load_beds()
	for bed: Dictionary in beds:
		assert_that(String(bed["name"])).is_not_equal("wot")

func test_band_weights_idle_bed_owns_zero_rpm() -> void:
	var centers := EngineAudio.normalized_centers()
	var weights := EngineAudio.band_weights(0.0, centers)
	assert_that(weights.size()).is_equal(5)
	assert_that(weights[0]).is_equal_approx(1.0, 0.001)
	for i in range(1, 5):
		assert_that(weights[i]).is_equal_approx(0.0, 0.001)

func test_band_weights_max_bed_owns_redline() -> void:
	var centers := EngineAudio.normalized_centers()
	var weights := EngineAudio.band_weights(1.0, centers)
	assert_that(weights[4]).is_equal_approx(1.0, 0.001)
	for i in range(4):
		assert_that(weights[i]).is_equal_approx(0.0, 0.001)

func test_band_weights_neighbours_split_at_segment_midpoint() -> void:
	var centers := EngineAudio.normalized_centers()
	var mid := (centers[0] + centers[1]) * 0.5
	var weights := EngineAudio.band_weights(mid, centers)
	assert_that(weights[0]).is_equal_approx(0.5, 0.001)
	assert_that(weights[1]).is_equal_approx(0.5, 0.001)
	assert_that(weights[2]).is_equal_approx(0.0, 0.001)
	assert_that(weights[3]).is_equal_approx(0.0, 0.001)
	assert_that(weights[4]).is_equal_approx(0.0, 0.001)

func test_band_weights_only_two_neighbours_nonzero_across_sweep() -> void:
	var centers := EngineAudio.normalized_centers()
	for i in range(20):
		var t := float(i) / 19.0
		var weights := EngineAudio.band_weights(t, centers)
		var nonzero := 0
		for w: float in weights:
			if w > 0.001:
				nonzero += 1
		assert_that(nonzero).is_less_equal(2)

func test_band_weights_sum_to_one_across_sweep() -> void:
	var centers := EngineAudio.normalized_centers()
	for i in range(11):
		var t := float(i) / 10.0
		var weights := EngineAudio.band_weights(t, centers)
		var total := 0.0
		for w: float in weights:
			total += w
		assert_that(total).is_between(0.98, 1.02)

func test_band_weights_stay_in_unit_range() -> void:
	var centers := EngineAudio.normalized_centers()
	for t: float in [0.0, 0.1, centers[1] * 0.5, centers[2], 0.7, 0.9, 1.0]:
		var weights := EngineAudio.band_weights(t, centers)
		for w: float in weights:
			assert_that(w).is_between(0.0, 1.0)

func test_band_weights_exact_center_is_single_band_owned() -> void:
	var centers := EngineAudio.normalized_centers()
	for i in range(1, 4):
		var c: float = centers[i]
		var below := EngineAudio.band_weights(c - 0.001, centers)
		var above := EngineAudio.band_weights(c + 0.001, centers)
		assert_that(below[i]).is_equal_approx(1.0, 0.005)
		assert_that(above[i]).is_equal_approx(1.0, 0.005)
		assert_that(below[i - 1]).is_less(0.01)
		assert_that(above[i + 1]).is_less(0.01)

func test_normalized_centers_are_monotonic_in_unit_range() -> void:
	var centers := EngineAudio.normalized_centers()
	assert_that(centers.size()).is_equal(5)
	for i in range(centers.size()):
		assert_that(centers[i]).is_between(0.0, 1.0)
		if i > 0:
			assert_that(centers[i]).is_greater(centers[i - 1])

func test_build_default_curves_returns_five_curves() -> void:
	var curves := EngineAudio.build_default_curves()
	assert_that(curves.size()).is_equal(5)
	for c: Curve in curves:
		assert_that(c.get_point_count()).is_greater(0)

func test_sample_curves_matches_analytic_band_weights() -> void:
	var curves := EngineAudio.build_default_curves()
	var centers := EngineAudio.normalized_centers()
	for i in range(21):
		var t := float(i) / 20.0
		var sampled := EngineAudio.sample_curves(curves, t)
		var analytic := EngineAudio.band_weights(t, centers)
		assert_that(sampled.size()).is_equal(analytic.size())
		for j in range(sampled.size()):
			assert_that(sampled[j]).is_equal_approx(analytic[j], 0.02)

func test_sample_curves_clamps_outside_domain() -> void:
	var curves := EngineAudio.build_default_curves()
	var at_n1 := EngineAudio.sample_curves(curves, -1.0)
	var at_2 := EngineAudio.sample_curves(curves, 2.0)
	assert_that(at_n1[0]).is_equal_approx(1.0, 0.001)
	assert_that(at_2[4]).is_equal_approx(1.0, 0.001)

func test_load_shaping_off_load_is_minimal() -> void:
	var shaping := EngineAudio.load_shaping(0.0)
	assert_that(float(shaping["gain_db"])).is_equal_approx(0.0, 0.001)
	assert_that(float(shaping["lpf_hz"])).is_equal_approx(EngineAudio.LPF_OFF_HZ, 0.001)

func test_load_shaping_on_load_is_boosted() -> void:
	var shaping := EngineAudio.load_shaping(1.0)
	assert_that(float(shaping["gain_db"])).is_equal_approx(EngineAudio.LOAD_GAIN_DB, 0.001)
	assert_that(float(shaping["lpf_hz"])).is_equal_approx(EngineAudio.LPF_ON_HZ, 0.001)

func test_load_shaping_is_monotonic() -> void:
	var low := EngineAudio.load_shaping(0.1)
	var high := EngineAudio.load_shaping(0.9)
	assert_that(float(high["gain_db"])).is_greater(float(low["gain_db"]))
	assert_that(float(high["lpf_hz"])).is_greater(float(low["lpf_hz"]))

func test_volume_cascade_is_audible_at_idle() -> void:
	## Audibility gate: at idle the pump's target_db for the owning band
	## (weights + load_gain + MASTER_TRIM_DB) must sit well above the -80 dB
	## mute floor and above -40 dB, so an idle car is never inaudible.
	var curves := EngineAudio.build_default_curves()
	var weights := EngineAudio.sample_curves(curves, 0.0)
	var shaping := EngineAudio.load_shaping(0.0)
	assert_that(float(shaping["gain_db"])).is_equal_approx(0.0, 0.001)
	var max_db := EngineAudio.MUTE_FLOOR_DB
	for w: float in weights:
		if w > 0.001:
			var db := clampf(linear_to_db(sqrt(w)) + float(shaping["gain_db"]) + EngineAudio.MASTER_TRIM_DB, EngineAudio.MUTE_FLOOR_DB, 6.0)
			max_db = maxf(max_db, db)
	assert_that(max_db).is_greater(-40.0)
	assert_that(max_db).is_greater(EngineAudio.MUTE_FLOOR_DB + 10.0)

func test_volume_cascade_is_audible_at_mid_rpm() -> void:
	## Audibility gate at mid ladder (~4200 rpm, the peak-power region): the
	## loudest crossfaded neighbour band must land above -40 dB.
	var curves := EngineAudio.build_default_curves()
	var rpm_norm := (4150.0 - EngineAudio.IDLE_RPM) / (EngineAudio.REDLINE_RPM - EngineAudio.IDLE_RPM)
	var weights := EngineAudio.sample_curves(curves, rpm_norm)
	var shaping := EngineAudio.load_shaping(0.5)
	var max_db := EngineAudio.MUTE_FLOOR_DB
	for w: float in weights:
		if w > 0.001:
			var db := clampf(linear_to_db(sqrt(w)) + float(shaping["gain_db"]) + EngineAudio.MASTER_TRIM_DB, EngineAudio.MUTE_FLOOR_DB, 6.0)
			max_db = maxf(max_db, db)
	assert_that(max_db).is_greater(-40.0)

func test_ready_builds_five_band_players_with_real_streams() -> void:
	var audio: EngineAudio = auto_free(EngineAudio.new())
	add_child(audio)
	assert_that(audio.get_child_count()).is_equal(5)
	for i in range(5):
		var player := audio.get_child(i) as AudioStreamPlayer3D
		assert_that(player).is_not_null()
		assert_that(player.stream is AudioStream).is_true()
		assert_that(player.stream.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
		assert_that(player.volume_db).is_less(-70.0)

func test_ready_installs_default_curves_when_unset() -> void:
	var audio: EngineAudio = auto_free(EngineAudio.new())
	add_child(audio)
	assert_that(audio.volume_curves.size()).is_equal(5)

func test_set_audio_active_false_mutes_to_floor() -> void:
	var audio: EngineAudio = auto_free(EngineAudio.new())
	add_child(audio)
	audio.set_audio_active(false)
	for i in range(5):
		var player := audio.get_child(i) as AudioStreamPlayer3D
		assert_that(player.volume_db).is_equal(EngineAudio.MUTE_FLOOR_DB)

func test_traffic_audio_range_reaches_further_than_synth() -> void:
	assert_that(EngineAudio.TRAFFIC_AUDIO_RANGE).is_greater(CarAudio.TRAFFIC_AUDIO_RANGE)

## --- Hybrid continuous-pitch tracking (round 2) ---

func test_band_pitch_scale_is_unity_when_live_equals_bed_rpm() -> void:
	assert_that(EngineAudio.band_pitch_scale(800.0, 800.0)).is_equal_approx(1.0, 0.001)
	assert_that(EngineAudio.band_pitch_scale(3500.0, 3500.0)).is_equal_approx(1.0, 0.001)
	assert_that(EngineAudio.band_pitch_scale(6900.0, 6900.0)).is_equal_approx(1.0, 0.001)

func test_band_pitch_scale_rises_above_one_for_higher_live_rpm() -> void:
	var pitch := EngineAudio.band_pitch_scale(3000.0, 2000.0)
	assert_that(pitch).is_greater(1.0)
	assert_that(pitch).is_equal_approx(1.5, 0.001)

func test_band_pitch_scale_falls_below_one_for_lower_live_rpm() -> void:
	var pitch := EngineAudio.band_pitch_scale(1500.0, 2000.0)
	assert_that(pitch).is_less(1.0)
	assert_that(pitch).is_equal_approx(0.75, 0.001)

func test_band_pitch_scale_clamps_to_floor_and_ceiling() -> void:
	assert_that(EngineAudio.PITCH_MIN).is_equal_approx(0.5, 0.001)
	assert_that(EngineAudio.PITCH_MAX).is_equal_approx(1.7, 0.001)
	assert_that(EngineAudio.band_pitch_scale(100.0, 6900.0)).is_equal_approx(EngineAudio.PITCH_MIN, 0.001)
	assert_that(EngineAudio.band_pitch_scale(6900.0, 800.0)).is_equal_approx(EngineAudio.PITCH_MAX, 0.001)

func test_band_pitch_scale_degenerate_band_rpm_returns_unity() -> void:
	assert_that(EngineAudio.band_pitch_scale(3000.0, 0.0)).is_equal_approx(1.0, 0.001)
	assert_that(EngineAudio.band_pitch_scale(3000.0, -100.0)).is_equal_approx(1.0, 0.001)

func test_effective_band_rpm_tracks_live_rpm_inside_clamp_window() -> void:
	assert_that(EngineAudio.effective_band_rpm(2750.0, 2000.0)).is_equal_approx(2750.0, 0.001)
	assert_that(EngineAudio.effective_band_rpm(1200.0, 800.0)).is_equal_approx(1200.0, 0.001)

func test_mix_pitch_estimate_near_equals_live_rpm_at_handoff() -> void:
	## Continuous hand-off property: wherever BOTH active neighbours are inside
	## their PITCH_MIN..PITCH_MAX windows, each band's effective RPM equals the
	## live RPM, so the equal-power weighted mix pitch equals the live RPM.
	for live: float in [1200.0, 2750.0, 4500.0, 6200.0]:
		var rpm_norm := EngineAudio.rpm_normalized(live, EngineAudio.IDLE_RPM, EngineAudio.REDLINE_RPM)
		var mix := EngineAudio.mix_pitch_estimate(live, rpm_norm)
		assert_that(mix).is_equal_approx(live, 0.001)

func test_mix_pitch_estimate_at_ladder_endpoints() -> void:
	var at_idle := EngineAudio.mix_pitch_estimate(EngineAudio.IDLE_RPM, 0.0)
	assert_that(at_idle).is_equal_approx(EngineAudio.IDLE_RPM, 0.001)
	var at_redline := EngineAudio.mix_pitch_estimate(EngineAudio.REDLINE_RPM, 1.0)
	assert_that(at_redline).is_equal_approx(EngineAudio.REDLINE_RPM, 0.001)

func test_rpm_normalized_boundaries_and_midpoint() -> void:
	assert_that(EngineAudio.rpm_normalized(800.0, 800.0, 7000.0)).is_equal_approx(0.0, 0.001)
	assert_that(EngineAudio.rpm_normalized(7000.0, 800.0, 7000.0)).is_equal_approx(1.0, 0.001)
	assert_that(EngineAudio.rpm_normalized(3900.0, 800.0, 7000.0)).is_equal_approx(0.5, 0.001)

func test_rpm_normalized_clamps_outside_idle_redline() -> void:
	assert_that(EngineAudio.rpm_normalized(100.0, 800.0, 7000.0)).is_equal_approx(0.0, 0.001)
	assert_that(EngineAudio.rpm_normalized(9000.0, 800.0, 7000.0)).is_equal_approx(1.0, 0.001)

func test_rpm_normalized_is_monotonic_in_rpm() -> void:
	var prev := -1.0
	for i in range(9):
		var rpm := lerpf(0.0, 8000.0, float(i) / 8.0)
		var norm := EngineAudio.rpm_normalized(rpm, 800.0, 7000.0)
		assert_that(norm).is_greater_equal(prev)
		prev = norm

func test_load_value_boundaries() -> void:
	assert_that(EngineAudio.load_value(0.0, 0.0, 0.0)).is_equal_approx(0.0, 0.001)
	assert_that(EngineAudio.load_value(0.5, 1.0, 0.0)).is_equal_approx(0.675, 0.001)
	assert_that(EngineAudio.load_value(1.0, 1.0, 1.0)).is_equal_approx(1.0, 0.001)
	assert_that(EngineAudio.load_value(-1.0, -1.0, -5.0)).is_equal_approx(0.0, 0.001)

func test_load_value_is_monotonic_in_throttle() -> void:
	var coast := EngineAudio.load_value(0.5, 0.0, 0.0)
	var half := EngineAudio.load_value(0.5, 0.5, 0.0)
	var full := EngineAudio.load_value(0.5, 1.0, 0.0)
	assert_that(half).is_greater(coast)
	assert_that(full).is_greater(half)

func test_load_value_is_monotonic_in_rpm_norm() -> void:
	var low := EngineAudio.load_value(0.2, 0.3, 0.0)
	var high := EngineAudio.load_value(0.8, 0.3, 0.0)
	assert_that(high).is_greater(low)

func test_load_value_positive_rpm_slew_adds_load() -> void:
	var coast := EngineAudio.load_value(0.5, 0.0, 0.0)
	var blip := EngineAudio.load_value(0.5, 0.0, 0.5)
	assert_that(blip).is_greater(coast)
	assert_that(blip).is_equal_approx(0.325, 0.001)

func test_gear_shift_pitch_mult_dips_then_recovers() -> void:
	var catch := EngineAudio.gear_shift_pitch_mult(0.0)
	assert_that(catch).is_equal_approx(EngineAudio.SHIFT_DIP_MIN, 0.001)
	assert_that(catch).is_equal_approx(0.82, 0.001)
	var done := EngineAudio.gear_shift_pitch_mult(EngineAudio.SHIFT_DURATION)
	assert_that(done).is_equal_approx(1.0, 0.001)

func test_gear_shift_pitch_mult_recovers_monotonically() -> void:
	var prev := -1.0
	for i in range(11):
		var elapsed := EngineAudio.SHIFT_DURATION * float(i) / 10.0
		var mult := EngineAudio.gear_shift_pitch_mult(elapsed)
		assert_that(mult).is_between(EngineAudio.SHIFT_DIP_MIN - 0.001, 1.001)
		assert_that(mult).is_greater_equal(prev)
		prev = mult

func test_gear_shift_gain_mult_blips_then_returns_to_unity() -> void:
	var blip := EngineAudio.gear_shift_gain_mult(0.0)
	assert_that(blip).is_greater(1.0)
	assert_that(blip).is_equal_approx(EngineAudio.SHIFT_BLIP_GAIN, 0.001)
	var done := EngineAudio.gear_shift_gain_mult(EngineAudio.SHIFT_DURATION)
	assert_that(done).is_equal_approx(1.0, 0.001)

func test_gear_shift_gain_mult_decays_monotonically() -> void:
	var prev := 10.0
	for i in range(11):
		var elapsed := EngineAudio.SHIFT_DURATION * float(i) / 10.0
		var mult := EngineAudio.gear_shift_gain_mult(elapsed)
		assert_that(mult).is_between(0.999, EngineAudio.SHIFT_BLIP_GAIN + 0.001)
		assert_that(mult).is_less_equal(prev)
		prev = mult

func test_lift_pop_envelope_shape() -> void:
	assert_that(EngineAudio.lift_pop(EngineAudio.LIFT_ENV_SECONDS)).is_equal_approx(1.0, 0.001)
	assert_that(EngineAudio.lift_pop(EngineAudio.LIFT_ENV_SECONDS * 0.5)).is_equal_approx(0.5, 0.001)
	assert_that(EngineAudio.lift_pop(0.0)).is_equal_approx(0.0, 0.001)

func test_lift_pop_is_clamped_and_monotonic() -> void:
	assert_that(EngineAudio.lift_pop(EngineAudio.LIFT_ENV_SECONDS * 4.0)).is_equal_approx(1.0, 0.001)
	assert_that(EngineAudio.lift_pop(-0.1)).is_equal_approx(0.0, 0.001)
	assert_that(EngineAudio.lift_pop(0.10)).is_greater(EngineAudio.lift_pop(0.05))

func test_transient_gain_db_is_zero_when_nothing_firing() -> void:
	assert_that(EngineAudio.transient_gain_db(EngineAudio.SHIFT_DURATION, 0.0)).is_equal_approx(0.0, 0.001)

func test_transient_gain_db_positive_on_shift_and_lift() -> void:
	var shift := EngineAudio.transient_gain_db(0.0, 0.0)
	assert_that(shift).is_greater(0.0)
	var lift := EngineAudio.transient_gain_db(EngineAudio.SHIFT_DURATION, EngineAudio.LIFT_ENV_SECONDS)
	assert_that(lift).is_greater(0.0)
	assert_that(lift).is_equal_approx(EngineAudio.LIFT_GAIN_DB, 0.001)

func test_band_gain_db_mutes_to_floor_at_zero_weight() -> void:
	assert_that(EngineAudio.band_gain_db(0.0, 0.0, 0.0)).is_equal_approx(EngineAudio.MUTE_FLOOR_DB, 0.001)
	assert_that(EngineAudio.band_gain_db(0.0, EngineAudio.LOAD_GAIN_DB, 6.0)).is_equal_approx(EngineAudio.MUTE_FLOOR_DB, 0.001)

func test_band_gain_db_ceiling_is_six_db() -> void:
	var hot := EngineAudio.band_gain_db(1.0, EngineAudio.LOAD_GAIN_DB, 20.0)
	assert_that(hot).is_equal_approx(6.0, 0.001)
	assert_that(EngineAudio.band_gain_db(1.0, 100.0, 100.0)).is_equal_approx(6.0, 0.001)

func test_band_gain_db_full_weight_nominal_is_master_trim() -> void:
	var nominal := EngineAudio.band_gain_db(1.0, 0.0, 0.0)
	assert_that(nominal).is_equal_approx(EngineAudio.MASTER_TRIM_DB, 0.001)

func test_band_gain_db_is_monotonic_in_weight() -> void:
	var quiet := EngineAudio.band_gain_db(0.1, 0.0, 0.0)
	var loud := EngineAudio.band_gain_db(0.9, 0.0, 0.0)
	assert_that(loud).is_greater(quiet)