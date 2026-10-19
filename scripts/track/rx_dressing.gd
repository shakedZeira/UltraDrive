# scripts/track/rx_dressing.gd
class_name RxDressing
extends Node3D

## P3 — Rallycross dressing for Circuit de Barcelona-Catalunya
## (docs/plans/track_barcelona_rallycross.md §3.4).
##
## A small DEDICATED polyline builder, NOT `OvalDressing` (plan §2.4: the oval
## class is hard-wired to `NorthernIsleLayout`'s fence/grandstand/billboard item
## set). Mirrors `oval_dressing.gd`'s proven shape — MultiMesh + GLB
## mesh-harvesting, deterministic, no RNG — but places the rallycross item set
## from `BarcelonaRxLayout`'s own frame math, so the dressing and the dirt mesh
## can never disagree about where the road edge is.
##
## WHAT IT BUILDS (plan §3.4 items 1-5)
##   1. S/F gantry   — `finish_gantry.glb` straddling the road at the start/finish
##      line (`start_line_arc()`, 991.375 m — on the start straight, bank 0);
##   2. S/F paint    — a generated 8x2 checker on a `WIDTH x 1.5` m quad at +0.02;
##   3. barrier line — `racing_barrier_red.glb` MultiMesh at 4 m pitch on the
##      OUTSIDE of every arc in `barrier_arc_ranges()` (T1, T2, T6);
##   4. apex cones   — `track_cone.glb` MultiMesh, a small arc run at each of the
##      7 named corner apexes, tucked just inside the road edge (ON the dirt by
##      design, so they are exposed via `cone_transforms()` and kept OUT of
##      `ground_transforms()`);
##   5. start flag   — `racing_flag_checkers.glb`, one instance beside the gantry.
##
## Explicitly OUT of scope (plan §3.4): catch fencing, grandstands, billboards,
## light poles, paddock tents — a club-level RX venue is the right read.
##
## DETERMINISM: no RNG, no wall clock, every loop is arc/constant driven, so two
## `build()` runs on one object produce bit-identical transform sets (pinned by
## the P3 suite).
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
##   barrier_transforms() / cone_transforms() / flag_transforms()
##   gantry_transform() / gantry_ok() / gantry_center() / gantry_span()
##   checker_transform() / checker_ok()
##   count_of(kind) / ground_transforms() / signature() / perimeter()
##   prop_mesh(kind) / referenced_glb_paths() / dropped_kinds()
##
## Chosen props that could not be loaded are DROPPED and named by
## `dropped_kinds()` rather than silently skipped.

## Prop kinds. `count_of(kind)` / `prop_mesh(kind)` key off these strings.
const KIND_BARRIER := "barrier"
const KIND_GANTRY := "gantry"
const KIND_CONE := "cone"
const KIND_FLAG := "flag"
## Not a placed GLB kind — the tag `signature()` uses for the S/F paint quad.
const KIND_CHECKER_TAG := "checker_paint"

## Referenced CC0 Kenney / Phase-A assets (read-only; never modified).
const PATH_BARRIER := "res://assets/track_props/racing_barrier_red.glb"
const PATH_GANTRY := "res://assets/track_props/finish_gantry.glb"
const PATH_CONE := "res://assets/track_props/track_cone.glb"
const PATH_FLAG := "res://assets/track_props/racing_flag_checkers.glb"

## --- item 1: S/F gantry ------------------------------------------------------
## The gantry GLB is 1.26 m wide on its local X axis (measured from the GLB
## accessor bounds), so 14x gives a 17.6 m beam — comfortably >= the 12 m track
## width (`gantry_span()`). Same scale the oval uses (oval_dressing.gd:106).
const GANTRY_SCALE := 14.0

## --- item 2: S/F checker paint ----------------------------------------------
const CHECKER_COLUMNS := 8
const CHECKER_ROWS := 2
const CHECKER_LENGTH := 1.5
## Lift of the paint quad over the dirt surface (m). Small, but not so small
## that it z-fights the road strip at distance.
const CHECKER_LIFT := 0.02

