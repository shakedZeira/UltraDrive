# Drift Scoring + POI Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make C5 (DriftScorer, unwired), C9 (POI discovery, no-op on arrival), and D6 (zero DriftScorer tests) real: wire drift scoring into the player car with a live HUD readout, make POI proximity discover a POI once per session with persistence + a HUD toast, and add GDUnit4 coverage for both. Everything additive — the 69-test baseline stays green and grows.

**Architecture:**
- **Drift pipeline:** `VehiclePhysics` already computes a per-wheel slip angle every grounded frame (`TireModel.calculate_slip_angle`, vehicle_physics.gd:104) but never exposes it. Add a read-only per-frame `get_slip_angle_deg()` that tracks the frame's max absolute wheel slip (additive; no tire/force logic touched). New `DriftController` node (child of the player car, sibling of `PlayerCarController`) owns a `DriftScorer`, thresholds slip+speed into a `drifting` bool, feeds `scorer.update(delta, slip_deg, drifting)` every physics tick, and emits `score_updated` / `drift_started` / `drift_ended`. HUD (`race_ui.gd` polling, matching its existing per-frame cluster poll) renders `DRIFT <n>`.
- **POI discovery:** New `POIDiscovery` node in `open_world_root.tscn` polls the player car's `global_position` against `POIRegistry.pois`; the first entry inside `DISCOVERY_RADIUS` (80 m) per session marks the POI discovered, persists it through `SaveManager` slot 0 under `discovered_pois` (exactly the `Garage` read-modify-write pattern, garage.gd:46-50), and emits `poi_discovered`. `race_ui` finds it via the `poi_discovery` group and flashes a toast label for 3 s. The pause-map POI dots (world_map.gd:69-74) are untouched.
- **Tests:** `tests/test_drift_scoring.gd` (DriftScorer semantics + DriftController feeding + slip getter contract), `tests/suites/test_poi_discovery.gd` (fire-once, no-fire-when-far, seed+persist roundtrip), `tests/suites/test_hud_readouts.gd` (HUD scene instantiates without car/POI).
- Testability: `DriftController._evaluate(delta)` and `POIDiscovery._check_discovery()` are plain callables invoked by the engine callbacks, so tests drive them directly with a stub `VehiclePhysics` (setting public `current_speed_kmh` and private `_max_slip_angle_deg` — the repo already drives privates this way, e.g. test_terrain_seeder_streaming.gd:36-49). This avoids physics-frame timing flakiness.

**Tech Stack:** Godot 4.7.2 GDScript, GDUnit4

**Spec:** inventory C5, C9, D6 (see preamble)

## Global Constraints

- **Indentation:** match the file being edited. `scripts/vehicle/vehicle_physics.gd` is 4-space; everything in `scripts/race/`, `scripts/world/`, `scripts/ui/`, `tests/`, `tests/suites/`, and the `.tscn` files uses TAB. New scripts use TAB (or 4-space where required by an existing 4-space file).
- **Never `git add -A` and never stage `*.uid` files.** Stage only the exact files a task touches, by path. `.gitignore` already ignores `*.uid`; keep them out of commits.
- **Never modify or delete:** `AGENTS.md`, `start_game.bat`, `play_game.bat`, `.godot/`. `project.godot` is NOT on that list but nothing below touches it either.
- **GDUnit4 warnings-as-errors:** do not use `:=` to infer from a `Variant`-returning call (e.g. `Dictionary.get(...)`). Always give an explicit type (`var x: T = call_returning_variant()`) or `v as T`. Vector approx asserts need a SAME-TYPE approx arg.
- **Full-verification recipe (run at the end of every task that touches scripts):**
  1. `git status --short` — must not list `*.uid` files.
  2. Import/probe (first run of any session): `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import . 2>&1 | findstr /i "SCRIPT ERROR Parse Error Failed to load"` → expect ZERO matching lines (benign "resources still in use at exit"/Terrain3D whitelist lines allowed).
  3. GDUnit suite (`--ignoreHeadlessMode` MUST come AFTER the tool-script path): `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1` then `findstr /c:"Overall Summary:" _gdunit.txt`. Baseline `69 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`; expected growth: +8 (test_drift_scoring) + 4 (test_poi_discovery) + 1 (test_hud_readouts) = **82 | 0 | 0 | 0 | 16** (orphan count may drift by the freed stub vehicles; benign).
