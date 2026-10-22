# Le Mans No-Chicane — Visual Realism Plan (GT7-grade trackside)

Status: **IMPLEMENTED 2026-10-21 (uncommitted) — see §8 for per-workstream
status, evidence and caveats; real elevation added 2026-10-22 (§9).** Techniques below are pinned to
`docs/research/gt7_le_mans_visual_realism.md` (GT7/Forza scan pipeline, real
Sarthe inventory, the five concrete "video-game" tells, and the Godot 4 routes
with their traps). P0 audit answer: Le Mans runs **no Terrain3D at all** (flat
6 x 7 km PlaneMesh by contract, v1 plan §3.7), so "autoshader / macro
variation" was implemented as a world-space ground shader instead (§8 WS-B).

## 1. Why

The Le Mans No-Chicane circuit (shipped in `4c92079`, plan
`docs/plans/track_le_mans_no_chicane.md`) drives well but reads as
"video game": sparse props, uniform grass, no sand/gravel run-off, rails only
at corner complexes, and no background depth. GT7's Circuit de la Sarthe feels
real through a specific, enumerable set of trackside layers — we can reproduce
most of it with systems we already own.

Reference research: `docs/research/gt7_le_mans_visual_realism.md`
(GT7 techniques, real Circuit de la Sarthe trackside inventory, Godot 4
implementation notes, sources).

## 2. Current state (audited 2026-10-20)

**Track definition:** `scripts/track/track_registry.gd:36-43` (`le_mans`,
"Le Mans No-Chicane", `res://scenes/track/le_mans.tscn`, ENDURANCE).
Geometry is `scripts/track/le_mans_layout.gd` (51 OSM anchors → 4800 pts,
13,626 m); scene orchestration `scripts/track/le_mans.gd`; dressing
`scripts/track/le_mans_dressing.gd` (`LeMansDressing`, self-contained,
MultiMesh + fused primitives, deterministic).

**What exists today (LeMansDressing kinds):**
| Kind | Where | Ref |
|---|---|---|
| Gantry (S/F, neutral banner) | arc 0 | `le_mans_dressing.gd:90-98,218-231` |
| Checker paint slab | S/F carriageway | `:100-104,233-241` |
| Dunlop-style arch (neutral) | chainage 869 | `:244-257` |
| Visual armco (no colliders) | corner complexes ≥40°, ±50 m | `:105-114,262-276` |
| Hedgerows | Mulsanne 2000–7300 m, both sides | `:114-120,279-293` |
| Tyre stacks (4×3) | braking zones 1450/7300/9600/9950/13020 | `:121-128,296-311` |
| Apex kerbs (red/white) | sharp corners | `:129-134,314-328` |
| Marshal posts | every 1500 m, alternating | `:135-145,331-345` |
Plus a `Foliage` instance (`le_mans.gd:101-113,302-313`) and ground skirt.

**Explicitly absent (v1 out-of-scope, now in scope for this plan):**
grandstands, pit buildings/lane, floodlights, full-lap armco + catch
fencing, ad boards/billboards, **gravel/sand traps & run-off**, branded
signage, background/distance scenery, surface wear/weathering.

**Environment** (`scenes/track/le_mans.tscn:15-70`): PhysicalSkyMaterial,
sky-ambient 0.7, light fog (density 0.0008), ACES, exposure 0.9; SDFGI/SSAO/
SSR/volumetric/glow all off; `sun_driver.gd` sun; shadow max distance 140 m.
Quality ladder (`SettingsMenuScript.apply_to_scene_tree`) re-applies on boot
— any new FX must degrade on Low/Medium.

**Reusable systems:** `LeMansDressing` API (`configure/build/prop_mesh/
transforms_of`), `RoadDef` rails (`RailSide` — currently `NONE`),
`TrackBuilder`, `PropScatterer` (GLB presets + road clearance),
`Foliage`/`RegionDresser` patterns, `assets/track_props/*` (Kenney CC0
racing kit), `OvalDressing`/`RxDressing` as dresser templates,
`SurfaceRegistry` (P3) for grip-correct sand/gravel surfaces.

