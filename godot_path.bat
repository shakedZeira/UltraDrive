@echo off
REM ============================================================================
REM  godot_path.bat - resolve the Godot 4.7.2 binary into %GODOT_EXE%
REM
REM  Works on BOTH machines without editing:
REM    PC     -> D:\Godot\Godot_v4.7.2-stable_win64.exe
REM    Laptop -> C:\Godot\Godot_v4.7.2-stable_win64.exe
REM
REM  Search order:
REM    1. %GODOT_EXE% if already set (override / CI / agent use)
REM    2. Exact match in each candidate dir below
REM    3. Any Godot_v4.7.2*.exe under C:\Godot or D:\Godot (version bumps)
REM
REM  Usage:  call "%~dp0godot_path.bat"   (exits /b 1 with a message if absent)
REM ============================================================================
setlocal

if defined GODOT_EXE goto :resolved

call :try "D:\Godot\Godot_v4.7.2-stable_win64.exe"  && goto :resolved
call :try "C:\Godot\Godot_v4.7.2-stable_win64.exe"  && goto :resolved
call :try "%ProgramFiles%\Godot\Godot_v4.7.2-stable_win64.exe" && goto :resolved
call :try "%ProgramFiles(x86)%\Godot\Godot_v4.7.2-stable_win64.exe" && goto :resolved
call :try "%LOCALAPPDATA%\Programs\Godot\Godot_v4.7.2-stable_win64.exe" && goto :resolved

for %%D in ("D:\Godot" "C:\Godot") do call :glob "%%~D"

if not defined GODOT_EXE (
    echo ERROR: Godot 4.7.2 not found.
    echo   Looked in: D:\Godot, C:\Godot, and the Program Files / LocalAppData defaults.
    echo   Fix: install Godot 4.7.2 into one of those, or set GODOT_EXE yourself:
    echo     set GODOT_EXE=C:\path\to\Godot_v4.7.2-stable_win64.exe
    endlocal & exit /b 1
)

:resolved
REM  Derive the CONSOLE-subsystem twin. The GUI binary is a WINDOWS_GUI PE: under
REM  PowerShell's & operator it detaches immediately, does not wait and does not
REM  attach stdout, so a headless run silently no-ops and reports a FALSE GREEN
REM  (observed: import probe "passed" in 8 ms, _gdunit.txt written as 0 bytes).
REM  Always use %GODOT_EXE_CONSOLE% for --headless / redirected runs.
set "GODOT_EXE_CONSOLE=%GODOT_EXE:win64.exe=win64_console.exe%"
if not exist "%GODOT_EXE_CONSOLE%" set "GODOT_EXE_CONSOLE=%GODOT_EXE%"
endlocal & set "GODOT_EXE=%GODOT_EXE%" & set "GODOT_EXE_CONSOLE=%GODOT_EXE_CONSOLE%" & exit /b 0

REM --- try <full path> : set GODOT_EXE if the file exists ---------------------
:try
if exist "%~1" (
    set "GODOT_EXE=%~f1"
    exit /b 0
)
exit /b 1

REM --- glob <dir> : first Godot_v4.7.2*.exe in <dir> (non-console preferred) ---
:glob
if not exist "%~1" exit /b 0
for /f "delims=" %%F in ('dir /b /o-n "%~1\Godot_v4.7.2*.exe" 2^>nul ^| findstr /v /c:"_console.exe"') do (
    set "GODOT_EXE=%~1\%%F"
    exit /b 0
)
exit /b 0
