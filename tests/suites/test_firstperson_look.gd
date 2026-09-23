# tests/suites/test_firstperson_look.gd
extends GdUnitTestSuite

## F6 player look-around gate ("make the hood,first person view be able to look
## around with the joystick just like the regular outside of car view"): the
## HOOD and COCKPIT cameras now sweep the view around on the same camera_orbit_*
## right-stick actions as ORBIT. The look rotates the camera basis ON TOP of the
## body (yaw about up, pitch about right), never moves the rigid anchor / seat
## offset, clamps pitch, zeroes below the deadzone, resets to forward on
## activation, and the orbit camera only grabs ORBIT from CHASE (in first person
## the stick is look-around, not a mode eject). Look lives on an apply_look()
## seam exactly like cycle_mode_for_test / debug_* — frames are driven directly,
## no physics loop, no real Input events.

const ChaseCameraScript: GDScript = preload("res://scripts/camera/chase_camera.gd")
const OrbitCameraScript: GDScript = preload("res://scripts/camera/orbit_camera.gd")
const HoodCameraScript: GDScript = preload("res://scripts/camera/hood_camera.gd")
const CockpitCameraScript: GDScript = preload("res://scripts/camera/cockpit_camera.gd")

var _managed: Array = []

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	for node in _managed:
		if is_instance_valid(node):
			node.free()
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

func _new_hood_camera(root: Node, cam_target: Node3D) -> Node3D:
	var cam := HoodCameraScript.new() as Node3D
	cam.set("target", cam_target)
	cam.set("debug_speed_kmh", 0.0)
	_managed.append(cam)
	root.add_child(cam)
	return cam

func _new_cockpit_camera(root: Node, cam_target: Node3D) -> Node3D:
	var cam := CockpitCameraScript.new() as Node3D
	cam.set("target", cam_target)
	cam.set("debug_speed_kmh", 0.0)
	_managed.append(cam)
	root.add_child(cam)
	return cam

func _look_yaw(cam: Node3D) -> float:
	return float(cam.call("get_look_yaw"))

func _look_pitch(cam: Node3D) -> float:
	return float(cam.call("get_look_pitch"))

## Hood look-around: the stick integrates yaw/pitch at the exported speeds, the
## basis becomes the body basis rotated by (yaw about up, pitch about right) —
## and the ANCHOR POSITION does not move a millimetre (bob is 0 at standstill).
func test_hood_look_rotates_basis_and_leaves_anchor_position_fixed() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)
	target.global_rotation = Vector3(0.0, deg_to_rad(25.0), 0.0)
	var cam := _new_hood_camera(root, target)
	cam.call("_update_camera", 1.0 / 60.0)
	var anchor_before := cam.call("get_hood_anchor") as Vector3

	for i in range(20):
		cam.call("apply_look", -1.0, 1.0, 1.0 / 60.0)
		cam.call("_update_camera", 1.0 / 60.0)

	var yaw := _look_yaw(cam)
	var pitch := _look_pitch(cam)
	var elapsed := 20.0 / 60.0
	assert_that(yaw).is_equal_approx(float(cam.get("look_speed_yaw")) * elapsed, 0.001)
	assert_that(pitch).is_equal_approx(float(cam.get("look_speed_pitch")) * elapsed, 0.001)

	# Look must never move the rigid anchor: the camera still sits ON the hood.
	assert_that(cam.global_position.distance_to(anchor_before)).is_less(0.001)

	# Basis = body basis with yaw about UP and pitch about RIGHT (positive look
	# pitch looks UP -> .rotated(RIGHT, -pitch), same sign coupling as ORBIT).
	var expected := target.global_basis.rotated(Vector3.UP, yaw).rotated(Vector3.RIGHT, -pitch)
	assert_that(cam.global_basis.x.distance_to(expected.x)).is_less(0.0001)
	assert_that(cam.global_basis.y.distance_to(expected.y)).is_less(0.0001)
	assert_that(cam.global_basis.z.distance_to(expected.z)).is_less(0.0001)

