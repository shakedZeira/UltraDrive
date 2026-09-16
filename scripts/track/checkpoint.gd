class_name Checkpoint
extends Area3D

## A checkpoint zone that vehicles must pass through.
## Set index to order checkpoints around the track.
## Set next_checkpoints array to allow multiple valid next checkpoints (for branching tracks).

@export var index: int = 0
@export var is_start_line: bool = false

var active: bool = false
var _counted: Dictionary = {}

func _ready() -> void:
	add_to_group("checkpoints")
	collision_layer = 0
	collision_mask = 1 | 16  # layer 1 (default bodies) + layer 5

func is_passed(vehicle: VehiclePhysics) -> bool:
	## Returns true once per pass while armed (after reset()).
	## Each vehicle is counted at most once per armed cycle.
	if not active:
		return false
	if not (vehicle in _overlapping_bodies()):
		return false
	if _counted.has(vehicle):
		return false
	_counted[vehicle] = true
	return true

func _overlapping_bodies() -> Array:
	return get_overlapping_bodies()

func reset() -> void:
	active = true
	_counted.clear()