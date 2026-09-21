# tests/suites/test_hardening.gd
extends GdUnitTestSuite

## Item 10 racing-game hardening audit. Encodes the plan's bug-prevention list:
## NaN body states must restore the last valid position/velocity instead of
## poisoning slip math and drag, the arcade path clamps forward speed to
## [-reverse cap, top speed] so the HUD/drift/wheels agree, steer at zero speed
## stays finite and bounded, a race re-entry resets the ceremony (countdown
## back to "3", fresh lap counters, cleared race time), start requests are
## debounced while a race is live, traffic despawn releases its driver and
## leaves no lingering vehicle, and extreme delta spikes never produce NaN.
## Headless-safe: pure statics where possible; in-tree frames only via the
## ground-latch test scene.

const TEST_SCENE := "res://scenes/test/test_vehicle_physics.tscn"
const CAR_SCENE := "res://scenes/vehicle/player_car.tscn"
const RING_RADIUS := 200.0
const RING_POINTS := 96
const PLAYER_POS := Vector3.ZERO
const FAR_PLAYER := Vector3(0.0, 0.0, -1000.0)

var _managed_cars: Array = []
var _managed_nodes: Array = []
var _managed_stubs: Array = []
var _managed_spawners: Array = []

func before_test() -> void:
	_managed_cars.clear()
	_managed_nodes.clear()
	_managed_stubs.clear()
	_managed_spawners.clear()

func after_test() -> void:
	for car in _managed_cars:
		if is_instance_valid(car):
			car.free()
	_managed_cars.clear()
	for node in _managed_nodes:
		if is_instance_valid(node):
			node.free()
	_managed_nodes.clear()
	for stub in _managed_stubs:
		if is_instance_valid(stub):
			stub.free()
	_managed_stubs.clear()
	for spawner in _managed_spawners:
		if is_instance_valid(spawner):
			for child in spawner.get_children():
				if is_instance_valid(child):
					child.free()
			spawner.free()
	_managed_spawners.clear()
	for child in RaceManager.get_children():
		if child is LapCounter:
			child.free()
	RaceManager.is_race_active = false
	RaceManager._participants = []
	RaceManager._lap_counters = {}
	RaceManager._checkpoints_dirty = true
	RaceManager._countdown = RaceCountdown.new()
	RaceManager.consume_pending_race()
	for child in get_children():
		if child is Checkpoint:
			child.free()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

func _new_stub_car() -> VehiclePhysics:
	var car := VehiclePhysics.new()
	_managed_cars.append(car)
	return car

func _build_ring() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in RING_POINTS:
		var angle := TAU * float(i) / float(RING_POINTS)
		points.append(Vector3(cos(angle) * RING_RADIUS, 0.0, sin(angle) * RING_RADIUS))
	return points

func _new_spawner(network: RoadNetwork, max_count: int = 3) -> TrafficSpawner:
	var spawner := TrafficSpawner.new()
	spawner.road_network = network
	spawner.vehicle_scene = load(CAR_SCENE)
	spawner.max_traffic = max_count
	spawner.spawn_radius = 220.0
	add_child(spawner)
	_managed_spawners.append(spawner)
	return spawner

func _new_network() -> RoadNetwork:
	var network := RoadNetwork.new()
	add_child(network)
	_managed_nodes.append(network)
	network.add_road(_build_ring(), 8.0)
	return network

func _live_count(spawner: TrafficSpawner) -> int:
	var n := 0
	for child in spawner.get_children():
		if child is VehiclePhysics:
			n += 1
	return n

func _finite_float(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)

func _starter_top_speed_m() -> float:
	var config := load("res://resources/cars/starter_car.tres") as CarConfig
	return config.get_max_speed() * float(config.arcade_mode.get("max_speed_modifier", 1.0))

func _starter_reverse_cap_m() -> float:
	var config := load("res://resources/cars/starter_car.tres") as CarConfig
	return config.max_reverse_speed_kmh / 3.6

