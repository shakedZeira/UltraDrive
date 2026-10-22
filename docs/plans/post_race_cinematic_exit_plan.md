# Post-Race Cinematic + Exit-to-Race-Menu Plan

**Goal:** two **additive** post-race features on the results flow:

1. **Post-race cinematic** — when the race ends, the cars keep driving under
   AI instead of the player staring at a frozen track, and the camera cuts to a
   dedicated cinematic rig that follows the pack. The same controller is
   reusable as a **main-menu background clip** (recorded offline, not at
   runtime).
2. **Exit button** — a third button on the post-race results overlay that
   returns to the **race menu** (`res://scenes/ui/track_select.tscn`), distinct
   from the existing "NEXT RACE" (re-arm ceremony) and "RETURN TO FREE ROAM".

**Working agreement: planning only.** This document is the only file this plan
authorises. It does **not** implement, does **not** run Godot, and does **not**
touch any game code. Everything below is the proposal, grounded in the current
tree with `file:line` evidence.

Related: `docs/plans/main_menu_video_bg_plan.md` (the clip-recording harness this
reuses); `docs/superpowers/plans/2026-09-13-race-loop-end-to-end.md`;
`docs/ROADMAP.md`.

---

## §1 GOAL + ACCEPTANCE CRITERIA

### 1.1 Goal, stated as behaviour

- After the race finishes, the player's car is **taken over by an AI driver** of
  the same kind the rivals already use, and continues around the loop.
- The rivals **already keep driving** at finish (see §2.2) — no work needed for
  them.
- A **cinematic camera** becomes the active view: the gameplay rigs
  (`ChaseCamera` / `OrbitCamera` / `HoodCamera` / `CockpitCamera`) are retired
  and a cinematic `Camera3D` follows the pack, cycling between cars.
- A new **EXIT** button on the results overlay returns to
  `res://scenes/ui/track_select.tscn`.
- Post-finish state is an explicit machine: `RACING → FINISHED → CINEMATIC →
  EXIT`.

### 1.2 Acceptance criteria (each verifiable)

| # | Criterion | How it is verified |
|---|---|---|
| **A1** | A state machine exposes exactly `RACING / FINISHED / CINEMATIC / EXIT` and the legal transitions | Unit test on the pure transition function (§5 T1) |
| **A2** | On race finish, the player car acquires an AI driver child and a **non-zero `input_override`** within one physics tick | Unit test calls the driver's `_physics_process` and asserts `car.input_override != Vector2.ZERO` (§5 T5) |
| **A3** | Every gameplay camera rig has `current == false` and its process disabled; the cinematic `Camera3D` has `current == true` | Node-tree unit test (§5 T6) |
| **A4** | The results overlay gains an `EXIT` button whose press calls the scene-navigation seam with `res://scenes/ui/track_select.tscn` | HUD scene test with a `launch_callback` spy (§5 T7) |
| **A5** | Leaving the cinematic restores the player's control (`input_override == Vector2.ZERO`, `scripted_driver == false`) and frees the auto-driver | Unit test (§5 T8) |
| **A6** | The cinematic runs without a track root / player car (headless HUD-only test) with no errors | Unit test (§5 T9) |
| **A7** | No existing suite regresses (results, race loop, rival AI) | Targeted re-runs + the parallel gate (§5 §5.4) |
| **A8** | A public seam exposes the cinematic rig so an offline recorder can drive it (menu-clip reuse) | API-present assertion (§5 T10) |

### 1.3 Non-goals

- Not a replay system (no recorded transform stream; `ReplayRecorder` is
  untouched).
- No new track, no new car, no physics change.
- The menu clip is **recorded offline** by a separate harness; the game never
  plays a video for the cinematic.

---

## §2 CURRENT STATE (verified)

### 2.1 Does an AI driver exist? — **YES**

- `scripts/ai/ai_controller.gd` — `class_name AIController extends Node`
  (line 3). A **wrap-safe pure-pursuit** waypoint follower: it advances a
  captured target index (line 180) but steers at an arc-length lookahead point
  measured forward from the *nearest* waypoint (lines 182-190), so a spun or
  displaced car rejoins instead of chasing a stale index. It adds
  curvature-lookahead braking (lines 192-208) and a no-teleport stuck recovery
  (lines 264-298).
- It drives a car **only** through
  `car.set_input_override(Vector2(steer, throttle - braking))`
  (`ai_controller.gd:240`) and declares itself scripted in `_ready` via
  `car.set_scripted_driver(true)` (line 150).
- `scripts/ai/rival_driver.gd` — `class_name RivalDriver extends AIController`
  (line 2). Adds a class×tier pace (`RacingLine.pace_for`, line 30) and the
  optional rubber-band assist (lines 32-35). It is the production rival driver
  (`autoload/race_manager.gd:240-243`).