## 3. Target look (research: the five concrete tells → our Gaps)

The research doc reduces "video-game look" to five causes, all present here:

1. **Uniform surfaces** — one grass material, one asphalt material, no macro
   variation, no texture set selected by slope/height. → WS-B.
2. **No wear layer of any kind** — real tracks carry rubbered lines, oil, dirt
   and graffiti *in the captured surface data*; we have zero decals. → WS-F.
3. **Thin trackside density** — barriers/hoardings/posts/towers sparse. → WS-C + D.
4. **Faceted horizon** — sky meets grass with nothing between. → WS-E.
5. **Flat atmosphere** — no aerial separation, procedural sky, no HDRI. → WS-F.

Honest framing carried from the research doc: GT7's look starts as a **survey
problem** (laser scan + 8 TB photogrammetry pass per circuit, GPS-registered,
Houdini-filled). We cannot scan Le Mans. The achievable equivalent is
**material variety + macro variation + wear decals + barrier/prop density +
aerial perspective + HDRI sky** — a build-out of systems we already own, not a
scan pipeline. Plan accordingly and do not promise scan fidelity.

## 4. Workstreams

Each workstream: (i) technique per research doc, (ii) implement inside
`LeMansDressing` (or a sibling `LeMansScenery` node) — keep it
self-contained/deterministic like v1, (iii) gate with an addition to
`tests/suites/test_le_mans_track.gd` (budget/count assertions), (iv) perf
budget: added per-frame cost must keep the 13.6 km scene within the
`test_perf_gate` relative mode envelope (MultiMesh-first, no per-frame JS).

### A. Sand/gravel traps + run-off (priority 1)
- Locations from the real-Sarthe inventory: Tertre Rouge (reprofiled 2013,
  tyre barriers), Mulsanne braking zones, Indianapolis/Arnage, and the Ford
  Chicane (gravel **plus sausage kerbs**).
- Geometry: flattened shoulder quads off the road edge, 3–8 m wide, 2–4°
  outward slope; material = pale sand/gravel with normal map + noise breakup
  and a ragged vertex-colored blend edge into grass (kill the "perfect edge").
- Paved run-off aprons at the modernized corners.
- Wire sand/gravel zones into `SurfaceRegistry` (P3) so grip drops
  realistically — visuals + physics from one source of truth.

### B. Ground/grass variation
- **Macro variation is the single cheapest win** — Terrain3D's own shader docs
  treat it as a standard step this project is skipping; enable/tune it first.
- More than one texture set, blended by slope/height via the **autoshader** so
  grass/dirt/stone separate automatically instead of one tiling grass.
- Repaint splat/vertex color: dark worn band along the road edge, discolored
  verge, dirt at braking zones.
- Optional: **Paint Wetness** to roughen/darken the shoulder band (research
  recommendation) where it does not fight the weather system.
- Foliage pass: denser clusters along the Mulsanne hedgerow sections, real
  gaps preserved; keep the existing `band_visibility` culling pattern.

### C. Barriers: full-lap armco + catch fence + tyre walls
- Extend armco from corner-windows to near-continuous coverage on outside
  edges (real no-chicane-era Sarthe is armco-lined; Armco present since 1969),
  reusing the 4.6 m segment pipeline, skipping pit/service gaps.
- **MultiMesh-instanced** barriers (research: Terrain3D instancer is
  MultiMesh-per-32 m-cell; no per-instance culling/collision). Catch fencing
  uses **alpha-scissor + distance fade** to kill aliasing.
- Double-stack tyre walls + blue-white barrier panels at every braking corner
  (not just the 4 v1 zones); Tertre Rouge tyre barriers specifically.
- Colliders stay out by default; if needed, enable `RoadDef` rails at corners
  only (perf).

