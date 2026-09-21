# Graphics Gap Plan — UltraDrive vs Forza Horizon 6 / GT7

Generated 2026-09-20 by the `/graphics-gap` pipeline. Analysis log:
`.vision/analysis.md` (local, gitignored). References analyzed:
Forza Horizon 6 (4: cockpit, mountain-drive, urban-Ferrari, ocean-showcase) and
Gran Turismo 7 (4: PS5 Pro RT race, photomode grandstand, forest-damp, Corvette C2).

## Diagnosis (what the captures show)

UltraDrive renders flat-lit: `background_mode = SKY` gradient, flat ambient
`Color(0.5, 0.5, 0.55)` at energy 1.0, no SDFGI/SSAO/SSR/volumetric at the
capture preset, unlit blocky geometry, matte single-color materials, plain
gradient sky with no clouds/fog, oversized fades, minimal HUD. The references
are all directionally lit with bounce, atmospheric haze, detailed materials
(clearcoat paint, damp asphalt), rich sky, and polished UI.

---

## Ranked gap-closing plan (impact-per-effort)

### 1. [QUICK WIN] Sky + atmospheric haze — Environment/GDScript
- **Ref:** FH6 mountain-drive (lush greens, snow peaks, natural haze); GT7
  photomode grandstand (scattered clouds, atmospheric depth); GT7 forest-damp.
- **Now:** gradient sky, no clouds, no haze, no fog — color banding visible at
  horizon (captures show light-purple→white gradient).
- **Fix (`.tscn` + `.gd`, no assets):** per-scene `Environment` tweaks in
  `open_world_root.tscn` / `mountain_pass.tscn`:
  - `background_mode = SKY` + a `ProceduralSkyMaterial` with sun-based
    `sky_energy`, low `horizon` curve, and soft `sun_angle_max` falloff.
  - Add `Environment.fog_enabled = true`, `fog_light_color` near sky horizon,
    `fog_density ~0.0008`, `fog_sky_affect ~0.2` for depth cue (matches FH6 haze).
  - Cost: free; works at every preset. Quick win with the largest visual ROI.

### 2. [QUICK WIN] Directional lighting + shadows
- **Ref:** FH6 urban-Ferrari (convincing light/shadow, water reflections);
  GT7 PS5 Pro RT (crisp car geometry shading).
- **Now:** flat ambient-only illumination, no visible shadow contrast; capture
  analysis names "flat, lacks dynamic shadows/highlights" as the #1 issue.
- **Fix (`scene .tscn` + `settings_menu.gd`):** give every driving scene a real
  `DirectionalLight3D` (sun) — the evening shot is dawn but references are
  high-noon crisp. Raise ambient to a cooler `Color(0.6,0.62,0.7)` so the sun
  direction is readable; enable `DirectionalShadow3D` with soft `filter_quality
  = PCF_5x5` at Medium+, cloud-blurred `shadow_blur ~2.0` at High. Ensures
  `default_quality_preset()` results already visible; per-knob SS shadow toggle.

### 3. [QUICK WIN] Tonemapping / exposure / contrast — Environment + settings
- **Ref:** All four FH6 + both GT7 photomode frames (punchy, balanced
  contrast; GT7 "journalistic" high-contrast cars vs asphalt/grass).
- **Now:** ACES is set in presets but the scene reads washed-out/flat (cvaper:
  "no post-processing, basic, flat"). Likely `total_exposure` and no color
  grading.
- **Fix (`settings_menu.gd` apply path):** when applying presets also set
  `env.total_exposure = 0.9` (slightly darker), `env.tonemap_exposure` shading
  curve, and add a subtle `env.glow_enabled = true` at all presets with
  `glow_intensity = 0.4`, `glow_strength = 0.8`, `glow_bloom = 0.1|0.6` (HDR
  fill) — Low keeps glow off but Medium+ gets it. Contrast is free headroom.

### 4. [HIGH EFFORT, HIGH IMPACT] SDFGI / SSAO / SSR adjacency
- **Ref:** GT7 PS5 Pro + FH6 (bounce light under cars, ambient occlusion in
  foliage/buildings, glossy paint reflections).
- **Now:** presets turn SDFGI/SSAO/SSR on only at Medium+/High; the capture
  preset is likely Low (hardware-recommended on this GTX 970-class GPU) so none
  are active — explains the plastic look. SDFGI exists in the ladder, just not
  default.
- **Fix (rules-only; no new system):**
  - Verify the capture preset vs `apply_quality_preset()`; docs say
    `default_quality_preset()` picks Low for legacy GPUs — that is correct for
    this machine but robs the *reference* look. Recommend: keep Low for
    perf, but ship these environment presets so High matches refs.
  - SSAO at Medium: `ssao_intensity = 2.0`, `ssao_radius = 0.05`,
    `ssao_ao_channel_affect = 0.1` for car-to-ground contact darkening (GT7
    hallmark).
  - SDFGI at High: `sdfgi_cascaded_distance`, `sdfgi_energy = 0.8`,
    `sdfgi_ray_steps` for bounced sky light into under-car + foliage (ref FG).
  - Ground task for a sub-agent with a `test_quality_ladder` gate.

