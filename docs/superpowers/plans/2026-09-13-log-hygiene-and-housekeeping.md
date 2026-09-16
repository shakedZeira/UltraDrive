# Log Hygiene + Housekeeping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every headless test run and drive log clean and truthful: kill the three debug `print()`s, fix the misleading car_audio asset probe, remove dead duplicated Input reads, correct the stale AIController comment, then snapshot the entire uncommitted D4/D5 backlog into owner-approved logical commits and tidy stray logs/reports. No gameplay behavior changes, **no new tests** — the GDUnit baseline must stay **exactly** `69 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`.

**Architecture:** Three one-line-to-remove debug prints in `main.gd` / `mountain_pass.gd` / `test_circuit.gd`; a 4-entry `ASSET_CANDIDATES` probe in `car_audio.gd` that always misses (neither `assets/audio/` nor `resources/audio/` exists); duplicated `Input.*` reads in `InputManager` (autoload at `res://autoload/input_manager.gd` — NOT `scripts/input/`, which does not exist); a stale "Phase 6" placeholder comment in `ai_controller.gd`. Housekeeping = gitignore `/_*.txt`, delete stray root logs + `reports/`, pin the AGENTS.md baseline + benign suite-noise whitelist, and an intended-staging-only snapshot commit wave (explicit `git add <paths>` forever, never `-A`, never `*.uid`).

**Tech Stack:** Godot 4.7.2 GDScript, GDUnit4, git (repo style: `feat(Dx):`, `fix:`, `docs(agents):` conventional prefixes).

**Spec:** inventory A8, A10, A11, A12, E1-E3, E5-E6 (see preamble).

## Global Constraints

Verbatim rules that gate EVERY step — the executor must respect these without exception:

- **TAB indentation must be preserved verbatim per file.** Files `scripts/track/mountain_pass.gd` and `scripts/vehicle/car_audio.gd` use TABS. Files `scripts/main.gd`, `scripts/test_circuit.gd`, `autoload/input_manager.gd`, `scripts/ai/ai_controller.gd` use 4-SPACE indentation. Match each file's existing style exactly in before/after blocks below.
- **NEVER `git add -A`.** Every staging step uses only explicit paths.
- **Never stage `*.uid` files.** `.gitignore` line 4 already ignores them; never fight that.
- **Do NOT commit `AGENTS.md` unless explicitly decided.** It IS decided here: AGENTS.md is already tracked and modified, E6 guarantees a change, and the repo has a `docs(agents):` commit convention — so AGENTS.md goes in the LAST commit (Task 8, commit 4) and nowhere earlier.
- **`git status --short` must show NO `*.uid` before ANY staging.** Verified today: it already shows none. If a `.uid` ever appears in `git status`, stop and clean it up before staging anything.
- **Verification recipe** (AGENTS.md known-good order):
  1. `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import . 2>&1 | findstr /i "SCRIPT ERROR Parse Error Failed to load"` → expect ZERO matches (benign `resources still in use at exit` and Terrain3D lines allowed).
  2. `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1` (**`--ignoreHeadlessMode` AFTER the tool-script path**), then `findstr /c:"Overall Summary:" _gdunit.txt`.
  3. EXPECT: `Overall Summary: 69 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`. **This plan adds no tests, so this baseline MUST stay identical.**
- **GDUnit4 treats GDScript warnings as errors.** The A11 refactor deletes variables and branches only (no new warnings). `push_debug` is not a warning.
- A8 caveat: `scripts/track/checkpoint.gd` connects `body_entered` on its own at `checkpoint.gd:14` — removing the extra debug handlers in `mountain_pass.gd` / `test_circuit.gd` does NOT affect checkpoint gating (race logic uses `Checkpoint.is_passed()`, via `lap_counter.gd`). Verified: `_on_checkpoint_body_entered` is referenced ONLY inside the two files being edited.
- Commits are **OPTIONAL / owner-approval gated** (Task 8). Every commit step carries an explicit `[OWNER APPROVAL GATE]` marker. Code changes still happen (Tasks 1–4); their commits are deferred and grouped in Task 8.

