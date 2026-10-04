@echo off
rem POSIX-name shim -> tools\pick.ps1 (see AGENTS.md).
rem Makes `head -n 20 file` WORK in cmd.exe instead of failing with
rem "'head' is not recognized". cmd.exe searches the current directory
rem before PATH, and this shim is only ever reached from the project root.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\pick.ps1" head %*
exit /b %ERRORLEVEL%