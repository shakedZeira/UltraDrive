# Main Menu Video Background Plan

**Goal:** the main menu plays short, **silent**, looping **in-game** clips in
the background — open world + cars — so the menu is never a flat grey screen.

Target rig: **GeForce GTX 970** (Maxwell, Vulkan), 1920x1080, **Forward+**,
Jolt, Terrain3D, Godot **4.7.2**. Related: `docs/ROADMAP.md`;
`docs/plans/open_world_seeding_plan.md`; `docs/plans/terrain_vista_plan.md`.

**Working agreement: planning only. Do NOT implement until approved.** The only
file this plan authorises is itself; the code/scene/asset changes below are the
*proposal*, and the recorded `.ogv` clips are a **follow-up the orchestrator
runs after approval** (this session cannot run Godot).

---

## §1 CURRENT STATE (verified by reading the tree)

### 1.1 The main menu today

- `scenes/ui/main_menu.tscn` is a bare full-rect `Control` (line 6) with two
  children: `UiBlip` (an `AudioStreamPlayer`, line 14) and `MenuLayout`
  (`VBoxContainer`, line 17) holding six buttons (lines 30-53). **There is no
  backdrop, no `WorldEnvironment`, no 3D, no video** — the menu is transparent
  over the project clear colour
  `environment/defaults/default_clear_color = Color(0.3, 0.3, 0.35, 1)`
  (`project.godot:171`), i.e. flat grey.
- `scripts/ui/main_menu.gd` (47 lines) wires the blip + six `pressed` handlers
  only. No `_process`, no background logic.
- Entry into the menu: `application/run/main_scene` is
  `res://scenes/ui/intro_video.tscn` (`project.godot:11`), which hands off via
  `SceneTransition.flash_to_scene("res://scenes/ui/main_menu.tscn")`
  (`scripts/ui/intro_video.gd:13,92`). The pause menu also has a quit-to-menu
  path (`scripts/ui/pause_menu.gd:53-55`).

### 1.2 Existing video infrastructure (the pattern to reuse)

- `scenes/ui/intro_video.tscn`: `Backdrop` `ColorRect` (line 15) +
  `VideoStreamPlayer` with `stream = assets/videos/intro.ogv`, `autoplay = true`,
  `expand = true` (lines 24-30) + a `SkipHint` label.
- `scripts/ui/intro_video.gd`:
  - `video.finished.connect(_leave_to_main_menu)` (line 31) — the **only** way to
    detect clip end is `finished` with `loop = false`.
  - `video.expand = true` (line 37) is load-bearing: with `expand` off Godot
    blits the clip at native size in the rect's top-left (the "not fullscreen"
    bug the comment at lines 32-36 records).
  - `_fit_video()` (lines 57-71) sizes the player to the **largest contained**
    rect (letterbox). `_process` (42-52) polls `get_video_texture().get_size()`
    for the true aspect until the first decoded frame.
  - `_unhandled_input` (73-77) skips on any key/mouse/joypad press.
- Asset: `assets/videos/intro.ogv`, **9,530,028 B / ~17.71 s ≈ 538 KB/s** — the
  bitrate budget basis for the new clips (§3B). `assets/videos/intro.ogv.uid`
  exists; `assets/videos/source/` is **gitignored** but `.ogv` files are
  **tracked** (`.gitignore:104-105`).
- Tests: `tests/suites/test_intro_video.gd` — 4 tests, **never `add_child`** (so
  no decode / no scene swap), asserts `stream.get_class() == "VideoStreamTheora"`,
  `autoplay`, `get_stream_length()` in `[16,20]`, `expand == true`, a `Backdrop`
  node, `DEST_SCENE_PATH == main_menu`, and `main_scene == intro_video.tscn`.
  Bounds constants live at lines 15-16; managed-node freeing at lines 18-27.

### 1.3 Quality re-apply + scene-change flow

- `GameState.change_scene()` (`autoload/game_state.gd:133-142`) →
  `get_tree().change_scene_to_file` then `call_deferred("_apply_quality_to_current_scene")`.
  It sets `is_paused = false` but **never `get_tree().paused = false`**.
