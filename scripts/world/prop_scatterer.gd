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

func _init() -> void:
	_mesh_builders = {
		"guardrail": _build_guardrail_mesh,
		"tent": _build_tent_mesh,
		"power_pole": _build_power_pole_mesh,
		"rock": _build_rock_mesh,
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

## Per-zone presets mirroring plan Section 5. Counts stay small (14-28 props
## per zone); the integration agent may tune or replace these Dictionaries.
static func default_preset(zone: String) -> Dictionary:
	match zone:
		"festival":
			return {
				"radius": 200.0, "inner_clear_radius": 90.0, "seed": 1001,
				"road_threshold": 8.0,
				"props": {"tent": {"count": 14, "min_spacing": 14.0, "scale": Vector2(0.9, 1.2)}},
			}
		"lowlands":
			return {
				"radius": 400.0, "inner_clear_radius": 30.0, "seed": 1002,
				"road_threshold": 10.0,
				"props": {
					"power_pole": {"count": 8, "min_spacing": 90.0, "scale": Vector2(0.9, 1.1)},
					"rock": {"count": 20, "min_spacing": 12.0, "scale": Vector2(0.8, 1.6)},
				},
			}
		"coast":
			return {
				"radius": 400.0, "inner_clear_radius": 20.0, "seed": 1003,
				"road_threshold": 8.0,
				"props": {"rock": {"count": 24, "min_spacing": 15.0, "scale": Vector2(1.4, 2.4)}},
			}
		"highlands":
			return {
				"radius": 500.0, "inner_clear_radius": 40.0, "seed": 1004,
				"road_threshold": 11.0,
				"props": {"guardrail": {"count": 26, "min_spacing": 16.0, "scale": Vector2(1.0, 1.0)}},
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

func _place_prop(entry: Dictionary) -> PackedVector3Array:
	var count := int(entry.get("count", 0))
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
	mmi.material_override = _prop_material(prop_type)
	return mmi

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
	# Chunkier than a raw octahedron: octahedron core fused with a box (~20 tris).
	var oct_st := SurfaceTool.new()
	oct_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts := PackedVector3Array([
		Vector3(0, 0.95, 0), Vector3(0.55, 0.35, 0), Vector3(0, 0.35, 0.5),
		Vector3(-0.55, 0.35, 0), Vector3(0, 0.35, -0.5), Vector3(0, 0, 0),
	])
	for v in verts:
		oct_st.add_vertex(v)
	var faces := PackedInt32Array([
		0, 2, 1,
		0, 3, 2,
		0, 4, 3,
		0, 1, 4,
		5, 1, 2,
		5, 2, 3,
		5, 3, 4,
		5, 4, 1,
	])
	for f in faces:
		oct_st.add_index(f)
	oct_st.generate_normals()
	var oct_mesh := oct_st.commit()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.6, 0.9)
	return _fuse([
		[oct_mesh, Transform3D(Basis.IDENTITY, Vector3(0, 0.0, 0))],
		[box, Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0))],
	])

func _fuse(parts: Array) -> ArrayMesh:
	# Fuses primitives into ONE ArrayMesh surface so MultiMesh can instance it
	# (same approach as foliage.gd::_build_tree_mesh).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		st.append_from(part[0] as Mesh, 0, part[1] as Transform3D)
	return st.commit()

func _road_ok(pos: Vector3) -> bool:
	if road_network != null:
		return not road_network.is_on_road(pos, road_threshold)
	return true

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