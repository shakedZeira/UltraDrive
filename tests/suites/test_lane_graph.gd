# tests/suites/test_lane_graph.gd
extends GdUnitTestSuite

## LaneGraph (traffic plan 3.2 / 12.1): lane count and offsets per tier, driving
## side, reversed opposite lanes, connectors through junctions (T, crossing,
## dead-end hairpin, overpass rejected), U-turns at dead ends, lane-change
## adjacency, spatial query, determinism, and the same rules on the real
## corridor network (whatever junctions it reports).

static func _straight(tier: int, from: Vector3, to: Vector3, n: int, id: String, closed := false, width := -1.0) -> RoadDef:
	var pts: Array[Vector3] = []
	for i in n:
		pts.append(from.lerp(to, float(i) / float(n - 1)))
	return RoadDef.make(tier, pts, id, closed, width)

static func _circle(tier: int, center: Vector3, radius: float, n: int, id: String) -> RoadDef:
	var pts: Array[Vector3] = []
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(center + Vector3(cos(a) * radius, 0.0, sin(a) * radius))
	return RoadDef.make(tier, pts, id, true)

static func _graph(defs: Array) -> LaneGraph:
	var topo := RoadGraph.build_topology(defs, RoadNetwork.LINK_THRESHOLD)
	return LaneGraph.build(defs, topo["junctions"])

## Signed lateral offset of p from the road through a->b (+ = right of travel,
## i.e. TrackBuilder's forward x UP side).
static func _lateral(p: Vector3, a: Vector3, b: Vector3) -> float:
	var f := (b - a).normalized()
	var right := f.cross(Vector3.UP).normalized()
	return (p - a).dot(right)

func test_lane_count_and_offsets_per_tier() -> void:
	var hw := _straight(RoadDef.Tier.HIGHWAY, Vector3(0, 0, 0), Vector3(400, 0, 0), 41, "hw")
	var art := _straight(RoadDef.Tier.ARTERIAL, Vector3(0, 0, 500), Vector3(400, 0, 500), 41, "art")
	var g := _graph([hw, art])
	assert_int(g.road_lanes[0].size()).is_equal(4)
	assert_int(g.road_lanes[1].size()).is_equal(2)
	var expect_hw := {0: hw.width / 8.0, 1: 3.0 * hw.width / 8.0}
	for lane in g.road_lanes[0]:
		var mag: float = expect_hw[g.lane_index[lane]]
		for p in g.lane_pts[lane]:
			var lat := _lateral(p, hw.points[0], hw.points[40])
			assert_float(absf(lat)).is_equal_approx(mag, 0.01)
			assert_float(absf(lat)).is_less(hw.width * 0.5)
	for lane in g.road_lanes[1]:
		for p in g.lane_pts[lane]:
			assert_float(absf(_lateral(p, art.points[0], art.points[40]))).is_equal_approx(art.width / 4.0, 0.01)
	assert_float(g.lane_limit[g.road_lanes[0][0]]).is_equal_approx(110.0 / 3.6, 0.01)
	assert_float(g.lane_limit[g.road_lanes[1][0]]).is_equal_approx(80.0 / 3.6, 0.01)

func test_driving_side_and_reversed_lanes() -> void:
	var art := _straight(RoadDef.Tier.ARTERIAL, Vector3(0, 0, 0), Vector3(300, 0, 0), 31, "art")
	var g := _graph([art])
	var fwd_lane := -1
	var rev_lane := -1
	for lane in g.road_lanes[0]:
		if g.lane_dir[lane] > 0:
			fwd_lane = lane
		else:
			rev_lane = lane
	assert_int(fwd_lane).is_not_equal(-1)
	assert_int(rev_lane).is_not_equal(-1)
	# Left-hand traffic: each direction drives on the LEFT of its own travel.
	var side := float(LaneGraph.DRIVE_SIDE)
	var mid_f: Vector3 = g.lane_pts[fwd_lane][g.lane_pts[fwd_lane].size() / 2]
	assert_float(signf(_lateral(mid_f, art.points[0], art.points[30]))).is_equal(side)
	var mid_r: Vector3 = g.lane_pts[rev_lane][g.lane_pts[rev_lane].size() / 2]
	assert_float(signf(_lateral(mid_r, art.points[30], art.points[0]))).is_equal(side)
	# The reverse lane runs end -> start, its tangents point back along the road.
	assert_float(g.lane_pts[rev_lane][0].x).is_greater(290.0)
	assert_float(g.lane_fwd[rev_lane][3].x).is_less(-0.99)
	assert_float(g.lane_fwd[fwd_lane][3].x).is_greater(0.99)
	# Arc length is monotonic and matches the road length.
	assert_float(g.lane_length[fwd_lane]).is_equal_approx(300.0, 0.05)

