# HANDOFF — GDUnit4 parallel gate (P1)

**Status at handoff:** P1 implemented, validated GREEN, and committed. Nothing
is left half-done. CI is still not written, but it is no longer blocked on
assert portability — both machine-calibrated/timing-band blockers are resolved
(§6). What remains is cold import and having no CI precedent to copy.

- Repo: `https://github.com/shakedZeira/UltraDrive.git`, branch `master`
- Working dir on this machine: `D:\AI Projects\UltraDrive`
- Engine: Godot **4.7.2.stable.official.ed1daf0bf**

---

## 1. What this work is

The GDUnit4 suite takes ~18 minutes serially on this box (GTX 970). It now runs
as N concurrent headless Godot processes.

| Configuration | Wall | vs serial |
|---|---|---|
| Serial baseline | 18m23s (1103 s) | 1.00x |
| P0 — count-weighted sharding (`3544b94`) | 4m24s (264.3 s) | 4.18x |
| P1 — measured weights + isolated benchmark (`5840ebd`) | 3m29s (208.9 s) | 5.28x |
| **P1 verified — weights re-measured after `794a199`** | **3m26s (206.4 s)** | **5.34x** |

The current row is the one to trust: two consecutive full `-j 4` runs after
upstream `794a199` made the two wall-clock suites machine-portable were both
`exit 0`, `1018 tests / 0 failures / 0 errors / 20 orphans`, 95/95 suites, with
`test_perf_gate.gd` passing 3/3 alone in serialized shard 0 under the **strict
absolute** gate (`mode=reference control_ms=8.42` and `6.97` vs the 16.7 ms
contract) — not the relative fallback.

**How to run it:**

```
py tools\gdunit_parallel.py -j 4
```

Exit codes: `0` clean, `1` test failures, `2` false green / environment problem.

---

## 2. The single most important lesson

**A wall-clock benchmark cannot be measured on a CPU that 3 other Godot
processes are saturating.**

`tests/suites/test_perf_gate.gd` asserts a frame-budget contract of 16.7 ms.
Run inside a parallel shard it measured **152-248 ms** — five hard assertion
failures, exit 2, and a genuinely red suite that was *not* a real regression.
Run alone on an idle CPU it **passes** (3/3, `45s 330ms`).

It is now in `SERIAL_SUITES` and runs by itself in shard 0, LAST.

```
SERIAL_SUITES: set[str] = {
    "test_perf_gate",
}
```

**Any future wall-clock, throughput, FPS or perf-budget suite must be added to
that set.** It is a one-line change in `tools/gdunit_parallel.py`.

Isolating it also made the run *faster overall* (208.9 s vs 236.1 s contended),
because a benchmark contending with 30 other suites inflates all of them too.

Two supporting facts, both measured:

- **4-way contention inflates per-shard wall ~10%** over the sum of its suites'
  own reported `time`. Weights equalise *contended* cost, which is the right
  thing to balance, but it means any projection from XML `time` understates
  wall-clock by roughly 20-25%. The projection said 162 s/shard; reality was
  144-160 s. **Do not quote a projection as a measurement.**
- **`test_open_world.gd` alone is ~150 s** and is now its own shard, so shard 1
  holds exactly one suite. That is correct, not a bug: it is the critical path
  and nothing can be done to shorten it without touching that suite.

---

## 3. What shipped in P1

All in `tools/gdunit_parallel.py`, plus generated `tools/suite_weights.json`:

- `--write-weights` — parses the highest `report_<N>/results.xml` under each
  `<reports-root>/shard_*` dir and writes measured per-suite durations. Launches
  no Godot process. Schema v1, `unit_seconds` 0.05.
- `--weights-file PATH` — defaults to `tools/suite_weights.json`. Overrides
  `func test_` counts. A missing/corrupt file, or a suite with no entry, falls
  back to the count with a one-line notice and never crashes.
- `--merge-only` — merges XMLs that already exist, no Godot launch, no import
  probe, through the same merge/summary/false-green path. This is the entry
  point for a CI follow-up-job merge.
