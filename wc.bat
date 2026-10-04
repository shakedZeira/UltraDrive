@echo off
rem POSIX-name shim -> tools\pick.ps1 (see AGENTS.md).
rem Makes `wc -l file` WORK in cmd.exe instead of failing with
rem "'wc' is not recognized". Note the mapping: wc forwards to pick's `lines`,
rem so `wc -l f` and `wc f` both print the line count.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\pick.ps1" lines %*
exit /b %ERRORLEVEL%