# Running the GDUnit4 gate on this machine (Windows)

How to actually run the full test suite and READ its results, written after the
`gate` sub-agent proved unreliable (it kept retrying POSIX commands and looping).
Everything here is copy-paste verified on the PC (`D:\AI Projects\UltraDrive`).

---

## 0. The two rules that cause every failure

1. **The Bash tool runs `cmd.exe`, not bash.** No `head`, `tail`, `cat`, `grep`,
   `ls`, `wc`, `sed`, `awk`, `xargs`, `tail -f`. Use **`tools\pick.bat`**, which
   works identically on both machines:

   ```
   tools\pick.bat tail 40 reports\parallel\logs\shard_4.log
   tools\pick.bat grep "FAILED" "D:\AI Projects\UltraDrive\reports\parallel\logs\*.log"
   tools\pick.bat grep "Overall Summary" reports\parallel\logs
   ```

   `grep` prints `file:lineno:text`, takes a file/glob/directory, and exits 1
   when nothing matches. Full list in `AGENTS.md`.
2. **Use `%GODOT_EXE_CONSOLE%`, never the GUI binary.**
   `Godot_v4.7.2-stable_win64.exe` is a WINDOWS_GUI-subsystem PE: it detaches,
   does not wait, does not attach stdout, and reports success while doing
   nothing. This is the "false-green" trap — see §4.

---

## 1. Resolve the engine (never hardcode a drive)

```
cmd /v:on /c "call godot_path.bat & echo !GODOT_EXE_CONSOLE!"
```

Verified output on the PC:

```
D:\Godot\Godot_v4.7.2-stable_win64_console.exe
```

Sanity check it is really the console twin (must print a version):

```
cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE! --version"
```

```
4.7.2.stable.official.ed1daf0bf
```

An **empty** result means you grabbed the GUI binary. Re-resolve; never hardcode.

---

## 2. Step 1 — headless import probe (MUST run before the suite)

```
cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE! --headless --import . 2>&1"
```

Expect **zero** `SCRIPT ERROR` / `Parse Error` / `Failed to load`.
`resources still in use at exit` and Terrain3D whitelist lines are benign.

To filter (see the gotcha in §3 — the obvious filter lies to you):

```
cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE! --headless --import . 2>&1" | findstr /i "SCRIPT ERROR Parse Error"
```

This is the same order used since D5. If you skip it, the GDUnit run can die
with exit 103 "Headless mode is not supported!" which has nothing to do with
your code.

---

## 3. Step 2 — the full suite

```
cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE! --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1"
```

- `--ignoreHeadlessMode` **must come AFTER** the tool-script path. Before it,
  the engine bails with exit 103.
- Takes **~15 minutes** on the GTX 970. Give the `bash` tool a timeout of at
  least `1200000` ms or it will be cut off mid-run.
- Targeted run: swap `-a res://tests` for `-a res://tests/suites/<name>.gd`.
  One Godot process at a time — never two in parallel.

### GOTCHA: the naive `findstr` filter lies

```
findstr /i "SCRIPT ERROR Parse Error Failed to load"
```

`findstr` splits that argument on spaces into OR'd tokens:
`SCRIPT`, `ERROR`, `Parse`, `Error`, `Failed`, `to`, `load`. So `load` matches
every `Loading...` progress line and `ERROR` matches the benign exit-leak line.
You get a screenful of noise and cannot tell a real failure from a progress bar.
Filter on `SCRIPT ERROR` and `Parse Error` only.

### GOTCHA: nested quotes break `findstr`

This FAILS, with a misleading error:

```
cmd /v:on /c "findstr /c:\"Overall Summary:\" _gdunit.txt"
```

```
FINDSTR: Cannot open Summary:"
```

cmd mangles the escaped quotes and `findstr` then treats `Summary:"` as a
filename. Use PowerShell or the `grep` tool instead (see §5). Do not try to
out-quote it.

---

## 4. Confirm the run actually happened

```powershell
powershell -NoProfile -Command "Get-Item '_gdunit.txt' | Select-Object Length"
```

A **0-byte** `_gdunit.txt` means nothing ran. This exact false-green has been
observed: a "passing" import probe in 8 ms and a 0-byte log in 8 ms, both
because the GUI binary was used. A real full run is ~700 KB.

---

## 5. Reading the results

### Overall summary (the gate line)

```powershell
powershell -NoProfile -Command "Get-Content '_gdunit.txt' -Tail 40"
```

