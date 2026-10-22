# UltraDrive — GT-R R35 Cockpit (First-Person) Improvement Plan

> **Written:** 2026-10-17 · **Author:** agent (research + plan) · **Status:** PROPOSED (nothing implemented)
> **Scope:** make the Nissan GT-R R35 **COCKPIT camera view** look production-quality.
> **Hard constraints honoured below:** no Godot runs performed by this plan; the plan itself
> modifies **no** game code or assets — it is a document. Verification is by `file:line`.
> **Predecessor docs:** `docs/plans/r35_cockpit_plan.md` (P0–P6, all marked EXECUTED
> 2026-10-09), `docs/plans/custom_interiors_plan.md`,
> `docs/plans/first_person_camera_plan.md`, `docs/plans/gtr_r35_lights_glass_plan.md`,
> `docs/plans/fix_gtr_windshield_glass.md`.

---

## 1. GOAL + verifiable acceptance criteria

**Goal.** The R35 cockpit is currently built entirely from near-black Godot primitives
(§2). It reads as "dark boxes". Replace the *static, non-animated* cabin trim with a
**pre-rendered, eye-accurate image composited into 3D space**, while keeping every
close-up element that must move or glow as real 3D. The result must look like a GT-R R35
cabin from the driver's eye, in every direction the cockpit camera can look, and must add
**no license debt**.

**Acceptance criteria** (each independently checkable; AC4/AC5 are the only ones that are
*not* numeric — see §5):

- **AC1 — Visual (screenshot review, not a unit test).** `tools/r35_cockpit_capture.gd`
  (exists; verified) produces `.vision/captures/r35_cockpit_forward.png`,
  `r35_cockpit_binnacle_stack.png`, `r35_cockpit_console.png`. A `gemini_vision.bat ask`
  critique against ≥2 real R35 interior reference photos must conclude: the dash shape,
  A-pillar rake, binnacle, console and materials are **recognisable as a GT-R R35**;
  no visible primitive "boxes"; no void/black holes when the view is yawed.
- **AC2 — Gates green.** `test_gtr_r35_interior.gd`, `test_gtr_r35_sightline.gd`,
  `test_gtr_cockpit_resources.gd`, `test_cockpit_visibility.gd`,
  `test_cockpit_interior.gd`, `test_cockpit_camera.gd`, `test_cockpit_hud.gd` all pass
  (run as shards via `tools/gdunit_parallel.py`, or per-suite; see §5).
- **AC3 — Perf/contract preserved.** `nissan_gt_r35_2017_cockpit.tscn` still contains
  **no** `OmniLight3D`/`SpotLight3D`/`DirectionalLight3D`, **no** `SubViewport`, and
  every `MeshInstance3D` still has `cast_shadow = 0`
  (`test_gtr_r35_interior.gd:56-81`, `:371-397`). Net new draw calls in the cockpit view
  ≤ **3**.
- **AC4 — No other car affected.** `interior_scene` for every non-R35 `CarConfig` is
  unchanged; the rig's default tree is untouched
  (`test_gtr_cockpit_resources.gd:63-107` stays green).
- **AC5 — No license debt.** Every new asset is **own work** or **CC0**, recorded in
  `assets/interiors/r35/License.txt`, matching the precedent
  `assets/cars/cc0/kenney_car-kit/License.txt` and the rejection of
  "Royalty Free" marketplace assets in `docs/plans/cc0_car_assets_plan.md:31-33`.

---

## 2. CURRENT STATE (verified)

### 2.1 The cockpit scene — why it "looks bad"

`scenes/vehicle/interiors/nissan_gt_r35_2017_cockpit.tscn` (617 lines) is authored
**entirely from `BoxMesh`/`QuadMesh`/`CylinderMesh`/`TorusMesh` primitives**, every
material near-black and barely self-lit:

| Evidence | Location |
|---|---|
| Base trim material: `albedo_color = Color(0.1, 0.1, 0.13, 1)`, `emission_energy_multiplier = 0.15` | `:3-8` |
| Leather/alcantara/carbon variants, all `0.028…0.075` grey, emission `0.15` | `:10-31`, `:76-88` |
| Crude trim bodies: `DashPad` (a `BoxMesh`) `:304-308`, `Dash` `:309-313`, `BinnacleHood` `:314-318`, `BinnacleBack` `:319-323`, `APillarLeft/Right` `:380-389`, `HeaderBar` `:390-394`, `DoorCardLeft/Right(+Amber)` `:395-414`, `ArmrestLeft/Right` `:415-424`, `CentreStackRiser` `:425-429` | `:304-429` |
| Root carries a `-0.32 m` Y "eye-below-roof" offset | `:301-302` |

