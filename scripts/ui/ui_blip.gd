class_name UiBlip
extends AudioStreamPlayer

## Procedural menu/HUD blip set (AAA-1). Small synth blips for navigation and
## HUD ping, no assets. Playback is disabled under the headless display server
## so test runners never touch the audio bus (mirrors countdown_audio's guard).

const SAMPLE_RATE: int = 22050
const MENU_FREQ_HZ: float = 880.0
const HUD_FREQ_HZ: float = 1320.0
const BLIP_SECONDS: float = 0.06
const VOLUME_DB: float = -6.0

var _disabled: bool = false

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		_disabled = true
	volume_db = VOLUME_DB

func is_playback_disabled() -> bool:
	return _disabled

func play_blip(kind: String) -> void:
	if _disabled:
		return
	match kind:
		"menu":
			stream = build_blip(MENU_FREQ_HZ, BLIP_SECONDS)
		"hud":
			stream = build_blip(HUD_FREQ_HZ, BLIP_SECONDS)
		_:
			return
	play()

static func build_blip(freq_hz: float, seconds: float) -> AudioStreamWAV:
	var total := int(seconds * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(total * 2)
	for i in total:
		var t := float(i) / float(SAMPLE_RATE)
		var attack := clampf(t * 200.0, 0.0, 1.0)
		var release := clampf((seconds - t) * 200.0, 0.0, 1.0)
		var sample := sin(TAU * freq_hz * t) * attack * release
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav