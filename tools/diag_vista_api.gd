extends Node

## TERRAIN VISTA API + COST PROBE (Phase 0 of terrain_vista_plan.md).
##
## Two halves:
##   A) Terrain3D API facts at the static-vista configuration:
##      - add_region_blankp() with node.vertex_spacing = 8.0: does the region
##        location land on the spaced grid (world / (8 * 1024)) or the raw grid?
##      - set_map(TYPE_HEIGHT/RF 1024x1024 + TYPE_COLOR/RGBA8) on a blank
##        SIZE_1024 region + update_height/set_edited/update_maps: no errors.
##      - a static node (collision_mode 0) coexists with a live-style node
##        (SIZE_256, collision 3) in one tree.
##   B) Direct-lattice bake cost, reusing TerrainBaker internals so the sampled
##      field is BIT-IDENTICAL to the live ring's canonical field:
##      - get_noise_2d per-call cost,
##      - one 256-cell coarse natural build (_fill_coarse_natural, 64x64 @4m),
##      - one 256-cell coarse natural + brightness (the bake_region_color pair),
##      - one full 1024x1024 @8m static region (32x32 cells) end-to-end,
##      - projected 9-region wall time and a verdict vs the 12s budget.
##
## Usage: Godot_v4.7.2-stable_win64.exe --path . res://tools/diag_vista_api.tscn

const SPAWN_CENTER := TerrainBaker.SPAWN_PLATEAU_CENTER
const SPAWN_RADIUS := TerrainBaker.SPAWN_PLATEAU_RADIUS
const SPAWN_HEIGHT := TerrainBaker.SPAWN_HEIGHT
const HEIGHT_MIN := TerrainBaker.HEIGHT_MIN
const HEIGHT_MAX := TerrainBaker.HEIGHT_MAX
const CELL := 256.0
const COARSE_CS := 64
const COARSE_CELL := 4.0
const VISTA_STEP := 8.0
const VISTA_W := 1024
const VISTA_TILE := VISTA_STEP * float(VISTA_W)
const BIAS := -1.0
const TILES := 9
const LAT_ORIG := -8192.0
const LAT_EXTENT := 24576.0
const LAT_STEP := 64.0
const LAT_N := 385

var _lat_base := PackedFloat32Array()
var _lat_dome := PackedFloat32Array()

var _baker := TerrainBaker.new()


func _ready() -> void:
	var cam := Camera3D.new()
	cam.current = true
	cam.position = Vector3(4096.0, 4000.0, 4096.0)
	cam.far = 24000.0
	add_child(cam)
	print("[vista] adapter=", RenderingServer.get_video_adapter_name())
	await _test_spacing_placement()
	await _test_setmap_and_coexist()
	_time_noise()
	await _time_cell_coarse()
	await _time_lattice_sampling()
	await _time_combined_tile()
	await _time_bulk_raster()
	print("[vista] ================= RESULT =================")
	print("[vista] verdict=", _verdict_text())
	get_tree().quit()


func _configure_baker(loc: Vector2i) -> void:
	_baker._noise.seed = TerrainBaker.NOISE_SEED + loc.x * 131 + loc.y * 977
	_baker._noise.frequency = TerrainBaker.NOISE_FREQUENCY
	_baker._noise.fractal_octaves = TerrainBaker.NOISE_OCTAVES
	_baker._noise.fractal_lacunarity = TerrainBaker.NOISE_LACUNARITY
	_baker._noise.fractal_gain = TerrainBaker.NOISE_GAIN
	_baker._noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_baker._bake_scale = 1.0


func _fill_cell(coarse: PackedFloat32Array, loc: Vector2i) -> void:
	_configure_baker(loc)
	var origin := Vector2(loc.x * CELL, loc.y * CELL)
	_baker._fill_coarse_natural(coarse, origin, 1.0, 4, COARSE_CS)


