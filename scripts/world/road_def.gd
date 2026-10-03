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

## Per-side rail mask. A bit field rather than two booleans so it stays additive:
## RIGHT | LEFT == BOTH, i.e. every corridor authored before this field existed
## keeps both rails, and a corridor only has to state the ONE side it drops.
## Sides are in the road's own TRAVEL order (centreline index 0 -> last): RIGHT
## is the +cross side TrackBuilder builds first (`forward x UP`), LEFT the other.
enum RailSide {
	NONE = 0,
	RIGHT = 1,
	LEFT = 2,
	BOTH = 3,
}

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
## Which rail sides this road carries. Defaults to BOTH, so the tier table alone
## decides rails as it always did; a merge lane that must stay open on ONE side
## (an on-ramp running parallel to the road it merges onto) masks that side out
## and keeps the field side. See RailSide.
@export var rail_sides: int = RailSide.BOTH
@export var points: Array[Vector3] = []

## Chain-index ranges over which ONE rail side is suppressed, as
## {"from": int, "to": int, "side": int} with an inclusive range and a RailSide
## bit. Empty means "the road-wide rail_sides decides everything", which is every
## road authored before this field existed.
##
## This exists because a single road-wide mask cannot describe an on-ramp that
## runs alongside the carriageway it merges onto. The highway-facing side is not
## constant along such a ramp: on the approach the carriageway lies to one side
## and on the merge lane it lies to the OTHER, because the ramp wraps the ring in
## the opposite sense. Measured on spawn-highway-ramp (MASTER_SEED) the ring is on
## the ramp's LEFT for the 271-point approach and on its RIGHT for the rest, which
## runs from the taper through the landing. A static mask therefore either walls
## off the approach (the defect this fixes) or walls off the landing. Suppressing
## per index keeps the field-side rail everywhere while opening whichever side
## actually faces the carriageway.
##
## Ranges are half-open [from, to] over chain indices and are clamped, so a range
## naming an index outside the chain is inert rather than an error. An empty
## array means "no suppression" and is the default for every non-ramp road.
@export var rail_open_ranges: Array[Dictionary] = []

## Factory: tier defaults applied, explicit width/surface/banking override.
## rail_sides defaults to BOTH so every existing caller is unchanged.
static func make(tier: int, points: Array[Vector3], id: String = "", closed: bool = true, \
		width_override: float = -1.0, surface_override: int = -1, \
		rail_sides_override: int = RailSide.BOTH) -> RoadDef:
	var def := RoadDef.new()
	def.tier = tier
	def.id = id
	def.closed = closed
	def.width = width_override if width_override > 0.0 else default_width(tier)
	def.surface = surface_override if surface_override >= 0 else default_surface(tier)
	def.rail_sides = rail_sides_override
	def.points = points
	return def

## The player-facing name for this road: `name` when it has one, else the id,
## else a last-resort literal. NEVER empty -- a consumer drawing this string
## (the pause map's road labels) must never have to special-case a blank, and a
## road with no curated name should read as its slug rather than vanish.
func display_name() -> String:
	if not name.is_empty():
		return name
	if not id.is_empty():
		return id
	return "Unnamed Road"

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

## The rail-side mask THIS road actually builds, with the two vetoes applied:
## a non-rail tier contributes nothing, a merge point contributes nothing, and a
## partial mask contributes exactly the sides it names. This is the single value
## TrackBuilder reads, so "no rails at all" and "one rail" never need two code
## paths -- 0 and a one-bit mask are both just "skip these slots".
func rail_sides_mask() -> int:
	if not rails_enabled():
		return RailSide.NONE
	return rail_sides

func rail_on_right() -> bool:
	return (rail_sides_mask() & RailSide.RIGHT) != 0

func rail_on_left() -> bool:
	return (rail_sides_mask() & RailSide.LEFT) != 0

## How many rail meshes/colliders this road carries: 0, 1 or 2. Junction rail
## gaps are chain positions shared by both sides (TrackBuilder cuts each built
## rail at the same indices), so masking a side removes rail geometry without
## renumbering anything the caller passed in.
func rail_side_count() -> int:
	var mask := rail_sides_mask()
	return int(bool(mask & RailSide.RIGHT)) + int(bool(mask & RailSide.LEFT))

## The chain-index ranges that suppress `side` (a RailSide bit), clamped to this
## road's point count. Returns [] when the side is never suppressed, which is the
## common case and keeps TrackBuilder on its existing no-op path.
func rail_open_ranges_for(side: int) -> Array:
	var out: Array = []
	var last := points.size() - 1
	if last < 0:
		return out
	for r in rail_open_ranges:
		if int(r.get("side", 0)) != side:
			continue
		var from := clampi(int(r.get("from", 0)), 0, last)
		var to := clampi(int(r.get("to", 0)), 0, last)
		if to < from:
			var swap := from
			from = to
			to = swap
		out.append([from, to])
	return out

## The rail-side mask actually in force at chain index `i`: the road-wide mask
## minus every side suppressed by rail_open_ranges at that index. Answers "is
## there a rail here" for a caller that cares about one spot (tests, diagnostics)
## without having to re-derive the ranges.
func rail_sides_mask_at(i: int) -> int:
	var mask := rail_sides_mask()
	for r in rail_open_ranges_for(RailSide.RIGHT):
		if i >= int(r[0]) and i <= int(r[1]):
			mask &= ~RailSide.RIGHT
	for r in rail_open_ranges_for(RailSide.LEFT):
		if i >= int(r[0]) and i <= int(r[1]):
			mask &= ~RailSide.LEFT
	return mask

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