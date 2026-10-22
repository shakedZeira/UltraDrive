extends Node3D

## Circuit de Barcelona-Catalunya — Rallycross (GT7 track build #2): a ~1,133 m
## closed DIRT rallycross circuit with two jumps, two sine-eased berms and a
## tight right-hand hairpin. Mirrors `northern_isle.gd`'s orchestration
## (ground bake -> road -> checkpoints -> foliage -> dressing -> colliders ->
## spawn) but the geometry comes from `BarcelonaRxLayout` and the road is a
## CLOSED DIRT/GRAVEL RoadDef carrying an explicit per-point bank profile.
##
## Unlike `mountain_pass.tscn` this scene owns a `RoadNetwork` child, so the
## minimap (`MapRoads.resolve_road_source`), the pause map and the
## `SurfaceRegistry` dirt grip all resolve the circuit from the `"road_network"`
## group with no extra plumbing.
##
## Geometry source of truth: `scripts/track/barcelona_rx_layout.gd`. The
## centerline (Y including the jump crests) and the bank profile are built ONCE
## in `_ready` and exposed as members for tests. `_generate_road_points()` is a
## pure off-tree probe for `TrackLayoutSource` (the race menu's layout preview),
## exactly like `northern_isle.gd` has no such probe yet but
## `TrackLayoutSource._probe_scene` documents the convention.

## Terrain recess under the dirt. The washbed floor sits this far BELOW the road
## surface so the two can never z-fight (same role as build #1's 0.30).
const WASHBED_DEPTH := 0.30

## The visible lip the ground drops over at a road edge. Feeding this into the
## blend (instead of the washbed depth) is what stops a texel that straddles the
## road edge from interpolating ABOVE the dirt: the modelled surface at the edge
## is road_y - EDGE_DROP, always below the road.
const EDGE_DROP := 0.10

## Heightmap spans TERRAIN_SPAN metres at 1 m/px (512 x 512 image, region size
## 256). import_images() snaps its position to a region anchor, so the pane
## starts exactly on one: -256 is a multiple of 256 and covers the whole
## circuit footprint (about 375 x 320 m) plus the blend runs with margin.
const TERRAIN_SPAN := 512.0
const TERRAIN_HALF := 256.0

## Coarse routing hint field spacing (m). Only routes a texel to the exact
## centerline scan or the plain; never a result by itself.
const FIELD_STEP := 8.0

## Coarse-field distance error absorbed before a texel is allowed to take the
## plain early-out (same role as build #1's EXACT_SCAN_MARGIN).
const EXACT_SCAN_MARGIN := 12.0

## How many centerline indices either side of a texel's coarse hint index the
## exact per-texel scan may touch. Spacing is ~2.83 m, so +/-10 indices spans
## ~57 m of arc -- far more than the 8 m grid step can shift the nearest index.
const FIELD_WINDOW := 10

## Dry, olive rallycross grass/dirt ground tint (build #1's oval uses a greener
## 0.30/0.36/0.27; a dirt circuit bakes a drier, more yellow surface).
const GRASS_COLOR := Color(0.34, 0.33, 0.20)

## Loose verge beside the DIRT section (`BarcelonaRxLayout.DIRT_SECTIONS`): the
## dirt that is thrown wide and graded off the racing surface. Fully loose out to
## LOOSE_VERGE_FULL m past the road edge, fading to grass by LOOSE_VERGE_FADE.
const LOOSE_VERGE_COLOR := Color(0.42, 0.33, 0.22)
const LOOSE_VERGE_FULL := 4.0
const LOOSE_VERGE_FADE := 11.0
## Narrow gravel run-off shoulder beside the ASPHALT sections -- the strip
## SurfaceRegistry already reports as GRAVEL (road edge + ROAD_EDGE_MARGIN).
const RUNOFF_COLOR := Color(0.50, 0.45, 0.36)
const RUNOFF_FULL := 2.0
const RUNOFF_FADE := 4.5
## Arc distance (m) over which the verge colour blends at a surface change, so
## the verge never steps from grass to dirt at one texel row.
const VERGE_ARC_BLEND := 12.0

