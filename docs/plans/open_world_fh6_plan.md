# Making the UltraDrive open world feel like Forza Horizon 6 - gap analysis and phased plan

Decisions already taken with the user (not re-opened here):
- Growth is STAGED: first densify the current map (roads, biomes, towns, POIs, verticality), then extend
  toward FH5-scale (~100 km2) with streaming tiles.
- Traffic target is "FH6-style ambient AI": cars follow road splines at sensible speeds, lane-aware, brake/avoid
  for the player, stream in/out around the player, mixed vehicle types. NO full pedestrian / intersection /
  police simulation in v1. (Architecture in `open_world_traffic_plan.md`.)

Inputs: `open_world_status.md` (verified current state), `docs/research/fh6_*.md`, `world_compare.md`,
the four older open-world plans, and the web sources cited at the end. Planning only; no code or asset changed.

Machine budget (user's rig): GTX 970 3.5 GB, 1080p, Forward+, Jolt 60 Hz, Godot 4.7.2. Gates used throughout:
frame <= 16.6 ms Medium / <= 12 ms Low; main-thread CPU <= 10 ms; physics tick <= 8 ms; draws <= 600; prims <= 1.2 M
Medium; VRAM <= 2.5 GB Medium. Today the hub area is 12.6-14.7 ms at Medium (see status doc section 2), i.e. ~2-3 ms of
headroom, so every phase must pay for itself.

## 1. What "feels like FH6" means (facts we can cite)

- Biggest and densest Horizon map; "most dense and vertical" per the official reveal. Tokyo is the series' largest
  urban space (reported ~5x Guanajuato), layered elevated roads built with tech reused from the FH5 Hot Wheels expansion,
  plus coast, mountain roads, open countryside, Mt. Fuji backdrop, seasons that shaped location choice.
  Sources: forza.net full map reveal; The Drive; Game Rant (links in section 9).
- Size is unofficial: ~18-20.5 miles end to end, roughly 17-25% larger than FH5 (~107 km2 community estimate);
  figures of 7 regions / 10 areas / 74 districts / 670+ roads come from single, uncorroborated sources.
  Treat them as orders of magnitude only.
- Design principle (Playground): "condensed reality" - capture the feel of a place, art-first, density over raw area.
  This is the licence to stay at ~50-100 km2 and spend effort on density, not square kilometres.
- Traffic: no hard FH6 technical facts found. FH5/FH ambient traffic cannot be disabled, thins at night and in
  mountains/desert, and Drivatars are a separate system (forum/anecdotal only). Our spec is therefore a design, not a copy.

## 2. Gap analysis (UltraDrive today vs FH6 feel)

Gap score: 5 = blocks the "place" illusion, 1 = polish.

| Dimension | FH6 | UltraDrive today (verified) | Gap | Primary lever |
|---|---|---|---|---|
| Size | ~120-250 km2 (unofficial); 10-20 mile span | ring ~51 km2, bbox ~114 km2, almost all empty; origin at SW corner | 3 (area ok, content absent) | Phase 6 tiles; Phase 1-3 fill |
| Terrain realism | textured ground, rock faces, cliffs, snow, coastline, far horizon | Terrain3D default checkerboard, no ground textures, horizon ends ~384 m, no vista | 5 | Phase 0 |
| Roads | 4+ tiers, junctions, narrow alleys, elevated/stacked, tunnels, signage | 19 corridors/5 tiers on flat strips, overlapping junctions, no rural/town streets, no signs, no centre line on 1-lane roads, all meshes live | 4 | Phase 2-3 |
| Biomes | 6 distinct looks (city, plains, coast, lowlands, highlands, alpine) | 6 height bands + colour tint only; one tree set, one rock | 5 | Phase 0-1 |
| Density / props | towns, houses, vegetation everywhere, roadside furniture | 1 Foliage at hub, 5 prop nodes (<= 28 props), 2 buildings; nothing in ~99% of area | 5 | Phase 1-2 |
| Lighting / weather / ToD | dynamic weather per region, seasons, 60-min day | 40-min day, 6 weather states, 5 regional profiles, 4 seasons, rain/wet FX are SHIPPED; sky/clouds/fog/ambient are plain, 1 shadow split @ 60 m | 2 | Phase 4 |
| Traffic | ambient traffic + Drivatars; roads rarely empty | 8 identical full-physics cars on centrelines, no lanes, no variety | 4 | Traffic plan |
| Activities | many event families, 400 collectibles, barn finds, car meets | 8 event families placed + 28 collectibles + speed traps + discovery/fast travel | 2 | Phase 7 (content) |
| Verticality | alpine to ~3,000 m, elevated city, tunnels | heightfield to ~1.1 km domes, flat-strip roads, no tunnels/bridges | 3 | Phase 3 |
| Streaming tech | tiled, DirectStorage | worker-thread terrain ring + prefetch; dressing/roads/traffic not streamed | 3 | Phase 1, 2, 6 |

## 3. Guiding principles

1. Ground first. The checkerboard is what players see 100% of the time; no amount of props fixes it. Phase 0 before anything else.
2. Reuse the deterministic pipeline (seeded noise, `RoadDef`, region-hash dressing). Every new system is a pure function of
   (master seed, region/sector id) so it can be unit-tested and cached.
3. Stream everything that scales with area: terrain (done), dressing, road meshes/collision, traffic, building kits.
4. One Godot process at a time; every phase ends with GDUnit + captures I inspect myself (Read tool; never Ollama/Gemini)
   + perf probe numbers vs the budget above.
5. Do not read MultiMesh transforms back (4.7.2 bug); keep side arrays.
6. Prefer CC0 assets (existing policy): ambientCG / Poly Haven textures, Kenney / Poly Pizza models.

## 4. Phased roadmap

Effort units: person-weeks (pw) for one dev who can delegate asset/test chores to agents. Ranges, not promises.

### Phase 0 - "It looks like ground" (terrain texture, vista, horizon)   [2-3 pw]  PRIORITY 1

Deliverables
1. Terrain3D texture set (`Terrain3DAssets`) of ~8 CC0 PBR layers: lush grass, dry grass, forest floor, dirt/mud,
   gravel, sand, rock (cliff), snow. 1024 px, packed (albedo+height / normal+rough), BC compressed; VRAM +~80-150 MB.
   Assign on the `Terrain3D` node in `open_world_root.tscn` (or in `terrain_seeder._ready`).
2. Control map per region: extend `terrain_baker.gd` with `bake_region_control(...)` (band + slope + road-distance +
   biome noise -> base/overlay texture ids and blend), written next to height/colour in `terrain_seeder._write_region`
   (`TYPE_CONTROL`). Alternative if per-texel control bake is too slow: Terrain3D auto-shader with height/slope thresholds
   driven by the existing colour map (verify addon 1.0.2 API first; the docs page for texturing was not retrievable in this
   research pass).
3. Road shoulder blend (gravel/dirt strip) from the existing road-distance field; cliff texture on slope > ~35 deg.
4. Finish the far-field vista per `terrain_vista_plan.md` (baker exists; add `terrain_vista.gd` controller, wire in
   `world_driver._ready` after `_bootstrap_roads`, camera far 24000 in chase/orbit cams, -1 m bias). Gate: no ring-edge seam in captures.
5. Atmosphere pass for distance: aerial-perspective fog colour by time of day, so the vista fades instead of ending.

Files: `terrain_baker.gd`, `terrain_seeder.gd`, `open_world_root.tscn`, new `terrain_vista.gd`, `chase_camera.gd`, `orbit_camera.gd`,
new `assets/terrain/*` (+ `.import`), tests `test_terrain_biomes`, `test_terrain_seeder_streaming`, new `test_terrain_control.gd`,
`test_vista_baker.gd`, `test_vista_wiring.gd`.
Verification: determinism (bake twice, byte-equal control map); per-biome texture id assertions; captures at hub, pass,
alpine, coast, ring edge (Claude opens each); hitch probe has no new frame > 120 ms; perf_probe vs budget.
Perf budget: +<= 1 ms GPU Medium, +<= 0.5 ms CPU, VRAM +150 MB. Cold start stays ~3.3 s.
Risks: control-map bake cost on the worker (measure per 256 m region; bake at 128 px control resolution if needed);
vista fill cost at far 24000 (fall back to reduced far + fog); texture tiling visible at distance (use Terrain3D UV scale/ detiling).

### Phase 1 - Fill the world with vegetation and rocks (wire the streamed dresser)   [2-3 pw]  PRIORITY 2

Deliverables
1. Instantiate `RegionDresser` in `open_world_root.tscn`, remove the 5 static Props nodes and the single Foliage (or keep the
   Props anchors as "landmark kits" separate from the dresser). Update the pinned test
   `test_open_world_dressing_static_budget` deliberately (it asserts the old design; edit only with intent, per the
   project's "assertion edit = red flag" rule).
2. Biome-aware dressing tables, keyed by `TerrainBaker.elevation_band` + slope + distance to road: conifer (have), broadleaf,
   scrub/bush, palm/coastal grass, dry grass, boulders (rock_a + 2-3 new), snow-dusted conifers, reeds near sea. 6-10 meshes
   total (CC0, <= 1.5 k tris with Godot auto-LOD), MultiMesh per 64 m cell (not per region) so frustum culling works.
3. Road-aware placement already exists (`is_on_road`, `along_road`); add "no trees within 12 m of road, rocks/guardrail posts roadside".
4. Region-hash determinism kept (`DEFAULT_MASTER_SEED`, `region_dresser.gd`); keep position side arrays.
5. Roadside furniture generator: poles, reflectors/delineators, guardrail runs (reuse `PropScatterer` guardrail), road signs (later Phase 2).

Perf budget: <= 80k visible tree/grass instances, <= 100 added draws, +<= 1.5 ms CPU (dresser budget 2 regions/frame already),
+<= 2 ms GPU Medium; shadows: trees cast only on High (existing preset ladder), grass never.
Verification: `test_streaming_dressing` (strengthen: assert non-identity positions), new `test_dressing_biomes.gd`
(distribution per band within tolerance), captures per biome, perf_probe driving 5 km at 150 km/h with a hitch probe.
Risks: MultiMesh read-back bug (side arrays only), spawn hitching (budget 2/frame, test with `hitch_probe`), VRAM from tree textures.

### Phase 2 - Densify the road network (second tier, intersections, towns)   [4-6 pw]  PRIORITY 3

Deliverables
1. Road mesh + collision streaming: `RoadNetwork.add_road_def` builds every `TrackBuilder` at load. Chunk road geometry per
   256-512 m cell and instantiate with the terrain ring (+ prefetch), free outside. This is a prerequisite for any network growth
   (roads were 83% of attributed prims, ~2.8 ms at 60 km). Keep `RoadDef` as the data source of truth.
2. New tiers: RURAL (6-7 m, two-way, centre line paint) and RESIDENTIAL/TOWN (6-8 m grid streets) added to `RoadDef.Tier` (+ `TIER_COUNT`,
   default width/surface tables, map styling, tests `test_road_graph`, `test_map_road_labels`).
3. Proper intersections: junction geometry (T and cross patches, stop lines, curb radii) generated at `RoadNetwork.get_junctions()` nodes
   (today roads just overlap within 15 m).
4. Centre line + lane paint for two-way roads (needed for lane-aware traffic; see traffic plan section 3.1).
5. Corridor planner v2: add ~25-40 rural/secondary roads (seeded, terrain-following with a slope budget) and 4-6 towns; target +60-90 km of road
   (network ~120-150 km). Reuse `CorridorPlanner.plan` deterministic contract; extend `ROAD_NAMES` (test enforces names).
6. Towns (300-600 m): street grid from `corridor_planner`, building kit (6-10 CC0 low-poly buildings + instanced facades/roofs), street lights,
   signs, parked cars (existing `parked_ratio` seam), town plaza as POI. Place near flat terrain, away from the highway ring.
7. Road surface material: PBR asphalt / worn asphalt / gravel / concrete with proper UV tiling, plus the pending shared dark-road/back-face fix
   in `track_builder.gd` (owned by another task; coordinate).

Perf budget: roads <= 120 draws / <= 120k prims live at any time (streamed), building instances <= 300 live, +<= 1.5 ms CPU.
Verification: `test_corridor_seeding` (km, naming, tier counts), `test_road_graph` (junction completeness), new `test_road_streaming.gd`
(cells load/free with player, no gap in collision at cell borders), drive-through captures at each junction type, `hitch_probe`.
Risks: collision seams at chunk borders (overlap one segment), rail/merge logic coupling in `corridor_planner` (large, 928 lines, tested),
dark-road fix conflict, authored-quality ceiling of procedural towns (set expectations: "stylised", not photoreal).

### Phase 3 - Verticality and landmarks   [3-4 pw]  PRIORITY 4

1. Terrain features beyond fBm: ridge lines, cliff bands, canyons/coast cliffs, a river or two (carve + flat water plane with shader), baked as
   extra terms in `terrain_baker` (keep byte-stable for unchanged regions or bump a version).
2. Tunnels and bridges: heightfield cannot do overhangs, so author tunnel meshes + Terrain3D hole mask; bridge deck meshes over valleys.
   Start with 2 tunnels + 2 bridges on touge/coastal roads. Elevated/stacked highway (FH6's signature) is deferred to the extension stage.
3. Landmarks (10-15): lighthouse, observatory, dam, shrine gate, ski lodge at the alpine snowline, radio tower, wind farm; each a POI + photo spot,
   reachable by a named road, distinct silhouette visible from the highway (supports discovery).
4. Seasonal visuals: snow line from `regional_climate.gd` drives the terrain control map tint and foliage colour variants.

Perf: landmarks are static scenes streamed with the dresser; <= 5k tris each.
Verification: captures from the highway and from each landmark, `test_event_placement` still green, new landmark POI test.
Risks: Terrain3D hole API in 1.0.2 (verify), tunnel collision continuity with road trimesh.

### Phase 4 - Light, sky, weather polish   [2 pw]  PRIORITY 5

1. Cloud layer (shader sky or cloud-plane) + cloud shadows moving over terrain on High only; time-of-day colour grading (sunrise/sunset warmth, blue hour).
2. Regional haze/fog (alpine clear + cold, coast humid) from `RegionalClimate`; volumetric fog only on High (SDFGI/volumetric are already ladder-gated).
3. Wet road: PBR roughness + puddle noise driven by `WetSurface.wet_intensity` on road and terrain materials rather than only a screen overlay.
4. Shadows: sun currently 1 split / 60 m for all presets (`open_world_root.tscn`); give High 2 splits / 120 m once Phase 1-2 fit the budget.
5. Night: lit windows on town buildings, lit road signs, headlight cones on traffic (traffic cars already get `Headlights`).

Perf: Low/Medium unchanged; High may use up to +2 ms. Verification: `test_environment_lighting`, `test_weather_vfx`, day/night capture strip (6 times of day x 3 weathers).

### Phase 5 - Ambient traffic v1   [4-6 pw, can start after Phase 2.4]  PRIORITY 3 (parallel)

See `open_world_traffic_plan.md`. Summary: lane graph from `RoadDef`, spawn/despawn ring, kinematic lightweight cars with a physical swap near the
player, IDM following + brake-for-player, vehicle variety (Kenney CC0 civilian set), audio LOD, pooling, caps (24 live / 8 near-physical).

### Phase 6 - Extend toward FH5 scale with streaming tiles   [6-9 pw]  PRIORITY 6 (after 0-5 are green)

Starting point: ring ~51 km2 plus empty box ~114 km2. "FH5-scale" (~100 km2) is therefore mostly a content-and-streaming problem, not a terrain-size one.
1. Recentre the world: shift origin to the map centre (or adopt floating-origin) so no gameplay position exceeds ~5 km. The Godot docs recommend
   single precision only up to ~4096-8192 m for third-person games; current extents reach ~9.7 km. A one-time translation of baker constants,
   corridor planner anchors, POIs and the scene is mechanical but touches many tests. https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html
2. Define 1 km "sectors" as the unit of streaming and authoring: each owns road cells, dressing seeds, building/town placements, POIs, traffic density table.
   Sector manifest generated offline by a headless tool from the master seed (`tools/gen_sectors.gd`), cached to disk.
3. Terrain: bake to disk. Today every region is baked at runtime (worker, ~3.3 s cold start). For 100 km2 write baked height/colour/control
   images per region to `res://world_cache/` (or Terrain3D `data_directory`), load asynchronously; keep deterministic bake as the rebuild path.
   Keep RING 3x3 live + prefetch 2 (measured superlinear beyond that); prefetch from disk instead of CPU.
4. Add 3-5 new regions of content (second city/coast/desert/forest) using Phase 1-3 tooling; extend highway ring with a second loop and 2 expressways;
   add the elevated-highway city core as the "FH6 Tokyo" analogue (biggest build, optional).
5. Async sector loader with a frame budget (extend `TerrainSeeder` priority queues: LIVE > CORRIDOR > PREFETCH > DECOR) and a loading-screen fallback for fast travel.
6. Minimap/pause map: tile-based render cache (roads draw is already distance-culled), map zoom levels, region names.

Perf: unchanged live set (3x3 + prefetch); memory <= 2.5 GB VRAM; disk ~1-2 GB cache; hitch budget: no frame > 50 ms while driving at 250 km/h.
Verification: 30-minute soak drive (scripted) with memory/orphan counters, `hitch_probe` p99, determinism suite for sector manifests.
Risks: float precision refactor blast radius; disk cache size and import times; the headless-import dance in `AGENTS.md`.

### Phase 7 - Activity and progression density   [3-5 pw, ongoing]

More event families (road-trip routes, showcase stunts, barn finds, treasure cars), 100+ collectibles via `Collectibles` families, car meet in town plaza
(static cars + garage entry), weekly seasonal rotation (`regional_climate` season tie-in), photo-op challenges (`photo_spot`). Low risk, high content volume;
use agents for placement tables and tests.

## 5. Recommended sequencing

1. Phase 0 (ground+horizon) - immediately; biggest visible change per week, low code risk.
2. Phase 1 (dresser wiring + biome kits) - overlaps Phase 0 asset work.
3. Phase 2.1-2.4 (road streaming, tiers, junctions, centre line) - unblocks traffic and network growth.
4. Phase 5 traffic v1 in parallel with Phase 2.5-2.7 (towns/roads).
5. Phase 3, 4 interleaved as polish.
6. Phase 6 only when 0-5 meet the perf budget on the GTX 970; start with the origin recentre and disk-baked terrain.

Rough total to "dense FH6-flavoured 50 km2 world + ambient traffic": 17-25 pw; to FH5-scale streamed extension: +6-9 pw.

## 6. Test and verification gates (apply every phase)

- `--headless --import .` probe clean (zero SCRIPT/Parse errors), then the parallel gate `py tools\gdunit_parallel.py -j 4` (baseline 1410 tests; 1 pre-existing failure
  `test_cinematic_retires_gameplay_rigs`, 1 known flaky barrier test). New tests never edit existing assertions without an explicit design reason.
- Determinism: same seed => identical region/sector output (byte compare) for control maps, dressing positions, sector manifests, road cells.
- Visual: capture strips at fixed stations (hub, pass, coast, alpine, town, highway at dusk) before/after; Claude inspects each image (no Ollama/Gemini); commit before/after pairs under `.vision/captures/`.
- Perf: `tools/perf_probe.gd` + `tools/hitch_probe.gd` at Low/Medium/High; record in a table; reject phases that exceed the budget unless a mitigation is documented.
- One Godot at a time: use the shared lock directory `D:/Temp/claude/d--AI-Projects-UltraDrive/godot.lock`; give every run a shell timeout.

## 7. Risks (project-level)

| Risk | Impact | Mitigation |
|---|---|---|
| CPU-bound machine (GTX 970 era CPU): process + physics were ~47 ms with 15 full-physics traffic cars before the Sept cuts (now ~25 ms combined) | Traffic/dressing eat the headroom | Kinematic traffic, budgets above, measure per phase |
| Procedural towns/roads look generic | "Not FH6" | Art-direct a few hand-tuned hero zones (hub, one town, one landmark) and keep style stylised |
| Terrain3D API drift (1.0.2) for control maps/holes/instancer | Rework | Spike (half a day) at start of Phase 0 and Phase 3 |
| Test suite pins current design (dressing static, 3 roads indices 0-2) | Friction | Treat as explicit design edits; keep `defs[0..2]` invariant |
| Asset licensing | Blocks ship | CC0-only intake; record sources in `assets/*/License.txt` |
| Scope creep to full Tokyo | Schedule | Defer elevated stacked city to Phase 6 stretch |

## 8. Open questions

1. Art direction: stylised low-poly (current Kenney/Poly Pizza look) or push toward realistic PBR? This changes asset cost 3-5x.
2. Driving side for traffic and road paint: Japan-theme (left) or right-hand? (Cockpit code says RHD while one note says it renders LHD.)
3. Is a city core with elevated roads wanted in the first extension, or is a "town + highway" world enough for v1?
4. Disk budget for baked world cache (1-2 GB) acceptable in the repo/installer?
5. Is changing the pinned `test_open_world_dressing_static_budget` and recentring the origin acceptable churn?
6. Do we keep `TerrainSeeder` runtime baking for the extension or commit to offline-baked regions only?
7. Minimum target spec: is the GTX 970 the floor for the shipped game or just this dev machine?

## 9. Sources

- Forza Horizon 6 full map reveal (official): https://forza.net/news/forza-horizon-6-full-map-reveal
- Forza Horizon 6 Developer_Direct interview (Xbox Wire): https://news.xbox.com/en-us/2026/01/22/forza-horizon-6-developer-direct-breakdown-interview/
- The Drive, "Why Forza Horizon 6 is finally ready to take the series to Japan" (largest map/city, elevated roads from Hot Wheels tech): https://www.thedrive.com/news/why-forza-horizon-6-is-finally-ready-to-take-the-series-to-japan
- FH6 map size comparison (Game Rant): https://gamerant.com/forza-horizon-6-map-size-comparison-big-small-fh4-fh5/
- FH6 map overview (unofficial): https://gameluster.com/forza-horizon-6-japan-map-everything-we-know-so-fa/ ; https://game.wiki/forza-horizon-6/map
- FH5 map size (Dexerto): https://www.dexerto.com/forza/how-big-is-the-forza-horizon-5-map-mexico-map-size-revealed-1697682/
- Godot large world coordinates: https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html
- Godot MultiMesh (single draw call, no per-instance culling, visible_instance_count): https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html
- Terrain3D docs (regions, instancer, texture prep): https://terrain3d.readthedocs.io/en/latest/ ; https://terrain3d.readthedocs.io/en/latest/docs/instancer.html ; https://terrain3d.readthedocs.io/en/latest/docs/texture_prep.html
  (instancer: per-32 m-cell MultiMeshes, LOD support, shadow impostors, API `add_transforms`; textures: up to 32 sets, packed albedo+height / normal+rough, 1024 px typical.)
