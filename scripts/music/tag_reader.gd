# scripts/music/tag_reader.gd
class_name TagReader
extends RefCounted

## Header-only metadata reader. Contract (same as Spotify Replica's TagWriter):
## best-effort, NEVER throws, a missing tag is fine.
##
##   read_raw(path)            file -> raw tag fields (no fallbacks), cacheable
##   resolve(raw, rel, ...)    raw + file name + folder -> final display fields
##   read_cover(path)          lazily pulls the embedded picture at play time
##
## Raw fields: title, artist, album, album_artist, track_no, duration_s,
## has_cover, cover_mime. Only the first bytes of the file are read: the ID3v2
## tag (<= 2 MB read), the last 128 bytes (ID3v1), the first MP3 frames, or the
## first 1 MB + last 64 KB of an Ogg file.

const MAX_TAG_READ := 2 * 1024 * 1024
const OGG_HEAD := 1024 * 1024
const OGG_TAIL := 64 * 1024
const COVER_READ_CAP := 12 * 1024 * 1024

static func read_raw(path: String) -> Dictionary:
	var raw := _blank_raw()
	var ext := path.get_extension().to_lower()
	if not FileAccess.file_exists(path):
		return raw
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return raw
	var size := f.get_length()
	if size <= 0:
		f.close()
		return raw
	match ext:
		"mp3":
			_read_mp3(f, size, raw)
		"ogg", "oga":
			_read_ogg(f, size, raw)
		"wav":
			_read_wav(f, size, raw)
		"flac":
			var head := _range(f, 0, mini(size, OGG_HEAD))
			_merge_tags(raw, FlacParser.parse(head, false))
	f.close()
	return raw

static func _blank_raw() -> Dictionary:
	return {
		"title": "", "artist": "", "album": "", "album_artist": "",
		"track_no": 0, "duration_s": 0.0, "has_cover": false, "cover_mime": "",
	}

static func _read_mp3(f: FileAccess, size: int, raw: Dictionary) -> void:
	var header := _range(f, 0, mini(size, 10))
	var tag_total := Id3Parser.tag_total_size(header)
	var tags := {}
	if tag_total > 0:
		var tag_bytes := _range(f, 0, mini(tag_total, mini(size, MAX_TAG_READ)))
		tags = Id3Parser.parse(tag_bytes, false)
	var v1 := {}
	var audio_end := size
	if size > tag_total + 128:
		var trailer := _range(f, size - 128, 128)
		v1 = Id3Parser.parse_v1(trailer)
		if not v1.is_empty() or (trailer.size() >= 3 and trailer[0] == 0x54 and trailer[1] == 0x41 and trailer[2] == 0x47):
			audio_end = size - 128
	# v2 wins; v1 fills the gaps.
	_merge_tags(raw, tags)
	_merge_tags(raw, v1)
	if tags.has("length_ms") and float(raw["duration_s"]) <= 0.0:
		raw["duration_s"] = float(tags["length_ms"]) / 1000.0
	# Duration from the audio frames beats TLEN (often wrong / absent).
	var audio_start := tag_total
	var frames := _range(f, audio_start, mini(maxi(audio_end - audio_start, 0), 70000))
	var est := Mp3Info.estimate(frames, maxi(audio_end - audio_start, 0))
	if not est.is_empty():
		raw["duration_s"] = float(est["duration_s"])

static func _read_ogg(f: FileAccess, size: int, raw: Dictionary) -> void:
	var head := _range(f, 0, mini(size, OGG_HEAD))
	var tags := OggCommentParser.parse(head, false)
	_merge_tags(raw, tags)
	var rate: int = int(tags.get("sample_rate", 0))
	if rate > 0:
		var tail_len := mini(size, OGG_TAIL)
		var tail := _range(f, size - tail_len, tail_len)
		var granule := OggCommentParser.last_granule(tail)
		if granule > 0:
			raw["duration_s"] = float(granule) / float(rate)

static func _read_wav(f: FileAccess, size: int, raw: Dictionary) -> void:
	var head := _range(f, 0, mini(size, 4096))
	var h := MusicStreams.parse_wav_header(head, size)
	if not h.is_empty():
		raw["duration_s"] = float(h["duration_s"])

static func _merge_tags(raw: Dictionary, tags: Dictionary) -> void:
	for key in ["title", "artist", "album", "album_artist"]:
		if String(raw[key]).is_empty() and tags.has(key):
			raw[key] = String(tags[key])
	if int(raw["track_no"]) <= 0 and tags.has("track"):
		raw["track_no"] = int(tags["track"])
	if tags.has("has_cover") and not bool(raw["has_cover"]):
		raw["has_cover"] = bool(tags["has_cover"])
		raw["cover_mime"] = String(tags.get("cover_mime", ""))
	if float(raw["duration_s"]) <= 0.0 and tags.has("duration_s"):
		raw["duration_s"] = float(tags["duration_s"])

static func _range(f: FileAccess, offset: int, length: int) -> PackedByteArray:
	if length <= 0:
		return PackedByteArray()
	f.seek(offset)
	return f.get_buffer(length)

## Final display fields. Fallback chain per field: embedded tag -> file name
## ("Artist - Title", track-number stripped) -> stem / parent folder -> placeholder.
## `rel` is the path relative to the library root, forward slashes.
static func resolve(raw: Dictionary, rel: String) -> Dictionary:
	var stem := rel.get_file().get_basename()
	var folder := ""
	var parts := rel.split("/")
	if parts.size() >= 2:
		folder = parts[parts.size() - 2]
	var fn := FilenameParser.parse(stem)
	var title := String(raw.get("title", ""))
	var artist := String(raw.get("artist", ""))
	if artist.is_empty():
		artist = String(raw.get("album_artist", ""))
	if title.is_empty():
		title = String(fn["title"])
	if title.is_empty():
		title = stem
	if artist.is_empty():
		artist = String(fn["artist"])
	if artist.is_empty():
		artist = folder
	if artist.is_empty():
		artist = "Unknown Artist"
	var track_no: int = int(raw.get("track_no", 0))
	if track_no <= 0:
		track_no = int(fn["track"])
	return {
		"title": title,
		"artist": artist,
		"album": String(raw.get("album", "")),
		"track_no": track_no,
		"duration_s": float(raw.get("duration_s", 0.0)),
		"has_cover": bool(raw.get("has_cover", false)),
		"cover_mime": String(raw.get("cover_mime", "")),
	}

## Embedded picture of a file: { data: PackedByteArray, mime: String } or {}.
static func read_cover(path: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var size := f.get_length()
	var tags := {}
	match ext:
		"mp3":
			var total := Id3Parser.tag_total_size(_range(f, 0, mini(size, 10)))
			if total > 0:
				tags = Id3Parser.parse(_range(f, 0, mini(total, mini(size, COVER_READ_CAP))), true)
		"ogg", "oga":
			tags = OggCommentParser.parse(_range(f, 0, mini(size, COVER_READ_CAP)), true)
		"flac":
			tags = FlacParser.parse(_range(f, 0, mini(size, COVER_READ_CAP)), true)
	f.close()
	if tags.has("cover"):
		return {"data": tags["cover"], "mime": String(tags.get("cover_mime", ""))}
	return {}
