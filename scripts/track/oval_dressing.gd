# scripts/track/oval_dressing.gd
class_name OvalDressing
extends Node3D

## P4 — Speedway dressing for Northern Isle Speedway
## (docs/plans/track_northern_isle_speedway.md §4 P4).
##
## A small DEDICATED polyline builder, not a `PropScatterer` preset: the
## scatterer places props by rejection-sampling an annulus / a roadside corridor,
## which cannot express "a fence post exactly on the outer road edge, every 4 m
## of arc, its base riding the banked cross-section". Everything here is placed
## from `NorthernIsleLayout`'s own frame math, so the dressing and the mesh can
## never disagree about where the road edge is.
##
## WHAT IT BUILDS (plan §4 P4 items 1-7)
##   1. catch fence  — posts every `FENCE_POST_SPACING` m at `W/2 + FENCE_OFFSET`
##      on the OUTFIELD side, plus one continuous 2.6 m transparent panel strip
##      between the post tops;
##   2. barrier line — `racing_barrier_red.glb` MultiMesh just outside the rails;
##   3. grandstands  — `grandstand.glb` x3 on the front straight outfield +
##      `racing_grandstand.glb` x1 at the back-straight midpoint;
##   4. S/F gantry   — `finish_gantry.glb` straddling the road at checkpoint 7;
##   5. S/F paint    — a generated 8x2 checker on a `WIDTH x 1.5` m quad at cp7;
##   6. billboards   — 10 sponsor quads + `Label3D` text riding the straights;
##   7. infield/night— `racing_tent.glb` x2 + 1 pit garage in the infield and
##      `light_pole.glb` x8 around the outside (UNWIRED — plan §6 risk 10: no
##      lighting or night listener is added in this phase).
##
## DETERMINISM: there is no RNG anywhere in this file, no wall clock, and every
## loop is arc/constant driven, so two `build()` runs on one object produce
## bit-identical transform sets (pinned by the P4 suite).
##
## USABLE WITH NO SCENE: `configure()` then `build()`. Nothing here reads a
## scene, a resource or a `RoadNetwork`; `terrain_height` is an optional
## `Callable(Vector3) -> float` and every consumer of it has a frame-math
## fallback, so a flat stub (or no callable at all) is a valid configuration.
##
## API CONTRACT (the scene wiring and tests depend on these names):
##   configure(centerline, bank_profile, width, terrain_height) -> void
##   build() -> void
##
## Query helpers (all valid after `build()`, all deterministic):
##   fence_posts() / barrier_transforms() / grandstand_transforms() /
##   billboard_transforms() / billboard_labels() / light_pole_transforms() /
##   tent_transforms() / garage_transforms()  -> per-kind transform sets
##   gantry_transform() / gantry_center() / gantry_span() / checker_transform()
##   count_of(kind) / ground_transforms() / signature()
##   prop_mesh(kind) / referenced_glb_paths() / dropped_kinds()
##
## Chosen props that could not be loaded are DROPPED and named by
## `dropped_kinds()` rather than silently skipped (plan §4 P4 / §6 risk 6).

## Prop kinds. `count_of(kind)` / `prop_mesh(kind)` key off these strings.
const KIND_FENCE_POST := "fence_post"
const KIND_FENCE_PANEL := "fence_panel"
const KIND_BARRIER := "barrier"
const KIND_GRANDSTAND := "grandstand"
const KIND_RACING_GRANDSTAND := "racing_grandstand"
const KIND_GANTRY := "gantry"
const KIND_BILLBOARD := "billboard"
const KIND_LIGHT_POLE := "light_pole"
const KIND_TENT := "tent"
const KIND_GARAGE := "garage"
## Not a placed GLB kind — the tag `signature()` uses for the S/F paint quad.
const KIND_CHECKER_TAG := "checker_paint"

## Referenced CC0 Kenney / Phase-A assets (read-only; never modified).
const PATH_BARRIER := "res://assets/track_props/racing_barrier_red.glb"
const PATH_GRANDSTAND := "res://assets/track_props/grandstand.glb"
const PATH_RACING_GRANDSTAND := "res://assets/track_props/racing_grandstand.glb"
const PATH_GANTRY := "res://assets/track_props/finish_gantry.glb"
const PATH_LIGHT_POLE := "res://assets/track_props/light_pole.glb"
const PATH_TENT := "res://assets/track_props/racing_tent.glb"
const PATH_GARAGE := "res://assets/buildings/building_pit_garage.glb"

## --- item 1: catch fence -----------------------------------------------------
## Lateral offset of the fence line beyond the outer road edge (m). This is the
## rail offset the plan names (`W/2 + 0.6`).
const FENCE_OFFSET := 0.6
## Post pitch measured in ARC length (m) — `ceil(perimeter / spacing)` posts.
const FENCE_POST_SPACING := 4.0
## Post cross-section (m): 0.12 x 3.2 x 0.12 box, base on the road edge.
const FENCE_POST_SIZE := Vector3(0.12, 3.2, 0.12)
## Panel strip between the post tops (m). `[BOTTOM, TOP]` above the post base.
const FENCE_PANEL_BOTTOM := 0.6
const FENCE_PANEL_TOP := 3.2