## Cockpit look-around with every feel layer hot (max lean/shake/dive/look-into-
## turn at 200 kmh): the look rotates the view but two twins with identical
## feel input and only the look differing produce IDENTICAL eye positions — the
## composition order is body -> feel layers -> player look (look is the outer
## rotation on the post-feel basis), so roll/pitch caps and the yaw hint are
## untouched by the player's head.
func test_cockpit_look_rotates_basis_and_leaves_seat_offset_fixed() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)
	var a := _new_cockpit_camera(root, target)
	var b := _new_cockpit_camera(root, target)
	for c in [a, b]:
		c.set("steer_lean_strength", 1.0)
		c.set("pitch_strength", 1.0)
		c.set("shake_strength", 1.0)
		c.set("look_turn_strength", 1.0)
		c.set("debug_speed_kmh", 200.0)
		c.set("debug_steer_deg", 25.0)
		c.set("debug_throttle", 1.0)
		c.set("debug_brake", 0.5)

	for i in range(60):
		a.call("apply_look", 0.6, 0.4, 1.0 / 60.0)
		a.call("_update_camera", 1.0 / 60.0)
		b.call("_update_camera", 1.0 / 60.0)

	# Same feel, same frames: look NEVER moves the eye (anchor + shake/lateral).
	assert_that(a.global_position).is_equal_approx(b.global_position, Vector3(0.0001, 0.0001, 0.0001))
	# ...but it rotates the view well off the look-free feel basis.
	assert_that(a.global_basis.z.distance_to(b.global_basis.z)).is_greater(0.01)

	# Composition order pinned: a == b's feel basis then yaw about up, pitch
	# about right (outer rotations on the post-feel frame).
	var expected := b.global_basis.rotated(Vector3.UP, _look_yaw(a)).rotated(Vector3.RIGHT, -_look_pitch(a))
	assert_that(a.global_basis.x.distance_to(expected.x)).is_less(0.0001)
	assert_that(a.global_basis.z.distance_to(expected.z)).is_less(0.0001)

## Pitch clamps at pitch_min/pitch_max and yaw runs free (full 360) — the same
## clamp contract on both first-person cameras.
func _assert_pitch_clamps_and_yaw_free(cam: Node3D) -> void:
	for i in range(300):
		cam.call("apply_look", 0.0, 1.0, 1.0 / 60.0)
	assert_that(_look_pitch(cam)).is_equal(float(cam.get("pitch_max")))
	for i in range(600):
		cam.call("apply_look", 0.0, -1.0, 1.0 / 60.0)
	assert_that(_look_pitch(cam)).is_equal(float(cam.get("pitch_min")))
	var before := _look_yaw(cam)
	cam.call("apply_look", 1.0, 0.0, 1.0 / 60.0)
	assert_that(_look_yaw(cam)).is_less(before)
	for i in range(500):
		cam.call("apply_look", 1.0, 0.0, 1.0 / 60.0)
	assert_that(_look_yaw(cam)).is_less(before - 5.0)  # ~21 rad, never clamped

func test_hood_look_pitch_clamps_and_yaw_runs_free() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)
	_assert_pitch_clamps_and_yaw_free(_new_hood_camera(root, target))

func test_cockpit_look_pitch_clamps_and_yaw_runs_free() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)
	_assert_pitch_clamps_and_yaw_free(_new_cockpit_camera(root, target))

## Deadzone: axis values at or below input_deadzone are ignored independently,
## so a gentle nudge can't drift the view.
func test_look_respects_input_deadzone() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)
	var cam := _new_hood_camera(root, target)
	var dz := float(cam.get("input_deadzone"))
	cam.call("apply_look", dz * 0.5, dz * 0.5, 1.0 / 60.0)
	assert_that(_look_yaw(cam)).is_equal(0.0)
	assert_that(_look_pitch(cam)).is_equal(0.0)
	cam.call("apply_look", dz * 2.0, 0.0, 1.0 / 60.0)
	assert_that(_look_yaw(cam)).is_not_equal(0.0)
	assert_that(_look_pitch(cam)).is_equal(0.0)

