# Race Loop End-to-End Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Play actually start a race, and make the race loop genuinely progress end-to-end: armed checkpoints with once-per-pass gating, a real lap counter clock, correct lap→checkpoint→distance standings, a live lap/position/time HUD, and a finish banner — with no LapCounter leaks and no per-frame group rescanning.
**Architecture:** `TrackSelect` (track_select.gd) queues the chosen track's `laps_default` on `RaceManager` when Play is pressed; `RaceManager` is an autoload that owns `start_race(cars, laps)`, caches the `"checkpoints"` group, resets/arms every member, drives each car's `LapCounter` per frame with no fresh group allocation, and re-arms checkpoints on each `lap_completed`. The HUD (`race_ui.gd`, instanced in every track scene) latches the pending race in `_ready()` and commits `start_race(VehicleManager.get_all_cars(), laps)` on the first `_process()` frame — by which point every track (including Mountain Pass, whose root `_ready()` builds checkpoints after child `_ready()`s) has registered its checkpoints. `Checkpoint` gates each vehicle once per armed cycle via an internal `_counted` dictionary instead of the broken `active`-toggle, with an `_overlapping_bodies()` seam so gdUnit tests can script overlaps without physics.
**Tech Stack:** Godot 4.7.2 GDScript, GDUnit4
**Spec:** issue inventory A1-A5 + D1 (see preamble)

## Global Constraints

- TAB indentation everywhere, including `.gd` files. Do not change whitespace style of unrelated lines.
- Never `git add -A` / `git add .` / `git add docs/`. Stage only the exact source/test files each task lists. Never stage `*.uid` (task 1 generates `test_race_loop.gd.uid` on first import — leave it untracked; `.gitignore` already excludes it and `git status --short` must NOT list `.uid` files).
- Do NOT touch `AGENTS.md`, `start_game.bat`, `play_game.bat`, or anything under `.godot/`.
- GDUnit4 treats GDScript warnings as errors. Never write `var x := <Variant-returning call>` (e.g. `_lap_counters.get(car)`); give such variables an explicit type (`var counter: LapCounter = _lap_counters.get(car)`) or use `as <Type>`.
- Repo verification recipe, in this order (each command self-terminating, add own timeouts):
  1. After any `.gd` edit — import probe (expect ZERO `SCRIPT ERROR` / `Parse Error` / `Failed to load` lines; benign `resources still in use at exit` + Terrain3D whitelist lines are allowed):
     `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import . 2>&1 | findstr /i "SCRIPT ERROR Parse Error Failed to load"`
  2. Targeted suite run for the task being worked (fast red/green loop):
     `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/suites/test_race_loop.gd > _gdunit.txt 2>&1`
     then `findstr /c:"Overall Summary:" _gdunit.txt`.
  3. Full-suite gate before EVERY commit (baseline is currently `69 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`; this plan adds a new `tests/suites/test_race_loop.gd` with 14 tests, so the expected summary grows to `83 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`):
     `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1`
     then `findstr /c:"Overall Summary:" _gdunit.txt`.
  - Never run the `-s` command alone on a cold cache (exit 103). Run the step-1 import probe first, then the `-s` run with `--ignoreHeadlessMode` AFTER the tool-script path.
- Never commit until the FULL suite shows `0 errors | 0 failures` AND the step-1 probe is clean. Commit scoped per task with the repo's identity style (see `docs/superpowers/plans/2026-09-10-ultradrive-master-plan.md` for the `-c user.name/email` pattern). The plan `.md` itself is never committed.
- Public API stays backward compatible: `RaceManager.start_race(cars: Array, laps: int) -> void`, `finish_race()`, `get_standings() -> Array`, `get_lap_counter(car: VehiclePhysics) -> LapCounter`, `total_laps`, `is_race_active`, the `race_started`/`race_finished(standings)` signals; `LapCounter.start_race(laps)`, `update(vehicle, passed_checkpoint)`, `get_current_lap()`, `get_lap_time()`, `get_total_time()`; `Checkpoint.index`, `is_start_line`, `active`, `reset()`, `is_passed(vehicle)`. Existing `tests/test_race_logic.gd` and `tests/test_track_system.gd` must keep passing.

