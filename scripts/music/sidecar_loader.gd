# scripts/music/sidecar_loader.gd
class_name SidecarLoader
extends RefCounted

## Optional human metadata next to the audio files. Spotify Replica's downloads
## are opaque `<playlistId>/<spotifyId>.<ext>`; embedded tags usually carry the
## title and artist, but folder names (= station names) and playlist order only
## exist in a sidecar:
##
##   1. `ultradrive_library.json` at the library root (schema 1):
##        { "schema": 1,
##          "playlists": [ {"name": "Night Drive", "cover": "covers/x.jpg",
##                          "tracks": ["<stem or relative path>", ...]} ],
##          "tracks": { "<file stem>": {"title": "...", "artists": ["..."], "album": "...",
##                                       "duration_ms": 258000, "cover": "covers/x.jpg"} } }
##   2. else `*.m3u8` / `*.m3u` at the root or in a top-level sub-folder
##      (`#EXTINF:<sec>,<Artist> - <Title>` + relative paths), one playlist each.
##
## Contract: a wrong schema, bad JSON or unreadable file means "no sidecar", never
## a crash; unknown keys are ignored; paths that escape the root (".." or
## absolute) are dropped. Embedded tags win over the sidecar (it only fills empty
## fields); the sidecar's playlists become stations.
##
## Result: { tracks: {key: {title, artist, album, duration_s, cover}},
##           playlists: [{name, keys: [String], cover}] } or {}.
## A "key" is a lower-cased file stem or a lower-cased root-relative path.

const JSON_NAME := "ultradrive_library.json"
const SCHEMA := 1
const MAX_BYTES := 8 * 1024 * 1024

## Loads the sidecar of a library root ({} when there is none).
static func load_root(root: String) -> Dictionary:
	var base := root.replace("\\", "/").rstrip("/")
	if base.is_empty() or not DirAccess.dir_exists_absolute(base):
		return {}
	var json_path := base + "/" + JSON_NAME
	if FileAccess.file_exists(json_path):
		var text := _read_text(json_path)
		var parsed := parse_json(text)
		if not parsed.is_empty():
			return parsed
	return _load_m3u8_files(base)

## Pure: JSON text -> result ({} for anything not a schema-1 library).
static func parse_json(text: String) -> Dictionary:
	if text.strip_edges().is_empty():
		return {}
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary):
		return {}
	var d: Dictionary = data
	if typeof(d.get("schema")) not in [TYPE_INT, TYPE_FLOAT] or int(d["schema"]) != SCHEMA:
		return {}
	var tracks := {}
	var src_tracks: Variant = d.get("tracks", {})
	if src_tracks is Dictionary:
		for id in src_tracks:
			var t: Variant = src_tracks[id]
			if not (t is Dictionary):
				continue
			var key := String(id).strip_edges().to_lower()
			if key.is_empty():
				continue
			tracks[key] = {
				"title": _str(t.get("title", "")),
				"artist": _artists(t.get("artists", t.get("artist", ""))),
				"album": _str(t.get("album", "")),
				"duration_s": _num(t.get("duration_ms", 0)) / 1000.0,
				"cover": safe_rel(_str(t.get("cover", ""))),
			}
	var playlists: Array = []
	var src_lists: Variant = d.get("playlists", [])
	if src_lists is Array:
		for p in src_lists:
			if not (p is Dictionary):
				continue
			var name := _str(p.get("name", ""))
			var keys: Array = []
			var raw_keys: Variant = p.get("tracks", [])
			if raw_keys is Array:
				for k in raw_keys:
					var s := String(k).strip_edges().replace("\\", "/")
					if s.contains("/"):
						s = safe_rel(s)
					if s.is_empty():
						continue
					keys.append(s.to_lower())
			if name.is_empty() or keys.is_empty():
				continue
			playlists.append({"name": name, "keys": keys, "cover": safe_rel(_str(p.get("cover", "")))})
	if tracks.is_empty() and playlists.is_empty():
		return {}
	return {"tracks": tracks, "playlists": playlists}

