# Graphics Lift — Car Paint → Reflections → Audio → Art Pass

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the garage → select car → drive loop look and sound "FH5/GT7-style" under Godot 4.7 Forward+ at 1080p60 mid-range, using the benchmark research (ForzaTech/Polyphony, verified) as the recipe: layered clearcoat-over-metallic paint, a reflection source for the paint in every view (garage probe + sky, gameplay per-car probe), per-part material overrides on the existing GLB splits, brake-glow + visual wheels, a tonemapper that preserves paint hue, and replacing the single pitch-lerped engine loop with a narrow-band multi-loop crossfade. Ceilings (no RT reflections, no BT.2020 wide-gamut, no photometric paint capture) are accepted; per-car ReflectionProbe + SSR + SDFGI + built-in FSR 2.2/TAA is the "closest-to-RT" finish.

**Architecture:** A shared runtime "car dresser" (`CarVisuals.apply_paint`) walks each instanced GLB visual and injects per-part `StandardMaterial3D` overrides (paint/glass/lights/trim/tires/rims — the GLBs already carry the split). Both `player_car_controller._apply_visual()` and `garage_ui._swap_preview()` route through it (they are duplicated today). The garage SubViewport gains a `ReflectionProbe` + procedural sky so clearcoat has something to reflect; gameplay gets a per-car real-time probe (off + profileable via a new settings toggle). `VehiclePhysics.get_drive_info()` exposes `brake`/`steer` so the visual layer can spin/steer wheels and ramp tail-light emissive. `WeatherManager.get_computed_sun_position()` finally drives every scene's sun. `car_audio.gd` moves from one audio loop pitched 0.8→2.2 to two/three narrow-band crossfading beds keyed off RPM/throttle. A quality-settings ladder (SSR/SDFGI/volumetric/MSAA/AgX/FSR2.2) replaces the dead `"msaa"` key.

**Tech Stack:** Godot 4.7.2 GDScript, GDUnit4, built-in Forward+ (no addons; FSR 2.2 is built-in since 4.2, enabled via `rendering/scaling_3d/mode`).

**Spec:** Decision log = A1 Balanced sweep · A2 All three cars equal · A3 Photo mode deferred · B1 1080p60 + quality ladder · B2 Profile-driven with perf tachometer + probe toggle · C1 Hybrid two-pass (runtime overrides now; authored textures in a later Blender MCP re-export pass) · C2 Stay 100% procedural (no HDRI/audio downloads) · D1 Minimal-viable audio (multi-loop crossfade + on/off-load; skid/wind/transmission deferred) · E1 Accept ceilings + built-in FSR 2.2 · E2 Wire settings ladder now.

## Global Constraints

- TAB indentation everywhere, including `.gd` files. Do not change whitespace style of unrelated lines.
- Never `git add -A` / `git add .` / `git add docs/`. Stage only the exact source/test files each task lists. Never stage `*.uid` (leave untracked — `.gitignore` excludes them and `git status --short` must NOT list `.uid` files).
- Do NOT touch `AGENTS.md`, `start_game.bat`, `play_game.bat`, or anything under `.godot/`.
- GDUnit4 treats GDScript warnings as errors. Never write `var x := <Variant-returning call>`; give explicit types (`var m: StandardMaterial3D = node.get_surface_override_material(i)`) or use `as <Type>`.
- Repo verification recipe, in this order (each self-terminating, add own timeouts):
  1. After any `.gd`/`.tscn` edit — import probe (expect ZERO `SCRIPT ERROR` / `Parse Error` / `Failed to load`; benign `resources still in use at exit` + Terrain3D whitelist lines allowed):
     `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import . 2>&1 | findstr /i "SCRIPT ERROR Parse Error Failed to load"`
  2. Full-suite gate BEFORE every commit (current baseline `83 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`; this plan adds a new suite — expect count to grow, orphans to stay ~16):
     `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1`
     then `findstr /c:"Overall Summary:" _gdunit.txt`.
  - Never run the `-s` command alone on a cold cache (exit 103). Run the step-1 import probe first, then the `-s` run with `--ignoreHeadlessMode` AFTER the tool-script path.