- `_apply_quality_to_current_scene()` (147-155) waits one frame, then
  `SettingsMenuScript.apply_to_scene_tree(quality_preset, scene, root)`.
- `SettingsMenuScript.apply_to_scene_tree(preset, scene, viewport)`
  (`scripts/ui/settings_menu.gd:271-274`) finds the scene's `WorldEnvironment`
  and sun and calls `apply_quality_preset` (280-334) — the single entry point
  for `ssao/glow/fog/ssr/sdfgi/tonemap/viewport.scaling_3d_*/use_taa/msaa`.
- `QUALITY_PRESETS` at `settings_menu.gd:85-182`; **index 2 = High**
  (`scaling_3d_mode = 1` FSR2, `scaling_3d_scale = 0.85`, `probe_enabled = true`).
- `default_quality_preset()` (200-201) → `preset_for_adapter_name(...)`;
  `_legacy_geforce()` (225-234) **matches "GTX 970"**, so the reference rig's
  no-save default is **Low (0)** — a menu background recorded on a default boot
  would look flat. The harness must force High (§3B).
- Main menu is a plain `Control`: `apply_to_scene_tree` on it finds **no**
  `WorldEnvironment` (`find_scene_environment` returns null, 241-248) and no
  light, so the quality ladder is a **no-op for the menu** — the background
  clip's look is baked into the recording, not applied at runtime. Good: the
  menu needs no `WorldEnvironment`.

### 1.4 The open world (the thing we are recording)

- `scenes/world/open_world_root.tscn` (root `WorldDriver`): runtime `Terrain3D`
  `GrassGround` + `TerrainSeeder`, `RoadNetwork`, `MountainPassZone`,
  `%PlayerCar` (`PlayerCarController` + `VehiclePhysics` + 4 wheels),
  `ChaseCamera`, HUD, PauseMenu, `TrafficSpawner`.
- `scripts/world/world_driver.gd` `_ready()` (72-113): 8 bootstrap steps, each an
  `await get_tree().process_frame`, wrapped in `LoadingScreenManager.show_loading/
  update_loading`, ending `LoadingScreenManager.hide_loading()` (line 113).
  `_bootstrap_roads()` (258-280) runs `CorridorPlanner.plan(MASTER_SEED, ...)`,
  registers every `RoadDef`, and pushes centrelines to the seeder.
  The player-region terrain bake is a ~3.3 s **synchronous block** on the first
  `_push_player_position()` (line 98).
- `LoadingScreenManager` (`scripts/ui/loading_screen_manager.gd`) is a
  `CanvasLayer` at **layer 128**, `PROCESS_MODE_ALWAYS`, with
  `show_loading(msg, pct)` / `update_loading(msg, pct)` / `hide_loading()`
  (59-71). It covers everything below layer 128 → a capture must hide it.
- Roads: `scripts/world/road_network.gd` exposes `get_roads()` (`Array[Array]`
  of `Vector3` chains) and `get_road_defs()` (`Array[RoadDef]`);
  `RoadDef` (`scripts/world/road_def.gd`) has `points` + `closed` +
  `display_name()` / id. `CorridorPlanner` emits 19 classified corridors.
- Scripted driving seam: `scripts/world/traffic_driver.gd` (`TrafficDriver`,
  `RefCounted`) drives a car along a chain via `VehiclePhysics.set_input_override(
  Vector2(steer, long))` — exactly the seam `AIController` and the probes use.
  `VehiclePhysics` treats an exact `Vector2.ZERO` override as "player input", so
  scripted drivers always keep a non-zero component (`HOLD_THROTTLE`/`HOLD_BRAKE`).
  **Non-zero override implies AUTO transmission.** `PlayerCarController` never
  clears `input_override`.
