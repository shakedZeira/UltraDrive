# UltraDrive open world - current status (verified against code, 2026-10-22)

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
| `docs/ROADMAP.md` W.6 / W.7 "region-streamed dressing wired into open_world_root.tscn" | Shipped | NOT wired. `RegionDresser` is built and unit-tested but is not in the scene; `test_open_world_dressing_static_budget` (`tests/suites/test_open_world_hud.gd:144-164`) pins "1 static Foliage + 5 static Props nodes and no RegionDresser" |
| `docs/plans/terrain_vista_plan.md` | Static far-terrain vista | Only `terrain_vista_baker.gd` exists. No `terrain_vista.gd` controller, no wiring in `world_driver.gd`, cameras still at default far 4000 |
| `docs/plans/open_world_optimization_plan.md` | Traffic = 15 cars | Scene now has `max_traffic = 8` (`open_world_root.tscn:196`); the spawner script default is also 8 |
| `docs/HANDOFF_2026-10-22_session.md` | Open-world capture hung in endless `TrafficSpawner._spawn_vehicle` null loop | Log shows 2,841 errors that all start with `Compile Error: Identifier not found: RaceManager` in the capture tool; the later `log_openworld_after.txt` run is clean (0 errors). Likely a harness compile problem, not a traffic regression (not proven) |

## 1. What the world is

### 1.1 Scene composition (`scenes/world/open_world_root.tscn`)

Root `OpenWorldRoot` (`world_driver.gd`) with: `Terrain3D` (collision FULL_GAME, no
shadows, **no texture assets assigned**), `TerrainSeeder`, `ChunkStreamer`
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
- **What it looks like** (captures `openworld_after_0_eye / 1_high / 2_high`, 2026-10-22):
  the ground is the Terrain3D default **checkerboard** with faint colour-map tint and sparse green
  flecks. No ground textures, no autoshader, no dirt/rock/snow materials. This is the single largest
  realism gap: `grep` finds no `Terrain3DAssets` / texture assets anywhere outside `addons/`.
- Horizon: terrain ends ~384 m out (ring) and falls to haze; the far-field vista is unimplemented.

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
  per-frame work, LOD by density) exists and is tested (`test_streaming_dressing`) but is not instantiated.
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
   regressions; strengthen when RegionDresser is wired in.
3. Checkerboard terrain (section 1.3), no vista, camera far 4000.
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
| Ground textures / biome look | MISSING | no Terrain3DAssets; checkerboard in captures |
| Far-field vista | PARTIAL | baker only, no controller, camera far 4000 |
| Region-streamed dressing | PARTIAL (built, unwired, test-pinned off) | region_dresser.gd |
| Trees/props outside the hub | MISSING | one Foliage node |
| Towns, buildings, signage, street furniture | MISSING | 2 pit buildings |
| Road mesh/collision streaming | MISSING | add_road_def builds all |
| Intersections, rural tier, town grids | MISSING | |
| Ambient traffic | PARTIAL (8 identical full-physics cars on centreline, no lanes) | traffic_spawner/driver |
| Pedestrians, police, intersections logic | OUT OF SCOPE v1 (user decision) | |
| Streaming tiles beyond current map | MISSING | |

## 5. Open questions

1. What is the exact total road km and per-tier km today? Needs one headless `CorridorPlanner.plan` run (cheap; needs the Godot slot).
2. Is the checkerboard really "no texture assets" or is a material override failing to load? (Cause inferred from code and captures, not from a Godot inspector.)
3. Should the open world move its origin to the map centre now (float precision) or only when the map is extended?
4. Is `RegionDresser` intentionally unwired (perf) or just never finished? The test comment suggests intent to stay static; git history does not show it ever in the scene.
5. Which car does the player expect traffic to be (Japan-flavoured JDM civilians vs generic Kenney CC0 vehicles)? Licence/asset policy matters (CC0-first).
