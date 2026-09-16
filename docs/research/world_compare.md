# UltraDrive vs Forza Horizon 6 — Open-World Map Comparison

> World-design gap analysis. Companion to `fh6_map.md` (FH6 reference dossier) and
> `self_audit.md`. UltraDrive facts are grounded in the codebase as of 2026-09-16
> (Godot 4.7.2, read-only survey; no code modified). FH6 figures are repeated with
> their original ⚠ confidence caveats from `fh6_map.md`.
>
> **Method note:** road counts/kilometres were *re-derived numerically* from the
> exact generator code (see §10), not measured in-game.

---

## Scorecard

| # | Dimension | FH6 | UltraDrive today | Gap size |
|---|---|---|---|---|
| 1 | Map scale & verticality | ~246 km² ⚠, 6 biomes, ~3,000 m alpine peaks | ~37 km² nominal footprint, 5 *numeric* elevation bands (1 visual biome), ~60 m max relief | **Severe** (≈7× area, ≈50× relief, no visual biomes) |
| 2 | Road network hierarchy | 673 roads, 4 tiers (expressway/touge/coastal/rural-dirt) | **3 roads**, 1 tier + 1 touring ribbon + 1 loop, all asphalt | **Critical** (0.4% of the road count) |
| 3 | Elevation as gameplay | Alpine friction, seasonal routing, stacked urban planes | Elevation is cosmetic only; grip is global, season = nothing | **Critical** (mechanic absent) |
| 4 | Discovery & route line | Fog of war, grey→white roads, free fast travel, GPS/autodrive | Map fully revealed, no fog of war, no fast travel, no route line | **Critical** (loop intact, reward absent) |
| 5 | Events by car culture | Touge duels ×5, drag meets ×3, drift circuit, street races, Colossus | No open-world events; 3 road chains exist to be used | **Critical** |
| 6 | Collectibles/dressing density | 400 collectibles, 15 barn finds, 9 treasure cars | **5 non-interactive POI dots**; no pickups | **Critical** |
| 7 | Regional climate/weather + TOD | 72 weather micro-stations ⚠, per-region seasons, ~60 min day | One global weather enum, clock advances **never** | **Major** |
| 8 | Traffic & living-world density | Drivatars, dense traffic, 3 car meets, convoys | TrafficSpawner exists (max 15) but is **not wired into the open world** | **Major** (absent at runtime) |
| 9 | Streaming/tech | DirectStorage tiles, ~4 s shader first-load, vertical multi-axis streaming | Threaded region bakes, prefetch ring, corridor pre-bake; dressing **not** streamed | **Moderate** (sound core, thin content) |
| 10 | Road counts & data | 673 roads / ~540 mi ⚠ | 3 chains / **6.4 km** / 666 points | **Critical** (~99.6% by road count) |

---

## 1. Map scale & verticality

**FH6 has:** ~246 km² (⚠ fan estimate; 12.3×18.5 km footprint ⚠), six biomes
(Tokyo + Plains + Coast + Low mountains + Highlands + Alpine), the series' tallest
vertical axis — sea level to ~3,000 m Alps, with elevation used to *conceal* the map.
Density, not size, is the endorsed pitch (`fh6_map.md` §1.2–1.4).

**UltraDrive has:**
- Nominal footprint **0..6144 on X/Z** per `scripts/world/poi_registry.gd:5` ⇒ ~37.7 km² — but only two content anchors exist: hub (128,128) and mountain pass (3800,14,3200). The rest of the nominally-fittable map is un-authored terrain from `terrain_baker.gd`.
- Terrain is baked in **1024² regions** with a live 3×3 ring + prefetch radius 2 (`scripts/world/terrain_seeder.gd:21-23`) — an infinite-tiling heightfield, theoretically unbounded.
- Elevation: `HEIGHT_MIN=-5.0`, `HEIGHT_MAX=60.0`, alpine `DOME_AMP=42.0` at (5632,5632), `DOME_RADIUS=5000` (`terrain_baker.gd:36-42,146`). Worst-case relief ≈ **65 m**; the hub sits at 2.2 m, the pass road climbs to ~24 m (world_driver connector) — a ~22 m driveable climb.
- Biome *table* is real but numeric-only: spawn (base 2), rolling (base 6), highland (base 20), fallback (base 1), plus the alpine dome (`terrain_baker.gd:25-39,141`). In the **open world the colour map is never baked** — `terrain_seeder._bake_player_region`/`TerrainBaker.bake_region` write only `TYPE_HEIGHT` (FORMAT_RF); only the standalone `mountain_pass.gd:115-118` bakes an RGBA `color_img` (a single `GRASS_COLOR`). So the open world renders as **one visual biome**.

