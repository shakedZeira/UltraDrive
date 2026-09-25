# scripts/world/prop_scatterer.gd
class_name PropScatterer
extends Node3D

## Generic low-cost prop scatterer for the open world. One MultiMesh per prop
## type (guardrail / tent / power pole / rock), all meshes built from fused
## primitives at runtime so there are zero external assets. Candidates are
## rejection-sampled inside a disc annulus, spaced out, and rejected whenever
## they land on/near a road (RoadNetwork.is_on_road). Props are visual only:
## no physics, no collision, no top-level transform. Deterministic for a given
## seed; counts are bounded by the preset and every retry loop is capped so
## placement can never hang. Zones are wired by calling configure() with a
## Dictionary preset (see default_preset() for per-zone examples).

const MAX_PLACEMENT_ATTEMPTS := 64
const GROUND_OFFSET_Y := 0.0
const ROAD_CLEARANCE_MARGIN := 3.0

## P1/P2/P4 imported CC0 meshes (Kenney Racing Kit + Quaternius via Poly Pizza),
## loaded once per scatterer and cached. Kenney GLBs are single-node
## single-mesh (multi-surface with native materials) so MultiMesh instances them
## directly; fused fallbacks get a flat-colour material instead.
const TRACK_BARRIER_PATH := "res://assets/track_props/track_barrier.glb"
const TRACK_RAIL_PATH := "res://assets/track_props/track_rail.glb"
const TRACK_CONE_PATH := "res://assets/track_props/track_cone.glb"
const GRANDSTAND_PATH := "res://assets/track_props/grandstand.glb"
const LIGHT_POLE_PATH := "res://assets/track_props/light_pole.glb"
const FINISH_GANTRY_PATH := "res://assets/track_props/finish_gantry.glb"
const PIT_GARAGE_PATH := "res://assets/buildings/building_pit_garage.glb"
const PIT_OFFICE_PATH := "res://assets/buildings/building_pit_office.glb"
const ROCK_PATH := "res://assets/rocks/rock_a.glb"
const RACING_BARRIER_RED_PATH := "res://assets/track_props/racing_barrier_red.glb"
const RACING_PYLON_PATH := "res://assets/track_props/racing_pylon.glb"
const RACING_GRANDSTAND_PATH := "res://assets/track_props/racing_grandstand.glb"
const RACING_RAIL_DOUBLE_PATH := "res://assets/track_props/racing_rail_double.glb"
const RACING_FLAG_CHECKERS_PATH := "res://assets/track_props/racing_flag_checkers.glb"
const RACING_TENT_PATH := "res://assets/track_props/racing_tent.glb"

## Real-mesh prop types ship native surface materials from their GLBs; the
## primitive types (guardrail / tent / power_pole) still get a tinted override.
const NATIVE_MATERIAL_TYPES := [
	"track_barrier", "track_rail", "track_cone", "grandstand",
	"light_pole", "finish_gantry", "pit_garage", "pit_office", "rock",
	"racing_barrier_red", "racing_pylon", "racing_grandstand",
	"racing_rail_double", "racing_flag_checkers", "racing_tent",
]

@export var radius: float = 300.0
@export var inner_clear_radius: float = 0.0
@export var seed: int = 1000
@export var road_threshold: float = 6.0
@export var placement_attempts: int = MAX_PLACEMENT_ATTEMPTS

## Optional map-height lookup, given a world (x, z) position as Vector2,
## returning the ground surface Y at that spot. When unset, props sit at Y 0
## (the flat-floor default used by the standalone circuits).
var ground_height_provider: Callable = Callable()

## Road network used for placement exclusion; when unset props scatter freely.
var road_network: RoadNetwork = null

var _rng := RandomNumberGenerator.new()
var _preset: Dictionary = {}
var _placed: Dictionary = {}  # prop_type -> PackedVector3Array of positions
var _mesh_builders: Dictionary = {}
var _materials: Dictionary = {}
var _real_mesh_cache: Dictionary = {}  # GLB path -> cached ArrayMesh

