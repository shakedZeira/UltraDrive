# tests/suites/test_map_route.gd
extends GdUnitTestSuite

## P5 fast travel + GPS route line: MapRoads.route_polyline concatenation
## (join chains, trim to the target, dedupe junctions), the screen_to_world
## inverse mapping, static route state, and WorldDriver.fast_travel_to gating
## on WorldDiscovery with a bare headless driver + stub player.

const JUNCTION := Vector3(0.0, 0.0, 100.0)

func _two_roads() -> RoadNetwork:
	var network := RoadNetwork.new()
	network.name = "RoadNetwork"
	network.add_road([Vector3(0, 0, 0), JUNCTION], 8.0, false)
	network.add_road([JUNCTION, Vector3(100, 0, 100)], 8.0, false)
	return network

func _hub_road() -> RoadNetwork:
	var network := RoadNetwork.new()
	network.name = "Hub"
	network.add_road([Vector3(0, 0, 0), Vector3(100, 0, 0), Vector3(100, 0, 100)], 8.0, false)
	return network

func test_route_polyline_joins_two_chains_toward_target() -> void:
	var network := _two_roads()
	var route := MapRoads.route_polyline(network, Vector3(0, 0, 0), Vector3(100, 0, 100))
	assert_that(route.size()).is_equal(3)
	assert_that(route[0]).is_equal(Vector3(0, 0, 0))
	assert_that(route[route.size() - 1]).is_equal(Vector3(100, 0, 100))

	# Reverse direction: the polyline still flows toward the target.
	var reverse := MapRoads.route_polyline(network, Vector3(100, 0, 100), Vector3(0, 0, 0))
	assert_that(reverse.size()).is_equal(2)
	assert_that(reverse[0]).is_equal(Vector3(100, 0, 100))
	assert_that(reverse[reverse.size() - 1]).is_equal(Vector3(0, 0, 0))

func test_route_polyline_same_chain_sub_route_and_guards() -> void:
	var single := _hub_road()
	# from/to on the same road: route() returns that one road; the polyline is
	# the whole chain with the junction duplicate removed.
	var route := MapRoads.route_polyline(single, Vector3(0, 0, 0), Vector3(100, 0, 100))
	assert_that(route.size()).is_equal(3)
	assert_that(route[0]).is_equal(Vector3(0, 0, 0))
	# from == to on a single road yields the full chain.
	var loop := MapRoads.route_polyline(single, Vector3(50, 0, 0), Vector3(50, 0, 0))
	assert_that(loop.size()).is_equal(3)
	# Pure guards: null source and sources without the road API return [].
	assert_that(MapRoads.route_polyline(null, Vector3.ZERO, Vector3.ZERO).is_empty()).is_true()
	var fake := RefCounted.new()
	assert_that(MapRoads.route_polyline(fake, Vector3.ZERO, Vector3.ZERO).is_empty()).is_true()

func test_map_roads_screen_to_world_inverse_and_route_state() -> void:
	MapRoads.clear_route()
	var fit := MapRoads.compute_fit([Vector3(0, 0, 0), Vector3(100, 0, 100)], Vector3.ZERO, Vector2(256, 256), 16.0)
	var world := Vector3(42.0, 0.0, 67.0)
	# screen_to_world is the exact inverse of world_to_screen on the X/Z axes.
	var screen: Vector2 = MapRoads.world_to_screen(world, fit)
	var back := MapRoads.screen_to_world(screen, fit)
	assert_float(back.x).is_equal_approx(world.x, 0.001)
	assert_float(back.z).is_equal_approx(world.z, 0.001)
	# Static route state is shared and clearable.
	assert_that(MapRoads.has_route).is_false()
	MapRoads.set_route(Vector3(10, 0, 20))
	assert_that(MapRoads.has_route).is_true()
	assert_that(MapRoads.route_target).is_equal(Vector3(10, 0, 20))
	MapRoads.clear_route()
	assert_that(MapRoads.has_route).is_false()

func test_fast_travel_gates_on_discovery_and_snaps_car() -> void:
	var driver := WorldDriver.new()
	driver.name = "Driver"
	var player := Node3D.new()
	player.name = "PlayerCar"
	player.position = Vector3(0, 0, 0)
	driver.add_child(player)
	add_child(driver)
	assert_that(driver.is_in_group(WorldDriver.DRIVER_GROUP)).is_true()

	# The driver bootstrapped a WorldDiscovery; teach it one road and reveal it.
	var disc: WorldDiscovery = null
	for candidate in driver.get_children():
		if candidate is WorldDiscovery:
			disc = candidate as WorldDiscovery
			break
	assert_that(disc != null).is_true()
	if disc == null:
		driver.free()
		return
	var defs: Array[RoadDef] = [
		RoadDef.make(RoadDef.Tier.HIGHWAY,
			[Vector3(0, 0, 0), Vector3(100, 0, 0)], "road_x", false),
	]
	disc.configure(defs)
	disc.reveal_at(Vector3(50, 0, 0))
	driver._player = player

	# Unrevealed position: rejected, the car does not move.
	assert_that(driver.fast_travel_to(Vector3(0, 0, 500))).is_false()
	assert_that(player.global_position).is_equal(Vector3(0, 0, 0))
	# Revealed position: accepted and the car snaps onto the road.
	assert_that(driver.fast_travel_to(Vector3(52, 0, 0))).is_true()
	assert_that(player.global_position).is_equal_approx(Vector3(52, 0, 0), Vector3(0.001, 0.001, 0.001))
	driver.free()

func test_driver_reuses_existing_discovery_node() -> void:
	var holder := Node.new()
	holder.name = "Holder"
	add_child(holder)
	var existing := WorldDiscovery.new()
	existing.name = "WorldDiscovery"
	holder.add_child(existing)
	var driver := WorldDriver.new()
	driver.name = "Driver"
	holder.add_child(driver)
	# The driver found the group instance and must not have added a second one.
	assert_that(driver.get_node_or_null("WorldDiscovery") == null).is_true()
	assert_that(driver._discovery == existing).is_true()
	assert_that(holder.get_children().size()).is_equal(2)
	holder.free()