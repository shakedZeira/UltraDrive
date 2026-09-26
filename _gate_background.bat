@echo off
rem Background gate: import probe, then full GDUnit suite. Run via start /b.
set GODOT=D:\Godot\Godot_v4.7.2-stable_win64.exe
set DIR=D:\AI Projects\UltraDrive
cd /d "%DIR%"

"%GODOT%" --headless --import . > _gate_import.txt 2>&1
"%GODOT%" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1

findstr /i "SCRIPT ERROR Parse Error Failed to load" _gate_import.txt > _gate_scripterrors.txt
findstr /c:"Overall Summary:" _gdunit.txt > _gate_summary.txt
findstr /i "SCRIPT ERROR" _gdunit.txt > _gate_suite_errors.txt
echo GATE_DONE >> _gate_summary.txt