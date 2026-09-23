# UltraDrive vs Gran Turismo 7 — Grounded Gap Analysis

_Research dossier. Written 2026-09-23. UltraDrive facts are grounded in this repo (scripts, tests, docs, git log). GT7 facts are cited to primary/secondary sources, current to the Sep 2026 Spec IV announcement. This document's job is to separate **what is genuinely closed**, **what is partially closed**, **what is a cheap ugly-win**, **what is a multi-year lift**, and **what is a hard ceiling on our target hardware_._

## Framing Block (verbatim, do not re-litigate)

- **Design identity:** UltraDrive is an **arcade-action racing experience**, not a sim. Gran Turismo 7's 360°-iteration "Real Driving Simulator" authenticity is an explicitly **different design lane** — we are not chasing it and never benchmark against it on fidelity.
- **Target hardware:** GTX 970 (Maxwell, EOL driver 560.94). The launch bar is **locked 60fps + crisp 1080p presentation**, not ray tracing, not 4K120, not VR.
- **Engine decision:** **Stay on Godot 4.7.2.** Unity + "HiggsField" were rejected (the asset does not exist). A UE5 assessment concluded staying in Godot. This is settled.
- **Verification bar:** 641 GDUnit tests green / 0 errors / 0 failures across 63+ suites (progression 587 → 630 → 641). Engine is behind us.
- **Test inventory (measured, not assumed):** 65 `.gd` test scripts = 53 suites in `tests/suites/` (+ `checkpoint_stub`) + 11 at `tests/` root. Suites cover rivals, race loop/countdown/results, garage tuning, cockpit, drive feel, surface grip, regional climate, traffic, career economy, event rewards, GPS routing, CC0 cars, quality ladder. **No suites exist for replay, photo/Scapes, multiplayer, or telemetry — those gaps are real, not undocumented.**

---

## Category-by-Category

### 1. Roster & acquisition
- **UltraDrive today:** 6 car configs (`resources/cars/`: starter_car, muscle_car, rally_hatch, cc0_sedan_sports, cc0_race, cc0_hatchback_sports) on 3 bespoke GLBs + 3 integrated CC0 GLBs, plus a CC0 kit library (kenney car-kit, free_concept_car_037) available for future variants. Garage tuning (S13, `f5d0e00`) adds gear/final-drive/mass sliders, paint swatches, live dyno. `test_garage_tuning.gd`, `test_cc0_cars.gd`.
- **GT7:** 574+ cars ("574 (plus one)" per update 1.71); three dealerships (Brand Central, Used, Legend) with engine-swap meta (≈300 swaps at Collector Level 50); **Car Concierge** (order rare Used/Legend cars) and **Vintage** (cars no longer sold new) arriving in Spec IV October 2026.
- **Gap:** Open. Volume ratio is ~100:1 and we will never close it.
- **Bridgeable verdict:** **Unreasonable** to chase count (~574 cars). **Cheap ugly-win:** deepen the 6 existing cars' tuning/paint expression (S13 already proves the direction) instead of widening the roster — garage depth beats car count (see `competitors.md` FH6 lesson).

