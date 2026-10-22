# tests/suites/test_brake_release_recovery.gd
extends GdUnitTestSuite

## Regression gate for the playtest report: "once I brake really hard and for a
## while, sometimes the braking continues even after I release the brakes".
##
## Root cause (wheel_physics.step_wheel_spin): the foot-brake torque was
## integrated as a plain signed torque, so a held brake that out-muscles the
## tire (starter: 2000 N*m brake vs ~1000 N*m tire peak) kept accelerating the
## wheel spin PAST zero and then ever more negative - a real brake can only
## bleed spin to a standstill, never reverse it. TireModel.calculate_slip_ratio
## clamps slip to -1, so the tire force (and the lockup slide) stayed pinned
## while the spin wound up without bound, linearly in how long the pedal was
## held. On release the tire reaction alone had to unwind that accumulator back
## to the rolling match - seconds for a multi-second hold - and for that whole
## time the locked/backspinning tire kept dragging the car down.
##
## Fix: the brake is dissipative. It may only drive the wheel spin toward zero
## and stops there (a locked wheel), so release recovers in a few frames
## whatever the hold duration. Pure/headless quarter-car plus one scene gate.

const STARTER_CONFIG: CarConfig = preload("res://resources/cars/starter_car.tres")
const TEST_SCENE := "res://scenes/test/test_vehicle_physics.tscn"
const DT := 1.0 / 60.0
const NORMAL_LOAD := 2700.0
const ARCADE_GRIP := 1.3
const QUARTER_MASS := 275.0  # starter 1100 kg / 4 wheels
const START_SPEED := 70.0  # m/s - long hold before the speed bleeds off

var _managed_nodes: Array = []

func before_test() -> void:
	_managed_nodes.clear()

func after_test() -> void:
	for node in _managed_nodes:
		if is_instance_valid(node):
			node.free()
	_managed_nodes.clear()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

func _wheel() -> WheelPhysics:
	var w := WheelPhysics.new()
	_managed_nodes.append(w)
	return w

## One quarter-car step. Returns the new road speed; the wheel is mutated.
func _step(wheel: WheelPhysics, v: float, brake: float) -> float:
	var slip := TireModel.calculate_slip_ratio(wheel.wheel_angular_velocity, v, WheelPhysics.WHEEL_RADIUS)
	var f := TireModel.calculate_longitudinal_force(slip, NORMAL_LOAD, STARTER_CONFIG, ARCADE_GRIP, 1.0)
	var stiff := TireModel.calculate_longitudinal_stiffness(slip, NORMAL_LOAD, STARTER_CONFIG, ARCADE_GRIP, 1.0)
	wheel.step_wheel_spin(DT, 0.0, brake, f, v, true, stiff)
	return v + f / QUARTER_MASS * DT

## Hold the pedal for `hold_s`, release, and return {min_omega, frames, v}.
## frames = physics frames after release until the tire is back near rolling
## (slip above -0.3), i.e. the braking drag has actually stopped. -1 if never.
func _hold_release(hold_s: float) -> Dictionary:
	var wheel := _wheel()
	var v := START_SPEED
	wheel.wheel_angular_velocity = v / WheelPhysics.WHEEL_RADIUS
	var min_omega := wheel.wheel_angular_velocity
	for _i in range(int(hold_s * 60.0)):
		v = _step(wheel, v, STARTER_CONFIG.max_brake_torque)
		min_omega = minf(min_omega, wheel.wheel_angular_velocity)
	var frames := -1
	for i in range(240):
		v = _step(wheel, v, 0.0)
		var slip := TireModel.calculate_slip_ratio(wheel.wheel_angular_velocity, v, WheelPhysics.WHEEL_RADIUS)
		if slip > -0.3:
			frames = i + 1
			break
	return {"min_omega": min_omega, "frames": frames, "v": v}

func test_held_brake_never_spins_the_wheel_backward() -> void:
	## A locked wheel sits at zero spin; the brake cannot wind it negative.
	var r := _hold_release(3.0)
	assert_that(float(r["min_omega"])).is_greater_equal(-0.001)

