# Terrain Vista Plan

> **AS BUILT 2026-10-23 (open-world stage 2, item 1).** Implemented and measured; see
> "§9 AS BUILT" at the end for what changed against this plan, why, the numbers and the
> captures. The sections below are the original plan, kept for reference. Where they
> disagree with §9, §9 is right (notably: 32 m lattice not 64 m, exact ring-support sampling
> at cell seams / biome edge / height clamp, regions pre-added blank, height `set_map` off the
> main thread, colour-map mipmaps, camera far via a per-scene `far_clip` export).

Target rig: **GeForce GTX 970** (Maxwell, 3.5 GB VRAM, Vulkan), 1920x1080,
**Forward+**, Jolt, Terrain3D 1.0.2 (GDExtension), Godot **4.7.2**.
Related: `docs/ROADMAP.md`; `docs/plans/open_world_optimization_plan.md`
(perf work is CLOSED at 94.9 FPS Low / 64.6 Medium / 56.5 High — a vista must
NOT reopen that).

## Objective

The live world is a 3x3 = 768 m `Terrain3D` ring streamed around the player,
yielding mountains that end at a hard flat edge ~384 m away. Add a **static
far-terrain vista**: a second `Terrain3D` node built **once at load**, never
streamed, covering the whole drivable world so seen mountains run to the
horizon with:
- **zero per-frame streaming cost** (no new main-thread bake, no new region
  swaps),
- **no z-fighting at the ring edge** (vista heights are the SAME field as the
  live bake, biased -1 m so the live ring always wins depth),
- **no regression to the region-crossing freeze fix** (ring/seeder untouched).

Deliverable proof: saved PNGs (pass/horizon, ring-edge boundary, spawn/hub),
a before/after hitch + perf probe, and a green suite.

**Working agreement: this plan is produced for review. Do NOT implement until
approved.**

---

## §1 BACKGROUND / FACTS (verified, not assumed)

### The live terrain (`scripts/world/terrain_seeder.gd`)

- `REGION_SIZE := 256`, `RING_RADIUS := 1` → 9 live regions (768 m), whatever
  the map size. `PREFETCH_RADIUS := 2`, `MAX_RING_ADD_PER_FRAME := 1`,
  `MAX_APPLY_PER_TICK := 2`, priorities LIVE 0 / CORRIDOR 1 / PREFETCH 2.
- Regions are baked by `scripts/world/terrain_baker.gd` (pure `RefCounted`,
  deterministic, tested byte-exact by `test_terrain_seeder_streaming.gd`).

### The heightfield (`scripts/world/terrain_baker.gd` — full read)

- **Per-256 m-cell seed**: `seed = 1337 + loc.x*131 + loc.y*977`. fBm 3 octaves,
  freq 0.003, lacunarity 2.0, gain 0.5 (verified full read: `terrain_baker.gd:41-45`).
- **Biome table (verified full read, 8 blends + fallback)**: spawn (128,128, base 2,
  r 1500), rolling (2048,2048, 18, 2000), highland (3584,2816, 35, 2600), farmland
  (2048,400, 6, 1600), coast (8200,−1800, 2.5, 1800), lowland (4600,4700, 90, 2200),
  highland_plateau (6800,6400, 260, 2600), sea (8200,−3400, −6, 2600), fallback 1.0.
- **Alpine domes**: legacy (5632,5632, amp 42, r 5000, edge 0.35) + DOME_FAMILY
  (7800,6400, 1100, 3200), (6400,7800, 850, 2800), (7000,3000, 150, 1800).
- **Spawn plateau**: (128,128, r 40, +2.2). **Height clamp**: [-8, 2000]
  (NOT the [-5,60] a stale source claimed). Colors: `BAND_COLORS` 6-band palette.
- Ring pipeline per region: natural coarse (64x64 @ 4 m) → bilinear upsample to
  256 -> `_conform_roads` (road carve, `d2` per texel, clip window 256 m +
  margin `1.0*step+0.1`, band `12*step^2`, core `ROAD_WIDTH*0.5+0.3`, blend to
  `BLEND_END`) → 3x3 blur → spawn guard → clamp.