## P7 per-region dressing state. When the scatterer is managed by a
## RegionDresser these identify the region it belongs to and the LOD density
## generated into it (full counts on the live ring, reduced counts on the
## prefetch band). Purely advisory for standalone use (Vector2i.ZERO / 1.0);
## configured via configure_for_region() before generate().
var region_key := Vector2i.ZERO
var density := 1.0

func _init() -> void:
	_mesh_builders = {
		"guardrail": _build_guardrail_mesh,
		"tent": _build_tent_mesh,
		"power_pole": _build_power_pole_mesh,
		"rock": _build_rock_mesh,
		"track_barrier": _build_track_barrier_mesh,
		"track_rail": _build_track_rail_mesh,
		"track_cone": _build_track_cone_mesh,
		"grandstand": _build_grandstand_mesh,
		"light_pole": _build_light_pole_mesh,
		"finish_gantry": _build_finish_gantry_mesh,
		"pit_garage": _build_pit_garage_mesh,
		"pit_office": _build_pit_office_mesh,
		"racing_barrier_red": _build_racing_barrier_red_mesh,
		"racing_pylon": _build_racing_pylon_mesh,
		"racing_grandstand": _build_racing_grandstand_mesh,
		"racing_rail_double": _build_racing_rail_double_mesh,
		"racing_flag_checkers": _build_racing_flag_checkers_mesh,
		"racing_tent": _build_racing_tent_mesh,
	}

func _ready() -> void:
	generate()

## Replaces the current preset. Any key not present keeps its current value.
func configure(preset: Dictionary) -> void:
	radius = float(preset.get("radius", radius))
	inner_clear_radius = float(preset.get("inner_clear_radius", inner_clear_radius))
	seed = int(preset.get("seed", seed))
	road_threshold = float(preset.get("road_threshold", road_threshold))
	placement_attempts = maxi(int(preset.get("placement_attempts", placement_attempts)), 1)
	_preset = preset

## P7 per-region hook (RegionDresser): pins this scatterer to a region and its
## deterministic seed, and sets the LOD density for the prefetch band. Does not
## generate -- callers call generate() once the scatterer is fully configured
## (RegionDresser relies on _ready wiring, so the first generate runs on
## add_child; later ones are explicit) so re-entry is bit-identical.
func configure_for_region(p_region_key: Vector2i, p_seed: int, p_density: float = 1.0) -> void:
	region_key = p_region_key
	seed = p_seed
	density = maxf(p_density, 0.0)

## Builds all prop MultiMesh instances synchronously. Idempotent: any existing
## children are removed first, so re-generating (or being called from _ready)
## never stacks duplicate batches.
func generate() -> void:
	for child in get_children():
		child.free()
	_rng.seed = seed
	_placed.clear()
	var props: Dictionary = _preset.get("props", {})
	for prop_type: String in props.keys():
		if not _mesh_builders.has(prop_type):
			continue
		var entry: Dictionary = props[prop_type]
		var positions := _place_prop(entry)
		_placed[prop_type] = positions
		if positions.size() > 0:
			add_child(_build_mmi(prop_type, positions, entry))

## World positions (ground-bound) of every placed instance of a prop type.
func get_instance_transforms(prop_type: String) -> PackedVector3Array:
	return _placed.get(prop_type, PackedVector3Array()) as PackedVector3Array

## Total number of placed instances across all prop types.
func get_instance_count() -> int:
	var total := 0
	for prop_type: String in _placed.keys():
		total += (_placed[prop_type] as PackedVector3Array).size()
	return total

## P7 LOD knob for distance-banded instance culling: caps how many of the
## placed instances are drawn per MultiMesh, clamped into [0, instance_count]
## so the value stays valid. Cheap at runtime (no re-generation), complements
## the generation-time density scale.
func set_visible_instance_count(count: int) -> void:
	var capped := maxi(count, 0)
	for child in get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi != null and mmi.multimesh != null:
			mmi.multimesh.visible_instance_count = mini(capped, int(mmi.multimesh.instance_count))