**Gap:** ~7× the area (at best) and ~50× the relief versus FH6, with no authored urban/coastal/lowland-biome *appearance* and no vertical obscuring structure. The elevation **pipeline** (seeded fBm + blended base + dome + road conform) is exactly the substrate a real biome spread would need, but today it only produces one green heightfield.

---

## 2. Road network hierarchy

**FH6 has:** 673 roads in four tiers — urban expressways (C1 inner loop ~14.8 km, Shuto, Wangan, perimeter), touge passes (Mt. Haruna, Bandai-Azuma Skyline, 5 official Touge Battle roads), coastal/scenic touring roads (Hakone Turnpike, Izu Skyline), and rural/dirt off-road lanes (`fh6_map.md` §2.2).

**UltraDrive has — exactly three roads** (`scripts/world/world_driver.gd:62-80`):
| Chain | Source | Width | Type |
|---|---|---|---|
| Hub ring | `_hub_ring()` (96 pts, r=110, world_driver.gd:82-87) | 12 m | Closed loop, flat (.691 km, measured) |
| Pass connector | `_pass_connector()` Catmull-Rom, ~5.3 km, 534 pts (world_driver.gd:91-130) | 10 m | **Open ribbon**, Y ramps 2.2→14 |
| Pass loop | mountain_pass `_generate_road_points()` (36 pts, ±10.5 m Y wobble, mountain_pass.gd:201-212) | 11 m | Closed winding loop (.374 km, measured) |

All three use `TrackBuilder.build_track()` (`scripts/track/track_builder.gd:15`) which emits a **flat, single-width, unbanked** strip + trimesh collision + two edge lines. There is:
- **No highway/expressway tier** — the connector is the closest thing to a touring route and is just one 10 m lane.
- **No coastal ribbons, no dirt/off-road lanes** — `road_network.gd` has no surface type at all; a road is a width + a point array (`road_network.gd:8,14`).
- **No junctions/intersections** — the connector simply *lands on* the pass loop start; there is no node/edge graph, only chain arrays (`road_network.gd:8` `_roads: Array[Array]`).
- **No elevated/stacked roads** — a road is a single strip following points; no banking/camber/tunnels.

**Gap:** Road *hierarchy, surface diversity, junctions* are all absent. FH6's 673 roads vs 3 — the map reads as "one track to a destination", not a network.

---

## 3. Elevation as gameplay

**FH6 has:** alpine blizzards/ice changing effective route choice, mountain passes where rally cars "drift down steep roads into tight hairpins", winter seasons that punish RWD, and Tokyo's three stacked driving planes (street → elevated expressway → tunnel) (`fh6_map.md` §1.3, §2.4, §3.5).

**UltraDrive has:**
- Grip varies **only by global weather**: `vehicle_physics.gd:99` `grip_mult *= WeatherManager.get_road_grip_factor()`; the table is one global dict `weather_manager.gd:15-22` (snow 0.45 → clear 1.0).
- **No surface-type grip** (asphalt/grass/gravel/dirt lookups) — flagged P0 in `self_audit.md` §2.1 ("no surface-type variance"). The 3 roads ride at different elevations but the accent is visual only.
- **No seasons, no regional routing** — a single `Weather` enum.
- **No stacked urban planes** — there is no city; `TrackBuilder` can't do over/under passes or camber.

**Gap:** Elevation exists (relief + road climbs) but never *does anything*. The alpine dome is where the connector goes flat; nothing at altitude behaves differently from the hub.