- **Canonical mapping** (the seam-critical bit). With K=4, cs=64, a texel
  `(ix,iy)` of a 256-cell maps to coarse-frame `fx = (ix+0.5)/4 - 0.5 =
  ix/4 - 0.375`. So the canonical value at a **world point** `wx` in its
  256-cell is the coarse-bilerp at `u = (wx - cell_origin)/4 - 0.375`, `v`
  likewise. Adjacent cells have different seeds → existing small seams are
  inherent to the design; a vista must reproduce the containing cell or stay
  strictly below it (we do both).

### Terrain3D API facts (docs + live node cross-checked)

- Maps are always `region_size` px (1px = 1 vertex). `region_size` max
  `SIZE_2048`.
- `vertex_spacing` (per-region, default 1.0; "managed by the instancer when
  `Terrain3D.vertex_spacing` is set") **latently scales world XZ**: at spacing 2
  a feature at (512,512) appears at (1024,1024). Region id grid =
  `world/(spacing*region_size)`; import valid range =
  `spacing*region_size*(±16)` → `REGION_MAP_SIZE` (32) is moot for a 3x3.
- `Terrain3DData.add_region_blankp(global_position, update)` places the region
  containing a world point (prefer over hand-computing locs).
- `collision_mode` enum: `0 DISABLED`, `1 DYNAMIC_GAME`, `2 DYNAMIC_EDITOR`,
  `3 FULL_GAME`, `4 FULL_EDITOR`. **0 = DISABLED confirmed** via
  `tools/diag_region_cost.gd`. Node defaults: `collision_mode 1`,
  `cast_shadows 1`, `cull_margin 0`, `collision_radius 64`, `collision_shape_size
  16`, `mesh_lods 7`, `mesh_size 48`.
- A written region needs `edited = true`, height_range updated
  (`calc_height_range`/`update_height` — else AABB/culling), then one
  `update_maps(TYPE_HEIGHT|TYPE_COLOR, all=false)`.
- The live node (`open_world_root.tscn`) writes **COLOR** maps and **no**
  CONTROL maps and renders colored → the static node must also write color maps
  (default-material look with no color map is unverified/risky).
- Runtime `Terrain3D.new()` is fine (diag tools + tests already do it).

### World / data / cameras

- Drivable world (events): x [-200..9702], z [-2944..8605]; spawn (128,128);
  mountain pass ~(3800,3200); sea near (8200,-3400).
- Chase + orbit cameras (`scripts/camera/chase_camera.gd:40-43`,
  `orbit_camera.gd:31-34`) create `Camera3D.new()` with **default far = 4000**.
  The vista needs far ≈ 24000. `settings_menu.gd` `apply_to_scene_tree` touches
  Environment + viewport only (**no camera/far/fog-density override** — read
  verified). Pause map is 2D (`map_roads.gd`) — no 3D far involvement.
- `world_driver.gd` `_ready` order: `_bootstrap_roads()` (roads exist) BEFORE
  `_push_player_position()` (first bake conforms under roads). The vista must be
  kicked off **after `_bootstrap_roads()`** so road points are available, and
  its spawn region should be visible before/with the player's first live region
  (~3.3 s cold start).
- Roads: `road_network.gd` group `"road_network"`, `add_road(points,width,
  closed)`, `add_road_def`, `get_road_defs()`, `RoadGraph.build_topology`.
  Seeder `set_roads(...)` receives the same spline points the baker carves
  with — the vista must consume the same source.

---

## §2 DESIGN (settled)

### Static vista node

- New `Terrain3D` node (runtime-created by a controller script), **9 regions
  (3x3) at `region_size = SIZE_1024`, `vertex_spacing = 8.0`**, covering
  x/z ∈ [-8192..16384) (region ids -1..1; centers `id*8192 + 4096`), placed via
  `add_region_blankp(center, false)`.
- `collision_mode = 0` (DISABLED), `cast_shadows = 0`. No COL texels written.
- 1024² @ 8 m/texel: VRAM ≈ 9 x (4 MB RF32 height + 4 MB RGBA8 color) ≈ 72 MB.
- Vertex spacing set on the **node BEFORE** adding regions (`terrain.vertex_spacing
  = 8.0`) AND belt-and-suspenders per-region after `add_region_blankp`.
  Placement semantics must be verified by the Phase 0 probe.

### Height/color fill (the z-fight guarantee)

- **Direct lattice evaluation** at each static texel's VERTEX position
  `(origin.x + i*8, origin.z + j*8)` — do NOT materialize 1 m buffers.
  Per texel: find containing 256-cell (seed, biome via same table) → evaluate
  natural fBm at the world point → coarse-bilerp with the canonical `u =
  (wx-cell_origin)/4 - 0.375` frame → apply road carve `d2` (same formulas,
  same road points, clip window `region+margin`) → spawn guard → clamp.
  Sub-cm differences vs the ring's own filtered/pixel-centered bake are
  absorbed by the bias.
- **-1.0 m bias on all vista heights.** 8 m-lattice sag ≪ 1 m (worst
  ~0.05-0.3 m), so the live ring always wins depth; z-fighting is impossible.
- **Color maps**: band color from `ELEVATION_BANDS` palette at the biased
  height, x coarse noise brightness (wx+500) bilerp, + road tint via the same
  d2 logic (cheap at coarse resolution). Renders colored exactly like the live
  node, so no color seam at the ring edge.
- **Determinism**: same constants, same seeds, pure function of (cell, world
  point) — a `TerrainVistaBaker` (`RefCounted`) mirroring `terrain_baker.gd`'s
  formulas. Existing bake outputs MUST stay byte-identical (tests guard).

### Threading / wiring

- Vista build runs on its own worker `Thread` (pure float math, no Terrain3D
  off-main). Regions applied on the main thread ≤ 1-2 per idle frame
  (`_process` drain, like the seeder), spawn-cell region FIRST so the vista
  exists when the first live region lands.
- Hook: `world_driver.gd` after `_bootstrap_roads()` → `bootstrap_vista()`
  reads road points, starts the worker. Static node added to `open_world_root`
  before the live Terrain3D (nice-to-have; the bias makes draw order
  non-critical).
- **Camera far** = `24000.0` on both `chase_camera.gd` and `orbit_camera.gd`.

---

## §3 EXECUTION CONTRACT

- **Sub-agents run strictly SEQUENTIALLY. One Godot process at a time** (two
  collide on `.godot/`). Watchdog on every headless run. Each task = one phase
  (below); sub-agent gets exact file:line targets, the gate command, and the
  rule "don't touch anything outside your phase".
- No commits. Report first with verbatim items: `git status --short`,
  `git diff --stat`, all `Overall Summary:` lines, import-gate output, perf
  numbers, the sample/design + proof, static config + cold start, z-fight
  mechanism + PNG paths.
- **No code comments. Tabs** in `scripts/world/*` and `tools/*`. Don't touch
  vehicle/audio/UI. Don't re-tune the ring/seeder freeze fix. Existing tests
  unchanged unless a phase explicitly flags one.
- Revert gate: if z-fighting cannot be made clean in ~2 focused attempts →
  revert clean tree + findings memo (API names, attempts, failure PNGs).
- A phase is "done" only when: import gate shows zero `SCRIPT ERROR`/`Parse
  Error`, the gdUnit suites are green, and (for perf phases) a probe prints a
  recorded number.

### Verification commands

```bat
rem (1) import / parse gate
"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import . 2>&1 | findstr /i "SCRIPT ERROR Parse Error Failed to load"

rem (2) suite (run AFTER step 1; flag MUST come AFTER the tool-script path)
"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1
findstr /c:"Overall Summary:" _gdunit.txt
```

Per-suite one-at-a-time: `test_terrain_baker`, `test_terrain_biomes`,
`test_terrain_seeder_streaming`, `test_streaming_dressing`, `test_discovery`,
`test_map_route` (all currently green; must stay green unchanged).

---

## §4 PHASES

### Phase 0 — API + cost probe (facts before code)

`tools/diag_vista_api.gd`: one headless run, one Godot process:
1. Create `Terrain3D` → `vertex_spacing = 8.0` → `add_region_blankp(Vector3(8192,
   0, 8192), false)` → print `region.location` (expect {0,0}; proves spacing
   participates in placement).
2. `region.set_map(TYPE_HEIGHT, 1024² RF)` + `TYPE_COLOR` image + `edited=true`
   + `update_height(0, h)` + `update_maps(HEIGHT|COLOR, false)` → no errors,
   image size accepted.
3. Co-existence: static `collision_mode=0` node + live node in the same tree →
   no script errors, `get_instantiated_regions()` count == 9 on static.
4. Cost: time `get_noise_2d` (1e5 calls), one 256-cell natural coarse (64², 3
   octaves), one full 1024² static region (32768 texels x natural+filters), and
   the projected 9-region build. Record in §5.

Gate: probe prints clean numbers; no errors. **Lock 8 m spacing + 9 regions**
(640 m -> 8192 m reach ~13x; do NOT reduce to 4 m → 4x regions + VRAM without
any visible gain at horizon).

**Phase 0 VERDICT (2026-09-22, measured once, GTX 970):** the "materialize the
same per-256-cell canonical field" sampler is DEAD at ~127 s for 9 regions
(0.2 us/noise, 11.9 ms/cell natural, 1.8 ms/cell brightness, 9216 cells).
Direct-lattice eval of the canonical field at the 8 m texel grid, factoring the
POSITION-ONLY biome/dome terms onto a shared 64 m lattice (385², ~0.77 s once)
and sampling only the seed-dependent fBm detail per texel, measures 2.93 s/
tile height-only, 3.72 s/tile height+color → ~26-33 s/9 single-threaded. **The
sampler cannot hit the 12 s gate single-threaded on this CPU; the mitigation is
the already-planned worker threading from Phase 2 (3-4 tile workers → ~7-9 s
wall) plus these three per-texel costs cuts in Phase 1:
(a) one `sum=base+dome` lattice + one `scale=1.8+0.14*base` lattice → 1 bilerp +
1 fBm detail per texel instead of rebuilds;
(b) precomputed spawn AABB so 99.9% of texels skip the `distance_to`;
(c) hardcoded RGBA byte tables per band × brightness → two `PackedByteArray`
writes instead of per-texel Color math.
D1 (bulk `get_image` 8-bit detail) is 23 s/9 but breaks per-cell seed parity →
rejected for seam fidelity (documented, not used).**

### Phase 1 — `TerrainVistaBaker` (pure math, worker-ready)

`scripts/world/terrain_vista_baker.gd` (`RefCounted`, deterministic), reading
`terrain_baker.gd` constants verbatim:
- `bake_region(loc, width, roads) -> {height: Image, color: Image}` for a
  **1024² @ 8 m** region: direct lattice eval of the canonical field
  (per-256-cell seed/biome/dome/plateau/clamp), road carve, -1.0 bias (height
  ONLY — color allowed to differ from ring for band brightness).
- Full reusable world helper: `natural_height_at(world: Vector3) -> float` so
  both live and vista share one source of truth (add as a thin wrapper around
  existing baker internals; verify ring bakes are byte-identical after — the
  existing baker tests are the gate).

Gate: `test_vista_baker.gd` asserts determinism + (vista value == ring value at
the same world point within `1.0 + blob` m after bias) + bias sign + coverage
(x/z [-8192..16384)).

### Phase 2 — `TerrainVista` controller + wiring

`scripts/world/terrain_vista.gd`: owns the static `Terrain3D`, starts the
worker, drains completed regions 1-2/frame on the main thread, spawn region
applied first. Added by `world_driver.gd` after `_bootstrap_roads()`.
Region apply mirrors `terrain_seeder.gd`'s write pattern (set maps → edited →
update_height → update_maps).

