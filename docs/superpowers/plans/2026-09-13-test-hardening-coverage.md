# Test Hardening / Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close four verified coverage gaps with real, behavior-gating GDUnit4 tests: D2 (WorldDriver road bootstrap: hub-ring/connector/pass-loop point counts, closed-vs-open chain flags, `set_roads()`-BEFORE-first-push ordering), D3 (TerrainSeeder corridor pre-bake: `MAX_CORRIDOR_LOCS=40` cap, `CORRIDOR_MARGIN=1` coverage, spawn-closest ordering), D8 (PlayerCarController visual swap per active car + garage config loading via `new_from_save()`/`get_active_car()`), D10 (TrackBuilder mesh sanity: verts/tris > 0, closed-loop seam, open-connector segment adjacency, trimesh collision). No production behavior changes — every one of these behaviors is already externally observable through public/production surfaces (`get_roads()`, `_baked`/`_queued_get` test surfaces, `car.config`, `build_track` child nodes/meshes), so no seams are required.
**Architecture:** 11 new test functions across 4 new test files (root `tests/` mirrors existing scene-based style in `test_open_world.gd`/`test_track_system.gd`; `tests/suites/` mirrors the `TerrainSeeder` unit style in `test_terrain_seeder_streaming.gd`). D2a/D2b build a real WorldDriver harness (tree-based: `RoadNetwork` + `mountain_pass_zone.tscn` sibling) and reuse the real `open_world_root.tscn` scene for the ordering proof. D3 unit-drives a bare `TerrainSeeder.new()` (no tree, `terrain = null`), exactly as the streaming suite does. D8 drives the real `player_car.tscn` via `scene_runner` with the REAL save path (`SaveManager.save_game(0, ...)`, save/restored in `before_test`/`after_test` for hermeticity). D10 unit-drives bare `TrackBuilder` nodes and asserts on `ArrayMesh` surface arrays + `ConcavePolygonShape3D.get_faces()`.
**Tech Stack:** Godot 4.7.2 GDScript, GDUnit4 (headless CLI per AGENTS.md)
**Spec:** inventory D2, D3, D8, D10 (see preamble)

## Global Constraints

- **TAB indentation in ALL new GDScript** (the whole repo, tests included, is tab-indented — see `test_track_system.gd`, `test_terrain_seeder_streaming.gd`).
- **NEVER `git add -A`.** Stage only the new `.gd` files by explicit path. `*.uid` files are gitignored noise (project `.gitignore`); `git status --short` must never list them before a commit. Existing untracked noise (`_gdunit.txt`, `diag/`, etc.) stays untouched.
- **Do NOT modify** `AGENTS.md`, `start_game.bat`, `play_game.bat`, `.godot/`, or any production `.gd`/`.tscn`/`.tres`. Decision: **zero production-code changes** — every D2/D3/D8/D10 behavior is testable through existing public/test surfaces.
- **GDUnit4 treats GDScript warnings as errors**: no `:=` on Variant-returning calls; vector `is_equal_approx` needs a SAME-TYPE approx arg (`assert_that(vec).is_equal_approx(vec, Vector2(0.001, 0.001))`); prefer plain `assert_that(x).is_*` assertion names that already exist in the repo (`is_equal`, `is_not_equal`, `is_greater`, `is_less`, `is_between`, `is_true`, `is_false`, `is_not_null`, `is_greater_equal`, `assert_array(...).contains_exactly`, `assert_float(...).is_equal_approx(a, b)`).
- **No placeholder tests**: every test makes ≥3 real asserts; no empty asserts, no `# TODO`, no `return`-supported pass-through.
- Pure-addition coverage tests may PASS on first run (behaviors are already correct) — that is explicitly fine; the gate is: real asserts execute + the full suite stays green + a behavior regression would fail. Do NOT invent a failure by breaking code. The "run" step documents first-run outcome honestly.
- **Worker hygiene:** every D3/D2 test that touches `TerrainSeeder` asynchrony MUST call `seeder._stop_worker()` before returning (matches `test_terrain_seeder_streaming.gd`).
- **Verification commands (AGENTS.md recipe)** — run BOTH, in order, every task:
  1) Probe: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import . 2>&1 | findstr /i "SCRIPT ERROR Parse Error Failed to load"` → expect ZERO matches.
  2) Suite: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1` then `findstr /c:"Overall Summary:" _gdunit.txt`.
