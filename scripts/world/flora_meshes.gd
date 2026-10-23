# scripts/world/flora_meshes.gd
class_name FloraMeshes
extends RefCounted

## Procedural low-poly vegetation, rocks and roadside furniture for the open
## world (FH6-look pass, 2026-10-23). Every mesh is built once from code (no
## imported assets, so no licence question) and cached for the session.
##
## Vertex contract shared with shaders/flora.gdshader and flora_grass.gdshader:
##  - COLOR.rgb is the albedo with baked shading (darker low / inside the canopy,
##    a little per-face jitter so a flat colour reads as foliage detail).
##  - COLOR.a = 1 marks "tintable" parts (leaves, petals, grass): the shader
##    multiplies them by the per-instance tint (MultiMesh custom data); 0 keeps
##    bark, posts and sign faces their own colour.
##  - UV.y = height above the mesh base / FLORA_SWAY_REF (wind bends the top).
## Front faces are clockwise seen from outside (Godot's convention), so closed
## meshes can use cull_back.

const FLORA_SWAY_REF := 10.0

## Triangle budgets (asserted by tests/suites/test_world_flora.gd). The kit
## places a few thousand instances per live region, so the per-instance cost
## has to stay at low-poly sizes.
const MAX_TREE_TRIS := 700
const MAX_BUSH_TRIS := 300
const MAX_GRASS_TRIS := 64
const MAX_ROCK_TRIS := 200
const MAX_PROP_TRIS := 200

const KEYS := [
	"oak", "poplar", "birch", "maple",
	"bush", "shrub",
	"grass", "dune_grass", "flowers",
	"boulder", "slab", "crag",
	"delineator", "chevron", "route_sign", "fence",
]

static var _cache: Dictionary = {}
static var _ico_verts := PackedVector3Array()
static var _ico_tris := PackedInt32Array()

## The mesh for a key (see KEYS), built on first use and shared afterwards.
static func get_mesh(key: String) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var mesh: ArrayMesh = null
	match key:
		"oak": mesh = _tree_oak()
		"poplar": mesh = _tree_poplar()
		"birch": mesh = _tree_birch()
		"maple": mesh = _tree_maple()
		"bush": mesh = _bush(3, 1.0)
		"shrub": mesh = _bush(2, 0.6)
		"grass": mesh = _grass(false)
		"dune_grass": mesh = _grass(true)
		"flowers": mesh = _flowers()
		"boulder": mesh = _rock(Vector3(1.0, 0.8, 1.0), 11)
		"slab": mesh = _rock(Vector3(1.4, 0.45, 1.1), 23)
		"crag": mesh = _rock(Vector3(0.9, 1.9, 0.8), 37)
		"delineator": mesh = _delineator()
		"chevron": mesh = _chevron()
		"route_sign": mesh = _route_sign()
		"fence": mesh = _fence()
		_:
			push_warning("FloraMeshes: unknown key '%s'" % key)
			return null
	_cache[key] = mesh
	return mesh

static func triangle_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			total += (idx as PackedInt32Array).size() / 3
		else:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total

# -- deterministic helpers -------------------------------------------------------

static func hash01(x: float, y: float, z: float, salt: float) -> float:
	var s := sin(x * 12.9898 + y * 78.233 + z * 37.719 + salt * 4.1414) * 43758.5453
	return s - floorf(s)

static func _icosphere() -> void:
	if not _ico_verts.is_empty():
		return
	var t := (1.0 + sqrt(5.0)) * 0.5
	var v := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	])
	for i in v.size():
		v[i] = v[i].normalized()
	var f := PackedInt32Array([
		0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
		1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
		4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
	])
	# One subdivision: 42 vertices, 80 faces.
	var mids := {}
	var out := PackedInt32Array()
	for k in range(0, f.size(), 3):
		var a := f[k]
		var b := f[k + 1]
		var c := f[k + 2]
		var ab := _mid(v, mids, a, b)
		var bc := _mid(v, mids, b, c)
		var ca := _mid(v, mids, c, a)
		out.append_array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
	_ico_verts = v
	_ico_tris = out

static func _mid(v: PackedVector3Array, mids: Dictionary, a: int, b: int) -> int:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if mids.has(key):
		return mids[key]
	v.append(((v[a] + v[b]) * 0.5).normalized())
	mids[key] = v.size() - 1
	return v.size() - 1

