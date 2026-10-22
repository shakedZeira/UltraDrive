# scripts/music/id3_parser.gd
class_name Id3Parser
extends RefCounted

## Pure ID3v2.2 / 2.3 / 2.4 (+ ID3v1 trailer) reader: PackedByteArray -> Dictionary.
## Never throws; returns whatever it found ({} for non-ID3 / garbage input).
##
## Result keys (only those present in the tag): title, artist, album,
## album_artist, track (int), length_ms (int), version (int), has_cover (bool),
## cover_mime (String) and, when want_cover is true, cover (PackedByteArray).
## Text encodings 0 (Latin-1), 1 (UTF-16 + BOM), 2 (UTF-16BE), 3 (UTF-8);
## unsynchronisation, extended headers and per-frame flags are honoured.
## Multi-value text (NUL separated) is joined with ", ".

const MAX_COVER_BYTES := 8 * 1024 * 1024

## Stand-in for NUL inside decoded text (Godot strings cannot hold a real NUL).
const SEP := "	"

const V22_IDS := {
	"TT2": "TIT2", "TP1": "TPE1", "TP2": "TPE2", "TAL": "TALB",
	"TRK": "TRCK", "TLE": "TLEN", "PIC": "APIC",
}

## Total bytes of the tag (10 byte header + body [+ footer]) given at least the
## first 10 bytes of the file; 0 when there is no ID3v2 tag.
static func tag_total_size(header: PackedByteArray) -> int:
	if header.size() < 10:
		return 0
	if header[0] != 0x49 or header[1] != 0x44 or header[2] != 0x33:
		return 0
	var ver: int = header[3]
	if ver < 2 or ver > 4:
		return 0
	var total := 10 + _syncsafe(header, 6)
	if ver == 4 and (header[5] & 0x10) != 0:
		total += 10
	return total

static func parse(bytes: PackedByteArray, want_cover: bool = false) -> Dictionary:
	var out := {}
	if tag_total_size(bytes) <= 0:
		return out
	var ver: int = bytes[3]
	var flags: int = bytes[5]
	var declared := _syncsafe(bytes, 6)
	var body := bytes.slice(10, mini(10 + declared, bytes.size()))
	out["version"] = ver
	if ver < 4 and (flags & 0x80) != 0:
		body = undo_unsync(body)
	var pos := 0
	# Extended header (v2.3: size excludes itself; v2.4: syncsafe, includes itself).
	if ver >= 3 and (flags & 0x40) != 0 and body.size() >= 4:
		pos = (4 + _be32(body, 0)) if ver == 3 else _syncsafe(body, 0)
	var id_len := 3 if ver == 2 else 4
	var hdr := 6 if ver == 2 else 10
	var best_cover_type := -1
	while pos + hdr <= body.size():
		if body[pos] == 0:
			break # padding
		var raw_id := body.slice(pos, pos + id_len).get_string_from_ascii()
		if not _valid_id(raw_id):
			break
		var size := 0
		var fflags := 0
		if ver == 2:
			size = (int(body[pos + 3]) << 16) | (int(body[pos + 4]) << 8) | int(body[pos + 5])
		elif ver == 3:
			size = _be32(body, pos + 4)
			fflags = (int(body[pos + 8]) << 8) | int(body[pos + 9])
		else:
			size = _syncsafe(body, pos + 4)
			fflags = (int(body[pos + 8]) << 8) | int(body[pos + 9])
		var start := pos + hdr
		if size < 0 or start + size > body.size():
			break # truncated frame: keep what we have
		pos = start + size
		var data := body.slice(start, start + size)
		var f2 := fflags & 0xFF
		if ver == 4:
			if (f2 & 0x0C) != 0:
				continue # compressed / encrypted
			if (f2 & 0x02) != 0 or (flags & 0x80) != 0:
				data = undo_unsync(data)
			var off := 0
			if (f2 & 0x40) != 0:
				off += 1
			if (f2 & 0x01) != 0:
				off += 4
			if off > 0:
				data = data.slice(off) if data.size() > off else PackedByteArray()
		elif ver == 3:
			if (f2 & 0xC0) != 0:
				continue
			if (f2 & 0x20) != 0:
				data = data.slice(1) if data.size() > 1 else PackedByteArray()
		var id: String = V22_IDS.get(raw_id, raw_id) if ver == 2 else raw_id
		match id:
			"TIT2":
				_set_once(out, "title", _text_frame(data))
			"TPE1":
				_set_once(out, "artist", _text_frame(data))
			"TPE2":
				_set_once(out, "album_artist", _text_frame(data))
			"TALB":
				_set_once(out, "album", _text_frame(data))
			"TRCK":
				var t := _text_frame(data)
				if not out.has("track") and not t.is_empty():
					var n := int(t.get_slice("/", 0).strip_edges())
					if n > 0:
						out["track"] = n
			"TLEN":
				var ms := int(_text_frame(data).strip_edges())
				if ms > 0 and not out.has("length_ms"):
					out["length_ms"] = ms
			"APIC":
				var pic := _parse_apic(data, ver == 2)
				if not pic.is_empty():
					var ptype: int = pic["type"]
					# Prefer picture type 3 (front cover), else the first one.
					var better: bool = best_cover_type < 0 or (ptype == 3 and best_cover_type != 3)
					if better:
						best_cover_type = ptype
						out["has_cover"] = true
						out["cover_mime"] = pic["mime"]
						if want_cover:
							out["cover"] = pic["data"]
	return out

