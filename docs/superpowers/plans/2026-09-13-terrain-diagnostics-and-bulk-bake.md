# Terrain Diagnostics + Bulk-Bake Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the broken `freeze_diag.gd` (A6) so it measures real terrain-streaming latency inside Terrain3D's valid region grid, and add a worker-only FastNoiseLite `get_image` 8-bit bulk-noise bake path (B6) that accelerates corridor/prefetch bakes ~4× while keeping the player's own region byte-identical-float and every existing streaming suite assertion green.

**Architecture:** A6 — replace the straight 30,848 m +X drive ("Location (29,0) out of bounds" + `2147483647` sentinel spam, invalid numbers) with a closed 8×8-region square loop driven by a new pure `FreezeRoute` helper (region coords 0..8, hard ±`REGION_LIMIT` guard, self-terminating caps + `DIAG_WALL` bail). B6 — a new `TerrainBaker.bake_region_8bit()` runs the *identical* float pipeline (biome blend, alpine dome, roads, 3×3 blur, spawn guard, clamp, `FORMAT_RF` output) but sources the per-texel fBm detail from one FastNoiseLite `get_image()` L8 map (offset = region origin, `normalize=false`, deterministic) instead of ~1M GDScript virtual `get_noise_2d()` calls. The seeder threads a `"bulk8"` flag through `_make_job → _worker_bake → finished record → _baked` cache; only `PRIORITY_CORRIDOR` and `PRIORITY_PREFETCH` jobs set it, `PRIORITY_LIVE`/player sync stays float. `bake_region()` resets `_noise.offset = Vector3.ZERO` so a shared worker baker mixing 8-bit and float jobs never corrupts the float path (guarantees the existing byte-identical test still passes).

**Tech Stack:** Godot 4.7.2 GDScript, GDUnit4

**Spec:** inventory A6 + B6 (see preamble)

## Global Constraints

- **TAB indentation everywhere** (never spaces) — this project is 100% tabs; a mixed file trips the GDUnit load warnings.
- **Never `git add -A`.** Stage only the specific files a task touched (tech-debt convention: `*.uid` are gitignored and must stay out of `git status` noise; `_gdunit.txt` is a scratch log, never committed).
- **Do NOT touch:** `AGENTS.md`, `start_game.bat`, `play_game.bat`, `.godot/`, root `.gitignore`, `project.godot`. These are off-limits; changing them is a diff-flag.
- **GDUnit4 treats GDScript warnings as errors.** Never use `:=` on a Variant-returning call (e.g. `var x := node.get(...)`); use an explicit type annotation or `: Variant`. Vector `is_equal_approx` needs a SAME-TYPE approx arg (never a bare float), and no warning-triggering shadowing/unused vars.
- **Verification** (run at every task boundary, exact commands):
  1. Import probe (expect ZERO `SCRIPT ERROR` / `Parse Error` / `Failed to load`; benign "resources still in use" + Terrain3D whitelist lines allowed):
     `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import . 2>&1 | findstr /i "SCRIPT ERROR Parse Error Failed to load"`
  2. Full GDUnit suite (MUST come AFTER the probe — first-run `--headless` bails exit 103):
     `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1`
     then `findstr /c:"Overall Summary:" _gdunit.txt`.
     Baseline: `69 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans` — **grows** to ~76 as this plan's suites land; 16 orphans stay benign.
  3. Targeted suite loops (FAIL→PASS) run the ONE suite file, e.g. `... -a res://tests/suites/test_freeze_route.gd`.
- **Watchdog:** any script error during a headless run leaves Godot hanging forever. The diag (`-s res://diag/freeze_diag.gd`) is a MANUAL run (never inside the GDUnit suite) and MUST be executed inside the bash tool with an explicit large timeout (≥ 600000 ms) — the plan's own iteration caps + `quit()` are the in-script fail-safe, the tool timeout is the out-of-script watchdog.
- **Diag contract:** produce `DIAG_RUN <n> RESULT max_sync_us=… sync_hits=… max_idle_us=… idle_hits=… sync_bake=… async_apply=…` (A6 keeps these field names; B6 appends `async_bulk=`), plus `SYNC_*us` / `IDLE_*us` / `DIAG_WALL` lines. Zero `out of bounds` / `2147483647` lines is a pass condition.
- **Commit discipline:** one commit per completed task, message style matches repo (`D6: …`-style short subject). Only after that task's suite is green.

---

## Task 1 — `FreezeRoute`: pure looped diag route + GDUnit suite (A6)

**Files:** new `diag/freeze_route.gd`; new `tests/suites/test_freeze_route.gd`

**Interfaces:**
- Consumes: nothing (pure RefCounted, zero scene access — headless/pure-testable).
- Produces (`class_name FreezeRoute extends RefCounted`):
  - `const STEP := 1024.0`, `const Y := 2.2`, `const SIDE_STEPS := 8`, `const CROSSINGS := 32`, `const REGION_LIMIT := 12`
  - `static func route_path(start: Vector3) -> Array[Vector3]` — 33 points, one 1024 m crossing per step, region coords bounded to 0..8 on both axes, closed (last == start).
  - `static func region_of(world_pos: Vector3) -> Vector2i`
  - `static func inside_valid_grid(world_pos: Vector3, limit: int = REGION_LIMIT) -> bool`

