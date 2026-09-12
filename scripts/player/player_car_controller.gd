extends Node

## Controls the player's car. Attach as child of VehiclePhysics.

@onready var car: VehiclePhysics = get_parent()

func _ready() -> void:
	VehicleManager.register_player_car(car)
	var active := Garage.new_from_save().get_active_car()
	if active != "":
		var car_path := "res://resources/cars/%s.tres" % active
		if ResourceLoader.exists(car_path):
			car.config = load(car_path) as CarConfig
