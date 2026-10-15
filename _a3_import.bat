@echo off
rem THROWAWAY (agent 3) - headless import probe. Delete when done.
cd /d "%~dp0"
call godot_path.bat
"%GODOT_EXE_CONSOLE%" --headless --import . > _a3_import.txt 2>&1
echo IMPORT_EXIT=%ERRORLEVEL%
