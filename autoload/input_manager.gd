extends Node

## Provides normalized input values for vehicle control.
## Works with both PS5 controller (via DS4Windows/XInput) and keyboard.

# --- Public API ---

func get_throttle() -> float:
    ## Returns throttle input [0.0 to 1.0].
    ## Controller: right trigger (axis 7). Keyboard: W key.
    var joy_throttle := Input.get_action_strength("throttle")
    var key_throttle := Input.get_action_strength("throttle")
    return maxf(joy_throttle, key_throttle)

func get_brake() -> float:
    ## Returns brake input [0.0 to 1.0].
    ## Controller: left trigger (axis 6). Keyboard: S key.
    var joy_brake := Input.get_action_strength("brake")
    var key_brake := Input.get_action_strength("brake")
    return maxf(joy_brake, key_brake)

func get_steer() -> float:
    ## Returns steering input [-1.0 left, 0.0 center, 1.0 right].
    ## Controller: left stick X axis. Keyboard: A/D keys.
    var joy_steer := Input.get_axis("steer_left", "steer_right")
    var key_steer := Input.get_axis("steer_left", "steer_right")
    # Prioritize joystick if it has significant input
    if absf(joy_steer) > 0.1:
        return joy_steer
    return key_steer

func is_handbrake() -> bool:
    return Input.is_action_pressed("handbrake")

func is_reset() -> bool:
    return Input.is_action_just_pressed("reset_car")

func is_pause_just_pressed() -> bool:
    return Input.is_action_just_pressed("pause")

func is_camera_mode_just_pressed() -> bool:
    return Input.is_action_just_pressed("camera_mode")

func is_any_input_active() -> bool:
    ## Returns true if any vehicle input is active (useful for AI takeover).
    return get_throttle() > 0.01 or get_brake() > 0.01 or absf(get_steer()) > 0.01

func get_raw_joy_info() -> Dictionary:
    ## Debug: returns raw joystick device info.
    var joy_name := Input.get_joy_name(0)
    var joy_guid := Input.get_joy_guid(0)
    return {"name": joy_name, "guid": joy_guid, "connected": joy_name != ""}
