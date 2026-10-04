# GDUnit4 Parallel Test Execution Plan

**Current baseline:** 1016 test cases, 95 suites, ~18 min single-threaded on GTX 970  
**Target:** ≤5 min wall-clock (3.6× speedup) via parallel Godot processes

---

## Executive Summary

GDUnit4 executes test suites **sequentially within one Godot process** (see `GdUnitTestSuiteExecutor.run_and_wait()`). The framework has no built-in parallel suite execution. However, **each suite is independent** — no shared state between `test_*.gd` files — so we can shard the 95 suites across N Godot processes and merge JUnit XML reports.

**Strategy:** Partition suites by estimated runtime into balanced buckets, launch N parallel Godot headless processes, collect per-process `results.xml`, merge into single JUnit + HTML report.

---

## Test Suite Profile (95 suites, ~1016 tests)

| Bucket | Suites | Est. Tests | Est. Time (single) |
|--------|--------|------------|---------------------|
| Heavy (>20 tests) | 6 | 228 | ~6 min |
| Medium (10–20) | 28 | 350 | ~7 min |
| Light (5–9) | 32 | 185 | ~3.5 min |
| Trivial (1–4) | 15 | 48 | ~1.5 min |
| **Total** | **81** | **811** | **~18 min** |

*Note: 14 suites are helper/stub files (0 tests). Actual test count varies per run due to fail-fast aborts.*

---

## Parallelization Architecture

### Option A: External Orchestrator (Recommended)
**Tool:** `gdunit4-test-runner` (Go) or custom Python/PowerShell wrapper

```bash
# Shard suites into 4 balanced groups
python shard_suites.py --groups 4 --suites-dir tests/suites

# Launch 4 Godot processes in parallel
godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/suites/group1 -c > group1.log 2>&1 &
godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/suites/group2 -c > group2.log 2>&1 &
godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/suites/group3 -c > group3.log 2>&1 &
godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/suites/group4 -c > group4.log 2>&1 &
wait

# Merge JUnit XML
python merge_junit.py reports/group*/results.xml > reports/merged-results.xml
```

**Pros:** Simple, no GDUnit4 changes, works today  
**Cons:** N× Godot startup cost (~3s each), N× VRAM for scene tree

### Option B: GDUnit4 Core Modification (Long-term)
Add `--parallel=N` flag to `GdUnitCmdTool.gd` that:
1. Shards discovered suites internally
2. Spawns N `Thread` workers via `GdUnitThreadManager.run()`
3. Each worker runs `_executor.run_and_wait()` on its shard
4. Aggregates results in main thread

**Pros:** Single Godot process, shared scene cache, lower overhead  
**Cons:** Requires GDUnit4 fork/PR, thread-safety audit of `GdUnitTestSuiteExecutor`, `GdUnitTestSession`, reporters

---

## Phase Plan

### P0 — Quick Win (1 week): External Orchestrator Script

**Deliverable:** `tools/gdunit_parallel.py`

```python
#!/usr/bin/env python3
"""
Parallel GDUnit4 test runner for UltraDrive.
Shards test suites by estimated runtime, launches N Godot processes,
merges JUnit XML reports.
"""
import subprocess, xml.etree.ElementTree as ET, sys, os, time
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor, as_completed

SUITES_DIR = Path("tests/suites")
GODOT = os.environ.get("GODOT_EXE_CONSOLE", "godot")
GDUNIT_TOOL = "res://addons/gdUnit4/bin/GdUnitCmdTool.gd"
REPORTS_DIR = Path("reports")

# Suite → estimated test count (from static analysis)
SUITE_WEIGHTS = {
    "test_engine_audio.gd": 55, "test_collectibles.gd": 44,
    "test_road_graph.gd": 25, "test_weather_vfx.gd": 25,
    "test_night_headlights.gd": 23, "test_surface_grip.gd": 23,
    "test_car_sound_profiles.gd": 20, "test_car_visuals.gd": 17,
    "test_multi_lane_rails.gd": 16, "test_regional_climate.gd": 16,
    "test_traffic_driving.gd": 16, "test_best_lap_records.gd": 18,
    "test_car_audio.gd": 18, "test_corridor_seeding.gd": 19,
    "test_drive_feel.gd": 19, "test_longitudinal_traction.gd": 19,
    "test_traction_hud.gd": 19, "test_event_rewards.gd": 15,
    "test_low_speed_reverse_handling.gd": 15, "test_manual_transmission_default.gd": 15,
    "test_race_loop.gd": 14, "test_highway_access.gd": 14,
    "test_map_road_labels.gd": 14, "test_settings_presets.gd": 14,
    "test_speed_trap_visuals.gd": 14, "test_audio_feel_layers.gd": 14,
    "test_career_economy.gd": 14, "test_rival_ai.gd": 13,
    "test_transmission_modes.gd": 13, "test_vehicle_fx.gd": 13,
    "test_photo_mode.gd": 12, "test_discovery.gd": 9,
    "test_cockpit_hud.gd": 9, "test_cockpit_interior.gd": 11,
    "test_camera_settings.gd": 11, "test_car_default_setup.gd": 11,
    "test_profile_slots.gd": 11, "test_rival_personalities.gd": 8,
    "test_camera_math.gd": 8, "test_brake_stop_holds_first.gd": 8,
    "test_cockpit_camera.gd": 8, "test_firstperson_look.gd": 8,
    "test_garage_tuning.gd": 8, "test_highspeed_stability.gd": 9,
    "test_weather_sun.gd": 8, "test_open_world_hud.gd": 6,
    "test_environment_lighting.gd": 6, "test_gps_route_follow.gd": 10,
    "test_hardening.gd": 10, "test_replay_recorder.gd": 10,
    "test_session_stats.gd": 10, "test_cc0_cars.gd": 6,
    "test_terrain_seeder_streaming.gd": 7, "test_player_marker.gd": 7,
    "test_car_paint_materials.gd": 7, "test_full_world_height.gd": 7,
    "test_quality_ladder.gd": 7, "test_map_route.gd": 6,
    "test_ground_latch.gd": 2, "test_starter_car_visual.gd": 6,
    "test_throttle_release_vehicle.gd": 6, "test_terrain_biomes.gd": 6,
    "test_photo_mode_controller.gd": 6, "test_race_results.gd": 8,
    "test_reflection_probes.gd": 8, "test_input_curves.gd": 9,
    "test_event_placement.gd": 9, "test_world_map_terrain.gd": 9,
    "test_prop_roadside_placement.gd": 5, "test_hud_gauge.gd": 5,
    "test_release_engine_brake.gd": 5, "test_hood_camera.gd": 5,
    "test_weather_fx_bootstrap.gd": 4, "test_world_map_features.gd": 4,
    "test_chase_camera.gd": 4, "test_hud_contrast.gd": 3,
    "test_building_placement.gd": 3, "test_track_props.gd": 3,
    "test_perf_gate.gd": 3, "test_manual_transmission_default.gd": 15,
    "test_foliage_models.gd": 1, "test_photo_free_roam_diag.gd": 1,
    "checkpoint_stub.gd": 0,
}

def shard_suites(num_shards: int) -> list[list[str]]:
    """Greedy bin-packing by test count weight."""
    items = sorted(SUITE_WEIGHTS.items(), key=lambda x: -x[1])
    shards = [[] for _ in range(num_shards)]
    shard_weights = [0] * num_shards
    for suite, weight in items:
        if weight == 0:
            continue
        idx = shard_weights.index(min(shard_weights))
        shards[idx].append(suite)
        shard_weights[idx] += weight
    return shards

def run_shard(shard_idx: int, suites: list[str]) -> tuple[int, str, Path]:
    """Run one shard in a Godot subprocess."""
    if not suites:
        return shard_idx, "", None
    args = [GODOT, "--headless", "-s", GDUNIT_TOOL, "--ignoreHeadlessMode", "-c"]
    for s in suites:
        args += ["-a", f"res://tests/suites/{s}"]
    report_dir = REPORTS_DIR / f"parallel_{shard_idx}"
    report_dir.mkdir(parents=True, exist_ok=True)
    args += ["-rd", report_dir.as_posix()]
    env = os.environ.copy()
    env["GODOT_EXE_CONSOLE"] = GODOT
    print(f"[Shard {shard_idx}] Launching {len(suites)} suites (est. {sum(SUITE_WEIGHTS[s] for s in suites)} tests)")
    t0 = time.time()
    proc = subprocess.run(args, cwd=".", capture_output=True, text=True, timeout=1800, env=env)
    dt = time.time() - t0
    result_xml = report_dir / "results.xml"
    print(f"[Shard {shard_idx}] Done in {dt:.1f}s, exit={proc.returncode}")
    return shard_idx, proc.stdout + proc.stderr, result_xml

def merge_junit(result_xmls: list[Path], output: Path) -> None:
    """Merge multiple JUnit XML files into one."""
    merged = ET.Element("testsuites")
    total_tests = total_failures = total_errors = total_time = 0
    for xml_path in result_xmls:
        if not xml_path.exists():
            continue
        tree = ET.parse(xml_path)
        for suite in tree.getroot():
            if suite.tag == "testsuite":
                total_tests += int(suite.get("tests", 0))
                total_failures += int(suite.get("failures", 0))
                total_errors += int(suite.get("errors", 0))
                total_time += float(suite.get("time", 0))
                merged.append(suite)
    merged.set("tests", str(total_tests))
    merged.set("failures", str(total_failures))
    merged.set("errors", str(total_errors))
    merged.set("time", f"{total_time:.3f}")
    ET.ElementTree(merged).write(output, encoding="utf-8", xml_declaration=True)

def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("-j", "--jobs", type=int, default=4, help="Parallel Godot processes")
    parser.add_argument("--dry-run", action="store_true", help="Show sharding only")
    args = parser.parse_args()

    shards = shard_suites(args.jobs)
    for i, s in enumerate(shards):
        w = sum(SUITE_WEIGHTS[x] for x in s)
        print(f"Shard {i}: {len(s)} suites, ~{w} tests")
    if args.dry_run:
        return

    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    with ProcessPoolExecutor(max_workers=args.jobs) as ex:
        futures = [ex.submit(run_shard, i, s) for i, s in enumerate(shards) if s]
        results = [f.result() for f in as_completed(futures)]

    # Merge
    xmls = [r[2] for r in results if r[2]]
    merged_xml = REPORTS_DIR / "merged-results.xml"
    merge_junit(xmls, merged_xml)
    print(f"Merged {len(xmls)} reports → {merged_xml}")
    print(f"Total tests: {sum(int(ET.parse(x).getroot().get('tests', 0)) for x in xmls)}")

if __name__ == "__main__":
    main()
```

