class_name POIRegistry
extends RefCounted

## Static registry of every open-world point of interest: id -> { name, stage, position }.
## Positions are world-space meters (map footprint 0..6144 on X and Z).

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
	return pois.keys()

static func get_poi(poi_id: String) -> Dictionary:
	return pois.get(poi_id, {})

static func has_poi(poi_id: String) -> bool:
	return pois.has(poi_id)