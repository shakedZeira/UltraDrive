class_name CarAudio
extends AudioStreamPlayer3D

const IDLE_RPM: float = 800.0
const REDLINE_RPM: float = 7000.0
const SAMPLE_RATE: int = 44100

const BED_CENTERS: Array[float] = [1.0, 2.0, 4.0]
const CROSSFADE_CENTERS: Array[float] = [0.0, 0.5, 1.0]

const LOAD_GAIN_DB: float = 6.0
const LOAD_DERIV_GAIN: float = 20.0
const LPF_OFF_HZ: float = 900.0
const LPF_ON_HZ: float = 8000.0
const MUTE_FLOOR_DB: float = -80.0
const MASTER_TRIM_DB: float = -3.0

const VOL_SLEW_DB: float = 1.6
const LPF_SLEW_HZ: float = 1200.0
const IDLE_WOBBLE_HZ: float = 9.0
const IDLE_WOBBLE_DEPTH: float = 0.02

const TRAFFIC_AUDIO_RANGE: float = 120.0

const TONE_GAIN: float = 0.6
const PULSE_GAIN: float = 0.3
const PULSE_SIGMA: float = 0.08
const HISS_BASE: int = 7
const HISS_COUNT: int = 10
const HISS_FALL: float = 0.72

const PROFILES: Dictionary = {
	"sport": {
		"loop_hz": 50.0,
		"base_pitch": 0.8,
		"redline_pitch": 2.2,
		"weights": [0.45, 0.25, 0.15, 0.10, 0.0, 0.05],
		"noise": 0.05,
		"wobble": 0.1,
		"pulses": 6,
	},
	"muscle": {
		"loop_hz": 42.0,
		"base_pitch": 0.55,
		"redline_pitch": 1.75,
		"weights": [0.40, 0.38, 0.10, 0.30, 0.04, 0.10],
		"noise": 0.09,
		"wobble": 0.14,
		"pulses": 8,
	},
	"rally": {
		"loop_hz": 58.0,
		"base_pitch": 1.0,
		"redline_pitch": 2.6,
		"weights": [0.25, 0.40, 0.28, 0.18, 0.10, 0.16],
		"noise": 0.14,
		"wobble": 0.12,
		"pulses": 4,
	},
}

var _car: VehiclePhysics = null
var _profile: Dictionary = PROFILES["sport"]
var _beds: Array[Dictionary] = []
var _bed_players: Array[AudioStreamPlayer3D] = []
var _vol_ema: Array[float] = []
var _prev_rpm_norm: float = 0.0
var _rpm_deriv: float = 0.0
var _smooth_rpm: float = 0.0
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
		player.volume_db = MUTE_FLOOR_DB
		_bed_players.append(player)
		_vol_ema.append(MUTE_FLOOR_DB)

func _physics_process(delta: float) -> void:
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
	var idle: float = IDLE_RPM
	var redline: float = REDLINE_RPM
	if cfg != null:
		idle = cfg.idle_rpm
		redline = cfg.redline_rpm
	var rpm_norm := clampf((rpm - idle) / maxf(redline - idle, 1.0), 0.0, 1.0)
	var throttle := clampf(float(info.get("throttle", 0.0)), 0.0, 1.0)

	var rpm_delta := rpm_norm - _prev_rpm_norm
	_prev_rpm_norm = rpm_norm
	_rpm_deriv = lerpf(_rpm_deriv, rpm_delta, 0.15)
	var load := clampf(rpm_norm * 0.25 + throttle * 0.55 + maxf(_rpm_deriv, 0.0) * LOAD_DERIV_GAIN * 0.02, 0.0, 1.0)

	_time += delta
	var bound := 4.0 * delta if rpm_norm >= _smooth_rpm else 2.2 * delta
	_smooth_rpm = move_toward(_smooth_rpm, rpm_norm, bound)

	var weights := layer_weights(_smooth_rpm, load)
	var shaping := load_shaping(load)
	var load_gain: float = shaping["gain_db"]

	var base_pitch := float(_profile.get("base_pitch", 0.8))
	var redline_pitch := float(_profile.get("redline_pitch", 2.2))
	var pitch := lerpf(base_pitch, redline_pitch, _smooth_rpm)
	if _smooth_rpm < 0.08 and load < 0.2:
		pitch += sin(_time * IDLE_WOBBLE_HZ * TAU) * IDLE_WOBBLE_DEPTH

	for i in range(_bed_players.size()):
		var player := _bed_players[i]
		var weight: float = weights[i]
		player.pitch_scale = pitch
		var target_db := MUTE_FLOOR_DB
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