## --- item 2: barrier line ----------------------------------------------------
const BARRIER_OFFSET := 2.2
const BARRIER_SPACING := 4.0
## The barrier GLB is 0.25 m long on its local X axis, so a 12x uniform scale
## makes one segment ~3.0 m long x 1.57 m tall. Measured, not guessed — see the
## P4 report's per-GLB bbox table.
const BARRIER_SCALE := 12.0

## --- item 3: grandstands -----------------------------------------------------
## Outfield run of a grandstand row: road edge (W/2) + the berm + 8 m of clear
## ground, i.e. it never stands on the embankment ramp.
const GRANDSTAND_RUN := 8.0
const GRANDSTAND_SCALE := 9.0
const RACING_GRANDSTAND_SCALE := 10.0

## --- item 4: S/F gantry ------------------------------------------------------
## The gantry GLB is 1.26 m wide on its local X axis, so 14x gives a 17.6 m
## beam — comfortably >= the 16 m track width (`gantry_span()`).
const GANTRY_SCALE := 14.0

## --- item 5: S/F checker paint ----------------------------------------------
const CHECKER_COLUMNS := 8
const CHECKER_ROWS := 2
const CHECKER_LENGTH := 1.5
## Lift of the paint quad over the road surface (m). Small, but not so small
## that it z-fights the road strip at distance.
const CHECKER_LIFT := 0.02

## --- item 6: sponsor billboards ---------------------------------------------
const BILLBOARD_OFFSET := 12.0
const BILLBOARD_SIZE := Vector2(4.0, 2.0)
const BILLBOARD_HEIGHT := 3.5
const BILLBOARD_PER_STRAIGHT := 5
const BILLBOARD_TEXTS: Array[String] = [
	"ULTRADRIVE", "APEX TYRES", "KENNEY AUTO", "GARAGE 51", "NORTHERN ISLE",
	"TURBO FUEL", "V6 MOTORSPORT", "PIT STOP 24", "OCTANE OIL", "SLIPSTREAM",
]
const BILLBOARD_COLORS: Array[Color] = [
	Color(0.84, 0.16, 0.13), Color(0.10, 0.32, 0.78), Color(0.93, 0.70, 0.12),
	Color(0.12, 0.60, 0.32), Color(0.86, 0.86, 0.88), Color(0.55, 0.16, 0.70),
]

## --- item 7: infield + light poles ------------------------------------------
const TENT_SCALE := 8.0
const GARAGE_SCALE := 9.0
const LIGHT_POLE_COUNT := 8
const LIGHT_POLE_OFFSET := 34.0
const LIGHT_POLE_SCALE := 12.0

## Front-straight arcs the three `grandstand.glb` rows sit on (span E, span E,
## span A — all on the flat +Z straight). The back-straight `racing_grandstand`
## sits at the midpoint of span C.
const GRANDSTAND_ARCS: Array[float] = [795.0, 855.0, 45.0]
const BACK_STRAIGHT_ARC := 450.0

## Infield footprints (XZ). All are >= 30 m clear of the centerline.
const TENT_POSITIONS: Array[Vector3] = [
	Vector3(-40.0, 0.0, 12.0),
	Vector3(-40.0, 0.0, -12.0),
]
const GARAGE_POSITION := Vector3(40.0, 0.0, 0.0)

## Uniform tint for the procedural fence posts / panel strip.
const FENCE_POST_COLOR := Color(0.30, 0.31, 0.34)
const FENCE_PANEL_COLOR := Color(0.14, 0.15, 0.17, 0.55)

## Backing store, written by configure().
var _centerline: Array[Vector3] = []
var _bank_points: PackedFloat32Array = PackedFloat32Array()
var _width: float = NorthernIsleLayout.WIDTH
## `Callable(Vector3) -> float`; called with `Vector3(x, 0, z)`. Empty is valid.
var _terrain_height: Callable = Callable()

## Deterministic output (rebuilt from scratch by every build()).
var _fence_posts: Array[Transform3D] = []
var _barriers: Array[Transform3D] = []
var _grandstand_rows: Array[Transform3D] = []
var _racing_grandstand_rows: Array[Transform3D] = []
var _billboards: Array[Transform3D] = []
var _billboard_texts: PackedStringArray = PackedStringArray()
var _light_poles: Array[Transform3D] = []
var _tents: Array[Transform3D] = []
var _garages: Array[Transform3D] = []
var _gantry := Transform3D()
var _gantry_ok := false
var _checker := Transform3D()
var _checker_ok := false
var _dropped: PackedStringArray = PackedStringArray()