- **Headless hang guard:** any script error during a headless diag can hang Godot forever — always run import + suite steps through the bash tool with a timeout, never without.
- **Commit granularity:** one small commit per completed task (`git add <explicit paths>` → `git commit`), only when the task's PASS gate is green. Never amend.
- Actual file locations (verified by reading them): `PlayerCarController` lives at `scripts/player/player_car_controller.gd`, Racer HUD script at `scripts/race/race_ui.gd`.

---

## Task 1 — VehiclePhysics exposes per-frame slip angle (missing input for drift)

**Files:** `scripts/vehicle/vehicle_physics.gd` (edit), `tests/test_drift_scoring.gd` (new, contract test only — full file finished in Tasks 2–3)

**Interfaces:**
- Consumes: existing per-wheel `slip_angle` (radians) computed at vehicle_physics.gd:104 inside the grounded branch; `TireModel`.
- Produces: `func get_slip_angle_deg() -> float` — frame-max absolute slip across all grounded wheels, in degrees.

**Design:** add `var _max_slip_angle_deg: float = 0.0` under `--- Internal ---`; reset it to `0.0` at the top of `_physics_process` (right after the `if config == null: return` guard); in the grounded wheel branch, after `slip_angle` is computed, take the frame max in degrees. Getter returns it. This is read-only and changes no force/steering behavior — impossible to regress the 69 baseline.

Write the contract test first (fails: method does not exist):

```gdscript
# tests/test_drift_scoring.gd
extends GdUnitTestSuite

func test_vehicle_slip_getter_exists_and_starts_zero() -> void:
	var vehicle := VehiclePhysics.new()
	assert_that(vehicle.get_slip_angle_deg()).is_equal(0.0)
	vehicle.free()
```

Checkbox steps:

- [ ] 1.1 Write `tests/test_drift_scoring.gd` with only `test_vehicle_slip_getter_exists_and_starts_zero` (above).
- [ ] 1.2 Run suite (`run-full`) → FAIL: `Nonexistent function 'get_slip_angle_deg'` in test (also a SCRIPT ERROR on `--headless --import .`).
- [ ] 1.3 Edit `scripts/vehicle/vehicle_physics.gd`:
  - add `var _max_slip_angle_deg: float = 0.0` to `--- Internal ---`;
  - in `_physics_process`, after `if config == null: return`, add `_max_slip_angle_deg = 0.0`;
  - inside the grounded wheel block after `var slip_angle := TireModel.calculate_slip_angle(...)`, add `_max_slip_angle_deg = maxf(_max_slip_angle_deg, absf(rad_to_deg(slip_angle)))`;
  - under `# --- Public API ---`, add:
    ```gdscript
    func get_slip_angle_deg() -> float:
        return _max_slip_angle_deg
    ```
    (4-space indentation — file convention.)
- [ ] 1.4 Run full verification recipe → PASS (`82 | 0 | 0 | 0 | 16` is not expected yet — expect `70 | 0 | 0 | 0 | 16`; the other new tests arrive in later tasks, so this run shows 70). Then `git commit` (only `scripts/vehicle/vehicle_physics.gd` + `tests/test_drift_scoring.gd`).

---

## Task 2 — DriftController: feed slip/speed into DriftScorer and emit score events (C5 wiring, D6)

**Files:** `scripts/race/drift_controller.gd` (new), `tests/test_drift_scoring.gd` (extend)

