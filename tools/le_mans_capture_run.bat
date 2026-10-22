@echo off
REM Throwaway runner for the P4 Le Mans visual capture (tools/le_mans_visual_capture.gd).
REM WINDOWED, NOT --headless: the capture reads root.get_texture().get_image(),
REM which needs a real rendering target.
REM Keeps APPDATA on D: (absolute, project-relative) so Godot's user:// stays off C:.
setlocal
cd /d "%~dp0.."
if not exist "reports\capture_userdata" mkdir "reports\capture_userdata"
set "APPDATA=%CD%\reports\capture_userdata"
call godot_path.bat
if "%GODOT_EXE_CONSOLE%"=="" set "GODOT_EXE_CONSOLE=%GODOT_EXE%"
echo USING: %GODOT_EXE_CONSOLE%
echo PROJECT: %CD%
"%GODOT_EXE_CONSOLE%" --path "%CD%" -s res://tools/le_mans_visual_capture.gd 2>&1
echo EXITCODE=%ERRORLEVEL%
endlocal
