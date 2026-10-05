# UltraDrive — Roadmap

Synthesized 2026-09-16 from `docs/research/competitors.md` (FH6 + GT7 research) and
`docs/research/self_audit.md` (our-game audit + gap analysis).

**Refreshed 2026-10-05** against the actual tree. The original "next sprint" list
turned out to be 8 items that had *all* shipped, and the stated test baseline was
144 tests against an actual 1033 — so this revision does two things: every item
below now carries an evidence-based **status**, and the quick-win list is derived
from what is genuinely missing. **The goal is unchanged: match GT7 / FH6
capability**, and the vision/benchmark sections are the north star, not decoration.

**How status was determined** (so it can be re-checked, not trusted): a status is
`SHIPPED` only when a dedicated GDUnit suite exists that exercises it. Suites
live in `tests/suites/` (~110 files) plus a dozen in `tests/`; the authoritative
count is the parallel gate, `py tools\gdunit_parallel.py -j 4`. Per-phase gates
and the perf-investigation state are in `docs/HANDOFF_PARALLEL_GATE.md`.
Status legend: `[SHIPPED]` `[PARTIAL]` `[NOT STARTED]` `[DEFERRED]`.

Grounding rule: every item maps to either a confirmed gap in the audit or a
demonstrated competitor strength we should match. Effort is T-shirt (S/M/L/XL)
for a small indie team (1–2 people). **Tech-stack agnostic:** items are their
ideal solution, never trimmed to what Godot/the current repo does today — if a
goal is best served by an engine change, new tooling, or a hot-path rewrite, that
is in scope (see "No tech ceiling" below).

---

## Capability matrix vs GT7 / FH6

The gap list that matters, given the goal is to match these two. **This is the
part to read first**; the phase detail below is the working plan.

| Capability | GT7 | FH6 | UltraDrive | Status |
|---|---|---|---|---|
| Drivable open world w/ classified road tiers | 121 layouts | ~960 roads, 74 districts | 19 named corridors, 60 km target, 5 tiers | `[PARTIAL]` scale, `[SHIPPED]` system |
| Terrain relief / biomes | massif-scale | Japan: touge/coast/forest/snow | spawn/rolling/highland/alpine + sea level, colour-baked | `[SHIPPED]` |
| GPS route line + map discovery | Sport-mode route | GPS drive-line, district discovery | `MapRoads` route line, reveal bitset, fast travel | `[SHIPPED]` |
| Handling depth / assists | 1.71 physics overhaul | assist levels | surface grip table, ABS/TCS, manual+auto transmission | `[SHIPPED]` |
| Fair readable AI (no rubber-band) | GT Sophy (paywalled) | Drivatars | rival personalities + per-class bands; old rubber-band script is dead code | `[SHIPPED]` |
| Garage tuning / paint | deep setup screens | most-lauded feature | tuning sliders + tiers, paint materials | `[SHIPPED]` |
| Economy loop (no paywall) | Brand Central / Used / Legend | vouchers (criticized) | credits + license + championship gating | `[SHIPPED]` |
| Weather / day-night / regional climate | ✔ | ✔ | 6 grip states, 24 h sun, 5 climate bands, alpine snow | `[SHIPPED]` |
| Cameras | chase/hood/cockpit/photo | chase/hood/cockpit/photo | chase + hood + cockpit + first-person + photo | `[SHIPPED]` |
| Per-car audio | 50-mic per car | per-class engines | 3-bed crossfade + feel layers + sound profiles | `[PARTIAL]` depth |
| Photo / Scapes | ✔ deep | ✔ | v0: free-roam, hide-UI, screenshot | `[PARTIAL]` depth |
| Best-lap / time attack | ✔ | ✔ | best-lap records, replay recorder, session stats | `[SHIPPED]` |
| **Ghost car + local leaderboards** | ✔ | ✔ | — | `[NOT STARTED]` |
| **Rewind / reset-to-road** | ✔ | ✔ | — | `[NOT STARTED]` |
| **Accessibility options** | ✔ | ✔ | — | `[NOT STARTED]` **launch-blocking** |
| **Monthly content cadence** | ✔ monthly drops | ✔ Festival Playlist | — | `[NOT STARTED]` |
| Car roster | 574 | 614 | ~4 | `[DEFERRED]` — explicitly not our axis |
| Ray-traced fidelity tier | ✔ | ✔ | SDFGI off at High by design | `[DEFERRED]` upgrade path |
| Multiplayer | ✔ | ✔ | — | `[DEFERRED]` post-v1 |