func test_banked_lane_follows_the_road_surface() -> void:
	var road := _straight(RoadDef.Tier.ARTERIAL, Vector3(0, 5, 0), Vector3(200, 5, 0), 21, "bank")
	var bank := PackedFloat32Array()
	for i in 21:
		bank.append(0.1)
	road.bank_angles = bank
	var g := _graph([road])
	for lane in g.road_lanes[0]:
		var p: Vector3 = g.lane_pts[lane][10]
		var lat := _lateral(p, road.points[0], road.points[20])
		# TrackBuilder cross = right*cos(a) - UP*sin(a): the surface drops on the right.
		assert_float(p.y).is_equal_approx(5.0 - sin(0.1) * lat / cos(0.1), 0.02)
		assert_float(g.lane_up[lane][10].y).is_greater(0.99)

func test_t_junction_connects_both_ways() -> void:
	# B ends on the middle of A at a right angle.
	var a := _straight(RoadDef.Tier.ARTERIAL, Vector3(-200, 0, 0), Vector3(200, 0, 0), 41, "a")
	var b := _straight(RoadDef.Tier.ARTERIAL, Vector3(0, 0, 200), Vector3(0, 0, 0), 21, "b")
	var g := _graph([a, b])
	assert_int(g.junction_count).is_equal(1)
	var into_a := 0
	var into_b := 0
	for lane in g.lane_count():
		if not g.is_connector(lane) or g.conn_junction[lane] < 0:
			continue
		var from_road := g.lane_road[g.conn_from_lane[lane]]
		var to_road := g.lane_road[g.conn_to_lane[lane]]
		assert_int(from_road).is_not_equal(to_road)
		if to_road == 0:
			into_a += 1
			assert_int(g.lane_dir[g.conn_from_lane[lane]]).is_equal(1)  # B's lane that ends here
		else:
			into_b += 1
			assert_int(g.lane_dir[g.conn_to_lane[lane]]).is_equal(-1)  # B's lane that starts here
	# B arriving turns left and right onto A; both A directions can turn into B.
	assert_int(into_a).is_equal(2)
	assert_int(into_b).is_equal(2)
	_assert_connector_endpoints(g)
	_assert_every_lane_has_a_successor(g)

func test_crossing_and_overpass() -> void:
	var a := _straight(RoadDef.Tier.ARTERIAL, Vector3(-200, 0, 0), Vector3(200, 0, 0), 41, "a")
	var b := _straight(RoadDef.Tier.ARTERIAL, Vector3(0, 0, -200), Vector3(0, 0, 200), 41, "b")
	var g := _graph([a, b])
	var conns := 0
	for lane in g.lane_count():
		if g.is_connector(lane) and g.conn_junction[lane] >= 0:
			conns += 1
	# Each of 4 arriving lanes turns left or right: 8 connectors.
	assert_int(conns).is_equal(8)
	_assert_connector_endpoints(g)
	# Same crossing with B 10 m higher (inside the 15 m link threshold): an
	# overpass, not a junction. No connectors.
	var b_high := _straight(RoadDef.Tier.ARTERIAL, Vector3(0, 10, -200), Vector3(0, 10, 200), 41, "b_high")
	var g2 := _graph([a, b_high])
	assert_int(g2.junction_count).is_equal(1)
	for lane in g2.lane_count():
		if g2.is_connector(lane):
			assert_int(g2.conn_junction[lane]).is_equal(-1)  # only dead-end U-turns