There is **no interior geometry to fall back on**: `assets/cars/nissan_gt-r_r35_2017.glb`
is exterior-only (GLB dump in `docs/plans/gtr_r35_lights_glass_plan.md:50-55`).

### 2.2 The contracts any change must respect

- **Interior is loaded in EYE space.** `CockpitRig._load_interior()`
  (`scripts/vehicle/cockpit_rig.gd:266-281`) instantiates `CarConfig.interior.interior_scene`
  as child `"Interior"`, then `_remove_default_geometry()`
  (`:308-315`); the rig origin **is** the drive eye
  (`_sync_to_seat_anchor`, `:395-401`). Interior geometry must **not** be wrapped in
  `CAR_ORIENT` and must **not** be a child of `CarBody`
  (`:13-16`; `_apply_visual()` wipes `CarBody` children).
- **Eye ≡ rig ≡ interior origin.** `CockpitRig.seat_anchor_for()` (`:376-387`) is shared
  by the rig and by `CockpitCamera.get_seat_anchor()`
  (`scripts/camera/cockpit_camera.gd:148-159`).
- **Camera params.** FOV animates **60 → 68**
  (`cockpit_camera.gd:23-25`, `:265-266`); near plane **0.2 m** (`:86`); forward is
  **−Z** in eye space.
- **Look-around.** Right stick, `camera_orbit_*` actions, `apply_look()`
  (`cockpit_camera.gd:177-182`). **Pitch is clamped `[−0.5, +1.35]` rad**
  (`:45-46`) but **yaw is NOT clamped** — `view_basis = view_basis * Basis(Vector3.UP, _look_yaw)`
  (`:257`) with no limit, so the player **can yaw a full 360°**. This single fact
  drives the whole design decision in §3.
- **Config.** `resources/cars/nissan_gt_r35_2017.tres:67-70` — `interior` + seat overrides
  (`cockpit_seat_height 0.62`, `_forward 0.55`, `_lateral −0.36` = RHD).
  `resources/interiors/nissan_gt_r35_2017_cockpit.tres:8-11` — `interior_scene`,
  `trim_color 0.1,0.1,0.13`, `emission_energy 0.15`, `suppress_hud_dash = true`.
- **Shell/glass in cockpit view.** `CarVisuals.set_cockpit_view()`
  (`scripts/vehicle/car_visuals.gd:837`) hides the paint shell and sets windscreen glass
  alpha to `COCKPIT_GLASS_ALPHA = 0.18` (`:807`); role table `CockpitRole` (`:809`).
  Invoked from `CockpitRig.sync_shell_view()` / `_apply_shell_view()`
  (`cockpit_rig.gd:438-460`).
- **HUD.** `suppress_hud_dash = true` hides the 2D panel while keeping the screen
  `%Cluster` dimmed to 0.2 (`scripts/race/cockpit_dash.gd:27`, `:53`, `:120-130`).
- **Rig visibility.** The whole rig (and thus any interior child) is hidden unless the
  cockpit camera owns the viewport (`cockpit_rig.gd:406-412`) — so anything added inside
  the interior scene is automatically cockpit-only (chase/hood/orbit unaffected).

### 2.3 The gates that pin today's structure

- `tests/suites/test_gtr_r35_sightline.gd` — **the hard geometric gate.**
  Rule (`:113-131`): any `MeshInstance3D` whose eye-space AABB overlaps the forward wedge
  (`_overlaps_forward_wedge`, `:95-104`, wedge `tan = 0.3`) must **not** straddle the eye
  band `(−0.05, +0.05)` (`_straddles_sightline`, `:108-111`); i.e. `top ≤ −0.05` **or**
  `bottom ≥ +0.05`. Plus `test_r35_cluster_tops_are_below_the_horizon` (`:135-146`) names
  `BinnacleHood`, `BinnacleBack`, `SteeringWheel`.
- `tests/suites/test_gtr_r35_interior.gd` — 27 test funcs pinning node **names**
  (`:41-52`), shadowless/emissive/light-free (`:56-81`), RHD (`:82-96`), wheel torus
  radius `[0.16, 0.20]` + `PaddleLeft/PaddleRight` + spin seam (`:296-328`), twin screens
  + console controls by name (`:337-367`), MFD emission swap (`:402-438`), seat-anchor
  maths (`:439-543`).
- `tests/suites/test_gtr_cockpit_resources.gd` — pins the **default** rig tree and
  `InteriorResource` defaults (`:39-107`); must stay green (AC4).
- `test_cockpit_visibility.gd`, `test_cockpit_interior.gd`, `test_cockpit_camera.gd`,
  `test_cockpit_hud.gd` — the surrounding cockpit/HUD contracts
  (`docs/plans/gtr_r35_lights_glass_plan.md:630-632` lists the affected set).

