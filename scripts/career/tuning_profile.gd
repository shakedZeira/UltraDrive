# scripts/career/tuning_profile.gd
class_name TuningProfile
extends RefCounted

## S13 garage tuning: a per-car override dict clamped to sane config bounds,
## applied to a base CarConfig via with_overrides(). RefCounted and purely
## data — save-round-trippable through the Garage tuning block. Sliders expose
## a normalized 0..1 travel that maps onto a +/-30% factor band.

## Unit-bound multipliers for every tunable. Slider 0.0 -> 0.7x, 1.0 -> 1.3x.
const RATIO_MIN_FACTOR := 0.7
const RATIO_MAX_FACTOR := 1.3
const FINAL_DRIVE_MIN_FACTOR := 0.7
const FINAL_DRIVE_MAX_FACTOR := 1.3
const MASS_MIN_FACTOR := 0.7
const MASS_MAX_FACTOR := 1.3

## Wheel radius (m) used by the dyno wheel-force math; matches CarVisuals and
## the physics tire radius.
const WHEEL_RADIUS := 0.33

var base_config: CarConfig = null
var overrides: Dictionary = {}

func _init(config: CarConfig = null) -> void:
	base_config = config

# --- Normalized slider <-> factor conversion (shared +-30% band) ---

static func slider_to_factor(t: float) -> float:
	return lerpf(RATIO_MIN_FACTOR, RATIO_MAX_FACTOR, clampf(t, 0.0, 1.0))

static func factor_to_slider(f: float) -> float:
	return clampf((f - RATIO_MIN_FACTOR) / (RATIO_MAX_FACTOR - RATIO_MIN_FACTOR), 0.0, 1.0)

# --- Bounds / clamps (defined as +/-30% of the base value) ---

static func clamp_ratio(value: float, base: float) -> float:
	return clampf(value, base * RATIO_MIN_FACTOR, base * RATIO_MAX_FACTOR)

static func clamp_final_drive(value: float, base: float) -> float:
	return clampf(value, base * FINAL_DRIVE_MIN_FACTOR, base * FINAL_DRIVE_MAX_FACTOR)

static func clamp_mass(value: float, base: float) -> float:
	return clampf(value, base * MASS_MIN_FACTOR, base * MASS_MAX_FACTOR)

# --- Setters (store absolute values, clamped to the base band) ---

func set_gear_ratio(index: int, value: float) -> void:
	if base_config == null or index < 0 or index >= base_config.gear_ratios.size():
		return
	var ratios := _gear_ratios()
	ratios[index] = clamp_ratio(value, base_config.gear_ratios[index])
	overrides["gear_ratios"] = ratios

func set_final_drive(value: float) -> void:
	if base_config == null:
		return
	overrides["final_drive_ratio"] = clamp_final_drive(value, base_config.final_drive_ratio)

func set_mass(value: float) -> void:
	if base_config == null:
		return
	overrides["mass_kg"] = clamp_mass(value, base_config.mass_kg)

func clear_override(key: String) -> void:
	overrides.erase(key)

# --- Getters (override wins, otherwise the base value) ---

func get_gear_ratio(index: int) -> float:
	if base_config == null or index < 0:
		return 0.0
	if overrides.has("gear_ratios") and overrides["gear_ratios"] is Array:
		var ratios: Array = overrides["gear_ratios"]
		if index < ratios.size():
			return ratios[index]
	return base_config.gear_ratios[index]

func get_final_drive() -> float:
	if overrides.has("final_drive_ratio"):
		return overrides["final_drive_ratio"]
	return base_config.final_drive_ratio if base_config != null else 0.0

func get_mass() -> float:
	if overrides.has("mass_kg"):
		return overrides["mass_kg"]
	return base_config.mass_kg if base_config != null else 0.0

# --- Whole-profile save / load ---

## Serializes the (clamped) override dict for the garage tuning block.
func to_dict() -> Dictionary:
	return overrides.duplicate(true)

## Ingests a stored dict, re-clamping every recognized key to the base band so
## hand-edited or corrupt saves can never push a ratio negative.
func from_dict(stored: Dictionary) -> void:
	if base_config == null:
		overrides = stored.duplicate(true)
		return
	var out: Dictionary = {}
	if stored.has("gear_ratios") and stored["gear_ratios"] is Array:
		var ratios := base_config.gear_ratios.duplicate()
		var src: Array = stored["gear_ratios"]
		for i in mini(src.size(), ratios.size()):
			ratios[i] = clamp_ratio(src[i], base_config.gear_ratios[i])
		out["gear_ratios"] = ratios
	if stored.has("final_drive_ratio") and stored["final_drive_ratio"] is float:
		out["final_drive_ratio"] = clamp_final_drive(stored["final_drive_ratio"], base_config.final_drive_ratio)
	if stored.has("mass_kg") and stored["mass_kg"] is float:
		out["mass_kg"] = clamp_mass(stored["mass_kg"], base_config.mass_kg)
	overrides = out

## The tuned config: base with the clamped overrides applied. Base untouched.
func applied() -> CarConfig:
	if base_config == null:
		return null
	return base_config.with_overrides(overrides)

# --- Pure-static engine dyno (testable without any UI) ---

## Samples torque/power over idle..redline. Each entry: rpm, torque (N m from
## config.get_engine_torque), power (W = torque * angular velocity) and the
## wheel drive force (N) that the combined 1st-gear ratio puts to the road.
static func dyno_samples(config: CarConfig, samples: int = 32) -> Array[Dictionary]:
	if config == null or samples < 2:
		return []
	var out: Array[Dictionary] = []
	var combined := 0.0
	if config.gear_ratios.size() > 0:
		combined = config.gear_ratios[0] * config.final_drive_ratio
	for i in samples:
		var t := float(i) / float(samples - 1)
		var rpm := lerpf(config.idle_rpm, config.redline_rpm, t)
		var torque := config.get_engine_torque(rpm)
		var omega := rpm * TAU / 60.0
		var force := torque * combined / WHEEL_RADIUS if WHEEL_RADIUS > 0.0 else 0.0
		out.append({
			"rpm": rpm,
			"torque": torque,
			"power": torque * omega,
			"wheel_force": force,
		})
	return out

## Peak crankshaft power in hp (1 hp = 745.7 W) across the rev range.
static func peak_power_hp(config: CarConfig) -> float:
	var peak: float = 0.0
	for sample in dyno_samples(config, 64):
		var power := float(sample["power"])
		if power > peak:
			peak = power
	return peak / 745.7

# ---

func _gear_ratios() -> Array[float]:
	var ratios := base_config.gear_ratios.duplicate()
	if overrides.has("gear_ratios") and overrides["gear_ratios"] is Array:
		var src: Array = overrides["gear_ratios"]
		for i in mini(src.size(), ratios.size()):
			ratios[i] = src[i]
	return ratios