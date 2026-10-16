extends Node3D

## Northern Isle Speedway — GT7's smallest circuit (900 m, a flat banked
## left-turn / CCW speedway oval). Mirrors `mountain_pass.gd`'s orchestration
## (ground bake -> road -> checkpoints -> foliage -> spawn) but the geometry
## comes from `NorthernIsleLayout` and the road is a CLOSED ARTERIAL RoadDef
## carrying an explicit per-point bank profile.
##
## Unlike `mountain_pass.tscn` this scene owns a `RoadNetwork` child, so the
## minimap (`MapRoads.resolve_road_source`), the pause map and the
## `SurfaceRegistry` asphalt grip all resolve the oval from the `"road_network"`
## group with no extra plumbing.
##
## Geometry source of truth: `scripts/track/northern_isle_layout.gd`. The
## centerline (Y included) and the bank profile are built ONCE in `_ready` and
## exposed as members for tests.

## Terrain recess under the asphalt. The washbed floor sits this far BELOW the
## road surface so the two can never z-fight, and it is shallower than
## mountain_pass's 0.6 (the oval's softest cap is the 6 m infield shoulder).
const WASHBED_DEPTH := 0.30

## The visible lip the ground drops over at a road edge. Feeding this into the
## shoulder/berm lerp (instead of the washbed depth) is what stops a texel that
## straddles the road edge from interpolating ABOVE the asphalt: the modelled
## surface at the edge is road_y - EDGE_DROP, always below the road.
const EDGE_DROP := 0.10

## Heightmap spans TERRAIN_SPAN metres at 1 m/px (512 x 512 image, region size
## 256). import_images() snaps its position to a region anchor, so the pane
## starts exactly on one: -256 is a multiple of 256 and covers the whole oval
## footprint (about +/-191 x +/-71 m) plus the berm/shoulder runs with margin.
const TERRAIN_SPAN := 512.0
const TERRAIN_HALF := 256.0

## Coarse routing hint field spacing (m). Only routes a texel to the exact
## centerline scan or the plain; never a result by itself.
const FIELD_STEP := 8.0

## Coarse-field distance error absorbed before a texel is allowed to take the
## plain early-out (same role as mountain_pass EXACT_SCAN_MARGIN).
const EXACT_SCAN_MARGIN := 12.0

## How many centerline indices either side of a texel's coarse hint index the
## exact per-texel scan may touch. Spacing is ~2.96 m, so +/-10 indices spans
## ~59 m of arc -- far more than the 8 m grid step can shift the nearest index.
const FIELD_WINDOW := 10

const GRASS_COLOR := Color(0.30, 0.36, 0.27)

## Bounded re-rolls of the foliage seed looking for a placement whose every
## instance clears the road corridor. `Foliage` rejects only `GRASS_ROAD_ATTEMPTS`
## (4) samples in `_grass_transform` and then keeps the LAST sample unchecked
## (`_tree_pos` has the same unchecked fallback) -- fixing that is out of scope
## for this scene, so rather than loosen this scene's corridor contract we re-run
## `Foliage.generate()` on the next seed until placement is clean. With the stock
## seed 2120 exactly one grass tuft lands 6.0 m from the centerline (the corridor
## needs >= 11 m); a clean seed is the common case, so 1-2 rolls normally suffice.
const FOLIAGE_SEED_ATTEMPTS := 8

## Centerline points used to build the road (exposed for tests, like
## `mountain_pass.road_points`).
var road_points: Array[Vector3] = []

## Signed bank angle (radians) per centerline point, in TrackBuilder._frame's
## sign space (negative = left turn). Exposed for tests.
var bank_profile: PackedFloat32Array = PackedFloat32Array()

## The road network this scene owns, resolved once in `_ready`.
var road_network: RoadNetwork = null

## Wall-clock milliseconds the last bank-aware ground bake took (diagnostic for
## the P3 gate; never asserted -- the `test_perf_gate` lesson).
var ground_bake_ms: int = 0

## Coarse hint field: `_hint_index[i]` is the nearest centerline POINT index at
## node i, `_hint_dist[i]` the XZ distance to the nearest segment. Populated by
## `_build_hint_field()` and consumed by `_terrain_height()`.
var _hint_index := PackedInt32Array()
var _hint_dist := PackedFloat32Array()
var _hint_stride := 0

## Export gates. Defaults keep the standalone scene behaving as the tests
## expect; a future lean `northern_isle_zone.tscn` (the `mountain_pass_zone`
## pattern) can turn ground/foliage/spawn off because the open world owns them.
@export var build_own_ground: bool = true
@export var build_foliage: bool = true
## Builds the scene's `Dressing` child (`OvalDressing`: catch fence, barrier
## line, grandstands, S/F gantry + checker paint, billboards, infield tents and
## the unwired light poles). A future lean `northern_isle_zone.tscn` can turn it
## off alongside ground/foliage if a zone owns the dressing instead.
@export var build_dressing: bool = true

## Builds the PHYSICAL barrier colliders (catch fence line, red barrier line and
## the inner road rail) as oriented box chains around the oval.
##
## The barrier MESHES are visual only: `OvalDressing` builds no collision at all
## and `TrackBuilder` adds rail collision only when a junction gap list is
## non-empty (a standalone oval has none), so before this a car drove straight
## through the fence/rail off the tarmac. Independent of `build_dressing` so a
## lean zone scene that dresses elsewhere still gets solid barriers.
@export var build_barrier_colliders: bool = true

@export var reposition_player: bool = true


func _ready() -> void:
	road_points = NorthernIsleLayout.build_centerline()
	bank_profile = NorthernIsleLayout.build_bank_profile()

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


## The scene ships a `RoadNetwork` child; create one if a lean variant omits it.
func _resolve_road_network() -> RoadNetwork:
	var network := get_node_or_null("RoadNetwork") as RoadNetwork
	if network == null:
		network = RoadNetwork.new()
		network.name = "RoadNetwork"
		add_child(network)
	return network


## Builds the oval ONCE: an ARTERIAL (rail-both-sides, red/white edges) closed
## asphalt def, then attaches the layout's bank profile and drops the lane
## dividers (a speedway has no dashed lane paint).
func _build_road(network: RoadNetwork) -> void:
	var def := RoadDef.make(
		RoadDef.Tier.ARTERIAL,
		road_points,
		"northern_isle-oval",
		true,
		NorthernIsleLayout.WIDTH,
		RoadDef.Surface.ASPHALT,
		RoadDef.RailSide.BOTH)
	def.bank_angles = bank_profile
	def.show_lane_dividers = false
	network.add_road_def(def)


## 8 checkpoints, one per `checkpoint_indices()` slot, in travel order. The
## 16 x 8 x 16 box spans the road width so a back-row rival cannot miss cp0
## (`RaceManager.RIVAL_GRID_ANCHOR_AHEAD` note in test_race_loop). The
## `"checkpoints"` group is set by `checkpoint.gd` itself.
func _build_checkpoints() -> void:
	var indices := NorthernIsleLayout.checkpoint_indices()
	for i in indices.size():
		var cp := Checkpoint.new()
		cp.index = i
		cp.position = road_points[indices[i]] + Vector3(0, 0.5, 0)
		cp.is_start_line = i == NorthernIsleLayout.START_LINE_INDEX
		var shape := BoxShape3D.new()
		shape.size = Vector3(16.0, 8.0, 16.0)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		cp.add_child(collision)
		cp.body_entered.connect(_on_checkpoint_body_entered.bind(i))
		add_child(cp)


## Scatter vegetation over the whole oval. `inner_clear_radius = 0` on purpose:
## a radial inner-clear would leave trees inside the turns' infields, so the
## road rejection (`road_network` must be set BEFORE add_child, because
## `Foliage._ready` generates immediately) does all the clearing.
##
## `Foliage`'s rejection sampling can still leave a stray instance inside the
## corridor (see FOLIAGE_SEED_ATTEMPTS), so after the first generate this bumps
## the seed and regenerates -- deterministically -- until every instance clears.
func _build_foliage(terrain: Terrain3D) -> void:
	var foliage := Foliage.new()
	foliage.name = "Foliage"
	foliage.radius = 240.0
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


