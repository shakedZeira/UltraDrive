# tests/suites/test_event_placement.gd
extends GdUnitTestSuite

## P6 event placement gate: every car-culture event is a pure, deterministic
## function of the classified road network plus the POI anchors, lands on the
## tier its discipline warrants (touge/drift on TOUGE, drag/marathon on HIGHWAY,
## night loop on the ARTERIAL hub ring), and resolves as a first-class
## POIRegistry marker so the pause-map dots draw automatically. Headless-safe:
## no scene tree, no frames, no Terrain3D.

const ANCHORS: Array[Vector3] = [
	Vector3(128.0, 2.2, 128.0),
	Vector3(1536.0, 6.0, 1536.0),
	Vector3(5888.0, 2.5, 1536.0),
	Vector3(3840.0, 10.0, 2304.0),
	Vector3(5632.0, 35.0, 5632.0),
]

const EVENT_KINDS := ["touge_duel", "drag_strip", "drift_zone", "night_street_loop", "marathon_highway"]

func _defs() -> Array[RoadDef]:
	return CorridorPlanner.plan(CorridorPlanner.MASTER_SEED, Callable(), {})

func test_place_returns_every_event_family_plus_one_time_attack_per_anchor() -> void:
	var events: Dictionary = EventRegistry.place(_defs(), ANCHORS)
	assert_that(events.size()).is_equal(EVENT_KINDS.size() + ANCHORS.size())
	for kind in EVENT_KINDS:
		assert_that(events.has(kind)).is_true()
	for i in ANCHORS.size():
		assert_that(events.has("time_attack_%d" % i)).is_true()

func test_every_event_is_classified_with_a_finite_position() -> void:
	var events: Dictionary = EventRegistry.place(_defs(), ANCHORS)
	for event_id: String in events.keys():
		var event: Dictionary = events[event_id]
		assert_that(event.has("kind")).is_true()
		assert_that(event.has("name")).is_true()
		assert_that(event.has("road_id")).is_true()
		assert_that(String(event["road_id"]).is_empty()).is_false()
		var pos := event["position"] as Vector3
		assert_that(is_finite(pos.x)).is_true()
		assert_that(is_finite(pos.y)).is_true()
		assert_that(is_finite(pos.z)).is_true()
		# The stage string must be the human name of the event's own tier.
		var tier := int(event["tier"])
		assert_that(String(event["stage"])).is_equal(RoadDef.tier_name(tier))

func test_touge_duel_lands_on_a_touge_corridor() -> void:
	var events: Dictionary = EventRegistry.place(_defs(), ANCHORS)
	var event: Dictionary = events["touge_duel"]
	assert_that(int(event["tier"])).is_equal(RoadDef.Tier.TOUGE)
	var road_id := String(event["road_id"])
	assert_that(["touge-a", "touge-b"].has(road_id)).is_true()
	var extra: Dictionary = event["extra"]
	assert_that(float(extra["mean_gradient"])).is_greater_equal(0.0)

func test_drift_zone_lands_on_a_touge_corridor() -> void:
	var events: Dictionary = EventRegistry.place(_defs(), ANCHORS)
	var event: Dictionary = events["drift_zone"]
	assert_that(int(event["tier"])).is_equal(RoadDef.Tier.TOUGE)
	var extra: Dictionary = event["extra"]
	assert_that(float(extra["turn_deg"])).is_greater(0.0)

func test_drag_and_marathon_land_on_the_highway_ring() -> void:
	var events: Dictionary = EventRegistry.place(_defs(), ANCHORS)
	var drag: Dictionary = events["drag_strip"]
	assert_that(int(drag["tier"])).is_equal(RoadDef.Tier.HIGHWAY)
	assert_that(String(drag["road_id"])).is_equal("highway-ring")
	assert_that(float(drag["extra"]["run_length_m"])).is_greater(0.0)
	var marathon: Dictionary = events["marathon_highway"]
	assert_that(int(marathon["tier"])).is_equal(RoadDef.Tier.HIGHWAY)
	var extra: Dictionary = marathon["extra"]
	assert_that(float(extra["length_m"])).is_greater(0.0)
	assert_that(int(extra["laps"])).is_equal(1)

func test_night_street_loop_spins_the_hub_ring_for_three_laps() -> void:
	var events: Dictionary = EventRegistry.place(_defs(), ANCHORS)
	var event: Dictionary = events["night_street_loop"]
	assert_that(int(event["tier"])).is_equal(RoadDef.Tier.ARTERIAL)
	assert_that(String(event["road_id"])).is_equal("hub-ring")
	assert_that(int(event["extra"]["laps"])).is_equal(3)

func test_time_attack_sites_sit_on_their_anchor() -> void:
	var events: Dictionary = EventRegistry.place(_defs(), ANCHORS)
	for i in ANCHORS.size():
		var event: Dictionary = events["time_attack_%d" % i]
		var pos := event["position"] as Vector3
		assert_that(pos.distance_to(ANCHORS[i])).is_less(0.001)
		assert_that(is_finite(float(event["extra"]["road_clearance_m"]))).is_true()

func test_same_master_seed_produces_identical_placement() -> void:
	var first: Dictionary = EventRegistry.place(_defs(), ANCHORS)
	var second: Dictionary = EventRegistry.place(_defs(), ANCHORS)
	assert_that(second).is_equal(first)

func test_events_resolve_as_poi_registry_markers() -> void:
	var events: Dictionary = EventRegistry.place(_defs(), ANCHORS)
	var ids := POIRegistry.get_poi_ids()
	for event_id: String in events.keys():
		assert_that(ids.has(event_id)).is_true()
		assert_that(POIRegistry.has_poi(event_id)).is_true()
		var poi: Dictionary = POIRegistry.get_poi(event_id)
		assert_that(poi.has("position")).is_true()
		assert_that(poi.has("name")).is_true()
		assert_that(poi.has("stage")).is_true()