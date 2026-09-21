# UltraDrive — Match FH6 + GT7 (Phase-Gap Execution Plan)

Purpose: close the measurable gaps between UltraDrive today and a "FH6 + GT7 feel"
target. Every work item follows the house plan style below (Goal / Today vs Target /
Work / **Acceptance test gate** / Effort / Depends-on / Quick-win) plus a **Sub-agent**
delegation brief (§ Sub-agent execution playbook). All gates run via the AGENTS.md
headless recipe; nothing ships without its suite green.

Sources: `docs/research/feature_comparison.md` (gap tables P0/P1/P2),
`docs/research/fh6_features.md`, `docs/research/gt7_features.md`, `docs/ROADMAP.md`
("no tech ceiling"), `docs/plans/open_world_seeding_plan.md`, `docs/plans/cc0_car_assets_plan.md`.

> **Integrated 2026-09-19:** absorbed `docs/plans/html_prototype_lessons_plan.md`
> (analysis of the FH6-inspired single-HTML prototype spec, `message.txt`) — the race
> ceremony, drive-feel presentation, living-traffic, hardening and perf-hygiene items
> are now items 1–3, 6, 8–10, 12[appendix], 16 below. The standalone html lessons file
> stays in the repo as provenance. Meta-lesson it supplies: nearly all of a Forza
> *feel* is presentation closure over state UltraDrive already emits (drift flag,
> surface key, standings, speed) — so those items are cheap **readers**, not new
> simulation. Existing items are renumbered (old → new): old 1→4, 2→5, 3→7, 4→11,
> 5→12, 6→13, 7→15, 8→16, 9→17.

## Baseline

- **266 tests green today** (`/c:"Overall Summary:" _gdunit.txt` — AGENTS.md's "263"
  line is stale; the runner output is truth). Target: **≥ 400** with **0 errors / 0 failures / 0 flaky**.
- Roads: hub ring + connector + pass loop + highway/touge/coastal/dirt corridors,
  seeded via `CorridorPlanner.MASTER_SEED` (~10 km of classified roads). Target: **≥ 60 km**.
