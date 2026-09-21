class_name BodyRig
extends Node3D

## Additive visual suspension rig sitting on CarBody: bounds pitch by
## accel/brake and roll by steer, lerped each frame from the drive_info
## readout (toward the target at ~LERP_FACTOR) and hard-clamped to the
## plan's ± values. Pure math: no physics, no scene dependencies.

const PITCH_ACCEL_DEG := -2.0
const PITCH_BRAKE_DEG := 3.0
const ROLL_MAX_DEG := 2.0
const LERP_FACTOR := 0.1
const SETTLE_EPSILON_DEG := 0.25

var _target_pitch_deg := 0.0
var _target_roll_deg := 0.0
var _pitch_deg := 0.0
var _roll_deg := 0.0

func _process(delta: float) -> void:
	var car := _find_car()
	if car == null:
		return
	apply_drive_info(car.get_drive_info(), delta)

func _find_car() -> VehiclePhysics:
	var node := get_parent() as Node
	while node != null:
		if node is VehiclePhysics:
			return node as VehiclePhysics
		node = node.get_parent()
	return null

## Reader entry point used by tests: converts a drive_info dictionary into
## bounded pitch/roll targets and steps toward them.
func apply_drive_info(info: Dictionary, delta: float) -> void:
	set_targets(
		float(info.get("throttle", 0.0)),
		float(info.get("brake", 0.0)),
		float(info.get("steer", 0.0))
	)
	step(delta)

func set_targets(throttle: float, brake: float, steer: float) -> void:
	_target_pitch_deg = clampf(
		PITCH_ACCEL_DEG * clampf(throttle, 0.0, 1.0)
		+ PITCH_BRAKE_DEG * clampf(brake, 0.0, 1.0),
		PITCH_ACCEL_DEG, PITCH_BRAKE_DEG
	)
	_target_roll_deg = clampf(steer * ROLL_MAX_DEG, -ROLL_MAX_DEG, ROLL_MAX_DEG)

func step(delta: float) -> void:
	if delta <= 0.0:
		return
	var t := clampf(LERP_FACTOR * delta * 60.0, 0.0, 1.0)
	_pitch_deg = lerpf(_pitch_deg, _target_pitch_deg, t)
	_roll_deg = lerpf(_roll_deg, _target_roll_deg, t)
	_apply_pose()

func _apply_pose() -> void:
	rotation = Vector3(deg_to_rad(_pitch_deg), rotation.y, deg_to_rad(_roll_deg))

func get_pitch_deg() -> float:
	return _pitch_deg

func get_roll_deg() -> float:
	return _roll_deg

func get_target_pitch_deg() -> float:
	return _target_pitch_deg

func get_target_roll_deg() -> float:
	return _target_roll_deg

func is_settled(epsilon_deg: float = SETTLE_EPSILON_DEG) -> bool:
	return absf(_pitch_deg) <= epsilon_deg and absf(_roll_deg) <= epsilon_deg