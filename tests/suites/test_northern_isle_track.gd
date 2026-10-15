# tests/suites/test_northern_isle_track.gd
extends GdUnitTestSuite

## P2/P3 gate for Northern Isle Speedway
## (docs/plans/track_northern_isle_speedway.md sections 4 "P2"/"P3").
##
## Covers the parts of the plan that are scene/engine state rather than pure
## math (P0) or TrackBuilder/RoadDef internals (P1):
##   * the scene skeleton: a 304-point looping centerline, 8 ordered
##     checkpoints on `points[i*38]`, the grid on checkpoint 0 with the car
##     facing +X, and the RoadNetwork child that gives the minimap / pause map /
##     surface-grip their road source;
##   * the registry entry and the RaceUI reverse-lookup (`_resolve_track_id`);
##   * the closed-loop validity of the checkpoint contract: 0 -> 7 ticks exactly
##     one lap, and the out-of-order 7-before-0 soft-lock case ticks none;
##   * the bank-aware ground bake (P3): recessed under the asphalt at every
##     checkpoint, no burial at the infield edge, the berm meeting the banked
##     outer edge at both turn apexes, plain beyond the embankment run, and
##     determinism across two independent bakes;
##   * foliage placement clear of the road corridor.
##
## The suite never asserts wall-clock (the `test_perf_gate` lesson) and cleans
## RaceManager state between tests exactly like `test_race_loop.gd`.

const EDGE_DROP := 0.10

var _managed_cars: Array = []
var _managed_counters: Array = []

func before_test() -> void:
	_managed_cars.clear()
	_managed_counters.clear()
	RaceManager._checkpoints_dirty = true
	RaceManager.rival_roster = []

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
	for child in get_children():
		if child is Checkpoint:
			child.free()

func _new_stub_car() -> VehiclePhysics:
	var car := VehiclePhysics.new()
	_managed_cars.append(car)
	return car

## A suite-owned counter fed the scene's real checkpoints. `start_race` would
## also flip `RaceManager.is_race_active` and start the 3-2-1-GO countdown, so
## this suite owns a bare counter to isolate the pure checkpoint/lap progression
## contract from those ceremony side effects. (The bug this comment used to cite
## is FIXED: `race_manager.gd` now binds `LapCounter.lap_completed` to a matching
## 3-arg `_on_lap_completed` handler, and `test_race_loop` pins the counted
## re-arm path that bug used to break.)
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
	for i in NorthernIsleLayout.CHECKPOINT_COUNT:
		for cp in source:
			if cp.index == i:
				ordered.append(cp)
				break
	return ordered

func _half_width() -> float:
	return NorthernIsleLayout.WIDTH * 0.5

## World position at horizontal lateral offset `s` from the frame's centerline
## (positive = outfield / right of travel), ignoring the cross-section's
## vertical component: the ground bake's `s` is measured in XZ along `right`.
func _edge_world(frame: Dictionary, s: float) -> Vector3:
	var center: Vector3 = frame["center"]
	var right: Vector3 = frame["right"]
	return center + right * s

## Banked road surface Y at lateral offset `s` (the layout's own Y rule).
func _surface_y_at(frame: Dictionary, s: float) -> float:
	var center: Vector3 = frame["center"]
	var bank := float(frame["bank"])
	return center.y - s * sin(bank)

func _apex_frame(cp_index: int) -> Dictionary:
	var indices := NorthernIsleLayout.checkpoint_indices()
	return NorthernIsleLayout.frame_at_arc(NorthernIsleLayout.arc_of_index(indices[cp_index]))

# --- scene skeleton --------------------------------------------------------

