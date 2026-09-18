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

## One-shot enrichment: plans the full corridor network and merges every event
## site into `pois`, keeping the base { name, stage, position } shape (plus
## kind / tier / road_id / extra). world_map.gd draws dots from get_poi_ids(),
## so the event markers appear on the pause map automatically.
static func _load_events() -> void:
	if _events_loaded:
		return
	_events_loaded = true
	var defs: Array[RoadDef] = CorridorPlanner.plan(CorridorPlanner.MASTER_SEED, Callable(), {})
	var anchors: Array[Vector3] = []
	for id: String in pois.keys():
		var poi: Dictionary = pois[id]
		anchors.append(poi["position"] as Vector3)
	_events = EventRegistry.place(defs, anchors)
	for event_id: String in _events.keys():
		pois[event_id] = _events[event_id]