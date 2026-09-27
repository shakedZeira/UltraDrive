@echo off
REM UltraDrive - start the game (2 ways)
REM Godot 4.7.2 project. No path editing needed: godot_path.bat finds the
REM binary in D:\Godot (PC) or C:\Godot (laptop). Set GODOT_EXE to override.
call "%~dp0godot_path.bat"
if errorlevel 1 (
    pause
    exit /b 1
)

set "PROJECT=%~dp0"
REM Strip the trailing backslash so "%PROJECT%" never ends in a dangling \
REM that swallows the closing quote and mangles the Godot --path argument.
set "PROJECT=%PROJECT:~0,-1%"

REM Prefer a GUI editor run so you can also edit/extend the game.
REM Press F5 inside Godot to run the whole project (main menu).
start "" "%GODOT_EXE%" --path "%PROJECT%"

REM ALTERNATIVE (uncomment to run the main scene directly without the editor):
REM start "" "%GODOT_EXE%" --path "%PROJECT%" res://scenes/main.tscn