## Mesh cache (path -> ArrayMesh; recentred). `_meshes` holds the same values
## keyed by KIND so the suite can assert a kind's surface/vertex counts.
var _mesh_cache: Dictionary = {}
var _meshes: Dictionary = {}

var _built := false
var _measured_perimeter := -1.0

## --- API ---------------------------------------------------------------------

## Stores the geometry the dressing is placed against. `centerline` is the same
## uniformly-sampled 304-point chain the mesh is built from (used here for the
## loop metric that sizes the fence/barrier runs); `bank_profile` is the signed
## radian bank per chain point (used for the cross-section angle, so the
## dressing follows the SAME profile the road mesh consumes). `terrain_height`
## is optional — every consumer falls back to the layout's frame math.
func configure(centerline: Array[Vector3], bank_profile: PackedFloat32Array, width: float, \
		terrain_height: Callable = Callable()) -> void:
	_centerline = []
	_centerline.append_array(centerline)
	_bank_points = bank_profile.duplicate()
	_width = width if width > 0.0 else NorthernIsleLayout.WIDTH
	_terrain_height = terrain_height
	_measured_perimeter = -1.0

## Builds every dressing batch. Idempotent: existing children are removed
## first, and every output array is reset, so re-running is bit-identical
## (there is no RNG in this builder).
func build() -> void:
	_clear_children()
	_fence_posts.clear()
	_barriers.clear()
	_grandstand_rows.clear()
	_racing_grandstand_rows.clear()
	_billboards.clear()
	_billboard_texts = PackedStringArray()
	_light_poles.clear()
	_tents.clear()
	_garages.clear()
	_gantry = Transform3D()
	_gantry_ok = false
	_checker = Transform3D()
	_checker_ok = false
	_dropped = PackedStringArray()
	_meshes.clear()

	_build_fence()
	_build_barrier_line()
	_build_grandstands()
	_build_gantry()
	_build_checker_paint()
	_build_billboards()
	_build_infield()
	_build_light_poles()
	_built = true

func is_built() -> bool:
	return _built

## --- query helpers -----------------------------------------------------------

func fence_posts() -> Array[Transform3D]:
	return _copy_xforms(_fence_posts)

func barrier_transforms() -> Array[Transform3D]:
	return _copy_xforms(_barriers)

## Both grandstand kinds, in build order (3 front-straight rows, then the
## back-straight racing grandstand).
func grandstand_transforms() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.append_array(_grandstand_rows)
	out.append_array(_racing_grandstand_rows)
	return out

func billboard_transforms() -> Array[Transform3D]:
	return _copy_xforms(_billboards)

func billboard_labels() -> PackedStringArray:
	var out := PackedStringArray()
	out.append_array(_billboard_texts)
	return out

func light_pole_transforms() -> Array[Transform3D]:
	return _copy_xforms(_light_poles)

func tent_transforms() -> Array[Transform3D]:
	return _copy_xforms(_tents)

func garage_transforms() -> Array[Transform3D]:
	return _copy_xforms(_garages)

## The single S/F gantry. `Transform3D()` when the GLB could not be loaded
## (check `gantry_ok()`), so a caller can never be handed a silent identity.
func gantry_transform() -> Transform3D:
	return _gantry

func gantry_ok() -> bool:
	return _gantry_ok

func gantry_center() -> Vector3:
	return _gantry.origin

## World-space span of the loaded gantry along its placed beam axis (m).
func gantry_span() -> float:
	var mesh := prop_mesh(KIND_GANTRY)
	if mesh == null:
		return 0.0
	return mesh.get_aabb().size.x * GANTRY_SCALE

func checker_transform() -> Transform3D:
	return _checker

func checker_ok() -> bool:
	return _checker_ok

## Number of placed instances of `kind`, or 0 for an unknown / dropped kind.
func count_of(kind: String) -> int:
	match kind:
		KIND_FENCE_POST:
			return _fence_posts.size()
		KIND_BARRIER:
			return _barriers.size()
		KIND_GRANDSTAND:
			return _grandstand_rows.size()
		KIND_RACING_GRANDSTAND:
			return _racing_grandstand_rows.size()
		KIND_GANTRY:
			return 1 if _gantry_ok else 0
		KIND_BILLBOARD:
			return _billboards.size()
		KIND_LIGHT_POLE:
			return _light_poles.size()
		KIND_TENT:
			return _tents.size()
		KIND_GARAGE:
			return _garages.size()
	return 0

## Every GROUND-BOUND dressing transform (fence, barrier, grandstands,
## billboards, light poles, tents, garage). The gantry and the paint quad are
## deliberately excluded: they sit on/over the carriageway by design. This is
## the list the "nothing overlaps the road corridor" gate walks.
func ground_transforms() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.append_array(_fence_posts)
	out.append_array(_barriers)
	out.append_array(_grandstand_rows)
	out.append_array(_racing_grandstand_rows)
	out.append_array(_billboards)
	out.append_array(_light_poles)
	out.append_array(_tents)
	out.append_array(_garages)
	return out

