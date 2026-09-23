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

func _ready() -> void:
	visible = false  # hidden until a cockpit camera proves current
	_sync_to_seat_anchor()
	_capture_steering_wheel()
	sync_visibility()
	sync_shell_view()

func _process(_delta: float) -> void:
	_sync_to_seat_anchor()
	_sync_steer_visual()
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
		apply_drive_info(info as Dictionary)

## Test-facing tick mirroring sync_visibility(): derives the cabin wheel spin
## from a drive_info dictionary so suites can drive it without a physics loop.
func apply_drive_info(info: Dictionary) -> void:
	set_steer_visual(float(info.get("steer", 0.0)))

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
	var wheel := get_node_or_null("SteeringWheel") as Node3D
	if wheel == null:
		return
	_wheel_node = wheel
	_wheel_base_basis = wheel.basis

## Keeps the interior glued to the drive eye when the car's CarConfig raises or
## moves the cockpit seat (per-car cockpit_seat_height / cockpit_seat_forward
## overrides). Falls back to the authored 0.55/0.55 anchor when the parent is
## not a VehiclePhysics or its config carries no override, so the rig scene
## stays byte-identical for every other car.
func _sync_to_seat_anchor() -> void:
	var car := get_parent() as VehiclePhysics
	var cfg: CarConfig = car.config if car != null and car.config != null else null
	var seat_height := 0.55
	var seat_forward := 0.55
	if cfg != null:
		if cfg.cockpit_seat_height > 0.0:
			seat_height = cfg.cockpit_seat_height
		if cfg.cockpit_seat_forward > 0.0:
			seat_forward = cfg.cockpit_seat_forward
	position.y = seat_height
	position.z = -seat_forward

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