@echo off
for %%S in (test_prop_roadside_placement test_streaming_dressing test_dressing_road_clearance test_prop_scatterer test_foliage_models test_track_props test_building_placement) do (
  echo === %%S === >> _gdunit_props_verify.txt
  "D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/suites/%%S.gd >> _gdunit_props_verify.txt 2>&1
)