- Motion seam on the car: `VehiclePhysics.set_input_override` /
  `set_scripted_driver` (`scripts/vehicle/vehicle_physics.gd:136-144`). A
  **non-zero** override makes the car ignore keyboard/joypad for throttle,
  brake, steer **and shifts** (`vehicle_physics.gd:222-234, 261-276`). The exact
  `Vector2.ZERO` is reserved for "no override → player input"
  (`vehicle_physics.gd:223-225`), which is why `AIController._simulate_input`
  floors the command to `0.01` rather than emitting zero
  (`ai_controller.gd:238-240`).

### 2.2 How do opponent cars move today?

- Rivals are spawned by `RaceManager._spawn_configured_rivals()`
  (`race_manager.gd:194`), called from `start_race()` (line 134). Each gets a
  `RivalDriver` child configured against `rival_centerline`
  (`race_manager.gd:240-243`).
- **Rivals only exist where the track published a centerline.** The spawn
  guard is `if rival_centerline.size() < 2: return` (`race_manager.gd:272`);
  `configure_default_rivals()` bails on the same condition (line 272).
  `northern_isle.tscn` and `barcelona_rx.tscn` publish it; `mountain_pass` and
  the flat test tracks do not — those races are **solo** (no opponents to
  cinematic).
- **Rivals already auto-drive after the finish.** Their `RivalDriver` is a
  plain child node whose `_physics_process` is never disabled by
  `finish_race()`; only `RaceManager._process` early-returns once
  `is_race_active == false` (`race_manager.gd:523-524`). So the field keeps
  lapping. **Implication: only the player car needs an auto-driver attached
  post-finish.**

### 2.3 What happens at race finish today

- `RaceManager.finish_race()` (`race_manager.gd:417-421`) takes standings,
  records rival W/L, sets `is_race_active = false` (line 420) and emits
  `race_finished(standings)` (line 421). It fires as soon as **any** car
  completes all laps.
- `RaceUI._on_race_finished(standings)` (`scripts/race/race_ui.gd:265-300`) sets
  `_race_over = true` (line 267), fills the results card and calls
  `show_result(...)` (line 297), which sets `results_overlay.visible = true`
  (line 325).
- **The player still drives manually under the overlay.** Control gating is
  `RaceManager.controls_locked() == is_race_active and countdown.controls_locked()`
  (`race_manager.gd:106-107`), which is `false` after finish; with
  `input_override == Vector2.ZERO` the car reads live player input
  (`vehicle_physics.gd:217-234`).
- `RaceUI._process` keeps refreshing gauges, then `if _race_over: return`
  (`race_ui.gd:170-171`); the live standings panel is hidden when `_race_over`
  (`race_ui.gd:554-555`).

### 2.4 Cameras

- There is **no cinematic camera and no camera manager.** Each track scene root
  carries four sibling rigs, e.g. `scenes/track/northern_isle.tscn:84,89,97,101`
  (`ChaseCamera`, `OrbitCamera`, `HoodCamera`, `CockpitCamera`);
  same at `mountain_pass.tscn:76,81,89,93`, `barcelona_rx.tscn:84,89,97,101`,
  `open_world_root.tscn:121,126,134,138`.
- `ChaseCamera` builds its **own** `Camera3D` in `_ready` and sets it
  `current = true` (`scripts/camera/chase_camera.gd:43-47`).
- Handoff is done by toggling `Camera3D.current`. The **precedent to copy** is
  `MenuClipRecorder._setup_pan()`
  (`scripts/capture/menu_clip_recorder.gd:283-304`): for each rig name it calls
  `set_process(false)` / `set_physics_process(false)` and sets every descendant
  `Camera3D.current = false`, then sets its own camera `current = true`
  (lines 294-304).

### 2.5 Scene transitions and the race menu

- `SceneTransition.flash_to_scene(path)` (`scripts/ui/scene_transition.gd`) →
  `GameState.change_scene(path)` (`autoload/game_state.gd:133-142`), which calls
  `get_tree().change_scene_to_file`, sets `is_paused = false` (line 140) and
  emits `scene_changed` (line 141). **It does not reset `get_tree().paused`.**
- The race menu (track select) scene is `res://scenes/ui/track_select.tscn`;
  `TrackSelect` has its own `launch_callback` defaulting to
  `_default_launch` → `SceneTransition.flash_to_scene`
  (`scripts/ui/track_select.gd:61,359-360`). Track scenes live in
  `scripts/track/track_registry.gd:17,24,31` — `track_select` is **not** a
  registered track, it is the picker.
- `RaceManager` reacts to scene changes by freeing its spawned rivals and
  clearing the cached roster/centerline — so nothing leaks across the exit
  (`race_manager.gd:56-74`).

### 2.6 Reusable seams

- `RaceUI.launch_callback: Callable` (`race_ui.gd:58-60`) — the scene-nav test
  seam, already used by `_on_next_race` / `_on_return_free_roam`
  (`race_ui.gd:367-382`).
