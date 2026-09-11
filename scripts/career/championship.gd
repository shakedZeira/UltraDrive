# scripts/career/championship.gd
class_name Championship
extends Node

## Manages a multi-race championship with F1-style points.

const POINTS := [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]

var championship_name: String = ""
var races: Array = []  # Array[Dictionary] - track names and configs
var _scores: Dictionary = {}  # car_name -> points
var _current_race: int = 0

func start_championship(champ_name: String, race_list: Array) -> void:
	championship_name = champ_name
	races = race_list
	_scores = {}
	_current_race = 0

func complete_race(position: int) -> void:
	## Award points based on finishing position (1-indexed).
	if position >= 1 and position <= POINTS.size():
		var participant := "player"  # simplify: single-player championship
		_scores[participant] = _scores.get(participant, 0) + POINTS[position - 1]
	_current_race += 1

func get_standings() -> Dictionary:
	return _scores

func is_complete() -> bool:
	return _current_race >= races.size()

func get_next_race() -> Dictionary:
	if _current_race < races.size():
		return races[_current_race]
	return {}
