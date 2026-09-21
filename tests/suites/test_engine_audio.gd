# tests/suites/test_engine_audio.gd
extends GdUnitTestSuite

## Deterministic coverage for EngineAudio's real-sample bed ladder (the V10
## simulated by enginesound -- see LICENSES.md): bed loading/looping, the pure
## equal-power RPM crossfade, Curve resources that reproduce it, load shaping,
## and a scene-free node probe. All static calls + one auto_freed node; no
## AudioServer. REMOVED from the pre-rewrite suite by design: pitch sweep
## (_pitch_for / BASE_PITCH / REDLINE_PITCH), the 4-bed BED_* mapping and the
## wot one-shot clip -- bands are authored at their exact RPM, so nothing is
## ever pitch-shifted and every bed loops.

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