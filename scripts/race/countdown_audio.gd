class_name CountdownAudio
extends AudioStreamPlayer

## Procedural per-phase start beeps: a low blip for "3 / 2 / 1" and a higher,
## longer beep for "GO!". Synth at runtime, no assets. Playback is disabled
## entirely under the headless display server so test runners never touch the
## audio bus.

const SAMPLE_RATE: int = 22050
const PHASE_FREQ_HZ: float = 660.0
const GO_FREQ_HZ: float = 990.0
const PHASE_SECONDS: float = 0.14
const GO_SECONDS: float = 0.3

var _disabled: bool = false

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		_disabled = true
	volume_db = -3.0

func play_phase(phase: String) -> void:
	if _disabled or not is_countdown_phase(phase):
		return
	if phase == "GO":
		stream = build_beep(GO_FREQ_HZ, GO_SECONDS)
	else:
		stream = build_beep(PHASE_FREQ_HZ, PHASE_SECONDS)
	play()

static func is_countdown_phase(phase: String) -> bool:
	return phase in ["3", "2", "1", "GO"]

static func build_beep(freq_hz: float, seconds: float) -> AudioStreamWAV:
	var total := int(seconds * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(total * 2)
	for i in total:
		var t := float(i) / float(SAMPLE_RATE)
		var attack := clampf(t * 120.0, 0.0, 1.0)
		var release := clampf((seconds - t) * 40.0, 0.0, 1.0)
		var sample := sin(TAU * freq_hz * t) * attack * release
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav