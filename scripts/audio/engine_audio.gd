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
	"bov": "res://assets/audio/engine/gtr/bov_0.wav",
	"flutter": "res://assets/audio/engine/gtr/flutter_mid_0.wav",
}
const TURBO_LAYER_ORDER: Array[String] = ["whine", "bov", "flutter"]
const TURBO_LAYER_NAMES: Array[String] = ["TurboWhine", "TurboBOV", "TurboFlutter"]
## Minimum boost fraction (0..1) at which the gas-off edge fires the blow-off
## valve / the wastegate "stutu" (flutter) after-effect.
const TURBO_BOV_MIN_FRACTION: float = 0.25
const TURBO_FLUTTER_MIN_FRACTION: float = 0.4
const TURBO_WHINE_TRIM_DB: float = 6.0
const TURBO_BOV_TRIM_DB: float = 6.0
## Re-levelled for the synthesised flutter set (peak 0.85 vs 0.44 for the
## retired flutter_hits.wav): 6.0 dB - 5.7 dB.
const TURBO_FLUTTER_TRIM_DB: float = 0.3

## Flutter / blow-off one-shot variants (tools/make_gtr_flutter.py; the layer
## is the GT-R's -- the only car with turbo_max_boost_bar > 0). Flutter tier is
## picked from the boost at lift-off: 0 = low (<0.65), 1 = mid, 2 = high
## (>= 0.85); two variants per tier. The vented, sharp bov_0 plays for a
## high-boost lift (> TURBO_BOV_VENTED_BOOST), the soft recirculating bov_1
## otherwise. docs/research/turbo_flutter_sound.md.
const TURBO_FLUTTER_VARIANTS: Dictionary = {
	0: ["res://assets/audio/engine/gtr/flutter_lo_0.wav", "res://assets/audio/engine/gtr/flutter_lo_1.wav"],
	1: ["res://assets/audio/engine/gtr/flutter_mid_0.wav", "res://assets/audio/engine/gtr/flutter_mid_1.wav"],
	2: ["res://assets/audio/engine/gtr/flutter_hi_0.wav", "res://assets/audio/engine/gtr/flutter_hi_1.wav"],
}
const TURBO_BOV_VARIANTS: Array[String] = [
	"res://assets/audio/engine/gtr/bov_0.wav",
	"res://assets/audio/engine/gtr/bov_1.wav",
]
const TURBO_FLUTTER_COOLDOWN_S: float = 1.4      # min gap between events (never retrigger mid-flutter)
const TURBO_FLUTTER_TIER_EDGES: Array[float] = [0.65, 0.85]
const TURBO_FLUTTER_RATE_SCALE_MIN: float = 0.92  # playback rate at the lowest boost
const TURBO_FLUTTER_RATE_SCALE_MAX: float = 1.08  # playback rate at full boost
const TURBO_FLUTTER_PITCH_JITTER: float = 0.03    # +/- per-event random pitch factor
const TURBO_BOV_VENTED_BOOST: float = 0.75
## Analog fast-lift detector: the throttle falls by more than TURBO_FAST_LIFT_DROP
## from its short-memory peak (decays over TURBO_FAST_LIFT_WINDOW_S) and ends
## below TURBO_FAST_LIFT_END -- catches pedal lifts the single-frame
## 0.5 -> 0.15 edge misses.
const TURBO_FAST_LIFT_DROP: float = 0.45
const TURBO_FAST_LIFT_WINDOW_S: float = 0.12
const TURBO_FAST_LIFT_END: float = 0.2

## Turbo boost smoothing (wobble fix). The Drivetrain's raw boost_fraction is a
## control-model value: on a wastegate car it is dipped to 15% on EVERY upshift
## and its target rides rpm_norm, so under steady acceleration it saws down/up
## each gear change. Driving the whistle straight from it (plus an rpm_norm
## gain term that also saws with shifts, and a 4 dB/frame volume slew) made the
## turbo audibly pump in volume and pitch. EngineAudio therefore keeps its OWN
## audio boost state: rate-limited spool-up, slow decay while the driver stays
## on the gas (so a shift dip is bridged, not followed), faster spool-down only
## when the driver lifts.
const TURBO_SPOOL_UP_RATE: float = 2.0         # boost-fraction per second, rising
const TURBO_SPOOL_DOWN_RATE: float = 1.4       # per second after a lift-off
const TURBO_HOLD_DECAY_RATE: float = 0.12      # per second while on the gas
const TURBO_LIFT_THROTTLE: float = 0.15        # at/below: full spool-down rate
const TURBO_ON_THROTTLE: float = 0.30          # at/above: hold-decay rate only
const TURBO_RPM_SLOW_TAU: float = 1.6          # s, rpm term of the whistle gain
const TURBO_VOL_TAU: float = 0.12              # s, linear-amplitude smoothing
const TURBO_PITCH_MIN: float = 0.94            # whistle pitch at no boost
const TURBO_PITCH_MAX: float = 1.08            # whistle pitch at full boost
const TURBO_PITCH_RATE: float = 0.07           # max pitch_scale change per second