- Deterministic clock/weather: `DayNightDriver.set_enabled(bool)`
  (`autoload/day_night_driver.gd:38`); `WeatherManager.set_time_of_day(hour)`
  and `WeatherManager.set_weather(WeatherManager.Weather)`
  (`autoload/weather_manager.gd:41,30`, enum at line 6 → `CLEAR`).
  `TrafficSpawner.set_enabled` / `LivingWorld.set_enabled` exist to switch the
  ambient traffic/living-world off for a clean shot.
- Prior art for scripted capture: `tools/perf_probe.gd:148-149` and
  `tools/hitch_probe.gd:90-92` already call `set_input_override` for automated
  driving.

### 1.5 Godot 4.7 Movie Maker facts (docs + engine source)

- CLI: `--write-movie <file.ogv>` records **offline** (perfect frame pacing);
  `--fixed-fps N` overrides the recording FPS; `--quit-after N` renders exactly
  N frames then quits. All three are documented in the 4.7 Movie Maker tutorial
  and the command-line tutorial.
- **OGV can only be recorded in editor builds** (playback works in exports).
  So recording must run the **editor binary** (`%GODOT_EXE%` /
  `%GODOT_EXE_CONSOLE%`), never an export template.
- **Output resolution follows the window for `disabled` / `canvas_items`
  stretch modes** (this project is `window/stretch/mode="canvas_items"`,
  `project.godot:22`). The project boots `window/size/mode=3`
  (**fullscreen**, line 19) → the window = desktop (1920x1080) → the clip would
  land at 1920x1080. **`--windowed --resolution 1280x720` is mandatory.** (If
  the viewport still differs, `MovieWriter::add_frame` cover-crops to the target
  aspect, `servers/movie_writer/movie_writer.cpp` — 1280x720 has the same 16:9
  aspect as 1920x1080, so this is a no-op crop for us.)
- Exact Project Settings keys (multiline `GLOBAL_DEF`s in
  `servers/movie_writer/movie_writer.cpp`):
  `editor/movie_writer/mix_rate` (int Hz, def 48000),
  `editor/movie_writer/speaker_mode` (enum, def 0 Stereo),
  `editor/movie_writer/video_quality` (0.0-1.0, def **0.75**),
  `editor/movie_writer/audio_bit_depth` (enum, def 16),
  `editor/movie_writer/ogv/audio_quality` (-0.1-1.0, def 0.5),
  `editor/movie_writer/ogv/encoding_speed` (enum 4=Fastest…1=Slowest, def 4),
  `editor/movie_writer/ogv/keyframe_interval` (1-1024, def 64),
  `editor/movie_writer/movie_file` (string), `editor/movie_writer/disable_vsync`
  (bool), `editor/movie_writer/fps` (1-300, def 60).
- **`MovieWriterOGV` always writes a stereo Vorbis track** (the writer takes an
  `audio_mix_buffer`; there is no "no-audio" switch). A truly silent file needs a
  post-pass (`ffmpeg -an`, §3B).
- Quitting: use the window **X** or `get_tree().quit()`. **F8 / Ctrl+C corrupts
  the AVI** (OGV survives but can get mismatched track durations).
- `AnimationPlayer.movie_quit_on_finish` quits the engine at animation end when
  Movie Maker mode is on (non-looping clips only) — an exact alternative to
  `--quit-after` math for a fixed-length pan.
- The `movie` **feature tag** can override project settings / be queried with
  `OS.has_feature("movie")` for record-only quality bumps.
- FFmpeg is already a project dependency through `imageio-ffmpeg`
  (`tools/make_wrx_turbo_flutter.py`, `tools/make_wrx_turbo_loop.py`) — no new
  install needed for trim/`-an`.

### 1.6 Shell / harness facts (this project)

- The AI shell is **cmd.exe** (PC); no POSIX tools. Resolve Godot through
  `godot_path.bat`; headless/normal runs use `%GODOT_EXE_CONSOLE%` to avoid the
  GUI-subsystem detach false-green (`AGENTS.md`). Recording is **windowed and
  real-GPU**, so it is the *one deliberate* "one Godot at a time" operation
  alongside the parallel gate — never run them together.

---