## Bounded re-rolls of the foliage seed looking for a placement whose every
## instance clears the road corridor. `Foliage`'s rejection sampling can leave a
## stray instance inside the corridor (the same unchecked last-sample fallback
## build #1 works around), so rather than loosen this scene's corridor contract
## we re-run `Foliage.generate()` on the next seed until placement is clean.
const FOLIAGE_SEED_ATTEMPTS := 8

## Centerline points used to build the road (exposed for tests, like
## `mountain_pass.road_points`).
var road_points: Array[Vector3] = []

## Signed bank angle (radians) per centerline point, in TrackBuilder._frame's
## sign space (POSITIVE = right turn). Exposed for tests.
var bank_profile: PackedFloat32Array = PackedFloat32Array()

## The road network this scene owns, resolved once in `_ready`.
var road_network: RoadNetwork = null

## Wall-clock milliseconds the last bank-aware ground bake took (diagnostic for
## the gate; never asserted -- the `test_perf_gate` lesson).
var ground_bake_ms: int = 0

## Coarse hint field: `_hint_index[i]` is the nearest centerline POINT index at
## node i, `_hint_dist[i]` the XZ distance to the nearest segment. Populated by
## `_build_hint_field()` and consumed by `_terrain_height()`.
var _hint_index := PackedInt32Array()
var _hint_dist := PackedFloat32Array()
var _hint_stride := 0

## Side outputs of the last `_terrain_height` call (no allocation in the bake
## loop): |lateral offset| from the centerline (INF on the plain early-out) and
## the public arc of the nearest centerline position. Read by `_verge_color`.
var _last_abs_s := INF
var _last_arc := 0.0

## Per-point loose weight along the loop (1 on the DIRT section, blended over
## VERGE_ARC_BLEND at each change), built once per bake for the verge colour.
var _verge_loose := PackedFloat32Array()

## Export gates. Defaults keep the standalone scene behaving as the tests
## expect; a future lean `barcelona_rx_zone.tscn` (the `mountain_pass_zone`
## pattern) can turn ground/foliage/spawn off because the open world owns them.
@export var build_own_ground: bool = true
@export var build_foliage: bool = true
## Builds the scene's `Dressing` child (`RxDressing`: S/F gantry + checker paint,
## the red barrier line, apex cones and the optional checkered flags). A future
## lean zone scene can turn it off alongside ground/foliage if a zone owns the
## dressing instead.
@export var build_dressing: bool = true

## Builds the PHYSICAL barrier colliders (the red barrier line around the three
## barriered corners) as oriented box chains.
##
## The barrier MESHES are visual only: `RxDressing` builds no collision at all
## and `TrackBuilder` adds rail collision only when a junction gap list is
## non-empty (a standalone circuit has none), so before this a car drove
## straight through the barrier off the dirt. Independent of `build_dressing` so
## a lean zone scene that dresses elsewhere still gets solid barriers.
@export var build_barrier_colliders: bool = true

@export var reposition_player: bool = true


func _ready() -> void:
	road_points = BarcelonaRxLayout.build_centerline()
	bank_profile = BarcelonaRxLayout.build_bank_profile()

	var terrain: Terrain3D = null
	if build_own_ground:
		terrain = _build_ground()

	road_network = _resolve_road_network()
	_build_road(road_network)

	_build_checkpoints()

	if build_foliage:
		_build_foliage(terrain)

	if build_dressing:
		_build_dressing(terrain)

	if build_barrier_colliders:
		_build_barrier_colliders(self, _make_dressing_height_provider(terrain))

	# Harmless today; enables rival rosters later (RaceManager/RivalDriver read
	# this centerline when a roster is configured).
	RaceManager.set_rival_centerline(road_points)

	if reposition_player:
		_reposition_player_to_start()


## Pure, side-effect-free centerline generation for `TrackLayoutSource`'s
## documented OFF-TREE probe: `instantiate()` WITHOUT entering the tree (so no
## race is consumed, no car registered and no terrain baked), then call this.
## Returns the same `Array[Vector3]` `_ready` drives from.
func _generate_road_points() -> Array[Vector3]:
	return BarcelonaRxLayout.build_centerline()


