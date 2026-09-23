# UltraDrive (shipped state) vs Forza Horizon 6 — honest comparison

> **Framing block.**
> - Renderer/DLSS/ray-tracing comparisons against FH6 at full fidelity are **out of scope** for this hardware (GTX 970, EOL Maxwell drivers, no RT cores).
> - This comparison is about **market parity and launch-candidate honesty**, not achieving parity with a first-party-funded AAA studio.
> - **"Achievable" means achievable-launch-bar** (locked 60 + crisp presentation), not FH6-equal.

Ground truth used throughout: UltraDrive repo at commit `b24d60e` (HEAD ~Sep 2026, 129 commits), **641 GDUnit tests green across 63+ headless suites** (progression 266 → 277 → 285 → 592 → 641). UltraDrive stays on **Godot 4.7.2 Forward+/Vulkan**; the Unity + "HiggsField" migration was rejected (the asset does not exist) and the UE5 assessment concluded: stay. Engine decision is settled.

FH6 fresh facts verified Sep 2026: official roster **636 cars** (forza.net/fh6cars, updated Aug 13 2026), third-party trackers at **642**; Series 5 "British Automotive" ran Sep 10 – Oct 8 2026, Series 6 **"Horizon Meets"** announced for after Oct 8; FH6's **minimum supported NVIDIA GPU architecture is Turing** — Pascal and older (GTX 1070/1080) are below minimum, so the GTX 970 UltraDrive targets is *two generations below FH6's own floor* (support.forza.net PC specs).

---

## 1. Roster & acquisition

**UltraDrive today.** Data-driven garage, not hand-made per-car code: 6 car definitions from `resources/cars/*.tres` — Striker (D), Thunderhead (C), Dirt Devil (B), Comet (C), Hooligan (B), Interceptor (A, incomplete spec). 3 original GLB bodies (sports coupe / muscle / rally-hatch) produced through the Blender-MCP asset pipeline plus CC0 Kenney kit integration, gated by `tests/suites/test_cc0_cars.gd`. Every car is license-safe by construction — **zero OEM licensing risk**, which is a structural advantage a licensed roster can never have.

**FH6.** 550+ cars marketed at launch, 614 community-verified at launch, **636 on the official roster (Aug 13 2026)**, 87 manufacturers. Acquisition paths: Autoshow purchase, Wheelspins/Super Wheelspins, 15 Barn Finds, 9 Treasure Chests, 31 Aftermarket models, Festival Playlist rewards, Car Pass weekly. Source: https://forza.net/fh6cars

**Gap: PARTIAL.** Roster *count* is structurally hopeless — the whole point of the comparison. Roster *depth* (S-class, per-car handling/tuning/paint depth) is data-shaped already.

**Bridgeable?** Count = unreasonable-for-small-team. Depth = **cheap ugly-win** (it is pure `resources/cars/*.tres` authoring once S-class + economy ship).

---

## 2. Open world & map

**UltraDrive today.** `scripts/world/corridor_planner.gd`: 12 corridors, 5 classes (arterial/highway/touge/coastal/dirt), budgeted ~60 km, 16-degree banked highway loop, ~1,100 m alpine relief (two elevation domes, 6 bands), elevation band HEIGHT −8…2000 driving. 256 m worlds-aligned chunks, 3×3 region streaming (~3.3 s cold start to drivable, region-crossing spike cut from 1.09 s → ~80 ms). Discovery loop shipped: grey→white fog-of-war reveal, POI/marker layer (5 anchors + 11 event markers), GPS route + brake line, minimap + pause map, fast travel. `scripts/world/` + `scripts/discovery/`. $60 km budget is not yet met; benchmark rows still open (60 km of roads, ≥25 junction graph, big-arc corridors, elevation ≥1,500 m).

**FH6.** Japan, ~122–246 km² (fan estimates), ~21-mile north-south span, ~671 reported roads, ~540 road-miles, 5 biomes, sea→~3,000 m; Tokyo metropolis ≈5× FH5 Guanajuato; fog-of-war map with region filter, free fast travel, ANNA autodrive. DF: open-world draw and density are the headline upgrade over FH5.

