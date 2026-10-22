# scripts/world/foliage.gd
class_name Foliage
extends Node3D

## Procedural countryside around the test circuit: an annulus of cheap grass
## tufts and low-poly trees, swayed by a light wind shader. Visuals only:
## no physics, no collisions, no top-level transform. Grass never casts
## shadows; trees do so they read against the sky and ground.

const GRASS_MESH_SIZE := Vector2(1.2, 0.8)
const GROUND_OFFSET_Y := 0.03
const TREE_HEIGHT := 10.0
const TREE_MIN_SPACING := 8.0
const TREE_PLACEMENT_ATTEMPTS := 32
const GRASS_ROAD_ATTEMPTS := 4
const GRASS_SHADER_PATH := "res://shaders/grass_wind.gdshader"
const TREE_SHADER_PATH := "res://shaders/foliage_wind.gdshader"

## P1 imported tree variants (CC0 Poly Pizza models, re-exported at
## 10.0 m, base at origin). Each variant becomes its own MultiMesh batch so the
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
## Square placement (RegionDresser regions): when > 0, positions are uniform
## over [-h, h]^2 around the node instead of the annulus, so neighbouring
## regions tile the map. 0 keeps the annulus (the hub and circuit foliage).
@export var square_half_extent: float = 0.0

var _rng := RandomNumberGenerator.new()
var _tree_roots: Array[Vector2] = []
var _positions: Dictionary = {}
## Shared across every Foliage node (static): the RegionDresser builds one per
## streamed region, and merging + re-baking the same tree GLB per region cost
## main-thread time and a duplicate GPU mesh each time. Never mutated after build.
static var _tree_mesh_cache: Dictionary = {}

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
## Optional extra placement rule, given a node-local (x, z) as Vector2 and
## returning false where nothing may grow (biome: snow, rock, beach; landmark
## clearings). Rejected samples are redrawn inside the existing bounded retry
## loops (the RNG stream length never changes); a slot whose final sample is
## still rejected is dropped, so counts only shrink where the filter says no.
## Unset (the default) keeps every legacy count exact.
var placement_filter: Callable = Callable()
## Optional grass-only rule (node-local XZ in, bool out). When set it REPLACES
## placement_filter + the road check for grass tufts: the RegionDresser passes
## a lookup into the baked ground control map (grass only on grass-family
## texels), which already excludes roads, shoulders, rock, sand and snow at a
## fraction of the cost of a road query per tuft. Trees keep the exact checks.
var grass_filter: Callable = Callable()
## Deferred grass (RegionDresser): generate() then builds only the trees and
## build_grass() adds the grass batch later, from its own RNG stream (seed ^
## GRASS_SEED_SALT), so a streamed region's two costliest batches land on
## different frames. Off (the default) keeps the legacy single-stream build.
var defer_grass := false
var _grass_last_ok := true
## Running time-sliced grass build (begin_grass / step_grass), empty when idle.
var _grass_job: Dictionary = {}

const GRASS_SEED_SALT := 0x5bd1e995

func _ready() -> void:
	generate()

## Builds both MultiMesh batches (grass + trees) synchronously. Idempotent:
## existing children are removed and the tree-root rejection history is cleared
## first, so re-generating (band density change, region re-entry) never stacks
## duplicate instances and stays bit-identical for a given seed. Density scales
## the instance counts for the LOD prefetch band. With defer_grass only the
## trees are built here (see build_grass).
func generate() -> void:
	for child in get_children():
		child.free()
	_tree_roots.clear()
	_positions.clear()
	_grass_job = {}  # a regenerate cancels any half-built grass batch
	_rng.seed = seed
	if not defer_grass:
		add_child(_build_grass())
	for mmi: MultiMeshInstance3D in _build_trees():
		add_child(mmi)

## Builds (or rebuilds) just the grass batch from its own deterministic stream
## in one go. Same result as begin_grass() + step_grass() until done.
func build_grass() -> void:
	begin_grass()
	step_grass(1 << 30)

## Starts a (re)build of the grass batch, time-sliced through step_grass() so
## the RegionDresser can spread one region's tufts over several frames. The
## slices draw from one deterministic stream, so the result is identical to a
## single build_grass(). Any previous grass batch is removed now.
func begin_grass() -> void:
	var old := get_node_or_null("GrassMMI")
	if old != null:
		old.free()
	_rng.seed = seed ^ GRASS_SEED_SALT
	var placed: Array[Transform3D] = []
	_grass_job = {"count": maxi(0, int(round(float(grass_count) * density))), "done": 0, "placed": placed}

