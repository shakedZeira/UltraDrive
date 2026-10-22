# Plan — Race Opponent Car Audio (audible, spatially-positioned rival engines)

Status: **PLAN ONLY** (written 2026-10-16 by planner subagent; no game code touched).
User report: *"I can't hear the other cars when I'm racing them."*

---

## 1. Goal + acceptance criteria

**Goal:** every opponent/rival car in a race emits an audible, spatially-positioned
engine sound driven by the same live RPM/throttle → pitch/volume mapping the
player's car uses (`EngineAudio`), with distance behaviour tuned so a full grid
is audible as a pack but never a wall of noise, without regressing player audio,
traffic audio, settings volume, or perf.

**Player-verifiable acceptance criteria** (start a race with `opponents >= 1`,
Northern Isle or any track that publishes a centerline):

1. **Audible:** on the starting grid and while racing, rival engine sound is
   clearly heard whenever a rival is within ~40 m — no input/config needed.
2. **Positional:** the sound pans to the rival's screen side (rival on the left
   is heard left, overtaking on the right is heard right), and moves with it.
3. **Pitch follows revs:** a rival accelerating sounds higher-pitched than one
   coasting; pitch changes continuously with its RPM (same ladder as the player).
4. **Distance behaviour:** a rival falls to inaudible past ~60 m (tunable) and
   ramps back in as it closes; the player's own engine remains the dominant,
   closest source at the grid (rivals trimmed below player level).
5. **Pack, not wall:** with 7 rivals in a tight pack the sum is clearly louder
   than one car but does not drown the player's engine or the countdown/HUD.
6. **Settings intact:** the Settings volume slider still scales everything
   (Master-bus only, unchanged).
7. **No regressions:** solo race (`opponents = 0`) byte-identical; free-roam
   traffic audio unchanged (still distance-culled by `traffic_spawner`);
   player engine/turbo audio unchanged; targeted GDUnit gate green (§5).

---

## 2. Current state — VERIFIED (file:line)

### 2.1 Player audio path (the working one)

- `scenes/vehicle/player_car.tscn:7` — ext_resource `res://scripts/audio/engine_audio.gd`;
  `player_car.tscn:53-56` — node `EngineAudio` (`AudioStreamPlayer3D`, script
  `engine_audio.gd`, `unit_size = 2.0`, `max_distance = 80.0`).
- `scripts/audio/engine_audio.gd:1-2` — `class_name EngineAudio extends AudioStreamPlayer3D`.
  It is **self-driving**: `_ready()` (`:175-185`) resolves its parent as
  `VehiclePhysics` (`:178`), loads five loop beds (per-timbre: sport/muscle/rally/gtr,
  `:27-70`, `:198-216`), creates **five child `AudioStreamPlayer3D` band players**
  (`_create_band_players`, `:225-235`) and starts them. `_physics_process()`
  (`:306-393`) reads the parent's `VehiclePhysics.get_drive_info()`
  (`scripts/vehicle/vehicle_physics.gd:490` → keys `rpm` `:501`, `throttle` `:505`,
  `gear`) and each frame writes `player.pitch_scale`
  (`engine_audio.gd:379`) and `player.volume_db` (`:380-383`) onto the band
  players, plus optional turbo voices (`:352-353`, `:275-303`).
- So **any `AudioStreamPlayer3D` running `engine_audio.gd` as a direct child of a
  `VehiclePhysics` works with zero external wiring** — no caller needs to feed it.
- LPF: only when the node's car `== VehicleManager.get_player_car()` (`:387-393`)
  does it install/drive a low-pass filter — on the **Master bus**
  (`_ensure_lpf`, `:800-817`). Non-player instances never touch the bus.

### 2.2 Opponent instantiation path (the silent one)

- Race start seam: `scripts/race/race_ui.gd:132` →
  `RaceManager.start_race(VehicleManager.get_all_cars(), laps)`
  (`autoload/race_manager.gd:127-150`).
- Rivals are spawned inside `start_race` → `_spawn_configured_rivals()`
  (`race_manager.gd:134`, `:194-209`) → **`_spawn_rival_car()`**
  (`race_manager.gd:211-248`), which instantiates `rival_vehicle_scene`,
  default **`preload("res://scenes/vehicle/rival_car.tscn")`** (`race_manager.gd:38`).
  Roster comes from `configure_default_rivals()` (`race_manager.gd:267-293`,
  `GameState.opponents` default **5**, `autoload/game_state.gd:27`, cap 7
  `race_manager.gd:18`). Alternate spawn path: `scripts/ui/grid_spawner.gd:44-67`
  (`_build_car`, also `preload("res://scenes/vehicle/rival_car.tscn")` at `:19`).
