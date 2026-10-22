# tests/suites/test_le_mans_track.gd
extends GdUnitTestSuite

## P1/P2 gate for "Le Mans No-Chicane" (docs/plans/track_le_mans_no_chicane.md
## §6 suite 2). Mirrors `test_barcelona_rx_track.gd`'s structure and
## RaceManager hygiene, but for `res://scenes/track/le_mans.tscn` driven by
## `scripts/track/le_mans.gd` and `LeMansLayout`.
##
## Covers the plan's scene-level acceptance:
##   * A6: one closed ARTERIAL/asphalt RoadDef, width 12, `RailSide.NONE`, no
##     lane dividers, 4,800 points + the attached bank profile, and the
##     RoadNetwork child that gives the minimap / pause map / SurfaceRegistry
##     their road source;
##   * the 24 checkpoints in travel order [200,...,4600,0], the line LAST, the
##     grid at rp4684 ON the straight but OFF every checkpoint;
##   * **A5 (hard gate)**: a stub car walked through the gates by INDEX ticks
##     lap 1 at 13,955 m (329 m standing-start run-up) and laps 2+ at exactly
##     13,626 m -- distances are summed from the layout's own arc coordinates,
##     never from a wall clock (plan §7 risk 2);
##   * A7 (re-cut for real elevation, 2026-10-22): the SRTM height-field
##     ground (`LeMansTerrain`) sits 0.40 m under the road edge along the whole
##     lap and the full-edge skirt reaches into it on both sides, no Terrain3D;
##   * the `TrackLayoutSource` off-tree probe returning `build_centerline()`.
##
## The registry reverse-lookup (`_resolve_track_id() == "le_mans"`) lands with
## P4's registry edit (plan §9 step 8), added to this suite at that step.
##
## The suite never asserts wall-clock (the `test_perf_gate` lesson) and cleans
## RaceManager state between tests exactly like `test_barcelona_rx_track.gd`.

const SCENE_LE_MANS := "res://scenes/track/le_mans.tscn"

## The visible lip the ground drops over at a road edge (m) -- the same
## constant the scene builds the skirt with, restated here so loosening the
## scene cannot loosen the gate (plan §3.7: ROAD_BASE_Y 0.15 -> PLAIN_Y -0.25,
## now relative to the real elevation at that station).
const EDGE_DROP := 0.40
## How far the 16 m terrain triangles may stray from the exact road-ground
## profile under the carriageway (curves/crests between grid vertices).
const TERRAIN_TOL := 0.2
## le_mans.gd SKIRT_BURY, restated (a const is not readable through get()).
const SKIRT_BURY := 0.3

## A5 tolerances, straight from the acceptance table.
const LAP_1_TARGET := 13955.0
const LAP_1_TOL := 6.0
const LAP_N_TARGET := 13626.0
const LAP_N_TOL := 3.0

var _managed_cars: Array = []
var _managed_counters: Array = []

func before_test() -> void:
	_managed_cars.clear()
	_managed_counters.clear()
	RaceManager._checkpoints_dirty = true
	RaceManager.rival_roster = []
	RaceManager.consume_pending_race()

func after_test() -> void:
	for car in _managed_cars:
		if is_instance_valid(car):
			car.free()
	_managed_cars.clear()
	for counter in _managed_counters:
		if is_instance_valid(counter):
			counter.free()
	_managed_counters.clear()
	for child in RaceManager.get_children():
		if child is LapCounter:
			child.free()
	RaceManager.is_race_active = false
	RaceManager._participants = []
	RaceManager._lap_counters = {}
	RaceManager._checkpoints_dirty = true
	RaceManager.rival_centerline = []
	for child in get_children():
		if child is Checkpoint:
			child.free()

func _new_stub_car() -> VehiclePhysics:
	var car := VehiclePhysics.new()
	_managed_cars.append(car)
	return car

## A suite-owned counter fed the scene's real checkpoints, isolating the pure
## checkpoint/lap progression contract from `start_race`'s countdown ceremony.
func _new_lap_counter(laps: int) -> LapCounter:
	var counter := LapCounter.new()
	_managed_counters.append(counter)
	add_child(counter)
	counter.start_race(laps)
	return counter

## Scene checkpoints ordered by `.index` (the group order is unspecified).
func _ordered_checkpoints() -> Array[Checkpoint]:
	var source := RaceManager.get_checkpoints()
	var ordered: Array[Checkpoint] = []
	for i in LeMansLayout.CHECKPOINT_COUNT:
		for cp in source:
			if cp.index == i:
				ordered.append(cp)
				break
	return ordered

# --- scene skeleton --------------------------------------------------------

