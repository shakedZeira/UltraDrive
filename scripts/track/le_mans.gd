extends Node3D

## Circuit des 24 Heures du Mans — No-Chicane (plan
## `docs/plans/track_le_mans_no_chicane.md`): a 13.626 km closed endurance road
## circuit built from `LeMansLayout`. Mirrors `barcelona_rx.gd`'s orchestration
## (centerline -> ground -> road -> checkpoints -> foliage -> dressing ->
## colliders -> spawn) with three v1 differences the plan calls out:
##
##   * the ground is a FLAT plane + a full-edge verge skirt, not a Terrain3D bake
##     (§3.7; the Dunlop climb is a named follow-up, §8.5);
##   * the grid sits at rp4684 (chainage 13,296.7, 329 m behind the line) and the
##     start/finish line is the LAST checkpoint in travel order (§3.6), because
##     checkpoints count by presence so a grid on a gate would eat lap 1;
##   * the dressing is the scene's own `LeMansDressing` (§3.8), never
##     `RxDressing`.
##
## HONESTY NOTE (plan §3.9, keep this docstring): the geometry is an
## OpenStreetMap centerline trace scaled to the published 13.626 km. It is
## APPROXIMATE: ±10-30 m lateral on straights, worse inside the corner
## complexes; the S/F line is ±100 m; the Dunlop bridge chainage is ±150 m; every
## chicane removal is a geometric chord, NOT the historic alignment; the
## Mulsanne kink is reconstructed from secondary sources; elevation is not
## modelled (flat v1). © OpenStreetMap contributors, ODbL.
##
## The scene owns a `RoadNetwork` child, so the minimap, the pause map and the
## `SurfaceRegistry` asphalt grip all resolve the circuit from the
## `"road_network"` group with no extra plumbing.

## Carriageway width (m), from the layout so mesh/dressing/tests cannot drift.
const WIDTH := LeMansLayout.WIDTH_M

## 24 checkpoint boxes. The 16 x 8 x 16 box spans the road width so a back-row
## rival cannot miss a gate (the `barcelona_rx` sizing).
const CHECKPOINT_BOX := Vector3(16.0, 8.0, 16.0)

## v1 flat ground plane (m). Covers the layout bbox (2,753 x 5,424 m) plus a
## generous margin on every side (§3.7).
const GROUND_SIZE := Vector2(6000.0, 7000.0)

## Flat-section verge drop (m): a road edge rides at ROAD_BASE_Y (0.15) and the
## plain at PLAIN_Y (-0.25), so the skirt closes exactly 0.40 m there. Banked
## edges start higher and drop to the same plain.
const SKIRT_DROP := 0.40

## Foliage annulus radius (m). The scene is 12.6x longer than any existing
## circuit, so the node is centred on the layout bbox centre and this radius
## reaches every bbox corner (max corner distance 3,041 m). Counts stay bounded:
## placement rejection tests every candidate against the 4,800-point road, and
## dense foliage over ~30 km2 is a named v1 compromise (§8.3(e)), not a claim.
const FOLIAGE_RADIUS := 3150.0
const FOLIAGE_GRASS := 700
const FOLIAGE_TREES := 60

## Dry French countryside plain / verge tints (flat v1 ground, §3.7).
const GROUND_COLOR := Color(0.21, 0.29, 0.15)
const SKIRT_COLOR := Color(0.17, 0.24, 0.12)

## Centerline points used to build the road (exposed for tests, like
## `barcelona_rx.road_points`).
var road_points: Array[Vector3] = []

## Signed bank angle (radians) per centerline point, in TrackBuilder._frame's
## sign space (POSITIVE = right turn). Exposed for tests.
var bank_profile: PackedFloat32Array = PackedFloat32Array()

## The road network this scene owns, resolved once in `_ready`.
var road_network: RoadNetwork = null

## Layout bbox centre in world XZ (the ground plane / foliage origin).
var ground_center := Vector3.ZERO

## Wall-clock milliseconds the flat ground + skirt build took (diagnostic only;
## never asserted -- the `test_perf_gate` lesson).
var ground_bake_ms: int = 0

## Vertices in the skirt ribbon (n * 2 sides * 2 per station).
var skirt_vertex_count: int = 0

## Export gates. Defaults keep the standalone scene behaving as the tests
## expect; a lean zone scene can turn ground/foliage/spawn off.
@export var build_own_ground: bool = true
@export var build_foliage: bool = true
## Builds the scene's `Dressing` child (`LeMansDressing`: gantry, arch, kerbs,
## tyre stacks, hedgerows, marshal posts). Independent of ground/foliage.
@export var build_dressing: bool = true
@export var reposition_player: bool = true


