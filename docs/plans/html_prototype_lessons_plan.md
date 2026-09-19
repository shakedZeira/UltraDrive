# UltraDrive — HTML Prototype Lessons (Feel-by-Riding-State Plan)

> Analysis of the FH6-inspired single-HTML prototype spec (`message.txt`, 1659
> lines, 23 sections) to extract the **genuinely new, cheap surprises** it offers
> and turn them into executable work items — copied into UltraDrive in house
> style. Every item rides *state the codebase already produces* (drift flag,
> surface key, race standings, speed), which is exactly the prototype's trick.
>
> **Written:** 2026-09-19 · **Source:** `message.txt`
> (single-file Three.js FH6 mock) · **Grounded in:** read-only survey of
> `scripts/race/*`, `scripts/camera/*`, `scripts/vehicle/*`, `scripts/world/*`,
> `autoload/race_manager.gd`, `scenes/vehicle/player_car.tscn`,
> `scenes/ui/hud.tscn`, `tests/suites/*`.
>
> **Companion plan:** `docs/plans/match_fh6_gt7_plan.md` owns GPS/rivals/events/
> economy/weather/garage/a11y/perf/parity. Anything that plan takes is **cited,
> not re-planned**. The 9 items here fill the renderings the prototype proves are
> cheap and that match plan's sprints do not cover.

## Baseline

- **266 tests green today** (match-plan baseline; AGENTS.md's "263" line is
  stale). Target: **≥ 320** with **0 errors / 0 failures / 0 flaky**, orphan
  count ≤ baseline (~109 benign), headless per the AGENTS.md recipe (import
  probe, then the `-s` run with `--ignoreHeadlessMode` AFTER the tool-script
  path).
- **Canvas:** arc tach cluster w/ gear + redline `scripts/race/tachometer.gd`,
  driven by `scripts/race/race_ui.gd`; circular minimap `scripts/ui/minimap.gd`;
  chase cam + orbit cam (`scripts/camera/chase_camera.gd` with
  `transients_enabled` default **OFF**).
- **State already produced (feel-ride source):** `get_drive_info()` speed/gear/
  rpm/brake/steer/surface (`scripts/vehicle/vehicle_physics.gd:182-196`),
  `DriftScorer` (exists, **not wired to UI**), `SurfaceRegistry` 6-state
  classify, `RaceManager` standings (lap→checkpoint→distance), `LapCounter`
  per-lap/race times, `WeatherManager` grip factor.
- **Confirmed empty (prototype gaps the plan targets):** zero GPU/CPU particle
  nodes in the repo, no countdown, no results screen (FINISH banner only),
  no session stats, no body pitch/roll rig, no hood cam, no tire marks,
  no speed vignette, traffic spawns **but never drives**, no nitro.

---

## What the prototype teaches us

The meta-lesson of a 1659-line "FH6 in one HTML file" is that nearly all of a
Forza *feel* is **presentation closure over state that already exists**. The
prototype builds no real simulation — it manufactures the whole fantasy from a
handful of signals: speed (arc), rpm (tach), gear, a drift flag, surface
sampling, race position, lap/timer, a countdown phase. UltraDrive already emits
every one of those signals. So the cheap, high-yield moves are **readers** —
DriftScorer already tracked → feed it a smoke emitter; SurfaceRegistry already
classifies → feed it dust; RaceManager already standings → feed it a ceremony
and a results card; speed already exists → pitch/roll/vignette. Second lesson:
the prototype's "edge-case hardening" list (§21) is where a drive-bug-free game
is actually won, and it is cheap to encode as regression tests. Third: the
biggest isolated cost item (traffic that *drives*) is also the biggest "world is
alive" win — anchor it to the road graph that already ships (`RoadNetwork` /
`RoadDef` / `RoadGraph`) so this plan never builds new map machinery.

---

## Cross-reference with `match_fh6_gt7_plan.md`

Already taken there (cited, NOT re-planned here): HUD cluster + minimap route
(match baseline + S1 GPS), garage stat-bar cards (match **S6**), rain/wet VFX
(match **S5**), clean-lap/drift payoff → economy grades (match **S4**,
our stats feed it as S-grade inputs), rivals + no-rubber-band-on-player
(match **S2**), brake-line/GPS (match **S1**), event→reward loop (match **S3**),
perf benchmark/auto-preset (match **S8**).

