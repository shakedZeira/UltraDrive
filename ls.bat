@echo off
rem POSIX-name shim -> tools\pick.ps1 (see AGENTS.md).
rem Makes `ls` and `ls -la` WORK in cmd.exe instead of failing with
rem "'ls' is not recognized". -l is accepted and ignored (long form is always
rem on); -a adds hidden entries.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\pick.ps1" ls %*
exit /b %ERRORLEVEL%