# scripts/ui/photo_mode_controller.gd
extends PhotoMode

## AAA-3 Photo Mode controller autoload: makes the tested PhotoMode base class
## reachable in play. Left-stick click (L3, JOY_BUTTON_LEFT_STICK = 7) freezes
## the world, hides the HUD and hands the viewport to the orbit camera; L3 again
## restores it. The same toggle is on keyboard P. Works in any scene that ships
## the OrbitCamera rig (test track, mountain pass, open world) + a HUD layer.
##
## Binding set (every action below is NEW in project.godot [input]; none collide
## with the shipped gameplay map, which uses keyboard W/A/S/D/space/E/Q/R/C/T
## and joypad buttons 0/1/3/6/8/9/11 + axes 0..5):
##   action                keyboard   PS4 button
##   photo_mode            P          L3 / left stick    (JOY_BUTTON_LEFT_STICK, 7)
##   photo_fov_up          U          R1                 (JOY_BUTTON_RIGHT_SHOULDER, 10)
##   photo_fov_down        J          D-pad Down         (JOY_BUTTON_DPAD_DOWN, 12)
##   photo_filter_cycle    I          D-pad Right        (JOY_BUTTON_DPAD_RIGHT, 14)
##   photo_toggle_ui       O          Square             (JOY_BUTTON_X, 2)
##   photo_screenshot      K          D-pad Left         (JOY_BUTTON_DPAD_LEFT, 13)
## While photo mode is ACTIVE the right stick (shared camera_orbit_left/right/
## up/down actions) free-orbits via orbit_delta(); FOV/filter/UI/screenshot
## knobs act on the photo camera; L3/P exits and restores the world exactly.
##
## Safety: every handler is a silent no-op when no orbit camera is present
## (menus) or outside photo mode — nothing spams errors, and the gdUnit gate
## sees no pause-state or render-path changes (capture_screenshot is already
## headless-guarded in the base class). Enter is additionally refused while the
## tree is already paused (the pause menu), so a frozen menu can never leak
## into a screenshot.

const ORBIT_YAW_SPEED := 2.6   # mirrors orbit_camera.gd orbit_speed_yaw
const ORBIT_PITCH_SPEED := 1.6 # mirrors orbit_camera.gd orbit_speed_pitch
const ORBIT_DEADZONE := 0.15   # mirrors orbit_camera.gd input_deadzone
const FOV_STEP := 0.05
## One physical button press can surface as several DISTINCT InputEvent objects
## (a driver echo across _input/_unhandled_input, or an emulated gamepad where
## the L3 click also lands as a keyboard event matching the same action). Without
## a debounce that one click would toggle enter() then exit() in the same
## instant — a "frozen for a blink" glitch. Any toggle within this window of the
## previous one is ignored, so one real press always toggles exactly once.
const TOGGLE_DEBOUNCE_MS := 250

var _shot_index := 0
## Same-physical-press echo guard: the identical InputEvent object can be handed
## to _input AND _unhandled_input on the same press; instance-id equality is how
## we tell "one press echoed across paths" from "two real presses in a row".
var _consumed_event_id := 0
## Frame on which the last toggle ran, so the _process poll fallback never
## double-fires a press that _input/_unhandled_input already consumed this frame.
var _toggle_frame := -1
## Wall-clock ms of the last accepted toggle (see TOGGLE_DEBOUNCE_MS). Tests
## widen this via `toggle_debounce_ms` when they need to suppress it entirely.
var _last_toggle_ms := -1
var toggle_debounce_ms := TOGGLE_DEBOUNCE_MS

func _ready() -> void:
	super._ready()
	photo_mode_unavailable.connect(func(reason: String) -> void: flash_message(_unavailable_text(reason)))