- `--max-jobs N` — clamps job count (hard cap `-j 1..8`). Not adaptive.
- `SERIAL_SUITES` — benchmark isolation (above).
- **Fail-fast coordination** via `Popen` + a shared abort event and child
  registry. Only exit `105` (script errors) or `--timeout` trips the event; a
  suite *failure* does not abort its peers. Aborted peers are excluded from the
  merge rather than merged as failures.
- **exit-100 classification fix.** A shard with real failures (gdUnit exit 100
  with `failures > 0` in its own XML) used to be mislabelled `!! FALSE GREEN`.
  It now reports `RED (n fail / m err)` and exits **1**. Exit **2** is reserved
  for genuinely untrustworthy results: no XML, `tests == 0`, exit 100 with 0
  failures *and* 0 errors, exit 103/105, timeout, aborted, rejected `-a` path.

Shard balance improved from a 4.8x spread to **1.08x**:
`153.7 / 149.9 / 155.7 / 140.1 s` parallel + `50.7 s` serialized tail.

**Do not try to improve this further.** The parallel pool is
`608.9 − 46.7 = 562.2 s` over 4 shards (ideal `140.6 s`) and the worst shard is
`148.8 s`, so packing is within ~6% of optimal. Raising `-j` changes nothing —
`test_open_world.gd` alone is 148.8 s and caps the parallel max regardless —
and splitting that suite test-by-test would make the makespan *worse*
(~152 s), because isolating it is already the best assignment.

---

## 4. Environment rules — read before running anything

These are hard-won and repeatedly violated. They live in `AGENTS.md`; the
short version:

1. **D: drive only. Never use C: at all.** Every headless or parallel Godot
   run must have `APPDATA` set to an ABSOLUTE path under
   `D:\AI Projects\UltraDrive\reports\parallel\userdata\shard_N`, because
   `user://` otherwise resolves to `%APPDATA%\Godot\app_userdata\<project>` on
   C:. A **relative** `APPDATA` silently resolves against the child CWD — always
   pass an absolute path. This is what makes per-shard save isolation possible
   and is why the 13 save-touching suites no longer need serializing.
2. **The shell is cmd.exe, not bash** (on the PC — see §8, the laptop is
   PowerShell 5.1). No `head`, `tail`, `cat`, `grep`, `ls`, `wc`, `sed`, `awk`,
   or `&&` after a pipe. Use `findstr /c:"pat" <ABSOLUTE path>`, `type`, `dir`,
   or wrap PowerShell as `powershell -NoProfile -Command "..."`. `findstr`
   silently reports `Cannot open` on relative paths — always pass absolute ones.
   Use the `workdir` parameter, never `cd`.
3. **Use `py`.** `python`/`python3` are WindowsApps Store stubs and do nothing.
   On the laptop there is not even a `py` launcher — §8 has the interpreter.
4. **Never use the GUI Godot binary headless.** `Godot_v4.7.2-stable_win64.exe`
   is a WINDOWS_GUI-subsystem PE: under `&` it *detaches*, does not wait, and
   writes nothing — while still reporting success. This produced two false
   greens in a row (an `--import` probe "passing" in 8 ms, and a 0-byte
   `_gdunit.txt`). Always `godot_path.bat` -> `%GODOT_EXE_CONSOLE%`.
5. **One Godot process at a time**, with exactly one exception: the parallel
   runner launches N at once and must never run beside another Godot process or
   another gate run.
6. Artifacts go to `reports/parallel/` (gitignored). No temp/system dirs.

---

## 5. GDUnit CLI facts this depends on — do not re-derive

- `-a` is **repeatable** and accumulates. Comma-joined paths are **not** split:
  six comma-joined suites print `Given directory or file does not exists:` and
  then **exit 0 having run nothing**. One `-a` per suite.
- **Every shard must get its own `-rd`.** gdUnit picks `report_<N>` by scanning
  the base dir for the highest index, and a finishing shard recursively DELETES
  lower-indexed siblings — a shared `-rd` interleaves reports and deletes live
  ones.
- `results.xml` is written per report dir, so merging is real. Output lands at
  `<rd>\report_<N>\results.xml`.
- Exit `101` = orphans only. That is **success-with-warning**; the baseline has
  20 orphans. Do not chase it.
