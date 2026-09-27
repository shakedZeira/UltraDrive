@echo off
REM UltraDrive - play the game directly (no editor).
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

start "" "%GODOT_EXE%" --path "%PROJECT%"