func _ready() -> void:
	road_points = LeMansLayout.build_centerline()
	bank_profile = LeMansLayout.build_bank_profile()

	if build_own_ground:
		_build_ground()

	road_network = _resolve_road_network()
	_build_road(road_network)

	_build_checkpoints()

	if build_foliage:
		_build_foliage()

	if build_dressing:
		_build_dressing()

	# Harmless today; enables rival rosters later (RaceManager/RivalDriver read
	# this centerline when a roster is configured).
	RaceManager.set_rival_centerline(road_points)

	if reposition_player:
		_reposition_player_to_start()


## Pure, side-effect-free centerline generation for `TrackLayoutSource`'s
## documented OFF-TREE probe: `instantiate()` WITHOUT entering the tree, then
## call this. Returns the same `Array[Vector3]` `_ready` drives from.
func _generate_road_points() -> Array[Vector3]:
	return LeMansLayout.build_centerline()


## The scene ships a `RoadNetwork` child; create one if a lean variant omits it.
func _resolve_road_network() -> RoadNetwork:
	var network := get_node_or_null("RoadNetwork") as RoadNetwork
	if network == null:
		network = RoadNetwork.new()
		network.name = "RoadNetwork"
		add_child(network)
	return network


## One closed ARTERIAL/asphalt def (§3.7/A6): width 12, no rails at all
## (`RailSide.NONE`; v1 armco is visual-only dressing, §8.3(f)), the layout's
## bank profile attached verbatim and no dashed lane paint.
func _build_road(network: RoadNetwork) -> void:
	var def := RoadDef.make(
		RoadDef.Tier.ARTERIAL,
		road_points,
		"le_mans-asphalt",
		true,
		WIDTH,
		RoadDef.Surface.ASPHALT,
		RoadDef.RailSide.NONE)
	def.name = "Le Mans No-Chicane"
	def.bank_angles = bank_profile
	def.show_lane_dividers = false
	network.add_road_def(def)


## 24 checkpoints, one per `checkpoint_indices()` slot, in travel order:
## [200, 400, ..., 4600, 0]. `checkpoint.index` is the POSITION in that list
## (0..23), so the start/finish line at rp0 is index 23 -- LAST in travel order,
## which is what makes a frame-based counter tick exactly one lap (§3.6).
func _build_checkpoints() -> void:
	var indices := LeMansLayout.checkpoint_indices()
	for i in indices.size():
		var cp := Checkpoint.new()
		cp.name = "Checkpoint%d" % i
		cp.index = i
		cp.position = road_points[indices[i]] + Vector3(0, 0.5, 0)
		cp.is_start_line = i == indices.size() - 1
		var shape := BoxShape3D.new()
		shape.size = CHECKPOINT_BOX
		var collision := CollisionShape3D.new()
		collision.shape = shape
		cp.add_child(collision)
		add_child(cp)


## --- v1 flat ground + verge skirt (§3.7) -------------------------------------

## The layout bbox centre in world XZ. The ground plane and foliage annulus are
## both centred here (not at the world origin, which sits near the loop's west
## edge and would waste most of the annulus off-circuit).
static func layout_center(points: Array[Vector3]) -> Vector3:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		lo.x = minf(lo.x, p.x)
		lo.y = minf(lo.y, p.z)
		hi.x = maxf(hi.x, p.x)
		hi.y = maxf(hi.y, p.z)
	var mid := (lo + hi) * 0.5
	return Vector3(mid.x, LeMansLayout.PLAIN_Y, mid.y)


## Flat plane at PLAIN_Y + a vertical verge skirt around the ENTIRE road edge,
## both sides. `track_builder.gd` emits no shoulder (checked in P0: no
## shoulder/verge symbol in the file), so the scene owns the ribbon. The plane
## is collision-backed; the skirt is visual only -- the plane under it is the
## ground a car leaving the road drops onto, and a collidable vertical skirt
## would snag a car at the edge instead.
func _build_ground() -> void:
	var bake_start := Time.get_ticks_msec()
	ground_center = layout_center(road_points)

	var grass := StandardMaterial3D.new()
	grass.albedo_color = GROUND_COLOR
	grass.roughness = 1.0

	var plane := PlaneMesh.new()
	plane.size = GROUND_SIZE
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = plane
	ground.material_override = grass
	ground.position = ground_center
	add_child(ground)

	var body := StaticBody3D.new()
	body.name = "GroundBody"
	body.position = ground_center - Vector3(0.0, 0.5, 0.0)
	var shape := BoxShape3D.new()
	shape.size = Vector3(GROUND_SIZE.x, 1.0, GROUND_SIZE.y)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

	var skirt_mat := StandardMaterial3D.new()
	skirt_mat.albedo_color = SKIRT_COLOR
	skirt_mat.roughness = 1.0
	# A skirt is seen from inside AND outside the loop; the ribbon's winding
	# cannot satisfy both, so the material is double-sided.
	skirt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var skirt := MeshInstance3D.new()
	skirt.name = "Skirt"
	skirt.mesh = _build_skirt_mesh()
	skirt.material_override = skirt_mat
	add_child(skirt)

	ground_bake_ms = Time.get_ticks_msec() - bake_start


