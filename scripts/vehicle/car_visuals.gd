# scripts/vehicle/car_visuals.gd
class_name CarVisuals
extends RefCounted

## Shared runtime car dresser. Walks an instanced GLB visual tree and injects
## per-part StandardMaterial3D surface overrides (paint, glass, lights, tires,
## rims, trim) by matching embedded material names, so every car reads as an
## FH5/GT7-style clearcoat-over-metallic paint. All overrides are runtime
## clones: embedded materials are NEVER mutated.

const CAR_ORIENT := Transform3D(Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0)), Vector3.ZERO)

const DEFAULT_PAINT := {
	"metallic": 0.92,
	"roughness": 0.35,
	"clearcoat": 1.0,
	"clearcoat_roughness": 0.03,
	"glass_roughness": 0.1,
	"glass_refraction_scale": 0.05,
	"tail_emission_strength": 5.0,
}

static func apply_paint(visual_root: Node3D, profile: Dictionary) -> void:
	if visual_root == null:
		return
	_paint_node(visual_root, profile)

static func _paint_node(node: Node3D, profile: Dictionary) -> void:
	if node is MeshInstance3D:
		_paint_mesh_instance(node as MeshInstance3D, profile)
	for child in node.get_children():
		if child is Node3D:
			_paint_node(child as Node3D, profile)

static func _paint_mesh_instance(mesh_instance: MeshInstance3D, profile: Dictionary) -> void:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return
	var surface_count: int = mesh.get_surface_count()
	for surface_index in range(surface_count):
		var override_material: StandardMaterial3D = _make_override(mesh_instance, mesh, surface_index, profile)
		if override_material != null:
			mesh_instance.set_surface_override_material(surface_index, override_material)

static func _make_override(mesh_instance: MeshInstance3D, mesh: Mesh, surface_index: int, profile: Dictionary) -> StandardMaterial3D:
	var material: Material = _resolved_surface_material(mesh_instance, mesh, surface_index)
	if material == null:
		return null
	var standard: StandardMaterial3D = material as StandardMaterial3D
	if standard == null:
		return null
	var name := _surface_name(mesh_instance, mesh, surface_index)
	if name.contains("paint") or standard.clearcoat_enabled:
		return _paint_clone(standard, profile)
	if name.contains("glass"):
		return _glass_clone(standard, profile)
	if name.contains("headlight") or name.contains("taillight"):
		return _light_clone(standard)
	if name.contains("tire"):
		return _tire_clone(standard)
	if name.contains("trim") or name.contains("graphite"):
		return _trim_clone(standard)
	if name.contains("rim"):
		return _rim_clone(standard)
	return null

static func _resolved_surface_material(mesh_instance: MeshInstance3D, mesh: Mesh, surface_index: int) -> Material:
	var override_material: Material = mesh_instance.get_surface_override_material(surface_index)
	if override_material != null:
		return override_material
	return mesh.surface_get_material(surface_index)

static func _surface_name(mesh_instance: MeshInstance3D, mesh: Mesh, surface_index: int) -> String:
	var material: Material = _resolved_surface_material(mesh_instance, mesh, surface_index)
	if material != null and not material.resource_name.is_empty():
		return material.resource_name.to_lower()
	var embedded: Material = mesh.surface_get_material(surface_index)
	if embedded != null and not embedded.resource_name.is_empty():
		return embedded.resource_name.to_lower()
	return ""

static func _paint_clone(source: StandardMaterial3D, profile: Dictionary) -> StandardMaterial3D:
	var cloned: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	cloned.clearcoat_enabled = true
	cloned.clearcoat = profile["clearcoat"]
	cloned.clearcoat_roughness = profile["clearcoat_roughness"]
	cloned.metallic = profile["metallic"]
	cloned.roughness = profile["roughness"]
	return cloned

static func _glass_clone(source: StandardMaterial3D, profile: Dictionary) -> StandardMaterial3D:
	var cloned: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	cloned.roughness = profile["glass_roughness"]
	cloned.refraction_enabled = true
	cloned.refraction_scale = profile["glass_refraction_scale"]
	return cloned

static func _light_clone(source: StandardMaterial3D) -> StandardMaterial3D:
	var cloned: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	cloned.metallic = 0.0
	cloned.roughness = 0.4
	return cloned

static func _tire_clone(source: StandardMaterial3D) -> StandardMaterial3D:
	var cloned: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	cloned.metallic = 0.0
	cloned.roughness = 0.95
	return cloned

static func _rim_clone(source: StandardMaterial3D) -> StandardMaterial3D:
	var cloned: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	cloned.metallic = 0.9
	cloned.roughness = 0.15
	return cloned

static func _trim_clone(source: StandardMaterial3D) -> StandardMaterial3D:
	var cloned: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	cloned.metallic = 0.85
	cloned.roughness = 0.45
	return cloned

static func paint_surface_count(root: Node3D) -> int:
	if root == null:
		return 0
	return _matching_surface_count(root)

static func _matching_surface_count(node: Node3D) -> int:
	var count := 0
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh: Mesh = mesh_instance.mesh
		if mesh != null:
			for surface_index in range(mesh.get_surface_count()):
				if mesh_instance.get_surface_override_material(surface_index) != null:
					count += 1
	for child in node.get_children():
		if child is Node3D:
			count += _matching_surface_count(child as Node3D)
	return count