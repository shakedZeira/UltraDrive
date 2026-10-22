extends GdUnitTestSuite

func test_throttle_returns_zero_when_no_input() -> void:
    assert_that(InputManager.get_throttle()).is_equal(0.0)

func test_brake_returns_zero_when_no_input() -> void:
    assert_that(InputManager.get_brake()).is_equal(0.0)

func test_steer_returns_zero_when_no_input() -> void:
    assert_that(InputManager.get_steer()).is_equal(0.0)

func test_handbrake_returns_false_when_no_input() -> void:
    assert_that(InputManager.is_handbrake()).is_equal(false)

func test_headlight_returns_false_when_no_input() -> void:
    assert_that(InputManager.is_headlight_just_pressed()).is_equal(false)

# --- FreeRoam music actions (MusicInput) -----------------------------------

func test_music_actions_exist_with_expected_keys() -> void:
    var expected := {
        "music_next": KEY_N, "music_prev": KEY_B, "music_toggle": KEY_M,
        "music_volume_up": KEY_EQUAL, "music_volume_down": KEY_MINUS,
        "music_station_next": KEY_TAB, "music_station_prev": KEY_TAB,
    }
    for action in expected:
        assert_that(InputMap.has_action(action)).is_true()
        var key_codes: Array[int] = []
        for e in InputMap.action_get_events(action):
            if e is InputEventKey:
                key_codes.append((e as InputEventKey).physical_keycode)
        assert_that(key_codes).contains([expected[action]])

func test_music_gamepad_bindings_and_back_is_free() -> void:
    var buttons := {}
    for action in ["music_next", "music_prev", "music_toggle"]:
        for e in InputMap.action_get_events(action):
            if e is InputEventJoypadButton:
                buttons[action] = (e as InputEventJoypadButton).button_index
    assert_that(buttons["music_next"]).is_equal(JOY_BUTTON_DPAD_RIGHT)
    assert_that(buttons["music_prev"]).is_equal(JOY_BUTTON_DPAD_LEFT)
    assert_that(buttons["music_toggle"]).is_equal(JOY_BUTTON_TOUCHPAD)
    # Back (the chord modifier / DS4Windows pause tap) and the touchpad are bound
    # to nothing but the music actions' own raw handling.
    for action in InputMap.get_actions():
        if String(action).begins_with("ui_"):
            continue
        for e in InputMap.action_get_events(action):
            if e is InputEventJoypadButton:
                var idx := (e as InputEventJoypadButton).button_index
                assert_that(idx != JOY_BUTTON_BACK).is_true()
