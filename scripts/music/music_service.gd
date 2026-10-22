# scripts/music/music_service.gd
extends Node

## Autoload "MusicService": the FreeRoam radio.
##
##   folder --scan(worker)--> MusicLibrary (tracks, stations) <-- user://music_index.json
##   StationQueue (shuffle bag + history) -> two AudioStreamPlayer decks (A/B)
##   on the "Music" bus with an equal-power crossfade. The BUS carries user
##   volume + ducking + the context gate, the decks only do the per-track fade.
##
## Music plays ONLY while a MusicContextHost declares FREE_ROAM (policy in
## MusicPolicy); every other context fades out and PAUSES, keeping the position.
## Runs while the tree is paused (PROCESS_MODE_ALWAYS). Nothing is scanned or
## created on disk until the first FREE_ROAM context arrives.
##
## Test seams: `persist`, `sync_loading`, `auto_start` and tick(delta).

signal track_changed(meta: Dictionary)
signal station_changed(station_name: String, station_id: String)
signal state_changed()
signal library_progress(done_count: int, total: int)
signal library_ready(stats: Dictionary)
signal cover_ready(track_id: String, texture: Texture2D, accent: Color, generated: bool)
signal volume_changed(volume: float)
## Generic one-line notice for the toast ("Paused", "Volume 70%", ...).
signal notice(title: String, subtitle: String)

const MUSIC_BUS := &"Music"
const MANUAL_FADE_S := 0.4
const STATION_FADE_S := 0.8
const MAX_CONSECUTIVE_FAILURES := 5
const SAVE_DEBOUNCE_S := 0.8
## Files modified within this many seconds are skipped (still being copied).
const SCAN_MIN_AGE_S := 2.0
const GATE_OFF_DB := -60.0
const GATE_PAUSE_DB := -55.0
const LPF_SLEW_HZ_PER_S := 60000.0
const HOOK_INTERVAL_S := 1.0

class _LoadJob extends RefCounted:
	var task: int = -1
	var stream: AudioStream = null
	var done: bool = false

var settings: Dictionary = MusicSettings.defaults()
var library: MusicLibrary = MusicLibrary.new()
var station: MusicStation = null
var queue: StationQueue = StationQueue.new()
var context: int = MusicPolicy.Context.NONE
var user_paused: bool = false
var current_id: String = ""
var current_track: Dictionary = {}
var current_cover: Texture2D = null
var no_playable: bool = false
var scan_total: int = 0
var scan_done_count: int = 0
var scan_active: bool = false
var folder_missing: bool = false

## Tests set these BEFORE add_child / _ready.
var persist: bool = true
var persist_slot: int = 0
var sync_loading: bool = false
var auto_start: bool = true
## Test seam: merged over the live {paused, photo} flags.
var force_flags: Dictionary = {}
var index_path: String = MusicScanner.DEFAULT_INDEX

var scanner: MusicScanner = MusicScanner.new()
var ducker: MusicDucker = MusicDucker.new()
var input_state: MusicInput = MusicInput.new()

var _decks: Array[AudioStreamPlayer] = []
var _active: int = 0
var _fade_from: int = -1
var _fade_to: int = -1
var _fade_t: float = 1.0
var _fade_len: float = 0.0
var _gate_db: float = GATE_OFF_DB
var _gate_fade_s: float = MusicPolicy.FADE_IN_S
var _duck_db: float = 0.0
var _last_pol_play: bool = false
var _last_user_paused: bool = false
var _decks_paused: bool = false
var _context_owner: int = 0
var _streams: Dictionary = {}
var _jobs: Dictionary = {}
var _job_mutex := Mutex.new()
var _want: Dictionary = {}
var _failures: int = 0
var _advancing: bool = false
var _scan_target: MusicLibrary = null
var _scanned_folder: String = ""
var _dirty: bool = false
var _dirty_major: bool = false
var _save_timer: float = -1.0
var _hook_timer: float = 0.0
var _car_hooked: Object = null
var _trap_hooked: Object = null
var _cover_job: int = -1
var _bus_index: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		auto_start = false
	AudioRouting.ensure_buses()
	_bus_index = AudioServer.get_bus_index(MUSIC_BUS)
	if persist and has_node("/root/SaveManager"):
		settings = MusicSettings.from_save(SaveManager.load_game(persist_slot))
	for i in range(2):
		var p := AudioStreamPlayer.new()
		p.bus = MUSIC_BUS
		p.name = "Deck%s" % ("AB"[i])
		add_child(p)
		_decks.append(p)
	set_process(true)

