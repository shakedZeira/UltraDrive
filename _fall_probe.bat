@echo off
REM THROWAWAY fall-probe runner. Delete with tests/suites/test_zzz_fall_probe.gd.
setlocal enabledelayedexpansion
call "%~dp0godot_path.bat"
if errorlevel 1 (
    echo ERROR: godot_path.bat failed
    exit /b 1
)

set "APPDATA=%~dp0reports\parallel\agent_fall\userdata"
if not exist "%APPDATA%" mkdir "%APPDATA%"
echo GODOT_EXE_CONSOLE=!GODOT_EXE_CONSOLE!
echo APPDATA=!APPDATA!

if /i "%~1"=="version" (
    "!GODOT_EXE_CONSOLE!" --version
    exit /b !errorlevel!
)

if /i "%~1"=="import" (
    "!GODOT_EXE_CONSOLE!" --headless --path "%~dp0." --import . > _fall_import.txt 2>&1
    exit /b !errorlevel!
)

if /i "%~1"=="probe" (
    "!GODOT_EXE_CONSOLE!" --headless --path "%~dp0." -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/suites/test_zzz_fall_probe.gd -rd reports/parallel/agent_fall > _fall_probe.txt 2>&1
    exit /b !errorlevel!
)

echo usage: _fall_probe.bat version^|import^|probe
exit /b 2
