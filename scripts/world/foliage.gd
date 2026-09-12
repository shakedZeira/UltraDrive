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
const GRASS_SHADER_PATH := "res://shaders/grass_wind.gdshader"
const TREE_SHADER_PATH := "res://shaders/foliage_wind.gdshader"

@export var radius: float = 140.0
@export var inner_clear_radius: float = 78.0
@export var grass_count: int = 700
@export var tree_count: int = 40
@export var seed: int = 2120

var _rng := RandomNumberGenerator.new()
var _tree_roots: Array[Vector2] = []

func _ready() -> void:
	_rng.seed = seed
	add_child(_build_grass())
	add_child(_build_trees())

## Updates the wind sway amount on every foliage material at runtime.
func set_wind_strength(strength: float) -> void:
	for child in get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi != null and mmi.material_override is ShaderMaterial:
			mmi.material_override.set_shader_parameter("wind_strength", strength)

func _build_grass() -> MultiMeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = GRASS_MESH_SIZE

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plane
	mm.instance_count = grass_count
	for i in grass_count:
		mm.set_instance_transform(i, _grass_transform())

	var mat := ShaderMaterial.new()
	mat.shader = load(GRASS_SHADER_PATH) as Shader
	mat.set_shader_parameter("wind_strength", 0.05)

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "GrassMMI"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi

func _build_trees() -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _build_tree_mesh()
	mm.instance_count = tree_count

	var mat := ShaderMaterial.new()
	mat.shader = load(TREE_SHADER_PATH) as Shader
	mat.set_shader_parameter("wind_strength", 0.05)

	for i in tree_count:
		var pos := _tree_pos()
		var yaw := _rng.randf_range(0.0, TAU)
		var scale := _rng.randf_range(0.8, 1.3)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
		mm.set_instance_transform(i, Transform3D(basis, Vector3(pos.x, GROUND_OFFSET_Y, pos.y)))

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "TreesMMI"
	mmi.multimesh = mm
	mmi.material_override = mat
	return mmi

func _build_tree_mesh() -> ArrayMesh:
	# Trunk + canopy merged into ONE surface so MultiMesh can instance it.
	var trunk := CylinderMesh.new()
	trunk.height = 1.6
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.30
	trunk.radial_segments = 6

	var canopy := CylinderMesh.new()
	canopy.bottom_radius = 1.4
	canopy.height = 3.0
	canopy.radial_segments = 8
	canopy.top_radius = 0.02

	# Primitives are centered on the origin: lift the trunk so its base sits at
	# y 0, then seat the cone base on top of the trunk (apex at y 4.6).
	var trunk_lift := Transform3D(Basis.IDENTITY, Vector3(0, trunk.height * 0.5, 0))
	var canopy_lift := Transform3D(Basis.IDENTITY, Vector3(0, trunk.height + canopy.height * 0.5, 0))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(trunk, 0, trunk_lift)
	st.append_from(canopy, 0, canopy_lift)
	var tree_mesh := st.commit()
	_bake_tree_height_uvs(tree_mesh)
	return tree_mesh

func _bake_tree_height_uvs(tree_mesh: ArrayMesh) -> void:
	# Rewrite UV.y as normalized height (0 = ground, 1 = canopy tip) so the
	# shader can split bark vs leaf with a single uv.y comparison.
	var arrays := tree_mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for i in uvs.size():
		uvs[i] = Vector2(uvs[i].x, clampf(verts[i].y / TREE_HEIGHT, 0.0, 1.0))
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	tree_mesh.surface_remove(0)
	tree_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func _grass_transform() -> Transform3D:
	var pos := _annulus_pos()
	var yaw := _rng.randf_range(0.0, TAU)
	var scale := _rng.randf_range(0.8, 1.6)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
	return Transform3D(basis, Vector3(pos.x, GROUND_OFFSET_Y, pos.y))

func _tree_pos() -> Vector2:
	# Rejection sampling keeps roughly 8 m between tree trunks.
	for attempt in range(TREE_PLACEMENT_ATTEMPTS):
		var candidate := _annulus_pos()
		if _spacing_ok(candidate):
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