**Interfaces:**
- Consumes: `DriftScorer.update(delta: float, slip_angle_deg: float, drifting: bool) -> float`, `DriftScorer.is_drifting`, `DriftScorer.reset()`, `DriftScorer.get_total_score() -> int`; `car.get_slip_angle_deg() -> float` (Task 1); `car.get_speed_kmh() -> float`.
- Produces:
  - `signal score_updated(total_score: int)`
  - `signal drift_started`
  - `signal drift_ended`
  - `func _evaluate(delta: float) -> void` (called by `_physics_process`; test hook)
  - `func reset() -> void`
  - `var car: VehiclePhysics` — injectable (defaults to `get_parent()`), `var scorer: DriftScorer = DriftScorer.new()`

New file `scripts/race/drift_controller.gd` (TAB):

```gdscript
# scripts/race/drift_controller.gd
class_name DriftController
extends Node

## Feeds the attached vehicle's slip/speed into a DriftScorer every physics
## frame and relays scoring events so the HUD can show a live total.

signal score_updated(total_score: int)
signal drift_started
signal drift_ended

const MIN_DRIFT_SPEED_KMH := 30.0
const DRIFT_SLIP_THRESHOLD_DEG := 12.0

var car: VehiclePhysics
var scorer: DriftScorer = DriftScorer.new()

func _ready() -> void:
	if car == null:
		car = get_parent() as VehiclePhysics

func _physics_process(delta: float) -> void:
	_evaluate(delta)

func _evaluate(delta: float) -> void:
	if car == null:
		return
	var slip_deg := car.get_slip_angle_deg()
	var speed_kmh := car.get_speed_kmh()
	var drifting := speed_kmh >= MIN_DRIFT_SPEED_KMH and slip_deg >= DRIFT_SLIP_THRESHOLD_DEG
	var was_drifting := scorer.is_drifting
	scorer.update(delta, slip_deg, drifting)
	score_updated.emit(scorer.get_total_score())
	if drifting and not was_drifting:
		drift_started.emit()
	elif not drifting and was_drifting:
		drift_ended.emit()

func reset() -> void:
	scorer.reset()
	score_updated.emit(0)
```

Append to `tests/test_drift_scoring.gd` (TAB; grading helper stubs a real `VehiclePhysics`, never entering it in a tree, and drives the private tracked value — repo style):

```gdscript
func _stub_car(speed_kmh: float, slip_deg: float) -> VehiclePhysics:
	var vehicle := VehiclePhysics.new()
	vehicle.current_speed_kmh = speed_kmh
	vehicle._max_slip_angle_deg = slip_deg
	return vehicle

func test_drift_controller_scores_when_slipping_at_speed() -> void:
	var controller := DriftController.new()
	controller.car = _stub_car(80.0, 30.0)
	var emitted: Array[int] = []
	controller.score_updated.connect(func(total: int) -> void: emitted.append(total))
	controller._evaluate(1.0 / 60.0)
	assert_that(controller.scorer.is_drifting).is_true()
	assert_that(controller.scorer.get_total_score()).is_greater(0)
	assert_that(emitted.size()).is_greater_equal(1)
	assert_that(emitted.back()).is_equal(controller.scorer.get_total_score())
	controller.free()

func test_drift_controller_ignores_low_speed() -> void:
	var controller := DriftController.new()
	controller.car = _stub_car(10.0, 30.0)
	controller._evaluate(1.0 / 60.0)
	assert_that(controller.scorer.get_total_score()).is_equal(0)
	assert_that(controller.scorer.is_drifting).is_false()
	controller.free()

func test_drift_controller_emits_start_then_end() -> void:
	var controller := DriftController.new()
	controller.car = _stub_car(80.0, 30.0)
	var starts := 0
	var ends := 0
	controller.drift_started.connect(func() -> void: starts += 1)
	controller.drift_ended.connect(func() -> void: ends += 1)
	controller._evaluate(1.0 / 60.0)
	controller.car._max_slip_angle_deg = 30.0
	controller._evaluate(1.0 / 60.0)
	controller.car.current_speed_kmh = 0.0
	controller._evaluate(1.0 / 60.0)
	assert_that(starts).is_equal(1)
	assert_that(ends).is_equal(1)
	controller.free()
```

Checkbox steps:

