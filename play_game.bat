@echo off
REM UltraDrive - play the game directly (no editor).
REM Godot 4.7.2 project. Edit GODOT_EXE if your Godot path differs.
set "GODOT_EXE=D:\Godot\Godot_v4.7.2-stable_win64.exe"
set "PROJECT=%~dp0"
REM Strip the trailing backslash so "%PROJECT%" never ends in a dangling \
REM that swallows the closing quote and mangles the Godot --path argument.
set "PROJECT=%PROJECT:~0,-1%"

if not exist "%GODOT_EXE%" (
    echo Godot not found at "%GODOT_EXE%"
    echo Edit play_game.bat and set GODOT_EXE to your Godot 4.7.2 binary.
    pause
    exit /b 1
)

start "" "%GODOT_EXE%" --path "%PROJECT%"