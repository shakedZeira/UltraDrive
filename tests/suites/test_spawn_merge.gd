# tests/suites/test_spawn_merge.gd
extends GdUnitTestSuite

## The spawn on-ramp (spawn-highway-ramp) merges into the highway ring as a real
## interchange: one junction node shared with the ring, a lane that arrives
## tangent to the highway's outside edge, runs edge-to-edge with it, tapers in on
## the highway's own banked surface, and lands on a ring vertex -- driveable from
## the spawn onto the highway and back.
##
## Regression it pins: the ramp used to be planned against ring vertex 96, 2.1 km
## away and behind the direction of travel; its approach rode beside the ring for
## ~3.8 km, turned a 179.7 deg hairpin and came back on top of itself, so in game
## it was a road next to the highway that never joined it (5.9 km long, 317 deg
## of total turning).

const RAMP_ID := "spawn-highway-ramp"
const RING_ID := "highway-ring"

var _managed: Array[Node] = []

func after_test() -> void:
	for node in _managed:
		if is_instance_valid(node):
			node.free()
	_managed.clear()

func _plan() -> Array[RoadDef]:
	return CorridorPlanner.plan(CorridorPlanner.MASTER_SEED)

func _def(defs: Array[RoadDef], id: String) -> RoadDef:
	for d in defs:
		if d.id == id:
			return d
	return null

func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

## Nearest ring segment to `p` (XZ): {"seg", "t", "d"}.
func _ring_proj(ring: Array[Vector3], p: Vector3) -> Dictionary:
	var best := {"d": INF, "seg": 0, "t": 0.0}
	var n := ring.size()
	for i in n:
		var a := _xz(ring[i])
		var b := _xz(ring[(i + 1) % n])
		var ab := b - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 <= 0.0 else clampf((_xz(p) - a).dot(ab) / l2, 0.0, 1.0)
		var d := (a + ab * t).distance_to(_xz(p))
		if d < float(best["d"]):
			best = {"d": d, "seg": i, "t": t}
	return best

## Height of the highway's rendered surface plane (TrackBuilder frames, blended
## linearly between vertices exactly as the strip mesh is), extended sideways,
## at the XZ of `p`.
func _highway_surface_y(ring: Array[Vector3], p: Vector3) -> float:
	var pr := _ring_proj(ring, p)
	var i: int = pr["seg"]
	var j := (i + 1) % ring.size()
	var t: float = pr["t"]
	var fa := TrackBuilder.frame_at(ring, i, true, CorridorPlanner.HIGHWAY_BANKING, PackedFloat32Array())
	var fb := TrackBuilder.frame_at(ring, j, true, CorridorPlanner.HIGHWAY_BANKING, PackedFloat32Array())
	var c: Vector3 = (fa["center"] as Vector3).lerp(fb["center"], t)
	var cross: Vector3 = (fa["cross"] as Vector3).lerp(fb["cross"], t)
	var ch := Vector2(cross.x, cross.z)
	var l := (_xz(p) - _xz(c)).dot(ch) / ch.length_squared()
	return c.y + cross.y * l

## Index of the first lane point: the first point within the edge-to-edge offset.
func _lane_first(ramp: RoadDef, ring: Array[Vector3]) -> int:
	for i in ramp.points.size():
		if float(_ring_proj(ring, ramp.points[i])["d"]) <= CorridorPlanner.SPAWN_LANE_OFFSET + 0.05:
			return i
	return -1

## One shared junction node: the ramp starts at the spawn anchor, ends ON a ring
## vertex verbatim, and RoadGraph registers exactly that vertex as the junction.
func test_ramp_shares_a_junction_node_with_the_ring() -> void:
	var defs := _plan()
	var ramp := _def(defs, RAMP_ID)
	var ring := _def(defs, RING_ID)
	assert_that(ramp).is_not_null()
	assert_that(ring).is_not_null()
	if ramp == null or ring == null:
		return
	assert_that(ramp.points[0]).is_equal_approx(CorridorPlanner.SPAWN_ANCHOR, Vector3(0.001, 0.001, 0.001))
	var end: Vector3 = ramp.points[ramp.points.size() - 1]
	assert_float(end.distance_to(ring.points[CorridorPlanner.SPAWN_LANDING_IDX])).is_less(0.001)
	var topo := RoadGraph.build_topology(defs, 15.0)
	var ri := defs.find(ring)
	var ai := defs.find(ramp)
	var found := 0
	for j in topo["junctions"]:
		var a: int = j["road_a"]
		var b: int = j["road_b"]
		if (a == ri and b == ai) or (a == ai and b == ri):
			found += 1
			assert_float(float(j["dist"])).is_less(0.001)
			assert_float((j["point"] as Vector3).distance_to(end)).is_less(0.001)
	assert_int(found).is_equal(1)