func test_release_recovers_quickly_after_a_long_hard_brake() -> void:
	## The bug: the recovery time scaled with the hold (10+ s for a few seconds
	## of braking). It must now be a fraction of a second.
	var r := _hold_release(3.0)
	var frames: int = r["frames"]
	assert_that(frames).is_greater(0)
	assert_that(frames).is_less_equal(40)

func test_release_recovery_is_independent_of_hold_duration() -> void:
	var short_r := _hold_release(0.5)
	var long_r := _hold_release(3.0)
	var short_frames: int = short_r["frames"]
	var long_frames: int = long_r["frames"]
	assert_that(short_frames).is_greater(0)
	assert_that(long_frames).is_greater(0)
	assert_that(absi(long_frames - short_frames)).is_less_equal(5)

func test_brake_still_bleeds_spin_to_a_stop_and_holds_there() -> void:
	## Not a no-op: from rolling the brake must lock the wheel at zero spin.
	var wheel := _wheel()
	wheel.wheel_angular_velocity = 40.0
	var omega := 40.0
	for _i in range(30):
		omega = wheel.step_wheel_spin(DT, 0.0, 2000.0, 0.0, 12.0, true, 0.0)
	assert_that(omega).is_equal_approx(0.0, 0.001)

func test_engine_brake_cannot_wind_a_braked_wheel_backward() -> void:
	## Engine-brake torque (drive < 0) on a wheel that is already locked, or one
	## that is airborne (no tire reaction), used to push it through zero while the
	## pedal was held; the windup then grew with the hold. Held brake = locked.
	for grounded in [true, false]:
		var wheel := _wheel()
		var omega := 0.0
		var min_omega := 0.0
		for _i in range(600):
			omega = wheel.step_wheel_spin(DT, -1500.0, 2000.0, 0.0, 30.0, grounded, 0.0)
			min_omega = minf(min_omega, omega)
		assert_that(min_omega).is_greater_equal(-0.001)

func test_reverse_travel_brake_is_dissipative_too() -> void:
	## Negative-signed brake (reversing) bleeds negative spin up to zero only.
	var wheel := _wheel()
	wheel.wheel_angular_velocity = -40.0
	var omega := -40.0
	for _i in range(30):
		omega = wheel.step_wheel_spin(DT, 0.0, -2000.0, 0.0, -12.0, true, 0.0)
	assert_that(omega).is_equal_approx(0.0, 0.001)

# --- Whole-vehicle gate -----------------------------------------------------

func test_car_coasts_after_releasing_a_long_hard_brake() -> void:
	var runner := scene_runner(TEST_SCENE)
	await runner.simulate_frames(60)
	var car := runner.scene().get_node("PlayerCar") as VehiclePhysics
	assert_that(car).is_not_null()
	if car == null:
		return
	# Cruise fast, then hold full brake for ~4 s.
	car.linear_velocity = -car.global_basis.z * 45.0
	car.set_input_override(Vector2(0.0, -1.0))
	var min_omega := 0.0
	for _i in range(240):
		await runner.simulate_frames(1)
		# Skip the first second: the teleport to speed, the airborne settle and the
		# brake-input ramp are transients. The bug grew with HOLD time, so the
		# steady-state window (1 s .. 4 s) is what shows it.
		if _i < 60:
			continue
		for w in car._wheels:
			min_omega = minf(min_omega, (w as WheelPhysics).wheel_angular_velocity)
	# A held brake may lock the wheels but never wind them up backward - not by
	# the brake, and not by the engine-brake pull on a locked or airborne wheel.
	assert_that(min_omega).is_greater_equal(-0.001)
	# Re-bump the speed so the post-release window is measured at speed (the
	# 4 s hold can legitimately bring the car to a halt).
	car.linear_velocity = -car.global_basis.z * 30.0
	car.set_input_override(Vector2(0.0, -1.0))
	await runner.simulate_frames(1)
	# Release: no pedals at all (override cleared -> InputManager, no keys).
	car.set_input_override(Vector2(0.001, 0.0))
	await runner.simulate_frames(30)
	var speed_a := car.linear_velocity.length()
	await runner.simulate_frames(30)
	var speed_b := car.linear_velocity.length()
	# Coast-down only: drag + engine brake is well under 1 g. A latched brake
	# drags at 0.4 g or more (> 7 m/s over 0.5 s).
	assert_that(speed_a - speed_b).is_less(3.0)