- [ ] 2.1 Add the three DriftController tests above to `tests/test_drift_scoring.gd`.
- [ ] 2.2 Run suite → FAIL: `class_name DriftController` unresolved (SCRIPT ERROR on import; `DriftController.new()` errors in suite).
- [ ] 2.3 Create `scripts/race/drift_controller.gd` exactly as above (TAB).
- [ ] 2.4 Run full verification recipe → PASS (expect `73 | 0 | 0 | 0 | 16`). Then `git commit` (`scripts/race/drift_controller.gd` + `tests/test_drift_scoring.gd`).

---

## Task 3 — D6 DriftScorer semantics locked in by unit tests (pure logic, green on existing impl)

**Files:** `tests/test_drift_scoring.gd` (extend only — no production code this task)

**Interfaces:** Consumes `DriftScorer` public API only (`update`, `get_total_score`, `reset`, `is_drifting`). Produces: none.

Rationale: D6 is "DriftScorer has zero tests". The scorer's existing behavior is the spec — these tests lock it in (they pass immediately; the "failing" state is that the tests do not exist). Append (TAB):

```gdscript
func test_scorer_accumulates_while_drifting() -> void:
	var scorer := DriftScorer.new()
	var raw_total := 0.0
	for i in 60:
		raw_total += scorer.update(1.0 / 60.0, 30.0, true)
	assert_that(scorer.is_drifting).is_true()
	assert_that(scorer.get_total_score()).is_greater(0)
	assert_that(scorer.get_total_score()).is_greater_equal(int(raw_total))

func test_scorer_returns_zero_when_not_drifting() -> void:
	var scorer := DriftScorer.new()
	assert_that(scorer.update(1.0 / 60.0, 30.0, false)).is_equal(0.0)
	assert_that(scorer.get_total_score()).is_equal(0)
	assert_that(scorer.is_drifting).is_false()

func test_scorer_ends_drift_keeps_total_and_resumes_cleanly() -> void:
	var scorer := DriftScorer.new()
	scorer.update(1.0 / 60.0, 45.0, true)
	var after_first := scorer.get_total_score()
	assert_that(scorer.is_drifting).is_true()
	var end_frame := scorer.update(1.0 / 60.0, 0.0, false)
	assert_that(end_frame).is_equal(0.0)
	assert_that(scorer.is_drifting).is_false()
	assert_that(scorer.get_total_score()).is_equal(after_first)
	scorer.update(1.0 / 60.0, 45.0, true)
	assert_that(scorer.get_total_score()).is_greater(after_first)

func test_scorer_reset_clears_total() -> void:
	var scorer := DriftScorer.new()
	scorer.update(1.0 / 60.0, 45.0, true)
	scorer.reset()
	assert_that(scorer.get_total_score()).is_equal(0)
	assert_that(scorer.is_drifting).is_false()
```

Checkbox steps:

- [ ] 3.1 Append the four scorer tests to `tests/test_drift_scoring.gd`.
- [ ] 3.2 Run suite → PASS (green-lock, expect `77 | 0 | 0 | 0 | 16`). Then `git commit` (`tests/test_drift_scoring.gd`).

---

## Task 4 — HUD drift readout + POI-toast labels and wiring (C5 HUD, C9 toast surface)

**Files:** `scenes/ui/hud.tscn` (edit), `scripts/race/race_ui.gd` (edit), `tests/suites/test_hud_readouts.gd` (new)

**Interfaces:**
- Consumes: `DriftController` (via `car.get_node_or_null("DriftController")`), `POIDiscovery` group `"poi_discovery"` and its `signal poi_discovered(poi_id: String, poi_name: String, stage: String)` (Task 5 node; HUD tolerates its absence).
- Produces (in `race_ui.gd`): `func _show_toast(text_value: String) -> void`, `func _on_poi_discovered(_poi_id: String, poi_name: String, stage: String) -> void`.

Add to `scenes/ui/hud.tscn` (after the `TimeLabel` node, TAB, `unique_name_in_owner`):