## GT-R support layers (non-headless, gtr bed set only): induction roar (on
## throttle, pulses at the firing rate) and GR6 gear/final-drive whine (pitch
## follows ROAD SPEED, not rpm). Both are loops from tools/make_gtr_beds.py.
const ENGINE_LAYER_ASSETS: Dictionary = {
	"roar": "res://assets/audio/engine/gtr/intake_roar.wav",
	"whine": "res://assets/audio/engine/gtr/gear_whine.wav",
}
const ENGINE_LAYER_ORDER: Array[String] = ["roar", "whine"]
const ENGINE_LAYER_NAMES: Array[String] = ["IntakeRoar", "GearWhine"]
const ROAR_REF_RPM: float = 3500.0        # rpm the roar loop was authored at
const ROAR_TRIM_DB: float = -11.0
const GEAR_WHINE_REF_KMH: float = 90.0    # road speed where the loop's 1 kHz tone is unshifted
const GEAR_WHINE_TRIM_DB: float = -21.0
const ENGINE_LAYER_VOL_TAU: float = 0.10  # s, linear-amplitude smoothing

## Overrun exhaust layer (pops & bangs), presentation-only: a synthesized burst
## one-shot layered on the bed mix when a high-rpm throttle release is detected.
## Opt-in per car (CarConfig.exhaust_pop_enabled); never created under the
## headless display server (same guard as the turbo layer). Every burst is built
## from a seeded RandomNumberGenerator so identical inputs give identical PCM.
const POP_STYLES: Array[String] = ["burble", "crackle", "bang"]
const POP_SAMPLE_RATE: int = 22050
## Bank size per style (variants the per-event RNG chooses between).
const POP_VARIANTS: int = 4
const POP_GAIN_TRIM_DB: float = -6.0        # fallback if cfg.gain missing
const POP_COOLDOWN_SECONDS: float = 0.15
const POP_RELEASE_HI: float = 0.5           # matches the lift edge
const POP_RELEASE_LO: float = 0.15
const POP_PITCH_MIN: float = 0.94
const POP_PITCH_MAX: float = 1.06
const DEFAULT_POP_SEED: int = 90210

## Optional editor override for the per-band RPM crossfade curves. When left
## empty, _ready installs build_default_curves(), which exactly reproduces
## band_weights() so runtime and pure-static math always agree.
@export var volume_curves: Array[Curve] = []

## Spatial defaults applied in _ready (new exports so scenes can override them
## WITHOUT being stomped by the old hard-coded literals; do NOT reuse the
## inherited unit_size/max_distance as the override channel -- the serialized
## player_car.tscn values and the _ready assignment must both stay valid).
@export var spatial_unit_size: float = 2.0
@export var spatial_max_distance: float = 80.0
## Extra level trim (dB) applied AFTER the timbre master trim and BEFORE the
## floor/ceiling clamp. 0.0 = player. Rivals use a negative value so a pack
## never overpowers the player's own engine.
@export var extra_trim_db: float = 0.0
## When > 0 and this node is NOT the player, distance-cull audio against the
## player car each physics tick (0 = off: player + traffic keep legacy behaviour).
@export var auto_cull_range: float = 0.0

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
var _routed_child_count: int = -1
const VEHICLE_BUS := &"Vehicle"
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
var _turbo_boost: float = 0.0          # smoothed audio boost state (0..1)
var _turbo_rpm_slow: float = 0.0       # slow rpm_norm for the whistle gain
var _turbo_whine_lin: float = 0.0      # smoothed whistle amplitude (linear)
var _turbo_pitch: float = TURBO_PITCH_MIN
var _flutter_variants: Dictionary = {}   # load_flutter_variants() result
var _flutter_cooldown: float = 0.0
var _throttle_peak: float = 0.0          # short-memory throttle peak (fast-lift detector)
var _last_flutter_idx: int = -1
var _last_bov_idx: int = -1
var _flutter_rng := RandomNumberGenerator.new()
var _engine_layer_players: Array[AudioStreamPlayer3D] = []
var _engine_layer_lin: Array[float] = [0.0, 0.0]
var _pop_player: AudioStreamPlayer3D = null
var _pop_rng := RandomNumberGenerator.new()
var _pop_cooldown: float = 0.0
static var _pop_bank_cache: Dictionary = {}


func _ready() -> void:
	unit_size = spatial_unit_size
	max_distance = spatial_max_distance
	_car = get_parent() as VehiclePhysics
	_auto_curves = volume_curves.is_empty()
	_apply_profile(_get_config())
	_sync_curves()
	_create_band_players()
	for player in _band_players:
		player.play()
	_pop_rng.seed = DEFAULT_POP_SEED
	_ensure_turbo_layer(_get_config())
	_ensure_pop_layer(_get_config())


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
	if _flutter_variants.is_empty():
		_flutter_variants = load_flutter_variants()
		_flutter_rng.randomize()
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
		_turbo_pitch = TURBO_PITCH_MIN
		_turbo_players[0].pitch_scale = _turbo_pitch
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


## Lazily creates the exhaust-overrun player once an opted-in config is
## available (the config may be assigned after _ready by a controller or
## spawner, same contract as _ensure_turbo_layer). No-op for cars without the
## flag and under the headless display server.
func _ensure_pop_layer(cfg: CarConfig) -> void:
	if _pop_player != null:
		return
	if not should_create_pop_players(cfg, DisplayServer.get_name()):
		return
	var player := AudioStreamPlayer3D.new()
	player.name = "ExhaustPop"
	player.unit_size = unit_size
	player.max_distance = max_distance
	add_child(player)
	player.volume_db = MUTE_FLOOR_DB
	_pop_player = player


