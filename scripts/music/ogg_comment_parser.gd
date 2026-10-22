# scripts/music/ogg_comment_parser.gd
class_name OggCommentParser
extends RefCounted

## Pure Ogg Vorbis header reader: PackedByteArray (the first <= 1 MB of the file)
## -> { title, artist, album, album_artist, track, sample_rate, channels,
## has_cover, cover_mime, [cover] }. Never throws; truncated input returns what
## was readable. Also hosts the Vorbis-comment block parser and the FLAC
## PICTURE block parser that FlacParser reuses.

const MAX_COVER_BYTES := 8 * 1024 * 1024

static func parse(bytes: PackedByteArray, want_cover: bool = false) -> Dictionary:
	var out := {}
	var packets := read_packets(bytes, 2)
	if packets.size() >= 1:
		var ident: PackedByteArray = packets[0]
		if ident.size() >= 16 and ident[0] == 1 and _is_vorbis(ident):
			out["channels"] = int(ident[11])
			out["sample_rate"] = _le32(ident, 12)
	if packets.size() >= 2:
		var comment: PackedByteArray = packets[1]
		if comment.size() >= 7 and comment[0] == 3 and _is_vorbis(comment):
			var tags := parse_comment_block(comment.slice(7), want_cover)
			for k in tags:
				out[k] = tags[k]
	return out

## Granule position of the last Ogg page found in `tail` (the final bytes of
## the file); 0 when none. Duration = granule / sample_rate.
static func last_granule(tail: PackedByteArray) -> int:
	var i := tail.size() - 14
	while i >= 0:
		if tail[i] == 0x4F and tail[i + 1] == 0x67 and tail[i + 2] == 0x67 and tail[i + 3] == 0x53:
			var lo := _le32(tail, i + 6)
			var hi := _le32(tail, i + 10)
			if hi >= 0x7FFFFFFF:
				return 0 # -1 / "no granule"
			return (hi << 32) | lo
		i -= 1
	return 0

## First `want` packets of the stream (a packet may span pages). A packet cut by
## the end of the buffer is returned partial so comments before the cut survive.
static func read_packets(bytes: PackedByteArray, want: int) -> Array:
	var packets: Array = []
	var cur := PackedByteArray()
	var pos := 0
	var n := bytes.size()
	while pos + 27 <= n and packets.size() < want:
		if bytes[pos] != 0x4F or bytes[pos + 1] != 0x67 or bytes[pos + 2] != 0x67 or bytes[pos + 3] != 0x53:
			break
		var segs: int = bytes[pos + 26]
		var table_end := pos + 27 + segs
		if table_end > n:
			break
		var data_pos := table_end
		for s in range(segs):
			var lace: int = bytes[pos + 27 + s]
			var take := mini(lace, n - data_pos)
			if take > 0:
				cur.append_array(bytes.slice(data_pos, data_pos + take))
			data_pos += lace
			if lace < 255:
				packets.append(cur)
				cur = PackedByteArray()
				if packets.size() >= want:
					return packets
			if data_pos > n:
				break
		if data_pos > n:
			# truncated page
			if cur.size() > 0 and packets.size() < want:
				packets.append(cur)
			return packets
		pos = data_pos
	if cur.size() > 0 and packets.size() < want:
		packets.append(cur)
	return packets

## Vorbis comment block WITHOUT the "\x03vorbis" prefix: vendor, count, KEY=VALUE.
static func parse_comment_block(block: PackedByteArray, want_cover: bool = false) -> Dictionary:
	var out := {}
	var n := block.size()
	if n < 8:
		return out
	var pos := 4 + _le32(block, 0)
	if pos + 4 > n:
		return out
	var count := _le32(block, pos)
	pos += 4
	var artists: Array[String] = []
	var best_type := -1
	for _i in range(count):
		if pos + 4 > n:
			break
		var clen := _le32(block, pos)
		pos += 4
		if clen < 0 or pos + clen > n:
			break # truncated comment (large embedded art); stop here
		var entry := block.slice(pos, pos + clen).get_string_from_utf8()
		pos += clen
		var eq := entry.find("=")
		if eq <= 0:
			continue
		var key := entry.substr(0, eq).to_upper()
		var value := entry.substr(eq + 1).strip_edges()
		match key:
			"TITLE":
				if not out.has("title") and not value.is_empty():
					out["title"] = value
			"ARTIST":
				if not value.is_empty():
					artists.append(value)
			"ALBUMARTIST":
				if not out.has("album_artist") and not value.is_empty():
					out["album_artist"] = value
			"ALBUM":
				if not out.has("album") and not value.is_empty():
					out["album"] = value
			"TRACKNUMBER":
				var t := int(value.get_slice("/", 0).strip_edges())
				if t > 0 and not out.has("track"):
					out["track"] = t
			"METADATA_BLOCK_PICTURE":
				var pic := _picture_from_base64(value, want_cover)
				if not pic.is_empty():
					var ptype: int = pic["type"]
					if best_type < 0 or (ptype == 3 and best_type != 3):
						best_type = ptype
						out["has_cover"] = true
						out["cover_mime"] = pic["mime"]
						if want_cover:
							out["cover"] = pic["data"]
	if not artists.is_empty():
		out["artist"] = ", ".join(artists)
	return out

