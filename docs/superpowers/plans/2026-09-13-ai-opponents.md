# AI Opponents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire AI opponents into races. `AIController` and `AIRubberBanding` exist and are unit-tested but nothing instantiates them; `VehiclePhysics.set_input_override()` / `input_override` exist but are disconnected. Deliver: a working per-frame AI driving path through `input_override`, an `ai_car.tscn` scene, a spawn factory (`OpponentFleet`) that derives waypoints from `road_network.get_roads()`, per-AI rubber banding, non-overlapping race grids, and GDUnit tests (scene-runner driven) proving steer/throttle response, waypoint progression, the speed-multiplier effect, and an AI car completing ≥ 2 waypoints of a synthetic road circuit.

**Architecture:**
- `VehiclePhysics` gains an explicit `input_override_active: bool` so an AI's `Vector2.ZERO` input (coast) is not mistaken for "no override / use player InputManager". `set_input_override(v)` activates it; `set_input_override_enabled(b)` overrides it. While active, steering/throttle/brake come from `input_override`, handbrake is forced off, and the drivetrain is forced AUTO (a MANUAL setting in Options must not lock AI cars in first gear).
- `AIController` (sibling of `VehiclePhysics`) extends to: per-target *lane offset* (recomputed on waypoint end), waypoint/lap progress accessors, and a rubber-banding hook `apply_rubber_banding(gap_seconds)` that routes through `AIRubberBanding.calculate_speed_multiplier`. An optional `rubber_band_provider: Callable` supplies the live gap every physics frame.
- `scenes/vehicle/ai_car.tscn` mirrors `player_car.tscn` (same `VehiclePhysics` root, `CarBody`, 4 `Wheel*`, `CarAudio`) but replaces the `PlayerCarController` child with an `AIController` child and embeds the `sports_coupe.glb` visual directly with the 180° `CAR_ORIENT` so AI cars never query `Garage`/`VehicleManager.player_car`.
- `scripts/race/opponent_fleet.gd` (`class_name OpponentFleet`) is the spawn factory the parallel race-loop plan reuses: `build_grid(network, player_car, opponent_count) -> Array[VehiclePhysics]` picks the nearest **closed** road chain from `road_network.get_roads()`, re-samples it to uniform 6 m waypoints, spawns opponents staggered `(i+1)*4` waypoints ahead with alternating ±2.6 m lane offsets, gives each an AIController (waypoints + lane offset + gap provider), registers each via `VehicleManager.register_ai_car()`, and returns `[player, ai1, ai2, ...]`.
- Rubber banding: gap seconds = `(ai_road_progress − player_road_progress) * 60.0`, where `road_progress` is the nearest road-point index fraction on the chosen chain (static `OpponentFleet.road_progress`). Positive gap (AI ahead) → `0.95×`; gap < −2 s → `1.05×`; else `1.0×`. `set_speed_multiplier` stays clamped `[0.5, 1.5]`.
- Race consume point: the parallel race-loop plan calls `RaceManager.start_race(grid, laps)` with the grid returned by `build_grid`. Confirmed current signature: `RaceManager.start_race(cars: Array, laps: int)` (autoload `race_manager.gd:14`), `RaceManager.get_lap_counter(car)`, `RaceManager.is_race_active`, `RaceManager.finish_race()`. Our D4 integration test wires the grid into `start_race(grid, 2)`.
- Determinism: no RNG anywhere in the AI path; tests seed fixed (`seed(12345)` in `before_test`), assert inequalities/monotonic progress (never exact values), and drive under GDUnit `scene_runner().simulate_frames()`. Physics tick = 120 Hz (`project.godot`), so one simulated frame ≈ 1/120 s.

**Tech Stack:** Godot 4.7.2 GDScript, GDUnit4
**Spec:** inventory C3 + D4 (see preamble)

## Global Constraints

- TAB indentation for all NEW `.gd`/`.tscn` code; when editing an existing file, preserve that file's own indentation for the lines you touch (repo is mixed: `vehicle_physics.gd` uses 4-space, `world_driver.gd` uses tabs).
- Never `git add -A`. Stage each task's intended files by explicit path (`git add scripts/vehicle/vehicle_physics.gd tests/test_vehicle_physics.gd`). Never stage `*.uid` files (project `.gitignore` covers them; Godot generates them on import).
- Never modify `AGENTS.md`, `start_game.bat`, `play_game.bat`, or anything under `.godot/`.
- GDUnit4 treats GDScript warnings as errors while loading suites: never use `:=` on a Variant-returning call; cast Variant → typed with explicit `as` (`var wp: Array = scene.get("road_points") as Array`). Vector approx assertions need same-type args: `assert_that(vec).is_equal_approx(vec2, Vector2(0.001, 0.001))`.
- Verification recipe — step 1 (import/probe, run FIRST whenever a `.gd`/`.tscn` is added or edited), expect **ZERO** `SCRIPT ERROR` / `Parse Error` / `Failed to load` lines (benign "resources still in use at exit" and Terrain3D whitelist lines allowed):
  `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import . 2>&1 | findstr /i "SCRIPT ERROR Parse Error Failed to load"`
