# UltraDrive open world - current status (verified against code, 2026-10-22)

> **Update 2026-10-22 (later, open-world stage 1):** ground textures and region-streamed
> dressing are now live. See section 6 for what changed, measurements and what is still
> unverified; sections 0-5 are corrected inline where they described the old state.
>
> **Update 2026-10-23 (open-world stage 2, item 1):** the far-terrain vista is built; the
> 384 m cliff is gone. See section 7, and two pre-existing world bugs it exposed (3d, 3e).

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
- **All roads are instantiated at load** (`add_road_def` builds one `TrackBuilder` child per road,
  `road_network.gd:53-65`). Nothing streams road meshes or collision. Perf attribution
  `e8fbf15`: roads were ~2.8 ms and 83% of attributed prims in the probe scene.
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
| Roads | 91 draws / ~90k prims, ~2.8 ms in the probe scene; grows with network because nothing streams |
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
3d. Pre-existing, found 2026-10-23, NOT fixed: the live ring cannot exist beyond +-4096 m. Terrain3D's region map
   allows locations -16..15 and `TerrainSeeder` uses 256 m regions, so any region past 4096 m fails
   (`Terrain3DRegion set_location: Location (24, 20) out of bounds`, thousands of errors per second while the car
   is there). The drivable world reaches x 9702 / z 8605, so the alpine and coast areas have no live ground or
   terrain collision (road meshes keep their own collision). The vista now draws terrain there.
3e. Pre-existing, found 2026-10-23, NOT fixed: some planned roads lie far below the heightfield. Measured
   (natural height minus road y): `touge-a` / `touge-b` 1969 m, `highway-ring` 1586 m at (6160, 5530),
   `touge-highway-ramp` 1378 m, `pass-highway-ramp` 116 m; everything inside +-4096 m is <= 63 m. The ring's carve
   turns these into km-deep 40 m-wide canyons through the alpine domes; the vista reproduces them faithfully.
   Needs CorridorPlanner elevations (or dome placement) to agree with the field.
4. Roads/collision are all live (section 1.4); extending the network multiplies load-time and per-frame cost.
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
| Road mesh/collision streaming | MISSING | add_road_def builds all |
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
