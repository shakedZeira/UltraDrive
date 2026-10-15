class_name CockpitRig
extends Node3D

## Procedural cockpit interior (F2a): a generic, cheap dash + A-pillars +
## windshield header + steering-wheel proxy built from primitives, sized to
## the F1 cockpit eye anchor (seat_height 0.55 / seat_forward 0.55). The rig's
## origin sits AT the driver eye (scene transform (0, 0.55, -0.55) in car
## space), so the cockpit camera nests exactly inside it. The interior is a
## single flat-shaded dark-grey material with a very mild self-emission
## (emission_energy_multiplier ~0.15) so it stays readable at night — chosen
## over a cabin OmniLight because it costs no dynamic light pass.
##
## Placement: SIBLING of CarBody in player_car.tscn (a direct child of the
## VehiclePhysics root), NOT a CarBody child — PlayerCarController._apply_visual()
## clears the body's children and re-adds the GLB on every car swap, so a rig
## inside CarBody would be wiped. As a sibling it is stable across swaps.
##
## Visibility gate (deliberately SEPARATE from world_driver._is_forward_view):
## droplets show in chase/hood/cockpit, but the interior geometry must be
## visible ONLY while the CockpitCamera owns the viewport (chase/hood/orbit
## cameras sit outside the shell and would see the boxes poking through).
## sync_visibility() polls the cockpit camera's is_current_view() — the same
## probe WorldDriver uses — found either via the cockpit_camera_path export or
## by walking up the ancestor chain for a node named "CockpitCamera" (all the
## player scenes wire it as a sibling of PlayerCar). Falls back to HIDDEN when
## no cockpit camera exists (test_vehicle_physics.tscn has none) and when a
## candidate exists but cannot report its view. Fully headless-safe: no render
## signals, no MainLoop dependency; tests drive sync_visibility() directly
## (mirroring _update_camera / cycle_mode_for_test style).

## Optional explicit pin to the cockpit camera. Empty by default: the rig
## auto-locates the node named "CockpitCamera" above the car.
@export var cockpit_camera_path: NodePath

## Cabin steering-wheel lock (rad) for the NORMALIZED -1..1 steer from
## get_drive_info(). Deliberately NOT CarVisuals.STEER_VISUAL_MAX_RAD (0.35),
## which is the road wheels' lock — the cabin wheel turns far more.
const STEER_VISUAL_MAX_RAD_CABIN := 2.2

var _wheel_node: Node3D
var _wheel_base_basis := Basis.IDENTITY
var _authored_wheel_transform := Transform3D.IDENTITY

var _rpm_needle: Node3D
var _speed_needle: Node3D
var _shift_material: StandardMaterial3D
var _shift_on := false
var _mfd_material: StandardMaterial3D

## Binnacle needle sweep, about each pod's LOCAL X: idle / face-zero maps to
## -GAUGE_SWEEP_HALF_RAD, redline / face-max to +GAUGE_SWEEP_HALF_RAD. The exact
## pure formula is  angle = -0.75 + 1.5 * clampf((value - lo) / (hi - lo), 0, 1)
## (lo/hi = idle/redline rpm for the tach, 0/face-max km-h for the speedo).
const GAUGE_SWEEP_HALF_RAD := 0.75
const GAUGE_SWEEP_RAD := 1.5
## Speedometer face maximum (km/h) the needle normalises against.
const SPEED_FACE_MAX_KMH := 320.0
## Shift-light strip turns red above this fraction of redline.
const SHIFT_LIGHT_RPM_FRACTION := 0.9
const SHIFT_LIGHT_BASE_COLOR := Color(0.35, 0.06, 0.04, 1.0)
const SHIFT_LIGHT_ON_COLOR := Color(1.0, 0.16, 0.08, 1.0)
const SHIFT_LIGHT_BASE_ENERGY := 0.15
const SHIFT_LIGHT_ON_ENERGY := 1.4
const GAUGE_DEFAULT_IDLE_RPM := 800.0
const GAUGE_DEFAULT_REDLINE_RPM := 7500.0