## Per-frame turbo voice update. The whistle follows a SMOOTHED audio boost
## state (turbo_boost_step), not the Drivetrain's raw per-shift-dipping
## boost_fraction: a stable continuous whistle with a gentle rise under load
## that bridges upshift dips and only decays when the driver lifts. The
## blow-off valve and wastegate flutter still fire once on the lift edge while
## boost was built.
func _update_turbo(cfg: CarConfig, info: Dictionary, rpm_norm: float, throttle: float, delta: float = 0.016667) -> void:
	if _turbo_players.is_empty():
		return
	var raw_boost := clampf(float(info.get("boost_fraction", 0.0)), 0.0, 1.0)
	var boost := turbo_boost_step(_turbo_boost, raw_boost, throttle, delta)
	_turbo_boost = boost
	_turbo_rpm_slow = lerpf(_turbo_rpm_slow, rpm_norm, 1.0 - exp(-delta / TURBO_RPM_SLOW_TAU))
	var whine := _turbo_players[0]
	var bov := _turbo_players[1]
	var flutter := _turbo_players[2]
	var whine_gain := turbo_whine_gain_db(boost, _turbo_rpm_slow)
	if cfg != null:
		whine_gain += linear_to_db(maxf(cfg.turbo_whine_gain, 0.001))
	var whine_target := clampf(whine_gain + extra_trim_db, MUTE_FLOOR_DB, 6.0)
	var target_lin := 0.0
	if whine_target > MUTE_FLOOR_DB + 0.5:
		target_lin = db_to_linear(whine_target)
	_turbo_whine_lin = ema_linear(_turbo_whine_lin, target_lin, delta, TURBO_VOL_TAU)
	var whine_vol := MUTE_FLOOR_DB
	if _turbo_whine_lin > 0.0001:
		whine_vol = maxf(linear_to_db(_turbo_whine_lin), MUTE_FLOOR_DB)
	_turbo_vol_ema[0] = whine_vol
	whine.volume_db = whine_vol
	_turbo_pitch = move_toward(_turbo_pitch, turbo_whine_pitch(boost, _turbo_rpm_slow), TURBO_PITCH_RATE * delta)
	whine.pitch_scale = _turbo_pitch
	if not whine.playing:
		whine.play()
	# BOV + wastegate flutter ("stu-tu-tu"): the after-effects of LETTING OFF
	# the gas -- the lift edge (throttle drops through 0.5 -> 0.15, or a fast
	# analog lift) while boost was built. Gas-off reactions, not gear-change
	# ones, so a steady throttle holds a clean whistle. One shared cooldown
	# stops either from retriggering mid-flutter; variant, pitch and length
	# follow the boost at lift-off.
	_flutter_cooldown = maxf(_flutter_cooldown - delta, 0.0)
	_throttle_peak = maxf(throttle, _throttle_peak - delta / TURBO_FAST_LIFT_WINDOW_S)
	var has_wastegate := cfg == null or cfg.turbo_has_wastegate
	var fire_bov := bov_should_fire(_prev_throttle, throttle, _prev_boost_fraction, _flutter_cooldown, _throttle_peak)
	var fire_flutter := flutter_should_fire(_prev_throttle, throttle, _prev_boost_fraction, _flutter_cooldown, has_wastegate, _throttle_peak)
	var event_len := 0.0
	if fire_bov:
		var bov_variants: Array = _flutter_variants.get("bov", [])
		if not bov_variants.is_empty():
			var bov_idx := 0 if _prev_boost_fraction > TURBO_BOV_VENTED_BOOST else 1
			bov_idx = mini(bov_idx, bov_variants.size() - 1)
			_last_bov_idx = bov_idx
			bov.stream = bov_variants[bov_idx] as AudioStream
		bov.pitch_scale = flutter_pitch_scale(_prev_boost_fraction, _flutter_rng.randf())
		bov.volume_db = bov_gain_db(_prev_boost_fraction) + extra_trim_db
		bov.play()
		event_len = maxf(event_len, _stream_seconds(bov.stream) / bov.pitch_scale)
	if fire_flutter:
		var tiers: Array = _flutter_variants.get("flutter", [])
		var tier := flutter_tier(_prev_boost_fraction)
		if tier < tiers.size() and not (tiers[tier] as Array).is_empty():
			var pool: Array = tiers[tier]
			var idx := pick_variant(pool.size(), _last_flutter_idx, _flutter_rng.randf())
			_last_flutter_idx = idx
			flutter.stream = pool[idx] as AudioStream
		flutter.pitch_scale = flutter_pitch_scale(_prev_boost_fraction, _flutter_rng.randf())
		flutter.volume_db = flutter_gain_db(_prev_boost_fraction) + extra_trim_db
		flutter.play()
		event_len = maxf(event_len, _stream_seconds(flutter.stream) / flutter.pitch_scale)
	if fire_bov or fire_flutter:
		_flutter_cooldown = maxf(TURBO_FLUTTER_COOLDOWN_S, event_len)
	_prev_boost_fraction = boost


