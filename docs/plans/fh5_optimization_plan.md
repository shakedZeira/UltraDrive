# FH5-Inspired Optimization Plan for UltraDrive (Godot 4.7.2)

**Target hardware:** GTX 970 (Maxwell, 4GB VRAM, compute 5.2, Vulkan 1.3)  
**Engine:** Godot 4.7.2, Vulkan backend (OpenGL fallback), Forward+ renderer  
**Current bottlenecks:** Terrain sync bake ~3.3s/region, no upscaling below High  
**Baseline quality ladder:** Low / Medium / High (settings_menu.gd)  
**GDUnit suite:** ~~95 suites ~18min~~ → **206 s / 1018 tests via `tools\gdunit_parallel.py -j 4`** (5.34x). Gate any phase here with the parallel runner, not a serial `-s` run.

---

## ⚠️ API VERIFICATION PASS — 2026-10-04 (read before implementing anything below)

This plan was written as a research/reference doc, not against a verified API.
Every rendering call in it was checked against the **actual engine** this project
runs (`4.7.2-stable`, `ed1daf0bf`) with `RenderingServer.has_method()`, plus a
dump of the real `rendering/*` project settings. **Most of the `RenderingServer`
API in this document does not exist.** Left uncorrected, implementing from the
original text fails at parse time — GDUnit and the engine both treat those as hard
errors.

| Plan claimed | Reality on 4.7.2 | Correct mechanism |
|---|---|---|
| `rs.enable_fsr2()` | **false** | `Viewport.scaling_3d_mode` + `rendering/scaling_3d/mode` |
| `rs.fsr2_set_quality()` | **false** | no per-call quality; use scale/sharpness |
| `rs.fsr2_set_sharpness()` | **false** | `rendering/scaling_3d/fsr_sharpness` (default 0.2) |
| `rs.enable_taa()` | **false** | `rendering/anti_aliasing/quality/use_taa` |
| `rs.set_taa_jitter_scale()` | **false** | no equivalent exposed |
| `rs.enable_vrs()` | **false** | `rendering/vrs/mode` |
| `rs.vrs_set_combiner()` | **false** | `rendering/vrs/mode` = 1 (combine only) |
| `rs.has_feature("vrs")` | **does not compile** | takes a `Features` **enum**, not a String |
| `rs.get_video_memory_usage()` | **false** | `Performance.get_monitor(RENDER_VIDEO_MEM_USED)` |
| `FidelityFXSuperResolution2` class | **does not exist** | — |

Confirmed **real** (safe to use): `DirectionalLight3D.shadow_cascade_count` /
`shadow_max_distance` / `shadow_resolution`; `Occluder3D`; `MeshLOD` +
`GeometryInstance3D.lod_threshold`; `StandardMaterial3D.motion_vector_enabled`;
`WorkerThreadPool`; `RenderingServer.get_video_adapter_name()`.

Also stale: the FPS/VRAM/timing numbers in "Measurable Targets" predate
`7ffb524` (FSR2 on High) and are **unverified on the current tree**. Treat them
as targets to measure, not facts.

---

## Executive Summary

Forza Horizon 5 achieves 60fps on Xbox Series S (4 TFLOPS, 10GB) and scales down to GTX 1070 / RX 590 on PC through aggressive **scalability by design**: every expensive feature has a quality knob, and the renderer is built around **Forward+ clustered lighting**, **virtual texturing**, **temporal upscaling (FSR2/DLSS)**, and **GPU-driven culling**. Our GTX 970 (3.9 TFLOPS) is close to FH5's min spec (GTX 1070 = 6.5 TFLOPS), so we can borrow their *architecture* but must strip RTX/DLSS dependencies.

**Strategy:** Implement FH5's scalability knobs in Godot terms, add FSR2 upscaling (native in 4.4+), replace synchronous terrain bake with GPU compute, and introduce mesh LOD / occlusion culling. Target: **terrain sync <1.5s, 60fps @ 1080p Medium on GTX 970**.

---

## Priority Matrix (Impact × Effort)

