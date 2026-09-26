extends SceneTree

func _initialize() -> void:
	var defs := CorridorPlanner.plan(CorridorPlanner.MASTER_SEED)
	var spawn: Array[Vector3] = defs[defs.size() - 1].points
	print("DEFS=", defs.size())
	print("SPAWN_FIRST=", spawn[0])
	print("SPAWN_MID=", spawn[spawn.size() / 2])
	print("SPAWN_LAST=", spawn[spawn.size() - 1])
	var topology := RoadGraph.build_topology(defs, RoadNetwork.LINK_THRESHOLD)
	var adjacency: Dictionary = topology["adjacency"]
	for i in defs.size():
		var neighbors: PackedInt32Array = adjacency[i]
		print("ADJ[", i, "]=", neighbors)
	var junctions: Array = topology["junctions"]
	print("JUNCTIONS=", junctions.size())

	var network := RoadNetwork.new()
	for def in defs:
		network.add_road_def(def)
	network.recompute_rails()
	for child in network.get_children():
		var builder := child as TrackBuilder
		if builder == null:
			continue
		var bodies := _rail_bodies(builder)
		if bodies.is_empty():
			continue
		var rail := builder.get_node("RoadRailRight") as MeshInstance3D
		print("HIGHWAY_RAIL_TRIANGLES=", _mesh_triangles(rail))
		for body in bodies:
			var collision := body.get_child(0) as CollisionShape3D
			var shape := collision.shape as ConcavePolygonShape3D
			print("RAIL_COLLISION=", body.name, " TRIANGLES=", shape.get_faces().size() / 3, " FRICTION=", body.physics_material_override.friction)
	quit()

func _rail_bodies(builder: TrackBuilder) -> Array[StaticBody3D]:
	var out: Array[StaticBody3D] = []
	for child in builder.get_children():
		if child is StaticBody3D and String(child.name).begins_with("RailCollision"):
			out.append(child as StaticBody3D)
	return out

func _mesh_triangles(instance: MeshInstance3D) -> int:
	if instance == null or instance.mesh == null or instance.mesh.get_surface_count() == 0:
		return 0
	var arrays: Array = instance.mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	return indices.size() / 3
