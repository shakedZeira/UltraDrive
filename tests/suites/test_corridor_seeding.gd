# tests/suites/test_corridor_seeding.gd
extends GdUnitTestSuite

## P2 corridor-seeding gate: CorridorPlanner (pure, deterministic blueprint ->
## RoadDef) satisfies the plan's targets — 60+ km of classified networks, exact
## per-tier population, correct closed/open semantics per class (the open
## hub->pass connector never draws a phantom chord), driveable Ys, and the
## determinism contract (same seed -> same chain hash, different seed ->
## different). Fully headless: every call is a static plan() with an empty
## height_provider, so this suite needs no scene, no Terrain3D and no frames.

const ROAD_COUNT := 16

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
	assert_that(arterial).is_equal(8)
	assert_that(touge).is_equal(3)
	assert_that(coastal).is_equal(2)
	assert_that(dirt).is_equal(2)
	var found_highway := false
	for def in defs:
		if def.id == "highway-ring":
			found_highway = true
			assert_float(def.width).is_equal_approx(24.0, 0.001)
			assert_int(def.lane_count()).is_equal(4)
			assert_that(def.rails_enabled()).is_true()
			break
	assert_that(found_highway).is_true()

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
	var expect_closed: Dictionary = {
		"hub-ring": true, "hub-pass": false, "pass-loop": true, "highway-ring": true,
		"hub-coast": false, "hub-highway-ramp": false,
		"touge-a": true, "touge-b": true,
		"coast-a": false, "coast-b": false,
		"dirt-a": false, "dirt-b": false,
		"pass-highway-ramp": false, "coast-highway-ramp": false, "touge-highway-ramp": false,
		"spawn-highway-ramp": false,
	}
	var defs: Array[RoadDef] = _plan(CorridorPlanner.MASTER_SEED)
	for def in defs:
		var expected: bool = expect_closed[def.id]
		assert_that(def.closed).is_equal(expected)
		var pts: Array[Vector3] = def.points
		var n := pts.size()
		if n < 2:
			continue
		var avg: float = CorridorPlanner.chain_length_m(pts) / float(n - 1)
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
	var avg: float = CorridorPlanner.chain_length_m(conn) / float(conn.size() - 1)
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
	var defs: Array[RoadDef] = CorridorPlanner.plan(CorridorPlanner.MASTER_SEED, Callable(), {})
	assert_that(defs.size()).is_equal(ROAD_COUNT)
	for def in defs:
		assert_that(def.points.size()).is_greater_equal(2)
	assert_float(_total_km(defs)).is_greater_equal(CorridorPlanner.KM_TARGET)
	# Tier defaults can widen/shrink the network per class.
	var tuned: Array[RoadDef] = CorridorPlanner.plan(CorridorPlanner.MASTER_SEED, Callable(),
		{"km_target": 40.0, "highway_width": 20.0})
	for def in tuned:
		if def.id == "highway-ring":
			assert_float(def.width).is_equal_approx(20.0, 0.001)

