extends Node3D

## Free 360° orbit camera: the right stick sweeps the camera around the car
## in camera-local yaw/pitch (full circle, clamped pitch), FOV widens with speed
## exactly like chase_camera.gd. Inactive by default so the chase camera stays
## current; pushing the right stick grabs the view and it stays grabbed until
## "camera_mode" (C / view button) cycles onward.
##
## F1: the C-toggle is now a deterministic 4-mode cycle CHASE -> ORBIT -> HOOD
## -> COCKPIT -> CHASE. Each mode activates exactly one camera; right-stick
## still grabs orbit directly from any mode (today's behaviour). The hood and
## cockpit cameras are sibling nodes wired via hood_camera_path /
## cockpit_camera_path. On switch the newly-current camera gets a
## reset_physics_interpolation() so physics interpolation never leaves a
## 1-frame ghost.

enum CameraMode { CHASE = 0, ORBIT = 1, HOOD = 2, COCKPIT = 3 }

@export var target: Node3D
@export var orbit_distance: float = 6.0
@export var yaw: float = 0.0
@export var pitch: float = 0.2
@export var pitch_min: float = -0.5
@export var pitch_max: float = 1.35
@export var orbit_speed_yaw: float = 2.6
@export var orbit_speed_pitch: float = 1.6
@export var input_deadzone: float = 0.15
@export var keep_target_height: float = 1.0
@export var center_height: float = 0.6
@export var follow_speed: float = 8.0
@export var fov_min: float = 70.0
@export var fov_max: float = 90.0
@export var fov_speed_factor: float = 0.05
## F5 speed-FOV knob (0..1): 0 pins the orbit camera to fov_min, 1.0 is the
## full shipped widening. Defaulting to 1.0 keeps today's feel until a player
## opts for less.
@export var fov_strength: float = 1.0
@export var chase_camera_path: NodePath
@export var hood_camera_path: NodePath
@export var cockpit_camera_path: NodePath

var _camera: Camera3D
var _mode: int = CameraMode.CHASE


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

	if target != null:
		_preserve_orbit_angles()

	if not is_instance_valid(get_node_or_null(chase_camera_path)):
		_mode = CameraMode.ORBIT
		_camera.current = true  # standalone orbit (no chase sibling)


func _physics_process(delta: float) -> void:
	if target == null:
		return

	var axis_x := Input.get_axis("camera_orbit_left", "camera_orbit_right")
	var axis_y := Input.get_axis("camera_orbit_up", "camera_orbit_down")
	var stick_active := absf(axis_x) > input_deadzone or absf(axis_y) > input_deadzone

	if Input.is_action_just_pressed("camera_mode") and not stick_active:
		cycle_mode_for_test()
	elif stick_active and _mode != CameraMode.ORBIT:
		_mode = CameraMode.ORBIT
		_apply_mode()
		_preserve_orbit_angles()

	if _mode != CameraMode.ORBIT:
		return

	if stick_active:
		yaw -= axis_x * orbit_speed_yaw * delta
		pitch += axis_y * orbit_speed_pitch * delta
		pitch = clampf(pitch, pitch_min, pitch_max)

	_apply_orbit(delta)


# --- F1 4-mode cycle. Drives from the camera_mode input press above AND
# --- directly from tests: CHASE -> ORBIT -> HOOD -> COCKPIT -> CHASE. No real
# --- Input needed, so headless tests can drive it deterministically.
func cycle_mode_for_test() -> void:
	_mode = (_mode + 1) % 4
	_apply_mode()

## Activates exactly one camera for the current mode and retires the others.
## The newly-current camera also gets reset_physics_interpolation() so a mode
## swap never renders a 1-frame physics-interpolation ghost.
func _apply_mode() -> void:
	_camera.current = false
	var hood := get_node_or_null(hood_camera_path) as Node3D
	if hood != null and hood.has_method("set_view_active"):
		hood.call("set_view_active", false)
	var cockpit := get_node_or_null(cockpit_camera_path) as Node3D
	if cockpit != null and cockpit.has_method("set_view_active"):
		cockpit.call("set_view_active", false)
	var chase_cam := _chase_camera()
	if chase_cam != null:
		chase_cam.current = false

	if _mode == CameraMode.ORBIT:
		_camera.current = true
		_reset_physics_interpolation(_camera)
		return
	if _mode == CameraMode.HOOD and hood != null and hood.has_method("set_view_active"):
		hood.call("set_view_active", true)
		_reset_physics_interpolation(hood.get("_camera") as Node3D)
		return
	if _mode == CameraMode.COCKPIT and cockpit != null and cockpit.has_method("set_view_active"):
		cockpit.call("set_view_active", true)
		_reset_physics_interpolation(cockpit.get("_camera") as Node3D)
		return
	if chase_cam != null:
		chase_cam.current = true
		_reset_physics_interpolation(chase_cam)

## No-op-safe physics-interpolation reset: calls only when the camera actually
## exposes it, so the cycle still works on stripped test rigs.
func _reset_physics_interpolation(cam: Node3D) -> void:
	if cam != null and cam.has_method("reset_physics_interpolation"):
		cam.call("reset_physics_interpolation")


func _apply_orbit(delta: float) -> void:
	var center := _get_orbit_center()
	var dir := Vector3(cos(pitch) * cos(yaw), sin(pitch), cos(pitch) * sin(yaw))
	var orbit_pos := center - dir * orbit_distance
	global_position = global_position.lerp(orbit_pos, follow_speed * delta)

	var look_target := target.global_position + Vector3.UP * keep_target_height
	if (look_target - global_position).length() > 0.01:
		_camera.look_at(look_target)

	_camera.current = true

	var car := target as VehiclePhysics
	var speed_kmh := 0.0
	if car:
		speed_kmh = car.get_speed_kmh()

	var target_fov := lerpf(fov_min, fov_max, clampf(speed_kmh / 200.0, 0.0, 1.0) * fov_strength)
	_camera.fov = lerpf(_camera.fov, target_fov, fov_speed_factor)


## F5 camera-and-feel apply: syncs the speed-FOV knob from the persisted
## settings onto this camera, falling back to the current export when the key
## is missing. Snaps back to fov_min so the applied value reads back
## deterministically.
func sync_camera_settings(settings: Dictionary) -> void:
	fov_strength = clampf(float(settings.get("camera_fov_orbit", fov_strength)), 0.0, 1.0)
	if _camera != null:
		_camera.fov = fov_min


## Hand the viewport back to the chase camera (CHASE mode / hood missing).
func _deactivate_camera() -> void:
	var chase_cam := _chase_camera()
	if chase_cam != null:
		chase_cam.current = true


func _chase_camera() -> Camera3D:
	var chase := get_node_or_null(chase_camera_path) as Node3D
	if chase == null:
		return null
	for cam in chase.find_children("*", "Camera3D", false, false):
		if cam is Camera3D:
			return cam as Camera3D
	return null


func _preserve_orbit_angles() -> void:
	var center := _get_orbit_center()
	var d := center - global_position
	if d.length() < 0.01:
		return
	d = d.normalized()
	yaw = atan2(d.z, d.x)
	pitch = asin(clampf(d.y, -1.0, 1.0))


func _get_orbit_center() -> Vector3:
	return target.global_position + Vector3.UP * center_height