## Current per-child visible-instance cap (the first child's), or -1 when no
## MultiMesh is built yet (-1 is the engine default: every instance drawn).
func get_visible_instance_count() -> int:
	for child in get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi != null and mmi.multimesh != null:
			return int(mmi.multimesh.visible_instance_count)
	return -1

## Every placed prop position across all prop types (node-local), concatenated.
## Used to prove bit-identical per-region placement on re-entry.
func get_instance_positions() -> PackedVector3Array:
	var result := PackedVector3Array()
	for prop_type: String in _placed.keys():
		result.append_array(_placed[prop_type] as PackedVector3Array)
	return result

## Per-zone presets mirroring plan Section 5. Counts stay small (14-28 props
## per zone); the integration agent may tune or replace these Dictionaries.
static func default_preset(zone: String) -> Dictionary:
	match zone:
		"festival":
			return {
				"radius": 200.0, "inner_clear_radius": 90.0, "seed": 1001,
				"road_threshold": 8.0,
				"props": {
					"tent": {"count": 12, "min_spacing": 16.0, "scale": Vector2(0.9, 1.2)},
					"grandstand": {"count": 3, "min_spacing": 70.0, "scale": Vector2(8.0, 10.0)},
					"pit_garage": {"count": 4, "min_spacing": 34.0, "scale": Vector2(6.0, 6.5)},
					"pit_office": {"count": 3, "min_spacing": 34.0, "scale": Vector2(6.0, 6.5)},
					"track_barrier": {"count": 8, "min_spacing": 16.0, "scale": Vector2(4.0, 4.5)},
					"track_cone": {"count": 6, "min_spacing": 12.0, "scale": Vector2(4.0, 5.0)},
					"racing_barrier_red": {"count": 6, "min_spacing": 14.0, "scale": Vector2(3.0, 4.0)},
					"racing_pylon": {"count": 4, "min_spacing": 10.0, "scale": Vector2(5.0, 6.0)},
					"racing_grandstand": {"count": 1, "min_spacing": 60.0, "scale": Vector2(6.0, 8.0)},
					"racing_rail_double": {"count": 6, "min_spacing": 18.0, "scale": Vector2(3.0, 4.5)},
					"racing_flag_checkers": {"count": 1, "min_spacing": 30.0, "scale": Vector2(2.5, 3.0)},
					"racing_tent": {"count": 3, "min_spacing": 20.0, "scale": Vector2(4.0, 5.0)},
				},
			}
		"lowlands":
			return {
				"radius": 400.0, "inner_clear_radius": 30.0, "seed": 1002,
				"road_threshold": 10.0,
				"props": {
					"power_pole": {"count": 8, "min_spacing": 90.0, "scale": Vector2(0.9, 1.1)},
					"rock": {"count": 20, "min_spacing": 12.0, "scale": Vector2(0.8, 1.6)},
					"track_rail": {"count": 10, "min_spacing": 22.0, "scale": Vector2(2.5, 3.5)},
				},
			}
		"coast":
			return {
				"radius": 400.0, "inner_clear_radius": 20.0, "seed": 1003,
				"road_threshold": 8.0,
				"props": {
					"rock": {"count": 24, "min_spacing": 15.0, "scale": Vector2(1.4, 2.4)},
					"track_rail": {"count": 8, "min_spacing": 24.0, "scale": Vector2(2.5, 3.5)},
				},
			}
		"highlands":
			return {
				"radius": 500.0, "inner_clear_radius": 40.0, "seed": 1004,
				"road_threshold": 11.0,
				"props": {
					"guardrail": {"count": 26, "min_spacing": 16.0, "scale": Vector2(1.0, 1.0)},
					"racing_barrier_red": {"count": 6, "min_spacing": 16.0, "scale": Vector2(3.0, 4.0)},
					"racing_pylon": {"count": 4, "min_spacing": 12.0, "scale": Vector2(5.0, 6.0)},
					"racing_grandstand": {"count": 1, "min_spacing": 70.0, "scale": Vector2(6.0, 8.0)},
					"racing_rail_double": {"count": 6, "min_spacing": 20.0, "scale": Vector2(3.0, 4.5)},
				},
			}
		"alpine":
			return {
				"radius": 500.0, "inner_clear_radius": 50.0, "seed": 1005,
				"road_threshold": 11.0,
				"props": {"rock": {"count": 18, "min_spacing": 20.0, "scale": Vector2(1.2, 2.2)}},
			}
	return {
		"radius": 300.0, "inner_clear_radius": 0.0, "seed": 1000,
		"road_threshold": 8.0, "props": {},
	}

