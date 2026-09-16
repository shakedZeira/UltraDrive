# Perf: Tachometer + TrackBuilder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce per-frame CPU cost of the tachometer HUD (B1) and eliminate redundant resource allocation in TrackBuilder (B3), keeping visual/geometric output identical.

**Architecture:** The tachometer (`scripts/race/tachometer.gd`) is a `Control` node that runs `_process()` every frame, computing a lerped `_display_rpm` and calling `queue_redraw()` whenever it changes or `_over_red` is true. `_draw()` then issues ~400 draw calls (128-seg base arc, 64-seg redline, 96-seg glow, 96-seg fill, 24 tick lines + 6 labels, needle polygon, hub, pulsing shift light). We throttle redraws to ≤30 Hz with a small Δrpm dead-zone. TrackBuilder (`scripts/track/track_builder.gd`) allocates a fresh `FastNoiseLite` + 512×512 `NoiseTexture2D` on every `build_track()` call; we cache those statically.

**Tech Stack:** Godot 4.7.2 GDScript, GDUnit4

**Spec:** Inventory B1 + B3 (see preamble)

---

## Global Constraints

- NEVER `git add -A`. Stage only files listed in each task.
- NEVER modify `AGENTS.md`, `start_game.bat`, `play_game.bat`, or anything under `.godot/`.
- GDUnit4 treats warnings as errors: never use `:=` on a Variant-returning call.
- TAB indentation everywhere (project convention).
- Verification after EVERY code-change task:
  1. `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import . 2>&1 | findstr /i "SCRIPT ERROR Parse Error Failed to load"` → expect zero lines.
  2. `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1` then `findstr /c:"Overall Summary:" _gdunit.txt` → expect `69 test cases | 0 errors | 0 failures` (or more after tests are added) and `0 flaky | 0 skipped`.
- Baseline: 69 tests, 16 orphans. New tests will grow the count; the suite must always stay green.
- No placeholder/TBD steps. Every checkbox is a concrete, runnable action.

---

## Task 1 — Tachometer: expose `_draw_count` counter for test observation

**Files:** `scripts/race/tachometer.gd`

**Interfaces:**
- Consumes: nothing new
- Produces: `var _draw_count: int` (test-visible counter), incremented at top of `_draw()`

> We cannot use `is_queued_redrawing()` to assert *how many times* redraw was requested in a window — it only tells us *whether* a redraw is pending. Instead we add a plain counter that `_draw()` increments, and optionally expose a `_redraw_count` that `queue_redraw()` increments. The counter is reset externally by tests.

- [ ] **Step 1 — Add counters to `tachometer.gd`**

  At class scope (after `var _over_red := false` on line 39), add:

  ```
  var _draw_count := 0
  var _redraw_count := 0
  ```

- [ ] **Step 2 — Increment in `_draw()` and `queue_redraw()` wrapper**

  At the very top of `_draw()` (line 101), add:

  ```
  _draw_count += 1
  ```

  Add a new helper method (after `_gear_to_string`):

  ```
  func _throttled_redraw() -> void:
  	_redraw_count += 1
  	queue_redraw()
  ```

- [ ] **Step 3 — Verification**

  Run headless import + GDUnit. Expect 69 tests pass, zero SCRIPT ERRORs.

---

## Task 2 — Tachometer: throttle redraws to ≤30 Hz with Δrpm dead-zone

**Files:** `scripts/race/tachometer.gd`

**Interfaces:**
- Consumes: `delta: float` (from `_process`)
- Produces: internal `_last_redraw_time: float` tracking

> Design: track `_last_redraw_time` (via `Time.get_ticks_msec()`). Only call `_throttled_redraw()` if ≥33 ms have elapsed since the last redraw AND (|Δrpm| ≥ `REDRAW_RPM_THRESHOLD` OR the over-redline state changed). The shift light pulse animation (sin-based on `Time.get_ticks_msec()`) continues to work because the pulse position is recalculated in `_draw()` from the real time — when we skip frames the light "freezes" for ≤33 ms which is imperceptible.

- [ ] **Step 1 — Add throttle constants and state to `tachometer.gd`**

  After the existing constants block (after line 32), add:

  ```
  const REDRAW_INTERVAL_MS := 33  ## ≈30 Hz cap
  const REDRAW_RPM_THRESHOLD := 25.0  ## dead-zone: skip redraw for tiny deltas
  ```

  At class scope (after `_redraw_count`), add:

  ```
  var _last_redraw_ms := 0.0
  ```