Gate: import probe clean; streaming + discovery + map_route suites green; cold
start ≈ 3.3 s (unchanged); `hitch_probe` shows no new frames > 120 ms at first
region landing.

### Phase 3 — Camera far planes

`scripts/camera/chase_camera.gd` + `orbit_camera.gd`: `_camera.far = 24000.0`
(right after fov assignment). Nothing else (settings ladder untouched).

Gate: probe FPS held at ≥60 Low; PNG (pass/horizon) shows mountains to the
horizon.

### Phase 4 — Tests

- `tests/suites/test_vista_baker.gd` (Phase 1): determinism, ring-sampler
  agreement at shared lattice points with bias, bias sign, per-256-cell seed
  parity, road-carve carve present in vista, 3x3 coverage of drivable extents.
- `tests/suites/test_vista_wiring.gd`: controller registers 9 regions with
  collision DISABLED, spawn-first ordering, apply budget ≤ 2/frame; live node
  untouched; no new orphans (or documented benign ones).
- Existing suites are the regression gate and MUST stay green unchanged.

Gate: full suite green (`-a res://tests`).

### Phase 5 — Verification + proof + report

- Baseline already recorded on `d8610ef` (optimization plan §5): hitch probe
  baseline, perf probe baseline.
- After: perf probe (Low/Medium) + hitch probe before/after table.
- Windowed PNGs → `D:\Temp\opencode\vista\`: (a) pass/horizon,
  (b) ring-edge look sideways (boundary), (c) spawn/hub. Analyze each with the
  vision-bridge `analyze_image` and keep them as the z-fight/coverage proof.
- Verbatim report (see §3), no commit.

Gate: all PNGs show seamless horizon with no visible edge/color line; suite
green; frame budget held.

---

## §5 MEASUREMENT LOG (fill in as phases land)

| Phase | Metric | Before | After | Note |
|---|---|---|---|---|
| 0 | `get_noise_2d` cost | — | 0.2 us/call | 2e5 calls |
| 0 | per-256-cell coarse natural | — | 11.94 ms | 64² x 3 octaves |
| 0 | per-256-cell coarse brightness | — | 1.82 ms | |
| 0 | naive 9-region canonical | — | ~127 s | DEAD (rejected) |
| 0 | direct-lattice tile (h only) | — | 2.93 s | 1 bilerp + 1 noise/texel |
| 0 | combined h+color tile | — | 3.72 s | final bake form |
| 0 | lattice base+dome 385² @64 m | — | 0.77 s | once, shared |
| 0 | bulk get_image 1024² (8-bit) | — | 0.11 s + 2.54 s fill | breaks seed parity → rejected |
| 0 | projected 9-region (threaded 3-4 workers) | — | est 7-9 s | Phase 2 target |
| 1 | region bake (heights+colour+control), 3 pool threads | 3.5 us | ~3.0 s/region wall (first ~6 s while loading) | 9 regions 28.9-31.8 s total, in the background |
| 2 | cold start | ~3.3 s | +0.5 s | one-time `setup_ms` 494-542 (9 blank regions added inside the loading screen) |
| 2 | hitch max frame | 26.5 ms | 26.9 ms | warm-up frames while the vista builds; 0 frames > 33 ms; max main-thread apply step 1.2 ms |
| 5 | perf Medium, 4 hub poses (ms/frame) | 12.89 / 18.63 / 11.39 / 13.93 | 14.18 / 19.79 / 13.75 / 15.71 | see §9.4 |
| 5 | VRAM | 1245 MB | 1376 MB | +131 MB (texture +122 MB: 9 x height RF + colour RGBA8 with mips + control) |

---

## §6 SOURCES

- Terrain3D docs + class refs:
  `https://terrain3d.readthedocs.io/en/latest/` (class_terrain3d.html,
  class_terrain3dregion.html, class_terrain3ddata.html, collisions, materials).
