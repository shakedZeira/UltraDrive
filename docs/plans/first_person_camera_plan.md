# First-Person (Cockpit/Hood) Camera Plan

Target rig: GeForce GTX 970 (Forward+), Godot **4.7.2**, Jolt. Related:
`docs/ROADMAP.md` ("Feel first", "accessible = launch-blocking"),
`docs/plans/match_fh6_gt7_plan.md` (**item 14 "Hood camera (optional, cheap
kicker)"** — S14, this plan is its full design), `docs/plans/terrain_vista_plan.md`
(far-plane coordination), `docs/plans/graphics_gap_plan.md` (motion blur verdict).

## Objective

Add a **first-person camera mode** to the chase/orbit toggle so the player can
drive from inside the car. Ships as the third slot in a deterministically
testable **chase → orbit → cockpit** cycle (C / joypad button 9, `project.godot`
`camera_mode`), with:

- **a rigid cockpit anchor** on the car chassis: camera is a scene sibling (like
  `ChaseCamera`/`OrbitCamera`) whose global transform is recomputed each physics
  tick from `car.global_basis * anchor_local`, so it rides the body's real
  pitch/roll/suspension — no smoothing, no latency;
- **a speed-tied FOV ramp** (narrower base than chase — 60→72 vs chase 74→90)
  reusing the chase `speed/200` mapping as a pure function;
- **optional right-stick head-look** (bounded pitch, snap-back) behind a flag —
  NOT wired to orbit;
- **no motion blur and no quality-ladder dependency** (Godot 4 has no built-in
  motion blur; the existing `%SpeedOverlay` vignette covers the speed sensation;
  `settings_menu.gd` is untouched);
- **windshield-droplet gating extended to cockpit mode** (today only chase shows
  droplets — `world_driver._is_chase_mode()`, `windshield_fx.gd:45-46`).

**Working agreement: this plan is produced for review. Do NOT implement until
approved.**

---

## §1 BACKGROUND / FACTS (verified, not assumed)

### Existing camera architecture

- `scripts/camera/chase_camera.gd` and `scripts/camera/orbit_camera.gd` both
  create their own `Camera3D` via `.new()` with **default `far = 4000`**
  (`chase_camera.gd:40-43`, `orbit_camera.gd:31-34`). The cockpit camera must
  follow the same convention (see §3 far-plane note for the vista plan).
- **Camera-node wiring is scene-sibling, not body-child.** Neither world scene
  parents cameras under the car: `scenes/world/open_world_root.tscn:103-112` and
  `scenes/track/mountain_pass.tscn:70-79` each have `ChaseCamera` +
  `OrbitCamera` as direct children of the scene root with `target =
  NodePath("%PlayerCar")`, and `OrbitCamera.chase_camera_path`.
