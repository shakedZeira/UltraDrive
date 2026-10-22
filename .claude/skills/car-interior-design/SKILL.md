---
name: car-interior-design
description: "Use when creating or improving a car's first-person cockpit/interior for UltraDrive: driver eye height and position (CarConfig cockpit_seat_*), the authored cabin GLB (dash, A-pillars, headliner, doors, seats, mirror), gauge/screen textures, the Godot interior scene and CockpitRig contracts, sightline and visibility tests, and the in-game capture/critique loop. Worked example: Nissan GT-R R35 2017 (tools/blender/r35/r35_cabin.py)."
---

# Car interior / cockpit design (UltraDrive, Godot 4.7.2, Blender 4.5)

Companion to `car-exterior-design` (same rules block: Claude-only image
analysis, graphify first, godot.lock, Blender caveats — see there). The R35
cockpit = **cabin GLB** (static shell) + **scene primitives** (steering wheel,
gauges, needles, screens, console) driven by `CockpitRig`.

## 1. Layers and files

| Layer | File |
|---|---|
| Eye anchor per car | `resources/cars/<id>.tres`: `cockpit_seat_height / _forward / _lateral` (`CarConfig`) |
| Anchor math (single source) | `CockpitRig.seat_anchor_for(cfg, default_h, default_f)` -> `Vector3(height, forward, lateral)`; camera and rig both call it |
| Camera | `scripts/camera/cockpit_camera.gd` (near 0.2, FOV 60-68, rigid eye, look yaw/pitch) |
| Rig | `scripts/vehicle/cockpit_rig.gd` (loads `InteriorResource`, spins wheel, needles, shift light, MFD mode) |
| Interior scene | `scenes/vehicle/interiors/<car>_cockpit.tscn` — authored in **eye space** (eye = rig origin) |
| Cabin shell | `assets/interiors/<car>/<car>_cabin.glb` + `scripts/vehicle/cockpit_cabin_mesh.gd` (forces no-shadow) |
| Textures | `r35_tach_face / speedo_face / mfd_screen / climate_screen.png` made by `tools/blender/r35/gauge_tex.py <outdir>` |
| Blender source | `tools/blender/r35/r35_cabin.py`, `wheel_fit.py` (solves wheel+dial layout so dials show through the upper rim) |

```
blender.exe --background --factory-startup --python tools/blender/r35/r35_cabin.py -- render        # eye / left / right previews
blender.exe --background --factory-startup --python tools/blender/r35/r35_cabin.py -- export assets/interiors/r35/r35_cabin.glb
```

## 2. Eye position (decide this FIRST)

`cockpit_seat_*` are in **car space relative to the exterior GLB**:
height above the ground plane (y), forward = metres ahead of the car origin
(**negative = behind it**), lateral = car-local X (**negative = driver side**,
in this cabin the driver sits at x = -0.36).

R35 final: `height 1.08, forward -0.18, lateral -0.36` (was 0.62/0.55/-0.36,
which put the eye at ~0.45 m too low and ahead of the real driver). Real
sports-coupe eye height is roughly 1.05-1.15 m for a 1.37 m tall car; set it so
the **windscreen top header sits ~12-15 deg above the horizon** and the dash top
~12 deg below it. Eye is ~0.18 m aft of mid-wheelbase for a front-mid-engine GT.

`cockpit_seat_forward` historically only applied when `> 0`; `seat_anchor_for`
now applies it when `!= 0` (height still needs `> 0`, lateral `!= 0`). Changing
these constants means updating every test that pins them (user-approved for the
R35): `test_gtr_r35_interior` (`test_r35_config_carries_cockpit_seat_overrides`,
`test_cockpit_camera_and_rig_share_the_rhd_lateral_anchor`), plus
`test_cockpit_visibility`, `test_firstperson_look`, `test_cockpit_hud`.

## 3. Cabin GLB authoring (Blender)

