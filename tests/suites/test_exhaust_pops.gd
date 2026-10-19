# tests/suites/test_exhaust_pops.gd
extends GdUnitTestSuite

## Exhaust overrun ("pops & bangs") gate: the pure, deterministic core of the
## new layer. Every assertion is on seed-pinned synthesis or pure statics --
## NO wall-clock assertions anywhere (see docs/plans/pops_and_bangs_exhaust.md §6).
## Fully headless-safe: the instance tests branch on DisplayServer.get_name().

const NA_CONFIG: CarConfig = preload("res://resources/cars/starter_car.tres")
const R35_CONFIG: CarConfig = preload("res://resources/cars/nissan_gt_r35_2017.tres")
const RALLY_CONFIG: CarConfig = preload("res://resources/cars/rally_hatch.tres")

func _pop_config() -> CarConfig:
	var cfg := CarConfig.new()
	cfg.exhaust_pop_enabled = true
	cfg.exhaust_pop_style = "crackle"
	return cfg


## Peak absolute sample of a 16-bit mono WAV (decoded from its byte payload).
func _peak_of(stream: AudioStreamWAV) -> float:
	var peak := 0.0
	var data: PackedByteArray = stream.data
	var count := data.size() / 2
	for i in range(count):
		peak = maxf(peak, absf(float(data.decode_s16(i * 2)) / 32767.0))
	return peak


func test_config_defaults_are_off_and_neutral() -> void:
	var cfg := CarConfig.new()
	assert_that(cfg.exhaust_pop_enabled).is_false()
	assert_that(cfg.exhaust_pop_style).is_equal("crackle")
	assert_that(cfg.exhaust_pop_intensity).is_equal(1.0)
	assert_that(cfg.exhaust_pop_min_rpm_fraction).is_equal(0.40)
	assert_that(cfg.exhaust_pop_duration).is_equal(0.9)
	assert_that(cfg.exhaust_pop_gain_db).is_equal(-6.0)
	# Regression lock (criterion 7): the starter car stays opted out.
	assert_that(NA_CONFIG.exhaust_pop_enabled).is_false()


func test_overrun_trigger_truth_table() -> void:
	# Fires only for enabled AND the lift edge AND revs at/above the floor AND
	# not reverse AND no active cooldown.
	assert_that(EngineAudio.overrun_should_fire(0.6, 0.0, 0.8, 3, true, 0.40, 0.0)).is_true()
	assert_that(EngineAudio.overrun_should_fire(0.6, 0.0, 0.8, 3, false, 0.40, 0.0)).is_false()
	assert_that(EngineAudio.overrun_should_fire(0.6, 0.0, 0.2, 3, true, 0.40, 0.0)).is_false()
	assert_that(EngineAudio.overrun_should_fire(0.2, 0.1, 0.8, 3, true, 0.40, 0.0)).is_false()
	assert_that(EngineAudio.overrun_should_fire(0.6, 0.0, 0.8, -1, true, 0.40, 0.0)).is_false()
	assert_that(EngineAudio.overrun_should_fire(0.6, 0.0, 0.8, 3, true, 0.40, 0.15)).is_false()


func test_pop_burst_is_deterministic_for_a_seed() -> void:
	var a := EngineAudio.build_pop_burst("crackle", 0.9, 1.0, 22050, 42)
	var b := EngineAudio.build_pop_burst("crackle", 0.9, 1.0, 22050, 42)
	assert_that(a).is_not_null()
	assert_that(b).is_not_null()
	assert_bool(a.data == b.data).is_true()
	assert_that(a.get_length()).is_equal(b.get_length())
	assert_that(a.format).is_equal(AudioStreamWAV.FORMAT_16_BITS)
	assert_that(a.stereo).is_false()
	assert_that(a.loop_mode).is_equal(AudioStreamWAV.LOOP_DISABLED)


func test_pop_burst_varies_with_seed_and_style() -> void:
	var s42 := EngineAudio.build_pop_burst("crackle", 0.9, 1.0, 22050, 42)
	var s43 := EngineAudio.build_pop_burst("crackle", 0.9, 1.0, 22050, 43)
	assert_bool(s42.data != s43.data).is_true()
	var burble := EngineAudio.build_pop_burst("burble", 0.9, 1.0, 22050, 42)
	var crackle := EngineAudio.build_pop_burst("crackle", 0.9, 1.0, 22050, 42)
	var bang := EngineAudio.build_pop_burst("bang", 0.9, 1.0, 22050, 42)
	assert_bool(burble.data != crackle.data).is_true()
	assert_bool(crackle.data != bang.data).is_true()
	assert_bool(burble.data != bang.data).is_true()


func test_pop_count_and_level_track_intensity() -> void:
	var prev := 0
	for i in range(0, 21):
		var amt := float(i) / 10.0
		var count := EngineAudio.pop_count_for("crackle", amt)
		assert_that(count).is_greater_equal(prev)
		assert_that(count).is_greater_equal(0)
		assert_that(count).is_less_equal(24)
		prev = count
	assert_that(EngineAudio.pop_count_for("crackle", 0.0)).is_equal(0)
	var silent := EngineAudio.build_pop_burst("crackle", 0.9, 0.0, 22050, 42)
	assert_that(_peak_of(silent)).is_equal(0.0)
	var prev_peak := -1.0
	for i in range(1, 5):
		var amt := float(i) / 2.0
		var peak := _peak_of(EngineAudio.build_pop_burst("crackle", 0.9, amt, 22050, 42))
		# +1 ulp of 16-bit quantization: the builder targets 0.95, the s16
		# round-trip can decode a hair above it (never clipping territory).
		assert_that(peak).is_less_equal(0.95 + 1.0 / 32767.0)
		assert_that(peak).is_greater_equal(prev_peak)
		prev_peak = peak