---

## 4. Discovery & route line

**FH6 has:** first-in-franchise fog of war; roads grey→white/orange as you drive them; fast travel to *any discovered road point*; ANNA drone reveal; autodrive with cinematic camera (`fh6_map.md` §2.5). Discovery is the core loop.

**UltraDrive has:**
- A minimap (`scripts/ui/minimap.gd`) and full pause map (`scripts/ui/world_map.gd`) that render **every road and all 5 POIs, always on**, via `MapRoads` (`scripts/ui/map_roads.gd:45-53` signature, `:71-99 compute_fit`). The map is fully revealed from frame one — **no grey/white discovery, no fog of war**.
- **No fast travel.**
- **No GPS route line** — `self_audit.md` §2.1 P0 ("Route computation on `MapRoads` graph"). The graph primitive exists (`MapRoads`, `RoadNetwork.get_roads()`, `get_nearest_road_pos()` at `road_network.gd:24-33`) but nothing computes a route.
- No autodrive / tourism mode.

**Gap:** The map *rendering* loop is complete; the *reward* layer (reveal + travel + route) is entirely absent.

---

## 5. Events placed by car culture

**FH6 has:** Horizon Rush ×3, Drag Meets ×3, Touge Battles ×5, street racing (night, Tokyo), Time Attack circuits, drift circuit, PR stunts, Showcases and the full-map Colossus marathon — each attached to a real place and driving subculture (`fh6_map.md` §3.1).

**UltraDrive has:**
- `scripts/race/race_manager.gd` / `scripts/race/lap_counter.gd` / `scripts/race/checkpoint.gd` + HUD — a complete **circuit race loop**, but only reachable via track-select for the 2 circuits (Sunset Oval, Mountain Pass) (`self_audit.md` §1.2); `track_select.gd:112` `RaceManager.queue_race(laps)` opens a menu, not a world event.
- `scripts/race/drift_scorer.gd` exists (standalone) — no drift zone placed in the world.
- **Nothing in the open world is an event.** No touge duel, drag strip, street race, marathon, or even an event marker. The P0 gap "no sprint/elimination/time-attack/drift/checkpoint events, no event markers" (`self_audit.md` §2.1) stands.

**Gap:** The *event engine* is missing entirely; the three generated roads currently exist only for touring.

---

## 6. Collectibles / dressing density

**FH6 has:** 400 collectibles (200 mascots + 200 bonus boards), 15 barn finds, 9 treasure cars, 76 discoverable areas, roadside aftermarket cars (`fh6_map.md` §3.4).

**UltraDrive has:**
- **5 non-interactive POI dots**, hardcoded in a static dict (`poi_registry.gd:7-33`), drawn as circles on the pause map (`world_map.gd:43-45`). No discovery trigger, no reward, no interaction.
- World dressing is **authored in code but never instantiated in the open world**:
  - `scripts/world/prop_scatterer.gd` — MultiMesh guardrail/tent/power-pole/rock, per-zone presets of **14–28 props** (e.g. festival 14 tents, highlands 26 guardrails, `prop_scatterer.gd:89-127`);
  - `scripts/world/foliage.gd` — 700 grass tufts + 40 trees per instance, wind shaders;
  - Neither appears in `scenes/world/open_world_root.tscn` (verified: **zero .tscn references to PropScatterer/Foliage/TrafficSpawner**). `Foliage.new()` is only used by the standalone `mountain_pass.gd:59-64` and `test_circuit.gd:44`; the open world's `MountainPassZone` sets `build_foliage=false` (`regions/mountain_pass_zone.tscn:7-9`).

**Gap:** The dressing *systems* are built and tested; the open world currently ships **bare heightfield + 3 roads + 5 dots**. No pickups, no boards, no barn finds, no discoverable landmarks beyond the dots.

---

## 7. Regional climate / weather zoning & time-of-day

**FH6 has:** dynamic per-region weather (72 micro-stations ⚠), ~60-min day (~40 day/~20 night), weekly per-region seasons, permanent alpine snow, all with grip/visibility tables per condition (`fh6_map.md` §3.5).