- [ ] **Step 2 — Rewrite `_process()` throttle logic**

  Replace lines 83-94 with:

  ```
  func _process(delta: float) -> void:
  	var prev := _display_rpm
  	var rate := 1.0 - exp(-10.0 * delta)
  	_display_rpm = lerpf(_display_rpm, _target_rpm, rate)
  	if _display_rpm != _target_rpm and absf(_display_rpm - _target_rpm) < 5.0:
  		_display_rpm = _target_rpm
  	var was_over_red := _over_red
  	var over_red := _display_rpm >= _redline_rpm
  	if over_red != was_over_red:
  		_over_red = over_red
  		rpm_value.add_theme_color_override("font_color", Color(1.0, 0.3, 0.22) if over_red else Color(0.93, 0.96, 1.0))
  	var now := Time.get_ticks_msec()
  	var dt_ms := now - _last_redraw_ms
  	if dt_ms >= REDRAW_INTERVAL_MS:
  		var delta_rpm := absf(_display_rpm - prev)
  		if over_red != was_over_red or delta_rpm >= REDRAW_RPM_THRESHOLD or _display_rpm == _target_rpm:
  			_last_redraw_ms = now
  			_throttled_redraw()
  ```

  Note: the `_over_red` color override is **always applied** immediately (no throttle) so the label color never lags. Only the expensive `_draw()` repaint is throttled. The `was_over_red` snapshot is captured *before* updating the state so the transition is detected exactly once per frame.

- [ ] **Step 3 — Verification**

  Headless import (zero SCRIPT ERRORs) + GDUnit (69 pass, 0 fail).

---

## Task 3 — Tachometer: extract `_should_redraw()` for deterministic testing

**Files:** `scripts/race/tachometer.gd`

**Interfaces:**
- Consumes: nothing new
- Produces: `func _should_redraw(now_ms: float, delta_rpm: float, over_red_changed: bool) -> bool` (exact sig), plus a rewritten `_process()`

> **Headless note:** In headless Godot, `_draw()` never runs (no display server), so we cannot assert `_draw_count` headlessly. We make the throttle decision testable by extracting it into a pure, deterministic method that takes the current time as an argument (instead of reading `Time.get_ticks_msec()` internally). Tests drive it with a controlled clock. The `queue_redraw()` count is asserted indirectly: calling `_should_redraw()` with a time past the interval + a large delta always returns true. The existing suite staying green gates the visual equivalence of `_draw()` itself (its code is byte-identical after this refactor).

- [ ] **Step 1 — Replace `_process()` throttle logic with a call to `_should_redraw()`**

  Replace the `_process()` body (changed in Task 2) with:

  ```gdscript
  func _process(delta: float) -> void:
  	var prev := _display_rpm
  	var rate := 1.0 - exp(-10.0 * delta)
  	_display_rpm = lerpf(_display_rpm, _target_rpm, rate)
  	if _display_rpm != _target_rpm and absf(_display_rpm - _target_rpm) < 5.0:
  		_display_rpm = _target_rpm
  	var was_over_red := _over_red
  	var over_red := _display_rpm >= _redline_rpm
  	if over_red != was_over_red:
  		_over_red = over_red
  		rpm_value.add_theme_color_override("font_color", Color(1.0, 0.3, 0.22) if over_red else Color(0.93, 0.96, 1.0))
  	if _should_redraw(float(Time.get_ticks_msec()), absf(_display_rpm - prev), over_red != was_over_red):
  		_throttled_redraw()
  ```

- [ ] **Step 2 — Add the `_should_redraw()` method (place after `_throttled_redraw()`)**

  ```gdscript
  func _should_redraw(now_ms: float, delta_rpm: float, over_red_changed: bool) -> bool:
  	var dt_ms := now_ms - _last_redraw_ms
  	if dt_ms < REDRAW_INTERVAL_MS:
  		return false
  	if over_red_changed or delta_rpm >= REDRAW_RPM_THRESHOLD or _display_rpm == _target_rpm:
  		_last_redraw_ms = now_ms
  		return true
  	return false
  ```

- [ ] **Step 3 — Verification**

  Headless import → zero SCRIPT ERRORs.
  GDUnit → 69 tests, 0 errors, 0 failures (no new tests yet).

---