func set_audio_active(active: bool) -> void:
	_culled = not active
	for i in range(_bed_players.size()):
		var player := _bed_players[i]
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

static func build_beds(profile: Dictionary) -> Array[Dictionary]:
	var loop_hz: float = float(profile.get("loop_hz", 50.0))
	var weights: Array = profile.get("weights", PROFILES["sport"]["weights"])
	var noise_gain: float = float(profile.get("noise", 0.04))
	var wobble: float = float(profile.get("wobble", 0.12))
	var pulses: int = int(profile.get("pulses", 4))
	var base_pitch: float = float(profile.get("base_pitch", 0.8))
	var redline_pitch: float = float(profile.get("redline_pitch", 2.2))

	var beds: Array[Dictionary] = []
	for center in BED_CENTERS:
		var fundamental := loop_hz * center
		var period := int(round(SAMPLE_RATE / fundamental))
		var wob_cycles := int(clampf(center, 1.0, 3.0))
		var rng := RandomNumberGenerator.new()
		rng.seed = int(loop_hz * 1000.0 + noise_gain * 100.0 + center * 1000.0)

		var phases: Array[float] = []
		phases.resize(weights.size())
		for h in range(weights.size()):
			phases[h] = rng.randf() * TAU
		var hiss_phases: Array[float] = []
		hiss_phases.resize(HISS_COUNT)
		for n in range(HISS_COUNT):
			hiss_phases[n] = rng.randf() * TAU

		var data := PackedByteArray()
		data.resize(period * 2)
		for i in period:
			var wob := sin(TAU * wob_cycles * float(i) / float(period)) * wobble
			var phase := TAU * float(i) / float(period) + wob
			var tone := 0.0
			for h in range(weights.size()):
				var w: float = float(weights[h])
				if w > 0.0:
					tone += sin(phase * float(h + 1) + phases[h]) * w
			var hiss := 0.0
			for n in range(HISS_COUNT):
				var amp: float = pow(HISS_FALL, float(n + 1)) * noise_gain
				hiss += sin(phase * float(HISS_BASE + n) + hiss_phases[n]) * amp
			var pulse := _pulse_env(i, period, pulses)
			var sample := tone * TONE_GAIN + hiss * (0.25 + 0.75 * pulse) + sin(phase) * pulse * PULSE_GAIN
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
			"pitch_min": base_pitch,
			"pitch_max": redline_pitch,
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

static func layer_weights(rpm_norm: float, load: float) -> Array[float]:
	var weights := crossfade_weights(rpm_norm, CROSSFADE_CENTERS)
	var drive := smoothstep(0.15, 0.6, clampf(load, 0.0, 1.0))
	var coast_bass := 0.4 * (1.0 - drive)
	weights[0] = weights[0] + coast_bass
	var total := 0.0
	for i in range(weights.size()):
		total += weights[i]
	if total > 0.0:
		for i in range(weights.size()):
			weights[i] = weights[i] / total
	return weights

static func load_shaping(load: float) -> Dictionary:
	var clamped := clampf(load, 0.0, 1.0)
	return {
		"gain_db": clamped * LOAD_GAIN_DB,
		"lpf_hz": lerpf(LPF_OFF_HZ, LPF_ON_HZ, clamped),
	}

static func _pulse_env(sample_index: int, period: int, pulses: int) -> float:
	if pulses <= 0 or period <= 0:
		return 0.0
	var t := float(sample_index) / float(period)
	var env := 0.0
	for k in range(pulses):
		var center := (float(k) + 0.5) / float(pulses)
		var d := t - center
		env += exp(-0.5 * (d * d) / (PULSE_SIGMA * PULSE_SIGMA))
	return env / float(pulses)

func _get_config() -> CarConfig:
	var parent := get_parent()
	if parent is VehiclePhysics:
		return (parent as VehiclePhysics).config
	return null