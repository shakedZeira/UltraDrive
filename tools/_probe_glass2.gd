extends SceneTree

const GLB := "res://assets/cars/nissan_gt-r_r35_2017.glb"

func _initialize() -> void:
	var ps := load(GLB) as PackedScene
	if ps == null:
		print("PROBE GLB load failed")
		quit(1)
		return
	var root: Node3D = ps.instantiate()
	root.add_child(root)
	print("PROBE root=", root.name, " children=", root.get_child_count())

	CarVisuals.apply_paint(root, CarVisuals.paint_profile_for("nissan_gt-r_r35_2017"))

	var roles: Dictionary = CarVisuals.cockpit_roles(root)
	print("PROBE roles glass=", (roles["glass"] as Array).size(), " shell=", (roles["shell"] as Array).size())

	for glass: Variant in roles["glass"]:
		var mi := glass as MeshInstance3D
		_dump(mi, "GLASS")
	for shell: Variant in roles["shell"]:
		var mi := shell as MeshInstance3D
		if String(mi.name).to_lower().contains("window") or String(mi.name).to_lower().contains("windshield") \
			or String(mi.name).to_lower().contains("glass"):
			_dump(mi, "WINDOW-SHELL")

	local("glass") if false else null
	CarVisuals.set_cockpit_view(root, true)
	print("PROBE after set_cockpit_view(true):")
	for glass: Variant in roles["glass"]:
		_dump(glass as MeshInstance3D, "GLASS")

	quit(0)

func local(_x) -> void:
	pass

func _dump(mi: MeshInstance3D, tag: String) -> void:
	var mesh: Mesh = mi.mesh
	if mesh == null:
		print("PROBE ", tag, " node=", mi.name, " mesh=null")
		return
	var parts: Array[String] = []
	for s in range(mesh.get_surface_count()):
		var ov := mi.get_surface_override_material(s) as StandardMaterial3D
		var emb: Material = mesh.surface_get_material(s)
		var m: StandardMaterial3D = ov if ov is StandardMaterial3D else (emb as StandardMaterial3D)
		if m != null:
			parts.append("s%d ovr=%s name=%s tr=%d a=%.2f" % [s, "Y" if ov != null else "N", m.resource_name, int(m.transparency), m.albedo_color.a])
	print("PROBE ", tag, " node=", mi.name, " ", " ".join(parts))