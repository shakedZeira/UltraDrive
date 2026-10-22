# UltraDrive — Circuit de Barcelona-Catalunya Rallycross (GT7 track build #2) Plan

> Build **Circuit de Barcelona-Catalunya — Rallycross** — GT7's rank-2 shortest
> layout (1,133 m, **dirt/jump**, one of only two rallycross tracks in GT7) — as a
> fully wired UltraDrive track scene: `TrackRegistry` entry + pins, race/checkpoint
> loop, lap timing + best-lap records, dirt surface/grip, two jumps, bermed
> corners, minimap, and minimal rallycross dressing (barriers + S/F gantry).
>
> **Written:** 2026-10-16 · **Inputs:** `docs/research/gt7_tracks.md` (rank-2
> entry L379/L400, circuit note L191-195, master-table row #15 L61), `AGENTS.md`,
> `docs/ROADMAP.md` (capability matrix L36: "3 track layouts"), `docs/GDUNIT_GATE.md`.
> **Grounded in:** the live code (read-only survey of `scripts/track/*`,
> `scripts/world/road_def.gd` / `spline.gd`, `scripts/vehicle/surface_registry.gd`
> + `vehicle_fx.gd`, `scripts/race/race_ui.gd`, `autoload/race_manager.gd`,
> `scenes/track/northern_isle.tscn`, and every test that touches the registry)
> and the proven template `docs/plans/track_northern_isle_speedway.md`
> (**GT7 track build #1**, shipped 2026-10-15).
>
> **The two hard rules (inherited from build #1):**
> 1. **No tech ceiling** — where this layout needs something the engine lacks, the
>    plan says so and names the owning file. It needs **nothing new** in shared
>    tooling: the one capability build #1 forced (`RoadDef.bank_angles` →
>    `TrackBuilder._frame`) shipped, and DIRT tier + GRAVEL surface already exist.
>    That is the point of choosing rank 2 next: it is the **first track that rides
>    on build #1's capability instead of extending it**.
> 2. **GDUnit discipline is a franchise asset.** Every phase names its gate suite;
>    the full-suite gate follows `docs/GDUNIT_GATE.md` (import probe first,
>    `--ignoreHeadlessMode` after the tool-script path, parallel runner `py
>    tools\gdunit_parallel.py -j 4`, never wall-clock assertions). Baseline at
>    plan time: all-green (1,146 cases, 0 failures — build #1's P6 report).
>    New suites must leave it green.

---

## 1. GOAL + ACCEPTANCE CRITERIA

**Goal.** Ship a 4th `TrackRegistry` layout, `barcelona_rx`, selectable and
raceable end-to-end: a ~1,133 m closed **dirt** rallycross circuit with
rallycross character (long start straight, fast rights, a tight hairpin, a
chicane, two jumps, two bermed corners), driving through the existing
RaceManager/LapCounter/Checkpoint loop, keyed for best-lap records, drawn on the
minimap, and dressed with a start/finish gantry, checker paint, a barrier line on
the tight corners, apex cones and solid barrier colliders.

**Acceptance criteria (all verifiable headless):**

| # | Criterion |
|---|---|
| A1 | `TrackRegistry.has_track("barcelona_rx")` with all five keys; `get_scene_path` loads as a `PackedScene`. |
| A2 | `tests/test_track_system.gd` registry list includes it (the one hard-coded registry assertion). |
| A3 | Perimeter 1,133 m ±10; chain closed; uniform arc spacing (≤2 %); right-hand turns (cross-product sign, mirror of build #1's left-turn test). |
| A4 | 8 checkpoints in travel order on `points[i*50]`, the line on index 7, the grid on index 0; 0→7 ticks exactly one lap, 7-before-0 ticks none. |
| A5 | The road `RoadDef` is `Tier.DIRT` + `Surface.GRAVEL`, closed, width 12, no rails; `SurfaceRegistry` resolves a point on the road to **GRAVEL** grip (0.85 lateral / 0.80 longitudinal) and `VehicleFX` raises the dust channel. |
| A6 | Ground bake recesses under the road at every checkpoint (never buries the asphalt), meets the road edge on both sides, and is `PLAIN_Y` beyond the blend; deterministic across two bakes. |
| A7 | Two jumps (crest heights within ±0.05 of spec, ramp slope ≤ 20°, zero lift outside their arcs) and two sine-eased berm banks (7°), the inner edge at exactly `ROAD_BASE_Y` everywhere the bank is non-zero. |
| A8 | Dressing: gantry centred on the start line with span ≥ road width, checker quad, barrier line + apex cones, all past the corridor; referenced GLBs load with > 0 vertices; deterministic. |
| A9 | Barrier colliders: a solid oriented box chain on the barrier arcs (layer/mask 1, friction 0.2), each chain rising no higher than the visual it guards. |
| A10 | Pins: `barcelona_rx` is driven by ≥3 pins, one of them labelled with the layout's exact `display_name`; the first three pins stay Israeli; the world region keeps ≥30 pins; no other pin's layout changes. |
| A11 | Full parallel gate: 0 new failures; every suite named in §5 green. |

---

## 2. CURRENT STATE — VERIFIED

### 2.1 Roster and the next-shortest track

- `scripts/track/track_registry.gd:7-29` — `tracks` holds exactly three layouts:
  `oval` (Sunset Oval), `mountain_pass`, `northern_isle`
  (`:22-28` = build #1's entry, `display_name "Northern Isle Speedway"`,
  `"scene_path": "res://scenes/track/northern_isle.tscn"`, `laps_default 5`,
  `difficulty "D"`, `circuit_type "OVAL"`).
- `docs/research/gt7_tracks.md:379` — rank 2 in "Shortest tracks by length" is
  **Circuit de Barcelona-Catalunya — Rallycross · Spain · 1,133 m · Dirt RX**;
  `:61` master-table row #15: `| 15 | … Rallycross | Spain | Dirt | 1,133 |`;
  `:191-195` the circuit note — "the Rallycross layout (1,133 m, dirt/jump) is one
  of only two rallycross tracks in the game." Rank 1 (Northern Isle) is shipped,
  so this is the next.

### 2.2 The proven template (build #1) — what to copy, exactly

| Layer | Shipped file(s) | What carries over |
|---|---|---|
| Pure geometry | `scripts/track/northern_isle_layout.gd` (`:33-63` constants, `:88-97` `build_centerline`, `:102-108` `build_bank_profile`, `:111-115` `checkpoint_indices`, `:141-165` `point_at_arc`/`frame_at_arc`, `:174-198` analytic spans) | The whole architecture: one static `RefCounted` class is the single source of truth for centerline + bank profile + checkpoint indices + frame math; everything else consumes it. **Copy the shape, swap the generator**: build #1 walks analytic straight/arc spans, this one walks a closed spline through control points. |
| Scene root | `scripts/track/northern_isle.gd` (`:107-136` `_ready` order, `:150-161` `_build_road`, `:168-181` `_build_checkpoints`, `:192-219` foliage + seed re-roll, `:237-246` dressing wiring, `:313-337` barrier colliders, `:407-436` ground bake, `:521-566` `_terrain_height`, `:572-577` spawn) | The `_ready` order (ground → road → checkpoints → foliage → dressing → colliders → spawn), the export gates (`build_own_ground/build_foliage/build_dressing/build_barrier_colliders/reposition_player`), and the ground-bake structure (coarse hint field + windowed exact scan) verbatim. |
| Scene file | `scenes/track/northern_isle.tscn:71-120` — root (`northern_isle.gd`), `RoadNetwork`, `Dressing`, `PlayerCar`, `ChaseCamera`/`OrbitCamera`/`HoodCamera`/`CockpitCamera`, `Sun`, `WorldEnvironment`, `PauseMenu`, `HUD` | Node-for-node, names included. |
| Road build | `northern_isle.gd:150-161` → `RoadDef.make(Tier.ARTERIAL, points, id, true, WIDTH, Surface.ASPHALT, RailSide.BOTH)` + `bank_angles` + `show_lane_dividers=false` → `network.add_road_def(def)` | Same call, **different tier/surface** (§3.2). |
| Tests | `tests/suites/test_northern_isle_layout.gd`, `test_northern_isle_track.gd`, `test_northern_isle_dressing.gd`, `test_northern_isle_barriers.gd`, `test_track_bank_profile.gd` | Suite structure, `scene_runner` + `simulate_frames(3)`, the `before_test`/`after_test` RaceManager hygiene (`test_northern_isle_track.gd:30-54`), the stub-car `LapCounter` progression harness (`:56-73`), and the edge/`_surface_y_at` sampling helpers (`:86-105`). |

### 2.3 Capabilities this layout needs — all already present

- **Bank profile (build #1's P1).** `scripts/world/road_def.gd:71-85` —
  `bank_angles: PackedFloat32Array` (signed radians, one per point, empty =
  legacy curvature path) and `show_lane_dividers: bool`.
  `scripts/track/track_builder.gd:91-96` honours the profile only when its size
  matches the point count, and `:24-31` documents that `_frame` is the single
  frame supplier for the strip, edges, dividers, rails and the collision trimesh —
  so one array upgrades all of them.
- **DIRT tier.** `road_def.gd:11-17` `Tier.DIRT = 4`; `:32-38`
  `ROADS_WITH_RAILS[DIRT] = false` (no rails — barriers come from dressing);
  `:141-154` default width 7.0 (we override to 12.0);
  `:242-247` `default_surface(DIRT) → Surface.GRAVEL`.
- **Dirt visuals.** `track_builder.gd:35-41` `TIER_EDGE_COLORS[4]` is the brown
  pair (the two 1 m EDGE strips only). The 12 m CARRIAGEWAY is a separate
  material: `tier_surface_albedo()` / `tier_surface_roughness()` overlay the
  DIRT tier on the Surface value, so a DIRT-tier road renders `DIRT_ALBEDO`
  (`Color(0.34,0.24,0.15)`) at roughness `1.0` with triplanar mottling noise,
  whatever its `Surface` says. This overlay is **required**: keying the surface
  off `surface` alone (as this doc originally claimed — "already reads as
  dirt-brown … zero new material code") conflated the 1 m edge colour with the
  carriageway material, and shipped a DIRT road as the pale tan
  `surface_albedo(GRAVEL) = Color(0.55,0.48,0.38)`. See
  `docs/plans/barcelona_dirt_surface_plan.md`.
- **Dirt grip + dust.** `scripts/vehicle/surface_registry.gd:30-37` grip table
  (GRAVEL 0.85/0.80, DIRT 0.80/0.75); `:40-46` `TIER_SURFACE = {4: GRAVEL}`;
  `:61-68` `classify()` keys surfaces off the nearest road's **tier**;
  `:115-136` `default_road_tier_provider` resolves the `"road_network"` group;
  `scripts/vehicle/vehicle_physics.gd:132-133` wires the classifier in
  `_ready`; `scripts/vehicle/vehicle_fx.gd:88` raises `CHANNEL_DUST` whenever the
  surface key is not ASPHALT. **This is the whole dirt feature**: declare the road
  DIRT-tier and the car slides on loose grip and kicks dust.
- **Splines.** `scripts/world/spline.gd:16-34` `catmull_rom_xz` (clamped ends —
  **open chain**, not usable as-is for a loop) and `:50-80` `resample_by_arc`
  (open chain, Y ramped by fraction → not usable for jumps). Both are the
  reference implementations to mirror inside the new layout class (§3.1).
- **Race loop.** `autoload/race_manager.gd:155-156` `set_rival_centerline`,
  `:267` `configure_default_rivals`, `:12` `RIVAL_GRID_ANCHOR_AHEAD = 8.0`;
  `scripts/race/race_ui.gd:441-451` `_resolve_track_id()` reverse-looks the
  scene path up in `TrackRegistry` — **a registry entry alone wires best-lap
  records**, no HUD plumbing.
- **Road props (CC0).** `assets/track_props/`: `finish_gantry.glb`,
  `racing_barrier_red.glb`, `track_barrier.glb`, `track_barrier_a.glb`,
  `track_cone.glb`, `track_rail.glb`, `racing_pylon.glb`,
  `racing_flag_checkers.glb`, `racing_tent.glb`, `light_pole.glb` +
  `License.txt` (CC0, read-only).

### 2.4 The dressing class is NOT reusable (verified)

`scripts/track/oval_dressing.gd:155-198` accepts a generic
`configure(centerline, bank_profile, width, terrain_height)`, **but** the
placement itself is hard-wired to build #1's layout: `:445`
`NorthernIsleLayout.EMBANK_RUN`, `:474`/`:484`/`:501`
`NorthernIsleLayout.start_line_arc()`, `:542-546` billboard rows built from
`NorthernIsleLayout.HALF_STRAIGHT`/`TURN_RADIUS`, `:634-653`
`NorthernIsleLayout.frame_at_arc()`/`perimeter()`/`spacing()`/`TOTAL_POINTS`,
`:683` `PLAIN_Y`. Repointing it at another layout would require a refactor of a
file the green build-#1 suites cover. **Decision: leave it alone; write a small
dedicated `rx_dressing.gd`** (§3.4).

### 2.5 Registry/pin tests that turn load-bearing the moment `tracks` grows

`tracks` membership is asserted in exactly **one** place, but `pins` has three
hard contracts that a new layout must satisfy:

| Test | Line | Contract |
|---|---|---|
| `tests/test_track_system.gd` | `:3-14` | `assert_array(ids).contains_exactly(["oval", "mountain_pass", "northern_isle"])` — **the one hard-coded list; MUST be updated.** Also asserts all five keys per entry, and (`:16-20`) that every `scene_path` exists. |
| `tests/suites/test_race_menu_map.gd` | `:35-46` | `test_every_layout_has_at_least_one_pin`: every layout needs ≥1 pin, and the pin counts must sum to the pin total. |
| ″ | `:197-207` | `test_shipped_layouts_have_a_pin_labelled_with_their_display_name`: **some** pin driving the layout must carry the layout's **exact** `display_name` as its `label`. |
| ″ | `:209-217` | The first three pins must stay region `ISRAEL` and drive real layouts (unchanged by us). |
| ″ | `:219-226` | `test_layout_distribution_is_balanced`: **every layout needs ≥3 pins**, and no layout may own >50 % of the table. |
| ″ | `:228-229` | WORLD region keeps ≥30 pins. |
| ″ | `:97-110` | Israel-fit must contain every Israeli pin and **exclude** every world pin (new pins are WORLD → fine). |
| `tests/suites/test_best_lap_records.gd` | `:51-59` | Dynamic: distinct record keys for every registry id (passes as long as the id is unique). |

Current pin distribution (verified by reading `track_registry.gd:72-257`):
`oval` 6, `mountain_pass` 15, `northern_isle` 15 → total 36
(3 `home_*` + 3 invented Israeli + 30 world; WORLD = 30 ✓). The existing
`barcelona` pin (`:212-216`) currently drives **`northern_isle`**.

---

## 3. DESIGN DECISIONS

### 3.1 Geometry — closed Catmull-Rom through control points, normalized to 1,133 m

Build #1 generated an oval **analytically** (three constants, `:174-198`). A
rallycross circuit has no closed form, so this layout is authored as a
**control-point table** and machine-fitted:

1. `CONTROL_POINTS: Array[Vector3]` — 14 authored XZ waypoints in travel order
   (the starting set, §3.1.1), Y = 0.
2. **Dense sample** a closed Catmull-Rom through them with **wrapped indices**
   (`p0 = c[(i-1+n)%n]`, `p3 = c[(i+2)%n]`; same cubic as `spline.gd:16-34`, but
   the wrap replaces its clamped ends). ~64 samples/segment.
3. **Normalize**: measure the dense polyline's XZ length `L`, scale every XZ by
   `k = TARGET_PERIMETER / L` (uniform scale ⇒ the perimeter is exactly `k·L`;
   `TARGET_PERIMETER = 1133.0`).
4. **Resample by arc** at `spacing = PERIMETER / TOTAL_POINTS` to get
   `TOTAL_POINTS = 400` uniform points (`CP_STRIDE = 50`, `CHECKPOINT_COUNT = 8`,
   `START_LINE_INDEX = 7` — the build-#1 contract shape).
5. **Lift Y**: `y_i = ROAD_BASE_Y + (WIDTH/2)·|sin(bank_i)| + jump_lift(arc_i)`.

`TOTAL_POINTS = 400` at 2.8325 m spacing is the same design idea as build #1's
304 × 38: a checkpoint every 50 points lands **exactly on a point**.

**Authored control set (proposal, tuning-free thanks to step 3):**

| # | x | z | Role |
|---|---|---|---|
| P0 | −120 | −95 | grid (checkpoint 0); start straight begins, travel +X |
| P1 | 10 | −105 | start straight, **jump 1** (table-top) |
| P2 | 120 | −98 | end of start straight |
| P3 | 168 | −55 | **T1** right |
| P4 | 172 | 10 | east side |
| P5 | 140 | 62 | **T2** right (bermed, 7°) |
| P6 | 78 | 92 | north-east |
| P7 | 18 | 66 | **T3** turning in |
| P8 | −8 | 26 | **T4 hairpin apex** (tightest corner; barrier + berm candidate) |
| P9 | −46 | 58 | hairpin exit, **jump 2** (single crest) on the run out |
| P10 | −118 | 82 | **T5** right |
| P11 | −172 | 40 | **T6** right (bermed, 7°) |
| P12 | −176 | −32 | west side |
| P13 | −158 | −82 | **T7** right onto the start straight |

Polyline length ≈ 973 m; the smooth curve ≈ 1,022 m ⇒ `k ≈ 1.11` ⇒ footprint
≈ 390 × 220 m, comfortably inside the ±256 m terrain pane (§3.3). The plan pins
**1,133 ± 10 m**, so the exact tuned numbers are a playtest detail; the layout
class exposes `perimeter()` so nothing else hardcodes it.

**Direction.** Turn 2 at Barcelona is documented CW
(`docs/research/gt7_tracks.md:191`), i.e. right-hand turns — the mirror of build
#1's left-turn oval. Build #1's direction test
(`test_northern_isle_layout.gd:22-23` prose; the per-turn
`cross(t1,t2).y > 0` assertion for left turns) is mirrored here as
`cross(t1,t2).y < 0` on every in-corner sample. Bank signs follow: build #1
stores **negative** radians for left turns (`northern_isle_layout.gd:22-31`), so
a right turn stores **positive** radians (`cross.y = −sin(angle) < 0` ⇒ the
right/inner edge drops, the left/outfield edge lifts). The invariant "the inner
edge rides at `ROAD_BASE_Y`" generalizes as
`center_y = ROAD_BASE_Y + (WIDTH/2)·|sin(bank)|` for either sign.

**Corners, berms, jumps** are declared as tables, not literals sprinkled in code:

```gdscript
# apex control-point index -> corner name (corner_names() order; display + maps)
CORNER_APEX_CONTROL := [3, 5, 7, 8, 10, 11, 13]        # T1..T7 (T4 = hairpin)
# berm banking: sine-eased +/- half_arc around the apex arc, sign = right turn (+)
BANK_REGIONS := [{"apex": 5, "half_arc": 30.0, "deg": 7.0},
                 {"apex": 11, "half_arc": 30.0, "deg": 7.0}]
# jumps: raised-cosine crest over [arc_from, arc_to], optional flat table in the middle
JUMP_REGIONS := [{"from": 70.0, "to": 96.0, "height": 1.0, "table": 10.0},   # table-top
                 {"from": 300.0, "to": 322.0, "height": 0.8, "table": 0.0}]   # single crest
```

Because corner arcs are derived by mapping each apex control point to the nearest
resampled centerline index (deterministic exact search), the corner table survives
any control-point tuning. `BANK_MAX_DEG = 0.0` is the escape hatch that flattens
the whole layout with one edit if berms play badly (§6.2).

**Why jumps are cheap here.** `TrackBuilder` builds the visual strip *and* the
collision trimesh from the same `points` array (`track_builder.gd:98-158`), and
the ground bake reads the same array's Y (`northern_isle.gd:521-566`). A raised
crest in the centerline Y is therefore a real driveable jump with matching
collision and matching ground, with **no new code** — only a Y profile. Limits
that keep it safe: crest height ≤ 1.0 m, ramp slope ≤ 20°, and the bake stays
recessed under the road (`WASHBED_DEPTH = 0.30`) so the car never lands on dirt
poking through the strip.

### 3.2 Surface — `Tier.DIRT` + `Surface.GRAVEL`, no shared-file change

- Road: `RoadDef.make(RoadDef.Tier.DIRT, road_points, "barcelona_rx-dirt", true,
  WIDTH, RoadDef.Surface.GRAVEL, RoadDef.RailSide.NONE)`; `bank_angles = profile`;
  `show_lane_dividers = false` (with `WIDTH = 12.0`, `lane_count_for` returns 1 so
  there are no divider meshes anyway — setting the flag is belt-and-braces).
- `Tier.DIRT ⇒ ROADS_WITH_RAILS[DIRT] = false` (`road_def.gd:32-38`), so the road
  carries **no rails**; the physical boundary is dressing-built (§3.4). The
  trimesh road collision is unaffected.
- **Grip choice, stated honestly:** the classifier keys off tier and
  `TIER_SURFACE[4] = GRAVEL` (`surface_registry.gd:40-46`) ⇒ lateral 0.85 /
  longitudinal 0.80. The table's `DIRT` key (0.80/0.75) is **unreachable from a
  road classification** today. We ship GRAVEL feel for v1: instantly correct
  behaviour, **zero shared-file change**. Remapping `TIER_SURFACE[4]` to `DIRT`
  would re-feel **every open-world dirt road** — that is an explicit
  **non-goal**, logged as a gated follow-up (§6.1).
- No new `RoadDef.Surface` enum member (unlike build #1, no shared-file edit at
  all). Off-road (off the strip) is GRASS via `classify()` — so cutting a corner
  costs grip, exactly the rallycross penalty loop.

### 3.3 Ground bake — build #1's structure, generalized to two blend sides

`northern_isle.gd:407-566` bakes a `Terrain3D` named **`GrassGround`** with a
coarse hint field (`FIELD_STEP 8`, `_hint_index`/`_hint_dist`) routing each texel
to a windowed exact scan (`FIELD_WINDOW ±10`) or the `PLAIN_Y` early-out. Copy it
verbatim with these deltas:

- **Pane**: 512 × 512 @ 1 m/px, `region_size = Terrain3D.SIZE_256`, anchored at
  `Vector3(-256, 0, -256)` (an exact multiple of 256 — the `import_images()` snap
  rule; the pane spans x/z ∈ [−256, 255], and §3.1's footprint is ≈ ±195 × ±115,
  so berm/shoulder/foliage margin is real).
- **Symmetry**: build #1 assumed a left-turn oval (infield always `s < −half`).
  For a circuit with both turn signs, compute **each side's edge height from the
  bank formula** and blend both sides to the plain over one run constant:

  ```
  under road (|s| <= W/2):  center_y - s·sin(bank) - WASHBED_DEPTH
  s >  +W/2:  lerp(center_y - half·sin(bank) - EDGE_DROP, PLAIN_Y, smoothstep(0, BLEND_RUN, s - half))
  s <  -W/2:  lerp(center_y + half·sin(bank) - EDGE_DROP, PLAIN_Y, smoothstep(0, BLEND_RUN, -s - half))
  past W/2 + BLEND_RUN + EXACT_SCAN_MARGIN:  PLAIN_Y
  ```

  with `WASHBED_DEPTH = 0.30`, `EDGE_DROP = 0.10`, `BLEND_RUN = 18.0`,
  `EXACT_SCAN_MARGIN = 12.0`, `ROAD_BASE_Y = 0.15`, `PLAIN_Y = −0.25`. The sign of
  `sin(bank)` makes the same formula lift whichever edge is the outfield one —
  no per-turn branch.
- **Colour**: `GRASS_COLOR * shade` like build #1, but a **dry/olive tint**
  (`Color(0.34, 0.33, 0.20)`) so a rallycross venue reads as dirt-surrounded
  rather than speedway- green. Cosmetic constant, one place.
- **Foliage**: build #1's seed re-roll loop (`northern_isle.gd:192-219`,
  `FOLIAGE_SEED_ATTEMPTS = 8`) with `radius = 220`, `inner_clear_radius = 0`,
  `road_network` set **before** `add_child` (its `_ready` generates immediately),
  and every placement checked with `PropScatterer.is_clear_of_road`.

### 3.4 Dressing — a small dedicated `RxDressing`, not `OvalDressing` (§2.4)

New `scripts/track/rx_dressing.gd` (`class_name RxDressing extends Node3D`),
mirroring `oval_dressing.gd`'s proven shape (MultiMesh + GLB mesh-harvesting,
deterministic, no RNG, `configure(centerline, bank_profile, width, terrain_height)`
then `build()`), but placing from **this** layout's `frame_at_arc()`. Minimal
rallycross dressing:

| # | Item | How |
|---|---|---|
| 1 | S/F gantry | `finish_gantry.glb` at `start_line_arc()`, yaw perpendicular to the tangent, scale from `oval_dressing.gd:106` precedent (`GANTRY_SCALE 14` ⇒ ~17.6 m beam ≥ 12 m road). |
| 2 | S/F checker paint | generated 8 × 2 `ImageTexture` on a `WIDTH × 1.5` m quad at +0.02 (flat — the line is on the start straight, bank 0 there). |
| 3 | Barrier line | `racing_barrier_red.glb` MultiMesh, 4 m pitch, on the **outside** of each arc in `barrier_arc_ranges()` (T4 hairpin + T1/T2/T6), at `WIDTH/2 + 1.6`, y from the terrain provider (`oval_dressing.gd:281-306` scale/height constants are the precedent, re-measured at implementation). |
| 4 | Apex cones | `track_cone.glb` MultiMesh — a small arc run at each named corner apex, tucked just inside the road edge. Visual only. |
| 5 | Start flags | `racing_flag_checkers.glb` at the gantry (one instance), optional. |

Explicitly **out** (scope): catch fencing, grandstands, billboards, light poles,
paddock tents — a club-level RX venue is the right read and none of it needs
testing in v1.

**Physical colliders.** `Tier.DIRT` supplies no rails, so copy
`northern_isle.gd:313-402` into `barcelona_rx.gd` as `_build_barrier_colliders()`:
one oriented `BoxShape3D` per layout step along the barrier arcs, chunked into
`CP_STRIDE`-sized `StaticBody3D`s (layer/mask 1, friction 0.2), top derived from
the barrier GLB's visual top plus `BARRIER_TOP_MARGIN 0.1`
(`northern_isle.gd:279-291` — the "no invisible wall" rule), buried
`BARRIER_DROP_BELOW 1.0` so no gap can open. Built from the same
`barrier_arc_ranges()` the meshes use, so physics and visuals cannot disagree.

### 3.5 Registry, pins, laps

```gdscript
"barcelona_rx": {
    "display_name": "Barcelona Rallycross",
    "scene_path": "res://scenes/track/barcelona_rx.tscn",
    "laps_default": 3,
    "difficulty": "D",
    "circuit_type": "DIRT RX",
},
```

`laps_default = 3` (a ~60 s dirt lap ⇒ ~3 min race, matching build #1's ~5 × 45 s)
and `difficulty "D"` are starting guesses (§6.6); `circuit_type` is display text
and renders on the card next to `CLASS D` (`track_select.gd:221` shows the layout
display name too). The HUD reverse-lookup (`race_ui.gd:441-451`) needs no change.

**Pin decision (justified — three registry tests force it, §2.5).** Repoint and
relabel the existing `barcelona` pin, and add two real World-RX venue pins:

```gdscript
"barcelona": {                       # REPOINTED + RELABELLED (was northern_isle)
    "label": "Barcelona Rallycross",
    "lat": 41.5700, "lon": 2.2611,
    "region": REGION_WORLD, "track_id": "barcelona_rx", "host": "Spain",
},
"holjes": {                          # NEW — real FIA World RX venue (Holjesbanan)
    "label": "Holjes Rallycross, SE",
    "lat": 60.0500, "lon": 13.2400,
    "region": REGION_WORLD, "track_id": "barcelona_rx", "host": "Sweden",
},
"loheac": {                          # NEW — real FIA World RX venue (Lohéac)
    "label": "Loheac Rallycross, FR",
    "lat": 47.9397, "lon": -2.0061,
    "region": REGION_WORLD, "track_id": "barcelona_rx", "host": "France",
},
```

Why each part of that is the right call:

- **≥3 pins per layout** (`test_race_menu_map.gd:219-226`) — one repoint alone
  would leave `barcelona_rx` with 1 pin and go red.
- **Exact-label pin** (`:197-207`) — the repointed `barcelona` pin carries the
  layout's `display_name` verbatim. Build #1's `home_*` pins use exactly this
  idiom (a pin labelled with its layout's display name).
- **Faithful, not invented:** repointing swaps a *lie* (a 4.6 km GP circuit driving
  build #1's 900 m oval) for a *truth* (the real Barcelona circuit driving its own
  RX layout). Höljes and Lohéac are the two most famous World RX venues; the pin
  table already maps real host venues onto fictional layouts everywhere
  (`silverstone → mountain_pass`, `monza → northern_isle`), so this is the
  established idiom, not a new one.
- **Invariants preserved:** first three pins unchanged (still Israeli `home_*`);
  WORLD pins 30 → 32 (≥30 ✓); distribution becomes oval 6 / mountain_pass 15 /
  northern_isle 14 / barcelona_rx 3 of 38 (each ≥ 3 ✓, each ≤ 50 % ✓); Israel fit
  still excludes every world pin (new pins are world) ✓; no other pin's
  `track_id` changes ✓.
- `pins` and `tracks` stay separate dictionaries — the `track_registry.gd:44-55`
  design note ("`tracks` is layouts, `pins` is where they're sold") is honoured:
  we grow `tracks` by one layout and point three pins at it, never duplicating a
  layout entry (which would mis-key best-lap records).

---

## 4. IMPLEMENTATION STEPS (ordered; each phase independently verifiable)

Build #1's phase letters are reused so the two plans read as one series. Note the
big structural difference: **there is no "shared tooling" phase** — build #1's P1
(`RoadDef.bank_angles`/`show_lane_dividers`) already shipped, so this plan starts
at geometry and ends at docs.

### P0 — Layout generator (pure math) · effort M
**Create `scripts/track/barcelona_rx_layout.gd`**
(`class_name BarcelonaRxLayout extends RefCounted`, all static, zero scene deps):

- Constants: `TARGET_PERIMETER 1133.0`, `WIDTH 12.0`, `TOTAL_POINTS 400`,
  `CHECKPOINT_COUNT 8`, `CP_STRIDE 50`, `START_LINE_INDEX 7`, `ROAD_BASE_Y 0.15`,
  `PLAIN_Y −0.25`, `BLEND_RUN 18.0`, `EDGE_DROP 0.10`, `BANK_MAX_DEG 7.0`,
  `CONTROL_POINTS`, `CORNER_APEX_CONTROL`, `BANK_REGIONS`, `JUMP_REGIONS`.
- Builders: `build_centerline() -> Array[Vector3]` (steps 2-5 of §3.1),
  `build_bank_profile() -> PackedFloat32Array`, `checkpoint_indices() ->
  PackedInt32Array`, `corner_names() -> Array[String]` (T1..T7),
  `corner_arc_ranges() -> Array[Vector2]`, `barrier_arc_ranges() -> Array[Vector2]`,
  `jump_arc_ranges() -> Array[Vector2]`, `jump_lift(arc) -> float`.
- Accessors mirroring build #1 so consumers are copy-paste: `perimeter()`,
  `spacing()`, `arc_of_index(i)`, `point_at_arc(s)`, `frame_at_arc(s)` →
  `{center, forward, right, cross, bank}`, `start_line_arc()`.
- Private: `_catmull_rom_closed(control, t)`, `_resample_closed(dense, spacing)`,
  `_ease(x)`, `_bank_rad_at_arc(s)`.
- Keep `spline.gd` untouched (it is used by `corridor_planner.gd`); promote a
  shared closed sampler later if a third track wants one (§6.7).

**Gate:** `tests/suites/test_barcelona_rx_layout.gd` (§5).

### P1 — Scene, road, checkpoints, registry, pins · effort M
**Create `scripts/track/barcelona_rx.gd`** — copy the shape of
`northern_isle.gd`: same `_ready` order and export gates
(`build_own_ground/build_foliage/build_dressing/build_barrier_colliders/
reposition_player`), `road_points`/`bank_profile`/`road_network` members for tests,
`_resolve_road_network()` (find or create the `RoadNetwork` child),
`_build_road()` with the DIRT/GRAVEL def (§3.2), `_build_checkpoints()` (8 boxes
16 × 8 × 16 at `road_points[i*50] + (0, 0.5, 0)`, `is_start_line` on index 7, the
"`"checkpoints"` group" via `checkpoint.gd`), `RaceManager.set_rival_centerline`,
and `_reposition_player_to_start()` with
`rotation.y = atan2(-fwd.x, -fwd.z)` from `frame_at_arc(0)`.

**Create `scenes/track/barcelona_rx.tscn`** — node-for-node the build-#1 scene set
(`northern_isle.tscn:71-120`), root script swapped, `Dressing` typed `RxDressing`.

**Edit `scripts/track/track_registry.gd`** — the `tracks` entry (§3.5) and the
three pin edits (§3.5).

**Edit `tests/test_track_system.gd:5`** — add `"barcelona_rx"` to the
`contains_exactly` list (the only hard-coded registry assertion in the tree).

**Gate:** `tests/suites/test_barcelona_rx_track.gd` (scene/registry half) +
`tests/test_track_system.gd` + `tests/suites/test_race_menu_map.gd` green.

### P2 — Ground bake + foliage · effort M
**Extend `barcelona_rx.gd`** with `_build_ground()`, `_build_hint_field()`,
`_nearest_centerline_full()`, `_hint_dist_at()`, `_hint_index_at()`,
`_plain_cutoff()`, `_terrain_height()` (§3.3, the two-sided generalization) and
`_build_foliage()` (radius 220, seed re-roll, road clearance).

**Gate:** the ground half of `test_barcelona_rx_track.gd` (recess at every
checkpoint, edge meet on both sides at a bermed corner and a flat corner, plain
beyond the blend, `PLAIN_Y` far out, bake determinism).

### P3 — Dressing + barrier colliders · effort M
**Create `scripts/track/rx_dressing.gd`** (§3.4, items 1-5) with the query
helpers the suite needs (`gantry_transform()`, `gantry_center()`, `gantry_span()`,
`checker_transform()`, `barrier_transforms()`, `cone_transforms()`,
`count_of(kind)`, `referenced_glb_paths()`, `dropped_kinds()`, `signature()` —
same API shape as `oval_dressing.gd:42-51`).
**Extend `barcelona_rx.gd`** with `_build_barrier_colliders()` (§3.4).
Wire both from `_ready` behind their export gates, plus the
`Dressing` child in the scene.

**Gate:** `tests/suites/test_barcelona_rx_dressing.gd` and
`tests/suites/test_barcelona_rx_barriers.gd`.

### P4 — Race-flow polish + integration pass · effort S
Verify end-to-end in the live scene: countdown → 3 laps ticking under the gantry →
results overlay → best lap persisted under `("barcelona_rx", class)` →
next-race/return; minimap draws the loop with a rotating marker; pause map shows
it (and degrades silently — standalone scenes have no discovery/fast-travel);
optional default rival field via `RaceManager.configure_default_rivals` /
`GridSpawner`; jumps not snagging the chassis (the manual checklist in §5).
No new code expected beyond tuning.

### P5 — Full gate + docs · effort S
Run the documented gate (§5), fix anything red, update `docs/ROADMAP.md`
(`:36` row "…3 track layouts — Sunset Oval, Mountain Pass, Northern Isle
Speedway" → add Barcelona Rallycross; `:250-259` changelog precedent — add a
"2026-10-XX — Barcelona Rallycross `[SHIPPED]`" entry), append the STATUS block
to this plan, and run `graphify update .` (AST-only).

---

## 5. TEST PLAN

### New suites (all under `tests/suites/`, `extends GdUnitTestSuite`)

**1. `test_barcelona_rx_layout.gd`** — P0, pure math, no scene, no wall clock.
Mirrors `test_northern_isle_layout.gd`:
- constants pinned (`TARGET_PERIMETER`, `WIDTH`, `TOTAL_POINTS 400`,
  `CHECKPOINT_COUNT 8`, `CP_STRIDE 50`, `START_LINE_INDEX 7`, `ROAD_BASE_Y`,
  `PLAIN_Y`);
- `perimeter()` ∈ [1123, 1143] and ≈ 1133 ± 10; chain closed (`points[0]` ≈ one
  spacing from `points[399]`); uniform spacing (max/min segment within 2 %);
- **direction**: on every in-corner sample `cross(t1,t2).y < 0` (right turns —
  the mirror of build #1's left-turn assertion);
- bounding box ⊂ ±240 m (the terrain pane margin);
- **inner-edge invariant**: for every point `p.y − (WIDTH/2)·|sin(bank)| ≈ ROAD_BASE_Y`;
- bank profile: 0.0 outside every `BANK_REGIONS` arc, sine-eased and monotone
  through each ramp, `|profile| ≤ deg_to_rad(BANK_MAX_DEG)`, never negative
  (right turns only);
- jumps: exactly 2 crest regions; crest heights 1.0 / 0.8 ± 0.05; ramp slope
  ≤ tan(20°) everywhere; `jump_lift == 0.0` outside both arcs; lift continuous
  (no step > 0.15 m between adjacent points);
- checkpoint indices `[0,50,…,350]`, `start_line_arc()` on the start straight
  after the grid; 7 corner names / ranges, ordered and inside the loop;
- determinism: two builds are element-wise `is_equal`.

**2. `test_barcelona_rx_track.gd`** — P1/P2, scene-runner
(`scene_runner("res://scenes/track/barcelona_rx.tscn")`, `simulate_frames(3)`,
`before_test`/`after_test` RaceManager hygiene copied from
`test_northern_isle_track.gd:30-54`):
- scene loads; `road_points.size() == 400`; `PlayerCar` at cp0 ± 1 m, not
  `Vector3.ZERO`, facing travel;
- exactly 8 checkpoints, indices `[0..7]` contiguous, positions match
  `points[i*50]`, group membership holds;
- `get_nodes_in_group("road_network")` finds the network: 1 **closed** def,
  `tier == Tier.DIRT`, `width == 12`, `surface == Surface.GRAVEL`,
  `nearest_road_distance(spawn) < 8`, `is_on_road(spawn)` true;
- **dirt grip**: `SurfaceRegistry.default_road_tier_provider(scene)` at a
  checkpoint position returns a tier report, and
  `SurfaceRegistry.build_classifier(provider, Callable())` yields
  `surface_key == GRAVEL`, `lateral ≈ 0.85`, `longitudinal ≈ 0.80`;
- `MapRoads.resolve_road_source(scene)` resolves to that network;
- **closed-loop validity**: stub cars + a suite-owned `LapCounter` fed the real
  checkpoints — passes 0→1→…→7 tick exactly one `lap_completed` at index 7 and
  none elsewhere; an out-of-order 7-before-0 pass ticks none;
- registry: `has_track("barcelona_rx")`, all five keys, `assert_file(scene_path)`,
  `load(scene_path) as PackedScene` non-null, and
  `race_ui._resolve_track_id()` returns `"barcelona_rx"` when the HUD is
  instanced in the scene;
- ground (P2): at every checkpoint the baked height is below the road surface
  (recessed, no burial) with the `WASHBED_DEPTH`/`EDGE_DROP` bands respected; at a
  bermed corner's outer edge the ground meets the banked edge within 0.3 m; on
  both sides beyond `W/2 + BLEND_RUN + 8` the height ≈ `PLAIN_Y`; two independent
  bakes agree (`is_equal_approx`);
- foliage: instance count > 0 and every sample ≥ 11 m from the centerline
  (`PropScatterer.is_clear_of_road`).

**3. `test_barcelona_rx_dressing.gd`** — P3 (mirrors
`test_northern_isle_dressing.gd`): gantry centred within 2 m of the start-line
position and `gantry_span() ≥ WIDTH`; checker quad at the line; barrier meshes
exist with count ≥ 1 and every instance beyond the road edge; cone count > 0 and
every cone inside the corridor-free band; every referenced GLB loads with > 0
vertices (the `test_building_placement.gd:73` loader assertion); two `build()`
runs produce identical transform sets; no dressed node overlaps the road corridor.

**4. `test_barcelona_rx_barriers.gd`** — P3 (mirrors
`test_northern_isle_barriers.gd`): a bare `barcelona_rx.gd` instance that never
entered the tree is configured and `_build_barrier_colliders()` called with a stub
parent; assert box count ≈ ceil(barrier arc-length / spacing) ±1, every box within
the barrier line's lateral ±0.5 m, box rise ≤ its visual top + 0.1
(`RED_BARRIER_VISUAL_TOP 1.57`), layer/mask 1, friction 0.2, and idempotence (a
second call replaces the previous build rather than stacking).

### Existing suites that must stay green / need edits

| Suite | Action |
|---|---|
| `tests/test_track_system.gd` | **EDIT** `:5` — add `"barcelona_rx"` to `contains_exactly`. Everything else in the file is dynamic. |
| `tests/suites/test_race_menu_map.gd` | No edit **if** §3.5's pin plan lands: `:35-46` (≥1 pin + sum), `:197-207` (exact-label), `:209-217` (first three Israeli), `:219-226` (≥3 per layout, ≤50 % cap), `:228-229` (WORLD ≥30) all hold. Verify by running it. |
| `tests/suites/test_best_lap_records.gd` | No edit (dynamic over `get_track_ids()`). |
| `tests/suites/test_track_bank_profile.gd` | No edit — but it is the regression proof for the profile path this track rides, so read it before touching the layout's bank profile. |
| `tests/suites/test_northern_isle_*` (4 suites) | Must stay green: nothing shared is edited, and `oval_dressing.gd` / `northern_isle*.gd` are untouched. This is the reason for the `RxDressing` decision (§2.4). |
| `tests/suites/test_road_graph.gd`, `test_multi_lane_rails.gd`, `test_highway_access.gd` | No edit; no shared road tooling is touched (unlike build #1's P1). |

### Commands (from `docs/GDUNIT_GATE.md` / AGENTS.md)

```
cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE! --headless --import . 2>&1"   (expect zero SCRIPT ERROR / Parse Error)
cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE! --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1"
tools\pick.bat grep "Overall Summary" _gdunit.txt
```
or the parallel runner (`py tools\gdunit_parallel.py -j 4`, PC) then
`tools\pick.bat grep "Overall Summary" reports\parallel\logs`. Confirm
`_gdunit.txt` is **not 0 bytes** first (the GUI-binary false-green trap), and set
`APPDATA` to an **absolute** path under the project root for `user://` isolation.
Never run beside another Godot process. `-a` does not accept comma-separated
paths (chain `&` instead); a suite aborts at its first failure, so compare
executed-case counts to the suites' `func test_` totals. Gate = baseline (1,146
cases, all-green at plan time) with **zero new failures**.

### Manual playtest checklist (P4)

Track select shows "Barcelona Rallycross · CLASS D · DIRT RX" (both in WORLD and,
via the two new pins, in the world calendar); countdown locks controls; the dirt
surface feels loose (0.85 grip) and the car kicks dust on the straights; both
jumps leave the ground cleanly and the car lands on the strip, never on protruding
dirt; the hairpin barrier holds the car in (no invisible wall, no pass-through);
the lap label ticks under the gantry; the results overlay shows a best-lap delta;
the minimap draws the loop and rotates the marker; off-road drops onto the
shoulder without getting stuck. Visual review can go through `gemini_vision.bat`.

---

## 6. RISKS / GOTCHAS

1. **Dirt grip is GRAVEL grip (0.85/0.80), not the table's `DIRT` key
   (0.80/0.75).** `TIER_SURFACE[4] = GRAVEL`
   (`surface_registry.gd:40-46`) is the only path from a road to a surface key, so
   a road can never classify as `DIRT`. Shipping as-is is correct behaviour at zero
   shared-file cost; remapping the tier would re-feel **every** open-world dirt
   road and needs its own test update. **Non-goal here; gated follow-up.**
2. **Berm banking flattens with one constant.** `BANK_MAX_DEG = 0.0` (and/or
   emptying `BANK_REGIONS`) turns the whole layout flat; the lay-out tests assert
   invariants that hold in both states, so this is a pure playtest knob. Watch for
   rollover feel at high speed on a 12 m-wide dirt track.
3. **Jumps vs the trimesh.** A too-sharp crest can snag the chassis or launch the
   car into the barrier; keep ramp slope ≤ 20° and crest heights ≤ 1.0 m, and
   verify each crest by playtest. `TrackBuilder` writes `Vector3.UP` normals for
   every vertex, so jumps are lit flat — a known shared-file cosmetic issue
   (build #1 §6.5), deferred.
4. **Spline self-intersection / cusps.** Tuning control points can fold the curve,
   which would fold the road mesh. The layout test asserts a bounding box, min
   segment length and a max inter-segment turn angle — keep those assertions when
   tuning, they are the guard rails.
5. **Terrain pane anchor.** `import_images()` snaps to a `region_size` multiple;
   the pane must stay `SIZE_256` anchored at −256, and the layout must stay inside
   ±240 m. Both are asserted (pane constant + bounding-box test).
6. **`laps_default`/`difficulty` are guesses**, as they were for build #1; the
   event-type framework (ROADMAP §1.4) will own per-event rules.
7. **Do not refactor `oval_dressing.gd`** for reuse (it is hard-wired to
   `NorthernIsleLayout`, §2.4). If a third track wants shared frame math, promote
   a static helper then — not now, with build #1's suites green and unrelated.
8. **The pin edits are load-bearing, not cosmetic.** Without ≥3 pins on
   `barcelona_rx` and one exact-`display_name` label, `test_race_menu_map.gd` goes
   red on three separate tests (§2.5). Make the edits in the same commit as the
   registry entry.
9. **`--import` creates `.uid` files** for the new `.gd`/`.tscn`. They are
   gitignored — never `git add -A`; `git status --short` must not list them.
10. **No wall-clock assertions.** The bake duration is a printed diagnostic
    (`ground_bake_ms`, as in build #1); if the 400-segment windowed scan is slow,
    bucket the exact scan by segment AABB (the `terrain_baker.gd` `_clip_chains`
    lesson) — noted, not planned.
11. **`RaceManager` is global state.** Every new suite resets
    `_checkpoints_dirty`, `rival_roster`, `_participants`, `_lap_counters` and any
    `LapCounter` children in `after_test` (the build-#1 hygiene), and track-select
    tests must drain `RaceManager.consume_pending_race()`.
12. **Kenney GLB axes/scales are unverified** (gantry/barrier/cone orientation);
    re-measure at implementation as build #1 did. `License.txt` stays CC0 and
    read-only.
13. **`RaceManager.rival_centerline` is not reset by the build-#1 suites**; if the
    new suites assert rival placement, reset it explicitly.

---

## 7. DO NOT TOUCH — files owned by concurrent tasks

The registry **entry** and the **pin** edits above are ours; the consumers' code is
not. Explicitly out of scope:

- **Car assets/materials + all camera scripts** (`assets/cars/**`,
  `scripts/vehicle/**` beyond reading, `scripts/camera/**`) — owned elsewhere.
- **`scenes/ui/garage.tscn` + `scripts/ui/garage_ui.gd`**.
- **Track-select / race-menu UI code and scenes** (`scripts/ui/track_select.gd`,
  `scripts/ui/world_map.gd`, `scripts/ui/minimap.gd`, `scripts/ui/map_roads.gd`,
  `scenes/ui/track_select.tscn`, …) — they build cards and map pins from the
  registry **dynamically**, so our registry + pin data is enough; their code is
  theirs. Fix them only if a test proves the data contract is wrong.
- **Vehicle audio** (`scripts/vehicle/car_audio.gd` and friends).
- **`scripts/world/spline.gd`** — keep the closed Catmull-Rom sampler private to
  the new layout class (§4 P0).

We own: `scripts/track/**` (new layout/scene/dressing scripts + the
`track_registry.gd` entry and pins), `scenes/track/**` (new scene), and the new
`tests/suites/test_barcelona_rx_*.gd` plus the one-line
`tests/test_track_system.gd` edit.

---

## 8. STATUS

**SHIPPED 2026-10-17 — Barcelona Rallycross is the 4th `TrackRegistry` layout and
the first DIRT circuit.** The three suites the cancelled run never wrote were
authored and the tree fixed; **all four new suites are green**
(`reports/report_677/`): `test_barcelona_rx_layout` 15 +
`test_barcelona_rx_track` 7 + `test_barcelona_rx_dressing` 11 +
`test_barcelona_rx_barriers` 3 = **36/36 cases, 0 errors, 0 failures, 0 flaky,
0 skipped, 0 orphans** (`Executed test cases : (36/36)` — no fail-fast abort).
The §7 layout bake now writes all four track JSONs
(`resources/ui/track_layouts/`), the registry/pin tests stay green
(`test_track_system` + `test_race_layout_preview` + `test_race_menu_map` = 41/41),
the headless import probe is clean, and the build rides entirely on build #1's
capabilities (DIRT tier + GRAVEL surface and `RoadDef.bank_angles` already
existed). Nothing is committed yet.

| Phase | State |
|---|---|
| P0 Layout generator + `test_barcelona_rx_layout.gd` | `[GREEN]` — 15/15 cases |
| P1 Scene + road + checkpoints + registry + pins + `test_barcelona_rx_track.gd` | `[GREEN]` — 7/7 cases (scene/road/checkpoints/network/spawn, registry, lap progression, dirt grip, ground+foliage bank-awareness, deterministic bake) |
| P2 Ground bake + foliage | `[GREEN]` — bank-aware + deterministic bake asserted inside the P1 suite |
| P3 `rx_dressing.gd` + barrier colliders + 2 dressing suites | `[GREEN]` — dressing 11/11, barriers 3/3 (incl. a pusher cannot cross the barrier) |
| P4 Race-flow polish + integration pass | `[SHIPPED]` — no new code beyond tuning (see §4 P4); dirt grip + lap timing verified in the P1 suite |
| P5 Full gate + ROADMAP + STATUS + `graphify update .` | `[DONE]` — ROADMAP `:36` row + changelog entry + this STATUS block landed; **full parallel gate GREEN: 1314 tests, 0 failures, 0 errors, 0 skipped, 0 false greens, 0 timeouts, exit 0** (`py tools\gdunit_parallel.py -j 4`, 128 suites, 276 s wall); `graphify update .` ran (no topology change — GDScript is not in the graph) |

Update this block as phases land (the build-#1 STATUS block is the precedent).