```
[node name="DriftScoreLabel" type="Label" parent="Root"]
unique_name_in_owner = true
offset_left = 20.0
offset_top = 96.0
offset_right = 260.0
offset_bottom = 136.0
visible = false
theme_override_colors/font_color = Color(0.95, 0.98, 1, 1)
theme_override_colors/font_outline_color = Color(0.03, 0.05, 0.1, 1)
theme_override_constants/outline_size = 3
theme_override_font_sizes/font_size = 26

[node name="POIToastLabel" type="Label" parent="Root"]
unique_name_in_owner = true
anchors_preset = 1
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -320.0
offset_top = -420.0
offset_right = 320.0
offset_bottom = -376.0
horizontal_alignment = 1
visible = false
theme_override_colors/font_color = Color(0.98, 0.95, 0.6, 1)
theme_override_colors/font_outline_color = Color(0.03, 0.05, 0.1, 1)
theme_override_constants/outline_size = 4
theme_override_font_sizes/font_size = 30
```

Extend `scripts/race/race_ui.gd` (TAB):

```gdscript
@onready var drift_label: Label = %DriftScoreLabel
@onready var poi_toast_label: Label = %POIToastLabel

const POI_DISCOVERY_GROUP := "poi_discovery"
const TOAST_DURATION_MS := 3000

var _poi_discovery: Node = null
var _toast_hide_ms := 0

func _ready() -> void:
	_poi_discovery = get_tree().get_first_node_in_group(POI_DISCOVERY_GROUP)
	if _poi_discovery != null:
		if not _poi_discovery.poi_discovered.is_connected(_on_poi_discovered):
			_poi_discovery.poi_discovered.connect(_on_poi_discovered)
```

And inside the existing `_process`, after the `time_label.text = ...` line:

```gdscript
	var drift := car.get_node_or_null("DriftController") as DriftController
	if drift != null:
		drift_label.text = "DRIFT %d" % drift.scorer.get_total_score()
		drift_label.visible = true
	else:
		drift_label.visible = false
	if poi_toast_label.visible and Time.get_ticks_msec() > _toast_hide_ms:
		poi_toast_label.visible = false
```

Plus two new functions in the same file:

```gdscript
func _on_poi_discovered(_poi_id: String, poi_name: String, stage: String) -> void:
	_show_toast("Discovered: %s (%s)" % [poi_name, stage])

func _show_toast(text_value: String) -> void:
	poi_toast_label.text = text_value
	poi_toast_label.visible = true
	_toast_hide_ms = Time.get_ticks_msec() + TOAST_DURATION_MS
```

New smoke test `tests/suites/test_hud_readouts.gd`:

```gdscript
# tests/suites/test_hud_readouts.gd
extends GdUnitTestSuite

## The HUD must instantiate and idle cleanly with no player car and no
## POIDiscovery in the tree (circuit races), and the refuse-to-crash path
## covers the drift label + toast poll in _process.
func test_hud_scene_instantiates_without_car_or_poi() -> void:
	var hud = load("res://scenes/ui/hud.tscn") as PackedScene
	assert_that(hud).is_not_null()
	var instance := hud.instantiate()
	add_child(instance)
	await await_idle_frame()
	await await_idle_frame()
	assert_that(is_instance_valid(instance)).is_true()
	if is_instance_valid(instance):
		instance.free()
```

Checkbox steps:

- [ ] 4.1 Write `tests/suites/test_hud_readouts.gd` (above).
- [ ] 4.2 Run suite → FAIL/ERROR: `@onready var drift_label: Label = %DriftScoreLabel` breaks load (label not in hud.tscn yet).
- [ ] 4.3 Edit `scenes/ui/hud.tscn` (append the two label nodes above after `TimeLabel`).
- [ ] 4.4 Edit `scripts/race/race_ui.gd` (onready refs + `_ready` wiring + `_process` additions + the two new funcs).
- [ ] 4.5 Run full verification recipe → PASS (expect `78 | 0 | 0 | 0 | 16`). Then `git commit` (`scenes/ui/hud.tscn`, `scripts/race/race_ui.gd`, `tests/suites/test_hud_readouts.gd`).