## --- item 3: barrier line ----------------------------------------------------
## Lateral offset beyond the outer road edge (plan §3.4: `WIDTH/2 + 1.6`).
const BARRIER_OFFSET := 1.6
## Segment pitch measured in ARC length (m).
const BARRIER_SPACING := 4.0
## The barrier GLB is 0.25 m long x 0.1312 m tall on its local axes (measured
## from the GLB accessor bounds), so a 12x uniform scale makes one segment 3.0 m
## long x 1.5744 m tall.
const BARRIER_SCALE := 12.0
## Visual top of the red barrier GLB at `BARRIER_SCALE` (m above its base line):
## 0.1312 * 12 = 1.5744, named here (to 2 dp, matching the oval's precedent) so
## `barcelona_rx.gd` can derive its collider rise WITHOUT importing the scale.
## Held honest by the barrier gate.
const RED_BARRIER_VISUAL_TOP := 1.57

## --- item 4: apex cones ------------------------------------------------------
## The cone GLB is 0.12 m wide x 0.132 m tall on its local axes, so 4x gives a
## ~0.48 m wide x 0.53 m tall cone (a real traffic cone).
const CONE_SCALE := 4.0
## How far inside the road edge a cone sits (m): `W/2 - CONE_INSET`.
const CONE_INSET := 1.0
## Half-width of the arc run of cones around a corner apex (m).
const CONE_ARC_HALF := 6.0
## Arc pitch between cones in a run (m).
const CONE_SPACING := 4.0

## --- item 5: start flag ------------------------------------------------------
## The flag GLB is 0.1972 m wide x 1.25 m tall on its local axes, so 2.5x gives
## a ~0.49 m wide x 3.13 m tall flag on its pole.
const FLAG_SCALE := 2.5
## Lateral offset of the flag beyond the road edge (m): `W/2 + FLAG_OFFSET`.
## Placed outfield of the barrier line so it never intrudes on the carriageway.
const FLAG_OFFSET := 3.2

## Backing store, written by configure().
var _centerline: Array[Vector3] = []
var _bank_points: PackedFloat32Array = PackedFloat32Array()
var _width: float = BarcelonaRxLayout.WIDTH
## `Callable(Vector3) -> float`; called with `Vector3(x, 0, z)`. Empty is valid.
var _terrain_height: Callable = Callable()

## Deterministic output (rebuilt from scratch by every build()).
var _barriers: Array[Transform3D] = []
var _cones: Array[Transform3D] = []
var _flags: Array[Transform3D] = []
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
## uniformly-sampled 400-point chain the mesh is built from (used here for the
## loop metric `perimeter()`); `bank_profile` is the signed radian bank per chain
## point (used for the cross-section angle, so the dressing follows the SAME
## profile the road mesh consumes). `terrain_height` is optional — every consumer
## falls back to the layout's frame math.
func configure(centerline: Array[Vector3], bank_profile: PackedFloat32Array, width: float, \
		terrain_height: Callable = Callable()) -> void:
	_centerline = []
	_centerline.append_array(centerline)
	_bank_points = bank_profile.duplicate()
	_width = width if width > 0.0 else BarcelonaRxLayout.WIDTH
	_terrain_height = terrain_height
	_measured_perimeter = -1.0

## Builds every dressing batch. Idempotent: existing children are removed first,
## and every output array is reset, so re-running is bit-identical (there is no
## RNG in this builder).
func build() -> void:
	_clear_children()
	_barriers.clear()
	_cones.clear()
	_flags.clear()
	_gantry = Transform3D()
	_gantry_ok = false
	_checker = Transform3D()
	_checker_ok = false
	_dropped = PackedStringArray()
	_meshes.clear()

	_build_gantry()
	_build_checker_paint()
	_build_barrier_line()
	_build_apex_cones()
	_build_start_flag()
	_built = true

func is_built() -> bool:
	return _built

## --- query helpers -----------------------------------------------------------

func barrier_transforms() -> Array[Transform3D]:
	return _copy_xforms(_barriers)

func cone_transforms() -> Array[Transform3D]:
	return _copy_xforms(_cones)

func flag_transforms() -> Array[Transform3D]:
	return _copy_xforms(_flags)

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
		KIND_BARRIER:
			return _barriers.size()
		KIND_GANTRY:
			return 1 if _gantry_ok else 0
		KIND_CONE:
			return _cones.size()
		KIND_FLAG:
			return _flags.size()
	return 0

## Every GROUND-BOUND dressing transform that must stand CLEAR of the road
## corridor: the barrier line and the start flag. The gantry and the paint quad
## are deliberately excluded (they sit on/over the carriageway by design), and so
## are the apex cones (they sit ON the dirt by design — see `cone_transforms()`).
func ground_transforms() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.append_array(_barriers)
	out.append_array(_flags)
	return out

