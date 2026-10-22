# scripts/music/music_streams.gd
class_name MusicStreams
extends RefCounted

## Builds a playable AudioStream from a file path / byte buffer. MP3 and Ogg keep
## the ENCODED bytes in memory and are decoded on the fly by the mixer; WAV is
## wrapped as 16-bit/8-bit PCM. Returns null for anything else (the caller marks
## the track bad). Safe to call from a worker thread.

const MAX_FILE_BYTES := 256 * 1024 * 1024

static func load_stream(path: String) -> AudioStream:
	var ext := path.get_extension().to_lower()
	if MusicFormats.kind_for(ext) != MusicFormats.Kind.NATIVE:
		return null
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var size := f.get_length()
	if size <= 0 or size > MAX_FILE_BYTES:
		f.close()
		return null
	var bytes := f.get_buffer(size)
	f.close()
	return stream_from_bytes(ext, bytes)

static func stream_from_bytes(ext: String, bytes: PackedByteArray) -> AudioStream:
	match ext.to_lower():
		"mp3":
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes
			return mp3 if mp3.get_length() > 0.0 else null
		"ogg", "oga":
			var ogg := AudioStreamOggVorbis.load_from_buffer(bytes)
			return ogg
		"wav":
			return wav_from_bytes(bytes)
	return null

## Parses the RIFF header: { channels, rate, bits, data_offset, data_size, duration_s }.
## `file_size` clamps a lying / streaming-style data chunk length.
static func parse_wav_header(bytes: PackedByteArray, file_size: int = -1) -> Dictionary:
	var n := bytes.size()
	if n < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return {}
	var pos := 12
	var fmt := {}
	while pos + 8 <= n:
		var cid := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var csize := _le32(bytes, pos + 4)
		var body := pos + 8
		if cid == "fmt " and body + 16 <= n:
			fmt = {
				"format": _le16(bytes, body),
				"channels": _le16(bytes, body + 2),
				"rate": _le32(bytes, body + 4),
				"bits": _le16(bytes, body + 14),
			}
		elif cid == "data":
			if fmt.is_empty():
				return {}
			var avail := (file_size if file_size > 0 else n) - body
			var dsize := mini(csize, avail) if csize > 0 else avail
			var bps: int = int(fmt["channels"]) * (int(fmt["bits"]) / 8)
			if bps <= 0 or int(fmt["rate"]) <= 0:
				return {}
			fmt["data_offset"] = body
			fmt["data_size"] = maxi(dsize, 0)
			fmt["duration_s"] = float(maxi(dsize, 0)) / float(bps * int(fmt["rate"]))
			return fmt
		pos = body + csize + (csize & 1)
	return {}

static func wav_from_bytes(bytes: PackedByteArray) -> AudioStream:
	var h := parse_wav_header(bytes, bytes.size())
	if h.is_empty():
		return null
	var fmt_tag: int = h["format"]
	var bits: int = h["bits"]
	var channels: int = h["channels"]
	if (fmt_tag != 1 and fmt_tag != 0xFFFE) or (bits != 16 and bits != 8) or channels < 1 or channels > 2:
		return null
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS if bits == 16 else AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = int(h["rate"])
	wav.stereo = channels == 2
	var off: int = h["data_offset"]
	var size: int = h["data_size"]
	var pcm := bytes.slice(off, off + size)
	if bits == 8:
		# RIFF 8-bit is unsigned; Godot's FORMAT_8_BITS is signed.
		for i in range(pcm.size()):
			pcm[i] = (int(pcm[i]) - 128) & 0xFF
	wav.data = pcm
	return wav

## Tiny synthetic mono 16-bit sine WAV (used by the tests and the self-check).
static func make_sine_wav(seconds: float, hz: float = 440.0, rate: int = 8000) -> PackedByteArray:
	var frames := int(seconds * float(rate))
	var pcm := PackedByteArray()
	pcm.resize(frames * 2)
	for i in range(frames):
		var s := int(sin(TAU * hz * float(i) / float(rate)) * 12000.0)
		pcm.encode_s16(i * 2, s)
	var out := PackedByteArray()
	out.append_array("RIFF".to_ascii_buffer())
	out.append_array(_u32(36 + pcm.size()))
	out.append_array("WAVEfmt ".to_ascii_buffer())
	out.append_array(_u32(16))
	out.append_array(_u16(1))
	out.append_array(_u16(1))
	out.append_array(_u32(rate))
	out.append_array(_u32(rate * 2))
	out.append_array(_u16(2))
	out.append_array(_u16(16))
	out.append_array("data".to_ascii_buffer())
	out.append_array(_u32(pcm.size()))
	out.append_array(pcm)
	return out

static func _u32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, v)
	return b

static func _u16(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(2)
	b.encode_u16(0, v)
	return b

static func _le16(b: PackedByteArray, at: int) -> int:
	if at + 2 > b.size():
		return 0
	return int(b[at]) | (int(b[at + 1]) << 8)

static func _le32(b: PackedByteArray, at: int) -> int:
	if at + 4 > b.size():
		return 0
	return int(b[at]) | (int(b[at + 1]) << 8) | (int(b[at + 2]) << 16) | (int(b[at + 3]) << 24)
