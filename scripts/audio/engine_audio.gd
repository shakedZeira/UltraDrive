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

## Per-timbre real-bed families (same enginesound pipeline, different synth
## recipes): muscle = big-bore V8, rally = high-rev turbo-4. Each family owns
## its own five loop beds under assets/audio/engine/<family>/, its own band
## ladder (authored relative to its redline), pitch clamp window and master
## trim. "sport" stays exactly today's V10 files / math.
const TIMBRE_SPORT: String = "sport"
const TIMBRE_MUSCLE: String = "muscle"
const TIMBRE_RALLY: String = "rally"
const TIMBRE_GTR: String = "gtr"

const BAND_FILES_MUSCLE: Dictionary = {
	"idle": "res://assets/audio/engine/muscle/engine_idle.wav",
	"low": "res://assets/audio/engine/muscle/engine_low.wav",
	"mid": "res://assets/audio/engine/muscle/engine_mid.wav",
	"high": "res://assets/audio/engine/muscle/engine_high.wav",
	"max": "res://assets/audio/engine/muscle/engine_max.wav",
}
const BAND_FILES_RALLY: Dictionary = {
	"idle": "res://assets/audio/engine/rally/engine_idle.wav",
	"low": "res://assets/audio/engine/rally/engine_low.wav",
	"mid": "res://assets/audio/engine/rally/engine_mid.wav",
	"high": "res://assets/audio/engine/rally/engine_high.wav",
	"max": "res://assets/audio/engine/rally/engine_max.wav",
}
const BAND_FILES_GTR: Dictionary = {
	"idle": "res://assets/audio/engine/gtr/engine_idle.wav",
	"low": "res://assets/audio/engine/gtr/engine_low.wav",
	"mid": "res://assets/audio/engine/gtr/engine_mid.wav",
	"high": "res://assets/audio/engine/gtr/engine_high.wav",
	"max": "res://assets/audio/engine/gtr/engine_max.wav",
}
const BAND_RPMS_MUSCLE: Array[float] = [800.0, 1700.0, 3000.0, 4500.0, 6000.0]
const BAND_RPMS_RALLY: Array[float] = [800.0, 2200.0, 4000.0, 6000.0, 7900.0]
const BAND_RPMS_GTR: Array[float] = [800.0, 1800.0, 3200.0, 4800.0, 6800.0]
## Family nominal idle/redline used to place each band ladder on the 0..1 RPM
## axis (build_curves_for): muscle V8 peaks at 6200, the rally 4-pot at 8200,
## the GT-R twin-turbo V6 at 7000.
const RPM_SPAN_MUSCLE: Vector2 = Vector2(800.0, 6200.0)
const RPM_SPAN_RALLY: Vector2 = Vector2(800.0, 8200.0)
const RPM_SPAN_GTR: Vector2 = Vector2(800.0, 7000.0)
const PITCH_MIN_MUSCLE: float = 0.55
const PITCH_MAX_MUSCLE: float = 1.6
const PITCH_MIN_RALLY: float = 0.45
const PITCH_MAX_RALLY: float = 1.9
const PITCH_MIN_GTR: float = 0.45
const PITCH_MAX_GTR: float = 1.5
const MASTER_TRIM_DB_MUSCLE: float = 1.0
const MASTER_TRIM_DB_RALLY: float = -1.0
const MASTER_TRIM_DB_GTR: float = -2.0

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

