extends SceneTree

func _init() -> void:
	var path := "res://assets/cars/nissan_gt-r_r35_2017.glb"
	var scene: PackedScene = load(path)
	if scene == null:
		print("PROBE FAILED to load ", path)
		quit(1)
		return
	var root := scene.instantiate() as Node3D
	_dump(root, 0)
	root.free()
	quit(0)

func _dump(node: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var line := pad + node.name
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh != null:
			var counts: Array[String] = []
			for s in range(mesh.get_surface_count()):
				var mat := mi.get_surface_override_material(s)
				var embedded: Material = mesh.surface_get_material(s)
				var m := mat if mat != null else embedded
				var name := "?"
				var type := "?"
				var transp := -1
				var alpha := -1.0
				if m is StandardMaterial3D:
					name = m.resource_name
					type = "std"
					transp = int(m.transparency)
					alpha = m.albedo_color.a
				var override := " (ovr)" if mat != null else ""
				counts.append("[%d:%s%s a=%.2f tr=%d]" % [s, name, override, alpha, transp])
			line += "  MESH surfaces=" + str(mesh.get_surface_count()) + " " + " ".join(counts)
		else:
			line += "  (no mesh)"
	elif node is Node3D:
		var node_mat_count := 0
	line += "  visible=" + str(node.visible if "visible" in node else true)
	print(line)
	for child in node.get_children():
		_dump(child, depth + 1)