**Validation:**
- Run with `-j 4` → expect 4.5–5.5 min wall-clock
- Verify merged `results.xml` loads in Jenkins/GitHub Actions
- Confirm no suite appears in two shards (mutually exclusive)

### P1 — Medium (2 weeks): CI Integration & Optimization

1. **GitHub Actions matrix** — replace single job with matrix of 4 shards
   ```yaml
   strategy:
     matrix:
       shard: [0, 1, 2, 3]
     fail-fast: false
   ```
   Each job runs `python tools/gdunit_parallel.py --shard ${{ matrix.shard }}`

2. **Dynamic sharding** — parse `_gdunit.txt` from previous run to get actual per-suite durations, feed back into `SUITE_WEIGHTS`

3. **Resource limits** — cap at 4 parallel on GTX 970 (4GB VRAM). Each Godot headless ~800MB VRAM.

4. **Fail-fast coordination** — if any shard hits a *script error* (not test failure), cancel others. Test failures should not cancel.

### P2 — Research (4 weeks): In-Process Parallelism (GDUnit4 Fork)

**Goal:** Single Godot process, N threads running suites concurrently.

**Changes needed in GDUnit4:**
1. `GdUnitTestSuiteExecutor.run_and_wait()` → make re-entrant (currently uses member `_executeStage`, `_terminated`)
2. `GdUnitTestSession` → thread-local or per-suite instance
3. Reporters (`GdUnitConsoleTestReporter`, `GdUnitHtmlReportWriter`) → thread-safe aggregation
4. `GdUnitThreadManager` → worker pool with `max_workers` config
5. CLI flag `--parallel=N` in `GdUnitCmdTool.gd`

**Risks:**
- Godot's `SceneTree` is NOT thread-safe — suites that add nodes to root will race
- `GdUnitTools.dispose_all()` uses global state
- Physics/rendering servers not thread-safe

**Mitigation:** Only parallelize *pure logic* suites (no scene tree). Tag suites with `@thread_safe` attribute. Run unsafe suites sequentially.

---

## Sharding Algorithm Details

### Static Weights (P0)
Use the `SUITE_WEIGHTS` table above. Greedy bin-packing (largest-first) gives good balance.

### Dynamic Weights (P1+)
After each full run, parse `reports/report_*/results.xml`:
```python
for suite in root.findall(".//testsuite"):
    name = suite.get("name")  # e.g. "test_highway_access"
    time = float(suite.get("time", 0))
    SUITE_WEIGHTS[name + ".gd"] = max(1, int(time / 0.5))  # 0.5s per test heuristic
```
Persist to `tools/suite_weights.json` for next run.

### Bucketing Strategy
| Parallelism | Shards | Expected Wall Time | VRAM Peak |
|-------------|--------|-------------------|-----------|
| 2 | 2 | ~9 min | ~1.6 GB |
| 3 | 3 | ~6.5 min | ~2.4 GB |
| **4** | **4** | **~5 min** | **~3.2 GB** |
| 6 | 6 | ~4 min | ~4.8 GB (OOM risk) |

