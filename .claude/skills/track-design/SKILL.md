---
name: track-design
description: "Use when adding a new circuit/track to UltraDrive (layout from OSM or real-world data, TrackRegistry entry, scene, race-menu pins) or when improving an existing track's trackside visuals, surfaces, barriers, environment or performance. Covers the layout → scene → dressing → surfaces → gates → capture/critique loop with Le Mans No-Chicane as the worked example, plus how Northern Isle (oval), Barcelona RX and Le Mans differ."
---

# Track design (UltraDrive, Godot 4.7.2)

A track here is four layers, always built in this order, each with its own test
suite. Copy the closest shipped track rather than inventing structure.

| Layer | Le Mans (worked example) | Northern Isle (oval) | Barcelona RX |
|---|---|---|---|
| Layout (pure static math) | `scripts/track/le_mans_layout.gd` `LeMansLayout` | `northern_isle_layout.gd` `NorthernIsleLayout` | `barcelona_rx_layout.gd` `BarcelonaRxLayout` |
| Scene root (orchestration) | `scripts/track/le_mans.gd` + `scenes/track/le_mans.tscn` | `northern_isle.gd` | `barcelona_rx.gd` |
| Dresser (props) | `le_mans_dressing.gd` `LeMansDressing` | `oval_dressing.gd` `OvalDressing` | `rx_dressing.gd` `RxDressing` |
| Ground | `LeMansTerrain` height field (SRTM far field + road corridor) in 512 m tiles + skirt + verge, world-space shader | Terrain3D bank-aware bake | Terrain3D bake, two blend sides |
| Layout suite / scene suite | `test_le_mans_layout.gd` / `test_le_mans_track.gd` | `test_northern_isle_layout/track/dressing/barriers.gd` | `test_barcelona_rx_layout/track/dressing/barriers.gd` |

Read first (do not duplicate them): `docs/plans/track_le_mans_no_chicane.md`
(§3 geometry, §4 architecture, §7 gotchas), `docs/plans/le_mans_visual_realism_plan.md`
(§8 = what shipped and why), `docs/HANDOFF_BARCELONA_RALLYCROSS.md` (§2 contract,
§7 layout-bake trap), `docs/plans/track_northern_isle_speedway.md`,
`docs/research/gt7_le_mans_visual_realism.md`, `docs/GDUNIT_GATE.md`.
Project rule: run `graphify query "<question>"` before grepping; `graphify update .`
after code changes.

## 1. Layout from real data

- Source a centerline (OSM ways, published length, landmark chainages). OSM traps
  already paid for at Le Mans: exclude pit ways (`/Pit/i`) and `*_link` ways;
  derive named windows AFTER route surgery (pre-splice name arrays misalign).
- Pipeline (`LeMansLayout`): control anchors (world XZ + chainage) → subdivide legs
  longer than `MAX_ANCHOR_SPACING_M` → dense closed Catmull-Rom (`DENSE_STEP_M`) →
  resample to `TOTAL_POINTS` uniform-arc points → rescale to the published
  perimeter → Y from a per-point bank profile (`build_bank_profile()`).
- Expose: `build_centerline()`, `build_bank_profile()`, `spacing()`,
  `arc_at_chainage(ch)`, `frame_at_arc(s)` (`center/forward/...`),
  `point_at_arc`, `start_line_arc()`, `grid_arc()`, `checkpoint_indices()`,
  `sharp_corner_chainages(min_turn_deg)`, `LANDMARK_*` constants.
- Keep it deterministic and scene-free; the scene's `_generate_road_points()`
  must return the same array (the OFF-TREE probe used by
  `scripts/ui/track_layout_source.gd`).
- Layout suite asserts: closed loop, perimeter ± tolerance, no crossings or
  reversals, winding, determinism, landmark chainages ± tolerance. Sample densely —
  Catmull-Rom overshoot at tight notches only shows at fine sampling.
- Laps: checkpoints count by presence, so put the grid OFF every checkpoint and make
  the start line the LAST checkpoint in travel order, then prove lap 1 / lap N
  distances with index-driven stub cars (never wall clock).

## 2. Registry, scene, menu pins

- `scripts/track/track_registry.gd` `tracks`: `display_name`, `scene_path`,
  `laps_default`, `difficulty`, `circuit_type`. Add the id to
  `tests/test_track_system.gd`.
- `pins` is a separate many-to-one table; pins are load-bearing —
  `test_race_menu_map.gd` checks counts, WORLD ≥ 30, every layout ≥ 3 pins,
  ≤ 50 % ownership, first three pins Israeli. Repoint/add pins deliberately.
- Re-run the preview bake after registering (else `test_race_layout_preview.gd`
  goes red): `--headless -s res://tools/gen_track_layouts.gd` →
  `resources/ui/track_layouts/<id>.json`, then import probe.
- Scene node set: root script, `RoadNetwork` child (`scripts/world/road_network.gd`;
  the `"road_network"` group is how minimap, pause map and `SurfaceRegistry` find
  the road), `Dressing` child, `PlayerCar`, the four cameras, `Sun`
  (`sun_driver.gd`), `WorldEnvironment`, `PauseMenu`, `HUD`.
- `_ready` order: centerline → ground → road (`RoadDef.make(tier, points, id,
  closed, width, surface, rail_side)`; `def.bank_angles`, `show_lane_dividers`) →
  checkpoints → foliage → dressing → `RaceManager.set_rival_centerline` → spawn.
  Export gates `build_own_ground / build_foliage / build_dressing /
  reposition_player` so a lean zone scene can reuse it.

## 3. Dresser pattern

- Self-contained class per track (never extend another track's dresser).
  `configure(points, banks, width, height_provider)` then `build()`; no scene
  reads, no RNG, no clock — every placement from arc/chainage math or an integer
  hash, so tests can assert exact counts and bit-identical rebuilds.
- Kinds pipeline: `KIND_*` string → `_meshes[kind]` + `_record(kind, xform[, colour])`
  → `_flush(kind)` builds MultiMeshInstance3D chunks (400 m cells, per-kind
  `VIS_RANGE`, `NO_SHADOW_KINDS`, `use_colors`). Query API: `count_of`,
  `transforms_of`, `origins_of`, `prop_mesh`, `dropped_kinds`.
- **Trap:** a kind's instance count is the SUM over its chunk children — use
  `count_of()` / `_transforms`, never `get_child(0).multimesh.instance_count`.
- `_station(s)` must INTERPOLATE between centerline points: snapping a 5 m pitch to
  2.84 m points gaps/overlaps every barrier segment.
- Merge geometry per material into one surface (`_acc_*` + `_mesh_from`); a BoxMesh
  face samples only one cell of its 3×2 UV atlas, so textured faces are quads.
- Use `_clear_of_road(p, r)` (grid of the centerline) for anything placed far
  out — long circuits fold back on themselves — and keep props on the ground plane.
- No trademarks anywhere: neutral, un-lettered banners and boards; the scene suite
  scans node names / Label3D text for brand tokens.
- Budget every kind in the scene suite (`is_greater` bands, exact where fixed).

## 4. Surfaces and grip

- `scripts/vehicle/surface_registry.gd`: `SURFACE_GRIP` table, `classify()`,
  `build_classifier()` (what `vehicle_physics.gd` uses) and zone polygons
  (`add_zone(poly_xz, key)`, `clear_zones()`, `classify_zone_at(pos)`), checked
  BEFORE the road-distance rule.
- Register trap/run-off polygons only while the dresser is in the tree (Le Mans:
  `_register_zones()` in build/`_enter_tree`, `clear_zones()` in `_exit_tree`) —
  zones are static global state and must never leak onto another map. Zones are
  per-owner: `add_zone(poly, key, owner)` / `clear_zones(owner)` / `zone_count(owner)`;
  the owner-less `clear_zones()` still wipes everything (legacy), so new code should
  pass its own owner tag and a track can never clear another's zones.
- **Mixed-surface circuits** (Barcelona RX: ~60 % asphalt / ~40 % dirt): ONE closed road
  with `RoadDef.point_surfaces` (one `Surface` per centerline point = the segment that
  starts there; wrong size = ignored). Author the loose ranges ONCE as chainage data
  (`BarcelonaRxLayout.DIRT_SECTIONS` -> `build_surface_profile()`); every consumer reads
  that table: `TrackBuilder` (mixed material `shaders/road_mixed_surface.gdshader`,
  vertex COLOR.r = loose weight with a 24 m dirt spill downstream of an exit and a 6 m
  dust lead-in, UV.x = lateral, UV.y = arc), `SurfaceRegistry` (the nearest segment's
  surface via `nearest_road_lookup()["seg"]` -> `ROAD_SURFACE_KEYS`; on the carriageway
  the segment wins, the verge keeps the TIER rule), and the ground bake (verge colour).
  A mixed road skips the 1 m tier edge strips and lane dividers (the shader paints the
  edge lines on asphalt only). AI: `ai_controller._corner_grip` takes the lower of the
  surface under the car and at the corner lookahead, so cars brake for a dirt corner
  while still on tarmac (asphalt = 1.0, other tracks unchanged).
- A DIRT-tier road with NO profile still gets the dark matte DIRT look
  (`TrackBuilder.tier_surface_albedo/roughness`, triplanar noise detail); grip stays the
  tier's GRAVEL (do not remap `TIER_SURFACE`).
- Visuals and physics from one polygon: the zone is the ribbon mesh's own rows.
- Grip decisions are contracts: Barcelona dirt = GRAVEL grip via `TIER_SURFACE`
  (do not remap the tier); Le Mans traps = SAND (0.82 / 0.76).

## 5. Barriers and colliders

- Visual barriers live in the dresser (Le Mans: full-lap W-beam armco following
  `barrier_offset(s, side)`, which moves out behind traps).
- Physical collision options: `RoadDef.RailSide` rails (TrackBuilder only adds rail
  collision with a junction gap list), or explicit box-chain colliders as in
  `barcelona_rx.gd::_build_barrier_colliders` (gated by
  `build_barrier_colliders`). Le Mans barriers are visual only (v1 decision).

## 6. Materials, environment, quality presets

- `LeMansSurfaces` (`scripts/track/le_mans_surfaces.gd`) + `shaders/le_mans_*`:
  one seamless noise sampled in world space at several scales gives macro
  variation with no UVs; surfaces that meet share
  `le_mans_ground_inc.gdshaderinc` so blend edges are seamless.
- Winding: Godot front faces are clockwise (seen from above
  `(v1-v0).cross(v2-v0).y < 0`). On `cull_disabled` materials a visible back face gets a
  flipped normal and renders near-black — build strips with
  `LeMansSurfaces.append_quad_up/append_quad_facing`. `TrackBuilder` had exactly this bug
  (every TrackBuilder road rendered near-black); fixed: `_append_up_quad` is the single
  index order for the road strip, edge lines, dashed dividers and the trimesh collision,
  and vertex normals follow the bank/slope (`_frame_normal`). Guarded by
  `test_track_builder_winding.gd` (all triangles face up, visual strip == collision
  triangles, front-face ray hits). Le Mans still uses its own visual strip.
- `ARRAY_COLOR` is stored 8-bit: read-backs of vertex colour need a 1/255 tolerance.
- Scene-owned: sky (custom `le_mans_sky.gdshader`, no HDRI in repo), fog density,
  sun scatter, aerial perspective. Preset-owned (rewritten on every scene load by
  `SettingsMenuScript.apply_quality_preset`): tonemap, SSAO/SSR/SDFGI, glow,
  volumetric fog toggle, shadow distance/cascades, MSAA/TAA/scaling — don't set
  these in the scene and expect them to stick.
- Forward+-only features (decals, SSAO/SSIL/SDFGI, auto-exposure) get a preset key
  in `scripts/ui/settings_menu.gd` `QUALITY_PRESETS` (e.g. `decals_enabled`:
  Low off). `apply_quality_preset` is **static**: it cannot call `get_tree()` /
  `is_inside_tree()` (that compile error broke `game_state.gd` loading — 53 gate errors) —
  pass the scene root as a parameter.
- Decals: generated textures (no texture = renders nothing), `cull_mask` = a layer
  only road/ground carry (Le Mans `DECAL_LAYER`, bit 11) so cars never get painted,
  distance fade on.

## 7. Performance rules

- Long tracks make O(track) per-frame work explode (commit `793342e`: 8 cars on
  13.6 km cost 25 ms/frame in `nearest_road_lookup` alone). Anything called per
  physics frame per car must be indexed: `RoadNetwork` spatial grid,
  `PointGridIndex` (`scripts/util/point_grid_index.gd`) for AI waypoints / gap
  tracker, sliced minimap redraw. Zone classifier: bounding-rect reject first.
- No new `_process` work for dressing; MultiMesh + chunks + visibility ranges;
  unshadowed far kinds; build-time cost stays well under a second (Le Mans
  dressing ~0.27 s).
- Measure with `tools/le_mans_visual_capture.gd` PERF lines (per view: avg/p95 ms,
  primitives, draw calls) before and after, per preset; `test_perf_gate.gd` guards
  the open world (read its `[perf_gate] mode=` line).

## 8. Gates (under the shared Godot lock)

- One Godot process at a time on this machine, shared with other agents:
  `mkdir "D:/Temp/claude/d--AI-Projects-UltraDrive/godot.lock"` before ANY Godot
  run (import, suites, captures); if it fails, wait and retry; `rmdir` when done.
  Never kill a Godot process you didn't start.
- Resolve the console binary via `godot_path.bat` (`GODOT_EXE_CONSOLE`); from Git
  Bash call the bat by absolute path or pass `--godot` to the runner.
- Import probe: `--headless --import .` → zero `SCRIPT ERROR`/`Parse Error`
  (Terrain3D `double_slider.gd` editor line is benign).
- Touched suites: `py tools\gdunit_parallel.py -j 2 --only test_<track>_track.gd,...`
  (comma list is fine for `--only`, never for raw gdUnit `-a`). Compare the case
  count with `grep -c "^func test_"` — a suite aborts at its first failure.
- Full gate: `py tools\gdunit_parallel.py -j 4` (hold the lock for the whole run).
  Take a baseline on the tree BEFORE your change and diff the failing-case lists
  from `reports/parallel/merged-results.xml` — don't gate on a hard-coded total.
- Warnings are errors: no `:=` from Variant (dictionary/untyped array access), no
  shadowing built-ins (`len`) or members.

## 9. Capture + critique loop

- `tools/le_mans_visual_capture.gd` (windowed, NOT `--headless`):
  `<console exe> --path . -s res://tools/le_mans_visual_capture.gd -- --tag=x --preset=1`
  → `.vision/captures/lemans_x_<view>.png` + PERF lines. It uses its own Camera3D
  placed from `frame_at_arc` (teleporting the player RigidBody does not work) and
  applies the preset like `GameState` does. Copy it per track; add close-up views
  (`height`, `out`, `ahead`, `look_out`, `look_h`).
- In `-s` scripts, autoload identifiers don't resolve at compile time — `load()`
  scripts that reference autoloads at runtime instead of `preload`, and never NAME a
  class (`VehiclePhysics`, ...) whose script uses an autoload (test `node is RigidBody3D`).
  Violating this makes `vehicle_physics.gd` fail to compile ("Identifier not found:
  RaceManager"), the player car scene instantiates broken, and `TrafficSpawner._spawn_vehicle`
  then logs a null-instance error EVERY physics frame forever (the 2026-10-22 open-world
  capture "hang" — a harness bug, not a game regression).
- `tools/track_visual_capture.gd` is the generic capture tool (any TrackBuilder scene):
  `-s res://tools/track_visual_capture.gd -- --scene=res://scenes/... --name=x --tag=before
  --out=<dir> [--arcs=a,b,c] [--views=N] [--warmup=N] [--max_wall_s=240]`. It has a
  fail-fast watchdog (Logger): any compile error, the same error repeated 25x, or the
  wall-clock cap aborts with `CAPTURE ABORT` and exit 3. A frozen main loop never reaches
  it, so ALWAYS wrap the run in a shell `timeout` too. Open-world views start at the road
  point nearest the player, clamped so every station stays on the road.
- **Critique = Claude opening the PNGs with the Read tool. Never Ollama or Gemini**
  (user rule; `tools/ollama_vision.py` is disabled). Judge against the five tells in
  the research doc: uniform surfaces, no wear layer, thin trackside density,
  faceted horizon, flat atmosphere. Capture before, fix the worst issue, recapture,
  and check Low and High presets too.

## 9b. Elevated tracks (Le Mans, real SRTM profile)

Worked example: Le Mans carries 36.8 m of real relief (Dunlop climb +22 m, Esses and
Tertre Rouge drop, Hunaudieres/Mulsanne undulation, Indianapolis descent, Maison
Blanche low point, rise back to the pit straight). Max grade 4.6 %. One source of truth
feeds the road, the ground and every prop, so nothing floats or sinks.

- **Data (bake once, commit):** `tools/le_mans_fetch_elevation.py` (network, ~45 calls,
  OpenTopoData `srtm30m`, cross-checked against `eudem25m`) writes
  `scripts/track/le_mans_elevation_data.gd` (`PROFILE_CHAINAGES/PROFILE_M` along the OSM
  trace + a 100 m `GRID_M` over the ground plane). The game never touches the network.
  Copy the script per track; mind its projection (the layout's local lat/lon frame).
- **Layout (`LeMansLayout._build_elevation`):** read the profile at each point's own
  chainage LABEL (same arc<->chainage map the landmarks use), then 3 circular box passes
  of +-60 m (`ELEVATION_SMOOTH_*`). SRTM is a surface model and the trace is +-10-30 m
  laterally, so unsmoothed data gives 10 % grades and ski-jump crests; smoothed it
  stays under 5 % and every Hunaudieres crest radius is above ~2,300 m. World Y is
  relative to the smoothed S/F height (`elevation_datum_asl()`), so grid/line heights
  keep their flat-era values. `_make_y = ROAD_BASE_Y + elevation_at_arc + bank lift`.
  API: `build_elevation_profile()`, `elevation_at_arc`, `ground_y_at_arc`
  (= `PLAIN_Y + elevation`, 0.40 m under the road edge at every height).
- **Ground (`LeMansTerrain`, static, built once per process, ~1-2 s):** 16 m grid =
  SRTM far field (3x3 smoothed, minus datum) lerped to the road-ground profile by
  `w(d)` (1 inside 30 m of the centerline, smoothstep to 0 at 120 m: the road sits on
  a cross-level shelf that fades into the real landscape). The SAME array feeds the
  512 m visual tiles (shared edge vertices, same diagonal), one trimesh collider per
  tile (built from the tile mesh) and `height_at(x, z)` (interpolates on exactly the
  drawn triangles). Never sample a second copy of the DEM.
- **Skirt/verge:** top = the road mesh's own edge vertex, bottom = `terrain_height` at its
  foot minus `SKIRT_BURY` (0.3 m): 16 m terrain triangles cannot follow the road edge
  round every curve, so bury the skirt instead of resting it on the ground.
- **Dressing:** `configure(points, banks, width, height_provider)`; the provider is
  `terrain_height` and is asked at the prop's OWN XZ (`_ground_y`), not the road centre.
  Without a provider it falls back to the road-corridor ground (standalone probes).
  Long props lying along the road (armco, fences, hoardings, hedges, panels, kerbs,
  stands) use `_basis_along_pitched`; decals and S/F paint `_basis_span_pitched`;
  banked surfaces `_basis_surface` (re-orthogonalised against the pitched tangent);
  vertical props keep the flat `_basis_along`. Footprint-wide props (trees, buildings)
  are sunk `TREE_BURY` / `BUILDING_BURY` so no corner floats on a slope.
- **Tests (copy):** profile vs real relief by chainage band, grade < 6 %, crest radius
  for 350 km/h at < 0.6 g unload, determinism; terrain == road-ground under the road
  and below every road edge; skirt vertex counts and exact top/bottom; every dressing
  kind within 0.01 m of `terrain_height` at its origin (minus bury); armco pitched on
  the climb; grid spawn above the road; checkpoints at `points[i] + 0.5 m`.
- **Traps:** (1) never drive the road Y from SRTM raw; (2) `LeMansTerrain` statics persist
  across scenes in one process - a test that rebuilds with different inputs must reset
  them; (3) a flat v1 `PLAIN_Y` assumption anywhere (verge, foliage `ground_height_provider`,
  trap meshes) shows up as a floating or buried prop only on the climb - check
  `dunlop_climb`, `esses_descent`, `indy_descent` captures, not just flat views;
  (4) grades this small (<= 4.6 %) read subtly in a 70 deg FOV - judge elevation from
  the aerial view and from long look-aheads, and assert it numerically;
  (5) physics: the player and AI drive on the road trimesh; the terrain trimesh only
  catches cars that leave the road. Probe with a headless script that drives
  `AIController` (load it at runtime, autoloads do not resolve at `-s` compile time).

## 10. Verification checklist

- [ ] Layout suite green (perimeter, crossings, winding, landmarks, determinism)
- [ ] Registry entry + `test_track_system` id list + pins invariants + preview bake JSON
- [ ] Scene suite: road def, checkpoints/lap distances via stub cars, ground/skirt
      coverage, dressing budgets, no trademarks, rebuild determinism
- [ ] Surface zones classify correctly (inside / road / off-side) and only while in tree;
      zones registered under an owner tag; mixed surface read from ONE chainage table
- [ ] Road top is lit asphalt in captures (not near-black) — winding suite green
- [ ] Forward+-only features gated per preset; Low still reads
- [ ] Import probe clean; touched suites green with full case counts; full gate
      diffed against a same-day baseline
- [ ] Before/after captures at every landmark + PERF numbers per preset, critiqued
      by reading the images
- [ ] Elevated track: profile smoothed + drivable (grade, crests), terrain/tiles/collider/
      `height_at` from one array, every prop kind on the ground, captures of each climb/drop
- [ ] Plan doc status updated with evidence and honest caveats (no "scan fidelity"
      claims); `graphify update .`; no commits unless asked
