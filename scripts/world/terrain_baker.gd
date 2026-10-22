# scripts/world/terrain_baker.gd
class_name TerrainBaker
extends RefCounted

## Pure heightfield math for Terrain3D regions: no scene tree access, so the
## whole class is headless-unit-testable and deterministic. bake_region() runs
## the passes in order: deterministic natural heightfield (region-seeded fBm
## over a blended biome elevation table plus alpine domes), the spawn-plateau
## guard, optional road-corridor conforming via a per-texel segment-splat min,
## a 3x3 separable blur, then the final height clamp. bake_region_color()
## produces a matching FORMAT_RGBA8 colour map by reusing the same biome/dome
## math and painting per-elevation-band colours plus road-surface tints.

const REGION_SIZE := 256.0

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
## Terrain3D MULTIPLIES the colour map into the textured albedo (and reads its
## alpha as a roughness offset, 0.5 = neutral), so since the ground is textured
## (TerrainTexturing) the colour map is a near-white per-band tint with a
## brightness wobble, not a paint colour. A saturated green here would turn
## every texture layer dark green.
const COLOR_GROUND_TINT := Color(0.97, 0.97, 0.95, 0.5)
const COLOR_ROAD := Color(0.78, 0.78, 0.78, 0.5)

## Band index -> RGBA8 colour, indexed by BAND_* so the colour loop never pays
## a per-texel _band_color() match call. Order must match BAND_SEA..BAND_ALPINE.
const BAND_COLORS := [
	Color(0.98, 0.96, 0.92, 0.5),
	COLOR_GROUND_TINT,
	COLOR_GROUND_TINT,
	Color(0.95, 0.97, 0.94, 0.5),
	Color(0.93, 0.95, 0.94, 0.5),
	Color(0.95, 0.96, 1.0, 0.5),
]

# -- Ground texture control map (Terrain3D TYPE_CONTROL) ----------------------
## Layer weights per texel come from classify_ground(); the two strongest
## layers become the texel's base/overlay pair. Noise is evaluated in WORLD
## space with fixed seeds (unlike the per-region-seeded height detail), so
## texture patches run continuously across region borders.
const CTRL_PATCH_SEED := 4242
const CTRL_PATCH_FREQUENCY := 0.006  # ~170 m meadow / forest-floor patches
const CTRL_DETAIL_SEED := 777
const CTRL_DETAIL_FREQUENCY := 0.035  # ~30 m dirt spots, snowline wobble
const CTRL_SHOULDER_WIDTH := 2.5  # gravel band beyond the road edge (m)
const CTRL_FRINGE_WIDTH := 4.0  # dirt fringe beyond the gravel (m)
const CTRL_ROCK_SLOPE_START := 0.6  # tan(31 deg): rock starts showing
const CTRL_ROCK_SLOPE_FULL := 1.0  # tan(45 deg): bare rock
const CTRL_SNOWLINE := 850.0
const CTRL_LOW_TOP := 180.0  # lowland grass gives way to highland forest
const CTRL_HIGH_TOP := 320.0
const CTRL_ALPINE_START := 620.0
const CTRL_ALPINE_FULL := 820.0
const CTRL_FOREST_LOW := 60.0  # forest floor begins to mix into lowland grass

var _bake_scale := 1.0
var _bake_region := Vector2i.ZERO
var _noise := FastNoiseLite.new()
var _ctrl_patch := FastNoiseLite.new()
var _ctrl_detail := FastNoiseLite.new()

## Returns an Image.FORMAT_RF heightmap covering the whole region. The caller
## passes image_width = the region's TYPE_HEIGHT map width (read via
## Terrain3DRegion.get_map()) because this class is scene-agnostic. Texels are
## sampled at step = region_size / image_width. An optional list of road
## centerlines (world-space Array[Vector3]) carves asphalt corridors.
func bake_region(region: Vector2i, bake_scale: float = 1.0, image_width: int = 1024, roads: Array = []) -> Image:
	_bake_scale = bake_scale
	_bake_region = region
	_configure_noise(_bake_region)
	var step := REGION_SIZE / float(image_width)
	var origin := Vector2(region.x * REGION_SIZE, region.y * REGION_SIZE)
	var stride := image_width
	var K := clampi(int(floorf(float(stride) / 32.0)), 1, 4)
	var cs := ceili(float(stride) / float(K))
	var coarse := PackedFloat32Array()
	coarse.resize(cs * cs)
	_fill_coarse_natural(coarse, origin, step, K, cs)
	var buf := PackedFloat32Array()
	buf.resize(stride * stride)
	_bilinear_upsample(coarse, buf, K, cs, stride)
	_apply_spawn_guard(buf, stride, origin, step)
	if not roads.is_empty():
		var chains := _raw_road_chains(roads)
		if not chains.is_empty():
			_conform_roads(buf, chains, origin, step)
	_blur3x3(buf, stride)
	for iz in stride:
		for ix in stride:
			buf[iz * stride + ix] = clampf(buf[iz * stride + ix], HEIGHT_MIN, HEIGHT_MAX)
	return Image.create_from_data(image_width, image_width, false, Image.FORMAT_RF, buf.to_byte_array())