- The post-race racing line: `RaceManager.rival_centerline` when present, else
  the checkpoint ring. `RaceUI._resolve_gap_path()` already computes exactly
  this (`race_ui.gd:659-663`), falling back to `_checkpoint_ring()`
  (`race_ui.gd:665-677`, which resamples checkpoints with
  `RacingLine.resample_arc`).
- `AIController.set_waypoints(points, start_index)` (`ai_controller.gd:246-257`)
  and `set_speed_multiplier(mult)` (clamped 0.5-1.5, line 259-260).
- Results buttons live in `scenes/ui/hud.tscn:581-595` (`Buttons` `HBoxContainer`
  → `NextRaceButton` line 585, `ReturnFreeRoamButton` line 591).

### 2.7 The R-respawn question (already answered by the tree)

`VehiclePhysics.try_manual_respawn` (`vehicle_physics.gd:822-828`) is only
reachable when `can_manual_respawn()` (`vehicle_physics.gd:811-817`) is true,
and that returns **false whenever `input_override != Vector2.ZERO`**
(lines 812-813). So once the cinematic auto-driver writes a non-zero override,
the player's reset key **cannot** respawn the cinematic car. No extra guard is
needed. (Recorded here because it is the obvious worry and it is already
covered.)

### 2.8 Test conventions to mirror

- `tests/suites/test_race_results.gd` — `scene_runner("res://scenes/ui/hud.tscn")`
  + `simulate_frames`, a `launch_callback` spy
  (lines 191-199), and an `after_test` that frees managed cars, every
  `LapCounter` child, resets `RaceManager` state and clears
  `VehicleManager` (lines 28-46).
- `tests/suites/test_race_loop.gd` — leak discipline + `after_test`
  (lines 17-35).
- `tests/suites/test_rival_ai.gd` — managed drivers/cars + `after_test`
  (lines 18-46), asserts the `input_override` control path.

---

## §3 DESIGN DECISIONS

### 3.1 Post-finish state machine

```
RACING ──(RaceManager.race_finished)──▶ FINISHED
FINISHED ──(dwell elapsed)────────────▶ CINEMATIC
CINEMATIC ──(cancel / ui_cancel)──────▶ FINISHED
FINISHED / CINEMATIC ──(Exit button)──▶ EXIT
```

