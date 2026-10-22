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

## Dressing budget of the open world (deliberately re-pinned 2026-10-22 when the
## RegionDresser was wired in, ROADMAP W.6/W.7; the old version asserted the
## dresser was ABSENT). The hand-placed landmark kits stay static (one hub
## Foliage + 5 Props kits); everything else is region-streamed by exactly one
## RegionDresser bound to the seeder/terrain/roads/player, at the bounded
## per-frame budget, with the hub cleared so it is not double-dressed. The
## dresser must not also drive traffic (LivingWorld owns TrafficSpawner).
func test_open_world_dressing_budget() -> void:
	var packed := load(OPEN_WORLD_SCENE) as PackedScene
	assert_that(packed).is_not_null()
	var scene := packed.instantiate()
	assert_that(scene).is_not_null()
	if scene == null:
		return
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
	var dressers := 0
	for child in scene.get_children():
		if child is RegionDresser:
			dressers += 1
	assert_that(dressers).is_equal(1)
	var dresser := scene.get_node_or_null("RegionDresser") as RegionDresser
	assert_that(dresser).is_not_null()
	if dresser != null:
		# Typed Node exports resolve at instantiate only when the scene lists
		# them in the node's node_paths; a bare NodePath is silently dropped
		# (null), which is how the first wiring shipped a dresser that never
		# dressed anything. So assert the RESOLVED nodes.
		assert_that(dresser.terrain_seeder).is_equal(scene.get_node_or_null("TerrainSeeder"))
		assert_that(dresser.terrain).is_equal(scene.get_node_or_null("Terrain3D"))
		assert_that(dresser.road_network).is_equal(scene.get_node_or_null("RoadNetwork"))
		assert_that(dresser.player).is_equal(scene.get_node_or_null("PlayerCar"))
		assert_that(dresser.terrain_seeder).is_not_null()
		assert_that(dresser.player).is_not_null()
		assert_that(dresser.traffic_spawner).is_null()
		# Region grass tufts stay off in the open world (flat-quad mesh reads as
		# green squares on the textured ground); trees/rocks/poles remain.
		assert_that(dresser.region_grass_scale).is_equal(0.0)
		assert_that(dresser.max_dresses_per_frame).is_between(1, 2)
		assert_that(dresser.max_frees_per_frame).is_between(1, 2)
		assert_that(dresser.live_ring_radius).is_equal(TerrainSeeder.RING_RADIUS)
		assert_that(dresser.prefetch_band_radius).is_equal(TerrainSeeder.PREFETCH_RADIUS)
		var hub_cleared := false
		for zone: Vector3 in dresser.clear_zones:
			if Vector2(zone.x, zone.y).distance_to(Vector2(128.0, 128.0)) < 1.0 and zone.z >= 140.0:
				hub_cleared = true
		assert_that(hub_cleared).is_true()
	var seeder := scene.get_node_or_null("TerrainSeeder") as TerrainSeeder
	assert_that(seeder).is_not_null()
	if seeder != null:
		assert_that(seeder.apply_ground_textures).is_true()
		assert_that(seeder.bake_ground_control).is_true()
		# The ~+1 ms LITE ground shader is the shipped default (perf budget).
		assert_that(seeder.ground_texture_quality).is_equal(TerrainTexturing.QUALITY_LITE)
	scene.free()