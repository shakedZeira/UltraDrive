@echo off
rem POSIX-name shim -> tools\pick.ps1 (see AGENTS.md).
rem Makes `tail -n 20 file` WORK in cmd.exe instead of failing with
rem "'tail' is not recognized".
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\pick.ps1" tail %*
exit /b %ERRORLEVEL%