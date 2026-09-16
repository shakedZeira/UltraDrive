# UltraDrive — Self-Audit & Gap Analysis

Audit date: 2026-09-16
Engine: Godot 4.7.2 (Forward Plus, 1920×1080, res://scenes/main.tscn)
Method: read-only code/source survey (scripts, scenes, resources, tests). No game code was modified.
Baseline: GDUnit headless suite green — 144 test cases | 0 errors | 0 failures | 0 flaky | 16 orphans (benign).
Reference point for gaps: Forza Horizon / Gran Turismo class open-world & circuit racing.

---

## 1. Current capability inventory

### 1.1 Vehicles & handling
- 4-wheel raycast suspension on a `RigidBody3D` (`scripts/vehicle/vehicle_physics.gd`, `wheel_physics.gd`) with arcade/simulation handling modes.
- Pacejka Magic Formula tire model (`scripts/vehicle/tire_model.gd`) — slip-angle dependent lateral force, per-car coefficients.
- Drivetrain with auto (RPM-based upshift) and manual gearboxes, real reverse gear with speed cap, over-rev downshift guard (`scripts/vehicle/drivetrain.gd`).
- Data-driven config per car: `resources/cars/*.tres` (`CarConfig`, `scripts/vehicle/car_config.gd`) — mass, torque curve, 5–6 gears, spring/damper rates, tire `B/C/D/E`, drag/downforce, countersteer assist, handbrake grip reduction.
- 3 original cars (license-safe, built via the Blender-MCP / Hyper3D pipeline — a differentiator vs licensed titles):
  - Striker — D class, starter (no GLB visual).
  - Thunderhead — C class muscle (muscle_car.glb).
  - Dirt Devil — B class rally hatch (rally_hatch.glb).
- Visual dressing (`scripts/vehicle/car_visuals.gd`): GLB body swap per active car, clearcoat paint, wheel spin + front-pair steering, brake glow, per-car `ReflectionProbe` (UPDATE_ALWAYS), static probes for world landmarks (budget-capped at 4 blended).
- Procedural engine audio (`scripts/vehicle/car_audio.gd`): per-timbre multi-bed crossfade (idle/mid/top), RPM→pitch, load shaping; traffic audio distance culling.

### 1.2 Tracks & race loop
- `TrackRegistry` (`scripts/track/track_registry.gd`) with 2 circuit tracks: Sunset Oval (D, 3 laps) and Mountain Pass (B, 2 laps).
- Procedural road/track mesh + collision via `TrackBuilder` (`scripts/track/track_builder.gd`); the oval is also generated at runtime (`scripts/test_circuit.gd`).
- Full race loop (`tests/suites/test_race_loop.gd`, 14 tests): `RaceManager` autoload → checkpoint gating/caching/re-arm → `LapCounter` progression validation → standings ordering (lap → checkpoint → gate distance) → HUD finish banner with total time.
- Mountain Pass rests on `Terrain3D` with roads recessed into a washbed, terrain baking conforming under every road point.
- Drift scoring exists (`scripts/race/drift_scorer.gd`).

### 1.3 Open-world streaming & dressing
- Runtime-built `Terrain3D` (`scenes/world/open_world_root.tscn`, `scripts/world/terrain_seeder.gd`): 1024² regions, 3×3 live ring, prefetch ring (radius 2) re-primed after `set_roads()`. Player region bakes synchronously (~3.3 s); neighbours stream from a worker thread drained ≤2 regions/frame.
- Deterministic heightfield bake (`scripts/world/terrain_baker.gd`): seeded fBm + blended biome table, alpine dome, spawn plateau guard, spatial road-conforming carve.
- Road graph (`scripts/world/road_network.gd`): hub ring + mountain-pass connector + pass loop, closed-chamber detection.
- World dressing: `PropScatterer` (MultiMesh guardrails/tents/power poles/rocks, rejection-sampled off-road), `Foliage` (grass + trees, wind shaders), `TrafficSpawner` (max 15, road-spawned, deterministic).
- World UI: minimap + pause-map overlay with road rendering (`scripts/ui/minimap.gd`, `world_map.gd`, `map_roads.gd`) and POI dots (`scripts/world/poi_registry.gd`, 5 POIs on a 6144 m footprint).
- 24 h sun driver (`scripts/world/sun_driver.gd`) and weather (`WeatherManager` autoload): CLEAR/CLOUDY/RAIN/STORM/FOG/SNOW with per-state road-grip multipliers (snow 0.45 … clear 1.0).

### 1.4 Camera
- `scripts/camera/chase_camera.gd`: smooth follow/look, speed-based look-ahead, gear-shift FOV kick (gated as a “presentation” transient), safe always-on defaults.
- `scripts/camera/orbit_camera.gd`: right-stick 360° orbit around the car — an FH5/GT7-style garage/photo-feel base.

### 1.5 Career & economy
- `Garage` (`scripts/career/garage.gd`): owned cars, active car, persisted via `SaveManager`; 3D turntable garage UI.
- `Championship` (`scripts/career/championship.gd`): F1-style points standings.
- `LicenseSystem` (`scripts/career/license_system.gd`): B/A/S/Race/Elite tiers with Bronze/Silver/Gold ratings.
- Save system: 3 JSON slots (`autoload/save_manager.gd`), stores garage, settings, license results.

### 1.6 AI
- `scripts/ai/ai_controller.gd`: waypoint-follow with per-car speed multiplier rubber banding (`ai_rubber_banding.gd`). Traffic follows road paths.

### 1.7 Settings / rendering quality
- 3 quality presets (Low/Medium/High, `scripts/ui/settings_menu.gd` + `tests/suites/test_settings_presets.gd`) controlling SDFGI, SSAO, SSR, volumetric fog, glow, MSAA, ACES tonemap, FSR scaling, probe refresh. Global quality ladder in `GameState`/`SettingsMenu`.
- Environment is feature-rich for indie scope: SDFGI (4 cascades), SSAO, SSR, volumetric fog, glow/bloom, per-car + static reflection probes.

### 1.8 UI / flow
- Main menu (Play / Free Roam / Garage / Continue / Settings / Quit), track-select cards, pause menu with world map overlay, scene transition fade, Forza/GT-inspired gauge cluster (`scripts/race/tachometer.gd`, `%Cluster`), position/lap/time labels, minimap.
- Input: gamepad + keyboard, auto/manual transmission toggle (`GameState.transmission_mode`), manual shift on buttons 3/0, handbrake on RB.

### 1.9 Testing discipline
- GDUnit4 headless workflow documented in AGENTS.md (import probe → suite run). 144 tests across: race loop, transmission modes, vehicle physics, terrain baker/seeder/streaming, open world, track system, mountain-pass zone, prop scatterer, traffic, car visuals, car audio, settings presets, chase camera, weather/sun, reflection probes, world map features, save manager, race logic, input mapping.
- GDUnit gotchas (warnings-as-errors, same-type `is_equal_approx`) already captured in AGENTS.md.

---

## 2. Gap analysis vs Forza Horizon / Gran Turismo

Priorities: **P0** = biggest fun/quality jump for effort; **P1** = strong loop builder; **P2** = polish/scale-up. Rough effort in “dev-weeks” for a small indie team (1–2 people, existing architecture reused).

### 2.1 Improve — existing systems that are thin next to the reference class

| Theme | What exists | Gap vs reference | Suggested work | Effort | Priority |
|---|---|---|---|---|---|
| Handling depth | Pacejka lat/long + raycast suspension + countersteer assist | No per-wheel load transfer/anti-roll bars, no ABS/TCS modelling, no surface-type variance (asphalt/grass/gravel), no tire-wear/heat, near-static setup | Add surface grip lookup (grass/gravel/wet), optional ABS/TCS toggles, light lateral load transfer; keep arcade default | 2–3 wks | **P0** (feel is king) |
| Navigation & HUD | Minimap + map overlay + POI dots, cluster | No GPS route line to a destination, no race-line assist, no speed/lap-time deltas vs opponent/ghost, no wheelspin/damage indicators | Route computation on `MapRoads` graph; optional braking line; position-delta HUD; wheelspin "cone" indicator | 2–3 wks | **P0** (FH sells on this) |
| Car personalization | 3 cars, paint dresser, 3D turntable | No performance upgrades, no visual tiers, no stats bars, no tuning sliders, no buy/sell | Tuning sliders (gears/springs/downforce → mutate `CarConfig`), upgrade tiers; stats comparison UI in garage | 3–4 wks | **P0** (GT core fantasy) |
| Weather & time of day | 6 states w/ grip tables, 24 h sun | No precipitation VFX, no wet-road shader, no headlights/tail-lights at night, no fog particles | Rain/snow particle systems, wetness→reflection/road shader, night headlight layer, per-state sun/fog color | 3 wks | **P0** |
| Race modes & events | Circuit races only (2 tracks) | No sprint/elimination/time-attack/drift/checkpoint events, no event markers in open world | Event-type framework + destination markers on existing POI/map systems | 3 wks | **P0** |
| Career loop | License tiers + championship points | No currency, no rewards screen, no event unlock gating, no career stats | Credits + reward screen, unlock gates on license/champ, season standings persistence | 2–3 wks | **P1** |
| AI racing | Waypoint + speed rubber band | No drafting, no side-by-side, no skill variance, no traffic response to player | Overtake cooldown, drafting bonus, difficulty band per class, traffic brake-check | 2–3 wks | **P1** |
| Audio | 3-bed engine + load shaping | No tire squeal, skids, impacts, wind, UI SFX, music/radio | Skid/impact layers, UI blips, optional radio/music bus | 1–2 wks | **P1** (huge feel/$) |
| Rendering polish | SDFGI/SSAO/SSR/vFog/glow, probe budget 4 | Probe blending is a perf bandaid; no LOD for props/foliage; no benchmark-driven preset | LOD for scatter/foliage meshes, GPU benchmark → auto preset, contact shadows | 2 wks | **P1** |
| Refresh/dressing | 5 POIs, guardrail/tent/pole/rock | Thin identities; no buildings/landmarks worth visiting; scenery stops at ~null props | Add 2–3 authored landmark sets w/ POI gameplay; distance-faded skyline props | 3 wks | **P2** |

### 2.2 Add — present in the reference class, absent here

| Theme | Gap | Suggested add | Effort | Priority |
|---|---|---|---|---|
| Photo mode | Not present at all | Orbit cam already exists → add hide-UI, FOV/aperture sliders, filters, screenshot export | 1–2 wks | **P1** (free marketing) |
| Ghost / time-attack leaderboard | No lap timers vs self/others | Persist local best laps per track/car class; ghost car playback | 1–2 wks | **P1** |
| Collectibles | None | FH-style bonus boards / photo spots / speed traps as `POIRegistry` entries w/ rewards | 1 wk + design | **P1** |
| Rewind / reset-to-road | None (open world can get stuck) | Short rewind buffer or reset-on-track; crash recorder | 1–2 wks | **P1** (QoL save) |
| Full save robustness | 3 slots exist | Add auto-save on exit, slot copy/delete UI, settings+profile split | 1 wk | **P2** |
| World size & tracks | 1 open-world zone + 2 circuits | A 2nd zone reuses seeder/baker/road pipeline (different biome via existing biome table) | 4–6 wks | **P2** (content) |
| Multiplayer | None | Out of scope for indie; note as future (LAN split-screen cheapest) | — | Post-v1 |
| Accessibility | None | Aim: steering assist, controller deadzone, screen-shake/vignette toggles | 1–2 wks | **P2** |

---

## 3. Technical debt / risk notes

- **Starter car has no GLB visual** (`starter_car.tres` lacks `visual_path`; `player_car.tscn` body is empty until `_apply_visual` swaps in the garage’s active car). On first-launch default flow the Striker is a config-only car — verify the default active visual is always the SportsCoupe instance, else the player sees an invisible car. (AGENTS.md implies the default is the `SportsCoupe` instance.)
- **Terrain3D headless hang risk**: a script error during a headless diag leaves Godot hanging — watchdog discipline is required in CI, already enforced by AGENTS.md workflow.
- **Open-world streaming vs dressing mismatch**: terrain/region culling is mature; props/foliage/traffic are spawned once (rejection-sampled) rather than region-streamed — will be a load/perf bottleneck if the world grows.
- **Quality ladder is manual**: presets are code-driven; a runtime GPU benchmark that auto-selects a preset would protect the “feels smooth” bar across machines.
- **Victory condition scope**: championship/license are functional but the exit loop (rewards → garage spend → unlock) is not wired, so progress has no economy to sink into.

---

## 4. Suggested roadmap (P0 first)

1. **Feel & loop (P0):** surface-type grip + ABS/TCS assists → GPS route + optional race line → tuning sliders + upgrade tiers in garage → event-type framework wired to POI markers.
2. **Environments (P0):** weather VFX + wet road + night headlights → 2nd biome zone using the existing bake/road pipeline.
3. **Loop glue (P1):** currency + rewards + unlock gates; ghost/time-attack + local leaderboards; rewind/reset; radio/music + skid/impact audio; auto quality preset via benchmark.
4. **Marketing surface (P1):** photo mode; collectibles.
5. **Content & polish (P2):** visual LOD, landmark sets, more tracks/zones, save UX, accessibility.

**North star:** keep the license-safe original-car pipeline and deterministic world-gen as franchises; spend the next cycle on *progression + navigation + weather visuals*, which are the three things that make the reference titles feel alive and are achievable at indie scale here.