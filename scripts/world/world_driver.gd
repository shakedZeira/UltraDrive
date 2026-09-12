# scripts/world/world_driver.gd
class_name WorldDriver
extends Node3D

## Feeds the player car's global position into the ChunkStreamer every physics
## tick so terrain chunks stream in/out around the driver. Also pushes once on
## ready so the first frame already has ground under the car.

var _streamer: ChunkStreamer
var _player: Node3D

func _ready() -> void:
	_streamer = get_node_or_null("ChunkStreamer") as ChunkStreamer
	_player = get_node_or_null("%PlayerCar") as Node3D
	_push_player_position()

func _physics_process(_delta: float) -> void:
	if _player == null:
		_player = get_node_or_null("%PlayerCar") as Node3D
	if _streamer == null or _player == null:
		return
	_push_player_position()

func _push_player_position() -> void:
	if _streamer == null or _player == null:
		return
	_streamer.set_player_position(_player.global_position)