## The scene ships a `RoadNetwork` child; create one if a lean variant omits it.
func _resolve_road_network() -> RoadNetwork:
	var network := get_node_or_null("RoadNetwork") as RoadNetwork
	if network == null:
		network = RoadNetwork.new()
		network.name = "RoadNetwork"
		add_child(network)
	return network


## Builds the circuit ONCE: a closed DIRT/GRAVEL def (loose dirt topping, no
## rails) with the layout's bank profile attached and the lane dividers dropped
## (a rallycross circuit has no dashed lane paint).
func _build_road(network: RoadNetwork) -> void:
	var def := RoadDef.make(
		RoadDef.Tier.DIRT,
		road_points,
		"barcelona_rx-dirt",
		true,
		BarcelonaRxLayout.WIDTH,
		RoadDef.Surface.GRAVEL,
		RoadDef.RailSide.NONE)
	def.bank_angles = bank_profile
	def.show_lane_dividers = false
	# Mixed surface: asphalt with one loose section, from the layout's
	# DIRT_SECTIONS table. The tier stays DIRT (its GRAVEL default is still what
	# the verge reports); the per-segment profile decides the carriageway's grip
	# and TrackBuilder's mixed asphalt/dirt material.
	def.point_surfaces = BarcelonaRxLayout.build_surface_profile()
	network.add_road_def(def)


## 8 checkpoints, one per `checkpoint_indices()` slot, in travel order. The
## 16 x 8 x 16 box spans the road width so a back-row rival cannot miss cp0
## (`RaceManager.RIVAL_GRID_ANCHOR_AHEAD` note in test_race_loop). The
## `"checkpoints"` group is set by `checkpoint.gd` itself.
func _build_checkpoints() -> void:
	var indices := BarcelonaRxLayout.checkpoint_indices()
	for i in indices.size():
		var cp := Checkpoint.new()
		cp.index = i
		cp.position = road_points[indices[i]] + Vector3(0, 0.5, 0)
		cp.is_start_line = i == BarcelonaRxLayout.START_LINE_INDEX
		var shape := BoxShape3D.new()
		shape.size = Vector3(16.0, 8.0, 16.0)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		cp.add_child(collision)
		cp.body_entered.connect(_on_checkpoint_body_entered.bind(i))
		add_child(cp)


## Scatter vegetation over the whole circuit. `inner_clear_radius = 0` on
## purpose: a radial inner-clear would leave trees inside the loop, so the road
## rejection (`road_network` must be set BEFORE add_child, because
## `Foliage._ready` generates immediately) does all the clearing.
##
## `Foliage`'s rejection sampling can still leave a stray instance inside the
## corridor (see FOLIAGE_SEED_ATTEMPTS), so after the first generate this bumps
## the seed and regenerates -- deterministically -- until every instance clears.
## The corridor floor for a 12 m road is `W/2 + PropScatterer.ROAD_CLEARANCE_MARGIN`
## = 9 m, applied by `is_clear_of_road` itself.
func _build_foliage(terrain: Terrain3D) -> void:
	var foliage := Foliage.new()
	foliage.name = "Foliage"
	foliage.radius = 220.0
	foliage.inner_clear_radius = 0.0
	if terrain != null:
		foliage.ground_height_provider = _make_ground_height_provider(terrain)
	foliage.road_network = road_network
	var base_seed := foliage.seed
	add_child(foliage)
	if road_network == null:
		return
	for attempt in FOLIAGE_SEED_ATTEMPTS:
		if attempt > 0:
			foliage.seed = base_seed + attempt
			foliage.generate()
		if _foliage_clears_road(foliage):
			return


## True when every placement in `foliage` sits outside the road corridor
## (`PropScatterer.is_clear_of_road` is exactly the predicate `Foliage` rejects
## with). Requires `foliage` to be in the tree for world-space conversion.
func _foliage_clears_road(foliage: Foliage) -> bool:
	for local in foliage.get_instance_positions():
		if not PropScatterer.is_clear_of_road(foliage.to_global(local), road_network):
			return false
	return true