func _exit_tree() -> void:
	flush_settings()
	scanner.cancel()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush_settings()

# ---------------------------------------------------------------------------
# Context (declared by MusicContextHost nodes).
# ---------------------------------------------------------------------------

func set_context(ctx: int, owner_id: int = 0) -> void:
	context = ctx
	_context_owner = owner_id
	if ctx == MusicPolicy.Context.FREE_ROAM and auto_start:
		ensure_library()
	state_changed.emit()

## Clears the context only if `owner_id` still owns it (an old scene's exit must
## not wipe the context its successor just declared).
func clear_context(owner_id: int = 0) -> void:
	if owner_id != 0 and owner_id != _context_owner:
		return
	context = MusicPolicy.Context.NONE
	_context_owner = 0
	input_state.reset()
	state_changed.emit()

func is_music_allowed() -> bool:
	return bool(MusicPolicy.policy_for(context, settings)["play"])

# ---------------------------------------------------------------------------
# Library / scan.
# ---------------------------------------------------------------------------

## Scans the configured folder once per folder (idempotent).
func ensure_library() -> void:
	var folder := _resolve_folder()
	if folder == _scanned_folder and (scan_active or not library.order.is_empty()):
		return
	rescan()

func rescan() -> void:
	var folder := _resolve_folder()
	_scanned_folder = folder
	folder_missing = not DirAccess.dir_exists_absolute(folder)
	# First scan feeds the live library (playback can start after batch 1); a
	# rescan builds a fresh one and swaps at the end so the current track survives.
	_scan_target = library if library.order.is_empty() else MusicLibrary.new()
	scan_total = 0
	scan_done_count = 0
	scan_active = true
	if sync_loading:
		scanner.run_sync(folder, index_path, 0.0)
		_pump_scanner()
	else:
		scanner.start(folder, index_path, SCAN_MIN_AGE_S)
	state_changed.emit()

## Folder chosen in the settings UI. False (and nothing changes) for res:// or
## in-project paths: files there are imported and bundled by the editor.
func set_folder(path: String) -> bool:
	var p := path.strip_edges().replace("\\", "/")
	if p.is_empty() or MusicSettings.is_inside_project(p):
		return false
	settings["folder"] = p
	_mark_dirty(false)
	scanner.cancel()
	_stop_all()
	library = MusicLibrary.new()
	station = null
	queue = StationQueue.new()
	_scanned_folder = ""
	flush_settings()
	if auto_start or sync_loading:
		rescan()
	state_changed.emit()
	return true

func _resolve_folder() -> String:
	var folder := MusicSettings.effective_folder(settings)
	if String(settings.get("folder", "")).strip_edges().is_empty():
		# Default folder: create it so the user has somewhere to drop songs.
		if not MusicSettings.ensure_folder(folder):
			var fallback := OS.get_system_dir(OS.SYSTEM_DIR_MUSIC).path_join("UltraDrive")
			if MusicSettings.ensure_folder(fallback):
				folder = fallback
	return folder

func _pump_scanner() -> void:
	for m in scanner.poll():
		var msg: Dictionary = m
		match String(msg["type"]):
			"meta":
				if _scan_target != null:
					_scan_target.set_folder_meta(msg["meta"])
			"tracks":
				if _scan_target != null:
					_scan_target.add_tracks(msg["tracks"])
					if _scan_target == library:
						_on_library_changed()
			"progress":
				scan_done_count = int(msg["done"])
				scan_total = int(msg["total"])
				library_progress.emit(scan_done_count, scan_total)
			"done":
				scan_active = false
				if _scan_target != null and _scan_target != library:
					library = _scan_target
					_on_library_changed()
				_scan_target = null
				library_ready.emit(library.stats())
				state_changed.emit()

func _on_library_changed() -> void:
	var list := library.playable_stations()
	if list.is_empty():
		station = null
		state_changed.emit()
		return
	var wanted_id := station.id if station != null else String(settings.get("station", MusicStation.ALL_ID))
	var found := library.station_by_id(wanted_id)
	if found == null or found.playable_count() == 0:
		found = library.station_by_id(MusicStation.ALL_ID)
	var changed := station == null or station.id != found.id
	station = found
	if changed:
		queue = StationQueue.new()
	queue.set_tracks(station.track_ids, library.artist_map(), station.shuffle and bool(settings.get("shuffle", true)))
	state_changed.emit()

