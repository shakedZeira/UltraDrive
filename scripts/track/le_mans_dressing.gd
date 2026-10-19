class_name LeMansDressing
extends Node3D

## Circuit dressing for the Le Mans No-Chicane circuit (plan
## docs/plans/track_le_mans_no_chicane.md §3.8). SELF-CONTAINED: this class
## never extends or reuses `RxDressing`, whose `rx_dressing.gd` is on the plan's
## do-not-touch list and whose barrier/gantry kit is sized for a 1.1 km
## rallycross circuit.
##
## WHAT IT BUILDS (§3.8 item list, budgets pinned by A8)
##   * gantry  — 1 fused portal (posts + beam + neutral banner slab) straddling
##       the road at the S/F line (arc 0). The banner carries NO TEXT AT ALL:
##       "neutral banner" is read literally (§7 gotcha 8 — no trademarked
##       names, and no text that could grow one later).
##   * paint   — 1 generated 8x2 checker slab on the carriageway at the line.
##   * arch    — 1 fused Dunlop-bridge-shaped arch at chainage 869 with a
##       neutral un-lettered banner (§3.8 explicitly: NO Dunlop trademark).
##   * armco   — visual-only guardrail segments (§8.3(f): cars pass through in
##       v1) at the CORNER COMPLEXES ONLY: +-50 m around every >=40 deg sharp
##       corner (`LeMansLayout.sharp_corner_chainages()`), OUTSIDE of the
##       corner, 4.6 m segments at 5 m pitch, offset WIDTH/2 + 1.6 m.
##   * hedge   — MultiMesh hedgerow blocks along the Mulsanne, chainage
##       2,000-7,300, both sides, 12 m pitch, offset WIDTH/2 + 5 m, with a
##       deterministic per-block height wobble (no RNG).
##   * tyre    — tyre-stack braking markers at the five §3.8 braking zones
##       (Tertre 1,450 / Mulsanne 7,300 / Indy 9,600 / Arnage 9,950 /
##       Ford 13,020): 4 stacks x 3 tyres per zone, outside of the corner.
##   * kerb    — red/white striped apex kerb slabs on the INNER edge at the
##       same sharp corners (+-15 m, 5 m pitch), seated on the banked surface
##       through the layout's own cross direction.
##   * post    — marshal post towers on a 1,500 m cadence, alternating sides,
##       offset WIDTH/2 + 10 m.
##
## Explicitly OUT of scope (§3.8 "Out:"): grandstands, pits, floodlights,
## full-lap armco.
##
## MESH FRAMES (the source of most off-by-one bugs here, stated once):
##   `_basis_along`   -> local X ALONG the road, Z across  (armco/hedge/tyre/post)
##   `_basis_span`    -> local X ACROSS the road, Z along  (gantry/arch/paint)
##   `_basis_surface` -> local X along the road, Y the banked surface normal
##                       (kerbs, which lie ON the carriageway)
##
## DETERMINISM: no RNG, no wall clock, every placement is arc/constant driven,
## so two `build()` runs on the same configuration produce bit-identical
## transform sets (pinned by A8).
##
## USABLE WITH NO SCENE: `configure()` then `build()`. Nothing here reads a
## scene or a `RoadNetwork`; `height_provider` is an optional
## `Callable(Vector3) -> float` for ground-bound props, and when it is absent
## they sit on `LeMansLayout.PLAIN_Y` -- the v1 flat plain the scene actually
## builds (an elevation pass, §8.5, would configure the callable instead).

## Kinds the builder can place, in build order.
const KIND_GANTRY := "gantry"
const KIND_PAINT := "paint"
const KIND_ARCH := "arch"
const KIND_ARMCO := "armco"
const KIND_HEDGE := "hedge"
const KIND_TYRE := "tyre"
const KIND_KERB := "kerb"
const KIND_POST := "post"

## Sharp-corner threshold (deg) shared by armco + kerbs; the layout's own
## default argument (restate here so a default change cannot drift silently).
const SHARP_TURN_DEG := 40.0

