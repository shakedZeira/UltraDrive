# tests/suites/test_cockpit_camera.gd
extends GdUnitTestSuite

## F1 cockpit camera gate: rigid driver-eye anchor (near plane 0.2), mild
## speed FOV (60 -> 68), strength-scaled layered feel (steer lean roll +
## lateral, brake dive / accel squat pitch, speed micro-shake, look-into-turn
## yaw) — all bounded, zero at standstill and zero at strength 0, FPS-
## independent at 1/60 vs 1/30 — the deterministic chase/orbit/hood/cockpit
## 4-mode C-cycle, and the windshield forward-view gate covering chase + hood +
## cockpit. Frames are driven directly through _update_camera /
## cycle_mode_for_test — no physics loop, no real Input events.

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

func _new_cockpit_camera(root: Node, cam_target: Node3D) -> Node3D:
	var cam := CockpitCameraScript.new() as Node3D
	cam.set("target", cam_target)
	_managed.append(cam)
	root.add_child(cam)
	return cam

func _cam_current(camera_node: Node3D) -> bool:
	return (camera_node.get("_camera") as Camera3D).current

func _cockpit_fov(cam: Node3D) -> float:
	return cam.call("get_cockpit_fov") as float

func _seat_anchor(cam: Node3D) -> Vector3:
	return cam.call("get_seat_anchor") as Vector3

func _offset(cam: Node3D) -> Vector3:
	return cam.call("get_last_pos_offset") as Vector3

func _roll(cam: Node3D) -> float:
	return cam.call("get_last_roll") as float

func _pitch(cam: Node3D) -> float:
	return cam.call("get_last_pitch") as float

func _yaw(cam: Node3D) -> float:
	return cam.call("get_last_yaw") as float

func _set_max_strengths(cam: Node3D) -> void:
	cam.set("steer_lean_strength", 1.0)
	cam.set("pitch_strength", 1.0)
	cam.set("shake_strength", 1.0)
	cam.set("look_turn_strength", 1.0)
	cam.set("fov_strength", 1.0)

## Rigid attach: the eye sits on the computed seat anchor (no lerp, no lag),
## mirrors the body basis, carries the cockpit near plane 0.2, and re-snaps in
## a single frame after the car moves. At standstill every feel layer is zero
## so the position == the anchor.
func test_cockpit_rigidly_tracks_eye_anchor() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)
	var cam := _new_cockpit_camera(root, target)
	cam.set("debug_speed_kmh", 0.0)
	target.global_rotation = Vector3(0.0, deg_to_rad(25.0), 0.0)

	for i in range(120):
		cam.call("_update_camera", 1.0 / 60.0)
		assert_that(cam.global_position.distance_to(_seat_anchor(cam))).is_less(0.001)
		assert_that(cam.global_basis.z.distance_to(target.global_basis.z)).is_less(0.0001)

	assert_that((cam.get("_camera") as Camera3D).near).is_equal_approx(0.2, 0.0001)

	# The car drives forward (-z) 0.5 m/frame: the next frame lands on the NEW
	# anchor — the cockpit must NOT trail behind like the lerped chase cam.
	for i in range(5):
		target.global_position -= target.global_basis.z * 0.5
		cam.call("_update_camera", 1.0 / 60.0)
		assert_that(cam.global_position.distance_to(_seat_anchor(cam))).is_less(0.001)

## FOV stays in the tight cockpit range: fov_min (60) at standstill, toward
## fov_max (68) at 200 kmh, and clamped even at extreame speed (no chase/hood
## style widening in the cockpit).
func test_cockpit_fov_converges_min_at_rest_and_max_at_speed() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)

	var fast := _new_cockpit_camera(root, target)
	fast.set("debug_speed_kmh", 200.0)
	for i in range(120):
		fast.call("_update_camera", 1.0 / 60.0)
	assert_that(_cockpit_fov(fast)).is_greater_equal(67.9)
	assert_that(_cockpit_fov(fast)).is_less_equal(float(fast.get("fov_max")))

	var over := _new_cockpit_camera(root, target)
	over.set("debug_speed_kmh", 400.0)
	for i in range(120):
		over.call("_update_camera", 1.0 / 60.0)
	assert_that(_cockpit_fov(over)).is_equal_approx(float(over.get("fov_max")), 0.01)

	var still := _new_cockpit_camera(root, target)
	still.set("debug_speed_kmh", 0.0)
	for i in range(120):
		still.call("_update_camera", 1.0 / 60.0)
	assert_that(_cockpit_fov(still)).is_equal_approx(float(still.get("fov_min")), 0.001)

