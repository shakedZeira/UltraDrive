# tests/suites/test_low_speed_reverse_handling.gd
extends GdUnitTestSuite

## Repro gate for the live playtest report: "driving in reverse, gear didn't
## matter, spun at low speed, brakes did nothing". Root causes traced:
## (1) Brake torque sign is keyed to the SELECTED GEAR (gear_dir at
##     vehicle_physics.gd), not to the direction of TRAVEL: backward travel in
##     a forward gear (MANUAL never auto-flips) feeds POSITIVE brake torque into
##     step_wheel_spin, which spins the wheel backward faster than the road,
##     producing negative slip and a BACKWARD tire force - the brake
##     accelerates the reverse.
## (2) Engine-brake torque is likewise gear-keyed (always -mag in a forward
##     gear regardless of travel), so once rolling backward off-throttle the
##     "engine braking" keeps pushing the car backward - a self-amplifying
##     runaway up to the arcade reverse cap. At standstill the legacy sign is
##     pinned by test_race_countdown, so the travel-keyed flip only applies to
##     actual (nonzero) travel.
## (3) The countersteer yaw assist is gated to forward_speed > 0 AND >= 70 km/h
##     (vehicle_physics.gd), so backward travel has ZERO yaw damping - once the
##     runaway plus 48 deg low-speed lock kicks off a spin nothing arrests it.
## Pure/headless: Drivetrain + VehiclePhysics statics, plus one scene
## integration that brakes a backward-rolling forward-gear car to a stop.

const TEST_SCENE := "res://scenes/test/test_vehicle_physics.tscn"
const STARTER_CONFIG: CarConfig = preload("res://resources/cars/starter_car.tres")
const DT := 1.0 / 60.0

var _managed_nodes: Array = []
var _prev_transmission: GameState.TransmissionMode = GameState.TransmissionMode.AUTO

func before_test() -> void:
	_managed_nodes.clear()
	_prev_transmission = GameState.transmission_mode

func after_test() -> void:
	for node in _managed_nodes:
		if is_instance_valid(node):
			node.free()
	_managed_nodes.clear()
	GameState.transmission_mode = _prev_transmission
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

func _new_manual_drivetrain() -> Drivetrain:
	var dt := Drivetrain.new()
	dt.manual_mode = true
	return dt

# --- Symptom 1/2: engine braking must oppose TRAVEL, not the gear ---

func test_engine_brake_opposes_backward_travel_in_forward_gear() -> void:
	var dt := _new_manual_drivetrain()
	dt.set_wheel_speed(-2.0)
	dt.update(DT, 0.0, STARTER_CONFIG)
	assert_that(dt.current_gear).is_equal(1)
	assert_that(dt.drive_torque).is_greater(0.0)

func test_engine_brake_opposes_forward_travel_in_forward_gear() -> void:
	var dt := _new_manual_drivetrain()
	dt.set_wheel_speed(2.0)
	dt.update(DT, 0.0, STARTER_CONFIG)
	assert_that(dt.drive_torque).is_less(0.0)

func test_engine_brake_keeps_legacy_sign_at_standstill() -> void:
	var dt := _new_manual_drivetrain()
	dt.set_wheel_speed(0.0)
	dt.update(DT, 0.0, STARTER_CONFIG)
	assert_that(dt.drive_torque).is_less(0.0)

func test_engine_brake_opposes_backward_travel_in_reverse_gear() -> void:
	var dt := _new_manual_drivetrain()
	dt.shift_down(STARTER_CONFIG)
	dt.is_shifting = false
	dt.set_wheel_speed(-2.0)
	dt.update(DT, 0.0, STARTER_CONFIG)
	assert_that(dt.current_gear).is_equal(-1)
	assert_that(dt.drive_torque).is_greater(0.0)

func test_engine_brake_opposes_forward_creep_out_of_reverse() -> void:
	var dt := _new_manual_drivetrain()
	dt.shift_down(STARTER_CONFIG)
	dt.is_shifting = false
	dt.set_wheel_speed(0.4)
	dt.update(DT, 0.0, STARTER_CONFIG)
	assert_that(dt.drive_torque).is_less(0.0)

# --- Symptom 4: brake torque sign must oppose TRAVEL ---

func test_brake_torque_opposes_backward_travel_in_forward_gear() -> void:
	var torque := VehiclePhysics.brake_torque_for(-3.0, 1, 1.0, STARTER_CONFIG.max_brake_torque)
	assert_that(torque).is_less(0.0)

func test_brake_torque_opposes_forward_travel_in_forward_gear() -> void:
	var torque := VehiclePhysics.brake_torque_for(3.0, 1, 1.0, STARTER_CONFIG.max_brake_torque)
	assert_that(torque).is_greater(0.0)