The tail always contains:

```
Overall Summary: N test cases | E errors | F failures | L flaky | S skipped | O orphans |
Executed test suites: (95/95)
Executed test cases : (1004/1004)
Total execution time: 14min 59s 215ms
Open XML Report at: file://D:/AI Projects/UltraDrive/reports/report_596/results.xml
Open HTML Report at: file://D:/AI Projects/UltraDrive/reports/report_596/index.html
Exit code: 100
```

### Only the failing suites, in one line

Every suite prints its own `Statistics:` line. Filtering to the non-clean ones
gives you the entire failure list at a glance — this is the single most useful
command here:

```powershell
powershell -NoProfile -Command "Select-String -Path '_gdunit.txt' -Pattern 'Statistics:' | ForEach-Object { $_.Line } | Where-Object { $_ -notmatch '\| 0 errors \| 0 failures \|' }"
```

Empty output = the entire tree is green.

### The failing assertion + stack trace

```powershell
powershell -NoProfile -Command "Select-String -Path '_gdunit.txt' -Pattern 'FAILED' | ForEach-Object { $_.LineNumber.ToString() + ': ' + $_.Line }"
```

then read around that line:

```powershell
powershell -NoProfile -Command "Get-Content '_gdunit.txt' | Select-Object -Skip 2225 -First 40"
```

### The browsable HTML report — the real answer to "see the logs"

gdUnit4 writes a full report per run to an incrementing directory:

```
reports/report_596/index.html     <- open this in a browser
reports/report_596/results.xml    <- machine-readable, per-test
reports/report_596/test_suites/   <- one page per suite
reports/report_596/path/
```

`reports/` is gitignored and accumulates one dir per run (currently `report_577`
… `report_596`). The HTML index gives you pass/fail per suite with the failure
message and timings, which is far faster than grepping a 700 KB text log. The
path is printed at the end of `_gdunit.txt` as `Open HTML Report at:`.

---

## 6. Interpreting the result — do NOT chase the wrong baseline

`AGENTS.md` carries a **measured baseline, not a target**:

```
950 test cases | 0 errors | 26 failures | 0 flaky | 0 skipped | 20 orphans
```

Those 26 were stale ROAD/CORRIDOR failures that have since been fixed. The
suite now defines **1004** test cases across 95 suites, and the road/rail
corridors are green. Judge the run by:

- `errors` — must be 0. Non-zero means a script failed to load (usually a
  GDUnit warnings-as-errors violation).
- `failures` — compare **against the previous run of the same tree**, and
  against the suites your change touches. Do not gate on a hard-coded count.
- `orphans` — ~20 is normal and benign (SceneTransition / autoload / freed
  stub vehicles).

### `test_perf_gate.gd` is a wall-clock flake, not a correctness signal

`test_pick_preset_is_deterministic_and_in_ladder` runs a real physics
benchmark and asserts `avg_ms <= CONTRACT_FRAME_BUDGET_MS`. On this GTX 970 it
measures 16-25 ms depending on what else is running, so it fails whenever the
box is loaded (a live LLM session, Ollama/Vulkan, a browser). Example from
2026-10-03: `Expecting to be less than or equal: 16.700000 but was 24.442944`.

This is **not** a regression from a logic change — nothing in
`RoadDef` / `TrackBuilder` / `CorridorPlanner` adds per-frame cost. If it is the
only failure, the gate is green for your change. Note it and move on.

The gate now self-selects between an absolute contract and a same-run relative
one, so this advice applies differently off the reference box. Read the `[perf_gate]
mode=...` line the suite prints before judging it, and see "The perf gate has two
modes, and one override" in the parallel-gate section below.

### GDUnit aborts a suite at its first failure

So a red suite hides every test after it. The true state is worse than one run
reports: fix the first failure in a suite before trusting its counts, and never
read "95/95 suites executed" as "everything passed".

---

## 7. Why the `gate` sub-agent was abandoned

`task(subagent_type="gate")` repeatedly failed: it retried the same POSIX
commands in a loop, ignored the cmd.exe constraint, and burned turns without
producing a summary. `.opencode/agent/gate.md` documents that agent, but the
recipe in this file is short enough that running it inline in the main session
is faster and more reliable — see the timing in §8.

If you do delegate, the prompt MUST open with the cmd.exe constraint and the
exact `cmd /v:on /c "call godot_path.bat & ..."` command lines. Never hand an
agent a PowerShell snippet to paste verbatim into the Bash tool.

