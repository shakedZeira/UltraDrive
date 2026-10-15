# tests/suites/test_zzz_fall_probe.gd  -- THROWAWAY PROBE, delete when done.
#
# Establishes, on the CURRENT (pre-fix) tree:
#   1. Whether off-road ground (Terrain3D "GrassGround") has any collision.
#   2. The value of every spawned rival's `_spawn_point` (the respawn anchor).
#   3. Whether rivals teleport mid-race, and where they land.
#   4. The steady-state speed per tier (does pace actually differentiate?).
extends GdUnitTestSuite

const NI_SCENE := "res://scenes/track/northern_isle.tscn"
const RIVAL_SCENE := "res://scenes/vehicle/rival_car.tscn"

func _ray_down(pos: Vector3, label: String) -> void:
	var space := get_tree().root.world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 3.0, pos + Vector3.DOWN * 60.0, 0xFFFFFFFF, [])
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		print("[probe] ray %-28s from %s -> NO HIT" % [label, str(pos)])
	else:
		var col: Object = hit.get("collider")
		var cname: String = col.name if col != null else "<null>"
		print("[probe] ray %-28s from %s -> hit y=%.2f collider=%s (%s)" % [
			label, str(pos), float(hit["position"].y), cname, col.get_class() if col != null else "?"])

