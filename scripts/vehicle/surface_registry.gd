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

const SURFACE_COUNT: int = 6

# --- Biome band constants (matches TerrainBaker band indices) ---
const BAND_SEA: int = 0
const BAND_PLAINS: int = 1
const BAND_ROLLING: int = 2
const BAND_LOWLAND: int = 3
const BAND_HIGHLAND: int = 4
const BAND_ALPINE: int = 5

const ROAD_TOPPING: float = 6.0

# --- Grip table: { surface_key: { lateral: float, longitudinal: float } } ---
# Tuned per FH6-inspired impact table (§3.5 fh6_map.md).
const SURFACE_GRIP: Dictionary = {
	ASPHALT:  { "lateral": 1.0,  "longitudinal": 1.0 },
	GRAVEL:   { "lateral": 0.85, "longitudinal": 0.80 },
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

# --- RoadTierProvider signature: (pos: Vector3) -> Dictionary ---
# Returns { "tier": int, "distance": float } when a road exists, {} otherwise.
# A Callable is used so tests can inject a stub without a live RoadNetwork.

## Deterministic surface classification. Near a road the road's tier surface
## wins; otherwise the terrain elevation band maps to an off-road surface.
## region_biome: TerrainBaker.elevation_band() return value (0..5).
## distance_to_road: world-space distance to nearest road centre (metres).
## tier: RoadDef.Tier value of nearest road (used only when road-close).
static func classify(region_biome: int, distance_to_road: float, tier: int) -> Dictionary:
	if distance_to_road <= ROAD_TOPPING:
		return _build_entry(TIER_SURFACE.get(tier, ASPHALT) as String)
	# Off-road: classify by biome band.
	return _build_entry(_biome_surface(region_biome))

static func _build_entry(surface_key: String) -> Dictionary:
	var grip: Dictionary = SURFACE_GRIP[surface_key] as Dictionary
	return {
		"surface_key": surface_key,
		"lateral": grip["lateral"],
		"longitudinal": grip["longitudinal"],
	}

## Resolves an off-road position into a surface key from the terrain biome band.
static func _biome_surface(band: int) -> String:
	match band:
		BAND_SEA:
			return GRASS
		BAND_PLAINS:
			return GRASS
		BAND_ROLLING:
			return GRASS
		BAND_LOWLAND:
			return MUD
		BAND_HIGHLAND:
			return GRAVEL
		BAND_ALPINE:
			return SNOW
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
## RoadNetwork (group "road_network") and reports { tier, distance } for a
## position; returns {} when no RoadNetwork exists so the physics falls back
## to asphalt (headless-safe: no scene, no network => empty).
static func default_road_tier_provider(owning_node: Node) -> Callable:
	return func(pos: Vector3) -> Dictionary:
		var net: RoadNetwork = SurfaceRegistry._current_road_network(owning_node)
		if net == null:
			return {}
		var lookup: Dictionary = net.nearest_road_lookup(pos)
		var nearest: Vector3 = lookup["pos"]
		var dist: float = nearest.distance_to(pos)
		var road_id: int = int(lookup["id"])
		var tier: int = RoadDef.Tier.ARTERIAL
		var defs: Array[RoadDef] = net.get_road_defs()
		if road_id >= 0 and road_id < defs.size():
			tier = defs[road_id].tier
		return {"tier": tier, "distance": dist}

## Builds a per-position classifier Callable safe to drop into VehiclePhysics.
## road_tier_provider: RoadTierProvider conforming callable (empty => asphalt
## fallback). biome_provider: Callable(pos: Vector3) -> int band (empty =>
## BAND_PLAINS). The returned callable yields { surface_key, lateral,
## longitudinal }; an empty tier report falls back to asphalt.
static func build_classifier(road_tier_provider: Callable, biome_provider: Callable) -> Callable:
	return func(pos: Vector3) -> Dictionary:
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
		var band := int(biome_provider.call(pos)) if biome_provider.is_valid() else BAND_PLAINS
		return SurfaceRegistry.classify(band, dist, tier)

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
