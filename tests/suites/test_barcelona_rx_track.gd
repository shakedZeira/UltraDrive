# tests/suites/test_barcelona_rx_track.gd
extends GdUnitTestSuite

## P1/P2 gate for Circuit de Barcelona-Catalunya — Rallycross
## (docs/plans/track_barcelona_rallycross.md §5 suite 2). Mirrors
## `test_northern_isle_track.gd`'s structure and `before_test`/`after_test`
## RaceManager hygiene, but for the DIRT/GRAVEL circuit scene
## `res://scenes/track/barcelona_rx.tscn` driven by `scripts/track/barcelona_rx.gd`
## and `BarcelonaRxLayout`.
##
## Covers the parts of the plan that are scene/engine state rather than pure
## math (P0 / `test_barcelona_rx_layout.gd`) or dressing internals (P3):
##   * the scene skeleton: a 400-point looping centerline + matching bank
##     profile, 8 ordered checkpoints on `points[i*50]`, the grid on checkpoint 0
##     facing travel, and the `RoadNetwork` child that gives the minimap / pause
##     map / dirt grip their road source;
##   * the registry entry and the RaceUI reverse-lookup;
##   * the closed-loop validity of the checkpoint contract (0 -> 7 ticks exactly
##     one lap; the out-of-order 7-before-0 case ticks none);
##   * the two-sided, bank-aware ground bake (P2): recessed under the dirt at
##     every checkpoint, both edges meeting the banked edge at a bermed AND a flat
##     corner, the plain beyond the blend on both sides, and determinism across
##     two independent bakes;
##   * the MIXED surface: the layout's DIRT_SECTIONS chainage table drives the
##     road's per-segment profile, so cars on the loose section report GRAVEL
##     grip (0.85/0.80), cars on the asphalt report ASPHALT (1.0/1.0), and the
##     verge beside both is loose GRAVEL;
##   * the mixed-surface LOOK: the road renders through the mixed asphalt/dirt
##     shader whose dirt colour is the dark matte DIRT profile, with the loose
##     weight in the mesh following the same chainage table;
##   * foliage placement clear of the road corridor.
##
## The suite never asserts wall-clock (the `test_perf_gate` lesson) and cleans
## RaceManager state between tests exactly like `test_northern_isle_track.gd`.

const SCENE_BARCELONA := "res://scenes/track/barcelona_rx.tscn"

## The visible lip the ground drops over at a road edge (m) — the same constant
## the scene bakes with, restated here so loosening the scene cannot loosen the
## gate.
const EDGE_DROP := 0.10

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
## checkpoint/lap progression contract from `start_race`'s countdown ceremony
## (the `test_northern_isle_track.gd` harness).
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
	for i in BarcelonaRxLayout.CHECKPOINT_COUNT:
		for cp in source:
			if cp.index == i:
				ordered.append(cp)
				break
	return ordered

func _half_width() -> float:
	return BarcelonaRxLayout.WIDTH * 0.5

## World position at horizontal lateral offset `s` from the frame's centerline
## (positive = right of travel = the INNER side of a right-hand turn), ignoring
## the cross-section's vertical component: the ground bake's `s` is measured in
## XZ along `right`.
func _edge_world(frame: Dictionary, s: float) -> Vector3:
	var center: Vector3 = frame["center"]
	var right: Vector3 = frame["right"]
	return center + right * s

## Banked road surface Y at lateral offset `s` (the layout's own Y rule):
## `center_y - s*sin(bank)`.
func _surface_y_at(frame: Dictionary, s: float) -> float:
	var center: Vector3 = frame["center"]
	var bank := float(frame["bank"])
	return center.y - s * sin(bank)

func _apex_frame(corner: int) -> Dictionary:
	return BarcelonaRxLayout.frame_at_arc(BarcelonaRxLayout.corner_apex_arc(corner))

# --- scene skeleton --------------------------------------------------------

