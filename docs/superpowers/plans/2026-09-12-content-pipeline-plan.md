# UltraDrive — 3D Content Pipeline & Content Expansion Plan (Blender / Blender-MCP / Unreal)

Status: TOOLCHAIN COMPLETE (T0-T2 verified 2026-09-12: Blender 4.5.13 + Blender-MCP addon v1.6 running on port 9876, opencode MCP server configured). Content phases D1-D5 not started, U1 deferred.
Created: 2026-09-12
Applies to: UltraDrive (Godot 4.7.2-stable, Forward+, Jolt 120 Hz)
Plan authority: User request — research how to integrate Blender, Unreal Engine, and Blender-MCP for free, then plan every improvement they unlock. Research verified by subagents on 2026-09-12 (sources: blender.org/lab/mcp-server, github.com/ahujasid/blender-mcp, github.com/GenOrca/unreal-mcp, github.com/remiphilippe/mcp-unreal, docs.godotengine.org asset pipeline docs).

## Goal

Stand up a **100% free, D-drive-only** 3D content pipeline and use it to close the game-content gaps:
1. Replace the all-primitive car with a properly modeled car (and add more cars for the Garage).
2. Give the tracks roadside scenery / props instead of empty grass.
3. Add a **track-selection menu** and more than one circuit.
4. Make the **open world reachable and drivable** (currently a dead skeleton).
5. Evaluate Unreal honestly: document the option, recommend deferral.

## Verified current state (subagents, 2026-09-12)

- **Open world EXISTS but is not playable.** `scenes/world/open_world_root.tscn` is a skeleton only: `ChunkStreamer` + `Terrain3D` (data dir `res://scenes/world/data/` = only `.gitkeep`, zero terrain data) + `PlayerSpawn` Marker3D + `CameraRig`. No player car, no WorldEnvironment/sun, no HUD/pause, and **nothing loads it** (menu hard-codes `test_track.tscn`, master-plan Task 4.4 originally wired Play/Continue here but the implementation diverged).
- **Exactly ONE track.** The procedural oval `scenes/track/test_circuit.tscn` (built at runtime from 32 points by `scripts/test_circuit.gd` + `TrackBuilder`). **No track registry, no selection UI, no TrackManager/scenario system.** Play & Continue both `flash_to_scene("res://scenes/test/test_track.tscn")`.
- **Machine facts:** Node.js ✓ (D:\nodejs), Python (broken MS Store stub), Go ✗, Docker ✗, **Blender ✗**, **Unreal ✗**. Godot 4.7.2 at D:\Godot.

## Design constraints (from master plan + project rulings)

- **D-drive at all costs.** The user explicitly requires any installs go on D:\ only. Never write to C:\Program Files for new tooling; use portable/manual installs where the default installer targets C:.
- Ruling 33/36: never `:=` from a Variant; unreferenced `class_name` scripts need `--import`.
- Rulings 18/20: verification = headless grep for `SCRIPT ERROR`/`Parse Error`/`Failed to load script`; GDUnit must stay 22/22.
- Commits: scoped identity `git -c user.name="UltraDrive Dev" -c user.email="dev@ultradrive.local" commit -m "..."; never stage *.uid, docs/, reports/, zen_keys.txt`.
- Never `git add .`/`-A`. Temp logs only under `D:\Temp\opencode`.
- Imported `.glb`: commit the `.glb` + its `.import` sidecar; gitignore `.godot/`.
- No paid assets. CC0 only (Poly Haven, Poly Pizza `licence="CC0"`); record source URLs in a README next to assets.

## Phase T0 — Install Blender on D: (user-assisted, no code)

Blender is the core 3D tool. Windows installer ~350 MB. For a D:-only install, use the BLENDER install directory override (or portable zip so nothing touches C:).

