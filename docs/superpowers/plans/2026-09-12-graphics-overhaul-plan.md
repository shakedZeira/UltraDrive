# UltraDrive — Graphics Overhaul Plan

Status: IN PROGRESS
Created: 2026-09-12
Applies to: UltraDrive (Godot 4.7.2-stable, Forward+, Jolt 120 Hz)
Plan authority: Gemini graphics blueprint provided by the user (adapted; all changes use built-in features / free CC0 textures — no paid assets).

## Goal

Close the gap between the flat prototype look and the "Forza Horizon"-style high-fidelity look using only Godot's built-in rendering features. Primary scene to satisfy: `res://scenes/test/test_track.tscn` (the current playable oval circuit).

## Design constraints (from the master plan + project rulings)

- Forward+ renderer is ALREADY active (`renderer/rendering_method="forward_plus"` in project.godot) — Task 1 of the blueprint is done.
- FOV-with-speed camera is ALREADY implemented in `scripts/camera/chase_camera.gd` (fov_min 70 / fov_max 90 / fov_speed_factor 0.05) — Task 4's FOV part is done; do NOT re-add another FOV controller.
- Terrain3D is installed (Phase 5) but the open world is unwired; this plan targets the test track scene ONLY.
- Ruling 33/36: never `:=` from a Variant; `class_name` additions need `--import`.
- Rulings 18/20: verification = grep headless output for `SCRIPT ERROR`/`Parse Error`/`Failed to load script`; run GDUnit (currently 22/22).
- Commits: scoped identity `git -c user.name="UltraDrive Dev" -c user.email="dev@ultradrive.local" commit -m "..."; never stage *.uid, docs/, reports/.
- D-drive only. Temp logs under D:\Temp\opencode.

## Texture source

Prefer PROCDURALLY-GENERATED textures (`NoiseTexture2D` / `GradientTexture2D` baked into `.tres`) over network downloads. If a CC0 texture is downloaded, keep it small (512-1024 px), commit it under `res://resources/textures/`, and record the source URL in a README. Prefer not to rely on network.

## Phase G1 — Environment core: sky, sun, lighting, post-processing (SUBa: env)

Target file: `scenes/test/test_track.tscn` (SubResource Environment + ProceduralSkyMaterial + Sun DirectionalLight3D). One subagent (SUBa), changes ONLY test_track.tscn.

1. **Sky**: upgrade ProceduralSkyMaterial to a warm "golden-hour" palette (sun on horizon ~20-30°, warm horizon tint, cool zenith). Keep the Sky/Environment structure.
2. **Sun (DirectionalLight3D)**: color `Color(1.0, 0.93, 0.82)`, energy ~1.2, `shadow_enabled = true`, `shadow_blur` slight, lower the sun angle to ~35° elevation for longer shadows.
3. **Ambient/Environment**:
   - `background_mode = 2` (Sky) already set.
   - `ambient_light_source = 2` (Sky) already set — keep.
   - `ambient_light_energy` ~1.0.