## Keeps foliage grounded on the bank-aware terrain (the mountain_pass pattern).
func _make_ground_height_provider(terrain: Terrain3D) -> Callable:
	return func ground_height_at(pos: Vector2) -> float:
		return terrain.data.get_height(Vector3(pos.x, 0.0, pos.y))


## Wires the scene's `Dressing` child (`OvalDressing`). Everything is placed from
## the layout's own frame math against the SAME centerline + bank profile the
## road mesh consumes, so the dressing can never disagree with the asphalt about
## where the road edge is.
##
## `terrain_height` is a `Callable(Vector3) -> float` -- NOT the
## `Callable(Vector2)` provider `Foliage` takes. It is optional: `OvalDressing`
## falls back to its road-edge frame math on an empty callable, so a scene with
## `build_own_ground = false` still dresses correctly.
func _build_dressing(terrain: Terrain3D) -> void:
	var dressing := get_node_or_null("Dressing") as OvalDressing
	if dressing == null:
		return
	dressing.configure(
		road_points,
		bank_profile,
		NorthernIsleLayout.WIDTH,
		_make_dressing_height_provider(terrain))
	dressing.build()


## Sits the dressing props on the baked ground (empty when no terrain is built).
func _make_dressing_height_provider(terrain: Terrain3D) -> Callable:
	if terrain == null:
		return Callable()
	return func dressing_height_at(pos: Vector3) -> float:
		return terrain.data.get_height(pos)


## --- physical barrier colliders (catch fence / red barrier line / inner rail) -

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
## plainly see under — an "invisible wall", worst when cutting a corner across
## the low infield rail.
##
## MEASURED before this cap (headless sphere walk up each chain's own lateral
## line, 2026-10-16): every chain towered over its own visual — the fence 0.60 m
## above its 3.2 m panels, the red barrier 0.43 m above its GLB top, the inner
## rail 1.05 m above its 0.75 m rail. The chain geometry, ground burial and
## thickness are unchanged — only the rise is now derived from the visual.
const BARRIER_TOP_MARGIN := 0.1

## Visual top of the red barrier GLB at `OvalDressing.BARRIER_SCALE` (m above its
## base line; `racing_barrier_red.glb` is ~0.131 m tall x 12.0). The GLB exposes
## no constant, so the figure is named here and held honest by the barrier gate.
const RED_BARRIER_VISUAL_TOP := 1.57

## Box top = base + rise (m): the top of the visual each chain guards, plus
## `BARRIER_TOP_MARGIN` — `OvalDressing.FENCE_PANEL_TOP` (3.2 m), the red barrier
## GLB top above and `TrackBuilder.RAIL_HEIGHT` (0.75 m).
const FENCE_RISE_ABOVE := OvalDressing.FENCE_PANEL_TOP + BARRIER_TOP_MARGIN
const RED_BARRIER_RISE_ABOVE := RED_BARRIER_VISUAL_TOP + BARRIER_TOP_MARGIN
const RAIL_RISE_ABOVE := TrackBuilder.RAIL_HEIGHT + BARRIER_TOP_MARGIN

## Box cross-section along the road (m): thicker than the visuals they guard (a
## 0.12 m post, a 0.18 m rail) so a fast car can never thread the chain.
const FENCE_COLLIDER_THICKNESS := 0.4
const RED_BARRIER_COLLIDER_THICKNESS := 0.5
const RAIL_COLLIDER_THICKNESS := 0.4

## Friction of the barrier boxes (matches `TrackBuilder`'s rail collision so a
## car scraping a barrier behaves the same wherever it touches one).
const BARRIER_FRICTION := 0.2