## Natural height at a world XZ position: region-seeded fBm detail on top of a
## blended biome base, plus alpine domes, scaled by _bake_scale. Neither the
## spawn plateau nor road conforming is applied here -- both are bake_region()
## passes, so an off-ring sample reads raw natural relief.
func _height_at(wx: float, wz: float) -> float:
	return _natural_height(wx, wz)

func _natural_height(wx: float, wz: float) -> float:
	var base := _biome_base(wx, wz)
	var detail := _noise.get_noise_2d(wx, wz) * (1.8 + 0.14 * base)
	var height := base + detail + _dome_weight(wx, wz)
	height *= _bake_scale
	return clampf(height, HEIGHT_MIN, HEIGHT_MAX)

## Seeds the region-cell noise frame the natural field is evaluated in. Shared
## by bake_region() / bake_region_color() / natural_height_at() so the ring
## bake and any full-world preload sample the identical per-256m-cell field.
func _configure_noise(loc: Vector2i) -> void:
	_noise.seed = NOISE_SEED + loc.x * 131 + loc.y * 977
	_noise.frequency = NOISE_FREQUENCY
	_noise.fractal_octaves = NOISE_OCTAVES
	_noise.fractal_lacunarity = NOISE_LACUNARITY
	_noise.fractal_gain = NOISE_GAIN
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM

## Deterministic natural height at any world XZ: reseeds the noise to the
## containing 256m cell and evaluates the same field bake_region() bakes (biome
## table + domes + fBm detail + clamp), so an off-ring world point reads the
## relief it WILL stream instead of 0.0. Side-effect free: _bake_scale and the
## noise state are saved/restored, leaving bake_region() outputs untouched.
func natural_height_at(wx: float, wz: float, bake_scale: float = 1.0) -> float:
	var prev_scale := _bake_scale
	_bake_scale = bake_scale
	_configure_noise(Vector2i(floori(wx / REGION_SIZE), floori(wz / REGION_SIZE)))
	var h := _natural_height(wx, wz)
	_bake_scale = prev_scale
	return h

## Full-world height Image (FORMAT_RF) over [world_min, world_max), each texel
## a natural_height_at() sample at its cell centre. Pure and deterministic;
## preloads the pause-map relief across the whole driveable world ahead of any
## region streaming. Does not conform roads or apply the spawn guard (the map
## only renders the natural relief), and never touches bake_region() outputs.
func bake_full_height_image(world_min: Vector2, world_max: Vector2, width: int = 256, height: int = 256, bake_scale: float = 1.0) -> Image:
	var w := maxi(width, 1)
	var h := maxi(height, 1)
	var span := Vector2(maxf(world_max.x - world_min.x, 0.001), maxf(world_max.y - world_min.y, 0.001))
	var step_x := span.x / float(w)
	var step_y := span.y / float(h)
	var buf := PackedFloat32Array()
	buf.resize(w * h)
	for iy in h:
		var wz := world_min.y + (float(iy) + 0.5) * step_y
		var row := iy * w
		for ix in w:
			var wx := world_min.x + (float(ix) + 0.5) * step_x
			buf[row + ix] = natural_height_at(wx, wz, bake_scale)
	return Image.create_from_data(w, h, false, Image.FORMAT_RF, buf.to_byte_array())

func _fill_coarse_natural(out: PackedFloat32Array, origin: Vector2, step: float, K: int, cs: int) -> void:
	var cell := step * float(K)
	for ci in cs:
		var wz := origin.y + (float(ci) + 0.5) * cell
		var row := ci * cs
		for cj in cs:
			var wx := origin.x + (float(cj) + 0.5) * cell
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
			out[row + cj] = clampf((base + detail + dome) * _bake_scale, HEIGHT_MIN, HEIGHT_MAX)

