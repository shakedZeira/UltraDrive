extends GdUnitTestSuite
## MANUAL respawn is player-only.
##
## Bug repro (plan docs/plans/fix_respawn_reverse_plan.md Bug 1): the old reset
## block called `respawn_at(_spawn_point)` for ANY car when `InputManager.
## is_reset()` fired, so pressing reset in multiplayer/AI races teleported every
## car on track. The fix routes the input edge through two seams in
## `vehicle_physics.gd`:
##   - `can_manual_respawn()` - asks "may THIS body take the manual respawn?"
##     true for a car with no player, true only for the registered player car,
##     and false for anything with a controller `input_override` (rival/AI),
##   - `try_manual_respawn(pressed, locked)` - false unless the press edge is
##     live, the car is not in a scripted reset, controls are not locked, and
##     `can_manual_respawn()` says yes; only then calls `respawn_at()`.
##
## Invariant that must hold for EVERY car regardless of the gate: the automatic
## fall safety (`global_position.y < -20.0`) still rescues an unmanned rival -
## test_fall_safety_still_respawns_unmanned_rival.
##
## The controllerless rival below is exactly the AI car of a multi-car race: a
## `player_car.tscn` body with its `PlayerCarController` child stripped BEFORE
## `add_child` so its `_ready` never runs and it never self-registers as player.
## `VehiclePhysics._ready` captures `_spawn_point` from `global_position`, so the
## rival's spawn position is set before it enters the tree.

const TEST_SCENE := "res://scenes/test/test_vehicle_physics.tscn"
const RIVAL_SCENE := "res://scenes/vehicle/player_car.tscn"
## Ground plane top sits at y=0 (test_ground.gd), so all spawns/teleports here
## are at least 1.5 m above it and no wheel touches before an explicit lift.
const RIVAL_SPAWN := Vector3(30.0, 2.0, 0.0)
## Teleports are far enough from BOTH spawn points (player (0,2,0) ~28 m away,
## rival (30,2,0) ~54 m away) that "did not move" is a discriminative assert -
## a buggy respawn would land within ~2 m of a spawn point.
const PLAYER_TELEPORT := Vector3(-20.0, 3.0, -20.0)
const RIVAL_TELEPORT := Vector3(-20.0, 3.0, 20.0)

var _managed_nodes: Array = []


func before_test() -> void:
	_managed_nodes.clear()
	# These tests are about the MANUAL respawn gate; a live race would hold
	# `controls_locked` (RaceManager.lock_controls) and mask it. Not a seam.
	RaceManager.is_race_active = false


func after_test() -> void:
	for node in _managed_nodes:
		if is_instance_valid(node):
			node.free()
	_managed_nodes.clear()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()
	# A pressed key must not leak a just-pressed edge into the next test.
	Input.action_release("reset_car")


