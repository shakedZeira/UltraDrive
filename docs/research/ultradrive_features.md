# UltraDrive — Current Feature Dossier (Read-the-Codebase)

*Compiled by reading every script, scene, resource, and test in the repo. Nothing below is inferred from marketing prose; every claim cites the code it was read from (`res://` paths). Where "the code now" differs from older plans in `docs/ROADMAP.md`, the code wins and the difference is flagged explicitly.*

- **Project**: `UltraDrive` — "Hybrid open-world + circuit racing game" (`project.godot` `config/name`, `config/description`).
- **Engine**: Godot 4.7, Forward+ renderer (`project.godot`).
- **Status line**: a playable vertical slice — real live road network, streaming 3D terrain, drivable cars, a full Tuning-era garage/kiosk shell, driveable weather states, and a living-world simulation — with racing events, AI rivals, and progression still arriving in later phases.

---

## 1. Overview

**IMPLEMENTED**
- Boot chain `res://main.tscn` → `res://scripts/main/main.gd` — immediately transitions to the main menu (`scene_transition` fade → `GameState.change_scene("scenes/ui/main_menu.tscn")` in `scripts/main/main.gd`).
- Core autoloads (all in `project.godot`): `GameState` (`scripts/autoload/game_state.gd`, the central scene/flow/vehicle-context state machine), `AudioManager` (`scripts/autoload/audio_manager.gd`), `SettingsStore` (`scripts/autoload/settings_store.gd`, persisted via `user://settings.json`), `WorldDiscovery` (persisted path discovery), `EventRegistry` (persisted placed events), and race/weather/terrain registries.
- Two full play surfaces: an **open world** (`res://scenes/world/open_world_root.tscn`) and **dedicated tracks** (`scenes/track/mountain_pass.tscn`, `scenes/track/test_circuit.tscn`), plus a test arena (`scenes/test/test_track.tscn`).
- A single `PlayerCar` vehicle scene (`scenes/vehicle/player_car.tscn`) that consumes `CarConfig` resources; six garage cars are configured and selectable.
- A complete **core loop**: main menu → **Free Roam** (open world, live traffic, day/night + weather, discovery, fast-travel via map) or **Track Select** (two maps) → per-map **Kiosk/Race Setup** screen → drive → results.
- Event "seeding": the open world already *places* 10 event sites (drag strip, drift zone, touge duel, night street loop, marathon highway, plus five time-attack anchors) in `world_discovery`-style `EventRegistry` — the launcher/score-management for them is **(PLANNED Phase 1.4)**.
- Determinism: everything generated from seeds (`MASTER_SEED = 1337 * 1337 = 1787569` in `res://scripts/world/corridor_planner.gd`; per-region seeds derived from it in `scripts/world/region_dresser.gd`) so the same machine always builds the same world.
- Expensive generation work lives in **worker threads** that report progress to `GameState.progress` (`terrain_seeder.gd`) and uses **idempotent, re-entrant** region dressing (`region_dresser.gd`), so "Press Start again" re-cycle works without duplication.

**Correction to earlier docs**: the "3 roads / ~6.4 km / 65 m relief" prose in `docs/ROADMAP.md` described the pre-W prototype. The live code generates **12 classified road corridors** on a **60 km** network budget over **~1100 m of real alpine relief** (see §2 and §3).

---

## 2. World & map

