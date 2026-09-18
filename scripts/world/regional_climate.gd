# scripts/world/regional_climate.gd
class_name RegionalClimate
extends RefCounted

## Deterministic regional weather sampler for the open world (P4). Avoids the
## cranky enum/int `as` casts in the non-polling path by returning plain ints
## and letting WeatherManager cast. Sampling is purely a function of
## (region, hour-of-day, season) so the universe stays reproducible across
## runs; the alpine grip floor and seasonal pass closure are derived here so
## WeatherManager stays a thin transport.

enum Season { WINTER, SPRING, SUMMER, FALL }

const SEASON_COUNT := 4
const SEASON_WEEKS := 52
const SEASON_LENGTH_WEEKS := 13

## Per-season snowline (metres of elevation below which snow never sticks).
## Indexed by Season. WINTER/SPRING/SUMMER/FALL.
const SNOWLINE: Array[float] = [150.0, 300.0, 500.0, 250.0]

## Alpine all-weather grip multiplier per season: even on a dry alpine day the
## surface is harder than the global ROAD_GRIP.SNOW floor allows elsewhere.
const ALPINE_GRIP: Array[float] = [0.30, 0.38, 0.45, 0.34]

## Weather weight tables per profile per season. Keys are
## WeatherManager.Weather values so the sampler only ever hands back a valid
## transport id.
const PROFILE_PLAINS: Dictionary = {
	Season.WINTER: {WeatherManager.Weather.CLEAR: 0.45, WeatherManager.Weather.CLOUDY: 0.35, WeatherManager.Weather.STORM: 0.20},
	Season.SPRING: {WeatherManager.Weather.CLEAR: 0.45, WeatherManager.Weather.CLOUDY: 0.35, WeatherManager.Weather.STORM: 0.20},
	Season.SUMMER: {WeatherManager.Weather.CLEAR: 0.45, WeatherManager.Weather.CLOUDY: 0.35, WeatherManager.Weather.STORM: 0.20},
	Season.FALL: {WeatherManager.Weather.CLEAR: 0.45, WeatherManager.Weather.CLOUDY: 0.35, WeatherManager.Weather.STORM: 0.20},
}

const PROFILE_COASTAL: Dictionary = {
	Season.WINTER: {WeatherManager.Weather.RAIN: 0.45, WeatherManager.Weather.STORM: 0.25, WeatherManager.Weather.CLOUDY: 0.20, WeatherManager.Weather.CLEAR: 0.10},
	Season.SPRING: {WeatherManager.Weather.RAIN: 0.40, WeatherManager.Weather.STORM: 0.25, WeatherManager.Weather.CLOUDY: 0.20, WeatherManager.Weather.CLEAR: 0.15},
	Season.SUMMER: {WeatherManager.Weather.RAIN: 0.30, WeatherManager.Weather.STORM: 0.20, WeatherManager.Weather.CLOUDY: 0.25, WeatherManager.Weather.CLEAR: 0.25},
	Season.FALL: {WeatherManager.Weather.RAIN: 0.45, WeatherManager.Weather.STORM: 0.25, WeatherManager.Weather.CLOUDY: 0.20, WeatherManager.Weather.CLEAR: 0.10},
}

const PROFILE_LOWLAND: Dictionary = {
	Season.WINTER: {WeatherManager.Weather.FOG: 0.30, WeatherManager.Weather.CLOUDY: 0.30, WeatherManager.Weather.RAIN: 0.25, WeatherManager.Weather.CLEAR: 0.15},
	Season.SPRING: {WeatherManager.Weather.FOG: 0.20, WeatherManager.Weather.CLOUDY: 0.30, WeatherManager.Weather.RAIN: 0.30, WeatherManager.Weather.CLEAR: 0.20},
	Season.SUMMER: {WeatherManager.Weather.CLEAR: 0.30, WeatherManager.Weather.CLOUDY: 0.30, WeatherManager.Weather.RAIN: 0.25, WeatherManager.Weather.FOG: 0.15},
	Season.FALL: {WeatherManager.Weather.FOG: 0.25, WeatherManager.Weather.CLOUDY: 0.30, WeatherManager.Weather.RAIN: 0.25, WeatherManager.Weather.CLEAR: 0.20},
}

