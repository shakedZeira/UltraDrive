# tests/suites/test_race_countdown.gd
extends GdUnitTestSuite

## S1 gate: the race start ceremony. Phase order and timing are deterministic,
## controls stay locked through "GO" and release afterwards, the rev override
## follows the phase (idle then a climb), and the HUD overlay mirrors the phase
## string on top of an armed race. Reuses test_race_loop.gd after_test hygiene
## (no leaked lap counters, ceremony reset).

func after_test() -> void:
	for child in RaceManager.get_children():
		if child is LapCounter:
			child.free()
	RaceManager.is_race_active = false
	RaceManager._participants = []
	RaceManager._lap_counters = {}
	RaceManager._checkpoints_dirty = true
	RaceManager._countdown = RaceCountdown.new()
	RaceManager.consume_pending_race()

func test_phases_advance_in_order_with_deterministic_deltas() -> void:
	var countdown := RaceCountdown.new()
	countdown.start()
	var observed: Array[String] = []
	observed.append(countdown.advance(0.5))
	observed.append(countdown.advance(0.5))
	observed.append(countdown.advance(1.0))
	observed.append(countdown.advance(1.0))
	observed.append(countdown.advance(0.8))
	assert_that(observed).is_equal(["3", "2", "1", "GO", "RACE"])

func test_controls_locked_until_go_then_released() -> void:
	var countdown := RaceCountdown.new()
	countdown.start()
	assert_that(countdown.controls_locked()).is_true()
	countdown.advance(1.0)
	assert_that(countdown.controls_locked()).is_true()
	countdown.advance(1.0)
	assert_that(countdown.controls_locked()).is_true()
	countdown.advance(1.0)
	assert_that(countdown.phase()).is_equal("GO")
	assert_that(countdown.controls_locked()).is_true()
	countdown.advance(0.8)
	assert_that(countdown.phase()).is_equal("RACE")
	assert_that(countdown.controls_locked()).is_false()
	countdown.advance(10.0)
	assert_that(countdown.controls_locked()).is_false()

func test_rev_override_zero_then_climbs_with_phase() -> void:
	var countdown := RaceCountdown.new()
	countdown.start()
	assert_that(countdown.phase()).is_equal("3")
	assert_that(countdown.rev_rpm_override()).is_equal(0.0)
	countdown.advance(1.0)
	assert_that(countdown.phase()).is_equal("2")
	assert_that(countdown.rev_rpm_override()).is_equal(0.0)
	countdown.advance(0.5)
	var early := countdown.rev_rpm_override()
	assert_that(early).is_greater(0.0)
	countdown.advance(0.5)
	assert_that(countdown.phase()).is_equal("1")
	assert_that(countdown.rev_rpm_override()).is_greater(early)
	countdown.advance(1.0)
	assert_that(countdown.phase()).is_equal("GO")
	assert_that(countdown.rev_rpm_override()).is_greater(0.6)
	countdown.advance(0.4)
	assert_that(countdown.rev_rpm_override()).is_greater(0.9)
	countdown.advance(0.4)
	assert_that(countdown.phase()).is_equal("RACE")
	assert_that(countdown.rev_rpm_override()).is_equal(0.0)

func test_progress_tracks_elapsed_and_clamps() -> void:
	var countdown := RaceCountdown.new()
	countdown.start()
	assert_that(countdown.progress()).is_equal(0.0)
	countdown.advance(1.9)
	assert_that(countdown.progress()).is_greater(0.0)
	assert_that(countdown.progress()).is_less(1.0)
	countdown.advance(2.0)
	assert_that(countdown.progress()).is_equal(1.0)
	countdown.advance(100.0)
	assert_that(countdown.progress()).is_equal(1.0)

func test_start_resets_to_first_phase() -> void:
	var countdown := RaceCountdown.new()
	countdown.start()
	countdown.advance(3.9)
	assert_that(countdown.phase()).is_equal("RACE")
	assert_that(countdown.controls_locked()).is_false()
	countdown.start()
	assert_that(countdown.phase()).is_equal("3")
	assert_that(countdown.controls_locked()).is_true()
	assert_that(countdown.progress()).is_equal(0.0)

func test_race_manager_ceremony_gate_locks_and_releases() -> void:
	RaceManager.start_race([], 3)
	assert_that(RaceManager.is_race_active).is_true()
	assert_that(RaceManager.controls_locked()).is_true()
	var countdown := RaceManager.get_countdown()
	assert_that(countdown != null).is_true()
	countdown.advance(3.8)
	assert_that(RaceManager.controls_locked()).is_false()
	assert_that(RaceManager.rev_override()).is_equal(0.0)
	RaceManager.consume_pending_race()

func test_request_race_seam_queues_pending_laps() -> void:
	RaceManager.request_race(5)
	assert_that(RaceManager.consume_pending_race()).is_equal(5)

func test_drivetrain_rev_override_holds_rpm_and_zero_torque() -> void:
	var drivetrain := Drivetrain.new()
	var config := CarConfig.new()
	drivetrain.rpm_override = 1.0
	var result := drivetrain.update(1.0 / 60.0, 0.0, config)
	assert_that(result["drive_torque"]).is_equal(0.0)
	assert_that(drivetrain.engine_rpm).is_greater(config.idle_rpm)
	drivetrain.rpm_override = -1.0
	assert_that(drivetrain.update(1.0 / 60.0, 0.0, config)["drive_torque"]).is_less(0.0)

func test_hud_overlay_hidden_before_race() -> void:
	var runner := scene_runner("res://scenes/ui/hud.tscn")
	await runner.simulate_frames(1)
	var overlay := runner.scene().get_node("%CountdownOverlay") as Control
	assert_that(overlay.visible).is_false()

func test_hud_countdown_overlay_shows_phases_in_order() -> void:
	RaceManager.queue_race(2)
	var runner := scene_runner("res://scenes/ui/hud.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene()
	var overlay := scene.get_node("%CountdownOverlay") as Control
	var banner := scene.get_node("%Banner") as Label
	assert_that(RaceManager.is_race_active).is_true()
	assert_that(overlay.visible).is_true()
	assert_that(banner.text).is_equal("3")
	var countdown := RaceManager.get_countdown()
	countdown.advance(1.05)
	await runner.simulate_frames(1)
	assert_that(banner.text).is_equal("2")
	countdown.advance(1.05)
	await runner.simulate_frames(1)
	assert_that(banner.text).is_equal("1")
	countdown.advance(1.05)
	await runner.simulate_frames(1)
	assert_that(banner.text).is_equal("GO!")
	countdown.advance(1.05)
	await runner.simulate_frames(1)
	assert_that(RaceManager.controls_locked()).is_false()
	assert_that(overlay.visible).is_false()

func test_hud_overlay_hidden_after_finish() -> void:
	RaceManager.queue_race(2)
	var runner := scene_runner("res://scenes/ui/hud.tscn")
	await runner.simulate_frames(2)
	var overlay := runner.scene().get_node("%CountdownOverlay") as Control
	assert_that(overlay.visible).is_true()
	RaceManager.finish_race()
	await runner.simulate_frames(1)
	assert_that(overlay.visible).is_false()