# scripts/world/traffic_model_catalog.gd
class_name TrafficModelCatalog
extends RefCounted

## Ambient traffic vehicle types (traffic plan section 8): CC0 Kenney Car Kit
## models, each merged at load into ONE mesh (body + wheels baked, one shared
## material) so a traffic car costs one draw call. Normalised here, not in the
## GLBs: centred on X/Z, wheels on y = 0, nose +Z (the project's car contract),
## scaled from the kit's toy units to road size.

const MODEL_DIR := "res://assets/cars/cc0/kenney_car-kit/Models/GLB format/"
## Kit units -> metres per axis (x width, y height, z length). The kit's cars are
## stubby (width/length ~0.6); a little extra length keeps them believable next to
## the player car without visibly squashing the wheels (y/z ratio ~0.9).
const KIT_SCALE := Vector3(1.3, 1.4, 1.6)
## +1 when the kit's nose points +Z, -1 when it points -Z (checked in captures).
const KIT_NOSE_SIGN := 1.0

const T_HWY := RoadDef.Tier.HIGHWAY
const T_ART := RoadDef.Tier.ARTERIAL
const T_TOU := RoadDef.Tier.TOUGE
const T_CST := RoadDef.Tier.COASTAL
const T_DRT := RoadDef.Tier.DIRT

## id, spawn weight per tier, v0 factor, a_max (m/s^2). Weights per plan 8.
const TYPES := [
	{"id": "sedan", "weights": {T_HWY: 0.30, T_ART: 0.30, T_CST: 0.30, T_TOU: 0.15, T_DRT: 0.20}, "v0_factor": 1.0, "a_max": 2.0},
	{"id": "suv", "weights": {T_HWY: 0.20, T_ART: 0.15, T_CST: 0.20, T_TOU: 0.10, T_DRT: 0.30}, "v0_factor": 0.97, "a_max": 1.9},
	{"id": "hatchback-sports", "weights": {T_HWY: 0.15, T_ART: 0.15, T_CST: 0.15, T_TOU: 0.30, T_DRT: 0.10}, "v0_factor": 1.03, "a_max": 2.4},
	{"id": "truck", "weights": {T_HWY: 0.15, T_ART: 0.08, T_CST: 0.05, T_TOU: 0.0, T_DRT: 0.15}, "v0_factor": 0.85, "a_max": 1.0},
	{"id": "van", "weights": {T_HWY: 0.10, T_ART: 0.10, T_CST: 0.10, T_TOU: 0.05, T_DRT: 0.15}, "v0_factor": 0.92, "a_max": 1.5},
	{"id": "suv-luxury", "weights": {T_HWY: 0.10, T_ART: 0.07, T_CST: 0.10, T_TOU: 0.05, T_DRT: 0.05}, "v0_factor": 1.02, "a_max": 2.2},
	{"id": "taxi", "weights": {T_HWY: 0.02, T_ART: 0.08, T_CST: 0.02, T_TOU: 0.0, T_DRT: 0.0}, "v0_factor": 0.95, "a_max": 1.9},
	{"id": "delivery", "weights": {T_HWY: 0.05, T_ART: 0.07, T_CST: 0.03, T_TOU: 0.0, T_DRT: 0.05}, "v0_factor": 0.88, "a_max": 1.2},
	{"id": "sedan-sports", "weights": {T_HWY: 0.05, T_ART: 0.05, T_CST: 0.10, T_TOU: 0.30, T_DRT: 0.0}, "v0_factor": 1.05, "a_max": 2.6},
]

static var _cache: Array = []

## Loads (once per process) every type: [{id, mesh, half_len, half_wid, height,
## shape, weights, default_weight, v0_factor, a_max}]. A type whose GLB is missing
## is skipped; an empty kit falls back to a box mesh so traffic never breaks.
static func load_models() -> Array:
	if not _cache.is_empty():
		return _cache
	for t: Dictionary in TYPES:
		var entry := _load_type(t)
		if not entry.is_empty():
			_cache.append(entry)
	if _cache.is_empty():
		_cache.append(_fallback())
	return _cache

## The sim's view of the catalog (no resources).
static func sim_models(models: Array) -> Array:
	var out: Array = []
	for m: Dictionary in models:
		out.append({"half_len": m["half_len"], "half_wid": m["half_wid"], "v0_factor": m["v0_factor"],
			"a_max": m["a_max"], "weights": m["weights"], "default_weight": 0.0})
	return out

static func _load_type(t: Dictionary) -> Dictionary:
	var path: String = MODEL_DIR + String(t["id"]) + ".glb"
	if not ResourceLoader.exists(path):
		return {}
	var packed := load(path) as PackedScene
	if packed == null:
		return {}
	var inst := packed.instantiate()
	var tools := {}  # material -> SurfaceTool
	var order: Array = []
	var aabb := AABB()
	var first := true
	for n in _walk(inst):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf := _xf_to_root(mi, inst)
		var b := xf * mi.mesh.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
		for si in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(si)
			if not tools.has(mat):
				var st := SurfaceTool.new()
				tools[mat] = st
				order.append(mat)
			(tools[mat] as SurfaceTool).append_from(mi.mesh, si, xf)
	inst.free()
	if order.is_empty():
		return {}
	# Normalise: centre X/Z, bottom on y = 0, nose +Z, kit units -> metres.
	var centre := aabb.get_center()
	var norm := Transform3D(Basis.from_scale(KIT_SCALE).rotated(Vector3.UP, 0.0 if KIT_NOSE_SIGN > 0.0 else PI), Vector3.ZERO)
	norm = norm * Transform3D(Basis(), Vector3(-centre.x, -aabb.position.y, -centre.z))
	var mesh := ArrayMesh.new()
	for mat in order:
		var st := SurfaceTool.new()
		st.append_from((tools[mat] as SurfaceTool).commit(), 0, norm)
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	var size := aabb.size * KIT_SCALE
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, size.y * 0.9, size.z)
	return {
		"id": t["id"], "mesh": mesh, "shape": shape,
		"half_len": size.z * 0.5, "half_wid": size.x * 0.5, "height": size.y,
		"weights": t["weights"], "v0_factor": t["v0_factor"], "a_max": t["a_max"],
	}

static func _fallback() -> Dictionary:
	var box := BoxMesh.new()
	box.size = Vector3(1.9, 1.5, 4.4)
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.append_from(box, 0, Transform3D(Basis(), Vector3(0, 0.75, 0)))
	st.commit(mesh)
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.9, 1.35, 4.4)
	return {"id": "box", "mesh": mesh, "shape": shape, "half_len": 2.2, "half_wid": 0.95, "height": 1.5,
		"weights": {}, "v0_factor": 1.0, "a_max": 2.0}

static func _walk(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

static func _xf_to_root(n: Node3D, root_node: Node) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != root_node:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf
