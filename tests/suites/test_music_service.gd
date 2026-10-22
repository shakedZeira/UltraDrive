# tests/suites/test_music_service.gd
extends GdUnitTestSuite

## MusicService state machine with GENERATED sine-wave tracks (no real music):
## play / pause / next / previous, track_changed signals, bad-track skip + give-up,
## station switching, the FreeRoam-only context gate (fade + pause + resume),
## bus volume, ducking hooks, persistence and the input commands. The service is
## instantiated fresh per test (sync loading, no persistence, no auto scan) so the
## real autoload and the user's music folder are never touched.

const ServiceScript: GDScript = preload("res://scripts/music/music_service.gd")
const FR := MusicPolicy.Context.FREE_ROAM

var _dir: String = ""
var _tracks_changed: Array = []
var _stations_changed: Array = []

func before_test() -> void:
	_dir = MusicTestUtil.temp_dir("svc")
	_tracks_changed.clear()
	_stations_changed.clear()

func after_test() -> void:
	MusicTestUtil.remove_dir(_dir)
	DirAccess.remove_absolute(_dir + "_index.json")
	DirAccess.remove_absolute("user://saves/slot_3.json")

## Long (30 s) 4 kHz tracks: playback runs in real time on the dummy driver, so
## the tracks must outlast any test.
func _wav(name: String, seconds: float = 30.0) -> void:
	MusicTestUtil.write_file("%s/%s" % [_dir, name], MusicStreams.make_sine_wav(seconds, 330.0, 4000))

func _populate() -> void:
	_wav("Rock/r1.wav")
	_wav("Rock/r2.wav")
	_wav("Rock/r3.wav")
	_wav("Jazz/j1.wav")
	_wav("Jazz/j2.wav")

func _make(persist: bool = false) -> Node:
	var svc: Node = ServiceScript.new()
	svc.persist = persist
	svc.persist_slot = 2
	svc.sync_loading = true
	svc.auto_start = false
	svc.index_path = _dir + "_index.json"
	add_child(svc)
	svc.settings["folder"] = _dir
	svc.settings["crossfade_s"] = 0.0
	svc.track_changed.connect(func(meta: Dictionary) -> void: _tracks_changed.append(meta))
	svc.station_changed.connect(func(n: String, id: String) -> void: _stations_changed.append(id))
	return svc

func _start(svc: Node) -> void:
	svc.set_context(FR, 1)
	svc.rescan()
	svc.tick(0.1)

func _free(svc: Node) -> void:
	svc.queue_free()

func test_does_nothing_until_free_roam_declares_itself() -> void:
	_populate()
	var svc := _make()
	svc.rescan()
	for _i in range(5):
		svc.tick(0.5)
	assert_that(svc.current_id).is_equal("")
	assert_that(_tracks_changed.size()).is_equal(0)
	_free(svc)

func test_free_roam_starts_playback_with_one_track_changed_signal() -> void:
	_populate()
	var svc := _make()
	_start(svc)
	assert_that(svc.current_id).is_not_equal("")
	assert_that(_tracks_changed.size()).is_equal(1)
	assert_that((_tracks_changed[0] as Dictionary)["title"]).is_not_equal("")
	assert_that(svc.station.id).is_equal("all")
	assert_that(svc.get_state()["stats"]["playable"]).is_equal(5)
	_free(svc)

func test_next_previous_and_forward_replay() -> void:
	_populate()
	var svc := _make()
	_start(svc)
	var first: String = svc.current_id
	svc.next_track()
	var second: String = svc.current_id
	assert_that(second).is_not_equal("")
	assert_that(_tracks_changed.size()).is_equal(2)
	svc.next_track()
	var third: String = svc.current_id
	svc.previous_track()
	assert_that(svc.current_id).is_equal(second)
	svc.previous_track()
	assert_that(svc.current_id).is_equal(first)
	svc.next_track()
	assert_that(svc.current_id).is_equal(second)
	svc.next_track()
	assert_that(svc.current_id).is_equal(third)
	_free(svc)

