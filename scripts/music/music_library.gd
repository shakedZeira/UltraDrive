# scripts/music/music_library.gd
class_name MusicLibrary
extends RefCounted

## In-memory model of a scanned music folder: tracks by id plus the stations
## derived from them. Fed in batches by the scanner (playback may begin after the
## first batch), rebuilt cheaply after each.
##
## Track dictionary: id (= relative path), path (absolute), rel, station_folder
## ("" for loose root files), title, artist, album, track_no, duration_s, ext,
## native (bool: playable now), has_cover, cover_mime, cover_file (relative
## sidecar image or "").

var tracks: Dictionary = {}
var order: Array[String] = []
## folder name -> station.json dictionary (name, order, shuffle, color).
var folder_meta: Dictionary = {}
var stations: Array[MusicStation] = []

func clear() -> void:
	tracks.clear()
	order.clear()
	folder_meta.clear()
	stations.clear()

func add_tracks(batch: Array) -> void:
	for t in batch:
		var track: Dictionary = t
		var id := String(track.get("id", ""))
		if id.is_empty():
			continue
		if not tracks.has(id):
			order.append(id)
		tracks[id] = track
	rebuild_stations()

func set_folder_meta(meta: Dictionary) -> void:
	folder_meta = meta
	rebuild_stations()

func get_track(id: String) -> Dictionary:
	return tracks.get(id, {})

func station_by_id(station_id: String) -> MusicStation:
	for s in stations:
		if s.id == station_id:
			return s
	return null

## Stations that have something to play, in cycle order (All Songs first).
func playable_stations() -> Array[MusicStation]:
	var out: Array[MusicStation] = []
	for s in stations:
		if s.playable_count() > 0:
			out.append(s)
	return out

func artist_map() -> Dictionary:
	var m := {}
	for id in order:
		m[id] = String(tracks[id].get("artist", ""))
	return m

func stats() -> Dictionary:
	var playable := 0
	var convert := 0
	for id in order:
		if bool(tracks[id].get("native", false)):
			playable += 1
		else:
			convert += 1
	var real_stations := 0
	for s in stations:
		if s.id != MusicStation.ALL_ID and s.playable_count() > 0:
			real_stations += 1
	return {"tracks": order.size(), "playable": playable, "needs_conversion": convert, "stations": real_stations}

func status_text() -> String:
	var st := stats()
	var text := "%d tracks, %d stations" % [int(st["playable"]), int(st["stations"])]
	if int(st["needs_conversion"]) > 0:
		text += ", %d need conversion" % int(st["needs_conversion"])
	return text

func rebuild_stations() -> void:
	var all := MusicStation.new()
	all.id = MusicStation.ALL_ID
	all.display_name = MusicStation.ALL_NAME
	all.order = -1000000
	all.color = MusicStation.color_for(all.display_name)
	var by_folder: Dictionary = {}
	for id in order:
		var t: Dictionary = tracks[id]
		var folder := String(t.get("station_folder", ""))
		var st: MusicStation = by_folder.get(folder)
		if st == null:
			st = MusicStation.new()
			st.folder = folder
			if folder.is_empty():
				st.id = MusicStation.LIBRARY_ID
				st.display_name = MusicStation.LIBRARY_NAME
			else:
				st.id = MusicStation.id_for_folder(folder)
				st.display_name = MusicStation.display_name_for_folder(folder)
			var meta: Dictionary = folder_meta.get(folder, {})
			if not String(meta.get("name", "")).strip_edges().is_empty():
				st.display_name = String(meta["name"]).strip_edges()
			st.order = int(meta.get("order", 1000))
			st.shuffle = bool(meta.get("shuffle", true))
			st.color = MusicStation.parse_color(String(meta.get("color", "")), MusicStation.color_for(st.display_name))
			by_folder[folder] = st
		if bool(t.get("native", false)):
			st.track_ids.append(id)
			all.track_ids.append(id)
		else:
			st.needs_conversion += 1
			all.needs_conversion += 1
	var list: Array[MusicStation] = []
	for folder in by_folder:
		list.append(by_folder[folder])
	list.sort_custom(func(a: MusicStation, b: MusicStation) -> bool:
		if a.order != b.order:
			return a.order < b.order
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	stations = [all]
	stations.append_array(list)