- [ ] Write `tests/suites/test_freeze_route.gd` with the six assertions below (route size 33; consecutive steps = 1024 m; every region coord inside ±`REGION_LIMIT`; closed loop; loop revisits both axes so regions leave & re-enter the ring; deterministic on repeat).
- [ ] Run the targeted suite → expect FAIL (class `FreezeRoute` unresolved / missing script). This is the required failing test.
- [ ] Write `diag/freeze_route.gd` per the full implementation below.
- [ ] Run the targeted suite → PASS (all six).
- [ ] Run the import probe (zero `SCRIPT ERROR`/`Parse Error`) + full GDUnit suite.
- [ ] Commit (`git add diag/freeze_route.gd tests/suites/test_freeze_route.gd`).

Intended `freeze_route.gd` (fully concrete — adapt only for lint/warning issues):

```gdscript
# diag/freeze_route.gd
class_name FreezeRoute
extends RefCounted

## Pure, deterministic drivable route for the freeze diag: a closed 8x8-region
## square loop (world span 128..8320 m on each axis, region coords 0..8) that
## stays well inside Terrain3D's valid grid (~+-16 regions at region_size
## 1024). Every step crosses exactly one region boundary, both axes are used so
## regions leave and re-enter the live ring (exercising removal + re-add), and
## the last point returns to the spawn. The old A6 diag drove a 30,848 m
## straight that left the grid and logged "Location (29,0) out of bounds" plus
## 2147483647 sentinel adds, invalidating its max_sync/max_idle numbers.

const STEP := 1024.0
const Y := 2.2
const SIDE_STEPS := 8
const CROSSINGS := SIDE_STEPS * 4
const REGION_LIMIT := 12

## 33 world positions (start + 32 crossings). Side length = SIDE_STEPS * STEP;
## corners are built from `start` so the loop is anchored exactly on the spawn
## region and the path re-enters regions that fell out of the live ring.
static func route_path(start: Vector3) -> Array[Vector3]:
	var side := float(SIDE_STEPS) * STEP
	var corners := [
		start,
		Vector3(start.x + side, Y, start.z),
		Vector3(start.x + side, Y, start.z + side),
		Vector3(start.x, Y, start.z + side),
	]
	var positions: Array[Vector3] = []
	positions.append(start)
	for c in 4:
		var a: Vector3 = corners[c]
		var b: Vector3 = corners[(c + 1) % 4]
		var dir := (b - a).normalized()
		for k in range(1, SIDE_STEPS + 1):
			positions.append(a + dir * (float(k) * STEP))
	return positions

static func region_of(world_pos: Vector3) -> Vector2i:
	return Vector2i(floori(world_pos.x / STEP), floori(world_pos.z / STEP))

static func inside_valid_grid(world_pos: Vector3, limit: int = REGION_LIMIT) -> bool:
	var r := region_of(world_pos)
	return absi(r.x) <= limit and absi(r.y) <= limit
```

Intended `test_freeze_route.gd`:

```gdscript
# tests/suites/test_freeze_route.gd
extends GdUnitTestSuite

## A6: the old diag route drove 30,848 m along +X (region 30, past Terrain3D's
## ~+-16-region validity), logging out-of-bounds spam and a 2147483647 sentinel.
## FreezeRoute drives a closed 8x8-region square that never leaves region coords
## 0..8 and always stays inside +-REGION_LIMIT.

const SPAWN := Vector3(128.0, 2.2, 128.0)
const STEP := 1024.0
const SIDE_STEPS := 8

func test_route_returns_crossings_plus_origin() -> void:
	var route := FreezeRoute.route_path(SPAWN)
	assert_that(route.size()).is_equal(FreezeRoute.CROSSINGS + 1)
	assert_that(FreezeRoute.CROSSINGS).is_equal(SIDE_STEPS * 4)

func test_route_steps_are_one_region() -> void:
	var route := FreezeRoute.route_path(SPAWN)
	for i in route.size() - 1:
		assert_that(route[i].distance_to(route[i + 1])).is_equal_approx(STEP)

func test_route_never_leaves_valid_grid() -> void:
	var route := FreezeRoute.route_path(SPAWN)
	for p in route:
		var r := FreezeRoute.region_of(p)
		assert_that(r.x).is_between(-FreezeRoute.REGION_LIMIT, FreezeRoute.REGION_LIMIT)
		assert_that(r.y).is_between(-FreezeRoute.REGION_LIMIT, FreezeRoute.REGION_LIMIT)
		assert_that(FreezeRoute.inside_valid_grid(p)).is_true()

func test_route_is_closed_and_revisits_regions() -> void:
	var route := FreezeRoute.route_path(SPAWN)
	assert_that(route[route.size() - 1]).is_equal(route[0])
	var locs := {}
	for p in route:
		locs[FreezeRoute.region_of(p)] = true
	assert_that(locs.has(Vector2i(0, 0))).is_true()
	assert_that(locs.has(Vector2i(8, 0))).is_true()
	assert_that(locs.has(Vector2i(8, 8))).is_true()
	assert_that(locs.has(Vector2i(0, 8))).is_true()
	assert_that(locs.size()).is_greater_equal(32)

func test_route_uses_both_axes_so_regions_relinquish() -> void:
	var route := FreezeRoute.route_path(SPAWN)
	var z_changed := false
	for p in route:
		if absf(p.z - SPAWN.z) > STEP:
			z_changed = true
			break
	assert_that(z_changed).is_true()

func test_route_is_deterministic() -> void:
	var a := FreezeRoute.route_path(SPAWN)
	var b := FreezeRoute.route_path(SPAWN)
	assert_that(PackedVector3Array(a)).is_equal(PackedVector3Array(b))
```

