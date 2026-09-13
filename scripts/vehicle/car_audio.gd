class_name CarAudio
extends AudioStreamPlayer3D

## Procedural engine sound.
## Synthesizes three narrow-band PCM loops ("beds") at runtime (no asset
## required), then equal-power crossfades between them from engine RPM so the
## sweep never reads as chipmunk: each bed is only ever pitched within a narrow
## band (~0.9-1.25x) around its own center fundamental. An on-load / off-load
## layer adds gain and raises the low-pass cutoff with throttle. Each car
## drives a distinct EngineProfile (timbre) via CarConfig:
##   - "sport"  inline 6, smooth with dominant firing-order partials
##   - "muscle" V8, deep growl with strong even harmonics + extra rasp
##   - "rally"  turbo 4, buzzy rasp with a high whistle-like partial + noise
## Attach as a child of a VehiclePhysics node.

const IDLE_RPM: float = 800.0
const REDLINE_RPM: float = 7000.0
const LOOP_HZ: float = 50.0
const SAMPLE_RATE: int = 44100

# --- Multi-bed narrow-band design ---
## Each bed's center ratio multiplies the profile loop fundamental; the bed is
## then pitched only within [PITCH_MIN, PITCH_MAX] around that center. The
## centers climb across the rev range while the per-bed multiplication stays
## small, so the crossfade never jumps a whole octave (no chipmunk).
const BED_CENTERS: Array[float] = [0.95, 1.6, 2.6]
const PITCH_MIN: float = 0.9
const PITCH_MAX: float = 1.25

## Normalized-RPM anchors for the equal-power crossfade (idle / mid / top).
const CROSSFADE_CENTERS: Array[float] = [0.0, 0.5, 1.0]

# --- On-load / off-load shaping ---
const LOAD_GAIN_DB: float = 6.0
const LOAD_DERIV_GAIN: float = 20.0
const LPF_OFF_HZ: float = 1400.0
const LPF_ON_HZ: float = 5000.0
const LPF_ENGAGE_LOAD: float = 0.5
const LPF_PASSTHROUGH_HZ: float = 20000.0
const MUTE_FLOOR_DB: float = -80.0
const MASTER_TRIM_DB: float = -3.0

## Traffic cars beyond this distance from the listener get their engine
## players stopped entirely (distance-based audio culling in TrafficSpawner).
const TRAFFIC_AUDIO_RANGE: float = 120.0

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
var _beds: Array[Dictionary] = []
var _bed_players: Array[AudioStreamPlayer3D] = []
var _prev_rpm_norm: float = 0.0
var _rpm_deriv: float = 0.0
var _culled: bool = false
var _is_player: bool = false
var _lpf_effect: AudioEffectLowPassFilter = null
var _lpf_bus_index: int = -1
var _lpf_added: bool = false

func _ready() -> void:
	unit_size = 2.0
	max_distance = 80.0
	_car = get_parent() as VehiclePhysics
	var cfg := _get_config()
	if cfg != null:
		_profile = PROFILES.get(cfg.engine_timbre, PROFILES["sport"])
	_beds = build_beds(_profile)
	_create_bed_players()
	for player in _bed_players:
		player.play()

func _exit_tree() -> void:
	_remove_lpf()

func _create_bed_players() -> void:
	for i in range(_beds.size()):
		var player := AudioStreamPlayer3D.new()
		player.name = "EngineBed%d" % i
		player.unit_size = unit_size
		player.max_distance = max_distance
		add_child(player)
		player.stream = _beds[i]["wav"]
		_bed_players.append(player)

