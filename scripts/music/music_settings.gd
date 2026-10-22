# scripts/music/music_settings.gd
class_name MusicSettings
extends RefCounted

## Static defaults / clamp / sanitize for the `music_settings` sub-dictionary of
## the slot-0 save (additive key: old saves lack it and get defaults; the same
## pattern as camera_settings_from_save). The folder is machine-specific, lives
## OUTSIDE the project, and an empty value means "the default folder".

const SAVE_KEY := "music_settings"
const DEFAULT_FOLDER_WINDOWS := "D:/Music/UltraDrive"
const STATION_ALL := "all"

const VOLUME_MIN := 0.0
const VOLUME_MAX := 1.0
const VOLUME_STEP := 0.05
const CROSSFADE_MIN := 0.0
const CROSSFADE_MAX := 8.0

static func defaults() -> Dictionary:
	return {
		"enabled": true,
		"folder": "",
		"volume": 0.7,
		"station": STATION_ALL,
		"track_id": "",
		"shuffle": true,
		"crossfade_s": 2.5,
		"toast": true,
		"duck": true,
		"streamer_safe": false,
	}

## Coerce anything (a corrupt save may hold any type) into a complete, clamped
## settings dictionary. Unknown keys are dropped.
static func sanitize(value: Variant) -> Dictionary:
	var out := defaults()
	if not (value is Dictionary):
		return out
	var src: Dictionary = value
	for key in ["enabled", "shuffle", "toast", "duck", "streamer_safe"]:
		if src.has(key):
			out[key] = _to_bool(src[key], bool(out[key]))
	out["volume"] = clampf(_to_float(src.get("volume", out["volume"]), float(out["volume"])), VOLUME_MIN, VOLUME_MAX)
	out["crossfade_s"] = clampf(_to_float(src.get("crossfade_s", out["crossfade_s"]), float(out["crossfade_s"])), CROSSFADE_MIN, CROSSFADE_MAX)
	for key in ["folder", "station", "track_id"]:
		if src.has(key):
			out[key] = _to_str(src[key], String(out[key]))
	if String(out["station"]).is_empty():
		out["station"] = STATION_ALL
	return out

static func from_save(data: Dictionary) -> Dictionary:
	return sanitize(data.get(SAVE_KEY, {}))

## Copy of `data` with the music settings stored under SAVE_KEY; every other
## slot key is preserved untouched.
static func merge_into_save(data: Dictionary, settings: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	out[SAVE_KEY] = sanitize(settings)
	return out

## Platform default music folder (not created here).
static func default_folder() -> String:
	if OS.get_name() == "Windows":
		return DEFAULT_FOLDER_WINDOWS
	return OS.get_system_dir(OS.SYSTEM_DIR_MUSIC).path_join("UltraDrive")

## The folder that will be scanned: the user's choice, else the default.
static func effective_folder(settings: Dictionary) -> String:
	var f := String(settings.get("folder", "")).strip_edges()
	return f if not f.is_empty() else default_folder()

## True for res:// paths and for anything inside the project directory: files
## there are imported by the editor and bundled into exports - never music.
static func is_inside_project(path: String) -> bool:
	var p := path.strip_edges().replace("\\", "/")
	if p.begins_with("res://"):
		return true
	if p.is_empty():
		return false
	var project := ProjectSettings.globalize_path("res://").replace("\\", "/")
	if not project.ends_with("/"):
		project += "/"
	var candidate := p if p.ends_with("/") else p + "/"
	return candidate.to_lower().begins_with(project.to_lower())

## Creates the folder if missing; false when it could not be created.
static func ensure_folder(path: String) -> bool:
	if path.is_empty() or is_inside_project(path):
		return false
	if DirAccess.dir_exists_absolute(path):
		return true
	return DirAccess.make_dir_recursive_absolute(path) == OK

static func _to_bool(v: Variant, fallback: bool) -> bool:
	match typeof(v):
		TYPE_BOOL:
			return v
		TYPE_INT:
			return int(v) != 0
		TYPE_FLOAT:
			return float(v) != 0.0
	return fallback

static func _to_float(v: Variant, fallback: float) -> float:
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		var f := float(v)
		if is_nan(f) or is_inf(f):
			return fallback
		return f
	return fallback

static func _to_str(v: Variant, fallback: String) -> String:
	if typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME:
		return String(v).substr(0, 1024)
	return fallback
