# tests/suites/test_terrain_texturing.gd
extends GdUnitTestSuite

## Open-world ground textures (TerrainTexturing + TerrainBaker control bake +
## TerrainSeeder control plumbing). Pins: the control-bit encoding against the
## addon's own Terrain3DUtil encoders, the layer table vs the shipped textures
## and the packer tool, the biome -> layer rules of classify_ground, the
## determinism / road shoulder / biome mix of bake_region_control, that the
## colour map is now a near-white tint (it multiplies the textures), and that
## the seeder's worker carries the control map next to height + colour.

const IMAGE_WIDTH := 256
const REGION_SIZE := 256.0
const PACKER_PATH := "res://tools/pack_terrain_textures.py"

func _await_until(condition: Callable, timeout_s: float) -> bool:
	var loops := int(timeout_s / 0.1)
	for _i in loops:
		if condition.call():
			return true
		await get_tree().create_timer(0.1).timeout
	return condition.call()

func _ids_histogram(control: Image) -> Dictionary:
	var hist := {}
	var data := control.get_data()
	for i in control.get_width() * control.get_height():
		var base := TerrainTexturing.decode_base(data.decode_u32(i * 4))
		hist[base] = int(hist.get(base, 0)) + 1
	return hist

func _share(hist: Dictionary, ids: Array) -> float:
	var total := 0
	var hit := 0
	for k in hist:
		total += int(hist[k])
		if ids.has(int(k)):
			hit += int(hist[k])
	return float(hit) / float(maxi(total, 1))

# -- Encoding -----------------------------------------------------------------

func test_encode_control_matches_terrain3d_util() -> void:
	var cases := [[0, 0, 0], [3, 5, 128], [7, 1, 255], [4, 6, 37], [5, 3, 200]]
	for c in cases:
		var base: int = c[0]
		var overlay: int = c[1]
		var blend: int = c[2]
		var expect: int = Terrain3DUtil.enc_base(base) | Terrain3DUtil.enc_overlay(overlay) | Terrain3DUtil.enc_blend(blend)
		var got := TerrainTexturing.encode_control(base, overlay, float(blend) / 255.0)
		assert_int(got).is_equal(expect)
		assert_int(Terrain3DUtil.get_base(got)).is_equal(base)
		assert_int(Terrain3DUtil.get_overlay(got)).is_equal(overlay)
		assert_int(Terrain3DUtil.get_blend(got)).is_equal(blend)
	assert_int(TerrainTexturing.encode_control(2, 2, 0.0, true)).is_equal(Terrain3DUtil.enc_base(2) | Terrain3DUtil.enc_overlay(2) | Terrain3DUtil.enc_auto(true))

func test_decode_round_trip_and_blend_clamp() -> void:
	var bits := TerrainTexturing.encode_control(6, 2, 0.4)
	assert_int(TerrainTexturing.decode_base(bits)).is_equal(6)
	assert_int(TerrainTexturing.decode_overlay(bits)).is_equal(2)
	assert_float(TerrainTexturing.decode_blend(bits)).is_equal_approx(0.4, 0.003)
	assert_float(TerrainTexturing.decode_blend(TerrainTexturing.encode_control(0, 0, 3.0))).is_equal(1.0)
	assert_float(TerrainTexturing.decode_blend(TerrainTexturing.encode_control(0, 0, -1.0))).is_equal(0.0)

# -- Layer table / assets ------------------------------------------------------

func test_layer_table_matches_shipped_textures_and_packer() -> void:
	assert_int(TerrainTexturing.LAYERS.size()).is_equal(TerrainTexturing.LAYER_COUNT)
	var packer := FileAccess.get_file_as_string(PACKER_PATH)
	assert_str(packer).is_not_empty()
	var rx := RegEx.create_from_string("\\(\"([a-z]+)\", \"[A-Za-z0-9]+\"\\)")
	var packer_names: Array[String] = []
	for m in rx.search_all(packer):
		packer_names.append(m.get_string(1))
	var names: Array[String] = []
	for id in TerrainTexturing.LAYERS.size():
		var layer: Dictionary = TerrainTexturing.LAYERS[id]
		names.append(String(layer["name"]))
		assert_bool(ResourceLoader.exists(TerrainTexturing.albedo_path(id))).is_true()
		assert_bool(ResourceLoader.exists(TerrainTexturing.normal_path(id))).is_true()
		assert_float(float(layer["uv_scale"])).is_greater(0.0)
	assert_array(packer_names).is_equal(names)
	# The id constants address the right layers.
	assert_str(String(TerrainTexturing.LAYERS[TerrainTexturing.ID_ROCK]["name"])).is_equal("rock")
	assert_str(String(TerrainTexturing.LAYERS[TerrainTexturing.ID_SNOW]["name"])).is_equal("snow")
	assert_str(String(TerrainTexturing.LAYERS[TerrainTexturing.ID_GRAVEL]["name"])).is_equal("gravel")

