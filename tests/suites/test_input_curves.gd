# tests/suites/test_input_curves.gd
extends GdUnitTestSuite

## Input-feel gate: the player's analog trigger response curve
## (VehiclePhysics.apply_analog_response). Pure-function coverage for
## endpoints, monotonicity, the power-2 feathering sweet spot (0.25 press ->
## 0.0625), the deadzone, and the power-1/deadzone-0 disable case that must
## reproduce the old linear read byte-for-byte. Plus a tree-free wiring probe:
## player_car.tscn is instantiated WITHOUT being added to a tree (no _ready)
## just to confirm the exported defaults are live on the real controller root.
## Keyboard keys read exactly 0.0/1.0 and both endpoints are fixed points, so
## the digital fallback is untouched by construction - no input injection here.

const PLAYER_CAR_SCENE := "res://scenes/vehicle/player_car.tscn"

var _managed: Array = []

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	for node in _managed:
		if is_instance_valid(node):
			node.free()
	_managed.clear()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

func test_curve_endpoints_hold_for_any_power_and_deadzone() -> void:
	## x=0 -> 0 and x=1 -> 1 must hold for every valid power>0 and deadzone in
	## the supported [0, 0.05] range.
	for power: float in [0.5, 1.0, 2.0, 3.0]:
		for deadzone: float in [0.0, 0.02, 0.05]:
			assert_that(VehiclePhysics.apply_analog_response(0.0, power, deadzone)).is_equal(0.0)
			assert_that(VehiclePhysics.apply_analog_response(1.0, power, deadzone)).is_equal(1.0)

func test_curve_is_monotonic_across_21_samples() -> void:
	## Non-decreasing across the whole [0,1] domain at the shipped config, so no
	## deadzoning or power fold can ever make a stronger press read weaker.
	var prev := -1.0
	for i in range(21):
		var x := float(i) / 20.0
		var y := VehiclePhysics.apply_analog_response(
			x, VehiclePhysics.ANALOG_RESPONSE_POWER, VehiclePhysics.ANALOG_RESPONSE_DEADZONE)
		assert_that(y).is_greater_equal(prev)
		assert_that(y).is_between(0.0, 1.0)
		prev = y

func test_curve_low_end_power_two_feathers_at_quarter() -> void:
	## power 2.0: a quarter trigger press reads 0.0625, not 0.25 - the extra
	## low-end resolution that makes throttle feathering / trail-braking usable.
	assert_float(VehiclePhysics.apply_analog_response(0.25, 2.0, 0.0)).is_equal_approx(0.0625, 0.00001)

func test_curve_default_config_feels_like_power_two() -> void:
	## The shipped feel uses ANALOG_RESPONSE_POWER (2.0): a half trigger press
	## must read ~0.25, not 0.5.
	assert_float(VehiclePhysics.apply_analog_response(
		0.5, VehiclePhysics.ANALOG_RESPONSE_POWER, VehiclePhysics.ANALOG_RESPONSE_DEADZONE)).is_equal_approx(0.25, 0.001)

func test_curve_disable_case_power_one_deadzone_zero_is_identity() -> void:
	## "Preserve existing behavior EXACTLY when nobody configures it": power 1.0 +
	## deadzone 0.0 must reproduce the old linear read across the full domain.
	for i in range(21):
		var x := float(i) / 20.0
		assert_float(VehiclePhysics.apply_analog_response(x, 1.0, 0.0)).is_equal_approx(x, 0.000001)

func test_curve_disable_case_power_one_is_byte_exact() -> void:
	## apply_analog_response short-circuits power == 1.0 and returns x itself, so
	## the disable case is bit-for-bit the value fed in (not just approx).
	for x: float in [0.0, 0.001, 0.0625, 0.25, 0.5, 0.999, 1.0]:
		assert_that(VehiclePhysics.apply_analog_response(x, 1.0, 0.0)).is_equal(x)

func test_curve_deadzone_zeroes_resting_trigger() -> void:
	## Anything at or below the deadzone reads as fully off (a resting trigger
	## must not creep), and the curve resumes immediately above it.
	assert_that(VehiclePhysics.apply_analog_response(0.0, 2.0, 0.02)).is_equal(0.0)
	assert_that(VehiclePhysics.apply_analog_response(0.02, 2.0, 0.02)).is_equal(0.0)
	assert_that(VehiclePhysics.apply_analog_response(0.015, 2.0, 0.02)).is_equal(0.0)
	assert_that(VehiclePhysics.apply_analog_response(0.021, 2.0, 0.02)).is_greater(0.0)

func test_curve_clamps_out_of_range_input() -> void:
	assert_that(VehiclePhysics.apply_analog_response(1.5, 2.0, 0.0)).is_equal(1.0)
	assert_that(VehiclePhysics.apply_analog_response(-0.5, 2.0, 0.0)).is_equal(0.0)

func test_player_car_scene_exports_live_curve_defaults() -> void:
	## Wiring probe: instantiate player_car.tscn WITHOUT adding it to a tree (no
	## _ready, physics, or audio server touched), read the exported config off the
	## VehiclePhysics root, and confirm it curves like power 2.0.
	var car: VehiclePhysics = (load(PLAYER_CAR_SCENE) as PackedScene).instantiate() as VehiclePhysics
	assert_that(car).is_not_null()
	if car == null:
		return
	_managed.append(car)
	assert_that(car.analog_response_power).is_equal(VehiclePhysics.ANALOG_RESPONSE_POWER)
	assert_that(car.analog_response_deadzone).is_equal(VehiclePhysics.ANALOG_RESPONSE_DEADZONE)
	assert_float(VehiclePhysics.apply_analog_response(
		0.25, car.analog_response_power, car.analog_response_deadzone)).is_equal_approx(0.0625, 0.00001)