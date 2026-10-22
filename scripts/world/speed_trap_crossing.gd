# scripts/world/speed_trap_crossing.gd
class_name SpeedTrapCrossing
extends Node

## Free-roam speed-trap crossing detector + personal-best recorder.
##
## Contract:
##  * ONE node per world, parented to the open-world root only (the same
##    "absent off-world" contract CollectibleField carries), so a circuit scene
##    never pays for it.
##  * The crossing rule is RADIUS ONLY: the player is inside
##    Collectibles.claim_radius_of(poi). It is deliberately INDEPENDENT of the
##    money gate Collectibles.can_claim() (the speed target) and of the claim
##    ledger: a trap crossed at 40 km/h or already banked still fires, because
##    "did I cross" is not "did it pay".
##  * The trap list is read from the SAME published POIRegistry entries the
##    pause map dots, the gate mesh and the claim trigger read, so a crossing
##    can never disagree with them.
##  * Free-roam only: nothing is emitted while RaceManager.is_race_active.
##
## The per-tick loop is a linear pass over the ~8 published speed traps, each
## with one squared XZ reject -- cheaper than the terrain push running beside it
## (the same argument as collectible_field.gd).

signal speed_trap_crossed(trap_id: String, speed_kmh: float, best_kmh: float, is_new_best: bool)

## Signal name, exposed so the HUD can connect without depending on the
## declaration's spelling.
const SIGNAL_NAME := &"speed_trap_crossed"
## Group the HUD resolves to find this node (the wiring direction is
## HUD -> crossing, and the HUD precedes the crossing in the open-world root,
## so the HUD's lookup is deferred one frame).
const GROUP_NAME := "speed_trap_crossing"
## Exit radius = enter radius * this. Firing once on entering and re-arming only
## well clear of the gate kills boundary jitter without a timer.
const HYSTERESIS := 1.6

@export var player_path: NodePath = NodePath("%PlayerCar")
## Mirror of the CollectibleField option shape: pause the world and the best map
## is written through to the slot (a disk write inside a physics tick would be
## unacceptable, and pausing already means "safe to persist").
@export var save_on_pause := true

## The published trap POIs this node watches (id / position / extra).
var _traps: Array[Dictionary] = []
var _records := SpeedTrapRecords.new()
## trap_id -> true while latched: it cannot re-fire until the player is clear.
var _inside: Dictionary = {}
var _player: Node3D
var _enabled := true

func _ready() -> void:
	add_to_group(GROUP_NAME)
	_collect_traps()
	_records.load_from_slot(SpeedTrapRecords.DEFAULT_SLOT)
	if save_on_pause and not GameState.game_paused.is_connected(_on_game_paused):
		GameState.game_paused.connect(_on_game_paused)

func _exit_tree() -> void:
	if GameState.game_paused.is_connected(_on_game_paused):
		GameState.game_paused.disconnect(_on_game_paused)

## Pulls the speed-trap half of the POI registry. The registry caches its
## one-shot corridor plan, so this costs nothing after the first access.
func _collect_traps() -> void:
	_traps = []
	for poi_id: String in POIRegistry.get_poi_ids():
		if Collectibles.kind_of_id(poi_id) != Collectibles.KIND_SPEED_TRAP:
			continue
		_traps.append(POIRegistry.get_poi(poi_id))
	_inside.clear()

func _physics_process(_delta: float) -> void:
	if _enabled:
		simulate_step()

## One crossing tick; returns how many traps were crossed (0 or more). Public so
## the headless gate can drive the shipped physics path without waiting on
## frames. Guarded so it is free with nothing to watch, no player, the trigger
## disabled, or a race in progress.
func simulate_step() -> int:
	if not _enabled or _traps.is_empty():
		return 0
	if RaceManager.is_race_active:
		return 0
	if _player == null:
		_player = get_node_or_null(player_path) as Node3D
		if _player == null:
			return 0
	var pos := _player.global_position
	var crossed := 0
	for poi: Dictionary in _traps:
		var trap_id := str(poi.get("id", ""))
		if trap_id.is_empty():
			continue
		var enter := Collectibles.claim_radius_of(poi)
		var target := poi.get("position", Vector3.ZERO) as Vector3
		var d := Collectibles.xz_distance(pos, target)
		if _inside.has(trap_id):
			if d > enter * HYSTERESIS:
				_inside.erase(trap_id)
			continue
		if d <= enter:
			_inside[trap_id] = true
			_emit_crossing(trap_id, _player_speed_kmh())
			crossed += 1
	return crossed

## Records the crossing (if it improved) and publishes it. The best published is
## always the merged/monotonic one, so the banner can never show a number lower
## than the stored best.
func _emit_crossing(trap_id: String, speed_kmh: float) -> void:
	var prev := _records.best_of(trap_id)
	var is_best := SpeedTrapRecords.is_new_best(prev, speed_kmh)
	if is_best:
		_records.record(trap_id, speed_kmh)
	speed_trap_crossed.emit(trap_id, speed_kmh, SpeedTrapRecords.merged_best(prev, speed_kmh), is_best)

## Car speed in km/h off the shipped VehiclePhysics property, with the
## get_drive_info() fallback the HUD cluster reads so a stub car in a test still
## reports a speed. The exact CollectibleField contract.
func _player_speed_kmh() -> float:
	if "current_speed_kmh" in _player:
		return float(_player.get("current_speed_kmh"))
	if _player.has_method("get_drive_info"):
		var info: Variant = _player.call("get_drive_info")
		if info is Dictionary and (info as Dictionary).has("speed_kmh"):
			return float((info as Dictionary)["speed_kmh"])
	return 0.0

func _on_game_paused() -> void:
	_records.save_to_slot(SpeedTrapRecords.DEFAULT_SLOT)

# ---------------------------------------------------------------------------
# Public surface: state queries and the tests' injection hooks.
# ---------------------------------------------------------------------------

func records() -> SpeedTrapRecords:
	return _records

func traps() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _traps:
		out.append(entry)
	return out

## Replaces the watched trap list (a test injects one stub trap), and re-arms
## every latch so the injected world starts from a clean crossing state.
func set_traps(list: Array[Dictionary]) -> void:
	_traps = []
	for entry in list:
		_traps.append(entry)
	_inside.clear()

## Event-mode parity: pause the trigger without unloading the world.
func set_enabled(value: bool) -> void:
	_enabled = value
	if not _enabled:
		set_physics_process(false)
		return
	set_physics_process(true)

func is_enabled() -> bool:
	return _enabled

## Re-arms one trap (or all of them with an empty id) so the suite can drive one
## crossing at a time without walking the car out of the radius.
func erase_latch(trap_id: String = "") -> void:
	if trap_id.is_empty():
		_inside.clear()
		return
	_inside.erase(trap_id)

func reset() -> void:
	_inside.clear()

## Forces the best map to disk (used on quit and by the headless gate).
func save_to_slot() -> bool:
	return _records.save_to_slot(SpeedTrapRecords.DEFAULT_SLOT)
