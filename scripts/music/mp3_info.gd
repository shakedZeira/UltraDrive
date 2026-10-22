# scripts/music/mp3_info.gd
class_name Mp3Info
extends RefCounted

## Duration of an MP3 without decoding: Xing/Info frame count when present,
## else a constant-bitrate estimate from the first frame header. Pure.

const BITRATES_V1_L3: Array[int] = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0]
const BITRATES_V2_L3: Array[int] = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0]
const BITRATES_V1_L2: Array[int] = [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 0]
const RATES_V1: Array[int] = [44100, 48000, 32000, 0]
const RATES_V2: Array[int] = [22050, 24000, 16000, 0]
const RATES_V25: Array[int] = [11025, 12000, 8000, 0]

## bytes = a buffer that starts at (or shortly before) the first audio frame;
## audio_bytes = file size minus the ID3v2 tag (and v1 trailer, if known).
## Returns { duration_s, bitrate_kbps, sample_rate, vbr } or {}.
static func estimate(bytes: PackedByteArray, audio_bytes: int) -> Dictionary:
	var n := bytes.size()
	var limit := mini(n - 4, 65536)
	var i := 0
	while i < limit:
		if bytes[i] == 0xFF and (bytes[i + 1] & 0xE0) == 0xE0:
			var info := _frame(bytes, i, audio_bytes)
			if not info.is_empty():
				return info
		i += 1
	return {}

static func _frame(b: PackedByteArray, at: int, audio_bytes: int) -> Dictionary:
	var b1: int = b[at + 1]
	var b2: int = b[at + 2]
	var b3: int = b[at + 3]
	var ver_bits := (b1 >> 3) & 3 # 0 = 2.5, 2 = 2, 3 = 1, 1 = reserved
	var layer_bits := (b1 >> 1) & 3 # 1 = III, 2 = II, 3 = I, 0 = reserved
	if ver_bits == 1 or layer_bits == 0:
		return {}
	var br_idx := (b2 >> 4) & 15
	var sr_idx := (b2 >> 2) & 3
	if br_idx == 0 or br_idx == 15 or sr_idx == 3:
		return {}
	var mpeg1 := ver_bits == 3
	var rate: int
	if ver_bits == 3:
		rate = RATES_V1[sr_idx]
	elif ver_bits == 2:
		rate = RATES_V2[sr_idx]
	else:
		rate = RATES_V25[sr_idx]
	var bitrate := 0
	var spf := 1152
	if layer_bits == 1: # Layer III
		bitrate = (BITRATES_V1_L3 if mpeg1 else BITRATES_V2_L3)[br_idx]
		spf = 1152 if mpeg1 else 576
	elif layer_bits == 2 and mpeg1: # Layer II, MPEG-1
		bitrate = BITRATES_V1_L2[br_idx]
	else:
		return {} # Layer I / MPEG-2 Layer II: not worth supporting
	if bitrate <= 0 or rate <= 0:
		return {}
	var mono := ((b3 >> 6) & 3) == 3
	var crc := 2 if (b1 & 1) == 0 else 0
	var side := (17 if mono else 32) if mpeg1 else (9 if mono else 17)
	var x := at + 4 + crc + side
	if layer_bits == 1 and x + 12 <= b.size():
		var tag := b.slice(x, x + 4).get_string_from_ascii()
		if tag == "Xing" or tag == "Info":
			var flags := _be32(b, x + 4)
			if (flags & 1) != 0:
				var frames := _be32(b, x + 8)
				if frames > 0:
					return {
						"duration_s": float(frames) * float(spf) / float(rate),
						"bitrate_kbps": bitrate,
						"sample_rate": rate,
						"vbr": tag == "Xing",
					}
	var secs := float(audio_bytes) * 8.0 / (float(bitrate) * 1000.0)
	return {"duration_s": maxf(secs, 0.0), "bitrate_kbps": bitrate, "sample_rate": rate, "vbr": false}

static func _be32(b: PackedByteArray, at: int) -> int:
	if at + 4 > b.size():
		return 0
	return (int(b[at]) << 24) | (int(b[at + 1]) << 16) | (int(b[at + 2]) << 8) | int(b[at + 3])