- **Baseline:** `Overall Summary: 69 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`. **Target after this plan: ~80 test cases (69 + 11 new), 0/0/**; orphan drift (queue_free'd visuals, runner teardowns) up to ~8 extra is benign and reported, not failed. If the summary shows ≥1 failure/error, the task is NOT done — debug and fix the TEST (production code is out of scope and must not change).
- **Commit cadence:** one standalone commit per task after its green suite run, message style matching repo history (`test(D6): <what the tests lock in> ...`). Never commit a red suite.

---

## Task 1 — D2a: WorldDriver road bootstrap (point counts + closed-vs-open flags)

**Files:** create `tests/test_world_driver_bootstrap.gd`

**Interfaces:**
- Consumes:
  - `WorldDriver.extends Node3D` (`scripts/world/world_driver.gd`): `_ready() -> void` auto-runs `_bootstrap_roads()` then `_push_player_position()`; exports `road_network_path: NodePath = NodePath("RoadNetwork")`, `mountain_pass_zone_path: NodePath = NodePath("MountainPassZone")`; helpers `_hub_ring() -> Array[Vector3]`, `_pass_connector(end: Vector3) -> Array[Vector3]`.
  - `RoadNetwork` (`scripts/world/road_network.gd`): `add_road(points: Array[Vector3], width: float = 8.0, closed: bool = true) -> void`, `get_roads() -> Array[Array]`; `_roads` order == child `TrackBuilder` order (each `add_road` does `add_child(builder)`).
  - `MountainPassZone` = `res://scenes/world/regions/mountain_pass_zone.tscn` → instance of `scripts/track/mountain_pass.gd` (`build_own_ground=false`); `var road_points: Array[Vector3]` generated in `_ready()` (length 36); zone global position `(3800, 14, 3200)`.
  - `TrackBuilder` children per road (from `build_track`): `[MeshInstance3D` (road surface), `MeshInstance3D` (red edge), `MeshInstance3D` (white edge), `StaticBody3D]`. `ArrayMesh.surface_get_array_index_len(0)` returns the index count: **closed strip = 6·n**, **open strip = 6·(n−1)** for n spline points.
- Produces: `tests/test_world_driver_bootstrap.gd` (2 test functions, tab-indented, `extends GdUnitTestSuite`).

Step list:
- [ ] Create `tests/test_world_driver_bootstrap.gd` with a helper `_build_bootstrapped_world() -> Dictionary` and 2 tests. Helper: `root := auto_free(Node3D.new())`; `add_child(root)`; instantiate `mountain_pass_zone.tscn`, `zone.name = "MountainPassZone"`, `root.add_child(zone)`; `network := RoadNetwork.new()`, `network.name = "RoadNetwork"`, `root.add_child(network)`; `driver := WorldDriver.new()`, `root.add_child(driver)` (its `_ready()` bootstraps — zone `road_points` is already populated because `_ready` fires on the earlier `add_child`); `await get_tree().process_frame`; return `{"network": network, "zone": zone, "driver": driver}`. Note: no `TerrainSeeder`/`ChunkStreamer`/`%PlayerCar` exist in this harness, so `_push_player_position()` no-ops — safe and intended.
- [ ] Test A `test_bootstrap_builds_ring_connector_and_pass_loop`: get `roads := network.get_roads()`; assert `roads.size() == 3`. Ring `roads[0]`: `size() == 96`; every point `is_equal_approx(Vector3(128.0, 2.2, 128.0), Vector3(200.0, 0.05, 200.0))` distance from `(128, 2.2, 128)` is `is_between(109.9, 110.1)` and `y == 2.2`. Connector `roads[1]`: `size().is_between(300, 600)`; `roads[1][0].is_equal_approx(Vector3(128.0, 2.2, 128.0), Vector3(0.01, 0.01, 0.01))`; `roads[1][roads[1].size()-1].x > 3800.0`; connector end sits on the loop start: `roads[1][roads[1].size()-1].distance_to(roads[2][0]).is_less(1.0)`. Pass loop `roads[2]`: `size() == 36`; loop all world-offset near the zone: every point `x.is_between(3700.0, 3940.0)` and `z.is_between(3100.0, 3310.0)`. Guard each step with early-return + `is_not_null`/`is_true` asserts so a regression fails loud, not with an index error.
- [ ] Test B `test_road_builders_reflect_closed_vs_open_flags` (uses the same helper): for `i in network.get_roads().size()`: `builder := network.get_child(i) as TrackBuilder`; `surface := builder.get_child(0) as MeshInstance3D`; `idx := (surface.mesh as ArrayMesh).surface_get_array_index_len(0)`. Ring (i=0, closed): `idx == 6 * 96` (= 576). Connector (i=1, open): `idx == 6 * (roads[1].size() - 1)` — proves the strip does NOT wrap on the chain (the open flag reached `build_track`). Pass loop (i=2, closed via `add_road(zone_roads, 11.0)` default): `idx == 6 * 36` (= 216). Also assert each builder `get_child_count() == 4`.
- [ ] Run verification 1 (probe) + verification 2 (suite + `findstr /c:"Overall Summary:"`). Expected: suite **67→69 → 71** (2 new). First-run outcome expected: **PASS** (behavior is correct; add "passes-on-first-run (coverage lock-in)" note in the commit message).
- [ ] Commit: `git add tests/test_world_driver_bootstrap.gd`; `git commit -m "test(D6): lock in WorldDriver road bootstrap — hub ring/connector/pass-loop counts + closed-vs-open via mesh index counts (2 tests)"`.

---

## Task 2 — D2b: critical ordering — `set_roads()` BEFORE first `_push_player_position()`

**Files:** append to `tests/test_world_driver_bootstrap.gd` (single new test function).

**Interfaces:**
- Consumes: `res://scenes/world/open_world_root.tscn` (full scene; `WorldDriver._ready` calls `_bootstrap_roads()` → `TerrainSeeder.set_roads(network.get_roads())` → then `_push_player_position()` → first `sync_player_pos`; `TerrainSeeder._bake_sync` snapshots `_roads` at bake time, so the FIRST spawn-region bake at frame 1 is roads-conformed under correct ordering). `TerrainSeeder` test surfaces: `_roads: Array`, `_baked: Dictionary` (`Vector2i -> {"image": Image, ...}`), `_queued_get(loc: Vector2i) -> int` (−1 = not queued). `TerrainBaker.bake_region(region: Vector2i, scale: float, width: int, roads: Array) -> Image` is deterministic and seeded — baking region `(0,0)` with **empty** roads gives the exact image the first bake would produce if roads had NOT been set first.
- Produces: 1 test function using the ordering proof below.

Step list:
- [ ] Add `test_roads_handed_to_seeder_before_first_bake_conforms_spawn`. `runner := scene_runner("res://scenes/world/open_world_root.tscn")`; `await runner.simulate_frames(2)`. `seeder := runner.scene().get_node_or_null("TerrainSeeder") as TerrainSeeder` (assert `is_not_null`). Asserts:
  1. `seeder._roads.size() == 3` and `(seeder._roads[1] as Array).size() == (network := runner.scene().get_node("RoadNetwork") as RoadNetwork).get_roads()[1].size()` — roads reached the seeder.
  2. Corridor pre-bake ran off the pass loop: `seeder._queued_get(Vector2i(3, 3)) != -1` (region containing the world-offset pass loop ~`(3800, 14, 3200)`; its 9 neighbor locs are all within the `MAX_CORRIDOR_LOCS=40` cap because the corridor union covers ~35 unique locs — see D3).
  3. **Ordering proof:** `seeder._baked.has(Vector2i(0, 0))` is true AND its cached image ≠ the empty-roads bake. `img := (seeder._baked[Vector2i(0, 0)] as Dictionary)["image"] as Image`; `ref := TerrainBaker.new().bake_region(Vector2i(0, 0), 1.0, 1024, [])`. `assert_that(img.get_data()).is_not_equal(ref.get_data())`. Rationale (write as a comment in the test): the spawn region `(0,0)` is `SPAWN_REGION`, which `_prebake_corridor` skips and the prefetch ring also skips once `_baked` holds it — so its only bake is the frame-1 synchronous bake, which snapshots `_roads`. If `set_roads()` did NOT run before the first `_push_player_position()`, that first bake used empty roads (image would be byte-identical to `ref`) and would never be corrected (no later bounce of `_baked`), so `is_not_equal` pins the ordering. Guard: if `img == null` or `!seeder._baked.has(...)`, `return` after a failing `is_true()` so the suite doesn't index a missing key.
- [ ] Run verification 1 + 2. Expect suite **71 → 72**, 0/0. (This test reads real Terrain3D bakes; if frame 2 is too early for `_baked[(0,0)]` under load, bump to `simulate_frames(3)` — document the observed frame count in the file comment.)
- [ ] Commit: `git add tests/test_world_driver_bootstrap.gd`; `git commit -m "test(D6): lock in WorldDriver set_roads() before first push — spawn bake must be road-conformed from frame 1"`.

---

## Task 3 — D3: TerrainSeeder corridor pre-bake (cap, margin, spawn-closest ordering)

**Files:** create `tests/suites/test_terrain_seeder_corridor.gd`

**Interfaces:**
- Consumes (`scripts/world/terrain_seeder.gd`, all already test-exposed or directly readable):
  - Consts: `REGION_SIZE = 1024.0`, `CORRIDOR_MARGIN = 1`, `MAX_CORRIDOR_LOCS = 40`, `SPAWN_REGION := Vector2i(0, 0)`.
  - `set_roads(roads: Array) -> void` (clears `_baked`, bumps gen, then calls `_prebake_corridor`).
  - `_prebake_corridor(roads: Array) -> void` — margin-expands every road point's region loc by ±`CORRIDOR_MARGIN`, erases `SPAWN_REGION`, sorts `_corridor_sort`, queues first `MIN(size, MAX_CORRIDOR_LOCS)` unmatched locs as `PRIORITY_CORRIDOR`.
  - `_corridor_sort(a: Vector2i, b: Vector2i) -> bool` — `(a.x²+a.y²)` then `a.x` then `a.y`.
  - Test surface: `_queue_bake(loc, width, priority)` guards re-queue via `_queued`; `_queued_count() -> int`, `_bake_queued(loc: Vector2i) -> bool`, `_queued_get(loc: Vector2i) -> int`, `_stop_worker() -> void`. `_queued` entries are only cleared on main-thread drain/`set_roads`/`_stop_worker`, so the count read immediately after `set_roads` equals the dispatch count even while the worker runs.
- Produces: `tests/suites/test_terrain_seeder_corridor.gd` (3 test functions + a `_new_seeder() -> TerrainSeeder` helper returning a bare `TerrainSeeder.new()` untouched by a tree).

Step list:
- [ ] Create the suite file. Every test: `var seeder := TerrainSeeder.new()`; end with `seeder._stop_worker()`.
- [ ] Test A `test_corridor_margin_covers_one_ring_and_skips_spawn`: `seeder.set_roads([[Vector3(1024 * 3 + 1, 0.0, 1024 * 3 + 1)], [Vector3(1100.0, 0.0, 50.0)]])`. First road point → base `(3,3)`, margin → 9 locs in `(2..4, 2..4)`. Second → base `(1,0)`, margin `(0..2, −1..1)` → 9, minus erased `SPAWN_REGION` = 8. Assert `_queued_count() == 17`; `_bake_queued(Vector2i(3, 3))` true (own region); `_bake_queued(Vector2i(2, 4))` true (proves `CORRIDOR_MARGIN=1` adds the neighbor ring); `_bake_queued(Vector2i(0, 0))` false (spawn excluded); `_bake_queued(Vector2i(5, 5))` false (beyond margin).
- [ ] Test B `test_corridor_cap_keeps_forty_spawn_closest`: 6 one-point roads at region-loc centers whose 3×3 margin blocks are pairwise disjoint (≥3-cell gap in at least one axis) and distances strictly increasing from `SPAWN_REGION`: `(1,0) d=1`, `(1,3) d=10`, `(4,1) d=17`, `(4,4) d=32`, `(7,2) d=53`, `(7,5) d=74`. 6×9 = 54 unique locs, cap = 40. Roads: `[[Vector3(1024.0 + 1, 0.0, 0.0 + 1)], ...]` — encode `loc.x * 1024` style. Assert `_queued_count() == 40` (cap); `_bake_queued(Vector2i(1, 0))` true (spawn-closest kept); `_bake_queued(Vector2i(1, 3))` and `_bake_queued(Vector2i(4, 4))` true (first four blocks fully kept → ordering is spawn-first); `_bake_queued(Vector2i(7, 5))` false (farthest block wholly dropped). Comment: blocks d 1/10/17/32 are the 36 closest locs, so the remaining 4 slots come from block (7,2) — the farthest block MUST be absent, i.e. spawn-closest ordering, not any-40.
- [ ] Test C `test_corridor_sort_orders_by_distance_then_x_then_y`: `locs := [Vector2i(0,2), Vector2i(1,1), Vector2i(2,0), Vector2i(1,-1), Vector2i(0,1)]`; `locs.sort_custom(_corridor_sort)` (callable on a bare instance via `seeder._corridor_sort`); assert `locs` is `[(0,1), (1,-1), (1,1), (0,2), (2,0)]` (d 1 → d 2 sorted by x then y → d 4 by x).
- [ ] Run verification 1 + 2. Expect suite **72 → 75** (3 new), 0/0. First-run: PASS (coverage lock-in). Watch the `Overall Summary` for broke-as-error on any `:=` on a Variant-typed expression — use explicit casts (`var rec: Variant = ...`) instead.
- [ ] Commit: `git add tests/suites/test_terrain_seeder_corridor.gd`; `git commit -m "test(D6): lock in TerrainSeeder corridor pre-bake — 40-loc cap, margin-1 coverage, spawn-closest ordering (3 tests)"`.

---

## Task 4 — D8: PlayerCarController visual swap per active car + garage config loading

**Files:** create `tests/test_player_car_controller.gd`

**Interfaces:**
- Consumes:
  - `scenes/vehicle/player_car.tscn` root `RigidBody3D` + `scripts/vehicle/vehicle_physics.gd` (`@export var config: CarConfig`; `_ready` assigns `mass = config.mass_kg` only when `config != null`; scene preloads `starter_car.tres` so default config is always non-null). Child `PlayerCarController` (`scripts/player/player_car_controller.gd`): `_ready()` calls `VehicleManager.register_player_car(car)`, then `Garage.new_from_save().get_active_car()`, then loads `res://resources/cars/%s.tres` into `car.config` ONLY if `ResourceLoader.exists(path)`, then `_apply_visual()` (clears `CarBody` children and instantiates `config.visual_path` under `CAR_ORIENT`).
  - `resources/cars/*.tres`: `starter_car.tres` (class D, default visual `res://assets/cars/sports_coupe.glb`, mass 1100), `muscle_car.tres` (class C, `visual_path = res://assets/cars/muscle_car.glb`, mass 1420), `rally_hatch.tres` (class B, `res://assets/cars/rally_hatch.glb`, mass 1050). `assets/cars/{sports_coupe,muscle_car,rally_hatch}.glb` exist.
  - `Garage` (`scripts/career/garage.gd`): `static new_from_save() -> Garage`, `get_active_car() -> String`, `get_owned_cars() -> Array[String]`, `set_active_car(car_id) -> void`. `SaveManager.save_game(0, data)` / `load_game(0)` persist the active car through the REAL save path (the exact integration the controller uses).
  - PackedScene root-name probe: `(load(glb_path) as PackedScene).get_state().get_node_name(0)` — read-only, spawns no node.
- Produces: `tests/test_player_car_controller.gd` (3 test functions + `before_test`/`after_test`).

Step list:
- [ ] Create the suite (root `tests/`, matches `test_vehicle_physics.gd` style). Lifecycle: `var _orig_save: Dictionary = {}`; `func before_test()` → `_orig_save = SaveManager.load_game(0)`; `func after_test()` → `SaveManager.save_game(0, _orig_save)` (hermeticity — the suite writes the real slot-0 save the same way the game does, then restores). Helper `_glb_root(path: String) -> String`. Private controller entry is still callable (`car.get_node("PlayerCarController")._apply_visual()`) for the in-place swap probe.
- [ ] Test A `test_garage_new_from_save_loads_active_config` (pure Garage, no scene): `garage := Garage.new_from_save()`; `var owned := garage.get_owned_cars()`; assert the starter trio is owned (`assert_array(owned).contains(["starter_car", "muscle_car", "rally_hatch"])`); `garage.get_active_car()` non-empty and in `owned`; for each of the 3 ids: `ResourceLoader.exists("res://resources/cars/%s.tres" % id)` true, `load(...) as CarConfig` is not null, and `config.visual_path` is not empty and `ResourceLoader.exists(config.visual_path)` true. (Lock-in: every owned car's config + visual is loadable end-to-end.)
- [ ] Test B `test_switch_active_car_swaps_config_and_visual`: `Garage.new_from_save().set_active_car("muscle_car")`; `runner := scene_runner("res://scenes/vehicle/player_car.tscn")`; `await runner.simulate_frames(3)`; `car := runner.scene() as VehiclePhysics`; `body := car.get_node("CarBody")`. Assert `car.config.car_class == "C"`, `car.config.visual_path == "res://assets/cars/muscle_car.glb"`, `car.mass.is_equal(1420.0)` (config took effect in physics), `body.get_child_count() == 1`, `(body.get_child(0) as Node3D).name == _glb_root("res://assets/cars/muscle_car.glb")`. Then WITHOUT a new scene: `Garage.new_from_save().set_active_car("rally_hatch")`; `car.config = load("res://resources/cars/rally_hatch.tres") as CarConfig`; `(car.get_node("PlayerCarController") as Node)._apply_visual()`; `await get_tree().process_frame`; assert `body.get_child_count() == 1` (old visual removed, not accumulated) and the child name now equals the rally root — this is the per-active-car swap.
- [ ] Test C `test_missing_active_car_config_falls_back_to_scene_default`: `SaveManager.save_game(0, {"owned_cars": ["ghost_car"], "active_car": "ghost_car"})`; new runner → 3 frames; assert `car.config.car_name == "Striker"` (starter), `car.config.visual_path == "res://assets/cars/sports_coupe.glb"`, `body.get_child_count() == 1` (default visual still resolved).
- [ ] Run verification 1 + 2. Expect suite **75 → 78** (3 new), 0/0. First-run: PASS (coverage lock-in). Note: each runner instantiation registers the car with `VehicleManager`; that is benign (same as the streaming suite tolerating registration side effects). Orphan drift from `queue_free()`'d visuals resolves within the awaited frames — if the summary shows a large orphan spike, add one more `await get_tree().process_frame` before test end; 16→~20 orphans is benign and not a failure.
- [ ] Commit: `git add tests/test_player_car_controller.gd`; `git commit -m "test(D6): lock in PlayerCarController active-car config + visual swap via real save path (3 tests)"`.

---

## Task 5 — D10: TrackBuilder mesh sanity (verts/tris, closed seam, open adjacency, trimesh)

**Files:** create `tests/test_track_builder.gd`

**Interfaces:**
- Consumes (`scripts/track/track_builder.gd`): `TrackBuilder extends Node3D`, `build_track(points: Array[Vector3], closed: bool = true) -> void` (early-returns for `points.size() < 3`). On success adds, in order: road-surface `MeshInstance3D` (ArrayMesh), 2 edge `MeshInstance3D`s, 1 `StaticBody3D` + `CollisionShape3D` (`ConcavePolygonShape3D` via `coll_mesh.create_trimesh_shape()`).
  - `ArrayMesh` math for n spline points: **verts = 2n** (left/right pair per point); **indices = 6·n closed / 6·(n−1) open**; closed strip reuses seam vertices (wrap `j := (i+1) % n`, so `max index == 2n−1`, no duplicated seam verts, watertight). Read via `mesh.surface_get_arrays(0)` → `arr[Mesh.ARRAY_VERTEX]`/`[Mesh.ARRAY_INDEX]`, or `surface_get_array_index_len(0)`.
  - Trimesh faces: `(col.shape as ConcavePolygonShape3D).get_faces()` size == index count (48 tris → 144 vectors), matching the visual strip exactly.
- Produces: `tests/test_track_builder.gd` (3 test functions + `_ring(n)`/`_chain(n)` point generators).

Step list:
- [ ] Create the suite. Helper `_ring_points(n: int) -> Array[Vector3]` (circle radius 60, y 0), `_chain_points(n: int)` (collinear, 0→1200). Each test: `builder := auto_free(TrackBuilder.new())` (matches `test_prop_scatterer.gd`'s `auto_free` usage).
- [ ] Test A `test_closed_loop_mesh_counts_and_seam`: n := 24; `builder.build_track(_ring_points(24))`; `surface := builder.get_child(0) as MeshInstance3D`; `arr := (surface.mesh as ArrayMesh).surface_get_arrays(0)`; `verts := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array`; `idx := arr[Mesh.ARRAY_INDEX] as PackedInt32Array`. Assert `verts.size() == 48`, `idx.size() == 144`, `surface_get_array_index_len(0) == 144`, min index 0 and max index 47 (no vertex above 2n−1), surface count 1. Edges: `builder.get_child_count() == 4`; children 1 and 2 (edge stripes) each have `surface_get_array_index_len(0) == 144` (closed edges wrap too). Seam comment: the wrap references `0`/`1` again instead of duplicating — that is why verts stays exactly 2n.
- [ ] Test B `test_open_chain_uses_segment_adjacency_without_wrap`: n := 24; `builder.build_track(_chain_points(24), false)`; assert verts 48, `idx.size() == 6 * 23 == 138`, max index 47, both edge stripes `== 138`; child count 4. Comment: open strip runs to the last point (n−1 quads), the end cap is the final quad between points n−2→n−1 with clamped tangent — no closing back across the map.
- [ ] Test C `test_trimesh_collision_matches_visual_and_short_inputs_noop`: closed build (n=24): `body := builder.get_child(3) as StaticBody3D`; `col := body.get_child(0) as CollisionShape3D`; `faces := (col.shape as ConcavePolygonShape3D).get_faces()`; assert `faces.size() == 144` (one tri per visual index). Open build (n=24, closed=false): `faces.size() == 138`. Then a fresh builder with `build_track([], true)` → `get_child_count() == 0`, and `build_track([Vector3.ZERO, Vector3.ONE])` → `get_child_count() == 0` (size<3 early-return, no crash).
- [ ] Run verification 1 + 2. Expect suite **78 → 81**, 0/0. First-run: PASS (coverage lock-in).
- [ ] Commit: `git add tests/test_track_builder.gd`; `git commit -m "test(D6): lock in TrackBuilder mesh sanity — closed seam, open adjacency, trimesh faces, <3-point noop (3 tests)"`.

---

## Task 6 — Final verification, full-suite green, sweep

**Files:** none (verification/cleanup only).

Step list:
- [ ] `git status --short` — confirm NO `*.uid` files appear (they are gitignored); confirm no production file was touched by this plan (only the 4 new `tests/*.gd` files, already committed in Tasks 1–5).
- [ ] Run verification 1 (probe) and expect zero `SCRIPT ERROR`/`Parse Error`/`Failed to load`.
- [ ] Run verification 2 and `findstr /c:"Overall Summary:" _gdunit.txt`. **Expected: `Overall Summary: 81 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | ~16-24 orphans`** (69 baseline + 11 new; orphans benign). If not → fix the failing TEST only; production code is out of scope.
- [ ] Confirm `git log --oneline -5` shows exactly the 5 task commits (one per task) and `git status --short` is back to the pre-plan noise (identical to the baseline listing, MINUS the new committed test files).

---

## Self-Review

**Inventory mapping (each requested gap → task):**
- D2 WorldDriver road bootstrap → Tasks 1 + 2. Hub-ring 96 pts / 110 m radius / y 2.2, connector endpoints + dense ~10 m sampling, pass-loop 36 world-offset pts (`test_bootstrap_builds_ring_connector_and_pass_loop`); closed-vs-open chain flags via real builder meshes 576 vs 6·(n−1) vs 216 (`test_road_builders_reflect_closed_vs_open_flags`); `set_roads()`-BEFORE-`_push_player_position()` ordering proven behaviorally on the real scene — the frame-1 spawn bake must be byte-different from an empty-roads bake (`test_roads_handed_to_seeder_before_first_bake_conforms_spawn`).
- D3 TerrainSeeder corridor pre-bake → Task 3. `MAX_CORRIDOR_LOCS=40` cap + spawn-closest ordering (`test_corridor_cap_keeps_forty_spawn_closest`), `CORRIDOR_MARGIN=1` neighbor coverage + `SPAWN_REGION` exclusion (`test_corridor_margin_covers_one_ring_and_skips_spawn`), deterministic tie-break order (`test_corridor_sort_orders_by_distance_then_x_then_y`). Queue/drain/priority remain the streaming suite's domain (unchanged).
- D8 PlayerCarController visual swap + garage config → Task 4. Active-car config load + mass + visual root-name swap per car via the REAL save path (`test_switch_active_car_swaps_config_and_visual`), missing-config fallback to the scene default (`test_missing_active_car_config_falls_back_to_scene_default`), and the garage config-loading chain (`test_garage_new_from_save_loads_active_config`).
- D10 TrackBuilder mesh sanity → Task 5. verts=2n / tris=6n closed with seam reuse (`test_closed_loop_mesh_counts_and_seam`), open adjacency 6(n−1) end-cap strip (`test_open_chain_uses_segment_adjacency_without_wrap`), trimesh collision faces == visual tris + <3 no-op (`test_trimesh_collision_matches_visual_and_short_inputs_noop`).

**Placeholder scan:** none — all 11 functions carry ≥3 concrete asserts (count/constants/enumerated point assertions, mesh `surface_get_array_*` math, byte-level `Image.get_data()` comparisons, face-count equality); no empty asserts, no `# TODO`, no `return` after a trivially-true assert, no `pass`. The only `return`s are guards that first run a failing assert (null/missing-key), matching the existing `test_track_system.gd`/`test_terrain_seeder_streaming.gd` pattern.

**Seam audit:** ZERO production-code changes across all tasks. Verified observable surfaces: `RoadNetwork.get_roads()` public; `TrackBuilder` children/meshes public; `TerrainSeeder._roads/_baked/_queued_get/_queued_count/_bake_queued` are the suite-exposed surface the streaming tests already rely on; `PlayerCarController` is driven through the save file exactly as production does; `TrackBuilder.build_track` output nodes are ordinary children. No behavior-only-for-tests code is introduced, so no regression can be masked.

**Expected new suite count:** baseline 69 → **81 (+11 test functions across 4 new files**: `test_world_driver_bootstrap.gd` +2, +1 scene ordering = 3; `suites/test_terrain_seeder_corridor.gd` +3; `test_player_car_controller.gd` +3; `test_track_builder.gd` +3). Each gate: `0 errors | 0 failures | 0 flaky | 0 skipped`, orphans benign. Every task is independently reviewable (one file, one behavior family, one commit, its own green-suite run).