## The centerline + bank profile the road mesh was built from (set by
## `configure()`; `build()` refuses to run without them).
var road_points: Array[Vector3] = []
var bank_profile: PackedFloat32Array = PackedFloat32Array()
var road_width: float = LeMansLayout.WIDTH_M
## Optional world-Y lookup for props that must sit on the ground. The flat v1
## scene passes none; an empty callable means "the plain at PLAIN_Y" (see the
## class note above).
var height_provider: Callable = Callable()

var _built := false
## kind -> Array[Transform3D] of every placed instance.
var _transforms: Dictionary = {}
## kind -> the Mesh each instance of that kind draws.
var _meshes: Dictionary = {}
## kinds that failed to resolve a mesh (always empty for a procedural builder;
## kept for the `dropped_kinds()` API symmetry with the barcelona suite).
var _dropped: Array[String] = []
## Cached closed-chain length of the configured centerline (-1 = unmeasured).
var _perim := -1.0

## --- §3.8 tuning table (all constants; no magic numbers below) ---------------

## Portals (span frames: X across the road).
const GANTRY_POST_OFFSET := 2.2          ## beyond the road edge each post
const GANTRY_POST_SIZE := Vector3(0.5, 6.2, 0.5)
const GANTRY_BEAM_Y := 6.45
const GANTRY_BANNER_Y := 5.45
const ARCH_POST_OFFSET := 2.0
const ARCH_POST_SIZE := Vector3(0.7, 5.6, 0.7)
const ARCH_BEAM_Y := 5.85
const ARCH_BANNER_Y := 4.95
## S/F checker paint (span frame: X across, Z along the road).
const CHECKER_CELLS_X := 8
const CHECKER_CELLS_Y := 2
const CHECKER_CELL_PX := 12
const CHECKER_LENGTH := 1.5              ## along the road
const CHECKER_LIFT := 0.02               ## over the road surface (z-fight guard)
## Armco (along frames: X along the road; visual only, v1 -- §8.3(f)).
const ARMCO_WINDOW_M := 50.0             ## +- around each sharp-corner chainage
const ARMCO_PITCH_M := 5.0
const ARMCO_OFFSET := 1.6                ## beyond the road edge
const ARMCO_SEGMENT_LENGTH := 4.6
const ARMCO_RAIL_Y := 0.62               ## rail centre above the plain
const ARMCO_RAIL_SIZE := Vector3(ARMCO_SEGMENT_LENGTH, 0.34, 0.08)
const ARMCO_POST_SIZE := Vector3(0.16, 1.05, 0.16)
const ARMCO_POST_INSET := 0.35           ## post inboard of the rail ends
## Hedgerows along the Mulsanne (§3.8 chainage window, literal; along frame).
const HEDGE_CHAINAGE_FROM := 2000.0
const HEDGE_CHAINAGE_TO := 7300.0
const HEDGE_PITCH_M := 12.0
const HEDGE_OFFSET := 5.0                ## beyond the road edge
const HEDGE_SIZE := Vector3(9.0, 1.9, 1.7)   ## X along road, Z across
const HEDGE_H_WOBBLE := 0.12             ## deterministic +- scale.y wobble
## Tyre stacks: the five §3.8 braking-zone chainages, verbatim.
const TYRE_ZONE_CHAINAGES: Array[float] = [1450.0, 7300.0, 9600.0, 9950.0, 13020.0]
const TYRE_STACKS_PER_ZONE := 4
const TYRE_PER_STACK := 3
const TYRE_STACK_PITCH := 1.4            ## between stacks along the road
const TYRE_OFFSET := 2.2                 ## beyond the road edge
const TYRE_RADIUS := 0.34
const TYRE_HEIGHT := 0.22
## Apex kerbs at the sharp corners (surface frame: X along road, Z across).
const KERB_WINDOW_M := 15.0              ## +- around each corner chainage
const KERB_PITCH_M := 5.0
const KERB_INSET := 0.55                 ## inboard of the road edge
const KERB_SIZE := Vector3(4.6, 0.06, 0.5)
const KERB_SURFACE_LIFT := 0.03          ## over the banked road surface
## Marshal posts (along frame).
const POST_CADENCE_M := 1500.0
const POST_OFFSET := 10.0                ## beyond the road edge
const POST_LEG_SIZE := Vector3(0.12, 2.4, 0.12)
const POST_DECK_Y := 2.45
const POST_DECK_SIZE := Vector3(1.2, 0.1, 1.6)
const POST_ROOF_Y := 3.35
const POST_ROOF_SIZE := Vector3(1.5, 0.08, 1.9)
## The corner-direction probe half-window (m of arc) for outside/inside calls.
const CORNER_PROBE_M := 30.0


