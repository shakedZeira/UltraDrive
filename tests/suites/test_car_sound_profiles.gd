# tests/suites/test_car_sound_profiles.gd
extends GdUnitTestSuite

## Gate for the per-timbre engine sound families (see
## assets/audio/engine/LICENSES.md): the shipped V10 "sport" beds are joined by
## a big-bore V8 ("muscle") and a high-rev turbo-4 ("rally"), each with its own
## five-loop real-bed ladder, pitch clamp window, master trim and RPM span.
## Per-car selection rides on CarConfig.engine_bed_set (falling back to
## engine_timbre, then sport). Sport must remain EXACTLY today's V10 behaviour:
## every parametrized helper (band_pitch_scale_window, normalized_centers_for,
## build_curves_for, load_beds_for, profile_for_timbre) is asserted to agree
## with the pre-existing static on the sport ladder. All pure statics plus
## config loads; loop resolution needs the WAV .import pass to have run (the
## headless import probe precedes the suite).

const CAR_EXPECTED := {
	"res://resources/cars/muscle_car.tres": "muscle",
	"res://resources/cars/rally_hatch.tres": "rally",
	"res://resources/cars/cc0_sedan_sports.tres": "sport",
	"res://resources/cars/cc0_race.tres": "sport",
	"res://resources/cars/cc0_hatchback_sports.tres": "rally",
}

const FAMILIES: Array[String] = [
	EngineAudio.TIMBRE_SPORT,
	EngineAudio.TIMBRE_MUSCLE,
	EngineAudio.TIMBRE_RALLY,
]

## --- Timbre resolution ---

func test_normalize_timbre_maps_every_unknown_to_sport() -> void:
	assert_that(EngineAudio.normalize_timbre("")).is_equal(EngineAudio.TIMBRE_SPORT)
	assert_that(EngineAudio.normalize_timbre("v10")).is_equal(EngineAudio.TIMBRE_SPORT)
	assert_that(EngineAudio.normalize_timbre("racing")).is_equal(EngineAudio.TIMBRE_SPORT)
	for family: String in FAMILIES:
		assert_that(EngineAudio.normalize_timbre(family)).is_equal(family)

func test_unknown_timbre_falls_back_to_sport_files_and_ladder() -> void:
	assert_that(EngineAudio.bed_files_for_timbre("nope")).is_equal(EngineAudio.BAND_FILES)
	var ladder := EngineAudio.band_rpms_for_timbre("nope")
	assert_that(ladder.size()).is_equal(5)
	for i in range(EngineAudio.BAND_RPMS.size()):
		assert_that(ladder[i]).is_equal_approx(EngineAudio.BAND_RPMS[i], 0.001)

func test_bed_files_for_timbre_point_into_dedicated_subdirs() -> void:
	var muscle := EngineAudio.bed_files_for_timbre(EngineAudio.TIMBRE_MUSCLE)
	var rally := EngineAudio.bed_files_for_timbre(EngineAudio.TIMBRE_RALLY)
	var sport := EngineAudio.bed_files_for_timbre(EngineAudio.TIMBRE_SPORT)
	for name: String in EngineAudio.BAND_ORDER:
		assert_that(String(muscle[name])).contains("/muscle/")
		assert_that(String(muscle[name])).ends_with("engine_%s.wav" % name)
		assert_that(String(rally[name])).contains("/rally/")
		assert_that(String(rally[name])).ends_with("engine_%s.wav" % name)
		assert_that(String(sport[name])).is_equal(String(EngineAudio.BAND_FILES[name]))

## --- Bed ladders ---

func test_family_ladders_are_five_strictly_increasing_rungs_from_idle() -> void:
	for family: String in FAMILIES:
		var rpms := EngineAudio.band_rpms_for_timbre(family)
		assert_that(rpms.size()).is_equal(5)
		assert_that(rpms[0]).is_equal_approx(EngineAudio.IDLE_RPM, 0.001)
		for i in range(1, rpms.size()):
			assert_that(rpms[i]).is_greater(rpms[i - 1])