## Per-frame GT-R support layers: induction roar (throttle x rpm, pitch follows
## rpm so its firing-rate pulsing tracks the engine) and GR6 gear whine (pitch
## and level follow road speed). Created lazily for the gtr bed set only.
func _update_engine_layers(info: Dictionary, live_rpm: float, rpm_norm: float, throttle: float, delta: float) -> void:
	if _engine_layer_players.is_empty():
		return
	var speed_kmh := absf(float(info.get("speed_kmh", 0.0)))
	var targets: Array[float] = [
		intake_roar_gain_db(throttle, rpm_norm) + extra_trim_db,
		gear_whine_gain_db(speed_kmh, throttle) + extra_trim_db,
	]
	for i in range(_engine_layer_players.size()):
		var tgt_lin := 0.0
		if targets[i] > MUTE_FLOOR_DB + 0.5:
			tgt_lin = db_to_linear(clampf(targets[i], MUTE_FLOOR_DB, 6.0))
		_engine_layer_lin[i] = ema_linear(_engine_layer_lin[i], tgt_lin, delta, ENGINE_LAYER_VOL_TAU)
		var player := _engine_layer_players[i]
		player.volume_db = MUTE_FLOOR_DB
		if _engine_layer_lin[i] >= 0.0001:
			player.volume_db = maxf(linear_to_db(_engine_layer_lin[i]), MUTE_FLOOR_DB)
		if not player.playing:
			player.play()
	_engine_layer_players[0].pitch_scale = intake_roar_pitch(live_rpm)
	_engine_layer_players[1].pitch_scale = gear_whine_pitch(speed_kmh)


## Lazily creates the roar / gear-whine players for the gtr bed set (never
## under the headless display server, same guard as the turbo layer).
func _ensure_engine_layers() -> void:
	if not _engine_layer_players.is_empty():
		return
	if not should_create_engine_layers(_bed_set, DisplayServer.get_name()):
		return
	var streams := load_engine_layer_assets()
	for i in range(ENGINE_LAYER_ORDER.size()):
		var player := AudioStreamPlayer3D.new()
		player.name = ENGINE_LAYER_NAMES[i]
		player.unit_size = unit_size
		player.max_distance = max_distance
		add_child(player)
		player.stream = streams.get(ENGINE_LAYER_ORDER[i]) as AudioStream
		player.volume_db = MUTE_FLOOR_DB
		_engine_layer_players.append(player)


## Per-frame overrun update: decay the anti-machine-gun cooldown, evaluate the
## pure trigger against the SAME lift edge the BOV/flutter voices use, and fire
## one burst. MUST be called BEFORE _physics_process() overwrites _prev_throttle
## (identical ordering rule to _update_turbo()).
func _update_overrun(cfg: CarConfig, rpm_norm: float, throttle: float, gear: int, delta: float) -> void:
	_pop_cooldown = maxf(_pop_cooldown - delta, 0.0)
	if cfg == null:
		return
	var enabled: bool = cfg.exhaust_pop_enabled and cfg.exhaust_pop_intensity > 0.0
	if not enabled:
		return
	if not overrun_should_fire(_prev_throttle, throttle, rpm_norm, gear, enabled, cfg.exhaust_pop_min_rpm_fraction, _pop_cooldown):
		return
	_pop_cooldown = POP_COOLDOWN_SECONDS
	_fire_overrun(cfg)


## Fires one overrun burst: picks a cached variant, applies a per-event pitch
## jitter from _pop_rng (so two lifts are not identical), then plays it. No-op
## when no player exists (headless / not opted in).
func _fire_overrun(cfg: CarConfig) -> void:
	if _pop_player == null or cfg == null:
		return
	var style := normalize_pop_style(cfg.exhaust_pop_style)
	var amount := clampf(cfg.exhaust_pop_intensity, 0.0, 2.0)
	var variant := _pop_rng.randi_range(0, POP_VARIANTS - 1)
	var seed := DEFAULT_POP_SEED + variant
	var key := pop_bank_key(style, cfg.exhaust_pop_duration, amount, seed)
	var stream: AudioStreamWAV = null
	if _pop_bank_cache.has(key):
		stream = _pop_bank_cache[key] as AudioStreamWAV
	else:
		stream = build_pop_burst(style, cfg.exhaust_pop_duration, amount, POP_SAMPLE_RATE, seed)
		_pop_bank_cache[key] = stream
	if stream == null:
		return
	_pop_player.stream = stream
	_pop_player.pitch_scale = pop_pitch_jitter(_pop_rng)
	var trim: float = cfg.exhaust_pop_gain_db if cfg != null else POP_GAIN_TRIM_DB
	_pop_player.volume_db = clampf(trim + extra_trim_db, MUTE_FLOOR_DB, 6.0)
	_pop_player.play()


