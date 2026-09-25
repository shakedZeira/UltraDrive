# tests/suites/test_throttle_release_vehicle.gd
extends GdUnitTestSuite

## Repro gate for the live playtest report: "release the throttle and the car
## KEEPS PULLING for a beat". Root cause traced to wheel_physics.step_wheel_spin:
## the drivetrain now flips the axle torque negative the same update (engine
## braking), but a wheel still carrying the throttle's spin keeps the Pacejka
## peak shoving the body forward for several frames (5 at cruise, 15-18 from a
## 1st-gear launch burnout) because that excess only bleeds off at the damped
## reaction rate. Fix: ENGINE_BRAKE_UNWIND_RATE unwinds an over-spinning wheel
## back to its rolling match at 60 rad/s per frame, gated STRICTLY to the
## engine-brake state (drive_axle_torque < 0), grounded, and WITHOUT a foot
## brake. These tests pin the release bite and prove launch (drive > 0), foot-
## brake feel, airborne wheels and the standstill engine-brake hold are intact.
## Pure/headless: a real Drivetrain produces the release axle torque (both
## wheel speed and axle speed are fed, matching vehicle_physics), and a bare
## WheelPhysics wheel integrates against the same TireModel calls the traction
## suite uses.

const STARTER_CONFIG: CarConfig = preload("res://resources/cars/starter_car.tres")
const DT := 1.0 / 60.0
const NORMAL_LOAD := 2700.0
const ARCADE_GRIP := 1.3
const CRUISE_V := 14.7  # ~53 km/h, mid pull-feel band

var _managed_nodes: Array = []

func before_test() -> void:
	_managed_nodes.clear()

func after_test() -> void:
	for node in _managed_nodes:
		if is_instance_valid(node):
			node.free()
	_managed_nodes.clear()

func _wheel() -> WheelPhysics:
	var w := WheelPhysics.new()
	_managed_nodes.append(w)
	return w

func _lon(slip: float) -> float:
	return TireModel.calculate_longitudinal_force(slip, NORMAL_LOAD, STARTER_CONFIG, ARCADE_GRIP, 1.0)

func _stiffness(slip: float) -> float:
	return TireModel.calculate_longitudinal_stiffness(slip, NORMAL_LOAD, STARTER_CONFIG, ARCADE_GRIP, 1.0)

func _slip(omega: float, v: float) -> float:
	return TireModel.calculate_slip_ratio(omega, v, WheelPhysics.WHEEL_RADIUS)

func _release_drive(dt: Drivetrain, v: float, omega: float) -> float:
	## Engine-brake wheel torque the drivetrain hands each driven wheel on a
	## lift-off. Mirror vehicle_physics exactly: body wheel speed first, then the
	## live driven-axle spin (wheelspin scales engine braking to the redline
	## cap), then update. Manual gear 1 keeps the ratio deterministic.
	dt.set_wheel_speed(v)
	dt.set_axle_speed(omega * WheelPhysics.WHEEL_RADIUS)
	dt.update(DT, 0.0, STARTER_CONFIG)
	return dt.drive_torque / 2.0

# --- The complaint: off-throttle release must bite, not coast the peak ---

func test_off_throttle_release_bites_within_a_couple_frames() -> void:
	## A wheel pre-spun above rolling (a mild build-up) must shed its thrust in
	## ~2 frames after lift-off. Was ~5 frames of shove before the unwind.
	var wheel := _wheel()
	var dt := Drivetrain.new()
	dt.manual_mode = true
	var omega := 60.0  # well above the rolling match (~44.5 rad/s)
	var drive := _release_drive(dt, CRUISE_V, omega)
	assert_that(drive).is_less(0.0)
	var neg_frame := -1
	var pos_frames := 0
	for i in range(10):
		drive = _release_drive(dt, CRUISE_V, omega)
		var slip := _slip(omega, CRUISE_V)
		var f := _lon(slip)
		if neg_frame < 0 and f < 0.0:
			neg_frame = i
		if f > 1.0:
			pos_frames += 1
		omega = wheel.step_wheel_spin(DT, drive, 0.0, f, CRUISE_V, true, _stiffness(slip))
	assert_that(neg_frame).is_between(1, 4)
	assert_that(pos_frames).is_less(3)
	assert_that(omega).is_less(CRUISE_V / WheelPhysics.WHEEL_RADIUS)
	assert_that(is_finite(omega)).is_true()

