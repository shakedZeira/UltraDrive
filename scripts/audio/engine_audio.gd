class_name EngineAudio
extends AudioStreamPlayer3D

## Real-engine ladder player. Replaces the old pitched Freesound MP3s (0.85-1.3
## chipmunk sweep) with five steady-state loop beds -- one V10 engine simulated
## by enginesound (MIT, see assets/audio/engine/LICENSES.md) at exactly
## 800 / 2000 / 3500 / 5500 / 6900 RPM. Each bed is already the engine at its
## RPM, so bands are never pitch-shifted: the two neighbours of the live RPM
## are equal-power crossfaded through exported Curve resources the same
## linearly-mapped way, and load (on vs off) is shaped by gain + low-pass.
##
## External contract kept for TrafficSpawner:
##   TRAFFIC_AUDIO_RANGE + cull_by_distance + set_audio_active.

const IDLE_RPM: float = 800.0
const REDLINE_RPM: float = 7000.0

## Ordered band names; index order maps to BAND_FILES / BAND_RPMS and to the
## children created in _ready.
const BAND_ORDER: Array[String] = ["idle", "low", "mid", "high", "max"]
const BAND_FILES: Dictionary = {
	"idle": "res://assets/audio/engine/engine_idle.wav",
	"low": "res://assets/audio/engine/engine_low.wav",
	"mid": "res://assets/audio/engine/engine_mid.wav",
	"high": "res://assets/audio/engine/engine_high.wav",
	"max": "res://assets/audio/engine/engine_max.wav",
}
## Bed centre RPMs, in BAND_ORDER order. These are the exact synth RPMs.
const BAND_RPMS: Array[float] = [800.0, 2000.0, 3500.0, 5500.0, 6900.0]

const TRAFFIC_AUDIO_RANGE: float = 300.0
const MASTER_TRIM_DB: float = -3.0
const MUTE_FLOOR_DB: float = -80.0
const VOL_SLEW_DB: float = 4.0

## Load shaping retained from the previous generation: off-load = quieter + a
## darker low-pass (coast); on-load = +3 dB-ish lift and a bright high-pass.
const LOAD_GAIN_DB: float = 6.0
const LPF_OFF_HZ: float = 900.0
const LPF_ON_HZ: float = 8000.0
const LPF_SLEW_HZ: float = 1200.0

const LOAD_DERIV_GAIN: float = 20.0

## Optional editor override for the per-band RPM crossfade curves. When left
## empty, _ready installs build_default_curves(), which exactly reproduces
## band_weights() so runtime and pure-static math always agree.
@export var volume_curves: Array[Curve] = []

var _car: VehiclePhysics = null
var _beds: Array[Dictionary] = []
var _band_players: Array[AudioStreamPlayer3D] = []
var _vol_ema: Array[float] = []
var _curves: Array[Curve] = []
var _smooth_rpm: float = 0.0
var _prev_rpm_norm: float = 0.0
var _rpm_deriv: float = 0.0
var _time: float = 0.0
var _culled: bool = false
var _is_player: bool = false
var _lpf_effect: AudioEffectLowPassFilter = null
var _lpf_bus_index: int = -1
var _lpf_added: bool = false


func _ready() -> void:
	unit_size = 2.0
	max_distance = 80.0
	_car = get_parent() as VehiclePhysics
	_beds = load_beds()
	_curves.resize(BAND_ORDER.size())
	if volume_curves.is_empty():
		volume_curves = build_default_curves()
	for i in range(volume_curves.size()):
		_curves[i] = volume_curves[i]
	_create_band_players()
	for player in _band_players:
		player.play()


func _exit_tree() -> void:
	_remove_lpf()


func _create_band_players() -> void:
	for i in range(_beds.size()):
		var player := AudioStreamPlayer3D.new()
		player.name = "Band%d" % i
		player.unit_size = unit_size
		player.max_distance = max_distance
		add_child(player)
		player.stream = _beds[i]["stream"]
		player.volume_db = MUTE_FLOOR_DB
		_band_players.append(player)
		_vol_ema.append(MUTE_FLOOR_DB)


