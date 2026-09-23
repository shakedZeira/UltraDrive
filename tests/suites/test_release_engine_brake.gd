# tests/suites/test_release_engine_brake.gd
extends GdUnitTestSuite
## Regression gate for the "car keeps accelerating after throttle release"
## bug. Lifting the throttle must promptly produce ENGINE BRAKING (drive torque
## goes negative the same update), and after a standing wheelspin that brake
## must scale off the SPINNING axle - not the near-stationary body, which left
## engine_rpm at idle and let the residual wheelspin keep pulling the car.

const STARTER_CONFIG: CarConfig = preload("res://resources/cars/starter_car.tres")

func _settled_drive(dt: Drivetrain) -> float:
	for _i in range(60):
		dt.update(1.0 / 60.0, 0.0, STARTER_CONFIG)
	return float(dt.update(1.0 / 60.0, 0.0, STARTER_CONFIG)["drive_torque"])

func test_standing_wheelspin_release_engine_brakes_the_spin() -> void:
	var dt := Drivetrain.new()
	dt.manual_mode = true
	dt.current_gear = 1
	dt.set_wheel_speed(1.0)
	dt.set_axle_speed(30.0)
	var drive := _settled_drive(dt)
	assert_that(drive).is_less(-700.0)

func test_legacy_axle_unset_keeps_legacy_magnitude() -> void:
	var dt := Drivetrain.new()
	dt.manual_mode = true
	dt.current_gear = 1
	dt.set_wheel_speed(1.0)
	var drive := _settled_drive(dt)
	assert_that(drive).is_less(0.0)
	assert_that(drive).is_greater(-400.0)

func test_release_immediately_switches_to_engine_braking() -> void:
	var dt := Drivetrain.new()
	dt.manual_mode = true
	dt.current_gear = 2
	dt.set_wheel_speed(11.0)
	dt.set_axle_speed(11.0)
	var with_throttle := float(dt.update(1.0 / 60.0, 1.0, STARTER_CONFIG)["drive_torque"])
	assert_that(with_throttle).is_greater(0.0)
	var released := float(dt.update(1.0 / 60.0, 0.0, STARTER_CONFIG)["drive_torque"])
	assert_that(released).is_less(0.0)

func test_normal_cruise_feel_unchanged_when_axle_matches_wheel() -> void:
	# Real release: engine was already spun to the matching wheel speed while
	# throttling, so the axle-scaled brake must equal the legacy ramp's steady
	# value at every post-release frame.
	var legacy := Drivetrain.new()
	legacy.manual_mode = true
	legacy.current_gear = 2
	legacy.set_wheel_speed(11.0)
	var with_axle := Drivetrain.new()
	with_axle.manual_mode = true
	with_axle.current_gear = 2
	with_axle.set_wheel_speed(11.0)
	with_axle.set_axle_speed(11.0)
	for _i in range(60):
		legacy.update(1.0 / 60.0, 1.0, STARTER_CONFIG)
		with_axle.update(1.0 / 60.0, 1.0, STARTER_CONFIG)
	for _i in range(10):
		var a := float(legacy.update(1.0 / 60.0, 0.0, STARTER_CONFIG)["drive_torque"])
		var b := float(with_axle.update(1.0 / 60.0, 0.0, STARTER_CONFIG)["drive_torque"])
		assert_float(b).is_equal_approx(a, 0.001)

func test_reverse_wheelspin_release_brakes_the_backward_spin() -> void:
	var dt := Drivetrain.new()
	dt.manual_mode = true
	dt.current_gear = -1
	dt.set_wheel_speed(2.0)
	dt.set_axle_speed(-30.0)
	var drive := _settled_drive(dt)
	assert_that(absf(drive)).is_greater(700.0)