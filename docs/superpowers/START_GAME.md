# UltraDrive — How to start the game (for you, not the AI)

Project root: this folder · Engine: Godot 4.7.2
Main scene: `res://scenes/main.tscn` (auto-selected on run)

## The Godot binary — don't type a path

The engine lives in a different place on each machine:

| Machine | Binary |
|---|---|
| PC | `D:\Godot\Godot_v4.7.2-stable_win64.exe` |
| Laptop | `C:\Godot\Godot_v4.7.2-stable_win64.exe` |

`godot_path.bat` (project root) finds whichever one exists and exports it as
`%GODOT_EXE%`. Never hardcode a drive letter in a command — use the resolver
so the same instructions work on both machines:

```bat
call godot_path.bat
```

PowerShell one-liner:

```powershell
$godot = (cmd /v:on /c "call godot_path.bat & echo !GODOT_EXE!").Trim()
```

To pin a specific copy, override it: `set GODOT_EXE=D:\Godot\Godot_v4.7.2-stable_win64.exe`

## Start the game (3 ways)

1. **Easiest — double-click the launcher:** `play_game.bat` (runs the game) or
   `start_game.bat` (opens the editor). Both resolve the engine themselves.

2. **Editor + F5 (normal dev flow):**
   `play_game.bat` is the shortcut-free version:
   ```bat
   call godot_path.bat
   start "" "%GODOT_EXE%" --path "%CD%"
   ```
   then press **F5** to run the project (Play), **F6** for the current scene.

3. **From a file manager:** double-click `project.godot` → Godot opens → press F5.

## Headless bake + tests (for when I'm doing the work — already in AGENTS.md)

Resolve `$godot`/`%GODOT_EXE%` first, then, from the project root:

- Import probe (expect zero SCRIPT ERROR / Parse Error):
  `"%GODOT_EXE%" --headless --import .`
- GDUnit suite (`--ignoreHeadlessMode` MUST come after the `-s` script path):
  `"%GODOT_EXE%" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
  → accept `Overall Summary: 263 test cases | 0 errors | 0 failures | ...`

## Notes
- Track menu: Play → Track Select → Oval or Mountain Pass → drive.
- Right stick = 360° orbit camera; garage has 3 cars (Starter/Muscle/Rally) w/ spinning turntable preview.