func _physics_process(delta: float) -> void:
	if _band_players.is_empty():
		return
	if _culled:
		for player in _band_players:
			if player.playing:
				player.stop()
		return
	if _car == null:
		_car = get_parent() as VehiclePhysics
		if _car == null:
			_car = VehicleManager.get_player_car()
		if _car == null:
			return

	var cfg := _get_config()
	var idle: float = IDLE_RPM
	var redline: float = REDLINE_RPM
	if cfg != null:
		idle = cfg.idle_rpm
		redline = cfg.redline_rpm

	var info := _car.get_drive_info()
	var rpm: float = float(info.get("rpm", idle))
	var rpm_norm := clampf((rpm - idle) / maxf(redline - idle, 1.0), 0.0, 1.0)
	var throttle := clampf(float(info.get("throttle", 0.0)), 0.0, 1.0)

	var rpm_delta := rpm_norm - _prev_rpm_norm
	_prev_rpm_norm = rpm_norm
	_rpm_deriv = lerpf(_rpm_deriv, rpm_delta, 0.15)
	var load := clampf(rpm_norm * 0.25 + throttle * 0.55 + maxf(_rpm_deriv, 0.0) * LOAD_DERIV_GAIN * 0.02, 0.0, 1.0)

	_time += delta
	var bound := 4.0 * delta if rpm_norm >= _smooth_rpm else 2.2 * delta
	_smooth_rpm = move_toward(_smooth_rpm, rpm_norm, bound)

	var weights := sample_curves(_curves, _smooth_rpm)
	var shaping := load_shaping(load)
	var load_gain: float = float(shaping["gain_db"])

	for i in range(_band_players.size()):
		var player := _band_players[i]
		player.pitch_scale = 1.0
		var target_db := MUTE_FLOOR_DB
		var weight: float = weights[i]
		if weight > 0.001:
			target_db = clampf(linear_to_db(sqrt(weight)) + load_gain + MASTER_TRIM_DB, MUTE_FLOOR_DB, 6.0)
		var vol: float = move_toward(_vol_ema[i], target_db, VOL_SLEW_DB)
		_vol_ema[i] = vol
		player.volume_db = vol
		if not player.playing:
			player.play()

	var player_car: VehiclePhysics = VehicleManager.get_player_car()
	_is_player = player_car != null and _car == player_car
	if _is_player:
		_ensure_lpf()
		if _lpf_effect != null:
			var lpf: float = float(shaping["lpf_hz"])
			_lpf_effect.cutoff_hz = move_toward(_lpf_effect.cutoff_hz, lpf, LPF_SLEW_HZ)


func set_audio_active(active: bool) -> void:
	_culled = not active
	for i in range(_band_players.size()):
		var player := _band_players[i]
		if active:
			if not player.playing:
				player.play()
		else:
			player.volume_db = MUTE_FLOOR_DB
			_vol_ema[i] = MUTE_FLOOR_DB
			if player.playing:
				player.stop()


func cull_by_distance(camera_pos: Vector3, range_m: float) -> void:
	set_audio_active(global_position.distance_to(camera_pos) <= range_m)


## Loads the five bed streams and forces them to seamless LOOP_FORWARD; missing
## files degrade to a null stream (silence) instead of crashing the car scene.
## Pure static for testability.
##
## IMPORTANT: the imported beds are QOA-compressed (the 4.7 WAV importer's
## default), and Godot's QOA playback path silently fails to start when
## loop_end is the -1 "whole sample" sentinel. The loop end is therefore snapped
## to the stream's actual sample count so playback actually begins and loops.
static func load_beds() -> Array[Dictionary]:
	var beds: Array[Dictionary] = []
	for name: String in BAND_ORDER:
		var path: String = BAND_FILES[name]
		var stream: AudioStream = null
		if ResourceLoader.exists(path):
			var res := load(path) as AudioStream
			if res != null:
				stream = res
				var wav := res as AudioStreamWAV
				if wav != null:
					wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
					wav.loop_begin = 0
					var frames := int(round(wav.get_length() * wav.mix_rate))
					wav.loop_end = maxi(frames - 1, 1)
		beds.append({
			"name": name,
			"path": path,
			"stream": stream,
		})
	return beds


## Equal-power crossfade over the ordered band centres: at any RPM only the two
## neighbouring bands are non-zero, blending cos2/sin2 on each segment.
static func band_weights(rpm_norm: float, centers: Array[float]) -> Array[float]:
	var n := centers.size()
	var weights: Array[float] = []
	weights.resize(n)
	for i in range(n):
		weights[i] = 0.0
	var t := clampf(rpm_norm, 0.0, 1.0)
	for i in range(n - 1):
		if t <= centers[i + 1] or i == n - 2:
			var seg_len := centers[i + 1] - centers[i]
			if seg_len <= 0.0:
				weights[i] = 1.0
				break
			var local_t := clampf((t - centers[i]) / seg_len, 0.0, 1.0)
			weights[i] = pow(cos(local_t * PI * 0.5), 2.0)
			weights[i + 1] = pow(sin(local_t * PI * 0.5), 2.0)
			break
	return weights