func test_scene_road_checkpoints_network_and_spawn() -> void:
	var runner := scene_runner(SCENE_BARCELONA)
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return

	# A 400-point looping centerline and its matching bank profile.
	var points: Array = scene.get("road_points")
	assert_int(points.size()).is_equal(BarcelonaRxLayout.TOTAL_POINTS)
	var bank: PackedFloat32Array = scene.get("bank_profile")
	assert_int(bank.size()).is_equal(BarcelonaRxLayout.TOTAL_POINTS)

	# The scene handed the centerline to RaceManager (the rival-roster hook).
	assert_int(RaceManager.rival_centerline.size()).is_equal(BarcelonaRxLayout.TOTAL_POINTS)

	# Exactly 8 checkpoints, indices 0..7, in travel order, one per stride slot;
	# index 7 is the start/finish line.
	var checkpoints: Array = scene.get_tree().get_nodes_in_group("checkpoints")
	assert_int(checkpoints.size()).is_equal(BarcelonaRxLayout.CHECKPOINT_COUNT)
	var by_index := {}
	for node in checkpoints:
		var cp := node as Checkpoint
		if cp != null:
			by_index[cp.index] = cp
	assert_int(by_index.size()).is_equal(BarcelonaRxLayout.CHECKPOINT_COUNT)
	for i in BarcelonaRxLayout.CHECKPOINT_COUNT:
		assert_bool(by_index.has(i)).is_true()
		var cp := by_index.get(i) as Checkpoint
		if cp == null:
			continue
		var expected: Vector3 = points[i * BarcelonaRxLayout.CP_STRIDE] + Vector3(0, 0.5, 0)
		assert_that(cp.global_position).is_equal_approx(expected, Vector3(0.01, 0.01, 0.01))
		assert_bool(cp.is_start_line).is_equal(i == BarcelonaRxLayout.START_LINE_INDEX)

	# The grid sits on checkpoint 0 with the car pointing down the road. The car
	# is a live VehiclePhysics, so after a few frames its Y has settled from the
	# spawn offset -- assert the XZ grid slot and "above the road", never the
	# settled ride height (a wall-clock/physics-timing assert).
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
	# SurfaceRegistry dirt grip; the def is a closed DIRT/GRAVEL circuit with the
	# layout's bank profile attached and no lane dividers.
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
				assert_int(def.tier).is_equal(RoadDef.Tier.DIRT)
				assert_int(def.surface).is_equal(RoadDef.Surface.GRAVEL)
				assert_float(def.width).is_equal_approx(BarcelonaRxLayout.WIDTH, 0.001)
				assert_int(def.points.size()).is_equal(BarcelonaRxLayout.TOTAL_POINTS)
				assert_bool(def.show_lane_dividers).is_false()
				assert_int(def.bank_angles.size()).is_equal(BarcelonaRxLayout.TOTAL_POINTS)
				assert_bool(def.has_surface_profile()).is_true()
				assert_that(def.point_surfaces).is_equal(BarcelonaRxLayout.build_surface_profile())
		assert_float(network.nearest_road_distance(points[0])).is_less(8.0)
		assert_bool(network.is_on_road(points[0])).is_true()
		assert_that(MapRoads.resolve_road_source(scene)).is_same(network)

	# RaceUI reverse-resolves the registry id from the scene path, so best-lap
	# records bucket under ("barcelona_rx", class) with no extra plumbing.
	var hud := scene.get_node_or_null("HUD")
	assert_that(hud).is_not_null()
	if hud != null:
		assert_that(hud.call("_resolve_track_id")).is_equal("barcelona_rx")

# --- P1 wiring (the scene's Dressing child) --------------------------------