func test_scene_road_checkpoints_network_and_spawn() -> void:
	var runner := scene_runner("res://scenes/track/northern_isle.tscn")
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return

	# A 304-point looping centerline and its matching bank profile.
	var points: Array = scene.get("road_points")
	assert_int(points.size()).is_equal(NorthernIsleLayout.TOTAL_POINTS)
	var bank: PackedFloat32Array = scene.get("bank_profile")
	assert_int(bank.size()).is_equal(NorthernIsleLayout.TOTAL_POINTS)

	# The scene handed the centerline to RaceManager (harmless today, the hook
	# rival rosters read later).
	assert_int(RaceManager.rival_centerline.size()).is_equal(NorthernIsleLayout.TOTAL_POINTS)

	# Exactly 8 checkpoints, indices 0..7, in travel order, one per stride slot;
	# index 7 is the start/finish line.
	var checkpoints: Array = scene.get_tree().get_nodes_in_group("checkpoints")
	assert_int(checkpoints.size()).is_equal(NorthernIsleLayout.CHECKPOINT_COUNT)
	var by_index := {}
	for node in checkpoints:
		var cp := node as Checkpoint
		if cp != null:
			by_index[cp.index] = cp
	assert_int(by_index.size()).is_equal(NorthernIsleLayout.CHECKPOINT_COUNT)
	for i in NorthernIsleLayout.CHECKPOINT_COUNT:
		assert_bool(by_index.has(i)).is_true()
		var cp := by_index.get(i) as Checkpoint
		if cp == null:
			continue
		var expected: Vector3 = points[i * NorthernIsleLayout.CP_STRIDE] + Vector3(0, 0.5, 0)
		assert_that(cp.global_position).is_equal_approx(expected, Vector3(0.01, 0.01, 0.01))
		assert_bool(cp.is_start_line).is_equal(i == NorthernIsleLayout.START_LINE_INDEX)

	# The grid sits on checkpoint 0 with the car pointing down the front straight
	# (+X), the orientation the ordered checkpoint progression assumes. The car
	# is a live VehiclePhysics, so after a few frames its Y has settled from the
	# spawn offset -- assert the XZ grid slot and "above the road", never the
	# settled ride height (that would be a wall-clock/physics-timing assert).
	var spawn := scene.get_node_or_null("PlayerCar") as Node3D
	assert_that(spawn).is_not_null()
	if spawn != null:
		var cp0: Vector3 = points[0]
		var spawn_xz := Vector2(spawn.global_position.x, spawn.global_position.z)
		var cp0_xz := Vector2(cp0.x, cp0.z)
		assert_float(spawn_xz.distance_to(cp0_xz)).is_less(1.0)
		assert_float(spawn.global_position.y).is_greater(cp0.y)
		assert_float(spawn.global_position.y - cp0.y).is_between(0.2, 2.0)
		assert_bool(spawn.global_position != Vector3.ZERO).is_true()
		var forward := -spawn.global_transform.basis.z
		var travel: Vector3 = (points[1] - points[0]).normalized()
		assert_float(forward.dot(travel)).is_greater(0.9)

	# The RoadNetwork child is the road source for the minimap, pause map and
	# SurfaceRegistry asphalt grip.
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
				assert_float(def.width).is_equal_approx(NorthernIsleLayout.WIDTH, 0.001)
				assert_int(def.points.size()).is_equal(NorthernIsleLayout.TOTAL_POINTS)
				assert_bool(def.show_lane_dividers).is_false()
				assert_int(def.bank_angles.size()).is_equal(NorthernIsleLayout.TOTAL_POINTS)
		assert_float(network.nearest_road_distance(points[0])).is_less(8.0)
		assert_bool(network.is_on_road(points[0])).is_true()
		assert_that(MapRoads.resolve_road_source(scene)).is_same(network)

	# RaceUI reverse-resolves the registry id from the scene path, so best-lap
	# records bucket under ("northern_isle", class) with no extra plumbing.
	var hud := scene.get_node_or_null("HUD")
	assert_that(hud).is_not_null()
	if hud != null:
		assert_that(hud.call("_resolve_track_id")).is_equal("northern_isle")

# --- P5 wiring (the scene's Dressing child) --------------------------------