## Await N PHYSICS ticks. The `physics_frame` signal is emitted before the nodes'
## `_physics_process`, so awaiting it guarantees the vehicle scripts saw the
## previous frame's input - `simulate_frames()` only awaits process_frame and
## cannot promise that.
func _physics_ticks(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


## Test scene + registered player, with wheels settled on the test floor.
func _spawn_settled_player() -> VehiclePhysics:
	var runner := scene_runner(TEST_SCENE)
	auto_free(runner)
	await _physics_ticks(10)
	var car := runner.scene().get_node("PlayerCar") as VehiclePhysics
	assert_that(car).is_not_null()
	if car == null:
		return null
	VehicleManager.register_player_car(car)
	return car


## Controllerless rival spawned at `spawn_pos` (its `_spawn_point`).
func _make_rival(spawn_pos: Vector3) -> VehiclePhysics:
	var holder := Node3D.new()
	holder.name = "RivalHolder"
	add_child(holder)
	_managed_nodes.append(holder)
	var rival := (load(RIVAL_SCENE) as PackedScene).instantiate() as VehiclePhysics
	assert_that(rival).is_not_null()
	if rival == null:
		return null
	var ctrl := rival.get_node_or_null("PlayerCarController")
	if ctrl != null:
		ctrl.free()  # before add_child so the rival never self-registers as player
	# Position BEFORE add_child: VehiclePhysics._ready captures _spawn_point.
	rival.position = spawn_pos
	holder.add_child(rival)
	_managed_nodes.append(rival)
	# Let the ground-exists ray clear so the body is fully live (the rival's
	# `_awaiting_ground` latch releases on its first physics tick).
	await _physics_ticks(2)
	return rival


func test_manual_respawn_respawns_the_player() -> void:
	var car := await _spawn_settled_player()
	if car == null:
		return
	car.global_position = PLAYER_TELEPORT
	var spawned: Vector3 = car._spawn_point + Vector3.UP
	# A direct `global_position` write on a RigidBody3D only reaches the physics
	# server on the NEXT step, so flush it before respawning - otherwise the
	# deferred teleport lands after `respawn_at()`'s server-side transform write
	# and silently undoes the respawn (the sibling tests await ticks after every
	# teleport for the same reason).
	await _physics_ticks(2)
	# `respawn_at()` zeroes both velocities and the drivetrain synchronously.
	var did: bool = car.try_manual_respawn(true, false)
	assert_that(did).is_equal(true)
	assert_that(car.linear_velocity).is_equal(Vector3.ZERO)
	assert_that(car.angular_velocity).is_equal(Vector3.ZERO)
	# Drivetrain.reset() parks in top gear with no torque.
	assert_that(car._drivetrain.current_gear).is_equal(1)
	assert_that(car._drivetrain.drive_torque).is_equal(0.0)
	assert_that(car._last_valid_position).is_equal_approx(spawned, Vector3(0.01, 0.01, 0.01))
	await _physics_ticks(2)
	assert_that(car.global_position.distance_to(spawned)).is_less(2.0)


func test_rival_with_input_override_is_not_manually_respawned() -> void:
	var car := await _spawn_settled_player()
	if car == null:
		return
	var rival := await _make_rival(RIVAL_SPAWN)
	if rival == null:
		return
	rival.input_override = Vector2(0.0, 0.5)  # AI/controller-driven car
	car.global_position = PLAYER_TELEPORT
	rival.global_position = RIVAL_TELEPORT
	assert_that(rival.try_manual_respawn(true, false)).is_equal(false)
	await _physics_ticks(3)
	# Still parked where we put it - ~54 m from the rival's own spawn point
	# (a buggy respawn would put it within ~2 m of spawn + UP). It may have
	# settled a centimetre or two onto the floor; the spawn distance is what
	# makes this discriminative.
	assert_that(rival.global_position.distance_to(rival._spawn_point)).is_greater(40.0)


func test_rival_without_override_is_still_blocked_by_identity() -> void:
	var car := await _spawn_settled_player()
	if car == null:
		return
	var rival := await _make_rival(RIVAL_SPAWN)
	if rival == null:
		return
	car.global_position = PLAYER_TELEPORT
	rival.global_position = RIVAL_TELEPORT
	# Override ZERO, but a player IS registered: the identity gate alone
	# (`player == self`) still keeps the respawn off a rival body.
	var did: bool = rival.try_manual_respawn(true, false)
	assert_that(did).is_equal(false)
	await _physics_ticks(3)
	assert_that(rival.global_position.distance_to(rival._spawn_point)).is_greater(40.0)


func test_player_with_input_override_is_not_manually_respawned() -> void:
	var car := await _spawn_settled_player()
	if car == null:
		return
	car.input_override = Vector2(0.0, 0.8)  # e.g. a scripted sequence took over
	car.global_position = PLAYER_TELEPORT
	assert_that(car.try_manual_respawn(true, false)).is_equal(false)
	await _physics_ticks(3)
	assert_that(car.global_position.distance_to(PLAYER_TELEPORT)).is_less(2.0)


func test_locked_controls_block_manual_respawn() -> void:
	var car := await _spawn_settled_player()
	if car == null:
		return
	car.global_position = PLAYER_TELEPORT
	assert_that(car.try_manual_respawn(true, true)).is_equal(false)
	await _physics_ticks(3)
	assert_that(car.global_position.distance_to(PLAYER_TELEPORT)).is_less(2.0)


func test_no_press_edge_means_no_manual_respawn() -> void:
	var car := await _spawn_settled_player()
	if car == null:
		return
	car.global_position = PLAYER_TELEPORT
	assert_that(car.try_manual_respawn(false, false)).is_equal(false)
	await _physics_ticks(3)
	assert_that(car.global_position.distance_to(PLAYER_TELEPORT)).is_less(2.0)


func test_registered_player_car_is_respawned_when_no_player_exists() -> void:
	var car := await _spawn_settled_player()
	if car == null:
		return
	VehicleManager.player_car = null  # pre-fix condition: no one registered
	assert_that(car.can_manual_respawn()).is_equal(true)
	car.global_position = PLAYER_TELEPORT
	var spawned: Vector3 = car._spawn_point + Vector3.UP
	assert_that(car.try_manual_respawn(true, false)).is_equal(true)
	assert_that(car._last_valid_position).is_equal_approx(spawned, Vector3(0.01, 0.01, 0.01))
	# With a player registered the identity gate closes on the rival again.
	var rival := await _make_rival(RIVAL_SPAWN)
	if rival == null:
		return
	VehicleManager.register_player_car(car)
	rival.input_override = Vector2(0.0, 0.5)
	assert_that(rival.can_manual_respawn()).is_equal(false)
	assert_that(rival.try_manual_respawn(true, false)).is_equal(false)


func test_reset_input_edge_respawns_only_the_player_car() -> void:
	var car := await _spawn_settled_player()
	if car == null:
		return
	var rival := await _make_rival(RIVAL_SPAWN)
	if rival == null:
		return
	rival.input_override = Vector2(0.0, 0.05)
	VehicleManager.register_player_car(car)  # after the rival: its _ready must not steal the role
	car.global_position = PLAYER_TELEPORT
	rival.global_position = RIVAL_TELEPORT
	# End-to-end through the real reset block: the press edge must survive into
	# a physics tick (VehiclePhysics reads `InputManager.is_reset()` there).
	Input.action_press("reset_car")
	assert_that(Input.is_action_pressed("reset_car")).is_equal(true)
	await _physics_ticks(2)
	Input.action_release("reset_car")
	await _physics_ticks(2)
	assert_that(car.global_position.distance_to(car._spawn_point + Vector3.UP)).is_less(2.0)
	# The rival stayed where we teleported it - far from its own spawn point.
	assert_that(rival.global_position.distance_to(rival._spawn_point)).is_greater(40.0)


func test_fall_safety_still_respawns_unmanned_rival() -> void:
	var car := await _spawn_settled_player()
	if car == null:
		return
	var rival := await _make_rival(RIVAL_SPAWN)
	if rival == null:
		return
	# The `y < -20` rescue is input-independent and must keep working for a car
	# with no player and no override. Drop it below the threshold; the rival's
	# `_awaiting_ground` latch already released during the fixture ticks.
	rival.global_position = RIVAL_TELEPORT
	rival.global_position.y = -30.0
	await _physics_ticks(5)
	# Rescued back above the void ...
	assert_that(rival.global_position.y).is_greater(-5.0)
	# ... and dropped back at ITS OWN spawn point (~1 m away, respawn_at(spawn)).
	assert_that(rival.global_position.distance_to(rival._spawn_point)).is_less(3.0)