## P3 integration check for the dressing WIRING. The builder's own contract is
## unit-covered by `test_barcelona_rx_dressing.gd`; this asserts only what the
## SCENE must do: the `Dressing` child is an `RxDressing` that `barcelona_rx.gd`
## configured with the same centerline + bank profile the road mesh uses and then
## built. Everything is read back through the query API, so it fails loudly if
## the scene loses the node, the script stops calling `configure()`/`build()`, or
## a GLB stops resolving at scene-build time.
func test_scene_dressing_is_wired_and_populated() -> void:
	var runner := scene_runner(SCENE_BARCELONA)
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return

	var dressing := scene.get_node_or_null("Dressing") as RxDressing
	assert_that(dressing).is_not_null()
	if dressing == null:
		return

	# Most diagnostic first: build() actually ran in the scene.
	assert_bool(dressing.is_built()).is_true()
	# Nothing was dropped: every referenced GLB resolved.
	assert_bool(dressing.dropped_kinds().is_empty()).is_true()
	for kind: String in [
			RxDressing.KIND_BARRIER, RxDressing.KIND_GANTRY,
			RxDressing.KIND_CONE, RxDressing.KIND_FLAG]:
		var mesh := dressing.prop_mesh(kind)
		assert_object(mesh).is_not_null()
		if mesh != null:
			assert_int(mesh.get_surface_count()).is_greater(0)

	# Barrier line, S/F gantry + paint, apex cones, one start flag.
	assert_that(dressing.barrier_transforms().size()).is_greater_equal(1)
	assert_int(dressing.barrier_transforms().size()) \
		.is_equal(dressing.count_of(RxDressing.KIND_BARRIER))
	assert_bool(dressing.gantry_ok()).is_true()
	assert_that(dressing.gantry_span()).is_greater_equal(BarcelonaRxLayout.WIDTH)
	assert_bool(dressing.checker_ok()).is_true()
	assert_that(dressing.cone_transforms().size()).is_greater(0)
	assert_int(dressing.cone_transforms().size()) \
		.is_equal(dressing.count_of(RxDressing.KIND_CONE))
	assert_int(dressing.flag_transforms().size()).is_equal(1)

	# Road-corridor gate, read through the scene's OWN RoadNetwork: every
	# ground-bound item (barriers + flag) sits outside the carriageway
	# (> W/2 from the centerline). The gantry and paint sit on/over the road by
	# design and the cones sit ON the dirt, so all three are excluded.
	var network := scene.get_node_or_null("RoadNetwork") as RoadNetwork
	assert_that(network).is_not_null()
	if network == null:
		return
	var half := BarcelonaRxLayout.WIDTH * 0.5
	var min_distance := INF
	var violations := 0
	for item: Transform3D in dressing.ground_transforms():
		var road_distance := network.nearest_road_distance(item.origin)
		min_distance = minf(min_distance, road_distance)
		if road_distance <= half:
			violations += 1
	print("[p3] dressing barriers=%d gantry_span=%.2f cones=%d min_road_distance=%.3f"
		% [dressing.count_of(RxDressing.KIND_BARRIER), dressing.gantry_span(),
			dressing.count_of(RxDressing.KIND_CONE), min_distance])
	assert_int(violations).is_equal(0)

# --- registry --------------------------------------------------------------

func test_registry_entry_is_complete() -> void:
	assert_bool(TrackRegistry.has_track("barcelona_rx")).is_true()
	var data := TrackRegistry.get_track("barcelona_rx")
	assert_that(data.get("display_name")).is_equal("Barcelona Rallycross")
	assert_that(data.get("scene_path")).is_equal(SCENE_BARCELONA)
	assert_int(int(data.get("laps_default"))).is_equal(3)
	assert_that(data.get("difficulty")).is_equal("D")
	assert_that(data.get("circuit_type")).is_equal("DIRT RX")
	assert_file(TrackRegistry.get_scene_path("barcelona_rx")).exists()
	assert_that(load(TrackRegistry.get_scene_path("barcelona_rx")) as PackedScene).is_not_null()

# --- checkpoint / lap contract --------------------------------------------

func test_checkpoint_progression_ticks_exactly_one_lap() -> void:
	var runner := scene_runner(SCENE_BARCELONA)
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return

	var car := _new_stub_car()
	var cps := _ordered_checkpoints()
	assert_int(cps.size()).is_equal(BarcelonaRxLayout.CHECKPOINT_COUNT)
	if cps.size() != BarcelonaRxLayout.CHECKPOINT_COUNT:
		return
	var counter := _new_lap_counter(3)

	# Feed passes 0 -> 7 in order: a lap ticks ONLY at the last checkpoint.
	var laps: Array = []
	counter.lap_completed.connect(
		func(_v: VehiclePhysics, lap_num: int, _time: float) -> void: laps.append(lap_num))
	for i in BarcelonaRxLayout.CHECKPOINT_COUNT:
		counter.update(car, cps[i])
		if i < BarcelonaRxLayout.START_LINE_INDEX:
			assert_int(laps.size()).is_equal(0)
	assert_int(laps.size()).is_equal(1)
	assert_int(counter.get_current_lap()).is_equal(2)

	# Out-of-order: crossing the S/F line (7) before the grid (0) completes no
	# lap, and the sticky progression then cannot complete one either.
	var counter2 := _new_lap_counter(3)
	var laps2: Array = []
	counter2.lap_completed.connect(
		func(_v: VehiclePhysics, lap_num: int, _time: float) -> void: laps2.append(lap_num))
	counter2.update(car, cps[BarcelonaRxLayout.START_LINE_INDEX])
	assert_int(laps2.size()).is_equal(0)
	assert_int(counter2.get_current_lap()).is_equal(1)
	for i in BarcelonaRxLayout.START_LINE_INDEX:
		counter2.update(car, cps[i])
	assert_int(laps2.size()).is_equal(0)

