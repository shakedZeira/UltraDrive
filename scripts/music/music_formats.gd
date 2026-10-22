# scripts/music/music_formats.gd
class_name MusicFormats
extends RefCounted

## Which audio containers the game can decode natively (Godot 4: MP3, Ogg
## Vorbis, WAV) and which it can only LIST ("needs conversion": FLAC, M4A/AAC,
## Opus, WebM). tools/music_convert.py turns the latter into Ogg Vorbis.

enum Kind { NONE, NATIVE, CONVERT }

const NATIVE_EXT: Array[String] = ["mp3", "ogg", "oga", "wav"]
const CONVERT_EXT: Array[String] = ["flac", "m4a", "aac", "mp4", "opus", "webm"]
const IMAGE_EXT: Array[String] = ["jpg", "jpeg", "png", "webp"]
## Folder-level cover names tried (any image extension) after "<stem>.<img>".
const FOLDER_COVER_STEMS: Array[String] = ["cover", "folder", "front", "album"]

static func kind_for(ext: String) -> int:
	var e := ext.to_lower()
	if NATIVE_EXT.has(e):
		return Kind.NATIVE
	if CONVERT_EXT.has(e):
		return Kind.CONVERT
	return Kind.NONE

static func is_image(ext: String) -> bool:
	return IMAGE_EXT.has(ext.to_lower())

## In-flight / temporary download files (Spotify Replica writes "<id>.part.<ext>").
static func is_partial(file_name: String) -> bool:
	var n := file_name.to_lower()
	return n.contains(".part.") or n.ends_with(".part") or n.ends_with(".tmp") \
		or n.ends_with(".crdownload") or n.ends_with(".download")

## Image MIME from magic bytes ("" if unknown).
static func sniff_image_mime(bytes: PackedByteArray) -> String:
	if bytes.size() >= 3 and bytes[0] == 0xFF and bytes[1] == 0xD8:
		return "image/jpeg"
	if bytes.size() >= 8 and bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		return "image/png"
	if bytes.size() >= 12 and bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[2] == 0x46 and bytes[3] == 0x46 \
			and bytes[8] == 0x57 and bytes[9] == 0x45 and bytes[10] == 0x42 and bytes[11] == 0x50:
		return "image/webp"
	return ""

static func normalize_mime(mime: String, data: PackedByteArray) -> String:
	var m := mime.strip_edges().to_lower()
	match m:
		"jpg", "jpeg", "image/jpg", "image/jpeg", "image/pjpeg":
			return "image/jpeg"
		"png", "image/png":
			return "image/png"
		"webp", "image/webp":
			return "image/webp"
	return sniff_image_mime(data)