## Emits one triangle with Godot's clockwise-from-outside winding relative to
## `outward`, flat-ish normals bent toward `outward` by `soft`.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, col: Color, soft: float, sway_base: float) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(outward) > 0.0:
		var tmp := b
		b = c
		c = tmp
		n = -n
	var fn := (-n).normalized()
	var nn := (fn * (1.0 - soft) + outward.normalized() * soft).normalized()
	for p: Vector3 in [a, b, c]:
		st.set_color(col)
		st.set_normal(nn)
		st.set_uv(Vector2(0.0, maxf(p.y - sway_base, 0.0) / FLORA_SWAY_REF))
		st.add_vertex(p)

## A displaced, squashed icosphere blob (80 faces). `shade_lo`/`shade_hi` set
## the vertical shading range in world Y of the whole mesh.
static func _blob(st: SurfaceTool, center: Vector3, radius: Vector3, base_col: Color, salt: float, rough: float, y_lo: float, y_hi: float, tint: bool, soft: float = 0.55, sway_base: float = 0.0, floor_y: float = -INF) -> void:
	_icosphere()
	var pts := PackedVector3Array()
	pts.resize(_ico_verts.size())
	for i in _ico_verts.size():
		var d := _ico_verts[i]
		var r := 1.0 + (hash01(d.x, d.y, d.z, salt) - 0.5) * 2.0 * rough
		pts[i] = center + Vector3(d.x * radius.x, d.y * radius.y, d.z * radius.z) * r
		pts[i].y = maxf(pts[i].y, floor_y)
	for k in range(0, _ico_tris.size(), 3):
		var a := pts[_ico_tris[k]]
		var b := pts[_ico_tris[k + 1]]
		var c := pts[_ico_tris[k + 2]]
		var mid := (a + b + c) / 3.0
		var outward := mid - center
		var h := clampf((mid.y - y_lo) / maxf(y_hi - y_lo, 0.001), 0.0, 1.0)
		var jitter := 0.9 + 0.18 * hash01(mid.x, mid.y, mid.z, salt + 7.0)
		var shade := lerpf(0.58, 1.0, h) * jitter
		var col := Color(base_col.r * shade, base_col.g * shade, base_col.b * shade, 1.0 if tint else 0.0)
		_tri(st, a, b, c, outward, col, soft, sway_base)

## Tapered n-sided cylinder (no caps) from `a` to `b`.
static func _trunk(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, sides: int, col: Color) -> void:
	var axis := (b - a).normalized()
	var ref := Vector3.FORWARD if absf(axis.dot(Vector3.UP)) > 0.9 else Vector3.UP
	var u := axis.cross(ref).normalized()
	var w := axis.cross(u).normalized()
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := u * cos(a0) + w * sin(a0)
		var d1 := u * cos(a1) + w * sin(a1)
		var p00 := a + d0 * r0
		var p01 := a + d1 * r0
		var p10 := b + d0 * r1
		var p11 := b + d1 * r1
		var out := (d0 + d1).normalized()
		var dark := Color(col.r * 0.75, col.g * 0.75, col.b * 0.75, col.a)
		_tri_shaded(st, p00, p01, p11, out, dark, col, a.y, b.y)
		_tri_shaded(st, p00, p11, p10, out, dark, col, a.y, b.y)

static func _tri_shaded(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, lo: Color, hi: Color, y0: float, y1: float) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(outward) > 0.0:
		var tmp := b
		b = c
		c = tmp
	for p: Vector3 in [a, b, c]:
		var t := clampf((p.y - y0) / maxf(y1 - y0, 0.001), 0.0, 1.0)
		st.set_color(lo.lerp(hi, t))
		st.set_normal(outward)
		st.set_uv(Vector2(0.0, maxf(p.y, 0.0) / FLORA_SWAY_REF))
		st.add_vertex(p)

## Axis-aligned box (closed), used for posts, sign panels and fence rails.
static func _box(st: SurfaceTool, lo: Vector3, hi: Vector3, col: Color, xform: Transform3D = Transform3D.IDENTITY) -> void:
	var c := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	var centre := xform * ((lo + hi) * 0.5)
	var faces := [[0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1], [2, 6, 7, 3], [1, 5, 6, 2], [0, 3, 7, 4]]
	for f: Array in faces:
		var p0: Vector3 = xform * (c[f[0]] as Vector3)
		var p1: Vector3 = xform * (c[f[1]] as Vector3)
		var p2: Vector3 = xform * (c[f[2]] as Vector3)
		var p3: Vector3 = xform * (c[f[3]] as Vector3)
		var out := ((p0 + p1 + p2 + p3) * 0.25 - centre)
		var shade := 0.85 if out.y < -0.01 else (1.0 if out.y > 0.01 else 0.93)
		var fc := Color(col.r * shade, col.g * shade, col.b * shade, col.a)
		_flat(st, p0, p1, p2, out, fc)
		_flat(st, p0, p2, p3, out, fc)

