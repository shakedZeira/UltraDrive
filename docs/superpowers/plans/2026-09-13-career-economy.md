# Career Economy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the shelved career classes (C4) into a minimal-but-real, testable (D6) career loop: races pay prize money, championships gate events by license tier, the shop + garage spend the money on cars, and everything persists through `SaveManager`.
**Architecture:** Pure `RefCounted`/`Node` logic classes keep the economy unit-testable with zero scenes; a thin `CareerManager` autoload glues them to existing autoload signals (`RaceManager.race_finished`, `VehicleManager.get_player_car`, `SaveManager`); small UI scenes (career hub, shop) plus one main-menu button expose the loop.
**Tech Stack:** Godot 4.7.2 GDScript, GDUnit4
**Spec:** inventory C4 + D6 (see preamble)

## Global Constraints

- **TAB indentation** everywhere new/edited GDScript and `.tscn`. Follow the DOM-style style of `championship.gd`/`garage.gd` (tabs) and `.tscn` 4-space node indents (Godot writes tabs in scenes — keep whatever the editor writes).
- **Do NOT modify or create**: `AGENTS.md`, `start_game.bat`, `play_game.bat`, anything under `.godot/`. Never `git add -A`. `git status --short` should never list `*.uid` files; commit only intended source files (if a `.uid` shows as new, leave it untracked).
- **GDUnit4 treats GDScript warnings as errors.** Never use `:=` on a call that returns `Variant` (e.g. `JSON.parse_string(...)`, `Dictionary.get(...)`). Use explicit `var x: Variant = ...` then an `is Dictionary`/cast when the value must be typed. Approx vector asserts need same-type args (see `test_world_map_features.gd`).
- **Verification (run after EVERY task, before commit):**
  1. `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import . 2>&1 | findstr /i "SCRIPT ERROR Parse Error Failed to load"` → expect ZERO matching lines.
  2. `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1` then `findstr /c:"Overall Summary:" _gdunit.txt`. Baseline is `69 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans` and it GROWS with each landed test; compare the count against the previous run, never a hard constant, and never commit while errors/failures > 0.
- **Commit style** (matches repo): `feat(D6): <imperative summary>` for code tasks, `tests(D6): ...` for test-only commits. Commit after each green task. The playtest loop (garage→select→drive, right-stick orbit, FH5/GT7 garage) must keep working at the end.
- **Scope guard — MUST NOT go here:** no license *test-driving* flow (no timed lap license exams, no silver/gold per-tier driving challenges in this plan — `license.promote_license()` advances tiers programmatically on championship completion instead); no multiple championships running in parallel; no car tuning/upgrades/stats shopping beyond buying whole cars; no AI opponent economy; no currency sinks beyond the car shop; no career XP/level system. `GameState.GameMode.LICENSE_TEST` stays unused by this plan.
- **Parallel-plan dependency (explicit):** this plan CONSUMES exactly two existing autoload surfaces — `RaceManager.race_finished(standings: Array)` and `VehicleManager.get_player_car() -> VehiclePhysics`. It never calls `RaceManager.start_race(...)` (career races are launched by flashing the track scene, just like `track_select.gd` already does). If the parallel race-loop plan changes the `race_finished` standings element type away from `VehiclePhysics`, only `CareerManager._on_race_finished()` `standings.find(car)` needs to adapt (see Task 6).

---

## Task 1 — `CareerProfile` economy model (pure RefCounted) + D6 tests

