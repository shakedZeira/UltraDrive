# Forza Horizon 6 — "Horizon Japan" Complete Feature Dossier

> Research compilation for game-design / rival-racer reference. All figures sourced from
> press, official Forza news, and community trackers as of **Sep 2026**. Items marked ⚠ are
> **fan estimates or single-source claims that are NOT officially confirmed** — treat with
> caution and cross-check before using as design inputs.
>
> Companion to `fh6_map.md` (map/road dossier). This file covers the full feature set:
> vehicles, customization, modes, UI, AI, weather, audio, economy, accessibility, tech,
> multiplayer, and collectibles.
>
> Launch context: revealed at TGS Sep 2025; **Early access 2026-05-15, global launch
> 2026-05-19** (Xbox Series X|S + PC, Game Pass day one); **PS5 promised "later in 2026"**,
> though as of Sep 2026 the date is disputed (see §1.3). Cover cars: **2025 Toyota GR GT
> Prototype** + **2025 Toyota Land Cruiser**; pre-order bonus 2017 Ferrari J50.

---

## 1. Overview

| Item | Detail |
| --- | --- |
| Developer / Publisher | Playground Games / Xbox Game Studios |
| Engine | ForzaTech (Turn 10 family; shared with Forza Motorsport) |
| Genre / setting | Open-world racing, fictionalised Japan ("Discover Japan") |
| Platforms | Windows, Xbox Series X\|S (PS5 port announced) |
| Release | 2026-05-15 (Premium early access) / 2026-05-19 (full) |
| Modes | Single-player (solo / co-op), online shared world ("Horizon Play" suite) |
| ESRB | Everyone |
| File size | **~100 GB** (vs FH5 ~116 GB) ⚠ (armadaboost FH6-vs-FH5 — https://armadaboost.com/blog/forza-horizon-6-vs-forza-horizon-5-is-japan-actually-worth-the-upgrade) |
| Launch momentum | **270,000+ concurrent Steam peaks** at launch ⚠ (fh6guide.org — https://www.fh6guide.org/); **6M+ players within one week** across console/PC/Game Pass, more concurrent Xbox players than CoD (Windows Central — https://www.windowscentral.com/gaming/forza/forza-horizon-6-players-have-it-out-for-bowie-knife99-an-ai-drivatar-that-rams-players-more-than-griefers-do) |

- Critically the best-reviewed Forza ever: **IGN 10/10 "gundamn masterpiece"** (https://www.ign.com/articles/forza-horizon-6-review), Metacritic ~90/100 critic tally as of Sep 2026 (vgtimes — https://vgtimes.com/gaming-news/166796-forza-horizon-6-ps5-release-reaffirmed-for-2026.html).
- **First Forza Horizon built exclusively for ninth-gen-era hardware** (no Xbox One version; Xbox One listed on store is a copy artifact) ⚠ first-gen "exclusive to Series X|S" claim sourced to promoblix — https://promoblix.site/forza-horizon-6-japan.
- **Cross-save across Xbox/PC/PS5** — first in the series; also cross-play (forza.net progression blog; Forza forums — https://forums.forza.net/t/fh6-progression-wristband-discussion/809857).
- Story framing: you arrive as a **tourist** with two companions — **Jordy** (motorsports nerd) and **Mei** (car builder / cultural guide); two campaign paths: **Horizon Festival** (wristbands) and **Discover Japan** (stamps). (Xbox Wire — https://news.xbox.com/en-us/2025/09/25/forza-horizon-6-japan-setting-2026; livemint — https://www.livemint.com/technology/tech-news/forza-horizon-6-set-to-launch-omay-19-with-550-cars-and-its-biggest-map-ever-pre-order-benefits-maps-gameplay-and-mor-11769156574439.html)

### 1.1 Editions & monetisation entry points
- **Standard** — base game (May 19).
- **Deluxe** — + **Car Pass (30 cars**, one per week May 19 → ~Dec 8 2026, then all redeemable) + Welcome Pack (3 cars). (Xbox.com — https://www.xbox.com/en-au/games/forza-horizon-6)
- **Premium** — Deluxe + early access May 15 + future DLC expansions + VIP (1 car) (promoblix).
- Paid car packs at launch: **Italian Passion** (4 cars: Ferrari F80, SE 048SP, 275 GTB4, Giulia GTAm), **Time Attack Car Pack** (8 WTAC cars). (Windows Central — https://www.windowscentral.com/gaming/forza/complete-forza-horizon-6-car-list)

### 1.2 Key feature pillars (marketing)
Playground's officially-branded "10 Incredible New Features" list covers: Horizon Rush events, 3 permanent Car Meets, multiplayer EventLab (**Horizon CoLab**), Time Attack Circuits, Aftermarket Cars, **Car Proximity Radar**, updated car/environment sound + **Triton Acoustics**, updated Forza Aero + window liveries + new rims, and touchable car customisation (forza.net — https://forza.net/news/forza-horizon-6-features).

### 1.3 PS5 status (Sep 2026 — contested)
- Aug 27 2026: The Verge's Tom Warren reported the PS5 window was effectively scrubbed and the port "no longer likely" for 2026; IGN corroborated (IGN — https://www.ign.com/articles/forza-horizon-6-ps5-launch-reportedly-scrubbed-for-2026).
- Sep 7 2026: Playground publicly reaffirmed "releasing on PS5 later this year," wishlists open (IGN — https://www.ign.com/articles/forza-horizon-6s-ps5-version-still-on-track-for-2026-release-playground-says).
- ⚠ Press speculation ties any delay to syncing the PS5 launch with the first major expansion (ixbt.games — https://ixbt.games/en/news/2026/09/09/433447-forza-horizon-6-zaderzitsia-na-ps5-zurnalist-nazval-pricinu.html). **Design note: treat a PS5 date as un-resolved.**

---

## 2. World & Map

> Full map specifics live in `fh6_map.md`. Summary of the feature-relevant facts:

- **No official km² figure.** Fan estimates range **~122–246 km²** depending on method:
  - **~246 km² (~95 mi²)** ⚠ yelzkizi fan-mapping ≈2.3× FH5 — https://yelzkizi.org/fh6-japan-map-reveal-fans-decode-huge-world-size/
  - **~142–145 km² / 12.3×18.5 km** ⚠ Reddit pixel-count — https://www.reddit.com/r/ForzaHorizon/comments/1sk61f9/forza_horizon_6_map_size/
  - **~124 km²** ⚠ another Reddit calc — https://www.reddit.com/r/ForzaHorizon/comments/1sg1gfa/forza_horizon_6_map_size_124_km2/
  - GameSpot's practical measure: **~21 miles (~34 km) north-south**, ~12.5 min across in a top-spec Supra (GameSpot — https://www.gamespot.com/articles/forza-horizon-6-map-size-best-places-to-visit-and-how-to-reach-them/1100-6540006).
- **Goliath/Colossus lap ≈ 50 miles** (~80 km), vs FH5's ~29-mile Goliath (GameSpot). **Colossus is the longest single event in series history**, looping the whole map on the freeway, R-class (forza.net campaign blog — https://forza.net/news/forza-horizon-6-campaign).
- **Regions: 10 discoverable** per the "Road Warrior" achievement ("Discover all 10 regions") (Red Bull achievement guide — https://www.redbull.com/int-en/forza-horizon-6-achievement-guide-all-achievements). Marketing talked about **7 regions / 74 districts** (PC Gamer map preview — https://www.pcgamer.com/games/racing/forza-horizon-6s-japan-map-is-the-series-best-yet/); post-launch guides enumerate 9 named base regions + **Legend Island** (see `fh6_map.md` §1.5).
- **9 main regions + Legend Island, 5 biomes + Tokyo** is the common post-launch framing (forzahorizonhub map — https://forzahorizonhub.com/map). The `fh6_map.md` count of "6 biomes including Tokyo" is the alternate rubric — pick one and stay consistent.
- **Tokyo City** = "largest urban environment in any Forza Horizon game", ~**5× FH5's Guanajuato**, 4 districts; features Shibuya Crossing, Ginko Avenue, Tokyo Tower, C1 loop, docklands, industrial zones. Elevated-highway tech reused from FH5's Hot Wheels expansion (Wikipedia — https://en.wikipedia.org/wiki/Forza_Horizon_6; PS.com — https://www.playstation.com/en-gb/games/forza-horizon-6).
- Elevation: sea level → ~**3,000 m** Japanese Alps (⚠ press ≈, see `fh6_map.md`), the series' tallest vertical axis.

---

## 3. Roads & Terrain

| Metric | Value | Status |
| --- | --- | --- |
| Total roads | **671** per the in-game discovery counter (Steam achievement thread "671/671 Roads"; 662 openable before Legend Island unlocks) | game-verified ⚠ |
| Roads (press preview) | PC Gamer preview build logged **84 of 673 roads** — the 673 figure did not hold at launch; no official count exists | press ⚠ |
| Marketers' claim | Red Bull review rounds to **"700-plus roads"** | press ⚠ |
| Districts | 74 (official marketing) | official |
| Road mileage | **~540 mi** of roads **vs ~380 mi FH5** ⚠ single-source table (fh6wiki.com — https://fh6wiki.com/map) |
| Asphalt:dirt ratio | **Not officially published** — tarmac dominates Tokyo/touge; dirt concentrates in farmland, coastal trails, cross-country cut-throughs (see `fh6_map.md` §2.3) |

### 3.1 Road hierarchy (4 designable tiers)
1. **Urban expressways / elevated rings** — C1 Inner Loop (~14.8 km elevated), Shuto Expressway (~10+ km), Wangan/Bayshore (widest, fastest straights), perimeter expressway paralleled by the bullet train. 2. **Touge passes** — Mt. Haruna (Initial D / Akina analogue), Bandai-Azuma Skyline, 5 official Touge Battle routes (Hakone, Mt. Haruna, Bandai-Azuma, Norikura Skyline, Arahiyama Takao Parkway). 3. **Coastal/scenic** — Hakone Turnpike, Izu Skyline, Rollercoaster Road, Seabed Road. 4. **Rural/dirt lanes** — rice-field farm roads, bamboo-forest tunnels, shrine roads, dead-end mountain tracks (full detail in `fh6_map.md` §2.2).

### 3.2 Discovery ("route line") system
- **Fog of war replaces always-on map** — first in franchise; roads grey→**white (driven) / orange (route)** as you traverse; regions reveal by driving through them (`fh6_map.md` §2.5; Windows Central — https://www.windowscentral.com/gaming/forza/fast-travel-in-forza-horizon-6-has-a-big-change-over-previous-games-heres-how-you-do-it).
- **Fast travel is free from the start but gated by fog of war**: you may teleport to *any point of any discovered road* (white/orange), plus houses, festival areas, events; press X (Xbox/PC) on the map cursor. Fast Travel Boards were **removed** this generation (dotesports — https://dotesports.com/forza/news/forza-horizon-6-fast-travel).
- **Autodrive / AutoDrive** (with ANNA): set a waypoint, car drives itself with cinematic camera — promoted as both tourism and accessibility (Forza Accessibility Support — https://support.forza.net/hc/en-us/articles/51644264237075-Forza-Horizon-6-Accessibility-Support).
- Map filters: D-pad-right filter menu (Drag Meet, Festival events, etc. category list) (fh6guide drag guide — https://www.fh6guide.org/drag-racing-guide.html).

---

## 4. Vehicles & Customization

### 4.1 Roster (numbers that settle the "600+" question)
| Count | What it is | Source / status |
| --- | --- | --- |
| **550+** | Official launch marketing figure ("over 550 real-world cars") | official (xbox.com; forza.net) |
| **618** | Community-checked official roster parsed at launch (87 manufacturers) | press/tracker: PC Gamer "right now, there are 618 cars" — https://www.pcgamer.com/games/racing/forza-horizon-6-car-list; forzahorizon6carlist.com; fh6guide |
| **636** | Official Forza car-list table, Aug 13 2026 (Series 4 + Car Pass additions) | official (forza.net/fh6cars) |
| **642** | labsgg tracker (post-Series 5) | tracker ⚠ (https://forza.labsgg.com/cars) |
| 87 | Manufacturers | tracker |
| ~162–163 | Japan-linked (JDM) entries | tracker ⚠ |
| **24** | Forza Edition cars (extreme custom fabrication) | guide (fh6guide.org) |

- OEM split ⚠ (fan breakdown, competitors.md): ~165 US, ~154 Japan, ~121 Germany, ~81 Italy, ~61 UK.
- **Car Pass** adds 30 more weekly (grew the Aug-2026 count to 636).
- Acquisition paths (fh6guide car-list page — https://www.fh6guide.org/car-list.html): **Autoshow** (~360 of 618), **Wheelspins/Super Wheelspins** (exclusive pool), **Barn Finds** (15, stamp-gated, not salable), **Treasure Cars** (9, one per region, no prereqs), **Festival Playlist**, **Aftermarket Cars** (31 fixed parking spots, discount/rare), 6 **Loyalty Rewards** for prior-save owners, promotional cars (Fanta Sports 800, Peel P50 Trolli Edition).
- Car classes: **7 performance classes — D 100–500, C 501–600, B 601–700, A 701–800, S1 801–900, S2 901–998, and new R-class** (track prototypes/factory race cars, PI-cap 998). The old "X" slot is effectively **replaced by R** ⚠ (u4n classes — https://www.u4n.com/news/forza-horizon-6-car-classes.html; games.gg tier list — https://games.gg/forza-horizon-6/guides/forza-horizon-6-full-car-tier-list; ⚠ one guide's drag-bracket table still lists "B/A/S1/S2/X" — https://www.fh6guide.org/drag-racing-guide.html).

### 4.2 Customization — FH6's headline system
Playground publicly framed this as the 20-years-requested overhaul. Confirmed concrete additions:

- **Updated Forza Aero, now per-car tailored** — front splitters shaped to each vehicle; separate paintable elements (wing, supports, tow hook); modern spoilers with separate paintable endplates + carbon materials (IGN First — https://www.ign.com/articles/forza-horizon-6s-customization-improvements-and-crazier-than-ever-forza-edition-cars-ign-first; forza.net car-culture — https://forza.net/news/forza-horizon-6-car-culture).
- **Paint liveries on windows** — series first; yes, you can cover the whole windscreen (IGN First; thedrive — https://www.thedrive.com/news/forza-horizon-6s-car-customization-is-getting-a-welcome-overhaul).
- **100+ new rims**; **separate front/rear rims** (fits stagger look) (forza.net features).
- **Body kits** for many cars from **Liberty Walk, Rocket Bunny, Origin Lab**; pre-packaged "Upgrade Presets" (e.g. Aim 9 GT, StreetHunter Designs, KRC, HKS) that jump a car classes (Game Rant — https://gamerant.com/forza-horizon-6-best-cars-for-tuning-upgrade-presets).
- **Engine/mechanical upgrades**: swaps (including **motorcycle-engine swaps for Kei cars**), turbos, drivetrain swaps, weight, brakes, race transmission with full gear ratios, suspension/camber/toe/caster, anti-roll, tyre width/pressure/compound, differential (full example build: forzafire.com build page — https://www.forzafire.com/build/1990-nissan-12-skyline-gt-r-bnr32-gr-a-jtc-13961).
- **Livery Editor**: window painting + more pre-made vinyls (PI-class logos, Wristband icons); in-world decorative decals; **vinyl import from prior Forza titles confirmed at launch** (IGN First).
- **Forza Edition cars** now carry *bespoke, un-recreatable fabrication* (e.g. the 1989 Nissan S-Cargo rebuilt into a rear-engine, single-seat, turbo-in-headlight monster) (IGN First; thedrive).
- **Paint favourites + quick material switching**; kei cars wear correct kei plates (Forza accessibility page; thedrive).
- **Steering animation up to 540° wheel rotation** (official).

### 4.3 Garage / houses / showroom
- **8 purchasable houses**, each with a **Customizable Garage** (you start with Mei's house). Load into the garage when you pull up; free-drone camera to walk around own/others' garages (forza.net sandbox blog — https://forza.net/news/forza-horizon-6-sandbox; Polygon — https://www.polygon.com/forza-horizon-6-fh6-customize-garage-how-to).
- Each garage displays **up to 4 cars** (official); community debate over the 3–4 car slots with posts asking for 6–8 (forums.forza.net — https://forums.forza.net/t/expand-fh6-garage-to-show-more-than-three-cars/818816). Certain houses (Akusan Mountain Lodge, Vision House) add +1 display slot each ⚠ (IGGM — https://www.iggm.com/news/fh6-garage-customization-guide-unlock-houses-arrange-cars-copy-community-designs).
- Garage decoration = prop-place "Sims-like" system; **download community layouts** (costs credits to apply); visit others' garages; earn credits if players download your layout (Polygon; forza.net).
- **The Estate** — a permanent mountainside valley (Akiya/abandoned-house concept) where you build freely in the open world with EventLab tools (roads, ramps, structures); solo-build only; downloadable/visit-estate sharing (forza.net sandbox; forza.net features).
- **Forzavista** per-car inspection retained (forza.net sandbox).
- **Autoshow** = the dealership; curated "showroom" area at Horizon Festival site plus buy-on-the-spot from race menus; free weekly cars via Festival Playlist (IGN wiki walkthrough — https://www.ign.com/wikis/forza-horizon-6/Walkthrough).

---

## 5. Game Modes & Events

### 5.1 Campaign content taxonomy (per IGN walkthrough + forzahorizonhub counts)
| Category | Count (in-world) | Notes |
| --- | --- | --- |
| Road Racing events | 22 | Closed roads, themed car restrictions |
| Dirt Racing events | 21 | Asphalt + off-road mix |
| Cross-Country events | 19 | Point-to-point off-road |
| Street Racing events | 15 | **Night/public-road races, live traffic on** (IGN wiki) |
| Touge Racing events | 5 | 1v1 mountain duels (see §5.3) |
| Time Attack circuits | 4 | Open-world PB circuits + leaderboards |
| Drag Racing events (roster) + Drag Meets (3 strips) | 3 + 3 | Festival structured + open-world strip nights |
| PR Stunts | Danger Sign 20 · Drift Zone 20 · Speed Trap 30 · Speed Zone 30 · Trailblazer 11 | = ~111 gated stunt challenges 3-star |
| Landmarks / discoverable areas | 75 ⚠ (game.wiki counts 76) | photo/stamp rasters |
| Player houses | 8 | see §4.3 |
| Horizon Stories (campaign jobs) | 4 story arcs ⚠ + 6 "Day Trips" + Tokyo Food Delivery jobs ⚠ | story chapters 3-star-able (IGN stamp guide keeps count; forzahorizonhub) |
| Festival Sites | 2 (main + Legend Island) | — |

Counts from forzahorizonhub.com/map (796 total markers, 38 categories) and IGN wiki walkthrough/stamp guide.

### 5.2 Race & discipline structure
- Official festival disciplines: **Road, Dirt, Cross-Country Races**, each with car-theme restrictions; plus **Time Attack Circuits, Drag Meets, PR Stunts and Bonus Boards** as wristband-feeders (forza.net progression — https://forza.net/news/forza-horizon-6-progression).
- **Wristband Events** = milestone showdowns; first one ("Pier Pressure") drives the Ford RS200 through Tokyo docks (IGN wiki).
- **Race Customizer unlocks after you finish an event once**: edit laps, weather, season, time-of-day, Drivatar count (up to 11), rewind, camera lock, traffic on/off, car themes/specific cars (u4n drivatars — https://www.u4n.com/news/how-drivatars-works-in-forza-horizon-6.html; forza.net progression).
- **Rivals** (ghost time-trial mode) exists per discipline incl. Touge via the Horizon Play "online tab" — Rivals runs are ghost-only (no collisions) (Steam discussions — https://steamcommunity.com/app/2483190/discussions/0/653730358120050322; dart; IGN wiki).

### 5.3 Signature modes
- **Touge Battles** — series-first formalised 1v1 mountain-pass duels; **5 preset routes** (Hakone, Mt. Haruna, Bandai-Azuma, Norikura, Arahiyama Takao); night-run; two rounds (lead/chase, chase wins by staying in the chase window); **not tied to festival progression** — unlock ≈1 hour in at the Festival; class-restricted (600/700/800/900 brackets); plus an **online Touge Showdown championship** cycling the routes (Operation Sports — https://www.operationsports.com/forza-horizon-6-details-new-touge-battles-progression-changes-in-latest-reveal; armadaboost — https://armadaboost.com/blog/forza-horizon-6-drift-touge-guide-best-cars-by-class-tunes-mountain-pass-strategy).
- **Horizon Rush** — new timed sector-based obstacle races (mix of Showcase spectacle + replayability); **3 at launch**: **Pier Pressure** (Tokyo docks, containers/cranes/billboards), **spaceport** ("a rocket may or may not take off"), **ski-resort "Off Piste"** in the Alps; solo/co-op/competitive; counts as milestone events alongside the classic Showcases (IGN First — https://www.ign.com/articles/forza-horizon-6s-new-rush-events-mix-showcase-style-spectacle-with-a-more-replayable-hook-ign-first).
- **Classic Showcases** — **2 traditional Showcases** kept (incl. the "Mech My Day" Chaser Zero mech race); bookended by the Horizon Invitational (prologue) and the Legend Island finale (IGN First; Wikipedia; fh6.willgameguide.com).
- **Colossus (Goliath)** — longest Goliath ever; full-map freeway loop, ~**50 mi/lap**, R-class; on Legend Island (forza.net campaign; GameSpot).
- **Drag Meets** — 3 persistent, no-loading open-world strips: **Festival Kilometer** (1,000 m, Ohtani), **Irokawa Quarter Mile** (Nangan), **Ito Half-Mile** (Minamino); synchronized Christmas-Tree lights, pre-stage/red-light rules, up to **12 players per strip**, convoy + weekly/season leaderboards, per-PI-class brackets — "less official event, more real-world strip night" (mapmaster.io — https://mapmaster.io/games/forza-horizon-6/guides/Drag%20Meet; fh6guide drag guide).
- **Time Attack** — new series mode: drive through a gantry, beat PBs; **sector splits + live delta**; physical leaderboards around the track filtered by PI and friends; others can join seamlessly in-world; on-site cheaper cars to buy (Traxion — https://traxion.gg/time-attack-and-drag-racing-modes-showcased-in-new-forza-horizon-6-deep-dive).
- **Stunt Party** — Forzathon Live renamed ⚠ (Operation Sports).
- **Drift Attack** — permanent in-world feature added ~Series 5 (Aug 2026) w/ Clipping Zone leaderboards in Tokyo (IGN — https://in.ign.com/forza-horizon-6/271604/permanent-new-drift-attack-feature-active-now-in-forza-horizon-6).
- **EventLab / Horizon CoLab** — see §6.3 + §13.

### 5.4 Checkpoints & event-authoring numbers ⚠ (guide-sourced)
- EventLab: 6 event types (Circuit 1–50 laps, Point-to-Point, Elimination, Playground, Skill Zone, Story); **~120 condition / ~150 action types** in the "Logic Layer" scripting; **up to 500 props per event**; start grid auto-generates **12 positions** (forza.net sandbox; fh6wiki EventLab guide — https://fh6wiki.com/blog/fh6-eventlab-creator-guide; fh6guide — https://www.fh6guide.org/eventlab-guide.html). ⚠ these are guide-reported, Playground publishes no prop/rule caps.

---

## 6. Menus & UI

Known screens and lattice (assembled from IGN wikis, Forza Support, Polygon, YouTube walkthroughs):

- **Main menu / first boot** — Accessibility menu reachable "at the push of a button" from start; difficulty/assists adjust from boot (Forza Accessibility).
- **Pause menu (tabs)** — **Campaign** (contains Settings submenu, both progression tracks, Collection Journal), **Horizon Play** ("online tab"; Rivals lives here), **Creative Hub** (EventLab, Challenges, Garage layouts, Tunes, Liveries, Photos, Community Challenges, Estate), **Cars** (Car Collection + view), **Map**, **Festival Playlist**, **Settings** (IGN wiki; fh6guide; Forza Creative Hub FAQ — https://support.forza.net/hc/en-us/articles/54196710794771-Forza-Horizon-6-Creative-Hub-FAQ).
- **Map screen** — fog-of-war world map, region overview toggle, category filter menu (D-pad right), fast-travel cursor (X on valid white/orange road, house, festival, or event icon); "Festival events" filter at top reveals wristband contributors (Windows Central; dotesports; Forza forums).
- **Festival Playlist UI** — weekly seasonal events, Daily/Weekly/Photo/Treasure challenges, accumulator reward ladder; resets **every Thursday 09:30 EST**; accessible from main menu after Yellow Wristband (IGN weekly-challenges wiki — https://www.ign.com/wikis/forza-horizon-6/All_Forza_Horizon_6_Weekly_Challenges).
- **Garage flow** — Pause → Cars → Car Collection; visit house → tabs: **Customize Garage / View Garage / Browse & Manage / Display Cars / Visitor Permission** (Polygon).
- **Autoshow** — manufacturer-sorted grid; sort by class/year/value/country; filters Affordable/Owned/etc.; car **Vouchers** (see §10) are the real-money shortcut (Forza wiki — https://forza.fandom.com/wiki/Autoshow ⚠ applies FH series conventions).
- **HUD** — speed, revs/tach, minimap, position, race timings, gear; assists display; **Car Proximity Radar** (blind-spot awareness, configurable HUD position + audio cue); cockpit drift-camera toggle + sensitivity; HUD size/opacity accessible (Forza Accessibility; fora.net features).
- **Photo mode** — standard suite; 21 fixed photo-stamped locations (forzahorizonhub); on PC the controls are **arrow-keys/WASD only** — mouse support removed vs FH5, a noted QoL regression (forums.forza.net — https://forums.forza.net/t/photo-mode-controls-for-pc-keyboard/835335).
- **Car Meets menu** — open-world, no menu (drive-in), with option to download liveries/replicas of others' cars at the meet (Operation Sports).

---

## 7. AI & Traffic (Drivatars)

- **Drivatars** = cloud behaviour-capture AI: aggressive/defensive multi-line behaviour, name-stamped from real players incl. offline friends; "roads are never empty"; up to **11 Drivatars per event** (Race Customizer); offline Drivatars race in other players' worlds and farm credits for you (u4n drivatars).
- FH6-specific complaints: **"cheating" hard AI** (corner traction, wall ghosting, rubber-banding) plus lairy aggression. Playground patched Drivatar balance in Series 3 (July 2026) (Wikipedia — https://en.wikipedia.org/wiki/Forza_Horizon_6; thegamepost — https://www.thegamepost.com/news/forza-horizon-6-series-3-italian-exotics-update-notes).
- **"bowie knife99"** — a single AI Drivatar became the community's internet-famous griefer ("WHY IS HE ALWAYS BULLYING ME"); great demonstration of how much *character* a well-scripted rival adds to world-feel (Windows Central; PC Gamer — https://www.pcgamer.com/games/racing/forza-horizon-6-car-list; GameSpot — https://www.gamespot.com/articles/forza-horizon-6s-most-hated-driver-has-become-an-internet-legend — mirrored in Wikipedia).
- **Rivals** = ghost time trials (no collisions) per discipline incl. Touge (see §5.2).
- **Traffic**: denser than FH5 per comparisons ⚠ (lootbar.com); Street Races keep live traffic; convoys up to 12.
- License-based matchmaking pilots hinted (skill/"cleanliness" ratings) ⚠ (u4n — rolling, not shipped).

---

## 8. Weather & Time

- **Day/night** — full cycle **~60 min (~40 day / ~20 night)**; shortcuts from events/fast travel advance time ⚠ guide — https://fh6.willgameguide.com/reference/times-of-day-cycle/ (see `fh6_map.md` §3.5).
- **Dynamic, regionalised weather** (not FH5's biome-fixed): Tokyo rain/fog, Fuji/Hakone mist/snow, north blizzards, coast storms — ⚠ "72 weather micro-stations" is a single-source claim (fh6.willgameguide.com), not corroborated.
- **Four seasons rotate weekly** (every Thursday, ~09:30 EST reset alongside the Playlist); **per-region** — the Alps can snow while the coast stays dry the same day; alpine biome keeps permanent year-round snow (allthings.how — https://allthings.how/how-to-change-seasons-in-forza-horizon-6-creative-hub-method/; fh6wiki.com; `fh6_map.md`).
- Weather/time are **event-runtime variables** in the Race Customizer (change weather/season/time per custom race). Creative Hub/EventLab can **fix a season** to play out-of-sequence (allthings.how).
- Grip/visibility effects ⚠ approx table in `fh6_map.md` §3.4: dry 100% → heavy snow ~50% → ice ~30% grip; winter punishes RWD; AWD far more valuable; snow tyres meta for drift ⚠ (mitchcactus YouTube).

---

## 9. Audio

- **Radio: 9 stations, 224+ tracks** — the largest licensed soundtrack in series history. Stations: **Horizon Pulse, Horizon Bass Arena, Horizon Block Party, Horizon XS, Hospital Records, Gacha City Radio (new, J-pop/J-rock/city pop), Sub Pop Records (new), Horizon Wave, Horizon Opus (new)** (forza.labsgg — https://forza.labsgg.com/soundtrack; NME — https://www.nme.com/news/gaming-news/forza-horizon-6-radio-soundtrack-playlist-3944223; Polygon — https://www.polygon.com/forza-horizon-6-fh6-radio-stations-song-list-how-to-change-music).
- Per-station trackblocks: Pulse 30, Bass Arena 27, Block Party 26, XS 25, Hospital 24, Gacha City 22, Sub Pop 23, Wave 22 + Opus ⚠ (labsgg table). Each station has DJ hosts (e.g. Biffy Clyro's Simon Neil on XS; Sub Pop staff on Sub Pop) (Polygon).
- **Car audio:** new recordings/remastered audio, upgraded modular engine systems with **turbo + backfire chatter**, surface-interaction detail, improved **cockpit impulse responses** (forza.net features).
- **Triton Acoustics** — object-based spatial reverb system simulating real-world acoustics from virtual object positions; new acoustic-modelling tech for world soundscape (forza.net features).
- Photo-mode/crowd ambience: crowds step-charted (Windows Central review).

---

## 10. Progression & Economy

### 10.1 Three campaign pathways (official framing)
1. **Horizon Festival — Wristbands (7)**: Yellow (qualify at Horizon Invitational) → Green → Blue → Pink → Orange → **Purple (needs ~32,500 Festival Points)** → **Gold (Horizon Legend)** → unlocks **Legend Island**. Wristbands gate event tiers and class caps (start C-class-qualified; Hypercars blocked until Purple) (forza.net progression + campaign; fh6guide — https://www.fh6guide.org/).
2. **Discover Japan — Stamps (7 ranks)**: point ladder **Yellow 1,250 / Green 2,500 / Blue 5,000 / Pink 8,000 / Orange 12,000 / Purple 16,000 / Gold 20,000 Discover-Japan points**; sources include touge/street wins (~350 pts), story 3-star (~300), mascots (~25); gates **Barn Find rumour reveals** and property unlocks (fh6treasurehunt — https://fh6treasurehunt.com/tools/explorer-stamps; IGN stamp guide).
3. **Horizon Play — Badges to Level 100** (multiplayer XP, +1 badge every 10 ranks; some cross-over with campaign).
- Plus classic XP/prestige player levelling and the **Collection Journal** (total ticker for cars/photos/mascots/homes/landmarks) (forza.net progression; IGN wiki).
- **57 achievements**, incl. "Destroy 200 regional mascots", "Destroy 200 bonus boards", "Reach level 100 in Horizon Play" (Red Bull achievement guide).

### 10.2 Economy
- Earn: races, Wheelspins (locked until Festival qualification), Time Attack, PR stunts, skill chains, playlist, Aftermarket deals, and Auctions.
- **Autoshow Car Vouchers** (real-money): **$4.99/4, $9.99/10, $19.99/24** — buy Autoshow cars without credits (GameWatcher — https://www.gamewatcher.com/reviews/forza-horizon-6/13966; Forza support voucher FAQ).
- **Auction House**: 15% listing fee, buy-it-now global cap **20M credits** (raised 21 July 2026 — previously per-car rarity caps); no vouchers accepted inside (Traxion — https://traxion.gg/forza-horizon-6-auction-house-explained/; Polygon — https://www.polygon.com/forza-horizon-6-update-auctions-nerfs-economy).
- **Economy controversy** (Summer 2026): launch-era slowdown (fewer credits/wheelspins), then the cap raise let rare/Wheelspin-only cars get listed at 20M, locking casual players out; long-race payouts reportedly further nerfed in the "Italian Exotics" update — the community's biggest live-service complaint (Polygon).
- **Festival Playlist** = the monthly live-service engine: 4-week series, weekly season rotation (Summer→Spring), 20/40/60/120-point reward ladder, plus new **"Series History Rewards"** (lifetime Playlist Points → exclusive cars); **FOMO criticism** is endemic — aftermarket-car rotation and auction pool are the catch-up mechanisms (IGN — https://www.ign.com/articles/forza-horizon-6s-first-festival-playlist-rewards-revealed-begins-may-21; Yahoo/WindowsCentral — https://tech.yahoo.com/gaming/articles/forza-horizon-6-festival-playlist-131001344.html).
- Post-launch series cadence 2026: **S1 "Welcome to Japan"** (May 21) → **S2 "Horizon Decades"** (Jun 18) → **S3 "Italian Exotics"** (Jul 16) → **S4** (Aug 10) → **S5 "British Automotive"** (Sep 10) (Traxion playlist guide — https://traxion.gg/forza-horizon-6-festival-playlist-guide/).

---

## 11. Accessibility & Options (headline slate)

Official (Forza Support accessibility page):
- **Granular High Contrast Mode** — fully customizable, in-gameplay (not just menus) — major new feature.
- **Car Proximity Radar** — blind-spot radar, HUD-position + audio-cue configurable.
- **AutoDrive** — with ANNA, set waypoint from map in free roam.
- **ASL + BSL sign language** (American/British) — carried forward (BSL "coming in a later update" per Xbox listing ⚠).
- Difficulty/assists: **Tourist Drivatar** (wins every race), ABS/TCS, steering assist, suggested line, rewind, **offline game-speed reduction**, story-chapter auto-complete toggle, colour-blind filters (Deuteranopia/Protanopia/Tritanopia applied to whole scene incl. cars), map-icon/UI colour schemes, HUD scaling/opacity, granular volume sliders, independent language select, subtitles, cockpit drift-camera options, button-hold remap (playable without holds), single-stick play, adjustable input sensitivity (Xbox store listing).
- HUD: adjustable size/position/opacity; Car Collection tab lists unlock source per car (fh6guide).
- The Eliminator ships an Auto-Drive support FAQ (Forza support — https://support.forza.net/hc/en-us/articles/52613640745875-The-Eliminator-Auto-Drive-Support-FAQ).

---

## 12. Performance & Tech (brief)

### 12.1 Console modes
- **Series X**: Quality = **native 4K, 30 fps, RT on**; Performance = **4K (dynamic res), 60 fps**. **Series S**: Quality = 1440p/30, Performance = **1080p/60**. No RT in Series S ⚠ review-noted (IGN — https://www.ign.com/articles/forza-horizon-6s-xbox-series-xs-quality-and-performance-modes-explained; Digital Foundry via eurogamer — https://www.eurogamer.net/digitalfoundry-2026-forza-horizon-6-review).
- RT: ray-traced global illumination + reflections across the open world; DF: tech base "largely unchanged from FH5", renderer is 2021-era on PC (no mesh shaders), RTGI has cost even on RTX 50 (eurogamer DF).
- GamesRadar/Windows Central: "best-looking racer on console/PC", RT crowds.

### 12.2 PC tiers & upscaling
- Official four tiers: **Minimum** 1080p60 low (i5-8400/R5 1600, GTX 1650 / RX 6500 XT / Arc A380, 16 GB, SSD); **Recommended** 1440p60 high (RTX 3060 Ti / RX 6700 XT / Arc A580); **Extreme** 4K60 extreme (RTX 4070 Ti / RX 7900 XT, 24 GB, NVMe); **Extreme RT** 4K60 with RT (RTX 5070 Ti / RX 9070 XT, 32 GB, NVMe) (instant-gaming news — https://news.instant-gaming.com/en/articles/18713-forza-horizon-6-reveals-its-minimum-pc-requirements).
- Upscaling: **DLSS 4.5 Super Resolution + Multi Frame Generation** (RTX 50: 4X–6X Dynamic mode via NVIDIA App), **FSR 4/3, XeSS 2.1**. NVIDIA claims ~5.2× at 4K max+RT with DLSS SR+MFG: RTX 5090 >330 fps / 5080 >230 / 5070 Ti >200 with FG (NVIDIA — https://www.nvidia.com/en-eu/geforce/news/forza-horizon-6-dlss-4-5-super-resolution-multi-frame-gen; Radio Times — https://www.radiotimes.com/technology/gaming/forza-horizon-6-benchmarks-explained).
- Notebookcheck independent: RT is brutally demanding; QHD+RT needs 5070 Ti desktop-class (~60 fps); RTX 4050 Laptop ~50 fps Extreme no-RT (notebookcheck.net — https://www.notebookcheck.net/Forza-Horizon-6-benchmark-test-Stunning-visuals-between-surprisingly-scalable-and-brutally-demanding.1296755.0.html).
- **Steam Deck Verified** (Radio Times).

### 12.3 I/O & load pipeline
- **Advanced Shader Delivery (ASD)**: precompiled PSO caches cut first-load **~90 s → ~4 s** on Windows (95% claimed; needs Win11 24H2+, MS Store/Xbox-app builds) (Tom's Hardware — https://www.tomshardware.com/pc-components/gpu-drivers/forza-horizon-6-boots-up-in-just-4-seconds-instead-of-90-with-new-advanced-shader-delivery-tech-and-amd-gpus-microsoft-claims-95-percent-reduction-in-gaming-load-times).
- **DirectStorage 1.2/1.3** w/ GPU GDeflate decompression + EnqueueRequests batching; NVMe recommended at high settings; ⚠ peak streams >1 GB/s, ~2 GB/s through Tokyo at speed (borecraft — https://borecraft.com/findings/fh6-storage-findings.html). Full detail in `fh6_map.md` §4.

---

## 13. Multiplayer & Social

- **Shared open world**: sessions on the same map with seamless drop-in events; ⚠ one source claims up to **72 players/session** (2upskill — https://2upskill.com/forza-horizon-6-multiplayer-guide-how-to-join-open-world-car-meets-and-convoys/; mirrored in Wikipedia for The Eliminator's 72-player cap).
- **Convoys** — up to **12 players**; members get pulled into the same activities (drag strip, car meet) and share Festival Playlist progress (forzahorizoncar multiplayer wiki — https://forzahorizoncar.com/en/wiki/guides/multiplayer.html).
- **Car Meets** — 3 permanent, no-loading open-world meets: **Horizon Festival Site, Okuibuki Parking Lot (Alps), Daikoku Parking Area (Tokyo)** + rotating Playlist meets; download liveries/vehicle replicas, buy others' builds (forza.net features; Polygon map — https://www.polygon.com/map/forza-horizon-6-fh6-japan-interactive/; `fh6_map.md`).
- **Horizon Play modes**: **The Eliminator** (72-player battle royale, starts in the 1984 Honda City, car-upgrade duels, closing safe zone), **Hide & Seek** (asymmetric 1v11, hunter aura), **Spec Racing Championships** (everyone same car + tune, weekly-rotating model), **Touge Showdown** (1v1 mountain ladder), **Co-op LINK skills** (Twin Drift, Sync checkpoint, SUPER LINK → Super Wheelspin), Custom Racing (Operation Sports; forzahorizoncar wiki; PS.com).
- **Rivals** — ghost leaderboards incl. Touge; per-discipline reward cars (Road Rivals → Cayman GT4 RS, Touge & Street Rivals → Nismo GT-R '24, etc.) (IGN wiki).
- **CoLab** — EventLab multiplayer co-building (up to 12 per official messaging ⚠ vs 4-editor sessions per some guides), with voice + ping, test-as-you-build.
- Photo contests / weekly Photo Challenges on the Playlist (IGN weekly-challenges wiki), Sharing: garages, estates, liveries, tunes, events (Forza Creative Hub FAQ).
- **Creative Hub rank**: global popularity rank across 9 UGC categories (Prefabs, Events, Tunes, Garage Layouts, Challenges, Liveries, Estate, Photos, Vinyl Groups); creators earn credits when their content is used (Polygon garage guide; Creative Hub FAQ).

---

## 14. Collectibles

| Collectible | Count | Notes / status |
| --- | --- | --- |
| Regional Mascots | **200** (9 food-themed types: Curry 20, Dango 25, Edamame 20, Kakigori 20, Matcha 25, Omurice 15, Onigiri 25, Ramen 25, Tempura 25) | press-confirmed + achievement "Destroy 200 regional mascots" (PowerPyx — https://www.powerpyx.com/forza-horizon-6-all-collectible-locations-treasure-map-mascots-bonus-boards/; forzahorizonhub) |
| Bonus Boards (XP boards) | **200** | press-confirmed; 3 difficulty tiers (roadside / hidden / rooftop-jump) ⚠ point values reported 10/30/50 vs 1,000/3,000/5,000 across guides |
| **Total collectibles** | **400** | press-confirmed |
| Fast Travel Boards | **0** (removed) | confirmed (see §3.2) |
| Barn Finds | **15**, gated by Discover-Japan Stamps (level 1→7 batches of ~2-4; final batch includes Nissan Tomica Super Silhouette + **Mazda 787B** as Gold unlock) | press-confirmed (IGN wiki; PC Gamer — https://www.pcgamer.com/games/racing/forza-horizon-6-barn-finds; Red Bull) |
| Treasure Cars | **9** (one per region, no prereqs, photo-clue hunts) | press-confirmed (PC Gamer; Shacknews — http://www.shacknews.com/article/149398/barn-finds-treasure-cars-fh6) |
| Aftermarket Cars spawn points | 31 parking spots (rotating cars, discount) | guide ⚠ (forzahorizonhub) |
| Discovery Landmarks | **75** (forzahorizonhub) vs **76** (game.wiki tracker) | ⚠ sources differ |
| Photo Locations | 21 (fixed stamp spots) | guide ⚠ |
| Playlist weekly collectibles | Treasure Hunt (per-region), Photo Challenge, snack/vending "Snack Attack", "Bamboo Bash" etc. | official (IGN weekly-challenges) |
| Treasure Map DLC | $2.99 — reveals all collectible locations instantly | press (PowerPyx) |
| Total interactive map markers | **796 across 38 categories** (incl. all events/stunts/houses/meets) | forzahorizonhub ⚠ |

---

## 15. Concrete Numbers Cheat-Sheet

| Metric | Value | Status |
| --- | --- | --- |
| Cars at launch | 550+ official; 618 community-checked (87 mfrs) | official + press |
| Cars current (Aug 2026) | 636 official table / 642 tracker | official + tracker ⚠ |
| Car classes | 7: D→R (R new, PI 100–998) | official |
| Car Pass DLC cars | 30 (weekly) | official |
| Houses / garages | 8 / 8 customizable (Estate +1) | official |
| Cars per garage display | up to 4 (+1-slot houses ⚠) | official / ⚠ guide |
| Map playable area | ~122–246 km² ⚠ (no official) | fan estimates |
| Map span | ~21 miles (~34 km) N–S | press measure |
| Colossus/Goliath lap | ~50 mi (~80 km) | press |
| Roads | 671 in-game counter ⚠ (673 preview press ⚠) | game data ⚠ |
| Road mileage | ~540 mi ⚠ (single-source) | ⚠ |
| Regions / districts | 10 regions (per achievement) / 74 districts | official-ish |
| Collectibles | 400 (200 mascots + 200 boards) | press-confirmed |
| Barn Finds / Treasure Cars / Aftermarket spots | 15 / 9 / 31 | press / ⚠ guide |
| PR stunts | 111 (20+20+30+30+11) | tracker ⚠ |
| Race events (base) | Road 22 · Dirt 21 · CC 19 · Street 15 · Touge 5 · TA 4 · Drag 3 | tracker ⚠ |
| Horizon Rush courses | 3 | official |
| Drag strips / Car Meets | 3 / 3 | official |
| Touge winner cap | 11 Drivatars/event | guide |
| Eliminator / session cap | 72 players | press + wiki |
| Convoy cap | 12 | official |
| Day/night cycle | ~60 min (40/20) | ⚠ guide |
| Seasons / Playlist reset | 4, weekly Thursday 09:30 EST | official |
| Radio stations / tracks | 9 / 224+ | official/press |
| Series pass | ~$70 Standard+ (see editions) | official |
| Car voucher packs | $4.99/4 · $9.99/10 · $19.99/24 | press |
| Auction buyout cap | 20M credits | official update |
| Achievements | 57 | press |
| Max earning difficulty | Tourist → above 100% (Unbeatable tier) | official |
| First-load (Win, ASD) | ~4 s (vs ~90 s) | press |
| Series X modes | 4K30RT / 4K-dyn60; Series S 1440p30 / 1080p60 | official |
| Launch players | 6M+ week one; 270K Steam peak ⚠ | press / ⚠ |

---

## 16. Sources Index (primary for this dossier)
- Official features list — https://forza.net/news/forza-horizon-6-features
- Official progression (3 pathways) — https://forza.net/news/forza-horizon-6-progression
- Official campaign/wristband blog — https://forza.net/news/forza-horizon-6-campaign
- Official sandbox (garages/Estate/EventLab/CoLab) — https://forza.net/news/forza-horizon-6-sandbox
- Official car-culture blog (customization) — https://forza.net/news/forza-horizon-6-car-culture
- Official FH6 car list (forza.net) — https://forza.net/fh6cars
- Xbox Wire launch — https://news.xbox.com/en-us/2026/05/18/forza-horizon-6-now-available/
- Xbox Wire Japan setting — https://news.xbox.com/en-us/2025/09/25/forza-horizon-6-japan-setting-2026
- IGN review (10/10) — https://www.ign.com/articles/forza-horizon-6-review
- IGN First customization — https://www.ign.com/articles/forza-horizon-6s-customization-improvements-and-crazier-than-ever-forza-edition-cars-ign-first
- IGN First Rush events — https://www.ign.com/articles/forza-horizon-6s-new-rush-events-mix-showcase-style-spectacle-with-a-more-replayable-hook-ign-first
- IGN wiki walkthrough + stamp guide + weekly challenge wiki + PS5 articles (as cited above)
- Wikipedia FH6 — https://en.wikipedia.org/wiki/Forza_Horizon_6
- PC Gamer car list (618) — https://www.pcgamer.com/games/racing/forza-horizon-6-car-list
- PC Gamer barn finds — https://www.pcgamer.com/games/racing/forza-horizon-6-barn-finds
- PC Gamer map preview — https://www.pcgamer.com/games/racing/forza-horizon-6s-japan-map-is-the-series-best-yet/
- Windows Central car list + fast travel + review — as cited above
- GameSpot map size + touge/hide-seek coverage — https://www.gamespot.com/articles/forza-horizon-6-map-size-best-places-to-visit-and-how-to-reach-them/1100-6540006
- GameSpot championship Rivals/Touge — https://www.gamespot.com/articles/forza-horizon-6-channels-initial-d-inspired-anime-racing-with-its-new-mode/1100-6537597
- Operation Sports touge/playlist — https://www.operationsports.com/forza-horizon-6-details-new-touge-battles-progression-changes-in-latest-reveal
- Traxion time attack/drag deep dive — https://traxion.gg/time-attack-and-drag-racing-modes-showcased-in-new-forza-horizon-6-deep-dive
- Traxion Car Pass — https://traxion.gg/every-car-included-with-forza-horizon-6s-car-pass-dlc
- Traxion auction house — https://traxion.gg/forza-horizon-6-auction-house-explained/
- fh6guide car list / progression / EventLab / drag / barns — https://www.fh6guide.org/ (+ subpages cited)
- forzahorizonhub interactive map counts (796 markers) — https://forzahorizonhub.com/map
- forzahorizon6carlist.com roster audit — https://forzahorizon6carlist.com/
- Red Bull achievement guide — https://www.redbull.com/int-en/forza-horizon-6-achievement-guide-all-achievements
- Red Bull barn finds — https://www.redbull.com/au-en/forza-horizon-6-barn-finds-guide
- Shacknews barn finds/treasure cars — http://www.shacknews.com/article/149398/barn-finds-treasure-cars-fh6
- Polygon economy/auction drama — https://www.polygon.com/forza-horizon-6-update-auctions-nerfs-economy
- Polygon garage guide — https://www.polygon.com/forza-horizon-6-fh6-customize-garage-how-to
- Polygon radio/soundtrack — https://www.polygon.com/forza-horizon-6-fh6-radio-stations-song-list-how-to-change-music
- forza.labsgg soundtrack (9 stn/224+) + car tracker — https://forza.labsgg.com/soundtrack ; https://forza.labsgg.com/cars
- Forza Accessibility Support — https://support.forza.net/hc/en-us/articles/51644264237075-Forza-Horizon-6-Accessibility-Support
- Forza Creative Hub FAQ — https://support.forza.net/hc/en-us/articles/54196710794771-Forza-Horizon-6-Creative-Hub-FAQ
- Eliminator Auto-Drive FAQ — https://support.forza.net/hc/en-us/articles/52613640745875-The-Eliminator-Auto-Drive-Support-FAQ
- u4n Drivatar explainer — https://www.u4n.com/news/how-drivatars-works-in-forza-horizon-6.html
- u4n car classes — https://www.u4n.com/news/forza-horizon-6-car-classes.html
- NME soundtrack — https://www.nme.com/news/gaming-news/forza-horizon-6-radio-soundtrack-playlist-3944223
- Disaster/Nvidia DLSS 4.5 + MFG — https://www.nvidia.com/en-eu/geforce/news/forza-horizon-6-dlss-4-5-super-resolution-multi-frame-gen
- Radio Times benchmarks — https://www.radiotimes.com/technology/gaming/forza-horizon-6-benchmarks-explained
- instant-gaming PC requirements — https://news.instant-gaming.com/en-us/articles/18713-forza-horizon-6-reveals-its-minimum-pc-requirements
- Notebookcheck benchmark — https://www.notebookcheck.net/Forza-Horizon-6-benchmark-test-Stunning-visuals-between-surprisingly-scalable-and-brutally-demanding.1296755.0.html
- Tom's Hardware ADS — https://www.tomshardware.com/pc-components/gpu-drivers/forza-horizon-6-boots-up-in-just-4-seconds-instead-of-90-with-new-advanced-shader-delivery-tech-and-amd-gpus-microsoft-claims-95-percent-reduction-in-gaming-load-times
- Digital Foundry / Eurogamer review — https://www.eurogamer.net/digitalfoundry-2026-forza-horizon-6-review
- armadaboost FH5-vs-FH6 — https://armadaboost.com/blog/forza-horizon-6-vs-forza-horizon-5-is-japan-actually-worth-the-upgrade
- GameWatcher review — https://www.gamewatcher.com/reviews/forza-horizon-6/13966
- fh6treasurehunt stamp ladder — https://fh6treasurehunt.com/tools/explorer-stamps
- fh6.willgameguide.com time/weather — https://fh6.willgameguide.com/reference/times-of-day-cycle/ ; /reference/weather-guide/
- allthings.how seasons — https://allthings.how/how-to-change-seasons-in-forza-horizon-6-creative-hub-method/
- Driveholic/TheDrive customization — https://www.thedrive.com/news/forza-horizon-6s-car-customization-is-getting-a-welcome-overhaul
- Windows Central bowie knife99 — https://www.windowscentral.com/gaming/forza/forza-horizon-6-players-have-it-out-for-bowie-knife99-an-ai-drivatar-that-rams-players-more-than-griefers-do
- forzahorizoncar multiplayer wiki — https://forzahorizoncar.com/en/wiki/guides/multiplayer.html
- 2upskill multiplayer — https://2upskill.com/forza-horizon-6-multiplayer-guide-how-to-join-open-world-car-meets-and-convoys/
- GameSpot Achievements mirror — https://www.gamespot.com/articles/forza-horizon-6s-most-hated-driver-has-become-an-internet-legend
- IGN PS5 articles — https://www.ign.com/articles/forza-horizon-6-ps5-launch-reportedly-scrubbed-for-2026 ; https://www.ign.com/articles/forza-horizon-6s-ps5-version-still-on-track-for-2026-release-playground-says
- Steam Community threads (road count 671; touge rivals; event restrictions) — as cited inline

---

## 17. What Makes FH6 Tick — Design Pillars a Rival Should Match

1. **Customization is the product.** FH6's biggest applause line is the garage: per-car Forza Aero, window liveries, 100+ rims w/ stagger fitment, true body kits (Liberty Walk / Rocket Bunny / Origin Lab), and a *physical* showroom (8 garages + Estate + community layouts). An indie rival should nail one layer deeply rather than 600 cars shallowly.
2. **Density over size.** No km² number is published by design — the selling point is "most dense + vertical map yet", ~670 roads, touge/urban/city four-tier road hierarchy, and fade-to-fog discovery that turns driving into the reward loop. Discovery = the core loop; fast travel is the payoff, gated by having driven a road.
3. **Car culture as event taxonomy.** Events are authored per driving subculture, not per grid: nuit street racing in Tokyo (live traffic), 1v1 Touge battles on 5 named passes, 3 no-loading drag strips, the C1 night-run, drift circuits, Daikoku car meets. The world "respects the car" — places to park, photograph, and play meet up (IGN).
4. **The world is a place for social display.** Car Meets (3 permanent), visitable/borrowable garages and estates, cooperative LINK skills, Spec Racing (same car/tune = pure skill) — multiplayer is threaded into the map instead of lobbies.
5. **Weather/time are *driving* mechanics, regionally.** Per-region seasons (not one global state), ~60-min day/night, grip/visibility tables that reward AWD in alpine winter — elevation and climate change route validity by season.
6. **Prologue-to-Legend arc made of wristbands + stamps.** Two parallel tracks (Festival wristbands 1–7, Discover-Japan stamps) structure pacing so slow cars matter for ~15–25 h; the full-map Colossus (~50 mi) and Legend Island are endgame trophies.
7. **"Approachable" as an explicit spec.** Granular High Contrast, Car Proximity Radar, AutoDrive, Tourist Drivatar, story skip — accessibility is a launch-blocking feature set, treated as headline marketing, not a patch.
8. **A characterful rival cast (even a villain).** The "bowie knife99" phenomenon shows that a single memorable AI can turbo-charge world-feel and social chatter for free — a cheap, huge personality win for a smaller studio.

> **Bottom line for UltraDrive:** the defensible FH6 recipe is *customization depth on a curated roster* + *density-and-discovery map* + *culture-themed live events* + *regional climate that changes driving* + *a transparent, calm economy*. Everything else (600+ cars, RT, 9 radio stations, live-service Playlist) is scale that an indie converts to focused equivalents, not needs to clone.