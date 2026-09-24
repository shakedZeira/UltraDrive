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
var _finished: bool = false

func start_race(laps: int) -> void:
	total_laps = laps
	_current_lap = 1
	_last_checkpoint = -1
	_finished = false
	var now := Time.get_ticks_msec() / 1000.0
	_race_start_time = now
	_lap_start_time = now

func update(vehicle: VehiclePhysics, passed_checkpoint: Checkpoint) -> Dictionary:
	## Called by RaceManager when a vehicle passes a checkpoint.
	## Returns { lap_completed: bool, race_finished: bool }

	var total := _get_total_checkpoints()
	if total == 0:
		return {"lap_completed": false, "race_finished": false}

	# Check for valid progression (allows wrap-around)
	var expected := (_last_checkpoint + 1) % total
	if passed_checkpoint.index == expected:
		_last_checkpoint = passed_checkpoint.index

		# If we've passed the last checkpoint, a lap is complete
		if _last_checkpoint == total - 1:
			_current_lap += 1
			lap_completed.emit(vehicle, _current_lap - 1, get_lap_time())
			_lap_start_time = Time.get_ticks_msec() / 1000.0

			if _current_lap > total_laps:
				_finished = true
				race_finished.emit(vehicle, get_total_time())
				return {"lap_completed": true, "race_finished": true}

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