- Visibility hand-off today: chase is `current = true` in `_ready`
  (`chase_camera.gd:43`); orbit stays `current = false` (`orbit_camera.gd:34`)
  and grabs current when the player pushes the right stick or presses
  `camera_mode` (`orbit_camera.gd:60-64`), releasing back to chase on the same
  button or via stick-release logic in `_deactivate_camera()` (`orbit_camera.gd:
  113-123`). **The mode-toggle state machine lives inside `orbit_camera.gd`
  today** — adding a third mode requires lifting that one-line toggle out so a
  single owner cycles it (S14 planned exactly this: "add to the mode toggle
  consumed by `player_car_controller.gd` / camera node wiring").
- FOV-with-speed is the house pattern: `chase_camera.gd:109-113` and
  `orbit_camera.gd:95-96` share `lerpf(fov_min, fov_max, clampf(speed_kmh /
  200.0, 0.0, 1.0))`, eased with `fov_speed_factor := 0.05`. `fov_min`/`fov_max`
  differ per camera; the cockpit camera should keep this shape with its own
  (narrower) bounds.

### The player car / anchor evidence

- `scenes/vehicle/player_car.tscn`: `PlayerCar` (RigidBody3D, `vehicle_physics.
  gd`) → `CarBody` (Node3D, line 22) → swappable GLB visual + `BodyRig`
  (lines 24-25). Collision box `1.8 × 0.5 × 4.0` (line 13-14), wheels at
  z = ±1.25 (lines 33, 37, 41, 45). Nose faces **-Z** (chase sits behind along
  `+global_basis.z`, `chase_camera.gd:91-93`; `CAR_ORIENT` in
  `player_car_controller.gd:5` rotates the GLB's +Z nose to -Z, applied at
  `player_car_controller.gd:128`).
- `player_car_controller.gd:_apply_visual()` (lines 111-132) swaps the body GLB
  per garage car and clears `CarBody` children except `BodyRig`. `CarVisuals.
  WHEEL_GROUPS` (`car_visuals.gd:134-172`) is the repo precedent for **per-car
  data tables keyed by garage id** — a future per-car cockpit anchor table
  follows the same pattern; v0 uses a single exported anchor (the GLBs have no
  interiors, so a driver-eye-over-hood vantage is the honest v0).
- `scripts/vehicle/body_rig.gd:60-61` rotates **itself** (a sibling of the GLB,
  not the mesh), adding only ±2-3° visual pitch/roll — nothing a rigid anchor
  needs to compensate for.

### Weather/UI interaction points

- `WorldDriver._is_chase_mode()` (`scripts/world/world_driver.gd:340-346`)
  returns true only while `ChaseCamera.is_current_view()` is true; it feeds
  `WindshieldFX.apply(..., _is_chase_mode())` (line 327). `WindshieldFX` doc
  comment explicitly says droplets run in "first-person/hood views"
  (`windshield_fx.gd:4-6`) but the gate (`windshield_fx.gd:45-46`) can only see
  chase — **cockpit mode would silently lose rain on the windshield**. Gated by
  `tests/suites/test_weather_vfx.gd:157` today.
- HUD: `scenes/ui/hud.tscn` `%Cluster` (lines 242-254) + `%SpeedOverlay` (lines
  498-506, `scripts/ui/speed_overlay.gd`) are screen-space; `RaceUI` drives the
  cluster from `car.get_drive_info()` (`race_ui.gd:84-101`). The cars have **no
  instrument-cluster meshes**, so the HUD cluster must remain visible in cockpit
  mode (GT7's "HUD-friendly cockpit" is aspirational; no dash to hide behind).
- `settings_menu.gd` ladder (`apply_to_scene_tree`, 140-142) touches Environment
  + Viewport only — **no camera/FOV/far override**, so the quality ladder is
  orthogonal to this plan and stays untouched.
- Fast travel: `WorldDriver._settle_chase_camera()` (world_driver.gd:147-165)
  snaps the chase camera after a teleport. A rigid cockpit camera needs **no
  settle** — it is recomputed from the car transform each physics tick.

### Input ground truth

- `project.godot:78-83`: `camera_mode` = C key + joypad button 9 (view button;
  matches FM's View-button camera cycle; FH uses RB — our button 9 is correct
  for the FM lineage, and **no new input action is needed**).
- `project.godot:84-99`: `camera_orbit_*` = right-stick axes. Cockpit head-look
  will reuse these behind its own flag so the orbit mapping is never hijacked.

### Suite baseline

- AGENTS.md headless recipe; the runner is truth: latest green was
  **361 test cases | 0 errors | 0 failures | 0 flaky | 18 orphans**
  (`match_fh6_gt7_plan.md` STATUS block, 2026-09-19). `tests/test_open_world.gd:
  17-22` asserts `ChaseCamera` + `OrbitCamera` exist and target the player — a
  new cockpit sibling must keep that green. `tests/suites/test_chase_camera.gd`
  drives `_update_camera` directly with no physics loop (the pattern to follow).
  `tests/suites/test_drive_feel.gd:184-189` pins chase transients OFF in the
  script default and ON in both player world scenes.

---

## §2 DESIGN (settled)

### Camera-cycle answer (a)

**`chase → orbit → cockpit`**, cycled by a new scene-sibling controller
`scripts/camera/camera_cycle.gd`. This is the FH/Motorsport lineage sanctioned by
`match_fh6_gt7_plan.md` item 14 and the "no tech ceiling" rule — but trimmed to
three slots because our GLBs have no dash/interior to reward a 4th/5th slot.
State machine is a **static pure function** so tests need no scenes:

```gdscript
enum Mode { CHASE = 0, ORBIT = 1, COCKPIT = 2 }
const MODE_COUNT := 3

## Strictly testable cycle. mode_pressed advances one slot; a right-stick grab
## enters ORBIT from chase (the FH "nudge into orbit" feel) but NEVER fires from
## COCKPIT, so right-stick head-look is free inside the cockpit.
static func next_mode(index: int, mode_pressed: bool, stick_grabbed: bool) -> int:
	if mode_pressed:
		return (index + 1) % MODE_COUNT
	if stick_grabbed and index != Mode.ORBIT and index != Mode.COCKPIT:
		return Mode.ORBIT
	return index
```

Controller responsibilities per frame:
1. read `Input.is_action_just_pressed("camera_mode")` and right-stick grab
   (existing deadzone logic moved out of `orbit_camera.gd:56-64`);
2. compute the next mode and set exactly one camera's `Camera3D.current = true`,
   others `false` (**one-shot advance**, see risk R3);
3. leave `ChaseCamera` as the cold-start current (chase keeps `current = true`
   in its own `_ready`; cycle is neutral until the first press).

`orbit_camera.gd` loses its self-toggle (`orbit_camera.gd:60-61`) and its
stick-grab (`62-64`) to the cycle, but keeps `_apply_orbit`/`_deactivate_camera`
unchanged — slide the existing lines into the controller rather than re-authoring
the orbit math.

### Anchor node + transform (b)

New `scripts/camera/cockpit_camera.gd` (`extends Node3D`, sibling node like the
others), `target := %PlayerCar`. Rigid follow — **transform set in
`_physics_process` from the car's physics transform, not lerped**:

```gdscript
@export var anchor_local := Vector3(0.0, 1.1, -0.75)  # x0 center, eye 1.1 m, ~0.75 m ahead of chassis center (nose -Z)
@export var look_pitch_deg := -6.0                    # horizon sits high; hood fills bottom of frame
@export var head_look_enabled := false                # right-stick Y look, OFF by default (a11y-first)
@export var head_look_max_deg := 15.0
@export var head_look_snap_rate := 4.0

var _cam: Camera3D

func _physics_process(delta: float) -> void:
	var car := target as Node3D
	if car == null:
		return
	var pitch := deg_to_rad(look_pitch_deg + _head_pitch())
	# -Z is forward: align the camera basis exactly to the car, then tip down.
	var basis := car.global_basis * (Basis(Vector3.LEFT, pitch))
	global_transform = Transform3D(basis, car.global_position + car.global_basis * anchor_local)
	_cam.fov = lerpf(_cam.fov, fov_for_speed(_car_speed_kmh(car)), fov_speed_factor)
```

- Camera3D created in `_ready` like chase/orbit, `current = false`; `near`
  default 0.05 suffices (anchor → hood ≈ 1.2+ m; nothing clips).
- **Per-car anchors:** v0 ships the single exported default tuned for the
  sports-coupé chassis; a `CarVisuals`-style `COCKPIT_ANCHORS` keyed by garage id
  (mirroring `WHEEL_GROUPS`, `car_visuals.gd:134-172`) is a listed follow-on, not
  a v0 gate — the GLBs are interchangeable enough that the chassis anchor reads
  correctly on all three body shells by eye (verify in Phase 4 windowed pass).
- Physics-interpolation note: recomputing in `_physics_process` (not `_process`)
  and writing the camera's **own** global transform (not the parent's) follows
  the engine's camera guidance for interpolated PhysicsBody targets (source S8).
  The chassis is the interpolated body, so the anchor rides pre-interpolation
  poses with zero feedback.

### FOV / look / speed tie-in (c)

Static pure function on the cockpit script (mirrors chase's ramp exactly, but
narrower — cockpit realism + motion-sickness comfort):

```gdscript
const FOV_MIN := 60.0
const FOV_MAX := 72.0
const FOV_SPEED_FULL_KMH := 200.0
const FOV_SPEED_FACTOR := 0.05

static func fov_for_speed(speed_kmh: float) -> float:
	return lerpf(FOV_MIN, FOV_MAX, clampf(speed_kmh / FOV_SPEED_FULL_KMH, 0.0, 1.0))
```

- **Speed sensation stays in the existing `%SpeedOverlay`** (vignette + streaks,
  `speed_overlay.gd`), which is screen-space and already camera-agnostic. **No
  Godot motion blur** — the project already recorded that Godot 4 has no built-in
  3D motion blur and deferred the AssetLib addon (graphics_gap_plan item 6
  verdict; confirmed against Godot Environment docs, source S9). A GT7-style
  depth-of-field/`CameraAttributes` pass is explicitly out of scope (flagged).
- Head-look: right-stick Y only, clamped to ±`head_look_max_deg`, re-centered at
  `head_look_snap_rate`/s when released or when `head_look_enabled` is false.
  Default OFF (accessible baseline; FH5 ships a "cockpit drift camera" toggle,
  sources S1/S3).
- **Camera shake: none by default.** The community signal is loud that cockpit
  shake has to be disableable (FH6 backlash, source S6) — cockpit mode does not
  inherit chase's transients; a future `GameState` a11y toggle is the follow-on.

### HUD cockpit tweaks (d)

Minimal by design — there is no dash mesh to hide behind:

1. **Keep the `%Cluster` and `%SpeedOverlay` as-is** in cockpit mode (GT7
   HUD-friendly lease: keep the info layer; it already leads to better lap times
   than glancing at the tach model in the cockpit).
2. **Fix the windshield-droplet gate** so cockpit mode shows droplets: re-name
   the intent of `WorldDriver._is_chase_mode()` (line 340-346) to
   `_is_cockpit_compatible_view()` (chase OR cockpit current). `WindshieldFX`
   keeps its pure `active()` — only the driver's boolean changes.
3. Optional (not a gate): a small `%CamBadge` label in `hud.tscn` showing
   "CHASE / ORBIT / COCKPIT" while cycling. Confetti/results/countdown overlays
   are unaffected.

### far = 4000 camera note (f)

The cockpit camera's `Camera3D.new()` will default to `far = 4000` exactly like
chase/orbit. That is **correct today**, but `terrain_vista_plan.md` Phase 3 sets
chase+orbit to `far = 24000` for the horizon vista. When the vista lands, the
cockpit camera must adopt the **same far** (one const per camera, or a follow
the chase convention). v0 asserts `far == 4000` to keep the three cameras
consistent; the vista plan is the coordination point, not this plan (R6).

### Settings ladders

`settings_menu.gd` untouched. A cockpit FOV **scale** and the
`head_look_enabled`/shake toggles are future `GameState` a11y toggles (S15 in
`match_fh6_gt7_plan.md`); v0 keeps exports with safe defaults (S3/S5).

---

## §3 EXECUTION CONTRACT

- **Sub-agents run strictly SEQUENTIALLY. One Godot process at a time** (two
  collide on `.godot/`). Watchdog on every headless run (any script error during
  a headless diag leaves Godot hanging forever — AGENTS.md). Each task = one
  phase below; the sub-agent gets exact file:line targets, the gate commands,
  and the rule "don't touch anything outside your phase."
- No commits. Report first with verbatim items: `git status --short`,
  `git diff --stat`, all `Overall Summary:` lines, import-gate output, the
  windowed proves (anchor/fov/cycle) and PNG paths.
- **No code comments. Tabs** in `scripts/camera/*`. Don't touch
  `settings_menu.gd`, `vehicle_physics.gd`, `race_ui.gd` HUD logic, or the
  quality ladder. Prefer `is_equal_approx` with same-type args (AGENTS.md
  GDUnit gotchas); warnings-as-errors applies (type every `var`).
- Full-suite gate (AGENTS.md headless workflow — import probe FIRST, then the
  `-s` run with `--ignoreHeadlessMode` AFTER the tool-script path):

```
"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import . 2>&1 | findstr /i "SCRIPT ERROR Parse Error Failed to load"
"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1
findstr /c:"Overall Summary:" _gdunit.txt
```

EXPECT: **≥ 361 test cases | 0 errors | 0 failures | 0 flaky | 18 orphans**
(runner output is truth; AGENTS.md's "263" line is stale). The existing suites
listed per-phase must stay green **unchanged**.

Per-suite one-at-a-time when isolating a phase: `test_chase_camera`,
`test_open_world`, `test_drive_feel`, `test_weather_vfx`, `test_cockpit_camera`
(new), `test_camera_cycle` (new).

---

## §4 PHASES

### Phase 0 — Pure math + tests first (no scenes)

- `cockpit_camera.gd` static `fov_for_speed()`; `camera_cycle.gd` static
  `next_mode()` + `Mode` enum. Both pure — land with zero scene wiring.
- `tests/suites/test_cockpit_camera.gd` pure-math half:
  `test_fov_speed_ramp_pure` (0 → 60, 200 → 72 within ε, monotonic sample sweep,
  clamped at extremes), `test_cycle_order_pure`
  (`next_mode(CHASE,true,_) → ORBIT`, `→ COCKPIT`, `→ CHASE`; stick grab from
  CHASE → ORBIT; from COCKPIT a grab returns COCKPIT unchanged).

Gate: `test_cockpit_camera` + `test_camera_cycle` green; suite total ≥ 361 + new
tests, 0 errors.

### Phase 1 — `cockpit_camera.gd` node + world-scene wiring

- Full node script (rigid anchor, look pitch, head-look behind
  `head_look_enabled`, `fov_for_speed` ramp, `current` flag, `is_current_view()`
  mirroring chase's gate seam `chase_camera.gd:68-69`).
- Add `CockpitCamera` sibling node to `open_world_root.tscn`, `mountain_pass.tscn`,
  `test_track.tscn` (not `test_vehicle_physics.tscn` — chase-only scene stays
  untouched). `target = NodePath("%PlayerCar")`, `current` never forced on.
- `test_cockpit_camera.gd` scene half: `test_anchor_rigid_follow` (drive
  `_physics_process`-equivalent update directly from a static-target pattern like
  `test_chase_camera.gd:46-59`; assert camera position ==
  `car.global_position + car.global_basis * anchor_local` within ε and camera
  -Z ≈ car -Z with the pitch offset), `test_head_look_clamped` (right-stick Y
  saturates at ±15°, snaps to look_pitch on release), and
  `test_cockpit_camera_default_inactive` (both world scenes: `CockpitCamera`
  camera `current == false`, chase still current — `test_open_world.gd:17-22`
  stays green).

Gate: import probe clean; `test_chase_camera.gd` + `test_open_world.gd` +
`test_drive_feel.gd` green unchanged; `test_cockpit_camera.gd` green.

### Phase 2 — `camera_cycle.gd` takes over the mode toggle

- New `scripts/camera/camera_cycle.gd` scene-sibling controller in all three
  scenes; it owns `camera_mode` + stick-grab, sets one `current` camera, and
  routes stick input to orbit (existing `_apply_orbit`) or cockpit head-look
  (Phase 1) **exclusively**.
- `orbit_camera.gd:60-64` self-toggle/stick-grab removed; `_apply_orbit`,
  `_deactivate_camera` (113-123) unchanged. `ChaseCamera.is_current_view()` stays
  the chase gate; cockpit gets its own.
- `tests/suites/test_camera_cycle.gd`: `test_advance_advances_exactly_once_per_press`,
  `test_final_mode_returns_to_chase`, `test_stick_grab_idempotent_from_cockpit`,
  and a scene-level test that fatigue-presses `camera_mode` N times and asserts
  the current camera matches `next_mode` bookkeeping (one-shot, no double-step).

Gate: `test_chase_camera.gd`, `test_open_world.gd`, `test_drive_feel.gd` green
unchanged; `test_camera_cycle.gd` green.

### Phase 3 — Windshield gate + optional HUD badge

- `world_driver.gd:340-346` `_is_chase_mode()` → `_is_cockpit_compatible_view()`
  (chase OR cockpit `current`). `windshield_fx.gd` untouched.
- Extend `tests/suites/test_weather_vfx.gd:157` windshield gate test: droplets
  active for chase, active for cockpit, hidden for orbit.
- Optional: `%CamBadge` in `hud.tscn` (chase/orbit/cockpit label) fed by the
  cycle. Not a gate.

Gate: `test_weather_vfx.gd` green (all prior tests + the extended gate).

### Phase 4 — Full verification + proof + report

- Full-suite gate command (§3). Perf note: cockpit mode renders the same world
  with no new particles/meshes — assert no probe regression if one exists
  (`tools/` probes stay green; do NOT reopen the closed perf work).
- Windowed PNGs → `D:\Temp\opencode\cockpit\`: (a) cockpit at speed on the hub
  ring, (b) cockpit braking into a corner (pitch/roll visible), (c) cycle badge /
  orbit still intact, (d) rain in cockpit shows windshield droplets. Analyze with
  the vision-bridge `analyze_image` and keep as the anchor/FOV proof.
- Verbatim report (see §3), no commit.

Gate: all PNGs show the hood/bodywork correctly framed, no near-plane clipping,
droplets in rain; suite green; `test_chase_camera`/`test_drive_feel` unchanged.

---

## §5 MEASUREMENT LOG (fill in as phases land)

| Phase | Metric | Before | After | Note |
|---|---|---|---|---|
| 0 | `fov_for_speed` sweep | — | 60.0→72.0 | monotonic, clamped |
| 0 | `next_mode` transitions | — | 3→chase | pure, no scenes |
| 1 | anchor pose error vs `car.basis*anchor` | — | <0.001 m | ε assert |
| 1 | head-look clamp | — | ±15°, snap ±head_look_max_deg | flag-off default |
| 2 | cycle one-shot per press | — | exact | fatigue 5 presses |
| 3 | droplets in cockpit/rain | only chase | chase + cockpit | `test_weather_vfx` extended |
| 4 | full suite | 361 | ≥ 361 green | 0 errors / 0 flaky |
| 4 | cockpit near-plane clip | — | none | windowed PNG (a) |

---

## §6 SOURCES

- FH5 Accessibility support — FOV sliders (console too), cockpit-drift-camera
  toggle (sensitivity/look/range), motion blur toggle:
  https://support.forza.net/hc/en-us/articles/46523995129747-Forza-Horizon-5-Accessibility-Support
- Forza camera-view lineage + cycle buttons (FM View button; FH right bumper;
  Chase Near/Chase Far/Driver/Cockpit/Hood/Bumper):
  https://forza.fandom.com/wiki/Camera_View · https://www.ign.com/wikis/forza-motorsport/How_to_Change_Camera_View
- Forza cockpit FOV / seat-position demand + "dashboard vs cockpit" split (FH4
  thread) and cockpit free-camera wishlist: https://forums.forza.net/t/cockpit-seating-position-pov/79444 ·
  https://forums.forza.net/t/cockpit-free-camera/541093
- GT7 VR manual — cockpit/bonnet-limited first-person views; cockpit-view data
  display options: https://www.gran-turismo.com/hk/gt7/manual/psvr/01
- Xbox Accessibility Guidelines 117 — visual-distraction motion settings: FOV,
  camera-shake, motion-blur, head-bob toggles as the motion-sickness floor:
  https://devdocs.xbox.com/build/game-principles/accessibility/xag-deep-dives/xag-117-visual-distractions-motion.md
  (and Access-Ability on FOV sliders + head-bob toggles:
  https://access-ability.uk/2022/04/25/gaming-with-motion-sickness)
- FH6 camera-shake backlash (un-disableable cockpit shake → nausea; players
  demand the toggle) — "do not ship cockpit shake without a toggle":
  https://steamcommunity.com/app/2483190/discussions/0/839502402944062495
- Skaruts `racing_cameras` (Godot 4, MIT) — `RacingCockpitCamera` mouse look,
  `RacingMountedCamera` cycling positions, and the `get_car_physicsbody` seam
  for vehicles whose physics body isn't the scene root:
  https://github.com/Skaruts/racing_cameras ·
  https://godotengine.org/asset-library/asset/3242
- Godot physics-interpolation camera guidance (update in `_physics_process`;
  specify the camera transform in global space when chasing a moving physics
  parent): https://github.com/godotengine/godot/issues/101814
- Godot Environment & post-processing docs — **no built-in 3D motion blur**;
  depth-of-field/exposure live on `CameraAttributes`:
  https://docs.godotengine.org/en/4.4/tutorials/3d/environment_and_post_processing.html
- Godot 4 arcade-racer precedent (chase/hood/bumper + speed-reactive FOV +
  G-force shake): https://github.com/joppe2001/racing-game
- Project Motor Racing (WSGF) — **separate cockpit seat-position tab, cockpit FOV
  25–100 default 54**, and draggable cockpit HUD layout:
  https://www.wsgf.org/dr/project-motor-racing
- Academic: FOV-restriction/rest-frame motion-sickness mitigations in racing
  games (flat-screen FOV trade-offs): https://arxiv.org/abs/2103.05200 ·
  https://arxiv.org/pdf/2205.07041
- In-repo grounding: `scripts/camera/chase_camera.gd`, `scripts/camera/orbit_camera.gd`,
  `scripts/player/player_car_controller.gd`, `scripts/vehicle/car_visuals.gd`,
  `scripts/world/world_driver.gd`, `scripts/weather/windshield_fx.gd`,
  `scripts/ui/settings_menu.gd`, `scripts/race/race_ui.gd`,
  `scenes/vehicle/player_car.tscn`, `scenes/world/open_world_root.tscn`,
  `scenes/track/mountain_pass.tscn`, `scenes/ui/hud.tscn`, `project.godot`,
  `docs/plans/match_fh6_gt7_plan.md` (S14), `docs/plans/terrain_vista_plan.md`.

---

## §7 RISKS

- **R1 — Physics-interpolation jitter on the rigid anchor.** A driver-eye
  camera glued to the chassis can fight the interpolated body if updated in
  `_process`. Mitigation: write the camera's own `global_transform` in
  `_physics_process` only (S8), keep the Camera3D's orientation offset small,
  and verify with the Phase 4 windowed pass + hitch probe. No new orphan cost
  (single stateless node).
- **R2 — Double-step camera switching.** Two `camera_mode` consumers (legacy
  orbit toggle + new cycle) would advance two slots per press. Mitigation:
  Phase 2 removes the orbit self-toggle; `test_camera_cycle` fatigue-press pins
  one-shot.
- **R3 — Windshield droplets silently vanish in cockpit.** The existing gate
  (`world_driver.gd:340-346`) reads only chase current. Mitigation: Phase 3
  extends the gate; `test_weather_vfx.gd:157` extended before any visual
  acceptance.
- **R4 — Cockpit shake / narrow FOV causing motion sickness.** Community +
  XAG signal. Mitigations: cockpit shake default OFF, `head_look_enabled` OFF,
  base FOV 60 (wide enough for comfort, narrower than chase for realism);
  FOV-scale + shake toggles deferred to the S15 a11y plan, not buried here.
- **R5 — Three scene files to keep in sync.** `open_world_root.tscn`,
  `mountain_pass.tscn`, `test_track.tscn` must each gain the two new nodes; a
  missing one degrades to "no cockpit" (chase unaffected) but `test_open_world`
  catches the player scenes. Sub-agent scope lists all three explicitly.
- **R6 — far-plane divergence.** Cockpit ships at `far = 4000`; if
  `terrain_vista_plan.md` Phase 3 (far → 24000) lands later, the cockpit camera
  must follow or the vista pops inside the cockpit view. Coordination point is
  the vista plan's Phase 3, flagged there via this plan (f).
- **R7 — GDUnit discipline.** Warnings-as-errors and same-type
  `is_equal_approx`: every new `var` typed; `fov_for_speed` compared with a
  float arg (`assert_that(float(fov)).is_equal_approx(60.0, 0.001)`), vectors
  compared with `Vector2(ε, ε)` style args per AGENTS.md.
- **R8 — Head-look vs orbit stick fight.** Right stick must never launch orbit
  from cockpit (S2 `next_mode` rule) or head-look becomes a modal trap. Pin with
  `test_stick_grab_idempotent_from_cockpit`.

---

## §8 DELIVERABLE CHECKLIST (review gate)

- [ ] Phase 0: `fov_for_speed` + `next_mode` pure funcs; `test_cockpit_camera` /
      `test_camera_cycle` pure-math tests green
- [ ] Phase 1: `cockpit_camera.gd` wired into all three world scenes; chase
      stays current; `test_open_world.gd` unchanged-green
- [ ] Phase 2: `camera_cycle.gd` owns the toggle; orbit self-toggle removed;
      one-shot cycle green
- [ ] Phase 3: windshield gate covers cockpit; `test_weather_vfx.gd` extended
- [ ] Phase 4: full GS-ladder suite green (≥ 361, 0 errors / 0 failures / 0
      flaky); `test_chase_camera` + `test_drive_feel` untouched
- [ ] 4 PNGs (`D:\Temp\opencode\cockpit\`) analyzed — anchor frame, braking
      pitch, cycle intact, rain droplets
- [ ] §5 log filled with measured rows
- [ ] Verbatim report (no commit)