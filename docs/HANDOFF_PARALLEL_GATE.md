# HANDOFF — GDUnit4 parallel gate (P1)

**Status at handoff:** P1 implemented, validated GREEN, and committed. Nothing
is left half-done. CI is the open item and is deliberately deferred.

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
2. **The shell is cmd.exe, not bash.** No `head`, `tail`, `cat`, `grep`, `ls`,
   `wc`, `sed`, `awk`, or `&&` after a pipe. Use `findstr /c:"pat" <ABSOLUTE
   path>`, `type`, `dir`, or wrap PowerShell as
   `powershell -NoProfile -Command "..."`. `findstr` silently reports
   `Cannot open` on relative paths — always pass absolute ones. Use the `workdir`
   parameter, never `cd`.
3. **Use `py`.** `python`/`python3` are WindowsApps Store stubs and do nothing.
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
arrival. Blockers:

1. `tests/suites/test_perf_gate.gd` asserts a **16.7 ms** budget calibrated to
   *this* machine. Per `AGENTS.md` it has failed twice in fully serial runs
   here (`avg_ms 24.44`). On shared CI runners that contract is meaningless.
   Fixing it means making the assertion machine-portable (compare against the
   fastest sustained row in the same run rather than an absolute number) — a
   change to the test's intent, so it needs a decision, not a drive-by edit.
2. `tests/suites/test_race_results.gd` has a timing band that only slips under
   full-suite load. It passes in isolation.
3. `.godot/` import cache is ~38.7 MB and 313 assets would import cold on every
   runner. Needs a cache strategy.

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

`HANDOFF.md` at the repo root is an **older, unrelated** handoff (spawn-highway
ramp / per-segment rails, with a user-requested task still pending). It was
left untracked and untouched. The next agent should read it before touching
`corridor_planner.gd` / rails.