### 2.4 Existing verification tooling (reuse it)

- `tools/r35_cockpit_capture.gd` — **already exists.** Boots `test_track.tscn`, swaps the
  player car to the R35 config, **rebuilds the interior**, cycles the C-camera to COCKPIT,
  holds a right-stick look sweep (`apply_look(-0.9, 0.18, delta)`, `:83-85`), and saves 3
  PNGs to `.vision/captures/` (`:1-11`, `:105-113`). This is the AC1 harness.
- `gemini_vision.bat` (project root) — uploads those PNGs + reference shots and returns a
  structured critique (`.vision/gemini/feedback_*.md`). >5 images per call is refused and
  ~1-in-3 calls fail transiently; re-run. Use for AC1.
- Window/aspect: `project.godot:19-23` — 1920×1080, `stretch/mode="canvas_items"`,
  `stretch/aspect="expand"`.

---

## 3. DESIGN DECISIONS

### 3.1 The four options

| # | Option | Why it looks good | Cost / failure mode | License |
|---|---|---|---|---|
| **i** | **Improve the modelled cockpit in Blender** (real 3D cabin, textured) | Correct parallax in **every** direction, incl. full 360° yaw; no compositing tricks; reusable for other cars | **L effort** (dash, console, seats, doors, UVs, materials); needs the Blender MCP path; risk of re-landing on "crude" if time-boxed | own work |
| **ii** | **Photo/billboard cockpit** — a real/photographic interior image on a **screen-aligned** quad, windscreen alpha-cut | Fastest, 1 draw call, photoreal | **Broken by design here:** a screen-aligned quad is glued to the screen, so a 360° yaw look (`:257`) slides *nothing* — the cabin rotates with your head. Wrong. Also needs a real R35 photo | real photo = **copyrighted** |
| **iii** | **Pre-rendered high-quality render composited** — own render of the cabin from the exact drive eye, mapped onto **eye-anchored** 3D carrier geometry | Eye-exact projection (parallax error is 0 at the eye and ≤ ~2° under the ≤0.035 m feel/0.013 m shake offsets); no photo licensing; can be re-rendered whenever the cabin is redesigned | Needs a Blender render pass; a *flat* single plane still has flat parallax on hard yaw unless the periphery is also carried | **own work** |
| **iv** | **Third-party free/CC0 interior model** | Real 3D → correct parallax; possibly zero cost | R35-specific interiors are **not** CC0; a generic CC0 car interior won't match the R35 and would need re-modelling anyway (≈ option i but with a wrong-silhouette starting point); integration + full re-test | CC0 required; unlikely to exist |

### 3.2 Chosen: **(iii), implemented eye-anchored and staged**

**Chosen approach — "own-work pre-rendered cabin, composited onto eye-anchored 3D
carriers" (option iii), staged in three phases, keeping all animated/live elements as
real 3D.**

Rationale:

1. It is the **only** option that is simultaneously (a) not blocked by the 360° yaw
   (because the carrier geometry is anchored in **eye/car space**, not screen space), and
   (b) carries **no license debt** (option ii needs a real photo; option iv has no
   suitable CC0 R35 interior).
2. It is **M effort**, not the L of option i, because the static cabin is *rendered*, not
   *modelled to production topology* — Blender is used as a renderer, not as a DCC
   authoring pass with UV/LOD/optimisation work.
3. It **reuses** the existing eye contract (`seat_anchor_for`, §2.2) so there is no new
   source of truth and no change to `cockpit_rig.gd`'s loading path.
4. Staging lets Phase 1 ship the dominant win (the dash) with **zero** gate changes and
   **zero** transparency risk.

**Trade-offs, stated plainly (and mitigated):**

- **Parallax.** A pre-rendered shell has no true parallax; error is 0 at the exact eye and
  grows only with eye translation. Max excursion is `STEER_LATERAL_CAP 0.035 m` +
  `SHAKE_AMP_MAX 0.013 m` (`cockpit_camera.gd:50-52`) ≈ 0.05 m. With a shell radius of
  1.2 m the worst-case angular error is `atan(0.05/1.2) ≈ 2.4°` — below perception for
  dark trim. Verdict: acceptable. (Option i has zero error; this is the price of M vs L.)
- **Resolution budget.** An equirectangular panorama wastes horizontal texels on the
  periphery. Mitigation is the staging itself: the **forward dash gets a dedicated
  high-res perspective quad** (Phase 1); the periphery uses the lower-res panorama
  (Phase 2), where sharpness matters least.
