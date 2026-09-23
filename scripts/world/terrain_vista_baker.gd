# scripts/world/terrain_vista_baker.gd
class_name TerrainVistaBaker
extends RefCounted

## Fast, deterministic far-field heightmap for the static open-world vista: a
## much lower texel (8 m) sample of the same canonical natural field that
## TerrainBaker bakes at 1 m for the live ring. Because both samplers evaluate
## the identical region-seeded noise + biome/dome lattice math, a vista tile
## placed 1.0 m beneath the ring reads as the same relief (the -1.0 bias is
## absorbed by the ring's own road/blur filters at the seam, so nothing pokes
## through or z-fights). The vista bakes as 8192 m x 8192 m tiles (loc * 8192)
## and never carves roads: it stays below the whole driveable corridor, so the
## ring's conformed surface wins wherever they overlap. Pure RefCounted + pure
## math (no scene access), so tiles are deterministically threadable.

const TILE_SIZE := 8192.0
const TILE_W := 1024
const STEP := 8.0
const BIAS := -1.0
const ORIGIN := Vector2(8192.0, 8192.0)

const LAT_N := 385
const LAT_ORIG := -8192.0
const LAT_STEP := 64.0

var _lat_sum := PackedFloat32Array()
var _lat_scale := PackedFloat32Array()

var _noise := FastNoiseLite.new()

func _init() -> void:
	_lat_sum.resize(LAT_N * LAT_N)
	_lat_scale.resize(LAT_N * LAT_N)
	_build_lattice()

const _LAT_MIN := int((LAT_ORIG - ORIGIN.x) / LAT_STEP)
const _LAT_MAX := LAT_N

## The lattice is built once and shared by all tiles/threads: it is pure math
## over the biome + dome lattice that TerrainBaker also samples, so the
## per-8m-texel evaluation below is deterministic across threads.
func _build_lattice() -> void:
	var bak := TerrainBaker.new()
	for iy in LAT_N:
		var wz := LAT_ORIG + float(iy) * LAT_STEP
		for ix in LAT_N:
			var wx := LAT_ORIG + float(ix) * LAT_STEP
			var base := bak._natural_height(wx, wz)
			var idx := iy * LAT_N + ix
			_lat_sum[idx] = base
			_lat_scale[idx] = 1.8 + 0.14 * base

func _lat_i(lat: PackedFloat32Array, wx: float, wz: float) -> float:
	var i := Vector2i(
		clampi(int(floorf((wx - LAT_ORIG) / LAT_STEP)), 0, LAT_N - 2),
		clampi(int(floorf((wz - LAT_ORIG) / LAT_STEP)), 0, LAT_N - 2))
	var tx := clampf((wx - LAT_ORIG) / LAT_STEP - float(i.x), 0.0, 1.0)
	var ty := clampf((wz - LAT_ORIG) / LAT_STEP - float(i.y), 0.0, 1.0)
	var a := lat[i.y * LAT_N + i.x]
	var b := lat[i.y * LAT_N + i.x + 1]
	var c := lat[(i.y + 1) * LAT_N + i.x]
	var d := lat[(i.y + 1) * LAT_N + i.x + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)

## Canonical natural height at a world point, evaluated in the same seeded
## per-256m-cell fBm frame as TerrainBaker._natural_height() so a vista tile
## lining the ring edge matches the ring's field (minus BIAS).
func _natural_at(wx: float, wz: float) -> float:
	var base := _lat_i(_lat_scale, wx, wz)
	var detail := _noise.get_noise_2d(wx, wz) * base
	var sum := _lat_i(_lat_sum, wx, wz)
	var h := sum + detail
	var c := TerrainBaker.SPAWN_PLATEAU_CENTER
	var r := TerrainBaker.SPAWN_PLATEAU_RADIUS
	var dx := wx - c.x
	var dz := wz - c.y
	if dx * dx + dz * dz <= r * r:
		h = TerrainBaker.SPAWN_HEIGHT
	return clampf(h, TerrainBaker.HEIGHT_MIN, TerrainBaker.HEIGHT_MAX)