**IMPLEMENTED**
- Network budget: `KM_TARGET = 60.0` (km) in `res://scripts/world/corridor_planner.gd`.
- `WorldDriver` (`res://scripts/world/world_driver.gd`) owns the whole open world: it boots the road network (`_bootstrap_roads()` registers *every* `CorridorPlanner.plan()` def), drives the sun and noon/ambient values, and spawns/despawns the player.
- `ChunkStreamer` (`res://scripts/world/chunk_streamer.gd`): 256 m chunks, load radius 2 (5×5 live grid), handled against the world origin (`Vector3.ZERO`), streams in `Terrain3D` regions + decor as the player moves.
- `TerrainSeeder` (`res://scripts/world/terrain_seeder.gd`): keeps a **3×3 storm of live regions** around the player, prefetch offset radius 2, applies at most 2 regions per tick (frame-budget friendly), pre-bakes corridors with a 1-chunk margin **before** the player spawns so roads are never missing, and hands the player a baking delay via `GameState.progress` (~3.3 s at world origin (128,2.2,128)).
- Six elevation bands in `res://scripts/world/terrain_baker.gd`: **SEA** (< 0) / **PLAINS** (0–10 m) / **ROLLING** (10–60 m) / **LOWLAND** (60–200 m) / **HIGHLAND** (200–600 m) / **ALPINE** (≥ 600 m) — the whole world envelope is `HEIGHT_MIN = -8` to `HEIGHT_MAX = 2000` m.
- Points of interest: 5 anchor POIs in `res://scripts/world/poi_registry.gd` (named, typed, map-icon'd); **10 more event scripts** from `EventRegistry.place()` merge in lazily → **15 discoverable places** on the map.
- `WorldDiscovery` (`res://scripts/world/world_discovery.gd`): per-flag **visited** tracking in small 30 m cells, reveal radius 90 m around the driver, persisted to a save key `discovery`; discovered roads render white on the map, undiscovered grey.
- **Fast travel**: the pause **World Map** (`res://scripts/ui/world_map.gd`) recenters the camera, and clicking any discovered POI dispatches `fast_travel_to` — communicated through the shared static `route_target` on `res://scripts/ui/map_roads.gd`.
- **Minimap** (`res://scripts/ui/minimap.gd`): circular world map with player blip + arrow, redraw threshold 4 m / 0.05 rad to avoid burning frames.
- **PLANNED** (Phase 1.2+): even more districts/landmarks; photo/video/telemetry modes; leaderboard anchors.

---

## 3. Roads & terrain

**IMPLEMENTED — the road network (`res://scripts/world/corridor_planner.gd`)**
12 classified `RoadDef` corridors, all registered by `WorldDriver._bootstrap_roads()`:

| Class | Road | Radius/shape | Width | Notes |
|---|---|---|---|---|
| ARTERIAL | `hub-ring` | r 110 m | w8 | Tight ring at the hub; **hard invariant `defs[0..2]` ordering** — cannot be lost on reseed |
| ARTERIAL | `hub-pass` | connector | w8 | Hub → mountain-pass zone (~5.3 km spine) |
| ARTERIAL | `pass-loop` | loop | w8 | Open loop over the pass |
| ARTERIAL | `hub-coast` | connector | w8 | Hub → coast (bridges 2 coastal roads to the hub) |
| ARTERIAL | `hub-highway-ramp` | ramp | w8 | Interchange between hub and ring road |
| HIGHWAY | `highway-ring` | ellipse center (4400,2250) axes 4600×3550 | w16, banking 0.35 | **~25.7 km** high-speed ring; the network backbone |
| TOUGE | `touge-a` | r 820 m | — | Wraps the **alpine dome at (7800,6400), amp 1100 m** |
| TOUGE | `touge-b` | r 700 m | — | Wraps the **alpine dome at (6400,7800), amp 850 m** |
| COASTAL | `coast-a` | — | — | Clings to the coast corridor |
| COASTAL | `coast-b` | — | — | Second coastal line |
| DIRT | `dirt-a` | — | w7, GRAVEL | Off-road through terrain, lower grip surface |
| DIRT | `dirt-b` | — | w7, GRAVEL | Second off-road line |

- Uses **island-road generation** (in `corridor_planner.gd`, read: random-walk/spline via `SimplexNoise`); radial corridors follow retargeted circumferences so they stay valid at large radii.
- All corridors **conform to terrain**: `RoadNetworkMeshGenerator` reads baked heights through a sparse AABB distance field so roads hug the hills (`ROAD_TOPPING = 0.15` m recess, `BLEND_END_DISTANCE = 40` m transitions).
- **Terrain baking** (`res://scripts/world/terrain_baker.gd`): pure/headless-safe; heightfield from a **dome family** — (7800,6400) amp 1100 r3200, (6400,7800) amp 850 r2800, (7000,3000) amp 150 r1800, and a legacy island dome (5632,5632) amp 42 r5000 — blended with rolling noise; color baking to RGBA8 for the colormap; roads carved into the heightfield with the same distance field.
- Roads are stored in `RoadNetwork` (`res://scripts/world/road_network.gd`) with `RoadData` per corridor (width, surface `set()`, per-segment visited flags); `world_road.png`/GDText atlas saves terrain from headless CI runs.

**IMPLIED + PLANNED**
- Real **road markings/signage/side-features**, potholes/surface damage, gravel churn, and **track day** variants are **(PLANNED Phase 1.7)**.
- Road **patches/fixes** as a retention mechanic are not yet implemented.

---

## 4. Vehicles

**IMPLEMENTED — garage roster (`res://resources/cars/*.tres`)**

| Car | Class | Mass | Torque | Redline | Gears | Stats flavor |
|---|---|---|---|---|---|---|
| **Striker** | D | 1100 kg | 180 Nm | 7000 rpm | 5 | Entry coupe (`starter_car.tres`); no `visual_path` → defaults to `res://assets/cars/sports_coupe.glb` |
| **Thunderhead** | C | 1420 kg | 420 Nm | 6200 rpm | 5 | Muscle (`muscle_car.tres`; `muscle_car.glb`) |
| **Dirt Devil** | B | 1050 kg | 260 Nm | 8200 rpm | 6 | Rally hatch (`rally_hatch.tres`; `rally_hatch.glb`) |
| **Comet** | C | 1200 kg | 305 Nm | 7600 rpm | 6 | Sports sedan (`cc0_sedan_sports.tres`; red `car_paint.tres`: albedo 0.82/0.13/0.12, metallic 0.92, roughness 0.35, clearcoat 1.0) |
| **Hooligan** | B | 1080 kg | 265 Nm | 8200 rpm | — | Hot hatch |
| **Interceptor** | A | — | — | — | — | Top tier; **no S-class car exists** yet |

- `CarConfig` schema (`res://scripts/vehicle/car_config.gd`): mass, torque, redline, gear count, shift tables (`upshift_rpm`/`downshift_rpm` per gear), diff type, `engine_timbre` (sport/muscle/rally), plus **arcade vs sim modifier dicts** consumed by the physics.
- **Rendering/audio** (`res://scripts/vehicle/car_visuals.gd` + `car_audio.gd`): paint-from-resource, wheel spin/steer from chassis state; engine audio **synthesized 3-bed** around ~0.95 / 1.6 / 2.6 kHz bed frequencies with a low-pass sweeping 1400→5000 Hz from the rev range — **no audio assets needed** for engines.
- Gearbox UI incl. the **"R" reverse digit** and redline shift-lights in the tach (`res://scripts/race/tachometer.gd`).
- **PLANNED** (Phase 1.3+): full garage customization (visual kits, wheels, livery, and the tant/rims flow), car **ownership/purchase**, upgrade parts, and the **S-class** ladder; `CarVisuals` multi-part kits/livery are on the roadmap.

---

## 5. Game modes & events

**IMPLEMENTED**
- **Free Roam** (open world): drive anywhere, chase cam + player-follow orbit cam (`scenes/world/open_world_root.tscn` cameras), fast-travel, live traffic, weather/time-of-day, discovery completion.
- **Track modes**: via `TrackSelect` (`scenes/track/…`) you can enter `mountain_pass.tscn` / `test_circuit.tscn` on a dedicated facility.
- **10 placed event sites** in `EventRegistry` (`res://scripts/world/event_registry.gd`), all dropped deterministically onto the road network:
  - `touge_duel` — matched to a TOUGE corridor (gradient ≥ 0.05 rule),
  - `drag_strip` + `marathon_highway` — straight-line rules (segment heading drift ≤ 2°, segment segment continuity),
  - `drift_zone` — near the hub ring,
  - `night_street_loop` — urban-ish circuit,
  - `time_attack_0..4` — time-trial anchors on the five base POIs.
  These merge lazily into the POI registry → **15 map markers**.
- **Kiosk/Race Setup** screen (per-map) lets you pick a car before driving; results flow back to `GameState`.
- **PLANNED** (all explicitly tagged): Phase 1.4 — event **launchers, lead-in sequences, scoring/tiers, restart**; Phase 1.6 — AI rivals with rubber-band assist (`rubber_band_assist` exists in `game_state.gd` as a flag awaiting the AI); Phase 1.8 — rewind/replay; Phase 2.1 — licenses, championships, credits-market; Phase 2.2 — ghosts + leaderboards.

---

## 6. Menus & UI

**IMPLEMENTED**
- `scenes/ui/main_menu.tscn` + `scripts/ui/main_menu.gd` — title, backdrop, and **Free Roam / Track Select / Settings / Quit** entry points, wrapped by the fade layer `SceneTransition` (`scripts/autoload/scene_transition.gd`, canvas layer 100, 0.5 s fade, then `GameState.change_scene`).
- `scenes/ui/track_select.tscn` — choose a track with preview tiles.
- `scenes/ui/garage.tscn` + `scripts/ui/garage_ui.gd` — **rail-card carousel** of the six cars, rotating turntable preview, and **6 stat bars** rendered from real `CarConfig` numbers plus a specs readout line.
- `scenes/ui/pause_menu.tscn` — Resume / Restart / Settings / Map / Quit, with the **World Map** (`scripts/ui/world_map.gd`, fit-all, north-up) and **fast-travel** on discovered waypoints.
- `scenes/ui/settings_menu.tscn` + `scripts/ui/settings_menu.gd` — audio, video quality, input, gameplay, accessibility.
- `scenes/ui/hud.tscn` + `scenes/race/tachometer.gd` — live HUD with revs/gear/speed, class badge, and hints; gap timers exist for races.
- TC: **cutscene/splitscreen/**DRM-free streaming UIs are **(PLANNED Phase 1.9 / later)**.
- Localization framework is scaffolded (translation resources in `project.godot`), but localized content is **(PLANNED Phase 3.2)**.

---

## 7. Physics & driving

**IMPLEMENTED**
- **Jolt** as the Godot physics engine (`addons/jolt_physics` in `project.godot`, `physics/gd_physics_provider`).
- `scripts/vehicle/vehicle_physics.gd` drives `PlayerCar`: 4-wheel `VehicleWheel3D` (`WheelFL/FR/RL/RR`), spring/stiffness tuned per-vehicle, tire friction from the current surface, power from torque curve + rev range, and gear shifts from the config's shift tables.
- **Surface-aware grip**: `SurfaceRegistry` (`scripts/world/surface_registry.gd`) maps per-surface grip — ASPHALT 1.0/1.0, CONCRETE 0.92/0.95, GRAVEL 0.85/0.85, DIRT 0.65/0.70, GRASS 0.55/0.58, SNOW 0.35/0.30 — and `vehicle_physics.gd` swaps grip/scuffing when the wheels leave the topping. Road surface cross-references `RegionalClimate`.
- **Handling modes** with per-car arcade/sim modifier dicts (steering speed, counter-steer assist, drift assistance), a `handling_mode` switch, and throttle mapping; assists expose **traction/steering/drift helps**.
- **Altitude/grip interplay**: `regional_climate.gd` reaches the surface table so grip can drop as you climb into alpine snow lines.
- **Sun/night torque**: day-night affects ambient light but not (yet) kinematics that bleed.
- Headlight/night-driving handling plus final tire model refinement are **(PLANNED Phase 1.5)**; rewind is **(PLANNED 1.8)**.

---

## 8. AI & traffic

**IMPLEMENTED — ambient traffic**
- `scripts/world/traffic_spawner.gd`: keeps **15 AI cars** in a 300 m ring around the player, spawns off-physics `RigidBody3D`/kinematic proxies with `is_on_road` + `nearest_road_pos` targeting, follows `RoadPath`/path curves via `road_network_patrol`, despawns beyond 400 m, and distance-halts engine audio.
- Traffic is refilled/rotated per tick by `LivingWorld` (`scripts/world/living_world.gd`, deferred `_setup`, per-region dressing triggers, Terrain3D height provider for ground alignment).
- **Race AI / rival packs**: not implemented — `rubber_band_assist` is reserved in `game_state.gd` for **(PLANNED Phase 1.6)**.

---

## 9. Weather & time

**IMPLEMENTED**
- `scripts/world/weather_manager.gd` implements a **state machine**: CLEAR / CLOUDY / RAIN / STORM / FOG / SNOW, each with a `time_of_day` (fposmod 0–1), and **rain-based grip modifiers** so wet/snowy surfaces actually feel different:
  - `ROAD_GRIP`: CLEAR 1.0 · CLOUDY 0.98 · RAIN 0.80 · STORM 0.60 · FOG 0.95 · **SNOW 0.45**.
- `scripts/world/day_night_driver.gd`: **day = 2400 s** (~40 min), but `.tick()` exits early unless in the `open_world` group with the driving scene — menus/tracks are unaffected; weather selection rolls from weights (CLEAR .40 / CLOUDY .25 / RAIN .15 / STORM .10 / FOG .06 / SNOW .04).
- `scripts/world/regional_climate.gd`: **Seasons** (SPRING/SUMMER/AUTUMN/WINTER), per-zone **snowlines** (e.g. ALPINE_GRIP 0.30–0.45 by scenario), `pass_locked` being `WINTER` + band ≥ HIGHLAND; profiles blend season→weather per region.
- `scripts/world/sun_driver.gd` + `SunDriver` companion: a sun node that works even in non-open-world scenes; **Godot lights** in scenarios.
- Baked-in **weather VFX** (rain streaks, wet skidmarks, FOG density surfacing, snow particles) is the explicitly-called **(PLANNED Phase 1.5)** — today the switches and strengths are all wired; the particles/VFX live behind that phase.

---

## 10. Progression & economy

**IMPLEMENTED**
- **Persistence** exists for the map: `WorldDiscovery` visited roads/cells and `EventRegistry` allow "the game remembers where you got lost" between sessions (`user://` saves); `SettingsStore` persists video/audio/input choices.
- Progress reporting to `GameState.progress` from threaded world work.
- Car *selection* across menus works (you can live the garage fantasy), but **money, XP, and rep** are **not earned from races** yet.

**PLANNED** (from ROADMAP, explicit): Phase 2.1 — credits economy, licenses, championships, fictional-brand part/tunes market; Phase 2.2 — leaderboards, ghosts, goal-driven unlocks; unlock/difficulty tuning is scheduled after live-service content lands. **No grind-loop exists today.**

---

## 11. Performance & tech

**IMPLEMENTED**
- **Streaming world**: 256 m chunked loading (`chunk_streamer.gd`), 3×3 **live region storm** instead of a full map (`terrain_seeder.gd`), corridor pre-bake before spawn, and frame-budgeted application (≤2 regions/tick).
- **Terrain3D** (`addons/terrain_3d`): heightfield + colormap baked to RGBA8 (`terrain_baker.gd`), `collision_mode` set before region size to keep physics valid, `show_colormap` on.
- **MultiMesh dressing**: `prop_scatterer.gd` lays down guardrails/tents/power poles/rocks via MultiMesh; promises rejection-sampled clear of roads (`MAX_PLACEMENT_ATTEMPTS = 64`).
- **Foliage instancing**: `foliage.gd` grasses (700)/trees (40/region) through `MultiMeshInstance3D` with wind shaders (`res://shaders/grass_wind.gdshader`, `foliage_wind.gdshader`) and a denser (0.5 density) prefetch band for pop-in hiding.
- **World dressing budgets**: `region_dresser.gd` spawn/free caps (2/frame), `band_visibility` culling at distance, and idempotent re-entry.
- **Quality presets** in `settings_menu.gd`: **Low** all-off; **Med** SSAO + glow + SDFGI + MSAA×4; **High** + volumetric fog + SSR + FSR 2.2 (scale 0.9) + light probes; first-boot picks a profile from the GPU.
- Headless-friendly generation (`terrain_baker.gd` runs pure/bare in CI; atlas images written for later inspection).
- **PLANNED**: LOD/stadium-skipping for grand touring, GPU benchmark (3.3), detailed telemetry/metrics tools.

---

## 12. Accessibility & options

**IMPLEMENTED**
- Full **Settings Menu** (`scenes/ui/settings_menu.tscn`): audio (music/SFX/car audio volumes), **video/quality** (renderer-tier presets above, shadows, reflections), **input** (driving keys), **gameplay** (assists, torque/arcade vs sim toggles), **accessibility** (camera shake, gauge readability).
- **Assists layer**: traction control, steering assist, drift assistance — all togglable in the default `user://settings.json`.
- QoS: minimal reliance on audio assets (3-bed synthesized engine) keeps data-cheap; fast travel avoids long drives.

**PLANNED** (Phase 3.1): full **rebinding UI** + configurable input map in `project.godot` (defaults exist; rebind UI does not), colorblind modes, screen-reader semantics, and handedness options. Camera-shake intensity is present; a dedicated **reduced-motion** toggle is **(PLANNED 3.1)**.

---

## 13. Strengths & gaps

**Top-10 implemented strengths**
1. A **real, seeded, 60 km classified road network** — 12 corridors across arterial/highway/touge/coastal/dirt with hard invariants (`defs[0..2]`), not a hand-placed strip.
2. **Industry-grade streaming** — chunk streamer + 3×3 region storm + threaded pre-bake means a >2000 m relief alpine map runs on per-tick budgets.
3. **Surface-driven feel** — ASPHALT→SNOW grip table wired through `SurfaceRegistry`, roads recessed `ROAD_TOPPING`, wheel-level surface swaps; driving physics reads the world, not the reverse.
4. **Deterministic generation** — `MASTER_SEED`, per-region seed hashing, idempotent dressing: the whole world is a pure-ish function of one number, so saves/CI/toggles stay consistent.
5. **Living, breathing world systems** — 15 AI traffic cars, per-region foliage/props, `LivingWorld` re-dressing, day/night + seasonal climate with `pass_locked` logic tying events to regions.
6. **A coherent vertical slice UX** — main menu → track select → kiosk → garage (treats cars with real stats) → drive → results, wrapped in a fade stage manager.
7. **Race-authentic HUD** — revs/gear tach with shift-lights and class badges, minimap, fast-travel, discovery feedback (road whiten-as-you-drive).
8. **Sound design in code** — synthesized 3-bed engine audio means zero audio dependencies for a polished rev-band feel.
9. **Test discipline at the core** — 263 known-good automated tests across 30 scripts run headless in CI every change (see §14).
10. **Design-forward orientation** — every kernel decision (Sun, fixed 0.08 min elevation, chambers, quality tiers, math seeds) was made up-front; the code is alive with annotated intent and keeps the dream intact.

**Top-5 gaps**
1. **No racing AI or rivals** — traffic exists, but competitive opponents (and the reserved `rubber_band_assist`) are Phase 1.6.
2. **Events are seeded, not playable** — 10 sites + 5 POIs are placed and listed, but launchers/lead-ins/scoring/restart are Phase 1.4.
3. **No economy/progression** — zero credits/XP/rep; no ownership, no tuning market, no S-class car (Phase 2.x).
4. **Weather VFX missing** — states, grip, snowlines are live, but rain/storms/fog/snow particles and wet skidmarks are Phase 1.5.
5. **No rewind/replay, ghosts, or leaderboards** and no input-rebind UI (Phases 1.8 / 2.2 / 3.1) — the live-service "compare and improve" surface is yet to come.

---

## 14. Test discipline

**IMPLEMENTED**
- **30 GDUnit4 test scripts** (`tests/*.gd` = 10, `tests/suites/*.gd` = 20, plus `tests/suites/checkpoint_stub.gd` as a helper stub), covering: corridor planner invariants/lengths/surfaces, terrain baker height ranges + road carving, road conforming, POI/event placement rules, discovery reveal/cell math, weather/season transitions, surface registry, screen-transition state machine, minimap/map line geometry, settings-store persistence, and `CarConfig` defaults.
- **Known-good state: 263 test cases · 0 errors · 0 failures** (the CI baseline in `AGENTS.md`).
- Everything runs **headless** (`--headless`) so CI never needs a GPU/window; generation scripts hide behind pure functions exactly for this.
- **Workflow**: run the GDUnit4 CLI headless — a normal `--headless --import` probe pass first, then the GDUnit `-s` run with `--ignoreHeadlessMode` placed after the tool-script path (AGENTS.md "known-good"); expect the 263/263 summary line.

---

## 15. Soul of the game

> One desert hub, a sea kept near, two alpine crowns you can climb above 1000 m and then pour down — connected by a 25 km, cambered ring that binds a whole district of short-set cars, touge duels, drag strips, drift zones, and storm-lit snow lines. It's a **dream-racer protocol**: one seed makes the entire map; your save records what you discovered; weather, seasons, and traffic all negotiate over the same grip table the physics reads. The plan says it will become a *live-service universe* — but what's real **today** is that pressing Start drops you into a deterministically-built, breathing world that is already bigger, weirder, and more coherent than most "2-lane demo" racetrack proofs. Everything else — AI rivals, rewind, money, a leaderboard — the roadmap already insists will join it. This file is where "done" starts and "the dream" continues.