- Cars: 3 AI-scripted glbs + Kenney CC0 kit integrated. Target: **≥ 10 drivable cars**.
- Quality ladder: 3 presets (Low/Med/High) with FSR2 at High 0.9. No perf gate.
- Probes: 2 static + 1 per-car UPDATE_ALWAYS = 3, under the documented 4-probe blend cap.
- **Feel signals already emitted (the prototype's trick, reused by items 1–3, 8–9):**
  `get_drive_info()` speed/gear/rpm/brake/steer/surface (`scripts/vehicle/vehicle_physics.gd:182-196`),
  `DriftScorer` (scored, **not wired to UI**), `SurfaceRegistry` 6-state classify,
  `RaceManager` standings (lap→checkpoint→distance), `LapCounter` per-lap/race times.
- **Confirmed empty (targets of the ceremony + feel items):** no countdown, no results
  screen (FINISH banner only), no session stats, zero particle nodes in the repo, no
  body pitch/roll rig, no hood cam, no tire marks, no speed vignette, traffic spawns
  **but never drives**, no nitro.

---

## Phase A — Close the core loop: ceremony → GPS → rivals/traffic → events → feel (P0)

### 1. Race pre-countdown + start-gate ("3…2…1…GO!")

- **Goal:** Every race starts with a controls-locked countdown: big "3 / 2 / 1 / GO!"
  HUD sequence with per-phase beeps and a GO flare, engine-rev anticipation while
  locked, then controls release — for circuit races now and free-roam events once
  item 7 raises them.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Race start | `race_ui.gd:20-23` starts the race on its first frame. No countdown | `RaceManager` ceremony gate; copy of race fully armed but player input clamped |
  | HUD | Position/Lap/Time labels only | `%CountdownOverlay` in `hud.tscn` — "3…2…1…GO!" |
  | Control lock | `VehiclePhysics` reads `InputManager` unconditionally (`vehicle_physics.gd:76-81`) | gate on `RaceManager.controls_locked()`; stores hold neutral |
  | Rev anticipation | none | drivetrain rpm blips toward redline during lock (reuse `Drivetrain.engine_rpm` path) |
  | Audio | engine beds only (`CarAudio`) | procedural per-phase beeps + higher GO beep (mirror prototype §12 beeps) |
  | Reuse | n/a | `RaceManager.request_race(laps)` seam callable by any start source (future events) |

- **Work** (S1):
  1. `scripts/race/race_countdown.gd` (new, `class_name RaceCountdown`, RefCounted —
     pure, headless-testable): `start()`, `advance(delta)` returns phase
     `"3"/"2"/"1"/"GO"/"RACE"`, `controls_locked()`, `rev_rpm_override() -> float`,
     `progress()`.
  2. `autoload/race_manager.gd`: `controls_locked()` + ceremony state hooks;
     `race_ui.gd` drives the overlay phases from the RefCounted in `_process`.
  3. `scripts/vehicle/vehicle_physics.gd`: when `controls_locked()`, zero inputs and
     feed `rev_rpm_override()` into `_drivetrain`. Small, single site.
  4. `scenes/ui/hud.tscn`: `%CountdownOverlay` + `%Banner` nodes; GO flare pulse.
  5. Optional audio: `scripts/race/countdown_audio.gd` (new, procedural blips, guarded headless).
- **Acceptance test gate:** `tests/suites/test_race_countdown.gd` — phases advance in
  order with deterministic delta timing; `controls_locked()` true until GO, false
  after; rev override follows phase (0 then climb); HUD label text equals the phase in
  order (scene_runner on `hud.tscn`); reuses `test_race_loop.gd` after_free discipline.
- **Effort:** S • **Depends-on:** D6 race loop (done). • **Quick-win:** the RefCounted
  + one overlay is already "a real race start".
- **Sub-agent:** one `general` sub agent per this item, handed this Goal + Today/Target
  + Work + gate **verbatim** plus the playbook guardrails. Expect return: files touched,
  `test_race_countdown.gd` name, GDUnit headless summary — then the parent re-runs the
  AGENTS.md recipe itself before shipping.

### 2. Race results screen + celebration

- **Goal:** A real results screen replacing the FINISH banner: finishing position,
  total time, best-lap, session-stats card, and a win/celebration state (confetti +
  gold "1st PLACE!") vs a flat also-ran state, with "Next Race / Return to Free Roam".
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Finish | `_on_race_finished` flips PositionLabel to "FINISH %.2fs" (`race_ui.gd:43-52`) | `%ResultsOverlay` panel; clear + dismiss via buttons |
  | Best lap | `LapCounter` per-lap times exist; best-lap not tracked | best-lap from `lap_completed` (item 3 owns it) |
  | Win state | none | 1st ⇒ confetti + gold glow; else neutral |
  | Exit | scene flow only | "Next Race" (re-arm ceremony) + "Return to Free Roam" (GameState scene nav) |
  | Grade socket | none | position/points → item 11 economy award stub |

- **Work** (S2):
  1. `scenes/ui/hud.tscn`: `%ResultsOverlay` (position, total time, best lap, per-item
     stats rows, buttons).
  2. `scripts/race/race_ui.gd`: `_on_race_finished` shows overlay fed by standings +
     `SessionStats` (item 3); `_on_next_race` / `_on_return_free_roam` handlers.
  3. `scripts/race/results_confetti.gd` (new, CanvasItem draw — plain 2D conic squares,
     no GPU particles, headless-safe): fade/fall over ~3 s.
  4. Position→points table constant (1st 1000…4th 250 per prototype §20), exported for item 11.
- **Acceptance test gate:** `tests/suites/test_race_results.gd` — overlay shows exactly
  standings[0]=winner, total = `get_total_time()`, best lap from SessionStats; win
  state true only for position 1; confetti tween completes without scene; buttons emit
  the right GameState transitions; no leaks.
- **Effort:** S • **Depends-on:** item 1, item 3 (stats card). • **Quick-win:** even a
  simple "P1 · 1:23.4 · BEST 1:22.1" card reads complete.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook
  guardrails. Expected return and parent re-verification as item 1.

### 3. Session stats tracker

- **Goal:** A pure `SessionStats` that accumulates distance driven, top speed, max G,
  drift time, clean-lap + best-lap flags across free-roam and races; surfaced on the
  results screen and pause menu; emits S-grade inputs to item 11.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Accumulator | none | `SessionStats` RefCounted (autoload-adjacent) accumulates via `tick(delta, speed_kmh, max_g, drifting)` |
  | Drift time | `DriftScorer` tracks internal `_drift_time` (`drift_scorer.gd:19`) but exposes only score | expose drift time; SessionStats mirrors it |
  | Clean lap | none (no collision signal to build from) | clean-lap flag from item 8's `impact` signal + `LapCounter.lap_completed` |
  | Best lap | `LapCounter.get_lap_time()` per lap only | global best-lap across session |
  | Surface | — | on pause menu (`pause_menu.gd`) + results screen (item 2) |
  | Feeds | — | item 11 S-grade + item 17 leaderboards |

- **Work** (S3):
  1. `scripts/race/session_stats.gd` (new, `class_name SessionStats`, RefCounted —
     pure logic, **no frames**): `tick()`, `start_lap()` / `end_lap(clean)`, getters,
     `reset()`; monotonic invariants.
  2. `race_ui.gd` calls `tick()` each frame from `get_drive_info()`; free-roam path
     calls `tick()` from `VehicleManager.get_player_car()`.
  3. `pause_menu.gd` stats panel (SessionStats readout).
  4. `DriftScorer` exposes `get_drift_time()` for parity.
- **Acceptance test gate:** `tests/suites/test_session_stats.gd` — pure math (no
  scene): distance monotonic, top-speed max, max-G clamp, drift-time sums, clean-lap
  only when zero impacts in the lap, best-lap min, `reset()` zeroes; determinism
  across identical tick sequences.
- **Effort:** S • **Depends-on:** item 8's `impact` signal (clean-lap input); otherwise
  standalone. • **Quick-win:** a pause-menu "Today: 3.2 km · 182 top" card instantly
  makes drivers feel a session. *(Match note: clean-lap/drift bonuses feed economy —
  item 11; do not build rewards here.)*
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook
  guardrails. Expected return and parent re-verification as item 1.

### 4. GPS route line + in-world drive assist

- **Goal:** A player-set destination draws an on-road route, the minimap/pause-map
  agree on it, and a "RACE line" assist (brake/turn hints) makes point-A→B driving
  feel like a Horizon event route.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Route state | `MapRoads` static `route_target/has_route/set_route/clear_route/route_polyline` | Same API, plus per-frame snap-to-route for the HUD |
  | Who can set it | `WorldMap.set_route_destination()` only from pause-map | Driver HUD "Set GPS" + POI/event "Navigate to" |
  | Render | Route polyline on pause map (`world_map.gd` ROUTE_COLOR) | Same + minimap route path + in-world ribbon on road surface |
  | Assist | none | Turn-distance arrows + brake/turn intensity (brake line) |
  | Fast travel | works on revealed roads (`WorldDriver.fast_travel_to`) | unchanged |

- **Work** (S4):
  1. `scripts/route/route_planner.gd` (RefCounted) — `snap(player_pos) -> {road_id, dist, arc}` for HUD reads.
  2. Extend `MapRoads` with `minimap_route_path(rect)` so `scripts/ui/minimap.gd` draws the same polyline as `world_map.gd`.
  3. `scripts/route/brake_line.gd` — curvature probe along the route ahead (0–120 m) → {hint: none/brake/hard-brake, arrow: left/right/straight}.
  4. HUD cluster (`race_ui.gd`) nav widget: next turn arrow + distance + assist intensity. Wired behind `GameState` feature flag.
  5. "Navigate to event/POI" from event cards (ties into item 7).
- **Acceptance test gate:** `tests/suites/test_gps_route_follow.gd` — route polyline agreement across world_map/minimap; brake-line hints decay and flip correctly on a closed loop; snap-to-route is monotonic; fast-travel still gated on `is_revealed`.
- **Effort:** M (~1 sprint) • **Depends-on:** none • **Quick-win:** the HUD widget alone is already "GPS exists".
- **Why here:** ceremony (items 1–3) ships first — GPS was the previous "lowest cost, highest daily feel" pick, and the countdown/results bundle now completes the perceived core loop with zero deps before the map-feel work starts.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails. Expected return and parent re-verification as item 1.

### 5. Race-rival AI (no-rubber-band, skill tiers)

- **Goal:** Rivals that follow a racing line at class-appropriate pace with per-driver
  skill, so races feel contested and passing matters — while the player is freed from
  the rubber-band assist that undermines that feel.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Driver | `AIController` (waypoint following) + `ai_rubber_banding.gd` BASE_GAP speed knob | Line-follow rivals using the racing line; rubber-band OFF on the player |
  | Traffic | `TrafficSpawner` spawns cars **without** drivers | Keep + opt-in "ambient traffic AI" mode (item 6 supplies the drivers) |
  | Pace | single speed multiplier | 3 skill tiers (Novice/Skilled/Expert) + car-class pace bands |
  | Line | `AIController._waypoints` (hand-authored) | Racing line derived from `TrackBuilder`/`RoadNetwork` centerline (apex sampling) |
  | Behavior | gap catch-up only | pass defense only `AHEAD`, brake-late/or range per tier, no wall-collision rubber band |

- **Work** (S5):
  1. `scripts/ai/racing_line.gd` (RefCounted) — resample road centerline per `CarConfig.car_class` into apex-shifted racing line.
  2. `scripts/ai/rival_driver.gd` — extends AIController; consumes racing_line + skill tier; drives via existing `input_override`.
  3. Keep `ai_rubber_banding.gd` for **traffic** and **low-tier** rivals only; add `GameState.rubber_band_assist` (default ON) that scales the multiplier **for rivals never for the player**.
  4. `RaceManager.start_race()` spawns configured rival roster (grid order, car_config), not just `VehicleManager.get_all_cars()`.
  5. Standings already tie-break lap→checkpoint→distance; keep, but exclude rubber-band from pace calc.
- **Acceptance test gate:** `tests/suites/test_rival_ai.gd` — line finite + smooth; tier paces strictly ordered; rubber-band multiplier never applies to the player; roster starts/stands consistent with `get_standings()`; headless, no leaked nodes (mirror `test_race_loop.gd` leak discipline).
- **Effort:** L (~2 sprints) • **Depends-on:** checkpoint/lap systems (D6 race loop, done).
- **Why here:** races are the "FUN" files; rival feel is the GT7 ask. Shares the `input_override` driving seam with item 6.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails. Expected return and parent re-verification as item 1.

### 6. Living traffic: driving behaviors (the prototype's "world is alive" win)

- **Goal:** Spawned traffic actually drives: curve-follow on `RoadNetwork` chains via
  the `input_override` seam, player-proximity slow/stop + avoid, parked cars,
  stuck-teleport rescue, intersection branch picks through the road graph — keeping
  the spawn/despawn ring and headless safety.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Driving | `TrafficSpawner` spawns `VehiclePhysics` cars; **nothing drives them** (`traffic_spawner.gd:48-51`) | per-vehicle `TrafficDriver`: waypoints from nearest road chain + `input_override` (AIController seam, `ai_controller.gd:53`) |
  | Route source | n/a | `RoadNetwork.get_nearest_road_pos` / chains + `RoadGraph` junction branching at intersections |
  | Player avoid | none | within ~10 m ahead slow, ~5 m stop; resume after gap |
  | Parked | none | spawner `parked_mode` flag → still cars in marked spots |
  | Stuck | none | no-movement 2 m / 5 s ⇒ teleport to random road point (prototype §8) |
  | Ring | `update()` despawns at `spawn_radius+100` + audio distance-cull (`traffic_spawner.gd:17,26`) | unchanged; staggered update turn (item 16) |

- **Work** (S6):
  1. `scripts/world/traffic_driver.gd` (new, `class_name TrafficDriver`, RefCounted per
     vehicle driven by the spawner): waypoints, speed (casual 10–20 u/s), smooth steer,
     branch-at-junction, avoid, parked, stuck rescue.
  2. `scripts/world/traffic_spawner.gd`: attach drivers on spawn; despawn frees drivers
     (no leaks); expose `update(player_pos, delta)`.
  3. `scripts/world/living_world.gd`: pass delta + stagger (item 16).
- **Acceptance test gate:** `tests/suites/test_traffic_driving.gd` (new — the existing
  `tests/test_traffic_spawner.gd` lives at `tests/` root, keep it): vehicles stay
  on-road within a tolerance across frames; avoid/slow fires only inside the band;
  parked cars never move; stuck rescue teleports to a road point once; despawn frees
  driver nodes (orphan count ≤ baseline).
- **Effort:** L • **Depends-on:** RoadNetwork/RoadDef/RoadGraph (exist); `input_override`
  driving (exists via AIController). • **Quick-win:** even a 2-point "drive to next
  road point and stop" pass makes the hub feel alive; full route-follow is the polish tail.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook
  guardrails. Expected return and parent re-verification as item 1.

### 7. Event taxonomy → playable loop (place → objective → score → reward)

- **Goal:** The 6 event families become playable, countable sessions with a defined
  scoring objective and an emitted reward (credits banked in item 11's ledger).
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Taxonomy | `EventRegistry.place()` 6 families exist (touge_duel, drag_strip, drift_zone, night_street_loop, marathon_highway, time_attack_N) | Same 6 → **8 types** (add 2 open-world brand: outbreak/convoy) with `objective_type` + `finish` contract |
  | Markers | `POIRegistry._load_events` lazy-appends dots | + event cards with preview (best time, payouts) |
  | Start | none (placement only) | "Start event" → themed physics setup (drag: launch startlights; drift: DriftScorer; touge: head-to-head; marathon: checkpoint chain to finish); countdown via item 1's `request_race` seam |
  | Result | none | Score → grade (S/A/B/C) → `event_completed` signal → credits via item 11 |
  | Persistence | none | best time/score per event in save (`SAVE_KEY` area) |

- **Work** (S7):
  1. `scripts/events/event_def.gd` (Resource) — `{type, objective_type, checkpoints/PackedVector3Array, target_time, payout}`; `EventRegistry.place()` upgraded to return these.
  2. `scripts/race/drift_scorer.gd` reuse for drift_zone grade; `race_manager` reuse for time_attack/marathon.
  3. Start/end bridge in `open_world_root.tscn`: event mode pauses ambient traffic (`day_night_driver`/`living_world`/item 6 no-op), gates player to event bounds.
  4. Emit `event_completed(event_def, grade)` → item 11 ledger adds credits (stub `Money` object first for S7, real economy in item 11).
- **Acceptance test gate:** `tests/suites/test_event_rewards.gd` — every placed event is startable; each objective produces a grade; every grade emits exactly one credit award; ledger (even the S7 stub) balances to zero-sum across a full session.
- **Effort:** M (S7 econ stub) then L (S11 full) • **Depends-on:** item 4 (navigate-to), item 11 ledger stub.
- **Why here:** rewards make the open world matter; it is the bridge between items 4–6 and the economy (item 11).
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails. Expected return and parent re-verification as item 1.

### 8. Vehicle FX particles (drift smoke, off-road dust, collision sparks)

- **Goal:** A pooled `GPUParticles3D` layer on `player_car.tscn` (and a latch on
  traffic) driven **by existing state**: tire smoke when drifting, off-road dust when
  surface ≠ asphalt (`SurfaceRegistry` already classifies), collision sparks from a
  small `impact` signal, nitro flame behind a `has_nitro` hook. Strictly headless-culled.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Particles | **zero** in repo (grep empty; no GPU/CPU particle node) | `VehicleFX` node: pooled smoke/dust/sparks/flame emitters |
  | Drift signal | `DriftScorer` tracked but **not wired**; physics computes handbrake rear-grip (`vehicle_physics.gd:132-133`) | smoke emitter reads drift state (DriftScorer or lateral slip) |
  | Dust signal | `get_surface_key()` / `resolve_surface_factors()` exists (`vehicle_physics.gd:205-225`) | surface path intended for GPUParticles dust |
  | Impact signal | none | `VehiclePhysics` gains `signal impact(strength)` via sharp deceleration delta (single site) — also feeds item 3 clean-lap |
  | Headless safety | renderer-guarded convention in quality ladder | no particle nodes when `DisplayServer.get_name() == "headless"` |

- **Work** (S8):
  1. `scripts/vehicle/vehicle_fx.gd` (new, `class_name VehicleFX`, Node on
     `player_car.tscn` + traffic-instance slot): pre-built GPUParticles3D children
     (smoke, dust, sparks, flame-slot), budget cap, `_ready` headless-cull, pooled
     (never instantiate at runtime).
  2. `scripts/vehicle/vehicle_physics.gd`: tiny `impact` signal (velocity delta spike)
     — feeds sparks + item 3 clean-lap.
  3. Wire drift → smoke, surface != ASPHALT → dust, impact → sparks.
- **Acceptance test gate:** `tests/suites/test_vehicle_fx.gd` — headless run: 0
  particle nodes instantiated; emitter budget & node-count caps respected;
  surface-driven dust only fires off-asphalt; impact threshold testable via a stub
  velocity delta; no leaks on free.
- **Effort:** M • **Depends-on:** DriftScorer wiring (no new physics) + SurfaceRegistry
  (exists). • **Quick-win:** drift smoke alone is the single largest "this is a racing
  game" frame. Mechanism is shared by item 12's rain particles.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook
  guardrails. Expected return and parent re-verification as item 1.

### 9. Drive feel presentation (visual suspension, speed vignette, tire marks, chase transients)

- **Goal:** Visual-only body pitch/roll on accel/brake/steer (independent additive rig
  on CarBody), a speed vignette/streak overlay, handbrake tire-mark skids, and
  `transients_enabled` presentation defaults ON for the player chase cam.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Body rig | CarBody is a static GLB child (`player_car.tscn:18`) | `BodyRig` Node3D on CarBody: bounded pitch/roll lerped from drive_info |
  | Chase presentation | `transients_enabled` **default OFF** (`chase_camera.gd:19`) | ON for player; speed look-ahead/FOV kick/lateral-g shake |
  | Speed vignette | none | `%SpeedOverlay` in `hud.tscn` — monotonic darkening + subtle streak layer |
  | Tire marks | none | `TireMarks` short-lived dark quads at rear wheels while handbrake held (~3 s fade, prototype §18) |
  | a11y | none | vignette/streak behind flags item 15 exposes |

- **Work** (S9):
  1. `scripts/vehicle/body_rig.gd` (new, Node3D on CarBody): pitch (−2° accel / +3°
     brake), roll (±2° steer), lerp factor ~0.1, hard-clamped; additive like chase transients.
  2. `scenes/vehicle/player_car.tscn`: `BodyRig` + `FXSlot`; `scenes/ui/hud.tscn` `%SpeedOverlay`.
  3. `scripts/ui/speed_overlay.gd` (new, Control draw) — vignette intensity = f(speed_kmh) monotonic.
  4. `scripts/vehicle/tire_marks.gd` (new, Node) — pooled short-lived quads; headless-culled.
  5. Chase `transients_enabled = true` by default for the player car (keep debug hooks for tests).
- **Acceptance test gate:** `tests/suites/test_drive_feel.gd` — body_rig angles within
  clamp bounds and settle toward rest; vignette opacity monotonic with speed; tire-marks
  spawn under handbrake and despawn within lifetime; chase default off→on toggle still
  passes `test_chase_camera.gd` (transient maths unchanged). This is the plan's **only
  default-behavior change**; everything else is additive.
- **Effort:** S–M • **Depends-on:** chase transients (exist). • **Quick-win:** the
  suspension rig alone is a "night-and-day" feel bump for a Node3D + lerp.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook
  guardrails. Expected return and parent re-verification as item 1.

---

## Phase B — Insurance, meta-systems, and depth (P1)

### 10. Racing-game hardening audit → test suite

- **Goal:** Encode the prototype's §21 bug-prevention list as GDUnit assertions; where
  a guard is genuinely missing, add it (small, surgical).
- **Today vs Target**

  | Guard | Today | Target |
  |---|---|---|
  | NaN + last-valid restore | `y < -20` respawn only (`vehicle_physics.gd:72-74`); **no `is_finite` guard, no last-valid store** | finite-check each frame; restore last-valid pos/speed (prototype §21-3) |
  | Speed clamping | reverse capped by drivetrain limiter (`drivetrain.gd:83-89`); **no top-speed clamp in arcade handling** | clamp speed ∈ [−reverseMax, topSpeed] in arcade path (§21-13) |
  | Steer-at-zero div-by-zero | steer path already division-free (`vehicle_physics.gd:89-91`) | regression assertion only |
  | Race state cleanup / re-entry | covered for lap counters (`test_race_loop.gd:130`); ceremony state reset when items 1–2 land | ceremony + results state fully reset on re-entry |
  | Start-action debounce | `queue_race` accepts any spam (`race_manager.gd:20`) | debounce start requests ~250 ms after ceremony |
  | Despawn memory disposal | `TrafficSpawner` `queue_free()`s vehicles; drivers (item 6) must not leak | assert freed nodes + orphan ≤ baseline |
  | Delta-time cap | engine clamps via physics ticks; no explicit `min(delta, 0.05)` | assert no NaN after an extreme delta spike |

- **Work** (S10): surgical edits to `scripts/vehicle/vehicle_physics.gd` (finite-guard
  + last-valid + speed clamp), `autoload/race_manager.gd` (debounce),
  `scripts/world/traffic_spawner.gd` (driver free, once item 6 ships). **Where the guard
  exists, only the test ships.**
- **Acceptance test gate:** `tests/suites/test_hardening.gd` — NaN injection → restore
  semantics; speed stays within bounds; steer-at-zero asserts; race re-entry leaves zero
  ceremony/counter residue; double start ignored; traffic despawn frees nodes; big-delta
  frame yields finite state.
- **Effort:** S • **Depends-on:** nothing (item 1/2/6 states if shipped). • **Quick-win:**
  the NaN + clamp saves a real playtest crash class for ~20 lines.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook
  guardrails. Expected return and parent re-verification as item 1.

### 11. Economy + license/championship unlock loops

- **Goal:** Credits + XP with license gating (`LicenseSystem`) and championship
  seasons (`Championship`) so races feed *something* and purchasing/tuning ripples.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Money | none | `Money` ledger (credits), persistent in slot save |
  | XP/level | none | `CareerProfile` (level, XP curve, perks) |
  | Licenses | `LicenseSystem` TIERS B/A/S/Race/Elite + `is_car_unlocked(class_index <= tier+1)` | + per-discipline tests (Circuit, Rally, Drift) with Bronze/Silver/Gold |
  | Championship | points + `complete_race` | + season calendar, carclass locks per series, podium rewards |
  | Garage buy | `Garage` owns `_owned_cars` | + buy/sell with price table; financing=N op |
  | Discovery | `SaveManager` slot 0 + DISCOVERY_KEY | profile split (item 17) keeps per-slot data |

- **Work** (S11):
  1. `scripts/career/money.gd` (RefCounted) + ledger hooks in `SaveManager`.
  2. `scripts/career/career_profile.gd` (level/XP/perks) persisted to slot; feeds `LicenseSystem` and `Championship`.
  3. Rework `Garage` buy/sell + price table (`car_config.tres` gains `price`); champion/elite gating on the garage door.
  4. Wire item 7 rewards + race finishes (incl. item 2 position→points) to ledger/XP.
- **Acceptance test gate:** `tests/suites/test_career_economy.gd` — ledger never
  negative; XP monotonic; license tier induces exactly the car-unlock set per
  `is_car_unlocked`; championship points → podium payouts consistent; save/load
  round-trips without data loss.
- **Effort:** L • **Depends-on:** item 7 (rewards in), item 13 later (spending outlet).
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook
  guardrails. Expected return and parent re-verification as item 1.

### 12. Weather VFX, night switch-over, and wet-road feel

- **Goal:** Weather *looks* like its state (rain particles/droplets, storm darkening,
  fog depth), night actually goes dark with headlights + street light pools, and wet
  roads read visually while the grip table keeps doing its physics job.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | State clock | `DayNightDriver` (2400 s day) + `WeatherManager` seasons/weather + ROAD_GRIP grip factor into `VehiclePhysics` | unchanged (already correct) |
  | Sun/light | `WorldDriver.apply_sun_transform` + `SunDriver` + 3 probes | + night switch: headlight energy/cone on player + rivals; street/dressing lights |
  | Wet looks | physics only | rain particle system + droplet/streak shader on windshield + darker/dimmer rim (wet asphalt tint) — reuses item 8's pooled GPU layer |
  | Storm/fog | enum + grip | volumetric fog scaled with storm/fog; reduced sun |
  | Audio | none per weather | ambience bed per weather + rain-on-car loops |

- **Work** (S12):
  1. `scripts/weather/wet_surface.gd` — viewport/post overlay driven by `WeatherManager.get_road_grip_factor()` (single source: grip=structure, shader=feel).
  2. `scripts/car/headlights.gd` — OmniLight/SpotLight on `player_car.tscn` + `open_world_root` light sphere per dressing band when `WeatherManager.is_night()`; `sun_direction` below horizon = night flag.
  3. Rain particles in `open_world_root.tscn` (GPU Particles) + windshield droplet ShaderMaterial only for chase-cam mode.
  4. Audio: `CarAudio`/Ambience nodes switched on weather event.
- **Acceptance test gate:** `tests/suites/test_weather_vfx.gd` — headlights toggle
  exactly on `is_night`; wet overlay intensity monotonic with grip factor;
  headless-safe (particles culled; no scene need); audio bus no-leak.
- **Effort:** L • **Depends-on:** none (state infra exists; item 8 FX mechanism).
- **Why this cadence:** the *rule set* already ships; this only attaches *feel* — highest
  polish-per-effort in P1.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook
  guardrails. Expected return and parent re-verification as item 1.

### 13. Garage depth (tuning, paintwork, stats)

- **Goal:** A GT garage meat-space: per-car tuning sliders that actually change
  `CarConfig`-driven physics, live stat readout, and paint/livery application.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Stock set | `Garage.new_from_save().get_active_car()`, STARTER_CARS | + buy/sell (item 11) |
  | Tuning | `CarConfig` fields exist (gears, final_drive_ratio, mass, torque, swing) but **UI-untouched** | sliders → cloned `CarConfig` variant persisted per car in garage; live stat line (0–100 per usage) |
  | Paint | `CarVisuals` PAINT_COLORS + CC0_WHEEL_COLOR | swatch picker → live `_apply_visual()` repaint + save |
  | Aircraft | none | dyno readout (torque/power curve) using config redline/ratios |
  | Visual swap | `PlayerCarController._apply_visual()` | already covers it — reuse for paint confirmation |

- **Work** (S13):
  1. `scripts/career/tuning_profile.gd` (RefCounted) — overrides dict over base `CarConfig`; `CarConfig` gains `with_overrides()` clone helper.
  2. `garage_ui.gd` — 3 tabs (Garage / Tune / Paint): sliders for gear_ratios, final_drive_ratio, mass_kg %; paint swatches via `CarVisuals`; dyno panel.
  3. Persist tuning+paint via `SaveManager` per car id in garage save block.
- **Acceptance test gate:** `tests/suites/test_garage_tuning.gd` — override clone
  satisfies 0.01-approx getter parity; sliders clamp to config bounds; paint id
  round-trips through save; `is_car_unlocked` gates non-owned paint/tune.
- **Effort:** L • **Depends-on:** item 11 (earning → buying → tuning loop).
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook
  guardrails. Expected return and parent re-verification as item 1.

### 14. Hood camera (optional, cheap kicker)

- **Goal:** Third camera mode — chase / close / hood — reusing chase follow maths with
  a FOV bump + light speed-based head bob; C-cycle wired.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Modes | chase + orbit only (`orbit_camera.gd` C-toggle, line 60) | chase / orbit / hood cycle |
  | Hood view | none | `hood_camera.gd` — rigid attach to body, FOV 70→75 bump, head bob amplitude×speed |

- **Work** (S14): `scripts/camera/hood_camera.gd` (new) extends chase follow maths; add
  to the mode toggle consumed by `player_car_controller.gd` / camera node wiring; FOV +
  bob assertion hooks (like chase's transients).
- **Acceptance test gate:** `tests/suites/test_hood_camera.gd` (following `test_chase_camera.gd`
  pattern) — transform stays on car hood; FOV bumps to the hood target; bob bounded;
  toggle cycles deterministically.
- **Effort:** S • **Depends-on:** chase follow (exists). • **Quick-win:** a hood
  FOV-only readout is 90% of the immersion.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails. Expected return and parent re-verification as item 1.

### 15. Accessibility & options depth

- **Goal:** Standard racer a11y floor + input depth: rebinding, steering/visual
  sensitivity, colorblind mode, assist toggles, per-quality perf knobs.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Quality | 3 presets + hardware default + FSR2 High | + per-knob override (SSAO/SSR/scale) post-preset |
  | Transmission | AUTO/MANUAL in settings | unchanged |
  | Rebind | hardcoded `InputManager` actions | rebind UI → `ProjectSettings`-agnostic `InputMap` overrides persisted |
  | Assists | none besides rubber-band switch (item 5 target) | `GameState.assists`: brake-line (item 4), rubber-band, camera shake (item 9 transients), auto-transmission toggle |
  | A11y | none | colorblind-safe palettes (for maps/brake-line/hint colors), camera height/distance sliders on chase cam; vignette/streak toggles (item 9) |
  | Audio | master volume only | SFX/music/voice bus sliders |

- **Work** (S15):
  1. `scripts/ui/options_menu.gd` (new scene) — keyboard/gamepad rebind + sensitivity sliders; persist in slot save.
  2. `GameState` assist flags documented, each with a `settings_menu.gd`/options mirror.
  3. Colorblind: `WorldMap`/`brake_line` palettes swap to deuteranopia-safe set when flag on.
- **Acceptance test gate:** `tests/suites/test_accessibility_options.gd` — rebind
  round-trips; assist flags actually change `VehiclePhysics`/`AIRubberBanding` outputs;
  palette swap covered (unit-level pure color math).
- **Effort:** M • **Depends-on:** item 4 (brake-line assist to toggle), item 9 (shake/vignette flags).
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails. Expected return and parent re-verification as item 1.

---

## Phase C — Scale, harden, and the P2 load-bearing floor (P2)

### 16. Performance bar + prototype perf-hygiene notes (GPU benchmark → auto preset + LOD ladder)

- **Goal:** `60 fps mid-range on its own preset` measured by CI, plus a runtime
  benchmark that picks the quality preset instead of first-boot heuristics — with the
  prototype's §15 budget list folded in as concrete hygiene notes.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Perf floor | no gate | headless frame-time budget gate on a reference scene (Low/Med/High all ≤16.7 ms avg) |
  | Auto preset | `default_quality_preset()` GPU-name heuristic | `scripts/bench/benchmark.gd` runs the reference scene 5 s → picks preset; name heuristic is the no-save fallback |
  | LOD | probe cap + dressing bands exist | + distance-based LOD on CC0 cars/rivals + dresser density already bound (done P7) |
  | Scaling | FSR2 High 0.9 | scale slider on every preset |

- **Work** (S16): benchmark harness (test-time pure pass; runtime path behind a flag),
  preset auto-apply feedback on first boot, frame-time gate in `tests/suites/test_perf_gate.gd`
  run headless with fixed time step — **plus these hygiene notes folded in (not a
  standalone project):**
  - **Stagger traffic updates** (item 6): rotate 3–4 `TrafficDriver` ticks per physics frame (prototype §15).
  - **Fake under-car shadow quads** for traffic (cheap dark plane, no shadowmap budget) instead of real casting.
  - **Shared materials:** already the norm (`prop_scatterer`/`foliage` MultiMesh reuse,
    `CarVisuals` surface clones) — extend to tires/skids/FX (items 8–9).
  - **LOD + draw-distance cull:** already in `region_dresser` (band density /
    `visible_instance_count`) — extend caps as density grows with FX + traffic.
  - **Budget rows:** reference scene ≤16.7 ms/avg on all presets, asserted in the gate.
- **Acceptance test gate:** `tests/suites/test_perf_gate.gd` — budget ≤16.7 ms avg;
  benchmark deterministically returns a preset; LOD switches never pop light/paint
  wrong-headless; traffic stagger + fake-shadow rows asserted via the gate + streaming suite.
- **Effort:** M • **Depends-on:** items 6/8 content exists for the hygiene rows.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails. Expected return and parent re-verification as item 1.

### 17. P1/P2 load-bearing parity sink (research-table items)

- **Goal:** Own the P2 table (feature_comparison) with a decision per row + where the
  shipped work lands. These are the "keeps the lights on and the promise honest" items.
- **Work** (S17, batch by depends):
  - **Save robustness + profile split** (P2-2): slot-per-profile, corruption-ratchet
    (`SaveManager` write-to-temp then rename), oversized/discovery multi-slot persistence. Gate `test_profile_slots.gd`.
  - **GPU benchmark → auto preset + LOD** (P2-3): shipped via item 16; mark done.
  - **Region-streamed dressing** (P2-4): already **done** (P7 dresser/bands, streaming suite) — mark done, add regression coverage wrapper.
  - **Monthly content cadence skeleton** (P2-5): a `ContentSchedule` (RefCounted) list
    of event/road packs loaded on boot; Season pass UI hook. Gate `test_content_cadence.gd`.
  - **Ghost/leaderboards** (P1-adjacent): lap-time ghost replay on `time_attack` (record
    input+positions, replay path) — item 3 stats feed lap records. Gate `test_ghost_replay.gd`.
  - **Collectibles/system** (P1-adjacent): "Merit badges" per event family collected from
    `POIRegistry`; cosmetic-only payout (paint unlocks). Gate `test_collectibles.gd`.
  - **Multiplayer (XL)**: explicitly deferred — documented as post-v1; roadmap keeps "no tech ceiling" note.
- **Acceptance test gate:** `tests/suites/test_parity_load_bearing.gd` — the P2 table
  becomes pass/fail booleans in a test (each row asserts its shipped shape), plus the
  four dedicated suites above.
- **Effort:** S17 = XL batched; individually M–L.
- **Sub-agent:** one `general` sub agent **per P1/P2 row** (each of the 5 active rows
  above is its own delegation with the playbook guardrails), plus one for the parity
  table test wrapper. Expected return and parent re-verification as item 1.

---

## Sub-agent execution playbook

Every work item above carries a **Sub-agent** brief; this playbook is the shared
contract for how one is run. One work item (or one P2 row, item 17) = one sub agent;
never bundle two gates into a single delegation.

**Prompt template (given by the parent):**
1. Paste the item's **Goal**, **Today vs Target** table, **Work**, and **Acceptance
   test gate** verbatim.
2. Constraint boilerplate: *"You are a coding sub agent for UltraDrive (Godot 4.7.2,
   GDUnit4). Project root `C:\Users\IMOE001\Desktop\Shaked Projects\UltraDrive\UltraDrive` (res://).
   Read `<files this item touches>` first and confirm the 'Today' claims; code ONLY this
   item — no adjacent features, no refactors beyond the named files. Do not touch
   `reports/`, do not run git operations, do not `git add`. Keep additions additive and
   headless-safe (`DisplayServer.get_name() == "headless"` culls for particles/FX). Name
   your suite exactly `tests/suites/<gate_name>.gd`. Follow the house style of sibling
   scripts (no comments unless asked, class_name + extends headers, `assert_that(...)`
   GDUnit idioms)."*
3. Verification instruction: *"Run the AGENTS.md headless recipe (import probe FIRST,
   then `-s res://addons/gdUnit4/bin/GdUnitCmdTool.gd` with `--ignoreHeadlessMode`
   AFTER the tool-script path; grep `Overall Summary:`). Use
   `C:\Godot\Godot_v4.7.2-stable_win64.exe` (AGENTS.md's `D:\` path is stale). Return:
   files changed, suite name + test count, headless summary line, JSON-safe list of
   residual risks."*

**Parent's duty after each sub agent:** re-run the headless recipe yourself on the
returned diff before shipping; confirm `git status --short` shows no `*.uid` noise and
no `reports/` writes; confirm the item's suite is green headless with `0 errors / 0
failures / 0 flaky`; tick the item off in STATUS.

**Failure rule:** if an item's submission fails its gate or leaks (orphan count above
baseline), re-delegate to the same sub-agent `task_id` for a fix pass rather than a new
agent — continuity beats fresh context for gate violations.

---

## Ordering rationale & sprint sequence

Rationale: **ceremony first, feel-second, loop-second, meta-system last.** Items 1–3
flip what the player perceives at the start/end of every race (countdown, results,
session stats) with zero dependencies — the prototype's proof that these are the
cheapest feel-per-line wins. Then the map/rival/event loop (4–7) plus the pure
presentation closures (8–9) — all *readers* of state the game already emits. Item 10 is
insurance that lands before deeper systems build on unguarded state. S11–S15 deepen
the incentives those loops created; S16–S17 harden and scale so the game stays honest
at #1 target spec. Quick wins sit at the front of every phase.

| Sprint | Item | Gate |
|---|---|---|
| S1 | 1 Race countdown + start-gate | `test_race_countdown` |
| S2 | 2 Results screen + celebration | `test_race_results` |
| S3 | 3 Session stats tracker | `test_session_stats` |
| S4 | 4 GPS route + brake-line assist | `test_gps_route_follow` |
| S5 | 5 Rival AI (line, tiers, no-rubber-band-on-player) | `test_rival_ai` |
| S6 | 6 Living traffic driving behaviors | `test_traffic_driving` |
| S7 | 7 Event loop → reward stub | `test_event_rewards` |
| S8 | 8 Vehicle FX particles | `test_vehicle_fx` |
| S9 | 9 Drive feel presentation | `test_drive_feel` |
| S10 | 10 Hardening audit → suite | `test_hardening` |
| S11 | 11 Economy + licenses + championships | `test_career_economy` |
| S12 | 12 Weather VFX + night + wet roads | `test_weather_vfx` |
| S13 | 13 Garage depth (tune/paint/dyno) | `test_garage_tuning` |
| S14 | 14 Hood camera (optional) | `test_hood_camera` |
| S15 | 15 Accessibility & options | `test_accessibility_options` |
| S16 | 16 Performance bar + perf hygiene | `test_perf_gate` |
| S17 | 17 P2 sink (profiles, cadence, ghosts, collectibles) | `test_parity_load_bearing` + sub-suites |

## Definition of "Match FH6 + GT7"

By the end of S17, all of these are true (each = a column in the parity table test):

- **≥ 10 drivable cars** in the garage (3 AI glbs + CC0 kit ≥ 7) with tune/paint.
- **≥ 60 km** of seeded roads; GPS route + brake-line over the whole graph; ≥ 8 event
  types playable with graded rewards.
- **Races feel like races**: 3-2-1-GO countdown with controls lock, results screen with
  celebration, session stats (distance/top/drift/clean/best-lap) on results + pause.
- **The world is alive**: traffic that actually drives (routes, avoid, parked, stuck
  rescue); drift smoke, off-road dust, collision sparks; body pitch/roll, speed
  vignette, tire marks; chase-camera presentation transients ON by default.
- **266 → ≥ 400 GDUnit green**, 0 errors / 0 failures / 0 flaky, dev and headless recipes both.
- **60 fps on a mid-range GPU**: `test_perf_gate` ≤16.7 ms avg on all 3 presets; runtime
  benchmark auto-picks the preset; FSR2 scale slider everywhere.
- **Race nights are real**: full day/night cycle, 6 weather states with visual+physical
  consequences, wet-road grip *and* look, headlights after sun-down, no-rubber-band
  rivals across 3 skill tiers for the PLAYER.
- Parity tests make feature_comparison.io executable: each P0/P1/P2 row resolves to a
  shipped suite or an explicit "post-v1 (XL)" decision in `test_parity_load_bearing`.

---

## STATUS

_Current baseline 2026-09-19: 266 tests green (0 errors / 0 failures). This plan is the
unified S1–S17 sequence = `match_fh6_gt7_plan.md` (items 4–17, renumbered from old
S1–S9) + `html_prototype_lessons_plan.md` (items 1–3, 6, 8–10, 14+16 hygiene).
Following item shipping per sprints, each with its own sub-agent + parent re-verification:
- [x] S1 countdown  [x] S2 results  [x] S3 session stats  [x] S4 GPS  [x] S5 rivals
- [x] S6 traffic   [x] S7 events   [x] S8 FX          [ ] S9 drive feel  [ ] S10 hardening
- [ ] S11 economy  [x] S12 weather [ ] S13 garage      [ ] S14 hood cam  [ ] S15 a11y
- [ ] S16 perf bar [ ] S17 P2 sink

**Shipped 2026-09-19 — S8 Vehicle FX particles.** Suite `test_vehicle_fx.gd` (12 tests):
`scripts/vehicle/vehicle_fx.gd` (`class_name VehicleFX`, pooled `GPUParticles3D` layer —
smoke/dust/sparks/flame, `EMITTER_COUNT` 4, per-channel amount caps, `_ready` headless
cull builds ZERO particle nodes; `emission_channels()` state machine runs renderer-free,
`_process` reads drift + surface from holder), `vehicle_physics.gd` gained `signal
impact(strength)` via sharp velocity-delta spike (`impact_strength`/`is_impact_strength`,
`_detect_impact` edge-armed once per spike) feeding S3 clean-lap
(`session_stats.get_lap_impacts`), `player_car.tscn` carries the `VehicleFX` slot,
surface-driven dust fires only off-asphalt, nitro flame gated off (no nitro gameplay).
Parent-verified headless: **361 test cases | 0 errors | 0 failures | 0 flaky | 18 orphans**
(355 draft run had 5/2 — emitters were assigning `mesh` on GPUParticles3D; fixed to
`draw_pass_1` + `QuadMesh`, final 361 green).

**Shipped 2026-09-19 — S7 Event loop → reward stub.** Suite `test_event_rewards.gd`
(15 tests): `event_def.gd` (Resource + objective enum), `event_scoring.gd` (S/A/B/C bands,
`reward(def, grade)`, drift by `score/target_score`, timed by `seconds/target_time`,
abandon→C payout×0.5), `money.gd` S7 ledger stub (zero-sum + `is_accounting_consistent`),
`event_session.gd` (startable events, pause gates on living_world/traffic_spawner/
day_night_driver `set_enabled`, drag start-lights via S1 countdown seam, best-score
persist under SAVE_KEY="events", bounds auto-fail), taxonomy upgraded to **8 families**
(+outbreak, +convoy) via `place_data`/`place_defs` (P6 `place()` shape untouched;
POI marker set 15→17, `test_traffic_spawner` expectation updated). Parent-verified
headless: **349 test cases | 0 errors | 0 failures | 0 flaky | 18 orphans**.

**Shipped 2026-09-19 — S6 Living traffic.** Suite `test_traffic_driving.gd` (16 tests):
`scripts/world/traffic_driver.gd` (curve-follow on RoadNetwork via input_override +
player-proximity slow/stop with hysteresis + parked_mode + stuck-teleport rescue with
deterministic per-chain seed + `get_rescue_count`), `traffic_spawner.gd`
(`parked_ratio` export, player_pos threaded to drivers, spawn-position-only-after-
`add_child` bug fixed), ring + audio cull preserved. FIX-PASS (interrupted draft → live):
leak root-caused — `Garage extends Node` statically leaked a Node per spawned car;
changed to `extends RefCounted` (kills the leak repo-wide). Parent-verified headless:
**334 test cases | 0 errors | 0 failures | 0 flaky | 18 orphans** (baseline was 109;
+8-orphan regression first seen at 117 eliminated, now 18).

**Shipped 2026-09-19 — S5 Rival AI.** Suite `test_rival_ai.gd` (13 tests):
`scripts/ai/racing_line.gd` (centerline → apex-shifted line, closed-loop seam fixed,
finite+smooth, deviations ~0.32–0.40), `scripts/ai/rival_driver.gd` (extends
AIController, consumes racing_line + tier via `input_override`), `scenes/vehicle/rival_car.tscn`,
tier-pace ordering strict (Novice/Skilled/Expert), `GameState.rubber_band_assist` applied
ONLY to traffic + Novice rivals — never the player — and excluded from contested-rival
pace; `RaceManager.start_race()` spawns rival roster w/ grid order. Parent-verified
headless: **318 test cases | 0 errors | 0 failures | 0 flaky | 109 orphans**.

**Shipped 2026-09-19 — S4 GPS route + brake-line.** Suite `test_gps_route_follow.gd`
(10 tests): `scripts/route/route_planner.gd` (`RoutePlanner.snap()` → road_id/
perpendicular dist/remaining arc to destination with NO_ROUTE sentinel + `navigate_to()`
seam), `scripts/route/brake_line.gd` (`BrakeLine.probe()` 120 m window → hint/arrow/
distance/corner_angle), `MapRoads.minimap_route_path(rect)` so minimap draws the SAME
polyline as world_map (point-for-point agreement test), `%NavWidget` in hud.tscn
(arrow + distance + hint) driven by race_ui behind `GameState.nav_assist_enabled`
(default true). Streaming suite wait-budgets de-flaked (10/12→30 s, load-related).
Parent-verified headless: **305 test cases | 0 errors | 0 failures | 0 flaky | 109 orphans**.

**Shipped 2026-09-19 — S3 Session stats.** Suite `test_session_stats.gd` (10 tests):
`scripts/race/session_stats.gd` (pure RefCounted: `tick`/`note_impact`/`start_lap`/
`end_lap`/`reset`, distance/top-speed/max-G/drift-time/clean-lap/best-lap, MAX_G 6.0),
owned by `GameState.session_stats`; `race_ui.gd` ticks it every frame (race + free-roam)
and feeds results rows (DISTANCE/TOP SPEED/DRIFT TIME); best-lap ownership moved into
SessionStats with `race_ui._best_lap` as a read mirror (S2 gate stays green);
`DriftScorer.get_drift_time()` added; `pause_menu.gd` + `pause_menu.tscn` stats readout
(`%DistanceLabel/%TopSpeedLabel/%DriftTimeLabel/%BestLapLabel`). Clean-lap is a pure API
seam (`note_impact`→`end_lap`), ready for S8's impact signal. Legend:
`GameState.session_stats` shared headless across suites. Parent-verified headless:
**295 test cases | 0 errors | 0 failures | 0 flaky | 109 orphans**. Also recorded:
Meshy AI research DECLINED (decision note in `docs/research/meshy_ai_research.md`) — project
stays on the free + strict-CC0 pipeline.

**Shipped 2026-09-19 — S2 Race results + celebration.** Suite `test_race_results.gd`
(8 tests): `scenes/ui/hud.tscn` `%ResultsOverlay` (Dim/Confetti/Card: title, position,
total, best lap, points, stats rows, `%NextRaceButton`/`%ReturnFreeRoamButton`),
`results_confetti.gd` (seeded 2D conic burst, headless-drivable), `race_ui.gd` now
`class_name RaceUI` with `show_result(...extra_rows)` + `points_for_position`
(POSITION_POINTS = [1000,750,500,250], static stub for S11), best-lap tracking from
`LapCounter.lap_completed`. Next Race → `RaceManager.request_race(laps)` re-arms the S1
ceremony; Free Roam → `SceneTransition.flash_to_scene(open_world_root)`. Parent-verified
headless: **285 test cases | 0 errors | 0 failures | 0 flaky | 109 orphans**.

**Shipped 2026-09-19 — S1 Race countdown + start-gate.** Suite `test_race_countdown.gd`
(11 tests): `scripts/race/race_countdown.gd` (RefCounted phase machine 3→2→1→GO→RACE,
controls lock, rev override 0→1.0), `countdown_audio.gd` (procedural beeps, headless
guarded), `race_manager.gd` gates with `controls_locked()`/`rev_override()` +
`request_race()` seam, `vehicle_physics.gd` zeroes inputs when locked, `drivetrain.gd`
rpm_override rev-hold, `race_ui.gd` + `hud.tscn` `%CountdownOverlay`/`%Banner`/`%Flare`.
Parent-verified headless: **277 test cases | 0 errors | 0 failures | 0 flaky | 109 orphans**.