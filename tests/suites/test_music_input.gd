# tests/suites/test_music_input.gd
extends GdUnitTestSuite

## MusicInput: keyboard actions, D-pad prev/next (not in photo mode / pause menu),
## touchpad click, Back TAP (the DS4Windows path), Back-chord volume / station,
## and the InputMap contract (actions exist, no collisions with driving buttons).

func _joy(button: int, pressed: bool) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = pressed
	return e

func _key(keycode: Key, shift: bool = false, pressed: bool = true) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = keycode
	e.keycode = keycode
	e.shift_pressed = shift
	e.pressed = pressed
	return e

func _cmds(r: Dictionary) -> Array:
	return r["commands"]

# --- gamepad -------------------------------------------------------------

func test_dpad_left_right_are_previous_and_next_and_consumed() -> void:
	var m := MusicInput.new()
	var left := m.interpret(_joy(MusicInput.JOY_DPAD_LEFT, true), 1.0)
	assert_that(_cmds(left)).is_equal(["prev"])
	assert_that(left["consume"]).is_true()
	var right := m.interpret(_joy(MusicInput.JOY_DPAD_RIGHT, true), 1.1)
	assert_that(_cmds(right)).is_equal(["next"])
	assert_that(m.interpret(_joy(MusicInput.JOY_DPAD_RIGHT, false), 1.2)["commands"]).is_empty()

func test_dpad_is_ignored_in_photo_mode_and_while_paused() -> void:
	var m := MusicInput.new()
	for button in [MusicInput.JOY_DPAD_LEFT, MusicInput.JOY_DPAD_RIGHT]:
		var photo := m.interpret(_joy(button, true), 1.0, {"photo": true})
		assert_that(_cmds(photo)).is_empty()
		assert_that(photo["consume"]).is_false()
		var paused := m.interpret(_joy(button, true), 1.0, {"paused": true})
		assert_that(_cmds(paused)).is_empty()
		assert_that(paused["consume"]).is_false()

func test_touchpad_click_toggles_pause() -> void:
	var m := MusicInput.new()
	var r := m.interpret(_joy(MusicInput.JOY_TOUCHPAD, true), 2.0)
	assert_that(_cmds(r)).is_equal(["toggle"])
	assert_that(r["consume"]).is_true()
	assert_that(_cmds(m.interpret(_joy(MusicInput.JOY_TOUCHPAD, false), 2.1))).is_empty()

func test_back_tap_toggles_pause_on_release() -> void:
	var m := MusicInput.new()
	assert_that(_cmds(m.interpret(_joy(MusicInput.JOY_BACK, true), 5.0))).is_empty()
	assert_that(m.back_held()).is_true()
	var up := m.interpret(_joy(MusicInput.JOY_BACK, false), 5.2)
	assert_that(_cmds(up)).is_equal(["toggle"])
	assert_that(m.back_held()).is_false()

func test_back_hold_longer_than_a_tap_does_not_toggle() -> void:
	var m := MusicInput.new()
	m.interpret(_joy(MusicInput.JOY_BACK, true), 5.0)
	assert_that(_cmds(m.interpret(_joy(MusicInput.JOY_BACK, false), 5.0 + MusicInput.TAP_MAX_S + 0.05))).is_empty()

func test_back_chord_volume_and_station_do_not_leave_a_tap() -> void:
	var m := MusicInput.new()
	m.interpret(_joy(MusicInput.JOY_BACK, true), 1.0)
	var up := m.interpret(_joy(MusicInput.JOY_DPAD_UP, true), 1.05)
	assert_that(_cmds(up)).is_equal(["vol_up"])
	assert_that(up["consume"]).is_true()
	assert_that(_cmds(m.interpret(_joy(MusicInput.JOY_DPAD_DOWN, true), 1.1))).is_equal(["vol_down"])
	assert_that(_cmds(m.interpret(_joy(MusicInput.JOY_RIGHT_SHOULDER, true), 1.15))).is_equal(["station_next"])
	# released well inside the tap window, but a chord was used: no pause toggle
	assert_that(_cmds(m.interpret(_joy(MusicInput.JOY_BACK, false), 1.2))).is_empty()
	# a following plain tap works again
	m.interpret(_joy(MusicInput.JOY_BACK, true), 3.0)
	assert_that(_cmds(m.interpret(_joy(MusicInput.JOY_BACK, false), 3.1))).is_equal(["toggle"])

func test_dpad_up_down_without_back_do_nothing_here() -> void:
	var m := MusicInput.new()
	for button in [MusicInput.JOY_DPAD_UP, MusicInput.JOY_DPAD_DOWN, MusicInput.JOY_RIGHT_SHOULDER]:
		var r := m.interpret(_joy(button, true), 1.0)
		assert_that(_cmds(r)).is_empty()
		assert_that(r["consume"]).is_false()