func _bilinear_upsample(coarse: PackedFloat32Array, fine: PackedFloat32Array, K: int, cs: int, stride: int) -> void:
	var invK := 1.0 / float(K)
	var xs := PackedInt32Array()
	xs.resize(stride * 2)
	var xt := PackedFloat32Array()
	xt.resize(stride)
	for ix in stride:
		var fx := (float(ix) + 0.5) * invK - 0.5
		var x0 := maxi(int(floorf(fx)), 0)
		var x1 := mini(x0 + 1, cs - 1)
		xs[ix * 2] = x0
		xs[ix * 2 + 1] = x1
		xt[ix] = clampf(fx - float(x0), 0.0, 1.0)
	for iz in stride:
		var gz := (float(iz) + 0.5) * invK - 0.5
		var y0 := maxi(int(floorf(gz)), 0)
		var y1 := mini(y0 + 1, cs - 1)
		var ty := clampf(gz - float(y0), 0.0, 1.0)
		var yrow0 := y0 * cs
		var yrow1 := y1 * cs
		var frow := iz * stride
		for ix in stride:
			var x0 := xs[ix * 2]
			var x1 := xs[ix * 2 + 1]
			var tx := xt[ix]
			var a := coarse[yrow0 + x0]
			var b := coarse[yrow0 + x1]
			var c := coarse[yrow1 + x0]
			var d := coarse[yrow1 + x1]
			fine[frow + ix] = lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)

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
	return BAND_COLORS[clampi(band, 0, BAND_COLORS.size() - 1)]

## Returns an Image.FORMAT_RGBA8 colour map for the given region, deterministic
## per (region, scale, roads).  Each texel is coloured by its elevation band
## (a near-white tint, see COLOR_GROUND_TINT) with a small deterministic
## brightness wobble from world-space noise, continuous across regions.  Road corridors are tinted asphalt grey along the conformed
## centreline within ROAD_WIDTH / 2 + 0.3, blending over ~3 m.
func bake_region_color(region: Vector2i, bake_scale: float = 1.0, image_width: int = 1024, roads: Array = []) -> Image:
	_bake_scale = bake_scale
	_bake_region = region
	_configure_noise(_bake_region)
	_configure_control_noise()
	var step := REGION_SIZE / float(image_width)
	var origin := Vector2(region.x * REGION_SIZE, region.y * REGION_SIZE)
	var stride := image_width
	var K := clampi(int(floorf(float(stride) / 32.0)), 1, 4)
	var cs := ceili(float(stride) / float(K))
	var cell := step * float(K)
	var coarse_h := PackedFloat32Array()
	coarse_h.resize(cs * cs)
	var coarse_br := PackedFloat32Array()
	coarse_br.resize(cs * cs)
	for ci in cs:
		var wz := origin.y + (float(ci) + 0.5) * cell
		var row := ci * cs
		for cj in cs:
			var wx := origin.x + (float(cj) + 0.5) * cell
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
			coarse_h[row + cj] = clampf((base + detail + dome) * bake_scale, HEIGHT_MIN, HEIGHT_MAX)
			# World-space (fixed-seed) brightness: the per-region-seeded height
			# noise stepped at every 256 m border, which showed as tinted squares
			# once the colour map started multiplying real textures.
			coarse_br[row + cj] = _ctrl_patch.get_noise_2d(wx * 2.3 + 911.0, wz * 2.3 - 377.0)
	var h_buf := PackedFloat32Array()
	h_buf.resize(stride * stride)
	_bilinear_upsample(coarse_h, h_buf, K, cs, stride)
	var br_buf := PackedFloat32Array()
	br_buf.resize(stride * stride)
	_bilinear_upsample(coarse_br, br_buf, K, cs, stride)
	var img := Image.create_empty(image_width, image_width, false, Image.FORMAT_RGBA8)
	var core := ROAD_WIDTH * 0.5 + 0.3
	var blend_dist := core + 3.0
	var blend2 := blend_dist * blend_dist
	var d2_map := PackedFloat32Array()
	if not roads.is_empty():
		var chains := _raw_road_chains(roads)
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
	var bytes := PackedByteArray()
	bytes.resize(stride * stride * 4)
	for iz in stride:
		var wz := origin.y + (float(iz) + 0.5) * step
		var row_z := iz * stride
		var row_b := row_z * 4
		for ix in stride:
			var wx := origin.x + (float(ix) + 0.5) * step
			var height := clampf(h_buf[row_z + ix], HEIGHT_MIN, HEIGHT_MAX)
			var band := elevation_band(height)
			var band_col: Color = BAND_COLORS[band]
			var brightness := 0.92 + 0.16 * br_buf[row_z + ix]
			var col := band_col * brightness
			if not d2_map.is_empty():
				var d2 := d2_map[row_z + ix]
				if d2 < blend2:
					var road_dist := sqrt(d2)
					if road_dist <= core:
						col = COLOR_ROAD
					else:
						var alpha := 1.0 - smoothstep(core, blend_dist, road_dist)
						col = col.lerp(COLOR_ROAD, alpha)
			var o := row_b + ix * 4
			# Clamped: the near-white tint times a >1 brightness wobble would
			# otherwise wrap past 255 into dark speckles.
			bytes[o] = clampi(int(col.r * 255.0), 0, 255)
			bytes[o + 1] = clampi(int(col.g * 255.0), 0, 255)
			bytes[o + 2] = clampi(int(col.b * 255.0), 0, 255)
			bytes[o + 3] = clampi(int(col.a * 255.0), 0, 255)
	return Image.create_from_data(image_width, image_width, false, Image.FORMAT_RGBA8, bytes)

