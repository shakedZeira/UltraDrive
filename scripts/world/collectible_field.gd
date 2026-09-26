# scripts/world/collectible_field.gd
class_name CollectibleField
extends Node

## Open-world runtime trigger for the road-anchored collectibles placed by
## Collectibles.place_data() and merged into POIRegistry (AAA-16).
##
## Contract:
##  * ONE node per world, parented to the open-world root only, so the trigger is
##    literally absent off-world (circuits) and never polls there.
##  * The claim rule is Collectibles.can_claim(), shared with the headless gate:
##    in-radius, and ABOVE the speed target for a speed trap. A trap crossed
##    under speed pays nothing.
##  * Payout goes through the shipped economy (Money.wallet_add +
##    CareerProfile.grant_xp) and the monotonic claim ledger, so a collectible
##    pays exactly once per save no matter how many times it is re-entered, and a
##    pause/session quit persists the claim set.
##
## The per-tick loop is a linear pass over the UNCLAIMED entries only (28 ids
## worst case, and it shrinks as the player collects), each with a squared XZ
## reject, so it is cheaper than the terrain streaming push that runs beside it.

signal collectible_claimed(collectible_id: String, reward: int)

## Group the pause map / minimap resolve to read claimed state from.
const GROUP_NAME := "collectible_field"

@export var player_path: NodePath = NodePath("%PlayerCar")
@export var save_slot: int = Collectibles.DEFAULT_SLOT
## Mirrors the WorldDiscovery contract: pause the world (game_paused) and the
## claim set is written through to the slot.
@export var save_on_pause := true

var _ledger: Collectibles = Collectibles.new()
## { collectible_id -> poi } as published by POIRegistry, i.e. the same entries
## the map dots are drawn from, so dots and triggers can never disagree.
var _placed: Dictionary = {}
## Unclaimed entries only; each successful claim removes its entry.
var _pending: Array[Dictionary] = []
var _player: Node3D
var _enabled := true

func _ready() -> void:
	add_to_group(GROUP_NAME)
	_collect_placed()
	_ledger.load_from_slot(save_slot)
	if save_on_pause and not GameState.game_paused.is_connected(_on_game_paused):
		GameState.game_paused.connect(_on_game_paused)

func _exit_tree() -> void:
	if GameState.game_paused.is_connected(_on_game_paused):
		GameState.game_paused.disconnect(_on_game_paused)

## Pull the collectible half of the POI registry (the base landmarks and the
## event markers are filtered out by their ids). The registry caches its one-shot
## plan, so this costs nothing after the first access.
func _collect_placed() -> void:
	_placed.clear()
	_pending.clear()
	for poi_id: String in POIRegistry.get_poi_ids():
		if not Collectibles.is_collectible_id(poi_id):
			continue
		_placed[poi_id] = POIRegistry.get_poi(poi_id)
	_pending = _unclaimed_entries()

func _unclaimed_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for poi_id: String in _placed.keys():
		if _ledger.is_claimed(poi_id):
			continue
		out.append(_placed[poi_id])
	return out

func _physics_process(_delta: float) -> void:
	if not _enabled:
		return
	simulate_step()

## One trigger tick; returns how many collectibles were claimed (0 or 1 in
## practice). Public so the headless gate can drive the SHIPPED physics path
## without waiting on frames. Guarded so it is free when there is nothing to
## collect, no player, or the trigger is disabled.
func simulate_step() -> int:
	if not _enabled or _pending.is_empty():
		return 0
	if _player == null:
		_player = get_node_or_null(player_path) as Node3D
		if _player == null:
			return 0
	return claim_at(_player.global_position, _player_speed_kmh()).size()

## THE single rule path: claims and PAYS every pending collectible the player at
## `position` travelling `speed_kmh` satisfies, and returns the ids paid in this
## pass. The physics tick and the headless gate both go through here, so there is
## only ever one place where a collectible can pay out.
##
## Reverse iteration so a claim can drop its own entry from _pending mid-pass.
func claim_at(position: Vector3, speed_kmh: float) -> Array[String]:
	var paid: Array[String] = []
	var i := _pending.size() - 1
	while i >= 0:
		var poi: Dictionary = _pending[i]
		if Collectibles.can_claim(poi, position, speed_kmh) and _award(poi):
			paid.append(str(poi["id"]))
			_pending.remove_at(i)
		i -= 1
	paid.reverse()
	return paid

## Registers the claim, then pays it. The claim is recorded FIRST so a re-entry
## in the same tick (or a second overlapping trigger) can never pay twice.
func _award(poi: Dictionary) -> bool:
	var collectible_id := str(poi.get("id", ""))
	var reward := _ledger.claim(_placed, collectible_id)
	if reward <= 0:
		return false
	Money.wallet_add(reward, save_slot)
	CareerProfile.grant_xp(CareerProfile.COLLECTIBLE_XP, save_slot)
	_ledger.save_to_slot(save_slot)
	collectible_claimed.emit(collectible_id, reward)
	return true

## Car speed in km/h off the shipped VehiclePhysics property, with the
## get_drive_info() fallback the HUD cluster reads so a stub car in a test still
## reports a speed.
func _player_speed_kmh() -> float:
	if "current_speed_kmh" in _player:
		return float(_player.get("current_speed_kmh"))
	if _player.has_method("get_drive_info"):
		var info: Variant = _player.call("get_drive_info")
		if info is Dictionary and (info as Dictionary).has("speed_kmh"):
			return float((info as Dictionary)["speed_kmh"])
	return 0.0

func _on_game_paused() -> void:
	save_to_slot()

# ---------------------------------------------------------------------------
# Public surface: state queries (pause map / minimap) and tests.
# ---------------------------------------------------------------------------

func placed() -> Dictionary:
	return _placed.duplicate()

func is_claimed(collectible_id: String) -> bool:
	return _ledger.is_claimed(collectible_id)

func claimed_ids() -> Array[String]:
	return _ledger.claimed_ids()

func completion() -> float:
	return _ledger.completion(_placed)

## True when this world has collectibles to trigger at all (an empty or
## fully-claimed world is loop-free).
func has_pending() -> bool:
	return not _pending.is_empty()

## Event-mode parity: pause the trigger without unloading the world.
func set_enabled(value: bool) -> void:
	_enabled = value
	if not _enabled:
		set_physics_process(false)
		return
	set_physics_process(true)

func is_enabled() -> bool:
	return _enabled

## Forces the claim set to disk (used on quit and by the headless gate).
func save_to_slot() -> bool:
	return _ledger.save_to_slot(save_slot)
