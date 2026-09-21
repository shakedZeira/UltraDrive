# Open World Optimization Plan

Target rig: **GeForce GTX 970** (Maxwell, 3.5 GB VRAM, Vulkan, no RT cores),
1920x1080, **Forward+**, Jolt, Terrain3D, Godot **4.7.2**.
Related: `docs/ROADMAP.md` ("No tech ceiling" — ambitions are not trimmed to
current hardware, but *playable framerate on the reference box* is a gate).

---

## §1 STATUS (measured, not estimated)

### Instrumentation

`tools/perf_probe.gd` + `tools/perf_probe.tscn` (temporary harness). Instantiates
`res://scenes/world/open_world_root.tscn` as a child, disables vsync, drives the
player at full throttle via `car.set_input_override(...)`, samples
`Performance.get_monitor(...)`, prints a summary, then quits.

```
"D:\Godot\Godot_v4.7.2-stable_win64.exe" --path . res://tools/perf_probe.tscn
```

Toggle one variable per run; the 8-phase A/B build is the reference methodology.

### Baseline (pre-fix) vs Current (post quick-fixes)

| Metric | Baseline | Current | Delta |
|---|---|---|---|
| FPS avg (min-max) | **7.7** (6-9) | **18.7** (8-28) | **+2.4x** |
| frame_ms | 129.3 | 53.5 | -59% |
| process_ms | 22.59 | 24.4 | ~ |
| physics_ms | 23.42 | 22.9 | ~ |
| draw_calls | 724 | 711 | ~ |
| primitives | 1,085,617 | 987,625 | -9% |
| VRAM | 787 MB | 788 MB | ~ |

**Verdict: a TWO-FRONT problem, not just GPU-bound.**

- **GPU front:** frame_ms (53.5-89.6 across runs) >> CPU. Draw calls are low
  (~711) so this is **primitive + fill + shadow** cost, not batching. 987k
  primitives/frame at 1080p Forward+ on a Maxwell GTX 970.
- **CPU front:** process_ms 24.8 + physics_ms 23.0 = **47.8 ms** on the latest
  run. **That alone caps the game at ~21 FPS no matter what the GPU does.**
  Hitting the 60 FPS target (16.6 ms) needs the CPU under 16.6 ms — a **~3x CPU
  cut** — on top of the GPU work.

So the acceptance target cannot be met by rendering work alone. Both fronts are
in scope, and the CPU front is the harder one (physics 23 ms for ~16 rigid
bodies + terrain collision; process 24.8 ms in streaming/foliage/traffic).

**Run-to-run variance is high** (18.7 -> 11.2 FPS on identical config; per-run
min-max 8-28). Treat any delta below ~10% as noise; report min/avg together and
prefer several runs before claiming a win.

### Phase A/B results (one variable each)

| Phase | FPS (run 1 / run 2) | Note |
|---|---|---|
| baseline | 8.5 / 8.0 | probe re-applies pre-fix values |
| **physics_60hz** | **17.9 / 22.1** | **dominant win** (+2.1-2.7x) |
| msaa_off | 8.7 / 8.0 | +2% |
| shadows_60m | 8.5 / 8.3 | ~ |
| shadows_off | 8.6 / 8.4 | ~ (max_distance alone is not the cost) |
| traffic_off | 8.9 / 8.5 | +5% |
| colormap_off | 8.5 / 8.8 | prims 988k -> 732k |
| combo_low | 29.5 / 12.1 | second run = proc 86.6 ms artifact |

Interpretation: the physics tick halving was the single biggest win because the
probe drives at full throttle and 120 Hz physics dominated the frame. Shadow
*tuning* barely moved FPS in the probe (a static probe scene under-samples the
shadow cost that a moving camera sees) — do **not** conclude shadows are cheap;
the research ranks them the #1 safe GPU win. Re-measure with a driving camera.

### Quick fixes already applied (keep)

| File | Change |
|---|---|
| `project.godot:111` | `physics_ticks_per_second` 120 -> **60** |
| `project.godot:119` | `msaa_3d` 2 -> **0** |
| `scenes/world/open_world_root.tscn:83` | `show_colormap` true -> **false** |
| `scenes/world/open_world_root.tscn:120` | `directional_shadow_max_distance` 220 -> **60.0** |
| `scripts/world/traffic_spawner.gd:8` | `max_traffic` 15 -> **5** |

### Test status after the above

