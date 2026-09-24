# tests/suites/test_replay_recorder.gd
extends GdUnitTestSuite

## AAA-5 gate: the pure replay recorder + headless-safe playback node.
## record->replay determinism (same feeds -> identical transform stream within
## tolerance), the N-second buffer cap (predictable FIFO eviction, no unbounded
## growth), finish-line event timestamps preserved exactly through playback,
## no physics dependence beyond the stored samples, and the existing chase /
## orbit camera rigs tracking a plain Node3D ghost as their target during
## playback. Leak discipline mirrors test_race_results.gd: every created Node
## is freed in after_test (the recorder is a RefCounted local — nothing leaks).

const ChaseCameraScript: GDScript = preload("res://scripts/camera/chase_camera.gd")
const OrbitCameraScript: GDScript = preload("res://scripts/camera/orbit_camera.gd")

const FRAME := 1.0 / 60.0

var _managed: Array = []
var _root: Node = null

func before_test() -> void:
	_managed.clear()
	_root = null

func after_test() -> void:
	for node in _managed:
		if is_instance_valid(node):
			node.free()
	_managed.clear()
	if is_instance_valid(_root):
		_root.free()
	_root = null

func _new_root() -> Node:
	_root = Node3D.new()
	_root.name = "TestRoot"
	add_child(_root)
	return _root

func _basis_axis(basis: Basis, axis: int) -> Vector3:
	match axis:
		0:
			return basis.x
		1:
			return basis.y
		_:
			return basis.z

func _pose_at(index: int) -> Transform3D:
	var basis := Basis(Vector3.UP, float(index) * 0.01).rotated(Vector3.RIGHT, float(index) * 0.005)
	return Transform3D(basis, Vector3(float(index) * 0.3, 0.0, float(index) * 0.12))

func _drive_info(speed_kmh: float, gear: int) -> Dictionary:
	return {
		"speed_kmh": speed_kmh,
		"gear": gear,
		"rpm": float(gear) * 1000.0,
		"throttle": 0.8,
		"brake": 0.1,
		"steer": 0.6,
	}

func _feed_stream(recorder: ReplayRecorder, frame_count: int, delta: float) -> void:
	for i in range(frame_count):
		recorder.feed(_pose_at(i), _drive_info(10.0 + float(i) * 0.5, (i % 4) + 1), delta)

func test_start_clears_and_stop_arms_and_freezes_feed() -> void:
	var recorder := ReplayRecorder.new()
	assert_that(recorder.is_capturing()).is_false()
	assert_that(recorder.is_empty()).is_true()
	recorder.start()
	assert_that(recorder.is_capturing()).is_true()
	_feed_stream(recorder, 30, FRAME)
	assert_that(recorder.is_empty()).is_false()
	var captured := recorder.get_sample_count()
	recorder.stop()
	assert_that(recorder.is_capturing()).is_false()
	_feed_stream(recorder, 30, FRAME)
	assert_that(recorder.get_sample_count()).is_equal(captured)

func test_sample_timestamps_follow_fixed_tick_grid_regardless_of_frame_size() -> void:
	var big := ReplayRecorder.new()
	big.start()
	for i in range(10):
		big.feed(_pose_at(i), _drive_info(20.0, 2), 1.0)
	var fine := ReplayRecorder.new()
	fine.start()
	for i in range(600):
		fine.feed(_pose_at(i), _drive_info(20.0, 2), 1.0 / 60.0)
	# 10 s captured in one huge delta vs 600 real frames: both land on the same
	# fixed TICK_RATE grid (~100 samples over 10 s) — never one sample per frame.
	assert_that(big.get_sample_count()).is_greater_equal(95)
	assert_that(big.get_sample_count()).is_less_equal(105)
	assert_that(fine.get_sample_count()).is_greater_equal(95)
	assert_that(fine.get_sample_count()).is_less_equal(105)
	assert_that(absf(big.get_duration() - 10.0)).is_less(0.4)
	assert_that(absf(fine.get_duration() - 10.0)).is_less(0.4)

