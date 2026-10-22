# tests/suites/test_audio_routing.gd
extends GdUnitTestSuite

## P0: Music / Vehicle / SFX / Ambience buses exist (idempotently), send to Master,
## the Music bus carries a (normally open) low-pass, and the player's engine
## low-pass lives on the Vehicle bus - NEVER on Master.

func test_ensure_buses_creates_the_layout_once() -> void:
	AudioRouting.ensure_buses()
	var count := AudioServer.bus_count
	AudioRouting.ensure_buses()
	assert_that(AudioServer.bus_count).is_equal(count) # idempotent
	for bus in [AudioRouting.BUS_MUSIC, AudioRouting.BUS_VEHICLE, AudioRouting.BUS_SFX, AudioRouting.BUS_AMBIENCE]:
		var idx := AudioServer.get_bus_index(bus)
		assert_that(idx).is_greater(0)
		assert_that(String(AudioServer.get_bus_send(idx))).is_equal("Master")

func test_music_bus_has_an_open_low_pass() -> void:
	AudioRouting.ensure_buses()
	var lpf := AudioRouting.music_lpf()
	assert_that(lpf).is_not_null()
	assert_that(lpf.cutoff_hz).is_equal(AudioRouting.MUSIC_LPF_OPEN_HZ)
	var idx := AudioServer.get_bus_index(AudioRouting.BUS_MUSIC)
	var lpf_count := 0
	for i in range(AudioServer.get_bus_effect_count(idx)):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectLowPassFilter:
			lpf_count += 1
	assert_that(lpf_count).is_equal(1)

func test_master_bus_never_gets_an_engine_filter() -> void:
	AudioRouting.ensure_buses()
	var player_engine := _player_engine()
	player_engine._ensure_lpf()
	var master := AudioServer.get_bus_index("Master")
	for i in range(AudioServer.get_bus_effect_count(master)):
		assert_that(AudioServer.get_bus_effect(master, i) is AudioEffectLowPassFilter).is_false()
	var vehicle := AudioServer.get_bus_index("Vehicle")
	var found := false
	for i in range(AudioServer.get_bus_effect_count(vehicle)):
		if AudioServer.get_bus_effect(vehicle, i) is AudioEffectLowPassFilter:
			found = true
	assert_that(found).is_true()
	assert_that(player_engine._lpf_bus_index).is_equal(vehicle)
	assert_that(String(player_engine.bus)).is_equal("Vehicle")
	player_engine._remove_lpf()

func test_rival_engine_stays_on_master() -> void:
	var rival: EngineAudio = auto_free(EngineAudio.new())
	assert_that(String(rival.bus)).is_equal("Master")
	assert_that(rival._lpf_added).is_false()

func _player_engine() -> EngineAudio:
	var engine: EngineAudio = auto_free(EngineAudio.new())
	return engine