**UltraDrive has:**
- One **global** weather enum, `Weather { CLEAR, CLOUDY, RAIN, STORM, FOG, SNOW }` (`weather_manager.gd:6`) with **one shared grip table** (`:15-22`). No per-region/zone state, no micro-stations, no seasons.
- **The clock never advances.** `WeatherManager.advance_time()` (`:39-40`) exists but nothing calls it (grep: zero callers outside its own definition). The world sits at `time_of_day = 12.0` (`:12`) and the sun is a pure function of that (one static hour) via `world_driver.gd:192-213` / `sun_driver.gd`. There is no day/night *cycle* at all.
- No precipitation VFX, wet-road shader, or night headlights — P0 list in `self_audit.md` §2.1/§2.2.

**Gap:** Weather is a "one-shot toggle", not a living climate. Even the FH-favored global day/night cycle is missing because `advance_time()` is never driven.

---

## 8. Traffic & living-world density

**FH6 has:** Drivatars (behaviour-capture cloud AI, "roads are never empty"), denser traffic than FH5, 3 no-loading Car Meets, convoys up to 12, 72-player sessions ⚠ (`fh6_map.md` §3.2–3.3).

**UltraDrive has:**
- `scripts/world/traffic_spawner.gd` — a complete traffic manager (max 15, road-spawned via `is_on_road`, distance-culled audio, deterministic-ish) — **but it is not instantiated anywhere in the open world** (no node in `open_world_root.tscn`; only unit-tested in `tests/test_traffic_spawner.gd`).
- `scripts/ai/ai_controller.gd` + `ai_rubber_banding.gd` — waypoint-follow AI for races only.
- No car meets, no convoy, no living-world social layer (multiplayer is post-v1 per `self_audit.md` §2.2).

**Gap:** The pieces to populate the world (traffic spawner, road-following AI) exist; the open world is empty at runtime.

---

## 9. Streaming / tech approach

**FH6 has:** DirectStorage 1.2/1.3 + GPU GDeflate, **Advanced Shader Delivery** (~90s→~4s first load), tile-based continuous terrain streaming, multi-axis vertical asset requests (elevated/underground), peak ~2 GB/s in Tokyo ⚠ (`fh6_map.md` §4).

**UltraDrive has — a genuinely comparable core:**
- `terrain_seeder.gd` worker-Thread region bakes (pure `TerrainBaker` math off the main thread, Mutex/Semaphore, `_lock`), live 3×3 ring, **prefetch ring ±2**, **corridor pre-bake** capped at 40 region-locs near spawn, ≤2 applies/frame, player region sync ~3.3 s cold-start (`terrain_seeder.gd:21-30,107-124,316-323,451`; AGENTS.md).
- Baked images cached so re-entering a region skips the rebuild (`_baked` cache, `:37`).
- **The mismatch:** terrain/region culling is mature, but **props/foliage/traffic are not region-streamed** — they're spawn-once (or not at all). `self_audit.md` §3 flags exactly this ("props/foliage/traffic are spawned once … will be a load/perf bottleneck if the world grows").
- `chunk_streamer.gd:8-11` exists mostly as a flat-chunk placeholder; Terrain3D owns the real ground (`open_world_root.tscn:63-74`).

**Gap:** Moderate. The *plumbing* beats what an indie usually has; the *payload* is thin (height only, no per-region dressing/colour/objects), and there's no shader-precompile equivalent (cold import is a documented multi-step headless dance in AGENTS.md).

---

## 10. Road counts & data (measured)

Re-derived numerically from the exact generators (read-only):