4. **SDFGI**: `sdfgi_enabled = true`, `sdfgi_cascades = 4`, `sdfgi_min_cell_size` ~0.5, `sdfgi_uses_occlusion = false` (probe only — Perf note), `sdfgi_bounce_feedback = 0.4`, `sdfgi_energy = 0.85`.
5. **SSAO**: `ssao_enabled = true`, `ssao_intensity = 2.0`, `ssao_radius = 0.5`, `ssao_bias = 0.01`.
6. **SSR**: `ssr_enabled = true`, `ssr_max_steps = 24`, `ssr_fade_in`, `ssr_fade_out`, `ssr_depth_tolerance = 0.6`.
7. **Tonemap**: `tonemap_mode = 3` (ACES), `tonemap_exposure` ~1.0. (Currently mode 2 = Filmic; ACES is the blueprint's choice. NOTE: opening in editor may reorder; keep keys sane.)
8. **Volumetric fog**: `volumetric_fog_enabled = true`, `volumetric_fog_density = 0.006`, `volumetric_fog_albedo` light warm, `volumetric_fog_emission` low, `volumetric_fog_length` ~64.0.
9. **Glow/Bloom**: `glow_enabled = true`, `glow_intensity = 0.6`, `glow_strength = 1.0`, `glow_bloom = 0.1`, `glow_hdr_threshold = 1.0`.
10. **Tone expose match camera**: skip — keep HUD legible (labels are bright).

ACCEPTANCE (SUBa):
- Run `scenes/test/test_track.tscn --quit-after 120` headless; grep → ZERO `SCRIPT ERROR`/`Parse Error`/`Failed to load script`; the Terrain3D whitelist lines are allowed only when the OPEN WORLD scene runs (this is the test track, no Terrain3D).
- GDUnit still 22/22.
- Report exact numeric values (color/energy/sdfgi/ssao/ssr).

## Phase G2 — Car paint clearcoat material (SUBa: car)

Target: `scenes/vehicle/player_car.tscn` + a new `res://resources/materials/car_paint.tres`.

1. Create a `StandardMaterial3D` resource `car_paint.tres`:
   - `metallic = 0.85`, `roughness = 0.18`.
   - `clearcoat = 1.0`, `clearcoat_roughness = 0.08`.
   - `albedo_color = Color(0.82, 0.13, 0.12, 1.0)` (a punchy race red — matches curb accent).
   - Enable `roughness_texture`/`ao_texture` only if a texture exists; otherwise flat values.
2. Assign as the `material_override` (or `surface_material_override/0`) on the `CarBody` MeshInstance3D in player_car.tscn.
3. Optional (only if trivial): set wheel/body depth — DO NOT restring physics.

ACCEPTANCE (SUBa): scene load headless clean; report the .tres values + how it is attached. No behavioral change to physics (mass/size unchanged).

## Phase G3 — Road (asphalt) + curbs PBR (SUBa: track)

Target: `scripts/track/track_builder.gd` (materials inside `build_track`). One subagent.

1. **Asphalt**: replace the flat `albedo_color Color(0.45,0.45,0.48)` + roughness 0.9 with:
   - `albedo_color = Color(0.18, 0.18, 0.20, 1.0)` (dark asphalt).
   - `roughness = 0.92`.
   - Add a procedural `NoiseTexture2D` (FastNoiseLite, seed fixed, frequency ~0.08) used as `roughness_texture` (making the surface read as asphalt, not plastic). Optionally add an AO map.
   - Keep `cull_mode = CULL_DISABLED`.
2. **Curbs**: keep the two edge meshes (red/white) but give them:
   - red: albedo (0.78, 0.10, 0.10), roughness 0.6.
   - white: albedo (0.85, 0.85, 0.82), roughness 0.6.
   (Minor — improves kerb read.)

ACCEPTANCE: build_track still constructs valid mesh (smoke via test_track load clean, zero script errors); GDUnit 22/22.

## Phase G4 — Foliage + wind sway + PBR ground (SUBa: foliage) — NEW per Gemini Step 3

Target: `scripts/test_circuit.gd` + NEW `scripts/world/foliage.gd` + NEW shader file(s). One subagent.

1. **PBR grass ground**: replace the flat `albedo_color Color(0.25,0.30,0.18)` ground plane material with:
   - a NoiseTexture2D-based albedo (patchy greens, seed fixed, frequency ~0.05, 512×512),
   - `roughness = 1.0`,
   - a subtle NoiseTexture2D normal map (frequency ~0.08, strength via `normal_enabled` + low `normal_scale` ~0.15) so the field reads as grass not hard plastic.
   - Keep `cull_mode = CULL_DISABLED` and the PlaneMesh size.
2. **Foliage system** (`scripts/world/foliage.gd`, class_name `Foliage`, extends Node3D):
   - `@export var density`, `@export var radius`, `@export var min_dist_from_track` — scatter grass clumps + simple low-poly trees around the oval (origin, ring radius ~60; scatter annulus 70–140 m so nothing is ON the road).
   - Use `MultiMeshInstance3D` for grass (a small two-triangle billboard/quad or cross-plane) and one for trees (cone+cylinder approx) — Quantity: grass ~600, trees ~40. `cast_shadow` off for grass.
   - Procedural placement: seeded RandomNumberGenerator; keep trees clear of the track ring (distance from origin > radius+road_width).
   - **Wind sway shader**: create `res://shaders/foliage_wind.gdshader` (vertex shader; sample a cheap sin/cos time wave, amplitude scaled by a per-vertex `_wind` attribute — simplest: scale by position.y or a COLOR/vertex tilt attribute; amplitude small ~0.05) and a `res://shaders/grass_wind.gdshader` variant if needed. Attach via `material_override` (ShaderMaterial) on the MultiMeshInstances.
3. Wire: `scripts/test_circuit.gd` `_ready()` adds one `Foliage.new()` child configured for the ring.

ACCEPTANCE: test_track headless load clean (foliage runs at circuit load); GDUnit 22/22; report tree/grass counts + shader.

## Phase G5 — Motion blur decision (controller) — Gemini Step 4

Godot 4 has NO built-in 3D motion blur (no Environment/Material property). The blueprint's Step 4 explicitly relies on an AssetLib third-party addon ("Camera Motion Blur for Godot 4"). Decision: DEFER the addon (network + unverifiable headless + licensing). Instead the speed sensation is covered by the already-present speed-based FOV (chase_camera.gd) + volumetric fog + bloom. If the player wants real motion blur later, install the addon from AssetLib as a separate task. Recorded in the plan.

## Phase G6 — Playtest polish hands-on (controller) + UI fixes (pause/menu wiring)

After G1-G4 land and verify, relaunch the game live (main.tscn → main_menu). Human check: menus clickable (pause), main menu wiring, visual result of G1-G4 on the oval circuit. Iterate one tuning round if the player reports something flat/broken.

## Out of scope (intentionally)

- Motion blur: DEFERRED (Godot has NO built-in 3D motion blur; the blueprint's Step 4 relies on a third-party AssetLib addon — network install + unverifiable headless + licensing. Speed sensation covered by the existing speed-FOV + fog + bloom. See Phase G5.)
- Terrain3D-authored terrain: plugin is INSTALLED + ENABLED (project.godot `[editor_plugins]`); the open world scene (open_world_root.tscn) is still unreachable until a drivable car is wired into it (master-plan Ruling 35). Foliage in this plan targets the PLAYABLE test track only.
- New car models (still the box car).
- Changing main menu/gameplay flow (small separate UI fix task, controller-owned).

## Deliverables to land (each = its own commit)

- G1: test_track.tscn environment upgrade — DONE `2e1113b` (`feat: Forza-style environment lighting (ACES, SDFGI, SSAO, SSR, fog, bloom)`).
- G2: car paint material — DONE `05193e4` (`feat: clearcoat car paint material`).
- G3: road asphalt/curb materials — DONE `3e0347a` (`feat: PBR asphalt and curb materials`).
- G4: foliage + grass PBR + wind sway (`feat: procedural foliage with wind sway and PBR grass ground`).

## Verification commands (all subagents)

- `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --import`
- `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" res://scenes/test/test_track.tscn --quit-after 120`
- grep output for `SCRIPT ERROR` / `Parse Error` / `Failed to load script` (ZERO real matches).
- `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests` (22/22).

## File ownership (NO overlaps between concurrent subagents)

- SUBa (env): `scenes/test/test_track.tscn` ONLY. DONE.
- SUBb (car): `scenes/vehicle/player_car.tscn` + `resources/materials/car_paint.tres`. DONE.
- SUBc (track): `scripts/track/track_builder.gd` ONLY. DONE.
- SUBd (foliage): `scripts/test_circuit.gd` + NEW `scripts/world/foliage.gd` + NEW `shaders/foliage_wind.gdshader`.
- Controller: UI fixes (pause menu clickability, hud.tscn mouse handling, main_menu wiring + garage button), progress.md.

## Sequence

- G1/G2/G3 dispatched in parallel (disjoint file ownership) — DONE, verified, each committed.
- G4 (foliage) dispatch now; commit independently; controller verifies cumulatively.
- Controller then does G6 (UI fixes + live relaunch) and updates progress.md, then relaunches main.tscn live for the human playtest.