- `docs/plans/open_world_optimization_plan.md` (§2 landmines, §5 measured
  baseline, §7 risks, §8 Gemini ledger — terrain/collision items).
- `scripts/world/terrain_baker.gd` (constants + carve formulas), `terrain_seeder.gd`
  (apply pattern), `world_driver.gd` (_ready ordering), `road_network.gd`.

---

## §7 RISKS

- **Fill-rate / depth cost of a giant static mesh at far = 24000.** The vista is
  mostly background haze; the clipmap LODs coarsen with distance. Must be
  re-measured with `perf_probe`; if it breaches ≥60 Low, reduce far to the
  horizon fog density first (fog_density 0.0008 already hides detail past ~4-6
  km), then spacing/LOD as last resort. Do NOT shrink region count (would
  reopen the edge).
- **Vertex-spacing placement semantics.** If `add_region_blankp` places by
  spacing-1.0 coords (addon bug), region ids land at world/1024 — the Phase 0
  probe catches it; fallback: hand-compute locs = `floor(world/(8*1024))` and
  pass through `add_region` as the seeder does. Plan-file consequence: none
  (Phase 0 is explicit).
- **Color seam at ring edge** if vista color differs from ring color. Mitigated
  by painting identical band colors from the same height field; the edge is
  inside the vista-fill's own region blend. Verdict by PNG (b).