## Feel is bounded with max strength + speed: total offset <= ~0.05 m, roll <=
## ~4 deg, pitch <= ~3 deg, look-into-turn <= ~4 deg — and each layer is
## actually applied (stays well above 0), not just capped.
func test_feel_layers_bounded_with_max_strength_at_speed() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)
	var cam := _new_cockpit_camera(root, target)
	_set_max_strengths(cam)
	cam.set("debug_speed_kmh", 200.0)
	cam.set("debug_steer_deg", 35.0)
	cam.set("debug_throttle", 0.0)
	cam.set("debug_brake", 1.0)

	var max_off: float = 0.0
	var max_roll: float = 0.0
	var max_pitch: float = 0.0
	var max_yaw: float = 0.0
	for i in range(240):
		cam.call("_update_camera", 1.0 / 60.0)
		max_off = maxf(max_off, _offset(cam).length())
		max_roll = maxf(max_roll, absf(_roll(cam)))
		max_pitch = maxf(max_pitch, absf(_pitch(cam)))
		max_yaw = maxf(max_yaw, absf(_yaw(cam)))

	assert_that(max_off).is_less_equal(0.05)
	assert_that(max_roll).is_less_equal(deg_to_rad(4.0))
	assert_that(max_pitch).is_less_equal(deg_to_rad(3.0))
	assert_that(max_yaw).is_less_equal(0.0701)  # cap 0.07 rad = ~4 deg

	assert_that(max_off).is_greater(0.03)
	assert_that(max_roll).is_greater(0.03)
	assert_that(max_pitch).is_greater(0.02)
	assert_that(max_yaw).is_greater(0.03)

## Directional sanity: positive steer (left turn) leans + shifts + looks INTO
## the corner, and brake input pitches the nose down (view into the road).
func test_feel_direction_leans_and_looks_into_the_turn() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)
	var cam := _new_cockpit_camera(root, target)
	_set_max_strengths(cam)
	cam.set("debug_speed_kmh", 200.0)
	cam.set("debug_steer_deg", 20.0)
	cam.set("debug_throttle", 0.0)
	cam.set("debug_brake", 1.0)
	for i in range(90):
		cam.call("_update_camera", 1.0 / 60.0)

	# +steer = left: roll > 0 leans left, yaw > 0 looks toward the apex.
	assert_that(_roll(cam)).is_greater(0.001)
	assert_that(_yaw(cam)).is_greater(0.001)
	# The position offset points against the car's +X (left = into the turn).
	assert_that(_offset(cam).dot(target.global_basis.x)).is_less(-0.001)
	# Brake -> nose pitches down: the view back-vector (basis.z) lifts up.
	assert_that(_pitch(cam)).is_greater(0.001)
	assert_that(cam.global_basis.z.y).is_greater(0.001)

## All feel layers are exactly zero when strength = 0 regardless of speed /
## input, and zero at standstill even at max strength (every layer scales with
## speed/200, so the rig is calm parked).
func test_feel_all_zero_when_strength_zero_or_at_standstill() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)

	var flat := _new_cockpit_camera(root, target)
	flat.set("steer_lean_strength", 0.0)
	flat.set("pitch_strength", 0.0)
	flat.set("shake_strength", 0.0)
	flat.set("look_turn_strength", 0.0)
	flat.set("fov_strength", 0.0)
	flat.set("debug_speed_kmh", 200.0)
	flat.set("debug_steer_deg", 35.0)
	flat.set("debug_throttle", 1.0)
	flat.set("debug_brake", 1.0)
	for i in range(90):
		flat.call("_update_camera", 1.0 / 60.0)
		assert_that(flat.global_position.distance_to(_seat_anchor(flat))).is_less(0.001)
		assert_that(_roll(flat)).is_equal(0.0)
		assert_that(_pitch(flat)).is_equal(0.0)
		assert_that(_yaw(flat)).is_equal(0.0)
	assert_that(_cockpit_fov(flat)).is_equal_approx(float(flat.get("fov_min")), 0.001)

	var idle := _new_cockpit_camera(root, target)
	_set_max_strengths(idle)
	idle.set("debug_speed_kmh", 0.0)
	idle.set("debug_steer_deg", 35.0)
	idle.set("debug_throttle", 1.0)
	idle.set("debug_brake", 1.0)
	for i in range(90):
		idle.call("_update_camera", 1.0 / 60.0)
		assert_that(idle.global_position.distance_to(_seat_anchor(idle))).is_less(0.001)
		assert_that(_roll(idle)).is_equal(0.0)
		assert_that(_pitch(idle)).is_equal(0.0)
		assert_that(_yaw(idle)).is_equal(0.0)

