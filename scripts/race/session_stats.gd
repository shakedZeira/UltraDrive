# scripts/race/session_stats.gd
class_name SessionStats
extends RefCounted

## Session-wide driving accumulator: distance driven, top speed, peak G, drift
## time and clean/best lap flags, shared across free-roam and races. Pure
## RefCounted — no scene access. race_ui feeds it via tick() each frame; the
## lap seams (LapCounter.lap_completed + item 8's impact signal) drive
## start_lap() / note_impact() / end_lap().

const MAX_G := 6.0
const KMH_TO_MS := 1.0 / 3.6

var _distance_m: float = 0.0
var _top_speed_kmh: float = 0.0
var _max_g: float = 0.0
var _drift_time: float = 0.0
var _total_laps: int = 0
var _clean_laps: int = 0
var _best_lap: float = 0.0
var _lap_impacts: int = 0
var _last_lap_clean: bool = false

func tick(delta: float, speed_kmh: float, max_g: float, drifting: bool) -> void:
	delta = maxf(delta, 0.0)
	speed_kmh = maxf(speed_kmh, 0.0)
	_distance_m += speed_kmh * KMH_TO_MS * delta
	_top_speed_kmh = maxf(_top_speed_kmh, speed_kmh)
	_max_g = maxf(_max_g, clampf(absf(max_g), 0.0, MAX_G))
	if drifting:
		_drift_time += delta

func note_impact() -> void:
	_lap_impacts += 1

func start_lap() -> void:
	_lap_impacts = 0
	_last_lap_clean = false

func end_lap(lap_time: float) -> void:
	_total_laps += 1
	_last_lap_clean = _lap_impacts == 0
	if _last_lap_clean:
		_clean_laps += 1
	_lap_impacts = 0
	if lap_time > 0.0 and (_best_lap <= 0.0 or lap_time < _best_lap):
		_best_lap = lap_time

func reset() -> void:
	_distance_m = 0.0
	_top_speed_kmh = 0.0
	_max_g = 0.0
	_drift_time = 0.0
	_total_laps = 0
	_clean_laps = 0
	_best_lap = 0.0
	_lap_impacts = 0
	_last_lap_clean = false

func get_distance_m() -> float:
	return _distance_m

func get_distance_km() -> float:
	return _distance_m / 1000.0

func get_top_speed_kmh() -> float:
	return _top_speed_kmh

func get_max_g() -> float:
	return _max_g

func get_drift_time() -> float:
	return _drift_time

func get_total_laps() -> int:
	return _total_laps

func get_clean_laps() -> int:
	return _clean_laps

func get_best_lap() -> float:
	return _best_lap

func get_lap_impacts() -> int:
	return _lap_impacts

func last_lap_was_clean() -> bool:
	return _last_lap_clean