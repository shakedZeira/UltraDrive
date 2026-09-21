# scripts/world/foliage.gd
class_name Foliage
extends Node3D

## Procedural countryside around the test circuit: an annulus of cheap grass
## tufts and low-poly trees, swayed by a light wind shader. Visuals only:
## no physics, no collisions, no top-level transform. Grass never casts
## shadows; trees do so they read against the sky and ground.

const GRASS_MESH_SIZE := Vector2(1.2, 0.8)
const GROUND_OFFSET_Y := 0.03
const TREE_HEIGHT := 4.6
const TREE_MIN_SPACING := 8.0
const TREE_PLACEMENT_ATTEMPTS := 32
const GRASS_ROAD_ATTEMPTS := 4
const GRASS_SHADER_PATH := "res://shaders/grass_wind.gdshader"
const TREE_SHADER_PATH := "res://shaders/foliage_wind.gdshader"

## P1 imported tree variants (CC0 Quaternius via Poly Pizza, re-exported at
## 4.6 m, base at origin). Each variant becomes its own MultiMesh batch so the
## same scene can draw a mixed forest; all share the wind shader override.
## Counts are split across the variants and must sum to tree_count so the
## live-ring/prefetch totals (40 / 20) stay exact.
const TREE_MODELS := [
	"res://assets/trees/tree_a.glb",
	"res://assets/trees/tree_b.glb",
	"res://assets/trees/tree_c.glb",
]
const TREE_MODEL_COUNTS := [14, 14, 12]
const TREES_BATCH_NAMES := ["TreesMMI", "TreesMMI_B", "TreesMMI_C"]

@export var radius: float = 140.0
@export var inner_clear_radius: float = 78.0
@export var grass_count: int = 700
@export var tree_count: int = 40
@export var seed: int = 2120

var _rng := RandomNumberGenerator.new()
var _tree_roots: Array[Vector2] = []
var _positions: Dictionary = {}
var _tree_mesh_cache: Dictionary = {}

## P7 per-region dressing state. When managed by a RegionDresser these identify
## the region and the LOD density generated into it (full counts on the live
## ring, reduced counts on the prefetch band). Standalone use keeps the defaults
## (Vector2i.ZERO / 1.0). Configured via configure_for_region() before the
## first generate() in _ready.
var region_key := Vector2i.ZERO
var density := 1.0

## Optional map-height lookup, given a world (x, z) position as Vector2,
## returning the ground surface Y at that spot. When unset, items sit at Y 0
## (the flat-floor default used by the oval circuit).
var ground_height_provider: Callable = Callable()
var road_network: RoadNetwork = null

func _ready() -> void:
	generate()

## Builds both MultiMesh batches (grass + trees) synchronously. Idempotent:
## existing children are removed and the tree-root rejection history is cleared
## first, so re-generating (band density change, region re-entry) never stacks
## duplicate instances and stays bit-identical for a given seed. Density scales
## the instance counts for the LOD prefetch band.
func generate() -> void:
	for child in get_children():
		child.free()
	_tree_roots.clear()
	_positions.clear()
	_rng.seed = seed
	add_child(_build_grass())
	for mmi: MultiMeshInstance3D in _build_trees():
		add_child(mmi)

## P7 per-region hook (RegionDresser): pins this instance to a region, its
## deterministic per-region seed and the LOD density for the prefetch band.
## Generation happens via generate()/_ready after this is set, so re-entry is
## bit-identical for a given region.
func configure_for_region(p_region_key: Vector2i, p_seed: int, p_density: float = 1.0) -> void:
	region_key = p_region_key
	seed = p_seed
	density = maxf(p_density, 0.0)

## Updates the wind sway amount on every foliage material at runtime.
func set_wind_strength(strength: float) -> void:
	for child in get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi != null and mmi.material_override is ShaderMaterial:
			mmi.material_override.set_shader_parameter("wind_strength", strength)

## P7 LOD knob for distance-banded instance culling: caps drawn instances per
## MultiMesh, clamped into [0, instance_count]. Cheap runtime control that
## complements the generation-time density scale.
func set_visible_instance_count(count: int) -> void:
	var capped := maxi(count, 0)
	for child in get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi != null and mmi.multimesh != null:
			mmi.multimesh.visible_instance_count = mini(capped, int(mmi.multimesh.instance_count))

## Total visible-cap sum across every batch: the number of instances actually
## drawn given the current band budget (live = full placement, prefetch = the
## culled fraction). Works after _apply_band_budget caps each batch's
## visible_instance_count; -1 (engine default = draw all) counts as the full
## batch size, mirroring get_instance_count().
func get_visible_instance_count() -> int:
	var total := 0
	for child in get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		var vis := int(mmi.multimesh.visible_instance_count)
		total += vis if vis >= 0 else int(mmi.multimesh.instance_count)
	return total

