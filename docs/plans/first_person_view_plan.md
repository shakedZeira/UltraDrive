# UltraDrive — First-Person / Cockpit View (Research-Backed Plan)

Purpose: add a **cockpit (driver's-eye) camera** as a 4th mode in the chase/orbit/
hood C-cycle — built on the existing hood-cam rig, per best-in-class racing practice
(research digest in `docs/research/first_person_view_research.md`, all claims citable).
Cockpit is a *feature/reward view*, never the onboarding default (chase stays that).
Every work item follows the house plan style (Goal / Today vs Target / Work /
**Acceptance test gate** / Effort / Depends-on / Quick-win) + a **Sub-agent**
delegation brief (§ Sub-agent execution playbook). All gates run via the AGENTS.md
headless recipe; nothing ships without its suite green. **Plan `.md` is never committed.**

Sources: `docs/research/first_person_view_research.md` (§1 industry split, §2 FOV
conventions, §3 camera-feel rig, §4 wheel/hands tiers, §5 XAG-117 accessibility,
§6 HUD/dash/mirrors, §7 Godot facts gotchas, §8 hood-cam validation, §9 gaps),
`docs/ROADMAP.md` ("no tech ceiling"), AGENTS.md.

## Baseline

- **592 test cases green today** (`/c:"Overall Summary:" _gdunit.txt` — AGENTS.md's
  "263" line is stale; the runner output is truth). 1 pre-existing **flaky** failure:
  `res://tests/suites/test_hud_gauge.gd:59` (`test_tachometer_needle_tracks_dropping_rpm`,
  frame-delta-sensitive on this laptop, unrelated to camera work). Gate target:
  **≥ 605** with `0 errors / 0 failures / 0 flaky` (S14 hood suite takes it to 597;
  this plan adds ≈ 8+ more cockpit tests) — see Reconcile note at end.
- Cameras today (C-cycle in `scripts/camera/orbit_camera.gd`, `_apply_mode()`):
  **chase** (`chase_camera.gd`, lerp-follow + speed FOV 70→75) → **orbit**
  (right-stick free cam) → **hood** (`hood_camera.gd`, rigid bolt + FOV 70→75 +
  bounded speed bob). `world_driver.gd._is_forward_view()` feeds windshield droplets
  (chase OR hood). Scenes with Chase+Orbit+Hood wired: `open_world_root.tscn`,
  `test_track.tscn`, `mountain_pass.tscn`. `test_vehicle_physics.tscn` has chase only.
- **Car shell**: `player_car.tscn` → `CarBody` → BodyRig swaps exterior-only GLBs
  per active car. **No interior geometry exists today** — a camera inside a closed
  mesh (default cull_mode=Back) sees through a hollow shell. This is the biggest
  scope lever in the plan (F1-vs-F3).
- Settings pattern to reuse: `scripts/ui/settings_menu.gd` (QUALITY_PRESETS ladder +
  `apply_to_scene_tree` + `default_quality_preset` hardware detect).
- HUD cluster to optionally mirror/tune in-cockpit: `%Cluster` in `scenes/ui/hud.tscn`
  (tachometer/speed/gear driven by `race_ui.gd` from `car.get_drive_info()`
  `vehicle_physics.gd:457`; car also exposes `get_steer_angle()` :448, `get_throttle()` :451,
  `get_speed_kmh()` :439).

---

## § Sub-agent execution playbook (house rules)

- **One `general` sub-agent per work item.** Its prompt = this item's Goal + Today-vs-
  Target + Work + **Acceptance test gate** text **verbatim**, plus these guardrails:
  - Repo root is `C:\Users\IMOE001\Desktop\Shaked Projects\UltraDrive\UltraDrive`
    (res://). **Godot = `C:\Godot\Godot_v4.7.2-stable_win64.exe`** (NOT `D:\...` — that
    is the GTX970 reference box; it does not exist on this laptop).
  - TAB indentation in `.gd`; GDUnit treats GDScript warnings as errors (no
    `var x := <Variant-return>`; give explicit types). Vector `is_equal_approx` needs a
    SAME-TYPE approx arg (Vector3 with Vector3). Free managed nodes in `after_test`.
  - Public APIs stay backward compatible. Never `git add -A`/`git add docs/`. Stage
    only the touched source/test/scene files. Never stage `*.uid`. Commit with the
    repo identity (existing git env, `shaked zeira <shakedzeira@gmail.com>`).
  - Verify every gate via the AGENTS.md headless recipe (import probe grep for
    `SCRIPT ERROR|Parse Error|Failed to load` = zero, THEN the GDUnit `-s` run with
    `--ignoreHeadlessMode` AFTER the tool-script path).
- **Expected return:** files touched, test names, the GDUnit `Overall Summary:` line
  (before/after counts), commit hash + subject, any deviations + why.
- **Parent re-verification:** after each sub-agent returns, the parent re-runs the
  probe + full suite itself before closing the item.

---

## 1. Cockpit camera rig — `scripts/camera/cockpit_camera.gd` (fourth C-mode)

- **Goal:** driver's-eye cockpit view — rigid eye-anchor + **layered, strength-scaled
  feel** (speed FOV, steering lean, brake/accel pitch, speed micro-shake, look-into-
  turn), controlled, FPS-independent, toggleable. Wired into the C-cycle as mode 3.
- **Today vs Target**

  | | Today | Target |
  |---|---|---|
  | C-cycle | chase / orbit / hood (3 modes) (`orbit_camera.gd`) | chase / orbit / hood / **cockpit** (4 modes) |
  | Rig | hood rigid bolt, no interior, near=0.05 | driver-eye pivot + spring-damper feel rig, near≈0.2, `reset_physics_interpolation()` on switch |

- **Work** (F1):
  - New `scripts/camera/cockpit_camera.gd` `extends Node3D` (mirror hood_camera.gd
    skeleton — self-created Camera3D, `_update_camera(delta)` extracted for tests,
    `is_current_view()`, `set_view_active(bool)`, `debug_speed_kmh` hook).
  - **Eye anchor**: exportable eye offset (seat height/depth; GT7-style seat sliders
    are a stretch, start with one `seat_height`/`seat_forward` export pair). Copy body
    basis like hood, then apply feel offsets on a **copy** (shake must never feed back —
    Bevy rule); default near plane 0.2.
  - **Feel layers, each `0..1 strength` export** (defaults tuned small/arcade, all
    `delta`-scaled so they're FPS-independent, all ≈0 at rest):
    - speed FOV: `fov_min 60 → fov_max 68` clamp (tight-ish per research; the widen
      stays on chase/hood, cockpit stays mild), lerp `1-exp(-k*delta)` like chase.
    - steering lean: roll + lateral offset from `car.get_steer_angle()` (filtered,
      never raw — ACC steer-assist lesson), capped ~3°.
    - brake dive / accel squat: pitch from `get_throttle()` / brake state, capped ~2°.
    - speed micro-shake: noise × `speed/200` × strength, amplitude ≤ ~0.015 m — off at
      standstill (FH1 lesson: sails speed, nauseates if always on).
    - look-into-turn ("rotate with velocity" / look-to-apex-lite): yaw hint toward
      lateral velocity, strength ~0.2-style, smoothed.
  - `orbit_camera.gd`: add `CameraMode.COCKPIT = 3`, `cockpit_camera_path: NodePath`,
    cycle `CHASE→ORBIT→HOOD→COCKPIT→CHASE` in `cycle_mode_for_test()`;
    `_apply_mode()` retires all cams then activates exactly one; call
    `reset_physics_interpolation()` on the newly-active camera (1-frame jump fix);
    `_camera.layer_mask` parity note none needed (all cams same mask today).
  - `world_driver.gd._is_forward_view()`: add `or _is_view_owner("CockpitCamera")` so
    windshield droplets show in cockpit (first-person = windshield view).
  - Wire `CockpitCamera` node + `cockpit_camera_path` into `open_world_root.tscn`,
    `test_track.tscn`, `mountain_pass.tscn` — set `target` (`NodePath("%PlayerCar")`
    or `NodePath("..")`, matching each scene's existing chase Camera wiring).
    `test_vehicle_physics.tscn`: leave chase-only (its own test surface).
  - Player-scene authors note: cockpit cam works with **no interior yet** (F3 adds
    geometry) — safe to land rig first.
- **Acceptance test gate:** new `tests/suites/test_cockpit_camera.gd` (mirror
  `test_hood_camera.gd`):
  - eye-anchor: after N `_update_camera(1/60)` frames the cam position == computed
    eye anchor (+ feel offsets within tolerance) — rigid, no lag; re-snaps after
    target moves.
  - FOV: converges to `fov_min` at rest, toward `fov_max` at `debug_speed_kmh=200`,
    clamps to configured range.
  - feel bounded: with max strength + speed, total offset magnitude ≤ ~0.05 m, roll ≤
    ~4°, pitch ≤ ~3°; **all ≈ 0 when `strength=0` regardless of speed**; zero at
    standstill.
  - cycle deterministic: `cycle_mode_for_test()` ×4 → chase→orbit→hood→cockpit→chase,
    exactly one camera current each step (extend the S14 test's ownership asserts).
  - near plane == 0.2 and FPS-independence: same feel output for `_update_camera` at
    1/60 vs 1/30 (two drivers, assert equality within tolerance).
  - windshield gate: `_is_forward_view` true in chase, hood AND cockpit; false in orbit.
  - Full-suite `Overall Summary: ≥ 597 | 0 errors | 0 failures` (plus the pre-existing
    flake reconcile below).
- **Effort:** M • **Depends-on:** S14 hood rig (committed). • **Quick-win:** even
  without interior, a fixed-FOV eye-anchor readout is 90% of first-person immersion.

## 2. Interior cockpit geometry — dash/A-pillars/wheel proxy (asset decision)

- **Goal:** give the cockpit view something to be *inside* of: a light, cheap
  interior proxy (dash, A-pillars, optionally steering wheel) so the game stops
  looking through a hollow shell. Exterior-only GLBs + default backface culling =
  invisible shell from inside (research §7).
- **Work** (F2, scope-flexible): **decision first** — three options, pick with boss:
  - **F2a (recommended, cheapest): procedural interior.** A small `CockpitRig.tscn`
    scene (dash + windshield frame + flat shading, built from primitives/MultiMesh in
    the repo's prop-scatter style) placed inside `player_car.tscn` above `CarBody`,
    hidden whenever a non-cockpit cam is current (visibility toggle driven by
    `_is_forward_view` gate or a per-mode signal from `orbit_camera.gd`). No new
    art assets. Applied uniformly across all cars (ok: same generic dash).
  - **F2b: per-car interiors** authored in Blender via the CC0 lane — heavy, L-sized,
    likely future.
  - **F2c: no interior — hide-the-shell variant** (BeamNG driver cam): camera at eye
    point, body hidden while current. Cheapest but *not* a cockpit; good as the
    "Driver-no-wheel" accessibility tier (see F4) rather than the hero view.
- **Acceptance test gate:** new `tests/suites/test_cockpit_interior.gd`: `CockpitRig`
  instance is present as `CarBody` child after `player_car.tscn` instancing; toggle
  hides it in chase/hood/orbit and shows it in cockpit mode (assert `visible` flag
  per mode); rig has no script errors headless. Visual eyeball via `capture_game_window`
  (vision bridge) in cockpit mode — confirm dash/pillars frame the view, no shell
  hole, no z-fighting at near=0.2.
- **Effort:** F2a M / F2b L / F2c S • **Depends-on:** F1 • **Quick-win:** a dash-only
  floorboard + pillars reads "cockpit" for 10% of the asset cost.

## 3. Virtual driver hands + wheel (optional, controller-smoothed)

- **Goal (stretch, do NOT block F1/F2):** optional rendered wheel + hands that animate
  to *filtered* player steer input, rotation-limited (~arcade 180–360°, never 900° —
  ACC steer-assist lesson §4) — matching the "no two wheels" rule.
- **Work** (F3, deferred unless boss wants it): `VirtualWheel` node in `CockpitRig`
  driven by `car.get_steer_angle()` through a lerp filter; hide-on-pad=false option;
  charge: one low-poly wheel + two glove hands (procedural).
- **Acceptance test gate:** steer animation bounded (|rotation| ≤ configured lock),
  smoothed (no single-frame snap), genertted no script errors; no new flake.
- **Effort:** S–M • **Depends-on:** F2 • **Quick-win:** the fixed wheel alone (hands
  later) sells the frame without 2 meshes.

## 4. Cockpit HUD, dash-as-HUD, rear-view mirror

- **Goal:** in-cockpit readouts + optional cheap rear-view mirror; HUD auto-shrinks
  in first-person (research §6: dash-as-HUD is the making-it-worth-it feature).
- **Work** (F4):
  - Mirror `%Cluster` values onto the cockpit dash (speed/gear/rpm via `get_drive_info()`
    — same feeds as `race_ui.gd`, read-only) OR ship a "subtract cluster" toggle that
    dims the screen HUD in cockpit mode (per GT7: race info is Display-Setting
    configurable). Make the dash HUD **optional** (ACC dash-removal demand).
  - **Rear-view mirror (deferred-paid):** `SubViewport` + `ViewportTexture` on a small
    virtual mirror in the corner (iRacing `VirtualMirrors` model — budget a low-res
    pass, `WhenParentVisible` update mode). Disabled by default; frame-budget note in
    settings even if not exposed.
  - **No fake windshield tint/reflections** — keep glass clean (FH5 complaint §6);
    if a glass shader exists, ensure it has zero opacity in cockpit view.
- **Acceptance test gate:** `test_cockpit_hud.gd`: cockpit-mode dash reads
  `get_drive_info()` speed/gear/rpm into UI text (no NaN), HUD-dim toggle toggles the
  `%Cluster` canvas visibility; mirror (if built) creates its SubViewport texture
  once, no leak (SceneRunner-driven frame test). No new failures.
- **Effort:** M • **Depends-on:** F1 (F2 for dash placement) • **Quick-win:** HUD-dim
  toggle is trivial and unlocks "read the car, not the screen" feel.

## 5. Accessibility & settings surface (XAG-117 alignment)

- **Goal:** every "nausea knob" is a settings control — FOV per camera, cockpit
  shake strength, head-bob/head-motion strength, motion blur off/short/long, lean-cam
  on/off (research §5). Ships with the feature, not in a patch.
- **Work** (F5): extend `settings_menu.gd`'s ladder pattern with a `Camera and
  Feel` section; persist via existing SaveManager slot (like `quality_preset`);
  `apply_to_scene_tree`-style application of shake/bob/FOV to active camera nodes;
  quality-preset defaults keep shake small at Low/Med (iGPU safety) and allow more at
  High.
- **Acceptance test gate:** `test_camera_settings.gd`: settings persist across an
  in-memory save/load round-trip; FOV/shake/bob values applied to a live cockpit cam
  reflect in `get_hood_fov`-style readbacks + strength exports; defaults satisfy
  XAG-117 (shake/bob default < 0.5 strength, never 1.0-unless-player); Low preset does
  not enable subviewport mirror.
- **Effort:** M • **Depends-on:** F1 (settings need the exports), F4 (mirror budget) •
  **Quick-win:** even FOV+shake+head-motion sliders alone clear the guideline.

## 6. Harden & ship acceptance (all-of-above gate)

- Full AGENTS.md recipe from a clean tree: `git status --short` no `*.uid`; import
  probe zero matches; GDUnit `Overall Summary: ≥ 605 | 0 errors | 0 failures | 0 flaky`
  (depends on flake reconcile, below).
- Playtest flow (the FUN the game exists for): garage → car → drive → C-cycle
  chase→orbit→hood→**cockpit**, speed-feed, brake dive, corner lean, dash readouts;
  screenshot-bound captures via `capture_game_window` for visual sign-off.
- **Reconcile note (pre-existing flake):** `test_hud_gauge.gd:59` currently fails on
  this laptop (frame-delta-sensitive; expected >5500 got ~5301 after 30 frames). It is
  NOT camera-related, but it violates the "0 failures" commit gate. Options for the
  gate: (a) make that test delta-robust (fixed-delta loop or tolerance from the easing
  `rate = 1-exp(-10*delta)` — the assertion should compute the expected value from the
  same frame count + dt, not hardcode 5500) — recommend fixing it as part of F1's
  headless hygiene; (b) if boss prefers, gate on "0 failing NEW tests" instead.

---

## Cut / later

- **Full per-car modeled interiors** (F2b) — L; revisit with CC0 art lane.
- **VR / XRCamera3D path** — keep the cam pivot-node based (research §7) so a VR
  head can swap later ("no tech ceiling" roadmap), but no XR work in this plan.
- **Look-to-apex steering assist** beyond the lite yaw-hint — tuning pass later.
- **Driver-no-wheel accessibility tier** folded as F2c/F3 hide options; not a separate
  mode this pass.

## Delivery order

1. F1 rig + cycle + gate (sub-agent A) → parent verify.
2. Decision F2a/b/c with boss → F2 if a (sub-agent B) → parent verify.
3. F5 settings + F4 HUD/mirror (sub-agent C) → parent verify.
4. F3 optional wheel/hands (sub-agent D, only if boss opts in). → full-suite gate.
5. Reconcile hud_gauge flake, final playtest + visual capture, ship.