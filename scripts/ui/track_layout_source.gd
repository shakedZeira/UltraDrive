class_name TrackLayoutSource
extends RefCounted

## READ-ONLY access to the offline-baked per-layout centerline data.
##
## `tools/gen_track_layouts.gd` bakes one `resources/ui/track_layouts/<id>.json`
## per `TrackRegistry.get_track_ids()` entry. This class is the only runtime
## reader: the race menu's layout preview and event panel consult it, and it
## never instantiates a track scene into the tree (that would consume a queued
## race via `race_ui._ready()`, pollute VehicleManager and trigger the Mountain
## Pass terrain bake — see docs/plans/race_tab_track_layout_event_details.md §6).
##
## Graceful degrade: when a layout was added AFTER the last bake its JSON is
## missing, so we fall back to a documented OFF-TREE convention probe — load the
## scene, `instantiate()` WITHOUT entering the tree, and call a pure
## `_generate_road_points()` when the script exposes one. Anything else returns
## empty data and the UI shows the "layout map unavailable" state (never a
## crash). Baked data is cached in memory; the probe runs at most once per id.
##
## All-static, mirroring MapRoads/TrackRegistry.

const PREVIEW_DIR := "res://resources/ui/track_layouts"
const MIN_POINTS := 3

## id -> resolved Dictionary {"points": Array[Vector3], "has_layout": bool,
## "rival_centerline": bool}. An empty Dictionary means "no data at all".
static var _cache: Dictionary = {}

## Absolute res:// path of the baked JSON for `track_id`.
static func preview_path(track_id: String) -> String:
	return "%s/%s.json" % [PREVIEW_DIR, track_id]

## The driven centerline (world space) for `track_id`; empty when unknown or
## unbaked-and-unprobeable. Returns a fresh array, so callers may mutate it.
static func points(track_id: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var data := _load_data(track_id)
	var raw: Variant = data.get("points", null)
	if raw is Array:
		out.assign(raw)
	return out

## True when a real centerline is available (baked, or probed off-tree).
static func has_layout(track_id: String) -> bool:
	var data := _load_data(track_id)
	return bool(data.get("has_layout", false))

## True when the layout will actually field AI rivals (only a track that calls
## `RaceManager.set_rival_centerline()` publishes one; today that is Northern
## Isle Speedway alone). Read from the bake, never guessed in the UI.
static func has_rival_centerline(track_id: String) -> bool:
	var data := _load_data(track_id)
	return bool(data.get("rival_centerline", false))

# --- internals ---------------------------------------------------------------

static func _load_data(track_id: String) -> Dictionary:
	if track_id.is_empty():
		return {}
	if _cache.has(track_id):
		return _cache[track_id]
	var data := _read_json(track_id)
	if data.is_empty():
		data = _probe_scene(track_id)
	_cache[track_id] = data
	return data

static func _read_json(track_id: String) -> Dictionary:
	var path := preview_path(track_id)
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var dict: Dictionary = parsed
	var parsed_points := _parse_points(dict.get("points", null))
	if parsed_points.size() < MIN_POINTS:
		return {}
	return {
		"points": parsed_points,
		"has_layout": bool(dict.get("has_layout", true)),
		"rival_centerline": bool(dict.get("rival_centerline", false)),
	}

## NEVER trust the file shape: only an Array of exactly 3 numbers is a point.
static func _parse_points(raw: Variant) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not (raw is Array):
		return out
	for entry: Variant in (raw as Array):
		if not (entry is Array):
			continue
		var triple: Array = entry
		if triple.size() != 3:
			continue
		var nums: Array[float] = []
		var ok := true
		for value: Variant in triple:
			if not (value is float or value is int):
				ok = false
				break
			nums.append(float(value))
		if not ok:
			continue
		out.append(Vector3(nums[0], nums[1], nums[2]))
	return out

## Documented convention probe for a track added after the last bake. OFF-TREE
## ONLY: `instantiate()` never calls `_ready()`, so no race is consumed, no car
## is registered and no terrain is baked. Anything but a pure
## `_generate_road_points()` yields empty data.
static func _probe_scene(track_id: String) -> Dictionary:
	var scene_path := TrackRegistry.get_scene_path(track_id)
	if scene_path.is_empty():
		return {}
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return {}
	var instance := packed.instantiate()
	if instance == null:
		return {}
	var collected: Array[Vector3] = []
	if instance.has_method("_generate_road_points"):
		var generated: Variant = instance.call("_generate_road_points")
		if generated is Array:
			collected.assign(generated)
	if is_instance_valid(instance):
		instance.free()
	if collected.size() < MIN_POINTS:
		return {}
	return {
		"points": collected,
		"has_layout": true,
		"rival_centerline": false,
	}