## Fence line lateral distance from the centerline (m): `W/2 + FENCE_OFFSET`.
func fence_offset() -> float:
	return _width * 0.5 + FENCE_OFFSET

## The recentred `ArrayMesh` a kind is instanced from (null when unbuilt or
## dropped). Lets the gate assert surface/vertex counts on the real GLB.
func prop_mesh(kind: String) -> ArrayMesh:
	var mesh: ArrayMesh = _meshes.get(kind, null)
	return mesh

## GLB paths that actually loaded (non-empty mesh) during the last build().
func referenced_glb_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for path: String in [PATH_BARRIER, PATH_GRANDSTAND, PATH_RACING_GRANDSTAND, PATH_GANTRY,
			PATH_LIGHT_POLE, PATH_TENT, PATH_GARAGE]:
		if _mesh_cache.has(path) and _mesh_cache[path] != null:
			out.append(path)
	return out

## Kinds dropped because their GLB was missing or yielded no vertices.
func dropped_kinds() -> PackedStringArray:
	var out := PackedStringArray()
	out.append_array(_dropped)
	return out

## A deterministic, human-readable dump of every placed transform — the cheap
## way to prove two builds are identical.
func signature() -> PackedStringArray:
	var out := PackedStringArray()
	out.append_array(_signature_for(KIND_FENCE_POST, _fence_posts))
	out.append_array(_signature_for(KIND_BARRIER, _barriers))
	out.append_array(_signature_for(KIND_GRANDSTAND, _grandstand_rows))
	out.append_array(_signature_for(KIND_RACING_GRANDSTAND, _racing_grandstand_rows))
	out.append_array(_signature_for(KIND_BILLBOARD, _billboards))
	out.append_array(_signature_for(KIND_LIGHT_POLE, _light_poles))
	out.append_array(_signature_for(KIND_TENT, _tents))
	out.append_array(_signature_for(KIND_GARAGE, _garages))
	if _gantry_ok:
		out.append("%s %s" % [KIND_GANTRY, _fmt_xform(_gantry)])
	if _checker_ok:
		out.append("%s %s" % [KIND_CHECKER_TAG, _fmt_xform(_checker)])
	return out

## --- item 1: catch fence -----------------------------------------------------

func _build_fence() -> void:
	var n := _run_count(FENCE_POST_SPACING)
	for j in n:
		var arc := float(j) * FENCE_POST_SPACING
		var frame := _frame_at(arc)
		var base := _on_cross(frame, fence_offset())
		base.y = _fence_base_y(frame)
		_fence_posts.append(_flat_transform(base, _yaw_along(frame["forward"] as Vector3)))
	if _fence_posts.is_empty():
		_dropped.append(KIND_FENCE_POST)
		return
	var post_mesh := _centered_box(FENCE_POST_SIZE)
	_meshes[KIND_FENCE_POST] = post_mesh
	add_child(_multimesh_node("FencePosts", post_mesh, _fence_posts, _simple_material(FENCE_POST_COLOR)))
	_build_fence_panel()

func _build_fence_panel() -> void:
	var n := _fence_posts.size()
	if n < 3:
		_dropped.append(KIND_FENCE_PANEL)
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var a: Vector3 = _fence_posts[i].origin
		var b: Vector3 = _fence_posts[(i + 1) % n].origin
		var a0 := a + Vector3.UP * FENCE_PANEL_BOTTOM
		var a1 := a + Vector3.UP * FENCE_PANEL_TOP
		var b0 := b + Vector3.UP * FENCE_PANEL_BOTTOM
		var b1 := b + Vector3.UP * FENCE_PANEL_TOP
		_add_quad(st, a0, a1, b1, b0)
	st.generate_normals()
	var panel := st.commit()
	_meshes[KIND_FENCE_PANEL] = panel
	var mat := StandardMaterial3D.new()
	mat.albedo_color = FENCE_PANEL_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.6
	var mi := MeshInstance3D.new()
	mi.name = "FencePanel"
	mi.mesh = panel
	mi.material_override = mat
	add_child(mi)

## --- item 2: barrier line ----------------------------------------------------

func _build_barrier_line() -> void:
	var mesh := _load_centered_mesh(PATH_BARRIER)
	if not _mesh_usable(mesh):
		_dropped.append(KIND_BARRIER)
		return
	var n := _run_count(BARRIER_SPACING)
	for j in n:
		var arc := float(j) * BARRIER_SPACING
		var frame := _frame_at(arc)
		var base := _on_cross(frame, _width * 0.5 + BARRIER_OFFSET)
		base.y = _surface_base_y(frame, _width * 0.5 + BARRIER_OFFSET)
		_barriers.append(_scaled_transform(base, _yaw_along(frame["forward"] as Vector3), BARRIER_SCALE))
	if _barriers.is_empty():
		_dropped.append(KIND_BARRIER)
		return
	_meshes[KIND_BARRIER] = mesh
	add_child(_multimesh_node("BarrierLine", mesh, _barriers, _native_material(mesh)))