## Design Decisions (locked in)

- **A1 flow:** `track_select._on_play_pressed()` calls `RaceManager.queue_race(int(TrackRegistry.get_track(_selected_id).get("laps_default", 3)))` then the existing `launch_callback.call(scene_path)`. `race_ui._ready()` latches `RaceManager.consume_pending_race()` into a member; `race_ui._process()` commits `start_race(VehicleManager.get_all_cars(), laps)` on the first frame a pending race exists. A pending race with `laps > 0` always wins over an in-flight/stale race (start_race re-initializes), and a 0 pending (free-roam, Continue) never starts anything.
- **Empty checkpoint group is legal:** `start_race` with zero checkpoints still sets `is_race_active = true` and the HUD shows P1 / LAP 1; the per-frame scan simply iterates an empty cache. `LapCounter.update` guards `_get_total_checkpoints() == 0` (returns a no-op dict) so there is no `% 0` crash.
- **Checkpoint lifecycle (A3):** `reset()` sets `active = true` AND clears the per-vehicle `_counted` dictionary (re-arms the next pass/lap). `is_passed` consumes once per vehicle per armed cycle and returns `false` while still overlapping afterwards. `RaceManager.start_race()` calls `reset_checkpoints()` on the cached group, and `RaceManager` also calls `reset_checkpoints()` on every `lap_completed` so the same checkpoint can be counted once per lap.
- **Standings (A4):** sort by `get_current_lap()` desc, then `get_last_checkpoint()` desc, then distance from the car to the next checkpoint in the cached list (`(last_checkpoint + 1) % size`, x/z plane) ascending (closer = more progress). Missing counters fall back to lap 1 / checkpoint −1; empty group gives a flat 0.0 distance.
- **A5:** `start_race()` `queue_free()`s every existing LapCounter child before rebuilding `_lap_counters` (autoload persists across scenes → leak fixed). The per-frame group scan becomes `_all_checkpoints()`, which rescans `get_tree().get_nodes_in_group("checkpoints")` ONLY when `_checkpoints_dirty` (set true initially and on `GameState.scene_changed`) or when any cached member is a freed instance (heals across gdUnit tests / scene teardowns). `get_checkpoints() -> Array[Checkpoint]` exposes the cache.
- **A2:** `LapCounter.start_race(laps)` sets `_race_start_time = now` (same `now` as `_lap_start_time`), so `get_total_time()` returns elapsed race time. `_race_start_time` declaration moves into the top var block.
- **Results surfacing (minimal):** `finish_race()` already emits `race_finished(standings)`; `race_ui` connects to it and, when the race is over, freezes the position/lap/time updates and shows a `FINISH` banner with the winner's `get_total_time()` and the manager's `get_race_time()`. No new results scene.

## Tasks

### Task 1 — LapCounter race clock (A2) + `get_last_checkpoint()` accessor

