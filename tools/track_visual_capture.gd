extends SceneTree

## Generic per-track visual capture + per-view frame-cost probe (any scene whose
## road is built by `TrackBuilder`). The Le Mans tool
## (`tools/le_mans_visual_capture.gd`) is the landmark-chainage specialisation;
## this one needs nothing but the scene path, so it covers Sunset Oval, Mountain
## Pass, Northern Isle, Barcelona RX and the open world.
##
## RUN (windowed, NOT --headless -- the capture reads the root viewport texture):
##   <godot_console> --path . -s res://tools/track_visual_capture.gd -- \
##       --scene=res://scenes/track/barcelona_rx.tscn --name=barcelona --tag=after
##
## User args (after `--`):
##   --scene=<res path>   scene to instantiate (required)
##   --name=<label>       file prefix (default "track")
##   --tag=<label>        second prefix, e.g. before/after (default "shot")
##   --out=<abs dir>      output dir (default res://.vision/captures)
##   --preset=<0..2>      quality preset, applied like GameState does (default 1)
##   --views=<N>          evenly spaced stations along the longest road (default 4)
##   --arcs=a,b,c         explicit stations as metres of arc along that road
##                        (overrides --views; Barcelona: its public chainage)
##   --warmup=<frames>    frames before the first view (default 90; open world
##                        wants more while terrain streams in)
##   --perf_frames=<N>    frames timed per view after the shutter (default 60)
##
## Every station is shot twice: `<i>_eye` (2.2 m up, 1.5 m right of centre,
## looking 45 m down the road -- what a chase camera sees) and `<i>_high` (an
## 18 m oblique over the road's right side, the view that shows the road's own
## shading against the ground under the sun).
##
## The road is found WITHOUT knowing the scene: every `TrackBuilder` in the
## tree, longest `_track_points` wins (a scene with a `RoadNetwork` and the test
## circuit's bare builder both work). Open world: the stations are taken on the
## road nearest the player car instead, since terrain only streams around it.
## The player car is hidden and frozen so it never occludes the critique.

const SETTINGS_MENU_PATH := "res://scripts/ui/settings_menu.gd"
const SETTLE_FRAMES := 30
const EYE_HEIGHT := 2.2
const EYE_LATERAL := 1.5
const LOOK_AHEAD_M := 45.0
const HIGH_HEIGHT := 18.0
const HIGH_LATERAL := 16.0
const HIGH_LOOK_AHEAD_M := 30.0

var _scene_path := ""
var _name := "track"
var _tag := "shot"
var _out_dir := "res://.vision/captures"
var _preset := 1
var _view_count := 4
var _arcs := PackedFloat32Array()
var _warmup := 90
var _perf_frames := 60

var _scene: Node = null
var _cam: Camera3D = null
var _points: Array[Vector3] = []
var _arc_of: PackedFloat32Array = PackedFloat32Array()
var _closed := true
var _views: Array[Dictionary] = []
var _frames := 0
var _view_i := -1
var _phase := ""
var _phase_frames := 0
var _frame_us := PackedInt64Array()
var _last_us := 0
var _busy := false


func _initialize() -> void:
	_watch_start()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			_scene_path = arg.substr(8)
		elif arg.begins_with("--name="):
			_name = arg.substr(7)
		elif arg.begins_with("--tag="):
			_tag = arg.substr(6)
		elif arg.begins_with("--out="):
			_out_dir = arg.substr(6)
		elif arg.begins_with("--preset="):
			_preset = clampi(int(arg.substr(9)), 0, 2)
		elif arg.begins_with("--views="):
			_view_count = maxi(int(arg.substr(8)), 1)
		elif arg.begins_with("--arcs="):
			for part in arg.substr(7).split(","):
				_arcs.append(float(part))
		elif arg.begins_with("--warmup="):
			_warmup = maxi(int(arg.substr(9)), 10)
		elif arg.begins_with("--perf_frames="):
			_perf_frames = maxi(int(arg.substr(14)), 0)

	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.title = "UltraDrive track capture"
	DirAccess.make_dir_recursive_absolute(_abs_out())

	var packed := load(_scene_path) as PackedScene
	if packed == null:
		print("CAPTURE ERROR: cannot load ", _scene_path)
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)
	for node in _all(_scene):
		if node is CanvasLayer:
			(node as CanvasLayer).visible = false
	_cam = Camera3D.new()
	_cam.name = "CaptureCamera"
	_cam.fov = 70.0
	_cam.far = 4000.0
	_scene.add_child(_cam)
	print("CAPTURE ready scene=", _scene_path, " tag=", _tag, " preset=", _preset)


