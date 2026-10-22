# tests/suites/test_turbo_audio.gd
extends GdUnitTestSuite

## Turbo audio layer gate (R35 v1): the three gain statics must be mute-floor
## at zero boost and monotonic in boost; the creation gate must be false for
## NA cars and under the headless display server; the gtr turbo WAVs must
## exist and load as AudioStreamWAV; load_turbo_assets() must force the whine
## to a seamless LOOP_FORWARD over the whole file. Fully headless-safe: the
## instance test branches on DisplayServer.get_name().

const WHINE_PATH: String = "res://assets/audio/engine/gtr/turbo_whine.wav"
const BOV_PATH: String = "res://assets/audio/engine/gtr/bov_0.wav"
const FLUTTER_PATH: String = "res://assets/audio/engine/gtr/flutter_mid_0.wav"
const GTR_DIR: String = "res://assets/audio/engine/gtr/"
const FLUTTER_FILES: Array[String] = [
	"flutter_lo_0.wav", "flutter_lo_1.wav", "flutter_mid_0.wav",
	"flutter_mid_1.wav", "flutter_hi_0.wav", "flutter_hi_1.wav",
]
const BOV_FILES: Array[String] = ["bov_0.wav", "bov_1.wav"]
const TURBO_PATHS: Array[String] = [
	WHINE_PATH, BOV_PATH, FLUTTER_PATH,
	GTR_DIR + "flutter_lo_0.wav", GTR_DIR + "flutter_lo_1.wav",
	GTR_DIR + "flutter_mid_1.wav", GTR_DIR + "flutter_hi_0.wav",
	GTR_DIR + "flutter_hi_1.wav", GTR_DIR + "bov_1.wav",
]

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


## --- Smoothed boost state (turbo wobble fix) ---------------------------------

func test_boost_step_bridges_upshift_dip_while_on_throttle() -> void:
	# Drivetrain dips the raw boost to ~15% for a shift while the driver stays
	# flat out; the audio boost must hold, not follow the dip.
	var state := 0.9
	for i in range(15):   # 0.25 s at 60 Hz
		state = EngineAudio.turbo_boost_step(state, 0.135, 1.0, 1.0 / 60.0)
	assert_that(state).is_greater(0.85)


func test_boost_step_spools_down_when_driver_lifts() -> void:
	var state := 0.9
	for i in range(24):   # 0.4 s
		state = EngineAudio.turbo_boost_step(state, 0.0, 0.0, 1.0 / 60.0)
	assert_that(state).is_less(0.5)
	for i in range(60):
		state = EngineAudio.turbo_boost_step(state, 0.0, 0.0, 1.0 / 60.0)
	assert_that(state).is_less(0.01)


func test_boost_step_spool_up_is_rate_limited_and_bounded() -> void:
	var state := 0.0
	var dt := 1.0 / 60.0
	for i in range(120):
		var nxt := EngineAudio.turbo_boost_step(state, 1.0, 1.0, dt)
		assert_that(nxt - state).is_less_equal(EngineAudio.TURBO_SPOOL_UP_RATE * dt + 0.00001)
		assert_that(nxt).is_between(0.0, 1.0)
		state = nxt
	assert_that(state).is_greater(0.99)


func test_steady_acceleration_gives_stable_whistle() -> void:
	# 8 s flat out; the raw boost saws (shift dip every 1.5 s) and rpm_norm saws
	# with the gears. After the initial spool the smoothed state, the whistle
	# gain and pitch must stay within a narrow window.
	var dt := 1.0 / 60.0
	var state := 0.0
	var rpm_slow := 0.0
	var gains: Array[float] = []
	var pitches: Array[float] = []
	for i in range(480):
		var t := float(i) * dt
		var in_shift := fmod(t, 1.5) > 1.25
		var raw := 0.135 if in_shift else 0.9
		var rpm_norm := 0.45 + 0.5 * fmod(t, 1.5) / 1.5
		state = EngineAudio.turbo_boost_step(state, raw, 1.0, dt)
		rpm_slow = lerpf(rpm_slow, rpm_norm, 1.0 - exp(-dt / EngineAudio.TURBO_RPM_SLOW_TAU))
		if t > 3.0:
			gains.append(EngineAudio.turbo_whine_gain_db(state, rpm_slow))
			pitches.append(EngineAudio.turbo_whine_pitch(state, rpm_slow))
	var g_range: float = float(gains.max()) - float(gains.min())
	var p_range: float = float(pitches.max()) - float(pitches.min())
	assert_that(g_range).is_less(1.5)      # dB
	assert_that(p_range).is_less(0.03)     # pitch_scale


