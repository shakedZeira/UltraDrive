# tests/suites/test_traffic_lanes.gd
extends GdUnitTestSuite

## Lane-following pooled traffic (TrafficSim + TrafficManager, traffic plan
## sections 4-6, 9, 12): spawn ring and view-cone rule, spawn gaps, despawn,
## pool bounds (no node churn), following distance, braking for a parked player,
## free-road speed, junction traversal, determinism, and "never on race tracks".

const VIEW_HALF := deg_to_rad(51.0)

static func _circle(tier: int, center: Vector3, radius: float, n: int, id: String) -> RoadDef:
	var pts: Array[Vector3] = []
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(center + Vector3(cos(a) * radius, 0.0, sin(a) * radius))
	return RoadDef.make(tier, pts, id, true)

static func _straight(tier: int, from: Vector3, to: Vector3, n: int, id: String) -> RoadDef:
	var pts: Array[Vector3] = []
	for i in n:
		pts.append(from.lerp(to, float(i) / float(n - 1)))
	return RoadDef.make(tier, pts, id, false)

static func _graph(defs: Array) -> LaneGraph:
	var topo := RoadGraph.build_topology(defs, RoadNetwork.LINK_THRESHOLD)
	return LaneGraph.build(defs, topo["junctions"])

static func _rings() -> LaneGraph:
	return _graph([
		_circle(RoadDef.Tier.ARTERIAL, Vector3.ZERO, 200.0, 120, "r200"),
		_circle(RoadDef.Tier.HIGHWAY, Vector3.ZERO, 250.0, 150, "r250"),
	])

static func _view(origin: Vector3, forward: Vector3) -> Dictionary:
	return {"origin": origin, "forward": forward.normalized(), "half_angle": VIEW_HALF}

static func _bumper_gaps_ok(sim: TrafficSim) -> float:
	var worst := INF
	for i in sim.slot_count:
		if sim.active[i] == 0:
			continue
		for j in sim.slot_count:
			if j == i or sim.active[j] == 0 or sim.car_lane[j] != sim.car_lane[i]:
				continue
			var ds := sim._ahead_dist(sim.car_lane[i], sim.car_s[i], sim.car_s[j])
			if ds < 0.0:
				continue
			worst = minf(worst, ds - sim.car_half_len[i] - sim.car_half_len[j])
	return worst

func test_spawns_in_ring_never_in_close_view_cone() -> void:
	var sim := TrafficSim.new(_rings(), 24, 20)
	var view := _view(Vector3(0, 1.5, 0), Vector3(1, 0, 0))
	var count := 0
	for _t in 60 * 20:
		sim.step(1.0 / 60.0, Vector3.ZERO, Vector3.ZERO, view)
		for slot in sim.spawned:
			count += 1
			var p := sim.car_pos[slot]
			var d := Vector2(p.x, p.z).length()
			assert_float(d).is_between(TrafficSim.SPAWN_MIN, TrafficSim.SPAWN_MAX)
			if sim.in_view(p, view):
				assert_float(d).is_greater_equal(TrafficSim.CONE_CLEAR_DIST)
	assert_int(count).is_greater(5)
	assert_int(sim.stats["rej_cone"]).is_greater(0)
	assert_int(sim.live_count()).is_less_equal(20)

func test_spawn_gaps_and_no_overlap() -> void:
	var sim := TrafficSim.new(_rings(), 40, 36)
	sim.density_scale = 10.0  # push the ring to the cap
	for _t in 60 * 30:
		sim.step(1.0 / 60.0, Vector3.ZERO, Vector3.ZERO, {})
		for slot in sim.spawned:
			var lane := sim.car_lane[slot]
			var need := TrafficSim.GAP_MIN + TrafficSim.GAP_TIME * sim.graph.lane_limit[lane]
			for j in sim.slot_count:
				if j == slot or sim.active[j] == 0:
					continue
				assert_float(sim.car_pos[j].distance_to(sim.car_pos[slot])).is_greater_equal(TrafficSim.SPAWN_CLEARANCE)
				if sim.car_lane[j] == lane:
					var fwd := sim._ahead_dist(lane, sim.car_s[slot], sim.car_s[j])
					var back := sim._ahead_dist(lane, sim.car_s[j], sim.car_s[slot])
					assert_float(minf(fwd, back)).is_greater_equal(need - 1.0)
		assert_float(_bumper_gaps_ok(sim)).is_greater_equal(TrafficSim.MIN_BUMPER_GAP - 0.05)
	assert_int(sim.live_count()).is_greater(10)
	assert_int(sim.live_count()).is_less_equal(36)