## SUITE NOISE (BENIGN, A13/A14 — documentation reference only)

Verified in today's `_gdunit.txt`. These non-fatal lines WILL appear in the GDUnit log; nothing in this plan touches them (they are engine/addon internals). They are documented in AGENTS.md (Task 7) so future agents don't chase them:

- `WARNING: instance_reset_physics_interpolation() is deprecated.` (engine-internal rendering-server compat)
- `ERROR: Terrain3D#...:_grab_camera:155: Cannot find the active camera. Set it manually with Terrain3D.set_camera(). Stopping _physics_process()` (headless: no camera)
- `ERROR: Condition "!is_inside_tree()" is true. Returning: Transform3D()` (Jolt/Node teardown between tests)
- `WARNING: Detected N possible orphan nodes.` (GdUnit reports, counted in the `16 orphans` baseline)
- `WARNING: N ObjectDB instances were leaked at exit` + `ERROR: N resources still in use at exit` (engine shutdown trailer)

---

## Task 1 — A8: kill the three debug `print()` noise sources

**Files:**
- `scripts/main.gd` (line 4; 4-space indent) — bootstrap lifecycle marker → downgrade to `push_debug`.
- `scripts/track/mountain_pass.gd` (line 78 connect, lines 223–225 handler; TAB indent) — remove print scaffolding entirely.
- `scripts/test_circuit.gd` (line 62 connect, lines 65–67 handler; 4-space indent) — remove print scaffolding entirely.

**Interfaces:**
- Consumes: `SceneTransition.flash_to_scene("res://scenes/ui/main_menu.tscn")` (unchanged call in `main.gd`).
- Produces: nothing new. The checkpoint-passed event is now observed only by `Checkpoint`'s own internal `body_entered` (used by nothing else in-tree).

**Steps:**

- [ ] `scripts/main.gd` — before:
```gdscript
func _ready() -> void:
    print("[UltraDrive] Main scene loaded – transitioning to main menu")
    SceneTransition.flash_to_scene("res://scenes/ui/main_menu.tscn")
```
after:
```gdscript
func _ready() -> void:
    push_debug("[UltraDrive] Main scene loaded – transitioning to main menu")
    SceneTransition.flash_to_scene("res://scenes/ui/main_menu.tscn")
```
(`push_debug` keeps a genuinely useful boot-order diagnostic but only in debug builds; it never pollutes a release or headless log the way `print` does.)

- [ ] `scripts/track/mountain_pass.gd` — remove the extra checkpoint handler. Before:
```gdscript
		var area_col := CollisionShape3D.new()
		area_col.shape = area_shape
		cp.add_child(area_col)
		cp.body_entered.connect(_on_checkpoint_body_entered.bind(cp.index))
		add_child(cp)
```
after:
```gdscript
		var area_col := CollisionShape3D.new()
		area_col.shape = area_shape
		cp.add_child(area_col)
		add_child(cp)
```
and delete the whole handler (lines 223–225):
```gdscript
func _on_checkpoint_body_entered(body: Node3D, index: int) -> void:
	if body is VehiclePhysics:
		print("[Track] Mountain Pass checkpoint %d passed by %s" % [index, body.name])
```

- [ ] `scripts/test_circuit.gd` — same removal. Before:
```gdscript
        cp.add_child(area_col)

        cp.body_entered.connect(_on_checkpoint_body_entered.bind(cp.index))
        add_child(cp)
```
after:
```gdscript
        cp.add_child(area_col)

        add_child(cp)
```
and delete the whole handler (lines 65–67):
```gdscript
func _on_checkpoint_body_entered(body: Node3D, index: int) -> void:
    if body is VehiclePhysics:
        print("[Track] Checkpoint %d passed by %s" % [index, body.name])
```

- [ ] **Verify:** run import probe (Global Constraints step 1) → zero script errors. Run the GDUnit suite (step 2), then confirm all three:
  - `findstr /c:"Overall Summary:" _gdunit.txt` → `69 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans` (unchanged).
  - `findstr /c:"[Track] Mountain Pass checkpoint" _gdunit.txt` → **no output** (was 3× per run: once in `test_mountain_pass_zone`, twice in `test_track_system`).
  - `findstr /c:"[Track] Checkpoint" _gdunit.txt` → **no output**.