## §2 DESIGN DECISIONS

- **D1 — Video is a `Control` layer, not 3D.** `VideoStreamPlayer` is a
  `Control`. The menu stays a plain `Control` scene; the background is a
  full-rect child behind `MenuLayout`. No `WorldEnvironment` is added to the menu
  (the ladder is a no-op there anyway, §1.3).
- **D2 — COVER, not letterbox.** Godot 4's `VideoStreamPlayer` has **no
  `keepAspectRatio`** and `expand` only stretches to the rect (it does *not*
  preserve aspect). To fill the screen without distorting, wrap the player in a
  `Control` with `clip_contents = true` and size the player to **cover** the
  viewport (scale = `max(sx/cx, sy/cy)`, centred; overflow is clipped). This
  differs on purpose from `intro_video.gd`'s contained/letterbox fit.
- **D3 — Never a black screen.** A `Backdrop` `TextureRect` carrying a
  code-defined `GradientTexture2D` (dark brand blue → near-black) is the *first*
  child and is **always** visible. The video draws over it; before the first
  decoded frame, and when **no clip exists**, the gradient shows. It is a
  resource, so it cannot be "missing".
- **D4 — Readability scrim.** A `ColorRect` (black, `alpha ≈ 0.45`,
  `mouse_filter = IGNORE`) sits between the video and `MenuLayout` so button text
  stays legible over bright road/terrain frames.
- **D5 — Playlist, one player, cycle on `finished`.** `loop = false` and
  self-advance on `finished` (with `loop = true`, `finished` never fires). For a
  single resolved clip, set `loop = true` instead and let the engine loop it.
  One player at a time (swap `stream`) keeps decoded-video VRAM to one clip.
- **D6 — Graceful absence.** Clip paths are candidates filtered by
  `ResourceLoader.exists()`. Zero existing → player hidden, background inert
  (gradient + menu). This is the state **today**, so the feature ships green
  before any clip is recorded, and tests never need a video file.
- **D7 — `PROCESS_MODE_ALWAYS`.** The quit-to-menu path can leave
  `get_tree().paused == true` (`GameState.change_scene` clears `is_paused`, not
  the tree; §1.3). The background `Control` is `PROCESS_MODE_ALWAYS` so the clip
  never freezes behind the menu.
- **D8 — Recording via Godot's own Movie Writer, not a screen recorder.**
  `--write-movie x.ogv` gives perfect frame pacing and deterministic content
  with zero GPU-capture tooling. ffmpeg is used **only** for trim + `-an`.
- **D9 — A dedicated capture scene wrapper, not edits to the real world.**
  `scenes/capture/menu_clip_capture.tscn` instances `open_world_root.tscn` as a
  child; a recorder node drives it. `open_world_root.tscn` / `world_driver.gd`
  are **not** touched.
- **D10 — Deterministic, silent, fixed-length shots.** Force quality High, fix
  the clock/weather, drive via `input_override`, and end each shot with
  `get_tree().quit()`; trim the loading pre-roll in post. Clips are silent by
  construction (no audio bus) *and* by post (`-an`).
- **D11 — Small testable core.** A pure `MenuVideoPlaylist` (`RefCounted`) owns
  candidate resolution + wrap logic so headless tests are file-free; the
  `MenuVideoBackground` node is a thin shell over it.

### Clip roster (3 clips, ~15-20 s each, 1280x720 Theora, silent)

| File | Shot | Camera | Length | Note |
|---|---|---|---|---|
| `assets/videos/menu_drive_hub.ogv` | Chase-cam drive on the hub ring / spawn city | `ChaseCamera` (existing) | ~18 s | densest "world + car" read |
| `assets/videos/menu_drive_pass.ogv` | Chase-cam drive up the mountain pass loop | `ChaseCamera` | ~18 s | vista + elevation |
| `assets/videos/menu_pan_vista.ogv` | Static slow pan over a scenic vantage, car parked in frame | dedicated `Camera3D` + `AnimationPlayer` (`movie_quit_on_finish`) | ~16 s | "beauty shot" variety |

