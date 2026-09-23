extends Node3D

## Hood camera: third camera mode in the chase / orbit / hood C-cycle (S14).
## The view is bolted rigidly to the front hood of the car (NO lerp-smooth
## follow like chase_camera.gd) so it inherits every pitch/roll/heading from the
## body, with a light speed-based head bob layered on top. FOV bumps from
## fov_min to fov_max with speed exactly like chase. Inactive by default so the
## chase camera stays current; the C-cycle in orbit_camera.gd flips it on via
## set_view_active().
## Attach as child of VehiclePhysics or set target in inspector.

@export var target: Node3D
@export var hood_height: float = 0.65
@export var hood_forward: float = 1.5
@export var fov_min: float = 70.0
@export var fov_max: float = 75.0
@export var fov_speed_factor: float = 0.05
## F5 speed-FOV knob (0..1): 0 pins the hood camera to fov_min, 1.0 is the full
## shipped widening. Defaulting to 1.0 keeps today's feel until a player opts.
@export var fov_strength: float = 1.0
@export var full_speed_kmh: float = 200.0
@export var bob_amplitude_max: float = 0.025
@export var bob_frequency: float = 12.0
## F5 head-bob knob (0..1): scales the speed head-bob amplitude. Shipped
## default is the full 0.025m amplitude; the XAG-117 defaults keep the *nausea
## knob* below 0.5, this is the visual accompaniment that never ships at 1.0
## unless the player opts in.
@export var bob_strength: float = 1.0
## Player look-around (right stick, same camera_orbit_* actions as orbit):
## yaw is free 360, pitch is clamped so the view can't cut through the floor
## or the roof line. The look piggybacks ON TOP of the body basis and never
## moves the rigid hood anchor.
@export var look_speed_yaw: float = 2.6
@export var look_speed_pitch: float = 1.6
@export var input_deadzone: float = 0.15
@export var pitch_min: float = -0.5
@export var pitch_max: float = 1.35

# --- Test/debug hooks (-1 speed means "use the real VehiclePhysics path"). ---
@export var debug_speed_kmh: float = -1.0

var _camera: Camera3D
var _bob_offset: Vector3 = Vector3.ZERO
var _bob_phase: float = 0.0
# Persistent player look state (radians); resets to forward on activation.
var _look_yaw: float = 0.0
var _look_pitch: float = 0.0

func _ready() -> void:
	_camera = Camera3D.new()
	_camera.fov = fov_min
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
	if is_current_view():
		# First-person look-around on the same right-stick actions as ORBIT:
		# while the hood cam owns the viewport the stick sweeps the view around
		# INSIDE the first-person view instead of grabbing the orbit camera.
		var axis_x := Input.get_axis("camera_orbit_left", "camera_orbit_right")
		var axis_y := Input.get_axis("camera_orbit_up", "camera_orbit_down")
		# camera_orbit_* use swapped joypad bindings (right/up push fires the
		# *_left/*_up action), so negate to make stick direction == view direction.
		apply_look(-axis_x, -axis_y, delta)
	_update_camera(delta)

# --- Forward-view gate (S12/S14). Mirrors chase_camera.gd; the hood cam also
# --- owns the viewport so windshield droplets carry into first-person hood mode.
func is_current_view() -> bool:
	return _camera != null and _camera.is_current()

# --- Mode ownership (S14). The C-cycle in orbit_camera.gd calls this to hand
# --- the viewport to the hood camera and to release it when cycling away.
# --- Entering the view resets the look to forward so first-person never
# --- resumes facing backwards.
func set_view_active(active: bool) -> void:
	if _camera == null:
		return
	if active:
		_look_yaw = 0.0
		_look_pitch = 0.0
	_camera.current = active

# --- Readable test hooks ---

func get_hood_fov() -> float:
	return _camera.fov if _camera != null else fov_min

func get_bob_offset() -> Vector3:
	return _bob_offset

