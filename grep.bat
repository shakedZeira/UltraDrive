@echo off
rem POSIX-name shim -> tools\pick.ps1 (see AGENTS.md).
rem Makes `grep -rn "pat" path` WORK in cmd.exe instead of failing with
rem "'grep' is not recognized". Prints file:lineno:text, takes a file / glob /
rem directory, and exits 1 on no match.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\pick.ps1" grep %*
exit /b %ERRORLEVEL%