### D. Trackside clutter layer
- Ad-board / hording rows (unbranded, colored — keep no-trademark stance)
  along straights and behind barriers; MultiMesh, 2–3 color sets.
- Marshal posts / distance boards / equipment boxes (extend the existing
  `KIND_POST`), TV camera towers at 3–4 vantage points, service-road dirt
  tracks behind barriers.
- **Ride existing density systems** (research: this is preset work, not new
  architecture): `PropScatterer` (deterministic, road-aware) + `RegionDresser`
  band budgets + seeder km→locs ladder (MAX 190).
- ⚠️ Research trap: MultiMesh instance counts **sum across children** — read
  the summed count, never first-child.

### E. Distance scenery / horizon depth
- Far tree-line ring (impostor/billboard MultiMesh, 400–1200 m band, dark
  value → aerial-perspective read), placed to match the real hedgerow/tree
  lines rather than uniformly scattered.
- Low silhouette geometry: industrial/port shapes, church spire, hangars —
  fogged low-poly silhouettes standing in for GT7's photo plates.
- Porsche Curves walls and other landmark silhouettes for route memory.

### F. Lighting/atmosphere + wear layer
- **Depth fog with Sun Scatter + Aerial Perspective** (one-class change),
  confirmed already partially on (`aerial_perspective=true`).
- **HDRI or custom sky** replacing the procedural `PhysicalSkyMaterial`
  (research/Terrain3D docs call the procedural sky "sub par"; recommend
  whites-balanced lighting). Keep ACES or move to **AgX**, White 6.0–8.0.
- **Wear decals** — the highest-value missing system: Godot `Decal` with
  `albedo_mix = 0` writes normal/ORM only, giving a **rubbered-in racing line
  with no colour change**. Forward+ only → gate per quality preset.
  Add corner-exit rubber, oil patches, dirt spill-off into traps.
- ⚠️ Research traps: Godot's **auto-exposure, SSAO/SSIL/SDFGI are
  Forward+-only** — gate them per preset in `scripts/ui/settings_menu.gd`;
  do not enable unconditionally.
- Raise `directional_shadow_max_distance` beyond 140 m if perf allows, else
  mask the hand-off with fog.

## 5. Phasing