func test_scene_road_checkpoints_network_and_spawn() -> void:
	var runner := scene_runner(SCENE_LE_MANS)
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return

	# A 4,800-point uniform-arc centerline and its matching bank profile.
	var points: Array = scene.get("road_points")
	assert_int(points.size()).is_equal(LeMansLayout.TOTAL_POINTS)
	var bank: PackedFloat32Array = scene.get("bank_profile")
	assert_int(bank.size()).is_equal(LeMansLayout.TOTAL_POINTS)

	# The scene handed the centerline to RaceManager (the rival-roster hook).
	assert_int(RaceManager.rival_centerline.size()).is_equal(LeMansLayout.TOTAL_POINTS)

	# Exactly 24 checkpoints, indices 0..23, in travel order
	# [200,400,...,4600, 0]; checkpoint 23 (rp0) is the start/finish line.
	var checkpoints: Array = scene.get_tree().get_nodes_in_group("checkpoints")
	assert_int(checkpoints.size()).is_equal(LeMansLayout.CHECKPOINT_COUNT)
	var by_index := {}
	for node in checkpoints:
		var cp := node as Checkpoint
		if cp != null:
			by_index[cp.index] = cp
	assert_int(by_index.size()).is_equal(LeMansLayout.CHECKPOINT_COUNT)
	var indices := LeMansLayout.checkpoint_indices()
	assert_int(indices.size()).is_equal(LeMansLayout.CHECKPOINT_COUNT)
	for i in LeMansLayout.CHECKPOINT_COUNT:
		assert_bool(by_index.has(i)).is_true()
		var cp := by_index.get(i) as Checkpoint
		if cp == null:
			continue
		var expected: Vector3 = points[indices[i]] + Vector3(0, 0.5, 0)
		assert_that(cp.global_position).is_equal_approx(expected, Vector3(0.01, 0.01, 0.01))
		assert_bool(cp.is_start_line).is_equal(i == LeMansLayout.CHECKPOINT_COUNT - 1)
	# The line is last in travel order at rp0; every other gate is a multiple of
	# the 200-point stride away from it (plan §3.6).
	assert_int(int(indices[LeMansLayout.CHECKPOINT_COUNT - 1])).is_equal(0)
	assert_int(int(indices[0])).is_equal(LeMansLayout.CP_STRIDE)

	# The grid sits on the straight at rp4684, ONE metre up, facing down the
	# road. The car is a live VehiclePhysics, so after a few frames its Y has
	# settled from the spawn offset -- assert the XZ slot and "above the road",
	# never the settled ride height (a physics-timing assert).
	var spawn := scene.get_node_or_null("PlayerCar") as Node3D
	assert_that(spawn).is_not_null()
	if spawn != null:
		var grid: Vector3 = points[LeMansLayout.GRID_INDEX]
		var spawn_xz := Vector2(spawn.global_position.x, spawn.global_position.z)
		var grid_xz := Vector2(grid.x, grid.z)
		assert_float(spawn_xz.distance_to(grid_xz)).is_less(1.0)
		assert_float(spawn.global_position.y).is_greater(grid.y)
		assert_float(spawn.global_position.y - grid.y).is_between(0.2, 2.0)
		var forward := -spawn.global_transform.basis.z
		var travel: Vector3 = LeMansLayout.frame_at_arc(LeMansLayout.grid_arc())["forward"]
		assert_float(forward.dot(travel)).is_greater(0.9)

		# The grid must NOT sit on a checkpoint: frame-based counting would
		# consume a gate the car never drove through (plan §3.6, §8.7).
		var min_gate_distance := INF
		for node2 in checkpoints:
			var gate := node2 as Checkpoint
			if gate == null:
				continue
			min_gate_distance = minf(min_gate_distance,
				gate.global_position.distance_to(spawn.global_position))
		print("[a5] grid to nearest checkpoint box = %.1f m" % min_gate_distance)
		assert_float(min_gate_distance).is_greater(16.0)

	# The RoadNetwork child is the road source for the minimap, pause map and
	# asphalt grip; the def is a closed ARTERIAL/asphalt circuit with the
	# layout's bank profile attached and no rails or lane paint (A6).
	var network := scene.get_node_or_null("RoadNetwork") as RoadNetwork
	assert_that(network).is_not_null()
	if network != null:
		var defs := network.get_road_defs()
		assert_int(defs.size()).is_equal(1)
		if defs.size() == 1:
			var def := defs[0] as RoadDef
			assert_that(def).is_not_null()
			if def != null:
				assert_bool(def.closed).is_true()
				assert_int(def.tier).is_equal(RoadDef.Tier.ARTERIAL)
				assert_int(def.surface).is_equal(RoadDef.Surface.ASPHALT)
				assert_float(def.width).is_equal_approx(LeMansLayout.WIDTH_M, 0.001)
				assert_int(def.points.size()).is_equal(LeMansLayout.TOTAL_POINTS)
				assert_bool(def.show_lane_dividers).is_false()
				assert_int(def.bank_angles.size()).is_equal(LeMansLayout.TOTAL_POINTS)
				assert_int(def.rail_sides_mask()).is_equal(RoadDef.RailSide.NONE)
				assert_int(def.rail_side_count()).is_equal(0)
		assert_float(network.nearest_road_distance(points[0])).is_less(8.0)
		assert_bool(network.is_on_road(points[0])).is_true()
		assert_that(MapRoads.resolve_road_source(scene)).is_same(network)

# --- A5: stub-car lap distances (hard gate) ---------------------------------

func test_stub_car_lap_distances_match_the_plan() -> void:
	var runner := scene_runner(SCENE_LE_MANS)
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return

	var cps := _ordered_checkpoints()
	assert_int(cps.size()).is_equal(LeMansLayout.CHECKPOINT_COUNT)
	if cps.size() != LeMansLayout.CHECKPOINT_COUNT:
		return
	var car := _new_stub_car()
	var counter := _new_lap_counter(3)

	# Distance bookkeeping: every gate's arc coordinate is the layout's own
	# uniform-arc address (index * spacing), and each advance adds the wrapped
	# gap from the car's last gate. Grid -> line is a +329 m run-up; a lap only
	# completes when the travel-order line gate (index 23, rp0) is reached with
	# enough of the circuit already taken.
	var st := {
		"arc": LeMansLayout.grid_arc(),
		"travelled": 0.0,
		"lap": counter.get_current_lap(),
		"dists": [],
	}

	# Lap 1 (from the grid): the line is the FIRST gate met but out of order,
	# so it must NOT tick; then gates 0..22 in order; the second line crossing
	# completes lap 1.
	_advance(st, counter, car, cps, LeMansLayout.CHECKPOINT_COUNT - 1)
	assert_int((st["dists"] as Array).size()).is_equal(0)
	assert_int(counter.get_current_lap()).is_equal(1)
	for i in LeMansLayout.CHECKPOINT_COUNT - 1:
		_advance(st, counter, car, cps, i)
		assert_int((st["dists"] as Array).size()).is_equal(0)
		assert_int(counter.get_current_lap()).is_equal(1)
	_advance(st, counter, car, cps, LeMansLayout.CHECKPOINT_COUNT - 1)
	assert_int(counter.get_current_lap()).is_equal(2)

	# Laps 2 and 3: gate 0 -> ... -> line, full circuit each time.
	for lap in 2:
		for i in LeMansLayout.CHECKPOINT_COUNT - 1:
			_advance(st, counter, car, cps, i)
		_advance(st, counter, car, cps, LeMansLayout.CHECKPOINT_COUNT - 1)
	assert_int(counter.get_current_lap()).is_equal(4)

	var dists := st["dists"] as Array
	assert_int(dists.size()).is_equal(3)
	if dists.size() < 3:
		return
	var lap1 := float(dists[0])
	print("[a5] lap1=%.3f lap2=%.3f lap3=%.3f (grid run-up %.3f)"
		% [lap1, float(dists[1]), float(dists[2]),
			LeMansLayout.perimeter() - LeMansLayout.grid_arc()])
	assert_float(lap1).is_equal_approx(LAP_1_TARGET, LAP_1_TOL)
	for k in range(1, dists.size()):
		assert_float(float(dists[k])).is_equal_approx(LAP_N_TARGET, LAP_N_TOL)
	# The plan's own arithmetic, not a re-derivation: the grid sits one full
	# circuit minus the 329 m run-up behind the line, so lap 1 = run-up + lap.
	assert_float(2.0 * LeMansLayout.perimeter() - LeMansLayout.grid_arc()) \
		.is_equal_approx(LAP_1_TARGET, LAP_1_TOL)

## One `counter.update()` per gate, accumulating the wrapped arc gap and
## recording the accumulated distance whenever a lap ticks.
func _advance(st: Dictionary, counter: LapCounter, car: VehiclePhysics,
		cps: Array[Checkpoint], gate: int) -> void:
	var perim := LeMansLayout.perimeter()
	var indices := LeMansLayout.checkpoint_indices()
	var gate_arc := float(indices[gate]) * LeMansLayout.spacing()
	var gap := fposmod(gate_arc - float(st["arc"]), perim)
	if gap <= 0.0001:
		gap = perim
	st["arc"] = gate_arc
	st["travelled"] = float(st["travelled"]) + gap
	counter.update(car, cps[gate])
	if counter.get_current_lap() != int(st["lap"]):
		(st["dists"] as Array).append(float(st["travelled"]))
		st["travelled"] = 0.0
		st["lap"] = counter.get_current_lap()