| Metric | Value | Where from |
|---|---|---|
| Road **chains** in open world | **3** | `world_driver.gd:75-78` (hub ring + connector + pass loop) |
| Road **points** in `RoadNetwork._roads` | **666** (96 + 534 + 36) | `world_driver.gd:84`; `:101`; `mountain_pass.gd:203` |
| Driveable kilometres | **6.4 km** (0.691 + 5.330 + 0.374) | measured: ~5,330 m connector spline, 691 m hub, 374 m pass |
| Terrain-conforming samples (2 m) | ~3,707 | `terrain_baker.gd:49` SAMPLE_SPACING re-upsample |
| Region size / live ring | 1024² / 3×3 + prefetch 2 | `terrain_seeder.gd:21-23` |
| Nominal map footprint | ~37 km² (6144²) — mostly un-authored | `poi_registry.gd:5` |

For comparison, FH6: **673 roads** (press-confirmed) and ~540 mi of road ⚠ (`fh6_map.md` §2.1, §6). By FH6's own counting unit, UltraDrive has **3 roads = 0.4%** of the reference. Even FH6's *single* C1 loop (14.8 km) is 2.3× the entire UltraDrive road network.

Honest caveat: "road" is not an apples-to-apples unit (FH6 splits a district into countably many named roads); but the difference in *network density and hierarchy* is not a counting artifact — UltraDrive has one through-route and two loops.

---

## What UltraDrive is missing to feel FH6-like (ranked)

1. **A real road network with classes, junctions, and count.** `road_network.gd` is 3 chains; ~673-scale density is unrealistic for the next sprint, but a *classified* network (highway/touge/coastal/dirt + intersections) is the single highest-leverage add — it feeds roads→bake→maps→placement→events all at once. (P0; `road_network.gd`, `world_driver.gd:62-80`, `track_builder.gd` needs width/camber/surface params.)
2. **Wire the already-built dressing into the open world.** PropScatterer + Foliage + TrafficSpawner exist, are tested, and are simply not instantiated in `open_world_root.tscn`. Cheapest "alive world" win in the whole list. (P0; `open_world_root.tscn`, `prop_scatterer.gd`, `foliage.gd`, `traffic_spawner.gd`.)
3. **Discovery as a loop: fog of war + grey/white road reveal + free fast-travel to discovered roads.** The map rendering already resolves the road source (`map_roads.gd:13-21`); add a per-segment visited bit and a "fast travel to any visited road point" — FH6's core reward. (P0; `map_roads.gd`, `world_map.gd`, `poi_registry.gd`.)
4. **GPS route line on the existing road graph** (`get_nearest_road_pos` already gives you a graph to crawl). (P0 confirmed in `self_audit.md`.)
5. **Regional climate + a running clock.** Call `WeatherManager.advance_time()` in the world, split weather by zone, add seasonal routing (snow-locked pass). Everything already reads global (vehicle grip, sun). (P1; `weather_manager.gd`, `world_driver.gd:159-162`.)
6. **Place events on roads: touge-duel + drift-zone + drag-strip + time-attack markers** reusing RaceManager/Checkpoint/DriftScorer, attached to the existing routes. (P1; `race_manager.gd`, `checkpoint.gd`, `drift_scorer.gd`.)
7. **Region-streamed dressing** — spawn props/foliage/traffic per streamed region (2/frame like bakes) instead of once at ready, so a bigger network doesn't stall. (P1; `terrain_seeder.gd` apply-drain pattern, `chunk_streamer.gd`.)
8. **Bake the colour map in the open world** so the 5 numeric elevation bands read as 5 visual biomes (the seams already exist in `terrain_baker.gd:25-39`; `terrain_seeder` just needs a colour pass alongside `TYPE_HEIGHT`). (P1.)
9. **Collectibles/landmarks** — turn the 5 POI dots into triggerable discoveries + bonus boards via POIRegistry. (P2; `poi_registry.gd`, `world_map.gd`.)
10. **An urban/elevated tier** (C1-style ring, stacked planes, buildings) — the biggest build; `TrackBuilder` cannot express it today and there is no city geometry. North-star content, not a near-term fix. (P2; `track_builder.gd`, new `regions/` scene.)

**North star for the next cycle:** the streaming + deterministic world-gen architecture is already FH-flavored; what's missing is *population* (dressing × traffic × events) and *incentive* (discovery × route × regional climate) layered onto a network that's currently 3 roads and a 6.4 km drive.