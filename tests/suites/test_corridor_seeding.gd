# tests/suites/test_corridor_seeding.gd
extends GdUnitTestSuite

## P2 corridor-seeding gate: CorridorPlanner (pure, deterministic blueprint ->
## RoadDef) satisfies the plan's targets — 60+ km of classified networks, exact
## per-tier population, correct closed/open semantics per class (the open
## hub->pass connector never draws a phantom chord), driveable Ys, and the
## determinism contract (same seed -> same chain hash, different seed ->
## different). Fully headless: every call is a static plan() with an empty
## height_provider, so this suite needs no scene, no Terrain3D and no frames.

const ROAD_COUNT := 12

func _plan(seed: int) -> Array[RoadDef]:
	return CorridorPlanner.plan(seed)

func _count_tier(defs: Array[RoadDef], tier: int) -> int:
	var c := 0
	for def in defs:
		if def.tier == tier:
			c += 1
	return c

func _network_hash(defs: Array[RoadDef]) -> int:
	var h := 0
	for def in defs:
		h += CorridorPlanner.chain_hash(def.points) * (def.tier + 1)
	return h

func _total_km(defs: Array[RoadDef]) -> float:
	var total := 0.0
	for def in defs:
		total += CorridorPlanner.chain_length_m(def.points)
	return total / 1000.0

## (1) Fixed seed -> total drivable length meets the 60 km plan target.
func test_fixed_seed_total_length_meets_target() -> void:
	var defs := _plan(CorridorPlanner.MASTER_SEED)
	var km := _total_km(defs)
	assert_float(km).is_greater_equal(CorridorPlanner.KM_TARGET)
	assert_that(defs.size()).is_equal(ROAD_COUNT)

## (2) Every class is populated; the seeded emission meets exact minimums.
func test_tier_counts_exact_per_class() -> void:
	var defs := _plan(CorridorPlanner.MASTER_SEED)
	var highway := _count_tier(defs, RoadDef.Tier.HIGHWAY)
	var arterial := _count_tier(defs, RoadDef.Tier.ARTERIAL)
	var touge := _count_tier(defs, RoadDef.Tier.TOUGE)
	var coastal := _count_tier(defs, RoadDef.Tier.COASTAL)
	var dirt := _count_tier(defs, RoadDef.Tier.DIRT)
	assert_that(highway).is_equal(1)
	assert_that(arterial).is_equal(5)
	assert_that(touge).is_equal(2)
	assert_that(coastal).is_equal(2)
	assert_that(dirt).is_equal(2)

## (3) Road-index invariant: defs 0/1/2 reproduce the bootstrap 1:1 — hub ring
## (w12 closed), hub->pass connector (w10 OPEN, ending flush on the pass loop),
## pass loop (w11 closed). The connector is the SAME Catmull-Rom + 10 m
## arc-length path with Y ramp 2.2 -> loop start y.
func test_road_index_invariant_0_1_2() -> void:
	var defs := _plan(CorridorPlanner.MASTER_SEED)
	var hub: Array[Vector3] = defs[0].points
	var conn: Array[Vector3] = defs[1].points
	var pass_loop: Array[Vector3] = defs[2].points
	# defs[0] hub ring.
	assert_that(defs[0].tier).is_equal(RoadDef.Tier.ARTERIAL)
	assert_float(defs[0].width).is_equal_approx(12.0, 0.001)
	assert_that(defs[0].closed).is_true()
	assert_that(hub.size()).is_equal(96)
	assert_that(hub[0]).is_equal_approx(Vector3(238.0, 2.2, 128.0), Vector3(0.001, 0.001, 0.001))
	# defs[1] open connector lands on the hub ring point 0 and the pass loop start.
	assert_that(defs[1].tier).is_equal(RoadDef.Tier.ARTERIAL)
	assert_float(defs[1].width).is_equal_approx(10.0, 0.001)
	assert_that(defs[1].closed).is_false()
	assert_that(conn[0]).is_equal_approx(hub[0], Vector3(0.001, 0.001, 0.001))
	assert_float(conn[0].y).is_equal_approx(2.2, 0.001)
	# defs[2] closed world-offset pass loop; connector ends FLUSH on loop[0] so
	# RoadGraph registers an exact zero-distance junction (test_road_graph parity).
	assert_that(defs[2].tier).is_equal(RoadDef.Tier.ARTERIAL)
	assert_float(defs[2].width).is_equal_approx(11.0, 0.001)
	assert_that(defs[2].closed).is_true()
	assert_that(pass_loop.size()).is_equal(36)
	assert_that(conn[conn.size() - 1]).is_equal_approx(pass_loop[0], Vector3(0.001, 0.001, 0.001))