func test_nan_velocity_and_position_restore_last_valid_state() -> void:
	var runner := scene_runner(TEST_SCENE)
	await runner.simulate_frames(5)
	var car := runner.scene().get_node("PlayerCar") as VehiclePhysics
	assert_that(car).is_not_null()
	if car == null:
		return
	assert_that(car._awaiting_ground).is_false()
	var valid_position := car.global_position
	var valid_basis := car.global_basis
	var valid_speed := car.current_speed_kmh
	car.linear_velocity = Vector3(NAN, NAN, NAN)
	car.angular_velocity = Vector3(NAN, NAN, NAN)
	car.global_position = Vector3(NAN, NAN, NAN)
	car._physics_process(1.0 / 60.0)
	assert_that(car.linear_velocity.is_finite()).is_true()
	assert_that(car.angular_velocity.is_finite()).is_true()
	assert_that(car.global_position.is_finite()).is_true()
	assert_that(car.global_basis.is_finite()).is_true()
	assert_that(_finite_float(car.current_speed_kmh)).is_true()
	assert_that(car.global_position).is_equal_approx(valid_position, Vector3(0.02, 0.02, 0.02))
	assert_that(car.global_basis.is_equal_approx(valid_basis)).is_true()
	assert_that(car.current_speed_kmh).is_equal_approx(valid_speed, 0.01)

func test_arcade_speed_clamp_caps_upper_bound() -> void:
	var top := _starter_top_speed_m()
	var forward := Vector3.FORWARD
	var clamped := VehiclePhysics.clamp_arcade_speed(forward * (top * 2.0), forward, top, _starter_reverse_cap_m())
	assert_that(clamped.is_finite()).is_true()
	assert_that(clamped.length()).is_equal_approx(top, 0.001)
	assert_that(clamped.dot(forward)).is_greater(0.0)

func test_arcade_speed_clamp_caps_reverse_limit() -> void:
	var cap := _starter_reverse_cap_m()
	assert_that(cap).is_greater(0.0)
	var clamped := VehiclePhysics.clamp_arcade_speed(Vector3.FORWARD * (-cap * 3.0), Vector3.FORWARD, _starter_top_speed_m(), cap)
	assert_that(clamped.is_finite()).is_true()
	assert_that(clamped.length()).is_equal_approx(cap, 0.001)
	assert_that(clamped.dot(Vector3.FORWARD)).is_less(0.0)

func test_arcade_speed_clamp_leaves_in_range_sideways_and_zero_alone() -> void:
	var top := _starter_top_speed_m()
	var cap := _starter_reverse_cap_m()
	var forward := Vector3.FORWARD
	var cruise := Vector3.FORWARD * (cap * 0.5)
	assert_that(VehiclePhysics.clamp_arcade_speed(cruise, forward, top, cap)) \
			.is_equal_approx(cruise, Vector3(0.0001, 0.0001, 0.0001))
	var side := Vector3.RIGHT * 30.0
	assert_that(VehiclePhysics.clamp_arcade_speed(side, forward, top, cap)) \
			.is_equal_approx(side, Vector3(0.0001, 0.0001, 0.0001))
	assert_that(VehiclePhysics.clamp_arcade_speed(Vector3.ZERO, forward, top, cap)).is_equal(Vector3.ZERO)
	var no_limit := VehiclePhysics.clamp_arcade_speed(Vector3.FORWARD * 100.0, forward, 0.0, cap)
	assert_that(no_limit).is_equal(Vector3.FORWARD * 100.0)

func test_arcade_speed_clamp_wired_into_live_physics_frame() -> void:
	var runner := scene_runner(TEST_SCENE)
	await runner.simulate_frames(5)
	var car := runner.scene().get_node("PlayerCar") as VehiclePhysics
	assert_that(car).is_not_null()
	if car == null:
		return
	car.set_handling_mode("arcade")
	var top := _starter_top_speed_m()
	var limit := Vector3.FORWARD * top
	car._prev_linear_velocity = limit
	car.linear_velocity = Vector3.FORWARD * (top * 5.0)
	car._physics_process(1.0 / 60.0)
	assert_that(car.linear_velocity.is_finite()).is_true()
	assert_that(car.linear_velocity).is_equal_approx(limit, Vector3(0.01, 0.01, 0.01))
	assert_that(car.current_speed_kmh).is_equal_approx(top * 3.6, 0.5)