- `-c` (continue after failure) is passed by default. Without it a suite aborts
  at its **first** failure and the "Executed test cases" denominator drops below
  the `func test_` count in the file — a suite reporting 16 of 19 defined cases
  is an ABORT, not a pass.
- gdUnit treats GDScript warnings as errors: `var x := f()` fails to load when
  `f()` returns `Variant`. Its `is_equal_approx` on a vector needs a same-type
  approx arg, not a float.

---

## 6. Open item: CI is deliberately deferred

An assessment was done. **No workflow was written**, because it would be red on
arrival — but two of the three original blockers are now **resolved in the
tree**, and both were re-measured on a second, non-reference machine (§8). CI is
unblocked on the assert-portability front.

**Resolved:**

1. `tests/suites/test_perf_gate.gd` no longer asserts a bare **16.7 ms**
   against the wall clock. `PerfBench.CONTRACT_FRAME_BUDGET_MS` is still `16.7`
   and its **value is never loosened** — but the **gate** that enforces it is now
   self-selecting. It engages only when this same run demonstrated the box can
   hold 60 Hz, i.e. its fastest SUSTAINED row (`control_ms`) came in at or under
   16.7 ms. That is **reference** mode, and it is the only mode the reference rig
   can ever be in. When `control_ms > 16.7` the gate enters **relative** mode and
   enforces only the same-run spread control that already existed: every
   sustained row within `1.35x` of the fastest sustained row *of that run*, floor
   `1.5` ms — which is meaningful at any machine speed, because headless draws
   nothing, so Low/Medium/High run the identical CPU workload and any spread
   between them is drift or a per-preset regression, never a legitimate saving.
   A `print` line
   `[perf_gate] mode=... control_ms=... contract_ms=... load_budget_ms=...`
   records which mode ran. The load-window bound is now
   `3.0 x maxf(control_ms, contract_ms)`, so "the world never settled" stays
   detectable on a slow box; in reference mode that evaluates to exactly the old
   `50.1` ms. `ULTRADRIVE_PERF_MODE=reference` forces the strict absolute gate on
   even where the box cannot hold it (it will then fail, deliberately),
   `=relative` forces it off, unset auto-detects.
   **The tradeoff, stated honestly:** in relative mode a regression that slows
   **every** preset *equally* is no longer detectable — only a *per-preset*
   regression is. The reference rig never degrades, so it pays none of this cost.
2. `tests/suites/test_race_results.gd` was **not** a calibration problem — it was
   a genuine test bug. It asserted the results-screen total against a `±0.05 s`
   band around a *second* read of `LapCounter.get_total_time()`, which is a live
   monotonic clock
   (`(Time.get_ticks_msec()/1000.0) - _race_start_time`). The HUD reads that clock
   once inside `RaceManager.finish_race()` and then does save-file I/O in
   `_submit_best_lap` before writing the label, so the band was measuring the
   test's own execution latency plus disk I/O latency and failed only under load.
   It is now an exact bracket: two clock reads taken immediately before and after
   the `finish_race()` call, with the label asserted to fall between them (plus
   `LABEL_QUANTISATION_SECONDS = 0.01` for the label's own `mm:ss.ss` rendering
   granularity). Exact on any machine at any speed. It is **not** a wall-clock
   benchmark and does **not** belong in `SERIAL_SUITES` — its problem was fixed,
   not isolated.

**Still open:**

3. `.godot/` import cache is ~38.7 MB and 313 assets would import cold on every
   runner. Needs a cache strategy.
4. **No precedent.** The repo has no CI of any kind today — no `.github/`, no
   other pipeline config — so the whole capability is unvalidated.

When these are settled: build the matrix from `[1, 2, 3, 4]` — **not** `[0, 1,
2, 3]`; shard 0 is the serialized benchmark tail and is not a matrix shard.
Feed artifacts through `--merge-only`. Read the `download-artifact` mtime
caveat in P1 item 1 of the plan first. Note headless allocates no meaningful
VRAM, so the plan's earlier VRAM rationale for shard count was wrong and has
been corrected.

---

## 7. Files

| File | Role |
|---|---|
| `tools/gdunit_parallel.py` | The runner. Sharding, weights, isolation, merge, false-green detection. |
| `tools/suite_weights.json` | Generated per-suite durations. **Regenerate after any suite is added/removed or becomes much slower** — `-j 4` will silently misbalance otherwise. |
| `docs/plans/gdunit_parallel_execution_plan.md` | Full plan, `P1 — STATUS` block holds the measured numbers. |
| `docs/GDUNIT_GATE.md` | Operator-facing flags and false-green rules. |
| `AGENTS.md` | Project-wide agent rules; P0 baseline + parallel-gate section. |
| `reports/parallel/` | Gitignored: per-shard HTML+XML, `logs/`, `userdata/`, `merged-results.xml`, `summary.json`. |

---

## 8. Second rig — the laptop (measured) and two environment gotchas

Everything above was measured on the PC (GTX 970). The perf gate was then
validated on a **second, much slower machine**, because "does the gate work on a
box that is not the reference box?" is exactly the question a CI runner asks.

**Laptop:** AMD Ryzen 3 5300U, 4c/8t, 7.3 GB RAM, Godot
`4.7.2.stable.official.ed1daf0bf`. Checkout at
`C:\Users\IMOE001\Desktop\Shaked Projects\UltraDrive\UltraDrive`.

| Run | Result |
|---|---|
| Default (auto) | `[perf_gate] mode=reference control_ms=7.00 contract_ms=16.7 load_budget_ms=50.1` -> 3/3 pass, 49.0 s, runner exit 0 |
| Forced relative | `mode=relative control_ms=7.07` -> 3/3 pass, runner exit 0 |
| Simulated slower-than-reference box (contract const temporarily `0.001`, then reverted), auto | `mode=relative control_ms=7.04 contract_ms=0.0 load_budget_ms=21.1` -> GREEN, runner exit 0 |
| Same box, forced `reference` | `mode=reference control_ms=6.98 contract_ms=0.0` -> RED, 2 failures, runner exit 1 |
| `test_race_results.gd` alone | 8/8 pass, runner exit 0 |
| Both suites together, default mode | `11 tests, 0 failures, 0 errors`, runner exit 0 |

Note the laptop is *reference-capable* despite being the slow box: headless
draws nothing, so the workload is CPU-only and `control_ms` is ~7 ms against the
16.7 ms contract. The two simulated-slow-box rows are the ones that matter — the
rescue and the strict gate were both confirmed end to end, the
`ULTRADRIVE_PERF_MODE` override works in both directions, and the runner's
exit-1 `RED` path was exercised for real (it had never been reached by a green
run before; it is now confirmed three times).

### Gotcha: no `py` launcher on the laptop

On the MAIN PC the runner is invoked with `py tools\gdunit_parallel.py`. On the
laptop `py` is **not installed**, and `python`/`python3` resolve to the
WindowsApps Store stubs that silently do nothing — a runner invocation that
returns instantly and runs nothing. The working interpreter is:

```
C:\Users\IMOE001\AppData\Local\Microsoft\WindowsApps\PythonSoftwareFoundation.Python.3.13_qbz5n2kfra8p0\python.exe
```

Real CPython 3.13.14. `tools/gdunit_parallel.py` is pure stdlib, so there is
nothing to `pip install`.

### Gotcha: the laptop shell is PowerShell 5.1, not cmd.exe

`AGENTS.md` used to claim the shell is cmd.exe. That is true on the PC only. The
laptop shell is **PowerShell 5.1**: there is no `&&`, and no `head`/`tail`/`cat`/
`ls`/`grep` either. Use the `read` / `grep` / `glob` / `edit` tools, or
PowerShell's own `Get-Content` / `Get-ChildItem` / `Select-String`. §4 rules 2 and
3 above are the PC's; this is the laptop's.

`HANDOFF.md` at the repo root is an **older, unrelated** handoff (spawn-highway
ramp / per-segment rails, with a user-requested task still pending). It was
left untracked and untouched. The next agent should read it before touching
`corridor_planner.gd` / rails.
 
## 9. FH5 optimization pass 2026-10-05 - optimization follow-up after the gate work

