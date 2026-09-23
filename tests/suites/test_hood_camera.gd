# tests/suites/test_hood_camera.gd
extends GdUnitTestSuite

## S14 hood camera gate: rigid attach to the car hood (no lag), speed FOV bump
## to the hood target, bounded speed-based head bob, deterministic chase/orbit/
## hood C-cycle, and the windshield forward-view gate covering chase + hood.
## Frames are driven directly through _update_camera / cycle_mode_for_test —
## no physics loop, no real Input events.

const ChaseCameraScript: GDScript = preload("res://scripts/camera/chase_camera.gd")
const OrbitCameraScript: GDScript = preload("res://scripts/camera/orbit_camera.gd")
const HoodCameraScript: GDScript = preload("res://scripts/camera/hood_camera.gd")

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
	_managed.append(cam)
	root.add_child(cam)
	return cam

func _fov(cam: Node3D) -> float:
	return (cam.get("_camera") as Camera3D).fov

func _bob(cam: Node3D) -> Vector3:
	return cam.call("get_bob_offset") as Vector3

## Rigid attach: the camera sits on the computed hood anchor (no lerp, no lag),
## mirrors the body basis (heading/pitch/roll), and re-snaps in a single frame
## even after the car has moved.
func test_hood_rigidly_tracks_hood_anchor() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)
	var cam := _new_hood_camera(root, target)
	cam.set("debug_speed_kmh", 0.0)
	target.global_rotation = Vector3(0.0, deg_to_rad(25.0), 0.0)

	var forward: float = float(cam.get("hood_forward"))
	var height: float = float(cam.get("hood_height"))
	var ideal := target.global_position - target.global_basis.z * forward + Vector3.UP * height

	for i in range(120):
		cam.call("_update_camera", 1.0 / 60.0)
		assert_that(cam.global_position.distance_to(ideal)).is_less(0.001)
		assert_that(cam.global_basis.z.distance_to(target.global_basis.z)).is_less(0.0001)

	# The car drives forward (-z) 0.5 m/frame: the next frame lands on the NEW
	# anchor — the hood cam must NOT trail behind like the lerped chase cam.
	for i in range(5):
		target.global_position -= target.global_basis.z * 0.5
		var moved_ideal := target.global_position - target.global_basis.z * forward + Vector3.UP * height
		cam.call("_update_camera", 1.0 / 60.0)
		assert_that(cam.global_position.distance_to(moved_ideal)).is_less(0.001)

## FOV bumps from fov_min (70) at standstill toward fov_max (75) at speed,
## smoothed exactly like chase's lerp-follow.
func test_hood_fov_bumps_with_speed_and_trims_at_standstill() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)

	var fast := _new_hood_camera(root, target)
	fast.set("debug_speed_kmh", 200.0)
	for i in range(120):
		fast.call("_update_camera", 1.0 / 60.0)
	assert_that(fast.call("get_hood_fov")).is_greater_equal(74.9)
	assert_that(fast.call("get_hood_fov")).is_less_equal(float(fast.get("fov_max")))

	var still := _new_hood_camera(root, target)
	still.set("debug_speed_kmh", 0.0)
	for i in range(120):
		still.call("_update_camera", 1.0 / 60.0)
	assert_that(still.call("get_hood_fov")).is_equal_approx(float(still.get("fov_min")), 0.001)