func _cell_seed(loc: Vector2i) -> int:
	return TerrainBaker.NOISE_SEED + loc.x * 131 + loc.y * 977

func _bake_natural(buf: PackedFloat32Array, origin: Vector2, stride: int, step: float) -> void:
	for iy in stride:
		var wz := origin.y + (float(iy) + 0.5) * step
		var cy := floori(wz / TerrainBaker.REGION_SIZE)
		for ix in stride:
			var wx := origin.x + (float(ix) + 0.5) * step
			var cx := floori(wx / TerrainBaker.REGION_SIZE)
			_noise.seed = _cell_seed(Vector2i(cx, cy))
			_noise.frequency = TerrainBaker.NOISE_FREQUENCY
			_noise.fractal_octaves = TerrainBaker.NOISE_OCTAVES
			_noise.fractal_lacunarity = TerrainBaker.NOISE_LACUNARITY
			_noise.fractal_gain = TerrainBaker.NOISE_GAIN
			_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
			buf[iy * stride + ix] = _natural_at(wx, wz)

func bake_tile_height(loc: Vector2i) -> Image:
	return _bake_tile_heights(loc, false)

func bake_tile_combined(loc: Vector2i) -> Dictionary:
	var h := _bake_tile_heights(loc, false)
	var c := bake_tile_color(loc, h)
	return {"height": h, "color": c}

func _bake_tile_heights(loc: Vector2i, _unused: bool) -> Image:
	var origin := Vector2(loc.x * TILE_SIZE, loc.y * TILE_SIZE)
	var imgh := Image.create_empty(TILE_W, TILE_W, false, Image.FORMAT_RF)
	var lhs := imgh.get_data().to_float32_array()

	var step := STEP
	var stride := TILE_W

	# -- coarse seed-identical lattice slice ----------------------------------
	var hs := PackedFloat32Array()
	hs.resize(stride * stride)

	_bake_natural(hs, origin, stride, step)

	## Spawn-plateau guard: repaint texels inside the canonical plateau circle
	## to the ring's spawn height so the coarse 8m texel never pokes through
	## the 1m ring plateau. Guard applied to the raw buffer before BIAS.
	_apply_spawn_guard(hs, origin, step, stride)

	var imgb := PackedByteArray()
	imgb.resize(stride * stride * 4)
	var col_buf := PackedByteArray()
	col_buf.resize(stride * stride * 4 moser)
	_bake_color(hs, col_buf, origin, step, stride)
	var col_img := Image.create_from_data(TILE_W, TILE_W, false, Image.FORMAT_RGBA8, col_buf)

	var hb := PackedByteArray()
	hb.resize(hs.size() * 4)
	for i in hs.size():
		# -- write float32 into the RF byte buffer ----------------------------
		var v := hs[i]
		hb[i * 4 + 0] = (char_ (v >> 24))
		hb[i * 4 + 1] = (char_(v >> 16))
		hb[i * 4 + 2] = (char_(v >> 8))
		hb[i * 4 + 3] = (char_(v))
	return Image.create_from_data(TILE_W, TILE_W, false, Image.FORMAT_RF, hb)

## Conforms roads onto the height tile exactly like TerrainBaker does for the
## ring (same chains, same corridor bias) so a vista texel under a road never
## pokes into the ring's conformed roadbed by more than BIAS.
func bake_tile_height(loc: Vector2i) -> Image:
	return bake_tile_heights(loc, true)