## The merge is short and direct: the spawn is ~440 m from the ring, so the ramp
## is a ~1.3 km road with one gentle curve, not a 5.9 km detour with a hairpin.
func test_ramp_is_direct_with_no_hairpin() -> void:
	var defs := _plan()
	var ramp := _def(defs, RAMP_ID)
	if ramp == null:
		fail("no spawn ramp")
		return
	var pts := ramp.points
	var length := 0.0
	var total_turn := 0.0
	var min_radius := INF
	for i in range(1, pts.size()):
		length += _xz(pts[i] - pts[i - 1]).length()
		if i < pts.size() - 1:
			var d0 := _xz(pts[i] - pts[i - 1])
			var d1 := _xz(pts[i + 1] - pts[i])
			var ang := absf(d0.normalized().angle_to(d1.normalized()))
			total_turn += rad_to_deg(ang)
			if ang > 0.0001:
				min_radius = minf(min_radius, 0.5 * (d0.length() + d1.length()) / ang)
	assert_float(length).is_less(1600.0)
	assert_float(total_turn).append_failure_message("total turning").is_less(90.0)
	# 250 m is comfortable at on-ramp speed (~80-100 km/h, < 3.1 m/s^2 lateral).
	assert_float(min_radius).append_failure_message("min curve radius").is_greater(250.0)

## Tangent merge: every lane point heads within a few degrees of the highway's
## own direction (the taper angle is the only deviation), the ramp arrives at
## the lane already tangent, and the visible lane ends parallel to the ring.
func test_lane_is_tangent_to_the_highway() -> void:
	var defs := _plan()
	var ramp := _def(defs, RAMP_ID)
	var ring_def := _def(defs, RING_ID)
	if ramp == null or ring_def == null:
		fail("missing roads")
		return
	var ring := ring_def.points
	var pts := ramp.points
	var first := _lane_first(ramp, ring)
	assert_int(first).is_greater(0)
	var worst := 0.0
	for i in range(maxi(first - 1, 1), pts.size()):
		var dir := _xz(pts[i] - pts[i - 1]).normalized()
		var pr := _ring_proj(ring, pts[i - 1].lerp(pts[i], 0.5))
		var a := _xz(ring[int(pr["seg"])])
		var b := _xz(ring[(int(pr["seg"]) + 1) % ring.size()])
		var tan := (b - a).normalized()
		worst = maxf(worst, rad_to_deg(acos(clampf(absf(dir.dot(tan)), 0.0, 1.0))))
	assert_float(worst).append_failure_message("worst lane heading vs ring (deg)").is_less(8.0)
	var n := pts.size()
	var last_dir := _xz(pts[n - 1] - pts[n - 3]).normalized()
	var ring_dir := _xz(ring[CorridorPlanner.SPAWN_LANDING_IDX] - ring[CorridorPlanner.SPAWN_LANDING_IDX + 1]).normalized()
	assert_float(rad_to_deg(acos(clampf(last_dir.dot(ring_dir), -1.0, 1.0)))).is_less(3.0)

## Height continuity: across its whole width, every lane point of the ramp lies
## on the highway's banked surface plane -- flush where the two roadbeds only
## touch, at most SPAWN_LANE_SINK below it where they overlap (the highway then
## draws and drives on top). No step, no gap, no floating lane.
func test_lane_is_flush_with_the_highway_surface() -> void:
	var defs := _plan()
	var ramp := _def(defs, RAMP_ID)
	var ring_def := _def(defs, RING_ID)
	if ramp == null or ring_def == null:
		fail("missing roads")
		return
	var ring := ring_def.points
	var first := _lane_first(ramp, ring)
	assert_that(ramp.bank_angles.size()).is_equal(ramp.points.size())
	var worst := 0.0
	var checked := 0
	for i in range(first, ramp.points.size()):
		var f := TrackBuilder.frame_at(ramp.points, i, false, 0.0, ramp.bank_angles)
		var c: Vector3 = f["center"]
		var cross: Vector3 = f["cross"]
		for side in [-1.0, 0.0, 1.0]:
			var p: Vector3 = c + cross * (ramp.width * 0.5 * side)
			var dy := _highway_surface_y(ring, p) - p.y
			# Ramp never above the highway surface, never more than the sink below.
			assert_float(dy).append_failure_message("idx %d side %.0f" % [i, side]) \
				.is_between(-0.01, CorridorPlanner.SPAWN_LANE_SINK + 0.02)
			worst = maxf(worst, absf(dy))
			checked += 1
	assert_int(checked).is_greater_equal(24)