### 5. [QUICK WIN] Materials: paint/element roughness — per-car + per-element
- **Ref:** FH6 cockpit (smooth reflective paint, real dash), GT7 Corvette C2
  (glossy clear-coat, colored metal reflections).
- **Now:** per capture text: "basic flat materials, no reflectivity/detail on
  car", "blocky".
- **Fix (`car_config.tres` + `CarVisuals`)**: raise paint `metallic = 0.15` with
  `roughness = 0.35`, tint clearcoat over the paint swatch; set element parallax
  so windshield reflection appears (already partly in `CarVisuals`). No new
  assets — just tweak StandardMaterial3D params per toolkit color. Same for
  grass/rock at $distance with a cheap roughness bump (foliage MultiMesh).

### 6. [QUICK WIN] Camera/FOV — chase_camera transients toggles
- **Ref:** All FH6/GT7 third-person (FOV 70–90 push at speed, subtle roll,
  depth-of-field hint at distance).
- **Now:** `transients_enabled=false` default; scene overrides set it true in
  player scenes (S9 landed). Captures show "static camera, no dynamism".
- **Fix:** keep transients ON for player (already in `player_car.tscn`/open
  world via S9 scene edits) — so this gap may already be closed in the live
  scene; verify the capture was mid-S9. If still flat, raise `fov_min` 70→74.
  FOV adds perceived speed (matches "speed vignette" in reference UI).

### 7. [MED, WIRE-ON] Pause UI re-skin — HUD readability
- **Ref:** FH6/GT7 HUD is crisp, `white/light-blue on dark`, minimap, minimal
  chrome, corner-positioned leaderboard.
- **Now:** captures show a functional but plain HUD with no contrast hierarchy;
  "speedo does not match scene aesthetic".
- **Fix (`hud.tscn` + `race_ui.gd`):** add a translucent `ColorRect` panel behind
  the cluster (dark `#0B0E14` at ~0.55 alpha) to lift contrast; set typeface
  weight/color hierarchy (white body, cyan accent); align `%SpeedOverlay`
  vignette with speed (already S9). Cheap, high-perception value.

### 8. [QUICK WIN / perf-safe] MSAA + scaling per preset
- **Ref:** GT7/PS5 Pro (usable) and all FH6 frames are anti-aliased (smooth
  car silhouettes, no jaggies).
- **Now:** Low = `msaa_3d 0`, Medium = `2`, High = `0` (with FSR2 0.9). Captures
  show aliased geometry.
- **Fix:** set per-preset `msaa_3d = MSAA_4X` at Low (MSAA is cheap on this
  content amount), keep High at FSR 2 Quality; assert 60fps via `test_perf_gate`.

---

### 9. [MED] World map & terrain presentation (pause map) — add elevations, biomes, hydro
- **Ref:** FH6 `fh6_map.webp` (satellite world map: real green-forest / brown-terrain / blue-water regions + POI icons + dense road network); FH6 `terrian.jfif` (photoreal gradient mountains, dense foliage, water, dynamic snow-vs-shade lighting).
- **Now:** UltraDrive `captures/map.PNG` — minimalistic top-down map showing ONLY the track routes; no elevation/hydro/biome/terrain read; muted dark grey + light-blue route lines; a faint circular blur artifact at map center (likely the `clip_circle` circular clip rendering leaking into the pause map).
- **Fix (`world_map.gd` + `map_roads.gd` — GDScript + shader only, no assets):**
  - Bake a discrete tint layer from the existing `Terrain3D` heighfield: blue below `water_level` (~0), green for vegetated bands, brown for alpine/rock above the highland clamp — sampled per-pixel in a shader from a low-res height/color bake (512²), composited under the route polyline. Matches FH6's region reading.
  - Draw elevation contour hints (subtle line overlay) using the same bake — cheap in `_draw`.
  - Add water-body tint + a soft hillshade (derivative of height) so mountains read (FH6 `terrian.jfif` gradient relief).
  - Fix the pause-map circular blur: reproduce in the minimap path (`clip_circle`, `world_to_screen`) — route the pause map through `MapRoads.compute_fit` so the clip step isn't double-applied; add a regression assertion to the map test.
  - POI icons: keep, but restyle to FH6's small glyph + outline style; per-zone color.
- **Effort:** Medium. Depends on height bake already present (Terrain3D `data.get_height`, region grid). Sub-agent gate: `test_world_map_terrain`.
1. `git status --short` → no `*.uid`.
2. Headless import probe:
   `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import .` → expect
   ZERO `SCRIPT ERROR` / `Parse Error` / `Failed to load`.
3. For behavior changes (presets, materials, camera toggles): run target
   suites (`test_drive_feel`, `test_chase_camera`, ``test_perf_gate` if/when it
   ships) then FULL suite:
   `... --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
   → expect `Overall Summary: ≥400 | 0 errors | 0 failures | 0 flaky`.
4. Present a reference frame + UltraDrive frame side-by-side in the plan report
   and verify each numbered item closes.

## Suggested execution
Run as sub-agents per domain with the standard playbook (see
`docs/plans/match_fh6_gt7_plan.md` playbook): sky/atmosphere first (biggest
ROI), then camera + HUD, materials, then ladder + AO/GI at High. Each with its
own gate suite, parent re-verifies headless.