---

## 8. Reference timings (PC, GTX 970)

| Step | Duration |
|---|---|
| `--version` sanity check | ~50-150 ms |
| headless import probe | ~10-60 s |
| Full GDUnit suite (1004 cases, 95 suites) | **~15 min** |
| `_gdunit.txt` size for a full run | ~700 KB |

A full run is too slow to block on casually, but it is also not worth a
sub-agent round-trip. Run it inline when you need the answer now; dispatch a
sub-agent only when you have other feature work to do in parallel.

---

## 9. GDUnit gotchas that cost real time

- **Warnings are errors.** `var x := some_func_returning_Variant()` fails to
  LOAD the whole suite. Use an explicit `var x: Variant = ...` or a cast.
- **Vector `is_equal_approx` needs a same-type approx arg**, not a float:
  `assert_that(vec).is_equal_approx(vec, Vector2(0.001, 0.001))`.
- A **parameter shadowing a member variable** (e.g. `func make(rail_sides: int)`
  next to `@export var rail_sides`) is a latent warning-as-error. Name it
  `rail_sides_override`, matching the existing `width_override` /
  `surface_override` convention.
- Any script error during a headless diag can leave Godot **hanging forever** —
  always run under a timeout/watchdog.
- Godot's `import_images()` snaps to region anchors; not a gate issue but the
  same "silent no-op" family of bugs.

---

## Parallel gate (`tools/gdunit_parallel.py`)

`tools/gdunit_parallel.py` is an **optional** sharding wrapper around the serial
recipe above. It discovers the suites under `tests/`, weights them by how many
`func test_` each file defines, bin-packs them into N balanced shards, runs one
headless Godot process per shard, and merges the per-shard JUnit XML.

**The serial gate in §2–§6 remains the source of truth for a single
authoritative run.** The parallel path does not replace it and does not produce
a run comparable to it: shard boundaries, VRAM pressure and cross-process
scheduling all change, so its totals, timings and flake profile are its own.
Use the parallel runner to iterate quickly and to fan out across CI; use the
serial recipe when you need the number you would quote.

Why it exists: the serial gate takes **~18 min** on the GTX 970 (§8), and every
gate run is a 18-minute decision gate. The parallel runner shards the 95 suites
across N processes to shorten that.

_Measured: `-j 4` completed in **264.3 s (4 m 24 s)** wall-clock vs the ~18 m 23 s
single-process baseline — a **4.18x** speedup, 95/95 suites, 1018 test cases,
0 errors / 0 failures / 20 orphans (the baseline orphan count), 0 false greens.
Shard walls were 264 s / 136 s / 247 s / 46 s, so the balance is decent but not
tight — shard 1 is the critical path. Re-measure with
`reports/parallel/summary.json` after touching the suite mix._

### Usage

Run from the project root. The shell here is `cmd.exe` (see §0), and the script
resolves the engine itself via `godot_path.bat` / `GODOT_EXE_CONSOLE` — never
hardcode a Godot drive path.

```
py tools\gdunit_parallel.py -j 4
py tools\gdunit_parallel.py -j 4 --dry-run
py tools\gdunit_parallel.py -j 2 --only test_road_graph.gd,test_collectibles.gd
py tools\gdunit_parallel.py -j 4 --shard 2
py tools\gdunit_parallel.py -j 4 --no-isolate-user-data
py tools\gdunit_parallel.py -j 4 --fail-fast
```

| Flag | Meaning |
|---|---|
| `-j`, `--jobs` | Number of parallel shards, clamped to `1..8`. Shard indices are `1..j` (`0` is reserved for the serialized shard — see below). |
| `--shard N` | Run only shard `N` and nothing else. Built for a future CI matrix: **every job in the matrix must pass the same `-j`**, because shard indices are derived from it. A job with a different `-j` runs a different partition. |
| `--dry-run` | Print the shard plan (suites, weights, estimated tests per shard) and exit. Launches no Godot process and writes nothing. Use this first when changing suite counts. |
| `--only a.gd,b.gd` | Restrict to a comma-separated list of suite filenames — the smoke subset. |
| `--continue` | **Default.** Passes gdUnit's `-c` so a suite runs every remaining case after a failure instead of aborting at the first one (see the abort gotcha in §6). |
| `--fail-fast` | Omits `-c`; a red suite stops at its first failure and the rest of its cases never execute. Faster, but hides state — use it to bisect, not to gate. |
| `--no-import` | Skip the `--headless --import` probe. It runs once per invocation by default because a `-s` run before a successful probe dies with exit 103 (§2). Only skip it if you just ran the probe in this same tree. |
| `--timeout` | Per-shard watchdog in seconds, default `3600`. Any script error during a headless run can hang Godot forever (§9), so do not disable this. |
| `--godot` | Explicit path to the Godot `*_console.exe`. Default: `$GODOT_EXE_CONSOLE`, else `godot_path.bat`. The resolved binary is sanity-checked with `--version` before any shard launches, which is the automated form of the GUI-binary trap in §4. |
| `--reports-root` | Report base dir, default `reports/parallel`. |

