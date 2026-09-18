# scripts/career/garage.gd
class_name Garage
extends Node

## Manages player's car collection.

var _owned_cars: Array[String] = []
var _active_car: String = "starter_car"

const STARTER_CARS: Array[String] = [
	"starter_car",
	"muscle_car",
	"rally_hatch",
	"cc0_sedan_sports",
	"cc0_hatchback_sports",
	"cc0_race",
]

## Builds a Garage populated from the persisted save. Seeds the starter cars
## (and any missing starter models) so the garage always has the base trio.
static func new_from_save() -> Garage:
	var garage := Garage.new()
	garage.load_data(SaveManager.load_game(0))
	for car_id in STARTER_CARS:
		if car_id not in garage._owned_cars:
			garage.add_car(car_id)
	if garage._owned_cars.is_empty():
		garage.add_car("starter_car")
	return garage

func add_car(car_id: String) -> void:
	if car_id not in _owned_cars:
		_owned_cars.append(car_id)
		save()

func remove_car(car_id: String) -> void:
	_owned_cars.erase(car_id)
	if _active_car == car_id:
		_active_car = _owned_cars[0] if _owned_cars.size() > 0 else ""
	save()

func get_owned_cars() -> Array[String]:
	return _owned_cars

func set_active_car(car_id: String) -> void:
	if car_id in _owned_cars:
		_active_car = car_id
		save()

func get_active_car() -> String:
	return _active_car

func save() -> void:
	var data := SaveManager.load_game(0)
	data["owned_cars"] = _owned_cars
	data["active_car"] = _active_car
	SaveManager.save_game(0, data)

func load_data(data: Dictionary) -> void:
	if data.has("owned_cars"):
		_owned_cars.assign(data["owned_cars"])
	if data.has("active_car"):
		_active_car = data["active_car"]