---

## Task 2 — Rewrite `freeze_diag.gd` to drive the looped route (A6)

**Files:** `diag/freeze_diag.gd`

**Interfaces:**
- Consumes: `FreezeRoute` (class_name), the existing `TerrainSeeder` API + its test-visible counters (`_queued_count`, `_pending_count`, `sync_bake_count`, `async_apply_count`). Keeps the exact `SeederTimed` `_process` timing harness.
- Produces: `DIAG_RUN 1/2 RESULT …` lines with the A6-invariant field order `max_sync_us, sync_hits, max_idle_us, idle_hits, sync_bake, async_apply` (B6 appends `async_bulk=` in Task 5), plus `SYNC_*us` / `IDLE_*us` / `DIAG_WALL` lines; self-terminating via `quit()` after hard iteration caps.

- [ ] Rewrite `freeze_diag.gd` per the full implementation below (drop `CROSSINGS=30`/`STEP`/straight-road drive; route = `FreezeRoute.route_path(SPAWN)`; the roads run hands `seeder.set_roads([route])` so the corridor pre-bake covers the loop box; add the `DIAG_WALL` never-drive-out guard inside the crossing loop; keep 2 runs + `quit()`).
- [ ] Run the diag MANUALLY with a watchdog timeout (≥ 600000 ms):
     `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://diag/freeze_diag.gd`
- [ ] Verify: exactly 2 `DIAG_RUN … RESULT` lines with finite `max_sync_us`/`max_idle_us`; **zero** `out of bounds` and **zero** `2147483647` lines; no `DIAG_WALL` fired; process exits on its own (`quit()`).
- [ ] Run the import probe + full GDUnit suite.
- [ ] Commit (`git add diag/freeze_diag.gd`).

Intended `freeze_diag.gd` (structure identical to today, route swapped, guard added):

```gdscript
# res://diag/freeze_diag.gd
extends SceneTree

## Measures terrain streaming frame-cost as the player drives a closed 8x8-region
## square loop (FreezeRoute) that never leaves Terrain3D's valid grid: times
## sync_player_pos() physics-tick cost and the seeder _process idle work (ring
## pass + drain), logging every delta above 10 ms. Runs the same crossing
## sequence with and without set_roads() so the corridor pre-bake effect is
## measurable. Self-terminating: hard iteration caps, a DIAG_WALL guard that
## never drives outside +-REGION_LIMIT, and quit(). Run under a watchdog
## timeout (headless hangs forever on a script error):
## godot --headless -s res://diag/freeze_diag.gd

const FRAMES_PER_STEP := 60
const SLOW_US := 10000
const SPAWN := Vector3(128.0, 2.2, 128.0)
const REGION_LIMIT := FreezeRoute.REGION_LIMIT

var _run := 0

class SeederTimed extends TerrainSeeder:
	const SLOW_US := 10000
	var max_idle_us := 0
	var idle_hits := 0

	func _process(delta: float) -> void:
		var t0 := Time.get_ticks_usec()
		super(delta)
		var dt := Time.get_ticks_usec() - t0
		if dt > SLOW_US:
			idle_hits += 1
			print("IDLE_%dus" % dt)
		max_idle_us = maxi(max_idle_us, dt)

func _initialize() -> void:
	await _measure(true)
	await _measure(false)
	quit()

func _measure(use_roads: bool) -> void:
	_run += 1
	print("=== DIAG RUN %d (roads=%s) ===" % [_run, use_roads])
	var route := FreezeRoute.route_path(SPAWN)
	var terrain := Terrain3D.new()
	root.add_child(terrain)
	await process_frame
	var seeder := SeederTimed.new()
	seeder.terrain = terrain
	root.add_child(seeder)
	var frames := 0
	while terrain.data == null and frames < 240:
		await process_frame
		frames += 1
	if terrain.data == null:
		print("DIAG_RUN %d ABORT terrain.data uninitialized" % _run)
		seeder._stop_worker()
		seeder.queue_free()
		terrain.queue_free()
		for _i in 3:
			await process_frame
		return
	if use_roads:
		seeder.set_roads([route])
	var max_sync_us := 0
	var sync_hits := 0
	for step in range(FreezeRoute.CROSSINGS):
		var pos := route[step + 1]
		if not FreezeRoute.inside_valid_grid(pos, REGION_LIMIT):
			print("DIAG_WALL run=%d crossing=%d pos=%s" % [_run, step, pos])
			break
		var t0 := Time.get_ticks_usec()
		seeder.sync_player_pos(pos)
		var dt := Time.get_ticks_usec() - t0
		if dt > SLOW_US:
			sync_hits += 1
			print("SYNC_%dus" % dt)
		if dt > max_sync_us:
			max_sync_us = dt
		for _i in FRAMES_PER_STEP:
			await process_frame
	var queued := seeder._queued_count()
	var pending := seeder._pending_count()
	seeder._stop_worker()
	print("DIAG_RUN %d RESULT max_sync_us=%d sync_hits=%d max_idle_us=%d idle_hits=%d sync_bake=%d async_apply=%d queued=%d pending=%d" % [
		_run, max_sync_us, sync_hits, seeder.max_idle_us, seeder.idle_hits,
		seeder.sync_bake_count, seeder.async_apply_count, queued, pending])
	seeder.queue_free()
	terrain.queue_free()
	for _i in 3:
		await process_frame
```