func _physics_process(_delta: float) -> void:
	if _bed_players.is_empty():
		return
	if _culled:
		for player in _bed_players:
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
	if cfg != null:
		_profile = PROFILES.get(cfg.engine_timbre, PROFILES["sport"])

	var info := _car.get_drive_info()
	var rpm: float = float(info.get("rpm", IDLE_RPM))
	var redline: float = REDLINE_RPM
	if cfg != null:
		redline = cfg.redline_rpm
	var rpm_norm := clampf((rpm - IDLE_RPM) / (redline - IDLE_RPM), 0.0, 1.0)

	# Load blends steady RPM with a trailing RPM derivative so a hard rev
	# "pops" above rest without tracking every speed dip.
	var rpm_delta := rpm_norm - _prev_rpm_norm
	_prev_rpm_norm = rpm_norm
	_rpm_deriv = lerpf(_rpm_deriv, rpm_delta, 0.15)
	var load := clampf(rpm_norm + maxf(_rpm_deriv * LOAD_DERIV_GAIN, 0.0), 0.0, 1.0)

	var weights := crossfade_weights(rpm_norm, CROSSFADE_CENTERS)
	var shaping := load_shaping(load)
	var load_gain: float = shaping["gain_db"]

	for i in range(_bed_players.size()):
		var player := _bed_players[i]
		var bed: Dictionary = _beds[i]
		var weight: float = weights[i]
		player.pitch_scale = lerpf(float(bed["pitch_min"]), float(bed["pitch_max"]), rpm_norm)
		if weight < 0.01:
			player.volume_db = MUTE_FLOOR_DB
			if player.playing:
				player.stop()
		else:
			# Equal-power: weight is a power fraction, so gain its square root
			# before linear_to_db.
			var amplitude: float = sqrt(weight)
			player.volume_db = clampf(linear_to_db(amplitude) + load_gain + MASTER_TRIM_DB, MUTE_FLOOR_DB, 6.0)
			if not player.playing:
				player.play()

	# The on-load low-pass lives on the shared Master bus and is only driven by
	# the player car, so traffic cars never fight each other over the effect.
	var player_car: VehiclePhysics = VehicleManager.get_player_car()
	_is_player = player_car != null and _car == player_car
	if _is_player:
		_ensure_lpf()
		if _lpf_effect != null:
			if load > LPF_ENGAGE_LOAD:
				_lpf_effect.cutoff_hz = float(shaping["lpf_hz"])
			else:
				_lpf_effect.cutoff_hz = LPF_PASSTHROUGH_HZ

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
	_lpf_effect.cutoff_hz = LPF_PASSTHROUGH_HZ
	_lpf_effect.resonance = 0.4
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

# --- Public API ---

func set_audio_active(active: bool) -> void:
	_culled = not active
	for player in _bed_players:
		if active:
			if not player.playing:
				player.play()
		else:
			if player.playing:
				player.stop()

func cull_by_distance(camera_pos: Vector3, range_m: float) -> void:
	set_audio_active(global_position.distance_to(camera_pos) <= range_m)

# --- Static synthesis helpers (deterministic, headless-testable) ---

static func build_beds(profile: Dictionary) -> Array[Dictionary]:
	var loop_hz: float = float(profile.get("loop_hz", LOOP_HZ))
	var weights: Array = profile.get("weights", PROFILES["sport"]["weights"])
	var noise_gain: float = float(profile.get("noise", 0.04))

	var beds: Array[Dictionary] = []
	for center in BED_CENTERS:
		var fundamental := loop_hz * center
		var period := int(round(SAMPLE_RATE / fundamental))
		var data := PackedByteArray()
		data.resize(period * 2)
		# Seeded by profile discriminators + bed center so every car of a given
		# class owns a stable, distinct bed set across runs.
		var rng := RandomNumberGenerator.new()
		rng.seed = int(loop_hz * 1000.0 + noise_gain * 100.0 + center * 10000.0)

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

		beds.append({
			"center_ratio": center,
			"pitch_min": PITCH_MIN,
			"pitch_max": PITCH_MAX,
			"wav": wav,
		})
	return beds

static func crossfade_weights(rpm_norm: float, centers: Array[float]) -> Array[float]:
	var n := centers.size()
	var weights: Array[float] = []
	weights.resize(n)
	for i in range(n):
		weights[i] = 0.0
	var t := clampf(rpm_norm, 0.0, 1.0)
	# Equal-power segment crossfade: within each [centers[i], centers[i+1]]
	# span the two neighbouring beds blend as cos^2/sin^2 which sums to 1.0.
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

static func load_shaping(load: float) -> Dictionary:
	var clamped := clampf(load, 0.0, 1.0)
	return {
		"gain_db": clamped * LOAD_GAIN_DB,
		"lpf_hz": lerpf(LPF_OFF_HZ, LPF_ON_HZ, clamped),
	}

# --- Private helpers (kept from the single-loop implementation) ---

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