## Places up to max_tufts more grass slots of the running job; returns true
## (and adds the GrassMMI batch) once every slot is done.
func step_grass(max_tufts: int) -> bool:
	if _grass_job.is_empty():
		return true
	var count: int = _grass_job["count"]
	var done: int = _grass_job["done"]
	var placed: Array[Transform3D] = _grass_job["placed"]
	var filtered := grass_filter.is_valid() or placement_filter.is_valid()
	var stop := mini(count, done + maxi(max_tufts, 1))
	while done < stop:
		var t := _grass_transform()
		done += 1
		if filtered and not _grass_last_ok:
			continue
		placed.append(t)
	_grass_job["done"] = done
	if done < count:
		return false
	_grass_job = {}
	add_child(_make_grass_mmi(placed))
	return true

func grass_job_active() -> bool:
	return not _grass_job.is_empty()

func has_grass_batch() -> bool:
	return get_node_or_null("GrassMMI") != null

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
	var count := maxi(0, int(round(float(grass_count) * density)))
	# Every slot draws its samples (the RNG stream never depends on the filter);
	# a slot whose last sample is still rejected by placement_filter is dropped.
	var placed: Array[Transform3D] = []
	var filtered := grass_filter.is_valid() or placement_filter.is_valid()
	for i in count:
		var t := _grass_transform()
		if filtered and not _grass_last_ok:
			continue
		placed.append(t)
	return _make_grass_mmi(placed)

func _make_grass_mmi(placed: Array[Transform3D]) -> MultiMeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = GRASS_MESH_SIZE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plane
	mm.instance_count = placed.size()
	var batch := PackedVector3Array()
	for i in placed.size():
		mm.set_instance_transform(i, placed[i])
		batch.append(placed[i].origin)
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
			if variant_pool[i] != v:
				continue
			# A fallback position the placement_filter still rejects is dropped.
			if placement_filter.is_valid() and not _placement_ok(positions[i]):
				continue
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

## Sets _grass_last_ok: whether the returned tuft passed the grass checks (the
## final redraw after GRASS_ROAD_ATTEMPTS misses is only checked against the
## filters, never the road, which keeps the legacy road fallback unchanged).
func _grass_transform() -> Transform3D:
	var pos := _annulus_pos()
	_grass_last_ok = false
	for _attempt in range(GRASS_ROAD_ATTEMPTS):
		if _grass_ok(pos):
			_grass_last_ok = true
			break
		pos = _annulus_pos()
	if not _grass_last_ok and (grass_filter.is_valid() or placement_filter.is_valid()):
		_grass_last_ok = _grass_ok(pos, false)
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
		if _spacing_ok(candidate) and _placement_ok(candidate) and _road_clear_of(candidate):
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
	if square_half_extent > 0.0:
		# Two draws, like the annulus, so both modes consume the same stream.
		var sx := _rng.randf_range(-square_half_extent, square_half_extent)
		var sz := _rng.randf_range(-square_half_extent, square_half_extent)
		return Vector2(sx, sz)
	# Uniform area sampling inside the ring [inner_clear_radius, radius].
	var angle := _rng.randf_range(0.0, TAU)
	var dist := sqrt(_rng.randf_range(inner_clear_radius * inner_clear_radius, radius * radius))
	return Vector2(cos(angle), sin(angle)) * dist

func _world_pos(xz: Vector2) -> Vector3:
	var gt := global_transform if is_inside_tree() else transform
	return gt.origin + gt.basis * Vector3(xz.x, 0.0, xz.y)

## Grass acceptance: grass_filter alone when set, else placement_filter plus
## (unless skipped) the road clearance.
func _grass_ok(xz: Vector2, check_road: bool = true) -> bool:
	if grass_filter.is_valid():
		return bool(grass_filter.call(xz))
	if not _placement_ok(xz):
		return false
	return not check_road or _road_clear_of(xz)

func _placement_ok(xz: Vector2) -> bool:
	if not placement_filter.is_valid():
		return true
	return bool(placement_filter.call(xz))

func _road_clear_of(xz: Vector2) -> bool:
	if road_network == null:
		return true
	return PropScatterer.is_clear_of_road(_world_pos(xz), road_network)
