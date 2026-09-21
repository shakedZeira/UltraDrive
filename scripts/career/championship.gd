# scripts/career/championship.gd
class_name Championship
extends RefCounted

## Manages a multi-race championship with F1-style points. Item 11 layers a
## seasonal calendar (series with a required car class) and podium payouts
## on top of the existing points flow. Reward seams (money_ledger/profile,
## garage/license) can be injected by tests; otherwise the persistent
## wallet/profile and slot saves are used.

const POINTS := [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
const PODIUM_PAYOUTS := [5000, 3000, 1500]
const CLASSES := ["D", "C", "B", "A", "S"]

var championship_name: String = ""
var races: Array = []  # Array[Dictionary] - track names and configs
var _scores: Dictionary = {}  # car_name -> points
var _current_race: int = 0

var _series: Array[Dictionary] = []
var _license: LicenseSystem = null
var _garage: Garage = null

var money_ledger: Money = null
var profile: CareerProfile = null

func set_license(license: LicenseSystem) -> void:
	_license = license

func set_garage(garage: Garage) -> void:
	_garage = garage

## Replaces the seasonal calendar: Array[Dictionary] entries shaped as
## {"name": String, "car_class_required": String, "races": Array}.
func set_season(matches: Array[Dictionary]) -> void:
	_series = matches

func get_series() -> Array[Dictionary]:
	return _series

## Loads the match at `index` into the active championship.
func select_series(index: int) -> bool:
	if index < 0 or index >= _series.size():
		return false
	var match: Dictionary = _series[index]
	start_championship(match.get("name", ""), match.get("races", []))
	return true

func start_championship(champ_name: String, race_list: Array) -> void:
	championship_name = champ_name
	races = race_list
	_scores = {}
	_current_race = 0

func can_enter_series(series: Dictionary) -> bool:
	## Gate: license must unlock the required class AND the garage must own a
	## car of at least that class.
	var required: String = series.get("car_class_required", "D")
	if required not in CLASSES:
		return false
	var license: LicenseSystem = _license if _license != null else LicenseSystem.load_from_save()
	if not license.is_car_unlocked(required):
		return false
	var garage: Garage = _garage if _garage != null else Garage.new_from_save()
	return _best_class_rank(garage) >= CLASSES.find(required)

func podium_payout(position: int) -> int:
	if position >= 1 and position <= PODIUM_PAYOUTS.size():
		return PODIUM_PAYOUTS[position - 1]
	return 0

func complete_race(position: int) -> void:
	## Award points based on finishing position (1-indexed) plus a podium
	## payout and XP for a top-3 finish.
	if position >= 1 and position <= POINTS.size():
		var participant := "player"  # simplify: single-player championship
		_scores[participant] = _scores.get(participant, 0) + POINTS[position - 1]
	var payout := podium_payout(position)
	if payout > 0:
		if money_ledger:
			money_ledger.add(payout)
		else:
			Money.wallet_add(payout)
		if profile:
			profile.add_xp(CareerProfile.PODIUM_XP)
		else:
			CareerProfile.grant_xp(CareerProfile.PODIUM_XP)
	_current_race += 1

func get_standings() -> Dictionary:
	return _scores

func is_complete() -> bool:
	return _current_race >= races.size()

func get_next_race() -> Dictionary:
	if _current_race < races.size():
		return races[_current_race]
	return {}

func _best_class_rank(garage: Garage) -> int:
	var best := -1
	for car_id in garage.get_owned_cars():
		var config := load("res://resources/cars/%s.tres" % car_id) as CarConfig
		var cls := config.car_class if config != null else "D"
		var rank := CLASSES.find(cls)
		if rank > best:
			best = rank
	return best