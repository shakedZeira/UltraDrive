# Feature Comparison — Forza Horizon 6 vs Gran Turismo 7 vs UltraDrive

> Rigorous side-by-side comparison compiled from three source dossiers:
> `fh6_features.md`, `gt7_features.md`, `ultradrive_features.md` (read-the-codebase), plus context from
> `world_compare.md`, `competitors.md`, `self_audit.md`, and `docs/ROADMAP.md`.
>
> **Confidence markers:** keeping ⚠ as-is from source dossiers (fan estimate / single-source / not
> officially confirmed). UltraDrive cells are marked **IMPLEMENTED** (verified live in the codebase
> today) vs **(PLANNED Phase X)** (roadmap ambitions — explicitly NOT attributed to today's build).
>
> **Honest framing up front:** this is an indie Godot 4.7 open-world racer (a playable vertical slice)
> compared against a 9th-gen AAA arcade-sim and a 4-year, 39-update AAA sim. Where UltraDrive wins it
> wins on architecture and discipline, not budget. Where it loses, the loss is scope — and the roadmap
> already names each item.

---

## 1. Overview & positioning

| Dimension | Forza Horizon 6 | Gran Turismo 7 | UltraDrive (what it has TODAY) | UltraDrive vs BOTH (gap / advantage) |
|---|---|---|---|---|
| Engine | ForzaTech (Turn 10 family, shared with Forza Motorsport) | Proprietary Polyphony engine (25-yr lineage; sim-cade, "The Real Driving Simulator") | Godot 4.7, Forward+ renderer, **Jolt** physics (`project.godot`, `addons/jolt_physics`) | **S–M.** Jolt is credible; neither rival runs Godot. What's missing is 25 years of tuned feel, not the engine class. |
| Scope / genre | Open-world racing, fictionalised Japan ("Discover Japan") | Simulation + car-culture resort: café, museums, Scapes, career tracks | "Hybrid open-world + circuit racing game" (`project.godot` description) — open world + 2 dedicated tracks | **S.** Same hybrid genre both rivals occupy. |
| Platforms | Windows, Xbox Series X\|S; PS5 promised "later in 2026" but contested as of Sep 2026 | PS4 + PS5 (cross-gen), PSVR2, PS5 Pro enhanced | PC/desktop Godot export; no console or online services today | **L→XL** (real, but roadmap de-scopes it; LAN/split-screen flagged as cheapest future wedge). |
| Release & cadence | 2026-05-15 Premium early access / 2026-05-19 full; Game Pass day one; 5 live-service series by Sep 2026 | 2022-03-04; still live — **v1.71 (2026-08-20) = 39th content update** | No release date; playable vertical slice; headless-CI green pipeline | **XL** on polish budget; **None** on being a moving target — UD ships when its 263 tests say so. |
| Content size | ~100 GB ⚠ (vs FH5 ~116 GB) | Not published (cross-gen install) | Data-cheap by design: synthesized 3-bed engine audio = zero audio assets; procedural terrain | **Advantage (None).** UD's entire content budget is a fraction of one FH6 DLC. |
| Launch momentum | **6M+ players in week one**; 270K+ Steam peak ⚠; IGN 10/10, ~90 Metacritic | Series crossed **100M cumulative units** in 2025 ⚠ (Polyphony PR) | Zero players — pre-alpha | **XL.** Not comparable; not the point of this phase. |
| Save / network model | Cross-save + cross-play Xbox/PC/PS5 (series first) | Always-online save model (only Arcade runs fully offline) | Local 3 JSON save slots (`autoload/save_manager.gd`), user:// settings, persisted discovery/events | **M (in UD's favour).** UD is fully offline-capable, never anticheat-gated. |

## 2. World & map

| Dimension | Forza Horizon 6 | Gran Turismo 7 | UltraDrive (what it has TODAY) | UltraDrive vs BOTH (gap / advantage) |
|---|---|---|---|---|
| World format | One continuous open world (Japan) | Stylised world-map hub; tracks accessed from it | One continuous open world + 2 separate circuit tracks (`open_world_root.tscn`, `mountain_pass.tscn`, `test_circuit.tscn`) | **S.** Shape matches FH6, not GT7's hub — the right call for an open-world racer. |
| Size | ****No official km²****; fan estimates ~**122–246 km²** ⚠; ~21 miles (~34 km) N–S (press); Tokyo ~5× FH5's Guanajuato | Not applicable (hub + 41 locations / 84 layouts / 121 configs ⚠) | **60 km road-network budget** (`KM_TARGET = 60.0` in `corridor_planner.gd`); 12 classified corridors; nominal 0–6144 tile footprint; HEIGHT_MIN −8 → HEIGHT_MAX 2000 m | **L.** A ~246 km² ⚠ landmass vs a 60 km drivable route is an order-of-magnitude gap — but FH6's own pitch is "density over size", and UD's 60 km is a measured number, not marketing. |
| Regions / biomes | **9 base regions + Legend Island**; 5 biomes + Tokyo (common framing; 6-biome rubric in `fh6_map.md`); 74 districts (official) / 10 regions (achievement) | 3 track continents (Americas; Europe/Middle East; Asia-Oceania) | **6 numeric elevation bands** (SEA / PLAINS / ROLLING / LOWLAND / HIGHLAND / ALPINE) but **ONE visual biome** in the open world (colour map only baked on the standalone mountain pass) | **L (cheap to close).** The biome *table* and bake seams exist in `terrain_baker.gd`; open-world colour baking is a P1 item (W.1/Roadmap 2.5). |
| Elevation / verticality | Sea level → **~3,000 m** Alps ⚠ press ≈; series-tallest vertical axis; stacked urban planes (street → expressway → tunnel) in Tokyo | Yas Marina: 11 m elevation change, 16 corners, longest straight 1,233 m (official) | **~1,100 m of real alpine relief**; two alpine domes (amp 1100 m / 850 m); pass climbs above 1000 m | **M.** Relief is real and driveable (touge corridors wrap the domes). No stacked-urban verticality — no city geometry exists (world_compare P2 north-star). |
| Density / POIs | 796 map markers across 38 categories ⚠; 74 districts; 75 landmarks ⚠ | 41 locations/121 layouts ⚠; ~2,570 Scapes photospots ⚠ | **15 discoverable places**: 5 anchor POIs (`poi_registry.gd`) + 10 lazily-appended event markers | **L.** Correct mechanism (lazy, deterministic POI placement), roughly 5% of FH6's marker count. |

## 3. Roads & terrain

| Dimension | Forza Horizon 6 | Gran Turismo 7 | UltraDrive (what it has TODAY) | UltraDrive vs BOTH (gap / advantage) |
|---|---|---|---|---|
| Road count | **671** in-game discovery counter ⚠ (662 pre-Legend-Island); press preview "673" didn't hold; Red Bull rounds "700-plus" | Tracks, not roads: 41 locations / 121 configs ⚠ | **12 classified corridors** (`corridor_planner.gd`): 5 arterial, 1 highway ring (~25.7 km, w16, banking 0.35), 2 touge, 2 coastal, 2 dirt (gravel, w7) | **XL by count** (671 vs 12); **S/M by structure** — UD already has 5 classes where FH6 has 4 tiers. The unit isn't apples-to-apples (FH6 counts named subroads), but count is a real deficit. |
| Road hierarchy | **4 tiers**: urban expressways (C1 ~14.8 km elevated, Shuto ~10+ km, Wangan), touge passes (Mt. Haruna + 5 official Touge Battle routes), coastal/scenic, rural/dirt lanes | Circuit hierarchy instead: Gr. classes + tyre compound gates per track | **5 classes** (arterial / highway / touge / coastal / dirt) with per-class width, banking, surface | **M.** UD's taxonomy already beats FH6's 4-tier structure on paper; what's missing is *topology* (junctions) and sheer count. |
| Surface types | Asphalt dominates; dirt in farmland/coastal/cross-country (ratio unpublished) | Track surfaces + off-track (Grip Reduction Off Track = "Real" rebalanced v1.71); dirt/snow compounds | **SurfaceRegistry grip table**: ASPHALT 1.0 · CONCRETE 0.92/0.95 · GRAVEL 0.85 · DIRT 0.65/0.70 · GRASS 0.55/0.58 · SNOW 0.35/0.30; roads recessed `ROAD_TOPPING` 0.15 m | **S.** Per-surface grip is live physics here; FH6 publishes no numbers and GT7 gates by compound. UD's wheels change grip the moment they leave the topping. |
| Junction graph / topology | Implied (chain of 74 districts, 671 named roads) | N/A (point-to-point circuits) | **No node/edge graph** — chains + splines (`road_network.gd`); the connector "lands on" the pass loop; no junctions, no over/under passes | **L.** Graph topology is the missing substrate for GPS routing and event congestion (roadmap **W.0**). |
| Discovery / fog-of-war | **First in franchise**: roads grey→white (driven) / orange (route); regions reveal by driving through; Fast Travel Boards removed | N/A (hub menu, fixed track availability) | **IMPLEMENTED**: `WorldDiscovery` per-segment visited bitset (30 m cells, reveal 90 m), grey→white map reveal, **fast travel to discovered POIs** via shared static `route_target` | **M (lean, close).** Core loop exists. No GPS *route line* yet (roadmap 1.2 / W.5 — FH6's #1 map feature). No autodrive. |
| Fast travel | **Free from start, gated by fog-of-war** — teleport to any discovered road point; Fast Travel Boards removed | N/A per se; event gates unlock tracks | **IMPLEMENTED**: pause-map click-to-fast-travel on discovered waypoints (`world_map.gd`) | **S.** Same reward-gating philosophy on a smaller map. |
| Road markings / signage | Implied (fully modelled Japanese roads) | Curbs and trackside objects standard | Road markings/signage, potholes/surface damage, gravel churn **(PLANNED Phase 1.7)** | **L.** A core "believable road" gap named in the UD dossier. |

## 4. Vehicles & garage

| Dimension | Forza Horizon 6 | Gran Turismo 7 | UltraDrive (what it has TODAY) | UltraDrive vs BOTH (gap / advantage) |
|---|---|---|---|---|
| Car count | 550+ official; **618** community-checked at launch (87 mfrs); **636** official Aug 2026; 642 tracker ⚠; ~162–163 JDM ⚠; 24 Forza Edition | **~583** after v1.71 ⚠ (579 v1.70 + 4; kudosprime 579, victorydash 570, GTDB 560 stale) | **6 cars**, D–A classes: Striker (D), Thunderhead (C), Dirt Devil (B), Comet (C), Hooligan (B), Interceptor (A); **no S-class** | **XL.** Roster size is the *least defensible* metric (competitors.md) — UD must win on depth of a curated set, not count. |
| Vehicle sourcing / licensing | Real-world licensed (87 mfrs; Car Pass 30 weekly) | Real-world licensed (Brand Central / Used / Legend / Power Pack) | **Entirely license-safe**: original GLBs (Blender-MCP/Hyper3D pipeline) + CC0 Kenney kit; cars are data (`resources/cars/*.tres`) | **Advantage (None for rivals).** UD ships forever with zero OEM licence cost/takedown risk. The single biggest structural edge. |
| Customization depth | **Headline overhaul**: per-car Forza Aero, **window liveries**, 100+ new rims (separate front/rear), body kits (Liberty Walk / Rocket Bunny / Origin Lab), upgrade presets, engine swaps incl. motorcycle-into-Kei, race gearboxes, camber/toe/caster, tyre width/pressure/compound | GT Auto: widebody kits, wheel fitment, **engine swaps (CL50)**, Car Valuation; Livery Editor with brand/partner decals & wheel brands | Paint-from-resource + wheel spin/steer only; full garage customization (visual kits, wheels, livery, tuning/upgrade parts, S-class) **(PLANNED Phase 1.3+)** | **XL.** This is "the product" for both franchises. UD's data-driven `CarConfig` is the right foundation; UI + mutation + part economy are unimplemented. |
| Tuning / setup | Race transmission, suspension camber/toe/caster, anti-roll, diffs; PI 100–998 across 7 classes (D→R, R replacing X ⚠) | **PP (Performance Points)** — one blended number fed by power, weight/ballast, aero, compound; rebalanced fleet-wide at every physics patch (1.31/1.49/1.55/1.71) | `CarConfig` holds mass/torque/gears/shift tables/diff; arcade↔sim modifier dicts; **no player-facing tuning sliders** (PLANNED 1.3) | **L.** Sliders = "UI + mutation over existing config" per roadmap 1.3 — a well-priced gap. |
| Garage / ownership | **8 purchasable houses, each a customizable garage** (start with Mei's) showing up to 4 cars; The Estate open-world build; Forzavista per-car; Autoshow dealership | Garage + Collection Book + Collector Level (CL 50→70 in v1.65); Used Cars 30/day; Legend Cars ~10–11 at a time / ~92 distinct ⚠ | `Garage` owns car list + active car, persisted via SaveManager; **rail-card carousel UI with turntable + 6 real stat bars** (Forza/GT-style) | **L.** The shell is genuinely rivals-adjacent (self_audit calls it "the FUN files"); ownership/purchase/economy flows are (PLANNED 2.1 / 1.3). |
| Livery / paint | Window painting (series first), vinyl import from prior Forza, paint favourites | Livery Editor, online-shared decals, replica downloads | Plain paint-from-resource only; livery editor + vinyls **(PLANNED Phase 1.3+)** | **L.** No livery = no community-identity surface yet. |

## 5. Physics & driving model

| Dimension | Forza Horizon 6 | Gran Turismo 7 | UltraDrive (what it has TODAY) | UltraDrive vs BOTH (gap / advantage) |
|---|---|---|---|---|
| Tire / core model | ForzaTech sim at **~360 Hz** tire/geometry ⚠ (engine-wide property; per-title tuning differs) | v1.71 rewrote the tire algorithm around "simulation of tyres slipping"; rolling resistance, heat/wear, off-track grip "Real"; 4 major overhauls (1.31/1.49/1.55/1.71) | **Pacejka Magic Formula** (`tire_model.gd`) + 4-wheel VehicleWheel3D springs/dampers; grip fed by `SurfaceRegistry` + `RegionalClimate` | **M.** A real Pacejka model vs two proprietary rigs — structurally credible; missing: heat/wear, lateral load transfer, ABS/TCS modelling (P0 in self_audit). |
| Assists | ABS/TCS, steering assist, suggested line, rewind, Tourist Drivatar (wins every race), offline game-speed reduction | Assist Presets Beginner/Intermediate/Expert/Custom; TCS 0–5; ABS Off/Weak/Default; **Auto-Drive** Off/Brake/Brake&Steering; ASM; Counter-steer Off/Weak/Strong | Traction / steering-assist / drift-assist toggles, arcade↔sim handling-mode switch, throttle mapping | **S.** The assist *layer* exists; ABS/TCS depth is a Phase 1.1 addition. |
| Transmission | Auto/manual; full gear-ratio editing on race gearboxes | Auto/Manual + forced-downshift behaviour (v1.71); gear HUD; MFD | **Auto** (RPM upshift at 0.92× redline) + **Manual** (shift-up button 3, shift-down button 0; E/Q keyboard); **real reverse gear** (cap 25 km/h); over-rev downshift guard | **S–M.** Manual + reverse-as-real-gear already shipped (D5); no clutch or ratio editor. |
| Handling modes | Horizon-arcade feel + per-event Race Customizer (11 drivatars, traffic on/off, camera lock, weather/season/TOD) | Sim depth: PP regulation, BoP vs tuning, "Championship" mechanical damage (v1.71), tyre-wear/fuel multipliers 1×–10× | Per-car arcade/sim modifier dicts (steering speed, counter-steer, drift assistance); `handling_mode` switch; grip drops with altitude into alpine snow lines | **S–M.** Modular and world-aware; rivals win on event configurability and damage modelling. |
| Damage / degradation | Not spotlighted in FH6 dossier | Light/heavy/off + **"Championship" mechanical damage** (v1.71); tyre wear & fuel 1×–10×; weather affecting line | None | **L.** No damage/wear model — a GT7 signature absent. |
| Feel-calibration cadence | Series 3 (Jul 2026) Drivatar + steering-feel balance patch (community-praised) | **Evergreen feel**: PP rebalanced fleet-wide per patch; Circuit Experience times re-shot after 1.49 & 1.71 | Physics is fully data-driven; config-level tuning; not yet a "revisit each cycle" discipline | **S (philosophy).** Data-driven config makes per-cycle recalibration cheap — the GT7 lesson is already architected. |

## 6. AI & traffic

| Dimension | Forza Horizon 6 | Gran Turismo 7 | UltraDrive (what it has TODAY) | UltraDrive vs BOTH (gap / advantage) |
|---|---|---|---|---|
| Race AI | **Drivatars** — cloud behaviour-capture, name-stamped from real players, up to **11 per event**; hard-AI "cheating" + rubber-banding complaints patched in Series 3; the famous griefer Drivatar "bowie knife99" | Standard AI = rubber-band model (throttles to ~90%, races outside player PP rules) ⚠; **16-car field cap**; **GT Sophy** = deep-RL (QR-SAC) expert AI, PS5-only, gated (Custom Race, 500+ cars) and $29.99 ⚠ Power Pack (3.0) | **No race rivals.** Ambient traffic only (**15 AI cars, 300 m ring**, road-following via `LivingWorld` + `traffic_spawner.gd`) | **L** today, but named **the cheapest competitive edge** (competitors.md): readable, no-rubber-band AI beats a legacy Drivatar and a paywalled Sophy. Roadmap 1.6 (`ai_controller.gd`, reserved `rubber_band_assist`). |
| Traffic | Denser than FH5 per comparisons ⚠; Street Races keep **live traffic on**; convoys up to 12 | Minimal ambient traffic (race-focused world) | **IMPLEMENTED**: 15 cars, road-spawned via `is_on_road`, despawned past 400 m, distance-halted audio | **S–M.** A real traffic simulation GT7 barely does; FH6 has more density. |
| Rivals / ghosts | Rivals per discipline incl. touge; ghost-only (no collisions); reward cars | Sport time trial + Lap Time Challenges; ghost rides | None (ghosts + local leaderboards PLANNED 2.2) | **M.** The compare-and-improve surface (ghost rival, sector/delta display) both competitors ship. |
## 7. Game modes & events

| Dimension | Forza Horizon 6 | Gran Turismo 7 | UltraDrive (what it has TODAY) | UltraDrive vs BOTH (gap / advantage) |
|---|---|---|---|---|
| Career / campaign | **Two parallel tracks**: Horizon Festival (7 Wristbands, Gold → Legend Island) + Discover Japan (7 Stamp ranks, Gold = 20,000 pts) + Horizon Play badges to Level 100 | **GT Café**: 39 main Menu Books + Bonus/Extra/Seasonal Menus post-MB39; serves as the career spine with story vignettes | Free Roam, Track Select (2 circuits), per-map Kiosk/Race Setup, results. `Championship` (points standings) + `LicenseSystem` (B/A/S/Race/Elite, Bronze/Silver/Gold) classes exist but are **not wired into an economy** | **L.** The *career containers* exist (championship + licence classes) but have no rewards loop to move the player forward (roadmap 2.1). |
| Race types / events | Road 22 · Dirt 21 · Cross-Country 19 · Street 15 (night, live traffic) · Touge 5 · Time Attack 4 · Drag 3+3 strips · PR stunts ~111 (20+20+30+30+11) · Horizon Rush 3 · Showcases 2 · Colossus (Goliath, ~50 mi ⚠) | Quick Race, Time Trial, Drift Trial, Custom Race (20-car fields), Circuit Experience, Missions (pass battles, drift/brake, Tsukuba One Hour), Music Rally (12 total), Weekly Challenges (5/wk) | **Full circuit race loop** (RaceManager → checkpoints → lap counter → standings → finish banner) on 2 tracks; `drift_scorer.gd` exists standalone; **10 event SITES placed** in the open world (touge duel, drag strip, marathon highway, drift zone, night street loop, 5× time-attack anchors) but **not launchable** | **L.** The event engine skeleton is 90% there; launchers/lead-ins/scoring/restart are (PLANNED Phase 1.4). |
| Signature / special modes | Touge Battles (5 preset routes, 1v1 lead/chase), Drag Meets (3 no-load strips, up to 12 players), Time Attack (sector PB, live delta, in-world leaderboards), Stunt Party, Drift Attack, Spec Racing, Eliminator (72) + Hide & Seek (1v11) | Sophy Quick/Custom Races, VR mode (PSVR2), Music Rally, Paddock lobbies, Broadcast Mode, 4-player split-screen (PS5 Spec II) | Racing loop only; no drift/touge/drag *leagues*, no VR, no splitscreen, no special modes | **XL for features, M for mean-replacement.** UD's 10 placed sites map 1:1 onto FH6's culture events; the gap is wiring them playable (1.4), then scoring layers (2.2). |
| Event-authoring / sandbox | EventLab + Horizon CoLab (6 event types; ~120 conditions / ~150 actions ⚠; up to 500 props ⚠; 12-grid start ⚠); The Estate world-build | **No track editor** — Showcase sharing of liveries/photos/replays only; tuning is the meta layer | None (no editor; scenario dressing is code-driven) | **XL.** Multiplayer co-building is the most expensive system both run; UD correctly de-scopes (post-v1). |
| Race-day variety | Race Customizer unlocks after one event: laps, weather, season, TOD, 11 drivatars, rewind, camera lock, traffic on/off | Custom Race: AI assignment, names/nationalities, full rules, 20-car fields, weather/compound/fuel events | Laps selectable per track (registry `laps_default`); no weather/season/TOD override, no grid customisation | **M.** Per-event parameter surface is thin (roadmap 1.4). |

## 8. Menus & UI

| Dimension | Forza Horizon 6 | Gran Turismo 7 | UltraDrive (what it has TODAY) | UltraDrive vs BOTH (gap / advantage) |
|---|---|---|---|---|
| Main / pause structure | 7 pause tabs (Campaign / Horizon Play / Creative Hub / Cars / Map / Festival Playlist / Settings); weather map filters (D-pad-right) | World-map hub with ~15 pavilions + Event Directory (all career events + completion %); MFD in race | Main menu (Free Roam / Track Select / Settings / Quit); pause (Resume / Restart / Settings / Map / Quit); per-map Kiosk screen; scene-transition fade | **S–M.** Browsable, purposeful menus already rival-shaped; no Creative Hub / Playlist / Collection equivalents yet. |
| Map screen | Fog-of-war world map, region toggle, category filter, fast-travel cursor on discovered roads | World Circuits (continental grouping), Event Directory | **World Map** (pause): fit-all, north-up, grey→white reveal, POI fast-travel; minimap with 4 m redraw threshold | **M (close).** The reward layer (GPS route line, discovery milestones, filters) is missing; the renderer is done. |
| HUD | Speed/revs/tach, minimap, position, timings, gear, assists; **Car Proximity Radar**; cockpit drift-cam; HUD size/opacity | Minimal HUD + MFD (traction/brake/power, EV maps, tire info, race info toggles) | **Forza/GT-style cluster**: revs/gear/speed, shift-lights, class badge, position/lap/time + gap timers, minimap; class badge from `car_class` | **S.** The HUD is the most rivals-adjacent surface in the build (self_audit "FUN files"). |
| Garage UI | Pause → Cars → (View/Manage/Customize); visit houses with Garage-Layout browser + community downloads + earn credits for layouts | Garage inventory with filter/sort; handling explanation texts | Rail-card carousel, 6 stat bars rendered from real `CarConfig`, turntable preview | **M.** Present and attractive; needs tuning sliders + part/upgrades UI (1.3). |
| Photo mode | Standard suite; 21 fixed photo-stamped locations; (PC controls regression — mouse removed vs FH5) | **Scapes**: ~2,570 photospots ⚠ / ~60 countries; raw-image 4K export; Showcase sharing | None (orbit camera exists; photo mode PLANNED 2.4) | **L.** Marketing surface for free rides on `orbit_camera.gd` (self_audit). |
| Localization / CX | English + per-platform languages (independent select) | Near-daily localisation patches | Localization framework scaffolded in `project.godot`; localized content **(PLANNED Phase 3.2)** | **S.** Scaffold is the hard part; content follows. |

## 9. Weather & time

| Dimension | Forza Horizon 6 | Gran Turismo 7 | UltraDrive (what it has TODAY) | UltraDrive vs BOTH (gap / advantage) |
|---|---|---|---|---|
| Day/night cycle | Full cycle ~**60 min** (~40 day / ~20 night) ⚠; shortcuts/events advance time | Real-time TOD loop with **1×–5× time-progression rates** (Custom Race); dynamic lighting & drying line | **IMPLEMENTED**: day = 2400 s (~40 min) via `day_night_driver.gd`; `.tick()` runs only in the `open_world` group; menus/tracks unaffected | **S.** A real clock already; FH6's ~60 min ≈ UD's ~40 min day. `.tick()`-gating is the one quirk to keep or revisit. |
| Region / forecast | Dynamic **regionalised** weather (not FH5 biome-fixed); ⚠ "72 weather micro-stations" single-source; Alpine keeps permanent snow | Dynamic weather with radar + forecast for pit strategy (Custom Race); wet line + **hydroplaning** since v1.49; rain affects AI less than player ⚠ | **Regional climate** (`regional_climate.gd`): 5 region bands, seasonal snowlines (ALPINE_GRIP 0.30–0.45), `pass_locked` = WINTER + band ≥ HIGHLAND | **S–M.** Region + season + a snow-locked pass is genuinely FH6-style design — arguably already a differentiator over GT7's circuit-scoped weather. |
| Weather states | Seasonal + per-region; Race Customizer varies it per event | Weather selector + variable rate; compounds react to wet/dry | `WeatherManager` state machine: CLEAR / CLOUDY / RAIN / STORM / FOG / SNOW with **grip modifiers** (CLEAR 1.0 · CLOUDY 0.98 · RAIN 0.80 · STORM 0.60 · FOG 0.95 · SNOW 0.45); roll weights CLEAR .40 … SNOW .04 | **S.** The *state machine and grip consequences* are live; VFX (rain streaks, wet skidmarks, fog, snow particles) is **(PLANNED Phase 1.5)**. |
| Grip / visibility effects | Approx tables ⚠: dry 100% → heavy snow ~50% → ice ~30% grip; winter punishes RWD, AWD more valuable; snow tyres meta | Wet racing-line grip loss, hydroplaning, compound-dependent behaviour; off-track "Real" rebalanced v1.71 | Grip table read by physics via `SurfaceRegistry`; altitude→grip interplay via `RegionalClimate`; `pass_locked` blocks winter highland routes | **Advantage (S).** FH6's ⚠ tables and GT7's v1.71 tuning are matched in kind — UD's numbers are deterministic and tested. |

## 10. Audio

| Dimension | Forza Horizon 6 | Gran Turismo 7 | UltraDrive (what it has TODAY) | UltraDrive vs BOTH (gap / advantage) |
|---|---|---|---|---|
| Car audio | Upgraded modular engine systems: turbo + backfire chatter, surface-interaction detail, improved cockpit impulse responses; **Triton Acoustics** spatial reverb | **1,700+ vehicles recorded**, 50+ mic types trialled; source-record + synthesis pipeline (GDC talk); crossfaded engine/exhaust/tire/transmission stems | **Synthesized 3-bed engine audio** (~0.95 / 1.6 / 2.6 kHz beds, RPM→pitch, load shaping, low-pass sweep) via `car_audio.gd` — **zero audio assets** | **M.** Different in kind, not lesser in intent: GT7's 50-mic captures are un-clonable at indie scale; synthesis is UD's license-safe analog. Missing: skids/impacts/wind/UI (PLANNED 1.7). |
| Music / radio | **9 stations, 224+ tracks** (largest licensed soundtrack in series); DJ hosts; Gacha City / Sub Pop / Opus new | **300+ tracks from 75+ artists**; Music Rally makes music a *mechanic*; Music Replay regenerates camera cuts per track | No radio/music bus (optional radio/music layer PLANNED 1.7) | **L.** Licensing 224+ tracks is out of reach; an original/CC0 radio shell is the sensible equivalent. |
| UI / feedback | Crowds step-charted; ambience layered via Triton | Cassette/UI SFX standard; Broadcast-mode commentary | UI blips/feedback largely absent (PLANNED 1.7) | **M.** Cheapest feel/$ item on the roadmap. |

## 11. Progression & economy

| Dimension | Forza Horizon 6 | Gran Turismo 7 | UltraDrive (what it has TODAY) | UltraDrive vs BOTH (gap / advantage) |
|---|---|---|---|---|
| Core loop | **3 pathways**: Wristbands (Purple ≈ 32,500 pts), Stamps (Gold = 20,000 Discover-Japan pts) gate Barn Finds/property; Horizon Play badges to 100 | Café Menus + Collector Level (cap 50→70 v1.65) + Licence Center + Missions; Weekly Challenges post-game (~**1.3M credits** clean sweep) | Car selection + discovery persistence + settings save; **no money/XP/rep earned from races**; no rewards screen, no unlock gating wired | **L.** This is the single largest *fun* gap: UD has `Garage`/`Championship`/`LicenseSystem` classes but no economy to sink into (self_audit "victory condition scope"). Roadmap 2.1. |
| Currency & acquisition | Autoshow (~360 of 618), Wheelspins/Super Wheelspins, Barn Finds (15, stamp-gated), Treasure Cars (9), Aftermarket (31 spots), Festival Playlist, Loyalty; **Car Vouchers** real-money $4.99/4 · $9.99/10 · $19.99/24; Auction House (15% fee, buyout cap 20M) | Brand Central / Used Cars (30/day) / Legend Cars (Cr up to **20,000,000** each; Hagerty-scaled) / roulette tickets (Daily Workout 26.219 mi/day) / invitations; real-money credit bundles ⚠ up to ~$100 / 20M ⚠ | Credits/economy entirely **(PLANNED Phase 2.1)**; car *selection* works, acquisition does not | **L.** Both competitors monetize exactly where UD refuses to — the no-paywall ethos (PLANNED 2.1 + 3.5) is the intended differentiator. |
| License / education | Race Customizer + wristband class gating (start C-qualified; Hypercars blocked until Purple) | **Licence Center: 150 tests + 50 Master tests** (5 Master Licences); Circuit Experience per track; brand history museums + designer cameos | `LicenseSystem` (B/A/S/Race/Elite tiers, Bronze/Silver/Gold ratings) **exists as a class but is not staged as a career gate** | **M.** The GT7 "education-first" framing has a scaffold in code; missing the staging + rewards. |
| Live-service / retention | **Festival Playlist**: 4-week series, weekly season rotation (Thu 09:30 EST), 20/40/60/120-point ladder, Series History rewards; economy controversy (Sep 2026: cap-raise locked casuals out) | Monthly free drops (39 updates), Weekly Challenges, Power Pack (paid, PS5, 50 events/20 categories, +Cr 5M), esports seasons | None. **(PLANNED Phase 3.5)** monthly content skeleton — data-only `.tres` packs | **L.** Cadence is table stakes for AAA retention; UD plans the skeleton deliberately without monetized grind. |

## 12. Accessibility & options

| Dimension | Forza Horizon 6 | Gran Turismo 7 | UltraDrive (what it has TODAY) | UltraDrive vs BOTH (gap / advantage) |
|---|---|---|---|---|
| Headline accessibility | **Granular High Contrast** (in-gameplay), **Car Proximity Radar**, **AutoDrive** (ANNA), ASL+BSL, Tourist Drivatar, offline game-speed reduction, story auto-complete, colour-blind filters, HUD scaling/opacity, button-hold remap, single-stick play | Assist Presets, Auto-Drive (Brake / Brake&Steering), Driving Line + Braking Indicator, ASM, Counter-steer, text chat transcription, pause anywhere (offline), 3D audio | Settings menu with input/gameplay/accessibility tabs; camera-shake toggle; traction/steering/drift assists; gauge readability | **M.** Assists + a real accessibility tab exist today; the *launch-blocking* FH6 slate (high contrast, proximity radar, auto-drive, colour-blind, remap UI, reduced-motion) is mostly **(PLANNED Phase 3.1)**. |
| Rebind / input | Full remapping (button-hold remap, adjustable sensitivity) | "Advanced" controller/wheel mapping, wheel auto-config | Default bindings documented; **rebinding UI absent** (PLANNED 3.1) | **M.** Defaults exist in `project.godot`; the UI is the delta. |
| Difficulty / assists ladder | Tourist → Unbeatable (100%+); assists from Tourist Drivatar to full manual | Easy/Normal/Hard + Professional; per-event "chili" flags; assist presets | Arcade↔sim toggles + assists; no difficulty tiers, no per-event chili | **S–M.** Present but shallow (roadmap 1.1/1.6 for depth). |


## 13. Performance & tech

| Dimension | Forza Horizon 6 | Gran Turismo 7 | UltraDrive (what it has TODAY) | UltraDrive vs BOTH (gap / advantage) |
|---|---|---|---|---|
| Resolutions / fps | Series X: Quality **native 4K30 + RT** / Performance **4K-dyn 60**; Series S 1440p30 / **1080p60** (no RT ⚠); RTGI + reflections across the open world | PS5 **60 fps** core; RT in Showroom/Scapes/menus (base PS5), RT reflections during gameplay on Pro; PSVR2 ~4K reprojected 120 fps; Pro: PSSR, 4K120, 8K output | Godot Forward+; quality presets Low/Med/High (SDFGI, SSAO, SSR, volumetric fog, glow, MSAA×4, FSR 2.2, light probes); first-boot auto-detect of weak GPUs | **M.** Tech parity isn't the goal — roadmap 3.3: locked 60 fps + crisp reconstruction is the bar, RT is the upgrade path, not the gate. |
| Upscaling | DLSS 4.5 SR + Multi Frame Gen (RTX 50: 4×–6×), FSR 4/3, XeSS 2.1; RTX 5090 >330 / 5080 >230 / 5070 Ti >200 fps (FG) ⚠ press | PSSR (image-quality and fps modes); "latest PSSR" in v1.71 on Pro | FSR 2.2 (scale 0.9) on High preset | **S–M.** FSR is in; DLSS/TSR-class equivalents are a settings addition, not architecture. |
| Load / streaming | **DirectStorage 1.2/1.3 + GPU GDeflate**; Advanced Shader Delivery: ~90 s → **~4 s** first load ⚠; peak ~1–2 GB/s streams ⚠ | PS4↔PS5 crossplay seamless; load time is the main PS5 differentiator (no equivalent published pipe) | **Streamed world**: 256 m chunks, 3×3 region storm, threaded pre-bake before spawn, ≤2 regions/tick, ~3.3 s to driveable cold start; headless CI-safe generation | **S–M.** UD's streaming is genuinely FH-flavored (world_compare: "sound core, thin content") — the largest parity point in this table. |
| Shader warm-up | ASD precompiled PSOs (~95% claim ⚠) | N/A (console) | No shader-precompile equivalent; cold import is a documented multi-step headless dance (AGENTS.md) | **M.** A real launch-QoL gap; GDUnit headless discipline partially de-risks it. |
| Platform validation | Steam Deck Verified; 2 console SKUs | 3 PlayStation SKU generations + PSVR2 | Headless CI (no GPU needed) + hardware-recommended preset logic | **Advantage (S).** Automated, reproducible validation beats console cert loops for correctness, if not for breadth. |

## 14. Multiplayer & social

| Dimension | Forza Horizon 6 | Gran Turismo 7 | UltraDrive (what it has TODAY) | UltraDrive vs BOTH (gap / advantage) |
|---|---|---|---|---|
| Shared world / sessions | Shared open world, ⚠ up to **72 players/session**; convoys to 12; Car Meets (3 permanent: Festival Site, Okuibuki, Daikoku) + rotating | Sport Mode + lobbies to **16 players**; Paddock pre-race lots (Room-ID, private rooms); cross-gen PS4↔PS5 | **None.** Multiplayer deliberately deferred post-v1 (roadmap 3.6); LAN/split-screen flagged as cheapest wedge | **XL.** Both rivals built their most expensive system here. UD's de-scope is a timing choice, not a stack limit. |
| Ranked / competitive | Horizon Play: Spec Racing (same car/tune), Touge Showdown, Rivals leaderboards; license-based matchmaking piloted ⚠ (unshipped) | **Sport Mode**: DR 0–150,000 (v1.55) / SR grades S–E; Daily Races A/B/C (refresh Mon 07:00 UTC); Lap Time Challenges (3%→Cr 2,000,000 / 5%→1M / 10%→200k); GTWS esports + 2026 Team Competition | None (local ghost/leaderboards PLANNED 2.2) | **L.** No online competition at all today; the *local* leaderboard layer is the achievable first rung. |
| Social / display | Visit/borrow garages + estates; download liveries/replicas at meets; earn credits when your layout is used (Creative Hub rank, 9 UGC categories) | Showcase (liveries/photos/replays), Paddock, brand Museums & Channels | None (sharing surfaces missing) | **L–XL.** The "world is a place for social display" thesis runs through both dossiers; UD's garage shell is single-player. |

## 15. Collectibles & discovery

| Dimension | Forza Horizon 6 | Gran Turismo 7 | UltraDrive (what it has TODAY) | UltraDrive vs BOTH (gap / advantage) |
|---|---|---|---|---|
| Collectibles | **400 total** (200 regional mascots + 200 bonus boards); **15 Barn Finds** (stamp-gated, incl. Mazda 787B); **9 Treasure Cars**; 31 Aftermarket spots; 75/76 landmarks ⚠; 21 photo stamps; Treasure Map DLC $2.99 | Garage + Collection Book + Collector Level as the collection layer; Legend trio (Cr 20M cars); engine-swap catalogue; brand museums | **5 non-interactive POI dots** + 10 event markers; no pickups, no boards, no barn finds, no rewards | **L.** The discovery *loop* exists (grey→white + fast travel); the collectibles to feed it are **(PLANNED 2.3** — bonus boards / speed traps / photo spots as POI entries). |
| Discovery reward loop | Fog-of-war + boards + treasure hunts convert map size into content | Museums/Café stories + Data Logger (v1.65 telemetry) provide depth instead of pickups | Grey→white reveal + fast travel already pay the player for driving | **S–M.** The loop is right; volume is the gap. |
| Interactive map | 796 interactive markers / 38 categories ⚠; in-game filters | Event Directory (completion % per event, v1.40) | World map renders roads + POIs; filters/nav aids minimal | **M.** Marker browsing + filters are a UI addition (roadmap 1.2). |

## 16. Test / quality discipline

| Dimension | Forza Horizon 6 | Gran Turismo 7 | UltraDrive (what it has TODAY) | UltraDrive vs BOTH (gap / advantage) |
|---|---|---|---|---|
| What the dossiers document | No internal QA numbers published. Observable signals: Drivatar balance patched (Series 3), photo-mode mouse regression on PC, economy re-balancing driven by backlash (Sep 2026 cap controversy) | No internal QA numbers published. Observable signals: launch server outage + credit backlash (Mar 2022) → 1M-credit apology; near-daily localisation patches; aggressive physics-retuning cadence | **263 GDUnit test cases · 0 errors · 0 failures** across 30 scripts (10 under `tests/`, 20 under `tests/suites/`), run headless in CI on every change; older audits pinned 144, the codebook counts 263 today | **Advantage in kind (scale differs).** UD's QA is measurable and automated where neither AAA publishes a number. The missing layer is human/playtest surface (FH6's 6M+ week-one crash-testing) — no suite substitutes for that. |
| Regression discipline | Community-corrected marketing numbers (e.g. the "960 roads" preview claim did not hold) | Update-by-update physics + Circuit Experience re-tuning implies internal CE-regression tooling ⚠ | **Deterministic and hermetic**: worldgen is a pure function of `MASTER_SEED`, dressing is idempotent, saves/settings round-trip tested, everything headless-safe | **Advantage (None).** The determinism that makes 263 green tests possible is a franchise asset the AAAs cannot reproduce at this fidelity. |


---

## Verdict tables

### (a) What FH6 does better than anyone → what UltraDrive must match / steal

| # | Feature | Why it matters | UD gap | Counter-part reference |
|---|---|---|---|---|
| a1 | **Customization as the product** (per-car Forza Aero, window liveries, 100+ rims with staggered fitment, true body kits, upgrade presets, 8 customizable garages + The Estate) | FH6's biggest applause line — the dossier says an indie should "nail one layer deeply rather than 600 cars shallowly" | **XL** | FH6 §4.2–4.3 · UD §4/§13 (rail-carousel shell only; sliders + livery + parts → 1.3) |
| a2 | **Density-and-discovery map** (fog-of-war route line, 671 roads ⚠, 4-tier hierarchy, free-but-gated fast travel) | "Discovery = the core loop; fast travel is the payoff" — turns map size into content | **L** | FH6 §3.1–3.2, §14 · UD §3/§15 (reveal + fast travel live; GPS line missing → 1.2/W.5) |
| a3 | **Car-culture event taxonomy** (Touge Battles ×5, 3 no-loading drag strips, night street racing with live traffic, drift circuits, Time Attack) | Events follow subcultures, not grids — "the world respects the car" | **L** | FH6 §5.3 · UD §5 (10 sites placed, none playable → 1.4) |
| a4 | **Social-display open world** (3 permanent Car Meets, visitable/borrowable garages + estates, convoys of 12, cooperative LINK) | Multiplayer threaded into the map instead of lobbies — the retention engine | **XL** | FH6 §13 · UD §14 (post-v1 de-scope) |
| a5 | **Regional climate that changes driving** (per-region weekly seasons, ~60 min day/night ⚠, grip/visibility tables, AWD-in-alpine-winter meta) | Elevation and season change route validity — FH6's most *mechanical* differentiator | **L** | FH6 §8 · UD §9 (region + season + pass_lock already live; VFX is the delta → 1.5) |
| a6 | **Two-track campaign pacing** (Wristbands 1–7 + Stamp ranks gating class caps over 15–25 h; ~50 mi Colossus + Legend Island as endgame) | Slow cars matter first; the map's biggest event is the endgame trophy | **L** | FH6 §5.1/§10.1 · UD §11 (career containers exist; no economy to pace) |
| a7 | **Accessibility as launch-blocking marketing** (Granular High Contrast, Car Proximity Radar, AutoDrive, Tourist Drivatar, story skip) | Treated as headline feature set, not a patch | **M** | FH6 §11 · UD §12 (assists + accessibility tab partial → 3.1) |
| a8 | **A characterful rival cast** (the "bowie knife99" griefer Drivatar became an internet-famous villain) | Cheapest personality win a small studio can copy — world-feel + social chatter for free | **M** | FH6 §7 · UD §6 (one memorable rival script once 1.6 AI lands) |

### (b) What GT7 does better than anyone → what UltraDrive must match / steal

| # | Feature | Why it matters | UD gap | Counter-part reference |
|---|---|---|---|---|
| b1 | **Sim-authentic, ever-iterating physics** (PP system; 4 major overhauls; tire slip/heat/wear; wet-line hydroplaning; CE times re-shot per patch) | "The Real Driving Simulator" — feel is the product, revisited each cycle | **L** | GT7 §5, §16 · UD §5 (Pacejka + data-driven config already; wear/damage + ABS/TCS missing → 1.1) |
| b2 | **Education-first career** (39 Café Menu Books, 150 + 50 licence tests, brand museums, designer cameos) | It re-ignites love of the automobile — onboarding + history count as content | **L→XL** | GT7 §3, §6, §11 · UD §11 (`LicenseSystem`/`Championship` classes exist but are unstaged) |
| b3 | **Collecting-with-restraint economy** (Used/Legend/Hagerty rotation, invitations, Collector Level, Cr 20M legends, roulette) | Starting at the bottom and growing the garage is the praised GT-proper loop | **L** | GT7 §11, §15 · UD §11 (no currency at all today → 2.1) |
| b4 | **Sophy-level rival AI** (deep-RL expert, clean overtakes, no cheating grip) | Proof that AI can beat rubber-banding — but it is paywalled ($29.99 ⚠ Power Pack), which is UD's opening | **M** | GT7 §8 · UD §6 (readable no-rubber-band AI is the named indie edge → 1.6) |
| b5 | **Replay/showcase culture** (Music Replay dynamic cameras, Data Logger telemetry, Broadcast Mode, dynamic viewing) | "The same importance on watching your driving as the fun of driving" | **L** | GT7 §7, §10, §15 · UD §5 (ghost/replay → 1.8/2.2) |
| b6 | **Track authenticity & breadth** (41 locations / 121 configs ⚠; Nürburgring TT-gated; lap times that match real life) | Circuit-fidelity benchmark UD's open world cannot match on volume | **XL** | GT7 §2 · UD §3/§5 (2 circuits; open-world routes are UD's alternative) |
| b7 | **Wheel/haptic fidelity** (Fanatec FullForce + Auto Setup; DualSense adaptive-trigger ABS; per-wheel tuning) | Peripheral feel is part of the simulation | **L** | GT7 §5, §13 · UD §5 (keyboard/gamepad only) |
| b8 | **Calibrated live-service economy** (Weekly Challenges ~1.3M-credit clean sweep; Lap Time Challenges 3%/5%/10% bands; 39 monthly drops) | Retention can be clean — UD's no-paywall ethos must still match the cadence | **L** | GT7 §11 × FH6 §10.2 · UD §11 (3.5 skeleton planned) |


### (c) What UltraDrive already has that is competitive (nothing the rivals do the same way)

| # | Asset | Why it matters | Gap to close | Counter-part reference |
|---|---|---|---|---|
| c1 | **License-safe original-car pipeline** (Blender-MCP/Hyper3D GLBs + CC0 Kenney kit; cars are `.tres` data) | No OEM licences, royalties, or takedown risk — the roster grows via data while FH6/GT7 spend per-car licence budgets | **None** (structural edge) | UD §4 · FH6 §4.1 (618+ licensed cars) · GT7 §4 |
| c2 | **Deterministic 60 km seeded world** (`MASTER_SEED = 1787569`, per-region seed hashing, idempotent dressing, 12 classified corridors) | The whole world is a pure function of one number → reproducible saves, CI, and toggles; both rivals hand-author at massive cost | **None** (edge); content *density* still L behind 671 roads ⚠ | UD §2/§3, §14 · FH6 §2/§3 |
| c3 | **Surface-grip physics that read the world** (SurfaceRegistry ASPHALT→SNOW table, alpine snowlines, `pass_locked`, altitude grip) | Driving physics negotiates with weather/seasons/regions — FH6's ⚠ tables and GT7's v1.71 tuning matched *in kind*, deterministically tested | **S** (add VFX + wear) | UD §7/§9 · FH6 §8 · GT7 §9 |
| c4 | **Test discipline as a franchise asset** (263 GDUnit cases · 0 errors · 0 failures, headless CI, gates on every change) | Measurable, automated regression quality the AAAs don't publish; shrinks every later phase's risk | **None**; grows with each phase | UD §14 · FH6/GT7 §16 (no published numbers) |
| c5 | **No-paywall ethos** (no Car Vouchers, no roulette, no grind-locked content) | Both rivals' economies are their worst-reviewed systems (FH6 voucher/cap controversy; GT7 launch crisis) — an honest loop is a genuine market position | **None** (philosophy); must still ship the loop | UD §11 · FH6 §10.2 · GT7 §11 |
| c6 | **Offline-first save + data-cheap audio** (local 3-slot saves; synthesized 3-bed engine, zero audio assets) | Fully offline-capable where GT7 is always-online, and content-light where FH6 is ~100 GB ⚠ | **None** (edge) | UD §1/§10 · GT7 §1 · FH6 §1 |

---

## Prioritized gap analysis — closing "match FH6 + GT7"

Ranked P0 → P2. Effort = roadmap T-shirt estimate for a 1–2 person indie team. Every item is grounded in the
dossiers; nothing invented. All roadmap phases referenced exist in `docs/ROADMAP.md`.

### P0 — the feel & loop gates (without these the game does not "read" as a competitor)

| # | Gap | Mirrors | Current UltraDrive state / landing route | Effort |
|---|---|---|---|---|
| P0-1 | **GPS route line + full discovery reward loop** — shortest-path on the road graph → route drawn on minimap/map; grey→white completion; free fast travel on any discovered road; HUD deltas | FH6 §3.2 route-line system ("#1 map-feels-alive feature" per roadmap 1.2) | `MapRoads` (static `route_target`, `compute_fit`, `world_to_screen`) + `WorldDiscovery` (30 m cells, 90 m reveal, persisted) exist — **route computation is missing**. Land: `scripts/ui/map_roads.gd`, `world_map.gd`, `minimap.gd`, `world_discovery.gd`. Gate `test_map_route`. | **M** (2–3 wks) |
| P0-2 | **Race-rival AI that refuses to rubber-band** — drafting bonus, overtake cooldown, skill bands per class, traffic brake-check, bounded catch-up | GT7 §8 Sophy — the gap + FH6 §7 Drivatar balance (the named indie edge, competitors.md) | Traffic-only AI today (**15 cars / 300 m**); `ai_controller.gd` + `ai_rubber_banding.gd` exist; `rubber_band_assist` reserved in `game_state.gd`. Land: `scripts/ai/`, `scripts/race/`. Gate `test_ai_race`. | **M** (2–3 wks) |
| P0-3 | **Playable event taxonomy** — the 10 placed sites become events: touge duel, drag strip, drift zone, night street loop, marathon highway, 5× time-attack anchors → launchers, lead-in, scoring/tiers, restart, HUD commit | FH6 §5.3 car-culture events | **10 sites already placed** via `EventRegistry.place()` and shown on the map, but not launchable. Land: `scripts/world/event_registry.gd`, `scripts/race/` (RaceManager, Checkpoint, `drift_scorer.gd`), `scripts/ui/`. Gate `test_event_types`. | **M** (3 wks) |
| P0-4 | **Economy + unlock-gate loop** — credits, rewards screen, spend in the garage, licence/championship gates, S-class car | GT7 §11 collect-with-restraint + FH6 §10.1 wristband pacing (deliberately without the paywall) | `Garage`, `Championship`, `LicenseSystem`, 3 JSON save slots all exist and persist; **no money/XP/rep is earned and no S-class car exists**. Land: `scripts/career/`, `scripts/ui/garage_ui.gd`, `SaveManager`. Gate: save round-trip + unlock-depends-on-state tests. | **M** (2–3 wks) |
| P0-5 | **Weather VFX + night headlights + wet-road layer** — rain/snow particles, wet skidmarks, fog density, per-state sun/fog colour, headlights/taillights | FH6 §8 + GT7 §9 mood/driving mechanics | The 6-state machine, grip consequences, snowlines and `pass_locked` are all live — **particles/lighting/layers sit behind Phase 1.5**. Land: `scripts/world/weather_manager.gd`, `sun_driver.gd`, `scripts/vehicle/car_visuals.gd`. Gate `test_weather_sun` + `test_car_visuals`. | **M** (3 wks) |
| P0-6 | **Garage tuning sliders + upgrade tiers + stat comparison** — gears/springs/dampers/downforce mutate `CarConfig`; 2–3 upgrade tiers; parts | FH6 §4.2 customization + GT7 §5 setup | `CarConfig` is data-driven and physics-ready; no player-facing UI. Land: `scenes/ui/garage.tscn`, `scripts/vehicle/car_config.gd`. Gate `test_tuning` (mutations stay in valid ranges). | **M–L** (3–4 wks) |
| P0-7 | **Road-network graph + junctions + tier metadata** — node/edge topology (enables P0-1 routing and event congestion), junction support, per-tier banking/surface | FH6 §3.1 four-tier hierarchy | 12 classified corridors exist as chains/splines; no graph, no junctions; `TrackBuilder` emits flat single-width strips. Land: `scripts/world/road_network.gd`, `scripts/track/track_builder.gd`. Gate `test_road_graph`. | **L** (W.0 → 1 sprint+) |


### P1 — content depth & a "compare-and-improve" surface

| # | Gap | Mirrors | Current UltraDrive state / landing route | Effort |
|---|---|---|---|---|
| P1-1 | **Ghost / local time-attack leaderboards** — persist best laps per track+class, ghost playback, HUD +/- delta | GT7 §14 time-trial + FH6 §5.3 Time Attack | `race_ui.gd` already draws gap timers; no ghosts, no persisted PBs. Land: `scripts/race/`, `SaveManager`. Gate: deterministic lap-replay tests. | **M** (1–2 wks) |
| P1-2 | **Collectibles & discovery boards** — bonus boards, speed traps, photo spots as `POIRegistry` entries paying rewards exactly once | FH6 §14 (400 collectibles; 15 barn finds; 9 treasure cars) | 5 POI dots, no pickups. Land: `scripts/world/poi_registry.gd`, `world_map.gd`. Gate: extend the world-map suite. | **S** (1 wk + design) |
| P1-3 | **Photo mode** — hide-UI, FOV/aperture sliders, filters, export | GT7 §3 Scapes (~2,570 spots ⚠) + FH6 photo suite | `orbit_camera.gd` is ready. Land: `scripts/camera/orbit_camera.gd`, pause menu. | **S–M** (1–2 wks) |
| P1-4 | **Audio feel layers** — tyre squeal/skids, impacts, wind, UI blips, optional music/radio bus | GT7 §10 50-mic depth (honestly uncloneable) + FH6 §9 | 3-bed synth exists. Land: `scripts/vehicle/car_audio.gd`. Gate `test_car_audio`. | **S–M** (1–2 wks) |
| P1-5 | **Rewind / reset-to-road** — short rewind buffer or on-track reset; an open world can beach the player | FH6 §5.2 + GT7 §12 rewind/reset QoL | None today. Land: transform buffer in `scripts/vehicle/`, HUD button, `GameState`. | **M** (1–2 wks) |
| P1-6 | **Open-world colour baking + a second biome zone** — make the 6 elevation bands render as 6 biomes; a 2nd zone via the existing pipeline | FH6 §2/§3 multi-biome Japan | Biome table + bake seams exist; open world bakes height-only today. Land: `terrain_baker.gd` colour pass, `terrain_seeder.gd`, a new `regions/` scene. | **L–XL** (4–6 wks) |
| P1-7 | **Authored landmarks & scenery depth** — 2–3 authored landmark sets with POI gameplay; distance-faded skyline props | FH6 §14 landmarks (75 ⚠) | Props are guardrail/tent/pole/rock only. Land: `prop_scatterer.gd`, `poi_registry.gd`. | **M–L** (3 wks) |

### P2 — launch-readiness & scale

| # | Gap | Mirrors | Current UltraDrive state / landing route | Effort |
|---|---|---|---|---|
| P2-1 | **Accessibility launch slate** — rebinding UI, colour-blind filters, reduced-motion toggle, screen-reader semantics, controller deadzone | FH6 §11 (High Contrast, Proximity Radar, AutoDrive) + GT7 §12 presets | Settings + assists are partial. Land: `scenes/ui/settings_menu.gd`, `project.godot` input map. Gate `test_accessibility`. | **S–M** (1–2 wks) |
| P2-2 | **Save robustness + profile split** — auto-save on exit, slot copy/delete UI, settings vs profile separation | GT7 §1 always-online saves (UD: offline equivalence, no anticheat gate) | 3 JSON slots, no user-facing management. Land: `autoload/save_manager.gd`. | **S** (1 wk) |
| P2-3 | **GPU benchmark → auto preset + LOD** — protect the locked-60 fps bar; RT stays an upgrade path, not the launch gate | FH6 §12 / GT7 §13 (bar = briskness, not RT) | Manual presets exist. Land: `settings_menu.gd`, LOD on `prop_scatterer.gd` / `foliage.gd`. | **M** (2 wks) |
| P2-4 | **Region-streamed dressing & traffic** — props/foliage/traffic stream per region instead of one-off rejection sampling | FH6 §12 DirectStorage-class streaming (UD: the stamped-down analogue) | Dressing is not region-streamed today. Land: `terrain_seeder.gd` apply-drain pattern, `chunk_streamer.gd`. | **L** (3–4 wks) |
| P2-5 | **Monthly content cadence skeleton** — data-only `.tres` packs so monthly drops never touch core code | FH6 §10.2 Festival Playlist + GT7 §11 monthly drops (without monetized grind) | None. Land: content-pack loader + `test_content_pack`. | **M** (2 wks skeleton) |
| P2-6 | **Multiplayer** — LAN/split-screen wedge first; full online de-scoped post-v1 | FH6 §13 shared world / GT7 §14 Sport + lobbies | None; roadmap 3.6 explicitly de-scopes | **XL** (post-v1) |

---

## How to read this (closing)

- **FH6 is the benchmark to steal a loop from** — customization + discovery + car-culture events + regional weather are
  mechanics, not budget. Three of those four already have live scaffolds in UD (P0-1/3/5/6).
- **GT7 is the benchmark to steal *discipline* from** — physics-as-evergreen, education-first career, and a clean,
  calibrated economy. UD's data-driven physics and licence/garage classes put that discipline within one or two phases.
- **UltraDrive's defensible position is not being "FH6/GT7 for less"** — it is a deterministic, license-safe,
  test-gated world whose economy refuses both incumbents' worst reviewed systems. The comparison's honest verdict:
  the *architecture* is competitive today; the *content and loop layer* is 5–7 P0 items away from closing the readable gap.

*End of comparison. Sources: `fh6_features.md`, `gt7_features.md`, `ultradrive_features.md`, context from
`world_compare.md`, `competitors.md`, `self_audit.md`, `docs/ROADMAP.md`. ⚠ markers and roadmap-phase labels are kept intact.*