func test_despawn_when_player_drives_away() -> void:
	var sim := TrafficSim.new(_rings(), 24, 20)
	for _t in 60 * 10:
		sim.step(1.0 / 60.0, Vector3.ZERO, Vector3.ZERO, {})
	assert_int(sim.live_count()).is_greater(0)
	var first_uids := {}
	for i in sim.slot_count:
		if sim.active[i] == 1:
			first_uids[sim.car_uid[i]] = true
	# Drive away along +X at 40 m/s for 30 s (1.2 km, no teleport).
	var pos := Vector3.ZERO
	var vel := Vector3(40, 0, 0)
	for _t in 60 * 30:
		pos += vel / 60.0
		sim.step(1.0 / 60.0, pos, vel, _view(pos, vel))
		for i in sim.slot_count:
			if sim.active[i] == 1:
				var d := Vector2(sim.car_pos[i].x - pos.x, sim.car_pos[i].z - pos.z).length()
				assert_float(d).is_less_equal(TrafficSim.DESPAWN_FORCE + 2.0)
	for i in sim.slot_count:
		if sim.active[i] == 1:
			assert_bool(first_uids.has(sim.car_uid[i])).is_false()
	assert_int(sim.live_count()).is_equal(0)

func test_teleport_clears_and_ramps_up() -> void:
	var sim := TrafficSim.new(_rings(), 24, 20)
	for _t in 60 * 10:
		sim.step(1.0 / 60.0, Vector3.ZERO, Vector3.ZERO, {})
	assert_int(sim.live_count()).is_greater(0)
	sim.step(1.0 / 60.0, Vector3(5000, 0, 0), Vector3.ZERO, {})
	assert_int(sim.live_count()).is_equal(0)
	assert_int(sim.stats["teleports"]).is_equal(1)

func test_following_distance_on_a_loop() -> void:
	var g := _graph([_circle(RoadDef.Tier.ARTERIAL, Vector3.ZERO, 160.0, 96, "loop")])
	var sim := TrafficSim.new(g, 14, 12)
	var lane := g.road_lanes[0][0]
	var length := g.lane_length[lane]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for k in 12:
		var slot := sim.place_car(lane, length * float(k) / 12.0 + rng.randf_range(0.0, 20.0), rng.randf_range(0.0, 25.0))
		assert_int(slot).is_not_equal(-1)
	# Mixed speeds: make one car a crawler so the rest must queue behind it.
	sim.car_v0f[0] = 0.25
	var worst := INF
	for _t in 60 * 180:
		sim.step(1.0 / 60.0, Vector3(0, 0, 0), Vector3.ZERO, {})
		worst = minf(worst, _bumper_gaps_ok(sim))
	assert_int(sim.live_count()).is_equal(12)
	assert_float(worst).is_greater_equal(TrafficSim.MIN_BUMPER_GAP - 0.05)
	# The queue behind the crawler settles at a real following gap, not bumper to bumper.
	var queued_gap := INF
	for i in sim.slot_count:
		if sim.active[i] == 1 and i != 0:
			for j in sim.slot_count:
				if sim.active[j] == 1 and j != i:
					var ds := sim._ahead_dist(lane, sim.car_s[i], sim.car_s[j])
					if ds > 0.0:
						queued_gap = minf(queued_gap, ds - sim.car_half_len[i] - sim.car_half_len[j])
	assert_float(queued_gap).is_greater(TrafficSim.S0 * 0.8)

