extends Node3D

## Circuit des 24 Heures du Mans — No-Chicane (plan
## `docs/plans/track_le_mans_no_chicane.md`): a 13.626 km closed endurance road
## circuit built from `LeMansLayout`. Mirrors `barcelona_rx.gd`'s orchestration
## (centerline -> ground -> road -> checkpoints -> foliage -> dressing ->
## colliders -> spawn) with three v1 differences the plan calls out:
##
##   * the ground is the scene's own real-elevation height field
##     (`LeMansTerrain`: SRTM terrain blended into a road corridor) + a
##     full-edge verge skirt, not a Terrain3D bake (2026-10-22, replaces the
##     flat v1 plane of §3.7);
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
## Mulsanne kink is reconstructed from secondary sources; elevation is real
## SRTM survey data along that approximate trace, smoothed (see LeMansLayout).
## © OpenStreetMap contributors, ODbL. Elevation: NASA SRTM (public domain).
##
## The scene owns a `RoadNetwork` child, so the minimap, the pause map and the
## `SurfaceRegistry` asphalt grip all resolve the circuit from the
## `"road_network"` group with no extra plumbing.

## Carriageway width (m), from the layout so mesh/dressing/tests cannot drift.
const WIDTH := LeMansLayout.WIDTH_M

## 24 checkpoint boxes. The 16 x 8 x 16 box spans the road width so a back-row
## rival cannot miss a gate (the `barcelona_rx` sizing).
const CHECKPOINT_BOX := Vector3(16.0, 8.0, 16.0)

## Ground extent (m). Covers the layout bbox (2,753 x 5,424 m) plus a generous
## margin on every side (§3.7); now the real-elevation terrain's extent.
const GROUND_SIZE := Vector2(6000.0, 7000.0)

## Flat-section verge drop (m): a road edge rides ROAD_BASE_Y - PLAIN_Y = 0.40 m
## above the road-corridor ground (`LeMansLayout.ground_y_at_arc`), at every
## height of the real profile; banked edges start higher.
const SKIRT_DROP := 0.40

## Foliage annulus radius (m). The scene is 12.6x longer than any existing
## circuit, so the node is centred on the layout bbox centre and this radius
## reaches every bbox corner (max corner distance 3,041 m). Counts stay bounded:
## placement rejection tests every candidate against the 4,800-point road, and
## dense foliage over ~30 km2 is a named v1 compromise (§8.3(e)), not a claim.
const FOLIAGE_RADIUS := 3150.0
const FOLIAGE_GRASS := 700
const FOLIAGE_TREES := 60


## --- WS-B / WS-F surface realism (docs/plans/le_mans_visual_realism_plan.md) ---
## The plain is ONE 6 x 7 km PlaneMesh, so "macro variation + more than one
## texture set" cannot come from Terrain3D's autoshader (the scene has no
## Terrain3D by contract, §3.7). It comes from `LeMansSurfaces.ground_material()`:
## a world-space shader sampling one seamless noise tile at four scales (field,
## 100 m, metre, sub-metre), blending lush / dry / damp grass. The skirt and a
## new verge wear band share that shader, and so do the dressing's sand traps,
## so every edge between them is seamless by construction.

## Verge wear band (a flat ribbon on the plain hugging both road edges).
## Width (m) on a plain straight, extra width at corner complexes, and the
## deterministic +- jitter of its torn outer edge.
const VERGE_WIDTH_BASE := 1.6
const VERGE_WIDTH_CORNER := 3.8
const VERGE_JITTER := 0.45
## Worn-earth weight at the road edge on a straight / added at corners.
const VERGE_WEAR_BASE := 0.32
const VERGE_WEAR_CORNER := 0.6
## Over the plain: above the ground, below the dressing's traps/aprons.
const VERGE_LIFT := 0.04
## Gaussian half-width (m of arc) of a sharp corner's influence on the verge.
const CORNER_INFLUENCE_M := 55.0

