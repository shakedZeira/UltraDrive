# tests/suites/test_turbo_audio.gd
extends GdUnitTestSuite

## Turbo audio layer gate (R35 v1): the three gain statics must be mute-floor
## at zero boost and monotonic in boost; the creation gate must be false for
## NA cars and under the headless display server; the gtr turbo WAVs must
## exist and load as AudioStreamWAV; load_turbo_assets() must force the whine
## to a seamless LOOP_FORWARD over the whole file. Fully headless-safe: the
## instance test branches on DisplayServer.get_name().

const WHINE_PATH: String = "res://assets/audio/engine/gtr/turbo_whine.wav"
const BOV_PATH: String = "res://assets/audio/engine/gtr/bov_tail.wav"
const FLUTTER_PATH: String = "res://assets/audio/engine/gtr/flutter_hits.wav"
const TURBO_PATHS: Array[String] = [WHINE_PATH, BOV_PATH, FLUTTER_PATH]

const NA_CONFIG: CarConfig = preload("res://resources/cars/starter_car.tres")

func _turbo_config() -> CarConfig:
	var cfg := CarConfig.new()
	cfg.turbo_max_boost_bar = 1.8
	return cfg

func test_gain_statics_mute_at_zero_boost() -> void:
	assert_that(EngineAudio.turbo_whine_gain_db(0.0, 1.0)).is_equal(EngineAudio.MUTE_FLOOR_DB)
	assert_that(EngineAudio.turbo_whine_gain_db(0.0005, 1.0)).is_equal(EngineAudio.MUTE_FLOOR_DB)
	assert_that(EngineAudio.bov_gain_db(0.0)).is_equal(EngineAudio.MUTE_FLOOR_DB)
	assert_that(EngineAudio.flutter_gain_db(0.0)).is_equal(EngineAudio.MUTE_FLOOR_DB)

func test_gain_statics_are_monotonic_and_capped() -> void:
	var prev_w: float = EngineAudio.MUTE_FLOOR_DB
	var prev_b: float = EngineAudio.MUTE_FLOOR_DB
	var prev_f: float = EngineAudio.MUTE_FLOOR_DB
	for i in range(1, 21):
		var f := float(i) / 20.0
		var w := EngineAudio.turbo_whine_gain_db(f, 1.0)
		var b := EngineAudio.bov_gain_db(f)
		var fl := EngineAudio.flutter_gain_db(f)
		assert_that(w).is_greater_equal(prev_w)
		assert_that(b).is_greater_equal(prev_b)
		assert_that(fl).is_greater_equal(prev_f)
		assert_that(w).is_greater_equal(EngineAudio.MUTE_FLOOR_DB)
		assert_that(w).is_less_equal(6.0)
		assert_that(b).is_greater_equal(EngineAudio.MUTE_FLOOR_DB)
		assert_that(b).is_less_equal(6.0)
		assert_that(fl).is_greater_equal(EngineAudio.MUTE_FLOOR_DB)
		assert_that(fl).is_less_equal(6.0)
		prev_w = w
		prev_b = b
		prev_f = fl

func test_whine_gains_rise_with_rpm_at_fixed_boost() -> void:
	var low_rpm := EngineAudio.turbo_whine_gain_db(1.0, 0.0)
	var mid_rpm := EngineAudio.turbo_whine_gain_db(1.0, 0.5)
	var redline_rpm := EngineAudio.turbo_whine_gain_db(1.0, 1.0)
	assert_that(mid_rpm).is_greater(low_rpm)
	assert_that(redline_rpm).is_greater(mid_rpm)

func test_creation_gate_rejects_na_headless_and_null() -> void:
	var turbo := _turbo_config()
	assert_that(EngineAudio.should_create_turbo_players(NA_CONFIG, "dummy")).is_false()
	assert_that(EngineAudio.should_create_turbo_players(turbo, "headless")).is_false()
	assert_that(EngineAudio.should_create_turbo_players(null, "dummy")).is_false()
	assert_that(EngineAudio.should_create_turbo_players(turbo, "dummy")).is_true()

func test_turbo_wav_files_exist_and_load() -> void:
	for path: String in TURBO_PATHS:
		assert_bool(FileAccess.file_exists(path)).is_true()
		var stream := load(path) as AudioStreamWAV
		assert_that(stream).is_not_null()
		if stream == null:
			continue
		assert_that(stream.get_length()).is_greater(0.02)

func test_turbo_whine_loops_forward_over_whole_file() -> void:
	var streams := EngineAudio.load_turbo_assets()
	var whine := streams.get("whine") as AudioStreamWAV
	assert_that(whine).is_not_null()
	if whine == null:
		return
	assert_that(whine.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_that(whine.loop_begin).is_equal(0)
	assert_that(whine.loop_end).is_greater(1)
	assert_that(whine.get_length()).is_greater(1.0)
	assert_that(whine.get_length()).is_less(60.0)
	var bov := streams.get("bov") as AudioStreamWAV
	assert_that(bov).is_not_null()
	if bov != null:
		assert_that(bov.loop_end).is_equal(0)
	var flutter := streams.get("flutter") as AudioStreamWAV
	assert_that(flutter).is_not_null()
	if flutter != null:
		assert_that(flutter.loop_end).is_equal(0)

func test_headless_instance_creates_no_turbo_players() -> void:
	var car := VehiclePhysics.new()
	car.config = _turbo_config()
	var audio := EngineAudio.new()
	car.add_child(audio)
	audio._create_turbo_players()
	var headless := DisplayServer.get_name() == "headless"
	if headless:
		assert_that(audio._turbo_players.is_empty()).is_true()
		assert_that(audio.get_node_or_null("TurboWhine")).is_null()
	else:
		assert_that(audio._turbo_players.size()).is_equal(3)
	car.free()

func test_na_config_instance_creates_no_turbo_players() -> void:
	var car := VehiclePhysics.new()
	car.config = NA_CONFIG
	var audio := EngineAudio.new()
	car.add_child(audio)
	audio._create_turbo_players()
	assert_that(audio._turbo_players.is_empty()).is_true()
	assert_that(audio.get_node_or_null("TurboWhine")).is_null()
	car.free()
