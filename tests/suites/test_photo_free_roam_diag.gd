extends GdUnitTestSuite

const OPEN_WORLD_SCENE := "res://scenes/world/open_world_root.tscn"

var _controller: PhotoMode

func before_test() -> void:
	get_tree().paused = false
	Input.action_release("photo_mode")
	_controller = get_tree().root.get_node_or_null("PhotoModeController") as PhotoMode
	if _controller != null and _controller.is_active():
		_controller.exit()
	if _controller != null:
		_controller.toggle_debounce_ms = 0

func after_test() -> void:
	Input.action_release("photo_mode")
	_controller = get_tree().root.get_node_or_null("PhotoModeController") as PhotoMode
	if _controller != null and _controller.is_active():
		_controller.exit()
	get_tree().paused = false

func _wait_always() -> void:
	await get_tree().create_timer(0.1, true, false, true).timeout

func _process_frame_seen_while_paused() -> bool:
	var seen := [false]
	var callback := func() -> void:
		seen[0] = true
	var process_frame := get_tree().process_frame
	process_frame.connect(callback, CONNECT_ONE_SHOT)
	await _wait_always()
	var emitted := bool(seen[0])
	if process_frame.is_connected(callback):
		process_frame.disconnect(callback)
	return emitted

func _press_on_next_process_frame() -> bool:
	var just_pressed := [false]
	var callback := func() -> void:
		Input.action_press("photo_mode")
		just_pressed[0] = Input.is_action_just_pressed("photo_mode")
	var process_frame := get_tree().process_frame
	process_frame.connect(callback, CONNECT_ONE_SHOT)
	await _wait_always()
	var emitted := bool(just_pressed[0])
	if process_frame.is_connected(callback):
		process_frame.disconnect(callback)
	return emitted

func test_photo_mode_toggle_in_open_world() -> void:
	var has_photo_mode := InputMap.has_action("photo_mode")
	var has_l3 := false
	var has_p := false
	if has_photo_mode:
		for event in InputMap.action_get_events("photo_mode"):
			if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_LEFT_STICK:
				has_l3 = true
			if event is InputEventKey:
				var key_event := event as InputEventKey
				if key_event.physical_keycode == KEY_P or key_event.keycode == KEY_P:
					has_p = true
	var throttle_has_joypad_button := false
	if InputMap.has_action("throttle"):
		for event in InputMap.action_get_events("throttle"):
			if event is InputEventJoypadButton:
				throttle_has_joypad_button = true
	print("PHRD input photo_mode=", has_photo_mode, " l3=", has_l3, " p=", has_p, " throttle_joypad_button=", throttle_has_joypad_button)
	assert_bool(has_photo_mode).is_true()
	assert_bool(has_l3).is_true()
	assert_bool(has_p).is_true()
	assert_bool(throttle_has_joypad_button).is_false()

	var runner := scene_runner(OPEN_WORLD_SCENE)
	await runner.simulate_frames(2)
	var scene := runner.scene()
	assert_object(scene).is_not_null()
	if scene == null:
		return
	var orbit := scene.get_node_or_null("OrbitCamera")
	print("PHRD scene=", scene.name, " orbit_present=", orbit != null)
	assert_object(orbit).is_not_null()
	if orbit == null:
		return
	_controller = get_tree().root.get_node_or_null("PhotoModeController") as PhotoMode
	assert_object(_controller).is_not_null()
	if _controller == null:
		return
	print("PHRD controller process_mode=", _controller.process_mode, " is_processing=", _controller.is_processing())
	assert_int(_controller.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	assert_bool(_controller.is_processing()).is_true()
	var paused_before_press := get_tree().paused
	print("PHRD paused_before_press=", paused_before_press, " action_pressed_before=", Input.is_action_pressed("photo_mode"))
	assert_bool(paused_before_press).is_false()
	assert_bool(Input.is_action_pressed("photo_mode")).is_false()

	var first_frames := Engine.get_process_frames()
	Input.action_press("photo_mode")
	print("PHRD feed_pressed=", Input.is_action_pressed("photo_mode"))
	await _wait_always()
	var first_active := _controller.is_active()
	var first_paused := get_tree().paused
	var first_frame_delta := Engine.get_process_frames() - first_frames
	var frame_seen := await _process_frame_seen_while_paused() if first_active else false
	print("PHRD first_active=", first_active, " paused=", first_paused, " process_frames_delta=", first_frame_delta, " process_frame_seen_while_paused=", frame_seen, " orbit_resolved=", _controller.get_orbit_camera() != null)
	assert_bool(first_active).is_true()
	assert_bool(first_paused).is_true()

	if not first_active:
		var direct_enter_paused_before := get_tree().paused
		var direct_enter_result := _controller.enter()
		var direct_orbit := _controller.get_orbit_camera()
		var direct_orbit_name := "<null>"
		if direct_orbit != null:
			direct_orbit_name = str(direct_orbit.name)
		print("PHRD direct_enter paused_before=", direct_enter_paused_before, " result=", direct_enter_result, " active=", _controller.is_active(), " orbit=", direct_orbit_name, " paused_after=", get_tree().paused)
		assert_bool(direct_enter_result).is_true()
		assert_object(direct_orbit).is_not_null()
		assert_bool(_controller.is_active()).is_true()
		if _controller.is_active():
			_controller.exit()
		await _wait_always()

	Input.action_release("photo_mode")
	await _wait_always()
	print("PHRD after_release pressed=", Input.is_action_pressed("photo_mode"), " just_pressed=", Input.is_action_just_pressed("photo_mode"), " toggle_frame=", _controller.get("_toggle_frame"))
	var second_frames := Engine.get_process_frames()
	var second_edge_just_pressed := await _press_on_next_process_frame()
	print("PHRD feed_pressed_second=", Input.is_action_pressed("photo_mode"), " just_pressed_on_process_frame=", second_edge_just_pressed, " toggle_frame=", _controller.get("_toggle_frame"), " engine_frame=", Engine.get_process_frames())
	var second_active := _controller.is_active()
	var second_paused := get_tree().paused
	var second_frame_delta := Engine.get_process_frames() - second_frames
	print("PHRD second_active=", second_active, " paused=", second_paused, " process_frames_delta=", second_frame_delta)
	assert_bool(second_active).is_false()
	assert_bool(second_paused).is_false()
	Input.action_release("photo_mode")
	await _wait_always()