- **Diagnostic hangs in headless** (any script error during diag leaves Godot
  hanging). Always run with a watchdog timeout.
- **500ms+ hitch when the first live region lands while the vista worker
  constructs** — mitigated by spawn-first region and the worker being non-GPU.
- **Perf regression reopening a CLOSED optimization** — gate is the probe
  before/after; any regression >5% on Low is a blocker to revisit (not to ship).

---

## §8 DELIVERABLE CHECKLIST (review gate)

- [ ] Phase 0 probe run; numbers in §5
- [ ] `terrain_vista_baker.gd` + tests green (import gate + `test_vista_baker`)
- [ ] `terrain_vista.gd` wired after `_bootstrap_roads()`; spawn-first
- [ ] Camera far 24000 on chase + orbit
- [ ] Full suite green, existing seams/tests untouched
- [ ] Perf/hitch before/after table
- [ ] 3 PNGs analyzed and saved to `D:\Temp\opencode\vista\`
- [ ] Verbatim report (no commit)

---

## §9 AS BUILT (2026-10-23)

### 9.1 Files

- `scripts/world/terrain_vista_baker.gd` (`TerrainVistaBaker`, pure `RefCounted`, rewritten: the
  previous file did not parse and had no road carve). Bands of 32 rows (one 256 m cell row),
  each with its own noise objects, so bands run in parallel.
- `scripts/world/terrain_vista.gd` (`TerrainVista`, new): owns the static `Terrain3D`
  (`VistaTerrain3D`, 3x3 x 1024 px at 8 m, collision 0, no shadows, LITE shader, the live
  terrain's `Terrain3DAssets` shared, world background NONE).
- `scenes/world/open_world_root.tscn`: `TerrainVista` node (`node_paths` header for
  `live_terrain`), `far_clip = 24000` on the Chase/Orbit/Hood/Cockpit cameras.
- `scripts/world/world_driver.gd`: `_bootstrap_vista()` right after `_bootstrap_roads()`.
- `scripts/camera/{chase,orbit,hood,cockpit}_camera.gd`: `@export var far_clip := 4000.0`
  (the Godot default, so the tracks are unchanged; only the open world sets 24000).
- `scripts/world/terrain_texturing.gd`: `apply(terrain, quality, shared_assets = null)`.
- Tests: `tests/suites/test_terrain_vista_baker.gd` (12), `tests/suites/test_terrain_vista_wiring.gd` (6).

### 9.2 Deviations from the plan, and why

1. **Lattice 32 m, not 64 m, and of the biome weight sums.** The 64 m bilerp is up to ~1.3 m
   off at the dome feet (convex smoothstep), more than the 1 m bias. Per band the baker builds a
   32 m lattice of biome `acc`, biome `total` and dome height; base = `acc / total`, which keeps
   the ring's hard fallback step where every biome weight reaches zero.
2. **Exact ring-support sampling where the ring is not smooth** (`_support_min`). An 8-aligned
   ring vertex X is a convex blend of the ring's 4 m coarse samples at X +- 2 m; the vista
   samples X + 0.5 (their bilinear centre) except:
   - on a live-cell seam (X or Z a multiple of 256) the ring clamps its coarse grid: its first
     texel is this cell's +2 m sample, its last texels hold the previous cell's -2 m sample with
     that cell's seed. Ring seams measured up to ~20 m in high relief (per-cell seeds, inherent).
     Seam vertices take the minimum of both cells' samples and drop a further 2 m x slope
     (the ring stays flat for 2 m and then rises, so the 8 m chord would otherwise cross it);
   - near the biome-union step (0 < total < 6e-4; 260 m -> 1 m east of the highland plateau,
     2 m -> 1 m round the spawn biome, -6 m -> 1 m round the sea): min of the four +-2 m
     samples, then a 3x3 erosion so no 8 m chord spans the step;
   - near the 2000 m height clamp (dome tops): min of the four +-2 m samples (the ring blends
     already-clamped samples, so it sits up to several metres under a clamped centre sample).
3. **Road carve** with the ring's rules (nearest segment, lower road wins near-ties, flat core,
   smoothstep to 40 m), plus `ROAD_SAG_BIAS` = 0.05 m per metre of cut/fill depth inside the
   blend (tapering 40-56 m): the 8 m chord over the cut/fill profile can rise above it.
4. **Main-thread apply.** Adding regions one by one made Terrain3D re-create its whole map
   texture arrays: 43-82 ms per region on the main thread. Now `start()` adds all nine regions
   blank at once (~0.5 s, inside the loading screen), and `Terrain3DRegion.set_map(TYPE_HEIGHT)`
   (19-28 ms: it scans the image) runs on the coordinator thread; nothing reads a vista
   region's CPU images meanwhile (no collision, no height queries, region not edited). The main
   thread then does one map per frame (height range + `update_maps(HEIGHT)`, colour, control):
   **max 1.2 ms per frame**.
5. **Colour-map mipmaps.** Without them the vista rendered pure black beyond ~5 km: the LITE
   shader samples the colour map at a distance-based mip and an 8 m texel reaches mip 1 there
   (live regions never get that far). Mipmaps are generated on the worker.
6. **Live world background NONE** (set at `start()`, when the blank vista regions replace it).
   This also removed the flat y = 0 plane, which by itself cost up to ~3 ms at high poses.
7. **Camera far** via a per-scene `far_clip` export rather than hard-coding 24000 in chase/orbit
   (that would have changed every track). Hood and cockpit cameras get it too.
8. Headless runs skip the bake unless `bake_in_headless` (tests opt in), so the many headless
   suites that load the open world do not spend 30 s of CPU on it.
9. Phase 0 "placement" is verified in the wiring test: with `vertex_spacing = 8` and SIZE_1024,
   `add_region_blankp(centre)` lands on the spaced grid and `data.get_height()` at world
   (128, 128) returns the spawn pad minus the bias.

### 9.3 Z-fight / seam proof

`test_terrain_vista_baker.gd` bakes the real ring (`TerrainBaker.bake_region` at 1 m) for 14 live
regions (hub, farmland, highland pass, dome foot / slope / legacy dome, height-clamped dome top,
sea, plateau biome edge, spawn biome edge, a 20 m road cut and a 15 m fill) and checks every live
vertex inside every vista quad against BOTH triangle splits: the vista is at least 0.1 m below
the ring everywhere, and tracks it (vertex error < 0.6 m, mean < 0.15 m, off seams and edges) in
smooth terrain. Captures (reviewed by Claude with the Read tool) are in the session scratchpad
`D:\Temp\claude\d--AI-Projects-UltraDrive\2afc40e3-6ded-4a3e-bfa8-14f5654eec46\scratchpad\cap\`:
`base_*` (before) vs `v4_*` (hub, after), `v5_*` (highland and far-camera views).

### 9.4 Performance (GTX 970, 1080p, Medium, vsync off, the stage 1 fixed poses + 3 more)

| pose | before (stage 1 baseline re-run) | after | delta | far 24000 only | background NONE, vista hidden |
|---|---|---|---|---|---|
| a eye, field | 12.89 | 14.18 | +1.29 | 13.14 | 13.31 |
| b high, hub | 18.63 | 19.79 | +1.16 | 18.72 | 17.21 |
| c eye, road | 11.39 | 13.75 | +2.36 | 11.54 | 11.25 |
| d high, outward | 13.93 | 15.71 | +1.78 | 14.18 | 11.06 |
| e seam, side | 13.19 | 14.00 | +0.81 | 13.46 | 12.69 |
| f horizon NE | 15.40 | 17.06 | +1.66 | 15.75 | 12.51 |
| g eye, west | 13.04 | 13.57 | +0.53 | 13.04 | 12.94 |
| highland pass NE | 13.93 | 16.96 | +3.03 | | |
| highland pass SW | 16.64 | 18.43 | +1.79 | | |

Draws +45..+60, prims +170k..+200k, VRAM 1245 -> 1376 MB. The vista is fragment-bound: a
probe-only variant with Terrain3D's `minimum.gdshader` (colour map only) on the vista ran
c 12.30 / d 13.91 / f 15.25 ms (near the baseline), but looks wrong as-is because our colour
map is a near-white tint (see 9.5). `mesh_lods` 6 instead of 7 changed nothing.

Low preset (same poses, ms/frame, before -> after): a 7.59 -> 8.72, b 12.14 -> 13.08,
c 6.37 -> 8.27, d 8.52 -> 9.71, e 7.71 -> 8.27, f 10.10 -> 11.36, g 7.49 -> 7.92. Every pose stays
above 60 FPS (worst 13.08 ms = 76 FPS), but the regression is +6..+30 %, over this plan's own
"> 5 % on Low = blocker to revisit" line in section 7. Not hidden: the decision (accept, make the
vista a quality-ladder option, or do the colour-only shader first) is the user's.

### 9.5 Open / not done

- **GPU cost +0.5..+2.4 ms at the hub (+3 ms at the pass).** Cheapest next step: a colour-only
  vista (bake per-layer average albedo x tint into the vista colour map, use a minimal shader);
  measured potential ~1-2 ms, needs a seam colour-match check.
- ~~Pre-existing, found here: the live ring cannot exist beyond +-4096 m.~~ FIXED the same day, see 9.6.
- **Pre-existing, found here: roads far below the heightfield in the east.** `touge-a` and
  `touge-b` (y ~31 m under ~2000 m domes, cut 1969 m), `highway-ring` (cut 1586 m at
  (6160, 5530)), `touge-highway-ramp` (1378 m). The ring's carve rule turns these into
  km-deep, 40 m-wide canyons; the vista reproduces them faithfully (seen as blade-like walls
  from inside the alpine area). Needs a CorridorPlanner / dome-placement fix, not a vista fix.
- Vista ground layers are classified per 16 m (2x2 texel blocks) without road shoulders.
- Not measured: High preset, a drive-through hitch probe while driving, RAM (the bake holds
  ~40 MB per region transiently).

### 9.6 Bug 3d: collision and a bias fade past the live ring's window (2026-10-23)

Terrain3D holds locations -16..15, so the 256 m live ring exists only inside x/z [-4096, 4096). Past it the
seeder now keeps the ring's locations *virtual* (baked and dressed, never added to Terrain3D; no more
"out of bounds" errors), and **the vista is the ground there**. Consequences for the vista, all in
`terrain_vista.gd` / `terrain_vista_baker.gd` (full write-up: `open_world_status.md` section 8):

- **Collision.** `TerrainVista.sync_player_pos()` switches the vista Terrain3D to DYNAMIC collision (shapes
  around the active camera, built from the drawn height maps; probed accurate to the 8 m mesh at 300 m
  range) while the player is within 512 m of the window edge or beyond it, once the vista region under the
  player is applied. Off elsewhere, so the area under the ring pays nothing. The earlier "no collision"
  design note (section 2) stays true inside the window.
- **Bias fade.** `BIAS` -1 m hides the vista under the ring, which only matters where the ring can exist.
  `TerrainVistaBaker.bias_at()`: -1 m until 128 m inside the window, -0.3 m at the edge, 0 from 128 m past it.
  A flat -1 m would have made the drivable far ground sit 1 m under the field the dresser/props use and left
  a 1 m wall at the window edge. The canonical field mapping (+0.5 m sample offset, seam minima, erosion,
  road sag) is unchanged; inside the window the heights are identical to before.
- **Tests.** The z-fight clearance rule (vista under the ring, > 0.1 m) now applies to quads inside the
  window only; the ring does not exist outside, so the old far-region cases (dome, clamp, sea) keep their
  *tracking* assertion (vertex error against `ring + bias_at`) and lose the clearance one. A new test covers
  the last 128 m inside the window, where the bias is smallest.
- **Cost.** None measured on the GPU (same mesh). Dynamic collision only runs near/after the window edge.