static func _point_segment_distance_xz(pos: Vector3, a: Vector3, b: Vector3) -> float:
	var abx := b.x - a.x
	var abz := b.z - a.z
	var len2 := abx * abx + abz * abz
	if len2 <= 0.0001:
		var dx := pos.x - a.x
		var dz := pos.z - a.z
		return sqrt(dx * dx + dz * dz)
	var t := clampf(((pos.x - a.x) * abx + (pos.z - a.z) * abz) / len2, 0.0, 1.0)
	var cx := a.x + abx * t
	var cz := a.z + abz * t
	var ex := pos.x - cx
	var ez := pos.z - cz
	return sqrt(ex * ex + ez * ez)

static func road_clearance_info(pos: Vector3, defs: Array[RoadDef]) -> Dictionary:
	var best := INF
	var half_width := 0.0
	for def: RoadDef in defs:
		var pts: Array[Vector3] = def.points
		var count := pts.size()
		if count < 2:
			continue
		for i in range(count - 1):
			var d := _point_segment_distance_xz(pos, pts[i], pts[i + 1])
			if d < best:
				best = d
				half_width = def.width * 0.5
		if def.closed and count > 2:
			var d := _point_segment_distance_xz(pos, pts[count - 1], pts[0])
			if d < best:
				best = d
				half_width = def.width * 0.5
	return {"distance": best, "half_width": half_width}

static func is_clear_of_road(pos: Vector3, network: RoadNetwork, floor_m: float = 0.0) -> bool:
	if network == null:
		return true
	var info := road_clearance_info(pos, network.get_road_defs())
	return float(info["distance"]) >= maxf(floor_m, float(info["half_width"]) + ROAD_CLEARANCE_MARGIN)

func _place_prop(entry: Dictionary) -> PackedVector3Array:
	var base_count := int(entry.get("count", 0))
	var count := maxi(0, int(round(float(base_count) * density)))
	var min_spacing := float(entry.get("min_spacing", 6.0))
	var used: Array[Vector2] = []
	var result := PackedVector3Array()
	for _i in range(count):
		for _attempt in range(placement_attempts):
			var pos_2d := _annulus_pos()
			var pos := Vector3(pos_2d.x, _ground_height(pos_2d), pos_2d.y)
			if _spacing_ok(pos_2d, used, min_spacing) and _road_ok(pos):
				used.append(pos_2d)
				result.append(pos)
				break
	return result