---

## Task 5 — POIDiscovery: fire once, persist, announce (C9 implementation)

**Files:** `scripts/world/poi_discovery.gd` (new), `tests/suites/test_poi_discovery.gd` (new)

**Interfaces:**
- Consumes: `POIRegistry.get_poi_ids() -> Array`, `POIRegistry.get_poi(poi_id: String) -> Dictionary`, `SaveManager.load_game(slot) -> Dictionary` / `save_game(slot, data) -> bool`, `VehicleManager.get_player_car()`.
- Produces:
  - `signal poi_discovered(poi_id: String, poi_name: String, stage: String)`
  - `const POI_DISCOVERY_GROUP := "poi_discovery"` (self-registers in `_ready`)
  - `func is_discovered(poi_id: String) -> bool`
  - `func get_discovered() -> Array[String]`
  - `func seed_discovered(ids: Array) -> void`
  - `func reset() -> void`
  - `func _check_discovery() -> void` (test-visible hook called by `_physics_process`)
  - `func _persist() -> void`
  - `var car: VehiclePhysics` (injectable; defaults to `VehicleManager.get_player_car()`)

New file `scripts/world/poi_discovery.gd` (TAB):

```gdscript
# scripts/world/poi_discovery.gd
class_name POIDiscovery
extends Node

## Watches the player car and marks a POI discovered the first time the car
## enters its discovery radius. Discoveries persist through SaveManager slot 0
## (the Garage read-modify-write pattern) and are announced on a signal so the
## HUD can toast the find.

signal poi_discovered(poi_id: String, poi_name: String, stage: String)

const POI_DISCOVERY_GROUP := "poi_discovery"
const DISCOVERY_RADIUS := 80.0

var car: VehiclePhysics

var _discovered: Array[String] = []

func _ready() -> void:
	add_to_group(POI_DISCOVERY_GROUP)
	if car == null:
		car = VehicleManager.get_player_car()
	var saved: Variant = SaveManager.load_game(0).get("discovered_pois", [])
	if saved is Array:
		for poi_id in saved:
			if poi_id is String and poi_id not in _discovered:
				_discovered.append(poi_id)

func _physics_process(_delta: float) -> void:
	_check_discovery()

func _check_discovery() -> void:
	if car == null:
		car = VehicleManager.get_player_car()
	if car == null:
		return
	for poi_id in POIRegistry.get_poi_ids():
		if poi_id in _discovered:
			continue
		var target: Vector3 = POIRegistry.get_poi(poi_id).get("position", Vector3.ZERO)
		if car.global_position.distance_to(target) <= DISCOVERY_RADIUS:
			_discovered.append(poi_id)
			var poi := POIRegistry.get_poi(poi_id)
			poi_discovered.emit(poi_id, poi.get("name", poi_id), poi.get("stage", ""))
			_persist()

func is_discovered(poi_id: String) -> bool:
	return poi_id in _discovered

func get_discovered() -> Array[String]:
	return _discovered.duplicate()

func seed_discovered(ids: Array) -> void:
	for poi_id in ids:
		if poi_id is String and poi_id not in _discovered:
			_discovered.append(poi_id)

func reset() -> void:
	_discovered.clear()

func _persist() -> void:
	var data := SaveManager.load_game(0)
	data["discovered_pois"] = _discovered.duplicate()
	SaveManager.save_game(0, data)
```

Note the explicit `var saved: Variant = ...` (no `:=` on a `Dictionary.get` Variant — warnings-as-errors).

New `tests/suites/test_poi_discovery.gd` (TAB):

