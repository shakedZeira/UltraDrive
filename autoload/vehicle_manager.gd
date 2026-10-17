extends Node

## Tracks the active player car and provides spawning utilities.

signal car_registered(car: VehiclePhysics)
signal car_removed(car: VehiclePhysics)

## The group PlayerCarController joins on _enter_tree so a lost registration
## can be re-found (see get_player_car()).
const PLAYER_CAR_GROUP := "player_car"

var player_car: VehiclePhysics = null
var all_cars: Array[VehiclePhysics] = []

func register_player_car(car: VehiclePhysics) -> void:
	# Null registrations are ignored: a controller that merely left the tree
	# (scene swap, respawn rebuild, pause-mode churn) must never wipe a
	# still-alive player car. That gap left every HUD readout dead with no
	# recovery path (docs/HANDOFF_2026-10-18_hud_fix_summary.md).
	if car == null:
		return
	player_car = car
	if car not in all_cars:
		all_cars.append(car)
	car_registered.emit(car)

func register_ai_car(car: VehiclePhysics) -> void:
	if car not in all_cars:
		all_cars.append(car)

func remove_car(car: VehiclePhysics) -> void:
	all_cars.erase(car)
	if car == player_car:
		player_car = null
	car_removed.emit(car)

func get_player_car() -> VehiclePhysics:
	if is_instance_valid(player_car):
		return player_car
	# Self-heal the registration gap: PlayerCarController unregisters in
	# _exit_tree(), so a tree removal + re-add of the car used to leave
	# player_car null FOREVER while the car stayed alive — the HUD went fully
	# dead (0 km/h, 0 rpm, -- hp, -- Nm, empty coords) with no recovery path.
	# Re-find the live controller in the tree and re-register it on demand.
	if not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group(PLAYER_CAR_GROUP):
		if not node.is_inside_tree():
			continue
		var physics := node.get_parent() as VehiclePhysics
		if physics != null and physics.is_inside_tree():
			register_player_car(physics)
			return physics
	return null

func get_all_cars() -> Array[VehiclePhysics]:
	return all_cars
