class_name SurfaceRegistry
extends RefCounted

## Pure surface-grip table and deterministic biome-to-surface classifier.
## Headless-safe: no scene tree access, no raycasts.

# --- Surface keys (used as dictionary keys in SURFACE_GRIP) ---
const ASPHALT: String = "ASPHALT"
const GRAVEL: String = "GRAVEL"
const DIRT: String = "DIRT"
const MUD: String = "MUD"
const GRASS: String = "GRASS"
const SNOW: String = "SNOW"
const SAND: String = "SAND"

const SURFACE_COUNT: int = 7

# --- Biome band constants (matches TerrainBaker band indices) ---
const BAND_SEA: int = 0
const BAND_PLAINS: int = 1
const BAND_ROLLING: int = 2
const BAND_LOWLAND: int = 3
const BAND_HIGHLAND: int = 4
const BAND_ALPINE: int = 5

const ROAD_TOPPING: float = 6.0
const ROAD_EDGE_MARGIN: float = 2.5

# --- Grip table: { surface_key: { lateral: float, longitudinal: float } } ---
# Tuned per FH6-inspired impact table (§3.5 fh6_map.md).
const SURFACE_GRIP: Dictionary = {
	ASPHALT:  { "lateral": 1.0,  "longitudinal": 1.0 },
	GRAVEL:   { "lateral": 0.85, "longitudinal": 0.80 },
	SAND:     { "lateral": 0.82, "longitudinal": 0.76 },
	DIRT:     { "lateral": 0.80, "longitudinal": 0.75 },
	GRASS:    { "lateral": 0.65, "longitudinal": 0.60 },
	MUD:      { "lateral": 0.50, "longitudinal": 0.45 },
	SNOW:     { "lateral": 0.35, "longitudinal": 0.30 },
}

# --- Default tier-to-surface mapping (when position is road-close) ---
const TIER_SURFACE: Dictionary = {
	0: ASPHALT,   # HIGHWAY
	1: ASPHALT,   # ARTERIAL
	2: ASPHALT,   # TOUGE
	3: ASPHALT,   # COASTAL
	4: GRAVEL,    # DIRT
}

# --- Mixed-surface roads (RoadDef.point_surfaces) ---------------------------
# A road with a per-point surface profile reports the surface of the segment a
# car is on. RoadDef.Surface -> surface key; CONCRETE grips like asphalt.
const ROAD_SURFACE_KEYS: Dictionary = {
	0: ASPHALT,   # RoadDef.Surface.ASPHALT
	1: ASPHALT,   # RoadDef.Surface.CONCRETE
	2: GRAVEL,    # RoadDef.Surface.GRAVEL (the dirt contract: 0.85 / 0.80)
	3: SNOW,      # RoadDef.Surface.SNOW
}
# The per-segment surface applies across the carriageway plus this margin
# (a wheel on the painted edge is still on the road). Between there and the
# road-close topping the TIER surface applies -- the loose verge (GRAVEL for a
# DIRT-tier road) -- and beyond it the off-road rule.
const PAVED_EDGE_MARGIN: float = 0.5

# Zone registry for track-specific surface overrides (e.g. Le Mans gravel traps)
#
# PARALLEL TYPED ARRAYS instead of an Array[Dictionary]: the classifier runs
# every physics frame, per wheel, so the old hot path paid a Dictionary hash
# lookup per zone AND allocated a fresh `PackedVector2Array()` on every zone
# it visited (the eager default argument of `Dictionary.get`). `_zone_rects`
# caches each polygon's XZ bounding box at add time, so a point that is
# nowhere near a zone costs one Rect2 test instead of a full polygon walk.
static var _zone_polys: Array[PackedVector2Array] = []
static var _zone_rects: Array[Rect2] = []
static var _zone_surfaces: Array[String] = []
## Owner tag per zone ("" = untagged, the legacy default). Lets two tracks (or a
## track and a test) register zones without one's cleanup wiping the other's.
static var _zone_owners: Array[String] = []


## Clears zones. With no `owner` (the legacy call) EVERY zone goes; with an
## owner only the zones registered under that owner are removed, so e.g.
## `clear_zones("le_mans")` cannot wipe another track's zones.
static func clear_zones(owner: String = "") -> void:
	if owner.is_empty():
		_zone_polys.clear()
		_zone_rects.clear()
		_zone_surfaces.clear()
		_zone_owners.clear()
		return
	for i in range(_zone_owners.size() - 1, -1, -1):
		if _zone_owners[i] == owner:
			_zone_polys.remove_at(i)
			_zone_rects.remove_at(i)
			_zone_surfaces.remove_at(i)
			_zone_owners.remove_at(i)


## Number of registered zones, or only those of `owner` when given.
static func zone_count(owner: String = "") -> int:
	if owner.is_empty():
		return _zone_polys.size()
	return _zone_owners.count(owner)