| Feature | Impact | Effort | Phase | Godot Mapping |
|---------|--------|--------|-------|---------------|
| FSR2 upscaling | ⭐⭐⭐⭐⭐ | Low | P0 | `RenderingServer.enable_fsr2()`, quality ladder |
| Forward+ clustered lighting (already on) | ⭐⭐⭐⭐ | Done | — | Project Settings → Rendering → Method |
| Mesh LOD system (cars, props, terrain) | ⭐⭐⭐⭐ | Medium | P1 | `MeshLOD` + `GeometryInstance3D.lod_threshold` |
| Occlusion culling (Occluder3D) | ⭐⭐⭐⭐ | Medium | P1 | `Occluder3D` + `VisualInstance3D.occlusion_culling` |
| GPU terrain bake (compute shader) | ⭐⭐⭐⭐ | High | P2 | `RenderingDevice` compute pipeline |
| Virtual texturing (streaming) | ⭐⭐⭐ | High | P2 | Not native — use `Texture2DArray` + manual streaming |
| Shader permutation reduction (uber-shader) | ⭐⭐⭐ | Medium | P1 | `StandardMaterial3D` feature flags, `Shader` variants |
| CPU job system / threading | ⭐⭐⭐ | High | P2 | `WorkerThreadPool`, `Thread`, `Mutex` |
| Temporal AA + motion vectors | ⭐⭐⭐ | Medium | P1 | `RenderingServer.enable_taa()`, `MotionVector` pass |
| Variable Rate Shading (VRS) | ⭐⭐ | Low | P1 | `RenderingServer.enable_vrs()` (Vulkan 1.1+) |
| Texture compression (BC7/ASTC) | ⭐⭐⭐ | Low | P0 | Import settings → VRAM compression |
| Shadow cascade tuning | ⭐⭐⭐ | Low | P0 | `DirectionalLight3D.shadow_cascade_*` |
| Dynamic resolution scaling | ⭐⭐⭐ | Medium | P1 | Custom `Viewport` resize + FSR2 |

---

## Phase Breakdown

### P0 — Quick Wins (1–2 weeks)

###### 1. FSR2 Upscaling + Quality Ladder Integration — **ALREADY SHIPPED (2026-09-27, `7ffb524`)**
**Target:** 1080p → upscale, fps gain at High preset. **Status: DONE, and the plan's API was wrong.**

The original text called `rs.enable_fsr2()` / `rs.fsr2_set_quality()` /
`fsr2_set_sharpness()`. **None of those methods exist.** Verified against
`RenderingServer.has_method()` on this exact engine (4.7.2-stable
`ed1daf0bf`): `enable_fsr2=false`, `fsr2_set_quality=false`,
`fsr2_set_sharpness=false`, `fsr2_set_render_scale=false`. FSR2 in Godot 4 is a
**`Viewport` property + project setting**, not a `RenderingServer` call.

What actually ships, and where:
- `Viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2` — applied by
  `scripts/ui/settings_menu.gd:211` via `_scaling_mode_for()`. Note the enum is
  **2**, not 1 (`SCALING_3D_MODE_FSR2=2`, `BILINEAR=0`); the code maps its own
  preset value 1 → FSR2 and warns about exactly this.
- `Viewport.scaling_3d_scale = 0.85` on **High** only (Medium/Low stay
  bilinear 1.0), the AAA-2 lever that took High from 57 fps toward the 60 bar.
- Project settings that back it: `rendering/scaling_3d/mode`,
  `rendering/scaling_3d/scale`, `rendering/scaling_3d/fsr_sharpness`
  (default **0.2**, currently unexposed in the UI).

Remaining, genuinely open:
- Expose a **sharpness** control (`rendering/scaling_3d/fsr_sharpness`,
  0.0–1.0) — the one piece of this item never built, and it is cheap.
- Consider FSR2 on Medium once its fps is measured, not assumed.

#### 2. Texture Compression Audit
**Target:** VRAM <3GB at High, <2GB at Medium