func test_steer_at_zero_speed_stays_finite_and_bounded() -> void:
	var runner := scene_runner(TEST_SCENE)
	await runner.simulate_frames(5)
	var car := runner.scene().get_node("PlayerCar") as VehiclePhysics
	assert_that(car).is_not_null()
	if car == null:
		return
	car.freeze = true
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.current_speed_kmh = 0.0
	car.set_input_override(Vector2(1.0, 0.0))
	var max_angle_rad := deg_to_rad(car.config.max_steer_angle)
	for _frame in range(60):
		car._physics_process(1.0 / 60.0)
	assert_that(_finite_float(car.steer_angle)).is_true()
	assert_that(_finite_float(car.current_speed_kmh)).is_true()
	assert_that(car.current_speed_kmh).is_equal_approx(0.0, 0.001)
	assert_that(car.steer_angle).is_greater(max_angle_rad * 0.9)
	assert_that(car.steer_angle).is_less_equal(max_angle_rad + 0.01)
	assert_that(car.wheel_fl.rotation.y).is_equal_approx(car.steer_angle, 0.0001)
	assert_that(float(car.get_drive_info()["steer"])).is_equal(1.0)

func test_race_reentry_resets_ceremony_and_lap_state() -> void:
	var first := _new_stub_car()
	var second := _new_stub_car()
	VehicleManager.register_player_car(first)
	RaceManager.start_race([first], 3)
	assert_that(RaceManager.is_race_active).is_true()
	assert_that(RaceManager.get_countdown().phase()).is_equal("3")
	RaceManager.get_countdown().advance(RaceCountdown.TOTAL_SECONDS)
	assert_that(RaceManager.get_countdown().phase()).is_equal("RACE")
	RaceManager.start_race([first, second], 2)
	assert_that(RaceManager.is_race_active).is_true()
	assert_that(RaceManager.total_laps).is_equal(2)
	assert_that(RaceManager.get_race_time()).is_equal(0.0)
	assert_that(RaceManager.get_countdown().phase()).is_equal("3")
	assert_that(RaceManager.get_countdown().controls_locked()).is_true()
	assert_that(RaceManager.get_lap_counter(first)).is_not_null()
	assert_that(RaceManager.get_lap_counter(second)).is_not_null()
	assert_that(RaceManager.get_lap_counter(first).get_current_lap()).is_equal(1)
	assert_that(RaceManager.get_lap_counter(second).get_current_lap()).is_equal(1)

func test_start_requests_ignored_while_race_live() -> void:
	var car := _new_stub_car()
	VehicleManager.register_player_car(car)
	RaceManager.start_race([car], 3)
	RaceManager.request_race(5)
	assert_that(RaceManager.consume_pending_race()).is_equal(0)
	RaceManager.queue_race(7)
	assert_that(RaceManager.consume_pending_race()).is_equal(0)
	RaceManager.finish_race()
	assert_that(RaceManager.is_race_active).is_false()
	RaceManager.request_race(3)
	assert_that(RaceManager.consume_pending_race()).is_equal(3)

func test_traffic_despawn_releases_drivers_and_vehicles() -> void:
	var spawner := _new_spawner(_new_network())
	for _frame in range(200):
		spawner.update(PLAYER_POS)
	assert_that(_live_count(spawner)).is_equal(3)
	assert_that(spawner._traffic.size()).is_equal(3)
	assert_that(spawner._drivers.size()).is_equal(3)
	var despawned := spawner._traffic.duplicate()
	spawner.update(Vector3(5000.0, 0.0, 5000.0))
	assert_that(spawner._traffic.size()).is_equal(0)
	assert_that(spawner._drivers.size()).is_equal(0)
	for vehicle in despawned:
		assert_that(vehicle != null).is_true()
		assert_that(vehicle.is_queued_for_deletion()).is_true()
	await get_tree().process_frame
	assert_that(_live_count(spawner)).is_equal(0)

func test_extreme_delta_keeps_ceremony_and_physics_finite() -> void:
	var countdown := RaceCountdown.new()
	countdown.advance(1e6)
	assert_that(countdown.phase()).is_equal("RACE")
	assert_that(countdown.controls_locked()).is_false()
	assert_that(countdown.rev_rpm_override()).is_equal(0.0)
	assert_that(countdown.progress()).is_equal(1.0)
	var top := _starter_top_speed_m()
	var clamped := VehiclePhysics.clamp_arcade_speed(Vector3.FORWARD * 1e9, Vector3.FORWARD, top, _starter_reverse_cap_m())
	assert_that(clamped.is_finite()).is_true()
	assert_that(clamped.length()).is_equal_approx(top, 0.001)
	assert_that(_finite_float(VehiclePhysics.impact_strength(Vector3.ZERO, Vector3.FORWARD * 1e6, 1e-3))).is_true()
	assert_that(_finite_float(VehiclePhysics.impact_strength(Vector3.ZERO, Vector3.ONE, 1e6))).is_true()