## Keeps foliage grounded on the bank-aware terrain (the build #1 pattern).
func _make_ground_height_provider(terrain: Terrain3D) -> Callable:
	return func ground_height_at(pos: Vector2) -> float:
		return terrain.data.get_height(Vector3(pos.x, 0.0, pos.y))


## Wires the scene's `Dressing` child (`RxDressing`). Everything is placed from
## the layout's own frame math against the SAME centerline + bank profile the
## road mesh consumes, so the dressing can never disagree with the dirt about
## where the road edge is.
##
## `terrain_height` is a `Callable(Vector3) -> float` -- NOT the
## `Callable(Vector2)` provider `Foliage` takes. It is optional: `RxDressing`
## falls back to its road-edge frame math on an empty callable, so a scene with
## `build_own_ground = false` still dresses correctly.
func _build_dressing(terrain: Terrain3D) -> void:
	var dressing := get_node_or_null("Dressing") as RxDressing
	if dressing == null:
		return
	dressing.configure(
		road_points,
		bank_profile,
		BarcelonaRxLayout.WIDTH,
		_make_dressing_height_provider(terrain))
	dressing.build()


## Sits the dressing props on the baked ground (empty when no terrain is built).
func _make_dressing_height_provider(terrain: Terrain3D) -> Callable:
	if terrain == null:
		return Callable()
	return func dressing_height_at(pos: Vector3) -> float:
		return terrain.data.get_height(pos)


## --- physical barrier colliders (the red barrier line) -----------------------

## Extra length stapled onto every chain box so neighbouring boxes overlap and
## no seam can open at a curve.
const BARRIER_BOX_OVERLAP := 0.35

## How far every chain box reaches BELOW its base line (m), burying it under the
## shoulder/berm so no gap can open beneath it (the ground lip here sits at most
## EDGE_DROP below the road edge).
const BARRIER_DROP_BELOW := 1.0

## Safety margin a chain box may stand above the VISUAL it guards (m). The chain
## is a physics proxy for a mesh, not a separate taller wall: it must cover the
## visual and rise no more, or a car meets solid air above a barrier it can
## plainly see under (an "invisible wall", worst when cutting a corner).
const BARRIER_TOP_MARGIN := 0.1

## Box top = base + rise (m): the top of the red barrier visual, plus
## `BARRIER_TOP_MARGIN`. `RxDressing.RED_BARRIER_VISUAL_TOP` is named there
## (where the scale lives) and held honest by the barrier gate.
const RED_BARRIER_RISE_ABOVE := RxDressing.RED_BARRIER_VISUAL_TOP + BARRIER_TOP_MARGIN

## Box cross-section along the road (m): thicker than the visual it guards so a
## fast car can never thread the chain.
const RED_BARRIER_COLLIDER_THICKNESS := 0.5

## Friction of the barrier boxes (matches `TrackBuilder`'s rail collision so a
## car scraping a barrier behaves the same wherever it touches one).
const BARRIER_FRICTION := 0.2


## Builds the barrier chain under a `BarrierColliders` child of `parent`.
## `parent` is a parameter (not `self`) purely so a test can host the colliders
## without instantiating the scene; `_ready` passes `self`. Idempotent: a
## previous build is removed first. Returns the number of collision boxes.
##
## BOX CHAIN, NOT TRIMESH: the red barrier GLB is a dense kit mesh instanced
## through a MultiMesh, so a per-instance trimesh would be expensive; one
## oriented box per layout step is cheap (one shared BoxShape3D) and solid.
##
## Only the three barriered corners carry a line, so the chain spans
## `BarcelonaRxLayout.barrier_arc_ranges()` (T1, T2, T6), NOT the whole loop.
func _build_barrier_colliders(parent: Node3D, terrain_height: Callable) -> int:
	var existing := parent.get_node_or_null("BarrierColliders") as Node3D
	if existing != null:
		parent.remove_child(existing)
		existing.free()

	var root := Node3D.new()
	root.name = "BarrierColliders"
	parent.add_child(root)

	var half := BarcelonaRxLayout.WIDTH * 0.5
	# Outfield: the barrier sits on the outside of each barriered corner. A
	# right-hand turn's outfield is the LEFT of travel, so the offset is
	# OUTFIELD_SIDE * (W/2 + BARRIER_OFFSET) = -(6 + 1.6) = -7.6 m.
	var offset := BarcelonaRxLayout.OUTFIELD_SIDE * (half + RxDressing.BARRIER_OFFSET)
	return _add_barrier_arcs_chain(root, "RedBarrierCollision", offset,
		RED_BARRIER_COLLIDER_THICKNESS, RED_BARRIER_RISE_ABOVE, terrain_height)