- All 3D textures: Import → VRAM Compression = **BC7 (RGBA)** or **BC1 (RGB)** / **BC4 (R)** for masks
- Terrain splatmaps: **BC5 (RG)** for normal/height pairs
- Disable compression only for pixel-art / UI textures
- Verify with `RenderingServer.get_video_memory_usage()`

#### 3. Shadow Cascade Tuning — **OPEN, the highest-value P0 item**
**Target:** 2.5ms → <1.5ms shadow cost at Medium.

This one's API is **correct** (`DirectionalLight3D.shadow_cascade_count`,
`shadow_max_distance`, `shadow_resolution` all exist) and it is genuinely
unbuilt: `project.godot` sets only
`rendering/lights_and_shadows/directional_shadow/size = 2048` globally, and
`settings_menu.gd`'s `QUALITY_PRESETS` carries **no shadow keys at all**, so
every preset currently renders identical shadows.

Preset split to implement (from the plan):
| Preset | `shadow_cascade_count` | `shadow_max_distance` | resolution |
|---|---|---|---|
| Low | 1 | 20 m | 1024 |
| Medium | 2 | 50 m | 2048 |
| High | 4 | 100 m | 2048 |

Two gotchas, both real in this tree:
- `apply_to_scene_tree()` currently only ever receives an `Environment` and a
  `Viewport` — it never sees the `DirectionalLight3D`. Shadow tuning needs the
  light found via `find_children("*", "DirectionalLight3D")` alongside the
  existing `find_scene_environment()` walk, and `DayNightDriver` also mutates
  the sun, so the preset must survive a time-of-day update.
- Low/Medium cutting `shadow_max_distance` to 20/50 m will visibly pop shadows
  at the far plane on the open world. Expect to tune `shadow_fade_start` /
  `shadow_opacity` alongside it.

#### 4. TAA + Motion Vectors — **OPEN, but the plan's API is wrong**
**Target:** Stable 60fps image, ghosting <1 frame.

`rs.enable_taa()` / `rs.set_taa_jitter_scale()` **do not exist**
(`has_method` → false for both). The real knobs, verified present in
`project.godot` on this engine:
- `rendering/anti_aliasing/quality/use_taa` — **currently `false`**
- `rendering/anti_aliasing/quality/screen_space_aa` — currently `0` (off)
- `rendering/anti_aliasing/quality/msaa_3d` — currently `0`; the ladder
  overrides this per preset via `Viewport.msaa_3d` (Low/Med 4x, High off,
  because High uses FSR2 instead).

TAA is a **project setting**, not per-frame API, so it is a boot-time cost
decision, not something `apply_to_scene_tree` can toggle. Caveat to weigh
before shipping: TAA + FSR2 both reconstruct, and High already runs FSR2 —
stacking both on a Maxwell GPU is the highest-risk item in this phase for
image quality. Gate it behind High only and verify visually.

#### 5. Variable Rate Shading (VRS) — **OPEN, but the plan's API is wrong**
**Target:** 5–10% fragment cost reduction on GTX 970 (Vulkan 1.1+).

`rs.enable_vrs()` / `rs.vrs_set_combiner()` **do not exist**
(`has_method` → false for both), and `RenderingServer.has_feature()` takes a
`Features` **enum, not a String** — the plan's `has_feature("vrs")` does not
compile. Real keys, verified in `project.godot`:
- `rendering/vrs/mode` — currently **`0`** (disabled). `1` = combined VRS.
- `rendering/vrs/texture` — currently empty, i.e. no per-draw VRS texture, so
  only the combine mode would apply.

Note the plan's `VRS_COMBINER_MAX` maps to `rendering/vrs/mode = 1`; the
per-draw-texture item needs an actual `Texture2DRD` bound, which is the
foveated-shading follow-up and is genuinely not built.

---

### P1 — Medium Investment (3–6 weeks)

#### 6. Mesh LOD System
**Target:** 40% triangle reduction at 50m+, zero pop

| Asset Type | LOD0 (0–20m) | LOD1 (20–50m) | LOD2 (50–150m) | LOD3 (150m+) |
|------------|--------------|---------------|----------------|--------------|
| Player car | 45k tris | 18k | 6k | 1.5k (impostor) |
| AI cars | 25k | 10k | 3k | 800 |
| Props (guardrail, poles) | 2k | 800 | 200 | — |
| Terrain tiles | 1024² | 512² | 256² | 128² |

