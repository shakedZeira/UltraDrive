# tests/suites/test_race_loop.gd
extends GdUnitTestSuite

## Race-loop end-to-end coverage: lap clock, checkpoint gating, race
## manager group caching / leak / re-arm lifecycle, standings ordering and
## the Play -> HUD commit flow.

const CheckpointStub := preload("res://tests/suites/checkpoint_stub.gd")

var _managed_cars: Array = []
var _managed_stubs: Array = []

func before_test() -> void:
	_managed_cars.clear()
	_managed_stubs.clear()

func after_test() -> void:
	for car in _managed_cars:
		if is_instance_valid(car):
			car.free()
	for stub in _managed_stubs:
		if is_instance_valid(stub):
			stub.free()
	_managed_cars.clear()
	_managed_stubs.clear()
	for child in RaceManager.get_children():
		if child is LapCounter:
			child.free()
	RaceManager.is_race_active = false
	RaceManager._participants = []
	RaceManager._lap_counters = {}
	RaceManager._checkpoints_dirty = true
	for child in get_children():
		if child is Checkpoint:
			child.free()

func test_total_time_is_relative_to_race_start() -> void:
	var counter := LapCounter.new()
	add_child(counter)
	# _race_start_time is set in start_race, so total time is measured from the
	# race start anchor, NOT from node creation. Capture the wall clock just
	# before start_race: if the anchor were node _ready/creation, total time
	# would be large here; from the race start it must be near zero.
	var before := Time.get_ticks_msec() / 1000.0
	counter.start_race(3)
	assert_that(counter.get_total_time()).is_less(1.0)
	# Deterministic clock advance without waiting on real wall time: rewind the
	# anchor 5 s, then total time must track elapsed wall clock from the race
	# start (5 s + the tiny elapsed-since-start, so comfortably above 4.5).
	counter._race_start_time -= 5.0
	assert_that(counter.get_total_time()).is_greater(4.5)

func test_checkpoint_reset_arms_and_counts_once_per_pass() -> void:
	var stub := _new_stub()
	var car := _new_stub_car()
	assert_that(stub.active).is_false()
	stub.reset()
	assert_that(stub.active).is_true()
	stub.overlaps = [car]
	# First overlap counts the pass...
	assert_that(stub.is_passed(car)).is_true()
	# ...but the same overlap does NOT count every physics frame.
	assert_that(stub.is_passed(car)).is_false()
	stub.overlaps = []
	# While the vehicle is gone we never report a pass.
	assert_that(stub.is_passed(car)).is_false()

func _new_stub_car() -> VehiclePhysics:
	var car := VehiclePhysics.new()
	_managed_cars.append(car)
	return car

func _new_stub() -> CheckpointStub:
	var stub := CheckpointStub.new()
	_managed_stubs.append(stub)
	return stub

func test_checkpoint_rearm_counts_next_pass() -> void:
	var stub := _new_stub()
	var car := _new_stub_car()
	stub.reset()
	stub.overlaps = [car]
	stub.is_passed(car)
	assert_that(stub.get("_counted").size()).is_equal(1)
	# Next lap: RaceManager re-arms -> reset() clears the counted latch.
	stub.overlaps = []
	stub.reset()
	stub.overlaps = [car]
	assert_that(stub.is_passed(car)).is_true()
	assert_that(stub.get("_counted").size()).is_equal(1)
	stub.free()

func _add_checkpoint(index: int) -> Checkpoint:
	var cp := Checkpoint.new()
	cp.index = index
	add_child(cp)
	return cp

func test_start_race_arms_existing_checkpoints() -> void:
	var car := _new_stub_car()
	var cp0 := _add_checkpoint(0)
	var cp1 := _add_checkpoint(1)
	RaceManager.start_race([car], 3)
	assert_that(cp0.active).is_true()
	assert_that(cp1.active).is_true()
	cp0.queue_free()
	cp1.queue_free()
	RaceManager.consume_pending_race()

func test_start_race_with_empty_checkpoint_group_stays_active() -> void:
	var car := _new_stub_car()
	RaceManager.start_race([car], 3)
	assert_that(RaceManager.is_race_active).is_true()
	assert_that(RaceManager.get_standings().size()).is_equal(1)
	RaceManager.consume_pending_race()

func test_checkpoint_cache_is_not_rescanned_within_scene() -> void:
	var car := _new_stub_car()
	RaceManager.start_race([car], 3)
	var late := _add_checkpoint(0)
	# Group was empty at start_race; the cache is not refreshed per frame.
	assert_that(RaceManager.get_checkpoints()).is_empty()
	late.queue_free()

func test_checkpoint_cache_recovers_after_nodes_freed() -> void:
	var car := _new_stub_car()
	var cp := _add_checkpoint(0)
	RaceManager.start_race([car], 3)
	assert_that(RaceManager.get_checkpoints().size()).is_equal(1)
	cp.queue_free()
	await get_tree().process_frame
	var other := _add_checkpoint(1)
	assert_that(RaceManager.get_checkpoints()).is_equal([other])
	other.queue_free()
	RaceManager.consume_pending_race()

