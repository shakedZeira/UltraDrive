# Weather + Day/Night Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make weather and the day/night cycle real (inventory A7, C7, D9). `WeatherManager` (autoload/weather_manager.gd) already owns all state and exposes `set_weather()`, `set_time_of_day()`, `advance_time()`, `get_road_grip_factor()`, `get_computed_sun_position()` — but nothing calls the setters and no light consumes the sun position, so the world is permanently CLEAR/noon. This plan locks that API with tests (D9), adds a small autoload driver that advances time-of-day and rolls weather **only** while an open world is active, drives the existing `Sun` DirectionalLight3D in `scenes/world/open_world_root.tscn` from `get_computed_sun_position()`, and surfaces a minimal weather/grip readout in the HUD. Grip-factor consumption at `scripts/vehicle/vehicle_physics.gd:93` is untouched.

**Architecture:**
- `WeatherManager` (autoload, unchanged public API) stays the single source of truth for weather/time state, grip, and sun direction.
- New autoload `DayNightDriver` (`autoload/day_night_driver.gd`, registered in `project.godot` after `WeatherManager`) advances `WeatherManager.advance_time(delta * HOURS_PER_SECOND)` and rolls weather on an interval timer each `_process`. It is gated to run only when `GameState.current_mode == GameState.GameMode.FREE_ROAM` **and** an `open_world` group member exists — so in menus and under headless GDUnit it is a strict no-op and existing tests stay deterministic. Pure math lives in `_tick(delta)` / `_roll_weather()` / `_weighted_pick()` so tests drive it directly.
- New `scripts/world/sun_driver.gd` (extends `DirectionalLight3D`) attached to the existing `Sun` node in `open_world_root.tscn`: each frame rebuilds the light basis so local `-Z` points at `WeatherManager.get_computed_sun_position()`, dims `light_energy` by solar elevation, and drops shadows below the horizon. No sky/atmosphere/Environment edits.
- HUD: add `%WeatherLabel` to `scenes/ui/hud.tscn` and drive it from `scripts/race/race_ui.gd` via the `weather_changed`/`time_of_day_changed` signals (text like `Rain · 80% · 14:30` — grip percent makes A7's factor visible).
- D9 tests in `tests/suites/` (weather_manager, day_night_driver, sun_driver, hud_weather_label, day_night_world_and_sun).

**Tech Stack:** Godot 4.7.2 GDScript, GDUnit4

**Spec:** inventory A7, C7, D9 (see preamble)

---

## Global Constraints

- **Headless recipe (reuse verbatim, never skip):**
  1. Import probe (expect ZERO `SCRIPT ERROR` / `Parse Error` / `Failed to load`; benign `resources still in use at exit` and Terrain3D whitelist lines allowed):
     ```
     "D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import . 2>&1 | findstr /i "SCRIPT ERROR Parse Error Failed to load"
     ```
  2. GDUnit (MUST come after step 1; `--ignoreHeadlessMode` MUST come AFTER the tool-script path):
     ```
     "D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1
     ```
     then `findstr /c:"Overall Summary:" _gdunit.txt`. Baseline today: `69 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`. Grows to ~85/0/0/16 by the end (exact count may vary ±1; read the summary, don't re-derive it). Always add your own generous `timeout` on the bash tool (import probe of this project ≈ 600000 ms) — a script error during headless diag hangs Godot forever.
- **Git hygiene:** commit after every task; stage ONLY the intended files with explicit paths (e.g. `git add autoload/day_night_driver.gd tests/suites/test_day_night_driver.gd`). NEVER `git add -A` (project `.gitignore` ignores `*.uid`, but never risk staging engine noise). Never commit `.uid` files.
- **Do NOT touch:** `AGENTS.md`, `start_game.bat`, `play_game.bat`, `.godot/`, `scenes/main.tscn`'s light, `scenes/test/test_track.tscn` Sun, `scenes/track/mountain_pass.tscn` Sun, `scenes/ui/garage.tscn` Sun.
- **Do NOT change** `WeatherManager`'s existing public signatures, enum values, `ROAD_GRIP` mapping, or the `get_computed_sun_position()` math (D9 locks them). Do NOT edit `scripts/vehicle/vehicle_physics.gd:93` or any tire/grip math.
- **NO atmospheric overhaul:** no sky material changes, no fog/Environment changes, no rain particles, no audio, no settings persistence (time/weather are runtime-only, matching how `GameState.transmission_mode` already behaves).
- **GDUnit warnings-as-errors:** never use `:=` on a call whose return is `Variant` (e.g. `Dictionary.get`), and never type-infer `Variant`. Use explicit typed `var name: String = WeatherManager...` in those spots. Vector approx asserts need a SAME-TYPE approx arg (use scalar `.dot()` comparisons or scalar floats instead).
- **Tabs**: match each file's local indent convention (new suite files and new autoload/scripts use TABS — see `tests/suites/*.gd` and `scripts/world/world_driver.gd`; do not re-indent legacy files).
- Evolving an autoload means a project.godot change → the import probe in step 1 catches any parse breakage. Never edit `project.godot` autoload table outside Task 2.
- Test functions that need a scene ready split into `pre_check`/`check_part_a`/`check_part_b` if two frames are required; use `await runner.simulate_frames(n)`.

---

## Task 0 — Baseline sanity (no code)

- [ ] Run the import probe (Global Constraints step 1) → expect zero errors.
- [ ] Run GDUnit (step 2) → confirm `Overall Summary: 69 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`.
- [ ] Read the three anchor files once more in this exact state: `autoload/weather_manager.gd`, `scripts/vehicle/vehicle_physics.gd` lines 80–130, `scenes/world/open_world_root.tscn` (Sun node is `open_world_root.tscn:99`).
- No commit (no changes).

---

## Task 1 — D9: lock WeatherManager semantics (grip mapping, setter/emit behavior, sun math)

**Files:**
- NEW `tests/suites/test_weather_manager.gd` (only file changed)

**Interfaces:**
- Consumes: `WeatherManager.Weather` enum (`CLEAR, CLOUDY, RAIN, STORM, FOG, SNOW`); `WeatherManager.current_weather`; `WeatherManager.time_of_day`; `WeatherManager.ROAD_GRIP`; `get_road_grip_factor() -> float`; `set_weather(weather: Weather) -> void`; `get_time_of_day() -> float`; `set_time_of_day(hour: float) -> void`; `advance_time(delta_hours: float) -> void`; `get_computed_sun_position() -> Vector3`; signals `weather_changed(weather: Weather)` / `time_of_day_changed(hour: float)`.
- Produces: a regression net of 8 tests.

**Note on fail-first:** these tests lock PRE-EXISTING behavior, so they pass on first run — that is the intended definition of done for this task (the bug is that the behavior is dead code, not that it's wrong). Fail-first applies to Tasks 2–5 where new behavior is added.

- [ ] Write `tests/suites/test_weather_manager.gd` (tabs):
  ```gdscript
  # tests/suites/test_weather_manager.gd
  extends GdUnitTestSuite

  func _grip_for(w: WeatherManager.Weather) -> float:
      WeatherManager.set_weather(w)
      return WeatherManager.get_road_grip_factor()

  func test_default_state_is_clear_noon() -> void:
      assert_that(int(WeatherManager.current_weather)).is_equal(int(WeatherManager.Weather.CLEAR))
      assert_that(WeatherManager.get_time_of_day()).is_equal(12.0)

  func test_road_grip_matches_table() -> void:
      assert_that(_grip_for(WeatherManager.Weather.CLEAR)).is_equal_approx(1.0, 0.0001)
      assert_that(_grip_for(WeatherManager.Weather.CLOUDY)).is_equal_approx(0.98, 0.0001)
      assert_that(_grip_for(WeatherManager.Weather.RAIN)).is_equal_approx(0.8, 0.0001)
      assert_that(_grip_for(WeatherManager.Weather.STORM)).is_equal_approx(0.6, 0.0001)
      assert_that(_grip_for(WeatherManager.Weather.FOG)).is_equal_approx(0.95, 0.0001)
      assert_that(_grip_for(WeatherManager.Weather.SNOW)).is_equal_approx(0.45, 0.0001)

  func test_grip_unknown_weather_falls_back_to_one() -> void:
      WeatherManager.current_weather = 999
      assert_that(WeatherManager.get_road_grip_factor()).is_equal(1.0)
      WeatherManager.current_weather = WeatherManager.Weather.CLEAR

  func test_set_weather_emits_signal_only_on_change() -> void:
      WeatherManager.set_weather(WeatherManager.Weather.CLEAR)
      monitor_signals(WeatherManager)
      WeatherManager.set_weather(WeatherManager.Weather.RAIN)
      assert_signal_emitted(WeatherManager, "weather_changed")
      WeatherManager.set_weather(WeatherManager.Weather.RAIN)
      assert_signal_emitted_count(WeatherManager, "weather_changed", 1)

  func test_set_time_of_day_wraps_to_zero_to_24() -> void:
      WeatherManager.set_time_of_day(13.5)
      assert_that(WeatherManager.get_time_of_day()).is_equal(13.5)
      WeatherManager.set_time_of_day(25.0)
      assert_that(WeatherManager.get_time_of_day()).is_equal(1.0)
      WeatherManager.set_time_of_day(-1.0)
      assert_that(WeatherManager.get_time_of_day()).is_equal(23.0)
      WeatherManager.set_time_of_day(24.0)
      assert_that(WeatherManager.get_time_of_day()).is_equal(0.0)

  func test_set_time_of_day_emits_signal() -> void:
      monitor_signals(WeatherManager)
      WeatherManager.set_time_of_day(14.0)
      assert_signal_emitted(WeatherManager, "time_of_day_changed")

  func test_advance_time_wraps_and_emits() -> void:
      monitor_signals(WeatherManager)
      WeatherManager.set_time_of_day(23.5)
      WeatherManager.advance_time(1.0)
      assert_that(WeatherManager.get_time_of_day()).is_equal(0.5)
      assert_signal_emitted_count(WeatherManager, "time_of_day_changed", 2)

  func test_sun_position_rises_and_sets_across_day() -> void:
      WeatherManager.set_time_of_day(12.0)
      var noon: Vector3 = WeatherManager.get_computed_sun_position()
      assert_that(noon.y).is_greater(0.8)
      WeatherManager.set_time_of_day(0.0)
      var midnight: Vector3 = WeatherManager.get_computed_sun_position()
      assert_that(midnight.y).is_less(-0.8)
      WeatherManager.set_time_of_day(6.0)
      var dawn: Vector3 = WeatherManager.get_computed_sun_position()
      assert_that(dawn.x).is_greater(0.9)
      WeatherManager.set_time_of_day(18.0)
      var dusk: Vector3 = WeatherManager.get_computed_sun_position()
      assert_that(dusk.x).is_less(-0.9)
  ```
- [ ] Import probe → zero errors.
- [ ] GDUnit run → `Overall Summary: 77 test cases | 0 errors | 0 failures | ...` (8 new tests all PASS — expected, they lock existing behavior).
- [ ] Commit explicitly: `git add tests/suites/test_weather_manager.gd && git commit -m "test(D9): lock WeatherManager grip mapping, weather/time setters, sun position"`.

---

## Task 2 — D9 + C7: `DayNightDriver` autoload (advance clock + roll weather, gated to open world)

**Files:**
- NEW `autoload/day_night_driver.gd`
- NEW `tests/suites/test_day_night_driver.gd`
- MODIFIED `project.godot` (add ONE autoload line)
- MODIFIED `scenes/world/open_world_root.tscn` (add `groups=["open_world"]` to the root node — the driver's activity gate)

**Interfaces:**
- Consumes: `WeatherManager.advance_time(float)`, `WeatherManager.set_weather(Weather)`, `WeatherManager.current_weather`, `WeatherManager.Weather` enum; `GameState.current_mode`, `GameState.GameMode.FREE_ROAM`; the `open_world` group on the open world scene root.
- Produces (exact sigs):
  - `_process(delta: float) -> void` — calls `_tick(delta)` only when `_world_is_active()`.
  - `_world_is_active() -> bool` — `true` iff `GameState.current_mode == GameState.GameMode.FREE_ROAM` and `get_tree().get_first_node_in_group("open_world") != null`.
  - `_tick(delta: float) -> void` — `WeatherManager.advance_time(delta * HOURS_PER_SECOND)`; decrements `_weather_timer`; on expiry resets it to `_rng.randf_range(MIN_WEATHER_INTERVAL_SECONDS, MAX_WEATHER_INTERVAL_SECONDS)` and calls `_roll_weather()`.
  - `_roll_weather() -> void` — picks a weighted weather that differs from current (up to 8 attempts), applies via `set_weather`.
  - `_weighted_pick() -> WeatherManager.Weather` — cumulative `WEATHER_WEIGHTS` roll.
  - Consts: `DAY_LENGTH_SECONDS := 600.0`, `HOURS_PER_SECOND := 24.0 / DAY_LENGTH_SECONDS`, `MIN_WEATHER_INTERVAL_SECONDS := 30.0`, `MAX_WEATHER_INTERVAL_SECONDS := 60.0`, `WEATHER_WEIGHTS: Dictionary` (CLEAR .40 / CLOUDY .25 / RAIN .15 / STORM .10 / FOG .06 / SNOW .04).
  - Vars: `_weather_timer: float`, `_rng := RandomNumberGenerator.new()`.

- [ ] Write `tests/suites/test_day_night_driver.gd` first (references `DayNightDriver` which does not exist yet → suite fails to parse → this is the real failing test):
  ```gdscript
  # tests/suites/test_day_night_driver.gd
  extends GdUnitTestSuite

  const DRIVER_SCRIPT := "res://autoload/day_night_driver.gd"

  func _new_driver() -> Node:
      var d: Node = load(DRIVER_SCRIPT).new()
      add_child(d)
      return d

  func test_tick_advances_time_by_delta() -> void:
      WeatherManager.set_time_of_day(12.0)
      var d := _new_driver()
      d._tick(10.0)
      assert_that(WeatherManager.get_time_of_day()).is_equal_approx(12.4, 0.0001)

  func test_process_no_ops_when_not_in_open_world() -> void:
      GameState.current_mode = GameState.GameMode.MAIN_MENU
      WeatherManager.set_time_of_day(12.0)
      var d := _new_driver()
      d._process(10.0)
      assert_that(WeatherManager.get_time_of_day()).is_equal(12.0)
      assert_that(int(WeatherManager.current_weather)).is_equal(int(WeatherManager.Weather.CLEAR))
      GameState.current_mode = GameState.GameMode.FREE_ROAM

  func test_roll_weather_changes_current_weather() -> void:
      var d := _new_driver()
      d._rng.seed = 1234
      WeatherManager.set_weather(WeatherManager.Weather.CLEAR)
      var seen: Dictionary = {}
      for i in 200:
          d._roll_weather()
          seen[int(WeatherManager.current_weather)] = true
      assert_that(seen.size()).is_greater_equal(2)

  func test_weighted_pick_prefers_clear_over_storm() -> void:
      var d := _new_driver()
      d._rng.seed = 99
      var clears := 0
      var storms := 0
      for i in 1000:
          var w := d._weighted_pick()
          if int(w) == int(WeatherManager.Weather.CLEAR):
              clears += 1
          elif int(w) == int(WeatherManager.Weather.STORM):
              storms += 1
      assert_that(clears).is_greater(storms)
  ```
- [ ] Import probe → confirm the new suite fails to load (parse error referencing `DayNightDriver`) with ZERO other regressions. This is the recorded FAIL.
- [ ] Write `autoload/day_night_driver.gd` (tabs):
  ```gdscript
  # autoload/day_night_driver.gd
  extends Node

  ## Advances the WeatherManager day/night clock and rolls weather while an
  ## open world (open_world group member) is active in FREE_ROAM. All state
  ## lives in WeatherManager; this driver only nudges the clock and weather.

  const WORLD_GROUP := "open_world"
  const DAY_LENGTH_SECONDS := 600.0
  const HOURS_PER_SECOND := 24.0 / DAY_LENGTH_SECONDS
  const MIN_WEATHER_INTERVAL_SECONDS := 30.0
  const MAX_WEATHER_INTERVAL_SECONDS := 60.0

  const WEATHER_WEIGHTS: Dictionary = {
      WeatherManager.Weather.CLEAR: 0.40,
      WeatherManager.Weather.CLOUDY: 0.25,
      WeatherManager.Weather.RAIN: 0.15,
      WeatherManager.Weather.STORM: 0.10,
      WeatherManager.Weather.FOG: 0.06,
      WeatherManager.Weather.SNOW: 0.04,
  }

  var _weather_timer: float = MIN_WEATHER_INTERVAL_SECONDS
  var _rng := RandomNumberGenerator.new()

  func _ready() -> void:
      _rng.randomize()

  func _process(delta: float) -> void:
      if not _world_is_active():
          return
      _tick(delta)

  func _world_is_active() -> bool:
      if GameState.current_mode != GameState.GameMode.FREE_ROAM:
          return false
      return get_tree().get_first_node_in_group(WORLD_GROUP) != null

  func _tick(delta: float) -> void:
      WeatherManager.advance_time(delta * HOURS_PER_SECOND)
      _weather_timer -= delta
      if _weather_timer <= 0.0:
          _weather_timer = _rng.randf_range(MIN_WEATHER_INTERVAL_SECONDS, MAX_WEATHER_INTERVAL_SECONDS)
          _roll_weather()

  func _roll_weather() -> void:
      for attempt in 8:
          var pick := _weighted_pick()
          if pick != WeatherManager.current_weather:
              WeatherManager.set_weather(pick)
              return

  func _weighted_pick() -> WeatherManager.Weather:
      var roll := _rng.randf()
      var acc := 0.0
      for weather in WEATHER_WEIGHTS:
          acc += WEATHER_WEIGHTS[weather]
          if roll < acc:
              return weather as WeatherManager.Weather
      return WeatherManager.Weather.CLEAR
  ```
- [ ] Add the autoload line to `project.godot` immediately AFTER the `WeatherManager` line (index order expresses the dependency):
  ```
  DayNightDriver="*res://autoload/day_night_driver.gd"
  ```
- [ ] Add the gate group to `scenes/world/open_world_root.tscn` root node (line 60 becomes):
  ```
  [node name="OpenWorldRoot" type="Node3D" groups=["open_world"]]
  ```
- [ ] Import probe → zero errors.
- [ ] GDUnit run → all 4 new driver tests PASS (`~81 test cases | 0 errors | 0 failures`).
- [ ] Commit explicitly: `git add tests/suites/test_day_night_driver.gd autoload/day_night_driver.gd project.godot scenes/world/open_world_root.tscn && git commit -m "feat(A7,C7): DayNightDriver autoload advances WeatherManager clock + rolls weather only in open world"`.

---

## Task 3 — C7: drive the open-world Sun from `get_computed_sun_position()`

**Files:**
- NEW `scripts/world/sun_driver.gd`
- NEW `tests/suites/test_sun_driver.gd`
- MODIFIED `scenes/world/open_world_root.tscn` (attach script to the existing `Sun` node; do NOT touch its transform/light properties in tscn)

**Interfaces:**
- Consumes: `WeatherManager.get_computed_sun_position() -> Vector3` (direction origin→sun; at noon ≈ +Y).
- Produces (exact sigs on a `DirectionalLight3D`):
  - `_process(_delta: float) -> void` → calls `_refresh()`.
  - `_refresh() -> void` — sets `transform.basis = _basis_from_forward(dir)`; `light_energy = lerpf(NIGHT_ENERGY_FLOOR, BASE_ENERGY, clampf(dir.y / ELEVATION_BAND, 0.0, 1.0))`; `shadow_enabled = dir.y > -SHADOW_HORIZON`.
  - `_basis_from_forward(forward: Vector3) -> Basis` — builds an orthonormal right-handed basis whose local `-Z` column equals `forward` (robust near zenith: no `look_at` up-vector singularity).
  - Consts: `BASE_ENERGY := 1.2` (matches current scene value), `NIGHT_ENERGY_FLOOR := 0.12`, `ELEVATION_BAND := 0.5`, `SHADOW_HORIZON := 0.05`.

- [ ] Write `tests/suites/test_sun_driver.gd` first (loads a script that does not exist yet → suite errors → FAIL):
  ```gdscript
  # tests/suites/test_sun_driver.gd
  extends GdUnitTestSuite

  const SUN_SCRIPT := "res://scripts/world/sun_driver.gd"

  func _new_sun() -> DirectionalLight3D:
      var sun := DirectionalLight3D.new()
      sun.set_script(load(SUN_SCRIPT))
      add_child(sun)
      return sun

  func test_negative_z_tracks_sun_direction() -> void:
      var sun := _new_sun()
      WeatherManager.set_time_of_day(6.0)
      sun._refresh()
      var expected: Vector3 = WeatherManager.get_computed_sun_position()
      var forward := -sun.global_basis.z
      assert_that(forward.dot(expected)).is_greater(0.99)
      sun.free()

  func test_energy_dims_at_night_and_rises_at_noon() -> void:
      var sun := _new_sun()
      var noon_energy: float
      WeatherManager.set_time_of_day(12.0)
      sun._refresh()
      noon_energy = sun.light_energy
      WeatherManager.set_time_of_day(0.0)
      sun._refresh()
      assert_that(sun.light_energy).is_less(noon_energy)
      assert_that(sun.shadow_enabled).is_false()
      WeatherManager.set_time_of_day(12.0)
      sun._refresh()
      assert_that(sun.shadow_enabled).is_true()
      assert_that(sun.light_energy).is_equal_approx(noon_energy, 0.0001)
      sun.free()
  ```
- [ ] Import probe → confirm the new suite errors (missing `res://scripts/world/sun_driver.gd`) with ZERO other regressions. Recorded FAIL.
- [ ] Write `scripts/world/sun_driver.gd` (tabs):
  ```gdscript
  # scripts/world/sun_driver.gd
  extends DirectionalLight3D

  ## Points the open-world Sun at WeatherManager's computed sun position and
  ## scales light energy + shadows by solar elevation. No sky/atmosphere work.

  const BASE_ENERGY := 1.2
  const NIGHT_ENERGY_FLOOR := 0.12
  const ELEVATION_BAND := 0.5
  const SHADOW_HORIZON := 0.05

  func _process(_delta: float) -> void:
      _refresh()

  func _refresh() -> void:
      var dir: Vector3 = WeatherManager.get_computed_sun_position()
      transform.basis = _basis_from_forward(dir)
      var elevation: float = dir.y
      light_energy = lerpf(NIGHT_ENERGY_FLOOR, BASE_ENERGY, clampf(elevation / ELEVATION_BAND, 0.0, 1.0))
      shadow_enabled = elevation > -SHADOW_HORIZON

  func _basis_from_forward(forward: Vector3) -> Basis:
      var zcol := -forward.normalized()
      var x := Vector3.UP.cross(zcol)
      if x.length() < 0.001:
          x = Vector3.RIGHT
      x = x.normalized()
      var y := zcol.cross(x)
      return Basis(x, y, zcol)
  ```
  Basis math: light travels along local `-Z`. `col2 = -forward` ⇒ local `-Z = forward` = sun direction. `x = UP × zcol` normalized, `y = zcol × x` ⇒ `x×y = zcol` (right-handed, orthonormal). At noon `forward ≈ (0,1,0.3)` → `x ≈ (-0.287,0,0)`, no degenerate case.
- [ ] In `scenes/world/open_world_root.tscn`: add an ext_resource for the script and a `script = ExtResource("N_sun")` line on the `Sun` node (pick the next free id, e.g. `id="11_sun"`). Leave the Sun's transform/color/energy/shadow lines untouched (script overwrites them at runtime).
- [ ] Import probe → zero errors.
- [ ] GDUnit run → 2 new sun tests PASS (`~83 test cases | 0 errors | 0 failures`).
- [ ] Commit explicitly: `git add scripts/world/sun_driver.gd tests/suites/test_sun_driver.gd scenes/world/open_world_root.tscn && git commit -m "feat(C7): sun_driver points open-world Sun at WeatherManager sun position, dims energy + shadows at night"`.

---

## Task 4 — A7: HUD weather / road-grip readout

**Files:**
- MODIFIED `scenes/ui/hud.tscn` (add `%WeatherLabel` under `Root`)
- MODIFIED `scripts/race/race_ui.gd` (drive the label from WeatherManager signals)
- NEW `tests/suites/test_hud_weather_label.gd`

**Interfaces:**
- Consumes: `WeatherManager.weather_changed(weather: Weather)`, `WeatherManager.time_of_day_changed(hour: float)`, `WeatherManager.current_weather`, `WeatherManager.get_time_of_day() -> float`, `WeatherManager.get_road_grip_factor() -> float`, `WeatherManager.Weather` enum.
- Produces (in `race_ui.gd`):
  - `@onready var weather_label: Label = %WeatherLabel`
  - `_ready() -> void` — connects both signals, then calls `_on_weather_changed(WeatherManager.current_weather)`.
  - `_weather_text(hour: float) -> String` → `"Rain · 80% · 14:30"` (`name` from a `WEATHER_NAMES` const map, grip as percent, hour/minute from `hour`).
  - `_on_weather_changed(_weather: WeatherManager.Weather) -> void` and `_on_time_changed(hour: float) -> void` → set `weather_label.text = _weather_text(...)`.
- Const: `WEATHER_NAMES: Dictionary` mapping each enum value to `"Clear"/"Cloudy"/"Rain"/"Storm"/"Fog"/"Snow"`.

- [ ] Write `tests/suites/test_hud_weather_label.gd` first (fails: no `%WeatherLabel` yet):
  ```gdscript
  # tests/suites/test_hud_weather_label.gd
  extends GdUnitTestSuite

  const OPEN_WORLD_SCENE := "res://scenes/world/open_world_root.tscn"

  func test_hud_shows_current_weather_and_grip_percent() -> void:
      WeatherManager.set_weather(WeatherManager.Weather.RAIN)
      var runner := scene_runner(OPEN_WORLD_SCENE)
      await runner.simulate_frames(2)
      var hud := runner.scene().get_node_or_null("%WeatherLabel")
      assert_that(hud).is_not_null()
      if hud == null:
          return
      assert_that((hud as Label).text).contains("Rain")
      assert_that((hud as Label).text).contains("80%")
  ```
- [ ] Import probe → confirm suite FAILS (`%WeatherLabel` null) with zero other regressions. Recorded FAIL.
- [ ] In `scenes/ui/hud.tscn`, under `[node name="HUD" ...]` → `Root` add (top-center, clear of the existing `TimeLabel` at bottom-left of `Root`):
  ```
  [node name="WeatherLabel" type="Label" parent="Root"]
  unique_name_in_owner = true
  anchors_preset = 1
  anchor_left = 0.5
  anchor_top = 0.5
  anchor_right = 0.5
  anchor_bottom = 0.5
  offset_left = -140.0
  offset_top = -500.0
  offset_right = 140.0
  offset_bottom = -460.0
  horizontal_alignment = 1
  vertical_alignment = 1
  theme_override_colors/font_color = Color(0.96, 0.98, 1, 1)
  theme_override_colors/font_outline_color = Color(0.03, 0.05, 0.1, 1)
  theme_override_constants/outline_size = 3
  theme_override_font_sizes/font_size = 22
  ```
- [ ] In `scripts/race/race_ui.gd` (tabs, matching the file's existing style): add below the existing `@onready` lines —
  ```gdscript
  @onready var weather_label: Label = %WeatherLabel

  const WEATHER_NAMES: Dictionary = {
      WeatherManager.Weather.CLEAR: "Clear",
      WeatherManager.Weather.CLOUDY: "Cloudy",
      WeatherManager.Weather.RAIN: "Rain",
      WeatherManager.Weather.STORM: "Storm",
      WeatherManager.Weather.FOG: "Fog",
      WeatherManager.Weather.SNOW: "Snow",
  }

  func _ready() -> void:
      WeatherManager.weather_changed.connect(_on_weather_changed)
      WeatherManager.time_of_day_changed.connect(_on_time_changed)
      _on_weather_changed(WeatherManager.current_weather)

  func _weather_text(hour: float) -> String:
      var name: String = WEATHER_NAMES.get(WeatherManager.current_weather, "Clear")
      var grip: int = int(roundf(WeatherManager.get_road_grip_factor() * 100.0))
      var h: int = int(floorf(hour))
      var m: int = int(floorf((hour - float(h)) * 60.0))
      return "%s · %d%% · %02d:%02d" % [name, grip, h, m]

  func _on_weather_changed(_weather: WeatherManager.Weather) -> void:
      weather_label.text = _weather_text(WeatherManager.get_time_of_day())

  func _on_time_changed(hour: float) -> void:
      weather_label.text = _weather_text(hour)
  ```
  IMPORTANT: `WEATHER_NAMES.get(...)` returns `Variant` — use the explicit `var name: String =` form, never `:=` (GDUnit warnings-as-errors).
- [ ] Import probe → zero errors.
- [ ] GDUnit run → new HUD test PASSES and everything else stays green (`~84 test cases | 0 errors | 0 failures`).
- [ ] Commit explicitly: `git add scenes/ui/hud.tscn scripts/race/race_ui.gd tests/suites/test_hud_weather_label.gd && git commit -m "feat(A7): HUD shows current weather + road grip % from WeatherManager"`.

---

## Task 5 — Integration: driver advances the live open world and the Sun follows

**Files:**
- NEW `tests/suites/test_day_night_world_and_sun.gd`
- No production code changes expected; if the test exposes a wiring gap, fix the smallest thing (e.g. group membership in Task 2 or Sun script attachment in Task 3), never the WeatherManager API.

**Interfaces:**
- Consumes: `DayNightDriver` (autoload), `GameState.GameMode.FREE_ROAM`, `open_world` group, `WeatherManager.get_time_of_day()/get_computed_sun_position()`, `scene_runner("res://scenes/world/open_world_root.tscn")`, the `Sun` node.
- Produces: one end-to-end test proving time-of-day advances under the driver while the world is active and the in-scene Sun's local `-Z` tracks the computed sun direction.

- [ ] Write `tests/suites/test_day_night_world_and_sun.gd`:
  ```gdscript
  # tests/suites/test_day_night_world_and_sun.gd
  extends GdUnitTestSuite

  const OPEN_WORLD_SCENE := "res://scenes/world/open_world_root.tscn"

  func test_open_world_driver_advances_clock_and_drives_sun() -> void:
      GameState.current_mode = GameState.GameMode.FREE_ROAM
      WeatherManager.set_time_of_day(12.0)
      var runner := scene_runner(OPEN_WORLD_SCENE)
      await runner.simulate_frames(30)
      assert_that(WeatherManager.get_time_of_day()).is_greater(12.0)
      var the_sun := runner.scene().get_node_or_null("Sun") as DirectionalLight3D
      assert_that(the_sun).is_not_null()
      if the_sun == null:
          return
      var expected: Vector3 = WeatherManager.get_computed_sun_position()
      assert_that((-the_sun.global_basis.z).dot(expected)).is_greater(0.95)
      GameState.current_mode = GameState.GameMode.MAIN_MENU
  ```
  The clock advance comes from `DayNightDriver._process` (gate: FREE_ROAM + scene in `open_world` group). Sun assertion is the exact sun_driver contract — its local `-Z` equals the computed sun direction.
- [ ] Import probe → zero errors.
- [ ] GDUnit run → new integration test PASSES and the whole suite is green (`~85 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`). If a wiring gap fails here, fix it and re-run the full suite.
- [ ] Full final verification (Global Constraints steps 1 + 2) and read the printed `Overall Summary:` line.
- [ ] Commit explicitly: `git add tests/suites/test_day_night_world_and_sun.gd && git commit -m "test(C7): open-world DayNightDriver advances clock and sun tracks WeatherManager direction"`.

---

## Final / What NOT to do

- [ ] Nothing in this plan touches `vehicle_physics.gd` grip math, `WeatherManager` public API/`ROAD_GRIP`/sun math, sky/Environment/fog/atmosphere, audio, or save/settings files.
- [ ] No `git add -A` anywhere; no `.uid` files; `AGENTS.md` / `start_game.bat` / `play_game.bat` / `.godot/` untouched.
- [ ] Every headless invoke has your own timeout; every GDUnit run is preceded by the import probe; `--ignoreHeadlessMode` always after the tool-script path.

---

## Self-Review

Mapping (inventory → tasks):
- **A7** (setters unused, world permanently CLEAR/noon; grip factor exists but is constant): Task 1 locks the grip-factor mapping + setter semantics (D9); Task 2 makes weather change in-world so `get_road_grip_factor()` becomes meaningful; Task 4 surfaces it on the HUD. `vehicle_physics.gd:93` consumption is preserved unchanged.
- **C7** (day/night + weather never change, no driven sun light): Task 2 adds the time/weather driver (advance_time + weather roll); Task 3 + Task 5 wire and prove the existing `Sun` DirectionalLight3D is driven from `get_computed_sun_position()` with elevation-based energy + shadows.
- **D9** (no WeatherManager tests): Task 1 = 8 lock tests on grip/weather/time/sun; Task 2 = 4 driver tests; Task 3 = 2 sun tests; Task 4 = 1 HUD test; Task 5 = 1 integration test. Baseline 69 → ~85, all green headless, driver no-ops outside the open world so existing suites are unaffected.

Placeholder scan: no TODO/TBD/FIXME/`…` in any proposed file or step; every signature, constant, and path is taken verbatim from the current codebase (`weather_manager.gd:6-45`, `vehicle_physics.gd:91-128`, `open_world_root.tscn:99-104`, `race_ui.gd:7-28`, `project.godot:126-134`, `tests/suites/*.gd` conventions, `AGENTS.md` headless recipe). No commits that skip the stated verification commands.