`533 test cases | 0 errors | 1 failure | 0 flaky | 0 skipped | 18 orphans`.
The 1 failure is `tests/suites/test_race_loop.gd::test_total_time_is_relative_to_race_start`
— a timer-sensitive flake (asserts elapsed > 0.04 s after `await_millis(250)`),
unrelated to rendering. Re-run to confirm; if it persists, widen the tolerance.

---

## §2 KNOWN LANDMINES (fix alongside, not after)

1. **Low preset is not actually low — DISPUTED, de-prioritised.** `settings_menu.gd:27`
   sets `"msaa_3d": 2` (**4x MSAA**) on preset 0 — the preset
   `default_quality_preset()` picks for this GTX 970. **But this is deliberate
   and test-enforced:** `tests/suites/test_quality_ladder.gd:27` asserts Low
   `msaa_3d >= 2`, `:112` asserts `MSAA_4X`, and `test_settings_presets.gd:51`
   carries the comment *"msaa_3d==0 passthrough assertion was updated
   deliberately to match"*. The intent is "Low has no AO/GI, so spend the
   savings on MSAA to kill aliasing".
   **Our own probe measured this at only +2%** (`msaa_off` 8.5 -> 8.7), so it is
   NOT the win an earlier draft of this plan claimed. **Leave Low's MSAA alone
   unless a driving-camera re-measure shows it matters** — changing it means
   rewriting three deliberate assertions for a ~2% gain.
2. **Medium (`:39`) is `msaa_3d: 2` + `sdfgi_enabled: true`.** SDFGI is the most
   expensive GI option in Forward+ and is largely invisible for a distance-racing
   game; it belongs on High only. Medium's SDFGI is a *legitimate* target
   (`test_settings_presets.gd:63` asserts it, so that test needs updating too).
   Lower value than the shadow/visibility work below — SDFGI only costs when it
   is on, and Medium is not the auto-selected preset for this GPU.
3. **Terrain shadow casting.** `open_world_root.tscn:80` Terrain3D sets
   `collision_mode = 3` but leaves `cast_shadows` at its default. The real
   property is **`cast_shadows`** (plural), type
   `RenderingServer.ShadowCastingSetting`, default `1` (ON) — *not*
   `cast_shadow`. The terrain is the largest single mesh in the scene;
   shadow-casting the whole clipmap is a fill-rate multiplier per split.
   Also available on Terrain3D: `collision_radius` (default `64`),
   `cull_margin` (`0.0`), `gi_mode`, `mesh_lods` (`7`), `mesh_size` (`48`).
4. **Sun has no explicit split count or atlas size.** `open_world_root.tscn:113`
   overrides `shadow_filter`/`max_distance` but leaves `directional_shadow_mode`
   at the 4-split default and `shadow_size` at the project default (4096).
   Per the docs, an object that lands in all splits is **rendered 5x** (4
   shadow passes + 1 view) — halving splits and atlas size is a large, cheap win.

---

## §3 EXECUTION CONTRACT

- **USE A SUB-AGENT PER SMALL TASK.** Each task below is sized to be handed to
  one sub-agent (a single phase, or one lettered sub-step of a phase). The
  sub-agent gets: the phase text, the exact file:line targets, the gate command,
  and the constraint that it must not touch anything outside its phase. The
  parent session then re-verifies (`git status --short` -> import probe -> gdUnit
  -> `Overall Summary:`) and runs the probe for the before/after number.
- **Sub-agents run strictly SEQUENTIALLY.** Concurrent Godot on one project
  collides on `.godot/`. Never dispatch two at once.
- One change (or one tightly-related group) per phase. **Measure after every
  phase** with `tools/perf_probe.gd`; record before/after in the §5 table.
- A phase is only "done" when: (a) the probe shows a measured FPS/frame_ms
  improvement or a neutral result with a documented reason, (b) the headless
  import probe shows zero `SCRIPT ERROR`/`Parse Error`, (c) the gdUnit suite is
  green (modulo the known race-loop flake).
- **If a task requires editing a test that asserts the current behaviour, that
  is a red flag** — stop and confirm the design change is intended before
  rewriting the assertion (see the disputed Low-MSAA item in §2).
- Ordered **cheapest-first by effort/impact**. Do not skip ahead to architecture
  work before the free wins are banked.
- Keep the probe until the target is hit, then delete `tools/` and the stray
  `_gdunit*.txt` logs.
- Acceptance: **>= 60 FPS (frame_ms <= 16.6) at 1080p Low on the GTX 970**, and
  >= 30 FPS on Medium.