Branch `master`, all commits below **pushed** unless noted. Full detail and
measured tables live in `docs/plans/fh5_optimization_plan.md`.

### 9.1 What shipped

| Commit | Change |
|---|---|
| `333b472` | Plan correction: **9 `RenderingServer` methods in the FH5 plan do not exist**; FidelityFX class absent; FSR2 already shipped in `7ffb524` |
| `13454c0` | Per-preset shadow ladder (Low 1 split/20 m, Medium 2/50 m, High 4/100 m + fade/opacity). Low **32.1 -> 78.6 fps (2.45x)**; +15 tests in `test_shadow_ladder.gd` |
| `77757cc` | Measured real baseline at 1080p on the GTX 970, replacing stale numbers |
| `5bf60ce` | High disables SDFGI: **41.7 -> 73.3 fps**, VRAM 1182 -> 777 MB |
| `493be14` | Fixed a gate error I introduced (see 9.3) |
| `aeae8a1` | `perf_probe.gd` prints active body count + physics share |
| `7202c88` | Plan: recorded the CPU-bound finding, dropped the dead GPU items |
| (this one) | `traffic_spawner.gd`: shelved traffic stops running its vehicle model |

### 9.2 The gate error was mine, and the fix pattern matters

`test_quality_ladder.gd` asserted with `assert_that(x).is_not_between(...)`.
**gdUnit4's float assert has no `is_not_between`** - it raised
`Nonexistent function 'is_not_between' in base 'GdUnitFloatAssertImpl.gd'`,
which the runner counted as 1 error.

Fixed by capturing the fresh `Environment`'s own values *before* applying the
preset and asserting they are unchanged, instead of hardcoding an engine default
a future Godot bump could invalidate. Prefer this shape whenever the invariant is
"this code must not write X".

Gate after the fix: **1033 tests, 0 failures, 0 errors, exit 0**.

### 9.3 ⚠️ THE BOTTLENECK MOVED TO THE CPU - most of the FH5 plan is now dead

After the SDFGI fix every preset measures `frame_ms ~= process_ms`:

| Preset | frame_ms | process_ms | bound by |
|---|---|---|---|
| Low | 12.7 | 13.2 | **CPU** |
| Medium | 16.1 | 17.0 | **CPU** |
| High | 13.6 | 14.6 | **CPU** |

High runs 13.6 ms against a 14.6 ms CPU floor: the GPU has ~1 ms of headroom,
not ten. **Texture compression, draw-call batching/MultiMesh merging, VRS, TAA,
mesh LOD, occlusion culling and virtual texturing are all DROPPED** - none of them
touch the constraint. Do not implement them; they cannot move the framerate.

`PHYSICS_3D_ACTIVE_OBJECTS avg=2`, so Jolt is solving essentially nothing. The CPU
cost is in per-frame callbacks, not rigid-body solving. `terrain_seeder.gd` and
`region_dresser.gd` use `_process`, not `_physics_process` - the `_physics_process`
implementations are `vehicle_physics.gd`, `ai_controller.gd`, `traffic`-side audio,
`living_world.gd`, `collectible_field.gd`, `event_session.gd` and the cameras.

### 9.4 Shipped CPU fix: shelved traffic was still running its whole vehicle model

`TrafficSpawner._apply_lod` shelves a car when it is parked or beyond
`lod_distance` (140 m) by calling `set_simulation_enabled(false)`. That halts Jolt
but **leaves the node's own `_physics_process` alive**, so every shelved car still
paid for the full pipeline each tick: arcade speed clamp, `_detect_impact`, input
reads, steering, drivetrain, tyre/surface model. Since `lod_distance` (140) sits
well inside `spawn_radius` (300), *most* traffic was frozen-but-busy.

Fixed by pairing `set_physics_process(false)` with the freeze and re-enabling it
on unshelve, alongside the audio cull that was already there. Safe because
`should_shelve` already excludes `_awaiting_ground` cars and the driver is
suspended.

**This fix is code-justified, not benchmark-justified** - a frozen suspended car
should not run its tyre model. See 9.5 for why no number is attached to it.

