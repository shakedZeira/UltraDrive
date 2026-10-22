extends GdUnitTestSuite
## Reverse has power on slopes (plan docs/plans/fix_respawn_reverse_plan.md Bugs 2a/2b).
##
## Bug 2a: reverse torque was halved by the old `reverse_torque_multiplier`
## (1.5) while forward got the full 2.2 in `VehiclePhysics` - too weak to climb.
## `CarConfig.reverse_torque_multiplier` is now 2.2 (test 1 pins it), and the
## reverse grade assist makes up any remaining shortfall.
##
## Bug 2b: `VehiclePhysics` now applies a reverse grade assist -
## `compute_reverse_grade_assist()` at the call site (gear -1 + at least one
## wheel grounded) delegates to the pure static `reverse_grade_assist_force()`,
## which cancels `config.reverse_grade_assist` (0.5) of the gravity component
## projected on the chassis forward axis, gated by a live pedal (>= 0.05),
## faded linearly to zero across `reverse_grade_assist_max_speed_kmh` (20),
## and clamped so it can never inject more energy than cancelling gravity.
## Zero on flat ground by construction: the projection is exactly zero there.
##
## Pre-fix failures by design (run the suite on the old tree to confirm):
##   - test_reverse_torque_multiplier_is_full_forward_value (1.5 != 2.2)
##   - test_reverse_drive_torque_is_full_strength (halved -> < 2400 Nm floor)
##   - test_reverse_torque_climbs_a_fifteen_degree_slope (1.5 -> 1245 N <
##     1395 N needed)
##
## Tests 1-10 are pure math on `CarConfig` / drivetrain / the static core;
## tests 11-12 instantiate `test_vehicle_physics.tscn` and verify the live
## instance seam (its gear + grounded gates and its config/body reads).

const TEST_SCENE := "res://scenes/test/test_vehicle_physics.tscn"
const STARTER_CONFIG: CarConfig = preload("res://resources/cars/starter_car.tres")

const DT := 1.0 / 60.0
const WHEEL_RADIUS := 0.33


func after_test() -> void:
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()


## Drivetrain pinned in reverse gear. Mirrors the working pattern of
## `test_low_speed_reverse_handling.gd`: manual mode + one `shift_down()` from
## gear 1 lands in -1 directly.
func _new_reverse_drivetrain() -> Drivetrain:
	var dt := Drivetrain.new()
	dt.manual_mode = true
	dt.shift_down(STARTER_CONFIG)
	dt.is_shifting = false
	return dt


## Forward direction of a body pitched nose-DOWN by `deg` degrees (its y
## component is -sin(deg), so gravity projects onto it).
func _nose_down_fwd(deg: float) -> Vector3:
	return -Basis(Vector3.RIGHT, deg_to_rad(-deg)).z


## Forward direction of a body pitched nose-UP by `deg` degrees.
func _nose_up_fwd(deg: float) -> Vector3:
	return -Basis(Vector3.RIGHT, deg_to_rad(deg)).z


## Scene + registered player, polled (not frame-counted) until every wheel has
## touched down - the car free-falls from y=2, so a fixed small frame budget
## can never land it.
func _spawn_grounded_player() -> VehiclePhysics:
	var runner := scene_runner(TEST_SCENE)
	auto_free(runner)
	var car := runner.scene().get_node("PlayerCar") as VehiclePhysics
	assert_that(car).is_not_null()
	if car == null:
		return null
	VehicleManager.register_player_car(car)
	var grounded: bool = await _wait_until_grounded(car, 150)
	assert_that(grounded).is_equal(true)
	return car


func _wait_until_grounded(car: VehiclePhysics, max_ticks: int) -> bool:
	for _i in range(max_ticks):
		if car._any_wheel_grounded():
			return true
		await get_tree().physics_frame
	return car._any_wheel_grounded()


func _wait_until_airborne(car: VehiclePhysics, max_ticks: int) -> bool:
	for _i in range(max_ticks):
		if not car._any_wheel_grounded():
			return true
		await get_tree().physics_frame
	return not car._any_wheel_grounded()


func test_reverse_torque_multiplier_is_full_forward_value() -> void:
	# Full 2.2, same as the forward gears (was 1.5, the reason reverse stalled).
	assert_that(STARTER_CONFIG.reverse_torque_multiplier).is_equal(2.2)