## Defaults preserve today's behaviour: with no look input the hood keeps
## mirroring the body basis exactly and the cockpit's feel composition is
## numerically unchanged (both converge to the plain body basis at standstill).
func test_look_defaults_preserve_body_basis_behavior() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)
	target.global_rotation = Vector3(0.0, deg_to_rad(30.0), 0.0)

	var hood := _new_hood_camera(root, target)
	var cockpit := _new_cockpit_camera(root, target)
	for i in range(30):
		hood.call("apply_look", 0.0, 0.0, 1.0 / 60.0)
		hood.call("_update_camera", 1.0 / 60.0)
		cockpit.call("apply_look", 0.0, 0.0, 1.0 / 60.0)
		cockpit.call("_update_camera", 1.0 / 60.0)
		assert_that(hood.global_basis.z.distance_to(target.global_basis.z)).is_less(0.0001)
		assert_that(cockpit.global_basis.z.distance_to(target.global_basis.z)).is_less(0.0001)
	assert_that(_look_yaw(hood)).is_equal(0.0)
	assert_that(_look_pitch(hood)).is_equal(0.0)
	assert_that(_look_yaw(cockpit)).is_equal(0.0)
	assert_that(_look_pitch(cockpit)).is_equal(0.0)

## Entering a first-person view resets the look to forward so you never resume
## facing backwards; leaving the view does not matter (activation always wins).
func test_look_resets_to_forward_on_view_activation() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)
	for cls in [HoodCameraScript, CockpitCameraScript]:
		var cam := cls.new() as Node3D
		cam.set("target", target)
		_managed.append(cam)
		root.add_child(cam)
		cam.call("set_view_active", true)
		cam.call("apply_look", -1.0, 1.0, 1.0 / 60.0)
		cam.call("apply_look", 0.0, 0.0, 1.0 / 60.0)
		assert_that(_look_yaw(cam)).is_not_equal(0.0)
		cam.call("set_view_active", false)
		cam.call("set_view_active", true)
		assert_that(_look_yaw(cam)).is_equal(0.0)
		assert_that(_look_pitch(cam)).is_equal(0.0)

## Orbit mode-grab decision (the predicate the _physics_process branch runs):
## the right stick grabs ORBIT only from CHASE. In HOOD/COCKPIT the stick is the
## first-person look-around input, so the grab must NOT arm there — no mode
## eject on stick while the first-person views own the wheel.
func test_orbit_stick_grab_arms_only_from_chase() -> void:
	var root := _new_root()
	var chase := ChaseCameraScript.new() as Node3D
	chase.name = "ChaseCamera"
	_managed.append(chase)
	root.add_child(chase)
	var hood := HoodCameraScript.new() as Node3D
	hood.name = "HoodCamera"
	_managed.append(hood)
	root.add_child(hood)
	var cockpit := CockpitCameraScript.new() as Node3D
	cockpit.name = "CockpitCamera"
	_managed.append(cockpit)
	root.add_child(cockpit)
	var orbit := OrbitCameraScript.new() as Node3D
	orbit.name = "OrbitCamera"
	orbit.set("chase_camera_path", NodePath("../ChaseCamera"))
	orbit.set("hood_camera_path", NodePath("../HoodCamera"))
	orbit.set("cockpit_camera_path", NodePath("../CockpitCamera"))
	_managed.append(orbit)
	root.add_child(orbit)

	assert_that(orbit.call("_stick_should_grab_orbit")).is_true()  # CHASE default
	orbit.call("cycle_mode_for_test")
	assert_that(orbit.call("_stick_should_grab_orbit")).is_false()  # ORBIT
	orbit.call("cycle_mode_for_test")
	assert_that(orbit.call("_stick_should_grab_orbit")).is_false()  # HOOD
	orbit.call("cycle_mode_for_test")
	assert_that(orbit.call("_stick_should_grab_orbit")).is_false()  # COCKPIT
	orbit.call("cycle_mode_for_test")
	assert_that(orbit.call("_stick_should_grab_orbit")).is_true()  # CHASE again