### Measured-wins reality check (do not re-litigate)

The probe's single-variable deltas were **all small except physics**: msaa_off
+2%, shadows_off +1%, traffic_off +5%, colormap_off +3.5%, physics_60hz **+110%**.
That means the scene is broadly **GPU-saturated by the terrain + foliage draw
itself**, and the levers that matter are the ones that *remove geometry*
(visibility ranges, clipmap tuning, mesh LOD) — not the toggles. It also means
the probe **under-samples shadow cost** (static-ish camera, no long view down the
road); Phase 1 must be validated with a driving view, not just the probe average.

### Recommended first task (reordered from the phase list)

**Phase 1 — Shadows** is the first task: it is config-only (no code logic), it is
the #1 win in the Godot docs, and it also *removes* shadow-pass geometry (terrain
+ trees + props currently all cast into every split). Phase 0 is deferred behind
it because its measured value is ~2% and it would rewrite deliberate assertions.

### Per-phase verification commands

```bat
rem (1) import / parse gate
"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import . 2>&1 | findstr /i "SCRIPT ERROR Parse Error Failed to load"

rem (2) suite (run AFTER step 1; flag must come AFTER the tool-script path)
"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1
findstr /c:"Overall Summary:" _gdunit.txt
```

---

## §4 PHASES

### Phase 0 — Fix the quality ladder (free, do first)

`scripts/ui/settings_menu.gd`:
- Low (`:20`): `msaa_3d` 2 -> **0**; keep SSAO/SDFGI/SSR/glow/fog off.
- Medium (`:33`): `msaa_3d` 2 -> **0**; `sdfgi_enabled` true -> **false**.
- Add shadow + scaling keys to the presets so the ladder owns them (see Phase 1-3):
  `directional_shadow_size` (Low 1024 / Med 2048 / High 4096),
  `directional_shadow_mode` (Low 1 split / Med 2 / High 4),
  `scaling_3d_mode`/`scaling_3d_scale` (Low FSR1 1.0, Med FSR1 0.9, High FSR1 0.9).
- `apply_to_scene_tree()` (`:140`) must apply them: iterate the
  `"sun"` group and set `shadow_enabled`, `directional_shadow_max_distance`,
  `directional_shadow_mode`, `shadow_blur`, and set
  `RenderingServer.directional_shadow_atlas_set_size()` /
  `Viewport.scaling_3d_mode`/`scaling_3d_scale`.
- Keep `default_quality_preset()` behaviour (GTX 970 -> Low) but now Low is
  genuinely cheap.
- Add a suite test asserting Low is `msaa_3d == 0` and has no SDFGI/SSR.

Gate: existing graphics support-ladder tests still pass (the 3 tests noted in
AGENTS.md) + the new assertion.

### Phase 1 — Shadows (highest safe GPU win)

Source: "Objects that cast shadows are rendered **once per split plus once for
the camera**" — `optimizing_3d_performance` / `lights_and_shadows`.

- `project.godot` `[rendering]`: add
  `lights_and_shadows/directional_shadow/size=2048` and
  `lights_and_shadows/directional_shadow/soft_shadow_filter_quality` reduced one
  step. (Low preset may drop to 1024 at runtime.)
- `scenes/world/open_world_root.tscn:113` Sun: set
  `directional_shadow_mode = 1` (**1 split**) or 2 for Low/Medium, keep
  `shadow_filter` softness only if it stays affordable.
- Terrain3D (`:80`): set `cast_shadows = 0`
  (`RenderingServer.SHADOW_CASTING_SETTING_OFF`) — terrain does not need to
  cast into its own shadow map at racing distance. Verify the horizon still
  reads correctly; if terrain shadows are visually required, keep them only on
  Medium/High.
- Foliage (`scripts/world/foliage.gd`): grass is **already** shadow-free
  (`:181` `SHADOW_CASTING_SETTING_OFF` — verified). **Trees are not**: the three
  `TreesMMI*` batches (`:229-234`) never set `cast_shadow`, so they default ON
  and render into *every* split (40/region x 9 regions = 360 shadow-casting
  instances). Give them a `visibility_range_end` (Phase 2) and/or
  `cast_shadow = OFF` on Low.
- Props (`scripts/world/prop_scatterer.gd`): sets **no** `cast_shadow`,
  `gi_mode`, or `visibility_range` at all — every guardrail/tent/pole/rock
  casts shadows and is never distance-culled. Same treatment as trees.