**Files:**
- NEW `scripts/career/career_profile.gd`
- NEW `tests/suites/test_career_economy.gd` (this task's tests live here; later tasks append to it)

**Interfaces**
- Consumes: `SaveManager.load_game(0)` / `SaveManager.save_game(0, data)` (existing autoloads, merged-dictionary write style exactly like `Garage.save()`).
- Produces (exact sigs):
  - `class_name CareerProfile extends RefCounted`
  - `const PRIZE_TABLE: Dictionary = {1:10000, 2:7000, 3:5000, 4:3000, 5:1500, 6:1000}`
  - `const PRIZE_FALLBACK: int = 500`
  - `static func new_from_save() -> CareerProfile`
  - `func get_money() -> int`
  - `func spend_money(amount: int) -> bool` (false if `amount < 0` or `amount > _money`)
  - `func record_finish(position: int, participant_count: int) -> int` (returns prize; clamps poor positions; `position == 1` also counts a win)
  - `func award_championship_bonus(bonus: int) -> void`
  - `func get_races_completed() -> int`
  - `func get_races_won() -> int`
  - `func to_dict() -> Dictionary` (keys: `money`, `races_completed`, `races_won`)
  - `func load_data(data: Dictionary) -> void`
  - `func save() -> void`

**Steps**
- [ ] 1.1 Write 5 failing tests in `test_career_economy.gd`: (a) `new_from_save` on a pristine/slot-0 state starts at `money == 0`; (b) `record_finish(1, 6)` returns `10000` and `get_money() == 10000`, `get_races_won() == 1`; (c) `record_finish(9, 6)` returns `500` (clamped fallback) and still bumps `races_completed` but not wins; (d) `spend_money(5000)` reduces money, `spend_money(999999)` returns false and leaves money unchanged, `spend_money(-1)` returns false; (e) `to_dict()`/`load_data()` roundtrip preserves the three fields.
  `extends GdUnitTestSuite`; no scene frames needed (pure RefCounted). Run suite → expect these NEW tests FAIL (class not found).
- [ ] 1.2 Implement `career_profile.gd`:
  ```
  class_name CareerProfile
  extends RefCounted

  const PRIZE_TABLE := {1: 10000, 2: 7000, 3: 5000, 4: 3000, 5: 1500, 6: 1000}
  const PRIZE_FALLBACK := 500

  var _money: int = 0
  var _races_completed: int = 0
  var _races_won: int = 0

  static func new_from_save() -> CareerProfile:
  	var profile := CareerProfile.new()
  	var save_data: Dictionary = SaveManager.load_game(0)
  	profile.load_data(save_data)
  	return profile

  func get_money() -> int:
  	return _money

  func spend_money(amount: int) -> bool:
  	if amount < 0 or amount > _money:
  		return false
  	_money -= amount
  	return true

  func record_finish(position: int, participant_count: int) -> int:
  	var pos := position if position >= 1 else 1
  	var prize: int = PRIZE_TABLE.get(pos, PRIZE_FALLBACK)
  	_money += prize
  	_races_completed += 1
  	if pos == 1:
  		_races_won += 1
  	return prize

  func award_championship_bonus(bonus: int) -> void:
  	_money += bonus

  func get_races_completed() -> int:
  	return _races_completed

  func get_races_won() -> int:
  	return _races_won

  func to_dict() -> Dictionary:
  	return {"money": _money, "races_completed": _races_completed, "races_won": _races_won}

  func load_data(data: Dictionary) -> void:
  	var cp: Variant = data.get("career_profile", {})
  	if cp is Dictionary:
  		_money = int(cp.get("money", 0))
  		_races_completed = int(cp.get("races_completed", 0))
  		_races_won = int(cp.get("races_won", 0))

  func save() -> void:
  	var data := SaveManager.load_game(0)
  	data["career_profile"] = to_dict()
  	SaveManager.save_game(0, data)
  ```
  Run suite → all tests PASS.
- [ ] 1.3 Run Global-Constraints verification (import=zero, gdunit green), then commit `feat(D6): career profile economy model (prize money, spend/earn, win counters) + tests`.

---

## Task 2 — `LicenseSystem` upgrades: persistence `load_data`, `promote_license`, `class_required_tier` + D6 tests

**Files:**
- EDIT `scripts/career/license_system.gd`
- EDIT `tests/suites/test_career_economy.gd`

**Interfaces**
- Consumes: existing `TIERS := ["B","A","S","Race","Elite"]`, `RATINGS`, `results`, `complete_test(tier, rating)`, `get_license_tier()`, `is_car_unlocked(car_class)`, `save()` — keep them unchanged (C4 backwards-compatible).
- Produces (additions to `LicenseSystem`, exact sigs):
  - `func promote_license() -> bool` — advances `get_license_tier()` one step via `complete_test(next_tier, "Gold")`; returns `false` at "Elite" (no-op) or if current tier unknown.
  - `func load_data(data: Dictionary) -> void` — `results = data["license_results"]` when present (fixes the C4 bug: `save()` persisted but nothing ever restored).
  - `static func license_class_index(car_class: String) -> int` (index of `car_class` in `["D","C","B","A","S"]`, `-1` if unknown)
  - `static func class_required_tier(car_class: String) -> String` — `TIERS[clampi(class_index - 1, 0, TIERS.size() - 1)]` (UI text: which license a class needs).

**Steps**
- [ ] 2.1 Add tests: (a) `promote_license` from B → A, then → S, then → Race, then → Elite, then returns false at Elite; `get_best_rating("A") == "Gold"`; (b) `load_data` with `{"license_results": {"B": "Gold"}}` makes `get_license_tier() == "B"`; `load_data({})` leaves results empty; (c) `is_car_unlocked` matrix: tier B unlocks D and C but NOT B-class; after `promote_license()` (tier A) unlocks B-class too; (d) `class_required_tier("C") == "B"`, `class_required_tier("B") == "A"`, `class_required_tier("S") == "Race"`. Use `before_test() -> void: CareerManager` NOT needed here — construct `LicenseSystem.new()` locally; DO NOT call `save()` paths that would touch slot 0 (avoid `complete_test` unless asserted tier stays local). Run → new tests FAIL (methods missing).
- [ ] 2.2 Implement the three additions (tabs; reuse existing `_rating_rank`; `complete_test` already guards invalid tiers):
  ```
  func promote_license() -> bool:
  	var tier := get_license_tier()
  	var idx := TIERS.find(tier)
  	if idx == -1 or idx >= TIERS.size() - 1:
  		return false
  	complete_test(TIERS[idx + 1], "Gold")
  	return true

  func load_data(data: Dictionary) -> void:
  	if data.has("license_results"):
  		var stored: Variant = data["license_results"]
  		if stored is Dictionary:
  			results = stored

  static func license_class_index(car_class: String) -> int:
  	return ["D", "C", "B", "A", "S"].find(car_class)

  static func class_required_tier(car_class: String) -> String:
  	var class_index := ["D", "C", "B", "A", "S"].find(car_class)
  	if class_index == -1:
  		return ""
  	return TIERS[clampi(class_index - 1, 0, TIERS.size() - 1)]
  ```
  Run → PASS.
- [ ] 2.3 Verification + commit `feat(D6): license tier promotion + save roundtrip load_data + class-required-tier helper (+ tests)`.

---

## Task 3 — `Championship` API additions for progress UI + state roundtrip + D6 tests

**Files:**
- EDIT `scripts/career/championship.gd`
- EDIT `tests/suites/test_career_economy.gd`

**Interfaces** (additions only; keep `POINTS`, `start_championship`, `complete_race`, `get_standings`, `is_complete`, `get_next_race` unchanged): exact sigs:
  - `func get_current_race_index() -> int` (returns `_current_race`)
  - `func get_total_races() -> int` (returns `races.size()`)
  - `func to_dict() -> Dictionary` — `{"name", "races", "scores", "current_race"}`
  - `func load_data(data: Dictionary) -> void` — restores the four keys when present.

**Steps**
- [ ] 3.1 Add tests: (a) 3-race championship: `get_total_races() == 3`, after `complete_race(1/3/5)` → `get_current_race_index() == 3`, `is_complete()` true, standings `{"player": 25+18+10}` (POINTS[0]+POINTS[2]+POINTS[5]); (b) out-of-range position still advances `_current_race`; (c) `to_dict()`/`load_data()` roundtrip preserves name/races/scores/current_race (build the dict from a live championship, feed it to a fresh one, assert equal standings + index). Pure `Championship.new()`, no scene. Run → FAIL.
- [ ] 3.2 Implement the four methods (tabs; arrays/dicts are passed by reference — use `.duplicate(true)` inside `load_data` for `_scores`/`races` to avoid aliasing save memory):
  ```
  func get_current_race_index() -> int:
  	return _current_race

  func get_total_races() -> int:
  	return races.size()

  func to_dict() -> Dictionary:
  	return {"name": championship_name, "races": races, "scores": _scores, "current_race": _current_race}

  func load_data(data: Dictionary) -> void:
  	if data.has("name"):
  		championship_name = data["name"]
  	if data.has("races"):
  		races = (data["races"] as Array).duplicate(true)
  	if data.has("scores"):
  		_scores = (data["scores"] as Dictionary).duplicate(true)
  	if data.has("current_race"):
  		_current_race = data["current_race"]
  ```
  Run → PASS.
- [ ] 3.3 Verification + commit `feat(D6): championship progress getters + save roundtrip (+ tests)`.

---

## Task 4 — D6: `DriftScorer` baseline coverage (pure, tiny)

**Files:**
- NEW `tests/suites/test_drift_scorer.gd`

**Interfaces**
- Consumes: existing `DriftScorer` (`scripts/race/drift_scorer.gd`, `class_name DriftScorer`, RefCounted): `update(delta, slip_angle_deg, drifting) -> float`, `get_total_score() -> int`, `reset()`. No changes to the class.

**Steps**
- [ ] 4.1 Tests: (a) drifting frames accumulate: call `update(0.016, 30.0, true)` x5 → `get_total_score() > 0` and per-frame return > 0; (b) when NOT drifting, after a drift session, `update(0.016, 0.0, false)` returns 0 and `is_drifting == false`; (c) `reset()` zeroes `get_total_score()` and `is_drifting`; (d) a pure non-drifting stream never scores (`get_total_score() == 0`). Pure `DriftScorer.new()`. Run → tests pass immediately (existing class) — count as landed D6 coverage.
- [ ] 4.2 Verification (import must stay zero-error; gdunit grows by 4) + commit `tests(D6): drift scorer baseline coverage`.

---

## Task 5 — `ChampionshipRegistry` + `CarShop` + two buyable car configs + tests

**Files:**
- NEW `scripts/career/championship_registry.gd`
- NEW `scripts/career/car_shop.gd`
- NEW `resources/cars/hot_hatch.tres`
- NEW `resources/cars/grand_tourer.tres`
- EDIT `tests/suites/test_career_economy.gd`

**Interfaces**
- Consumes: `TrackRegistry` (existing static, for track metadata only — registry stores `track_scene` strings directly, no dependency at runtime), `CarConfig` resource class, `LicenseSystem.license_class_index`.
- Produces:
  - `class_name ChampionshipRegistry extends RefCounted`
  - `static func get_events() -> Array` — `Array[Dictionary]`, each:
    - `{"id": "national_d", "name": "National D Cup", "required_class": "D", "track_scene": "res://scenes/test/test_track.tscn", "laps": 3, "completion_bonus": 25000, "races": [{"name": "Round 1", "track_id": "oval"}, {"name": "Round 2", "track_id": "oval"}, {"name": "Round 3", "track_id": "oval"}]}`
    - `{"id": "national_c", "name": "National C Trophy", "required_class": "C", "track_scene": "res://scenes/test/test_track.tscn", "laps": 3, "completion_bonus": 40000, "races": same three oval rounds}`
    - `{"id": "national_b", "name": "National B Championship", "required_class": "B", "track_scene": "res://scenes/track/mountain_pass.tscn", "laps": 2, "completion_bonus": 60000, "races": [{"name": "Round 1", "track_id": "mountain_pass"}, x3]}`
  - `static func get_event(event_id: String) -> Dictionary`
  - `static func get_event_ids() -> Array[String]`
  - `class_name CarShop extends RefCounted`
  - `static func get_catalog() -> Array` — `Array[Dictionary]`: `{"car_id": "hot_hatch", "price": 12000}` and `{"car_id": "grand_tourer", "price": 32000}`
  - `static func get_price(car_id: String) -> int` (0 for unknown)
  - `static func is_buyable(car_id: String) -> bool` (in catalog)
- The two `.tres` are `CarConfig` resources (`script_class="CarConfig"`, `ext_resource` to `res://scripts/vehicle/car_config.gd`), reusing existing glbs (no new Blender assets):
  - `hot_hatch.tres`: `car_name = "Pocket Rocket"`, `car_class = "C"`, `visual_path = "res://assets/cars/sports_coupe.glb"`, `engine_timbre = "sport"`, mass 980, torque 210, redline 7000, 5-speed, tire_D 1.0, spring 38000, brake 2300, steer 36.
  - `grand_tourer.tres`: `car_name = "Grand Tourer"`, `car_class = "B"`, `visual_path = "res://assets/cars/muscle_car.glb"`, `engine_timbre = "muscle"`, mass 1500, torque 480, redline 6400, 5-speed, tire_D 0.94, spring 36000, brake 2600, steer 33.
  - Both files must be model-checked by an `--headless --import` before the suite runs (`CarConfig` field names exactly as in the starter/muscle tres: `car_name`, `car_class`, `visual_path`, `mass_kg`, `max_torque`, `peak_rpm`, `redline_rpm`, `gear_ratios`, `final_drive_ratio`, `tire_B/C/D/E`, `spring_rate`, `max_brake_torque`, `max_steer_angle`).

**Steps**
- [ ] 5.1 Tests: (a) `ChampionshipRegistry.get_events().size() == 3`, `get_event("national_d")` has `required_class == "D"` + non-empty `races`, `get_event("nope").is_empty()`; (b) `CarShop.get_catalog().size() == 2`, `get_price("hot_hatch") == 12000`, `get_price("phantom") == 0`, `is_buyable("starter_car") == false`, `is_buyable("hot_hatch") == true`. Run → FAIL (scripts don't exist).
- [ ] 5.2 Implement `championship_registry.gd` + `car_shop.gd` (static dictionaries exactly as specced above; `get_event` returns `{}` for unknown ids; tabs). Run → PASS.
- [ ] 5.3 Add the two `.tres`; run `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import . 2>&1 | findstr /i "SCRIPT ERROR Parse Error Failed to load"` → zero matches, and `resources/cars/hot_hatch.tres`/`grand_tourer.tres` load as `CarConfig` (sanity: `load("res://resources/cars/hot_hatch.tres") as CarConfig`).
- [ ] 5.4 Verification (import zero, gdunit green) + commit `feat(D6): championship + car-shop catalogs and two buyable B/C car configs (+ tests)`.

---

## Task 6 — `CareerManager` autoload: race-finish → currency/championship/license flow + persistence + integration tests

**Files:**
- NEW `scripts/career/career_manager.gd`
- EDIT `project.godot` (append to `[autoload]`: `CareerManager="*res://scripts/career/career_manager.gd"` — must come AFTER the `SaveManager`, `RaceManager`, `VehicleManager` lines; it depends on them at runtime only, so append works)
- EDIT `tests/suites/test_career_economy.gd`

**Interfaces**
- Consumes (existing, exact):
  - `RaceManager.race_finished(standings: Array)` — autoload signal, `Array[VehiclePhysics]` desc by lap; **this is the race-loop-parallel-plan contract**.
  - `VehicleManager.get_player_car() -> VehiclePhysics`
  - `SaveManager.load_game(0)` / `save_game(0, data)`
  - `Garage.new_from_save()`, `.get_owned_cars()`, `.add_car(car_id)`
  - `Championship`, `LicenseSystem`, `CareerProfile`, `ChampionshipRegistry`, `CarShop` (own classes from Tasks 1-3, 5)
- Produces (exact sigs), `class_name CareerManager extends Node`:
  - `var profile: CareerProfile`
  - `var championship: Championship`
  - `var license: LicenseSystem`
  - `func _ready() -> void` — `profile = CareerProfile.new_from_save()`, `championship = Championship.new()`, `license = LicenseSystem.new()`, restore saves, `RaceManager.race_finished.connect(_on_race_finished)`
  - `func _on_race_finished(standings: Array) -> void`
  - `func start_championship(event_id: String) -> bool`
  - `func can_start_event(event_id: String) -> bool`
  - `func get_unlocked_event_ids() -> Array[String]`
  - `func get_active_event() -> Dictionary`
  - `func get_next_race() -> Dictionary` (delegates `championship.get_next_race()`)
  - `func get_championship_index() -> int`
  - `func get_championship_total() -> int`
  - `func is_championship_complete() -> bool`
  - `func get_money() -> int`
  - `func get_license_tier() -> String`
  - `func buy_car(car_id: String) -> bool`
  - `func save() -> void`
  - `func reset_for_test() -> void`

**Step 6.1 — failing integration tests first**
- [ ] Tests (in `test_career_economy.gd`):
  1. `before_test()` calls `CareerManager.reset_for_test()` (isolate from earlier suites' slot-0 writes — `test_save_manager.gd` pollutes slot 0 by design).
  2. `test_race_finish_credits_currency`: build a real-but-treeless `var car := VehiclePhysics.new()`, `VehicleManager.register_player_car(car)`, return `[car]` as standings, call `CareerManager._on_race_finished([car])` → `CareerManager.get_money() == 10000`, `profile.get_races_completed() == 1`, `profile.get_races_won() == 1`; then `VehicleManager.remove_car(car)`. (No `add_child`, so `VehiclePhysics._ready()` never runs — no wheel nodes needed.)
  3. `test_race_finish_positions_from_standings`: with no player car registered, `_on_race_finished([])` clamps to position 1 (`get_money() >= 10000`).
  4. `test_championship_event_progression`: `start_championship("national_d")` returns true; `_on_race_finished([car])` x3 with the same car → `is_championship_complete() == true`; completing bumps profile by `completion_bonus` (25000) and `license.get_license_tier() == "A"` (promoted from B).
  5. `test_event_unlock_gating`: at tier B, `can_start_event("national_d")` true, `can_start_event("national_b")` false, `"national_b" not in get_unlocked_event_ids()`; after `license.promote_license()` (→ A) `can_start_event("national_b")` true.
  6. `test_buy_car_flow`: after `start_championship` + 2 wins `buy_car("hot_hatch")` true and money decreased by 12000; `buy_car("hot_hatch")` again returns false (owned); `buy_car("phantom")` returns false.
  Run → new tests FAIL (new `CareerManager` autoload missing, so the suite fails at class resolution — expected FAIL state).

**Step 6.2 — minimal implementation**
- [ ] `career_manager.gd` (tabs):
  ```
  class_name CareerManager
  extends Node

  var profile: CareerProfile = null
  var championship: Championship = null
  var license: LicenseSystem = null
  var _active_event_id: String = ""

  func _ready() -> void:
  	championship = Championship.new()
  	_restore_from_save()
  	RaceManager.race_finished.connect(_on_race_finished)

  func _restore_from_save() -> void:
  	var data: Dictionary = SaveManager.load_game(0)
  	profile = CareerProfile.new()
  	profile.load_data(data)
  	license = LicenseSystem.new()
  	license.load_data(data)
  	var active: Variant = data.get("championship_active_event", "")
  	if active is String and active != "":
  		_start_championship_state(active, data.get("championship", {}))

  func _on_race_finished(standings: Array) -> void:
  	var car := VehicleManager.get_player_car()
  	var position := int(standings.find(car)) + 1
  	if position <= 0:
  		position = maxi(standings.size(), 1)
  	var prize := profile.record_finish(position, standings.size())
  	if not championship.championship_name.is_empty():
  		championship.complete_race(position)
  		if championship.is_complete():
  			var event := ChampionshipRegistry.get_event(_active_event_id)
  			var bonus: int = event.get("completion_bonus", 25000)
  			profile.award_championship_bonus(bonus)
  			license.promote_license()
  			championship = Championship.new()
  			_active_event_id = ""
  	save()

  func start_championship(event_id: String) -> bool:
  	var event := ChampionshipRegistry.get_event(event_id)
  	if event.is_empty():
  		return false
  	_active_event_id = event_id
  	championship = Championship.new()
  	championship.start_championship(event.get("name", event_id), event.get("races", []))
  	save()
  	return true

  func _start_championship_state(event_id: String, saved: Variant) -> void:
  	var event := ChampionshipRegistry.get_event(event_id)
  	if event.is_empty():
  		return
  	_active_event_id = event_id
  	championship = Championship.new()
  	championship.start_championship(event.get("name", event_id), event.get("races", []))
  	if saved is Dictionary:
  		championship.load_data(saved)

  func can_start_event(event_id: String) -> bool:
  	var event := ChampionshipRegistry.get_event(event_id)
  	if event.is_empty():
  		return false
  	return license.is_car_unlocked(event.get("required_class", ""))

  func get_unlocked_event_ids() -> Array[String]:
  	var result: Array[String] = []
  	for event in ChampionshipRegistry.get_events():
  		var event_id: String = event.get("id", "")
  		if license.is_car_unlocked(event.get("required_class", "")):
  			result.append(event_id)
  	return result

  func get_active_event() -> Dictionary:
  	return ChampionshipRegistry.get_event(_active_event_id)

  func get_next_race() -> Dictionary:
  	return championship.get_next_race()

  func get_championship_index() -> int:
  	return championship.get_current_race_index()

  func get_championship_total() -> int:
  	return championship.get_total_races()

  func is_championship_complete() -> bool:
  	return championship.is_complete()

  func get_money() -> int:
  	return profile.get_money()

  func get_license_tier() -> String:
  	return license.get_license_tier()

  func buy_car(car_id: String) -> bool:
  	var garage := Garage.new_from_save()
  	if car_id in garage.get_owned_cars():
  		return false
  	var price := CarShop.get_price(car_id)
  	if price <= 0 or not profile.spend_money(price):
  		return false
  	garage.add_car(car_id)
  	save()
  	return true

  func save() -> void:
  	var data := SaveManager.load_game(0)
  	data["career_profile"] = profile.to_dict()
  	data["license_results"] = license.results
  	data["championship_active_event"] = _active_event_id
  	data["championship"] = championship.to_dict()
  	SaveManager.save_game(0, data)

  func reset_for_test() -> void:
  	profile = CareerProfile.new()
  	license = LicenseSystem.new()
  	championship = Championship.new()
  	_active_event_id = ""
  ```
  Note: `_on_race_finished` keeps `_active_event_id` when a championship is still running (start_championship stores it; `save()` persists it; `_restore_from_save` resumes it). `reset_for_test` deliberately does NOT save so slot 0 stays untouched by tests.
- [ ] Add the `CareerManager` autoload line to `project.godot` `[autoload]` (append; autoload section is order-sensitive — keep it after `SaveManager`).
- [ ] 6.3 Verification: full import pass then full gdunit run. If `VehiclePhysics.new()` triggers any GDUnit warning (it must not be added to tree, so no `_ready`, no onready `$WheelFL` hits), restructure the integration test to pass a bare `RigidBody3D`-subclass test double registered in `VehicleManager` instead. Expect the 6 integration tests green. Commit `feat(D6): career manager autoload — race finishes pay prize money, drive championship/license progression, shop purchases; persisted via SaveManager`.

---

## Task 7 — Career hub UI scene + main-menu entry

**Files:**
- NEW `scenes/ui/career_hub.tscn`
- NEW `scripts/ui/career_hub.gd`
- EDIT `scenes/ui/main_menu.tscn` (add `CareerButton` node between `GarageButton` and `ContinueButton`, plus one `[connection]`)
- EDIT `scripts/ui/main_menu.gd` (add `func _on_career_pressed()`)

**Interfaces**
- Consumes: `CareerManager` getters (`get_money`, `get_license_tier`, `can_start_event`, `get_unlocked_event_ids`, `start_championship`, `get_active_event`, `get_championship_index`, `get_championship_total`, `get_next_race`), `ChampionshipRegistry` (event list), `SceneTransition.flash_to_scene`, `LicenseSystem.class_required_tier` (status text).
- Produces: `class_name CareerHub extends Control` with public methods `func refresh() -> void` and `func select_event(event_id: String) -> void` (UI test / future-proofing).

**career_hub.tscn node tree (unique names via `unique_name_in_owner = true`):**
```
CareerHub (Control, full-rect, script = career_hub.gd)
├─ Background (ColorRect full-rect, mouse_filter=2, color 0.055 0.07 0.12)
├─ Margin (MarginContainer, offsets 28/18/-28/-96)
│  └─ VBox (VBoxContainer, separation 10)
│     ├─ TitleLabel "CAREER" (accent font, size 22)
│     ├─ MoneyLabel  (%MoneyLabel)
│     ├─ LicenseLabel (%LicenseLabel)
│     ├─ EventRail (HBoxContainer, %EventRail)          # event cards built in code
│     ├─ EventNameLabel (%EventNameLabel)
│     ├─ EventStatusLabel (%EventStatusLabel)
│     ├─ ProgressLabel (%ProgressLabel)
│     └─ ButtonsRow (HBoxContainer, separation 14)
│        ├─ StartRaceButton (%StartRaceButton) "START RACE"
│        ├─ ShopButton (%ShopButton) "SHOP"
│        ├─ GarageButton (%GarageButton) "GARAGE"
│        └─ BackButton (%BackButton) "BACK"
```
Style buttons to match garage.tscn (`btn_gold`/`btn_dark` styleboxes — duplicate the four StyleBoxFlat sub-resources). Cards reuse the `track_select.gd` card pattern (Button with VBox of class-letter + name, `_card_style`-like toggle).

**career_hub.gd responsibilities (tabs, mirrors `track_select.gd` structure):**
- `_ready`: connect `StartRaceButton/ShopButton/GarageButton/BackButton`; `refresh()`; select first unlocked event.
- `refresh()`: set `%MoneyLabel "CREDITS" % money`, `%LicenseLabel "LICENSE: %s" % tier`, rebuild `%EventRail` cards from `ChampionshipRegistry.get_events()` (each card shows class + display name), then `_update_selected()`.
- `_update_selected()`: `%ProgressLabel "RACE %d OF %d" % [CareerManager.get_championship_index() if active else 0, CareerManager.get_championship_total() if active else event.races.size() + 1]` (progress of an active championship, or "0 of N" otherwise); `%EventStatusLabel` = `"UNLOCKED — CLASS %s" % required_class` when `CareerManager.can_start_event(id)` else `"REQUIRES %s LICENSE" % LicenseSystem.class_required_tier(required_class)`; `%StartRaceButton.disabled = not unlocked`.
- `_on_start_pressed`: if `CareerManager.can_start_event(selected)`: `CareerManager.start_championship(selected)`; `SceneTransition.flash_to_scene(event.track_scene)`.
- `_on_shop_pressed` / `_on_garage_pressed`: `SceneTransition.flash_to_scene("res://scenes/ui/shop.tscn")` / `".../garage.tscn"`.
- `_on_back_pressed`: `SceneTransition.flash_to_scene("res://scenes/ui/main_menu.tscn")`.

**main_menu edits:** add `CareerButton` (text "Career", `custom_minimum_size = Vector2(0, 40)`) between `GarageButton` and `ContinueButton`; connection `[connection signal="pressed" from="MenuLayout/CareerButton" to="." method="_on_career_pressed"]`; `func _on_career_pressed() -> void: SceneTransition.flash_to_scene("res://scenes/ui/career_hub.tscn")`.

**Steps**
- [ ] 7.1 Create `career_hub.gd` with all handlers + `refresh/select_event` AND the scene tree above (tabs). No test file for the scene (UI is only smoke-checked); verify the scene loads with a probe run.
- [ ] 7.2 Edit `main_menu.tscn` + `main_menu.gd` for the Career button.
- [ ] 7.3 Verification: import zero errors; gdunit still green (no new tests this task); commit `feat(D6): career hub screen (license tier, championship progress, prize money) + main-menu entry`.

---

## Task 8 — Shop scene (car purchases gated by money + license)

**Files:**
- NEW `scenes/ui/shop.tscn`
- NEW `scripts/ui/shop_ui.gd`

**Interfaces**
- Consumes: `CarShop.get_catalog`/`get_price`, `CareerManager.get_money`/`buy_car`/`get_license_tier`, `load("res://resources/cars/%s.tres")` → `CarConfig`, `LicenseSystem.is_car_unlocked` (instance method on `CareerManager.license` — expose a passthrough `CareerManager.func is_car_unlocked(car_class: String) -> bool: return license.is_car_unlocked(car_class)` via Task 6 edit, or call `license` directly in UI; prefer the passthrough for UI decoupling), `Garage.new_from_save().get_owned_cars()`.
- Produces: `class_name ShopUI extends Control` (scene script; no public contract needed beyond handlers).

**shop.tscn node tree:**
```
Shop (Control full-rect, shop_ui.gd)
├─ Background (ColorRect full-rect)
├─ Margin → VBox
│  ├─ TitleLabel "SHOP"
│  ├─ MoneyLabel (%MoneyLabel)
│  ├─ ShopRail (HBoxContainer %ShopRail)     # catalog cards built in code
│  ├─ PriceLabel (%PriceLabel)
│  ├─ StatusLabel (%StatusLabel)             # "OWNED" / "REQUIRES A LICENSE" / price
│  ├─ BuyButton (%BuyButton) "BUY"
│  └─ BackButton (%BackButton) "BACK"
```

**shop_ui.gd (tabs, mirrors garage_ui rail):**
- `_ready`: connect Buy/Back; `_build_rail()`; select first buyable card; refresh.
- `_build_rail()`: clear `%ShopRail`; for each `CarShop.get_catalog()` entry load its `CarConfig`; card shows class letter + `car_name` + price; track `_cards` + `_selected_ids`.
- `_update_selected()`: `%MoneyLabel "CREDITS %d"`; `%PriceLabel "$%d"`; compute owned (`car_id in Garage.new_from_save().get_owned_cars()`), locked (`not CareerManager.is_car_unlocked(config.car_class)`), affordable (`CareerManager.get_money() >= price`): `%StatusLabel` = "OWNED" | "REQUIRES %s LICENSE" (via `LicenseSystem.class_required_tier`) | "$%d — INSUFFICIENT FUNDS" when not affordable | "" ; `%BuyButton.disabled = owned or locked or not affordable`.
- `_on_buy_pressed`: `CareerManager.buy_car(selected_id)` then `_update_selected()` (button disables once owned).
- `_on_back_pressed`: `flash_to_scene("res://scenes/ui/career_hub.tscn")`.

**Steps**
- [ ] 8.1 Write `shop_ui.gd` + `shop.tscn` as specced (plus the `CareerManager.is_car_unlocked` passthrough from Task 6 if not already added — if needed, add it in Task 6 alongside `get_license_tier`).
- [ ] 8.2 Verification (import zero, gdunit green) + commit `feat(D6): car shop — buy catalog cars with prize money, license-gated, SaveManager persistence through CareerManager`.

---

## Task 9 — Full verification sweep + smoke-run the loop

**Files:** none (verification-only).

**Steps**
- [ ] 9.1 `git status --short` → no `*.uid` files listed; diff review per file (only intended source edits).
- [ ] 9.2 Headless import probe (`--headless --import .` then findstr `SCRIPT ERROR|Parse Error|Failed to load`) → zero lines.
- [ ] 9.3 GDUnit full run → `findstr /c:"Overall Summary:" _gdunit.txt`; expect baseline 69 + (5 + 4 + 3 + 4 + 2 + 6) = 93 test cases, `0 errors | 0 failures | 0 flaky | 0 skipped`, orphans grow from 16 only via SceneTransition/autoload noise (benign). If any failures: fix, re-run, do NOT commit red.
- [ ] 9.4 Smoke (manual, runtime — a GPU window opens; NOT headless): main menu → Career → hub shows `LICENSE: B`, `CREDITS $0`, `National D Cup` unlocked, `National B Championship` shows `REQUIRES A LICENSE`; START RACE on D Cup launches the track scene; finish a race → money credits. Back → Garage shows owned trio still. Shop shows Pocket Rocket ($12,000) and Grand Tourer ($32,000, requires A); buy Pocket Rocket → disappears from shop, appears in Garage. (If a full 3-lap, 120-tick-physics race is impractical in one session, confirm at minimum that the loop hand-offs exist and hub state is correct; leave the runtime smoke as a playtest note.)
- [ ] 9.5 Commit any final fallout fixes as separate `fix(D6): ...` commits. Do NOT touch `AGENTS.md`.

---

## Self-Review

**C4 → tasks:** `Championship` + `LicenseSystem` (zero callers/UI/flow) get called from `CareerManager` (Task 6), rendered by `career_hub.tscn` (Task 7), and gated by license via `can_start_event`/`get_unlocked_event_ids`; garage purchase flow → `CarShop` + `shop.tscn` (Tasks 5, 8); race-finish → currency award consumes `RaceManager.race_finished` (Task 6); `SaveManager` persistence for money/license/championship (Tasks 1, 2, 3, 6). C4 scope fully delivered and the parallel `start_race`/`race_finished` plan is consumed without touching its signature.
**D6 → tasks:** no-test classes now covered — `DriftScorer` (Task 4), `Championship` (Task 3), `LicenseSystem` (Task 2); economy + integration (Tasks 1, 6).
**Placeholder scan:** no `TODO`/`FIXME`/`XXX`/`lorem`/`placeholder`/oversized-`TBD` text in this file; every interface lists the exact signature it must implement; every `mission` constant has a concrete value (prizes, event dicts, prices, bonuses). Nothing references a file or scene that does not exist in the plan's Files sections or in the current repo (all consumed autoloads/scripts verified by reading them in research).