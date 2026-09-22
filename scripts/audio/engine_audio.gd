class_name EngineAudio
extends AudioStreamPlayer3D

## Real-engine ladder player with CONTINUOUS PITCH TRACKING (hybrid round 2).
## Five steady-state loop beds -- one V10 engine simulated by enginesound (MIT,
## see assets/audio/engine/LICENSES.md) at exactly 800 / 2000 / 3500 / 5500 /
## 6900 RPM (BAND_RPMS). The centrepiece fix over the round-2 "static" ladder
## and the round-1 pure sine-bank: the real beds now pitch-shift per frame so
## the exhaust-pulse firing frequency moves continuously with the live RPM
## (`band_pitch_scale = live_rpm / band_rpm`, clamped 0.5..1.7). Because both
## active neighbours pitch to (almost) the same frequency, the equal-power
## band crossfade hands off TIMBRE while pitch stays continuous -- the standard
## Forza/GT technique. On top: load shaping (on-throttle louder + brighter via
## gain + LPF, off-throttle darker coast), a gear-change clutch catch (pitch
## sag + torque blip), and a lift-off pop (short gain nudge) -- all applied to
## the real-bed mix, never as synthetic sine tones.
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
## darker low-pass (coast); on-load = +6 dB lift and a bright high-pass.
const LOAD_GAIN_DB: float = 6.0
const LPF_OFF_HZ: float = 900.0
const LPF_ON_HZ: float = 8000.0
const LPF_SLEW_HZ: float = 1200.0

## Continuous pitch tracking window per band. A band is never warped more than
## 0.5x..1.7x; beyond that the crossfade has already handed the mix to the
## neighbour whose clamp window contains the live RPM.
const PITCH_MIN: float = 0.5
const PITCH_MAX: float = 1.7

## Gear-change clutch catch: pitch sags to 0.82 at the catch and recovers on a
## sqrt ramp; a ~1.18x torque blip rides on top.
const SHIFT_DURATION: float = 0.18
const SHIFT_DIP_MIN: float = 0.82
const SHIFT_BLIP_GAIN: float = 1.18

## Lift-off pop: on a sudden throttle release a short gain nudge (max
## LIFT_GAIN_DB) ramps down linearly over LIFT_ENV_SECONDS. A gain bump on the
## real-bed mix, NOT a synthetic sine tone.
const LIFT_ENV_SECONDS: float = 0.22
const LIFT_GAIN_DB: float = 3.0

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
var _prev_gear: int = 0
var _gear_primed: bool = false
var _shift_elapsed: float = SHIFT_DURATION
var _prev_throttle: float = 0.0
var _lift_env: float = 0.0


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
	var rpm_norm := rpm_normalized(rpm, idle, redline)
	var throttle := clampf(float(info.get("throttle", 0.0)), 0.0, 1.0)
	var gear := int(info.get("gear", 1))

	if not _gear_primed:
		_prev_gear = gear
		_gear_primed = true
	if gear != _prev_gear:
		_prev_gear = gear
		_shift_elapsed = 0.0
	else:
		_shift_elapsed = minf(_shift_elapsed + delta, SHIFT_DURATION)

	if _prev_throttle > 0.5 and throttle < 0.15:
		_lift_env = LIFT_ENV_SECONDS
	_prev_throttle = throttle
	if _lift_env > 0.0:
		_lift_env = maxf(_lift_env - delta, 0.0)

	var rpm_delta := rpm_norm - _prev_rpm_norm
	_prev_rpm_norm = rpm_norm
	_rpm_deriv = lerpf(_rpm_deriv, rpm_delta, 0.15)
	var load := load_value(rpm_norm, throttle, _rpm_deriv)

	_time += delta
	var bound := 4.0 * delta if rpm_norm >= _smooth_rpm else 2.2 * delta
	_smooth_rpm = move_toward(_smooth_rpm, rpm_norm, bound)
	var live_rpm := lerpf(idle, redline, _smooth_rpm)

	var weights := sample_curves(_curves, _smooth_rpm)
	var shaping := load_shaping(load)
	var load_gain: float = float(shaping["gain_db"])
	var shift_pitch := gear_shift_pitch_mult(_shift_elapsed)
	var trans_db := transient_gain_db(_shift_elapsed, _lift_env)

	for i in range(_band_players.size()):
		var player := _band_players[i]
		player.pitch_scale = band_pitch_scale(live_rpm, BAND_RPMS[i]) * shift_pitch
		var target_db := band_gain_db(weights[i], load_gain, trans_db)
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