func _physics_process(delta: float) -> void:
	if _band_players.is_empty():
		return
	# Distance LOD for non-player sources (rivals). MUST run BEFORE the _culled
	# early-return below: once culled the function returns there, so a check
	# placed after it could never un-cull. A null player (tests / free-roam
	# moments) keeps the emitter ACTIVE instead of silently muting it.
	if auto_cull_range > 0.0 and not _is_player:
		var ref := VehicleManager.get_player_car()
		if ref != null:
			cull_by_distance(ref.global_position, auto_cull_range)
	if _culled:
		for player in _band_players:
			if player.playing:
				player.stop()
		for player in _turbo_players:
			if player.playing:
				player.stop()
		for player in _engine_layer_players:
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
	_update_turbo(cfg, info, rpm_norm, throttle, delta)

	# Exhaust overrun layer (presentation-only): create lazily like the turbo
	# layer, then evaluate the overrun trigger. Same ordering rule -- it reads
	# _prev_throttle (last frame's value) for the shared lift edge, so it MUST
	# run before the line that overwrites _prev_throttle just below.
	_ensure_pop_layer(cfg)
	_update_overrun(cfg, rpm_norm, throttle, gear, delta)

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
	_ensure_engine_layers()
	_update_engine_layers(info, live_rpm, rpm_norm, throttle, delta)
	var load_gain: float = float(shaping["gain_db"])
	var shift_pitch := gear_shift_pitch_mult(_shift_elapsed)
	var trans_db := transient_gain_db(_shift_elapsed, _lift_env)

	for i in range(_band_players.size()):
		var player := _band_players[i]
		player.pitch_scale = band_pitch_scale_window(live_rpm, _band_rpms[i], _pitch_min, _pitch_max) * shift_pitch
		var target_db := clampf(band_gain_db(weights[i], load_gain, trans_db) + _trim_db + extra_trim_db, MUTE_FLOOR_DB, 6.0)
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
	_flutter_cooldown = 0.0
	_throttle_peak = 0.0
	for i in range(_engine_layer_players.size()):
		_engine_layer_players[i].volume_db = MUTE_FLOOR_DB
		_engine_layer_lin[i] = 0.0
		if _engine_layer_players[i].playing:
			_engine_layer_players[i].stop()
	_turbo_whine_lin = 0.0
	if active:
		_prev_boost_fraction = 0.0
		_turbo_boost = 0.0


func cull_by_distance(camera_pos: Vector3, range_m: float) -> void:
	set_audio_active(global_position.distance_to(camera_pos) <= range_m)


## Idempotent, additive sibling of the rival scene's own EngineAudio node: returns
## the existing "EngineAudio" child when the car already ships one, otherwise
## creates a configured rivals-grade node and parents it to `car`. Lets a
## swapped-in rival scene (RaceManager.set_rival_vehicle_scene) or a future
## spawner guarantee audible rival engines without duplicating the node. Player +
## traffic already own their nodes, so this is a no-op for them.
static func ensure_for(car: VehiclePhysics) -> EngineAudio:
	if car == null:
		return null
	var existing := car.get_node_or_null("EngineAudio") as EngineAudio
	if existing != null:
		return existing
	var audio := EngineAudio.new()
	audio.name = "EngineAudio"
	audio.auto_cull_range = 150.0
	audio.extra_trim_db = -4.0
	audio.spatial_max_distance = 60.0
	car.add_child(audio)
	return audio


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


## Smoothed audio boost state. `state` chases the Drivetrain's raw
## boost_fraction with a rate limit: rising at TURBO_SPOOL_UP_RATE, falling at a
## rate blended from TURBO_HOLD_DECAY_RATE (driver on the gas, throttle >=
## TURBO_ON_THROTTLE -- bridges the per-upshift boost dip) to
## TURBO_SPOOL_DOWN_RATE (throttle <= TURBO_LIFT_THROTTLE -- real spool-down).
## Pure + deterministic; the result stays within 0..1.
static func turbo_boost_step(state: float, raw_boost: float, throttle: float, delta: float) -> float:
	var target := clampf(raw_boost, 0.0, 1.0)
	var cur := clampf(state, 0.0, 1.0)
	if target >= cur:
		return clampf(move_toward(cur, target, TURBO_SPOOL_UP_RATE * delta), 0.0, 1.0)
	var k := clampf((throttle - TURBO_LIFT_THROTTLE) / (TURBO_ON_THROTTLE - TURBO_LIFT_THROTTLE), 0.0, 1.0)
	var down := lerpf(TURBO_SPOOL_DOWN_RATE, TURBO_HOLD_DECAY_RATE, k)
	return clampf(move_toward(cur, target, down * delta), 0.0, 1.0)


## Whistle pitch_scale: a gentle rise with boost (75%) and slow rpm (25%),
## bounded to TURBO_PITCH_MIN..TURBO_PITCH_MAX.
static func turbo_whine_pitch(boost: float, rpm_slow: float) -> float:
	var load := clampf(0.75 * clampf(boost, 0.0, 1.0) + 0.25 * clampf(rpm_slow, 0.0, 1.0), 0.0, 1.0)
	return lerpf(TURBO_PITCH_MIN, TURBO_PITCH_MAX, load)


## One-pole smoothing of a LINEAR amplitude with time constant `tau`
## (frame-rate independent) so volume changes never jump in dB.
static func ema_linear(current: float, target: float, delta: float, tau: float) -> float:
	return lerpf(current, target, 1.0 - exp(-maxf(delta, 0.0) / maxf(tau, 0.0001)))