**Files:**
- Modify `scripts/track/lap_counter.gd`
- Create `tests/suites/test_race_loop.gd` (first commit of this plan's suite file)

**Interfaces:**
- Consumes: `LapCounter.start_race(laps)`, `Time.get_ticks_msec()`, `get_total_time()` — all existing.
- Produces: `LapCounter.get_last_checkpoint() -> int` (new accessor, returns `_last_checkpoint`; no behavior change — `get_standings()` in Task 5 consumes it).

- [ ] Write failing test: create `tests/suites/test_race_loop.gd` with `extends GdUnitTestSuite` and this test, using the suite-of-the-day fix: add `RaceManager.consume_pending_race()` clearing after every test that mutates autoload state (pre-emptive hygiene; see note in Task 6). The suite file starts containing ONLY:

```gdscript
# tests/suites/test_race_loop.gd
extends GdUnitTestSuite

## Race-loop end-to-end coverage: lap clock, checkpoint gating, race
## manager group caching / leak / re-arm lifecycle, standings ordering and
## the Play -> HUD commit flow.

func test_total_time_is_relative_to_race_start() -> void:
    var counter := LapCounter.new()
    add_child(counter)
    counter.start_race(3)
    # _race_start_time is set in start_race, so total time starts near zero.
    assert_that(counter.get_total_time()).is_less(0.5)
    await get_tree().create_timer(0.05).timeout
    assert_that(counter.get_total_time()).is_greater(0.04)
```

- [ ] Run the targeted suite (Global Constraint #2): expect FAIL — `get_total_time()` is `Time.get_ticks_msec()/1000.0 - 0` ≈ engine uptime, so the first `assert_that(...).is_less(0.5)` fails.
- [ ] Implement: in `scripts/track/lap_counter.gd`, move `_race_start_time` into the top var block and set it in `start_race`, plus add the accessor:

```gdscript
class_name LapCounter
extends Node

## Tracks lap progress for vehicles by monitoring checkpoints.

signal lap_completed(vehicle: VehiclePhysics, lap: int, time: float)
signal race_finished(vehicle: VehiclePhysics, total_time: float)

var total_laps: int = 3
var _race_start_time: float = 0.0
var _lap_start_time: float = 0.0
var _current_lap: int = 1
var _last_checkpoint: int = -1
var _finished: bool = false

func start_race(laps: int) -> void:
	total_laps = laps
	_current_lap = 1
	_last_checkpoint = -1
	_finished = false
	var now := Time.get_ticks_msec() / 1000.0
	_race_start_time = now
	_lap_start_time = now

func update(vehicle: VehiclePhysics, passed_checkpoint: Checkpoint) -> Dictionary:
	## Called by RaceManager when a vehicle passes a checkpoint.
	## Returns { lap_completed: bool, race_finished: bool }

	var total := _get_total_checkpoints()
	if total == 0:
		return {"lap_completed": false, "race_finished": false}

	# Check for valid progression (allows wrap-around)
	var expected := (_last_checkpoint + 1) % total
	if passed_checkpoint.index == expected:
		_last_checkpoint = passed_checkpoint.index

		# If we've passed the last checkpoint, a lap is complete
		if _last_checkpoint == total - 1:
			_current_lap += 1
			lap_completed.emit(vehicle, _current_lap - 1, get_lap_time())
			_lap_start_time = Time.get_ticks_msec() / 1000.0

			if _current_lap > total_laps:
				_finished = true
				race_finished.emit(vehicle, get_total_time())
				return {"lap_completed": true, "race_finished": true}

	return {"lap_completed": false, "race_finished": false}

func get_current_lap() -> int:
	return _current_lap

func get_last_checkpoint() -> int:
	return _last_checkpoint

func get_lap_time() -> float:
	return (Time.get_ticks_msec() / 1000.0) - _lap_start_time

func get_total_time() -> float:
	return (Time.get_ticks_msec() / 1000.0) - _race_start_time

func _get_total_checkpoints() -> int:
	return get_tree().get_nodes_in_group("checkpoints").size()
```

- [ ] Run targeted suite: expect PASS (both asserts).
- [ ] Run import probe (Global Constraint #1) clean, then full suite green, then commit ONLY `scripts/track/lap_counter.gd` and `tests/suites/test_race_loop.gd`. Expected full-suite summary now `70 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`.

### Task 2 — Checkpoint once-per-pass gating + `reset()` lifecycle (A3 core)

**Files:**
- Modify `scripts/track/checkpoint.gd`
- Modify `tests/suites/test_race_loop.gd` (append tests)

**Interfaces:**
- Consumes: `Checkpoint.active`, `get_overlapping_bodies()` (Area3D API), `VehiclePhysics` type.
- Produces: `Checkpoint._overlapping_bodies() -> Array` (new internal seam, overridable by tests), same public `reset()`/`is_passed(vehicle)` signatures.
- Test helper: inner class `_CheckpointStub extends Checkpoint` with `var overlaps: Array = []` overriding `_overlapping_bodies()` so a pass can be scripted without the physics server.

- [ ] Write failing tests (append to `tests/suites/test_race_loop.gd`):

```gdscript
class _CheckpointStub:
	extends Checkpoint
	var overlaps: Array = []

	func _overlapping_bodies() -> Array:
		return overlaps

func _new_stub_car() -> VehiclePhysics:
	return VehiclePhysics.new()

func test_checkpoint_reset_arms_and_counts_once_per_pass() -> void:
	var stub := _CheckpointStub.new()
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

func test_checkpoint_rearm_counts_next_pass() -> void:
	var stub := _CheckpointStub.new()
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
```

- [ ] Run targeted suite: expect FAIL — pre-fix `is_passed` returns true for overlapping not-armed checkpoints every frame, so `test_checkpoint_reset_arms_and_counts_once_per_pass` fails at the `is_false()` assertion, and `test_checkpoint_rearm_counts_next_pass` fails at `stub.get("_counted")` (null).
- [ ] Implement: rewrite `scripts/track/checkpoint.gd`:

```gdscript
class_name Checkpoint
extends Area3D

## A checkpoint zone that vehicles must pass through.
## Set index to order checkpoints around the track.
## Set next_checkpoints array to allow multiple valid next checkpoints (for branching tracks).

@export var index: int = 0
@export var is_start_line: bool = false

var active: bool = false
var _counted: Dictionary = {}

func _ready() -> void:
	add_to_group("checkpoints")
	collision_layer = 0
	collision_mask = 1 | 16  # layer 1 (default bodies) + layer 5

func is_passed(vehicle: VehiclePhysics) -> bool:
	## Returns true once per pass while armed (after reset()).
	## Each vehicle is counted at most once per armed cycle.
	if not active:
		return false
	if not (vehicle in _overlapping_bodies()):
		return false
	if _counted.has(vehicle):
		return false
	_counted[vehicle] = true
	return true

func _overlapping_bodies() -> Array:
	return get_overlapping_bodies()

func reset() -> void:
	active = true
	_counted.clear()
```

Note: the old `body_entered` / `_on_body_entered` toggle is removed — external `.body_entered.connect(...)` handlers in `scripts/test_circuit.gd` and `scripts/track/mountain_pass.gd` are independent and keep working.
- [ ] Run targeted suite: expect PASS (both tests).
- [ ] Run import probe clean, full suite green, commit ONLY `scripts/track/checkpoint.gd` and `tests/suites/test_race_loop.gd`. Expected summary `72 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`.

### Task 3 — `start_race` cleanup + checkpoint cache + group reset (A3 wiring, A5 first half)

**Files:**
- Modify `autoload/race_manager.gd`
- Modify `tests/suites/test_race_loop.gd` (append tests)

**Interfaces:**
- Consumes: `VehiclePhysics`, `LapCounter`, `Checkpoint.reset()`, group `"checkpoints"`, `GameState.scene_changed(scene_path: String)` (existing autoload signal).
- Produces (backward compatible):
  - `RaceManager.get_checkpoints() -> Array[Checkpoint]` (new; returns the cached group)
  - `RaceManager._all_checkpoints() -> Array[Checkpoint]` (internal cache-or-rescan)
  - `RaceManager.reset_checkpoints() -> void` (public; arms every cached member)
  - `start_race()` now: frees prior LapCounter children, caches + arms checkpoints, wires `_process` to the cached list.

- [ ] Write failing tests (append):

```gdscript
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
```

- [ ] Run targeted suite: expect FAIL — pre-fix `start_race` never resets checkpoints (`cp0.active` stays false), `get_checkpoints()` does not exist (parse error on `test_checkpoint_cache_is_not_rescanned_within_scene` / `..._recovers...`), and the leak test finds 2 LapCounter children.
- [ ] Implement: rewrite `autoload/race_manager.gd`:

```gdscript
extends Node

## Manages the active race: checkpoints, lap timing, positions.

signal race_started
signal race_finished(standings: Array)

var is_race_active: bool = false
var total_laps: int = 3
var _participants: Array[VehiclePhysics] = []
var _lap_counters: Dictionary = {}
var _race_time: float = 0.0
var _pending_laps: int = 0
var _checkpoints_cache: Array[Checkpoint] = []
var _checkpoints_dirty: bool = true

func _ready() -> void:
	GameState.scene_changed.connect(func(_scene: String) -> void: _checkpoints_dirty = true)

func queue_race(laps: int) -> void:
	_pending_laps = laps

func consume_pending_race() -> int:
	var laps := _pending_laps
	_pending_laps = 0
	return laps

func get_race_time() -> float:
	return _race_time

func start_race(cars: Array, laps: int) -> void:
	for counter in _lap_counters.values():
		(counter as LapCounter).queue_free()
	_lap_counters = {}
	_participants = cars
	total_laps = laps
	_race_time = 0.0
	for car in cars:
		var counter := LapCounter.new()
		_lap_counters[car] = counter
		add_child(counter)
		counter.start_race(laps)
	is_race_active = true
	reset_checkpoints()
	race_started.emit()

func finish_race() -> void:
	is_race_active = false
	var standings := get_standings()
	race_finished.emit(standings)

func get_standings() -> Array:
	## Returns array of cars sorted by progress (lap, then checkpoint, then distance)
	var sorted := _participants.duplicate()
	sorted.sort_custom(func(a: VehiclePhysics, b: VehiclePhysics) -> bool:
		var a_lap: int = _lap_of(a)
		var b_lap: int = _lap_of(b)
		if a_lap != b_lap:
			return a_lap > b_lap
		var a_cp: int = _checkpoint_of(a)
		var b_cp: int = _checkpoint_of(b)
		if a_cp != b_cp:
			return a_cp > b_cp
		return _distance_to_next_checkpoint(a, a_cp) < _distance_to_next_checkpoint(b, b_cp)
	)
	return sorted

func _lap_of(car: VehiclePhysics) -> int:
	var counter: LapCounter = _lap_counters.get(car)
	return counter.get_current_lap() if counter != null else 1

func _checkpoint_of(car: VehiclePhysics) -> int:
	var counter: LapCounter = _lap_counters.get(car)
	return counter.get_last_checkpoint() if counter != null else -1

func _distance_to_next_checkpoint(car: VehiclePhysics, last_checkpoint: int) -> float:
	var cps := _all_checkpoints()
	if cps.is_empty():
		return 0.0
	var next_index := (last_checkpoint + 1) % cps.size()
	var target: Checkpoint = cps[next_index]
	var offset := car.global_position - target.global_position
	return Vector2(offset.x, offset.z).length()

func get_lap_counter(car: VehiclePhysics) -> LapCounter:
	return _lap_counters.get(car)

func reset_checkpoints() -> void:
	for cp in _all_checkpoints():
		cp.reset()

func get_checkpoints() -> Array[Checkpoint]:
	return _all_checkpoints()

func _all_checkpoints() -> Array[Checkpoint]:
	if _checkpoints_dirty or not _cache_valid():
		_checkpoints_cache.clear()
		for node in get_tree().get_nodes_in_group("checkpoints"):
			if node is Checkpoint:
				_checkpoints_cache.append(node)
		_checkpoints_dirty = false
	return _checkpoints_cache

func _cache_valid() -> bool:
	for cp in _checkpoints_cache:
		if not is_instance_valid(cp):
			return false
	return true

func _process(delta: float) -> void:
	if not is_race_active:
		return
	_race_time += delta
	var checkpoints := _all_checkpoints()
	for car in _participants:
		var counter: LapCounter = _lap_counters.get(car)
		if counter == null:
			continue
		for cp in checkpoints:
			if cp.is_passed(car):
				var result := counter.update(car, cp)
				if result["race_finished"]:
					finish_race()
					return
```

Note: `get_standings()` (with the tie-breaks) and `_lap_of`/`_checkpoint_of`/`_distance_to_next_checkpoint` are written here because A4's sort belongs with this rewrite; Task 5 only locks them down with tests. `queue_race`/`consume_pending_race`/`get_race_time` are added now so Task 6 (Play → HUD) and the banner consume them.
- [ ] Run targeted suite: expect PASS (all 5). (The full-suite gate must also stay green on `test_race_loop.gd`'s Task 1/2 tests and the existing 69 — watch that the lap-completion path is not yet wired, which is fine here.)
- [ ] Run import probe clean, full suite green, commit ONLY `autoload/race_manager.gd` and `tests/suites/test_race_loop.gd`. Expected summary `77 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`.

### Task 4 — Re-arm checkpoints on every `lap_completed` (lap-loop continuity)

**Files:**
- Modify `autoload/race_manager.gd`
- Modify `tests/suites/test_race_loop.gd` (append test)

**Interfaces:**
- Consumes: `LapCounter.lap_completed(vehicle: VehiclePhysics, lap: int, time: float)` (existing signal), `reset_checkpoints()` (Task 3).
- Produces: the wiring line `counter.lap_completed.connect(reset_checkpoints)` inside `start_race()`.

- [ ] Write failing test (append):

```gdscript
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
```

- [ ] Run targeted suite: expect FAIL — Task 3's `start_race` does not wire `lap_completed`, so after the second `update` the `_counted` dictionaries still hold the car (`.size()` is 1) and `current_lap` may still be 1.
- [ ] Implement: in `autoload/race_manager.gd` `start_race()`, add one line inside the `for car in cars:` loop, right after `add_child(counter)` and before `counter.start_race(laps)`:

```gdscript
		add_child(counter)
		counter.lap_completed.connect(reset_checkpoints)
		counter.start_race(laps)
```

- [ ] Run targeted suite: expect PASS.
- [ ] Run import probe clean, full suite green, commit ONLY `autoload/race_manager.gd` and `tests/suites/test_race_loop.gd`. Expected summary `78 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`.

### Task 5 — Standings ordering lap → checkpoint → distance (A4)

**Files:**
- Modify `tests/suites/test_race_loop.gd` (append tests) — `get_standings()` implementation already landed in Task 3.

**Interfaces:**
- Consumes: `RaceManager.start_race(cars, laps)`, `get_lap_counter(car).update(vehicle, cp)`, `LapCounter.get_last_checkpoint()`, `Checkpoint.global_position`, `get_standings()`.

- [ ] Write failing tests (append). The distance case drives two cars to the same lap/checkpoint but passes them into `start_race` in the "wrong" order so the lap-only sort cannot match the contract; the second covers lap then checkpoint ordering:

```gdscript
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
```

Note on `test_standings_lap_then_checkpoint_ordering`: pre-fix (lap-only comparator) can only order the three by lap, and the `leader` (unique lap 2) is fine pre-fix; the `ahead` vs `behind` pair equal on lap is where the pre-fix sort is unlucky-or-lucky. The decisive fail-first assertion is `test_standings_distance_tiebreak` (two-car array, all-false lap-level compares leave the inserted `[near, far]` order unchanged, so `standings.find(near_car) == 0` fails pre-fix). If the distance test passes red→green on the try, treat the second test as a contract guard.
- [ ] Run targeted suite: expect FAIL — pre-fix `get_standings()` compares lap only, so `standings.find(near_car)` returns 1 (insertion order preserved) and the first test fails. Second test may or may not fail (unstable sort); Task 3's rewritten `get_standings()` is what must make both pass.
- [ ] Verify (no further implementation needed — the Task 3 `get_standings()` already implements the contract; if the distance test unexpectedly passed pre-fix, confirm the comparator uses `_distance_to_next_checkpoint` and rerun after a `touch`-free restart). Run targeted suite: expect PASS.
- [ ] Run import probe clean, full suite green, commit ONLY `tests/suites/test_race_loop.gd`. Expected summary `80 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`.

### Task 6 — Play → race start → live HUD + finish banner (A1)

**Files:**
- Modify `scripts/ui/track_select.gd`
- Modify `scripts/race/race_ui.gd`
- Modify `tests/suites/test_race_loop.gd` (append tests)
- Modify `tests/test_track_system.gd` (one hygiene line in the existing play test; keeps it green w.r.t. the new `queue_race` side effect)

**Interfaces:**
- Consumes: `TrackRegistry.get_scene_path/get_track` (`laps_default`), `RaceManager.queue_race`/`consume_pending_race`/`start_race`/`get_lap_counter`/`get_standings`/`race_finished`/`get_race_time`, `VehicleManager.get_all_cars()`, `VehiclePhysics.get_drive_info()`, `LapCounter.get_current_lap()/get_lap_time()/get_total_time()`.
- Produces: `race_ui` gains `_ready()` (latch pending + connect `race_finished`) and a first-frame commit in `_process()`; `_on_race_finished(standings)` freezes the HUD and shows the FINISH banner.

- [ ] Modify `scripts/ui/track_select.gd` `_on_play_pressed()` (lines 107-110) to queue the race before launching:

```gdscript
func _on_play_pressed() -> void:
	if _selected_id == "":
		return
	var scene_path := TrackRegistry.get_scene_path(_selected_id)
	var laps := int(TrackRegistry.get_track(_selected_id).get("laps_default", 3))
	RaceManager.queue_race(laps)
	launch_callback.call(scene_path)
```

- [ ] Modify `scripts/race/race_ui.gd` (add `_pending_laps`/`_race_over` members, `_ready()`, commit in `_process()`, `_on_race_finished()`; keep cluster/gauges updating every frame, freeze position/lap/time once the race is over):

```gdscript
# scripts/race/race_ui.gd
extends CanvasLayer

## In-race HUD: drives the Forza-style gauge cluster (tach/speed/gear) plus
## position, lap and lap-time readouts, and the FINISH banner.

@onready var cluster: Tachometer = %Cluster
@onready var lap_label: Label = %LapLabel
@onready var position_label: Label = %PositionLabel
@onready var time_label: Label = %TimeLabel

var _pending_laps: int = 0
var _race_over: bool = false

func _ready() -> void:
	_pending_laps = RaceManager.consume_pending_race()
	RaceManager.race_finished.connect(_on_race_finished)

func _process(_delta: float) -> void:
	if _pending_laps > 0:
		var laps := _pending_laps
		_pending_laps = 0
		RaceManager.start_race(VehicleManager.get_all_cars(), laps)
	var car := VehicleManager.get_player_car()
	if car == null:
		return

	var info := car.get_drive_info()
	cluster.set_rpm(float(info["rpm"]))
	cluster.set_gear(int(info["gear"]))
	cluster.set_speed_kmh(float(info["speed_kmh"]))
	var cfg := car.config
	if cfg != null:
		cluster.set_engine_range(cfg.idle_rpm, cfg.redline_rpm)
		cluster.set_car_class(cfg.car_class)
	if _race_over:
		return
	position_label.text = _position_text(car)
	var lap_counter := RaceManager.get_lap_counter(car)
	lap_label.text = "LAP %d" % (lap_counter.get_current_lap() if lap_counter else 1)
	time_label.text = "%.3f" % (lap_counter.get_lap_time() if lap_counter else 0.0)

func _on_race_finished(standings: Array) -> void:
	_race_over = true
	if standings.is_empty():
		return
	var winner: VehiclePhysics = standings[0]
	var counter := RaceManager.get_lap_counter(winner)
	var total := counter.get_total_time() if counter else 0.0
	position_label.text = "FINISH  %.2fs" % total
	lap_label.text = "RACE TIME %.2fs" % RaceManager.get_race_time()

func _position_text(car: VehiclePhysics) -> String:
	if RaceManager.get_lap_counter(car) == null:
		return "P1"
	var standings := RaceManager.get_standings()
	if standings.is_empty():
		return "P1"
	var index := standings.find(car)
	return "P%d" % (index + 1) if index != -1 else "-"
```

- [ ] Write failing tests (append to `tests/suites/test_race_loop.gd`):

```gdscript
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
	var scene := runner.scene() as Control
	var label := scene.get_node("%PositionLabel") as Label
	var car := _new_stub_car()
	RaceManager.start_race([car], 3)
	RaceManager.finish_race()
	assert_that(label.text.contains("FINISH")).is_true()
	RaceManager.consume_pending_race()
```

- [ ] Modify `tests/test_track_system.gd` `test_track_select_play_loads_selected_scene` (lines 40-56): after the final `assert_that(launched[...])`, add `RaceManager.consume_pending_race()` so the `queue_race` side effect added by Task 6 does not bleed into later tests.
- [ ] Run targeted suite: expect FAIL — pre-fix `queue_race`/`consume_pending_race` do not exist (`test_track_select_play_queues_race` parse error), and the HUD never calls `start_race` (`test_hud_commits_pending_race_on_first_frame` fails on `is_race_active`).
- [ ] Implement the two `_on_play_pressed` / `race_ui` edits above (already applied in the Modify steps; confirm both files reflect them and the import probe is clean).
- [ ] Run full suite (not just the targeted file, because `tests/test_track_system.gd` also changed):
  expect `83 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans` and the import probe clean.
- [ ] Commit ONLY `scripts/ui/track_select.gd`, `scripts/race/race_ui.gd`, `tests/suites/test_race_loop.gd`, `tests/test_track_system.gd`.

## Self-Review

- **A1 (Play starts a race):** Task 6 — `track_select._on_play_pressed()` → `queue_race(laps_default)`; `race_ui._ready()` latches, first-frame commit → `start_race(VehicleManager.get_all_cars(), laps)`; verified by `test_track_select_play_queues_race`, `test_hud_commits_pending_race_on_first_frame`, plus pre-existing `test_track_select_play_loads_selected_scene` kept green with the one-line hygiene edit.
- **A2 (`_race_start_time` unassigned):** Task 1 — set in `LapCounter.start_race()`, declaration moved to the var block; verified by `test_total_time_is_relative_to_race_start`.
- **A3 (checkpoint `reset()` / `active` gate):** Task 2 — `is_passed` once-per-pass via `_counted`, `reset()` arms + clears; Task 3 — `start_race()` → `reset_checkpoints()` on the cached group; Task 4 — re-arm per `lap_completed` so a checkpoint is countable once per lap. Verified by tasks 2-4 tests (esp. `test_checkpoint_reset_arms_and_counts_once_per_pass`, `test_start_race_arms_existing_checkpoints`, `test_checkpoints_rearm_after_lap_completed`).
- **A4 (standings tie-breaks):** Task 5 — Task 3's `get_standings()` sorts lap → checkpoint → distance (with `get_last_checkpoint()` accessor from Task 1); verified by `test_standings_distance_tiebreak` and `test_standings_lap_then_checkpoint_ordering`.
- **A5 (per-frame group rescan, LapCounter leak, dead `_race_time`):** Task 3 — cached `_all_checkpoints()` (dirty-on-scene-change + freed-instance healing), `start_race()` frees old LapCounter children, `get_race_time()` exposed and consumed by the FINISH banner in Task 6. Verified by `test_checkpoint_cache_is_not_rescanned_within_scene`, `test_checkpoint_cache_recovers_after_nodes_freed`, `test_start_race_twice_does_not_leak_lap_counters`, `test_start_race_with_empty_checkpoint_group_stays_active`.
- **D1 (coverage gaps):** new `tests/suites/test_race_loop.gd` (14 tests) covers lap progression (Task 4 test drives updates through a lap), race finish (`test_hud_shows_finish_banner_on_race_finished` + LapCounter `race_finished` path), `get_total_time` sanity, standings ordering, checkpoint reset lifecycle, group caching, and no LapCounter leak across two `start_race` calls.

**Placeholder scan:** no TODOs, TBDs, "similar to Task N" references, or pseudo-code remain — every test and implementation block above is final code matching the real current signatures read from the repo (`lap_counter.gd`, `checkpoint.gd`, `race_manager.gd`, `race_ui.gd`, `track_select.gd`, `track_registry.gd`, `vehicle_manager.gd`, `vehicle_physics.gd`, `scene_transition.gd`, `game_state.gd`, existing test suites). No files are modified by this document.