func test_whistle_pitch_bounded_and_rises_gently_with_load() -> void:
	assert_that(EngineAudio.turbo_whine_pitch(0.0, 0.0)).is_equal_approx(EngineAudio.TURBO_PITCH_MIN, 0.0001)
	assert_that(EngineAudio.turbo_whine_pitch(1.0, 1.0)).is_equal_approx(EngineAudio.TURBO_PITCH_MAX, 0.0001)
	assert_that(EngineAudio.turbo_whine_pitch(0.5, 0.5)).is_greater(EngineAudio.turbo_whine_pitch(0.2, 0.5))
	assert_that(EngineAudio.TURBO_PITCH_MAX - EngineAudio.TURBO_PITCH_MIN).is_less(0.2)


func test_ema_linear_is_frame_rate_independent() -> void:
	var one := EngineAudio.ema_linear(0.0, 1.0, 0.032, 0.12)
	var two := EngineAudio.ema_linear(EngineAudio.ema_linear(0.0, 1.0, 0.016, 0.12), 1.0, 0.016, 0.12)
	assert_that(one).is_equal_approx(two, 0.0001)


## --- Flutter / blow-off variants (docs/research/turbo_flutter_sound.md) -------

func test_flutter_tier_boundaries_and_monotonic() -> void:
	assert_that(EngineAudio.flutter_tier(0.0)).is_equal(0)
	assert_that(EngineAudio.flutter_tier(0.649)).is_equal(0)
	assert_that(EngineAudio.flutter_tier(0.65)).is_equal(1)
	assert_that(EngineAudio.flutter_tier(0.849)).is_equal(1)
	assert_that(EngineAudio.flutter_tier(0.85)).is_equal(2)
	assert_that(EngineAudio.flutter_tier(1.0)).is_equal(2)
	var prev := 0
	for i in range(101):
		var t := EngineAudio.flutter_tier(float(i) / 100.0)
		assert_that(t).is_greater_equal(prev)
		prev = t


func test_pick_variant_never_repeats_and_stays_in_range() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for count in [2, 3]:
		var last := -1
		for i in range(200):
			var idx := EngineAudio.pick_variant(count, last, rng.randf())
			assert_that(idx).is_greater_equal(0)
			assert_that(idx).is_less(count)
			if last >= 0:
				assert_that(idx).is_not_equal(last)
			last = idx
	assert_that(EngineAudio.pick_variant(1, 0, 0.7)).is_equal(0)
	assert_that(EngineAudio.pick_variant(2, -1, 1.0)).is_less(2)


func test_flutter_pitch_scale_bounds_and_monotonic_mean() -> void:
	for i in range(11):
		var boost := float(i) / 10.0
		for r in [0.0, 0.5, 1.0]:
			var ps := EngineAudio.flutter_pitch_scale(boost, r)
			assert_that(ps).is_greater_equal(0.89)
			assert_that(ps).is_less_equal(1.115)   # 1.08 * 1.03 = 1.1124
	assert_that(EngineAudio.flutter_pitch_scale(0.0, 0.5)).is_equal_approx(0.92, 0.0001)
	assert_that(EngineAudio.flutter_pitch_scale(1.0, 0.5)).is_equal_approx(1.08, 0.0001)
	var prev := 0.0
	for i in range(11):
		var ps := EngineAudio.flutter_pitch_scale(float(i) / 10.0, 0.5)
		assert_that(ps).is_greater(prev)
		prev = ps
	# Per-event jitter: different draws give different rates at the same boost.
	assert_that(EngineAudio.flutter_pitch_scale(0.7, 0.0)).is_less(EngineAudio.flutter_pitch_scale(0.7, 1.0))


