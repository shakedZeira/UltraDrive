# scripts/music/music_station.gd
class_name MusicStation
extends RefCounted

## One radio station: the virtual "All Songs", the root-level "Library", or one
## top-level sub-folder of the music folder (nested folders flatten into it).

const ALL_ID := "all"
const LIBRARY_ID := "library"
const FOLDER_PREFIX := "f:"
const ALL_NAME := "All Songs"
const LIBRARY_NAME := "Library"

var id: String = ""
var display_name: String = ""
var folder: String = ""
var track_ids: Array[String] = []
var needs_conversion: int = 0
var shuffle: bool = true
var order: int = 0
var color: Color = Color(0.2, 0.2, 0.2)

func playable_count() -> int:
	return track_ids.size()

static func id_for_folder(folder_name: String) -> String:
	return FOLDER_PREFIX + folder_name

## Spotify Replica's un-playlisted downloads live in "standalone".
static func display_name_for_folder(folder_name: String) -> String:
	if folder_name.to_lower() == "standalone":
		return "Singles"
	return folder_name

## Stable accent colour from the station name (hash -> hue).
static func color_for(station_name: String) -> Color:
	var h := station_name.hash()
	var hue := float(h % 360) / 360.0
	return Color.from_hsv(hue, 0.55, 0.85)

## "#rrggbb" / "#rgb" or "" -> fallback.
static func parse_color(text: String, fallback: Color) -> Color:
	var t := text.strip_edges()
	if t.is_empty() or not Color.html_is_valid(t):
		return fallback
	return Color.html(t)
