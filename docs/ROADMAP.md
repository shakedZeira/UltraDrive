# UltraDrive — Roadmap

Synthesized 2026-09-16 from `docs/research/competitors.md` (FH6 + GT7 research) and
`docs/research/self_audit.md` (our-game audit + gap analysis), against the current
state captured in `AGENTS.md`. Grounding rule: every item maps to either a confirmed
gap in the audit or a demonstrated competitor strength we should match. Effort is
T-shirt (S/M/L/XL) for a small indie team (1–2 people). **Tech-stack agnostic:**
items are their ideal solution, never trimmed to what Godot/the current repo does
today — if a goal is best served by an engine change, new tooling, or a hot-path
rewrite, that is in scope (see "No tech ceiling" below).

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
item, not a disqualifier.

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
3. **Two truths survive any tech change:** the 144+ GDUnit discipline (whatever
   the stack, tests gate the work) and worldgen/license-safety (they are product
   identity, not engine artifacts). Everything else is negotiable.
4. **Write it down when it changes.** If implementation reveals a hard ceiling in
   the current stack, say so in the item's file/PR and propose the tooling delta —
   that is expected work, not a failure.

---

## Phase 1 — Feel & Loop (polish the core driving fantasy)

Priority P0 items from `self_audit.md §2.1`. Everything here makes the existing 3-car / 2-track loop feel alive before we add content.

### 1.1 Surface-type handling depth
- **What:** Add per-surface grip lookup (asphalt / grass / gravel / wet) feeding `tire_model.gd` coefficients; optional ABS/TCS assist toggles; light lateral load transfer / anti-roll. Keep the arcade default on.
- **Why:** "Wrap-around grip" + assist toggles is what makes handling read as deep and approachable; audit P0 "feel is king". Maps directly to GT7 1.71 physics-overhaul lesson and FH6 accessibility assist levels. [self_audit.md §2.1 Handling depth; competitors.md L85, L55]
- **Effort:** M–L (2–3 wks).
- **Test note:** extend `test_transmission`/physics suites; add a `test_surface_grip` suite asserting per-surface grip multipliers apply and ABS/TCS cap slip — keep GDUnit warnings-as-errors discipline (type every return).

### 1.2 GPS route line + race-line assist + nav HUD
- **What:** Route computation on the `road_network.gd` graph → drive-line rendered on `minimap.gd` / `world_map.gd` (reuse `map_roads.gd` `compute_fit`/`world_to_screen`); optional braking-line assist; HUD position/speed deltas vs the route line.
- **Why:** FH6 reworked its whole map around the GPS drive-line + district discovery; it's the #1 "map feels alive" feature. Audit P0. [self_audit.md §2.1 Navigation & HUD; competitors.md L44]
- **Effort:** M (2–3 wks).
- **Test note:** add `test_map_route` for shortest-path on the road graph + fit/clip math (mirror existing world-map suite `tests/suites/`). Keep `MapRoads` static-pure so no scene frames needed where possible.

### 1.3 Garage depth — tuning sliders + upgrade tiers
- **What:** Tuning sliders in `scenes/ui/garage.tscn` that mutate `CarConfig` (`car_config.gd`) live (gears, springs/dampers, downforce); 2–3 upgrade tiers per car; stats-bar comparison UI.
- **Why:** FH6's customization is its most-lauded feature; GT7's setup/tuning is core. We have the data-driven config already — this is UI + mutation over it. Audit P0 "GT core fantasy". [self_audit.md §2.1 Car personalization; competitors.md L20, L117]
- **Effort:** M–L (3–4 wks).
- **Test note:** add a pure `test_tuning` suite that mutates a `CarConfig` and asserts derived physics values (weight→gear ratios→speed table) stay in valid ranges; keep asserts same-type (`is_equal_approx` Vector2 arg rule).

