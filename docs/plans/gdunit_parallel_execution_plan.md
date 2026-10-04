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
**Cons:** N× Godot startup cost (~3s each), N× the RAM/CPU for the scene tree — *not* VRAM, headless uses the dummy rendering driver

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

1. **GitHub Actions matrix** — replace single job with a matrix of 4 shards.
   **Shard indices are `1..jobs`, NOT `0..jobs-1`.** Under the default
   `--isolate-user-data` mode the runner builds shards `1..jobs`, so `-j 4` means
   `[1, 2, 3, 4]`. Shard `0` is reserved for the serialized save-contention
   shard and exists ONLY under `--no-isolate-user-data`; `--shard 0` in the
   default mode exits with an error, so a `[0, 1, 2, 3]` matrix would burn a job
   on a shard that does not exist.
   ```yaml
   strategy:
     matrix:
       shard: [1, 2, 3, 4]
     fail-fast: false
   ```
   Each job runs `py tools/gdunit_parallel.py -j 4 --shard ${{ matrix.shard }}`.
   **Every matrix job MUST pass the identical `-j` AND the identical committed
   `tools/suite_weights.json`.** Shard membership is a function of both — `-j`
   decides how many bins exist, the weights file decides which suite lands in
   which bin — so a job that drifts on either runs a *different partition* and
   the merged total silently loses or double-counts suites. The runner prints
   the weights file's sha1 in its `--shard` warning precisely so CI jobs can
   compare digests and prove they matched; fail the workflow if they differ.

   **A cross-job merge cannot trust mtimes.** Merging in a follow-up job means
   `actions/download-artifact`, and downloaded files get *download-time* mtimes,
   so the runner's own staleness guard (`_xml_is_fresh`, `st_mtime` vs process
   launch with 120 s of slack) is meaningless after a download — it would accept
   a stale XML or reject a good one depending on download order. A cross-job
   merge must key on the **shard count** (all of `1..j` present) and the
   **parsed JUnit counts**, never on mtime.

2. **Dynamic sharding** — parse the previous run's actual per-suite durations
   and feed them back as shard weights. Shipped as `--write-weights` /
   `--weights-file` (see `### P1 — STATUS`); the source is the per-shard
   `results.xml` files, not the `_gdunit.txt` scratch log this item used to name.

3. **Resource limits** — cap the parallel job count on the GTX 970. **The real
   constraint is CPU and RAM, not VRAM.** `--headless` runs Godot's *dummy*
   rendering driver: the shard logs show `RendererDummy` allocations and
   `servers/rendering/dummy/storage/material_storage.cpp` frames, with zero
   Vulkan/VRAM use. The earlier "each Godot headless ~800 MB VRAM" claim in this
   plan was simply false and must never be used to reason about job counts. What
   the implementation actually ships is a `--max-jobs N` clamp on the job
   **COUNT**: it does not measure VRAM, no VRAM measurement was implemented, and
   it is not adaptive.

4. **Fail-fast coordination** — if any shard hits a *script error* (not test
   failure), cancel others. Test failures must not cancel. Shipped; see
   `### P1 — STATUS`.

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
After each full run, parse the per-shard JUnit XML — the highest
`report_<N>/results.xml` in each `<reports-root>/shard_*/` dir, which is what
`--write-weights` does:
```python
for suite in root.findall(".//testsuite"):
    name = suite.get("name")  # e.g. "test_highway_access"
    time = float(suite.get("time", 0))
    SUITE_WEIGHTS[name + ".gd"] = max(1, int(time / WEIGHT_UNIT_SECONDS))
```
`WEIGHT_UNIT_SECONDS` is **0.05** in the implementation (one weight = 0.05 s of
measured time), not the 0.5 s sketched here originally — the 0.5 s granularity
was far too coarse to balance 95 suites. Persisted to
`tools/suite_weights.json` for the next run.

### Bucketing Strategy
| Parallelism | Shards | Expected Wall Time | Real constraint |
|-------------|--------|-------------------|-----------------|
| 2 | 2 | ~9 min | CPU / RAM |
| 3 | 3 | ~6.5 min | CPU / RAM |
| **4** | **4** | **~5 min** | CPU / RAM — measured 4.18× on the GTX 970 |
| 6 | 6 | ~4 min | CPU / RAM — diminishing returns, *not* VRAM OOM |

