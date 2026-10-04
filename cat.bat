@echo off
rem POSIX-name shim -> tools\pick.ps1 (see AGENTS.md).
rem Makes `cat file` WORK in cmd.exe instead of failing with
rem "'cat' is not recognized". The read tool is still preferable in a session.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\pick.ps1" cat %*
exit /b %ERRORLEVEL%