## Turbo audio layer (v1, presentation-only): three additive voices on top of
## the gtr engine bed, driven by the Drivetrain's live boost state through
## get_drive_info()'s boost_bar / boost_fraction / has_turbo keys. The whine
## is a whole-file loop (spool); the BOV psh and the wastegate "stutu" are
## one-shots fired on the throttle-lift (gas-off) edge. Created only for turbo
## cars (turbo_max_boost_bar > 0) and never under the headless display server
## (same guard as CarAudio's feel players).
const TURBO_ASSETS: Dictionary = {
	"whine": "res://assets/audio/engine/gtr/turbo_whine.wav",
	"bov": "res://assets/audio/engine/gtr/bov_tail.wav",
	"flutter": "res://assets/audio/engine/gtr/flutter_hits.wav",
}
const TURBO_LAYER_ORDER: Array[String] = ["whine", "bov", "flutter"]
const TURBO_LAYER_NAMES: Array[String] = ["TurboWhine", "TurboBOV", "TurboFlutter"]
## Minimum boost fraction (0..1) at which the gas-off edge fires the blow-off
## valve / the wastegate "stutu" (flutter) after-effect.
const TURBO_BOV_MIN_FRACTION: float = 0.25
const TURBO_FLUTTER_MIN_FRACTION: float = 0.4
const TURBO_WHINE_TRIM_DB: float = 6.0
const TURBO_BOV_TRIM_DB: float = 6.0
const TURBO_FLUTTER_TRIM_DB: float = 6.0

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
var _bed_set: String = ""
var _band_rpms: Array[float] = []
var _pitch_min: float = PITCH_MIN
var _pitch_max: float = PITCH_MAX
var _trim_db: float = 0.0
var _auto_curves: bool = true
var _turbo_streams: Dictionary = {}
var _turbo_players: Array[AudioStreamPlayer3D] = []
var _turbo_vol_ema: Array[float] = []
var _prev_boost_fraction: float = 0.0


func _ready() -> void:
	unit_size = 2.0
	max_distance = 80.0
	_car = get_parent() as VehiclePhysics
	_auto_curves = volume_curves.is_empty()
	_apply_profile(_get_config())
	_sync_curves()
	_create_band_players()
	for player in _band_players:
		player.play()
	_ensure_turbo_layer(_get_config())


func _exit_tree() -> void:
	_remove_lpf()


## Resolves the car's bed family (engine_bed_set, else engine_timbre, else
## sport) and, when it changed since last call, reloads the five loop beds, the
## per-band RPM ladder, pitch clamp window and master trim, and rebuilds the
## auto crossfade curves. Called from _ready and re-checked every physics frame
## so a config assigned after this node's _ready (controller or spawner) takes
## effect without a scene reload.
func _apply_profile(cfg: CarConfig) -> void:
	var bed_set := TIMBRE_SPORT
	if cfg != null:
		bed_set = normalize_timbre(cfg.get_engine_bed_set())
	if bed_set == _bed_set:
		return
	_bed_set = bed_set
	_band_rpms = band_rpms_for_timbre(bed_set)
	var pitch_window := pitch_window_for_timbre(bed_set)
	_pitch_min = pitch_window.x
	_pitch_max = pitch_window.y
	_trim_db = master_trim_db_for_timbre(bed_set)
	_beds = load_beds_for(bed_files_for_timbre(bed_set))
	if _auto_curves:
		var span := rpm_span_for_timbre(bed_set)
		volume_curves = build_curves_for(_band_rpms, span.x, span.y)
	for i in range(_band_players.size()):
		if i < _beds.size():
			_band_players[i].stream = _beds[i]["stream"]


func _sync_curves() -> void:
	_curves.resize(BAND_ORDER.size())
	for i in range(volume_curves.size()):
		_curves[i] = volume_curves[i]


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


func _create_turbo_players() -> void:
	if _turbo_players.size() > 0:
		return
	if not should_create_turbo_players(_get_config(), DisplayServer.get_name()):
		return
	if _turbo_streams.is_empty():
		_turbo_streams = load_turbo_assets()
	for i in range(TURBO_LAYER_ORDER.size()):
		var player := AudioStreamPlayer3D.new()
		player.name = TURBO_LAYER_NAMES[i]
		player.unit_size = unit_size
		player.max_distance = max_distance
		add_child(player)
		player.stream = _turbo_streams.get(TURBO_LAYER_ORDER[i]) as AudioStream
		player.volume_db = MUTE_FLOOR_DB
		_turbo_players.append(player)
		_turbo_vol_ema.append(MUTE_FLOOR_DB)
	# The whine is a whole-file loop: start it now (muted until boost arrives).
	# The BOV/flutter one-shots fire on the gas-off edge in _update_turbo().
	if _turbo_players.size() > 0:
		_turbo_players[0].play()