## --- item 3: grandstands -----------------------------------------------------

func _build_grandstands() -> void:
	var run := _width * 0.5 + NorthernIsleLayout.EMBANK_RUN + GRANDSTAND_RUN
	var mesh := _load_centered_mesh(PATH_GRANDSTAND)
	if _mesh_usable(mesh):
		for arc: float in GRANDSTAND_ARCS:
			var frame := _frame_at(arc)
			var spot := _on_cross(frame, run)
			spot.y = _ground_y(spot)
			_grandstand_rows.append(_scaled_transform(spot, _yaw_facing_track(frame), GRANDSTAND_SCALE))
		if not _grandstand_rows.is_empty():
			_meshes[KIND_GRANDSTAND] = mesh
			add_child(_multimesh_node("Grandstands", mesh, _grandstand_rows, _native_material(mesh)))
		else:
			_dropped.append(KIND_GRANDSTAND)
	else:
		_dropped.append(KIND_GRANDSTAND)

	var racing_mesh := _load_centered_mesh(PATH_RACING_GRANDSTAND)
	if not _mesh_usable(racing_mesh):
		_dropped.append(KIND_RACING_GRANDSTAND)
		return
	var back := _frame_at(BACK_STRAIGHT_ARC)
	var back_spot := _on_cross(back, run)
	back_spot.y = _ground_y(back_spot)
	_racing_grandstand_rows.append(_scaled_transform(back_spot, _yaw_facing_track(back), RACING_GRANDSTAND_SCALE))
	_meshes[KIND_RACING_GRANDSTAND] = racing_mesh
	add_child(_multimesh_node("RacingGrandstand", racing_mesh, _racing_grandstand_rows, _native_material(racing_mesh)))

## --- item 4: S/F gantry ------------------------------------------------------

## Centred on checkpoint 7 (`NorthernIsleLayout.start_line_arc()`, 787.4 m — on
## the flat front straight) with its beam ACROSS the road: the GLB's long axis
## is its local X (measured 1.26 m), so the basis aligns local X with the road's
## horizontal `right` and the 14x scale gives a 17.6 m span >= WIDTH. Because
## cp7 is on a straight (theta = 0) the placement is also perfectly flat.
func _build_gantry() -> void:
	var mesh := _load_centered_mesh(PATH_GANTRY)
	if not _mesh_usable(mesh):
		_dropped.append(KIND_GANTRY)
		return
	var frame := _frame_at(NorthernIsleLayout.start_line_arc())
	var spot: Vector3 = frame["center"]
	_meshes[KIND_GANTRY] = mesh
	_gantry = _scaled_transform(spot, _yaw_across(frame["right"] as Vector3), GANTRY_SCALE)
	_gantry_ok = true
	var mi := MeshInstance3D.new()
	mi.name = "FinishGantry"
	mi.mesh = mesh
	mi.transform = _gantry
	var mat := _native_material(mesh)
	if mat != null:
		mi.material_override = mat
	add_child(mi)

## --- item 5: S/F checker paint ----------------------------------------------

func _build_checker_paint() -> void:
	var frame := _frame_at(NorthernIsleLayout.start_line_arc())
	var spot: Vector3 = frame["center"]
	spot.y += CHECKER_LIFT
	var plane := PlaneMesh.new()
	plane.size = Vector2(_width, CHECKER_LENGTH)
	plane.material = _checker_material()
	var mi := MeshInstance3D.new()
	mi.name = "StartFinishPaint"
	mi.mesh = plane
	mi.transform = Transform3D(_flat_basis(frame["right"] as Vector3, frame["forward"] as Vector3), spot)
	_checker = mi.transform
	_checker_ok = true
	add_child(mi)

func _checker_material() -> StandardMaterial3D:
	var img := Image.create_empty(CHECKER_COLUMNS, CHECKER_ROWS, false, Image.FORMAT_RGBA8)
	for x in CHECKER_COLUMNS:
		for y in CHECKER_ROWS:
			var dark := (x + y) % 2 == 0
			img.set_pixel(x, y, Color.BLACK if dark else Color.WHITE)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 0.9
	return mat

## --- item 6: sponsor billboards ---------------------------------------------