```gdscript
# tests/suites/test_poi_discovery.gd
extends GdUnitTestSuite

const SLOT := 0

func _vehicle_at(pos: Vector3) -> VehiclePhysics:
	var vehicle := VehiclePhysics.new()
	vehicle.name = "PoiTestCar"
	add_child(vehicle)
	vehicle.global_position = pos
	return vehicle

func _cleanup_poi_save() -> void:
	var data := SaveManager.load_game(SLOT)
	if data.has("discovered_pois"):
		data.erase("discovered_pois")
		SaveManager.save_game(SLOT, data)

func test_pending_start_is_empty() -> void:
	var discovery := POIDiscovery.new()
	discovery.reset()
	assert_that(discovery.get_discovered().is_empty()).is_true()
	discovery.free()

func test_discovery_fires_exactly_once_per_poi() -> void:
	var discovery := POIDiscovery.new()
	add_child(discovery)
	var car := _vehicle_at(POIRegistry.get_poi("festival_hub")["position"] as Vector3)
	discovery.car = car
	var fired := 0
	discovery.poi_discovered.connect(func(_id: String, _n: String, _s: String) -> void: fired += 1)
	discovery._check_discovery()
	discovery._check_discovery()
	assert_that(fired).is_equal(1)
	assert_that(discovery.is_discovered("festival_hub")).is_true()
	car.free()
	discovery.free()

func test_distant_poi_is_not_discovered() -> void:
	var discovery := POIDiscovery.new()
	add_child(discovery)
	var car := _vehicle_at(Vector3(500.0, 0.0, 500.0))
	discovery.car = car
	var fired := 0
	discovery.poi_discovered.connect(func(_id: String, _n: String, _s: String) -> void: fired += 1)
	discovery._check_discovery()
	assert_that(fired).is_equal(0)
	car.free()
	discovery.free()

func test_seed_and_persist_roundtrip() -> void:
	_cleanup_poi_save()
	var discovery := POIDiscovery.new()
	add_child(discovery)
	discovery.seed_discovered(["dry_lake"])
	discovery._persist()
	var pois: Array = SaveManager.load_game(SLOT).get("discovered_pois", [])
	assert_that(pois).contains("dry_lake")
	var reloaded := POIDiscovery.new()
	reloaded._ready()
	assert_that(reloaded.is_discovered("dry_lake")).is_true()
	assert_that(reloaded.is_discovered("festival_hub")).is_false()
	_cleanup_poi_save()
	discovery.free()
	reloaded.free()
```

(There is no `test_garage.gd`; `test_save_manager.gd` only asserts its own roundtrip keys, so slot-0 `discovered_pois` writes are non-conflicting; the suite still cleans up after itself.)

Checkbox steps:

- [ ] 5.1 Write `tests/suites/test_poi_discovery.gd` (above).
- [ ] 5.2 Run suite → FAIL: `POIDiscovery` class unresolved (SCRIPT ERROR on import).
- [ ] 5.3 Create `scripts/world/poi_discovery.gd` exactly as above (TAB).
- [ ] 5.4 Run full verification recipe → PASS (expect `82 | 0 | 0 | 0 | 16`). Then `git commit` (`scripts/world/poi_discovery.gd` + `tests/suites/test_poi_discovery.gd`).

---

## Task 6 — Wire DriftController and POIDiscovery into the scenes (runtime activation)

**Files:** `scenes/vehicle/player_car.tscn` (edit), `scenes/world/open_world_root.tscn` (edit)

**Interfaces:** Consumes the nodes created in Tasks 2 and 5. Produces: a `DriftController` child on every player car, a `POIDiscovery` sibling in the open world.

`scenes/vehicle/player_car.tscn` — bump `load_steps=6` → `load_steps=7`, add one ext_resource and one node (append after `CarAudio`, TAB):

```
[ext_resource type="Script" path="res://scripts/race/drift_controller.gd" id="6_drift"]

[node name="DriftController" type="Node" parent="."]
script = ExtResource("6_drift")
```

`scenes/world/open_world_root.tscn` — bump `load_steps=14` → `load_steps=15`, add one ext_resource and one node. Place it after `RoadNetwork` and BEFORE `PauseMenu`/`HUD` so `race_ui._ready` finds the group member within the same scene (node `_ready` order):

```
[ext_resource type="Script" path="res://scripts/world/poi_discovery.gd" id="11_poid"]

[node name="POIDiscovery" type="Node" parent="."]
script = ExtResource("11_poid")
```

