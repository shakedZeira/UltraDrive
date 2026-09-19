# tests/suites/test_race_results.gd
extends GdUnitTestSuite

## S2 gate: the race results screen. On finish the overlay is fed from the real
## standings + player per-lap data (position, total time, best lap), the win
## state (gold "1ST PLACE!" + confetti) lights only for position 1, Next Race
## re-arms the start ceremony, Return to Free Roam launches the open-world
## scene, the position->points table is exported for item 11, and the confetti
## burst steps to completion without a scene. Leak discipline mirrors
## test_race_loop.gd.

const FREE_ROAM_SCENE := "res://scenes/world/open_world_root.tscn"

var _managed_cars: Array = []

func before_test() -> void:
	_managed_cars.clear()

func after_test() -> void:
	for car in _managed_cars:
		if is_instance_valid(car):
			car.free()
	_managed_cars.clear()
	for child in RaceManager.get_children():
		if child is LapCounter:
			child.free()
	RaceManager.is_race_active = false
	RaceManager._participants = []
	RaceManager._lap_counters = {}
	RaceManager._checkpoints_dirty = true
	RaceManager._countdown = RaceCountdown.new()
	RaceManager.consume_pending_race()
	for child in get_children():
		if child is Checkpoint:
			child.free()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

func _new_stub_car() -> VehiclePhysics:
	var car := VehiclePhysics.new()
	_managed_cars.append(car)
	return car

func _add_checkpoint(index: int) -> Checkpoint:
	var cp := Checkpoint.new()
	cp.index = index
	add_child(cp)
	return cp

func _parse_mm_ss(text: String) -> float:
	var tokens := text.split(" ", false)
	if tokens.is_empty():
		return -1.0
	var time_token: String = tokens[tokens.size() - 1]
	var parts := time_token.split(":", false)
	if parts.size() != 2:
		return -1.0
	return float(parts[0]) * 60.0 + float(parts[1])

func test_results_overlay_hidden_before_finish() -> void:
	var runner := scene_runner("res://scenes/ui/hud.tscn")
	await runner.simulate_frames(1)
	var overlay := runner.scene().get_node("%ResultsOverlay") as Control
	assert_that(overlay.visible).is_false()

