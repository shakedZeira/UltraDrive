# UltraDrive — How to start the game (for you, not the AI)

Project root: `D:\AI Projects\UltraDrive` · Engine: Godot 4.7.2
Binary: `D:\Godot\Godot_v4.7.2-stable_win64.exe`
Main scene: `res://scenes/main.tscn` (auto-selected on run)

## Start the game (3 ways)

1. **Play the build right now (easiest):**
   `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --path "D:\AI Projects\UltraDrive" --editor`  *(no  — that's the editor)*
   → To just RUN the game scene, skip the editor and do:
   `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --path "D:\AI Projects\UltraDrive" --main-scene` **wrong** …
   → The one-command way that just works:
   `"D:\Godot\Godot_v4.7.2-stable_win64.exe" "D:\AI Projects\UltraDrive\scenes\main.tscn"`

2. **Open the editor + F5 (normal dev flow):**
   `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --path "D:\AI Projects\UltraDrive" --editor`
   then press **F5** to run the project (Play), **F6** to run the current scene.

3. **From a file manager:** double-click `project.godot` → Godot opens → press F5.

## Headless bake + tests (for when I'm doing the work — already in AGENTS.md)

- Import probe (expect zero SCRIPT ERROR / Parse Error):
  `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import .`
- GDUnit suite:
  `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --ignoreHeadlessMode -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests`
  → accept `Overall Summary: 28 test cases | 0 errors | 0 failures | ...`

## Notes
- Track menu: Play → Track Select → Oval or Mountain Pass → drive.
- Right stick = 360° orbit camera; garage has 3 cars (Starter/Muscle/Rally) w/ spinning turntable preview.