## Wire-up hook called by `le_mans.gd` BEFORE `build()`. Everything the dressing
## places is derived from these, so it cannot disagree with the road mesh about
## where the carriageway edge is.
func configure(points: Array[Vector3], banks: PackedFloat32Array, width: float,
		p_height_provider: Callable = Callable()) -> void:
	road_points = points
	bank_profile = banks
	road_width = width
	height_provider = p_height_provider
	_perim = -1.0
	_built = false


## Whether `build()` has run (cleared by a re-configure).
func is_built() -> bool:
	return _built


## Kinds that failed to resolve their mesh at build time (empty when healthy).
func dropped_kinds() -> Array:
	return _dropped


## How many instances of `kind` were placed.
func count_of(kind: String) -> int:
	return (_transforms.get(kind, []) as Array).size()


## The mesh an instance of `kind` draws, or null.
func prop_mesh(kind: String) -> Mesh:
	return _meshes.get(kind) as Mesh


## Every placement transform of `kind` (stable build order).
func transforms_of(kind: String) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for t: Transform3D in (_transforms.get(kind, []) as Array):
		out.append(t)
	return out


## World origin of every `kind` instance.
func origins_of(kind: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	for t: Transform3D in (_transforms.get(kind, []) as Array):
		out.append(t.origin)
	return out


func build() -> void:
	_clear_children()
	_transforms = {}
	_meshes = {}
	_dropped = []
	_built = false
	if road_points.size() < 3:
		return

	_build_gantry()
	_build_checker_paint()
	_build_arch()
	_build_armco()
	_build_hedges()
	_build_tyres()
	_build_kerbs()
	_build_marshal_posts()
	_built = true

## --- item builders -----------------------------------------------------------

## S/F gantry: one fused portal straddling the carriageway at the line.
func _build_gantry() -> void:
	var st := _station(LeMansLayout.start_line_arc())
	var half := road_width * 0.5 + GANTRY_POST_OFFSET
	var entries: Array = [
		{"size": GANTRY_POST_SIZE, "offset": Vector3(-half, GANTRY_POST_SIZE.y * 0.5, 0.0)},
		{"size": GANTRY_POST_SIZE, "offset": Vector3(half, GANTRY_POST_SIZE.y * 0.5, 0.0)},
		{"size": Vector3(half * 2.0 + 0.5, 0.7, 0.7), "offset": Vector3(0.0, GANTRY_BEAM_Y, 0.0)},
		# Neutral banner slab: deliberately UN-LETTERED (§7 gotcha 8).
		{"size": Vector3(half * 1.6, 0.9, 0.16), "offset": Vector3(0.0, GANTRY_BANNER_Y, 0.0)},
	]
	var mesh := _fused_mesh(entries, _mat(Color(0.62, 0.65, 0.70), 0.7))
	# Posts stand on the PLAIN beyond the road edge (not on the carriageway).
	_emit_single(KIND_GANTRY, mesh, _xform_ground(st, _basis_span(st), 0.0))


## The 8x2 start checker: a thin slab ON the carriageway at the line, textured
## by a generated checker image (no asset dependency, no RNG).
func _build_checker_paint() -> void:
	var st := _station(LeMansLayout.start_line_arc())
	var mesh := _slab_mesh(Vector3(road_width * 0.96, CHECKER_LIFT * 0.5, CHECKER_LENGTH),
		_mat(Color.WHITE, 0.95, _checker_texture()))
	var t := _xform_on_road(st, _basis_span(st), Vector3.ZERO)
	t.origin.y = st["center"].y + CHECKER_LIFT
	_emit_single(KIND_PAINT, mesh, t)


## The Dunlop-bridge-shaped arch at chainage 869 with a NEUTRAL banner.
func _build_arch() -> void:
	var st := _station(LeMansLayout.arc_at_chainage(LeMansLayout.LANDMARK_DUNLOP_BRIDGE))
	var half := road_width * 0.5 + ARCH_POST_OFFSET
	var entries: Array = [
		{"size": ARCH_POST_SIZE, "offset": Vector3(-half, ARCH_POST_SIZE.y * 0.5, 0.0)},
		{"size": ARCH_POST_SIZE, "offset": Vector3(half, ARCH_POST_SIZE.y * 0.5, 0.0)},
		{"size": Vector3(half * 2.0 + 0.4, 0.6, 0.6), "offset": Vector3(0.0, ARCH_BEAM_Y, 0.0)},
		# Neutral banner slab, un-lettered by design (no Dunlop trademark).
		{"size": Vector3(half * 1.5, 0.8, 0.14), "offset": Vector3(0.0, ARCH_BANNER_Y, 0.0)},
	]
	var mesh := _fused_mesh(entries, _mat(Color(0.24, 0.36, 0.52), 0.65))
	var t := _xform_ground(st, _basis_span(st), 0.0)
	_emit_single(KIND_ARCH, mesh, t)


## Armco at the corner complexes ONLY, outside of each corner (§8.3(f): these
## are visuals -- there is deliberately no collider in v1).
func _build_armco() -> void:
	var mesh := _fused_mesh([
		{"size": ARMCO_RAIL_SIZE, "offset": Vector3(0.0, ARMCO_RAIL_Y, 0.0)},
		{"size": ARMCO_POST_SIZE, "offset": Vector3(
			ARMCO_SEGMENT_LENGTH * 0.5 - ARMCO_POST_INSET, ARMCO_POST_SIZE.y * 0.5, 0.0)},
	], _mat(Color(0.72, 0.74, 0.78), 0.45))
	_meshes[KIND_ARMCO] = mesh
	for ch in LeMansLayout.sharp_corner_chainages(SHARP_TURN_DEG):
		var arc := LeMansLayout.arc_at_chainage(ch)
		var offset := float(_outside_side(arc)) * (road_width * 0.5 + ARMCO_OFFSET)
		var count := int(ARMCO_WINDOW_M * 2.0 / ARMCO_PITCH_M) + 1
		for k in count:
			var st := _station(arc - ARMCO_WINDOW_M + float(k) * ARMCO_PITCH_M)
			_record(KIND_ARMCO, _xform_ground(st, _basis_along(st), offset))
	_flush(KIND_ARMCO)


## Hedgerow blocks along the Mulsanne window, both sides, deterministic
## height wobble (an integer sine of the block index -- no RNG anywhere).
func _build_hedges() -> void:
	_meshes[KIND_HEDGE] = _slab_mesh(HEDGE_SIZE, _mat(Color(0.15, 0.28, 0.12), 1.0))
	var a0 := LeMansLayout.arc_at_chainage(HEDGE_CHAINAGE_FROM)
	var a1 := LeMansLayout.arc_at_chainage(HEDGE_CHAINAGE_TO)
	var blocks := int((a1 - a0) / HEDGE_PITCH_M)
	for k in blocks + 1:
		var st := _station(a0 + float(k) * HEDGE_PITCH_M)
		for side: float in [-1.0, 1.0]:
			var t := _xform_ground(st, _basis_along(st), side * (road_width * 0.5 + HEDGE_OFFSET))
			var wobble := 1.0 + HEDGE_H_WOBBLE * sin(float(k) * 1.7)
			t.basis = t.basis * Basis.from_scale(Vector3(1.0, wobble, 1.0))
			_record(KIND_HEDGE, t)
	_flush(KIND_HEDGE)


## Tyre-stack braking markers at the five §3.8 zone chainages: a short run of
## stacks, each three tyres high, outside of the zone's corner.
func _build_tyres() -> void:
	_meshes[KIND_TYRE] = _cylinder_mesh(TYRE_RADIUS, TYRE_HEIGHT, _mat(Color(0.08, 0.08, 0.09), 0.95))
	for ch in TYRE_ZONE_CHAINAGES:
		var arc := LeMansLayout.arc_at_chainage(ch)
		var offset := float(_outside_side(arc)) * (road_width * 0.5 + TYRE_OFFSET)
		for s in TYRE_STACKS_PER_ZONE:
			var st := _station(arc
				+ (float(s) - float(TYRE_STACKS_PER_ZONE - 1) * 0.5) * TYRE_STACK_PITCH)
			var ground := _ground_y(st, offset)
			for level in TYRE_PER_STACK:
				var t := _xform_ground(st, _basis_along(st), offset)
				t.origin.y = ground + TYRE_HEIGHT * 0.5 + float(level) * TYRE_HEIGHT
				_record(KIND_TYRE, t)
	_flush(KIND_TYRE)


## Red/white apex kerb slabs on the INNER edge of every sharp corner, seated on
## the banked surface via the layout's own cross direction.
func _build_kerbs() -> void:
	_meshes[KIND_KERB] = _slab_mesh(KERB_SIZE, _mat(Color.WHITE, 0.85, _stripe_texture()))
	for ch in LeMansLayout.sharp_corner_chainages(SHARP_TURN_DEG):
		var arc := LeMansLayout.arc_at_chainage(ch)
		var side := -float(_outside_side(arc))   # inner edge = opposite the armco
		var count := int(KERB_WINDOW_M * 2.0 / KERB_PITCH_M) + 1
		for k in count:
			var st := _station(arc - KERB_WINDOW_M + float(k) * KERB_PITCH_M)
			var cross: Vector3 = st["cross"]
			_record(KIND_KERB, _xform_on_road(st, _basis_surface(st),
				cross * (side * (road_width * 0.5 - KERB_INSET))
				+ st["normal"] * KERB_SURFACE_LIFT))
	_flush(KIND_KERB)


## Marshal-post towers on the 1,500 m cadence, alternating sides.
func _build_marshal_posts() -> void:
	_meshes[KIND_POST] = _fused_mesh([
		{"size": POST_LEG_SIZE, "offset": Vector3(0.0, POST_LEG_SIZE.y * 0.5, -0.55)},
		{"size": POST_LEG_SIZE, "offset": Vector3(0.0, POST_LEG_SIZE.y * 0.5, 0.55)},
		{"size": POST_DECK_SIZE, "offset": Vector3(0.0, POST_DECK_Y, 0.0)},
		{"size": POST_ROOF_SIZE, "offset": Vector3(0.0, POST_ROOF_Y, 0.0)},
	], _mat(Color(0.55, 0.57, 0.60), 0.8))
	var posts := int(_perimeter() / POST_CADENCE_M)
	for k in posts:
		var st := _station(float(k) * POST_CADENCE_M + POST_CADENCE_M * 0.5)
		var side := 1.0 if k % 2 == 0 else -1.0
		_record(KIND_POST, _xform_ground(st, _basis_along(st),
			side * (road_width * 0.5 + POST_OFFSET)))
	_flush(KIND_POST)

## --- road-frame math (same neighbour-tangent + bank convention as the road
## --- mesh and `LeMansLayout.frame_at_arc`, so dressing and asphalt agree) ----

## Closed-chain length of the configured centerline (cached per configure).
func _perimeter() -> float:
	if _perim < 0.0:
		var total := 0.0
		var n := road_points.size()
		for i in n:
			total += road_points[i].distance_to(road_points[(i + 1) % n])
		_perim = total if total > 0.0 else 1.0
	return _perim

## Spacing (m) between configured centerline points.
func _spacing() -> float:
	var n := road_points.size()
	if n < 2:
		return 1.0
	return _perimeter() / float(n)

## Bank angle (rad) at centerline index `i` (0 when unprofiled).
func _bank_at(i: int) -> float:
	if i < 0 or i >= bank_profile.size():
		return 0.0
	return float(bank_profile[i])

## Road frame at arc `s`: {center, forward, right, cross, normal, bank}.
## `center` is the road SURFACE centerline point (the mesh's own Y rule lives
## in it); `cross` is the banked in-plane direction (`right*cos - UP*sin`) and
## `normal` its perpendicular (`UP*cos + right*sin`).
func _station(s: float) -> Dictionary:
	var n := road_points.size()
	var idx := fposmod(s, _perimeter()) / _spacing()
	var i0 := int(idx) % n
	var prev := road_points[(i0 - 1 + n) % n]
	var next := road_points[(i0 + 1) % n]
	var forward := (next - prev).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var angle := _bank_at(i0)
	return {
		"center": road_points[i0],
		"forward": forward,
		"right": right,
		"cross": right * cos(angle) - Vector3.UP * sin(angle),
		"normal": Vector3.UP * cos(angle) + right * sin(angle),
		"bank": angle,
	}

## +1 when the corner at `s` turns LEFT (its outside is the right side), -1
## when it turns right: measured from the tangent swing either side of the
## apex, so it cannot disagree with the geometry it is dressing.
func _outside_side(s: float) -> int:
	var t1: Vector3 = _station(s - CORNER_PROBE_M)["forward"]
	var t2: Vector3 = _station(s + CORNER_PROBE_M)["forward"]
	return 1 if (t1.cross(t2)).y > 0.0 else -1

## World Y a ground-bound prop stands on: the configured provider, else the
## FLAT v1 plain (see the class note).
func _ground_y(station: Dictionary, _offset: float) -> float:
	if height_provider.is_valid():
		var center: Vector3 = station["center"]
		return float(height_provider.call(Vector3(center.x, 0.0, center.z)))
	return LeMansLayout.PLAIN_Y

## --- transform helpers -------------------------------------------------------

## Basis with local X along the road, Y up (det +1).
func _basis_along(station: Dictionary) -> Basis:
	var f: Vector3 = station["forward"]
	var fwd := Vector3(f.x, 0.0, f.z).normalized()
	return Basis(fwd, Vector3.UP, fwd.cross(Vector3.UP))

## Basis with local X ACROSS the road, Y up (det +1) -- portals and paint.
func _basis_span(station: Dictionary) -> Basis:
	var f: Vector3 = station["forward"]
	var fwd := Vector3(f.x, 0.0, f.z).normalized()
	var right := fwd.cross(Vector3.UP)
	return Basis(right, Vector3.UP, -fwd)

## Basis lying ON the banked surface: local X along the road, Y the surface
## normal, Z the completion (det +1).
func _basis_surface(station: Dictionary) -> Basis:
	var f: Vector3 = station["forward"]
	var normal: Vector3 = station["normal"]
	return Basis(f, normal, f.cross(normal))

## On-road placement: `offset` along the banked `cross` from the surface
## centerline (paint/kerb live ON the carriageway by design).
func _xform_on_road(station: Dictionary, basis: Basis, offset: Vector3) -> Transform3D:
	var center: Vector3 = station["center"]
	return Transform3D(basis, center + offset)

## Ground placement: `offset` laterally from the centerline at plain height
## (armco/hedges/tyres/posts live OUTSIDE the road).
func _xform_ground(station: Dictionary, basis: Basis, offset: float) -> Transform3D:
	var center: Vector3 = station["center"]
	var right: Vector3 = station["right"]
	return Transform3D(basis, Vector3(
		center.x + right.x * offset, _ground_y(station, offset), center.z + right.z * offset))

## --- mesh + node helpers -----------------------------------------------------

## One ArrayMesh surface per {size, offset} box entry, fused (rx_dressing's
## "fused primitives" idiom), all sharing `mat`. Entries are local to the
## kind's mesh frame (see the MESH FRAMES note).
func _fused_mesh(entries: Array, mat: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for e in entries:
		var box := BoxMesh.new()
		box.size = e["size"]
		var arrays := box.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var offset: Vector3 = e["offset"]
		for i in verts.size():
			verts[i] += offset
		arrays[Mesh.ARRAY_VERTEX] = verts
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh

## A single box with `mat` -- hedges, kerbs, paint.
func _slab_mesh(size: Vector3, mat: Material) -> ArrayMesh:
	return _fused_mesh([{"size": size, "offset": Vector3.ZERO}], mat)

## A low-segment cylinder for tyre stacks.
func _cylinder_mesh(radius: float, height: float, mat: Material) -> ArrayMesh:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 12
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cyl.surface_get_arrays(0))
	mesh.surface_set_material(0, mat)
	return mesh

## StandardMaterial3D with an optional albedo texture.
func _mat(color: Color, roughness: float, texture: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if texture != null:
		m.albedo_texture = texture
	return m

## Generated 8x2 checker (deterministic, no asset).
func _checker_texture() -> ImageTexture:
	var img := Image.create(CHECKER_CELLS_X * CHECKER_CELL_PX, CHECKER_CELLS_Y * CHECKER_CELL_PX,
		false, Image.FORMAT_RGB8)
	for y in CHECKER_CELLS_Y:
		for x in CHECKER_CELLS_X:
			var dark := (x + y) % 2 == 1
			img.fill_rect(Rect2i(x * CHECKER_CELL_PX, y * CHECKER_CELL_PX,
				CHECKER_CELL_PX, CHECKER_CELL_PX),
				Color(0.06, 0.06, 0.07) if dark else Color(0.94, 0.94, 0.94))
	return ImageTexture.create_from_image(img)

## Generated red/white kerb stripes alternating along local X (the kerb
## segment length).
func _stripe_texture() -> ImageTexture:
	var img := Image.create(8 * 8, 8, false, Image.FORMAT_RGB8)
	for i in 8:
		var red := i % 2 == 0
		img.fill_rect(Rect2i(i * 8, 0, 8, 8),
			Color(0.75, 0.10, 0.10) if red else Color(0.94, 0.94, 0.94))
	return ImageTexture.create_from_image(img)

## Record one placement (query API) for a kind whose mesh is already in
## `_meshes`; `_flush()` turns the recorded set into the shared MultiMesh node.
func _record(kind: String, t: Transform3D) -> void:
	if not _transforms.has(kind):
		_transforms[kind] = []
	(_transforms[kind] as Array).append(t)

## Build the single shared MultiMeshInstance3D for a recorded kind.
func _flush(kind: String) -> void:
	var list := _transforms.get(kind, []) as Array
	var mesh := _meshes.get(kind) as ArrayMesh
	if list.is_empty() or mesh == null:
		if not list.is_empty():
			_dropped.append(kind)
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i] as Transform3D)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = kind.capitalize()
	mmi.multimesh = mm
	add_child(mmi)

## Record + flush in one step (single-instance kinds: gantry/paint/arch).
func _emit_single(kind: String, mesh: ArrayMesh, t: Transform3D) -> void:
	_meshes[kind] = mesh
	_record(kind, t)
	_flush(kind)

## Rebuild hygiene: drop every child node from a previous build immediately
## (`free()`, not `queue_free()`: a test may rebuild and re-count in one frame).
func _clear_children() -> void:
	for child in get_children():
		child.free()