## Lazily creates the turbo layer once a turbo config is available (it may be
## assigned after this node's _ready by a controller or spawner, same contract
## as _apply_profile). No-op for NA cars and under the headless display server.
func _ensure_turbo_layer(cfg: CarConfig) -> void:
	if _turbo_players.size() > 0:
		return
	if not should_create_turbo_players(cfg, DisplayServer.get_name()):
		return
	_create_turbo_players()


## Per-frame turbo voice update: the spool whine chases the boost fraction x
## rpm position; the blow-off valve fires once on the lift edge while boost was
## built; the wastegate flutter fires on a gear-change edge while boost is up.
func _update_turbo(cfg: CarConfig, info: Dictionary, rpm_norm: float, throttle: float) -> void:
	if _turbo_players.is_empty():
		return
	var boost := clampf(float(info.get("boost_fraction", 0.0)), 0.0, 1.0)
	var whine := _turbo_players[0]
	var bov := _turbo_players[1]
	var flutter := _turbo_players[2]
	var whine_gain := turbo_whine_gain_db(boost, rpm_norm)
	if cfg != null:
		whine_gain += linear_to_db(maxf(cfg.turbo_whine_gain, 0.001))
	var whine_target := clampf(whine_gain, MUTE_FLOOR_DB, 6.0)
	var whine_vol: float = move_toward(_turbo_vol_ema[0], whine_target, VOL_SLEW_DB)
	_turbo_vol_ema[0] = whine_vol
	whine.volume_db = whine_vol
	if not whine.playing:
		whine.play()
	# BOV: same lift edge as the lift-off pop, gated on boost actually built.
	if _prev_throttle > 0.5 and throttle < 0.15 and _prev_boost_fraction > TURBO_BOV_MIN_FRACTION:
		bov.volume_db = bov_gain_db(_prev_boost_fraction)
		bov.play()
	# Wastegate flutter ("stutu"): the after-effect of LETTING OFF the gas --
	# same lift edge as the BOV (throttle drops through 0.5 -> 0.15 while boost
	# was built), gated on a wastegate being fitted. It is a gas-off reaction,
	# not a gear-change reaction, so a steady throttle holds a clean whistle.
	if _prev_throttle > 0.5 and throttle < 0.15 and _prev_boost_fraction > TURBO_FLUTTER_MIN_FRACTION \
			and (cfg == null or cfg.turbo_has_wastegate):
		flutter.volume_db = flutter_gain_db(_prev_boost_fraction)
		flutter.play()
	_prev_boost_fraction = boost


func _physics_process(delta: float) -> void:
	if _band_players.is_empty():
		return
	if _culled:
		for player in _band_players:
			if player.playing:
				player.stop()
		for player in _turbo_players:
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
	_apply_profile(cfg)
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

	# Turbo layer (presentation-only): create lazily in case the config was
	# assigned after _ready, then fire the per-frame spool/BOV/flutter voices.
	# Must run BEFORE the lift-edge block below: _update_turbo() reads
	# _prev_throttle (last frame's value) for the BOV edge, exactly like the
	# lift-off pop does one block later.
	_ensure_turbo_layer(cfg)
	_update_turbo(cfg, info, rpm_norm, throttle)

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
		player.pitch_scale = band_pitch_scale_window(live_rpm, _band_rpms[i], _pitch_min, _pitch_max) * shift_pitch
		var target_db := clampf(band_gain_db(weights[i], load_gain, trans_db) + _trim_db, MUTE_FLOOR_DB, 6.0)
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
	for i in range(_turbo_players.size()):
		var turbo_player := _turbo_players[i]
		turbo_player.volume_db = MUTE_FLOOR_DB
		_turbo_vol_ema[i] = MUTE_FLOOR_DB
		if turbo_player.playing:
			turbo_player.stop()
	if active:
		_prev_boost_fraction = 0.0


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
	return load_beds_for(BAND_FILES)


## Same ladder load as load_beds() but from an explicit per-band file table
## (eg a per-timbre family). Pure static for testability.
static func load_beds_for(files: Dictionary) -> Array[Dictionary]:
	var beds: Array[Dictionary] = []
	for name: String in BAND_ORDER:
		var path: String = files[name]
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