- Use `MeshLOD` resource on each `MeshInstance3D` / `MultiMesh`
- Generate LODs in Blender (decimate modifier) or via `meshoptimizer` CLI
- **Impostors** for far cars: render-to-texture billboard (Godot 4.4+ `Billboard` + `Camera3D`)

#### 7. Occlusion Culling
**Target:** 30% draw call reduction in dense areas (city, forests)

- Place `Occluder3D` boxes around buildings, terrain chunks, large props
- Enable `VisualInstance3D.occlusion_culling = true` on all static geometry
- Use `OccluderInstance3D` for dynamic objects (cars) — cheap AABB test
- **Debug:** `RenderingServer.debug_draw_occluders(true)` to visualize

#### 8. Shader Permutation Reduction (Uber-Shader)
**Target:** <50 unique shader pipelines at High (currently 100+)

- Consolidate `StandardMaterial3D` feature sets: group by (albedo_tex, normal_tex, rough_metal_tex, emission, clearcoat, anisotropy)
- Use `Shader` with `#ifdef` feature flags instead of separate materials
- **Car paint:** single shader with `CLEARCOAT`, `ANISOTROPY`, `FLIPPED` defines
- **Terrain:** single splatmap shader with `LAYER_COUNT` uniform (max 8)
- Verify with `RenderingServer.debug_shader_compilation_stats()`

#### 9. Dynamic Resolution Scaling (DRS)
**Target:** Maintain 60fps under load (rain, traffic, photo mode)

```gdscript
# In _process(delta):
var frame_ms = Time.get_ticks_msec() - frame_start
var target_ms = 16.67 # 60fps
if frame_ms > target_ms * 1.15:
    drs_scale = max(drs_scale * 0.9, 0.5)
elif frame_ms < target_ms * 0.8:
    drs_scale = min(drs_scale * 1.05, 1.0)
viewport.size = base_size * drs_scale
rs.fsr2_set_render_scale(drs_scale)
```

- Clamp: 50%–100% render scale
- Hysteresis: 2-frame cooldown between changes
- Only at Medium/High (Low uses fixed 1080p)

#### 10. CPU Threading: Terrain Bake + Prop Scattering
**Target:** 3.3s → 1.5s sync bake, async ring <16ms/frame

- Move `TerrainBaker._bake_region()` to `WorkerThreadPool` compute task
- Use `RenderingDevice` compute shader for noise + road conform (see P2)
- Keep `PropScatterer` on main thread but batch `MultiMesh` updates via `call_deferred`
- Profile with `OS.get_static_memory_usage()` and `Performance.get_monitor(Performance.TIME_FPS)`

---

### P2 — Research / Heavy Lift (6–12 weeks)

#### 11. GPU Terrain Bake (Compute Shader)
**Target:** 3.3s → 0.5s per 1024×1024 region (6–10× speedup)

**Pipeline:**
```
1. Upload region seed + road spline buffers (SSBO) to GPU
2. Compute shader: fBm noise (3 octaves) → height texture (R32F)
3. Compute shader: biome blending (4 layers) → color texture (RGBA8)
4. Compute shader: road conform — segment-splat via atomicMin on height tex
5. Compute shader: 3×3 blur (separable) → final height
6. Download height texture → Terrain3D.data.set_height_image()
```

- **Godot API:** `RenderingDevice.compute_list_add()`, `RDTextureFormat.R32_SFLOAT`, `RDTextureFormat.RGBA8_UNORM`
- **Synchronization:** `RD fence` → main thread copies to `Terrain3DData`
- **Memory:** 2× 1024² × 4B = 8MB per region (height + color), fits in 4GB VRAM
- **Fallback:** CPU path if `RD` compute not supported (unlikely on GTX 970)

#### 12. Virtual Texturing (Streaming)
**Target:** 4GB VRAM → 2GB VRAM for 50km² world, no pop-in

