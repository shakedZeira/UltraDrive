class_name CockpitRig
extends Node3D

## Procedural cockpit interior (F2a): a generic, cheap dash + A-pillars +
## windshield header + steering-wheel proxy built from primitives, sized to
## the F1 cockpit eye anchor (seat_height 0.42 / seat_forward 0.55). The rig's
## origin sits AT the driver eye (scene transform (0, 0.42, -0.55) in car
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

func _ready() -> void:
	visible = false  # hidden until a cockpit camera proves current
	sync_visibility()

func _process(_delta: float) -> void:
	sync_visibility()

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