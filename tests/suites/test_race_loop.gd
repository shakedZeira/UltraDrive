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

## A `CheckpointStub` PARENTED to the suite, so `Checkpoint._ready()` adds it to
## the `"checkpoints"` group `RaceManager.reset_checkpoints()` iterates. The
## plain `_add_checkpoint` helper cannot reach the re-arm path: a real
## `Checkpoint` has no way to fake an overlap, so its `_counted` is never
## populated and any `_counted.size() == 0` check on it is vacuous.
func _add_stub_checkpoint(index: int) -> CheckpointStub:
	var cp := _new_stub()
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

## The REAL regression for the `lap_completed` -> re-arm wiring, which
## `test_checkpoints_rearm_after_lap_completed` above cannot catch: that test
## calls `counter.update()` directly and never runs `Checkpoint.is_passed()`, so
## `_counted` stays empty and its `_counted.size() == 0` assertions are true no
## matter what the signal is bound to.
##
## The bug: `start_race` used to `connect(reset_checkpoints)` on the 3-arg
## `LapCounter.lap_completed(vehicle, lap, time)` signal while `reset_checkpoints()`
## takes 0 args. Godot does NO arity validation at `connect()` time -- it returns
## OK -- and only fails at EMIT time with "Method expected 0 argument(s), but
## called with 3", so the handler never ran. `Checkpoint.reset()` is the only
## thing that clears `_counted`, so the lap-completion re-arm silently no-op'd:
## every checkpoint kept each car latched forever and no lap after the first
## could ever tick. This test drives the counted path and fails (on the
## `_counted.size() == 0` checks) against that code, and passes with the fix.
func test_lap_completion_rearms_checkpoints_that_actually_counted() -> void:
	var car := _new_stub_car()
	var cp0 := _add_stub_checkpoint(0)
	var cp1 := _add_stub_checkpoint(1)
	RaceManager.start_race([car], 2)
	# Precondition: only these two stubs are in the group, so cp1 really is the
	# LAST checkpoint of a 2-checkpoint loop (else `update` could not complete a
	# lap and this test would be proving nothing).
	assert_int(get_tree().get_nodes_in_group("checkpoints").size()).is_equal(2)
	var counter: LapCounter = RaceManager.get_lap_counter(car)

	# Drive the counted path: `overlaps` makes the stub report a pass, and
	# `is_passed` is the seam that writes `_counted` -- the exact state the
	# re-arm must clear.
	cp0.overlaps = [car]
	cp1.overlaps = [car]
	assert_that(cp0.is_passed(car)).is_true()
	assert_int(cp0.get("_counted").size()).is_equal(1)
	counter.update(car, cp0)
	assert_that(cp1.is_passed(car)).is_true()
	# Crossing the last checkpoint completes lap 1 -> lap_completed -> re-arm.
	counter.update(car, cp1)

	# THE diagnostic assertions: both latches must be cleared by the re-arm.
	assert_int(cp0.get("_counted").size()).is_equal(0)
	assert_int(cp1.get("_counted").size()).is_equal(0)
	# Re-armed, so lap 2 can count: the next pass latches again.
	assert_that(cp0.is_passed(car)).is_true()
	assert_int(cp0.get("_counted").size()).is_equal(1)
	assert_int(counter.get_current_lap()).is_equal(2)
	RaceManager.consume_pending_race()

## Drives `car` through a stub gate exactly the way `RaceManager._process`
## drives it in a real race: the checkpoint must report the pass (latch) for
## the counter to see it, and the car only lingers in the box when a test
## explicitly keeps the overlap set.
func _drive_gate(cp: CheckpointStub, car: VehiclePhysics, counter: LapCounter) -> void:
	cp.overlaps = [car]
	if cp.is_passed(car):
		counter.update(car, cp)
	cp.overlaps = []