## Ribbon mesh: per side, per station, one vertex on the banked road edge and one
## directly below it on the plain, joined by two triangles per segment. Built
## from EXACTLY `TrackBuilder._frame`'s math (neighbour tangent, `cross = right *
## cos(bank) - UP * sin(bank)`) so the top of the skirt is the road mesh's own
## edge vertex -- no gap and no overlap by construction.
func _build_skirt_mesh() -> ArrayMesh:
	var n := road_points.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for side: float in [-1.0, 1.0]:
		var base := vertices.size()
		for i in n:
			var edge := edge_point(i, side)
			var outward := _edge_normal(i, side)
			vertices.append(edge)
			normals.append(outward)
			vertices.append(Vector3(edge.x, LeMansLayout.PLAIN_Y, edge.z))
			normals.append(outward)
		for i in n:
			var j := (i + 1) % n
			var top_a := base + i * 2
			var bot_a := top_a + 1
			var top_b := base + j * 2
			var bot_b := top_b + 1
			indices.append_array([top_a, bot_a, top_b, top_b, bot_a, bot_b])
	skirt_vertex_count = vertices.size()

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The road mesh's own edge vertex at centerline index `index` (`side` -1 = the
## left edge, +1 = the right edge), replicating `TrackBuilder._frame` exactly:
## forward from the neighbour points, right = forward x UP, and the banked cross
## direction `right*cos(bank) - UP*sin(bank)`.
func edge_point(index: int, side: float) -> Vector3:
	var n := road_points.size()
	var prev := road_points[(index - 1 + n) % n]
	var next := road_points[(index + 1) % n]
	var forward := (next - prev).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var angle := float(bank_profile[index])
	var cross := right * cos(angle) - Vector3.UP * sin(angle)
	return road_points[index] + cross * (side * WIDTH * 0.5)


## Horizontal outward normal of the skirt at `index` (away from the road).
func _edge_normal(index: int, side: float) -> Vector3:
	var n := road_points.size()
	var forward := (road_points[(index + 1) % n] - road_points[(index - 1 + n) % n]).normalized()
	return forward.cross(Vector3.UP).normalized() * side


## Scatter vegetation around the whole circuit. `inner_clear_radius = 0`: the
## road rejection (`road_network` set BEFORE `add_child`, because
## `Foliage._ready` generates immediately) does all the clearing. The road is
## rejected with `PropScatterer`'s predicate inside `Foliage` itself; unlike the
## 1.1 km barcelona circuit there is no bounded seed-retry loop here -- over
## ~30 km2 the annulus is deliberately sparse (§8.3(e)) and a retry pass would
## cost a full extra road-clearance sweep of every instance.
func _build_foliage() -> void:
	var foliage := Foliage.new()
	foliage.name = "Foliage"
	foliage.radius = FOLIAGE_RADIUS
	foliage.inner_clear_radius = 0.0
	foliage.grass_count = FOLIAGE_GRASS
	foliage.tree_count = FOLIAGE_TREES
	foliage.ground_height_provider = func(_pos: Vector2) -> float:
		return LeMansLayout.PLAIN_Y
	foliage.road_network = road_network
	foliage.position = Vector3(ground_center.x, 0.0, ground_center.z)
	add_child(foliage)


## Wires the scene's `Dressing` child (`LeMansDressing`). Everything is placed
## from the layout's own frame math against the SAME centerline + bank profile
## the road mesh consumes, so the dressing never disagrees with the asphalt
## about where the road edge is. `height_provider` is optional; the flat v1
## scene passes its own plain height.
func _build_dressing() -> void:
	var dressing := get_node_or_null("Dressing") as LeMansDressing
	if dressing == null:
		return
	dressing.configure(
		road_points,
		bank_profile,
		WIDTH,
		func(_pos: Vector3) -> float: return LeMansLayout.PLAIN_Y)
	dressing.build()


## Player spawn: the grid point (chainage 13,296.7, rp4684), one metre up,
## facing down the road. The vehicle's forward is -basis.z, so
## `rotation.y = atan2(-fwd.x, -fwd.z)` aligns it with the frame's forward at
## the grid arc. The grid is NOT on a checkpoint (§3.6): the first line crossing
## is out of order and must not tick a lap.
func _reposition_player_to_start() -> void:
	var player := get_node_or_null("%PlayerCar") as Node3D
	if player == null:
		return
	var frame := LeMansLayout.frame_at_arc(LeMansLayout.grid_arc())
	var forward: Vector3 = frame["forward"]
	player.global_position = road_points[LeMansLayout.GRID_INDEX] + Vector3(0, 1.0, 0)
	player.global_rotation = Vector3(0.0, atan2(-forward.x, -forward.z), 0.0)
