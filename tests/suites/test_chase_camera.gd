# tests/suites/test_chase_camera.gd
extends GdUnitTestSuite

## Chase-camera presentation pass (Task 8: M3): follow/fov still converge with
## defaults (transients off), and the transient extras (speed look-ahead,
## gear-shift FOV kick) behave deterministically when transients_enabled is
## true. Frames are driven directly through _update_camera — no physics loop.

const ChaseCameraScript: GDScript = preload("res://scripts/camera/chase_camera.gd")

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

func _new_camera(root: Node, cam_target: Node3D) -> Node3D:
	var cam := ChaseCameraScript.new() as Node3D
	cam.set("target", cam_target)
	_managed.append(cam)
	root.add_child(cam)
	return cam

func _fov(cam: Node3D) -> float:
	return (cam.get("_camera") as Camera3D).fov

func test_default_camera_converges_and_fov_stays_in_range() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)
	var cam := _new_camera(root, target)
	for i in range(180):
		cam.call("_update_camera", 1.0 / 60.0)
	var dist: float = float(cam.get("camera_distance"))
	var height: float = float(cam.get("camera_height"))
	var ideal := target.global_position \
		+ target.global_basis.z * dist \
		+ Vector3.UP * height
	assert_that(cam.global_position.distance_to(ideal)).is_less(0.5)
	assert_that(_fov(cam)).is_greater_equal(float(cam.get("fov_min")))
	assert_that(_fov(cam)).is_less_equal(float(cam.get("fov_max")))

func test_speed_look_ahead_biases_camera_and_trails_moving_target() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)
	var plain := _new_camera(root, target)
	var lead := _new_camera(root, target)
	lead.set("transients_enabled", true)
	lead.set("debug_speed_kmh", 200.0)
	lead.set("look_ahead_strength", 1.0)
	for i in range(180):
		plain.call("_update_camera", 1.0 / 60.0)
		lead.call("_update_camera", 1.0 / 60.0)
	# Static target: same follow position (shake is zero for a static target)...
	assert_that(lead.global_position.distance_to(plain.global_position)).is_less(0.05)
	# ...but the camera looks further forward (toward the car's -z facing) at speed.
	var plain_forward: Vector3 = -(plain.get("_camera") as Camera3D).global_transform.basis.z
	var lead_forward: Vector3 = -(lead.get("_camera") as Camera3D).global_transform.basis.z
	assert_that(lead_forward.z).is_less(plain_forward.z)
	# Moving target: the chase keeps the camera trailing along the +z (behind) axis.
	var dist: float = float(lead.get("camera_distance"))
	var height: float = float(lead.get("camera_height"))
	for i in range(60):
		target.position += Vector3(0.0, 0.0, -0.5)
		lead.call("_update_camera", 1.0 / 60.0)
	var ideal := target.global_position + target.global_basis.z * dist + Vector3.UP * height
	assert_that(lead.global_position.z - ideal.z).is_greater(0.0)

func test_gear_upshift_kicks_fov_then_decays() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)
	var cam := _new_camera(root, target)
	cam.set("transients_enabled", true)
	cam.set("debug_speed_kmh", 200.0)
	cam.set("debug_gear", 1)
	cam.set("fov_kick_amount", 8.0)
	for i in range(120):
		cam.call("_update_camera", 1.0 / 60.0)
	var fov_max: float = float(cam.get("fov_max"))
	assert_that(_fov(cam)).is_greater_equal(fov_max - 0.5)
	# Upshift 1 -> 3: FOV briefly rises above fov_max...
	cam.set("debug_gear", 3)
	cam.call("_update_camera", 1.0 / 60.0)
	var fov_kicked: float = _fov(cam)
	assert_that(fov_kicked).is_greater(fov_max)
	# ...then decays back toward the speed FOV.
	for i in range(60):
		cam.call("_update_camera", 1.0 / 60.0)
	var fov_after: float = _fov(cam)
	assert_that(fov_after).is_less(fov_kicked)
	assert_that(fov_after).is_less_equal(fov_max + 0.5)

func test_defaults_unchanged_when_transients_off() -> void:
	var root := _new_root()
	var cam := _new_camera(root, null)
	assert_that(cam.get("transients_enabled")).is_false()
	assert_that(cam.get("follow_speed")).is_equal(5.0)
	assert_that(cam.get("camera_distance")).is_equal(6.0)
	assert_that(cam.get("camera_height")).is_equal(2.5)
	assert_that(cam.get("fov_min")).is_equal(70.0)
	assert_that(cam.get("fov_max")).is_equal(90.0)
	assert_that(cam.get("fov_speed_factor")).is_equal(0.05)
	assert_that(_fov(cam)).is_equal(70.0)