- **Flatness on hard yaw.** Looking 90°/180° shows the panorama at its fixed radius. Doors
  and the rear bulkhead read as a cabin, not a void, but with no depth change. This is the
  one honest visual concession; §3.3 defines the escalation gate if a review rejects it.

### 3.3 Escalation gate (documented, not vague)

If, after Phase 2, the AC1 review judges hard-yaw flatness unacceptable, **escalate to
option (i)**: treat the Phase-1/2 renders as the art-direction target and re-author the
cabin as real 3D in Blender (the renders become the modelling reference). Record the
decision and the review screenshots in this doc's STATUS block.

### 3.4 Two sub-decisions the prompt asks for explicitly

- **Steering wheel: animated, kept as real 3D.** The rig already spins the cabin wheel
  from `get_drive_info()` via `_sync_steer_visual()` (`cockpit_rig.gd:98-104`) against the
  `STEER_VISUAL_MAX_RAD_CABIN = 2.2` seam (`:38`), and the spin behaviour is pinned by
  `test_gtr_r35_interior.gd:98-122`, `:296-328`. **The cockpit image must therefore
  exclude the wheel** — a baked wheel would be a lie. The wheel subtree (`WheelHub`,
  `SpokeTop/Left/Right`, `PaddleLeft/Right`, `Badge`, `FlatBottom`) stays exactly as-is.
- **Gauges/needles: live 3D, not baked.** The binnacle already has real needles and a
  shift-light strip driven by `_sync_gauges()` / `apply_gauge_drive_info()`
  (`cockpit_rig.gd:109-163`) and a real MFD (`set_mfd_mode`, pinned by
  `test_gtr_r35_interior.gd:402-438`). The 2D `%Cluster` is kept dimmed to 0.2 as the
  speed/gear/rpm readout (`cockpit_dash.gd:27`; `suppress_hud_dash = true`). So **nothing
  that animates is baked** — the image covers only static trim.

### 3.5 Licensing position

- **Chosen source = own work.** Render the cabin ourselves in Blender (the Blender MCP
  bridge is available: Blender 4.5.13, `mcp-for-blender`, port 9876 — `AGENTS.md` /
  `docs/...` D4 section). Record authorship in `assets/interiors/r35/License.txt`.
- **Rejected:** any real R35 interior photograph (copyright), and marketplace
  "Royalty Free" packs (rejected precedent, `cc0_car_assets_plan.md:31-33`).
- **Acceptable alternative if the user supplies one:** a user-owned/licensed photo or a
  CC0-equivalent recreation, in which case the same pipeline (Phase 1/2) consumes it and
  `License.txt` records the provenance.

### 3.6 Exact node dispositions (replaces the crude primitives)

| Scene node (`nissan_gt_r35_2017_cockpit.tscn`) | Disposition | Reason |
|---|---|---|
| `DashPad` `:304-308` | **Repurpose → Phase-1 billboard quad** (rename mesh, keep the node name) | It is already the dash slab; its transform `(0, −0.24, −0.80)` is the billboard anchor |
| `Dash` `:309-313` | Keep as a thin 3D lip below the billboard top edge | Preserves the `Dash` anchor that `test_..._anchors` (`:49`) requires |
| `BinnacleHood` `:314-318`, `BinnacleBack` `:319-323` | **Keep** | They frame the live 3D cluster; pinned by `:139` of the sightline test |
| `APillarLeft/Right` `:380-389`, `HeaderBar` `:390-394` | **Phase 2:** replace with panorama-derived quads at the same transforms | Crude boxes → baked, correctly-raked pillars |
| `DoorCardLeft/Right(+Amber)` `:395-414`, `ArmrestLeft/Right` `:415-424` | **Phase 2:** replace with panorama-derived quads (keep node names/transforms — `:88-93` requires `DoorCardRight.x < 0`) | Same |
| `CentreStackRiser` `:425-429` | **Keep** (Phase 1 keeps the console 3D for now) | `:90-93` requires `riser.x > 0` |
| `MfdFrame` `:430-434`, `NavScreen` `:435-439` | **Keep** | Emissive screens; pinned by `:337-397` |
| `SteeringWheel` subtree `:440-483` | **Keep unchanged** | Animated; §3.4 |
| `GaugeRPM/Speed/MFD` `:324-376` | **Keep unchanged** | Live needles; §3.4 |
| `SteeringColumn` `:485-489`, `Vent*` `:490-539`, `CentreConsole` subtree `:541-617` | **Keep** | Small 3D detail that reads *better* in 3D than baked; §3.5 detail |
| `SeatRoot` `:377-379` | **Keep** | Anchor used by seat maths |