Budget: `intro.ogv` is ~538 KB/s (§1.2), so 18 s at quality 0.75 ≈ 9.7 MB.
Target **≤ 6 MB/clip** by setting `editor/movie_writer/video_quality ≈ 0.6`
and `editor/movie_writer/ogv/encoding_speed = 2`, and/or shortening (§5).

---

## §3 IMPLEMENTATION

### §3A — Menu side (small, safe, ships before any clip exists)

**A1. `scripts/ui/menu_video_playlist.gd`** — new, `class_name MenuVideoPlaylist
extends RefCounted`, pure logic, no nodes:

```
const CANDIDATE_CLIPS: Array[String] = [
    "res://assets/videos/menu_drive_hub.ogv",
    "res://assets/videos/menu_drive_pass.ogv",
    "res://assets/videos/menu_pan_vista.ogv",
]
# injectable existence predicate (tests pass a fake; runtime passes ResourceLoader.exists)
static func resolve(candidates: Array[String], exists: Callable) -> Array[String]
func next_index(current: int) -> int        # wraps; -1 when empty
func is_empty() -> bool
func is_single() -> bool                     # size == 1 -> native loop
```

**A2. `scripts/ui/menu_video_background.gd`** — new, `extends Control`:

- `_ready()`: `process_mode = PROCESS_MODE_ALWAYS`; `mouse_filter = IGNORE`;
  `clip_contents = true`; build `MenuVideoPlaylist.resolve(CANDIDATE_CLIPS,
  ResourceLoader.exists)`. If empty → stay inert (hide the player, `set_process(
  false)`), leaving `Backdrop` visible. Else create/configure the
  `VideoStreamPlayer` (one), `expand = true`, `volume_db = -80.0` (belt-and-
  braces "silent"), connect `finished`, set `loop` per `is_single()`, `play()`.
- `_process`: until the first decoded frame, poll `get_video_texture().get_size()`
  for the true aspect (mirror `intro_video.gd:42-52`); then `set_process(false)`.
- `_cover()`: size/centre the player to **cover** the viewport with the clip
  aspect (§2/D2); reconnect on `get_viewport().size_changed`.
- `_on_finished()`: `next_index`; assign `stream`, `play()`.

**A3. `scenes/ui/main_menu.tscn`** — add three children, in draw order
(before `MenuLayout`): a `Backdrop` `TextureRect` with the gradient
`GradientTexture2D` sub-resource (D3), a `MenuVideoBackground` `Control` with
`clip_contents = true`, `mouse_filter = 2`, `process_mode = 3`
(`PROCESS_MODE_ALWAYS`), and a `Scrim` `ColorRect` (D4). Existing nodes keep
their names/paths: `MenuLayout`, `UiBlip`, and `%ContinueButton` stay unchanged
so `main_menu.gd` and its tests are untouched.

**A4. `scripts/ui/main_menu.gd`** — **no change required.** (Optional polish,
out of scope: nothing.)

**A5. Assets** — none required for §3A to be correct. When the clips exist, drop
them in `assets/videos/` and run `--headless --import .` once so `ResourceLoader.
exists()` resolves (`.ogv.import`). No `main_menu.tscn` edit is needed to pick
them up — that is D6.

### §3B — Capture harness (runs AFTER approval; records the clips)

**B1. `scripts/capture/menu_clip_recorder.gd`** — new, `class_name
MenuClipRecorder extends Node` (child of the capture scene root):

- `@export var shot: String` + `@export var duration_sec: float` +
  `@export var road_name: String` + `@export var mode: String` (`"chase"` /
  `"pan"`) + `@export var hour: float` / `@export var cruise_kmh: float`.