func test_reverse_drive_torque_is_full_strength() -> void:
	var dt := _new_reverse_drivetrain()
	assert_that(dt.current_gear).is_equal(-1)
	for _i in range(30):
		dt.update(DT, 1.0, STARTER_CONFIG)
	var drive_torque: float = dt.drive_torque
	# Reverse pulls backwards.
	assert_that(drive_torque < 0.0).is_equal(true)
	# |torque| == engine torque x ratio x multiplier - nothing else divides it.
	var engine_nm: float = STARTER_CONFIG.get_engine_torque(800.0)
	var ratio: float = STARTER_CONFIG.get_gear_ratio(-1)
	var mult: float = STARTER_CONFIG.reverse_torque_multiplier
	assert_that(absf(drive_torque)).is_equal_approx(engine_nm * 1.0 * ratio * mult, 1.0)
	# Full forward strength (gear 1 @ 800 rpm is the same 1.0 x 12.16 x 2.2).
	assert_that(absf(drive_torque)).is_greater_equal(2400.0)


func test_reverse_torque_climbs_a_fifteen_degree_slope() -> void:
	var dt := _new_reverse_drivetrain()
	for _i in range(30):
		dt.update(DT, 1.0, STARTER_CONFIG)
	var drive_torque: float = dt.drive_torque
	assert_that(drive_torque < 0.0).is_equal(true)
	# 15 deg pitch - a pitch about RIGHT keeps fwd in the YZ plane, so the
	# nose simply tilts toward the ground: dot(fwd, DOWN) = sin(15 deg).
	var fwd := _nose_down_fwd(15.0)
	assert_that(fwd.dot(Vector3.DOWN) > 0.0).is_equal(true)
	# The wheel pushes back with force = torque / radius.
	var wheel_n: float = absf(drive_torque) / WHEEL_RADIUS
	# 50% of the component of gravity along the slope (the config's grade
	# assist fraction is on top of this - this is the raw torque check).
	var need_n: float = STARTER_CONFIG.mass_kg * 9.8 * sin(deg_to_rad(15.0)) * 0.5
	assert_that(wheel_n).is_greater_equal(need_n)


func test_reverse_grade_assist_config_defaults() -> void:
	# New CarConfig fields, shipped values.
	assert_that(STARTER_CONFIG.reverse_grade_assist).is_equal(0.5)
	assert_that(STARTER_CONFIG.reverse_grade_assist_max_speed_kmh).is_equal(20.0)
	assert_that(STARTER_CONFIG.reverse_grade_assist_max_speed_kmh < STARTER_CONFIG.max_reverse_speed_kmh).is_equal(true)


func test_reverse_grade_assist_zero_on_flat_ground() -> void:
	# On flat ground the gravity projection on the forward axis is exactly
	# zero, so the assist can never push a car on level terrain.
	var rest: Vector3 = VehiclePhysics.reverse_grade_assist_force(
		Vector3.FORWARD, STARTER_CONFIG.mass_kg, 0.5, 0.5, 5.0, 20.0
	)
	assert_that(rest).is_equal(Vector3.ZERO)


func test_reverse_grade_assist_needs_a_live_pedal() -> void:
	var fwd := _nose_down_fwd(12.0)  # slope present - the pedal gate is the only zero-cause
	var no_pedal: Vector3 = VehiclePhysics.reverse_grade_assist_force(
		fwd, STARTER_CONFIG.mass_kg, 0.5, 0.0, 0.0, 20.0
	)
	assert_that(no_pedal).is_equal(Vector3.ZERO)
	# Under the 0.05 throttle gate (mirrors Drivetrain's engine-braking gate)
	# it stays silent too ...
	var below_gate: Vector3 = VehiclePhysics.reverse_grade_assist_force(
		fwd, STARTER_CONFIG.mass_kg, 0.5, 0.049, 0.0, 20.0
	)
	assert_that(below_gate).is_equal(Vector3.ZERO)
	# ... and the moment the pedal is live it pulls UPHILL (against the roll).
	var live: Vector3 = VehiclePhysics.reverse_grade_assist_force(
		fwd, STARTER_CONFIG.mass_kg, 0.5, 0.05, 0.0, 20.0
	)
	assert_that(live).is_not_equal(Vector3.ZERO)
	assert_that(live.dot(fwd) < 0.0).is_equal(true)


