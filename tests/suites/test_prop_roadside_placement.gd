# tests/suites/test_prop_roadside_placement.gd
extends GdUnitTestSuite

## Roadside prop placement (the "props bundle": scatter throughout the map,
## biased NEAR roads). PropScatterer draws a `roadside_fraction` share of every
## prop type in a corridor alongside a road centreline instead of the annulus, so
## the dressing hugs the highways the player actually drives. Pinned here:
##  * pure roadside (fraction 1.0) keeps every prop inside the requested
##    [roadside_min_dist, roadside_max_dist] band and never inside a road
##    (half-width + ROAD_CLEARANCE_MARGIN, via the shared road_clearance_info);
##  * the per-road near bound is raised to the road's own half-width + margin, so
##    a 24 m highway clears 15 m and a 7 m dirt road 6.5 m;
##  * road picks are tier-weighted (HIGHWAY > DIRT);
##  * determinism: same seed -> same placements, and a region with no road near
##    it places BIT-IDENTICALLY to one with a road network attached (the shared
##    token budget), while fraction 0.0 vs 1.0 on the same seed differ.
## Headless-safe: everything is synchronous mesh/placement math, no tree walking.

const MARGIN_EPS := 0.001
const ROAD_X := 400.0

func _straight(points: Array[Vector3], tier: int) -> RoadDef:
	return RoadDef.make(tier, points, "", false)

func _road_network(defs: Array[RoadDef]) -> RoadNetwork:
	var network := auto_free(RoadNetwork.new()) as RoadNetwork
	for def: RoadDef in defs:
		network.add_road_def(def)
	return network

func _scatterer(network: RoadNetwork, preset: Dictionary, origin: Vector3) -> PropScatterer:
	var scatterer := auto_free(PropScatterer.new()) as PropScatterer
	scatterer.road_network = network
	scatterer.configure(preset)
	scatterer.position = origin
	add_child(scatterer)
	scatterer.generate()
	return scatterer

func _straight_x(z: float) -> Array[Vector3]:
	return [Vector3(-ROAD_X, 0.0, z), Vector3(ROAD_X, 0.0, z)]

## Custom preset big enough that the whole road corridor is inside the region
## reach (radius), so the roadside branch never falls back to the annulus.
func _roadside_preset(count: int, fraction: float, spacing: float = 5.0) -> Dictionary:
	return {
		"radius": 900.0,
		"inner_clear_radius": 0.0,
		"seed": 5150,
		"road_threshold": 6.0,
		"placement_attempts": 64,
		"roadside_fraction": fraction,
		"roadside_min_dist": 3.0,
		"roadside_max_dist": 18.0,
		"props": {"rock": {"count": count, "min_spacing": spacing}},
	}

## Every placed prop sits in the requested roadside band of SOME road centreline
## and none of them is inside a road.
func test_roadside_mode_keeps_props_in_the_corridor_band() -> void:
	var network := _road_network([_straight(_straight_x(0.0), RoadDef.Tier.ARTERIAL)])
	var scatterer := _scatterer(network, _roadside_preset(30, 1.0), Vector3.ZERO)
	var placed: PackedVector3Array = scatterer.get_instance_transforms("rock")
	assert_int(placed.size()).is_equal(30)
	var defs: Array[RoadDef] = network.get_road_defs()
	for local_pos: Vector3 in placed:
		var info := PropScatterer.road_clearance_info(scatterer.to_global(local_pos), defs)
		var distance := float(info["distance"])
		# Inside [roadside_min_dist, roadside_max_dist] of the centreline ...
		assert_that(distance).is_greater_equal(scatterer.roadside_min_dist - MARGIN_EPS)
		assert_that(distance).is_less_equal(scatterer.roadside_max_dist + MARGIN_EPS)
		# ... and never inside the carriageway itself.
		assert_that(distance).is_greater_equal(
			float(info["half_width"]) + PropScatterer.ROAD_CLEARANCE_MARGIN - MARGIN_EPS
		)
		assert_bool(PropScatterer.is_clear_of_road(scatterer.to_global(local_pos), network, 0.0)).is_true()

## The near bound is per road: it is raised to that road's half-width + the
## clearance margin (24 m highway -> 15 m, 7 m dirt -> 6.5 m) and never below
## road_threshold, while the far bound always leaves room above it.
func test_roadside_band_clears_each_road_half_width() -> void:
	var scatterer := auto_free(PropScatterer.new()) as PropScatterer
	scatterer.configure(_roadside_preset(1, 1.0))
	scatterer.road_threshold = 6.0
	for tier: int in [RoadDef.Tier.HIGHWAY, RoadDef.Tier.ARTERIAL, RoadDef.Tier.TOUGE,
			RoadDef.Tier.COASTAL, RoadDef.Tier.DIRT]:
		var def := RoadDef.make(tier, _straight_x(0.0))
		var band: Vector2 = scatterer.roadside_band_for(def)
		assert_float(band.x).is_greater_equal(def.width * 0.5 + PropScatterer.ROAD_CLEARANCE_MARGIN)
		assert_float(band.x).is_greater_equal(6.0)
		assert_float(band.y).is_greater(band.x)
		assert_float(band.x).is_less_equal(scatterer.roadside_max_dist)
	# A HIGHWAY is 24 m wide and a DIRT track 7 m, so their bands differ.
	var highway_band: Vector2 = scatterer.roadside_band_for(RoadDef.make(RoadDef.Tier.HIGHWAY, _straight_x(0.0)))
	var dirt_band: Vector2 = scatterer.roadside_band_for(RoadDef.make(RoadDef.Tier.DIRT, _straight_x(0.0)))
	assert_float(highway_band.x).is_greater(dirt_band.x)
	assert_float(highway_band.x).is_greater_equal(12.0 + 3.0)
	assert_float(dirt_band.x).is_greater_equal(3.5 + 3.0)

