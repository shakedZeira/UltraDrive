---
name: car-exterior-design
description: "Use when creating or redesigning a car's exterior model for UltraDrive (Blender -> GLB -> Godot): building a body from reference photos, wheels that fill the arches, lights/glass/materials, the node and material contracts the game and tests depend on, triangle budget, export, the test suites, and the in-game capture/critique loop. Worked example: Nissan GT-R R35 2017 (tools/blender/r35/)."
---

# Car exterior design (UltraDrive, Godot 4.7.2, Blender 4.5)

The R35 (`assets/cars/nissan_gt-r_r35_2017.glb`, ~97k tris) is the worked
example. Pass 1 built it from references; pass 2 added wheels filling the arches,
shoulder line, fender peaks, shut lines, deep grille, angular mirrors and smaller
wing end plates. Interior/cockpit work is the sibling skill `car-interior-design`
— the exterior and the cabin share ONE eye coordinate (see "Cabin coupling").

## Rules that apply to every step

- **Analyse images yourself** (open the PNG with Read). Never Ollama / Gemini /
  `tools\ollama_vision.py` / `analyze_image` (user directive). Put this in every
  sub-agent prompt that does visual checks.
- `graphify query "<question>"` before grepping code; `graphify update .` after.
- One Godot process at a time: `mkdir D:/Temp/claude/d--AI-Projects-UltraDrive/godot.lock`
  before any Godot run, `rm -rf` it right after; shell-side `timeout` on every
  run. Engine: `D:\Godot\Godot_v4.7.2-stable_win64_console.exe` (console twin,
  never the GUI exe). Gate rules: `docs/GDUNIT_GATE.md`.
- Blender: headless `"D:/Blender 4.5/blender-4.5.13-windows-x64/blender.exe"
  --background --factory-startup --python x.py -- args`, or the live session via
  `py tools\blender_exec.py x.py`. Never `read_factory_settings`/`read_homefile`
  in the live session (it unloads the MCP add-on).
- Don't commit unless asked.

## 1. Pipeline

Source of truth = the scripts in `tools/blender/r35/` (copy the folder for a new
car; the car GLB re-exports **byte-identical** from them, verified):

| Script | Role |
|---|---|
| `r35_common.py` | helpers: lofted sections, boxes, bevels, materials, `obj()` |
| `r35_body.py` | the paint body: loft of cross-sections, arches, shoulder/fender shape |
| `r35_details.py` | grille, lamps, vents, mirrors, wing, diffuser, exhaust, shut-line grooves |
| `r35_wheels.py` | tyre, rim (Y-spokes, machined lip), disc, caliper |
| `r35_recess.py` | arch / wheel-well recess |
| `r35_build.py` | assemble + `render` / `ortho` / `export` / `save` modes |
| `r35_render.py` | studio render + ortho overlay for reference matching |
| `wheel_fit.py`, `gauge_tex.py` | cabin helpers (see interior skill) |

```
blender.exe --background --factory-startup --python tools/blender/r35/r35_build.py -- render side front34 rear34 front frontlow wheel
blender.exe --background --factory-startup --python tools/blender/r35/r35_build.py -- export assets/cars/<car>.glb
```

Renders land in `tools/blender/r35/renders/` (git-ignored PNGs). Workflow:

1. **References first.** `.vision/refs/<car>/` (NetCarShow `nc_*`, press kit,
   Wikimedia). Pick side, front, front-3/4, rear-3/4, wheel close-up. Fetch tools:
   `tools/fetch_r35_refs.py`, `_dl_nc*.py`. Downscale with `_downscale_refs.py`.
2. **Measure, don't eyeball.** Take length/width/height/wheelbase/track/wheel
   diameter from the spec sheet, set them as constants at the top of
   `r35_body.py`, then match silhouettes with `R.render_ortho_match` (ortho
   overlay vs the ref photo).
3. Build big forms first (body loft -> glass/greenhouse -> arches), then
   details (lamps, grille, mirrors, wing), then wheels. Re-render after each.
4. Compare `gtr_vN_*.png` with the ref at the SAME angle; list concrete gaps
   (see checklist) and fix the top three per iteration.

## 2. Contracts (tests pin these — do not break)

Coordinates in the GLB (glTF, +Y up): **nose = +Z**, left = +X (car-left),
ground y = 0.

- Wheel hubs are nodes `Wheel_FL/FR/RL/RR` with **identity rotation**
  (`apply_wheel_visuals` overwrites hub rotation) at the car's `CarConfig`
  geometry: R35 = x ±0.80, y 0.355 (tyre radius), z ±1.39. Children: `Tyre_*`,
  `Rim_*`, `BrakeDisc_*`; `Caliper_*` sits beside the hub (not spun).
- `Body` is the paint mesh, **surface 0 = CarPaint** (Bayside Blue embedded;
  the paint pipeline overrides surface 0, keeping blue > red). Clearcoat/metal
  values come from `CarVisuals.paint_profile_for(id)`, not the GLB.
- Glass material name contains `Glass`; meshes `Windscreen`, `Glass`,
  `GlassFastback`. Embedded glass is tinted **alpha-transparent** (alpha < 1,
  metallic 0, no refraction) — `test_r35_windshield_is_tinted_transparent_glass`.
- **Two** taillight materials/meshes (`Taillight_L`/`_R`, name contains
  `taillight`) so brake glow ramps all four lamps; reverse glow whitens them.
