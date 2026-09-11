class_name Checkpoint
extends Area3D

## A checkpoint zone that vehicles must pass through.
## Set index to order checkpoints around the track.
## Set next_checkpoints array to allow multiple valid next checkpoints (for branching tracks).

@export var index: int = 0
@export var is_start_line: bool = false

var active: bool = false

func _ready() -> void:
    body_entered.connect(_on_body_entered)
    add_to_group("checkpoints")
    collision_layer = 0
    collision_mask = 16  # layer 5 (Checkpoints)

func _on_body_entered(body: Node3D) -> void:
    if active and body is VehiclePhysics:
        active = false

func is_passed(vehicle: VehiclePhysics) -> bool:
    ## Returns true if this checkpoint detects the given vehicle passing.
    ## Called by RaceManager. Returns true once per passing (then resets active).
    if active and !(vehicle in get_overlapping_bodies()):
        return false
    return not active and (vehicle in get_overlapping_bodies())

func reset() -> void:
    active = true