- [ ] Commit: **deferred** to Task 8 snapshot (hygiene wave).

## Task 2 — A10: fix the misleading `car_audio` asset probe

`ASSET_CANDIDATES` probes 4 paths, but verified via glob that **neither `assets/audio/` nor `resources/audio/` exists** (only `assets/cars/` and `resources/cars/` + `resources/materials/`). The `res://resources/audio/` entries are a stale guess. Quiet behavior is correct (synthesis), the probe is misleading.

**Files:** `scripts/vehicle/car_audio.gd` (TAB indent).

**Interfaces:**
- Consumes: `ResourceLoader.exists(path)`, `load(path) as AudioStream` (both unchanged in the single-probe path).
- Produces: `_load_loop_or_generate() -> AudioStream` — behavior-identical (still loads a dropped-in file if present, still synthesizes otherwise). No callers change; `CarAudio` is attached as a child of `VehiclePhysics` in scenes.

**Steps:**

- [ ] Replace the probe list. Before:
```gdscript
const ASSET_CANDIDATES: Array[String] = [
	"res://assets/audio/engine_loop.wav",
	"res://assets/audio/engine_loop.ogg",
	"res://resources/audio/engine_loop.wav",
	"res://resources/audio/engine_loop.ogg",
]
```
after:
```gdscript
## OPTIONAL shipped engine loop. Drop a real recording here to bypass the
## synthesized loop; the default (no file) is the intended path — engine audio
## is procedural-only. No assets/audio/ or resources/audio/ dirs exist; the old
## stale resources/audio probe was removed in the log-hygiene pass.
const ENGINE_LOOP_OVERRIDE_PATH := "res://assets/audio/engine_loop.ogg"
```

- [ ] Simplify `_load_loop_or_generate()`. Before:
```gdscript
func _load_loop_or_generate() -> AudioStream:
	for path in ASSET_CANDIDATES:
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return _generate_engine_loop()
```
after:
```gdscript
func _load_loop_or_generate() -> AudioStream:
	if ResourceLoader.exists(ENGINE_LOOP_OVERRIDE_PATH):
		return load(ENGINE_LOOP_OVERRIDE_PATH) as AudioStream
	return _generate_engine_loop()
```

