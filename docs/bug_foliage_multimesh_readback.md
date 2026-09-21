# Bug state: 740 foliage MultiMesh read-back failures (2026-09-20)

## Symptom
`tests/test_dressing_road_clearance.gd` failed with **740 failures** all shaped
like:

```
Expecting to be greater than or equal: 5.999000 but was 0.000000
```

740 = 700 grass + 40 trees. Every `MultiMesh` instance origin read back as
`(0, 0, 0)`. The two other tests in the file (world-offset PropScatterer,
segment/width road-clearance) passed, so the shared road-clearance math is fine.

## Root cause (confirmed by diagnostics, not yet fixed in repo)

In this Godot build (`4.7.2.stable.official.ed1daf0bf`), `MultiMesh`
**transform read-back does not round-trip CPU-side**:

- `mm.set_instance_transform(i, t)` writes the RenderingServer-side buffer
  (visible in-game — grass/trees render in the right annulus), but a subsequent
  `mm.get_instance_transform(i)` / `mm.transform_array` read returns identity /
  `(0,0,0)` every time.
- Reproduced minimally with a bare `MultiMesh`, `instance_count` set, in-tree
  `add_child`, and even after waiting 3 real `_process` frames in a
  `SceneTree`-mode diagnostic (`_diag_frames.gd`). The CPU-side
  `transform_array` (PackedVector3Array, 2800 = 700×4 rows) also reads identity.
- The game **looks correct** because rendering consumes the server buffer, not
  the CPU-side array.

`PropScatterer` never hits this because it stores its placed positions at
generate time in `_placed` and exposes those via `get_instance_transforms()`
(scripts/world/prop_scatterer.gd:35,96). `Foliage` instead read back from the
MultiMesh in `get_instance_positions()` — that was the bug.

## Why some suites "passed" anyway
- `tests/suites/test_streaming_dressing.gd` reads
  `foliage.get_instance_positions()` but only asserts `.size() > 0` and
  *equality between two runs* — comparing a 740-length array of identical
  zero-vectors passes trivially. It does not catch the read-back defect.
- The original 368-test `_gdunit.txt` never ran the two foliage tests at all
  (only `test_world_offset` / `test_road_clearance` produced STARTED lines), so
  the regression was invisible there too.

## Fix applied (working tree)
Mirror the PropScatterer pattern in `scripts/world/foliage.gd`:

- New `_positions: Dictionary` (batch name -> PackedVector3Array) populated
  during `_build_grass()` / `_build_trees()` from the exact transform origins
  handed to `set_instance_transform`; cleared in `generate()`.
- `get_instance_positions()` now concatenates those stored arrays (no MultiMesh
  read-back).
- New `get_batch_positions(mmi_name)` exposes per-batch positions
  ("GrassMMI" / "TreesMMI").
- Test updated (tests/test_dressing_road_clearance.gd): the trees/grass loops
  now iterate `get_batch_positions(...)` instead of reading
  `multimesh.get_instance_transform(i).origin` directly.

## Verification status
- `git status --short`: no `*.uid` noise (gate OK).
- Headless import: **zero** SCRIPT ERROR / Parse Error / "Failed to load".
- Targeted suite `res://tests/test_dressing_road_clearance.gd`:
  **4 test cases | 0 errors | 0 failures** (green).
- Full `res://tests` suite: **NOT yet re-run** (attempt aborted; needs a fresh
  `--headless --import .` pass first, then the `-s GdUnitCmdTool.gd
  --ignoreHeadlessMode -a res://tests` run per AGENTS.md).

## What changed in this session (before the fix)
- `tests/test_dressing_road_clearance.gd`: test (b) assertion point moved
  `(210,0,12)` -> `(310,0,12)` (beyond segment endpoint, dist ~15.62 >= 13);
  world-offset test now `add_child(scatterer)` before generate and reads
  `scatterer.to_global(p)`; `is_greater_or_equal` -> `is_greater_equal`.
- `scripts/world/foliage.gd`, `scripts/world/prop_scatterer.gd`: `_world_pos()`
  uses local `transform` fallback when off-tree (killed 700+ "is_inside_tree"
  error spam).
- These earlier edits: **all green** in the targeted run along with the fixes.

## Next steps (for later sessions)
1. Re-run full suite (AGENTS.md order: probe pass, then gdUnit) and confirm
   `Overall Summary:` green with the expected count.
2. Drop leftover `git stash@{0}` AFTER green (`git stash drop stash@{0}`).
3. Delete `_diag_frames.gd`, `_diag_tree.gd`, `_diag_foliage.gd`,
   `_diag_mm.gd`, `_diag_api.gd` diag scripts from the project root; remove
   `_gdunit_*.txt` / `_diag_*.txt` scratch logs.
4. Do not commit anything unless explicitly asked.

## Notes for future debugging
- `MultiMesh` in this build exposes `buffer`, `transform_array`,
  `transform_2d_array` (NOT `instance_transform`); `get_instance_transform`
  exists but the CPU array never reflects it headless.
- Order matters if a MultiMesh is rebuilt: set `transform_format` BEFORE
  `instance_count` ("Instance count must be 0 to change the transform format").
- GDUnit: use `is_greater_equal`, not `is_greater_or_equal` (nonexistent).