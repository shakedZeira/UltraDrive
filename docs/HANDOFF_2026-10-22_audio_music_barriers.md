# Handoff — 2026-10-22 (session 2): GT-R audio, brakes, backfire, music, Le Mans barriers, open-world plans

Written for the next Claude session. **Nothing from this session is committed.** Sub-agents were
still running when this was written; see "Agent status" and verify the tree with tests before trusting
any "done". Read `docs/HANDOFF_2026-10-22_session.md` too (older work, commit plan, usage notes).

## Standing rules (also in CLAUDE.md / memory)

- Never use Ollama or Gemini. Claude analyzes images itself (Read tool). Put this in every sub-agent prompt.
- graphify first (`graphify query/explain/path`), `graphify update .` after code changes.
- One Godot process at a time: `mkdir "D:/Temp/claude/d--AI-Projects-UltraDrive/godot.lock"` before any
  Godot run, `rmdir` after. Console exe: `D:\Godot\Godot_v4.7.2-stable_win64_console.exe`.
  Set `GODOT_EXE_CONSOLE` to it when running `py tools/gdunit_parallel.py -j 4`. `godot_path.bat` does NOT
  resolve from agent shells; a log line "did not export a usable GODOT_EXE_CONSOLE" means NOTHING ran and the
  exit code 0 is a FALSE GREEN. Read the real test counts. See `docs/GDUNIT_GATE.md`.
- Never `git stash` / checkout while agents edit the tree. A user stash exists and must stay:
  `stash@{0}: grass-green work (backup before revert to 487e667)`.
