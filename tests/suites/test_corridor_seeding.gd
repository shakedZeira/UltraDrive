# tests/suites/test_corridor_seeding.gd
extends GdUnitTestSuite

## P2 corridor-seeding gate: CorridorPlanner (pure, deterministic blueprint ->
## RoadDef) satisfies the plan's targets — 60+ km of classified networks, exact
## per-tier population, correct closed/open semantics per class (the open
## hub->pass connector never draws a phantom chord), driveable Ys, and the
## determinism contract (same seed -> same chain hash, different seed ->
## different). Fully headless: every call is a static plan() with an empty
## height_provider, so this suite needs no scene, no Terrain3D and no frames.

## P2 plan size: the 12 base corridors (hub ring/connector/loop, highway ring,
## hub-coast, hub-highway ramp, 2 touge, 2 coast, 2 dirt) plus the 7 return
## connectors and access ramps the planner now emits:
##   highway-hub-ramp, highway-pass-ramp, pass-highway-ramp,
##   coast-highway-ramp, touge-highway-ramp, spawn-highway-ramp,
##   hub-access-ramp.
const ROAD_COUNT := 19

# Highway-ring ellipse, the same locus CorridorPlanner._access_ramp measures its
# merge clearance against. A raw radial compare against the nearest ring VERTEX
# cannot express it: the ring is an ellipse, and the pass ramp's source sits
# inside it (normalised radius 0.30).
const RING_CENTER := Vector2(4400.0, 2250.0)
const RING_AXIS_X := 4600.0
const RING_AXIS_Z := 3550.0
# Float32 noise on Y and on ~4.6 km ring coordinates, not a relaxed bound.
const RING_EPS := 0.01

## Signed metres from `p2d` to the highway-ring ellipse along its own ray out of
## the ring centre: positive outside the carriageway, negative inside.
func _ring_signed_offset(p2d: Vector2) -> float:
	var radial := p2d - RING_CENTER
	var radial_len := radial.length()
	if radial_len < 0.0001:
		return -INF
	var ray := radial / radial_len
	var locus := 1.0 / sqrt(pow(ray.x / RING_AXIS_X, 2.0) + pow(ray.y / RING_AXIS_Z, 2.0))
	return radial_len - locus

## Which side of the ring an access ramp lives on, from its source point: -1.0
## when the source is inside the ellipse (pass), +1.0 when it is outside.
func _merge_side(ramp: RoadDef) -> float:
	var src := Vector2(ramp.points[0].x, ramp.points[0].z)
	var nx := (src.x - RING_CENTER.x) / RING_AXIS_X
	var nz := (src.y - RING_CENTER.y) / RING_AXIS_Z
	return -1.0 if (nx * nx + nz * nz) < 1.0 else 1.0

func _plan(seed: int) -> Array[RoadDef]:
	return CorridorPlanner.plan(seed)

## Lookup by id, never by plan position: the corridor list grows, so a
## positional index (e.g. defs[3] == highway-ring) silently starts pointing at
## a different road. Returns null when the id is missing.
func _def_by_id(defs: Array[RoadDef], id: String) -> RoadDef:
	for def in defs:
		if def.id == id:
			return def
	return null