## Induction roar level: only on throttle, rising with rpm. Mute floor when the
## driver is off the gas (coast/overrun is then just bed + pops).
static func intake_roar_gain_db(throttle: float, rpm_norm: float) -> float:
	var t := clampf((throttle - 0.08) / 0.92, 0.0, 1.0)
	if t <= 0.001:
		return MUTE_FLOOR_DB
	var linear := pow(t, 1.3) * lerpf(0.30, 1.0, clampf(rpm_norm, 0.0, 1.0))
	return clampf(linear_to_db(linear) + ROAR_TRIM_DB, MUTE_FLOOR_DB, 6.0)


## Roar pitch: its firing-rate pulsing tracks the engine (authored at ROAR_REF_RPM).
static func intake_roar_pitch(live_rpm: float) -> float:
	return clampf(live_rpm / ROAR_REF_RPM, 0.45, 1.8)


## GR6 gear/final-drive whine level: fades in with road speed, stronger on
## throttle (drive side) than on coast. Mute floor when parked.
static func gear_whine_gain_db(speed_kmh: float, throttle: float) -> float:
	var v := clampf((absf(speed_kmh) - 5.0) / 115.0, 0.0, 1.0)
	if v <= 0.001:
		return MUTE_FLOOR_DB
	var linear := v * v * (3.0 - 2.0 * v) * (0.45 + 0.55 * clampf(throttle, 0.0, 1.0))
	return clampf(linear_to_db(linear) + GEAR_WHINE_TRIM_DB, MUTE_FLOOR_DB, 6.0)


## Gear-whine pitch follows ROAD SPEED (rises monotonically with km/h).
static func gear_whine_pitch(speed_kmh: float) -> float:
	return clampf(absf(speed_kmh) / GEAR_WHINE_REF_KMH, 0.15, 3.5)


## True when the roar / gear-whine players should exist: the gtr bed set and
## NOT the headless display server.
static func should_create_engine_layers(bed_set: String, display_name: String) -> bool:
	return bed_set == TIMBRE_GTR and display_name != "headless"


## Loads the roar / gear-whine loops as seamless LOOP_FORWARD (same QOA
## loop_end snap as load_beds_for()). Missing files degrade to null (silence).
static func load_engine_layer_assets() -> Dictionary:
	var streams := {}
	for key: String in ENGINE_LAYER_ASSETS:
		var path: String = ENGINE_LAYER_ASSETS[key]
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
		streams[key] = stream
	return streams


## Blow-off valve command: louder the more boost was built when the throttle
## lifted. 0 boost => the mute floor, monotonic.
static func bov_gain_db(boost_fraction: float) -> float:
	if boost_fraction <= 0.001:
		return MUTE_FLOOR_DB
	return clampf(linear_to_db(clampf(boost_fraction, 0.0, 1.0)) + TURBO_BOV_TRIM_DB, MUTE_FLOOR_DB, 6.0)


## Wastegate flutter command: a little quieter than the BOV at the same boost.
## 0 boost => the mute floor, monotonic. The synthesised flutter files peak at
## 0.85 (the retired flutter_hits.wav peaked at 0.44), hence the 5.7 dB lower
## TURBO_FLUTTER_TRIM_DB.
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


## Length in seconds of a one-shot stream (0 when missing).
static func _stream_seconds(stream: AudioStream) -> float:
	if stream == null:
		return 0.0
	return stream.get_length()


## Flutter strength tier from the boost at lift-off: 0 below the first edge,
## 1 below the second, else 2. Monotonic in boost.
static func flutter_tier(boost: float) -> int:
	var tier := 0
	for edge in TURBO_FLUTTER_TIER_EDGES:
		if boost >= edge:
			tier += 1
	return tier


## Picks a variant index in [0, count) from a 0..1 random draw, never equal to
## `last` when count > 1 (so the same sample never plays twice in a row).
static func pick_variant(count: int, last: int, r01: float) -> int:
	if count <= 1:
		return 0
	var r := clampf(r01, 0.0, 0.999999)
	if last < 0 or last >= count:
		return int(r * count)
	var idx := int(r * (count - 1))
	return idx + 1 if idx >= last else idx


## Playback-rate scale: the boost sets a 0.92..1.08 base (more boost = faster,
## higher flutter), then a +/-3 % per-event random factor from r01 (0..1).
static func flutter_pitch_scale(boost: float, r01: float) -> float:
	var base := lerpf(TURBO_FLUTTER_RATE_SCALE_MIN, TURBO_FLUTTER_RATE_SCALE_MAX, clampf(boost, 0.0, 1.0))
	return base * (1.0 + TURBO_FLUTTER_PITCH_JITTER * (2.0 * clampf(r01, 0.0, 1.0) - 1.0))


## True on the throttle lift edge: the classic single-frame 0.5 -> 0.15 drop,
## or an analog fast lift (fall of more than TURBO_FAST_LIFT_DROP from the
## short-memory `throttle_peak`, ending below TURBO_FAST_LIFT_END).
static func is_lift_edge(prev_throttle: float, throttle: float, throttle_peak: float = 0.0) -> bool:
	if prev_throttle > 0.5 and throttle < 0.15:
		return true
	return throttle_peak > 0.5 and throttle_peak - throttle > TURBO_FAST_LIFT_DROP \
			and throttle < TURBO_FAST_LIFT_END


