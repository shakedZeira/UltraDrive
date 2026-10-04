@echo off
rem Portable head/tail/grep/lines/find/ls shim for a Windows agent shell.
rem Usage: tools\pick.bat head 20 file.txt      (see tools\pick.ps1 for all)
rem
rem Deliberately label-free and goto-free: cmd.exe mis-parses batch files that
rem have LF-only line endings once labels or parenthesised blocks appear, and
rem keeping the logic in the .ps1 makes that impossible here.
rem
rem Arguments are forwarded verbatim, so avoid | < > & inside a pattern.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pick.ps1" %*
exit /b %ERRORLEVEL%