## Unknown or empty timbres fall back to the shipped V10 sport family.
static func normalize_timbre(timbre: String) -> String:
	if timbre == TIMBRE_MUSCLE or timbre == TIMBRE_RALLY or timbre == TIMBRE_GTR:
		return timbre
	return TIMBRE_SPORT


## Per-band file table for a timbre. "sport" is exactly BAND_FILES (the
## shipped V10 beds); muscle/rally point into their own synthesized sub-dirs.
static func bed_files_for_timbre(timbre: String) -> Dictionary:
	match normalize_timbre(timbre):
		TIMBRE_MUSCLE:
			return BAND_FILES_MUSCLE
		TIMBRE_RALLY:
			return BAND_FILES_RALLY
		TIMBRE_GTR:
			return BAND_FILES_GTR
	return BAND_FILES


## Bed ladder for a timbre (a fresh copy so callers can't mutate the const).
static func band_rpms_for_timbre(timbre: String) -> Array[float]:
	match normalize_timbre(timbre):
		TIMBRE_MUSCLE:
			return BAND_RPMS_MUSCLE.duplicate()
		TIMBRE_RALLY:
			return BAND_RPMS_RALLY.duplicate()
		TIMBRE_GTR:
			return BAND_RPMS_GTR.duplicate()
	return BAND_RPMS.duplicate()


## Pitch clamp window {min, max} for the ladder's continuous tracking.
static func pitch_window_for_timbre(timbre: String) -> Vector2:
	match normalize_timbre(timbre):
		TIMBRE_MUSCLE:
			return Vector2(PITCH_MIN_MUSCLE, PITCH_MAX_MUSCLE)
		TIMBRE_RALLY:
			return Vector2(PITCH_MIN_RALLY, PITCH_MAX_RALLY)
		TIMBRE_GTR:
			return Vector2(PITCH_MIN_GTR, PITCH_MAX_GTR)
	return Vector2(PITCH_MIN, PITCH_MAX)


## Master trim DELTA (dB) added on top of MASTER_TRIM_DB. sport = 0 keeps the
## shipped V10 mix untouched.
static func master_trim_db_for_timbre(timbre: String) -> float:
	match normalize_timbre(timbre):
		TIMBRE_MUSCLE:
			return MASTER_TRIM_DB_MUSCLE
		TIMBRE_RALLY:
			return MASTER_TRIM_DB_RALLY
		TIMBRE_GTR:
			return MASTER_TRIM_DB_GTR
	return 0.0


## Family nominal {idle, redline} used to place its band ladder on the 0..1 axis.
static func rpm_span_for_timbre(timbre: String) -> Vector2:
	match normalize_timbre(timbre):
		TIMBRE_MUSCLE:
			return RPM_SPAN_MUSCLE
		TIMBRE_RALLY:
			return RPM_SPAN_RALLY
		TIMBRE_GTR:
			return RPM_SPAN_GTR
	return Vector2(IDLE_RPM, REDLINE_RPM)


## Everything EngineAudio needs about one timbre in one deterministic dict.
static func profile_for_timbre(timbre: String) -> Dictionary:
	var family := normalize_timbre(timbre)
	var pitch_window := pitch_window_for_timbre(family)
	var span := rpm_span_for_timbre(family)
	return {
		"timbre": family,
		"band_files": bed_files_for_timbre(family),
		"band_rpms": band_rpms_for_timbre(family),
		"pitch_min": pitch_window.x,
		"pitch_max": pitch_window.y,
		"trim_db": master_trim_db_for_timbre(family),
		"idle_rpm": span.x,
		"redline_rpm": span.y,
	}


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
	return build_curves_for(BAND_RPMS, IDLE_RPM, REDLINE_RPM)


## Builds the same raised-cosine ladder curves as build_default_curves() but
## from an explicit band-RPM ladder and idle/redline anchors, so each bed
## family can own its crossfade shape.
static func build_curves_for(band_rpms: Array[float], idle_rpm: float, redline_rpm: float) -> Array[Curve]:
	var centers := normalized_centers_for(band_rpms, idle_rpm, redline_rpm)
	var curves: Array[Curve] = []
	for b in range(band_rpms.size()):
		var c := Curve.new()
		var pts := PackedVector2Array()
		if b == 0:
			pts.push_back(Vector2(0.0, 1.0))
		elif b == band_rpms.size() - 1:
			pts.push_back(Vector2(1.0, 1.0))
		var seg_start: float = 0.0
		var seg_end: float = 1.0
		if b > 0:
			seg_start = centers[b - 1]
		if b < band_rpms.size() - 1:
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


