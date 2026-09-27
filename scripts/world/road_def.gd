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
const LANE_COUNT_BY_MIN_WIDTH := {
	24.0: 4,
	15.0: 2,
}
const ROADS_WITH_RAILS := {
	Tier.HIGHWAY: true,
	Tier.ARTERIAL: true,
	Tier.TOUGE: true,
	Tier.COASTAL: false,
	Tier.DIRT: false,
}

## Merge-point policy: ramps and connectors that start at or land on other roads
## intentionally disable rails at the merge so the merge side stays open. Specific
## merge points (e.g. the hub-access ramp leaving the spawn basin at
## (128, -0.1, 81.8) and landing on the hub ring's north point (128, 2.2, 18))
## are treated the same way; the receiving road only has its rail cleared at the
## merge zone rather than both sides.
static func is_merge_point(id: String) -> bool:
	return id == "hub-access-ramp"

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
			return 24.0
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

static func lane_count_for(width: float) -> int:
	var lanes := 1
	if width >= 24.0:
		lanes = int(LANE_COUNT_BY_MIN_WIDTH[24.0])
	elif width >= 15.0:
		lanes = int(LANE_COUNT_BY_MIN_WIDTH[15.0])
	return clampi(lanes, 1, 6)

static func lanes_for(width: float) -> int:
	return lane_count_for(width)

func lane_count() -> int:
	return lane_count_for(width)

static func has_rails(tier: int) -> bool:
	return bool(ROADS_WITH_RAILS.get(tier, false))

## Whether this road carries rails at all: the tier table AND the merge-point
## veto. A merge point emits no rail meshes, which is what keeps the merge side
## of the junction open. Consumers that need the UN-GATED answer (is this a rail
## TIER road, so does it take part in junction rail gaps at all?) ask
## has_rails(tier) instead - RoadNetwork.recompute_rails does exactly that for
## the other side of a junction, so a merge point still makes the receiving road
## clear its rail.
func rails_enabled() -> bool:
	return has_rails(tier) and not is_merge_point(id)

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