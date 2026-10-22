# Ambient traffic architecture for the UltraDrive open world ("FH6-style ambient AI")

Agreed scope (user decision): cars follow road splines at sensible speeds, lane-aware, brake/avoid for the player,
stream in/out around the player, mixed vehicle types. NOT in v1: pedestrians, traffic-light/intersection simulation,
police, Drivatar-style learning, multiplayer. Planning only; no code or asset changed.

Related: `open_world_status.md` (section 1.8 = what exists), `open_world_fh6_plan.md` (Phase 2 road work this depends on).

## 1. Starting point (verified in code)

`scripts/world/traffic_spawner.gd` (179 lines) + `traffic_driver.gd` (259 lines), ticked from `LivingWorld._physics_process`.

| Aspect | Now | Problem |
|---|---|---|
| Vehicle | full `VehiclePhysics` RigidBody (4 raycast wheels, Pacejka, drivetrain, audio, headlights) from `player_car.tscn`, `PlayerCarController` stripped | ~42% of physics at 15 cars; every car is the starter car |
| Spawn | random point in +-300 m square around player, `is_on_road(10 m)` on 8 tries, snaps to nearest road point | can spawn in front of the camera; can spawn on the wrong side; no gap check vs other cars |
| Path | `nearest_road_id` once, then aims 18 m ahead on that chain's centreline; open chains shuttle back and forth | no lanes (oncoming share the centreline), no junction turns, no following other cars |
| Speed | 41-69 km/h cruise, corner slowdown by steer magnitude | independent of road tier / curvature / speed limit |
| Player | slows/stops only if the player is within 10 m directly ahead | will not yield, steer or react to anything else |
| Lifetime | `instantiate`/`queue_free`, despawn beyond 400 m, one spawn per update if under cap (8) | allocation churn, no pooling |
| LOD | > 140 m: frozen + `_physics_process` off (shelved) | still full scene cost per car; cap keeps CPU OK only because cap is tiny |
| Recovery | stuck 5 s / 2 m => teleport to random chain point | pops cars into existence in view |
| Tests | `tests/test_traffic_spawner.gd`, `tests/suites/test_traffic_driving.gd`, `test_open_world_hud.gd` (max_traffic 1..15, spawn_radius <= 300, vehicle_scene set) | must be migrated deliberately |

Collision layers already reserved in `project.godot`: 1 Vehicles, 2 Track, 3 OpenWorld, 4 Traffic, 5 Checkpoints.

## 2. Target architecture (overview)

```
RoadDef[]  --(build, pure, deterministic, cached)-->  LaneGraph  (lanes, connectors, spatial hash)
                                                          |
Player pos/vel -> TrafficManager (Node, replaces TrafficSpawner; same public API)
                    |- SpawnPlanner   (ring + density + gap rules, seeded RNG)
                    |- TrafficCar pool (kinematic, 3 LOD tiers, shared meshes)
                    |- LaneFollower + IDM (per car, updated by manager in one loop)
                    |- PlayerAwareness (lane projection, TTC, oncoming nudge)
                    |- CrashPool (few RigidBody3D, swapped in on contact)
                    |- TrafficAudio (shared 3D voice pool)
```

Principles: (1) one manager loop, no per-car `_physics_process`; (2) simulation is 1-D along a lane (s, v) + a lateral offset, positions
derived from the lane polyline, so cars cannot leave the road; (3) physics only where the player can touch; (4) everything deterministic
from (master seed, sector, time bucket) so tests can replay; (5) pure logic (`LaneGraph`, `IDM`, `SpawnPlanner`) is RefCounted and headless-testable.

## 3. Road graph and lane splines

