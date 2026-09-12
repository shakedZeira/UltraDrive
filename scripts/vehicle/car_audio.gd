class_name CarAudio
extends AudioStreamPlayer3D

## Procedural engine sound.
## Synthesizes a low-frequency PCM loop at runtime (no asset required), then
## modulates playback pitch_scale from engine RPM and a touch of volume from
## road speed. Each car drives a distinct EngineProfile (timbre) via CarConfig:
##   - "sport"  inline 6, smooth with dominant firing-order partials
##   - "muscle" V8, deep growl with strong even harmonics + extra rasp
##   - "rally"  turbo 4, buzzy rasp with a high whistle-like partial + noise
## Attach as a child of a VehiclePhysics node.

const IDLE_RPM: float = 800.0
const REDLINE_RPM: float = 7000.0
const BASE_PITCH: float = 0.8
const REDLINE_PITCH: float = 2.2
const LOOP_HZ: float = 50.0
const SAMPLE_RATE: int = 44100

# Per-timbre harmonic weights for partials 1..6 (relative to the loop
# fundamental) + a noise/rasp gain. Higher partials read as rasp; emphasising
# the even partials (2, 4, 6) reads as a big V8; odd-blue combos read buzzy.
const PROFILES: Dictionary = {
	"sport": {
		"loop_hz": 50.0,
		"base_pitch": 0.8,
		"redline_pitch": 2.2,
		"weights": [0.45, 0.25, 0.15, 0.10, 0.0, 0.05],
		"noise": 0.04,
	},
	"muscle": {
		"loop_hz": 42.0,
		"base_pitch": 0.55,
		"redline_pitch": 1.75,
		"weights": [0.40, 0.38, 0.10, 0.30, 0.04, 0.10],
		"noise": 0.08,
	},
	"rally": {
		"loop_hz": 58.0,
		"base_pitch": 1.0,
		"redline_pitch": 2.6,
		"weights": [0.25, 0.40, 0.28, 0.18, 0.10, 0.16],
		"noise": 0.12,
	},
}

const ASSET_CANDIDATES: Array[String] = [
	"res://assets/audio/engine_loop.wav",
	"res://assets/audio/engine_loop.ogg",
	"res://resources/audio/engine_loop.wav",
	"res://resources/audio/engine_loop.ogg",
]

var _car: VehiclePhysics = null
var _profile: Dictionary = PROFILES["sport"]

func _ready() -> void:
	unit_size = 2.0
	max_distance = 80.0
	var cfg := _get_config()
	if cfg != null:
		_profile = PROFILES.get(cfg.engine_timbre, PROFILES["sport"])
	var loop := _load_loop_or_generate()
	if loop != null:
		stream = loop
		play()

func _physics_process(_delta: float) -> void:
	if _car == null:
		_car = get_parent() as VehiclePhysics
		if _car == null:
			_car = VehicleManager.get_player_car()
		if _car == null:
			return

	var cfg := _get_config()
	if cfg != null:
		_profile = PROFILES.get(cfg.engine_timbre, PROFILES["sport"])

	var info := _car.get_drive_info()
	var rpm: float = float(info.get("rpm", IDLE_RPM))
	var redline: float = REDLINE_RPM
	if cfg != null:
		redline = cfg.redline_rpm
	var norm := clampf((rpm - IDLE_RPM) / (redline - IDLE_RPM), 0.0, 1.0)
	var base_pitch: float = float(_profile.get("base_pitch", BASE_PITCH))
	var redline_pitch: float = float(_profile.get("redline_pitch", REDLINE_PITCH))
	pitch_scale = lerpf(base_pitch, redline_pitch, norm)

	var speed_kmh: float = float(info.get("speed_kmh", 0.0))
	volume_db = lerpf(-8.0, 0.0, clampf(speed_kmh / 140.0, 0.0, 1.0))

func _get_config() -> CarConfig:
	var parent := get_parent()
	if parent is VehiclePhysics:
		return (parent as VehiclePhysics).config
	return null

func _load_loop_or_generate() -> AudioStream:
	for path in ASSET_CANDIDATES:
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return _generate_engine_loop()

func _generate_engine_loop() -> AudioStreamWAV:
	var loop_hz: float = float(_profile.get("loop_hz", LOOP_HZ))
	var weights: Array = _profile.get("weights", PROFILES["sport"]["weights"])
	var noise_gain: float = float(_profile.get("noise", 0.04))

	var period := int(round(SAMPLE_RATE / loop_hz))
	var data := PackedByteArray()
	data.resize(period * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(loop_hz * 1000.0 + noise_gain * 100.0)

	for i in period:
		var phase := TAU * float(i) / float(period)
		var sample := 0.0
		for h in range(weights.size()):
			var w: float = float(weights[h])
			if w > 0.0:
				sample += sin(phase * float(h + 1)) * w
		if noise_gain > 0.0:
			sample += (rng.randf() * 2.0 - 1.0) * noise_gain
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = period
	wav.data = data
	return wav