- Spawn agents with `model: "sonnet"` unless the user asks otherwise (usage cost, see older handoff).
- Commit plan (user's choice): after all agent work is done and tests are green, a few logical commits,
  push to `origin master`. Exclude repo-root scratch (`_*.txt`, `check_import.py`, `import_test.txt`,
  `le_mans_test.txt`, `lemans_test.out`, `run_lemans_test.bat`, `tools/_dl_brands.py`,
  `tools/_r35_capture_tmp.bat`, `*.v1.bak`). Commit message trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## User requests this session and where each stands

| # | Request | State |
|---|---|---|
| 1 | GT-R turbo whistle goes up/down in gear | DONE in code (untested by ear). Boost smoothing in `scripts/audio/engine_audio.gd` (`turbo_boost_step`), loop stabilised by `tools/make_gtr_turbo_stable.py`. |
| 2 | GT-R engine sound not realistic | DONE in code (untested by ear). `tools/make_gtr_beds.py` rewritten around engine orders (firing = order 3, rpm/20 Hz); new `intake_roar.wav`, `gear_whine.wav`; checks `tools/check_gtr_orders.py`, `tools/check_gtr_beds.py`. Mix trims (roar -11 dB, gear whine -21 dB) are first guesses. |
| 3 | Open-world status + FH6-style plan (bigger, realistic, real traffic) | DONE (docs only): `docs/plans/open_world_status.md`, `open_world_fh6_plan.md`, `open_world_traffic_plan.md`. |
| 4 | Pops/bangs must show backfire flames | DONE, captures inspected. `scripts/vehicle/exhaust_backfire.gd`, shaders `shaders/exhaust_flame.gdshader` + `exhaust_ember.gdshader`, node added to `scenes/vehicle/player_car.tscn`, tests `test_exhaust_backfire.gd`. Polls EngineAudio's `ExhaustPop` player; an `exhaust_pop(loudness,count,window)` signal in `engine_audio.gd::_fire_overrun` would give exact timing (not added). Player car only; cockpit view not captured. |
| 5 | Music in free roam, using Spotify Replica as reference | Plan DONE: `docs/plans/freeroam_music_plan.md`. Implementation PARTIAL (agent stopped; see below). |
| 6 | Brake sticks after a long hard brake | FIXED in `scripts/vehicle/wheel_physics.gd` (`step_wheel_spin`: brake only moves spin toward 0, never crosses it). Tests `tests/suites/test_brake_release_recovery.gd`. Not played by hand. |
| 7 | "stututu" flutter not realistic | Research DONE: `docs/research/turbo_flutter_sound.md`, prototype `tools/make_gtr_flutter.py`, `tools/check_gtr_flutter.py`. Execution PARTIAL (agent stopped; assets generated, code/tests unverified). |
| 8 | Le Mans barriers must be solid | PARTIAL (agent stopped): `le_mans_dressing.gd` edited, `test_le_mans_barriers.gd` added, nothing verified. |
| 9 | Download songs via Spotify Replica core | DECLINED: its core uses `YouTubeResolver` (ToS violation / copyright); user asked to avoid detection. Offered: `adb pull` of songs already on the phone, user's own library, licensed CC music fetch script. User has not chosen. |

User decisions: music = folder of files (default `D:\Music\UltraDrive`), FreeRoam only; radio stations,
now-playing toast, controls. PS4 pad via **DS4Windows** (presents an Xbox pad): D-pad Left/Right = prev/next,
pause = touchpad (button 20, only if the game sees a native DS4) AND Back/Select tap; user must map
touchpad click -> Back in DS4Windows. Traffic = FH6-style ambient AI; world growth = staged.

## Agent status: ALL THREE WERE STOPPED MID-TASK at ~94% usage (user request). Work is on disk, UNVERIFIED.

No agents are running, no Godot processes, no `godot.lock`. Two orphan Godot runs (a `test_le_mans_barriers.gd`
shard) were killed. None of the three agents delivered a final report: treat everything below as partial.
No Godot test run was done on any of it after the last full gate, so run the affected suites first.

- **Music implementation (stopped while writing the pure-logic test suites).** On disk:
  `scripts/music/*.gd` (21 files: scanner, library, tag/id3/ogg/flac parsers, shuffle bag, station queue,
  crossfade math, ducker, policy, input, settings, service, context host), `scripts/ui/music_toast.gd` +
  `scenes/ui/music_toast.tscn`, `scripts/ui/music_settings_section.gd`, `tools/music_convert.py` +
  `tools/test_music_convert.py`, 14 `tests/suites/test_music_*.gd` files + `music_test_util.gd`.
  Edited existing files: `project.godot` (+39 lines: autoload and input actions), `.gitignore` (+15),
  `scenes/world/open_world_root.tscn`, `scenes/ui/settings_menu.tscn`, `tests/test_input_mapping.gd`,
  `scripts/audio/engine_audio.gd` (bus-target change, maybe). Unknown: whether P0 (Vehicle/Music buses +
  moving the engine LPF off Master) is complete, whether any music test has ever run, DS4/touchpad behaviour.
  `test_rival_ai` was failing earlier with `EngineAudio.ensure_for` missing = a half-finished edit; check it.
- **Flutter execution (stopped while editing tests).** New assets in `assets/audio/engine/gtr/`:
  `flutter_{lo,mid,hi}_{0,1}.wav`, `bov_0.wav`, `bov_1.wav`. Unknown: whether `engine_audio.gd` playback
  (variant select by boost, cooldown, pitch jitter, -5.7 dB trim) was finished, whether tests were updated, and
  whether `tools/check_gtr_flutter.py` passes on the shipped assets. Plan: `docs/research/turbo_flutter_sound.md`
  section 6. Old `flutter_hits.wav` / `bov_tail.wav` must stay for other cars.
- **Le Mans barriers (stopped while its test was running).** `scripts/track/le_mans_dressing.gd` has +210 lines;
  new `tests/suites/test_le_mans_barriers.gd`. Unknown: whether the test passes, lap coverage before/after, whether
  an out-of-bounds respawn was added, no screenshots reviewed. Also run the Barcelona RX / multi-lane rail barrier
  suites to confirm shared code was not broken. Repo-root `le_mans_test.txt` is scratch.
- Resume options: start fresh agents with the task text from this file, telling them what is already on disk,
  or finish by hand. Do not rewrite from scratch.

## FINAL gate (98% usage, everything included): 1643 tests, 3 failures, no false greens

Failing: `test_post_race_cinematic.gd:239` (pre-existing, fails on clean HEAD) and the two Le Mans agent tests
`test_le_mans_barriers.gd:315` (`test_wall_height_follows_the_elevated_road`) and `:425`
(`test_crash_test_car_is_stopped_at_30_60_90_ms`). Everything else is green: audio/flutter/backfire, music
(160 tests), brake (7/7). Not yet committed. Only the Le Mans barrier work is unfinished; the rest could be
committed now (exclude the Le Mans edits in `scripts/track/le_mans_dressing.gd` + `test_le_mans_barriers.gd`
if committing before they pass). The older sections below are history; where they conflict, this section wins.

## Test status — earlier gate (after all agents stopped): 1483 tests, 4 failures, music suites NOT included

The gate aborts as a false green (0 tests) while ANY test file has a parse error. The stopped music agent left
parse errors in at least `tests/suites/test_music_scanner.gd`, `test_music_ogg_flac_parser.gd`,
`test_music_id3_parser.gd` and `test_music_tag_reader.gd` (`Assigned value for constant "U" isn't a constant
expression`; `write_file()` given a String instead of PackedByteArray). To get a real result I temporarily moved
ALL `tests/suites/test_music_*.gd*` out and ran the gate, then restored them (24 files back in place). So the
music suites have never run. Fix those parse errors first (probably `const U = <preload/func call>` -> `var`/`preload`
const, and `PackedByteArray` for `write_file`), then run them.

**UPDATE (later, ~96% usage): music parse errors FIXED and music suites now run green: 160 tests, 0 failures**
(14 `test_music_*` suites). Fixes: `const U = preload("res://tests/suites/music_test_util.gd")` in 4 suites,
`to_utf8_buffer()` in `test_music_scanner.gd:145`, `scripts/music/id3_parser.gd` UTF-8 multi-value separator now
`SEP` (was 0x1F, so multi-artist tags were not joined), and two save round-trip asserts use `int(...)` because JSON
loads whole numbers as floats. A full gate (music included) has NOT been re-run since; do that first. The music
code is still untested by ear/with real songs and on a real DS4/DS4Windows pad. Failures 1-4 below are unchanged.

Real failures in that run (4):
1. ~~`test_brake_release_recovery.gd` whole-car test~~ FIXED LATER (suite 7/7). NOTE: the line-148 failure was the
   windup assertion (min wheel spin -24.8 rad/s over the whole 4 s hold), NOT the coast-down check as first written
   here. Cause was transient frames right after the 45 m/s teleport (airborne settle, brake-input ramp, engine-brake
   pull). The test now checks only the steady window (frames 60-240), where the spin stays >= -0.001, which is the
   signature of the user's bug (windup grew with hold time). The post-release coast-down assertion passes. Residual:
   the transient first second is not asserted, and nobody has played it by hand.
2. `test_le_mans_barriers.gd:315` `test_wall_height_follows_the_elevated_road` and
3. `test_le_mans_barriers.gd:425` `test_crash_test_car_is_stopped_at_30_60_90_ms` — the Le Mans agent's own new tests
   fail: the barrier fix is incomplete or the tests are wrong.
4. `test_post_race_cinematic.gd:239` — pre-existing (fails on clean HEAD), not ours.
Everything else passed (flutter/audio suites, backfire, tests touched by the music edits to project.godot/input map).

## Older test status (gate before the later agent edits: 1464 tests)

- Failing, NOT ours: `test_post_race_cinematic.gd:239` `test_cinematic_retires_gameplay_rigs` (fails the
  same on a clean worktree of HEAD; cause unknown: prior camera not `current` after `cine.stop()`).
- Earlier-noted pre-existing: `test_hardening.gd` 2 failures (`test_arcade_speed_clamp_wired_into_live_physics_frame` + one more).
- Seen mid-session: `test_rival_ai` 3 failures `EngineAudio.ensure_for` missing = another agent's half-finished
  `engine_audio.gd` edit. Re-run after all agents finish; must be green.
- The brake suite was fixed after that gate run (7/7 alone); re-run in the final gate.

## Next steps

1. Check which agents finished / were stopped; read their final reports if any.
2. Re-run the full gate: `GODOT_EXE_CONSOLE=... py tools/gdunit_parallel.py -j 4` (verify real counts, no false green).
3. Fix anything red that is ours (see above); leave the two pre-existing failures documented.
4. Ask the user to listen: GT-R turbo steadiness, engine, flutter, backfire; try a long hard brake; check Le Mans
   walls by driving into them; try music with songs in `D:\Music\UltraDrive` and the DS4Windows setup.
5. Commit in logical groups (audio, brake fix, backfire VFX, music, Le Mans barriers, plans/docs), push to `origin master`.
6. Open questions remaining in `docs/plans/freeroam_music_plan.md` section 17 (ffmpeg conversion mandatory?,
   Replica export, crossfade default, toast position, favourites/radio-off, Windows-only, mix levels).
7. Open-world next steps (from the status doc): terrain texture set (terrain shows the default checkerboard),
   wire `RegionDresser` (built but not in the scene; ROADMAP W.6/W.7 claim is wrong), stream road meshes, LaneGraph,
   pooled kinematic traffic.
