# scripts/world/terrain_baker.gd
class_name TerrainBaker
extends RefCounted

## Pure heightfield math for Terrain3D regions: no scene tree access, so the
## whole class is headless-unit-testable and deterministic. bake_region() runs
## the passes in order: deterministic natural heightfield (region-seeded fBm
## over a blended biome elevation table plus alpine domes), optional
## road-corridor conforming via a coarse distance field, a 3x3 separable blur,
## then the spawn-plateau guard and the final height clamp. bake_region_color()
## produces a matching FORMAT_RGBA8 colour map by reusing the same biome/dome
## math and painting per-elevation-band colours plus road-surface tints.

const REGION_SIZE := 1024.0

# -- Elevation band taxonomy (SEA < 0, ALPINE 600..1500+) -------------------
const BAND_SEA := 0
const BAND_PLAINS := 1
const BAND_ROLLING := 2
const BAND_LOWLAND := 3
const BAND_HIGHLAND := 4
const BAND_ALPINE := 5
const BAND_COUNT := 6

const ELEVATION_BANDS := [
	{"name": "SEA",      "min": -INF, "max": 0.0},
	{"name": "PLAINS",   "min": 0.0,  "max": 10.0},
	{"name": "ROLLING",  "min": 10.0, "max": 60.0},
	{"name": "LOWLAND",  "min": 60.0, "max": 200.0},
	{"name": "HIGHLAND", "min": 200.0, "max": 600.0},
	{"name": "ALPINE",   "min": 600.0, "max": INF},
]

# -- Spawn plateau (unchanged) -----------------------------------------------
const SPAWN_PLATEAU_CENTER := Vector2(128.0, 128.0)
const SPAWN_PLATEAU_RADIUS := 40.0
const SPAWN_HEIGHT := 2.2
const BASE_HEIGHT := 1.0

# -- Noise (unchanged) -------------------------------------------------------
const NOISE_SEED := 1337
const NOISE_FREQUENCY := 0.003
const NOISE_OCTAVES := 3
const NOISE_LACUNARITY := 2.0
const NOISE_GAIN := 0.5

# -- Original driveable-corridor biome centres (preserved exactly) ------------
const BIOME_SPAWN_CENTER := Vector2(128.0, 128.0)
const BIOME_SPAWN_BASE := 2.0
const BIOME_SPAWN_RADIUS := 1500.0
const BIOME_ROLLING_CENTER := Vector2(2048.0, 2048.0)
const BIOME_ROLLING_BASE := 18.0
const BIOME_ROLLING_RADIUS := 2000.0
const BIOME_HIGHLAND_CENTER := Vector2(3584.0, 2816.0)
const BIOME_HIGHLAND_BASE := 35.0
const BIOME_HIGHLAND_RADIUS := 2600.0
const BIOME_FALLBACK_BASE := 1.0

# -- Legacy alpine dome (preserved exactly) -----------------------------------
const LEGACY_DOME_CENTER := Vector2(5632.0, 5632.0)
const LEGACY_DOME_RADIUS := 5000.0
const LEGACY_DOME_EDGE := 0.35
const LEGACY_DOME_AMP := 42.0

# -- New driveable-corridor biomes (far from hub/pass) -----------------------
const BIOME_LOWLAND_CENTER := Vector2(4600.0, 4700.0)
const BIOME_LOWLAND_BASE := 90.0
const BIOME_LOWLAND_RADIUS := 2200.0
const BIOME_HIGHLAND_PLATEAU_CENTER := Vector2(6800.0, 6400.0)
const BIOME_HIGHLAND_PLATEAU_BASE := 260.0
const BIOME_HIGHLAND_PLATEAU_RADIUS := 2600.0
const BIOME_FARMLAND_CENTER := Vector2(2048.0, 400.0)
const BIOME_FARMLAND_BASE := 6.0
const BIOME_FARMLAND_RADIUS := 1600.0
const BIOME_COAST_CENTER := Vector2(8200.0, -1800.0)
const BIOME_COAST_BASE := 2.5
const BIOME_COAST_RADIUS := 1800.0
const BIOME_SEA_CENTER := Vector2(8200.0, -3400.0)
const BIOME_SEA_BASE := -6.0
const BIOME_SEA_RADIUS := 2600.0

# -- Massif dome family (compact alpine domes, far from driveable corridor) ---
const DOME_FAMILY := [
	{"center": Vector2(7800.0, 6400.0), "radius": 3200.0, "edge": 0.5, "amp": 1100.0},
	{"center": Vector2(6400.0, 7800.0), "radius": 2800.0, "edge": 0.5, "amp": 850.0},
	{"center": Vector2(7000.0, 3000.0), "radius": 1800.0, "edge": 0.5, "amp": 150.0},
]

