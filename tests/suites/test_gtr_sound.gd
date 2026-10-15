# tests/suites/test_gtr_sound.gd
extends GdUnitTestSuite

## Gate for the Nissan GT-R R35's dedicated "gtr" engine-sound family (VR38DETT
## 3.8L twin-turbo V6). The car's CarConfig used to pin engine_timbre /
## engine_bed_set to the generic V10 "sport" family; it now resolves to the
## dedicated twin-turbo-V6 beds under assets/audio/engine/gtr/ with their own
## band ladder, pitch clamp window, master trim and RPM span. These tests pin
## that wiring and the family geometry; stream resolution additionally needs the
## WAV .import pass (the headless import probe precedes the suite).

const GTR_CFG_PATH := "res://resources/cars/nissan_gt_r35_2017.tres"
const GTR_REDLINE := 7000.0
const GTR_RPM_SPAN := Vector2(800.0, GTR_REDLINE)
const GTR_PITCH_WINDOW := Vector2(0.45, 1.5)
const GTR_TRIM_DB := -2.0
const GTR_LADDER: Array[float] = [800.0, 1800.0, 3200.0, 4800.0, 6800.0]


func test_gtr_config_uses_the_gtr_family() -> void:
	var cfg := load(GTR_CFG_PATH) as CarConfig
	assert_that(cfg).is_not_null()
	assert_that(String(cfg.engine_timbre)).is_equal(EngineAudio.TIMBRE_GTR)
	assert_that(String(cfg.engine_bed_set)).is_equal(EngineAudio.TIMBRE_GTR)
	assert_that(String(cfg.get_engine_bed_set())).is_equal(EngineAudio.TIMBRE_GTR)
	assert_that(EngineAudio.normalize_timbre(EngineAudio.TIMBRE_GTR)).is_equal(EngineAudio.TIMBRE_GTR)
	assert_that(String(EngineAudio.profile_for_timbre(EngineAudio.TIMBRE_GTR)["timbre"])).is_equal(EngineAudio.TIMBRE_GTR)


func test_gtr_is_a_real_family_not_the_sport_fallback() -> void:
	var gtr_files := EngineAudio.bed_files_for_timbre(EngineAudio.TIMBRE_GTR)
	assert_that(String(gtr_files["idle"])).contains("/gtr/")
	assert_that(String(gtr_files["idle"])).is_not_equal(String(EngineAudio.BAND_FILES["idle"]))
	var gtr_ladder := EngineAudio.band_rpms_for_timbre(EngineAudio.TIMBRE_GTR)
	assert_that(gtr_ladder).is_not_equal(EngineAudio.BAND_RPMS)


func test_gtr_bed_ladder_geometry() -> void:
	var ladder := EngineAudio.band_rpms_for_timbre(EngineAudio.TIMBRE_GTR)
	var profile := EngineAudio.profile_for_timbre(EngineAudio.TIMBRE_GTR)
	assert_that(ladder.size()).is_equal(5)
	assert_that(ladder[0]).is_equal_approx(EngineAudio.IDLE_RPM, 0.001)
	var pmin := float(profile["pitch_min"])
	var pmax := float(profile["pitch_max"])
	for i in range(ladder.size()):
		assert_that(ladder[i]).is_equal_approx(GTR_LADDER[i], 0.001)
		assert_that(ladder[i]).is_less_equal(GTR_REDLINE)
		if i > 0:
			assert_that(ladder[i]).is_greater(ladder[i - 1])
	for i in range(ladder.size() - 1):
		var ratio := sqrt(ladder[i + 1] / maxf(ladder[i], 1.0))
		assert_that(ratio).is_less_equal(pmax + 0.001)
		assert_that(1.0 / ratio).is_greater_equal(pmin - 0.001)


func test_gtr_profile_fields() -> void:
	var profile := EngineAudio.profile_for_timbre(EngineAudio.TIMBRE_GTR)
	var pitch_window := EngineAudio.pitch_window_for_timbre(EngineAudio.TIMBRE_GTR)
	assert_that(pitch_window).is_equal(GTR_PITCH_WINDOW)
	assert_that(float(profile["pitch_min"])).is_equal_approx(GTR_PITCH_WINDOW.x, 0.001)
	assert_that(float(profile["pitch_max"])).is_equal_approx(GTR_PITCH_WINDOW.y, 0.001)
	assert_that(float(profile["trim_db"])).is_equal_approx(GTR_TRIM_DB, 0.001)
	var span := EngineAudio.rpm_span_for_timbre(EngineAudio.TIMBRE_GTR)
	assert_that(span).is_equal(GTR_RPM_SPAN)
	assert_that(float(profile["idle_rpm"])).is_equal_approx(GTR_RPM_SPAN.x, 0.001)
	assert_that(float(profile["redline_rpm"])).is_equal_approx(GTR_RPM_SPAN.y, 0.001)


func test_gtr_streams_resolve_and_loop() -> void:
	var beds := EngineAudio.load_beds_for(EngineAudio.bed_files_for_timbre(EngineAudio.TIMBRE_GTR))
	assert_that(beds.size()).is_equal(5)
	for bed: Dictionary in beds:
		var wav := bed["stream"] as AudioStreamWAV
		assert_that(wav).is_not_null()
		assert_that(wav.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
		assert_that(wav.loop_begin).is_equal(0)
		assert_that(wav.loop_end).is_greater(1)
		assert_that(wav.get_length()).is_greater(0.001)
		assert_that(wav.get_length()).is_less(60.0)