## P5 integration check for the speedway dressing WIRING. The builder's own
## contract is unit-covered by `test_northern_isle_dressing.gd`; this asserts
## only what the SCENE must do (plan §4 P5): the `Dressing` child is an
## `OvalDressing` that `northern_isle.gd` configured with the same centerline +
## bank profile the road mesh uses and then built. Everything is read back
## through the query API, so it fails loudly if the scene loses the node, the
## script stops calling `configure()`/`build()`, or a GLB stops resolving at
## scene-build time.
func test_scene_dressing_is_wired_and_populated() -> void:
	var runner := scene_runner("res://scenes/track/northern_isle.tscn")
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return

	var dressing := scene.get_node_or_null("Dressing") as OvalDressing
	assert_that(dressing).is_not_null()
	if dressing == null:
		return

	# Most diagnostic first: build() actually ran in the scene.
	assert_bool(dressing.is_built()).is_true()
	# Nothing was dropped: every referenced GLB resolved (plan §4 P4 / §6 risk 6).
	assert_bool(dressing.dropped_kinds().is_empty()).is_true()
	for kind: String in [
			OvalDressing.KIND_BARRIER, OvalDressing.KIND_GRANDSTAND,
			OvalDressing.KIND_RACING_GRANDSTAND, OvalDressing.KIND_GANTRY,
			OvalDressing.KIND_LIGHT_POLE, OvalDressing.KIND_TENT,
			OvalDressing.KIND_GARAGE]:
		var mesh := dressing.prop_mesh(kind)
		assert_object(mesh).is_not_null()
		if mesh != null:
			assert_int(mesh.get_surface_count()).is_greater(0)

	# Catch fence: ceil(perimeter / 4) posts (~225) run the whole loop, one
	# barrier segment per post (`BARRIER_SPACING` == `FENCE_POST_SPACING`).
	var expected := int(ceil(NorthernIsleLayout.perimeter() / OvalDressing.FENCE_POST_SPACING))
	assert_that(dressing.count_of(OvalDressing.KIND_FENCE_POST)) \
		.is_between(expected - 2, expected + 2)
	assert_int(dressing.barrier_transforms().size()) \
		.is_equal(dressing.count_of(OvalDressing.KIND_FENCE_POST))

	# The S/F gantry straddles the 16 m track; the sponsor boards ride both
	# straights (>= 8, `BILLBOARD_PER_STRAIGHT * 2`).
	assert_bool(dressing.gantry_ok()).is_true()
	assert_that(dressing.gantry_span()).is_greater_equal(NorthernIsleLayout.WIDTH)
	assert_int(dressing.billboard_transforms().size()).is_greater_equal(8)

	# Road-corridor gate, read through the scene's OWN RoadNetwork: every
	# ground-bound item sits outside the carriageway (> W/2 from the centerline).
	# `PropScatterer.is_clear_of_road` would demand 3 m more and the catch fence is
	# deliberately just off the edge at W/2 + 0.6 — the same corridor predicate the
	# P4 suite's own gate uses.
	var network := scene.get_node_or_null("RoadNetwork") as RoadNetwork
	assert_that(network).is_not_null()
	if network == null:
		return
	var half := NorthernIsleLayout.WIDTH * 0.5
	var min_distance := INF
	var violations := 0
	for item: Transform3D in dressing.ground_transforms():
		var road_distance := network.nearest_road_distance(item.origin)
		min_distance = minf(min_distance, road_distance)
		if road_distance <= half:
			violations += 1
	print("[p5] dressing posts=%d gantry_span=%.2f billboards=%d min_road_distance=%.3f"
		% [dressing.count_of(OvalDressing.KIND_FENCE_POST), dressing.gantry_span(),
			dressing.billboard_transforms().size(), min_distance])
	assert_int(violations).is_equal(0)

# --- registry --------------------------------------------------------------