**Recommendation:** start with `-j 4` on the GTX 970 and read
`reports/parallel/summary.json` for the actual per-shard walls. There is no VRAM
to watch: headless shards run on the dummy rendering driver and allocate none.

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

Still open: the GitHub Actions JUnit-parser validation above. P1 progress (the
matrix deferred behind two blockers; the machine-calibration blocker that was
the third is now shipped) is in `### P1 — STATUS` below.

### P1 (Next Sprint)
- [ ] GitHub Actions workflow with matrix sharding (blocked — see P1 — STATUS)
- [x] Dynamic weight update from measured durations (`--write-weights` /
      `--weights-file`) — shipped against LOCAL per-shard XML; the "from CI
      artifacts" half still needs a CI to exist
- [x] Job-count clamp (`--max-jobs N`) — supersedes the original `--max-vram`
      sketch in P1 item 3: headless allocates no VRAM, so there is nothing to
      measure and no measurement was implemented
- [ ] HTML report merge (optional: `gdunit4-test-runner` already does this)

### P1 — STATUS

Progress only — nothing below re-designs the P1 items above. The numbers come
from `reports/parallel/summary.json`, `tools/suite_weights.json` and the shard
logs; read those, not this block, which ages.

**SHIPPED — dynamic weights.** `--write-weights` parses the highest
`report_<N>/results.xml` of every `<reports-root>/shard_*` dir, sums each
`<testsuite>`'s `time` (a suite appearing in more than one shard's XML is
summed, and the shards recorded), and writes `tools/suite_weights.json`. Schema
v1: `schema`, `generated_at`, `source`, `unit_seconds` (0.05 — one weight =
0.05 s of measured time), `suites` keyed `<package>/<name>.gd` so the keys are
exactly the discovered suite paths, plus `totals`. `--weights-file` consumes it
and **overrides the `func test_` counts**; a missing or corrupt file, or a suite
with no entry, falls back to the count with a one-line notice and never crashes.
No Godot process is launched to write or read it.

  Result: shard balance went from a **4.8× spread to 1.11×**, and wall-clock
  from 264.3 s to **208.9 s**.
  - Before (count weights): `264 / 136 / 247 / 46 s`.
  - Projection from the per-suite `time` in the four existing shard XMLs (total
    648.6 s, ideal `648.6 / 4 = 162.15 s`): `162.0 / 162.1 / 162.2 / 162.2 s`.
    **The projection was roughly 23% optimistic** — see the contention note
    below. Do not trust a projection for wall-clock.
  - **MEASURED** (`-j 4`, exit 0, `1018 tests / 0 failures / 0 errors /
    20 orphans`): parallel shards `156.0 / 154.3 / 159.7 / 144.1 s`
    (spread **15.6 s**), plus a 49.2 s serialized tail. Total wall **208.9 s**
    = **5.28×** the 18m23s serial baseline, and **55.4 s (1.27×) faster** than
    the count-weighted P0 run.

  **Wall-clock contention is real and it invalidates naive projections.**
  The per-shard estimates predicted 148-150 s; measured 144-160 s. Worse, the
  weights file was itself *generated from a contended run*, so it records
  inflated per-suite times. Equalising the weights therefore equalises
  *contended* cost, not serial cost — which is the right thing to balance, but
  it means the projected total understates wall-clock by ~20-25%.

  **SHIPPED — benchmark isolation (`SERIAL_SUITES`).** `test_perf_gate.gd`
  measures wall-clock frame time, so it is meaningless under 4-way CPU
  contention. Measured contended, it reported `152-248 ms` against its 16.7 ms
  contract — **5 hard assertion failures**, exit 2. It is now excluded from the
  parallel pool and runs alone in shard 0, LAST. Isolated, it **passes** (3/3,
  `45s 330ms`, no `Expecting to be less than or equal:` line emitted). This is
  worth more than it looks: paying a 49.2 s serialized tail is still 27 s
  **faster** in total than running the benchmark contended (208.9 vs 236.1 s),
  because the contended version also inflates every other shard it shares with.
  **Any future wall-clock or throughput benchmark must be added to
  `SERIAL_SUITES`** — it is a one-line change in `tools/gdunit_parallel.py`.