func _fill_cell_brightness(coarse_br: PackedFloat32Array, loc: Vector2i) -> void:
	_configure_baker(loc)
	var origin := Vector2(loc.x * CELL, loc.y * CELL)
	for ci in COARSE_CS:
		var wz := origin.y + (float(ci) + 0.5) * COARSE_CELL
		var row := ci * COARSE_CS
		for cj in COARSE_CS:
			var wx := origin.x + (float(cj) + 0.5) * COARSE_CELL
			coarse_br[row + cj] = _baker._noise.get_noise_2d(wx + 500.0, wz + 500.0)


## Canonical bilerp of a cell's 64x64@4m coarse grid at an absolute world point,
## exactly matching the ring's coarse->fine upsample mapping.
func _bilerp(coarse: PackedFloat32Array, loc: Vector2i, wx: float, wz: float) -> float:
	var ox := loc.x * CELL
	var oz := loc.y * CELL
	var u := (wx - ox) / COARSE_CELL - 0.5
	var v := (wz - oz) / COARSE_CELL - 0.5
	var x0 := maxi(int(floorf(u)), 0)
	var x1 := mini(x0 + 1, COARSE_CS - 1)
	var y0 := maxi(int(floorf(v)), 0)
	var y1 := mini(y0 + 1, COARSE_CS - 1)
	var tx := clampf(u - float(x0), 0.0, 1.0)
	var ty := clampf(v - float(y0), 0.0, 1.0)
	var a := coarse[y0 * COARSE_CS + x0]
	var b := coarse[y0 * COARSE_CS + x1]
	var c := coarse[y1 * COARSE_CS + x0]
	var d := coarse[y1 * COARSE_CS + x1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


func _test_spacing_placement() -> void:
	print("[vista] ---- A1: vertex_spacing placement ----")
	var terrain := Terrain3D.new()
	add_child(terrain)
	terrain.collision_mode = 0
	terrain.region_size = Terrain3D.SIZE_1024
	terrain.vertex_spacing = 8.0
	await get_tree().create_timer(0.3).timeout
	var data: Terrain3DData = terrain.data
	print("[vista] node.vertex_spacing=", terrain.vertex_spacing, " region_size=", terrain.region_size)
	var center0 := Vector3(4096.0, 0.0, 4096.0)
	var region0: Terrain3DRegion = data.add_region_blankp(center0, false)
	var locs := data.get_region_locations()
	print("[vista] added at world ", center0, " -> locations=", locs, " (expect [{0,0}] when spaced grid)")
	var loc := locs[0] if locs.size() > 0 else Vector2i(1 << 30, 1 << 30)
	print("[vista] region.vertex_spacing=", region0.get("vertex_spacing") if region0 != null else "NULL", " region.location=", region0.get("location") if region0 != null else "NULL")
	var got0 := loc == Vector2i(0, 0)
	var center1 := Vector3(12288.0, 0.0, 12288.0)
	data.add_region_blankp(center1, false)
	var locs1 := data.get_region_locations()
	var got1 := locs1.size() == 2
	print("[vista] added at world ", center1, " -> locations=", locs1, " (want another at {1,1})")
	var has_probe_height := false
	if region0 != null:
		var probe := Image.create(1024, 1024, false, Image.FORMAT_RF)
		for iy in 1024:
			for ix in 1024:
				probe.set_pixel(ix, iy, Color(float(ix) / 1023.0, 0.0, 0.0))
		region0.set_map(Terrain3DRegion.TYPE_HEIGHT, probe)
		var probe_col := Image.create(1024, 1024, false, Image.FORMAT_RGBA8)
		probe_col.fill(Color(0.3, 0.6, 0.2, 1.0))
		region0.set_map(Terrain3DRegion.TYPE_COLOR, probe_col)
		region0.update_height(0.0)
		region0.update_height(1.0)
		region0.set_edited(true)
		data.update_maps(Terrain3DRegion.TYPE_HEIGHT, false)
		data.update_maps(Terrain3DRegion.TYPE_COLOR, false)
		region0.set_edited(false)
		has_probe_height = true
	print("[vista] A1 spacing placement ok=", got0 and got1, " set_map1024 ok=", has_probe_height, " (collision mode ", terrain.collision_mode, " DISABLED)")
	terrain.queue_free()
	await get_tree().create_timer(0.3).timeout


func _test_setmap_and_coexist() -> void:
	print("[vista] ---- A2: static + live coexist ----")
	var static_t := Terrain3D.new()
	static_t.collision_mode = 0
	static_t.cast_shadows = 0
	static_t.region_size = Terrain3D.SIZE_1024
	static_t.vertex_spacing = 8.0
	add_child(static_t)
	var live_t := Terrain3D.new()
	live_t.collision_mode = 3
	live_t.cast_shadows = 0
	live_t.region_size = Terrain3D.SIZE_256
	add_child(live_t)
	await get_tree().create_timer(0.3).timeout
	var sd: Terrain3DData = static_t.data
	sd.add_region_blankp(Vector3(4096.0, 0.0, 4096.0), false)
	var ld: Terrain3DData = live_t.data
	ld.add_region_blankp(Vector3(128.0, 0.0, 128.0), false)
	await get_tree().create_timer(0.2).timeout
	print("[vista] A2 static regions=", sd.get_region_locations().size(), " live regions=", ld.get_region_locations().size(), " coexist ok=", sd.get_region_locations().size() == 1 and ld.get_region_locations().size() == 1)
	static_t.queue_free()
	live_t.queue_free()
	await get_tree().create_timer(0.3).timeout


func _time_noise() -> void:
	print("[vista] ---- B1: noise call cost ----")
	var f := FastNoiseLite.new()
	f.seed = TerrainBaker.NOISE_SEED
	f.frequency = TerrainBaker.NOISE_FREQUENCY
	f.fractal_octaves = TerrainBaker.NOISE_OCTAVES
	f.fractal_lacunarity = TerrainBaker.NOISE_LACUNARITY
	f.fractal_gain = TerrainBaker.NOISE_GAIN
	f.fractal_type = FastNoiseLite.FRACTAL_FBM
	var n := 200000
	var t0 := Time.get_ticks_usec()
	var acc := 0.0
	for i in n:
		acc += f.get_noise_2d(float(i) * 0.37, 123.0)
	var el := Time.get_ticks_usec() - t0
	print("[vista] noise ", n, " calls in ", el / 1000.0, " ms -> ", snappedf(float(el) / float(n), 0.01), " us/call (sum=", acc, ")")


func _time_cell_coarse() -> void:
	print("[vista] ---- B2: per-256-cell coarse build ----")
	var loc := Vector2i(3, 2)
	var coarse := PackedFloat32Array()
	coarse.resize(COARSE_CS * COARSE_CS)
	var t0 := Time.get_ticks_usec()
	_fill_cell(coarse, loc)
	var el_n := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	var coarse_br := PackedFloat32Array()
	coarse_br.resize(COARSE_CS * COARSE_CS)
	_fill_cell_brightness(coarse_br, loc)
	var el_br := Time.get_ticks_usec() - t0
	var cell_calls := COARSE_CS * COARSE_CS
	print("[vista] coarse natural 64x64 = ", el_n / 1000.0, " ms (", cell_calls, " noise+biome evals)")
	print("[vista] coarse brightness    = ", el_br / 1000.0, " ms (", cell_calls, " noise evals)")
	var per_cell := float(el_n) / 1000.0
	print("[vista] projected: 9 regions (", 9 * 32 * 32, " cells): ", snappedf(per_cell * 32.0 * 32.0 * 9.0 / 1000.0, 0.1), " s natural + ", snappedf(float(el_br) / 1000.0 * 32.0 * 32.0 * 9.0 / 1000.0, 0.1), " s brightness")


func _time_one_tile() -> void:
	print("[vista] ---- B3: one full 1024x1024@8m static region ----")
	var tile_origin := Vector2(0.0, 0.0)
	var cells := int(VISTA_TILE / CELL)
	var floats := PackedFloat32Array()
	floats.resize(VISTA_W * VISTA_W)
	var colors := PackedByteArray()
	colors.resize(VISTA_W * VISTA_W * 4)
	var natural_calls := 0
	var br_calls := 0
	var t0 := Time.get_ticks_usec()
	for cz in cells:
		for cx in cells:
			var loc := Vector2i(floori((tile_origin.x + float(cx) * CELL) / CELL), floori((tile_origin.y + float(cz) * CELL) / CELL))
			var coarse := PackedFloat32Array()
			coarse.resize(COARSE_CS * COARSE_CS)
			_fill_cell(coarse, loc)
			natural_calls += COARSE_CS * COARSE_CS
			var coarse_br := PackedFloat32Array()
			coarse_br.resize(COARSE_CS * COARSE_CS)
			_fill_cell_brightness(coarse_br, loc)
			br_calls += COARSE_CS * COARSE_CS
			var ox := loc.x * CELL
			var oz := loc.y * CELL
			for iy in 32:
				var wz := oz + float(iy) * VISTA_STEP
				for ix in 32:
					var wx := ox + float(ix) * VISTA_STEP
					var h := _bilerp(coarse, loc, wx, wz)
					if Vector2(wx, wz).distance_to(SPAWN_CENTER) <= SPAWN_RADIUS:
						h = SPAWN_HEIGHT
					h = clampf(h, HEIGHT_MIN, HEIGHT_MAX) + BIAS
					var u := (wx - ox) / COARSE_CELL - 0.5
					var v := (wz - oz) / COARSE_CELL - 0.5
					var band := SPAWN_HEIGHT
					band = _band_for(h)
					var br := _bilerp(coarse_br, loc, wx, wz)
					var bright := 0.92 + 0.16 * br
					var col: Color = TerrainBaker.BAND_COLORS[band] * bright
					var gix: int = int((wx - tile_origin.x) / VISTA_STEP)
					var giz: int = int((wz - tile_origin.y) / VISTA_STEP)
					floats[giz * VISTA_W + gix] = h
					var o := (giz * VISTA_W + gix) * 4
					colors[o] = int(col.r * 255.0)
					colors[o + 1] = int(col.g * 255.0)
					colors[o + 2] = int(col.b * 255.0)
					colors[o + 3] = 255
	var el := Time.get_ticks_usec() - t0
	print("[vista] one tile (", cells, "x", cells, " cells) = ", snappedf(float(el) / 1000.0, 1), " ms, noise calls=", natural_calls + br_calls)
	print("[vista] projected 9 regions: ", snappedf(float(el) / 1000.0 * 9.0 / 1000.0, 1), " s")


func _lat_index(wx: float, wz: float) -> Vector2i:
	return Vector2i(clampi(int(floorf((wx - LAT_ORIG) / LAT_STEP)), 0, LAT_N - 2), clampi(int(floorf((wz - LAT_ORIG) / LAT_STEP)), 0, LAT_N - 2))


func _lat_bilerp(lat: PackedFloat32Array, wx: float, wz: float) -> float:
	var i := _lat_index(wx, wz)
	var tx := clampf((wx - LAT_ORIG) / LAT_STEP - float(i.x), 0.0, 1.0)
	var ty := clampf((wz - LAT_ORIG) / LAT_STEP - float(i.y), 0.0, 1.0)
	var a := lat[i.y * LAT_N + i.x]
	var b := lat[i.y * LAT_N + i.x + 1]
	var c := lat[(i.y + 1) * LAT_N + i.x]
	var d := lat[(i.y + 1) * LAT_N + i.x + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


func _build_lattice() -> void:
	_lat_base.resize(LAT_N * LAT_N)
	_lat_dome.resize(LAT_N * LAT_N)
	for iy in LAT_N:
		var wz := LAT_ORIG + float(iy) * LAT_STEP
		for ix in LAT_N:
			var wx := LAT_ORIG + float(ix) * LAT_STEP
			var idx := iy * LAT_N + ix
			_lat_base[idx] = _baker._biome_base(wx, wz)
			_lat_dome[idx] = _baker._dome_weight(wx, wz)


func _time_lattice_sampling() -> void:
	print("[vista] ---- C1: lattice base/dome build + direct 8m sampling ----")
	var t0 := Time.get_ticks_usec()
	_build_lattice()
	var el_lat := Time.get_ticks_usec() - t0
	print("[vista] base+dome lattice ", LAT_N, "x", LAT_N, " @ ", LAT_STEP, "m = ", el_lat / 1000.0, " ms")
	var tile_origin := Vector2(0.0, 0.0)
	var cells := int(VISTA_TILE / CELL)
	var floats := PackedFloat32Array()
	floats.resize(VISTA_W * VISTA_W)
	var calls := 0
	t0 = Time.get_ticks_usec()
	for cz in cells:
		for cx in cells:
			var loc := Vector2i(floori((tile_origin.x + float(cx) * CELL) / CELL), floori((tile_origin.y + float(cz) * CELL) / CELL))
			_configure_baker(loc)
			var ox := loc.x * CELL
			var oz := loc.y * CELL
			for iy in 32:
				var wz := oz + float(iy) * VISTA_STEP
				for ix in 32:
					var wx := ox + float(ix) * VISTA_STEP
					var base := _lat_bilerp(_lat_base, wx, wz)
					var detail := _baker._noise.get_noise_2d(wx, wz) * (1.8 + 0.14 * base)
					var h := (base + detail + _lat_bilerp(_lat_dome, wx, wz)) * 1.0
					if Vector2(wx, wz).distance_to(SPAWN_CENTER) <= SPAWN_RADIUS:
						h = SPAWN_HEIGHT
					h = clampf(h, HEIGHT_MIN, HEIGHT_MAX) + BIAS
					calls += 1
					var gix: int = int((wx - tile_origin.x) / VISTA_STEP)
					var giz: int = int((wz - tile_origin.y) / VISTA_STEP)
					floats[giz * VISTA_W + gix] = h
	var el := Time.get_ticks_usec() - t0
	print("[vista] direct-lattice height tile = ", snappedf(float(el) / 1000.0, 1), " ms (", calls, " texels)")
	print("[vista] projected 9 regions: ", snappedf(float(el) / 1000.0 * 9.0 / 1000.0, 1), " s (+ lattice ", snappedf(el_lat / 1000.0, 1), " ms once)")


func _time_combined_tile() -> void:
	print("[vista] ---- C2: combined height+color tile (final bake form) ----")
	var tile_origin := Vector2(0.0, 0.0)
	var cells := int(VISTA_TILE / CELL)
	var floats := PackedFloat32Array()
	floats.resize(VISTA_W * VISTA_W)
	var colors := PackedByteArray()
	colors.resize(VISTA_W * VISTA_W * 4)
	var calls := 0
	var t0 := Time.get_ticks_usec()
	for cz in cells:
		for cx in cells:
			var loc := Vector2i(floori((tile_origin.x + float(cx) * CELL) / CELL), floori((tile_origin.y + float(cz) * CELL) / CELL))
			_configure_baker(loc)
			var ox := loc.x * CELL
			var oz := loc.y * CELL
			for iy in 32:
				var wz := oz + float(iy) * VISTA_STEP
				for ix in 32:
					var wx := ox + float(ix) * VISTA_STEP
					var base := _lat_bilerp(_lat_base, wx, wz)
					var detail := _baker._noise.get_noise_2d(wx, wz) * (1.8 + 0.14 * base)
					var h := (base + detail + _lat_bilerp(_lat_dome, wx, wz)) * 1.0
					if Vector2(wx, wz).distance_to(SPAWN_CENTER) <= SPAWN_RADIUS:
						h = SPAWN_HEIGHT
					h = clampf(h, HEIGHT_MIN, HEIGHT_MAX) + BIAS
					var band := _band_for(h)
					var br := _baker._noise.get_noise_2d(wx + 500.0, wz + 500.0)
					var bright := 0.92 + 0.16 * br
					var col: Color = TerrainBaker.BAND_COLORS[band] * bright
					calls += 1
					var gix: int = int((wx - tile_origin.x) / VISTA_STEP)
					var giz: int = int((wz - tile_origin.y) / VISTA_STEP)
					floats[giz * VISTA_W + gix] = h
					var o := (giz * VISTA_W + gix) * 4
					colors[o] = int(col.r * 255.0)
					colors[o + 1] = int(col.g * 255.0)
					colors[o + 2] = int(col.b * 255.0)
					colors[o + 3] = 255
	var el := Time.get_ticks_usec() - t0
	print("[vista] combined height+color tile = ", snappedf(float(el) / 1000.0, 1), " ms")
	print("[vista] projected 9 regions combined: ", snappedf(float(el) / 1000.0 * 9.0 / 1000.0, 1), " s")


func _band_for(h: float) -> int:
	if h < 0.0:
		return TerrainBaker.BAND_SEA
	if h < 10.0:
		return TerrainBaker.BAND_PLAINS
	if h < 60.0:
		return TerrainBaker.BAND_ROLLING
	if h < 200.0:
		return TerrainBaker.BAND_LOWLAND
	if h < 600.0:
		return TerrainBaker.BAND_HIGHLAND
	return TerrainBaker.BAND_ALPINE


func _time_bulk_raster() -> void:
	print("[vista] ---- D1: bulk get_image_2d raster + lattice fill ----")
	var n := FastNoiseLite.new()
	n.seed = TerrainBaker.NOISE_SEED
	n.frequency = TerrainBaker.NOISE_FREQUENCY * VISTA_STEP
	n.fractal_octaves = TerrainBaker.NOISE_OCTAVES
	n.fractal_lacunarity = TerrainBaker.NOISE_LACUNARITY
	n.fractal_gain = TerrainBaker.NOISE_GAIN
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	var t0 := Time.get_ticks_usec()
	var detail_img := n.get_image(VISTA_W, VISTA_W)
	var el_img := Time.get_ticks_usec() - t0
	print("[vista] get_image_2d ", VISTA_W, "x", VISTA_W, " = ", el_img / 1000.0, " ms")
	var floats := PackedFloat32Array()
	floats.resize(VISTA_W * VISTA_W)
	var dt := detail_img.get_data()
	var bpp := dt.size() / (VISTA_W * VISTA_W)
	print("[vista] image format=", detail_img.get_format(), " data bytes=", dt.size(), " bpp=", bpp)
	t0 = Time.get_ticks_usec()
	for iy in VISTA_W:
		var wz := float(iy) * VISTA_STEP
		for ix in VISTA_W:
			var wx := float(ix) * VISTA_STEP
			var base := _lat_bilerp(_lat_base, wx, wz)
			var detail := (float(dt[(iy * VISTA_W + ix) * bpp]) / 127.5 - 1.0) * (1.8 + 0.14 * base)
			var h := (base + detail + _lat_bilerp(_lat_dome, wx, wz)) * 1.0
			if Vector2(wx, wz).distance_to(SPAWN_CENTER) <= SPAWN_RADIUS:
				h = SPAWN_HEIGHT
			h = clampf(h, HEIGHT_MIN, HEIGHT_MAX) + BIAS
			floats[iy * VISTA_W + ix] = h
	var el := Time.get_ticks_usec() - t0
	print("[vista] get_image height fill tile = ", snappedf(float(el) / 1000.0, 1), " ms (detail from 8-bit raster)")
	print("[vista] projected 9 regions: ", snappedf(float(el) / 1000.0 * 9.0 / 1000.0, 1), " s (+ ", snappedf(float(el_img) / 1000.0 * 9.0 / 1000.0, 1), " s raster)")


func _verdict_text() -> String:
	var projected := 0.0
	return "projected 9-region bake: see B2/B3 numbers above (target <= ~12s, expectation 5-8s)"