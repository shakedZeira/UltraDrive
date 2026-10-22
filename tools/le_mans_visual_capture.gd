extends SceneTree

## Automated Le Mans visual capture + per-view frame-cost probe for the P4
## vision critique (docs/plans/le_mans_visual_realism_plan.md §6).
##
## RUN (windowed, NOT --headless — the capture reads
## `root.get_texture().get_image()`, which needs a real render target):
##   <godot_console> --path . -s res://tools/le_mans_visual_capture.gd -- --tag=after --preset=1
## or tools\le_mans_capture_run.bat. Keep APPDATA on D: so `user://` stays off C:.
##
## User args (after `--`):
##   --tag=<name>     file prefix, default "shot"  -> lemans_<tag>_<view>.png
##   --preset=<0..2>  quality preset pushed through
##                    SettingsMenuScript.apply_to_scene_tree, exactly like
##                    GameState does on a scene change (default 1 = Medium,
##                    the discrete-GPU first-boot preset)
##   --perf_frames=N  frames timed per view after the shutter (default 90)
##
## WHY A FREE CAMERA: the earlier revision teleported the player RigidBody3D and
## relied on the chase camera following it. Setting `global_position` on a
## physics body that the controller/physics server immediately re-integrates is
## not reliable, and every one of its seven PNGs actually showed the S/F line.
## A dedicated Camera3D placed from `LeMansLayout.frame_at_arc` (the same frame
## math le_mans.gd spawns from) cannot drift. The player car is hidden so it
## never occludes the trackside being critiqued.
##
## Output: res://.vision/captures/lemans_<tag>_<view>.png (1920x1080) plus a
## `PERF view=... avg_ms=... p95_ms=... prims=... draws=...` line per view.

const TRACK := "res://scenes/track/le_mans.tscn"
const OUT_DIR := "res://.vision/captures"
## Loaded at RUNTIME, not preloaded: settings_menu.gd references the GameState
## autoload, which is not yet registered when a `-s` script is compiled.
const SETTINGS_MENU_PATH := "res://scripts/ui/settings_menu.gd"

const WARMUP_FRAMES := 60
const SETTLE_FRAMES := 30
## Camera rig: metres above the road surface, metres right of the centerline,
## and how far down the road it looks.
const CAM_HEIGHT := 2.2
const CAM_LATERAL := 1.5
const LOOK_AHEAD_M := 60.0
const LOOK_HEIGHT := 0.8

var _views: Array[Dictionary] = []
var _tag := "shot"
var _preset := 1
var _perf_frames := 90

