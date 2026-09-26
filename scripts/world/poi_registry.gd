class_name POIRegistry
extends RefCounted

## Static registry of every open-world point of interest: id -> { name, stage, position }.
## Positions are world-space meters (map footprint 0..6144 on X and Z).

## P6: event markers appended lazily on first access (one-shot), derived from
## the classified road network via EventRegistry.place / CorridorPlanner.plan.
## Pure and deterministic: same master seed, same markers — the pause-map dots
## and the headless assertions always agree with the game build.
static var _events: Dictionary = {}
static var _events_loaded := false

static var pois: Dictionary = {
	"festival_hub": {
		"name": "Horizon Festival",
		"stage": "Festival Plains",
		"position": Vector3(128.0, 2.2, 128.0),
	},
	"lowland_view": {
		"name": "Lowland View",
		"stage": "Rolling Lowlands",
		"position": Vector3(1536.0, 6.0, 1536.0),
	},
	"dry_lake": {
		"name": "Dry Lake",
		"stage": "Coast Apron",
		"position": Vector3(5888.0, 2.5, 1536.0),
	},
	"pass_entry": {
		"name": "Pass Entry",
		"stage": "Forested Highlands",
		"position": Vector3(3840.0, 10.0, 2304.0),
	},
	"alpine_overlook": {
		"name": "Alpine Overlook",
		"stage": "Alpine Overlook",
		"position": Vector3(5632.0, 35.0, 5632.0),
	},
}

static func get_poi_ids() -> Array:
	_load_events()
	return pois.keys()

static func get_poi(poi_id: String) -> Dictionary:
	_load_events()
	return pois.get(poi_id, {})

static func has_poi(poi_id: String) -> bool:
	_load_events()
	return pois.has(poi_id)

## AAA-3 map filters: every known POI belongs to exactly one category —
## CATEGORY_LANDMARKS (the base five destinations), CATEGORY_EVENTS (the planned
## race/event sites) or CATEGORY_COLLECTIBLES (the road-anchored bonus boards,
## speed traps and photo spots).
##
## Collectibles get their OWN category instead of riding the events bucket.
## They are permanent gameplay the player has to aim at, not a calendar entry,
## so the events filter can never hide a speed trap: the pause map is the only
## planning tool the player has, and a target missing off that map is a target
## that is easy to miss in the world. Both families are still data-driven — a
## base POI carries neither a "kind" nor a collectible id — so category stays a
## pure function of the registry entry and needs no side tables.
const CATEGORY_LANDMARKS := "landmarks"
const CATEGORY_EVENTS := "events"
const CATEGORY_COLLECTIBLES := "collectibles"

## `poi_id` is optional and only ever a fast path: the map's filter holds the id
## it is drawing, so it can classify even an entry that forgot to carry its own
## "id" key. Everything else reads the entry, which is what the static buckets
## and the tests do.
static func category_of(poi: Dictionary, poi_id: String = "") -> String:
	var id := poi_id if not poi_id.is_empty() else str(poi.get("id", ""))
	if Collectibles.is_collectible_id(id):
		return CATEGORY_COLLECTIBLES
	return CATEGORY_EVENTS if poi.has("kind") else CATEGORY_LANDMARKS

## Exact per-category id buckets: {"landmarks": [ids...], "events": [ids...],
## "collectibles": [ids...]}. Exhaustive and disjoint — every get_poi_ids() id
## lands in exactly one bucket.
static func category_buckets() -> Dictionary:
	var buckets := {CATEGORY_LANDMARKS: [], CATEGORY_EVENTS: [], CATEGORY_COLLECTIBLES: []}
	for poi_id in get_poi_ids():
		var cat: String = category_of(get_poi(poi_id), poi_id)
		var bucket: Array = buckets[cat]
		bucket.append(poi_id)
		buckets[cat] = bucket
	return buckets

## { poi_id -> poi } restricted to the requested categories (exact match: a POI
## is kept iff category_of(poi) is in `include`).
static func filter_by_category(include: Array) -> Dictionary:
	var out := {}
	for poi_id in get_poi_ids():
		var poi := get_poi(poi_id)
		if include.has(category_of(poi, poi_id)):
			out[poi_id] = poi
	return out

## Case-insensitive substring match on the POI's stage name. An empty region
## matches everything (the shipped "any region" default).
static func matches_region(poi: Dictionary, region: String) -> bool:
	if region.is_empty():
		return true
	return str(poi.get("stage", "")).to_lower().contains(region.to_lower())

## { poi_id -> poi } from `source` (a get_poi_ids()-shaped dict) whose stage
## matches the region substring.
static func filter_by_region(source: Dictionary, region: String) -> Dictionary:
	var out := {}
	for poi_id in source.keys():
		var poi: Dictionary = source[poi_id]
		if matches_region(poi, region):
			out[poi_id] = poi
	return out

## Travel-eligibility predicate for the map's "travel" filter. With no gate
## (the shipped default) every POI is eligible; with a gate, only ids it maps
## to true qualify. Pure, so the map dot set is testable without a scene.
static func is_travel_eligible(poi_id: String, revealed: Callable = Callable()) -> bool:
	if not revealed.is_valid():
		return true
	return bool(revealed.call(poi_id))

## One-shot enrichment: plans the full corridor network and merges every event
## site into `pois`, keeping the base { name, stage, position } shape (plus
## kind / tier / road_id / extra). world_map.gd draws dots from get_poi_ids(),
## so the event markers appear on the pause map automatically.
##
## AAA-16: the road-anchored collectibles (bonus boards, speed traps, photo
## spots) merge in the same pass, in the same shape and with a "kind" so both
## map dot layers pick them up from get_poi_ids() with no second source. They
## classify as CATEGORY_COLLECTIBLES (their own always-shown bucket, NOT the
## events one), so the pause map's events filter can never hide a speed trap.
## The anchors are read from the base five only, so collectible placement is NOT
## bound by the 0..6144 base-POI tile bounds — like the event markers it rides
## the real road net.
static func _load_events() -> void:
	if _events_loaded:
		return
	_events_loaded = true
	var defs: Array[RoadDef] = CorridorPlanner.plan(CorridorPlanner.MASTER_SEED, Callable(), {})
	var anchors: Array[Vector3] = []
	for id: String in pois.keys():
		var poi: Dictionary = pois[id]
		anchors.append(poi["position"] as Vector3)
	_events = EventRegistry.place_data(defs, anchors)
	for event_id: String in _events.keys():
		pois[event_id] = _events[event_id]
	pois.merge(Collectibles.place_data(defs), true)