# tests/suites/test_ground_latch.gd
extends GdUnitTestSuite

## Ground-release latch: the player car spawns frozen above the ground so the
## open world can bake terrain under it without a void fall, then releases
## itself once ground below is physically proven - including on paths that
## never queue a race (free roam, Continue), where nothing calls
## RaceManager.start_race()'s release_ground_lock(). Regression for a bug where
## the HUD read 0 km/h / idle RPM while "driving": the latch only released on
## the queued-race path.

const TEST_SCENE := "res://scenes/test/test_vehicle_physics.tscn"

var _managed_nodes: Array = []

func before_test() -> void:
	_managed_nodes.clear()

func after_test() -> void:
	for node in _managed_nodes:
		if is_instance_valid(node):
			node.free()
	_managed_nodes.clear()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

func test_car_spawned_above_ground_releases_without_race() -> void:
	var runner := scene_runner(TEST_SCENE)
	await runner.simulate_frames(5)
	var car := runner.scene().get_node("PlayerCar") as VehiclePhysics
	assert_that(car).is_not_null()
	if car == null:
		return
	assert_that(car.freeze).is_false()
	assert_that(car._awaiting_ground).is_false()
	var spawn_y := car.global_position.y
	await runner.simulate_frames(60)
	assert_that(car.global_position.y).is_less(spawn_y)
	assert_that(car.global_position.y).is_greater(-1.0)
	assert_that(car.global_position.y).is_less(1.5)
	car.set_input_override(Vector2(0.0, 1.0))
	await runner.simulate_frames(240)
	var info := car.get_drive_info()
	assert_that(float(info["speed_kmh"])).is_greater(8.0)
	assert_that(float(info["rpm"])).is_greater(car.config.idle_rpm)

func test_car_without_ground_from_spawn_stays_frozen() -> void:
	var holder := Node3D.new()
	get_tree().root.add_child(holder)
	_managed_nodes.append(holder)
	var car: VehiclePhysics = (load("res://scenes/vehicle/player_car.tscn") as PackedScene).instantiate() as VehiclePhysics
	holder.add_child(car)
	car.global_position = Vector3(0.0, 2.0, 0.0)
	for i in range(60):
		await get_tree().physics_frame
	assert_that(car.freeze).is_true()
	assert_that(car._awaiting_ground).is_true()
	assert_that(car.global_position.y).is_greater(1.0)