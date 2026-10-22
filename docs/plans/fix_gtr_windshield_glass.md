# Fix: R35 first-person view is blocked by opaque near-black cabin geometry ("black windshield")

**Author session date:** 2026-10-16
**Scope of this document:** a PLAN only. No game code was modified in this
session, and no Godot/GDUnit run was performed. Every claim below is either
tagged **VERIFIED** (read from source with a `file:line` reference) or
**UNCERTAIN** (needs the screenshot in §4 step 0 to confirm).
**Related prior plan:** `docs/plans/gtr_r35_lights_glass_plan.md` (its FIX 3 —
"make the shell glass transparent" — is already implemented on the working tree;
this defect is what that change *exposed*, and it is the risk that plan flagged
in its own §6.1: "transparent windshield exposes the body's interior… a dark
cavity").

---

## 1. Goal and player-verifiable acceptance criteria

### Goal
With the **Nissan GT-R R-35** selected and the **cockpit (first-person)** camera
active, the driver must be able to see the road ahead. Today the forward view is
filled by an opaque near-black mass, so the game reads as "the windshield is
black and I can't see out". The fix must clear that sightline **without**
changing how any car renders in chase / hood / orbit views.

### Player-verifiable acceptance criteria (manual, in `play_game.bat`)
- **AC1** — Select the GT-R R35, drive, press the camera-cycle key to COCKPIT.
  Looking straight ahead, the **horizon and road are visible**; there is no
  black slab/dash mass covering the centre of the view.
- **AC2** — In the same view, look **down** (right stick): the instrument
  cluster (tach, speedo, MFD, wheel) is still present, now **below** the
  sightline; look **up**: the sky/windscreen reads through **transparent**
  glass, not black.
- **AC3** — Cycle COCKPIT → CHASE → HOOD → ORBIT: the car renders exactly as it
  does today (body paint intact, glass tinted, no missing panels, no leftover
  floating trim).
- **AC4** — Repeat AC1 on another car (e.g. Comet `cc0_sedan_sports`, starter
  `sports_coupe`): the cockpit view still sees out, and chase view is unchanged.
- **AC5** — (Robustness) In the R35 cockpit view, no exterior body dressing
  (front intake/grille, headlights, hood vents, splitter) floats in the forward
  view in place of the removed dashboard.

### Automated acceptance
The GDUnit gate in §5 is green, and every touched suite stays green.

---

## 2. Current state — VERIFIED

### 2.1 What is NOT the cause (already ruled out)

| Hypothesis | Verdict | Evidence |
|---|---|---|
| The glass override is still opaque mirror | **RULED OUT** | `scripts/vehicle/car_visuals.gd:729-736` (`_glass_clone`) sets `transparency = TRANSPARENCY_ALPHA`, `metallic = glass_metallic` (`0.0`, `car_visuals.gd:39`), `roughness = glass_roughness` (`0.05`), `refraction_enabled = false`, `albedo_color = DEFAULT_GLASS_COLOR` = `Color(0.42,0.50,0.58,0.45)` (`car_visuals.gd:148`). Pinned by a PASSING test: `tests/suites/test_gtr_r35.gd:130-140`. |
| The shell body is opaque from inside in cockpit view | **RULED OUT** | The cockpit pass hides `SHELL` meshes: `car_visuals.gd:803-810` (`cockpit_roles`), `:901-910` (`_set_shell_cockpit`), driven from `scripts/vehicle/cockpit_rig.gd:438-460` (`sync_shell_view` → `_apply_shell_view`). |
| A RainFX windshield overlay is drawn | **RULED OUT** | The overlay is only built/applied while raining. |
| `cockpit_seat_*` config values can move the view relative to the cabin | **RULED OUT** | The eye and the interior are glued to **one** anchor, and a test asserts it: `scripts/vehicle/cockpit_rig.gd:376-401` (`seat_anchor_for`, `_sync_to_seat_anchor`), `scripts/camera/cockpit_camera.gd:148-159` (`get_seat_anchor`), `tests/suites/test_gtr_r35_interior.gd:481-522` (`test_seat_height_delta_moves_camera_rig_and_seat_root_together`). **Consequence: raising `cockpit_seat_height` raises the interior's instrument cluster by the same amount, so it cannot clear the sightline** (see §6-risk 1). |

### 2.2 The R35 shell geometry (VERIFIED from the GLB)

Dumped with `py reports\glb_dump_tmp.py assets/cars/nissan_gt-r_r35_2017.glb`
(scratch file, deleted at the end of this session). Glass material index 1:
`base [0.02,0.03,0.04]`, `metallic 0.9`, `roughness 0.05`,
`KHR_materials_transmission 0.7`, `doubleSided`. Three nodes reference it
(`Glass`, `Windscreen`, `GlassFastback`), each carrying a 180°-about-Y rotation.
The shell GLB is consumed with `CAR_ORIENT` (a 180°-about-Y transform,
`scripts/player/player_car_controller.gd:5`, applied at `:236`), so **car
space = GLB space**, forward = **−Z**, and the eye sits at
`(x=-0.36, y=0.62, z=-0.55)` (from the R35 anchor, §2.4).

| Part | car-space Y | car-space Z | relative to the eye (y=0.62, z=−0.55) |
|---|---|---|---|
| `Windscreen` (mesh 38) | 0.847 … 1.356 | −1.405 … −0.287 | **+0.227 … +0.736 m above the eye → +15° … +41°** |
| `Glass` roof/side (mesh 1) | 0.780 … 1.256 | −0.327 … +0.727 | +0.160 … +0.636 |
| `GlassFastback` (mesh 41) | 0.984 … 1.308 | +0.750 … +1.395 | (behind) |

**The horizon ray (0°) never passes through the windscreen**: the glass is
entirely **above** the eye (its lowest point is +0.227 m, i.e. +15°). So the
driver's forward view is *below* the glass, and whatever geometry occupies
0° is what the player sees.

### 2.3 The R35 authored interior occupies the forward view (VERIFIED)

The interior is `scenes/vehicle/interiors/nissan_gt_r35_2017_cockpit.tscn`,
loaded by `cockpit_rig.gd:266-281` (`_load_interior`) as a child of the rig
named `Interior` at **identity** transform (the scene root
`NissanGTR35Cockpit`, tscn line 301, carries no transform). Because the rig's
origin **is** the drive eye (§2.4), the interior is authored in **eye space**
(forward = −Z, per `docs/plans/r35_cockpit_plan.md:248`). Every material is
near-black with a token emission: `mat_pad_black` albedo `0.075`
(tscn:76-81), `mat_interior` `0.1` (tscn:3-8), `mat_carbon` `0.028`
(tscn:25-31), `emission_energy_multiplier = 0.15`.

Top of each near-field node above the eye line (`y=0`), forward = −Z:

| Node (tscn line) | position (x,y,z) | size | top y | ≈ angle above the eye line at its depth |
|---|---|---|---|---|
| `BinnacleHood` (313) | (0, +0.15, −0.82) | (0.64,0.08,0.46), 20° tilt | **+0.266** | ≈ +18° (extends down to ≈ −4°) |
| `BinnacleBack` (318) | (0, −0.04, −0.9) | (0.68,**0.36**,0.07) | **+0.14** | **+8.9°**, spans **−13.7° … +8.9°**, ±**20.7°** wide |
| `GaugeMFD` (368) + `MFDScreen` (371) | (0.29,−0.1,−0.6) | quad (0.19,0.12) | +0.08 | ≈ +7.4° |
| `SteeringWheel` (439) | (0,−0.1,−0.46) | torus outer 0.18, 28.6° tilt | ≈ +0.063 | ≈ +7° |
| `ShiftLightStrip` (331) | (…, +0.048, …) | quad | +0.054 | — |
| `GaugeRPM` (323) | (0.02,−0.06,−0.7) | quad (0.15,0.15) | +0.015 | — |
| `DashPad` (303) / `Dash` (308) | (0,−0.24,−0.8) / (0,−0.42,−0.72) | boxes | −0.20 / −0.31 | below (OK) |
| `HeaderBar` (389) | (0, +0.62, −0.86) | (1.5,0.09,0.28) | +0.665 | +36° (above — OK) |
| `APillarLeft/Right` (379/384) | (±0.58, +0.14, −0.82) | (0.07,0.85,0.09) | ≈ +0.56 | ±35° lateral (OK) |
| `DoorCardLeft/Right` (394/399) | (±0.76, −0.28, −0.12) | (0.06,0.55,0.95) | −0.005 | ±43° lateral (OK) |

The `BinnacleHood` + `BinnacleBack` + full `GaugeRPM`/`ShiftLightStrip` +
`GaugeMFD` + steering-wheel rim all **straddle the eye's horizontal plane**
inside a roughly ±20° forward cone, at 0.46–0.9 m. Because they are near-black
(`albedo 0.075`, emission 0.15) they render as a **black mass over the horizon**
— the reported symptom. `docs/plans/r35_cockpit_plan.md:389` states the
authoring intent explicitly: *"binnacle bottom just under the sightline"* — and
`:481` says the eye height was to be *"raise[d]/lower[ed] until the binnacle
bottom sits just under the sightline"*. **That calibration was never finished.**

### 2.4 The eye anchor and why the cluster cannot be moved by config (VERIFIED)

`resources/cars/nissan_gt_r35_2017.tres:67-70` →
`interior = ExtResource("2_interior")` (→
`resources/interiors/nissan_gt_r35_2017_cockpit.tres:4,8`),
`cockpit_seat_height = 0.62`, `cockpit_seat_forward = 0.55`,
`cockpit_seat_lateral = -0.36`.
- `cockpit_rig.gd:395-401` sets the rig at `(lateral, height, −forward)` =
  `(−0.36, 0.62, −0.55)` in car space.
- `cockpit_camera.gd:148-159` sets the eye at
  `car_pos + UP*height − basis.z*forward + basis.x*lateral` = the same point.
- Therefore **eye ≡ rig origin ≡ interior origin**, and the interior's geometry
  relative to the eye is fixed by the authored tscn and cannot be changed by
  `cockpit_seat_*` (pinned by `test_gtr_r35_interior.gd:481-522`).

### 2.5 The exterior shell's non-paint dressing stays visible (VERIFIED)

`car_visuals.gd:854-869` (`_material_cockpit_role`) classifies `trim`,
`graphite`, headlights, taillights, reverse, tires, rims, brake, caliper as
`OTHER`, and only `SHELL` meshes are hidden (`:901-910`). The doc comment at
`:798-802` states "Wheels / rims / tires / lights / trim are neither and stay
visible."

The R35 shell keeps **11 `DarkTrim` exterior nodes** plus headlights/taillights
visible during cockpit view (direct children of the shell root). Their
car-space positions relative to the eye:

| Node | car-space position | relative to the eye |
|---|---|---|
| `UpperGrille` | (0, 0.707, −2.348) | **+0.062 … +0.112 above the eye → +2.0° … +3.7°** |
| `Headlight_L/R` | (±0.49, 0.759, −2.02) | +0.089 … +0.189 → +3° … +6° |
| `HoodVent_L/R` | (±0.30, 0.854, −1.735) | +0.209 … +0.259 → +5.2° … +6.5° |
| `FrontIntake` | (0, 0.411, −2.363) | −0.089 … −0.329 → −2.8° … −10.3° |
| `FrontSplitter` | (0, 0.164, −2.325) | well below |

Today the binnacle occludes these (they sit inside its −13.7°…+8.9°/±20.7°
cone and are 1.7–2.3 m away vs the binnacle's 0.9 m). **Once the binnacle is
lowered they become the next black blocker** — floating in mid-air, because the
paint body/hood that would normally hide them is itself hidden
(`car_visuals.gd:901-910`). This is the reason §3 includes a shell-dressing fix
and not just the interior move.

---

## 3. Design decisions

**D1 — Fix the interior, not the glass, not the config.** The glass and the
cockpit shell pass are correct and test-pinned (§2.1). The config path cannot
work (§2.4). The defect is authored interior geometry crossing the sightline.

**D2 — Keep the fix R35-specific and data-driven where possible.** The shared
default cockpit geometry in `scenes/vehicle/cockpit_rig.tscn` must not change
(other cars fall back to it). Only the R35's authored interior is touched.

**D3 — Do not raise `cockpit_seat_height`.** Because the interior is glued to
the eye, raising the eye raises the cluster too; it cannot clear the sightline
and it would also unseat the cabin's absolute car-space placement relative to
the shell. It is a non-goal (see §6-risk 1). Whether the eye "should" be higher
to look *through* the glass is a **separate realism issue**, not this defect:
in cockpit view the paint shell is already hidden, so the driver sees the world
regardless of the eye height; matching the eye to the windscreen would require
decoupling eye from interior (a design change, out of scope here).

**D4 — Lower the cluster by moving the authored interior root.** The smallest,
most monotone edit that satisfies the sightline rule is a single vertical
offset on the interior root node (§4 step 2, Variant A). It is exactly
equivalent to "raise the eye within the cabin by 0.32 m" and it cannot
accidentally leave one node straddling the horizon. Variant B (per-node cluster
shift) is the more surgical alternative if the capture shows the seat/pillars
sitting wrong.

**D5 — Hide the shell's non-glass _body dressing_ in the cockpit pass.** The
existing `SHELL` role is documented as "the paint/body surfaces that block a
driver's forward view" (`car_visuals.gd:799-801`). Grille/intake/headlight/
taillight/hood-vent meshes are body surfaces by that definition; leaving them
classified `OTHER` is the latent bug. Reclassify them to `SHELL` **but keep the
wheel assembly** (`tire`/`rim`/`wheel`/`brake`/`caliper`) as `OTHER`, because
`tests/suites/test_cockpit_visibility.gd:142,153` pins that the Comet's front
wheel stays visible while the cockpit camera is active, and the CC0 `colormap`
branch (`car_visuals.gd:859-862`) must not change.

**D6 — Gate the sightline with a structural test.** Add a test that computes
each interior mesh's AABB in eye space and fails if any mesh that overlaps the
forward cone straddles the eye's horizontal plane. This is the regression guard
that keeps the calibration from silently drifting again.

---

## 4. Implementation steps

> Ownership note: `assets/cars/**`, `resources/cars/**`,
> `scripts/vehicle/car_visuals.gd`, camera scripts and (if unavoidable)
> `scenes/vehicle/player_car.tscn` are the normal owned set.
> **`scenes/vehicle/interiors/nissan_gt_r35_2017_cockpit.tscn` is a scene edit
> OUTSIDE that set — flag it for approval** (it is not in either the owned list
> or the Do-Not-Touch list). It is required: §2.4 proves no owned file can move
> the cluster relative to the eye.

### Step 0 — Diagnostic first (UNCERTAIN → VERIFIED)
The exact dominant occluder is **UNCERTAIN** from source alone (binnacle vs
hood vs wheel vs exterior trim all sit in the cone). Before committing numbers:
1. Launch the game (`play_game.bat`), select the GT-R R35, switch to COCKPIT.
2. Capture the frame with `capture_game_window` (window title `UltraDrive`).
3. Read it back through the vision bridge — `analyze_image`, or the stronger
   `gemini_vision.bat ask --image .vision\captures\<shot>.png --prompt "..."`
   (see AGENTS.md "VISION BRIDGE" / "GEMINI VISION"; local Ollama is ~2.6 tok/s
   so keep prompts short). Ask specifically: *"what near-black shape covers the
   centre of the view; is it the dashboard/binnacle, the steering wheel, or the
   front grille?"*
4. If the capture shows the black is the **windscreen pane itself** rather than
   interior geometry, stop and re-assess with the "Option A" note in §6-risk 1 —
   that case needs the eye/interior decoupling design, which this plan does not
   cover.
Keep the capture in `.vision/` (gitignored) and append the verdict to
`.vision/analysis.md`.

### Step 1 — Confirm the gate is currently RED for the new rule (baseline)
Add the new test from §5 first and confirm it fails on the unmodified tscn.
This proves the test measures the defect (evidence before assertion).

### Step 2 — Lower the R35 authored interior cluster  *(FLAGGED scene edit)*
Edit `scenes/vehicle/interiors/nissan_gt_r35_2017_cockpit.tscn`.

**Variant A — recommended (one line).** Give the scene root a downward offset
so the whole cabin drops relative to the eye:
```
[node name="NissanGTR35Cockpit" type="Node3D"]          # line 301
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.32, 0)
```
Verified against the §2.3 table: every offender's top moves to
`BinnacleHood −0.054`, `BinnacleBack −0.18`, `GaugeMFD −0.24`,
`SteeringWheel −0.257`, `ShiftLightStrip −0.266`, `GaugeRPM −0.305` — all below
the eye line, while `HeaderBar` stays at +0.345 (above, fine) and the A-pillars
stay lateral. Tune the value in −0.02 steps until the §5 test passes with the
`BinnacleHood` top ≤ −0.05 m.

**Variant B — cluster-only (if the capture shows the seat/pillars now sitting
too low).** Apply `y -= 0.34` to `DashPad`, `Dash`, `BinnacleHood`,
`BinnacleBack`, `GaugeRPM`, `GaugeSpeed`, `GaugeMFD`, `SteeringWheel`,
`SteeringColumn`, `VentLeft`, `VentCentre`, `VentRight`, `CentreConsole`; and
shorten `mesh_binnacle_back.size` from `Vector3(0.68, 0.36, 0.07)` (tscn:103) to
`Vector3(0.68, 0.24, 0.07)`. Leave `SeatRoot` (376), `APillar*` (379/384),
`HeaderBar` (389), `DoorCard*` (394/399) untouched.

Do **not** touch any material, `cast_shadow`, or node names — the interior
tests (`tests/suites/test_gtr_r35_interior.gd:56-93,296-367,439-522`) assert
materials, shadow flags, RHD left/right placement and rig-to-eye gluing by
name, and a pure vertical translation preserves all of them.

### Step 3 — Hide the shell's non-glass body dressing in the cockpit pass *(owned)*
`scripts/vehicle/car_visuals.gd`, `_material_cockpit_role` (`:854-869`):
- Split the current `OTHER` branch: keep `tire`/`rim`/`brake`/`caliper` (and the
  CC0 `colormap` + name-based wheel branch at `:859-862`) returning
  `CockpitRole.OTHER`;
- return `CockpitRole.SHELL` for `headlight` / `taillight` / `reverse` / `trim`
  / `graphite`.
Update the `cockpit_roles` doc comment (`:798-802`) and the block comment
(`:780-786`) so they match the new intent ("body dressing hides with the shell;
the wheel assembly stays visible"). No change to `_set_shell_cockpit` — the
existing per-mesh meta restore (`:901-910`) already restores dressing visibility
exactly when the cockpit camera releases the viewport.

### Step 4 — Run the gate, then update the touched tests
See §5. Run `--headless --import .` first (filter for `SCRIPT ERROR`/`Parse
Error`), then one GDUnit `-s` run; the full suite is
`py tools\gdunit_parallel.py -j 4`. Never two Godot processes at once.

### Step 5 — Delete scratch
Delete `reports/glb_dump_tmp.py` and the dump it produced
(`reports/_glb_r35.txt`) — both are throwaway analysis artifacts.

---

## 5. Test plan

GDUnit conventions that must be honoured (AGENTS.md + past failures):
- GDScript warnings are **errors** — type every local explicitly
  (`var roles: Dictionary = …`, `Array[MeshInstance3D]`, etc.).
- Use `assert_that(x).is_equal(y)` / `.is_false()` / `.is_true()`.
- Vector approx compares need a **same-type** approx argument:
  `assert_that(vec).is_equal_approx(vec2, Vector3(0.0001, 0.0001, 0.0001))`.
- Free every managed node in an `after_test` (`_managed` pattern as in
  `tests/suites/test_cockpit_visibility.gd:35-41`).

### 5.1 New — sightline gate (the deliverable's regression guard)
New suite `tests/suites/test_gtr_r35_sightline.gd` (instantiate
`res://scenes/vehicle/interiors/nissan_gt_r35_2017_cockpit.tscn` directly; the
interior root's local space **is** eye space, so no car/rig needed):

- `test_r35_interior_no_mesh_straddles_the_sightline`:
  for every `MeshInstance3D` under the interior root, compute its AABB
  (`Mesh.get_aabb()` transformed by the node's transform relative to the
  interior root). Decide whether the AABB overlaps the forward cone (e.g. test
  segment-AABB intersection along rays at yaw 0, ±5°, ±10°, ±15°, or overlap
  with the `|x| ≤ 0.3·(−z)` wedge for `z < 0`). For any mesh that overlaps the
  cone, assert it does **not** straddle `y = 0`: i.e.
  `(max_y ≤ -0.05) or (min_y ≥ +0.05)`. This fails on the current tree for
  `BinnacleBack`, `BinnacleHood`, `SteeringWheel`, `GaugeMFD`, `GaugeRPM`
  (expected RED at step 1) and passes after step 2.
- `test_r35_cluster_tops_are_below_the_horizon`: explicit spot checks on the
  named nodes (`find_child("BinnacleBack")`, `BinnacleHood`, `SteeringWheel`)
  asserting each top ≤ −0.05 m in eye space. Names keep the intent readable.

### 5.2 Extend `tests/suites/test_cockpit_visibility.gd`
- `test_r35_exterior_dressing_hidden_only_while_cockpit_active`: build the R35
  car (mirror `_build_comet_car` at `:60-70` but point at
  `resources/cars/nissan_gt_r35_2017.tres` / `_car_id = "nissan_gt_r35_2017"`).
  Cockpit camera active → assert the `DarkTrim`/headlight/taillight meshes are
  hidden and the glass is still visible + `TRANSPARENCY_ALPHA`; camera released
  → assert every one of them is visible again (exact restore, as the Comet
  round-trip test at `:308-343` does).
- `test_wheel_assembly_stays_visible_in_cockpit` — assert the Comet's
  `wheel-front-left` (already pinned at `:142,153`) and one AI-car wheel remain
  visible, proving step 3 did not touch the wheel branch.

### 5.3 Must stay green (no edits expected, confirm anyway)
`test_gtr_r35`, `test_gtr_r35_interior`, `test_car_visuals`,
`test_car_paint_materials`, `test_cc0_cars`, `test_night_headlights`,
`test_cockpit_hud`, `test_car_reverse_lights`. If any of them pins an absolute
interior Y or the old "trim/lights stay visible" wording, update **that test**
in the same change and say so in the commit message.

### 5.4 Gate commands
```
call godot_path.bat && "%GODOT_EXE_CONSOLE%" --headless --import .
call godot_path.bat && "%GODOT_EXE_CONSOLE%" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/suites/test_gtr_r35_sightline.gd
call godot_path.bat && "%GODOT_EXE_CONSOLE%" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/suites/test_gtr_r35_interior.gd
call godot_path.bat && "%GODOT_EXE_CONSOLE%" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/suites/test_cockpit_visibility.gd
```
One `-a` per suite (comma-joined `-a` is a documented false-green). For the
whole tree: `py tools\gdunit_parallel.py -j 4`. Verify `_gdunit.txt` is not
0 bytes before trusting it, and use `%GODOT_EXE_CONSOLE%` (the GUI binary
detaches and false-greens). Read `docs/GDUNIT_GATE.md` first.

---

## 6. Risks and gotchas

1. **Raising `cockpit_seat_height` is a trap, not a fix.** The interior is glued
   to the eye (`cockpit_rig.gd:395-401`, `cockpit_camera.gd:148-159`,
   `test_gtr_r35_interior.gd:481-522`), so raising the eye raises the cluster by
   the same amount and the binnacle still straddles the horizon. It would also
   change whether the eye sits below/inside the windscreen. *Option A (out of
   scope):* if the step-0 capture shows the black mass is the windscreen pane
   **itself** (not interior geometry) because the eye is ~0.4 m below the glass,
   then the real fix is decoupling eye from interior (a new car-space interior
   anchor on `CockpitRig` + a `CarConfig` field), which **breaks** the
   eye≡interior contract test and needs its own plan. Do not start it without
   the capture.
2. **The interior scene is outside the normal owned set.** Flag the
   `scenes/vehicle/interiors/nissan_gt_r35_2017_cockpit.tscn` edit for
   approval. It is unavoidable (§2.4).
3. **Do not over-lower.** Variant A moves the seat, door cards and A-pillars
   down with the cluster. If the capture shows the cabin now reads wrong (eye
   floating above the seat/doors), switch to Variant B (cluster-only). Verify
   with a second capture, not by guess.
4. **Step 3 changes a documented contract.** `car_visuals.gd:798-802` currently
   says trim/lights stay visible; update that comment, and do **not** reclassify
   `tire`/`rim`/`wheel`/`brake`/`caliper` — `test_cockpit_visibility.gd:142,153`
   pins the Comet front wheel visible. Keep the CC0 `colormap` wheel branch
   (`:859-862`) untouched.
5. **Only the R35 interior changes.** Do not touch the shared default geometry
   in `scenes/vehicle/cockpit_rig.tscn`; the Comet and every car without an
   authored interior fall back to it.
6. **Do not re-touch `_glass_clone`.** It is already correct and test-pinned
   (`car_visuals.gd:729-736`, `test_gtr_r35.gd:130-140`); do not raise the glass
   alpha "to hide the cavity" as `gtr_r35_lights_glass_plan.md:644-646`
   suggested — that would mute the windscreen without unblocking the road.
7. **Warnings-as-errors.** Type every local; a `Variant`-returning helper
   assigned with `:=` fails to load the suite.
8. **Timeouts / false greens.** Use the console binary, sanity-check
   `_gdunit.txt` size, and remember `-a` must not be comma-joined. The 20-orphan
   baseline and any perf-gate wall-clock flake are unrelated to this change.
9. **Vision tooling cost.** Local Ollama analyses are ~90 s/shot; prefer
   `gemini_vision.bat` for the step-0 critique and keep the prompt short.

---

## 7. Do NOT touch

- **Garage UI:** `scenes/ui/garage.tscn`, `scripts/ui/garage_ui.gd`.
- **Track-select / race menu:** `scripts/ui/track_select*`, the race-menu
  scripts/scenes.
- **Vehicle audio:** `scripts/audio/*` (engine/tyre/etc.).
- **Track layer:** `scripts/track/**`, `scenes/track/**`,
  `scripts/track/track_registry.gd`.
- **Shared cockpit defaults:** `scenes/vehicle/cockpit_rig.tscn`.
- **Glass pipeline:** `CarVisuals._glass_clone` and the glass profile values
  (`car_visuals.gd:729-736`, `:39-40`, `:148`) — already fixed and pinned.
- **Other cars' interiors:** `resources/interiors/*.tres` other than the R35
  (and the R35's `.tres` needs no change — the interior is moved in its scene).
- **The `dash`/HUD suppression contract:** `suppress_hud_dash = true` in
  `resources/interiors/nissan_gt_r35_2017_cockpit.tres:11` stays as-is.

---

## 9. STATUS — implemented (2026-10-16)

Implemented in a worktree agent session. **No Godot/GDUnit run was performed**
(one full-suite gate runs later in the main session; concurrent Godot processes
are forbidden). All verification below is offline/static.

### What changed

| File | Change |
|---|---|
| `scenes/vehicle/interiors/nissan_gt_r35_2017_cockpit.tscn:302` | Root `NissanGTR35Cockpit` now carries `transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.32, 0)` (plan §4 step 2, Variant A). **This is the flagged scene edit outside the normal owned set** (§4 ownership note / §6-risk 2). |
| `scripts/vehicle/car_visuals.gd:863-883` (`_material_cockpit_role`) | Split the old `OTHER` branch (plan §4 step 3): `headlight` / `taillight` / `trim` / `graphite` / `reverse` → `CockpitRole.SHELL`; `tire` / `rim` / `brake` / `caliper` (and the CC0 `colormap` + name-based wheel branch) stay `OTHER`. `'trim'` is tested **before** `'rim'` because the R35 material is `DarkTrim` (contains both substrings). |
| `scripts/vehicle/car_visuals.gd:777-791, ~803-810, ~860-862` | Doc comments updated to the new intent ("body dressing hides with the shell; only the wheel assembly stays visible"). |
| `tests/suites/test_gtr_r35_sightline.gd` | **New suite** (§5.1) — the deliverable's regression guard. |
| `tests/suites/test_cockpit_visibility.gd` | Added `_build_r35_car` helper + two §5.2 tests (below). |

### Offset: `-0.32 m` (Variant A), and why

`eye ≡ rig origin ≡ interior origin` (plan §2.4), so a single downward root
translation is exactly "raise the eye in the cabin by 0.32 m" and cannot leave
one node straddling the horizon (§3 D4). `cockpit_seat_height` is a non-goal
(§3 D3 / §6-risk 1). `_load_interior` (`cockpit_rig.gd:266-281`) does **not**
reset the interior root transform, so the offset is preserved in game.

### Evidence (offline model, no Godot)

An independent pure-Python model of the authored tscn (parses every node + all
primitive-mesh AABBs, applies each AABB corner through the full transform chain
into the interior root's **parent** = eye space, then the §5.1 rule) was run
against the real file:

- **Baseline** (root offset cancelled → identity): **12** cone-overlapping
  meshes straddle the horizon — `BinnacleHood` top **+0.266**, `BinnacleBack`
  **+0.140**, `SteeringWheel` **+0.063**, the tach/speedo faces + needles, the
  shift-light strip, `CentreStackRiser`, the wheel hub/spoke-top and the
  steering column. This is the plan's expected RED (§2.3).
- **After the −0.32 offset (current tree): FAIL COUNT 0.** Spot tops:
  `BinnacleHood` **−0.0536**, `BinnacleBack` −0.180, `SteeringWheel` −0.257,
  `GaugeMFD` −0.360, `GaugeRPM` −0.305. `HeaderBar` sits at `[+0.255,+0.345]`
  (above the band, OK); the A-pillars stay lateral (off-cone).

**Bug found and fixed in the offline model (not in game code):** its
`mat_mul` point-transformed the child's *basis columns*, adding the parent
origin to each basis vector. That is invisible with an identity parent root
(which is why the earlier baseline run was correct) but corrupts every AABB
once the root carries the −0.32 translation — the first post-edit run
spuriously reported `BinnacleHood +0.110` / `HeaderBar` as straddling. After
fixing the composition (basis by the linear part; origin = `A·B.o + A.o`) the
numbers match the plan's hand-table exactly. **Lesson for any future run: a
translated parent root is required to exercise this path.**

### Tests added / updated

- **New** `tests/suites/test_gtr_r35_sightline.gd`:
  - `test_r35_interior_no_mesh_straddles_the_sightline` — every
    `MeshInstance3D` whose AABB overlaps the forward wedge (`z < 0`,
    `|x| ≤ 0.3·(−z)`) must satisfy `(top ≤ −0.05) or (bottom ≥ +0.05)`. RED at
    baseline, GREEN after.
  - `test_r35_cluster_tops_are_below_the_horizon` — named spot checks
    (`BinnacleHood`, `BinnacleBack`, `SteeringWheel`) each `top ≤ −0.05 m`.
  - Measured in **eye space = the interior root's PARENT space** (the interior is
    instantiated under an explicit identity `Eye` Node3D); a root-local
    measurement would cancel the offset and make the gate vacuous.
- **Updated** `tests/suites/test_cockpit_visibility.gd` (§5.2):
  - `test_r35_exterior_dressing_hidden_only_while_cockpit_active` — live R35;
    the `Headlight_L/R`, `Taillight_L/R` and `DarkTrim`
    grille/intake/vents/splitter meshes are `SHELL`, visible outside cockpit,
    hidden while the cockpit camera is active, restored exactly on release; the
    real `Windscreen` stays visible and drops to `COCKPIT_GLASS_ALPHA`.
  - `test_wheel_assembly_stays_visible_in_cockpit` — the Comet's CC0
    `wheel-front-left` and the AI starter car's two-surface (`Tire`+`Rim`)
    `Wheel_FL` both stay visible while the cockpit camera is active (proves step
    3 did not touch the wheel branch).
  - Added `const R35Config` and the `_build_r35_car` helper (mirrors
    `_build_comet_car`).

### §5.3 — suites checked for pinned old behaviour (no edits needed)

`test_gtr_r35`, `test_gtr_r35_interior`, `test_car_visuals`,
`test_car_paint_materials`, `test_cc0_cars`, `test_night_headlights`,
`test_cockpit_hud`, `test_car_reverse_lights`: none pins an absolute interior Y,
the interior-root transform, or the old "trim/lights stay visible" wording. The
Comet `shell.size() >= 2` assertion in `test_cockpit_visibility.gd` still holds
(the Comet is all-`colormap`, so its classification is unchanged).

### What the gate must confirm (later, in the main session)

1. `--headless --import .` clean (zero `SCRIPT ERROR` / `Parse Error`).
2. `test_gtr_r35_sightline.gd` GREEN (both tests).
3. `test_cockpit_visibility.gd` GREEN (all original + 2 new tests).
4. `test_gtr_r35_interior.gd` and `test_gtr_r35.gd` GREEN (offset is a pure
   translation; glass/taillight pins untouched).
5. Full suite: no new failures vs the known baseline (only the perf-gate
   wall-clock flake and the 20-orphan count are pre-existing).

### Open risks / uncertainty

- **Step-0 in-game capture was SKIPPED** (the game must not run during this
  work). If the black mass were the windscreen pane *itself* rather than
  interior geometry, the fix would need the eye/interior decoupling of §6-risk 1
  — the offline model rules that out geometrically (the glass is entirely above
  the eye; §2.2) but only a capture can confirm it visually.
- **Thin margin:** `BinnacleHood` top is `−0.0536`, only 3.6 mm below the
  `−0.05` threshold. The analytic `BoxMesh` AABB is exact so this is expected to
  pass, but it is the tightest node; if the gate red-flags it, nudge the offset
  to `−0.34` (top `−0.0736`).
- **Variant A moves the whole cabin** (seat, door cards, A-pillars) down with the
  cluster (§6-risk 3). Accepted per §3 D4; switch to Variant B only if a playtest
  shows the cabin now reads wrong.
- **Pre-existing edge case left unchanged:** the R35's tyre material is named
  `Tyre` (British spelling), which contains neither `tire` nor `rim`, so
  `_material_cockpit_role` classifies `Tyre_*` as `SHELL` (hidden in cockpit).
  This is **pre-existing** (the old code had the same gap) and is out of scope
  here; noted for a future cleanup (add `tyre` to the wheel branch if it ever
  matters visually).
- The working tree also carries unrelated uncommitted work from prior sessions
  (glass tint / reverse glow); it was left untouched.

---

## 10. §9 EXECUTED — live verification, and a REAL pre-existing bug the new test caught (2026-10-17)

### Gate results (this box, GTX 970; headless, one Godot process at a time)

- `--headless --import .`: clean. The only `SCRIPT ERROR` line is the pre-existing
  Terrain3D addon one (`addons/terrain_3d/src/double_slider.gd:25`); everything
  else is the allowed "resources still in use at exit" / RID-leak noise.
- Targeted suites (T1 + its three sibling fix tasks), 108 cases:

  `Overall Summary: 108 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans`

  `test_gtr_r35_sightline.gd` is GREEN, so the §9 "thin margin" did **not** need
  the `−0.34` nudge (`BinnacleHood` at `−0.0536` is accepted as-is).

### The one failure — and it was a genuine bug, not a test bug

`test_cockpit_visibility.gd > test_wheel_assembly_stays_visible_in_cockpit`
(the new §5.2 test) failed at its starter-car half:
`starter_visual.get_node_or_null("Wheel_FL")` returned `null`.

Root cause, measured with a GLB JSON-chunk dump plus a headless instantiation
probe (both diagnostics lived in gitignored `reports/`):

| car glb | glTF scene roots | Godot instance root | wheel depth |
|---|---|---|---|
| `sports_coupe.glb` (starter / `DEFAULT_VISUAL`) | 1 (`SportsCoupe`) | `sports_coupe` → `SportsCoupe` → `Wheel_FL` | **2** |
| `muscle_car.glb` | 1 (`MuscleCoupe`) | wrapper → `MuscleCoupe` → `MCW_Rim_FL` | **2** |
| `rally_hatch.glb` | 1 (`RallyHatch`) | wrapper → `RallyHatch` → `Rim_LF`/`Tire_LF` | **2** |
| `nissan_gt-r_r35_2017.glb` | 43 | 43 direct children incl. `Wheel_FL` | 1 |
| `cc0_*.glb` (Kenney kits) | 5 | direct children incl. `wheel-front-left` | 1 |

Godot wraps a **single-root** glTF scene in an extra root node, so a wheel authored
as that scene's root node sits one level BELOW the instance root.
`CarVisuals.resolve_wheel_nodes()` only did
`visual_root.get_node_or_null(name)`, so for **14 of the 20 car GLBs** (every
single-root one — the starter car, muscle, rally) it returned `{}`: those cars'
wheels never span or steered, silently, in production. The test was right and the
production code was wrong.

Fix: `resolve_wheel_nodes()` now tries the exact name first and falls back to
`visual_root.find_child(name, true, false)` — depth-independent on purpose (no
behaviour change for the cars that already resolved). The test half was rewritten
to assert through that production seam
(`resolve_wheel_nodes(...).size() == 4`, then visibility/role on the resolved
node) rather than pinning an authoring depth it should not care about.
After the fix the same 108-case run is GREEN.

### Out-of-scope gap noted (NOT fixed here)

`WHEEL_GROUPS` has entries for only 7 car ids. The 11 licensed classics
(`bmw_m3_1988`, … , `volkswagen_golf_r_2010`) have NO entry, so they resolve no
wheel groups at all — a pre-existing gap unrelated to the nesting bug above.
Fixing it needs each car's real node names (a per-car GLB dump) and is a separate
task.

### Still playtest-only

The cockpit sightline (§1 acceptance) still needs a game-window capture. No Godot
*game* run was performed here (single-process rule, and the R35 visual is the
whole point of that capture).
