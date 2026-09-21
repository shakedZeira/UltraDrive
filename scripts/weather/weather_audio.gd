class_name WeatherAudio
extends AudioStreamPlayer3D

## Weather VFX (S12): a per-weather ambience bed (procedural rain, deterministic
## seed) whose gain follows the weather state. Volume is applied directly on
## set_weather -- no AudioServer/play() calls -- so the node is headless-safe
## and leaves no audio bus residue in the suite.

const WEATHER_GAIN: Dictionary = {
	WeatherManager.Weather.CLEAR: 0.0,
	WeatherManager.Weather.CLOUDY: 0.0,
	WeatherManager.Weather.FOG: 0.3,
	WeatherManager.Weather.RAIN: 0.75,
	WeatherManager.Weather.STORM: 1.0,
	WeatherManager.Weather.SNOW: 0.6,
}

## Cold -> loud ladder. volume_db sits in this range mapping the gain above.
const VOLUME_MIN_DB := -60.0
const VOLUME_MAX_DB := -4.0

const BED_SAMPLE_RATE := 22050
const BED_SECONDS := 2.0
const BED_SEED := 1337

var _weather: int = WeatherManager.Weather.CLEAR
var _intensity := 0.0

## Fixed per-weather ambience gain (0.0 quiet... 1.0 storm roar).
static func gain_for(weather: int) -> float:
	return float(WEATHER_GAIN.get(weather, 0.0))

## Monotonic intensity -> dB mapping: cold silence at 0, loud bed at 1.
static func volume_for(intensity: float) -> float:
	return lerpf(VOLUME_MIN_DB, VOLUME_MAX_DB, clampf(intensity, 0.0, 1.0))

func _ready() -> void:
	stream = _build_bed()
	volume_db = VOLUME_MIN_DB
	if not WeatherManager.weather_changed.is_connected(_on_weather_changed):
		WeatherManager.weather_changed.connect(_on_weather_changed)
	set_weather(WeatherManager.current_weather)

func _exit_tree() -> void:
	if WeatherManager.weather_changed.is_connected(_on_weather_changed):
		WeatherManager.weather_changed.disconnect(_on_weather_changed)

func set_weather(weather: int) -> void:
	_weather = weather
	_intensity = gain_for(weather)
	volume_db = volume_for(_intensity)

func get_weather() -> int:
	return _weather

func get_intensity() -> float:
	return _intensity

func _on_weather_changed(weather: int) -> void:
	set_weather(weather)

func _build_bed() -> AudioStreamWAV:
	var sample_count := int(BED_SAMPLE_RATE * BED_SECONDS)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = BED_SEED
	var brown := 0.0
	for i in sample_count:
		var white: float = rng.randf_range(-1.0, 1.0)
		brown += (white - brown) * 0.04
		var sample := clampf(white * 0.55 + brown * 1.25, -1.0, 1.0)
		var value := int(sample * 32767.0)
		bytes.encode_s16(i * 2, value)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = BED_SAMPLE_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = sample_count
	wav.data = bytes
	return wav