Gate: probe FPS up; visual check (capture) that shadows still ground the car.

### Phase 2 — Distance culling / visibility ranges — **RESOLVED: REDUNDANT, REVERTED**

**Do not implement this.** Measured 2026-09-21: adding `visibility_range_end` to
trees/props changed primitives by -0.4% (noise) and was reverted.

The premise ("props currently have no culling") was false.
`region_dresser.gd:276-282` `_apply_band_budget()` already distance-culls both
`PropScatterer` and `Foliage` via `set_visible_instance_count()`, using
`band_visibility()` (`:268`) per live/prefetch band. The band system is the
existing single source of truth for dressing culling.

Worse, per-node `visibility_range_end` is *coarser* than the band system — it
culls a whole MultiMesh based on its node origin, so a 400 m range could pop an
entire region's trees simultaneously.

**Rule going forward:** before adding any new culling, read
`scripts/world/region_dresser.gd` first.

### Phase 3 — Resolution scaling (Forward+ knob)

Source: `optimizing_3d_performance` -> `scaling_3d_mode`.
- Low: `scaling_3d_mode = FSR1` with `scaling_3d_scale = 1.0` (no-op today;
  make it 0.85 if needed) — **FSR1, not FSR2/TSR**: FSR2 needs motion vectors +
  TAA and is explicitly costly on Maxwell, and we ship MSAA off.
- This is the emergency lever: it buys FPS on *any* GPU without touching content.
  Use it only after Phase 1-2, since it softens the image.

Gate: probe FPS up; capture check for acceptable softness.

### Phase 4 — Terrain3D clipmap tuning

Source: `https://terrain3d.readthedocs.io/en/latest/api/class_terrain3d.html`.
- **Verified defaults** (Terrain3D 1.1.0-dev, from the class reference):
  `mesh_lods = 7`, `mesh_size = 48`, `collision_radius = 64`,
  `collision_mode` default `1`, `cast_shadows = 1`, `gi_mode = 1`,
  `cull_margin = 0.0`. The scene overrides only `collision_mode = 3`.
- `mesh_lods` / `mesh_size`: the addon already LODs, so **reduce** rather than
  add — fewer LOD levels, and a smaller `mesh_size` keeps lod0 dense near the
  camera while far rings coarsen faster.
- `collision_mode` — **CORRECTION (verified against the Terrain3DCollision
  docs, 2026-09-21).** The enum is:
  `0 DISABLED`, `1 DYNAMIC_GAME` (shapes generated around the camera as it
  moves; "very fast, can be updated at 60fps for little cost"),
  `2 DYNAMIC_EDITOR`, `3 FULL_GAME` (one shape per region, all regions),
  `4 FULL_EDITOR`. The scene and seeder use **`3` = FULL_GAME**, *not* "Dynamic"
  as an earlier draft of this plan said. Gemini's advice ("collision only in a
  local radius around the player") is literally mode **`1` DYNAMIC_GAME** +
  `collision_radius` (64) + `collision_target` = the car.
  **But do not switch blindly:** the open world never has an 8x8 km collision
  field — the seeder only ever keeps `RING_RADIUS := 1` (9 x 1024 m regions)
  live, so FULL_GAME is bounded to ~9 shapes, and a per-region trimesh is
  *smoother* under the suspension raycasts than DYNAMIC's `shape_size` (16)
  box grid. Treat this as a **measure-both** item, not a free win.
- `collision_radius` (64) / `collision_shape_size` (16): only used in DYNAMIC
  modes — irrelevant unless the mode changes.
- `gi_mode = 1` (`GI_MODE_STATIC`): if we ever enable SDFGI this feeds it; with
  SDFGI off (Phase 0) it is dead weight — set `GI_MODE_DISABLED`.

Gate: probe FPS up; no holes in the terrain under the car; streaming suite green.

### Phase 5 — Mesh LOD for props/trees

Source: `3d/mesh_lod`.
- Import meshes with LOD generation enabled, or `Mesh.add_lod()`; set
  `Mesh.lod_error` (Low 0.5-1.0, Med/High lower) and
  `GeometryInstance3D.lod_bias` per preset.
- **MultiMesh caveat:** a MultiMesh draws one mesh, so per-instance LOD needs
  separate MultiMeshes per LOD band (which `TREE_MODELS`/`TREE_MODEL_COUNTS` in
  `foliage.gd` already gives us a seam for).

Gate: probe FPS up; capture check for popping.

