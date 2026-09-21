extends Node

## Manages the active race: ceremony countdown, checkpoints, lap timing, positions.

signal race_started
signal race_finished(standings: Array)

## Grid layout for a configured rival roster (S5), anchored ahead of the player.
const RIVAL_GRID_COLUMNS := 2
const RIVAL_GRID_COL_SPACING := 3.0
const RIVAL_GRID_ROW_SPACING := 6.0
const RIVAL_GRID_ANCHOR_AHEAD := 8.0
const RIVAL_GRID_START_Y := 0.3

var is_race_active: bool = false
var total_laps: int = 3
var _countdown: RaceCountdown = RaceCountdown.new()
var _participants: Array[VehiclePhysics] = []
var _lap_counters: Dictionary = {}
var _race_time: float = 0.0
var _pending_laps: int = 0
var _checkpoints_cache: Array[Checkpoint] = []
var _checkpoints_dirty: bool = true

## S5 rival roster: ordered specs of {car_config, tier} spawned into the grid at
## start_race (empty roster = no rivals, free roam unchanged). The vehicle is
## built from rival_vehicle_scene (default rival_car.tscn) or a custom spawner
## callback (grid_spawner GridSpawner.spawn_grid) for richer visuals.
var rival_roster: Array[Dictionary] = []
var rival_centerline: Array[Vector3] = []
var rival_vehicle_scene: PackedScene = preload("res://scenes/vehicle/rival_car.tscn")
var rival_spawner: Callable = Callable()
var _spawned_rivals: Array[VehiclePhysics] = []

func _ready() -> void:
	GameState.scene_changed.connect(func(_scene: String) -> void: _checkpoints_dirty = true)

## Ceremony-aware start seam: any start source (track select today, free-roam
## events later) lands here to queue a race for the HUD to commit.
## Debounced (hardening): while a race is live or its ceremony/results run the
## request is refused, so a second start source can never re-arm or replace the
## active race. The HUD drains _pending_laps once per frame anyway, so a stale
## accepted request would otherwise double-start.
func request_race(laps: int) -> void:
	if is_race_active:
		return
	_pending_laps = laps

func queue_race(laps: int) -> void:
	if is_race_active:
		return
	_pending_laps = laps

## The countdown gate: true while the ceremony is running (phases 3/2/1/GO).
## Free-roam and post-race states never lock controls.
func controls_locked() -> bool:
	return is_race_active and _countdown != null and _countdown.controls_locked()

## Normalized rev override (0 = idle, 1 = redline) for drivetrain anticipation
## while controls are locked. Zero outside an active ceremony.
func rev_override() -> float:
	if _countdown == null or not is_race_active:
		return 0.0
	return _countdown.rev_rpm_override()

func get_countdown() -> RaceCountdown:
	return _countdown

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
	for rival in _spawn_configured_rivals():
		_participants.append(rival)
	for car in _participants:
		car.release_ground_lock()
	total_laps = laps
	_race_time = 0.0
	for car in _participants:
		var counter := LapCounter.new()
		_lap_counters[car] = counter
		add_child(counter)
		counter.lap_completed.connect(reset_checkpoints)
		counter.start_race(laps)
	is_race_active = true
	_countdown.start()
	_checkpoints_dirty = true
	reset_checkpoints()
	race_started.emit()

func set_rival_roster(specs: Array) -> void:
	rival_roster.assign(specs)

func set_rival_centerline(line: Array[Vector3]) -> void:
	rival_centerline.assign(line)

func set_rival_vehicle_scene(scene: PackedScene) -> void:
	rival_vehicle_scene = scene

func set_rival_spawner(spawn: Callable) -> void:
	rival_spawner = spawn

func get_spawned_rivals() -> Array[VehiclePhysics]:
	return _spawned_rivals

## Builds a rival spec for roster configuration: {car_config, tier}.
static func rival_spec(car_config: CarConfig, tier: String) -> Dictionary:
	return {"car_config": car_config, "tier": tier}

## Spawns the configured rival roster into a grid ahead of the player, keeping
## roster order. Returns the spawned cars (also cached in _spawned_rivals).
## Re-run of start_race replaces the previous grid.
func _spawn_configured_rivals() -> Array[VehiclePhysics]:
	_spawned_rivals.clear()
	if rival_roster.is_empty():
		return _spawned_rivals
	if rival_vehicle_scene == null and not rival_spawner.is_valid():
		return _spawned_rivals
	var player := VehicleManager.get_player_car()
	if player == null and not _participants.is_empty():
		player = _participants[0]
	if player == null:
		return _spawned_rivals
	for spec in rival_roster:
		var car := _spawn_rival_car(spec, player)
		if car != null:
			_spawned_rivals.append(car)
	return _spawned_rivals

func _spawn_rival_car(spec: Dictionary, player: VehiclePhysics) -> VehiclePhysics:
	var cfg := spec.get("car_config") as CarConfig
	var tier := String(spec.get("tier", "Skilled"))
	var car: VehiclePhysics = null
	if rival_spawner.is_valid():
		car = rival_spawner.call(cfg, tier) as VehiclePhysics
	elif rival_vehicle_scene != null:
		car = rival_vehicle_scene.instantiate() as VehiclePhysics
	if car == null:
		return null
	if cfg != null:
		car.config = cfg
	var car_class_name := cfg.car_class if cfg != null else "D"
	var row := _spawned_rivals.size() / RIVAL_GRID_COLUMNS
	var col := _spawned_rivals.size() % RIVAL_GRID_COLUMNS
	var offset := Vector3(
		(float(col) - 0.5) * RIVAL_GRID_COL_SPACING,
		RIVAL_GRID_START_Y,
		RIVAL_GRID_ANCHOR_AHEAD + float(row) * RIVAL_GRID_ROW_SPACING)
	add_child(car)
	# Position AFTER entering the tree: global_position is a no-op on a node
	# without a parent (the transform setter is dropped), so the grid offset
	# would otherwise collapse to the origin.
	car.global_position = player.global_position + offset
	car.global_rotation = Vector3.ZERO
	var driver := RivalDriver.new()
	driver.configure(rival_centerline, tier, car_class_name)
	car.add_child(driver)
	return car

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
	if not controls_locked():
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