# -- Height limits (no 60 m ceiling; real alpine peaks reach >= 1500 m) -------
const HEIGHT_MIN := -8.0
const HEIGHT_MAX := 2000.0

# -- Road / field constants (unchanged) --------------------------------------
const ROAD_WIDTH := 11.0
const ROAD_TOPPING := 0.15
const BLEND_END_DISTANCE := 40.0
const FIELD_STEP := 4.0
const FIELD_MARGIN := 16.0
const SAMPLE_SPACING := 2.0

# -- Elevation-band colour palette (RGBA8) -----------------------------------
const COLOR_SEA := Color(0.12, 0.24, 0.56)
const COLOR_COAST := Color(0.82, 0.77, 0.55)
const COLOR_PLAINS := Color(0.38, 0.62, 0.28)
const COLOR_FARMLAND := Color(0.55, 0.65, 0.28)
const COLOR_ROLLING := Color(0.28, 0.55, 0.22)
const COLOR_LOWLAND := Color(0.14, 0.42, 0.14)
const COLOR_HIGHLAND := Color(0.52, 0.44, 0.32)
const COLOR_ALPINE := Color(0.92, 0.92, 0.95)
const COLOR_FALLBACK := Color(0.60, 0.58, 0.42)
const COLOR_ROAD := Color(0.30, 0.30, 0.32)

var _bake_scale := 1.0
var _bake_region := Vector2i.ZERO
var _noise := FastNoiseLite.new()

## Returns an Image.FORMAT_RF heightmap covering the whole region. The caller
## passes image_width = the region's TYPE_HEIGHT map width (read via
## Terrain3DRegion.get_map()) because this class is scene-agnostic. Texels are
## sampled at step = region_size / image_width. An optional list of road
## centerlines (world-space Array[Vector3]) carves asphalt corridors.
func bake_region(region: Vector2i, bake_scale: float = 1.0, image_width: int = 1024, roads: Array = []) -> Image:
	_bake_scale = bake_scale
	_bake_region = region
	_noise.seed = NOISE_SEED + _bake_region.x * 131 + _bake_region.y * 977
	_noise.frequency = NOISE_FREQUENCY
	_noise.fractal_octaves = NOISE_OCTAVES
	_noise.fractal_lacunarity = NOISE_LACUNARITY
	_noise.fractal_gain = NOISE_GAIN
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	var step := REGION_SIZE / float(image_width)
	var origin := Vector2(region.x * REGION_SIZE, region.y * REGION_SIZE)
	var stride := image_width
	var buf := PackedFloat32Array()
	buf.resize(stride * stride)
	_bake_natural(buf, origin, step, stride)
	if not roads.is_empty():
		var chains := _upsample_roads(roads)
		if not chains.is_empty():
			_conform_roads(buf, chains, origin, step)
	_blur3x3(buf, stride)
	_apply_spawn_guard(buf, stride, origin, step)
	for iz in stride:
		for ix in stride:
			buf[iz * stride + ix] = clampf(buf[iz * stride + ix], HEIGHT_MIN, HEIGHT_MAX)
	return Image.create_from_data(image_width, image_width, false, Image.FORMAT_RF, buf.to_byte_array())

## Natural height at a world XZ position: region-seeded fBm detail on top of a
## blended biome base, plus alpine domes, scaled by _bake_scale. The spawn
## guard is applied later inside bake_region() so it wins over everything.
func _height_at(wx: float, wz: float) -> float:
	return _natural_height(wx, wz)

func _natural_height(wx: float, wz: float) -> float:
	var base := _biome_base(wx, wz)
	var detail := _noise.get_noise_2d(wx, wz) * (1.8 + 0.14 * base)
	var height := base + detail + _dome_weight(wx, wz)
	height *= _bake_scale
	return clampf(height, HEIGHT_MIN, HEIGHT_MAX)