const PROFILE_HIGHLAND: Dictionary = {
	Season.WINTER: {WeatherManager.Weather.SNOW: 0.40, WeatherManager.Weather.STORM: 0.30, WeatherManager.Weather.CLOUDY: 0.30},
	Season.SPRING: {WeatherManager.Weather.SNOW: 0.25, WeatherManager.Weather.RAIN: 0.25, WeatherManager.Weather.CLOUDY: 0.25, WeatherManager.Weather.CLEAR: 0.25},
	Season.SUMMER: {WeatherManager.Weather.CLEAR: 0.30, WeatherManager.Weather.CLOUDY: 0.30, WeatherManager.Weather.RAIN: 0.25, WeatherManager.Weather.STORM: 0.15},
	Season.FALL: {WeatherManager.Weather.SNOW: 0.30, WeatherManager.Weather.STORM: 0.25, WeatherManager.Weather.RAIN: 0.25, WeatherManager.Weather.CLOUDY: 0.20},
}

const PROFILE_ALPINE: Dictionary = {
	Season.WINTER: {WeatherManager.Weather.SNOW: 1.0},
	Season.SPRING: {WeatherManager.Weather.SNOW: 1.0},
	Season.SUMMER: {WeatherManager.Weather.SNOW: 1.0},
	Season.FALL: {WeatherManager.Weather.SNOW: 1.0},
}

const PROFILES: Dictionary = {
	"plains": PROFILE_PLAINS,
	"coastal": PROFILE_COASTAL,
	"lowland": PROFILE_LOWLAND,
	"highland": PROFILE_HIGHLAND,
	"alpine": PROFILE_ALPINE,
}

# -- Elevation/band mirror of TerrainBaker (const copy, no fBm detail so the
# -- classifier stays cheap and fully deterministic per region).

const REGION_SIZE := 1024.0
const BIOME_FALLBACK_BASE := 1.0
const HEIGHT_MIN := -8.0
const HEIGHT_MAX := 2000.0

const BIOMES := [
	{"center": Vector2(128.0, 128.0), "base": 2.0, "radius": 1500.0},
	{"center": Vector2(2048.0, 2048.0), "base": 18.0, "radius": 2000.0},
	{"center": Vector2(3584.0, 2816.0), "base": 35.0, "radius": 2600.0},
	{"center": Vector2(2048.0, 400.0), "base": 6.0, "radius": 1600.0},
	{"center": Vector2(8200.0, -1800.0), "base": 2.5, "radius": 1800.0},
	{"center": Vector2(4600.0, 4700.0), "base": 90.0, "radius": 2200.0},
	{"center": Vector2(6800.0, 6400.0), "base": 260.0, "radius": 2600.0},
	{"center": Vector2(8200.0, -3400.0), "base": -6.0, "radius": 2600.0},
]

const DOMES := [
	{"center": Vector2(5632.0, 5632.0), "radius": 5000.0, "edge": 0.35, "amp": 42.0},
	{"center": Vector2(7800.0, 6400.0), "radius": 3200.0, "edge": 0.5, "amp": 1100.0},
	{"center": Vector2(6400.0, 7800.0), "radius": 2800.0, "edge": 0.5, "amp": 850.0},
	{"center": Vector2(7000.0, 3000.0), "radius": 1800.0, "edge": 0.5, "amp": 150.0},
]

## Rotates the 52-week year through WINTER/SPRING/SUMMER/FALL (13 weeks each).
static func season_for_week(week: int) -> Season:
	var w := posmod(week, SEASON_WEEKS)
	return int(w / SEASON_LENGTH_WEEKS) as Season

## Deterministic uniform float in [0,1) from any int seed.
static func _hash01(v: int) -> float:
	var x := v & 0x7FFFFFFF
	x = (x ^ (x >> 16)) * 0x45D9F3B
	x = (x ^ (x >> 13)) & 0x7FFFFFFF
	x = (x * 0x9E3779B1) & 0x7FFFFFFF
	x = x ^ (x >> 16)
	return float(x) / float(0x7FFFFFFF)

static func _biome_weight(pos: Vector2, center: Vector2, radius: float) -> float:
	var d := pos.distance_to(center)
	if d >= radius:
		return 0.0
	var t := 1.0 - d / radius
	return t * t