## `BILLBOARD_PER_STRAIGHT` quads on each straight, `BILLBOARD_OFFSET` m out
## from the centerline (beyond the fence line at `W/2 + 0.6`), each with a
## `Label3D` brand child. The front straight runs at z = +R and its outfield is
## +Z; the back straight runs at z = -R with its outfield at -Z (travel is -X
## there, so `right = forward x UP` is -Z).
func _build_billboards() -> void:
	var quad := QuadMesh.new()
	quad.size = BILLBOARD_SIZE
	quad.orientation = PlaneMesh.FACE_Z
	for straight in 2:
		var front := straight == 0
		var z_sign := 1.0 if front else -1.0
		var right := Vector3(0.0, 0.0, z_sign)
		var half := NorthernIsleLayout.HALF_STRAIGHT + NorthernIsleLayout.TURN_RADIUS
		for i in BILLBOARD_PER_STRAIGHT:
			var t := (float(i) + 0.5) / float(BILLBOARD_PER_STRAIGHT)
			var x := lerpf(0.0, half * 0.8, (t - 0.5) * 2.0)
			var spot := Vector3(x, 0.0, NorthernIsleLayout.TURN_RADIUS * z_sign + BILLBOARD_OFFSET * z_sign)
			spot.y = _ground_y(spot) + BILLBOARD_HEIGHT
			var index := _billboards.size() % BILLBOARD_TEXTS.size()
			# The recorded transform and the rendered node are the SAME basis: the
			# quad faces across the straight at its own track side. (An earlier
			# draft stored this yaw but rendered `_flat_basis(right, forward)`, so
			# the placed board and the query disagreed by 90 degrees.)
			var xform := _flat_transform(spot, _yaw_facing_inward(right))
			_billboards.append(xform)
			_billboard_texts.append(BILLBOARD_TEXTS[index])
			add_child(_billboard_node(index, quad, xform))
	if _billboards.is_empty():
		_dropped.append(KIND_BILLBOARD)
	else:
		_meshes[KIND_BILLBOARD] = quad

func _billboard_node(index: int, quad: QuadMesh, xform: Transform3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Billboard%d" % index
	root.transform = xform
	var mi := MeshInstance3D.new()
	mi.name = "Board"
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BILLBOARD_COLORS[index % BILLBOARD_COLORS.size()]
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.75
	mi.material_override = mat
	root.add_child(mi)
	var label := Label3D.new()
	label.name = "Brand"
	label.text = BILLBOARD_TEXTS[index]
	label.font_size = 64
	label.pixel_size = 0.014
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 1.0, 1.0)
	label.outline_size = 12
	label.outline_modulate = Color(0.0, 0.0, 0.0)
	label.position = Vector3(0.0, 0.0, 0.06)
	root.add_child(label)
	return root

## --- item 7: infield tents / pit garage + light poles -----------------------

func _build_infield() -> void:
	var tent_mesh := _load_centered_mesh(PATH_TENT)
	if _mesh_usable(tent_mesh):
		for spot: Vector3 in TENT_POSITIONS:
			var grounded := Vector3(spot.x, _ground_y(spot), spot.z)
			_tents.append(_scaled_transform(grounded, 0.0, TENT_SCALE))
		_meshes[KIND_TENT] = tent_mesh
		add_child(_multimesh_node("InfieldTents", tent_mesh, _tents, _native_material(tent_mesh)))
	else:
		_dropped.append(KIND_TENT)

	var garage_mesh := _load_centered_mesh(PATH_GARAGE)
	if not _mesh_usable(garage_mesh):
		_dropped.append(KIND_GARAGE)
		return
	var ground := Vector3(GARAGE_POSITION.x, _ground_y(GARAGE_POSITION), GARAGE_POSITION.z)
	_garages.append(_scaled_transform(ground, 0.0, GARAGE_SCALE))
	_meshes[KIND_GARAGE] = garage_mesh
	add_child(_multimesh_node("PitGarage", garage_mesh, _garages, _native_material(garage_mesh)))

## 8 poles spread evenly in arc around the whole loop, out on the plain beyond
## the berm. PLACED ONLY — plan §6 risk 10: no light, no night listener.
func _build_light_poles() -> void:
	var mesh := _load_centered_mesh(PATH_LIGHT_POLE)
	if not _mesh_usable(mesh):
		_dropped.append(KIND_LIGHT_POLE)
		return
	var step := _perimeter() / float(LIGHT_POLE_COUNT)
	for j in LIGHT_POLE_COUNT:
		var frame := _frame_at(float(j) * step)
		var spot := _on_cross(frame, LIGHT_POLE_OFFSET)
		spot.y = _ground_y(spot)
		_light_poles.append(_scaled_transform(spot, _yaw_along(frame["forward"] as Vector3), LIGHT_POLE_SCALE))
	_meshes[KIND_LIGHT_POLE] = mesh
	add_child(_multimesh_node("LightPoles", mesh, _light_poles, _native_material(mesh)))

## --- placement math ----------------------------------------------------------

## The arc parameterisation is `NorthernIsleLayout`'s uniform 304-point chain:
## placement goes through `frame_at_arc()`/`point_at_arc()` (the same frames the
## road mesh is built from), never a re-derived spline. `_perimeter()` is
## measured from the chain the caller registered when there is one, so the
## fence/barrier run count follows that chain.
func _frame_at(arc: float) -> Dictionary:
	var frame := NorthernIsleLayout.frame_at_arc(arc)
	var angle := _bank_at_arc(arc)
	var right: Vector3 = frame["right"]
	var cross := right * cos(angle) - Vector3.UP * sin(angle)
	return {
		"center": frame["center"],
		"forward": frame["forward"],
		"right": right,
		"cross": cross,
		"bank": angle,
	}