func test_pause_toggle_gates_audio_and_resume_continues() -> void:
	_populate()
	var svc := _make()
	_start(svc)
	svc.tick(2.0) # gate fully open
	assert_that(svc._gate_db).is_equal(0.0)
	var id: String = svc.current_id
	svc.toggle_pause()
	assert_that(svc.user_paused).is_true()
	svc.tick(1.0)
	svc.tick(1.0)
	assert_that(svc._gate_db).is_less_equal(ServiceScript.GATE_PAUSE_DB)
	assert_that(svc._decks_paused).is_true()
	svc.toggle_pause()
	svc.tick(0.1)
	assert_that(svc._decks_paused).is_false()
	svc.tick(2.0)
	assert_that(svc._gate_db).is_equal(0.0)
	assert_that(svc.current_id).is_equal(id) # same track resumed
	assert_that(_tracks_changed.size()).is_equal(1) # pause/resume is not a track change
	_free(svc)

func test_next_while_paused_resumes_playback() -> void:
	_populate()
	var svc := _make()
	_start(svc)
	svc.toggle_pause()
	svc.next_track()
	assert_that(svc.user_paused).is_false()
	_free(svc)

func test_race_context_fades_out_and_pauses_then_free_roam_resumes_same_track() -> void:
	_populate()
	var svc := _make()
	_start(svc)
	svc.tick(2.0)
	var id: String = svc.current_id
	svc.set_context(MusicPolicy.Context.RACE, 2)
	for _i in range(4):
		svc.tick(0.5)
	assert_that(svc._gate_db).is_less_equal(ServiceScript.GATE_PAUSE_DB)
	assert_that(svc._decks_paused).is_true()
	var bus := AudioServer.get_bus_index("Music")
	assert_that(AudioServer.get_bus_volume_db(bus)).is_less(-50.0)
	svc.set_context(FR, 3)
	svc.tick(0.1)
	assert_that(svc._decks_paused).is_false()
	svc.tick(2.0)
	assert_that(svc.current_id).is_equal(id)
	assert_that(_tracks_changed.size()).is_equal(1)
	assert_that(svc._gate_db).is_equal(0.0)
	_free(svc)

func test_garage_menu_and_no_host_never_play() -> void:
	_populate()
	var svc := _make()
	svc.rescan()
	for ctx in [MusicPolicy.Context.GARAGE, MusicPolicy.Context.MENU, MusicPolicy.Context.NONE]:
		svc.set_context(ctx, 5)
		for _i in range(3):
			svc.tick(0.5)
		assert_that(svc.current_id).is_equal("")
		assert_that(svc._gate_db).is_less_equal(ServiceScript.GATE_PAUSE_DB)
	_free(svc)

func test_old_scene_exit_does_not_clear_the_new_scene_context() -> void:
	var svc := _make()
	svc.set_context(FR, 10)
	svc.set_context(FR, 11) # new scene enters first
	svc.clear_context(10) # old scene exits afterwards
	assert_that(svc.context).is_equal(FR)
	svc.clear_context(11)
	assert_that(svc.context).is_equal(MusicPolicy.Context.NONE)
	_free(svc)

func test_bus_volume_follows_user_volume_when_gate_is_open() -> void:
	_populate()
	var svc := _make()
	_start(svc)
	svc.set_volume(0.5)
	for _i in range(6):
		svc.tick(0.5)
	var bus := AudioServer.get_bus_index("Music")
	assert_that(AudioServer.get_bus_volume_db(bus)).is_equal_approx(linear_to_db(0.5), 0.2)
	svc.set_volume(0.0)
	for _i in range(6):
		svc.tick(0.5)
	assert_that(AudioServer.get_bus_volume_db(bus)).is_less(-60.0)
	_free(svc)

func test_volume_steps_clamp_and_emit() -> void:
	var svc := _make()
	var seen: Array = []
	svc.volume_changed.connect(func(v: float) -> void: seen.append(v))
	svc.set_volume(0.98)
	svc.volume_up()
	assert_that(svc.settings["volume"]).is_equal(1.0)
	svc.volume_down()
	assert_that(float(svc.settings["volume"])).is_equal_approx(0.95, 0.0001)
	assert_that(seen.size()).is_equal(3)
	svc.set_volume(0.02)
	svc.volume_down()
	assert_that(svc.settings["volume"]).is_equal(0.0)
	_free(svc)