---

## Task 3 — `bake_region_8bit` in `TerrainBaker` + offset reset (B6)

**Files:** `scripts/world/terrain_baker.gd`; tests added to existing `tests/test_terrain_baker.gd`

**Interfaces:**
- Consumes: existing `FastNoiseLite` member `_noise` (already seed/freq/fractal configured), `get_image(w, h, invert, in_3d_space, normalize)`.
  Godot source fact (verified): `get_noise_2d(x, y)` adds `_noise.offset` BEFORE the internal `frequency` multiply, and the base `Noise::_get_image` (FastNoiseLite does not override it) samples pixel `(px, pz)` at `get_noise_2d(px, pz)` and, with `normalize=false`, stores byte `b = clampf(value * 127.5 + 127.5, 0, 255)` in a `FORMAT_L8` image. So `offset = region origin` maps pixel `(px, pz)` to world `(origin.x + px, origin.y + pz)`, and the noise base is recovered as `n = b / 127.5 - 1.0`.
- Produces (`scripts/world/terrain_baker.gd`):
  - New: `func bake_region_8bit(region: Vector2i, bake_scale: float = 1.0, image_width: int = 1024, roads: Array = []) -> Image` — same pass order + `FORMAT_RF` output as `bake_region`, deterministic.
  - New private: `func _bake_natural8(buf: PackedFloat32Array, raw_bytes: PackedByteArray, origin: Vector2, step: float, stride: int, image_width: int) -> void`.
  - Modified: `bake_region()` gains `_noise.offset = Vector3.ZERO` right after its fractal setup (currently it never touches offset). REQUIRED: a worker baker alternates 8-bit and float jobs on one instance; a stale offset would corrupt the float path and break the existing byte-identical streaming test.