**SHIPPED — exit-100 classification fix.** A shard reporting *real* failures
(gdUnit exit 100 with `failures > 0` in its own XML) was mislabelled
`!! FALSE GREEN`, conflating "red" with "untrustworthy". It now reports
`RED (n fail / m err)` and the run exits **1** (test failures); exit **2**
(false green) is reserved for genuinely untrustworthy results — no XML,
`tests == 0`, exit 100 with 0 failures *and* 0 errors, exit 103/105, timeout,
aborted, or a rejected `-a` path. The `RED` path is **now VERIFIED**: it had
never been exercised by a green run, and has since been confirmed three times,
including deliberately on the forced-`reference` run below (2 failures, runner
exit 1) — so exit 1 / exit 2 is a distinction that has been observed in both
directions rather than only asserted.

**SHIPPED — `--merge-only`.** Merges per-shard XMLs that already exist, with no
Godot launch and no import probe, through the same merge → summary →
false-green path, so the exit code and the `!! FALSE GREEN` banner mean exactly
what they mean on a real run. Verified reproducing `1018 tests / 0 failures /
0 errors / 95 suite nodes / EXIT 0` in **0.39 s**. This is the entry point for
a CI follow-up-job merge — read the `download-artifact` mtime caveat in P1
item 1 before wiring it up.

**SHIPPED — `--max-jobs N` clamp.** Clamps the job **COUNT** from above (hard
cap `-j` 1..8). It does not measure VRAM and is not adaptive — see P1 item 3.

**SHIPPED — fail-fast coordination.** Shards are now driven with
`subprocess.Popen` plus a shared abort event and a shared child registry. A
shard exiting **105** (script errors) or blowing `--timeout` trips the event,
which terminates the other live Godot children (terminate, then
`KILL_GRACE_SECONDS` = 5 s, then kill). Test FAILURES (exit 100) deliberately do
**not** trip it. Aborted shards report status `aborted (peer script error)`, are
excluded from the merge, and force a non-zero exit.

**SHIPPED — two-mode perf gate (the machine-calibration blocker).** The
assert-portability work this plan called for has landed in
`tests/suites/test_perf_gate.gd` and `scripts/bench/benchmark.gd`, so a 4-job CI
matrix is no longer red for a reason that has nothing to do with the code.
`PerfBench.CONTRACT_FRAME_BUDGET_MS` is still `16.7` ms and its VALUE is never
loosened; the GATE that enforces it is now **self-selecting** from this run's own
numbers. It engages only when the run demonstrated the box can hold 60 Hz — its
fastest SUSTAINED row (`control_ms`) at or under 16.7 ms — which is **reference**
mode, and the only mode the reference rig can ever be in. When `control_ms >
16.7` the gate enters **relative** mode and enforces only the same-run spread
control that already existed: every sustained row within `1.35x` of the fastest
sustained row of that same run, floor `1.5` ms. A `print` line
`[perf_gate] mode=... control_ms=... contract_ms=... load_budget_ms=...` records
which mode ran, and the load-window bound became
`3.0 x maxf(control_ms, contract_ms)` — exactly the old `50.1` ms in reference
mode, and still able to report "the world never settled" on a slow box instead of
masking it behind the machine's own slowness. New `ULTRADRIVE_PERF_MODE` env var
overrides the detection: `reference` forces the strict absolute gate on even
where the box cannot hold it (it will then fail, which is the point), `relative`
forces it off, unset or any other value auto-detects.
**COST, stated plainly:** in relative mode a regression that slows EVERY preset
EQUALLY is no longer detectable — only a *per-preset* regression is. The
reference rig never degrades, so it pays none of this cost.