### 3.1 What exists and what is missing
`RoadNetwork` already has junction detection (`LINK_THRESHOLD = 15 m`), adjacency, `route()`, a nearest-road spatial index (32 m cells)
and seasonal tier closure. It has NO lane model: `RoadDef.lane_count_for(width)` returns 1 for < 15 m, 2 for >= 15 m, 4 for >= 24 m and only
drives where dashed dividers are painted (`track_builder.gd:188`). A 10 m arterial or 9 m touge has no centre line at all.
Highway default width is 24 m (4 painted lanes), arterial 10, touge 9, coastal 9, dirt 7.

### 3.2 New data: `LaneGraph` (`scripts/world/lane_graph.gd`, pure RefCounted)
Built from `RoadNetwork.get_road_defs()` after `_bootstrap_roads()` (same ordering contract as the terrain bake), deterministic, unit-testable.

- Travel lanes per direction (new `RoadDef.traffic_lanes_per_dir`, derived, overridable): HIGHWAY 2, ARTERIAL 1, TOUGE 1, COASTAL 1, DIRT 1 (low density), future RURAL/TOWN 1.
- Lane centre offset from the road centreline: one lane per direction -> +-width/4; two per direction on the 24 m highway -> +-(width/8) and +-(3*width/8)
  (the painted middle divider is the median). Offsets are measured in the banked road frame (use the same frame as `TrackBuilder._frame`, so lanes follow banking/camber and Y).
- Lane polyline: offset the centreline, resample to ~4 m spacing, store `PackedVector3Array pts`, `PackedFloat32Array s` (arc length), `v_curve` (see 6.4),
  `speed_limit` by tier (HIGHWAY 110 km/h, ARTERIAL 80, COASTAL 70, TOUGE 60, DIRT 40, town 40; tunable), `road_id`, `dir` (+1 along point order, -1 reverse = reversed array), `closed`.
- Driving side: configurable constant `DRIVE_SIDE` (-1 left-hand / +1 right-hand). Default per open question (Japan theme => left).
- Connectors: at each junction from `RoadNetwork.get_junctions()` create short lane-to-lane Bezier connectors (length 10-25 m) from every incoming lane to the outgoing lanes
  of the other road(s) in the correct direction; weights by tier (prefer same road ~70%). At dead ends (open chains) create a U-turn connector into the opposite-direction lane so traffic loops instead of shuttling.
  Closed loops need none.
- Ramps/merges (`*-highway-ramp` roads): connector at the taper end onto the highway lane; reuse `corridor_planner` anchors; v1 may treat ramp joins as plain connectors with a yield-by-gap rule (7.2).
- Spatial hash: 64 m cells -> list of (lane_id, index range) for `nearest_lane(pos, heading)` (used by spawn snapping and player projection). Size estimate: 120 km of road x 2 directions / 4 m = ~60k points x 20 B = ~1.2 MB; keep the whole graph resident (no streaming needed), unlike road meshes.
- Dependencies: Phase 2 of the FH6 plan adds centre-line paint and junction geometry; the lane graph can ship first on existing roads (cars drive right/left of an unpainted centre; cosmetic gap).
- Seasonal closures (`set_closed_tiers`): lanes of closed tiers get density 0 and are not spawn targets.

### 3.3 Density table (per tier, per 100 m of lane, daytime, Medium)
HIGHWAY 0.9, ARTERIAL 0.7, COASTAL 0.4, TOUGE 0.15, DIRT 0.05, town streets 1.2. Night x0.4, storm x0.6, alpine tier lanes x0.3 (FH traffic thins at night and in mountains; anecdotal).
Resulting live count is the min of the density-derived target and the quality cap (section 9).

## 4. Spawn / despawn ring