# --- mixed surface grip ----------------------------------------------------

## Distance (m of arc) kept clear of a surface change when sampling: the
## per-segment profile honours a boundary to within half a point spacing.
const BOUNDARY_GUARD_M := 3.0

func _near_boundary(s: float) -> bool:
	for r in BarcelonaRxLayout.DIRT_SECTIONS:
		for edge: float in [r.x, r.y]:
			var d := absf(fposmod(s - edge + BarcelonaRxLayout.TARGET_PERIMETER * 0.5,
				BarcelonaRxLayout.TARGET_PERIMETER) - BarcelonaRxLayout.TARGET_PERIMETER * 0.5)
			if d < BOUNDARY_GUARD_M:
				return true
	return false

## The scene's real classifier (the one VehiclePhysics builds) against the
## layout's chainage table, every 5 m round the lap and at two lateral offsets
## inside the carriageway: dirt chainages report GRAVEL dirt grip, asphalt
## chainages ASPHALT grip. One source of truth, checked end to end.
func test_surface_grip_follows_the_dirt_sections_round_the_lap() -> void:
	var runner := scene_runner(SCENE_BARCELONA)
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return
	var classifier := SurfaceRegistry.build_classifier(
		SurfaceRegistry.default_road_tier_provider(scene), Callable())
	var dirt_samples := 0
	var asphalt_samples := 0
	var mismatches := 0
	var s := 0.0
	while s < BarcelonaRxLayout.TARGET_PERIMETER:
		if not _near_boundary(s):
			var frame := BarcelonaRxLayout.frame_at_arc(s)
			var expected := BarcelonaRxLayout.surface_key_at_arc(s)
			for lateral: float in [0.0, -4.5, 4.5]:
				var report: Dictionary = classifier.call(_edge_world(frame, lateral))
				if String(report.get("surface_key")) != expected:
					mismatches += 1
			if expected == SurfaceRegistry.GRAVEL:
				dirt_samples += 1
			else:
				asphalt_samples += 1
		s += 5.0
	assert_int(mismatches).is_equal(0)
	# ~40 % / 60 % of the lap, sampled.
	assert_int(dirt_samples).is_greater(80)
	assert_int(asphalt_samples).is_greater(120)

## Spot values: the grid and the S/F line are asphalt (1.0 / 1.0), the jump-2
## run and the T2 berm are dirt at the GRAVEL contract (0.85 / 0.80), and the
## verge beside BOTH surfaces is loose GRAVEL until the off-road grass.
func test_grip_values_at_landmarks_and_on_the_verge() -> void:
	var runner := scene_runner(SCENE_BARCELONA)
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return
	var classifier := SurfaceRegistry.build_classifier(
		SurfaceRegistry.default_road_tier_provider(scene), Callable())
	var grid: Dictionary = classifier.call(BarcelonaRxLayout.point_at_arc(0.0))
	assert_that(grid.get("surface_key")).is_equal(SurfaceRegistry.ASPHALT)
	assert_float(float(grid.get("lateral"))).is_equal_approx(1.0, 0.001)
	assert_float(float(grid.get("longitudinal"))).is_equal_approx(1.0, 0.001)
	var sf: Dictionary = classifier.call(BarcelonaRxLayout.point_at_arc(BarcelonaRxLayout.start_line_arc()))
	assert_that(sf.get("surface_key")).is_equal(SurfaceRegistry.ASPHALT)
	for arc: float in [120.0, BarcelonaRxLayout.corner_apex_arc(2)]:
		var dirt: Dictionary = classifier.call(BarcelonaRxLayout.point_at_arc(arc))
		assert_that(dirt.get("surface_key")).is_equal(SurfaceRegistry.GRAVEL)
		assert_float(float(dirt.get("lateral"))).is_equal_approx(0.85, 0.001)
		assert_float(float(dirt.get("longitudinal"))).is_equal_approx(0.80, 0.001)
	# Verge: 1.5 m past the edge is loose on both surfaces; 25 m out is grass.
	for arc: float in [300.0, 800.0]:
		var frame := BarcelonaRxLayout.frame_at_arc(arc)
		var verge: Dictionary = classifier.call(_edge_world(frame, -(_half_width() + 1.5)))
		assert_that(verge.get("surface_key")).is_equal(SurfaceRegistry.GRAVEL)
		var far: Dictionary = classifier.call(_edge_world(frame, -(_half_width() + 25.0)))
		assert_that(far.get("surface_key")).is_equal(SurfaceRegistry.GRASS)