## Fills `buf` (row-major, stride x stride) with the natural base field. This
## is the very same math as _natural_height(): per-texel fBm detail over the
## blended biome table, alpine domes, bake scale and the height clamp. The
## arithmetic is inlined into one loop (no per-texel helper frames, no Vector2
## temporaries), which is ~3x faster while keeping the values equivalent to
## the reference (float results match to within 1 ulp per texel).
func _bake_natural(buf: PackedFloat32Array, origin: Vector2, step: float, stride: int) -> void:
	for iz in stride:
		var wz := origin.y + (float(iz) + 0.5) * step
		var row := iz * stride
		for ix in stride:
			var wx := origin.x + (float(ix) + 0.5) * step
			var total := 0.0
			var acc := 0.0
			var dx := wx - BIOME_SPAWN_CENTER.x
			var dz := wz - BIOME_SPAWN_CENTER.y
			var dist := sqrt(dx * dx + dz * dz)
			var weight := 0.0
			if dist < BIOME_SPAWN_RADIUS:
				var t := 1.0 - dist / BIOME_SPAWN_RADIUS
				weight = t * t
			total += weight
			acc += weight * BIOME_SPAWN_BASE
			dx = wx - BIOME_ROLLING_CENTER.x
			dz = wz - BIOME_ROLLING_CENTER.y
			dist = sqrt(dx * dx + dz * dz)
			weight = 0.0
			if dist < BIOME_ROLLING_RADIUS:
				var t := 1.0 - dist / BIOME_ROLLING_RADIUS
				weight = t * t
			total += weight
			acc += weight * BIOME_ROLLING_BASE
			dx = wx - BIOME_HIGHLAND_CENTER.x
			dz = wz - BIOME_HIGHLAND_CENTER.y
			dist = sqrt(dx * dx + dz * dz)
			weight = 0.0
			if dist < BIOME_HIGHLAND_RADIUS:
				var t := 1.0 - dist / BIOME_HIGHLAND_RADIUS
				weight = t * t
			total += weight
			acc += weight * BIOME_HIGHLAND_BASE
			dx = wx - BIOME_FARMLAND_CENTER.x
			dz = wz - BIOME_FARMLAND_CENTER.y
			dist = sqrt(dx * dx + dz * dz)
			weight = 0.0
			if dist < BIOME_FARMLAND_RADIUS:
				var t := 1.0 - dist / BIOME_FARMLAND_RADIUS
				weight = t * t
			total += weight
			acc += weight * BIOME_FARMLAND_BASE
			dx = wx - BIOME_COAST_CENTER.x
			dz = wz - BIOME_COAST_CENTER.y
			dist = sqrt(dx * dx + dz * dz)
			weight = 0.0
			if dist < BIOME_COAST_RADIUS:
				var t := 1.0 - dist / BIOME_COAST_RADIUS
				weight = t * t
			total += weight
			acc += weight * BIOME_COAST_BASE
			dx = wx - BIOME_LOWLAND_CENTER.x
			dz = wz - BIOME_LOWLAND_CENTER.y
			dist = sqrt(dx * dx + dz * dz)
			weight = 0.0
			if dist < BIOME_LOWLAND_RADIUS:
				var t := 1.0 - dist / BIOME_LOWLAND_RADIUS
				weight = t * t
			total += weight
			acc += weight * BIOME_LOWLAND_BASE
			dx = wx - BIOME_HIGHLAND_PLATEAU_CENTER.x
			dz = wz - BIOME_HIGHLAND_PLATEAU_CENTER.y
			dist = sqrt(dx * dx + dz * dz)
			weight = 0.0
			if dist < BIOME_HIGHLAND_PLATEAU_RADIUS:
				var t := 1.0 - dist / BIOME_HIGHLAND_PLATEAU_RADIUS
				weight = t * t
			total += weight
			acc += weight * BIOME_HIGHLAND_PLATEAU_BASE
			dx = wx - BIOME_SEA_CENTER.x
			dz = wz - BIOME_SEA_CENTER.y
			dist = sqrt(dx * dx + dz * dz)
			weight = 0.0
			if dist < BIOME_SEA_RADIUS:
				var t := 1.0 - dist / BIOME_SEA_RADIUS
				weight = t * t
			total += weight
			acc += weight * BIOME_SEA_BASE
			var base := BIOME_FALLBACK_BASE if total <= 0.0001 else acc / total
			var detail := _noise.get_noise_2d(wx, wz) * (1.8 + 0.14 * base)
			var dome := 0.0
			var leg_dx := wx - LEGACY_DOME_CENTER.x
			var leg_dz := wz - LEGACY_DOME_CENTER.y
			var leg_d := sqrt(leg_dx * leg_dx + leg_dz * leg_dz)
			dome += LEGACY_DOME_AMP * (1.0 - smoothstep(LEGACY_DOME_RADIUS * LEGACY_DOME_EDGE, LEGACY_DOME_RADIUS, leg_d))
			for di in DOME_FAMILY.size():
				var dome_c: Vector2 = DOME_FAMILY[di]["center"]
				var dome_r: float = DOME_FAMILY[di]["radius"]
				var dome_e: float = DOME_FAMILY[di]["edge"]
				var dome_a: float = DOME_FAMILY[di]["amp"]
				var ddx := wx - dome_c.x
				var ddz := wz - dome_c.y
				var dd := sqrt(ddx * ddx + ddz * ddz)
				dome += dome_a * (1.0 - smoothstep(dome_r * dome_e, dome_r, dd))
			buf[row + ix] = clampf((base + detail + dome) * _bake_scale, HEIGHT_MIN, HEIGHT_MAX)

