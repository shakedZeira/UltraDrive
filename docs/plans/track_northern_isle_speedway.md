# UltraDrive — Northern Isle Speedway (GT7 track build #1) Plan

> Build **Northern Isle Speedway** — GT7's smallest track (900 m, a flat banked
> left-turn/CCW speedway oval) — as a fully wired UltraDrive track scene:
> TrackRegistry entry, race/checkpoint loop, lap timing + best-lap records,
> banked turns, minimap, and speedway dressing (catch fence, grandstands,
> start/finish gantry, sponsor billboards).
>
> **Written:** 2026-10-14 · **Inputs:** `docs/research/gt7_tracks.md`
> (Northern Isle entry + shortest-tracks ranking), `AGENTS.md`,
> `docs/ROADMAP.md` (capability matrix: GT7 has 121 layouts, we have 2 track
> scenes), `docs/GDUNIT_GATE.md` · **Grounded in:** the live code (read-only
> survey of `scripts/track/*`, `scripts/world/road_network.gd` /
> `road_def.gd` / `prop_scatterer.gd` / `foliage.gd`, `autoload/race_manager.gd`,
> `scripts/race/race_ui.gd`, `scripts/track/track_registry.gd`,
> `scenes/track/mountain_pass.tscn` + `scripts/track/mountain_pass.gd`,
> `scripts/test_circuit.gd`, `tests/suites/test_race_loop.gd`,
> `tests/test_track_system.gd`).
>
> **Two hard rules this plan is written against:**
> 1. **No tech ceiling** (ROADMAP §"No tech ceiling"). Where the oval needs a
>    capability the engine lacks (explicit bank profiles, bank-aware ground),
>    the plan says so explicitly and names the owning file — reuse everywhere
>    else.
> 2. **The GDUnit discipline is a franchise asset.** Every phase names its
>    gate suite; the full-suite gate follows `docs/GDUNIT_GATE.md` (import
>    probe first, `--ignoreHeadlessMode` AFTER the tool-script path, parallel
>    runner `py tools\gdunit_parallel.py -j 4`, never wall-clock assertions).
>    Baseline at plan time: **all-green** (1018 cases, 0 failures — AGENTS.md
>    2026-10-04 parallel run). New suites must leave it green.

---

## 1. DESIGN INTENT — why an oval is the right first GT7 track

The track roster is the sharpest content gap vs GT7 (121 layouts vs our 2
track scenes). The honest blocker to cloning more of them is that every GT7
circuit we'd want (Tsukuba, Deep Forest, Trial Mountain…) is *authored road
geometry with road-adjacent infrastructure* — banked surfaces, catch fencing,
grandstands, gantries — which UltraDrive's track tooling has never had to do
at circuit scale. Northern Isle Speedway is the cheapest possible way to
close that tooling gap, because it is the simplest possible GT track:

- **Simplest geometry.** Two straights + two 180° arcs — a stadium oval can be
  generated analytically from three constants (R, L, W) with no spline
  authoring, and it is small (~900 m perimeter, ~380 × 135 m footprint), so
  every bake, test and playtest iteration is fast.