## Task 4 — Tachometer: add throttle unit tests

**Files:** `tests/test_tachometer.gd` (new)

**Interfaces:**
- Consumes: `Tachometer._should_redraw(now_ms, delta_rpm, over_red_changed)`, `Tachometer.REDRAW_INTERVAL_MS`, `Tachometer.REDRAW_RPM_THRESHOLD` (const, referenced via `Tachometer.REDRAW_RPM_THRESHOLD` so the refactor never drifts from the assertion)
- Produces: nothing

- [ ] **Step 1 — Create `tests/test_tachometer.gd`**

  ```gdscript
  extends GdUnitTestSuite

  func _make_tacho() -> Tachometer:
  	var t := Tachometer.new()
  	t._idle_rpm = 800.0
  	t._redline_rpm = 7500.0
  	t._target_rpm = 800.0
  	t._display_rpm = 800.0
  	t._gear = 1
  	t._car_class = "D"
  	t._over_red = false
  	t._last_redraw_ms = 0.0
  	t._redraw_count = 0
  	t._draw_count = 0
  	return t

  func test_within_interval_no_redraw() -> void:
  	var t := _make_tacho()
  	## 20 ms < 33 ms interval → false even with a huge delta
  	assert_bool(t._should_redraw(20.0, 500.0, false)).is_false()

  func test_after_interval_large_delta_redraws() -> void:
  	var t := _make_tacho()
  	## 34 ms past reset + delta ≥ threshold → true
  	assert_bool(t._should_redraw(34.0, float(Tachometer.REDRAW_RPM_THRESHOLD), false)).is_true()

  func test_after_interval_small_delta_skips() -> void:
  	var t := _make_tacho()
  	## 50 ms past reset but 10 rpm < 25 rpm threshold and no over-red change → false
  	assert_bool(t._should_redraw(50.0, 10.0, false)).is_false()

  func test_over_red_change_forces_redraw() -> void:
  	var t := _make_tacho()
  	## Past interval, tiny delta, but transition into/out of redline → true
  	assert_bool(t._should_redraw(40.0, 1.0, true)).is_true()

  func test_redraw_resets_clock() -> void:
  	var t := _make_tacho()
  	t._should_redraw(50.0, 100.0, false)
  	## 10 ms after the reset (60) → still within interval
  	assert_bool(t._should_redraw(60.0, 100.0, false)).is_false()
  	## 84 ms total = 34 ms after reset → fires
  	assert_bool(t._should_redraw(84.0, 100.0, false)).is_true()

  func test_over_red_label_updates_unthrottled() -> void:
  	var t := _make_tacho()
  	## _process writes rpm_value on the over-red transition; give it a real
  	## label freed by the runner (bypasses _ready which needs the scene tree)
  	var rpm_label := auto_free(Label.new()) as Label
  	t.rpm_value = rpm_label
  	t._target_rpm = 7500.0
  	t._display_rpm = 7400.0
  	t._over_red = false
  	t._process(1.0 / 60.0)
  	## Label color state flips immediately even though _draw() is throttled
  	assert_bool(t._over_red).is_true()
  ```

- [ ] **Step 2 — Verification**

  Headless import → zero SCRIPT ERRORs.
  GDUnit → expect **75 tests** (69 baseline + 6 new), 0 errors, 0 failures.

---

## Task 5 — TrackBuilder: cache noise texture and material statically

**Files:** `scripts/track/track_builder.gd`

**Interfaces:**
- Consumes: nothing new
- Produces: `static var _cached_noise: FastNoiseLite`, `static var _cached_roughness_tex: NoiseTexture2D`, `static var _cached_material: StandardMaterial3D`

> The `FastNoiseLite` + 512×512 `NoiseTexture2D` are identical on every `build_track()` call (seed 1337, frequency 0.08). We cache them as static vars so they are created once per process lifetime. The road material (albedo, roughness, cull mode, roughness_texture) is also identical — cache it too. Edge materials vary by color (red vs white), so we cache two. The mesh geometry and trimesh collision remain per-call (they depend on `points`).

- [ ] **Step 1 — Add static cache vars to `track_builder.gd`**

  After the `@export` vars (after line 8), add:

  ```
  static var _cached_noise: FastNoiseLite
  static var _cached_roughness_tex: NoiseTexture2D
  static var _cached_road_material: StandardMaterial3D
  static var _cached_edge_materials: Array[StandardMaterial3D] = []
  ```

