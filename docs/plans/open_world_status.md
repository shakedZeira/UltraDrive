# UltraDrive open world - current status (verified against code, 2026-10-22)

> **Update 2026-10-22 (later, open-world stage 1):** ground textures and region-streamed
> dressing are now live. See section 6 for what changed, measurements and what is still
> unverified; sections 0-5 are corrected inline where they described the old state.
>
> **Update 2026-10-23 (open-world stage 2, item 1):** the far-terrain vista is built; the
> 384 m cliff is gone. See section 7, and two pre-existing world bugs it exposed (3d, 3e).
>
> **Update 2026-10-23 (bug 3d fixed):** the live ring no longer asks Terrain3D for regions past
> +-4096 m (thousands of "out of bounds" errors per second gone); the vista carries collision there.
> See section 8.
>
> **Update 2026-10-24 (FH6-look pass):** biome vegetation (broadleaf woods, bushes, grass clumps, flowers, rocks),
> roadside furniture, landmarks, atmosphere (grade, lighter haze, clouds, sea, time-of-day sun) and softer terrain
> tones. See section 12.
>
> **Update 2026-10-23 (open-world stage 2, item 2):** road meshes and collision stream per 256 m cell
> around the car, with a far-LOD mesh for the horizon; the road topology build at load went from 21 s to
> 36 ms. See section 10.

Scope: what the free-roam world actually is today, measured or known sizes, what is
done / partial / missing, perf budget and known bugs. Companion docs:
`open_world_fh6_plan.md` (gap analysis + roadmap) and `open_world_traffic_plan.md`
(ambient AI traffic architecture).

Method: read the listed docs, then verified every claim against `scripts/world/*`,
`scenes/world/open_world_root.tscn`, `project.godot`, the tests that pin behaviour,
and today's captures (`openworld_after_*` in the 2026-10-22 track-capture scratchpad,
opened and inspected directly). `graphify query` was run first, but the graph only
indexes docs (GDScript symbols are not nodes), so code facts below come from raw reads.
Godot was NOT run for this document, so numbers marked (derived) are computed from
constants, not measured in-game.

## 0. Doc drift to be aware of (do not trust these claims)