### Phase 6 — CPU headroom (only after GPU is fixed)

At 18.7 FPS, process 24.4 + physics 22.9 ≈ 47 ms. Once GPU drops below that,
CPU becomes the wall.
- Physics: `max_traffic=5` is already down from 15; consider physics-culling
  distant traffic, and `Jolt` shape simplification (box/convex instead of trimesh
  where possible).
- Process: `traffic_spawner.update()`, `terrain_seeder._process()` drain budget
  (<= 2 regions/frame) and `region_dresser` budgeting are the hot spots — profile
  with the probe's `TIME_PROCESS` monitor before changing anything.

### Phase 7 — Occlusion culling (probably skip)

Source: `3d/occlusion_culling`. Open-world terrain is largely convex/visible, so
occluder baking rarely pays for itself here. Only revisit if a specific dense
area (e.g. the mountain-pass corridor) shows up as the outlier in the probe.

---

## §5 MEASUREMENT LOG (fill in as phases land)

| After phase | FPS avg | frame_ms | prims | draws | notes |
|---|---|---|---|---|---|
| (baseline) | 7.7 | 129.3 | 1,085,617 | 724 | pre-fix |
| quick fixes | 18.7 | 53.5 | 987,625 | 711 | physics 60 + msaa off + traffic 5 |
| before Phase 1 | 11.2 | 89.6 | 987,851 | 713 | re-measure, same config (noise: 18.7 -> 11.2) |
| **Phase 1** | **15.6** | **64.3** | **617,636** | **621** | shadows: 2 splits + atlas 2048 + terrain `cast_shadows=0` |
| Phase 2 | 10.7 | 93.5 | 615,062 | 619 | **NO-OP — REVERTED** (redundant with `RegionDresser`) |
| Phase 0 | | | | | DEFERRED (~2% measured, would rewrite deliberate tests) |
| Phase 3 | | | | | scaling |
| Phase 4 | | | | | terrain clipmap |
| Phase 5 | | | | | mesh LOD |
| Phase 6 | | | | | CPU |

**Phase 2 analysis — the plan's premise was WRONG.** `visibility_range_end` on
the tree/prop MultiMeshes changed primitives by **-0.4% (noise)**. Reason:
`region_dresser.gd:276-282` `_apply_band_budget()` **already** distance-culls both
props and foliage via `set_visible_instance_count()` on the live vs prefetch band
(`band_visibility()`, `:268`). Adding per-node `visibility_range_end` was
redundant, and worse, it is *coarser* — it culls a whole MultiMesh by node origin,
so a 400 m range could pop an entire region's trees at once. **Reverted**
(`git checkout` on `foliage.gd` + `prop_scatterer.gd`). Lesson: check
`region_dresser.gd` before adding any new culling; the band system is the
existing single source of truth.

**Phase 1 analysis:** primitives **-37%** (-370k), draws -13%, VRAM -24 MB, FPS
+39%, frame_ms -28%. The 370k drop confirms the docs' claim that shadow-pass
geometry dominates — the terrain alone was casting into 4 splits. CPU
(process 24.5 / physics 22.6) is **unchanged**, exactly as expected: this was a
GPU-side change. Caveat: run-to-run variance is high (this run min-max 9-29), so
treat +39% as "clearly positive" rather than precise.

---

## §6 SOURCES

- Godot 4.7 docs — Optimizing 3D performance:
  `https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html`
- Mesh LOD: `https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html`
- Visibility ranges: `https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html`
- Occlusion culling: `https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html`
- Using MultiMesh: `https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html`
- Pipeline compilations (stutter, not steady-state): `https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html`
- Terrain3D docs: `https://terrain3d.readthedocs.io/en/latest/`
- Terrain3D class reference (verified property names/defaults):
  `https://terrain3d.readthedocs.io/en/latest/api/class_terrain3d.html`

---

## §7 RISKS

- The probe under-samples shadow cost (static scene); Phase 1 must be validated
  with a **driving** camera, not just the probe average.
- Visibility ranges / LOD can pop visibly at speed — always capture-check.
- `RegionDresser` budget tests assert summed instance counts; visibility-range
  changes must not alter the totals those tests read.
- Resolution scaling (Phase 3) is a crutch: if 60 FPS is only reached with
  FSR1 < 1.0, the content pipeline (Phases 1-2, 4-5) is still unfinished.
- Low-end acceptance is defined on the GTX 970; do not tune the whole ladder to
  it. High must remain the reference look.