func test_flutter_should_fire_truth_table() -> void:
	# Clean lift with built boost, no cooldown, wastegate fitted -> fires.
	assert_bool(EngineAudio.flutter_should_fire(1.0, 0.0, 0.9, 0.0, true)).is_true()
	# Cooldown running (mid-flutter) -> never retriggers.
	assert_bool(EngineAudio.flutter_should_fire(1.0, 0.0, 0.9, 0.5, true)).is_false()
	# Below the minimum boost -> silent.
	assert_bool(EngineAudio.flutter_should_fire(1.0, 0.0, 0.2, 0.0, true)).is_false()
	# No wastegate -> no flutter.
	assert_bool(EngineAudio.flutter_should_fire(1.0, 0.0, 0.9, 0.0, false)).is_false()
	# Throttle only dips to 0.3 (never reaches the lift threshold) -> no.
	assert_bool(EngineAudio.flutter_should_fire(1.0, 0.3, 0.9, 0.0, true)).is_false()
	# Already off the gas (no edge) -> no.
	assert_bool(EngineAudio.flutter_should_fire(0.0, 0.0, 0.9, 0.0, true)).is_false()
	# Analog fast lift that skips the 0.5 -> 0.15 frame pair: peak 1.0, now 0.18.
	assert_bool(EngineAudio.flutter_should_fire(0.4, 0.18, 0.9, 0.0, true, 1.0)).is_true()
	# A slow lift (small drop from the peak) does not count.
	assert_bool(EngineAudio.flutter_should_fire(0.4, 0.18, 0.9, 0.0, true, 0.5)).is_false()
	# BOV uses the same edge but ignores the wastegate.
	assert_bool(EngineAudio.bov_should_fire(1.0, 0.0, 0.9, 0.0)).is_true()
	assert_bool(EngineAudio.bov_should_fire(1.0, 0.0, 0.9, 0.5)).is_false()
	assert_bool(EngineAudio.bov_should_fire(1.0, 0.0, 0.1, 0.0)).is_false()


func test_load_flutter_variants_shape_and_lengths() -> void:
	var v := EngineAudio.load_flutter_variants()
	var tiers: Array = v.get("flutter", [])
	var bovs: Array = v.get("bov", [])
	assert_that(tiers.size()).is_equal(3)
	assert_that(bovs.size()).is_equal(2)
	var prev_mean := 0.0
	for tier in range(3):
		var pool: Array = tiers[tier]
		assert_that(pool.size()).is_equal(2)
		var total := 0.0
		for stream in pool:
			var wav := stream as AudioStreamWAV
			assert_that(wav).is_not_null()
			assert_that(wav.loop_mode).is_equal(AudioStreamWAV.LOOP_DISABLED)
			assert_that(wav.loop_end).is_equal(0)
			assert_that(wav.get_length()).is_greater(0.3)
			assert_that(wav.get_length()).is_less(1.5)
			total += wav.get_length()
		var mean := total / 2.0
		assert_that(mean).is_greater(prev_mean)   # lengths ascend by tier
		prev_mean = mean
	for stream in bovs:
		var wav := stream as AudioStreamWAV
		assert_that(wav).is_not_null()
		assert_that(wav.loop_mode).is_equal(AudioStreamWAV.LOOP_DISABLED)
		assert_that(wav.loop_end).is_equal(0)
		assert_that(wav.get_length()).is_greater(0.15)
		assert_that(wav.get_length()).is_less(0.5)


func test_flutter_trim_and_constants_match_plan() -> void:
	assert_that(EngineAudio.TURBO_FLUTTER_TRIM_DB).is_equal_approx(0.3, 0.0001)
	assert_that(EngineAudio.TURBO_FLUTTER_COOLDOWN_S).is_greater_equal(1.3)
	assert_that(EngineAudio.TURBO_FLUTTER_VARIANTS.size()).is_equal(3)
	assert_that(EngineAudio.TURBO_BOV_VARIANTS.size()).is_equal(2)
	for name in FLUTTER_FILES + BOV_FILES:
		assert_bool(FileAccess.file_exists(GTR_DIR + name)).is_true()