### 9.5 ⚠️ MEASUREMENT INTEGRITY - the box was too loaded to measure

The dev box carried **46-53% ambient CPU load** (opencode, VS Code, copilot,
Steam, OneDrive). Two **identical** Medium configs measured **62.1 and 38.5 fps**,
and an identical High config measured **73.3 fps earlier vs 10.8 fps later** - a
6.8x collapse.

This also **invalidates leave-one-out ablation** under contention: disabling any
subsystem frees CPU for everything else, so every ablation looks like a win. We
measured base 10.8 / traffic-off 56.3 / dressing-off 45.1 / terrain-off 29.8, and
**none of that ranking is meaningful.** Do not conclude "traffic is the
bottleneck" from those numbers.

Consequences for the next agent:
- **Trustworthy:** SDFGI ~9 ms, the shadow ladder's 2.45x on Low, VRAM
  1182 -> 777 MB. These reproduce across runs.
- **Not trustworthy:** per-preset figures, especially Medium's. Nothing within
  ~20% of current is measurable here.
- `physics_ms` vs `process_ms` are **not comparable** under load (observed
  `physics_ms` 26.3 > `frame_ms` 25.9, and "143% of process"). Only `fps` is
  meaningful. This is why the probe now ablates and reads fps only.
- **Re-baseline on a quiet machine before optimizing against any number.**
  Median of >=3 runs. Never gate on a single run's fps.
- `tools/perf_probe.gd` gained `PERF_DISABLE` CPU names (`chunk_streamer`,
  `terrain_stream`, `traffic`, `living`, `collectibles`, `events`, `dressing`)
  which `set_process`+`set_physics_process` the named nodes WITHOUT hiding
  geometry, so a delta is CPU time not render time. Infrastructure only - no
  conclusions drawn from it yet.
- Perf logs always warn `7 RIDs of type "Texture" were leaked`; runs still complete.

### 9.6 ⚠️ CORRECTION to 9.5 - paired A/B also failed; the noise is NOT background load

The user confirmed this box is already at its quietest (VS Code always runs), so
9.5's "re-baseline on a quiet machine" advice is **wrong** - there is no quieter
machine to wait for. Re-tested with **paired back-to-back runs in one session**,
which is supposed to control for machine state. It does not:

| Run | Config | fps | phys_bodies |
|---|---|---|---|
| `abA_prefix` | traffic PRE-fix | **7.4** | 4 |
| `abB_postfix` | traffic POST-fix | **70.1** | 2 |
| `abA2_prefix` | traffic PRE-fix | **73.1** | 1 |
| `abB2_postfix` | traffic POST-fix | **73.2** | 1 |
| `abC_notraffic1` | traffic OFF entirely | **53.7** | 3 |
| `abC_notraffic2` | traffic OFF entirely | **69.9** | 2 |

Three conclusions, and they matter more than any number above:

1. **The traffic fix has NO measured perf benefit.** Pair 1 said 9.5x, pair 2 said
   0.1%. Same-session repeats of the same config swing 7.4 -> 73.1. It is kept
   because it is correct-by-construction (a frozen suspended car should not run
   its tyre model) - **not** because it was measured. Do not cite it as a win.
2. **Config has no reliable effect.** Disabling traffic *entirely* still produced
   53.7 and 69.9. Every earlier ablation number (56.3 / 45.1 / 29.8 / 10.8) is
   noise. None of them rank anything.
3. **The swing is NOT in script CPU.** `process_ms` stayed 13.8-15.0 and
   `physics_ms` 13.9-14.1 across runs that differed 10x in fps. So the variance
   lives outside `TIME_PROCESS`/`TIME_PHYSICS_PROCESS` - i.e. GPU/driver/present
   stall, not GDScript. `phys_bodies` (1-4) does not correlate with fps either.

**Next agent: do not try to profile on this box.** Before trusting any fps figure,
check whether the GTX 970 is thermally throttling or power/clock limited
(`nvidia-smi -q -d PERFORMANCE,TEMPERATURE,CLOCK` while a run is going) - a 10x
collapse with flat script timings is not something load averaging explains.
Until that is resolved, the only safe perf work is code-justified changes, and
the `test_perf_gate.gd` CPU budget is the only trustworthy gate signal.

