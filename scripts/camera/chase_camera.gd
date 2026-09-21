extends Node3D

## Smooth chase camera that follows the vehicle.
## Attach as child of VehiclePhysics or set target in inspector.
##
## Presentation extras (speed look-ahead, gear-shift FOV kick, lateral-g
## shake) are additive and gated behind transients_enabled (default OFF), so
## with defaults the follow/look/FOV math is identical to the original.

@export var target: Node3D
@export var follow_speed: float = 5.0
@export var camera_distance: float = 6.0
@export var camera_height: float = 2.5
@export var fov_min: float = 74.0
@export var fov_max: float = 90.0
@export var fov_speed_factor: float = 0.05

# --- Presentation pass (Task 8: M3). Off by default (backwards compatible). ---
@export var transients_enabled: bool = false
@export var shake_intensity: float = 0.05
@export var lateral_g_sensitivity: float = 0.3
@export var fov_kick_amount: float = 4.0
@export var look_ahead_strength: float = 0.25

# --- Test/debug hooks (-1 speed means "use the real VehiclePhysics path"). ---
@export var debug_speed_kmh: float = -1.0
@export var debug_gear: int = 1

var _camera: Camera3D

# Transient state, reset in _ready.
var _prev_gear: int = 0
var _gear_initialized: bool = false
var _fov_kick: float = 0.0
var _shake_amount: float = 0.0
var _shake_phase: float = 0.0
var _last_forward: Vector3 = Vector3.ZERO

func _ready() -> void:
	_camera = Camera3D.new()
	_camera.fov = fov_min
	add_child(_camera)
	_camera.current = true

	_prev_gear = 0
	_gear_initialized = false
	_fov_kick = 0.0
	_shake_amount = 0.0
	_shake_phase = 0.0
	_last_forward = Vector3.ZERO

	if target == null:
		var parent := get_parent() as Node3D
		if parent is VehiclePhysics:
			target = parent
		else:
			var found := get_parent().find_children("*", "VehiclePhysics", false, false)
			target = found[0] as Node3D if found.size() > 0 else parent

func _physics_process(delta: float) -> void:
	if target == null:
		return
	_update_camera(delta)

# --- Chase-mode gate (S12). The chase camera is the default view; orbit and
# --- others take over only when their camera becomes current. Windshield
# --- droplets are gated on this so only the chase view carries them.
func is_current_view() -> bool:
	return _camera != null and _camera.is_current()

# --- Per-frame update. Extracted so tests can drive frames deterministically
# --- without the physics loop; null-target guard still applies.
func _update_camera(delta: float) -> void:
	if target == null:
		return

	var car := target as VehiclePhysics
	var speed_kmh := 0.0
	var gear := 0
	if debug_speed_kmh >= 0.0:
		speed_kmh = debug_speed_kmh
		gear = debug_gear
	elif car:
		speed_kmh = car.get_speed_kmh()
		gear = int(car.get_drive_info()["gear"])

	if transients_enabled:
		_update_transients(delta, gear)

	# --- Target position (behind and above car) ---
	var target_pos := target.global_position \
		+ target.global_basis.z * camera_distance \
		+ Vector3.UP * camera_height

	# --- Smooth follow ---
	global_position = global_position.lerp(target_pos, follow_speed * delta)

	# --- Look at car (slightly forward-biased at speed when transients on) ---
	var look_target := target.global_position + Vector3.UP * 1.0
	if transients_enabled:
		var look_bias := -target.global_basis.z \
			* clampf(speed_kmh / 200.0, 0.0, 1.0) * look_ahead_strength
		look_target += look_bias
	var look_dir := (look_target - global_position).normalized()
	if look_dir.length() > 0.01:
		_camera.look_at(look_target)

	# --- FOV scaling with speed (+ transient gear-kick setpoint when on) ---
	var target_fov := lerpf(fov_min, fov_max, clampf(speed_kmh / 200.0, 0.0, 1.0))
	var fov_setpoint := target_fov
	if transients_enabled:
		fov_setpoint = target_fov + _fov_kick
	_camera.fov = lerpf(_camera.fov, fov_setpoint, fov_speed_factor)
	if transients_enabled:
		global_position += _shake_offset()

# --- Presentation extras (transients_enabled only) ---

func _update_transients(delta: float, gear: int) -> void:
	_fov_kick = move_toward(_fov_kick, 0.0, (fov_kick_amount / 0.4) * delta)
	if not _gear_initialized:
		_prev_gear = gear
		_gear_initialized = true
	elif gear > _prev_gear:
		_fov_kick = fov_kick_amount
	_prev_gear = gear

	# Lateral-g proxy from the change in forward facing (transform math only).
	var fwd := -target.global_basis.z
	var yaw_rate := 0.0
	if _last_forward.length() > 0.01:
		var a := Vector3(fwd.x, 0.0, fwd.z)
		var b := Vector3(_last_forward.x, 0.0, _last_forward.z)
		if a.length() > 0.01 and b.length() > 0.01:
			yaw_rate = a.signed_angle_to(b, Vector3.UP) / maxf(delta, 0.0001)
	_last_forward = fwd

	var lateral_g := clampf(abs(yaw_rate) * lateral_g_sensitivity, 0.0, 1.0)
	var target_shake := lateral_g * shake_intensity
	_shake_amount = move_toward(_shake_amount, target_shake, shake_intensity * delta)
	_shake_phase = _shake_phase + delta * 25.0

func _shake_offset() -> Vector3:
	if _shake_amount <= 0.0:
		return Vector3.ZERO
	return Vector3(
		sin(_shake_phase) * _shake_amount,
		cos(_shake_phase * 1.37) * _shake_amount * 0.5,
		0.0
	)