## Closed-chain length of the configured centerline (the layout's analytic
## perimeter when none was configured). Public so a suite can pin the metric
## `configure()` receives.
func perimeter() -> float:
	if _measured_perimeter >= 0.0:
		return _measured_perimeter
	if _centerline.size() < 2:
		_measured_perimeter = BarcelonaRxLayout.perimeter()
		return _measured_perimeter
	var total := 0.0
	var n := _centerline.size()
	for i in n:
		total += _centerline[i].distance_to(_centerline[(i + 1) % n])
	_measured_perimeter = total if total > 0.0 else BarcelonaRxLayout.perimeter()
	return _measured_perimeter

## The recentred `ArrayMesh` a kind is instanced from (null when unbuilt or
## dropped). Lets the gate assert surface/vertex counts on the real GLB.
func prop_mesh(kind: String) -> ArrayMesh:
	var mesh: ArrayMesh = _meshes.get(kind, null)
	return mesh

## GLB paths that actually loaded (non-empty mesh) during the last build().
func referenced_glb_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for path: String in [PATH_BARRIER, PATH_GANTRY, PATH_CONE, PATH_FLAG]:
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
	out.append_array(_signature_for(KIND_BARRIER, _barriers))
	out.append_array(_signature_for(KIND_CONE, _cones))
	out.append_array(_signature_for(KIND_FLAG, _flags))
	if _gantry_ok:
		out.append("%s %s" % [KIND_GANTRY, _fmt_xform(_gantry)])
	if _checker_ok:
		out.append("%s %s" % [KIND_CHECKER_TAG, _fmt_xform(_checker)])
	return out

## --- item 1: S/F gantry ------------------------------------------------------

## Centred on the start/finish line (`start_line_arc()`, 991.375 m — on the
## start straight, bank 0) with its beam ACROSS the road: the GLB's long axis is
## its local X (measured 1.26 m), so the basis aligns local X with the road's
## horizontal `right` and the 14x scale gives a 17.6 m span >= WIDTH.
func _build_gantry() -> void:
	var mesh := _load_centered_mesh(PATH_GANTRY)
	if not _mesh_usable(mesh):
		_dropped.append(KIND_GANTRY)
		return
	var frame := _frame_at(BarcelonaRxLayout.start_line_arc())
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

## --- item 2: S/F checker paint ----------------------------------------------

func _build_checker_paint() -> void:
	var frame := _frame_at(BarcelonaRxLayout.start_line_arc())
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

## --- item 3: barrier line ----------------------------------------------------

## `BARRIER_SPACING` m pitch along every arc in `barrier_arc_ranges()`, on the
## OUTFIELD side (`OUTFIELD_SIDE = -1`: a right-hand turn's outside is the LEFT
## of travel), at `W/2 + BARRIER_OFFSET`.
func _build_barrier_line() -> void:
	var mesh := _load_centered_mesh(PATH_BARRIER)
	if not _mesh_usable(mesh):
		_dropped.append(KIND_BARRIER)
		return
	var offset := BarcelonaRxLayout.OUTFIELD_SIDE * (_width * 0.5 + BARRIER_OFFSET)
	for r in BarcelonaRxLayout.barrier_arc_ranges():
		var from: float = r.x
		var to: float = r.y
		var count := int(ceil((to - from) / BARRIER_SPACING))
		for k in count:
			var arc := from + float(k) * BARRIER_SPACING
			var frame := _frame_at(arc)
			var base := _on_cross(frame, offset)
			base.y = _surface_base_y(frame, offset)
			_barriers.append(_scaled_transform(base, _yaw_along(frame["forward"] as Vector3), BARRIER_SCALE))
	if _barriers.is_empty():
		_dropped.append(KIND_BARRIER)
		return
	_meshes[KIND_BARRIER] = mesh
	add_child(_multimesh_node("BarrierLine", mesh, _barriers, _native_material(mesh)))

## --- item 4: apex cones ------------------------------------------------------