func test_family_ladders_are_pairwise_distinct() -> void:
	var sport := EngineAudio.band_rpms_for_timbre(EngineAudio.TIMBRE_SPORT)
	var muscle := EngineAudio.band_rpms_for_timbre(EngineAudio.TIMBRE_MUSCLE)
	var rally := EngineAudio.band_rpms_for_timbre(EngineAudio.TIMBRE_RALLY)
	assert_that(muscle).is_not_equal(sport)
	assert_that(rally).is_not_equal(sport)
	assert_that(rally).is_not_equal(muscle)

func test_rally_redline_outranks_sport_which_outranks_muscle() -> void:
	var rally := EngineAudio.band_rpms_for_timbre(EngineAudio.TIMBRE_RALLY)
	var sport := EngineAudio.band_rpms_for_timbre(EngineAudio.TIMBRE_SPORT)
	var muscle := EngineAudio.band_rpms_for_timbre(EngineAudio.TIMBRE_MUSCLE)
	assert_that(rally[4]).is_greater(sport[4])
	assert_that(sport[4]).is_greater(muscle[4])

func test_band_rpms_are_fresh_copies() -> void:
	var a := EngineAudio.band_rpms_for_timbre(EngineAudio.TIMBRE_MUSCLE)
	var b := EngineAudio.band_rpms_for_timbre(EngineAudio.TIMBRE_MUSCLE)
	a[0] = 999.0
	assert_that(b[0]).is_equal_approx(EngineAudio.BAND_RPMS_MUSCLE[0], 0.001)

## --- Pitch windows & trims ---

func test_pitch_windows_are_sane_and_pairwise_distinct() -> void:
	var seen: Array[Vector2] = []
	for family: String in FAMILIES:
		var pitch_window := EngineAudio.pitch_window_for_timbre(family)
		assert_that(pitch_window.x).is_greater(0.0)
		assert_that(pitch_window.x).is_less(1.0)
		assert_that(pitch_window.y).is_greater(1.0)
		assert_that(pitch_window.y).is_less(3.0)
		assert_that(pitch_window.x).is_less(pitch_window.y)
		for prev: Vector2 in seen:
			assert_that(pitch_window).is_not_equal(prev)
		seen.append(pitch_window)

func test_master_trims_are_small_and_sport_is_neutral() -> void:
	assert_that(EngineAudio.master_trim_db_for_timbre(EngineAudio.TIMBRE_SPORT)).is_equal_approx(0.0, 0.001)
	assert_that(EngineAudio.master_trim_db_for_timbre(EngineAudio.TIMBRE_MUSCLE)).is_greater(0.0)
	assert_that(EngineAudio.master_trim_db_for_timbre(EngineAudio.TIMBRE_RALLY)).is_less(0.0)
	for family: String in FAMILIES:
		assert_that(absf(EngineAudio.master_trim_db_for_timbre(family))).is_less_equal(6.0)

func test_ladder_handoff_midpoints_stay_inside_pitch_window() -> void:
	## Continuous hand-off precondition: at every segment midpoint both active
	## neighbours are inside the family's pitch clamp window, so the equal-power
	## crossfade never hits a clamp gap.
	for family: String in FAMILIES:
		var profile := EngineAudio.profile_for_timbre(family)
		var rpms: Array[float] = profile["band_rpms"] as Array[float]
		var pmin := float(profile["pitch_min"])
		var pmax := float(profile["pitch_max"])
		for i in range(rpms.size() - 1):
			var ratio := sqrt(rpms[i + 1] / maxf(rpms[i], 1.0))
			assert_that(ratio).is_less_equal(pmax + 0.001)
			assert_that(1.0 / ratio).is_greater_equal(pmin - 0.001)

## --- Sport must stay byte-for-byte the shipped V10 behaviour ---