## Racing line (asphalt UV2):
## line = -LINE_GAIN * k_narrow + LINE_OUT_GAIN * (k_wide - k_narrow): the
## narrow term pulls the line to the inside at the apex, the wide-minus-narrow
## term swings it to the outside on entry and exit (k > 0 = left turn, and the
## lateral axis runs -1 left edge .. +1 right edge).
const LINE_NARROW_M := 25.0
const LINE_WIDE_M := 120.0
const LINE_GAIN := 30.0
const LINE_OUT_GAIN := 80.0
const LINE_MAX := 0.72
## Rubber intensity: straight-line floor and per-curvature gain.
const RUBBER_FLOOR := 0.28
const RUBBER_GAIN := 60.0

## Skirt face darkening (the earth bank under the road edge).
const SKIRT_TINT := 0.72
## How far the skirt's bottom edge reaches BELOW the terrain at its foot (m):
## the 16 m terrain triangles cannot follow the road edge exactly round every
## curve and crest, so the skirt is driven into the ground instead of resting
## on it.
const SKIRT_BURY := 0.3

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
	_dress_road_surface(network)


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


## Real-elevation ground (`LeMansTerrain`, replaces the flat v1 plane): one
## height field drawn as 512 m tiles under the shared world-space grass
## material, collided as per-tile trimeshes, and sampled by `terrain_height()`
## for everything that stands on it. Plus the vertical verge skirt around the
## ENTIRE road edge, both sides, now reaching SKIRT_BURY below the terrain at
## its foot so the road edge never shows daylight underneath. The skirt is
## visual only -- the terrain under it is what a car leaving the road drops onto
## (a collidable vertical skirt would snag a car at the edge).
func _build_ground() -> void:
	var bake_start := Time.get_ticks_msec()
	ground_center = layout_center(road_points)
	LeMansTerrain.ensure(Vector2(ground_center.x, ground_center.z), GROUND_SIZE, road_points)

	# WS-B macro variation: world-space multi-scale grass (see the const block).
	var grass := LeMansSurfaces.ground_material(0.0, 1.0)
	var ground := Node3D.new()
	ground.name = "Ground"
	add_child(ground)
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	add_child(body)
	var tiles := LeMansTerrain.tiles()
	for i in tiles.size():
		var mesh := tiles[i]["mesh"] as ArrayMesh
		var tile := MeshInstance3D.new()
		tile.name = "GroundTile_%d" % i
		tile.mesh = mesh
		tile.material_override = grass
		# Receives the dressing's dirt-spill decals (never the cars).
		tile.layers = tile.layers | LeMansDressing.DECAL_LAYER
		ground.add_child(tile)
		var collision := CollisionShape3D.new()
		collision.name = "GroundShape_%d" % i
		collision.shape = mesh.create_trimesh_shape()
		body.add_child(collision)

	# Same world-space grass as the ground, darkened: the skirt is the earth
	# bank under the road edge. The shader is cull_disabled (a skirt is seen
	# from inside AND outside the loop) and needs no UVs.
	var skirt_mat := LeMansSurfaces.ground_material(0.0, SKIRT_TINT)
	var skirt := MeshInstance3D.new()
	skirt.name = "Skirt"
	skirt.mesh = _build_skirt_mesh()
	skirt.material_override = skirt_mat
	add_child(skirt)

	var verge := MeshInstance3D.new()
	verge.name = "Verge"
	verge.mesh = _build_verge_mesh()
	verge.material_override = LeMansSurfaces.ground_material(1.0, 1.0)
	verge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	verge.layers = verge.layers | LeMansDressing.DECAL_LAYER
	add_child(verge)

	ground_bake_ms = Time.get_ticks_msec() - bake_start


## Ground height at world XZ (the terrain's own triangles). Valid once
## `_build_ground` ran; before that (a lean scene without own ground) it falls
## back to the nearest road-ground profile height.
func terrain_height(x: float, z: float) -> float:
	if LeMansTerrain.is_ready():
		return LeMansTerrain.height_at(x, z)
	return LeMansLayout.PLAIN_Y


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
			vertices.append(Vector3(edge.x, terrain_height(edge.x, edge.z) - SKIRT_BURY, edge.z))
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


## --- WS-B / WS-F: road surface + verge wear (plan WS-B "uniform asphalt", WS-F
## "rubbered-in racing line") ------------------------------------------------

