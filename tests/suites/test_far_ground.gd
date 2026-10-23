# tests/suites/test_far_ground.gd
extends GdUnitTestSuite

## Bug 3d: Terrain3D only holds region locations -16..15, so with 256 m regions
## the live ring cannot exist past +-4096 m while the drivable world reaches
## ~9.7 km. Before the fix every ring region out there called
## add_region_blankp(), which logged "Location (x, y) out of bounds" (thousands
## of errors per second while the car was in the alpine / coast areas) and the
## area had no ground except the vista, which had no collision.
##
## After the fix: ring locations outside the window are virtual (baked and
## announced to the dresser, never added to Terrain3D), the vista bias fades
## out past the window so the far ground meets the ring without a curb, and the
## vista carries collision there.

const ALPINE := Vector3(6200.0, 100.0, 5200.0)
const WINDOW_EDGE_PLAYER := Vector3(4000.0, 20.0, 4000.0)

## Counts Terrain3D's "out of bounds" errors (any thread).
class BoundsErrors extends Logger:
	var count := 0
	var first := ""
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if rationale.contains("out of bounds") or code.contains("out of bounds"):
			count += 1
			if first == "":
				first = "%s:%d %s" % [function, line, rationale if rationale != "" else code]

func _await_until(condition: Callable, timeout_s: float) -> bool:
	var loops := int(timeout_s / 0.1)
	for _i in loops:
		if condition.call():
			return true
		await get_tree().create_timer(0.1).timeout
	return condition.call()

