extends Node3D

## Cockpit camera: fourth camera mode in the chase / orbit / hood / cockpit
## C-cycle (F1). Driver's-eye view — a rigid eye anchor (seat height/forward
## offset, near plane 0.2) bolted to the car body exactly like the hood cam,
## with layered, strength-scaled feel built on a COPY of the body transform so
## feel never feeds back into the anchor (Bevy rule):
##   - speed FOV (fov_min 60 -> fov_max 68, 1-exp(-k*delta) smoothing; the wide
##     chase/hood widen stays on those cams, cockpit stays mild)
##   - steering lean: roll + lateral offset from a filtered steer angle
##     (never the raw value), capped ~3 deg, INTO the corner
##   - brake dive / accel squat: nose pitch, capped ~2 deg
##   - speed micro-shake: bounded noise, off at standstill
##   - look-into-turn: yaw hint from a steering x speed lateral-velocity proxy
## Every layer is a pure function of (delta, speed, steer, throttle/brake,
## strength) with no feedback loops, delta-scaled so it is FPS-independent, and
## ~0 at rest. Inactive by default so the chase camera stays current; the
## C-cycle in orbit_camera.gd flips it on via set_view_active().

@export var target: Node3D
@export var seat_height: float = 0.42
@export var seat_forward: float = 0.55
@export var fov_min: float = 60.0
@export var fov_max: float = 68.0
@export var fov_k: float = 6.0
@export var full_speed_kmh: float = 200.0
@export var steer_filter_k: float = 8.0
@export var shake_frequency: float = 35.0

# --- Feel strengths, all 0..1. Defaults are arcade-small — the FH5 principle:
# --- shake never ships at 1.0 unless the player opts in (F5 settings expose
# --- these later). ---
@export var steer_lean_strength: float = 0.7
@export var pitch_strength: float = 0.6
@export var shake_strength: float = 0.5
@export var look_turn_strength: float = 0.3
@export var fov_strength: float = 1.0

# --- Caps from the plan research digest (radians / metres). ---
const STEER_ROLL_CAP: float = 0.052        # ~3 deg lean
const STEER_LATERAL_CAP: float = 0.035     # ~0.035 m body shift
const PITCH_CAP: float = 0.035             # ~2 deg dive / squat
const SHAKE_AMP_MAX: float = 0.013         # <= ~0.015 m at full speed
const LOOK_YAW_CAP: float = 0.07           # ~4 deg look-into-turn

# --- Test/debug hooks (-1 speed means "use the real VehiclePhysics path"). ---
@export var debug_speed_kmh: float = -1.0
@export var debug_steer_deg: float = 0.0
@export var debug_throttle: float = 0.0
@export var debug_brake: float = 0.0

var _camera: Camera3D

# Smoothing state (persistent but derived fresh each frame; never fed back
# into the anchor). Time-delta smoothed so the feel is FPS-independent.
var _steer_filtered: float = 0.0
var _shake_phase: float = 0.0

# Last-frame feel readouts (test hooks; derived fresh, never fed back).
var _last_pos_offset: Vector3 = Vector3.ZERO
var _last_roll: float = 0.0
var _last_pitch: float = 0.0
var _last_yaw: float = 0.0

func _ready() -> void:
	_camera = Camera3D.new()
	_camera.fov = fov_min
	_camera.near = 0.2  # cockpit rig near plane (was the generic 0.05)
	add_child(_camera)
	_camera.current = false  # chase camera stays the default view

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

# --- Forward-view gate (F1). Mirrors chase/hood: the cockpit owns the viewport
# --- while current, so windshield droplets carry into the first-person view.
func is_current_view() -> bool:
	return _camera != null and _camera.is_current()

# --- Mode ownership (F1). The C-cycle in orbit_camera.gd calls this to hand
# --- the viewport to the cockpit camera and to release it when cycling away.
func set_view_active(active: bool) -> void:
	if _camera == null:
		return
	_camera.current = active

# --- Readable test hooks ---

func get_cockpit_fov() -> float:
	return _camera.fov if _camera != null else fov_min

func get_seat_anchor() -> Vector3:
	if target == null:
		return global_position
	return target.global_position + Vector3.UP * seat_height \
		- target.global_basis.z * seat_forward

func get_last_pos_offset() -> Vector3:
	return _last_pos_offset

func get_last_roll() -> float:
	return _last_roll

func get_last_pitch() -> float:
	return _last_pitch

func get_last_yaw() -> float:
	return _last_yaw