## ID3v1 trailer (the last 128 bytes of the file). {} when absent.
static func parse_v1(trailer: PackedByteArray) -> Dictionary:
	var out := {}
	if trailer.size() < 128:
		return out
	var t := trailer.slice(trailer.size() - 128)
	if t[0] != 0x54 or t[1] != 0x41 or t[2] != 0x47:
		return out
	var title := _latin1_trim(t, 3, 30)
	var artist := _latin1_trim(t, 33, 30)
	var album := _latin1_trim(t, 63, 30)
	if not title.is_empty():
		out["title"] = title
	if not artist.is_empty():
		out["artist"] = artist
	if not album.is_empty():
		out["album"] = album
	# ID3v1.1: byte 125 == 0 and byte 126 != 0 -> track number.
	if t[125] == 0 and t[126] != 0:
		out["track"] = int(t[126])
	return out

# ---------------------------------------------------------------------------
# Text decoding.
# ---------------------------------------------------------------------------

static func decode_text(enc: int, bytes: PackedByteArray) -> String:
	match enc:
		1:
			if bytes.size() >= 2 and bytes[0] == 0xFE and bytes[1] == 0xFF:
				return _utf16(bytes, 2, true)
			if bytes.size() >= 2 and bytes[0] == 0xFF and bytes[1] == 0xFE:
				return _utf16(bytes, 2, false)
			return _utf16(bytes, 0, false)
		2:
			var from := 2 if (bytes.size() >= 2 and bytes[0] == 0xFE and bytes[1] == 0xFF) else 0
			return _utf16(bytes, from, true)
		3:
			var fixed := bytes.duplicate()
			for i in range(fixed.size()):
				if fixed[i] == 0:
					fixed[i] = SEP.unicode_at(0)
			return fixed.get_string_from_utf8()
	return _latin1(bytes, 0, bytes.size())