func test_pause_menu_ducks_and_muffles_the_music_bus() -> void:
	_populate()
	var svc := _make()
	_start(svc)
	svc.tick(2.0)
	svc.force_flags = {"paused": true}
	for _i in range(6):
		svc.tick(0.5)
	assert_that(svc._duck_db).is_equal_approx(MusicPolicy.PAUSE_DUCK_DB, 0.05)
	assert_that(AudioRouting.music_lpf().cutoff_hz).is_equal_approx(MusicPolicy.PAUSE_LPF_HZ, 1.0)
	var bus := AudioServer.get_bus_index("Music")
	assert_that(AudioServer.get_bus_volume_db(bus)).is_equal_approx(linear_to_db(0.7) + MusicPolicy.PAUSE_DUCK_DB, 0.3)
	svc.force_flags = {}
	for _i in range(8):
		svc.tick(0.5)
	assert_that(svc._duck_db).is_equal_approx(0.0, 0.05)
	assert_that(AudioRouting.music_lpf().cutoff_hz).is_equal_approx(MusicPolicy.LPF_OPEN_HZ, 1.0)
	assert_that(svc.current_id).is_not_equal("") # music keeps playing under the pause menu
	_free(svc)

func test_crash_and_speed_trap_ducks() -> void:
	_populate()
	var svc := _make()
	_start(svc)
	svc.tick(2.0)
	svc.notify_impact(10.0) # below threshold: nothing
	svc.tick(0.5)
	assert_that(svc._duck_db).is_equal(0.0)
	svc.notify_impact(MusicDucker.CRASH_THRESHOLD * 3.0)
	svc.tick(0.5)
	assert_that(svc._duck_db).is_less(-10.0)
	for _i in range(10):
		svc.tick(0.5) # hold 0.8 + release 1.5, then slew back
	assert_that(svc._duck_db).is_equal_approx(0.0, 0.01)
	svc.notify_speed_trap()
	svc.tick(0.5)
	assert_that(svc._duck_db).is_less(-4.0)
	svc.settings["duck"] = false
	svc.ducker.clear_all()
	svc.tick(3.0)
	svc.notify_impact(MusicDucker.CRASH_THRESHOLD * 3.0)
	svc.tick(0.5)
	assert_that(svc._duck_db).is_equal_approx(0.0, 0.01)
	_free(svc)

func test_bad_track_is_skipped_and_marked() -> void:
	_wav("Mix/good1.wav")
	_wav("Mix/good2.wav")
	MusicTestUtil.write_file(_dir + "/Mix/broken.wav", PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46]))
	var svc := _make()
	_start(svc)
	svc._begin_track("Mix/broken.wav", 0.0)
	assert_that(svc.current_id).is_not_equal("Mix/broken.wav")
	assert_that(svc.current_id).is_not_equal("")
	assert_that(svc.queue.bad.has("Mix/broken.wav")).is_true()
	assert_that(svc.no_playable).is_false()
	for _i in range(12):
		svc.next_track()
		assert_that(svc.current_id).is_not_equal("Mix/broken.wav")
	_free(svc)

func test_all_bad_tracks_give_up_with_no_playable() -> void:
	for i in range(7):
		MusicTestUtil.write_file("%s/Bad/b%d.wav" % [_dir, i], PackedByteArray([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47]))
	var svc := _make()
	_start(svc)
	assert_that(svc.no_playable).is_true()
	assert_that(svc.current_id).is_equal("")
	assert_that(svc.queue.bad.size()).is_less_equal(ServiceScript.MAX_CONSECUTIVE_FAILURES)
	# it stops trying: more ticks do not loop forever
	for _i in range(5):
		svc.tick(0.5)
	assert_that(svc.no_playable).is_true()
	_free(svc)

func test_station_switch_plays_from_that_station() -> void:
	_populate()
	var svc := _make()
	_start(svc)
	assert_that(svc.set_station("f:Jazz")).is_true()
	assert_that(_stations_changed).is_equal(["f:Jazz"])
	assert_that(String(svc.current_id).begins_with("Jazz/")).is_true()
	assert_that(svc.settings["station"]).is_equal("f:Jazz")
	assert_that(svc.set_station("f:Nope")).is_false()
	svc.next_track()
	assert_that(String(svc.current_id).begins_with("Jazz/")).is_true()
	_free(svc)