### 1.4 Event-type framework wired to POI markers
- **What:** Refactor race-start to an event-type framework (circuit / sprint / elimination / time-attack / drift / checkpoint), placed as destination markers on the existing `poi_registry.gd` + map systems.
- **Why:** Both flagships sell event variety in the open world (Touge 1v1, drag, Time Attack vs the FH6 suite). We already have `track_registry.gd`, `drift_scorer.gd` and RaceManager — this stitches them together. Audit P0. [self_audit.md §2.1 Race modes & events; competitors.md L17-19]
- **Effort:** M (3 wks).
- **Test note:** extend `test_race_loop.gd` pattern — new `test_event_types` asserting each event type's Win/Lose path resolves standings and HUD commit; keep sync-freeing stubs in `after_test`.

### 1.5 Weather/environment VFX + night lighting
- **What:** Rain/snow particle systems, wetness→reflection/road shader, headlights/taillights at night, per-state sun/fog color (extend `sun_driver.gd` + `WeatherManager`).
- **Why:** FH6/GT7 both drive mood off weather + day/night; we already have 6 grip states + 24 h sun — it's a VFX/layer gap. Audit P0. [self_audit.md §2.1 Weather & time; competitors.md L33, L81]
- **Effort:** M (3 wks).
- **Test note:** extend `test_weather_sun` + `test_car_visuals` for wet-shader flag/headlight layer toggling; avoid frame-dependent asserts (use `pre_check/check_part_a/b` split per AGENTS.md).

### 1.6 AI racing depth
- **What:** Replace pure speed-multiplier rubber-banding (`ai_rubber_banding.gd`) with: drafting bonus, overtake cooldown, difficulty band per car class, traffic brake-check response.
- **Why:** Fair, readable, no-rubber-band AI is our named competitive edge over Drivatars/Sophy-paywall. Audit P1, promoted to Phase 1 because it shapes every race feel. [self_audit.md §2.1 AI racing; competitors.md L113]
- **Effort:** M (2–3 wks).
- **Test note:** new `test_ai_race` suite — assert drafting speed delta bounds and that rubber-band stays within a configurable band (no unbounded catch-up), pure-logic where possible.

### 1.7 Audio feel layers
- **What:** Add tire squeal/skid, impacts, wind, UI blips to the existing 3-bed `car_audio.gd`; optional radio/music bus.
- **Why:** Cheapest feel/$ available; both sound-hungry audiences notice it immediately; GT7's 50-mic per-car depth is the benchmark for a scrapped surface. Audit P1. [self_audit.md §2.1 Audio; competitors.md L89, L116]
- **Effort:** S–M (1–2 wks).
- **Test note:** extend `test_car_audio` — assert crossfade bus structure extended without breaking existing 3-bed tests; stub AudioServer calls headlessly.

### 1.8 Rewind / reset-to-road
- **What:** Short rewind buffer (crash recorder) or reset-on-track helper for the open world.
- **Why:** Both flagships ship rewind/reset; an open world that lets you beach yourself needs the QoL bailout. Audit P1. [self_audit.md §2.2 Rewind]
- **Effort:** M (1–2 wks).
- **Test note:** assert buffer start/restore is deterministic (no physics frame dependence in tests — restore via stored transforms).

---

## Phase W — World & Roads (the place to drive)

Synthesized from `docs/plans/open_world_seeding_plan.md` (built on
`docs/research/fh6_map.md` + `docs/research/world_compare.md`). The user's goal:
UltraDrive's world stops being a ~6 km road strip and becomes an FH6-style place —
a big classified road system (highways, mountains/touge, coast, dirt/off-road),
multi-biome ground you can see, and regional weather you must respect. Slots
**between Phase 1 and Phase 2** — it upgrades what Phase 1's feel-loop runs on.

Today vs. target (from the comparison): **3 roads / 6.4 km / no hierarchy / 65 m
relief / 1 visual biome** ⇒ **60 km+ five-tier network / 6 biomes / ~1,500 m
relief / regional clock**. Full detail, benchmarks + per-item test gates live in
the plan file; the phases below are the shape of the work.