# ---------------------------------------------------------------------------
# Transport.
# ---------------------------------------------------------------------------

func has_tracks() -> bool:
	return station != null and station.playable_count() > 0

func next_track() -> void:
	if not has_tracks():
		return
	user_paused = false
	_begin_track(queue.next(), MANUAL_FADE_S)
	state_changed.emit()

func previous_track() -> void:
	if not has_tracks():
		return
	user_paused = false
	var elapsed := 0.0
	var deck: AudioStreamPlayer = _decks[_active] if not _decks.is_empty() else null
	if deck != null and deck.playing:
		elapsed = deck.get_playback_position()
	_begin_track(queue.previous(elapsed), MANUAL_FADE_S)
	state_changed.emit()

func toggle_pause() -> void:
	user_paused = not user_paused
	notice.emit("Paused" if user_paused else "Playing", String(current_track.get("title", "")))
	state_changed.emit()

func set_paused(value: bool) -> void:
	if user_paused != value:
		toggle_pause()

func set_volume(v: float) -> void:
	settings["volume"] = clampf(v, MusicSettings.VOLUME_MIN, MusicSettings.VOLUME_MAX)
	_mark_dirty(false)
	volume_changed.emit(float(settings["volume"]))

func volume_up() -> void:
	set_volume(float(settings["volume"]) + MusicSettings.VOLUME_STEP)
	notice.emit("Volume", "%d%%" % int(round(float(settings["volume"]) * 100.0)))

func volume_down() -> void:
	set_volume(float(settings["volume"]) - MusicSettings.VOLUME_STEP)
	notice.emit("Volume", "%d%%" % int(round(float(settings["volume"]) * 100.0)))

func set_setting(key: String, value: Variant) -> void:
	if not MusicSettings.defaults().has(key):
		return
	settings[key] = value
	settings = MusicSettings.sanitize(settings)
	_mark_dirty(false)
	if key == "shuffle" and station != null:
		queue.set_tracks(station.track_ids, library.artist_map(), station.shuffle and bool(settings["shuffle"]))
	if key == "streamer_safe" and bool(settings["streamer_safe"]):
		notice.emit("Music off", "Streamer-safe mode")
	state_changed.emit()

func set_station(station_id: String) -> bool:
	var st := library.station_by_id(station_id)
	if st == null or st.playable_count() == 0:
		return false
	station = st
	settings["station"] = station_id
	settings["track_id"] = ""
	_mark_dirty(false)
	queue = StationQueue.new()
	queue.set_tracks(st.track_ids, library.artist_map(), st.shuffle and bool(settings.get("shuffle", true)))
	user_paused = false
	station_changed.emit(st.display_name, st.id)
	_begin_track(queue.next(), STATION_FADE_S)
	state_changed.emit()
	return true

func cycle_station(step: int = 1) -> void:
	var list := library.playable_stations()
	if list.is_empty():
		return
	var at := 0
	for i in range(list.size()):
		if station != null and list[i].id == station.id:
			at = i
	set_station(list[posmod(at + step, list.size())].id)

## Snapshot for UI / tests.
func get_state() -> Dictionary:
	var deck: AudioStreamPlayer = _decks[_active] if not _decks.is_empty() else null
	var length := 0.0
	var pos := 0.0
	if deck != null and deck.stream != null:
		length = deck.stream.get_length()
		pos = deck.get_playback_position()
	return {
		"context": context,
		"allowed": is_music_allowed(),
		"paused": user_paused,
		"station_id": station.id if station != null else "",
		"station_name": station.display_name if station != null else "",
		"track": current_track,
		"position_s": pos,
		"length_s": length,
		"no_playable": no_playable,
		"volume": float(settings["volume"]),
		"stats": library.stats(),
	}

## 0..1 progress through the current track (the toast's bar).
func playback_fraction() -> float:
	if _decks.is_empty():
		return 0.0
	var deck := _decks[_active]
	if deck.stream == null or not deck.playing:
		return 0.0
	var length := deck.stream.get_length()
	if length <= 0.0:
		return 0.0
	return clampf(deck.get_playback_position() / length, 0.0, 1.0)

func scan_status_text() -> String:
	if scan_active:
		return "Scanning... %d / %d" % [scan_done_count, scan_total]
	if folder_missing and library.order.is_empty():
		return "Folder not found. Create it or choose another."
	var st := library.stats()
	if int(st["tracks"]) == 0:
		return "No songs found. Drop mp3 / ogg / wav files in the folder."
	return library.status_text()