- **P0 — Baseline audit:** what Terrain3D autoshader / macro variation /
  splat state Le Mans actually runs today (the research doc's named gap),
  plus a before-capture set (S/F, Tertre Rouge, Mulsanne, Indianapolis
  /Arnage, Porsche Curves, Ford Chicane) for later comparison.
- **P1 — Cheapest real wins (research-ranked):** WS-B macro variation +
  autoshader texture sets, WS-F wear decals, WS-F HDRI/aerial perspective.
  These three need no new geometry and move the look the most per hour.
- **P2 — WS-A sand/gravel/run-off (+ SurfaceRegistry grip):** biggest
  geometry-side realism win.
- **P3 — WS-C barriers (MultiMesh, alpha-scissor fence) + WS-D clutter:**
  pure `LeMansDressing` growth on the existing kind pipeline.
- **P4 — WS-E horizon + foliage density + perf pass:** impostor ring,
  silhouettes, full-scene perf-gate check on target hardware, vision critique.

## 6. Gates & verification

- `tests/suites/test_le_mans_track.gd` — extend: new kind counts > 0,
  sand zones at expected chainages, full-lap armco coverage assertion,
  determinism (rebuild → identical transforms).
- New `test_le_mans_surface_registry` case: sand zone → grip factor < asphalt.
- Visual verification: headless capture of S/F, Dunlop, Mulsanne, Ford
  chicane → vision critique done by Claude opening the captures directly (no Ollama/Gemini — see CLAUDE.md).
- Perf: run the touched suites via `tools\gdunit_parallel.py -j 4` (gate
  rules in `docs/GDUNIT_GATE.md`); no new per-frame allocations in
  `_process` paths.

## 7. Constraints / honesty

- Keep the v1 **no-trademark** stance: unbranded ad boards and banners.
- OdbL/OSM attribution already handled in v1 plan stays in force.
- All placement stays deterministic (seeded, chainage-math based) so tests
  can assert exact counts/positions.
- New visuals must degrade cleanly through the quality ladder
  (Low/Medium/High) — no High-only geometry.
- **Forward+ only features** (auto-exposure, SSAO/SSIL/SDFGI, wear `Decal`s)
  must be gated per preset in `scripts/ui/settings_menu.gd`, never enabled
  unconditionally — on lower presets the look must still read, just less rich.
- **Do not promise scan fidelity.** GT7's output is a survey pipeline; ours is
  procedural material/decoration work. Say so in PR/commit notes.
- One Godot process at a time; gate runs go through the background gate
  sub-agent, per AGENTS.md.

## 8. Implementation status (2026-10-21, uncommitted working tree)

Honest framing first: this is procedural material + decoration work on the
flat v1 scene, **not** scan fidelity. The trees are stylised low-poly canopy
lobes, the buildings are plain massing, there is no HDRI. It reads as a wooded,
armco-lined endurance circuit with sand traps, rubber and haze; it does not
read as GT7.

Files: `scripts/track/le_mans_dressing.gd` (rewritten around the v1 API),
`scripts/track/le_mans.gd` (ground/skirt/verge/asphalt), new
`scripts/track/le_mans_surfaces.gd` (shared materials/noise), new shaders
`shaders/le_mans_ground_inc.gdshaderinc`, `le_mans_ground.gdshader`,
`le_mans_gravel.gdshader`, `le_mans_asphalt.gdshader`, `le_mans_sky.gdshader`,
`scenes/track/le_mans.tscn` (sky + fog), `scripts/vehicle/surface_registry.gd`
(SAND + zone registry), `scripts/ui/settings_menu.gd` (decal gate),
`tests/suites/test_le_mans_track.gd`, `tools/le_mans_visual_capture.gd`.

| WS | Status | What shipped (counts from a live scene build) | Not done / caveats |
|---|---|---|---|
| A traps + run-off | **SHIPPED** | Sand traps at Tertre Rouge, Mulsanne, Indianapolis, Arnage, Ford (outside of the turn, ±55 m, 8 m wide at the centre, tapered): ribbon meshes with a ragged edge + a fringe row that blends into the *same* world-space grass the plain draws; pebble normal map. Paved aprons (2.6 m) between road and sand. 12 Ford-chicane sausage kerbs. 5 SAND + 5 ASPHALT polygons registered in `SurfaceRegistry` while the dressing is in the tree (cleared on `_exit_tree`, never registered by off-tree probes); the car's `build_classifier` resolves the zone first → SAND grip 0.82 lat / 0.76 long. | Ground was the flat v1 plain at the time of this pass (no 2–4° outward slope); 2026-10-22 it became the real-elevation `LeMansTerrain` (§9), but traps still sit on the cross-level corridor shelf, so there is still no outward slope, and the 0.40 m road-edge step remains. Only the Mulsanne *corner* gets a trap, not separate Mulsanne braking-zone run-offs. `clear_zones()` is global (only Le Mans uses zones). |
| B ground/grass | **SHIPPED (adapted)** | No Terrain3D in this scene, so macro variation = `le_mans_ground.gdshader`: one seamless noise tile sampled at ~770 m / 110 m / 9 m / 1.4 m, lush / dry / damp blend; shared by plain, skirt and a new **verge wear band** (worn earth at the edge, wider + heavier through corner complexes, torn outer edge). Asphalt: `le_mans_asphalt.gdshader` on a UV'd copy of the road's visual mesh — resurfacing sections, macro tone, aggregate normal, dusty edges, sparse crack sealant, painted white edge lines (TrackBuilder's 1 m red/white ARTERIAL strips hidden), curvature-derived rubbered racing line. | No slope/height texture selection (flat ground). Paint Wetness not done (optional). Existing `Foliage` node (700 grass / 60 trees) unchanged. |
| C barriers | **SHIPPED** | Full-lap armco both sides: 5,441 W-beam segments, measured coverage 0.991 / 0.993 of 25 m samples, gaps at marshal posts, pushed out behind every trap. 514 chain-link catch-fence panels (alpha scissor + alpha-to-coverage, mip-faded, 320 m visibility range) at corner complexes + S/F. 768 tyre-wall tyres (8 zones, painted marker tyres) + 64 blue/white panels. | Visual only (no colliders), as v1 §8.3(f). |
| D clutter | **SHIPPED** | 319 unbranded hoardings (5 colour sets, greyscale pattern, no text), 15 countdown boards (no numerals), 4 TV towers, 9 marshal posts (orange flag panel), 60 service-track slabs, S/F grandstand modules (8) + pit building (10 modules). | No equipment boxes. Did not route through `PropScatterer`/`RegionDresser` (no region dresser in this scene; kept self-contained + deterministic instead). |
| E horizon | **SHIPPED (stylised)** | Near forest edge 2,736 canopy clumps (24–44 m, field openings preserved), forest mass 2,431 big clumps (~50 m), far canopy ring 1,335 clumps (300–1,100 m, unshadowed), 4 landmark silhouettes (works + chimney, church + spire, hangar, walls) 340–700 m out; all cleared from every part of the circuit and kept on the ground plane. | Low-poly blobs with a leaf-noise albedo, not impostor/photo trees (repo has one CC0 tree GLB). |
| F atmosphere + wear | **SHIPPED / PARTIAL** | Custom sky shader with a cumulus layer replaces PhysicalSkyMaterial; fog density 0.0011, sun scatter 0.18, aerial perspective 0.7. 24 wear decals (S/F launch rubber, braking + exit rubber at every ≥40° corner, oil patches, dirt spill from each trap) with generated textures, projected only on render layer 11 (road/verge/ground/traps, never cars), distance-faded, hidden on Low by `settings_menu.gd` `decals_enabled`. | **No HDRI** (none in repo; custom sky instead). Tonemap and shadow distance are owned by the quality preset (`apply_quality_preset` rewrites them every scene load), so AgX / >140 m shadows were not changed here; the haze masks the shadow hand-off. |

Everything instanced is MultiMesh, chunked into 400 m cells with per-kind
visibility ranges; no `_process` code was added.

**Gates (§6):** `tests/suites/test_le_mans_track.gd` 13/13 green — new kind
counts, sand zones at the trap chainages classify SAND (and the car's own
classifier reports sub-asphalt grip), apron ASPHALT, carriageway never in a
zone, zone lifecycle, full-lap armco coverage > 0.95 per side, armco behind
traps, determinism (rebuild → identical transforms, decals included), asphalt
shader/racing line/up-facing faces, shared ground shader, decal textures +
layer + Low/Medium/High gating, registry-level sand < asphalt. Full parallel
gate: baseline before this pass `1407 cases | 0 errors | 2 failures`
(`test_barcelona_rx_barriers::test_pusher_cannot_cross_the_barrier`,
`test_post_race_cinematic::test_cinematic_retires_gameplay_rigs`); after
`1410 cases | 0 errors | 1 failure` (the same pre-existing post-race cinematic
case; the barcelona one is intermittent). `test_perf_gate` green,
`mode=reference control_ms=6.90`.

**Perf (Le Mans itself, capture camera, 1080p, GTX 970,
`tools/le_mans_visual_capture.gd` PERF lines):** Medium before 8.6–8.9 ms/frame
(0.23–0.47 M prims, 81–122 draws) → after 9.8–11.9 ms (0.28–0.88 M prims,
46–216 draws). Low after 5.7–6.5 ms; High after 8.6–9.6 ms (one 15 ms SDFGI
settle outlier). Scene build ~1.5 s, dressing build ~0.27 s standalone.

**Bugs found on the way:** (1) TrackBuilder's road strip winds its triangles
so the visible top is a back face; with `CULL_DISABLED` Godot flips the normal
down and the asphalt renders near-black under the sun (visible in every
"before" capture). Le Mans now draws its own up-facing visual strip; the shared
`track_builder.gd` is untouched (other tracks may still show this). (2) The
earlier capture harness teleported the player RigidBody and every PNG actually
showed the S/F line — likely why a previous ground-shader attempt looked like
an "empty world". The harness now uses its own camera.

Captures (12 views: sf, dunlop, tertre_rouge, hunaudieres, mulsanne,
indianapolis, arnage, porsche_curves, ford_chicane + close-ups tertre_trap,
arnage_brake, ford_kerbs): `.vision/captures/lemans_before_*.png` (this pass's
starting point, 9 views) vs `lemans_final_*.png` (Medium), `lemans_low_*`,
`lemans_high_*`; intermediate iterations `lemans_a1..a5_*`.

**Visual critique — done by Claude reading the PNGs directly (no
Ollama/Gemini).** Before: near-black asphalt (back-face bug), 1 m red edge
strip, flat mottled grass to the horizon, 22 m-tall black slabs standing in
for a tree line, flat dark boxes as hedges, armco only at corners, flat
procedural sky with no clouds — a "video game" read on all five research
tells. Fixed across five capture/critique iterations: armco segments gapped
and overlapped (stations snapped to centerline points → now interpolated);
contour-map-like crack lines (now sparse); a flat forest sheet read as a
painted wall and rendered black from behind (replaced by instanced canopy
mass); flat-shaded canopy facets (leaf-noise albedo); hoardings with no
pattern; empty S/F straight (grandstands + pit building added). After: a
grey asphalt with white edge lines and visible braking rubber, sand traps
with tyre walls and blue/white panels, continuous W-beam armco, wooded
Hunaudières/Mulsanne/Porsche sections, cloud sky and aerial haze. Low drops
the decals and still reads; High adds volumetric haze. **Still clearly short
of GT7:** stylised blob trees with visible trunk stubs, plain-massing
buildings (pit facade reads dark in shade), no elevation (Dunlop climb
absent -- fixed 2026-10-22, §9), near grass blurs at grazing angles with no blade detail, no crowd /
flags / pit-lane furniture, hoardings repeat.

## 9. Real elevation (2026-10-22, uncommitted)

The circuit is no longer flat. 36.8 m of real relief (world Y -14.3 .. +22.4 m
about the smoothed S/F datum, ~60 m ASL), max grade 4.6 % (Dunlop climb, ch 607).
Source: NASA SRTM GL1 30 m (public domain) via OpenTopoData, sampled every <= 50 m
along the same OSM trace, cross-checked against EU-DEM v1.1 (max |difference| along the lap 5.0 m);
baked offline by `tools/le_mans_fetch_elevation.py` into
`scripts/track/le_mans_elevation_data.gd` (profile + 100 m grid). Honest limits: SRTM is
a surface model and the trace is +-10-30 m off the real road, so the profile is
smoothed (3 box passes of +-60 m): it keeps the shape (Dunlop climb, Esses and Tertre
Rouge drop, Hunaudieres undulation, Indianapolis descent, Maison Blanche low,
climb back to the pit straight) but not every real crest or bump.

| Where (chainage) | Profile (m about S/F) | Grade |
|---|---|---|
| S/F -> Dunlop bridge (0 -> 869) | 0 -> +22.4 | up to +4.6 % (Dunlop climb) |
| Esses / Tertre Rouge (869 -> 1790 -> 2500) | +22.4 -> +8.1 -> -2.9 | -2 % to -4.3 % |
| Hunaudieres (2500 -> 5000) | -2.9 -> -7.2 -> -2.0 | |
| Mulsanne (5000 -> 8500) | -2.0 -> +11 (plateau) | +2.9 % |
| Indianapolis descent (8500 -> 9150) | +10.9 -> 0.0 | -2.3 % |
| Arnage -> Porsche -> Maison Blanche (9570 -> 12250) | -3.2 -> -14.3 (lap low) | |
| Ford -> S/F (12250 -> 13626) | -14.3 -> 0 | up to +2.5 % |

Pieces (all Le Mans-owned; `track_builder.gd` untouched):
- `LeMansLayout`: `_build_elevation`, `build_elevation_profile`, `elevation_at_arc`,
  `elevation_datum_asl`, `ground_y_at_arc`; `_make_y` adds the profile to `ROAD_BASE_Y` + bank
  lift, so the road mesh, collider, checkpoints, grid and spawn all follow it.
- `LeMansTerrain` (new): one 16 m height field = SRTM far field blended to the
  road-ground profile (flat 30 m, smoothstep to 120 m). The same array makes the
  512 m visual tiles, the per-tile trimesh colliders and `height_at()`.
  Replaces the flat PlaneMesh (`le_mans.gd::_build_ground`); bake ~1-2 s once per process.
- Verge, skirt (now buried 0.3 m below the terrain foot), foliage provider and the
  dressing all read `terrain_height()`; the dressing asks at each prop's own XZ,
  pitches long props with the grade, and sinks trees/buildings (0.4 / 0.5 m).

Verification (2026-10-22):
- Suites: `test_le_mans_layout` 15/15 and `test_le_mans_track` 14/14 (3 elevation
  layout cases; terrain-vs-road, skirt and dressing-on-ground cases in the track suite).
  Full parallel gate: 1430 cases | 0 errors | 1 failure (the pre-existing
  `test_post_race_cinematic::test_cinematic_retires_gameplay_rigs`);
  `test_perf_gate` green (`mode=reference control_ms=6.90`).
- Captures (`.vision/captures/lemans_elev3_*`, Medium, read by Claude, no Ollama/Gemini):
  `dunlop_climb`, `dunlop`, `esses_descent`, `tertre_rouge`, `mulsanne`, `indy_descent`,
  `porsche_rise`, `aerial_dunlop` and the rest of the 17 views. No floating or sunk
  props, road/verge/armco/hoardings/sand trap sit on the terrain, the aerial view shows the
  rolling landscape. Honest read: at <= 4.6 % grade and a 70 deg FOV the climb reads
  subtly from the driver's eye; it is clearest in the aerial view and in the car's pitch/height.
- Drive probes (headless, throwaway scripts): `AIController` laps the Dunlop climb
  (Y 4 -> 22 m, stays on the road, < 1.5 m lateral), cars that leave the road land on the
  terrain trimesh and never fall through (1.8 km cross-country); a down-ray at every one
  of 4,800 stations x 5 lateral offsets hits the road collider at the road height. One
  headless AI run at 63 m/s hit something near idx 1442 (ch ~4100) and stalled;
  re-runs with a 53-63 m/s teleported start did not reproduce it (no static collider found
  by 7 x 2 horizontal rays over idx 1380-1500), so it was not attributed.
- Perf (Le Mans, capture camera, 1080p, GTX 970, Medium): 10.4-12.1 ms avg
  (0.31-1.03 M prims, 57-309 draws) vs 9.8-11.9 ms after the realism pass and 8.6-8.9 ms
  originally, i.e. elevation itself costs about +0.5 ms; total vs the flat v1 +1.5-3.4 ms.
  The terrain is 168 tiles (12 x 14 of 512 m); no `_process` work.

Not done / unverified: Low and High preset recaptures after elevation (only Medium
was recaptured); no windowed AI race on a full lap (probes were headless, ~5 km of the
lap); no race-menu preview screenshot (the layout JSON is 2-D and unchanged; its suite
is green in the gate); chase/hood/cockpit cameras follow the car's transform and were not
captured on a climb; the 2-4 degree outward slope of WS-A traps is still absent.