func test_pop_duration_is_bounded() -> void:
	assert_that(EngineAudio.pop_duration_for("crackle", 0.001)).is_equal(0.1)
	assert_that(EngineAudio.pop_duration_for("crackle", 99.0)).is_equal(3.0)
	for style: String in EngineAudio.POP_STYLES:
		var dur := EngineAudio.pop_duration_for(style, 0.9)
		var burst := EngineAudio.build_pop_burst(style, 0.9, 1.0, 22050, 7)
		assert_that(burst.get_length()).is_greater(dur - 0.05)
		assert_that(burst.get_length()).is_less(dur + 0.05)


func test_creation_gate_rejects_disabled_na_and_headless() -> void:
	var enabled := _pop_config()
	assert_that(EngineAudio.should_create_pop_players(null, "dummy")).is_false()
	assert_that(EngineAudio.should_create_pop_players(NA_CONFIG, "dummy")).is_false()
	assert_that(EngineAudio.should_create_pop_players(enabled, "headless")).is_false()
	assert_that(EngineAudio.should_create_pop_players(enabled, "dummy")).is_true()


func test_headless_instance_creates_no_pop_player() -> void:
	var car := VehiclePhysics.new()
	car.config = _pop_config()
	var audio := EngineAudio.new()
	car.add_child(audio)
	audio._ensure_pop_layer(car.config)
	if DisplayServer.get_name() == "headless":
		assert_that(audio._pop_player).is_null()
		assert_that(audio.get_node_or_null("ExhaustPop")).is_null()
	else:
		assert_that(audio._pop_player).is_not_null()
	car.free()


func test_enabled_instance_creates_pop_player() -> void:
	var car := VehiclePhysics.new()
	car.config = _pop_config()
	var audio := EngineAudio.new()
	car.add_child(audio)
	audio._ensure_pop_layer(car.config)
	if DisplayServer.get_name() == "headless":
		assert_that(audio._pop_player).is_null()
	else:
		assert_that(audio._pop_player).is_not_null()
		var node := audio.get_node_or_null("ExhaustPop")
		assert_that(node).is_not_null()
		assert_that(node is AudioStreamPlayer3D).is_true()
	car.free()


func test_overrun_fires_one_shot_on_lift_edge() -> void:
	var cfg := _pop_config()
	var car := VehiclePhysics.new()
	car.config = cfg
	var audio := EngineAudio.new()
	car.add_child(audio)
	audio._ensure_pop_layer(cfg)
	var headless := DisplayServer.get_name() == "headless"
	# Lift edge fires exactly one burst and arms the cooldown.
	audio._prev_throttle = 0.6
	audio._update_overrun(cfg, 0.8, 0.0, 3, 0.016)
	if headless:
		assert_that(audio._pop_player).is_null()
	else:
		assert_that(audio._pop_player.is_playing()).is_true()
	assert_that(audio._pop_cooldown).is_equal(EngineAudio.POP_COOLDOWN_SECONDS)
	# Steady throttle does not fire and only decays the cooldown.
	audio._prev_throttle = 0.8
	audio._update_overrun(cfg, 0.8, 0.8, 3, 0.016)
	var before := audio._pop_cooldown
	assert_that(before).is_less(EngineAudio.POP_COOLDOWN_SECONDS)
	# A second lift inside the cooldown must NOT re-arm it.
	audio._prev_throttle = 0.6
	audio._update_overrun(cfg, 0.8, 0.0, 3, 0.01)
	assert_that(audio._pop_cooldown).is_less(before)
	# Once the cooldown expires, a lift fires again.
	audio._prev_throttle = 0.6
	audio._update_overrun(cfg, 0.8, 0.0, 3, 1.0)
	assert_that(audio._pop_cooldown).is_equal(EngineAudio.POP_COOLDOWN_SECONDS)
	car.free()


func test_cars_without_the_flag_are_unaffected() -> void:
	var car := VehiclePhysics.new()
	car.config = NA_CONFIG
	var audio := EngineAudio.new()
	car.add_child(audio)
	audio._ensure_pop_layer(car.config)
	assert_that(audio._pop_player).is_null()
	assert_that(audio.get_node_or_null("ExhaustPop")).is_null()
	car.free()


func test_r35_config_enables_crackle() -> void:
	assert_that(R35_CONFIG.exhaust_pop_enabled).is_true()
	assert_that(R35_CONFIG.exhaust_pop_style).is_equal("crackle")
	assert_that(R35_CONFIG.exhaust_pop_gain_db).is_equal(-6.0)


## Rollout decision (2026-10-20): the rally hatch is the second car opted in,
## with the anti-lag "bang" character to match its rally timbre. It ships no
## turbo flags, so the layer does not share the lift edge with a flutter burst.
func test_rally_config_enables_bang() -> void:
	assert_that(RALLY_CONFIG.exhaust_pop_enabled).is_true()
	assert_that(RALLY_CONFIG.exhaust_pop_style).is_equal("bang")
	assert_that(RALLY_CONFIG.exhaust_pop_gain_db).is_equal(-6.0)
	assert_that(RALLY_CONFIG.exhaust_pop_min_rpm_fraction).is_equal(0.40)