1. Download Blender 4.5 LTS (or 5.0.x) Windows installer from blender.org/download.
2. Install; change the install path to `D:\Program Files\Blender Foundation\Blender 4.5\` (never the default C: path).
3. Verify: run `"D:\Program Files\Blender Foundation\Blender 4.5\blender.exe" --version`.
4. In Godot: Editor → Editor Settings → FileSystem → Import → **Blender Path** → set to that blender.exe (enables direct `.blend` import for WIP iteration).
5. Record the absolute path in this plan's "Paths" section (below).

BEST PRACTICE for everything modeled (per Godot docs):
- 1 Blender unit = 1 meter. Apply Scale (`Ctrl+A`) before export.
- Export **glTF 2.0 `.glb`**: +Y Up, Apply Modifiers, UVs, Normals, Tangents; triangulate N-gons; Backface Culling on materials; Principled BSDF + image textures (procedural node trees do NOT export — bake first).
- Godot auto-generates collision at import: **Generate → Physics** (Shape Type: Trimesh for static, Convex/Decompose for dynamic). Suffix `-col`/`-colonly`/`-convcolonly`/`-noimp`/`-lod0/1/2` on object names controls it.
- Never edit an imported scene directly — make an **Inherited Scene** for gameplay tweaks.

## Phase T1 — Install uv on D: (tooling for Blender-MCP)

`uv` is the package runner the Blender-MCP server uses; it also sidesteps the broken MS Store Python stub because its tool env installs its own Python.

1. Download the standalone zip `uv-x86_64-pc-windows-msvc.zip` from github.com/astral-sh/uv/releases and extract to `D:\Tools\uv\`.
2. Add `D:\Tools\uv` to the user PATH (keeps everything on D:).
3. Set env vars so uv's tool installs land on D::
   - `UV_TOOL_DIR=D:\Tools\uv\tools`
   - `UV_TOOL_BIN_DIR=D:\Tools\uv\bin`
4. Verify: `uv --version`, `uvx --version`.

## Phase T2 — Blender-MCP (AI-driven Blender, free)

Primary project: `ahujasid/blender-mcp` (MIT, blendermcp.org, ~21k stars) — the ecosystem standard. Two parts: a Blender add-on (runs a socket server on localhost:9876) and a Python MCP server that bridges your AI client.

1. Install the add-on: `uvx blender-mcp install-addon` (or grab `addon.py` from the repo manually).
2. In Blender: Edit → Preferences → Add-ons → enable **Interface/System "MCP for Blender"**; press `N` in 3D view → **MCP for Blender** sidebar → **Start MCP Server** (port 9876).
3. Register in opencode config `%USERPROFILE%\.config\opencode\opencode.json` (note: opencode.json lives on C: as a config file — this is config, not a software install; user OK'd config edits already):
   ```json
   {
     "mcp": {
       "blender-mcp": {
         "type": "local",
         "command": ["uvx", "blender-mcp"],
         "enabled": true,
         "environment": { "BLENDER_HOST": "localhost", "BLENDER_PORT": "9876" }
       }
     }
   }
   ```
4. Restart opencode. Test: "create a cube, make it red and metallic, export as glb to D:\AI Projects\UltraDrive\assets\tmp\test.glb".
5. Only run one MCP client at a time (port 9876 conflicts if Cursor also connects).
6. Free asset integrations (optional): Poly Haven (CC0, no key — HDRIs/textures), Poly Pizza (free key at poly.pizza/settings/api; filter `licence="CC0"` to avoid attribution), Sketchfab (free account + token; only downloadable models; many CC with attribution). Hyper3D Rodin text→3D = free trial key with a daily limit (skip unless needed).

## Phase D1 — Model a real car, retire the primitive box (SUBa: car-model)

Everything under `scripts/career/garage.gd` + `resources/cars/starter_car.tres` already supports multiple cars; `PlayerCarController` now loads the Garage's active car at spawn (committed). The missing piece is real geometry.

1. In Blender, model a low-poly sports coupe matching the physics footprint: 1.8 m wide × 4.0 m long, wheelbase ±1.25 m, axle height 0.2 m, seat the body so wheel centers sit at y=0.2. Export as `assets/cars/sports_coupe.glb`. ✅ DONE 2026-09-12 via Blender-MCP subagent (2784 tris; wheels at exact (±0.8, 0.2, ±1.25)).
2. Replace the all-primitive `CarBody` visual inside `scenes/vehicle/player_car.tscn` with an instanced scene of the `.glb` (keep all physics nodes, config, controller intact). ✅ DONE — glb instanced under CarBody with 180° Y rotation to correct Godot glb front/back flip; primitive Tire/Rim meshes removed (glb carries its own wheel visuals); physics/controller/audio untouched. Committed 29cb0d3.
3. Tune `resources/materials/car_paint.tres` against the modeled body (metallic ~0.45, roughness ~0.3, clearcoat 1.0 stays as committed). ✅ DONE — glb bakes its own Paint material at these values; car_paint.tres kept as reference.
4. ACCEPTANCE: headless `test_track.tscn --quit-after 60` → zero script errors ✅; GDUnit 22/22 ✅; wheels visually at ground ✅ (tire bottom Z≈0); physics unchanged ✅ (lap/speed normal).

## Phase D2 — More cars for the Garage (SUBa: cars)

The Garage UI is wired; `resources/cars/` holds one CarConfig. Add 2 more cars and expose them:

1. Author 2 more low-poly vehicles in Blender (e.g. a muscle coupe and a rally hatch) → `assets/cars/*.glb`.
2. Create `resources/cars/muscle_car.tres` and `resources/cars/rally_hatch.tres` (CarConfig: different mass/torque/class/steer; distinct accent trim colors via per-car paint material instance).
3. Wire: garage starts with `starter_car` owned; add the other two as owned (or via a "dealership"/purchase stub later) so the ItemList shows 3 cars; selecting one sets active car; spawn honors it.
4. ACCEPTANCE: Garage lists 3 cars, Select changes the car driven in test_track; GDUnit 22/22.

## Phase D3 — Track-selection menu + a second circuit (SUBa: tracks)

1. Create a track registry (new autoload `TrackRegistry` or static array in code): human name → packed scene path (+ metadata: description, laps default, difficulty).
2. Add `scenes/ui/track_select.tscn` (grid of buttons generated from the registry) + `scripts/ui/track_select.gd`; re-point `_on_play_pressed()` in `main_menu.gd` to it. Continue keeps its resume semantics.
3. Author a second circuit scene `scenes/track/mountain_pass.tscn` built from a new point set (Twisty canyons use TrackBuilder points with varied radius/altitude; add its own checkpoint set + foliage).
4. ACCEPTANCE: main menu Play → track select → pick oval or mountain → SceneTransition loads chosen scene; HUD/lap display follows; GDUnit 22/22.

## Phase D4 — Make the open world reachable & drivable (SUBa: open-world)

Per subagent analysis, turn the skeleton into a functioning free-roam:

1. In `scenes/world/open_world_root.tscn`: instance `player_car.tscn` at `PlayerSpawn` (128, 2.2, 128); point CameraRig `target` at `%PlayerCar`; add WorldEnvironment + sun (mirror test_track's golden-hour env); add HUD + PauseMenu.
2. Drive `ChunkStreamer.set_player_position()` each physics tick from the car position (add a small driver script on OpenWorldRoot).
3. Author Terrain3D data into `scenes/world/data/` (height/colors) OR fall back to a large procedural ground like test_circuit until real terrain is sculpted in the Terrain3D editor.
4. Add the entry point: a "Free Roam" button on the main menu (and/or re-point Play as master-plan Task 4.4 originally intended) → `flash_to_scene("res://scenes/world/open_world_root.tscn")`.
5. Optional follow-ups (deferred): roads via `scripts/world/road_network.gd` (currently uninstanced), traffic via `scripts/world/traffic_spawner.gd`, real Terrain3D sculpt, streaming chunk scenes.
6. ACCEPTANCE: Free Roam loads, car drives on terrain, camera follows, pause works; headless run + GDUnit 22/22.

## Phase D5 — Roadside props & scenery via MCP (SUBa: assets)

Use Blender-MCP to generate and place CC0 props into the tracks and open world:

1. Curbs/bollards/barriers, start gantry, billboards, guardrails along both circuits; scatter low-poly trees/rocks/structures using the existing `Foliage` system or a new props spawner script.
2. Each prop = `.glb` under `assets/props/` with `-col` collision suffixes so racing feels solid; reuse the TrackBuilder vicinity + chunk approach for placement.
3. ACCEPTANCE: tracks not empty; props collide when hit; no script errors; GDUnit 22/22.

## Phase U1 — Unreal Engine (documented, DEFERRED / likely skipped)

Reality check (research): UE is free via the Epic Games Launcher but needs an Epic account, ~100+ GB disk, and a DX11/12 GPU — and it is a *different engine*; nothing it builds runs in Godot natively. Its only role here would be as a second asset/level authoring tool (export FBX/glTF/USD → import into Godot), credibly covered by Blender at a fraction of the footprint. `erhansiraci/ue-mcp` + UE's built-in Remote Control API is the only UE-MCP option that fits this machine (Node ✓, no Go/Docker/C++ build). **Recommended: skip Unreal unless** we need Nanite-scale static meshes/Lumen-level looks or receive UE-authored assets from a collaborator — then GlTF-through-Blender remains the interop bridge.

If the user overrides: install Epic Launcher to `D:\Program Files\Epic Games` (launcher lets you choose the install dir), install a UE 5.x build trimmed of unused platforms to D:, enable Remote Control API plugin, run `ue-mcp` via npx. Full steps captured in the research subagent report (see chat log).

## Paths (D-drive only, actual as of 2026-09-12)

| Tool | Target path |
|---|---|
| Blender 4.5.13 LTS (portable zip) | D:\Blender 4.5\blender-4.5.13-windows-x64\blender.exe |
| Blender user scripts (BLENDER_USER_SCRIPTS env) | D:\Blender UserData\scripts (addon at ...\scripts\addons\addon.py) |
| uv | D:\Tools\uv\uv.exe |
| uv tools dir (UV_TOOL_DIR env) | D:\Tools\uv\tools |
| uv bin dir (UV_TOOL_BIN_DIR env) | D:\Tools\uv\bin |
| Blender-MCP addon | D:\Blender UserData\scripts\addons\addon.py (from ahujasid/blender-mcp, `main` branch) |
| opencode MCP config (global) | C:\Users\LotusSeven\.config\opencode\opencode.json (config file, NOT an install) |
| Epic Launcher (UNLESS skipped) | D:\Program Files\Epic Games |

## Verification commands (run after every phase)

```
"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --import
"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" res://scenes/test/test_track.tscn --quit-after 60   (grep zero SCRIPT ERROR/Parse Error/Failed to load)
"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests   (expect 22/22)
```