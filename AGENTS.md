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

3) GDUnit suite (headless, PRECEDED by step 2 so gdUnit4 has had its
   first-run). IMPORTANT: `--ignoreHeadlessMode` MUST come AFTER the tool-script
   path (before it, the engine bails with exit 103):
   `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1`
   Then `findstr /c:"Overall Summary:" _gdunit.txt`.
   EXPECT: `Overall Summary: 39 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 5 orphans` (39/39 — D4 HUD + D5 reverse grew the suite; 5 orphans are benign).

NOTE: if you run the GDUnit `-s` command ALONE (without the earlier headless
run), it may bail with exit 103/exit 1 "Headless mode is not supported". The
order above (plain --headless probe FIRST, then the -s run with the flag AFTER
the tool-script path) is what keeps it green. When in doubt, just run step 2
once, then step 3.

## BLENDER MCP (D4 — configured and verified)

- Blender MCP bridges this session to a live Blender 4.5 (addon version [1,6],
  protocol 5). Tools are exposed as `blender-mcp_*` in sessions whose
  `opencode.json` includes the server; they appear AFTER opencode restarts.
- MCP launcher (in `~/.config/opencode/opencode.json`): use the direct exe
  `["D:\\Tools\\uv\\bin\\blender-mcp.exe"]` — NOT `uv tool run blender-mcp` (that
  scans venvs and can hang). Env `BLENDER_HOST`/`BLENDER_PORT` default to
  localhost:9876.
- Verify with `opencode mcp list` (server should report Connected) and call
  `blender-mcp_get_addon_status` → expect `up_to_date`, protocol 5, Blender
  4.5.13. Check telemetry with `blender-mcp_get_addon_status` too.
- Known-good PNG → silhouette → model flow (used for the sports coupe &
  muscle/rally builds): generate in Blender via Hyper3D `rodin`, export glb to
  `assets/cars/`, consume as PackedScene.

## TERRAIN (D4)
- Mountain Pass ground is now a runtime-built `Terrain3D` (node named
  `GrassGround`): a 1024² height/color bake imported via `data.import_images()`
  anchored at region grid -512 (spacing 1.0, region_size 512) so the road loop
  (x/z ±80 m) sits inside regions -1..0. Every road point is recessed into a
  0.6 m "washbed" (SHOULDER_DISTANCE 8, BLEND_END_DISTANCE 40). Query heights
  with `Terrain3D.data.get_height()`. IMPORTANT: `import_images()` SNAPS its
  position to a region anchor (multiples of region_size), so a bake pane must
  start exactly on one — centered panes straddle a gap and return NaN half the
  loop (this bug was found + fixed in D4 in playtest).
- Foliage (`scripts/world/foliage.gd`) takes an optional
  `ground_height_provider: Callable(Vector2 -> float)` to sit on real terrain;
  falls back to Y 0 on flat circuits.

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
  gear_ratios, upshift/downshift kmh). Reverse (`-1`) is a real gear: drives
  backward, torque is flipped, capped at `max_reverse_speed_kmh` (25).
- HUD: gauges are a Forza/GT-style cluster (`scripts/race/tachometer.gd`,
  `%Cluster` in `scenes/ui/hud.tscn`) driven by `scripts/race/race_ui.gd` from
  `car.get_drive_info()` (`speed_kmh`, `gear`, `rpm`) + config `idle_rpm`/
  `redline_rpm`/`car_class`.
- GDUnit structure: `functions` split into `pre_check`/`check_part_a`/`check_part_b`
  where the scene needs two frames; keep using `assert_that(...).is_equal`.
- The FUN files (the reasons the game exists) live in the playtest flows:
  garage→select car→drive; right-joystick orbit camera; FH5/GT7-style garage.
