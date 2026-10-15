@echo off
rem THROWAWAY (agent 3) - run the track-geometry dump. Delete when done.
cd /d "%~dp0"
call godot_path.bat
set "APPDATA=%~dp0reports\parallel\agent3\userdata"
"%GODOT_EXE_CONSOLE%" --headless -s res://_tmp_a3_track.gd > _a3_track.txt 2>&1
echo [a3-track] exit=%ERRORLEVEL%