- **Root cause:** `scenes/vehicle/rival_car.tscn` (36 lines, read in full) contains
  only `RivalCar` (root, `vehicle_physics.gd`), `CollisionShape3D`, `CarBody`
  (`rival_car_visual.gd`) and `WheelFL/FR/RL/RR` — **no `EngineAudio` node, no
  audio script ext_resource of any kind**. Neither `_spawn_rival_car` nor
  `GridSpawner._build_car` creates one. Rivals are therefore 100% silent.
- Contrast — traffic *does* have audio: `scripts/world/traffic_spawner.gd:49,107`
  does `vehicle.get_node_or_null("EngineAudio")` for distance culling/LOD; traffic
  spawns the **player scene** (comment at `traffic_spawner.gd:135-136`), which
  carries the node. Rivals spawn `rival_car.tscn`, which does not.
- `scripts/vehicle/car_audio.gd` (`CarAudio`, feel layers: squeal/wind/impact/shift)
  is **not attached to any scene or spawned by any script** (project-wide grep:
  only test suites instantiate it). It is not part of the runtime audio path and
  is out of scope; the engine sound is `EngineAudio`.

### 2.3 Buses / settings

- **There is no `default_bus_layout.tres` anywhere in the project** (glob
  `**/default_bus_layout*` → none) and `project.godot` has no bus-layout/audio
  keys → the game runs on the single built-in **Master** bus.
- Settings: `scripts/ui/settings_menu.gd:599-600` — the volume slider sets
  `AudioServer.set_bus_volume_db(get_bus_index("Master"), linear_to_db(value))`.
  No SFX/Music split exists. `EngineAudio` band/turbo children never set `bus`,
  so they inherit Master automatically → **adding rival audio needs zero
  bus/volume-menu work**; criterion 6 comes for free.

### 2.4 Why it must be designed around `_ready`'s hard-coded spatial params

- `engine_audio.gd:176-177` **unconditionally stomps** `unit_size = 2.0` and
  `max_distance = 80.0` in `_ready()`, before creating the band children
  (`:229-230` copy those values). Scene-file overrides of those two *inherited*
  properties on an `EngineAudio` node are therefore **silently ignored** — the
  player scene's serialized `unit_size/max_distance` (`player_car.tscn:55-56`)
  only *look* like they do something. Per-car spatial tuning needs new exported
  properties, not inherited ones (renaming/repurposing the inherited ones would
  also orphan `player_car.tscn:55-56` serialization — see §7).

---

## 3. Design decisions (options considered → chosen)

| # | Option | Verdict |
|---|--------|---------|
| A | **Add an `EngineAudio` node directly to `scenes/vehicle/rival_car.tscn`** (mirror of `player_car.tscn:53`) | **CHOSEN.** One minimal scene edit covers *both* production spawn paths (RaceManager `:211` + GridSpawner `:44`) and every test that instantiates the scene. Reuses `engine_audio.gd` logic verbatim — nothing duplicated. |
| B | Runtime-attach helper (`EngineAudio.new()` + `add_child`) called from `_spawn_rival_car` and `_build_car` | Rejected as primary: two call sites to keep in sync, misses any future/`set_rival_vehicle_scene`-swapped scene, harder to assert structurally in tests. Kept as an **optional belt-and-braces** (Step 3, optional) because it is idempotent and covers scene swaps. |
| C | New lightweight rival-only sound (single loop, simple rpm→pitch) | Rejected: duplicates the pitch/volume/load mapping the task explicitly wants reused, and drifts from the player's timbre families. |
| D | Non-positional `AudioStreamPlayer` bus mix for the pack | Rejected: fails acceptance criteria 2/3 (spatial + rev-tracking). |

**Mix / near-field / pack decisions (on top of option A):**

- **Trim:** new `@export var extra_trim_db` (default `0.0` = player unchanged),
  added to each band target **before** the existing `MUTE_FLOOR..6 dB` clamp so
  rivals sit below the player (`-4.0 dB` start value, playtest-tunable).