func test_two_recorders_fed_identically_produce_identical_streams() -> void:
	var a := ReplayRecorder.new()
	var b := ReplayRecorder.new()
	a.start()
	b.start()
	for i in range(420):
		a.feed(_pose_at(i), _drive_info(10.0 + float(i), (i % 4) + 1), FRAME)
		b.feed(_pose_at(i), _drive_info(10.0 + float(i), (i % 4) + 1), FRAME)
	assert_that(a.get_sample_count()).is_equal(b.get_sample_count())
	assert_that(a.get_sample_count()).is_greater_equal(69)
	assert_that(a.get_sample_count()).is_less_equal(72)
	var samples_a := a.get_samples()
	var samples_b := b.get_samples()
	for i in range(samples_a.size()):
		assert_that(float(samples_a[i]["t"])).is_equal_approx(float(samples_b[i]["t"]), 0.00001)
		assert_that(float(samples_a[i]["speed_kmh"])).is_equal_approx(float(samples_b[i]["speed_kmh"]), 0.0001)
		assert_that(int(samples_a[i]["gear"])).is_equal(int(samples_b[i]["gear"]))
		assert_that(bool(samples_a[i]["drifting"])).is_equal(bool(samples_b[i]["drifting"]))
		var ta: Transform3D = samples_a[i]["transform"]
		var tb: Transform3D = samples_b[i]["transform"]
		assert_that(ta.origin.distance_to(tb.origin)).is_less(0.0001)
		for axis in range(3):
			assert_that(_basis_axis(ta.basis, axis).distance_to(_basis_axis(tb.basis, axis))).is_less(0.0001)

func test_playback_re_drives_recorded_transform_stream_within_tolerance() -> void:
	var recorder := ReplayRecorder.new()
	recorder.start()
	_feed_stream(recorder, 300, FRAME)
	recorder.stop()
	var root := _new_root()
	var playback := ReplayPlayback.new()
	root.add_child(playback)
	_managed.append(playback)
	playback.set_source(recorder)
	playback.set_loop(false)
	playback.start_playback()
	var samples := recorder.get_samples()
	assert_that(samples.size()).is_greater_equal(50)
	var final_expected: Transform3D = samples[samples.size() - 1]["transform"]
	for i in range(300):
		playback.advance(FRAME)
	# Same per-frame deltas as the record feed -> identical end-of-stream pose.
	assert_that(playback.get_time()).is_less(5.0 + 0.2)
	assert_that(playback.get_time()).is_greater(4.8)
	assert_that(playback.global_position.distance_to(final_expected.origin)).is_less(0.001)
	# Seeking an exact sample time reproduces that exact stored transform.
	var mid_index := samples.size() / 2
	playback.seek(float(samples[mid_index]["t"]))
	var expected: Transform3D = samples[mid_index]["transform"]
	assert_that(playback.global_position.distance_to(expected.origin)).is_less(0.00001)
	for axis in range(3):
		assert_that(_basis_axis(playback.global_basis, axis).distance_to(_basis_axis(expected.basis, axis))).is_less(0.00001)

func test_buffer_cap_enforced_no_unbounded_growth() -> void:
	var recorder := ReplayRecorder.new()
	recorder.start()
	for i in range(60 * 300):
		recorder.feed(_pose_at(i % 100), _drive_info(50.0, 3), FRAME)
	assert_that(recorder.get_sample_count()).is_equal(ReplayRecorder.MAX_SAMPLES)
	assert_that(recorder.get_duration()).is_less_equal(ReplayRecorder.RECORD_SECONDS)
	assert_that(recorder.get_duration()).is_greater(ReplayRecorder.RECORD_SECONDS - ReplayRecorder.TICK_INTERVAL * 3.0)
	# Feeding far past the cap can never grow the buffer: FIFO eviction is fixed.
	for i in range(60 * 300):
		recorder.feed(_pose_at(i % 100), _drive_info(50.0, 3), FRAME)
	assert_that(recorder.get_sample_count()).is_equal(ReplayRecorder.MAX_SAMPLES)

func test_finish_event_timestamp_preserved_through_playback() -> void:
	var recorder := ReplayRecorder.new()
	recorder.start()
	_feed_stream(recorder, 60, FRAME)
	recorder.record_event("race_finished")
	var finish_time := recorder.get_clock()
	recorder.stop()
	var events := recorder.get_events()
	assert_that(events.size()).is_equal(1)
	assert_that(String(events[0]["name"])).is_equal("race_finished")
	assert_that(float(events[0]["t"])).is_equal_approx(finish_time, 0.000001)
	# The playback source carries the same timeline event + timestamp untouched.
	var root := _new_root()
	var playback := ReplayPlayback.new()
	root.add_child(playback)
	_managed.append(playback)
	playback.set_source(recorder)
	playback.start_playback()
	for i in range(60):
		playback.advance(FRAME)
	var playback_events := playback.get_events()
	assert_that(playback_events.size()).is_equal(1)
	assert_that(String(playback_events[0]["name"])).is_equal("race_finished")
	assert_that(float(playback_events[0]["t"])).is_equal_approx(finish_time, 0.000001)