## The finish re-latch regression: the lap-completion re-arm fires WHILE the
## car is still inside the finish box (a 16 m box takes many frames to clear),
## so on the very next frame the still-overlapping car latches the finish gate
## again for the NEW lap. That second latch must not tick a phantom lap -- and
## it must not be swallowed forever either: the rejection releases the latch,
## the car collects its gates, and the next real crossing completes lap 2.
## Fails twice on the old code (the strict chain re-latched the finish and
## nothing could ever clear `_counted` again, so lap 2 never ticked).
func test_second_lap_counts_while_car_lingers_in_finish_box() -> void:
	var car := _new_stub_car()
	var cp0 := _add_stub_checkpoint(0)
	var cp1 := _add_stub_checkpoint(1)
	RaceManager.start_race([car], 3)
	var counter: LapCounter = RaceManager.get_lap_counter(car)

	# Lap 1: both gates, then the car STAYS in the finish box (cp1) afterwards.
	_drive_gate(cp0, car, counter)
	cp1.overlaps = [car]
	assert_that(cp1.is_passed(car)).is_true()
	counter.update(car, cp1)
	assert_int(counter.get_current_lap()).is_equal(2)

	# Frame after the re-arm: still inside the finish box -> the pass re-latches
	# and is fed to the counter exactly like RaceManager._process would.
	cp1.overlaps = [car]
	if cp1.is_passed(car):
		counter.update(car, cp1)
	# No phantom lap from the lingering overlap...
	assert_int(counter.get_current_lap()).is_equal(2)
	# ...and the rejected crossing RELEASED the latch instead of leaving it
	# latched forever (the old wedge: only `reset()` clears `_counted`, and it
	# runs only at a lap completion this crossing failed to earn).
	assert_int(cp1.get("_counted").size()).is_equal(0)

	# The car finally clears the box and takes the gates of lap 2.
	cp1.overlaps = []
	assert_that(cp1.is_passed(car)).is_false()
	_drive_gate(cp0, car, counter)
	cp1.overlaps = [car]
	assert_that(cp1.is_passed(car)).is_true()
	counter.update(car, cp1)
	assert_int(counter.get_current_lap()).is_equal(3)
	RaceManager.consume_pending_race()

## Off-track regression: an excursion that skips a gate used to desync the
## strict expected-index chain permanently, after which the finish line never
## counted again -- the lap was lost, and so was every lap after it. Skipping
## a gate should cost that gate's progress, not the lap.
## Fails on the old code (6 of 7 gates then the finish never ticked).
func test_missing_one_gate_offtrack_still_counts_the_lap() -> void:
	var car := _new_stub_car()
	var cps: Array[CheckpointStub] = []
	for i in range(8):
		cps.append(_add_stub_checkpoint(i))
	RaceManager.start_race([car], 3)
	# Precondition: these 8 stubs are the whole field, so cp7 is the finish
	# line (index == total - 1) -- the test would prove nothing otherwise.
	assert_int(get_tree().get_nodes_in_group("checkpoints").size()).is_equal(8)
	var counter: LapCounter = RaceManager.get_lap_counter(car)

	# Lap 1: every gate but cp6 -- the car ran wide and missed that one.
	for i in range(6):
		_drive_gate(cps[i], car, counter)
	_drive_gate(cps[7], car, counter)
	# 6 of the 7 non-finish gates taken -> the lap counts despite the miss.
	assert_int(counter.get_current_lap()).is_equal(2)

	# Lap 2, clean: the skipped gate did not wedge the progression.
	for i in range(7):
		_drive_gate(cps[i], car, counter)
	_drive_gate(cps[7], car, counter)
	assert_int(counter.get_current_lap()).is_equal(3)
	RaceManager.consume_pending_race()

## The anti-cheese counter-case: crossing the finish line having taken almost
## none of the circuit must NOT tick a lap (no laps gained by skipping gates),
## and the refusal must not wedge the counter either -- once enough of the
## circuit has genuinely been taken, the next crossing counts.
func test_finish_crossing_without_enough_gates_grants_no_lap() -> void:
	var car := _new_stub_car()
	var cps: Array[CheckpointStub] = []
	for i in range(8):
		cps.append(_add_stub_checkpoint(i))
	RaceManager.start_race([car], 3)
	assert_int(get_tree().get_nodes_in_group("checkpoints").size()).is_equal(8)
	var counter: LapCounter = RaceManager.get_lap_counter(car)

	# Only 3 of the 7 non-finish gates (the halfway floor is 4), then blag the
	# finish line.
	for i in range(3):
		_drive_gate(cps[i], car, counter)
	_drive_gate(cps[7], car, counter)
	# No lap...
	assert_int(counter.get_current_lap()).is_equal(1)
	# ...and the rejected crossing released the finish latch instead of
	# swallowing every later one.
	assert_int(cps[7].get("_counted").size()).is_equal(0)

	# The same car now takes the rest of the circuit: the next crossing counts.
	for i in range(3, 7):
		_drive_gate(cps[i], car, counter)
	_drive_gate(cps[7], car, counter)
	assert_int(counter.get_current_lap()).is_equal(2)
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