## One oriented box per `BarcelonaRxLayout.spacing()` step across every barrier
## arc range, chunked into `CP_STRIDE`-box StaticBody3Ds so each body's
## broadphase AABB hugs its own stretch of the line instead of all 59 boxes.
## Returns the number of boxes added.
##
## Layer/mask 1 is what every body in the game already uses -- `VehiclePhysics`
## is a plain RigidBody3D on the defaults -- so the chain collides with cars
## without any layer plumbing.
func _add_barrier_arcs_chain(parent: Node3D, prefix: String, offset: float, \
		thickness: float, rise_above: float, terrain_height: Callable) -> int:
	var step := BarcelonaRxLayout.spacing()
	var chunk := BarcelonaRxLayout.CP_STRIDE
	var height := BARRIER_DROP_BELOW + rise_above
	var shape := BoxShape3D.new()
	shape.size = Vector3(thickness, height, step + BARRIER_BOX_OVERLAP)
	var material := PhysicsMaterial.new()
	material.friction = BARRIER_FRICTION

	# Collect every box's mid-point + yaw first so bodies can be chunked evenly
	# across arcs (a per-arc body would leave a ragged final chunk).
	var placements: Array[Dictionary] = []
	for r in BarcelonaRxLayout.barrier_arc_ranges():
		var from: float = r.x
		var to: float = r.y
		var count := int(ceil((to - from) / step))
		for k in count:
			var arc_a := from + float(k) * step
			var arc_b := minf(arc_a + step, to)
			var a := _barrier_line_point(arc_a, offset, terrain_height)
			var b := _barrier_line_point(arc_b, offset, terrain_height)
			placements.append({
				"mid": (a + b) * 0.5,
				"yaw": atan2(b.x - a.x, b.z - a.z),
			})

	var added := 0
	var body: StaticBody3D = null
	for i in placements.size():
		if i % chunk == 0:
			body = StaticBody3D.new()
			body.name = "%s%d" % [prefix, i / chunk]
			body.collision_layer = 1
			body.collision_mask = 1
			body.physics_material_override = material
			parent.add_child(body)
		var mid: Vector3 = placements[i]["mid"]
		var yaw: float = placements[i]["yaw"]
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = Vector3(mid.x, mid.y - BARRIER_DROP_BELOW + height * 0.5, mid.z)
		# Local +Z along the segment so the box's long axis runs with the road
		# (the same convention the road mesh/rails use).
		collision.rotation = Vector3(0.0, yaw, 0.0)
		body.add_child(collision)
		added += 1
	return added


## Base point of a chain box at `arc` on the cross-section at `offset`: the
## exact lateral line the visuals are placed from (`center + cross * offset`),
## with Y taken from the baked ground when a terrain provider was configured and
## the frame's own cross-section height otherwise, so a lean scene with no
## ground still gets a coherent wall.
func _barrier_line_point(arc: float, offset: float, terrain_height: Callable) -> Vector3:
	var frame := BarcelonaRxLayout.frame_at_arc(arc)
	var center: Vector3 = frame["center"]
	var cross: Vector3 = frame["cross"]
	var p := center + cross * offset
	if terrain_height.is_valid():
		var probe := Vector3(p.x, 0.0, p.z)
		var ground: float = terrain_height.call(probe)
		p.y = ground
	return p