- **W.0 Road taxonomy & network graph.** Turn `road_network.gd`'s point-array
  storage into a real road graph: tier classes (highway / arterial / coastal /
  touge / dirt) with per-tier width, banking/camber and surface type, plus junction
  support so roads form loops and forks, not single ribbons. `track_builder.gd`
  gets the banking/camber + tier normals. Effort L. Test: `test_road_graph`
  (topology, connectivity, tier metadata round-trip).
- **W.1 Elevation & biome overhaul.** Replace `terrain_baker.gd`'s -5..60 clamp
  with real mountain massifs, highland plateaus and a sea-level rule; bake the
  **color map** too (`terrain_seeder.gd` currently writes height only), so the
  existing seeded-biome table *shows* in the world. Effort XL. Test: extend the
  streaming suite — elevation bands + `TYPE_COLOR` determinism, region-anchor snape
  rules intact.
- **W.2 Large-corridor auto-seeding.** A determinist seed-authoring path: waypoint
  chains → splines → road-conform bake (reusing the washbed `_clip_chains` math) to
  grow the 60+ km classified network — highway loops, pass connectors, coastal runs,
  dead-end overlooks, dirt cut-throughs. Effort XL. Test: seeded-corridor golden
  runs (bake N seeds, assert identical output, within `is_on_road` bounds).