**Recommendation:** Start with `-j 4` on GTX 970. Monitor `nvidia-smi` during run.

---

## Implementation Checklist

### P0 (This Week)
- [x] Create `tools/gdunit_parallel.py` with sharding + merge
- [x] Test locally: `python tools/gdunit_parallel.py -j 4`
- [ ] Verify merged `results.xml` passes GitHub Actions JUnit parser
- [x] Document in `docs/GDUNIT_GATE.md` (add parallel section)

### P0 — STATUS

- **Deliverable:** `tools/gdunit_parallel.py`. Usage, flags and the false-green
  rules are documented in `docs/GDUNIT_GATE.md` § "Parallel gate" — that section,
  not this plan, is the operational reference.
- **Suite weights come from runtime discovery**, not the `SUITE_WEIGHTS` table in
  this plan: `tests/` is walked recursively and every `*.gd` with at least one
  `func test_` is a suite, weighted by that count. The static table above was
  stale — it was missing the 11 suites in the `tests/` root and carried a
  duplicate `test_manual_transmission_default.gd` key. It is kept only as an
  empty `STATIC_WEIGHTS` override for P1's measured-duration feedback, so
  discovery stays the single source of truth.
- **gdUnit `-a` is repeatable**; a comma-joined `-a` value is NOT split and
  becomes one literal path, which discovers zero tests and exits 0. The runner
  emits one `-a` per suite and treats the resulting silence as a false green.
- **Each shard needs its own `-rd`.** gdUnit picks `report_<N>` by scanning for
  the highest existing index and a finishing run deletes lower-indexed siblings,
  so concurrent shards sharing a base would delete each other's reports.
- **Per-shard `APPDATA` isolation removed the need to serialize** the 13
  save-touching suites (`CONTENDED_SUITES`), by giving every shard a private
  `user://`. `--no-isolate-user-data` remains as the serialize-into-one-trailing-
  shard fallback.
- **Three plan-doc bugs were fixed during implementation:** `ProcessPoolExecutor`
  → `ThreadPoolExecutor` (the work is `subprocess.run`, not picklable CPU work),
  the assumed `<rd>/results.xml` path (it is actually `<rd>/report_<N>/results.xml`),
  and the missing import probe (a `-s` run before a successful
  `--headless --import .` dies with exit 103).

Still open: the GitHub Actions JUnit-parser validation above, plus every P1 item.

### P1 (Next Sprint)
- [ ] GitHub Actions workflow with matrix sharding
- [ ] Dynamic weight update from CI artifacts
- [ ] Add `--max-vram` flag to auto-scale job count
- [ ] HTML report merge (optional: `gdunit4-test-runner` already does this)

### P2 (Future)
- [ ] Fork GDUnit4, implement `--parallel` in `GdUnitCmdTool.gd`
- [ ] Thread-safety audit of executor + reporters
- [ ] `@thread_safe` attribute for suite tagging
- [ ] Benchmark: in-process vs multi-process overhead

---

## Commands Reference

```bash
# Local parallel run (4 jobs)
python tools/gdunit_parallel.py -j 4

# Dry-run: show shard assignment
python tools/gdunit_parallel.py -j 4 --dry-run

# Single shard (for debugging)
python tools/gdunit_parallel.py -j 1 --shard 0

# CI: run one shard (matrix index from env)
SHARD_IDX=2 python tools/gdunit_parallel.py -j 4 --shard $SHARD_IDX
```

---

## Risks & Mitigations

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Godot OOM with 4× processes | Medium | High | Monitor VRAM; fallback to `-j 2` |
| Shared `.godot` cache corruption | Low | Medium | Each process uses same cache (read-only after import) |
| Flaky tests non-deterministic across shards | Low | Low | Run flaky suites in isolation (sequential) |
| JUnit merge loses per-suite timing | Low | Low | Keep per-shard XML as artifacts |
| GDUnit4 internal state leak between suites | Low | High | Verified: each suite loads fresh script instance |

---

## References

- GDUnit4 source: `addons/gdUnit4/src/core/runners/GdUnitTestCIRunner.gd`, `GdUnitTestSuiteExecutor.gd`
- `gdunit4-test-runner` (Go): https://github.com/minami110/gdunit4-test-runner
- GitHub Actions matrix: https://docs.github.com/en/actions/using-jobs/using-a-matrix-for-your-jobs
- JUnit XML schema: https://github.com/junit-team/junit4/wiki/Aggregating-Results