**SHIPPED — `test_race_results.gd` timing band (a test bug, not a machine).**
This one was **not** the same class of problem as the perf gate. It asserted the
results-screen total against a `±0.05 s` band around a SECOND read of
`LapCounter.get_total_time()`, which is a live monotonic clock
(`(Time.get_ticks_msec()/1000.0) - _race_start_time`). The HUD reads that clock
once inside `RaceManager.finish_race()` and then does save-file I/O in
`_submit_best_lap` before writing the label, so the band was measuring the
test's own execution latency plus disk I/O latency, and failed only under load.
It is now an exact bracket: two clock reads taken immediately before and after
the `finish_race()` call, with the label asserted to fall between them, plus a
new `LABEL_QUANTISATION_SECONDS = 0.01` const for the label's own `mm:ss.ss`
rendering granularity (not a latency allowance). Exact on any machine at any
speed. `test_race_results.gd` is **not** a wall-clock benchmark and does **not**
belong in `SERIAL_SUITES` — its problem was fixed, not isolated.

**MEASURED on a second, non-reference box** (AMD Ryzen 3 5300U, 4c/8t, 7.3 GB
RAM, Godot `4.7.2.stable.official.ed1daf0bf`). The laptop is itself
reference-capable — headless draws nothing, so the workload is CPU-only:

| Run | Result |
|---|---|
| Default (auto) | `mode=reference control_ms=7.00 contract_ms=16.7 load_budget_ms=50.1` → 3/3 pass, 49.0 s, runner exit 0 |
| Forced `relative` | `mode=relative control_ms=7.07` → 3/3 pass, runner exit 0 |
| Simulated slower-than-reference box (contract const temporarily `0.001`, then reverted), auto | `mode=relative control_ms=7.04 contract_ms=0.0 load_budget_ms=21.1` → GREEN, runner exit 0 |
| Same box, forced `reference` | `mode=reference control_ms=6.98 contract_ms=0.0` → RED, 2 failures, runner exit 1 |
| `test_race_results.gd` alone | 8/8 pass, runner exit 0 |
| Both suites, default mode | `11 tests, 0 failures, 0 errors`, runner exit 0 |

Both the rescue and the strict gate were confirmed end to end, in both
directions of the override. This is the evidence that closes the
machine-calibration half of the CI matrix item in `### P1 (Next Sprint)` above;
it does not touch the P1 numbers above, which stay as measured on the PC.

**OPEN / BLOCKER (cold import).** `.godot/` is gitignored, so every CI job pays
a cold editor import — 313 assets, ~38.8 MB of generated cache. Four matrix
jobs would pay it four times, plausibly exceeding the entire 264 s of test time.
Mitigable with `actions/cache` keyed on `assets/**`, `addons/**`,
`project.godot`, `shaders/**` plus the runner OS.

**OPEN / BLOCKER (no precedent).** The repo has **no CI of any kind today** — no
`.github/`, no other pipeline config — so there is zero precedent here and the
whole capability is unvalidated.

**DEFERRED — GitHub Actions matrix**, for the two blockers above. Already
known-good whenever it is built:
  * `--godot <path>` fully bypasses the Windows-only `godot_path.bat`.
  * `ubuntu-latest` is viable: no drive letters, no `.bat`/`.exe` calls and no
    `APPDATA` dependency anywhere in the 96 suite files.
  * Per-shard `results.xml` lands at a predictable path and `merge_junit` is
    already path-agnostic.
  * Assets are only 21.4 MB.
  * No secrets and no extra permissions are required.
  * `APPDATA`-based `user://` isolation is **Windows-only**, so it no-ops on a
    Linux runner. Harmless in a matrix: each job is its own machine with its own
    filesystem.

The P0 checklist item "verify merged `results.xml` passes GitHub Actions JUnit
parser" stays **unticked** — that validation has not happened.

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

# Single shard (for debugging) — indices are 1..j, so this is shard 1
python tools/gdunit_parallel.py -j 1 --shard 1

# CI: run one shard. -j must match the matrix, and the weights file must match too.
py tools/gdunit_parallel.py -j 4 --shard 2
```

---

## Risks & Mitigations

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| CPU/RAM exhaustion with 4× processes | Medium | High | Headless shards allocate no VRAM; clamp the count with `--max-jobs`, fall back to `-j 2` |
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