# --- Per-frame update. Extracted so tests can drive frames deterministically
# --- without the physics loop; null-target guard still applies. Rigid eye
# --- anchor (no lerp, no lag); every feel layer is layered on a COPY of the
# --- body transform, so no frame's output feeds any later frame's anchor.
func _update_camera(delta: float) -> void:
	if target == null:
		return

	var speed_kmh := maxf(_read_speed_kmh(), 0.0)
	var speed_frac := clampf(speed_kmh / full_speed_kmh, 0.0, 1.0)
	var steer_deg := _read_steer_deg()
	var steer_rad := deg_to_rad(steer_deg)
	_steer_filtered = lerpf(_steer_filtered, steer_rad, 1.0 - exp(-steer_filter_k * delta))
	var throttle := clampf(_read_throttle(), 0.0, 1.0)
	var brake := clampf(_read_brake(), 0.0, 1.0)

	# --- Steering lean: roll + lateral offset, smoothed (never raw — ACC
	# --- steer-assist lesson). Positive steer = left turn (body forward -Z):
	# --- the view leans, shifts and looks INTO the corner. speed_frac keeps
	# --- everything ~0 at rest / exactly zero at standstill.
	var roll := clampf(_steer_filtered * steer_lean_strength * speed_frac, -STEER_ROLL_CAP, STEER_ROLL_CAP)
	var lateral_shift := -clampf(
		_steer_filtered * steer_lean_strength * speed_frac, -STEER_LATERAL_CAP, STEER_LATERAL_CAP
	)

	# --- Brake dive / accel squat: nose pitches toward the road, capped ~2 deg.
	var pitch := clampf((brake - throttle) * pitch_strength * speed_frac, -PITCH_CAP, PITCH_CAP)

	# --- Look-into-turn: yaw hint toward lateral velocity (steer angle x speed
	# --- lateral-velocity proxy), smoothed via _steer_filtered, capped ~4 deg.
	var yaw := clampf(_steer_filtered * speed_frac * look_turn_strength, -LOOK_YAW_CAP, LOOK_YAW_CAP)

	# --- Speed micro-shake: bounded noise, off at standstill. Amplitude is
	# --- magnitude-capped so the total offset stays under its bound.
	_shake_phase += delta * shake_frequency
	var shake_amp := shake_strength * SHAKE_AMP_MAX * speed_frac
	var shake_vec := Vector3(
		sin(_shake_phase),
		sin(_shake_phase * 1.37) * 0.6,
		sin(_shake_phase * 0.89) * 0.35
	)
	if shake_amp > 0.0 and shake_vec.length() > 0.001:
		shake_vec = shake_vec.normalized() * shake_amp
	else:
		shake_vec = Vector3.ZERO

	# --- Compose onto a COPY of the body transform (no feedback loops). The
	# --- seat anchor is global; offsets ride the body basis so they rotate
	# --- with the car.
	var body_basis := target.global_basis
	var position_offset := body_basis.x * lateral_shift
	var shake_global := body_basis.x * shake_vec.x + body_basis.y * shake_vec.y + body_basis.z * shake_vec.z
	_last_pos_offset = position_offset + shake_global

	global_position = get_seat_anchor() + _last_pos_offset
	global_basis = _compose_feel_basis(body_basis, roll, pitch, yaw)

	_last_roll = roll
	_last_pitch = pitch
	_last_yaw = yaw

	var target_fov := lerpf(fov_min, fov_max, speed_frac * fov_strength)
	_camera.fov = lerpf(_camera.fov, target_fov, 1.0 - exp(-fov_k * delta))

# --- Yaw then roll then pitch, applied in the body's local frame. Each
# --- .rotated() post-multiplies a pure rotation, so small-angle composition
# --- stays clean and never touches the anchor position.
func _compose_feel_basis(body_basis: Basis, roll: float, pitch: float, yaw: float) -> Basis:
	var feel := body_basis
	feel = feel.rotated(Vector3.UP, yaw)      # look-into-turn (toward apex)
	feel = feel.rotated(Vector3.BACK, roll)   # lean into the corner
	feel = feel.rotated(Vector3.RIGHT, -pitch)  # brake dive (nose down)
	return feel

func _read_speed_kmh() -> float:
	if debug_speed_kmh >= 0.0:
		return debug_speed_kmh
	var car := target as VehiclePhysics
	return car.get_speed_kmh() if car else 0.0

func _read_steer_deg() -> float:
	if debug_speed_kmh >= 0.0:
		return debug_steer_deg
	var car := target as VehiclePhysics
	return car.get_steer_angle() if car else 0.0

func _read_throttle() -> float:
	if debug_speed_kmh >= 0.0:
		return debug_throttle
	var car := target as VehiclePhysics
	return car.get_throttle() if car else 0.0

func _read_brake() -> float:
	if debug_speed_kmh >= 0.0:
		return debug_brake
	var car := target as VehiclePhysics
	var info: Dictionary = car.get_drive_info() if car else {}
	return float(info.get("brake", 0.0))