- `_ready()`:
  1. Force the reference look: `SettingsMenuScript.apply_to_scene_tree(2,
     get_tree().current_scene, get_viewport())` and
     `GameState.probe_enabled = SettingsMenuScript.probe_enabled_for(2)`
     (assignment only — **never `set_probe_enabled`**, which writes the save).
     Optionally neutralise FSR2 for crisp 720p: `get_viewport().scaling_3d_mode =
     0; get_viewport().scaling_3d_scale = 1.0`.
  2. Determinism: `DayNightDriver.set_enabled(false)`;
     `WeatherManager.set_time_of_day(hour)`;
     `WeatherManager.set_weather(WeatherManager.Weather.CLEAR)`;
     optionally `TrafficSpawner`/`LivingWorld.set_enabled(false)`.
  3. Hide chrome: `LoadingScreenManager.hide_loading()`; hide HUD + PauseMenu.
  4. Wait for the world: `await` the WorldDriver's 8 bootstrap frames (poll until
     `LoadingScreenManager` is hidden, with a frame cap), then a couple more
     frames to let the first terrain region settle.
  5. **Marker**: `print("CAPTURE_READY frame=", Engine.get_frames_drawn())`.
  6. Arm the shot:
     - `"chase"`: get `%PlayerCar`; pick a `RoadDef` by `road_name` from
       `RoadNetwork.get_road_defs()`; attach `TrafficDriver.configure(car,
       def.points, def.closed, cruise_kmh)`; every physics tick call
       `driver.update(FAR_AWAY, delta)` with **`FAR_AWAY = Vector3(1e9, 0, 1e9)`**
       so `TrafficDriver`'s player-proximity latch (STOP_GAP 5 m) can never fire
       on the car's own position (§5).
     - `"pan"`: park the car (`TrafficDriver.set_parked(true)`), enable a
       dedicated `Camera3D` + `AnimationPlayer` (non-looping) with
       `movie_quit_on_finish = true`.
  7. Start the fixed-length countdown; at `duration_sec`:
     `print("CAPTURE_END frame=", Engine.get_frames_drawn())` then
     `get_tree().quit()`.

**B2. `scenes/capture/menu_clip_capture.tscn`** — new: root `Node3D`
`CaptureRoot` (`menu_clip_recorder.gd`) with an `open_world_root.tscn` instance
child (and, for the `pan` shot, a `Camera3D` + `AnimationPlayer`). The recorder's
exports are set per shot **by the recording script** via
`--` user args or by a tiny per-shot `.tscn` / `@export` override; the simplest
deterministic route is one `.tscn` per shot
(`menu_clip_capture_hub.tscn`, `_pass.tscn`, `_pan.tscn`) each inheriting the
base and setting the exports. (Keep it data, not code.)

**B3. `tools/record_menu_clips.py`** — new, pure stdlib + `imageio_ffmpeg`
(already a dependency):

1. `os.makedirs("reports/menu_clips", exist_ok=True)`.
2. Per shot, launch **one** Godot editor build, windowed, at 720p/30 fps:

   ```
   cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE! --path . --windowed --resolution 1280x720 --fixed-fps 30 --write-movie reports\menu_clips\<shot>_raw.ogv res://scenes/capture/menu_clip_capture_<shot>.tscn > reports\menu_clips\<shot>.log 2>&1"
   ```

   `--windowed` is required (the project boots fullscreen, §1.5); the positional
   scene path runs the capture scene instead of `intro_video.tscn`; the raw is
   relative to the project folder.
3. Parse `CAPTURE_READY frame=<r>` / `CAPTURE_END frame=<e>` from the log
   (`sec = frame / 30`), then trim + strip audio to the final tracked clip:

   ```
   ffmpeg -y -ss <r/30> -i reports\menu_clips\<shot>_raw.ogv -t <(e-r)/30 \
          -an -c:v libtheora -q:v 8 assets\videos\menu_<shot>.ogv
   ```

   (`-q:v` for `libtheora` is 0-10.) The trim removes the loading pre-roll and
   makes each clip exactly `(e-r)/30` s; `-an` makes it truly silent (§1.5).
4. After all clips: `--headless --import .` once so `.ogv.import` files exist.

**B4. Recording project settings.** Add to `project.godot` `[editor]` (editor-only
keys, no gameplay/export effect):