## Builds every barrier chain under a `BarrierColliders` child of `parent`.
## `parent` is a parameter (not `self`) purely so a test can host the colliders
## without instantiating the scene; `_ready` passes `self`. Idempotent: a
## previous build is removed first. Returns the number of collision boxes.
##
## BOX CHAIN, NOT TRIMESH: the red barrier GLB is a dense kit mesh instanced
## ~225x through a MultiMesh and the fence panel is a fine triangle strip, so a
## per-instance trimesh would be expensive; one oriented box per layout step is
## cheap (three shared BoxShape3D resources in total) and bullet-proof solid.
func _build_barrier_colliders(parent: Node3D, terrain_height: Callable) -> int:
	var existing := parent.get_node_or_null("BarrierColliders") as Node3D
	if existing != null:
		parent.remove_child(existing)
		existing.free()

	var root := Node3D.new()
	root.name = "BarrierColliders"
	parent.add_child(root)

	var half := NorthernIsleLayout.WIDTH * 0.5
	var added := 0
	# Outfield: the catch-fence line (posts + panel) and the red barrier line,
	# at the SAME lateral lines `OvalDressing` places their meshes on.
	added += _add_barrier_chain(root, "FenceCollision",
		half + OvalDressing.FENCE_OFFSET,
		FENCE_COLLIDER_THICKNESS, FENCE_RISE_ABOVE, terrain_height)
	added += _add_barrier_chain(root, "RedBarrierCollision",
		half + OvalDressing.BARRIER_OFFSET,
		RED_BARRIER_COLLIDER_THICKNESS, RED_BARRIER_RISE_ABOVE, terrain_height)
	# Infield: the road rail's own line (the visuals are on both sides).
	added += _add_barrier_chain(root, "InnerRailCollision",
		-(half + TrackBuilder.RAIL_GAP),
		RAIL_COLLIDER_THICKNESS, RAIL_RISE_ABOVE, terrain_height)
	return added


## One oriented box per layout step along the banked cross-section at `offset`
## (signed: + = outfield). Boxes are chunked into `NorthernIsleLayout.CP_STRIDE`
## -segment StaticBody3Ds so each body's broadphase AABB hugs its own stretch of
## the loop instead of the whole oval. Returns the number of boxes added.
##
## Layer/mask 1 is what every body in the game already uses — `VehiclePhysics`
## is a plain RigidBody3D on the defaults — so the chain collides with cars
## without any layer plumbing.
func _add_barrier_chain(parent: Node3D, prefix: String, offset: float, thickness: float, \
		rise_above: float, terrain_height: Callable) -> int:
	var n := road_points.size()
	if n < 3:
		return 0
	var step := NorthernIsleLayout.spacing()
	var chunk := NorthernIsleLayout.CP_STRIDE
	var height := BARRIER_DROP_BELOW + rise_above
	var shape := BoxShape3D.new()
	shape.size = Vector3(thickness, height, step + BARRIER_BOX_OVERLAP)
	var material := PhysicsMaterial.new()
	material.friction = BARRIER_FRICTION

	var body_count := int(ceil(float(n) / float(chunk)))
	var bodies: Array[StaticBody3D] = []
	for b in body_count:
		var body := StaticBody3D.new()
		body.name = "%s%d" % [prefix, b]
		body.collision_layer = 1
		body.collision_mask = 1
		body.physics_material_override = material
		parent.add_child(body)
		bodies.append(body)

	var added := 0
	for i in n:
		var a := _barrier_line_point(float(i) * step, offset, terrain_height)
		var b := _barrier_line_point(float(i + 1) * step, offset, terrain_height)
		var mid := (a + b) * 0.5
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = Vector3(mid.x, mid.y - BARRIER_DROP_BELOW + height * 0.5, mid.z)
		# Local +Z along the segment so the box's long axis runs with the road
		# (the same convention the road mesh/rails use).
		collision.rotation = Vector3(0.0, atan2(b.x - a.x, b.z - a.z), 0.0)
		bodies[int(i / float(chunk))].add_child(collision)
		added += 1
	return added


## Base point of a chain box at `arc` on the cross-section at `offset`: the
## exact lateral line the visuals are placed from (`center + cross * offset`),
## with Y taken from the baked ground when a terrain provider was configured
## (the `OvalDressing._surface_base_y` rule) and the frame's own cross-section
## height otherwise, so a lean scene with no ground still gets a coherent wall.
func _barrier_line_point(arc: float, offset: float, terrain_height: Callable) -> Vector3:
	var frame := NorthernIsleLayout.frame_at_arc(arc)
	var center: Vector3 = frame["center"]
	var cross: Vector3 = frame["cross"]
	var p := center + cross * offset
	if terrain_height.is_valid():
		var probe := Vector3(p.x, 0.0, p.z)
		var ground: float = terrain_height.call(probe)
		p.y = ground
	return p


