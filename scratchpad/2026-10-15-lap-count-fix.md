# Lap counting fix — off-track must not eat the lap (2026-10-15)

## Bug (2 coupled defects, verified against code + prior tree work)
1. Finish re-latch at re-arm: `lap_completed` -> `_on_lap_completed` -> `reset_checkpoints()`
   clears `_counted` while the car is STILL INSIDE the finish box -> next `_process` frame
   `is_passed` re-latches the finish gate. Old strict chain: `_last_checkpoint` = total-1 ->
   expected 0 -> the re-latch is rejected but `_counted` stays latched forever (only `reset()`
   clears it, which needs a lap completion that can never come) -> lap 2+ never ticks.
2. Strict expected-index wedge: one missed gate off-track desyncs `(_last+1)%total` forever.

## Fix (both files, ZERO race_manager.gd edits)
- `checkpoint.gd`: `uncount(vehicle)` releases the per-vehicle pass latch without re-arming.
- `lap_counter.gd`: forward high-water `_last_checkpoint` (standings) + per-lap distinct-gate
  set `_passed_in_lap`. Finish (index == total-1) completes a lap only when
  `_passed_in_lap.size() >= total / 2` (int div: 8->4 of 7, 3->1 of 2, 2->1 of 1, 1->0 trivially).
  Rejected finish -> `passed_checkpoint.uncount(vehicle)` so a later legitimate crossing still
  counts (nothing else clears the finish latch). Gate set left intact, keeps accumulating.
  Lap completion clears set + hw (fresh lap). Non-finish gates: always credited, hw advances
  only on forward moves (duplicates/backward = no state change).
- Deviation from the pre-checkpoint plan (inside_at_arm suppression): `uncount`-on-reject alone
  fixes the linger-wedge AND the reject-then-full-loop wedge, has no start-race behavior change
  (grid cars still count cp0 by sitting on it, as before), no multi-car denial. Superseded.

## Behavior pinned by existing tests (all traced, all stay green)
- test_northern_isle: 0..7 -> exactly 1 lap at 7 (set 7>=4); cp7-first rejected (0<4) then
  0..6 -> no lap (finish never re-crossed).
- test_race_results: total=1 update(cp0) -> 0>=0 accept (best_lap); total=2 rival cp0,cp1 -> 1>=1.
- test_race_loop standings: hw semantics preserve tie structure ([leader, ahead, behind]).
- test_rival_personalities `_finish_counter`: 3-ring x2 laps -> 2>=1 each lap, is_finished.
- test_lap_completion_rearms...: no edit needed anymore (suppression design would have needed
  one; uncount doesn't touch non-finish latches) -> assert cp0.is_passed stays true.
- `["lap_completed"]` result key: no consumer reads it (RM reads race_finished only).
- int/int `/` OK: committed green precedent (racing_line.gd, test_collectibles.gd).

## New regression tests (tests/suites/test_race_loop.gd + `_drive_gate` helper)
(a) test_second_lap_counts_while_car_lingers_in_finish_box — falsifies OLD code twice
    (phantom/wedge asserts after the lingering re-latch).
(b) test_missing_one_gate_offtrack_still_counts_the_lap — 8 gates, skip 6 -> lap counts (old: desync, no lap); then clean lap 2 -> no wedge.
(c) test_finish_crossing_without_enough_gates_grants_no_lap — 3 of 7 gates then finish -> no lap; then enough gates -> next crossing counts (anti-wedge of the rejection itself).

## Gate (targeted suites, ONE godot process)
tasklist check -> import probe (`--headless --import .`, console exe via godot_path.bat, own
APPDATA `reports\parallel\agent2\userdata`) -> gdUnit `-s GdUnitCmdTool.gd --ignoreHeadlessMode`
with repeated `-a` for: test_race_loop, test_race_countdown, test_race_results, test_race_rivals,
test_northern_isle_track, test_rival_ai, test_rival_personalities. Output `_gdunit_agent2.txt`,
verify non-zero bytes + Overall Summary + executed-vs-defined counts.
(test_race_logic / test_lap_counter* do not exist in the tree.)
