# tests/suites/test_photo_mode_controller.gd
extends GdUnitTestSuite

## AAA-3 Photo Mode reachability gate: the PhotoModeController autoload script
## (scripts/ui/photo_mode_controller.gd) instantiates, inherits the base
## PROCESS_MODE_ALWAYS behaviour, wires the new photo_mode input actions into
## the project's input map without colliding with gameplay bindings, and — when
## handed an OrbitCamera rig — enters/exits photo mode from a left-stick click
## (L3, JOY_BUTTON_LEFT_STICK = 7) press through the same _unhandled_input path
## a real controller drives. Without an orbit camera the toggle is a silent
## no-op that never touches the tree pause state.

const PhotoModeControllerScript: GDScript = preload("res://scripts/ui/photo_mode_controller.gd")
const ChaseCameraScript: GDScript = preload("res://scripts/camera/chase_camera.gd")
const OrbitCameraScript: GDScript = preload("res://scripts/camera/orbit_camera.gd")

var _managed: Array = []

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	# Controller tests pause the tree in enter(); always force it back so the
	# runner and the next test never inherit a frozen world.
	get_tree().paused = false
	for entry in _managed:
		if is_instance_valid(entry):
			entry.free()
	_managed.clear()

func _new_root() -> Node:
	var root := Node.new()
	root.name = "TestRoot"
	_managed.append(root)
	add_child(root)
	return root

func _new_target(root: Node, position: Vector3) -> Node3D:
	var target := Node3D.new()
	target.position = position
	root.add_child(target)
	_managed.append(target)
	return target

## Photo rig identical to test_photo_mode.gd: target -> chase "ChaseCamera" ->
## orbit "OrbitCamera" + CanvasLayer "HUD", plus the controller under test.
func _rig_controller(root: Node, position: Vector3) -> Dictionary:
	var target := _new_target(root, position)
	var chase := ChaseCameraScript.new() as Node3D
	chase.name = "ChaseCamera"
	chase.set("target", target)
	root.add_child(chase)
	_managed.append(chase)
	var orbit := OrbitCameraScript.new() as Node3D
	orbit.name = "OrbitCamera"
	orbit.set("target", target)
	orbit.set("chase_camera_path", NodePath("../ChaseCamera"))
	root.add_child(orbit)
	_managed.append(orbit)
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	root.add_child(hud)
	_managed.append(hud)
	var controller: PhotoMode = PhotoModeControllerScript.new()
	controller.name = "PhotoController"
	root.add_child(controller)
	_managed.append(controller)
	return {"target": target, "chase": chase, "orbit": orbit, "hud": hud, "controller": controller}

## A fresh left-stick click (L3, JOY_BUTTON_LEFT_STICK = 7), exactly the event
## the action registered in project.godot matches.
func _photo_press() -> InputEventJoypadButton:
	var evt := InputEventJoypadButton.new()
	evt.button_index = JOY_BUTTON_LEFT_STICK
	evt.pressed = true
	return evt

## Gate #1: the controller script instantiates as a PhotoMode, is promoted to
## PROCESS_MODE_ALWAYS by the base _ready, and the requested photo_mode input
## action is present in the project input map with an L3 button event while
## throttle has no joypad button event.
func test_photo_controller_instantiates_and_wires_photo_mode_action() -> void:
	var root := _new_root()
	var controller: PhotoMode = PhotoModeControllerScript.new()
	controller.name = "PhotoController"
	root.add_child(controller)
	_managed.append(controller)

	assert_that(controller is PhotoMode).is_true()
	assert_that(controller.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)

	assert_that(InputMap.has_action("photo_mode")).is_true()
	var l3_bound := false
	for event in InputMap.action_get_events("photo_mode"):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_LEFT_STICK:
			l3_bound = true
	assert_that(l3_bound).is_true()

	var throttle_has_joypad_button := false
	for event in InputMap.action_get_events("throttle"):
		if event is InputEventJoypadButton:
			throttle_has_joypad_button = true
	assert_that(throttle_has_joypad_button).is_false()

## Gate #2: toggling photo mode with no orbit camera in the tree is a silent
## no-op — no crash, never active, tree pause untouched.
func test_photo_controller_toggle_safe_noop_without_orbit() -> void:
	var root := _new_root()
	var controller: PhotoMode = PhotoModeControllerScript.new()
	controller.name = "PhotoController"
	root.add_child(controller)
	_managed.append(controller)

	controller._unhandled_input(_photo_press())
	assert_that(controller.is_active()).is_false()
	assert_that(get_tree().paused).is_false()

