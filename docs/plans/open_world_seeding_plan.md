# UltraDrive — Open-World Road System & Seeding Plan

> Gap-fill implementation plan for the UltraDrive open world: a big, classified,
> deterministic road network (highways, touge, coastal touring roads, dirt/off-road
> lanes) sitting on the existing terrain seeder/baker pipeline, folded into the
> master roadmap.
>
> **Written:** 2026-09-16 · **Inputs:** `docs/research/fh6_map.md`,
> `docs/research/world_compare.md`, `docs/research/self_audit.md`, `docs/ROADMAP.md`,
> `AGENTS.md` · **Grounded in:** the live world code (read-only survey of
> `scripts/world/*.gd`, `scripts/track/*.gd`, `scripts/ui/*.gd`,
> `autoload/weather_manager.gd`, `scenes/world/open_world_root.tscn`).
>
> **Two hard rules this plan is written against:**
> 1. **No tech ceiling** (ROADMAP.md §“No tech ceiling”). Ambition first; engine,
>    architecture, plugin or hot-path rewrites are in scope when they best serve a
>    goal — cost is the filter, not capability. Where a phase needs a repo/design
>    change that goes beyond "tweak a constant", it is called out explicitly.
> 2. **144-GDUnit + deterministic worldgen are franchise assets.** Every phase below
>    names the suite that gates it; headless workflow stays per AGENTS.md (import
>    probe first, then the `-s` run with `--ignoreHeadlessMode` *after* the
>    tool-script path). `terrain_baker.gd` fixed-hash/fBm reproducibility and the
>    `TerrainSeeder` region-anchor rules are non-negotiable.

---

## 1. VISION

UltraDrive's open world grows from a 6.4 km "one track to a destination" into a
**60–150 km deterministic road network** that is a *place to drive*, not a path:
a classified, graph-based road system in five tiers — a perimeter **highway** ring
with long fast straights and banked sweepers, multi-lane **arterial** connectors
between hubs, hard-packed alpine **touge** passes with switchbacks and hairpins,
sea-hugging **coastal touring** ribbons with clifftop drops, and hidden **dirt /
off-road** cut-throughs that only reward drivers who leave tarmac — all auto-seeded
from a master world seed (waypoints → spline → conform-to-terrain) with the *existing*
`TerrainBaker` washbed clipping, so a reader can compute the whole 37+ km² world the
same way it is rendered. The terrain they sit on stops being a cosmetic 1-green
heightfield: a rebuilt elevation/bio table (10 bands, no 60 m ceiling) plus a baked
RGBA color map paint real massifs, highland plateaus, coastline, farmland and an
alpine snow belt; off-road surface grip *does* something (asphalt/gravel/dirt/mud/
snow feed `TireModel`); a running regional clock + per-region climate drives the sun,
weather and seasonal route locking; and the map's core loop is FH6's — **fog-of-war
road reveal, fast travel to any discovered point, a GPS route line, and cultural
events (touge duels, drag strips, drift zones, night street loops, a full-map
highway marathon) living on the roads where they belong**, kept green by the 144+
GDUnit discipline. This is the "living map" pillar of the ROADMAP's north star, and
everything here is achievable at indie scale because the deterministic worldgen and
streaming architecture are already FH-flavored — what's missing is population,
incentive, and count.

---

## 2. PHASED IMPLEMENTATION PLAN (P0 → P7)

Ordered by dependency. Effort is T-shirt (S/M/L/XL) for the 1–2 person team.
Each phase: **What / Why / How / Effort / Test-gate** (+ explicit architecture
changes where the no-tech-ceiling rule applies).

---

### P0 — Road classification & network graph
**Turn `RoadNetwork` from a list of point-arrays into a typed graph with topology, routing, and per-road identity.**

- **What:**
  - Introduce a road-definition struct/resource: `{ id, tier, name, width, closed,
    surface, banking, points: Array[Vector3] }`.
  - Add a road tier enum: `HIGHWAY / ARTERIAL / TOUGE / COASTAL / DIRT` with default
    widths and surface per tier (highway 16–18 m asphalt w/ banking; arterial 10–12 m;
    touge 9 m winding asphalt; coastal 9 m panoramic; dirt 6–8 m gravel).
  - Upgrade `road_network.gd` internals: `_roads` stays the canonical point storage
    (minimap/map/`MapRoads.get_roads()` keep working untouched), but the network also
    builds **junction nodes** wherever two chains come within a link threshold (the
    pass connector currently just *lands on* the pass loop — it should be a real
    intersection), and exposes **graph queries**: `nearest_road_id(pos)`,
    `neighbor_roads(road_id)`, `route(road_id_a, road_id_b)`.
  - Extend `TrackBuilder` to carry tier params: `road_width` already exists; add
    `banking` (superelevation on turns — rotate the strip normal right/left by a
    signed amount derived from curvature), surface-driven **material palette**
    (asphalt blacktop vs gravel tan vs snow white), and per-tier edge-line color.
- **Why:** It's the single highest-leverage add in the world (`world_compare.md` gap
  #1, scored **Critical**): a classified network feeds the bake (roads→conform), the
  map (grey→white tiers), placement (events need tier-valid sites), routing (GPS),
  and events all at once. FH6's map is a "network of iconic runs", not a flat plane —
  tier identity is what makes a touge feel different from a highway before physics
  even runs.
