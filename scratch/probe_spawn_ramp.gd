extends SceneTree

func _initialize() -> void:
	var defs := CorridorPlanner.plan(CorridorPlanner.MASTER_SEED)
	var ring: Array[Vector3] = defs[3].points
	var source := Vector3(128.0, 2.2, 128.0)
	var direction := (ring[110] - source).normalized()
	var perpendicular := Vector2(-direction.z, direction.x)
	print("ring110=", ring[110], " direction=", direction, " perpendicular=", perpendicular)
	for distance in [-80.0, -60.0, -40.0, -20.0, 20.0, 40.0, 60.0, 80.0]:
		var bulge: Vector2 = perpendicular * distance
		var points := _access(source, ring[110], bulge)
		var first: Vector3 = points[0]
		var middle: Vector3 = points[points.size() / 2]
		var last: Vector3 = points[points.size() - 1]
		var hub := RoadGraph.chain_distance(points, defs[0].points)
		var connector := RoadGraph.chain_distance(points, defs[1].points)
		var highway := RoadGraph.chain_distance(points, defs[3].points)
		var min_sea := INF
		for point in points:
			min_sea = minf(min_sea, Vector2(point.x, point.z).distance_to(TerrainBaker.BIOME_SEA_CENTER))
		print("bulge=", bulge, " count=", points.size(), " first=", first, " mid=", middle, " last=", last, " hub=", hub, " connector=", connector, " highway=", highway, " sea=", min_sea)

func _access(source: Vector3, end: Vector3, bulge: Vector2) -> Array[Vector3]:
	var mid := Vector3((source.x + end.x) * 0.5 + bulge.x, 0.0, (source.z + end.z) * 0.5 + bulge.y)
	var control: Array[Vector3] = [source, mid, end]
	var chain := PackedVector3Array()
	for i in 97:
		chain.append(Spline.catmull_rom_xz(control, float(i) / 96.0))
	chain[96] = end
	var result := Spline.resample_by_arc(chain, 12.0, source.y, end)
	result[result.size() - 1] = end
	return result