## All foliage instance origins (node-local), concatenated across the batches.
## Used to prove bit-identical re-entry placement for a per-region seed. Reads
## the positions captured at generate time (MultiMesh transform read-back does
## not round-trip CPU-side in this engine build).
func get_instance_positions() -> PackedVector3Array:
	var result := PackedVector3Array()
	for mmi in get_children():
		var batch := _positions.get(mmi.name, PackedVector3Array()) as PackedVector3Array
		result.append_array(batch)
	return result

## Positions for a single batch, captured at generate. "TreesMMI" aggregates
## every tree variant batch so callers (e.g. road-clearance checks) see every
## tree regardless of which mesh a slot drew.
func get_batch_positions(mmi_name: String) -> PackedVector3Array:
	if mmi_name == "TreesMMI":
		var result := PackedVector3Array()
		for key: String in _positions.keys():
			if key.begins_with("TreesMMI"):
				result.append_array(_positions[key] as PackedVector3Array)
		return result
	return _positions.get(mmi_name, PackedVector3Array()) as PackedVector3Array

## The primary tree-batch mesh (merged imported GLB, single surface). Used by
## the P1 gate to prove foliage no longer draws primitive geometry.
func get_tree_mesh() -> ArrayMesh:
	for child in get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi != null and mmi.name == "TreesMMI" and mmi.multimesh != null:
			return mmi.multimesh.mesh as ArrayMesh
	return null

## Total placed instance count across all batches (mirrors PropScatterer).
func get_instance_count() -> int:
	var total := 0
	for child in get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi != null and mmi.multimesh != null:
			total += int(mmi.multimesh.instance_count)
	return total