## Swap the TrackBuilder road's VISUAL mesh for a UV'd copy with the same
## vertices (so the skirt/edge contract is untouched) and give it the asphalt
## shader; the painted edge lines move into that shader, so TrackBuilder's 1 m
## ARTERIAL red/white edge strips are hidden (real Sarthe edges are thin white
## lines). TrackBuilder's collision body is not touched.
func _dress_road_surface(network: RoadNetwork) -> void:
	if network.get_child_count() == 0:
		return
	var builder := network.get_child(network.get_child_count() - 1)
	var surface := builder.get_node_or_null("RoadSurface") as MeshInstance3D
	if surface != null:
		surface.mesh = _build_road_visual_mesh()
		surface.material_override = LeMansSurfaces.asphalt_material(WIDTH * 0.5)
		surface.layers = surface.layers | LeMansDressing.DECAL_LAYER
	for edge_name: String in ["RoadEdgeRight", "RoadEdgeLeft"]:
		var edge := builder.get_node_or_null(edge_name) as MeshInstance3D
		if edge != null:
			edge.visible = false


## Signed curvature (rad/m, > 0 = left turn) at every centerline point.
func _curvatures() -> PackedFloat32Array:
	var n := road_points.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var spacing := LeMansLayout.spacing()
	for i in n:
		var t1 := road_points[i] - road_points[(i - 1 + n) % n]
		var t2 := road_points[(i + 1) % n] - road_points[i]
		t1.y = 0.0
		t2.y = 0.0
		var turn := atan2(t1.cross(t2).y, t1.dot(t2))
		out[i] = turn / spacing
	return out


## Circular box-filter of `values` with a half-window of `half_m` metres.
static func _smooth_circular(values: PackedFloat32Array, half_m: float) -> PackedFloat32Array:
	var n := values.size()
	var half := maxi(int(roundf(half_m / LeMansLayout.spacing())), 1)
	var prefix := PackedFloat64Array()
	prefix.resize(n + 1)
	prefix[0] = 0.0
	for i in n:
		prefix[i + 1] = prefix[i] + values[i]
	var total := prefix[n]
	var out := PackedFloat32Array()
	out.resize(n)
	var count := float(half * 2 + 1)
	for i in n:
		var a := i - half
		var b := i + half + 1
		var sum := 0.0
		if a < 0:
			sum = prefix[b] + (total - prefix[n + a])
		elif b > n:
			sum = (total - prefix[a]) + prefix[b - n]
		else:
			sum = prefix[b] - prefix[a]
		out[i] = float(sum / count)
	return out


## Racing-line lateral (-1 left .. +1 right) and rubber intensity per point.
func racing_line_profile() -> Dictionary:
	var k := _curvatures()
	var kn := _smooth_circular(k, LINE_NARROW_M)
	var kw := _smooth_circular(k, LINE_WIDE_M)
	var n := k.size()
	var line := PackedFloat32Array()
	var rubber := PackedFloat32Array()
	line.resize(n)
	rubber.resize(n)
	for i in n:
		line[i] = clampf(-LINE_GAIN * kn[i] + LINE_OUT_GAIN * (kw[i] - kn[i]), -LINE_MAX, LINE_MAX)
		rubber[i] = clampf(RUBBER_FLOOR + RUBBER_GAIN * absf(kw[i]), 0.0, 1.0)
	return {"line": line, "rubber": rubber}


## The road's visual strip with UV (x across 0..1, y arc metres), UV2 (racing
## line, rubber), true banked normals and tangents. Vertices are EXACTLY
## `edge_point(i, -1/+1)` -- the TrackBuilder mesh's own edge vertices -- plus
## one duplicated closing row so the arc-length UV has no wrap seam.
func _build_road_visual_mesh() -> ArrayMesh:
	var n := road_points.size()
	var profile := racing_line_profile()
	var line: PackedFloat32Array = profile["line"]
	var rubber: PackedFloat32Array = profile["rubber"]
	var spacing := LeMansLayout.spacing()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in n + 1:
		var i := row % n
		var left := edge_point(i, -1.0)
		var right_edge := edge_point(i, 1.0)
		var across := (right_edge - left).normalized()
		var forward := (road_points[(i + 1) % n] - road_points[(i - 1 + n) % n]).normalized()
		var up := forward.cross(across).normalized()
		if up.y < 0.0:
			up = -up
		var s := float(row) * spacing
		for v: Vector3 in [left, right_edge]:
			verts.append(v)
			normals.append(up)
			tangents.append_array([across.x, across.y, across.z, 1.0])
		uvs.append(Vector2(0.0, s))
		uvs.append(Vector2(1.0, s))
		uv2s.append(Vector2(line[i], rubber[i]))
		uv2s.append(Vector2(line[i], rubber[i]))
	for row in n:
		var a := row * 2
		LeMansSurfaces.append_quad_up(indices, verts, a, a + 1, a + 2, a + 3)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Arc positions of the layout's sharp corners and which side (+1 right / -1