func test_band_pitch_scale_delegates_to_window_with_sport_clamps() -> void:
	for live: float in [100.0, 800.0, 1500.0, 2750.0, 4000.0, 6200.0, 9000.0]:
		for band: float in [800.0, 2000.0, 3500.0, 5500.0, 6900.0]:
			assert_that(EngineAudio.band_pitch_scale(live, band)).is_equal_approx(
				EngineAudio.band_pitch_scale_window(live, band, EngineAudio.PITCH_MIN, EngineAudio.PITCH_MAX), 0.0001)

func test_band_pitch_scale_window_respects_custom_clamps() -> void:
	assert_that(EngineAudio.band_pitch_scale_window(6900.0, 800.0, 0.55, 1.6)).is_equal_approx(1.6, 0.001)
	assert_that(EngineAudio.band_pitch_scale_window(800.0, 6900.0, 0.45, 1.9)).is_equal_approx(0.45, 0.001)
	assert_that(EngineAudio.band_pitch_scale_window(4400.0, 5500.0, 0.45, 1.9)).is_equal_approx(0.8, 0.001)

func test_normalized_centers_for_sport_matches_ship_function() -> void:
	var ship := EngineAudio.normalized_centers()
	var via_for := EngineAudio.normalized_centers_for(EngineAudio.BAND_RPMS, EngineAudio.IDLE_RPM, EngineAudio.REDLINE_RPM)
	assert_that(via_for.size()).is_equal(ship.size())
	for i in range(ship.size()):
		assert_that(via_for[i]).is_equal_approx(ship[i], 0.0001)

func test_sport_default_curves_are_exactly_the_build_curves_for_defaults() -> void:
	var defaults := EngineAudio.build_default_curves()
	var via_profile := EngineAudio.build_curves_for(EngineAudio.BAND_RPMS, EngineAudio.IDLE_RPM, EngineAudio.REDLINE_RPM)
	for i in range(21):
		var t := float(i) / 20.0
		var a := EngineAudio.sample_curves(defaults, t)
		var b := EngineAudio.sample_curves(via_profile, t)
		for j in range(a.size()):
			assert_that(a[j]).is_equal_approx(b[j], 0.0001)

func test_load_beds_sport_family_matches_the_ship_loader() -> void:
	var ship := EngineAudio.load_beds()
	var family := EngineAudio.load_beds_for(EngineAudio.bed_files_for_timbre(EngineAudio.TIMBRE_SPORT))
	assert_that(family.size()).is_equal(ship.size())
	for i in range(ship.size()):
		assert_that(String(family[i]["name"])).is_equal(String(ship[i]["name"]))
		assert_that(String(family[i]["path"])).is_equal(String(ship[i]["path"]))
		var fwav := family[i]["stream"] as AudioStreamWAV
		var swav := ship[i]["stream"] as AudioStreamWAV
		assert_that(fwav).is_not_null()
		assert_that(swav).is_not_null()
		assert_that(fwav.mix_rate).is_equal(swav.mix_rate)
		assert_that(fwav.get_length()).is_equal_approx(swav.get_length(), 0.001)

## --- Curve reproduction for every family ---

func test_build_curves_for_reproduces_band_weights_for_each_family() -> void:
	for family: String in FAMILIES:
		var profile := EngineAudio.profile_for_timbre(family)
		var rpms: Array[float] = profile["band_rpms"] as Array[float]
		var idle := float(profile["idle_rpm"])
		var redline := float(profile["redline_rpm"])
		var centers := EngineAudio.normalized_centers_for(rpms, idle, redline)
		var curves := EngineAudio.build_curves_for(rpms, idle, redline)
		for i in range(21):
			var t := float(i) / 20.0
			var sampled := EngineAudio.sample_curves(curves, t)
			var analytic := EngineAudio.band_weights(t, centers)
			for j in range(sampled.size()):
				assert_that(sampled[j]).is_equal_approx(analytic[j], 0.02)