func test_launch_burnout_release_bites_within_a_few_frames() -> void:
	## Worst case: a 1st-gear launch burnout leaves 90+ rad/s of excess spin; the
	## unwind sheds it in 1-5 frames instead of coasting the peak for 15-18.
	var wheel := _wheel()
	var dt := Drivetrain.new()
	dt.manual_mode = true
	var omega := 108.0  # near the off-throttle burnout shed seen in playtest
	var neg_frame := -1
	for i in range(6):
		var drive := _release_drive(dt, CRUISE_V, omega)
		var slip := _slip(omega, CRUISE_V)
		var f := _lon(slip)
		if neg_frame < 0 and f < 0.0:
			neg_frame = i
		omega = wheel.step_wheel_spin(DT, drive, 0.0, f, CRUISE_V, true, _stiffness(slip))
	assert_that(neg_frame).is_between(1, 5)
	assert_that(omega).is_less(CRUISE_V / WheelPhysics.WHEEL_RADIUS + 1.0)

# --- The gate: on-throttle drive must keep its wheelspin untouched ---

func test_on_throttle_over_spin_is_not_unwound() -> void:
	## Launch/cruise wheelspin (drive > 0) must be byte-identical: the unwind is
	## gated to the engine-brake state, so a DRIVEN wheel keeps its spin.
	var wheel := _wheel()
	var omega := CRUISE_V / WheelPhysics.WHEEL_RADIUS
	for _i in range(30):
		var slip := _slip(omega, CRUISE_V)
		omega = wheel.step_wheel_spin(DT, 1500.0, 0.0, _lon(slip), CRUISE_V, true, _stiffness(slip))
	assert_that(is_finite(omega)).is_true()
	assert_that(omega).is_greater(CRUISE_V / WheelPhysics.WHEEL_RADIUS + 10.0)

# --- The gate: foot brake preserves the integrated release, not a pin ---

func test_foot_brake_preserves_release_instead_of_instant_pin() -> void:
	## With a foot brake the unwind is inert (|brake| > 1). The wheel integrates
	## the torques: the 2000 N*m brake physically decelerates the spin past the
	## rolling match in this step - it must NOT snap straight to rolling (an
	## unwind pin would land AFTER exactly on the match).
	var wheel := _wheel()
	var dt := Drivetrain.new()
	dt.manual_mode = true
	var omega := 60.0
	var rolling := CRUISE_V / WheelPhysics.WHEEL_RADIUS
	var drive := _release_drive(dt, CRUISE_V, omega)
	var slip := _slip(omega, CRUISE_V)
	var after := wheel.step_wheel_spin(DT, drive, 2000.0, _lon(slip), CRUISE_V, true, _stiffness(slip))
	assert_that(after).is_less(rolling)
	assert_that(absf(after - rolling)).is_greater(1.0)

# --- The gate: airborne wheels bleed only through the axle, never snap ---

func test_airborne_release_is_not_snapped_to_rolling() -> void:
	## A crest hop: the axle free-spins the airborne wheel (no tire reaction).
	## The grounded gate keeps the unwind inert, so the strong engine-brake
	## torque integrates through the axle alone - the spin must NOT be pinned
	## straight to the rolling match (a snap would land exactly on it).
	var wheel := _wheel()
	var dt := Drivetrain.new()
	dt.manual_mode = true
	var omega := 90.0
	var rolling := CRUISE_V / WheelPhysics.WHEEL_RADIUS
	var drive := _release_drive(dt, CRUISE_V, omega)
	var after := wheel.step_wheel_spin(DT, drive, 0.0, 0.0, CRUISE_V, false, 0.0)
	assert_that(absf(after - rolling)).is_greater(1.0)

# --- The complement: standstill engine brake pins a residual-spin wheel ---

func test_standstill_off_throttle_engine_brake_pins_the_wheel() -> void:
	## No foot brake but the engine biting at rest (manual gear 1, throttle 0,
	## legacy negative sign) would previously let a residual spin run backward
	## through the gearbox. The unwind is the parked-hold equivalent for the
	## engine brake: a residual-spin wheel is pinned to the rolling match (0).
	var wheel := _wheel()
	wheel.wheel_angular_velocity = 3.0
	var dt := Drivetrain.new()
	dt.manual_mode = true
	var drive := _release_drive(dt, 0.0, 0.0)
	assert_that(drive).is_less(0.0)
	var omega := wheel.step_wheel_spin(DT, drive, 0.0, 0.0, 0.0, true, 0.0)
	assert_that(omega).is_equal_approx(0.0, 0.01)