- **How:**
  - `scripts/world/road_network.gd`: keep `add_road(points, width, closed)` as a
    thin shim that deletes to `add_road_def(RoadDef)` so existing callers
    (`world_driver.gd:_bootstrap_roads`, `MapRoads`, `PropScatterer._road_ok`) don't
    change. Persist the defs beside `_roads`; build the adjacency/junction table once
    via a pure `build_topology(roads, link_threshold)` helper.
  - `scripts/track/track_builder.gd`: extend `build_track(points, closed, tier)`;
    compute per-vertex banking from the forward/right frame in `_build_mesh()`
    (right vector already computed at line ~94) and offset the vertex Y by
    `banking * cross-slope * half_width`. Keep the concave trimesh path so Jolt
    collision stays watertight.
  - Routing: a new pure `scripts/world/road_graph.gd` (RefCounted, no tree access —
    mirror `map_roads.gd` static-pure pattern) computing shortest path on the
    adjacency, Dijkstra over per-chain point heuristics first, refined to segment
    resolution later.
- **Effort:** M (~2–3 wks).
- **Test-gate:** new `tests/suites/test_road_graph.gd` — junction detection is
  deterministic and complete for the current 3-chain bootstrap, adjacency is
  symmetric and connected, routing returns a valid chain-sequence shortest path,
  tier metadata round-trips, and the old `get_roads()`/`is_on_road()`/
  `get_nearest_road_pos()` behaviors are byte-identical (existing open-world +
  world-map suites stay green). No scene frames needed (pure logic).
