# scripts/music/flac_parser.gd
class_name FlacParser
extends RefCounted

## FLAC cannot be decoded at runtime; this only labels FLAC files nicely in the
## "needs conversion" list. Reads STREAMINFO (rate, samples -> duration),
## VORBIS_COMMENT and PICTURE from the first <= 1 MB. Never throws.

static func parse(bytes: PackedByteArray, want_cover: bool = false) -> Dictionary:
	var out := {}
	var n := bytes.size()
	if n < 8 or bytes[0] != 0x66 or bytes[1] != 0x4C or bytes[2] != 0x61 or bytes[3] != 0x43:
		return out
	var pos := 4
	var best_type := -1
	while pos + 4 <= n:
		var header: int = bytes[pos]
		var last := (header & 0x80) != 0
		var btype := header & 0x7F
		var length := (int(bytes[pos + 1]) << 16) | (int(bytes[pos + 2]) << 8) | int(bytes[pos + 3])
		pos += 4
		var end := mini(pos + length, n)
		var block := bytes.slice(pos, end)
		var complete := pos + length <= n
		match btype:
			0:
				if block.size() >= 18:
					var rate := (int(block[10]) << 12) | (int(block[11]) << 4) | (int(block[12]) >> 4)
					var total := ((int(block[13]) & 0x0F) << 32) | (int(block[14]) << 24) \
						| (int(block[15]) << 16) | (int(block[16]) << 8) | int(block[17])
					out["sample_rate"] = rate
					if rate > 0 and total > 0:
						out["duration_s"] = float(total) / float(rate)
			4:
				var tags := OggCommentParser.parse_comment_block(block, want_cover)
				for k in tags:
					if k == "has_cover" or k == "cover_mime" or k == "cover":
						continue
					out[k] = tags[k]
			6:
				if complete or not want_cover:
					var pic := OggCommentParser.parse_flac_picture(block, want_cover)
					if not pic.is_empty():
						var ptype: int = pic["type"]
						if best_type < 0 or (ptype == 3 and best_type != 3):
							best_type = ptype
							out["has_cover"] = true
							out["cover_mime"] = pic["mime"]
							if want_cover:
								out["cover"] = pic["data"]
		if last or not complete:
			break
		pos = end
	return out
