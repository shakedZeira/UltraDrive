# tests/suites/test_world_map_features.gd
extends GdUnitTestSuite

const MINIMAP_SCRIPT := "res://scripts/ui/minimap.gd"

func _road_chain() -> Array[Vector3]:
	return [
		Vector3(0.0, 0.0, 0.0),
		Vector3(100.0, 0.0, 0.0),
		Vector3(100.0, 0.0, 100.0),
		Vector3(0.0, 0.0, 100.0),
	]

func test_road_source_resolution_group_then_tree_walk() -> void:
	var root := Node.new()
	root.name = "ResolverRoot"
	add_child(root)

	# Group path: RoadNetwork registers itself via _ready(), the resolver must
	# find it and return its chains in add order with the expected first point.
	var network := RoadNetwork.new()
	network.name = "RoadNetwork"
	var chain_a := _road_chain()
	var chain_b: Array[Vector3] = [Vector3(10.0, 0.0, 20.0), Vector3(30.0, 0.0, 40.0)]
	network.add_road(chain_a)
	network.add_road(chain_b, 8.0, false)
	root.add_child(network)

	var resolved = MapRoads.resolve_road_source(root)
	assert_that(resolved == network).is_true()
	if resolved != network:
		return
	var roads := MapRoads.get_roads(resolved)
	assert_that(roads.size()).is_equal(2)
	assert_that(roads[0][0]).is_equal(Vector3(0.0, 0.0, 0.0))
	assert_that(roads[1][0]).is_equal(Vector3(10.0, 0.0, 20.0))

	# Drop the group member: the resolver must fall back to a tree walk and
	# still find a node that exposes get_roads().
	network.remove_from_group(MapRoads.ROAD_GROUP)
	root.remove_child(network)
	network.free()

	var fake_script := GDScript.new()
	fake_script.source_code = "extends Node\n\nfunc get_roads() -> Array:\n\treturn []\n"
	fake_script.reload()
	var fake := Node.new()
	fake.name = "FakeRoads"
	fake.set_script(fake_script)
	root.add_child(fake)

	var walked = MapRoads.resolve_road_source(root)
	assert_that(walked == fake).is_true()
	root.free()

func test_fit_maps_content_into_overlay_rect_with_uniform_scale() -> void:
	var roads: Array = []
	var chain := _road_chain()
	roads.append(chain)
	var player := Vector3(50.0, 1.0, 50.0)
	var content: Array = []
	for p in chain:
		content.append(p)
	content.append(player)
	var draw_size := Vector2(200.0, 200.0)
	var inset := 20.0
	var fit := MapRoads.compute_fit(content, player, draw_size, inset)
	var scale: float = fit["scale"]
	assert_that(scale).is_greater(0.0)
	for p in content:
		var screen: Vector2 = MapRoads.world_to_screen(p, fit)
		assert_that(screen.x).is_between(inset - 0.001, draw_size.x - inset + 0.001)
		assert_that(screen.y).is_between(inset - 0.001, draw_size.y - inset + 0.001)
	var a: Vector2 = MapRoads.world_to_screen(Vector3(0.0, 0.0, 0.0), fit)
	var b: Vector2 = MapRoads.world_to_screen(Vector3(50.0, 0.0, 0.0), fit)
	var c: Vector2 = MapRoads.world_to_screen(Vector3(0.0, 0.0, 50.0), fit)
	# Uniform on both axes: 50 world-meters map to the same screen delta.
	assert_float(b.x - a.x).is_equal_approx(c.y - a.y, 0.001)
	# North-up: moving +Z must not shift X.
	assert_float(c.x - a.x).is_less_equal(0.001)

func test_clip_circle_keeps_points_inside_radius() -> void:
	var chain: Array[Vector3] = []
	for i in range(-10, 11):
		chain.append(Vector3(float(i) * 40.0, 0.0, 0.0))
	var local := MapRoads.world_to_local_points(chain, Vector3.ZERO, Vector2.ZERO, 1.0)
	var clipped := MapRoads.clip_circle(local, Vector2.ZERO, 100.0)
	assert_that(clipped.size()).is_greater_equal(3)
	for i in clipped.size():
		var p: Vector2 = clipped[i]
		assert_float(p.distance_to(Vector2.ZERO)).is_less_equal(100.0 + 0.001)
	# Boundary-crossing segments stay intact: exact on-circle entry/exit points.
	assert_that(clipped[0]).is_equal_approx(Vector2(-100.0, 0.0), Vector2(0.001, 0.001))
	assert_that(clipped[clipped.size() - 1]).is_equal_approx(Vector2(100.0, 0.0), Vector2(0.001, 0.001))

func test_minimap_runs_without_vehicle_or_road_source() -> void:
	var minimap := Control.new()
	minimap.name = "Minimap"
	minimap.size = Vector2(200.0, 200.0)
	minimap.set_script(load(MINIMAP_SCRIPT))
	add_child(minimap)
	await await_idle_frame()
	await await_idle_frame()
	assert_that(is_instance_valid(minimap)).is_true()
	if is_instance_valid(minimap):
		minimap.free()