- Not native in Godot 4.x — implement manual **Texture2DArray streaming**:
  - Tile world into 256×256 pages (mip 0 = 1m/px)
  - `Texture2DArray` of 1024 pages (256MB at BC7)
  - CPU tracks visible pages (frustum + distance) → upload on demand
  - Shader: `texture(tex_array, vec3(uv, page_index))`
- **Alternative:** Wait for Godot 4.5+ `VirtualTexture` (experimental)
- **Interim:** Use `Texture2DArray` for terrain splatmaps only (8 layers × 1024² = 32MB)

#### 13. Surfel GI / Probe System (FH5-style indirect lighting)
**Target:** Baked-quality GI at runtime cost <2ms

- Replace SDFGI (heavy) with **Surfel GI**: render surfel buffers from probe positions
- Godot 4.4+ has `LightmapGI` + `VoxelGI` — but both are voxel-based
- **Custom:** `RenderingDevice` compute → generate surfels from `LightmapGI` bake → runtime temporal filter
- **Scope:** P2 research — may not pay off for racing game (high speed = low GI noticeability)

#### 14. Meshlet / GPU-Driven Culling (Future)
**Target:** 100k+ draw calls at 60fps

- Requires mesh shader (DX12/VulkanEXT) — **not on GTX 970**
- **Defer** to Godot 5 / Vulkan 1.3 mesh shader support
- Current: `MultiMesh` + `InstanceCount` + frustum culling is sufficient

---

## Measurable Targets

### MEASURED BASELINE — 2026-10-04 (replaces every estimated number below)

Real hardware, not a spec sheet. `tools/perf_probe.gd` windowed, vsync off,
1920×1080, `res://scenes/world/open_world_root.tscn`, car at full throttle,
8 s warmup + 20 s measure. Adapter reported by the engine itself:
`NVIDIA GeForce GTX 970`, `Vulkan 1.3.280 - Forward+`.

| Metric | **Low** | **Medium** | **High** |
|---|---|---|---|
| FPS avg | **78.6** | **62.1** | **73.3** |
| FPS min–max | 72–88 | 57–70 | 70–76 |
| frame_ms | 12.7 | 16.1 | 13.6 |
| process_ms (CPU) | 13.2 | 17.0 | 14.6 |
| draw_calls | 303 | 354 | 476 |
| primitives | 406,445 | 480,391 | 652,995 |
| VRAM | 664 MB | 1161 MB | **777 MB** |

High's row is **after** the SDFGI fix below; the pre-fix High baseline was
41.7 fps / 24.0 ms / 1182 MB.

### High GPU attribution — SDFGI was the entire deficit (measured)

Leave-one-out from the High preset, same probe, each run disabling exactly one
effect:

| High configuration | FPS | frame_ms | Δ ms |
|---|---|---|---|
| as originally shipped | 41.7 | 24.0 | — |
| − volumetric fog | 57.5 | 17.4 | **−6.6** |
| SDFGI cheapened (2 cascades, 32 m) | 57.4 | 17.4 | −6.6 |
| SDFGI cheapened − volumetric fog | 58.9 | 17.0 | −7.0 |
| **− SDFGI (shipped fix)** | **73.3** | **13.6** | **−10.4** |

The decisive line is the last one: High with SDFGI off runs at **13.6 ms
against a 14.6 ms CPU floor**, i.e. the GPU is no longer the constraint at all.

**Cheapening SDFGI does not work.** Halving the cascades and cutting
`sdfgi_max_distance` to 32 m recovered only 6.6 of the 9.3 ms, and adding back a
no-fog configuration still landed at 58.9. *Every* configuration that keeps
ray-traced diffuse GI measured 57–59 fps — just under the bar. On this GPU, GI
and 60 fps are mutually exclusive. Note also the engine clamps
`sdfgi_max_distance` to 32 m when cascades are reduced, so the distance lever is
not independently tunable.

**Shipped fix:** High sets `sdfgi_enabled = false` and keeps volumetric fog +
SSR + glow + SSAO + FSR2 0.85 + the 4-split shadow ladder. Result 41.7 → 73.3
fps, and VRAM fell 1182 → 777 MB because SDFGI's cascade buffers are no longer
allocated. GI is not gone from the ladder: **Medium keeps SDFGI**. Ambient light
plus High's per-car `ReflectionProbe` carry the fill light.