func test_reverse_grade_assist_fades_linearly_with_speed() -> void:
	var fwd := _nose_down_fwd(12.0)
	var max_speed: float = STARTER_CONFIG.reverse_grade_assist_max_speed_kmh
	var rest: Vector3 = VehiclePhysics.reverse_grade_assist_force(
		fwd, STARTER_CONFIG.mass_kg, 0.5, 0.5, 0.0, max_speed
	)
	assert_that(rest).is_not_equal(Vector3.ZERO)
	# Exactly half at half the fade-out speed.
	var half: Vector3 = VehiclePhysics.reverse_grade_assist_force(
		fwd, STARTER_CONFIG.mass_kg, 0.5, 0.5, max_speed * 0.5, max_speed
	)
	assert_that(half.length()).is_equal_approx(rest.length() * 0.5, 0.001)
	# Direction and magnitude are speed-SIGN independent (abs inside).
	var half_backwards: Vector3 = VehiclePhysics.reverse_grade_assist_force(
		fwd, STARTER_CONFIG.mass_kg, 0.5, 0.5, -(max_speed * 0.5), max_speed
	)
	assert_that(half_backwards).is_equal(half)
	# Zero at the fade-out ceiling and beyond - in either direction.
	var at_ceiling: Vector3 = VehiclePhysics.reverse_grade_assist_force(
		fwd, STARTER_CONFIG.mass_kg, 0.5, 0.5, max_speed, max_speed
	)
	assert_that(at_ceiling).is_equal(Vector3.ZERO)
	var above_ceiling: Vector3 = VehiclePhysics.reverse_grade_assist_force(
		fwd, STARTER_CONFIG.mass_kg, 0.5, 0.5, max_speed + 5.0, max_speed
	)
	assert_that(above_ceiling).is_equal(Vector3.ZERO)
	var above_backwards: Vector3 = VehiclePhysics.reverse_grade_assist_force(
		fwd, STARTER_CONFIG.mass_kg, 0.5, 0.5, -(max_speed + 5.0), max_speed
	)
	assert_that(above_backwards).is_equal(Vector3.ZERO)


func test_reverse_grade_assist_cancels_the_slope_pull() -> void:
	# Nose-down pitch: the nose tilts INTO the hill (dot(fwd, DOWN) = sin(12)).
	var fwd := _nose_down_fwd(12.0)
	assert_that(fwd.dot(Vector3.DOWN) > 0.0).is_equal(true)
	# Stationary hill-start (speed 0 -> full assist, no fade).
	var force: Vector3 = VehiclePhysics.reverse_grade_assist_force(
		fwd, STARTER_CONFIG.mass_kg, 0.5, 0.5, 0.0, 20.0
	)
	assert_that(force).is_not_equal(Vector3.ZERO)
	# Pulls against the roll, i.e. uphill.
	assert_that(force.dot(fwd) < 0.0).is_equal(true)
	# Magnitude: fraction 0.5 x the gravity pull along the slope
	# (mass x 9.8 x sin(12 deg) = 2241 N -> 1121 N of cancel).
	var expected_n: float = STARTER_CONFIG.mass_kg * 9.8 * absf(fwd.y) * 0.5
	assert_that(force.length()).is_equal_approx(expected_n, 1.0)
	# Clamped: never more than the full gravity pull along the slope.
	assert_that(force.length()).is_less_equal(
		STARTER_CONFIG.mass_kg * 9.8 * absf(fwd.y) + 0.001
	)


func test_reverse_grade_assist_always_combats_the_roll() -> void:
	# Both orientations: with a live pedal the assist can never HELP the car
	# roll downhill (dot(force, forward) x gravity-along-forward <= 0).
	var gravity := Vector3.DOWN * 9.8
	for pitch_deg: float in [12.0, -12.0]:
		var fwd := -Basis(Vector3.RIGHT, deg_to_rad(pitch_deg)).z
		var force: Vector3 = VehiclePhysics.reverse_grade_assist_force(
			fwd, STARTER_CONFIG.mass_kg, 0.5, 0.5, 5.0, 20.0
		)
		assert_that(force).is_not_equal(Vector3.ZERO)
		var gravity_along: float = gravity.dot(fwd)
		assert_that(force.dot(fwd) * gravity_along).is_less_equal(0.0)