## Builds the bank-aware terrain under the dirt. The node keeps the historical
## "GrassGround" name other code/tests look up. Deterministic: no RNG anywhere.
func _build_ground() -> Terrain3D:
	var bake_start := Time.get_ticks_msec()
	var terrain := Terrain3D.new()
	terrain.name = "GrassGround"
	add_child(terrain)
	terrain.region_size = Terrain3D.SIZE_256

	_build_hint_field()
	_build_verge_profile()

	var size := int(TERRAIN_SPAN)
	var height_img := Image.create_empty(size, size, false, Image.FORMAT_RF)
	var color_img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for iz in range(size):
		var wz := -TERRAIN_HALF + float(iz)
		for ix in range(size):
			var wx := -TERRAIN_HALF + float(ix)
			var elevation := _terrain_height(wx, wz)
			height_img.set_pixel(ix, iz, Color(elevation, 0.0, 0.0, 0.0))
			var shade := 0.82 + 0.36 * clampf((elevation + 1.0) / 7.0, 0.0, 1.0)
			color_img.set_pixel(ix, iz, Color(_verge_color(ix, iz) * shade, 0.5))

	terrain.data.import_images(
		[height_img, null, color_img],
		Vector3(-TERRAIN_HALF, 0, -TERRAIN_HALF),
		0.0, 1.0)
	terrain.material.show_checkered = false
	terrain.material.show_colormap = true
	terrain.collision_mode = 3  # FULL_GAME: ensure full track collision (not radius-limited)
	ground_bake_ms = Time.get_ticks_msec() - bake_start
	return terrain


## Coarse grid over the whole pane: each node stores the nearest centerline
## point index (the exact scan's window hint) and the XZ distance to the nearest
## segment (the plain early-out). Only a hint: the per-texel answer re-scans.
func _build_hint_field() -> void:
	_hint_stride = int(TERRAIN_SPAN / FIELD_STEP) + 1
	var count := _hint_stride * _hint_stride
	_hint_index.resize(count)
	_hint_dist.resize(count)
	for i in _hint_stride:
		var wz := -TERRAIN_HALF + float(i) * FIELD_STEP
		for j in _hint_stride:
			var wx := -TERRAIN_HALF + float(j) * FIELD_STEP
			var nearest := _nearest_centerline_full(wx, wz)
			_hint_index[i * _hint_stride + j] = int(nearest.x)
			_hint_dist[i * _hint_stride + j] = nearest.y


## Full centerline scan (only ever used on the ~4 k coarse nodes). Returns
## Vector2(nearest point index, XZ distance to the nearest segment).
func _nearest_centerline_full(wx: float, wz: float) -> Vector2:
	var n := road_points.size()
	var best_d2 := INF
	var best_idx := 0
	for j in n:
		var a: Vector3 = road_points[j]
		var b: Vector3 = road_points[(j + 1) % n]
		var abx := b.x - a.x
		var abz := b.z - a.z
		var len2 := abx * abx + abz * abz
		if len2 <= 0.0001:
			continue
		var t := clampf(((wx - a.x) * abx + (wz - a.z) * abz) / len2, 0.0, 1.0)
		var dx := wx - (a.x + abx * t)
		var dz := wz - (a.z + abz * t)
		var d2 := dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best_idx = j
	return Vector2(float(best_idx), sqrt(best_d2))


## Bilinearly samples the coarse hint-distance field.
func _hint_dist_at(wx: float, wz: float) -> float:
	var fx := (wx + TERRAIN_HALF) / FIELD_STEP
	var fz := (wz + TERRAIN_HALF) / FIELD_STEP
	var j0 := clampi(int(floorf(fx)), 0, _hint_stride - 1)
	var i0 := clampi(int(floorf(fz)), 0, _hint_stride - 1)
	var j1 := mini(j0 + 1, _hint_stride - 1)
	var i1 := mini(i0 + 1, _hint_stride - 1)
	var tx := clampf(fx - floorf(fx), 0.0, 1.0)
	var tz := clampf(fz - floorf(fz), 0.0, 1.0)
	var a00 := i0 * _hint_stride + j0
	var a10 := i0 * _hint_stride + j1
	var a01 := i1 * _hint_stride + j0
	var a11 := i1 * _hint_stride + j1
	return lerpf(lerpf(_hint_dist[a00], _hint_dist[a10], tx), lerpf(_hint_dist[a01], _hint_dist[a11], tx), tz)