### 9.7 Thermal / power throttling is RULED OUT (measured, not guessed)

Sampled the GPU with `nvidia-smi --query-gpu=... --format=csv,noheader -lms 2000`
in a detached loop while a probe ran in the foreground
(`reports/perf/gpu_telemetry.txt`, 32 samples; the first 18 are world-load idle,
the last 14 are the measured window):

- `clocks_throttle_reasons.active` = **`0x0` (none)** for the entire active window
- SM clock **steady 1278 MHz** (max 1418) - no clock drop
- Temperature **46 -> 52 C** - cool, and it *rose* during load, so it is not
  sitting in a thermal ceiling
- Power **120-149 W** against a **160 W** limit - not power limited
- **GPU utilization only 47-88% (avg ~68%)** - the GPU is NOT saturated

So the 10x fps collapse is **not** thermal and **not** power/clock limited, and
the GPU is not the bottleneck. Combined with 9.6's flat `process_ms`/`physics_ms`,
the stall is CPU- or present/driver-side. Low GPU util at low fps means the frame
is *waiting*, not computing - which is the signature to chase next.

Reproduction recipe (works; note `timeout /t N >nul` fails here with "Input
redirection is not supported", and `start /b` did not launch Godot - launch
`nvidia-smi` detached and run the probe in the foreground instead):

```
start "" /b cmd /c "nvidia-smi --query-gpu=temperature.gpu,clocks.sm,power.draw,utilization.gpu,clocks_throttle_reasons.active --format=csv,noheader -lms 2000 > reports\perf\gpu_telemetry.txt"
<run probe in foreground>
taskkill /im nvidia-smi.exe /f
```

### 9.8 ⚠️ BREAKTHROUGH: the bottleneck is PRESENT/WAIT, not work — the whole plan was aimed at the wrong stage

Added a self-consistent frame-stage breakdown to `perf_probe.gd` (see
`_prev_frame_usec`): using `Time.get_ticks_usec()` at `process_frame` and at
`RenderingServer.frame_post_draw` to split each frame into
`todraw` (process+render up to draw done) and `wait` (engine tail + present +
compositor). Validation: `stage_period` **13.6 ms vs `frame_ms` 13.6 ms** in the
same run, so the two independent measures agree and the split is trustworthy.
(Do NOT use `OS.get_ticks_usec()` - it does not exist in Godot 4; it is `Time`.)

Same High config, four windowed runs:

| run | fps | period | **todraw** | **wait** |
|---|---|---|---|---|
| healthy | 73.5 | 13.6 | 9.5 | **4.1** |
| b1 | 53.2 | 18.7 | 6.6 | **12.0** |
| b2 | 61.7 | 16.2 | 7.2 | **9.0** |
| b3 | 74.3 | 13.4 | 9.6 | **3.8** |

**The work is stable; the wait is not.** `todraw` stays in a tight 6.6-9.7 ms
band, while `wait` swings **3.8 -> 12.0 ms** and fps tracks it almost exactly
(`fps ~= 1000/(todraw+wait)` reproduces every row). That is the whole mystery
resolved:

- The 7-73 fps swing was **never** a workload difference. It is present /
  compositor blocking, and it varies run to run on identical content.
- **Every A/B in this handoff was measuring noise**, because the effect being
  chased (~1-3 ms of render work) sits under a +-8 ms present stall.
- `todraw` ~7-10 ms is the *only* stable cost, and it is already under the 16.7
  ms contract. There is no 2x render win available - the GPU was never the wall.

Fullscreen probe (`--fullscreen --resolution 1920x1080`), same config:

| run | fps | todraw | **wait** |
|---|---|---|---|
| f1 | 74.3 | 9.7 | **3.7** |
| f2 | 75.3 | 9.7 | **3.5** |

2/2 fullscreen runs sat at the *floor* of the wait band and were healthy, versus
2/4 windowed runs collapsing to 9-12 ms. **Suggestive, not conclusive** (n=2) -
but it is the cheapest thing to try and it costs no quality. Get more samples
before claiming it.