## Bank angle (rad) at `arc`, interpolated from the caller's profile so the
## dressing follows the SAME profile the mesh consumes. Falls back to the
## layout's continuous query when no (or a wrongly-sized) profile was passed.
func _bank_at_arc(arc: float) -> float:
	if _bank_points.size() != NorthernIsleLayout.TOTAL_POINTS:
		return NorthernIsleLayout.bank_rad_at_arc(arc)
	var n := _bank_points.size()
	var x := fposmod(arc, NorthernIsleLayout.perimeter()) / NorthernIsleLayout.spacing()
	var i0 := int(floor(x)) % n
	var i1 := (i0 + 1) % n
	var t := x - floorf(x)
	return lerpf(_bank_points[i0], _bank_points[i1], t)

## A point on the banked cross-section at lateral `offset` (positive = outfield,
## right of travel).
func _on_cross(frame: Dictionary, offset: float) -> Vector3:
	var center: Vector3 = frame["center"]
	var cross: Vector3 = frame["cross"]
	return center + cross * offset

## Fence/barrier base height: the terrain at the pole's XZ when a callable was
## configured, else the road-edge height straight from the frame math (the
## documented fallback).
func _surface_base_y(frame: Dictionary, offset: float) -> float:
	if _terrain_height.is_valid():
		var probe := _on_cross(frame, offset)
		probe.y = 0.0
		return _terrain_height.call(probe)
	return _on_cross(frame, offset).y

func _fence_base_y(frame: Dictionary) -> float:
	return _surface_base_y(frame, fence_offset())

## Terrain height at a world XZ, falling back to the ground plain (`PLAIN_Y`).
func _ground_y(spot: Vector3) -> float:
	if _terrain_height.is_valid():
		return _terrain_height.call(Vector3(spot.x, 0.0, spot.z))
	return NorthernIsleLayout.PLAIN_Y

## Loop length used to size the fence/barrier runs: the closed-chain length of
## the configured centerline when there is one, else the layout's analytic
## perimeter.
func _perimeter() -> float:
	if _measured_perimeter >= 0.0:
		return _measured_perimeter
	if _centerline.size() < 2:
		_measured_perimeter = NorthernIsleLayout.perimeter()
		return _measured_perimeter
	var total := 0.0
	var n := _centerline.size()
	for i in n:
		total += _centerline[i].distance_to(_centerline[(i + 1) % n])
	_measured_perimeter = total if total > 0.0 else NorthernIsleLayout.perimeter()
	return _measured_perimeter

func _run_count(spacing: float) -> int:
	return int(ceil(_perimeter() / spacing))

## --- transform helpers -------------------------------------------------------

## Yaw that puts local +X along `dir` (dir is horizontal).
func _yaw_across(dir: Vector3) -> float:
	return atan2(-dir.z, dir.x)

## Yaw that puts local +Z along `dir` (dir is horizontal).
func _yaw_facing(dir: Vector3) -> float:
	return atan2(dir.x, dir.z)

## Yaw that puts local +Z along the travel direction: fence/barrier segment runs
## ALONG the road (the barrier GLB's long axis is its local X, hatched by
## `_scaled_transform`'s basis, so this keeps it parallel to the curb).
func _yaw_along(forward: Vector3) -> float:
	return _yaw_across(forward)

## Grandstand rows face the track: local +Z points inward, i.e. against the
## outfield `right`.
func _yaw_facing_track(frame: Dictionary) -> float:
	var right: Vector3 = frame["right"]
	return _yaw_facing(-right)

## Billboard quads face their own straight's track side.
func _yaw_facing_inward(right: Vector3) -> float:
	return _yaw_facing(-right)

func _flat_basis(right: Vector3, forward: Vector3) -> Basis:
	var x := right
	x.y = 0.0
	x = x.normalized()
	var z := forward
	z.y = 0.0
	z = z.normalized()
	# Right-handed: X x Y == Z requires X = -right when Z = forward.
	return Basis(-x, Vector3.UP, z)

func _flat_transform(origin: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), origin)

func _scaled_transform(origin: Vector3, yaw: float, uniform_scale: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * uniform_scale), origin)

func _add_quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	st.add_vertex(p0)
	st.add_vertex(p1)
	st.add_vertex(p2)
	st.add_vertex(p0)
	st.add_vertex(p2)
	st.add_vertex(p3)

