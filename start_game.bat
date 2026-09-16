@echo off
REM UltraDrive - start the game (2 ways)
REM Godot 4.7.2 project. Edit GODOT_EXE if your path differs.

set "GODOT_EXE=D:\Godot\Godot_v4.7.2-stable_win64.exe"
set "PROJECT=%~dp0"

REM Prefer a GUI editor run so you can also edit/extend the game.
REM Press F5 inside Godot to run the whole project (main menu).
start "" "%GODOT_EXE%" --path "%PROJECT%"

REM ALTERNATIVE (uncomment to run the main scene directly without the editor):
REM start "" "%GODOT_EXE%" --path "%PROJECT%" scenes/ui/main_menu.tscn