---

## §8 GEMINI COVERAGE LEDGER (validated 2026-09-21)

Both Gemini prompts audited against the repo. **Prompt 2 (visual) is NOT this
plan's scope** — it lives in `gemini_visual_overhaul_plan.md` (§1-§6 + the 9-item
R-* playbook). This plan owns the *perf* half.

### Gemini prompt 1 — physics/architecture

| # | Gemini item | Verdict | Evidence |
|---|---|---|---|
| 1 | Ditch `VehicleBody3D` for a raycast "hovercar" | **DONE** | `vehicle_physics.gd:2` extends `RigidBody3D`; 4x `WheelPhysics` `RayCast3D` spring-damper `wheel_physics.gd:20-57`; visuals decoupled (wheel meshes follow real spin, `player_car_controller.gd:37`) |
| 2 | Upgrade to Godot Jolt | **DONE** | `project.godot:112` `3d/physics_engine="jolt"`; `addons/jolt_physics` 0.16.0 |
| 3 | Pacejka tire friction (slip-angle curve) | **DONE** | `tire_model.gd:27,48` magic formula; lateral applied `vehicle_physics.gd:232-256`; longitudinal + traction + `test_longitudinal_traction.gd` (19) |
| 4 | Square the analog trigger input | **DONE** | `ANALOG_RESPONSE_POWER 2.0` / `DEADZONE 0.02`, `vehicle_physics.gd:26-37,383`; `test_input_curves.gd` (9) |
| 5a | Terrain3D collision only in a local radius | **MITIGATED, reframed** | Collision *is* bounded — the seeder keeps only `RING_RADIUS := 1` (9 regions) live, so `FULL_GAME` = ~9 shapes, not an 8x8 km field. Literal Gemini advice = mode `1 DYNAMIC_GAME`; see Phase 4 for the measure-both note (trimesh accuracy vs box grid) |
| 5b | Road mesh must not float above terrain collision (suspension hitch) | **ALREADY SOLVED — keep as an invariant** | `track_builder.gd:96` builds road collision from the **exact same vertices** as the visual mesh (watertight, gapless, winding flipped for Jolt); `mountain_pass.gd:198` carves the terrain washbed to `road_elevation - WASHBED_DEPTH` (0.6 m) so terrain collision can never poke through the asphalt |

**Regression guards for 5b (do not break these):**
- Never offset the visual road mesh independently of `coll_mesh` — both come from
  `_build_mesh(points, <flag>, closed, width, banking)`; any new `road_height`
  (+0.1) lift must be applied to *both*.
- Never raise `WASHBED_DEPTH` toward 0 (terrain would breach the asphalt) and
  never let a road be added without `set_roads()` before the first height push
  (the bake must conform before the car spawns).
- `track_phys_mat.friction = 0.0` is deliberate — all friction comes from the
  Pacejka model. Do not "fix" it.

### Gemini prompt 2 — visual overhaul

Fully covered by `gemini_visual_overhaul_plan.md`: §1 rendering/env (SSAO/SSR/
glow/CSM shipped; sky cubemap, TAA, DoF as gaps 1a-1c), §2 terrain/vegetation
(2a-2c), §3 roads/props (3a asphalt PBR, 3b parked vehicles + wires), §4 vehicle
(4a hero car via rodin with zero-physics-delta gate, 4b materials), §5 HUD (5a
minimap compass, 5b dial reskin), §6 VFX (6a dirt kick-up, 6b motion blur).

**Deliberate divergences (not gaps — documented and justified):**
- **Volumetric cloud skybox** (Gemini §1) → Godot 4 has no built-in volumetric
  clouds; substituted with a CC0 HEQTL/Panorama sky cubemap (visual plan 1a).
- **Lumen/RT reflections, Nanite-class geometry** → hardware-budget no on the
  GTX 970 (no RT cores, 3.5 GB VRAM); recorded in the visual plan's tech-stack
  verdict §3.
- **TAA** → to be verified for 4.7.2 Forward+; High preset only if present.
- **Per-pixel motion blur** (Gemini §6) → no engine built-in; deferred to a
  screen-space post shader, High-only and perf-gated (visual plan 6b).

**Only un-covered sub-item found:** Gemini §4 mentions "detailed rubber on the
tires, detailed brake calipers". Brake calipers/glow are covered
(`car_visuals.apply_brake_glow`); a dedicated tire-rubber material pass is not
listed. Cosmetic, fold into R-HERO-1.