### Per-shard `user://` isolation — the important design note

Every shard gets a private `user://` tree by overriding `APPDATA` in its child
process environment (`build_shard_env`). This works with **zero project
changes** because Godot resolves `user://` to
`%APPDATA%/Godot/app_userdata/<application/config/name>` and does no path
canonicalisation — so an absolute per-child `APPDATA` redirects the whole tree.

Two consequences, both of which the design depends on:

1. **It removes real save-slot contention.** `autoload/save_manager.gd` writes
   `user://saves/slot_N.json` through a single shared, fixed `.tmp` name, and
   **13 suites** reach that write — directly or through `GameState` setters,
   `Garage`, `BestLapRecords`. The list is `CONTENDED_SUITES` at the top of the
   script. Without isolation those suites genuinely race each other.
2. **It keeps every byte off C:.** The un-overridden default writes to
   `C:\Users\<user>\AppData\Roaming\Godot\app_userdata\UltraDrive`. That matters
   on the PC, where the C: drive is small (see `AGENTS.md`).

**Windows-only caveat:** this relies on `APPDATA` being how Godot resolves the
data directory *on Windows*, and the value **must be absolute**. A relative
`APPDATA` is resolved against the child's working directory, not the project,
and the isolation silently becomes a no-op at best and cross-drive at worst.

The fallback, `--no-isolate-user-data`, drops the redirect and instead
serializes all 13 `CONTENDED_SUITES` into one trailing shard (index `0`), so
they never overlap. Use it only to test the isolation itself, or if a future
platform makes the `APPDATA` trick inapplicable.

### False-green detection

The whole point of the wrapper is that it **refuses to report green on the
silences documented throughout this file**. The runner exits non-zero and prints
a `!! FALSE GREEN` banner when any shard:

- produced **no `results.xml`** under its report dir, or the XML reports
  **`tests == 0`**;
- exited **103** (headless guard tripped) or **105** (script errors during
  discovery) — the two exit codes in §2 that mean "nothing ran";
- exited 100 while the XML shows 0 failures and 0 errors (bad CLI arguments
  masquerading as results);
- printed **`Given directory or file does not exists:`** or
  **`No test cases found`** for any suite in the shard — i.e. gdUnit silently
  rejected an `-a` path. This is the §9 gotcha in machine-checked form.

**Exit code 101 (orphans only) counts as success-with-warning**, not a false
green: the measured baseline has 20 orphans (§6) and gdUnit reports it
distinctly from failures.

Runner exit codes: `0` clean, `1` test failures/errors, `2` false green or
environment problem.

**Exit `1` and exit `2` are different verdicts — never collapse them.** A shard
with real failures prints `RED (n fail / m err)` and the run exits `1`: the tests
ran and something genuinely failed, so the result is *red but trustworthy*. The
`!! FALSE GREEN` banner and exit `2` mean the opposite: the result is
*untrustworthy* — nothing ran, or the numbers cannot be believed. The `RED`
path had never been reached by a green run before; it is now **verified**,
confirmed three times, so the distinction is observed rather than merely
asserted.

### The perf gate has two modes, and one override

`test_perf_gate.gd` asserts a frame-budget contract, so the box's speed decides
which contract is meaningful. The **value** of
`PerfBench.CONTRACT_FRAME_BUDGET_MS` is never loosened — only the **gate** that
enforces it changes, and it picks its own mode from the run's own numbers:

- **`reference`** — this run's fastest SUSTAINED row (`control_ms`) already came
  in at or under 16.7 ms, so the box demonstrated it can hold 60 Hz. The
  **absolute** contract binds: every sustained row must fit 16.7 ms.