## Returns the Terrain3D TYPE_CONTROL map (FORMAT_RF holding raw uint32 control
## bits, see TerrainTexturing.encode_control) for a region: per texel the two
## strongest ground layers from classify_ground() and their blend. Inputs are
## the region's final baked heights (pass the bake_region() image to skip a
## second height bake), the slope derived from them, world-space patch/detail
## noise, the coast/sea biome weight and the distance past the nearest road
## edge (road_widths[i] is road i's carriageway width; ROAD_WIDTH when absent).
## Pure and deterministic, safe on the seeder's worker thread.
func bake_region_control(region: Vector2i, bake_scale: float = 1.0, image_width: int = 1024, roads: Array = [], height_image: Image = null, road_widths: PackedFloat32Array = PackedFloat32Array()) -> Image:
	var stride := image_width
	var step := REGION_SIZE / float(stride)
	var origin := Vector2(region.x * REGION_SIZE, region.y * REGION_SIZE)
	var h_img := height_image
	if h_img == null or h_img.get_width() != stride or h_img.get_format() != Image.FORMAT_RF:
		h_img = bake_region(region, bake_scale, image_width, roads)
	var heights := h_img.get_data().to_float32_array()
	_configure_control_noise()
	var K := clampi(int(floorf(float(stride) / 32.0)), 1, 4)
	var cs := ceili(float(stride) / float(K))
	var cell := step * float(K)
	var coarse_patch := PackedFloat32Array()
	coarse_patch.resize(cs * cs)
	var coarse_detail := PackedFloat32Array()
	coarse_detail.resize(cs * cs)
	var coarse_coast := PackedFloat32Array()
	coarse_coast.resize(cs * cs)
	var any_coast := false
	for ci in cs:
		var wz := origin.y + (float(ci) + 0.5) * cell
		for cj in cs:
			var wx := origin.x + (float(cj) + 0.5) * cell
			coarse_patch[ci * cs + cj] = _ctrl_patch.get_noise_2d(wx, wz)
			coarse_detail[ci * cs + cj] = _ctrl_detail.get_noise_2d(wx, wz)
			var cw := coast_weight(wx, wz)
			coarse_coast[ci * cs + cj] = cw
			any_coast = any_coast or cw > 0.0
	var patch := PackedFloat32Array()
	patch.resize(stride * stride)
	_bilinear_upsample(coarse_patch, patch, K, cs, stride)
	var detail := PackedFloat32Array()
	detail.resize(stride * stride)
	_bilinear_upsample(coarse_detail, detail, K, cs, stride)
	# Most regions are nowhere near the coast: skip that upsample entirely.
	var coast := PackedFloat32Array()
	if any_coast:
		coast.resize(stride * stride)
		_bilinear_upsample(coarse_coast, coast, K, cs, stride)
	var edge := _road_edge_field(roads, road_widths, origin, step, stride, CTRL_SHOULDER_WIDTH + CTRL_FRINGE_WIDTH)
	var has_edge := not edge.is_empty()
	var bytes := PackedByteArray()
	bytes.resize(stride * stride * 4)
	var band := CTRL_SHOULDER_WIDTH + CTRL_FRINGE_WIDTH
	# Nature (patch ~170 m, detail ~30 m, slope) does not need 1 m precision and
	# Terrain3D blends neighbouring texels anyway, so away from roads one
	# classification covers a 2x2 block; blocks touching the road shoulder band
	# are classified per texel so the gravel edge stays 1 m sharp. ~3x cheaper.
	for bz in range(0, stride, 2):
		var bz1 := mini(bz + 1, stride - 1)
		for bx in range(0, stride, 2):
			var bx1 := mini(bx + 1, stride - 1)
			var i00 := bz * stride + bx
			var i01 := bz * stride + bx1
			var i10 := bz1 * stride + bx
			var i11 := bz1 * stride + bx1
			if has_edge and minf(minf(edge[i00], edge[i01]), minf(edge[i10], edge[i11])) < band:
				bytes.encode_u32(i00 * 4, _control_texel(heights, stride, step, bx, bz, patch, detail, coast, edge))
				if i01 != i00:
					bytes.encode_u32(i01 * 4, _control_texel(heights, stride, step, bx1, bz, patch, detail, coast, edge))
				if i10 != i00:
					bytes.encode_u32(i10 * 4, _control_texel(heights, stride, step, bx, bz1, patch, detail, coast, edge))
				if i11 != i01 and i11 != i10:
					bytes.encode_u32(i11 * 4, _control_texel(heights, stride, step, bx1, bz1, patch, detail, coast, edge))
				continue
			var bits := _control_texel(heights, stride, step, bx, bz, patch, detail, coast, edge)
			bytes.encode_u32(i00 * 4, bits)
			bytes.encode_u32(i01 * 4, bits)
			bytes.encode_u32(i10 * 4, bits)
			bytes.encode_u32(i11 * 4, bits)
	return Image.create_from_data(stride, stride, false, Image.FORMAT_RF, bytes)