- Never commit until the FULL suite shows `0 errors | 0 failures` AND the step-1 probe is clean. Commit scoped per task with the repo's identity style (see `docs/superpowers/plans/2026-09-10-ultradrive-master-plan.md` for the `-c user.name/email` pattern). The plan `.md` itself is never committed.
- Public APIs stay backward compatible: `VehiclePhysics.get_drive_info()` gains NEW `brake`/`steer` keys (existing keys unchanged); `CarVisuals` is a NEW static class; `settings_menu` presets keep `ssao_enabled`/`glow_enabled` keys. Existing `tests/test_race_logic.gd`, `tests/test_vehicle_physics.gd`, and `tests/suites/test_race_loop.gd` must keep passing.

## Design Decisions (locked in)

- **Runtime car dresser (`CarVisuals.apply_paint`) is the single override path.** The GLBs already carry per-part surfaces (Paint/Glass/Headlight/Taillight/Trim/Tire/Rim). Import settings keep `extract=false` (embedded materials) — we override at instance time, never by editing `.tres`/GLB. Paint profile (benchmark): metallic ≈ 0.9–0.95, roughness ≈ 0.35, `clearcoat` 1.0, `clearcoat_roughness` ≈ 0.03. Rally hatch gets clearcoat forced on (its embedded material has none). Existing `resources/materials/car_paint.tres` is retuned to the profile and consumed as the default paint base (it is byte-identical to sports_coupe's embedded paint — un-orphans it).
- **The garage gets an IBL source, gameplay gets a per-car probe.** Garage: replace `background_mode=1` flat color with a procedural sky (C2: no HDRI download — `ProceduralSkyMaterial` tuned to a light stage) + a `ReflectionProbe` at the turntable; raise SubViewport 620×500 → 1024×768. Gameplay: one `ReflectionProbe` parented to the player car (Update Always, low-res), MUST have a settings toggle (B2) and a perf profiling step before enabling permanently; static probes at hub(128,128) and mountain_pass(3800,3200) keep probe blend ≤ 4.
- **`get_drive_info()` exposes `brake` (0–1, from `brake_input`) and `steer` (from `steer_angle`).** `player_car_controller.gd` gains a `_process()` visual layer: visual wheel nodes (match names from GLB: `Wheel_FL/FR/RL/RR` for sports_coupe, `Rim_FL/Tire_FL/...` for muscle/rally) spin via `speed_kmh / wheel_circumference`, front pair steers by the exposed `steer`, and the Taillight material's `emission_energy_multiplier` ramps ≈1.8 → 5–6 on brake (brake-glow start; disc glow deferred with the full art pass).
- **WeatherManager finally drives the sun** (A6): `get_computed_sun_position()` (already exists at `autoload/weather_manager.gd:42-45`) drives each scene's hard-coded sun DirectionalLight; `current_weather` stays CLEAR — this is a daylight loop, not a weather-system activation.
- **Settings ladder (Q3, E2):** replace the dead `"msaa"` key in `settings_menu.gd:10-14` with a real preset set applied at lines 28-33: `ssao_enabled`, `glow_enabled`, `volumetric_fog_enabled`, `ssr_enabled`, `sdfgi_enabled`, `msaa_3d`, `tonemap_mode` (ACES/AgX), probe on/off (M1), and (built-in) FSR 2.2 scaling mode. Extended later by the perf plan.
- **Tonemap consistency (Q4):** every scene uses ACES (`tonemap_mode=3`); `main.tscn:20` currently Filmic (2) → ACES. AgX (4) exposed as the settings option only.
- **Audio (M2, D1-minimal):** replace the single synthesized loop + `pitch_scale` 0.8→2.2 in `car_audio.gd` (lines 15-16, 105-135) with 2–3 procedurally generated WAV beds, each pitched ONLY in a narrow band (≈0.9–1.25), equal-power crossfaded by RPM, with an on-load / off-load gain+low-pass layer driven by throttle. Skid/wind/transmission beds and per-perspective mixes are explicitly DEFERRED (D1-minimal). Traffic cars get distance-based audio culling/disable.
- **Performance policy (B1/B2):** 1080p60 mid-range. SDFGI + SSR stay as-is (already on in gameplay scenes). Probe settings are measurement-gated: profile with the perf-tachometer plan (2026-09-13-perf-tachometer-and-trackbuilder.md) before finalizing probe update-rate/resolution; ship the probe toggle regardless.

## Verified Starting State (anchors re-checked 2026-09-13 — re-verify during implementation)

- Gameplay scenes already enable ACES + SDFGI (4 cascades, min_cell_size 0.5, bounce 0.4, energy 0.85) + SSAO (2.0) + SSR (24 steps) + volumetric fog + glow (`scenes/world/open_world_root.tscn`, `scenes/track/mountain_pass.tscn`, `scenes/test/test_track.tscn`).
- Garage lags: SubViewport 620×500 (`scenes/ui/garage.tscn:231`), `background_mode=1` flat color (`:134`), only 2 omnis (RimLight `:246`, FillLight `:252`), no sky/probe/SSR; turntable at `:265` (0.4 rad/s, `garage_ui.gd:39`).
- `scenes/main.tscn:20` `tonemap_mode=2` (Filmic) — the only non-ACES scene.
- All three GLBs carry real per-part splits; sports metallic 0.45 / muscle 0.55 (low for paint), rally has NO clearcoat; muscle+rally Glass lacks transmission/refraction; zero textures (flat color). `resources/materials/car_paint.tres` (metallic 0.45) is orphaned but byte-identical to sports_coupe's embedded paint.
- No `ReflectionProbe` anywhere in the project (grep = 0). Visual wheels are static GLB geometry; `brake_input` is a local var at `scripts/vehicle/vehicle_physics.gd:61`; `get_drive_info()` at `:159-165` lacks brake/steer. `scripts/player/player_car_controller.gd:19-35` (`_apply_visual`) and `scripts/ui/garage_ui.gd:178-189` (`_swap_preview`) both instantiate the raw GLB with no overrides.
- `scripts/vehicle/car_audio.gd` = single synthesized AudioStreamWAV loop, pitch 0.8→2.2 (lines 15-16, 105-135); traffic cars each run a full loop (`traffic_spawner.gd:41`).
- `scripts/ui/settings_menu.gd:10-14` dead `"msaa"` key; only `ssao`/`glow` applied at 28-33.
- `project.godot:119` `msaa_3d=2`; no TAA, no FSR, no debanding, no scaling config.
- `autoload/weather_manager.gd:42-45` `get_computed_sun_position()` has exactly one call site (`get_road_grip_factor()`, `vehicle_physics.gd:93`).
- Collision is a single `BoxShape3D` (1.8×0.5×4.0) on the RigidBody3D — keep (Agent D: simple collider + visual shell is already correct).

## Tasks

Tasks are grouped into Phases 0 (quick wins), 1 (gameplay immersion), 2 (art pass — DEFERRED to a Blender MCP follow-up per C1-hybrid, listed for scope only). Phase 0 must land first; its tasks are independent and can be parallelized by worker. Each task ends with its tests + the task-level commit.

### Task 1 — Shared `CarVisuals` paint override + wiring (Q1)

**Files:**
- Create `scripts/vehicle/car_visuals.gd` (static class)
- Modify `resources/materials/car_paint.tres` (retune metallic 0.45 → 0.92, roughness → 0.35, keep clearcoat 1.0 / clearcoat_roughness 0.03)
- Modify `scripts/player/player_car_controller.gd` (`_apply_visual`, call helper after visual swap)
- Modify `scripts/ui/garage_ui.gd` (`_swap_preview`, call same helper)
- Create `tests/suites/test_car_visuals.gd`

**Interfaces:**
- Consumes: instanced GLB trees under `CarBody` / `%CarVisual`; `CarVisuals.CAR_ORIENT` move or reference (keep existing const; do not break callers).
- Produces: `CarVisuals.apply_paint(visual_root: Node3D, profile: Dictionary) -> void` (recursive tree walk; per-part overrides by material/surface name: Paint → clearcoat-metal profile, Glass → roughness 0.05-0.15, Headlight/Taillight → keep emissive, Tire/Rim/Trim → flat PBR sanity), plus `DEFAULT_PAINT: Dictionary`.

- [ ] Retune `car_paint.tres` to the benchmark paint profile (metallic ≈0.92, roughness 0.35, clearcoat 1.0, cc_rough 0.03), keep `albedo_color` so it stays the default paint base.
- [ ] Create `CarVisuals` static class: `apply_paint(root, profile)` walks `get_children()` recursively (+ `MeshInstance3D` surface materials via `get_surface_override_material(i)`), matches material names containing `Paint` (or any material with `clearcoat_enabled`) and applies the paint profile (preserve per-car `albedo_color`); force `clearcoat_enabled = true` for rally.
- [ ] Wire `_apply_visual()` (after line 35) and `_swap_preview()` (after line 189) to call `CarVisuals.apply_paint(visual, _current_paint_profile())`.
- [ ] Tests: `test_car_visuals.gd` — a fabricated tree (MeshInstance3D nodes with named materials across two levels) asserts (a) paint surfaces get metallic≈0.92/clearcoat, (b) non-paint surfaces untouched, (c) rally-style material without clearcoat gets it forced, (d) nested lookup robustness (2-level hierarchy), (e) `DEFAULT_PAINT` values sane. Use `GdUnitTestSuite`, `before_test`/`after_test` hygiene mirroring `test_race_loop.gd`.
- [ ] Verification: import probe clean; full suite green (count grows by the new suite's tests); commit.

### Task 2 — Garage reflection source + viewport bump (Q2)

**Files:**
- Modify `scenes/ui/garage.tscn`
- Modify `scripts/ui/garage_ui.gd` (only if a probe-refresh hook is needed)

**Interfaces:** No code API change (scene-only).

- [ ] Change garage Environment `background_mode` 1 → sky (ProceduralSkyMaterial tuned to a cool light-stage gradient; C2 keeps it procedural).
- [ ] Add `ReflectionProbe` under the SubViewport root at the turntable origin (extents ≈ 8–10 m), `update_mode = ALWAYS` (low res 256 max for the 1024 viewport), baked ambient.
- [ ] Raise SubViewport size 620×500 → 1024×768 (`:231`); keep aspect convention used by `%CarVisual`/turntable code in `garage_ui.gd`.
- [ ] Rebalance Rim/Fill omnis as a softbox pair (warm key ≈ energy raised, cool rim) — small numeric tune only.
- [ ] Tests: none new (visual); verify `test_garage`-family and full suite green + import probe clean; commit. Manual gate: garage turntable shows paint reflections in the SubViewport.

### Task 3 — Settings quality ladder (Q3/E2) + tonemap consistency (Q4)

**Files:**
- Modify `scripts/ui/settings_menu.gd` (replace dead `"msaa"` key + preset application)
- Modify `scenes/ui/settings_menu.tscn` if controls are added
- Modify `scenes/main.tscn` (tonemap 2 → 3)
- Modify `tests/suites/test_settings_presets.gd` (extend or create)

**Interfaces:**
- Consumes: existing `GameState`/`SaveManager` settings flow.
- Produces: extended `QUALITY_PRESETS` handling `ssao_enabled`/`glow_enabled` (existing) + `volumetric_fog_enabled`/`ssr_enabled`/`sdfgi_enabled`/`msaa_3d`/`tonemap_mode`/`probe_enabled`; applied to the current scene's `WorldEnvironment` + `project.godot` where scene-global (AA, scaling).

- [ ] Rewrite `QUALITY_PRESETS` block (`settings_menu.gd:10-14`) to a typed preset dictionary; wire application at lines 28-33 to set the above keys on the active `Environment` (fog/SSR/SDFGI/probe) and project settings (MSAA, FSR 2.2 scaling mode, debanding) with `GameState` persistence.
- [ ] Set `scenes/main.tscn:20` tonemap → ACES (3) to match every other scene.
- [ ] Tests: presets apply expected key values; fresh default preset equals current defaults; MSAA/scaling keys in project.godot are settable without smoke. Extend or create `tests/suites/test_settings_presets.gd` with before/after hygiene.
- [ ] Verification: probe clean + full suite green; commit.

### Task 4 — `get_drive_info` brake/steer + visual wheels & brake-glow (Q5)

**Files:**
- Modify `scripts/vehicle/vehicle_physics.gd` (expose `brake`, `steer` in `get_drive_info()`)
- Modify `scripts/player/player_car_controller.gd` (visual wheel spin/steer + tail-light emissive ramp)
- Modify `tests/test_vehicle_physics.gd` or `tests/suites/test_car_visuals.gd` (keys present; ramp logic)

**Interfaces:**
- Produces: `get_drive_info()` dictionary grows `"brake"` (0–1, from `brake_input`) and `"steer"` (normalized −1..1 from `steer_angle`). Existing keys untouched.

- [ ] Expose `brake`/`steer` in `vehicle_physics.gd` `get_drive_info()` (normalize `brake_input` to 0–1; `steer_angle` to ±1 by max).
- [ ] `player_car_controller.gd`: new `_process()` visual layer — find wheel nodes by name from the active GLB (`Wheel_FL/FR/RL/RR` for sports_coupe; `Rim_*`/`Tire_*` for muscle/rally), rotate around local X by cumulative `speed_kmh / (2π·radius)`; steer front pair Z by `steer`; ramp the Taillight material `emission_energy_multiplier` ≈1.8 → 5–6 with `brake`. Guard: wheels must not spin when `CarBody` isn't the sports_coupe (per-car wheel name table).
- [ ] Tests: `get_drive_info()` contains `brake`/`steer` at rest and braking; visual wheel transform changes after simulated frames with speed (mirror `test_race_loop` scene-runner pattern if feasible), braking raises tail emission. Add to `test_car_visuals.gd` or the vehicle suite.
- [ ] Verification: probe clean + full suite green; commit. Manual gate: on track, wheels spin/steer and brake lights flare.

### Task 5 — WeatherManager sun driver (Q6)

**Files:**
- Modify `scripts/world/world_driver.gd` (add sun driver using `weather_manager.get_computed_sun_position()`)
- Modify `scenes/world/open_world_root.tscn`, `scenes/track/mountain_pass.tscn`, `scenes/test/test_track.tscn`, `scenes/ui/garage.tscn` (sun node transforms become driven; keep `DirectionalLight` shadows on)

**Interfaces:** none new (consume existing `WeatherManager.get_computed_sun_position()`).

- [ ] Add a light driver to `world_driver.gd` that on startup + on scene day/time change portals `get_computed_sun_position()` into each gameplay scene's sun node; keep `current_weather = CLEAR` (no gameplay weather). Clamp/lerp to avoid sun-under-ground pop.
- [ ] Remove/normalize the hard-coded sun transforms so the driver owns them at runtime (keep editor default).
- [ ] Tests: sun elevation/azimuth result is finite and never below horizon across 0..23h; driver leaves `DirectionalLight.shadow_enabled` true. Extend `test_frame...`/create small suite entry (reuse a `WeatherManager`-fixture pattern).
- [ ] Verification: probe clean + full suite green; commit. Manual gate: ambient light level changes across day in open world.

### Task 6 — Per-car gameplay ReflectionProbe + toggle (M1, B2)

**Files:**
- Modify `scripts/vehicle/player_car_controller.gd` (or `player_car.tscn`) — add a parented `ReflectionProbe` to the player car
- Modify `scripts/world/world_driver.gd` — static probes at hub(128,128) and mountain_pass(3800,3200), probe blend ≤ 4
- Modify `scripts/ui/settings_menu.gd` — `probe_enabled` toggle (from Task 3 ladder)

**Interfaces:** `probe_enabled` setting read by the car controller.

- [ ] Add a per-car `ReflectionProbe` child (Update Always, low res; extents ≈ car-size ×4), toggled by `probe_enabled`.
- [ ] Place static probes; verify total blended probes per view ≤ 4.
- [ ] Perf gate (B2): run the perf-tachometer plan's measurement before enabling high-res/Always; tune update-rate/resolution from numbers; keep toggle for users.
- [ ] Tests: toggling `probe_enabled` flips the probe's `update_mode`/visibility; static probe existence after `_bootstrap` in `test_open_world` (extend). Manual: paint reflects garage lights on the car body in gameplay.
- [ ] Verification: probe clean + full suite green; commit.

### Task 7 — Engine audio: narrow-band multi-loop crossfade (M2, D1-minimal)

**Files:**
- Modify `scripts/vehicle/car_audio.gd`
- Modify `scripts/world/traffic_spawner.gd` (distance-cull/disable traffic audio)
- Modify `tests/suites/test_car_audio.gd` (create/extend)

**Interfaces:** no public API change; internal bed generation + crossfade. `get_drive_info()` already carries `speed_kmh`/`rpm` (Task 4 adds `brake`/`steer`).

- [ ] Replace the single loop + `pitch_scale` ramp: generate 2–3 narrow-band procedural WAV beds (≈ idle + mid + top, each pitched only ~0.9–1.25×), equal-power crossfade by RPM; add on-load/off-load gain + low-pass shaping from throttle. Keep timbre tables per car class (sport/muscle/rally).
- [ ] Add distance-based audio culling/disable for traffic car audio to avoid the full-loop-per-car cost.
- [ ] Tests: bed set has correct band constraints; crossfade weights are equal-power & sum ≈1 across RPM sweep; on-load changes signal above rest (or equivalent deterministic assertions on generated data). Keep `car_audio` suite orphan-free.
- [ ] Verification: probe clean + full suite green; commit. Manual gate: rev pays listenable through the garage/on-track without chipmunk pitch.
- [ ] (Deferred, NOT in this plan) skid/wind/transmission beds, per-perspective mixes, granular playback.

### Task 8 — Camera presentation pass (M3)

**Files:**
- Modify `scripts/camera/chase_camera.gd`
- Modify `scripts/camera/orbit_camera.gd` (only if orbit-to-chase intro is added)
- Modify `tests/suites/test_chase_camera.gd` (create/extend)

**Interfaces:** none new.

- [ ] Add subtle speed/g-force shake (amplitude lerped by lateral g), a gear-shift FOV kick, and slight speed look-ahead to `chase_camera.gd:45-55`. Keep default transient off.
- [ ] Tests: follow-distance/fov respond to speed inputs deterministically across simulated frames; defaults unbroken. Manual: driving feels fast without nausea.
- [ ] Verification: probe clean + full suite green; commit.

### Phase 2 (DEFERRED — scope note only, per C1-hybrid)

Authored texture sets (paint/ORM/flake), wheel/suspension visual split + calipers, showroom/photo mode, interior light bakes — via the known-good Blender MCP PNG→silhouette→glb flow (AGENTS.md D4). A follow-up plan owns this; the current plan's runtime overrides are deliberately the ceiling for now. Document Godot-4 ceilings (no RT, no BT.2020, no photometric capture) in a `docs/superpowers/plans/2026-09-13-graphics-ceilings.md` one-pager (Task 9).

## Verification

- GDUnit headless suite (AGENTS.md steps 2-3): current baseline `83 | 0 | 0 | 16 orphans`; new cases for `CarVisuals.apply_paint`, `get_drive_info` brake/steer keys, settings presets, WeatherManager sun clamp (0-24h finite/above-horizon), car-audio bed constraints, chase-cam behaviour. Orphans stay ≈16 (reuse `before_test`/`after_test` sync-free hygiene from `test_race_loop.gd`).
- Perf (B2): perf-tachometer plan before/after Task 6 to fix probe update-rate/resolution; settings ladder is the escape valve at 1080p60.
- Playtest gate: garage → select each of the three cars → drive loop holds ≥60fps on mid-range with budget met; open-world seeding (terrain_baker + seeder) regression-free; no new engine warnings.

## Rollout order + open items

- Suggested order: Q4 (Task 3 partially) → Q1 (Task 1) → Q2 (Task 2) → Q5 (Task 4) → Q6 (Task 5) → M1 (Task 6) → M2 (Task 7) → M3 (Task 8). Tasks 1-5 are parallelizable.
- Open/owned externally: FSR 2.2/AgX availability confirmed built-in (no asset download — C2 held); perf numbers for Task 6; per-car wheel-name tables for the three GLBs (Task 4 — read from glTF JSON during implementation); decisions on any NIS-style upscaler rejection (recorded as ceiling).