## rpm on the 0..1 ladder between idle and redline.
static func rpm_normalized(rpm: float, idle: float, redline: float) -> float:
	return clampf((rpm - idle) / maxf(redline - idle, 1.0), 0.0, 1.0)


## Load blends rpm position, throttle and a positive-rpm-slew bonus (blips feel
## loaded). Same determinism contract as the procedural voice it replaced.
static func load_value(rpm_norm: float, throttle: float, rpm_deriv: float = 0.0) -> float:
	return clampf(0.25 * clampf(rpm_norm, 0.0, 1.0) + 0.55 * clampf(throttle, 0.0, 1.0) + maxf(rpm_deriv, 0.0) * 0.4, 0.0, 1.0)


## Per-bed pitch multiplier for a live RPM: the bed authored at band_rpm is
## played band_rpm*scale Hz so its firing frequency lands on the live RPM.
## Clamped to PITCH_MIN..PITCH_MAX so no band warps beyond recognition; the
## crossfade hands the mix to a neighbour whose clamp window holds the live RPM.
static func band_pitch_scale(live_rpm: float, band_rpm: float) -> float:
	if band_rpm <= 0.0:
		return 1.0
	return clampf(live_rpm / band_rpm, PITCH_MIN, PITCH_MAX)


## Effective (post-pitch-shift) engine speed a given bed sounds like.
static func effective_band_rpm(live_rpm: float, band_rpm: float) -> float:
	return band_rpm * band_pitch_scale(live_rpm, band_rpm)


## Pitch of the whole crossfaded mix: the band_weights() equal-power ladder
## sums the effective frequencies of the active bands. Wherever both active
## neighbours are inside their clamp windows this equals the live RPM, which is
## exactly the continuous pitch hand-off the hybrid is built around.
static func mix_pitch_estimate(live_rpm: float, rpm_norm: float) -> float:
	var centers := normalized_centers()
	var weights := band_weights(rpm_norm, centers)
	var num := 0.0
	var den := 0.0
	for i in range(BAND_RPMS.size()):
		var w: float = weights[i] if i < weights.size() else 0.0
		if w > 0.0:
			num += w * effective_band_rpm(live_rpm, BAND_RPMS[i])
			den += w
	if den <= 0.0:
		return live_rpm
	return num / den


## Per-band volume command: equal-power weight -> db, plus load and transient
## gain nudges, inside the mute floor..6 dB ceiling.
static func band_gain_db(weight: float, load_gain_db: float, transient_db: float = 0.0) -> float:
	return clampf(linear_to_db(sqrt(clampf(weight, 0.0, 1.0))) + load_gain_db + MASTER_TRIM_DB + transient_db, MUTE_FLOOR_DB, 6.0)


## Clutch-catch pitch sag: dips to SHIFT_DIP_MIN at the catch and recovers fast.
static func gear_shift_pitch_mult(elapsed: float, duration: float = SHIFT_DURATION) -> float:
	if elapsed >= duration or duration <= 0.0:
		return 1.0
	return lerpf(SHIFT_DIP_MIN, 1.0, sqrt(clampf(elapsed / duration, 0.0, 1.0)))


## Torque blip that rides on top of the shift dip.
static func gear_shift_gain_mult(elapsed: float, duration: float = SHIFT_DURATION) -> float:
	if elapsed >= duration or duration <= 0.0:
		return 1.0
	return lerpf(SHIFT_BLIP_GAIN, 1.0, clampf(elapsed / duration, 0.0, 1.0))


## Lift-off pop envelope: a short gain nudge (0..1) ramping down linearly from
## the trigger. Decays to silence exactly at LIFT_ENV_SECONDS.
static func lift_pop(remaining: float) -> float:
	return clampf(remaining / LIFT_ENV_SECONDS, 0.0, 1.0)


## Combined transient volume offset (db): gear torque blip (always on during a
## shift) plus the lift-off pop. 0 dB when nothing is firing.
static func transient_gain_db(shift_elapsed: float, lift_env: float = 0.0) -> float:
	var db := linear_to_db(gear_shift_gain_mult(shift_elapsed))
	if lift_env > 0.0:
		db += LIFT_GAIN_DB * lift_pop(lift_env)
	return db


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