## MFD page colours (P4). Index 0 is the AUTHORED scene colour so mode 0 is a
## true reset; set_mfd_mode() swaps ONLY this emissive colour — no texture, no
## flipbook, no SubViewport — which is the whole reason the MFD is a colour
## swap and not a screen buffer.
const MFD_MODE_COLORS: Array[Color] = [
	Color(0.22, 0.5, 0.85, 1.0),
	Color(0.9, 0.48, 0.14, 1.0),
	Color(0.55, 0.3, 0.88, 1.0),
]

func _ready() -> void:
	visible = false  # hidden until a cockpit camera proves current
	_authored_wheel_transform = _default_wheel_transform()
	_load_interior()
	_sync_to_seat_anchor()
	_capture_steering_wheel()
	_capture_gauges()
	_capture_mfd()
	sync_visibility()
	sync_shell_view()

func _process(_delta: float) -> void:
	_sync_to_seat_anchor()
	_sync_steer_visual()
	_sync_gauges()
	sync_visibility()
	sync_shell_view()

## Reads the parent VehiclePhysics drive_info readout each frame and spins the
## cabin wheel to match. Degrades silently (wheel stays put) when the parent is
## not a VehiclePhysics or reports no steer.
func _sync_steer_visual() -> void:
	var car := get_parent()
	if car == null or not car.has_method("get_drive_info"):
		return
	var info: Variant = car.call("get_drive_info")
	if info is Dictionary:
		set_steer_visual(float((info as Dictionary).get("steer", 0.0)))

## Polls the same get_drive_info() feed each frame and updates the binnacle
## needles + shift-light strip. Degrades silently when the parent is not a
## VehiclePhysics or the active interior ships no gauge anchors.
func _sync_gauges() -> void:
	if _rpm_needle == null and _speed_needle == null and _shift_material == null:
		return
	var car := get_parent()
	if car == null or not car.has_method("get_drive_info"):
		return
	var info: Variant = car.call("get_drive_info")
	if info is Dictionary:
		apply_gauge_drive_info(info as Dictionary)

## Test-facing tick mirroring sync_visibility(): derives the cabin wheel spin AND
## the binnacle gauge state from a drive_info dictionary so suites can drive both
## without a physics loop.
func apply_drive_info(info: Dictionary) -> void:
	set_steer_visual(float(info.get("steer", 0.0)))
	apply_gauge_drive_info(info)

## Drives the needles + shift light from a drive_info dictionary using the
## active car's CarConfig idle/redline (falls back to sane defaults). Pure,
## deterministic, allocation-free.
func apply_gauge_drive_info(info: Dictionary) -> void:
	var cfg := _config()
	var idle := cfg.idle_rpm if cfg != null else GAUGE_DEFAULT_IDLE_RPM
	var redline := cfg.redline_rpm if cfg != null else GAUGE_DEFAULT_REDLINE_RPM
	set_gauge_values(
		float(info.get("speed_kmh", 0.0)),
		float(info.get("rpm", 0.0)),
		idle,
		redline
	)

## Pure gauge update: needle angles from the clamped formula and the shift-light
## state from rpm/redline. No dynamics; fully deterministic.
func set_gauge_values(speed_kmh: float, rpm: float, idle_rpm: float, redline_rpm: float) -> void:
	if _rpm_needle != null:
		_rpm_needle.rotation.x = gauge_rpm_angle(rpm, idle_rpm, redline_rpm)
	if _speed_needle != null:
		_speed_needle.rotation.x = gauge_speed_angle(speed_kmh, SPEED_FACE_MAX_KMH)
	_update_shift_light(rpm, redline_rpm)

## Tach needle angle (rad) about the pod's local X: -0.75 at idle, +0.75 at
## redline, clamped outside.
static func gauge_rpm_angle(rpm: float, idle_rpm: float, redline_rpm: float) -> float:
	return _sweep_angle(rpm, idle_rpm, redline_rpm)

## Speedo needle angle (rad): -0.75 at 0 km/h, +0.75 at face_max, clamped.
static func gauge_speed_angle(speed_kmh: float, face_max_kmh: float) -> float:
	return _sweep_angle(speed_kmh, 0.0, face_max_kmh)