func _process(_delta: float) -> bool:
	if _watch_tripped():
		return true
	_frames += 1
	if _frames == 2:
		var settings: GDScript = load(SETTINGS_MENU_PATH)
		settings.call("apply_to_scene_tree", _preset, _scene, root)
	if _busy:
		return false
	if _view_i < 0:
		if _frames >= _warmup:
			if not _plan_views():
				print("CAPTURE ERROR: no TrackBuilder road found")
				quit(1)
				return false
			_cam.make_current()
			_next_view()
		return false
	match _phase:
		"settle":
			_phase_frames += 1
			if _phase_frames >= SETTLE_FRAMES:
				_busy = true
				_shutter()
		"perf":
			var now := Time.get_ticks_usec()
			if _last_us > 0:
				_frame_us.append(now - _last_us)
			_last_us = now
			_phase_frames += 1
			if _phase_frames >= _perf_frames:
				_report_perf()
				_next_view()
	return false


## Picks the road and the stations. Done after warm-up so scenes that build
## their road a few frames late (or stream it, the open world) are ready.
func _plan_views() -> bool:
	var car := _find_player_car()
	var car_pos := Vector3.ZERO
	if car != null:
		car_pos = car.global_position
		car.visible = false
		car.process_mode = Node.PROCESS_MODE_DISABLED
	var best: Node = null
	var best_score := -INF
	var open_world := _scene_path.contains("open_world")
	for node in _all(_scene):
		if not (node is TrackBuilder):
			continue
		var pts: Array = node.get("_track_points")
		if pts.size() < 3:
			continue
		var score := float(pts.size())
		if open_world:
			score = -_nearest_dist(pts, car_pos)
		if score > best_score:
			best_score = score
			best = node
	if best == null:
		return false
	var raw: Array = best.get("_track_points")
	for p: Vector3 in raw:
		_points.append((best as Node3D).global_transform * p)
	_closed = bool(best.get("_track_closed"))
	_arc_of.resize(_points.size())
	var acc := 0.0
	for i in _points.size():
		_arc_of[i] = acc
		if i + 1 < _points.size():
			acc += _points[i].distance_to(_points[i + 1])
	var total := acc
	var stations := PackedFloat32Array()
	if not _arcs.is_empty():
		stations = _arcs
	elif open_world:
		# Keep every station on the road: a player parked at the end of an open road
		# would otherwise clamp all views onto one spot.
		var start := minf(_arc_of[_nearest_index(car_pos)], maxf(0.0, total - 60.0 * float(_view_count - 1)))
		for i in _view_count:
			stations.append(clampf(start + 60.0 * float(i), 0.0, total))
	else:
		for i in _view_count:
			stations.append(total * float(i) / float(_view_count))
	for i in stations.size():
		_views.append({"label": "%d_eye" % i, "arc": stations[i], "high": false})
		_views.append({"label": "%d_high" % i, "arc": stations[i], "high": true})
	print("CAPTURE road points=", _points.size(), " length=", total, " stations=", stations)
	return true


func _next_view() -> void:
	_view_i += 1
	if _view_i >= _views.size():
		print("CAPTURE DONE")
		quit(0)
		return
	var view: Dictionary = _views[_view_i]
	var arc: float = view["arc"]
	var here := _frame_at(arc)
	var high: bool = view["high"]
	var ahead := _frame_at(arc + (HIGH_LOOK_AHEAD_M if high else LOOK_AHEAD_M))
	var c: Vector3 = here["center"]
	var r: Vector3 = here["right"]
	var eye := c + Vector3.UP * EYE_HEIGHT + r * EYE_LATERAL
	var target: Vector3 = (ahead["center"] as Vector3) + Vector3.UP * 0.8
	if high:
		eye = c + Vector3.UP * HIGH_HEIGHT + r * HIGH_LATERAL
		target = ahead["center"] as Vector3
	_cam.global_position = eye
	_cam.look_at(target, Vector3.UP)
	_phase = "settle"
	_phase_frames = 0
	print("CAPTURE view ", view["label"], " arc=", arc, " eye=", eye)


