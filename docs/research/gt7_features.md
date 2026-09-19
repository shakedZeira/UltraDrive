# Gran Turismo 7 — Full Feature Reference Dossier

> Research compilation for game-design reference, gathered for the UltraDrive project.
> All figures sourced from press, official Polyphony/Sony blogs, and community-tracked databases
> (GTDB, GT Wiki, Fandom, kudosprime, victorydash) as of **Sep 2026**. Items marked ⚠ are
> **fan-tracked, single-source, or internally inconsistent numbers that are NOT officially
> confirmed** — cross-check before using them as design inputs.
>
> Launch context: Released **2022-03-04** for PS4/PS5 (cross-gen). Series 25th-anniversary title —
> "the most complete GT to date" (Kazunori Yamauchi, State of Play deep-dive —
> https://www.youtube.com/watch?v=JlbMzBnfnzM). Still receiving monthly content updates: version
> **1.71 (2026-08-20) is the 39th content update**.

---

## 1. Overview

- Product pitch: **"The Real Driving Simulator"** — a driving simulation Polyphony designed to be
  enjoyed by newcomers and sim veterans alike, centered on car culture rather than pure competition
  (YouTube State of Play deep-dive — https://www.youtube.com/watch?v=JlbMzBnfnzM). Positioning is
  sim-cade: reviewers call it "the perfect balance between simulation and arcade racing" — not a
  hardcore sim like ACC/iRacing (CogConnected review — https://cogconnected.com/review/gran-turismo-7-review/).
- **Return-to-roots package:** full single-player career, deep car tuning/modding, classic circuits,
  License Tests and car-culture education — restoring what GT Sport stripped out — while keeping
  GT Sport's online/Sport infrastructure (Eurogamer review —
  https://www.eurogamer.net/gran-turismo-7-review-sonys-flagship-series-returns-to-its-ps2-glory-days).
- Career is structured as the **GT Café**: ~39 main "Menu Books" (collection/race objectives) plus
  Bonus/Extra/Seasonal Menus unlocked after finishing Menu Book 39 and watching the ending.
- Update cadence: roughly monthly content drops; **39 by v1.71 (Aug 2026)**. Major milestones:
  v1.29 PSVR2 + Sophy (Feb 2023); v1.40 *Spec II* (Nov 2023 — Lake Louise, Master Licenses, Weekly
  Challenges); v1.49 physics overhaul + Michelin (Jul 2024); v1.54 PS5 Pro support (Nov 2024);
  v1.55 DR-cap raise + physics (Jan 2025); v1.65 *Spec III* + Yas Marina + Dunlop (Dec 2025);
  v1.71 physics overhaul + Fanatec FullForce (Aug 2026). Timeline sources: gtplus —
  https://gtplus.app/gt7/updates; Fandom — https://gran-turismo.fandom.com/wiki/Gran_Turismo_7/Updates;
  GTDB — https://gtdb.io/gt7/updates/.
- Always-online save model with one offline fallback: only the **Arcade modes run fully offline**;
  the rest needs a network connection for save anti-cheat and livery downloads (Yamauchi via
  GTPlanet — https://www.gtplanet.net/new-gran-turismo-7-details-ps4-vs-ps5-driving-physics-gt-cafe-and-more-revealed-in-kazunori-yamauchi-interview/).

## 2. Tracks & Circuits

- **As of v1.67: 41 locations, 84 layouts, 121 drivable configurations** (incl. reverse) per GT
  Wiki — https://www.gtwiki.co.uk/wiki/Tracks_in_Gran_Turismo_7. ⚠ GTPlanet's master list counted
  **41 locations / 120 variations** as of v1.65 (Americas 15 locations/37 variations; Europe/Middle
  East 17/60) — the 120-vs-121 gap is the Yas Marina/v1.65 addition and has not been reconciled
  against v1.71 — https://www.gtplanet.net/forum/threads/gran-turismo-7-master-track-list.394378/;
  victorydash also lists 121 layouts ⚠ — https://victorydash.io/games/gt7/tracks.
- **Two configurations stay locked out of career:** *Nürburgring Nordschleife Tourist* and
  *Nürburgring Endurance II* are drivable only in solo Time Trial — a deliberate restriction
  (GTWiki tracks page).
- Launch state: **34 circuit locations**, of which only 3 are open at first — Autodrome Lago
  Maggiore (Europe), BB Raceway (Asia-Oceania), Northern Isle Speedway (Americas) (GTPlanet unlock
  guide — https://www.gtplanet.net/gt7-how-to-unlock-everything-20220305/).
- Tracks unlock through **Menu Books and Collector Levels**, not credits:
  - Nürburgring = Menu Book 21; Spa = Book 30; Le Mans ("24 Heures du Mans Racing Circuit") = Book 38.
  - Collector-level gates: Grand Valley Highway-1 CL15, Watkins Glen CL17, Road Atlanta CL20,
    Lake Louise CL22, Eiger Nordwand CL25 (GTPlanet unlock guide).
- Post-launch track additions:

| Version | Track / layout(s) added | Source |
| --- | --- | --- |
| 1.29 (Feb 2023) | Grand Valley – Highway 1 (revamped) | Fandom updates page |
| 1.40 Spec II (Nov 2023) | Lake Louise snow courses (3 layouts) | PlayStation.Blog Spec II |
| 1.49 (Jul 2024) | Eiger Nordwand (+ Reverse) | PlayStation.Blog 1.49 |
| 1.65 Spec III (Dec 2025) | Yas Marina + Circuit Gilles-Villeneuve; *Nürburgring Endurance II* (TT-only) | gran-turismo.com 1.65 |

- Yas Marina stat block (from Polyphony): **5,281 m long, 11 m elevation change, 16 corners,
  longest straight 1,233 m** (PlayStation.Blog Spec III —
  https://blog.playstation.com/2025/12/03/gran-turismo-7-spec-iii-power-pack-dlc-available-december-4/).
- **Circuit Experience** exists per track; target times are reset and demo replays re-shot whenever
  a physics patch lands (explicit in the 1.49 and 1.71 patch notes —
  https://www.gran-turismo.com/gb/gt7/news/00_3638095.html).

## 3. World Map

- The hub is a stylised **world-map home screen** with pavilions: GT Café (center), World Circuits,
  GT Auto, Brand Central, Used Cars, Legend Cars, Garage, License Center, Missions, Multiplayer
  (Lobby/Sport), Scapes, Showcase, Music Rally, Sport Mode, Gifts, and the news ticker
  (GTPlanet unlock guide; gamepressure menu walkthrough — https://www.gamepressure.com/gran-turismo-7/menu-1-menu-10/z5f852).
- World Circuits splits into continent regions — **Americas; Europe/Middle East; Asia-Oceania** —
  with events mostly organised **per-track**; since v1.40 an **Event Directory** button lists every
  event and its completion % (Fandom World Circuits — https://gran-turismo.fandom.com/wiki/World_Circuits).
- **Scapes** photo mode: ⚠ **~2,570 photospots across ~60 countries** — reveal build showed 2,568,
  launch press cited 2,573, Digital Trends recorded "2,571 (current)" in May 2022; that roughly
  doubles GT Sport's 1,235 spots in 23 countries. Locations arrive as curated collections via
  updates (Whistler, Lone Pine, Pikes Peak, Tomica Town, etc.) (Pro Game Guides —
  https://progameguides.com/gran-turismo/how-many-photo-locations-are-there-in-gran-turismo-7/;
  GTPlanet Scapes trailer — https://www.gtplanet.net/gt7-trailer-scapes-20211104/; Digital Trends —
  https://www.digitaltrends.com/gaming/how-to-use-photo-mode-in-gran-turismo-7/).
- **GT Auto** = car maintenance (oil/wash/repair), body/widebody kits, wheel fitment, engine swaps
  (unlocked at Collector Level 50), and — post-MB39 — a **Car Valuation Service** to sell cars back
  (GTPlanet unlock guide).
- **Brand Central** doubles as a museum network: each manufacturer gets a **Museum** (brand-history
  essays) plus **Channels**, expanded by updates (1.49 added Volvo/Subaru museums; 1.65 added
  Dunlop, Polestar, Mine's).
- **Paddock** (Spec II, formerly Meeting Places): a social pre-race lot where rooms chat and inspect
  cars, reachable from both Multiplayer and World Circuits (gran-turismo.com news —
  https://www.gran-turismo.com/us/news/00_1863603.html).

## 4. Vehicles

- **Car count: 579 as of v1.70 (570 standard + 3 special editions + 6 paid-DLC) per Fandom** —
  https://gran-turismo.fandom.com/wiki/Gran_Turismo_7/Car_List. v1.71 (2026-08-20) added four more
  (Caterham Seven Superlight R500 '08, Hyundai IONIQ 6 N '25, Toyota Chaser Tourer V '97, Toyota
  Mark II Tourer V '97) → **~583 total. ⚠ Cross-sources disagree:** kudosprime lists *579 models*
  (live DB), victorydash says *570* (looks stale), GTDB says *all 560* (stale) —
  https://www.kudosprime.com/gt7/carlist.php; https://victorydash.io/games/gt7/cars; https://gtdb.io/gt7/all-cars/.
- Distribution: **Brand Central** (new cars incl. Vision Gran Turismo concepts and tuner-spec
  models), **Used Cars** (30/day, rotated), **Legend Cars / Hagerty Collection** (historic race
  cars & classics), plus **rewards** (licenses, Menus, roulette) and **Power Pack DLC** exclusives.
- Category system: **Gr.1–Gr.4** (prototype → GT4), **Gr.B** rally, road cars, karts, Formula
  (F3500-A/B, F1500T-A, SF19/SF23) and VGT concepts. BoP-fixed vs tuning races coexist in both
  single-player and Sport.
- **Tire brands ship as in-game content:** Michelin (added v1.49), Dunlop (added v1.65 — incl.
  default Dunlop design on certain special cars); compounds span Comfort/Sports/Racing (S/M/H),
  Intermediate + Heavy Wet, and Dirt/Snow (1.49/1.65 patch notes).
- **Engine swaps** (GT Auto service) exist for a large catalogue and sit behind **Collector Level
  50**; personality picks (e.g. an Escudo swap with brutal turbo lag) feed the meta economy
  (Coach Dave Academy tuning guide — https://coachdaveacademy.com/tutorials/gran-turismo-7-tuning-explained/).

## 5. Physics & Driving

- **v1.71 (2026-08-20) = biggest physics overhaul since 1.49** (GTPlanet —
  https://www.gtplanet.net/gran-turismo-7-update-1-71-arrives-with-major-physics-changes-fanatec-fullforce-support-20260820/;
  official notes — https://www.gran-turismo.com/gb/gt7/news/00_3638095.html):
  - **Tires:** algorithm rewritten around "simulation of tyres slipping"; rolling resistance
    optimised; heating/wear values adjusted; off-track grip on **Grip Reduction Off Track = "Real"**
    adjusted.
  - **Engine:** torque-control improvements for drifting and partial throttle; per-car fixes
    (IONIQ 5 N front:rear torque split 0–100% ↔ 100:0 settable via Car Settings/MFD).
  - **Chassis:** steering geometry optimised per car; damper attenuation re-tuned for stance/road
    tracking; defaults (suspension, diff, aero ranges) recalibrated; fleet-wide **PP recalculated**.
  - **Damage:** new **"Championship"** mechanical-damage mode (Light rules but trips on minor hits;
    recovery time scales with severity).
  - **Content:** Fanatec GT DD Pro **FullForce** + Auto Setup across DD Pro/DD Extreme/Podium; TCS
    and ABS interventions re-tuned; forced-downshift behaviour (manual) adjusted; fuel-consumption
    fixes on some production EVs.
- **v1.49 (Jul 2024)** reset the baseline: suspension- and steering-geometry calculation revamp,
  damper behaviour on bumps/kerbs, tyre heating/wear on Racing compounds, wet-racetrack grip loss +
  hydroplaning, CFD aero defaults, controller steering algorithm, FFB torque range
  (PlayStation.Blog — https://blog.playstation.com/2024/07/24/gran-turismo-7-update-1-49-brings-six-new-cars-updated-physics-simulation-model-and-more-on-july-24/).
- **v1.31 (Mar 2023)** is the archetype of the iterative model: suspension/tire/aero pass, an
  anti-lag rev limiter, and assist defaults softened (Intermediate CSA Strong→Weak + TCS 5→3;
  Expert CSA Strong→Off; TCS "1" intervention reduced / "5" increased; ASM intervention increased) —
  https://www.gran-turismo.com/us/gt7/news/00_1462138.html.
- **Performance Points (PP):** a single number blending power/torque, weight distribution/ballast,
  power-to-weight, downforce and tire compound — PD-internal, used as the regulation filter in
  career races (Fandom PP — https://gran-turismo.fandom.com/wiki/Performance_Points). PP is
  rebalanced across the roster at each physics patch (1.31, 1.49, 1.71 all did it).
- **Controller/wheel feel:** DualSense **adaptive triggers model ABS** ("feel the relationship
  between braking force and tire grip") + synchronised haptics; FFB is tuned per wheel hardware,
  with per-brand Auto Setup for Fanatec (gamespot —
  https://www.gamespot.com/articles/new-gran-turismo-7-trailer-pushes-you-to-find-your-line/1100-6500023/).

## 6. Game Modes

- **GT Café career:** 39 main Menu Books (collection + race objectives); car designers appear for
  in-person history vignettes. Progress gating: License Center (MB1), Tuning Shop (MB3), Brand
  Central (MB4), GT Auto + Scapes (MB7), Multiplayer/Sport/Power Pack (MB9), Missions (MB12),
  Legends Cars (MB17) (GTPlanet unlock guide).
- **License Center — 150 tests:** 10 licenses × 10 tests (National B, National A, International B,
  International A, Super), each hosted by a real driver / World Finalist (Daniel Solis, Coque
  López, Igor Fraga, Mikail Hizal, Takuma Miyazono), plus 5 **Master Licenses** (50 more, Spec II
  1.40) unlocked after Super at Bronze+ (Fandom — https://gran-turismo.fandom.com/wiki/GT7_Licenses).
  Rewards are material: National B Gold → Mitsubishi GTO Twin Turbo '91; Super completion → Audi R8
  LMS Evo '19; all-gold → Red Bull X2019 (SAMURAI GAMERS; TheGamer).
- **Missions:** driving challenge card (pass battles, drift/brake tests, one-hour endurance such as
  Tsukuba One Hour); event difficulty gets targeted tweaks across patches (1.49 adjusted the Tsukuba
  One Hour).
- **Music Rally:** checkpoint "beat" minigame — carry a song's beat count through gates or retire.
  **6 events at launch + 6 more in v1.35 = 12 total**; each has Beginner/Intermediate/Expert assist
  presets; medals = distance driven when the track ends (first event: Bronze 7,000 m / Silver
  8,400 m / Gold 8,800 m, Alsace–Village, Porsche 356 A/1500 GS GT Carrera Speedster '56). Unlocks
  progressively and **needs a connection to save progress**; pays no credits (Fandom —
  https://gran-turismo.fandom.com/wiki/Gran_Turismo_7/Music_Rally; Traxion —
  https://traxion.gg/gran-turismo-7s-next-update-will-include-more-music-rally/; ScreenRant).
- **Arcade modes** (folded into World Circuits): **Quick Race** (Beginner/Intermediate/Professional
  difficulty; prize credits scale up to **+400%** — +200% each for Collector Level and Circuit
  Experience progress); **Time Trial**; **Drift Trial** (score = drift angle × record-line
  proximity × speed × duration; disabled at Blue Moon Bay, Northern Isle, BB Raceway and Special
  Stage Route X, enabled at Daytona oval); **Custom Race** (AI car assignment, names, nationalities,
  full rules; 20-car fields; Sophy 2.1 on PS5 from v1.57) (Fandom World Circuits).
- **VR mode (PS5, free via v1.29):** nearly everything playable in PS VR2 **except local
  split-screen**; includes a VR Showroom and Drift Stage Scapes (GTPlanet —
  https://www.gtplanet.net/gt7-update-129-psvr2-sophy-gvalley-20230221/; PlayStation.com FAQ —
  https://www.playstation.com/en-us/support/games/gran-turismo-7-announcement-faq/).
- **Split-screen:** 2-player at launch → **4 players on PS5 in Spec II** (PlayStation.Blog Spec II).
- **Weekly Challenges** (post-game, after MB39 + ending): 5 events/week (4 evergreen + 1 exclusive
  Special), bonus tickets at 1/3/5 completions; a clean sweep is worth roughly **1.3 million
  credits** (GTPlanet weekly guide — https://www.gtplanet.net/gran-turismo-7-weekly-challenges-deep-frest-raceway-20260917/).

## 7. Menus & UI

- All modes hang off the **world map**; in-race, a minimal HUD (speed/gear/RPM cluster), **MFD**
  (multi-function display for traction/brake/power, EV maps, tire info) and race info toggles.
- **Event Directory** (v1.40): a list of every career event an account can enter, with completion %,
  removing the need to hunt tracks (gran-turismo.com news; Fandom World Circuits).
- **GT Menu / Dashboard** got a structural overhaul in Spec II: the Café re-groups menus and the
  home screen gains watchable GT Live / Dynamic Viewing entries (PlayStation.Blog Spec II).
- **Dynamic Viewing** (v1.49): watch past GTWS races in-game — switch cars/cameras, or enable
  **Broadcast Mode** to see the live-commentary stream view (v1.49 notes).
- **Data Logger** (v1.65): post-run physics/telemetry analysis for Time Trial, Online TT, Drift
  Trial, License and Circuit Experience — load immediately, from saved replays, or from top
  rankings (v1.65 notes).
- **Paddock** UI = social room grid replacing Meeting Places; room cards show track, people,
  settings; rooms now support Room-ID entry and private visibility (v1.65 notes).

## 8. AI & Traffic

- **Standard AI** is improved over GT Sport (side-by-side battles, defensive lines, divebombs,
  pit strategy) but remains **the "rubber-band" model**:
  - AI throttles to ~90% on straights when the player catches up, then lifts entirely once too far
    ahead ("AI throttles themselves until you catch up") (r/GranTurismo7 — see replay evidence in
    https://www.reddit.com/r/GranTurismo7/comments/1lztcot/is_this_rubberbanding/ and https://www.reddit.com/r/GranTurismo7/comments/1ucoiyr/rubber_banding/). ⚠ Community-documented, not officially acknowledged.
  - AI cars do **not** follow the same regulation/PP rules as the player and can be given extra PP
    to compensate ("AI has a Racing IQ of 75, so it needs extra PP" — community read of replay data) ⚠.
  - Early pre-launch analysis already flagged that contacts resolve like "train cars on rails"
    (GTPlanet AI analysis thread — https://www.gtplanet.net/forum/threads/gran-turismo-7-ai-behavior-analysis.395262/).
  - Difficult events are surfaced with a **chili-pepper rating**; difficulty tiers run Easy → Normal
    → Hard plus a Professional tier in Custom/Quick race contexts.
- **Field size cap: 16 cars max on track** (Yamauchi-confirmed era design) —
  https://www.gtplanet.net/new-gran-turismo-7-details-ps4-vs-ps5-driving-physics-gt-cafe-and-more-revealed-in-kazunori-yamauchi-interview/.
- **GT Sophy** — a separately-trained deep-RL racing AI (Sony AI): **QR-SAC (Quantile-Regression
  Soft-Actor-Critic)** with multi-table experience replay, trained from its own experience (no human
  demos) with a reward balancing track progress, collision avoidance, steering smoothness and racing
  etiquette (Sony AI, "Gran Turismo Sophy, Five Years On" —
  https://ai.sony/blog/gran-turismo-sophy-five-years-on-from-nature-cover-to-open-frontier):
  - Feb 2023 → PS5 **Race Together** (time-limited, 4 circuits).
  - Nov 2023 → **Sophy 2.0** permanently in Quick Race (Spec II), 340+ cars across 9 tracks.
  - Mar 2025 → **Sophy 2.1** in Custom Race mode, 500+ cars.
  - Sophy is PS5-only and track/car-gated; it behaves much faster and fights back in a way the
    scripted AI cannot (r/GranTurismo7 2026 thread).

## 9. Weather & Time

- **Dynamic weather with a real-time time-of-day loop — reinstated** after GT Sport dropped it:
  Yamauchi confirmed time and weather move in real time; the drying line, dynamic lighting and
  full sessions were in the launch discourse from the start (Eurogamer interview, Sep 2021 —
  https://www.eurogamer.net/the-big-gran-turismo-7-interview; ResetEra info blowout —
  https://www.resetera.com/threads/gran-turismo-7-info-blowout-dynamic-time-weather-drying-line-raytracing-physics-and-more.487243/).
- Race settings expose **weather selector** (custom/random), **time-of-day** and **variable time-
  progression rate** (1×–5×) so laps can push through sunset/night/daybreak; pit strategy reads a
  weather radar and forecast (Custom Race settings in community events; Fandom World Circuits).
- Track-state physics: **wet racing-line grip loss** and **hydroplaning** modelled since v1.49;
  off-track grip on "Real" setting rebalanced in v1.71; rain physics affect AI & player differently
  (reports say AI is less degraded by standing water) ⚠ (r/GranTurismo7 2025).
- **Circuit Experience / License / Mission target times were re-tuned for the 1.49 and 1.71
  physics** — a recurring pattern proving the sim model keeps moving (patch notes).

## 10. Audio

- **Engine sound pipeline** (GDC Vault session by Kimura/Takeuchi/Minagawa): source recording,
  miking/mixing/editing workflow, an engine-sound synthesis system, and impulse-response / early-
  late reverb spatial audio — GDC talk "Gran Turismo 7 Sound" —
  https://gdcvault.com/play/1034189/-Gran-Turismo-7-Sound.
- **25-year recording legacy: 1,700+ vehicles captured** — DAT-era capture moved to multi-channel
  arrays; interior cabin ambience and intake sounds recorded separately; **50+ microphone types**
  were trialled during GT Sport development to converge on the rig (GTPlanet, Feb 2024 —
  https://www.gtplanet.net/recording-gt7-sounds-polyphony-digital-20240207/).
- **Soundtrack: "Find Your Line"** — **300+ tracks from 75+ artists**, the largest GT soundtrack
  ever (racinggames.gg — https://racinggames.gg/article/gran-turismo-7s-music-rally-mode-lets-you-relax-and-drive-to-music;
  NME — https://www.nme.com/news/gaming-news/gran-turismo-7-reveals-music-rally-mode-campaign-details-and-more-3151507).
- **Music Replay** dynamically generates the replay camera cut to match a song, so every replay of
  the same race looks different (Yamauchi State of Play deep-dive).
- **Music Rally** doubles the music as a gameplay mechanic (see §6) — the mode Yamauchi calls
  feasible only because music is core to GT (racinggames.gg).
- Platform audio: PS5 **3D audio** (Tempest); a Dolby Atmos BGM bug was fixed in v1.54.

## 11. Progression & Economy

- **Launch crisis (Mar 2022):** server downtime + race-reward nerfs triggered a backlash; Polyphony
  gave every player **1M credits**, Yamauchi apologised, and the roadmap added doubled late-game
  payouts, new high-reward events and car selling (Polygon —
  https://www.polygon.com/22995971/gran-turismo-7-ps5-updates-free-credits-offline-grind-economy/).
- **Credit sinks:** used/legend cars (up to **Cr 20,000,000** each — Ferrari 250 GTO '62, Shelby
  Cobra Daytona Coupe '64), tuning/engine swaps, and cosmetics. The richest single-item catalogue
  sits in **Legend Cars**, priced in line with the **Hagerty Valuation Tool** and periodically
  revised (McLaren F1 '94 rose to Cr 20M; W 196 R '55 to Cr 20M+; some dropped) (Fandom Legend Car
  Dealership — https://gran-turismo.fandom.com/wiki/Legend_Car_Dealership).
- **Roulette tickets** (6-star ladder): earned via **Daily Workout** (drive **26.219 miles/day** =
  one Olympic marathon) and Café Menu Books. 1★ top payout 5,000 Cr; 6★ up to 500,000 Cr or a car;
  **4★ and above can pay "invitations"** to buy rare marques (Pagani etc.); tickets expire after ~1
  month (Traxion — https://traxion.gg/how-the-daily-workouts-function-in-gran-turismo-7/; GameRant —
  https://gamerant.com/gran-turismo-7-how-to-get-roulette-tickets-guide/).
- **Collector Level** ("book of cars" from purchasing/winning vehicles): cap raised **50 → 70 in
  v1.65**; gates engine swaps (CL50), several tracks, Extra Menus (CL 48–70) (v1.65 notes; GTPlanet
  unlock guide).
- **Used Cars:** 30 cars/day shown since v1.11, refreshed at local midnight; full rotation ~1 month
  (Traxion Used Cars; reddit GT7 community consensus).
- **Legend Cars:** unlocks at MB17; ~10–11 cars at a time (plus extra **Special Picks** slots for
  new cars / Sport support); cars leave via Limited-Stock → Sold-Out → replaced at midnight UTC;
  full rotation ~3 months; 92 distinct legendary vehicles as of v1.69 ⚠ (Fandom Legend Car
  Dealership; GTDB — https://gtdb.io/gt7/legend-cars-dealer/).
- **Sport Mode ranks:** DR scored 0–100,000 (cap raised to **150,000 in v1.55**), shown A+→E;
  SR 0–99 with grades S/A/B/C/D/E (S = 80–99 with a hidden 90–99 split); matchmaking sorts by SR
  first then DR; rank-ups award 1,500 DR (Coach Dave Academy — https://coachdaveacademy.com/tutorials/how-to-improve-your-dr-sr-in-gt7/;
  Fandom Sport Mode — https://gran-turismo.fandom.com/wiki/Sport_Mode_(GT7)).
- **Lap Time Challenges** pay by closeness to the world record: within 3% → **2,000,000 Cr**,
  5% → 1M, 10% → 200k; two run concurrently (offset weeks) since v1.32 (Fandom Sport Mode).

## 12. Accessibility & Options

- **Assist Settings** (per-session, pre-race + pause): gears Auto/Manual; **Assist Preset Selection**
  (Beginner/Intermediate/Expert/Custom); **Traction Control 0–5**; **ABS** Off/Weak/Default;
  **Auto-Drive** Off/Brake/Brake & Steering ("training wheels" that brake/steer for you); **Driving
  Line Assistance**; **Braking Indicator**; **Braking Area**; **Replace Car After Leaving Track**;
  **Active Stability Management (ASM)**; **Countersteering Assistance** Off/Weak/Strong
  (simracingsetup.com — https://simracingsetup.com/gran-turismo/best-gran-turismo-7-assist-settings/;
  Dexerto — https://www.dexerto.com/gaming/ultimate-gran-turismo-7-settings-guide-1774225/).
  Presets were re-balanced in v1.31 (CSA/TCS lowered) and assists get behavioural passes in each
  physics patch (1.49, 1.71).
- **Race rules layer:** mechanical damage (off/light/heavy + v1.71 "Championship" mode), tire-wear
  and fuel multipliers (1×–10×), slipstream strength, **Boost** (catch-up setting), shortcut/flag
  penalties, grid vs qualifying starts, mandatory tire compounds, refuelling speed, weather/time
  selectors (Fandom Sport Mode; v1.65 notes).
- **Difficulty architecture:** career difficulty (Easy/Normal/Hard) + per-event "chili" flags;
  arcade tiers Beginner/Intermediate/Professional; payouts scale with it.
- **Output/display:** Broadcast Mode, audio mix, HUD density, controller mapping incl. wheel
  auto-config, VR reprojection toggle (PS5 Pro), localisation (patched near-daily).

## 13. Performance & Tech

- **PS5:** 60fps core gameplay; ray tracing in Showroom/Scapes/menus; PS VR2 at ~**4K reprojected
  120fps** effective; **PS4↔PS5 crossplay** seamless, load times being the main differentiator
  (GTPlanet Yamauchi interview; PlayStation.com VR FAQ).
- **PS5 Pro patch (v1.54, Nov 2024)** — Digital Foundry analysis
  (https://www.digitalfoundry.net/articles/digitalfoundry-2024-gran-turismo-7-on-ps5-pro-rt-8k-vr-performance-modes):
  - **PSSR** with a mode combining higher image quality and frame rate.
  - **Ray-traced reflections during gameplay** via **"Prioritize Ray Tracing/Resolution"** — car
    self-reflections + world reflections while racing.
  - **8K resolution compatibility**; enhanced VR rendering with **VR Positional Reprojection** toggle.
  - v1.71 ships the "latest version of PSSR" to Pro owners (v1.71 notes).
- **DualSense:** adaptive triggers (ABS/modulation feel) + haptics; 3D audio end-to-end.
- **Fanatec:** FullForce feedback on GT DD Extreme (v1.65) and GT DD Pro (v1.71) + tuning-menu
  **Auto Setup** for DD Pro/Extreme/Podium.
- Service model: FFB/encoder/Dolby-Atmos bugs (1.54) fixed across patches; official servers carry
  saves, liveries and Sport.

## 14. Multiplayer & Online

- **Sport Mode** (unlock: Menu Book 9; PS Plus required): ranked DR/SR ladder, **Daily Races A/B/C**
  refreshed **every Monday 07:00 UTC**, plus Lap Time Challenges and season championships (Fandom
  Sport Mode; Coach Dave Academy — https://coachdaveacademy.com/tutorials/gt7-daily-races-explained/):
  - **Race A** — beginner, ~10–12 min, unranked for DR since May 2022 (SR still counts), variety cars.
  - **Race B** — intermediate, ~10–12 min, Gr.3/Gr.4 under BoP, no fuel/tyre wear.
  - **Race C** — flagship, 20+ min, fuel/tyre wear + mandatory compounds, usually Gr.3 BoP; sessions
    every 30–60 min.
- **Lap Time Challenges:** two concurrent 2-week events with 3%/5%/10% credit bands (§11).
- **Esports:** **GT World Series** (Nations + Manufacturers Cups) run inside the client; 2026 added
  the first esports **Team Competition** (Feb 2026 news; live calendars via DG Edge —
  https://www.dg-edge.com/).
- **Lobbies:** custom rooms to **16 players**, host race settings (compounds, mandatory stops,
  weather, privacy by Room ID); full **cross-gen PS4↔PS5**; Room-ID join + private rooms added v1.65
  (Traxion — https://traxion.gg/a-guide-to-gran-turismo-7s-online-lobbies/).
- **Split-screen:** 2 players (4 on PS5 in Spec II); VR-mode split-screen excluded.
- **Paddock:** social pre-race lot for lobby rooms (Spec II) — the car-showroom meetup
  (gran-turismo.com news).
- **Showcase:** liveries, photos and replays shared publicly; no user-made tracks/level editor —
  tuning is the meta layer (community consensus).

## 15. Collectibles / Depth

- **Garage + Collection Book + Collector Level** form a full car-collecting layer, fed by
  purchase, winnings, roulette and DLC (GTPlanet unlock guide).
- **Brand Museums & Channels** teach real brand history (Volvo, Subaru, then Dunlop, Polestar,
  Mine's…); **Café Menus** with car-designer conversations are the narrative spine.
- **Livery Editor:** decal placement, brand/partner decal packs (AP Racing, Dunlop, Mine's, Brembo,
  Rotiform, pokal…; HIGHSPEED Étoile packs retired v1.49), wheel brands (WORK, Rotiform, American
  Racing, KMC, Motegi), widebody kits.
- **Engine swaps** as collectibles — catalogue grows every patch (v1.71 adds AMG 300 SEL, SLS AMG,
  Caterham Seven, Focus RS '18, X2014 Junior, Evo IX, 911 GT3 (996), and more).
- **Scapes & Showcase:** 2,500+ photospots with curation packs; public photo/article sharing.
- **Meta-gated legends:** e.g. the "Three Legendary Cars" trio of Cr-20M cars; Hagerty-driven price
  revisions change acquisition cost over time (GTDB; Fandom).
- **Ongoing loop:** Weekly Challenges + **Seasonal Menu** (post-MB39); **Power Pack DLC** (PS5,
  paid) = 50 extra events across 20 categories including full-length 24h sessions with practice +
  qualifying + race, plus Cr 5,000,000 of credits; and its own weekly reward track (v1.65 notes;
  GTPlanet Power Pack coverage).

## 16. Soul of the Game

Design pillars, straight from Yamauchi's own framing (State of Play deep-dive —
https://www.youtube.com/watch?v=JlbMzBnfnzM; find-your-line campaign — 
https://www.gamespot.com/articles/new-gran-turismo-7-trailer-pushes-you-to-find-your-line/1100-6500023/):

1. **The Real Driving Simulator** — simulation is the bedrock: 25 years of physics history, CFD
   aero, tire-partner science (Michelin feedback loop), track data making lap times match real life.
2. **A "paradise" celebrating car culture** — GT7 is a themed resort of automotive history (Café,
   Museums, Scapes, collections) more than a pure racing ladder.
3. **Cars story & education** — License Tests teach driving from the ground up; the Café's Menu
   Books and designer cameos "naturally contact you with the history of cars"; Brand Central Museums
   are history lessons. Reviewers frame it as re-igniting young players' love of the automobile
   (CogConnected review).
4. **Collecting with restraint** — starting from the bottom and growing a garage (vs Forza's
   showering of top-tier cars) is praised as the return of GT-proper progression (CogConnected).
5. **Replay quality on par with driving** — "we place the same importance on watching your driving
   in a replay as the fun of driving"; **Music Replay** regenerates camera cuts per song
   (State of Play).
6. **Exquisite feel** — DualSense adaptive-trigger ABS and haptics are pitched as part of the
   simulation ("feel the road beneath you"); wheel/kart feel tuned per hardware generation.
7. **Accessible invitation** — "a driving simulator all players can enjoy": Music Rally exists so
   people "may never have played a car game" can still have fun; assists ladder from full auto-drive
   to pure manual (State of Play; racinggames.gg on Music Rally).
8. **Built to be lived in** — a 4-year service cadence of monthly content, physics revisions and
   esports seasons; GT7 positions itself as the single game you keep coming back to well past the
   credits (39 content updates by v1.71).

---

*Dossier ends. As-of date: 2026-09-19. Version covered: 1.71 (2026-08-20). For design work,
  treat every ⚠ figure as unverified until confirmed against the game or a fresher source.*