func _build_grass() -> MultiMeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = GRASS_MESH_SIZE

	var count := maxi(0, int(round(float(grass_count) * density)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plane
	mm.instance_count = count
	var batch := PackedVector3Array()
	for i in count:
		var t := _grass_transform()
		mm.set_instance_transform(i, t)
		batch.append(t.origin)
	_positions["GrassMMI"] = batch

	var mat := ShaderMaterial.new()
	mat.shader = load(GRASS_SHADER_PATH) as Shader
	mat.set_shader_parameter("wind_strength", 0.05)

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "GrassMMI"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi

## One MultiMesh batch per tree variant (TreesMMI, TreesMMI_B, TreesMMI_C).
## Placement is a single RNG stream drawn up front (pos/yaw/scale per slot), so
## the variant split never shifts the stream and re-entry stays bit-identical.
func _build_trees() -> Array[MultiMeshInstance3D]:
	var counts := _tree_variant_counts()
	var total := 0
	for c in counts:
		total += c

	var positions: Array[Vector2] = []
	var yaws: Array[float] = []
	var scales: Array[float] = []
	for i in total:
		positions.append(_tree_pos())
		yaws.append(_rng.randf_range(0.0, TAU))
		scales.append(_rng.randf_range(0.8, 1.3))

	# Deterministic slot->variant assignment: a sorted pool of the scaled counts.
	var variant_pool: PackedInt32Array = []
	for v in counts.size():
		for _k in counts[v]:
			variant_pool.append(v)

	var mat := ShaderMaterial.new()
	mat.shader = load(TREE_SHADER_PATH) as Shader
	mat.set_shader_parameter("wind_strength", 0.05)

	var result: Array[MultiMeshInstance3D] = []
	for v in counts.size():
		var slots_for_v: Array[int] = []
		for i in total:
			if variant_pool[i] == v:
				slots_for_v.append(i)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _build_tree_mesh(TREE_MODELS[v])
		mm.instance_count = slots_for_v.size()
		var batch := PackedVector3Array()
		for k in slots_for_v.size():
			var idx := slots_for_v[k]
			var pos: Vector2 = positions[idx]
			var basis := Basis(Vector3.UP, yaws[idx]).scaled(Vector3.ONE * scales[idx])
			var t := Transform3D(basis, Vector3(pos.x, _ground_height(pos) + GROUND_OFFSET_Y, pos.y))
			mm.set_instance_transform(k, t)
			batch.append(t.origin)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = TREES_BATCH_NAMES[v]
		mmi.multimesh = mm
		mmi.material_override = mat
		_positions[mmi.name] = batch
		result.append(mmi)
	return result

## Splits the density-scaled tree budget between the variants proportionally to
## TREE_MODEL_COUNTS (largest remainder), so counts always sum exactly to the
## scaled total (40 live, 20 at the 0.5 prefetch band).
func _tree_variant_counts() -> Array[int]:
	var total := maxi(0, int(round(float(tree_count) * density)))
	var weights := TREE_MODEL_COUNTS
	var wsum := 0
	for w in weights:
		wsum += w
	var out: Array[int] = []
	if wsum <= 0:
		out.append(total)
		return out
	var fracs: Array[float] = []
	var assigned := 0
	for w in weights:
		var exact := float(w) * float(total) / float(wsum)
		var c := int(floor(exact))
		out.append(c)
		assigned += c
		fracs.append(exact - float(c))
	var guard := 0
	while assigned < total and guard < weights.size() + 8:
		var best := -1
		var best_f := -1.0
		for k in fracs.size():
			if fracs[k] > best_f:
				best_f = fracs[k]
				best = k
		if best < 0:
			break
		out[best] += 1
		fracs[best] = -1.0
		assigned += 1
		guard += 1
	return out

func _build_tree_mesh(path: String) -> ArrayMesh:
	if _tree_mesh_cache.has(path):
		return _tree_mesh_cache[path]
	var scene := load(path) as PackedScene
	var inst := scene.instantiate()
	var entries: Array = []
	_collect_mesh_instances(inst, entries, Transform3D.IDENTITY)
	inst.free()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for entry in entries:
		var m: ArrayMesh = entry[0]
		var xform: Transform3D = entry[1]
		for s in m.get_surface_count():
			st.append_from(m, s, xform)
	st.generate_normals()
	var tree_mesh := st.commit()
	_bake_tree_height_uvs(tree_mesh)
	_tree_mesh_cache[path] = tree_mesh
	return tree_mesh

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

func _bake_tree_height_uvs(tree_mesh: ArrayMesh) -> void:
	# Rewrite UV.y as normalized height (0 = ground, 1 = canopy tip) so the
	# shader can split bark vs leaf with a single uv.y comparison. Some CC0
	# trees ship without any UV layer; synthesize a (0,0) layer for those.
	var arrays := tree_mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs := PackedVector2Array()
	if arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array:
		uvs = arrays[Mesh.ARRAY_TEX_UV]
	if uvs.size() < verts.size():
		uvs.resize(verts.size())
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	for i in uvs.size():
		uvs[i] = Vector2(maxf(uvs[i].x, 0.0), clampf(verts[i].y / TREE_HEIGHT, 0.0, 1.0))
	tree_mesh.surface_remove(0)
	tree_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func _grass_transform() -> Transform3D:
	var pos := _annulus_pos()
	for _attempt in range(GRASS_ROAD_ATTEMPTS):
		if _road_clear_of(pos):
			break
		pos = _annulus_pos()
	var yaw := _rng.randf_range(0.0, TAU)
	var scale := _rng.randf_range(0.8, 1.6)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
	return Transform3D(basis, Vector3(pos.x, _ground_height(pos) + GROUND_OFFSET_Y, pos.y))

## Ground surface Y at a map position; falls back to 0 for flat circuits.
func _ground_height(pos: Vector2) -> float:
	if ground_height_provider.is_valid():
		return ground_height_provider.call(pos)
	return 0.0

func _tree_pos() -> Vector2:
	# Rejection sampling keeps roughly 8 m between tree trunks.
	for attempt in range(TREE_PLACEMENT_ATTEMPTS):
		var candidate := _annulus_pos()
		if _spacing_ok(candidate) and _road_clear_of(candidate):
			_tree_roots.append(candidate)
			return candidate
	var fallback := _annulus_pos()
	_tree_roots.append(fallback)
	return fallback

func _spacing_ok(pos: Vector2) -> bool:
	for root: Vector2 in _tree_roots:
		if pos.distance_to(root) < TREE_MIN_SPACING:
			return false
	return true

func _annulus_pos() -> Vector2:
	# Uniform area sampling inside the ring [inner_clear_radius, radius].
	var angle := _rng.randf_range(0.0, TAU)
	var dist := sqrt(_rng.randf_range(inner_clear_radius * inner_clear_radius, radius * radius))
	return Vector2(cos(angle), sin(angle)) * dist

func _world_pos(xz: Vector2) -> Vector3:
	var gt := global_transform if is_inside_tree() else transform
	return gt.origin + gt.basis * Vector3(xz.x, 0.0, xz.y)

func _road_clear_of(xz: Vector2) -> bool:
	if road_network == null:
		return true
	return PropScatterer.is_clear_of_road(_world_pos(xz), road_network)
