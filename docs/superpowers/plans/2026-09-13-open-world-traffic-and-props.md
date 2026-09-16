# Open World Traffic + Props Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire traffic + props into the open world: fix the `TrafficSpawner` spawn bug (A9), harden its lifecycle into a budgeted spawn–despawn–activate–replenish loop only around the player (C1/D5), and attach the Phase-5 prop layers (guardrails along road chains + scattered presets per zone) to `open_world_root.tscn` with terrain-grounded placement and distance-based hide gating (C2). Full suite stays `0 errors | 0 failures`, orphan count does NOT grow past the 16 baseline, and the `!is_inside_tree()` error flood drops from 65 lines to 0.

**Architecture:**
- `TrafficSpawner` (existing world script, currently instantiated by NO scene) becomes the single traffic manager, wired as an additive child of `OpenWorldRoot`. It already has `update(player_pos)`; we extend its lifecycle: **despawn** beyond `despawn_distance` (budgeted per tick), **activate** a `TrafficDriver` AI child for vehicles inside `active_radius`, **despawn-activated** park vehicles at rest when the player recedes, **replenish** up to `max_traffic` (budgeted spawns per tick). Spawn bug (C1/A9): a spawning vehicle is placed by its LOCAL `position` BEFORE `add_child()` (never `global_position`, which errors off-tree and creates orphans), and player-only children (`PlayerCarController`, `CarAudio`) are stripped before `add_child()` so traffic never hijacks the `VehicleManager.player_car` registry or loads the garage.
- New `scripts/world/traffic_driver.gd` (`TrafficDriver extends Node`, child of each active traffic `VehiclePhysics`): cruises via `set_input_override(Vector2)` toward a look-ahead point on the nearest road chain — the codebase already ships the AI hook (`VehiclePhysics.set_input_override`, `VehicleManager.register_ai_car`).
- `PropScatterer` gains one new deterministic placement mode `"mode": "along_road"` (guardrail posts walked along road chains at a fixed lateral offset), for the highlands pass. Its existing scattered presets (`default_preset()`) cover the other zones.
- New `scripts/world/world_dressing.gd` (`WorldDressing extends Node3D`, additive child of `OpenWorldRoot`): builds the five §5 biome prop zones (festival/lowlands/coast/highlands/alpine) anchored at POI centers, wires each `PropScatterer` to a `ground_height_provider` lambda reading `terrain.data.get_height()` (anchor-relative local XZ → world height, the same callable pattern as `mountain_pass.gd::_make_ground_height_provider`), passes the shared `RoadNetwork`, **generates lazily** on first approach (regions under the player are already baked then) and **hides beyond `hide_distance`** so props never float over streamed-out Terrain3D regions. Traffic despawns outright past `despawn_distance`; props are cheated back (visibility-gated, never re-baked) because MultiMesh batches are cheap.
- `WorldDriver._push_player_position()` (already the single per-tick player read feeding `ChunkStreamer` + `TerrainSeeder`) additionally drives `TrafficSpawner.update(player_pos)` and `WorldDressing.update(player_pos)`, keeping traffic/props strictly inside the baked region window.
- Decision — scene attachment: both are **additive nodes authored in `open_world_root.tscn`** (not runtime `new()` by a parent), mirroring `ChunkStreamer`/`TerrainSeeder`, so the scene graph is inspectable and `test_open_world` can find them by name. Programmatic wiring (callables/providers) lives in `WorldDressing`, not the scene file.

**Tech Stack:** Godot 4.7.2 GDScript, GDUnit4

**Spec:** inventory C1, C2, A9, D5 (see preamble)

## Preamble — verified inventory (2026-09-13)

- **C1** — `scripts/world/traffic_spawner.gd` is complete + unit-tested but instantiated by NO scene; the open world has no AI traffic.
- **A9** — `traffic_spawner.gd:41-42` runs `vehicle.global_position = spawn_pos` BEFORE `add_child(vehicle)` → 11× `Condition "!is_inside_tree()" is true` engine errors + 6 orphans in its test. Current full-suite `_gdunit.txt` shows the string `!is_inside_tree() is true` 65 times total and `Overall Summary: 69 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`.
- **D5** — tests only cover placement-on-road: no despawn-distance, no replenish, no null-`vehicle_scene` path.
- **C2** — `scripts/world/prop_scatterer.gd` (guardrail/tent/power-pole/rock presets in `default_preset()`) is unwired; the Phase-5 festival/lowlands/coast/highlands/alpine prop layers from `docs/plan_open_world_seeding.md` §5 never attached to `scenes/world/open_world_root.tscn`.

## Global Constraints

