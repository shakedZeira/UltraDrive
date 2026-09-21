# tests/suites/test_traffic_driving.gd
extends GdUnitTestSuite

## S6 living-traffic driving gates. TrafficDriver steers every spawned vehicle
## along its road chain through the same input_override seam rivals use --
## with the CONVERGENT law (positive steer = left turn), so a car actually
## tracks the road instead of diverging like the inverted AIController sign.
## Covers steer direction for left/right targets, throttle/brake response to
## cruise mismatch, closed-ring target progression (monotonic arc advance),
## the inert no-chain fallback that never hands back to player input, and the
## spawner's attach-on-spawn / free-on-despawn driver lifecycle. Headless-safe
## and leak-free: stub VehiclePhysics cars are childed into the suite so the
## driver's global-position reads stay fast (global_transform reads on an out-of-
## tree RigidBody3D are pathologically slow, ~0.5 s per update call, which made
## this suite ~80x slower), and after_test frees every spawner/network/car node
## that entered the tree. Expected saving vs. in-tree stubs: ~256 s.

const CAR_SCENE := "res://scenes/vehicle/player_car.tscn"
const RING_RADIUS := 200.0
const RING_POINTS := 96
const PLAYER_POS := Vector3.ZERO
## Player far away in front of the stub cars (forward -Z): proximity band and
## stuck logic must not interfere with pure curve-follow assertions.
const FAR_PLAYER := Vector3(0.0, 0.0, -1000.0)

var _managed_spawners: Array = []
var _managed_nodes: Array = []
var _managed_stubs: Array = []

func before_test() -> void:
	_managed_spawners.clear()
	_managed_nodes.clear()
	_managed_stubs.clear()

func after_test() -> void:
	for spawner in _managed_spawners:
		if is_instance_valid(spawner):
			for child in spawner.get_children():
				if is_instance_valid(child):
					child.free()
			spawner.free()
	for node in _managed_nodes:
		if is_instance_valid(node):
			node.free()
	for stub in _managed_stubs:
		if is_instance_valid(stub):
			stub.free()
	_managed_spawners.clear()
	_managed_nodes.clear()
	_managed_stubs.clear()

func _build_ring() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in RING_POINTS:
		var angle := TAU * float(i) / float(RING_POINTS)
		points.append(Vector3(cos(angle) * RING_RADIUS, 0.0, sin(angle) * RING_RADIUS))
	return points

## Bare VehiclePhysics childed into the tree at the suite origin: _ready runs
## (no wheels present, but nothing steps physics while these tests run, so the
## null wheel refs are never dereferenced), and the driver's global_position /
## global_basis reads are instant -- the same reads on an out-of-tree body are
## pathologically slow (probed at ~0.5 s per update call).
func _new_stub_car(pos: Vector3) -> VehiclePhysics:
	var car := VehiclePhysics.new()
	add_child(car)
	car.position = pos
	_managed_stubs.append(car)
	return car

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

func test_steers_left_for_target_on_the_left() -> void:
	var car := _new_stub_car(Vector3.ZERO)
	var driver := TrafficDriver.new()
	driver.configure(car, [Vector3.ZERO, Vector3(-10.0, 0.0, -10.0)], false)
	driver.update(FAR_PLAYER, 1.0 / 60.0)
	# Target offset (-1,0,-1)*n is on the car's LEFT (its basis.x is +X), so the
	# convergent law must yield positive steer (positive steer = left turn).
	assert_float(car.input_override.x).is_greater(0.3)
	assert_float(car.input_override.x).is_less_equal(1.0)

func test_steers_right_for_target_on_the_right() -> void:
	var car := _new_stub_car(Vector3.ZERO)
	var driver := TrafficDriver.new()
	driver.configure(car, [Vector3.ZERO, Vector3(10.0, 0.0, -10.0)], false)
	driver.update(FAR_PLAYER, 1.0 / 60.0)
	assert_float(car.input_override.x).is_less(-0.3)
	assert_float(car.input_override.x).is_greater_equal(-1.0)

func test_throttles_when_below_cruise() -> void:
	var car := _new_stub_car(Vector3.ZERO)
	car.current_speed_kmh = 0.0
	var driver := TrafficDriver.new()
	driver.configure(car, [Vector3.ZERO, Vector3(-10.0, 0.0, -10.0)], false)
	driver.update(FAR_PLAYER, 1.0 / 60.0)
	assert_float(car.input_override.y).is_greater(0.5)

func test_brakes_when_above_cruise() -> void:
	var car := _new_stub_car(Vector3.ZERO)
	car.current_speed_kmh = TrafficDriver.CRUISE_KMH + 60.0
	var driver := TrafficDriver.new()
	driver.configure(car, [Vector3.ZERO, Vector3(-10.0, 0.0, -10.0)], false)
	driver.update(FAR_PLAYER, 1.0 / 60.0)
	assert_float(car.input_override.y).is_less(-0.3)

