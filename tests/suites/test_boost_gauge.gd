# tests/suites/test_boost_gauge.gd
extends GdUnitTestSuite

## Boost gauge chain (Forza/GT style): auto-hidden for NA cars (max_bar <= 0),
## shows and eases (never snaps) toward the target for a turbo car, converges
## dt-robustly within ~200 frames, clamps out-of-range values, and lives at
## Root/Cluster/BoostGauge in the HUD scene.

const HUD_SCENE := "res://scenes/ui/hud.tscn"

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

func _gauge_of(runner: GdUnitSceneRunner) -> BoostGauge:
	var gauge := runner.scene().get_node("Root/Cluster/BoostGauge") as BoostGauge
	return gauge

func test_boost_gauge_resolves_hidden_and_stays_hidden_for_na() -> void:
	var runner := scene_runner(HUD_SCENE)
	await runner.simulate_frames(2)
	var gauge := _gauge_of(runner)
	assert_that(gauge).is_not_null()
	if gauge == null:
		return
	assert_that(gauge.visible).is_false()
	gauge.set_boost_bar(0.5, 0.0)
	assert_that(gauge.visible).is_false()
	assert_that(gauge._target_bar).is_equal(0.0)
	assert_that(gauge._display_bar).is_equal(0.0)

func test_boost_gauge_shows_and_eases_not_snaps_on_turbo_boost() -> void:
	var runner := scene_runner(HUD_SCENE)
	await runner.simulate_frames(2)
	var gauge := _gauge_of(runner)
	assert_that(gauge).is_not_null()
	if gauge == null:
		return
	# No player car: RaceUI's _process no-car branch drives the gauge to 0 every
	# frame. Silence it so this test observes the gauge's own easing, not the HUD
	# override (the gauge Control still processes itself).
	runner.scene().set_process(false)
	gauge.set_boost_bar(1.8, 1.8)
	assert_that(gauge.visible).is_true()
	assert_that(gauge._target_bar).is_equal_approx(1.8, 0.001)
	await runner.simulate_frames(1)
	assert_that(gauge._display_bar).is_greater(0.0)
	assert_that(gauge._display_bar).is_less(1.8)
	await runner.simulate_frames(200)
	assert_that(gauge._display_bar).is_equal_approx(1.8, 0.05)

func test_boost_gauge_clamps_out_of_range_values() -> void:
	var runner := scene_runner(HUD_SCENE)
	await runner.simulate_frames(2)
	var gauge := _gauge_of(runner)
	assert_that(gauge).is_not_null()
	if gauge == null:
		return
	gauge.set_boost_bar(99.0, 1.8)
	assert_that(gauge._target_bar).is_equal_approx(1.8, 0.001)
	gauge.set_boost_bar(-5.0, 1.8)
	assert_that(gauge._target_bar).is_equal_approx(BoostGauge.BAR_MIN, 0.001)

func test_boost_gauge_is_unique_node_under_cluster() -> void:
	var runner := scene_runner(HUD_SCENE)
	await runner.simulate_frames(2)
	var scene := runner.scene()
	var cluster := scene.get_node("Root/Cluster")
	assert_that(cluster.has_node("%BoostGauge")).is_true()
	var gauge := cluster.get_node("%BoostGauge") as BoostGauge
	assert_that(gauge).is_not_null()
	if gauge == null:
		return
	assert_that(gauge.size.x).is_greater(0.0)