## Band centre positions from an explicit ladder + idle/redline anchors.
static func normalized_centers_for(band_rpms: Array[float], idle_rpm: float, redline_rpm: float) -> Array[float]:
	var centers: Array[float] = []
	for rpm: float in band_rpms:
		centers.append(clampf((rpm - idle_rpm) / maxf(redline_rpm - idle_rpm, 1.0), 0.0, 1.0))
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
	return band_pitch_scale_window(live_rpm, band_rpm, PITCH_MIN, PITCH_MAX)


## band_pitch_scale() with an explicit clamp window (per-timbre pitch character).
static func band_pitch_scale_window(live_rpm: float, band_rpm: float, pitch_min: float, pitch_max: float) -> float:
	if band_rpm <= 0.0:
		return 1.0
	return clampf(live_rpm / band_rpm, pitch_min, pitch_max)


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


## Compressor-spool whine command: scales with the boost fraction and the rpm
## position (the spool screams harder higher in the rev range). 0 boost => the
## mute floor, monotonic in boost_fraction for a fixed rpm.
static func turbo_whine_gain_db(boost_fraction: float, rpm_norm: float) -> float:
	if boost_fraction <= 0.001:
		return MUTE_FLOOR_DB
	var b := clampf(boost_fraction, 0.0, 1.0)
	var linear := pow(b, 1.4) * lerpf(0.35, 1.0, clampf(rpm_norm, 0.0, 1.0))
	return clampf(linear_to_db(linear) + TURBO_WHINE_TRIM_DB, MUTE_FLOOR_DB, 6.0)


## Blow-off valve command: louder the more boost was built when the throttle
## lifted. 0 boost => the mute floor, monotonic.
static func bov_gain_db(boost_fraction: float) -> float:
	if boost_fraction <= 0.001:
		return MUTE_FLOOR_DB
	return clampf(linear_to_db(clampf(boost_fraction, 0.0, 1.0)) + TURBO_BOV_TRIM_DB, MUTE_FLOOR_DB, 6.0)


## Wastegate flutter command: a little quieter than the BOV at the same boost.
## 0 boost => the mute floor, monotonic.
static func flutter_gain_db(boost_fraction: float) -> float:
	if boost_fraction <= 0.001:
		return MUTE_FLOOR_DB
	return clampf(linear_to_db(clampf(boost_fraction, 0.0, 1.0) * 0.8) + TURBO_FLUTTER_TRIM_DB, MUTE_FLOOR_DB, 6.0)


## True when the turbo players should exist for this config on this display
## server: a turbo car (turbo_max_boost_bar > 0) NOT running headless (the
## headless guard mirrors CarAudio.is_player_creation_culled). Pure static for
## testability.
static func should_create_turbo_players(cfg: CarConfig, display_name: String) -> bool:
	if cfg == null or cfg.turbo_max_boost_bar <= 0.0:
		return false
	return display_name != "headless"


## Loads the three turbo layer streams. The whine is forced to seamless
## LOOP_FORWARD with the same QOA loop_end snap load_beds_for() applies (the
## whole file is the loop); the one-shots are left unlooped. Missing files
## degrade to a null stream (silence) instead of crashing. Pure static for
## testability.
static func load_turbo_assets() -> Dictionary:
	var streams := {}
	for key: String in TURBO_ASSETS:
		var path: String = TURBO_ASSETS[key]
		var stream: AudioStream = null
		if ResourceLoader.exists(path):
			var res := load(path) as AudioStream
			if res != null:
				stream = res
				if key == "whine":
					var wav := res as AudioStreamWAV
					if wav != null:
						wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
						wav.loop_begin = 0
						var frames := int(round(wav.get_length() * wav.mix_rate))
						wav.loop_end = maxi(frames - 1, 1)
		streams[key] = stream
	return streams


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