# ---------------------------------------------------------------------------
# Track pipeline: load (worker) -> activate (deck + crossfade) -> prefetch.
# ---------------------------------------------------------------------------

func _begin_track(id: String, fade_s: float) -> void:
	if id.is_empty() or not library.tracks.has(id):
		no_playable = id.is_empty()
		_want = {}
		return
	_want = {"id": id, "fade": fade_s}
	_request_load(id)
	_resolve_want()

func _request_load(id: String) -> void:
	if _streams.has(id) or _jobs.has(id):
		return
	var track := library.get_track(id)
	if track.is_empty():
		_streams[id] = null
		return
	var path := String(track.get("path", ""))
	if sync_loading:
		_streams[id] = MusicStreams.load_stream(path)
		return
	var job := _LoadJob.new()
	_jobs[id] = job
	job.task = WorkerThreadPool.add_task(_load_job.bind(job, path), false, "music_load")

func _load_job(job: _LoadJob, path: String) -> void:
	var s := MusicStreams.load_stream(path)
	_job_mutex.lock()
	job.stream = s
	job.done = true
	_job_mutex.unlock()

func _poll_jobs() -> void:
	if _jobs.is_empty():
		return
	for id in _jobs.keys():
		var job: _LoadJob = _jobs[id]
		_job_mutex.lock()
		var finished := job.done
		_job_mutex.unlock()
		if finished:
			WorkerThreadPool.wait_for_task_completion(job.task)
			_streams[id] = job.stream
			_jobs.erase(id)

func _resolve_want() -> void:
	if _want.is_empty():
		return
	var id := String(_want["id"])
	if not _streams.has(id):
		return
	var stream: AudioStream = _streams[id]
	var fade := float(_want["fade"])
	_want = {}
	if stream == null:
		_on_load_failed(id, fade)
	else:
		_activate(id, stream, fade)

func _on_load_failed(id: String, fade_s: float) -> void:
	push_warning("MusicService: cannot play a track (unsupported or corrupt file); skipping it.")
	queue.mark_bad(id)
	_streams.erase(id)
	_failures += 1
	if _failures >= MAX_CONSECUTIVE_FAILURES:
		no_playable = true
		_advancing = false
		state_changed.emit()
		return
	var nxt := queue.next()
	if nxt.is_empty():
		no_playable = true
		_advancing = false
		state_changed.emit()
		return
	_begin_track(nxt, fade_s)

func _activate(id: String, stream: AudioStream, fade_s: float) -> void:
	_failures = 0
	no_playable = false
	_advancing = false
	var from := _active
	var to := 1 - from if _decks[from].playing else from
	var deck := _decks[to]
	var crossfading := fade_s > 0.0 and to != from
	deck.stop()
	deck.stream = stream
	deck.volume_db = CrossfadeMath.SILENCE_DB if crossfading else 0.0
	deck.stream_paused = _decks_paused
	deck.play()
	if crossfading:
		_fade_from = from
		_fade_to = to
		_fade_t = 0.0
		_fade_len = fade_s
	else:
		if to != from:
			_decks[from].stop()
		_fade_from = -1
		_fade_t = 1.0
	_active = to
	current_id = id
	current_track = library.get_track(id)
	if queue.current() != id:
		queue.jump_to(id)
	settings["track_id"] = id
	_mark_dirty(true)
	_prune_streams()
	var meta := current_track.duplicate()
	meta["station_name"] = station.display_name if station != null else ""
	track_changed.emit(meta)
	_request_cover(current_track)
	var nxt := queue.peek_next()
	if not nxt.is_empty():
		_request_load(nxt)

func _prune_streams() -> void:
	var keep := {current_id: true}
	if not _want.is_empty():
		keep[String(_want["id"])] = true
	var nxt := queue.peek_next()
	if not nxt.is_empty():
		keep[nxt] = true
	for id in _streams.keys():
		if not keep.has(id):
			_streams.erase(id)

func _step_fade(delta: float) -> void:
	if _fade_from < 0:
		return
	_fade_t = CrossfadeMath.advance_t(_fade_t, delta, _fade_len)
	_decks[_fade_to].volume_db = CrossfadeMath.gain_to_db(CrossfadeMath.in_gain(_fade_t))
	_decks[_fade_from].volume_db = CrossfadeMath.gain_to_db(CrossfadeMath.out_gain(_fade_t))
	if _fade_t >= 1.0:
		_decks[_fade_from].stop()
		_decks[_fade_to].volume_db = 0.0
		_fade_from = -1