func test_target_progresses_monotonically_around_closed_ring() -> void:
	var ring := _build_ring()
	var car := _new_stub_car(ring[0])
	var driver := TrafficDriver.new()
	driver.configure(car, ring, true)
	var last_angle := -INF
	for _frame in range(120):
		driver.update(FAR_PLAYER, 1.0 / 60.0)
		var target: Vector3 = driver.get_target_waypoint()
		assert_that(is_finite(target.x)).is_true()
		var on_road := INF
		for point in ring:
			on_road = minf(on_road, point.distance_to(target))
		assert_float(on_road).is_less_equal(2.0)
		var angle := atan2(target.z, target.x)
		if last_angle > -INF:
			var delta_angle := angle - last_angle
			while delta_angle < -PI:
				delta_angle += TAU
			assert_float(delta_angle).is_greater_equal(0.0)
		last_angle = angle
		# Kinematic follow: park the stub on the target so the lookahead walk
		# advances forward instead of re-aiming at the same neighbour forever.
		car.position = target

func test_inert_without_a_chain_never_falls_back_to_player_input() -> void:
	var car := _new_stub_car(Vector3.ZERO)
	var driver := TrafficDriver.new()
	driver.configure(car, [], true)
	driver.update(FAR_PLAYER, 1.0 / 60.0)
	# Exact Vector2.ZERO would route the car through InputManager; a held idle
	# throttle keeps it inert under HOLD_THROTTLE instead.
	assert_that(car.input_override).is_not_equal(Vector2.ZERO)
	assert_float(car.input_override.y).is_equal_approx(TrafficDriver.HOLD_THROTTLE, 0.0001)

func test_spawner_attaches_a_driver_per_vehicle_and_drives_update() -> void:
	var network := _new_network()
	var spawner := _new_spawner(network)
	for _frame in range(200):
		spawner.update(PLAYER_POS)
	assert_that(_live_count(spawner)).is_equal(3)
	for vehicle in spawner._traffic:
		assert_that(spawner._drivers.has(vehicle)).is_true()
		assert_that(spawner._drivers[vehicle]).is_not_null()
		# AI-driven either way: a ring car close to the player may legitimately
		# brake (proximity stop), so only the non-zero override is guaranteed.
		assert_that(vehicle.input_override).is_not_equal(Vector2.ZERO)

func test_despawn_freeing_the_vehicle_also_releases_its_driver() -> void:
	var network := _new_network()
	var spawner := _new_spawner(network)
	for _frame in range(200):
		spawner.update(PLAYER_POS)
	assert_that(spawner._traffic.size()).is_equal(3)
	assert_that(spawner._drivers.size()).is_equal(3)
	spawner.update(Vector3(5000.0, 0.0, 5000.0))
	# Drivers are dropped in the same pass the vehicles are despawned, so the
	# RefCounted ones free themselves without waiting on queue_free().
	assert_that(spawner._traffic.size()).is_equal(0)
	assert_that(spawner._drivers.size()).is_equal(0)

func test_living_world_passes_delta_through_to_spawner() -> void:
	var spawner := _new_spawner(_new_network(), 1)
	var car := _new_stub_car(Vector3.ZERO)
	var driver := TrafficDriver.new()
	driver.configure(car, _build_ring(), true)
	spawner._traffic.append(car)
	spawner._drivers[car] = driver

	var player := Node3D.new()
	player.name = "PlayerCar"
	add_child(player)
	_managed_nodes.append(player)
	var living := LivingWorld.new()
	add_child(living)
	_managed_nodes.append(living)
	living._traffic_spawner = spawner
	living.player_path = NodePath(player.get_path())
	car.position = Vector3(200.0, 0.0, 0.0)
	# Player ahead of the car along its forward (-Z): far enough past RESUME_GAP
	# that proximity slow/stop never engages and the cruise throttle fires.
	player.position = Vector3(200.0, 0.0, -30.0)

	living._physics_process(1.0 / 60.0)
	# The player position routed through LivingWorld drove the driver this
	# tick, so the override must have been (re)written from the stub's idle.
	assert_float(car.input_override.y).is_greater(0.5)

## Straight-ahead two-point chain: steer stays 0 so corner_target == cruise and
## longitudinal responses isolate the player-proximity behaviour.
func _straight_chain() -> Array[Vector3]:
	return [Vector3.ZERO, Vector3(0.0, 0.0, -20.0)]

func test_proximity_slow_fires_only_inside_the_band() -> void:
	var car := _new_stub_car(Vector3.ZERO)
	var driver := TrafficDriver.new()
	driver.configure(car, _straight_chain(), false)
	car.current_speed_kmh = TrafficDriver.CRUISE_KMH
	# Outside the band (15 m gap, player straight ahead): pure cruise hold.
	driver.update(Vector3(0.0, 0.0, -15.0), 1.0 / 60.0)
	assert_float(car.input_override.y).is_equal_approx(TrafficDriver.HOLD_THROTTLE, 0.0001)
	# Inside the slow band (8 m): speed target scales to 60% => braking.
	driver.update(Vector3(0.0, 0.0, -8.0), 1.0 / 60.0)
	assert_float(car.input_override.y).is_less(-0.2)
	# Inside the stop gap (4 m): full stop command.
	driver.update(Vector3(0.0, 0.0, -4.0), 1.0 / 60.0)
	assert_float(car.input_override.y).is_equal_approx(-1.0, 0.0001)