## left) is each one's OUTSIDE, from the same tangent-swing probe the dressing
## uses (`LeMansDressing._outside_side`, +-30 m).
func _corner_table() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := road_points.size()
	var spacing := LeMansLayout.spacing()
	var probe := int(roundf(LeMansDressing.CORNER_PROBE_M / spacing))
	for ch in LeMansLayout.sharp_corner_chainages(LeMansDressing.SHARP_TURN_DEG):
		var arc := LeMansLayout.arc_at_chainage(ch)
		var i := int(roundf(arc / spacing)) % n
		var f1 := road_points[i] - road_points[(i - probe + n) % n]
		var f2 := road_points[(i + probe) % n] - road_points[i]
		out.append({"arc": arc, "outside": 1.0 if f1.cross(f2).y > 0.0 else -1.0})
	return out


## 0..1 corner-complex weight at point `i` on `side` (the outside of a corner
## weighs 1, the inside 0.55): a Gaussian in arc distance.
func _corner_weight(i: int, side: float, corners: Array[Dictionary], perimeter: float) -> float:
	var s := float(i) * LeMansLayout.spacing()
	var best := 0.0
	for c: Dictionary in corners:
		var d := absf(fposmod(s - float(c["arc"]) + perimeter * 0.5, perimeter) - perimeter * 0.5)
		if d > CORNER_INFLUENCE_M * 3.0:
			continue
		var g := exp(-pow(d / CORNER_INFLUENCE_M, 2.0))
		if float(c["outside"]) != side:
			g *= 0.55
		best = maxf(best, g)
	return best


## The verge wear band: per side, a flat ribbon on the plain from the road edge
## outwards, COLOR.r = worn-earth weight (high at the edge and through corner
## complexes, 0 on the torn outer row, where the ground shader returns exactly
## the plain's own grass).
func _build_verge_mesh() -> ArrayMesh:
	var n := road_points.size()
	var corners := _corner_table()
	var perimeter := LeMansLayout.spacing() * float(n)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for side: float in [-1.0, 1.0]:
		var base := verts.size()
		for i in n:
			var edge := edge_point(i, side)
			var outward := _edge_normal(i, side)
			var cw := _corner_weight(i, side, corners, perimeter)
			var jitter := VERGE_JITTER * sin(float(i) * 0.37 + side * 1.3) * sin(float(i) * 0.113 + 0.7)
			var width := VERGE_WIDTH_BASE + VERGE_WIDTH_CORNER * cw + jitter
			var foot := Vector3(edge.x, terrain_height(edge.x, edge.z) + VERGE_LIFT, edge.z)
			var outer := Vector3(edge.x, 0.0, edge.z) + outward * width
			outer.y = terrain_height(outer.x, outer.z) + VERGE_LIFT
			verts.append(foot)
			verts.append(outer)
			normals.append(Vector3.UP)
			normals.append(Vector3.UP)
			colors.append(Color(clampf(VERGE_WEAR_BASE + VERGE_WEAR_CORNER * cw, 0.0, 1.0), 0.0, 0.0, 1.0))
			colors.append(Color(0.0, 0.0, 0.0, 1.0))
		for i in n:
			var j := (i + 1) % n
			LeMansSurfaces.append_quad_up(indices, verts,
				base + i * 2, base + i * 2 + 1, base + j * 2, base + j * 2 + 1)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


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
	foliage.ground_height_provider = func(pos: Vector2) -> float:
		return terrain_height(pos.x, pos.y)
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
		func(pos: Vector3) -> float: return terrain_height(pos.x, pos.z))
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