- **`relative`** — `control_ms > 16.7` ms, so the absolute number would only
  measure the machine. The absolute gate is **off** and only the same-run spread
  control applies: every sustained row within `1.35x` of the fastest sustained
  row of that same run, floor `1.5` ms.

Whichever mode ran is printed by the suite:
`[perf_gate] mode=... control_ms=... contract_ms=... load_budget_ms=...`. The load
window's bound is `3.0 x maxf(control_ms, contract_ms)`, which is exactly the old
`50.1` ms in reference mode and keeps "the world never settled" detectable on a
slow box.

`ULTRADRIVE_PERF_MODE` overrides the auto-detection when the detection is not
good enough:

| Value | Effect |
|---|---|
| unset, or any other value | auto-detect from `control_ms` (default) |
| `reference` | force the strict absolute gate on even if the box cannot hold it — it will then fail, which is the point |
| `relative` | force the absolute gate off |

**The tradeoff, stated honestly:** in relative mode a regression that slows
EVERY preset EQUALLY is no longer detectable — only a *per-preset* regression is,
because only the per-preset comparison survives at a machine speed that already
misses the budget. The reference rig never degrades, so it pays none of this
cost.

### Report layout

Per-shard artifacts land under `reports/parallel/`:

```
reports/parallel/
  shard_<i>/report_<N>/     <- gdUnit's own output: index.html,
                               browsable test_suites/, results.xml
  logs/shard_<i>.log        <- full stdout/stderr of that shard
  logs/import_probe.log     <- the --headless --import probe
  userdata/shard_<i>/       <- that shard's isolated user:// tree
  merged-results.xml        <- all shards concatenated into one JUnit <testsuites>
  summary.json              <- per-shard counts, exit codes, suite lists
```

**Each shard gets its own `-rd`, and that is mandatory.** gdUnit picks
`report_<N>` by scanning the target directory for the highest existing index,
and a *finishing* run recursively deletes lower-indexed siblings in its base.
Concurrent shards sharing one `-rd` would therefore interleave their numbering
and delete each other's reports out from under the merge. The runner also wipes
its shard dir before launch and globs for the XML rather than assuming a fixed
index, so a stale `report_` directory cannot be picked up as this run's result.

`summary.json` is the thing to read for a quick verdict; open
`shard_<i>/report_<N>/index.html` for per-suite failure text exactly as you
would in §5.

### Timing flakes: one is fixed, one is still hardware timing

§6 records two wall-clock flakes. Their status is no longer the same:

- **`test_race_results.gd`'s timing band is FIXED.** It was never a
  machine-calibration problem — it was a genuine test bug. The suite asserted the
  results-screen total against a `±0.05 s` band around a *second* read of
  `LapCounter.get_total_time()`, a live monotonic clock, while the HUD reads that
  clock once inside `RaceManager.finish_race()` and then does save-file I/O in
  `_submit_best_lap` before writing the label — so the band measured the test's
  own execution latency plus disk I/O latency. It is now an exact bracket taken
  around the `finish_race()` call (plus `LABEL_QUANTISATION_SECONDS = 0.01` for
  the label's `mm:ss.ss` granularity), which is exact at any machine speed. It is
  not a benchmark and is not in `SERIAL_SUITES`; nothing about parallel load can
  break it now.
- **`test_perf_gate.gd` is still the one real hardware-timing suite**, which is
  why it still runs alone in the serialized shard (index `0`). Four concurrent
  Godot processes on the GTX 970 make it measurably worse — this is CPU
  contention and the budget is wall-clock. A red perf gate is **not** a
  correctness signal: read the `mode=` field of the `[perf_gate]` line first (see
  "The perf gate has two modes" above), because a red gate is either a loaded box
  or a deliberately forced strict mode. Re-run it alone before believing it.

### One Godot process at a time — the deliberate exception

§3 says never run two Godot processes in parallel, and that rule still holds for
the serial recipe. **The parallel runner is the one deliberate exception**: it
launches N at once by design. The consequence is that you must not run it
*alongside* anything else — no other Godot process, no serial gate, no second
`gdunit_parallel.py`. Serialize whole gate runs, not individual shards.

---

## 10. Scratch files

`test_ring.gd` sits untracked in the project root — throwaway debug scratch
from an earlier session (a `SceneTree` script that prints highway-ring vertex
coordinates). It is untracked and harmless, but it is not part of the project.
Delete it or move it under `docs/` when convenient. Never `git add -A`:
`*.uid` files are gitignored noise and must not be staged.