## (4) Closed/open semantics per class: highway ring + hub ring + pass loop +
## touge loops closed; connector, coastal ribbons, arterial connectors and dirt
## cut-throughs open; an open chain's last point is never coerced back to its
## first (geocheck: gap > 2x average segment for open, <= 2x for closed, the
## same "nearly-touch" rule terrain_baker uses).
func test_closed_correctness_per_class() -> void:
	var expect_closed := {
		"hub-ring": true, "hub-pass": false, "pass-loop": true, "highway-ring": true,
		"hub-coast": false, "hub-highway-ramp": false,
		"touge-a": true, "touge-b": true,
		"coast-a": false, "coast-b": false,
		"dirt-a": false, "dirt-b": false,
	}
	var defs := _plan(CorridorPlanner.MASTER_SEED)
	for def in defs:
		var expected: bool = expect_closed[def.id]
		assert_that(def.closed).is_equal(expected)
		var pts: Array[Vector3] = def.points
		var n := pts.size()
		if n < 2:
			continue
		var avg := CorridorPlanner.chain_length_m(pts) / float(n - 1)
		var gap := pts[n - 1].distance_to(pts[0])
		if expected:
			assert_float(gap).is_less_equal(2.0 * avg)
		else:
			assert_float(gap).is_greater(2.0 * avg)

## (5) The open hub->pass connector must NEVER draw a phantom chord back to the
## hub: its endpoints sit ~3.8 km apart and no closing segment exists.
func test_open_connector_has_no_phantom_chord() -> void:
	var defs := _plan(CorridorPlanner.MASTER_SEED)
	var conn: Array[Vector3] = defs[1].points
	assert_that(defs[1].closed).is_false()
	var gap := conn[conn.size() - 1].distance_to(conn[0])
	assert_float(gap).is_greater(1000.0)
	var avg := CorridorPlanner.chain_length_m(conn) / float(conn.size() - 1)
	assert_float(gap).is_greater(2.0 * avg)

## (6) All road Ys stay driveable: every non-touge point in [-8, 120], every
## touge point <= 300 (the washbed the terrain bake recesses into).
func test_all_road_y_in_driveable_band() -> void:
	var defs := _plan(CorridorPlanner.MASTER_SEED)
	for def in defs:
		var ceiling := 300.0 if def.tier == RoadDef.Tier.TOUGE else 120.0
		for p in def.points:
			assert_float(p.y).is_greater_equal(-8.0)
			assert_float(p.y).is_less_equal(ceiling)

## (7) No drivable centre sits under the P1 SEA interior: non-coastal corridors
## stay >= 2400 m from the sea centre (the deep band), while coastal ribbons hug
## a tight shoreline band around the rim.
func test_no_roads_under_sea_interior() -> void:
	var defs := _plan(CorridorPlanner.MASTER_SEED)
	var sea: Vector2 = TerrainBaker.BIOME_SEA_CENTER
	for def in defs:
		for p in def.points:
			var d := Vector2(p.x, p.z).distance_to(sea)
			if def.tier == RoadDef.Tier.COASTAL:
				assert_float(d).is_between(2550.0, 2700.0)
			else:
				assert_float(d).is_greater_equal(2400.0)

## (8) Determinism: same seed twice -> identical network hash (and the same
## 0/1/2 bootstrap), two seeds -> different networks.
func test_determinism_same_seed_same_chains() -> void:
	var a1 := _plan(CorridorPlanner.MASTER_SEED)
	var a2 := _plan(CorridorPlanner.MASTER_SEED)
	var b := _plan(CorridorPlanner.MASTER_SEED + 7)
	assert_that(_network_hash(a1)).is_equal(_network_hash(a2))
	assert_that(_network_hash(a1)).is_not_equal(_network_hash(b))
	# The bootstrap that guards test_road_graph/test_open_world is bit-stable
	# regardless of seed.
	assert_that(a1[0].points).is_equal(a2[0].points)
	assert_that(a1[1].points).is_equal(a2[1].points)
	assert_that(a1[2].points).is_equal(a2[2].points)

## (9) Headless-pure: a static plan() call with an EMPTY height_provider (no
## scene, no Terrain3D) returns a full, valid network with non-empty chains and
## all tier/length/closed guarantees intact.
func test_headless_pure_static_call_with_empty_callable() -> void:
	var defs := CorridorPlanner.plan(CorridorPlanner.MASTER_SEED, Callable(), {})
	assert_that(defs.size()).is_equal(ROAD_COUNT)
	for def in defs:
		assert_that(def.points.size()).is_greater_equal(2)
	assert_float(_total_km(defs)).is_greater_equal(CorridorPlanner.KM_TARGET)
	# Tier defaults can widen/shrink the network per class.
	var tuned := CorridorPlanner.plan(CorridorPlanner.MASTER_SEED, Callable(),
		{"km_target": 40.0, "highway_width": 20.0})
	for def in tuned:
		if def.id == "highway-ring":
			assert_float(def.width).is_equal_approx(20.0, 0.001)