**This also explains Medium.** Medium is MSAA 4x at full resolution with no
upscaling, and MSAA resolve lands on the swapchain - a classic present-cost
multiplier. Medium being the slowest preset (62.1 vs High 73.3) fits the
present-cost theory far better than it fits a GPU-fill theory.

### 9.9 CORRECTION to 9.8 - `wait` is mostly OS scheduling, and there IS real GPU headroom

Two refinements, the second of which **retracts the over-claim in 9.8**.

**(a) `wait` is background CPU load, not GPU present.** Sampled system load
*during* runs (`reports/load_sampler.ps1`, append-per-sample):

| run | todraw | wait | fps | load during measured window |
|---|---|---|---|---|
| f2 (fullscreen) | 9.7 | 3.5 | 75.3 | quiet |
| healthy windowed | 9.5 | 4.1 | 73.5 | quiet |
| b2 | 7.2 | 9.0 | 61.7 | - |
| load_s2 | 6.6 | 12.1 | 53.4 | **15-39%, rising** |
| loadtest | 6.8 | 21.0 | 34.6 | **46%** |

`wait` tracks background load, and it is the OS descheduling our process between
`process_frame` and the next one - VS Code, copilot, OneDrive and Steam. This is
**not** a GPU present/compositor wall as 9.8 guessed. Note also that `todraw`
*falls* as `wait` rises (9.7 -> 6.6), because a slower loop submits fewer draws
and the GPU idles more - further proof the GPU is not the constraint.

**(b) RETRACTION: there IS real GPU headroom, and 9.8's "no 2x render win" was
wrong.** `todraw` runs 6.6-9.7 ms *inside a 13.4-13.6 ms frame*, and it includes
GPU time, because `frame_post_draw` only fires once the GPU has finished drawing.
So at the quiet floor (wait 3.7) the frame is ~70% draw work. Cutting `todraw`
from 9.7 -> 6.6 would take the frame from 13.4 -> ~10.3 ms, i.e. **74 -> ~97
fps**. That is a genuine ~30% win, and it is exactly the kind of GPU-side work
9.8 and the earlier sections cancelled.

Why it still could not be *measured*: the effect (1-3 ms) is smaller than the
`wait` noise (+-8 ms, driven by apps outside the game). So the GPU items are not
worthless - they are **unverifiable on this box while other apps run**.

Practical consequence: **all GPU reductions must be judged on `todraw`, never on
fps**, and `todraw` must be sampled across several runs and compared at a
similar `wait`. The right target is the 9.7 ms figure, not 73 fps.

### 9.10 Open items

1. **Re-measure GPU items against `todraw`, not fps.** Anything that cuts draw
   work (fewer draws/primitives, cheaper shading, less overdraw) should move the
   9.7 ms `todraw`. Previously-dropped items are reconsidered ONLY with this
   metric. Do not re-run the old fps A/B - it cannot resolve 1-3 ms.
2. **Still dropped:** TAA (stacks with FSR2, visual risk) and VRS (needs a
   startup ProjectSettings flag, and terrain here is mostly distant). Keep
   texture compression / batching / culling in "only if `todraw` won't move".
3. **Confirm fullscreen (n=2)** - but note 9.9(a): if `wait` is OS scheduling,
   fullscreen's apparent benefit may be coincidence. Re-test with load sampled.
4. **The bad case is the real case.** Healthy runs are 73-75 fps; the same content
   also measures 34-61 fps when the box is busy. Player-facing targets must be set
   against the busy case, and `stage_wait` is worth wiring into a regression check.
5. **`todraw` composition is still unattributed.** It is ~7-10 ms and includes
   both CPU submit and GPU execution; splitting those two would say whether more
   headroom exists. GPU util 47-88% says the GPU is moderately busy, not pegged.
6. **FSR2 sharpness** - `Viewport.fsr_sharpness` VERIFIED to exist as a real float
   property (project setting default 0.2). Quality only; near-free under this
   model; needs `settings.tscn` work since the menu binds `%UniqueName` nodes.
7. Delete `reports/load_sampler.ps1` (throwaway; `reports/` is gitignored).
8. CI still deliberately deferred (section 6). 

