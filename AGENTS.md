# AGENTS.md — UltraDrive (Godot 4.7.2)

Project knowledge for autonomous agents. Godot project root = this directory
(`D:\AI Projects\UltraDrive`, res://). Godot binary:
`D:\Godot\Godot_v4.7.2-stable_win64.exe` (win64 arrows). GDUnit4 addon at
`addons/gdUnit4`, tests under `tests/` (suite: `tests/suites`).

## HEADLESS WORKFLOW (KNOWN-GOOD — reuse, don't rediscover)

GDUnit4 CLI correctly drags in the headless-mode guard, but ONLY when run
AFTER a normal `--headless` import+probe pass. The engine will refuse
`--headless` first-run launches with exit 103 ("Headless mode is not
supported!"), which has nothing to do with your code.

### Reliable recipe (each step self-terminating, add your own timeouts)

1) Permanent file-mode sanity: `git status --short` should NOT list `*.uid`
   (project `.gitignore` ignores them). If it does, they're untracked noise —
   never `git add -A`.

2) First-time or Big-Asset import (a real Blender/glb world):
   `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import . 2>&1 | findstr /i "SCRIPT ERROR Parse Error Failed to load"`
   → expect ZERO `SCRIPT ERROR` / `Parse Error` lines (benign `resources still
   in use at exit` and Terrain3D whitelist lines are allowed).

3) GDUnit suite (headless, PRECEDED by step 2 so gdUnit4 has had its
   first-run). IMPORTANT: `--ignoreHeadlessMode` MUST come AFTER the tool-script
   path (before it, the engine bails with exit 103):
   `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1`
   Then `findstr /c:"Overall Summary:" _gdunit.txt`.
   EXPECT: `Overall Summary: 144 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans` (144/144 — open-world seeding (terrain_baker + mountain_pass_zone) plus D5 control-mapping / world-map / transmission / streaming suites, the D6 race-loop suite `test_race_loop.gd` (14 tests; lap clock, checkpoint gating/caching/re-arm, RaceManager lifecycle, standings ordering, Play->HUD commit; kept leak-free via a suite `after_test` that sync-frees managed stub cars/checkpoints and resets RaceManager) and the graphics-lift suites added by the 2026-09-13 plan: `test_car_visuals` (paint dresser + visual wheels/brake-glow), `test_settings_presets` (quality ladder), `test_car_audio` (3-bed crossfade), `test_chase_camera`, `test_weather_sun` (sun driver) and `test_reflection_probes` (probe toggle/budget); 16 orphans are benign).
   GDUnit gotchas: it treats GDScript warnings as errors (e.g. `var x := some_func_returning_Variant()` fails to load) and its vector `is_equal_approx` requires a SAME-TYPE approx arg, not a float (`assert_that(vec).is_equal_approx(vec, Vector2(0.001, 0.001))`).

NOTE: if you run the GDUnit `-s` command ALONE (without the earlier headless
run), it may bail with exit 103/exit 1 "Headless mode is not supported". The
order above (plain --headless probe FIRST, then the -s run with the flag AFTER
the tool-script path) is what keeps it green. When in doubt, just run step 2
once, then step 3.

## BLENDER MCP (D4 — configured and verified)

- Blender MCP bridges this session to a live Blender 4.5 (addon version [1,6],
  protocol 5). Tools are exposed as `blender-mcp_*` in sessions whose
  `opencode.json` includes the server; they appear AFTER opencode restarts.
- MCP launcher (in `~/.config/opencode/opencode.json`): use the direct exe
  `["D:\\Tools\\uv\\bin\\blender-mcp.exe"]` — NOT `uv tool run blender-mcp` (that
  scans venvs and can hang). Env `BLENDER_HOST`/`BLENDER_PORT` default to
  localhost:9876.
- Verify with `opencode mcp list` (server should report Connected) and call
  `blender-mcp_get_addon_status` → expect `up_to_date`, protocol 5, Blender
  4.5.13. Check telemetry with `blender-mcp_get_addon_status` too.
- Known-good PNG → silhouette → model flow (used for the sports coupe &
  muscle/rally builds): generate in Blender via Hyper3D `rodin`, export glb to
  `assets/cars/`, consume as PackedScene.