- **Exercises banking end-to-end.** It is the first track that *requires*
  banked turns (GT7's Northern Isle is a speedway-style banked oval). That
  forces the one real new capability — a deterministic, spacing-independent
  **bank profile** through `RoadDef` → `TrackBuilder` (mesh AND trimesh
  collision) — plus the terrain consequences of banking (the outfield
  embankment). Every future banked GT7 track (Daytona, High Speed Ring,
  Blue Moon Bay, Route X) inherits this work.
- **Exercises the closed checkpoint loop at minimum scale.** A 900 m lap with
  8 checkpoints is the tightest case for checkpoint ordering, lap-line
  placement, lap timing and results (short laps → many laps per race →
  checkpoint re-arm paths get hammered).
- **Tests the speedway-infrastructure vocabulary** (fence/grandstand/gantry/
  billboards) that every purpose-built circuit needs, reusing the CC0 Kenney
  kit already in `assets/track_props/` (Phase A of the ROADMAP).
- **Direction check (ROADMAP).** Matches the capability-matrix track gap and
  feeds §1.4 (event-type framework consumes `TrackRegistry`), §2.2
  (time-attack: best-lap records already key off the registry id) and Phase A
  (track props). Nothing here trims ambition — it is the first step of the
  "121 layouts" row.

---

## 2. TRACK LAYOUT SPEC (the number source of truth)

All values live as constants in `scripts/track/northern_isle_layout.gd`
(P0). Nothing else may hardcode them.

| Quantity | Value | Derivation |
|---|---|---|
| Shape | Stadium oval: 2 straights + 2 × 180° left turns | GT7 Northern Isle character |
| Direction | CCW / left-turn (NASCAR-style) | turn centers sit LEFT of travel; increasing point index = travel direction |
| Turn radius `TURN_RADIUS` | **60.0 m** | chosen |
| Straight length `STRAIGHT_LENGTH` | **261.5 m** (BOTH — a stadium oval's straights are necessarily equal, they span the same turn-center distance) | `2L + 2πR = 523.0 + 376.99 = 899.99 m ≈ 900 m` ✓ |
| Track width `WIDTH` | **16.0 m** | 3–4 NASCAR-style grooves |
| Point count `TOTAL_POINTS` | **304** (uniform arc-length spacing ≈ 2.96 m) | 304 = 8 × 38 so checkpoints land on exact points |
| Checkpoints | 8, at `points[i * 38]`, indices in travel order | `CP_STRIDE = 38` |
| Banking `BANK_MAX_DEG` | **18.0°** (speedway-style; tunable 12–20°, see risks) | constant through the middle of each turn |
| Bank transition `TRANSITION_ARC` | **40.0 m** of arc at each end of each 188 m turn (sine smoothstep 0→18°); straights stay perfectly flat | real speedways bank inside the turn, not the straight |
| Corner numbering | **T1** = first 90° of turn A, **T2** = second 90°, **T3/T4** = turn B in travel order (CCW oval convention) | expose `corner_names` for HUD/map later |
| Centerline Y | `ROAD_BASE_Y (0.15) + (WIDTH/2)·\|sin θ(s)\|` | **banking pivots on the inner edge**: the left (infield) edge rides at exactly +0.15 m everywhere, the outer edge rises to ≈ 5.1 m at apex. Straights: both edges +0.15 m |
| Ground plain | `PLAIN_Y = −0.25` | 0.4 m washbed below the road base — the mountain_pass precedent (`WASHBED_DEPTH` band 0.4–0.8) |
| Outfield embankment | `EMBANK_RUN = 22.0 m` from the outer road edge down to plain (only meaningful where θ > 0) | the bank sits on a berm; infield needs no berm because the inner edge stays at 0.15 |
| Infield shoulder | `SHOULDER_RUN = 6.0 m` from inner edge down to plain | same visual language as the mountain-pass shoulder |
| S/F line & gantry | at checkpoint **index 7** (`points[266]`, arc 787.4 m — 18.25 m after T4 exit, on the front straight) | see §2.1 for why the line is the LAST checkpoint |
| Starting grid | on checkpoint **index 0** (`points[0]`, mid front straight, 112.5 m downtrack of the line) | lap 1 is 787 m, then full 900 m laps |

CCW sign convention (must be asserted in a test, mirrors the existing
right-turn test `test_track_builder_banking_lowers_right_edge_on_right_turn`):
in the turns, `cross(t1, t2).y > 0` → `TrackBuilder._frame` produces a
**negative** signed angle → the LEFT (infield) edge goes down, right
(outfield) edge up. The bank profile array therefore carries **signed
radians** (negative = left turn), in the exact sign space `_frame` already
uses.

### 2.1 Checkpoint/lap-line contract (the trap this section exists to defuse)

`LapCounter.update()` accepts only `expected = (_last + 1) % total`, and a lap
ticks when `_last == total − 1`. `Checkpoint._counted` is cleared only by
`reset()`, which fires on `lap_completed` (and `start_race`). Consequences
that the layout MUST obey — the same ones `mountain_pass.gd`/`test_circuit.gd`
already obey implicitly:

1. **Index 0 must be the first checkpoint crossed after the green.** The grid
   sits ON checkpoint 0 (spawn = `points[0]`, precedent `_reposition_player_to_start`).
   The car overlaps cp0 at `start_race`, it is counted with `_last = 0`, and
   progression runs 1 → 2 → … → 7 from there.
2. **A checkpoint crossed out of sequence is SPENT forever** (marked
   `_counted`, progression ignores it, nothing re-arms it until the next lap
   tick). This is the deadlock: if the car ever crosses checkpoint 7 before
   0…6, lap 1 can never complete. Two specific traps:
   - Do NOT place the grid behind the start/finish line if the line is
     checkpoint 7 — the green would cross 7 first and soft-lock the race.
   - Checkpoint 0's detection box must cover the whole starting grid (use a
     16 × 8 × 16 box, road-width), otherwise a rival spawned in a back row
     (`RaceManager.RIVAL_GRID_ANCHOR_AHEAD`) misses cp0 and its LapCounter
     stays at `_last = −1` all race.
3. **The lap line is checkpoint 7 (the last index), which is placed ON the
   S/F gantry.** Laps tick exactly under the gantry; the reset-on-lap then
   re-arms cp0 for the next pass. The trade-off (both shipped tracks have the
   same shape): the grid sits 112.5 m *past* the line, so lap 1 is 787 m and
   the green flag falls with the gantry behind the player. This is consistent
   — timing, gantry and paint all live at cp7 — and cheap to re-tune later
   (both are just offsets; see open questions).
4. `Checkpoint.is_start_line = true` on index 7 (semantic marker; no logic
   reads it today — the flag exists in `checkpoint.gd`).

---

## 3. SCENE / SCRIPT ARCHITECTURE

### New files

| File | Kind | Purpose |
|---|---|---|
| `scripts/track/northern_isle_layout.gd` | `class_name NorthernIsleLayout extends RefCounted` (pure, static) | THE geometry source of truth: `build_centerline() -> Array[Vector3]`, `build_bank_profile() -> Array[Vector3]`... **no** — `build_bank_profile() -> PackedFloat32Array` (signed radians, one per point), `checkpoint_indices() -> PackedInt32Array`, `corner_names() -> Array[String]`, `perimeter() -> float`, plus the constants above. Deterministic, zero scene deps, headless-safe. |
| `scripts/track/northern_isle.gd` | root script of the track scene (mirrors `mountain_pass.gd`) | `_ready()` orchestration: ground bake → `RoadNetwork` registration → checkpoints → foliage → dressing → player spawn. Export gates `build_own_ground` / `build_foliage` / `build_dressing` / `reposition_player` (all default true, `mountain_pass` pattern). Exposes `road_points: Array[Vector3]` and `bank_profile: PackedFloat32Array` as members **for tests** (like `mountain_pass.road_points`). Bank-aware ground bake lives here (`_build_ground`, `_ground_height`, `_build_distance_field` — same coarse-field/exact-scan structure as `mountain_pass.gd` but with the berm rule below). |
| `scripts/track/oval_dressing.gd` | `class_name OvalDressing extends Node3D` | Deterministic speedway dressing. `configure(centerline: Array[Vector3], bank_profile: PackedFloat32Array, width: float, terrain_height: Callable)` then `build()`. Catch fence + barrier line + grandstands + S/F gantry + S/F paint + billboards (§5). |
| `scenes/track/northern_isle.tscn` | track scene | Same node set as `scenes/track/mountain_pass.tscn`: root (`northern_isle.gd`), `PlayerCar` (instance of `scenes/vehicle/player_car.tscn`), `ChaseCamera`/`OrbitCamera`/`HoodCamera`/`CockpitCamera` (the four camera scripts), `Sun` (`DirectionalLight3D` + `scripts/world/sun_driver.gd`), `WorldEnvironment`, `PauseMenu` (`scenes/ui/pause_menu.tscn`), `HUD` (`scenes/ui/hud.tscn`) — plus **`RoadNetwork`** (type Node + `scripts/world/road_network.gd`), which `mountain_pass.tscn` does NOT have. |
| `tests/suites/test_northern_isle_layout.gd` | GDUnit suite | P0 gate (pure math). |
| `tests/suites/test_track_bank_profile.gd` | GDUnit suite | P1 gate (TrackBuilder/RoadDef). |
| `tests/suites/test_northern_isle_track.gd` | GDUnit suite | P2/P3 gate (scene, checkpoints, race flow, ground). |
| `tests/suites/test_northern_isle_dressing.gd` | GDUnit suite | P4 gate (dressing). |

### Modified files

| File | Change |
|---|---|
| `scripts/world/road_def.gd` | **NEW (additive, defaults preserve every existing road):** `@export var bank_angles: PackedFloat32Array = PackedFloat32Array()` (signed radians per point; empty = legacy `banking` path) and `@export var show_lane_dividers: bool = true`. |
| `scripts/track/track_builder.gd` | **NEW capability (bank profile).** New member `var _bank_angles := PackedFloat32Array()`; `build_track()` sets it from `def.bank_angles` **only when `def.bank_angles.size() == points.size()`** (else empty = legacy). `_frame()` gains one precedence branch: `if _bank_angles.size() > 0: angle = _bank_angles[i]` else the existing `banking × curvature` math, untouched. Because `_frame` is the single frame supplier for `_build_mesh`, `_build_edge_mesh`, `_build_dashed_edge_mesh`, `_build_rail_mesh` and the trimesh collision build, ONE branch upgrades surface, edges, rails and collision consistently — and `configure_rails()` rebuilds read the same member. Also: skip the lane-divider loop when the def says `show_lane_dividers == false`. |
| `scripts/track/track_registry.gd` | Add the track: |
| | `"northern_isle": { "display_name": "Northern Isle Speedway", "scene_path": "res://scenes/track/northern_isle.tscn", "laps_default": 5, "difficulty": "D", "circuit_type": "OVAL" }` — `track_select.gd` builds cards from the registry, `race_ui._resolve_track_id()` reverse-looks the scene path up for best-lap records (`BestLapRecords` keyed `"northern_isle"` + car class), so both flows pick it up with zero extra plumbing. `circuit_type` is display text only. `laps_default: 5` ≈ a 3–4 min race at ~35–45 s laps (open question below). |
| `tests/test_track_system.gd` | `test_registry_contains_expected_tracks` asserts `contains_exactly(["oval", "mountain_pass"])` — **must be updated** to include `"northern_isle"` (this is the one hard-coded registry assertion in the tree; the card-count tests are dynamic and adapt). |

### What is reused (no new code)

- **Race flow:** `RaceManager` autoload (`queue_race` ← `track_select._on_play_pressed`,
  first-frame commit in `race_ui._process`, checkpoint group pooling,
  standings, countdown, results overlay), `LapCounter`, `Checkpoint` —
  untouched. The scene only has to place checkpoints in travel order (§2.1).
- **Road/mesh pipeline:** `RoadNetwork.add_road_def()` builds the
  `TrackBuilder` (surface strip, red/white ARTERIAL edge lines, rails, trimesh
  collision) from one `RoadDef`; `Tier.ARTERIAL` gives rail-both-sides +
  red/white edges, which read exactly like speedway curbing.
- **Minimap + pause map:** a `RoadNetwork` child auto-registers in the
  `"road_network"` group on its `_ready` → `MapRoads.resolve_road_source()`
  (used by `minimap.gd` in the HUD and `world_map.gd` in the pause menu)
  finds it and draws the oval. This is a small upgrade over `mountain_pass`
  (whose standalone scene has no road source, so its minimap roads silently
  no-op).
- **Surface grip:** `SurfaceRegistry` resolves the `"road_network"` group →
  ARTERIAL tier → asphalt grip table → `tire_model.gd`. Without the group it
  would fall back to its default; with it, the classification is real.
- **Foliage:** `Foliage` instance with `ground_height_provider` (the
  `mountain_pass._make_ground_height_provider` pattern) and — new for this
  scene — `foliage.road_network = network`, which arms its existing
  `_road_clear_of()` rejection (reuses `PropScatterer.is_clear_of_road`,
  clearance = halfwidth + 3 m = 11 m). Annulus: `radius = 240.0`,
  `inner_clear_radius = 0.0` (uniform scatter; the road rejection does the
  clearing — the radial inner-clear does NOT work for an oval, trees would
  otherwise land in the turns' infield at r > 78 m).
- **Prop assets:** `assets/track_props/*.glb` (CC0 Kenney kit, Phase A):
  `finish_gantry.glb`, `grandstand.glb`, `racing_grandstand.glb`,
  `track_barrier.glb`, `racing_barrier_red.glb`, `racing_pylon.glb`,
  `racing_tent.glb`, `light_pole.glb`, `racing_flag_checkers.glb`; optional
  `assets/buildings/building_pit_garage.glb`. Mesh-harvesting GLBs for
  MultiMesh reuse follows the `prop_scatterer.gd` `_load_prop_mesh` /
  `_collect_mesh_instances` pattern (copy the ~30-line loader into
  `oval_dressing.gd`; extracting a shared static is optional).
- **Zone precedent:** export-gate booleans on the root script keep a future
  lean `scenes/world/regions/northern_isle_zone.tscn` (the
  `mountain_pass_zone.tscn` pattern, `build_own_ground/build_foliage/
  reposition_player = false`) trivial to add later — explicitly OUT of scope
  here (open question).

### Ground bake rule (bank-aware, replaces the mountain-pass washbed logic)

Per texel (world XZ), with `d` = distance to centerline, `s` = signed
lateral offset (positive = outfield/right, relative to travel), `θ(s)` =
bank profile interpolated at the nearest arc position, `PLAIN_Y = −0.25`,
`ROAD_BASE_Y = 0.15`:

- `|s| ≤ W/2` (under the road): road surface height `center_y + s·sin θ`
  (exact, so nothing ever pokes through).
- Infield (`s < −W/2`): `lerp(ROAD_BASE_Y, PLAIN_Y, smoothstep(0, SHOULDER_RUN, |s| − W/2))`
  — note the inner edge is *always* 0.15 by construction, so this is a plain
  6 m shoulder everywhere.
- Outfield (`s > W/2`): `lerp(edge_outer_y, PLAIN_Y, smoothstep(0, EMBANK_RUN, s − W/2))`
  where `edge_outer_y = ROAD_BASE_Y + W·|sin θ|` — the berm. On straights
  `edge_outer_y = 0.15`, so the rule degenerates to the same gentle shoulder.
- Beyond `W/2 + max(run) + EXACT_SCAN_MARGIN`: `PLAIN_Y` (early-out via a
  coarse `FIELD_STEP = 8` distance field, `mountain_pass._build_distance_field`
  structure verbatim).

Bake container: `Terrain3D` node named `"GrassGround"` (historical name other
code/tests look up), **512 × 512 image @ 1 m/px imported at
`Vector3(-256, 0, -256)` with `region_size = Terrain3D.SIZE_256`** — the
anchor −256 is an exact multiple of 256 (the `import_images()` snap rule from
AGENTS.md) and the pane covers the whole footprint (±191 × ±71 m) plus berm
and shoulder runs with margin. Colour image: grass tint + height shade
(mountain-pass `GRASS_COLOR * shade` pattern). `material.show_checkered =
false`, `show_colormap = true`.

---

## 4. PHASED IMPLEMENTATION (dependency order, each phase verifiable)

Ordered by dependency; T-shirt effort for 1–2 people + sub-agents. P0/P1 are
pure-data and can run in parallel behind a fixed API contract (the P0 outputs
are exactly the `RoadDef.bank_angles` / centerline signatures P1 consumes).

### P0 — Layout generator (pure)
- **What:** `scripts/track/northern_isle_layout.gd` — analytical stadium-oval
  generator: uniform arc-length walk (`s → (x, y, z)` through straight/arc
  spans), bank profile (sine smoothstep over `TRANSITION_ARC` at each end of
  each turn), centerline lift `0.15 + (W/2)·|sin θ|`, checkpoint indices,
  corner names, perimeter.
- **Why:** one deterministic source of truth for geometry + banking; every
  later phase (mesh, ground, dressing, tests) consumes it and can be tested
  against it without a scene.
- **How:** straight spans at z = ±R, turn centers at (±L/2, 0); signed bank
  angle negative (left turn) in `_frame`'s sign space; TOTAL_POINTS 304.
- **Effort:** S.
- **Test-gate:** `tests/suites/test_northern_isle_layout.gd` —
  perimeter ∈ [895, 905]; chain closes (`points[0].distance_to(points[303])`
  ≈ one spacing); uniform spacing (max/min segment length within 2 %);
  ALL left edges at exactly `ROAD_BASE_Y` (i.e. `p.y − (W/2)|sin θ| = 0.15 ± 0.001`);
  bank profile zero across every straight, ≈ 18° at both turn apexes,
  monotone through the transitions; direction is CCW/left (per-turn
  `cross(t1,t2).y > 0`); checkpoint indices 0,38,…,266 with cp7 on the front
  straight 15–25 m past the T4 tangent point; determinism (two builds are
  `is_equal` element-wise).

### P1 — Bank-profile capability in RoadDef/TrackBuilder (shared tooling)
- **What:** `RoadDef.bank_angles` + `RoadDef.show_lane_dividers`; the
  `_bank_angles` member + `_frame` precedence branch in `track_builder.gd`;
  lane-divider suppression.
- **Why:** NEW capability. Today `RoadDef.banking` is a curvature multiplier
  (`angle = clamp(curvature,−1,1) × banking` where curvature is the *per-point
  tangent sine*) — the resulting bank angle depends on point spacing, its
  transition is one segment wide, and the centerline Y must be reverse-derived
  from the same curvature math. A per-point signed profile is
  spacing-independent, eases over `TRANSITION_ARC`, and gives the layout
  builder a single source for both mesh rotation and centerline lift.
- **How:** additive member + ONE branch in `_frame`; default (empty profile)
  is byte-identical legacy behaviour, so `test_road_graph`,
  `test_multi_lane_rails`, `test_highway_access` etc. cannot shift.
  `show_lane_dividers = false` skips only the divider-mesh loop (speedways
  have no dashed lane lines; edge lines stay).
- **Effort:** S.
- **Test-gate:** `tests/suites/test_track_bank_profile.gd` — profile overrides
  the curvature path (build a 3-point left arc with a constant profile, assert
  left edge lower / right edge higher — mirror image of
  `test_track_builder_banking_lowers_right_edge_on_right_turn`); a zeroed
  profile keeps the strip flat; a wrong-sized profile array is ignored (legacy
  path); `show_lane_dividers = false` removes `LaneDivider*` children while
  edge meshes and rail counts stay; plus **existing** `test_road_graph` /
  `test_multi_lane_rails` green (regression proof for the shared file).

### P2 — Scene skeleton + checkpoints + registry (the race loop)
- **What:** `scenes/track/northern_isle.tscn` (mountain_pass node set +
  `RoadNetwork` child), `scripts/track/northern_isle.gd` with RoadDef
  construction (`RoadDef.make(Tier.ARTERIAL, points, "northern_isle-oval",
  true, 16.0, Surface.ASPHALT, RailSide.BOTH)` + `bank_angles` +
  `show_lane_dividers = false`) → `network.add_road_def(def)`, 8 checkpoints
  (`cp.index = i`, position `points[i*38] + (0,0.5,0)`, BoxShape3D
  16 × 8 × 16, `is_start_line` on index 7, group `"checkpoints"` auto via
  `_ready`), player spawn on cp0 (`_reposition_player_to_start` pattern),
  `RaceManager.set_rival_centerline(road_points)` (harmless today, enables
  §1.6/1.4 rival rosters later), registry entry, `test_track_system.gd`
  registry assertion update.
- **Why:** minimum viable track — selectable, driveable, raceable, timed,
  with asphalt grip and a working minimap (all via existing systems once the
  scene holds a `RoadNetwork`).
- **Effort:** M.
- **Test-gate:** `tests/suites/test_northern_isle_track.gd` (scene-runner,
  `simulate_frames(3)`, `before_test` sets `RaceManager._checkpoints_dirty =
  true` and empties `rival_roster` like `test_race_loop`):
  - scene loads; `road_points.size() == 304`; `PlayerCar` at cp0 ± 1 m,
    not at `Vector3.ZERO`;
  - exactly 8 checkpoints, indices `[0..7]` contiguous, positions match
    `points[i*38]`, group membership holds;
  - `RoadNetwork` found via `get_nodes_in_group("road_network")`, has 1 closed
    def, `nearest_road_distance(spawn) < 8.0`, `is_on_road(spawn)` true
    (surface-grip + minimap prerequisites);
  - `MapRoads.resolve_road_source(scene)` resolves to that network;
  - **closed-loop validity**: script the LapCounter progression — with stub
    cars (checkpoint_stub pattern) feed passes 0→1→…→7 and assert exactly one
    `lap_completed` at index 7 and none elsewhere; feed an out-of-order pass
    (7 before 0) and assert no lap;
  - registry: `TrackRegistry.has_track("northern_isle")`, scene file exists
    (`assert_file`), all five keys present; `race_ui._resolve_track_id()`
    returns `"northern_isle"` when the HUD is instanced in the scene (best-lap
    bucket wiring).

### P3 — Bank-aware ground + foliage
- **What:** `_build_ground()` + helpers in `northern_isle.gd` (§3 ground rule),
  `Foliage` wiring (radius 240, inner clear 0, terrain provider,
  `road_network` set).
- **Why:** the banked turns float (outer edge ≈ 5.1 m at apex, inner edge at
  +0.15); only a bank-aware bake closes the gap under the outer edge (berm)
  while keeping the infield and straights flush. Terrain3D also gives off-track
  collision and colour for the minimap's terrain cells.
- **Effort:** M.
- **Test-gate:** same `test_northern_isle_track.gd` (added cases, or a
  `test_northern_isle_ground.gd` split if it grows): sampling every checkpoint
  and both edges at turn apexes —
  `terrain.data.get_height(inner_edge) ≤ inner_edge.y − 0.05` (no burial,
  no z-fight: road base 0.15 over plain −0.25), and at apex outer edge
  `|terrain − (edge_y − embank ramp)| < 0.3` at the edge sample (berm meets
  the road, no visible gap > 0.3 m), plain beyond `W/2 + EMBANK_RUN + 8` ≈
  `PLAIN_Y`; foliage instance counts > 0 and every tree/grass sample ≥ 11 m
  from the centerline (`PropScatterer.is_clear_of_road` — reuses
  `test_dressing_road_clearance` conventions); bake determinism (two runs,
  heights `is_equal_approx` at sampled points).

### P4 — Speedway dressing
- **What:** `scripts/track/oval_dressing.gd` + a `Dressing` child in the
  scene (gated by `build_dressing`), built in `build()` from the centerline /
  bank profile / terrain-height callable:
  1. **Catch fence (outer):** MultiMesh posts (0.12 × 3.2 m box) every 4 m at
     `W/2 + 0.6` (the rail offset) on the outfield side, following the banked
     cross-section (post base on the road edge, y from the frame math), plus
     ONE continuous panel strip mesh between post tops (2.6 m tall,
     `TRANSPARENCY_ALPHA`, dark grey) — procedural, deterministic.
  2. **Barrier line (outer):** `racing_barrier_red.glb` mesh as a 4 m-spacing
     MultiMesh just outside the rails (`W/2 + 2.2`), y from terrain/edge.
  3. **Grandstands:** `grandstand.glb` × 3 along the front straight outfield
     (offset ≈ `W/2 + EMBANK_RUN + 8`, y from terrain, yaw facing track
     center) + `racing_grandstand.glb` × 1 at back-straight midpoint.
  4. **S/F gantry:** `finish_gantry.glb` at cp7, yaw perpendicular to the
     tangent, straddling the 16 m road (verify the GLB's axis/scale at
     implementation — Kenney prop axes are unverified; cars are nose +Z).
  5. **S/F paint:** checker strip (small generated `ImageTexture`, 8 × 2
     checker) on a 16 × 1.5 m quad at cp7 + 0.02 — flat is fine, the line is
     on the straight (θ = 0 there).
  6. **Sponsor billboards:** ~10 quads (4 × 2 m, alternating brand albedos)
     with `Label3D` text children ("ULTRADRIVE", "APEX TYRES", "KENNEY AUTO",
     "GARAGE 51", "NORTHERN ISLE", …) riding the fence line every ~70 m of
     the straights, at 3.5 m.
  7. **Infield / night (cheap wins):** `racing_tent.glb` × 2 + 1 pit garage in
     the infield; `light_pole.glb` × 8 around the outside (unwired for night
     lighting in this phase — open question).
- **Why:** the infrastructure vocabulary every GT7 circuit needs; reuses the
  Phase-A CC0 kit and the MultiMesh patterns of `prop_scatterer.gd`, but
  polyline-precise placement (fence ON the outer edge) is something
  `PropScatterer`'s annulus/roadside samplers cannot express — hence a small
  dedicated builder, not a `PropScatterer` preset.
- **Effort:** M.
- **Test-gate:** `tests/suites/test_northern_isle_dressing.gd` — fence post
  count = `ceil(perimeter / 4)` (±1); every post within `W/2 + 0.6 ± 0.5 m`
  of the centerline in XZ and y ≈ road-edge height at its arc position;
  grandstand count ≥ 4 and each ≥ 11 m clear of the road
  (`PropScatterer.is_clear_of_road`); gantry centered within 2 m of the cp7
  point and its span ≥ track width; billboards ≥ 8, all beyond the fence
  radius; all referenced GLBs load with > 0 vertices (the `test_track_props`
  loader assertions); determinism (two `build()` runs → identical transform
  sets); dressing leaves no node overlapping the road corridor.

### P5 — Race-flow polish & integration pass
- **What:** verify/finish the end-to-end loop in the live scene: countdown →
  5 laps ticking at the gantry → results overlay → best-lap record persisted
  under `("northern_isle", class)` → next-race/return buttons; minimap oval +
  player marker; pause map shows the oval (fast-travel/discovery absent in
  standalone scenes — mountain-pass precedent, must degrade silently);
  optional: a default rival roster via `GridSpawner`/`RaceManager.rival_roster`
  so the grid isn't lonely (note: `RaceManager.configure_default_rivals` now
  builds the production field when `GameState.opponents>0` and the scene has a
  centerline; the HUD seam calls it only if the roster is empty — see
  `docs/plans/match_fh6_gt7_plan.md` §5).
- **Effort:** S.
- **Test-gate:** the P2 suite plus `test_race_results`-style assertions stay
  green; a manual playtest checklist (below) is the real gate for feel items.

### P6 — Full gate, docs, STATUS
- **What:** run the documented headless gate (below), fix anything red, update
  `docs/ROADMAP.md` (capability-matrix "121 layouts" row: "3 layouts —
  oval/NTSC-speedway/…" + a line in the relevant phase notes), and fill the
  STATUS block at the end of this plan.
- **Effort:** S (verification only).

---

## 5. TESTING & GATE STRATEGY (commands are `docs/GDUNIT_GATE.md`'s, restated)

- **Per-phase gates** are the suites named above; they live in
  `tests/suites/` and follow existing conventions: `extends GdUnitTestSuite`,
  `scene_runner(...)` + `simulate_frames(n)` for scene tests, stub cars /
  `checkpoint_stub.gd` for race logic, `assert_that/assert_int/assert_float/
  assert_file/assert_array`, `before_test` teardown that resets
  `RaceManager` state (`_checkpoints_dirty = true`, empty `rival_roster`).
- **GDUnit gotchas that apply here specifically:**
  - GDScript warnings are errors — no `var x := variant_call()`.
  - Vector `is_equal_approx` needs a same-type epsilon arg.
  - A suite aborts at its FIRST failure — write assertions so the most
    diagnostic one runs first; compare "Executed test cases" to the file's
    `func test_` count.
  - Never assert wall-clock (the `test_perf_gate` lesson); bake/load times are
    eyeballed, not gated.
  - `-a` does not accept comma-separated paths; chain runs or run the whole
    `res://tests` tree.
  - Track-select tests must drain `RaceManager.consume_pending_race()` at the
    end (precedent in `test_track_system.gd`).
- **Full-suite gate (P6, orchestrator or a background sub-agent — one Godot
  process at a time, never alongside other feature work):**
  ```
  cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE! --headless --import . 2>&1" | findstr /i "SCRIPT ERROR Parse Error"
  cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE! --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1"
  tools\pick.bat grep "Overall Summary" _gdunit.txt
  ```
  or the parallel runner (`py tools\gdunit_parallel.py -j 4`, PC) and
  `tools\pick.bat grep "Overall Summary" reports\parallel\logs`. Confirm
  `_gdunit.txt` is non-zero bytes before reading it (the GUI-binary
  false-green trap). **Gate = baseline (all-green, 1018 cases at plan time) +
  the new suites green, zero new failures.**
- **Manual playtest checklist (P5):** track select shows "Northern Isle
  Speedway · CLASS D · OVAL"; countdown locks controls; banking feel through
  T1–T4 (car should *want* to hold the line; no wall-snag on the trimesh
  seam); lap label ticks under the gantry; results overlay + best-lap delta;
  minimap shows the oval and the marker rotates correctly; off-track drops
  onto the shoulder/berm without getting stuck (the mountain-pass washbed
  contract); photo mode framing of the bank. Visual-quality review can go
  through `gemini_vision.bat` (screenshot → critique) per AGENTS.md.

---

## 6. OPEN QUESTIONS / RISKS

1. **Bank amount & physics payoff.** 18° is the spec; whether `TireModel`/
   `VehiclePhysics` actually *gain* cornering grip from the banked contact
   normal (vs just tilting the car) is unverified — banked highways
   (`HIGHWAY_BANKING 0.35`) exist but at much lower angles. Gate: playtest
   tune, `BANK_MAX_DEG` is one constant. Watch for rollover feel at S-class
   speeds (downforce + 18° bank).
2. **Centerline-lift ⇄ bank-profile coupling.** The inner edge stays at 0.15
   only because the layout builder computes Y from the *same* θ array the
   mesh consumes. Both live in `NorthernIsleLayout` and a test pins the
   invariant (`p.y − (W/2)|sin θ| = 0.15`), but any future hand-edit of one
   without the other breaks the ground contact — documented in the layout
   header comment.
3. **Grid 112.5 m past the line** (§2.1 rationale). Consistent, but a GT7
   feel wants the grid *behind* the gantry. Cheapest fix later: move the grid
   to the back straight's midpoint… (no — cp0 must be first crossed; the real
   options are (a) accept, (b) unequal checkpoint spacing with a short wrap
   arc around the line, which works but adds 1-frame re-arm subtleties at the
   overlapping boxes). Decision: ship (a), revisit after playtest.
4. **Ground bake cost.** 262 144 texels with coarse-field routing
   (FIELD_STEP 8) + exact 304-segment scan only inside the blend band
   (~72 k texels × 304 segments) — should be low single-digit seconds like
   mountain pass. If slow, bucket the exact scan by segment AABB (the
   `terrain_baker.gd` `_clip_chains` lesson) — noted, not planned.
5. **Flat-shaded banking.** `TrackBuilder._build_mesh` writes `Vector3.UP`
   normals for every vertex, so the banked surface is lit as if flat. Known
   cosmetic issue (banked highways too); fixing normals is a shared-file
   change with visual-regression risk → deferred, logged here.
6. **GLB axes/scales for gantry/grandstand** are unverified (Kenney kit).
   Implementation must check orientation in-editor/playtest; License.txt
   stays CC0 (gate: don't touch it, only read).
7. **`show_lane_dividers` flag** is a tiny shared-surface change; if review
   balks, fallback is accepting one dashed center divider at width 16 (or
   width 14 → `lane_count_for` = 1 → no dividers at all, zero code change —
   14 m is still a plausible speedway width; keep as the zero-risk option).
8. **Open-world presence.** Should the oval also exist inside the open world
   (`northern_isle_zone.tscn` + a connector corridor, `mountain_pass_zone`
   precedent)? Out of scope here; the export gates make it a ~30-line follow-up
   plus a `CorridorPlanner` param.
9. **`laps_default` = 5** and difficulty "D" are starting guesses; the
   event-type framework (ROADMAP §1.4) will own per-event rules anyway.
10. **Night racing.** Light poles are placed unwired; wiring them into the
    open world's `street_lights` night-toggle is a standalone-scene decision
    for later (SunDriver handles the sun; pole lights need a small local
    night listener).

---

## 7. STATUS — 2026-10-15 (P0–P6 shipped; full gate green)

| Phase | State |
|---|---|
| P0 Layout generator + `test_northern_isle_layout.gd` | `[SHIPPED]` — 13/13 |
| P1 `RoadDef.bank_angles` / `show_lane_dividers` + `track_builder.gd` profile + `test_track_bank_profile.gd` | `[SHIPPED]` — 47/47 (3 suites) |
| P2+P3 Scene + checkpoints + registry + bank-aware ground + foliage (`test_northern_isle_track.gd`) | `[SHIPPED]` — 31/31 across 4 suites (`test_northern_isle_track` + `test_northern_isle_layout` + `test_track_bank_profile` + `test_track_system`); bake 1729 ms; foliage min 11.047 m from the centerline |
| P4 `oval_dressing.gd` (fence/grandstands/gantry/billboards) + `test_northern_isle_dressing.gd` | `[SHIPPED]` — 13/13 |
| P5 Race-flow polish + integration pass | `[SHIPPED]` — 128/128 over 14 suites; the new lap-completion re-arm regression test was falsified against the old binding, then restored green |
| P6 Full gate + ROADMAP/STATUS update | `[SHIPPED]` — parallel full gate: 1146 test cases, 0 errors / 0 failures / 0 flaky / 0 skipped / 20 orphans (baseline), 109/109 suites in 238.3 s, exit 0 — first run, no re-run needed |

**Notes / deviations:**

- The §3 ground-bake rule was implemented with a corrected sign
  (`center_y − s·sin(bank)`), with `WASHBED_DEPTH = 0.30` below the road rather
  than coplanar, and `EDGE_DROP = 0.10` on the blend bands.
- The foliage seed is re-rolled deterministically (`FOLIAGE_SEED_ATTEMPTS = 8`)
  because `foliage.gd`'s rejection sampling lets one stray tuft through at the
  stock seed.
- The `race_manager.gd` `lap_completed` → `reset_checkpoints` arity bug (a
  3-arg signal bound to a 0-arg callable — the lap-completion re-arm silently
  never ran on any track) was found and fixed with a new regression test.
- The §4 P6 instruction to rewrite the ROADMAP row's `121 layouts` cell was
  **not** applied literally: under the table header
  (`| Capability | GT7 | FH6 | UltraDrive | Status |`) that cell is the **GT7
  benchmark**, so our count went into the **UltraDrive** column instead, as the
  three `TrackRegistry` layouts — Sunset Oval, Mountain Pass, Northern Isle
  Speedway. The `oval/NTSC-speedway/…` sketch above names no track that exists
  (`NTSC-speedway` is a garble of §1's "NASCAR-style"); the registry's display
  names are authoritative.

Update this block as phases land (the `open_world_seeding_plan.md` STATUS
block is the precedent).