func test_brake_torque_sign_follows_travel_in_reverse_gear() -> void:
	assert_that(VehiclePhysics.brake_torque_for(-3.0, -1, 1.0, 2000.0)).is_less(0.0)
	assert_that(VehiclePhysics.brake_torque_for(3.0, -1, 1.0, 2000.0)).is_greater(0.0)

func test_brake_torque_uses_gear_sign_inside_parked_hold_band() -> void:
	var band := WheelPhysics.PARKED_HOLD_SPEED
	assert_that(VehiclePhysics.brake_torque_for(0.0, 1, 1.0, 2000.0)).is_greater(0.0)
	assert_that(VehiclePhysics.brake_torque_for(0.0, -1, 1.0, 2000.0)).is_less(0.0)
	assert_that(VehiclePhysics.brake_torque_for(-band * 0.5, 1, 1.0, 2000.0)).is_greater(0.0)

func test_brake_torque_zero_without_brake_input() -> void:
	assert_that(VehiclePhysics.brake_torque_for(-5.0, 1, 0.0, 2000.0)).is_equal(0.0)

func test_braking_backward_roll_produces_forward_tire_force() -> void:
	var wheel := WheelPhysics.new()
	_managed_nodes.append(wheel)
	var v := -4.0
	var omega := v / WheelPhysics.WHEEL_RADIUS
	var lon := 0.0
	for _i in range(30):
		var brake := VehiclePhysics.brake_torque_for(v, 1, 1.0, STARTER_CONFIG.max_brake_torque)
		var slip := TireModel.calculate_slip_ratio(omega, v, WheelPhysics.WHEEL_RADIUS)
		var stiffness := TireModel.calculate_longitudinal_stiffness(
			slip, 2700.0, STARTER_CONFIG, 1.3, 1.0
		)
		lon = TireModel.calculate_longitudinal_force(slip, 2700.0, STARTER_CONFIG, 1.3, 1.0)
		omega = wheel.step_wheel_spin(DT, 0.0, brake, lon, v, true, stiffness)
	assert_that(lon).is_greater(0.0)

# --- Symptom 3: yaw assist envelope ---

func test_yaw_taper_full_for_backward_travel() -> void:
	assert_that(VehiclePhysics.yaw_assist_taper(-3.0, 11.0)).is_greater(0.0)
	assert_that(VehiclePhysics.yaw_assist_taper(-6.94, 25.0)).is_greater(0.0)

func test_yaw_taper_zero_at_standstill() -> void:
	assert_that(VehiclePhysics.yaw_assist_taper(0.0, 0.0)).is_equal(0.0)

func test_yaw_taper_forward_envelope_unchanged() -> void:
	assert_that(VehiclePhysics.yaw_assist_taper(50.0, 60.0)).is_equal(0.0)
	assert_that(VehiclePhysics.yaw_assist_taper(50.0, 70.0)).is_equal(0.0)
	assert_that(VehiclePhysics.yaw_assist_taper(50.0, 105.0)).is_equal_approx(0.5, 0.0001)
	assert_that(VehiclePhysics.yaw_assist_taper(50.0, 140.0)).is_equal(1.0)
	assert_that(VehiclePhysics.yaw_assist_taper(50.0, 250.0)).is_equal(1.0)

# --- Scene integration: full brake on a backward-rolling forward-gear car ---

func test_brake_stops_backward_roll_in_forward_gear() -> void:
	GameState.transmission_mode = GameState.TransmissionMode.MANUAL
	var runner := scene_runner(TEST_SCENE)
	await runner.simulate_frames(5)
	var car := runner.scene().get_node("PlayerCar") as VehiclePhysics
	assert_that(car).is_not_null()
	if car == null:
		return
	assert_that(car.freeze).is_false()
	car.set_handling_mode("arcade")
	await runner.simulate_frames(90)
	car._drivetrain.current_gear = 1
	car.linear_velocity = -car.global_basis.z * -3.0
	car.angular_velocity = Vector3.ZERO
	car._prev_linear_velocity = car.linear_velocity
	car.set_input_override(Vector2(0.0, -1.0))
	await runner.simulate_frames(90)
	var fwd_stop: float = -car.global_basis.z.dot(car.linear_velocity)
	var info := car.get_drive_info()
	assert_that(int(info["gear"])).is_equal(1)
	assert_that(fwd_stop).is_greater(-1.0)
	assert_that(fwd_stop).is_less(1.5)
	assert_that(float(info["speed_kmh"])).is_less(6.0)