- **Spatial reach:** new exports `spatial_unit_size` (default `2.0`) and
  `spatial_max_distance` (default `80.0`) that `_ready()` applies instead of the
  literals — player behaviour byte-identical (same numbers), rival scene opts into
  a shorter reach (`60.0`) + slightly larger `unit_size` (`2.5`) so a distant pack
  fades instead of stacking. (Godot attenuates/mix-culls at `max_distance`, which
  is the main "wall of noise" breaker; verify `rolloff_*`/attenuation-model
  property names against the 4.7 `AudioStreamPlayer3D` API during implementation
  — defaults `INVERSE_DISTANCE` + `unit_size` are what the player already uses.)
- **Distance LOD:** new `@export var auto_cull_range` (metres, **default `0.0` = OFF**
  so player + traffic keep today's exact behaviour — traffic's cull at
  `traffic_spawner.gd:46-51` stays authoritative). Rival node sets `150.0`; the
  node then reuses the existing `cull_by_distance()` / `set_audio_active()`
  machinery (`engine_audio.gd:396-419`) against `VehicleManager.get_player_car()`,
  so far rivals stop their band loops entirely. **Placement inside
  `_physics_process` is a correctness issue, see §6.1.**
- **Per-rival timbre:** rivals get the player's `CarConfig`
  (`race_manager.gd:267-280` → `_player_config`), so `_apply_profile()`
  (`engine_audio.gd:198-216`, re-checked every frame) gives them the correct
  bed family automatically. All rivals sharing the player's engine family is the
  designed "even field" — noted as a possible future per-persona timbre pass, NOT
  in this plan.
- **No bus work, no settings-menu work** (§2.3).
- **No `player_car.tscn` edit needed at all** — the player already has audio; we
  only change files we own plus one minimal `rival_car.tscn` edit (flagged in §7).

---

## 4. Implementation steps — ordered, exact files/nodes/functions

> Style: `scripts/audio/engine_audio.gd` uses **TAB** indentation; `rival_car.tscn`
> is Godot-serialized text. Re-read each anchor right before editing (line numbers
> in §2 are the verified baseline).

**Step 1 — `scripts/audio/engine_audio.gd`: add the four exports (top of class,
near `volume_curves` at `:142`).**

```gdscript
## Spatial defaults applied in _ready (new exports so scenes can override
## WITHOUT being stomped by the old hard-coded literals; do NOT reuse the
## inherited unit_size/max_distance as the override channel — serialized
## player_car.tscn values and the _ready assignment must both stay valid).
@export var spatial_unit_size: float = 2.0
@export var spatial_max_distance: float = 80.0
## Extra level trim (dB) applied AFTER the timbre master trim and BEFORE the
## floor/ceiling clamp. 0.0 = player. Rivals use a negative value so a pack
## never overpowers the player's own engine.
@export var extra_trim_db: float = 0.0
## When > 0 and this node is NOT the player, distance-cull audio against the
## player car each physics tick (0 = off: player + traffic keep legacy behaviour).
@export var auto_cull_range: float = 0.0
```

**Step 2 — `scripts/audio/engine_audio.gd`: honour the exports.**

- `_ready()` `:176-177`: replace the literals
  `unit_size = 2.0` / `max_distance = 80.0` with
  `unit_size = spatial_unit_size` / `max_distance = spatial_max_distance`
  (still runs *before* `_create_band_players()` `:182`, which copies them at
  `:229-230` — order unchanged).
- Band target in `_physics_process` `:380`:
  `clampf(band_gain_db(weights[i], load_gain, trans_db) + _trim_db + extra_trim_db, MUTE_FLOOR_DB, 6.0)`
  (trim **inside** the clamp). Apply the same `+ extra_trim_db` to the turbo
  whine target `:285` and one-shot targets `:293` / `:301` for consistency —
  one-line each, keeps turbo/bud levels coherent on rivals.
- **Auto-cull block at the very TOP of `_physics_process` `:306`, i.e. BEFORE the
  `_culled` early-return at `:309-316`:**

```gdscript
if auto_cull_range > 0.0 and not _is_player:
    var ref := VehicleManager.get_player_car()
    if ref != null:
        cull_by_distance(ref.global_position, auto_cull_range)
```

  Rationale (must not be reordered): once `_culled` is true the function returns
  at `:309`, so a check placed *after* it could never un-cull — see §6.1.
  `_is_player` defaults to `false` (`:154`) and is only ever set true for the
  player's own node (`:387-388`), and the player/traffic scenes leave
  `auto_cull_range` at `0.0`, so no behaviour changes for them.