func test_dead_ends_get_uturns_and_hairpin_forks_connect() -> void:
	var a := _straight(RoadDef.Tier.ARTERIAL, Vector3(0, 0, 0), Vector3(300, 0, 0), 31, "lonely")
	var g := _graph([a])
	var uturns := 0
	for lane in g.lane_count():
		if g.is_connector(lane):
			uturns += 1
			assert_int(g.conn_junction[lane]).is_equal(-1)
			assert_int(g.lane_road[g.conn_to_lane[lane]]).is_equal(0)
			assert_int(g.lane_dir[g.conn_to_lane[lane]]).is_equal(-g.lane_dir[g.conn_from_lane[lane]])
	assert_int(uturns).is_equal(2)
	_assert_every_lane_has_a_successor(g)
	# A road that ends where another starts heading almost straight back (a fork):
	# the hairpin is the only way on, so it is connected.
	var b := _straight(RoadDef.Tier.ARTERIAL, Vector3(300, 0, 0), Vector3(10, 0, 60), 31, "fork")
	var g2 := _graph([a, b])
	var hairpin := false
	for lane in g2.lane_count():
		if g2.is_connector(lane) and g2.conn_junction[lane] >= 0 and g2.lane_road[g2.conn_from_lane[lane]] == 0:
			hairpin = true
	assert_bool(hairpin).is_true()
	_assert_every_lane_has_a_successor(g2)

func test_lane_change_adjacency() -> void:
	var hw := _straight(RoadDef.Tier.HIGHWAY, Vector3(0, 0, 0), Vector3(400, 0, 0), 41, "hw")
	var art := _straight(RoadDef.Tier.ARTERIAL, Vector3(0, 0, 500), Vector3(400, 0, 500), 41, "art")
	var g := _graph([hw, art])
	for lane in g.road_lanes[0]:
		var targets := g.lane_change_targets(lane)
		assert_int(targets.size()).is_equal(1)
		var other := targets[0]
		assert_int(g.lane_dir[other]).is_equal(g.lane_dir[lane])
		assert_int(g.lane_road[other]).is_equal(0)
		assert_int(absi(g.lane_index[other] - g.lane_index[lane])).is_equal(1)
		if g.lane_index[lane] == 0:
			assert_int(g.lane_outer[lane]).is_equal(other)
		else:
			assert_int(g.lane_inner[lane]).is_equal(other)
	for lane in g.road_lanes[1]:
		assert_int(g.lane_change_targets(lane).size()).is_equal(0)

func test_nearest_lane_respects_heading() -> void:
	# Along z = 32, the middle of a 64 m hash cell, so both lanes share the cell.
	var art := _straight(RoadDef.Tier.ARTERIAL, Vector3(0, 0, 32), Vector3(300, 0, 32), 31, "art")
	var g := _graph([art])
	var q := Vector3(150, 0, 32)
	var east := g.nearest_lane(q, 5.0, Vector3(1, 0, 0))
	var west := g.nearest_lane(q, 5.0, Vector3(-1, 0, 0))
	assert_bool(east.is_empty()).is_false()
	assert_bool(west.is_empty()).is_false()
	assert_int(g.lane_dir[int(east["lane"])]).is_equal(1)
	assert_int(g.lane_dir[int(west["lane"])]).is_equal(-1)
	assert_float(float(east["s"])).is_equal_approx(150.0, 0.1)
	assert_float(float(west["s"])).is_equal_approx(150.0, 0.1)
	assert_bool(g.nearest_lane(Vector3(150, 0, 72), 5.0).is_empty()).is_true()
	# The cell query lists both lanes where the road runs.
	assert_int(g.lanes_in_cell(LaneGraph.cell_of(q)).size()).is_equal(2)

func test_curve_speed_profile() -> void:
	var tight := _circle(RoadDef.Tier.ARTERIAL, Vector3.ZERO, 30.0, 48, "tight")
	var g := _graph([tight])
	var lane := g.road_lanes[0][0]
	var r := g.lane_pts[lane][0].length()
	var expect := sqrt(LaneGraph.A_LAT_MAX * r)
	for v in g.lane_vmax[lane]:
		assert_float(v).is_less_equal(expect * 1.1)
		assert_float(v).is_greater(expect * 0.8)
	# Braking pass: no step asks for more than B_COMFORT.
	var straight := _straight(RoadDef.Tier.HIGHWAY, Vector3(0, 0, 500), Vector3(1000, 0, 500), 101, "s")
	var g2 := _graph([straight, ])
	for l in g2.lane_count():
		var vm: PackedFloat32Array = g2.lane_vmax[l]
		var ss: PackedFloat32Array = g2.lane_s[l]
		for k in range(vm.size() - 1):
			assert_float(vm[k] * vm[k] - vm[k + 1] * vm[k + 1]).is_less_equal(2.0 * LaneGraph.B_COMFORT * (ss[k + 1] - ss[k]) + 0.01)

