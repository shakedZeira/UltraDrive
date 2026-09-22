extends Node

## TERRAIN3D REGION-COST DIAGNOSTIC (temp, round 3).
##
## Two phases:
##   A) isolated per-op cost at region sizes 256/512/1024, collision off/on.
##   B) growing-grid sweep at 256: add blank regions shell-by-shell up to 169
##      (13x13), logging worst add_blankp cost and a full update_maps cost at
##      every shell count. Separates collider rebuild cost (collision 3 vs 0)
##      from pure mesh/data cost and shows how per-region cost scales.
##
## Usage: Godot_v4.7.2-stable_win64.exe --path . res://tools/diag_region_cost.tscn

const TRIALS := 3
const ABS := 6

func _ready() -> void:
	var cam := Camera3D.new()
	cam.current = true
	cam.position = Vector3(0.0, 600.0, 0.0)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	cam.far = 6000.0
	add_child(cam)
	print("[diag] adapter=", RenderingServer.get_video_adapter_name())
	for region_size in [Terrain3D.SIZE_256, Terrain3D.SIZE_512, Terrain3D.SIZE_1024]:
		for collision in [0, 3]:
			await _measure(region_size, collision)
	await _phase_b()
	print("[diag] ================= RESULT =================")
	get_tree().quit()

func _label(size: int) -> String:
	match size:
		Terrain3D.SIZE_256:
			return "256"
		Terrain3D.SIZE_512:
			return "512"
	return "1024"

func _measure(size: int, collision: int) -> void:
	var label: String = _label(size) + "_collision" + str(collision)
	var terrain := Terrain3D.new()
	add_child(terrain)
	terrain.collision_mode = collision
	terrain.region_size = size
	await get_tree().create_timer(0.3).timeout
	var data: Terrain3DData = terrain.data
	var n: int = size
	var row := {"label": label, "add_ms": 0.0, "set_height_ms": 0.0, "set_color_ms": 0.0, "update_ms": 0.0}
	for trial in TRIALS:
		row["add_ms"] = maxf(row["add_ms"], _time(func() -> void: data.add_region_blankp(Vector3(float(trial * size), 0.0, 0.0), false)))
	var center := Vector3(size * 1.5, 0.0, 0.0)
	data.add_region_blankp(center, false)
	await get_tree().create_timer(0.2).timeout
	var height := Image.create(n, n, false, Image.FORMAT_RF)
	for iy in n:
		for ix in n:
			height.set_pixel(ix, iy, Color(float(ix) / float(n - 1), 0.5, 0.0))
	var color := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for iy in n:
		for ix in n:
			color.set_pixel(ix, iy, Color(0.3, 0.7, 0.2, 1.0))
	var region: Terrain3DRegion = data.get_regionp(center)
	if region == null:
		print("[diag] ", label, " NO CENTER REGION (skip)")
		terrain.queue_free()
		await get_tree().create_timer(0.2).timeout
		return
	row["set_height_ms"] = maxf(row["set_height_ms"], _time(func() -> void: region.set_map(Terrain3DRegion.TYPE_HEIGHT, height)))
	row["set_color_ms"] = maxf(row["set_color_ms"], _time(func() -> void: region.set_map(Terrain3DRegion.TYPE_COLOR, color)))
	region.update_height(0.0)
	region.update_height(1.0)
	region.set_edited(true)
	row["update_ms"] = maxf(row["update_ms"], _time(func() -> void: data.update_maps(Terrain3DRegion.TYPE_HEIGHT, false)))
	region.set_edited(false)
	print("[diag] ", label, " add=", snappedf(row["add_ms"], 0.01), "ms setH=", snappedf(row["set_height_ms"], 0.01), "ms setC=", snappedf(row["set_color_ms"], 0.01), "ms update=", snappedf(row["update_ms"], 0.01), "ms")
	terrain.queue_free()
	await get_tree().create_timer(0.2).timeout

func _phase_b() -> void:
	for collision in [0, 3]:
		await _sweep(256, collision)

func _sweep(size: int, collision: int) -> void:
	var label: String = "sweep_256_collision" + str(collision)
	var terrain := Terrain3D.new()
	add_child(terrain)
	terrain.collision_mode = collision
	terrain.region_size = size
	await get_tree().create_timer(0.4).timeout
	var data: Terrain3DData = terrain.data
	var locs: Array[Vector2i] = []
	for r in ABS + 1:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dz), absi(dx)) == r:
					locs.append(Vector2i(dx, dz))
	var added := 0
	var bucket := 1
	var worst := 0.0
	var wall := 0.0
	print("[diag] ", label, " growing grid up to ", locs.size(), " regions (count = add_worst_ms / update_ms)")
	for loc in locs:
		var cost := _time(func() -> void: data.add_region_blankp(Vector3(float(loc.x * size), 0.0, float(loc.y * size)), false))
		worst = maxf(worst, cost)
		wall += cost
		added += 1
		if added == bucket * bucket or added == locs.size():
			var up := _sweep_update_all(data)
			print("[diag] ", label, " n=", added, " add_worst_ms=", snappedf(worst, 0.1), " update_ms=", snappedf(up, 0.1))
			worst = 0.0
			bucket += 2
	print("[diag] ", label, " total_add_wall_ms=", snappedf(wall, 0.1), " avg_add_ms=", snappedf(wall / float(maxi(locs.size(), 1)), 0.1))
	terrain.queue_free()
	await get_tree().create_timer(0.2).timeout

func _sweep_update_all(data: Terrain3DData) -> float:
	var edited: Array = data.get_regions_active()
	for r in edited:
		(r as Terrain3DRegion).set_edited(true)
	var cost := _time(func() -> void: data.update_maps(Terrain3DRegion.TYPE_HEIGHT, true, false))
	for r in edited:
		(r as Terrain3DRegion).set_edited(false)
	return cost

func _time(cb: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	cb.call()
	return (Time.get_ticks_usec() - t0) / 1000.0