# --- P4: registry <-> scene resolution --------------------------------------

func test_registry_and_race_ui_resolve_this_scene_to_le_mans() -> void:
	# The registry reverse-lookup a RaceUI under this scene performs (plan §9
	# step 8): the registry maps this scene's path to the new "le_mans" id, and
	# a live HUD child resolves exactly that id (never the "" unknown bucket).
	assert_that(TrackRegistry.get_scene_path("le_mans")).is_equal(SCENE_LE_MANS)
	assert_that(TrackRegistry.get_track("le_mans").get("display_name")) \
		.is_equal("Le Mans No-Chicane")
	var runner := scene_runner(SCENE_LE_MANS)
	await runner.simulate_frames(2)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return
	# Read the scene's OWN HUD (the same node barcelona/northern_isle assert on):
	# a bare `RaceUI.new()` has none of the `%Cluster`-class children its `_ready`
	# binds, so constructing one detached was the wrong probe. The HUD's parent
	# chain carries this scene's file path, which is what `_resolve_track_id`
	# walks (plan §4 note: the registry maps this scene's path to "le_mans").
	var hud := scene.get_node_or_null("HUD")
	assert_that(hud).is_not_null()
	if hud != null:
		assert_that(hud.call("_resolve_track_id")).is_equal("le_mans")

# --- checkpoint / lap contract ---------------------------------------------

func test_checkpoint_progression_ticks_exactly_one_lap() -> void:
	var runner := scene_runner(SCENE_LE_MANS)
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return

	var car := _new_stub_car()
	var cps := _ordered_checkpoints()
	assert_int(cps.size()).is_equal(LeMansLayout.CHECKPOINT_COUNT)
	if cps.size() != LeMansLayout.CHECKPOINT_COUNT:
		return
	var counter := _new_lap_counter(3)

	# Feed gates 0 -> 23 in index order: a lap ticks ONLY at the line (23),
	# and only because >= half the circuit's gates were taken (23 >= 12).
	var laps: Array = []
	counter.lap_completed.connect(
		func(_v: VehiclePhysics, lap_num: int, _time: float) -> void: laps.append(lap_num))
	for i in LeMansLayout.CHECKPOINT_COUNT:
		counter.update(car, cps[i])
		if i < LeMansLayout.CHECKPOINT_COUNT - 1:
			assert_int(laps.size()).is_equal(0)
	assert_int(laps.size()).is_equal(1)
	assert_int(int(laps[0])).is_equal(1)
	assert_int(counter.get_current_lap()).is_equal(2)

	# Out-of-order: the line crossed BEFORE any gate completes no lap (this is
	# exactly the standing-start grid run-up), and the following gate sweep
	# cannot complete one either -- the car has never re-crossed the line.
	var counter2 := _new_lap_counter(3)
	var laps2: Array = []
	counter2.lap_completed.connect(
		func(_v: VehiclePhysics, lap_num: int, _time: float) -> void: laps2.append(lap_num))
	counter2.update(car, cps[LeMansLayout.CHECKPOINT_COUNT - 1])
	assert_int(laps2.size()).is_equal(0)
	assert_int(counter2.get_current_lap()).is_equal(1)
	for i in LeMansLayout.CHECKPOINT_COUNT - 1:
		counter2.update(car, cps[i])
	assert_int(laps2.size()).is_equal(0)

# --- preview probe ----------------------------------------------------------

## `TrackLayoutSource` instantiates the scene OFF-TREE and calls this; it must
## return exactly what `_ready` drives from, with no side effects.
func test_generate_road_points_probe_matches_build_centerline() -> void:
	var packed := load(SCENE_LE_MANS) as PackedScene
	assert_that(packed).is_not_null()
	if packed == null:
		return
	var probe_scene := packed.instantiate()
	assert_that(probe_scene).is_not_null()
	if probe_scene == null:
		return
	var generated: Array = probe_scene.call("_generate_road_points")
	var expected := LeMansLayout.build_centerline()
	assert_int(generated.size()).is_equal(LeMansLayout.TOTAL_POINTS)
	assert_int(generated.size()).is_equal(expected.size())
	for i in [0, 1, 2400, 4684, 4799]:
		if i < generated.size() and i < expected.size():
			assert_that(generated[i]).is_equal_approx(expected[i], Vector3(0.001, 0.001, 0.001))
	# Off-tree means off-tree: nothing was built by the probe.
	assert_that(probe_scene.get_node_or_null("RoadNetwork/RoadSurface")).is_null()
	probe_scene.free()

# --- P2 ground + verge skirt (A7, real elevation) ------------------------

