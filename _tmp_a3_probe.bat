@echo off
rem THROWAWAY PROBE LAUNCHER (agent 3) - delete when done.
rem Watchdog kills ONLY this probe's own Godot process (command line match), never another agent's.
cd /d "%~dp0"
call godot_path.bat
set "APPDATA=%~dp0reports\parallel\agent3\userdata"
if "%A3_LABEL%"=="" set "A3_LABEL=%~1"
if "%A3_LABEL%"=="" set "A3_LABEL=before"
if "%A3_DURATION%"=="" set "A3_DURATION=%~2"
if "%A3_DURATION%"=="" set "A3_DURATION=60"
start "" /b powershell -NoProfile -Command "Start-Sleep -Seconds 420; Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*_tmp_a3_probe.tscn*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
"%GODOT_EXE_CONSOLE%" --headless --fixed-fps 60 res://_tmp_a3_probe.tscn > _a3_probe_%A3_LABEL%.txt 2>&1
echo [a3] exit=%ERRORLEVEL%