## A real acceleration lane: >= 230 m edge-to-edge with the highway before the
## taper, and the leg after the taper lies entirely on the highway roadbed (no
## dead-end stub sticking out beside it).
func test_acceleration_lane_and_no_stub() -> void:
	var defs := _plan()
	var ramp := _def(defs, RAMP_ID)
	var ring_def := _def(defs, RING_ID)
	if ramp == null or ring_def == null:
		fail("missing roads")
		return
	var ring := ring_def.points
	var pts := ramp.points
	var first := _lane_first(ramp, ring)
	var run := 0.0
	var i := first + 1
	while i < pts.size() and float(_ring_proj(ring, pts[i])["d"]) >= CorridorPlanner.SPAWN_LANE_OFFSET - 0.05:
		run += _xz(pts[i] - pts[i - 1]).length()
		i += 1
	assert_float(run).append_failure_message("edge-to-edge run (m)").is_greater_equal(230.0)
	var ring_half := ring_def.width * 0.5
	var hidden := 0
	for k in range(i, pts.size()):
		var d := float(_ring_proj(ring, pts[k])["d"])
		# Strictly inside: the taper-end point itself (outer edges exactly flush)
		# still carries the field-side rail that closes the taper.
		if d + ramp.width * 0.5 < ring_half - 0.05:
			hidden += 1
			# Under the highway surface the ramp carries no rails at all.
			assert_int(ramp.rail_sides_mask_at(k)).append_failure_message("idx %d" % k) \
				.is_equal(RoadDef.RailSide.NONE)
	assert_int(hidden).is_greater_equal(2)
	# The very last points are inside the roadbed: nothing protrudes past the merge.
	var tail_d := float(_ring_proj(ring, pts[pts.size() - 2])["d"])
	assert_float(tail_d + ramp.width * 0.5).is_less_equal(ring_half)

## Vertical profile: hub grade where it crosses the hub ring, a climb no steeper
## than 6 % up to the highway's elevation, never cut into the canonical ground.
## The return ramp sharing the spawn anchor keeps a driveable grade too.
func test_ramp_profile_is_driveable() -> void:
	var defs := _plan()
	var ramp := _def(defs, RAMP_ID)
	var ret := _def(defs, "highway-hub-ramp")
	if ramp == null or ret == null:
		fail("missing roads")
		return
	var terrain := CorridorPlanner.canonical_height_provider()
	var pts := ramp.points
	for i in pts.size():
		var r := _xz(pts[i]).distance_to(_xz(CorridorPlanner.SPAWN_ANCHOR))
		if r <= 116.0 and i < pts.size() / 2:
			assert_float(pts[i].y).is_equal_approx(CorridorPlanner.SPAWN_ANCHOR.y, 0.001)
		assert_float(pts[i].y).append_failure_message("idx %d under ground" % i) \
			.is_greater_equal(float(terrain.call(_xz(pts[i]))) - 1.0)
	for road in [ramp, ret]:
		var rp: Array[Vector3] = (road as RoadDef).points
		var worst := 0.0
		for i in range(1, rp.size()):
			var h := _xz(rp[i] - rp[i - 1]).length()
			if h > 0.5:
				worst = maxf(worst, absf(rp[i].y - rp[i - 1].y) / h)
		assert_float(worst).append_failure_message("%s max grade" % (road as RoadDef).id).is_less(0.065)