func _process(delta: float) -> void:
	# Poll fallback: the Input action state updates for EVERY parsed event before
	# the engine decides who handled it, so even an event eaten by a stray GUI
	# node or an early _input consumer still shows up here a frame later. The
	# frame guard keeps one press == one toggle across _input+_unhandled_input.
	if Input.is_action_just_pressed("photo_mode") and _toggle_frame != Engine.get_process_frames():
		_toggle()
	if not is_active():
		return
	var axis_x := Input.get_axis("camera_orbit_left", "camera_orbit_right")
	var axis_y := Input.get_axis("camera_orbit_up", "camera_orbit_down")
	if absf(axis_x) < ORBIT_DEADZONE:
		axis_x = 0.0
	if absf(axis_y) < ORBIT_DEADZONE:
		axis_y = 0.0
	if axis_x != 0.0 or axis_y != 0.0:
		orbit_delta(-axis_x * ORBIT_YAW_SPEED * delta, axis_y * ORBIT_PITCH_SPEED * delta, delta)

## Front-of-line listener: runs BEFORE the GUI and before any unhandled stage,
## so no focused Control or _input consumer can starve the L3 photo toggle.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("photo_mode"):
		_consumed_event_id = event.get_instance_id()
		_toggle_frame = Engine.get_process_frames()
		_toggle()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	var viewport := get_viewport()
	if event.is_action_pressed("photo_mode"):
		# A press already consumed by _input (same event object echoed) must not
		# double-toggle; a fresh event (direct call, or a delivery path where
		# _input never ran) toggles here normally.
		if _consumed_event_id != event.get_instance_id():
			_consumed_event_id = event.get_instance_id()
			_toggle_frame = Engine.get_process_frames()
			_toggle()
	else:
		_handle_photo_knobs(event)
	if viewport != null:
		viewport.set_input_as_handled()

func _handle_photo_knobs(event: InputEvent) -> void:
	if not is_active():
		return
	var handled := true
	if event.is_action_pressed("photo_fov_up"):
		set_fov_strength(float(get_photo_params()["fov_strength"]) + FOV_STEP)
	elif event.is_action_pressed("photo_fov_down"):
		set_fov_strength(float(get_photo_params()["fov_strength"]) - FOV_STEP)
	elif event.is_action_pressed("photo_filter_cycle"):
		_cycle_filter()
	elif event.is_action_pressed("photo_toggle_ui"):
		toggle_ui()
	elif event.is_action_pressed("photo_screenshot"):
		capture_screenshot(_shot_index)
		_shot_index += 1
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()

## Single toggle entry point for every delivery path. Entering is gated on live
## gameplay (the world running, not paused); every refusal is surfaced instead
## of silently dying. The debounce window collapses duplicate Events that a
## single physical press may produce into ONE toggle (see TOGGLE_DEBOUNCE_MS).
func _toggle() -> void:
	if toggle_debounce_ms > 0:
		var now := Time.get_ticks_msec()
		if _last_toggle_ms >= 0 and now - _last_toggle_ms < toggle_debounce_ms:
			return
		_last_toggle_ms = now
	if is_active():
		exit()
	elif _can_enter():
		enter()
	elif get_tree() != null:
		flash_message("RESUME TO ENTER PHOTO MODE")

func _unavailable_text(reason: String) -> String:
	if reason == "no_orbit_camera":
		return "PHOTO MODE UNAVAILABLE HERE"
	return "PHOTO MODE UNAVAILABLE"

## Enter only from live gameplay: the world must be running so the pause menu
## can never be frozen into a screenshot. (enter() itself still refuses when no
## orbit camera is present, which keeps the menu path a silent no-op.)
func _can_enter() -> bool:
	var tree := get_tree()
	return tree != null and not tree.paused

## Cycles the photo filter forward through FILTERS (alphabetical order),
## wrapping back to "none" after the last named grade.
func _cycle_filter() -> void:
	var names: Array = FILTERS.keys()
	names.sort()
	var idx: int = names.find(_filter)
	if idx < 0:
		idx = 0
	set_filter(str(names[(idx + 1) % names.size()]))