## The single clamped sweep: -GAUGE_SWEEP_HALF_RAD .. +GAUGE_SWEEP_HALF_RAD.
static func _sweep_angle(value: float, lo: float, hi: float) -> float:
	var span := hi - lo
	if is_zero_approx(span):
		return -GAUGE_SWEEP_HALF_RAD
	return -GAUGE_SWEEP_HALF_RAD + GAUGE_SWEEP_RAD * clampf((value - lo) / span, 0.0, 1.0)

## Flips the cached shift-light material toward red once, only on a state change
## (no allocation per frame; base energy stays the F2a 0.15 discipline).
func _update_shift_light(rpm: float, redline_rpm: float) -> void:
	if _shift_material == null:
		return
	var on := redline_rpm > 0.0 and rpm > SHIFT_LIGHT_RPM_FRACTION * redline_rpm
	if on == _shift_on:
		return
	_shift_on = on
	_shift_material.emission = SHIFT_LIGHT_ON_COLOR if on else SHIFT_LIGHT_BASE_COLOR
	_shift_material.emission_energy_multiplier = (
		SHIFT_LIGHT_ON_ENERGY if on else SHIFT_LIGHT_BASE_ENERGY
	)

## Spins the SteeringWheel around its LOCAL Y (the torus axle) by the normalized
## steer times the cabin lock. Right-multiplying by a Y-rotation preserves the
## wheel's physical tilt. Pure Basis math — headless-safe.
func set_steer_visual(steer: float) -> void:
	if _wheel_node == null:
		return
	_wheel_node.basis = _wheel_base_basis * Basis(
		Vector3(0.0, 1.0, 0.0),
		clampf(steer, -1.0, 1.0) * STEER_VISUAL_MAX_RAD_CABIN
	)

func _capture_steering_wheel() -> void:
	var wheel := _find_anchor("SteeringWheel") as Node3D
	if wheel == null:
		return
	_wheel_node = wheel
	_wheel_base_basis = wheel.basis

## Caches the binnacle needle pivots and an ISOLATED copy of the shift-light
## mesh/material so per-frame updates never mutate the shared scene sub-resource
## (and allocate nothing after capture). No-op when the interior has no gauges.
func _capture_gauges() -> void:
	_rpm_needle = null
	_speed_needle = null
	_shift_material = null
	_shift_on = false
	var rpm_pod := _find_anchor("GaugeRPM") as Node3D
	if rpm_pod != null:
		_rpm_needle = rpm_pod.find_child("Needle", true, false) as Node3D
	var speed_pod := _find_anchor("GaugeSpeed") as Node3D
	if speed_pod != null:
		_speed_needle = speed_pod.find_child("Needle", true, false) as Node3D
	var strip := _find_anchor("ShiftLightStrip") as MeshInstance3D
	if strip == null:
		return
	var base_mesh := strip.mesh as PrimitiveMesh
	if base_mesh == null:
		return
	var base_mat := base_mesh.material as StandardMaterial3D
	if base_mat == null:
		return
	var mat := base_mat.duplicate() as StandardMaterial3D
	var mesh := base_mesh.duplicate() as PrimitiveMesh
	mesh.material = mat
	strip.mesh = mesh
	_shift_material = mat

## Caches an ISOLATED copy of the MFD screen's quad + material so set_mfd_mode()
## never mutates the shared scene sub-resource (same isolation seam as the shift
## light). No-op when the active interior ships no MFDScreen anchor.
func _capture_mfd() -> void:
	_mfd_material = null
	var screen := _find_anchor("MFDScreen") as MeshInstance3D
	if screen == null:
		return
	var base_mesh := screen.mesh as PrimitiveMesh
	if base_mesh == null:
		return
	var base_mat := base_mesh.material as StandardMaterial3D
	if base_mat == null:
		return
	var mat := base_mat.duplicate() as StandardMaterial3D
	var mesh := base_mesh.duplicate() as PrimitiveMesh
	mesh.material = mat
	screen.mesh = mesh
	_mfd_material = mat

