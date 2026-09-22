extends Node

## TERRAIN REGION-CROSSING HITCH PROBE.
##
## Instantiates the open world and measures single-frame cost across Terrain3D
## 256m region boundaries, plus the TerrainSeeder's env-gated per-section
## timings (run with HITCH_TIMING=1).
##
## Two modes (user args via `--`):
##   (default) teleport windows: a control window, then a crossing window per
##     boundary line at x = 256/512/768/1024 (car settled 500m before each).
##   --drive-across [--target=1280]: car is spawned on the hub->pass connector
##     corridor (region 0,0, already baked), throttled straight +X, crossing
##     every 256m boundary at speed. Every crossing is windowed to the frames
##     around the actual boundary cross so the worst frame is per-real-crossing.
##
## The car is teleported by setting global_position directly (NOT
## WorldDriver.fast_travel_to), mirroring WorldDriver._settle_car.

const WORLD_SCENE := "res://scenes/world/open_world_root.tscn"
const SPAWN := Vector3(128.0, 2.2, 128.0)
const DRIVE_START := Vector3(8.0, 2.2, 128.0)
const REGION := 256.0
const WARMUP_SECONDS := 6.0
const WINDOW_SECONDS := 5.0
const LOOKAHEAD := 500.0
const THROTTLE := 0.55
const WARMUP_THROTTLE := 0.35
const DRIVE_THROTTLE := 0.6
const HITCH_MS := 50.0
const MAX_DRIVE_SECONDS := 50.0
const CROSS_FRAME_HALF_WINDOW := 30  # frames (0.5s @60fps) before a cross
const CROSS_FRAME_TAIL_WINDOW := 90  # frames (1.5s @60fps) after a cross
const STEADY_PADDING := 150  # frames excluded around each cross for steady stats

var _world: Node = null
var _car: Node = null
var _seeder: Node = null
var _drive_across := false
var _drive_target := 1280.0
var _phase := "warmup"
var _t := 0.0
var _window_t := 0.0
var _frame_prev_usec := -1
var _phys_prev_usec := -1
var _frame_deltas: Array = []
var _phys_deltas: Array = []
var _frame_x: Array = []
var _region_was := Vector2i(1 << 30, 1 << 30)
var _crossings: Array = []
var _stat: Dictionary = {}
var _hitch_before: Dictionary = {}

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--drive-across":
			_drive_across = true
		elif a.begins_with("--target="):
			_drive_target = float(a.trim_prefix("--target="))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	print("[hitchprobe] window=", DisplayServer.window_get_size(), " adapter=", RenderingServer.get_video_adapter_name())
	print("[hitchprobe] max_fps=", int(Engine.max_fps), " engine_ticks=", Engine.physics_ticks_per_second, " mode=", "drive" if _drive_across else "teleport")
	_world = load(WORLD_SCENE).instantiate()
	add_child(_world)
	if _seeder == null:
		_seeder = _world.get_node_or_null("TerrainSeeder")
	if _car == null:
		_car = _world.get_node_or_null("%PlayerCar")
	if _drive_across:
		_teleport(DRIVE_START)
		_phase = "drive"
		print("[hitchprobe] drive-across from ", DRIVE_START, " toward x=", _drive_target)
	else:
		_phase = "warmup"
		print("[hitchprobe] warmup ", WARMUP_SECONDS, "s at spawn")

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _frame_prev_usec > 0:
		var ms := (now - _frame_prev_usec) / 1000.0
		_frame_deltas.append(ms)
		_frame_x.append(float(_car.global_position.x) if _car != null else -1.0)
	_frame_prev_usec = now

func _physics_process(delta: float) -> void:
	_t += delta
	if _car == null:
		_car = _world.get_node_or_null("%PlayerCar")
	if _car != null and _car.has_method("set_input_override"):
		var throb := WARMUP_THROTTLE if _phase == "warmup" else (DRIVE_THROTTLE if _phase == "drive" else THROTTLE)
		_car.call("set_input_override", Vector2(0.0, throb))
	var now := Time.get_ticks_usec()
	if _phys_prev_usec > 0:
		_phys_deltas.append((now - _phys_prev_usec) / 1000.0)
	_phys_prev_usec = now
	match _phase:
		"warmup":
			if _t >= WARMUP_SECONDS:
				_start_window()
		"control":
			_window_t += delta
			if _window_t >= WINDOW_SECONDS:
				_end_window(true)
		"crossing":
			_window_t += delta
			if _window_t >= WINDOW_SECONDS:
				_end_window(true)
		"drive":
			if _car != null:
				var region := Vector2i(floori(_car.global_position.x / REGION), floori(_car.global_position.z / REGION))
				if region != _region_was:
					if _region_was != Vector2i(1 << 30, 1 << 30):
						_crossings.append({"region": region, "x": float(_car.global_position.x), "frame": _frame_deltas.size()})
					_region_was = region
				if _car.global_position.x >= _drive_target and _drive_target > 0.0:
					_end_drive()
				elif _t >= MAX_DRIVE_SECONDS:
					_end_drive()

