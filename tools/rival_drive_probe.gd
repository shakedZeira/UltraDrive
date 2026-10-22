extends SceneTree

## Headless rival-driving probe: loads a track scene, starts a real
## `RaceManager` race with a rival roster, simulates it on a fixed timestep and
## reports, per rival, laps completed, lap times, time spent per surface key,
## mean speed per surface, worst lateral excursion from the centerline, time off
## the road and stuck-recovery latches. Used to check that AI rivals complete
## laps sensibly on mixed surfaces (Barcelona RX dirt).
##
## RUN (headless is fine -- physics only; --fixed-fps makes it deterministic and
## faster than real time):
##   <godot_console> --headless --fixed-fps 60 --path . -s res://tools/rival_drive_probe.gd -- \
##       --scene=res://scenes/track/barcelona_rx.tscn --rivals=4 --laps=3 --max_s=420
##
## Autoloads are reached through /root (bare autoload identifiers do not compile
## in `-s` mode), and no autoload-dependent class (VehiclePhysics, RivalDriver)
## is named here for the same reason -- everything goes through call()/get().

const STARTER_CAR := "res://resources/cars/starter_car.tres"
const TIERS: Array[String] = ["Expert", "Skilled", "Novice", "Skilled", "Expert", "Novice", "Skilled", "Expert"]

var _scene_path := "res://scenes/track/barcelona_rx.tscn"
var _rivals := 4
var _laps := 3
var _max_s := 420.0
var _width := 12.0

var _scene: Node = null
var _rm: Node = null
var _cars: Array[Node] = []
var _line: Array[Vector3] = []
var _t := 0.0
var _started := false
var _frames := 0
var _stats: Array[Dictionary] = []
var _done := false


func _initialize() -> void:
	_watch_start()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			_scene_path = arg.substr(8)
		elif arg.begins_with("--rivals="):
			_rivals = clampi(int(arg.substr(9)), 1, 8)
		elif arg.begins_with("--laps="):
			_laps = maxi(int(arg.substr(7)), 1)
		elif arg.begins_with("--max_s="):
			_max_s = float(arg.substr(8))
		elif arg.begins_with("--width="):
			_width = float(arg.substr(8))
	var packed := load(_scene_path) as PackedScene
	_scene = packed.instantiate()
	root.add_child(_scene)
	_rm = root.get_node_or_null("/root/RaceManager")
	print("PROBE scene=", _scene_path, " rivals=", _rivals, " laps=", _laps)


func _physics_process(delta: float) -> bool:
	if _watch_tripped():
		return true
	if _done:
		return true
	_frames += 1
	if _frames == 5:
		_start()
		return false
	if not _started:
		return false
	_t += delta
	for i in _cars.size():
		_sample(i, delta)
	var finished := not bool(_rm.get("is_race_active"))
	if finished or _t >= _max_s:
		_report(finished)
		_done = true
		quit(0)
	return false


func _start() -> void:
	var player: Node = _scene.get_node_or_null("%PlayerCar")
	if player == null:
		player = _scene.get_node_or_null("PlayerCar")
	_line.assign(_rm.get("rival_centerline"))
	var cfg := load(STARTER_CAR)
	var specs: Array = []
	for i in _rivals:
		specs.append({"car_config": cfg, "tier": TIERS[i % TIERS.size()]})
	_rm.call("set_rival_roster", specs)
	# The player car parks: freeze it on the grid so only rivals race.
	_rm.call("start_race", [player], _laps)
	if player is RigidBody3D:
		(player as RigidBody3D).freeze = true
	for car in _rm.call("get_spawned_rivals"):
		_cars.append(car)
		_stats.append({
			"tier": "", "surf_t": {}, "surf_v": {}, "max_off": 0.0, "off_t": 0.0,
			"recover_n": 0, "was_recovering": false, "laps": [], "last_lap_t": 0.0,
		})
	for i in _cars.size():
		var driver := _driver_of(_cars[i])
		_stats[i]["tier"] = String(driver.get("skill_tier")) if driver != null else "?"
		var counter: Node = _rm.call("get_lap_counter", _cars[i])
		if counter != null:
			counter.connect("lap_completed", _on_lap.bind(i))
	_started = true
	print("PROBE started rivals=", _cars.size(), " centerline=", _line.size())


func _on_lap(_car: Node, lap: int, time: float, index: int) -> void:
	var st: Dictionary = _stats[index]
	(st["laps"] as Array).append(snappedf(time, 0.01))
	print("PROBE lap rival=%d tier=%s lap=%d time=%.2f t=%.1f" % [index, st["tier"], lap, time, _t])


