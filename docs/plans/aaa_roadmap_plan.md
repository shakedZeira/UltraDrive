# UltraDrive — AAA Roadmap Plan (AAA-feel & AAA-depth on an AA-tech budget)

**Written:** 2026-09-23 · **Status:** execution-ready · **Engine:** Godot 4.7.2 (settled — Unity/"HiggsField" disproven, UE5 assessed, stay).
**Sources synthesized:** `docs/research/ultradrive_vs_fh6.md` (ranked gaps vs Forza Horizon 6), `docs/research/ultradrive_vs_gt7.md` (ranked gaps vs Gran Turismo 7), `docs/ROADMAP.md` ("No tech ceiling" — ambitions never trimmed to engine), `docs/research/feature_comparison.md`, `docs/research/self_audit.md`, house plan conventions from `docs/plans/match_fh6_gt7_plan.md`, `docs/plans/open_world_seeding_plan.md`, `docs/plans/first_person_view_plan.md`.
**Verification baseline:** **641 GDUnit tests / 0 errors / 0 failures across 63+ suites** (git-confirmed shipped state through `b24d60e`).

---

## 1. Executive Summary — what "AAA" means for UltraDrive

UltraDrive will not match Forza Horizon 6's renderer or Gran Turismo 7's roster. It does not need to. **"AAA" for UltraDrive = AAA-feel and AAA-depth delivered on an AA-tech budget:** the race ceremony, discovery loop, economy loop, accessibility slate, presentation surfaces (photo/replay/telemetry), audio-feel layers, and live-cadence mechanisms that make a racing game read as a premium product — all at a **locked 60 fps on a GTX 970**, a GPU FH6's own minimum spec (Turing) refuses to run on at all. That hardware-floor coverage is our structural marketing niche; the FH6/GT7 comparison docs both conclude the same: *world density + discovery + feel, not pixels, is what won those games their reviews.*

This plan merges **both** fresh research docs' ranked gap lists into **one unified 21-item backlog** (deduplicated: photo mode, rival-AI polish, accessibility/S15, and audio-feel each appeared in both docs), grouped into **5 phases**, every item carrying the house **Goal / Today-vs-Target / Work / Acceptance test gate / Effort / Depends-on / Sub-agent** contract.

### Hard red lines (never chased — stated plainly so no session re-litigates them)

1. **No RT, no 4K/8K natives, no DLSS MFG, no PSSR, no VR.** GTX 970 = Maxwell, no RT cores, EOL drivers (560.94). FH6's minimum NVIDIA arch is *Turing* — we are two generations below the competitor's own floor. These are hardware ceilings, not work items.
2. **No roster-count race.** FH6 ships 636 licensed cars, GT7 ~574. We ship 6 license-safe originals + CC0 kit and win on **garage depth**, never on count. 600+ OEM licenses = unreasonable for a small team, forever.
3. **Multiplayer is not core.** No netcode, no servers, no ranked sport mode before/around v1. The only wedge ever promised is post-v1 **LAN / split-screen**.
4. **No GB-scale content, no licensed 224-track radio.** Content stays data-cheap (synthesized audio, `.tres` packs, procedural world).
5. **No grind-paywall monetization, ever.** Both incumbents' economies are their worst-reviewed systems (FH6 voucher/CR-cap controversy, GT7 credit-pack + $29.99 Power Pack backlash). Our launch plank inverts them: *no grind, no paywall, one purchase.*

---

## 2. Current state snapshot (shipped — do not re-plan any of this)

STATUS conventions for this document: `- [x]` = shipped/verified in repo · `- [ ]` = open work item (each maps to `AAA-n` below).

**The bench:** `- [x]` **641 GDUnit tests green, 0 errors / 0 failures, 63+ suites** — the gate every AAA item must keep monotonically green.

Shipped feature blocks (one-liners, suite named):

- `- [x]` Full race loop: countdown 3-2-1-GO, checkpoint/lap/standings, results overlay + celebration, session stats (`test_race_countdown`, `test_race_results`, `test_session_stats`, `test_race_loop`).
- `- [x]` GPS route + brake-line assist + NavWidget HUD (`test_gps_route_follow`, `test_map_route`, `test_discovery`).
- `- [x]` No-rubber-band rival AI, Novice/Skilled/Expert tiers, racing lines (`test_rival_ai`) — the named competitive edge vs Drivatar and paywalled GT Sophy.
- `- [x]` Living traffic: route-follow, lane avoid, parked cars, stuck-rescue (`test_traffic_driving`, `test_traffic_spawner`).
- `- [x]` 8-family event taxonomy + S/A/B/C scoring + economy stub (S11) (`test_event_rewards`, `test_event_placement`).
- `- [x]` Vehicle FX particles + drive-feel transients: body-rig, speed vignette, tire marks, chase transients (`test_vehicle_fx`, `test_drive_feel`).
- `- [x]` Weather VFX + 24 h sun + regional climate + surface grip registry (`test_weather_vfx`, `test_weather_sun`, `test_regional_climate`, `test_surface_grip`).
- `- [x]` Garage tuning sliders + paint + live dyno (S13) + ownership gates (`test_garage_tuning`).
- `- [x]` Open world P0–P7: road graph + tiers/junctions, elevation bands + biome palette, 12-corridor seeding, 256 m streaming (~80 ms crossing), discovery + fast travel, region-streamed dressing (`test_road_graph`, `test_corridor_seeding`, `test_terrain_biomes`, `test_terrain_seeder_streaming`, `test_streaming_dressing`, `test_open_world`).
- `- [x]` CC0 car kit + data-driven garage (`test_cc0_cars`); 6 cars, D–A classes, **no S-class yet**.
- `- [x]` Cockpit first-person F1/F2a/F4/F5: 4-mode C-cycle, procedural interior, dash-as-HUD, virtual mirror, Camera & Feel settings (`test_cockpit_camera`, `test_cockpit_interior`, `test_cockpit_hud`, `test_camera_settings`) + hood cam S14 (`test_hood_camera`).
- `- [x]` Career XP profile + license tiers + championship classes (`test_career_economy`); money ledger stub (S11).
- `- [x]` Save robustness + profile slots + corrupt-slot detection (S17 P2-2) (`test_profile_slots`, `test_save_manager`).
- `- [x]` Quality ladder Low/Med/High + hardware-detect first boot (`test_quality_ladder`, `test_settings_presets`); hardening audit suite (`test_hardening`); engine audio 3-bed + hybrid real-bed pitch tracking (`test_engine_audio`, `test_car_audio`).
- `- [ ]` Everything in the ranked backlog below (§3) — 21 open items across 5 phases.

---

## 3. Unified ranked gap backlog (FH6 + GT7, deduplicated)

Ranked by **impact × closability**. Every row cites its source doc; overlapping rows from the two research docs are merged (photo mode, rival-AI polish, accessibility↔S15, audio-feel layers, garage depth each appeared in both). Class = `cheap ugly-win` / `medium lift` / `multi-sprint` / `unreasonable (non-goal)`.