## Control bits of texel (ix, iz): slope from central differences of the baked
## heights, then classify_ground. coast / edge may be empty (no coast nearby,
## no road in reach).
func _control_texel(heights: PackedFloat32Array, stride: int, step: float, ix: int, iz: int, patch: PackedFloat32Array, detail: PackedFloat32Array, coast: PackedFloat32Array, edge: PackedFloat32Array) -> int:
	var last := stride - 1
	var xm := maxi(ix - 1, 0)
	var xp := mini(ix + 1, last)
	var zm := maxi(iz - 1, 0)
	var zp := mini(iz + 1, last)
	var row := iz * stride
	var gx := (heights[row + xp] - heights[row + xm]) / (float(maxi(xp - xm, 1)) * step)
	var gz := (heights[zp * stride + ix] - heights[zm * stride + ix]) / (float(maxi(zp - zm, 1)) * step)
	var i := row + ix
	var road_edge := edge[i] if not edge.is_empty() else INF
	var coast_w := coast[i] if not coast.is_empty() else 0.0
	return classify_ground(heights[i], sqrt(gx * gx + gz * gz), patch[i], detail[i], coast_w, road_edge)

## Ground layer choice for one texel, returned as packed control bits. height
## in metres, slope as rise/run (tan), patch/detail world noise in [-1, 1],
## coast in [0, 1] (coast_weight), road_edge = metres past the nearest road's
## edge (negative under the road, INF with no road nearby). Every layer gets a
## weight; the strongest is the base, the runner-up the overlay, and the blend
## is the runner-up's share, so two neighbouring texels that swap ranks meet
## at 0.5 and the transition stays continuous.
static func classify_ground(height: float, slope: float, patch: float, detail: float, coast: float, road_edge: float) -> int:
	# Scalar weights, and every smoothstep is skipped when its input is outside
	# the ramp (this runs 65k times per region on the bake worker; GDScript call
	# overhead dominates, so a typical lowland texel costs ~2 ramps, not ~12).
	var alpine := 0.0
	if height > CTRL_ALPINE_START:
		alpine = 1.0 if height >= CTRL_ALPINE_FULL else smoothstep(CTRL_ALPINE_START, CTRL_ALPINE_FULL, height)
	var high := 0.0
	if height > CTRL_LOW_TOP:
		high = 1.0 if height >= CTRL_HIGH_TOP else smoothstep(CTRL_LOW_TOP, CTRL_HIGH_TOP, height)
	var low := 1.0 - high
	high *= 1.0 - alpine
	var w_grass := 0.0
	var w_meadow := 0.0
	var w_forest := 0.0
	var w_dirt := 0.0
	if low > 0.0:
		var meadow_share := smoothstep(-0.15, 0.45, patch)
		var forest_low := 0.0
		if height > CTRL_FOREST_LOW and patch < 0.1:
			forest_low = smoothstep(CTRL_FOREST_LOW, CTRL_LOW_TOP, height) * smoothstep(0.1, -0.5, patch)
		w_grass = low * (1.0 - meadow_share) * (1.0 - forest_low)
		w_meadow = low * meadow_share
		w_forest = low * (1.0 - meadow_share) * forest_low
		if detail > 0.6:
			w_dirt = low * smoothstep(0.6, 0.95, detail) * 0.75
	if high > 0.0:
		var high_meadow := smoothstep(0.0, 0.6, patch)
		w_meadow += high * high_meadow
		w_forest += high * (1.0 - high_meadow)
	var w_rock := 0.0
	var w_snow := 0.0
	if alpine > 0.0:
		var snowline := CTRL_SNOWLINE + detail * 90.0
		var snow := smoothstep(snowline - 70.0, snowline + 70.0, height)
		w_rock = alpine * (1.0 - snow)
		w_snow = alpine * snow
	# Beaches: only near the coast/sea biomes and near sea level, so a low
	# inland dip (the spawn plains sit at ~2 m) never turns to sand.
	var sand := 0.0
	if coast > 0.0 and height < 8.0:
		sand = coast * smoothstep(8.0, 3.0, height)
	# Steep faces are bare rock whatever the biome; snow and sand slide off.
	var steep := 0.0
	if slope > CTRL_ROCK_SLOPE_START:
		steep = 1.0 if slope >= CTRL_ROCK_SLOPE_FULL else smoothstep(CTRL_ROCK_SLOPE_START, CTRL_ROCK_SLOPE_FULL, slope)
	var w_sand := 0.0
	if sand > 0.0 or steep > 0.0:
		var keep := 1.0 - maxf(sand, steep)
		w_grass *= keep
		w_meadow *= keep
		w_forest *= keep
		w_dirt *= keep
		w_rock = w_rock * keep + steep
		w_snow *= keep
		w_sand = sand * (1.0 - steep)
	var w_gravel := 0.0
	# Road shoulders: a gravel band past the edge, then a dirt fringe.
	if road_edge < CTRL_SHOULDER_WIDTH + CTRL_FRINGE_WIDTH:
		var gravel := 1.0 - smoothstep(CTRL_SHOULDER_WIDTH * 0.6, CTRL_SHOULDER_WIDTH, road_edge)
		var fringe := (1.0 - gravel) * (1.0 - smoothstep(CTRL_SHOULDER_WIDTH, CTRL_SHOULDER_WIDTH + CTRL_FRINGE_WIDTH, road_edge))
		var nature := 1.0 - maxf(gravel, fringe * 0.45)
		w_grass *= nature
		w_meadow *= nature
		w_forest *= nature
		w_rock *= nature
		w_snow *= nature
		w_sand *= nature
		w_dirt = w_dirt * nature + fringe * 0.45
		w_gravel = gravel
	# Inline top-2 in fixed id order with strict comparisons, so ties keep the
	# lower id (deterministic). b = best, s = runner-up.
	var b_id := TerrainTexturing.ID_GRASS
	var b_w := w_grass
	var s_id := TerrainTexturing.ID_GRASS
	var s_w := -1.0
	if w_meadow > s_w:
		if w_meadow > b_w:
			s_id = b_id; s_w = b_w; b_id = TerrainTexturing.ID_MEADOW; b_w = w_meadow
		else:
			s_id = TerrainTexturing.ID_MEADOW; s_w = w_meadow
	if w_dirt > s_w:
		if w_dirt > b_w:
			s_id = b_id; s_w = b_w; b_id = TerrainTexturing.ID_DIRT; b_w = w_dirt
		else:
			s_id = TerrainTexturing.ID_DIRT; s_w = w_dirt
	if w_rock > s_w:
		if w_rock > b_w:
			s_id = b_id; s_w = b_w; b_id = TerrainTexturing.ID_ROCK; b_w = w_rock
		else:
			s_id = TerrainTexturing.ID_ROCK; s_w = w_rock
	if w_sand > s_w:
		if w_sand > b_w:
			s_id = b_id; s_w = b_w; b_id = TerrainTexturing.ID_SAND; b_w = w_sand
		else:
			s_id = TerrainTexturing.ID_SAND; s_w = w_sand
	if w_snow > s_w:
		if w_snow > b_w:
			s_id = b_id; s_w = b_w; b_id = TerrainTexturing.ID_SNOW; b_w = w_snow
		else:
			s_id = TerrainTexturing.ID_SNOW; s_w = w_snow
	if w_gravel > s_w:
		if w_gravel > b_w:
			s_id = b_id; s_w = b_w; b_id = TerrainTexturing.ID_GRAVEL; b_w = w_gravel
		else:
			s_id = TerrainTexturing.ID_GRAVEL; s_w = w_gravel
	if w_forest > s_w:
		if w_forest > b_w:
			s_id = b_id; s_w = b_w; b_id = TerrainTexturing.ID_FOREST; b_w = w_forest
		else:
			s_id = TerrainTexturing.ID_FOREST; s_w = w_forest
	var total := b_w + maxf(s_w, 0.0)
	if total <= 0.000001:
		return TerrainTexturing.encode_control(TerrainTexturing.ID_GRASS, TerrainTexturing.ID_GRASS, 0.0)
	return TerrainTexturing.encode_control(b_id, s_id, maxf(s_w, 0.0) / total)

