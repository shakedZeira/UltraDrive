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

## S5 production roster. MAX_RIVAL_OPPONENTS caps a GameState.opponents field;
## _TIER_SPREAD spreads the field across skill tiers around the difficulty anchor
## so a race is never N clones of one pace. Deterministic per grid slot, no RNG.
const MAX_RIVAL_OPPONENTS := 7
const _TIER_ORDER: Array[String] = ["Novice", "Skilled", "Expert"]
const _TIER_SPREAD: Array[int] = [0, -1, 1, 0, -1, 1, 0]

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

## A4 rival personalities: ordered personas attached to the roster (by index or
## via each spec's "persona" key). Pure presentation/persistence over the
## existing roster — the RivalDriver's pace/tier logic is untouched, so
## no-rubber-band invariants stay byte-identical. _car_persona maps each spawned
## rival car to its persona for grid/standings/results name+record lookups, and
## _recorded_results guards the W/L record to exactly one update per finished
## rival per race.
var roster_personas: Array[RivalPersona] = []
var _car_persona: Dictionary = {}
var _recorded_results: Dictionary = {}

func _ready() -> void:
	GameState.scene_changed.connect(_on_scene_changed)

## Scene transitions tear down the track that published the rival centerline, so
## the cached roster/centerline/personas AND any cars still parented here must be
## released: a leftover rival keeps driving a dead track and leaks a RigidBody per
## race (this autoload never unloads). Checkpoints are re-collected by the new
## scene, so the cache is marked dirty too.
func _on_scene_changed(_scene: String) -> void:
	clear_rival_config()
	_checkpoints_dirty = true

## Frees the current spawn grid and drops the cached roster/centerline/personas.
## Idempotent (safe on an already-empty RaceManager). Vehicle scene + spawner
## callback are configuration, not per-race state, so they are left alone.
func clear_rival_config() -> void:
	_free_spawned_rivals()
	rival_roster = []
	rival_centerline = []
	roster_personas = []
	_car_persona = {}
	_recorded_results = {}

## Detaches + frees every rival spawned for the previous race. RaceManager is an
## autoload, so `add_child`ed rivals outlive a scene change unless explicitly
## removed — leaving them is the cross-race leak. remove_child immediately breaks
## the parent/child link (so a same-frame respawn cannot see a half-freed car)
## and queue_free defers the actual delete to the frame boundary.
func _free_spawned_rivals() -> void:
	for car in _spawned_rivals:
		if is_instance_valid(car):
			remove_child(car)
			car.queue_free()
	_spawned_rivals.clear()

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
	_car_persona = {}
	_recorded_results = {}
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
		counter.lap_completed.connect(_on_lap_completed)
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

## A4: attaches an ordered persona roster (same order as rival_roster). Each
## persona is also picked up from spec["persona"] at spawn when set directly.
func set_personas(personas: Array) -> void:
	roster_personas.clear()
	for persona in personas:
		var p := persona as RivalPersona
		if p != null:
			roster_personas.append(p)

func get_personas() -> Array[RivalPersona]:
	return roster_personas.duplicate()

## Persona for a spawned rival car (null for the player / un-persona'd cars).
func get_persona_for(car: VehiclePhysics) -> RivalPersona:
	return _car_persona.get(car) as RivalPersona

func get_spawned_rivals() -> Array[VehiclePhysics]:
	return _spawned_rivals

## Builds a rival spec for roster configuration: {car_config, tier}. Passing an
## optional persona embeds it directly so RaceManager picks it up at spawn.
static func rival_spec(car_config: CarConfig, tier: String, persona: RivalPersona = null) -> Dictionary:
	var spec := {"car_config": car_config, "tier": tier}
	if persona != null:
		spec["persona"] = persona
	return spec

## Spawns the configured rival roster into a grid ahead of the player, keeping
## roster order. Returns the spawned cars (also cached in _spawned_rivals).
## Re-run of start_race replaces the previous grid.
func _spawn_configured_rivals() -> Array[VehiclePhysics]:
	_free_spawned_rivals()
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
	# Rival visuals: cycle the shared GLB roster so a grid reads as a mixed field
	# instead of N identical boxes. Runs BEFORE add_child so RivalCarVisual
	# builds exactly once (its _ready skips a rebuild when a visual exists).
	_assign_rival_visual(car, _spawned_rivals.size(), tier)
	add_child(car)
	# Audible rival engines (idempotent): the production rival scene ships an
	# EngineAudio node, so this is a no-op today; it guarantees audio for a
	# swapped-in rival scene that lacks one.
	EngineAudio.ensure_for(car)
	# Position AFTER entering the tree: global_transform is a no-op on a node
	# without a parent (the transform setter is dropped), so the grid placement
	# would otherwise collapse to the origin. Track-frame transform: the car
	# faces the centerline tangent at its grid point (world-axis placement faced
	# every rival at world -Z, i.e. sideways on the +X-travelling oval).
	car.global_transform = _rival_grid_transform(player, _spawned_rivals.size())
	GridSpawner.apply_tier_color(car, tier)
	var driver := RivalDriver.new()
	driver.configure(rival_centerline, tier, car_class_name,
		_nearest_centerline_index(car.global_position))
	car.add_child(driver)
	# A4: map the persona (spec["persona"] first, else the ordered roster entry
	# at this spawn index) so grid/standings/results can read name + record.
	if not _car_persona.has(car):
		var persona := spec.get("persona") as RivalPersona
		if persona == null and roster_personas.size() > _spawned_rivals.size():
			persona = roster_personas[_spawned_rivals.size()]
		if persona != null:
			_car_persona[car] = persona
	return car