- **Indentation:** match the **target file's existing indentation**, never reformat untouched lines. `scripts/world/traffic_spawner.gd` and `road_network.gd` are **4-space** indented; `world_driver.gd`, `prop_scatterer.gd`, `foliage.gd`, `terrain_seeder.gd`, and every NEW file (`traffic_driver.gd`, `world_dressing.gd`) use **TAB** indentation.
- **Never `git add -A`.** Stage the specific files each task touches; never stage `*.uid`, `_gdunit.txt`, `diag/`, or the other untracked mud-strewn run artifacts. `git status --short` must never list `*.uid` (they are gitignored).
- **Do not touch** `AGENTS.md`, `start_game.bat`, `play_game.bat`, `.godot/`, or any docs file except this plan.
- **GDUnit4 treats GDScript warnings as errors** (a script that warns fails to load): no `:=` on Variant-returning calls (`instantiate()` must be `var x := scene.instantiate() as VehiclePhysics`, provider lookups must be typed or `as`-cast, dictionary reads assigned to typed locals, dictionary writes via typed copies). Vector `is_equal_approx` needs a same-type approx arg.
- **Verification recipe (KNOWN-GOOD, sequential, never concurrent):**
  1. Import/probe: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import . 2>&1 | findstr /i "SCRIPT ERROR Parse Error Failed to load"` → expect ZERO matches (benign `resources still in use at exit` and Terrain3D whitelist lines allowed).
  2. Suite (flag AFTER the tool-script path): `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1` then `findstr /c:"Overall Summary:" _gdunit.txt`.
  3. Error-flood gate: `findstr /c:"Condition \"!is_inside_tree()\" is true" _gdunit.txt` → must print 0 lines after Task 2 (was 65). Orphan gate: summary's orphan number must stay ≤ 16.
- **Baseline:** `69 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`. Expected after this plan: **76 test cases** (5 new traffic + 1 new prop + 1 new open-world) with `0 errors | 0 failures` and orphans ≤ 16. Report the *actual* suite number in every task's PASS step; never edit AGENTS.md to claim a number the run didn't print.
- **Every task ends with the two verification steps of the recipe** (STOP at the first red gate — that means the previous step's story is wrong, go back and fix it, do not paper over it).
- Commit after each green task with a short conventional message scoped to that task.

---

## Task 1 — Baseline capture (no code changes)

**Files:** none written.

**Interfaces:** Consumes none; Produces a factual snapshot only.

**Steps:**
- [ ] Run the probe step (`--headless --import .` + `findstr`), confirm zero `SCRIPT ERROR` / `Parse Error` / `Failed to load`.
- [ ] Run the full suite step; record `findstr /c:"Overall Summary:" _gdunit.txt` (expect `69 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`).
- [ ] Run the error-flood gate; record the count of `Condition "!is_inside_tree()" is true` lines (expect 65) and note whether the traffic test block is a major source.
- [ ] `git status --short`: confirm NO `*.uid` entries. No commit (nothing changed).

---

## Task 2 — A9: fix spawn order + traffic spawn hygiene (impl-first; the existing test already reproduces the defect as errors/orphans)

**Files:** `scripts/world/traffic_spawner.gd` (edit — keep its existing 4-space indent).

**Interfaces:**
- Consumes (unchanged): `@export var vehicle_scene: PackedScene`, `@export var max_traffic: int = 15`, `@export var spawn_radius: float = 300.0`, `@export var road_network: RoadNetwork`, `update(player_pos: Vector3) -> void`, `_random_offset() -> Vector3`, `RoadNetwork.is_on_road(pos: Vector3, threshold: float) -> bool`, `RoadNetwork.get_nearest_road_pos(pos: Vector3) -> Vector3`.
- Produces (new/changed):
  - `@export var active_radius: float = 120.0` — inside this distance traffic gets a `TrafficDriver`; outside it is parked.
  - `@export var despawn_distance: float = 400.0` — hard despawn radius (replaces the magic `spawn_radius + 100`).
  - `@export var spawns_per_update: int = 2` — replenish budget per `update()` call.
  - `@export var despawns_per_update: int = 4` — removal budget per `update()` call.
  - `func clear() -> void` — frees every managed vehicle and empties `_traffic` (test/suite-orphan hygiene).
  - `func get_live_count() -> int` — returns `_traffic.size()`.
  - `func _spawn_vehicle(player_pos: Vector3) -> bool` — changed return type from `void`; false when a vehicle refused/spawn skipped.
  - `func _strip_player_children(vehicle: VehiclePhysics) -> void`.
  - `const PLAYER_CHILDREN_TO_STRIP := ["PlayerCarController", "CarAudio"]`.
- **Consumed by:** Task 3 tests and later tasks. **Produced for:** o `_traffic` invariant — every appended vehicle is `is_instance_valid` and in-tree.

**Steps:**
- [ ] In `_spawn_vehicle`, after computing `spawn_pos`, replace the buggy block with:
  ```gdscript
  	var vehicle := vehicle_scene.instantiate() as VehiclePhysics
  	if vehicle == null:
  		return false
  	_strip_player_children(vehicle)
  	vehicle.position = spawn_pos
  	add_child(vehicle)
  	vehicle.can_sleep = true
  	_traffic.append(vehicle)
  	return true
  ```
  (`vehicle.position` is the LOCAL position — safe off-tree; `TrafficSpawner` is a plain `Node` under an identity `Node3D`, so local == world. `VehiclePhysics._ready` then sees the correct `_spawn_point = global_position` instead of the origin.)
- [ ] Add `_strip_player_children` (removes `PlayerCarController`/`CarAudio` BEFORE `add_child` so their `_ready` never runs — traffic must never call `VehicleManager.register_player_car` or load `Garage.new_from_save()`):
  ```gdscript
  func _strip_player_children(vehicle: VehiclePhysics) -> void:
  	for child_name in PLAYER_CHILDREN_TO_STRIP:
  		var child := vehicle.get_node_or_null(child_name)
  		if child != null:
  			vehicle.remove_child(child)
  			child.queue_free()
  ```
- [ ] Restructure `update` into the budgeted lifecycle skeleton (driver logic hooks land in Task 4; `_apply_budget` is a no-op shell until then):
  ```gdscript
  func update(player_pos: Vector3) -> void:
  	_remove_far(player_pos)
  	_apply_budget(player_pos)
  	_replenish(player_pos)
  ```
- [ ] Add `_remove_far` (budgeted desktop; mirrors the existing `_traffic.duplicate()` iteration pattern so GDUnit stays happy with the untyped loop var):
  ```gdscript
  func _remove_far(player_pos: Vector3) -> void:
  	var budget: int = despawns_per_update
  	for vehicle in _traffic.duplicate():
  		if budget <= 0:
  			break
  		if vehicle.global_position.distance_to(player_pos) > despawn_distance:
  			_remove_vehicle(vehicle)
  			budget -= 1
  ```
- [ ] Add `_remove_vehicle(vehicle: VehiclePhysics) -> void` (single teardown path reused by despawn + `clear()` + its own strip bookkeeping):
  ```gdscript
  func _remove_vehicle(vehicle: VehiclePhysics) -> void:
  	_deactivate(vehicle)
  	vehicle.queue_free()
  	_traffic.erase(vehicle)
  ```
- [ ] Add `_replenish`, `get_live_count`, `clear`, and the temporary `_apply_budget`/`_deactivate` stubs (Task 4 fleshes them out): replacement and activation shell:
  ```gdscript
  func _replenish(player_pos: Vector3) -> void:
  	var budget: int = spawns_per_update
  	while _traffic.size() < max_traffic and budget > 0:
  		if not _spawn_vehicle(player_pos):
  			return
  		budget -= 1

  func get_live_count() -> int:
  	return _traffic.size()

  func clear() -> void:
  	for vehicle in _traffic:
  		if is_instance_valid(vehicle):
  			vehicle.queue_free()
  	_traffic.clear()

  func _apply_budget(player_pos: Vector3) -> void:
  	pass  # Task 4

  func _deactivate(vehicle: VehiclePhysics) -> void:
  	vehicle.set_input_override(Vector2.ZERO)
  	vehicle.sleeping = true
  	vehicle.can_sleep = true
  ```
- [ ] Run the probe; then the full suite; then the error-flood gate: `findstr` count for `!is_inside_tree() is true` must be **0** (was 65).
- [ ] Confirm suite summary `0 errors | 0 failures` and orphans ≤ 16; record actual suite count.
- [ ] Stage ONLY `scripts/world/traffic_spawner.gd` and commit: `fix(A9): traffic spawn sets local position before add_child; strip player-only children; add budgeted despawn/replenish lifecycle skeleton`.

---

## Task 3 — D5: expand traffic unit tests (despawn, replenish, null scene, in-tree invariant) — test-first

**Files:** `tests/test_traffic_spawner.gd` (edit).

**Interfaces:**
- Consumes: all Task 2 traffic API (`despawn_distance`, `spawns_per_update`, `despawns_per_update`, `get_live_count`, `clear`, `_spawn_vehicle -> bool`), existing helpers `_build_ring()`, `RoadNetwork.add_road(points, width)`, `player_car.tscn` as `PackedScene`.
- Produces (test helpers + 4 new tests):
  - `func _make_spawner(road_network: RoadNetwork) -> TrafficSpawner` — spawner with `road_network`, `vehicle_scene = load("res://scenes/vehicle/player_car.tscn")`, `max_traffic = 6`, `spawn_radius = 220.0`, `spawns_per_update = 2`, `despawns_per_update = 6`, added via `add_child`.
  - `func _live_count(spawner: TrafficSpawner) -> int` — counts direct `VehiclePhysics` children.
  - `func _live_vehicles(spawner: TrafficSpawner) -> Array[VehiclePhysics]`.
  - `func test_traffic_despawns_beyond_despawn_distance() -> void`.
  - `func test_traffic_replenishes_after_despawn() -> void`.
  - `func test_null_vehicle_scene_never_spawns() -> void`.
  - `func test_spawned_vehicles_are_in_tree_with_correct_position() -> void`.

**Steps:**
- [ ] Add the helpers:
  ```gdscript
  func _make_spawner(road_network: RoadNetwork) -> TrafficSpawner:
  	var spawner := TrafficSpawner.new()
  	spawner.road_network = road_network
  	spawner.vehicle_scene = load("res://scenes/vehicle/player_car.tscn")
  	spawner.max_traffic = 6
  	spawner.spawn_radius = 220.0
  	spawner.spawns_per_update = 2
  	spawner.despawns_per_update = 6
  	add_child(spawner)
  	return spawner

  func _live_count(spawner: TrafficSpawner) -> int:
  	var count := 0
  	for child in spawner.get_children():
  		if child is VehiclePhysics:
  			count += 1
  	return count

  func _live_vehicles(spawner: TrafficSpawner) -> Array[VehiclePhysics]:
  	var result: Array[VehiclePhysics] = []
  	for child in spawner.get_children():
  		if child is VehiclePhysics:
  			result.append(child)
  	return result
  ```
- [ ] Despawn-distance test (fails if despawn distance isn't honoured):
  ```gdscript
  func test_traffic_despawns_beyond_despawn_distance() -> void:
  	var road_network := auto_free(RoadNetwork.new()) as RoadNetwork
  	add_child(road_network)
  	road_network.add_road(_build_ring(), ROAD_WIDTH)
  	var spawner := auto_free(_make_spawner(road_network))
  	spawner.despawn_distance = 400.0
  	for _frame in range(120):
  		spawner.update(PLAYER_POS)
  	assert_that(_live_count(spawner)).is_greater(0)
  	for _frame in range(200):
  		spawner.update(Vector3(9000.0, 0.0, 9000.0))
  	assert_that(_live_count(spawner)).is_equal(0)
  	assert_that(spawner.get_live_count()).is_equal(0)
  	spawner.clear()
  	await get_tree().process_frame
  ```
- [ ] Replenish test:
  ```gdscript
  func test_traffic_replenishes_after_despawn() -> void:
  	var road_network := auto_free(RoadNetwork.new()) as RoadNetwork
  	add_child(road_network)
  	road_network.add_road(_build_ring(), ROAD_WIDTH)
  	var spawner := auto_free(_make_spawner(road_network))
  	for _frame in range(120):
  		spawner.update(PLAYER_POS)
  	var before := _live_count(spawner)
  	assert_that(before).is_greater(0)
  	for _frame in range(200):
  		spawner.update(Vector3(9000.0, 0.0, 9000.0))
  	assert_that(_live_count(spawner)).is_equal(0)
  	for _frame in range(300):
  		spawner.update(PLAYER_POS)
  	assert_that(_live_count(spawner)).is_equal(before)
  	spawner.clear()
  	await get_tree().process_frame
  ```
- [ ] Null-`vehicle_scene` test (D5 gap):
  ```gdscript
  func test_null_vehicle_scene_never_spawns() -> void:
  	var road_network := auto_free(RoadNetwork.new()) as RoadNetwork
  	add_child(road_network)
  	road_network.add_road(_build_ring(), ROAD_WIDTH)
  	var spawner := auto_free(_make_spawner(road_network))
  	spawner.vehicle_scene = null
  	for _frame in range(200):
  		spawner.update(PLAYER_POS)
  	assert_that(spawner.get_live_count()).is_equal(0)
  	assert_that(_live_count(spawner)).is_equal(0)
  ```
- [ ] No-add-before-`add_child` invariant test (direct regression guard for A9 — fails loudly if the spawn-ordering bug returns):
  ```gdscript
  func test_spawned_vehicles_are_in_tree_with_correct_position() -> void:
  	var road_network := auto_free(RoadNetwork.new()) as RoadNetwork
  	add_child(road_network)
  	road_network.add_road(_build_ring(), ROAD_WIDTH)
  	var spawner := auto_free(_make_spawner(road_network))
  	for _frame in range(60):
  		spawner.update(PLAYER_POS)
  	var live := _live_vehicles(spawner)
  	assert_that(live.size()).is_greater(0)
  	for vehicle: VehiclePhysics in live:
  		assert_that(vehicle.is_inside_tree()).is_true()
  		assert_that(spawner.is_ancestor_of(vehicle)).is_true()
  		assert_that(road_network.is_on_road(vehicle.global_position, 10.0)).is_true()
  	spawner.clear()
  	await get_tree().process_frame
  ```
- [ ] Run the suite: the new tests FAIL on the pre-Task-2 code if re-run there; on current code they must PASS (evidence each D5 gap is now pinned). Then the error-flood gate still shows 0 and orphans ≤ 16.
- [ ] Convert the old "error-print" observation into a hard gate: after the run, `findstr /c:"Condition \"!is_inside_tree()\" is true" _gdunit.txt` prints nothing — that is the assert-clean conversion.
- [ ] Stage `tests/test_traffic_spawner.gd` and commit: `test(D5): traffic despawn-distance, replenish, null vehicle_scene, in-tree spawn invariant`.

---

## Task 4 — C1: TrafficDriver AI + activate/deactivate lifecycle (test-first)

**Files:** `scripts/world/traffic_driver.gd` (new, TAB indent), `scripts/world/traffic_spawner.gd` (edit — `_apply_budget`, `_activate`, `_driver_of`), `tests/test_traffic_spawner.gd` (edit — +1 test).

**Interfaces:**
- Consumes: `RoadNetwork.get_nearest_road_pos(pos: Vector3) -> Vector3`, `VehiclePhysics.set_input_override(value: Vector2)`, `VehiclePhysics.global_basis`, `VehiclePhysics.can_sleep`, `VehiclePhysics.sleeping`.
- Produces (`traffic_driver.gd`):
  - `class_name TrafficDriver extends Node`
  - `const LOOKAHEAD := 12.0`, `const CRUISE_THROTTLE := 0.55`, `const STEER_GAIN := 2.4`
  - `func setup(network: RoadNetwork) -> void`
  - `func _physics_process(_delta: float) -> void`
- Consumed by: `TrafficSpawner._activate` (attaches driver as child named `"TrafficDriver"`), `TrafficSpawner._driver_of`.

**Steps:**
- [ ] Write the FAILING activation test first:
  ```gdscript
  func test_traffic_activates_driver_near_player_and_parks_far() -> void:
  	var road_network := auto_free(RoadNetwork.new()) as RoadNetwork
  	add_child(road_network)
  	road_network.add_road(_build_ring(), ROAD_WIDTH)
  	var spawner := auto_free(_make_spawner(road_network))
  	spawner.active_radius = 300.0
  	spawner.despawn_distance = 600.0
  	for _frame in range(60):
  		spawner.update(PLAYER_POS)
  	for vehicle: VehiclePhysics in _live_vehicles(spawner):
  		assert_that(vehicle.get_node_or_null("TrafficDriver")).is_not_null()
  	var mid_pos := Vector3(520.0, 0.0, 520.0)
  	for _frame in range(60):
  		spawner.update(mid_pos)
  	for vehicle: VehiclePhysics in _live_vehicles(spawner):
  		if vehicle.global_position.distance_to(mid_pos) > 300.0:
  			assert_that(vehicle.get_node_or_null("TrafficDriver")).is_null()
  	spawner.clear()
  	await get_tree().process_frame
  ```
  (Runs RED now — no driver exists yet.)
- [ ] Create `traffic_driver.gd`:
  ```gdscript
  # scripts/world/traffic_driver.gd
  class_name TrafficDriver
  extends Node

  ## Minimal road-following AI for traffic: looks a fixed distance up the nearest
  ## road chain, steers toward that point, cruises at a constant throttle. Input
  ## is pushed through VehiclePhysics.set_input_override(), never the InputManager.
  ## No pathfinding, no collision avoidance, no overtaking.

  const LOOKAHEAD := 12.0
  const CRUISE_THROTTLE := 0.55
  const STEER_GAIN := 2.4

  var _network: RoadNetwork
  var _vehicle: VehiclePhysics

  func setup(network: RoadNetwork) -> void:
  	_network = network
  	_vehicle = get_parent() as VehiclePhysics

  func _physics_process(_delta: float) -> void:
  	if _vehicle == null or _network == null:
  		return
  	var forward := -_vehicle.global_basis.z
  	forward.y = 0.0
  	if forward.length() < 0.001:
  		forward = Vector3.FORWARD
  	forward = forward.normalized()
  	var look_pos := _network.get_nearest_road_pos(_vehicle.global_position + forward * LOOKAHEAD)
  	var to_road := look_pos - _vehicle.global_position
  	to_road.y = 0.0
  	var steer := 0.0
  	if to_road.length() > 0.01:
  		steer = clampf(forward.cross(to_road.normalized()).y * STEER_GAIN, -1.0, 1.0)
  	_vehicle.set_input_override(Vector2(steer, CRUISE_THROTTLE))
  ```
- [ ] Fill in `_apply_budget`, `_activate`, `_driver_of` in `traffic_spawner.gd` (replacing the Task 2 stub; keep `_deactivate` as-is):
  ```gdscript
  func _apply_budget(player_pos: Vector3) -> void:
  	if road_network == null:
  		return
  	for vehicle in _traffic:
  		var distance := vehicle.global_position.distance_to(player_pos)
  		if distance <= active_radius and _driver_of(vehicle) == null:
  			_activate(vehicle)
  		elif distance > active_radius and _driver_of(vehicle) != null:
  			_deactivate(vehicle)

  func _activate(vehicle: VehiclePhysics) -> void:
  	if road_network == null:
  		return
  	var driver := TrafficDriver.new()
  	driver.name = "TrafficDriver"
  	vehicle.add_child(driver)
  	driver.setup(road_network)
  	vehicle.can_sleep = false
  	vehicle.sleeping = false

  func _driver_of(vehicle: VehiclePhysics) -> TrafficDriver:
  	return vehicle.get_node_or_null("TrafficDriver") as TrafficDriver
  ```
- [ ] Run the probe, then the suite: the new activation test and all existing traffic/open-world tests PASS; error-flood gate still 0; orphans ≤ 16.
- [ ] Stage `scripts/world/traffic_driver.gd`, `scripts/world/traffic_spawner.gd`, `tests/test_traffic_spawner.gd` and commit: `feat(C1): TrafficDriver AI + budgeted activate/despawn lifecycle in TrafficSpawner`.

---

## Task 5 — C2a: `along_road` placement mode in PropScatterer (test-first)

**Files:** `scripts/world/prop_scatterer.gd` (edit — TAB indent), `tests/test_prop_scatterer.gd` (edit — +1 test).

**Interfaces:**
- Consumes (unchanged): `road_network: RoadNetwork`, `ground_height_provider: Callable`, `_spacing_ok(pos: Vector2, used: Array[Vector2], min_spacing: float) -> bool`, `_ground_height(pos: Vector2) -> float`, `RoadNetwork.get_roads() -> Array[Array]`.
- Produces:
  - Placement entry keys: `"mode": "along_road"`, `"count": int`, `"chain_spacing": float`, `"road_offset": float`, `"min_spacing": float`, `"chain_radius": float` (world m; skip segments farther than this from `"center"`), `"center": Vector3` (world anchor).
  - `func _place_props_along_road(entry: Dictionary) -> PackedVector3Array` — local coords (world − center), matching the anchor-relative `_ground_height` convention.
  - `func _chain_is_closed(chain: Array) -> bool` — true when first≈last within ~2× avg spacing (same rule as `terrain_baker._chain_is_closed`).
- **Consumed by:** `WorldDressing._prepare_preset` (Task 6) and the new unit test.

**Steps:**
- [ ] Write the FAILING prop test first (guardrails must sit in a lateral band on one side of the road; a plain scatter fails the band assert):
  ```gdscript
  const GUARDRAIL_OFFSET := 6.5

  func test_along_road_places_guardrails_in_lateral_band_of_chain() -> void:
  	var roads := auto_free(RoadNetwork.new()) as RoadNetwork
  	var chain := _synthetic_road(24)  # a straight diagonal, world coords
  	roads.add_road(chain, 12.0)
  	var scatterer := auto_free(PropScatterer.new()) as PropScatterer
  	scatterer.road_network = roads
  	scatterer.configure({
  		"seed": 1,
  		"props": {
  			"guardrail": {
  				"mode": "along_road", "count": 10, "chain_spacing": 12.0,
  				"road_offset": GUARDRAIL_OFFSET, "min_spacing": 6.0,
  				"chain_radius": 400.0, "center": Vector3.ZERO,
  			},
  		},
  	})
  	scatterer.generate()
  	var placed := scatterer.get_instance_transforms("guardrail")
  	assert_that(placed.size()).is_equal(10)
  	for i in placed.size():
  		var p: Vector3 = placed[i]
  		# Local coords: distance from the diagonal must stay within offset band.
  		var lat := abs(p.x - p.z) / sqrt(2.0)
  		assert_that(lat).is_greater(GUARDRAIL_OFFSET - 1.5)
  		assert_that(lat).is_less(GUARDRAIL_OFFSET + 1.5)
  ```
- [ ] In `_place_prop`, add the mode dispatch at the top (scatter branch unchanged below):
  ```gdscript
  func _place_prop(entry: Dictionary) -> PackedVector3Array:
  	if String(entry.get("mode", "scatter")) == "along_road":
  		return _place_props_along_road(entry)
  	var count := int(entry.get("count", 0))
  	# ... existing scatter body untouched ...
  ```
- [ ] Add `_place_props_along_road` and `_chain_is_closed` (deterministic, no RNG, bounded by `count`):
  ```gdscript
  func _place_props_along_road(entry: Dictionary) -> PackedVector3Array:
  	if road_network == null:
  		return PackedVector3Array()
  	var count := int(entry.get("count", 0))
  	var chain_spacing := maxf(float(entry.get("chain_spacing", 12.0)), 1.0)
  	var road_offset := float(entry.get("road_offset", 6.0))
  	var min_spacing := float(entry.get("min_spacing", 6.0))
  	var chain_radius := float(entry.get("chain_radius", 0.0))
  	var center: Vector3 = entry.get("center", Vector3.ZERO)
  	if chain_radius <= 0.0:
  		return PackedVector3Array()
  	var used: Array[Vector2] = []
  	var result := PackedVector3Array()
  	for chain: Array in road_network.get_roads():
  		var closed := _chain_is_closed(chain)
  		for i in range(chain.size()):
  			if not closed and i + 1 >= chain.size():
  				break
  			var a: Vector3 = chain[i]
  			var b: Vector3 = chain[(i + 1) % chain.size()]
  			var a_world := Vector3(a.x, 0.0, a.z)
  			var b_world := Vector3(b.x, 0.0, b.z)
  			if center.distance_to(a_world.lerp(b_world, 0.5)) > chain_radius:
  				continue
  			var dir := b_world - a_world
  			var seg_len := dir.length()
  			if seg_len < 0.001:
  				continue
  			dir /= seg_len
  			var side := Vector3(-dir.z, 0.0, dir.x)
  			var d := 0.0
  			while d < seg_len and result.size() < count:
  				var t := d / seg_len
  				var base := a_world.lerp(b_world, t) + side * road_offset
  				var local := base - center
  				var local_2d := Vector2(local.x, local.z)
  				if _spacing_ok(local_2d, used, min_spacing):
  					used.append(local_2d)
  					result.append(Vector3(local.x, _ground_height(local_2d), local.z))
  				d += chain_spacing
  			if result.size() >= count:
  				return result
  	return result

  func _chain_is_closed(chain: Array) -> bool:
  	if chain.size() < 2:
  		return false
  	var first: Vector3 = chain[0]
  	var last: Vector3 = chain[chain.size() - 1]
  	var spacing := 0.0
  	for i in range(1, chain.size()):
  		spacing += (chain[i - 1] as Vector3).distance_to(chain[i] as Vector3)
  	spacing /= float(chain.size() - 1)
  	return first.distance_to(last) <= spacing * 2.0
  ```
- [ ] Run probe + suite: new prop test PASSES, existing prop tests (scatter, flat fallback, determinism) unchanged and green; orphans ≤ 16.
- [ ] Stage both files and commit: `feat(C2): PropScatterer along_road placement mode for chain-lining guardrails`.

---

## Task 6 — C2b: WorldDressing zone orchestrator + scene/driver wiring

**Files:** `scripts/world/world_dressing.gd` (new, TAB indent), `scripts/world/world_driver.gd` (edit — TAB indent), `scenes/world/open_world_root.tscn` (edit).

**Interfaces:**
- Consumes: `Terrain3D.data.get_height(world_pos: Vector3) -> float`, `PropScatterer.default_preset(zone: String) -> Dictionary`, `PropScatterer.configure(preset: Dictionary)`, `PropScatterer.generate()`, `PropScatterer.visible`, `RoadNetwork`.
- Produces (`world_dressing.gd`):
  - `class_name WorldDressing extends Node3D`
  - `const ZONES := {"festival": Vector3(128.0, 0.0, 128.0), "lowlands": Vector3(1536.0, 0.0, 1536.0), "coast": Vector3(5888.0, 0.0, 1536.0), "highlands": Vector3(3800.0, 0.0, 3200.0), "alpine": Vector3(5632.0, 0.0, 5632.0)}`
  - `const GEN_BUDGET_PER_TICK := 1`
  - `@export var terrain: Terrain3D`, `@export var road_network: RoadNetwork`, `@export var hide_distance: float = 900.0`
  - `func update(player_pos: Vector3) -> void`
  - `func get_zone(zone_name: String) -> PropScatterer`
  - `func _build_zones() -> void`, `func _make_height_provider(anchor: Vector3) -> Callable`, `func _prepare_preset(zone_name: String, anchor: Vector3) -> Dictionary`
  - `var _zones: Array[Dictionary] = []` — entries `{"name": String, "anchor": Vector3, "scatterer": PropScatterer, "generated": bool}`.
- Produces (`world_driver.gd` changes): `@export var traffic_spawner_path: NodePath = NodePath("TrafficSpawner")`, `@export var world_dressing_path: NodePath = NodePath("WorldDressing")`, `var _traffic_spawner: TrafficSpawner`, `var _world_dressing: WorldDressing`; `_push_player_position()` additionally calls `_traffic_spawner.update(player_pos)` and `_world_dressing.update(player_pos)`.
- Produces (`open_world_root.tscn`): ext_resources `11_traffic` (traffic_spawner.gd), `12_dressing` (world_dressing.gd); nodes `TrafficSpawner` (Node) and `WorldDressing` (Node3D); `load_steps` 14 → 16.
- Consumed by: Task 7 integration test.

**Steps:**
- [ ] Create `world_dressing.gd`:
  ```gdscript
  # scripts/world/world_dressing.gd
  class_name WorldDressing
  extends Node3D

  ## Attaches the Phase-5 biome prop layers to the open world. Each PropScatterer
  ## zone is anchored at a POI centre, wired to the seeder's Terrain3D via a
  ## ground_height_provider (anchor-relative local XZ -> world height) and to the
  ## RoadNetwork for road exclusion / chain placement. Zones generate lazily the
  ## first time the player approaches (the terrain regions under the player are
  ## already baked then) and are hidden again beyond hide_distance, so distant
  ## MultiMeshes never hang over streamed-out/removed regions: props stay inside
  ## the Terrain3D streaming ring. Visual only - no physics, no collision.

  const ZONES := {
  	"festival": Vector3(128.0, 0.0, 128.0),
  	"lowlands": Vector3(1536.0, 0.0, 1536.0),
  	"coast": Vector3(5888.0, 0.0, 1536.0),
  	"highlands": Vector3(3800.0, 0.0, 3200.0),
  	"alpine": Vector3(5632.0, 0.0, 5632.0),
  }
  const GEN_BUDGET_PER_TICK := 1

  @export var terrain: Terrain3D
  @export var road_network: RoadNetwork
  @export var hide_distance: float = 900.0

  var _zones: Array[Dictionary] = []

  func _ready() -> void:
  	if terrain == null:
  		terrain = get_node_or_null("../Terrain3D") as Terrain3D
  	if road_network == null:
  		road_network = get_node_or_null("../RoadNetwork") as RoadNetwork
  	_build_zones()

  func update(player_pos: Vector3) -> void:
  	var budget: int = GEN_BUDGET_PER_TICK
  	for zone in _zones:
  		var anchor: Vector3 = zone["anchor"]
  		var scatterer: PropScatterer = zone["scatterer"]
  		var near := player_pos.distance_squared_to(anchor) < hide_distance * hide_distance
  		var generated: bool = zone["generated"]
  		if near and not generated and budget > 0:
  			scatterer.generate()
  			generated = true
  			zone["generated"] = true
  			budget -= 1
  		if generated:
  			scatterer.visible = near

  func get_zone(zone_name: String) -> PropScatterer:
  	for zone in _zones:
  		if zone["name"] == zone_name:
  			return zone["scatterer"] as PropScatterer
  	return null

  func _build_zones() -> void:
  	for zone_name: String in ZONES:
  		var anchor: Vector3 = ZONES[zone_name]
  		var zone := Node3D.new()
  		zone.name = "PropZone_%s" % zone_name
  		zone.position = anchor
  		var scatterer := PropScatterer.new()
  		scatterer.name = "PropScatterer"
  		scatterer.road_network = road_network
  		scatterer.ground_height_provider = _make_height_provider(anchor)
  		scatterer.configure(_prepare_preset(zone_name, anchor))
  		scatterer.visible = false
  		zone.add_child(scatterer)
  		add_child(zone)
  		_zones.append({
  			"name": zone_name, "anchor": anchor,
  			"scatterer": scatterer, "generated": false,
  		})

  func _make_height_provider(anchor: Vector3) -> Callable:
  	var ax := anchor.x
  	var az := anchor.z
  	var t := terrain
  	return func(pos: Vector2) -> float:
  		if t == null or t.data == null:
  			return 0.0
  		return t.data.get_height(Vector3(ax + pos.x, 0.0, az + pos.y))

  func _prepare_preset(zone_name: String, anchor: Vector3) -> Dictionary:
  	var preset: Dictionary = PropScatterer.default_preset(zone_name).duplicate(true)
  	if zone_name == "highlands":
  		preset["props"]["guardrail"] = {
  			"mode": "along_road",
  			"count": 60, "chain_spacing": 12.0, "road_offset": 6.5,
  			"min_spacing": 6.0, "chain_radius": 700.0,
  			"center": anchor, "scale": Vector2(1.0, 1.0),
  			"ground_offset": 0.05,
  		}
  	return preset
  ```
  (Fetch the ground via the seeder's `Terrain3D` — `Terrain3D.data.get_height()` — matching the `terrain_seeder.gd` surface query and the `mountain_pass.gd` provider pattern.)
- [ ] Edit `world_driver.gd`: add the two exported NodePaths + two member vars; resolve them in `_ready` (`get_node_or_null(traffic_spawner_path) as TrafficSpawner`, `get_node_or_null(world_dressing_path) as WorldDressing`); in `_push_player_position()` after the `_terrain_seeder.sync_player_pos(player_pos)` call add:
  ```gdscript
  	if _traffic_spawner != null:
  		_traffic_spawner.update(player_pos)
  	if _world_dressing != null:
  		_world_dressing.update(player_pos)
  ```
- [ ] Edit `open_world_root.tscn`: bump `load_steps` to 16; add `[ext_resource type="Script" path="res://scripts/world/traffic_spawner.gd" id="11_traffic"]` and `[ext_resource type="Script" path="res://scripts/world/world_dressing.gd" id="12_dressing"]`; after the `RoadNetwork` node add:
  ```
  [node name="TrafficSpawner" type="Node" parent="."]
  script = ExtResource("11_traffic")
  vehicle_scene = ExtResource("3_car")
  road_network = NodePath("../RoadNetwork")

  [node name="WorldDressing" type="Node3D" parent="."]
  script = ExtResource("12_dressing")
  terrain = NodePath("../Terrain3D")
  road_network = NodePath("../RoadNetwork")
  ```
  (`vehicle_scene` reuses the existing `ExtResource("3_car")` PlayerCar PackedScene; the Task 2 strip makes it safe for traffic. NodePath-valued node-typed exports mirror the `ChunkStreamer.terrain = NodePath("../Terrain3D")` precedent already in this scene.)
- [ ] Run the probe (this is the strongest syntax gate for the two new scripts + scene). Then the full suite: existing tests (open-world, terrain seeder streaming, etc.) must stay green — no ordering/lifecycle regression from the two new nodes; orphans ≤ 16.
- [ ] Stage the three files and commit: `feat(C2/C1): WorldDressing biome prop zones wired to terrain height provider + RoadNetwork; drive traffic/props from WorldDriver`.

---

## Task 7 — Integration test: open world wires traffic + dressing (fails before Task 6)

**Files:** `tests/test_open_world.gd` (edit +1 test).

**Interfaces:**
- Consumes: the Task 6 scene (`TrafficSpawner`, `WorldDressing` nodes), `WorldDressing.get_zone(zone_name: String) -> PropScatterer`, `PropScatterer.visible`, `PropScatterer.get_child_count() -> int`.
- Produces: `func test_open_world_wires_traffic_and_prop_dressing() -> void`.

**Steps:**
- [ ] Add the test (this is the task's RED→GREEN proof — it fails on the pre-Task-6 scene because the nodes don't exist):
  ```gdscript
  func test_open_world_wires_traffic_and_prop_dressing() -> void:
  	var runner := scene_runner(OPEN_WORLD_SCENE)
  	await runner.simulate_frames(3)
  	var scene := runner.scene()
  	assert_that(scene.get_node_or_null("TrafficSpawner")).is_not_null()
  	var dressing := scene.get_node_or_null("WorldDressing") as WorldDressing
  	assert_that(dressing).is_not_null()
  	if dressing == null:
  		return
  	var festival := dressing.get_zone("festival")
  	var alpine := dressing.get_zone("alpine")
  	var highlands := dressing.get_zone("highlands")
  	assert_that(festival).is_not_null()
  	assert_that(alpine).is_not_null()
  	assert_that(highlands).is_not_null()
  	if festival == null or alpine == null:
  		return
  	await runner.simulate_frames(5)
  	# Player spawns at (128,128): only the festival zone is within hide_distance.
  	assert_that(festival.visible).is_true()
  	assert_that(festival.get_child_count()).is_greater(0)
  	assert_that(alpine.visible).is_false()
  	await runner.simulate_frames(1)
  ```
  (Client notes: `simulate_frames` drives `_physics_process`, where `WorldDriver` calls `WorldDressing.update`; festival generates on the first tick. The trailing `simulate_frames(1)` lets pending `queue_free()`s from traffic reap before the scene is torn down, protecting the orphan budget.)
- [ ] Run probe + suite: new test PASSES; full summary `0 errors | 0 failures`, orphans ≤ 16; error-flood gate 0.
- [ ] Stage `tests/test_open_world.gd` and commit: `test(C1/C2): open world wires TrafficSpawner + WorldDressing zones with lagged visibility gating`.

---

## Task 8 — Final verification + commit

**Files:** none changed (verification only; commit any legitimately staged drift from the run artifacts is FORBIDDEN — add-specific-files only).

**Steps:**
- [ ] Re-run the full recipe end-to-end: probe → suite → `findstr /c:"Overall Summary:" _gdunit.txt`.
- [ ] Record the final summary: expect **76 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | ≤ 16 orphans** (report the actual number — it is the truth this plan pins, not a claim).
- [ ] Error-flood gate: `findstr /c:"Condition \"!is_inside_tree()\" is true" _gdunit.txt` → 0 lines.
- [ ] `git status --short`: no `*.uid`, no `_gdunit.txt`/`diag/` artifacts staged.
- [ ] Confirm `AGENTS.md`, `start_game.bat`, `play_game.bat`, `.godot/` unchanged on disk.
- [ ] If proxy/unrelated files are dirty from earlier work, leave them unstaged; do NOT `git add -A`.
- [ ] Re-run `scenes/world/open_world_root.tscn` in the editor import path once more (probe step) to regenerate any `.uid`/import side effects before finishing, then commit nothing unless a Task-6/7 file is still missing its commit.

---

## Self-Review

**Inventory → task mapping:**
- **C1** (traffic unwired / no AI traffic): Task 4 (TrafficDriver + budgeted activate lifecycle) → Task 6 (scene + driver wiring) → Task 7 (open-world wiring test) → Task 8 (verification).
- **A9** (add-before-`add_child` → 11 engine errors + 6 orphans): Task 2 (local-`position`-before-`add_child` + `_strip_player_children` + `clear()`) → Task 3 (in-tree invariant test) → every task's error-flood gate (`!is_inside_tree()` = 0) + orphan ≤ 16 gate.
- **D5** (test gaps): Task 3 (despawn-distance, replenish, null-`vehicle_scene`, in-tree/no-add-before-`add_child` invariant; old error-print now asserted clean via the flood gate) → Task 4 activation test → Task 5 prop `along_road` test → Task 7 open-world integration test.
- **C2** (props unwired): Task 5 (`along_road` guardrail placement mode) → Task 6 (`WorldDressing` zones + terrain `get_height()` provider + `hide_distance` gating + shared `RoadNetwork`) → Task 8 (verification).

**Lifecycle / streaming-safety checks (design-lock compliance):**
- Spawn–despawn–activate–replenish with per-tick budgets (`spawns_per_update 2`, `despawns_per_update 4`), traffic only alive within `despawn_distance 400` and truly driven within `active_radius 120` — caps keep Terrain3D streaming + collision cheap (≤ ~3 active physics bodies near the player; dormant cars `can_sleep = true`).
- Spawn eligibility reuses `RoadNetwork.is_on_road(candidate, 10.0)` for on-road placement; `TrafficDriver` keeps AI cars following chains via `get_nearest_road_pos`.
- Props: `WorldDressing` generates a zone only when the player is within `hide_distance 900` (terrain regions under the player are baked by then — `terrain.data.get_height()` is valid), and hides zones again past that, so props never render over/float on streamed-out regions; guardrails ride the highlands pass via `along_road` with `chain_radius 700` around the pass-loop anchor so hubs/connectors stay clean.
- No new scene-level synchronous baking, no thread changes, no touching `terrain_seeder.gd`/`terrain_baker.gd`/`mountain_pass.gd`/`foliage.gd`.

**Placeholder scan:** this document contains no `TBD`, `TODO`, `FIXME`, or `???` placeholders; every code block is complete with real signatures and concrete values; the only "TBD-like" phrasing is guidance to *record the actual suite number* from the run output, which is a verification instruction, not a specification gap.