## P4 static mode hook: swaps the MFD's emissive colour to MFD_MODE_COLORS[mode]
## (clamped), touching nothing else — nav screen, shift light and gauges keep
## their own emission. Mode 0 restores the authored colour exactly. Silent no-op
## when no MFD has been captured (default rig / interior-less car).
func set_mfd_mode(mode: int) -> void:
	if _mfd_material == null:
		return
	_mfd_material.emission = MFD_MODE_COLORS[clampi(mode, 0, MFD_MODE_COLORS.size() - 1)]

## The isolated MFD material (test seam — read emission state from this), or
## null when the active interior ships no MFDScreen.
func get_mfd_material() -> StandardMaterial3D:
	return _mfd_material

## Loads the parent CarConfig's optional InteriorResource scene override.
## res == null keeps the literal cockpit_rig.tscn tree untouched (byte-
## identical for every car without an interior). A valid interior_scene is
## added as a child named "Interior" and the F2a default geometry is removed;
## a missing SteeringWheel is covered by a spawned default wheel. Any failure
## (missing/empty scene) falls back to the literal tree with zero error spew.
func _load_interior() -> void:
	var cfg := _config()
	if cfg == null or cfg.interior == null:
		return
	var scene: PackedScene = cfg.interior.interior_scene
	if scene == null or not scene.can_instantiate():
		return
	var instance := scene.instantiate()
	if instance == null:
		return
	_clear_interior()
	instance.name = "Interior"
	add_child(instance)
	_remove_default_geometry()
	if _find_anchor("SteeringWheel") == null:
		_spawn_default_wheel()

## Test / car-reconfig seam: re-runs the interior loader, freeing the previous
## Interior subtree first (orphan hygiene).
func rebuild_interior() -> void:
	_load_interior()
	_capture_steering_wheel()
	_capture_gauges()
	_capture_mfd()

## Returns the parent's CarConfig when the parent exposes one, else null.
func _config() -> CarConfig:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get("config") as CarConfig

## Frees a previously-loaded Interior subtree so a rebuild never leaks it.
func _clear_interior() -> void:
	var old := get_node_or_null("Interior")
	if old == null:
		return
	remove_child(old)
	old.queue_free()

## Removes the literal F2a primitives (only called when an override loaded) so
## the authored cabin is the sole interior. Direct children only.
func _remove_default_geometry() -> void:
	var parts: Array[String] = ["Dashboard", "PillarLeft", "PillarRight", "HeaderBar", "SteeringWheel"]
	for part: String in parts:
		var node := get_node_or_null(part)
		if node == null:
			continue
		remove_child(node)
		node.queue_free()

## Resolves a named anchor anywhere under the rig root, preferring one inside
## the loaded Interior subtree over a direct child.
func _find_anchor(anchor_name: String) -> Node:
	var interior := get_node_or_null("Interior")
	if interior != null:
		var nested := interior.find_child(anchor_name, true, false)
		if nested != null:
			return nested
	return get_node_or_null(anchor_name)

## Default wheel fallback when a custom interior ships no SteeringWheel: a
## torus at the captured F2a authored transform, axle along local Y so the spin
## seam still right-multiplies a Y rotation.
func _spawn_default_wheel() -> void:
	var wheel := MeshInstance3D.new()
	wheel.name = "SteeringWheel"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.11
	torus.outer_radius = 0.16
	torus.rings = 12
	torus.ring_segments = 24
	wheel.mesh = torus
	wheel.transform = _authored_wheel_transform
	wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wheel)

## The authored SteeringWheel transform from the literal cockpit_rig.tscn, kept
## for the fallback wheel even after the authored node is removed.
func _default_wheel_transform() -> Transform3D:
	var wheel := get_node_or_null("SteeringWheel") as Node3D
	return wheel.transform if wheel != null else Transform3D.IDENTITY

## The captured SteeringWheel anchor (the spin seam target), or null.
func get_steering_wheel() -> Node3D:
	return _wheel_node

## The captured GaugeRPM needle pivot (test seam), or null.
func get_rpm_needle() -> Node3D:
	return _rpm_needle

## The captured GaugeSpeed needle pivot (test seam), or null.
func get_speed_needle() -> Node3D:
	return _speed_needle

## Whether the shift-light strip is in its red "shift now" state.
func get_shift_light_on() -> bool:
	return _shift_on

