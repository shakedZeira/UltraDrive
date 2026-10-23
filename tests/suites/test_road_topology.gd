# tests/suites/test_road_topology.gd
extends GdUnitTestSuite

## RoadGraph.build_topology used to compare every segment of every road with
## every segment of every other road: 21.2 s on the main thread for the
## open-world network (4,256 points), inside the loading screen, before the
## first frame. It now visits only segment pairs whose boxes can be closer than
## the link threshold (a per-road XZ grid, built once). The junctions must be
## IDENTICAL to the all-pairs scan: same pairs, same segments, same points,
## same first-minimum tie-break.

## The all-pairs scan RoadGraph.build_topology used to run (21 s on the
## open-world network): every segment pair of every road pair.
static func _brute_junctions(defs: Array, threshold: float) -> Array:
	var out: Array = []
	for i in defs.size():
		for j in range(i + 1, defs.size()):
			var c := RoadGraph._closest_segments((defs[i] as RoadDef).points, (defs[j] as RoadDef).points)
			if float(c["dist"]) < threshold:
				out.append({"road_a": i, "road_b": j, "segment_a": c["seg_a"], "segment_b": c["seg_b"],
					"point": (c["on_a"] + c["on_b"]) * 0.5, "dist": c["dist"]})
	return out

func _assert_same_topology(defs: Array, label: String) -> void:
	var expected := _brute_junctions(defs, RoadNetwork.LINK_THRESHOLD)
	var got: Array = RoadGraph.build_topology(defs, RoadNetwork.LINK_THRESHOLD)["junctions"]
	assert_int(got.size()).override_failure_message("%s: %d junctions vs %d" % [label, got.size(), expected.size()]).is_equal(expected.size())
	for k in mini(got.size(), expected.size()):
		var g: Dictionary = got[k]
		var e: Dictionary = expected[k]
		for field in ["road_a", "road_b", "segment_a", "segment_b", "point", "dist"]:
			assert_bool(g[field] == e[field]).override_failure_message("%s junction %d %s: %s vs %s" % [label, k, field, g[field], e[field]]).is_true()

func test_topology_matches_the_all_pairs_scan_on_random_networks() -> void:
	var rng := RandomNumberGenerator.new()
	for trial in 6:
		rng.seed = 9100 + trial
		var defs: Array = []
		for r in 7:
			var pts: Array[Vector3] = []
			var p := Vector3(rng.randf_range(-400, 400), rng.randf_range(0, 30), rng.randf_range(-400, 400))
			var heading := rng.randf() * TAU
			var count := rng.randi_range(2, 70)
			for i in count:
				pts.append(p)
				heading += rng.randf_range(-0.4, 0.4)
				# Mix of 1 m and 150 m steps (the sparse highway ring has ~150 m).
				var step := rng.randf_range(1.0, 150.0) if rng.randf() < 0.3 else rng.randf_range(5.0, 20.0)
				p += Vector3(cos(heading) * step, rng.randf_range(-2.0, 2.0), sin(heading) * step)
			defs.append(RoadDef.make(RoadDef.Tier.ARTERIAL, pts, "r%d" % r, false))
		# A guaranteed touch and a guaranteed near miss (14.99 m) per trial.
		var a: RoadDef = defs[0]
		var touch: Array[Vector3] = [a.points[0] + Vector3(0, 0, 0), a.points[0] + Vector3(40, 0, 40)]
		defs.append(RoadDef.make(RoadDef.Tier.ARTERIAL, touch, "touch", false))
		var near: Array[Vector3] = [a.points[0] + Vector3(0, 14.99, 0), a.points[0] + Vector3(0, 14.99, 0.5)]
		defs.append(RoadDef.make(RoadDef.Tier.ARTERIAL, near, "near", false))
		# A one-point road.
		var single: Array[Vector3] = [a.points[a.points.size() - 1] + Vector3(3, 0, 0)]
		defs.append(RoadDef.make(RoadDef.Tier.ARTERIAL, single, "single", false))
		_assert_same_topology(defs, "trial %d" % trial)

func test_topology_matches_the_all_pairs_scan_on_the_corridor_network() -> void:
	var all: Array[RoadDef] = CorridorPlanner.plan(CorridorPlanner.MASTER_SEED)
	# The all-pairs reference is what took 21 s; keep the pairs it scans small
	# by leaving out the four longest chains (they are covered by the random
	# trials' long sparse chains and by test_road_graph's live-network rows).
	var sorted := all.duplicate()
	sorted.sort_custom(func(x: RoadDef, y: RoadDef) -> bool: return x.points.size() > y.points.size())
	var defs: Array = []
	for d: RoadDef in all:
		if sorted.find(d) >= 4:
			defs.append(d)
	assert_int(defs.size()).is_greater(10)
	_assert_same_topology(defs, "corridors")