func test_elevated_ground_and_full_edge_skirt() -> void:
	var runner := scene_runner(SCENE_LE_MANS)
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return

	# Still no Terrain3D: the scene owns its height field (LeMansTerrain).
	assert_that(_first_of_type(scene, "Terrain3D")).is_null()
	assert_bool(LeMansTerrain.is_ready()).is_true()
	var tiles := LeMansTerrain.tiles()
	var ground := scene.get_node_or_null("Ground") as Node3D
	assert_that(ground).is_not_null()
	if ground == null:
		return
	assert_int(ground.get_child_count()).is_equal(tiles.size())
	assert_int(tiles.size()).is_greater(100)
	# Collision: one trimesh per visual tile, built FROM that tile's mesh, so
	# the physics ground is exactly the drawn ground.
	var body := scene.get_node_or_null("GroundBody") as StaticBody3D
	assert_that(body).is_not_null()
	if body != null:
		assert_int(body.get_child_count()).is_equal(tiles.size())
		var shape := (body.get_child(0) as CollisionShape3D).shape
		assert_bool(shape is ConcavePolygonShape3D).is_true()
	# Coverage: the grid spans the old 6 x 7 km plane around the bbox centre.
	var center: Vector3 = scene.get("ground_center")
	var g0 := LeMansTerrain.grid_origin()
	var gs := LeMansTerrain.grid_size()
	assert_float(g0.x).is_less_equal(center.x - 2999.0)
	assert_float(g0.y).is_less_equal(center.z - 3499.0)
	assert_float(g0.x + float(gs.x - 1) * LeMansTerrain.CELL_M).is_greater_equal(center.x + 2999.0)
	assert_float(g0.y + float(gs.y - 1) * LeMansTerrain.CELL_M).is_greater_equal(center.z + 3499.0)
	# Real relief in the surrounding terrain, not a plane.
	var hs := LeMansTerrain.heights()
	var lo := INF
	var hi := -INF
	for v in hs:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	print("[a7] terrain relief %.1f m (%.1f .. %.1f world Y), bake %d ms" % [hi - lo, lo, hi, LeMansTerrain.bake_ms()])
	assert_float(hi - lo).is_between(30.0, 70.0)

	# Under the road: the terrain follows the road-ground profile everywhere
	# (0.40 m under the inner edge), and never rises through the carriageway.
	var n := LeMansLayout.TOTAL_POINTS
	var road: Array = scene.get("road_points")
	var worst_under := 0.0
	var worst_poke := -INF
	for i in range(0, n, 7):
		var arc := LeMansLayout.arc_of_index(i)
		var c: Vector3 = road[i]
		var t := float(scene.call("terrain_height", c.x, c.z))
		worst_under = maxf(worst_under, absf(t - LeMansLayout.ground_y_at_arc(arc)))
		for side: float in [-1.0, 1.0]:
			var e: Vector3 = scene.call("edge_point", i, side)
			worst_poke = maxf(worst_poke, float(scene.call("terrain_height", e.x, e.z)) - e.y)
	print("[a7] terrain vs road-ground worst %.3f m, worst (terrain - edge) %.3f m" % [worst_under, worst_poke])
	assert_float(worst_under).is_less(TERRAIN_TOL)
	assert_float(worst_poke).is_less(-(EDGE_DROP - TERRAIN_TOL))

	# The skirt ribbon: 2 sides x 2 vertices per station x every station.
	var skirt := scene.get_node_or_null("Skirt") as MeshInstance3D
	assert_that(skirt).is_not_null()
	if skirt == null:
		return
	var arrays := (skirt.mesh as ArrayMesh).surface_get_arrays(0)
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	assert_int(verts.size()).is_equal(n * 4)
	assert_int(verts.size()).is_equal(int(scene.get("skirt_vertex_count")))
	assert_int(indices.size()).is_equal(n * 2 * 6)
	# Every station, both sides: top = the road mesh's own edge vertex, bottom
	# driven SKIRT_BURY into the terrain at its foot, exactly vertical.
	var bury := SKIRT_BURY
	var worst_top := 0.0
	var worst_bottom := 0.0
	var worst_vertical := 0.0
	for side: float in [-1.0, 1.0]:
		var base := 0 if side < 0.0 else n * 2
		for i in n:
			var top: Vector3 = verts[base + i * 2]
			var bottom: Vector3 = verts[base + i * 2 + 1]
			var edge: Vector3 = scene.call("edge_point", i, side)
			worst_top = maxf(worst_top, top.distance_to(edge))
			var foot := float(scene.call("terrain_height", bottom.x, bottom.z))
			worst_bottom = maxf(worst_bottom, absf(bottom.y - (foot - bury)))
			worst_vertical = maxf(worst_vertical, Vector2(top.x - bottom.x, top.z - bottom.z).length())
	assert_float(worst_top).is_less(0.001)
	assert_float(worst_bottom).is_less(0.001)
	assert_float(worst_vertical).is_less(0.001)

	# Y rule at real heights: a FLAT station's edge rides ROAD_BASE_Y above the
	# profile and 0.40 m above the ground; the banked inner edge rides
	# ROAD_BASE_Y, the outer edge carries the full WIDTH * |sin(bank)| lift.
	var bank: PackedFloat32Array = scene.get("bank_profile")
	var elev := LeMansLayout.build_elevation_profile()
	var flat_i := -1
	var bank_i := -1
	var max_bank := 0.0
	for i in n:
		if absf(bank[i]) < 1.0e-9 and flat_i < 0:
			flat_i = i
		if absf(bank[i]) > max_bank:
			max_bank = absf(bank[i])
			bank_i = i
	assert_that(flat_i).is_greater_equal(0)
	assert_float(max_bank).is_greater(deg_to_rad(2.0))
	for side: float in [-1.0, 1.0]:
		var base := 0 if side < 0.0 else n * 2
		var top: Vector3 = verts[base + flat_i * 2]
		var foot := float(scene.call("terrain_height", top.x, top.z))
		print("[a7] flat station %d side %.0f top=%.4f drop-to-ground=%.4f" % [flat_i, side, top.y, top.y - foot])
		assert_float(top.y - elev[flat_i]).is_equal_approx(LeMansLayout.ROAD_BASE_Y, 0.005)
		assert_float(top.y - foot).is_equal_approx(EDGE_DROP, TERRAIN_TOL)
	var side_a: Vector3 = verts[bank_i * 2]
	var side_b: Vector3 = verts[n * 2 + bank_i * 2]
	var inner_top := side_a if side_a.y < side_b.y else side_b
	var outer_top := side_b if side_a.y < side_b.y else side_a
	var lift := LeMansLayout.WIDTH_M * absf(sin(bank[bank_i]))
	assert_float(inner_top.y - elev[bank_i]).is_equal_approx(LeMansLayout.ROAD_BASE_Y, 0.005)
	assert_float(outer_top.y - inner_top.y).is_equal_approx(lift, 0.005)

	# Foliage present (its own clearance contract is §8.3(e)).
	var foliage := scene.get_node_or_null("Foliage") as Foliage
	assert_that(foliage).is_not_null()
	if foliage != null:
		assert_int(foliage.get_instance_count()).is_greater(0)


## Every dressing kind stands ON the real ground: barrier/prop origins at the
## terrain height at their own XZ (minus the documented bury for trees and
## buildings), on-road kinds on the road surface, and nothing floating.
func test_dressing_follows_the_terrain() -> void:
	var runner := scene_runner(SCENE_LE_MANS)
	await runner.simulate_frames(3)
	var scene := runner.scene()
	var dressing := scene.get_node_or_null("Dressing") as LeMansDressing
	assert_that(dressing).is_not_null()
	if dressing == null:
		return
	var exact_kinds: Array[String] = [
		LeMansDressing.KIND_ARMCO, LeMansDressing.KIND_CATCH_FENCE,
		LeMansDressing.KIND_BARRIER_PANEL, LeMansDressing.KIND_HEDGE,
		LeMansDressing.KIND_POST, LeMansDressing.KIND_AD_BOARD,
		LeMansDressing.KIND_DISTANCE_BOARD, LeMansDressing.KIND_CAMERA_TOWER,
		LeMansDressing.KIND_SAUSAGE_KERB, LeMansDressing.KIND_TRAP,
		LeMansDressing.KIND_RUNOFF,
	]
	for kind in exact_kinds:
		var worst := 0.0
		var origins := dressing.origins_of(kind)
		for i in range(0, origins.size(), maxi(1, origins.size() >> 7)):
			var o := origins[i]
			worst = maxf(worst, absf(o.y - float(scene.call("terrain_height", o.x, o.z))))
		assert_float(worst).override_failure_message("%s off the ground by %.3f m" % [kind, worst]).is_less(0.01)
	var buried: Dictionary = {
		LeMansDressing.KIND_TREELINE: LeMansDressing.TREE_BURY,
		LeMansDressing.KIND_FOREST_WALL: LeMansDressing.TREE_BURY,
		LeMansDressing.KIND_FAR_TREELINE: LeMansDressing.TREE_BURY * 4.0,
		LeMansDressing.KIND_GRANDSTAND: LeMansDressing.BUILDING_BURY,
		LeMansDressing.KIND_PIT_BUILDING: LeMansDressing.BUILDING_BURY,
	}
	for kind2: String in buried:
		var depth: float = buried[kind2]
		var worst2 := 0.0
		var origins2 := dressing.origins_of(kind2)
		for i in range(0, origins2.size(), maxi(1, origins2.size() >> 7)):
			var o2 := origins2[i]
			worst2 = maxf(worst2, absf(o2.y + depth - float(scene.call("terrain_height", o2.x, o2.z))))
		assert_float(worst2).override_failure_message("%s off the ground by %.3f m" % [kind2, worst2]).is_less(0.01)
	# On-road kinds: on the (elevated, banked) carriageway -- within the bank
	# lift of the centerline height at the nearest point.
	var center_line := LeMansLayout.build_centerline()
	for kerb in dressing.origins_of(LeMansDressing.KIND_KERB):
		var q := _nearest_point(center_line, kerb)
		assert_float(absf(kerb.y - q.y)).is_less(0.35)
	# Long props follow the grade: armco on the Dunlop climb is pitched.
	var climb_arc := LeMansLayout.arc_at_chainage(500.0)
	var max_pitch := 0.0
	for t in dressing.transforms_of(LeMansDressing.KIND_ARMCO):
		var c := LeMansLayout.point_at_arc(climb_arc)
		if Vector2(t.origin.x - c.x, t.origin.z - c.z).length() < 60.0:
			max_pitch = maxf(max_pitch, absf(t.basis.x.normalized().y))
	assert_float(max_pitch).is_greater(0.01)