**Open design smell this exposes:** Medium (62.1 fps) is now *slower* than High
(73.3), so selecting High gives both better visuals and more frames — Medium is
dominated. Medium is CPU-bound, not GPU-bound (`process_ms` 17.0 vs High's
14.6), driven by MSAA 4x at full resolution with no upscaling. Deciding what
Medium should be is a product call, not a perf one, so it is left open here.

### ⚠️ THE BOTTLENECK MOVED — the rest of this plan is now obsolete

After the SDFGI fix, every preset measures `frame_ms ≈ process_ms`, i.e. **the
frame is CPU-bound and the GPU is no longer the constraint**:

| Preset | frame_ms | process_ms | bound by |
|---|---|---|---|
| Low | 12.7 | 13.2 | **CPU** |
| Medium | 16.1 | 17.0 | **CPU** |
| High | 13.6 | 14.6 | **CPU** |

High with SDFGI off runs at 13.6 ms against a 14.6 ms CPU floor — the GPU has
roughly a millisecond of headroom, not ten.

**Therefore do not implement the remaining GPU items. None of them can move the
framerate, because none of them touch the constraint:** texture compression,
draw-call batching / MultiMesh merging, VRS, TAA, mesh LOD, occlusion culling,
and virtual texturing are all **DROPPED**. SDFGI's own cost was ~9 ms of GPU
time; nothing else in this document is plausibly that large, and there is no
longer anywhere to hide it.

### SUPERSEDED by handoff 9.9-9.10 - the DROPPED list above is now WRONG

The reasoning above rested on fps, which turned out to be unmeasurable on this
box (it swings 34-75 fps for identical content because the OS deschedules us
between frames). Measured on `stage_todraw` instead, which repeats within
+-0.1 ms:

- Gameplay script CPU, ALL of it disabled, is worth **< 0.5 ms** - so the CPU
  leads below really are dead, and the traffic LOD change is correctness only.
- But `stage_todraw` is **geometry-bound, not fill-bound**: rendering at
  `scaling_3d_scale=0.25` (1/16 the pixels) saves only ~1.3 ms of ~9.6 ms.
  Fragment cost is ~14%; the other ~8 ms is vertex/primitive/draw-call work
  (476 calls, 650k primitives per frame at High).

**Revised, with cause:**

| Item | Verdict now | Why |
|---|---|---|
| Draw-call batching / MultiMesh merging | **RESURRECT** | geometry-bound frame |
| Mesh LOD, distance culling | **RESURRECT** | 650k prims/frame |
| Occlusion culling | maybe | geometry-bound, but high complexity |
| VRS | **PERMANENTLY DROP** | pure fragment rate; ~14% of frame |
| TAA | **PERMANENTLY DROP** | fragment + history |
| Texture compression | **PERMANENTLY DROP** | fragment/bandwidth |
| Resolution scale / FSR tuning | **PERMANENTLY DROP** | max ~1.3 ms, costs quality |
| Medium MSAA 4x removal | **DROP** | resolve is largely fragment cost |

The binding constraint is now ~8 ms of geometry/vertex/submission cost, not ~9 ms
of SDFGI and not any fragment-side lever. See
`docs/HANDOFF_PARALLEL_GATE.md` 9.9-9.11 for the measurements, and do not trust
any fps-only comparison in this document.

First CPU measurement (`perf_probe.gd`, `PHYSICS_3D_ACTIVE_OBJECTS`):
**`phys_bodies avg=2`**. Jolt is solving essentially nothing, so physics cost is
*not* body-count bound — the CPU time is in `_physics_process` callbacks
(terrain streaming, `TerrainSeeder`, `RegionDresser`), which count toward
`TIME_PHYSICS_PROCESS`. That is where the next investigation belongs.
(**Now closed: those callbacks total < 0.5 ms.**)

### ⚠️ Measurement integrity — read before trusting any number here