```
editor/movie_writer/video_quality=0.6
editor/movie_writer/ogv/encoding_speed=2
editor/movie_writer/ogv/keyframe_interval=64
editor/movie_writer/fps=30
editor/movie_writer/disable_vsync=true
```

**B5. Raw output** goes under `reports/menu_clips/` (already gitignored) — the
raw `.ogv` never enters git; only the trimmed `assets/videos/menu_*.ogv` are
tracked (matches `.gitignore:104-105`). The recorder's log lives beside the raw.

**B6. Run it:** `py tools\record_menu_clips.py` (PC; the laptop has no `py` — use
its CPython, per `AGENTS.md`). One Godot process at a time: never beside the
GDUnit parallel gate.

---

## §4 TESTS

Mirror `tests/suites/test_intro_video.gd` conventions (no `add_child` of a video;
`_managed` + `after_test` freeing; `assert_that` / `assert_float`).

**New `tests/suites/test_menu_video_background.gd`:**

1. `test_playlist_resolves_only_existing_clips`
   - `resolve(["a.ogv","b.ogv","c.ogv"], func(p): return p == "b.ogv")` → `["b.ogv"]`.
   - `resolve([...], func(_p): return false)` → `[]` (the current tree).
2. `test_playlist_cycles_and_wraps`
   - size 3: `next_index(0) == 1`, `1 → 2`, `2 → 0`.
   - size 1: `is_single() == true`; size 0: `is_empty() == true`,
     `next_index(0) == -1`.
3. `test_main_menu_has_a_background_layer` (structure only, no `add_child`)
   - instantiate `main_menu.tscn`; assert a `MenuVideoBackground` child exists
     with a `VideoStreamPlayer` and a `Backdrop`; assert
     `script.CANDIDATE_CLIPS.size() >= 2`.
4. `test_background_is_inert_without_clips` (the state today)
   - read `MenuVideoBackground`'s script + assert the resolve-empty path leaves
     no stream requirement and the `Backdrop` is the first child (fallback never
     black). Assert `Scrim` exists.
5. `test_background_covers_and_is_always_processing`
   - assert the background's `clip_contents == true`,
     `process_mode == PROCESS_MODE_ALWAYS`, `mouse_filter == MOUSE_FILTER_IGNORE`,
     and that any `VideoStreamPlayer` has `expand == true` and
     `volume_db <= -60.0` (silent-by-construction).
6. `test_menu_still_reaches_intro_boot`
   - guard: `application/run/main_scene` is still `intro_video.tscn` and
     `main_menu.gd` still targets the six existing destinations (no accidental
     coupling to the video layer).

**No change to `test_intro_video.gd`.** Keep `main_menu.gd` untouched so any
existing main-menu suite stays green. Add a follow-up assertion (same file,
guarded by `ResourceLoader.exists`) that a resolved clip's
`stream.get_class() == "VideoStreamTheora"` and `get_stream_length()` is in
`[12, 22]` **once clips ship** — but the suite must pass with the clips absent.

---

## §5 RISKS / GOTCHAS

- **Fullscreen eats the resolution.** `window/size/mode=3` + 1920x1080 viewport
  means a naive `--write-movie` records at 1080p. `--windowed --resolution
  1280x720` is mandatory. (Movie Writer cover-crops on aspect mismatch, but 16:9
  matches, so no crop.)
- **Editor-only OGV.** Recorder must be the editor build (`%GODOT_EXE_CONSOLE%`),
  never an export template.
- **Always-audio.** `MovieWriterOGV` writes stereo Vorbis regardless. `-an` in
  post is the only way to a truly silent file; `volume_db = -80` on the menu
  player is the runtime belt-and-braces.
- **Loading pre-roll + async bake.** The player-region terrain bake is a ~3.3 s
  sync block and the bootstrap is 8 awaited frames → a variable head. Trim using
  the recorder's own `CAPTURE_READY`/`CAPTURE_END` markers, never a guessed
  constant.
