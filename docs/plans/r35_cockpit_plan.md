# UltraDrive - Nissan GT-R R35 Cockpit (Interior) Replica Plan

> Research + phased implementation plan for giving the Nissan GT-R R35 2017
> (`nissan_gt_r35_2017`) a **bespoke cockpit**: a right-hand-drive instrument
> binnacle with the big red-accented centre tachometer, the twin-screen centre
> stack (Multi-Function Display + nav), a flat-bottom paddle-shifted steering
> wheel, carbon/leather/Alcantara trim with red stitching, and an R35-specific
> seat anchor - all inside the shipped F1/F2a/F4 camera + rig + dash-as-HUD
> contract, without breaking a single existing cockpit suite.
>
> **Written:** 2026-10-09 . **Inputs:** `AGENTS.md` (house rules, "No tech
> ceiling", plan-doc format, shell-is-cmd.exe traps), `docs/ROADMAP.md`
> (believable-garage / "garage depth" north star), `docs/plans/custom_interiors_plan.md`
> (P0-P6 contract this plan rides), `docs/plans/first_person_camera_plan.md`
> (F1 camera + vision-bridge sign-off convention) .
> **Grounded in (read-only survey):** `scripts/vehicle/cockpit_rig.gd`,
> `scenes/vehicle/cockpit_rig.tscn`, `scripts/camera/cockpit_camera.gd`,
> `scripts/race/cockpit_dash.gd`, `scenes/ui/cockpit_dash.tscn` (via
> `scenes/ui/hud.tscn`), `scripts/vehicle/car_config.gd` (`cockpit_seat_height`
> / `cockpit_seat_forward` at `car_config.gd:122-125`),
> `resources/cars/nissan_gt_r35_2017.tres`, `scenes/vehicle/player_car.tscn`,
> `assets/cars/nissan_gt-r_r35_2017.glb`,
> `tests/suites/test_cockpit_interior.gd`, `tests/suites/test_cockpit_camera.gd`,
> `tests/suites/test_cockpit_hud.gd`, `tests/suites/test_gtr_r35.gd`.
>
> **No code was changed to write this document.** This is the plan, not the
> execution (see STATUS). Every claim about the `.glb` node tree and the four
> test gates below was verified by reading the files, not assumed.

---

## Sec 0 EXECUTION CONVENTIONS (read before delegating any phase)

> Standing house contract, mirrored from `custom_interiors_plan.md Sec 0` and
> `open_world_seeding_plan.md Sec 3.0`.

- **One owner per phase / file set.** Phases here are ordered so a single agent
  can do P0 (the contract spine) and then author the R35 scene. No two agents
  edit `cockpit_rig.gd` at once.
- **Contracts fixed before parallel work.** The node anchors (Sec 4.2), the new
  `CarConfig` exports, and the fallback order (Sec 4.3) are the contract. If the
  R35 and future cars are built in parallel, they share these names.
- **"No tech ceiling" is respected** (`ROADMAP.md:96-107`): the plan states the
  ambition (a recognizable R35 cabin), then the cheapest Godot route, then the
  upgrade path (authored scene today, Blender/GLB interior later).
- **Shell discipline.** The `bash` tool is `cmd.exe`. Use `tools\pick.bat`,
  and the `read` / `grep` / `glob` / `edit` / `write` tools. Never type a POSIX
  pipeline. Never hardcode a drive path; resolve via `godot_path.bat`.
- **Engine discipline.** Import probe FIRST (`cmd /v:on /c "call godot_path.bat
  & !GODOT_EXE_CONSOLE! --headless --import ."`), then the GDUnit `-s` run with
  `--ignoreHeadlessMode` AFTER the tool-script path. One Godot process at a
  time. Full-suite runs go to a background sub-agent (never block).
- **GDScript rules.** No code comments unless asked; tabs; warnings-as-errors
  (type every `var`); vector `is_equal_approx` needs a same-type approx arg.
- **ASCII only** in this document and in any new scene text - the older plan
  docs picked up mojibake; do not add more.

---

## Sec 1 VISION & SCOPE

The cockpit view for the GT-R should stop looking like the shared F2a box and
read unmistakably as an R35 driver's seat. The ambition:

- **The binnacle is the hero.** A hooded instrument cowl behind the wheel with
  the large **red-accented centre tachometer** (gear readout at its upper right)
  flanked by the analog speedometer/fuel/temp dials, cluster angled toward the
  driver (Nissan 2015/2021 press kits; Wikipedia R35). A small emissive strip
  carries the shift lights.
- **The centre stack is twin-screen.** The video-game-inspired Multi-Function
  Display (created with Polyphony Digital, 11 pages of mechanical/driving data)
  plus the 8-inch nav/audio touchscreen, framed by carbon-fibre trim and a
  metallic shift surround with the R/N/D drive selector, the red engine-start
  button and the Display Command rotary dial.
- **The wheel is a GT-R wheel.** Leather/partial-Alcantara rim, a flattened
  bottom chord, a squared-off centre hub with the GT-R badge, and a **paddle on
  each side** - reviewed against the F2a torus proxy, which is not enough.
- **Trim vibe.** Black leather + Alcantara (metre hood / headliner), carbon
  fibre cluster + console panels, discrete **red stitching** on seats, console,
  door trim and wheel, and **red instrument backlighting**.
- **Right-hand drive (RHD).** The R35 is a Japanese car; the driver sits on the
  **right**. Distinctive, and explicitly in scope - left-hand drive is NOT.
- **Seat anchor.** An R35-specific eye (`cockpit_seat_height` /
  `cockpit_seat_forward`, plus a new lateral offset for RHD) with a calibration
  procedure against reference screenshots.

**Out of scope:** LHD cockpit, interactive dash controls, VR, cloth/leather UV
texturing beyond flat/matte `StandardMaterial3D` tones + one carbon noise
texture, a photo-real hand-stitched bake (that is the later GLB art lane,
`custom_interiors_plan.md Sec 5-P5`), and any dynamic (non-emissive) cabin lights.

---

## Sec 2 RESEARCH FINDINGS

### 2.1 The codebase contract (verified by reading)

- **The rig is a SIBLING of `CarBody`**, a direct child of the `VehiclePhysics`
  root (`player_car.tscn:28`), precisely because
  `PlayerCarController._apply_visual()` clears `CarBody`'s children on every car
  swap (`cockpit_rig.gd:13-16`). A cockpit scene therefore **must not live inside
  `CarBody`**, and `_apply_visual()` can never be asked to preserve it. This is
  the single most important placement constraint.
- **Rig origin == the drive eye** in car space (authored `(0, 0.55, -0.55)`,
  `cockpit_rig.tscn:33`). `_sync_to_seat_anchor()` moves the whole rig on
  `position.y/z` each frame from `CarConfig.cockpit_seat_height` /
  `cockpit_seat_forward` (`cockpit_rig.gd:95-106`). Interior content authored in
  eye space is therefore never re-positioned by the seat override.
- **Visibility gate is separate from the windshield gate.** `sync_visibility()`
  reveals the interior ONLY while `CockpitCamera.is_current_view()` is true and
  hides it for chase/hood/orbit; no cockpit camera at all means HIDDEN
  (`cockpit_rig.gd:111-134`). `sync_shell_view()` separately hides the exterior
  shell / clears glass in the same state (`cockpit_rig.gd:143-165`).
- **The steering-wheel spin seam** captures `SteeringWheel.basis` and
  right-multiplies `Basis(Vector3.UP, steer * STEER_VISUAL_MAX_RAD_CABIN)` where
  `STEER_VISUAL_MAX_RAD_CABIN = 2.2` (`cockpit_rig.gd:38,75-88`). The wheel axle
  is **local Y**; a non-Y axle would silently break spin.
- **Camera eye math** (`cockpit_camera.gd:148-160`): `global_position + UP *
  seat_height - global_basis.z * seat_forward`, near plane 0.2, FOV 60->68,
  plus bounded feel layers. There is **no lateral term** today.
- **The 2D dash-as-HUD** (`cockpit_dash.gd`) reads the same
  `car.get_drive_info()` (speed_kmh / gear / rpm) as `race_ui.gd`, shows a text
  panel while the cockpit cam owns the viewport, and dims `%Cluster` to
  `cluster_dim_opacity` (`cockpit_dash.gd:24-65,106-117`). It is already
  optional (`dash_hud_enabled`).
- **The R35 config** (`nissan_gt_r35_2017.tres`) has A-class / 1740 kg / 1.8 bar
  turbo and **no cockpit overrides** (`cockpit_seat_height/forward` are 0.0, the
  CarConfig default, `car_config.gd:124-125`).

### 2.2 R35 interior facts (researched, sourced in Sec 8)

- **Instrument cluster:** a large **centre-mounted tachometer with a gear
  display at its upper right**, an analog speedometer, fuel and temperature
  meters, all at a uniform height and **angled toward the driver**; the cluster
  finisher is **carbon-look**, the tach is **red-accented** (full red on NISMO),
  and the metre hood is wrapped in **Alcantara** (Nissan 2015 press kit;
  Wikipedia). Redline 7,000-7,100 rpm. Hidden **shift lights** live in the tach
  face (GT-R Life) - the manual-mode upshift indicator.
- **Multi-Function Display (MFD):** a "video-game-inspired" multi-function
  display created with **Polyphony Digital**, 11 pages of mechanical and
  driving data (acceleration, brake pedal pressure, steering angle, G-forces,
  turbo boost, water/oil temp + pressure, trans-oil temp, front/rear drive
  split, on-board recorder) (Nissan 2011/2015/2021 press kits).
- **Second screen:** an **8-inch nav/audio touchscreen** on the centre stack,
  operated by a **rotary Display Command dial** on the carbon centre console
  (Nissan UK/2024 brochures).
- **Centre console:** large metallic-framed console, ergonomically-designed
  shift lever / drive-mode (R/N/D) selector, **red engine-start button** (Nissan
  2011 press kit). Rear transaxle layout gives a flat floor + narrow tunnel.
- **Steering wheel:** leather-wrapped (Alcantara on NISMO), GT-R badged, audio +
  cruise buttons; **paddles on the column pre-2017, on the wheel post-2017**
  (Wikipedia; the game car is the 2017 facelift, so paddles mount on the wheel).
  The KMP aftermarket replacement for this car is **330 mm**; the OEM rim is a
  normal sports-car size (assume 0.36 m - see Sec 8 unverified).
- **Trim:** black leather + synthetic-suede/Alcantara, **carbon fibre** console
  and cluster, **discrete red stitching** on seats/console/door trim/wheel,
  **red** instrument backlighting (Nissan 2011/2015/2024 material).
- **Real dimensions (feeds seat math):** width 1,895 mm, height 1,370 mm,
  wheelbase 2,780 mm, length ~4,656-4,709 mm, track 1,590/1,600 mm, ground
  clearance ~105 mm (auto-data; Wikipedia; cardekho).

### 2.3 GLB verdict - the interior is NOT in the asset (verified)

Parsing the GLB JSON chunk of `assets/cars/nissan_gt-r_r35_2017.glb` (79 nodes,
75 meshes, 9 materials, exported by Khronos glTF Blender I/O v4.5.51):

- Node names are **exterior-only**: `Body`, `Glass`, `Windscreen`,
  `GlassFastback`, `Shoulder_L/R`, the four `Wheel_*` hubs + rims/tyres/calipers,
  lights, mirrors, intakes, wing, exhaust, diffuser fins.
- A keyword sweep for `interior`, `dash`, `cockpit`, `seat`, `steer`, `pedal`,
  `console`, `gauge`, `door`, `roof`, `headliner`, `pillar` returns **zero
  matches**. Materials are `CarPaint/Glass/BrakeDisc/Rim/Tyre/Caliper/Headlight/
  Taillight/DarkTrim` - no interior material.
- Model bounds (local, pre-`CAR_ORIENT`): x `[-1.007, 1.037]` (~2.04 m incl.
  mirrors), y `[-0.5, 1.356]`, z `[-2.35, 2.269]` (~4.62 m, nose +Z confirmed).

**Consequence:** there is **no existing interior geometry to wire up**. The
"consume the GLB interior into the rig" path is dead; the R35 cockpit must be
**authored** (Godot primitives / a small hand-built scene), which is exactly the
`custom_interiors_plan.md` option (a)/(c), delivered through its scene-override
lane. This is the single biggest finding and it sets the phase order in Sec 5.

---

## Sec 3 RECOMMENDED APPROACH

**Recommendation: ride the `custom_interiors_plan.md` contracts, but deliver the
R35 through the scene-override lane (custom_interiors P5) front-loaded, not the
parametric data tables (P2).**

Why, concretely:

1. **The contracts fit.** `InteriorResource.interior_scene` (PackedScene
   override), the `CarConfig.interior` export, the anchor names
   (`SteeringWheel`/`Dash`/`SeatRoot`/`GaugeRPM`/`GaugeSpeed`) and the fallback
   chain are exactly what an authored R35 cabin needs, and the sibling-of-CarBody
   rule is inherited for free. Implementing the **minimal P0 + the
   `interior_scene` half of P1** from that plan gives us a clean home.
2. **The parametric tables do not fit an R35.** P2 is a per-car box builder
   (dash/pillars/header/wheel from primitives, one trim material). The R35 needs
   RHD asymmetry, a hooded double-dial binnacle, a twin-screen stack, a
   flat-bottom paddle wheel and red cluster backlighting - none of which a
   `dash_width/height/depth` table expresses. Authoring one `.tscn` is cheaper
   and higher-fidelity than stretching the param space.
3. **Divergence, stated plainly:** this plan does **not** wait for the full
   `custom_interiors_plan` P2/P3. It promotes the two pieces that unblock the
   R35 (the `InteriorResource` type with an `interior_scene`, and the loader
   branch) and leaves the parametric builder + gauge-pod framework to that plan.
   If `custom_interiors_plan` is later executed, the R35 keeps working as its
   first `interior_scene` entry.

**HUD decision: keep the 2D dash-as-HUD as the global default and the
accessibility fallback, but the R35 hides it and carries a 3D cluster.**
Rationale: the GT-R's identity is its instruments
(`Sec 2.2`); a screen-space text panel drawn over the binnacle would occlude the
exact geometry this plan exists to show. The 3D cluster consumes the same
read-only `car.get_drive_info()` feed (single source of truth, no new signal),
so nothing about the drive feed forks. Concretely, the R35 sets
`InteriorResource.suppress_hud_dash = true` (the flag is defined in
`custom_interiors_plan.md Sec 3/Sec 4.4`) so `cockpit_dash.gd`'s text panel stays
hidden in cockpit mode for this car only, while `%Cluster`'s dim toggle is
untouched (the player can still choose the screen cluster). Every other car keeps
today's 2D panel byte-for-byte.

**Dynamic-light discipline:** the 3D cluster, MFD and screens are **emissive
`StandardMaterial3D` quads + a rotated needle mesh** only - self-emission like
the F2a trim material (`cockpit_rig.tscn:8-10`), **no `OmniLight`, no
`SubViewport`** beyond the pre-existing off-by-default rear-view mirror. This
holds the quality-ladder Low preset.

---

## Sec 4 ARCHITECTURE / CONTRACT

### 4.1 New data (minimal subset of custom_interiors P0)

- New `scripts/vehicle/interior_resource.gd` (`class_name InteriorResource
  extends Resource`) with, at minimum: `interior_scene: PackedScene`,
  `trim_color: Color`, `emission_energy: float`, `suppress_hud_dash: bool`,
  `gauge_layout: Dictionary`. A default instance == today's F2a look.
- `CarConfig` gains `@export var interior: InteriorResource` (default null) and
  **`@export var cockpit_seat_lateral: float = 0.0`** (new: RHD needs a lateral
  eye, which no export currently provides).

### 4.2 Node anchor contract (authored in EYE space)

All names below are required for the loader and tests; the R35 scene provides
them. Authored in eye space (root origin = drive eye; forward = -Z looking out;
car's left = +X per `test_gtr_r35.gd:71-75`, so **driver-right = -X** for RHD).

| Anchor | Type | Contract |
|---|---|---|
| `SteeringWheel` | `Node3D`/`MeshInstance3D` | **REQUIRED.** Axle along local **Y**; spin seam right-multiplies a Y rotation (`cockpit_rig.gd:75-88`). Missing -> default wheel fallback, never a crash. |
| `Dash` | `Node3D` | Dash root (any child meshes). |
| `SeatRoot` | `Node3D` | Interior-local seat marker (used for eye/seat agreement). |
| `GaugeRPM` / `GaugeSpeed` | `Node3D` | Needle pivot pods (needle rotates about the pod's local X). |
| `GaugeMFD` | `Node3D` | Optional emissive MFD screen quad (static/emissive; mode shown by swapping an emissive colour or flipbook-free texture). |

### 4.3 Loading + fallback chain (extends `CockpitRig._ready`)

1. `cfg = get_parent().config as CarConfig`; `res = cfg.interior`.
2. `res == null` -> keep the literal `cockpit_rig.tscn` tree (byte-identical for
   every car without a table; all existing cockpit tests stay green).
3. `res.interior_scene != null` -> instantiate as a child named `Interior`;
   resolve anchors under it; missing `SteeringWheel` spawns the default wheel.
   Any instantiate error -> fall through to (2)/(4).
4. else -> `custom_interiors_plan` parametric builder (out of scope HERE; if the
   R35 is the only customer, this branch stays unimplemented and `interior ==
   null` remains the fallback).

### 4.4 Seat-anchor + RHD

- Add a shared helper (the custom_interiors P4 single-source idea) so
  `cockpit_camera.get_seat_anchor()` and `cockpit_rig._sync_to_seat_anchor()`
  both read `(cockpit_seat_height, cockpit_seat_forward, cockpit_seat_lateral)`.
- `cockpit_seat_height/forward` keep their `> 0.0` guard; **`cockpit_seat_lateral`
  must be applied on `!= 0.0`** (it is legitimately negative for RHD). Default
  0.0 keeps `test_cockpit_camera`'s 0.55/0.55 anchor math identical.
- R35 assumed values (calibrate per Sec 5-P5): `cockpit_seat_height ~ 0.55`,
  `cockpit_seat_forward ~ 0.50`, `cockpit_seat_lateral ~ -0.36` (driver right,
  car-local -X). Lateral ~0.36 m is a plausible half-cabin offset for a 1.895 m
  car; treat as an assumption, not a measurement.

### 4.5 Materials (quality-ladder safe)

- Trim: one matte black `StandardMaterial3D` (roughness ~0.9) + a leather tone +
  an Alcantara tone (slightly higher roughness, lower specular).
- Carbon: the same material with a small tiled normal/noise texture (single
  texture budget, no shader) OR a darker low-roughness panel - pick whichever
  the Low preset handles cheapest; state the choice in the phase.
- Accents: a thin red **emissive** strip for stitching/backlight (low energy,
  like the F2a 0.15 emission) and a red-accented tach face (emissive texture).
- No `OmniLight`, no `SubViewport`, no dynamic light pass.

---

## Sec 5 PHASED IMPLEMENTATION PLAN

Effort = T-shirt (S/M/L). Every phase keeps the four cockpit suites green
(Sec 6 table). Vision sign-off (`capture_game_window` in cockpit mode ->
`.vision/captures/`, critique via `analyze_image` / `gemini_vision.bat`) is part
of each phase's acceptance, not a separate afterthought.

### P0 - Contract spine: `InteriorResource` + `CarConfig` exports + loader branch

- **What/Why:** the zero-behaviour-change data home. Null default = every `.tres`
  byte-identical; the runtime stays on the literal rig.
- **Files:** new `scripts/vehicle/interior_resource.gd`; `scripts/vehicle/car_config.gd`
  (`interior`, `cockpit_seat_lateral`); `scripts/vehicle/cockpit_rig.gd` (the
  `interior_scene` branch of Sec 4.3).
- **Acceptance / gate:** `tests/suites/test_gtr_cockpit_resources.gd` -
  a default `InteriorResource` equals today's rig constants; `CarConfig`
  round-trips `interior` + `cockpit_seat_lateral`; a car with `interior == null`
  instantiates identical anchors (`Dashboard`/`SteeringWheel` names) so
  `test_cockpit_interior.gd` is unchanged; a bogus `interior_scene` path degrades
  to the default with zero error.
- **Effort:** S-M.

### P1 - Author the R35 cockpit shell (`nissan_gt_r35_2017_cockpit.tscn`)

- **What:** a new authored scene under `scenes/vehicle/interiors/`, in eye space,
  RHD: dash body, hooded binnacle cowl, A-pillars, windshield header, door cards
  with an armrest, and a centre-stack riser. Pods/nodes named per Sec 4.2.
  Wire via `resources/cars/nissan_gt_r35_2017.tres` -> `interior.interior_scene`.
- **Files:** `scenes/vehicle/interiors/nissan_gt_r35_2017_cockpit.tscn` (+ its
  `.uid`), the R35 `.tres`.
- **Acceptance / gate:** new `tests/suites/test_gtr_r35_interior.gd` - the scene
  instantiates headless; `SteeringWheel`/`Dash`/`SeatRoot` exist; the rig shows
  only while the cockpit cam is current (drive `sync_visibility()`); the exterior
  shell see-through still flips (`sync_shell_view()`); AABB sanity (dash top below
  the eye, no node behind the eye). Vision: cockpit capture reads as a dash +
  pillars, not the generic box.
- **Effort:** M.

### P2 - Double-dial binnacle + 3D gauge cluster (red-accented tach)

- **What:** the hooded cowl over `GaugeRPM`/`GaugeSpeed`; a red-accented tach
  face with a `GaugeRPM` needle (rotates about local X from rpm normalised to the
  config `idle_rpm`/`redline_rpm`), an analog speedo needle from
  `speed_kmh / face_max`, an emissive shift-light strip, and a static emissive
  mode label. HUD coupling: `suppress_hud_dash = true` for the R35.
- **Files:** the R35 cockpit scene (mesh pods + `_sync_gauges()` in
  `cockpit_rig.gd`, polled beside `_sync_steer_visual()`), `cockpit_dash.gd`
  (read the active car's `suppress_hud_dash`).
- **Acceptance / gate:** extend `test_gtr_r35_interior.gd` - needle angle is a
  pure clamped function of `(rpm, idle, redline)` and `(speed, face_max)` (drive
  `apply_drive_info`, assert the recovered angle); R35 hides the 2D `DashPanel`
  and does not change `%Cluster` behaviour; non-R35 cars keep
  `cockpit_dash.gd`'s existing panel + dim, so `test_cockpit_hud.gd` is green
  unchanged. Vision: the tach reads red-accented, needles move.
- **Effort:** M.

### P3 - Flat-bottom, paddle-shifted steering wheel

- **What:** replace the torus proxy for the R35 with a rim that has a flattened
  bottom chord (a ring minus a lower arc, or a swept profile), a squared hub with
  a badge disc, and a **paddle leaf on each side** (simple beveled boxes). Keep
  the axle exactly local-Y so the F2a spin seam is untouched. Target ~0.36 m rim
  diameter.
- **Files:** the R35 cockpit scene.
- **Acceptance / gate:** `test_gtr_r35_interior.gd` - `_recover_steer_spin`
  matches `steer * STEER_VISUAL_MAX_RAD_CABIN` exactly (mirror the
  `test_cockpit_interior.gd:245-313` math); two paddle nodes exist, one each side
  of the hub (eye-local +/-X); rim outer radius sits in the authored band.
- **Effort:** M.

### P4 - Twin-screen centre stack + console controls

- **What:** the MFD emissive quad (`GaugeMFD`, may show a mode via an emissive
  colour/texture swap) + the 8-inch nav screen quad, a carbon console panel, a
  metallic shift surround with R/N/D selector blocks, the red engine-start
  button (emissive), and the Display Command rotary disc.
- **Files:** the R35 cockpit scene; a small static mode hook on `CockpitRig`
  (`set_mfd_mode(int)` swapping an emissive colour - optional, test-only).
- **Acceptance / gate:** `test_gtr_r35_interior.gd` - all console nodes exist;
  every screen material has `emission_enabled = true` and NO `OmniLight` /
  `SubViewport` in the subtree (assert via `find_children("*","OmniLight3D")`
  empty and no `SubViewport`); an optional `set_mfd_mode` changes only the
  emissive colour. Vision: twin screens read as two lit panels.
- **Effort:** S-M.

### P5 - Trim vibe + RHD seat anchor + calibration

- **What:** apply the leather/carbon/Alcantara tones + red stitching/backlight
  accents; set the R35 `.tres` cockpit overrides (height/forward/lateral) and run
  the calibration procedure: capture the cockpit view, overlay/compare with two
  reference R35 interior screenshots (binnacle height + wheel-to-eye + centre
  stack), and nudge `cockpit_seat_*` until the eye sits behind the wheel with the
  binnacle bottom just under the sightline.
- **Files:** the R35 cockpit scene (materials), `resources/cars/nissan_gt_r35_2017.tres`
  (overrides).
- **Acceptance / gate:** `test_gtr_r35_interior.gd` - config round-trips the three
  overrides; camera `get_seat_anchor()` == rig eye including lateral; raising
  `cockpit_seat_height` moves camera + rig + `SeatRoot` by the same delta.
  `test_cockpit_camera.gd` green (its 0.55/0.55 defaults untouched because
  lateral defaults 0 and only the R35 config sets it). Vision: side-by-side
  critique vs references.
- **Effort:** S.

### P6 - Full-suite gate + per-phase vision sign-off closeout

- **What:** run the AGENTS.md headless recipe full suite via the background gate
  sub-agent; confirm 0 new failures vs the measured baseline (all cockpit suites
  green, `test_gtr_r35.gd` green, `test_cockpit_interior/camera/hud` green);
  collect the `.vision/captures/` cockpit PNGs for the cube (tach, wheel, stack,
  RHD seat) and store the critique in `.vision/analysis.md`.
- **Acceptance / gate:** full-suite gate green; every phase's capture archived;
  no orphan-count regression (managed nodes freed in `after_test`).
- **Effort:** S (verification only).

---

## Sec 6 RISKS / REGRESSIONS

| Risk | Why | Guardrail |
|---|---|---|
| `test_cockpit_interior.gd` geometry pins | It asserts `Dashboard`/`PillarLeft`/`PillarRight`/`HeaderBar`/`SteeringWheel` and `wheel.position.y in [-0.22,-0.18]`, `z == -0.4`, `x == 0` on the **default** `cockpit_rig.tscn` | The default scene is **not edited**; the R35 uses its own `interior_scene`. Its own suite asserts R35 anchors. |
| `test_cockpit_camera.gd` anchor pins | Pins 0.55/0.55 defaults | `cockpit_seat_lateral` defaults 0.0 and is only applied on `!= 0.0`; height/forward guards unchanged. |
| `test_cockpit_hud.gd` panel pins | Pins the 2D panel + `%Cluster` dim | `suppress_hud_dash` is R35-only (`InteriorResource` null for other cars); the SceneRunner test uses `test_track.tscn` (starter car), so it stays green. |
| RHD needs a lateral eye | No lateral term exists today | Add `cockpit_seat_lateral` (default 0) + one shared anchor helper; the "driver-right" assumption is calibrated in P5, not hardcoded silently. |
| Wheel axle regression | Spin right-multiplies a **Y** rotation | The R35 wheel is authored axle-along-Y; the spin test mirrors `_recover_steer_spin`. |
| `_apply_visual()` wipes `CarBody` children | Car swaps clear the body | Cockpit stays a **sibling of CarBody** (rig scene placement is inherited); never parent the R35 interior under `CarBody`. |
| Interior GLB transform traps | Body GLBs are nose-+Z + `CAR_ORIENT` | The R35 interior is authored in **eye space** and must NOT be wrapped in `CAR_ORIENT`; test asserts eye-space forward. |
| Quality ladder / iGPU | Low preset must stay light | Emissive-only materials, no `OmniLight`/`SubViewport`, bounded primitive count; a `find_children` assert enforces no lights. |
| Orphan leak on rebuild | Rig may swap interiors | `queue_free()` the previous `Interior` subtree; suites free managed nodes in `after_test`; orphan baseline is a gate. |
| GLB/config drift | Adding fields to the R35 `.tres` | Additive only; `test_gtr_r35.gd`'s existing asserts (class A, visual_path, torque, turbo) are untouched. |
| Fabricated dimensions | OEM wheel dia / H-point not published | Mark all assumed numbers in Sec 8 as assumptions with a visual calibration procedure. |

---

## Sec 7 STATUS

**This document is the RESEARCH + PLAN, not the execution. No game code, scene,
`.tres` or test file was modified to produce it** (verified: read-only survey +
GLB parse only). Nothing is ticked until its suite is green via the AGENTS.md
headless recipe and its cockpit capture has been critiqued.

**EXECUTED 2026-10-09 (all phases green).** Baseline update: full suite now at
`1103 test cases | 0 errors | 0 failures | 20 orphans` (exit 101, orphans-only
= success). The `InteriorResource` .tres does NOT live in `resources/cars/` —
it is at `resources/interiors/nissan_gt_r35_2017_cockpit.tres`, because two
AAA-6 gate suites (`test_car_default_setup.gd`, `test_starter_car_visual.gd`)
glob `resources/cars/*.tres` and cast to `CarConfig`; an InteriorResource there
loaded as nil and turned the gate RED until moved.

- [x] P0 - `InteriorResource` + `CarConfig.interior` / `cockpit_seat_lateral` + loader branch
- [x] P1 - authored R35 cockpit shell (`nissan_gt_r35_2017_cockpit.tscn`) wired into the `.tres`
- [x] P2 - double-dial binnacle + 3D cluster (red-accented tach, shift lights) + `suppress_hud_dash`
- [x] P3 - flat-bottom paddle-shifted steering wheel (axle-Y, spin seam preserved)
- [x] P4 - twin-screen centre stack + console controls (MFD / nav / R-N-D / start / rotary)
- [x] P5 - trim vibe + RHD seat anchor overrides (0.55 / 0.50 / -0.36) + screenshot calibration
- [x] P6 - full-suite gate green (1103/1103, 0 failures) + windowed cockpit captures

*Plan ends. When adopted, fold into `custom_interiors_plan.md` as its first
`interior_scene` entry and note the RHD `cockpit_seat_lateral` contract as the
shared seat-anchor convention.*

---

## Sec 8 RESEARCH DIGEST

### 8.1 Verified facts (sourced)

| Item | Finding | Source |
|---|---|---|
| Cluster | Large centre-mounted tach w/ gear display upper-right; analog speedo/fuel/temp; angled to driver; carbon-look finisher; red-accented tach (full red on NISMO); Alcantara metre hood; redline 7,000-7,100 | Nissan 2015/2021 press kits; Wikipedia; 2024 brochure |
| Shift lights | Hidden in the tach face; orange "get ready" then red "shift now"; manual mode | GT-R Life forum |
| MFD | Video-game-inspired multi-function display, made with Polyphony Digital, 11 pages (accel, brake pressure, steering angle, G, boost, temps, drive split, recorder) | Nissan 2011/2015/2021 press kits |
| Nav screen | 8-inch nav/audio touchscreen on the centre stack; Display Command rotary dial on the carbon console | Nissan UK brochure; 2024 brochure |
| Console | Metallic-framed console, shift lever / drive-mode (R/N/D) selector, red engine-start button; flat floor, narrow tunnel | Nissan 2011 press kit |
| Steering wheel | Leather-wrapped / Alcantara (NISMO), GT-R badged, audio + cruise buttons; paddles on column pre-2017, on wheel post-2017; KMP replacement = 330 mm | Wikipedia; KMP Drivetrain |
| Trim | Black leather + synthetic-suede/Alcantara; carbon console + cluster; discrete red stitching (seats/console/door/wheel); red instrument backlight | Nissan 2011/2015/2024 material |
| Dimensions | 1,895 mm wide, 1,370 mm tall, 2,780 mm wheelbase, 4,656-4,709 mm long, track 1,590/1,600 mm, ground clearance ~105 mm | auto-data; Wikipedia; cardekho |
| Layout | RHD (Japan); model years 2009-2024; 2017 facelift = the game car | Wikipedia; `test_gtr_r35.gd` |

### 8.2 Could NOT verify -> ASSUMPTIONS (calibrate visually, do not treat as fact)

| Item | Assumed value | Calibration (P5) |
|---|---|---|
| OEM steering-wheel diameter | 0.36 m (KMP aftermarket is 330 mm) | Fit rim outer radius to a reference wheel photo at the same FOV. |
| Eye height / H-point | keep `cockpit_seat_height = 0.55` | Overlay reference; raise/lower until the binnacle bottom sits just under the sightline. |
| Seat forward | `cockpit_seat_forward = 0.50` | Fit so the wheel hub is hand-span from the eye and the dash fills the lower third. |
| Seat lateral (RHD) | `cockpit_seat_lateral = -0.36` (car-local -X = driver right) | Overlay: the wheel must be centred in view; nudge until the A-pillar/console relationship matches. |
| Windshield rake / dash depth | not published | Fit dash top edge + pillar angle to reference screenshots. |
| "Double-bubble" binnacle | NOT a sourced Nissan term; treat as the hooded twin-dial cowl | Visual only. |
| Tach face base colour | black face with red accents (full red = NISMO) | Confirm against a 2017 Premium reference before painting a full-red face. |
| Cabin interior width | ~1.5 m (derived from exterior width) | Sanity-check against the GLB bounds. |

### 8.3 Source links

- Nissan 2015 GT-R press kit: https://usa.nissannews.com/en-US/releases/us-2015-nissan-gt-r-press-kit
- Nissan 2011 GT-R press kit: https://usa.nissannews.com/en-US/releases/release-9f615165f18a4f22847ece5e49f105ae-2011-nissan-gt-r-press-kit-2
- Nissan 2021 GT-R press kit: https://usa.nissannews.com/en-US/releases/2021-nissan-gt-r-press-kit
- Nissan 2024 GT-R brochure (PDF): https://www.nissanusa.com/content/dam/Nissan/us/vehicle-brochures/2024/2024-nissan-gt-r-brochure-en.pdf
- Nissan UK GT-R brochure (PDF): https://www.nissan-cdn.net/content/dam/Nissan/gb/brochures/Vehicles/Nissan_GT-R_UK.pdf
- Wikipedia, Nissan GT-R: https://en.wikipedia.org/wiki/Nissan_GT-R
- GT-R Life, tach shift lights: https://www.gtrlife.com/threads/what-do-these-do-on-the-tach-shift-lights.191130
- KMP Drivetrain GT-R R35 wheel (330 mm): https://www.kmpdrivetrain.com/product/nissan-gt-r-r35-gen2
- auto-data.net GT-R R35 dimensions: https://www.auto-data.net/en/nissan-gt-r-r35-generation-250