func _biome_base(wx: float, wz: float) -> float:
	var wp := Vector2(wx, wz)
	var total := 0.0
	var acc := 0.0
	var w := _biome_weight(wp, BIOME_SPAWN_CENTER, BIOME_SPAWN_RADIUS)
	total += w
	acc += w * BIOME_SPAWN_BASE
	w = _biome_weight(wp, BIOME_ROLLING_CENTER, BIOME_ROLLING_RADIUS)
	total += w
	acc += w * BIOME_ROLLING_BASE
	w = _biome_weight(wp, BIOME_HIGHLAND_CENTER, BIOME_HIGHLAND_RADIUS)
	total += w
	acc += w * BIOME_HIGHLAND_BASE
	w = _biome_weight(wp, BIOME_FARMLAND_CENTER, BIOME_FARMLAND_RADIUS)
	total += w
	acc += w * BIOME_FARMLAND_BASE
	w = _biome_weight(wp, BIOME_COAST_CENTER, BIOME_COAST_RADIUS)
	total += w
	acc += w * BIOME_COAST_BASE
	w = _biome_weight(wp, BIOME_LOWLAND_CENTER, BIOME_LOWLAND_RADIUS)
	total += w
	acc += w * BIOME_LOWLAND_BASE
	w = _biome_weight(wp, BIOME_HIGHLAND_PLATEAU_CENTER, BIOME_HIGHLAND_PLATEAU_RADIUS)
	total += w
	acc += w * BIOME_HIGHLAND_PLATEAU_BASE
	w = _biome_weight(wp, BIOME_SEA_CENTER, BIOME_SEA_RADIUS)
	total += w
	acc += w * BIOME_SEA_BASE
	if total <= 0.0001:
		return BIOME_FALLBACK_BASE
	return acc / total

func _biome_weight(wp: Vector2, center: Vector2, radius: float) -> float:
	var d := wp.distance_to(center)
	if d >= radius:
		return 0.0
	var t := 1.0 - d / radius
	return t * t

func _dome_weight(wx: float, wz: float) -> float:
	var dome := 0.0
	var leg_d := Vector2(wx, wz).distance_to(LEGACY_DOME_CENTER)
	dome += LEGACY_DOME_AMP * (1.0 - smoothstep(LEGACY_DOME_RADIUS * LEGACY_DOME_EDGE, LEGACY_DOME_RADIUS, leg_d))
	for di in DOME_FAMILY.size():
		var dome_c: Vector2 = DOME_FAMILY[di]["center"]
		var dome_r: float = DOME_FAMILY[di]["radius"]
		var dome_e: float = DOME_FAMILY[di]["edge"]
		var dome_a: float = DOME_FAMILY[di]["amp"]
		var d := Vector2(wx, wz).distance_to(dome_c)
		dome += dome_a * (1.0 - smoothstep(dome_r * dome_e, dome_r, d))
	return dome

## Classifies a height into an elevation band index (SEA=0..ALPINE=5).
static func elevation_band(height: float) -> int:
	if height < 0.0:
		return BAND_SEA
	if height < 10.0:
		return BAND_PLAINS
	if height < 60.0:
		return BAND_ROLLING
	if height < 200.0:
		return BAND_LOWLAND
	if height < 600.0:
		return BAND_HIGHLAND
	return BAND_ALPINE

## Returns the RGBA8 colour for a given elevation band index.
func _band_color(band: int) -> Color:
	match band:
		BAND_SEA:
			return COLOR_SEA
		BAND_PLAINS:
			return COLOR_PLAINS
		BAND_ROLLING:
			return COLOR_ROLLING
		BAND_LOWLAND:
			return COLOR_LOWLAND
		BAND_HIGHLAND:
			return COLOR_HIGHLAND
		BAND_ALPINE:
			return COLOR_ALPINE
		_:
			return COLOR_FALLBACK