func _check_auto_advance() -> void:
	if not _want.is_empty() or current_id.is_empty() or _advancing or _decks_paused or no_playable:
		return
	var deck := _decks[_active]
	if not deck.playing or deck.stream == null:
		_advance_auto(0.0)
		return
	var length := deck.stream.get_length()
	if CrossfadeMath.should_start_next(length, deck.get_playback_position(), AudioServer.get_time_since_last_mix(), float(settings["crossfade_s"])):
		_advance_auto(CrossfadeMath.window_for(float(settings["crossfade_s"]), length))

func _advance_auto(fade_s: float) -> void:
	_advancing = true
	var id := queue.next()
	if id.is_empty():
		_advancing = false
		return
	_begin_track(id, fade_s)

func _stop_all() -> void:
	for d in _decks:
		d.stop()
		d.stream = null
	_streams.clear()
	_want = {}
	_fade_from = -1
	current_id = ""
	current_track = {}
	current_cover = null
	_advancing = false
	no_playable = false
	_failures = 0

func _start_initial() -> void:
	if not has_tracks() or not _want.is_empty():
		return
	var saved := String(settings.get("track_id", ""))
	var id := ""
	if not saved.is_empty() and station.track_ids.has(saved):
		id = saved
		queue.jump_to(id)
	else:
		id = queue.next()
	_begin_track(id, 0.0)

# ---------------------------------------------------------------------------
# Cover art (decoded on a worker, texture built on the main thread).
# ---------------------------------------------------------------------------

func _request_cover(track: Dictionary) -> void:
	current_cover = null
	var id := String(track.get("id", ""))
	var label := station.display_name if station != null else ""
	if sync_loading:
		_finish_cover(id, MusicCovers.load_cover(track, String(track.get("artist", label))))
		return
	WorkerThreadPool.add_task(_cover_worker.bind(track.duplicate(), id, String(track.get("artist", label))), false, "music_cover")

func _cover_worker(track: Dictionary, id: String, label: String) -> void:
	var res := MusicCovers.load_cover(track, label)
	_finish_cover.call_deferred(id, res)

func _finish_cover(id: String, res: Dictionary) -> void:
	if id != current_id:
		return
	var img: Image = res.get("image")
	if img == null:
		return
	current_cover = ImageTexture.create_from_image(img)
	cover_ready.emit(id, current_cover, res.get("accent", Color(0.3, 0.3, 0.3)), bool(res.get("generated", false)))

# ---------------------------------------------------------------------------
# Per-frame: policy gate, ducking, bus volume, crossfade, auto-advance.
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	tick(delta)

func tick(delta: float) -> void:
	_pump_scanner()
	_poll_jobs()
	_resolve_want()
	var flags := _flags()
	var pol := MusicPolicy.policy_for(context, settings, flags)
	var pol_play: bool = bool(pol["play"])
	var want := pol_play and not user_paused
	# Gate fade speed: context change -> policy fade, user pause -> short fade.
	if pol_play != _last_pol_play:
		_gate_fade_s = float(pol["fade_s"])
	elif user_paused != _last_user_paused:
		_gate_fade_s = MusicPolicy.USER_FADE_S
	_last_pol_play = pol_play
	_last_user_paused = user_paused
	_gate_db = move_toward(_gate_db, 0.0 if want else GATE_OFF_DB, 60.0 / maxf(_gate_fade_s, 0.05) * delta)
	# Ducking: sustained context duck (+ one-shot crash / speed-trap ducks).
	ducker.hold("context", float(pol["duck_db"]))
	ducker.advance(delta)
	_duck_db = MusicDucker.slew_db(_duck_db, ducker.target_db(), delta)
	var vol_db := linear_to_db(maxf(float(settings["volume"]), 0.0001))
	if _bus_index >= 0:
		AudioServer.set_bus_volume_db(_bus_index, vol_db + _duck_db + _gate_db)
		var lpf := AudioRouting.music_lpf()
		if lpf != null:
			lpf.cutoff_hz = move_toward(lpf.cutoff_hz, float(pol["lpf_hz"]), LPF_SLEW_HZ_PER_S * delta)
	# Pause decks once silent; resume the moment music is wanted again.
	if not want and _gate_db <= GATE_PAUSE_DB and not _decks_paused:
		_set_decks_paused(true)
	elif want and _decks_paused:
		_set_decks_paused(false)
	if want and current_id.is_empty() and not no_playable and has_tracks():
		_start_initial()
	_step_fade(delta)
	if want or not _decks_paused:
		_check_auto_advance()
	if _save_timer >= 0.0:
		_save_timer -= delta
		if _save_timer < 0.0:
			flush_settings()
	_hook_timer -= delta
	if _hook_timer <= 0.0:
		_hook_timer = HOOK_INTERVAL_S
		_wire_hooks()