func test_cycle_station_wraps_through_all_stations() -> void:
	_populate()
	var svc := _make()
	_start(svc)
	var seen: Array[String] = [svc.station.id]
	for _i in range(3):
		svc.cycle_station(1)
		seen.append(svc.station.id)
	assert_that(seen).is_equal(["all", "f:Jazz", "f:Rock", "all"])
	svc.cycle_station(-1)
	assert_that(svc.station.id).is_equal("f:Rock")
	_free(svc)

func test_input_commands_drive_the_service() -> void:
	_populate()
	var svc := _make()
	_start(svc)
	var next_btn := InputEventJoypadButton.new()
	next_btn.button_index = MusicInput.JOY_DPAD_RIGHT
	next_btn.pressed = true
	var first: String = svc.current_id
	assert_that(svc.handle_event(next_btn, 1.0)).is_true() # consumed
	assert_that(svc.current_id).is_not_equal(first)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_TOUCHPAD
	pad.pressed = true
	svc.handle_event(pad, 2.0)
	assert_that(svc.user_paused).is_true()
	# outside FreeRoam the pad does nothing
	svc.set_context(MusicPolicy.Context.MENU, 4)
	assert_that(svc.handle_event(next_btn, 3.0)).is_false()
	_free(svc)

func test_streamer_safe_and_disabled_silence_everything() -> void:
	_populate()
	var svc := _make()
	svc.settings["streamer_safe"] = true
	_start(svc)
	for _i in range(3):
		svc.tick(0.5)
	assert_that(svc.current_id).is_equal("")
	assert_that(svc.is_music_allowed()).is_false()
	svc.set_setting("streamer_safe", false)
	svc.tick(0.5)
	assert_that(svc.current_id).is_not_equal("")
	svc.set_setting("enabled", false)
	assert_that(svc.is_music_allowed()).is_false()
	_free(svc)

func test_folder_inside_the_project_is_refused() -> void:
	var svc := _make()
	assert_that(svc.set_folder("res://music")).is_false()
	assert_that(svc.set_folder(ProjectSettings.globalize_path("res://") + "songs")).is_false()
	assert_that(svc.settings["folder"]).is_equal(_dir)
	assert_that(svc.set_folder(_dir + "_elsewhere")).is_true()
	svc.settings["folder"] = _dir
	_free(svc)

func test_set_folder_rescans_and_replaces_the_library() -> void:
	_populate()
	var svc := _make()
	_start(svc)
	var other := _dir + "_other"
	MusicTestUtil.write_file(other + "/Only/x.wav", MusicStreams.make_sine_wav(30.0, 330.0, 4000))
	assert_that(svc.set_folder(other)).is_true()
	svc.tick(0.1)
	assert_that(svc.library.order).is_equal(["Only/x.wav"])
	assert_that(svc.current_id).is_equal("Only/x.wav")
	MusicTestUtil.remove_dir(other)
	DirAccess.remove_absolute(_dir + "_index.json")
	_free(svc)

func test_rescan_keeps_the_playing_track_alive() -> void:
	_populate()
	var svc := _make()
	_start(svc)
	var id: String = svc.current_id
	svc.rescan()
	svc.tick(0.1)
	assert_that(svc.current_id).is_equal(id)
	assert_that(_tracks_changed.size()).is_equal(1)
	_free(svc)

func test_missing_folder_is_reported_not_fatal() -> void:
	var svc := _make()
	svc.settings["folder"] = _dir + "/nope"
	_start(svc)
	svc.tick(0.5)
	assert_that(svc.folder_missing).is_true()
	assert_that(String(svc.scan_status_text())).contains("not found")
	assert_that(svc.current_id).is_equal("")
	_free(svc)

func test_auto_advance_when_the_track_ends() -> void:
	_populate()
	var svc := _make()
	_start(svc)
	var first: String = svc.current_id
	# Pretend the deck ran out: stop it (playing == false) and tick.
	svc._decks[svc._active].stop()
	svc.tick(0.1)
	assert_that(svc.current_id).is_not_equal(first)
	assert_that(_tracks_changed.size()).is_equal(2)
	_free(svc)