## Coast/sea biome weight at a world XZ: 1 in the middle of the coast or sea
## biome, fading to 0 at its radius. Pure.
static func coast_weight(wx: float, wz: float) -> float:
	var dc := Vector2(wx, wz).distance_to(BIOME_COAST_CENTER)
	var ds := Vector2(wx, wz).distance_to(BIOME_SEA_CENTER)
	var c := 1.0 - smoothstep(BIOME_COAST_RADIUS * 0.55, BIOME_COAST_RADIUS, dc)
	var s := 1.0 - smoothstep(BIOME_SEA_RADIUS * 0.7, BIOME_SEA_RADIUS, ds)
	return maxf(c, s)

func _configure_control_noise() -> void:
	_ctrl_patch.seed = CTRL_PATCH_SEED
	_ctrl_patch.frequency = CTRL_PATCH_FREQUENCY
	_ctrl_patch.fractal_type = FastNoiseLite.FRACTAL_FBM
	_ctrl_patch.fractal_octaves = 3
	_ctrl_detail.seed = CTRL_DETAIL_SEED
	_ctrl_detail.frequency = CTRL_DETAIL_FREQUENCY
	_ctrl_detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	_ctrl_detail.fractal_octaves = 2

## Per-texel metres past the nearest road EDGE (centreline distance minus that
## road's half width), INF beyond `reach` past every edge. Empty when there are
## no roads. Each road's segments are only scanned over their own clipped AABB.
func _road_edge_field(roads: Array, road_widths: PackedFloat32Array, origin: Vector2, step: float, stride: int, reach: float) -> PackedFloat32Array:
	var field := PackedFloat32Array()
	if roads.is_empty():
		return field
	field.resize(stride * stride)
	field.fill(INF)
	var max_x := origin.x + REGION_SIZE
	var max_z := origin.y + REGION_SIZE
	for ci in roads.size():
		var road: Array = roads[ci]
		if road.size() < 2:
			continue
		var half := (road_widths[ci] if ci < road_widths.size() else ROAD_WIDTH) * 0.5
		var lim := half + reach
		var pts := PackedVector3Array(road)
		if _chain_is_closed(pts):
			pts.append(pts[0])
		for s in pts.size() - 1:
			var a := pts[s]
			var b := pts[s + 1]
			if not _seg_in_rect(a, b, origin.x - lim, origin.y - lim, max_x + lim, max_z + lim):
				continue
			var abx := b.x - a.x
			var abz := b.z - a.z
			var len2 := abx * abx + abz * abz
			if len2 <= 0.0001:
				continue
			var lo_ix := maxi(0, int(floorf((minf(a.x, b.x) - lim - origin.x) / step)))
			var hi_ix := mini(stride - 1, int(floorf((maxf(a.x, b.x) + lim - origin.x) / step)))
			var lo_iz := maxi(0, int(floorf((minf(a.z, b.z) - lim - origin.y) / step)))
			var hi_iz := mini(stride - 1, int(floorf((maxf(a.z, b.z) + lim - origin.y) / step)))
			for iz in range(lo_iz, hi_iz + 1):
				var wz := origin.y + (float(iz) + 0.5) * step
				var dz := wz - a.z
				var row := iz * stride
				for ix in range(lo_ix, hi_ix + 1):
					var wx := origin.x + (float(ix) + 0.5) * step
					var t := clampf(((wx - a.x) * abx + dz * abz) / len2, 0.0, 1.0)
					var ex := wx - (a.x + abx * t)
					var ez := dz - abz * t
					var e := sqrt(ex * ex + ez * ez) - half
					if e < field[row + ix]:
						field[row + ix] = e
	return field

