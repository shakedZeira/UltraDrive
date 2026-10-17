# tests/suites/test_hud_live_readouts.gd
extends GdUnitTestSuite

## HUD live-readout gate (docs/HANDOFF_2026-10-18_hud_fix_summary.md).
##
## Every cluster readout (speed, rpm, hp, Nm, coords) is fed from
## VehicleManager.get_player_car() each frame, so a LOST REGISTRATION is a
## fully-dead HUD with no recovery: "0 km/h, 0 rpm, -- hp, -- Nm, empty
## coords" (race_ui._process early-returns on a null car and refreshes the
## power/torque lines through PowerGauge's null-config placeholders).
##
## The defect was a lifecycle asymmetry in PlayerCarController: it registered
## once in _ready() (which runs only ONCE per node) but unregistered in
## _exit_tree() (which runs on EVERY tree exit). Any tree removal + re-add of
## the car — scene swap, pause-mode churn, respawn rebuild — therefore left
## player_car null forever while the car stayed alive. The fix registers in
## _enter_tree() (re-runs on every re-entry), refuses null registrations, and
## gives get_player_car() a live-tree scan of the `player_car` group as a
## self-healing fallback.
##
## These tests instantiate the REAL hud.tscn + player_car.tscn together and
## assert the readouts populate, that the remove/re-add cycle restores
## registration end-to-end (the exact pre-fix dead state), and that a null
## registration can never wipe a live car.

const HUD_SCENE := "res://scenes/ui/hud.tscn"
const CAR_SCENE := "res://scenes/vehicle/player_car.tscn"

var _managed: Array = []

func before_test() -> void:
	_managed.clear()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

func after_test() -> void:
	for node in _managed:
		if is_instance_valid(node):
			node.free()
	_managed.clear()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

func _spawn_car(holder: Node) -> VehiclePhysics:
	var car: VehiclePhysics = (load(CAR_SCENE) as PackedScene).instantiate() as VehiclePhysics
	holder.add_child(car)
	return car

func test_real_player_car_self_registers_on_tree_enter() -> void:
	var holder := Node3D.new()
	get_tree().root.add_child(holder)
	_managed.append(holder)
	var car := _spawn_car(holder)
	await get_tree().process_frame
	assert_that(VehicleManager.get_player_car()).is_same(car)
	assert_that(VehicleManager.all_cars.has(car)).is_true()
	# The CONTROLLER joins the group (the fallback resolves the body via
	# get_parent()), so assert membership on the controller, not the car.
	var controller := car.get_node_or_null("PlayerCarController")
	assert_that(controller).is_not_null()
	if controller != null:
		assert_that(controller.is_in_group(VehicleManager.PLAYER_CAR_GROUP)).is_true()

func test_hud_readouts_populate_with_the_real_player_car() -> void:
	var runner := scene_runner(HUD_SCENE)
	var holder := Node3D.new()
	get_tree().root.add_child(holder)
	_managed.append(holder)
	var car := _spawn_car(holder)
	await runner.simulate_frames(6)
	var scene := runner.scene()
	var power := scene.get_node("%PowerValue") as Label
	var torque := scene.get_node("%TorqueValue") as Label
	var coords := scene.get_node("%CoordsLabel") as Label
	assert_that(power).is_not_null()
	assert_that(torque).is_not_null()
	assert_that(coords).is_not_null()
	if power == null or torque == null or coords == null:
		return
	assert_that(VehicleManager.get_player_car()).is_same(car)
	# The live signature: no "-- hp" / "-- Nm" placeholders, and the coords
	# line is populated — the exact things the bug report said were dead.
	assert_that(power.text.contains("hp")).is_true()
	assert_that(power.text.contains("--")).is_false()
	assert_that(torque.text.contains("Nm")).is_true()
	assert_that(torque.text.contains("--")).is_false()
	assert_that(coords.text.contains("X:")).is_true()

func test_car_tree_readd_restores_registration() -> void:
	var holder := Node3D.new()
	get_tree().root.add_child(holder)
	_managed.append(holder)
	var car := _spawn_car(holder)
	await get_tree().process_frame
	assert_that(VehicleManager.get_player_car()).is_same(car)
	# The exact defect class: the car leaves the tree and comes back. Before
	# the fix the controller unregistered on exit but never re-registered on
	# re-entry, so player_car stayed null forever while the car was alive.
	holder.remove_child(car)
	await get_tree().process_frame
	assert_that(VehicleManager.get_player_car()).is_null()
	holder.add_child(car)
	await get_tree().process_frame
	assert_that(VehicleManager.get_player_car()).is_same(car)
	# all_cars must not accumulate duplicates across the re-add either.
	assert_that(VehicleManager.all_cars.has(car)).is_true()
	var count := 0
	for entry in VehicleManager.all_cars:
		if entry == car:
			count += 1
	assert_that(count).is_equal(1)

func test_hud_readouts_survive_car_tree_readd_end_to_end() -> void:
	var runner := scene_runner(HUD_SCENE)
	var holder := Node3D.new()
	get_tree().root.add_child(holder)
	_managed.append(holder)
	var car := _spawn_car(holder)
	await runner.simulate_frames(6)
	var scene := runner.scene()
	var power := scene.get_node("%PowerValue") as Label
	var torque := scene.get_node("%TorqueValue") as Label
	if power == null or torque == null:
		return
	assert_that(power.text.contains("--")).is_false()
	holder.remove_child(car)
	await runner.simulate_frames(4)
	# With the car genuinely out of the tree the HUD honestly reports the
	# dead placeholders (the null guard in race_ui._process is NOT weakened).
	assert_that(power.text).is_equal("-- hp")
	assert_that(torque.text).is_equal("-- Nm")
	# THE regression: when the car comes back, the readouts must RECOVER.
	# Pre-fix this stayed "-- hp" / "-- Nm" forever (registration was lost).
	holder.add_child(car)
	await runner.simulate_frames(6)
	assert_that(VehicleManager.get_player_car()).is_same(car)
	assert_that(power.text.contains("--")).is_false()
	assert_that(torque.text.contains("--")).is_false()

func test_null_registration_never_wipes_a_live_car() -> void:
	var holder := Node3D.new()
	get_tree().root.add_child(holder)
	_managed.append(holder)
	var car := _spawn_car(holder)
	await get_tree().process_frame
	assert_that(VehicleManager.get_player_car()).is_same(car)
	VehicleManager.register_player_car(null)
	assert_that(VehicleManager.get_player_car()).is_same(car)
	assert_that(VehicleManager.all_cars.has(car)).is_true()

func test_get_player_car_heals_a_lost_registration_from_the_group() -> void:
	var holder := Node3D.new()
	get_tree().root.add_child(holder)
	_managed.append(holder)
	var car := _spawn_car(holder)
	await get_tree().process_frame
	# Simulate a lost cached ref (the pre-fix permanent-null state) while the
	# controller is still live in the tree: get_player_car() must re-find and
	# re-register the car from the group instead of returning null forever.
	VehicleManager.player_car = null
	assert_that(VehicleManager.get_player_car()).is_same(car)

func test_freed_car_never_leaks_a_dangling_player_ref() -> void:
	var holder := Node3D.new()
	get_tree().root.add_child(holder)
	_managed.append(holder)
	var car := _spawn_car(holder)
	await get_tree().process_frame
	assert_that(VehicleManager.get_player_car()).is_same(car)
	car.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	# The controller unregisters on exit, and the group scan must not resurrect
	# a freed body: get_player_car() returns null, never a dangling ref.
	assert_that(VehicleManager.get_player_car()).is_null()