## FLAC PICTURE block body (also the payload of METADATA_BLOCK_PICTURE after
## base64): { type, mime, data }. With want_data false, `data` is left empty
## (the header alone identifies the picture).
static func parse_flac_picture(raw: PackedByteArray, want_data: bool = true) -> Dictionary:
	var n := raw.size()
	if n < 32:
		return {}
	var ptype := _be32(raw, 0)
	var mime_len := _be32(raw, 4)
	var pos := 8
	if mime_len < 0 or mime_len > 128 or pos + mime_len + 4 > n:
		return {}
	var mime_raw := raw.slice(pos, pos + mime_len).get_string_from_ascii()
	pos += mime_len
	var desc_len := _be32(raw, pos)
	pos += 4
	if desc_len < 0 or pos + desc_len + 20 > n:
		return {}
	pos += desc_len + 16 # width, height, depth, colors
	var data_len := _be32(raw, pos)
	pos += 4
	if data_len <= 0 or data_len > MAX_COVER_BYTES:
		return {}
	var data := PackedByteArray()
	if want_data:
		if pos + data_len > n:
			return {}
		data = raw.slice(pos, pos + data_len)
	var head := raw.slice(pos, mini(pos + 16, n))
	var mime := MusicFormats.normalize_mime(mime_raw, head)
	if mime.is_empty():
		return {}
	return {"type": ptype, "mime": mime, "data": data}

static func _picture_from_base64(value: String, want_data: bool) -> Dictionary:
	if value.is_empty():
		return {}
	if want_data:
		return parse_flac_picture(Marshalls.base64_to_raw(value), true)
	# Header only: decode a prefix (multiple of 4 chars) that covers the fixed
	# fields + mime + description + the first image bytes.
	var prefix := value.substr(0, mini(value.length(), 2048))
	prefix = prefix.substr(0, prefix.length() - (prefix.length() % 4))
	var raw := Marshalls.base64_to_raw(prefix)
	# data_len is checked against the declared size, not the truncated prefix.
	return _picture_header_only(raw)

static func _picture_header_only(raw: PackedByteArray) -> Dictionary:
	var n := raw.size()
	if n < 32:
		return {}
	var ptype := _be32(raw, 0)
	var mime_len := _be32(raw, 4)
	if mime_len < 0 or mime_len > 128 or 8 + mime_len + 4 > n:
		return {}
	var mime_raw := raw.slice(8, 8 + mime_len).get_string_from_ascii()
	var mime := MusicFormats.normalize_mime(mime_raw, PackedByteArray())
	if mime.is_empty():
		var desc_len := _be32(raw, 8 + mime_len)
		var data_at := 8 + mime_len + 4 + desc_len + 20
		if desc_len >= 0 and data_at < n:
			mime = MusicFormats.sniff_image_mime(raw.slice(data_at))
	if mime.is_empty():
		return {}
	return {"type": ptype, "mime": mime, "data": PackedByteArray()}

static func _is_vorbis(p: PackedByteArray) -> bool:
	return p.size() >= 7 and p[1] == 0x76 and p[2] == 0x6F and p[3] == 0x72 \
		and p[4] == 0x62 and p[5] == 0x69 and p[6] == 0x73

static func _le32(b: PackedByteArray, at: int) -> int:
	if at < 0 or at + 4 > b.size():
		return 0
	return int(b[at]) | (int(b[at + 1]) << 8) | (int(b[at + 2]) << 16) | (int(b[at + 3]) << 24)

static func _be32(b: PackedByteArray, at: int) -> int:
	if at < 0 or at + 4 > b.size():
		return 0
	return (int(b[at]) << 24) | (int(b[at + 1]) << 16) | (int(b[at + 2]) << 8) | int(b[at + 3])