The dev box carried **53% ambient CPU load** from unrelated processes (opencode,
VS Code, Steam, OneDrive) during these runs. Two **identical** Medium
configurations measured **62.1 fps and 38.5 fps (min 18)**. Consequences:

- **Trustworthy:** large effects far above the noise floor — SDFGI ±9 ms, the
  shadow ladder's 2.45× on Low, VRAM 1182 → 777 MB. These reproduce.
- **NOT trustworthy:** fine-grained per-preset figures, especially Medium's,
  and any target set within ~20% of current. Re-baseline on a quiet machine
  before optimising against them.
- Do not gate a regression on a single run's fps. Median of ≥3 runs, or the
  `test_perf_gate.gd` CPU budget, which is measured under a serialized shard.

Shadow-ladder A/B (same probe, `apply_shadow_preset` bypassed):

| Run | FPS avg | frame_ms | draw_calls | primitives |
|---|---|---|---|---|
| Low, ladder ON | **78.6** | **12.7** | 303 | 406,445 |
| Low, ladder OFF | 32.1 | 31.2 | 347 | 468,122 |
| High, ladder ON | 41.7 | 24.0 | 464 | 633,871 |
| High, ladder OFF | 39.2 | 25.5 | 372 | 479,616 |

**What the measurements change — four of this plan's assumptions were wrong:**

1. **VRAM was never a problem.** Peak is **1.18 GB on a 4 GB card**. The
   "~3.5 GB current / <2.5 GB P0" row was ~3× wrong. **The texture-compression
   P0 is solving a non-problem** — the single largest item in the original
   plan, and it should be dropped, not scheduled.
2. **Draw calls were never a problem either** — 303–464, not "~2500". The
   `<1500` / `<800` targets are already met by 5×. Batching work is not where
   the time goes.
3. **Medium already hits the plan's headline goal** at 62.1 fps. "60 FPS @
   1080p Medium" is *met*, not aspirational.
4. **The one real gap was High, and it was SDFGI alone** — not the ~10 ms of
   unspecified GPU cost this section originally speculated about. High measured
   41.7 fps and was GPU-bound (frame_ms 24.0 vs process_ms 14.2); attribution
   put essentially all of it on ray-traced diffuse GI. Fixed by disabling SDFGI
   at High: **73.3 fps**, GPU no longer the constraint.