## Pure: one m3u/m3u8 -> {name, keys, tracks}. `dir_rel` is the playlist's folder
## relative to the root ("" for the root), `name` its display name.
static func parse_m3u8(text: String, dir_rel: String, name: String) -> Dictionary:
	var keys: Array = []
	var tracks := {}
	var pending_title := ""
	var pending_artist := ""
	var pending_len := 0.0
	for raw_line in text.replace("\r", "").split("\n"):
		var line := String(raw_line).strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("#"):
			if line.to_upper().begins_with("#EXTINF:"):
				var body := line.substr(8)
				var comma := body.find(",")
				pending_len = _num(body.substr(0, comma) if comma >= 0 else body)
				var label := body.substr(comma + 1).strip_edges() if comma >= 0 else ""
				var sep := label.find(" - ")
				if sep > 0:
					pending_artist = label.substr(0, sep).strip_edges()
					pending_title = label.substr(sep + 3).strip_edges()
				else:
					pending_artist = ""
					pending_title = label
			continue
		var joined := line.replace("\\", "/")
		if not dir_rel.is_empty():
			joined = dir_rel + "/" + joined
		var rel := safe_rel(joined)
		if rel.is_empty():
			pending_title = ""
			pending_artist = ""
			continue
		var key := rel.to_lower()
		keys.append(key)
		if not pending_title.is_empty() or not pending_artist.is_empty():
			tracks[key] = {"title": pending_title, "artist": pending_artist, "album": "",
				"duration_s": maxf(pending_len, 0.0), "cover": ""}
		pending_title = ""
		pending_artist = ""
	if keys.is_empty():
		return {}
	return {"name": name, "keys": keys, "tracks": tracks}

## Normalised root-relative path ("a/b/c.ogg"), or "" when it is empty, absolute,
## has a drive letter or a ".." segment (must stay inside the library root).
static func safe_rel(path: String) -> String:
	var p := path.strip_edges().replace("\\", "/")
	if p.is_empty() or p.begins_with("/") or p.contains(":") or p.begins_with("res://") or p.begins_with("user://"):
		return ""
	var out: PackedStringArray = []
	for seg in p.split("/"):
		if seg == "" or seg == ".":
			continue
		if seg == "..":
			return ""
		out.append(seg)
	return "/".join(out)

static func _load_m3u8_files(base: String) -> Dictionary:
	var playlists: Array = []
	var tracks := {}
	var dirs: Array = [""]
	var root_dir := DirAccess.open(base)
	if root_dir == null:
		return {}
	root_dir.list_dir_begin()
	var entry := root_dir.get_next()
	while entry != "":
		if root_dir.current_is_dir() and not entry.begins_with("."):
			dirs.append(entry)
		entry = root_dir.get_next()
	root_dir.list_dir_end()
	dirs.sort()
	for rel_dir in dirs:
		var dir := DirAccess.open(base if rel_dir == "" else base + "/" + rel_dir)
		if dir == null:
			continue
		var files: Array = []
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if not dir.current_is_dir() and f.get_extension().to_lower() in ["m3u8", "m3u"]:
				files.append(f)
			f = dir.get_next()
		dir.list_dir_end()
		files.sort()
		for file_name in files:
			var path: String = (base if rel_dir == "" else base + "/" + rel_dir) + "/" + String(file_name)
			var text := _read_text(path)
			var pl := parse_m3u8(text, rel_dir, String(file_name).get_basename())
			if pl.is_empty():
				continue
			playlists.append({"name": pl["name"], "keys": pl["keys"], "cover": ""})
			for k in pl["tracks"]:
				tracks[k] = pl["tracks"][k]
	if playlists.is_empty():
		return {}
	return {"tracks": tracks, "playlists": playlists}

static func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var n := mini(f.get_length(), MAX_BYTES)
	var text := f.get_buffer(n).get_string_from_utf8()
	f.close()
	if text.begins_with("﻿"):
		text = text.substr(1)
	return text

static func _str(v: Variant) -> String:
	return String(v).strip_edges() if typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME else ""

static func _num(v: Variant) -> float:
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		var f := float(v)
		return 0.0 if (is_nan(f) or is_inf(f)) else f
	if typeof(v) == TYPE_STRING and String(v).is_valid_float():
		return String(v).to_float()
	return 0.0

static func _artists(v: Variant) -> String:
	if v is Array:
		var parts: PackedStringArray = []
		for a in v:
			var s := _str(a)
			if not s.is_empty():
				parts.append(s)
		return ", ".join(parts)
	return _str(v)
