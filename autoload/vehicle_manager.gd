extends Node

## Tracks the active player car and provides spawning utilities.

signal car_registered(car: VehiclePhysics)
signal car_removed(car: VehiclePhysics)

var player_car: VehiclePhysics = null
var all_cars: Array[VehiclePhysics] = []

func register_player_car(car: VehiclePhysics) -> void:
	player_car = car
	if car not in all_cars:
		all_cars.append(car)
	car_registered.emit(car)

func register_ai_car(car: VehiclePhysics) -> void:
	if car not in all_cars:
		all_cars.append(car)

func remove_car(car: VehiclePhysics) -> void:
	all_cars.erase(car)
	if car == player_car:
		player_car = null
	car_removed.emit(car)

func get_player_car() -> VehiclePhysics:
	return player_car

func get_all_cars() -> Array[VehiclePhysics]:
	return all_cars