| # | Gap (deduplicated) | Source | Status today | Class | Effort | Lands in |
|---|---|---|---|---|---|---|
| 1 | Audio daily-feel layer: tire squeal/skid, impacts, wind, gearbox blurt, UI blips | both (FH6 #1, GT7 §8 garnish) | Open — 3-bed engine audio shipped, *readers* missing | cheap ugly-win | S (1 sprint) | AAA-1 |
| 2 | Close High-preset 57→60 fps locked bar + perf-gate suite | FH6 #9 | Open — Low 93 / Med 65 / **High 57** @1080p GTX 970 | cheap ugly-win, high story value | S (1 sprint) | AAA-2 |
| 3 | Photo Mode + map filters (marketing surface) | both (FH6 #4, GT7 #6 Scapes-lite) | Open — orbit cam + settings shipped | cheap ugly-win | S–M (1 sprint) | AAA-3 |
| 4 | Nameable, persistent rival personalities ("players race *people*") | both (FH6 #5 Drivatar lesson, GT7 #5 polish) | AI shipped & fair; personality/name layer open | cheap ugly-win | S–M (1 sprint) | AAA-4 |
| 5 | Replay mode — ghost/state recorder + camera playback | GT7 #2 | Open — standings/drift/speed already emitted; no recorder | cheap ugly-win | M (1 sprint) | AAA-5 |
| 6 | Per-car default-setup pass + downshift-guard sibling (GT7 1.71 *process*) | GT7 #12/§5 | Partial — over-rev guard shipped; per-car defaults not staged | cheap ugly-win | S (1 sprint) | AAA-6 |
| 7 | Economy loop completion: S-class car, championship payouts, garage→tune→event→buy closure | both (FH6 #2) | Partial — S11 stub + XP + ownership gates shipped; loop open at the ends | cheap ugly-win | M (1–2 sprints) | AAA-7 |
| 8 | Championship / curated season ladder over the 8 event families (GT7 Menu-Book + Seasonal-Menu lesson) | GT7 #1 | Open — `Championship`/`LicenseSystem` classes exist, unstaged | cheap ugly-win | M (1–2 sprints) | AAA-8 |
| 9 | Circuit-Experience-style section / best-sector challenges | GT7 #4 | Open — GPS route + checkpoint timing shipped | cheap ugly-win | M (1 sprint) | AAA-9 |
| 10 | Dealership / used-car rotation over the owned run | GT7 #7 | Open — S11 ledger shipped | cheap-medium | S–M (1 sprint) | AAA-10 |
| 11 | Car Viewer / gallery surface (small garage reads curated) | GT7 §9 | Open — orbit cam + garage shell shipped | cheap ugly-win | S (1 sprint) | AAA-11 |
| 12 | Event variety per family: weather / TOD / season overrides | FH6 #6 | Open — 8 families + climate/TOD systems shipped | medium lift | M (1 sprint) | AAA-12 |
| 13 | Garage / tuning / livery-lite depth on the 6 cars (roster substitute) | both (GT7 #9, FH6 §1) | Partial — S13 sliders+paint shipped; depth/livery open | medium lift | M (1–2 sprints) | AAA-13 |
| 14 | Open-world visual biome pass: full-world color bake + 2nd biome | FH6 #7 | Partial — P1 bake seams exist; per FH6 doc seeded open world still reads height-only (verify `_write_region` TYPE_COLOR first) | medium lift | M–L (2–3 sprints) | AAA-14 |
| 15 | Authored landmark clusters — "one memorable place with one twist" | both (FH6 §2, GT7 §2 Autumn Ring lesson) | Open — generic guardrail/tent/pole/rock dressing only | medium lift | M (1–2 sprints) | AAA-15 |
| 16 | Collectibles / discovery rewards: bonus boards, speed traps, photo spots | FH6-shaped (`feature_comparison` P1-2, `self_audit` §2.2) | Open — discovery loop shipped, no pickups feeding it | cheap-medium | S–M (1 sprint) | AAA-16 |
| 17 | Accessibility launch slate: autodrive, colorblind filters, in-game rebind UI, HUD scaling, proximity radar | both (FH6 #3 = S15 mirror, GT7 §12 Family) | Partial — assists, contrast HUD, input curves, F5 feel flags shipped; headline slate open | cheap ugly-win, **launch-blocking** | M (1–2 sprints) | AAA-17 |
| 18 | Shuffle Race + Family named presets (low-friction entry mode) | GT7 #3 | Open | cheap ugly-win | S (1 sprint) | AAA-18 |
| 19 | Telemetry / Data Logger graph over emitted variables | GT7 #8 | Open — drive_info/drift/standings emitted; no consumer | medium lift | M (1 sprint) | AAA-19 |
| 20 | Data-only content schedule packs (monthly no-grind cadence *mechanism*) | FH6 #8 | Open — no `ContentSchedule` module in tree | cheap mechanism (operation = live cadence) | M (1 sprint) | AAA-20 |
| 21 | LAN / split-screen wedge (the only multiplayer ever promised pre–post-v1) | both (FH6 #10, GT7 #10 note) | Open | medium, **post-v1 only** | L (2+ sprints) | AAA-21 |

### Declared non-goals (hard red lines — never backlog rows)

| Gap | Source | Verdict |
|---|---|---|
| Roster count parity (636 FH6 / ~574 GT7 vs our 6) | both | **Unreasonable (XL).** Answered by garage depth (AAA-13) + rotation (AAA-10). |
| RTGI / RT reflections / native 4K30–4K120 / 8K / DLSS 4.5 MFG / PSSR | both | **Hard ceiling.** Maxwell has no RT cores; FH6 min spec = Turing; our launch bar is locked-60 1080p with FSR 2.2 (works on the GPU FH6 refuses). |
| VR / PSVR2 | GT7 | **Hard ceiling + unreasonable** on the 970. |
| UGC / EventLab / auctions / auction house | FH6 | **Unreasonable (XXL).** |
| 224-track licensed soundtrack | FH6 | **Unreasonable (XXL).** CC0/procedural only; optional CC0 radio shell is non-blocking. |
| Online multiplayer / Sport Mode / ranked ratings / Sophy-class RL AI | both | **Multi-year, roadmap-excluded.** Post-v1 LAN/split only (AAA-21). Our answer to Sophy is free, fair, tiered rivals (already shipped). |
| 360° sim-fidelity physics | GT7 | **Not a gap — arcade identity.** Steal the 1.71 *process* only (AAA-6). |
| DirectStorage-class GPU streaming | FH6 | **Not needed.** 256 m streaming at ~80 ms crossing already meets the feel bar. |

---

## 4. Phased execution

Five phases. Every implementable item follows the house contract: **Goal / Today vs Target table / Work / Acceptance test gate (exact suite name + assertion sketch) / Effort / Depends-on / Sub-agent note.** Nothing in this plan rebuilds a shipped system — each item extends or reads an existing, suite-guarded one.

### Phase A — Feel & Loop completeness (why now: zero-dependency ugly-wins on top of shipped systems)

Why now: every Phase A item is a *reader* or *closer* over state the 641-test build already emits (engine beds, standings, orbit cam, rival roster) or a launch-bar number already half-measured (High 57 fps). Nothing here waits on anything else — this phase is deliberately front-loaded because these five cheap wins plus the perf bar are what make a first 10 minutes *feel* AAA.

#### AAA-1. Audio daily-feel layer

- **Goal:** Add the daily-feel audio beds both research docs call the cheapest feel-per-dollar win — tire squeal/skid, impacts, wind rush, gearbox blurts, UI blips — layered onto the shipped 3-bed/real-bed engine audio without touching its crossfade core.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Engine | 3-bed synth + hybrid real-bed continuous pitch (`car_audio.gd`, `test_engine_audio`/`test_car_audio` green) | unchanged core |
  | Tire/friction | none | squeal/skid bed keyed on lateral slip + `SurfaceRegistry` surface key + handbrake |
  | Impacts | `VehiclePhysics.signal impact(strength)` shipped (S8) | impact one-shot scaled by strength |
  | Wind | none | speed-keyed noise bed (0→full across 60→200 km/h) |
  | Gearbox | upshift/downshift events exist in `drivetrain` | short blurt on shift, esp. manual mode |
  | UI | procedural countdown beeps exist (`countdown_audio.gd`) | menu/HUD blip set, headless-guarded |

- **Work** (A1, 1 sprint): extend `scripts/vehicle/car_audio.gd` with slip/wind beds reading `get_drive_info()`; impact one-shot bus fed from the shipped `impact` signal; shift blurt hook in drivetrain event path; UI blip player in `scripts/ui/` guarded headless (`DisplayServer.get_name() == "headless"` culls).
- **Acceptance test gate:** `tests/suites/test_audio_feel_layers.gd` — beds exist and crossfade without breaking the existing 3-bed asserts; squeal intensity monotonic with slip; wind bed monotonic with speed and silent at rest; impact one-shot fires exactly once per `impact` emission; headless run instantiates no AudioStreamPlayers that block (mirror `test_car_audio` stub discipline).
- **Effort:** S (1 sprint) • **Depends-on:** shipped `impact` signal, `SurfaceRegistry`, engine audio. • **Source:** FH6 ranked #1, GT7 §8.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails (§6).

#### AAA-2. Close High-preset 57→60 + perf-gate suite

- **Goal:** Hit the launch bar honestly — **locked 60 fps on Low, Medium AND High** on the GTX 970 reference @1080p — and make it a CI-enforced gate (`test_perf_gate` was planned in match-plan S16 but never shipped).
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Measured | Low 93 / Med 65 / **High 57** fps (`7ffb524` preset probe) | Low ≥60, Med ≥60, **High ≥60** avg on reference scene |
  | Gate | no `test_perf_gate.gd` in tree | headless fixed-timestep budget gate ≤16.7 ms avg rows per preset |
  | Headroom spend | open-world milestone 94.9 fps avg exists (`d8610ef`) | spend surplus on dressing (Phase C), not resolution |

- **Work** (A2, 1 sprint): profile High preset hot spots (SDFGI/SSR/volumetrics/MSAA/FSR scale are the knobs); cheapest correct lever wins — probe-refresh discipline, FSR scale 0.9→0.85 on High, shadow-pass trims already proven (`7825def`); add `scripts/bench/` reference-scene harness + gate assertions (runtime auto-pick stays the shipped `default_quality_preset()` fallback).
- **Acceptance test gate:** `tests/suites/test_perf_gate.gd` — reference scene avg frame-time ≤16.7 ms rows asserted for all three presets at fixed timestep headless; benchmark deterministically returns a valid preset id; no regression in `test_quality_ladder`/`test_settings_presets`.
- **Effort:** S (1 sprint) • **Depends-on:** quality ladder (shipped). • **Source:** FH6 ranked #9.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails.

#### AAA-3. Photo Mode + map filters

- **Goal:** A real Photo Mode (freeze-frame, hide-UI, FOV/aperture + filter sliders, screenshot export) over the shipped orbit/camera rigs, plus category filters on the world map — flagged in *both* research docs and the single cheapest marketing surface in the backlog.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Cameras | chase/orbit/hood/cockpit 4-cycle; F5 Camera & Feel settings | Photo Mode sub-state: pause world, free orbit, FOV/aperture/DoF-lite, filters |
  | Export | none | `Viewport.get_texture()` → PNG to user:// |
  | Map | grey→white reveal + fast travel (`test_world_map_features`) | category filters (events/POIs/landmarks/travel) + filter-by-region |
  | HUD | always on | hide-UI toggle inside photo mode |

- **Work** (A3, 1 sprint): `scripts/ui/photo_mode.gd` state over `orbit_camera.gd` (reuse F5 settings pattern for sliders); screenshot writer headless-guarded; `world_map.gd` filter flag set + POI-category buckets from `poi_registry`.
- **Acceptance test gate:** `tests/suites/test_photo_mode.gd` — photo state round-trips (enter/exit restores camera + HUD visibility); filter math pure-assert (POI set filtered by category exactly); screenshot path writes only when not headless; existing `test_camera_settings`/`test_world_map_features` stay green.
- **Effort:** S–M (1 sprint) • **Depends-on:** orbit cam + F5 (shipped). • **Source:** FH6 #4, GT7 #6.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails.

#### AAA-4. Nameable persistent rival personalities

- **Goal:** Deepen the shipped no-rubber-band rival AI into *people*: a persistent roster of named rival personalities (handle, tier, signature trait, rivalry record) shown on grid, standings and results — the "bowie knife99" lesson from both docs: players race people, and our clean AI is already the field neither incumbent can defend.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Rivals | `rival_driver.gd` + tiers + roster spawn (`test_rival_ai` green) | + `RivalPersona` (name, tier, trait e.g. late-braker/drafter, W/L record) |
  | Presentation | anonymous grid | names on grid card, live standings, results rows |
  | Persistence | none | persona records in save (S17 slot schema) |

- **Work** (A4, 1 sprint): `scripts/ai/rival_persona.gd` (pure RefCounted + deterministic name pool seeded per save); RaceManager attaches personas to roster; `race_ui`/results read name+record; persist under a new SAVE_KEY area.
- **Acceptance test gate:** `tests/suites/test_rival_personalities.gd` — persona assignment deterministic per seed; W/L record updates exactly once per finished rival; save/load round-trip; `test_rival_ai` invariants (tier pacing, no rubber-band on player) unchanged.
- **Effort:** S–M (1 sprint) • **Depends-on:** rival AI + results + profile slots (all shipped). • **Source:** FH6 #5, GT7 #5.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails.

#### AAA-5. Replay mode (recorder + playback)

- **Goal:** Record a driven run (positions/inputs/standings/drift/speed — all already emitted) and play it back through the existing camera rigs with a simple timeline — GT7's replay culture at Scapes-lite scope.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | State | standings, drift time, speed, lap splits all emitted; no recorder | `ReplayRecorder` samples transforms + timeline events per fixed tick |
  | Playback | none | ghost/playback entity re-drives recorded stream; camera cycle works during playback |
  | Storage | none | bounded buffer (N seconds), persisted PB clips optional later |

- **Work** (A5, 1 sprint): `scripts/race/replay_recorder.gd` (pure, fixed-tick sample buffer) + playback node; hook at `race_ui` finish and free-roam capture toggle; headless-culled playback visuals.
- **Acceptance test gate:** `tests/suites/test_replay_recorder.gd` — record→replay determinism (same samples → identical transform stream within tolerance); buffer cap enforced (no unbounded growth); finish-line event timestamps preserved; no physics dependence beyond stored samples; orphan count ≤ baseline.
- **Effort:** M (1 sprint) • **Depends-on:** emitted state (shipped); pairs with AAA-1's feel later. • **Source:** GT7 ranked #2.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails.

#### AAA-6. Per-car default-setup pass + downshift-guard sibling

- **Goal:** Steal GT7 1.71's most transferable *process*: a documented default setup (suspension/diff/balance baselines) per car in `resources/cars/*.tres`, plus finishing the downshift-protection sibling to the already-shipped over-rev guard.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Configs | 6 cars with physics-valid defaults but no staged "setup identity" | per-car `default_setup` block: baseline springs/dampers/diff/balance with design intent noted in data |
  | Downshift | over-rev guard shipped (`redline*1.05` reject) | + forced-downshift prevention under hard lateral load (arcade-compatible) |
  | Feel cadence | data-driven but no per-cycle pass discipline | this pass *is* the first cycle (GT7's evergreen-feel lesson) |

- **Work** (A6, 1 sprint): author `default_setup` data across the 6 `.tres`; `drivetrain.gd` lateral-load downshift veto (small, single site); document the re-tune cadence in the plan (each future car ships with a setup block).
- **Acceptance test gate:** `tests/suites/test_car_default_setup.gd` — every `resources/cars/*.tres` exposes a valid default_setup within config bounds; downshift veto rejects under high lateral G and allows at rest; existing `test_transmission_modes`/`test_vehicle_physics`/`test_cc0_cars` stay green.
- **Effort:** S (1 sprint) • **Depends-on:** drivetrain + configs (shipped). • **Source:** GT7 ranked #12/§5 ("steal the process, not the fidelity").
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails.

---

### Phase B — Career depth & content systems (why now: Phase A closed the *feel*; the loop's ends are still open)

Why now: the S11 ledger stub, XP profile, license tiers, championship class, 8 event families, GPS and garage tuning are all shipped and suite-guarded — what's missing is the *frame* (ladder, payouts, sinks) the GT7 and FH6 docs both call the single largest fun gap. Phase B is ordered economy-first because AAA-7's payouts feed AAA-8/9/10/16/20 rewards; nothing else in the phase can pay the player until it lands.

#### AAA-7. Economy loop completion (S-class car, championship payouts, full closure)

- **Goal:** Close the loop end-to-end: **garage → tune → event → win → payout → buy car → championship** — a headline S-class car to spend on, championship→payout wiring, and a "cost of success" balance pass that lets us invert both incumbents' economy controversies into a launch plank (*no grind, no paywall, one purchase*).
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Ledger | `money.gd` zero-sum stub + S/A/B/C event rewards (`test_event_rewards`, `test_career_economy`) | fully wired: race position → points → credits; all 8 families pay |
  | Roster top | A-class Interceptor only, no S | S-class hero car (data `.tres` + CC0/GLB visual) with price tuned to ~mid-career grind-free earn rate |
  | Championship | points class exists, no payout path | season completion → podium payout + license XP |
  | Sinks | tuning/paint gated but no purchase flow completion | buy/sell → ledger → garage ownership verified in one integration suite |

- **Work** (B7, 1–2 sprints): wire `RaceUI.POSITION_POINTS` + `event_scoring.reward` → ledger for every family; author the S-class car (CC0-first per license policy); championship podium payout table; economy balance pass (earn rates vs prices: full loop completable without grind in a target session count).
- **Acceptance test gate:** `tests/suites/test_economy_loop.gd` — one scripted full loop (earn → buy → tune → enter → win → payout) keeps the ledger zero-sum and never negative; S-class car exists, is priced, unlockable only via ownership gates; every one of the 8 event families emits exactly one payout; save/load round-trips mid-loop.
- **Effort:** M (1–2 sprints) • **Depends-on:** S11 stub, event rewards, garage (shipped). • **Source:** FH6 ranked #2.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails.

#### AAA-8. Championship / curated season ladder

- **Goal:** Wrap the shipped 8 event families + license tiers in a curated Menu-Book-style sequence with an ending unlock and a post-ending seasonal rotation — GT7's career spine at frame-cost, not content-cost.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Career | free-form event selection; XP/licenses exist unstaged | ordered ladder: stage = themed run through families, gated by license/class; completion pays AAA-7 rewards |
  | Ending | none | final stage unlock (S-class event / elite license ceremony) |
  | Post-game | none | seasonal rotation pointer (feeds AAA-20 packs) |

- **Work** (B8, 1–2 sprints): `scripts/career/season_ladder.gd` (pure stage defs over existing `event_registry` data + `LicenseSystem` gates); ladder UI page in pause/garage shell; persistence under save.
- **Acceptance test gate:** `tests/suites/test_championship_ladder.gd` — stages resolve in order, gating depends only on persisted state (no scene frames), completion pays exactly once, final unlock flips, ladder round-trips through save; existing `test_career_economy` stays green.
- **Effort:** M (1–2 sprints) • **Depends-on:** AAA-7 (payouts), shipped 8 families + licenses. • **Source:** GT7 ranked #1.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails.

#### AAA-9. Circuit-Experience-style section challenges

- **Goal:** Give the single open world more *remembered places*: per-route section/best-sector challenges (start gate → split timing → best-sector ghost target) over the shipped GPS routes and checkpoint machinery — GT7 Circuit Experience, Autumn-Ring lesson.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Timing | lap/checkpoint timing in races; time_attack family placed | section splits on named route segments (touge hairpins, highway blast, coast run) |
  | Feedback | results screen at event end | live ±delta vs personal best sector (HUD already draws gap timers) |
  | Persistence | best event score under `SAVE_KEY="events"` | + per-section best times |

- **Work** (B9, 1 sprint): section defs as data on existing routes (pure Resource list); split timer + delta readout reusing `race_ui` gap-draw path; best-sector persistence beside event bests.
- **Acceptance test gate:** `tests/suites/test_section_challenges.gd` — splits fire in order at section boundaries; delta math exact against recorded times; best-sector persists and improves monotonically; sections placed only on valid revealed routes; no dependence on physics frames past stored times.
- **Effort:** M (1 sprint) • **Depends-on:** GPS route + checkpoint timing (shipped), AAA-7 for rewards. • **Source:** GT7 ranked #4.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails.

#### AAA-10. Dealership / used-car rotation

- **Goal:** A small used-car rotation over the shipped run of cars — a rotating "in stock today" slate with soft price variation — giving the ledger a GT-flavored acquisition texture **without** GT7's invitations/roulette/paid credits (explicit anti-lesson: never monetize economy progression).
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Buying | garage ownership gates + ledger | + dealership page: owned/not-owned matrix, rotating stock (deterministic per in-game week), used prices ~0.6–0.85× base |
  | Rotation | none | pure function of week index — headless-testable, save-persisted |

- **Work** (B10, 1 sprint): `scripts/career/dealership.gd` (pure rotation function + buy flow into `Garage`/`money`); garage-UI dealership tab.
- **Acceptance test gate:** `tests/suites/test_used_car_rotation.gd` — rotation deterministic per week index and identical across reload; purchase moves ownership + debits exactly once; never sells cars outside the defined roster; ledger stays zero-sum; no paid-credit path exists (assert absence).
- **Effort:** S–M (1 sprint) • **Depends-on:** AAA-7 ledger completion (stub sufficient to start). • **Source:** GT7 ranked #7.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails.

#### AAA-11. Car Viewer / gallery surface

- **Goal:** A standalone gallery scene to admire owned cars (slow orbit, name/class/stat card, paint+tune applied) — makes a 6–10 car garage read *curated*, GT7 Car Viewer / FH Forzavista-lite, using the orbit camera we already own.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Viewing | garage carousel + turntable (shipped) | full-screen viewer: free slow orbit, spotlight, stat/name card, next/prev owned car |
  | Cameras | orbit rig exists (F1-adjacent maths) | viewer scene reuses orbit follow with gallery framing defaults |

- **Work** (B11, 1 sprint): `scenes/ui/car_viewer.tscn` + `scripts/ui/car_viewer.gd` (loads owned cars from `Garage`, applies `CarVisuals` paint/tune state, orbit control); entry points from garage + photo mode hand-off.
- **Acceptance test gate:** `tests/suites/test_car_viewer.gd` — viewer lists exactly the owned set from save; switching cars swaps config+visual without leaks; works headless (no renderer asserts); entry/exit restores previous scene via `SceneTransition`.
- **Effort:** S (1 sprint) • **Depends-on:** garage + orbit cam (shipped). • **Source:** GT7 §9.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails.

#### AAA-12. Event variety per family (weather / TOD / season overrides)

- **Goal:** FH6's Race Customizer lesson at data cost: each placed event can override weather, time-of-day and season using the shipped climate/TOD systems, so the same 8 families replay with different moods.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Event def | `event_def.gd` {type, objective, checkpoints, payout} | + optional `override_weather/override_tod/override_season` |
  | Systems | `WeatherManager`, `DayNightDriver`, regional climate shipped | event session applies overrides on start, restores on exit (mirror S7's `set_enabled` pause-gate pattern) |
  | Placement | deterministic per seed | variants seeded per event (night touge duel, storm drag, dawn marathon) |

- **Work** (B12, 1 sprint): extend `event_def` + `event_session` apply/restore; variant fields in `event_registry.place_data`; optional per-event HUD mood badge.
- **Acceptance test gate:** `tests/suites/test_event_variety.gd` — overrides apply exactly on event start and restore exactly on exit (weather/TOD/season equal pre-event values); override values validated against enums; headless-safe (no frame-dependent asserts); `test_event_rewards`/`test_event_placement` stay green.
- **Effort:** M (1 sprint) • **Depends-on:** event session + weather/TOD (shipped). • **Source:** FH6 ranked #6.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails.

#### AAA-13. Garage / tuning / livery-lite depth (roster substitute)

- **Goal:** Deepen S13's sliders+paint into FH6/GT7-grade *garage depth on a curated fleet*: upgrade tiers, livery-lite (decal layers over paint), stat-comparison before/after, per-car setup pages — the named strategy for never racing the 574/636 count.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Tuning | gear/final-drive/mass sliders + dyno (S13, `test_garage_tuning`) | + spring/damper/downforce sliders + 2–3 upgrade tiers mutating `CarConfig` |
  | Paint | swatch picker | + 2-layer livery-lite (stripe/accent decal params on `CarVisuals`) |
  | Compare | live stat line | before/after stat delta bars in garage UI |

- **Work** (B13, 1–2 sprints): extend `tuning_profile.gd` override set; upgrade-tier data in `.tres`; decal params in `car_visuals.gd`; garage tabs gain compare rows; all behind existing ownership gates.
- **Acceptance test gate:** `tests/suites/test_tuning_depth.gd` — every slider/tier keeps derived physics within config bounds (mirror S13 clamp asserts); livery params round-trip through save; non-owned cars cannot tune/paint (keep `9067d11` gate semantics); `test_garage_tuning` + `test_car_visuals` stay green.
- **Effort:** M (1–2 sprints) • **Depends-on:** S13 (shipped), AAA-7 for upgrade prices. • **Source:** both (GT7 #9, FH6 §1 garage-depth lesson).
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails.

---

### Phase C — World density & discovery (why now: the discovery *loop* is shipped; it needs things worth discovering)

Why now: fog-of-war reveal, fast travel, GPS, region streaming and dressing bands are all green (`test_discovery`, `test_streaming_dressing`…). FH6's reviewer takeaway — **world density + discovery, not pixels, won the reviews** — lands exactly here, and AAA-14 must precede AAA-15/16 because landmarks and collectibles need a visible biome world to sit in.

#### AAA-14. Open-world visual biome pass (full-world color bake + second biome)

- **Goal:** Make the seeded open world *render* its elevation/biome table — extend the Terrain3D color bake across the streamed world (Mountain Pass precedent), then activate a second biome zone from the existing biome table — closing FH6 gap #7 (M–L "cheap-to-close" per feature_comparison too).
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Bake | P1 shipped elevation bands + 10-biome palette + color bake seams (`test_terrain_biomes`); per `ultradrive_vs_fh6` §6 the **seeded open world still reads height-only** — first task is verifying `terrain_seeder._write_region` TYPE_COLOR wiring | every streamed region writes TYPE_COLOR; roads tinted; biome bands visibly distinct in-world |
  | Biomes | numeric bands, one visual read | ≥2 clearly distinct visual zones (e.g. rolling farmland vs highland/alpine) using existing table entries |
  | Perf | streaming at ~80 ms crossing | color channel must not regress `test_terrain_seeder_streaming` budgets |

- **Work** (C14, 2–3 sprints): (0) verify/fix seeder color-channel wiring against the Mountain Pass precedent (`mountain_pass.gd` color_img pattern); (1) road-corridor tint in bake; (2) second-biome zone parameterization + dressing preset blend; (3) memory/bandwidth check per the open-world plan's architecture note (half-res color + shader sample only if profiling demands — cost, not capability).
- **Acceptance test gate:** `tests/suites/test_terrain_biomes.gd` (extended) — color image bit-deterministic per region hash across the *seeded* world (not just Mountain Pass); second-biome region hash set deterministic; road corridors still recess; existing conform/streaming suites stay green; watchdog discipline held.
- **Effort:** M–L (2–3 sprints) • **Depends-on:** P0–P7 (shipped). • **Source:** FH6 ranked #7.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails.

#### AAA-15. Authored landmark clusters

- **Goal:** 2–3 authored landmark clusters (hub festival grounds, alpine overlook shrine, coast lighthouse) with POI gameplay hooks — the GT7 Autumn Ring lesson: *one memorable place with one twist* beats a long list of bland layouts; also fixes the audit's "scenery stops at null props" finding.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Dressing | fused-primitive guardrail/tent/pole/rock + CC0 building/rock/tree kit (`asset_pass_3d`) | 3 named landmark clusters at corridor tips/junctions, CC0-first, distance-faded |
  | POIs | 5 base landmarks + event markers | +3 landmark POIs with discovery credit (feeds AAA-16 payouts via AAA-7) |

- **Work** (C15, 1–2 sprints): landmark scenes from CC0 kit assets placed deterministically per master seed via `poi_registry`/`prop_scatterer` presets; clear-of-road rejection kept; POI entries + map dots + brief discovery text.
- **Acceptance test gate:** `tests/suites/test_landmark_clusters.gd` — landmarks spawn at deterministic seeds, never overlap roads (`is_on_road` rejection), survive re-stream without duplication (mirror `test_streaming_dressing` ring asserts), register exactly once in `POIRegistry`.
- **Effort:** M (1–2 sprints) • **Depends-on:** AAA-14 (visible biomes), CC0 asset pass (shipped). • **Source:** both (FH6 §2, GT7 §2).
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails.

#### AAA-16. Collectibles & discovery rewards

- **Goal:** Feed the shipped discovery loop: bonus boards, speed traps and photo spots as POI entries that pay AAA-7 credits exactly once — turning map size into content FH6-style (400 boards → our honest dozen-plus).
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | POIs | markers shown, nothing interactive | interactive collectible class: board smash / trap trigger / photo-spot enter |
  | Reward | none | credit payout via ledger, once per save; discovery % readout on map |
  | Placement | deterministic registry | collectibles seeded on road-adjacent clear ground per corridor class |

- **Work** (C16, 1 sprint): `scripts/world/collectibles.gd` (pure placement + claim state) + interaction trigger at player radius; map completion % row; persistence beside discovery SAVE_KEY.
- **Acceptance test gate:** `tests/suites/test_collectibles.gd` — claims pay exactly once across save round-trip; placement deterministic + clear of roads; completion % monotonic and hits 100% only when all claimed; `test_discovery`/`test_world_map_features` stay green.
- **Effort:** S–M (1 sprint) • **Depends-on:** AAA-7 payouts (stub OK to start), discovery (shipped). • **Source:** FH6-shaped (`feature_comparison` P1-2, `self_audit` §2.2).
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails.

---

### Phase D — Accessibility & launch readiness (why now: launch-blocking per ROADMAP 3.1 and both research docs)

Why now: both incumbents treat a11y as headline marketing, not polish — FH6's slate *is* the parity gap named in FH6 ranked #3, and GT7 Spec IV's Family mode proves even Polyphony ships a low-friction entry mode. Autodrive reuses the shipped GPS `route_planner`; colorblind filters are palette math; rebind + HUD scale are the medium tail. This phase must complete before any public build.

#### AAA-17. Accessibility launch slate

- **Goal:** Ship the FH6-class headline slate: **autodrive** (follow the GPS route hands-off), **colorblind scene filters**, **in-game rebind UI**, **HUD scaling**, **car proximity radar** — promoting our existing assists, F5 feel flags and S15 partial work into a named launch feature set.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Assists/feels | traction/steer/drift assists, shake/bob/FOV/reduced-motion (F5), contrast HUD (`test_hud_contrast`), input curves (`test_input_curves`) | keep; expose as named assist presets incl. a "Family" easy preset (see AAA-18) |
  | Autodrive | `route_planner.gd` snap + GPS polyline shipped | autodrive follows route via the shipped `input_override` AI seam; toggle in HUD/settings |
  | Colorblind | none | deuteranopia/protanopia/tritanopia palette swaps for map, brake-line, HUD accents (pure color math) |
  | Rebind | defaults only (`test_input_mapping`) | rebind UI → persisted InputMap overrides per slot |
  | HUD scale | fixed | HUD scale/opacity slider applying to `%Cluster` + overlays |
  | Radar | none | proximity radar widget (angle/distance of nearby cars from `VehicleManager`) |

- **Work** (D17, 1–2 sprints): `autodrive.gd` consumer of `BrakeLine`/`RoutePlanner` through input seam; palette tables + shader/UI flag; `options_menu` rebind page (S15's planned shape); HUD scale via CanvasItem scale persisted like `quality_preset`; radar Control drawing vehicle positions.
- **Acceptance test gate:** `tests/suites/test_accessibility_options.gd` — autodrive holds route within tolerance headless (pure path-follow asserts, no physics frames); palette swaps are exact table lookups; rebind round-trips through save and never binds two actions to one conflicting event without explicit override; HUD scale clamps [0.75, 1.5]; radar list ≤ N nearest and excludes self; all F5/HUD-contrast suites stay green.
- **Effort:** M (1–2 sprints) • **Depends-on:** GPS route + input seam + F5 (shipped). • **Source:** FH6 ranked #3 (= S15 mirror), GT7 §12. **Launch-blocking.**
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails.

#### AAA-18. Shuffle Race + Family named presets

- **Goal:** Two named low-friction modes: **Shuffle Race** (random car from your owned pool, random valid event) and **Family** (the assist/difficulty ladder promoted into a named easy-entry preset) — GT7 Spec IV's lesson that even shipped-AAA ships a kids/beginners door.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Modes | 8 families + free roam | + Shuffle Race launcher (owned-pool RNG, seeded per attempt) |
  | Difficulty | arcade/sim switch + assists (dispersed) | "Family" preset: one toggle applying auto-transmission, brake-line, gentler rivals tier, reduced shake |

- **Work** (D18, 1 sprint): shuffle picker (pure RNG over `Garage` owned ids) + launcher reusing `event_session`; Family preset as a settings macro applying existing flags (no new physics).
- **Acceptance test gate:** `tests/suites/test_shuffle_family.gd` — shuffle only ever picks owned cars, is seeded-deterministic in tests, and launches a valid event; Family preset sets every expected flag and round-trips through save; `test_event_rewards` stays green.
- **Effort:** S (1 sprint) • **Depends-on:** owned garage + event session (shipped), AAA-17 presets for Family glue. • **Source:** GT7 ranked #3.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails.

#### AAA-19. Telemetry / Data Logger

- **Goal:** GT7 Data Logger-lite: graph existing telemetry (speed, throttle/brake, RPM, gear, slip, G) over a recorded run — the third presentation-extra both docs note is 100% reader over state we already emit.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Signals | `get_drive_info()`, steer/throttle getters, drift/session stats all emitted | sampled into a `TelemetryTrack` during any run |
  | Consumer | none | post-run graph page (Canvas draw, 4 channels selectable), export CSV optional |

- **Work** (D19, 1 sprint): `scripts/race/telemetry_logger.gd` (pure ring buffer + downsample) + graph Control; toggle in pause/results.
- **Acceptance test gate:** `tests/suites/test_telemetry_logger.gd` — buffer bounded; samples align to timestamps; downsample preserves min/max envelopes; graph node renders sample counts headless without scene frames; no leak after clear.
- **Effort:** M (1 sprint) • **Depends-on:** emitted drive info (shipped); pairs with AAA-5 recorder. • **Source:** GT7 ranked #8.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails.

---

### Phase E — Post-v1 live cadence (why now: mechanism before operation; both incumbents' cadence is table stakes, their monetization is the anti-pattern)

Why now: AAA-7/8/10/16 have created rewards and stages worth rotating; the FH6 doc ranks the content-schedule *mechanism* as a cheap ugly-win (only the multi-year *operation* is out of scope). Ships as skeleton in-plan; operation runs post-v1.

#### AAA-20. Data-only content schedule packs

- **Goal:** A `ContentSchedule` of data-only `.tres` packs (theme + event variants + collectible/landmark additions + reward boosts) loadable on boot without touching core code — FH6 Festival Playlist / GT7 monthly-drop *shape*, executed with **no battle pass, no grind gate, no paywall**.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Content | static seed-placed events/POIs | pack list merges additional defs on boot; active pack selectable; rewards flagged as pack bonuses |
  | Cadence | none (`FH6` doc §12: mechanism absent from tree) | `ContentSchedule` + first-party "Season 1" demo pack + ops rhythm doc |
  | Monetization | none (by policy) | asserted absence: no paid entry, no time-gating of owned content |

- **Work** (E20, 1 sprint): `scripts/content/content_schedule.gd` (RefCounted, loads ordered pack Resources); merge hooks in `event_registry`/`poi_registry`/ladder; ship one demo season pack; short ops doc in the plan footer.
- **Acceptance test gate:** `tests/suites/test_content_cadence.gd` — every pack in `resources/content/` loads with all referenced resources existing (the match-plan's planned shape); merge is idempotent; disabling a pack restores baseline defs; no pack can gate content behind payment (structural assert).
- **Effort:** M (1 sprint) • **Depends-on:** AAA-8 ladder + AAA-7 rewards (shipped by then). • **Source:** FH6 ranked #8.
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails.

#### AAA-21. LAN / split-screen wedge (post-v1)

- **Goal:** The only multiplayer commitment in any launch story: local split-screen (and LAN peer-hosted same-heat racing) over the existing race loop — explicitly post-v1, explicitly *not* Sport Mode.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | Multi | none (roadmap 3.6 deferred) | 2-player split-screen on circuit events; synchronized `RaceManager` state |
  | Online | none | unchanged — no servers, no ranked, no anti-cheat |

- **Work** (E21, 2+ sprints, post-v1): split viewport rig + second input map; `RaceManager` dual-player standings; LAN peer discovery deferred to a follow-on if wanted.
- **Acceptance test gate:** `tests/suites/test_split_screen.gd` — both viewports instantiate one shared race state; dual input maps don't conflict (`test_input_mapping` extended); standings count both players; headless run creates no renderer-dependent nodes; full suite stays green.
- **Effort:** L (2+ sprints, post-v1) • **Depends-on:** race loop + input system (shipped); scheduled after launch. • **Source:** both (FH6 #10, GT7 #10 note).
- **Sub-agent:** one `general` sub agent, this item's text verbatim + playbook guardrails.

---

## 5. Engine & hardware honesty (the ceilings, stated once)

- **Reference hardware: GTX 970 (Maxwell, EOL driver 560.94), launch bar = locked 60 fps + crisp 1080p presentation.** No RT cores → no RTGI, no RT reflections. No Turing+ → **FH6's own minimum NVIDIA architecture is Turing; the 970 is below FH6's floor entirely** (support.forza.net PC specs, cited in `ultradrive_vs_fh6.md` §6). "We can't match AAA rendering" is *structural*, not a work item — it never appears in §3.
- **Red lines restated as ceilings:** RT / 4K natives / 4K120 / 8K / DLSS MFG / PSSR / VR are hard non-goals. FSR 2.2 (which *does* run on the 970) is our upscaler; that a locked-60 game runs on a GPU the AAA competitor refuses is the honest niche, not a compromise to hide.
- **What still sells "AAA-feel" on a 970** (each already shipped or in §3):
  1. **Locked 60** on all three presets (AAA-2) — briskness is the launch bar; FH6's DF analysis notes its base renderer is 2021-era, so the *kind* of presentation (SDFGI + FSR + 60) is reachable while its RT/ML extras are not.
  2. **Crisp UI & palette discipline** — cluster HUD, contrast-tested gauges, photo mode (AAA-3), gallery viewer (AAA-11): pixels-per-dollar presentation.
  3. **Motion & feel** — body rig, vignette, tire marks, chase transients, cockpit layers (shipped) + audio-feel (AAA-1) + personality (AAA-4).
  4. **World density & discovery** — the FH6 reviewer takeaway: *density + discovery, not pixels, won FH6.* Phase C is the direct expression of that finding.
  5. **Audio depth over audio assets** — synthesized/CC0 chain, zero license risk (both docs call this different-in-kind, not lesser).
- **"No tech ceiling" (ROADMAP) still applies inside the red lines:** cost/scope is the filter, never "Godot can't." If an §3 item reveals a genuine stack limit mid-flight, the item's PR states the tooling delta — that is expected work.

---

## 6. Sequencing & dependency map

**Sub-agent contract (house playbook, applies to every AAA item):** one work item = one `general` sub agent; prompt = item text **verbatim** (Goal + Today/Target + Work + gate) + guardrails (repo root `C:\Users\IMOE001\Desktop\Shaked Projects\UltraDrive\UltraDrive`; Godot `C:\Godot\Godot_v4.7.2-stable_win64.exe`; warnings-as-errors; same-type `is_equal_approx`; headless culling for FX; name the suite exactly as gated; no `reports/`, no git ops, no `git add -A`, never stage `*.uid`); sub agent returns files touched + suite name + `Overall Summary:` line + residual risks; **the parent re-runs the AGENTS.md headless recipe itself (import probe first, then `-s` GDUnit with `--ignoreHeadlessMode` AFTER the tool-script path) before ticking STATUS.** Failed gate → re-delegate to the same `task_id` for a fix pass.

**The cheap ugly-wins that unblock the most later work:**

1. **AAA-7 (economy loop completion)** — the keystone: AAA-8 ladder payouts, AAA-9 section rewards, AAA-10 dealership prices, AAA-15/16 discovery credits and AAA-20 pack bonuses all read the ledger it finishes. Start it first inside Phase B (Phase A runs in parallel — A has no cross-deps).
2. **AAA-2 (locked-60 + perf gate)** — zero deps, protects every later phase's frame budget; must land before Phase C spends headroom on density.
3. **AAA-17 (a11y slate)** — launch-blocking; autodrive half-depends only on shipped GPS; also unblocks AAA-18's Family macro.
4. **AAA-14 (biome pass)** — gates AAA-15 landmarks and AAA-16 collectible placement aesthetics (they sit *in* visible biomes).
5. **AAA-1 (audio-feel)** — pure readers of shipped signals; do anytime, do early.

**What waits for what:**

| Item | Must wait for |
|---|---|
| AAA-8 ladder | AAA-7 payouts |
| AAA-9 sections | shipped GPS/checkpoints + AAA-7 (for rewards) |
| AAA-10 dealership | AAA-7 ledger (stub sufficient to begin) |
| AAA-13 upgrade tiers | AAA-7 prices |
| AAA-15 landmarks | AAA-14 biomes |
| AAA-16 collectibles | AAA-7 payouts (placement may start earlier) |
| AAA-18 Family | AAA-17 preset plumbing |
| AAA-20 packs | AAA-8 + AAA-7 (defs worth rotating) |
| AAA-21 split-screen | v1 (post-v1 by decree) |
| Everything in Phase A | nothing — all ship on shipped systems |

Parallelization note (per open-world plan §3.0): agents own disjoint file sets; never run two headless engine sessions on the same `res://` concurrently; only the parent runs the full suite.

---

## 7. Definition of "Done" for the AAA push

All of the following are true and measurable:

- **Performance:** locked ≥60 fps avg @1080p on the GTX 970 reference across **Low, Medium and High** presets, enforced by `tests/suites/test_perf_gate.gd` (AAA-2) — the "runs locked 60 on a GPU FH6 won't install on" claim is bench-backed.
- **Bench:** **≥ 720 GDUnit tests green** (641 baseline + every new AAA suite), **0 errors / 0 failures / 0 flaky**, import probe clean, orphan count ≤ baseline — headless recipe order per AGENTS.md on every ship.
- **Full loop demo (single playtest path):** garage → tune → enter event → win → payout → buy car (incl. S-class hero) → championship ladder stage → next stage unlock — proven headless by `test_economy_loop.gd` + `test_championship_ladder.gd` and by a human playtest capture.
- **Feel floor:** audio-feel beds live (AAA-1), rival personalities on grid/results (AAA-4), photo mode + replay + car viewer presentable (AAA-3/5/11) — the three surfaces a store page screenshots.
- **A11y launch slate complete (AAA-17/18):** autodrive, colorblind filters, rebind UI, HUD scale, proximity radar, Family preset — the FH6-parity list from FH6 ranked #3, all behind `test_accessibility_options.gd`.
- **World reads AAA:** ≥2 visible biomes, ≥3 landmark clusters, collectibles feeding credits, event weather/TOD variants — Phase C suites green.
- **Red-line audit:** no RT/4K/VR/roster-count/online claims anywhere in marketing or code; no paid-credit or grind-gate path exists (structural asserts in `test_used_car_rotation`/`test_content_cadence`).

### Post-v1 live cadence sketch (indie-friendly, inspired-but-not-copied)

- **Shape:** FH6 Festival Playlist's rotating beat + GT7's monthly free drop — executed as AAA-20 **data-only packs**: one seasonal theme pack per month (new event variants on the 8 families, a landmark or collectible set, a reward modifier), all free, all loadable without core-code changes.
- **Rules (inverted from both incumbents):** no battle-pass XP grind, no FOMO paywall, no paid credits, no content permanently removed (packs stay selectable — "no grind, no paywall, one purchase" stays true forever). Weekly *challenges* may rotate for flavor; they only ever pay the same ledger everyone can already earn.
- **Operation budget:** mechanism = shipped in-plan (AAA-20); operation = one data pack + one ops note per month — sustainable for a small team precisely because it touches zero systems code.

---

## 8. STATUS

_Baseline at writing: **641 tests green / 0 errors / 0 failures / 63+ suites** (2026-09-23, HEAD `b24d60e`). Each item ships via one `general` sub agent + parent re-verification (headless recipe) before its box is ticked._

**Phase A — Feel & Loop completeness**
- [ ] AAA-1 audio daily-feel layers (`test_audio_feel_layers`)
- [ ] AAA-2 locked-60 High + perf gate (`test_perf_gate`)
- [ ] AAA-3 photo mode + map filters (`test_photo_mode`)
- [ ] AAA-4 rival personalities (`test_rival_personalities`)
- [ ] AAA-5 replay recorder (`test_replay_recorder`)
- [ ] AAA-6 per-car default setup + downshift sibling (`test_car_default_setup`)

**Phase B — Career depth & content systems**
- [ ] AAA-7 economy loop completion (`test_economy_loop`)
- [ ] AAA-8 championship/season ladder (`test_championship_ladder`)
- [ ] AAA-9 section challenges (`test_section_challenges`)
- [ ] AAA-10 used-car rotation (`test_used_car_rotation`)
- [ ] AAA-11 car viewer (`test_car_viewer`)
- [ ] AAA-12 event weather/TOD/season variety (`test_event_variety`)
- [ ] AAA-13 tuning/livery depth (`test_tuning_depth`)

**Phase C — World density & discovery**
- [ ] AAA-14 open-world biome color pass + 2nd biome (`test_terrain_biomes` extended)
- [ ] AAA-15 landmark clusters (`test_landmark_clusters`)
- [ ] AAA-16 collectibles & discovery rewards (`test_collectibles`)

**Phase D — Accessibility & launch readiness**
- [ ] AAA-17 accessibility launch slate (`test_accessibility_options`) — launch-blocking
- [ ] AAA-18 Shuffle Race + Family presets (`test_shuffle_family`)
- [ ] AAA-19 telemetry / data logger (`test_telemetry_logger`)

**Phase E — Post-v1 live cadence**
- [ ] AAA-20 content schedule packs (`test_content_cadence`)
- [ ] AAA-21 LAN/split-screen wedge (`test_split_screen`) — post-v1 only

**Full-suite gate (final):** [ ] `Overall Summary: ≥ 720 | 0 errors | 0 failures | 0 flaky` + Definition-of-Done §7 checklist signed.

_Reference shipped suites (never re-planned as new): `test_race_loop`, `test_race_countdown`, `test_race_results`, `test_session_stats`, `test_gps_route_follow`, `test_map_route`, `test_discovery`, `test_rival_ai`, `test_traffic_driving`, `test_event_rewards`, `test_event_placement`, `test_vehicle_fx`, `test_drive_feel`, `test_hardening`, `test_weather_vfx`, `test_weather_sun`, `test_regional_climate`, `test_surface_grip`, `test_garage_tuning`, `test_career_economy`, `test_profile_slots`, `test_save_manager`, `test_road_graph`, `test_corridor_seeding`, `test_terrain_biomes`, `test_terrain_seeder_streaming`, `test_streaming_dressing`, `test_cc0_cars`, `test_engine_audio`, `test_car_audio`, `test_cockpit_camera`, `test_cockpit_interior`, `test_cockpit_hud`, `test_camera_settings`, `test_hood_camera`, `test_quality_ladder`, `test_settings_presets`._
