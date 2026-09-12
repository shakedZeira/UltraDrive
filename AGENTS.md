# AGENTS.md — UltraDrive (Godot 4.7.2)

Project knowledge for autonomous agents. Godot project root = this directory
(`D:\AI Projects\UltraDrive`, res://). Godot binary:
`D:\Godot\Godot_v4.7.2-stable_win64.exe` (win64 arrows). GDUnit4 addon at
`addons/gdUnit4`, tests under `tests/` (suite: `tests/suites`).

## HEADLESS WORKFLOW (KNOWN-GOOD — reuse, don't rediscover)

GDUnit4 CLI correctly drags in the headless-mode guard, but ONLY when run
AFTER a normal `--headless` import+probe pass. The engine will refuse
`--headless` first-run launches with exit 103 ("Headless mode is not
supported!"), which has nothing to do with your code.

### Reliable recipe (each step self-terminating, add your own timeouts)

1) Permanent file-mode sanity: `git status --short` should NOT list `*.uid`
   (project `.gitignore` ignores them). If it does, they're untracked noise —
   never `git add -A`.

2) First-time or Big-Asset import (a real Blender/glb world):
   `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import . 2>&1 | findstr /i "SCRIPT ERROR Parse Error Failed to load"`
   → expect ZERO `SCRIPT ERROR` / `Parse Error` lines (benign `resources still
   in use at exit` and Terrain3D whitelist lines are allowed).

3) GDUnit suite (headless, PRECEDED by step 2 so gdUnit4 is had its first-run):
   `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --ignoreHeadlessMode -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests > _gdunit.txt 2>&1`
   Then `findstr /c:"Overall Summary:" _gdunit.txt`.
   EXPECT: `Overall Summary: 33 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans` (33/33 — suite grew with D4).

NOTE: if you run the GDUnit `-s` command ALONE (without the earlier headless
run), it may bail with exit 103/exit 1 "Headless mode is not supported". The
order above (plain --headless probe FIRST, then --ignoreHeadlessMode) is what
keeps it green. When in doubt, just run step 2 once, then step 3.

## PROJECT CONVENTIONS
- Runtime entry: `res://scenes/main.tscn`. Player on track:
  `res://scenes/vehicle/player_car.tscn` (VehiclePhysics, mass ~1100kg, 4×
  `Wheel*` children, `PlayerCarController` child with `_apply_visual()` swapping
  the CarBody glb per active car from `Garage.new_from_save().get_active_car()`).
- Cars are DOOM-style 3D: `assets/cars/*.glb` (sports_coupe, muscle_car,
  rally_hatch) each consumed as `PackedScene`; the player visual is the
  `SportsCoupe` instance with `CAR_ORIENT` (const Transform3D of a 180° Y
  rotation) so the nose faces forward. Chase camera: `scripts/camera/chase_camera.gd`.
- Career: `scripts/career/garage.gd` (Garage owns `_owned_cars`, `set_active_car`,
  saves via `SaveManager`). Garage UI: `scenes/ui/garage.tscn` + `scripts/ui/garage_ui.gd`.
- Progression classes: D/C/B/A/S via `car_config.gd` (`car_class`, mass, torque,
  gear_ratios, upshift/downshift kmh).
- GDUnit structure: `functions` split into `pre_check`/`check_part_a`/`check_part_b`
  where the scene needs two frames; keep using `assert_that(...).is_equal`.
- The FUN files (the reasons the game exists) live in the playtest flows:
  garage→select car→drive; right-joystick orbit camera; FH5/GT7-style garage.