## Same weighted blend as TerrainBaker._biome_base (minus fBm detail).
static func _biome_base(wx: float, wz: float) -> float:
	var wp := Vector2(wx, wz)
	var total := 0.0
	var acc := 0.0
	for biome in BIOMES:
		var w := _biome_weight(wp, biome["center"] as Vector2, biome["radius"] as float)
		total += w
		acc += w * (biome["base"] as float)
	if total <= 0.0001:
		return BIOME_FALLBACK_BASE
	return acc / total

## Same dome family as TerrainBaker._dome_weight.
static func _dome_weight(wx: float, wz: float) -> float:
	var wp := Vector2(wx, wz)
	var total := 0.0
	for dome in DOMES:
		var center: Vector2 = dome["center"]
		var radius: float = dome["radius"]
		var edge: float = dome["edge"]
		var amp: float = dome["amp"]
		total += amp * (1.0 - smoothstep(radius * edge, radius, wp.distance_to(center)))
	return total

static func _approx_height(wx: float, wz: float) -> float:
	return clampf(_biome_base(wx, wz) + _dome_weight(wx, wz), HEIGHT_MIN, HEIGHT_MAX)

## Elevation band at a world XZ position (0=SEA .. 5=ALPINE), from the baked
## terrain's natural heightfield without the fBm detail term.
static func region_band(pos: Vector2) -> int:
	return TerrainBaker.elevation_band(_approx_height(pos.x, pos.y))

static func _region_hash(pos: Vector2) -> int:
	var rx := int(floorf(pos.x / REGION_SIZE))
	var rz := int(floorf(pos.y / REGION_SIZE))
	return 1337 + rx * 131 + rz * 977

static func _profile_for(pos: Vector2, band: int) -> String:
	if band >= TerrainBaker.BAND_ALPINE:
		return "alpine"
	if band >= TerrainBaker.BAND_HIGHLAND:
		return "highland"
	if band >= TerrainBaker.BAND_LOWLAND:
		return "lowland"
	if band == TerrainBaker.BAND_SEA:
		return "coastal"
	if _dominant_biome_is_water(pos):
		return "coastal"
	return "plains"

## The coastal profile applies wherever the nearest biome blend is dominated by
## coast or sea centres (band alone is not enough: the sea terrace is flat).
static func _dominant_biome_is_water(pos: Vector2) -> bool:
	var best_weight := 0.0
	var best_index := -1
	for i in BIOMES.size():
		var w := _biome_weight(pos, BIOMES[i]["center"] as Vector2, BIOMES[i]["radius"] as float)
		if w > best_weight:
			best_weight = w
			best_index = i
	return best_index == 4 or best_index == 7  # coast / sea

static func _pick_weather(weights: Dictionary, seed: int) -> int:
	var roll := _hash01(seed)
	var acc := 0.0
	for key in weights:
		var wk: int = key
		var weight: float = weights[key]
		acc += weight
		if roll < acc:
			return wk
	var first: int = weights.keys()[0]
	return first

## Deterministic regional sample. `time_of_day` is the 0-24h clock value
## (fractional hours allowed); `season` is a RegionalClimate.Season.
## Returns weather (WeatherManager.Weather id), snowline (m), grip_mod
## (1.0 except alpine), pass_locked (seasonal mountain-pass closure) and the
## elevation band the sample came from.
func sample(pos: Vector2, time_of_day: float, season: int) -> Dictionary:
	var band := region_band(pos)
	var profile_name := _profile_for(pos, band)
	var weights: Dictionary = PROFILES[profile_name][season]
	var hour_slot := posmod(int(floorf(time_of_day)), 24)
	var seed := posmod(_region_hash(pos) * 31337 + hour_slot * 977, 0x7FFFFFFF)
	var weather := _pick_weather(weights, seed)
	var snowline: float = SNOWLINE[season]
	var grip_mod := 1.0
	if band >= TerrainBaker.BAND_ALPINE:
		grip_mod = ALPINE_GRIP[season]
	var pass_locked := season == Season.WINTER and band >= TerrainBaker.BAND_HIGHLAND
	return {
		"weather": weather,
		"snowline": snowline,
		"grip_mod": grip_mod,
		"pass_locked": pass_locked,
		"band": band,
	}