## The highway ring's centreline, resolved by id.
func _highway_ring(defs: Array[RoadDef]) -> Array[Vector3]:
	var empty: Array[Vector3] = []
	var ring_def := _def_by_id(defs, "highway-ring")
	assert_that(ring_def).is_not_null()
	if ring_def == null:
		return empty
	return ring_def.points

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
	# 5 base arterials (hub-ring, hub-pass, pass-loop, hub-coast,
	# hub-highway-ramp) + 6 appended arterials (highway-hub-ramp,
	# highway-pass-ramp, pass-highway-ramp, coast-highway-ramp,
	# spawn-highway-ramp, hub-access-ramp) = 11. touge gains
	# touge-highway-ramp, so touge 3 and coastal/dirt stay at 2.
	assert_that(arterial).is_equal(11)
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
		# The two return connectors and the hub access ramp were appended after
		# this table was written; all three are open chains (their endpoints sit
		# on a loop vertex and on the hub-basin anchor far apart), so they belong
		# in the open branch of the same gap rule.
		"highway-hub-ramp": false, "highway-pass-ramp": false, "hub-access-ramp": false,
	}
	var defs: Array[RoadDef] = _plan(CorridorPlanner.MASTER_SEED)
	# The table must cover the plan exactly: a missing key would make
	# expect_closed[def.id] return null and silently skip the closed check.
	assert_int(expect_closed.size()).is_equal(ROAD_COUNT)
	for def in defs:
		assert_bool(expect_closed.has(def.id)).is_true()
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
## that runs parallel to the highway ring at the ring's Y, offset clear of the
## carriageway on the RAMP'S OWN SIDE of the ring ellipse, with offset tapering
## monotonically to 0 at the landing. Endpoint is the ring vertex verbatim
## (XZ+Y). No ramp point in the last 250 m of the approach ALONG THE CHAIN
## drops more than 0.5 m below the nearest ring vertex Y.
func test_access_ramp_merge_lane_geometry() -> void:
	var defs: Array[RoadDef] = CorridorPlanner.plan(CorridorPlanner.MASTER_SEED)
	var ring: Array[Vector3] = _highway_ring(defs)
	assert_that(ring.size()).is_greater_equal(2)
	var ramp_ids := ["pass-highway-ramp", "coast-highway-ramp", "touge-highway-ramp", "spawn-highway-ramp"]
	for ramp_id in ramp_ids:
		var ramp_def := _def_by_id(defs, ramp_id)
		assert_that(ramp_def).is_not_null()
		if ramp_def == null:
			continue
		var pts: Array[Vector3] = ramp_def.points
		var n := pts.size()
		assert_that(n).is_greater_equal(10)
		
		# Endpoint exact match (zero-distance junction)
		var end := pts[n - 1]
		var matches := false
		for rp in ring:
			if rp.distance_to(end) < 0.001:
				matches = true
				break
		assert_that(matches).is_true()
		
		# The lane sits on the ramp's own side of the ring: outside for a source
		# outside the ellipse (coast / touge / spawn), inside for the pass ramp,
		# whose source is inside it. The previous raw radial check ("further from
		# the ring centre than the nearest ring vertex") cannot express that, and
		# is unsatisfiable for the pass ramp.
		var side := _merge_side(ramp_def)
		
		# Runner: last 8 points (7 runner + approach end)
		var runner_start_idx := n - 8
		var prev_offset := -1.0
		for i in range(runner_start_idx, n):
			var p := pts[i]
			var p2d := Vector2(p.x, p.z)
			
			# Find nearest ring vertex
			var min_ring_dist := INF
			var nearest_ring_y := 0.0
			for rp in ring:
				var dist := p2d.distance_to(Vector2(rp.x, rp.z))
				if dist < min_ring_dist:
					min_ring_dist = dist
					nearest_ring_y = rp.y
			var offset := side * _ring_signed_offset(p2d)
			
			# On the ramp's side of the ring locus (the landing is on it)
			if i < n - 1:
				assert_float(offset).is_greater_equal(-RING_EPS)
			
			# At-grade Y (within 0.5 m of ring Y)
			assert_float(absf(p.y - nearest_ring_y)).is_less_equal(0.5)
			
			# Offset shrinks monotonically
			if prev_offset >= 0.0 and i > runner_start_idx + 1:
				assert_float(min_ring_dist).is_less_equal(prev_offset + 0.1)
			prev_offset = min_ring_dist
		
		# Approach settle: the stretch within 250 m of the merge ENTRY measured
		# ALONG THE CHAIN, not as the crow flies to the landing vertex. The
		# plan-view measure was the premise bug here: the spawn approach runs
		# past within 250 m of the landing vertex while still ~1.4 km upstream
		# (indices 32..57), where it is legitimately still climbing, so the
		# assertion fired 26 times on correct geometry. Chain distance is the
		# measure the profile actually implements, so "within 250 m of the merge"
		# now means the merge zone instead of a fly-over 1.4 km upstream.
		# (No monotonic-Y claim here: the highway is banked, so the merge lane
		# that follows the ring legitimately rises and falls by +/-16 m.)
		var window_first := runner_start_idx
		var walked := 0.0
		for i in range(runner_start_idx - 1, -1, -1):
			walked += Vector2(pts[i].x, pts[i].z).distance_to(Vector2(pts[i + 1].x, pts[i + 1].z))
			if walked > 250.0:
				break
			window_first = i
		assert_int(window_first).is_less_equal(runner_start_idx)
		for i in range(window_first, runner_start_idx):
			var p := pts[i]
			var nearest_ring_y := 0.0
			var min_d := INF
			for rp in ring:
				var d := Vector2(p.x, p.z).distance_to(Vector2(rp.x, rp.z))
				if d < min_d:
					min_d = d
					nearest_ring_y = rp.y
			# At grade before the merge: never under the highway roadbed.
			assert_float(p.y).is_greater_equal(nearest_ring_y - 0.5)

## No ramp-ring self-intersection (headless, XZ plane): no ramp segment may cross
## any highway-ring segment, over the WHOLE chain (approach and merge lane). The
## only legal contact is the landing, where the ramp's last point IS a ring
## vertex; segments sharing that endpoint are skipped. The old planner crossed
## the ring 3 times on the pass ramp and twice on the spawn ramp, which also
## moved the RoadGraph junction off the merge and onto the far side of the
## highway.
func test_access_ramp_no_self_intersection() -> void:
	var defs: Array[RoadDef] = CorridorPlanner.plan(CorridorPlanner.MASTER_SEED)
	var ring: Array[Vector3] = _highway_ring(defs)
	var ramp_ids := ["pass-highway-ramp", "coast-highway-ramp", "touge-highway-ramp", "spawn-highway-ramp"]
	for ramp_id in ramp_ids:
		var ramp_def := _def_by_id(defs, ramp_id)
		assert_that(ramp_def).is_not_null()
		if ramp_def == null:
			continue
		var pts: Array[Vector3] = ramp_def.points
		
		var crossings := 0
		var first_cross := ""
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
					crossings += 1
					if first_cross.is_empty():
						first_cross = "ramp segment %d vs ring segment %d" % [i, j]
		assert_int(crossings).append_failure_message("%s: %s" % [ramp_id, first_cross]).is_equal(0)

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