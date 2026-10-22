# tests/suites/music_test_util.gd
class_name MusicTestUtil
extends RefCounted

## Byte builders for the music tests. NOTHING binary is committed and no real
## music is used: ID3 tags, Ogg pages, FLAC blocks, a fake MP3 frame and tiny
## sine WAVs are generated here, in code.

# --- ID3 ---------------------------------------------------------------

static func u32be(n: int) -> PackedByteArray:
	return PackedByteArray([(n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF])

static func syncsafe(n: int) -> PackedByteArray:
	return PackedByteArray([(n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F])

static func u32le(n: int) -> PackedByteArray:
	return PackedByteArray([n & 0xFF, (n >> 8) & 0xFF, (n >> 16) & 0xFF, (n >> 24) & 0xFF])

static func encode_text(enc: int, s: String) -> PackedByteArray:
	var out := PackedByteArray()
	match enc:
		0:
			for i in range(s.length()):
				out.append(s.unicode_at(i) & 0xFF)
		1, 2:
			if enc == 1:
				out.append(0xFF)
				out.append(0xFE)
			for i in range(s.length()):
				var u := s.unicode_at(i)
				var units: Array[int] = []
				if u > 0xFFFF:
					var v := u - 0x10000
					units.append(0xD800 + (v >> 10))
					units.append(0xDC00 + (v & 0x3FF))
				else:
					units.append(u)
				for unit in units:
					if enc == 1:
						out.append(unit & 0xFF)
						out.append((unit >> 8) & 0xFF)
					else:
						out.append((unit >> 8) & 0xFF)
						out.append(unit & 0xFF)
		3:
			out = s.to_utf8_buffer()
	return out

## encoded text + the terminator the encoding needs
static func terminated(enc: int, s: String) -> PackedByteArray:
	var out := encode_text(enc, s)
	out.append(0)
	if enc == 1 or enc == 2:
		out.append(0)
	return out

static func text_payload(enc: int, s: String) -> PackedByteArray:
	var out := PackedByteArray([enc])
	out.append_array(encode_text(enc, s))
	return out

static func apic_payload(mime: String, pic_type: int, data: PackedByteArray, v22: bool = false) -> PackedByteArray:
	var out := PackedByteArray([0])
	if v22:
		out.append_array(mime.to_ascii_buffer())
	else:
		out.append_array(mime.to_ascii_buffer())
		out.append(0)
	out.append(pic_type)
	out.append(0) # empty description
	out.append_array(data)
	return out

static func frame(version: int, id: String, payload: PackedByteArray, flags: int = 0) -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array(id.to_ascii_buffer())
	if version == 2:
		out.append((payload.size() >> 16) & 0xFF)
		out.append((payload.size() >> 8) & 0xFF)
		out.append(payload.size() & 0xFF)
	elif version == 3:
		out.append_array(u32be(payload.size()))
		out.append((flags >> 8) & 0xFF)
		out.append(flags & 0xFF)
	else:
		out.append_array(syncsafe(payload.size()))
		out.append((flags >> 8) & 0xFF)
		out.append(flags & 0xFF)
	out.append_array(payload)
	return out

static func id3_tag(version: int, frames: Array, tag_flags: int = 0, padding: int = 0, extra_header: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	var body := PackedByteArray()
	body.append_array(extra_header)
	for f in frames:
		body.append_array(f)
	for _i in range(padding):
		body.append(0)
	if version < 4 and (tag_flags & 0x80) != 0:
		body = unsync(body)
	var out := PackedByteArray([0x49, 0x44, 0x33, version, 0, tag_flags])
	out.append_array(syncsafe(body.size()))
	out.append_array(body)
	return out

static func unsync(bytes: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	for i in range(bytes.size()):
		out.append(bytes[i])
		if bytes[i] == 0xFF and (i + 1 >= bytes.size() or bytes[i + 1] == 0x00 or (bytes[i + 1] & 0xE0) == 0xE0):
			out.append(0)
	return out

static func id3v1(title: String, artist: String, album: String, track: int = 0) -> PackedByteArray:
	var out := PackedByteArray([0x54, 0x41, 0x47])
	for field in [[title, 30], [artist, 30], [album, 30]]:
		var b := encode_text(0, field[0])
		b.resize(field[1])
		out.append_array(b)
	var year := PackedByteArray([0x32, 0x30, 0x32, 0x36])
	out.append_array(year)
	var comment := PackedByteArray()
	comment.resize(30)
	if track > 0:
		comment[28] = 0
		comment[29] = track
	out.append_array(comment)
	out.append(255) # genre
	return out

# --- images ------------------------------------------------------------

static func png_bytes(w: int = 8, h: int = 8, color: Color = Color(0.8, 0.2, 0.2)) -> PackedByteArray:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(color)
	return img.save_png_to_buffer()

static func jpg_bytes(w: int = 8, h: int = 8, color: Color = Color(0.2, 0.6, 0.9)) -> PackedByteArray:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(color)
	return img.save_jpg_to_buffer(0.9)

# --- MP3 (a header-valid frame with an Info tag; not decodable audio) -----

static func fake_mp3_frames(info_frames: int, extra_cbr_frames: int = 0) -> PackedByteArray:
	# MPEG-1 Layer III, 128 kbps, 44.1 kHz, stereo, no padding: 417-byte frames.
	var out := PackedByteArray()
	var first := PackedByteArray([0xFF, 0xFB, 0x90, 0x00])
	first.resize(417)
	var x := 4 + 32
	first[x] = 0x49
	first[x + 1] = 0x6E
	first[x + 2] = 0x66
	first[x + 3] = 0x6F
	var flags := u32be(1)
	for i in range(4):
		first[x + 4 + i] = flags[i]
	var frames := u32be(info_frames)
	for i in range(4):
		first[x + 8 + i] = frames[i]
	out.append_array(first)
	for _k in range(extra_cbr_frames):
		var f := PackedByteArray([0xFF, 0xFB, 0x90, 0x00])
		f.resize(417)
		out.append_array(f)
	return out

# --- Ogg ---------------------------------------------------------------

static func ogg_page(packet_chunk: PackedByteArray, header_type: int, granule: int, seq: int, last_chunk: bool) -> PackedByteArray:
	var lacing := PackedByteArray()
	var remaining := packet_chunk.size()
	while remaining >= 255:
		lacing.append(255)
		remaining -= 255
	if last_chunk:
		lacing.append(remaining) # terminates the packet (may be 0)
	var out := PackedByteArray([0x4F, 0x67, 0x67, 0x53, 0, header_type])
	for i in range(8):
		out.append((granule >> (8 * i)) & 0xFF)
	out.append_array(u32le(1)) # serial
	out.append_array(u32le(seq))
	out.append_array(u32le(0)) # crc (not verified)
	out.append(lacing.size())
	out.append_array(lacing)
	out.append_array(packet_chunk)
	return out

## One logical packet split over as many pages as needed (255 segments each).
static func ogg_pages_for_packet(packet: PackedByteArray, seq_start: int, granule: int = 0, first_type: int = 0) -> PackedByteArray:
	var out := PackedByteArray()
	var chunk_max := 255 * 255
	var pos := 0
	var seq := seq_start
	var first := true
	while true:
		var take := mini(chunk_max, packet.size() - pos)
		var is_last := pos + take >= packet.size()
		var chunk := packet.slice(pos, pos + take)
		out.append_array(ogg_page(chunk, first_type if first else 1, granule if is_last else -1, seq, is_last))
		pos += take
		seq += 1
		first = false
		if is_last:
			break
	return out

static func vorbis_id_packet(rate: int = 44100, channels: int = 2) -> PackedByteArray:
	var p := PackedByteArray([1])
	p.append_array("vorbis".to_ascii_buffer())
	p.append_array(u32le(0))
	p.append(channels)
	p.append_array(u32le(rate))
	p.append_array(u32le(0))
	p.append_array(u32le(128000))
	p.append_array(u32le(0))
	p.append(0xB8)
	p.append(1)
	return p

static func comment_block(entries: Array, with_prefix: bool = true) -> PackedByteArray:
	var p := PackedByteArray()
	if with_prefix:
		p.append(3)
		p.append_array("vorbis".to_ascii_buffer())
	var vendor := "UltraDrive test".to_utf8_buffer()
	p.append_array(u32le(vendor.size()))
	p.append_array(vendor)
	p.append_array(u32le(entries.size()))
	for e in entries:
		var b := String(e).to_utf8_buffer()
		p.append_array(u32le(b.size()))
		p.append_array(b)
	if with_prefix:
		p.append(1) # framing bit
	return p

static func flac_picture_block(mime: String, pic_type: int, data: PackedByteArray) -> PackedByteArray:
	var p := PackedByteArray()
	p.append_array(u32be(pic_type))
	var m := mime.to_ascii_buffer()
	p.append_array(u32be(m.size()))
	p.append_array(m)
	p.append_array(u32be(0)) # description length
	p.append_array(u32be(8))
	p.append_array(u32be(8))
	p.append_array(u32be(24))
	p.append_array(u32be(0))
	p.append_array(u32be(data.size()))
	p.append_array(data)
	return p

## A parseable Ogg Vorbis HEADER set (not decodable audio) + a closing page with
## the given end granule.
static func ogg_vorbis(entries: Array, rate: int = 44100, end_granule: int = 0) -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array(ogg_pages_for_packet(vorbis_id_packet(rate), 0, 0, 2))
	out.append_array(ogg_pages_for_packet(comment_block(entries), 1, 0))
	if end_granule > 0:
		out.append_array(ogg_page(PackedByteArray([0, 0, 0, 0]), 4, end_granule, 2, true))
	return out

static func flac_file(entries: Array, rate: int = 44100, total_samples: int = 441000, picture: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	var out := PackedByteArray([0x66, 0x4C, 0x61, 0x43])
	var info := PackedByteArray()
	info.resize(34)
	info[0] = 0x10
	info[2] = 0x10
	var packed: int = (rate << 44) | (1 << 41) | (15 << 36) | total_samples
	for i in range(8):
		info[10 + i] = (packed >> (8 * (7 - i))) & 0xFF
	out.append(0x00) # STREAMINFO, not last
	out.append_array(PackedByteArray([0, 0, 34]))
	out.append_array(info)
	var vc := comment_block(entries, false)
	var last_is_vc := picture.is_empty()
	out.append(4 | (0x80 if last_is_vc else 0))
	out.append_array(PackedByteArray([(vc.size() >> 16) & 0xFF, (vc.size() >> 8) & 0xFF, vc.size() & 0xFF]))
	out.append_array(vc)
	if not picture.is_empty():
		out.append(6 | 0x80)
		out.append_array(PackedByteArray([(picture.size() >> 16) & 0xFF, (picture.size() >> 8) & 0xFF, picture.size() & 0xFF]))
		out.append_array(picture)
	return out

# --- files -------------------------------------------------------------

static func temp_dir(tag: String) -> String:
	var path := "user://music_test_%s_%d" % [tag, Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(path)
	return path

static func write_file(path: String, data: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()

static func remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var child := path + "/" + name
		if dir.current_is_dir():
			remove_dir(child)
		else:
			DirAccess.remove_absolute(child)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