func _build_mmi(prop_type: String, positions: PackedVector3Array, entry: Dictionary) -> MultiMeshInstance3D:
	var builder: Callable = _mesh_builders[prop_type]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = builder.call()
	mm.instance_count = positions.size()
	var scale_range := Vector2(0.8, 1.2)
	var scale_raw: Variant = entry.get("scale", scale_range)
	if scale_raw is Vector2:
		scale_range = scale_raw
	var ground_offset := float(entry.get("ground_offset", GROUND_OFFSET_Y))
	for i in positions.size():
		var p: Vector3 = positions[i]
		var yaw := _rng.randf_range(0.0, TAU)
		var s := _rng.randf_range(scale_range.x, scale_range.y)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s)
		mm.set_instance_transform(i, Transform3D(basis, Vector3(p.x, p.y + ground_offset, p.z)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "%sMMI" % prop_type
	mmi.multimesh = mm
	mmi.material_override = _effective_material(prop_type, mm.mesh as ArrayMesh)
	return mmi

## MultiMesh material: primitive types always get a tinted override; imported
## GLB types keep their native surface materials when they ship any, and only
## fall back to a flat colour when the mesh carries none (e.g. fused parts).
func _effective_material(prop_type: String, mesh: ArrayMesh) -> StandardMaterial3D:
	if prop_type in NATIVE_MATERIAL_TYPES:
		if mesh != null and mesh.get_surface_count() > 0 and mesh.surface_get_material(0) != null:
			return null
		return _default_material(prop_type)
	return _prop_material(prop_type)

func _prop_material(prop_type: String) -> StandardMaterial3D:
	if _materials.has(prop_type):
		return _materials[prop_type]
	var mat := StandardMaterial3D.new()
	match prop_type:
		"guardrail":
			mat.albedo_color = Color(0.6, 0.62, 0.66)
			mat.metallic = 0.6
			mat.roughness = 0.45
		"tent":
			mat.albedo_color = Color(0.78, 0.22, 0.16)
			mat.roughness = 0.95
		"power_pole":
			mat.albedo_color = Color(0.42, 0.32, 0.22)
			mat.roughness = 0.9
		_:
			mat.albedo_color = Color(0.48, 0.49, 0.52)
			mat.roughness = 0.95
	_materials[prop_type] = mat
	return mat

func _build_guardrail_mesh() -> ArrayMesh:
	# One roadside segment: a single post plus the rail above it (~24 tris).
	var post := BoxMesh.new()
	post.size = Vector3(0.16, 0.9, 0.16)
	var rail := BoxMesh.new()
	rail.size = Vector3(0.1, 0.08, 2.0)
	return _fuse([
		[post, Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0))],
		[rail, Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 0))],
	])

func _build_tent_mesh() -> ArrayMesh:
	# Festival stall: a low box base with a single-slope PrismMesh roof
	# leaning back over it (~20 tris).
	var base := BoxMesh.new()
	base.size = Vector3(2.6, 0.12, 2.0)
	var roof := PrismMesh.new()
	roof.size = Vector3(3.0, 1.2, 2.2)
	roof.left_to_right = 0.5
	return _fuse([
		[base, Transform3D(Basis.IDENTITY, Vector3(0, 0.06, 0))],
		[roof, Transform3D(Basis.IDENTITY, Vector3(0, 1.32, 0))],
	])

func _build_power_pole_mesh() -> ArrayMesh:
	# Vertical pole plus crossarm (~24 tris).
	var pole := BoxMesh.new()
	pole.size = Vector3(0.18, 6.0, 0.18)
	var arm := BoxMesh.new()
	arm.size = Vector3(3.2, 0.14, 0.14)
	return _fuse([
		[pole, Transform3D(Basis.IDENTITY, Vector3(0, 3.0, 0))],
		[arm, Transform3D(Basis.IDENTITY, Vector3(0, 5.4, 0))],
	])

func _build_rock_mesh() -> ArrayMesh:
	return _load_prop_mesh(ROCK_PATH)

## --- Imported CC0 prop meshes (P1/P2/P4) -------------------------------

func _build_track_barrier_mesh() -> ArrayMesh:
	return _load_prop_mesh(TRACK_BARRIER_PATH)

func _build_track_rail_mesh() -> ArrayMesh:
	return _load_prop_mesh(TRACK_RAIL_PATH)

func _build_track_cone_mesh() -> ArrayMesh:
	return _load_prop_mesh(TRACK_CONE_PATH)

func _build_grandstand_mesh() -> ArrayMesh:
	return _load_prop_mesh(GRANDSTAND_PATH)

func _build_light_pole_mesh() -> ArrayMesh:
	return _load_prop_mesh(LIGHT_POLE_PATH)

func _build_finish_gantry_mesh() -> ArrayMesh:
	return _load_prop_mesh(FINISH_GANTRY_PATH)

