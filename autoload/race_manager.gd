extends Node

## Manages the active race: checkpoints, lap timing, positions.

signal race_started
signal race_finished(standings: Array)

var is_race_active: bool = false
var total_laps: int = 3
var _participants: Array[VehiclePhysics] = []
var _lap_counters: Dictionary = {}
var _race_time: float = 0.0
var _pending_laps: int = 0
var _checkpoints_cache: Array[Checkpoint] = []
var _checkpoints_dirty: bool = true

func _ready() -> void:
	GameState.scene_changed.connect(func(_scene: String) -> void: _checkpoints_dirty = true)

func queue_race(laps: int) -> void:
	_pending_laps = laps

func consume_pending_race() -> int:
	var laps := _pending_laps
	_pending_laps = 0
	return laps

func get_race_time() -> float:
	return _race_time

func start_race(cars: Array, laps: int) -> void:
	for counter in _lap_counters.values():
		(counter as LapCounter).queue_free()
	_lap_counters = {}
	_participants.assign(cars)
	total_laps = laps
	_race_time = 0.0
	for car in cars:
		var counter := LapCounter.new()
		_lap_counters[car] = counter
		add_child(counter)
		counter.lap_completed.connect(reset_checkpoints)
		counter.start_race(laps)
	is_race_active = true
	_checkpoints_dirty = true
	reset_checkpoints()
	race_started.emit()

func finish_race() -> void:
	is_race_active = false
	var standings := get_standings()
	race_finished.emit(standings)

func get_standings() -> Array:
	## Returns array of cars sorted by progress (lap, then checkpoint, then distance)
	var sorted := _participants.duplicate()
	sorted.sort_custom(func(a: VehiclePhysics, b: VehiclePhysics) -> bool:
		var a_lap: int = _lap_of(a)
		var b_lap: int = _lap_of(b)
		if a_lap != b_lap:
			return a_lap > b_lap
		var a_cp: int = _checkpoint_of(a)
		var b_cp: int = _checkpoint_of(b)
		if a_cp != b_cp:
			return a_cp > b_cp
		return _distance_to_next_checkpoint(a, a_cp) < _distance_to_next_checkpoint(b, b_cp)
	)
	return sorted

func _lap_of(car: VehiclePhysics) -> int:
	var counter: LapCounter = _lap_counters.get(car)
	return counter.get_current_lap() if counter != null else 1

func _checkpoint_of(car: VehiclePhysics) -> int:
	var counter: LapCounter = _lap_counters.get(car)
	return counter.get_last_checkpoint() if counter != null else -1

func _distance_to_next_checkpoint(car: VehiclePhysics, last_checkpoint: int) -> float:
	var cps := _all_checkpoints()
	if cps.is_empty():
		return 0.0
	var next_index := (last_checkpoint + 1) % cps.size()
	var target: Checkpoint = cps[next_index]
	var offset := car.global_position - target.global_position
	return Vector2(offset.x, offset.z).length()

func get_lap_counter(car: VehiclePhysics) -> LapCounter:
	return _lap_counters.get(car)

func reset_checkpoints() -> void:
	for cp in _all_checkpoints():
		cp.reset()

func get_checkpoints() -> Array[Checkpoint]:
	return _all_checkpoints()

func _all_checkpoints() -> Array[Checkpoint]:
	if _checkpoints_dirty or not _cache_valid():
		_checkpoints_cache.clear()
		for node in get_tree().get_nodes_in_group("checkpoints"):
			if node is Checkpoint:
				_checkpoints_cache.append(node)
		_checkpoints_dirty = false
	return _checkpoints_cache

func _cache_valid() -> bool:
	for cp in _checkpoints_cache:
		if not is_instance_valid(cp):
			return false
	return true

func _process(delta: float) -> void:
	if not is_race_active:
		return
	_race_time += delta
	var checkpoints := _all_checkpoints()
	for car in _participants:
		var counter: LapCounter = _lap_counters.get(car)
		if counter == null:
			continue
		for cp in checkpoints:
			if cp.is_passed(car):
				var result := counter.update(car, cp)
				if result["race_finished"]:
					finish_race()
					return