func test_family_normalized_centers_are_monotonic_inside_unit_range() -> void:
	for family: String in FAMILIES:
		var profile := EngineAudio.profile_for_timbre(family)
		var rpms: Array[float] = profile["band_rpms"] as Array[float]
		var centers := EngineAudio.normalized_centers_for(rpms, float(profile["idle_rpm"]), float(profile["redline_rpm"]))
		assert_that(centers.size()).is_equal(5)
		assert_that(centers[0]).is_between(0.0, 0.01)
		assert_that(centers[4]).is_between(0.9, 1.0)
		for i in range(centers.size()):
			assert_that(centers[i]).is_between(0.0, 1.0)
			if i > 0:
				assert_that(centers[i]).is_greater(centers[i - 1])

## --- Profile aggregation ---

func test_profile_dict_agrees_with_its_individual_parts() -> void:
	for family: String in FAMILIES:
		var profile := EngineAudio.profile_for_timbre(family)
		var family_norm := EngineAudio.normalize_timbre(family)
		assert_that(String(profile["timbre"])).is_equal(family_norm)
		var pitch_window: Vector2 = EngineAudio.pitch_window_for_timbre(family_norm)
		assert_that(float(profile["pitch_min"])).is_equal_approx(pitch_window.x, 0.001)
		assert_that(float(profile["pitch_max"])).is_equal_approx(pitch_window.y, 0.001)
		var span: Vector2 = EngineAudio.rpm_span_for_timbre(family_norm)
		assert_that(float(profile["idle_rpm"])).is_equal_approx(span.x, 0.001)
		assert_that(float(profile["redline_rpm"])).is_equal_approx(span.y, 0.001)
		assert_that(float(profile["trim_db"])).is_equal_approx(EngineAudio.master_trim_db_for_timbre(family_norm), 0.001)
		var rpms := EngineAudio.band_rpms_for_timbre(family_norm)
		var from_profile: Array[float] = profile["band_rpms"] as Array[float]
		assert_that(from_profile.size()).is_equal(rpms.size())
		for i in range(rpms.size()):
			assert_that(from_profile[i]).is_equal_approx(rpms[i], 0.001)

## --- Real streams resolve for every family (needs the WAV import pass) ---

func test_all_family_streams_resolve_and_loop() -> void:
	for family: String in FAMILIES:
		var beds := EngineAudio.load_beds_for(EngineAudio.bed_files_for_timbre(family))
		assert_that(beds.size()).is_equal(5)
		for bed: Dictionary in beds:
			var wav := bed["stream"] as AudioStreamWAV
			assert_that(wav).is_not_null()
			assert_that(wav.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
			assert_that(wav.loop_begin).is_equal(0)
			assert_that(wav.loop_end).is_greater(1)
			assert_that(wav.get_length()).is_greater(0.001)
			assert_that(wav.get_length()).is_less(60.0)

## --- Per-car config mapping ---

func test_car_configs_pin_their_bed_family() -> void:
	for path: String in CAR_EXPECTED:
		var expected := String(CAR_EXPECTED[path])
		var cfg := load(path) as CarConfig
		assert_that(cfg).is_not_null()
		assert_that(String(cfg.engine_bed_set)).is_equal(expected)
		assert_that(String(cfg.engine_timbre)).is_equal(expected)
		assert_that(String(cfg.get_engine_bed_set())).is_equal(expected)
		var profile := EngineAudio.profile_for_timbre(expected)
		assert_that(String(profile["timbre"])).is_equal(expected)
		var idle_path := String((profile["band_files"] as Dictionary)["idle"])
		if expected == EngineAudio.TIMBRE_MUSCLE:
			assert_that(idle_path).contains("/muscle/")
		elif expected == EngineAudio.TIMBRE_RALLY:
			assert_that(idle_path).contains("/rally/")
		else:
			assert_that(idle_path).is_equal(String(EngineAudio.BAND_FILES["idle"]))