## Road picks are tier-weighted over the whole network: a highway 400 m from the
## scatterer centre gets more roadside props than the dirt track across the map
## (coarse comparison -- the exact split is allowed to move with the weights).
func test_high_tier_roads_get_more_roadside_props_than_dirt() -> void:
	var highway: Array[RoadDef] = [_straight(_straight_x(0.0), RoadDef.Tier.HIGHWAY)]
	var dirt: Array[RoadDef] = [_straight(_straight_x(400.0), RoadDef.Tier.DIRT)]
	var network := _road_network(highway + dirt)
	var scatterer := _scatterer(network, _roadside_preset(40, 1.0), Vector3(0.0, 0.0, 200.0))
	var placed: PackedVector3Array = scatterer.get_instance_transforms("rock")
	assert_int(placed.size()).is_equal(40)
	var on_highway := 0
	var on_dirt := 0
	for local_pos: Vector3 in placed:
		var world := scatterer.to_global(local_pos)
		var highway_dist := float(PropScatterer.road_clearance_info(world, highway)["distance"])
		var dirt_dist := float(PropScatterer.road_clearance_info(world, dirt)["distance"])
		if highway_dist <= dirt_dist:
			on_highway += 1
		else:
			on_dirt += 1
	assert_int(on_highway + on_dirt).is_equal(40)
	assert_int(on_highway).is_greater(on_dirt)

## Determinism: the same seed and preset place bit-identically, while the two
## modes (annulus vs roadside) on the same seed do not.
func test_roadside_placement_is_deterministic_and_mode_sensitive() -> void:
	var network := _road_network([_straight(_straight_x(0.0), RoadDef.Tier.ARTERIAL)])
	var first := _scatterer(network, _roadside_preset(24, 1.0), Vector3.ZERO)
	var second := _scatterer(network, _roadside_preset(24, 1.0), Vector3.ZERO)
	var annulus := _scatterer(network, _roadside_preset(24, 0.0), Vector3.ZERO)
	assert_that(second.get_instance_transforms("rock")).is_equal(first.get_instance_transforms("rock"))
	assert_that(annulus.get_instance_transforms("rock")).is_not_equal(first.get_instance_transforms("rock"))
	# Fraction 0.0 is the historical annulus: the props are spread over the disc
	# ring, so not even the CLOSEST one sits in the roadside corridor.
	assert_int(annulus.get_instance_transforms("rock").size()).is_equal(24)
	var nearest := INF
	for local_pos: Vector3 in annulus.get_instance_transforms("rock"):
		nearest = minf(nearest, float(PropScatterer.road_clearance_info(
			annulus.to_global(local_pos), network.get_road_defs())["distance"]))
	assert_float(nearest).is_greater(first.roadside_max_dist)

## RNG lockstep: every attempt consumes the same token budget whichever branch it
## takes, so a region whose roads are all out of reach places EXACTLY like the
## same region with no road network at all -- the roadside feature can never
## desync an existing region's placement or count.
func test_roadless_and_far_road_regions_place_identically() -> void:
	var near_network := _road_network([_straight(_straight_x(0.0), RoadDef.Tier.HIGHWAY)])
	var far_network := _road_network([_straight(_straight_x(5000.0), RoadDef.Tier.DIRT)])
	var without := _scatterer(null, _roadside_preset(20, 0.5), Vector3.ZERO)
	var with_far := _scatterer(far_network, _roadside_preset(20, 0.5), Vector3.ZERO)
	var with_near := _scatterer(near_network, _roadside_preset(20, 0.5), Vector3.ZERO)
	assert_that(with_far.get_instance_transforms("rock")).is_equal(without.get_instance_transforms("rock"))
	assert_int(with_far.get_instance_count()).is_equal(without.get_instance_count())
	assert_int(with_near.get_instance_count()).is_equal(without.get_instance_count())
	assert_that(with_near.get_instance_transforms("rock")).is_not_equal(without.get_instance_transforms("rock"))
	# A region on the corridor gets its full budget AND a real roadside share.
	var roadside := 0
	for local_pos: Vector3 in with_near.get_instance_transforms("rock"):
		var distance := float(PropScatterer.road_clearance_info(
			with_near.to_global(local_pos), near_network.get_road_defs())["distance"])
		if distance >= with_near.roadside_min_dist - MARGIN_EPS and distance <= with_near.roadside_max_dist + MARGIN_EPS:
			roadside += 1
	assert_int(roadside).is_greater(with_near.get_instance_count() / 4)