## TERRAIN (D4)
- Mountain Pass ground is now a runtime-built `Terrain3D` (node named
  `GrassGround`): a 1024² height/color bake imported via `data.import_images()`
  anchored at region grid -512 (spacing 1.0, region_size 512) so the road loop
  (x/z ±80 m) sits inside regions -1..0. Every road point is recessed into a
  0.6 m "washbed" (SHOULDER_DISTANCE 8, BLEND_END_DISTANCE 40). Query heights
  with `Terrain3D.data.get_height()`. IMPORTANT: `import_images()` SNAPS its
  position to a region anchor (multiples of region_size), so a bake pane must
  start exactly on one — centered panes straddle a gap and return NaN half the
  loop (this bug was found + fixed in D4 in playtest).
- Foliage (`scripts/world/foliage.gd`) takes an optional
  `ground_height_provider: Callable(Vector2 -> float)` to sit on real terrain;
  falls back to Y 0 on flat circuits.

## OPEN WORLD SEEDING (D4/D5)
- `scenes/world/open_world_root.tscn` (WorldDriver root): runtime
  `Terrain3D` node + `TerrainSeeder` (`terrain_seeder.gd`). **Critical ordering:**
  setting `collision_mode` REINITIALIZES terrain data and RESETS region_size to
  256, so seeder._ready sets `collision_mode` FIRST, then
  `region_size = Terrain3D.SIZE_1024` (Terrain3DData has NO region_size property;
  data is null until node _ready). Hybrid async pipeline (D5): the PLAYER region
  sync-bakes on first push (~3.3 s as `_bake_sync`); neighbours stream from a
  worker Thread (Mutex/Semaphore), drained ≤ 2 regions/frame via `_process()`.
  `set_roads()` then `_push_player_position()` order matters so the bake
  conforms under roads BEFORE the first height lookup. Prefetch: `_prefetch_ring`
  (`PREFETCH_RADIUS 2`) re-primes after `set_roads()` resets `_ring_sig`.
  Region heats warp: never pass a >1-element `get_region_locations()` Array to a
  single `%s` format arg ("not all arguments converted"). Any script error
  during a headless diag leaves Godot hanging forever — always run a watchdog.
  NOTE: the Terrain3D `get_regionp`/`has_regionp`/`add_region_blankp`/
  `remove_regionp` signatures were VERIFIED green in D5 (streaming suite).
- `scripts/world/terrain_baker.gd` (pure RefCounted, deterministic): per-region
  seeded fBm base (region hash + 131/977, freq 0.003, 3 octaves), blended biome
  table (spawn/rolling/highland/fallback 2/6/20/1), alpine dome (5632,5632,
  amp 42, radius 5000), 3×3 blur, spawn plateau (128,128, r40, 2.2), clamp
  [-5,60]. Road conforming = `set_map(TYPE_HEIGHT)` bulk image path with
  **spatial clipping** (`_clip_chains`, AABB+margin) + per-texel segment-splat
  min (NOT a full-world O(cells×segments) field — that was the Wave 3 hang,
  126s/region → 2s). Roads are only wrapped as closed chambers when first/last
  points nearly touch (`_chain_is_closed`, ~2×avg spacing) so the open
  hub(128,128)→pass(3800,3200) connector never carves a phantom diagonal.
- Roads: `road_network.gd` (`add_road(points, width=8, closed=true)`,
  `get_roads()`, `is_on_road`) builds `track_builder.gd` meshes (`build_track`
  now takes `closed`; pass false for connector ribbons). `world_driver.gd`
  `_bootstrap_roads()` adds hub ring + pass connector + pass loop and calls
  `terrain_seeder.set_roads(...)` BEFORE the first `_push_player_position()`
  so the bake conforms under every road. `scenes/world/regions/mountain_pass_zone.tscn`
  is a lean instance of `mountain_pass.gd` with `build_own_ground`/
  `build_foliage`/`reposition_player` exports off (standalone scene defaults on).
- Cold open-world start used to be ≈ 35-40s (3×3×1024² sync bake, ~3.3s/region
  base floor); D5 made it ~3.3s to get driveable (player region sync) with the
  ring streaming async behind you. FastNoiseLite `get_image` bulk-noise is a
  possible ~4× cut but quantizes to 8-bit — not yet done.
- Minimap roads + pause map (D5): `scripts/ui/map_roads.gd` (static `MapRoads`:
  `resolve_road_source` finds the `road_network` group or tree-walks
  `get_roads()`, `compute_fit`, `world_to_screen`, `clip_circle`) is shared by
  `scripts/ui/minimap.gd` and `scripts/ui/world_map.gd` (class `WorldMap`, map
  overlay in `scenes/ui/pause_menu.tscn`). POI dots come from static
  `scripts/world/poi_registry.gd`. Roads silently no-op when no source exists.