func test_car_stops_behind_a_parked_player() -> void:
	var g := _graph([_circle(RoadDef.Tier.ARTERIAL, Vector3.ZERO, 160.0, 96, "loop")])
	var sim := TrafficSim.new(g, 2, 1)
	var lane := g.road_lanes[0][0]
	var player_s := 300.0
	var player := g.position_at(lane, player_s)
	var slot := sim.place_car(lane, player_s - 120.0, 18.0)
	for _t in 60 * 30:
		sim.step(1.0 / 60.0, player, Vector3.ZERO, {})
	assert_bool(sim.is_active(slot)).is_true()
	assert_float(sim.car_v[slot]).is_less(0.2)
	var gap := player_s - sim.car_s[slot] - sim.car_half_len[slot] - TrafficSim.PLAYER_HALF_LEN
	assert_float(gap).is_between(TrafficSim.S0 - 0.5, 8.0)

func test_free_road_speed_converges_to_desired_speed() -> void:
	var g := _graph([_circle(RoadDef.Tier.ARTERIAL, Vector3.ZERO, 600.0, 240, "big")])
	var sim := TrafficSim.new(g, 2, 1)
	var lane := g.road_lanes[0][0]
	var slot := sim.place_car(lane, 0.0, 5.0)
	for _t in 60 * 60:
		# Keep the player 30 m above the car: never a leader, never despawns it.
		sim.step(1.0 / 60.0, sim.car_pos[slot] + Vector3(0, 30, 0), Vector3.ZERO, {})
	var want := minf(g.lane_limit[lane] * sim.car_v0f[slot], g.vmax_at(lane, sim.car_s[slot]))
	assert_float(sim.car_v[slot]).is_equal_approx(want, 0.6)
	assert_float(sim.car_v[slot]).is_less_equal(g.lane_limit[lane] * 1.2)

func test_junction_traffic_takes_connectors_and_stays_ordered() -> void:
	var a := _straight(RoadDef.Tier.ARTERIAL, Vector3(-250, 0, 0), Vector3(250, 0, 0), 51, "a")
	var b := _straight(RoadDef.Tier.ARTERIAL, Vector3(0, 0, -250), Vector3(0, 0, 250), 51, "b")
	var g := _graph([a, b])
	var sim := TrafficSim.new(g, 16, 12)
	sim.density_scale = 10.0
	var on_connector := {}
	for _t in 60 * 120:
		# Player parked off both roads next to the crossing.
		sim.step(1.0 / 60.0, Vector3(30, 0, 30), Vector3.ZERO, {})
		for i in sim.slot_count:
			if sim.active[i] == 1 and g.is_connector(sim.car_lane[i]):
				on_connector[sim.car_uid[i]] = sim.car_lane[i]
				var expect := g.position_at(sim.car_lane[i], sim.car_s[i])
				assert_float(sim.car_pos[i].distance_to(expect)).is_less(0.01)
		assert_float(_bumper_gaps_ok(sim)).is_greater_equal(TrafficSim.MIN_BUMPER_GAP - 0.05)
	var junction_turns := 0
	for uid in on_connector:
		if g.conn_junction[on_connector[uid]] >= 0:
			junction_turns += 1
	assert_int(junction_turns).is_greater(0)

func test_same_seed_same_spawns() -> void:
	var logs: Array = []
	for _run in 2:
		var sim := TrafficSim.new(_rings(), 24, 20)
		sim.keep_spawn_log = true
		var pos := Vector3.ZERO
		for t in 60 * 20:
			pos = Vector3(sin(t * 0.01) * 30.0, 0, 0)
			sim.step(1.0 / 60.0, pos, Vector3.ZERO, _view(pos, Vector3(0, 0, 1)))
		logs.append(sim.spawn_log)
	assert_int((logs[0] as Array).size()).is_greater(5)
	assert_bool(logs[0] == logs[1]).is_true()

func _network(defs: Array) -> RoadNetwork:
	var net := RoadNetwork.new()
	net.stream_geometry = true  # register defs only, no meshes
	add_child(net)
	for d in defs:
		net.add_road_def(d)
	return net

