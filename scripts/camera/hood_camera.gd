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

# --- Test/debug hooks (-1 speed means "use the real VehiclePhysics path"). ---
@export var debug_speed_kmh: float = -1.0

var _camera: Camera3D
var _bob_offset: Vector3 = Vector3.ZERO
var _bob_phase: float = 0.0

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
	_update_camera(delta)

# --- Forward-view gate (S12/S14). Mirrors chase_camera.gd; the hood cam also
# --- owns the viewport so windshield droplets carry into first-person hood mode.
func is_current_view() -> bool:
	return _camera != null and _camera.is_current()

# --- Mode ownership (S14). The C-cycle in orbit_camera.gd calls this to hand
# --- the viewport to the hood camera and to release it when cycling away.
func set_view_active(active: bool) -> void:
	if _camera == null:
		return
	_camera.current = active

# --- Readable test hooks ---

func get_hood_fov() -> float:
	return _camera.fov if _camera != null else fov_min

func get_bob_offset() -> Vector3:
	return _bob_offset

func get_hood_anchor() -> Vector3:
	if target == null:
		return global_position
	return target.global_position - target.global_basis.z * hood_forward \
		+ Vector3.UP * hood_height

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
	global_basis = target.global_basis  # mirror the body: heading, pitch and roll

	var target_fov := lerpf(fov_min, fov_max, clampf(speed_kmh / full_speed_kmh, 0.0, 1.0) * fov_strength)
	_camera.fov = lerpf(_camera.fov, target_fov, fov_speed_factor)

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

func _compute_bob(speed_kmh: float) -> Vector3:
	var amplitude := bob_amplitude_max * bob_strength * clampf(speed_kmh / full_speed_kmh, 0.0, 1.0)
	return Vector3(
		sin(_bob_phase) * amplitude,
		cos(_bob_phase * 1.37) * amplitude * 0.5,
		0.0
	)