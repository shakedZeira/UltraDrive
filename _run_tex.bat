@echo off
for %%S in (test_streaming_dressing test_foliage_models test_dressing_road_clearance test_track_props test_building_placement) do (
  echo === %%S === >> _gdunit_tex.txt
  "D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/suites/%%S.gd >> _gdunit_tex.txt 2>&1
  findstr /c:"Overall Summary:" _gdunit_tex.txt
)