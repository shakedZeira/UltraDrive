# Track Plan — Circuit des 24 Heures du Mans | No-Chicane (1979–1985 "Circuit N°7")

- **STATUS: NOT STARTED — plan complete**
- **Precedent:** `docs/plans/track_barcelona_rallycross.md` — mirror its structure, effort tags, acceptance table.
- **Variant:** Circuit N°7, **13.626 km**, era-official **27 turns**. Mulsanne flat out (no chicanes), no Dunlop chicane, Mulsanne kink present.
- **Effort:** L (phases tagged S/M). **Prepared 2026-10-18** from research + a verified OSM geometry trace + live-tree line checks. No code/scenes/tests touched yet.

## Contents

1. [Research digest (sources, variant decision, corner count)](#§2-research-digest)
2. [Geometry / control-point plan — APPROXIMATE](#§3-geometry--control-point-plan)
3. [Architecture — files added / edited / do-not-touch](#§4-architecture)
4. [Acceptance criteria](#§5-acceptance-criteria)
5. [Phases & test plan / gate](#§6-phases--test-plan)
6. [Risks / gotchas](#§7-risks--gotchas)
7. [KNOWN UNFINISHED PROBLEMS / OPEN ISSUES](#§8-known-unfinished-problems--open-issues)
8. [Execution contract + do-not-do list](#§9-execution-contract)
9. [STATUS](#§10-status)

## §2 RESEARCH DIGEST

**Goal / scope recap.** Add drivable layout `"Le Mans No-Chicane"` (id `le_mans`) as a closed endurance road circuit: pure layout class → scene (road → checkpoints → ground → dressing → spawn) → registry + pins → suites. **In scope:** OSM-derived geometry (§3), layout/scene/dressing scripts + `.tscn`, flat ground + full-edge skirt, 24 checkpoints + grid/line, registry + 3 pins, tests, gate. **Out (v1):** terrain/elevation (Dunlop climb §8.5), grandstands, pit buildings/lane (pit ways excluded), floodlights, sector timing, AI roster tuning, night racing, licensing review (§8.4), `MapRoads` fit edits and physical armco colliders (§8.3).

**Sources (every fact cited here):**
- **S1** Wikipedia Circuit de la Sarthe — `https://en.wikipedia.org/wiki/Circuit_de_la_Sarthe`: era table (Circuit N°7, **1979–85, 13.626 km / 27 turns**); evolution dates (Ford chicane 1968, Raccordement/Porsche 1972, kink removed 1986, Dunlop chicane 1987, Mulsanne chicanes 1990); FIA 2 km-straight rule context.
- **S2** 24h-lemans turn-by-turn — `https://www.24h-lemans.com/en/news/explore-the-24-hours-of-le-mans-circuit-turn-by-turn-60679`: corner names/order.
- **S3** 24h-lemans landmarks — `https://www.24h-lemans.com/en/news/landmarks-of-the-24-hours-of-le-mans-circuit-57442`: 7 % climb, 76 m high point, Forest Esses (since 1932), Mulsanne 5.5 km / 350 kph, Mulsanne corner 300→75 km/h, Indianapolis (since 1923), second Dunlop bridge stood until 1979.
- **S4** Le Mans Ultimate wiki track guide — `https://lemansultimate.wiki.gg/wiki/Track_Guide:_Circuit_de_la_Sarthe`: sectors; counting convention (official 38 vs guide-style 21).
- **S5** FIA WEC evolution — `https://www.fiawec.com/en/news/evolution-of-the-circuit-des-24-heures/181`.
- **S6** Maison Blanche old circuits — `https://www.maisonblanche.co.uk/old/circuits.html`. **S7** `https://acracemods.wordpress.com/2024/05/29/track-evolution/`. **S8** `https://otomobilgi.com/en/from-the-mulsanne-straight-to-the-ford-chicanes-the-story-of-la-sarthe`.
- **S9** racingcircuits.info — HTTP 403, unusable, excluded.
- **S10** Geometry source: OpenStreetMap `https://api.openstreetmap.org/api/0.6/map?bbox=0.2050,47.9100,0.2500,47.9650` — **ODbL; attribute "© OpenStreetMap contributors"** in the scene docstring and any map/about text.

**Variant decision (S1).** IN = Ford chicane (1968), Raccordement (1972), Porsche Curves (1972), Indianapolis, Arnage, Mulsanne kink. OUT = Dunlop chicane (1987), Mulsanne chicanes (1990), modern Ford widening. Rationale: longest-lived pre-chicane configuration (7 seasons) and the only layout with the full ~5.5 km flat-out Hunaudières — the single most distinctive drive this track can offer (and the reason FIA later mandated chicanes, S1).

**Corner count — which number to publish.** **27** = era official (S1), the number this plan publishes. **~15** named corner groups are distinguishable in our traced ring. **38 vs ~21** (S4) = counting convention (every kink vs named corners only), not a geometry conflict. Independent cross-check on our own trace: **8 heading changes > 40°, ~29 > 20°** — same order as 27 ✓. Document the convention wherever a count is printed (residual ambiguity → §8.2).

**Published figures the trace is checked against (§3.4):** Mulsanne straight 5.5 km / 350 kph; Mulsanne corner 300→75 km/h; 7 % climb to 76 m at Dunlop; Arnage ≈51 m; Indy→Arnage ~340 m; Mulsanne→Indy ~2.1 km (S1/S3).

**Live-tree facts (verified this session, line numbers current):**
- `scripts/track/track_registry.gd:7-36` — `tracks` dict, 4 layouts (`oval`, `mountain_pass`, `northern_isle`, `barcelona_rx`).
- `track_registry.gd:137-141` — pin id **`spa`** drives `mountain_pass` (id is TAKEN — repoint it, don't add a second).
- `track_registry.gd:252-256` — pin id **`le_mans`** currently drives `northern_isle`.
- `track_registry.gd:128-129` — WORLD pin-count comment (32 → 33 after this plan).
- `tests/test_track_system.gd:5` — hard-coded id list `["oval","mountain_pass","northern_isle","barcelona_rx"]` (add `"le_mans"`).
- `tests/suites/test_race_menu_map.gd` — pin invariants: ≥3 pins/layout, exact `display_name` labels, ≤50 % ownership, first three pins Israeli, WORLD ≥30.
- Templates: `barcelona_rx_layout.gd` (pure static layout class), `barcelona_rx.gd` (scene orchestration + `_generate_road_points()` off-tree preview probe), `test_barcelona_rx_layout.gd` / `test_barcelona_rx_track.gd`.
- Checkpoint semantics (from `checkpoint.gd` / `lap_counter.gd`): presence is **frame-based** (no enter-edge) → the grid must NOT sit on a checkpoint; the line must be the LAST checkpoint in travel order (worked out fully in §3.6).

## §3 GEOMETRY / CONTROL-POINT PLAN

### 3.1 Pipeline (v9, verified end-to-end) — **APPROXIMATE, NOT SURVEYED**

1. Fetch S10 bbox. Filter `highway=raceway` plus motorway/trunk/primary/secondary/tertiary/residential/unclassified/service (no `*_link`), **exclude any way matching `/Pit/i` (17 ways)**.
2. Dijkstra over 6 anchors: `dunlop_bridge (47.9457,0.2143)`, `tertre (47.96111,0.22340)`, `mulsanne (47.91384,0.24353)`, `indy (47.92219,0.21983)`, `arnage (47.92146,0.21562)`, `ford (47.94700,0.20865)` → closed ring.
3. Chord-splice OUT modern chicane zones: Chicane Michelin, Chicane Daytona, Chicane Dunlop, Giratoire de Mulsanne. KEEP Ford chicane + Raccordement.
4. Douglas-Peucker eps 8 m → uniform scale k = 1.0123 (raw 13,460.8 → **13,626.0 exact**) → insert S/F.
5. World frame: **X east, Z south, origin at centroid (lat 47.9437, lon 0.21596)**. (Godot Y up; keep these XZ as-is.)

**v9 verification (all clean):** self-crossings `[]`, reversals `[]`, duplicates 0, sharp>40 = 7, **winding clockwise** ✓, perimeter 13,626.0, bbox x[−642..2111] z[−2034..3390] (2,753 × 5,424 m). Anchor snaps: Dunlop bridge 7 m, Tertre Rouge 1 m, Mulsanne 26 m, Indianapolis 0 m, Arnage 0 m, Ford 1 m.

### 3.2 The 51 control points — **APPROXIMATE** (world XZ @ chainage m from S/F)

```
 0(-630,-844)@0      1(-624,-1016)@172   2(-582,-1223)@384   3(-528,-1331)@504
 4(-275,-1569)@852   5(-260,-1579)@869   6(-214,-1612)@927   7(-121,-1718)@1067
 8(-60,-1742)@1133   9(87,-1758)@1281   10(116,-1791)@1324  11(131,-1873)@1408
12(156,-1909)@1452  13(254,-1977)@1571  14(413,-2034)@1740  15(540,-1963)@1885
16(621,-1893)@1992  17(856,-1523)@2430  18(2034,2095)@6236  19(2111,3283)@7426
20(2104,3364)@7508  21(2084,3390)@7541  22(1346,3196)@8303  23(850,2947)@8859
24(370,2589)@9457   25(336,2543)@9514   26(294,2411)@9653   27(272,2391)@9683
28(239,2393)@9716   29(-14,2490)@9987   30(-35,2480)@10010  31(-178,1907)@10601
32(-375,1508)@11046 33(-481,1353)@11234 34(-523,1268)@11329 35(-525,1210)@11387
36(-512,1170)@11428 37(-403,1040)@11598 38(-382,974)@11668  39(-401,819)@11823
40(-503,710)@11972  41(-526,635)@12051  42(-510,559)@12129  43(-429,475)@12245
44(-407,423)@12301  45(-434,205)@12521  46(-422,84)@12642   47(-539,-353)@13094
48(-586,-393)@13157 49(-607,-486)@13252 50(-642,-514)@13296
```

Closing leg 13,296 → 13,626 = 330 m (front straight). These are Catmull-Rom **anchors**, not final mesh points — the layout resamples uniformly (§3.5).

### 3.3 Long-segment subdivision (mandatory: ≤250 m between anchors → **85 anchors**)

Subdivide at evenly spaced points along each leg: rp3→4 @504 (347 m); rp16→17 @1992 (438); rp17→18 @2430 (**3,805** — the Mulsanne straight); rp18→19 @6236 (1,190); rp21→22 @7541 (762); rp22→23 @8303 (556); rp23→24 @8859 (599); rp28→29 @9716 (271); rp30→31 @10010 (590); rp31→32 @10601 (446); rp46→47 @12642 (452); rp50→0 @13296 (330). Straight-line interpolation along each (the real Mulsanne straight IS straight).

### 3.4 Landmarks & named-way chainage windows (m from S/F)

Landmarks (anchor within ±30 m): Dunlop bridge rp5@869 · Tertre Rouge rp15@1885 · Mulsanne corner rp20@7508 · Indianapolis rp26@9653 · Arnage rp29@9987 · Ford chicane rp47@13094.

Named windows (OSM way names mapped post-surgery, cross-checked vs Dijkstra leg composition): Courbe Dunlop 159–546 · La Chapelle 1007–1199 · Esses de la Forêt 1199–1523 · Tertre Rouge 1523–1910 · Ligne Droite des Hunaudières 1910–2053 and 2935–5783 · Route de Tours 6208–7357 · Route du Golf 7541–9649 · Virage d'Indianapolis 9649–9723 · Virage d'Arnage 9984–10014 · Virage Porsche 11318–11481 · Virage du Pont 11574–11919 · Virage du Karting 11919–12193 · Virage Corvette 12193–12433 · Chicane Maison Blanche 12433–13044 · Chicane Ford 13044–13176 · Chicane du Raccordement 13176–13269 · Virage du Raccordement 13269–13297 · unnamed 5,024 m (incl. front straight 13,297→13,785 = 488 m).

**Dimension cross-checks (trace vs published):** Tertre exit 1,910 → Mulsanne braking 7,357 = 5,447 (pub 5.5 km ✓) · Mulsanne→Indy 2,108 (~2.1 ✓) · Indy→Arnage 335 (~340 ✓) · Arnage→Ford 3,060 (~3.1 ✓) · Dunlop→Tertre 977 (~1.0 ✓) · Raccordement exit→La Chapelle 1,336 (pit straight ~1.3 ✓).

### 3.5 Generation contract (`le_mans_layout.gd`, mirrors `BarcelonaRxLayout` API)

- Closed **Catmull-Rom** through the 85 anchors (non-convex loop — barcelona's convex-fillet constraint does NOT apply), centred on own mean, uniform rescale so `perimeter()` = `TARGET_PERIMETER 13626.0` exactly.
- `TOTAL_POINTS 4800` → spacing **2.83875 m**; `WIDTH 12.0`; `ROAD_BASE_Y 0.15`; `PLAIN_Y −0.25`; `BANK_MAX_DEG 3.0` (flat straights, sine-eased banks in the big corners; sign convention = barcelona: positive = right turn); no jumps.
- **S/F line at rp0 (chainage 0)** ≈ **66 % along the 488 m front straight**, ≈330 m after the Raccordement exit, ≈159 m before Courbe Dunlop. v9 used target (−622.4,−843.4); the exact straight midpoint ≈(−625.7,−750.0) — an arithmetic slip KEPT on purpose: it yields 329 m of grid run-up + 158 m to Dunlop (document the rule; do not recenter — §8.8).
- `GRID_INDEX 4684` (chainage 13,297 ≈ Raccordement exit, **329 m behind the line**), on the straight, **not on any checkpoint**.
- `CHECKPOINT_COUNT 24`, `CP_STRIDE 200`, `checkpoint_indices()` = `[200,400,…,4600, 0]` — **line LAST in travel order**; checkpoint `index` = position 0..23 in that list (barcelona convention), `is_start_line` on the last.
- **Mulsanne kink (P0, explicit):** absent from OSM. Apply a sine S before resampling: lateral `A·sin(2π(s−s0)/L)` over [s0−150, s0+150] with `MULSANNE_KINK_CHAINAGE = 4630`, `MULSANNE_KINK_LATERAL_M = 30` (tunables), marked `RECONSTRUCTED`. Do NOT bake into the OSM table. (The 14.4° bend at rp18@6236 is the natural road alignment, not the kink.)
- Expose `_generate_road_points()` off-tree probe (TrackLayoutSource convention) + landmark chainage consts for tests.

### 3.6 Lap / grid semantics (read `checkpoint.gd` + `lap_counter.gd` FIRST — §9 step 1, §8.7)

Frame-based checkpoint counting: spawning inside a checkpoint consumes it → free/short lap. Hence grid NOT on any checkpoint, line LAST. Expected: **lap 1 = 13,955 m** (329 m standing-start run-up; the out-of-order first line crossing must not tick), **laps 2+ = exactly 13,626 m**. Prove with a stub-car test in P1 before trusting; §8.7 has the fallback if progression doesn't gate.

### 3.7 Ground (v1 FLAT — no Terrain3D)

Large flat plane at `PLAIN_Y −0.25` covering bbox + margin (~6,000 × 7,000 m) + a **0.40 m verge skirt** from the road edge (Y 0.15) down to the plain along the ENTIRE road edge, both sides (~27 km total). First check whether `track_builder.gd`/`RoadDef` already emits a shoulder — reuse if so; otherwise `le_mans.gd` builds a ribbon. Dunlop climb (+25 m to 76 m ASL) = named follow-up (§8.5).

### 3.8 Dressing (`le_mans_dressing.gd` — NEW; do NOT edit `rx_dressing.gd`)

S/F gantry + checker paint @0; procedural Dunlop-bridge arch @869 (**neutral banner — no Dunlop trademark**); armco (visual only, v1) at corner complexes only, `RailSide.NONE` on the track; MultiMesh hedgerows along Mulsanne 2,000–7,300; tyre stacks at big-braking zones: Tertre ~1,450, Mulsanne ~7,300, Indy ~9,600, Arnage ~9,950, Ford ~13,020; apex kerb quads at the 8 >40° corners; marshal posts every ~1,500 m. Out: grandstands, pits, floodlights, full-lap armco.

### 3.9 Honesty note (keep in the shipped docstring)

Geometry is an OSM-centerline trace scaled to the published 13.626 km — **approximate**: ±10–30 m lateral on straights, worse in complexes; S/F ±100 m; Dunlop bridge chainage ±150 m; chicane-removal chords are geometric approximations, not historic alignments; Mulsanne kink reconstructed; elevation not modelled. **© OpenStreetMap contributors, ODbL.**

## §4 ARCHITECTURE

**Add:**
| File | Role |
|---|---|
| `scripts/track/le_mans_layout.gd` | `class_name LeMansLayout` — pure static geometry source of truth (anchors → subdivision → kink → Catmull-Rom → 4,800 uniform points → rescale 13,626), checkpoint/grid/landmark constants, `frame_at_arc`, `_generate_road_points` convention |
| `scripts/track/le_mans.gd` | scene root orchestration, mirrors `barcelona_rx.gd` `_ready` order: centerline → road → checkpoints → ground → dressing → `RaceManager.set_rival_centerline` → spawn at `GRID_INDEX` facing forward; export gates `build_own_ground / build_foliage / build_dressing / reposition_player` |
| `scripts/track/le_mans_dressing.gd` | §3.8 dressing (new class — never extend `RxDressing`) |
| `scenes/track/le_mans.tscn` | root Node3D + `RoadNetwork` child + `Dressing` child (barcelona structure; RoadNetwork child is what makes minimap/`SurfaceRegistry` resolve via the `"road_network"` group) |
| `tests/suites/test_le_mans_layout.gd` | pure-math suite |
| `tests/suites/test_le_mans_track.gd` | scene-runner suite |

**Edit:**
- `scripts/track/track_registry.gd` — add `le_mans` entry to `tracks` (`:7-36`): `display_name "Le Mans No-Chicane"`, `scene_path res://scenes/track/le_mans.tscn`, `laps_default 1`, `difficulty "A"`, `circuit_type "ENDURANCE"`.
- Pin `spa` (`:137-141`) → repoint to `le_mans` (swap a lie for a truth, same argument as the barcelona repoint).
- Pin `le_mans` (`:252-256`, currently `northern_isle`) → repoint to `le_mans` + relabel with the exact `display_name`.
- Add ONE new pin `sebring` (id verified unused; US, `REGION_NORTH_AMERICA`) → `le_mans`.
- Update WORLD comment (`:128-129`) 32 → 33.
- **Result:** oval 6 / mountain_pass 14 / northern_isle 13 / barcelona_rx 3 / le_mans 3 = **39 pins, WORLD 33** (≥30 ✓, every layout ≥3 ✓, max 35.9 % ≤ 50 % ✓, first three pins stay Israeli ✓).
- `tests/test_track_system.gd:5` — add `"le_mans"` to the id list.

**Do NOT touch:** `rx_dressing.gd`, `track_builder.gd`, `checkpoint.gd`, `lap_counter.gd`, `map_roads.gd` / `minimap.gd` / `world_map.gd`, `race_ui.gd`, any existing test's assertions (beyond the id list), any other pin, `settings_menu.gd` / quality ladder, `tools/gdunit_parallel.py`, `tools/gen_track_layouts.gd` (re-run the bake only — it iterates registry ids itself).

## §5 ACCEPTANCE CRITERIA

| ID | Criterion | Verification |
|----|-----------|--------------|
| A1 | Registry entry exactly: `"Le Mans No-Chicane"`, `res://scenes/track/le_mans.tscn`, `laps_default 1`, `difficulty "A"`, `circuit_type "ENDURANCE"`; id list updated | `test_track_system` + registry asserts |
| A2 | Layout math: closed loop, perimeter **13,626 ± 2 m**, no crossings/reversals/duplicates, winding **clockwise**, deterministic (two builds element-wise identical) | `test_le_mans_layout` |
| A3 | Landmark chainages within **±30 m**: Dunlop bridge 869, Tertre Rouge 1885, Mulsanne 7508, Indianapolis 9653, Arnage 9987, Ford 13094 | `test_le_mans_layout` |
| A4 | Dimension cross-checks hold (§3.4 tolerances: ±100 / ±80 / ±40 / ±100 m) | `test_le_mans_layout` |
| A5 | 24 checkpoints, stride 200, line = last in travel order at rp0, grid at rp4684 and off every checkpoint; stub-car: lap 1 = **13,955 ± 6 m**, laps 2+ = **13,626 ± 3 m** | `test_le_mans_track` (stub cars, index-driven) |
| A6 | One closed `RoadDef` `Tier.ARTERIAL` / `Surface.ASPHALT` / `RailSide.NONE`, width 12, no lane dividers; builds clean at 4,800 points | scene suite + import probe |
| A7 | Flat ground + 0.40 m skirt along the full road edge both sides; no gap/underlap; no Terrain3D | scene suite + screenshot review |
| A8 | Dressing (gantry, arch, kerbs, tyre stacks, hedges, posts) built by `le_mans_dressing.gd` alone; no trademarks | scene suite + screenshot |
| A9 | Pin invariants pass: 39 pins, WORLD 33, le_mans 3, exact labels, ≤50 % ownership, first three Israeli | `test_race_menu_map` (unmodified) |
| A10 | Minimap + pause-map paths run error-free on the le_mans source; loop bbox maps inside the viewport with nonzero margin | map suite extended (legibility follow-up §8.3) |
| A11 | Import probe clean; parallel gate green with **no regression vs baseline 1314 tests / 0 failures** | background gate sub-agent |

## §6 PHASES & TEST PLAN

**Phases (effort tags):**
- **P0 (M)** — `le_mans_layout.gd`: 51 anchors + §3.3 subdivision + Mulsanne kink + Catmull-Rom + rescale + checkpoint/grid/landmark constants; `test_le_mans_layout.gd` green.
- **P1 (M)** — `le_mans.tscn` + `le_mans.gd`: road, checkpoints, spawn, preview probe; `test_le_mans_track.gd` green **including the A5 lap test** (gates everything else).
- **P2 (S)** — flat ground plane + full-edge skirt; A7 suite + screenshot.
- **P3 (M)** — `le_mans_dressing.gd`; A8 suite + screenshot.
- **P4 (S)** — registry + pins + test-list edits; A1/A9/A10; re-run preview bake (no edit); measure a real lap time → raise the `laps_default` question with the user (§8.4).
- **P5 (S)** — full gate (background sub-agent), `graphify update .`, STATUS block.

**New suites** (mirror the barcelona split):
- `test_le_mans_layout.gd` (pure math, no engine state): A2 closed/perimeter/winding/crossing/determinism; A3 landmark chainages; A4 dimension checks; kink tunables exist and are zero-effect at their window ends; `checkpoint_indices()` = 24 entries, stride 200, last entry 0; `GRID_INDEX` off-checkpoint and 329 m behind the line; spacing = 13,626/4,800 = 2.83875.
- `test_le_mans_track.gd` (scene runner, `pre_check` / two-frame split per convention): A6 RoadDef fields; checkpoint positions/order/`is_start_line`; spawn position + heading (`rotation.y = atan2(-fwd.x, -fwd.z)` pattern); **A5 stub-car lap counts driven by checkpoint indices — never by wall clock**; A7 skirt presence + Y values (edge 0.15 → plain −0.25); dressing child nodes present; `_generate_road_points()` == `build_centerline()` off-tree.
- A9/A10 come from the existing `test_race_menu_map` plus a small map-source extension — do not weaken any existing assertion.

**Gate recipe (PC, cmd.exe — read `docs/GDUNIT_GATE.md` first):**
1. Import probe: `cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE! --headless --import . 2>&1"` → zero `SCRIPT ERROR` / `Parse Error` (a sub-second "clean" = GUI binary detached; re-resolve via `GODOT_EXE_CONSOLE`).
2. Targeted runs: `… !GODOT_EXE_CONSOLE! --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/suites/test_le_mans_layout.gd` — flag AFTER the tool path; `-a` never comma-joined; confirm `_gdunit.txt` is not 0 bytes.
3. Full suite = **ONE background sub-agent**, `py tools\gdunit_parallel.py -j 4`, absolute `APPDATA` under the project root on D:, one Godot process at a time, commands run once, no looping.
4. GDUnit traps: warnings-as-errors; vector `is_equal_approx` needs a same-type eps; suites abort at first failure (compare executed counts vs `func test_` counts); never assert wall-clock.

## §7 RISKS / GOTCHAS

1. **12× scale vs any existing track (highest).** 13.6 km vs ~1.1–2 km: mesh is 4,800 points; `MapRoads.compute_fit` over a 2,753 × 5,424 m bbox can render the loop as a dot or clip it; dressing/MultiMesh/prop counts scale ~12×; every "small-track" constant (foliage radius, seed retries, checkpoint box sizes) is suspect. *Mitigate:* A10 + screenshots early in P1, not at the end; keep dressing instanced (MultiMesh), budget counts explicitly.
2. **Long-track race flow.** Multi-minute laps: anything time-based in tests becomes flaky — tests must drive lap progression by moving stub cars through checkpoint indices, never by elapsed time. `laps_default 1` is a placeholder pending a measured lap (P4) and a human decision.
3. **Flat-ground transition over ~27 km of road edge** with no Terrain3D: if the 0.40 m skirt does not run the entire edge on both sides, the car sees under the road strip or snags it — a visible/physical defect repeated everywhere. *Mitigate:* A7 asserts skirt coverage + Y values; screenshot the whole loop, not just one corner.
4. **Lap-counting arrangement is unexecuted** — frame-based checkpoint counting + "grid off-checkpoint + line last" must produce 13,955/13,626; if `lap_counter` ticks on any line crossing, lap 1 collapses to 329 m. Gate P1 on the stub test; fallback in §8.7.
5. **Catmull-Rom overshoot** on the 85 anchors — especially the kink insertion and the tight Arnage/Indianapolis notches (271 m / 74 m windows): an overshoot creates a self-crossing or a spike that A2 will catch only if the suite samples densely. Subdivide first, keep the kink gentle (30 m over 300 m), test crossings at fine sampling.
6. **OSM extraction traps (already paid once — do not re-derive):** pit ways must be excluded (`/Pit/i`, 17 ways) or the route dives into the pits; derive named windows via a node-pair→way lookup AFTER all route surgery (pre-splice name arrays misalign silently — off-by-one + removed-node offset, it shipped wrong twice before being caught); `*_link` ways excluded.
7. **Environment traps:** cmd.exe (no POSIX tools — `tools\pick.bat`); never C: (absolute `APPDATA` under project root for headless); one Godot process; `--ignoreHeadlessMode` after the tool path; `-a` not comma-joinable; GUI-binary false-green on `&` (use `GODOT_EXE_CONSOLE`); suites abort at first failure so red suites hide later tests.
8. **Trademark/naming exposure** — Dunlop/Terminal/Maison Blanche brands: arch uses a neutral banner; do not print third-party brands in game text (§8.4 is the human decision).

## §8 KNOWN UNFINISHED PROBLEMS / OPEN ISSUES

*(Deferred to the user by explicit request — do not silently scope these out, do not solve them in the implementing session.)*

1. **Control-point accuracy limits.** No surveyed/GIS data: ±10–30 m lateral on straights, worse in corner complexes. Least certain: Porsche Curves rp37–42 and the sector-3 Route de Tours arc rp22–24 (OSM patch-boundary checks inconclusive at ±50 m), S/F line ±100 m, Dunlop bridge chainage ±150 m, and every chicane-removal chord (geometric approximations, NOT the historic alignments). *Impact:* landmark/feel mismatches; local mismatch with the game world's asphalt. *Future:* compare against a period map or satellite imagery and nudge anchors in the table.
2. **Unresolved research questions.** Which exact 1979–85 sub-configuration is canonical (sources lump variants; kink-removal date is 1986 per S1 while secondary claims are looser); sector splits undetermined; corner-count convention 27/38/21 documented but not adjudicated; elevation has only two anchors (76 m high point, ~51 m Arnage, one 7 % figure) with competing claims unreconciled — none modelled. *Impact:* a future elevation/sector pass or a re-trace may move parts of the table.
3. **Integration gaps noticed but deliberately not designed.** (a) Map legibility: `MapRoads.compute_fit` over the 5.4 km-long bbox — loop may render tiny/clipped; fixing fit margins means editing map code (out of scope). (b) Pit logic: pit ways excluded → there is no pit lane at all. (c) Timing/sector loops: none exist. (d) AI: centerline is fed to `RaceManager`, but rival pace/roster over a multi-minute lap is untested. (e) Foliage: the Mulsanne straight crosses a forest patch (~350 m near z −489..−137) and rp18→19 may clip a hedgerow patch (~900 m) — `Foliage`/`PropScatterer` rejection must be wired via `road_network` (barcelona's seed-retry may not scale); tree/road intersection is unverified. (f) Armco colliders: visuals only in v1 — cars pass through the corner-complex barriers. *Future:* decide which of these become tickets.
4. **Human decisions required.** Licensing/attribution posture for a named real circuit (ODbL credit placement, "Le Mans" AOC branding, neutral arch banner as stopgap); final display string; `laps_default 1` vs 2–3 (measure in P4, then ask); the `sebring` pin drives the `le_mans` layout — a stand-in of the same class as the old `spa` lie, revisit when a real Sebring layout exists; whether a first "photo mode"/screenshot review is wanted before merge.
5. **Elevation follow-up.** Dunlop climb (+25 m, 7 % to 76 m ASL) is a named future task; flat v1 is deliberate, not a claim about the real track.
6. **Gate/CI work outside a plan's remit.** Merged-JUnit validation and shard-balance P1s (existing open items in `GDUNIT_GATE.md`) remain open; new suites must stay load-insensitive; if the full-suite baseline has drifted from 1314/0, re-baseline rather than assume.
7. **Lap-counting semantics are unexecuted.** The 13,955/13,626 arrangement follows from the frame-based checkpoint rule *as read*, not from a run. If P1's stub test shows lap 1 ticking at 329 m, fall back to the barcelona-proven pattern (grid ON the first travel-order checkpoint at rp200 → lap 1 = 13,058, laps 2+ = 13,626) — never ship without this test.
8. **S/F arithmetic slip kept on purpose.** v9's line target (−622.4,−843.4) sits ≈66 % along the straight rather than at its exact midpoint (≈−625.7,−750.0); adopted for the 329 m run-up. Document as "~66 % / ≈330 m after the Raccordement exit" — do not silently recenter (that would move the line ~94 m and break A5's chainages).

## §9 EXECUTION CONTRACT

**Ordered steps (literal — follow in sequence):**

1. **Read first (no searching beyond these):** `docs/GDUNIT_GATE.md` → `barcelona_rx_layout.gd` → `barcelona_rx.gd` → `test_barcelona_rx_layout.gd` → `test_barcelona_rx_track.gd` → `track_builder.gd` → `checkpoint.gd` + `lap_counter.gd` → `track_registry.gd` → `rx_dressing.gd` (API only) → `test_race_menu_map.gd`.
2. **Create `scripts/track/le_mans_layout.gd`** per §3.5: paste the 51 anchors (§3.2) verbatim → apply §3.3 subdivision → apply the §3.5 Mulsanne-kink step (tunables) → closed Catmull-Rom → 4,800 uniform points → rescale so perimeter = 13,626.0 exactly. Add all constants (landmarks, named windows, `GRID_INDEX 4684`, `CHECKPOINT_COUNT 24`, `CP_STRIDE 200`, Y values, `BANK_MAX_DEG 3.0`).
3. **Write `test_le_mans_layout.gd`** (A2/A3/A4 + kink/checkpoint/grid asserts) and run it headless (probe first, §6). Green before continuing.
4. **Create `scenes/track/le_mans.tscn` + `scripts/track/le_mans.gd`** mirroring `barcelona_rx.gd`: `_ready` order centerline → road (`Tier.ARTERIAL`, `Surface.ASPHALT`, `RailSide.NONE`, width 12, no lane dividers) → checkpoints (travel order `[200,…,4600,0]`, line last) → ground → dressing → `set_rival_centerline` → spawn at `GRID_INDEX` facing forward.
5. **Write `test_le_mans_track.gd`** including the stub-car lap test (A5). **Do not proceed until it proves lap 1 ≈ 13,955 and lap 2 = 13,626 — if not, apply the §8.7 fallback and re-run.**
6. **Add flat ground (§3.7):** check TrackBuilder for an existing shoulder/verge and reuse; else plane at `PLAIN_Y` + 0.40 m skirt ribbon along the full edge both sides. A7 suite + screenshots.
7. **Create `le_mans_dressing.gd` (§3.8)**, wire into the scene; A8 suite + screenshots (whole loop, not one corner).
8. **Edit `track_registry.gd`** per §4 (entry, `spa` repoint, `le_mans` pin repoint+relabel, `sebring` pin, WORLD comment 32→33) and `tests/test_track_system.gd:5`.
9. **Re-run the preview bake** (`tools/gen_track_layouts.gd` — run only, no edit). Run all targeted suites. Measure one real lap → log the `laps_default` question for the user (§8.4).
10. **Gate:** import probe once, then dispatch ONE background sub-agent for `py tools\gdunit_parallel.py -j 4` (absolute `APPDATA` under project root on D:). On green: `graphify update .`, flip §10 STATUS. Leave committing to the user.

**Do NOT do this:**
- Never use POSIX tools (`head/grep/cat/ls/sed/awk`) — shell is cmd.exe; use `tools\pick.bat`, `read`, `grep`, `glob`, `edit`. Never write to C: — project root only; absolute `APPDATA` under the project on every headless run. Never hardcode a Godot/checkout path — `godot_path.bat` / `GODOT_EXE_CONSOLE`.
- Never comma-join GDUnit `-a` paths; never put `--ignoreHeadlessMode` before the tool script; never run two Godot processes at once; never loop/re-run the gate "to confirm"; never assert wall-clock; never trust a sub-second probe or a 0-byte `_gdunit.txt`.
- Do not touch anything on the §4 do-not-touch list; do not weaken, loosen or delete any existing assertion to make the new track pass; do not add a fifth+ pin beyond `sebring`.
- Do not add Terrain3D/elevation in v1; do not put the grid on a checkpoint; do not move the S/F line off rp0 or recenter it (§8.8); do not bake the Mulsanne kink as an ad-hoc table edit — tunables only; no trademarked banners in game text.
- Do not resolve any §8 open issue yourself — geometry nudges, sector splits, lap defaults, naming/licensing and map-fit changes are the user's calls.

## §10 STATUS

```
STATUS: P0–P4 COMPLETE (2026-10-19) — all targeted suites green; full gate run, 1
unrelated pre-existing failure open. Not committed (left to the user).
P0 layout class + suite        [x]  12/12
P1 scene + checkpoints + lap   [x]  7/7  (A5: lap1=13955.295, laps2+=13626.000)
P2 ground                      [x]  (A7: flat drop 0.40, banked 0.15/0.778)
P3 dressing                    [x]  procedural only, no branded text
P4 registry/pins/bake/lap time [x]  39 pins / WORLD-non-Israel 33 / every layout >=3
P5 gate + graphify + close     [~]  gate executed; see below
Open issues §8 deferred to the user by request.
```

**P5 detail (2026-10-19).** Import probe clean (only the whitelisted Terrain3D
editor-addon `double_slider.gd:25` line). `py tools\gdunit_parallel.py -j 4`
(APPDATA under the project, D:) → `1391 tests | 0 errors | 1 failure`, 5 shards,
133 suites, wall 285.6 s, exit 1 — i.e. RED **only** by
`tests/suites/test_post_race_cinematic.gd > test_cinematic_retires_gameplay_rigs`
(line 239, `prior_camera.current` false after `stop()`). That suite is unrelated
untracked WIP (`scripts/race/post_race_cinematic.gd`,
`docs/plans/post_race_cinematic_exit_plan.md`), touches no Le Mans or map symbol,
and **fails identically in isolation** (6/6 executed, 1 failure) — it is not a
regression from this plan. `graphify update .` run (2808 nodes / 3266 edges).

**Deviations recorded (see the implementing session's report for full detail):**
1. The `spa` pin was **not** repointed — it is asserted by two existing suites
   (`test_race_menu_map.gd`, `test_race_layout_preview.gd`), which A9/§4 forbid
   editing. `nurburgring` was repointed instead (barcelona precedent); A9 still
   holds exactly.
2. `laps_default` kept at **1** for the ~13.6 km lap — user call (§8.4).
3. Foliage is one bbox-centre instance (radius 3150), no clearance assertion
   (§8.3(e) left open as planned).
