class_name VehicleFX
extends Node3D

## Pooled GPUParticles3D FX layer for cars: drift smoke, off-road dust,
## collision sparks, a gated nitro-flame slot and a small tailpipe exhaust
## puff. Emitters are pre-built once
## in _ready and never instantiated at runtime; the emission state machine
## (emission_channels) runs even headless, where a _ready cull builds zero
## GPUParticles3D nodes so the suite stays renderer-free.

const EMITTER_COUNT := 5
const SMOKE_AMOUNT_CAP := 48
const DUST_AMOUNT_CAP := 80
const SPARK_AMOUNT_CAP := 48
const NITRO_AMOUNT_CAP := 32
const EXHAUST_AMOUNT_CAP := 8
const EXHAUST_IDLE_SPEED_KMH := 5.0
const TOTAL_BUDGET := SMOKE_AMOUNT_CAP + DUST_AMOUNT_CAP + SPARK_AMOUNT_CAP + NITRO_AMOUNT_CAP + EXHAUST_AMOUNT_CAP
const SPARK_BURST_FRAMES := 6
const SPARK_MIN_STRENGTH := 300.0

const CHANNEL_SMOKE := "smoke"
const CHANNEL_DUST := "dust"
const CHANNEL_SPARKS := "sparks"
const CHANNEL_FLAME := "flame"
const CHANNEL_EXHAUST := "exhaust"

var _emitters: Dictionary = {}
var _drifting := false
var _surface_key := SurfaceRegistry.ASPHALT
var _nitro_active := false
var _throttle := 0.0
var _speed_kmh := -1.0
var _spark_frames_left := 0
var _sparks_emitting := false

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_build_emitters()
	var holder := get_parent()
	if holder is VehiclePhysics:
		(holder as VehiclePhysics).impact.connect(_on_vehicle_impact)

func _process(_delta: float) -> void:
	var holder := get_parent()
	if holder is VehiclePhysics:
		_drifting = (holder as VehiclePhysics).is_drifting()
		_surface_key = (holder as VehiclePhysics).get_surface_key()
		_throttle = (holder as VehiclePhysics).get_throttle()
		_speed_kmh = (holder as VehiclePhysics).get_speed_kmh()
	_apply_channels()
	if _spark_frames_left > 0:
		_spark_frames_left = maxi(_spark_frames_left - 1, 0)

## Public state setters (tests + upstream wiring drive these directly).

func set_drifting(value: bool) -> void:
	_drifting = value

func set_surface_key(value: String) -> void:
	_surface_key = value

func set_nitro_active(value: bool) -> void:
	_nitro_active = value

func set_throttle(value: float) -> void:
	_throttle = clampf(value, -1.0, 1.0)

func set_speed_kmh(value: float) -> void:
	_speed_kmh = value

func get_surface_key() -> String:
	return _surface_key

## Impact seam: VehiclePhysics emits impact(strength) on sharp velocity-delta
## spikes; sparks are a short pooled burst gated by SPARK_MIN_STRENGTH.
func on_impact(strength: float) -> void:
	if strength < SPARK_MIN_STRENGTH:
		return
	_spark_frames_left = SPARK_BURST_FRAMES

## Desired per-frame channel states, computed regardless of whether the cull
## left any GPUParticles3D nodes behind (headless-safe assertion surface).
func emission_channels() -> Dictionary:
	return {
		CHANNEL_SMOKE: _drifting,
		CHANNEL_DUST: _surface_key != SurfaceRegistry.ASPHALT,
		CHANNEL_SPARKS: _spark_frames_left > 0,
		CHANNEL_FLAME: _nitro_active,
		CHANNEL_EXHAUST: absf(_throttle) > 0.01 or (_speed_kmh >= 0.0 and _speed_kmh < EXHAUST_IDLE_SPEED_KMH),
	}

func emitter_count() -> int:
	return _emitters.size()

static func emitter_budget() -> int:
	return EMITTER_COUNT

func emission_limits() -> Dictionary:
	return {
		CHANNEL_SMOKE: SMOKE_AMOUNT_CAP,
		CHANNEL_DUST: DUST_AMOUNT_CAP,
		CHANNEL_SPARKS: SPARK_AMOUNT_CAP,
		CHANNEL_FLAME: NITRO_AMOUNT_CAP,
		CHANNEL_EXHAUST: EXHAUST_AMOUNT_CAP,
	}