## A short run of cones around each of the 7 corner apexes, `CONE_INSET` inside
## the road edge. The inside of a right-hand turn is `+right`, i.e.
## `-OUTFIELD_SIDE`. Y comes from the FRAME math (the banked road surface), not
## the terrain provider: the terrain under the road is the washbed (WASHBED_DEPTH
## below the surface), so a terrain-read cone would sink into the dirt.
func _build_apex_cones() -> void:
	var mesh := _load_centered_mesh(PATH_CONE)
	if not _mesh_usable(mesh):
		_dropped.append(KIND_CONE)
		return
	var inner := -BarcelonaRxLayout.OUTFIELD_SIDE
	var offset := inner * (_width * 0.5 - CONE_INSET)
	var steps := maxi(1, int(CONE_ARC_HALF / CONE_SPACING))
	for corner in BarcelonaRxLayout.corner_names().size():
		var apex := BarcelonaRxLayout.corner_apex_arc(corner + 1)
		for k in range(-steps, steps + 1):
			var frame := _frame_at(apex + float(k) * CONE_SPACING)
			var base := _on_cross(frame, offset)
			_cones.append(_scaled_transform(base, _yaw_along(frame["forward"] as Vector3), CONE_SCALE))
	if _cones.is_empty():
		_dropped.append(KIND_CONE)
		return
	_meshes[KIND_CONE] = mesh
	add_child(_multimesh_node("ApexCones", mesh, _cones, _native_material(mesh)))

## --- item 5: start flag ------------------------------------------------------

## One checkered flag beside the gantry, outfield of the barrier line, facing the
## track so it is visible from the start straight.
func _build_start_flag() -> void:
	var mesh := _load_centered_mesh(PATH_FLAG)
	if not _mesh_usable(mesh):
		_dropped.append(KIND_FLAG)
		return
	var frame := _frame_at(BarcelonaRxLayout.start_line_arc())
	var offset := BarcelonaRxLayout.OUTFIELD_SIDE * (_width * 0.5 + FLAG_OFFSET)
	var base := _on_cross(frame, offset)
	base.y = _surface_base_y(frame, offset)
	_flags.append(_scaled_transform(base, \
		_yaw_facing((frame["right"] as Vector3) * BarcelonaRxLayout.OUTFIELD_SIDE), FLAG_SCALE))
	_meshes[KIND_FLAG] = mesh
	add_child(_multimesh_node("StartFlag", mesh, _flags, _native_material(mesh)))

## --- placement math ----------------------------------------------------------

## The arc parameterisation is `BarcelonaRxLayout`'s uniform 400-point chain:
## placement goes through `frame_at_arc()`/`point_at_arc()` (the same frames the
## road mesh is built from), never a re-derived spline. `perimeter()` is measured
## from the chain the caller registered when there is one.
func _frame_at(arc: float) -> Dictionary:
	var frame := BarcelonaRxLayout.frame_at_arc(arc)
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
	if _bank_points.size() != BarcelonaRxLayout.TOTAL_POINTS:
		return BarcelonaRxLayout.bank_rad_at_arc(arc)
	var n := _bank_points.size()
	var x := fposmod(arc, BarcelonaRxLayout.perimeter()) / BarcelonaRxLayout.spacing()
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

## Barrier/flag base height: the terrain at the point's XZ when a callable was
## configured, else the road-edge height straight from the frame math (the
## documented fallback).
func _surface_base_y(frame: Dictionary, offset: float) -> float:
	if _terrain_height.is_valid():
		var probe := _on_cross(frame, offset)
		probe.y = 0.0
		return _terrain_height.call(probe)
	return _on_cross(frame, offset).y

## --- transform helpers -------------------------------------------------------

## Yaw that puts local +X along `dir` (dir is horizontal).
func _yaw_across(dir: Vector3) -> float:
	return atan2(-dir.z, dir.x)

## Yaw that puts local +Z along `dir` (dir is horizontal).
func _yaw_facing(dir: Vector3) -> float:
	return atan2(dir.x, dir.z)

## Yaw that puts local +X along the travel direction: the barrier/cone segment
## runs ALONG the road (their GLBs' long axis is local X, hatched by
## `_scaled_transform`'s basis, so this keeps them parallel to the curb).
func _yaw_along(forward: Vector3) -> float:
	return _yaw_across(forward)

func _flat_basis(right: Vector3, forward: Vector3) -> Basis:
	var x := right
	x.y = 0.0
	x = x.normalized()
	var z := forward
	z.y = 0.0
	z = z.normalized()
	# Right-handed: X x Y == Z requires X = -right when Z = forward.
	return Basis(-x, Vector3.UP, z)

func _scaled_transform(origin: Vector3, yaw: float, uniform_scale: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * uniform_scale), origin)

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

## --- mesh helpers (the `oval_dressing.gd` loader, verbatim) -------------------

## Native surface materials are preserved for MultiMesh instancing; a fused
## multi-node GLB falls back to a flat override.
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
## the Kenney kit bakes an origin offset into every node, which would otherwise
## shift a 14x gantry off its arc.
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
## append into a parameter would never reach the caller.
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