func _build_pit_garage_mesh() -> ArrayMesh:
	return _load_prop_mesh(PIT_GARAGE_PATH)

func _build_pit_office_mesh() -> ArrayMesh:
	return _load_prop_mesh(PIT_OFFICE_PATH)

func _build_racing_barrier_red_mesh() -> ArrayMesh:
	return _load_prop_mesh(RACING_BARRIER_RED_PATH)

func _build_racing_pylon_mesh() -> ArrayMesh:
	return _load_prop_mesh(RACING_PYLON_PATH)

func _build_racing_grandstand_mesh() -> ArrayMesh:
	return _load_prop_mesh(RACING_GRANDSTAND_PATH)

func _build_racing_rail_double_mesh() -> ArrayMesh:
	return _load_prop_mesh(RACING_RAIL_DOUBLE_PATH)

func _build_racing_flag_checkers_mesh() -> ArrayMesh:
	return _load_prop_mesh(RACING_FLAG_CHECKERS_PATH)

func _build_racing_tent_mesh() -> ArrayMesh:
	return _load_prop_mesh(RACING_TENT_PATH)

## Loads a GLB PackedScene and resolves it to one MultiMesh-friendly mesh,
## cached per path. A single MeshInstance3D (whatever its baked node transform,
## e.g. the wrapper glTF import adds) keeps its native multi-surface materials;
## multiple nodes are fused into one surface (material-less flat fallback).
func _load_prop_mesh(path: String) -> ArrayMesh:
	if _real_mesh_cache.has(path):
		return _real_mesh_cache[path]
	var scene := load(path) as PackedScene
	var inst := scene.instantiate()
	var entries: Array = []
	_collect_mesh_instances(inst, entries, Transform3D.IDENTITY)
	inst.free()
	var mesh: ArrayMesh
	if entries.size() == 1:
		mesh = _bake_prop_mesh(entries[0][0] as ArrayMesh, entries[0][1] as Transform3D)
	else:
		mesh = _fuse_entries(entries)
	_real_mesh_cache[path] = mesh
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

## Flat fallback for an imported mesh that ships without surface materials.
func _default_material(prop_type: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	match prop_type:
		"rock":
			mat.albedo_color = Color(0.45, 0.45, 0.47)
			mat.roughness = 0.95
		_:
			mat.albedo_color = Color(0.62, 0.62, 0.65)
			mat.roughness = 0.9
	return mat

func _fuse(parts: Array) -> ArrayMesh:
	# Fuses primitives into ONE ArrayMesh surface so MultiMesh can instance it
	# (same approach as foliage.gd::_build_tree_mesh).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		st.append_from(part[0] as Mesh, 0, part[1] as Transform3D)
	return st.commit()

func _road_ok(pos: Vector3) -> bool:
	if road_network == null:
		return true
	return PropScatterer.is_clear_of_road(_world_pos(pos), road_network, road_threshold)

func _world_pos(pos: Vector3) -> Vector3:
	var gt := global_transform if is_inside_tree() else transform
	return gt.origin + gt.basis * Vector3(pos.x, 0.0, pos.z)

func _spacing_ok(pos: Vector2, used: Array[Vector2], min_spacing: float) -> bool:
	for root: Vector2 in used:
		if pos.distance_to(root) < min_spacing:
			return false
	return true

## Uniform area sampling inside the disc ring [inner_clear_radius, radius].
func _annulus_pos() -> Vector2:
	var inner := clampf(inner_clear_radius, 0.0, maxf(radius - 0.5, 0.0))
	var angle := _rng.randf_range(0.0, TAU)
	var dist := sqrt(_rng.randf_range(inner * inner, radius * radius))
	return Vector2(cos(angle), sin(angle)) * dist

## Ground surface Y at a map position; falls back to 0 when no provider is set.
func _ground_height(pos: Vector2) -> float:
	if ground_height_provider.is_valid():
		return ground_height_provider.call(pos)
	return 0.0