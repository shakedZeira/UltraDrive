extends Node

## Manages the active race: checkpoints, lap timing, positions.

signal race_started
signal race_finished(standings: Array)

var is_race_active: bool = false
var total_laps: int = 3
var _participants: Array[VehiclePhysics] = []
var _lap_counters: Dictionary = {}
var _race_time: float = 0.0

func start_race(cars: Array, laps: int) -> void:
    _participants = cars
    total_laps = laps
    _lap_counters = {}
    for car in cars:
        _lap_counters[car] = LapCounter.new()
        add_child(_lap_counters[car])
        _lap_counters[car].start_race(laps)
    _race_time = 0.0
    is_race_active = true
    race_started.emit()

func finish_race() -> void:
    is_race_active = false
    var standings := get_standings()
    race_finished.emit(standings)

func get_standings() -> Array:
    ## Returns array of cars sorted by progress (lap, then checkpoint, then distance)
    var sorted := _participants.duplicate()
    sorted.sort_custom(func(a, b):
        var a_lap: int = (_lap_counters[a] as LapCounter).get_current_lap() if _lap_counters.has(a) else 1
        var b_lap: int = (_lap_counters[b] as LapCounter).get_current_lap() if _lap_counters.has(b) else 1
        return a_lap > b_lap
    )
    return sorted

func get_lap_counter(car: VehiclePhysics) -> LapCounter:
    return _lap_counters.get(car)

func _process(delta: float) -> void:
    if is_race_active:
        _race_time += delta
        # Check all participants for passed checkpoints
        var checkpoints := get_tree().get_nodes_in_group("checkpoints")
        for car in _participants:
            var counter: LapCounter = _lap_counters[car]
            for cp in checkpoints:
                if cp.is_passed(car):
                    var result := counter.update(car, cp)
                    if result["race_finished"]:
                        finish_race()