func test_build_assets_fills_every_layer_with_matching_sizes() -> void:
	var assets := TerrainTexturing.build_assets()
	assert_object(assets).is_not_null()
	if assets == null:
		return
	assert_int(assets.get_texture_count()).is_equal(TerrainTexturing.LAYER_COUNT)
	var size := Vector2i.ZERO
	for id in TerrainTexturing.LAYER_COUNT:
		var tex: Terrain3DTextureAsset = assets.get_texture(id)
		assert_object(tex).is_not_null()
		if tex == null:
			continue
		assert_object(tex.albedo_texture).is_not_null()
		assert_object(tex.normal_texture).is_not_null()
		var s := Vector2i(tex.albedo_texture.get_width(), tex.albedo_texture.get_height())
		if size == Vector2i.ZERO:
			size = s
		# Terrain3D texture arrays need one size for every layer and both maps.
		assert_that(s).is_equal(size)
		assert_that(Vector2i(tex.normal_texture.get_width(), tex.normal_texture.get_height())).is_equal(size)

func test_apply_turns_off_the_checkerboard_and_assigns_assets() -> void:
	var terrain := Terrain3D.new()
	add_child(terrain)
	assert_bool(TerrainTexturing.apply(terrain)).is_true()
	assert_object(terrain.assets).is_not_null()
	assert_int(terrain.assets.get_texture_count()).is_equal(TerrainTexturing.LAYER_COUNT)
	assert_bool(terrain.show_checkered).is_false()
	assert_bool(terrain.material.show_checkered).is_false()
	assert_bool(terrain.material.auto_shader).is_true()
	assert_bool(terrain.material.dual_scaling).is_false()
	# Default tier is LITE: the addon's lightweight shader as an override.
	assert_bool(terrain.material.shader_override_enabled).is_true()
	assert_object(terrain.material.shader_override).is_not_null()
	# FULL tier: Terrain3D's generated shader, no override.
	assert_bool(TerrainTexturing.apply(terrain, TerrainTexturing.QUALITY_FULL)).is_true()
	assert_bool(terrain.material.shader_override_enabled).is_false()
	assert_bool(TerrainTexturing.apply(null)).is_false()
	terrain.free()

# -- classify_ground rules -----------------------------------------------------

func _base(h: float, slope: float, patch: float, detail: float, coast: float, edge: float) -> int:
	return TerrainTexturing.decode_base(TerrainBaker.classify_ground(h, slope, patch, detail, coast, edge))

func test_classify_ground_biome_rules() -> void:
	assert_int(_base(5.0, 0.0, -0.8, 0.0, 0.0, INF)).is_equal(TerrainTexturing.ID_GRASS)
	assert_int(_base(5.0, 0.0, 0.9, 0.0, 0.0, INF)).is_equal(TerrainTexturing.ID_MEADOW)
	assert_int(_base(320.0, 0.0, -0.8, 0.0, 0.0, INF)).is_equal(TerrainTexturing.ID_FOREST)
	# Alpine ramp 620..820 m: forest floor still leads at 700 m, rock by 800 m.
	assert_int(_base(700.0, 0.0, 0.0, 0.0, 0.0, INF)).is_equal(TerrainTexturing.ID_FOREST)
	assert_int(_base(800.0, 0.0, 0.0, 0.0, 0.0, INF)).is_equal(TerrainTexturing.ID_ROCK)
	assert_int(_base(1200.0, 0.0, 0.0, 0.0, 0.0, INF)).is_equal(TerrainTexturing.ID_SNOW)
	# Steep faces are rock in any biome, snow included.
	assert_int(_base(40.0, 1.5, -0.8, 0.0, 0.0, INF)).is_equal(TerrainTexturing.ID_ROCK)
	assert_int(_base(1200.0, 1.5, 0.0, 0.0, 0.0, INF)).is_equal(TerrainTexturing.ID_ROCK)
	# Beaches only by the coast: the same 2 m height inland stays grass.
	assert_int(_base(2.0, 0.0, -0.8, 0.0, 1.0, INF)).is_equal(TerrainTexturing.ID_SAND)
	assert_int(_base(2.0, 0.0, -0.8, 0.0, 0.0, INF)).is_equal(TerrainTexturing.ID_GRASS)