static func _flat(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(outward) > 0.0:
		var tmp := b
		b = c
		c = tmp
	var nn := outward.normalized()
	for p: Vector3 in [a, b, c]:
		st.set_color(col)
		st.set_normal(nn)
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(p)

static func _commit(st: SurfaceTool) -> ArrayMesh:
	st.index()
	return st.commit()

static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

# -- trees ------------------------------------------------------------------------

const BARK := Color(0.30, 0.22, 0.15, 0.0)
const LEAF := Color(0.30, 0.46, 0.17)

## Broad round deciduous tree (~9.5 m): trunk, two limbs, five canopy lobes.
static func _tree_oak() -> ArrayMesh:
	var st := _begin()
	_trunk(st, Vector3(0, -0.4, 0), Vector3(0.05, 3.6, 0.0), 0.32, 0.2, 6, BARK)
	_trunk(st, Vector3(0.05, 2.8, 0), Vector3(1.4, 4.6, 0.5), 0.14, 0.08, 5, BARK)
	_trunk(st, Vector3(0.0, 3.0, 0), Vector3(-1.0, 4.8, -1.0), 0.13, 0.07, 5, BARK)
	var lobes := [
		[Vector3(0.0, 6.0, 0.0), Vector3(2.9, 2.3, 2.9)],
		[Vector3(1.9, 5.3, 0.8), Vector3(2.0, 1.7, 2.0)],
		[Vector3(-1.5, 5.4, -1.4), Vector3(2.1, 1.7, 2.0)],
		[Vector3(0.3, 7.6, 0.4), Vector3(2.0, 1.6, 2.0)],
		[Vector3(-0.8, 5.0, 1.8), Vector3(1.8, 1.5, 1.8)],
	]
	for i in lobes.size():
		_blob(st, lobes[i][0], lobes[i][1], LEAF, 3.0 + i, 0.16, 3.2, 9.4, true)
	return _commit(st)

## Tall columnar tree (~11 m): three stacked narrow lobes.
static func _tree_poplar() -> ArrayMesh:
	var st := _begin()
	_trunk(st, Vector3(0, -0.4, 0), Vector3(0, 3.0, 0), 0.24, 0.16, 6, BARK)
	var leaf := Color(0.26, 0.44, 0.16)
	_blob(st, Vector3(0, 4.6, 0), Vector3(1.5, 2.4, 1.5), leaf, 41.0, 0.14, 2.4, 11.2, true)
	_blob(st, Vector3(0.1, 7.2, 0.1), Vector3(1.3, 2.4, 1.3), leaf, 42.0, 0.14, 2.4, 11.2, true)
	_blob(st, Vector3(0.0, 9.5, 0.0), Vector3(0.9, 1.8, 0.9), leaf, 43.0, 0.14, 2.4, 11.2, true)
	return _commit(st)

## Light birch-like tree (~9 m): pale trunk, airy yellow-green crown.
static func _tree_birch() -> ArrayMesh:
	var st := _begin()
	var bark := Color(0.82, 0.80, 0.74, 0.0)
	_trunk(st, Vector3(0, -0.4, 0), Vector3(0.2, 6.4, 0.1), 0.17, 0.08, 6, bark)
	var leaf := Color(0.42, 0.56, 0.20)
	var lobes := [
		[Vector3(0.2, 5.0, 0.0), Vector3(1.7, 1.6, 1.7)],
		[Vector3(-0.6, 6.4, 0.6), Vector3(1.5, 1.5, 1.5)],
		[Vector3(0.9, 6.8, -0.5), Vector3(1.4, 1.5, 1.4)],
		[Vector3(0.2, 8.0, 0.1), Vector3(1.2, 1.2, 1.2)],
	]
	for i in lobes.size():
		_blob(st, lobes[i][0], lobes[i][1], leaf, 51.0 + i, 0.2, 3.4, 9.2, true)
	return _commit(st)

## Compact rounded tree (~7 m), used with warm tints for colour accents.
static func _tree_maple() -> ArrayMesh:
	var st := _begin()
	_trunk(st, Vector3(0, -0.4, 0), Vector3(0, 2.6, 0), 0.24, 0.16, 6, BARK)
	var leaf := Color(0.36, 0.44, 0.18)
	_blob(st, Vector3(0, 4.4, 0), Vector3(2.6, 1.9, 2.6), leaf, 61.0, 0.18, 2.4, 7.2, true)
	_blob(st, Vector3(0.6, 5.6, -0.4), Vector3(1.8, 1.4, 1.8), leaf, 62.0, 0.18, 2.4, 7.2, true)
	_blob(st, Vector3(-1.2, 4.6, 0.9), Vector3(1.6, 1.3, 1.6), leaf, 63.0, 0.18, 2.4, 7.2, true)
	return _commit(st)

# -- low vegetation ----------------------------------------------------------------

## Bush (~1.6 m, `lobes` lobes) or shrub (smaller). Sits slightly sunk.
static func _bush(lobes: int, size: float) -> ArrayMesh:
	var st := _begin()
	var leaf := Color(0.27, 0.42, 0.16)
	var offs := [Vector3(0, 0.55, 0), Vector3(0.7, 0.42, 0.3), Vector3(-0.5, 0.45, -0.55)]
	for i in lobes:
		var c: Vector3 = offs[i] * size
		var r := Vector3(0.95, 0.75, 0.95) * size * (1.0 if i == 0 else 0.78)
		_blob(st, c, r, leaf, 71.0 + i + size, 0.2, -0.2, 1.4 * size, true, 0.6, 0.0)
	return _commit(st)

## A clump of upright blades (three tufts over ~1.4 m). Not a flat card: every
## blade is a thin standing triangle leaning out, so it never reads as a tile.
## Blade normals point mostly up so the clump is lit like the ground under it.
static func _grass(dune: bool) -> ArrayMesh:
	var st := _begin()
	var lo := Color(0.24, 0.33, 0.11, 1.0) if not dune else Color(0.42, 0.4, 0.25, 1.0)
	var hi := Color(0.56, 0.68, 0.28, 1.0) if not dune else Color(0.8, 0.74, 0.5, 1.0)
	var tufts := [Vector2(0, 0), Vector2(0.6, 0.25), Vector2(-0.4, 0.5), Vector2(0.15, -0.55)]
	var blades := 8
	var height := 0.42 if not dune else 0.8
	var salt := 91.0 if not dune else 97.0
	for t in tufts.size():
		var base2: Vector2 = tufts[t]
		for b in blades:
			var ang := TAU * (float(b) + hash01(float(t), float(b), 0.0, salt)) / float(blades)
			var dir := Vector3(cos(ang), 0.0, sin(ang))
			var side := Vector3(-dir.z, 0.0, dir.x)
			var hgt := height * (0.65 + 0.6 * hash01(float(b), float(t), 1.0, salt))
			var lean := 0.18 + 0.25 * hash01(float(t), 2.0, float(b), salt)
			var root := Vector3(base2.x, -0.05, base2.y) + dir * 0.06
			var w := 0.035 if not dune else 0.03
			var a := root - side * w
			var c := root + side * w
			var tip := root + dir * (lean * hgt) + Vector3(0, hgt, 0)
			var n := (Vector3.UP * 0.8 + dir * 0.2).normalized()
			for p: Vector3 in [a, tip, c]:
				var k := clampf(p.y / hgt, 0.0, 1.0)
				st.set_color(lo.lerp(hi, k))
				st.set_normal(n)
				st.set_uv(Vector2(0.0, maxf(p.y, 0.0) / 1.0))
				st.add_vertex(p)
	return _commit(st)

## A small patch of wild flowers: thin stems with a two-triangle bloom each.
## Petals are tintable (COLOR.a = 1, white base) so one mesh gives every colour.
static func _flowers() -> ArrayMesh:
	var st := _begin()
	var stem := Color(0.2, 0.34, 0.1, 0.0)
	var petal := Color(1.0, 1.0, 1.0, 1.0)
	for i in 6:
		var a := TAU * float(i) / 6.0 + hash01(float(i), 0.0, 0.0, 13.0)
		var r := 0.15 + 0.45 * hash01(float(i), 1.0, 0.0, 13.0)
		var root := Vector3(cos(a) * r, -0.03, sin(a) * r)
		var h := 0.3 + 0.25 * hash01(float(i), 2.0, 0.0, 13.0)
		var top := root + Vector3(0.0, h, 0.0)
		var n := Vector3.UP
		for p: Vector3 in [root + Vector3(0.015, 0, 0), top, root - Vector3(0.015, 0, 0)]:
			st.set_color(stem)
			st.set_normal(n)
			st.set_uv(Vector2(0.0, p.y))
			st.add_vertex(p)
		var s := 0.07
		var q := [top + Vector3(-s, 0.0, 0.0), top + Vector3(0.0, 0.02, -s), top + Vector3(s, 0.0, 0.0), top + Vector3(0.0, 0.02, s)]
		for tri: Array in [[0, 1, 2], [0, 2, 3]]:
			for k: int in tri:
				st.set_color(petal)
				st.set_normal(n)
				st.set_uv(Vector2(0.0, top.y))
				st.add_vertex(q[k])
	return _commit(st)

# -- rocks ------------------------------------------------------------------------

## Grey faceted rock; `stretch` shapes boulder / slab / crag. Base sunk 25 %.
static func _rock(stretch: Vector3, salt: int) -> ArrayMesh:
	var st := _begin()
	var col := Color(0.4, 0.39, 0.36)
	# Flat underside a little below y = 0, so the rock sits on (in) the ground
	# instead of balancing on a point (pointed crags read as floating).
	_blob(st, Vector3(0.0, stretch.y * 0.55, 0.0), stretch, col, float(salt), 0.28, -0.2, stretch.y * 1.4, false, 0.15, 0.0, -0.25)
	return _commit(st)

# -- roadside furniture -------------------------------------------------------------

## Japanese-style roadside delineator: white post (1.1 m) with an amber reflector.
static func _delineator() -> ArrayMesh:
	var st := _begin()
	_box(st, Vector3(-0.05, -0.2, -0.05), Vector3(0.05, 1.1, 0.05), Color(0.92, 0.92, 0.9, 0.0))
	_box(st, Vector3(-0.07, 0.8, -0.07), Vector3(0.07, 0.98, 0.07), Color(1.0, 0.62, 0.1, 0.0))
	return _commit(st)

## Curve chevron board on a post: yellow panel with a black arrow band. Faces +Z.
static func _chevron() -> ArrayMesh:
	var st := _begin()
	_box(st, Vector3(-0.05, -0.3, -0.05), Vector3(0.05, 1.3, 0.05), Color(0.55, 0.55, 0.55, 0.0))
	_box(st, Vector3(-0.42, 1.3, -0.03), Vector3(0.42, 1.9, 0.03), Color(0.95, 0.78, 0.08, 0.0))
	_box(st, Vector3(-0.12, 1.36, 0.03), Vector3(0.12, 1.84, 0.045), Color(0.08, 0.08, 0.08, 0.0))
	return _commit(st)

## Route / direction sign on two posts: blue panel with a white border band.
static func _route_sign() -> ArrayMesh:
	var st := _begin()
	var post := Color(0.6, 0.6, 0.62, 0.0)
	_box(st, Vector3(-1.3, -0.3, -0.06), Vector3(-1.18, 3.4, 0.06), post)
	_box(st, Vector3(1.18, -0.3, -0.06), Vector3(1.3, 3.4, 0.06), post)
	_box(st, Vector3(-1.6, 2.0, -0.04), Vector3(1.6, 3.6, 0.04), Color(0.92, 0.92, 0.92, 0.0))
	_box(st, Vector3(-1.5, 2.1, 0.04), Vector3(1.5, 3.5, 0.06), Color(0.06, 0.2, 0.55, 0.0))
	_box(st, Vector3(-1.1, 2.75, 0.06), Vector3(0.9, 2.9, 0.07), Color(0.95, 0.95, 0.95, 0.0))
	return _commit(st)

## One 4 m wooden fence bay along +X: post at x = 0 and two rails.
static func _fence() -> ArrayMesh:
	var st := _begin()
	var wood := Color(0.42, 0.32, 0.22, 0.0)
	_box(st, Vector3(-0.07, -0.3, -0.07), Vector3(0.07, 1.15, 0.07), wood)
	_box(st, Vector3(0.0, 0.45, -0.03), Vector3(4.0, 0.58, 0.03), wood)
	_box(st, Vector3(0.0, 0.88, -0.03), Vector3(4.0, 1.01, 0.03), wood)
	return _commit(st)