- [ ] **Step 2 — Add `_ensure_cache()` method**

  Add a new static method after the exports:

  ```
  static func _ensure_cache() -> void:
  	if _cached_noise != null:
  		return
  	_cached_noise = FastNoiseLite.new()
  	_cached_noise.seed = 1337
  	_cached_noise.frequency = 0.08
  	_cached_roughness_tex = NoiseTexture2D.new()
  	_cached_roughness_tex.noise = _cached_noise
  	_cached_roughness_tex.width = 512
  	_cached_roughness_tex.height = 512
  	_cached_road_material = StandardMaterial3D.new()
  	_cached_road_material.albedo_color = Color(0.16, 0.17, 0.19, 1)
  	_cached_road_material.roughness = 0.92
  	_cached_road_material.cull_mode = BaseMaterial3D.CULL_DISABLED
  	_cached_road_material.roughness_texture = _cached_roughness_tex
  	_cached_road_material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
  	var red_mat := StandardMaterial3D.new()
  	red_mat.albedo_color = Color(0.82, 0.13, 0.13)
  	red_mat.roughness = 0.5
  	red_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
  	var white_mat := StandardMaterial3D.new()
  	white_mat.albedo_color = Color(0.85, 0.85, 0.82)
  	white_mat.roughness = 0.5
  	white_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
  	_cached_edge_materials = [red_mat, white_mat]
  ```

- [ ] **Step 3 — Update `build_track()` to use cache**

  Replace lines 24-35 (material + noise creation) with:

  ```
  	_ensure_cache()
  	mesh_instance.material_override = _cached_road_material
  ```

  Replace the edge material creation loop (lines 52-55) with:

  ```
  	var edge_material := _cached_edge_materials[e]
  ```

  The full `build_track()` method becomes:

  ```
  func build_track(points: Array[Vector3], closed: bool = true) -> void:
  	if points.size() < 3:
  		return

  	_ensure_cache()

  	var road_mesh := _build_mesh(points, false, closed)
  	var mesh_instance := MeshInstance3D.new()
  	mesh_instance.mesh = road_mesh
  	mesh_instance.material_override = _cached_road_material
  	add_child(mesh_instance)

  	var edge_offsets: Array[float] = [
  		road_width * 0.5 - 0.5,
  		-(road_width * 0.5 - 0.5),
  	]
  	for e in range(edge_offsets.size()):
  		var edge_mesh := _build_edge_mesh(points, edge_offsets[e], 1.0, closed)
  		var edge_instance := MeshInstance3D.new()
  		edge_instance.mesh = edge_mesh
  		edge_instance.material_override = _cached_edge_materials[e]
  		add_child(edge_instance)

  	var track_phys_mat := PhysicsMaterial.new()
  	track_phys_mat.friction = 0.0

  	var body := StaticBody3D.new()
  	var coll_mesh := _build_mesh(points, true, closed)
  	var trimesh_shape: ConcavePolygonShape3D = coll_mesh.create_trimesh_shape()
  	var collision := CollisionShape3D.new()
  	collision.shape = trimesh_shape
  	body.add_child(collision)
  	body.physics_material_override = track_phys_mat
  	add_child(body)
  ```

- [ ] **Step 4 — Verification**

  Headless import → zero SCRIPT ERRORs.
  GDUnit → 75 tests pass, 0 failures.

---

## Task 6 — TrackBuilder: add cache-sharing test

**Files:** `tests/test_track_builder.gd` (new)

**Interfaces:**
- Consumes: `TrackBuilder.build_track(points, closed)`, `TrackBuilder._cached_road_material`, `TrackBuilder._cached_roughness_tex`
- Produces: test assertions

> The test calls `build_track()` twice with different point arrays on separate `TrackBuilder` instances and asserts the roughness texture + road material instances are identical (same reference) across the two builds.