## Whether the wastegate flutter fires this frame: lift edge, boost above
## TURBO_FLUTTER_MIN_FRACTION, cooldown expired, wastegate fitted.
static func flutter_should_fire(prev_throttle: float, throttle: float, boost: float, cooldown: float, has_wastegate: bool, throttle_peak: float = 0.0) -> bool:
	return has_wastegate and cooldown <= 0.0 and boost > TURBO_FLUTTER_MIN_FRACTION \
			and is_lift_edge(prev_throttle, throttle, throttle_peak)


## Whether the blow-off valve fires this frame: lift edge, boost above
## TURBO_BOV_MIN_FRACTION, cooldown expired.
static func bov_should_fire(prev_throttle: float, throttle: float, boost: float, cooldown: float, throttle_peak: float = 0.0) -> bool:
	return cooldown <= 0.0 and boost > TURBO_BOV_MIN_FRACTION \
			and is_lift_edge(prev_throttle, throttle, throttle_peak)


## Loads the flutter / blow-off one-shot variants as
## {"flutter": [[AudioStreamWAV x2] per tier lo/mid/hi], "bov": [AudioStreamWAV x2]}
## with looping disabled. A missing file degrades to a shorter array (silence),
## like load_turbo_assets().
static func load_flutter_variants() -> Dictionary:
	var tiers: Array = []
	for tier in range(TURBO_FLUTTER_TIER_EDGES.size() + 1):
		var pool: Array = []
		var paths: Array = TURBO_FLUTTER_VARIANTS.get(tier, [])
		for path in paths:
			var wav := _load_oneshot(String(path))
			if wav != null:
				pool.append(wav)
		tiers.append(pool)
	var bovs: Array = []
	for path in TURBO_BOV_VARIANTS:
		var wav := _load_oneshot(path)
		if wav != null:
			bovs.append(wav)
	return {"flutter": tiers, "bov": bovs}


static func _load_oneshot(path: String) -> AudioStreamWAV:
	if not ResourceLoader.exists(path):
		return null
	var wav := load(path) as AudioStreamWAV
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return wav


## --- Exhaust overrun (pops & bangs) statics --------------------------------
## Pure, deterministic core of the overrun layer: style normalization, the
## burst's pop count / window, the trigger truth table, the per-event pitch
## jitter, the bank cache key and the runtime burst synthesis. No engine/scene
## dependency, so every one is unit-testable headless.

## Unknown/empty styles fall back to the shipped "crackle" character.
static func normalize_pop_style(style: String) -> String:
	if POP_STYLES.has(style):
		return style
	return "crackle"


## Pop count for a burst: a style-aware base scaled by the clamped intensity.
## Monotonic non-decreasing in intensity; a zero intensity gives zero pops.
static func pop_count_for(style: String, intensity: float) -> int:
	var amt := clampf(intensity, 0.0, 2.0)
	var base := 9.0
	match normalize_pop_style(style):
		"burble":
			base = 3.0
		"bang":
			base = 2.0
		_:
			base = 9.0
	return clampi(int(round(base * amt)), 0, 24)


## Overrun window (seconds): the requested duration clamped to [0.1, 3.0], with
## a small style nudge (burbles run long, bangs short). Sampled from real
## overrun maps only approximately -- these are ear-tuned starting points.
static func pop_duration_for(style: String, duration: float) -> float:
	var scale := 1.0
	match normalize_pop_style(style):
		"burble":
			scale = 1.15
		"bang":
			scale = 0.85
	return clampf(duration * scale, 0.1, 3.0)


## Pure overrun trigger truth: opted in AND the shared throttle-lift edge AND
## revs above the per-car floor AND not reverse AND the anti-machine-gun cooldown
## has expired. Built on the same edge as the BOV/flutter voices so a single
## lift produces one coherent event.
static func overrun_should_fire(prev_throttle: float, throttle: float, rpm_norm: float, gear: int, enabled: bool, min_rpm_fraction: float, cooldown: float) -> bool:
	if not enabled:
		return false
	if cooldown > 0.0:
		return false
	if gear == -1:
		return false
	if clampf(rpm_norm, 0.0, 1.0) < clampf(min_rpm_fraction, 0.0, 1.0):
		return false
	return prev_throttle > POP_RELEASE_HI and throttle < POP_RELEASE_LO