**Gap: PARTIAL→OPEN.** The discovery/route layer is genuinely FH-shaped. Density, scale, biome variety are open by orders of magnitude.

**Bridgeable?** Density parity = multi-year lift. **Cheap ugly-win within reach:** open-world color-map bake (Terrain3D already does this on Mountain Pass — extend to seeded world), a second biome, authored landmark clusters.

---

## 3. Modes & events

**UltraDrive today.** Full circuit race loop: countdown → checkpoint/lap/standings → results overlay → session stats (`scripts/race/race_countdown.gd`, `scripts/ui/results_overlay.gd`, `scripts/race/session_stats.gd`). Event taxonomy of **8 families** placed on the map via `event_registry`, `event_session`, `event_scoring` — touge_duel, drag_strip, drift_zone, night_street_loop, marathon_highway, time_attack, outbreak, convoy — each graded S/A/B/C with rewards that flow into the ledger. Playable, scored, rewarded.

**FH6.** Races by type (legal street racing, dirt, cross-country, touge showdowns, time attacks, drags) + PR stunts (speed/drift/danger), Rush, Showcases, the ~50-mile Colossus cross-country, **Drag Meets / Meet Badges (Series 5)**, Spec Racing, Eliminator, Hide & Seek, EventLab/CoLab, the Festival Playlist topping out at 20/40/60/120 points. Series 5 "British Automotive" added Drift Attack as a permanent feature.

**Gap: PARTIAL.** Event *culture* (score highscores, discover-by-driving, graded runs) is ordered correctly and shipped. Scale/co-op/User-Generated-Content is open.

**Bridgeable?** Culture ordering = done, keep it. UGC/EventLab = unreasonable-for-small-team. Cheap next win: event *diversity per family* (weather/TOD/season overrides reusing existing climate + TOD systems).

---

## 4. Physics & handling feel

**UltraDrive today.** 4-wheel raycast RigidBody3D with **Pacejka tire model** (`scripts/vehicle/tire_model.gd`), Jolt physics provider, drivetrain (auto + manual + reverse), surface grip registry (`SurfaceRegistry`: asphalt 1.0 → snow 0.35), regional climate + altitude interplay, arcade/sim modifier config + assists (TCS/steer/drift), input-response curves. Drive-feel layer ships transients: visual suspension body-rig, speed vignette, tire marks, chase-cam feedback. Deliberately **Featherweight arcade**, not a BeamNG-class soft-body sim — a design position, not a missing feature.

**FH6.** ForzaTech 6 (2021-era source engine per DF): ~360 Hz tire/physics rate, horizon-arcade handling with assists defaulted on, Series 3 steering-feel patch mid-year.

**Gap: PARTIAL.** UltraDrive's model is structurally credible, data-driven, deterministic, and covered by `tire_model` / `drivetrain` / `surface_grip` / `climate` test suites. Missing: heat/wear/damage, tuning depth on suspension geometry, anti-roll bars.

**Bridgeable?** Differential possible. Config-driven handling feels (a "feel pass" per milestone) is cheap; a full damage/heat/wear sim is a medium lift. Consider this an honest strength zone: the driving feel loop is already 60 fps and tuned per-car.

---

## 5. AI