## Nearest coarse node's centerline index (window hint; NOT interpolated --
## indices are not interpolable).
func _hint_index_at(wx: float, wz: float) -> int:
	var j := clampi(int(roundf((wx + TERRAIN_HALF) / FIELD_STEP)), 0, _hint_stride - 1)
	var i := clampi(int(roundf((wz + TERRAIN_HALF) / FIELD_STEP)), 0, _hint_stride - 1)
	return _hint_index[i * _hint_stride + j]


## The distance at which a texel can stop caring about the road: past
## W/2 + BLEND_RUN + EXACT_SCAN_MARGIN the coalesced shoulder/berm blend has
## already flattened to PLAIN_Y.
func _plain_cutoff() -> float:
	return BarcelonaRxLayout.WIDTH * 0.5 + BarcelonaRxLayout.BLEND_RUN + EXACT_SCAN_MARGIN


## Bank-aware ground height at a world XZ position.
##
## `s` is the signed lateral offset from the centerline (positive = right of
## travel = the INNER side of a right-hand turn), `bank` the profile angle
## interpolated at the nearest centerline position (POSITIVE in every right
## turn), `center_y` that point's Y. Because the layout lifts the centerline by
## (W/2)|sin(bank)|, the road surface at s is `center_y - s*sin(bank)`; the
## ground is that minus WASHBED_DEPTH under the road, and a two-sided lip blend
## (EDGE_DROP -> PLAIN_Y over BLEND_RUN) outside it. Both sides blend, because a
## rallycross circuit is a closed loop with no distinct infield shoulder.
func _terrain_height(wx: float, wz: float) -> float:
	_last_abs_s = INF
	if _hint_dist_at(wx, wz) > _plain_cutoff():
		return BarcelonaRxLayout.PLAIN_Y

	var n := road_points.size()
	var hint := _hint_index_at(wx, wz)
	var best_d2 := INF
	var best_s := 0.0
	var best_y := 0.0
	var best_bank := 0.0
	var best_j := 0
	var best_t := 0.0
	for k in range(-FIELD_WINDOW, FIELD_WINDOW + 1):
		var j := posmod(hint + k, n)
		var jn := (j + 1) % n
		var a: Vector3 = road_points[j]
		var b: Vector3 = road_points[jn]
		var abx := b.x - a.x
		var abz := b.z - a.z
		var len2 := abx * abx + abz * abz
		if len2 <= 0.0001:
			continue
		var t := clampf(((wx - a.x) * abx + (wz - a.z) * abz) / len2, 0.0, 1.0)
		var dx := wx - (a.x + abx * t)
		var dz := wz - (a.z + abz * t)
		var d2 := dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			# right = forward rotated -90 deg in XZ = (-abz, abx) / |ab|.
			var inv := 1.0 / sqrt(len2)
			best_s = dx * (-abz * inv) + dz * (abx * inv)
			best_y = a.y + (b.y - a.y) * t
			best_bank = bank_profile[j] + (bank_profile[jn] - bank_profile[j]) * t
			best_j = j
			best_t = t

	var half := BarcelonaRxLayout.WIDTH * 0.5
	_last_abs_s = absf(best_s)
	_last_arc = BarcelonaRxLayout.arc_of_index(best_j) + best_t * BarcelonaRxLayout.spacing()
	# 1. Under the road: the exact (banked) surface minus the washbed.
	if absf(best_s) <= half:
		return best_y - best_s * sin(best_bank) - WASHBED_DEPTH
	# 2. Both sides: from the banked road edge down to the plain over BLEND_RUN.
	# The edge height is `center_y - sign(s)*half*sin(bank)`, so the inner (right)
	# edge is at ROAD_BASE_Y and the outer (left) edge at ROAD_BASE_Y + W*sin.
	var sgn := signf(best_s)
	var edge_y := best_y - sgn * half * sin(best_bank)
	var blend := smoothstep(0.0, BarcelonaRxLayout.BLEND_RUN, absf(best_s) - half)
	return lerpf(edge_y - EDGE_DROP, BarcelonaRxLayout.PLAIN_Y, blend)


