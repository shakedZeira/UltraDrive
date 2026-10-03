# FH5-Inspired Optimization Plan for UltraDrive (Godot 4.7.2)

**Target hardware:** GTX 970 (Maxwell, 4GB VRAM, compute 5.2, Vulkan 1.3)  
**Engine:** Godot 4.7.2, Vulkan backend (OpenGL fallback), Forward+ renderer  
**Current bottlenecks:** Terrain sync bake ~3.3s/region, 95 GDUnit suites ~18min, no upscaling  
**Baseline quality ladder:** Low / Medium / High (settings_menu.gd)

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

#### 1. Enable FSR2 Upscaling + Quality Ladder Integration
**Target:** 1080p → 1440p/4K upscale, 30–50% fps gain at High preset

```gdscript
# In SettingsMenuScript.apply_to_scene_tree()
var rs = RenderingServer
rs.enable_fsr2(true)
rs.fsr2_set_quality(FidelityFXSuperResolution2.QUALITY_ULTRA_QUALITY) # map: Low=Performance, Med=Balanced, High=Quality
```

- Add `fsr2_mode` enum to `QUALITY_PRESETS`: `OFF`, `PERFORMANCE`, `BALANCED`, `QUALITY`, `ULTRA_QUALITY`
- Expose sharpness slider (0.0–1.0) in Settings UI
- **Fallback:** If `rs.has_feature("fsr2")` false → disable gracefully

#### 2. Texture Compression Audit
**Target:** VRAM <3GB at High, <2GB at Medium

- All 3D textures: Import → VRAM Compression = **BC7 (RGBA)** or **BC1 (RGB)** / **BC4 (R)** for masks
- Terrain splatmaps: **BC5 (RG)** for normal/height pairs
- Disable compression only for pixel-art / UI textures
- Verify with `RenderingServer.get_video_memory_usage()`

#### 3. Shadow Cascade Tuning
**Target:** 2ms → 1ms shadow cost at Medium

```gdscript
# In SettingsMenuScript.apply_to_scene_tree() per preset:
# Low: 1 cascade, 1024, 20m max
# Med: 2 cascades, 2048, 50m max
# High: 4 cascades, 2048, 100m max
dir_light.shadow_cascade_count = cascades
dir_light.shadow_max_distance = max_dist
dir_light.shadow_resolution = res
```

- Disable shadows for `OmniLight3D`/`SpotLight3D` beyond 15m (traffic, props)
- Use `shadow_contact` bias to avoid acne without PCF cost

#### 4. Enable TAA + Motion Vectors
**Target:** Stable 60fps image, ghosting <1 frame

```gdscript
rs.enable_taa(true)
rs.set_taa_jitter_scale(0.5) # tune for vehicle speed
```

- Ensure all moving objects (cars, wheels) have `MotionVector` pass (StandardMaterial3D → `motion_vector` enabled)
- Disable TAA at Low preset (FXAA only)

#### 5. Variable Rate Shading (VRS)
**Target:** 5–10% fragment cost reduction on GTX 970 (Vulkan 1.1+)

```gdscript
if rs.has_feature("vrs"):
    rs.enable_vrs(true)
    rs.vrs_set_combiner(VRS_COMBINER_MAX) # per-draw VRS texture later
```

- Start with `VRS_COMBINER_MAX` (coarse shading on low-detail tiles)
- Later: generate VRS texture from depth/velocity for foveated shading

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

| Metric | Current | P0 Target | P1 Target | P2 Target |
|--------|---------|-----------|-----------|-----------|
| Terrain sync bake (1 region) | 3.3s | 3.3s | 3.3s | **<0.5s** (GPU) |
| Async ring budget/frame | 16ms | 16ms | **<8ms** | **<4ms** |
| VRAM at High (1080p) | ~3.5GB | **<2.5GB** | **<2GB** | **<1.5GB** |
| Draw calls (dense scene) | ~2500 | ~2500 | **<1500** | **<800** |
| Shadow cost (Medium) | ~2.5ms | **<1.5ms** | **<1ms** | **<0.5ms** |
| FPS @ 1080p Medium (GTX 970) | ~45 | **55** | **60** | **60+** |
| FSR2 Quality mode gain | N/A | **1.4×** | **1.5×** | **1.6×** |
| Shader pipelines (High) | ~120 | ~120 | **<50** | **<30** |
| GDUnit suite time | 18min | 18min | 15min | 10min |

---

## Risks & Fallback Paths

| Risk | Likelihood | Impact | Fallback |
|------|------------|--------|----------|
| FSR2 not working on GTX 970 driver | Low | Medium | Use built-in bilinear upscale + sharpen pass |
| Compute shader terrain bake fails on Maxwell | Medium | High | Keep CPU baker, optimize with `FastNoiseLite.get_image()` bulk |
| Occluder3D setup labor-intensive | High | Low | Start with auto-generated occluders from collision meshes |
| Mesh LOD pop-in visible | Medium | Medium | Cross-fade LODs (Godot 4.4+ `lod_transition_mode`) |
| VRS unsupported on driver 560.94 | Medium | Low | Detect `has_feature("vrs")`, skip gracefully |
| DRS causes UI flicker | Medium | Medium | Clamp min scale 0.6, exclude UI viewport |
| Virtual texturing too complex | High | High | Skip — use Texture2DArray for splatmaps only |

---

## Godot-Specific APIs to Use

| Feature | Class / Method | Notes |
|---------|----------------|-------|
| FSR2 | `RenderingServer.enable_fsr2()`, `fsr2_set_quality()`, `fsr2_set_sharpness()` | 4.4+ |
| TAA | `RenderingServer.enable_taa()`, `set_taa_jitter_scale()` | 4.0+ |
| VRS | `RenderingServer.enable_vrs()`, `vrs_set_combiner()` | Vulkan 1.1+, 4.3+ |
| Clustered lighting | Project Settings → Rendering → 3D → Rendering Method = Forward+ | Default |
| Occlusion culling | `Occluder3D`, `VisualInstance3D.occlusion_culling` | 4.0+ |
| Mesh LOD | `MeshLOD`, `GeometryInstance3D.lod_threshold` | 4.0+ |
| Compute shader | `RenderingDevice`, `compute_list_begin/end`, `RDShaderFile` | 4.0+ |
| Texture2DArray | `Texture2DArray.create_from_images()` | 4.0+ |
| MultiMesh | `MultiMesh.instance_count`, `set_instance_transform()` | Batched props |
| WorkerThreadPool | `WorkerThreadPool.add_task()`, `add_group_task()` | CPU async |
| Motion vectors | `StandardMaterial3D.motion_vector_enabled` | For TAA/FSR2 |
| Shadow tuning | `DirectionalLight3D.shadow_cascade_*`, `shadow_max_distance` | Per preset |

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