## Per-event pitch jitter (deterministic given the caller's RNG) so two lifts
## are audibly not identical. Pure static for testability.
static func pop_pitch_jitter(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(POP_PITCH_MIN, POP_PITCH_MAX)


## Bank cache key for one burst (style + window + intensity bucket + seed).
static func pop_bank_key(style: String, duration: float, intensity: float, seed: int) -> String:
	return "%s|%.3f|%.3f|%d" % [normalize_pop_style(style), pop_duration_for(style, duration), clampf(intensity, 0.0, 2.0), seed]


## True when the pop players should exist for this config on this display
## server: an opted-in car NOT running headless (mirrors
## should_create_turbo_players). Pure static for testability.
static func should_create_pop_players(cfg: CarConfig, display_name: String) -> bool:
	if cfg == null or not cfg.exhaust_pop_enabled:
		return false
	return display_name != "headless"


## Builds one deterministic overrun burst as a 16-bit mono AudioStreamWAV. The
## whole burst is a single stream, so once started Godot mixes it
## sample-accurately and the sound is identical at any frame rate. `intensity`
## is clamped to [0, 2]; every random draw comes from an RNG seeded with `seed`,
## so identical inputs produce byte-identical data. Runtime-built WAVs also
## sidestep the QOA loop-end import trap entirely.
static func build_pop_burst(style: String, duration: float, intensity: float, sample_rate: int, seed: int) -> AudioStreamWAV:
	var named := normalize_pop_style(style)
	var sr := clampi(sample_rate, 4000, 192000)
	var dur := pop_duration_for(named, duration)
	var amt := clampf(intensity, 0.0, 2.0)
	var frames := maxi(int(round(dur * float(sr))), 1)
	var samples := PackedFloat32Array()
	samples.resize(frames)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	# Per-style transient shaping (APPROXIMATE ear-tuned starting points, not
	# measurements): crackle = sharp high-passed noise, bang = dull low-passed
	# boom with a strong body tone, burble = soft band-limited thock.
	var pop_tc := 0.02
	var body_gain := 0.18
	var noise_gain := 1.0
	var lp_hz := 0.0
	var hp_hz := 0.0
	var body_lo := 80.0
	var body_hi := 130.0
	match named:
		"burble":
			pop_tc = 0.05
			body_gain = 0.55
			noise_gain = 0.7
			lp_hz = 1400.0
			body_lo = 60.0
			body_hi = 110.0
		"bang":
			pop_tc = 0.09
			body_gain = 1.0
			noise_gain = 0.5
			lp_hz = 700.0
			body_lo = 55.0
			body_hi = 95.0
		_:
			pop_tc = 0.02
			body_gain = 0.18
			noise_gain = 1.0
			hp_hz = 1600.0
			body_lo = 80.0
			body_hi = 130.0

	var count := pop_count_for(named, amt)
	var mean_gap := dur / float(maxi(count, 1))
	var pos := 0.0
	for p in range(count):
		if p == 0:
			pos = rng.randf() * minf(0.02, mean_gap * 0.3)
		else:
			pos += mean_gap * (0.45 + 1.1 * rng.randf())
		var t_start := pos
		if t_start >= dur:
			break
		var this_tc := pop_tc * (0.7 + 0.8 * rng.randf())
		var body_freq := lerpf(body_lo, body_hi, rng.randf())
		var pop_amp := 0.7 + 0.3 * rng.randf()
		var env := pow(maxf(1.0 - t_start / dur, 0.0), 0.8)
		var start_frame := int(round(t_start * float(sr)))
		var tail := int(round(this_tc * 6.0 * float(sr)))
		var hp_alpha := 0.0
		if hp_hz > 0.0:
			hp_alpha = 1.0 - exp(-TAU * hp_hz / float(sr))
		var lp_alpha := 0.0
		if lp_hz > 0.0:
			lp_alpha = 1.0 - exp(-TAU * lp_hz / float(sr))
		var lp_state := 0.0
		for k in range(tail):
			var idx := start_frame + k
			if idx >= frames:
				break
			var t := float(k) / float(sr)
			var shape := (1.0 - exp(-t / 0.0015)) * exp(-t / maxf(this_tc, 0.001))
			var noise := rng.randf() * 2.0 - 1.0
			var shaped := noise
			if hp_hz > 0.0:
				lp_state += (noise - lp_state) * hp_alpha
				shaped = noise - lp_state
			elif lp_hz > 0.0:
				lp_state += (noise - lp_state) * lp_alpha
				shaped = lp_state
			var body := sin(TAU * body_freq * t) * body_gain
			samples[idx] += (shaped * noise_gain + body) * pop_amp * env * shape

	# Normalize to an intensity-scaled target peak (never above 0.95) so the
	# burst level is monotonic in intensity and can never clip.
	var raw_peak := 0.0
	for i in range(frames):
		raw_peak = maxf(raw_peak, absf(samples[i]))
	var target_peak := 0.95 * clampf(0.25 + 0.75 * amt / 2.0, 0.0, 1.0)
	var gain := 0.0
	if raw_peak > 0.0000001:
		gain = target_peak / raw_peak
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var s := clampf(samples[i] * gain, -0.95, 0.95)
		data.encode_s16(i * 2, int(round(s * 32767.0)))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.loop_begin = 0
	wav.loop_end = 0
	wav.data = data
	return wav


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
		_route_to_vehicle_bus()
		return
	# The shaping low-pass lives on the dedicated Vehicle bus (never Master) so
	# music routed through Master is not muffled by engine shaping.
	AudioRouting.ensure_buses()
	_lpf_bus_index = AudioServer.get_bus_index(VEHICLE_BUS)
	if _lpf_bus_index < 0:
		_lpf_added = true
		return
	_route_to_vehicle_bus()
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


## Sends this node and every sound player directly below it to the Vehicle bus.
## Only the PLAYER car calls this (via _ensure_lpf); rivals stay on Master.
## Re-runs when children were added since the last pass (lazy feel players).
func _route_to_vehicle_bus() -> void:
	if _lpf_bus_index < 0 or _routed_child_count == get_child_count():
		return
	_routed_child_count = get_child_count()
	bus = VEHICLE_BUS
	for child in get_children():
		if child is AudioStreamPlayer3D:
			(child as AudioStreamPlayer3D).bus = VEHICLE_BUS


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