## Driveable both ways through the live RoadNetwork: spawn ramp <-> highway ring
## is a direct route edge, and the hub ring reaches the highway through it. The
## highway's rails are gapped over the lane (which lies ahead of the landing in
## ring index) and nowhere behind the landing.
func test_network_routes_spawn_to_highway_and_back() -> void:
	var defs := _plan()
	var network := RoadNetwork.new()
	add_child(network)
	_managed.append(network)
	var idx := {}
	for d in defs:
		idx[d.id] = network.add_road_def(d)
	network.recompute_rails()
	var there := network.route(int(idx[RAMP_ID]), int(idx[RING_ID]))
	var back := network.route(int(idx[RING_ID]), int(idx[RAMP_ID]))
	assert_that(there).is_equal(PackedInt32Array([int(idx[RAMP_ID]), int(idx[RING_ID])]))
	assert_that(back).is_equal(PackedInt32Array([int(idx[RING_ID]), int(idx[RAMP_ID])]))
	var hub_route := network.route(int(idx["hub-ring"]), int(idx[RAMP_ID]))
	assert_int(hub_route.size()).is_equal(2)
	var ring_builder := network.get_children()[int(idx[RING_ID])] as TrackBuilder
	var ring_pts: Array[Vector3] = _def(defs, RING_ID).points
	var landing := ring_pts[CorridorPlanner.SPAWN_LANDING_IDX]
	var lane_start := ring_pts[CorridorPlanner.SPAWN_LANE_START_IDX]
	var forward_gap := false
	for g in ring_builder._rail_gaps:
		var s: Vector3 = g["start"]
		var e: Vector3 = g["end"]
		if s.distance_to(landing) < 0.001:
			var e_idx := -1
			for k in ring_pts.size():
				if ring_pts[k].distance_to(e) < 0.001:
					e_idx = k
			forward_gap = e_idx >= CorridorPlanner.SPAWN_LANE_START_IDX
		# No gap may END on the landing (that is the old backward cut).
		assert_float(e.distance_to(landing)).is_greater(0.001)
	assert_bool(forward_gap).override_failure_message(
		"highway rail not gapped from the landing over the lane to %s" % lane_start).is_true()

## Bug 3f investigation pin: `hub-pass` crosses ~6 m over `hub-coast` near
## x 1796 (the handoff blamed `highway-ring`, which crosses hub-coast at x 683).
## The BAKED ground keeps the whole lower carriageway clear there: the carve's
## "lower road wins near a tie" rule already cuts the underpass. So the reported
## terrain-over-road (seen only while the camera moves) is not the height bake;
## see open_world_status.md section 11. This pins the bake side of it.
func test_underpass_bake_keeps_the_lower_road_clear() -> void:
	var defs := _plan()
	var lower := _def(defs, "hub-coast")
	var upper := _def(defs, "hub-pass")
	if lower == null or upper == null:
		fail("missing roads")
		return
	var hit := Vector2.INF
	var dir := Vector2.ZERO
	var lower_y := 0.0
	var upper_y := 0.0
	for i in lower.points.size() - 1:
		var a1 := _xz(lower.points[i])
		var a2 := _xz(lower.points[i + 1])
		for j in upper.points.size() - 1:
			var b1 := _xz(upper.points[j])
			var b2 := _xz(upper.points[j + 1])
			var x = Geometry2D.segment_intersects_segment(a1, a2, b1, b2)
			if x != null and (x as Vector2).x > 1500.0:
				hit = x as Vector2
				dir = (a2 - a1).normalized()
				lower_y = lerpf(lower.points[i].y, lower.points[i + 1].y, hit.distance_to(a1) / a1.distance_to(a2))
				upper_y = lerpf(upper.points[j].y, upper.points[j + 1].y, hit.distance_to(b1) / b1.distance_to(b2))
	assert_bool(hit != Vector2.INF).is_true()
	if hit == Vector2.INF:
		return
	assert_float(upper_y - lower_y).is_greater(4.0)
	var roads: Array = []
	for d in defs:
		roads.append(d.points)
	var region := Vector2i(floori(hit.x / TerrainBaker.REGION_SIZE), floori(hit.y / TerrainBaker.REGION_SIZE))
	const W := 256
	var img := TerrainBaker.new().bake_region(region, 1.0, W, roads)
	var step := TerrainBaker.REGION_SIZE / float(W)
	var origin := Vector2(region.x * TerrainBaker.REGION_SIZE, region.y * TerrainBaker.REGION_SIZE)
	var normal := Vector2(-dir.y, dir.x)
	var worst := -INF
	var samples := 0
	for along in range(-15, 16, 3):
		for lateral in [-4.0, -2.0, 0.0, 2.0, 4.0]:
			var q := hit + dir * float(along) + normal * float(lateral)
			var ix := floori((q.x - origin.x) / step)
			var iz := floori((q.y - origin.y) / step)
			if ix < 1 or iz < 1 or ix >= W - 1 or iz >= W - 1:
				continue
			worst = maxf(worst, img.get_pixel(ix, iz).r - lower_y)
			samples += 1
	assert_int(samples).is_greater_equal(20)
	# Across the whole lower carriageway the ground stays at (or under) the lower
	# road, never raised toward the upper road's height.
	assert_float(worst).append_failure_message("terrain above hub-coast at the crossing (m)").is_less(0.6)