var _window_idx := -1

func _start_window() -> void:
	_window_idx += 1
	_window_t = 0.0
	_phase = "crossing" if _window_idx > 0 else "control"
	_frame_deltas.clear()
	_phys_deltas.clear()
	_frame_x.clear()
	var label := "control" if _window_idx == 0 else "crossing"
	var target := SPAWN
	if _window_idx > 0:
		var bx: float = _boundary(_window_idx)
		target = Vector3(bx - LOOKAHEAD, SPAWN.y, SPAWN.z)
	_track_window_start()
	_teleport(target)
	print("[hitchprobe] window ", label, " idx=", _window_idx, " settle=", target, " (boundary at x=", _boundary(_window_idx) if _window_idx > 0 else -1, ")")

func _boundary(index: int) -> float:
	return REGION * float(index)

func _track_window_start() -> void:
	if _seeder != null and _seeder.has_method("reset_hitch"):
		_seeder.call("reset_hitch")
	_hitch_before = _seeder_hitch_now()

func _teleport(target: Vector3) -> void:
	if _car == null:
		return
	_car.global_position = _grounded(target)
	if _car.has_method("reset_physics_interpolation"):
		_car.call("reset_physics_interpolation")
	if _car is RigidBody3D:
		var body := _car as RigidBody3D
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	if _car is Node3D:
		if _drive_across:
			(_car as Node3D).rotation = Vector3(0.0, -PI / 2.0, 0.0)
		else:
			(_car as Node3D).rotation = Vector3.ZERO

func _grounded(target: Vector3) -> Vector3:
	if _seeder != null and _seeder.has_method("baked_region_height"):
		var loc := Vector2i(floori(target.x / REGION), floori(target.z / REGION))
		var h: float = _seeder.call("baked_region_height", loc, target)
		if h > 0.05:
			return Vector3(target.x, h, target.z)
	return target

func _end_window(valid: bool) -> void:
	_stat = _frame_stats()
	_stat["physics"] = _tick_stats()
	_stat["monitors"] = _monitors()
	_stat["hitch"] = _hitch_diff()
	_print_stats("WINDOW")
	if not _drive_across and _window_idx < 4:
		_start_window()
	else:
		_finish()

func _end_drive() -> void:
	_phase = "done"
	var steady := _steady_stats()
	var crossing_stats: Array = []
	for c in _crossings:
		crossing_stats.append(_crossing_stats(c))
	_stat = {
		"drive_total": _frame_stats(),
		"steady": steady,
		"physics": _tick_stats(),
		"monitors": _monitors(),
		"hitch": _hitch_max_ms() as Dictionary,
		"crossings": crossing_stats,
	}
	_print_stats("DRIVE")
	_finish()

func _crossing_stats(cross: Dictionary) -> Dictionary:
	var idx: int = cross["frame"]
	var lo := maxi(0, idx - CROSS_FRAME_HALF_WINDOW)
	var hi := mini(_frame_deltas.size() - 1, idx + CROSS_FRAME_TAIL_WINDOW)
	var worst := 0.0
	var phys_worst := 0.0
	var sum := 0.0
	var n := 0
	for i in range(lo, hi + 1):
		var ms: float = _frame_deltas[i]
		if ms > worst:
			worst = ms
		sum += ms
		n += 1
		phys_worst = maxf(phys_worst, float(_phys_deltas[mini(i, _phys_deltas.size() - 1)]))
	return {
		"x": roundf(float(cross["x"] * 10.0)) / 10.0,
		"region": cross["region"],
		"worst_frame_ms": snappedf(worst, 0.1),
		"phys_worst_ms": snappedf(phys_worst, 0.1),
		"avg_frame_ms": snappedf(sum / float(maxi(n, 1)), 0.1),
	}