**The shadow ladder is the one shipped P0 with a measured win — and it is a
large one.** Low went **32.1 → 78.6 fps (2.45×)**, because the engine default
`directional_shadow_max_distance = 100` put the *entire* open world into the
shadow cascade; cutting Low to 1 orthogonal split at 20 m removed most shadow
casters. On High the effect is inside run-to-run noise (41.7 vs 39.2, and the
OFF run's average was dragged down by a 16 fps min hitch) even though 4 splits
versus the default 2 visibly raised submitted primitives (634k vs 480k). Do not
claim a High win from this — the ladder's value is Low.

### Remaining targets, re-based on the measurements

| Metric | Measured | Still worth doing? |
|---|---|---|
| FPS @ 1080p High | **73.3** (was 41.7) | Fixed — SDFGI attribution + fix shipped |
| FPS @ 1080p Medium | 62.1 | No — target met. But see the dominance note above |
| FPS @ 1080p Low | 78.6 | No |
| VRAM at High | 777 MB (was 1182) | **No — drop the texture-compression P0** |
| Draw calls | 303–476 | No — already 5x under target |
| Shadow cost | ladder shipped; Low 2.45x faster | Done |
| Terrain sync bake (1 region) | ~3.3 s (CPU, unchanged) | Yes — unchanged, still the load-time cost |
| GDUnit suite time | **206 s** (was 18 min) | Done — `tools\gdunit_parallel.py -j 4` |

---

## Risks & Fallback Paths

| Risk | Likelihood | Impact | Fallback |
|------|------------|--------|----------|
| FSR2 not working on GTX 970 driver | Low | Medium | Use built-in bilinear upscale + sharpen pass |
| Compute shader terrain bake fails on Maxwell | Medium | High | Keep CPU baker, optimize with `FastNoiseLite.get_image()` bulk |
| Occluder3D setup labor-intensive | High | Low | Start with auto-generated occluders from collision meshes |
| Mesh LOD pop-in visible | Medium | Medium | Cross-fade LODs (Godot 4.4+ `lod_transition_mode`) |
| VRS unsupported on driver 560.94 | Medium | Low | Read `rendering/vrs/mode`; there is no runtime `has_feature` check to write |
| DRS causes UI flicker | Medium | Medium | Clamp min scale 0.6, exclude UI viewport |
| Virtual texturing too complex | High | High | Skip — use Texture2DArray for splatmaps only |

---

## Godot-Specific APIs to Use

| Feature | Class / Method | Notes |
|---------|----------------|-------|
| FSR2 | `Viewport.scaling_3d_mode` + `rendering/scaling_3d/mode` | **NOT** `RenderingServer.enable_fsr2()` — see the verification table |
| TAA | `rendering/anti_aliasing/quality/use_taa` | **NOT** `RenderingServer.enable_taa()`; startup-only, not runtime |
| VRS | `rendering/vrs/mode` | **NOT** `RenderingServer.enable_vrs()`; `1` = combine mode |
| Clustered lighting | Project Settings → Rendering → 3D → Rendering Method = Forward+ | Default |
| Occlusion culling | `Occluder3D`, `VisualInstance3D.occlusion_culling` | 4.0+ |
| Mesh LOD | `MeshLOD`, `GeometryInstance3D.lod_threshold` | 4.0+ |
| Compute shader | `RenderingDevice`, `compute_list_begin/end`, `RDShaderFile` | 4.0+ |
| Texture2DArray | `Texture2DArray.create_from_images()` | 4.0+ |
| MultiMesh | `MultiMesh.instance_count`, `set_instance_transform()` | Batched props |
| WorkerThreadPool | `WorkerThreadPool.add_task()`, `add_group_task()` | CPU async |
| Motion vectors | `StandardMaterial3D.motion_vector_enabled` | For TAA/FSR2 |
| Shadow tuning | `directional_shadow_mode`, `directional_shadow_max_distance`, `directional_shadow_fade_start`, `Light3D.shadow_opacity` | `shadow_cascade_count` / `shadow_max_distance` / `shadow_fade_start` **do not exist** — see item 3 |

---

## Integration with Existing Code

| File | Change |
|------|--------|
| `scripts/ui/settings_menu.gd` | Add `fsr2_mode`, `drs_enabled`, `vrs_enabled`, shadow cascade counts to `QUALITY_PRESETS` |
| `scripts/world/terrain_baker.gd` | Add `bake_region_gpu(region)` compute path, keep CPU fallback |
| `scripts/world/terrain_seeder.gd` | Move `_bake_sync` to `WorkerThreadPool`, use GPU path when available |
| `scripts/world/prop_scatterer.gd` | Batch `MultiMesh` updates, add `occlusion_culling = true` |
| `scripts/vehicle/vehicle_physics.gd` | Enable `motion_vector` on car materials |
| `scenes/ui/hud.tscn` | Separate UI `Viewport` (fixed res) from 3D `Viewport` (DRS) |
| `project.godot` | `rendering/3d/rendering_method = "forward_plus"`, `rendering/vram_compression/import_*` |

---

## References

- Digital Foundry: "The Technology of Forza Horizon 5" (2021) — surfel GI, virtual texturing, parallax occlusion mapping
- Playground Games GDC 2022: "Visual Effects Summit: How Parameters Drive Particle Effects" — parameterized VFX
- Godot 4.4 Docs: GPU Optimization, Forward+ Renderer, FSR2, VRS, Occlusion Culling
- AMD FidelityFX SDK: FSR2 integration guide
- NVIDIA Streamline: Cross-vendor upscaling framework (for future DLSS)

---

## Sign-Off

- **Author:** [Agent]
- **Review:** Run P0 items, validate FSR2 + TAA on GTX 970, measure VRAM & FPS
- **Gate:** Full GDUnit suite + manual playtest at each phase boundary