var _scene: Node = null
var _cam: Camera3D = null
var _frames := 0
var _view_i := -1
var _phase := ""
var _phase_frames := 0
var _frame_us: PackedInt64Array = PackedInt64Array()
var _last_us := 0
var _busy := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			_tag = arg.substr(6)
		elif arg.begins_with("--preset="):
			_preset = clampi(int(arg.substr(9)), 0, 2)
		elif arg.begins_with("--perf_frames="):
			_perf_frames = maxi(int(arg.substr(14)), 0)

	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.title = "UltraDrive LeMans capture"

	# Chainage = where the CAMERA stands; it looks LOOK_AHEAD_M down the road.
	_views = [
		{"label": "sf", "chainage": 13560.0},
		{"label": "dunlop", "chainage": 700.0},
		{"label": "tertre_rouge", "chainage": 1790.0},
		{"label": "hunaudieres", "chainage": 4000.0},
		{"label": "mulsanne", "chainage": 7410.0},
		{"label": "indianapolis", "chainage": 9570.0},
		{"label": "arnage", "chainage": 9915.0},
		{"label": "porsche_curves", "chainage": 11300.0},
		{"label": "ford_chicane", "chainage": 13000.0},
		# Close-ups (optional keys: height, out = eye lateral toward the corner's
		# OUTSIDE, ahead = look distance, look_out / look_h = target offsets).
		{"label": "tertre_trap", "chainage": 1840.0, "height": 1.7, "out": 4.0,
			"ahead": 28.0, "look_out": 11.0, "look_h": 0.0},
		{"label": "arnage_brake", "chainage": 9925.0, "height": 1.15, "out": 2.0,
			"ahead": 30.0, "look_out": 1.0, "look_h": -0.4},
		{"label": "ford_kerbs", "chainage": 13050.0, "height": 1.4, "out": 0.0,
			"ahead": 22.0, "look_out": -3.0, "look_h": 0.0},
		# Elevation reads (real SRTM profile): long look-aheads along the grades
		# and one raised view over the Dunlop climb.
		{"label": "dunlop_climb", "chainage": 150.0, "height": 1.6, "ahead": 450.0, "look_h": 0.5},
		{"label": "esses_descent", "chainage": 1000.0, "height": 1.6, "ahead": 350.0, "look_h": 0.0},
		{"label": "indy_descent", "chainage": 9150.0, "height": 1.6, "ahead": 420.0, "look_h": 0.0},
		{"label": "porsche_rise", "chainage": 12250.0, "height": 1.6, "ahead": 600.0, "look_h": 0.5},
		{"label": "aerial_dunlop", "chainage": 60.0, "height": 45.0, "out": 0.0,
			"ahead": 700.0, "look_h": 0.0},
	]

	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)

	var track := load(TRACK) as PackedScene
	if track == null:
		print("CAPTURE ERROR: cannot load ", TRACK)
		quit(1)
		return
	_scene = track.instantiate()
	root.add_child(_scene)

	# Hide 2D overlays and the player car: the critique is of the WORLD.
	for node in _all(_scene):
		if node is CanvasLayer:
			(node as CanvasLayer).visible = false
	var car := _scene.get_node_or_null("%PlayerCar") as Node3D
	if car != null:
		car.visible = false
		car.process_mode = Node.PROCESS_MODE_DISABLED

	_cam = Camera3D.new()
	_cam.name = "CaptureCamera"
	_cam.fov = 70.0
	_cam.far = 6000.0
	_scene.add_child(_cam)
	print("CAPTURE ready: ", _views.size(), " views tag=", _tag, " preset=", _preset)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		# Same call GameState makes one frame after a scene change.
		var settings: GDScript = load(SETTINGS_MENU_PATH)
		settings.call("apply_to_scene_tree", _preset, _scene, root)
		_cam.make_current()
	if _busy:
		return false
	if _view_i < 0:
		if _frames >= WARMUP_FRAMES:
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


func _next_view() -> void:
	_view_i += 1
	if _view_i >= _views.size():
		print("CAPTURE DONE")
		quit(0)
		return
	var view: Dictionary = _views[_view_i]
	var arc := LeMansLayout.arc_at_chainage(float(view["chainage"]))
	var look_ahead: float = float(view.get("ahead", LOOK_AHEAD_M))
	var here := LeMansLayout.frame_at_arc(arc)
	var ahead := LeMansLayout.frame_at_arc(arc + look_ahead)
	var c: Vector3 = here["center"]
	var f: Vector3 = here["forward"]
	var right := f.cross(Vector3.UP).normalized()
	# Outside of the corner ahead (+1 = right), from the dressing's own probe.
	var outside := 1.0
	var dressing := _scene.get_node_or_null("Dressing")
	if dressing != null:
		outside = float(dressing.call("_outside_side", arc + look_ahead))
	var lateral: float = CAM_LATERAL
	if view.has("out"):
		lateral = outside * float(view["out"])
	var eye := c + Vector3.UP * float(view.get("height", CAM_HEIGHT)) + right * lateral
	var af: Vector3 = ahead["forward"]
	var aright := af.cross(Vector3.UP).normalized()
	var target: Vector3 = (ahead["center"] as Vector3) + Vector3.UP * float(view.get("look_h", LOOK_HEIGHT)) \
		+ aright * (outside * float(view.get("look_out", 0.0)))
	_cam.global_position = eye
	_cam.look_at(target, Vector3.UP)
	_phase = "settle"
	_phase_frames = 0
	print("CAPTURE view ", view["label"], " chainage=", view["chainage"], " eye=", eye)


func _shutter() -> void:
	await RenderingServer.frame_post_draw
	var view: Dictionary = _views[_view_i]
	var img := root.get_texture().get_image()
	if img == null or img.is_empty():
		print("CAPTURE ERROR: empty frame for ", view["label"])
	else:
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		var file := "lemans_%s_%s.png" % [_tag, view["label"]]
		var path := ProjectSettings.globalize_path(OUT_DIR + "/" + file)
		var err := img.save_png(path)
		print("CAPTURE ", file, " size=", img.get_size(), " err=", err, " -> ", path)
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
	print("PERF view=%s avg_ms=%.2f p95_ms=%.2f prims=%d draws=%d" % [view["label"], avg_ms, p95_ms, prims, draws])


func _all(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_all(child))
	return out
