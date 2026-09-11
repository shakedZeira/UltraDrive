class_name CarAudio
extends AudioStreamPlayer3D

## Procedural engine sound.
## Synthesizes a low-frequency PCM loop at runtime (no asset required),
## then modulates playback pitch_scale from engine RPM and a touch of volume
## from road speed. Attach as a child of a VehiclePhysics node.

const IDLE_RPM: float = 800.0
const REDLINE_RPM: float = 7000.0
const BASE_PITCH: float = 0.8
const REDLINE_PITCH: float = 2.2
const LOOP_HZ: float = 50.0
const SAMPLE_RATE: int = 44100

const ASSET_CANDIDATES: Array[String] = [
	"res://assets/audio/engine_loop.wav",
	"res://assets/audio/engine_loop.ogg",
	"res://resources/audio/engine_loop.wav",
	"res://resources/audio/engine_loop.ogg",
]

var _car: VehiclePhysics = null

func _ready() -> void:
	unit_size = 2.0
	max_distance = 80.0
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

	var info := _car.get_drive_info()
	var rpm: float = float(info.get("rpm", IDLE_RPM))
	var norm := clampf((rpm - IDLE_RPM) / (REDLINE_RPM - IDLE_RPM), 0.0, 1.0)
	pitch_scale = lerpf(BASE_PITCH, REDLINE_PITCH, norm)

	var speed_kmh: float = float(info.get("speed_kmh", 0.0))
	volume_db = lerpf(-8.0, 0.0, clampf(speed_kmh / 140.0, 0.0, 1.0))

func _load_loop_or_generate() -> AudioStream:
	for path in ASSET_CANDIDATES:
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return _generate_engine_loop()

func _generate_engine_loop() -> AudioStreamWAV:
	var period := int(round(SAMPLE_RATE / LOOP_HZ))
	var data := PackedByteArray()
	data.resize(period * 2)
	for i in period:
		var phase := TAU * float(i) / float(period)
		var sample := sin(phase) * 0.45 \
			+ sin(phase * 2.0) * 0.25 \
			+ sin(phase * 3.0) * 0.15 \
			+ sin(phase * 4.0) * 0.10 \
			+ sin(phase * 6.0) * 0.05
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