func test_classify_ground_road_shoulder_bands() -> void:
	assert_int(_base(5.0, 0.0, -0.8, 0.0, 0.0, -3.0)).is_equal(TerrainTexturing.ID_GRAVEL)
	assert_int(_base(5.0, 0.0, -0.8, 0.0, 0.0, 0.5)).is_equal(TerrainTexturing.ID_GRAVEL)
	var fringe := TerrainBaker.classify_ground(5.0, 0.0, -0.8, 0.0, 0.0, 4.0)
	var pair := [TerrainTexturing.decode_base(fringe), TerrainTexturing.decode_overlay(fringe)]
	assert_bool(pair.has(TerrainTexturing.ID_DIRT)).is_true()
	assert_int(_base(5.0, 0.0, -0.8, 0.0, 0.0, 20.0)).is_equal(TerrainTexturing.ID_GRASS)

func test_classify_ground_blend_is_runner_up_share() -> void:
	for h in [0.0, 5.0, 150.0, 250.0, 650.0, 900.0]:
		for patch in [-0.9, -0.2, 0.2, 0.9]:
			var bits := TerrainBaker.classify_ground(h, 0.3, patch, 0.4, 0.2, 3.0)
			assert_float(TerrainTexturing.decode_blend(bits)).is_between(0.0, 0.502)
			assert_int(TerrainTexturing.decode_base(bits)).is_less(TerrainTexturing.LAYER_COUNT)
			assert_int(TerrainTexturing.decode_overlay(bits)).is_less(TerrainTexturing.LAYER_COUNT)

# -- bake_region_control --------------------------------------------------------

func _road_through(region: Vector2i) -> Array:
	var z := region.y * REGION_SIZE + REGION_SIZE * 0.5
	var x0 := region.x * REGION_SIZE - 50.0
	var pts: Array[Vector3] = [Vector3(x0, 2.0, z), Vector3(x0 + REGION_SIZE + 100.0, 2.0, z)]
	return [pts]

func test_control_bake_is_deterministic_and_sized() -> void:
	var a := TerrainBaker.new().bake_region_control(Vector2i(1, 1), 1.0, IMAGE_WIDTH, [])
	var b := TerrainBaker.new().bake_region_control(Vector2i(1, 1), 1.0, IMAGE_WIDTH, [])
	assert_int(a.get_width()).is_equal(IMAGE_WIDTH)
	assert_int(a.get_height()).is_equal(IMAGE_WIDTH)
	assert_int(a.get_format()).is_equal(Image.FORMAT_RF)
	assert_that(a.get_data()).is_equal(b.get_data())
	# Passing the already-baked height image gives the same answer as rebaking it.
	var baker := TerrainBaker.new()
	var h := baker.bake_region(Vector2i(1, 1), 1.0, IMAGE_WIDTH, [])
	var c := baker.bake_region_control(Vector2i(1, 1), 1.0, IMAGE_WIDTH, [], h)
	assert_that(c.get_data()).is_equal(a.get_data())

func test_control_bake_puts_gravel_on_the_road_shoulder() -> void:
	var region := Vector2i(2, 0)
	var roads := _road_through(region)
	var widths := PackedFloat32Array([10.0])
	var img := TerrainBaker.new().bake_region_control(region, 1.0, IMAGE_WIDTH, roads, null, widths)
	var mid := IMAGE_WIDTH / 2
	# 6 m off the centreline = 1 m past the 5 m half width: gravel shoulder.
	assert_int(TerrainTexturing.decode_base(TerrainTexturing.control_at(img, mid, mid + 6))).is_equal(TerrainTexturing.ID_GRAVEL)
	# 80 m away: no road influence at all.
	assert_int(TerrainTexturing.decode_base(TerrainTexturing.control_at(img, mid, mid + 80))).is_not_equal(TerrainTexturing.ID_GRAVEL)

func test_control_bake_biome_mix_per_region() -> void:
	var baker := TerrainBaker.new()
	# Spawn plains: grass family, never sand/snow.
	var spawn := _ids_histogram(baker.bake_region_control(Vector2i(0, 0), 1.0, IMAGE_WIDTH, []))
	assert_float(_share(spawn, [TerrainTexturing.ID_GRASS, TerrainTexturing.ID_MEADOW, TerrainTexturing.ID_DIRT, TerrainTexturing.ID_FOREST])).is_greater(0.95)
	assert_float(_share(spawn, [TerrainTexturing.ID_SAND, TerrainTexturing.ID_SNOW])).is_equal(0.0)
	# The tallest dome's summit: rock and snow.
	var peak: Vector2 = TerrainBaker.DOME_FAMILY[0]["center"]
	var peak_loc := Vector2i(floori(peak.x / REGION_SIZE), floori(peak.y / REGION_SIZE))
	var alpine := _ids_histogram(baker.bake_region_control(peak_loc, 1.0, IMAGE_WIDTH, []))
	assert_float(_share(alpine, [TerrainTexturing.ID_ROCK, TerrainTexturing.ID_SNOW])).is_greater(0.9)
	# Coast biome centre: mostly beach sand.
	var coast_loc := Vector2i(floori(TerrainBaker.BIOME_COAST_CENTER.x / REGION_SIZE), floori(TerrainBaker.BIOME_COAST_CENTER.y / REGION_SIZE))
	var coast := _ids_histogram(baker.bake_region_control(coast_loc, 1.0, IMAGE_WIDTH, []))
	assert_float(_share(coast, [TerrainTexturing.ID_SAND])).is_greater(0.3)

func test_colour_map_is_a_near_white_tint() -> void:
	var img := TerrainBaker.new().bake_region_color(Vector2i(0, 0), 1.0, IMAGE_WIDTH, [])
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for y in range(0, IMAGE_WIDTH, 16):
		for x in range(0, IMAGE_WIDTH, 16):
			var c := img.get_pixel(x, y)
			sum += c
			n += 1
	var avg := sum / float(n)
	assert_float(avg.r).is_greater(0.8)
	assert_float(avg.g).is_greater(0.8)
	assert_float(avg.b).is_greater(0.8)
	assert_float(avg.a).is_equal_approx(0.5, 0.06)

# -- Seeder plumbing -------------------------------------------------------------

func test_worker_bake_carries_the_control_map() -> void:
	var seeder := TerrainSeeder.new()
	var target := Vector2i(3, 1)
	seeder._queue_bake(target, IMAGE_WIDTH)
	var landed := await _await_until(func() -> bool: return seeder._pending_count() > 0, 30.0)
	assert_bool(landed).is_true()
	seeder._drain_pending(null, 100)
	var rec: Dictionary = seeder._baked.get(target, {})
	var control: Image = rec.get("control") as Image
	assert_object(control).is_not_null()
	if control != null:
		var reference := TerrainBaker.new().bake_region_control(target, 1.0, IMAGE_WIDTH, [])
		assert_that(control.get_data()).is_equal(reference.get_data())
	assert_bool(seeder.has_baked_region(target)).is_true()
	assert_bool(seeder.has_baked_region(Vector2i(40, 40))).is_false()
	seeder._stop_worker()

func test_player_region_write_lands_in_terrain_control_map() -> void:
	var terrain := Terrain3D.new()
	add_child(terrain)
	var seeder := TerrainSeeder.new()
	seeder.terrain = terrain
	add_child(seeder)
	seeder.sync_player_pos(Vector3(128.0, 2.2, 128.0))
	var region: Terrain3DRegion = terrain.data.get_region(Vector2i(0, 0))
	assert_object(region).is_not_null()
	if region != null:
		var control: Image = region.get_map(Terrain3DRegion.TYPE_CONTROL)
		assert_object(control).is_not_null()
		var rec: Dictionary = seeder._baked.get(Vector2i(0, 0), {})
		var cached: Image = rec.get("control") as Image
		assert_object(cached).is_not_null()
		if control != null and cached != null:
			assert_int(TerrainTexturing.control_at(control, 128, 128)).is_equal(TerrainTexturing.control_at(cached, 128, 128))
	seeder._stop_worker()
	seeder.free()
	terrain.free()

## Live-ring regions must bake ahead of the speculative corridor pre-bake. A
## ring region the corridor pass already queued (PRIORITY_CORRIDOR) is promoted
## to PRIORITY_LIVE when the ring moves onto it; ring regions queued fresh go in
## at LIVE; the outer prefetch band stays PREFETCH. (Regression: the ring sat
## blank and flat for tens of seconds behind ~150 corridor jobs.) The worker is
## held off by keeping the seeder's (recursive) mutex for the whole check.
func test_live_ring_beats_the_corridor_prebake() -> void:
	var seeder := TerrainSeeder.new()
	seeder._lock.lock()
	# The corridor pass marks regions around road POINTS, so sample densely.
	var road: Array[Vector3] = []
	for i in range(23):
		road.append(Vector3(-200.0 + 50.0 * float(i), 2.0, 128.0))
	seeder.set_roads([road])
	assert_int(seeder._queued_priority(Vector2i(1, 0))).is_equal(TerrainSeeder.PRIORITY_CORRIDOR)
	seeder._prefetch_ring(Vector2i(0, 0))
	assert_int(seeder._queued_priority(Vector2i(1, 0))).is_equal(TerrainSeeder.PRIORITY_LIVE)
	assert_int(seeder._queued_priority(Vector2i(-1, -1))).is_equal(TerrainSeeder.PRIORITY_LIVE)
	assert_int(seeder._queued_priority(Vector2i(0, 0))).is_equal(TerrainSeeder.PRIORITY_LIVE)
	assert_int(seeder._queued_priority(Vector2i(2, 2))).is_equal(TerrainSeeder.PRIORITY_PREFETCH)
	seeder._lock.unlock()
	seeder._stop_worker()
	seeder.free()