- **`TrafficDriver` proximity latch.** It stops when the player is within
  `STOP_GAP` (5 m) *ahead*. Pass `player_pos = Vector3(1e9, 0, 1e9)` so the
  captured car (the "player") never trips it. It also stuck-teleports after 5 s
  < 2 m — a cruise > 0 avoids it.
- **AUTO-only scripted driving.** A non-zero `input_override` implies AUTO;
  `Manual` transmission would ignore it. Clips are recorded in AUTO.
- **Pause freeze.** Entering the menu from the pause menu can leave
  `get_tree().paused == true`; `PROCESS_MODE_ALWAYS` on the background prevents a
  frozen clip (D7).
- **`VideoStreamPlayer` has no aspect control.** COVER requires a
  `clip_contents` wrapper (§2/D2); letterboxing (intro's approach) would show the
  grey clear colour in the bars.
- **First-frame `get_video_texture()` is null/short.** Reuse intro's poll loop
  before sizing, else a short clip loads at the wrong aspect for one frame.
- **`.ogv` size.** Budget ~538 KB/s at q0.75 → 18 s ≈ 9.7 MB. Target ≤ 6 MB via
  `video_quality ≈ 0.6` + `encoding_speed = 2` + optional shorter clip; measure
  `intro.ogv` as the yardstick.
- **Import step.** A dropped `.ogv` needs `--headless --import .` once before
  `ResourceLoader.exists()` is true; forgetting it makes the menu silently stay
  on the fallback (which looks like "the feature didn't work").
- **One Godot at a time.** Recording is real-GPU windowed; never run it
  concurrently with the GDUnit parallel gate.
- **Don't kill with F8/Ctrl+C.** Use the countdown's `get_tree().quit()`.
- **CI:** recording is a manual/asset step, not a test. No suite may require a
  clip file to exist.

---

## §6 DO NOT TOUCH (hard boundaries for the implementation)

- **`scenes/ui/intro_video.tscn`, `scripts/ui/intro_video.gd`,
  `assets/videos/intro.ogv`** — the boot intro is a separate, working feature.
  The menu background is additive; it does not replace or refactor the intro.
- **`application/run/main_scene`** (`project.godot:11`) — stays
  `intro_video.tscn`.
- **`project.godot [display]`** (`window/size/mode=3`, 1920x1080,
  `canvas_items`/`expand`) — do not change the shipping window config to make
  recording easier; the harness overrides it on the CLI.
- **`scripts/ui/settings_menu.gd` `QUALITY_PRESETS` values** — do not loosen the
  ladder; the harness forces High at runtime.
- **`scripts/ui/main_menu.gd` and the existing `main_menu.tscn` node names** —
  `MenuLayout`, `UiBlip`, `%ContinueButton`, and the six button `pressed`
  connections stay; add children, do not rename/move.
- **`scenes/world/open_world_root.tscn` and `scripts/world/world_driver.gd`** —
  no capture nodes/scripts inside the real world; use the wrapper capture scene.
- **`scripts/world/terrain_seeder.gd` / `terrain_baker.gd` / Terrain3D regions**
  — no bake changes for recording.
- **`autoload/game_state.gd` `change_scene` flow** — do not "fix" the
  `get_tree().paused` non-reset here; handle it locally via `PROCESS_MODE_ALWAYS`.
- **`.gitignore:104-105`** — keep `.ogv` tracked and `assets/videos/source/`
  ignored; raw captures go to `reports/` (already ignored).
- **Any GDUnit run** must not depend on a recorded clip existing.

---

## §7 EXECUTION ORDER (after approval)

1. Land §3A + §4 (menu layer + tests). Suite green **with no clips present**.
2. Land §3B harness + `project.godot [editor]` movie settings.
3. Run `py tools\record_menu_clips.py` (windowed, one Godot, alone) → 3 trimmed
   `.ogv` in `assets/videos/`.
4. `--headless --import .`, eyeball the menu over each clip, then run the gate
   suite once (menu background is a plain `Control`; no perf-gate interaction).
5. Commit the three `.ogv` (tracked) — **not** the raws/logs in `reports/`.