**Read that table as the real backlog.** Seven `[NOT STARTED]` rows and one
genuinely `[DEFERRED]`-on-purpose axis; everything else in the phase list below is
already built and gated.

---

## Competitor benchmark snapshots

- **FH6 wins on fantasy-place pacing, not tech:** the biggest map in the series (Japan, ~960 roads, 74 districts, Tokyo ~5× FH5's Guanajuato) and route-based map discovery are what reviewers celebrated — its renderer is 2021-era. *Takeaway:* world-density, route line + discovery sell more than raw pixels. [competitive.md L15, L44]
- **FH6's most-celebrated feature is garage customization** (visual + mechanical, 20 years requested) — depth on a curated fleet, not a 600-car roster. *Takeaway:* a deep, believable garage + tuning beats car count for us. [competitors.md L20, L117]
- **Both incumbents run monthly live-service cadence** (FH6 Festival Playlist series; GT7 free monthly car/track drops) and both paywall/monetize their economies (Car Vouchers, roulette tickets) which players widely criticize. *Takeaway:* an indie can ship monthly content drops *without* grind-paywall pressure. [competitors.md L51, L98, L112]
- **Grand-sim AI is the field a small team can actually beat:** GT Sophy (RL agent) is locked behind a $30 Power Pack; FH6 Drivatars are legacy-scripted and rubber-banding reports trace to Forza Motorsport, not FH6. *Takeaway:* clean, readable, rubber-band-free AI is a genuine, reachable differentiator. [competitors.md L113]
- **GT7's package is depth + authenticity:** 574 cars, 121 layouts, per-car 50-mic audio, deep handling/setup, economy-driven collect-all loop (Brand Central / Used / Legend cars). *Takeaway:* our tuning sliders, per-car audio tiers and loss-making economy loop target exactly this. [competitors.md L89, L77, L117]
- **GT7/Sophy re-invented the career AI and physics repeatedly (1.71 physics overhaul)** — constant feel iteration is a franchise trait. *Takeaway:* treat handling feel and AI as evergreen systems, revisited each cycle. [competitors.md L85]
- **Accessibility is launch-blocking, not polish:** both ship HUD scaling, colorblind filters, assist levels, remapping, auto-drive/flash. [competitors.md L55, L101, L118]
- **Performance bar is briskness, not RT:** FH6 = 4K60 perf / 30 RT quality on Series X; GT7 = 4K120 on Pro. *Takeaway:* locked 60fps + crisp reconstruction + an auto-quality preset is the launch bar. RTGI is a latent *upgrade path*, not the launch gate — once 60fps is met on-target, a graded ray-traced tier (or engine that gives one cheaply) is a real marketing wedge. [competitors.md L114, L32]

---

## High-level goals / vision

UltraDrive is a **license-safe, procedurally world-seeded open-world racer** built in
Godot with original cars and a deterministic terrain pipeline. It does not try to win
on roster size (FH6 ≈ 614 / GT7 ≈ 574 cars) — it wins on:

1. **Feel first** — deep but approachable handling that iterates every cycle (the GT7 1.71 lesson).
2. **A believable garage** — curated cars you can tune, upgrade, paint, and learn to drive (the FH6 lesson).
3. **A living map** — GPS route line, POI events, weather/night, discoverable collectibles (the FH6 map lesson).
4. **Fair, readable AI** — no rubber-banding, skill bands per car class, traffic that responds (the Sophy-the-gap lesson).
5. **A clean living loop** — credits → rewards → unlock gates → spend in the garage, with monthly content drops and *no* paywalled grind (the anti-pattern lesson from both incumbents).

North star (from the audit): *progression + navigation + weather visuals* are the
three things that make the reference titles feel alive and are achievable at indie
scale. These are **ambitions, not current-capability claims** — if achieving them
wants a different engine, renderer, physics layer, or toolchain, that's a plan
item, not a disqualifier. Items 1–4 are now built; **item 5's monthly cadence is
the one vision pillar still missing.**

---

## No tech ceiling (read this first)

UltraDrive is not married to Godot, nor to the architecture in the current repo.
The existing stack and the deterministic worldgen/test discipline are *assets to
reuse*, but they are a **default, not a bound**. Rules for every item below:

1. **State the ambition first, the constraint second.** "Night driving that looks
   like GT7's" is the goal; "GPUParticles + spotlights" is one *possible* route.
   If the route we already have can't carry the ambition, the plan item includes
   the delta to get there (new render feature, plugin, custom engine fork,
   middleware physics, etc.).
2. **Cost, not capability, is the filter.** Deferring something you'd have to
   *build or learn* is a budget decision — never phrase a roadmap item as "Godot
   can't" when it means "we chose not to this cycle." Recurring temptation items
   (fidelity RT, multi-car online, 500-car roster) are timed by scope, not tech.
3. **Two truths survive any tech change:** the GDUnit discipline (whatever the
   stack, tests gate the work — currently **1033 tests**) and worldgen/license-safety (they are product identity, not engine artifacts). Everything else is negotiable.
4. **Write it down when it changes.** If implementation reveals a hard ceiling in
   the current stack, say so in the item's file/PR and propose the tooling delta —
   that is expected work, not a failure.

---

## Phase 1 — Feel & Loop (polish the core driving fantasy)

Priority P0 items from `self_audit.md §2.1`. **This phase is complete** — all but
1.8 shipped, each with a dedicated suite.

### 1.1 Surface-type handling depth `[SHIPPED]`
- **What:** Add per-surface grip lookup (asphalt / grass / gravel / wet) feeding `tire_model.gd` coefficients; optional ABS/TCS assist toggles; light lateral load transfer / anti-roll. Keep the arcade default on.
- **Why:** "Wrap-around grip" + assist toggles is what makes handling read as deep and approachable; audit P0 "feel is king". Maps directly to GT7 1.71 physics-overhaul lesson and FH6 accessibility assist levels. [self_audit.md §2.1 Handling depth; competitors.md L85, L55]
- **Effort:** M–L (2–3 wks). **Shipped.**
- **Test note:** `test_surface_grip` (per-surface multipliers apply, ABS/TCS cap slip), `test_longitudinal_traction`.

### 1.2 GPS route line + race-line assist + nav HUD `[PARTIAL]`
- **What:** Route computation on the `road_network.gd` graph → drive-line rendered on `minimap.gd` / `world_map.gd` (reuse `map_roads.gd` `compute_fit`/`world_to_screen`); optional braking-line assist; HUD position/speed deltas vs the route line.
- **Why:** FH6 reworked its whole map around the GPS drive-line + district discovery; it's the #1 "map feels alive" feature. Audit P0. [self_audit.md §2.1 Navigation & HUD; competitors.md L44]
- **Effort:** M (2–3 wks). **Route line + route-follow shipped** (`test_map_route`, `test_gps_route_follow`, `test_world_map_features`). **Remaining: braking-line assist and HUD position/speed deltas.**
- **Test note:** `test_map_route` covers shortest-path on the road graph + fit/clip math; keep `MapRoads` static-pure so no scene frames needed where possible.

### 1.3 Garage depth — tuning sliders + upgrade tiers `[SHIPPED]`
- **What:** Tuning sliders in `scenes/ui/garage.tscn` that mutate `CarConfig` (`car_config.gd`) live (gears, springs/dampers, downforce); 2–3 upgrade tiers per car; stats-bar comparison UI.
- **Why:** FH6's customization is its most-lauded feature; GT7's setup/tuning is core. We have the data-driven config already — this is UI + mutation over it. Audit P0 "GT core fantasy". [self_audit.md §2.1 Car personalization; competitors.md L20, L117]
- **Effort:** M–L (3–4 wks). **Shipped** (`test_garage_tuning`, `test_car_paint_materials`).

### 1.4 Event-type framework wired to POI markers `[SHIPPED]`
- **What:** Refactor race-start to an event-type framework (circuit / sprint / elimination / time-attack / drift / checkpoint), placed as destination markers on the existing `poi_registry.gd` + map systems.
- **Why:** Both flagships sell event variety in the open world (Touge 1v1, drag, Time Attack vs the FH6 suite). We already have `track_registry.gd`, `drift_scorer.gd` and RaceManager — this stitches them together. Audit P0. [self_audit.md §2.1 Race modes & events; competitors.md L17-19]
- **Effort:** M (3 wks). **Shipped** (`test_event_placement` — 6 event families incl. `time_attack_N` per anchor; `test_event_rewards`).

### 1.5 Weather/environment VFX + night lighting `[SHIPPED]`
- **What:** Rain/snow particle systems, wetness→reflection/road shader, headlights/taillights at night, per-state sun/fog color (extend `sun_driver.gd` + `WeatherManager`).
- **Why:** FH6/GT7 both drive mood off weather + day/night; we already have 6 grip states + 24 h sun — it's a VFX/layer gap. Audit P0. [self_audit.md §2.1 Weather & time; competitors.md L33, L81]
- **Effort:** M (3 wks). **Shipped** (`test_weather_vfx`, `test_weather_fx_bootstrap`, `test_night_headlights`, `test_environment_lighting`).

### 1.6 AI racing depth `[SHIPPED]`
- **What:** Replace pure speed-multiplier rubber-banding (`ai_rubber_banding.gd`) with: drafting bonus, overtake cooldown, difficulty band per car class, traffic brake-check response.
- **Why:** Fair, readable, no-rubber-band AI is our named competitive edge over Drivatars/Sophy-paywall. Audit P1, promoted to Phase 1 because it shapes every race feel. [self_audit.md §2.1 AI racing; competitors.md L113]
- **Effort:** M (2–3 wks). **Shipped** (`test_rival_ai`, `test_rival_personalities`).
- **Cleanup:** `scripts/ai/ai_rubber_banding.gd` is now **dead code** — nothing references it. Delete it, or keep it only if a test still imports it.

### 1.7 Audio feel layers `[PARTIAL]`
- **What:** Add tire squeal/skid, impacts, wind, UI blips to the existing 3-bed `car_audio.gd`; optional radio/music bus.
- **Why:** Cheapest feel/$ available; both sound-hungry audiences notice it immediately; GT7's 50-mic per-car depth is the benchmark for a scrapped surface. Audit P1. [self_audit.md §2.1 Audio; competitors.md L89, L116]
- **Effort:** S–M (1–2 wks). **Feel layers shipped** (`test_audio_feel_layers`). **Remaining vs GT7's per-car depth: per-car sample sets, radio/music bus.**
- **Test note:** `test_car_audio`, `test_engine_audio`, `test_car_sound_profiles` — stub AudioServer calls headlessly.

### 1.8 Rewind / reset-to-road `[NOT STARTED]`
- **What:** Short rewind buffer (crash recorder) or reset-on-track helper for the open world.
- **Why:** Both flagships ship rewind/reset; an open world that lets you beach yourself needs the QoL bailout. Audit P1. [self_audit.md §2.2 Rewind]
- **Effort:** M (1–2 wks). **This is the last open Phase 1 item** — no rewind script exists in `scripts/`.
- **Test note:** assert buffer start/restore is deterministic (no physics frame dependence in tests — restore via stored transforms).

---

## Phase W — World & Roads (the place to drive)

Synthesized from `docs/plans/open_world_seeding_plan.md` (built on
`docs/research/fh6_map.md` + `docs/research/world_compare.md`). **Substantially
shipped.** The user goal: UltraDrive's world stops being a ~6 km road strip and
becomes an FH6-style place — a big classified road system (highways,
mountains/touge, coast, dirt/off-road), multi-biome ground you can see, and
regional weather you must respect.

Original target vs. actual: **3 roads / 6.4 km / no hierarchy / 65 m relief / 1
visual biome** ⇒ **19 named corridors / 60 km target (`KM_TARGET`) / 5 tiers /
massif relief / 4+ biomes colour-baked.** The system is done; **scale is the
remaining gap** (19 corridors vs FH6's ~960 is the honest delta).

- **W.0 Road taxonomy & network graph `[SHIPPED]`.** `road_network.gd` point arrays
  became a real road graph with tier classes (highway / arterial / coastal /
  touge / dirt), per-tier width/banking/surface, junctions, loops and forks;
  `track_builder.gd` got banking/camber + per-side rail masks. Tests:
  `test_road_graph`, `test_highway_access`, `test_multi_lane_rails`,
  `test_map_road_labels`.
- **W.1 Elevation & biome overhaul `[SHIPPED]`.** `terrain_baker.gd` -5..60 clamp
  replaced with alpine dome + biome table (spawn/rolling/highland/fallback);
  height **and colour** are baked, so the seeded-biome table shows in the world
  (`terrain_vista_baker.gd`). Tests: `test_terrain_biomes`, `test_full_world_height`.
- **W.2 Large-corridor auto-seeding `[SHIPPED, scale-limited]`.**
  `corridor_planner.gd` is a deterministic blueprint→`RoadDef` pipeline
  (`MASTER_SEED`, `KM_TARGET = 60.0`, 19 ids, every one named in `ROAD_NAMES` and
  enforced by `test_all_planned_roads_are_named`). Tests: `test_corridor_seeding`.
  **Gap: corridor count/extent, not machinery.**
- **W.3 Off-road & surface grip `[SHIPPED]`.** Same work as 1.1 — per-surface grip
  (asphalt/grass/gravel/mud/snow) into `tire_model.gd`/`vehicle_physics.gd`.
  Test: `test_surface_grip`.
- **W.4 Regional climate & elapsed time `[SHIPPED]`.** `day_night_driver.gd` autoload
  runs the clock (the old `advance_time()` had zero callers) with 5 regional
  climate bands and year-round alpine snow. Tests: `test_regional_climate`,
  `test_weather_sun`.
- **W.5 Discovery loop: GPS route, fast travel, fog-of-war `[SHIPPED]`.**
  `world_discovery.gd` monotonic visited-segment bitset, `MapRoads.route_polyline` +
  `screen_to_world`, `world_map.gd` grey→white reveal, click-to-fast-travel gated on
  reveal. Tests: `test_discovery`, `test_map_route`, `test_world_map_features`.
- **W.6 Living-world density `[SHIPPED]`.** `prop_scatterer.gd`, `foliage.gd`,
  `traffic_spawner.gd` and `living_world.gd` are wired into
  `open_world_root.tscn` as region-streamed dressing; events place by car culture
  off the W.0 network. Tests: `test_event_placement`, `test_traffic_driving`,
  `test_prop_roadside_placement`.
- **W.7 Streaming/LOD evolution `[SHIPPED]`.** Hybrid async terrain streaming
  (player region sync-baked, neighbours on a worker Thread drained ≤2/frame),
  `region_dresser.gd` ring budgets. Tests: `test_streaming_dressing`,
  `test_terrain_seeder_streaming`, `test_dressing_road_clearance`.

**Benchmark "define done" status:** 60 km network **met** · 5 tiers **met** ·
multi-biome **met** · relief **met** · map reveal + fast travel **met** ·
GDUnit baseline monotonic **met (1033)**.

**Overlaps with the master phases:** W.3 ⇢ 1.1 · W.5 ⇢ 1.2 · W.6 ⇢ 1.4/2.3/3.4 ·
W.1 ⇢ 2.5 · W.6 landmarks ⇢ 2.6 — all now landed.

---

## Phase A — 3D Asset Pass (CC0-first, low-poly 3D pipeline) `[SHIPPED]`

Research closed 2026-09-20: the "looks awful" finding was a *model-source* problem,
not an engine one. **Landed.** The strict **CC0-first, low-poly 3D model pipeline**
runs through the already-wired Blender-MCP tools: **CARS** use the shipped Kenney
CC0 swap (`assets/cars/cc0_*.glb` + `resources/cars/cc0_*.tres`, resolved via
`CarVisuals.WHEEL_GROUPS`); **BUILDINGS / pit structures** come from Poly Pizza
CC0; **MOUNTAIN ROCKS** are Poly Haven low-vert boulders herd-instanced via MultiMesh
over the unchanged fBm terrain; **TREES/BUSHES** are Poly Haven / Poly Pizza
low-poly models as `foliage.gd` ArrayMesh sources (wind shader kept); **TRACK
PROPS** (Kenney Racing Kit CC0 barriers, cones, grandstands, guardrails) land in
the `PropScatterer` presets. Licensing is the gate — only verifiable CC0 ships.
Tests: `test_cc0_cars`, `test_foliage_models`, `test_building_placement`,
`test_track_props`, `test_speed_trap_visuals`. Detail + gates in
`docs/plans/asset_pass_3d_plan.md`.

---

## Phase 2 — Content Depth & Progression (a loop worth returning to)

### 2.1 Currency + rewards + unlock gates (the economy loop) `[SHIPPED]`
- **What:** Credits + rewards screen, unlock gating on license (`license_system.gd`) / championship (`championship.gd`), season standings persistence, spend in the garage (ties to 1.3).
- **Why:** Both flagships' collect-all/economy loops are the retention engine — but theirs are paywalled/grindy, which we explicitly avoid. Audit P1; addresses the "victory condition scope" debt. [self_audit.md §2.1 Career loop, §3]
- **Effort:** M (2–3 wks). **Shipped** (`test_career_economy`).

### 2.2 Ghost / time-attack + local leaderboards `[PARTIAL]`
- **What:** Persist local best laps per track/car-class; ghost-car playback; HUD delta vs best/ghost on `race_ui.gd`.
- **Why:** GT7 Sport-mode time-trial culture + FH6 drop-in Time Attack; cheapest leaderboard that still creates return visits. Audit P1. [self_audit.md §2.2 Ghost; competitors.md L18]
- **Effort:** M (1–2 wks). **Best laps + replay + session stats shipped**
  (`test_best_lap_records`, `test_replay_recorder`, `test_session_stats`).
  **Remaining: ghost-car playback and local leaderboards** — no ghost or
  leaderboard code exists yet.
- **Test note:** deterministic lap-replay tests — record a synthetic lap, replay
  against it, assert timing deltas are exact; no physics dependence past stored
  transforms.

### 2.3 Collectibles & discovery `[SHIPPED]`
- **What:** FH-style bonus boards / photo spots / speed traps as `poi_registry.gd` entries with rewards (credits from 2.1).
- **Why:** FH map-discovery loop (fog-of-war + senders + boards) converts map size into content. Audit P2→P1. [self_audit.md §2.2 Collectibles; competitors.md L44]
- **Effort:** S (1 wk + design). **Shipped** (`test_collectibles`, `test_session_stats`).

### 2.4 Photo mode `[PARTIAL]`
- **What:** On-top of `orbit_camera.gd`: hide-UI, FOV/aperture sliders, filters, screenshot export.
- **Why:** Free marketing surface both flagships treat as core (Scapes, FH photo). Audit P1. [self_audit.md §2.2 Photo mode; competitors.md L69, L33]
- **Effort:** S–M (1–2 wks). **v0 shipped** (`test_photo_mode`,
  `test_photo_mode_controller`, `test_photo_free_roam_diag`). **Remaining vs
  Scapes: filters, aperture/DoF, framing guides.**
- **Test note:** screenshot capture + settings state round-trip headlessly
  (Viewport.get_texture → save is deterministic); orbit-camera suite green.

### 2.5 Second biome zone (world-scale proof) `[SHIPPED]`
- **What:** A second open-world biome reusing `terrain_seeder.gd` / `terrain_baker.gd` / `road_network.gd`, with its own `prop_scatterer.gd` dressing + POI set.
- **Why:** FH6's multi-biome Japan is the map fantasy; our world-gen pipeline made the 2nd zone parameterization, not net-new machinery. [self_audit.md §2.2 World size; competitors.md L15]
- **Effort:** L–XL. **Shipped** — spawn/rolling/highland/alpine biomes with
  colour bake + vista horizon (`terrain_vista_baker.gd`, `test_terrain_biomes`).

### 2.6 Authored landmarks & scenery depth `[SHIPPED]`
- **What:** 2–3 authored landmark sets with POI gameplay; distance-faded skyline props.
- **Why:** The audit's "scenery stops at null props" finding; even a few landmarks make the hub feel authored. Audit P2. [self_audit.md §2.1 Refresh/dressing]
- **Effort:** M–L (3 wks). **Shipped** (`test_building_placement`,
  `test_prop_scatterer`, `test_prop_roadside_placement`).

---

## Phase 3 — Live Features, Scale & Launch-Readiness

### 3.1 Accessibility & control options (launch-blocking) `[NOT STARTED]` — HIGHEST-VALUE GAP
- **What:** Steering/handling assist levels (levers from 1.1), controller deadzone, screen-shake/vignette toggles; verify remapping incl. manual-shift bindings.
- **Why:** Both flagships treat this as expected, not bonus; audit P2 but functionally launch-gating. [self_audit.md §2.2 Accessibility; competitors.md L55, L101]
- **Effort:** S–M (1–2 wks). **Nothing exists** — the only `accessib` match in the
  tree is `garage.gd is_car_accessible()`, which is about car *ownership*. This is
  the one item its own document calls launch-blocking and the single highest-value
  gap in the capability matrix.
- **Test note:** add `test_accessibility` — asserts toggles clamp valid ranges,
  deadzone never zero-divides; reuse the control-mapping suite structure.

### 3.2 Save robustness + profile split `[SHIPPED]`
- **What:** Auto-save on exit, slot copy/delete UI, settings+profile persistence split across the JSON slots (`autoload/save_manager.gd`).
- **Why:** Load-bearing for any live economy (2.1) — saves are the contract for the loop. Audit P2. [self_audit.md §2.2 Save robustness]
- **Effort:** S (1 wk). **Shipped** (`test_hardening`, `test_profile_slots`,
  `test_save_manager`).

### 3.3 Performance: GPU benchmark → auto preset + LOD `[PARTIAL]`
- **What:** Runtime GPU auto-selecting Low/Medium/High (`settings_menu.gd` ladder); LOD for scatter/foliage meshes; contact shadows. Follow-on: graded ray-traced reflections/global illumination.
- **Why:** The "locked 60fps" benchmark lesson — briskness is the launch bar; a higher-fidelity tier is the upgrade path. Protects the feel bar across machines without manual preset shuffling. [self_audit.md §3; competitors.md L114]
- **Effort:** M (2 wks). **Auto-preset shipped**: hardware-recommended default
  (weak iGPU → Low, discrete → Medium), persisted in slot 0; High now runs
  SDFGI-off (`5bf60ce`), and there is a per-preset shadow ladder (`13454c0`).
  Tests: `test_settings_presets`, `test_quality_ladder`, `test_perf_gate`,
  `test_shadow_ladder`.
  **Remaining: road LOD.** See the perf finding below before spending here.
- **Perf reality (2026-10-05, `docs/HANDOFF_PARALLEL_GATE.md` §9.9–9.14):** the
  frame is **geometry-bound, not fill-bound** — rendering at 1/16 the pixels
  (`scaling_3d_scale=0.25`) saves only ~1.3 ms of a ~9.6 ms `todraw`, and disabling
  *all* gameplay script CPU saves <0.5 ms. Attribution: **roads ~2.8 ms (83% of
  visible primitives, 91 draws)**, terrain ~1.7 ms. So VRS/TAA/texture-compression/
  resolution-scale are **permanently dropped** (fragment-side), and the only real
  lever is road geometry: merge each road's sub-meshes (91 → ~19-25 draws), then
  distance-cull rails and dashed dividers. Expect ~1.4 ms (~74 → ~83 fps at the
  quiet floor) — worth it, but not dramatic, and each step sits near the ~1 ms
  `todraw` noise floor. **Also note: `test_perf_gate.gd` false-REDs under
  background load — re-run it alone before believing a red.**

### 3.4 Streaming/dressing alignment (debt paydown) `[SHIPPED]`
- **What:** Region-stream props/foliage/traffic instead of once-only rejection sampling.
- **Why:** Audit's open-world debt — the once-spawned dressing would bottleneck once 2.5/2.6 grow the world. [self_audit.md §3]
- **Effort:** L (3–4 wks). **Shipped** (`test_streaming_dressing`,
  `test_dressing_road_clearance`, `test_traffic_spawner`; `region_dresser.gd`
  spawn/free budgets and band culling).

### 3.5 Monthly content cadence (live-service skeleton) `[NOT STARTED]`
- **What:** A lightweight seasonal/playlist container (theme + car/event set + rewards) that can ship monthly without touching core code; document the ops rhythm.
- **Why:** Matches FH6 Festival Playlist / GT7 monthly drops — our differentiator is doing it *without* monetized grind; cadence is the retention engine. [competitors.md L47, L58, L103, L112]
- **Effort:** M (2 wks skeleton) then ongoing content teams. **No content-pack
  code exists.** This is the **last unbuilt vision pillar** (goals §5).
- **Test note:** content packs are data-only (`*.tres`) — a `test_content_pack`
  loads each pack and asserts all referenced resources/cars exist; keeps the suite
  green as data grows.

### 3.6 (Post-v1, scope-deferred — not a tech ceiling) Multiplayer `[DEFERRED]`
- **What:** Deliberately deferred after v1; cheapest future wedge is LAN/split-screen.
- **Why:** Indie attention discipline — both competitors' online is the most
  expensive system they operate. This is a *timing* choice, not a stack limit; if
  later the vision needs it, networked play becomes a planned phase rather than a
  "can't". [self_audit.md §2.2 Multiplayer]

---

## Cross-cutting constraints (apply to every item)

- **Test discipline is non-negotiable.** Baseline = **1033 GDUnit tests green**
  (was 144 when this doc was written; `py tools\gdunit_parallel.py -j 4`, exit 0).
  Every item ships with its test note; headless run order per AGENTS.md (import
  probe first, then `-s` run with `--ignoreHeadlessMode` *after* the tool-script
  path). Warnings-as-errors and same-type `is_equal_approx` gotchas apply to all
  new suites. **A status of `SHIPPED` in this document means a suite exists** —
  if you delete the suite, the status is wrong until you update it.
- **No tech ceiling.** Every item is its ideal solution; Godot/current-architecture
  reuse is a convenience, not a bound. Engine/tooling/physics/rendering changes are
  in scope when they serve an item's "Why" — flag the cost estimate, don't pre-trim
  the ambition (see "No tech ceiling" above).
- **Streaming hot path is load-bearing.** Even now that 3.4 has landed, keep
  correctness first, then whatever architectural improvement the profiling demands.
- **Worldgen stays deterministic.** `terrain_baker.gd` fixed-seed fBm/biome-table is
  a franchise asset (AGENTS.md); any baking change must keep the region-anchor +
  hash rules so tests stay reproducible.
- **License-safe pipeline is a franchise asset.** Original GLB cars via the
  Blender-MCP/Hyper3D flow stay; car count grows via data (`resources/cars/*.tres`)
  not new machinery.
- **Keep this doc honest.** It drifted once already (an entire "next sprint" of
  shipped work). When something ships, change its status in the same commit.

---

## What is actually left (the real backlog)

Derived from the capability matrix, not from the original guesswork. Ordered by
value against the GT7/FH6 goal:

1. **Accessibility (§3.1)** — S–M. The only launch-blocking item, and both
   reference titles treat it as table stakes. Bounded and self-contained.
2. **Monthly content cadence (§3.5)** — M skeleton. The last unbuilt **vision
   pillar** (goals §5), and the retention engine both incumbents run on. Data-only
   packs keep it cheap.
3. **Ghost car + local leaderboards (§2.2)** — M. Time-trial culture is a core GT7/
   FH6 retention loop; best laps already exist, so this is the smaller half.
4. **Rewind / reset-to-road (§1.8)** — M. Closes Phase 1, and an open world that
   lets you beach yourself needs the bailout.
5. **World scale** — the honest structural gap: 19 corridors vs FH6's ~960. The
   *machinery* is done and deterministic, so this is authoring + streaming budget,
   not new systems.
6. **Depth passes on shipped v0s** — per-car audio sets (§1.7), photo
   filters/aperture (§2.4), braking-line assist (§1.2).
7. **Road geometry / LOD (§3.3)** — ~+9 fps, highest-risk-to-reward of the lot.
8. **Deferred on purpose** — car roster, RT tier, multiplayer. Do not re-open
   without a scope decision.
9. **Cleanup** — delete dead `scripts/ai/ai_rubber_banding.gd`; remove the
   throwaway `reports/verify_*.gd` + `reports/load_sampler.ps1` helpers.

Suggested order for the next cycle: **1 → 2 → 3 → 4**, then revisit 5 and 7 with
the profiling evidence in hand.