- **RACING** — unchanged, `is_race_active == true`.
- **FINISHED** — `race_finished` has fired; the results card is up; the player
  can still drive (today's behaviour). A dwell timer runs.
- **CINEMATIC** — after `FINISHED_DWELL_SEC` (default **6.0 s**, enough to read
  the card): the results overlay hides, an additive prompt shows, the player car
  is auto-driven, the strong camera rigs are retired and the cinematic camera
  goes live. The pack loops.
- **EXIT** — teardown, then `launch_callback.call(TRACK_SELECT_SCENE)`.

The transition function is **pure** (`advance(state, event, dwell_elapsed,
dwell_sec) -> State`) so the whole machine is unit-testable with no scene
(§5 T1-T2).

**Options considered → chosen**

| Option | Verdict |
|---|---|
| Cinematic starts immediately on finish | Rejected: the player would never read the results card |
| Cinematic only on a button press | Rejected: the feature is "automatic after the race ends" |
| **Auto-start after a configurable dwell, `ui_cancel` returns to the card** | **Chosen** — reads first, shows off second, skips in one key |

### 3.2 Auto-drive approach

**Chosen: reuse `AIController` directly, attached to the player car.**

- Why not `RivalDriver`: its pace/rubber-band model is class×tier and it reads
  the player as a rubber-band peer (`rival_driver.gd:37-52`), which is noise for
  a post-race beauty pass. `AIController` with a gentle speed multiplier is
  exactly a relaxed cruise.
- Attach as a **child of the player car** (`car.add_child(driver)`), then
  `driver.set_waypoints(line, nearest_index)` and
  `driver.set_speed_multiplier(0.55)` (clamped 0.5-1.5,
  `ai_controller.gd:259-260`). The car's `input_override` makes
  `can_manual_respawn()` false (§2.7) and the drivetrain AUTO
  (`vehicle_physics.gd:261-262`).
- **Line source:** `RaceManager.rival_centerline` when `size() >= 2`, else the
  checkpoint ring — i.e. exactly `RaceUI._resolve_gap_path()`
  (`race_ui.gd:659-663`). If **neither** exists (`< MIN_PATH_POINTS`), there is
  nothing to drive along: the cinematic is **skipped** and the results card
  stays up (graceful, matches the existing "roads silently no-op" convention).
- **Rejoin:** the pure-pursuit + stall recovery (`ai_controller.gd:171-190,
  264-298`) is what makes this safe — a car that stopped at the line, or faces
  backwards, steers back onto the loop instead of deadlocking.
- **Restore on cancel:** `set_input_override(Vector2.ZERO)` +
  `set_scripted_driver(false)` + free the driver (§5 T8).

| Option | Verdict |
|---|---|
| New bespoke cinematic driver | Rejected: duplicates a battle-tested controller |
| `RivalDriver` for the player | Rejected: pace/rubber-band semantics are wrong here |
| **`AIController` + `set_speed_multiplier(0.55)`** | **Chosen** |
| Freeze the player car in place | Rejected: the pack would drive away from a statue |

### 3.3 Cinematic camera approach

**Chosen: a small `PostRaceCinematic` node that owns one `Camera3D` and cuts
between cars; the *selection/offset math* is a pure `CinematicDirector`.**

- The shell reuses the verified handoff from
  `menu_clip_recorder.gd:283-304`: disable the four gameplay rigs, set their
  descendant `Camera3D.current = false`, then `own_camera.current = true`.
- Each `CINEMATIC_TARGET_HOLD_SEC` (default 4.0 s) it switches the followed car:
  pick the active car as `standings[floor(elapsed / hold) % standings.size()]`
  (a **pure** function, §5 T3), so the shot cycles the whole field, leader first.
- The camera sits behind-and-above the target via a **pure** transform helper
  `chase_transform(target_pos, target_basis, distance, height)` (§5 T4), with a
  slow yaw drift for a "beauty pass" feel.
- Targets are resolved from `RaceManager.get_standings()` (leader first,
  `race_manager.gd:451`), which includes the player and rivals while they exist.

| Option | Verdict |
|---|---|
| Reuse `OrbitCamera` | Rejected: it is the player-look rig; hijacking it is fragile |
| Author an `AnimationPlayer` path per track | Rejected: per-track asset work, no generality |
| Cut to each car's own chase rig in turn | Rejected: coupling to rig targets; one owned camera is simpler |
| **One owned `Camera3D` + pure director, cycling cars** | **Chosen** |

**Guarded degradation:** if there is no `Node3D` track root (e.g. the headless
HUD-only test) the cinematic runs the state machine + auto-driver but performs
**no camera work** (`§5 T9`). `null`-safe everywhere.

### 3.4 Where the cinematic lives

`RaceUI._on_race_finished` already owns the finish hook (`race_ui.gd:265`), so
`RaceUI` creates and owns the `PostRaceCinematic`. It resolves the track root by
walking up from itself to the first `Node3D` ancestor (the pattern
`_resolve_track_id` uses for `scene_file_path`, `race_ui.gd:441-451`), falling
back to `get_tree().current_scene` when that is a `Node3D`. No new autoload, no
track-scene edit.

### 3.5 Exit wiring

Mirror `_on_return_free_roam` (`race_ui.gd:374-382`) exactly, with a new
destination constant:

```gdscript
const TRACK_SELECT_SCENE := "res://scenes/ui/track_select.tscn"
```

`_on_exit()` resets `_race_over` / `_rewards_banked`, hides the overlay, resets
confetti, **stops the cinematic** (idempotent), then
`launch_callback.call(TRACK_SELECT_SCENE)`. Using `launch_callback` keeps the
existing spy seam (`test_race_results.gd:196`) and the `SceneTransition` fade
in the default path.

### 3.6 Menu-background reuse (follow-up, non-blocking)

The cinematic shell is deliberately the same shape as `MenuClipRecorder`
(`menu_clip_recorder.gd`): a scripted driver plus an owned camera on a real
track scene. A follow-up can instance a track scene, start a race, force a
finish, arm `PostRaceCinematic`, and record with `--write-movie` (the
`docs/plans/main_menu_video_bg_plan.md` §3B recipe), producing
`assets/videos/menu_race_finish.ogv` for the menu playlist
(`menu_drive_hub/pass/pan` roster, §2 of that plan). **This is a separate
execution and must not gate §4/§5.** The only thing §4 must guarantee is that
the cinematic rig is reachable from a public seam (§5 T10).

### 3.7 Testable-core principle

All decision logic (state transitions, target cycling, camera offset) lives in a
`RefCounted` with static/pure functions; the `Node3D` shell is a thin adapter
that reads the tree and writes the camera + driver. This matches the codebase's
existing pattern (`RaceGapTracker`, `RacingLine`, `MenuVideoPlaylist`) and is
what makes §5 file-free and mutation-safe.

---

## §4 IMPLEMENTATION STEPS (ordered)

> Files in scope: **new** `scripts/race/post_race_cinematic.gd`,
> **new** `scripts/race/cinematic_director.gd`,
> **new** `tests/suites/test_post_race_cinematic.gd`;
> **edited** `scripts/race/race_ui.gd`, `scenes/ui/hud.tscn`.
> Optional follow-up: `scenes/capture/post_race_cinematic_capture.tscn` +
> `tools/record_post_race_clip.py`.

### Step 1 — `scripts/race/cinematic_director.gd` (new, pure)

`class_name CinematicDirector extends RefCounted`. No nodes, no tree access.

- `enum State { RACING, FINISHED, CINEMATIC, EXIT }` and
  `enum Event { FINISH, DWELL_ELAPSED, CANCEL, EXIT }`.
- `const FINISHED_DWELL_SEC := 6.0`, `const CINEMATIC_TARGET_HOLD_SEC := 4.0`.
- `static func advance(state: int, event: int, dwell_elapsed: float, dwell_sec: float) -> int`
  implementing the §3.1 table (FINISH: RACING→FINISHED; DWELL_ELAPSED with
  `dwell_elapsed >= dwell_sec`: FINISHED→CINEMATIC; CANCEL: CINEMATIC→FINISHED;
  EXIT: FINISHED|CINEMATIC→EXIT; otherwise unchanged). Pure, total.
- `static func target_index(count: int, elapsed: float, hold_sec: float) -> int`
  — `0` when `count <= 0`, else `floori(elapsed / hold_sec) % count`.
- `static func chase_transform(target_pos: Vector3, target_basis: Basis, distance: float, height: float, yaw: float) -> Transform3D`
  — behind-and-above the target, flattened to XZ, `look_at`-equivalent basis
  built from the target forward so the camera faces the car.
- `static func yaw_drift(elapsed: float, rate_rps: float) -> float` — the slow
  beauty-pass rotation, `fposmod`-wrapped (project convention for time wrap,
  see `AGENTS.md` → DayNightDriver `fposmod`).

### Step 2 — `scripts/race/post_race_cinematic.gd` (new, shell)

`class_name PostRaceCinematic extends Node3D`. The thin adapter.

- `var state: int = CinematicDirector.State.RACING`.
- `func begin(standings: Array, line: Array[Vector3]) -> void` — store the line
  and standings source; `state = FINISHED`; start the dwell clock. If
  `line.size() < 2`, set a `_skip_cinematic` flag (stay in FINISHED forever).
- `func _process(delta) -> void` — drive `CinematicDirector.advance(...)` on
  DWELL_ELAPSED; on the FINISHED→CINEMATIC edge call `_enter_cinematic()`; keep
  the camera posed each frame; cycle the target every
  `CINEMATIC_TARGET_HOLD_SEC`.
- `func _enter_cinematic() -> void`:
  1. Resolve the player car (`VehicleManager.get_player_car()`); if null, stay
     in FINISHED (degraded, §5 T9).
  2. Resolve the racing line once (passed in from `RaceUI`).
  3. Create the auto-driver: `AIController.new()`; `player.add_child(driver)`;
     `driver.set_waypoints(_line, _nearest_index(player.global_position))`
     (nearest-index helper mirrors `RaceManager._nearest_centerline_index`,
     `race_manager.gd:375-390`); `driver.set_speed_multiplier(0.55)`.
  4. Build the cinematic camera: a `Camera3D` child of this node (or a child
     pivot), then retire every gameplay rig found by
     `_track_root()` (`ChaseCamera`/`OrbitCamera`/`HoodCamera`/`CockpitCamera`)
     exactly as `menu_clip_recorder.gd:294-304`.
  5. `emit_signal("cinematic_started")` (local signal; `RaceUI` listens to hide
     the overlay).
- `func _leave_cinematic() -> void` — Called on CANCEL: free the auto-driver,
  `set_input_override(Vector2.ZERO)`, `set_scripted_driver(false)`, restore the
  gameplay rigs (`set_process(true)`; set the previously-current rig's camera
  `current = true` — remember which one at enter), `state = FINISHED`.
- `func request_exit() -> void` — `state = EXIT`; `_leave_cinematic()` if in
  CINEMATIC (idempotent); `emit_signal("exit_requested")`.
- `func _track_root() -> Node3D` — nearest `Node3D` ancestor of the parent
  (or `get_tree().current_scene` if it is a `Node3D`); `null`-safe.
- Resolution of the target each hold: `RaceManager.get_standings()`
  (`race_manager.gd:451`); index via `CinematicDirector.target_index(...)`;
  guard freed instances.
- **No new input actions.** Listen for the existing `ui_cancel` in
  `_unhandled_input` (like `RaceUI._unhandled_input`, `race_ui.gd:260-263`) to
  emit CANCEL. Do not touch `project.godot`'s input map.

### Step 3 — `scenes/ui/hud.tscn` (edit, additive)

After `ReturnFreeRoamButton` (`hud.tscn:591-595`), add inside
`Root/ResultsOverlay/Card/VBox/Buttons`:

```
[node name="ExitButton" type="Button" parent="Root/ResultsOverlay/Card/VBox/Buttons"]
unique_name_in_owner = true
custom_minimum_size = Vector2(0, 46)
size_flags_horizontal = 3
text = "EXIT"
```

Additive only: **do not** rename or reorder the two existing buttons, and
**do not** touch `%ResultsOverlay`'s other children. (Coordination note in §7.)

Optionally add one additive label for the cinematic prompt, e.g.
`CinematicPrompt` (`Label`, full-rect, `visible = false`) under `Root`, so the
`CINEMATIC` state can tell the player how to return. If the concurrent HUD agent
owns that space, reuse `%Banner` (`race_ui.gd:36`) instead — either is fine.

### Step 4 — `scripts/race/race_ui.gd` (edit)

- Add `const TRACK_SELECT_SCENE := "res://scenes/ui/track_select.tscn"` next to
  `FREE_ROAM_SCENE` (`race_ui.gd:10`).
- Add `@onready var exit_button: Button = %ExitButton` next to the existing
  button refs (`race_ui.gd:49-50`) and
  `exit_button.pressed.connect(_on_exit)` in `_ready` (next to line 116).
- Add `var _cinematic: PostRaceCinematic = null` and
  `var _post_race_state: int = CinematicDirector.State.RACING`.
- In `_on_race_finished` (line 265), after `_bank_race_rewards` (line 300):
  `_post_race_state = CinematicDirector.State.FINISHED` and create the
  cinematic: instantiate `PostRaceCinematic`, add it to the resolved track root
  (first `Node3D` ancestor, else a `Node3D` `current_scene`; if none, add to
  `self` and let it run camera-less), connect its `cinematic_started` →
  `_on_cinematic_started`, `exit_requested` → `_on_exit`, then
  `begin(RaceManager.get_standings(), _resolve_gap_path())`.
- `func _on_cinematic_started()` — hide `results_overlay`, show the prompt (or
  set `%Banner`).
- `func _on_exit()` — new handler for the EXIT button:
  ```
  _set_post_race_state(CinematicDirector.State.EXIT)   # drives _cinematic.request_exit()
  _race_over = false
  _rewards_banked = false
  results_overlay.visible = false
  confetti.reset()
  launch_callback.call(TRACK_SELECT_SCENE)
  ```
  Mirrors `_on_return_free_roam` (`race_ui.gd:374-382`).
- `_on_next_race` (line 367) and `_on_return_free_roam` (line 374): also
  `_set_post_race_state(CinematicDirector.State.RACING)` and free/stop the
  cinematic, so a re-armed ceremony cannot inherit a live cinematic or a
  scripted player car.
- Keep the early-return in `_process` (`race_ui.gd:170-171`) untouched; the
  cinematic runs on its own `_process`.

### Step 5 — `tests/suites/test_post_race_cinematic.gd` (new)

See §5.

### Step 6 — (follow-up, non-blocking) menu-clip capture

`scenes/capture/post_race_cinematic_capture.tscn` (root `Node3D` instancing
`northern_isle.tscn`) + `tools/record_post_race_clip.py`, per
`docs/plans/main_menu_video_bg_plan.md` §3B (`--windowed --resolution 1280x720
--fixed-fps 30 --write-movie ...`, `CAPTURE_READY`/`CAPTURE_END` markers,
`ffmpeg -an` trim) → `assets/videos/menu_race_finish.ogv`, then
`--headless --import .`. **Do not start this until §4 Steps 1-5 are green.**

---

## §5 TEST PLAN

### 5.1 New suite `tests/suites/test_post_race_cinematic.gd`

Conventions: `extends GdUnitTestSuite`, managed-node arrays + `after_test`
freeing (mirror `test_race_results.gd:23-46` and `test_rival_ai.gd:18-46`),
`assert_that` / `assert_float`, no reliance on a live world.

| ID | Test name | Assertions |
|---|---|---|
| **T1** | `test_state_machine_transitions_are_pure` | Every legal edge returns the expected state; every illegal pair is identity; `EXIT` is absorbing |
| **T2** | `test_dwell_gates_finished_to_cinematic` | `advance(FINISHED, DWELL_ELAPSED, 5.9, 6.0) == FINISHED`; `... 6.0 ... == CINEMATIC`; `advance(CINEMATIC, CANCEL, ...) == FINISHED` |
| **T3** | `test_target_index_cycles_the_field` | `count=0 → 0`; `count=3, elapsed 0→0, 3.9→0, 4.0→1, 8.0→2, 12.0→0` |
| **T4** | `test_chase_transform_sits_behind_and_above` | Camera origin is `distance` behind and `height` above the target on XZ; the basis forward points at the target (`-Z` axis dot target-forward > 0) |
| **T5** | `test_cinematic_attaches_auto_driver_and_overrides` | Build a stub `VehiclePhysics` (via `VehicleManager.register_player_car`), call `begin(standings, line)`, force DWELL_ELAPSED; assert a child `AIController` exists with `waypoints.size() == line.size()`, then call its `_physics_process(0.016)` and assert `car.input_override != Vector2.ZERO` (the override path floors at 0.01, `ai_controller.gd:238-240`) |
| **T6** | `test_cinematic_retires_gameplay_rigs` | Build a fake track root with `ChaseCamera` (`Node3D` + child `Camera3D current=true`) and the three other rigs; enter cinematic; assert each rig's `is_processing() == false` and every descendant `Camera3D.current == false`, and the cinematic camera `current == true` |
| **T7** | `test_exit_button_launches_track_select` | `scene_runner("res://scenes/ui/hud.tscn")`, `simulate_frames(1)`, set `launch_callback` spy, `%ExitButton.emit_signal("pressed")`, assert `launched == ["res://scenes/ui/track_select.tscn"]` and `%ResultsOverlay.visible == false` |
| **T8** | `test_leaving_cinematic_restores_player_control` | After T5 state + `request_exit()`/CANCEL: `car.input_override == Vector2.ZERO`, `car.scripted_driver == false`, auto-driver not `is_instance_valid` |
| **T9** | `test_cinematic_is_null_safe_without_track_root` | `begin()` with no `Node3D` root and no player car: no error, state still advances, no camera created |
| **T10** | `test_cinematic_rig_is_reachable_for_recording` | The shell exposes `begin()`/state/`Camera3D` names used by the follow-up capture harness (API-present; guards a rename regression) |
| **T11** | `test_exit_stops_a_live_cinematic` | At CINEMATIC, `_on_exit()` tears the driver down before `launch_callback` fires (assert the spy ran and the driver is freed) |
| **T12** | `test_next_race_resets_post_race_state` | After a cinematic, pressing `%NextRaceButton` returns state to `RACING` and stops the cinematic (no scripted player car carries into the new ceremony) |

### 5.2 Existing suites that MUST stay green

- `tests/suites/test_race_results.gd` — the results screen, both existing
  buttons, the exact `finish_race()` total bracket (lines 75-199).
- `tests/suites/test_race_loop.gd` — race lifecycle + `after_test` discipline.
- `tests/suites/test_rival_ai.gd` — the `AIController`/`RivalDriver`
  `input_override` control path and the configured-roster spawn.
- Any suite touching `hud.tscn` structure (the Exit button is additive; no node
  is renamed).

### 5.3 Run order

1. `tools\pick.bat` read of the new/edited files for a manual pass.
2. Import probe once (`cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE!
   --headless --import . 2>&1"`) — expect zero `SCRIPT ERROR` / `Parse Error`.
3. The new suite, then the three must-stay-green suites, one `-a` per suite
   (`-a` is repeatable, comma-joined paths do not work — `docs/GDUNIT_GATE.md`).

### 5.4 Full gate

`py tools\gdunit_parallel.py -j 4` (PC; the laptop has no `py`, see
`AGENTS.md`). Gate on the **changed suites**, not a hard-coded total; the
all-green baseline is 1018 cases. Run the full suite as ONE background
sub-agent, never in the main session's foreground.

---

## §6 RISKS / GOTCHAS

- **Leak discipline (the big one).** The auto-driver and cinematic `Camera3D`
  are new nodes. Mirror `test_race_loop.gd` / `test_race_results.gd`:
  `after_test` frees every managed driver/camera/car and resets `RaceManager`
  (`is_race_active`, `_participants`, `_lap_counters`, `_countdown`,
  `consume_pending_race`) and `VehicleManager`. In the game, the shell must
  `queue_free()` the driver on CANCEL/EXIT, and a scene change frees the
  cinematic (it is parented to the track root) — but **`RaceManager` is an
  autoload**, so its `_spawned_rivals` are freed only by
  `_on_scene_changed → clear_rival_config` (`race_manager.gd:61-74`). Never
  parent the cinematic or its camera to `RaceManager`.
- **Camera handoff.** At enter, remember which rig was `current` and restore
  exactly that one at exit; disabling all four rigs without recording the prior
  state leaves the player with **no camera** on cancel. Copy
  `menu_clip_recorder.gd:283-304` verbatim (disable process + clear `current`),
  and add the inverse.
- **`ChaseCamera` rebuilds its own camera.** `chase_camera.gd:43-47` creates a
  new `Camera3D` in `_ready`. If a rig is re-added/re-`_ready`'d mid-cinematic it
  will re-assert `current = true` and steal the view. Re-disabling processing
  (not just `current`) prevents `_update_camera` from running; the camera itself
  is created only once, so disabling process is sufficient — do **not** rely on
  `current` alone.
- **Input re-enable on exit/cancel.** `set_scripted_driver(true)` also forces
  AUTO (`vehicle_physics.gd:261-262`); leaving it set after a cancel would
  silently cap the player to AUTO. Always pair `set_input_override(Vector2.ZERO)`
  with `set_scripted_driver(false)`.
- **No auto-driver without a line.** If `_resolve_gap_path()` returns `< 2`
  points (solo races: mountain_pass, flat test tracks — §2.2), skip the
  cinematic and leave the results card up. Do not attach a driver to a car with
  no waypoints (it would sit still and look broken).
- **`RaceUI`/`PostRaceCinematic` `_process` ordering.** Godot ticks children
  before parents; the cinematic must be a child of the track root (sibling of
  the rigs), not of `RaceUI`'s `CanvasLayer`, or its `_process` may run after
  the cars' physics within a frame. Camera posing is presentation-only, so this
  is tolerance, but the driver node itself must be a child of the car so it
  ticks with the car.
- **Headless / HUD-only tests have no track root.** `get_tree().current_scene`
  in `scene_runner` may be a `CanvasLayer` and `VehicleManager.get_player_car()`
  may be null. The shell must be `null`-safe (§3.3, T9); never assume rigs or a
  player exist.
- **`get_tree().paused` is not cleared by `change_scene`** (`game_state.gd:133-142`).
  The racing path never pauses, so EXIT→track_select is safe; but if a future
  path reaches EXIT while paused, the destination would be frozen. Note, do not
  "fix" `change_scene` (it is a shared autoload and out of scope — §7).
- **Additive `hud.tscn` edits only.** The results overlay is also being touched
  by the concurrent speed-trap HUD work. Add `ExitButton`; never reorder or
  rename `NextRaceButton` / `ReturnFreeRoamButton` / `ResultsOverlay` children,
  or a three-way merge will silently break a test.
- **Two-button-row width.** Three buttons in a fixed-width card
  (`hud.tscn:504-507`, offsets ±340) may crowd at small resolutions. Prefer
  `size_flags_horizontal = 3` (already the pattern) and short text ("EXIT").
- **`-` in Godot CLI vs the shell.** All commands here are the cmd.exe forms
  from `AGENTS.md`; never type POSIX pipelines, and resolve Godot through
  `godot_path.bat`.
- **Determinism for the recorded clip (Step 6 only).** Follow
  `menu_clip_recorder.gd`'s determinism rules (force High look, fix the clock,
  force CLEAR weather, pin `TrafficDriver`'s proximity probe at `FAR_AWAY`).
  This risk does not apply to the in-game feature.

---

## §7 DO NOT TOUCH

Hard boundaries. These belong to **concurrent agents** and/or other workstreams;
touching them in this change would collide:

- **Barcelona track materials** — `scenes/track/barcelona_rx.tscn`,
  `scripts/track/barcelona_rx.gd`, and any Barcelona-specific material/asset
  under `assets/`. (Barcelona publishes a rival centerline, so the cinematic
  *reads* `RaceManager.rival_centerline` there — it never edits the scene.)
- **Race menu UI** — `scripts/ui/track_select.gd`, `scenes/ui/track_select.tscn`,
  `scripts/ui/main_menu.gd`, `scenes/ui/main_menu.tscn`, and the track-select
  card/map widgets. This plan only **navigates to** `track_select.tscn`; it does
  not edit it.
- **Speed-trap HUD** — whatever node/script owns the speed-trap readout inside
  `scenes/ui/hud.tscn` / `scripts/race/`. The `ExitButton` is an **additive**
  node in the `Buttons` row only; do not modify or restyle other HUD nodes.
- **Cockpit view** — `scripts/vehicle/cockpit_*` / `CockpitRig` / the
  `CockpitCamera` rig and its interior assets. The cinematic retires the
  cockpit rig at enter and restores it at exit; it never edits the rig.
- **Plugins** — `.opencode/plugins/**`, `addons/**` (including
  `addons/gdUnit4`), and `tools/pick.ps1` / `pick.bat` / `godot_path.bat`.
- **Shared autoloads** — do **not** change `autoload/game_state.gd`
  (`change_scene`'s `get_tree().paused` behaviour is deliberately left alone) or
  `autoload/race_manager.gd`'s finish/spawn logic. The cinematic is additive
  around `race_finished` and `get_standings()`; it must not alter
  `finish_race()`, `is_race_active`, or rival spawning.
- **`VehiclePhysics` motion/physics** — the cinematic uses the **existing**
  `set_input_override` / `set_scripted_driver` seams only. No change to
  `vehicle_physics.gd`, `AIController`, `RivalDriver`, `RacingLine`, or the
  drivetrain.
- **`project.godot` input map** — no new input actions (reuse `ui_cancel` /
  `ui_accept`).
- **The main-menu video plan's owned files** — `scenes/ui/main_menu.tscn`,
  `scripts/ui/menu_video_*.gd`, `scripts/capture/menu_clip_recorder.gd`,
  `tools/record_menu_clips.py`, `assets/videos/**`. Step 6 is a *separate*
  follow-up that reuses the recipe; it must not modify those files.

---

## §8 EXECUTION ORDER (after approval)

1. Land Step 1 + Step 2 (pure core + shell) with Step 5 T1-T6, T8-T12.
2. Land Step 3 + Step 4 (Exit button + RaceUI wiring) with Step 5 T7.
3. Import probe → new suite → the three must-stay-green suites → parallel gate.
4. Playtest: finish a race on `northern_isle` (rivals present) and
   `mountain_pass` (solo — expect the cinematic to skip gracefully); confirm the
   EXIT button lands on track select with a fade and the pads re-drive the car.
5. Only then, Step 6 (record `menu_race_finish.ogv`) as a separate op.
