# Plan: Seeding UltraDrive's Open World (Terrain3D Ground + Road-Conforming Terrain)

Research + planning document. No engine code is changed by this file. Godot 4.7.2,
project root `D:\AI Projects\UltraDrive`. Ground solution: **Terrain3D** (GDExtension,
`addons/terrain_3d`, v1.0.2, min Godot 4.4).

---

## 1. Research findings summary

### Forza Horizon 6 — "Horizon Japan"
- Official reveal states the world runs "from the iconic downtown streets of Tokyo City
  all the way to the snowy Japanese Alps" and is Playground's "most dense and vertical
  map yet" — *Forza Horizon 6 – Full Map Reveal*, forza.net:
  https://forza.net/news/forza-horizon-6-full-map-reveal
- Unofficial size estimates: ~18 miles across (largest in series vs ~14 miles for FH5),
  ~10 regions, ~673 roads, ~74 discoverable areas — *Map | FH6 Wiki*, game.wiki:
  https://game.wiki/forza-horizon-6/map . Area estimates range ~120-246 km² (non-official),
  e.g. *FH6 Map Size, Density, and Biomes*, game-meta.com:
  https://game-meta.com/forza-horizon-6-map-size-density-and-biomes-japan-open-world-breakdown/
- Six biomes, each with distinct vegetation/elevation and separate seasonal weather:
  Tokyo City (largest urban space in the series), Plains, Coast, Lowlands, Highlands,
  and Alpine (permanent snow, ski resort modeled on the Tateyama Kurobe route) —
  *Locations | FH6 Wiki*, game.wiki: https://game.wiki/forza-horizon-6/locations
- Tokyo is reported ~5x larger than Guanajuato in FH5 and ~2.5x Edinburgh in FH4 —
  *FH6's Map Size: How It Compares*, Game Rant:
  https://gamerant.com/forza-horizon-6-map-size-comparison-big-small-fh4-fh5/
- Design approach: not a 1:1 benchmark of Japan but a "condensed reality" that captures
  the essence of the place; maps are chosen art-first and biome/culture drive gameplay
  ideas — *Forza Horizon 6 Developer_Direct breakdown/interview*, Xbox Wire:
  https://news.xbox.com/en-us/2026/01/22/forza-horizon-6-developer-direct-breakdown-interview/

### Forza Horizon 5 (Mexico) — concrete biomes + sandbox lessons
- FH5 Mexico is ~1.5x FH4's 71 km², community-estimated ~107 km² (DonJoewonSong) —
  *How big is the FH5 map*, Dexerto: https://www.dexerto.com/forza/how-big-is-the-forza-horizon-5-map-mexico-map-size-revealed-1697682/
- 11 advertised biomes (arid hills, canyon, farmland, jungle, living desert, sand desert,
  rocky coast, tropical coast, swamp, Guanajuato city, volcano) — *A closer look at FH5's
  take on Mexico*, The Verge: https://www.theverge.com/22586277/forza-horizon-5-biomes-playground-games-microsoft-xbox
- Field trip / art-first production; the campaign drives players to "festival outposts"
  in each new region as the world-discovery structure — *Secrets behind a Forza Horizon
  world map*, Top Gear: https://www.topgear.com/car-news/gaming/secrets-behind-a-forza-horizon-world-map-playground-games-spills-all

### Judgments applicable to UltraDrive
1. **Road density beats raw area.** "Players do not drive map borders, they drive roads";
   FH6's selling point is 600+ roads / route variety, not empty km² — *FH6 670 Roads
   Explained*, mitchcactus: https://mitchcactus.co/blog/forza-horizon-6/forza-horizon-6-670-roads-explained/
   -> We seed a compact map where every road is a *meaningful* route, and we conform
   the ground to roads so terrain never fights the road surface.
2. **Festival hub anchors the map.** Horizon hubs + regional outposts give the world a
   town square and a progression spine — Top Gear interview above. -> UltraDrive gets one
   "Horizon Festival" hub plaza at the player spawn plus small POI anchors per zone.
3. **Verticality is the differentiator.** FH6 is "dense and vertical"; elevation changes
   and passes are the memorable driving (Mt. Haruna / Bandai-Azuma style touge). ->
   Our mountain-pass circuit (y swings -11..+11) is the signature terrain feature, and
   the heightfield is shaped to celebrate it.

---

## 2. Map vision for UltraDrive

