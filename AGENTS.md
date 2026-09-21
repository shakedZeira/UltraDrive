# AGENTS.md — UltraDrive (Godot 4.7.2)

Project knowledge for autonomous agents. Godot project root = this directory
(`D:\AI Projects\UltraDrive`, res://). Godot binary:
`D:\Godot\Godot_v4.7.2-stable_win64.exe` (win64 arrows). GDUnit4 addon at
`addons/gdUnit4`, tests under `tests/` (suite: `tests/suites`).

## VISION BRIDGE (local image analysis)

- A text-only session (opencode/big-pickle) can still "see" via the
  `vision-bridge` plugin (`.opencode/plugins/vision-bridge.js`): pasted images
  are staged to `.vision/inbox/`, screen/window captures to `.vision/captures/`,
  and both are inspected through the **local** vision model `qwen2.5vl:7b`
  served by Ollama on this machine.
- Tools provided by the plugin: `analyze_image` (LLM should ALWAYS use this to
  read an image — it cannot see images directly) and `capture_game_window`
  (window title defaults to "UltraDrive").
- Ollama lifecycle: installed at `D:\Ollama` (models in `D:\Ollama\models`).
  The plugin **spawns `ollama serve` on demand and kills it after ~60s idle** —
  never leave it running (it grabs GPU/CPU and would slow the game). The LLM
  backend is forced to **Vulkan** via `OLLAMA_LLM_LIBRARY=vulkan` (the bundled
  CUDA libs are compiled with CUDA 12.8+ PTX that this GPU's driver 560.94
  (CUDA 12.6) cannot JIT — the NVIDIA driver cannot be upgraded because the
  Maxwell GTX 970 is EOL after the R580 branch). Vulkan works and is stable
  (~2.6 tok/s on this GPU), just slow; if analyses come back
  "llama-server process no longer running", check the env var survived.
- Expect slow analyses: ~90s per screenshot at 2.6 tok/s. Keep prompts short
  and bounded (`max_tokens` is capped in the plugin).
- `.vision/` is gitignored (transient staging + captures).

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
   EXPECT: `Overall Summary: 263 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 109 orphans` (263/263 — the 260 baseline plus 3 graphics support-ladder tests: hardware-recommended default preset, scene-env discovery, and preset auto-apply onto a scene tree; 17 orphans are benign).
   GDUnit gotchas: it treats GDScript warnings as errors (e.g. `var x := some_func_returning_Variant()` fails to load) and its vector `is_equal_approx` requires a SAME-TYPE approx arg, not a float (`assert_that(vec).is_equal_approx(vec, Vector2(0.001, 0.001))`).

NOTE: if you run the GDUnit `-s` command ALONE (without the earlier headless
run), it may bail with exit 103/exit 1 "Headless mode is not supported". The
order above (plain --headless probe FIRST, then the -s run with the flag AFTER
the tool-script path) is what keeps it green. When in doubt, just run step 2
once, then step 3.

## BLENDER MCP (D4)

- Blender MCP bridges this session to a live Blender 4.5 (addon version [1,6],
  protocol 5). Tools are exposed as `blender-mcp_*` in sessions whose
  `opencode.json` includes the server; they appear AFTER opencode restarts.
- **This laptop (2026-09-18):** Blender 4.5.13 LTS is a portable ZIP at
  `C:\Blender\blender-4.5.13-windows-x64\blender.exe` (matches the reference box
  version; not installed to Program Files on this machine). The MCP bridge was
  renamed: the package is now **`mcp-for-blender`** (installed via
  `uvx mcp-for-blender`, uv at `C:\Users\IMOE001\.local\bin\uvx.exe`); the
  bundled addon was installed with
  `uvx mcp-for-blender install-addon --addons-dir "%APPDATA%\Blender Foundation\Blender\4.5\scripts\addons"`
  (module `blender_mcp`, verified: `addon_utils.enable('blender_mcp')` OK
  headless via `--background --python-expr`).
- MCP launcher entry (in `~/.config/opencode/opencode.jsonc`):
  `{"type":"local","command":["C:\\Users\\IMOE001\\.local\\bin\\uvx.exe","mcp-for-blender"],"environment":{"BLENDER_HOST":"localhost","BLENDER_PORT":"9876","DISABLE_TELEMETRY":"true"}}`.
  Env `BLENDER_HOST`/`BLENDER_PORT` default to localhost:9876.
- Verify with `opencode mcp list` (server should report Connected) and call
  `blender-mcp_get_addon_status` → expect `up_to_date`, protocol 5, Blender
  4.5.13. Check telemetry with `blender-mcp_get_addon_status` too.
  To CONNECT: launch `C:\Blender\blender-4.5.13-windows-x64\blender.exe`,
  enable "Interface: MCP for Blender" in Preferences→Add-ons, then in the 3D
  viewport `N` panel → MCP for Blender tab → Start MCP Server (port 9876).
- Known-good PNG → silhouette → model flow (used for the sports coupe &
  muscle/rally builds): generate in Blender via Hyper3D `rodin`, export glb to
  `assets/cars/`, consume as PackedScene.
- **CC0 car pipeline (2026-09-18):** handcrafted public-domain vehicles replace
  AI-scripted geometry (`docs/plans/cc0_car_assets_plan.md`). Kit at
  `assets/cars/cc0/kenney_car-kit/` (GLB only, `License.txt` = CC0). Integrated
  cars live at `assets/cars/cc0_*.glb` and resolve through `CarVisuals.
  WHEEL_GROUPS` (Kenney wheel nodes are top-level, named `wheel-front-left`,
  `wheel-back-right`, …), each with a `resources/cars/cc0_*.tres`. Kenney GLBs
  are nose-+Z in GLB space (same as the AI cars) and carry per-corner wheel
  meshes with an X axle — they use the stock `CAR_ORIENT` and wheel-spin
  conventions untouched. Gate: `tests/suites/test_cc0_cars.gd`.

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
- P0–P7 open-world seeding (2026-09-18/19) — **suite green at 263 tests / 0 errors /
  0 failures**. Plan: `docs/plans/open_world_seeding_plan.md` (§3.0 = execution
  contract, STATUS block at end of §2 = what shipped).

## GRAPHICS QUALITY (2026-09-18)
- The quality ladder in `scripts/ui/settings_menu.gd` (QUALITY_PRESETS: Low/
  Medium/High) is the single source of truth for environment + viewport quality.
- Scenes no longer bake in max post-FX: their `Environment` sub-resources ship
  OFF (SDFGI/SSAO/SSR/volumetric fog/glow), and `GameState` re-applies the
  ladder on boot and on every `change_scene` (`SettingsMenuScript.apply_to_scene_tree`).
- First-boot default is hardware-recommended: `SettingsMenuScript.default_quality_preset()`
  detects weak/integrated GPUs (Radeon iGPU, Intel UHD/HD, VGA/llvmpipe) → Low;
  discrete cards → Medium. `quality_preset` is persisted in the slot-0 save and
  restored in `GameState._ready`. Raising to High in Settings works on any machine.
  - **P3 surfaces:** `scripts/vehicle/surface_registry.gd` (class_name
    `SurfaceRegistry`) maps terrain/weather to a grip table the tyres read via
    `vehicle_physics.gd` / `tire_model.gd` hooks. Gate: `test_surface_grip`.
  - **P4 climate:** `autoload/day_night_driver.gd` (DayNightDriver autoload in
    project.godot — the game clock; `advance_time` uses **`fposmod`**, tests
    must assert with ≥0.01 tolerance) + `scripts/world/regional_climate.gd`
    (5 region bands, alpine year-round snow) + `weather_manager.gd` season/regional
    sampling. Gates: `test_regional_climate`, `test_weather_sun`.
  - **P5 discovery:** `scripts/world/world_discovery.gd` (WorldDiscovery —
    monotonic visited-segment bitset, XZ segment math, `is_revealed`,
    `try_snap_to_revealed`, SaveManager persistence under `SAVE_KEY`),
    `scripts/ui/map_roads.gd` (`MapRoads` adds `route_polyline`, `screen_to_world`,
    static `route_target`; from==to yields the full enclosing chain),
    `scripts/ui/world_map.gd` (grey→white reveal + click-to-fast-travel gated on
    revealed), `scripts/ui/minimap.gd`, `scripts/world/world_driver.gd` (teleport).
    Gates: `test_discovery`, `test_map_route`.
  - **P6 living-world:** `scripts/world/event_registry.gd` (EventRegistry.place —
    6 event families, time_attack_N per anchor), `scripts/world/living_world.gd`
    (traffic driver), `scripts/world/poi_registry.gd` (POIRegistry — base 5
    landmarks + 11 event markers appended lazily via `_load_events`; `0..6144`
    tile bounds check applies ONLY to base POIs — events sit on the real road net,
    x[−200..9702] z[−2944..8605]). `open_world_root.tscn` gets the `open_world`
    group. Gate: `test_event_placement`.
  - **P7 streaming dressing:** `scripts/world/region_dresser.gd` (RegionDresser —
    ring mirror with spawn/free budgeting, `band_density`, `band_visibility`
    culling via `visible_instance_count`), `scripts/world/terrain_seeder.gd`
    (region callbacks + `corridor_budget_locs` km→locs ladder, MAX 190),
    `scripts/world/prop_scatterer.gd` + `scripts/world/foliage.gd` per-region
    `configure_for_region` hooks. Gates: `test_streaming_dressing`.
  - **Gotcha:** foliages/props own several MultiMesh children (grass 700 + trees
    40 …); `get_instance_count()` / `get_visible_instance_count()` SUM across all
    children (first-child-only reads return 700 not 740). `RegionDresser.
    _apply_band_budget` builds `placed` from the summed counts.

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
- Planning docs are version-controlled under `docs/` (gitignored `reports/`
  stays local): `docs/ROADMAP.md` (master roadmap; "No tech ceiling" — ambitions
  are never trimmed to Godot/current architecture, engine/tooling changes are in
  scope when they serve a goal), `docs/plans/*` (phase/feature gap-fill plans),
  `docs/research/*` (competitor + self-audit research). Read the roadmap section
  relevant to any new work before planning.