func test_back_chord_is_ignored_in_photo_mode() -> void:
	var m := MusicInput.new()
	m.interpret(_joy(MusicInput.JOY_BACK, true), 1.0)
	var r := m.interpret(_joy(MusicInput.JOY_DPAD_UP, true), 1.1, {"photo": true})
	assert_that(_cmds(r)).is_empty()
	assert_that(r["consume"]).is_false()

func test_dpad_left_right_with_back_held_do_not_skip_tracks() -> void:
	var m := MusicInput.new()
	m.interpret(_joy(MusicInput.JOY_BACK, true), 1.0)
	assert_that(_cmds(m.interpret(_joy(MusicInput.JOY_DPAD_LEFT, true), 1.1))).is_empty()

# --- keyboard ------------------------------------------------------------

func test_keyboard_actions() -> void:
	var m := MusicInput.new()
	assert_that(_cmds(m.interpret(_key(KEY_N), 0.0))).is_equal(["next"])
	assert_that(_cmds(m.interpret(_key(KEY_B), 0.0))).is_equal(["prev"])
	assert_that(_cmds(m.interpret(_key(KEY_M), 0.0))).is_equal(["toggle"])
	assert_that(_cmds(m.interpret(_key(KEY_EQUAL), 0.0))).is_equal(["vol_up"])
	assert_that(_cmds(m.interpret(_key(KEY_MINUS), 0.0))).is_equal(["vol_down"])
	assert_that(_cmds(m.interpret(_key(KEY_TAB), 0.0))).is_equal(["station_next"])
	assert_that(_cmds(m.interpret(_key(KEY_TAB, true), 0.0))).is_equal(["station_prev"])
	assert_that(_cmds(m.interpret(_key(KEY_Y), 0.0))).is_equal(["info"])

func test_keyboard_ignores_release_echo_and_other_keys() -> void:
	var m := MusicInput.new()
	assert_that(_cmds(m.interpret(_key(KEY_N, false, false), 0.0))).is_empty()
	var echo := _key(KEY_N)
	echo.echo = true
	assert_that(_cmds(m.interpret(echo, 0.0))).is_empty()
	assert_that(_cmds(m.interpret(_key(KEY_W), 0.0))).is_empty()
	assert_that(_cmds(m.interpret(InputEventMouseButton.new(), 0.0))).is_empty()

func test_keys_are_never_consumed() -> void:
	var m := MusicInput.new()
	assert_that(m.interpret(_key(KEY_N), 0.0)["consume"]).is_false()

# --- InputMap contract ---------------------------------------------------

func test_actions_exist_in_the_input_map() -> void:
	for action in MusicInput.ACTIONS:
		assert_that(InputMap.has_action(action)).is_true()

func _first_key(action: String) -> int:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return (e as InputEventKey).physical_keycode
	return 0

func _joy_buttons(action: String) -> Array[int]:
	var out: Array[int] = []
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			out.append((e as InputEventJoypadButton).button_index)
	return out

func test_default_keys_and_buttons() -> void:
	assert_that(_first_key("music_next")).is_equal(KEY_N)
	assert_that(_first_key("music_prev")).is_equal(KEY_B)
	assert_that(_first_key("music_toggle")).is_equal(KEY_M)
	assert_that(_first_key("music_volume_up")).is_equal(KEY_EQUAL)
	assert_that(_first_key("music_volume_down")).is_equal(KEY_MINUS)
	assert_that(_first_key("music_station_next")).is_equal(KEY_TAB)
	assert_that(_first_key("music_station_prev")).is_equal(KEY_TAB)
	assert_that(_first_key("music_info")).is_equal(KEY_Y)
	assert_that(_joy_buttons("music_next")).is_equal([14])
	assert_that(_joy_buttons("music_prev")).is_equal([13])
	assert_that(_joy_buttons("music_toggle")).is_equal([JOY_BUTTON_TOUCHPAD])
	assert_that(JOY_BUTTON_TOUCHPAD).is_equal(20)
	assert_that(JOY_BUTTON_BACK).is_equal(MusicInput.JOY_BACK)

func test_music_buttons_do_not_collide_with_driving_buttons() -> void:
	# Driving / camera actions read these joypad buttons every frame; the music
	# actions may only share the D-pad L/R with the photo actions (photo mode
	# only) and must never touch face buttons, shoulders, START or L3.
	var driving: Array[String] = ["headlight", "handbrake", "shift_down", "shift_up", "pause", "reset_car", "camera_mode", "replay_capture"]
	var music_buttons: Array[int] = []
	for action in MusicInput.ACTIONS:
		music_buttons.append_array(_joy_buttons(action))
	for action in driving:
		if not InputMap.has_action(action):
			continue
		for b in _joy_buttons(action):
			assert_that(music_buttons.has(b)).is_false()
	assert_that(MusicInput.JOY_BACK).is_not_equal(6) # START = pause
	for action in InputMap.get_actions():
		if String(action).begins_with("ui_") or String(action).begins_with("music_"):
			continue
		assert_that(_joy_buttons(action).has(MusicInput.JOY_BACK)).is_false()
		assert_that(_joy_buttons(action).has(JOY_BUTTON_TOUCHPAD)).is_false()