func get_hood_anchor() -> Vector3:
	if target == null:
		return global_position
	var forward := hood_forward
	var height := hood_height
	var cfg := _car_config()
	if cfg != null:
		if cfg.hood_cam_forward > 0.0:
			forward = cfg.hood_cam_forward
		if cfg.hood_cam_height > 0.0:
			height = cfg.hood_cam_height
	return target.global_position - target.global_basis.z * forward \
		+ Vector3.UP * height

# --- Per-frame update. Extracted so tests can drive frames deterministically
# --- without the physics loop; null-target guard still applies. Rigid: no
# --- lerp, so the transform lands on the hood anchor (plus head bob) each frame.
func _update_camera(delta: float) -> void:
	if target == null:
		return

	var speed_kmh := _read_speed_kmh()
	_bob_phase += delta * bob_frequency
	_bob_offset = _compute_bob(speed_kmh)

	global_position = get_hood_anchor() + _bob_offset

	# Rigid body mirror (heading/pitch/roll) then the player look on top: yaw
	# about the body's UP (free 360), pitch about its RIGHT (clamped). Positive
	# look pitch = look up, opposite sign to the .rotated() axis so stick-up
	# reads the same as the orbit camera.
	var look_basis := target.global_basis
	look_basis = look_basis.rotated(Vector3.UP, _look_yaw)
	look_basis = look_basis.rotated(Vector3.RIGHT, -_look_pitch)
	global_basis = look_basis

	var target_fov := lerpf(fov_min, fov_max, clampf(speed_kmh / full_speed_kmh, 0.0, 1.0) * fov_strength)
	_camera.fov = lerpf(_camera.fov, target_fov, fov_speed_factor)

## Player look-around seam, driven by the camera_orbit_* right-stick actions
## (in _physics_process, only while this camera owns the viewport) and called
## directly by tests. Each axis below input_deadzone is ignored; pitch clamps
## to pitch_min/pitch_max so the view can't cut through the floor or roof.
func apply_look(axis_x: float, axis_y: float, delta: float) -> void:
	var dx := axis_x if absf(axis_x) > input_deadzone else 0.0
	var dy := axis_y if absf(axis_y) > input_deadzone else 0.0
	_look_yaw -= dx * look_speed_yaw * delta
	_look_pitch += dy * look_speed_pitch * delta
	_look_pitch = clampf(_look_pitch, pitch_min, pitch_max)

# --- Readable look test hooks ---

func get_look_yaw() -> float:
	return _look_yaw

func get_look_pitch() -> float:
	return _look_pitch

## F5 camera-and-feel apply: syncs the speed-FOV and head-bob knobs from the
## persisted settings onto this camera, falling back to current exports when a
## key is missing. Snaps back to fov_min so the applied value reads back
## deterministically.
func sync_camera_settings(settings: Dictionary) -> void:
	fov_strength = clampf(float(settings.get("camera_fov_hood", fov_strength)), 0.0, 1.0)
	bob_strength = clampf(float(settings.get("hood_bob", bob_strength)), 0.0, 1.0)
	if _camera != null:
		_camera.fov = fov_min

func _read_speed_kmh() -> float:
	if debug_speed_kmh >= 0.0:
		return debug_speed_kmh
	var car := target as VehiclePhysics
	return car.get_speed_kmh() if car else 0.0

## Resolves the target's CarConfig (per-car hood-anchor overrides); null for
## plain Node3D test targets = fall back to the actor's exports.
func _car_config() -> CarConfig:
	var car := target as VehiclePhysics
	if car == null:
		return null
	return car.config

func _compute_bob(speed_kmh: float) -> Vector3:
	var amplitude := bob_amplitude_max * bob_strength * clampf(speed_kmh / full_speed_kmh, 0.0, 1.0)
	return Vector3(
		sin(_bob_phase) * amplitude,
		cos(_bob_phase * 1.37) * amplitude * 0.5,
		0.0
	)