## Terrain3D stops its physics process (and its collision) when it cannot find
## an active camera; the game always has one.
func _add_camera(pos: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = pos
	cam.current = true
	return cam

func _make_seeder() -> Array:
	var t := Terrain3D.new()
	add_child(t)
	var seeder := TerrainSeeder.new()
	seeder.terrain = t
	add_child(seeder)
	return [seeder, t]

## Fills the bake cache for the 5x5 block around centre with flat records so the
## ring logic is tested without paying for 25 real 256 m bakes.
func _prime(seeder: TerrainSeeder, centre: Vector2i, height: float = 10.0) -> void:
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var img := Image.create(256, 256, false, Image.FORMAT_RF)
			img.fill(Color(height, 0.0, 0.0, 1.0))
			var color := Image.create(256, 256, false, Image.FORMAT_RGBA8)
			var control := Image.create(256, 256, false, Image.FORMAT_RF)
			seeder._baked[centre + Vector2i(dx, dz)] = {"image": img, "color": color, "control": control, "height_min": height, "height_max": height}

func _ring_locs(centre: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dx in range(-TerrainSeeder.RING_RADIUS, TerrainSeeder.RING_RADIUS + 1):
		for dz in range(-TerrainSeeder.RING_RADIUS, TerrainSeeder.RING_RADIUS + 1):
			out.append(centre + Vector2i(dx, dz))
	return out

func test_terrain_bounds_match_the_terrain3d_location_window() -> void:
	assert_that(TerrainSeeder.loc_in_terrain_bounds(Vector2i(-16, -16))).is_true()
	assert_that(TerrainSeeder.loc_in_terrain_bounds(Vector2i(15, 15))).is_true()
	assert_that(TerrainSeeder.loc_in_terrain_bounds(Vector2i(16, 0))).is_false()
	assert_that(TerrainSeeder.loc_in_terrain_bounds(Vector2i(0, -17))).is_false()
	assert_that(TerrainSeeder.LOC_MAX + 1).is_equal(int(TerrainVistaBaker.LIVE_LIMIT / TerrainSeeder.REGION_SIZE))
	assert_that(-TerrainSeeder.LOC_MIN).is_equal(int(TerrainVistaBaker.LIVE_LIMIT / TerrainSeeder.REGION_SIZE))

## The reproduction: drive the ring into the alpine area. No bounds error, no
## Terrain3D region out there, and every ring location is still announced so the
## dresser dresses it.
func test_ring_in_the_alpine_area_logs_no_errors_and_still_enters() -> void:
	var errors := BoundsErrors.new()
	OS.add_logger(errors)
	var made := _make_seeder()
	var seeder: TerrainSeeder = made[0]
	var t: Terrain3D = made[1]
	var entered: Array[Vector2i] = []
	seeder.region_entered.connect(func(loc: Vector2i) -> void: entered.append(loc))
	var cam := _add_camera(ALPINE + Vector3(0.0, 20.0, 0.0))
	var centre := Vector2i(floori(ALPINE.x / 256.0), floori(ALPINE.z / 256.0))
	_prime(seeder, centre)
	seeder.sync_player_pos(ALPINE)
	var want := _ring_locs(centre)
	var landed := await _await_until(func() -> bool:
		seeder.sync_player_pos(ALPINE)
		for loc in want:
			if not entered.has(loc):
				return false
		return true, 60.0)
	await get_tree().process_frame
	OS.remove_logger(errors)
	assert_that(landed).override_failure_message("ring entered %s of %s" % [entered.size(), want.size()]).is_true()
	assert_that(errors.count).override_failure_message("bounds errors: %d (%s)" % [errors.count, errors.first]).is_equal(0)
	assert_that(t.data.get_region_locations().size()).is_equal(0)
	assert_that(seeder.has_baked_region(centre)).is_true()
	cam.queue_free()
	seeder.queue_free()
	t.queue_free()

## Straddling the window edge: regions inside get real Terrain3D regions, the
## ones outside are virtual, and leaving evicts both kinds.
func test_ring_straddling_the_window_edge_mixes_real_and_virtual_regions() -> void:
	var errors := BoundsErrors.new()
	OS.add_logger(errors)
	var made := _make_seeder()
	var seeder: TerrainSeeder = made[0]
	var t: Terrain3D = made[1]
	var entered: Array[Vector2i] = []
	var left: Array[Vector2i] = []
	seeder.region_entered.connect(func(loc: Vector2i) -> void: entered.append(loc))
	seeder.region_left.connect(func(loc: Vector2i) -> void: left.append(loc))
	var cam := _add_camera(WINDOW_EDGE_PLAYER + Vector3(0.0, 20.0, 0.0))
	var centre := Vector2i(floori(WINDOW_EDGE_PLAYER.x / 256.0), floori(WINDOW_EDGE_PLAYER.z / 256.0))
	_prime(seeder, centre)
	_prime(seeder, Vector2i(0, 0))
	var want := _ring_locs(centre)
	var landed := await _await_until(func() -> bool:
		seeder.sync_player_pos(WINDOW_EDGE_PLAYER)
		for loc in want:
			if not entered.has(loc):
				return false
		return true, 90.0)
	assert_that(landed).override_failure_message("ring entered %s of %s" % [entered.size(), want.size()]).is_true()
	var real := 0
	for loc in want:
		if TerrainSeeder.loc_in_terrain_bounds(loc):
			real += 1
	await _await_until(func() -> bool:
		seeder.sync_player_pos(WINDOW_EDGE_PLAYER)
		return t.data.get_region_locations().size() == real, 30.0)
	assert_that(t.data.get_region_locations().size()).is_equal(real)
	assert_that(real).is_equal(4)
	# Drive back to the hub: every far location and every old real one leaves.
	var home := Vector3(128.0, 2.2, 128.0)
	var gone := await _await_until(func() -> bool:
		seeder.sync_player_pos(home)
		for loc in want:
			if not left.has(loc):
				return false
		return true, 60.0)
	OS.remove_logger(errors)
	assert_that(gone).override_failure_message("left %s of %s" % [left.size(), want.size()]).is_true()
	assert_that(errors.count).override_failure_message("bounds errors: %d (%s)" % [errors.count, errors.first]).is_equal(0)
	cam.queue_free()
	seeder.queue_free()
	t.queue_free()

func test_vista_bias_fades_out_past_the_ring_window() -> void:
	var B := TerrainVistaBaker
	assert_that(B.bias_at(0.0, 0.0)).is_equal(B.BIAS)
	assert_that(B.bias_at(3000.0, -2000.0)).is_equal(B.BIAS)
	assert_that(B.bias_at(B.LIVE_LIMIT - B.BIAS_TAPER_IN, 0.0)).is_equal_approx(B.BIAS, 0.0001)
	# At the window edge the curb is BIAS_EDGE, then it fades to 0 and stays 0.
	assert_that(B.bias_at(B.LIVE_LIMIT, 0.0)).is_equal_approx(B.BIAS_EDGE, 0.0001)
	assert_that(B.bias_at(B.LIVE_LIMIT + B.BIAS_TAPER_OUT, 0.0)).is_equal_approx(0.0, 0.0001)
	assert_that(B.bias_at(9000.0, 7000.0)).is_equal(0.0)
	assert_that(B.bias_at(-B.LIVE_LIMIT, 0.0)).is_equal_approx(B.BIAS_EDGE, 0.0001)
	# Monotone along a line out of the window (no bumps), either axis.
	var prev := B.bias_at(3500.0, 100.0)
	var x := 3500.0
	while x < 4600.0:
		x += 16.0
		var b := B.bias_at(x, 100.0)
		assert_that(b).override_failure_message("bias not monotone at x=%s" % x).is_greater_equal(prev - 0.00001)
		prev = b
	assert_that(B.bias_at(100.0, 4096.0 + 64.0)).is_equal_approx(B.bias_at(4096.0 + 64.0, 100.0), 0.0001)

## The baked far band sits on the canonical field (bias 0) past the fade, and
## one BIAS under it inside the window.
func test_vista_band_follows_the_field_past_the_window() -> void:
	var baker := TerrainVistaBaker.new()
	var vloc := Vector2i(0, 0)
	var o := TerrainVistaBaker.region_origin(vloc)
	var tb := TerrainBaker.new()
	# Band 3 = rows z 768..1023: x < 3968 is inside the window (BIAS under the
	# field), x > 4224 is past the fade (on the field).
	var band := 3
	var out := baker.bake_band(vloc, band, [] as Array[PackedVector3Array])
	var h: PackedFloat32Array = out["height"]
	var row := 10
	var sz := o.y + float(band * TerrainVistaBaker.BAND_ROWS + row) * TerrainVistaBaker.STEP
	var far_sum := 0.0
	var far_n := 0
	var in_sum := 0.0
	var in_n := 0
	for ix in range(2, TerrainVistaBaker.REGION_PX, 4):
		var sx := o.x + float(ix) * TerrainVistaBaker.STEP
		var delta := h[row * TerrainVistaBaker.REGION_PX + ix] - tb.natural_height_at(sx + 0.5, sz + 0.5)
		var d := TerrainVistaBaker.window_distance(sx, sz)
		if d > TerrainVistaBaker.BIAS_TAPER_OUT:
			far_sum += delta
			far_n += 1
		elif d < -TerrainVistaBaker.BIAS_TAPER_IN:
			in_sum += delta
			in_n += 1
	assert_that(far_n).is_greater(10)
	assert_that(in_n).is_greater(10)
	assert_that(far_sum / float(far_n)).override_failure_message("far mean delta %s" % (far_sum / float(far_n))).is_between(-0.25, 0.25)
	assert_that(in_sum / float(in_n)).override_failure_message("inside mean delta %s" % (in_sum / float(in_n))).is_between(TerrainVistaBaker.BIAS - 0.25, TerrainVistaBaker.BIAS + 0.25)

## The vista carries collision past the window: a ray straight down in the
## alpine area hits the drawn surface (not nothing, not y = 0).
func test_vista_has_collision_where_the_ring_cannot_exist() -> void:
	var cam := _add_camera(ALPINE + Vector3(0.0, 30.0, 0.0))
	var vista := TerrainVista.new()
	vista.bake_in_headless = true
	add_child(vista)
	await get_tree().process_frame
	var locs: Array[Vector2i] = [Vector2i(0, 0)]
	assert_that(vista.start([], ALPINE, locs)).is_true()
	assert_that(vista.terrain.collision_mode).is_equal(TerrainVista.COLLISION_OFF)
	var done := await _await_until(func() -> bool: return vista.is_complete(), 120.0)
	assert_that(done).is_true()
	# Inside the window, away from the edge: collision stays off.
	vista.sync_player_pos(Vector3(1000.0, 5.0, 1000.0))
	assert_that(vista.collision_active).is_false()
	vista.sync_player_pos(ALPINE)
	assert_that(vista.collision_active).is_true()
	assert_that(vista.terrain.collision_mode).is_equal(TerrainVista.COLLISION_DYNAMIC)
	var expect := vista.terrain.data.get_height(Vector3(ALPINE.x, 0.0, ALPINE.z))
	assert_that(is_finite(expect)).is_true()
	var space := get_viewport().world_3d.direct_space_state
	var hit: Dictionary = {}
	for _i in 30:
		await get_tree().physics_frame
		var q := PhysicsRayQueryParameters3D.create(Vector3(ALPINE.x, expect + 400.0, ALPINE.z), Vector3(ALPINE.x, expect - 400.0, ALPINE.z))
		hit = space.intersect_ray(q)
		if not hit.is_empty():
			break
	assert_that(hit.is_empty()).override_failure_message("no collision under the car at %s (surface %s)" % [ALPINE, expect]).is_false()
	if not hit.is_empty():
		assert_that((hit["position"] as Vector3).y).is_equal_approx(expect, 0.6)
	# Back at the hub the collision switches off again.
	vista.sync_player_pos(Vector3(128.0, 2.0, 128.0))
	assert_that(vista.collision_active).is_false()
	cam.queue_free()
	vista.queue_free()
