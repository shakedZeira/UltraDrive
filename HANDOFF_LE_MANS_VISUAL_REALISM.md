# Handoff: Le Mans Visual Realism — final state (2026-10-21)

Plan: `docs/plans/le_mans_visual_realism_plan.md` — **§8 is the authoritative
per-workstream status** (shipped / partial / not done, counts, caveats).
Nothing is committed.

## What changed in this pass
- The previous handoff was stale: the `settings_menu.gd` static-call compile
  error was already fixed (scene_root parameter); the import probe is clean
  (only the benign Terrain3D editor-plugin `double_slider.gd` line).
- The previous dressing extension was mostly placeholder (untextured Decals
  that rendered nothing, a self-intersecting sand polygon, 80 m black "tree"
  slabs, corner-only armco, uniform slabs). Rewritten:
  - `scripts/track/le_mans_dressing.gd` — WS-A/C/D/E/F (see plan §8).
  - `scripts/track/le_mans_surfaces.gd` (new) — shared noise + materials.
  - `scripts/track/le_mans.gd` — world-space ground shader on plain/skirt, verge
    wear band, UV'd road visual strip + asphalt shader, edge strips hidden.
  - `shaders/le_mans_*.gdshader(inc)` — ground, gravel, asphalt, sky.
  - `scenes/track/le_mans.tscn` — custom cloud sky, fog retune.
  - `tests/suites/test_le_mans_track.gd` — 13 cases (6 for this plan).
  - `tools/le_mans_visual_capture.gd` — rewritten: free camera (the old one
    teleported a RigidBody and every shot was the S/F line), applies a quality
    preset, prints per-view PERF lines.
- `surface_registry.gd` / `settings_menu.gd` changes from the earlier pass kept.

## Gate
Baseline (tree before this pass): 1407 cases, 0 errors, 2 failures
(`test_barcelona_rx_barriers::test_pusher_cannot_cross_the_barrier`,
`test_post_race_cinematic::test_cinematic_retires_gameplay_rigs`).
After: 1410 cases, 0 errors, 1 failure (the same post-race-cinematic case).
Both failures are outside Le Mans and pre-existing.

## Visual critique
Done by Claude opening the captures with the Read tool — **never Ollama or
Gemini** (project rule; `tools/ollama_vision.py` is
disabled; the old Ollama batch script was deleted). Earlier Ollama critique output is not evidence.
Before/after: `.vision/captures/lemans_before_*.png` vs `lemans_final_*.png`
(Medium), `lemans_low_*`, `lemans_high_*`. Findings in plan §8.

## How to re-check
- Suites: `py tools\gdunit_parallel.py -j 2 --only test_le_mans_track.gd`
- Captures (windowed, NOT headless):
  `<GODOT_EXE_CONSOLE> --path . -s res://tools/le_mans_visual_capture.gd -- --tag=x --preset=1`
  → `.vision/captures/lemans_x_*.png` + `PERF view=...` lines.
- Shared machine: take `D:/Temp/claude/d--AI-Projects-UltraDrive/godot.lock`
  (mkdir) before any Godot run.

## Open items (honest)
- No HDRI asset (custom sky instead); tonemap/shadow distance stay preset-owned.
- Trees are stylised low-poly lobes; buildings are plain massing.
- Flat v1 ground: no trap slope, 0.40 m road-edge step remains.
- `TrackBuilder` road strip renders its back face (near-black asphalt) on other
  tracks too — fixed only for Le Mans (own visual mesh); worth a shared fix.
- Untracked scratch left by earlier passes: `tools/_lemans_*.bat/.py/.gd`,
  repo-root `_lemans_*.log/.txt`. Safe to delete.

## Reusable guidance
`.claude/skills/track-design/SKILL.md` — project skill distilling this work
(layout → registry/scene/pins → dresser → surfaces → presets → perf → gates →
capture/critique) for any future track.
