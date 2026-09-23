# Terrain Vista Plan

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
| 1 | per-texel cost w/ (a)(b)(c) cuts | 3.5 us | est <2.5 us | Phase 1 |
| 2 | cold start | ~3.3 s | | driveable-to-first-frame |
| 2 | hitch max frame | baseline | | at first vista region landing |
| 5 | perf Low avg/ml | 92.7/94.7 | | must stay ≥60 |
| 5 | perf Medium avg/ml | 64.6/64.6 | | ≥30 |
| 5 | VRAM | 763 MB | | +72 MB static expected |

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