## Assigns a distinct real-car GLB to a spawned rival. The visual roster is
## cycled by grid slot (CarVisuals.RIVAL_VISUALS), and the rival's skill tier
## paints it through CarVisuals.RIVAL_PALETTE, so the field reads as a mixed
## grid of real cars instead of N identical placeholder boxes. Only the visual
## layer is touched — physics, colliders and the Wheel* nodes are untouched.
func _assign_rival_visual(car: VehiclePhysics, index: int, tier: String) -> void:
	CarVisuals.assign_rival_visual(car, index, tier)

## --- S5 production roster ---------------------------------------------------

## The field the HUD commits through race_ui's start seam. Builds GameState.
## opponents rival specs around the player's own car config (an even field — the
## player is never out-classed by their own grid), spreads them across skill
## tiers around GameState.ai_difficulty, attaches personas for `slot`, and
## installs them as the roster. Safe to call unconditionally: no-op while the
## scene has published no usable centerline (< 2 points: free roam / most scenes)
## or when the player asked for a solo race.
func configure_default_rivals(player: VehiclePhysics = null, slot: int = 0) -> void:
	if rival_centerline.size() < 2:
		return
	var count := GameState.clamp_opponents(GameState.opponents)
	if count <= 0:
		return
	var resolved_player := player
	if resolved_player == null:
		resolved_player = VehicleManager.get_player_car()
	var config := _player_config(resolved_player)
	var anchor := GameState.normalize_difficulty(GameState.ai_difficulty)
	var specs: Array[Dictionary] = []
	for i in range(count):
		specs.append(rival_spec(config, _tier_for_slot(anchor, i)))
	var contract := RivalPersona.contract_for_slot(specs, slot)
	var personas: Array = contract.get("personas", [])
	# A restored field keeps its names + W/L records, but the presented tier must
	# always mirror the tier the RivalDriver actually races (the spec), or changing
	# the difficulty would leave the grid card advertising the old pace. Re-sync the
	# in-memory tier to the fresh spec (the persisted record is unaffected; the next
	# run re-syncs again, so it is idempotent).
	for i in range(personas.size()):
		var persona := personas[i] as RivalPersona
		if persona != null and i < specs.size():
			persona.tier = RacingLine.normalize_tier(String(specs[i].get("tier", "Skilled")))
	set_rival_roster(specs)
	set_personas(personas)

## Skill tier for grid slot `index`: the difficulty anchor nudged by the
## deterministic spread ladder and clamped to Novice..Expert. Slot 0 is always
## the anchor itself, so the selected difficulty names the leading rival.
func _tier_for_slot(anchor: String, index: int) -> String:
	var base := _TIER_ORDER.find(anchor)
	if base < 0:
		base = 1
	var delta := _TIER_SPREAD[index % _TIER_SPREAD.size()]
	return _TIER_ORDER[clampi(base + delta, 0, _TIER_ORDER.size() - 1)]

## The player's car config for the field, falling back to the starter car when
## there is no registered player / no config (so a race always has a real car).
func _player_config(player: VehiclePhysics) -> CarConfig:
	if player != null and player.config != null:
		return player.config
	return load("res://resources/cars/starter_car.tres") as CarConfig

## World transform for the rival at roster slot `slot` in the grid ahead of the
## player. Track-frame correct: forward is the centerline tangent at the grid
## point, so cars face down the track. Falls back to the player's own heading
## when the scene published no usable centerline.
func _rival_grid_transform(player: VehiclePhysics, slot: int) -> Transform3D:
	var row := slot / RIVAL_GRID_COLUMNS
	var col := slot % RIVAL_GRID_COLUMNS
	var lateral := (float(col) - 0.5) * RIVAL_GRID_COL_SPACING
	var ahead := RIVAL_GRID_ANCHOR_AHEAD + float(row) * RIVAL_GRID_ROW_SPACING
	var grid := _centerline_grid_point(player, ahead, lateral)
	if grid.is_empty():
		return _heading_grid_transform(player, ahead, lateral)
	return Transform3D(_grid_basis(grid["forward"] as Vector3), grid["position"] as Vector3)

