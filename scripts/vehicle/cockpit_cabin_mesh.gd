# scripts/vehicle/cockpit_cabin_mesh.gd
extends Node3D

## Static cabin dressing for an authored interior scene: hosts an imported GLB
## shell (dash, binnacle cowl, stack, console, doors, pillars, headliner, seats)
## and forces every mesh under it shadowless, keeping the interior contract the
## procedural primitives already follow (no shadow casting, no lights, emissive
## flat materials). The GLB itself carries no animated nodes — gauges, needles,
## screens and the steering wheel stay as the scene's own primitives so
## CockpitRig's anchor lookups and per-frame updates are unchanged.

func _ready() -> void:
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