func _sample(i: int, delta: float) -> void:
	var car := _cars[i] as RigidBody3D
	if car == null or not is_instance_valid(car):
		return
	var st: Dictionary = _stats[i]
	var key := String(car.call("get_surface_key"))
	var speed := Vector2(car.linear_velocity.x, car.linear_velocity.z).length()
	var surf_t: Dictionary = st["surf_t"]
	var surf_v: Dictionary = st["surf_v"]
	surf_t[key] = float(surf_t.get(key, 0.0)) + delta
	surf_v[key] = float(surf_v.get(key, 0.0)) + speed * delta
	var off := _lateral(car.global_position)
	st["max_off"] = maxf(float(st["max_off"]), off)
	if off > _width * 0.5 + 1.0:
		st["off_t"] = float(st["off_t"]) + delta
	var driver := _driver_of(car)
	if driver != null:
		var rec := bool(driver.call("is_recovering"))
		if rec and not bool(st["was_recovering"]):
			st["recover_n"] = int(st["recover_n"]) + 1
		st["was_recovering"] = rec


func _lateral(pos: Vector3) -> float:
	var best := INF
	var n := _line.size()
	for j in n:
		var a := _line[j]
		var b := _line[(j + 1) % n]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var ap := Vector2(pos.x - a.x, pos.z - a.z)
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 0.0001 else clampf(ap.dot(ab) / l2, 0.0, 1.0)
		best = minf(best, (ap - ab * t).length())
	return best


func _driver_of(car: Node) -> Node:
	for child in car.get_children():
		if child.has_method("get_pace_multiplier"):
			return child
	return null


func _report(finished: bool) -> void:
	print("PROBE end t=%.1f finished=%s" % [_t, str(finished)])
	for i in _cars.size():
		var st: Dictionary = _stats[i]
		var parts: PackedStringArray = []
		var surf_t: Dictionary = st["surf_t"]
		var surf_v: Dictionary = st["surf_v"]
		for key in surf_t.keys():
			var tt := float(surf_t[key])
			parts.append("%s %.1fs @%.1fkmh" % [key, tt, float(surf_v[key]) / maxf(tt, 0.001) * 3.6])
		print("PROBE rival=%d tier=%s laps=%s max_off=%.1fm off_road=%.1fs recover=%d | %s" % [
			i, st["tier"], str(st["laps"]), float(st["max_off"]), float(st["off_t"]),
			int(st["recover_n"]), ", ".join(parts)])


## --- fail-fast watchdog -----------------------------------------------------
## Never let a capture hang: a hard wall-clock cap (--max_wall_s, default
## 600 s) and an abort when the SAME error repeats (a per-frame error loop, e.g.
## a spawner instantiating a scene whose script failed to compile) or when any
## script fails to compile. Both quit with exit code 3. The shell side must STILL
## wrap the run in `timeout`, because a frozen main loop never reaches _process.
const WATCH_REPEAT_LIMIT := 25

class FailFastLogger extends Logger:
	var counts: Dictionary = {}
	var abort_reason := ""

	func _log_error(_function: String, file: String, line: int, message: String,
			_rationale: String, _editor_notify: bool, error_type: int,
			_script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		var key := "%s:%d %s" % [file, line, message]
		var n := int(counts.get(key, 0)) + 1
		counts[key] = n
		if abort_reason.is_empty():
			if message.contains("Compile Error") or message.contains("Parse Error") 					or message.contains("Failed to compile"):
				abort_reason = "script compile error: " + key
			elif n >= WATCH_REPEAT_LIMIT:
				abort_reason = "error repeated %d x: %s" % [n, key]

	func _log_message(_message: String, _error: bool) -> void:
		pass

var _watch := FailFastLogger.new()
var _max_wall_s := 600.0
var _wall_start_ms := 0


func _watch_start() -> void:
	_wall_start_ms = Time.get_ticks_msec()
	OS.add_logger(_watch)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--max_wall_s="):
			_max_wall_s = float(arg.substr(13))


## True (and quits with exit 3) when the run must abort.
func _watch_tripped() -> bool:
	var reason := _watch.abort_reason
	if reason.is_empty() and float(Time.get_ticks_msec() - _wall_start_ms) / 1000.0 > _max_wall_s:
		reason = "wall-clock cap %.0f s exceeded" % _max_wall_s
	if reason.is_empty():
		return false
	print("PROBE ABORT: ", reason)
	OS.remove_logger(_watch)
	quit(3)
	return true
