# tests/suites/test_open_world_hud.gd
extends GdUnitTestSuite

## Open-world HUD drive-path gates. In free roam the same HUD/cluster rig the
## races use sits on the open-world scene, but its data source used to be
## hijacked: traffic cars were spawned from player_car.tscn, whose
## PlayerCarController._ready re-registers itself as VehicleManager.player_car
## and nulls it on despawn -- so the cluster jumped between a traffic car's
## gauges and an empty slot. These tests pin the fix (TrafficSpawner strips the
## controller before the vehicle enters the tree) and cap the open-world
## dressing/traffic budget so the scene stays within the headless/perf contract.

const OPEN_WORLD_SCENE := "res://scenes/world/open_world_root.tscn"
const CAR_SCENE := "res://scenes/vehicle/player_car.tscn"
const RING_RADIUS := 200.0
const RING_POINTS := 96
const PLAYER_POS := Vector3.ZERO
const FAR_PLAYER := Vector3(5000.0, 0.0, 5000.0)

var _managed_nodes: Array = []

func before_test() -> void:
	_managed_nodes.clear()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

func after_test() -> void:
	for node in _managed_nodes:
		if is_instance_valid(node):
			node.free()
	_managed_nodes.clear()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

func _build_ring() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in RING_POINTS:
		var angle := TAU * float(i) / float(RING_POINTS)
		points.append(Vector3(cos(angle) * RING_RADIUS, 0.0, sin(angle) * RING_RADIUS))
	return points

func _new_stub_car(pos: Vector3) -> VehiclePhysics:
	var car := VehiclePhysics.new()
	car.position = pos
	_managed_nodes.append(car)
	return car

func _new_network() -> RoadNetwork:
	var network := RoadNetwork.new()
	add_child(network)
	_managed_nodes.append(network)
	network.add_road(_build_ring(), 8.0)
	return network

func _new_spawner(network: RoadNetwork, max_count: int = 3) -> TrafficSpawner:
	var spawner := TrafficSpawner.new()
	spawner.road_network = network
	spawner.vehicle_scene = load(CAR_SCENE)
	spawner.max_traffic = max_count
	spawner.spawn_radius = 220.0
	add_child(spawner)
	_managed_nodes.append(spawner)
	return spawner

func _live_count(spawner: TrafficSpawner) -> int:
	var n := 0
	for child in spawner.get_children():
		if child is VehiclePhysics:
			n += 1
	return n

func _spawn_traffic(spawner: TrafficSpawner) -> void:
	for _frame in range(200):
		spawner.update(PLAYER_POS)

func test_traffic_never_overwrites_registered_player() -> void:
	var player := _new_stub_car(PLAYER_POS)
	VehicleManager.register_player_car(player)
	var spawner := _new_spawner(_new_network())
	_spawn_traffic(spawner)
	assert_that(_live_count(spawner)).is_equal(3)
	# The real player must still own the slot even though every traffic car
	# instantiated the full player scene.
	assert_that(VehicleManager.get_player_car()).is_same(player)

func test_traffic_never_owns_controller_or_probe() -> void:
	var spawner := _new_spawner(_new_network())
	_spawn_traffic(spawner)
	for vehicle in spawner._traffic:
		assert_that(vehicle.get_node_or_null("PlayerCarController")).is_null()
		var body := vehicle.get_node_or_null("CarBody") as Node3D
		if body != null:
			assert_that(body.get_node_or_null("CarProbe")).is_null()

func test_traffic_despawn_keeps_player_slot() -> void:
	var player := _new_stub_car(PLAYER_POS)
	VehicleManager.register_player_car(player)
	var spawner := _new_spawner(_new_network())
	_spawn_traffic(spawner)
	assert_that(_live_count(spawner)).is_equal(3)
	# Despawning a traffic car must not null the player slot (the pre-fix
	# failure mode that froze the cluster when traffic dropped out of range).
	# Assert on _traffic, not children: queue_free() defers the node removal
	# past the end of this call.
	spawner.update(FAR_PLAYER)
	assert_that(spawner._traffic.size()).is_equal(0)
	assert_that(VehicleManager.get_player_car()).is_same(player)

func test_open_world_hud_tracks_real_player_while_traffic_loads() -> void:
	var runner := scene_runner(OPEN_WORLD_SCENE)
	# Traffic spawns one vehicle per update at max 15, so the grid is fully
	# loaded by frame ~15-30; 90 frames keeps the whole load phase under the
	# HUD without the 240-frame soak. Expected saving ~12 s.
	await runner.simulate_frames(90)
	var scene := runner.scene()
	var player := scene.get_node_or_null("%PlayerCar") as VehiclePhysics
	assert_that(player).is_not_null()
	assert_that(scene.get_node_or_null("HUD")).is_not_null()
	# The HUD cluster's data source must be the real player the whole time,
	# even once open-world traffic spawns from the same player scene.
	assert_that(VehicleManager.get_player_car()).is_same(player)
	var traffic := scene.get_node_or_null("TrafficSpawner") as TrafficSpawner
	if traffic != null and traffic._traffic.size() > 0:
		assert_that(VehicleManager.get_player_car()).is_same(player)

func test_open_world_traffic_budget_caps() -> void:
	var packed := load(OPEN_WORLD_SCENE) as PackedScene
	assert_that(packed).is_not_null()
	var scene := packed.instantiate()
	assert_that(scene).is_not_null()
	if scene == null:
		return
	var traffic := scene.get_node_or_null("TrafficSpawner") as TrafficSpawner
	assert_that(traffic).is_not_null()
	if traffic == null:
		scene.free()
		return
	assert_that(traffic.max_traffic).is_greater_equal(1)
	assert_that(traffic.max_traffic).is_less_equal(15)
	assert_that(traffic.spawn_radius).is_less_equal(300.0)
	assert_that(traffic.vehicle_scene).is_not_null()
	scene.free()

func test_open_world_dressing_static_budget() -> void:
	var packed := load(OPEN_WORLD_SCENE) as PackedScene
	assert_that(packed).is_not_null()
	var scene := packed.instantiate()
	assert_that(scene).is_not_null()
	if scene == null:
		return
	# The scene ships with one static Foliage + 5 static PropScatterer nodes
	# and no runtime RegionDresser: dressing budget stays bounded and static.
	var foliage := scene.get_node_or_null("Foliage")
	assert_that(foliage).is_not_null()
	if foliage != null:
		assert_that(int(foliage.get("grass_count"))).is_less_equal(1000)
		assert_that(int(foliage.get("tree_count"))).is_less_equal(80)
	var props := 0
	for child in scene.get_children():
		if String(child.name).begins_with("Props"):
			props += 1
	assert_that(props).is_equal(5)
	assert_that(scene.get_node_or_null("RegionDresser")).is_null()
	scene.free()