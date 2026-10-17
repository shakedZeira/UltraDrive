# HANDOFF — 2026-10-18: HUD dead-readouts investigation

## Status
The user reported: "0 km/h, 0 rpm, and no hp,nm are showing, also can't see my location (x,y,z)" — all four HUD readouts dead simultaneously.

## Proven facts
- Import probe (`--headless --import .`): clean; no `SCRIPT ERROR`/`Parse Error` (benign RID leak).
- Real scenes run headless clean: `mountain_pass.tscn` with `--quit-after 400` exits 0, no script errors.
- HUD core suites pass: `test_hud_gauge.gd + test_traction_hud.gd + test_cockpit_hud.gd + test_hud_contrast.gd` → 38/38, 0 failures.
- `race_ui.gd::_process()` (lines ~150-192): all dead readouts share a single early-return path: `if car == null:` at line ~150. After that it returns without updating cluster/hp/nm/coords/lap/position. The `_race_over` early-return at line ~183 is AFTER gauges update — cannot kill gauges.
- Defaults in `hud.tscn`: `%PowerValue` = `"-- hp"`, `%TorqueValue` = `"-- Nm"`, `%CoordsLabel`/`%LapLabel`/`%PositionLabel` = `""` (empty). Exactly matches the report when `car == null`.
- Root registration: `VehicleManager.player_car` is set only by `register_player_car(car)`; `player_car_controller.gd::_ready()` (line 23) does `VehicleManager.register_player_car(car)` after `@onready var car: VehiclePhysics = get_parent()` (line 8). `_exit_tree()` unregisters on exit.
- Batch changes (benign for this): `exit_button.pressed.connect(_on_exit)` added in `race_ui.gd::_ready()`; cinematic code added but only runs at race finish; `TorqueValue` node added to `hud.tscn`; `power_gauge.gd` and `vehicle_physics.gd` got reverse-grade/turbo-related additions — import and targeted HUD suites still pass.

## Strong hypothesis (root cause)
`VehicleManager.get_player_car()` returns `null` in the live session. Most plausible triggers:
1. Player car controller re-registered after scene-swap in a way that left `player_car` `null` (or was cleared by `remove_car()` and never re-set). 
2. `@onready var car: VehiclePhysics = get_parent()` returns non-VehiclePhysics in some edge case → `car` becomes `null` (GDScript allows assigning null to typed var) and `register_player_car(null)` would set `player_car = null` (silent). Check parent type.
3. The cinematic/teardown path left registration in an unexpected state (less likely; HUD dead on entry/normal play).
4. A race finish → EXIT via new button returned to track select/open world, but the player car instance in the destination scene wasn't registered (scene-load order). 

## Next steps (for a subagent)
1. **Reproduce**: run windowed (not headless) a real track/open world scene and watch console + HUD. Capture stdout/stderr. (Gemini Vision not signed in; don't block on vision.)
2. **Prove/disprove**: add a temporary probe that logs `VehicleManager.get_player_car() != null`, `player` identity, and whether `race_ui.car` resolution sees null — but need to be careful not to break `-s` SceneTree runs (autoload globals don't compile cleanly in a pure `SceneTree` `-s` script). Better: write a throwaway scene under `scenes/test/` that instances real HUD+PlayerCar, runs frames, prints.
3. **Fix minimally**: if registration lost on scene-swap/re-entry, ensure re-registration happens (e.g. `register_player_car` is idempotent and also called on re-enter, or `VehicleManager` falls back to scanning tree on demand). If `register_player_car(null)` can occur, guard: `if car != null: register_player_car(car)`. Do NOT delete EXIT/cinematic.
4. **Regression test**: add a suite that instantiates real `hud.tscn` + real `player_car.tscn` together and asserts gauges populate (not stuck at defaults). 
5. **Verify**: targeted GDUnit run on touched suites + HUD + `test_race_results.gd` + `test_post_race_cinematic.gd`. One `-a` per suite, never comma-joined. Read `Overall Summary:`.
6. **Clean up** any throwaway files created. Don't `git add -A`.

## Shell notes
- cmd.exe shell; pass `workdir=D:\AI Projects\UltraDrive`. Use relative paths.
- Resolve Godot via `godot_path.bat`, use `%GODOT_EXE_CONSOLE%` for headless/redirection; write a small `.bat` wrapper (cmd can't expand `!GODOT_EXE_CONSOLE!` after `call` in some one-liners).
- Never write to C:; set `APPDATA` to an absolute path under project root.
- One Godot process at a time.
- `*.uid` gitignored.
- GDUnit rules as in `docs/GDUNIT_GATE.md`/`AGENTS.md`.

## Key files to inspect
- `autoload/vehicle_manager.gd` (register/remove/get)
- `scripts/player/player_car_controller.gd` (_ready/_exit_tree)
- `scripts/race/race_ui.gd` (_process early-return at ~150)
- `scenes/ui/hud.tscn` (TorqueValue + ExitButton)
- `scenes/vehicle/player_car.tscn` (parent structure)
- `scripts/vehicle/vehicle_physics.gd` (get_drive_info returns expected keys)
- `project.godot` — do NOT touch `[editor]` section.

Evidence before assertions. Fix at the right layer (registration/scene lifecycle), not by weakening HUD guards.