# Handoff — 2026-10-22 session (Blender MCP, R35 redesign, Le Mans, tracks, skills)

Written for the next Claude session. **Nothing from this session is committed.**
All three sub-agents stopped mid-task when the user's usage limit hit (HTTP 429,
2026-10-22 ~07:30). Their work is on disk; each item below says where it stopped.
Verify state with tests before trusting any "done".

## Standing rules (also in CLAUDE.md / AGENTS.md / memory)

- **Never use Ollama or Gemini.** Claude analyzes images itself (Read tool).
  `tools/ollama_vision.py` exits unless the user sets `ULTRADRIVE_ALLOW_OLLAMA=1`.
  Repeat this in every sub-agent prompt that does visual checks.
- graphify first (`graphify query/explain/path`) before grepping/reading code;
  `graphify update .` after code changes.
- **One Godot process at a time.** Agents share a lock: `mkdir
  "D:/Temp/claude/d--AI-Projects-UltraDrive/godot.lock"` before any Godot run,
  `rmdir` after. (A stale lock was removed at handoff time.) Godot exe:
  `D:\Godot\Godot_v4.7.2-stable_win64_console.exe` (`godot_path.bat` may not
  resolve from agent shells). Gate rules: `docs/GDUNIT_GATE.md`.
- Give every Godot run a shell-side timeout (an open-world capture hung once).

## Usage / cost — pending user decision (NOT applied)

`/usage`: built-in `general-purpose` sub-agents were 94% of usage (they inherited
Opus, high effort). No agent file defines them. Proposed, awaiting the user's OK:
1. `C:\Users\LotusSeven\.claude\settings.json`: add
   `"env": {"CLAUDE_CODE_SUBAGENT_MODEL": "sonnet"}` (main chat stays Opus).
2. Optional: graphify skill chunk agents → `model="haiku"`
   (`.claude/skills/graphify/SKILL.md:300-306`; `graphify install` overwrites it).
3. A memory note: spawn agents with `model: "sonnet"` unless the user asks for Opus.
Until the user decides, pass `model: "sonnet"` when spawning agents, and say so.

## Commit & push — user asked; do it when the work is finished

User chose: commit **after all agent work is finished and tests are green**, in a
few logical commits, then push to `origin master` (their workflow is direct to
master; remote was in sync at `e9f75a0`). Include older uncommitted features
(speed-trap HUD, post-race cinematic, menu videos, garage brands, etc. — they
predate this session). **Exclude repo-root scratch**: `_d1.txt`, `_d2.txt`,
`_diff_*.txt`, `_gstatus.txt`, `_hud_tests.txt`, `_r35_capture_log.txt`,
`_resolve*.txt`, `_rl.txt`, `_t.txt`, `_tl.txt`, `import_test.txt`,
`le_mans_test.txt`, `lemans_test.out`, `_glb_aabb.py`, `check_import.py`
(confirm with the user if unsure). Largest file is a 9 MB .ogv (fine for GitHub).
Avoid per-file `stat` loops over git status — that's what hung last time.

## 1. Blender MCP — done

- Blender 4.5 LTS add-on on `localhost:9876`. `.mcp.json` declares server
  `blender` (`uvx blender-mcp`) — it **times out on connect** (CONNECT_TIMEOUT);
  not fixed. Working path: `py tools\blender_exec.py <script.py | ->` (raw socket,
  `execute_code`). Headless `blender.exe --background --python ...` also works and
  needs no live Blender.
- Never call `read_factory_settings`/`read_homefile` in the live session — it
  unloads the add-on (happened once).

## 2. GT-R R35 redesign — pass 1 done, pass 2 interrupted

Pass 1 (verified: 11 R35/car/cockpit suites, 103/103 green):
- `assets/cars/nissan_gt-r_r35_2017.glb` rebuilt from `.vision/refs/r35/`
  (10.9k → 95.9k tris); contracts kept (wheel hubs ±0.80/0.355/±1.39, nose +Z,
  `Body` Bayside Blue on surface 0, two taillight materials, `Windscreen` glass).
- `scenes/vehicle/interiors/nissan_gt_r35_2017_cockpit.tscn` rewritten around
  `assets/interiors/r35/r35_cabin.glb` + dial/screen textures; new
  `scripts/vehicle/cockpit_cabin_mesh.gd` (no-shadow rule).
- Originals backed up: `D:\Temp\claude\d--AI-Projects-UltraDrive\ef5daa43-2316-42cf-8b50-085cfbacf98b\scratchpad\r35\backup\`.
  Builder scripts (r35_build/body/details/wheels/cabin.py, gauge_tex.py) in the same `scratchpad\r35\`.

Pass 2 (user-approved; **interrupted, unverified**):
- Goals: realistic driver eye height/position (change `cockpit_seat_*` values
  and their tests — user approved), shaped A-pillar/headliner, find the
  translucent band ~20° below horizon, shoulder character line, fender peaks,
  real panel gaps, deep grille, gunmetal wheels with machined lip filling the
  arches, angular mirrors, smaller wing end plates, ≤150k tris.
- Last known step: wheels done (gunmetal, machined lip, Y-spokes); seat rig was
  being changed to accept a negative (behind-centre) forward offset; renders
  `.vision/renders/gtr_v6_*.png` exist (incl. `gtr_v6_interior_eye*.png`).
  Was about to write the two car skills.
- Modified in pass 2 (check): `scripts/vehicle/cockpit_rig.gd`,
  `scripts/vehicle/car_config.gd`, `resources/cars/nissan_gt_r35_2017.tres`,
  `tests/suites/test_gtr_r35*.gd`, `test_gtr_r35_sightline.gd`, cockpit tests.
- **Next:** inspect gtr_v6 renders vs refs, finish the eye/cabin work, export,
  run the R35/car/cockpit suites + anything touching seat constants, in-game
  captures (`tools/r35_cockpit_capture.gd`; it prints a harmless-looking
  `_apply_visual` SCRIPT ERROR), then write skills
  `.claude/skills/car-exterior-design/SKILL.md` and
  `.claude/skills/car-interior-design/SKILL.md` (contracts, Blender pipeline,
  gotchas, tests, capture/critique loop, checklist).
- Known oddities: cockpit is visually LHD though code says RHD; the steering wheel
  stays black and the dials sweep ~86° because tests pin them.

## 3. Le Mans visual realism plan — done & verified

`docs/plans/le_mans_visual_realism_plan.md` §8 and `HANDOFF_LE_MANS_VISUAL_REALISM.md`
hold full detail. Gate after: 1410 tests, 0 errors, 1 pre-existing failure
(`test_post_race_cinematic::test_cinematic_retires_gameplay_rigs`);
`test_barcelona_rx_barriers::test_pusher_cannot_cross_the_barrier` is flaky.
Medium perf +1.5–3 ms (GTX 970). Captures `.vision/captures/lemans_before_*` vs
`lemans_final_*`. Skill written: `.claude/skills/track-design/SKILL.md`.
Housekeeping done: `_lemans_*` scratch deleted; capture runner renamed to
`tools/le_mans_capture_run.bat`.

## 4. Le Mans elevation — interrupted

- Goal: real Sarthe elevation profile by chainage (Dunlop climb, Tertre Rouge
  drop, Mulsanne undulation, Indianapolis descent, Porsche Curves rise); road,
  ground (replacing the flat plane) and every dressing kind follow it; physics,
  AI, timing, grid, cameras, race-menu preview still work.
- New files: `scripts/track/le_mans_elevation_data.gd`,
  `scripts/track/le_mans_terrain.gd`; edits in `le_mans.gd`, `le_mans_layout.gd`,
  `le_mans_dressing.gd`, `test_le_mans_layout.gd`, `test_le_mans_track.gd`.
- Last known step: "Full counts ran. Now captures with elevation."
- **Next:** run the Le Mans suites, capture (Dunlop, Tertre Rouge, Mulsanne,
  Indianapolis, Porsche Curves) and inspect, full gate, perf, update the plan
  doc + the track-design skill (elevated tracks). Must not edit
  `track_builder.gd`/`surface_registry.gd` (owned by task 5) without coordinating.

## 5. Shared dark-road fix + Barcelona RX dirt — interrupted

- Root issue: `scripts/track/track_builder.gd` emits the road top as a back face →
  near-black asphalt on all tracks (Le Mans has its own workaround strip).
- Barcelona RX is mixed-surface: rallycross/joker sections must be **dirt**
  (visuals + SurfaceRegistry grip from one source of truth, e.g. chainage
  ranges), AI and lap/joker logic still working.
- Files so far: `track_builder.gd`, `surface_registry.gd` (zones should be
  per-owner so Le Mans and Barcelona can't clear each other's),
  `barcelona_rx.gd`, `barcelona_rx_layout.gd`, `scripts/ai/ai_controller.gd`,
  `scripts/world/road_def.gd`, `road_network.gd`, `test_surface_grip.gd`,
  new `shaders/road_mixed_surface.gdshader`, `tests/suites/test_track_builder_winding.gd`,
  `docs/plans/barcelona_dirt_surface_plan.md`, plus a new
  `tools/track_visual_capture.gd` (before-captures in
  `scratchpad\tracks\captures\`).
- Last known step: "Now append layout tests for the dirt sections."
- **Open bug:** the open-world capture hung in an endless
  `TrafficSpawner._spawn_vehicle` null-instance loop (traffic_spawner.gd:129-130,
  152; log `scratchpad\tracks\log_openworld_before.txt`). Unknown whether it's
  the capture harness or a real regression (possibly a car asset changed by
  task 2). Investigate; add a hard timeout / repeated-error abort to the capture tool.
- **Next:** finish the dirt layout tests, run the touched suites and full gate,
  after-captures per track, update the track-design skill.

## Resuming

The previous agents can't be resumed from a new session. Start fresh agents
(Sonnet unless the user says otherwise) with tasks 2, 4 and 5 above, each
pointed at this file and the matching skill/plan. Keep file ownership separate
(task 4 = Le Mans files; task 5 = track_builder/surface_registry/Barcelona/AI;
task 2 = R35/cockpit files). Then commit and push per the section above.
