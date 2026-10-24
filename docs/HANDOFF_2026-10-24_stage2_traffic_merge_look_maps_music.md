# Handoff — 2026-10-24: spawn on-ramp, LaneGraph + traffic, FH6 look, map UI, R35 front end, music

Written for the next Claude session. Continues `docs/HANDOFF_2026-10-23_open_world_stage2.md` (read its "Standing rules";
they still apply). **All commits below are local on `master`, NOT pushed** (ask the user before pushing). Reports are the
sub-agents' own; the lead session did not re-run anything itself. Last full gate (run by the road-merge agent on the final
tree, after all six commits): **1816 tests, 1 failure, 0 false greens**; the failure is the pre-existing
`test_post_race_cinematic.gd:239`.

## Standing rules (unchanged, short)

- No Ollama/Gemini; Claude opens images itself (Read). Put this in every sub-agent prompt.
- graphify first (`graphify query/explain/path`), `graphify update .` after code changes.
- One Godot process at a time: `mkdir "D:/Temp/claude/d--AI-Projects-UltraDrive/godot.lock"` before, `rmdir` after (also on
  failure). Keep each locked Godot run short (a 10-minute probe once blocked every agent). Console exe
  `D:\Godot\Godot_v4.7.2-stable_win64_console.exe`; set `GODOT_EXE_CONSOLE` for `py tools/gdunit_parallel.py -j 4`.
  "did not export a usable GODOT_EXE_CONSOLE" = nothing ran (false green).
- No `git stash/checkout/reset` while agents edit the tree; `stash@{0}` (grass-green backup) must stay.
- Commit trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Cost:** the session hit its usage limit three times with six agents (three Opus). `.claude/agents/general-purpose.md`
  now sets `model: sonnet` for `general-purpose` sub-agents; a model passed on the Agent call still overrides it. Resume
  agents one or two at a time, and tell them not to idle on the Godot lock.

## Commits (oldest first)

| Commit | Area | Summary |
|---|---|---|
| `4953903` | Music | Station strip (Back held), `music_info` (Y), `.json`/`.m3u8` sidecar playlists, `CarAudio` LPF off Master, `docs/MUSIC_USER_GUIDE.md`, plan status header as-built. |
| `e6dddcd` | Map UI | `MapStyle`, `MapTerrain` (+ `shaders/ui/map_terrain.gdshader`), restyled race-menu map, pause map (zoom/pan/GPS ribbon/hover), minimap; 25 tests. |
| `85138d2` | R35 | Lower blunter nose, V-motion grille, bumper bar, headlight clusters, intercooler mouth, DRL, splitter, hood vents; 103.5k tris. |
| `a180ade` | 3D look | Code-built flora (`flora.gd`, `flora_meshes.gd`), roadside dressing, `world_atmosphere.gd`, `world_landmarks.gd`, terrain tone fixes, `world_detail` preset hook; 18 tests. |
| `6586c0e` | Traffic | `lane_graph.gd`, `traffic_sim.gd`, `traffic_manager.gd`, pooled kinematic cars (14/24/36 by preset); 22 tests. |
| `7e53a71` | Roads | `CorridorPlanner._spawn_on_ramp`: spawn ramp now 1352 m (was 5934 m with a 179.7 deg hairpin) and joins the highway at vertex 103; bug 3f fixed on the terrain side (lower road keeps its lanes clear); 8 tests. |

Docs: `docs/plans/open_world_status.md` sections 11 (merge/3f), 12 (look), 13 (traffic).

## Open items / decisions for the user

1. **Driving side is inconsistent.** `LaneGraph.DRIVE_SIDE = DRIVE_LEFT` (comment: "Japan theme"), matching the right-hand-drive
   R35 cockpit. The new spawn on-ramp lane and its rail gaps suit right-hand traffic on the outer lanes, and older coast/touge
   ramps join the highway the other way. The user has to pick a side; then mirror the ramp or flip the constant (and
   `test_lane_graph.gd:66` follows the constant).
2. Traffic v1 gaps: hitting a car feels like a wall (cars are placed, not physics-synced); no lane changes, horns, night
   lights, audio, far-LOD cars; events still clear all traffic; no menu toggle (`TrafficManager.ENABLED`, spawner flags).
3. Merge: nobody drove the new ramp; `highway-hub-ramp` joins at 46 deg with no exit lane (redundant now); highway outer rail
   missing ~130 m past the taper; 3f proven by measurement only (captures look identical, strip is under the deck).
4. 3D look: alpine dome top is a flat 2000 m clamp, vista draws green below the rocks (they float); fog density is set at
   runtime so `test_environment_lighting` (checks the scene's 0.0012) no longer matches the game; Low/High not measured;
   dusk/night not captured; grass spiky up close; known issue 3c did not reproduce (white box was the grandstand).
5. Map UI: right-click GPS route not confirmed visually; relief image stair-steps when zoomed; Europe/other continent tabs and
   circuit pause map not re-captured; race-menu card list renders as slivers (also in the "before" captures); pad pan/zoom untested.
6. R35: in-game test track lights the nose from behind so the fascia reads near-black; chrome V thin; headlight cluster
   protrudes ~3 cm inner edge; hood vents small; arch lip not shaped; nose ~12 cm long vs reference. Blender MCP was
   disconnected for part of the session (use `tools/blender_exec.py`).
7. Music: nothing heard by ear; no real DS4/DS4Windows or Replica files tried; native folder dialog not clicked;
   `D:\Music\UltraDrive` is empty (user must add MP3/Ogg/WAV or run `tools/music_convert.py`); plan open questions 1, 2, 4, 6-9 still open.
8. Stage-2 leftovers from the previous handoff: hand-drive the ring/touge/x=4096/fast travel; vista/ground quality-preset hook; Low/High measurements.

## Uncommitted leftovers (intentionally excluded)

Repo-root scratch `_*.txt`, `check_import.py`, `import_test.txt`, `le_mans_test.txt`, `lemans_test.out`, `run_lemans_test.bat`,
`_glb_aabb.py`, `tools/_dl_brands.py`, `tools/_r35_capture_tmp.bat`; `*.v1.bak` and pre-existing `.opencode/` changes;
untracked `graphify-out/` caches and dated folders. Agent captures live in the session scratchpad, not the repo
(R35 renders are in `tools/blender/r35/renders/`, in-game R35 captures in `.vision/captures/`).