Child-processing order guarantees the freshly computed vehicle slip is what `DriftController._evaluate` reads (parent `VehiclePhysics._physics_process` runs before its children's).

Checkbox steps:

- [ ] 6.1 Commit the Task 5 state, then edit `scenes/vehicle/player_car.tscn` (DriftController node + ext_resource).
- [ ] 6.2 Edit `scenes/world/open_world_root.tscn` (POIDiscovery node + ext_resource, ordered before HUD).
- [ ] 6.3 Run full verification recipe → PASS (expect `82 | 0 | 0 | 0 | 16`, unchanged count but the new nodes now load in-tree). Then `git commit` (the two `.tscn` files).

---

## Task 7 — Final verification + self-review

**Files:** none (verification only)

Checkbox steps:

- [ ] 7.1 `git status --short` → only the intended tracked files; zero `*.uid`.
- [ ] 7.2 Run the import probe: expect ZERO `SCRIPT ERROR` / `Parse Error` / `Failed to load`.
- [ ] 7.3 Run the GDUnit suite; `Overall Summary:` must read `82 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans` (or exactly your running total — at this point 82; orphan count +- a few is benign).
- [ ] 7.4 Grep the changed/new files for placeholders: `findstr /S /C:"TODO" /C:"TBD" /C:"FIXME" /C:"placeholder" /C:"XXX" scripts\race\drift_controller.gd scripts\world\poi_discovery.gd scripts\race\race_ui.gd scripts\vehicle\vehicle_physics.gd tests\test_drift_scoring.gd` → expect no output. Add an explicit follow-up only if something surfaces (it should be nothing — every line above is concrete).
- [ ] 7.5 Confirm nothing was touched outside the allowlist: `AGENTS.md`, `start_game.bat`, `play_game.bat`, `.godot/`, `project.godot` all unchanged (`git status --short` shows none).

---

## Self-Review

**Inventory → task mapping:**
- **C5 (drift_scorer unwired) → Tasks 1, 2, 4:** slip is now readably exposed (`get_slip_angle_deg`), `DriftController` feeds the scorer from real vehicle state every physics tick and emits `score_updated`/`drift_started`/`drift_ended`, and the HUD shows a live `DRIFT <n>` readout. Scorer data flow is call-only — `DriftScorer` itself is untouched (zero regression surface).
- **C9 (POI arrival does nothing) → Tasks 5, 6:** `POIDiscovery` fires `poi_discovered` exactly once per POI per session when the player enters the 80 m radius, persists via `SaveManager` slot 0 under `discovered_pois` (Garage pattern), and `race_ui` toasts `Discovered: <name> (<stage>)` for 3 s. Pause-map POI dots (world_map.gd:69-74) are left untouched; only the new discovery layer is added.
- **D6 (no drift tests) → Tasks 1, 2, 3 (+ 4, 5 tests):** 8 drift-scoring tests (slip getter contract, controller scoring/threshold/start-end events, scorer accumulation/zero/end/reset) plus 4 POI-discovery tests (empty start, fire-once, no-fire-when-far, seed+persist roundtrip) plus 1 HUD smoke test = 13 new test cases; baseline 69 → 82.

**Placeholder scan:** no `TODO`/`TBD`/`FIXME`/`placeholder`/`XXX` anywhere in the plan's code; every signature matches a getter/field verified by reading the actual files (vehicle_physics.gd:147-165, poi_registry.gd:7-42, race_ui.gd, garage.gd:46-50, save_manager.gd:12-35). The only forward dependency is Task 1 → Tasks 2/4 (getter must exist before `DriftController`/HUD read it) and Task 5 → Task 4/6 (`poi_discovered` signal and scene node feed the HUD). Task ordering above enforces both.

**Verification evidence:** tasks gate on the AGENTS.md known-good recipe — import probe (zero SCRIPT ERROR/Parse Error/Failed to load) before every suite run, suite summary grepped to `Overall Summary:`, and `_gdunit.txt` preserved as the evidence artifact per session. 69/0/0/0/16 baseline never regresses; expected end state 82/0/0/0/16.