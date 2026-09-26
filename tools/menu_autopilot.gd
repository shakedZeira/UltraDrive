# TEMP diagnostic: drives the real boot path and clicks menu buttons.
extends Node

const MENU_PATH := "res://scenes/ui/main_menu.tscn"
const TARGET_AFTER_PLAY := "res://scenes/ui/track_select.tscn"

var _frames := 0
var _phase := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_bootstrap")

func _bootstrap() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	print("[AUTOP] booting main.tscn; current_scene=", get_tree().current_scene)

func _process(_delta: float) -> void:
	_frames += 1
	match _phase:
		0:
			_await_menu()
		1:
			_click_phase()
		2:
			_await_target_after_play()
		3:
			_quit_phase()
		_:
			pass

func _await_menu() -> void:
	if _frames < 120:
		return
	var scene: Node = get_tree().current_scene
	if scene == null or scene.name != "MainMenu":
		print("[AUTOP] still on ", scene, " at frame ", _frames)
		return
	print("[AUTOP] MainMenu is live at frame ", _frames)
	print("[AUTOP] SceneTransition._transitioning = ", SceneTransition.get("_transitioning"))
	_frames = 0
	_phase = 1

func _click_phase() -> void:
	if _frames == 3:
		print("[AUTOP] current_scene=", get_tree().current_scene)
		_dump_menu_state()
	if _frames == 30:
		_inject_click("PlayButton")
		print("[AUTOP] click injected on PlayButton")
	if _frames == 60:
		var scene: Node = get_tree().current_scene
		print("[AUTOP] after play click current_scene=", scene, " transitioning=", SceneTransition.get("_transitioning"))
		_frames = 0
		_phase = 2

func _await_target_after_play() -> void:
	var scene: Node = get_tree().current_scene
	if _frames == 1:
		print("[AUTOP] poll start scene=", scene)
	if scene != null and scene.scene_file_path == TARGET_AFTER_PLAY:
		print("[AUTOP] SUCCESS: track_select reached")
		_frames = 0
		_phase = 3
		return
	if _frames > 180:
		print("[AUTOP] FAIL: never reached track_select (scene=", scene, ")")
		print("[AUTOP] transitioning=", SceneTransition.get("_transitioning"))
		get_tree().quit(2)

func _quit_phase() -> void:
	if _frames == 3:
		_inject_click("QuitButton")
		print("[AUTOP] click injected on QuitButton")
	if _frames > 60:
		print("[AUTOP] FAIL: game did not quit after QuitButton click")
		get_tree().quit(3)

func _inject_click(button_name: String) -> void:
	var menu := get_tree().current_scene
	if menu == null:
		print("[AUTOP] no current scene to click into")
		return
	var btn := menu.get_node_or_null("MenuLayout/" + button_name) as Button
	if btn == null:
		print("[AUTOP] button not found: ", button_name)
		return
	if btn.disabled:
		print("[AUTOP] button IS DISABLED: ", button_name)
	print("[AUTOP] ", button_name, " disabled=", btn.disabled, " visible=", btn.visible, " focus=", btn.has_focus())
	var local_center := btn.size / 2.0
	var window_pos: Vector2 = btn.get_screen_transform() * local_center
	print("[AUTOP] ", button_name, " canvas center=", btn.get_global_rect().get_center(), " window pos=", window_pos)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = window_pos
	press.global_position = window_pos
	Input.parse_input_event(press)
	await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = window_pos
	release.global_position = window_pos
	Input.parse_input_event(release)

func _dump_menu_state() -> void:
	var menu := get_tree().current_scene
	if menu == null:
		return
	for child: Node in menu.get_children():
		if child is Control:
			var c := child as Control
			print("[AUTOP] ", child.name, " type=", child.get_class(), " mouse_filter=", c.mouse_filter)
		for sub: Node in child.get_children():
			if sub is Button:
				var b := sub as Button
				print("[AUTOP]   ", sub.name, " disabled=", b.disabled, " focus_mode=", b.focus_mode)
	print("[AUTOP] overlay check: root children: ")
	for child: Node in get_tree().root.get_children():
		print("[AUTOP]   /", child.name, " type=", child.get_class())