The cabin is authored in **driver-eye space**: Blender X = eye-right (toward the
car centreline), Y = forward, Z = up, eye at the origin; glTF (+Y up) maps to
Godot eye space `x = X, y = Z, z = -Y`. Conversion from exterior coordinates
(`T()` in `r35_cabin.py`): `Xc = 0.36 - Xb, Yc = 0.18 - Yb, Zc = Zb - 1.08`.
So the cabin always agrees with the exterior body (A-pillar base under the
windscreen, doors at the door cut-outs, seat on the floor).

Pieces (node names matter for debugging): `CabShell{Lo,Mid}{D,P}{F,R}`/`CabShellHi`
(tub, pillars, headliner — lofted sections, not boxes), `CabDoorDrv/Pas`,
`CabDashTop/Face`, `CabBinnacle`, `CabGaugeTunnel`, `CabVent*`, `CabStack(+Panels)`,
`CabConsole`, `CabShifter`, `CabFloor`, `CabRear`, `CabRearMirror`, `CabVisors`,
`CabSeatDrvCushion/Back`, `CabSeatPas`.

Shaping rules that made it read as a car (vs a box):
- **A-pillars**: loft a thin section along the windscreen frame, thicker at the
  base, with the dash-to-glass joint hidden by a pillar trim.
- **Headliner**: slightly domed (sagitta ~1.5 cm per 10 cm), visible at the top of
  the view when looking right/up; roof-rail and rear-view-mirror stalk to the header.
- **Dash top** sweeps down to the binnacle; instrument cowl is a hood over the
  dials; vents are cylinders with ring bezels.
- Seats: lofted cushion + back with bolsters; the driver seat is split at the
  hip so the back can later recline.
- Materials: `CabHeadliner, CabBlack, CabTan, CabSoft, CabVent, CabAlloy,
  CabGloss, CabCarbon, CabCarpet, CabMirror`. Interiors are flat emissive-lit,
  so keep albedo values mid/dark and never rely on scene lights.
- Triangle budget: R35 cabin ~8.7k tris. Spend them on silhouettes near the
  eye (dash edge, pillar, wheel), not on the far rear.

## 4. Contracts (tests pin these)

- Interior scene root children incl. `Cabin/CabinMesh`, `SeatRoot`, `Dash`,
  `BinnacleHood/Back`, `GaugeRPM`, `GaugeSpeed`, `GaugeMFD`, `SteeringWheel`
  (+ `PaddleLeft/Right`, `Badge`), `CentreConsole`, `DoorCardRight`,
  `CentreStackRiser`, `NavScreen`. Names are looked up by `CockpitRig`.
- Needles (`GaugeRPM/Needle`, `GaugeSpeed/Needle`) rotate with a **clamped**
  sweep (the speedo/tach dials sweep ~86 deg because tests pin the sweep).
- Shift light switches on above 90% of redline.
- The interior is **light-free, shadowless, emissive** (flat materials with
  `emission` = albedo x ~0.15). No `Light3D`, no `cast_shadow` — `cockpit_cabin_mesh.gd`
  enforces it for the GLB.
- Sightline gate (`test_gtr_r35_sightline`): in eye space, **no mesh overlapping
  the forward wedge `|x| <= 0.3*(-z)` may have an AABB straddling y in
  (-0.05, +0.05)** — near-black geometry on the horizon reads as a "black
  windscreen". Cluster tops must sit below the horizon. The cabin builder uses
  `BAND = 0.051` for this. Tall pieces (mirror, visors, header) must be wholly
  above +0.05 or below -0.05.
- Visibility follows the camera: the rig is shown only in cockpit view and the
  exterior shell/dressing hides then (`CarVisuals.set_cockpit_view`); the wheel
  assembly stays visible.
- HUD: R35 hides the generic dash panel (`suppress_hud_dash`) and keeps the
  cluster dimmed; non-R35 cars keep it.