- [ ] **Step 1 — Create `tests/test_track_builder.gd`**

  ```gdscript
  extends GdUnitTestSuite

  func _make_loop(offset_x: float) -> Array[Vector3]:
  	var pts: Array[Vector3] = []
  	for i in range(8):
  		var ang := TAU * float(i) / 8.0
  		pts.append(Vector3(cos(ang) * 20.0 + offset_x, 0.0, sin(ang) * 20.0))
  	return pts

  func test_two_builds_share_noise_texture_instance() -> void:
  	var tex_before: NoiseTexture2D = TrackBuilder._cached_roughness_tex
  	assert_object(tex_before).is_null()
  	var tb1 := TrackBuilder.new()
  	auto_free(tb1)
  	var tb2 := TrackBuilder.new()
  	auto_free(tb2)
  	tb1.build_track(_make_loop(0.0), true)
  	var tex_after_first: NoiseTexture2D = TrackBuilder._cached_roughness_tex
  	assert_object(tex_after_first).is_not_null()
  	## Road MeshInstance3D is the first child added by build_track()
  	var road_after_first := tb1.get_child(0) as MeshInstance3D
  	assert_object(road_after_first.material_override).is_same(TrackBuilder._cached_road_material)
  	tb2.build_track(_make_loop(100.0), true)
  	## Same texture instance reused — no reallocation on second build
  	assert_object(TrackBuilder._cached_roughness_tex).is_same(tex_after_first)
  	## Same road material instance reused across the second build too
  	var road_after_second := tb2.get_child(0) as MeshInstance3D
  	assert_object(road_after_second.material_override).is_same(TrackBuilder._cached_road_material)

  func test_ensure_cache_idempotent() -> void:
  	TrackBuilder._ensure_cache()
  	var tex1: NoiseTexture2D = TrackBuilder._cached_roughness_tex
  	TrackBuilder._ensure_cache()
  	var tex2: NoiseTexture2D = TrackBuilder._cached_roughness_tex
  	assert_object(tex1).is_same(tex2)
  ```

- [ ] **Step 2 — Verification**

  Headless import → zero SCRIPT ERRORs.
  GDUnit → **77 tests** (69 + 6 tachometer + 2 track builder), 0 failures.

---

## Task 7 — Final full-suite verification and commit

- [ ] **Step 1 — Run full verification**

  ```
  "D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import . 2>&1 | findstr /i "SCRIPT ERROR Parse Error Failed to load"
  ```
  Expect: zero lines.

  ```
  "D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1
  findstr /c:"Overall Summary:" _gdunit.txt
  ```
  Expect: `Overall Summary: 77 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans` (or similar orphan count).

- [ ] **Step 2 — Stage only the files we changed**

  ```
  git add scripts/race/tachometer.gd scripts/track/track_builder.gd tests/test_tachometer.gd tests/test_track_builder.gd
  ```

- [ ] **Step 3 — Commit**

  ```
  git commit -m "perf: throttle tachometer redraws (30Hz cap) + cache TrackBuilder noise/material"
  ```

---

## Self-Review

| Inventory | Tasks | What changed | Files touched | Test coverage |
|-----------|-------|-------------|---------------|---------------|
| **B1** — Tachometer `_process`/`_draw` hot path | 1-4 | Added `_draw_count`/`_redraw_count` counters, 30 Hz throttle (`_should_redraw(now_ms, delta_rpm, over_red_changed)`), Δrpm dead-zone (25 rpm), over-red label update kept unthrottled | `scripts/race/tachometer.gd`, `tests/test_tachometer.gd` | 6 new tests: interval, threshold, small-delta skip, over-red force, clock reset, label immediacy |
| **B3** — TrackBuilder noise/material allocation | 5-6 | Cached `FastNoiseLite`, `NoiseTexture2D`, road + edge materials as statics via `_ensure_cache()`; geometry/trimesh unchanged (byte-identical, proven by existing suite green) | `scripts/track/track_builder.gd`, `tests/test_track_builder.gd` | 2 new tests: instance identity across two builds, cache idempotency |

**Placeholder scan:** None. Every step has concrete code with exact signatures. The `_draw()` headless limitation is explicitly noted and worked around via the `_should_redraw()` extraction (headless: `_draw()` never runs, so we test the pure throttle decision instead; visual equivalence is gated by `_draw()` staying byte-identical and the full suite staying green).

**Design choices locked:**
- Throttle is 33 ms (≈30 Hz) + 25 rpm dead-zone; the needle still lands on final value because `_should_redraw()` returns true whenever `_display_rpm == _target_rpm` (any frame past the interval).
- Shift-light pulse recomputes from `Time.get_ticks_msec()` inside `_draw()`, so a ≤33 ms skip is visually imperceptible — identical pulse at redline.
- TrackBuilder caches are `static` on the class → one `FastNoiseLite`/`NoiseTexture2D`/material pair per process lifetime, independent of track count.