## Centerline point nearest `p` (XZ), full resolution.
func _nearest_point(points: Array[Vector3], p: Vector3) -> Vector3:
	var best := INF
	var best_q := Vector3.ZERO
	for q in points:
		var d := Vector2(p.x - q.x, p.z - q.z).length_squared()
		if d < best:
			best = d
			best_q = q
	return best_q


# --- WS-B: ground macro variation (Le Mans visual realism plan) ---------------


func test_le_mans_ground_has_macro_variation() -> void:
	var runner := scene_runner(SCENE_LE_MANS)
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return

	# Plain, skirt and verge all run the shared world-space ground shader
	# (le_mans_visual_realism_plan WS-B): same shader + same noise texture is
	# the seamless-edge contract, so check both, not just "a material exists".
	var shared_noise: Texture2D = LeMansSurfaces.noise_texture()
	for node_name: String in ["Ground/GroundTile_0", "Skirt", "Verge"]:
		var mi := scene.get_node_or_null(node_name) as MeshInstance3D
		assert_that(mi).is_not_null()
		if mi == null:
			continue
		var mat := mi.material_override as ShaderMaterial
		assert_that(mat).is_not_null()
		if mat == null:
			continue
		assert_str(mat.shader.resource_path).is_equal(LeMansSurfaces.GROUND_SHADER)
		assert_that(mat.get_shader_parameter("lm_noise")).is_same(shared_noise)
	# Only the verge turns the vertex-colour wear on.
	var verge := scene.get_node_or_null("Verge") as MeshInstance3D
	var ground := scene.get_node_or_null("Ground/GroundTile_0") as MeshInstance3D
	if verge != null and ground != null:
		assert_float(float((verge.material_override as ShaderMaterial).get_shader_parameter("vertex_wear"))).is_equal(1.0)
		assert_float(float((ground.material_override as ShaderMaterial).get_shader_parameter("vertex_wear"))).is_equal(0.0)
		# Verge ribbon: 2 sides x 2 rows x every station, wear on the inner
		# row only (the outer row is exactly 0 -> dissolves into the plain).
		var arrays := (verge.mesh as ArrayMesh).surface_get_arrays(0)
		var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var colors := arrays[Mesh.ARRAY_COLOR] as PackedColorArray
		assert_int(verts.size()).is_equal(LeMansLayout.TOTAL_POINTS * 4)
		var inner_max := 0.0
		var outer_max := 0.0
		for i in colors.size():
			if i % 2 == 0:
				inner_max = maxf(inner_max, colors[i].r)
			else:
				outer_max = maxf(outer_max, colors[i].r)
		assert_float(inner_max).is_greater(0.5)
		assert_float(outer_max).is_equal(0.0)

	# Skirt structure unchanged (still the ArrayMesh the A7 contract pins).
	var skirt := scene.get_node_or_null("Skirt") as MeshInstance3D
	if skirt != null:
		var sarrays := (skirt.mesh as ArrayMesh).surface_get_arrays(0)
		assert_int((sarrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(LeMansLayout.TOTAL_POINTS * 4)


# --- WS-B/WS-F: carriageway surface -------------------------------------------

func test_road_surface_asphalt_shader_and_racing_line() -> void:
	var runner := scene_runner(SCENE_LE_MANS)
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return
	var surfaces := scene.get_node("RoadNetwork").find_children("RoadSurface", "MeshInstance3D", true, false)
	assert_int(surfaces.size()).is_equal(1)
	if surfaces.is_empty():
		return
	var surface := surfaces[0] as MeshInstance3D
	var mat := surface.material_override as ShaderMaterial
	assert_that(mat).is_not_null()
	if mat != null:
		assert_str(mat.shader.resource_path).is_equal(LeMansSurfaces.ASPHALT_SHADER)
	# Receives the wear decals.
	assert_int(surface.layers & LeMansDressing.DECAL_LAYER).is_equal(LeMansDressing.DECAL_LAYER)
	# The visual strip is the road's own edge vertices (+ one closing row), with
	# arc-length UVs and the racing-line UV2.
	var arrays := (surface.mesh as ArrayMesh).surface_get_arrays(0)
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var uv := arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
	var uv2 := arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array
	var n := LeMansLayout.TOTAL_POINTS
	assert_int(verts.size()).is_equal((n + 1) * 2)
	assert_int(uv2.size()).is_equal(verts.size())
	var worst := 0.0
	for i in range(0, n, 37):
		worst = maxf(worst, verts[i * 2].distance_to(scene.call("edge_point", i, -1.0) as Vector3))
		worst = maxf(worst, verts[i * 2 + 1].distance_to(scene.call("edge_point", i, 1.0) as Vector3))
	assert_float(worst).is_less(0.001)
	assert_float(uv[n * 2].y).is_equal_approx(LeMansLayout.spacing() * float(n), 0.01)
	# Every front face points up (a back face reads near-black under the sun).
	var idx := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var down := 0
	for t in range(0, idx.size(), 3):
		var nrm := (verts[idx[t + 1]] - verts[idx[t]]).cross(verts[idx[t + 2]] - verts[idx[t]])
		if nrm.y > 0.0:
			down += 1
	assert_int(down).is_equal(0)
	# Racing line: bounded, swings well off-centre somewhere (corners), and
	# stays near the middle mid-Hunaudieres (chainage 4,000, dead straight).
	var profile: Dictionary = scene.call("racing_line_profile")
	var line := profile["line"] as PackedFloat32Array
	var max_abs := 0.0
	for v in line:
		max_abs = maxf(max_abs, absf(v))
	assert_float(max_abs).is_less_equal(0.721)
	assert_float(max_abs).is_greater(0.3)
	var straight_i := int(roundf(LeMansLayout.arc_at_chainage(4000.0) / LeMansLayout.spacing())) % n
	assert_float(absf(line[straight_i])).is_less(0.15)
	# TrackBuilder's 1 m ARTERIAL red/white edge strips are replaced by the
	# shader's painted lines.
	for edge_name: String in ["RoadEdgeRight", "RoadEdgeLeft"]:
		var edges := scene.get_node("RoadNetwork").find_children(edge_name, "MeshInstance3D", true, false)
		for e in edges:
			assert_bool((e as MeshInstance3D).visible).is_false()


# --- A8: dressing -------------------------------------------------------------

## Brand tokens that must appear NOWHERE in the dressing subtree (node names
## or any label text): §7 gotcha 8 forbids trademarked banners in game text,
## and §3.8 demands the Dunlop-bridge arch carry a NEUTRAL banner.
const BANNED_BRAND_TOKENS: Array[String] = [
	"dunlop", "michelin", "bridgestone", "pirelli", "continental",
	"lexus", "toyota", "mazda", "porsche", "ferrari", "chevrolet",
]

func test_dressing_budgets_placement_and_no_trademarks() -> void:
	var runner := scene_runner(SCENE_LE_MANS)
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return

	var dressing := scene.get_node_or_null("Dressing") as LeMansDressing
	assert_that(dressing).is_not_null()
	if dressing == null:
		return
	assert_bool(dressing.is_built()).is_true()
	assert_that(dressing.dropped_kinds()).is_empty()

	# §3.8 budgets: portals + paint are singletons; the rest are cadence/window
	# driven. Bands, not exact counts, so a pitch tweak is not a red suite --
	# but every kind must be visibly populated (risk 1: "budget counts
	# explicitly").
	assert_int(dressing.count_of(LeMansDressing.KIND_GANTRY)).is_equal(1)
	assert_int(dressing.count_of(LeMansDressing.KIND_PAINT)).is_equal(1)
	assert_int(dressing.count_of(LeMansDressing.KIND_ARCH)).is_equal(1)
	assert_int(dressing.count_of(LeMansDressing.KIND_HEDGE)).is_greater(500)
	assert_int(dressing.count_of(LeMansDressing.KIND_TYRE)).is_equal(
		LeMansDressing.TYRE_STACKS_PER_ZONE * LeMansDressing.TYRE_PER_STACK
		* LeMansDressing.TYRE_ZONE_CHAINAGES.size())
	assert_int(dressing.count_of(LeMansDressing.KIND_ARMCO)).is_greater(50)
	assert_int(dressing.count_of(LeMansDressing.KIND_KERB)).is_greater(20)
	assert_int(dressing.count_of(LeMansDressing.KIND_POST)).is_greater(8)
	# WS-C: barriers/fences/tyre walls/panels
	assert_int(dressing.count_of(LeMansDressing.KIND_CATCH_FENCE)).is_greater(40)
	assert_int(dressing.count_of(LeMansDressing.KIND_TYRE_WALL)).is_greater(100)
	assert_int(dressing.count_of(LeMansDressing.KIND_BARRIER_PANEL)).is_greater(30)
	# WS-D: ad boards/posts/towers/service tracks
	assert_int(dressing.count_of(LeMansDressing.KIND_AD_BOARD)).is_greater(50)
	assert_int(dressing.count_of(LeMansDressing.KIND_DISTANCE_BOARD)).is_greater(10)
	assert_int(dressing.count_of(LeMansDressing.KIND_CAMERA_TOWER)).is_greater(2)
	assert_int(dressing.count_of(LeMansDressing.KIND_SERVICE_TRACK)).is_greater(10)
	assert_int(dressing.count_of(LeMansDressing.KIND_SAUSAGE_KERB)).is_greater(5)
	assert_int(dressing.count_of(LeMansDressing.KIND_GRANDSTAND)).is_greater(3)
	assert_int(dressing.count_of(LeMansDressing.KIND_PIT_BUILDING)).is_greater(3)
	# WS-E: tree lines + horizon silhouettes
	assert_int(dressing.count_of(LeMansDressing.KIND_TREELINE)).is_greater(800)
	assert_int(dressing.count_of(LeMansDressing.KIND_FOREST_WALL)).is_greater(800)
	assert_int(dressing.count_of(LeMansDressing.KIND_FAR_TREELINE)).is_greater(500)
	for sil: String in [LeMansDressing.KIND_SILHOUETTE_INDUSTRIAL, LeMansDressing.KIND_SILHOUETTE_CHURCH,
			LeMansDressing.KIND_SILHOUETTE_HANGAR, LeMansDressing.KIND_SILHOUETTE_WALLS]:
		assert_int(dressing.count_of(sil)).is_equal(1)

	# Every kind resolves a procedural mesh (a GLB-less builder cannot drop).
	var kinds: Array[String] = [
		LeMansDressing.KIND_GANTRY, LeMansDressing.KIND_PAINT,
		LeMansDressing.KIND_ARCH, LeMansDressing.KIND_ARMCO,
		LeMansDressing.KIND_CATCH_FENCE, LeMansDressing.KIND_TYRE_WALL,
		LeMansDressing.KIND_BARRIER_PANEL,
		LeMansDressing.KIND_HEDGE, LeMansDressing.KIND_TYRE,
		LeMansDressing.KIND_KERB, LeMansDressing.KIND_POST,
		LeMansDressing.KIND_DISTANCE_BOARD, LeMansDressing.KIND_AD_BOARD,
		LeMansDressing.KIND_CAMERA_TOWER, LeMansDressing.KIND_SERVICE_TRACK,
		LeMansDressing.KIND_TRAP, LeMansDressing.KIND_RUNOFF,
		LeMansDressing.KIND_SAUSAGE_KERB, LeMansDressing.KIND_GRANDSTAND,
		LeMansDressing.KIND_PIT_BUILDING, LeMansDressing.KIND_TREELINE,
		LeMansDressing.KIND_FOREST_WALL, LeMansDressing.KIND_FAR_TREELINE,
		LeMansDressing.KIND_SILHOUETTE_INDUSTRIAL, LeMansDressing.KIND_SILHOUETTE_CHURCH,
		LeMansDressing.KIND_SILHOUETTE_HANGAR, LeMansDressing.KIND_SILHOUETTE_WALLS,
	]
	for kind in kinds:
		assert_that(dressing.prop_mesh(kind)).is_not_null()
	# WS-A: sand/gravel traps and run-off present
	assert_int(dressing.count_of(LeMansDressing.KIND_TRAP)).is_greater(10)
	assert_int(dressing.count_of(LeMansDressing.KIND_RUNOFF)).is_greater(10)

	# Landmark placement: the gantry at the S/F line (arc 0), the neutral arch
	# at the Dunlop-bridge chainage (869) -- both within one road width of the
	# centerline point they straddle.
	var gantry := dressing.transforms_of(LeMansDressing.KIND_GANTRY)[0].origin
	assert_float(_xz_distance_to_centerline(gantry)).is_less(2.0)
	var arch := dressing.transforms_of(LeMansDressing.KIND_ARCH)[0].origin
	var arch_target := LeMansLayout.point_at_arc(
		LeMansLayout.arc_at_chainage(LeMansLayout.LANDMARK_DUNLOP_BRIDGE))
	assert_float(Vector2(arch.x - arch_target.x, arch.z - arch_target.z).length()).is_less(5.0)

	# Road-bound vs ground-bound placement, sampled: kerbs and paint lie ON the
	# carriageway (lateral < W/2), armco/hedges/tyres/posts stand CLEAR of it
	# (lateral > W/2) and on the plain.
	var road_half := LeMansLayout.WIDTH_M * 0.5
	for kind: String in [LeMansDressing.KIND_KERB, LeMansDressing.KIND_PAINT]:
		var on_road := dressing.transforms_of(kind)
		for i in mini(on_road.size(), 24):
			var lateral := _xz_distance_to_centerline(on_road[i].origin)
			assert_float(lateral).is_less(road_half + 0.5)
	for kind2: String in [LeMansDressing.KIND_ARMCO, LeMansDressing.KIND_HEDGE,
			LeMansDressing.KIND_TYRE, LeMansDressing.KIND_POST]:
		var off_road := dressing.transforms_of(kind2)
		for i in mini(off_road.size(), 24):
			var lateral2 := _xz_distance_to_centerline(off_road[i].origin)
			assert_float(lateral2).is_greater(road_half + 0.5)
	# Ground-bound kinds stand on the (real-elevation) ground exactly -- see
	# test_dressing_follows_the_terrain for every kind.
	for kind3: String in [LeMansDressing.KIND_ARMCO, LeMansDressing.KIND_POST]:
		var origins3 := dressing.origins_of(kind3)
		for k3 in range(0, origins3.size(), 97):
			var origin := origins3[k3]
			assert_float(origin.y).is_equal_approx(float(scene.call("terrain_height", origin.x, origin.z)), 0.001)

	# No trademarked brand in any node name or label text anywhere under the
	# dressing (the neutral-banner contract, machine-checked).
	assert_that(_brand_leaks(dressing)).is_empty()

	# Determinism + scene parity: two standalone builds are bit-identical, and
	# the scene's own dressing matches them (same inputs, same code path) --
	# i.e. §3.8 "built by le_mans_dressing.gd alone" holds.
	var probe := LeMansDressing.new()
	probe.configure(LeMansLayout.build_centerline(), LeMansLayout.build_bank_profile(),
		LeMansLayout.WIDTH_M)
	probe.build()
	var probe2 := LeMansDressing.new()
	probe2.configure(LeMansLayout.build_centerline(), LeMansLayout.build_bank_profile(),
		LeMansLayout.WIDTH_M)
	probe2.build()
	assert_bool(probe.is_built()).is_true()
	var det_kinds: Array[String] = kinds.duplicate()
	det_kinds.append(LeMansDressing.KIND_DECAL)
	for kind4 in det_kinds:
		var a := probe.transforms_of(kind4)
		var b := probe2.transforms_of(kind4)
		assert_int(a.size()).is_equal(b.size())
		assert_that(a).is_equal(b)
		assert_int(dressing.count_of(kind4)).is_equal(a.size())
	probe2.free()
	probe.free()


## WS-C: the armco runs (nearly) the full lap on BOTH sides -- every 25 m
## sample of the barrier line has an armco instance within 3.5 m, except the
## deliberate marshal-post gaps -- and stands behind any trap.
func test_full_lap_armco_coverage() -> void:
	var runner := scene_runner(SCENE_LE_MANS)
	await runner.simulate_frames(3)
	var dressing := runner.scene().get_node_or_null("Dressing") as LeMansDressing
	assert_that(dressing).is_not_null()
	if dressing == null:
		return
	var grid := {}
	for o in dressing.origins_of(LeMansDressing.KIND_ARMCO):
		var key := Vector2i(floori(o.x / 10.0), floori(o.z / 10.0))
		if not grid.has(key):
			grid[key] = PackedVector2Array()
		var arr: PackedVector2Array = grid[key]
		arr.append(Vector2(o.x, o.z))
		grid[key] = arr
	var perimeter := LeMansLayout.spacing() * float(LeMansLayout.TOTAL_POINTS)
	var samples := int(perimeter / 25.0)
	for side: float in [1.0, -1.0]:
		var hit := 0
		for k in samples:
			var s := float(k) * 25.0
			var frame := LeMansLayout.frame_at_arc(s)
			var c: Vector3 = frame["center"]
			var f: Vector3 = frame["forward"]
			var right := f.cross(Vector3.UP).normalized()
			var p := Vector2(c.x, c.z) + Vector2(right.x, right.z) * dressing.barrier_offset(s, side)
			var found := false
			var cell := Vector2i(floori(p.x / 10.0), floori(p.y / 10.0))
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					var arr2: PackedVector2Array = grid.get(Vector2i(cell.x + dx, cell.y + dz), PackedVector2Array())
					for q in arr2:
						if q.distance_to(p) < 3.5:
							found = true
			if found:
				hit += 1
		var coverage := float(hit) / float(samples)
		print("[ws-c] armco coverage side %.0f = %.3f (%d/%d)" % [side, coverage, hit, samples])
		assert_float(coverage).is_greater(0.95)
	# Behind every trap: the barrier line at the trap centre clears the sand.
	for ch in LeMansDressing.TRAP_CHAINAGES:
		var arc := LeMansLayout.arc_at_chainage(ch)
		var side2 := float(dressing.call("_outside_side", arc))
		assert_float(absf(dressing.barrier_offset(arc, side2))).is_greater(
			LeMansLayout.WIDTH_M * 0.5 + LeMansDressing.APRON_WIDTH_M + LeMansDressing.TRAP_WIDTH_M)


## WS-A: a sand trap + paved apron at every TRAP_CHAINAGES corner, on the
## outside; the scene's dressing registers them in SurfaceRegistry (sand grip
## below asphalt), the carriageway itself is never inside a zone, and the zones
## exist only while the dressing is in the tree.
func test_sand_traps_at_chainages_drive_surface_grip() -> void:
	var runner := scene_runner(SCENE_LE_MANS)
	await runner.simulate_frames(3)
	var dressing := runner.scene().get_node_or_null("Dressing") as LeMansDressing
	assert_that(dressing).is_not_null()
	if dressing == null:
		return
	var zones := dressing.surface_zones()
	assert_int(zones.size()).is_equal(LeMansDressing.TRAP_CHAINAGES.size() * 2)
	var classifier := SurfaceRegistry.build_classifier(Callable(), Callable())
	var asphalt_lat := SurfaceRegistry.get_lateral(SurfaceRegistry.ASPHALT)
	for ch in LeMansDressing.TRAP_CHAINAGES:
		var arc := LeMansLayout.arc_at_chainage(ch)
		var side := float(dressing.call("_outside_side", arc))
		var frame := LeMansLayout.frame_at_arc(arc)
		var c: Vector3 = frame["center"]
		var f: Vector3 = frame["forward"]
		var right := f.cross(Vector3.UP).normalized()
		var sand_lat := LeMansLayout.WIDTH_M * 0.5 + LeMansDressing.APRON_WIDTH_M + LeMansDressing.TRAP_WIDTH_M * 0.5
		var in_sand := c + right * (side * sand_lat)
		var on_apron := c + right * (side * (LeMansLayout.WIDTH_M * 0.5 + LeMansDressing.APRON_WIDTH_M * 0.5))
		assert_str(SurfaceRegistry.classify_zone_at(in_sand)).is_equal(SurfaceRegistry.SAND)
		assert_str(SurfaceRegistry.classify_zone_at(on_apron)).is_equal(SurfaceRegistry.ASPHALT)
		assert_str(SurfaceRegistry.classify_zone_at(c)).is_equal("")
		assert_str(SurfaceRegistry.classify_zone_at(c + right * (-side * sand_lat))).is_equal("")
		# What the car's own classifier reports (vehicle_physics wiring):
		var grip: Dictionary = classifier.call(in_sand)
		assert_str(String(grip["surface_key"])).is_equal(SurfaceRegistry.SAND)
		assert_float(float(grip["lateral"])).is_less(asphalt_lat)
		# Visual trap instances exist around this corner.
		var near := 0
		for o in dressing.origins_of(LeMansDressing.KIND_TRAP):
			if Vector2(o.x - c.x, o.z - c.z).length() < LeMansDressing.TRAP_HALF_WINDOW_M + 20.0:
				near += 1
		assert_int(near).is_greater(10)

	# Lifecycle: a standalone (off-tree) build registers nothing; entering the
	# tree registers; leaving clears.
	var probe_arc := LeMansLayout.arc_at_chainage(LeMansDressing.TRAP_CHAINAGES[0])
	var probe_side := float(dressing.call("_outside_side", probe_arc))
	var pf := LeMansLayout.frame_at_arc(probe_arc)
	var pc: Vector3 = pf["center"]
	var pr := (pf["forward"] as Vector3).cross(Vector3.UP).normalized()
	var probe_pt := pc + pr * (probe_side * (LeMansLayout.WIDTH_M * 0.5 + LeMansDressing.APRON_WIDTH_M + LeMansDressing.TRAP_WIDTH_M * 0.5))
	SurfaceRegistry.clear_zones()
	var probe := LeMansDressing.new()
	probe.configure(LeMansLayout.build_centerline(), LeMansLayout.build_bank_profile(), LeMansLayout.WIDTH_M)
	probe.build()
	assert_str(SurfaceRegistry.classify_zone_at(probe_pt)).is_equal("")
	add_child(probe)
	assert_str(SurfaceRegistry.classify_zone_at(probe_pt)).is_equal(SurfaceRegistry.SAND)
	remove_child(probe)
	assert_str(SurfaceRegistry.classify_zone_at(probe_pt)).is_equal("")
	probe.free()


## Plan §6: "sand zone -> grip factor < asphalt" at the registry level.
func test_le_mans_surface_registry() -> void:
	SurfaceRegistry.clear_zones()
	var poly := [Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)]
	SurfaceRegistry.add_zone(poly, SurfaceRegistry.SAND)
	var near: Dictionary = SurfaceRegistry.classify(SurfaceRegistry.BAND_PLAINS, 100.0, RoadDef.Tier.ARTERIAL, -1.0, Vector3(5, 0, 5))
	assert_that(near["surface_key"]).is_equal(SurfaceRegistry.SAND)
	assert_float(float(near["lateral"])).is_less(SurfaceRegistry.get_lateral(SurfaceRegistry.ASPHALT))
	assert_float(float(near["longitudinal"])).is_less(SurfaceRegistry.get_longitudinal(SurfaceRegistry.ASPHALT))
	var outside: Dictionary = SurfaceRegistry.classify(SurfaceRegistry.BAND_PLAINS, 100.0, RoadDef.Tier.ARTERIAL, -1.0, Vector3(25, 0, 5))
	assert_that(outside["surface_key"]).is_not_equal(SurfaceRegistry.SAND)
	SurfaceRegistry.clear_zones()


## WS-F: wear decals exist (braking/exit per sharp corner, dirt per trap, S/F),
## carry generated textures, project ONLY onto DECAL_LAYER (never the cars),
## and the quality ladder hides them on Low and shows them on Medium/High.
func test_wear_decals_textured_layered_and_preset_gated() -> void:
	var runner := scene_runner(SCENE_LE_MANS)
	await runner.simulate_frames(3)
	var dressing := runner.scene().get_node_or_null("Dressing") as LeMansDressing
	assert_that(dressing).is_not_null()
	if dressing == null:
		return
	var decals := dressing.find_children("*", "Decal", true, false)
	var corners := LeMansLayout.sharp_corner_chainages(LeMansDressing.SHARP_TURN_DEG).size()
	assert_int(decals.size()).is_greater_equal(corners * 2 + LeMansDressing.TRAP_CHAINAGES.size() + 2)
	assert_int(dressing.count_of(LeMansDressing.KIND_DECAL)).is_equal(decals.size())
	for d in decals:
		var decal := d as Decal
		assert_that(decal.texture_albedo).is_not_null()
		assert_int(decal.cull_mask).is_equal(LeMansDressing.DECAL_LAYER)
		assert_bool(decal.distance_fade_enabled).is_true()
	var settings: GDScript = load("res://scripts/ui/settings_menu.gd")
	for preset_i in 3:
		var preset: Dictionary = settings.call("preset_for", preset_i)
		settings.call("apply_quality_preset", null, null, preset, null, dressing)
		var want := preset_i >= 1
		for d2 in decals:
			assert_bool((d2 as Decal).visible).is_equal(want)


## Horizontal distance from `p` to the nearest centerline point (full
## resolution: a strided search has a half-stride along-arc bias, which at
## 5.45 m true lateral reads ~7.9 m and would make the road/ground split
## unfalsifiable).
func _xz_distance_to_centerline(p: Vector3) -> float:
	var best := INF
	var n := LeMansLayout.TOTAL_POINTS
	var probe := Vector2(p.x, p.z)
	for i in n:
		var q: Vector3 = LeMansLayout.point_at_arc(LeMansLayout.arc_of_index(i))
		best = minf(best, probe.distance_to(Vector2(q.x, q.z)))
	return best

## Every banned brand token found in the subtree's node names or Label3D text.
func _brand_leaks(node: Node) -> Array:
	var hits: Array = []
	var lower := String(node.name).to_lower()
	for token in BANNED_BRAND_TOKENS:
		if lower.find(token) >= 0:
			hits.append(String(node.name))
	if node is Label3D:
		var text := (node as Label3D).text.to_lower()
		for token in BANNED_BRAND_TOKENS:
			if text.find(token) >= 0:
				hits.append(text)
	for child in node.get_children():
		hits.append_array(_brand_leaks(child))
	return hits

## First node of class `type_name` under `from`, depth-first, or null.
func _first_of_type(from: Node, type_name: String) -> Node:
	for child in from.get_children():
		if child.get_class() == type_name:
			return child
		var nested := _first_of_type(child, type_name)
		if nested != null:
			return nested
	return null
