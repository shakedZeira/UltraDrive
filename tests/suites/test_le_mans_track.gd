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
##   * A7: flat ground plane at PLAIN_Y + the full-edge 0.40 m verge skirt on
##     both sides, no Terrain3D;
##   * the `TrackLayoutSource` off-tree probe returning `build_centerline()`.
##
## The registry reverse-lookup (`_resolve_track_id() == "le_mans"`) lands with
## P4's registry edit (plan §9 step 8), added to this suite at that step.
##
## The suite never asserts wall-clock (the `test_perf_gate` lesson) and cleans
## RaceManager state between tests exactly like `test_barcelona_rx_track.gd`.

const SCENE_LE_MANS := "res://scenes/track/le_mans.tscn"

## The visible lip the flat ground drops over at a road edge (m) -- the same
## constant the scene builds the skirt with, restated here so loosening the
## scene cannot loosen the gate (plan §3.7: ROAD_BASE_Y 0.15 -> PLAIN_Y -0.25).
const EDGE_DROP := 0.40

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

# --- P2 flat ground + verge skirt (A7) -------------------------------------

func test_flat_ground_plane_and_full_edge_skirt() -> void:
	var runner := scene_runner(SCENE_LE_MANS)
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return

	# v1 is FLAT: no Terrain3D anywhere in the scene (plan §3.7).
	assert_that(_first_of_type(scene, "Terrain3D")).is_null()

	# The plane: 6,000 x 7,000 m at PLAIN_Y, centred on the layout bbox centre.
	var ground := scene.get_node_or_null("Ground") as MeshInstance3D
	assert_that(ground).is_not_null()
	if ground == null:
		return
	var plane := ground.mesh as PlaneMesh
	assert_that(plane).is_not_null()
	if plane != null:
		assert_float(plane.size.x).is_equal_approx(6000.0, 0.01)
		assert_float(plane.size.y).is_equal_approx(7000.0, 0.01)
	assert_float(ground.position.y).is_equal_approx(LeMansLayout.PLAIN_Y, 0.001)
	var center: Vector3 = scene.get("ground_center")
	assert_float(ground.position.x).is_equal_approx(center.x, 0.001)
	assert_float(ground.position.z).is_equal_approx(center.z, 0.001)

	# Collision: one box whose TOP face is exactly the plain, so a skirt bottom
	# on the plain is never floating above the physics ground.
	var body := scene.get_node_or_null("GroundBody") as StaticBody3D
	assert_that(body).is_not_null()
	if body != null:
		var shapes := body.get_children()
		assert_int(shapes.size()).is_equal(1)
		if shapes.size() == 1:
			var box := (shapes[0] as CollisionShape3D).shape as BoxShape3D
			assert_that(box).is_not_null()
			if box != null:
				assert_float(box.size.x).is_equal_approx(6000.0, 0.01)
				assert_float(box.size.y).is_equal_approx(1.0, 0.01)
				assert_float(box.size.z).is_equal_approx(7000.0, 0.01)
				var top_y := body.global_position.y + box.size.y * 0.5
				assert_float(top_y).is_equal_approx(LeMansLayout.PLAIN_Y, 0.001)

	# The skirt ribbon: 2 sides x 2 vertices per station x every station.
	var skirt := scene.get_node_or_null("Skirt") as MeshInstance3D
	assert_that(skirt).is_not_null()
	if skirt == null:
		return
	var mesh := skirt.mesh as ArrayMesh
	assert_that(mesh).is_not_null()
	if mesh == null:
		return
	var arrays := mesh.surface_get_arrays(0)
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var n := LeMansLayout.TOTAL_POINTS
	assert_int(verts.size()).is_equal(n * 4)
	assert_int(verts.size()).is_equal(int(scene.get("skirt_vertex_count")))
	# One wrapped quad per station per side (the ribbon closes on itself with
	# `(i + 1) % n`), so 6 indices per station per side -- NOT per vertex.
	assert_int(indices.size()).is_equal(n * 2 * 6)

	# Coverage, both sides, every station: the top vertex IS the road mesh's
	# edge (same frame math -> no gap/underlap), the bottom vertex sits on the
	# plain, and the ribbon is exactly vertical.
	var worst_top := 0.0
	var worst_bottom := 0.0
	var worst_vertical := 0.0
	for side: float in [-1.0, 1.0]:
		var base := 0 if side < 0.0 else n * 2
		for i in n:
			var top: Vector3 = verts[base + i * 2]
			var bottom: Vector3 = verts[base + i * 2 + 1]
			var edge: Vector3 = scene.call("edge_point", i, side)
			worst_top = maxf(worst_top, Vector2(top.x - edge.x, top.z - edge.z).length())
			worst_bottom = maxf(worst_bottom, absf(bottom.y - LeMansLayout.PLAIN_Y))
			worst_vertical = maxf(worst_vertical, Vector2(top.x - bottom.x, top.z - bottom.z).length())
	assert_float(worst_top).is_less(0.001)
	assert_float(worst_bottom).is_less(0.001)
	assert_float(worst_vertical).is_less(0.001)

	# Y rule: a FLAT station drops exactly 0.40 m (road edge 0.15 -> plain
	# -0.25) and a fully banked one starts at the lifted outer edge and drops
	# further -- both still land on the plain.
	var bank: PackedFloat32Array = scene.get("bank_profile")
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
	assert_that(bank_i).is_greater_equal(0)
	assert_float(max_bank).is_greater(deg_to_rad(2.0))
	for side: float in [-1.0, 1.0]:
		var base := 0 if side < 0.0 else n * 2
		var top: Vector3 = verts[base + flat_i * 2]
		var bottom: Vector3 = verts[base + flat_i * 2 + 1]
		var drop := top.y - bottom.y
		print("[a7] flat station %d side %.0f top=%.4f drop=%.4f" % [flat_i, side, top.y, drop])
		assert_float(top.y).is_equal_approx(LeMansLayout.ROAD_BASE_Y, 0.005)
		assert_float(drop).is_equal_approx(EDGE_DROP, 0.005)
	# Banked station: the barcelona invariant the layout's Y rule encodes --
	# exactly ONE edge rides at ROAD_BASE_Y (the banked-down, inner edge) and
	# the other carries the full `WIDTH * |sin(bank)|` lift. WHICH side block
	# that is follows the bank sign, so read the two tops and sort them
	# rather than re-deriving the frame convention here.
	var side_a: Vector3 = verts[bank_i * 2]
	var side_b: Vector3 = verts[n * 2 + bank_i * 2]
	var inner_top := side_a if side_a.y < side_b.y else side_b
	var outer_top := side_b if side_a.y < side_b.y else side_a
	var lift := LeMansLayout.WIDTH_M * absf(sin(bank[bank_i]))
	print("[a7] banked station %d bank=%.4f deg inner_y=%.4f outer_y=%.4f lift=%.4f"
		% [bank_i, rad_to_deg(bank[bank_i]), inner_top.y, outer_top.y, lift])
	assert_float(inner_top.y).is_equal_approx(LeMansLayout.ROAD_BASE_Y, 0.005)
	assert_float(outer_top.y - LeMansLayout.ROAD_BASE_Y).is_equal_approx(lift, 0.005)
	assert_float(outer_top.y - inner_top.y).is_greater(0.4)

	# Foliage present (its own clearance contract is §8.3(e), deliberately NOT
	# asserted here: Foliage's bounded rejection may leave a stray tuft).
	var foliage := scene.get_node_or_null("Foliage") as Foliage
	assert_that(foliage).is_not_null()
	if foliage != null:
		assert_int(foliage.get_instance_count()).is_greater(0)

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

	# Every kind resolves a procedural mesh (a GLB-less builder cannot drop).
	var kinds: Array[String] = [
		LeMansDressing.KIND_GANTRY, LeMansDressing.KIND_PAINT,
		LeMansDressing.KIND_ARCH, LeMansDressing.KIND_ARMCO,
		LeMansDressing.KIND_HEDGE, LeMansDressing.KIND_TYRE,
		LeMansDressing.KIND_KERB, LeMansDressing.KIND_POST,
	]
	for kind in kinds:
		assert_that(dressing.prop_mesh(kind)).is_not_null()

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
	# Ground-bound kinds stand on the v1 plain exactly.
	for kind3: String in [LeMansDressing.KIND_ARMCO, LeMansDressing.KIND_POST]:
		for origin: Vector3 in dressing.origins_of(kind3):
			assert_float(origin.y).is_equal_approx(LeMansLayout.PLAIN_Y, 0.001)

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
	for kind4 in kinds:
		var a := probe.transforms_of(kind4)
		var b := probe2.transforms_of(kind4)
		assert_int(a.size()).is_equal(b.size())
		assert_that(a).is_equal(b)
		assert_int(dressing.count_of(kind4)).is_equal(a.size())
	probe2.free()
	probe.free()

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
