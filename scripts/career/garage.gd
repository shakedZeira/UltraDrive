# scripts/career/garage.gd
class_name Garage
extends RefCounted

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

## Cars that can never be sold off: the free base trio the garage must keep.
const STARTER_PROTECTED: Array[String] = ["starter_car", "muscle_car", "rally_hatch"]

## Resale returns this fraction of the sticker price (item 11 economy).
const RESALE_RATIO: float = 0.5

static func get_price(car_id: String) -> int:
	var config := load("res://resources/cars/%s.tres" % car_id) as CarConfig
	return config.price if config != null else 0

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

## Purchases a car: gated by the license unlocking its class and by the
## wallet covering the price. Already-owned cars are a successful no-op.
func buy_car(car_id: String, money: Money) -> bool:
	if car_id in _owned_cars:
		return true
	var price := get_price(car_id)
	if price <= 0:
		return false
	var config := load("res://resources/cars/%s.tres" % car_id) as CarConfig
	if config == null:
		return false
	if not LicenseSystem.load_from_save().is_car_unlocked(config.car_class):
		return false
	if money.get_credits() < price:
		return false
	if not money.spend(price):
		return false
	add_car(car_id)
	return true

## Sells a car back at the resale ratio. The base starter trio is protected and
## can never be sold.
func sell_car(car_id: String, money: Money) -> bool:
	if car_id not in _owned_cars or car_id in STARTER_PROTECTED:
		return false
	var price := get_price(car_id)
	if price <= 0:
		return false
	money.add(int(price * RESALE_RATIO))
	remove_car(car_id)
	return true

## True when the player could use this car right now: license unlocks its
## class AND it is either owned or affordable from the persistent wallet.
func is_car_accessible(car_id: String) -> bool:
	var config := load("res://resources/cars/%s.tres" % car_id) as CarConfig
	if config == null:
		return false
	if not LicenseSystem.load_from_save().is_car_unlocked(config.car_class):
		return false
	if car_id in _owned_cars:
		return true
	return Money.load_wallet().get_credits() >= get_price(car_id)

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
