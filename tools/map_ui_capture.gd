extends Node

## Dev capture of the three 2D map screens: race-menu circuit map, HUD minimap,
## and the pause world map. Saves PNGs of the main viewport.
##
## Usage (windowed, NOT headless):
##   godot --path . res://tools/map_ui_capture.tscn -- --tag=after --what=menu|world --out=<dir>

var tag := "shot"
var what := "menu"
var out_dir := "user://"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.trim_prefix("--tag=")
		elif a.begins_with("--what="):
			what = a.trim_prefix("--what=")
		elif a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	if not out_dir.ends_with("/"):
		out_dir += "/"
	call_deferred("_run")

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir + "%s_%s.png" % [tag, shot_name])
	print("[cap] saved ", shot_name, " ", img.get_size())

func _run() -> void:
	if what == "menu":
		await _menu()
	else:
		await _world()
	get_tree().quit(0)

func _menu() -> void:
	var scene: TrackSelect = load("res://scenes/ui/track_select.tscn").instantiate()
	add_child(scene)
	await _frames(20)
	await _shot("menu_israel")
	scene.set_region("world")
	await _frames(10)
	await _shot("menu_world")
	scene.set_region("europe")
	await _frames(10)
	await _shot("menu_europe")
	scene.select_pin("home_northern_isle")
	await _frames(10)
	await _shot("menu_israel_sel")
	var tm: TrackMap = scene.track_map
	tm.zoom_by(2.5, tm.size * 0.5)
	await _frames(10)
	await _shot("menu_israel_zoom")
	# Time-based focus animation (if any) needs real frames to settle.
	await _frames(40)
	await _shot("menu_israel_zoom_settled")

func _world() -> void:
	var world: Node = load("res://scenes/world/open_world_root.tscn").instantiate()
	add_child(world)
	var t0 := Time.get_ticks_msec()
	await _frames(240)
	print("[cap] world warmed ", Time.get_ticks_msec() - t0)
	await _shot("hud_minimap")
	var pm: PauseMenu = world.get_node("PauseMenu/Menu")
	GameState.pause_game()
	await _frames(10)
	pm._on_map_pressed()
	await _frames(30)
	await _shot("pause_map")
	var wm: WorldMap = pm.world_map
	wm.set_route_destination(Vector3(3000, 0, 1200))
	await _frames(20)
	await _shot("pause_map_route")
	wm.clear_route()
	# Real input path: wheel zoom, drag pan, hover, right-click GPS.
	var centre := wm.get_global_rect().get_center()
	for i in 3:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		wheel.position = centre
		Input.parse_input_event(wheel)
		await _frames(2)
	var motion := InputEventMouseMotion.new()
	motion.position = centre + Vector2(60.0, 20.0)
	Input.parse_input_event(motion)
	await _frames(60)
	print("[cap] zoom after wheel=", wm.get_zoom())
	await _shot("pause_map_zoom")
	var rc := InputEventMouseButton.new()
	rc.button_index = MOUSE_BUTTON_RIGHT
	rc.pressed = true
	rc.position = centre + Vector2(120.0, 80.0)
	Input.parse_input_event(rc)
	await _frames(20)
	await _shot("pause_map_zoom_route")
	wm.clear_route()
	GameState.resume_game()