- Headlight material names contain `headlight`; trim `DarkTrim`/`Graphite`.
- `CarVisuals._material_cockpit_role` classifies by **material name**: glass ->
  see-through in cockpit view; paint/lights/trim/graphite/other -> hidden shell;
  tire/rim/brake/caliper -> stays visible. Name new materials so they land in the
  right bucket (`DarkTrim` contains `rim` — `trim` is tested first on purpose).
- Exterior cabin meshes `CabinTub`/`CabinSeats`/`CabinSteer` are hidden shell
  (cockpit uses the separate interior GLB); keep them out of the glass bucket.
- `config.visual_path`, class, engine/turbo keys live in
  `resources/cars/<id>.tres` + `scripts/vehicle/car_config.gd` — a new car needs a
  `.tres`, `Garage.STARTER_CARS`/price entry and its tests (copy `test_gtr_r35.gd`).

## 3. Triangle / material budget

- Target <= 150k tris for a hero car (R35 ~97k; check with `py -c` accessor
  count or `py tools\glb_inspect.py <glb>`). Wheels are ~35% of it — every
  spoke counts x4.
- ~28 materials max-ish; share across parts (`LampBezel`, `Chrome`, `RimLip`).
- `sharp=` angle on `obj()` shading: hard edges for panels, smooth for body loft.
- Do **not** bake lighting/AO into vertex colours; Godot lights it.

## 4. Gotchas (all hit during R35)

- **Translucent horizontal band ~20 deg below the horizon in cockpit captures** was
  NOT the R35 glass. The capture harness swapped config *before*
  `PlayerCarController._ready()`, so `_apply_visual()` errored on a null car and
  the garage save's active car GLB mounted under the R35 interior; its
  cockpit-transparent glass drew over the horizon. Fixed in
  `tools/r35_cockpit_capture.gd` (swap at frame 3, set `_car_id`). If a band
  reappears: capture with each of {glass, exterior} hidden (see
  `r35_band_*` captures) before touching geometry.
- Back-facing: windows lofted inside-out render invisible; check normals
  (`recalc_face_normals`) and `use_backface_culling` on glass.
- Z-fighting between body and trim: inset trim by >= 2 mm or give it its own
  surface; panel gaps are real grooves (0.004 m wide, 0.002 deep), not textures.
- Wheel fit: rim lip radius ~ arch radius - 0.045; tyre sidewall flush with the
  fender lip at +-0.80 (+-0.78 at the tread). Check front AND dead-on side.
- A long loft with too few sections shows a faceted shoulder; add sections near
  the fender peaks and the C-pillar.
- gltf export: `export_apply=True`, select only MESH/EMPTY (not the studio floor
  or lights/cameras), `export_yup=True`.
- Godot caches imports: after overwriting a GLB run
  `godot --headless --import .` (once) or captures show the old mesh.

## 5. Tests (run after any exterior change)

`test_gtr_r35` (config, forward/identity hubs, Bayside Blue paint, two
taillights, tinted glass, reverse glow), `test_car_paint_materials`,
`test_car_visuals`, `test_car_default_setup`, `test_starter_car_visual`,
`test_garage_brands`, `test_cockpit_visibility` (exterior hidden only in cockpit
view, wheels stay visible), `test_gtr_cockpit_resources`, plus `test_awd_drive`,
`test_car_reverse_lights`, `test_car_sound_profiles`, `test_exhaust_pops`,
`test_gtr_sound`, `test_turbo_boost` for anything keyed on the car id. Last
verified run (pass 2): 23 suites, **211 cases, 0 errors/failures/orphans**.

Run (cmd.exe semantics; see `docs/GDUNIT_GATE.md`): import probe first
`godot --headless --import .`, then
`godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -c -a res://tests/suites/<a>.gd -a res://tests/suites/<b>.gd`
with `APPDATA=<project>\reports\godot_userdata` set. Read the `Overall Summary`
line; filter logs on `SCRIPT ERROR` / `Parse Error` only.

## 6. Capture / critique loop

1. Studio renders: `r35_build.py -- render ...` -> `.vision/renders/` (copy the
   named views). Read each PNG and compare with the matching ref.
2. In-game: `tools/r35_exterior_capture.gd` (front 3/4, side, rear 3/4, chase
   height) -> `.vision/captures/r35_ext_*.png`; windowed run, **not** headless:
   `godot --path . -s res://tools/r35_exterior_capture.gd` (APPDATA set, timeout
   240, lock held). It will print a harmless-looking `_apply_visual` error if
   the swap runs too early — keep the frame-3 swap.
3. In-game lighting is darker/cooler than the studio render — judge colour and
   shape in-game, form in the studio.
4. Write down concrete deltas vs the reference, fix, repeat. Stop when
   silhouette, stance, wheels and lamp signature read as the real car from the
   chase camera (that is the angle the player sees 90% of the time).

## 7. Checklist

- [ ] Silhouette matches ref side + front (ortho overlay); wheelbase/track exact
- [ ] Stance: tyres fill arches, even gap, rim lip visible, calipers behind spokes
- [ ] Shoulder character line + fender peaks read in front 3/4
- [ ] Panel gaps: door, hood, trunk, fuel flap as grooves; deep dark grille
- [ ] Lamps: signature shape, bezel, DRL; two taillight materials; plate recess
- [ ] Mirrors angular on short stalks; wing end plates small; diffuser/exhausts
- [ ] Glass tinted-transparent; pillars shaped; no inside-out faces
- [ ] Contracts of section 2 intact; tris <= 150k; GLB re-imported
- [ ] Test list of section 5 green; in-game captures reviewed
- [ ] `graphify update .`