**Step 3 (OPTIONAL, recommended) — idempotent attach helper for swapped scenes.**

- In `scripts/audio/engine_audio.gd`, add a static:
  `static func ensure_for(car: VehiclePhysics) -> EngineAudio` — returns the
  existing child if `car.get_node_or_null("EngineAudio")` is one, else creates
  `EngineAudio.new()`, names it `EngineAudio`, sets `auto_cull_range = 150.0`,
  `extra_trim_db = -4.0`, `spatial_max_distance = 60.0` and `car.add_child(audio)`.
- Call it after `add_child(car)` in `autoload/race_manager.gd::_spawn_rival_car`
  (right after `:228`) and `scripts/ui/grid_spawner.gd::_build_car`
  (right after `:59`). Guard makes it a no-op when the scene already ships the
  node (Step 4), and it covers `RaceManager.set_rival_vehicle_scene()` swaps
  (`race_manager.gd:158`) plus any future rival scene.
- If this step is skipped, Step 4 alone still fully fixes the reported bug.

**Step 4 — `scenes/vehicle/rival_car.tscn`: add the audio node (the fix).**

- Bump line 1: `load_steps=5` → `load_steps=6`.
- Add after the existing ext_resources (`:3-5`):
  `[ext_resource type="Script" path="res://scripts/audio/engine_audio.gd" id="4_audio"]`
- Append at the end of the file (after `WheelRR`, mirroring "systems nodes last"):
  ```
  [node name="EngineAudio" type="AudioStreamPlayer3D" parent="."]
  script = ExtResource("4_audio")
  spatial_max_distance = 60.0
  spatial_unit_size = 2.5
  extra_trim_db = -4.0
  auto_cull_range = 150.0
  ```
- Nothing else in the scene changes (no collisions/wheels/visuals touched).

**Step 5 — tests** (new suite only; no existing suite edited) — §5.

**Step 6 — gate + housekeeping.**
- Run the targeted suite list of §5 via the known-good headless recipe
  (`docs/GDUNIT_GATE.md`; `-a` is repeatable, comma-joined paths false-green),
  then the full suite as a **background sub-agent** per AGENTS.md.
- Player playtest for acceptance criteria 1-7 (§1), tune `extra_trim_db` /
  `spatial_max_distance` / `auto_cull_range` on the rival node only — the
  exports keep tuning to 3 numbers in one scene block.
- `graphify update .` after code changes (per AGENTS.md; graph is docs/tooling
  only, but the rebuild is still the standing rule).

---

## 5. Test plan (GDUnit4)

Conventions: `assert_that(...).is_equal` / `.is_equal_approx(x, tol)`; **gdUnit
treats GDScript warnings as errors** — declare types explicitly
(`var audio: EngineAudio = node.get_node_or_null("EngineAudio")`, never
`:=` on a `Variant`-returning call); tests cannot assert *audible* sound, only
node presence, configuration, and that the mapping code ran; headless display
server auto-skips turbo players (`should_create_turbo_players`,
`engine_audio.gd:754-757`) — no cleanup needed for those.

**New suite: `tests/suites/test_rival_car_audio.gd`**