Replace the square `_random_offset()` with a planned ring around the player (world XZ):
- Spawn annulus: 140-280 m along the driver's reachable lanes (query `LaneGraph` cells in the annulus, not random world points).
- Visibility rule: never spawn inside the camera frustum cone (use the active camera's forward +- (fov/2 + 12 deg)) unless distance > 230 m; prefer lanes ahead of the player's motion (60%) and behind (40%).
- Gap rule: min 14 m (+ 0.5 s of lane speed) to any existing car on the same lane; never within 40 m of another spawn done in the last 0.5 s.
- Despawn: beyond 330 m, or behind the player AND > 200 m, or out of ring for > 4 s; never despawn a car whose mesh is on screen within 200 m (defer one tick). Hysteresis between 280 m and 330 m prevents flip-flop.
- Rate limit: <= 4 spawns/s, <= 4 despawns/s; spawn sweep every 0.25 s, not every physics tick.
- Determinism: RNG seeded from `hash(master_seed, cell_id, time_bucket_10s)`; tests can replay a drive and compare the spawn list.
- Fast travel / teleport: on `fast_travel_to` or large position jump (> 400 m) clear the ring and rebuild with a ramp-up over 3 s (avoids a wall of cars appearing at once).
- Event mode: keep `set_enabled(false)` seam used by `EventSession`; v1.1 replaces it with "clear lanes within 120 m of the event route" so traffic still exists elsewhere.

## 5. Vehicle pool, LOD tiers and physics

### 5.1 Options considered
| Option | CPU | Player interaction | Verdict |
|---|---|---|---|
| A. Keep full `VehiclePhysics` per car (today) | high: whole vehicle model per tick; shelving only trims the far ones | perfect | Reject for > 8 cars |
| B. Lightweight kinematic car (`AnimatableBody3D`/`Node3D` on the lane), RigidBody "crash" swap on contact | ~0.02-0.05 ms/car (est.) | AnimatableBody3D transmits estimated velocity to bodies in its path (Godot class docs), but acts like infinite mass => stiff hits; solve with swap | Recommended |
| C. Visual-only (no body), query by distance only | lowest | none: player drives through cars | Use only for the far tier |

Godot docs: AnimatableBody3D is moved by code, affects other bodies in its path, `sync_to_physics` defaults true and must not be combined with `move_and_collide()`
(https://docs.godotengine.org/en/stable/classes/class_animatablebody3d.html). Jolt makes moving kinematic bodies cheap relative to dynamic vehicle rigs; measure before trusting.

### 5.2 `TrafficCar` (pooled)
- Scene: `scenes/world/traffic_car.tscn` = `AnimatableBody3D` (layer 4 Traffic, mask 1 Vehicles) + box `CollisionShape3D` (size from model AABB) + `Model` (shared Mesh resources) + 4 wheel nodes (near tier only) + lights node (emissive material params, no `OmniLight` except the nearest 4 at night).
- Pool: preallocate `cap + 4` cars at world start; "spawn" = activate (position, visible, collision on); "despawn" = deactivate (hide, collision off, return to pool). No `instantiate`/`queue_free` at runtime => no GC spikes, no orphans.
- Tiers (by distance to player, hysteresis 10 m):
  - N (near, < 70 m, max 8): body enabled, wheels spin, brake lights, shadows on High, shared audio voice eligible.
  - M (mid, 70-250 m): body DISABLED (`collision_layer = 0`), single merged mesh (wheels baked), no shadows, position updated each tick (cheap) but without wheel/lights nodes.
  - F (far, 250-330 m): hidden or MultiMesh-only (Stage B), simulated at 10 Hz.
- Stage B (optional, when cap > 40): per-model `MultiMesh` for tiers M/F with `visible_instance_count` and `use_colors` for paint; per Godot docs MultiMesh is one draw call but has no per-instance culling (all-or-none), so partition by 256 m cell or limit to F tier
  (https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html). Do not read instance transforms back (4.7.2 defect, see status doc); keep own arrays.
- Draw budget: 8 near x ~8 draws + 20 mid x ~2 = ~100 draws, shared materials. Wheels/lights only on near cars is what keeps this under budget.

### 5.3 Crash mode (`CrashPool`)
When the player's car contacts a traffic body (or predicted contact < 0.15 s with closing speed > 15 km/h, from the manager's own check, because Area3D enter events lag):
swap that car for a pooled `RigidBody3D` (box shape, mass ~1300 kg, layer 4, mask 1|2|3, linear damp) at the same transform with the car's current velocity;
apply the player's impulse naturally; play impact sound; after 6 s (or when > 120 m away) fade and return it to the traffic pool, which respawns it elsewhere.
Pool of 4 crash bodies; if exhausted, the oldest is recycled. Damage/rewards/penalties: none in v1 (Horizon style).

## 6. Speed, following and brake logic

### 6.1 State per car
`lane_id, s (m along lane), v (m/s), lateral_offset (m, default 0, smoothed), desired_speed v0, vehicle_type, IDM params, state {CRUISE, FOLLOW, YIELD, EMERGENCY, CRASHED}`.
Position = `lane.sample(s) + right * lateral_offset`; heading from the lane tangent (smoothed, banked frame). Updated by the manager in a single loop at the physics tick (60 Hz for tier N, 20-30 Hz for tier M, 10 Hz for F).

### 6.2 Longitudinal: Intelligent Driver Model (IDM)
`a = a_max * [1 - (v/v0)^4 - (s*/gap)^2]`, `s* = s0 + v*T + v*dv / (2*sqrt(a_max*b))`
(Treiber IDM; MOBIL for lane changes; reference implementation: highway-env `IDMVehicle`, https://highway-env.farama.org/main/dynamics/vehicle/behavior/).
Defaults: `s0 = 2.5 m`, `T = 1.2-1.8 s` (per car), `a_max = 1.5-2.5 m/s2`, `b = 2.5 m/s2`; `v0 = speed_limit * U(0.85, 1.05)`; trucks `a_max 1.0`, `v0 x 0.85`.
Gap/leader = nearest car ahead in the same lane within 100 m (per-lane array kept sorted by `s`; insertion O(n) is fine for < 40 cars), connectors included through `next_lane` look-ahead.

### 6.3 Player as leader
The player is a virtual vehicle projected onto the lane graph each tick (`nearest_lane` within lane half-width + 1.5 m, using position + velocity heading).
If the player lies ahead in the lane: IDM leader with the player's actual speed and a bumper-to-bumper gap (use both AABB half-lengths).
If the player is behind and faster, traffic does not yield (no pull-over in v1).

### 6.4 Curves, junctions and speed limits
- Precompute per lane point `v_curve = sqrt(a_lat_max / max(kappa, eps))` with `a_lat_max = 3.0 m/s2` comfort (touge hairpins ~25-35 km/h), then a backward pass so braking distance is honoured (`v_i <= sqrt(v_{i+1}^2 + 2*b*ds)`).
  The car's target speed = `min(v0, v_curve_lookahead)`; replaces the steer-magnitude hack in `TrafficDriver`.
- Junction connectors: speed cap 30-40 km/h inside; no yielding simulation (agreed). To avoid pass-through collisions the manager rejects a connector entry if another car is within 8 m of the connector start on a conflicting connector (simple reservation set keyed by junction id, released on exit). Worst case a car waits <= 4 s then proceeds (ghost) -- acceptable per scope.
- Ramps: join the highway lane only if the target lane has a gap >= 25 m ahead and >= 15 m behind (else slow to merge-end speed).

### 6.5 Lane changes (v1.1, highway/arterial 2+ lane roads only)
MOBIL-lite: change when the current leader is > 15 km/h slower and the target-lane gap is >= 25 m ahead / >= 15 m behind, with a 10 s cooldown;
lateral blend over 2.5 s smoothstep; abort if a car enters the target gap. No lane changes in curves with curvature above a threshold or on ramps.

### 6.6 Variance so traffic does not look cloned
Per-car `v0` factor, following time T, small lateral wander (+-0.25 m low-frequency noise), occasional slow drivers (5%) and fast drivers (5%), trucks slower, taxis in towns, parked cars (existing `parked_ratio` seam) at lane edges on town streets.

## 7. Player avoidance and feel

1. Brake for player ahead via IDM (6.3); emergency decel 8 m/s2 when TTC < 1.5 s (brake lights on, ABS-less sliding not modelled).
2. Oncoming nudge: if the player is in an oncoming lane (wrong side) on a collision course (TTC < 3 s and lateral separation < 2.2 m), offset toward the verge up to 1.5 m, return when clear. This is the single most "alive" behaviour for little code and keeps free-roam drivers from head-on contacts.
3. Honk (short audio) on near miss (< 1 m lateral at > 60 km/h closing) with a 6 s cooldown per car.
4. Cars must never block fast travel / start-of-event positions: manager exposes `clear_area(center, radius)`.
5. Never spawn on top of the player or a stopped player within 40 m ahead of the camera.

## 8. Vehicle variety

- Source: CC0 Kenney Car Kit already in the repo (`assets/cars/cc0/kenney_car-kit/Models`): sedan, sedan-sports, hatchback-sports, suv, suv-luxury, van, delivery, delivery-flat, truck, truck-flat, taxi, garbage-truck (+ ambulance/firetruck as rare, police excluded in v1).
  Existing player-grade CC0 cars (`cc0_sedan_sports`, `cc0_hatchback_sports`, `rally_hatch`, `muscle_car` with `.tres` configs) can be mixed in at low weight.
- Spawn weights by context (sum 1.0): highway sedan 0.30 / suv 0.2 / hatch 0.15 / truck 0.15 / van 0.1 / luxury 0.1; town sedan/taxi/hatch/delivery/van; touge sports cars + hatch.
- Paint: ~10 neutral-biased palette entries applied as `material_override` params (or `INSTANCE_CUSTOM` in Stage B), plus 5% saturated.
- `scripts/world/traffic_model_catalog.gd`: id -> mesh path, AABB (auto-measured at pool build), mass, v0 factor, wheel node names (`CarVisuals.WHEEL_GROUPS` convention), light node names, audio class.
- Open check: Kenney model forward axis and origin vs the project's "nose +Z" contract; normalise in the catalog (rotation + origin offset), not in the GLBs.

## 9. Performance caps and budgets (GTX 970, 1080p)

| Quality | Live cars cap | Near (tier N) | Spawn rate | Traffic CPU (main thread) | Physics |
|---|---|---|---|---|---|
| Low | 14 | 4 | 2/s | <= 0.8 ms | <= 0.3 ms |
| Medium | 24 | 8 | 4/s | <= 1.2 ms | <= 0.5 ms |
| High | 36 | 10 | 4/s | <= 2.0 ms | <= 0.8 ms |

Total traffic budget at Medium: <= 1.7 ms CPU, <= 100 draws, <= 120k prims (Kenney meshes are ~1-3k tris), <= 60 MB VRAM. Today 8 full-physics cars cost ~half of the ~12 ms physics tick (derived from the 42% at 15 cars figure).
Hard guard: manager measures its own tick time (`Time.get_ticks_usec`) and halves spawn rate / drops tier-N count when the 95th percentile exceeds the budget for 2 s.
Quality hook: `GameState`/settings ladder sets the cap; add keys to `settings_menu.gd` presets (existing tests must be extended, not rewritten).

## 10. Audio

- Remove `EngineAudio` from traffic cars. `TrafficAudio` keeps a pool of 6 `AudioStreamPlayer3D` voices assigned each 0.25 s to the nearest cars inside 70 m: engine loop pitch/volume from `v` and acceleration, road noise above 40 km/h, Doppler tracking on, pass-by whoosh (relative speed > 30 km/h within 6 m), horn one-shots.
- Trucks use a lower engine bed; reuse existing sound assets (`assets/audio`) and `EngineAudio` bed logic only as a data source. Budget: <= 6 voices, <= 0.2 ms.

## 11. Integration points

- `LivingWorld._physics_process` keeps ticking `traffic.update(player_pos, delta)`; `TrafficManager` keeps the old public surface (`update`, `set_enabled`, `is_enabled`, `sync_headlights`, `max_traffic`, `spawn_radius`, `vehicle_scene`) so `WorldDriver._sync_night_lights`, `RegionDresser` (calls `traffic_spawner.update`) and the scene keep working while `TrafficSpawner` becomes a facade or is renamed in one commit.
- `WorldDriver._bootstrap_roads` builds the `LaneGraph` right after `network.recompute_rails()`; `RoadNetwork` emits "roads changed" so the graph rebuilds if corridors change.
- `WeatherManager` / `DayNightDriver`: density multipliers, headlights at night (`Headlights.set_night`), spray/wet handling not needed in v1.
- `EventSession`/`RaceManager`: pause or clear traffic near event routes. `GameState` race rivals are separate (`rival_driver`); never mix rival cars into the traffic list.
- Map: optional traffic blips off by default (no minimap clutter); debug overlay draws lanes + car states behind a debug key.
- Terrain streaming: spawns require the lane's region to be live (`TerrainSeeder` ring) or a ground-height cache hit; if not, delay the spawn (kinematic cars read Y from the lane polyline, so they do not fall through unbaked ground, but visible cars over missing ground look wrong).

## 12. Testing

Pure (GDUnit, no scene):
1. `test_lane_graph.gd`: lane count per tier, lane offset = expected +-w/4 and inside road bounds at every sample; right/left-hand side correct; reverse lanes are reversed arrays; every lane has a successor (connector or loop) except explicitly closed tiers; connector endpoints within 0.5 m of lane ends; graph build deterministic (hash of arrays equal across runs); build time < 0.5 s for the current 19 roads.
2. `test_idm.gd`: free-road speed converges to `v0`; follower never overlaps leader in a 10-minute simulation of 20 cars on a closed loop; leader hard-brake => follower stops with gap >= `s0 - 0.5`; curve speed profile obeys `b`.
3. `test_traffic_spawn_planner.gd`: spawn points lie in the annulus, on a live lane, outside the frustum cone and >= 14 m from neighbours; despawn hysteresis; same seed => same spawn list; teleport clears and ramps up.
4. `test_traffic_pool.gd`: 1000 spawn/despawn cycles => node count, orphan count and RID count flat; tiers switch with distance; crash pool recycles.
5. `test_traffic_player.gd`: scripted player parked in a lane => followers stop at a safe gap; oncoming player in wrong lane => nudge offset > 0.5 m; TTC emergency triggers; crash swap preserves velocity.
Integration (scene, headless-safe):
6. Open-world scene run, player scripted at 100 km/h for 3 simulated minutes: no `ERROR`, live count <= cap, tier-N <= 8, traffic tick p95 under budget, no car off-lane (distance to lane polyline < 0.5 m, excluding crashed).
7. Migrate existing suites deliberately: `test_traffic_spawner.gd`, `test_traffic_driving.gd`, `test_open_world_hud.gd::test_traffic_...` (bounds: `max_traffic <= 15` and `spawn_radius <= 300` become cap-per-quality and ring params).
Perf and visual:
8. `tools/perf_probe.gd` with traffic off vs on (A/B), Low/Medium/High; `hitch_probe` while spawning; budgets in section 9.
9. Capture strips (highway, touge, town, junction, night, rain); I open each image and critique (no Ollama/Gemini); a debug lane overlay capture for correctness.

## 13. Phasing and effort (person-weeks, 1 dev + agents)

| Step | Deliverable | Effort |
|---|---|---|
| T-1 stopgap (1-2 days, optional) | Spawn outside frustum and on the correct side of centreline (+-w/4), model variety via existing CC0 `CarConfig`s, tighter spawn gap, pool reuse of `VehiclePhysics` | 0.3 pw |
| T0 | `LaneGraph` + tests (+ centre-line paint in `TrackBuilder`) | 1.5 |
| T1 | `TrafficManager`, `TrafficCar` pool/tiers, IDM follower, spawn planner, facade for old API | 2.0 |
| T2 | Catalog + Kenney variety + paint, lights, shared audio | 1.0 |
| T3 | Player awareness (leader projection, TTC, oncoming nudge) + crash pool | 1.0 |
| T4 | Junction connectors/reservations, ramps, lane changes, event clearing | 1.0 |
| T5 (optional) | MultiMesh far tier, cap 40-60 | 1.0 |
Total 6.5-7.5 pw for v1; T0-T3 (~5.5 pw) is already a convincing "roads are alive" result.

## 14. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Kinematic car vs RigidBody player feels like hitting a wall | Bad feel | Crash swap (5.3), predicted contact, tune masses; spike early in T1 |
| Unpainted/no-centre-line roads make lane sides look wrong | Looks off | Paint centre line (Phase 2.4) or choose offsets that match edge lines |
| Junction overlap geometry today is raw overlaps | Cars cross at odd angles | Connectors + reservations; full junction meshes in Phase 2 |
| Cars floating/sinking where roads sit on conformed terrain | Visual bugs | Use lane polyline Y (banked frame) and not terrain height; test drift < 0.1 m |
| Spawn pops visible | Immersion | Frustum rule, 3 s ramp, fade-in alpha on tier M |
| CPU budget regression with many cars | FPS | Tier system, self-profiling guard, caps per quality |
| Test churn on pinned traffic assertions | Time | Keep facade API; update tests with explicit intent |
| Driving-side mismatch with road art/cockpit | Rework | Constant + single decision up front |
| 4.7.2 MultiMesh read-back defect | Hidden bugs | Own transform arrays; never read from MultiMesh |
| Pooled bodies and Jolt `freeze`/collision toggling hitches | Stutter | Toggle `collision_layer`, not tree membership; benchmark in T1 |

## 15. Open questions

1. Driving side (left for a Japan theme, or right)? Also whether to add centre-line paint to 1-lane roads in Phase 2 or offset cars by +-w/4 without paint first.
2. Should traffic run during events/races (v1.1 route clearing) or stay paused as today?
3. Is the Kenney CC0 civilian set acceptable visually, or do we want JDM-flavoured civilians (kei cars, vans) authored in Blender (cost ~1-2 days per car with the existing pipeline)?
4. Max acceptable "crash" feedback: purely physical shove, or add damage/score penalty/"outbreak" interactions later?
5. Do rivals/race AI ever share lanes with traffic (events on the open-world network)? That decides whether rivals need the same lane graph.
6. Tolerance for the junction "ghost pass-through" simplification once junction geometry exists.
7. Do we want traffic blips and a "traffic density" setting in the options menu?

## 16. Sources

- Godot AnimatableBody3D: https://docs.godotengine.org/en/stable/classes/class_animatablebody3d.html
- Godot MultiMesh performance and `visible_instance_count`: https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html
- Godot large world coordinates (precision limits that affect traffic positions far from origin): https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html
- IDM / MOBIL reference implementation (highway-env): https://highway-env.farama.org/main/dynamics/vehicle/behavior/ ; Treiber & Kesting open-source microscopic simulator: https://arxiv.org/pdf/1012.4913
- Godot forum discussion on moving many NPCs with kinematic vs RigidBody (anecdotal): https://forum.godotengine.org/t/rigidbody-3d-movement-is-slow-and-inconsistent/128931
- Godot open-world racing project using collision layers for surfaces (pattern reference): https://forum.godotengine.org/t/3d-open-world-racing-game-godot-4-4-4-6/120192
- FH ambient traffic observations (anecdotal, no developer documentation found): https://www.gtplanet.net/forum/threads/forza-horizon-5-general-discussion.399481/post-13521556
