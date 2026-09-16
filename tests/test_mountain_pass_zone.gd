# tests/test_mountain_pass_zone.gd
extends GdUnitTestSuite

const OPEN_WORLD_SCENE := "res://scenes/world/open_world_root.tscn"
const STANDALONE_PASS_SCENE := "res://scenes/track/mountain_pass.tscn"

func test_zone_and_roads_present() -> void:
	var runner := scene_runner(OPEN_WORLD_SCENE)
	await runner.simulate_frames(1)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return
	var zone := scene.get_node_or_null("MountainPassZone")
	assert_that(zone).is_not_null()
	var network := scene.get_node_or_null("RoadNetwork") as RoadNetwork
	assert_that(network).is_not_null()
	if network == null:
		return
	assert_that(network.get_roads().size()).is_greater_equal(3)

func test_all_roads_conformed_above_terrain() -> void:
	var runner := scene_runner(OPEN_WORLD_SCENE)
	await runner.simulate_frames(10)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return
	var terrain := scene.get_node("Terrain3D") as Terrain3D
	assert_that(terrain).is_not_null()
	if terrain == null:
		return
	var network := scene.get_node_or_null("RoadNetwork") as RoadNetwork
	assert_that(network).is_not_null()
	if network == null:
		return
	var checked := 0
	for road in network.get_roads():
		for i in range(0, road.size(), 4):
			var p: Vector3 = road[i]
			var ground: float = terrain.data.get_height(p)
			if ground != ground:
				continue  # road point lies outside the baked 3x3 ring around spawn
			assert_that(ground).is_less_equal(p.y + 0.05)
			checked += 1
	assert_that(checked).is_greater_equal(20)

func test_standalone_mountain_pass_unchanged() -> void:
	var runner := scene_runner(STANDALONE_PASS_SCENE)
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return
	var terrain := scene.get_node("GrassGround") as Terrain3D
	assert_that(terrain).is_not_null()
	if terrain == null:
		return
	var points: Array = scene.get("road_points")
	assert_that(points.size()).is_equal(36)
	var first: Vector3 = points[0]
	assert_that(terrain.data.get_height(first)).is_less(first.y)