| Source | Claim | Reality in code |
|---|---|---|
| `docs/research/world_compare.md` (2026-09-16) | 3 roads / 6.4 km, traffic/props not wired | Stale: 19 corridors, >= 60 km (test-pinned); one static Foliage + 5 PropScatterers + TrafficSpawner ARE in the scene |
| `docs/plan_open_world_seeding.md` | Terrain3D regions 1024 m, 6x6 map | `TerrainSeeder.REGION_SIZE := 256`, live ring 3x3 = 768 m (`terrain_seeder.gd:21-22`); 1024 appears only in a stale const in `regional_climate.gd:75` |
| `docs/ROADMAP.md` W.6 / W.7 "region-streamed dressing wired into open_world_root.tscn" | Shipped | Was NOT wired until 2026-10-22 (only a test pinning it absent). FIXED: `RegionDresser` is now in the scene and ROADMAP W.6/W.7 say so with the real date; the pinned test became `test_open_world_dressing_budget` |
| `docs/plans/terrain_vista_plan.md` | Static far-terrain vista | Built 2026-10-23 (section 7; as-built notes in the plan's section 9). Before that only a non-parsing `terrain_vista_baker.gd` existed |
| `docs/plans/open_world_optimization_plan.md` | Traffic = 15 cars | Scene now has `max_traffic = 8` (`open_world_root.tscn:196`); the spawner script default is also 8 |
| `docs/HANDOFF_2026-10-22_session.md` | Open-world capture hung in endless `TrafficSpawner._spawn_vehicle` null loop | Log shows 2,841 errors that all start with `Compile Error: Identifier not found: RaceManager` in the capture tool; the later `log_openworld_after.txt` run is clean (0 errors). Likely a harness compile problem, not a traffic regression (not proven) |

## 1. What the world is

### 1.1 Scene composition (`scenes/world/open_world_root.tscn`)

Root `OpenWorldRoot` (`world_driver.gd`) with: `Terrain3D` (collision FULL_GAME, no
shadows; since 2026-10-22 the seeder gives it 8 CC0 texture layers, `apply_ground_textures`),
`TerrainSeeder`, `RegionDresser` (since 2026-10-22), `ChunkStreamer`
(`terrain` set => flat chunks are empty anchors; effectively a placeholder),
`RoadNetwork`, `MountainPassZone` (instanced at 3800, 14, 3200), `PlayerCar` at spawn
(128, 2.2, 128), chase/orbit/hood/cockpit cameras, Sun (1 split, 60 m shadow
distance), `WorldEnvironment` (PhysicalSky, aerial-perspective fog 0.0012, SDFGI/SSAO/SSR/
glow off in the scene; the quality ladder switches them), 1 `Foliage`, 5
`PropScatterer` (`PropsFestival/Lowlands/Coast/Highlands/Alpine`), 1 `TrafficSpawner`,
`LivingWorld`, `EventSession`, `CollectibleField`, `SpeedTrapVisuals/Crossing`,
`RainSystem`, `WeatherAudio`, HUD/pause/speed-trap HUD.
`world_driver.gd` adds static reflection probes (hub, pass), street lights, discovery
(fog-of-war bitset), fast travel and the weather FX layer.

### 1.2 Size and extents

| Quantity | Value | Basis |
|---|---|---|
| Highway ring | ellipse centre (4400, 2250), semi-axes 4600 x 3550 m, 192 pts | `corridor_planner.gd:409-411, 552-566` |
| Ring circumference | ~25.9 km (derived, Ramanujan) | |
| Area inside ring | ~51 km2 (derived, pi*a*b) | |
| Drivable extents (events) | x -200..9702, z -2944..8605 (~9.9 x 11.5 km bounding box, ~114 km2 box but mostly empty) | `terrain_vista_plan.md` section 1; sea near (8200,-3400) |
| Road corridors | 19 named `RoadDef`s, 5 tiers | `corridor_planner.gd:ROAD_NAMES` |
| Total road length | >= 60 km, asserted by `test_corridor_seeding.gd:105`; exact km NOT measured here | `CorridorPlanner.KM_TARGET = 60.0` |
| POIs | 5 hand-placed landmarks + event markers (touge duel, drag strip, drift zone, night street loop, marathon highway, time-attack per anchor, outbreak, convoy) + 28 collectibles (12 bonus boards, 8 speed traps, 8 photo spots) | `poi_registry.gd`, `event_registry.gd:27-37`, `collectibles.gd:75-79` |
| Hand-authored content footprint | hub (128,128), pass zone (3800,3200), 4 other prop anchors; everything else is generated road + noise terrain | scene |
| Float precision | Origin is at the SW corner, extents reach ~9.7 km +x and ~8.6 km +z. Godot docs recommend single precision only up to ~4096-8192 m for third-person games | https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html |

Reading: the nominal playable box is already FH5-order (~100 km2) but only ~51 km2 is
inside the ring and almost none of it has content. The "6 km x 6 km" footprint in
`plan_open_world_seeding.md` and `poi_registry.gd:5` is obsolete.

### 1.3 Terrain (Terrain3D 1.0.2 + custom bake)

- `terrain_baker.gd` (905 lines, pure RefCounted, deterministic): seeded fBm (3 octaves, freq 0.003,
  per-256-m-cell seed `1337 + x*131 + y*977`), blended biome-base table (spawn 2 m, rolling 18,
  highland 35, farmland 6, coast 2.5, lowland 90, highland plateau 260, sea -6), a legacy
  alpine dome plus a 3-dome family reaching ~1100 m, clamp -8..2000 m, spawn plateau (r 40, 2.2 m),
  road-corridor carve (width 11, topping 0.15, blend 40 m), 3x3 blur.
  6 elevation bands (sea, plains, rolling, lowland, highland, alpine) with a baked RGBA colour map.
- `terrain_seeder.gd` (861 lines): live ring 3x3 of 256 m regions (768 m across), prefetch ring +-2 baked on a
  worker `Thread`, <= 2 applies/frame, <= 1 live-ring blank add/frame, corridor pre-bake budget
  (up to 190 region-locs, tier-prioritised), baked-image cache, `region_entered/left` signals.
  Player's own region is sync-baked (~3.3 s cold start). Streaming/hitch tests exist.
- **What it looked like before 2026-10-22 stage 1** (captures `openworld_after_0_eye / 1_high / 2_high`):
  the Terrain3D **checkerboard**. Cause confirmed: with no `Terrain3DAssets` the addon shader falls back
  to its checker (the node's `show_checkered = false` alone does not remove it).
- **Now** (section 6): textured, biome-driven ground from a per-region control map.
- Horizon: since 2026-10-23 a static vista (`TerrainVista`, 3x3 x 8192 m at 8 m, section 7) carries
  the same field to x/z [-8192, 16384); the live ring's flat y = 0 background is switched off.

### 1.4 Roads

- `RoadDef` (id, tier HIGHWAY/ARTERIAL/TOUGE/COASTAL/DIRT, width, closed, surface
  asphalt/concrete/gravel/snow + per-segment profile, banking / bank_angles, rails with per-side masks).
  `lane_count_for(width)` = 1 lane below 15 m, 2 at >= 15 m, 4 at >= 24 m (a visual lane-divider count;
  it is NOT a travel-lane model).
- `RoadNetwork`: topology with junctions (link threshold 15 m), adjacency, `route()`, nearest-road
  spatial index (32 m cells), seasonal tier closure (`set_closed_tiers`), `is_on_road`.
  Roads are flat-strip meshes with trimesh collision (`TrackBuilder`), edge lines and dashed dividers.
- ~~All roads are instantiated at load~~ Since 2026-10-23 (section 10) the open world streams road geometry:
  `RoadNetwork.stream_geometry` (set in `open_world_root.tscn` only) makes `add_road_def` register the def and
  `RoadChunkMesher` build 256 m cells around the car (radius 2, freed past 3) plus one far-LOD mesh of the whole
  network. The circuits (Le Mans, Barcelona RX, Northern Isle) keep one `TrackBuilder` per road. (Old perf
  attribution `e8fbf15`: roads were ~2.8 ms and 83% of attributed prims in the probe scene.)
- Missing: intersections as geometry (roads just overlap at junction points), rural/residential
  tier, town street grids, lane-accurate two-way model, road signs/lights, tunnels, bridges, stacked roads.
- Visual: road reads OK (captures show asphalt, red/white edge lines, dashes), but flat and untextured.

### 1.5 Biomes, dressing, density

- Biome *height* diversity is real (6 bands, sea, alpine); biome *look* is not: no per-biome
  ground textures, grass or tree sets (one fir-style tree set, 3 variants: `assets/trees/tree_a/b/c.glb`,
  one rock `rock_a.glb`).
- `Foliage`: ONE node at the hub (700 grass + 40 trees, annulus around (128,128)). The pass zone
  sets `build_foliage = false`. Everywhere else in ~51 km2: zero trees.
- `PropScatterer`: 5 static nodes with 14-28 props each (tents, grandstands, pit buildings, barriers,
  power poles, rocks, guardrails) around fixed anchors. Buildings: 2 pit-style GLBs only.
- `RegionDresser` (per-region Props + Foliage, ring/prefetch bands, deterministic hash seeds, bounded
  per-frame work, LOD by density) is instantiated in the scene since 2026-10-22 (section 6): trees,
  boulders and power poles now fill every 256 m region around the player.
- No towns, no houses, no billboards, no signs, no street lights except 5 omni lights (one per Props node).
- Collectibles/events are real systems (claim radius, rewards, save), but few (28 collectibles).

### 1.6 Lighting, weather, time

- Shipped and tested: 40-minute day (`DAY_LENGTH_SECONDS = 2400`, `day_night_driver.gd` autoload), sun arc,
  night headlights/street lights, 6 weather states with grip table, rain system, wet overlay, windshield FX,
  5 regional climate profiles + 4 seasons + alpine snowline/pass closure (`regional_climate.gd`),
  per-surface grip. Sky = PhysicalSky; fog on; 1 sun shadow split (60 m) on every preset.
- Gaps: no volumetric clouds / cloud shadows, no aerial haze tuning by biome, flat default-looking ambient,
  no puddles/wet road reflections beyond a screen overlay, no seasonal foliage colour.

### 1.7 Map, discovery, events

Done: pause map + minimap over `MapRoads`, road names, grey->white reveal (`world_discovery.gd`, monotonic
bitset, movement-gated), GPS route line + route follow, click fast travel on revealed roads, event placement by
car culture, collectible dots, speed-trap gantries + HUD. Partial: braking-line assist, route HUD deltas.

### 1.8 Traffic (summary; full detail in `open_world_traffic_plan.md`)

`TrafficSpawner` (179 lines) + `TrafficDriver` (259 lines), driven from `LivingWorld._physics_process`.
- Cap 8 cars (scene), spawn on a random road point within +-300 m square of the player (8 tries), despawn
  beyond 400 m, one car every update when under cap.
- Each car is a full `VehiclePhysics` RigidBody (4 raycast wheels + Pacejka) built from `player_car.tscn`
  with `PlayerCarController` stripped => **every traffic car is the starter car** (config `starter_car.tres`). No variety.
- Driver: aims 18 m ahead on the road *centreline* of the nearest chain (`nearest_road_id` at spawn time), cruise
  ~41-69 km/h, corner slowdown, slows/stops for the player only when the player is within 10 m ahead, stuck rescue
  teleports to a random point on its chain. Open chains shuttle back and forth; no junction turns; no lane offset
  (oncoming cars share the centreline); no car-following between traffic cars; no collision response design.
- LOD: beyond 140 m cars are frozen and their `_physics_process` disabled (shelved), which is what made the
  perf gate pass. No pooling (instantiate/`queue_free` per car). Headlights follow night flag. Engine audio is
  distance culled.
- Tests: `tests/test_traffic_spawner.gd`, `tests/suites/test_traffic_driving.gd`, `test_open_world_hud.gd`.

## 2. Perf budget and measurements (GTX 970, 1080p, Forward+, Jolt, 60 Hz physics)

| Source | Result |
|---|---|
| `open_world_optimization_plan.md` (closed at `d8610ef`, perf_probe) | Low ~93 FPS (10.5 ms), Medium ~64.6 (15.5 ms), High ~56.5 (17.7 ms); 617k prims, 268 draws; process 12-14 ms, physics 12-13 ms/tick |
| What moved it | physics 120 -> 60 Hz (+110%), shadow passes (-37% prims), traffic LOD, HUD/minimap cut |
| Today's capture log (`PERF track=openworld`, preset 1 = Medium, near the hub) | eye view 12.6-14.7 ms avg (p95 13.6-15.6), 295-544k prims, 174-237 draws; elevated view 19.6-20.5 ms |
| Traffic cost | 15 full-physics cars were 42% of per-tick physics; shelving far cars cut physics 22.9 -> 15.3 ms |
| Terrain | ~187k of 618k prims, ~1.7 ms; hiding dressing did not change FPS (CPU-bound) |
| Roads | Before streaming: 88 mesh instances / ~90k triangles drawn everywhere, 43.6k collision triangles live. Streamed (2026-10-23, section 10): -54..-96 draws, -140..-190k prims at the hub poses, 1.8k collision triangles live; frame time unchanged (GPU-bound on terrain/vista) |
| Bake hitch | first-time region bakes run on a worker; cold start ~3.3 s |

Working budget for the user's rig (use these as gates in the plan): frame <= 16.6 ms at Medium, <= 12 ms at Low;
CPU main thread <= 10 ms; physics tick <= 8 ms; draws <= 600; prims <= 1.2 M at Medium; VRAM <= 2.5 GB at
Medium (3.5 GB card, ~1.26 GB measured at Medium today).

## 3. Known bugs / hazards

1. **MultiMesh CPU read-back is broken in Godot 4.7.2** (`docs/bug_foliage_multimesh_readback.md`): `get_instance_transform` /
   `transform_array` return identity after `set_instance_transform`. Fixed for `Foliage` by storing positions at generate
   time (`_positions`), like `PropScatterer._placed`. Rule: never read transforms back from a MultiMesh; keep a side array.
   Doc says the full suite re-run was pending at that time; the 2026-10-22 gate (1410 tests, 1 pre-existing failure) covers it.
2. `tests/suites/test_streaming_dressing.gd` only asserts size and run-to-run equality, so it cannot catch read-back
   regressions; strengthen when RegionDresser is wired in. (2026-10-22: dresser is wired; the suite now also pins
   square per-cell placement, bake-gated spawns, biome zones, filters and draw distances, but still reads the
   side arrays, not the MultiMesh.)
3. ~~Checkerboard terrain~~ FIXED 2026-10-22 (section 6). ~~No vista, camera far 4000, cliff at ~384 m~~ FIXED
   2026-10-23 (section 7).
3a. FIXED 2026-10-22: live-ring regions were queued at PRIORITY_PREFETCH by `_prefetch_ring` and never promoted,
   so after spawn they sat blank and flat behind ~150 corridor pre-bake jobs for tens of seconds
   (`terrain_seeder.gd::_prefetch_ring` / `_promote_live`, test `test_live_ring_beats_the_corridor_prebake`).
3b. Pre-existing, NOT fixed: typed Node exports set as bare `NodePath(...)` in `open_world_root.tscn` without a
   `node_paths=` header entry are silently null at runtime (e.g. `TerrainSeeder.terrain`, which survives only via
   its `get_node_or_null("../Terrain3D")` fallback; `ChunkStreamer.terrain` likely too). The new RegionDresser node
   uses `node_paths=` and its test asserts the resolved nodes.
3c. Pre-existing: irregular white flat patches beyond the highway north-east of the hub (~(700-900, 600-700)),
   visible in the untextured baseline too; source object not identified. The hub's static `Foliage` grass tufts are
   flat `PlaneMesh` quads that read as bright green squares (region grass is disabled for that reason).
3d. ~~The live ring cannot exist beyond +-4096 m~~ FIXED 2026-10-23 (section 8). Terrain3D's region map allows
   locations -16..15 and `TerrainSeeder` uses 256 m regions, so every ring region past 4096 m used to fail
   (`Terrain3DRegion set_location: Location (24, 20) out of bounds`, 238 errors in 60 frames in a headless probe,
   thousands per second in game) and the alpine and coast areas had no ground collision. Now the ring's far
   locations are virtual (baked + dressed, never sent to Terrain3D) and the vista is the collision-bearing ground there.
3e. ~~Some planned roads lie far below the heightfield~~ FIXED 2026-10-23 (section 9). Was (natural height minus
   road y): `touge-a` / `touge-b` 1969 m, `highway-ring` 1586 m at (6160, 5530), `touge-highway-ramp` 1378 m,
   `pass-highway-ramp` 116 m; the carve turned these into km-deep 40 m-wide canyons through the alpine massifs, in
   the live ring and the vista alike. Root cause: the planner's Ys were free-floating design values, never tied to the
   field, and the P1 massifs (1100 / 850 m) sat on top of the touge loops and across the ring's south-east quarter.
3f. Pre-existing, found 2026-10-23 (section 10), NOT fixed: on `hub-coast` about 1.79 km from its start (x ~1790,
   z 256..512), where `highway-ring` passes overhead, the live terrain covers the right half of the road for a few
   frames while the camera moves (rock/grass drawn over asphalt); held still, the road is clear. Same with road
   streaming off, and gone with the terrain hidden, so it is terrain (carve or clipmap LOD near the overpass), not
   road geometry.
4. ~~Roads/collision are all live~~ FIXED 2026-10-23 (section 10): geometry and collision stream per cell; the
   topology (junction search) at load is 36 ms instead of 21 s.
5. Traffic: unpooled spawn/free, single car model, no lane model, spawn ring is a square around the player including
   in front of the camera, stuck-rescue can teleport a car into view.
6. Float precision beyond ~8 km from origin (section 1.2).
7. Open: `test_post_race_cinematic::test_cinematic_retires_gameplay_rigs` fails (pre-existing); `test_pusher_cannot_cross_the_barrier` is flaky.
8. Mixed indentation: `traffic_spawner.gd`, `living_world.gd`, `road_network.gd` use spaces; the rest of `scripts/world` uses tabs.
9. Handoff open item: shared dark-road / back-face fix in `track_builder.gd` is uncommitted and owned by another task.

## 4. Done / partial / missing

| Area | State | Evidence |
|---|---|---|
| Heightfield, biomes (height), road carve, async streaming | DONE | terrain_baker/seeder + 3 suites |
| Road taxonomy, graph, routing, discovery, GPS, fast travel | DONE | road_graph, world_discovery, test_map_route |
| 19-corridor network, 60 km, 5 tiers | DONE (scale-limited) | corridor_planner, test_corridor_seeding |
| Surface grip, regional climate, day/night, weather FX | DONE | tests listed in ROADMAP |
| Events + collectibles + speed traps | DONE v1 | event_registry, collectibles |
| Ground textures / biome look | DONE v1 (2026-10-22) | 8 CC0 layers, control-map bake, LITE shader; captures in section 6 |
| Far-field vista | DONE v1 (2026-10-23) | TerrainVista + baker, camera far 24000 in the open world; section 7 |
| Region-streamed dressing | DONE v1 (2026-10-22) | RegionDresser in scene, biome kits, bake-gated, live-ring only |
| Trees/props outside the hub | DONE v1 (one conifer set, one rock, power poles) | ZONE_FOLIAGE / region_preset |
| Towns, buildings, signage, street furniture | MISSING | 2 pit buildings |
| Road mesh/collision streaming | DONE v1 (2026-10-23) | RoadChunkMesher + RoadNetwork.stream_geometry, far LOD; section 10 |
| Intersections, rural tier, town grids | MISSING | |
| Ambient traffic | PARTIAL (8 identical full-physics cars on centreline, no lanes) | traffic_spawner/driver |
| Pedestrians, police, intersections logic | OUT OF SCOPE v1 (user decision) | |
| Streaming tiles beyond current map | MISSING | |

## 5. Open questions

1. What is the exact total road km and per-tier km today? Needs one headless `CorridorPlanner.plan` run (cheap; needs the Godot slot).
2. ~~Is the checkerboard really "no texture assets"?~~ Answered 2026-10-22: yes (addon fallback without Terrain3DAssets).
3. Should the open world move its origin to the map centre now (float precision) or only when the map is extended?
4. ~~Is `RegionDresser` intentionally unwired?~~ Answered by measurement 2026-10-22: wired, it costs ~0 ms of frame
   time at the hub (section 6); spawn work is bounded per frame.
5. Which car does the player expect traffic to be (Japan-flavoured JDM civilians vs generic Kenney CC0 vehicles)? Licence/asset policy matters (CC0-first).

## 6. Stage 1 (2026-10-22): ground textures + RegionDresser wired

### 6.1 What changed

- **Textures**: 8 CC0 ambientCG layers (`assets/terrain/SOURCES.md`): grass Grass004, meadow Ground037, dirt
  Ground048, rock Rock030, sand Ground054, snow Snow006, gravel Gravel043, forest floor Grass001. Packed by
  `tools/pack_terrain_textures.py` into Terrain3D's 2-array layout (albedo+height, OpenGL normal+roughness),
  1024 px, VRAM compressed + mipmaps (~45 MB PNG source in `assets/terrain/textures/`).
- **`scripts/world/terrain_texturing.gd`** (new): layer table, control-bit encode/decode (pinned against
  `Terrain3DUtil`), `build_assets()`, `apply(terrain, quality)`. Two shader tiers: `QUALITY_LITE` (default; the
  addon's `extras/shaders/lightweight.gdshader` as override) and `QUALITY_FULL` (generated shader: detiling,
  projected UVs on steep faces; dual scaling off). Autoshader (background past the ring + not-yet-baked
  regions) is plain grass. Roughness pushed up per layer (natural ground; the scans' own roughness mirrored
  the sky as white blotches at grazing angles).
- **Control map**: `TerrainBaker.bake_region_control()` + pure `classify_ground()` (height bands, slope -> rock,
  snowline ~850 m with noise, beaches only by the coast/sea biomes, world-space patch/detail noise for
  meadow / forest-floor / dirt, gravel shoulder + dirt fringe from each road's real width). Baked on the
  seeder worker next to height + colour, cached, written as `TYPE_CONTROL`. Nature is classified per 2x2
  texels, road-affected blocks per texel. Colour map is now a near-white tint with world-space brightness
  (it multiplies the textures; the per-region-seeded wobble showed as tinted squares).
- **Seeder**: `apply_ground_textures`, `ground_texture_quality`, `bake_ground_control`, `has_baked_region`,
  `baked_region_control`; live-ring priority fix (3a above).
- **RegionDresser in `open_world_root.tscn`** (`node_paths=` header so its exports resolve): biome zone per
  region (`region_zone`: lowlands / highlands / coast / alpine from natural height + coast weight), natural kits
  only (`region_preset`: rocks + power poles; no racing kit in the countryside), square per-cell placement (no
  overlap), foliage filter (treeline, beach sand, `clear_zones` hub clearing), spawns wait for the region's bake,
  nearest-first queue, grass deferred and time-sliced (`grass_tufts_per_frame`), per-batch draw distances
  (grass 140 m, props 420 m, trees 900 m), only live-ring dressing drawn (`band_shown`), 1 dress + 2 frees per
  frame, `region_grass_scale = 0` in the scene (flat-quad grass looks like green squares). The 5 `Props*` kits and
  the hub `Foliage` stay as static landmark kits. Shared static mesh/material caches in Foliage/PropScatterer.
- **`PropScatterer.is_clear_of_road`** now uses `RoadNetwork.nearest_road_lookup(pos, max_dist)` (grid, bounded
  search) instead of scanning every road point: same answers (485/485 on 500 random points of the real network),
  0.033 vs 2.4 ms per call.

### 6.2 Measurements (GTX 970, 1080p, Medium preset, vsync off, fixed camera poses around the hub)

| Pose | A: untextured, no dresser | B: full shader, no dresser | final: LITE + dresser |
|---|---|---|---|
| a eye, field | 12.59 ms | 19.05 | 12.86 (+0.27) |
| b high, hub | 17.59 | 28.69 | 18.54 (+0.95) |
| c eye, road | 10.61 | 13.32 | 11.28 (+0.67) |
| d high, outward | 13.65 | 20.50 | 13.90 (+0.25) |

- Full (generated) shader with dual scaling: +2.7..+11 ms; dual scaling alone 1.5..4 ms; projection + macro
  variation ~0.3 ms. LITE: +0.5..+1.2 ms. The dresser itself measured ~0 ms (+30..50 draws, +100..250k prims).
- Bake costs per 256 m region (worker thread): height ~50 ms, colour ~90 ms, control ~76 ms (hub region with
  many roads 169 ms). Cold start pays one extra control bake for the player region (~0.1-0.2 s).
- Dresser main-thread work (headless probe, real corridor network): worst drain ~5 ms with grass on, ~2-3 ms
  typical (props ~0.6 ms + trees ~1.5-2 ms per region; grass slices ~1-1.5 ms each); first region pays the
  one-time GLB/tree-mesh load (~100 ms, inside the loading screen at spawn).
- Not measured: hitch_probe drive-through, physics tick, VRAM delta (texture arrays ~16 x 1024^2 BC3 ~ 22 MB
  estimated), RAM of the bake cache (+256 KB per cached region for the control map).

### 6.3 Captures reviewed (Claude, Read tool)

Scratchpad `.../0b37d5da-.../scratchpad/fixed/` (A_*, B*_*, C2_*, C4_*) and `cap/openworld_after1_*`.
Before: checkerboard everywhere. After: grass / meadow / forest-floor patches, gravel shoulders with a dirt
verge, rock on road cuttings, trees and boulders across every live region, grass to the horizon.
Open visual issues: meadow patches still read a bit bright and blocky-edged (2 m classification + LITE shader
blending), conifer set only (no broadleaf / bushes), live-ring edge is a cliff to the flat background (vista
work), the hub's own flat grass quads, the pre-existing white patches (3c), Rock030 cuttings read as dark-ish.

### 6.4 Unverified

Not played by hand or driven (no drive-through hitch probe); alpine / coast / highlands regions not captured
(only the hub area: the car spawns there and the dresser/seeder follow the car); High/Low presets not
measured; `QUALITY_FULL` not offered in the settings ladder (could map High -> FULL later).

## 7. Stage 2 item 1 (2026-10-23): far-terrain vista

Full as-built notes, deviations from the plan and the z-fight proof: `terrain_vista_plan.md` section 9.

- **What**: `TerrainVista` (scene node) owns a second `Terrain3D`: 3x3 regions of 1024 px at 8 m
  (x/z [-8192, 16384)), no collision, no shadows, the live terrain's texture set and LITE shader,
  heights = the live ring's canonical field minus 1 m (exact ring-support sampling on cell seams,
  the biome-union step and the 2000 m clamp; road carve with a sag allowance), colour map with
  mipmaps, control map classified per 16 m. Built in the background on 3 WorkerThreadPool tasks,
  nearest region first; started from `world_driver.gd` right after `_bootstrap_roads()`. Cameras
  in the open world get `far_clip = 24000` (tracks keep 4000). The live terrain's flat world
  background is switched off (it hid the vista and cost up to ~3 ms at high poses by itself).
- **Main thread**: one-time ~0.5 s inside the loading screen (nine blank regions); then one map
  write per frame, max 1.2 ms. Warm-up frames while the vista builds: max 26.9 ms vs 26.5 ms
  baseline, 0 frames > 33 ms. All nine regions land in ~29-32 s (spawn region first, ~6 s).
- **GPU (Medium, ms/frame, stage 1 poses)**: a 12.89 -> 14.18, b 18.63 -> 19.79, c 11.39 -> 13.75,
  d 13.93 -> 15.71; highland pass +1.8..+3.0. Low: +0.4..+1.9 ms (worst pose 13.08 ms, still 76 FPS, but
  +6..+30 %, over the plan's 5 % line). VRAM 1245 -> 1376 MB, draws +45..+60.
- **Captures reviewed** (Claude, Read tool), scratchpad
  `D:\Temp\claude\d--AI-Projects-UltraDriveafc40e3-6ded-4a3e-bfa8-14f5654eec46\scratchpad\cap\`:
  the hub ring now continues into rolling vista terrain with no cliff, no gap, no z-fight band and no
  colour step at the seam; the alpine range stands on the horizon in aerial haze (it was clipped
  before); the flat-plane white blotches beyond the ring are gone (the ones inside the ring, 3c,
  remain); highland pass merges into the vista mountain; coast reads as a sand plain to the sea.
  From inside the alpine area the 3e road canyons show as blade-like walls.
- **Open**: GPU cost (a colour-only vista shader measured ~1-2 ms cheaper but needs a colour-match
  pass); bugs 3d and 3e; High preset and a driven hitch probe not measured.

## 8. Bug 3d fixed (2026-10-23): ground and collision beyond +-4096 m

**Root cause.** Terrain3D keeps its regions in a 32 x 32 location map (locations -16..15). With the
seeder's 256 m regions that is world x/z [-4096, 4096). The drivable world reaches x 9702 / z 8605, so
every ring region the car needed past 4096 m made `add_region_blankp()` log `Location (x, y) out of
bounds. Max: -16 to 15` twice (`Terrain3DRegion.set_location` and `Terrain3DData.add_region`, the second
with location (2147483647, 2147483647)) and return null, every physics tick. Reproduced two ways: the
fixed-pose probe at the alpine pose logged 4290 errors; a headless seeder probe at (6200, 5200) logged
238 in 60 frames. With no region there was no live ground, no terrain collision and no dresser output.

**Options considered.**
1. Bigger live regions (SIZE_512 / 1024). A 1024 m region at 1 m is 16x the bake, the sync bake of the
   player's region, the VRAM and the Jolt heightfield per region; SIZE_512 only reaches +-8192, not 9.7 km.
   Rejected.
2. Origin shift / node offset. Probed: Terrain3D 1.0.2 ignores the node's transform for region
   locations (a node at (8192, 0, 8192) still maps world 9000 to location (35, 35)). Re-centring would
   mean removing and rewriting every region, plus every height query in the project. Rejected.
3. vertex_spacing 2..4 on the live node. Visible loss of resolution at the car and a new bake path.
   Rejected.
4. **Chosen: virtual regions + collision on the vista.** The vista already draws the same canonical
   field everywhere, so it only needs collision, and the ring only needs to stop talking to Terrain3D
   where Terrain3D cannot hold a region.

**Fix.**
- `terrain_seeder.gd`: `LOC_MIN/LOC_MAX` (-16/15) and `loc_in_terrain_bounds()`. A ring location outside
  the window is *virtual*: baked on the worker and cached like any other, announced through
  `region_entered` / `region_left` at the same moments a real region would be, but never added to
  Terrain3D (`_ensure_virtual_region`, a virtual branch in `_apply_record`, virtual eviction in
  `_remove_far_regions`, bounds checks in `_ring_region_settled`, `_region_work_pending`,
  `force_player_region_color_bake`). The RegionDresser only needs `has_baked_region` and the signals,
  so trees, rocks and poles now appear in the alpine and coast areas too, standing on the canonical
  field. No sync bake happens for a far player region, so crossing the edge has no hitch.
- `terrain_vista.gd`: `sync_player_pos()` (called from `WorldDriver._push_player_position`) turns on
  Terrain3D's DYNAMIC collision (shapes around the active camera, built from the very height maps that
  are drawn) when the player is within 512 m of the window edge or beyond it and the vista region under
  the player has been written; off again 768 m inside. It hands the viewport camera to Terrain3D
  explicitly (Terrain3D stops its physics process for good if it finds no camera when it starts).
- `terrain_vista_baker.gd`: the seam. `BIAS` (-1 m) only exists to hide the vista under the ring, and
  past the window there is no ring, so a flat -1 m would put the visible and drivable ground 1 m under
  the canonical field and leave a 1 m wall for a car crossing the edge. `bias_at()` keeps -1 m up to 128 m
  inside the window, eases to -0.3 m at the edge and to 0 over the next 128 m. Everything inside the window
  is as before (the ring still wins the depth test, tests prove it incl. the new fade strip); the
  canonical heightfield mapping is untouched. The control bake recovers the natural height with the same
  `bias_at`.
- `living_world.gd`: `PropsCoast` (5888, 1536) and `PropsAlpine` (5632, 5632) asked Terrain3D for
  ground height past the window and got NaN -> 0; they now use the canonical field there.

**Tests.** `tests/suites/test_far_ground.gd` (6): window constants; the alpine ring logs no "out of
bounds" error (a `Logger` counts them) and still announces all 9 locations; a ring straddling the edge
mixes 4 real + 5 virtual regions and evicts both kinds on leaving; `bias_at` shape; baked far band sits on
the field past the fade and 1 m under it inside; the vista has collision under the car in the alpine area.
`test_terrain_vista_baker.gd`: the old tests compared the far vista to a ring that cannot exist there; the
clearance rule now only applies inside the window, the tracking rule uses `bias_at`, plus a fade-strip
test.

**Measured.** Before: 238 bounds errors in 60 frames (headless seeder probe at (6200, 100, 5200),
9 ring locations never announced). After: 0 errors, 9 of 9 announced, 0 Terrain3D regions. In game (windowed,
car frozen until the vista is complete, then released): 0 "out of bounds" lines; the car stays on the
surface. Seam drive (20 m/s across x = 4096, car origin above the canonical field): -0.07 m on the ring,
-0.35 m for a moment after the edge (the 0.3 m curb, vertical speed -1.0 m/s), back to -0.05 m 120 m later;
with a first -0.5 m edge value it was 0.47 m / -2.9 m/s, hence -0.3. Alpine (6094, 1024, 5033, a ~45 degree
slope) and the 2000 m dome top (5780, 6500): the car stays 0.8 m / -0.06 m from the field for 420 frames.
Coast (8000, -1500): see weakness below. Captures `seam_f600.png` (driving on grass past the window edge,
trees standing on the ground, no visible seam), `alpine2_f400.png`, `coast_f400.png` in the scratchpad `cap\`.

**Remaining weaknesses.**
- The far ground is the vista's 8 m mesh: collision is as coarse as what is drawn (chords of up to ~0.6 m
  from the 1 m field in rough terrain), road carving is 8 m, the road meshes keep their own collision.
- Dynamic collision follows the *active camera*: any camera that is not near the car (cinematic, photo
  mode) moves the collision away from it.
- Collision exists only once the vista region under the player is applied (~6 s for the first region, ~30 s
  for all nine after load). Fast travel into the far area within that time drops the car.
- Dressing in the far area stands on the canonical field; within the 256 m fade (0..0.5 m) it can float
  that much.
- `FallbackGround` (a y = 0 slab under the world) is older than this fix and still exists: a car that is
  *spawned* (not driven) over sea-level far terrain releases its ground latch on it, ends up 1 m under the vista
  surface and stays there (the heightfield is one-sided). Driving in from the ring never does this.
- 3e (roads far below the heightfield) was still open here; fixed afterwards, see section 9. Float precision beyond ~8 km is untouched.

## 9. Bug 3e fixed (2026-10-23): roads agree with the heightfield

**Reproduced first** (`CorridorPlanner.plan` vs `TerrainBaker.natural_height_at`, max ground-minus-road per road, m):
touge-a 1969, touge-b 1969, highway-ring 1586 (49 of 192 vertices > 65 m), touge-highway-ramp 1378,
pass-highway-ramp 116; the rest <= 63. Along the ring the ground is 767-1593 m between vertices 18 and 42 (the ring's
south-east quarter runs through the skirt of the two alpine massifs, `DOME_FAMILY[0]/[1]`, amp 1100 / 850, clamp 2000)
while the ring sat at y 6-38.

**Root cause.** Not units, not the sampler: the planner never read the field. `world_driver` and `event_session` call
`CorridorPlanner.plan(seed, Callable(), ...)`, and an empty provider meant "flat-Y fallback": the ring got a 22 +/- 16 m
bank, the touge loops 115 +/- 85 m, centred on the *massif centres* (`DOME_FAMILY[0]/[1]`). That was fine while the P1
domes were a few hundred metres; they grew to 1100 / 850 m (P1 commit fbfb648, "driveable corridor bases preserved" only
covered the 2 / 18 / 35 m biome bases) and nobody re-checked the corridors. Even with a provider the old touge code
clamped Y to 300, and a ramp from a 22 m ring to a 1400 m summit loop could never be drivable.

**Fix** (`scripts/world/corridor_planner.gd`, no change to the terrain, vista, domes or any carve rule):
- `plan()` defaults the height provider to `canonical_height_provider()` (TerrainBaker's natural field, the same one the
  live ring and vista bake). Callers need no change; a caller-supplied provider is used as before.
- Touge loops moved to the highland shelf in front of the massifs (`TOUGE_A_CENTER` (7100, 1900) r600, `TOUGE_B_CENTER`
  (5500, 2100) r450; ground 50-190 m, inside the touge band) with Ys sampled from the smoothed field.
- The ring is deflected inward between vertices 6..50 to the foot of the massif (`_ring_radial_scale`: slide toward the
  centre until the ground within 200 m is < 240 m, erode + blur, fade to the exact ellipse at both window ends). Every
  other vertex is bit-identical, so the ramps anchored at ring 65/96/110/160/174 keep their geometry; the touge
  on-ramp now lands on ring vertex 4 (was 24).
- `_conform_chain_y`: wherever a road is more than 10 m (cut) / 40 m (fill) off the smoothed ground its Y is pulled
  back, blended over 450 m, faded to 0 at anchored ends, merge lanes and junction vertices untouched. Applied to the
  ring, the touge-highway / pass-highway / highway-pass ramps. Roads already inside the band are unchanged.

**After** (same measurement, raw natural height, cut / fill in m): highway-ring 48 / 38 (worst: the lowland-edge descent
at ring 60, the rest <= 30), touge-a 5 / 18, touge-b 10 / 6, touge-highway-ramp 1 / 38, pass-highway-ramp 56 / 33
(its start is the pass loop's own 63 m cut, pre-existing), highway-pass-ramp 56 / 15. Max grade over 100 m: ring 17 %,
touge ramp 12.5 %. Regression: `tests/suites/test_road_terrain_agreement.gd` (tolerance cut 70 / fill 45).

**Side effects to know about.** The ring now climbs 30 -> ~190 m over the highland shelf between vertices 6 and 30
(was a flat 6-38 m bank), so `test_all_road_y_in_driveable_band` allows 250 m for non-touge roads. The two touge loops no
longer sit on the massifs, so the "touge" is a hilltop circuit, not a summit run; the massifs are scenery again.

**Remaining.** The ring's flank between vertices 16 and 22 is a 20-30 m side-hill cut that renders as a rock-textured
scar; the ring's east edge climb (vertex 6-7) is ~17 %; touge grades reach 21 % (terrain slope). `hub-coast` keeps its
legacy end-Y (reads only a caller-supplied provider). No road yet climbs the massifs themselves.

## 10. Stage 2 item 2 (2026-10-23): road meshes and collision stream per cell

**Before.** `RoadNetwork.add_road_def` built one `TrackBuilder` per road at load: 19 roads, 4,256 points, 94.9 km,
88 mesh instances / 89.9k triangles, 45 static bodies / 45.7k collision triangles, all live. Each road was one mesh with
one AABB (the 25.6 km `highway-ring` too), so most of them were drawn and in the 60 m shadow pass from anywhere. Each
`TrackBuilder` made its own materials, i.e. its own 512 px noise textures. Load (main thread, headless): build 140 ms,
rails 81 ms and **`RoadGraph.build_topology` 21.2 s** (all segment pairs of all road pairs), inside
`WorldDriver._bootstrap_roads` before the first await; every headless suite that loads the open world paid it too.

**What was built** (`scripts/world/road_chunk_mesher.gd` new; `road_network.gd`, `road_graph.gd`, `world_driver.gd`,
`track_builder.gd` (`frame_at` static), `open_world_root.tscn`):
- `RoadNetwork.stream_geometry` (default off; on in the open-world scene). `add_road_def` registers the def only;
  topology, nearest-road grid, maps, discovery, traffic and the terrain carve read the defs and are unchanged.
  `recompute_rails` keeps each road's junction rail gaps for the cell builds.
- Cells of 256 m (the seeder's region grid). Every segment (k -> k+1, plus a closed road's wrap) belongs to the cell of
  its midpoint and is built from `TrackBuilder.frame_at`, the old frame math. The union of the cells is the old road,
  triangle for triangle (surface, edge lines, dash phase carried on in double precision, rails and their gap ranges,
  carriageway + rail collision with `create_trimesh_shape`'s 0.1 mm vertex weld); neighbouring cells share
  bit-identical seam vertices. One mesh per material per cell, materials shared network-wide.
- Cells within Chebyshev 2 of the car are built on `WorkerThreadPool` (max 2 in flight) and added nearest first under a
  2 ms budget per frame; cells past 3 are freed (2 per frame). `sync_player_pos` (every physics tick from
  `WorldDriver._push_player_position`, 4.3 us per call) builds any missing cell of the 3x3 block around the car
  synchronously (spawn, fast travel, a car outrunning the worker). `prime_stream` builds the radius at load.
- At load every material the network uses, and its shader pipelines (one hidden one-quad instance per material), is
  created (60 ms in the loading screen). Without that, the first DIRT-tier cell met at a fast travel cost 160 ms.
- Far LOD: one mesh of the whole network (carriageway + edge colours as vertex colour, 24.3k triangles, 6 cm under the
  road, no collision, no shadow) so roads stay on the horizon past the stream radius (the vista does not paint roads).
- Edge lines and lane dashes no longer cast shadows; carriageway and rails still do (a first version turned the
  carriageway off too and an overpass lost its shadow on the road below; caught in the A/B captures, reverted).
- `RoadGraph.build_topology`: segment boxes + a 64 m XZ grid per road; a road pair only visits segment pairs whose boxes
  can be closer than the 15 m link threshold, in the same order with the same strict-< rule, so every junction is
  identical to the all-pairs scan. Same 41 junctions, 21,217 ms -> 36 ms.

**Measured** (GTX 970, 1080p, Medium, vsync off; A/B = same tree, `stream_geometry` off/on, back to back, after bug 3e
landed; probes in the session scratchpad `rs\`: `probe_roads.gd`, `probe_drive.gd`, `rs_bench.gd`):

| stage 1 pose | ms off -> on (2 runs each, mean) | prims off -> on | draws off -> on |
|---|---|---|---|
| a eye, field | 14.29 -> 14.24 | 655k -> 466k | 263 -> 179 |
| b high, hub | 19.86 -> 19.85 | 932k -> 791k | 259 -> 205 |
| c eye, road | 13.80 -> 13.84 | 659k -> 491k | 275 -> 201 |
| d high, outward | 15.68 -> 15.67 | 528k -> 363k | 198 -> 102 |
| f horizon NE | 17.11 -> 17.05 | 734k -> 570k | 290 -> 207 |

- Frame time: no change beyond the +-0.2 ms run-to-run noise. On this GPU at Medium the open world is bound by
  terrain/vista fragment work, not by road triangles or draw calls. The gain is headroom for a bigger network: cost now
  scales with the roads near the car, not with network length.
- Memory: static RAM 523.9 -> 502.2 MB at the hub (677 -> 656 MB after a drive), VRAM 1376 -> 1362 MB; nodes 1817 -> 1723.
  Live road collision 43,586 -> 1,834 triangles (drive), 45 -> 16 bodies (hub).
- Drive, `hub-coast` 6 km at 70 m/s (car moved kinematically, chase camera): avg 25.06 vs 25.27 ms, p99 47.1 vs 50.6,
  frames > 33 ms 364 vs 391 (on vs off; the spikes in both come from terrain/dresser streaming). Road work on the main
  thread: worst cell add 1.24 ms, worst frame 1.68 ms; worker build <= 1.3 ms per cell. `highway-ring` 8 km at 90 m/s:
  worst frame 1.40 ms.
- Collision continuity: rays for road collision under the car and 80 / 200 m ahead every 4th physics tick: 0 misses of
  3,900 (hub-coast) and 4,032 (highway ring at 90 m/s). The test suite drives a ring at ~940 m/s equivalent: 0 misses.
- Fast travel: the synchronous 3x3 road build costs 1.9-7.3 ms (the terrain seeder's own sync bake around it is
  300-1000 ms). Load, roads only, main thread: before 140 + 81 + 21,217 ms; after 36 ms register/topology/rails +
  18 ms tables + 35 ms far LOD + 60 ms materials + ~10 cells at ~1 ms (headless numbers for the first two).
- Gate: 1716 tests, 1 failure (pre-existing `test_post_race_cinematic.gd:239`), 0 false greens (before: 1694 / same
  failure). Gate wall time 300 s -> 179 s, mostly the topology fix (each open-world scene load was 21 s).

**Tests.** `tests/suites/test_road_streaming.gd` (14): cells rebuild `TrackBuilder` exactly (4 roads: banked closed ring
with junction gaps, 4-lane highway with a < 0.5 m segment, dirt, mixed asphalt/gravel with a one-side rail range; 64 m
and one-chunk cells); every segment in exactly one cell; bit-identical seams; rail gaps equal the whole-road path;
load/free around the car; shared materials and the shadow rule; fast-travel target has the 3x3 block and collision
without waiting; drive two laps probing under and ahead; freeing with jobs in flight; materials warmed for every bucket;
the open-world scene streams. `tests/suites/test_road_topology.gd` (2): junctions identical to the all-pairs scan.

**Captures reviewed** (Claude, Read tool), scratchpad
`D:\Temp\claude\d--AI-Projects-UltraDrive\2afc40e3-6ded-4a3e-bfa8-14f5654eec46\scratchpad\rs\cap\`: `p0_*` vs `p1_*` /
`ab_*` (poses, off/on): identical near roads; far roads continue to the horizon on the far LOD. `crop_f_ab.png`: the
distant highway reads a little lighter streamed, because the far LOD has no guard rails (they darken the line in the
old view). `drive_ab_*.png` (hub-coast every 600 m, off left / on right): same road, no pop-in or gap seen at the
cell borders crossed. `hold_grid.png`, `q0_grid.png` / `q1_grid.png` (terrain on / hidden) / `r0_grid.png` (streaming
off): the transient terrain-over-road at the `highway-ring` overpass is pre-existing (3f).

**Remaining weaknesses.**
- Frame time did not improve at the stage 1 poses; the win is draws, triangles, collision and memory, plus load time.
- The far LOD has no rails or lane dashes; past ~512-768 m roads are carriageway + edge colours only (slightly
  lighter highway line at distance). It is one always-drawn mesh (24k triangles, 1 draw), also under the near roads.
- Stream radius 2 cells = at least 512 m of full detail ahead in any direction; a high camera can see the step from full
  detail to the far LOD (rails end) at that distance if it looks for it.
- Cells are sized for today's 95 km network; the hub cell is the worst (3.8 ms worker build, ~1.5 ms add).
- Not done here: the `MountainPassZone` scene keeps its own always-live `TrackBuilder` road; Low/High presets and VRAM
  on High not measured; not driven by hand.

## 12. FH6-look pass (2026-10-24): vegetation, atmosphere, terrain tones, roadside, landmarks

**Goal** (user): "make the map look more like Forza Horizon 6". Scope here is the 3D look of the driveable world, inside
the GTX 970 Medium budget. All new nodes are created at runtime by `WorldDriver._bootstrap_world_look()`; the scene
file is unchanged (other agents edit it), so its authored Environment / PhysicalSkyMaterial stay the fallback that
`test_environment_lighting` parses.

**What changed**
- **Flora** (`scripts/world/flora.gd`, `flora_meshes.gd`, `shaders/flora.gdshader`, `flora_grass.gdshader`): a third
  child per LIVE-ring dressed region (`RegionDresser.flora_enabled`, off by default so the dresser's unit-test contract
  of one Props + one Foliage child is unchanged). Procedural low-poly meshes built in code (no imported assets, no
  licence question): broadleaf oak / maple (with autumn tints) / birch / poplar, bush, shrub, standing grass clumps
  (blades, not flat quads), wild flowers (5 petal colours), dune grass, grey boulder / slab / crag (flat-based), and
  roadside furniture (delineator posts where a road has no rail, chevron boards on the outside of bends > 16 deg per
  30 m, blue route signs every 700 m on highway / arterial, wooden fences along lowland country roads). Placement is a
  jittered grid per kit entry decided by an integer hash of (region seed, entry, cell): deterministic, order- and
  slice-size-independent. Ground rules read the region's baked control map (`TerrainSeeder.baked_region_maps`, new
  read-only accessor): plants only on their texture (grass / meadow / forest / sand / rock), nothing on the gravel
  road + shoulder, trees test 9 points at their road clearance. World-space grove noise makes woods and open fields.
  Per-zone kits (`Flora.kit_for`): lowlands mixed broadleaf woods + bushes + grass + flowers in meadows; highlands
  birch/oak with conifers, more rocks; coast low shrubs, dune grass on sand, few trees; alpine shrubs, boulders,
  crags on rock, nothing on snow. Conifers per zone scaled (`ZONE_CONIFER_SCALE`: lowlands 0.3, highlands 0.75,
  coast 0.9). Time-sliced on idle dresser drains (`flora_budget_usec` 1.5 ms): a lowland region takes ~68 ms in ~31
  slices (headless probe). MultiMesh buffers written in one call; positions kept in side arrays (4.7.2 read-back bug).
  Grass / flowers are batched per 64 m patch (draw distance 130 m, shrink-to-ground fade 55..95 m in the shader);
  trees 900 m, bushes 320 m, rocks 650 m, crags 1400 m. Shadows: trees + crags from Medium, rocks/props on High.
- **Conifer shader** (`foliage_wind.gdshader`, shared with the circuits): back faces flip their normal (whole pines
  read black from the shaded side), wrap diffuse, darker low canopy / lighter tips, per-tree hue/value variation.
- **Terrain tones** (`terrain_texturing.gd`, `terrain_baker.gd`): meadow tint (0.86, 0.92, 0.78) -> (0.7, 0.8, 0.56) and
  meadow share capped at 0.62 (`MEADOW_MAX_SHARE`) so patches are a mottled grass/meadow mix, `blend_sharpness`
  0.5 -> 0.35 (softer patch edges); snow roughness +0.1 -> +0.55; beaches only below 3.4 m (`BEACH_TOP`, was 8 m: the
  whole coastal plain was sand). Hub static `Foliage` drops its 700 flat-quad grass tufts at runtime.
- **Atmosphere** (`scripts/world/world_atmosphere.gd`, `shaders/cloud_layer.gdshader`, `sea_water.gdshader`): colour
  grade via Environment adjustments (contrast 1.07, saturation 1.16, brightness 1.02); aerial fog 0.0012 -> 0.00026
  (x1.6 near the coast, x0.55 high up; `haze_for`) so the 24 km vista keeps relief instead of flat blue silhouettes;
  clearer PhysicalSky (turbidity 3.2, Mie 0.005, brighter ground bounce); time-of-day sun colour/energy (`sun_grade`:
  warm low sun, 1.3 at noon, faint blue at night; re-applied only when the hour moves > 0.05 h); an opaque sea plane
  at y = 0 over the sea biome (there was no water); a cumulus layer on a camera-following inverted hemisphere
  (not baked into the sky radiance; off on Low).
- **Landmarks** (`scripts/world/world_landmarks.gd`): shrine gate near the hub, farm (barn + silo), red/white radio
  mast, 5 wind turbines with spinning rotors on the highland shelf, lighthouse on the coast, observatory on the alpine
  shoulder. Primitive meshes, nudged clear of every road (`resolve_site`, 40 m), visible to 9 km. Visual only.
- **Quality hook**: `SettingsMenu.QUALITY_PRESETS[*]["world_detail"]` 0/1/2 -> `apply_world_detail()` calls
  `set_world_detail` on group `world_detail` (RegionDresser rebuilds Flora; atmosphere toggles clouds). Low thins
  small plants to 0.35x and bushes to 0.7x, no clouds, no tree shadows; High 1.4x grass.

**Measured** (GTX 970, 1080p, Medium, vsync off, noon, same tree before/after; probe `fh_probe.gd` in the session
scratchpad, poses a-f as in sections 6/10 plus biome stations reached by teleport), ms/frame avg:

| pose | before | after | | pose | before | after |
|---|---|---|---|---|---|---|
| a eye field | 14.08 | 14.21 | | roll road | 15.12 | 16.59 |
| b high hub | 19.92 | 20.48 | | high road | 14.10 | 15.37 |
| c eye road | 13.52 | 15.20 | | high side | 14.83 | 16.60 |
| d high out | 15.54 | 16.07 | | high over | 17.41 | 18.67 |
| f horizon NE | 16.92 | 17.65 | | alp road | 13.32 | 14.39 |
| low road | 15.24 | 16.35 | | alp over | 17.12 | 18.09 |
| low side | 14.17 | 15.08 | | coast road | 13.52 | 14.47 |
| low over | 22.85 | 23.57 | | coast over | 17.29 | 18.29 |

+0.1..+1.8 ms (worst: hub road pose c +1.7, highland side +1.8); prims +50..+300k (max ~1.02 M at the rolling
overview, under the 1.2 M gate); draws +60..+100 (max 289); VRAM 1363 -> 1375 MB; static RAM 502 -> 526 MB. The
40-45 m overview poses were already over 16.6 ms before. Low and High presets not measured.

**Captures reviewed** (Claude, Read tool), `D:\Temp\claude\d--AI-Projects-UltraDrive\f2a7efd1-cbf7-4d57-b7e5-4b678469a6f0\scratchpad\cap\`:
`base_*` (before) vs `a1_*` / `a2_*` (after) for every pose. Lowlands now mixed broadleaf woods with autumn accents,
bushes, grass clumps, flowers, fences and route signs under a cloudy blue sky; meadow patches no longer read as
bright yellow decals; the alpine massif shows rock and snow through light haze (was a flat blue-grey silhouette);
the coast has a sea on the horizon and grass/sand mix instead of a sand desert; chevrons line the touge hairpins.

**Findings / not fixed**
- Known issue 3c (white flat patches NE of the hub): not visible at its pose (e_3c_ne) in the baseline of this tree. A
  white box seen near pose a was identified by a screen-ray pick as the pre-existing `PropsFestival` grandstand.
- Alpine dome top (5780, 6500): the "very dark" read was the snow's low roughness mirroring the dark sky ground colour
  (fixed by the roughness change), but the summit there is the flat 2000 m `HEIGHT_MAX` clamp and the vista draws it
  as green ground well below where the dressing stands (pre-existing; the old orange rocks floated the same way).
  Rocks placed there float. Root cause in the vista bake at the clamp not investigated.
- The fog density change is a runtime override of the scene's authored 0.0012 (still inside the environment test
  band in the file). Grass clumps still read a little spiky up close; groves cluster only mildly. Coast sand/grass
  patches have stair-stepped edges (2 m classification). Not driven by hand; no drive-through hitch probe for the
  Flora slices; Low/High not measured; night/dusk grade only checked by unit test, not captured.