## Ramp merge-lane geometry (headless): each access ramp ends with a runner
## that runs parallel to the highway ring at the ring's Y, offset OUTSIDE the
## loop, with offset tapering monotonically to 0. Endpoint is the ring vertex
## verbatim (XZ+Y). No ramp point within 250 m of the junction drops more than
## 0.5 m below the nearest ring vertex Y.
func test_access_ramp_merge_lane_geometry() -> void:
	var defs: Array[RoadDef] = CorridorPlanner.plan(CorridorPlanner.MASTER_SEED)
	var ring: Array[Vector3] = defs[3].points  # highway-ring
	var ring_center := Vector2(4400.0, 2250.0)
	var ramp_ids := ["pass-highway-ramp", "coast-highway-ramp", "touge-highway-ramp", "spawn-highway-ramp"]
	
	for ramp_id in ramp_ids:
		var ramp_def: RoadDef = null
		for def in defs:
			if def.id == ramp_id:
				ramp_def = def
				break
		assert_that(ramp_def).is_not_null()
		var pts: Array[Vector3] = ramp_def.points
		var n := pts.size()
		assert_that(n).is_greater_equal(10)
		
		# Endpoint exact match (zero-distance junction)
		var end := pts[n - 1]
		var matches := false
		for rp in ring:
			if assert_that(rp).is_equal_approx(end, Vector3(0.001, 0.001, 0.001)):
				matches = true
				break
		assert_that(matches).is_true()
		
		# Runner: last 8 points (7 runner + approach end)
		var runner_start_idx := n - 8
		var prev_offset := -1.0
		for i in range(runner_start_idx, n):
			var p := pts[i]
			var p2d := Vector2(p.x, p.z)
			var d_from_center := p2d.distance_to(ring_center)
			
			# Find nearest ring vertex
			var min_ring_dist := INF
			var nearest_ring_y := 0.0
			var nearest_ring_2d := Vector2.ZERO
			for rp in ring:
				var dist := p2d.distance_to(Vector2(rp.x, rp.z))
				if dist < min_ring_dist:
					min_ring_dist = dist
					nearest_ring_y = rp.y
					nearest_ring_2d = Vector2(rp.x, rp.z)
			var offset := min_ring_dist
			var ring_vert_dist_from_center := nearest_ring_2d.distance_to(ring_center)
			
			# Outside or on the ring locus
			assert_float(d_from_center).is_greater_equal(ring_vert_dist_from_center - 0.5)
			
			# At-grade Y (within 0.5 m of ring Y)
			assert_float(absf(p.y - nearest_ring_y)).is_less_equal(0.5)
			
			# Offset shrinks monotonically
			if prev_offset >= 0.0 and i > runner_start_idx + 1:
				assert_float(offset).is_less_equal(prev_offset + 0.1)
			prev_offset = offset
		
		# Approach climb: no point within 250 m of junction below ring Y - 0.5
		for i in range(runner_start_idx):
			var p := pts[i]
			var p2d := Vector2(p.x, p.z)
			var dist_to_junction := p2d.distance_to(Vector2(end.x, end.z))
			if dist_to_junction < 250.0:
				var nearest_ring_y := 0.0
				var min_d := INF
				for rp in ring:
					var d := p2d.distance_to(Vector2(rp.x, rp.z))
					if d < min_d:
						min_d = d
						nearest_ring_y = rp.y
				assert_float(p.y).is_greater_equal(nearest_ring_y - 0.5)

## No ramp-ring self-intersection (headless, XZ plane).
func test_access_ramp_no_self_intersection() -> void:
	var defs: Array[RoadDef] = CorridorPlanner.plan(CorridorPlanner.MASTER_SEED)
	var ring: Array[Vector3] = defs[3].points
	var ramp_ids := ["pass-highway-ramp", "coast-highway-ramp", "touge-highway-ramp", "spawn-highway-ramp"]
	
	for ramp_id in ramp_ids:
		var ramp_def: RoadDef = null
		for def in defs:
			if def.id == ramp_id:
				ramp_def = def
				break
		assert_that(ramp_def).is_not_null()
		var pts: Array[Vector3] = ramp_def.points
		
		for i in range(pts.size() - 1):
			var a1 := pts[i]
			var a2 := pts[i + 1]
			for j in range(ring.size()):
				var b1 := ring[j]
				var b2 := ring[(j + 1) % ring.size()]
				# Skip if segments share the junction endpoint
				if a2.distance_to(b1) < 0.01 or a2.distance_to(b2) < 0.01:
					continue
				if _segments_intersect_xz(a1, a2, b1, b2):
					assert_that(false).is_true()
					return

func _segments_intersect_xz(a1: Vector3, a2: Vector3, b1: Vector3, b2: Vector3) -> bool:
	var p := Vector2(a1.x, a1.z)
	var r := Vector2(a2.x - a1.x, a2.z - a1.z)
	var q := Vector2(b1.x, b1.z)
	var s := Vector2(b2.x - b1.x, b2.z - b1.z)
	
	var rxs := r.x * s.y - r.y * s.x
	var q_p := q - p
	var qpxs := q_p.x * s.y - q_p.y * s.x
	
	if absf(rxs) < 0.0001:
		return false
	
	var t := (q_p.x * r.y - q_p.y * r.x) / rxs
	var u := qpxs / rxs
	
	return t > 0.0 and t < 1.0 and u > 0.0 and u < 1.0