- [ ] **Verify:** import probe → zero script errors. No suite changes needed (no test touches CarAudio's probe; full-suite re-run happens at the Task 5 gate).

- [ ] Commit: **deferred** to Task 8 snapshot (hygiene wave).

## Task 3 — A11: remove dead duplicate input reads in `InputManager`

`get_throttle()/get_brake()` read the SAME action twice into `joy_*`/`key_*` and `maxf()` them (identical → no-op). `get_steer()` calls `Input.get_axis(...)` twice and the `absf(joy_steer) > 0.1` branch short-circuits to an identical value. Only `is_any_input_active()` calls these three — dead code.

**Files:** `autoload/input_manager.gd` (4-space indent; path corrected from inventory `scripts/input/` → `autoload/`, per `project.godot` [autoload] `InputManager="*res://autoload/input_manager.gd"`).

**Interfaces:**
- Consumes: `Input.get_action_strength("throttle"|"brake")`, `Input.get_axis("steer_left", "steer_right")` — action-name string constants kept EXACTLY (they must keep matching the `project.godot` [input] map).
- Produces: `get_throttle() -> float`, `get_brake() -> float`, `get_steer() -> float` — identical return values (verified by `tests/test_input_mapping.gd`, which asserts 0.0/0.0/0.0 under no input).
- Consumers: `scripts/vehicle/vehicle_physics.gd:60-62` (`get_throttle/get_brake/get_steer`), `vehicle_physics.gd:63,66,83,85` (`is_handbrake/is_reset/is_shift_*_just_pressed`), `is_any_input_active()` at `input_manager.gd:50-52` (untouched). D5 control-mapping suite (`tests/test_input_mapping.gd`) and `tests/suites/test_transmission_modes.gd` must stay green.

**Steps:**

- [ ] `get_throttle()` — before:
```gdscript
func get_throttle() -> float:
    ## Returns throttle input [0.0 to 1.0].
    ## Controller: right trigger (axis 7). Keyboard: W key.
    var joy_throttle := Input.get_action_strength("throttle")
    var key_throttle := Input.get_action_strength("throttle")
    return maxf(joy_throttle, key_throttle)
```
after:
```gdscript
func get_throttle() -> float:
    ## Returns throttle input [0.0 to 1.0].
    ## Controller: right trigger (axis 7). Keyboard: W key.
    return Input.get_action_strength("throttle")
```

- [ ] `get_brake()` — before:
```gdscript
func get_brake() -> float:
    ## Returns brake input [0.0 to 1.0].
    ## Controller: left trigger (axis 6). Keyboard: S key.
    var joy_brake := Input.get_action_strength("brake")
    var key_brake := Input.get_action_strength("brake")
    return maxf(joy_brake, key_brake)
```
after:
```gdscript
func get_brake() -> float:
    ## Returns brake input [0.0 to 1.0].
    ## Controller: left trigger (axis 6). Keyboard: S key.
    return Input.get_action_strength("brake")
```

- [ ] `get_steer()` — before:
```gdscript
func get_steer() -> float:
    ## Returns steering input [-1.0 left, 0.0 center, 1.0 right].
    ## Controller: left stick X axis. Keyboard: A/D keys.
    var joy_steer := Input.get_axis("steer_left", "steer_right")
    var key_steer := Input.get_axis("steer_left", "steer_right")
    # Prioritize joystick if it has significant input
    if absf(joy_steer) > 0.1:
        return joy_steer
    return key_steer
```
after:
```gdscript
func get_steer() -> float:
    ## Returns steering input [-1.0 left, 0.0 center, 1.0 right].
    ## Controller: left stick X axis. Keyboard: A/D keys.
    return Input.get_axis("steer_left", "steer_right")
```

- [ ] Leave `is_any_input_active()` (lines 50–52), `is_handbrake()`, `is_reset()`, `is_pause_just_pressed()`, `is_camera_mode_just_pressed()`, `is_shift_up_just_pressed()`, `is_shift_down_just_pressed()`, `get_raw_joy_info()` byte-for-byte unchanged.

- [ ] **Verify:** import probe → zero script errors. GDUnit suite → `Overall Summary: 69 ... 16 orphans` unchanged (this is the D5 control-mapping wave — `tests/test_input_mapping.gd` + `tests/suites/test_transmission_modes.gd` must PASS).

- [ ] Commit: **deferred** to Task 8 snapshot (hygiene wave).

## Task 4 — A12: fix the stale `ai_controller` comment

`_simulate_input` still claims "Phase 6 will refactor VehiclePhysics to accept external input." The refactor LANDED (`set_input_override` exists at `vehicle_physics.gd:49` and is consumed at `vehicle_physics.gd:60-62`). Update the comment to state reality.

**Files:** `scripts/ai/ai_controller.gd` (4-space indent; line 52).

**Interfaces:**
- Consumes: `car.set_input_override(Vector2(steer, throttle - braking))` at `vehicle_physics.gd:49` — call unchanged, comment-only edit.
- Produces: nothing. No test touches `AIController` comments.

**Steps:**

- [ ] Before:
```gdscript
func _simulate_input(steer: float, throttle: float, braking: float) -> void:
    ## Drives the car by re-routing input through the physics controller.
    ## This bypasses InputManager (which is player-only).
    ## (Placeholder — Phase 6 will refactor VehiclePhysics to accept external input.)
    car.set_input_override(Vector2(steer, throttle - braking))
```
after:
```gdscript
func _simulate_input(steer: float, throttle: float, braking: float) -> void:
    ## Drives the car through VehiclePhysics.set_input_override().
    ## When input_override != ZERO, VehiclePhysics applies it INSTEAD of polling
    ## InputManager, which stays player-only.
    car.set_input_override(Vector2(steer, throttle - braking))
```

- [ ] **Verify:** import probe → zero script errors; file parses (no syntax change beyond a comment).

- [ ] Commit: **deferred** to Task 8 snapshot (hygiene wave).

## Task 5 — VERIFICATION GATE for Tasks 1–4 (full suite)

All four code changes are in the tree. This gate is the single authoritative confirmation that behavior is untouched.

- [ ] Step 1 (import probe): `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import . 2>&1 | findstr /i "SCRIPT ERROR Parse Error Failed to load"` → ZERO lines.
- [ ] Step 2 (suite): `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1`
- [ ] Step 3: `findstr /c:"Overall Summary:" _gdunit.txt` → **`Overall Summary: 69 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`** (identical to baseline).
- [ ] Step 4: `findstr /c:"[Track] Mountain Pass checkpoint" _gdunit.txt` → no output, and `findstr /c:"[Track] Checkpoint" _gdunit.txt` → no output.
- [ ] Step 5 (E5 gate): `git status --short | findstr /i "uid"` → **no output**.

## Task 6 — E2 + E3: stray root logs, `reports/` tidy, `.gitignore`

**Files:** `.gitignore` (modify); filesystem deletes (no `git` involvement).

**Interfaces:** none — pure repo hygiene. `reports/` is ALREADY ignored (`.gitignore` line 6); the four root logs are NOT ignored today (`_gdunit.txt` fails the existing `_gdunit_*.txt` pattern on line 11).

**Steps:**

- [ ] `.gitignore` — insert the root log pattern. Before (lines 13–14):
```
*gdunit_run*.cmd
# Godot engine temp files left behind by addon import/reload
```
after:
```
*gdunit_run*.cmd
_gdunit.txt
_mpz.txt
_ow.txt
_tb.txt
# Stray root-level diag/probe logs written by the headless AGENTS workflow
/_*.txt
# Godot engine temp files left behind by addon import/reload
```
  NOTE: `_gdunit.txt` / `_mpz.txt` / `_ow.txt` / `_tb.txt` are enumerated for clarity AND covered by the root-anchored `/_*.txt` wildcard (future-proof). Existing line 11 `_gdunit_*.txt` becomes redundant — leave it (harmless). The `git add` for `.gitignore` uses the explicit path in Task 8 commit 3.
- [ ] Delete the four stale root logs:
  `del /q _gdunit.txt _mpz.txt _ow.txt _tb.txt`
- [ ] E3 — delete accumulated GDUnit reports (ALL files under `reports/` are untracked+ignored; verified `git ls-files reports` returns nothing): `if exist reports rmdir /s /q reports` (GdUnit recreates a fresh `report_N` on the next suite run — still ignored). Optionally keep it if the owner wants the history; the report is re-generated by every suite run.
- [ ] **Verify:** `git status --short` no longer lists `_gdunit.txt`, `_mpz.txt`, `_ow.txt`, `_tb.txt` (they exist but are ignored) and `reports/` stays absent. Re-run only the import probe (step 1) after the `.gitignore` edit.

## Task 7 — E6: AGENTS.md baseline sync + suite-noise whitelist + hygiene notes

**Files:** `AGENTS.md` (already tracked + modified; E6 REQUIRES this change, which is what authorizes its Task 8 commit).

**Interfaces:** documentation only. The expected baseline line must keep reading exactly `Overall Summary: 69 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans` — verified today it already matches, so E6 is a *confirmation* plus additions.

**Steps:**

- [ ] Confirm the step-3 EXPECT line in `AGENTS.md` (line 31) still says `69 test cases | ... | 16 orphans` — it does as of today; do not change the numbers.
- [ ] Under `## HEADLESS WORKFLOW` (after the "GDUnit gotchas" line 32), add a `### Suite noise (benign — don't chase)` block:
```
### Suite noise (benign — don't chase)
The GDUnit log routinely prints these NON-fatal engine/addon lines; leave them:
- `WARNING: instance_reset_physics_interpolation() is deprecated.`
- `ERROR: Terrain3D#...:_grab_camera:155: Cannot find the active camera...
  Stopping _physics_process()` (headless: no active camera)
- `ERROR: Condition "!is_inside_tree()" is true. Returning: Transform3D()`
- `WARNING: Detected N possible orphan nodes.` (counted in the `16 orphans`)
- `WARNING: N ObjectDB instances were leaked at exit` /
  `ERROR: N resources still in use at exit` (engine shutdown trailer)
```
- [ ] Under step 1 of the recipe, append: "Stray root probe logs (`_gdunit.txt`, `_mpz.txt`, `_ow.txt`, `_tb.txt`) are gitignored via `/_*.txt`; delete them locally whenever they pile up."
- [ ] Under note for step 2, append: "Runtime start is `print`-free by policy; dev-only lifecycle markers in `scripts/main.gd` use `push_debug` (never `print`)."
- [ ] **Verify:** import probe → zero script errors (`.md` only, but confirm nothing broke). Commit: **deferred** to Task 8, commit 4 (LAST).

## Task 8 — E1: snapshot commit wave (OWNER-APPROVAL GATED, OPTIONAL)

Verified inventory (differs slightly from the 18/20 announced in the preamble — use THESE numbers): **19 modified + 19 untracked** entries. Every path below is verified to exist in `git status` today. Commits are explicit-path-only; commit style matches `git log` (`feat(D4):` / `feat(D5):` / `refactor(...):` / `docs(agents):`).

**Global pre-stage guard for EVERY commit below:**
- [ ] `git status --short | findstr /i "uid"` → **no output** (E5). If a `.uid` shows up, stop and fix it.
- [ ] **NEVER** `git add -A`. Only the explicit paths below.
- [x] `AGENTS.md` decision locked: committed ONLY in commit 4 (last); `start_game.bat`/`play_game.bat`/`diag/freeze_diag.gd` are dev tooling → commit 4 (owner may drop the two `.bat`s if machine-specific paths are deemed undesirable; `diag/` then instead goes to `.gitignore`).
- [x] The four `_*.txt` root logs and `reports/` are NOT committed (Task 6 ignores them).

**Commit 1 — D4 terrain/streaming wave** (`feat(D4): Terrain3D open-world seeding + streaming (player-region sync bake, worker ring, road-conformed terrain), prop/traffic scatter, mountain-pass zone; drop checkpoint debug prints`)
```
git add scripts/world/terrain_baker.gd scripts/world/terrain_seeder.gd scripts/world/prop_scatterer.gd scripts/world/traffic_spawner.gd scripts/world/road_network.gd scripts/world/chunk_streamer.gd scripts/world/world_driver.gd scripts/track/mountain_pass.gd scripts/track/track_builder.gd scenes/world/open_world_root.tscn scenes/world/regions/mountain_pass_zone.tscn tests/suites/test_terrain_seeder_streaming.gd tests/test_terrain_baker.gd tests/test_mountain_pass_zone.gd tests/test_prop_scatterer.gd tests/test_traffic_spawner.gd
git commit -m "feat(D4): Terrain3D open-world seeding + streaming (player-region sync bake, worker ring, road-conformed terrain), prop/traffic scatter, mountain-pass zone instance; remove checkpoint debug prints"
```

**Commit 2 — D5 map/transmission/control-map wave** (`feat(D5): world map + minimap roads + POI, manual/auto transmission modes, control-map rewire`)
```
git add autoload/game_state.gd scripts/vehicle/car_config.gd scripts/vehicle/drivetrain.gd scripts/vehicle/vehicle_physics.gd scripts/ui/minimap.gd scripts/ui/map_roads.gd scripts/ui/world_map.gd scripts/ui/pause_menu.gd scenes/ui/pause_menu.tscn scripts/ui/settings_menu.gd scenes/ui/settings_menu.tscn scripts/world/poi_registry.gd project.godot tests/suites/test_world_map_features.gd tests/suites/test_transmission_modes.gd
git commit -m "feat(D5): world map + minimap roads + POI registry, manual/auto transmission modes, control-map rewiring (handbrake off Triangle)"
```
NOTE: `project.godot` carries this wave's input-map + autoload edits (also D3/D4-era `SceneTransition`/physics-tick lines travelled together in the working tree; committing them here is the least misleading single home).

**Commit 3 — log-hygiene wave (this plan's code, incl. the A8 edits already baked into `mountain_pass.gd` committed in C1)** (`refactor(log-hygiene): print-free debug, single audio drop-in probe, purge duplicate Input reads, AIController override comment`)
```
git add .gitignore scripts/main.gd scripts/test_circuit.gd scripts/vehicle/car_audio.gd scripts/ai/ai_controller.gd autoload/input_manager.gd
git commit -m "refactor(log-hygiene): replace debug prints with push_debug/remove, single canonical audio drop-in probe, purge duplicate Input reads in InputManager, update AIController override comment; ignore root /_*.txt diag logs"
```

**Commit 4 — docs + tooling (LAST; ONLY because AGENTS.md was changed by Task 7)** (`docs(agents): pin GDUnit baseline 69/69 | 16 orphans + benign suite-noise whitelist; dev launchers + freeze diag tool`)
```
git add AGENTS.md start_game.bat play_game.bat diag/freeze_diag.gd
git commit -m "docs(agents): pin GDUnit baseline 69/69 | 16 orphans + benign suite-noise whitelist (A13/A14), note /_*.txt ignore and print-free policy; add dev launcher bats + freeze diag tool"
```
If the owner declines the two `.bat` launchers: drop them from the `git add` and instead append `diag/` to `.gitignore` (with `start_game.bat`/`play_game.bat` left untracked).

**After the wave (only if the owner approved all commits).**
- [ ] `git status --short` → clean except ignored regenerated `_gdunit.txt` and the (gitignored) plan under `docs/`.
- [ ] Final suite verification: import probe then GDUnit suite → `Overall Summary: 69 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`.
- [ ] Push only if the owner asks: `git push` is NOT part of this plan.

---

## Self-Review

Item → task mapping (every inventory item covered here):

| Item | Task(s) | How |
|---|---|---|
| A8 | Task 1 (verify Task 5, committed C1/C3) | `main.gd` → `push_debug`; `mountain_pass.gd` + `test_circuit.gd` print handlers removed (3× `[Track] ... checkpoint` lines verified gone) |
| A10 | Task 2 (committed C3) | 4-entry stale probe → single documented `ENGINE_LOOP_OVERRIDE_PATH=res://assets/audio/engine_loop.ogg`; synthetic-only intent documented |
| A11 | Task 3 (committed C3) | `joy_*`/`key_*` duplicate reads removed; action-name strings kept; `is_any_input_active()` untouched; `test_input_mapping.gd` + `test_transmission_modes.gd` stay green |
| A12 | Task 4 (committed C3) | "Phase 6 placeholder" comment → accurate `set_input_override()` description |
| E1 | Task 8 (owner-gated) | 4 logical commits, 35 explicit-path `git add` lists, `git log`-style messages; never `-A`; never `*.uid`; AGENTS.md last |
| E2 | Task 6 (committed C3) | Delete `_gdunit.txt`/`_mpz.txt`/`_ow.txt`/`_tb.txt` + gitignore `/_*.txt` (exact new lines shown) |
| E3 | Task 6 (no commit needed — `reports/` already ignored line 6) | `rmdir /s /q reports` tidy; verified untracked |
| E5 | Global Constraints + Task 5 step 5 + Task 8 guard | `git status --short | findstr /i "uid"` → empty enforced pre-every-staging |
| E6 | Task 7 (committed C4) | Baseline line confirmed at `69 ... 16 orphans` (unchanged); benign suite-noise whitelist (A13/A14) added as docs lines |
| A13/A14 | Task 7 only | Documented in the "Suite noise (benign)" block; NOT fixed (out of scope) |

Placeholder scan: every before/after block above contains real code or real file content — no `...`, `TODO`, `XXX`, or `lorem` anywhere in this plan; the only ellipses are in the quoted suite-noise log lines and the MD attribute block at the top, which are verbatim content. No new tests, so the 69/16 baseline cannot shift. The monitored output changes are exactly three: `main.gd` no longer `print`s (debug-only marker), and zero `[Track] ... checkpoint` lines in any future `_gdunit.txt`.