- `test_r35_cockpit_is_right_hand_drive` pins `DoorCardRight.x < 0` and the
  `CentreStackRiser.x > 0`; the shipped cabin is visually driver-left (the
  code naming says RHD). Known oddity — don't "fix" it without updating the
  tests and the capture sweep directions together.

## 5. Gotchas (all hit during R35)

- **Translucent band below the horizon**: not a glass bug — the capture harness
  swapped config before `PlayerCarController._ready()` so the garage save's car
  GLB ended up under the interior (see exterior skill, section 4). Capture with
  glass hidden / exterior hidden to localise before editing meshes.
- Camera near plane 0.2 m: anything closer than 20 cm to the eye is clipped
  (e.g. the steering-wheel rim top if the eye is too close). Keep wheel centre
  ~0.48 m ahead and 0.30 m below the eye.
- Dials use baked textures; needle and bezel are primitives so tests can read
  rotation — don't merge them into the GLB.
- `apply_look` yaw is unclamped: holding it for dozens of frames in a capture
  spins the view round onto your own seat back (looks like a huge brown wall).
  Keep sweeps ~20 frames; right = positive `apply_look` x, left = negative.
- The `_apply_visual` SCRIPT ERROR when the swap runs before ready is the
  symptom of the band bug; with the frame-3 swap it no longer prints.
- After overwriting a GLB run `godot --headless --import .` or captures show the
  old mesh.
- Orphan Godot windows from the capture tool: always use `timeout`.

## 6. Tests

Run with godot.lock held, `APPDATA` redirected (see `docs/GDUNIT_GATE.md`):
`test_gtr_r35_interior`, `test_gtr_r35_sightline`, `test_gtr_cockpit_resources`,
`test_cockpit_camera`, `test_cockpit_hud`, `test_cockpit_interior`,
`test_cockpit_visibility`, `test_firstperson_look`, `test_hood_camera`,
`test_chase_camera`, `test_camera_math`, plus the exterior list. Last verified
(pass 2, together with the exterior suites): 23 suites, **211 cases, 0
errors/failures/orphans**.

## 7. Capture / critique loop

`tools/r35_cockpit_capture.gd` (windowed, not headless; lock; `timeout 240`;
`APPDATA` set):
```
godot --path . -s res://tools/r35_cockpit_capture.gd
```
-> `.vision/captures/r35_cockpit_forward.png`, `..._binnacle_stack.png` (look
right: MFD/climate stack, headliner, mirror), `..._console.png` (look left: door,
mirror, B-pillar). Open each PNG with Read and judge against
`.vision/refs/r35/nc_12_*Interior*.jpg` and the other `File_*interior*.jpg`.
Critique list: horizon height vs dash (~45-55% of frame height), no translucent
band or black slab on the horizon, A-pillar angle/thickness, headliner visible
when looking up-right, wheel+dials unobstructed, screens legible, mirror size
sane (real mirror ~ 6 deg tall).
Blender previews (`r35_cabin.py -- render`) are only for form; in-game is truth.

Remaining known crudeness (pass 2): low-poly facets on the dash/door, flat-colour
leather (no stitching texture), oversized rear-view mirror, black steering wheel
(tests pin its material), `apply_look` has no yaw clamp.

## 8. Checklist

- [ ] Eye anchor decided from real car dims; `.tres` + tests updated together
- [ ] Cabin authored in eye space from the exterior numbers (`T()`)
- [ ] A-pillars/headliner/dash/door/seat/mirror shaped, no overlap with sightline band
- [ ] Interior scene light-free, shadowless, emissive; node names intact
- [ ] Gauge/screen textures regenerated (`gauge_tex.py`) and imported
- [ ] GLB exported + `godot --headless --import .`
- [ ] Suites of section 6 green (cases/0 errors recorded)
- [ ] In-game captures reviewed by you (never Ollama/Gemini)
- [ ] `graphify update .`