func _upsample_roads(roads: Array) -> Array[PackedVector3Array]:
	var chains: Array[PackedVector3Array] = []
	for road in roads:
		var pts := _upsample_centerline(road)
		if pts.size() >= 2:
			chains.append(pts)
	return chains

## Same chain set as _upsample_roads but WITHOUT the 2 m point resampling:
## the raw control points (plus the closing point for closed chains) produce
## the IDENTICAL distance field, because upsampling only inserts collinear
## points along existing segments. Conforming against the sparse chains is
## therefore pixel-exact while scanning ~10-100x fewer per-segment AABBs.
func _raw_road_chains(roads: Array) -> Array[PackedVector3Array]:
	var chains: Array[PackedVector3Array] = []
	for road in roads:
		if road.size() < 2:
			continue
		var pts := PackedVector3Array(road)
		if _chain_is_closed(pts):
			pts.append(pts[0])
		chains.append(pts)
	return chains

func _upsample_centerline(points: Array[Vector3]) -> PackedVector3Array:
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
			var len := sqrt(len2)
			var blend_cap := BLEND_END_DISTANCE * len
			var row_lo := minf(a.x, b.x) - BLEND_END_DISTANCE
			var row_hi := maxf(a.x, b.x) + BLEND_END_DISTANCE
			for iz in range(lo_iz, hi_iz + 1):
				var wz := origin.y + (float(iz) + 0.5) * step
				var dz := wz - a.z
				var row := iz * stride
				var c_lo := row_lo
				var c_hi := row_hi
				if absf(abz) > 1.0e-6:
					var k0 := abx * dz + abz * a.x
					var s0 := (k0 - blend_cap) / abz
					var s1 := (k0 + blend_cap) / abz
					var s_lo := minf(s0, s1)
					var s_hi := maxf(s0, s1)
					var f_lo: float
					var f_hi: float
					if absf(abx) > 1.0e-6:
						var q0 := (a.x * abx - dz * abz) / abx
						var q1 := q0 + len2 / abx
						f_lo = minf(q0, q1)
						f_hi = maxf(q0, q1)
					else:
						if dz * abz < 0.0 or dz * abz > len2:
							f_lo = 1.0
							f_hi = 0.0
						else:
							f_lo = -INF
							f_hi = INF
					var a_lo := maxf(s_lo, f_lo)
					var a_hi := minf(s_hi, f_hi)
					if a_lo <= a_hi:
						c_lo = minf(c_lo, a_lo)
						c_hi = maxf(c_hi, a_hi)
				var dz2 := dz * dz
				if dz2 <= blend2:
					var r := sqrt(blend2 - dz2)
					c_lo = minf(c_lo, a.x - r)
					c_hi = maxf(c_hi, a.x + r)
				var dzb := wz - b.z
				var dzb2 := dzb * dzb
				if dzb2 <= blend2:
					var r := sqrt(blend2 - dzb2)
					c_lo = minf(c_lo, b.x - r)
					c_hi = maxf(c_hi, b.x + r)
				var margin := 1.0 * step + 0.1
				var s_lo := maxi(lo_ix, int(floorf((c_lo - margin - origin.x) / step)))
				var s_hi := mini(hi_ix, int(floorf((c_hi + margin - origin.x) / step)) + 1)
				for ix in range(s_lo, s_hi + 1):
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

## Flattens the spawn disc (SPAWN_PLATEAU_CENTER, SPAWN_PLATEAU_RADIUS) to
## SPAWN_HEIGHT so the car always starts on level ground. Runs BEFORE road
## conforming: a road centreline is a drivable surface, the plateau is only a
## pad, so a corridor that terminates inside the disc is still carved to its own
## height instead of being buried under (or floating above) the flat pad. The
## pad stays flat everywhere else, and the following blur softens the carve
## edges into it.
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