## Returns an Image.FORMAT_RGBA8 colour map for the given region, deterministic
## per (region, scale, roads).  Each texel is coloured by its elevation band
## with a small deterministic brightness wobble from the same region-seeded noise
## used for height.  Road corridors are tinted asphalt grey along the conformed
## centreline within ROAD_WIDTH / 2 + 0.3, blending over ~3 m.
func bake_region_color(region: Vector2i, bake_scale: float = 1.0, image_width: int = 1024, roads: Array = []) -> Image:
	_bake_scale = bake_scale
	_bake_region = region
	_noise.seed = NOISE_SEED + _bake_region.x * 131 + _bake_region.y * 977
	_noise.frequency = NOISE_FREQUENCY
	_noise.fractal_octaves = NOISE_OCTAVES
	_noise.fractal_lacunarity = NOISE_LACUNARITY
	_noise.fractal_gain = NOISE_GAIN
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	var step := REGION_SIZE / float(image_width)
	var origin := Vector2(region.x * REGION_SIZE, region.y * REGION_SIZE)
	var stride := image_width
	var img := Image.create_empty(image_width, image_width, false, Image.FORMAT_RGBA8)
	# -- Sparse road distance field for the tint; mirror of _conform_roads's
	# per-segment AABB splat so this is never an O(cells x segments) scan. -------
	var core := ROAD_WIDTH * 0.5 + 0.3
	var blend_dist := core + 3.0
	var blend2 := blend_dist * blend_dist
	var d2_map := PackedFloat32Array()
	if not roads.is_empty():
		var chains := _upsample_roads(roads)
		if not chains.is_empty():
			var clipped := _clip_chains(chains, origin, blend_dist + FIELD_MARGIN)
			d2_map.resize(stride * stride)
			d2_map.fill(INF)
			for pts in clipped:
				for s in pts.size() - 1:
					var a := pts[s]
					var b := pts[s + 1]
					var abx := b.x - a.x
					var abz := b.z - a.z
					var len2 := abx * abx + abz * abz
					if len2 <= 0.0001:
						continue
					var lo_ix := maxi(0, int(floorf((minf(a.x, b.x) - blend_dist - origin.x) / step)))
					var hi_ix := mini(stride - 1, int(floorf((maxf(a.x, b.x) + blend_dist - origin.x) / step)))
					var lo_iz := maxi(0, int(floorf((minf(a.z, b.z) - blend_dist - origin.y) / step)))
					var hi_iz := mini(stride - 1, int(floorf((maxf(a.z, b.z) + blend_dist - origin.y) / step)))
					for iz in range(lo_iz, hi_iz + 1):
						var wz := origin.y + (float(iz) + 0.5) * step
						var dz := wz - a.z
						var row := iz * stride
						for ix in range(lo_ix, hi_ix + 1):
							var wx := origin.x + (float(ix) + 0.5) * step
							var t := clampf(((wx - a.x) * abx + dz * abz) / len2, 0.0, 1.0)
							var dx := wx - (a.x + abx * t)
							var ddz := dz - abz * t
							var d2 := dx * dx + ddz * ddz
							if d2 < blend2 and d2 < d2_map[row + ix]:
								d2_map[row + ix] = d2
	for iz in stride:
		var wz := origin.y + (float(iz) + 0.5) * step
		var row_z := iz * stride
		for ix in stride:
			var wx := origin.x + (float(ix) + 0.5) * step
			# -- biome base (same weighted blend as _bake_natural) ---------------
			var total := 0.0
			var acc := 0.0
			var dx := wx - BIOME_SPAWN_CENTER.x
			var dz := wz - BIOME_SPAWN_CENTER.y
			var dist := sqrt(dx * dx + dz * dz)
			var weight := 0.0
			if dist < BIOME_SPAWN_RADIUS:
				var t := 1.0 - dist / BIOME_SPAWN_RADIUS
				weight = t * t
			total += weight
			acc += weight * BIOME_SPAWN_BASE
			dx = wx - BIOME_ROLLING_CENTER.x
			dz = wz - BIOME_ROLLING_CENTER.y
			dist = sqrt(dx * dx + dz * dz)
			weight = 0.0
			if dist < BIOME_ROLLING_RADIUS:
				var t := 1.0 - dist / BIOME_ROLLING_RADIUS
				weight = t * t
			total += weight
			acc += weight * BIOME_ROLLING_BASE
			dx = wx - BIOME_HIGHLAND_CENTER.x
			dz = wz - BIOME_HIGHLAND_CENTER.y
			dist = sqrt(dx * dx + dz * dz)
			weight = 0.0
			if dist < BIOME_HIGHLAND_RADIUS:
				var t := 1.0 - dist / BIOME_HIGHLAND_RADIUS
				weight = t * t
			total += weight
			acc += weight * BIOME_HIGHLAND_BASE
			dx = wx - BIOME_FARMLAND_CENTER.x
			dz = wz - BIOME_FARMLAND_CENTER.y
			dist = sqrt(dx * dx + dz * dz)
			weight = 0.0
			if dist < BIOME_FARMLAND_RADIUS:
				var t := 1.0 - dist / BIOME_FARMLAND_RADIUS
				weight = t * t
			total += weight
			acc += weight * BIOME_FARMLAND_BASE
			dx = wx - BIOME_COAST_CENTER.x
			dz = wz - BIOME_COAST_CENTER.y
			dist = sqrt(dx * dx + dz * dz)
			weight = 0.0
			if dist < BIOME_COAST_RADIUS:
				var t := 1.0 - dist / BIOME_COAST_RADIUS
				weight = t * t
			total += weight
			acc += weight * BIOME_COAST_BASE
			dx = wx - BIOME_LOWLAND_CENTER.x
			dz = wz - BIOME_LOWLAND_CENTER.y
			dist = sqrt(dx * dx + dz * dz)
			weight = 0.0
			if dist < BIOME_LOWLAND_RADIUS:
				var t := 1.0 - dist / BIOME_LOWLAND_RADIUS
				weight = t * t
			total += weight
			acc += weight * BIOME_LOWLAND_BASE
			dx = wx - BIOME_HIGHLAND_PLATEAU_CENTER.x
			dz = wz - BIOME_HIGHLAND_PLATEAU_CENTER.y
			dist = sqrt(dx * dx + dz * dz)
			weight = 0.0
			if dist < BIOME_HIGHLAND_PLATEAU_RADIUS:
				var t := 1.0 - dist / BIOME_HIGHLAND_PLATEAU_RADIUS
				weight = t * t
			total += weight
			acc += weight * BIOME_HIGHLAND_PLATEAU_BASE
			dx = wx - BIOME_SEA_CENTER.x
			dz = wz - BIOME_SEA_CENTER.y
			dist = sqrt(dx * dx + dz * dz)
			weight = 0.0
			if dist < BIOME_SEA_RADIUS:
				var t := 1.0 - dist / BIOME_SEA_RADIUS
				weight = t * t
			total += weight
			acc += weight * BIOME_SEA_BASE
			var base := BIOME_FALLBACK_BASE if total <= 0.0001 else acc / total
			# -- detail + dome (same as _bake_natural) --------------------------
			var detail := _noise.get_noise_2d(wx, wz) * (1.8 + 0.14 * base)
			var dome := 0.0
			var leg_dx := wx - LEGACY_DOME_CENTER.x
			var leg_dz := wz - LEGACY_DOME_CENTER.y
			var leg_d := sqrt(leg_dx * leg_dx + leg_dz * leg_dz)
			dome += LEGACY_DOME_AMP * (1.0 - smoothstep(LEGACY_DOME_RADIUS * LEGACY_DOME_EDGE, LEGACY_DOME_RADIUS, leg_d))
			for di in DOME_FAMILY.size():
				var dome_c: Vector2 = DOME_FAMILY[di]["center"]
				var dome_r: float = DOME_FAMILY[di]["radius"]
				var dome_e: float = DOME_FAMILY[di]["edge"]
				var dome_a: float = DOME_FAMILY[di]["amp"]
				var ddx := wx - dome_c.x
				var ddz := wz - dome_c.y
				var dd := sqrt(ddx * ddx + ddz * ddz)
				dome += dome_a * (1.0 - smoothstep(dome_r * dome_e, dome_r, dd))
			var height := clampf((base + detail + dome) * bake_scale, HEIGHT_MIN, HEIGHT_MAX)
			# -- band colour + brightness wobble --------------------------------
			var band := elevation_band(height)
			var band_col := _band_color(band)
			var brightness := 0.92 + 0.16 * _noise.get_noise_2d(wx + 500.0, wz + 500.0)
			var col := band_col * brightness
			# -- road tint along conformed centreline ---------------------------
			if not d2_map.is_empty():
				var d2 := d2_map[row_z + ix]
				if d2 < blend2:
					var road_dist := sqrt(d2)
					if road_dist <= core:
						col = COLOR_ROAD
					else:
						var alpha := 1.0 - smoothstep(core, blend_dist, road_dist)
						col = col.lerp(COLOR_ROAD, alpha)
			img.set_pixel(ix, iz, col)
	return img