1. `test_rival_scene_ships_engine_audio_node` —
   `var car: RigidBody3D`-typed instantiate of `load("res://scenes/vehicle/rival_car.tscn")`
   inside `auto_free`; assert `get_node_or_null("EngineAudio")` `is_not_null`,
   `is EngineAudio`, `is AudioStreamPlayer3D` (positional, criterion 2's basis),
   and `extra_trim_db < 0.0`, `spatial_max_distance` `is_equal(60.0)`,
   `auto_cull_range > 0.0`.
2. `test_rival_audio_builds_five_band_children_with_streams` — after the node
   enters the tree (existing pattern, `test_engine_audio.gd:226-235`): child
   count `is_equal(5)`, each child `is AudioStreamPlayer3D`, `stream is AudioStream`,
   loop mode `LOOP_FORWARD`, `volume_db` at/below `MUTE_FLOOR_DB` before frames run.
3. `test_band_targets_include_extra_trim` — pure static: add a small static
   `band_gain_db_extra(weight, load_gain, transient, extra)` (or assert through
   the existing `band_gain_db` + documented `extra_trim_db` addition): trim
   lowers the result by exactly `extra`, never drops below `MUTE_FLOOR_DB`,
   never exceeds `6 dB`, monotonic in weight.
4. `test_spawned_rivals_have_engine_audio` — integration, harness copied from
   `test_race_rivals.gd:38-74` (`before_test`/`after_test` slot snapshot +
   `RaceManager` reset): `GameState.opponents = 3`, publish a centerline, call
   `RaceManager.configure_default_rivals(...)` + `RaceManager.start_race([...], 1)`,
   then for every `car in RaceManager.get_spawned_rivals()` assert an
   `EngineAudio` child exists, is 3D, and `bus == "Master"` (default — asserts
   criterion 6's wiring).
5. `test_rival_audio_pitch_volume_follow_drive_info` — on an instantiated
   rival (parent is `VehiclePhysics`, `_car` resolves at `engine_audio.gd:178`):
   await ~10 `get_tree().physics_frame`s, then read
   `car.get_drive_info()["rpm"]` and assert band-0 `pitch_scale` is within
   tolerance of
   `EngineAudio.band_pitch_scale_window(rpm, band_rpms[0], pitch_min, pitch_max)`
   and `volume_db > MUTE_FLOOR_DB + 6.0` (proves the mapping ran, criterion 3).
   Use the tolerant form documented above; if the car sits frozen/awaiting
   ground (`vehicle_physics.gd:147`), rpm stays at idle — the assertion still
   holds because idle is a valid mapping input.
6. `test_rival_audio_is_not_player_lpf_path` — register a *different* car as
   `VehicleManager.player_car`, run the rival's audio frames, assert
   `audio._lpf_added == false` (privates are already poked by suites like
   `test_race_rivals.gd:61`); guarantees rivals never add Master-bus effects.
7. `test_player_scene_audio_defaults_unchanged` — instantiate
   `scenes/vehicle/player_car.tscn`, assert its `EngineAudio` still reports
   `spatial_unit_size == 2.0`, `spatial_max_distance == 80.0`,
   `extra_trim_db == 0.0`, `auto_cull_range == 0.0` (regression lock for
   criteria 6/7 — the player path must be numerically identical).
8. *(only if Step 3 ships)* `test_ensure_for_is_idempotent` — call
   `EngineAudio.ensure_for(car)` twice on a rival, assert exactly one
   `EngineAudio` child.

**Targeted gate after implementation** (each `-a` separate, known-good cmd
forms in `docs/GDUNIT_GATE.md`): `test_rival_car_audio` (new),
`test_engine_audio`, `test_turbo_audio`, `test_car_audio`,
`test_car_sound_profiles`, `test_audio_feel_layers`, `test_race_rivals`,
`test_rival_ai`, `test_rival_personalities`, `test_car_paint_materials`,
`test_zzz_fall_probe`, `test_map_rival_blips`. Then full suite via background
sub-agent. Baseline for comparison: AGENTS.md measured
`1018 test cases | 0 errors | 0 failures` (parallel gate) / expect only the
+8-ish new cases.

**Playtest gate** (manual, cannot be automated): acceptance criteria 1-7.

---

## 6. Risks / gotchas

1. **Auto-cull placement is a deadlock trap.** If the distance check goes after
   the `_culled` early-return (`engine_audio.gd:309-316`), a culled rival can
   never re-activate (the code that could un-cull is unreachable). Must be at the
   top of `_physics_process`, before that return (Step 2). Also: `VehicleManager.get_player_car()`
   can be null in tests/free-roam moments — keep active (skip the call) rather
   than cull, so nothing silently mutes in harnesses that never register a player.
2. **`_ready` stomps inherited spatial props** (`:176-177`) — scene overrides of
   `unit_size`/`max_distance` do nothing today; that is exactly why the fix uses
   *new* exports. Do not "clean this up" by deleting `_ready`'s defaults without
   also updating `player_car.tscn:55-56` — and `player_car.tscn` is under a
   concurrent-task handshake (§7).
3. **Shared cached streams:** `load_beds_for()` (`:436-456`) mutates
   `loop_mode/loop_end` on `AudioStreamWAV`s returned by `load()`, which are
   ResourceLoader-cached and shared by player + traffic + all rivals. The
   mutation is idempotent and already multi-consumer today; keep it that way
   (no per-instance `duplicate()` — 7 rivals × 5 beds of duplicated PCM is the
   memory trap to avoid).
4. **Perf/voice count:** up to 7 rivals × 5 band players (+3 turbo for
   gtr-family configs, which the player's config often is) = 35-56
   `AudioStreamPlayer3D`s, but `max_distance` bounds Godot's 3D mixing and
   `auto_cull_range` stops the loops + our per-frame math beyond 150 m.
   `tools/perf_probe.gd:22-23` carries a *stale* comment claiming AI cars already
   tick `engine_audio` (rivals have no audio today) — after this change it
   becomes roughly true again; do not edit `tools/` (not ours), just don't be
   surprised, and watch `test_perf_gate` (relative mode on this GTX 970, see
   AGENTS.md PARALLEL GATE).
5. **Master-bus LPF quirk (pre-existing):** the player's audio installs an
   `AudioEffectLowPassFilter` on Master driven 900-8000 Hz (`:800-817`) — rival
   audio passes through it too (it is global). Do **not** let rivals take the
   LPF path (`_is_player` gate must stay, `:387-393`); N per-car bus effects
   would be an audio-quality and teardown disaster (`_remove_lpf` `:820-830`
   assumes single ownership).
6. **gdUnit false-greens:** warnings-as-errors (typed vars, no `:=` from
   Variant), `-a` paths must be one-per-flag, a suite aborts at first failure
   (compare executed counts to `func test_` count), and never gate on a
   hard-coded global total.
7. **Countdown/HUD interplay:** rivals now emit during the countdown too —
   `RaceCountdown.rev_rpm_override()` (`race_manager.gd:111-114`) only drives the
   drivetrain of cars the ceremony code touches; verify visually that rivals idle
   normally and the countdown audio (`scripts/race/countdown_audio.gd`) is not
   buried (criterion 5).
8. **Scene teardown:** rivals are `remove_child` + `queue_free`d by
   `_free_spawned_rivals` (`race_manager.gd:81-86`); `EngineAudio._exit_tree`
   (`:188-189`) only removes the LPF it never added as a rival — safe, no leak.

---

## 7. Do NOT touch — files owned by concurrent tasks

- **Car assets/materials:** `assets/cars/**`, `resources/cars/**`,
  `scripts/vehicle/car_visuals.gd`.
- **Camera scripts** (`scripts/camera/**`).
- **Garage UI:** `scenes/ui/garage.tscn`, `scripts/ui/garage_ui.gd`.
- **Track-select / race-menu UI:** `scripts/ui/track_select.gd`,
  `scenes/ui/track_select.tscn`, race-menu/hud entry points beyond the audio seam.
- **Track:** `scripts/track/**`, `scenes/track/**`,
  `scripts/track/track_registry.gd`.

**Interaction note — `scenes/vehicle/player_car.tscn`:** a concurrent task may
apply a **single minimal edit** there (windshield material). This plan requires
**no edit to `player_car.tscn` at all** (the player already ships `EngineAudio`,
and Step 2's new exports default to today's literal values, so nothing
serialized changes). If implementation ever needs to touch it, add **only**
audio nodes/properties and re-check the file immediately before editing.

**Files this plan DOES own/change:** `scripts/audio/engine_audio.gd`,
`scenes/vehicle/rival_car.tscn` (one node + one ext_resource + load_steps —
flagged as a minimal scene edit), `tests/suites/test_rival_car_audio.gd` (new),
and optionally `autoload/race_manager.gd` / `scripts/ui/grid_spawner.gd`
(one guarded call each, only if Step 3 ships).

---

## 9. STATUS — implemented (2026-10-16)

Implemented by the coding agent (not yet gated — **no Godot/GDUnit run was made
in this session**; a single full-suite gate is queued separately, per AGENTS.md).
Steps 1, 2, 3 (partial), 4 and 5 shipped; Step 6 (gate/playtest) is pending.

### 9.1 Files changed (file:line)

**`scripts/audio/engine_audio.gd`** — TAB indentation preserved.

- **New exports** at `:144-156` (immediately after `volume_curves`):
  - `spatial_unit_size: float = 2.0` (`:148`)
  - `spatial_max_distance: float = 80.0` (`:149`)
  - `extra_trim_db: float = 0.0` (`:153`)
  - `auto_cull_range: float = 0.0` (`:156`)
- **`_ready()`** `:190-191` — the hard-coded literals now read the exports:
  `unit_size = spatial_unit_size` / `max_distance = spatial_max_distance`
  (still before `_create_band_players()`).
- **Auto-cull block at the very top of `_physics_process`** `:323-330`, i.e.
  **before** the `_culled` early-return at `:331-338` (the §6.1 deadlock trap):
  ```gdscript
  if auto_cull_range > 0.0 and not _is_player:
      var ref := VehicleManager.get_player_car()
      if ref != null:
          cull_by_distance(ref.global_position, auto_cull_range)
  ```
  A null player skips the call (keeps the emitter ACTIVE), so harnesses with no
  registered player never silently mute.
- **Band target** `:402` —
  `clampf(band_gain_db(weights[i], load_gain, trans_db) + _trim_db + extra_trim_db, MUTE_FLOOR_DB, 6.0)`
  (trim **inside** the floor/ceiling clamp; `_trim_db` is the timbre master trim,
  `extra_trim_db` the rival delta).
- **Turbo layer trim** — `+ extra_trim_db` on the whine target `:299`, and on the
  BOV `:307` / flutter `:315` one-shot gains, so a turbo rival's whole layer is
  trimmed coherently.
- **New static `ensure_for(car: VehiclePhysics) -> EngineAudio`** at `:450-462`
  (Step 3): returns the existing `EngineAudio` child if present, else creates one
  named `EngineAudio` with `auto_cull_range = 150.0`, `extra_trim_db = -4.0`,
  `spatial_max_distance = 60.0` and parents it to `car`.

**`scenes/vehicle/rival_car.tscn`** — the fix (Step 4):

- `load_steps=5` → `load_steps=6` (`:1`).
- New ext_resource (after `:5`): `:6`
  `[ext_resource type="Script" path="res://scripts/audio/engine_audio.gd" id="4_audio"]`.
- New node appended after `WheelRR` (`:39-44`):
  ```
  [node name="EngineAudio" type="AudioStreamPlayer3D" parent="."]
  script = ExtResource("4_audio")
  spatial_max_distance = 60.0
  spatial_unit_size = 2.5
  extra_trim_db = -4.0
  auto_cull_range = 150.0
  ```
  Nothing else in the scene changed (collisions/wheels/visuals untouched).

**`autoload/race_manager.gd`** — Step 3 call site:

- `EngineAudio.ensure_for(car)` added right after `add_child(car)` in
  `_spawn_rival_car` (`:232`, with a 3-line comment at `:229-231`). No-op today
  (the shipped `rival_car.tscn` already carries the node); guarantees audio for a
  scene swapped in via `set_rival_vehicle_scene()`.

**`tests/suites/test_rival_car_audio.gd`** — new suite (Step 5), see §9.3.

### 9.2 Exact node / property values

| Knob | Player (`player_car.tscn`) | Rival (`rival_car.tscn`) | Export default |
|---|---|---|---|
| `spatial_unit_size` | 2.0 (export default; scene serializes inherited `unit_size = 2.0`) | **2.5** | 2.0 |
| `spatial_max_distance` | 80.0 (export default; scene serializes inherited `max_distance = 80.0`) | **60.0** | 80.0 |
| `extra_trim_db` | 0.0 | **-4.0** | 0.0 |
| `auto_cull_range` | 0.0 (off) | **150.0** | 0.0 |

The player path is numerically **byte-identical**: the new exports default to
exactly the literals `_ready` used to hard-code, and `player_car.tscn` was **not
edited** (its serialized inherited `unit_size`/`max_distance` stay valid and
unused-as-override, as §2.4/§6.2 require). Rival `ensure_for`-created nodes get
`spatial_unit_size` left at its default `2.0` (the plan's Step-3 spec sets only
the three other values).

### 9.3 Tests added — `tests/suites/test_rival_car_audio.gd` (9 cases)

1. `test_rival_scene_ships_engine_audio_node` (`:99`) — the scene ships a
   `AudioStreamPlayer3D`-typed `EngineAudio` with `extra_trim_db < 0`,
   `spatial_max_distance == 60`, `auto_cull_range > 0`.
2. `test_rival_audio_builds_five_band_children_with_streams` (`:114`) — after the
   node enters the tree: exactly 5 children (headless ⇒ no turbo), each a
   `AudioStreamPlayer3D` with an `AudioStream` stream in `LOOP_FORWARD`, initial
   `volume_db <= MUTE_FLOOR_DB`.
3. `test_band_targets_include_extra_trim` (`:139`) — pure static: the production
   target formula (`band_gain_db(...) + _trim_db + extra_trim_db`, clamped) lowers
   the result by exactly the trim, stays inside `MUTE_FLOOR_DB..6 dB`, is
   monotonic in weight, and the floor wins over a negative trim.
4. `test_spawned_rivals_have_engine_audio` (`:164`) — integration through
   `RaceManager.set_rival_roster()` + `start_race()`: every spawned rival has a
   3D `EngineAudio` on the `Master` bus (criterion 6) with `auto_cull_range > 0`.
5. `test_rival_audio_pitch_volume_follow_drive_info` (`:188`) — after 10 physics
   frames on a rival with the starter config, band-0 `pitch_scale` matches
   `band_pitch_scale_window(rpm, band_rpms[0], …)` within 0.05 and its `volume_db`
   climbed off the mute floor (the mapping actually ran; criterion 3).
6. `test_auto_cull_culls_far_and_unculls_when_player_returns` (`:220`) — the §6.1
   regression assertion: a rival culls when the player is far **and un-culls when
   the player returns** (proves the distance check sits before the `_culled`
   early-return).
7. `test_rival_audio_is_not_player_lpf_path` (`:240`) — a non-player emitter keeps
   `_is_player == false` and never adds the shared Master-bus LPF.
8. `test_player_scene_audio_defaults_unchanged` (`:258`) — regression lock: the
   player scene reports `spatial_unit_size == 2.0`, `spatial_max_distance == 80.0`,
   `extra_trim_db == 0.0`, `auto_cull_range == 0.0`, and inherited
   `unit_size == 2.0` / `max_distance == 80.0`.
9. `test_ensure_for_is_idempotent_and_configures_rivals` (`:276`) — `ensure_for`
   creates exactly one rival-grade node on a bare car, is idempotent, and is a
   no-op for a car that already ships the node.

Test **1 extra beyond the plan's 8** (case 6) to guard the deadlock trap; the
plan's test-3 static `band_gain_db_extra` helper was **not** added (the plan
allowed asserting through the existing `band_gain_db` + documented trim
addition), and test 4 uses `set_rival_roster`/`start_race` (the proven
`test_rival_ai.gd` harness) instead of `configure_default_rivals`, so **no
SaveManager slot write** occurs and no slot snapshot/restore is needed.

Expected gate delta: **+9 test cases** over the AGENTS.md parallel baseline
`1018 test cases | 0 errors | 0 failures`. No global total is hard-coded.

### 9.4 Deliberate deviation — `grid_spawner.gd` call omitted

The plan's Step 3 also proposed an `EngineAudio.ensure_for(car)` call in
`scripts/ui/grid_spawner.gd::_build_car`. **Not added**: `scripts/ui/*` is under
a concurrent-task handshake (AGENTS.md / §7) and was off-limits. This is safe —
`GridSpawner` instantiates the **same `rival_car.tscn`** (default at
`grid_spawner.gd:19`), so the Step-4 scene fix already covers that spawn path.
The `ensure_for` helper still covers `RaceManager.set_rival_vehicle_scene()`
swaps through its `race_manager.gd:232` call site.

### 9.5 What the gate must confirm (Step 6, pending)

- Targeted suites per §5 (one `-a` each) + the full suite via the background
  parallel gate; expect `+9` cases, **0 errors / 0 failures**, and no new
  `perf_gate` failure (watch the `mode=` line; the GTX 970 runs relative mode).
- No new `SCRIPT ERROR` / `Parse Error` in the import probe — in particular the
  new `EngineAudio` node loads in `scenes/vehicle/rival_car.tscn` and both suites
  load clean under gdUnit warnings-as-errors (typed vars; `loop_mode` read only
  through an `AudioStreamWAV` cast).
- **Not verifiable headless (playtest):** acceptance criteria 1-7 — audibility of
  a rival pack, left/right panning, ±60 m distance fade, and that the rival pack
  does not drown the player or the countdown (tune `extra_trim_db` /
  `spatial_max_distance` / `auto_cull_range` on the rival scene block only).

### 9.6 Open risks carried forward

- **Relative-mode perf gate blind spot** (AGENTS.md): a rival-audio cost that
  slows every preset equally is undetectable on this box; only the playtest and
  the absolute mode on a reference rig would catch it.
- **Voice count:** up to 7 rivals × 5 band players (+3 turbo for a gtr-family
  config) = 35-56 `AudioStreamPlayer3D`s; `max_distance` + `auto_cull_range`
  bound it, but not load-tested here.
- Rivals use the player's engine family ("even field", §3); per-persona timbre
  remains a future pass.