func test_registry_entry_is_complete() -> void:
	assert_bool(TrackRegistry.has_track("northern_isle")).is_true()
	var data := TrackRegistry.get_track("northern_isle")
	assert_that(data.get("display_name")).is_equal("Northern Isle Speedway")
	assert_that(data.get("scene_path")).is_equal("res://scenes/track/northern_isle.tscn")
	assert_int(int(data.get("laps_default"))).is_equal(5)
	assert_that(data.get("difficulty")).is_equal("D")
	assert_that(data.get("circuit_type")).is_equal("OVAL")
	assert_file(TrackRegistry.get_scene_path("northern_isle")).exists()
	assert_that(load(TrackRegistry.get_scene_path("northern_isle")) as PackedScene).is_not_null()

# --- checkpoint / lap contract --------------------------------------------

func test_checkpoint_progression_ticks_exactly_one_lap() -> void:
	var runner := scene_runner("res://scenes/track/northern_isle.tscn")
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return

	var car := _new_stub_car()
	var cps := _ordered_checkpoints()
	assert_int(cps.size()).is_equal(NorthernIsleLayout.CHECKPOINT_COUNT)
	if cps.size() != NorthernIsleLayout.CHECKPOINT_COUNT:
		return
	var counter := _new_lap_counter(3)

	# Feed passes 0 -> 7 in order: a lap ticks ONLY at the last checkpoint.
	var laps: Array = []
	counter.lap_completed.connect(
		func(_v: VehiclePhysics, lap_num: int, _time: float) -> void: laps.append(lap_num))
	for i in NorthernIsleLayout.CHECKPOINT_COUNT:
		counter.update(car, cps[i])
		if i < NorthernIsleLayout.START_LINE_INDEX:
			assert_int(laps.size()).is_equal(0)
	assert_int(laps.size()).is_equal(1)
	assert_int(counter.get_current_lap()).is_equal(2)

	# Out-of-order: crossing the S/F line (7) before the grid (0) completes no
	# lap, and the sticky progression then cannot complete one either.
	var counter2 := _new_lap_counter(3)
	var laps2: Array = []
	counter2.lap_completed.connect(
		func(_v: VehiclePhysics, lap_num: int, _time: float) -> void: laps2.append(lap_num))
	counter2.update(car, cps[NorthernIsleLayout.START_LINE_INDEX])
	assert_int(laps2.size()).is_equal(0)
	assert_int(counter2.get_current_lap()).is_equal(1)
	for i in NorthernIsleLayout.START_LINE_INDEX:
		counter2.update(car, cps[i])
	assert_int(laps2.size()).is_equal(0)

# --- P3 ground + foliage ---------------------------------------------------

