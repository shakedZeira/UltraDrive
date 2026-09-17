# scripts/world/road_def.gd
class_name RoadDef
extends Resource

## Pure-data description of one road in the open-world network: identity,
## classification tier, geometry and surface. RoadNetwork builds topology from
## these; TrackBuilder renders them. Points are world-space centerline points;
## road_id used by the graph APIs is the 0-based index into RoadNetwork's
## def list (RoadDef.id is human-authoring metadata only).

enum Tier {
	HIGHWAY = 0,
	ARTERIAL = 1,
	TOUGE = 2,
	COASTAL = 3,
	DIRT = 4,
}

enum Surface {
	ASPHALT = 0,
	CONCRETE = 1,
	GRAVEL = 2,
	SNOW = 3,
}

const TIER_COUNT := 5
const SURFACE_COUNT := 4

@export var id: String = ""
@export var tier: int = Tier.ARTERIAL
@export var name: String = ""
@export var width: float = 10.0
@export var closed: bool = true
@export var surface: int = Surface.ASPHALT
## Max superelevation (cross-slope) cap in metres of bank per metre of
## half-width; 0 keeps the strip flat. Banking direction is derived from
## curvature by TrackBuilder.
@export var banking: float = 0.0
@export var points: Array[Vector3] = []

## Factory: tier defaults applied, explicit width/surface/banking override.
static func make(tier: int, points: Array[Vector3], id: String = "", closed: bool = true, \
		width_override: float = -1.0, surface_override: int = -1) -> RoadDef:
	var def := RoadDef.new()
	def.tier = tier
	def.id = id
	def.closed = closed
	def.width = width_override if width_override > 0.0 else default_width(tier)
	def.surface = surface_override if surface_override >= 0 else default_surface(tier)
	def.points = points
	return def

## Default width in world metres per tier.
static func default_width(t: int) -> float:
	match t:
		Tier.HIGHWAY:
			return 16.0
		Tier.ARTERIAL:
			return 10.0
		Tier.TOUGE:
			return 9.0
		Tier.COASTAL:
			return 9.0
		Tier.DIRT:
			return 7.0
		_:
			return 10.0

## Default surface per tier.
static func default_surface(t: int) -> int:
	match t:
		Tier.DIRT:
			return Surface.GRAVEL
		_:
			return Surface.ASPHALT

## Human-readable display name for a tier.
static func tier_name(t: int) -> String:
	match t:
		Tier.HIGHWAY:
			return "Highway"
		Tier.ARTERIAL:
			return "Arterial"
		Tier.TOUGE:
			return "Touge"
		Tier.COASTAL:
			return "Coastal"
		Tier.DIRT:
			return "Dirt"
		_:
			return "Arterial"

## Surface display name + the TrackBuilder albedo hint lives in TrackBuilder;
## this only names the surface for debug/HUD use.
static func surface_name(s: int) -> String:
	match s:
		Surface.ASPHALT:
			return "Asphalt"
		Surface.CONCRETE:
			return "Concrete"
		Surface.GRAVEL:
			return "Gravel"
		Surface.SNOW:
			return "Snow"
		_:
			return "Asphalt"