func test_manager_pool_is_fixed_and_bounded() -> void:
	var net := _network([
		_circle(RoadDef.Tier.ARTERIAL, Vector3.ZERO, 200.0, 120, "r200"),
		_circle(RoadDef.Tier.HIGHWAY, Vector3(3000, 0, 0), 250.0, 150, "far"),
	])
	var mgr := TrafficManager.new()
	mgr.quality = 0
	mgr.density_scale = 10.0
	mgr.road_network = net
	add_child(mgr)
	mgr.build_now()
	mgr.sim.spawn_filter = Callable()  # nothing is streamed in this bare network
	assert_bool(mgr.is_ready()).is_true()
	var pool := mgr.get_child_count()
	assert_int(pool).is_equal(mgr.cap + TrafficManager.POOL_EXTRA)
	for t in 60 * 40:
		# Alternate between the two loops every 8 s: teleport clears, ramp refills.
		var at := Vector3.ZERO if (t / 480) % 2 == 0 else Vector3(3000, 0, 0)
		mgr.view_override = _view(at, Vector3(1, 0, 0))
		mgr.update(at, 1.0 / 60.0)
		assert_int(mgr.live_count()).is_less_equal(mgr.cap)
		var near := 0
		var shown := 0
		for i in pool:
			var body := mgr.car_node(i)
			if body.collision_layer != 0:
				near += 1
				assert_int(body.collision_layer).is_equal(TrafficManager.TRAFFIC_LAYER)
				assert_int(body.collision_mask).is_equal(TrafficManager.TRAFFIC_MASK)
			if body.visible:
				shown += 1
		assert_int(near).is_less_equal(mgr.near_cap)
		assert_int(shown).is_equal(mgr.live_count())
	assert_int(mgr.get_child_count()).is_equal(pool)
	assert_int(int(mgr.sim.stats["spawns"])).is_greater(20)
	assert_int(int(mgr.sim.stats["teleports"])).is_greater(2)
	# Near and mid cars sit exactly on their lane (far cars refresh every few ticks).
	for i in mgr.sim.slot_count:
		if mgr.sim.active[i] == 1 and mgr.tier_of(i) != TrafficManager.TIER_FAR:
			var on := mgr.graph.position_at(mgr.sim.car_lane[i], mgr.sim.car_s[i])
			assert_float(mgr.car_node(i).global_position.distance_to(on)).is_less(0.01)
	mgr.set_enabled(false)
	assert_int(mgr.live_count()).is_equal(0)
	mgr.queue_free()
	net.queue_free()

func test_never_runs_on_race_tracks() -> void:
	# A spawner outside the open world (no WorldDriver) keeps the legacy path.
	var spawner := TrafficSpawner.new()
	add_child(spawner)
	assert_bool(spawner.uses_lane_traffic()).is_false()
	assert_object(spawner.lane_manager()).is_null()
	spawner.queue_free()
	# No race track scene carries traffic or the open-world driver.
	var dir := DirAccess.open("res://scenes/track")
	assert_object(dir).is_not_null()
	for f in dir.get_files():
		if not f.ends_with(".tscn"):
			continue
		var text := FileAccess.get_file_as_string("res://scenes/track/" + f)
		assert_bool(text.contains("traffic_spawner.gd")).override_failure_message(f).is_false()
		assert_bool(text.contains("traffic_manager.gd")).override_failure_message(f).is_false()
		assert_bool(text.contains("world_driver.gd")).override_failure_message(f).is_false()
	# The open world does.
	var ow := FileAccess.get_file_as_string("res://scenes/world/open_world_root.tscn")
	assert_bool(ow.contains("traffic_spawner.gd")).is_true()
	assert_bool(ow.contains("world_driver.gd")).is_true()

func test_quality_caps_follow_the_plan() -> void:
	assert_int(int(TrafficManager.CAP_BY_QUALITY[0])).is_equal(14)
	assert_int(int(TrafficManager.CAP_BY_QUALITY[1])).is_equal(24)
	assert_int(int(TrafficManager.CAP_BY_QUALITY[2])).is_equal(36)
	assert_int(int(TrafficManager.NEAR_BY_QUALITY[1])).is_equal(8)