- **Architecture note:** this is a data-structure upgrade only — no engine change.
  `TrackBuilder` banking touches mesh/complexity in `_build_mesh`, flagged as the
  first place where we deliberately deviate from "flat strip" (`self_audit`'s
  tallest gap #10 is still future work; banking here is camber, not stacked planes).

---

### P1 — Elevation & biome overhaul + color-map bake
**Make the terrain itself a multi-biome, genuinely vertical stage — and render it.**

- **What:**
  - Replace the `HEIGHT_MIN=-5.0 / HEIGHT_MAX=60.0` clamp (`terrain_baker.gd:41-42,
    97,146`) with an **elevation band model**: discrete base bands per region
    (`plains 0–10`, `rolling 10–60`, `lowland-foothill 60–200`, `highland 200–600`,
    `alpine 600–1,500+`) blended like the current biome table but ordered
    *elevation-monotonic* (a lowland can't be higher than a highland saddle crossing
    its band). Introduce a **sea-level band** (heights below ~0 m read as water/wet
    lowland) with a shoreline rule so coastal roads hug a real coastline.
  - Grow the biome table from the current 4 anchoring bases
    (`BIOME_SPAWN/ROLLING/HIGHLAND/FALLBACK`, `terrain_baker.gd:25-34`) toward a
    **~10-band palette** (spawn plains, farmland, coast, rolling, forested lowland,
    highland plateau, alpine snowline, fallback, plus the sea-water mask and the
    road-clearance washbed), with **real massifs**: multiple `DOME_*`-style radial
    mountains (the existing single `DOME_AMP=42` at (5632,5632) becomes a family of
    amped domes + ridgelines) placed so major touge corridors climb, not flatten.
  - **Bake the color map.** `terrain_seeder._bake_sync`/`_write_region` currently
    write only `Terrain3DRegion.TYPE_HEIGHT` (FORMAT_RF); write a deterministic
    `TYPE_COLOR` RGBA image alongside it so the numeric bands read as visible biomes.
    Precedent already exists: `scripts/track/mountain_pass.gd:105-116` bakes an RGBA
    `color_img` and applies it as the third element of `[height_img, null, color_img]`
    — mirror that in the open-world pipeline, including a road-surface tint paint
    along conformed corridors.
  - Elevation becomes *gameplay substrate*: alpine snow belt, gradient-restricted
    routes (P4's seasonal routing reads these bands).
- **Why:** FH6 is "most dense and vertical": 6 biomes, ~3,000 m peaks, and elevation
  that *conceals* the map. UltraDrive today renders **one green biome** and ~65 m of
  relief (`world_compare.md` gap #1, ~50× less). The fixed-seed fBm + blended-table
  pipeline is exactly the substrate a real biome spread needs — this phase is
  parameterization plus one new image channel, not net-new machinery.
- **How:**
  - `scripts/world/terrain_baker.gd`: introduce `bake_region_color(region, scale,
    width, roads)` returning `Image.FORMAT_RGBA8`, sharing the *same* biome-weight
    math (`_biome_base`/`_biome_weight`) so color and height are perfectly correlated;
    replace the hard clamp with per-band clamps that preserve elevation order; keep
    `_clip_chains`/`_conform_roads` road-carve untouched (it already wins inside the
    core radius). `bake_region()` signature is stable — add the color image as a
    sibling record, computed on the worker thread just like the height (same
    determinism, same cache record).
  - `scripts/world/terrain_seeder.gd`: extend the cached `_baked` record to hold
    `{"image", "color", "height_min", "height_max"}`; `_write_region` calls
    `region.set_map(Terrain3DRegion.TYPE_COLOR, color)` when present and folds the
    color channel into the existing `data.update_maps(...)` rebuild so the batched
    ring-pass discipline is preserved.
  - Terrain3D colormap rendering already exists (`open_world_root.tscn` has
    `show_colormap = true`) — no addon change.
- **Effort:** M–L (~3–4 wks; color pass is the bulk).
- **Test-gate:** extend `tests/suites/test_terrain_baker.gd` + a new
  `tests/suites/test_terrain_biomes.gd` — height-band ordering is monotonic across a
  sweep of region hashes, sea-level mask is consistent, color image is
  **bit-deterministic per region hash** (same input → same RGBA), road corridors
  still recess (existing conform tests stay green), and the headless watchdog
  discipline holds (region-bake diag never hangs).
- **Architecture note:** this is the phase where the *"[Godot] Terrain3D can't"* test
  gets forced — if `TYPE_COLOR` at full region resolution proves a memory/bandwidth
  problem at streaming speed, the no-tech-ceiling answer is a half-res color map +
  a custom terrain shader that samples it (or a Terrain3D fork). Cost, not
  capability: state it in the PR if we hit it. *(Expectation: full-res RGBA8 for a
  1024² region is ~4 MB/region — fine — but verify with profiling rather than assume.)*

---

### P2 — Large-corridor auto-seeding (the 60–100 km classified network)
**Author/grow the network deterministically: seed waypoints → spline → conform-to-terrain, tier-aware.**

- **What:**
  - A **corridor blueprint** system: a master world seed (fixed, e.g. derived from
    `TerrainBaker.NOISE_SEED`) deterministically emits a set of corridor definitions:
    - **Highway perimeter ring** — the FH6 "Colossus" full-map fast loop (wide, long
      straights, banking on curves), a closed long-arc circuit around the footprint.
    - **Arterial connectors** — hub↔highway on-ramp links, hub↔pass, hub↔coast
      (open ribbons like today's `_pass_connector`, `world_driver.gd:91-130`).
    - **Touge passes** — switchback-laden mountain climbs into the new P1 massifs,
      generated by spline serration (re-sampled with hairpin folds where the gradient
      exceeds a slope budget).
    - **Coastal ribbons** — splines that follow the P1 sea-level band within a
      tolerance (a "hug the coast" conformer), scenic dead-ends/overlooks at their
      tips (open chains, no phantom close via `_chain_is_closed`).
    - **Dirt cut-throughs** — short cross-country connectors between non-adjacent
      networks, narrower, gravel surface, occasionally dead-ending at overlooks.
  - A shared **spline toolkit**: extract `_catmull_rom_xz` (today private in
    `world_driver.gd:135-153`) into a pure `scripts/world/spline.gd` (Catmull-Rom +
    resampling by arc length + gradient profile ramping, so Y follows terrain
    conforming instead of the hand-ramp lerp).
  - `_bootstrap_roads()` (`world_driver.gd:62-80`) stops hand-instantiating 3 roads
    and instead instantiates the blueprint's corridors; ordering stays
    `set_roads()` **before** the first `_push_player_position()` so the bake
    conforms under every road before the first height lookup (critical ordering from
    AGENTS.md).
  - Interact with the washbed: each tier maps a `(width, topping, blend)` tuple into
    the baker (`ROAD_WIDTH=11 / ROAD_TOPPING=0.15 / BLEND_END_DISTANCE=40`) so wider
    highways carve wider channels; `_clip_chains` spatial clipping already keeps the
    per-region cost O(cells×clipped-segments) — verify it holds with 10× the roads.
- **Why:** This is the "count" fix — FH6 ships 673 roads; we ship 3 (0.4%,
  `world_compare.md` §10). But FH6's lesson is **density/hierarchy, not sheer
  number**: a classified, 60 km network with four distinct character classes
  delivers the "network of iconic runs" faster than grinding toward 600 artificial
  segments. Every downstream system (bake, map, events, GPS) needs the *topology +
  tier*, which P0 built — P2 buys the *extent*.
- **How:**
  - `scripts/world/corridor_planner.gd` (pure RefCounted, deterministic): takes the
    master seed, biome/elevation queries (height bands from P1 + `Terrain3DData`
    height lookups via a `Soothing` callable — reuse the
    `ground_height_provider: Callable(Vector2 → float)` convention from
    `foliage.gd`/`prop_scatterer.gd` and `mountain_pass.gd:89`), and road tier
    defaults; returns the corridor list ready for `RoadNetwork.add_road_def`.
  - `terrain_seeder._prebake_corridor` (`:107-125`) is the streaming guard: raise
    `MAX_CORRIDOR_LOCS` from 40 and add a per-tier priority (highway ring first, then
    arterial, then touge/coastal, dirt last) so the 100 km network still pre-bakes
    ahead of the player without flooding the worker; keep `PRIORITY_LIVE` the winner.
- **Effort:** L (~4–6 wks).
- **Test-gate:** new `tests/suites/test_corridor_seeding.gd` — given a fixed seed,
    total km ≥ target, tier counts exact, closure detection correct per corridor
    type (`_chain_is_closed` wrapping tested with the "nearly-touch" rule — the open
    hub→pass connector must NEVER get a phantom chord), all road points conform into
    a washbed within bounds, determinism: same seed → same chain hash; two seeds →
    different. Keep the streaming suite `test_terrain_seeder_streaming.gd` green
    (corridor pre-bake grows but region-anchor + cache rules don't change).
- **Architecture note:** extraction of a shared spline module is a refactor of
  `world_driver.gd` internals (behavior-preserving; the diff is guarded by the
  seeding tests). This is the phase where "a written, authored map" becomes
  "a generated, readable map" — that decision is deliberate because the franchise
  asset is *reproducibility*.

---

### P3 — Off-road capability (surface grip & consequences)
**Make surface a real physics input: per-tier + off-road grip variance feeding the tire model.**

- **What:**
  - A **surface registry** (pure): `SURFACE_GRIP` table for `ASPHALT / GRAVEL /
    DIRT / MUD / SNOW / GRASS` with lateral & longitudinal multipliers (roughly:
    asphalt 1.0, gravel 0.85, dirt 0.8, grass 0.65, mud 0.5, snow/ice 0.45–0.3 —
    styled on the FH6 impact table in `fh6_map.md` §3.5, kept as data so tuning is
    trivial).
  - **Surface detection at the wheel/con car**: `VehiclePhysics` samples ground
    under the car — if the nearest road is `ROAD_TOPPING`-close (i.e., a `DIRT` or
    `GRAVEL` tier) use the road's surface; else classify the terrain by the P1 biome
    band (grass/farmland, gravel shoulders, mud lowland, alpine snow) — deterministic
    per region hash, no perf-cost raycast per wheel required (one sample per frame).
  - Hook into the existing grip path: `vehicle_physics.gd:98-99` currently multiplies
    `grip_mult = config.{arcade|sim}.grip_multiplier * WeatherManager.get_road_grip_factor()`.
    Widen it to `grip_mult *= surface_factor * weather_factor`, and pass the surface
    factor into `TireModel.calculate_lateral_force` / `calculate_longitudinal_force`
    (`tire_model.gd:12,32`) so both axes degrade together.
  - Off-road *consequences*: DIRT/off-piste gives the rally hatch (`Dirt Devil`,
    `resources/cars/rally_hatch.glb`) its intended advantage window; light
    suspension/throttle mastery on gravel; a snow-bound alpine belt from P1 returns
    the steep-grip penalty that makes seasonal routing (P4) matter.
- **Why:** FH6's review praise is literally "wheels rolling convincingly over
  smoothly undulating dirt roads"; `self_audit` P0 flags "no surface-type variance
  (asphalt/grass/gravel)". Elevation/weather only matter once *surface* matters —
  this is the pivot that makes the DIRT tier a mechanical differentiator, not a
  palette choice.
- **How:** new `scripts/vehicle/surface_registry.gd` (RefCounted, static table +
  `classify(region_biome, distance_to_road, tier)`); `vehicle_physics.gd` calls it
  where it already calls `WeatherManager`; a `RoadTierProvider` callable — defaulting
  to `RoadNetwork` via `is_on_road`/tier lookup (P0) — keeps the physics headless-safe.
- **Effort:** S–M (~1.5–2.5 wks).
- **Test-gate:** new `tests/suites/test_surface_grip.gd` — per-surface multipliers
  apply to lateral AND longitudinal, detection is deterministic given
  (region, position, tier), weather × surface compounds correctly (snow on asphalt ≠
  snow on dirt), and no zero-divide at the lookup edges; keep `test_transmission`/
  physics suites green.
- **Architecture note:** none beyond a new pure module + one multiplication site.
  If we ever want *per-wheel* surface sim (distance-based mixed grip), that's a
  physics-layer upgrade — flagged here as a deliberate future split, not a blocker:
  the no-ceiling rule says we may go there when the profiler and feel demand.

---

### P4 — Regional weather & time-of-day
**A running regional clock, per-region climate bands, alpine snow/ice belt, seasonal routing.**

- **What:**
  - **Run the clock.** `WeatherManager.advance_time()` (`autoload/weather_manager.gd:39-40`)
    has **zero callers** today; the world sits frozen at `time_of_day = 12.0`.
    Drive it from `world_driver._physics_process` at a shippable rate (target FH6's
    ~60-min day → ~40 min day / ~20 min night; value is a constant, e.g.
    `1.0/2400` h/frame @60fps for a 40-min day). `sun_driver.gd` / `WorldDriver.
    _bootstrap_sun_driver` already react to `time_of_day_changed` — verify the gated
    night lighting from ROADMAP 1.5 uses this same signal.
  - **Regional climate bands.** A pure `RegionalClimate` sampler: partition the
    world by P1 biome band + a per-region weather node (5+ bands: plains/farmland —
    dry/clear + storms; coast — tropical rain; lowland — mist/fog; highland —
    storms occasionally snow; **alpine — permanent snow/ice belt**, FH6's year-round
    snow). `WeatherManager` stays the global enum, but the *active* weather is
    sampled from the player's region (deterministic per region hash), and grip/VFX
    tables read the regional state.
  - **Seasonal routing:** a season enum (Weekly rotation per FH6, data-driven) that
    (a) locks/unlocks the top touge corridor (snow-covered pass = route line avoids
    it or marks it `SEASONAL`) and (b) adjusts the alpine band's grip floor.
- **Why:** `world_compare.md` gap #7 (Major): one global weather enum, clock that
  "advances never", season = nothing. FH6's regionalized seasons + alpine friction
  turn *route choice* into gameplay; this is the cheapest high-impact "alive world"
  layer after dressing. It also connects to ROADMAP Phase 1.5 (weather VFX + night)
  — this phase supplies the *signal*, 1.5 supplies the *visuals*.
- **How:**
  - `scripts/world/regional_climate.gd` (RefCounted, deterministic): `sample(pos,
    time, season) -> {weather, snowline, grip_mod}` using the P1 band weights; a tiny
    autoload or a WorldDriver child pulses `WeatherManager.advance_time()` and
    re-samples on region change (cheap: only on ring entry, `sync_player_pos`).
  - `weather_manager.gd`: keep the enum + global tables (other code reads them) but
    let the regional sampler set the *effective* weather via `set_weather()`; extend
    `ROAD_GRIP` to a 2D surface×weather lookup by folding in P3's table.
  - Save `/ road-map` compatibility: season is a persisted `GameState`/Settings key.
- **Effort:** M (~2–3 wks).
- **Test-gate:** extend `tests/suites/test_weather_sun.gd` + new
  `tests/suites/test_regional_climate.gd` — advancing the clock changes
  `get_time_of_day()` and emits `time_of_day_changed`; regional sampling is
  deterministic per (region, time, season); alpine never samples non-snow in winter;
  seasonal pass lock toggles the route gate; sun transform sweep stays clean
  (`test_weather_sun` still green).
- **Architecture note:** the "frozen clock" is a *stub decision*, not an engine
  limit — a running clock is one call + a real-time-source. Night/headlight VFX is
  explicitly ROADMAP 1.5; this phase guarantees the *signal* arrives on schedule.

---

### P5 — Discovery flow layers: fog-of-war, fast travel, GPS route line
**FH6's core reward loop on our existing map UI: revealed roads, travel-to-discovered, a route.**

- **What:**
  - **Fog of war + grey→white reveal.** A `WorldDiscovery` (autoload, or state on
    `RoadNetwork`/`GameState`) tracks a **per-road-segment visited bit** (world
    graded on a grid or per chain point within a reveal radius as the player drives).
    `minimap.gd`/`world_map.gd` switch from drawing every road to drawing
    visited=white/orange, unvisited=grey (`ROAD_COLOR` in `world_map.gd:9` /
    `minimap.gd:11` become visited/unvisited pairs). Persist visited state in the
    3 JSON slots (`autoload/save_manager.gd`) so discovery persists per save.
  - **Fast travel to any discovered road point.** FH6's most permissive fast travel
    (any point of any discovered road — `fh6_map.md` §2.5). The open world is a
    single scene, so this is a load-free teleport: pick a revealed road point on the
    pause map (`world_map.gd`) → instantiate/move the player car + settle the chase
    camera + re-push `_push_player_position()` so the ring already bakes around the
    destination. (Coupled with ROADMAP 1.8 rewind/reset for the "no soft-lock" bar.)
  - **GPS route line.** On the P0 graph: `route(from, to)` → chain-sequence → project
    to screen via existing `MapRoads.world_to_screen`/`world_to_local_points` +
    `compute_fit`/`clip_circle` and draw a highlighted polyline on minimap + world
    map. This is also ROADMAP 1.2's deliverable — one phase, one dependency.
  - **Autodrive v1 (tourism)** is the stretch tail: follow the GPS polyline with a
    cinematic camera (FH6's tourism mode). Mark optional in this phase.
- **Why:** The rendering loop (minimap + world map + `MapRoads` static math) is
  *complete and tested*; the **reward layer is entirely absent** (`world_compare.md`
  gaps #4/#3, Critical). This is the difference between a map and a "discover Japan"
  loop — and it retroactively justifies every kilometre P2 lays down.
- **How:** a pure `scripts/world/world_discovery.gd` (visited-bits + reveal) feeding
  the existing `MapRoads` static map; `minimap._draw_roads` and `world_map._rebuild`
  branch on visited state; pause-menu click-to-travel + a `SceneTransition`-less
  teleport (no loading screen — FH6's selling point). Route line = P0 `route()` +
  `MapRoads.clip_circle`.
- **Effort:** M (~2–3 wks; autodrive +1 wk, optional).
- **Test-gate:** new `tests/suites/test_discovery.gd` + `tests/suites/test_map_route.gd`
  — reveal is monotonic (no un-reveal), fast travel only accepts *revealed* points,
  route-line optimizes to the target and feeds `clip_circle` without degenerate
  points, visited state round-trips through `SaveManager` (same suite style as
  `test_world_map_features.gd`); discovery is deterministic and headless (no frames).
- **Architecture note:** needs a new autoload + save-field addition (small, additive
  to the 3-slot schema). No engine change. The single-scene open world makes
  load-free fast travel essentially free — that's our FH6 parity at a fraction of
  ForzaTech's cost.

---

### P6 — Living-world density: dressing + traffic + events by car culture
**Fill the world with the systems we already built, and place events the way FH6 does — by driving culture.**

- **What:**
  - **Wire the built-but-orphaned dressing into the open world** (`world_compare.md`
    gap #2, the cheapest "alive" win in the list): instantiate `PropScatterer`,
    `Foliage`, and `TrafficSpawner` in `scenes/world/open_world_root.tscn` (currently
    **zero** references — the open world ships a bare heightfield + 3 roads + 5
    dots). Give each `PropScatterer` a `configure(default_preset(zone))` where the
    zones already exist: `festival / lowlands / coast / highlands / alpine`
    (`prop_scatterer.gd:89-127`), point their `ground_height_provider` at
    `terrain.data.get_height` (the `mountain_pass.gd:89` convention) and
    `road_network` at `RoadNetwork`; wire `TrafficSpawner.update(player_pos)` from
    `world_driver._physics_process` at the spawn radius ring.
  - **Event placement by car culture** (FH6's lesson #3): on the P0/P2 tiers, place
    event markers at *tier-valid* sites:
    - **Touge duel** — a mountain/TOUGE corridor where gradient > threshold (reuse
      `RaceManager` 1v1 vs `ai_controller.gd` rubber-band-lite);
    - **Drag strip** — the longest straight highway segment (PackedVector2Array of a
      highway chain, find max-arc run; the hub ring + perimeter give candidates);
    - **Drift zone** — a hairpin-heavy touge segment or closed dirt ring (reuse
      `scripts/race/drift_scorer.gd` with a zone radius + clear line);
    - **Night street loop** — the hub ring/arterial under night lighting (P4 clock +
      ROADMAP 1.5 headlights) — a compact circuit on `RaceManager.checkpoint`/`lap_counter`;
    - **Marathon highway race** — the full perimeter highway (P2) as a "Colossus"-style
      long-distance point-to-point around the map;
    - **Time-attack landmarks** at `poi_registry.gd` anchors (5 exist; grow the
      registry per collectibles ROADMAP 2.3).
    Event sites are deterministic (same master seed) and exposed as
    `POIRegistry` entries + map markers (`world_map.gd` POI dots already draw).
  - Growing the POI registry from 5 dots toward collections/bonus boards (ROADMAP
    2.3) hangs off this phase's placement machinery.
- **Why:** Every required subsystem exists, is unit-tested, and is simply *not
  instantiated* in the open world (`world_compare.md` gap #8: "TrafficSpawner exists
  … not wired"; gap #6: 5 non-interactive dots; gap #5: no events). Wire-up beats
  new systems here; event-by-culture is the FH6 design move that makes the map feel
  authored.
- **How:** `.tscn` edits + a `WorldDriver`-driven update loop (traffic spawner
  already exposes `update(player_pos)`; prop/foliage re-generate when a region
  enters the ring — see P7 for the *streamed* form). Event definitions as data
  (`scripts/world/event_registry.gd`, pure, deterministic placement formula) feeding
  `RaceManager.queue_race`, `drift_scorer`, and a new sprint/touge helper —
  self_audit's event-type framework (ROADMAP 1.4) lands here.
- **Effort:** L (~3–4 wks).
- **Test-gate:** extend `test_prop_scatterer`, `test_traffic_spawner` + a new
  `tests/suites/test_event_placement.gd` — dressing spawns deterministically per
  region/preset and never overlaps roads (`road_network.is_on_road` rejection stays);
  traffic never exceeds `max_traffic`; event sites are tier-valid (touge on TOUGE,
  drag on longest-straight, drift on the target segment) and resolve through
  `POIRegistry`; each event's Win/Lose path reuses `test_race_loop.gd`'s
  sync-freeing `after_test` discipline.
- **Architecture note:** `.tscn` content wiring (no code smell) — the technical
  review here is "why weren't these instantiated" — they predate the open world.
  The `drift_scorer`→`RaceManager` seam may want a light `Event` base class;
  flagged as a small refactor, not a rewrite.

---

### P7 — Streaming & performance evolution for the bigger world
**Region-stream dressing, LOD, and keep correct near-player sync-bake as the network grows 10×.**

- **What:**
  - **Region-streamed dressing.** Today props/foliage/traffic spawn once per scene
    (or never). Port them to the TerrainSeeder region-lifetime model: keep a
    `dressed_regions` set mirrored to the live 3×3 ring + prefetch band, spawning
    per-region `PropScatterer`/`Foliage` MultiMeshes on main-thread drains (bounded
    ≤2/frame like `MAX_APPLY_PER_TICK` in `terrain_seeder.gd:24`) and freeing them
    when a region leaves the ring — **exactly the `_apply_ring_pass`/
    `_remove_far_regions` cadence** so dressing never pops far and never duplicates on
    re-stream. Deterministic per region seed so re-entering a region is bit-identical
    placement.
  - **LOD for scatter/foliage** (visual budget: MultiMesh already cheap; add
    distance-banded instance culling + reduced instance counts on the prefetch band).
  - **Corridor pre-bake scaling.** With 10× the roads, revisit
    `MAX_CORRIDOR_LOCS=40`/`CORRIDOR_MARGIN=1`: make corridor pre-bake **tier-aware**
    and saturate the worker (a 100 km ring touches ~190 regions — the cap must be a
    budget, not an arbitrary constant; keep `PRIORITY_LIVE` first so the player
    region sync-bake is never starved).
  - **Near-player sync-bake correctness audit** (the AGENTS.md hot rule): re-verify
    `import_images()` region-anchor snapping, the `±1` live-ring trim, and the
    cached-write-on-reentry path all hold at scale — plus the "never pass
    >1-element `get_region_locations()` to a `%s` format arg" rule.
  - Optional stretch (no-ceiling): shader precompile / cold-import path parity for a
    bigger asset surface — measured, not assumed.
- **Why:** `self_audit.md` §3 debt, exactly: "props/foliage/traffic are spawned once
  … bottleneck if the world grows." P2's network is what makes the world *grow*; this
  phase keeps it *streaming*. The core (threaded bakes, Mutex/Semaphore, corridor
  pre-bake, prefetch ring) is FH-comparable (`world_compare.md` gap #9 = Moderate);
  the payload is just thin today.
- **How:** refactor `terrain_seeder` to expose region enter/leave callbacks
  (or a `Dresser` node observing `sync_player_pos`) driving `PropScatterer.
  configure/generate` + `Foliage`, and run `TrafficSpawner.update` within the ring
  (already takes `player_pos`). Keep all worker-thread math pure (no Terrain3D off
  main thread — dressing generation is main-thread but bounded/frame).
- **Effort:** L (~3–4 wks).
- **Test-gate:** extend `tests/suites/test_terrain_seeder_streaming.gd` with a
  dressing twin: assert dressing appears with the ring, is freed on eviction, NEVER
  duplicates on re-entry, and stays deterministically placed per region seed; assert
  the corridor pre-bake budget at scale (km → region-locs math is a pure testable
  function); keep orphan count ≤ baseline and the headless watchdog enforced.
- **Architecture note:** the one place we touch the streaming hot path deliberately
  (ROADMAP 3.4's debt paydown is absorbed here). If dressing-at-scale reveals a
  MultiMesh instance ceiling in the current renderer path, the no-ceiling answer is
  GPU-instancing changes or a deferred MultiMesh pool — state it with profiler
  evidence, don't pre-trim.

---

## 3. BENCHMARK TARGETS — "define done"

Every phase's exit is a measured row. Baseline is the codebase today
(`world_compare.md` §10 — 3 roads / 6.4 km / 666 points).

| Metric | Today | Done when (exit) |
|---|---|---|
| Road kilometres (driveable) | 6.4 km | **≥ 60 km** classified, deterministic, at P2 exit (stretch 100–150 km) |
| Road tiers live | 1 (asphalt only) | **5**: HIGHWAY / ARTERIAL / TOUGE / COASTAL / DIRT — distinct width, surface, banking (P0) |
| Network topology | 3 chains, 1 pseudo-junction | **Graph with ≥ 25 real junction/link nodes**, symmetric adjacency, routing queries green (P0→P2) |
| Visual biomes rendered | 1 (single green) | **≥ 6** visible through baked TYPE_COLOR (plains/farmland/coast/lowland/highland/alpine) (P1) |
| Elevation relief / bands | ~65 m, `-5..60` clamp, 5 numeric bands | **≥ 1,500 m peaks**, sea-level water band, ~10-band elevation monotonic table, no clamp ceiling (P1) |
| Corridor authoring | 3 hand-coded chains | Full blueprint → spline → conform pipeline; big-arc perimeter, switchback touge, coastal huggers, dirt cut-throughs; deterministic per master seed (P2) |
| Off-road surface dependence | none (grip = weather only) | **6 surfaces** (asphalt/gravel/dirt/mud/grass/snow) driven into lateral+longitudinal TireModel; tire squeal/traction differences measurable in `test_surface_grip` (P3) |
| Regional climate | 1 global enum, clock frozen at 12:00 | Clock advances (≥ 60-min day); **≥ 5 region bands**; alpine year-round snow; seasonal pass lock toggles route gate (P4) |
| Discovery loop | Map fully revealed, no travel | Fog-of-war grey→white roads, **fast travel to any discovered road point**, GPS route line on minimap + world map, discovery persisted per save (P5) |
| Living-world density | 0 dressing nodes in open world, 5 static dots | PropScatterer + Foliage + TrafficSpawner live in `open_world_root.tscn`; **≥ 6 event markers** placed by car culture (touge/drag/drift/street/marathon/time-attack) (P6) |
| Dressing streaming | spawn-once | Streamed per region with the ring — no duplication on re-entry, ≤2 applies/frame, orphan count ≤ baseline (P7) |
| Test discipline | 144 GDUnit green | **Every new suite green, baseline 144 stays green, count grows monotonically**; headless per-AGENTS.md order on every phase gate |

---

## 4. DEPENDENCY GRAPH — how this weaves into ROADMAP.md

**Proposal: a new top-level pillar "Phase W — World & Roads" (W0–W7 ≡ P0–P7),**
slotted between ROADMAP Phase 1 (Feel & Loop) and Phase 2 (Content Depth &
Progression), because it *is* the map half of the "living map" north star and
reorders a chunk of existing items.

| This plan | Maps to ROADMAP item | Relationship |
|---|---|---|
| W0 (road graph) | **1.2 GPS route line** | 1.2's routing needs a real graph → W0 is 1.2's Prerequisite; 1.2 lands as part of W5 |
| W0 (tiers/banking) | **2.5 second biome zone** | Second biome becomes "parameterize W0 tier + W1 bands", not new machinery |
| W1 (elevation/color) | **2.5 second biome zone**, **2.6 landmarks** | 2.5's biome table is the P1 band table; landmarks need a visual-biome world to sit in |
| W2 (corridor seeding) | **2.6 landmarks** + world-scale proof | The authored-landmark sets sit on seeded corridors; 2.6's "scenery stops at null props" is fixed by W2 density + W6 dressing |
| W3 (surface grip) | **1.1 surface-type handling depth** | Same hot spot (`vehicle_physics.gd` grip_mult) — merge: 1.1 takes the registry/table, W3 adds per-tier + off-road consequences |
| W4 (regional climate/time) | **1.5 weather VFX + night** | W4 owns the *signal* (clock, region sampling); 1.5 owns the *visuals* (rain/snow VFX, wet shader, headlights). Wire 1.5 to W4's events |
| W5 (discovery/travel/route) | **1.2 GPS route**, **2.3 collectibles/discovery**, **1.8 rewind/reset** | Rewind is 1.8's; fast-travel + fog-of-war extend 2.3's discovery into FH6's full loop |
| W6 (dressing + events) | **1.4 event-type framework**, **2.3/2.6 POIs + landmarks**, **3.5 monthly content** | Event framework (1.4) becomes W6's placement engine; POI/collectibles (2.3) hang off W6's registry growth; W6's event sites are data → 3.5's content packs |
| W7 (streaming evolution) | **3.4 streaming/dressing alignment** | 3.4's debt paydown is *absorbed* by W7 (it is the same work) |

**Sequencing:** W0 → W1 → W2 is the critical chain (graph → terrain → extent); W3,
W4, W5 and W6 are parallelizable off it (different files: `vehicle_physics.gd` vs
`weather_manager.gd`+`world_driver.gd` vs `minimap/world_map/map_roads` vs
`open_world_root.tscn`+`event_registry.gd`). W7 trails W2+W6 (it optimizes content
that exists). ROADMAP Phase 1 items not on this chain (1.3 garage, 1.6 AI, 1.7
audio) are independent — the two tracks can run concurrently.

**Conflict note:** ROADMAP lists 2.5 (second biome) in Phase 2 and 3.4 (streaming)
in Phase 3; this plan pulls both forward because they are the *substrate* for the
map fantasy, not post-v1 polish. Their exit criteria are preserved, their order is
changed — edit ROADMAP accordingly when the plan is adopted.

---

## 5. QUICK WINS / NEXT SPRINT (7 pick-up-able items, test discipline preserved)

Ordered by bang-per-buck; each is S, mostly existing systems, all with a named test gate.

1. **Wire the dressed world — `scenes/world/open_world_root.tscn`.**
   Instantiate `PropScatterer` (one per zone from `default_preset`: festival/lowlands/
   coast/highlands/alpine), `Foliage`, and `TrafficSpawner`; point their
   `ground_height_provider` at `terrain.data.get_height` and `road_network` at the
   `RoadNetwork` node; drive `traffic_spawner.update(player_pos)` from
   `world_driver._physics_process`. Doors: `test_prop_scatterer` /
   `test_traffic_spawner` + open-world suite. *(S — fills the empty world in an afternoon.)*

2. **Surface-grip table + hook (W3 v0).** New pure `scripts/vehicle/surface_registry.gd`
   with `SURFACE_GRIP`; multiply into the existing `vehicle_physics.gd:99`
   weather factor; feed `TireModel` lateral+longitudinal. Gate: `test_surface_grip`.
   *(S)*

3. **Run the clock.** Call `WeatherManager.advance_time(...)` from
   `world_driver._physics_process` at a `1.0/2400`-h-per-frame rate; keep
   `set_time_of_day` gated to real minutes so tests stay deterministic. Gate:
   extend `test_weather_sun` (assert `time_of_day_changed` pulses, sun transform
   sweeps the arc). *(S)*

4. **Color-map bake (W1 v0).** Add `bake_region_color()` to `terrain_baker.gd`
   sharing `_biome_base` weights; write `Terrain3DRegion.TYPE_COLOR` in
   `terrain_seeder._write_region` (precedent: `mountain_pass.gd:105-116`). Gate:
   `test_terrain_baker` + a new deterministic RGBA-hash test. *(M)*

5. **Road-tier metadata skeleton (W0 v0).** Extend `road_network.add_road` with
   optional `tier`/`surface`/`banking` keys while keeping `get_roads()`
   byte-compatible (minimap/map untouched); migrate `world_driver._bootstrap_roads`
   to declare the hub as HIGHWAY-tier for a first visual.width/banking read. Gate:
   new `test_road_graph` (adjacency/tier round-trip) + existing world-map suite.
   *(S)*

6. **GPS route line v0 (W5 v0).** Pure `route_path(from, to)` over today's 3-chain
   `get_roads()` via `get_nearest_road_pos` + Dijkstra (upgraded to the P0 graph
   later); draw on `minimap.gd` with `MapRoads.world_to_local_points` + `clip_circle`.
   Gate: `test_map_route` headless (route + fit/clip math, no frames). *(M — the
   first visible "map is alive" win.)*

7. **One placed drift zone + one placed drag marker (W6 v0).** Data-first: a
   `scripts/world/event_registry.gd` that finds the longest-straight highway run and
   a hairpin-touge segment deterministically, registers them as `POIRegistry` entries
   so `world_map.gd` dots appear; hook the drift zone's clear-line into
   `drift_scorer.gd`. Gate: `test_event_placement` (tier-valid placement) + reuse
   `test_race_loop` sync-free discipline. *(S–M)*

Suggested single-sprint order: **1 → 2 → 3** (the "world feels alive" bundle),
then **5 → 6** (map/graph bring-up), then **4** (the visual biome win) and **7**
(proof of event-by-culture) to close out.

---

*Plan ends. When adopted, fold W0–W7 into ROADMAP.md as an explicit "Phase W —
World & Roads" pillar and renumber the absorbed items (1.2, 1.4, 1.5, 2.3, 2.5,
2.6, 3.4) as deltas on top of it.*