func test_start_race_twice_does_not_leak_lap_counters() -> void:
	var car_a := _new_stub_car()
	var car_b := _new_stub_car()
	RaceManager.start_race([car_a], 3)
	await get_tree().process_frame
	RaceManager.start_race([car_b], 3)
	await get_tree().process_frame
	var counters := 0
	for child in RaceManager.get_children():
		if child is LapCounter:
			counters += 1
	assert_that(counters).is_equal(1)
	RaceManager.consume_pending_race()

func test_checkpoints_rearm_after_lap_completed() -> void:
	var car := _new_stub_car()
	var cp0 := _add_checkpoint(0)
	var cp1 := _add_checkpoint(1)
	RaceManager.start_race([car], 2)
	var counter: LapCounter = RaceManager.get_lap_counter(car)
	counter.update(car, cp0)
	counter.update(car, cp1)   # crosses last checkpoint -> lap_completed -> re-arm
	assert_that(cp0.get("_counted").size()).is_equal(0)
	assert_that(cp1.get("_counted").size()).is_equal(0)
	assert_that(cp0.active).is_true()
	assert_that(cp1.active).is_true()
	assert_that(counter.get_current_lap()).is_equal(2)
	cp0.queue_free()
	cp1.queue_free()
	RaceManager.consume_pending_race()

func _store_checkpoints(count: int) -> Array[Checkpoint]:
	var cps: Array[Checkpoint] = []
	for i in range(count):
		cps.append(_add_checkpoint(i))
	return cps

func test_standings_distance_tiebreak() -> void:
	var cps := _store_checkpoints(3)
	var near_car := _new_stub_car()
	var far_car := _new_stub_car()
	# Both cars lap 1, last checkpoint 1 (passed cp0 then cp1).
	RaceManager.start_race([near_car, far_car], 3)
	var near_count: LapCounter = RaceManager.get_lap_counter(near_car)
	near_count.update(near_car, cps[0])
	near_count.update(near_car, cps[1])
	var far_count: LapCounter = RaceManager.get_lap_counter(far_car)
	far_count.update(far_car, cps[0])
	far_count.update(far_car, cps[1])
	near_car.position = cps[2].position              # next checkpoint: tiny distance
	far_car.position = cps[2].position + Vector3(40, 0, 0)  # same cp, far away
	var standings := RaceManager.get_standings()
	assert_that(standings.find(near_car)).is_equal(0)
	assert_that(standings.find(far_car)).is_equal(1)
	for cp in cps:
		cp.queue_free()
	RaceManager.consume_pending_race()

func test_standings_lap_then_checkpoint_ordering() -> void:
	var cps := _store_checkpoints(3)
	var leader := _new_stub_car()   # lap 2 (finished one full lap)
	var ahead := _new_stub_car()    # lap 1, last checkpoint 2
	var behind := _new_stub_car()   # lap 1, last checkpoint 0
	RaceManager.start_race([behind, leader, ahead], 3)
	var counters := {
		leader: RaceManager.get_lap_counter(leader),
		ahead: RaceManager.get_lap_counter(ahead),
		behind: RaceManager.get_lap_counter(behind),
	}
	for idx in range(3):
		counters[leader].update(leader, cps[idx])
	for idx in range(3):
		counters[ahead].update(ahead, cps[idx])
	for idx in range(1):
		counters[behind].update(behind, cps[idx])
	var standings := RaceManager.get_standings()
	assert_that(standings).is_equal([leader, ahead, behind])
	for cp in cps:
		cp.queue_free()
	RaceManager.consume_pending_race()

func test_track_select_play_queues_race() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	var launched: Array[String] = []
	scene.launch_callback = func(path: String) -> void: launched.append(path)
	scene.select_track("mountain_pass")
	scene._on_play_pressed()
	assert_that(launched).is_equal([TrackRegistry.get_scene_path("mountain_pass")])
	assert_that(RaceManager.consume_pending_race()).is_equal(2)

func test_hud_commits_pending_race_on_first_frame() -> void:
	RaceManager.queue_race(2)
	var runner := scene_runner("res://scenes/ui/hud.tscn")
	await runner.simulate_frames(2)
	assert_that(RaceManager.is_race_active).is_true()
	assert_that(RaceManager.total_laps).is_equal(2)
	RaceManager.consume_pending_race()

func test_hud_shows_finish_banner_on_race_finished() -> void:
	var runner := scene_runner("res://scenes/ui/hud.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene()
	var label := scene.get_node("%PositionLabel") as Label
	var car := _new_stub_car()
	RaceManager.start_race([car], 3)
	RaceManager.finish_race()
	assert_that(label.text.contains("FINISH")).is_true()
	RaceManager.consume_pending_race()