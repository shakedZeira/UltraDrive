# tests/suites/test_hud_gauge.gd
extends GdUnitTestSuite

## Speedometer cluster chain: the tach needle must actually move (and repaint)
## toward the engine RPM target instead of snapping, the speed readout must
## reflect a moving body, and the player car must unregister itself from
## VehicleManager when freed so a later race can never drive a stale ref.
## Regression for the frozen-needle defect: set_rpm() used to write BOTH
## _target_rpm and _display_rpm and _process() then mirrored display=target, so
## `prev == _display_rpm` every frame and queue_redraw() never fired below
## redline - the gauge froze while the numerals updated.

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

func test_tachometer_needle_interpolates_and_converges() -> void:
	var runner := scene_runner(HUD_SCENE)
	await runner.simulate_frames(2)
	var cluster := runner.scene().get_node("Root/Cluster") as Tachometer
	assert_that(cluster).is_not_null()
	if cluster == null:
		return
	cluster.set_engine_range(800.0, 7000.0)
	cluster.set_rpm(1000.0)
	assert_that(cluster._target_rpm).is_equal(1000.0)
	await runner.simulate_frames(1)
	# After one tick the needle must have moved past idle but NOT snapped all the
	# way to 1000: proves the display chases the target (and repaints along the
	# way) instead of teleporting then freezing.
	assert_that(cluster._display_rpm).is_greater(800.0)
	assert_that(cluster._display_rpm).is_less(1000.0)
	await runner.simulate_frames(200)
	assert_that(cluster._display_rpm).is_equal_approx(1000.0, 0.5)

func test_tachometer_needle_tracks_dropping_rpm() -> void:
	var runner := scene_runner(HUD_SCENE)
	await runner.simulate_frames(2)
	var cluster := runner.scene().get_node("Root/Cluster") as Tachometer
	if cluster == null:
		return
	cluster.set_engine_range(800.0, 7000.0)
	cluster.set_rpm(6000.0)
	await runner.simulate_frames(30)
	# The needle eased toward 6000 but has not teleported past the easing
	# envelope. The exact position after 30 frames depends on the runner's
	# per-frame delta (headless ticks at ~6-7ms, not 1/60), so assert the
	# dt-robust bounds (strictly above idle, at-or-below target) instead of a
	# hardcoded rpm like 5500 — that was the pre-existing flake.
	assert_that(cluster._display_rpm).is_greater(800.0)
	assert_that(cluster._display_rpm).is_less_equal(6000.0)
	cluster.set_rpm(800.0)
	# Wait well past the ~1s easing envelope so the assert is independent of the
	# exact per-frame delta the headless runner hands _process().
	await runner.simulate_frames(240)
	assert_that(cluster._display_rpm).is_less(900.0)

func test_speed_readout_text_updates_from_kmh() -> void:
	var runner := scene_runner(HUD_SCENE)
	await runner.simulate_frames(1)
	var cluster := runner.scene().get_node("Root/Cluster") as Tachometer
	if cluster == null:
		return
	cluster.set_speed_kmh(88.0)
	var speed_label := runner.scene().get_node("Root/Cluster/SpeedValue") as Label
	assert_that(speed_label.text).is_equal("88")

func test_drive_info_speed_reflects_moving_body() -> void:
	var holder := Node3D.new()
	get_tree().root.add_child(holder)
	_managed.append(holder)
	var car: VehiclePhysics = (load(CAR_SCENE) as PackedScene).instantiate() as VehiclePhysics
	holder.add_child(car)
	car.global_position = Vector3(0.0, 5.0, 0.0)
	assert_that(car.freeze).is_true()
	car.release_ground_lock()
	assert_that(car.freeze).is_false()
	car.linear_velocity = Vector3(0.0, 0.0, -10.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var info := car.get_drive_info()
	assert_that(float(info["speed_kmh"])).is_greater(30.0)
	assert_that(float(info["speed_kmh"])).is_less(42.0)

func test_player_car_unregisters_when_freed() -> void:
	var holder := Node3D.new()
	get_tree().root.add_child(holder)
	_managed.append(holder)
	var car: VehiclePhysics = (load(CAR_SCENE) as PackedScene).instantiate() as VehiclePhysics
	holder.add_child(car)
	await get_tree().process_frame
	assert_that(VehicleManager.get_player_car()).is_equal(car)
	assert_that(VehicleManager.all_cars.size()).is_equal(1)
	car.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_that(VehicleManager.get_player_car()).is_null()
	assert_that(VehicleManager.all_cars.is_empty()).is_true()