## The isolated shift-light material (test seam — read emission state from this).
func get_shift_material() -> StandardMaterial3D:
	return _shift_material

## Single source of truth for the seat anchor (Sec 4.4): the cockpit CAMERA and
## this rig both read (height, forward, lateral) from here so an RHD car can
## never drift out of agreement between eye and interior. Defaults reproduce the
## F2a 0.55/0.55 anchor; height/forward only apply when > 0.0 and lateral when
## != 0.0 (it is legitimately negative for RHD), so a config carrying no
## overrides yields exactly today's math with lateral 0. Returned as
## Vector3(height, forward, lateral).
static func seat_anchor_for(cfg: CarConfig, default_height: float, default_forward: float) -> Vector3:
	var height := default_height
	var forward := default_forward
	var lateral := 0.0
	if cfg != null:
		if cfg.cockpit_seat_height > 0.0:
			height = cfg.cockpit_seat_height
		if cfg.cockpit_seat_forward > 0.0:
			forward = cfg.cockpit_seat_forward
		if cfg.cockpit_seat_lateral != 0.0:
			lateral = cfg.cockpit_seat_lateral
	return Vector3(height, forward, lateral)

## Keeps the interior glued to the drive eye when the car's CarConfig raises or
## moves the cockpit seat (per-car cockpit_seat_height / _forward / _lateral
## overrides — the RHD eye sits right of centre, hence a negative lateral).
## Falls back to the authored 0.55/0.55 anchor with no lateral when the parent
## is not a VehiclePhysics or its config carries no override, so the rig scene
## stays byte-identical for every other car.
func _sync_to_seat_anchor() -> void:
	var car := get_parent() as VehiclePhysics
	var cfg: CarConfig = car.config if car != null and car.config != null else null
	var seat := seat_anchor_for(cfg, 0.55, 0.55)
	position.x = seat.z
	position.y = seat.x
	position.z = -seat.y

## Polls cockpit-camera ownership and mirrors it onto this node's visibility.
## Returns the resulting state so tests can assert it directly without waiting
## for the main loop.
func sync_visibility() -> bool:
	var cam := _find_cockpit_camera()
	var active := false
	if cam != null and cam.has_method("is_current_view"):
		active = bool(cam.call("is_current_view"))
	visible = active
	return active

## Resolves the cockpit camera: explicit path first, then a cheap ancestor walk
## looking for a node named "CockpitCamera" (the wired player scenes all put it
## as a sibling of PlayerCar). Re-looked-up every call — no stale cached refs
## across scene swaps, cost is a few get_node_or_null calls.
func _find_cockpit_camera() -> Node:
	if not cockpit_camera_path.is_empty():
		var via_path := get_node_or_null(cockpit_camera_path)
		if via_path != null:
			return via_path
	var node := get_parent()
	while node != null:
		var cam := node.get_node_or_null("CockpitCamera")
		if cam != null:
			return cam
		node = node.get_parent()
	return null

## Drives the car shell/glass see-through state off the SAME cockpit-ownership
## probe as sync_visibility(): while the cockpit camera owns the viewport the
## exterior shell meshes are hidden and the glass turns transparent
## (CarVisuals.set_cockpit_view), so the driver can actually SEE OUT — critical
## for cars like the Comet whose red body shell IS the windshield (no glass
## mesh). Every flag is restored when the cockpit camera loses the viewport, so
## chase / hood / orbit render unchanged. No-op when no CarBody visual exists.
func sync_shell_view() -> void:
	var cam := _find_cockpit_camera()
	var active := false
	if cam != null and cam.has_method("is_current_view"):
		active = bool(cam.call("is_current_view"))
	_apply_shell_view(active)

## Walks CarBody for its live GLB visual root (the newest non-rig, non-probe,
## non-queued Node3D child, stable across _apply_visual swaps) and applies the
## cockpit see-through state to it.
func _apply_shell_view(active: bool) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var body := parent.get_node_or_null("CarBody") as Node3D
	if body == null:
		return
	for child: Node in body.get_children():
		if child is BodyRig or child is ReflectionProbe:
			continue
		if not (child is Node3D) or child.is_queued_for_deletion():
			continue
		CarVisuals.set_cockpit_view(child as Node3D, active)