- **Footprint:** 6 km x 6 km live map (world coordinates +X/+Z in `0..6144`), aligned to
  both ground systems so math stays integer:
  - Chunk grid: 24 x 24 chunks of 256 m (matches `ChunkStreamer.chunk_size = 256.0`).
    Streaming window stays 25 chunks / 1.28 km x 1.28 km (`load_radius = 2`).
  - Terrain3D region grid: 6 x 6 regions of 1024 m (Terrain3D default `region_size`);
    one region = exactly a 4x4 block of chunks, so region index =
    `Vector2i(floor(chunk_cx / 4.0), floor(chunk_cz / 4.0))`.
  - Expansion path: because streaming is radius-based and regions are coordinate-keyed,
    growing = baking more regions east/north. No re-architecture needed.
- **Player spawn anchors the festival.** `PlayerSpawn` at `(128, 2.2, 128)` sits in chunk
  `(0,0)` / region `(0,0)`, ~128 m from the SW corner. The "Horizon Festival" hub plaza is
  built around it (region 0,0 = Festival Plains).
- **Biome zones (6, mirroring FH6's compression):**
  | Region range | Zone | Elevation | Character |
  |---|---|---|---|
  | (0,0)-(1,1) | Festival Plains | flat ~2 m | hub plaza, wide plaza roads, farm-green control map |
  | (1,1) center | Rolling Lowlands | 0..+12 m | undulating, forested; safe where tests teleport |
  | east rim (0-5,5) | Coast Apron | 0..+4 m | dry lakebed/caster apron, open sightlines |
  | (2,2)-(3,3) | Forested Highlands | +8..+30 m | **mountain-pass circuit** embedded here |
  | (4,4)-(5,5) NE | Alpine Overlook | +25..+45 m | snow control map, viewpoint POI |
  | loop 5-6 ring | Perimeter freeway | follows zone | one closed ring road around the landmass |
- **Mountain pass location:** the `res://scripts/track/mountain_pass.gd` circuit lives as
  an open-world instance centered near `(3800, ~14, 3200)` in the NE highlands, connected
  to the hub by a "Pass Road" connector through the lowlands. `road_points` are reused
  verbatim as the road-corridor input for terrain conforming (Section 3).
- **Hub concept:** "Horizon Festival" = U-shape plaza of low-poly tents/banners/stage at
  spawn, garage door (GarageUI entry), free-roam start; the plaza is also `POI #0` in the
  new POI registry. No fast-travel in Phase 1 (out of scope).

---

## 3. Terrain3D ground pipeline

### 3.1 Control flow / where the logic lives
Keep `ChunkStreamer` as the chunk *manager*; put terrain generation in a new node so the
two stay decoupled and only share the player position:

- New `scripts/world/terrain_seeder.gd` (`class_name TerrainSeeder extends Node`) - owns
  a `Terrain3D` reference, region lifetime, baking, and road conforming.
- New `scripts/world/terrain_baker.gd` (`class_name TerrainBaker extends RefCounted`) -
  pure heightfield math (no scene tree), so it is directly unit-testable headless.
- Edit `scripts/world/world_driver.gd::_push_player_position()` so it feeds BOTH systems
  from the one player read:
  `_streamer.set_player_position(player_pos)` and `_terrain_seeder.sync_player_pos(player_pos)`.
- Edit `scripts/world/chunk_streamer.gd`: add `@export var terrain: Terrain3D`. When set,
  `_create_flat_chunk()` returns a lightweight empty `Node3D` group-holder (no PlaneMesh,
  no StaticBody3D) so `get_loaded_chunk_count()` still reports >=25 (keeps
  `tests/test_open_world.gd` green) while Terrain3D owns all ground + collision.
- Edit `scenes/world/open_world_root.tscn`: add a `Terrain3D` node
  (`region_size = 1024`, `height_range = Vector2(-10, 60)`), and a `TerrainSeeder` child
  that wires streamer <-> terrain; leave `ChunkStreamer` and `WorldDriver` structure intact.

### 3.2 Heightfield storage & runtime baking
Terrain3D stores height per region in an `Image` (`Terrain3DRegion.TYPE_HEIGHT == 0`).
Documented runtime-safe API (no hand-poking of the 16-bit encoding):

- Region lifecycle: `terrain.get_data().has_regionp(global_pos)`,
  `add_region_blankp(global_pos, update)`, `get_regionp(global_pos)`,
  `remove_regionp(global_pos)`.
- Read/write heights: `terrain.get_data().get_height(global_pos)` /
  `set_height(global_pos, y)` (absolute world Y). After edits:
  - `region.update_height(y)` to grow the AABB height range,
  - `region.set_edited(true)`, `terrain.get_data().update_maps(Terrain3DRegion.TYPE_HEIGHT, false)`,
    `region.set_edited(false)` (documented "only update changed regions" pattern).
- Bake resolution: read `region.get_map(Terrain3DRegion.TYPE_HEIGHT).get_width()` once and
  derive `step = region_size / image_width`; walk texel world positions at `step` (then
  coarsen to `step*2` if the first bake takes >1 frame).
- Height source (Section 3.3) -> final Image; `set_map(TYPE_HEIGHT, image)` is
  an alternative for bulk writes once the encoding is tuned, but Phase 3 ships on
  `set_height` per texel (a 1024 m region at 4 m steps only needs ~65k writes).

Referenced API docs: *Terrain3DRegion* https://terrain3d.readthedocs.io/en/latest/api/class_terrain3dregion.html ,
*Terrain3DData* https://terrain3d.readthedocs.io/en/latest/api/class_terrain3ddata.html

### 3.3 Terrain baking passes (in `terrain_baker.gd`, ordered)
1. **Natural base heightfield** per region: deterministic `FastNoiseLite` (fBm, low
   frequency ~0.003) + a radial "alpine dome" falloff toward the NE corner, scaled by biome
   elevation table (Section 2). Seeded from `(region.x, region.z)` so baking is reproducible.
2. **Road-corridor conforming:** for every road (Section 5) upsample centerline points to
   ~1.5-2 m spacing (mountain pass `_generate_road_points()` yields only 36 points for a
   ~78 m-radius loop); for each texel, compute distance to the nearest centerline sample:
   - inside `road_width * 0.5 + 0.3` -> target = road y (sample height, `LERP` along spline)
     minus ~0.15 m so the asphalt ribbon sits a few cm proud of the dirt;
   - in the falloff band `road ~+ 4 .. +40 m` -> blend target with natural height using a
     smoothstep falloff (cosine/`smoothstep`, not linear, to avoid terraces);
   - beyond 40 m -> natural height untouched.
   Corners: use the same right-vector math as `TrackBuilder._build_mesh` so centerline
   distance is perpendicular to the road heading, not Euclidean to the nearest node.
3. **Smoothing:** one 3x3 separable blur over the whole region height buffer (breaks
   texel aliasing created by per-sample writes), then clamp to
   `clampf(y, -5.0, 55.0)`.
4. **Spawn plateau guard:** force a 40 m disc around `(128,128)` to y ~2.2 (baked, not
   runtime) so `test_open_world_car_lands_on_ground` (player y in `(-5, 5)`) is immune to
   noise.

### 3.4 Caching & streaming coordination
- Terrain3D has **no built-in region streaming** ("Region Streaming is in progress" -
  *Terrain3D Technical Tips* https://terrain3d.readthedocs.io/en/latest/docs/tips_technical.html ),
  so `TerrainSeeder` implements it: `sync_player_pos(pos)` loads the region ring
  `Vector2i(floor(pos/1024))` +/NE 1 (radius `(load_radius*chunk_size)/region_size + 1`
  -> 3x3 = 9 regions live around the player) and calls `add_region_blankp` +
  `terrain_baker.bake_region(...)` for any region not already baked in
  `_baked: Dictionary[Vector2i, Image]` (in-memory cache; regions removed from the scene
  via `remove_regionp` keep their cached image so re-entry is instant).
- Optional persistence (Phase 7): save a baked region's `Image` to
  `user://terrain_cache/region_%d_%d.exr` on first bake, load on entry. Never write into
  `res://` at runtime.
- **No double-ground:** when `ChunkStreamer.terrain` is set, flat chunks become empty
  anchors; otherwise `_create_flat_chunk()` behavior is unchanged (backwards compatible
  for standalone track scenes).

---

## 4. Seeding phases (ordered; game stays playable, suite stays green)

All "acceptance" lines below are verified by the AGENTS.md headless recipe (see Section 6).

### Phase 0 - Baseline & this plan (no code)
- Input: this document. Output: nothing changed.
- Acceptance: `git status --short` shows no `*.uid` noise; suite reports
  `33 test cases | 0 errors | 0 failures`.

### Phase 1 - Terrain3D rig behind the existing streamer
- Files: new `scripts/world/terrain_seeder.gd`, new `scripts/world/terrain_baker.gd` (base
  "flat + spawn plateau" only); edit `scripts/world/chunk_streamer.gd`
  (`@export var terrain`, empty group-chunk when set); edit
  `scripts/world/world_driver.gd` (dual push); edit
  `scenes/world/open_world_root.tscn` (Terrain3D + TerrainSeeder nodes).
- Input: `open_world_root.tscn` as-is; `tests/test_open_world.gd`.
- Acceptance: player at spawn rests on terrain (y in `(-5,5)` after 96 frames);
  `ChunkStreamer.get_loaded_chunk_count() >= 25` after spawn AND after
  `set_player_position(Vector3(1500,5,1500))`; suite green at 33/33.

### Phase 2 - Deterministic heightfield (noise + alpine dome)
- Files: extend `terrain_baker.gd` (pass 1: `FastNoiseLite` base + biome elevation table +
  NE alpine dome); `terrain_seeder.gd` bake-on-region-entry.
- Input: region coords `Vector2i`; seed constants; elevation table from Section 2.
- Acceptance: same two bakes at the same region produce byte-identical heights
  (determinism test below); spawn plateau still ~2.2; suite green. Frame spike of a
  first-time region bake < ~1 frame budget (coarsen `step` if not).

### Phase 3 - Road-corridor conforming
- Files: extend `terrain_baker.gd` (pass 2+3: upsample road_points, falloff blend,
  3x3 blur, clamp); `terrain_seeder.gd` accepts a `roads: Array[Array[Vector3]]` input.
- Input: `mountain_pass.gd::road_points`; `RoadNetwork._roads`; `TrackBuilder` right-vector
  math reference.
- Acceptance (new `tests/test_terrain_baker.gd`): `data.get_height()` at each road
  centerline sample is within 0.5 m of the road point y around the whole loop;
  `get_height()` at +120 m lateral is back at natural height; suite green (33 + new tests).

### Phase 4 - Embed the Mountain Pass into the open world
- Files: new `scenes/world/regions/mountain_pass_zone.tscn` (instance
  `mountain_pass.tscn` with an export flag to skip its own `GrassGround`, placed at
  `(3800, ~14, 3200)`); `road_network.gd` add the hub<->pass "Pass Road" connector
  before terrain bake; `scenes/world/open_world_root.tscn` gain the zone node.
- Input: `track_registry.gd` ("mountain_pass"); `TrackBuilder.road_width=11` (road corridor
  used by Phase 3 conforming).
- Acceptance: standalone `mountain_pass.tscn` untouched (its own track tests still pass);
  in open world the loop is drivable end-to-end with no buried/as-of-ground road segments
  (walk all `road_points`, assert `get_height(...) <= point.y`); suite green.

### Phase 5 - Biome materials, foliage & prop scattering
- Files: `terrain_baker.gd` control-map pass (per-biome base texture IDs + `is_on_road`
  painted asphalt/dirt blend, rock/snow by elevation); new `scripts/world/prop_scatterer.gd`
  (MultiMesh guardrail/tent/power-pole/rock placements, exclusion via
  `RoadNetwork.is_on_road`); instance `scripts/world/foliage.gd` per zone with tuned
  `radius` / `inner_clear_radius` / `seed`.
- Input: `foliage.gd` params; `RoadNetwork.is_on_road(pos, threshold)`.
- Acceptance: no foliage/prop instance intersects a road centerline by more than
  `is_on_road` tolerant; counts bounded (grass+m trees per region below a fixed budget,
  assert in a new perf test); suite green.

### Phase 6 - Traffic, POI registry & festival hub
- Files: new `scripts/world/poi_registry.gd` (static dict: id -> name, stage, position;
  entries incl. Horizon Festival plaza at spawn and Alpine Overlook); edit
  `traffic_spawner.gd::_spawn_vehicle` to retry candidates until
  `RoadNetwork.is_on_road(candidate, 10.0)` (max 8 attempts, else skip - traffic only on
  roads); hub prop set around spawn in `open_world_root.tscn`.
- Input: `traffic_spawner.gd` (`max_traffic=15`, `spawn_radius=300`); `minimap.gd` untouched.
- Acceptance: with a road map, spawned traffic is always on/near a road (loop 200 updates,
  assert `is_on_road` for every live vehicle); POI registry returns exactly the seeded set;
  suite green.

### Phase 7 - Persistence, tuning & polish (optional)
- Files: `terrain_baker.gd` add `Save/load` to `user://terrain_cache`; config for world
  size (regions per axis) so the map can grow without code changes.
- Acceptance: entering a region a second time loads from cache (no rebake print);
  suite green. Playtest loop: spawn plaza -> Pass Road -> mountain pass loop -> Alpine
  Overlook POI -> freeway ring -> hub.

---

## 5. Seeded content per region (references existing systems)

| Zone | Roads (RoadNetwork.add_road) | Ground/biome control | Foliage (Foliage params) | Props (prop_scatterer) | Traffic/POI |
|---|---|---|---|---|---|
| Festival Plains (0,0)-(1,1) | Plaza ring + N/E exit roads, width 12 | grass base, plaza smooth | grass 900 / trees 10, inner 90 | festival tents, banners, stage | POI #0 Festival Hub; traffic on plaza exits |
| Rolling Lowlands (1,1) | "Pass Road" S-N connector, width 10 | grass + dirt blend | grass 700 / trees 40, seed per-region | power poles, rocks | traffic onroads; POI #1 Lowland View |
| Coast Apron (east rim) | Perimeter freeway east leg, width 14 | sand/rock blend | grass 300 / trees 0 | buoys, boulders | POI #2 Dry Lake |
| Forested Highlands (2,2)-(3,3) | mountain-pass loop (embedded) + hairpin spurs, width 11 | forest floor, rock near steep | grass 500 / trees 90, inner 100 | guardrails on falloff | POI #3 Pass Entry; drift traffic |
| Alpine Overlook (4,4)-(5,5) | freeway north leg, width 14 | snow control + rock | grass 0 / trees 8 stunted | viewing deck, snow walls | POI #4 Alpine Overlook |
| Perimeter freeway ring | full loop around map edge, width 14 | follows zone under it | none inside roadway | guardrails | ring traffic |

Reuse: roads go through `RoadNetwork.add_road(points, width)`; terrain conforming reads
the same point arrays (single source of truth). Foliage stays *visual-only* (no collision,
per `foliage.gd`). `traffic_spawner.gd` gains road gating only.

---

## 6. Testing & verification strategy

- Use the project's gdUnit4 suite: `res://tests` (view `tests/test_open_world.gd`, keep it
  green) via the exact AGENTS.md recipe - FIRST a normal `--headless --import .` probe
  (expect ZERO `SCRIPT ERROR`/`Parse Error`), THEN
  `--ignoreHeadlessMode -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests`.
  Do NOT start a second Godot process while one pipeline is running; run the two steps
  sequentially, never concurrently with other work.
- New tests (following `tests/test_open_world.gd` style, `pre_check`, `is_equal` asserts):
  - `tests/test_terrain_baker.gd`: determinism (bake twice -> compare buffers); road
    conforming (<0.5 m error on centerline, natural beyond 120 m); spawn plateau guard.
  - `tests/test_terrain_seeder.gd`: region added around spawn and around `(1500,5,1500)`;
    `Terrain3DData.has_regionp` true; removed regions free their scene entry but keep the
    in-memory cache.
  - `tests/test_traffic_spawner.gd`: after 200 `update()` calls every live
    `VehiclePhysics` satisfies `RoadNetwork.is_on_road`.
  - Keep expected summary line updated in AGENTS.md as the count grows past 33; the
    baseline 33 must never regress during the phases.

---

## 7. Out of scope / bias for simplicity

- No runtime water/ocean, no seasons, no weather system, no day/night cycle changes.
- No Terrain3D *instancing* (its foliage/grass system) - reuse `foliage.gd` MultiMeshes.
- No multi-threaded baking initially; bake synchronously on region entry, coarsen texel
  step if a bake exceeds one frame. Revisit only if measured.
- No saving into `res://`; persistence is memory-cache (+ optional `user://`) only.
- No fast travel, no EventLab/build mode, no AI route graph, no off-road physics tuning.
- Keep `road_width`/`TrackBuilder` conventions unchanged; do not touch HUD, pause menu,
  cameras, garage, or minimap. The standalone `mountain_pass.tscn`/`test_track.tscn` must
  remain byte-for-byte behavior-compatible (their own tests stay green).
- FH6-scale density (600+ roads, 5x city) is consciously NOT the target; UltraDrive iterates
  a few-km² world with ~6-10 meaningful roads first, then expands regionally.