func test_win_results_overlay_matches_standings_total_and_best_lap() -> void:
	var player := _new_stub_car()
	VehicleManager.register_player_car(player)
	var cp := _add_checkpoint(0)
	RaceManager.start_race([player], 1)
	var runner := scene_runner("res://scenes/ui/hud.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as RaceUI
	var counter: LapCounter = RaceManager.get_lap_counter(player)
	counter.update(player, cp)
	var standings := RaceManager.get_standings()
	RaceManager.finish_race()

	var overlay := scene.get_node("%ResultsOverlay") as Control
	assert_that(overlay.visible).is_true()
	assert_that(standings[0]).is_equal(player)
	assert_that((scene.get_node("%ResultsPosition") as Label).text).is_equal("P1")
	assert_that((scene.get_node("%ResultsTitle") as Label).text).is_equal("1ST PLACE!")
	var total := counter.get_total_time()
	var total_label := scene.get_node("%ResultsTotal") as Label
	assert_that(_parse_mm_ss(total_label.text)).is_equal_approx(total, 0.05)
	var best_parsed := _parse_mm_ss((scene.get_node("%ResultsBestLap") as Label).text)
	assert_that(best_parsed).is_greater(0.0)
	var best_lap: float = scene.get("_best_lap")
	assert_that(best_lap).is_greater(0.0)
	assert_that((scene.get_node("%ResultsConfetti") as ResultsConfetti).finished).is_false()

func test_second_place_is_flat_with_no_celebration() -> void:
	var player := _new_stub_car()
	var rival := _new_stub_car()
	VehicleManager.register_player_car(player)
	var cp0 := _add_checkpoint(0)
	var cp1 := _add_checkpoint(1)
	RaceManager.start_race([player, rival], 1)
	var runner := scene_runner("res://scenes/ui/hud.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as RaceUI
	var rival_counter: LapCounter = RaceManager.get_lap_counter(rival)
	rival_counter.update(rival, cp0)
	rival_counter.update(rival, cp1)
	RaceManager.finish_race()

	var standings := RaceManager.get_standings()
	var overlay := scene.get_node("%ResultsOverlay") as Control
	assert_that(overlay.visible).is_true()
	assert_that(standings[0]).is_equal(rival)
	assert_that((scene.get_node("%ResultsPosition") as Label).text).is_equal("P2")
	assert_that((scene.get_node("%ResultsTitle") as Label).text).is_equal("RACE FINISH")
	assert_that((scene.get_node("%ResultsConfetti") as ResultsConfetti).finished).is_true()

func test_show_result_renders_position_total_and_extra_rows() -> void:
	var runner := scene_runner("res://scenes/ui/hud.tscn")
	await runner.simulate_frames(1)
	var scene := runner.scene() as RaceUI
	scene.show_result(3, 93.5, 92.1, [{"label": "TOP SPEED", "value": "212 km/h"}])
	var overlay := scene.get_node("%ResultsOverlay") as Control
	assert_that(overlay.visible).is_true()
	assert_that((scene.get_node("%ResultsPosition") as Label).text).is_equal("P3")
	assert_that((scene.get_node("%ResultsTitle") as Label).text).is_equal("RACE FINISH")
	assert_that((scene.get_node("%ResultsTotal") as Label).text).is_equal("TOTAL TIME  %s" % scene._format_time(93.5))
	assert_that((scene.get_node("%ResultsPoints") as Label).text).contains("500")
	var stats := scene.get_node("%ResultsStatsRows") as VBoxContainer
	assert_that(stats.get_child_count()).is_equal(1)
	var row := stats.get_child(0) as Label
	assert_that(row.text).contains("TOP SPEED")
	assert_that(row.text).contains("212 km/h")
	assert_that((scene.get_node("%ResultsConfetti") as ResultsConfetti).finished).is_true()

func test_position_points_table_is_exported() -> void:
	assert_that(RaceUI.points_for_position(1)).is_equal(1000)
	assert_that(RaceUI.points_for_position(2)).is_equal(750)
	assert_that(RaceUI.points_for_position(3)).is_equal(500)
	assert_that(RaceUI.points_for_position(4)).is_equal(250)
	assert_that(RaceUI.points_for_position(5)).is_equal(0)
	assert_that(RaceUI.points_for_position(0)).is_equal(0)

func test_confetti_burst_completes_without_scene() -> void:
	var confetti := ResultsConfetti.new()
	confetti.burst()
	assert_that(confetti.finished).is_false()
	var elapsed := 0.0
	while not confetti.finished and elapsed < 10.0:
		confetti.advance(0.5)
		elapsed += 0.5
	assert_that(confetti.finished).is_true()
	confetti.advance(1.0)
	assert_that(confetti.finished).is_true()
	confetti.free()

func test_next_race_button_rearms_the_ceremony() -> void:
	var player := _new_stub_car()
	VehicleManager.register_player_car(player)
	RaceManager.start_race([player], 3)
	var runner := scene_runner("res://scenes/ui/hud.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as RaceUI
	RaceManager.finish_race()
	var overlay := scene.get_node("%ResultsOverlay") as Control
	assert_that(overlay.visible).is_true()
	(scene.get_node("%NextRaceButton") as Button).emit_signal("pressed")
	assert_that(overlay.visible).is_false()
	assert_that(RaceManager.consume_pending_race()).is_equal(3)
	RaceManager.queue_race(RaceManager.total_laps)
	await runner.simulate_frames(2)
	assert_that(RaceManager.is_race_active).is_true()
	assert_that((scene.get_node("%CountdownOverlay") as Control).visible).is_true()

func test_return_free_roam_button_launches_open_world() -> void:
	var runner := scene_runner("res://scenes/ui/hud.tscn")
	await runner.simulate_frames(1)
	var scene := runner.scene() as RaceUI
	var launched: Array[String] = []
	scene.launch_callback = func(path: String) -> void: launched.append(path)
	(scene.get_node("%ReturnFreeRoamButton") as Button).emit_signal("pressed")
	assert_that(launched).is_equal([FREE_ROAM_SCENE])
	assert_that((scene.get_node("%ResultsOverlay") as Control).visible).is_false()