## Gate #3: with an orbit camera + HUD in the rig, an L3 press enters photo
## mode (tree paused, HUD hidden, orbit camera current) and a second L3 press
## exits and restores all three.
func test_photo_controller_l3_press_enters_and_exits() -> void:
	var rig := _rig_controller(_new_root(), Vector3.ZERO)
	var controller: PhotoMode = rig["controller"]
	# This gate double-presses back-to-back on purpose; the real game must not
	# (a single physical click can echo as many Events). See the debounce gate.
	controller.toggle_debounce_ms = 0
	var orbit: Node3D = rig["orbit"]
	var hud: CanvasLayer = rig["hud"]
	var orbit_cam := orbit.get("_camera") as Camera3D

	assert_that(controller.is_active()).is_false()
	controller._unhandled_input(_photo_press())
	assert_that(controller.is_active()).is_true()
	assert_that(get_tree().paused).is_true()
	assert_that(hud.visible).is_false()
	assert_that(orbit_cam.is_current()).is_true()

	controller._unhandled_input(_photo_press())
	assert_that(controller.is_active()).is_false()
	assert_that(get_tree().paused).is_false()
	assert_that(hud.visible).is_true()
	assert_that(orbit_cam.is_current()).is_false()

## Gate #4: a real press flows through _input (the front-of-line path, before
## any GUI focus can swallow it) and toggles exactly once. The engine hands the
## SAME InputEvent object to _input and then _unhandled_input; the echo guard
## (instance-id) must stop the second delivery from double-toggling.
func test_photo_controller_front_of_line_input_path_toggles_once() -> void:
	var rig := _rig_controller(_new_root(), Vector3.ZERO)
	var controller: PhotoMode = rig["controller"]
	controller.toggle_debounce_ms = 0
	var orbit_cam := (rig["orbit"] as Node3D).get("_camera") as Camera3D

	var press := _photo_press()
	controller._input(press)
	assert_that(controller.is_active()).is_true()
	assert_that(get_tree().paused).is_true()

	# SAME event object echoed to _unhandled_input must NOT toggle back out.
	controller._unhandled_input(press)
	assert_that(controller.is_active()).is_true()

	# A genuinely fresh second press exits normally.
	controller._unhandled_input(_photo_press())
	assert_that(controller.is_active()).is_false()
	assert_that(get_tree().paused).is_false()
	assert_that(orbit_cam.is_current()).is_false()

## Gate #6: a single physical L3 click can surface as several DISTINCT press
## Events back-to-back (driver echo / emulated button also landing as a key).
## The debounce window must collapse all of them into ONE toggle — the enter
## must survive the burst, and only a press after the window has lapsed exits.
func test_photo_controller_duplicate_press_burst_toggles_once() -> void:
	var rig := _rig_controller(_new_root(), Vector3.ZERO)
	var controller: PhotoMode = rig["controller"]
	var orbit_cam := (rig["orbit"] as Node3D).get("_camera") as Camera3D
	controller.toggle_debounce_ms = 100000  # generous window: burst is the whole test

	# Press #1 enters photo mode.
	controller._unhandled_input(_photo_press())
	assert_that(controller.is_active()).is_true()
	assert_that(get_tree().paused).is_true()

	# Distinct duplicate presses #2..#4 (different Event objects, same physical
	# click) land inside the window and must NOT exit photo mode.
	controller._input(_photo_press())
	controller._unhandled_input(_photo_press())
	controller._unhandled_input(_photo_press())
	assert_that(controller.is_active()).is_true()
	assert_that(get_tree().paused).is_true()
	assert_that(orbit_cam.is_current()).is_true()

	# Simulate the debounce window lapsing (player presses L3 again for real):
	# only NOW does a press exit and restore the world.
	controller._last_toggle_ms = Time.get_ticks_msec() - controller.toggle_debounce_ms - 1
	controller._unhandled_input(_photo_press())
	assert_that(controller.is_active()).is_false()
	assert_that(get_tree().paused).is_false()
	assert_that(orbit_cam.is_current()).is_false()

## Gate #5: a refused entry (no orbit camera) surfaces the flash message instead
## of dead silence, and the tree pause state is never touched.
func test_photo_controller_refused_entry_flashes_instead_of_silent() -> void:
	var root := _new_root()
	var controller: PhotoMode = PhotoModeControllerScript.new()
	controller.name = "PhotoController"
	root.add_child(controller)
	_managed.append(controller)

	controller._unhandled_input(_photo_press())
	assert_that(controller.is_active()).is_false()
	assert_that(get_tree().paused).is_false()
	# The unavailable flash is the visible feedback for a refused toggle.
	assert_that((controller.get("_flash_label") as Label) != null).is_true()
	assert_that((controller.get("_flash_label") as Label).visible).is_true()