### 2. Tracks & environments
- **UltraDrive today:** One handcrafted open world — deterministic seeding (P0–P7), `corridor_planner.gd` with `MASTER_SEED := TerrainBaker.NOISE_SEED * 1337` and `KM_TARGET := 60.0` km of classified corridors negotiated against 256m streaming regions (`6dd68bb`, streaming blip 1.09s → ~80ms). Regional climate bands, 24h sun, weather. `test_corridor_seeding.gd`, `test_terrain_biomes.gd`, `test_surface_grip.gd`.
- **GT7:** 41 locations / 121 layouts. 2026 additions: Sportsland SUGO (real, elevation-heavy) and **Autumn Ring** (returning original layout + a new greatly expanded layout) in Spec IV; Circuit Gilles-Villeneuve + Yas Marina in Spec III; Interlagos event in 1.69. Circuit Experience per track.
- **Gap:** Partial. One distinctive open world vs 121 layouts is a *design* choice, not a defect.
- **Bridgeable verdict:** **Cheap ugly-win:** Circuit-Experience-style section/best-sector challenges over our GPS route (`test_gps_route_follow.gd`, `test_map_route.gd` exist — the state is already emitted). Give the single world more remembered *places* (Autumn Ring's lesson: familiarity + one twist) rather than more maps.

### 3. Career & loop
- **UltraDrive today:** Full race loop shipped (countdown, results, rewards; `test_race_countdown.gd`, `test_race_results.gd`, `test_event_rewards.gd`), GPS route, event taxonomy with **8 racing families**, career XP profile, S11 economy ledger.
- **GT7:** ~39 Café Menu Books pacing through the World GT Series ending, plus Extra/Tutorial menus and a **Seasonal Menu** after clearing Menu Book 39 (1.69) with rotating collect-and-reward quests; single-player grinding criticized in reviews (Eurogamer return-to-roots).
- **Gap:** Partial. Loop + progression exists; the *curated narrative sequence* (menu-book style) over the 8 families does not.
- **Bridgeable verdict:** **Multi-year?** No — **medium lift / cheap ugly-win:** each of our 8 event families already stands in for a "Menu Book stage"; wrapping them in a curated order + an ending unlock is in reach with existing economy/rewards infra.

### 4. Modes
- **UltraDrive today:** Free roam, events, timed races, high-speed stability tuned for sustained driving. No luck-based/driving-school modes.
- **GT7:** World Circuits, Circuit Experience, Time Trial, Sport Mode, Music Rally, plus Spec IV: **Family** mode (kids→adults), **Shuffle Race** (randomly drawn cars), **Online Drift Trial**.
- **Gap:** Open on mode breadth; closed on core racing.
- **Bridgeable verdict:** **Cheap ugly-win:** Shuffle Race = pick a random car from the owned pool and go — trivially closeable. **Family** maps onto our S15 accessibility plan (difficulty presets), also cheap. **Medium:** a drift-trial scoring replay of existing drift-flag state. **Unreasonable:** anything online (see #10).

### 5. Physics & handling
- **UltraDrive today:** Godot 4.7.2 + Jolt, Pacejka tire model, 4-wheel raycast, surface grip registry, drive-feel transients, grip-limited high-speed stability + high-speed handling stability fixes (`1c8733c`, `fa6c561`), manual transmission + over-rev guard, assist surface-radars. `test_vehicle_physics.gd`, `test_drive_feel.gd`, `test_longitudinal_traction.gd`, `test_transmission_modes.gd`.
- **GT7:** "The Real Driving Simulator"; update 1.71 (2026-08-20) delivered the biggest physics overhaul since 1.49 — steering geometry revision, new damping force calculations, new **default suspension and differential settings** per car, downshift-prevention tweaks (GTPlanet).
- **Gap:** By intent, open on 360° sim fidelity — that is our identity, not a gap to close. The *transferable* engineering lessons are: (a) a **default-setup pass per car**, (b) **gear-change/downshift protection**, (c) **geometry/steering-rate review** — all are arcade-action-compatible.
- **Bridgeable verdict:** **Cheap.** Steal 1.71's *process* (per-car default setup + downshift guard), not its physics fidelity.

### 6. AI
- **UltraDrive today:** Rival AI with **Novice / Skilled / Expert skill tiers** and no rubber-banding, exercised over GPS routes (`test_rival_ai.gd`, `test_gps_route_follow.gd`).
- **GT7:** GT Sophy (reinforcement-learned) is **paywalled inside the $29.99 Power Pack** races; Sophy 3.0 runs those races; "the next evolution of GT Sophy" arrives December 2026. PS5-only.
- **Gap:** Open on learning-AI; **closed** on fair, tiered rival behavior — which is the player-facing feature.
- **Bridgeable verdict:** **Already-shipped differentiator; polish is cheap.** Sophy being paywalled + next-gen-only means *our* clean, free rival AI tiers are a genuine field to win (per `competitors.md`). Lean in.

### 7. Graphics & rendering
- **UltraDrive today:** GTX 970 preset probe: Low 93fps / Medium 65fps / High 57fps @1080p (`7ffb524`); open-world milestone 94.9fps avg (`d8610ef`); minimap draw-cull 22.8→14.0ms, 616→268 draws (`6f9f247`); reflection probes, weather VFX, regional climate. Target: locked 60 + crisp.
- **GT7:** PS5 Pro 4K120 / 8K60 / PSSR upscaling; raytraced reflections (garage + replays); photogrammetry-grade environments.
- **Gap:** Open vs RT/4K/8K — but those are **hard hardware ceilings**, see below. Against our *own* launch bar (locked 60 crisp), this category is **near-closed**.
- **Bridgeable verdict:** **Cheap huge-win:** the presentation bar is 60fps + art direction, not pixels; the 94.9fps headroom means we can spend the surplus on dressing, not resolution.

### 8. Audio
- **UltraDrive today:** Hybrid **real-bed engine audio with continuous pitch tracking** (`a3bb009`), vehicle FX layer. `test_engine_audio.gd`, `test_car_audio.gd`.
- **GT7:** Per-car studio recordings with up to ~50 microphones; distinct audio per engine swap; famous pops/crackles polish.
- **Gap:** Open on per-car bespoke studio fidelity — unreachable at our team size.
- **Bridgeable verdict:** **Cheap-medium ugly-win:** one continuous-pitch real-bed core is *already* the honest approximation; add the cheap garnish (tire skid, wind, gearbox whine) so the *whole chain* sells, instead of chasing per-car fidelity.

### 9. UI & UX
- **UltraDrive today:** Cockpit HUD, cluster HUD-dim, virtual rear-view mirror (F4), camera/feel settings incl. XAG-117 (F5, `337c383`), chase/orbit/hood/cockpit camera cycle (F1/F2a/F4/S14), open-world HUD, session stats. `test_cockpit_hud.gd`, `test_camera_settings.gd`, `test_hud_contrast.gd`.
- **GT7:** Gallery-level Scapes curation ("Move the camera up and down III" curation in 1.69), **Car Viewer** (admire garage cars, Spec IV October), deeply polished menus/livery editor from a multi-disciplinary art dept.
- **Gap:** Partial — presentation polish and a *show off the cars* surface.
- **Bridgeable verdict:** **Cheap ugly-win:** a **Car Viewer** over our 6 cars is a gallery scene + orbit camera we already own from the F1 chases. Scapes-style photo sits in #13.

### 10. Multiplayer & Sport Mode
- **UltraDrive today:** **None.** No netcode, no matches, no ratings. No test suites reference multiplayer.
- **GT7:** Sport Mode ratings, daily races, **Online Drift Trial** (Spec IV Dec), World Series broadcast circuits.
- **Gap:** Open.
- **Bridgeable verdict:** **Multi-year lift** (netcode + server + anti-cheat + ratings) — the single most expensive thing on this list. Note as roadmap-excluded; **local split-screen** is the only medium option and it is not the Sport Mode experience.

### 11. Progression & economy
- **UltraDrive today:** S11 economy stub (money ledger + rewards), career XP profile, event rewards, garage ownership gates on tuning/paint (`9067d11`). `test_career_economy.gd`, `test_event_rewards.gd`, `test_profile_slots.gd`.
- **GT7:** Credits + Collector Level (cap increase coming in Spec IV Oct) + roulette/invitations; dealerships; **paid** credit packs and the $29.99 Power Pack.
- **Gap:** Partial — the ledger and ownership gates are closed; the *economy texture* (a dealership, a hangar, a rotation) is open.
- **Bridgeable verdict:** **Cheap-medium ugly-win:** a small **used-car rotation** over our existing run of cars fits the S11 ledger in days of work. **Explicit anti-lesson:** GT7's paid credit packs and $29.99 Power Pack have drawn sustained community backlash — we should never monetize economy progression.

### 12. Accessibility
- **UltraDrive today:** Assist surface-radars, camera/feel settings, contrast-tested HUD (`test_hud_contrast.gd`, `test_input_curves.gd`), S15 accessibility plan exists and passed its gate at 341 tests.
- **GT7:** Assist suite (TSM, TCS, braking assists); Spec IV adds a **Family** mode "so that kids and beginners can enjoy GT."
- **Gap:** Partial — we're mid-plan, and Family shows even PD ships a low-friction entry mode.
- **Bridgeable verdict:** **Cheap.** Finish S15; Family presets = the S15 difficulty ladder as a named mode.

### 13. Presentation-extras (replays / photo / telemetry)
- **UltraDrive today:** **None of the three.** No replay, no photo/Scapes, no Data Logger. State for all three already exists across driven runs (standings, drift flags, speed, camera rigs), but no suite or module consumes it.
- **GT7:** RT-assisted replays, **Scapes** photo mode (constantly curated), **Data Logger** telemetry graphing, livery editor, 24h endurance events.
- **Gap:** Open, and 100% of it is presentation-layer over infra we already emit.
- **Bridgeable verdict:** **Cheap ugly-win:** replay = re-drive the recorded ghost/state with the existing chase/cockpit cameras (ghost/recording is the only genuinely *new* gear). Photo mode = Scapes-lite freeze-frame + camera settings + optional DoF. **Medium:** Data Logger graph over existing telemetry variables.

---

## Ranked Gap Table (impact × closability, biggest/most-closable first)

| # | Gap | State | Verdict | Blocker / note |
|---|-----|-------|---------|----------------|
| 1 | **Championship / season ladder** | Open | Cheap ugly-win | Career XP + economy ledger + 8 event families already shipped; wrap them in a curated order (GT7 "Menu Book" + 1.69 Seasonal Menu lesson) |
| 2 | **Replay mode** | Open | Cheap ugly-win | All state (standings, drift, speed) already emitted; add ghost/state recorder + existing camera rigs |
| 3 | **Shuffle Race + Family presets** | Open | Cheap ugly-win | Random-owned-car race; Family = S15 difficulty presets as a named mode |
| 4 | **Circuit-Experience-style section challenges** | Open | Cheap | GPS route + checkpoint timing already exist |
| 5 | **Rival AI as differentiator** | Closed → polish | Cheap | Tiered no-rubber-band AI already shipped; Sophy is paywalled/PS5-only — our clean field to win |
| 6 | **Photo / Scapes-lite** | Open | Cheap | Freeze-frame + camera settings + optional DoF over emitted state |
| 7 | **Dealership / used-car rotation** | Open (ledger closed) | Cheap-medium | Extends S11 ledger; never monetize economy (GT7 backlash lesson) |
| 8 | **Telemetry / Data Logger** | Open | Medium | Graph existing telemetry variables |
| 9 | **Garage/tuning depth as roster substitute** | Partial | Medium | S13 shipped; deepen tuning/livery-lite on 6 cars instead of widening count |
| 10 | **Multiplayer / Sport Mode / Online Drift** | Open | **Multi-year lift** | Netcode + ratings + servers; roadmap-exclude; split-screen only medium option |
| 11 | **Roster volume (~574 cars)** | Open | **Unreasonable** | 3+3 cars; garage depth beats car count |
| 12 | **Sim-fidelity physics (360°)** | By design | **Unreasonable / not a gap** | Steal 1.71's *process*: per-car default setup + downshift guard (`cheap`) |

_Ordering note: 1–6 are "impact × closability" winners and safe for the roadmap's near term; 10–12 are declared not-roadmap._

---

## Where GT7's Example Genuinely Teaches UltraDrive Cheaply

1. **A default-setup pass per car + downshift/over-rev protection** (1.71's most transferable work; we already have the over-rev guard — finish the sibling).
2. **One memorable place with one twist beats a long list of bland layouts** (Spec IV Autumn Ring "original layout + greatly expanded layout": one world, two personalities, zero new streaming machinery).
3. **A named low-friction entry mode** (Special IV Family) — promotes our existing assist surface-radars + difficulty ladder into the UX.
4. **Curated single-player sequence with a post-ending seasonal rotation** (Menu Books + 1.69 Seasonal Menu) — our 8 families are the raw material; the frame is the cheap part.
5. **Selling cars ≠ grinding: GT7's paid credit packs and $29.99 Power Pack have drawn sustained community backlash — the cheap lesson is to never monetize progression.** (Power Pack's *content* — 24h endlander endurance, race weekends — is good; its paywall is the part to copy as *free*.)
6. **A photo/gallery surface (Car Viewer, Scapes) makes a small garage feel curated** — we already own the orbit camera.

## Hard Ceiling Notes (never target on GTX 970)

- **Raytraced reflections** in replays/garage: Maxwell has no RT cores. Hardware ceiling.
- **4K120 / 8K60 / PSSR**: PS5-Pro-class features tied to that hardware. We target 1080p60 *locked*, which is also the *right* marketing ("runs locked 60 on a 970").
- **PS VR2 / VR**: = **unreasonable** at our scope; also physically hard-ceilinged on the 970.
- **GT Sophy**-class learning AI: paywalled PS5 content; our competitive answer is clean tiered rivals (already shipped).
- **574-car roster**: **unreasonable**; answered with garage depth (S13) + used-car rotation.
- **Multiplayer / Sport Mode**: **multi-year lift**; roadmap-excluded.

---

_Identities and hardware are grounded in `AGENTS.md` + `docs/ROADMAP.md` + `docs/plans/match_fh6_gt7_plan.md` shipment ledger (`git log`: S1–S17 P2-2, F1–F5). GT7 cited sources: GTPlanet (update 1.71) https://www.gtplanet.net/gran-turismo-7-update-1-71-arrives-with-major-physics-changes-fanatec-fullforce-support-20260820 ; Traxion (Spec III) https://traxion.gg/gran-turismo-7-spec-iii-everything-you-need-to-know ; gran-turismo.com (update 1.69) https://www.gran-turismo.com/gb/gt7/news/00_8515746.html ; gran-turismo.com (Spec IV announcement) https://www.gran-turismo.com/gb/news/00_5621263.html ; Traxion (Spec IV) https://traxion.gg/gran-turismo-7s-new-spec-iv-update-heralds-return-of-the-autumn-ring-and-12-new-cars ; The Drive (Spec IV) https://www.thedrive.com/news/gt7-revives-autumn-ring-adds-12-new-cars-in-huge-spec-iv-update ; gran-turismo.com (Power Pack) https://www.gran-turismo.com/us/products/gt7/powerpack ; State of Play launch https://www.youtube.com/watch?v=JlbMzBnfnzM ; CogConnected review https://cogconnected.com/review/gran-turismo-7-review/ ; Eurogamer review https://www.eurogamer.net/gran-turismo-7-review-sonys-flagship-series-returns-to-its-ps2-glory-days_