static func add_zone(points_xz: Array, surface_key: String, owner: String = "") -> void:
	if points_xz.is_empty():
		return
	var poly: PackedVector2Array = PackedVector2Array()
	for p in points_xz:
		if p is Vector2:
			poly.append(p)
		elif p is Vector3:
			poly.append(Vector2(p.x, p.z))
	_zone_polys.append(poly)
	_zone_surfaces.append(surface_key)
	_zone_rects.append(_poly_bounds(poly))
	_zone_owners.append(owner)


## XZ bounding box of a polygon, cached at `add_zone` time so the hot
## classifier can reject a zone with a single Rect2 test. A polygon with fewer
## than three points can never contain a point (`_point_in_poly` rejects
## n < 3), so it gets an empty rect and is skipped by the size check.
static func _poly_bounds(poly: PackedVector2Array) -> Rect2:
	if poly.size() < 3:
		return Rect2()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo.x = minf(lo.x, p.x)
		lo.y = minf(lo.y, p.y)
		hi.x = maxf(hi.x, p.x)
		hi.y = maxf(hi.y, p.y)
	return Rect2(lo, hi - lo)


static func _point_in_poly(pt: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var n := poly.size()
	if n < 3:
		return false
	var j := n - 1
	for i in n:
		var xi := poly[i].x
		var yi := poly[i].y
		var xj := poly[j].x
		var yj := poly[j].y
		var intersect := ((yi > pt.y) != (yj > pt.y)) and \
			(pt.x < (xj - xi) * (pt.y - yi) / ((yj - yi) if absf(yj - yi) > 1e-12 else 1e-12) + xi)
		if intersect:
			inside = not inside
		j = i
	return inside


static func classify_zone_at(pos: Vector3) -> String:
	if _zone_polys.is_empty():
		return ""
	var pt := Vector2(pos.x, pos.z)
	for i in _zone_polys.size():
		var poly: PackedVector2Array = _zone_polys[i]
		# Degenerate zone (fewer than three points) can never contain a point;
		# `_point_in_poly` rejects n < 3, so skip it before the bounds test.
		if poly.size() < 3:
			continue
		var rect: Rect2 = _zone_rects[i]
		if not rect.has_point(pt):
			continue
		if _point_in_poly(pt, poly):
			return _zone_surfaces[i]
	return ""

# --- RoadTierProvider signature: (pos: Vector3) -> Dictionary ---
# Returns { "tier": int, "distance": float, "width": float } when a road exists,
# {} otherwise. A Callable is used so tests can inject a stub without a live RoadNetwork.

## Deterministic surface classification. Near a road the road's tier surface
## wins; otherwise EVERY off-road position is grass (biome band no longer
## changes the surface key).
## region_biome: TerrainBaker.elevation_band() return value (0..5).
## distance_to_road: XZ distance in metres to the nearest road CENTERLINE, as
## reported by RoadNetwork.nearest_road_lookup (never the distance to a sparse
## polyline vertex, which reads 60+ m mid-span on the perimeter highway).
## tier: RoadDef.Tier value of nearest road (used only when road-close).
## road_width: full nearest-road width in metres; non-positive keeps the fixed canopy.
## road_surface: RoadDef.Surface of the nearest SEGMENT of a mixed-surface road
## (-1 = the road has no per-point profile, the tier decides).
static func classify(region_biome: int, distance_to_road: float, tier: int, road_width: float = -1.0, pos: Vector3 = Vector3.ZERO, road_surface: int = -1) -> Dictionary:
	return _classify_with_zone(classify_zone_at(pos), region_biome, distance_to_road, tier, road_width, road_surface)


## The body of `classify` with the zone ALREADY resolved. `build_classifier`
## resolves the zone ONCE and calls this directly: the old code called
## `classify()` which re-ran `classify_zone_at`, walking every zone polygon a
## SECOND time for every physics frame.
static func _classify_with_zone(zone_key: String, region_biome: int, distance_to_road: float, tier: int, road_width: float, road_surface: int = -1) -> Dictionary:
	if zone_key != "":
		# SAND and GRAVEL are both in SURFACE_GRIP, so this branch is subsumed
		# by the lookup below; it is kept explicit because a gravel/sand trap
		# is a first-class surface, not a fallback.
		if zone_key == SAND or zone_key == GRAVEL:
			return _build_entry(zone_key)
		if SURFACE_GRIP.has(zone_key):
			return _build_entry(zone_key)
	# Mixed-surface road: ON the carriageway the segment's own surface wins
	# (Barcelona RX: asphalt vs its loose section). The verge keeps the tier rule.
	if road_surface >= 0 and road_width > 0.0 \
			and distance_to_road <= road_width * 0.5 + PAVED_EDGE_MARGIN:
		return _build_entry(ROAD_SURFACE_KEYS.get(road_surface, TIER_SURFACE.get(tier, ASPHALT)) as String)
	var topping: float = ROAD_TOPPING
	if road_width > 0.0:
		topping = maxf(ROAD_TOPPING, road_width * 0.5 + ROAD_EDGE_MARGIN)
	if distance_to_road <= topping:
		return _build_entry(TIER_SURFACE.get(tier, ASPHALT) as String)
	# Off-road: grass, whatever the band.
	return _build_entry(_biome_surface(region_biome))

static func _build_entry(surface_key: String) -> Dictionary:
	var grip: Dictionary = SURFACE_GRIP[surface_key] as Dictionary
	return {
		"surface_key": surface_key,
		"lateral": grip["lateral"],
		"longitudinal": grip["longitudinal"],
	}

## Resolves an off-road position into a surface key. EVERY biome band is grass:
## no band changes grip any more, so the whole open world away from tarmac
## feels like one continuous off-road surface (the alpine snow/ice VISUALS are
## RegionalClimate/WeatherManager's business, this table is feel only). The
## match stays for exhaustiveness so a new band has to be added deliberately.
static func _biome_surface(band: int) -> String:
	match band:
		BAND_SEA:
			return GRASS
		BAND_PLAINS:
			return GRASS
		BAND_ROLLING:
			return GRASS
		BAND_LOWLAND:
			return GRASS
		BAND_HIGHLAND:
			return GRASS
		BAND_ALPINE:
			return GRASS
		_:
			return GRASS

## Convenience: returns only the lateral multiplier for a surface key.
static func get_lateral(surface_key: String) -> float:
	var grip: Dictionary = SURFACE_GRIP.get(surface_key, SURFACE_GRIP[ASPHALT]) as Dictionary
	return grip["lateral"] as float

## Convenience: returns only the longitudinal multiplier for a surface key.
static func get_longitudinal(surface_key: String) -> float:
	var grip: Dictionary = SURFACE_GRIP.get(surface_key, SURFACE_GRIP[ASPHALT]) as Dictionary
	return grip["longitudinal"] as float

## Default RoadTierProvider bound to `owning_node`'s tree. Finds the local
## RoadNetwork (group "road_network") and reports { tier, distance, width } for
## a position (plus "surface", the nearest segment's RoadDef.Surface, when the
## road carries a per-point surface profile); returns {} when no RoadNetwork exists (or it holds no roads) so
## the physics falls back to asphalt (headless-safe: no scene, no network =>
## empty).
static func default_road_tier_provider(owning_node: Node) -> Callable:
	return func(pos: Vector3) -> Dictionary:
		var net: RoadNetwork = SurfaceRegistry._current_road_network(owning_node)
		if net == null:
			return {}
		var lookup: Dictionary = net.nearest_road_lookup(pos)
		var road_id: int = int(lookup["id"])
		if road_id < 0:
			# Network present but empty: report "no tier" so the classifier keeps
			# its asphalt fallback instead of classifying against an INF distance.
			return {}
		# The XZ centerline distance the lookup already resolved -- recomputing it
		# from lookup["pos"] would reintroduce the vertex-distance bug.
		var dist: float = float(lookup["distance"])
		var tier: int = RoadDef.Tier.ARTERIAL
		var width: float = 0.0
		var defs: Array[RoadDef] = net.get_road_defs()
		if road_id < defs.size():
			var road_def: RoadDef = defs[road_id]
			tier = road_def.tier
			width = road_def.width
			if road_def.has_surface_profile():
				return {"tier": tier, "distance": dist, "width": width,
					"surface": road_def.surface_at_segment(int(lookup.get("seg", 0)))}
		return {"tier": tier, "distance": dist, "width": width}

## Builds a per-position classifier Callable safe to drop into VehiclePhysics.
## road_tier_provider: RoadTierProvider conforming callable (empty => asphalt
## fallback). biome_provider: Callable(pos: Vector3) -> int band (empty =>
## BAND_PLAINS). The returned callable yields { surface_key, lateral,
## longitudinal }; an empty tier report falls back to asphalt.
static func build_classifier(road_tier_provider: Callable, biome_provider: Callable) -> Callable:
	return func(pos: Vector3) -> Dictionary:
		# Resolve the zone ONCE. The old code scanned every zone polygon here
		# and then called `classify()`, which scanned them all AGAIN.
		var zone_key := classify_zone_at(pos)
		if zone_key != "" and SURFACE_GRIP.has(zone_key):
			return _build_entry(zone_key)
		var tier_report: Dictionary = road_tier_provider.call(pos) if road_tier_provider.is_valid() else {}
		if tier_report.is_empty():
			var asphalt: Dictionary = SURFACE_GRIP[ASPHALT] as Dictionary
			return {
				"surface_key": ASPHALT,
				"lateral": asphalt["lateral"],
				"longitudinal": asphalt["longitudinal"],
			}
		var dist := float(tier_report.get("distance", INF))
		var tier := int(tier_report.get("tier", RoadDef.Tier.ARTERIAL))
		var road_width: float = float(tier_report.get("width", -1.0))
		var band := int(biome_provider.call(pos)) if biome_provider.is_valid() else BAND_PLAINS
		var road_surface := int(tier_report.get("surface", -1))
		return SurfaceRegistry._classify_with_zone(zone_key, band, dist, tier, road_width, road_surface)

static func _current_road_network(owning_node: Node) -> RoadNetwork:
	if owning_node == null or not is_instance_valid(owning_node):
		return null
	var tree := owning_node.get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("road_network"):
		if node is RoadNetwork:
			return node as RoadNetwork
	return null