## The C-cycle is deterministic: CHASE -> ORBIT -> HOOD -> COCKPIT -> CHASE,
## exactly one camera current per step. (S14's ownership asserts, extended to
## the fourth mode.)
func test_mode_cycle_flips_camera_ownership_deterministically_4_modes() -> void:
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

	# Initial: chase (the default) owns the view.
	assert_that(_cam_current(chase)).is_true()
	assert_that(_cam_current(orbit)).is_false()
	assert_that(_cam_current(hood)).is_false()
	assert_that(_cam_current(cockpit)).is_false()

	# Chase -> Orbit
	orbit.call("cycle_mode_for_test")
	assert_that(_cam_current(orbit)).is_true()
	assert_that(_cam_current(chase)).is_false()
	assert_that(_cam_current(hood)).is_false()
	assert_that(_cam_current(cockpit)).is_false()

	# Orbit -> Hood
	orbit.call("cycle_mode_for_test")
	assert_that(_cam_current(hood)).is_true()
	assert_that(_cam_current(chase)).is_false()
	assert_that(_cam_current(orbit)).is_false()
	assert_that(_cam_current(cockpit)).is_false()

	# Hood -> Cockpit
	orbit.call("cycle_mode_for_test")
	assert_that(_cam_current(cockpit)).is_true()
	assert_that(_cam_current(chase)).is_false()
	assert_that(_cam_current(orbit)).is_false()
	assert_that(_cam_current(hood)).is_false()

	# Cockpit -> Chase
	orbit.call("cycle_mode_for_test")
	assert_that(_cam_current(chase)).is_true()
	assert_that(_cam_current(orbit)).is_false()
	assert_that(_cam_current(hood)).is_false()
	assert_that(_cam_current(cockpit)).is_false()

## The feel math is time-based (1-exp(-k*delta) smoothing, phase at cumulative
## time), so 60 frames @ 1/60 and 30 frames @ 1/30 — the same 1.0 s — produce
## the same position, basis and FOV within tolerance.
func test_feel_fps_independent_same_output_1of60_vs_1of30() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)

	var a := _new_cockpit_camera(root, target)
	a.set("debug_speed_kmh", 200.0)
	a.set("debug_steer_deg", 20.0)
	a.set("debug_throttle", 1.0)
	a.set("debug_brake", 0.5)
	_set_max_strengths(a)
	var b := _new_cockpit_camera(root, target)
	b.set("debug_speed_kmh", 200.0)
	b.set("debug_steer_deg", 20.0)
	b.set("debug_throttle", 1.0)
	b.set("debug_brake", 0.5)
	_set_max_strengths(b)

	# Same cumulative time (1.0 s), two different frame rates.
	for i in range(60):
		a.call("_update_camera", 1.0 / 60.0)
	for i in range(30):
		b.call("_update_camera", 1.0 / 30.0)

	assert_that(a.global_position).is_equal_approx(b.global_position, Vector3(0.002, 0.002, 0.002))
	assert_that(_cockpit_fov(a)).is_equal_approx(_cockpit_fov(b), 0.05)
	assert_that(a.global_basis.z).is_equal_approx(b.global_basis.z, Vector3(0.001, 0.001, 0.001))

## Windshield gate (world_driver._is_forward_view): true in chase, hood AND
## cockpit (first-person = windshield view), false in orbit.
func test_windshield_forward_view_gate_covers_chase_hood_and_cockpit() -> void:
	var driver := WorldDriver.new()
	driver.name = "Driver"
	var chase := ChaseCameraScript.new() as Node3D
	chase.name = "ChaseCamera"
	driver.add_child(chase)
	var orbit := OrbitCameraScript.new() as Node3D
	orbit.name = "OrbitCamera"
	orbit.set("chase_camera_path", NodePath("../ChaseCamera"))
	orbit.set("hood_camera_path", NodePath("../HoodCamera"))
	orbit.set("cockpit_camera_path", NodePath("../CockpitCamera"))
	driver.add_child(orbit)
	var hood := HoodCameraScript.new() as Node3D
	hood.name = "HoodCamera"
	driver.add_child(hood)
	var cockpit := CockpitCameraScript.new() as Node3D
	cockpit.name = "CockpitCamera"
	driver.add_child(cockpit)
	_managed.append(driver)
	add_child(driver)

	assert_that(driver.call("_is_forward_view")).is_true()  # chase by default

	orbit.call("cycle_mode_for_test")  # orbit
	assert_that(driver.call("_is_forward_view")).is_false()

	orbit.call("cycle_mode_for_test")  # hood — droplets still show
	assert_that(driver.call("_is_forward_view")).is_true()

	orbit.call("cycle_mode_for_test")  # cockpit — first-person carries droplets
	assert_that(driver.call("_is_forward_view")).is_true()

	orbit.call("cycle_mode_for_test")  # chase again
	assert_that(driver.call("_is_forward_view")).is_true()