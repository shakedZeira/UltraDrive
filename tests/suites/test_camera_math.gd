# tests/suites/test_camera_math.gd
extends GdUnitTestSuite

## Pure camera math gate (Phase 0): CameraMath.fov_for_speed() and
## CameraMath.next_mode(). Both are static pure functions -- no scenes, no
## frames, no timestamps -- so these tests are exact-number asserts on the
## chase/orbit/cockpit share that cockpit_camera.gd and camera_cycle.gd build on.

# --- fov_for_speed: the house speed/200 clamp-eased ramp, narrowed 60->72 ---

func test_fov_speed_ramp_floor_and_ceiling() -> void:
	assert_float(CameraMath.fov_for_speed(0.0, 60.0, 72.0)).is_equal_approx(60.0, 0.001)
	assert_float(CameraMath.fov_for_speed(200.0, 60.0, 72.0)).is_equal_approx(72.0, 0.001)
	# Beyond speed: stays clamped at the ceiling.
	assert_float(CameraMath.fov_for_speed(400.0, 60.0, 72.0)).is_equal_approx(72.0, 0.001)

func test_fov_speed_ramp_midpoint() -> void:
	assert_float(CameraMath.fov_for_speed(100.0, 60.0, 72.0)).is_equal_approx(66.0, 0.001)

func test_fov_speed_ramp_monotonic() -> void:
	var prev := CameraMath.fov_for_speed(0.0, 60.0, 72.0)
	var at := 10.0
	while at <= 200.0:
		var fov := CameraMath.fov_for_speed(at, 60.0, 72.0)
		assert_that(fov).is_greater_equal(prev)
		prev = fov
		at += 10.0

func test_fov_speed_ramp_negative_speed_clamps_to_floor() -> void:
	assert_float(CameraMath.fov_for_speed(-30.0, 60.0, 72.0)).is_equal_approx(60.0, 0.001)

# --- next_mode: chase -> orbit -> cockpit -> chase, one-shot per press ---

func test_cycle_order_pure() -> void:
	assert_that(CameraMath.next_mode(CameraMath.Mode.CHASE, true, false)).is_equal(CameraMath.Mode.ORBIT)
	assert_that(CameraMath.next_mode(CameraMath.Mode.ORBIT, true, false)).is_equal(CameraMath.Mode.COCKPIT)
	assert_that(CameraMath.next_mode(CameraMath.Mode.COCKPIT, true, false)).is_equal(CameraMath.Mode.CHASE)

func test_stick_grab_enters_orbit_from_chase() -> void:
	# The FH "nudge into orbit" feel: a right-stick grab from CHASE enters ORBIT.
	assert_that(CameraMath.next_mode(CameraMath.Mode.CHASE, false, true)).is_equal(CameraMath.Mode.ORBIT)

func test_stick_grab_idempotent_from_orbit_and_cockpit() -> void:
	# A grab from ORBIT or COCKPIT never re-enters ORBIT, so right-stick
	# head-look stays free inside the cockpit (no modal trap).
	assert_that(CameraMath.next_mode(CameraMath.Mode.ORBIT, false, true)).is_equal(CameraMath.Mode.ORBIT)
	assert_that(CameraMath.next_mode(CameraMath.Mode.COCKPIT, false, true)).is_equal(CameraMath.Mode.COCKPIT)

func test_no_input_keeps_any_mode() -> void:
	# No press, no stick grab: mode is preserved for every slot.
	for index in CameraMath.MODE_COUNT:
		assert_that(CameraMath.next_mode(index, false, false)).is_equal(index)