func test_reverse_grade_assist_fraction_scales_linearly_and_clamps() -> void:
	var fwd := _nose_down_fwd(12.0)
	var one: Vector3 = VehiclePhysics.reverse_grade_assist_force(
		fwd, STARTER_CONFIG.mass_kg, 1.0, 0.5, 5.0, 20.0
	)
	var half: Vector3 = VehiclePhysics.reverse_grade_assist_force(
		fwd, STARTER_CONFIG.mass_kg, 0.5, 0.5, 5.0, 20.0
	)
	assert_that(half).is_not_equal(Vector3.ZERO)
	assert_that(half.length()).is_equal_approx(one.length() * 0.5, 0.001)
	# fraction > 1 clamps to 1.0 - the assist can never inject more energy
	# than cancelling gravity (identical result, exactly).
	var clamped: Vector3 = VehiclePhysics.reverse_grade_assist_force(
		fwd, STARTER_CONFIG.mass_kg, 2.0, 0.5, 5.0, 20.0
	)
	assert_that(clamped).is_equal(one)
	# And a zero fraction is silent.
	var zeroed: Vector3 = VehiclePhysics.reverse_grade_assist_force(
		fwd, STARTER_CONFIG.mass_kg, 0.0, 0.5, 5.0, 20.0
	)
	assert_that(zeroed).is_equal(Vector3.ZERO)


func test_vehicle_applies_reverse_grade_assist_in_gear() -> void:
	var car := await _spawn_grounded_player()
	if car == null:
		return
	# Park nose-down on a 12 deg slope (reversing uphill). The basis set and
	# every call below happen synchronously - no physics tick in between -
	# so the chassis forward the seam reads is exactly ours.
	car.global_basis = Basis(Vector3.RIGHT, deg_to_rad(-12.0))
	var fwd := _nose_down_fwd(12.0)
	var slope_up := -fwd
	# Parked in forward gear (the box has no neutral and AUTO never selects
	# reverse on its own, so the settle ticks leave it in 1): no assist
	# without the reverse GEAR.
	assert_that(car._drivetrain.current_gear).is_not_equal(-1)
	var neutral: Vector3 = car.compute_reverse_grade_assist(0.5, 1.0)
	assert_that(neutral).is_equal(Vector3.ZERO)
	# Engage reverse: the seam's live inputs produce an UPHILL pull.
	car._drivetrain.current_gear = -1
	var assist: Vector3 = car.compute_reverse_grade_assist(0.5, 1.0)
	assert_that(assist).is_not_equal(Vector3.ZERO)
	assert_that(assist.dot(slope_up) > 0.0).is_equal(true)
	# Out of reverse gear again: silent.
	car._drivetrain.current_gear = 1
	var out_of_gear: Vector3 = car.compute_reverse_grade_assist(0.5, 1.0)
	assert_that(out_of_gear).is_equal(Vector3.ZERO)


func test_reverse_grade_assist_gates_in_the_live_vehicle() -> void:
	var car := await _spawn_grounded_player()
	if car == null:
		return
	# Reverse gear engaged on the 12 deg slope, grounded - every gate but the
	# one under test is open, so each ZERO below is attributable to that gate.
	car.global_basis = Basis(Vector3.RIGHT, deg_to_rad(-12.0))
	car._drivetrain.current_gear = -1
	var slope_up := -_nose_down_fwd(12.0)
	# Gate 1: no pedal -> zero, whatever the speed.
	var no_pedal: Vector3 = car.compute_reverse_grade_assist(0.0, 1.0)
	assert_that(no_pedal).is_equal(Vector3.ZERO)
	# Gate 2: over the 20 km/h fade ceiling (6 m/s = 21.6 km/h) -> zero.
	var too_fast: Vector3 = car.compute_reverse_grade_assist(0.5, 6.0)
	assert_that(too_fast).is_equal(Vector3.ZERO)
	# Positive control: pedal live, crawling - the assist engages uphill.
	var engaged: Vector3 = car.compute_reverse_grade_assist(0.5, 1.0)
	assert_that(engaged).is_not_equal(Vector3.ZERO)
	assert_that(engaged.dot(slope_up) > 0.0).is_equal(true)
	# Gate 3: airborne -> zero even with pedal, speed and gear (the seam's
	# `_any_wheel_grounded()` check). Lift the body clear and poll - it is
	# falling the moment we let go, so the state change cannot race us.
	car.global_position.y = 50.0
	var airborne: bool = await _wait_until_airborne(car, 60)
	assert_that(airborne).is_equal(true)
	# AUTO may pop out of reverse during the fall (wheel speed > 0.5 km/h):
	# re-engage so the GROUND is the only thing that can zero the result.
	car._drivetrain.current_gear = -1
	var lifted: Vector3 = car.compute_reverse_grade_assist(0.5, 1.0)
	assert_that(lifted).is_equal(Vector3.ZERO)
