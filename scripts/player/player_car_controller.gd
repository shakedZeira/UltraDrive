extends Node

## Controls the player's car. Attach as child of VehiclePhysics.

@onready var car: VehiclePhysics = get_parent()

func _ready() -> void:
	VehicleManager.register_player_car(car)