## Interpolated centerline frame at `arc` metres (wrapping on a closed road).
func _frame_at(arc: float) -> Dictionary:
	var n := _points.size()
	var total := _arc_of[n - 1] + (_points[n - 1].distance_to(_points[0]) if _closed else 0.0)
	var s := fposmod(arc, total) if _closed else clampf(arc, 0.0, _arc_of[n - 1])
	var i := 0
	while i + 1 < n and _arc_of[i + 1] <= s:
		i += 1
	var j := (i + 1) % n if _closed else mini(i + 1, n - 1)
	var seg := _points[i].distance_to(_points[j])
	var t := 0.0 if seg < 0.0001 else clampf((s - _arc_of[i]) / seg, 0.0, 1.0)
	var center := _points[i].lerp(_points[j], t)
	var forward := (_points[j] - _points[i]).normalized()
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	return {"center": center, "forward": forward, "right": forward.cross(Vector3.UP).normalized()}


func _shutter() -> void:
	await RenderingServer.frame_post_draw
	var view: Dictionary = _views[_view_i]
	var img := root.get_texture().get_image()
	if img == null or img.is_empty():
		print("CAPTURE ERROR: empty frame for ", view["label"])
	else:
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		var file := "%s_%s_%s.png" % [_name, _tag, view["label"]]
		var path := _abs_out().path_join(file)
		var err := img.save_png(path)
		print("CAPTURE ", file, " err=", err, " -> ", path)
	_phase = "perf"
	_phase_frames = 0
	_frame_us = PackedInt64Array()
	_last_us = 0
	_busy = false


func _report_perf() -> void:
	var view: Dictionary = _views[_view_i]
	if _frame_us.is_empty():
		return
	var sorted := _frame_us.duplicate()
	sorted.sort()
	var total := 0
	for us in sorted:
		total += us
	var avg_ms := float(total) / float(sorted.size()) / 1000.0
	var p95_ms := float(sorted[int(float(sorted.size() - 1) * 0.95)]) / 1000.0
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	print("PERF track=%s view=%s avg_ms=%.2f p95_ms=%.2f prims=%d draws=%d" % [_name, view["label"], avg_ms, p95_ms, prims, draws])


func _abs_out() -> String:
	if _out_dir.begins_with("res://") or _out_dir.begins_with("user://"):
		return ProjectSettings.globalize_path(_out_dir)
	return _out_dir


func _find_player_car() -> Node3D:
	var car := _scene.get_node_or_null("%PlayerCar") as Node3D
	if car != null:
		return car
	# RigidBody3D, not VehiclePhysics: naming that class here would compile
	# vehicle_physics.gd (which uses the RaceManager autoload) before the
	# autoloads are registered, the `-s` trap.
	for node in _all(_scene):
		if node is RigidBody3D:
			return node as Node3D
	return null


func _nearest_index(pos: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in _points.size():
		var d := Vector2(_points[i].x - pos.x, _points[i].z - pos.z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


func _nearest_dist(pts: Array, pos: Vector3) -> float:
	var best_d := INF
	for p: Vector3 in pts:
		best_d = minf(best_d, Vector2(p.x - pos.x, p.z - pos.z).length())
	return best_d


func _all(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_all(child))
	return out


## --- fail-fast watchdog -----------------------------------------------------
## Never let a capture hang: a hard wall-clock cap (--max_wall_s, default
## 240 s) and an abort when the SAME error repeats (a per-frame error loop, e.g.
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
var _max_wall_s := 240.0
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
	print("CAPTURE ABORT: ", reason)
	OS.remove_logger(_watch)
	quit(3)
	return true