- **W.3 Off-road & surface grip.** Per-surface grip (asphalt/grass/gravel/mud/snow)
  flowing into `tire_model.gd`/`vehicle_physics.gd`; off-road is a *handling
  consequence*, not a recolour. Effort M. Test: `test_surface_grip` — per-surface
  multipliers apply, ABS/TCS cap slip (subsumes Phase 1.1's surface half).
- **W.4 Regional climate & elapsed time.** Run the regional clock (WeatherManager
  `advance_time()` currently has zero callers) with per-region climate bands and an
  alpine snow/ice belt whose grip/visibility changes routing. Effort M. Test:
  extend `test_weather_sun` — regional band + season switch deterministic, no
  frame-dependent asserts.
- **W.5 Discovery loop: GPS route, fast travel, fog-of-war.** Route computation on
  the W.0 graph → `MapRoads` drive-line (Phase 1.2), free fast-travel to discovered
  points, map reveal as you drive. Effort M. Test: `test_map_route` +
  `test_fog_of_war` (reveal state serializes, route shortest-path exact).
- **W.6 Living-world density.** Wire the orphaned-but-tested `prop_scatterer.gd`,
  `foliage.gd` and `traffic_spawner.gd` into `open_world_root.tscn` as a
  region-streamed dressing runtime; place events by car culture (touge duel, drag
  strip, drift zone, night street loop, highway marathon) off the W.0 network.
  Effort L. Test: extend dressing/event suites — appears/despawns with the region
  ring, no duplication on re-stream, each event resolves Win/Lose.
- **W.7 Streaming/LOD evolution.** Region-stream dressing + LOD as the map grows;
  keep the near-player sync-bake correctness and ≤2 applies/frame discipline. Feeds
  Phase 3.4. Effort L.

**Benchmark "define done" (from the plan):** 6.4 km → ≥60 km road network ·
1 → 5 live road tiers · 1 → 6 rendered biomes · 65 m → ~1,500 m relief · map
reveal + fast travel green · GDUnit baseline monotonic 144+.

**Overlaps with the master phases:** W.3 ⇢ 1.1 · W.5 ⇢ 1.2 · W.6 ⇢ 1.4/2.3/3.4 ·
W.1 ⇢ 2.5 (second biome becomes parameterization of an already-multi-biome world) ·
W.6 landmarks ⇢ 2.6. World quick-wins (start here): wire dressing+traffic into the
root scene → surface grip → run the regional clock → tier metadata on existing roads
→ GPS route v0 → color-bake one region → one drift + one drag event (see plan §Quick wins).

---

## Phase A — 3D Asset Pass (CC0-first, low-poly 3D pipeline)

Research closed 2026-09-20: the "looks awful" finding is a *model-source* problem,
not an engine one. This phase swaps the fused-primitive scenery and AI-scripted
geometry for a strict **CC0-first, low-poly 3D model pipeline** driven through the
already-wired Blender-MCP tools: **CARS** keep the shipped Kenney CC0 swap (a
bespoke Hyper3D-Rodin hero car is optional); **BUILDINGS / pit structures** come
from Poly Pizza CC0; **MOUNTAIN ROCKS** are Poly Haven low-vert boulders
herd-instanced via MultiMesh over the unchanged fBm terrain; **TREES/BUSHES** are
2–4 Poly Haven / Poly Pizza low-poly models as new `foliage.gd` ArrayMesh sources
(wind shader kept); and **TRACK PROPS** (Kenney Racing Kit CC0 barriers, cones,
grandstands, guardrails) land in the `PropScatterer` presets. Licensing is the
gate — only verifiable CC0 assets ship. Runs as the next plan, ahead of the
remaining `match_fh6_gt7_plan.md` S9+ items; the dependency-ordered phases and
per-phase GDUnit gates are in `docs/plans/asset_pass_3d_plan.md`.

---

## Phase 2 — Content Depth & Progression (a loop worth returning to)

Priority P0/P1 from `self_audit.md §2.1/§2.2`. Turns the polished loop into a campaign.

### 2.1 Currency + rewards + unlock gates (the economy loop)
- **What:** Credits + rewards screen, unlock gating on license (`license_system.gd`) / championship (`championship.gd`), season standings persistence, spend in the garage (ties to 1.3).
- **Why:** Both flagships' collect-all/economy loops are the retention engine — but theirs are paywalled/grindy, which we explicitly avoid. Audit P1; addresses the "victory condition scope" debt (no sink for progress). [self_audit.md §2.1 Career loop, §3]
- **Effort:** M (2–3 wks).
- **Test note:** extend save tests (`test_save_manager`-style) for credits/license-unlock persistence round-trips; assert unlock depends on license/champ state, not on scene frames.

### 2.2 Ghost / time-attack + local leaderboards
- **What:** Persist local best laps per track/car-class; ghost-car playback; HUD delta vs best/ghost on `race_ui.gd`.
- **Why:** GT7 Sport-mode time-trial culture + FH6 drop-in Time Attack; cheapest leaderboard that still creates return visits. Audit P1. [self_audit.md §2.2 Ghost; competitors.md L18]
- **Effort:** M (1–2 wks).
- **Test note:** set of deterministic lap-replay tests — record a synthetic lap, replay against it, assert timing deltas are exact; no physics dependence allowed past the stored transforms.

### 2.3 Collectibles & discovery
- **What:** FH-style bonus boards / photo spots / speed traps as `poi_registry.gd` entries with rewards (credits from 2.1).
- **Why:** FH map-discovery loop (fog-of-war + senders + boards) converts map size into content. Audit P2→P1. [self_audit.md §2.2 Collectibles; competitors.md L44]
- **Effort:** S (1 wk + design).
- **Test note:** extend the world-map suite — assert POI registry resolves, marks completed, and pays the reward exactly once per save.

### 2.4 Photo mode
- **What:** On-top of `orbit_camera.gd`: hide-UI, FOV/aperture sliders, filters, screenshot export.
- **Why:** Free marketing surface both flagships treat as core (Scapes, FH photo). Audit P1. [self_audit.md §2.2 Photo mode; competitors.md L69, L33]
- **Effort:** S–M (1–2 wks).
- **Test note:** assert screenshot capture + settings state round-trip headlessly (Viewport.get_texture → save is deterministic); keep orbit-camera suite green.

### 2.5 Second biome zone (world-scale proof)
- **What:** A second open-world biome reusing `terrain_seeder.gd` / `terrain_baker.gd` / `road_network.gd` (existing biome table has an unused highland/fallback biomes ready), with its own `prop_scatterer.gd` dressing + POI set.
- **Why:** FH6's multi-biome Japan (Touge/coastal/forest/snow) is the map fantasy; our world-gen pipeline means the 2nd zone is parameterization, not net-new machinery. Audit P2 but validates the franchise thesis. [self_audit.md §2.2 World size; competitors.md L15]
- **Effort:** L–XL (4–6 wks).
- **Test note:** extend the open-world seeding suite — bake a second-biome region hash set deterministically, assert heightfield + road-conform stays in valid bounds (watch headless watchdog discipline per AGENTS.md).

### 2.6 Authored landmarks & scenery depth
- **What:** 2–3 authored landmark sets with POI gameplay (distinct from the generic guardrail/tent/pole/rock); distance-faded skyline props.
- **Why:** The audit's "scenery stops at null props" finding; FH's Tokyo/density is aspirational but even 3 landmarks make the hub feel authored. Audit P2. [self_audit.md §2.1 Refresh/dressing]
- **Effort:** M–L (3 wks).
- **Test note:** extend `test_prop_scatterer` — landmarks spawn on deterministic seeds, reject on roads, survive serialization.

---

## Phase 3 — Live Features, Scale & Launch-Readiness

Priority P1/P2 from `self_audit.md §2.2/§3`; prerequisite for any public build.

### 3.1 Accessibility & control options (launch-blocking)
- **What:** Steering/handling assist levels (levers from 1.1), controller deadzone, screen-shake/vignette toggles; verify remapping incl. manual-shift bindings.
- **Why:** Both flagships treat this as expected, not bonus; audit P2 but functionally launch-gating. [self_audit.md §2.2 Accessibility; competitors.md L55, L101]
- **Effort:** S–M (1–2 wks).
- **Test note:** add `test_accessibility` — asserts toggles clamp valid ranges, deadzone never zero-divides; reuse D5 control-mapping suite structure.

### 3.2 Save robustness + profile split
- **What:** Auto-save on exit, slot copy/delete UI, settings+profile persistence split across the 3 JSON slots (`autoload/save_manager.gd`).
- **Why:** Load-bearing for any live economy (2.1) — saves are the contract for the loop. Audit P2. [self_audit.md §2.2 Save robustness]
- **Effort:** S (1 wk).
- **Test note:** `test_save_manager` additions — corrupt-slot tolerance, atomic write, copy/delete round-trip; all disk-free (tmp dir) so CI stays hermetic.

### 3.3 Performance: GPU benchmark → auto preset + LOD
- **What:** Runtime GPU benchmark auto-selecting Low/Medium/High (`settings_menu.gd` ladder); LOD for scatter/foliage meshes; contact shadows. Follow-on (post-60fps tier): graded ray-traced reflections/global illumination, chosen on a profiler's evidence rather than "engine can't".
- **Why:** The "locked 60fps" benchmark lesson — briskness is the launch bar; a higher-fidelity tier is the upgrade path (see No tech ceiling). Protects the feel bar across machines without manual preset shuffling. Audit §3 debt. [self_audit.md §3, §2.1 Rendering polish; competitors.md L114]
- **Effort:** M (2 wks).
- **Test note:** extend `test_settings_presets` — benchmark output maps to a valid preset id; LOD thresholds monotonically valid; keep probe budget test green.

### 3.4 Streaming/dressing alignment (debt paydown)
- **What:** Region-stream props/foliage/traffic instead of once-only rejection sampling (`prop_scatterer.gd` / `foliage.gd` / `traffic_spawner.gd`).
- **Why:** Audit's open-world debt — the current once-spawned dressing will be the bottleneck once 2.5/2.6 grow the world. [self_audit.md §3]
- **Effort:** L (3–4 wks).
- **Test note:** extend streaming suite — assert dressing appears/despawns with the region ring and never duplicates on re-stream (mirror `terrain_seeder` thread discipline, watchdog enforced).

### 3.5 Monthly content cadence (live-service skeleton)
- **What:** A lightweight seasonal/playlist container (theme + car/event set + rewards) that can ship monthly without touching core code; document the ops rhythm.
- **Why:** Matches FH6 Festival Playlist / GT7 monthly drops — our differentiator is doing it *without* monetized grind; cadence is the retention engine. [competitors.md L47, L58, L103, L112]
- **Effort:** M (2 wks skeleton) then ongoing content teams.
- **Test note:** content packs are data-only (`*.tres`) — a `test_content_pack` loads each pack and asserts all referenced resources/cars exist; keeps the 144-test suite green as data grows.

### 3.6 (Post-v1, scope-deferred — not a tech ceiling) Multiplayer
- **What:** Deliberately deferred after v1; cheapest future wedge is LAN/split-screen.
- **Why:** Indie attention discipline — both competitors' online is the most
  expensive system they operate. This is a *timing* choice, not a stack limit; if
  later the vision needs it, networked play becomes a planned phase rather than a
  "can't". [self_audit.md §2.2 Multiplayer]

---

## Cross-cutting constraints (apply to every item)

- **Test discipline is non-negotiable.** Baseline = 144 GDUnit tests green (0 errors/failures/flaky). Every item above ships with its test note; headless run order per AGENTS.md (import probe first, then `-s` run with `--ignoreHeadlessMode` *after* the tool-script path). Warnings-as-errors and same-type `is_equal_approx` gotchas apply to all new suites.
- **No tech ceiling.** Every item is its ideal solution; Godot/current-architecture
  reuse is a convenience, not a bound. Engine/tooling/physics/rendering changes are
  in scope when they serve an item's "Why" — flag the cost estimate, don't pre-trim
  the ambition (see the "No tech ceiling" section above).
- **Streaming hot path is load-bearing.** Phase 3.4 is the one place we touch the
  streaming hot path incrementally; even there, the goal is correctness first, then
  whatever architectural improvement the profiling demands.
- **Worldgen stays deterministic.** `terrain_baker.gd` fixed-seed fBm/biome-table is a franchise asset (AGENTS.md); any baking change must keep the region-anchor + hash rules so tests stay reproducible.
- **License-safe pipeline is a franchise asset.** Original GLB cars via the Blender-MCP/Hyper3D flow stay; car count grows via data (`resources/cars/*.tres`) not new machinery.

---

## Quick wins / next sprint (do these first)

1. **Starter-car visual is a live bug-risk.** `resources/cars/starter_car.tres` (Striker) has no `visual_path`; confirm the first-launch default always resolves the SportsCoupe GLB via `car_visuals.gd` `_apply_visual()`, else players see an invisible car. Fix + add a regression assert. *(S — see audit §3)*
2. **GPS drive-line v0:** shortest-path on `road_network.gd` `get_roads()` → draw on `minimap.gd` using existing `map_roads.gd` fit/clip math. First visible "map is alive" win. *(M)*
3. **Skid/impact/wind audio layers** on `car_audio.gd` (extends the existing 3-bed crossfade, doesn't replace it). *(S)*
4. **Wheelspin "cone" HUD indicator + HP delta** on `race_ui.gd` from `drivetrain.gd` slip/RPM state. *(S)*
5. **Night headlight/taillight layer** on `car_visuals.gd` (extra lights + tail emission) gated by `sun_driver.gd` time-of-day. *(S)*
6. **Photo mode v0:** hide-UI + FOV/aperture sliders + screenshot export on top of `orbit_camera.gd`. *(S)*
7. **Local best-lap + HUD delta:** persist best lap per track/car-class in the save, show `+0.42s` on `race_ui.gd`; ghost playback next cycle. *(M)*
8. **Collectibles-as-POIs:** 5 bonus boards / speed traps as `poi_registry.gd` entries rewarding credits (once economy lands in 2.1). *(S)*

Suggested ordering for a single sprint: 1 → 4 → 5 → 3 (feel, all small) then 2 and 7 (map/alive loop), then 6 and 8 (marketing surface).