## Grid point `ahead` m of arc forward of the player's nearest centerline index,
## offset `lateral` m along the track's right (outfield) direction. Returns {}
## when there is no usable centerline.
func _centerline_grid_point(player: VehiclePhysics, ahead: float, lateral: float) -> Dictionary:
	var count := rival_centerline.size()
	if count < 2:
		return {}
	var player_pos := player.global_position if player != null else Vector3.ZERO
	var cursor := _nearest_centerline_index(player_pos)
	var remaining := ahead
	var forward := Vector3.FORWARD
	var steps := 0
	while steps < count:
		steps += 1
		var a := rival_centerline[cursor]
		var b := rival_centerline[(cursor + 1) % count]
		var seg := b - a
		seg.y = 0.0
		var seg_len := seg.length()
		if seg_len > 0.0001:
			var dir := seg / seg_len
			if remaining <= seg_len:
				return {
					"position": a + dir * remaining + _lateral_offset(dir, lateral),
					"forward": dir,
				}
			forward = dir
			remaining -= seg_len
		cursor = (cursor + 1) % count
	# `ahead` exceeded the whole (closed) loop: park at the last cursor.
	return {
		"position": rival_centerline[cursor] + _lateral_offset(forward, lateral),
		"forward": forward,
	}

## `lateral` m along the track's right-of-travel direction (`forward x UP`) plus
## the grid stand-off height.
func _lateral_offset(forward: Vector3, lateral: float) -> Vector3:
	var right := forward.cross(Vector3.UP)
	if right.length() > 0.0001:
		right = right.normalized()
	return right * lateral + Vector3.UP * RIVAL_GRID_START_Y

## Index of the centerline point nearest `pos` in XZ (Y ignored: the grid is
## placed relative to the flat oval, not the banked surface height).
func _nearest_centerline_index(pos: Vector3) -> int:
	var best_index := 0
	var best_dist := INF
	for i in range(rival_centerline.size()):
		var p := rival_centerline[i]
		var dx := p.x - pos.x
		var dz := p.z - pos.z
		var d := dx * dx + dz * dz
		if d < best_dist:
			best_dist = d
			best_index = i
	return best_index

## Fallback grid transform when no centerline is published: uses the player's
## own heading so the rival still sits beside/ahead of the player facing the same
## way (never world -Z on a track that travels +X).
func _heading_grid_transform(player: VehiclePhysics, ahead: float, lateral: float) -> Transform3D:
	var forward := Vector3.FORWARD
	var origin := Vector3.ZERO
	if player != null:
		origin = player.global_position
		forward = -player.global_basis.z
	forward.y = 0.0
	if forward.length() < 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var position := origin + forward * ahead + _lateral_offset(forward, lateral)
	return Transform3D(_grid_basis(forward), position)

## Orthonormal basis whose forward axis (-Z) is `forward` flattened to XZ, i.e.
## a car placed with it faces along `forward` (matches AIController's
## `-car.global_basis.z` convention).
func _grid_basis(forward: Vector3) -> Basis:
	var fwd := forward
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.0001 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP)
	right = right.normalized() if right.length() > 0.0001 else Vector3.RIGHT
	var up := right.cross(fwd).normalized()
	return Basis(right, up, -fwd)

func finish_race() -> void:
	var standings := get_standings()
	_record_rivals_results(standings)
	is_race_active = false
	race_finished.emit(standings)

## A4: W/L recording, exactly once per finished rival per race. Only rivals who
## actually crossed the line at the moment the race ends get a record: each is a
## W when it placed ahead of the player in the final standings, an L otherwise.
## _recorded_results makes the update idempotent against a re-fired finish_race.
func _record_rivals_results(standings: Array) -> void:
	if standings.is_empty():
		return
	var player := VehicleManager.get_player_car()
	if player == null or not _participants.has(player):
		return
	var player_rank := standings.find(player)
	if player_rank < 0:
		return
	for car in _spawned_rivals:
		if _recorded_results.has(car):
			continue
		var counter: LapCounter = _lap_counters.get(car)
		if counter == null or not counter.is_finished():
			continue
		var persona := _car_persona.get(car) as RivalPersona
		if persona == null:
			continue
		var rank := standings.find(car)
		if rank < 0:
			continue
		persona.record_result(rank < player_rank)
		_recorded_results[car] = true

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

## Re-arms every checkpoint so `Checkpoint.is_passed` counts each vehicle once
## again. Called directly at `start_race` (lap 1) and from `_on_lap_completed`
## (every lap after that), so it is the ONLY thing that clears `_counted`.
func reset_checkpoints() -> void:
	for cp in _all_checkpoints():
		cp.reset()

## Lap-completion re-arm. The parameter list is deliberately matched to
## `LapCounter.lap_completed` (3 args) -- do NOT "simplify" it back to a bare
## `connect(reset_checkpoints)`: Godot does NO arity check in `connect()` (it
## returns OK), then fails at emit time with "Method expected 0 argument(s), but
## called with 3" and the handler is NEVER run. Bound to the 0-arg
## `reset_checkpoints` that silently made the re-arm a no-op, leaving every
## checkpoint's `_counted` holding each car for the rest of the race, so no lap
## after the first could ever tick (the race was unwinnable from lap 2 on).
func _on_lap_completed(_vehicle: VehiclePhysics, _lap: int, _time: float) -> void:
	reset_checkpoints()

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