func test_ground_and_foliage_are_bank_aware() -> void:
	var build_start := Time.get_ticks_msec()
	var runner := scene_runner("res://scenes/track/northern_isle.tscn")
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return
	var terrain := scene.get_node_or_null("GrassGround") as Terrain3D
	assert_that(terrain).is_not_null()
	if terrain == null:
		return
	var points: Array = scene.get("road_points")
	print("[p2] ground bake %d ms (scene+bake+foliage+3 frames %d ms)"
		% [int(scene.get("ground_bake_ms")), Time.get_ticks_msec() - build_start])

	# Under every checkpoint the baked terrain is recessed below the asphalt.
	var worst_recess := INF
	for idx in NorthernIsleLayout.checkpoint_indices():
		var center: Vector3 = points[idx]
		var ground: float = terrain.data.get_height(center)
		assert_float(ground).is_less_equal(center.y - 0.05)
		worst_recess = minf(worst_recess, center.y - ground)
	print("[p2] worst checkpoint recess below asphalt = %.3f m (min allowed 0.05)" % worst_recess)

	# Both turn apexes (cp2 and cp6 carry the max bank): the infield edge never
	# buries the road, the berm meets the banked outer edge, and past the
	# embankment run the ground is the plain.
	var half := _half_width()
	var plain_reach := half + NorthernIsleLayout.EMBANK_RUN + 8.0
	for cp_index in [2, 6]:
		var frame := _apex_frame(cp_index)
		var bank := float(frame["bank"])
		assert_float(bank).is_less(-0.3)

		var inner_y := _surface_y_at(frame, -half)
		# The infield edge rides at ROAD_BASE_Y by construction (the layout's
		# load-bearing invariant).
		assert_float(inner_y).is_equal_approx(NorthernIsleLayout.ROAD_BASE_Y, 0.01)
		var inner_ground: float = terrain.data.get_height(_edge_world(frame, -half))
		assert_float(inner_ground).is_less_equal(inner_y - 0.05)

		var outer_y := _surface_y_at(frame, half)
		var outer_ground: float = terrain.data.get_height(_edge_world(frame, half))
		assert_float(absf(outer_ground - (outer_y - EDGE_DROP))).is_less(0.3)

		var plain_ground: float = terrain.data.get_height(_edge_world(frame, plain_reach))
		assert_float(absf(plain_ground - NorthernIsleLayout.PLAIN_Y)).is_less(0.05)
		print("[p2] apex cp%d bank=%.4f rad inner_y=%.3f inner_g=%.3f outer_y=%.3f outer_g=%.3f plain_g=%.3f"
			% [cp_index, bank, inner_y, inner_ground, outer_y, outer_ground, plain_ground])

	# Foliage exists and every instance clears the road corridor
	# (half width 8 + PropScatterer.ROAD_CLEARANCE_MARGIN 3 = 11 m; the same
	# predicate Foliage itself rejects with). The placement is a fixed RNG seed,
	# so this is deterministic rather than wall-clock flaky.
	var foliage := scene.get_node_or_null("Foliage") as Foliage
	assert_that(foliage).is_not_null()
	if foliage == null:
		return
	assert_int(foliage.get_instance_count()).is_greater(0)
	var network := scene.get_node_or_null("RoadNetwork") as RoadNetwork
	assert_that(network).is_not_null()
	if network == null:
		return
	var positions := foliage.get_instance_positions()
	assert_int(positions.size()).is_greater(0)
	var min_distance := INF
	var violations := 0
	for local in positions:
		var world: Vector3 = foliage.to_global(local)
		min_distance = minf(min_distance, network.nearest_road_distance(world))
		if not PropScatterer.is_clear_of_road(world, network):
			violations += 1
	print("[p2] foliage instances %d, min road distance %.3f m, violations %d"
		% [positions.size(), min_distance, violations])
	assert_int(violations).is_equal(0)
	assert_float(min_distance).is_greater_equal(11.0)

func test_ground_bake_is_deterministic() -> void:
	var first_runner := scene_runner("res://scenes/track/northern_isle.tscn")
	await first_runner.simulate_frames(2)
	var second_runner := scene_runner("res://scenes/track/northern_isle.tscn")
	await second_runner.simulate_frames(2)
	var first := first_runner.scene()
	var second := second_runner.scene()
	assert_that(first).is_not_null()
	assert_that(second).is_not_null()
	if first == null or second == null:
		return
	var t1 := first.get_node_or_null("GrassGround") as Terrain3D
	var t2 := second.get_node_or_null("GrassGround") as Terrain3D
	assert_that(t1).is_not_null()
	assert_that(t2).is_not_null()
	if t1 == null or t2 == null:
		return

	var samples := _ground_sample_points()
	assert_int(samples.size()).is_greater(10)
	for sample in samples:
		var h1: float = t1.data.get_height(sample)
		var h2: float = t2.data.get_height(sample)
		assert_float(h1).is_equal_approx(h2, 0.0001)

func _ground_sample_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var points := NorthernIsleLayout.build_centerline()
	for i in range(0, points.size(), 17):
		out.append(points[i])
		out.append(points[i] + Vector3(30.0, 0.0, 0.0))
		out.append(points[i] + Vector3(0.0, 0.0, 30.0))
	# Far corners of the pane must all read the plain.
	out.append(Vector3(-250.0, 0.0, -250.0))
	out.append(Vector3(250.0, 0.0, 250.0))
	return out