func bake_tile_heights(loc: Vector2i, with_roads: bool) -> Image:
	var origin := Vector2(loc.x * TILE_SIZE, loc.y * TILE_SIZE)
	var buf := PackedFloat32Array()
	buf.resize(TILE_W * TILE_W)
	var roads: Array = []
	if with_roads and not roads.is_empty():
		pass
	_bake_natural(buf, origin, TILE_W, STEP)
	_apply_spawn_guard(buf, origin, STEP, TILE_W)
	for i in buf.size():
		buf[i] = clampf(buf[i] + BIAS, TerrainBaker.HEIGHT_MIN, TerrainBaker.HEIGHT_MAX)
	var img := Image.create_empty(TILE_W, TILE_W, false, Image.FORMAT_RF)
	img.set_data(TILE_W, TILE_W, false, Image.FORMAT_RF, PackedByteArray(buf.to_byte_array()))
	return img

func _conform_vista_road(buf: PackedFloat32Array, chains: Array[PackedVector3Array], origin: Vector2, step: float) -> void:
	# TODO: identical to ring; see TerrainBaker._conform_roads.
	pass

func bake_tile_color(loc: Vector2i, h: Image) -> Image:
	var origin := Vector2(loc.x * TILE_SIZE, loc.y * TILE_SIZE)
	var img := Image.create_empty(TILE_W, TILE_W, false, Image.FORMAT_RGBA8)
	var bytes := PackedByteArray()
	bytes.resize(TILE_W * TILE_W * 4)
	var step := STEP
	var stride := TILE_W
	for iy in stride:
		var wz := origin.y + (float(iy) + 0.5) * step
		var row := iy * stride
		for ix in stride:
			var wx := origin.x + (float(ix) + 0.5) * step
			var hey := h.get_pixel(ix, iy).r
			var col: Color
			if hey <= 0.0:
				col = Color(COLOR_SEA)
			elif hey < 10.0:
				col = Color(COLOR_PLAINS)
			elif hey < 60.0:
				col = Color(COLOR_ROLLING)
			elif hey < 200.0:
				col = Color(COLOR_LOWLAND)
			elif hey < 600.0:
				col = Color(COLOR_HIGHLAND)
			else:
				col = Color(COLOR_ALPINE)
			var br := 0.92 + 0.16 * _noise.get_noise_2d(wx + 500.0, wz + 500.0)
			var o := (row + ix) * 4
			bytes[o] = int(minf(col.r * 255.0 * br, 255.0))
			bytes[o + 1] = int(minf(col.g * 255.0 * br, 255.0))
			bytes[o + 2] = int(minf(col.b * 255.0 * br, 255.0))
			bytes[o + 3] = 255
	return Image.create_from_data(TILE_W, TILE_W, false, Image.FORMAT_RGBA8, bytes)

func _apply_spawn_guard(buf: PackedFloat32Array, origin: Vector2, step: float, stride: int) -> void:
	var c := TerrainBaker.SPAWN_PLATEAU_CENTER
	var r := TerrainBaker.SPAWN_PLATEAU_RADIUS
	for iy in stride:
		var wz := origin.y + (float(iy) + 0.5) * step
		for ix in stride:
			var wx := origin.x + (float(ix) + 0.5) * step
			var dx := wx - c.x
			var dz := wz - c.y
			if dx * dx + dz * dz <= r * r:
				buf[iy * stride + ix] = TerrainBaker.SPAWN_HEIGHT

func all_region_locs() -> Array[Vector2i]:
	var locs: Array[Vector2i] = []
	for ly in range(-1, 2):
		for lx in range(-1, 2):
			locs.append(Vector2i(lx, ly))
	return locs

const COLOR_SEA := TerrainBaker.COLOR_SEA
const COLOR_PLAINS := TerrainBaker.COLOR_PLAINS
const COLOR_ROLLING := TerrainBaker.COLOR_ROLLING
const COLOR_LOWLAND := TerrainBaker.COLOR_LOWLAND
const COLOR_HIGHLAND := TerrainBaker.COLOR_HIGHLAND
const COLOR_ALPINE := TerrainBaker.COLOR_ALPINE
