class_name TrackRegistry
extends RefCounted

## Static registry of every drivable track: id -> { display_name, scene_path,
## laps_default, difficulty, circuit_type }.

static var tracks: Dictionary = {
	"oval": {
		"display_name": "Sunset Oval",
		"scene_path": "res://scenes/test/test_track.tscn",
		"laps_default": 3,
		"difficulty": "D",
		"circuit_type": "CIRCUIT",
	},
	"mountain_pass": {
		"display_name": "Mountain Pass",
		"scene_path": "res://scenes/track/mountain_pass.tscn",
		"laps_default": 2,
		"difficulty": "B",
		"circuit_type": "CIRCUIT",
	},
}

static func get_track_ids() -> Array:
	return tracks.keys()

static func get_track(track_id: String) -> Dictionary:
	return tracks.get(track_id, {})

static func get_scene_path(track_id: String) -> String:
	return get_track(track_id).get("scene_path", "")

static func has_track(track_id: String) -> bool:
	return tracks.has(track_id)