## Builds the bank-aware terrain under the oval. The node keeps the historical
## "GrassGround" name other code/tests look up. Deterministic: no RNG anywhere.
func _build_ground() -> Terrain3D:
	var bake_start := Time.get_ticks_msec()
	var terrain := Terrain3D.new()
	terrain.name = "GrassGround"
	add_child(terrain)
	terrain.region_size = Terrain3D.SIZE_256

	_build_hint_field()

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
			color_img.set_pixel(ix, iz, Color(GRASS_COLOR * shade, 0.5))

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


## Bilinearly samples the coarse hint-distance field (the mountain_pass
## `_distance_field_at` structure).
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
## W/2 + EMBANK_RUN + EXACT_SCAN_MARGIN the coalesced shoulder/berm blend has
## already flattened to PLAIN_Y.
func _plain_cutoff() -> float:
	return NorthernIsleLayout.WIDTH * 0.5 + NorthernIsleLayout.EMBANK_RUN + EXACT_SCAN_MARGIN


## Bank-aware ground height at a world XZ position.
##
## `s` is the signed lateral offset from the centerline (positive = outfield /
## RIGHT of travel), `bank` the profile angle interpolated at the nearest
## centerline position (NEGATIVE in the left turns), `center_y` that point's Y.
## Because the layout lifts the centerline by (W/2)|sin(bank)|, the road surface
## at s is `center_y - s*sin(bank)`; the ground is that minus WASHBED_DEPTH under
## the road, and a lip blend (EDGE_DROP) outside it.
func _terrain_height(wx: float, wz: float) -> float:
	if _hint_dist_at(wx, wz) > _plain_cutoff():
		return NorthernIsleLayout.PLAIN_Y

	var n := road_points.size()
	var hint := _hint_index_at(wx, wz)
	var best_d2 := INF
	var best_s := 0.0
	var best_y := 0.0
	var best_bank := 0.0
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

	var half := NorthernIsleLayout.WIDTH * 0.5
	# 1. Under the road: the exact (banked) surface minus the washbed.
	if absf(best_s) <= half:
		return best_y - best_s * sin(best_bank) - WASHBED_DEPTH
	# The infield road edge is at ROAD_BASE_Y by construction, so this shoulder
	# is a plain 6 m ramp to the plain at every point of the oval.
	if best_s < -half:
		var t_in := smoothstep(0.0, NorthernIsleLayout.SHOULDER_RUN, absf(best_s) - half)
		return lerpf(NorthernIsleLayout.ROAD_BASE_Y - EDGE_DROP, NorthernIsleLayout.PLAIN_Y, t_in)
	# Outfield: the berm, starting at the banked outer edge (ROAD_BASE_Y + W|sin|)
	# and flattening to the plain over EMBANK_RUN.
	var outer_edge_y := best_y - half * sin(best_bank)
	var t_out := smoothstep(0.0, NorthernIsleLayout.EMBANK_RUN, best_s - half)
	return lerpf(outer_edge_y - EDGE_DROP, NorthernIsleLayout.PLAIN_Y, t_out)


## Player spawn: checkpoint 0, one metre up. `rotation.y = -PI/2` because the
## vehicle's forward is -basis.z and travel at point 0 is +X, so -PI/2 points
## the car down the front straight (guarded by the P2 gate suite).
func _reposition_player_to_start() -> void:
	var player := get_node_or_null("%PlayerCar") as Node3D
	if player == null:
		return
	player.global_position = road_points[0] + Vector3(0, 1.0, 0)
	player.global_rotation = Vector3(0.0, -PI * 0.5, 0.0)


func _on_checkpoint_body_entered(body: Node3D, index: int) -> void:
	if body is VehiclePhysics:
		print("[Track] Northern Isle checkpoint %d passed by %s" % [index, body.name])