| This plan item | Relationship to match sprints |
|---|---|
| 1 Countdown ceremony | New work; sits **before S1** (completes the D6 race loop's last felt step). Reusable by match S3's event loop (`request_race` seam). |
| 2 Results + celebration | New work; sits **before S1**; stats card from item 3. Graded position/score socket for match S4's economy. |
| 3 Session stats | New work; pure-logic S; **feeds match S4** (S-grade rewards), **S9 leaderboards** (ghost/lap records need stats). |
| 4 Vehicle FX particles | New work; mechanism shared by match **S5** rain particles (same pooled GPU layer). Nitro-flame slot reserved for a future boost item (none planned). |
| 5 Visual suspension + speed presentation | New work; `transients_enabled` ON is the flag match **S7** a11y "camera feel" sliders will expose. Vignette needs an a11y/colorblind-safe palette toggle in S7. |
| 6 Hood camera | New work; third mode in the C-cycle that S7's rebind/sensitivity covers. |
| 7 Traffic driving behaviors | New work; shares `input_override` driving with match **S2** rival AI (same `AIController._simulate_input` seam). Fills match S2's "traffic spawned without drivers" gap. |
| 8 Hardening audit → suite | New work; race-cleanup assertions overlap match S2 roster + S9 parity discipline. |
| 9 Performance hygiene | **Appendix only** — feeds match **S8** `test_perf_gate` (staggered traffic, fake shadows, shared mats, LOD, draw-distance cull). |

---

## Sprint mapping & ordering rationale

Ordered by **value-of-feel ÷ cost** (feel is what the prototype maximises; cost
is an S/M/L judgement against the 1–2 person team).

| Order | Fuel | Items | Sits with match plan |
|---|---|---|---|
| F1 | "Race ceremony" | 1 + 2 + 3 | **Before S1** — zero deps, completes the core loop, pure-state + overlay work |
| F2 | "Drive feel" | 5 + 4 | **Phase-A window (S1–S3 in parallel)** — no file overlap with GPS/rivals/events |
| F3 | "Living traffic" | 7 | **Alongside S2** — shares the `input_override` driving seam |
| F4 | "Insurance" | 6 + 8 | **With Phase-B boundary / before S8** — hood cam is trivial, hardening is a small-surgical batch |
| — | Perf notes | 9 | **Feeds S8** (appendix, not a sprint) |

Rationale: the ceremony bundle is the single biggest race-feel win and has no
dependencies (D6 race loop + LapCounter already ship standings and per-lap
times), so it lands first. Drive-feel reads existing state and touches files
nobody else plans for (car scenes, hud.tscn, chase defaults) — safe to run
parallel in Phase A. Traffic drives only after the road graph exists (it does),
so F3 slots with the AI sprint. Hardening is tagged F4 because it is insurance,
not feature feel, but its edits stay small and surgical.

---

## Work items

### 1. Race pre-countdown + start-gate ("3…2…1…GO!")

- **Goal:** Every race starts with a controls-locked countdown: big "3 / 2 / 1 /
  GO!" HUD sequence with per-phase beeps and a GO flare, engine-rev
  anticipation while locked, then controls release — for circuit races now and
  free-roam events once match S3 raises them.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Race start | `race_ui.gd:20-23` starts the race on its first frame. No countdown | `RaceManager` ceremony gate; copy of race fully armed but player input clamped |
  | HUD | Position/Lap/Time labels only | `%CountdownOverlay` in `hud.tscn` — "3…2…1…GO!" |
  | Control lock | `VehiclePhysics` reads `InputManager` unconditionally (`vehicle_physics.gd:76-81`) | gate on `RaceManager.controls_locked()`; stores hold neutral |
  | Rev anticipation | none | drivetrain rpm blips toward redline during lock (reuse `Drivetrain.engine_rpm` path) |
  | Audio | engine beds only (`CarAudio`) | procedural per-phase beeps + higher GO beep (mirror §12 beeps) |
  | Reuse | n/a | `RaceManager.request_race(laps)` seam callable by any start source (future events) |

- **Work:**
  1. `scripts/race/race_countdown.gd` (new, `class_name RaceCountdown`,
     RefCounted — pure, headless-testable): `start()`, `advance(delta)`
     returns phase `"3"/"2"/"1"/"GO"/"RACE"`, `controls_locked()`,
     `rev_rpm_override() -> float` (0…redline fraction), `progress()`.
  2. `autoload/race_manager.gd`: `controls_locked()` + ceremony state hooks;
     `race_ui.gd` drives the overlay phases from the RefCounted in `_process`.
  3. `scripts/vehicle/vehicle_physics.gd`: when `controls_locked()`, zero
     inputs and feed `rev_rpm_override()` into `_drivetrain`. Small, single
     site.
  4. `scenes/ui/hud.tscn`: `%CountdownOverlay` + `%Banner` nodes; GO flare
     pulse.
  5. Optional audio: `scripts/race/countdown_audio.gd` (new, procedural
     blips, guarded headless).
- **Acceptance test gate:** `tests/suites/test_race_countdown.gd` — phases
  advance in order with deterministic delta timing; `controls_locked()` true
  until GO, false after; rev override follows phase (0 then climb); HUD label
  text equals the phase in order (scene_runner on `hud.tscn`); reuses
  `test_race_loop.gd` after_free discipline (no leaked counters).
- **Effort:** S • **Depends-on:** D6 race loop (done). • **Quick-win:**
  the RefCounted + one overlay is already "a real race start".

### 2. Race results screen + celebration

- **Goal:** A real results screen replacing the FINISH banner: finishing
  position, total time, best-lap, session-stats card, and a win/celebration
  state (confetti + gold "1st PLACE!") vs a flat also-ran state, with
  "Next Race / Return to Free Roam".
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Finish | `_on_race_finished` flips PositionLabel to "FINISH %.2fs" (`race_ui.gd:43-52`) | `%ResultsOverlay` panel; clear + dismiss via buttons |
  | Best lap | `LapCounter` per-lap times exist; best-lap not tracked | best-lap from `lap_completed` (item 3 owns it) |
  | Win state | none | 1st ⇒ confetti + gold glow; else neutral |
  | Exit | scene flow only | "Next Race" (re-arm ceremony) + "Return to Free Roam" (GameState scene nav) |
  | Grade socket | none | position/points → match **S4** economy award stub |

- **Work:**
  1. `scenes/ui/hud.tscn`: `%ResultsOverlay` (position, total time, best lap,
     per-item stats rows, buttons).
  2. `scripts/race/race_ui.gd`: `_on_race_finished` shows overlay fed by
     standings + `SessionStats` (item 3); `_on_next_race` / `_on_return_free_roam`
     handlers.
  3. `scripts/race/results_confetti.gd` (new, CanvasItem draw — plain 2D
     conic squares, no GPU particles, headless-safe): fade/fall over ~3 s.
  4. Position→points table constant (1st 1000…4th 250 per §20), exported for
     match S4.
- **Acceptance test gate:** `tests/suites/test_race_results.gd` — overlay
  shows exactly standings[0]=winner, total = `get_total_time()`, best lap from
  SessionStats; win state true only for position 1; confetti tween completes
  without scene; buttons emit the right GameState transitions; no leaks.
- **Effort:** S • **Depends-on:** item 1, item 3 (stats card). • **Quick-win:**
  even a simple "P1 · 1:23.4 · BEST 1:22.1" card reads complete.

### 3. Session stats tracker

- **Goal:** A pure `SessionStats` that accumulates distance driven, top speed,
  max G, drift time, clean-lap + best-lap flags across free-roam and races;
  surfaced on the results screen and pause menu; emits S-grade inputs to match
  **S4**.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Accumulator | none | `SessionStats` RefCounted (autoload-adjacent) accumulates via `tick(delta, speed_kmh, max_g, drifting)` |
  | Drift time | `DriftScorer` tracks internal `_drift_time` (`drift_scorer.gd:19`) but exposes only score | expose drift time; SessionStats mirrors it |
  | Clean lap | none (no collision signal to build from) | clean-lap flag from item 4's `impact` signal + `LapCounter.lap_completed` |
  | Best lap | `LapCounter.get_lap_time()` per lap only | global best-lap across session |
  | Surface | ps | On pause menu (`pause_menu.gd`) + results screen (item 2) |
  | Feeds | — | match **S4** S-grade + **S9** leaderboards |

- **Work:**
  1. `scripts/race/session_stats.gd` (new, `class_name SessionStats`,
     RefCounted — pure logic, **no frames**): `tick()`, `start_lap()` /
     `end_lap(clean)`, getters, `reset()`; monotonic invariants.
  2. `race_ui.gd` calls `tick()` each frame from `get_drive_info()`;
     free-roam path calls `tick()` from `VehicleManager.get_player_car()`.
  3. `pause_menu.gd` stats panel (SessionStats readout).
  4. `DriftScorer` exposes `get_drift_time()` for parity.
- **Acceptance test gate:** `tests/suites/test_session_stats.gd` — pure math
  (no scene): distance monotonic, top-speed max, max-G clamp, drift-time sums,
  clean-lap only when zero impacts in the lap, best-lap min, `reset()` zeroes;
  determinism across identical tick sequences.
- **Effort:** S • **Depends-on:** item 4's `impact` signal (clean-lap input);
  otherwise standalone. • **Quick-win:** a pause-menu "Today: 3.2 km · 182 top"
  card instantly makes drivers feel a session.
- *(Match note: clean-lap/drift bonuses feed economy — match S4; do not build
  rewards here.)*

### 4. Vehicle FX particles

- **Goal:** A pooled `GPUParticles3D` layer on `player_car.tscn` (and a latch on
  traffic) driven **by existing state**: tire smoke when drifting, off-road
  dust when surface ≠ asphalt (`SurfaceRegistry` already classifies), collision
  sparks from a small `impact` signal, nitro flame behind a `has_nitro` hook.
  Strictly headless-culled.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Particles | **zero** in repo (grep empty; no GPU/CPU particle node) | `VehicleFX` node: pooled smoke/dust/sparks/flame emitters |
  | Drift signal | `DriftScorer` tracked but **not wired**; physics computes handbrake rear-grip (`vehicle_physics.gd:132-133`) | smoke emitter reads drift state (DriftScorer or lateral slip) |
  | Dust signal | `get_surface_key()` / `resolve_surface_factors()` exists (`vehicle_physics.gd:205-225`) | surface path intended for GPUParticlesWater |
  | Impact signal | none | `VehiclePhysics` gains `signal impact(strength)` via sharp deceleration delta (single site) |
  | Headless safety | renderer-guarded convention in quality ladder | no particle nodes when `DisplayServer.get_name() == "headless"` |

- **Work:**
  1. `scripts/vehicle/vehicle_fx.gd` (new, `class_name VehicleFX`, Node on
     `player_car.tscn` + traffic-instance slot): pre-built GPUParticles3D
     children (smoke, dust, sparks, flame-slot), budget cap, `_ready`
     headless-cull, pooled (never instantiate at runtime).
  2. `scripts/vehicle/vehicle_physics.gd`: tiny `impact` signal (velocity
     delta spike) — feeds sparks + item 3 clean-lap.
  3. Wire drift → smoke, surface != ASPHALT → dust, impact → sparks.
- **Acceptance test gate:** `tests/suites/test_vehicle_fx.gd` — headless run:
  0 particle nodes instantiated; emitter budget & node-count caps respected;
  surface-driven dust only fires off-asphalt; impact threshold testable via a
  stub velocity delta; no leaks on free.
- **Effort:** M • **Depends-on:** DriftScorer wiring (no new physics) +
  SurfaceRegistry (exists). • **Quick-win:** drift smoke alone is the single
  largest "this is a racing game" frame.

### 5. Visual suspension + speed presentation

- **Goal:** Visual-only body pitch/roll on accel/brake/steer (independent
  additive rig on CarBody), a speed vignette/streak overlay, handbrake
  tire-mark skids, and `transients_enabled` presentation defaults ON for the
  player chase cam.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Body rig | CarBody is a static GLB child (`player_car.tscn:18`) | `BodyRig` Node3D on CarBody: bounded pitch/roll lerped from drive_info |
  | Chase presentation | `transients_enabled` **default OFF** (`chase_camera.gd:19`) | ON for player; speed look-ahead/FOV kick/lateral-g shake |
  | Speed vignette | none | `%SpeedOverlay` in `hud.tscn` — monotonic darkening + subtle streak layer |
  | Tire marks | none | `TireMarks` short-lived dark quads at rear wheels while handbrake held (~3 s fade, §18) |
  | a11y | none | vignette/streak behind flags match **S7** expose |

- **Work:**
  1. `scripts/vehicle/body_rig.gd` (new, Node3D on CarBody): pitch (−2° accel /
    +3° brake), roll (±2° steer), lerp factor ~0.1, hard-clamped; additive like
    chase transients.
  2. `scenes/vehicle/player_car.tscn`: `BodyRig` + `FXSlot`; `scenes/ui/hud.tscn`
    `%SpeedOverlay`.
  3. `scripts/ui/speed_overlay.gd` (new, Control draw) — vignette intensity =
    f(speed_kmh) monotonic.
  4. `scripts/vehicle/tire_marks.gd` (new, Node) — pooled short-lived quads;
    headless-culled.
  5. Chase `transients_enabled = true` by default for the player car
    (keep debug hooks for tests).
- **Acceptance test gate:** `tests/suites/test_drive_feel.gd` — body_rig angles
  within clamp bounds and settle toward rest; vignette opacity monotonic with
  speed; tire-marks spawn under handbrake and despawn within lifetime; chase
  default off→on toggle still passes `test_chase_camera.gd` (transient maths
  unchanged).
- **Effort:** S–M • **Depends-on:** chase transients (exist). • **Quick-win:**
  the suspension rig alone is a "night-and-day" feel bump for a Node3D + lerp.

### 6. Hood camera (optional)

- **Goal:** Third camera mode — chase / close / hood — reusing chase follow
  maths with a FOV bump + light speed-based head bob; C-cycle wired.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Modes | chase + orbit only (`orbit_camera.gd` C-toggle, line 60) | chase / orbit / hood cycle |
  | Hood view | none | `hood_camera.gd` — rigid attach to body, FOV 70→75 bump, head bob amplitude×speed |

- **Work:** `scripts/camera/hood_camera.gd` (new) extends chase follow maths;
  add to the mode toggle consumed by `player_car_controller.gd` / camera node
  wiring; FOV + bob assertion hooks (like chase's `debug_*`).
- **Acceptance test gate:** `tests/suites/test_hood_camera.gd` (following
  `test_chase_camera.gd` pattern) — transform stays on car hood; FOV bumps to
  the hood target; bob bounded; toggle cycles deterministically.
- **Effort:** S • **Depends-on:** chase follow (exists). • **Quick-win:** a
  hood FOV-only readout is 90% of the immersion.

### 7. Traffic driving behaviors

- **Goal:** Spawned traffic actually drives: curve-follow on `RoadNetwork`
  chains via the `input_override` seam, player-proximity slow/stop + avoid,
  parked cars, stuck-teleport rescue, intersection branch picks through the
  road graph — keeping spawn/despawn ring and headless safety.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Driving | `TrafficSpawner` spawns `VehiclePhysics` cars; **nothing drives them** (`traffic_spawner.gd:48-51`) | per-vehicle `TrafficDriver`: waypoints from nearest road chain + `input_override` (AIController seam, `ai_controller.gd:53`) |
  | Route source | n/a | `RoadNetwork.get_nearest_road_pos` / chains + `RoadGraph` junction branching at intersections |
  | Player avoid | none | within ~10 m ahead slow, ~5 m stop; resume after gap |
  | Parked | none | spawner `parked_mode` flag → still cars in marked spots |
  | Stuck | none | no-movement 2 m / 5 s ⇒ teleport to random road point (§8) |
  | Ring | `update()` despawns at `spawn_radius+100` + audio distance-cull (`traffic_spawner.gd:17,26`) | unchanged; staggered update turn (perf, item 9) |

- **Work:**
  1. `scripts/world/traffic_driver.gd` (new, `class_name TrafficDriver`,
     RefCounted per vehicle driven by the spawner): waypoints, speed (casual
     10–20 u/s), smooth steer, branch-at-junction, avoid, parked, stuck rescue.
  2. `scripts/world/traffic_spawner.gd`: attach drivers on spawn; despawn
     frees drivers (no leaks); expose `update(player_pos, delta)`;
  3. `scripts/world/living_world.gd`: pass delta + stagger (item 9).
- **Acceptance test gate:** `tests/suites/test_traffic_driving.gd` (new — the
  existing `tests/test_traffic_spawner.gd` lives at `tests/` root, keep it):
  vehicles stay on-road within a tolerance across frames; avoid/slow fires only
  inside the band; parked cars never move; stuck rescue teleports to a road
  point once; despawn frees driver nodes (orphan count ≤ baseline).
- **Effort:** L • **Depends-on:** RoadNetwork/RoadDef/RoadGraph (exist);
  `input_override` driving (exists via AIController). • **Quick-win:** even a
  2-point "drive to next road point and stop" pass makes the hub feel alive;
  full route-follow is the polish tail.

### 8. Racing-game hardening audit → test suite

- **Goal:** Encode the prototype's §21 bug-prevention list as GDUnit
  assertions; where a guard is genuinely missing, add it (small, surgical).
- **Today vs Target**

  | Guard | Today | Target |
  |---|---|---|
  | NaN + last-valid restore | `y < -20` respawn only (`vehicle_physics.gd:72-74`); **no `is_finite` guard, no last-valid store** | finite-check each frame; restore last-valid pos/speed (mirror spec §21-3) |
  | Speed clamping | reverse capped by drivetrain limiter (`drivetrain.gd:83-89`); **no top-speed clamp in arcade handling** | clamp speed ∈ [−reverseMax, topSpeed] in arcade path (§21-13) |
  | Steer-at-zero div-by-zero | steer path already division-free (`vehicle_physics.gd:89-91`) | regression assertion only |
  | Race state cleanup / re-entry | covered for lap counters (`test_race_loop.gd:130`); ceremony state reset when items 1–2 land | ceremony + results state fully reset on re-entry |
  | Start-action debounce | `queue_race` accepts any spam (`race_manager.gd:20`) | debounce start requests ~250 ms after ceremony |
  | Despawn memory disposal | `TrafficSpawner` `queue_free()`s vehicles; drivers (item 7) must not leak | assert freed nodes + orphan ≤ baseline |
  | Delta-time cap | engine clamps via physics ticks; no explicit `min(delta, 0.05)` | assert no NaN after an extreme delta spike |

- **Work:** surgical edits to `scripts/vehicle/vehicle_physics.gd`
  (finite-guard + last-valid + speed clamp), `autoload/race_manager.gd`
  (debounce), `scripts/world/traffic_spawner.gd` (driver free, if item 7
  shipped first). **Where the guard exists, only the test ships.**
- **Acceptance test gate:** `tests/suites/test_hardening.gd` — NaN injection →
  restore semantics; speed stays within bounds; steer-at-zero asserts; race
  re-entry leaves zero ceremony/counter residue; double start ignored; traffic
  despawn frees nodes; big-delta frame yields finite state.
- **Effort:** S • **Depends-on:** nothing (item 1/2/7 states if shipped). •
  **Quick-win:** the NaN + clamp saves a real playtest crash class for ~20
  lines.

### 9. Performance hygiene (appendix → match S8)

- **Goal:** Feed the match **S8** perf gate with the prototype's §15 budget
  list — as notes, not a standalone mega project.
- **Notes (fold into S8 `test_perf_gate` + `region_dresser` audit):**
  - **Stagger traffic updates** (item 7): rotate 3–4 `TrafficDriver` ticks per
    physics frame (§15).
  - **Fake under-car shadow quads** for traffic (cheap dark plane, no shadowmap
    budget), instead of real casting — the prototype's exact move.
  - **Shared materials:** already the norm (`prop_scatterer`/`foliage`
    MultiMesh reuse, `CarVisuals` surface clones) — extend to tires/skids/FX.
  - **LOD + draw-distance cull:** already in `region_dresser` (band density /
    `visible_instance_count`) — extend caps as density grows with FX + traffic.
  - **Budget rows:** reference scene ≤16.7 ms/avg on all presets, asserted in
    match S8.
- **Acceptance test gate:** none standalone — rows land in match S8's
  `test_perf_gate` and the streaming-dressing suite.
- **Effort:** S (scoped into S8) • **Depends-on:** items 4/7 content exists. •
  **Quick-win:** traffic fake shadows beat shadow-casting for 10+ cars.

---

## Definition of "done" for this plan

- All 8 work items shipped; item 9 folded into match S8.
- New suites **green headless** per the AGENTS.md recipe: `test_race_countdown`,
  `test_race_results`, `test_session_stats`, `test_vehicle_fx`, `test_drive_feel`,
  `test_hood_camera`, `test_traffic_driving`, `test_hardening`.
- GDUnit total **266 → ≥ 320**, 0 errors / 0 failures / 0 flaky, orphan count
  ≤ baseline. No rubber-band assist added on the player (project ethos).
- `transients_enabled` ON is the only default-behavior change; everything else
  is additive (overlays, nodes, particles) with `test_chase_camera.gd` and
  `test_race_loop.gd` still green as the regression guard.

---

## STATUS — 2026-09-19: plan written, nothing shipped