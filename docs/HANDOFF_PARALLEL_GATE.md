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
| **P1 — measured weights + isolated benchmark** | **3m29s (208.9 s)** | **5.28x** |

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

Shard balance improved from a 4.8x spread to **1.11x**:
`156.0 / 154.3 / 159.7 / 144.1 s` parallel + `49.2 s` serialized tail.

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