func test_crossfade_window_triggers_the_next_track_early_and_fades() -> void:
	_wav("X/a.wav", 20.0)
	_wav("X/b.wav", 20.0)
	var svc := _make()
	svc.settings["crossfade_s"] = 2.0
	_start(svc)
	var first: String = svc.current_id
	# Mid-track nothing happens; the deck position is real-time, so drive the pure
	# decision instead of waiting 2 s.
	assert_that(CrossfadeMath.should_start_next(20.0, 0.5, 0.0, 2.0)).is_false()
	assert_that(CrossfadeMath.should_start_next(20.0, 18.1, 0.0, 2.0)).is_true()
	svc._advance_auto(CrossfadeMath.window_for(2.0, 20.0))
	assert_that(svc.current_id).is_not_equal(first)
	assert_that(svc._fade_from).is_greater_equal(0)
	svc.tick(0.5)
	var out_db: float = svc._decks[svc._fade_from].volume_db
	var in_db: float = svc._decks[svc._active].volume_db
	assert_that(out_db).is_greater(in_db) # a quarter of the way in, the old track is still louder
	svc.tick(1.6)
	assert_that(svc._fade_from).is_equal(-1)
	assert_that(svc._decks[svc._active].volume_db).is_equal(0.0)
	_free(svc)

func test_settings_persist_to_the_slot_and_keep_other_keys() -> void:
	SaveManager.save_game(2, {"quality_preset": 1})
	var svc := _make(true)
	svc.set_volume(0.33)
	svc.set_setting("toast", false)
	svc.flush_settings()
	var loaded := SaveManager.load_game(2)
	assert_that(int(loaded["quality_preset"])).is_equal(1) # JSON loads whole numbers as floats
	var saved: Dictionary = loaded["music_settings"]
	assert_that(float(saved["volume"])).is_equal_approx(0.33, 0.0001)
	assert_that(saved["toast"]).is_false()
	_free(svc)

func test_saves_are_debounced_and_a_track_change_alone_does_not_create_a_save() -> void:
	DirAccess.remove_absolute("user://saves/slot_3.json")
	_populate()
	var svc := _make(true)
	_start(svc) # track change only (minor)
	svc.flush_settings()
	assert_that(SaveManager.has_save(2)).is_false()
	svc.set_volume(0.2)
	svc.set_volume(0.25)
	svc.set_volume(0.3)
	assert_that(SaveManager.has_save(2)).is_false() # debounce: not yet written
	svc.tick(ServiceScript.SAVE_DEBOUNCE_S + 0.1)
	assert_that(SaveManager.has_save(2)).is_true()
	assert_that(float(MusicSettings.from_save(SaveManager.load_game(2))["volume"])).is_equal_approx(0.3, 0.0001)
	_free(svc)

func test_saved_station_and_track_are_restored() -> void:
	_populate()
	var data := MusicSettings.defaults()
	data["station"] = "f:Jazz"
	data["track_id"] = "Jazz/j2.wav"
	data["folder"] = _dir
	SaveManager.save_game(2, {MusicSettings.SAVE_KEY: data})
	var svc := _make(true)
	svc.settings["folder"] = _dir
	svc.settings["crossfade_s"] = 0.0
	_start(svc)
	assert_that(svc.station.id).is_equal("f:Jazz")
	assert_that(svc.current_id).is_equal("Jazz/j2.wav")
	_free(svc)

func test_wav_loader_and_unsupported_formats() -> void:
	var path := _dir + "/ok.wav"
	MusicTestUtil.write_file(path, MusicStreams.make_sine_wav(0.5, 440.0, 8000))
	var stream := MusicStreams.load_stream(path)
	assert_that(stream).is_not_null()
	assert_that(stream.get_length()).is_equal_approx(0.5, 0.01)
	MusicTestUtil.write_file(_dir + "/song.flac", PackedByteArray([1, 2, 3]))
	assert_that(MusicStreams.load_stream(_dir + "/song.flac")).is_null()
	assert_that(MusicStreams.load_stream(_dir + "/missing.wav")).is_null()
	assert_that(MusicStreams.stream_from_bytes("wav", PackedByteArray([1, 2, 3]))).is_null()