func _multimesh_node(node_name: String, mesh: ArrayMesh, xforms: Array[Transform3D], mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	return mmi

## --- mesh helpers (the `prop_scatterer.gd` loader, plus a recentre) ----------

## Native surface materials are preserved for MultiMesh instancing; a fused
## multi-node GLB falls back to a flat override (see `_native_material`).
func _native_material(mesh: ArrayMesh) -> Material:
	if mesh == null or mesh.get_surface_count() == 0:
		return _simple_material(Color(0.62, 0.62, 0.65))
	if mesh.surface_get_material(0) != null:
		return null
	return _simple_material(Color(0.62, 0.62, 0.65))

func _simple_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat

func _mesh_usable(mesh: ArrayMesh) -> bool:
	if mesh == null or mesh.get_surface_count() == 0:
		return false
	var arrays := mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return false
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return vertices.size() > 0

## Loads a GLB, bakes its node transform into one `ArrayMesh`, and RECENTRES it:
## XZ centre at the origin, base (min Y) at Y 0. Placement is therefore exact —
## the Kenney kit bakes an origin offset into every node (`t = [-0.35, -0.01,
## -0.65]`), which would otherwise shift a 14x gantry 7.8 m off its arc.
func _load_centered_mesh(path: String) -> ArrayMesh:
	if _mesh_cache.has(path):
		var cached: ArrayMesh = _mesh_cache[path]
		return cached
	var mesh: ArrayMesh = null
	var scene := load(path) as PackedScene
	if scene != null:
		var inst := scene.instantiate()
		var entries: Array = []
		_collect_mesh_instances(inst, entries, Transform3D.IDENTITY)
		inst.free()
		if entries.size() == 1:
			mesh = _bake_prop_mesh(entries[0][0] as ArrayMesh, entries[0][1] as Transform3D)
		elif entries.size() > 1:
			mesh = _fuse_entries(entries)
	if mesh != null:
		var aabb := mesh.get_aabb()
		var shift := Vector3(-aabb.get_center().x, -aabb.position.y, -aabb.get_center().z)
		mesh = _translate_mesh(mesh, shift)
	_mesh_cache[path] = mesh
	return mesh

## Bakes a GLB mesh (node transform included) surface by surface, re-attaching
## each surface's native material so MultiMesh instances keep their textures.
func _bake_prop_mesh(m: ArrayMesh, xform: Transform3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in m.get_surface_count():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(m, s, xform)
		st.generate_normals()
		var surf := st.commit()
		out.add_surface_from_arrays(surf.surface_get_primitive_type(0), surf.surface_get_arrays(0))
		var mat: Material = m.surface_get_material(s)
		if mat != null:
			out.surface_set_material(out.get_surface_count() - 1, mat)
	return out

func _collect_mesh_instances(node: Node, out: Array, accumulated: Transform3D) -> void:
	var local := accumulated
	if node is Node3D:
		local = accumulated * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var m: Mesh = mi.mesh
		if m != null and m is ArrayMesh:
			out.append([m, local])
	for child in node.get_children():
		_collect_mesh_instances(child, out, local)

func _fuse_entries(entries: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for entry in entries:
		var m: ArrayMesh = entry[0]
		var xform: Transform3D = entry[1]
		for s in m.get_surface_count():
			st.append_from(m, s, xform)
	st.generate_normals()
	return st.commit()

func _translate_mesh(m: ArrayMesh, shift: Vector3) -> ArrayMesh:
	var out := ArrayMesh.new()
	var xform := Transform3D(Basis.IDENTITY, shift)
	for s in m.get_surface_count():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(m, s, xform)
		var surf := st.commit()
		out.add_surface_from_arrays(surf.surface_get_primitive_type(0), surf.surface_get_arrays(0))
		var mat: Material = m.surface_get_material(s)
		if mat != null:
			out.surface_set_material(out.get_surface_count() - 1, mat)
	return out

func _centered_box(box_size: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := BoxMesh.new()
	box.size = box_size
	st.append_from(box, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, box_size.y * 0.5, 0.0)))
	return st.commit()

## --- misc --------------------------------------------------------------------

func _clear_children() -> void:
	for child in get_children():
		remove_child(child)
		child.free()

func _copy_xforms(source: Array[Transform3D]) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.append_array(source)
	return out

## Signature lines for one kind. RETURNS the lines rather than appending into a
## caller-supplied array: `PackedStringArray` is a value type, so an in-place
## append into a parameter would never reach the caller (an earlier draft did
## exactly that and produced a signature holding only the gantry + checker lines).
func _signature_for(kind: String, xforms: Array[Transform3D]) -> PackedStringArray:
	var out := PackedStringArray()
	for xform: Transform3D in xforms:
		out.append("%s %s" % [kind, _fmt_xform(xform)])
	return out

func _fmt_xform(xform: Transform3D) -> String:
	var o := xform.origin
	var b := xform.basis
	return "(%.4f,%.4f,%.4f)|(%.4f,%.4f,%.4f,%.4f,%.4f,%.4f)" % [
		o.x, o.y, o.z, b.x.x, b.x.y, b.x.z, b.z.x, b.z.y, b.z.z]
