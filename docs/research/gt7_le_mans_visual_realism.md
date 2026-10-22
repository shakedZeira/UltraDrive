# GT7 Le Mans Visual Realism — Research

Research for the UltraDrive (Godot 4.7.2) team on how Gran Turismo 7, Forza
Motorsport and Assetto Corsa achieve photoreal-looking Circuit de la Sarthe,
what the real circuit actually contains trackside, why our current track reads
as "video game", and what Godot 4.7 can actually do about it.

All claims below carry a source URL. Nothing is asserted without one.

---

## How GT7 achieves the look

**1. The circuit is physically surveyed, not modelled.**

Polyphony Digital's CEDEC 2022 talk describes a scan pipeline built on a
vehicle-mounted laser scanner that captures the road surface, the run-off
areas, the track furniture (barriers, marshal posts, signage) and nearby
buildings
(https://www.gtplanet.net/pd-circuit-scanning-creation-techniques-20220831/).
Alongside the laser pass they drive the track at roughly 10 mph while recording
30 fps video, then run photogrammetry over that footage — one Spa-Francorchamps
pass produced about 8 TB of data
(https://www.gtplanet.net/pd-circuit-scanning-creation-techniques-20220831/).
Bright and reflective surfaces (sky, glass buildings) and moving objects are
masked out before reconstruction, and a UAV drone survey covers the paddock and
off-track areas, supplemented by ground-level and helicopter stills
(https://www.gtplanet.net/pd-circuit-scanning-creation-techniques-20220831/).
GPS ties the captures together into a 3D mesh, and the image data is kept as
texture — which is how tire marks, oil stains and graffiti survive into the
shipped asset
(https://www.gtplanet.net/pd-circuit-scanning-creation-techniques-20220831/).
The result earned FIA certification
(https://www.gtplanet.net/pd-circuit-scanning-creation-techniques-20220831/).

For *fictional* circuits the same discipline is applied to a real place: the
team visits the region (Kyoto's Kitayama cedars are the cited example), and
extra buildings are placed according to local planning regulations
(https://www.gtplanet.net/pd-circuit-scanning-creation-techniques-20220831/).

**2. Procedural generation fills in the mass of detail.**

A 2023 GTPlanet write-up on Polyphony's Houdini work describes procedural
generation used for landscapes, roads and buildings, with Houdini automating
road junctions, non-destructive polygon reduction of distant mountains, and a
USD/Solaris-based look-dev workflow; "metadata" attached to the generated
geometry is what drives the real-time lighting engine
(https://www.gtplanet.net/gt7-procedural-generation-houdini-20230727/).

**3. The sky and lighting are simulated, not painted.**

Polyphony's SIGGRAPH 2023 talk "Rendering Technologies behind Gran Turismo 7:
VR, Ray Tracing and Sky Simulation" covers ray tracing and a simulated sky
model
(https://s3.amazonaws.com/gran-turismo.com/pdi_publications/SIGGRAPH2023_RenderingTechBehindGT7.pdf);
a contemporaneous summary of the slides is at
https://www.resetera.com/threads/rendering-technologies-behind-gran-turismo-7-vr-ray-tracing-and-sky-simulation-siggraph-2023-slides-pdf.756907/.
GT7 ships 580 cars across 42 track environments / 122 layouts as of v1.72
(https://gran-turismo.fandom.com/wiki/Gran_Turismo_7).

**4. Photos are real places.**

Gran Turismo's Scapes mode is roughly 3,000 photographed real-world locations
with the car composited in
(https://www.thedrive.com/features/i-recreated-gran-turismo-photos-in-real-life-and-cant-tell-the-difference).

**Forza does the same thing with the same tools.** Turn 10's GDC presentation on
Forza Motorsport 7 describes laser scanning and photogrammetry used to hit a 1:1
likeness including light direction and tree positions, with 8 days of photo
capture in the UAE and 2–3 on-site laser scanners at 6 mm accuracy
(https://www.gtplanet.net/how-forza-motorsport-7-uses-laser-scanning-and-photogrammetry-to-create-realistic-environments/).
The current Forza Motorsport marketing confirms the same pillars: laser scanning
plus photogrammetry, real-time ray tracing, global illumination, PBR lighting,
tens of thousands of animated 3D spectators, and paints sourced with a
spectrophotometer (https://forza.net/motorsport). Its track list includes
"Le Mans — Circuit International de la Sarthe" with dynamic time of day and
weather, living crowds, rubbering-in and temperature-reactive track surfaces
(https://forza.net/news/forza-motorsport-track-list).

**Assetto Corsa's Le Mans is not an official track.** The Circuit de la Sarthe
content for AC is a community mod (commonly credited to Tiago Lima, Jim Lloyd
and Terra21 as "Circuit 24H Lemans")
(https://www.assettoworld.com/track/circuit-de-la-sarthe-le-mans,
https://www.overtake.gg/downloads/circuit-24h-lemans.6070/). Worth stating
plainly: the third reference in the brief is fan-made, and its fidelity comes
from the same source materials (photos, survey references, hand modelling)
plus high-resolution textures, not from a factory scan pipeline.

---

## Real Circuit de la Sarthe trackside inventory

Facts about the actual venue, because "photoreal" means matching these:

- Circuit de la Sarthe is a **semi-permanent** circuit of **13.626 km with 38
  turns**, using the **D338 public road** for the Mulsanne straight section
  (https://en.wikipedia.org/wiki/Circuit_de_la_Sarthe).
- **Armco barriers** were introduced in **1969**
  (https://en.wikipedia.org/wiki/Circuit_de_la_Sarthe).
- **Tyre barriers** stand at the Tertre Rouge exit after the **2013** reprofile
  of that corner (https://en.wikipedia.org/wiki/Circuit_de_la_Sarthe).
- **Dunlop** run-off was reprofiled in **2006**; the **Ford chicane** dates from
  **1968**; the **Mulsanne chicanes** were added in **1990** to satisfy the FIA's
  2 km straight limit (https://en.wikipedia.org/wiki/Circuit_de_la_Sarthe).
- The **Dunlop Bridge** is the signature landmark, with Goodyear branding
  arriving in **2026** (https://en.wikipedia.org/wiki/Circuit_de_la_Sarthe).
- Up to **85% of a lap is at full throttle**
  (https://en.wikipedia.org/wiki/Circuit_de_la_Sarthe).
- In GT7 the layout is 5 layouts/2 layouts depending on source; GT7's track page
  lists Le Mans with **2 layouts, 5 events, a 5,700 m longest straight, a 24-hour
  time cycle with rain, 55 m altitude**, and a "No Chicane" layout of **32
  corners** (https://www.gtplus.app/gt7/tracks/circuit-de-la-sarthe).
- Trackside furniture as documented by circuit guides: **gravel traps and
  sausage kerbs** at the Ford Chicane, and **walls** through the Porsche Curves
  (https://lemansultimate.wiki/track-guide/le-mans). General layout notes are at
  https://www.racetrackdesigner.com/tracks/le-mans.html and
  https://thefour11.net/topics/wec/le-mans-2026/circuit. Grandstand and public
  area inventory is described at
  https://www.24h-lemans.com/en/spectators/grandstands and
  https://www.24h-lemans.com/en/spectators/spectator-area.

The inventory that matters for a game: **Armco + tyre stacks + concrete walls of
several vintages, catch fencing, marshal posts, advertising hoardings, the
Dunlop Bridge, grandstands, forest on both sides of the Mulsanne, gravel traps,
sausage kerbs, and long runs of public-road-spec asphalt.**

---

## Why our track reads as "video game"

Those are aesthetic judgements, so they are stated as ours, with the concrete
cause named for each — the point is that every one has a documented fix.

- **Uniform surfaces.** A single tiling albedo with no macro variation reads as
  a repeating texture, not a road. Terrain3D's own shader documentation treats
  macro variation as a standard, separate multiply applied on top of the painted
  albedo (https://terrain3d.readthedocs.io/en/latest/docs/shader_design.html) —
  meaning we are missing a step the tool expects us to take.
- **No wear decals.** GT7 keeps tire marks and oil stains because they are baked
  into the photogrammetry texture
  (https://www.gtplanet.net/pd-circuit-scanning-creation-techniques-20220831/).
  We have no equivalent layer at all.
- **Thin trackside.** Real Le Mans is dense with Armco, tyre stacks, fencing,
  posts and hoardings (https://en.wikipedia.org/wiki/Circuit_de_la_Sarthe). Our
  prop scatter currently places guardrails, tents, power poles and rocks
  (`scripts/world/prop_scatterer.gd`) — correct in kind, sparse in density.
- **Procedural-looking horizon.** Distant mountains that are visible as raw
  mesh read as geometry. Polyphony explicitly performs non-destructive polygon
  reduction on distant mountains
  (https://www.gtplanet.net/gt7-procedural-generation-houdini-20230727/), and
  Forza/GT both lean on real terrain shape. Our horizon comes from
  `terrain_baker.gd`'s procedural fBm plus an alpine dome — plausible in shape,
  but with no atmospheric separation.
- **Flat atmosphere.** With no aerial perspective, sunlight on a distant object
  matches a near object, which is the single strongest "game" cue. Godot ships
  the fix: depth fog with **Sun Scatter** and **Aerial Perspective**, enabled by
  default in the depth-fog options
  (https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html).
- **Default sky, default tonemap.** Godot's built-in procedural sky is documented
  by Terrain3D as "sub par" next to an HDRI or a custom sky shader
  (https://terrain3d.readthedocs.io/en/latest/docs/environment.html), and Godot's
  own environment docs recommend **ACES or AgX tonemapping with White set to
  roughly 6.0–8.0** for photoreal output
  (https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html).
  We ship the quality ladder in `scripts/ui/settings_menu.gd`, so this is a
  preset-value question, not an architecture question.
- **One material for grass.** Terrain3D supports 32 texture sets, each
  channel-packed as albedo+height and normal+AO+roughness
  (https://terrain3d.readthedocs.io/en/latest/docs/texture_prep.html), plus an
  autoshader that picks a texture set by **normal and height**
  (https://terrain3d.readthedocs.io/en/latest/docs/shader_design.html). One
  grass material across sand, gravel and run-off is a content gap, not an engine
  limit.
- **Crowd and world are static.** Forza's marketing makes animated 3D spectators
  and "living crowds" an explicit feature
  (https://forza.net/motorsport, https://forza.net/news/forza-motorsport-track-list).
  We have no spectator population.

---

## Godot 4 implementation techniques

Ordered by cost-to-benefit. Everything here maps onto systems UltraDrive already
owns.

### Terrain, sand, grass

- **Use more than one texture set, and let the autoshader choose.** Terrain3D
  ships an autoshader that selects a texture set from the surface **normal and
  height**, with height-based blending between sets
  (https://terrain3d.readthedocs.io/en/latest/docs/shader_design.html). Define
  separate sets for asphalt, sand/gravel run-off, dry grass and forest floor
  rather than one grass texture everywhere. The kit supports **32 texture sets**
  (https://terrain3d.readthedocs.io/en/latest/docs/texture_prep.html).
- **Add macro variation.** The same shader doc describes macro variation as a
  large-scale pattern multiplied onto albedo specifically to break up tiling
  (https://terrain3d.readthedocs.io/en/latest/docs/shader_design.html). This is
  the cheapest single fix for the uniform-surface problem.
- **Channel-pack and compress.** Albedo+height in one texture, normal+AO+
  roughness in another, with mipmaps and VRAM compression required for the
  pipeline to behave (https://terrain3d.readthedocs.io/en/latest/docs/texture_prep.html).
  Performance guidance puts mipmaps and compression first, ahead of every other
  terrain optimisation (https://terrain3d.readthedocs.io/en/latest/docs/performance.html).
- **Paint wear and wetness into the control map.** The texture-painting doc
  documents Paint/Spray tools, a Paint Color operation that multiplies albedo,
  and a Paint Wetness operation that edits roughness
  (https://terrain3d.readthedocs.io/en/latest/docs/texture_painting.html). A
  painted darkening down the racing line plus a slightly wetter (rougher) band
  near the shoulder is a direct stand-in for GT7's baked-in road staining
  (https://www.gtplanet.net/pd-circuit-scanning-creation-techniques-20220831/).
- **Derive normals from the heightmap, not from extra mesh.** Terrain3D computes
  normals from heightmap derivatives via `texelFetch`
  (https://terrain3d.readthedocs.io/en/latest/docs/shader_design.html), so
  baking real camber and kerb-height variation into the height channel costs no
  extra geometry. Our pipeline already bakes through `terrain_baker.gd` /
  `terrain_seeder.gd`.
- **Match receded road beds carefully.** Our roads are recessed into a washbed
  with shoulder and blend distances; the terrain texture sets must change at the
  same boundaries or the sand/grass will bleed onto the racing surface.

### Barriers, rails, catch fencing

- **Instance, don't node.** Terrain3D's instancer is MultiMesh-based, one
  MultiMesh per 32×32 m cell, with LOD support, and it explicitly does **not**
  support individual culling or collision, so neutral transforms are required
  (https://terrain3d.readthedocs.io/en/latest/docs/instancer.html). For long
  Armco runs this is the right mechanism — thousands of metres of barrier as
  a handful of instanced meshes.
- **Fence and catch-fence materials want alpha.** Godot's StandardMaterial3D has
  an **alpha-scissor** mode documented as the way to cut out foliage and fences
  (https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html),
  with proximity fade and distance fade (including dither modes) to avoid hard
  pop (same URL).
- **Every barrier needs a distance fade.** StandardMaterial3D documents
  distance-fade including dither modes specifically so thin geometry does not
  alias at range
  (https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html).
- **Vary the barrier types.** Real Le Mans has Armco from 1969, tyre barriers
  from the 2013 Tertre Rouge reprofile, and concrete walls in the Porsche Curves
  (https://en.wikipedia.org/wiki/Circuit_de_la_Sarthe,
  https://lemansultimate.wiki/track-guide/le-mans). Three visibly different
  materials in three places is what a scan-based game actually looks like.
- **Use back-lighting on thin geo.** StandardMaterial3D exposes **back lighting**
  for materials that are lit from behind
  (https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html)
  — appropriate for fencing and foliage clumps.

### Props

- **Density is the point, and our scatterer is the vehicle.** `PropScatterer`
  already builds runtime MultiMesh props (guardrail, tent, power pole, rock) from
  fused primitives, rejection-samples clear of roads via `is_on_road`, and is
  deterministic per seed (`scripts/world/prop_scatterer.gd`). Adding marshal
  posts, hoardings, tyre-stack clusters and signage families is a preset change
  on the `/self/` bridge presets, not new architecture.
- **Budget props per region, not globally.** `RegionDresser` already mirrors the
  terrain ring with spawn/free budgeting and per-band density
  (`scripts/world/region_dresser.gd`), and the seeder has a km→locs corridor
  budget ladder capped at 190 (`scripts/world/terrain_seeder.gd`). Trackside
  density should ride those existing ladders so it scales with distance.
- **Beware the summed-count trap.** Foliage and prop nodes own several MultiMesh
  children and `get_instance_count()` / `get_visible_instance_count()` **sum
  across all children** — a first-child read returns 700 instead of 740
  (project docs; `RegionDresser._apply_band_budget` builds `placed` from summed
  counts). Any new density assertions must use summed counts.

### Distance scenery

- **Reduce distant mountains non-destructively.** Polyphony does exactly this
  (https://www.gtplanet.net/gt7-procedural-generation-houdini-20230727/); in
  Godot the equivalent is baked LOD meshes for horizon geometry plus a
  low-frequency terrain far LOD, so silhouettes stay smooth instead of faceted.
- **Use `World Background` modes deliberately.** Terrain3D's performance doc
  treats the `World Background` setting as a first-class knob
  (https://terrain3d.readthedocs.io/en/latest/docs/performance.html); the
  horizon should be drawn cheaply and correctly, not as a fully shaded mesh.
- **Occlusion cull.** Occlusion culling is listed among Terrain3D's performance
  levers (https://terrain3d.readthedocs.io/en/latest/docs/performance.html) and
  pays for itself the moment the forest starts hiding distance.

### Lighting and atmosphere

- **Replace the procedural sky with an HDRI or custom sky.** Terrain3D's
  environment doc is explicit that HDRIs/custom sky over the built-in procedural
  sky are the quality option, and that lighting should be balanced
  whites-first (https://terrain3d.readthedocs.io/en/latest/docs/environment.html).
  Godot's environment doc covers ambient-light source (sky / IBL) and PBR
  ambient (https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html).
- **Set tonemapping for photoreal.** ACES or AgX with White 6.0–8.0 is Godot's
  own recommendation, and `CameraAttributesPhysical` is the recommended node for
  photorealism (https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html).
  Auto exposure is Forward+-only (same URL), so gate it in the quality ladder in
  `scripts/ui/settings_menu.gd` rather than assuming it everywhere.
- **Turn on depth fog with Sun Scatter and Aerial Perspective.** Both are
  default-enabled depth-fog options and both are what create the separation
  between near and far objects that our track currently lacks
  (https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html).
- **Use SSAO/SSIL/SDFGI where the preset allows.** They are Forward+-only
  (https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html);
  Forza markets global illumination and real-time ray tracing as core
  (https://forza.net/motorsport), so SDFGI is the nearest honest analogue and
  belongs on High only.
- **Add localised atmosphere with FogVolume, sparingly.** FogVolume requires
  `volumetric_fog_enabled`, the docs say to keep volumes small and simple, and
  warn that thin volumes flicker
  (https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html).
  Good for a low morning mist over the Mulsanne sand; bad as a blanket.
- **Colour-correct with a LUT and DOF.** Both are documented in the environment
  tutorial (https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html).

### Surface wear

- **Use Decals for tire marks, oil stains and rubber.** Godot's Decal is
  **clustered** and Forward+/Mobile only, has `cull_mask` to restrict which
  surfaces it lands on, supports distance fade, and `albedo_mix = 0` gives a
  decal that only writes normal/ORM — i.e. a purely wetness/roughness mark with
  no colour change (https://docs.godotengine.org/en/stable/classes/class_decal.html).
  That last mode is precisely a rubbered-in racing line.
- **Source placement deterministically.** GT7's stains survive because they were
  captured rather than authored
  (https://www.gtplanet.net/pd-circuit-scanning-creation-techniques-20220831/);
  the closest honest equivalent is to place wear decals procedurally along the
  same road polylines `RoadNetwork` already owns, seeded deterministically like
  `PropScatterer`.
- **Drift the wear with conditions.** Forza advertises rubbering-in and
  temperature-reactive surfaces as features
  (https://forza.net/news/forza-motorsport-track-list). Our
  `SurfaceRegistry` grip table (`scripts/vehicle/surface_registry.gd`) plus
  `weather_manager.gd` already carry the state; decal density/roughness is the
  visual channel for it.
- **Detail-texture the mid-field.** StandardMaterial3D's detail albedo/normal
  blend adds high-frequency texture at a second scale without a second model
  (https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html),
  and triplanar / world-triplanar mapping avoids UV stretching across track
  meshes (same URL).

---

## Sources

- Polyphony Digital CEDEC 2022 circuit-scanning pipeline — GTPlanet:
  https://www.gtplanet.net/pd-circuit-scanning-creation-techniques-20220831/
- Polyphony Digital procedural generation in Houdini — GTPlanet:
  https://www.gtplanet.net/gt7-procedural-generation-houdini-20230727/
- Turn 10 laser scanning and photogrammetry (Forza Motorsport 7, GDC) — GTPlanet:
  https://www.gtplanet.net/how-forza-motorsport-7-uses-laser-scanning-and-photogrammetry-to-create-realistic-environments/
- Forza Motorsport technology overview — official:
  https://forza.net/motorsport
- Forza Motorsport track list (includes Le Mans, dynamic time/weather) — official:
  https://forza.net/news/forza-motorsport-track-list
- "Rendering Technologies behind Gran Turismo 7: VR, Ray Tracing and Sky
  Simulation", SIGGRAPH 2023 — Polyphony Digital:
  https://s3.amazonaws.com/gran-turismo.com/pdi_publications/SIGGRAPH2023_RenderingTechBehindGT7.pdf
- SIGGRAPH 2023 slides summary — ResetEra:
  https://www.resetera.com/threads/rendering-technologies-behind-gran-turismo-7-vr-ray-tracing-and-sky-simulation-siggraph-2023-slides-pdf.756907/
- GT7 car/track counts (580 cars, 42 environments / 122 layouts) — Gran Turismo
  Wiki: https://gran-turismo.fandom.com/wiki/Gran_Turismo_7
- GT7 Circuit de la Sarthe track page (layouts, straight length, altitude,
  time cycle) — GTPlus: https://www.gtplus.app/gt7/tracks/circuit-de-la-sarthe
- Scapes = ~3,000 real photographed locations — The Drive:
  https://www.thedrive.com/features/i-recreated-gran-turismo-photos-in-real-life-and-cant-tell-the-difference
- Assetto Corsa Le Mans as a community mod — AssettoWorld:
  https://www.assettoworld.com/track/circuit-de-la-sarthe-le-mans
- Assetto Corsa "Circuit 24H Lemans" mod — Overtake.gg:
  https://www.overtake.gg/downloads/circuit-24h-lemans.6070/
- Circuit de la Sarthe (13.626 km, 38 turns, Armco 1969, tyre barriers 2013,
  Ford chicane 1968, Mulsanne chicanes 1990, 85% full throttle) — Wikipedia:
  https://en.wikipedia.org/wiki/Circuit_de_la_Sarthe
- Le Mans track guide (gravel and sausage kerbs at Ford Chicane, walls at Porsche
  Curves) — Le Mans Ultimate Wiki:
  https://lemansultimate.wiki/track-guide/le-mans
- Le Mans circuit layout notes — Racetrack Designer:
  https://www.racetrackdesigner.com/tracks/le-mans.html
- Le Mans 2026 circuit notes — The Four One One:
  https://thefour11.net/topics/wec/le-mans-2026/circuit
- Grandstands and spectator areas — official 24 Hours of Le Mans:
  https://www.24h-lemans.com/en/spectators/grandstands
  https://www.24h-lemans.com/en/spectators/spectator-area
- Environment and post-processing (tonemapping, ambient/IBL, fog with Sun
  Scatter and Aerial Perspective, SSAO/SSIL/SDFGI, glow, auto exposure, LUT,
  DOF, CameraAttributesPhysical) — Godot docs:
  https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html
- StandardMaterial3D (triplanar, detail blending, alpha-scissor, depth
  pre-pass, proximity/distance fade, height/parallax, bent normals, AO, ORM,
  back lighting) — Godot docs:
  https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html
- Decal (clustered, Forward+/Mobile, `cull_mask`, `albedo_mix`, distance fade) —
  Godot docs:
  https://docs.godotengine.org/en/stable/classes/class_decal.html
- FogVolume (localised volumetric fog, thin-volume flicker warning) — Godot
  docs: https://docs.godotengine.org/en/stable/classes/class_fogvolume.html
- MultiMeshInstance3D — Godot docs:
  https://docs.godotengine.org/en/stable/classes/class_multimeshinstance3d.html
- Terrain3D documentation index — Terrain3D:
  https://terrain3d.readthedocs.io/en/latest/
- Terrain3D shader design (autoshader by normal and height, index vs splat map,
  macro variation, height blending, normals from heightmap derivatives) —
  Terrain3D: https://terrain3d.readthedocs.io/en/latest/docs/shader_design.html
- Terrain3D texture painting (Paint/Spray, Paint Color multiplies albedo, Paint
  Wetness edits roughness) — Terrain3D:
  https://terrain3d.readthedocs.io/en/latest/docs/texture_painting.html
- Terrain3D texture prep (32 texture sets, channel packing, mipmaps + VRAM
  compression) — Terrain3D:
  https://terrain3d.readthedocs.io/en/latest/docs/texture_prep.html
- Terrain3D instancer (MultiMesh per 32×32 m cell, LOD, no per-instance culling
  or collision, neutral transforms) — Terrain3D:
  https://terrain3d.readthedocs.io/en/latest/docs/instancer.html
- Terrain3D environment (HDRI/custom sky over procedural sky, whites-balanced
  lighting, foliage shader tips) — Terrain3D:
  https://terrain3d.readthedocs.io/en/latest/docs/environment.html
- Terrain3D performance (mipmaps/compression first, region count, foliage LOD,
  occlusion culling, `World Background`, lightweight shader) — Terrain3D:
  https://terrain3d.readthedocs.io/en/latest/docs/performance.html
- UltraDrive internal: `scripts/world/prop_scatterer.gd`,
  `scripts/world/foliage.gd`, `scripts/world/terrain_seeder.gd`,
  `scripts/world/region_dresser.gd`, `scripts/world/terrain_baker.gd`,
  `scripts/ui/settings_menu.gd`, `scripts/vehicle/surface_registry.gd`
  (project sources, not external).