func test_event_buffer_bounded_evicts_oldest() -> void:
	var recorder := ReplayRecorder.new()
	recorder.start()
	for i in range(ReplayRecorder.MAX_EVENTS + 40):
		recorder.record_event("event_%d" % i)
	assert_that(recorder.get_event_count()).is_equal(ReplayRecorder.MAX_EVENTS)
	var events := recorder.get_events()
	assert_that(String(events[0]["name"])).is_equal("event_%d" % 40)
	assert_that(String(events[events.size() - 1]["name"])).is_equal("event_%d" % (ReplayRecorder.MAX_EVENTS + 39))

func test_playback_is_headless_safe_with_no_physics_dependence() -> void:
	assert_that(ReplayRecorder.is_headless()).is_true()
	var recorder := ReplayRecorder.new()
	recorder.start()
	_feed_stream(recorder, 60, FRAME)
	recorder.stop()
	var root := _new_root()
	var playback := ReplayPlayback.new()
	root.add_child(playback)
	_managed.append(playback)
	playback.set_source(recorder)
	playback.set_loop(false)
	playback.start_playback()
	# The playback entity is a bare Node3D: no physics body, no collision shape.
	var entity: Node = playback
	assert_that(entity is RigidBody3D).is_false()
	assert_that(String(playback.get_class())).is_equal("Node3D")
	assert_that(playback.find_children("*", "RigidBody3D", true, false)).is_empty()
	assert_that(playback.find_children("*", "CollisionShape3D", true, false)).is_empty()
	# Headless cull: playback visuals are never attached, so the node stays
	# child-free while the transform stream still drives.
	assert_that(playback.get_child_count()).is_equal(0)
	var start_position := playback.global_position
	for i in range(60):
		playback.advance(FRAME)
	assert_that(playback.global_position.distance_to(start_position)).is_greater(1.0)
	# The ghost factory is real data even headless; the CULL happens at attach.
	var ghost := ReplayPlayback.build_ghost()
	assert_that(ghost.mesh).is_not_null()
	ghost.free()

func test_chase_camera_rig_follows_the_replay_ghost() -> void:
	var recorder := ReplayRecorder.new()
	recorder.start()
	_feed_stream(recorder, 300, FRAME)
	recorder.stop()
	var root := _new_root()
	var playback := ReplayPlayback.new()
	root.add_child(playback)
	_managed.append(playback)
	playback.set_source(recorder)
	playback.set_loop(false)
	playback.start_playback()
	for i in range(150):
		playback.advance(FRAME)
	playback.stop_playback()
	var chase := ChaseCameraScript.new() as Node3D
	chase.set("target", playback)
	root.add_child(chase)
	_managed.append(chase)
	for i in range(120):
		chase.call("_update_camera", FRAME)
	var dist: float = float(chase.get("camera_distance"))
	var height: float = float(chase.get("camera_height"))
	var ideal := playback.global_position + playback.global_basis.z * dist + Vector3.UP * height
	assert_that(chase.global_position.distance_to(ideal)).is_less(0.5)

func test_orbit_cycle_holds_a_ghost_target() -> void:
	var recorder := ReplayRecorder.new()
	recorder.start()
	_feed_stream(recorder, 120, FRAME)
	recorder.stop()
	var root := _new_root()
	var playback := ReplayPlayback.new()
	root.add_child(playback)
	_managed.append(playback)
	playback.set_source(recorder)
	playback.set_loop(false)
	playback.start_playback()
	for i in range(60):
		playback.advance(FRAME)
	playback.stop_playback()
	var chase := ChaseCameraScript.new() as Node3D
	chase.set("target", playback)
	root.add_child(chase)
	_managed.append(chase)
	var orbit := OrbitCameraScript.new() as Node3D
	orbit.set("target", playback)
	orbit.set("chase_camera_path", chase.get_path())
	root.add_child(orbit)
	_managed.append(orbit)
	# The 4-mode cycle runs over a plain Node3D ghost without a break.
	for i in range(4):
		orbit.call("cycle_mode_for_test")
	assert_that(int(orbit.get("_mode"))).is_equal(0)
	# Standalone ORBIT over the ghost still converges: the camera settles at the
	# configured orbit_distance from the ghost-centered orbit point.
	orbit.set("_mode", 1)
	orbit.call("_apply_mode")
	for i in range(180):
		orbit.call("_apply_orbit", FRAME)
	var center: Vector3 = orbit.call("_get_orbit_center")
	var radius: float = float(orbit.get("orbit_distance"))
	assert_that(orbit.global_position.distance_to(center)).is_greater(radius - 0.4)
	assert_that(orbit.global_position.distance_to(center)).is_less(radius + 0.4)
	assert_that(orbit.global_position.distance_to(playback.global_position)).is_less_equal(radius + 1.0)