Net effect: Phase 1 swaps **one** mesh (`DashPad`) for a textured quad and leaves every
pinned node intact — hence almost no test churn. Phase 2 swaps the four big lateral/overhead
slabs and adds one panorama shell.

---

## 4. IMPLEMENTATION STEPS

> Ordered. Every step lists exact files / nodes / functions / line anchors. Nothing here
> has been executed; this is the work list.

### Phase 0 — preconditions (no code)

1. Confirm the art bar: collect **≥2 CC0/own reference images** of a GT-R R35 driver's
   view (dashboard, binnacle, console) as the AC1 target. Store them under
   `assets/interiors/r35/reference/` (own/downloaded-CC0 only).
2. Confirm the Blender route: Blender 4.5.13 via the `mcp-for-blender` bridge, or a
   scripted `--background --python` render (deterministic, no GUI needed).
3. Confirm the license posture with the user (§3.5) and create
   `assets/interiors/r35/License.txt` (own-work statement; copy the shape of
   `assets/cars/cc0/kenney_car-kit/License.txt`).

### Phase 1 — forward dash billboard (the big win; gate-safe; no alpha)

4. **Render the Phase-1 texture (Blender).**
   - Build/borrow a *static trim only* cabin: dash top + cowl + windscreen base, centre
     console top, door tops, A-pillar lowers, seat edges — **exclude** the steering wheel,
     gauge pods, MFD, nav screen, vents and console controls (those stay real 3D; §3.4).
   - Camera: at the **exact drive eye** used in-game. Eye = rig origin; get its in-car
     coords from `CockpitRig.seat_anchor_for()` with the R35 config
     (`cockpit_seat_height 0.62`, `_forward 0.55`, `_lateral −0.36` —
     `nissan_gt_r35_2017.tres:68-70`) plus the root offset `−0.32 Y`
     (`...cockpit.tscn:302`). **Do not guess — read the values through the shared helper.**
   - Vertical FOV = **68°** (the camera's maximum, `cockpit_camera.gd:24`), so the texture
     covers the widest case; at FOV 60 the quad over-covers and the extra is off-screen.
   - Aspect/resolution: render **16:9 at 4096×2304**, downscale to **2048×1152** for the
     texture. Include a **10% bleed margin** on all sides to absorb non-16:9 windows
     (`stretch/aspect="expand"`, `project.godot:23`).
   - Output: `assets/interiors/r35/r35_dash_forward.png` (+ Godot `.import`).
5. **Author the quad in `nissan_gt_r35_2017_cockpit.tscn`.**
   - Repurpose `DashPad` (`:304-308`): change its mesh to a `QuadMesh` (or `PlaneMesh`)
     sized **width 2.00 m, height 0.50 m**, transform = plane at **z = −0.80**, spanning
     **y ∈ [−0.55, −0.05]**, x centred. The **top edge must sit at ≤ −0.05 m** (this is what
     keeps `test_gtr_r35_sightline.gd` green with **no** exemption — see §5.2).
   - New `StandardMaterial3D` `mat_dash_billboard`: `albedo_texture = r35_dash_forward.png`,
     `shading_mode = SHADING_MODE_UNSHADED`, `albedo_color = Color(1,1,1,1)`,
     `cast_shadow = 0`. **Author the image pre-graded to the target in-game night
     brightness** so no runtime dimming (and hence **no `cockpit_rig.gd` edit**) is needed.
     (Optional future work: per-car dimming via `InteriorResource.emission_energy` — out of
     scope here to keep `cockpit_rig.gd` untouched, per
     `gtr_r35_lights_glass_plan.md:696`.)
6. **Phase-1 gate check (local, no full suite):** run only
   `test_gtr_r35_sightline.gd` + `test_gtr_r35_interior.gd` + `test_gtr_cockpit_resources.gd`
   (§5.1). Expect: sightline green with no edits; interior green except any assertion that
   inspected `DashPad`'s old `BoxMesh` (see §5.2).

### Phase 2 — panoramic shell for the periphery (adds the one documented exemption)

7. **Render the Phase-2 panorama (Blender).**
   - Same trim-only cabin, same eye, but an **equirectangular 360°×180°** render.
   - Resolution **4096×2048** (≈11.4 px/° horizontally — acceptable for periphery; sharpness
     ahead is Phase 1's job).
   - Bake the **windscreen opening as fully transparent (alpha = 0)** so the world shows
     through; keep A-pillars, header, doors, roof, rear bulkhead, floor **opaque**.
   - Output `assets/interiors/r35/r35_cabin_pano.png` (RGBA).
8. **Add the shell to the scene.**
   - New node `CockpitShell` (`MeshInstance3D`) as a direct child of `NissanGTR35Cockpit`,
     identity transform, `SphereMesh` **radius 1.2 m** with **inverted normals**
     (`flip_faces = true`) so it renders from inside; `cast_shadow = 0`.
   - `ShaderMaterial` `mat_cabin_pano` sampling the equirect by view direction, i.e.
     `uv = vec2(atan(-dir.z, dir.x) / (2π) + 0.5, acos(dir.y) / π)` in a small
     `spatial` shader; `render_mode cull_front, unshaded;` and
     `transparency = TRANSPARENCY_ALPHA_SCISSOR` with `alpha_scissor_threshold ≈ 0.5` on
     the sampled alpha. Rationale for **scissor, not blend**: the cut windscreen is a
     *hard* silhouette, and alpha-scissor renders in the **opaque** pass (depth-written), so
     — unlike alpha blending — it needs **no** render-order fix, and the 3D wheel/cluster
     (at 0.46 m / 0.70 m, in front of the 1.2 m shell) occlude the shell correctly through
     the ordinary depth test. **No `no_depth_test` is required** (this is a deliberate
     refinement over an earlier draft).
   - Put `CockpitShell` in a group **`cockpit_billboard`** (used by §5.2's exemption).
   - Add the panorama-derived `APillarLeft/Right`, `HeaderBar`, `DoorCardLeft/Right`,
     `ArmrestLeft/Right` quads — **keep the existing node names and transforms**
   (`:380-424`, `:88-93`) — sampling sub-rects of the same panorama; these are **opaque**
   quads and, by their transforms, are outside the forward wedge or above/below the band
   (§5.2 shows they pass unmodified).
9. **Remove the replaced primitive meshes** (`APillar*`, `HeaderBar`, `DoorCard*`,
   `Armrest*` bodies) so no crude box remains; leave `Dash`.
10. **Phase-2 gate check:** full R35 set + `test_cockpit_visibility.gd` (+ the suite list in
    §5.1). Only `test_gtr_r35_sightline.gd` needs the one documented edit in §5.3.

### Phase 3 — optional escalation (only if §3.3 fires)

11. Re-author the cabin as real 3D in Blender (option i), using the Phase-1/2 renders as
    the reference target; swap `CockpitShell`/quads for the 3D cabin; keep the wheel/gauges.
    Re-run §5.

### Asset specification summary (the prompt's "image asset requirements")

| Asset | Resolution | Camera | Aspect / FOV | Cut-out | License |
|---|---|---|---|---|---|
| `r35_dash_forward.png` (Phase 1) | 4096×2304 → 2048×1152 | at the drive eye (derived via `seat_anchor_for`) | 16:9, vertical FOV **68°**, +10% bleed | none (opaque) | own work |
| `r35_cabin_pano.png` (Phase 2) | 4096×2048 (RGBA) | same eye | 360°×180° equirect | **windscreen = alpha 0** | own work |
| `assets/interiors/r35/License.txt` | — | — | — | — | own-work statement |

**User-supplied input required:** (a) approval/ownership confirmation for the render route,
or a user-owned/CC0 photo as an alternative source; (b) ≥2 reference images defining the
art bar; (c) acceptance of the §3.2 parallax trade-off. Nothing else — the geometry, the
eye point and the FOV all come from the repo.

---

## 5. TEST PLAN

### 5.1 Suites to run

Per-suite (fast, prefer while iterating):
`test_gtr_r35_sightline.gd`, `test_gtr_r35_interior.gd`, `test_gtr_cockpit_resources.gd`,
`test_cockpit_visibility.gd`, `test_cockpit_interior.gd`, `test_cockpit_camera.gd`,
`test_cockpit_hud.gd`.
Note: `-a` is **repeatable but not comma-joinable** (comma-joined paths silently run
**zero** tests and exit 0); run one `-a` per suite or use the sharded runner. Full gate:
`py tools\gdunit_parallel.py -j 4` (all artifacts under `reports/parallel/`; exit 0 clean,
1 = real failures — trustworthy, 2 = false-green).

### 5.2 Phase-1 test impact — expected **zero** edits

- **Sightline gate stays green with no change.** The billboard is `z = −0.80`, spans the
  forward wedge, and has **top ≤ −0.05 m** → `_straddles_sightline` is `false`
  (`test_gtr_r35_sightline.gd:108-111`). The Phase-2 lateral quads are outside the wedge
  (`|x| > 0.3·|z|`) or above `+0.05`/below `−0.05` by construction.
- **Anchor/contract tests stay green** because Phase 1 keeps every pinned node name and the
  wheel/gauge subtrees (§3.6).
- **Only possible Phase-1 edit:** an assertion that reads `DashPad`'s mesh *type* (a
  `BoxMesh`) — if one exists, update it to accept the `QuadMesh` + textured material.
  `test_gtr_r35_interior.gd:41-81` currently checks names, `cast_shadow`, and the **wheel's**
  material only, so this is likely a no-op; confirm before claiming it.

### 5.3 Phase-2 test edits (exactly one gate needs a change)

- `test_gtr_r35_sightline.gd::test_r35_interior_no_mesh_straddles_the_sightline`
  (`:115-131`): **skip meshes in the `cockpit_billboard` group.** Justification: the gate's
  AABB test (`_eye_aabb`, `:69-90`) cannot see alpha, and the shell's occlusion model is
  per-pixel (alpha-scissor), not per-AABB. **Do not loosen** `SIGHTLINE_BAND` (`:33`) or
  `SIGHTLINE_WEDGE_TAN` (`:30`).
- **Add a compensating test in the same file** (this is what earns the exemption):
  `test_r35_billboard_alpha_cut_opens_the_forward_wedge` — assert that `CockpitShell`
  exists, is in group `cockpit_billboard`, uses a `ShaderMaterial`
  (`transparency == TRANSPARENCY_ALPHA_SCISSOR`), has a non-null `albedo_texture`/pano
  sampler, `cast_shadow == OFF`, and that its radius covers the forward wedge at the
  camera's max FOV (a pure geometric assertion over the mesh AABB + FOV constants).
  **Be explicit in a comment that the *pixel* claim ("the windscreen is actually
  see-through") cannot be asserted headless** (dummy driver renders black) and is instead
  covered by AC1 (§5.4).
- Any `test_gtr_r35_interior.gd` assertion that inspected a removed `APillar*`/`HeaderBar`/
  `DoorCard*`/`Armrest*` mesh: update to the new opaque-quad equivalent; keep the
  `DoorCardRight.x < 0` / `CentreStackRiser.x > 0` RHD assertions intact (`:88-93`).
- `test_gtr_cockpit_resources.gd` must remain untouched (default rig tree, AC4).

### 5.4 Visual quality — verified by screenshot, **not** by a numeric test

Numeric gates can prove geometry rules; they cannot prove "looks like a GT-R". So AC1 is a
**screenshot workflow**, reusing existing tooling:

```
call godot_path.bat & !GODOT_EXE_CONSOLE! --path . -s res://tools/r35_cockpit_capture.gd
gemini_vision.bat ask --image .vision/captures/r35_cockpit_forward.png ^
  --image .vision/captures/r35_cockpit_binnacle_stack.png ^
  --image .vision/captures/r35_cockpit_console.png ^
  --image assets/interiors/r35/reference/<ref>.jpg ^
  --prompt "Compare this game cockpit to the real GT-R R35. Is the dash/binnacle/console recognisable? List concrete mismatches." --timeout 400
```

- `r35_cockpit_capture.gd` already holds the right-stick **look sweep**
  (`apply_look(-0.9, 0.18, delta)`, `:83-85`) so `binnacle_stack.png` proves the yawed view
  is coherent (AC1's "no void" clause). Its docstring mandates: **windowed run, not
  `--headless`** (dummy driver renders black), and `APPDATA` set to a project-absolute dir.
- ≤5 images per `ask`; ~1-in-3 calls fail transiently — re-run; a <100-char reply is an
  error blob. Append the verdict to `.vision/analysis.md`.

### 5.5 Regression checklist before shipping

- AC2 suite list green (5.1). · AC3 light/SubViewport/shadow contract green
  (`:56-81`, `:371-397`). · AC4 `test_gtr_cockpit_resources.gd` green. · AC5
  `License.txt` present. · AC1 screenshot review passed and saved.

---

## 6. RISKS / GOTCHAS

- **Aspect / FOV scaling.** The cockpit FOV animates 60→68 (`cockpit_camera.gd:23-25`) and
  the window uses `stretch/aspect="expand"` (`project.godot:23`), so the 3D view widens
  horizontally on ultrawide. If the billboard/panorama is calibrated only for 16:9 it will
  under-cover on 21:9+ and reveal un-textured edges. **Mitigations:** render the Phase-1
  texture at FOV 68 (the max) with **10% bleed**; for the panorama, an equirect sphere
  covers *all* aspects by construction; keep the A-pillar/door quads overlapping the
  billboard's left/right edges. If the ±4° FOV animation is judged to skew the billboard
  perspective, the option (deferred, needs an export) is a per-car `cockpit_billboard_fov`
  that pins the camera FOV while the billboard is active.
- **Clipping / near plane.** Near plane is **0.2 m** (`cockpit_camera.gd:86`). Every added
  quad/shell must sit **beyond** it (billboard `z = −0.80`, shell `r = 1.2` are safe).
  Keep any new geometry at `|z| > 0.2` or it will be clipped away at the eye.
- **Transparency order (the trap a naive billboard falls into).** A *blended* full-frame
  overlay would need explicit ordering vs the alpha-0.18 windscreen glass
  (`car_visuals.gd:807`) and could sort wrong. **Chosen fix: `TRANSPARENCY_ALPHA_SCISSOR`**
  (opaque pass, depth-written, hard cut) — no ordering, plus correct occlusion by the 3D
  wheel/cluster. Do **not** reach for `no_depth_test=true`; it is unnecessary here and would
  let the shell draw over the wheel.
- **Sightline gate.** The panorama shell **will** trip
  `test_r35_interior_no_mesh_straddles_the_sightline` (one big AABB). That is expected and
  handled **once** in Phase 2 by a group-based skip + a compensating assertion (§5.3).
  Phase 1 deliberately needs **no** gate change. Never widen `SIGHTLINE_BAND`/`WEDGE_TAN`.
- **Look controls.** `apply_look()` is unchanged; because the carriers are in the **rig**
  (eye/car space), yaw sweeps across them like a real cabin. **Yaw is unclamped**
  (`cockpit_camera.gd:257`) → this is exactly why a *screen-aligned* billboard (option ii)
  is unacceptable and why Phase 2 exists. Pitch clamps at `[−0.5, +1.35]` (`:45-46`); at
  max up-pitch the shell (not the roof quad) must be what's seen — verify in the capture
  sweep. No change to `orbit_camera.gd`'s C-cycle is needed (`scripts/camera/orbit_camera.gd`,
  CHASE→ORBIT→HOOD→COCKPIT).
- **Other cars.** The interior loads only when `CarConfig.interior != null`
  (`cockpit_rig.gd:266-281`); all new nodes live **inside** `nissan_gt_r35_2017_cockpit.tscn`,
  so no other car can be affected. Do **not** touch `cockpit_rig.tscn` (the literal default
  tree pinned by `test_gtr_cockpit_resources.gd:63-107`).
- **The `-0.32 m` root offset.** `NissanGTR35Cockpit` carries `transform = ... (0, −0.32, 0)`
  (`...cockpit.tscn:301-302`). Any hand-authored quad transform must be authored **relative
  to that**, or it lands 0.32 m too high. Derive all placements from the existing node
  transforms where possible.
- **Documentation conflict.** `docs/plans/gtr_r35_lights_glass_plan.md:696` says "**Do not
  edit `scripts/vehicle/cockpit_rig.gd` or the R35 interior scene**." That instruction is
  scoped to *that* plan's goal (preserving the glass contract), and Phase 1 here honours it
  by keeping `cockpit_rig.gd` untouched; the R35 -> *interior scene* is necessarily edited
  (that is the deliverable). Record the supersession in this doc's STATUS block.
- **GDUnit conventions.** Warnings are errors (type every `var`; no
  `var x := returns_Variant()`); vector `is_equal_approx` needs a same-type approx arg;
  free managed nodes in `after_test`; use `%GODOT_EXE_CONSOLE%`; a suite **aborts at its
  first failure**, so check the executed-case count against the file's `func test_` count
  before trusting a green.
- **`tools/r35_cockpit_capture.gd` must run windowed**, with `APPDATA` set to a
  project-absolute path (never C:) — see `AGENTS.md`.

---

## 7. DO NOT TOUCH

Explicitly out of scope; do not modify while implementing this plan:

- **Barcelona track materials** — `scenes/tracks/**` materials, terrain shaders and
  track-specific `.tres` (any change alters the reference circuit's look).
- **Race menu UI** — `scenes/ui/race_menu*`, `scripts/ui/race_menu*.gd`.
- **Race HUD / post-race** — `scenes/ui/hud.tscn`, `scripts/race/race_ui.gd`,
  `scenes/ui/race_results*`, `scripts/race/race_results*.gd` (except where a suite is
  re-run, not edited).
- **Speed-trap HUD** — the speed-trap overlay/HUD scripts and scenes.
- **Plugins** — `addons/**` (incl. `addons/gdUnit4`), `plugins/**`,
  `.opencode/plugins/**` (the vision bridge).
- Also **not** in scope (adjacent, mentioned only to prevent scope creep):
  `cockpit_rig.gd`'s loading/visibility path, `cockpit_camera.gd`'s look/FOV behaviour,
  `orbit_camera.gd`'s C-cycle, `car_visuals.gd`'s glass/role tables
  (`COCKPIT_GLASS_ALPHA`, `CockpitRole`), and `cockpit_rig.tscn`'s default tree.

---

*Plan ends. No code or assets were modified to produce it.*