## Crossfade curves that reproduce band_weights() for every rpm_norm: one
## raised-cosine lobe per band. Each curve is sampled across its support so the
## runtime Curve.sample() path and the analytic function agree.
static func build_default_curves() -> Array[Curve]:
	var centers := normalized_centers()
	var curves: Array[Curve] = []
	for b in range(BAND_ORDER.size()):
		var c := Curve.new()
		var pts := PackedVector2Array()
		if b == 0:
			pts.push_back(Vector2(0.0, 1.0))
		elif b == BAND_ORDER.size() - 1:
			pts.push_back(Vector2(1.0, 1.0))
		var seg_start: float = 0.0
		var seg_end: float = 1.0
		if b > 0:
			seg_start = centers[b - 1]
		if b < BAND_ORDER.size() - 1:
			seg_end = centers[b + 1]
		# Points on both adjacent segments around this band.
		for k in range(0, 9):
			var frac := float(k) / 8.0
			var t0 := lerpf(seg_start, centers[b], frac)
			pts.push_back(Vector2(t0, _band_curve_y(b, t0, centers)))
			if seg_end > centers[b]:
				var t1 := lerpf(centers[b], seg_end, frac)
				pts.push_back(Vector2(t1, _band_curve_y(b, t1, centers)))
		pts.sort()
		for p: Vector2 in pts:
			c.add_point(p)
		curves.append(c)
	return curves


static func _band_curve_y(band: int, t: float, centers: Array[float]) -> float:
	var w := band_weights(t, centers)
	return w[band] if band < w.size() else 0.0


## Sampled per-band gain for a given (smoothed) rpm_norm via the Curve path.
static func sample_curves(curves: Array[Curve], rpm_norm: float) -> Array[float]:
	var weights: Array[float] = []
	var t := clampf(rpm_norm, 0.0, 1.0)
	for c: Curve in curves:
		weights.append(clampf(c.sample(t), 0.0, 1.0))
	return weights


## Band centre positions on the 0..1 ladder (800..7000 RPM).
static func normalized_centers() -> Array[float]:
	var centers: Array[float] = []
	for rpm: float in BAND_RPMS:
		centers.append(clampf((rpm - IDLE_RPM) / (REDLINE_RPM - IDLE_RPM), 0.0, 1.0))
	return centers


static func load_shaping(load: float) -> Dictionary:
	var clamped := clampf(load, 0.0, 1.0)
	return {
		"gain_db": clamped * LOAD_GAIN_DB,
		"lpf_hz": lerpf(LPF_OFF_HZ, LPF_ON_HZ, clamped),
	}


func _get_config() -> CarConfig:
	var parent := get_parent()
	if parent is VehiclePhysics:
		return (parent as VehiclePhysics).config
	return null


func _ensure_lpf() -> void:
	if _lpf_added:
		return
	_lpf_bus_index = AudioServer.get_bus_index("Master")
	if _lpf_bus_index < 0:
		_lpf_added = true
		return
	for i in range(AudioServer.get_bus_effect_count(_lpf_bus_index)):
		var effect: AudioEffect = AudioServer.get_bus_effect(_lpf_bus_index, i)
		if effect is AudioEffectLowPassFilter:
			_lpf_effect = effect as AudioEffectLowPassFilter
			_lpf_added = true
			return
	_lpf_effect = AudioEffectLowPassFilter.new()
	_lpf_effect.cutoff_hz = LPF_OFF_HZ
	_lpf_effect.resonance = 0.5
	AudioServer.add_bus_effect(_lpf_bus_index, _lpf_effect, 0)
	_lpf_added = true


func _remove_lpf() -> void:
	if _lpf_bus_index < 0 or not _lpf_added:
		return
	if _lpf_effect != null:
		for i in range(AudioServer.get_bus_effect_count(_lpf_bus_index)):
			var effect: AudioEffect = AudioServer.get_bus_effect(_lpf_bus_index, i)
			if effect == _lpf_effect:
				AudioServer.remove_bus_effect(_lpf_bus_index, i)
				break
	_lpf_added = false
	_lpf_effect = null