func _upsample_roads(roads: Array) -> Array[PackedVector3Array]:
	var chains: Array[PackedVector3Array] = []
	for road in roads:
		var pts := _upsample_centerline(road)
		if pts.size() >= 2:
			chains.append(pts)
	return chains

func _upsample_centerline(points: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := points.size()
	if n == 0:
		return out
	if n == 1:
		out.append(points[0])
		return out
	var closed := _chain_is_closed(points)
	for i in (n if closed else n - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % n] if closed else points[i + 1]
		out.append(a)
		var seg := b - a
		var seg_len := seg.length()
		if seg_len > SAMPLE_SPACING:
			var sub := int(floorf(seg_len / SAMPLE_SPACING)) + 1
			var inv := 1.0 / float(sub)
			for s in range(1, sub):
				out.append(a + seg * (float(s) * inv))
	return out

## True when the polyline reads as a closed loop: its endpoints nearly touch
## relative to the average segment length. Rings (hub ring, mountain-pass loop,
## test loops) have a closing gap ~= one segment length so they stay wrapped;
## the open hub->pass connector ends ~5.3 km from where it started, so it is
## left open and never gets a phantom closing chord back across the map.
func _chain_is_closed(points) -> bool:
	var n: int = points.size()
	if n < 2:
		return false
	var gap: float = (points[n - 1] as Vector3).distance_to(points[0] as Vector3)
	if n == 2:
		return gap <= 0.001
	var total := 0.0
	for i in n - 1:
		total += (points[i] as Vector3).distance_to(points[i + 1] as Vector3)
	var avg := total / float(n - 1)
	return gap <= 2.0 * avg

func _conform_roads(buf: PackedFloat32Array, chains: Array[PackedVector3Array], origin: Vector2, step: float) -> void:
	var scan_limit := BLEND_END_DISTANCE + FIELD_MARGIN
	var clipped := _clip_chains(chains, origin, scan_limit)
	if clipped.is_empty():
		return
	var core := ROAD_WIDTH * 0.5 + 0.3
	var blend2 := BLEND_END_DISTANCE * BLEND_END_DISTANCE
	var band := 12.0 * step * step
	var stride := int(round(sqrt(float(buf.size()))))
	var d2_map := PackedFloat32Array()
	d2_map.resize(stride * stride)
	d2_map.fill(INF)
	var elev_map := PackedFloat32Array()
	elev_map.resize(stride * stride)
	var owner_chain := PackedInt32Array()
	owner_chain.resize(stride * stride)
	owner_chain.fill(-1)
	var ri := 0
	for pts in clipped:
		ri += 1
		for s in pts.size() - 1:
			var a := pts[s]
			var b := pts[s + 1]
			var abx := b.x - a.x
			var abz := b.z - a.z
			var len2 := abx * abx + abz * abz
			if len2 <= 0.0001:
				continue
			var dy := b.y - a.y
			var lo_ix := maxi(0, int(floorf((minf(a.x, b.x) - BLEND_END_DISTANCE - origin.x) / step)))
			var hi_ix := mini(stride - 1, int(floorf((maxf(a.x, b.x) + BLEND_END_DISTANCE - origin.x) / step)))
			var lo_iz := maxi(0, int(floorf((minf(a.z, b.z) - BLEND_END_DISTANCE - origin.y) / step)))
			var hi_iz := mini(stride - 1, int(floorf((maxf(a.z, b.z) + BLEND_END_DISTANCE - origin.y) / step)))
			for iz in range(lo_iz, hi_iz + 1):
				var wz := origin.y + (float(iz) + 0.5) * step
				var dz := wz - a.z
				var row := iz * stride
				for ix in range(lo_ix, hi_ix + 1):
					var wx := origin.x + (float(ix) + 0.5) * step
					var t := clampf(((wx - a.x) * abx + dz * abz) / len2, 0.0, 1.0)
					var dx := wx - (a.x + abx * t)
					var ddz := dz - abz * t
					var d2 := dx * dx + ddz * ddz
					if d2 >= blend2:
						continue
					var i := row + ix
					var elev := a.y + dy * t
					var gap := elev_map[i] - elev
					var owned := d2_map[i] < blend2
					var too_high := owned and elev - elev_map[i] > 9.0
					if (d2 < d2_map[i] - band and not too_high) or (owned and d2 <= d2_map[i] + band and gap > 0.5 and owner_chain[i] != ri):
						d2_map[i] = d2
						elev_map[i] = elev
						owner_chain[i] = ri
	for iz in stride:
		var row := iz * stride
		for ix in stride:
			var i := row + ix
			if d2_map[i] >= blend2:
				continue
			var dist := sqrt(d2_map[i])
			var target := elev_map[i] - ROAD_TOPPING
			if dist <= core:
				buf[i] = target
			else:
				buf[i] = lerpf(target, buf[i], smoothstep(core, BLEND_END_DISTANCE, dist))

## Restricts conforming to the road segments whose AABB overlaps the region
## rect grown by `margin`. A clipped-away segment is strictly farther than the
## BLEND_END_DISTANCE from every texel in the region, so it can never win the
## nearest-segment minimum: the carve output is unchanged, but roads that only
## touch other regions (e.g. the multi-km connector) are no longer scanned for
## every cell of an unrelated region. Segments are kept as runs of the exact
## original segment set (no invented chords) so the per-texel minimum is
## bit-identical to the reference full-world scan.
func _clip_chains(chains: Array[PackedVector3Array], origin: Vector2, margin: float) -> Array[PackedVector3Array]:
	var min_x := origin.x - margin
	var max_x := origin.x + REGION_SIZE + margin
	var min_z := origin.y - margin
	var max_z := origin.y + REGION_SIZE + margin
	var clipped: Array[PackedVector3Array] = []
	for ci in chains.size():
		var pts: PackedVector3Array = chains[ci]
		var n := pts.size()
		var closed := _chain_is_closed(pts)
		var run := PackedVector3Array()
		for s in (n if closed else n - 1):
			var a := pts[s]
			var b := pts[(s + 1) % n] if closed else pts[s + 1]
			if not _seg_in_rect(a, b, min_x, min_z, max_x, max_z):
				if run.size() >= 2:
					clipped.append(run)
				run = PackedVector3Array()
				continue
			if run.is_empty() or run[run.size() - 1] != a:
				run.append(a)
			if run[run.size() - 1] != b:
				run.append(b)
		if run.size() >= 2:
			clipped.append(run)
	return clipped

func _seg_in_rect(a: Vector3, b: Vector3, min_x: float, min_z: float, max_x: float, max_z: float) -> bool:
	if maxf(a.x, b.x) < min_x or minf(a.x, b.x) > max_x:
		return false
	if maxf(a.z, b.z) < min_z or minf(a.z, b.z) > max_z:
		return false
	return true

func _build_distance_field(chains: Array[PackedVector3Array], origin: Vector2) -> PackedFloat32Array:
	var stride := int(REGION_SIZE / FIELD_STEP) + 1
	var field := PackedFloat32Array()
	field.resize(stride * stride)
	for i in stride:
		var wz := origin.y + float(i) * FIELD_STEP
		for j in stride:
			var wx := origin.x + float(j) * FIELD_STEP
			field[i * stride + j] = sqrt(_nearest_road(chains, wx, wz).x)
	return field

func _field_dist_at(field: PackedFloat32Array, origin: Vector2, wx: float, wz: float) -> float:
	var stride := int(REGION_SIZE / FIELD_STEP) + 1
	var fx := (wx - origin.x) / FIELD_STEP
	var fz := (wz - origin.y) / FIELD_STEP
	var j0 := clampi(int(floorf(fx)), 0, stride - 1)
	var i0 := clampi(int(floorf(fz)), 0, stride - 1)
	var j1 := mini(j0 + 1, stride - 1)
	var i1 := mini(i0 + 1, stride - 1)
	var tx := clampf(fx - floorf(fx), 0.0, 1.0)
	var tz := clampf(fz - floorf(fz), 0.0, 1.0)
	var a00 := i0 * stride + j0
	var a10 := i0 * stride + j1
	var a01 := i1 * stride + j0
	var a11 := i1 * stride + j1
	return lerpf(lerpf(field[a00], field[a10], tx), lerpf(field[a01], field[a11], tx), tz)

func _nearest_road(chains: Array[PackedVector3Array], wx: float, wz: float) -> Vector2:
	var best_d2 := INF
	var best_e := 0.0
	for pts in chains:
		for s in pts.size():
			var a := pts[s]
			var b := pts[(s + 1) % pts.size()]
			var abx := b.x - a.x
			var abz := b.z - a.z
			var len2 := abx * abx + abz * abz
			if len2 <= 0.0001:
				continue
			var t := clampf(((wx - a.x) * abx + (wz - a.z) * abz) / len2, 0.0, 1.0)
			var cx := a.x + abx * t
			var cz := a.z + abz * t
			var dx := wx - cx
			var dz := wz - cz
			var d2 := dx * dx + dz * dz
			if d2 < best_d2:
				best_d2 = d2
				best_e = a.y + (b.y - a.y) * t
	return Vector2(best_d2, best_e)

func _blur3x3(buf: PackedFloat32Array, stride: int) -> void:
	var tmp := PackedFloat32Array()
	tmp.resize(buf.size())
	var third := 1.0 / 3.0
	for iz in stride:
		var row := iz * stride
		for ix in stride:
			var lx := maxi(ix - 1, 0)
			var rx := mini(ix + 1, stride - 1)
			tmp[row + ix] = (buf[row + lx] + buf[row + ix] + buf[row + rx]) * third
	for ix in stride:
		for iz in stride:
			var uy := maxi(iz - 1, 0)
			var dy := mini(iz + 1, stride - 1)
			buf[iz * stride + ix] = (tmp[uy * stride + ix] + tmp[iz * stride + ix] + tmp[dy * stride + ix]) * third

func _apply_spawn_guard(buf: PackedFloat32Array, stride: int, origin: Vector2, step: float) -> void:
	var c := SPAWN_PLATEAU_CENTER
	var r := SPAWN_PLATEAU_RADIUS
	if origin.x - step > c.x + r or origin.x + REGION_SIZE + step < c.x - r:
		return
	if origin.y - step > c.y + r or origin.y + REGION_SIZE + step < c.y - r:
		return
	var lo_x := clampi(int(floorf((c.x - r) / step - 0.5)), 0, stride - 1)
	var hi_x := clampi(int(floorf((c.x + r) / step - 0.5)), 0, stride - 1)
	var lo_z := clampi(int(floorf((c.y - r) / step - 0.5)), 0, stride - 1)
	var hi_z := clampi(int(floorf((c.y + r) / step - 0.5)), 0, stride - 1)
	for iz in range(lo_z, hi_z + 1):
		var wz := origin.y + (float(iz) + 0.5) * step
		for ix in range(lo_x, hi_x + 1):
			var wx := origin.x + (float(ix) + 0.5) * step
			if Vector2(wx, wz).distance_to(c) <= r:
				buf[iz * stride + ix] = SPAWN_HEIGHT