- [ ] Extend `tests/test_terrain_baker.gd` with the three assertions below (8-bit deterministic + byte-differs from float reference + max-texel |delta| < 0.5 m on spawn, far, and road-carved regions). The tolerance test doubles as the §offset calibration check.
- [ ] Run the targeted suite (`-a res://tests/test_terrain_baker.gd`) → FAIL (method `bake_region_8bit` doesn't exist).
- [ ] Implement `bake_region_8bit`, `_bake_natural8`, and the offset reset in `bake_region()` per the full implementation below.
- [ ] Run the targeted suite → PASS. No `:` assignment on Variant-returning calls anywhere.
- [ ] Run the import probe + full GDUnit suite (this ALWAYS includes the byte-identical streaming test — it must still pass, because live-queued jobs still call `bake_region` with a zeroed offset).
- [ ] Commit (`git add scripts/world/terrain_baker.gd tests/test_terrain_baker.gd`).

Intended additions to `terrain_baker.gd`:

```gdscript
## Bulk-noise bake: identical passes to bake_region() (biome blend, alpine
## dome, optional road conforming, 3x3 blur, spawn guard, height clamp) but the
## per-texel fBm detail is read from a FastNoiseLite.get_image() L8 map instead
## of a per-pixel get_noise_2d() GDScript virtual call. One C++ bulk fill
## replaces ~1M virtual noise calls (~4x faster). The DETAIL term is quantized
## to 8 bits (~0.008 noise units, ~0.03 m of height after the detail gain) --
## invisible in practice but never used for the player's own region: callers
## restrict this path to corridor/prefetch jobs. byte-identical to nothing,
## but deterministic for a fixed (region, scale, width, roads).
func bake_region_8bit(region: Vector2i, bake_scale: float = 1.0, image_width: int = 1024, roads: Array = []) -> Image:
	_bake_scale = bake_scale
	_bake_region = region
	_noise.seed = NOISE_SEED + _bake_region.x * 131 + _bake_region.y * 977
	_noise.frequency = NOISE_FREQUENCY
	_noise.fractal_octaves = NOISE_OCTAVES
	_noise.fractal_lacunarity = NOISE_LACUNARITY
	_noise.fractal_gain = NOISE_GAIN
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	var origin := Vector2(region.x * REGION_SIZE, region.y * REGION_SIZE)
	# get_noise_2d(px, pz) = noise at world (origin.x + px, origin.y + pz):
	# offset is added BEFORE the internal frequency multiply (see godot
	# modules/noise fastnoise_lite.cpp get_noise_2d), then Noel::_get_image
	# stores `byte = value * 127.5 + 127.5` per pixel at normalize=false.
	_noise.offset = Vector3(origin.x, origin.y, 0.0)
	var raw := _noise.get_image(image_width, image_width, false, false, false)
	var raw_bytes := raw.get_data()
	var step := REGION_SIZE / float(image_width)
	var stride := image_width
	var buf := PackedFloat32Array()
	buf.resize(stride * stride)
	_bake_natural8(buf, raw_bytes, origin, step, stride, image_width)
	if not roads.is_empty():
		var chains := _upsample_roads(roads)
		if not chains.is_empty():
			_conform_roads(buf, chains, origin, step)
	_blur3x3(buf, stride)
	_apply_spawn_guard(buf, stride, origin, step)
	for iz in stride:
		for ix in stride:
			buf[iz * stride + ix] = clampf(buf[iz * stride + ix], HEIGHT_MIN, HEIGHT_MAX)
	return Image.create_from_data(image_width, image_width, false, Image.FORMAT_RF, buf.to_byte_array())

## Mirror of _bake_natural() with one substitution: the fBm detail value is
## read from the bulk L8 map instead of _noise.get_noise_2d(). All biome/dome
## arithmetic stays EXACTLY the inline float form so blur/roads/guard behave
## identically; only the noise detail source differs (8-bit + ~half-texel
## sampling shift, bounded and covered by the <0.5 m tolerance test).
func _bake_natural8(buf: PackedFloat32Array, raw_bytes: PackedByteArray, origin: Vector2, step: float, stride: int, image_width: int) -> void:
	var dome_edge := DOME_RADIUS * DOME_EDGE
	for iz in stride:
		var wz := origin.y + (float(iz) + 0.5) * step
		var row := iz * stride
		for ix in stride:
			var wx := origin.x + (float(ix) + 0.5) * step
			var n := float(raw_bytes[iz * image_width + ix]) / 127.5 - 1.0
			var total := 0.0
			var acc := 0.0
			var dx := wx - BIOME_SPAWN_CENTER.x
			var dz := wz - BIOME_SPAWN_CENTER.y
			var dist := sqrt(dx * dx + dz * dz)
			var weight := 0.0
			if dist < BIOME_SPAWN_RADIUS:
				var t := 1.0 - dist / BIOME_SPAWN_RADIUS
				weight = t * t
			total += weight
			acc += weight * BIOME_SPAWN_BASE
			dx = wx - BIOME_ROLLING_CENTER.x
			dz = wz - BIOME_ROLLING_CENTER.y
			dist = sqrt(dx * dx + dz * dz)
			weight = 0.0
			if dist < BIOME_ROLLING_RADIUS:
				var t := 1.0 - dist / BIOME_ROLLING_RADIUS
				weight = t * t
			total += weight
			acc += weight * BIOME_ROLLING_BASE
			dx = wx - BIOME_HIGHLAND_CENTER.x
			dz = wz - BIOME_HIGHLAND_CENTER.y
			dist = sqrt(dx * dx + dz * dz)
			weight = 0.0
			if dist < BIOME_HIGHLAND_RADIUS:
				var t := 1.0 - dist / BIOME_HIGHLAND_RADIUS
				weight = t * t
			total += weight
			acc += weight * BIOME_HIGHLAND_BASE
			var base := BIOME_FALLBACK_BASE if total <= 0.0001 else acc / total
			var detail := n * (1.8 + 0.14 * base)
			var dome_dx := wx - DOME_CENTER.x
			var dome_dz := wz - DOME_CENTER.y
			var dome := 1.0 - smoothstep(dome_edge, DOME_RADIUS, sqrt(dome_dx * dome_dx + dome_dz * dome_dz))
			buf[row + ix] = clampf((base + detail + DOME_AMP * dome) * _bake_scale, HEIGHT_MIN, HEIGHT_MAX)
```

And in `bake_region()`, immediately after the existing fractal setup, insert:

```gdscript
	_noise.offset = Vector3.ZERO
```

Test helpers + cases to add to `tests/test_terrain_baker.gd`:

```gdscript
func _bake8(region: Vector2i, roads: Array = []) -> Image:
	return TerrainBaker.new().bake_region_8bit(region, 1.0, IMAGE_WIDTH, roads)

func _max_abs_delta(img_a: Image, img_b: Image) -> float:
	var max_delta := 0.0
	for iz in img_a.get_height():
		for ix in img_a.get_width():
			max_delta = maxf(max_delta, absf(img_a.get_pixel(ix, iz).r - img_b.get_pixel(ix, iz).r))
	return max_delta

func test_bake_region_8bit_is_deterministic_and_differs_from_float() -> void:
	var img_a := _bake8(Vector2i.ZERO)
	var img_b := _bake8(Vector2i.ZERO)
	assert_that(img_a.get_data()).is_equal(img_b.get_data())
	assert_that(img_a.get_data()).is_not_equal(_bake(Vector2i.ZERO).get_data())

func test_bake_region_8bit_approximates_float_within_tolerance() -> void:
	for region in [Vector2i(0, 0), Vector2i(3, 1), Vector2i(5, 5)]:
		assert_that(_max_abs_delta(_bake8(region), _bake(region))).is_less(0.5)

func test_bake_region_8bit_approximates_float_on_carved_regions() -> void:
	var loop := _build_loop(LOOP_CENTER)
	var region := Vector2i(3, 3)
	assert_that(_max_abs_delta(_bake8(region, [loop]), _bake(region, [loop]))).is_less(0.5)
```

(If the half-texel sampling shift pushes max-delta past 0.5, tighten `_bake_natural8` by blending the two adjacent map texels `(ix, iz)` and `(ix + 1, iz)` at 0.5/0.5 before decoding `n` — the tolerance test is the calibration oracle.)

---

## Task 4 — `"bulk8"` flag through the seeder worker pipeline (B6)

**Files:** `scripts/world/terrain_seeder.gd`; tests added to existing `tests/suites/test_terrain_seeder_streaming.gd`

**Interfaces:**
- Consumes: `TerrainBaker.bake_region_8bit` (Task 3), existing `_make_job` / `_worker_bake` / `_apply_record` / `_bake_sync` record flows.
- Produces (`scripts/world/terrain_seeder.gd`):
  - `_make_job(...)` record gains `"bulk8": priority != PRIORITY_LIVE` (CORRIDOR=1 and PREFETCH=2 → bulk8; LIVE=0 and player path → float).
  - `_worker_bake(worker_baker, job)` reads `job.get("bulk8", false)`, branches to `bake_region_8bit` vs `bake_region`, and its finished record gains `"bulk8"`.
  - `_bake_sync` `_baked` record gains `"bulk8": false` (player sync is always float).
  - `_apply_record` copies `"bulk8"` into the `_baked[loc]` cache record.
  - New counter `async_bulk_completed_count: int` (bumped under `_lock` in `_worker_process` next to `async_completed_count` when the finished record's `bulk8` is true).
  - New accessor `func _async_bulk_completed() -> int` (locked read).
- Keeps every existing streaming test byte-identical: test (a) queues with default `PRIORITY_LIVE` → float → still byte-matches `_bake_direct`; test (b) default priority → float; test (c) player sync → float.

- [ ] Extend `tests/suites/test_terrain_seeder_streaming.gd` with the four assertions below (corridor job is `bulk8` + deterministic vs direct 8-bit reference + differs from float; LIVE job is not `bulk8`; player sync `_baked` record is not `bulk8`; mixed bulk+float jobs on the shared worker cross-contaminate nothing). Do not modify the three existing test functions.
- [ ] Run the targeted suite (`-a res://tests/suites/test_terrain_seeder_streaming.gd`) → new tests FAIL (no `bulk8` in jobs/records yet).
- [ ] Implement the seeder changes per the snippets below.
- [ ] Run the targeted suite → all existing + new tests PASS (the EXISTING `test_worker_streamed_bake_matches_sync_baker` byte-identical assertion is in this run).
- [ ] Run the import probe + full GDUnit suite.
- [ ] Commit (`git add scripts/world/terrain_seeder.gd tests/suites/test_terrain_seeder_streaming.gd`).

Seeder snippets (context lines from today's file shown for exact placement):

```gdscript
# in _make_job: add the flag (priority is set by every caller, never defaulted
# inside this function)
func _make_job(loc: Vector2i, width: int, gen: int, priority: int = 0) -> Dictionary:
	var bulk8 := priority != PRIORITY_LIVE
	return {
		"loc": loc,
		"width": width,
		"gen": gen,
		"scale": bake_scale,
		"roads": _roads.duplicate(),
		"priority": priority,
		"bulk8": bulk8,
	}

# in _worker_bake: branch on the flag, tag the finished record
func _worker_bake(worker_baker: TerrainBaker, job: Dictionary) -> Dictionary:
	var loc: Vector2i = job["loc"]
	var width: int = job["width"]
	var gen: int = job["gen"]
	var scale: float = job["scale"]
	var roads: Array = job["roads"]
	var bulk8: bool = job.get("bulk8", false)
	var image: Image
	if bulk8:
		image = worker_baker.bake_region_8bit(loc, scale, width, roads)
	else:
		image = worker_baker.bake_region(loc, scale, width, roads)
	var range := _scan_height_range(image)
	return {
		"loc": loc,
		"gen": gen,
		"image": image,
		"height_min": range.x,
		"height_max": range.y,
		"bulk8": bulk8,
	}

# in _worker_process, next to `async_completed_count += 1` (still under _lock)
		if bool(record.get("bulk8", false)):
			async_bulk_completed_count += 1

# in _bake_sync, tag the player's synced record as float (cache schema superset)
	_baked[loc] = {"image": image, "height_min": range.x, "height_max": range.y, "bulk8": false}

# in _apply_record, propagate the flag into the cache so tests/consumer code
# can assert provenance
	_baked[loc] = {
		"image": image,
		"height_min": record["height_min"],
		"height_max": record["height_max"],
		"bulk8": bool(record.get("bulk8", false)),
	}

# new field + locked accessor (declare next to the other test-visible counters)
var async_bulk_completed_count: int = 0

func _async_bulk_completed() -> int:
	var n := 0
	_lock.lock()
	n = async_bulk_completed_count
	_lock.unlock()
	return n
```

New tests for the streaming suite:

```gdscript
func test_corridor_job_is_bulk8_and_deterministic() -> void:
	var seeder := TerrainSeeder.new()
	var target := Vector2i(4, 3)
	seeder._queue_bake(target, IMAGE_WIDTH, seeder.PRIORITY_CORRIDOR)
	assert_that(seeder._work_queue.back()["bulk8"]).is_true()
	var landed := await _await_until(func() -> bool: return seeder._pending_count() > 0, 10.0)
	assert_that(landed).is_true()
	seeder._drain_pending(null, 100)
	var cached: Variant = seeder._baked.get(target)
	var img: Image = (cached as Dictionary)["image"] as Image if cached is Dictionary else null
	assert_that(img).is_not_null()
	if img == null:
		return
	assert_that((cached as Dictionary)["bulk8"]).is_true()
	var ref := TerrainBaker.new().bake_region_8bit(target, 1.0, IMAGE_WIDTH, [])
	assert_that(img.get_data()).is_equal(ref.get_data())
	assert_that(img.get_data()).is_not_equal(_bake_direct(target, IMAGE_WIDTH).get_data())
	seeder._stop_worker()

func test_live_job_is_never_bulk8() -> void:
	var seeder := TerrainSeeder.new()
	seeder._queue_bake(Vector2i(5, 4), 8, seeder.PRIORITY_LIVE)
	assert_that(seeder._work_queue.back()["bulk8"]).is_false()
	seeder._stop_worker()

func test_player_sync_bake_record_is_never_bulk8() -> void:
	var terrain := Terrain3D.new()
	add_child(terrain)
	var seeder := TerrainSeeder.new()
	seeder.terrain = terrain
	add_child(seeder)
	await get_tree().create_timer(0.3).timeout
	seeder._player_region = PLAYER_REGION
	var data: Terrain3DData = terrain.data
	assert_that(data).is_not_null()
	if data == null:
		return
	seeder._ensure_region(data, PLAYER_REGION)
	assert_that(seeder.sync_bake_count).is_equal(1)
	var rec: Variant = seeder._baked.get(PLAYER_REGION)
	assert_that((rec as Dictionary)["bulk8"]).is_false()
	seeder._stop_worker()

func test_worker_mixes_bulk_and_float_jobs_without_cross_contamination() -> void:
	var seeder := TerrainSeeder.new()
	var bulk_loc := Vector2i(6, 2)
	var float_loc := Vector2i(2, 2)
	seeder._queue_bake(bulk_loc, IMAGE_WIDTH, seeder.PRIORITY_CORRIDOR)
	seeder._queue_bake(float_loc, IMAGE_WIDTH, seeder.PRIORITY_LIVE)
	var landed := await _await_until(func() -> bool: return seeder._pending_count() >= 2, 12.0)
	assert_that(landed).is_true()
	seeder._drain_pending(null, 100)
	var bulk_img: Image = (seeder._baked.get(bulk_loc) as Dictionary)["image"] as Image
	var float_img: Image = (seeder._baked.get(float_loc) as Dictionary)["image"] as Image
	assert_that(bulk_img.get_data()).is_equal(
		TerrainBaker.new().bake_region_8bit(bulk_loc, 1.0, IMAGE_WIDTH, []).get_data())
	assert_that(float_img.get_data()).is_equal(_bake_direct(float_loc, IMAGE_WIDTH).get_data())
	assert_that(bulk_img.get_data()).is_not_equal(float_img.get_data())
	seeder._stop_worker()
```

(The mixed test is the regression net for the `_noise.offset` reset: if `bake_region()` still left a stale 8-bit offset, `float_img` would deviate from `_bake_direct` and the byte-identical assert fires.)

---

## Task 5 — Diag bulk telemetry + ~4× measurement (B6)

**Files:** `diag/freeze_diag.gd`; `scripts/world/terrain_seeder.gd` (only if a counter-accessor detail is missing — Task 4 already lands `_async_bulk_completed()`)

**Interfaces:**
- Consumes: `_async_bulk_completed()` accessor (Task 4), `TerrainBaker.bake_region` / `bake_region_8bit`.
- Produces: extended `DIAG_RUN … RESULT` line with an appended `async_bulk=` field (after `async_apply=`), and a one-shot `BULK_DIAG float_us=… bulk_us=… ratio=…` micro-benchmark line printed once before the two runs.

- [ ] Add `var bulk := seeder._async_bulk_completed()` and the `async_bulk=%d` slot to the RESULT print in `_measure`, and add `_benchmark_bulk()` (below) called at the top of `_initialize()`.
- [ ] Run the FULL diag manually (watchdog timeout ≥ 600000 ms):
     `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://diag/freeze_diag.gd`
- [ ] Verify: 2 RESULT lines (run 1/roads and run 2/no-roads) + exactly one `BULK_DIAG` line; the roads run reports `async_bulk > 0` (corridor pre-bake now goes through the 8-bit path); no `out of bounds`, no `2147483647`.
- [ ] Record the actual `BULK_DIAG ratio`: expect ~4× (one C++ `get_image` bulk fill replacing ~1M GDScript virtual `get_noise_2d` calls). If the diag exposes it as per-crossing latency (`SYNC_*us` spread / `max_sync_us` between the two runs), report that; otherwise state the ratio as the expected ~4× gain. NEVER assert timing in the GDUnit suite (flaky) — the diag is the measurement, the plan notes it.
- [ ] Run the import probe + full GDUnit suite.
- [ ] Commit (`git add diag/freeze_diag.gd`).

```gdscript
## One-shot micro-benchmark of the bulk bake path vs the float path on a single
## natural region; printed to the log, never asserted in the suite (timing is
## too flaky for CI). Uses ONE baker so the offset reset is also exercised.
func _benchmark_bulk() -> void:
	var loc := Vector2i(4, 4)
	var baker := TerrainBaker.new()
	var t0 := Time.get_ticks_usec()
	baker.bake_region(loc, 1.0, 1024, [])
	var float_us := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	baker.bake_region_8bit(loc, 1.0, 1024, [])
	var bulk_us := Time.get_ticks_usec() - t0
	print("BULK_DIAG float_us=%d bulk_us=%d ratio=%.2f" % [float_us, bulk_us, float(float_us) / float(maxi(bulk_us, 1))])
```

---

## Final verification

- [ ] Import probe: zero `SCRIPT ERROR` / `Parse Error` / `Failed to load`.
- [ ] Full GDUnit suite: `findstr /c:"Overall Summary:" _gdunit.txt` → the baseline **grows** from 69 to ~76 (5 Route + 3 baker + 4 streaming additions); `0 errors | 0 failures`; 16 orphans benign.
- [ ] `git status --short`: only the intended `.gd` files staged; zero `*.uid` entries; `_gdunit.txt` untracked/ignored.

---

## Self-Review

**A6 mapping → Task 1 + Task 2.** Task 1 ships the pure `FreezeRoute` (region coords 0..8, hard ±12 guard, closed 8×8 loop, deterministic) with a failing-first GDUnit proof; Task 2 rewrites `freeze_diag.gd` to drive it, dropping the 30,848 m straight that measured out-of-bounds territory (`Location (29,0) out of bounds` spam + `2147483647` sentinel). The old measurement structure is preserved exactly (`sync_player_pos` tick timing, `_process` idle timing, `SYNC_`/`IDLE_`/`RESULT` lines); self-termination is now triple-layered (fixed 32-crossing cap, `DIAG_WALL` never-drive-out bail, `quit()`), watchdog-safe with the outer tool timeout. The route also drives BOTH axes so regions leave and re-enter the live ring, so the diag still measures the removal path the old straight exercised.

**B6 mapping → Task 3 + Task 4 + Task 5.** Task 3 lands `bake_region_8bit` (bulk `get_image` L8 fBm base → scaled float heights → clamp; same roads/blur/guard tail) plus the mandatory `_noise.offset` reset in `bake_region`; Task 4 threads the `"bulk8"` flag strictly through CORRIDOR/PREFETCH jobs and keeps LIVE/player jobs float, with the provenance key on every baked record. The EXISTING byte-identical worker-vs-sync assertion is untouched and kept green (live jobs never set `bulk8`), and the new mixed-job test proves no cross-contamination on a shared worker baker. Player-region never-8-bit is asserted twice (live job flag false + synced cache record false). Task 5 surfaces `async_bulk` in the diag RESULT and measures the ~4× gain via the `BULK_DIAG` line (reported, never CI-asserted).

**Placeholder scan:** no `TBD`, `TODO`, `FIXME`, `???`, `PLACEHOLDER`, or `…to be decided` remains — every interface and code block above has concrete signatures and bodies. The only deliberate "if" is the §offset calibration oracle in Task 3 (tolerance test drives the exact 0.5-texel blend if the mapping drifts past 0.5 m), which is an explicit, executable fallback, not a placeholder.

**Constraint compliance:** TAB indentation in every snippet; only targeted `git add <file>`; `AGENTS.md`/`start_game.bat`/`play_game.bat`/`.godot/` untouched; GDUnit warnings-as-errors respected (no `:=` on Variant-returning calls; float `is_equal_approx` only for floats); verification = import probe (expect zero errors) THEN the `-s …GdUnitCmdTool.gd --ignoreHeadlessMode` suite with the `Overall Summary` grep; diag runs are manual-only under a ≥600000 ms watchdog; 69/0/0/16 baseline grows.