func test_zzz_fall_probe() -> void:
	var runner := scene_runner(NI_SCENE)
	await runner.simulate_frames(5)
	var scene := runner.scene()
	if scene == null:
		print("[probe] NI scene failed to load")
		return

	# --- 1. terrain collision ------------------------------------------------
	var terrain := scene.get_node_or_null("GrassGround") as Terrain3D
	if terrain == null:
		print("[probe] NO GrassGround node found")
	else:
		print("[probe] GrassGround collision_mode=%d region_size=%d data=%s" % [
			terrain.collision_mode, terrain.region_size, str(terrain.data != null)])
		for prop in ["collision_radius", "collision_layer", "collision_mask", "collision_enabled"]:
			print("[probe]   %s = %s" % [prop, str(terrain.get(prop))])
		if terrain.data != null:
			print("[probe] regions = %s" % str(terrain.data.get_region_locations()))

	# --- 2. dense collision scan --------------------------------------------
	var space := get_tree().root.world_3d.direct_space_state
	var cam := get_viewport().get_camera_3d()
	print("[probe] camera=%s" % (str(cam.global_position) if cam != null else "<none>"))
	print("[probe] player=%s" % str(VehicleManager.get_player_car().global_position))
	if terrain != null:
		print("[probe] terrain.node_pos=%s terrain.data.get_height(0,0,0)=%s" % [
			str(terrain.global_position),
			str(terrain.data.get_height(Vector3.ZERO)) if terrain.data != null else "<no data>"])
		for prop in ["collision_target", "collision_shape_size", "mesh_lods"]:
			print("[probe]   %s = %s" % [prop, str(terrain.get(prop))])

	# Legend: T=terrain(GrassGround)  R=road/track  V=vehicle  ?=other  .=NO COLLIDER
	#         second column: h=terrain height data present  n=no height data (NaN)
	var rows: Array[String] = []
	for iz in range(-240, 241, 20):
		var row := ""
		var hrow := ""
		for ix in range(-240, 241, 20):
			var q := PhysicsRayQueryParameters3D.create(
				Vector3(ix, 20.0, iz), Vector3(ix, -40.0, iz), 0xFFFFFFFF, [])
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				row += "."
			else:
				var col: Object = hit.get("collider")
				var cname: String = ""
				if col != null:
					cname = String(col.name) + "/" + col.get_class()
				if cname.contains("GrassGround") or cname.contains("Terrain3D"):
					row += "T"
				elif cname.contains("Road") or cname.contains("Track") or cname.contains("ribbon"):
					row += "R"
				elif cname.contains("Car") or cname.contains("Rigid") or cname.contains("Player"):
					row += "V"
				else:
					row += "?"
			var h := 0.0
			var has_h := false
			if terrain != null and terrain.data != null:
				h = terrain.data.get_height(Vector3(ix, 0.0, iz))
				has_h = not is_nan(h)
			hrow += "h" if has_h else "n"
		rows.append("z=%5d %s  %s" % [iz, row, hrow])
	print("[probe] collision map x=-240..240 step20 (left=ray, right=height data):")
	for r in rows:
		print("[probe]   " + r)
	# Road centerline coverage: ray down at every 16th centerline point.
	var line_probe: Array[Vector3] = NorthernIsleLayout.build_centerline()
	var missing := 0
	for i in range(0, line_probe.size(), 16):
		var c := line_probe[i]
		var q2 := PhysicsRayQueryParameters3D.create(
			c + Vector3.UP * 4.0, c + Vector3.DOWN * 20.0, 0xFFFFFFFF, [])
		if space.intersect_ray(q2).is_empty():
			missing += 1
			print("[probe]   centerline NO-HIT idx=%d pos=%s" % [i, str(c)])
	print("[probe] centerline samples missing=%d" % missing)

	_ray_down(Vector3(180.0, 6.0, 15.0), "turn-1 inner (approx)")
	_ray_down(Vector3(205.0, 8.0, 15.0), "outfield beyond turn 1")

	# --- 3. spawn + drive ----------------------------------------------------
	GameState.opponents = 3
	GameState.ai_difficulty = "Skilled"
	GameState.rubber_band_assist = false
	RaceManager.rival_vehicle_scene = load(RIVAL_SCENE) as PackedScene
	RaceManager.rival_spawner = Callable()
	RaceManager.configure_default_rivals(VehicleManager.get_player_car(), 0)
	RaceManager.start_race(VehicleManager.get_all_cars(), 3)
	RaceManager.get_countdown().advance(RaceCountdown.TOTAL_SECONDS + 0.5)
	var rivals := RaceManager.get_spawned_rivals()
	print("[probe] rival count=%d" % rivals.size())
	for car in rivals:
		var driver: RivalDriver = null
		for ch in car.get_children():
			if ch is RivalDriver:
				driver = ch
		print("[probe] rival spawn_point=%s pos=%s tier=%s pace=%.3f" % [
			str(car._spawn_point), str(car.global_position),
			driver.get_tier() if driver != null else "?",
			driver.get_pace_multiplier() if driver != null else -1.0])

	var line: Array[Vector3] = RaceManager.rival_centerline
	var prev: Dictionary = {}
	for car in rivals:
		prev[car] = car.global_position

	for i in range(2400):
		await get_tree().physics_frame
		for car in rivals:
			var jump := car.global_position.distance_to(prev[car])
			if jump > 20.0:
				print("[probe] TELEPORT t=%.1fs car=%s from %s to %s (jump %.1f m) y_prev=%.2f" % [
					float(i) / 60.0, str(car), str(prev[car]), str(car.global_position), jump,
					prev[car].y])
			prev[car] = car.global_position
		if i % 60 == 0:
			var parts: Array[String] = []
			for car in rivals:
				var idx := _nearest_index(line, car.global_position)
				var lat := _lateral_distance_to(line, car.global_position)
				var grounded := 0
				for w in car._wheels:
					if w.is_in_contact:
						grounded += 1
				parts.append("y=%.2f v=%.1f lat=%.1f idx=%d gnd=%d fz=%s" % [
					car.global_position.y, car.linear_velocity.length(), lat, idx,
					grounded, str(car.freeze)])
			print("[probe] t=%4.1fs | %s" % [float(i) / 60.0, " || ".join(parts)])

	# --- 4. cleanup ----------------------------------------------------------
	RaceManager.clear_rival_config()

func _nearest_index(line: Array[Vector3], pos: Vector3) -> int:
	var best_index := 0
	var best_dist := INF
	for i in range(line.size()):
		var p := line[i]
		var dx := p.x - pos.x
		var dz := p.z - pos.z
		var d := dx * dx + dz * dz
		if d < best_dist:
			best_dist = d
			best_index = i
	return best_index

func _lateral_distance_to(line: Array[Vector3], pos: Vector3) -> float:
	var p := line[_nearest_index(line, pos)]
	var dx := p.x - pos.x
	var dz := p.z - pos.z
	return sqrt(dx * dx + dz * dz)