**UltraDrive today. The genuine differentiator.** `scripts/ai/rival_driver.gd` + `racing_line.gd`: **no rubber-banding on the player, ever** (GameState's `rubber_band_assist` touches only traffic + Novice tier), 3 skill tiers (Novice/Skilled/Expert), physics-honest cars drive racing lines. `traffic_driver.gd`: living traffic with route-follow, lane avoid, parked cars, stuck-rescue. Covered by `tests/suites/test_rival_ai.gd`.

**FH6.** Drivatars — cloud behavior-capture AI, up to 11 per event, individually named and remembered by players (the recurring "I miss running Drivatar [handle]" posts) — though analysis traces rubber-banding complaints to FM, not FH6; Series 3 rebalanced Drivatar fairness. GT Sophy is GT7's thing, **not FH6** (and was locked behind a $30 Power Pack there).

**Gap: CLOSED in kind.** We have the "clean AI beats scripted catch-up" advantage, shipped and test-covered. What FH6 has that we don't: personality/nameability of rivals.

**Bridgeable?** **Cheap ugly-win:** nameable, persistent rival personalities (the "bowie knife99" lesson — players race *people*). AI fairness is already a fortress; make it a marketing claim.

---

## 6. Graphics & rendering

**UltraDrive today.** Godot Forward+ (Vulkan), quality ladder Low/Medium/High with SDFGI, SSAO, SSR, volumetric fog, glow, MSAA×4, FSR 2.2 (0.9 scale High). Measured on the reference GTX 970 @1080p from the perf-preset work: **Low 93 fps / Medium 65 fps / High 57 fps** (High misses the locked-60 bar — a known open item). First-boot GPU-detect chooses a preset, headless-safe. Terrain3D gives full height+color on Mountain Pass, currently height-only in the seeded open world.

**FH6.** ForzaTech 6 renderer — DF flatly notes it is a **2021-era base largely carried forward**. Even so: RTGI + RT car reflections in open world, Series X 4K60 perf / **native 4K30 RT quality**, Series S 1080p60 / 1080p30 RT, **DLSS 4.5 (SR + MFG 4X/6X)**, FSR 4/3, XeSS 2.1, DLAA, DirectStorage (~4 s SSD load to drivable). IGN: 10/10. And critically: **minimum NVIDIA GPU arch = Turing; the GTX 970 is unsupported by FH6 entirely**.

**Gap: OPEN on fidelity; CLOSED on approach.** Our launch bar *is* FH6's performance mode (locked 60, resolution-scaled, no RT) — the difference is FH6 also offers the 30 fps RT mode on Series X/PC, which we structurally cannot on Maxwell hardware.

**Bridgeable?** Fidelity parity = the hard ceiling (see notes below). But: "2021-era renderer" + SDFGI + FSR2 + locked 60 on a GPU **FH6 refuses to run on** is a defensible, honest niche. Close the High preset 57→60 gap and this category becomes a clean story.

---

## 7. Audio

**UltraDrive today.** Procedural 3-bed engine audio with per-car timbre + hybrid real-bed continuous pitch tracking (`scripts/audio/car_audio.gd`), traffic distance culling, engine-audio coverage in tests. **Zero licensed audio assets** — everything synthesized or CC0.

**FH6.** 224+ licensed tracks across 9 stations (largest Horizon soundtrack), upgraded modular engine audio with distinct turbo/backfire layer, Triton Acoustics spatial reverb, cockpit impulse responses.

**Gap: PARTIAL.** Engine synthesis is different-in-kind and license-safe. Missing daily-feel layers: tire squeal/skid, impacts, wind, gearbox blurts, UI blips (a P-series item).

**Bridgeable?** **Cheap ugly-win vector**: synth/CC0 tire-friction + impact + wind beds lift the daily feel enormously for near-zero cost. Licensed 224-track radio = unreasonable; a CC0 radio shell with procedural DJ = medium, not launch-blocking.

---

## 8. UI & UX & discovery

**UltraDrive today.** Full shell: main menu, track select, kiosk, garage (carousel + turntable + 6-stat bars, `scripts/ui/garage_ui.gd`). Discovery map with grey→white road reveal, POI markers, fast travel; minimap; Forza/GT-style cluster HUD + shift lights; optional cockpit HUD/flashlight + mirrors (F-series, shipped S14→F5). Settings tabs for quality / input / gameplay / accessibility. Session stats, save profile slots + corrupt-slot detection (S17 P2-2).

**FH6.** 7 pause tabs, fog-of-war map with region filters and free fast-travel cursor, playlist UI, ANNA autodrive, **Photo Mode**, **car proximity radar**, HUD scaling, massive Settings depth.

**Gap: PARTIAL.** Discovery/map/garage/HUD is the strongest parity zone. Missing: photo mode, map filters, proximity radar, autodrive, in-game rebind UI.

**Bridgeable?** Hook cam rig (F1) + settings F5 into a **Photo Mode = cheap ugly-win** and a marketing surface. Map filters + rebind UI = cheap-medium, and rebind is launch-blocking per the roadmap's accessibility-hardening.

---

## 9. Multiplayer & online

**UltraDrive today.** **None.** Deferred post-v1 by roadmap (item 3.6). No netcode, no server, no accounts.

**FH6.** Shared world up to 72 players, convoys of 12, 3 permanent Car Meets, Eliminator/Hide&Seek/Spec Racing/Touge Showdown, cross-play + cross-save across PC/Xbox/PS5 (PS5 later in 2026), car trading/auctions.

**Gap: OPEN by design.** Largest single-parity gap, and the one with the clearest "don't try to match" reasoning.

**Bridgeable?** Full FH6-style online = unreasonable-for-small-team (years + infra). Post-v1 LAN / split-screen is the cheapest real wedge and should be the only commitment made in a launch story.

---

## 10. Progression & economy

**UltraDrive today.** `money.gd` zero-sum ledger (events S/A/B/C rewards flow in; buy/sell flows out), career profile (level/XP), tuning profile + garage tuning sliders + paint swatches (S13), license tiers (B/A/S/Race/Elite, `LicenseSystem`), garage ownership gates, Championship class. Save robustness + profile slots shipped (S17). Deliberately **no grind, no paywall** — the ledger is clean by construction.

**FH6.** Three progression tracks (wristbands 7 ranks, stamps, Horizon Play badges 100), deep economy with known controversy (voucher/auction/CR-cap issues, Series 3 long-race reward nerf), Festival Playlist ladder at 20/40/60/120.

**Gap: PARTIAL→OPEN.** The loop is *almost* closed: play → score → pay out → buy/upgrade. What's missing: a headline S-class car to spend on, championship → payout wiring, and a "cost of success" balancing pass.

**Bridgeable?** **Cheap ugly-win**: finish the loop (payouts → car purchases → tuning → next event) and invert FH6's controversy into "no grind, no paywall, one purchase, no vouchers" as a launch plank.

---

## 11. Accessibility

**UltraDrive today.** Settings tabs for input/gameplay/accessibility; camera-shake toggle; traction/steer/drift assists; quality presets; F5 camera & feel sliders (FOV, shake, bob, reduced-motion defaults). Clear heads-down polish: accessibility *principles* are baked into every feel-based feature.

**FH6.** Industry-leadership slate: granular high-contrast colors, proximity radar, ANNA autodrive, ASL/BSL sign videos, Tourist Drivatar (non-rival), game-speed reduction offline, colorblind scene filters, HUD scaling, single-stick steering, full remap, sensitivity curves.

**Gap: PARTIAL→OPEN.** Assist layer + feel controls exist. The FH6 headline slate (colorblind scene filters, autodrive, in-game remap, HUD scaling) does not.

**Bridgeable?** **Cheap ugly-win set** (launch-blocking per roadmap 3.1): autodrive reuses the shipped GPS route + route_planner; colorblind scene filters are a subtree shader/tone pass; rebind UI and HUD scaling are medium. Every one of these is orderable in one sprint each.

---

## 12. Live-service & content cadence

**UltraDrive today.** Monthly content cadence is a roadmap target (**not shipped**): no `ContentSchedule` pack system yet — `scripts/` has no content-cadence module and no test suite for it. The intent is on paper (S-sprint), the mechanism is not in the tree.

**FH6.** Five series in ~4 months: Series 1 (May 21), Series 5 "British Automotive" (Sep 10 – Oct 8), Series 6 "Horizon Meets" announced after Oct 8. Weekly Thursday playlist resets, seasonal content beats, 2 paid car packs (Italian Passion, Time Attack), relentless live-ops team.

**Gap: OPEN.** Named gap with a fully known shape.

**Bridgeable?** The *mechanism* (data-only `.tres` event/road/playlist packs) is a cheap ugly-win and is where UltraDrive's "no grind, no grind-gated content" stance can genuinely out-position FH6's contested ladder. The *operation* (weekly resets for years) = multi-year/good-team-scale — out of scope for a launch candidate.

---

## Ranked gap table (biggest-impact × most-cheaply-closable first)

| # | Gap | Category | Closed/Partial/Open | Verdict | Effort class |
|---|---|---|---|---|---|
| 1 | Sync-based Procedural Audio daily-feel layer (tire squeal, impacts, wind) | Audio | partial | cheap ugly-win | S |
| 2 | Economy loop completion (S-class car, championship payouts) + launch-free-of-controversy plank | Progression | partial | cheap ugly-win | M |
| 3 | Accessibility launch slate (autodrive, colorblind filters, rebind, HUD scale) | Accessibility | partial→open | cheap ugly-win, launch-blocking | M |
| 4 | Photo Mode + map filters (perk: real marketing surface) | UI/UX | partial | cheap ugly-win | S–M |
| 5 | Personality/nameable rival AI (Drivatar-personality lesson) | AI | closed-but-deepening | cheap ugly-win | S–M |
| 6 | Event variety per family (weather/TOD/season overrides) | Modes | partial | medium lift | M |
| 7 | Open-world visual biome pass (color-map bake + 2nd biome + landmarks) | Open world | partial→open | medium lift | M–L |
| 8 | Data-only content schedule packs (monthly no-grind cadence) | Live-service | open | cheap ugly-win mechanism, multi-year operation | M |
| 9 | Close High-preset 57→60 locked bar on GTX 970 | Graphics | partial | small lift, high story value | S |
| 10 | LAN / split-screen multiplayer wedge | Multiplayer | open | medium, post-v1 only | L |
| — | Roster count parity (636 vs 3) | Roster | open | unreasonable-for-small-team | XL |
| — | RTI / RT reflections / DLSS 4.5 MFG / native 4K30 | Graphics | open | hard ceiling (see below) | XXL |
| — | UGC/EventLab, per-series fuzzy playlists, auctions | — | open | unreasonable | XXL |
| — | 224-track licensed soundtrack | Audio | open | unreasonable | XXL |

---

## Hard ceiling notes (why some gaps must stay open)

- **RTGI / RT reflections / native 4K30**: GTX 970 has no RT cores and EOL Maxwell drivers; Godot Forward+ doesn't run the RT path anyway. There is no path on this hardware and no launch-bar requirement. Non-goal, stated plainly.
- **DLSS 4.5 (SR + MFG 4X/6X) / FSR 4**: proprietary RTX/AMD-2025 stack; FH6's own minimum is **Turing**. UltraDrive uses FSR 2.2 — which works on the GTX 970 FH6 won't even run. This is the honest, structural niche: a locked-60 game on a GPU the AAA competitor refuses.
- **Renderer parity**: ForzaTech 6 is itself a 2021-era base (DF) — so the *kind* of presentation is reachable (SDFGI + FSR2 + locked 60), while its RT/ML extras are not. UltraDrive's quality ladder (Low/Med/High) is a real FH5-generation-style presentation; High just needs the last 3 fps.
- **Streaming**: FH6's DirectStorage GPU-decompression is a pipeline difference, not a parity need — UltraDrive's threaded 256 m region streaming (~80 ms crossing spikes) already hits the feel bar.

> Bottom line: on **Modes, AI, Discovery, Feel (arcade), and hardware-floor coverage** UltraDrive has closed or credibly partial parity with a defensible, different-in-kind position. On **Roster, Scale, Online, RT-fidelity, and licensed content** the gap is structural and the honest answer is: different product, same genre space.