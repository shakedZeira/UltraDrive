extends GdUnitTestSuite

const OPEN_WORLD_SCENE := "res://scenes/world/open_world_root.tscn"
const OPEN_WORLD_SPAWN := Vector3(128.0, 2.2, 128.0)

func test_open_world_instantiates_player_at_spawn_with_cameras() -> void:
	var runner := scene_runner(OPEN_WORLD_SCENE)
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	var player := scene.get_node_or_null("%PlayerCar") as VehiclePhysics
	assert_that(is_instance_valid(player)).is_true()
	assert_that(player).is_not_null()
	if player == null:
		return
	assert_that(player.global_position.distance_to(OPEN_WORLD_SPAWN)).is_less(8.0)
	var chase := scene.get_node_or_null("ChaseCamera")
	assert_that(chase).is_not_null()
	assert_that(chase.target == player).is_true()
	var orbit := scene.get_node_or_null("OrbitCamera")
	assert_that(orbit).is_not_null()
	assert_that(orbit.target == player).is_true()

func test_open_world_bakes_ground_under_the_player_spawn() -> void:
	# The TerrainSeeder is only ever fed by WorldDriver._push_player_position().
	# If that wiring is missing the seeder never syncs a player position, no
	# region is ever baked, and every Terrain3D height lookup in the world
	# (road conforming, props, foliage) silently reads NaN. Ten frames covers the
	# driver bootstrap (roads first, then the player push) plus the ring pass.
	var runner := scene_runner(OPEN_WORLD_SCENE)
	await runner.simulate_frames(10)
	var scene := runner.scene()
	var terrain := scene.get_node_or_null("Terrain3D") as Terrain3D
	assert_that(terrain).is_not_null()
	if terrain == null:
		return
	var spawn := scene.get_node_or_null("PlayerSpawn") as Node3D
	assert_that(spawn).is_not_null()
	if spawn == null:
		return
	var ground: float = terrain.data.get_height(spawn.global_position)
	assert_that(is_nan(ground)).is_false()
	if is_nan(ground):
		return
	var player := scene.get_node_or_null("%PlayerCar") as VehiclePhysics
	assert_that(player).is_not_null()
	if player == null:
		return
	# The car starts on the ground the seeder wrote, not on the flat-circuit
	# fallback: a couple of metres of settle is all the drop from SPAWN_HEIGHT.
	assert_that(absf(player.global_position.y - ground)).is_less(3.0)

func test_open_world_driver_streams_chunks_around_player() -> void:
	var runner := scene_runner(OPEN_WORLD_SCENE)
	await runner.simulate_frames(3)
	var scene := runner.scene()
	var streamer := scene.get_node_or_null("ChunkStreamer") as ChunkStreamer
	assert_that(streamer).is_not_null()
	if streamer == null:
		return
	assert_that(streamer.get_loaded_chunk_count()).is_greater_equal(25)
	streamer.set_player_position(Vector3(1500.0, 5.0, 1500.0))
	await runner.simulate_frames(1)
	assert_that(streamer.get_loaded_chunk_count()).is_greater_equal(25)

func test_open_world_car_lands_on_ground() -> void:
	var runner := scene_runner(OPEN_WORLD_SCENE)
	# 96 frames was way more soak than a 2.2 m drop needs (fall ~0.67 s after
	# the first-frame ground bake releases the freeze latch); 64 keeps ~0.4 s
	# of post-landing settle with a wide margin. Expected saving ~4 s.
	await runner.simulate_frames(64)
	var scene := runner.scene()
	var player := scene.get_node_or_null("%PlayerCar") as VehiclePhysics
	assert_that(player).is_not_null()
	if player == null:
		return
	assert_that(player.global_position.y).is_greater(-5.0)
	assert_that(player.global_position.y).is_less(5.0)

func test_main_menu_has_free_roam_button() -> void:
	var runner := scene_runner("res://scenes/ui/main_menu.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	assert_that(scene.get_node_or_null("MenuLayout/FreeRoamButton")).is_not_null()
	assert_that((scene.get_node("MenuLayout/FreeRoamButton") as Button).text).is_equal("Free Roam")