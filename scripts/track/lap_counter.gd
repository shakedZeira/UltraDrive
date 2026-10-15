class_name LapCounter
extends Node

## Tracks lap progress for vehicles by monitoring checkpoints.

signal lap_completed(vehicle: VehiclePhysics, lap: int, time: float)
signal race_finished(vehicle: VehiclePhysics, total_time: float)

var total_laps: int = 3
var _race_start_time: float = 0.0
var _lap_start_time: float = 0.0
var _current_lap: int = 1
var _last_checkpoint: int = -1
## Distinct (non-finish) gate indices taken THIS lap. A finish-line crossing
## completes the lap only when this holds at least half the field's
## checkpoints, so an off-track excursion that misses a gate or three costs
## that progress -- not the lap -- while cutting most of the course earns no
## lap at all ("no laps gained by skipping gates").
var _passed_in_lap: Dictionary = {}
var _finished: bool = false

func start_race(laps: int) -> void:
	total_laps = laps
	_current_lap = 1
	_last_checkpoint = -1
	_passed_in_lap.clear()
	_finished = false
	var now := Time.get_ticks_msec() / 1000.0
	_race_start_time = now
	_lap_start_time = now

func update(vehicle: VehiclePhysics, passed_checkpoint: Checkpoint) -> Dictionary:
	## Called by RaceManager when a vehicle passes a checkpoint.
	## Returns { lap_completed: bool, race_finished: bool }
	##
	## Progression is a forward high-water mark (`_last_checkpoint`, used for
	## standings) plus the set of distinct gates taken this lap -- NOT a strict
	## "next index expected" chain. The strict chain desynced permanently the
	## moment a car missed one gate (off-track excursion), after which no
	## finish crossing could ever be counted again. Gates may now arrive in
	## any order; duplicates and backward moves simply do not advance state.

	var total := _get_total_checkpoints()
	if total == 0:
		return {"lap_completed": false, "race_finished": false}

	var index := passed_checkpoint.index
	if index == total - 1:
		# Finish-line crossing: it completes a lap only if the car has taken at
		# least half of the circuit's OTHER gates this lap (total / 2 of them,
		# integer division: 4 of 7 on an 8-gate track, 1 of 1 on a 2-gate
		# track, and, on the degenerate single-checkpoint track, 0 -- any
		# crossing completes there).
		if _passed_in_lap.size() < total / 2:
			# Reject. The crossing still must not be swallowed: release the
			# checkpoint's pass latch (see Checkpoint.uncount) or this latched
			# pass would eat every later legitimate crossing, because nothing
			# re-arms the finish gate until a lap completes -- and this
			# crossing just failed to. The gate set is left intact; it keeps
			# accumulating toward the threshold.
			passed_checkpoint.uncount(vehicle)
			return {"lap_completed": false, "race_finished": false}
		_current_lap += 1
		lap_completed.emit(vehicle, _current_lap - 1, get_lap_time())
		_lap_start_time = Time.get_ticks_msec() / 1000.0
		# Fresh lap: no gates credited, high-water back at the line.
		_passed_in_lap.clear()
		_last_checkpoint = -1
		if _current_lap > total_laps:
			_finished = true
			race_finished.emit(vehicle, get_total_time())
			return {"lap_completed": true, "race_finished": true}
		return {"lap_completed": true, "race_finished": false}

	# Ordinary gate: credit the distinct gate (idempotent for re-passes) and
	# advance the high-water mark on forward moves only.
	if index > _last_checkpoint:
		_last_checkpoint = index
	_passed_in_lap[index] = true
	return {"lap_completed": false, "race_finished": false}

func get_current_lap() -> int:
	return _current_lap

## True after the vehicle crossed the final checkpoint of its last lap. Used by
## RaceManager to record a rival's W/L result exactly once per finished rival.
func is_finished() -> bool:
	return _finished

func get_last_checkpoint() -> int:
	return _last_checkpoint

func get_lap_time() -> float:
	return (Time.get_ticks_msec() / 1000.0) - _lap_start_time

func get_total_time() -> float:
	return (Time.get_ticks_msec() / 1000.0) - _race_start_time

func _get_total_checkpoints() -> int:
	return get_tree().get_nodes_in_group("checkpoints").size()