static func channel_cap(channel: String) -> int:
	match channel:
		CHANNEL_SMOKE:
			return SMOKE_AMOUNT_CAP
		CHANNEL_DUST:
			return DUST_AMOUNT_CAP
		CHANNEL_SPARKS:
			return SPARK_AMOUNT_CAP
		CHANNEL_FLAME:
			return NITRO_AMOUNT_CAP
		CHANNEL_EXHAUST:
			return EXHAUST_AMOUNT_CAP
	return 0

static func clamped_channel_amount(channel: String, requested: int) -> int:
	return maxi(mini(requested, channel_cap(channel)), 0)

func _on_vehicle_impact(strength: float) -> void:
	on_impact(strength)

func _build_emitters() -> void:
	_emitters.clear()
	_emitters[CHANNEL_SMOKE] = _make_emitter(
		"FXSmoke", Color(0.70, 0.70, 0.75, 0.35), SMOKE_AMOUNT_CAP, false, Vector3(0.0, 0.4, 1.15), false
	)
	_emitters[CHANNEL_DUST] = _make_emitter(
		"FXDust", Color(0.55, 0.45, 0.30, 0.60), DUST_AMOUNT_CAP, false, Vector3(0.0, 0.4, 1.15), false
	)
	_emitters[CHANNEL_SPARKS] = _make_emitter(
		"FXSparks", Color(1.00, 0.85, 0.30, 1.00), SPARK_AMOUNT_CAP, true, Vector3(0.0, 0.45, -1.35)
	)
	_emitters[CHANNEL_FLAME] = _make_emitter(
		"FXNitro", Color(0.30, 0.60, 1.00, 0.90), NITRO_AMOUNT_CAP, false, Vector3(0.0, 0.3, 1.45)
	)
	_emitters[CHANNEL_EXHAUST] = _build_exhaust_emitter()

func _build_exhaust_emitter() -> GPUParticles3D:
	var emitter := _make_emitter(
		"FXExhaust", Color(0.62, 0.62, 0.66, 0.28), EXHAUST_AMOUNT_CAP, false, Vector3(0.0, 0.25, 1.55)
	)
	emitter.lifetime = 0.45
	var material := emitter.process_material as ParticleProcessMaterial
	material.scale_min = 0.03
	material.scale_max = 0.08
	material.initial_velocity_min = 0.6
	material.initial_velocity_max = 1.2
	material.spread = 15.0
	material.emission_sphere_radius = 0.05
	material.damping_min = 2.0
	material.damping_max = 4.0
	material.gravity = Vector3(0.0, 0.5, 0.0)
	return emitter

func _make_emitter(node_name: String, color: Color, amount: int, one_shot: bool, local_pos: Vector3, local_coords: bool = true) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = node_name
	emitter.amount = amount
	emitter.lifetime = 0.8
	emitter.one_shot = one_shot
	emitter.emitting = false
	emitter.local_coords = local_coords
	emitter.draw_pass_1 = QuadMesh.new()
	var material := ParticleProcessMaterial.new()
	material.color = color
	material.gravity = Vector3(0.0, -2.0, 0.0)
	material.damping_min = 0.5
	material.damping_max = 2.0
	material.scale_min = 0.2
	material.scale_max = 0.6
	material.initial_velocity_min = 0.5
	material.initial_velocity_max = 2.5
	material.direction = Vector3(0.0, 1.0, 0.0)
	material.spread = 35.0
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.3
	emitter.process_material = material
	emitter.position = local_pos
	add_child(emitter)
	return emitter

func _apply_channels() -> void:
	var channels := emission_channels()
	_set_channel(_emitters.get(CHANNEL_SMOKE), bool(channels[CHANNEL_SMOKE]))
	_set_channel(_emitters.get(CHANNEL_DUST), bool(channels[CHANNEL_DUST]))
	var sparks := bool(channels[CHANNEL_SPARKS])
	if sparks and not _sparks_emitting:
		_restart_emitter(_emitters.get(CHANNEL_SPARKS))
	_sparks_emitting = sparks
	_set_channel(_emitters.get(CHANNEL_SPARKS), sparks)
	_set_channel(_emitters.get(CHANNEL_FLAME), bool(channels[CHANNEL_FLAME]))
	_set_channel(_emitters.get(CHANNEL_EXHAUST), bool(channels[CHANNEL_EXHAUST]))

func _set_channel(emitter: Variant, active: bool) -> void:
	if emitter == null:
		return
	(emitter as GPUParticles3D).emitting = active
	(emitter as GPUParticles3D).visible = active

func _restart_emitter(emitter: Variant) -> void:
	if emitter == null:
		return
	(emitter as GPUParticles3D).restart()