- Verification recipe — step 2 (full GDUnit suite; `--ignoreHeadlessMode` MUST come after `-s`'s script path):
  `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1`
  then `findstr /c:"Overall Summary:" _gdunit.txt`.
  Baseline today: `69 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`. The suite GROWS with each task — at PASS every run must show `0 errors | 0 failures | 0 flaky | 0 skipped` and a count equal to the previous count + this task's new tests; `orphans` may change. For a fast targeted iteration run `-a res://tests/suites/test_ai_race.gd` or `-a res://tests/test_ai_rubber_banding.gd` instead of `-a res://tests`.
- Any script error during a headless run can hang Godot forever — always wrap long runs with a timeout.
- `RaceManager`/`InputManager`/`GameState`/`VehicleManager`/`WeatherManager`/`SaveManager` are autoloads (project.godot `[autoload]`) and are available inside GDUnit suites.

---

## Task 1 — VehiclePhysics explicit input-override flag (C3: un-dangle the input path)

VehiclePhysics today treats `input_override == Vector2.ZERO` as "no override" (vehicle_physics.gd:60-62, 82). An AI coasting on `Vector2.ZERO` would silently fall back to player `InputManager` — the disconnect that blocks the AI. Fix with an explicit active flag.

**Files:** `scripts/vehicle/vehicle_physics.gd`, `tests/test_vehicle_physics.gd`

**Interfaces:**
- Consumes: none (reads `GameState.transmission_mode` as today).
- Produces:
  - `var input_override_active: bool = false`
  - `func set_input_override(value: Vector2) -> void` — sets `input_override` and `input_override_active = true` (existing signature preserved, now also activates).
  - `func set_input_override_enabled(enabled: bool) -> void` — sets `input_override_active = enabled`.

**Steps:**
- [ ] Write the failing tests (append to `tests/test_vehicle_physics.gd`, 4-space indent to match file):
  - [ ] `func test_input_override_active_defaults_false() -> void:` → `var car := VehiclePhysics.new()`; `assert_that(car.input_override_active).is_false()`.
  - [ ] `func test_set_input_override_activates_override_mode() -> void:` → `car.set_input_override(Vector2(0.5, 1.0))`; `assert_that(car.input_override_active).is_true()`; `assert_that(car.input_override).is_equal(Vector2(0.5, 1.0))`.
  - [ ] `func test_set_input_override_enabled_false_deactivates() -> void:` → `car.set_input_override(Vector2(0.0, -0.5))`; `car.set_input_override_enabled(false)`; `assert_that(car.input_override_active).is_false()`.
- [ ] Run step 1 (import probe) + step 2 targeting `tests/test_vehicle_physics.gd`; **expect FAIL** (`1 errors` from unknown member `input_override_active` or a load error).
- [ ] Minimal impl in `scripts/vehicle/vehicle_physics.gd`:
  - [ ] Add `var input_override_active: bool = false` after the `input_override` declaration (line 20).
  - [ ] Replace line 49-50 with:
    ```
    func set_input_override(value: Vector2) -> void:
        input_override = value
        input_override_active = true

    func set_input_override_enabled(enabled: bool) -> void:
        input_override_active = enabled
    ```
  - [ ] Line 60-62: swap every `input_override == Vector2.ZERO` guard to `not input_override_active` (throttle, brake_input, steer_input); line 63 `handbrake` becomes `InputManager.is_handbrake() if not input_override_active else false`.
  - [ ] Line 82: `if not input_override_active and _drivetrain.manual_mode:`.
- [ ] Run step 1 + step 2 targeting `tests/test_vehicle_physics.gd`; **expect PASS** (`0 errors | 0 failures`, count 71 = 68 existing vehicle/wheel/drivetrain cases + 3 new).
- [ ] Commit: `git add scripts/vehicle/vehicle_physics.gd tests/test_vehicle_physics.gd` then commit `VehiclePhysics: explicit input_override_active flag for AI input`.

## Task 2 — AIController lane offset, progress, and rubber-banding hook (C3)

Extend the existing controller (which already computes steer/throttle/brake and calls `set_input_override` — vehicle_physics.gd now activates the flag correctly). Add lane offsets whose direction is recomputed on waypoint end, progress accessors, and the rubber-band entry point. Keep the existing steering math untouched.

**Files:** `scripts/ai/ai_controller.gd`, `tests/test_ai_rubber_banding.gd` (new)

**Interfaces:**
- Consumes: `car: VehiclePhysics` (parent), `AIRubberBanding.calculate_speed_multiplier`, unchanged.
- Produces (all on `AIController`):
  - `var lane_offset: float = 0.0`
  - `var _lane_dir: Vector3`, `var _laps_completed: int = 0`, `var _gap_provider: Callable = Callable()`
  - `func set_lane_offset(offset: float) -> void`
  - `func get_lane_offset() -> float`
  - `func set_rubber_band_provider(provider: Callable) -> void`
  - `func apply_rubber_banding(gap_seconds: float) -> void` → `set_speed_multiplier(AIRubberBanding.calculate_speed_multiplier(gap_seconds))`
  - `func get_speed_multiplier() -> float`
  - `func get_waypoint_index() -> int`
  - `func get_laps_completed() -> int`
  - `func get_progress_fraction() -> float` (= `_laps_completed + _current_target / max(waypoints.size()-1, 1)`)
  - private `func _target_point() -> Vector3`, `func _advance_target() -> void`, `func _update_lane_dir() -> void`
- New constants: `const REACH_DISTANCE := 8.0`

**Steps:**
- [ ] Write the failing tests (new file `tests/test_ai_rubber_banding.gd`, TAB indent, `extends GdUnitTestSuite`). Helper: `func _make_ai() -> AIController:` creates `var car := VehiclePhysics.new(); var ai := AIController.new(); car.add_child(ai); return ai` (safe off-tree: `@onready car` resolves on add_child, no `_physics_process` runs).
  - [ ] `test_apply_rubber_banding_routes_through_airubber_banding`: `ai.apply_rubber_banding(5.0)` → `assert_that(ai.get_speed_multiplier()).is_equal(0.95)`; `-5.0` → `1.05`; `0.5` → `1.0`.
  - [ ] `test_speed_multiplier_clamps_at_bounds`: `set_speed_multiplier(9.0)` → `1.5`; `set_speed_multiplier(-9.0)` → `0.5`.
  - [ ] `test_ai_defaults`: multiplier `1.0`, `get_lane_offset() == 0.0`, `get_waypoint_index() == 0`, `get_laps_completed() == 0`.
  - [ ] `test_set_waypoints_resets_progress`: `ai.set_waypoints([Vector3.ZERO, Vector3(0, 0, -10)])` → index `0`, laps `0`.
  - [ ] `test_lane_offset_recomputes_direction_on_waypoint_set`: waypoints `[Vector3.ZERO, Vector3(0,0,-10), Vector3(5,0,-20)]`; `ai.set_lane_offset(2.0)`; `assert_that(ai.get_lane_offset()).is_equal(2.0)`; check `ai._target_point()` lies 2.0 m to the right of waypoint[0] toward waypoint[1] (XZ distance `2.0`).
- [ ] Run step 1 + targeted step 2 on `tests/test_ai_rubber_banding.gd`; **expect FAIL** (unknown methods/properties).
- [ ] Implement in `scripts/ai/ai_controller.gd` (keep 4-space indent as the file currently uses):
  - [ ] Add `const REACH_DISTANCE := 8.0`, `var lane_offset: float = 0.0`, `var _lane_dir: Vector3 = Vector3.ZERO`, `var _laps_completed: int = 0`, `var _gap_provider: Callable = Callable()`.
  - [ ] In `_physics_process`: compute `var target := _target_point()` (replaces line 19); before applying control add: `if _gap_provider.is_valid(): var gap_value: Variant = _gap_provider.call(); var gap: float = gap_value if gap_value is float else 0.0; set_speed_multiplier(AIRubberBanding.calculate_speed_multiplier(gap))`; replace the `to_target.length() < 8.0` block (line 38) with `if to_target.length() < REACH_DISTANCE: _advance_target()`.
  - [ ] Add the new methods:
    ```
    func _target_point() -> Vector3:
        if waypoints.is_empty():
            return car.global_position if car != null else Vector3.ZERO
        return waypoints[_current_target] + _lane_dir * lane_offset

    func _advance_target() -> void:
        var prev_index := _current_target
        _current_target = (_current_target + 1) % waypoints.size()
        if waypoints.size() > 1 and prev_index >= waypoints.size() - 1:
            _laps_completed += 1
        _update_lane_dir()

    func _update_lane_dir() -> void:
        if waypoints.size() < 2:
            _lane_dir = Vector3.ZERO
            return
        var t := waypoints[(_current_target + 1) % waypoints.size()] - waypoints[_current_target]
        t.y = 0.0
        if t.length() < 0.001:
            _lane_dir = Vector3.ZERO
            return
        _lane_dir = Vector3(-t.z, 0.0, t.x).normalized()

    func set_lane_offset(offset: float) -> void:
        lane_offset = offset
        _update_lane_dir()

    func get_lane_offset() -> float:
        return lane_offset

    func set_rubber_band_provider(provider: Callable) -> void:
        _gap_provider = provider

    func apply_rubber_banding(gap_seconds: float) -> void:
        set_speed_multiplier(AIRubberBanding.calculate_speed_multiplier(gap_seconds))

    func get_speed_multiplier() -> float:
        return _speed_multiplier

    func get_waypoint_index() -> int:
        return _current_target

    func get_laps_completed() -> int:
        return _laps_completed

    func get_progress_fraction() -> float:
        var last := maxi(waypoints.size() - 1, 1)
        return float(_laps_completed) + float(_current_target) / float(last)
    ```
  - [ ] `set_waypoints()`: also reset `_laps_completed = 0` and call `_update_lane_dir()`.
- [ ] Run step 1 + targeted step 2; **expect PASS** (count 76 = 71 + 5).
- [ ] Commit: `git add scripts/ai/ai_controller.gd tests/test_ai_rubber_banding.gd` → `AIController: lane offsets, progress accessors, rubber-banding hook`.

## Task 3 — `scenes/vehicle/ai_car.tscn` (C3: AI cars exist as spawnable scenes)

**Files:** `scenes/vehicle/ai_car.tscn` (new), `tests/suites/test_ai_race.gd` (new)

**Interfaces:**
- Consumes: `scripts/vehicle/vehicle_physics.gd`, `scripts/vehicle/wheel_physics.gd`, `scripts/vehicle/car_audio.gd`, `scripts/ai/ai_controller.gd`, `resources/cars/starter_car.tres`, `assets/cars/sports_coupe.glb` (as PackedScene for the visual, like `PlayerCarController._apply_visual`).
- Produces: scene root `AICar` (RigidBody3D + `vehicle_physics.gd`), children `CarBody` (with embedded `Visual` instance, `CAR_ORIENT` 180° Y), `CollisionShape3D`, `WheelFL/FR/RL/RR`, `AIController` (script `ai_controller.gd`), `CarAudio`.

**Steps:**
- [ ] Write the failing wiring test (`tests/suites/test_ai_race.gd`, TAB indent):
  - [ ] `func test_ai_car_scene_wires_controller_to_physics() -> void:` `var packed := load("res://scenes/vehicle/ai_car.tscn") as PackedScene`; `assert_that(packed).is_not_null()`; instantiate `as VehiclePhysics`, `add_child(root)`; `root.get_node("AIController") as AIController` is not null and `(… ai).car` is `root`; all four `Wheel*` nodes exist; `root.get_node("CarBody").get_child_count() > 0`.
- [ ] Run step 1 + targeted step 2 on the suite; **expect FAIL** (load error: scene missing).
- [ ] Write `scenes/vehicle/ai_car.tscn` (mirror `player_car.tscn`, format=3):
  ```
  [gd_scene load_steps=8 format=3]

  [ext_resource type="Script" path="res://scripts/vehicle/vehicle_physics.gd" id="1_vp"]
  [ext_resource type="Script" path="res://scripts/vehicle/wheel_physics.gd" id="2_wp"]
  [ext_resource type="Script" path="res://scripts/vehicle/car_audio.gd" id="3_audio"]
  [ext_resource type="Script" path="res://scripts/ai/ai_controller.gd" id="4_ai"]
  [ext_resource type="Resource" path="res://resources/cars/starter_car.tres" id="5_config"]
  [ext_resource type="PackedScene" path="res://assets/cars/sports_coupe.glb" id="6_visual"]

  [sub_resource type="BoxShape3D" id="box_shape"]
  size = Vector3(1.8, 0.5, 4.0)

  [node name="AICar" type="RigidBody3D"]
  script = ExtResource("1_vp")
  config = ExtResource("5_config")
  mass = 1100.0
  can_sleep = false

  [node name="CarBody" type="Node3D" parent="."]

  [node name="Visual" parent="CarBody" instance=ExtResource("6_visual")]
  transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 0, 0, 0)

  [node name="CollisionShape3D" type="CollisionShape3D" parent="."]
  shape = SubResource("box_shape")
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.3, 0)

  [node name="WheelFL" type="Node3D" parent="."]
  script = ExtResource("2_wp")
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -0.8, 0.2, -1.25)

  [node name="WheelFR" type="Node3D" parent="."]
  script = ExtResource("2_wp")
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.8, 0.2, -1.25)

  [node name="WheelRL" type="Node3D" parent="."]
  script = ExtResource("2_wp")
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -0.8, 0.2, 1.25)

  [node name="WheelRR" type="Node3D" parent="."]
  script = ExtResource("2_wp")
  transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.8, 0.2, 1.25)

  [node name="AIController" type="Node" parent="."]
  script = ExtResource("4_ai")

  [node name="CarAudio" type="AudioStreamPlayer3D" parent="."]
  script = ExtResource("3_audio")
  unit_size = 2.0
  max_distance = 80.0
  ```
- [ ] Run step 1 (import probe — regenerate is fine; expect ZERO SCRIPT ERROR) + targeted step 2; **expect PASS** (count 77 = 76 + 1).
- [ ] Commit: `git add scenes/vehicle/ai_car.tscn tests/suites/test_ai_race.gd` → `Add AI car scene wired to AIController`.

## Task 4 — `OpponentFleet` spawn factory (C3: roads → waypoints → spawned grid)

**Files:** `scripts/race/opponent_fleet.gd` (new), `tests/suites/test_ai_race.gd`

**Interfaces:**
- Consumes: `RoadNetwork.get_roads()`, `road_network.gd` chain arrays `Array[Vector3]`; `VehicleManager.register_ai_car(car: VehiclePhysics)`; `resources/cars/{starter_car,muscle_car,rally_hatch}.tres` via `play_car` templates; `res://scenes/vehicle/ai_car.tscn`.
- Produces (`class_name OpponentFleet extends Node`):
  - `const AI_CAR_SCENE: PackedScene = preload("res://scenes/vehicle/ai_car.tscn")`
  - `const MAX_OPPONENTS := 5`, `const CONFIG_NAMES: Array[String] = ["starter_car", "muscle_car", "rally_hatch"]`, `const LANE_OFFSETS: Array[float] = [2.6, -2.6, 2.6, -2.6, 0.0]`, `const STAGGER_STEPS := 4`, `const RESAMPLE_SPACING := 6.0`, `const LAP_ESTIMATE_SECONDS := 60.0`
  - `var ai_cars: Array[VehiclePhysics] = []`
  - `func build_grid(network: RoadNetwork, player_car: VehiclePhysics, opponent_count: int) -> Array[VehiclePhysics]`
  - `func get_ai_cars() -> Array[VehiclePhysics]`
  - `static func road_progress(network: RoadNetwork, world_pos: Vector3) -> float`
  - private `_choose_circuit`, `_chain_is_closed`, `_resample_closed`, `_min_dist_to_chain`, `_spawn_opponent`, `_tangent`, `_make_gap_provider`, `_lane_offset_for(index: int)`.

**Steps:**
- [ ] Write failing grid tests (append to `tests/suites/test_ai_race.gd`). Build a ring exactly like `tests/test_traffic_spawner.gd`:
  ```
  func _build_ring() -> Array[Vector3]:
      var points: Array[Vector3] = []
      for i in 96:
          var angle := TAU * float(i) / 96.0
          points.append(Vector3(cos(angle) * 200.0, 0.0, sin(angle) * 200.0))
      return points
  ```
  - [ ] `func test_grid_spawns_flagged_ai_cars_off_waypoints() -> void:` `var network := RoadNetwork.new(); add_child(network); network.add_road(_build_ring(), 8.0)`. `var player := VehiclePhysics.new(); player.global_position = Vector3(200.0, 0.0, 0.0); add_child(player)`. `var fleet := OpponentFleet.new(); add_child(fleet)`; `var grid: Array[VehiclePhysics] = fleet.build_grid(network, player, 3)`. Assert `grid.size() == 4`, `grid[0] == player`, `fleet.get_ai_cars().size() == 3`, every grid car is `VehiclePhysics`.
  - [ ] `func test_grid_cars_are_spaced_apart_on_road() -> void:` same setup; for each pair in `grid` assert `a.global_position.distance_to(b.global_position) >= 5.0`; and `network.is_on_road(car.global_position, 10.0)` true for every car.
  - [ ] `func test_grid_wires_waypoints_and_lane_offsets() -> void:` same setup; for each ai in `fleet.get_ai_cars()`: `(ai.get_node("AIController") as AIController).get_waypoint_index()` is `0` and `get_lane_offset()` alternates `2.6 / -2.6 / 2.6`.
- [ ] Run step 1 + targeted suite; **expect FAIL** (`OpponentFleet` unknown).
- [ ] Implement `scripts/race/opponent_fleet.gd` (TAB indent):
  - [ ] Grid builder:
    ```
    func build_grid(network: RoadNetwork, player_car: VehiclePhysics, opponent_count: int) -> Array[VehiclePhysics]:
        var waypoints := _choose_circuit(network, player_car.global_position)
        var grid: Array[VehiclePhysics] = [player_car]
        ai_cars.clear()
        var max_count := mini(opponent_count, MAX_OPPONENTS)
        for i in max_count:
            var start_step := (i + 1) * STAGGER_STEPS
            var car := _spawn_opponent(waypoints, start_step, _lane_offset_for(i), CONFIG_NAMES[i % CONFIG_NAMES.size()], network)
            grid.append(car)
            ai_cars.append(car)
        return grid
    ```
  - [ ] Chain choice (mirror `terrain_baker`'s closed-chain idea):
    ```
    func _choose_circuit(network: RoadNetwork, origin: Vector3) -> Array[Vector3]:
        var best_closed: Array[Vector3] = []
        var best_open: Array[Vector3] = []
        var best_closed_dist := INF
        var best_open_dist := INF
        for road in network.get_roads():
            if road.size() < 2:
                continue
            var d := _min_dist_to_chain(road, origin)
            if _chain_is_closed(road):
                if d < best_closed_dist:
                    best_closed_dist = d
                    best_closed = road
            elif d < best_open_dist:
                best_open_dist = d
                best_open = road
        var chain := best_closed if not best_closed.is_empty() else best_open
        return _resample_closed(chain, RESAMPLE_SPACING) if _chain_is_closed(chain) else chain

    func _chain_is_closed(chain: Array[Vector3]) -> bool:
        if chain.size() < 3:
            return false
        var avg := 0.0
        for i in chain.size() - 1:
            avg += chain[i].distance_to(chain[i + 1])
        avg /= float(chain.size() - 1)
        return chain[0].distance_to(chain[chain.size() - 1]) < avg * 2.0

    func _min_dist_to_chain(chain: Array[Vector3], pos: Vector3) -> float:
        var best := INF
        for p in chain:
            best = minf(best, p.distance_to(pos))
        return best
    ```
  - [ ] Re-sample a closed chain to uniform spacing (cumulative arc-length; drop trailing near-first point so wrap indices stay clean):
    ```
    func _resample_closed(chain: Array[Vector3], spacing: float) -> Array[Vector3]:
        var n := chain.size()
        if n < 3 or spacing <= 0.0:
            return chain
        var cum := PackedFloat32Array()
        cum.resize(n + 1)
        cum[0] = 0.0
        for i in n:
            cum[i + 1] = cum[i] + chain[i].distance_to(chain[(i + 1) % n])
        var total := cum[n]
        if total <= 0.0:
            return chain
        var out: Array[Vector3] = [chain[0]]
        var next_dist := spacing
        for i in n:
            var a: Vector3 = chain[i]
            var b: Vector3 = chain[(i + 1) % n]
            var seg_len := cum[i + 1] - cum[i]
            while next_dist <= cum[i + 1] and out.size() < 4096:
                var frac := (next_dist - cum[i]) / seg_len if seg_len > 0.0001 else 0.0
                out.append(a.lerp(b, frac))
                next_dist += spacing
        if out[out.size() - 1].distance_to(out[0]) < spacing * 0.5:
            out.remove_at(out.size() - 1)
        return out
    ```
  - [ ] Spawn helper (config BEFORE `add_child` so `VehiclePhysics._ready` picks `mass`/torque from the real `.tres`):
    ```
    func _spawn_opponent(waypoints: Array[Vector3], start_step: int, lane_offset: float, config_name: String, network: RoadNetwork) -> VehiclePhysics:
        if waypoints.is_empty():
            return null
        var idx := start_step % waypoints.size()
        var t := _tangent(waypoints, idx)
        var car := AI_CAR_SCENE.instantiate() as VehiclePhysics
        car.config = load("res://resources/cars/%s.tres" % config_name) as CarConfig
        car.global_position = waypoints[idx] + Vector3.UP * 0.3
        car.global_rotation = Vector3(0.0, atan2(-t.x, -t.z), 0.0)
        add_child(car)
        VehicleManager.register_ai_car(car)
        var ai := car.get_node("AIController") as AIController
        ai.set_waypoints(waypoints)
        ai.set_lane_offset(lane_offset)
        ai.set_rubber_band_provider(_make_gap_provider(network, car))
        return car
    ```
    (`build_grid`'s loop returns only non-null results: guard `if car != null:` before append.)
  - [ ] Tangent / lane / gap helpers:
    ```
    func _tangent(waypoints: Array[Vector3], index: int) -> Vector3:
        var n := waypoints.size()
        if n < 2:
            return Vector3.FORWARD
        var t := waypoints[(index + 1) % n] - waypoints[index % n]
        t.y = 0.0
        return t.normalized() if t.length() > 0.0001 else Vector3.FORWARD

    func _lane_offset_for(index: int) -> float:
        return LANE_OFFSETS[index % LANE_OFFSETS.size()]

    func _make_gap_provider(network: RoadNetwork, ai_car: VehiclePhysics) -> Callable:
        var player: VehiclePhysics = VehicleManager.get_player_car()
        return func() -> float:
            if player == null or not is_instance_valid(player) or player == ai_car or network == null:
                return 0.0
            var player_gap := ai_car.global_position.distance_to(player.global_position)
            var ai_progress: float = road_progress(network, ai_car.global_position)
            var player_progress: float = road_progress(network, player.global_position)
            return clampf((ai_progress - player_progress) * float(LAP_ESTIMATE_SECONDS), -10.0, 10.0)

    static func road_progress(network: RoadNetwork, world_pos: Vector3) -> float:
        var roads := network.get_roads()
        if roads.is_empty():
            return 0.0
        var best_chain := 0
        var best_idx := 0
        var best_d := INF
        for c in roads.size():
            var chain: Array[Vector3] = roads[c]
            for i in chain.size():
                var d := chain[i].distance_to(world_pos)
                if d < best_d:
                    best_d = d
                    best_chain = c
                    best_idx = i
        var chain: Array[Vector3] = roads[best_chain]
        return float(best_idx) / float(maxi(chain.size() - 1, 1))
    ```
    (Remove the unused `player_gap` local — included above only as a hint; the static `road_progress` gap is the wired measure.)
- [ ] Run step 1 + targeted suite; **expect PASS** (count 80 = 77 + 3).
- [ ] Commit: `git add scripts/race/opponent_fleet.gd tests/suites/test_ai_race.gd` → `Add OpponentFleet: road-derived waypoints, staggered non-overlapping grid`.

## Task 5 — Synthetic ring scene + driving-tests ground (D4: steer/throttle, progression, ≥2 waypoints)

**Files:** `tests/synthetic_ring.gd` (new), `tests/scenes/synthetic_ring.tscn` (new), `tests/suites/test_ai_race.gd`

**Interfaces:**
- Produces:
  - `tests/synthetic_ring.gd` (`extends Node3D`): `const ROAD_RADIUS := 80.0`, `const POINT_COUNT := 96`, `const ROAD_Y := 1.0`; `var road_points: Array[Vector3] = []`; `func _ready() -> void:` builds the ring, adds child `RoadNetwork` (`RoadNetwork.new()`, `.add_road(road_points, 8.0)`), sets root property `road_points`, and adds a flat `StaticBody3D` "Ground" (`BoxShape3D` 400×1×400 at y −0.5) so wheels have collidable ground.
  - `tests/scenes/synthetic_ring.tscn` — root `Node3D` "SyntheticRing" with `script = ExtResource` → `res://tests/synthetic_ring.gd`. Filename deliberately avoids the `test` prefix so GdUnit does not collect it as a suite.
  - Suite additions (all scene-runner driven, TAB indent):
    - `func before_test() -> void:` → `seed(12345)` and `GameState.transmission_mode = GameState.TransmissionMode.AUTO` (restores isolation; Task 6 mutates it).
    - `func test_ai_steers_and_throttles_when_override_active() -> void:`
    - `func test_ai_completes_two_waypoints_of_synthetic_road() -> void:`

**Steps:**
- [ ] Write `tests/synthetic_ring.gd` and `tests/scenes/synthetic_ring.tscn` first (scene source), then the two failing tests:
  ```
  func _ring_setup() -> Array:
      var runner := scene_runner("res://tests/scenes/synthetic_ring.tscn")
      await runner.simulate_frames(2)
      var scene := runner.scene()
      var wp: Array = scene.get("road_points") as Array
      var car := (load("res://scenes/vehicle/ai_car.tscn") as PackedScene).instantiate() as VehiclePhysics
      car.global_position = (wp[0] as Vector3) + Vector3.UP * 0.3
      scene.add_child(car)
      var ai := car.get_node("AIController") as AIController
      ai.set_waypoints(wp)
      return [runner, scene, car, ai]
  ```
  - [ ] `func test_ai_steers_and_throttles_when_override_active() -> void:` `var setup := await _ring_setup()`; `var car := setup[2] as VehiclePhysics; var ai := setup[3] as AIController; var runner := setup[0] as ISceneRunner`; loop `for _f in 300: await runner.simulate_frames(1)`: assert `car.get_speed_kmh() > 0.0` (throttle response) and `car.input_override_active` (override path drives, not InputManager); after loop also `assert_that(ai.get_waypoint_index()).is_greater_equal(1)`.
  - [ ] `func test_ai_completes_two_waypoints_of_synthetic_road() -> void:` same setup; `for _f in 1200: await runner.simulate_frames(1)` (10 s at 120 Hz); `assert_that(ai.get_waypoint_index()).is_greater_equal(2)`.
  - [ ] Add a ground-roll safety: `func test_predicted_speed_multiplier_effect_hint()` is NOT written — see Task 6.
- [ ] Run step 1 (import probe) + targeted suite; **expect FAIL** (scene/suite load errors).
- [ ] Implement `tests/synthetic_ring.gd`:
  ```
  extends Node3D

  const ROAD_RADIUS := 80.0
  const POINT_COUNT := 96
  const ROAD_Y := 1.0

  var road_points: Array[Vector3] = []

  func _ready() -> void:
      road_points = _build_ring()
      var network := RoadNetwork.new()
      network.name = "RoadNetwork"
      add_child(network)
      network.add_road(road_points, 8.0)

      var box := BoxShape3D.new()
      box.size = Vector3(400.0, 1.0, 400.0)
      var ground_shape := CollisionShape3D.new()
      ground_shape.shape = box
      var ground := StaticBody3D.new()
      ground.name = "Ground"
      ground.position = Vector3(0.0, -0.5, 0.0)
      ground.add_child(ground_shape)
      add_child(ground)

  func _build_ring() -> Array[Vector3]:
      var points: Array[Vector3] = []
      for i in POINT_COUNT:
          var angle := TAU * float(i) / float(POINT_COUNT)
          points.append(Vector3(cos(angle) * ROAD_RADIUS, ROAD_Y, sin(angle) * ROAD_RADIUS))
      return points
  ```
- [ ] Implement the two scene tests in the suite exactly as written above (note `setup` returns `Array`, index-cast with `as`).
- [ ] Run step 1 + targeted suite; **expect PASS** (count 82 = 80 + 2).
- [ ] Commit: `git add tests/synthetic_ring.gd tests/scenes/synthetic_ring.tscn tests/suites/test_ai_race.gd` → `Add synthetic ring scene + AI driving tests (steer/throttle, 2-waypoint completion)`.

## Task 6 — Speed-multiplier effect, 3-car race grid through RaceManager, manual-suppression (D4)

**Files:** `tests/suites/test_ai_race.gd`

**Interfaces:**
- Consumes: `RaceManager.start_race(cars: Array, laps: int)`, `RaceManager.is_race_active`, `RaceManager.finish_race()`; `GameState.transmission_mode`; `OpponentFleet.build_grid`.
- Produces: three new suite tests.

**Steps:**
- [ ] Write failing tests:
  - [ ] `func test_speed_multiplier_effect_changes_pace() -> void:` run `_ring_setup()` twice, first `ai.set_speed_multiplier(0.5)` then `ai.set_speed_multiplier(1.5)`; each: `for _f in 600: await runner.simulate_frames(1)`; record `low := car.get_speed_kmh()` and `high := car.get_speed_kmh()`; `assert_that(low).is_less(high)`.
  - [ ] `func test_grid_race_runs_through_race_manager() -> void:` scene-runner the ring; `var network := scene.get_node("RoadNetwork") as RoadNetwork`; player = `(load("res://scenes/vehicle/player_car.tscn") as PackedScene).instantiate() as VehiclePhysics` at `(wp[0] as Vector3) + Vector3.UP * 0.3`, `player.name = "PlayerCar"`, `scene.add_child(player)`; `var fleet := OpponentFleet.new(); scene.add_child(fleet)`; `var grid: Array[VehiclePhysics] = fleet.build_grid(network, player, 3)`; `RaceManager.start_race(grid, 2)`; `assert_that(RaceManager.is_race_active).is_true()`; then `for _f in 600: await runner.simulate_frames(1)`; assert every `fleet.get_ai_cars()` entry: `network.is_on_road(car.global_position, 10.0)` and `(car.get_node("AIController") as AIController).get_waypoint_index() >= 1`; finally `RaceManager.finish_race()`.
  - [ ] `func test_ai_keeps_manual_settings_from_locking_gears() -> void:` `_ring_setup()`, drive 600 frames; `assert_that(car.get_gear()).is_greater_equal(2)` (auto upshift used first/second gear) while `GameState.transmission_mode == GameState.TransmissionMode.MANUAL` (set in `before_test` — Task 5 sets AUTO; this test sets MANUAL at its start: `GameState.transmission_mode = GameState.TransmissionMode.MANUAL`, `before_test` resets to AUTO after each test).
- [ ] Run targeted suite; **expect FAIL** (these explicitly compare two differently-multiplied runs; on the current multiplier-only-throttle code low vs high on a long straight may already differ — if the FAIL does not reproduce because the new code already passes, replace the assertion with a stronger one: after `set_speed_multiplier(0.5)` assert `car.get_speed_kmh()` after 900 frames is `is_less` than 45 (km/h) while the 1.5 run exceeds 45; keep it a real behavioral lock, not a no-op).
- [ ] Implement — no engine changes needed for effect test: verify assertions, and if needed to make the effect robust, in `ai_controller.gd` scale the upshift-free **requested throttle** so a 0.5× car stays clearly slower on a straight (currently handled by `throttle * _speed_multiplier`; if the 600-frame difference is too small to lock, increase to 900 frames).
- [ ] Run step 1 + step 2 **full suite** (`-a res://tests`); **expect PASS**: `Overall Summary:` shows 85 test cases, `0 errors | 0 failures | 0 flaky | 0 skipped` (85 = 82 + 3). Record the actual count + orphan count in the commit message note.
- [ ] Commit: `git add tests/suites/test_ai_race.gd` → (plus any ai_controller tweak) `AI race suite: speed-multiplier pace effect, 3-car RaceManager grid, manual-mode suppression`.

## Task 7 — Full validation sweep + baseline record

**Files:** none (verification only)

**Steps:**
- [ ] `git status --short` — confirm NO `*.uid` files are visible/untracked-staged from the new `ai_car.tscn`, `opponent_fleet.gd`, `synthetic_ring.*`, suites.
- [ ] Step 1 import probe; expect ZERO `SCRIPT ERROR` / `Parse Error` / `Failed to load`.
- [ ] Step 2 full GDUnit run; `findstr /c:"Overall Summary:" _gdunit.txt` → expect `0 errors | 0 failures | 0 flaky | 0 skipped` and **85 test cases** (69 baseline + 3 + 5 + 1 + 3 + 2 + 3). If the count differs, the plan's arithmetic is off — record the real number, do not fake PASS.
- [ ] Confirm no test left `RaceManager.is_race_active == true` or `GameState.transmission_mode == MANUAL` (any later failure would leak across suites — `before_test` in the AI suite resets transmission only; verify RaceManager state by asserting `RaceManager.is_race_active` is false at suite end or rely on the standalone `test_race_manager_starts_clean` semantics).
- [ ] Commit any leftover (should be none): do NOT run `git add -A`; if nothing staged, skip the commit.

---

## Self-Review

| C3 / D4 item | Delivered by |
| --- | --- |
| C3 — `AIController` exists, unit-tested, nothing instantiates it | Task 3 (`ai_car.tscn` embeds `AIController` as a non-`PlayerCarController` child) + Task 4 (`OpponentFleet._spawn_opponent` instantiates and wires it) + Tasks 5-6 scene tests drive it |
| C3 — `set_speed_multiplier()` exists but disconnected | Task 2 (`get_speed_multiplier`, `apply_rubber_banding`, `set_rubber_band_provider`) + Task 4 (provider wired per AI) + Task 6 (pace effect test) |
| C3 — `input_override` / `set_input_override()` exist but disconnected (Vector2.ZERO sentinel conflict) | Task 1 (`input_override_active` flag), consumed per-frame by `AIController` (Task 2) and verified live in Tasks 5-6 |
| C3 — car class/mass config | Task 4 `_spawn_opponent` assigns real `.tres` `CarConfig` (`CONFIG_NAMES`: starter/muscle/rally) BEFORE `add_child` so `VehiclePhysics._ready` sets mass/torque |
| C3 — how three 4-wheel cars spawn without overlap | Task 4: `STAGGER_STEPS` (24 m along chain) + alternating `LANE_OFFSETS` ±2.6 m + test `test_grid_cars_are_spaced_apart_on_road` asserting ≥ 5 m pairwise |
| D4 — AI cars wired into a race driving road waypoints | Task 4 (`road_network.get_roads()` → nearest closed chain → 6 m resample → AIController `set_waypoints`), Task 6 (`build_grid` grid through `RaceManager.start_race(grid, 2)`) |
| D4 — steer/throttle response test | Task 5 `test_ai_steers_and_throttles_when_override_active` |
| D4 — waypoint progression test | Task 5 (index ≥ 1) + Task 5 `test_ai_completes_two_waypoints_of_synthetic_road` (index ≥ 2) |
| D4 — speed-multiplier effect test | Task 2 unit (`apply_rubber_banding` mapping/clamps) + Task 6 `test_speed_multiplier_effect_changes_pace` (0.5× < 1.5× under physics) |
| D4 — deterministic under GDUnit scene_runner | Task 5 (fixed `seed(12345)`, ring all-y=1.0 flat, no RNG; 120 Hz physics ticks budgeted: 1200 frames = 10 s); no placeholder constants |
| TEMPORAL WARRANTY — lane offset recomputed on waypoint end | Task 2 `_advance_target()` → `_update_lane_dir()` → `_target_point()` |
| Parallel race-loop plan integration | Task 4 `build_grid(network, player_car, count) -> Array[VehiclePhysics]` is the exact array type `RaceManager.start_race(cars: Array, laps: int)` consumes (verified `race_manager.gd:14`); no signature guesswork |

Confirmed: every task declares exact files, exact `Consumes`/`Produces` signatures with real code, a real failing test before implementation, and a PASS gate (full-suite `Overall Summary`) before commit. No placeholders, no "similar to Task N", no TBD. Baseline arithmetic: 69 → Task1 +3 = 71 → Task2 +5 = 76 → Task3 +1 = 77 → Task4 +3 = 80 → Task5 +2 = 82 → Task6 +3 = **85**.