# --- mixed surface look ----------------------------------------------------

## The road renders through the mixed asphalt/dirt shader (not one StandardMaterial
## slab): its dirt colour is the dark matte DIRT profile (DIRT_ALBEDO /
## DIRT_ROUGHNESS, docs/plans/barcelona_dirt_surface_plan.md), its asphalt the
## shared ASPHALT albedo, and the mesh's per-row loose weight is 1 on every dirt
## chainage and 0 on clean asphalt far from a surface change.
func test_scene_road_renders_the_mixed_surface_from_the_chainage_table() -> void:
	var runner := scene_runner(SCENE_BARCELONA)
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return
	var network := scene.get_node_or_null("RoadNetwork") as RoadNetwork
	assert_that(network).is_not_null()
	if network == null:
		return
	var surface := _road_surface(network)
	assert_that(surface).is_not_null()
	if surface == null:
		return
	var mat := surface.material_override as ShaderMaterial
	assert_that(mat).is_not_null()
	if mat == null:
		return
	assert_that(mat.shader).is_same(TrackBuilder.MIXED_SURFACE_SHADER)
	var dirt: Color = mat.get_shader_parameter("dirt_color")
	assert_float(dirt.r).is_equal_approx(0.34, 0.01)
	assert_float(dirt.g).is_equal_approx(0.24, 0.01)
	assert_float(dirt.b).is_equal_approx(0.15, 0.01)
	assert_float(float(mat.get_shader_parameter("dirt_roughness"))).is_equal_approx(1.0, 0.01)
	var asphalt: Color = mat.get_shader_parameter("asphalt_color")
	assert_float(asphalt.r).is_less(0.2)
	var colors := (surface.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
	assert_int(colors.size()).is_equal(BarcelonaRxLayout.TOTAL_POINTS * 2)
	var bad := 0
	for i in BarcelonaRxLayout.TOTAL_POINTS:
		var arc := (float(i) + 0.5) * BarcelonaRxLayout.spacing()
		var w := colors[i * 2].r
		if BarcelonaRxLayout.is_loose_at_arc(arc):
			if w < 0.999:
				bad += 1
		elif not _near_boundary(arc) and fposmod(arc - 525.0, BarcelonaRxLayout.TARGET_PERIMETER) > TrackBuilder.LOOSE_SPILL_M + 3.0 \
				and fposmod(72.0 - arc, BarcelonaRxLayout.TARGET_PERIMETER) > TrackBuilder.LOOSE_LEAD_M + 3.0:
			if w > 0.001:
				bad += 1
	assert_int(bad).is_equal(0)
	# The exit spill: dirt dragged onto the asphalt just past the section end.
	var exit_i := int(ceilf(525.0 / BarcelonaRxLayout.spacing()))
	assert_float(colors[(exit_i + 1) * 2].r).is_greater(0.3)

## The scene's rendered road surface: the sole `TrackBuilder` child of the
## scene's `RoadNetwork` has a child named `RoadSurface`.
func _road_surface(network: RoadNetwork) -> MeshInstance3D:
	for child in network.get_children():
		var builder := child as TrackBuilder
		if builder == null:
			continue
		var surface := builder.get_node_or_null("RoadSurface") as MeshInstance3D
		if surface != null:
			return surface
	return null

# --- P2 ground + foliage ---------------------------------------------------

func test_ground_and_foliage_are_bank_aware() -> void:
	var build_start := Time.get_ticks_msec()
	var runner := scene_runner(SCENE_BARCELONA)
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

	# Under every checkpoint the baked terrain is recessed below the dirt.
	var worst_recess := INF
	for idx in BarcelonaRxLayout.checkpoint_indices():
		var center: Vector3 = points[idx]
		var ground: float = terrain.data.get_height(center)
		assert_float(ground).is_less_equal(center.y - 0.05)
		worst_recess = minf(worst_recess, center.y - ground)
	print("[p2] worst checkpoint recess below dirt = %.3f m (min allowed 0.05)" % worst_recess)

	# Both sides blend at a bermed corner and at a flat one.
	var half := _half_width()
	var plain_reach := half + BarcelonaRxLayout.BLEND_RUN + 8.0

	# Bermed corner T2: the outfield (left / cross-negative) edge is the HIGH one
	# and the inner (right) edge rides at ROAD_BASE_Y by construction.
	var berm_frame := _apex_frame(2)
	var berm_bank := float(berm_frame["bank"])
	assert_float(berm_bank).is_greater(0.1)
	var inner_y := _surface_y_at(berm_frame, half)
	assert_float(inner_y).is_equal_approx(BarcelonaRxLayout.ROAD_BASE_Y, 0.01)
	var inner_ground: float = terrain.data.get_height(_edge_world(berm_frame, half))
	assert_float(inner_ground).is_less_equal(inner_y - 0.05)
	var outer_y := _surface_y_at(berm_frame, -half)
	var outer_ground: float = terrain.data.get_height(_edge_world(berm_frame, -half))
	assert_float(absf(outer_ground - (outer_y - EDGE_DROP))).is_less(0.3)
	for side: float in [-1.0, 1.0]:
		var plain_ground: float = terrain.data.get_height(_edge_world(berm_frame, side * plain_reach))
		assert_float(absf(plain_ground - BarcelonaRxLayout.PLAIN_Y)).is_less(0.06)
	print("[p2] berm cp2 bank=%.4f rad inner_y=%.3f inner_g=%.3f outer_y=%.3f outer_g=%.3f"
		% [berm_bank, inner_y, inner_ground, outer_y, outer_ground])

	# Flat corner T3 (no berm): both edges sit at ROAD_BASE_Y, both shoulders drop
	# below the road, and the plain holds on both sides.
	var flat_frame := _apex_frame(3)
	assert_float(float(flat_frame["bank"])).is_equal_approx(0.0, 1.0e-9)
	for side: float in [-1.0, 1.0]:
		var edge_y := _surface_y_at(flat_frame, side * half)
		assert_float(edge_y).is_equal_approx(BarcelonaRxLayout.ROAD_BASE_Y, 0.01)
		var edge_ground: float = terrain.data.get_height(_edge_world(flat_frame, side * half))
		assert_float(edge_ground).is_less_equal(edge_y - 0.04)
		var flat_plain: float = terrain.data.get_height(_edge_world(flat_frame, side * plain_reach))
		assert_float(absf(flat_plain - BarcelonaRxLayout.PLAIN_Y)).is_less(0.06)

	# Foliage exists and every instance clears the road corridor (half width 6 +
	# PropScatterer.ROAD_CLEARANCE_MARGIN 3 = 9 m; the same predicate Foliage
	# itself rejects with). The placement is a fixed RNG seed, so this is
	# deterministic rather than wall-clock flaky.
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
	assert_float(min_distance).is_greater_equal(BarcelonaRxLayout.WIDTH * 0.5 + PropScatterer.ROAD_CLEARANCE_MARGIN)

func test_ground_bake_is_deterministic() -> void:
	var first_runner := scene_runner(SCENE_BARCELONA)
	await first_runner.simulate_frames(2)
	var second_runner := scene_runner(SCENE_BARCELONA)
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
	var points := BarcelonaRxLayout.build_centerline()
	for i in range(0, points.size(), 17):
		out.append(points[i])
		out.append(points[i] + Vector3(30.0, 0.0, 0.0))
		out.append(points[i] + Vector3(0.0, 0.0, 30.0))
	# Far corners of the pane must all read the plain.
	out.append(Vector3(-250.0, 0.0, -250.0))
	out.append(Vector3(250.0, 0.0, 250.0))
	return out