func test_proximity_player_behind_never_fires() -> void:
	var car := _new_stub_car(Vector3.ZERO)
	var driver := TrafficDriver.new()
	driver.configure(car, _straight_chain(), false)
	car.current_speed_kmh = TrafficDriver.CRUISE_KMH
	# Player 4 m behind the traffic nose (car faces -Z): no influence at all,
	# the car keeps cruising exactly as with an empty band.
	driver.update(Vector3(0.0, 0.0, 4.0), 1.0 / 60.0)
	assert_float(car.input_override.y).is_equal_approx(TrafficDriver.HOLD_THROTTLE, 0.0001)

func test_proximity_stop_holds_until_the_gap_reopens() -> void:
	var car := _new_stub_car(Vector3.ZERO)
	var driver := TrafficDriver.new()
	driver.configure(car, _straight_chain(), false)
	car.current_speed_kmh = TrafficDriver.CRUISE_KMH
	# Gap collapses to 4 m: latch the stop.
	driver.update(Vector3(0.0, 0.0, -4.0), 1.0 / 60.0)
	assert_float(car.input_override.y).is_equal_approx(-1.0, 0.0001)
	# Gap reopens to 9 m, still short of RESUME_GAP: stays put (hysteresis).
	driver.update(Vector3(0.0, 0.0, -9.0), 1.0 / 60.0)
	assert_float(car.input_override.y).is_less(0.0)
	# Gap fully reopens (12 m): stop releases, cruise resumes.
	driver.update(Vector3(0.0, 0.0, -12.0), 1.0 / 60.0)
	assert_float(car.input_override.y).is_equal_approx(TrafficDriver.HOLD_THROTTLE, 0.0001)

func test_parked_driver_never_drives() -> void:
	var car := _new_stub_car(Vector3.ZERO)
	var driver := TrafficDriver.new()
	driver.configure(car, _straight_chain(), false)
	driver.set_parked(true)
	assert_that(driver.is_parked()).is_true()
	for _frame in range(120):
		car.current_speed_kmh = float(_frame) * 0.5
		# Even inside the stop/slow band and with a pushing speed, the parked
		# car only ever holds the brake override -- never steers nor throttles.
		driver.update(Vector3(0.0, 0.0, -4.0), 1.0 / 60.0)
		assert_that(car.input_override).is_equal(Vector2(0.0, -TrafficDriver.HOLD_BRAKE))
		assert_float(car.input_override.y).is_less(0.0)
	# Parked cars never accumulate stuck time either.
	assert_that(driver.get_rescue_count()).is_equal(0)

func test_stuck_driver_teleports_to_a_road_point_once() -> void:
	var ring := _build_ring()
	var car := _new_stub_car(ring[0])
	var driver := TrafficDriver.new()
	driver.configure(car, ring, true)
	# The stub never moves: 5+ s of ticks triggers the teleport to a chain point.
	for _frame in range(320):
		driver.update(FAR_PLAYER, 1.0 / 60.0)
	assert_that(driver.get_rescue_count()).is_equal(1)
	# In-tree stubs read their real pose back, so the rescue teleport target
	# lands on the chain exactly as the driver placed it (global == local at
	# the suite origin).
	assert_that(ring.has(car.position)).is_true()
	var rescued_at := car.position
	# Reset at the new anchor: the immediate next tick must NOT re-rescue, and
	# the teleport happened exactly once so far.
	driver.update(FAR_PLAYER, 1.0 / 60.0)
	assert_that(driver.get_rescue_count()).is_equal(1)
	assert_that(car.position).is_equal(rescued_at)

func test_spawner_parked_ratio_spawns_only_parked_drivers() -> void:
	var spawner := _new_spawner(_new_network())
	spawner.parked_ratio = 1.0
	for _frame in range(200):
		spawner.update(PLAYER_POS)
	assert_that(_live_count(spawner)).is_equal(3)
	for vehicle in spawner._traffic:
		var driver: TrafficDriver = spawner._drivers[vehicle]
		assert_that(driver.is_parked()).is_true()
		assert_float(vehicle.input_override.y).is_less(0.0)

func test_spawner_zero_parked_ratio_spawns_no_parked_drivers() -> void:
	var spawner := _new_spawner(_new_network())
	spawner.parked_ratio = 0.0
	for _frame in range(200):
		spawner.update(PLAYER_POS)
	for vehicle in spawner._traffic:
		var driver: TrafficDriver = spawner._drivers[vehicle]
		assert_that(driver.is_parked()).is_false()