- Open-world dressing: `scripts/world/prop_scatterer.gd` (PropScatterer —
  runtime MultiMesh props: guardrail/tent/power-pole/rock, built from fused
  primitives, rejection-sampled clear of roads via `is_on_road`, deterministic
  per seed) configurable per zone with `/self/` bridge presets.

## RACE LOOP (D6)
- `RaceManager` (autoload) owns race state: `queue_race(laps)` /
  `consume_pending_race()` bridge track-select (`laps_default` from the track
  registry) to the HUD — `race_ui.gd` consumes the pending lap count and calls
  `start_race(VehicleManager.get_all_cars(), laps)` on its first frame.
  Checkpoints are pooled from the `checkpoints` group through a cached
  `_all_checkpoints()` list invalidated on `GameState.scene_changed`.
- `checkpoint.gd` counts each vehicle once per armed cycle (an internal
  `_counted` map) instead of enter/leave edge detection; `reset()` re-arms.
  `lap_counter.gd` validates progression against the expected next index
  (wrap-around allowed) and tracks race/lap start times separately. Standings
  tie-break by lap, then checkpoint index, then distance to the next gate.
  Finish: `race_ui.gd` swaps the HUD to a FINISH banner with total time.
- Tested by `tests/suites/test_race_loop.gd` (14 tests) with `checkpoint_stub.gd`;
  kept leak-free via a suite `after_test` that sync-frees managed stub
  cars/checkpoints and resets RaceManager.

## PROJECT CONVENTIONS
- Runtime entry: `res://scenes/main.tscn`. Player on track:
  `res://scenes/vehicle/player_car.tscn` (VehiclePhysics, mass ~1100kg, 4×
  `Wheel*` children, `PlayerCarController` child with `_apply_visual()` swapping
  the CarBody glb per active car from `Garage.new_from_save().get_active_car()`).
- Cars are DOOM-style 3D: `assets/cars/*.glb` (sports_coupe, muscle_car,
  rally_hatch) each consumed as `PackedScene`; the player visual is the
  `SportsCoupe` instance with `CAR_ORIENT` (const Transform3D of a 180° Y
  rotation) so the nose faces forward. Chase camera: `scripts/camera/chase_camera.gd`.
- Career: `scripts/career/garage.gd` (Garage owns `_owned_cars`, `set_active_car`,
  saves via `SaveManager`). Garage UI: `scenes/ui/garage.tscn` + `scripts/ui/garage_ui.gd`.
- Progression classes: D/C/B/A/S via `car_config.gd` (`car_class`, mass, torque,
  gear_ratios, upshift/downshift kmh). Reverse (`-1`) is a real gear: drives
  backward, torque is flipped, capped at `max_reverse_speed_kmh` (25).
- Transmission (D5): `GameState.transmission_mode` is AUTO (default) or MANUAL
  (settings `%TransmissionOption`). Manual shifting on the controller:
  `shift_up` = physical button 3 (PS Triangle/Xbox Y), `shift_down` = button 0
  (PS X/Xbox A), keyboard E/Q; handbrake was moved to button 10 (RB/R1) to free
  the old Triangle binding. In MANUAL every gear change is player-input driven;
  in AUTO upshifts are RPM-based at `auto_shift_rpm_fraction` (0.92 × redline,
  so the rally car doesn't shift at ~2,850 rpm in 1st) and downshifts stay
  speed-table based; an over-rev guard rejects a downshift above `redline*1.05`.
- HUD: gauges are a Forza/GT-style cluster (`scripts/race/tachometer.gd`,
  `%Cluster` in `scenes/ui/hud.tscn`) driven by `scripts/race/race_ui.gd` from
  `car.get_drive_info()` (`speed_kmh`, `gear`, `rpm`) + config `idle_rpm`/
  `redline_rpm`/`car_class`.
- GDUnit structure: `functions` split into `pre_check`/`check_part_a`/`check_part_b`
  where the scene needs two frames; keep using `assert_that(...).is_equal`.
- The FUN files (the reasons the game exists) live in the playtest flows:
  garage→select car→drive; right-joystick orbit camera; FH5/GT7-style garage.
