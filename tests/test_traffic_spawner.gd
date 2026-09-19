# tests/test_traffic_spawner.gd
extends GdUnitTestSuite

const ROAD_WIDTH := 8.0
const RING_RADIUS := 200.0
const RING_POINTS := 96
const PLAYER_POS := Vector3.ZERO

const BASE_POI_IDS := [
	"festival_hub",
	"lowland_view",
	"dry_lake",
	"pass_entry",
	"alpine_overlook",
]
const EVENT_POI_IDS := [
	"touge_duel",
	"drag_strip",
	"drift_zone",
	"night_street_loop",
	"marathon_highway",
	"time_attack_0",
	"time_attack_1",
	"time_attack_2",
	"time_attack_3",
	"time_attack_4",
	"outbreak",
	"convoy",
]

func _build_ring() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in RING_POINTS:
		var angle := TAU * float(i) / float(RING_POINTS)
		points.append(Vector3(cos(angle) * RING_RADIUS, 0.0, sin(angle) * RING_RADIUS))
	return points

func test_poi_registry_returns_exactly_the_seeded_set() -> void:
	var ids := POIRegistry.get_poi_ids()
	# Base landscape POIs first, then the S7 event markers derived from the
	# classified road network (same master seed -> same ids, same order): the
	# 6 P6 families plus the two open-world brands (outbreak / convoy).
	assert_array(ids).contains_exactly([
		"festival_hub",
		"lowland_view",
		"dry_lake",
		"pass_entry",
		"alpine_overlook",
		"touge_duel",
		"drag_strip",
		"drift_zone",
		"night_street_loop",
		"marathon_highway",
		"time_attack_0",
		"time_attack_1",
		"time_attack_2",
		"time_attack_3",
		"time_attack_4",
		"outbreak",
		"convoy",
	])
	assert_that(ids.size()).is_equal(BASE_POI_IDS.size() + EVENT_POI_IDS.size())
	for poi_id: String in ids:
		var data := POIRegistry.get_poi(poi_id)
		assert_that(data.has("name")).is_true()
		assert_that(data.has("stage")).is_true()
		assert_that(data.has("position")).is_true()
		assert_that(POIRegistry.has_poi(poi_id)).is_true()
		assert_that(data["position"] is Vector3).is_true()
		if poi_id in BASE_POI_IDS:
			# Base landmark POIs live inside the map tile footprint.
			var pos: Vector3 = data["position"]
			assert_that(pos.x >= 0.0 and pos.x <= 6144.0).is_true()
			assert_that(pos.z >= 0.0 and pos.z <= 6144.0).is_true()
	assert_that(POIRegistry.has_poi("missing_poi")).is_false()

func test_traffic_spawner_keeps_every_live_vehicle_on_road() -> void:
	var road_network := RoadNetwork.new()
	add_child(road_network)
	road_network.add_road(_build_ring(), ROAD_WIDTH)

	var spawner := TrafficSpawner.new()
	spawner.road_network = road_network
	spawner.vehicle_scene = load("res://scenes/vehicle/player_car.tscn")
	spawner.max_traffic = 6
	spawner.spawn_radius = 220.0
	add_child(spawner)

	var live: Array[VehiclePhysics] = []
	for _frame in range(200):
		spawner.update(PLAYER_POS)
		live.clear()
		for child in spawner.get_children():
			if child is VehiclePhysics:
				live.append(child)
		for vehicle in live:
			assert_that(road_network.is_on_road(vehicle.global_position, 10.0)).is_true()

	assert_that(live.size()).is_equal(6)