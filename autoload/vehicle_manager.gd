extends Node

## Tracks the active player car and provides spawning utilities.

signal car_registered(car)
signal car_removed(car)

var player_car = null
var all_cars: Array = []

func register_player_car(car) -> void:
	player_car = car
	if car not in all_cars:
		all_cars.append(car)
	car_registered.emit(car)

func register_ai_car(car) -> void:
	if car not in all_cars:
		all_cars.append(car)

func remove_car(car) -> void:
	all_cars.erase(car)
	if car == player_car:
		player_car = null
	car_removed.emit(car)

func get_player_car():
	return player_car

func get_all_cars() -> Array:
	return all_cars