## Head bob: amplitude grows with speed (same phase sequence for a fair
## comparison), stays bounded well under the ~0.03 m cap, and is exactly zero
## at standstill.
func test_head_bob_bounded_scales_with_speed_and_zero_at_standstill() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)
	var cap: float = 0.03

	var fast := _new_hood_camera(root, target)
	fast.set("debug_speed_kmh", 200.0)
	var slow := _new_hood_camera(root, target)
	slow.set("debug_speed_kmh", 100.0)
	for i in range(120):
		fast.call("_update_camera", 1.0 / 60.0)
		slow.call("_update_camera", 1.0 / 60.0)
		var bob: Vector3 = _bob(fast)
		assert_that(bob.length()).is_less_equal(cap)
		assert_that(absf(bob.x)).is_less_equal(cap)
		assert_that(absf(bob.y)).is_less_equal(cap)
		var slow_bob: Vector3 = _bob(slow)
		assert_that(slow_bob.length()).is_less(_bob(fast).length())

	var still := _new_hood_camera(root, target)
	still.set("debug_speed_kmh", 0.0)
	for i in range(30):
		still.call("_update_camera", 1.0 / 60.0)
	assert_that(_bob(still).length()).is_equal(0.0)

func _cam_current(camera_node: Node3D) -> bool:
	return (camera_node.get("_camera") as Camera3D).current

## The C-cycle is deterministic and testable without Input events:
## CHASE -> ORBIT -> HOOD -> CHASE, exactly one camera current per mode.
func test_mode_cycle_flips_camera_ownership_deterministically() -> void:
	var root := _new_root()
	var chase := ChaseCameraScript.new() as Node3D
	chase.name = "ChaseCamera"
	_managed.append(chase)
	root.add_child(chase)
	var hood := HoodCameraScript.new() as Node3D
	hood.name = "HoodCamera"
	_managed.append(hood)
	root.add_child(hood)
	var orbit := OrbitCameraScript.new() as Node3D
	orbit.name = "OrbitCamera"
	orbit.set("chase_camera_path", NodePath("../ChaseCamera"))
	orbit.set("hood_camera_path", NodePath("../HoodCamera"))
	_managed.append(orbit)
	root.add_child(orbit)

	# Initial: chase (the default) owns the view.
	assert_that(_cam_current(chase)).is_true()
	assert_that(_cam_current(orbit)).is_false()
	assert_that(_cam_current(hood)).is_false()

	# Chase -> Orbit
	orbit.call("cycle_mode_for_test")
	assert_that(_cam_current(orbit)).is_true()
	assert_that(_cam_current(chase)).is_false()
	assert_that(_cam_current(hood)).is_false()

	# Orbit -> Hood
	orbit.call("cycle_mode_for_test")
	assert_that(_cam_current(hood)).is_true()
	assert_that(_cam_current(chase)).is_false()
	assert_that(_cam_current(orbit)).is_false()

	# Hood -> Chase
	orbit.call("cycle_mode_for_test")
	assert_that(_cam_current(chase)).is_true()
	assert_that(_cam_current(orbit)).is_false()
	assert_that(_cam_current(hood)).is_false()

## Windshield gate (world_driver._is_forward_view): true in chase AND hood,
## false in orbit.
func test_windshield_forward_view_gate_chase_orbit_hood() -> void:
	var driver := WorldDriver.new()
	driver.name = "Driver"
	var chase := ChaseCameraScript.new() as Node3D
	chase.name = "ChaseCamera"
	driver.add_child(chase)
	var orbit := OrbitCameraScript.new() as Node3D
	orbit.name = "OrbitCamera"
	orbit.set("chase_camera_path", NodePath("../ChaseCamera"))
	orbit.set("hood_camera_path", NodePath("../HoodCamera"))
	driver.add_child(orbit)
	var hood := HoodCameraScript.new() as Node3D
	hood.name = "HoodCamera"
	driver.add_child(hood)
	_managed.append(driver)
	add_child(driver)

	assert_that(driver.call("_is_forward_view")).is_true()  # chase by default

	orbit.call("cycle_mode_for_test")  # orbit
	assert_that(driver.call("_is_forward_view")).is_false()

	orbit.call("cycle_mode_for_test")  # hood — droplets still show
	assert_that(driver.call("_is_forward_view")).is_true()

	orbit.call("cycle_mode_for_test")  # chase again
	assert_that(driver.call("_is_forward_view")).is_true()