func test_real_network_is_connected_and_deterministic() -> void:
	var defs: Array[RoadDef] = CorridorPlanner.plan(CorridorPlanner.MASTER_SEED)
	var topo := RoadGraph.build_topology(defs, RoadNetwork.LINK_THRESHOLD)
	var g := LaneGraph.build(defs, topo["junctions"])
	var g2 := LaneGraph.build(defs, topo["junctions"])
	assert_int(g.checksum()).is_equal(g2.checksum())
	# Plan target is 0.5 s on the main thread; it runs on a worker in game. The
	# loose bound keeps parallel CI shards from flaking.
	assert_int(g.build_usec).is_less(2000000)
	_assert_every_lane_has_a_successor(g)
	_assert_connector_endpoints(g)
	for road_id in defs.size():
		var def := defs[road_id]
		if def.points.size() < 2:
			continue
		assert_int(g.road_lanes[road_id].size()).is_equal(2 * LaneGraph.lanes_per_direction(def.tier))
	# Every junction that is not an overpass gets at least one connector, whatever
	# junctions the network reports.
	var with_conn := {}
	for lane in g.lane_count():
		if g.is_connector(lane) and g.conn_junction[lane] >= 0:
			with_conn[g.conn_junction[lane]] = true
	for j in topo["junctions"].size():
		var jj: Dictionary = topo["junctions"][j]
		var pa := LaneGraph._road_param(defs[jj["road_a"]].points, LaneGraph._cumulative(defs[jj["road_a"]].points), jj["segment_a"], jj["point"])
		var pb := LaneGraph._road_param(defs[jj["road_b"]].points, LaneGraph._cumulative(defs[jj["road_b"]].points), jj["segment_b"], jj["point"])
		if absf((pa[1] as Vector3).y - (pb[1] as Vector3).y) > LaneGraph.MAX_JUNCTION_DY:
			continue
		assert_bool(with_conn.has(j)).override_failure_message("junction %d (%s x %s) has no connector" % [j, defs[jj["road_a"]].id, defs[jj["road_b"]].id]).is_true()
	# Lane points stay inside the carriageway (lateral distance to the centreline).
	for lane in g.lane_count():
		if g.is_connector(lane):
			continue
		var def := defs[g.lane_road[lane]]
		var cum := LaneGraph._cumulative(def.points)
		var pts: PackedVector3Array = g.lane_pts[lane]
		for k in range(0, pts.size(), 7):
			var c: Vector3 = _centre_at(def, cum, g.lane_c[lane][k])
			var d := Vector2(pts[k].x - c.x, pts[k].z - c.z).length()
			assert_float(d).override_failure_message("%s lane %d point %d: %.2f m off centre" % [def.id, lane, k, d]).is_less(def.width * 0.5)

## Centreline point at road parameter c (wraps a closed road's last segment).
static func _centre_at(def: RoadDef, cum: PackedFloat32Array, c: float) -> Vector3:
	var n := def.points.size()
	for i in range(n - 1):
		if c <= cum[i + 1]:
			var span := cum[i + 1] - cum[i]
			return def.points[i].lerp(def.points[i + 1], 0.0 if span <= 0.0 else (c - cum[i]) / span)
	var wrap := def.points[n - 1].distance_to(def.points[0])
	return def.points[n - 1].lerp(def.points[0], 0.0 if wrap <= 0.0 else clampf((c - cum[n - 1]) / wrap, 0.0, 1.0))

func _assert_every_lane_has_a_successor(g: LaneGraph) -> void:
	for lane in g.lane_count():
		assert_bool(g.has_end_successor(lane)).override_failure_message("lane %d has no successor" % lane).is_true()
		assert_int(g.successors(lane).size()).is_greater(0)

func _assert_connector_endpoints(g: LaneGraph) -> void:
	for lane in g.lane_count():
		if not g.is_connector(lane):
			continue
		var pts: PackedVector3Array = g.lane_pts[lane]
		var start := g.position_at(g.conn_from_lane[lane], g.conn_from_s[lane])
		var end := g.position_at(g.conn_to_lane[lane], g.conn_to_s[lane])
		assert_float(pts[0].distance_to(start)).is_less(0.5)
		assert_float(pts[pts.size() - 1].distance_to(end)).is_less(0.5)
		# The exit is registered on the source lane.
		assert_bool(g.lane_exit_to[g.conn_from_lane[lane]].has(lane)).is_true()
