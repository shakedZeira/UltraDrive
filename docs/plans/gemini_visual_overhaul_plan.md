# Gemini Visual Overhaul + Tech-Stack Plan — UltraDrive vs AAA Photorealism

Generated 2026-09-21. Source: Gemini feedback ("OpenCode Visual Overhaul Prompt…"
+ "any tech stack changes recommended?") evaluated against the **current** repo
state (verified by this session's audit), NOT against the March prototype
Gemini was shown. Every "Already done" below was confirmed with file:line.

Read together with `graphics_gap_plan.md` (its 9 ranked items have shipped via
GG-Env/GG-Paint/GG-HUD/GG-Map/GG-Ladder) — this plan is the *photorealism layer*
above that ladder, plus the tech-stack verdict.

---

## Baseline truth (what Gemini's screenshots did NOT show)

Gemini judged `image_0.png` = the old prototype. The live repo since then:

| Gemini claim | Reality (verified) |
|---|---|
| "default physics / VehicleBody3D" | Custom raycast controller since D-era — `vehicle_physics.gd:2` extends `RigidBody3D`, 4× `WheelPhysics` RayCast3D spring-damper `wheel_physics.gd:20-57` |
| "upgrade to Jolt" | **Already default** — `project.godot:112` `3d/physics_engine="jolt"`, gdextension 0.16.0 enabled `project.godot:124` |
| "implement Pacejka" | Magic formula live — `tire_model.gd:27,48`; lateral applied at `vehicle_physics.gd:232-256`; **longitudinal + traction just wired + 19 tests (546 green)** |
| "square the triggers for feathering" | **Just shipped** — `ANALOG_RESPONSE_POWER 2.0`/`DEADZONE 0.02` on player-only path `vehicle_physics.gd:26-37,383` + `test_input_curves.gd` (527→546) |
| "flat render, no AO/GI/SSR" | Quality ladder ships SSAO/SDFGI/glow at Medium+, SSR+volumetric at High (`settings_menu.gd:22-66`); GG-Env presets sunrise/haze; GG-Paint clearcoat paint |

So the **core friction rodeo is closed**. What's genuinely open is the ART layer
+ a few render/VFX features, and every one of them collides with one fact:

> **Dev/play rig = GTX 970 (Maxwell, 3.5 GB VRAM, Vulkan 1.3, no RT cores).**
> FH6/GT7-grade photoreal (Lumen/Nanite/RT reflections/16–64 GB VRAM) **cannot
> run on this GPU regardless of engine**. ROADMAP "No tech ceiling" rule 2 sees
> through this: it is a *hardware budget* call, not a Godot capability call. We
> aim for "best Godot look that still holds 60fps on the 970"; the fidelity
> ladder above High is post-launch / better-hardware territory.

---

## Ledger: Gemini items → verdict

### 1. Global rendering & environment — MOSTLY DONE, small gaps
- DirectionalLight + CSM + tonemap + glow + SSR + SSAO + volumetric: shipped by
  GG-Env + GG-Ladder. Verified `scripts/ui/settings_menu.gd:22-66,146-161`.
- **Gap 1a — sky:** `ProceduralSkyMaterial` (GG-Env) is a gradient + sun disc, no
  clouds. Godot 4 has **no built-in volumetric cloud system** — the honest path
  is a photorealistic **HEQTL/equirect cubemap sky** (Poly Haven CC0, e.g.
  "kloppenheim" / "rosendal_plains") fed into `PanoramaSkyMaterial`. Swap per
  scene, keep GG-Env exposure/sun matching by `sky_energy`. THE single biggest
  "prototype→real" pixel change, zero perf cost (it's one texture sample).
- **Gap 1b — TAA:** verify availability on 4.7 Forward+ (`Viewport` TAA / project
  `rendering/anti_aliasing`). If present, plug to High+ only (970 perf); keep
  MSAA Low/Medium (already `msaa_3d 2` = 4×).
- **Gap 1c — DoF:** `Environment.dof_blur_far/near` is built-in and cheap at
  distance; enable far DoF at High + camera near-DoF ONLY in photo mode (never
  chase-race). Perf-gated.
- **Out of scope (firm):** volumetric clouds (no engine support, C++ addon needed
  — deferred), Lumen-style GI (would need a better GPU).

### 2. Terrain & vegetation — PARTIAL, driven by existing GLB assets
- Trees/rocks were primitives → **now real GLBs** (`assets/trees/tree_{a,b,c}.glb`,
  `assets/rocks/rock_a.glb`, just committed). `foliage.gd`/`prop_scatterer.gd`
  already instance them per region.
- **Gap 2a — ground texture:** Terrain3D albedo is a flat/placeholder set. Feed
  `terrain_baker.gd`/`TerrainSeeder` texture layers a CC0 PBR ground atlas
  (grass/soil/gravel/alpine) instead of flat color; verify the D5 height/color
  bake path (`data.import_images` → new color layers, same region_anchor rules).
- **Gap 2b — rolling hills + far mountains:** `terrain_baker.gd` has an alpine
  dome + 3-octave fBm; increase mid-band amplitude + add a cheap distant
  "background" mountain ring **mesh** (not terrain) so the horizon reads like the
  reference. Must keep worldgen **deterministic** (region-anchor + hash — ROADMAP
  cross-cutting).
- **Gap 2c — grass/gravel detail:** grass MultiMesh exists (700/region); lift with
  a CC0 grass *texture* on the ground layer + increase density only with the
  perf budget (`test_streaming_dressing` sums all MultiMesh children — keep the
  `visible_instance_count` culling).

### 3. Roads & props — PARTIAL
- Roads are procedural `StandardMaterial3D` albedo color + noise roughness
  (`track_builder.gd:104-117`). **Gap 3a — asphalt PBR:** add a CC0 asphalt
  albedo + normal + roughness texture atlas to `_surface_material` (same code
  path, just texture-backed), keep the tintable edge lanes + road-line mesh.
- **Gap 3b — roadside dressing:** guardrails/tents/power-poles already exist in
  `prop_scatterer.gd`; the missing beats are **parked vehicles** (covered box
  truck / parked CC0 cars on pull-offs) and utility **wires** (a low-poly cable
  between near poles). New dressing family in `region_dresser.gd` with a
  `configure_for_region` hook.
- Power-poles/tents guardrails: keep — they read read correctly against the
  richer ground.

### 4. Vehicle model + materials — PARTIAL (the "yellow F1" is gone)
- The prototype's stylized F1 was replaced long ago; roster = SportsCoupe/
  MuscleCar/RallyHatch GLBs + CC0 Kenney kit, all with GT7-style clearcoat paint
  (`car_visuals.gd:20-30,317-369`) + brake-glow (`apply_brake_glow`).
- **Gap 4a — hero car mesh:** generate ONE high-detail sports car GLB via the
  Hyper3D `rodin` pipeline (the known-good PNG→silhouette→model flow), then
  **transfer the mesh onto the existing chassis** — constraint: preserve
  `WheelFL/FR/RL/RR` attachment nodes, `CarBody` swap node, `CAR_ORIENT`
  (180° Y), wheel-spin conventions (`car_visuals.gd:108-170`). GDUnit gate must
  prove zero physics delta (same `${car_id}` → identical drive numbers).
- **Gap 4b — hero interior/glass:** dab of SSR-friendly gloss + tinted glass
  already there; optionally add carbon accents on the hero car. Cheap material
  pass only (no new mesh needed).

### 5. Photoreal HUD — PARTIAL, one strong add
- GG-HUD already ships dark contrast pill + cyan accents; cluster/tach in
  `scenes/ui/hud.tscn` (`%Cluster`), minimap exists (`minimap.gd` via
  `map_roads.gd`).
- **Gap 5a — minimap compass + reposition:** add the Forza-style **"N" compass
  arrow** rotating with heading (we already draw a player chevron via
  `marker_style()` for P5) and move minimap lower-left, semi-transparent.
- **Gap 5b — dial re-skin:** evolve `tachometer.gd`/`%Cluster` toward the hybrid
  digital-analog dial (lower-right, translucent). CSS-free restyle of the
  existing gauge, no architecture change.
- **Gap 5c — HUD photos only:** non-obtrusive (radio/campaign) is out of scope —
  no in-world HUD screens (perf + scope on 970).

### 6. VFX + dynamic realism — SMALL, one medium feature
- Tire smoke/drift + skid marks exist (`vehicle_fx.gd`, `tire_marks.gd` — S9).
- **Gap 6a — kick-up dirt/gravel off-road:** extend `vehicle_fx.gd` with a
  cheap `GPUParticles3D` dirt burst when `SurfaceRegistry` disagrees with
  ASPHALT and speed > threshold. Small, gated by `test_drive_feel`.
- **Gap 6b — motion blur (the real medium one):** Godot 4 has **no built-in
  camera motion blur**; the honest route is a full-screen post shader sampling
  `hint_screen_texture` + velocity texture (screen-space, Forward+). Medium
  effort, High preset only, perf-gated on 970. If it eats >1.5ms, ship it as
  "High + motion_blur=quality" knob only.

---

## Tech-stack recommendations — verdict

### 1. "Migrate physics to C#/C++" — NOT NOW (measure-first)
- The 60 Hz loop is 4 raycasts + Pacejka per car; the CPU headroom is fine (the
  full 546-test headless suite runs in minutes; the ONE historic hot path —
  Terrain3D region baking 126s→2s — was already C++/optimized data-path, and
  suspension math was never the cost). Porting the core controller to GDExtension
  buys almost nothing today and costs the GDScript testability that gates every
  item. **Gate:** profile with the 970 GPU uncapped; if convoys (LivingWorld +
  traffic + rivals ≈ 16 cars) show per-car physics > 0.35ms sustained, revisit —
  that's the signal, not vibes.
- PS5 note: GDScript→C++ has shipping value on console budget; this is a launch
  decision, not a dev-feel decision. Write a `reports/` note if the decision
  flips.

### 2. "Finalize Godot Jolt" — ALREADY SHIPPED
`project.godot:112` + `addons/jolt_physics` 0.16.0-stable. Godot 4.4+ bundling
Jolt as a module only changes upgrade mechanics, not behavior. Nothing to do.

### 3. "Migrate to Unreal 5 (Nanite/Lumen)" — HARDWARE-BUDGET NO (this cycle)
- ROADMAP "No tech ceiling" is honored: we state the ambition (AAA photorealism)
  and the *cost dimension* is the binding filter — **the 970 cannot run Nanite/
  Lumen/RT at 60fps, on any engine**. Migrating now would lose 546 green tests +
  a deterministic worldgen franchise asset + 4 years of learnings for visuals
  this GPU can't display.
- Verdict: keep Godot Forward+; **pursue the photorealism ceiling via the plan
  above (sky cubemap + PBR terrain/roads + hero car + VFX)**. Reassess UE5 only
  if/when the target hardware tier shifts (post-launch, or an RT-capable dev
  rig). Write this decision into `docs/ROADMAP.md` Phase-3 note when convenient.

---

## Execution playbook

Standard sub-agent flow per `docs/plans/match_fh6_gt7_plan.md` playbook, each
domain with its own gate suite, **run sequentially** (concurrent Godot on one
project collides on `.godot/`). Parent re-verifies: `git status --short` (no
`*.uid`) → import probe (zero `SCRIPT ERROR`/`Parse Error`) → GDUnit `-s` run →
`Overall Summary:` gate; then a manual `capture_game_window` + `analyze_image`
pass on this rig to eyeball the 970-render before commit.

Suggested order (impact-per-effort on a 970):
1. **R-VFX-1 Sky cubemap** (biggest pixel ROI, free perf) — sub-agent +
   `test_environment_lighting`.
2. **R-ROAD-1 Asphalt PBR textures** on `track_builder._surface_material` +
   road-lines already present — `test_track_builder`.
3. **R-TER-1 CC0 ground texture layers** into the Terrain3D color bake (keep
   region-anchor determinism) — extend `test_open_world`/`test_terrain_baker`.
4. **R-HUD-1 Minimap compass + reposition** to lower-left; translucent dial
   restyle — `test_map_route`/`test_player_marker`.
5. **R-VFX-1 Dirt kick-up** off-road particles — `test_drive_feel`.
6. **R-HERO-1 Hero car mesh** via rodin, transferred onto existing chassis, zero
   physics delta gate.
7. **R-PROP-1 Parked vehicles + utility wires** dressing family.
8. **R-MB-1 Screen-space motion blur** (High-only, perf-gated) — new
   `test_motion_blur_shader` (off-by-default so headless stays green).
9. **R-TER-2 Rolling hills + far mountain ring** (deterministic).

Deferred (hardware): volumetric clouds (engine addon), RT reflections, TAA
(finalize when 4.7 verify), photo-mode near-DoF (needs photo mode from
ROADMAP quick-wins).

---

## STATUS (this plan)

- **2026-09-21** — Plan created from Gemini feedback + preceding audit. Core
  physics/input/Jolt gaps from the earlier Gemini pass already closed
  (longitudinal Pacejka + input curves; suite 518→546, all green). Items above
  are the fresh backlog; none executed yet.