static func undo_unsync(bytes: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	var i := 0
	var n := bytes.size()
	while i < n:
		var b: int = bytes[i]
		out.append(b)
		if b == 0xFF and i + 1 < n and bytes[i + 1] == 0x00:
			i += 1
		i += 1
	return out

static func _text_frame(data: PackedByteArray) -> String:
	if data.size() < 2:
		return ""
	var s := decode_text(int(data[0]), data.slice(1))
	var parts := s.split(SEP, false)
	var cleaned: Array[String] = []
	for p in parts:
		var v := p.strip_edges()
		if not v.is_empty():
			cleaned.append(v)
	return ", ".join(cleaned)

static func _parse_apic(data: PackedByteArray, v22: bool) -> Dictionary:
	if data.size() < 6:
		return {}
	var enc: int = data[0]
	var i := 1
	var mime := ""
	if v22:
		mime = _latin1(data, 1, 3)
		i = 4
	else:
		var nul := _find_nul(data, i, false)
		if nul < 0:
			return {}
		mime = _latin1(data, i, nul - i)
		i = nul + 1
	if i >= data.size():
		return {}
	var ptype: int = data[i]
	i += 1
	# Description: NUL-terminated in the frame encoding (UTF-16: double NUL).
	var wide := enc == 1 or enc == 2
	var dnul := _find_nul(data, i, wide)
	if dnul < 0:
		return {}
	i = dnul + (2 if wide else 1)
	if i > data.size():
		return {}
	var pic := data.slice(i)
	if pic.is_empty() or pic.size() > MAX_COVER_BYTES:
		return {}
	var m := MusicFormats.normalize_mime(mime, pic)
	if m.is_empty():
		return {}
	return {"type": ptype, "mime": m, "data": pic}

static func _find_nul(data: PackedByteArray, from: int, wide: bool) -> int:
	var i := from
	if wide:
		while i + 1 < data.size():
			if data[i] == 0 and data[i + 1] == 0:
				return i
			i += 2
		return -1
	while i < data.size():
		if data[i] == 0:
			return i
		i += 1
	return -1

static func _set_once(out: Dictionary, key: String, value: String) -> void:
	if value.is_empty() or out.has(key):
		return
	out[key] = value

static func _valid_id(id: String) -> bool:
	if id.length() < 3:
		return false
	for i in range(id.length()):
		var c := id.unicode_at(i)
		var ok := (c >= 48 and c <= 57) or (c >= 65 and c <= 90)
		if not ok:
			return false
	return true

static func _latin1(bytes: PackedByteArray, from: int, count: int) -> String:
	var s := ""
	var end := mini(from + count, bytes.size())
	for i in range(from, end):
		var b: int = bytes[i]
		s += SEP if b == 0 else String.chr(b)
	return s

static func _latin1_trim(bytes: PackedByteArray, from: int, count: int) -> String:
	var s := ""
	for i in range(from, mini(from + count, bytes.size())):
		var b: int = bytes[i]
		if b == 0:
			break
		s += String.chr(b)
	return s.strip_edges()

static func _utf16(bytes: PackedByteArray, from: int, big_endian: bool) -> String:
	var s := ""
	var i := from
	var n := bytes.size()
	while i + 1 < n:
		var u: int = (int(bytes[i]) << 8 | int(bytes[i + 1])) if big_endian else (int(bytes[i + 1]) << 8 | int(bytes[i]))
		i += 2
		if u >= 0xD800 and u <= 0xDBFF and i + 1 < n:
			var lo: int = (int(bytes[i]) << 8 | int(bytes[i + 1])) if big_endian else (int(bytes[i + 1]) << 8 | int(bytes[i]))
			if lo >= 0xDC00 and lo <= 0xDFFF:
				i += 2
				u = 0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00)
		s += SEP if u == 0 else String.chr(u)
	return s

static func _syncsafe(b: PackedByteArray, at: int) -> int:
	if at + 4 > b.size():
		return 0
	return ((int(b[at]) & 0x7F) << 21) | ((int(b[at + 1]) & 0x7F) << 14) | ((int(b[at + 2]) & 0x7F) << 7) | (int(b[at + 3]) & 0x7F)

static func _be32(b: PackedByteArray, at: int) -> int:
	if at + 4 > b.size():
		return 0
	return (int(b[at]) << 24) | (int(b[at + 1]) << 16) | (int(b[at + 2]) << 8) | int(b[at + 3])
