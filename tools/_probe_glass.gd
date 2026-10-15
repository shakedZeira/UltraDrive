extends SceneTree

func _init() -> void:
	var path := "res://scenes/vehicle/player_car.tscn"
	var scene: PackedScene = load(path)
	if scene == null:
		print("PROBE FAILED to load ", path)
		quit(1)
		return
	var car := scene.instantiate() as Node
	root.add_child(car)
	await process_frame
	await process_frame

	print("=== car tree (2 frames) ===")
	var visual_root: Node3D = _find_visual_root(car)
	print("visual_root=", visual_root)
	if visual_root == null:
		quit(1)
		return

	print("=== BEFORE cockpit pass ===")
	_dump_glass_state(visual_root)
	var roles: Dictionary = CarVisuals.cockpit_roles(visual_root)
	print("roles: glass=", (roles["glass"] as Array).size(), " shell=", (roles["shell"] as Array).size())
	for n in roles["glass"]:
		print("  GLASS node=", n.name)
	for n in roles["shell"]:
		print("  SHELL node=", n.name)

	CarVisuals.set_cockpit_view(visual_root, true)
	await process_frame
	print("=== AFTER set_cockpit_view(true) ===")
	_dump_glass_state(visual_root)

	car.free()
	quit(0)

func _find_visual_root(root: Node) -> Node3D:
	for child in root.find_children("*", "MeshInstance3D", true, false):
		return (child as MeshInstance3D)
	return null

func _dump_mi(mi: MeshInstance3D) -> void:
	var mesh: Mesh = mi.mesh
	if mesh == null:
		print("  ", mi.name, " (no mesh)  ")
		return
	var parts: Array[String] = []
	for s in range(mesh.get_surface_count()):
		var ov := mi.get_surface_override_material(s)
		var emb: Material = mesh.surface_get_material(s)
		var m: Material = ov if ov != null else emb
		var name := "?"
		var transp := -1
		var alpha := -1.0
		var albedo := "?"
		if m is StandardMaterial3D:
			var std := m as StandardMaterial3D
			name = std.resource_name
			transp = int(std.transparency)
			alpha = std.albedo_color.a
			albedo = std.albedo_color.to_html(false)
		parts.append("[ovr=%s n=%s tr=%d a=%.2f albedo=#%s]" % ["Y" if ov != null else "N", name, transp, alpha, albedo])
	print("  ", mi.name, " ", " ".join(parts))

func _dump_glass_state(root: Node3D) -> void:
	for child in root.find_children("Windscreen", "MeshInstance3D", true, false):
		_dump_mi(child as MeshInstance3D)
	for child in root.find_children("Glass", "MeshInstance3D", true, false):
		_dump_mi(child as MeshInstance3D)
	for child in root.find_children("GlassFastback", "MeshInstance3D", true, false):
		_dump_mi(child as MeshInstance3D)