func _set_decks_paused(value: bool) -> void:
	_decks_paused = value
	for d in _decks:
		d.stream_paused = value

func _flags() -> Dictionary:
	var paused := false
	if is_inside_tree():
		paused = get_tree().paused
	var photo := false
	var pm := get_node_or_null("/root/PhotoModeController")
	if pm != null and pm.has_method("is_active"):
		photo = bool(pm.call("is_active"))
	var flags := {"paused": paused, "photo": photo}
	flags.merge(force_flags, true)
	return flags

# ---------------------------------------------------------------------------
# Input (gamepad chord / tap logic lives in MusicInput).
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if handle_event(event, Time.get_ticks_msec() / 1000.0) and is_inside_tree():
		get_viewport().set_input_as_handled()

## Interprets one event; runs its commands. True when the event should be
## swallowed (gamepad buttons only; keys always pass through).
func handle_event(event: InputEvent, now_s: float) -> bool:
	if context != MusicPolicy.Context.FREE_ROAM or not is_music_allowed():
		return false
	var res := input_state.interpret(event, now_s, _flags())
	for c in res["commands"]:
		run_command(String(c))
	return bool(res["consume"])

func run_command(command: String) -> void:
	match command:
		"next":
			next_track()
		"prev":
			previous_track()
		"toggle":
			toggle_pause()
		"vol_up":
			volume_up()
		"vol_down":
			volume_down()
		"station_next":
			cycle_station(1)
		"station_prev":
			cycle_station(-1)

# ---------------------------------------------------------------------------
# Ducking hooks (player impact, speed trap) - connected lazily in FREE_ROAM.
# ---------------------------------------------------------------------------

func _wire_hooks() -> void:
	if context != MusicPolicy.Context.FREE_ROAM or not is_inside_tree():
		return
	var vm := get_node_or_null("/root/VehicleManager")
	if vm != null and vm.has_method("get_player_car"):
		var car: Object = vm.call("get_player_car")
		if car != null and car != _car_hooked and is_instance_valid(car) and car.has_signal("impact"):
			if not car.is_connected("impact", _on_impact):
				car.connect("impact", _on_impact)
			_car_hooked = car
	var trap := get_tree().get_first_node_in_group(SpeedTrapCrossing.GROUP_NAME)
	if trap != null and trap != _trap_hooked and trap.has_signal(SpeedTrapCrossing.SIGNAL_NAME):
		if not trap.is_connected(SpeedTrapCrossing.SIGNAL_NAME, _on_trap):
			trap.connect(SpeedTrapCrossing.SIGNAL_NAME, _on_trap)
		_trap_hooked = trap

func _on_impact(strength: float) -> void:
	notify_impact(strength)

func notify_impact(strength: float) -> void:
	if not bool(settings.get("duck", true)):
		return
	var db := MusicDucker.crash_duck_db(strength)
	if db < 0.0:
		ducker.trigger("crash", db, 0.8, 1.5)

func _on_trap(_trap_id: String, _speed: float, _best: float, _is_best: bool) -> void:
	notify_speed_trap()

func notify_speed_trap() -> void:
	if bool(settings.get("duck", true)):
		ducker.trigger("trap", MusicDucker.SPEED_TRAP_DB, MusicDucker.SPEED_TRAP_HOLD_S, 1.0)

# ---------------------------------------------------------------------------
# Persistence (slot-0 save, additive key, debounced).
# ---------------------------------------------------------------------------

func _mark_dirty(minor: bool) -> void:
	_dirty = true
	if not minor:
		_dirty_major = true
	_save_timer = SAVE_DEBOUNCE_S

## load -> mutate -> save of the slot, so unrelated keys survive. A track-change
## alone never CREATES a save file; settings changes do (like quality_preset).
func flush_settings() -> void:
	_save_timer = -1.0
	if not _dirty or not persist or not has_node("/root/SaveManager"):
		return
	if not _dirty_major and not SaveManager.has_save(persist_slot):
		_dirty = false
		return
	var data := SaveManager.load_game(persist_slot)
	SaveManager.save_game(persist_slot, MusicSettings.merge_into_save(data, settings))
	_dirty = false
	_dirty_major = false