func _steady_stats() -> Dictionary:
	var marked := {}
	for c in _crossings:
		var idx: int = c["frame"]
		for i in range(maxi(0, idx - STEADY_PADDING), mini(_frame_deltas.size() - 1, idx + STEADY_PADDING)):
			marked[i] = true
	var worst := 0.0
	var sum := 0.0
	var over := 0
	var n := 0
	for i in _frame_deltas.size():
		if marked.has(i):
			continue
		var ms: float = _frame_deltas[i]
		if ms > worst:
			worst = ms
		sum += ms
		n += 1
		if ms > HITCH_MS:
			over += 1
	return {
		"steady_avg_ms": snappedf(sum / float(maxi(n, 1)), 0.1),
		"steady_worst_ms": snappedf(worst, 0.1),
		"steady_over_50ms": over,
		"steady_n": n,
	}

func _frame_stats() -> Dictionary:
	var worst := 0.0
	var sum := 0.0
	var over := 0
	for ms: float in _frame_deltas:
		if ms > worst:
			worst = ms
		sum += ms
		if ms > HITCH_MS:
			over += 1
	var avg := sum / float(_frame_deltas.size()) if not _frame_deltas.is_empty() else 0.0
	return {"worst_frame_ms": snappedf(worst, 0.1), "avg_frame_ms": snappedf(avg, 0.1), "over_50ms": over, "n": _frame_deltas.size()}

func _tick_stats() -> Dictionary:
	var worst := 0.0
	var sum := 0.0
	for ms: float in _phys_deltas:
		if ms > worst:
			worst = ms
		sum += ms
	var avg := sum / float(_phys_deltas.size()) if not _phys_deltas.is_empty() else 0.0
	return {"worst_phys_ms": snappedf(worst, 0.1), "avg_phys_ms": snappedf(avg, 0.1), "n": _phys_deltas.size()}

func _monitors() -> Dictionary:
	var regions := 0
	if _seeder != null:
		var t: Terrain3D = _seeder.get("terrain") as Terrain3D
		if t != null and t.data != null:
			regions = t.data.get_region_locations().size()
	var avg_ms := 0.0
	if not _frame_deltas.is_empty():
		var s := 0.0
		for ms: float in _frame_deltas:
			s += ms
		avg_ms = s / float(_frame_deltas.size())
	return {
		"fps_avg": snappedf(1000.0 / maxf(avg_ms, 0.01), 0.1),
		"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.1),
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.1),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"prims": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"vram_mb": snappedf(float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0, 0.1),
		"live_regions": regions,
	}

func _seeder_hitch_now() -> Dictionary:
	return _seeder.call("hitch_max_ms") if _seeder != null and _seeder.has_method("hitch_max_ms") else {}

func _hitch_max_ms() -> Dictionary:
	return _seeder.call("hitch_max_ms") if _seeder != null and _seeder.has_method("hitch_max_ms") else {}

func _hitch_diff() -> Dictionary:
	var after := _seeder_hitch_now()
	var diff: Dictionary = {}
	for key in after:
		var before: float = float(_hitch_before.get(key, 0.0))
		var v: float = float(after[key])
		if v > before:
			diff[key] = snappedf(v - before, 0.01)
	return diff

func _print_stats(tag: String) -> void:
	var sep := "================================================"
	print("[hitchprobe] ", sep)
	print("[hitchprobe] ", tag, "  (across ", _crossings.size(), " real boundary crossings)")
	if _stat.has("crossings"):
		for c in _stat["crossings"]:
			var cw: Dictionary = c
			print("[hitchprobe]   cross x=", cw["x"], " region=", cw["region"], " worst_frame_ms=", cw["worst_frame_ms"], " phys_worst_ms=", cw["phys_worst_ms"], " avg_frame_ms=", cw["avg_frame_ms"])
	for key in _stat:
		if key == "crossings":
			continue
		if key == "hitch":
			print("[hitchprobe]   hitch:")
			for hk in _stat["hitch"]:
				print("[hitchprobe]     ", hk, "=", _stat["hitch"][hk])
		elif key == "monitors":
			print("[hitchprobe]   monitors:")
			for mk in _stat["monitors"]:
				print("[hitchprobe]     ", mk, "=", _stat["monitors"][mk])
		else:
			print("[hitchprobe]   ", key, "=", _stat[key])

func _finish() -> void:
	print("[hitchprobe] DONE")
	get_tree().quit()