## Per-point loose weight for the verge colour: 1 on a DIRT_SECTIONS point, 0 on
## asphalt, linearly blended over VERGE_ARC_BLEND m of arc centred on each
## surface change. Reads the layout table directly (the road's own source).
func _build_verge_profile() -> void:
	var n := BarcelonaRxLayout.TOTAL_POINTS
	_verge_loose.resize(n)
	var half_blend := VERGE_ARC_BLEND * 0.5
	for i in n:
		var arc := BarcelonaRxLayout.arc_of_index(i)
		var w := 1.0 if BarcelonaRxLayout.is_loose_at_arc(arc) else 0.0
		for r in BarcelonaRxLayout.DIRT_SECTIONS:
			for edge: float in [r.x, r.y]:
				var d := fposmod(arc - edge + BarcelonaRxLayout.TARGET_PERIMETER * 0.5,
					BarcelonaRxLayout.TARGET_PERIMETER) - BarcelonaRxLayout.TARGET_PERIMETER * 0.5
				if absf(d) < half_blend:
					# Inside the blend window of this edge: entering (r.x) ramps up
					# with d, leaving (r.y) ramps down with d.
					var u := (d + half_blend) / VERGE_ARC_BLEND
					w = u if edge == r.x else 1.0 - u
		_verge_loose[i] = clampf(w, 0.0, 1.0)


## Ground colour of texel (ix, iz), from the side outputs of the
## `_terrain_height` call that just ran for it: grass, a loose dirt verge beside
## the DIRT section, and a narrow gravel run-off beside the asphalt. A
## deterministic per-texel hash breaks the band edges up (no RNG).
func _verge_color(ix: int, iz: int) -> Color:
	if not is_finite(_last_abs_s):
		return GRASS_COLOR
	var beyond := _last_abs_s - BarcelonaRxLayout.WIDTH * 0.5
	var n := _verge_loose.size()
	var loose := 0.0
	if n > 0:
		var f := _last_arc / BarcelonaRxLayout.spacing()
		var i0 := posmod(int(floorf(f)), n)
		loose = lerpf(_verge_loose[i0], _verge_loose[(i0 + 1) % n], f - floorf(f))
	var jitter := float(posmod(ix * 73856093 ^ iz * 19349663, 1000)) / 1000.0
	var dirt_w := 1.0 - smoothstep(LOOSE_VERGE_FULL, LOOSE_VERGE_FADE, beyond + (jitter - 0.5) * 3.0)
	var run_w := 1.0 - smoothstep(RUNOFF_FULL, RUNOFF_FADE, beyond + (jitter - 0.5) * 1.5)
	var verge := RUNOFF_COLOR.lerp(LOOSE_VERGE_COLOR, loose)
	var weight := lerpf(run_w, dirt_w, loose)
	return GRASS_COLOR.lerp(verge * (0.92 + 0.16 * jitter), clampf(weight, 0.0, 1.0))


## Player spawn: the grid point (checkpoint 0), one metre up, facing down the
## road. The vehicle's forward is -basis.z, so `rotation.y = atan2(-fwd.x,
## -fwd.z)` aligns it with the frame's forward at arc 0 (guarded by the P2
## gate suite).
func _reposition_player_to_start() -> void:
	var player := get_node_or_null("%PlayerCar") as Node3D
	if player == null:
		return
	var frame := BarcelonaRxLayout.frame_at_arc(0.0)
	var forward: Vector3 = frame["forward"]
	player.global_position = road_points[0] + Vector3(0, 1.0, 0)
	player.global_rotation = Vector3(0.0, atan2(-forward.x, -forward.z), 0.0)


func _on_checkpoint_body_entered(body: Node3D, index: int) -> void:
	if body is VehiclePhysics:
		print("[Track] Barcelona RX checkpoint %d passed by %s" % [index, body.name])
