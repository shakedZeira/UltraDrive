# AGENTS.md — UltraDrive (Godot 4.7.2)

Project knowledge for autonomous agents. Godot project root = **this
directory** (res://) — the checkout path differs per machine, so never
hardcode it:
- PC: `D:\AI Projects\UltraDrive`
- Laptop: `C:\Users\IMOE001\Desktop\Shaked Projects\UltraDrive\UltraDrive`

GDUnit4 addon at `addons/gdUnit4`, tests under `tests/` (suite:
`tests/suites`).

## READ FIRST — THE `head`/`tail`/`grep` TRAP (top of file on purpose)

**The `bash` tool in this project is NOT bash.** It is **cmd.exe** on the PC and
**PowerShell 5.1** on the laptop. `head`, `tail`, `cat`, `grep`, `ls`, `wc`,
`sed`, `awk`, `xargs` and `tail -f` **do not exist** and there is no `&&` after
a pipe.

**Use `tools\pick.bat` instead. It is the same on both machines:**

```
tools\pick.bat head 40 _gdunit.txt
tools\pick.bat tail 40 _gdunit.txt
tools\pick.bat grep "FAILED" "D:\AI Projects\UltraDrive\reports\parallel\logs\*.log"
tools\pick.bat grep "Overall Summary" reports\parallel\logs
tools\pick.bat lines AGENTS.md
tools\pick.bat find test_perf_gate.gd tests
tools\pick.bat ls tools
tools\pick.bat debug grep -n "pat" file      <- dumps arg parsing
```

Notes that matter:
- `grep` prints **`file:lineno:text`**, and its `<path>` may be a **file, a
  glob, or a directory** (searched recursively). `grep` and `find` exit `1`
  when nothing matches, so absence is detectable rather than silent.
- Common POSIX flags are absorbed, not rejected: `-n`, `-r`, `-e` are no-ops
  (those behaviours are always on), `-i` works, and `head -20` == `head 20`.
  An **unknown flag is a hard error**, never a silent mis-binding.
- Patterns may start with `-`. Avoid `|`, `<`, `>`, `&` inside a pattern —
  cmd.exe eats them before the script ever sees them.
- If you would have written `sed -i`, use the `edit` tool. If you would have
  written `cat`, use the `read` tool.

**Never type a POSIX pipeline into the `bash` tool.** If a sub-agent starts
emitting `head -20`/`grep -rn`/`ls -la`, that is the bug this section exists to
stop: it burns a whole run on `head is not recognized`. Two further notes so
you do not repeat it:

- `findstr` silently reports `Cannot open <basename>` for a **relative** path.
  Always pass **absolute** paths, or use `pick`.
- **Do not add a `param()` block to `tools\pick.ps1`.** `powershell -File
  script.ps1 -n grep f.txt` tries to bind `-n` as a *named parameter* of that
  block and dies with "A parameter cannot be found that matches parameter name
  'n'". That is fatal here because grep patterns so often start with a dash,
  which is why argv is parsed manually out of `$args`. Read the header comment
  in `tools/pick.ps1` before touching it — it records that and two other traps
  that were each hit for real.

The long-form shell rules (PowerShell vs cmd, the `py` launcher, `findstr`
recipes, Godot invocation) are further down under `## SHELL IS cmd.exe ...`.

## GODOT BINARY (never hardcode one drive)

`godot_path.bat` (project root) resolves the engine and exports `GODOT_EXE`.
It checks, in order: an existing `GODOT_EXE`, then
`D:\Godot\Godot_v4.7.2-stable_win64.exe` (PC), then
`C:\Godot\Godot_v4.7.2-stable_win64.exe` (laptop), then the Program Files /
`%LOCALAPPDATA%\Programs` defaults, then any `Godot_v4.7.2*.exe` under
`D:\Godot` or `C:\Godot`. It also exports `GODOT_EXE_CONSOLE` — see below,
you want that one for headless.

**Always resolve it instead of typing a path** (works on both machines):

```bat
call godot_path.bat && "%GODOT_EXE%" --path .
```

### HEADLESS RUNS MUST USE `%GODOT_EXE_CONSOLE%` (false-green trap)

`Godot_v4.7.2-stable_win64.exe` is a **WINDOWS_GUI-subsystem PE**. Under
PowerShell's `&` operator it DETACHES: it does not wait and does not attach
stdout. A headless run then silently no-ops and reports success. Observed for
real: an `--import` probe that "passed" in **8 ms** because `Select-String` was
handed zero lines, and a **0-byte** `_gdunit.txt` written in 8 ms. Both looked
green. Nothing had run.

`Godot_v4.7.2-stable_win64_console.exe` is the console-subsystem twin: `&`
waits and `>` redirection captures output. `godot_path.bat` derives it
automatically (`%GODOT_EXE:win64.exe=win64_console.exe%`, falling back to the
GUI binary if absent).

```powershell
$godot = (cmd /v:on /c "call godot_path.bat & echo !GODOT_EXE_CONSOLE!").Trim()
```

**Always sanity-check a headless run actually happened** before trusting it:
`& $godot --version` must print a version AND take real time (~50–150 ms warm);
an empty string or a single-digit millisecond count means you grabbed the GUI
binary. After the suite, confirm `_gdunit.txt` is not 0 bytes.

`play_game.bat` / `start_game.bat` already do this. If a path was hardcoded
to one drive, fix it to go through `godot_path.bat` — do NOT just flip it to
the other drive, that breaks the other machine.

## SHELL IS cmd.exe ON THE PC, POWERSHELL 5.1 ON THE LAPTOP — NO POSIX TOOLS (agents keep breaking on this)

The Bash tool on this project runs **cmd.exe** on the PC, not bash/zsh. There is
no `head`, `tail`, `cat`, `grep`, `ls`, `wc`, `sed`, `awk`, `xargs`, `tail -f`, or
`&&`-after-pipe. Do NOT reach for them — use the Windows equivalents. Also do
NOT paste the PowerShell snippets below straight into the tool: `&`, `$var`,
`2>&1 |` and backtick syntax are PowerShell-only and will not parse in cmd.

**The laptop is the exception (corrected):** there the shell is **PowerShell
5.1**, NOT cmd.exe. No `&&` either, and no `head`/`tail`/`cat`/`ls`/`grep` at
all. Use the `read` / `grep` / `glob` / `edit` tools, or PowerShell's own
`Get-Content` / `Get-ChildItem` / `Select-String`. The `cmd /v:on /c` forms below
are the PC's recipe and stay the verified one.

**The laptop also has no `py` launcher**, and `python`/`python3` there resolve to
the WindowsApps Store stubs that do nothing. The working interpreter is
`C:\Users\IMOE001\AppData\Local\Microsoft\WindowsApps\PythonSoftwareFoundation.Python.3.13_qbz5n2kfra8p0\python.exe`
(real CPython 3.13.14; `tools/gdunit_parallel.py` is pure stdlib, so nothing to
`pip install`). On the PC, use `py` as the rules below say.

| Instead of | Use |
|---|---|
| **anything POSIX** | **`tools\pick.bat ...`** — see the top section |
| `head -n 20 f` / `tail -n 20 f` | `tools\pick.bat head 20 f` / `tools\pick.bat tail 20 f` |
| `cat f` | the `read` tool, or `tools\pick.bat lines f` |
| `grep -n "pat" f` / `grep -rn` | `tools\pick.bat grep "pat" <abs path or glob>` |
| `ls` / `ls -la` | `tools\pick.bat ls [dir]` / `... ls [dir] a` |
| `wc -l f` | `tools\pick.bat lines f` |
| `sed -i` / `awk` | the `edit` tool — do not shell out |
| `find . -name x` | `tools\pick.bat find x [dir]` |

`findstr` remains available for one-off cases, but it is the second choice, not
the first: it silently no-ops on relative paths and has no exit-code contract.

**Paths:** always pass the `workdir` parameter instead of `cd`. `cd /d "..." &&
cmd` chains have proven unreliable here, and `findstr` silently reports
`Cannot open <basename>` when handed a relative path. Quote absolute paths.

**Godot from cmd** (verified working — this is the form to use, not the
PowerShell one in the workflow section below):

```
cmd /v:on /c "call godot_path.bat & echo !GODOT_EXE_CONSOLE!"
cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE! --version"
cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE! --headless --import . 2>&1"
cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE! --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1"
```

If you must use PowerShell, wrap it explicitly:
`powershell -NoProfile -Command "..."`.

## FILESYSTEM HYGIENE (MANDATORY)
- **Only write inside the project root** (this directory, whatever drive it
  is on). All tool output, logs, and artifacts stay in the project folder —
  no temp files, no scratch, no system temp dir.
- **HARD RULE (stated by the user 2026-10-04): do not use the C: drive AT ALL
  — D: only.** This overrides any earlier softer wording here.
- This bites in a specific place: Godot's `user://` defaults to
  `%APPDATA%\Godot\app_userdata\<project>`, which is on C:. Every headless or
  parallel run must set `APPDATA` to an ABSOLUTE path under the project root so
  saves, engine logs and gdUnit temp land on D: (see the PARALLEL GATE note
  below for the exact mechanism). Never leave it unset on a run you care about.
- **Caveat for when this project is cloned on another machine:** this repo is
  developed from `D:\AI Projects\UltraDrive`, but a checkout whose project root
  is itself on `C:\` cannot honour the rule — keep artifacts beside the project
  there. Never hardcode either path; resolve via `godot_path.bat` / `__file__`.

## VISION BRIDGE (local image analysis)

- A text-only session (opencode/big-pickle) can still "see" via the
  `vision-bridge` plugin (`.opencode/plugins/vision-bridge.js`): pasted images
  are staged to `.vision/inbox/`, screen/window captures to `.vision/captures/`,
  and both are inspected through the **local** vision model `qwen2.5vl:7b`
  served by Ollama on this machine.
- Tools provided by the plugin: `analyze_image` (LLM should ALWAYS use this to
  read an image — it cannot see images directly) and `capture_game_window`
  (window title defaults to "UltraDrive").
- Ollama lifecycle: installed at `D:\Ollama` (models in `D:\Ollama\models`).
  The plugin **spawns `ollama serve` on demand and kills it after ~60s idle** —
  never leave it running (it grabs GPU/CPU and would slow the game). The LLM
  backend is forced to **Vulkan** via `OLLAMA_LLM_LIBRARY=vulkan` (the bundled
  CUDA libs are compiled with CUDA 12.8+ PTX that this GPU's driver 560.94
  (CUDA 12.6) cannot JIT — the NVIDIA driver cannot be upgraded because the
  Maxwell GTX 970 is EOL after the R580 branch). Vulkan works and is stable
  (~2.6 tok/s on this GPU), just slow; if analyses come back
  "llama-server process no longer running", check the env var survived.
- Expect slow analyses: ~90s per screenshot at 2.6 tok/s. Keep prompts short
  and bounded (`max_tokens` is capped in the plugin).
- `.vision/` is gitignored (transient staging + captures).

## HEADLESS WORKFLOW (KNOWN-GOOD — reuse, don't rediscover)

GDUnit4 CLI correctly drags in the headless-mode guard, but ONLY when run
AFTER a normal `--headless` import+probe pass. The engine will refuse
`--headless` first-run launches with exit 103 ("Headless mode is not
supported!"), which has nothing to do with your code.

### Reliable recipe (each step self-terminating, add your own timeouts)

1) Permanent file-mode sanity: `git status --short` should NOT list `*.uid`
   (project `.gitignore` ignores them). If it does, they're untracked noise —
   never `git add -A`.

2) First-time or Big-Asset import (a real Blender/glb world). Resolve the
   **console** binary once, then use it (PowerShell — this is what agents
   should run):
   ```powershell
   $godot = (cmd /v:on /c "call godot_path.bat & echo !GODOT_EXE_CONSOLE!").Trim()
   & $godot --headless --import . 2>&1 | findstr /i "SCRIPT ERROR Parse Error Failed to load"
   ```
   (cmd equivalent: `call godot_path.bat && "%GODOT_EXE_CONSOLE%" --headless --import .`)
   → expect ZERO `SCRIPT ERROR` / `Parse Error` lines (benign `resources still
   in use at exit` and Terrain3D whitelist lines are allowed). A sub-second
   "clean" result means the GUI binary detached — see the false-green trap
   above and re-resolve.

3) GDUnit suite (headless, PRECEDED by step 2 so gdUnit4 has had its
   first-run). IMPORTANT: `--ignoreHeadlessMode` MUST come AFTER the tool-script
   path (before it, the engine bails with exit 103):
   ```powershell
   & $godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1
   ```
   Then `findstr /c:"Overall Summary:" _gdunit.txt` — and confirm
   `_gdunit.txt` is NOT 0 bytes before reading it.

   **READ `docs/GDUNIT_GATE.md` BEFORE RUNNING ANY OF THIS.** It has the
   cmd.exe command forms that actually work (the PowerShell snippets here do
   NOT parse in the Bash tool), the one-line command that lists every failing
   suite, the browsable HTML report gdUnit writes to `reports/report_<N>/`, the
   nested-quote `findstr` breakage, and the `test_perf_gate.gd` wall-clock
   flake you must not mistake for a regression. Prefer running the gate INLINE
   here over dispatching the `gate` sub-agent, which has proven unreliable.
   **MEASURED BASELINE at `a6287bb` (2026-09-27), not a target:**
   `Overall Summary: 950 test cases | 0 errors | 26 failures | 0 flaky | 0 skipped | 20 orphans`
   (exit 100). The tree defines 982 `func test_` across 95 files; 94 suites ran
   in 4m21s. **The old "263 test cases / 0 failures" figure in this file was
   badly stale — do not gate against it.**
   - GDUnit4 **aborts a suite at its first failure**, so 32 of the 982 defined
     tests never execute while suites are red. The true state is worse than any
     single run reports; fix the first failure in a suite before trusting it.
   - The 26 failures at this commit are pre-existing and concentrated in the
     ROAD/CORRIDOR layer, not gameplay: `corridor_planner.gd` grew (corridor
     count 16→19, an extra `hub-access-ramp` appended), which shifted every
     test that indexes `defs[]` positionally or asserts corridor/rail counts.
     Affected: `test_highway_access`, `test_road_graph`, `test_corridor_seeding`,
     `test_multi_lane_rails`, `test_mountain_pass_zone`, `test_open_world`,
     `test_terrain_biomes`, `test_map_route`, `test_photo_mode`.
   - Known unexplained defect: `test_highway_access` sees road id
     `'spawnhub-highwayccess-ramp'`, which matches no id literal in
     `corridor_planner.gd` — looks like string corruption, not an index bug.
   - **SUPERSEDED 2026-10-03** by a full run of the current tree
     (working tree, per-side rail mask landed):
     `Overall Summary: 1004 test cases | 0 errors | 1 failures | 0 flaky | 0 skipped | 20 orphans`
     (exit 100), 95/95 suites in **14m59s**, `_gdunit.txt` ~700 KB, HTML report
     in `reports/report_596/`. All 26 ROAD/CORRIDOR failures above are FIXED.
     The single remaining failure is
     `test_perf_gate.gd > test_pick_preset_is_deterministic_and_in_ladder`
     (`avg_ms 24.44` vs a `16.7` wall-clock budget) — a hardware-timing flake
      on this GTX 970, NOT a correctness signal. Gate on the suites your change
      touches, never on a hard-coded total.
    - **SUPERSEDED 2026-10-03 (later)** by a full run with road NAMING landed
      (`CorridorPlanner.ROAD_NAMES`, `RoadDef.display_name()`,
      `MapRoads.get_road_names()`, pause map labels all 19 corridors):
      `Overall Summary: 1006 test cases | 0 errors | 2 failures | 0 flaky | 0 skipped | 20 orphans`
      (exit 100), 95/95 suites in **18m23s**. BOTH failures are wall-clock
      flakes, neither touching roads or maps:
      (1) the same `test_perf_gate.gd` budget (16.7 ms);
      (2) `test_race_results.gd > test_win_results_overlay_matches_standings_total_and_best_lap`
      — `Expecting: 0.590000 in range between 0.741000 <> 0.841000`, a timing
      band that only slips under full-suite load. **It PASSES 8/8 in
      isolation**, so treat it as cross-suite interference, not a regression —
      re-run the suite alone before you investigate.
      **BOTH flakes are now FIXED in the tree**, so treat the diagnosis above as
      history, not as live guidance: the perf gate is now two-mode
      (`ULTRADRIVE_PERF_MODE`, see the PARALLEL GATE rules below) and
      `test_race_results.gd` now brackets `finish_race()` exactly instead of
      tolerating a wall-clock band. Neither is load-sensitive any more, and the
      `test_race_results.gd` defect was a genuine test bug — the band measured
      the test's own latency plus the HUD's save-file I/O — not cross-suite
      interference.
    - **TWO MORE FALSE-GREENS on this shell, both hit for real:**
      (a) GDUnit `-a` does NOT accept comma-separated paths. Passing six suites
      comma-joined prints `Given directory or file does not exists: ...` and then
      **`Exit code: 0` with zero tests run**. Chain the runs with `&` instead.
      (b) A suite aborts at its FIRST failure, so the "Executed test cases"
      denominator is lower than the number of `func test_` in the file and later
      tests are silently never executed. A suite reporting 16 cases when the file
      defines 19 is an ABORT, not a pass — check the counts against the file.
   - **PARALLEL GATE — P0 of `docs/plans/gdunit_parallel_execution_plan.md`
      SHIPPED 2026-10-04.** `tools/gdunit_parallel.py` shards the 95 suites
      across N headless Godot processes and merges the per-shard JUnit XML:
      `py tools\gdunit_parallel.py -j 4` (on the PC use `py` — `python`/`python3`
      are WindowsApps Store stubs there; on the laptop there is no `py` at all,
      see the SHELL section for the interpreter). MEASURED **264.3 s (4m24s)** wall
      vs the 18m23s serial baseline = **4.18x**, 95/95 suites,
      `1018 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 20 orphans`,
      0 false greens, exit 0 — an ALL-GREEN full run, and both prior
      wall-clock flakes did NOT fire. Because it passes `-c`, every shard ran
      its full case list (255/255, 255/255, 254/254, 254/254) with no fail-fast
      truncation, which is why the count rose 1006 → 1018. Artifacts (ignored
      by git) in `reports/parallel/`: `shard_<i>/report_1/` HTML + XML,
      `logs/`, `userdata/`, `merged-results.xml`, `summary.json`.
      Audited facts this depends on — do not re-derive:
      * `-a` is REPEATABLE and accumulates into one command; comma-joined paths
        do NOT work (that is false-green (a) above). One `-a` per suite.
      * Every shard MUST get its own `-rd`. gdUnit picks `report_<N>` by scanning
        the base dir for the highest index, and a finishing shard recursively
        DELETES lower-indexed siblings — a shared `-rd` interleaves reports and
        deletes live ones.
      * Per-shard `user://` isolation by overriding `APPDATA` (absolute!) in each
        child env; Godot resolves `user://` to
        `%APPDATA%/Godot/app_userdata/<name>` with NO canonicalization. This
        removed the need to serialize the 13 suites that write
        `user://saves/slot_N.json` through `save_manager.gd`'s shared fixed
        `.tmp` name, and keeps every byte off C:. A relative `APPDATA` silently
        resolves against the child CWD — always pass an absolute path.
        `--no-isolate-user-data` restores the serialized fallback.
      * Exit 101 (orphans only) counts as SUCCESS (baseline has 20 orphans).
        Runner exits: 0 clean, 1 test failures, 2 false green / env problem.
        **Exit 1 and exit 2 are different verdicts:** a shard with real failures
        prints `RED (n fail / m err)` and exits 1 — red but TRUSTWORTHY. The
        `!! FALSE GREEN` banner / exit 2 means the numbers cannot be believed.
        That RED path had never been exercised by a green run before; it is now
        VERIFIED, confirmed three times.
      * **PERF GATE HAS TWO MODES, and `ULTRADRIVE_PERF_MODE` picks one.** The
        16.7 ms `PerfBench.CONTRACT_FRAME_BUDGET_MS` VALUE is never loosened —
        only the GATE that enforces it is self-selecting. It engages only when
        the run's own fastest SUSTAINED row (`control_ms`) already met 16.7 ms,
        i.e. the box proved it can hold 60 Hz (**reference** mode). Otherwise the
        gate drops to **relative** mode and enforces only the same-run spread
        control: every sustained row within `1.35x` of the fastest sustained row
        of THAT run, floor `1.5` ms. Every run prints
        `[perf_gate] mode=... control_ms=... contract_ms=... load_budget_ms=...` —
        read `mode=` before believing a perf failure. Set
        `ULTRADRIVE_PERF_MODE=reference` to force the strict absolute gate on
        anyway (it will then fail, deliberately) or `=relative` to force it off;
        unset auto-detects. **COST, stated plainly:** in relative mode a
        regression that slows EVERY preset EQUALLY is undetectable — only a
        per-preset regression is. The reference rig never degrades, so it pays
        none of this cost. VERIFIED on a second, non-reference box (AMD Ryzen 3
        5300U): auto -> `mode=reference control_ms=7.00 load_budget_ms=50.1`
        3/3 pass exit 0; forced `relative` -> 3/3 pass; with the contract const
        temporarily `0.001` (reverted) auto -> `mode=relative` GREEN exit 0 while
        forced `reference` -> RED, 2 failures, exit 1.
      * **`test_race_results.gd` is NOT a wall-clock benchmark** and is NOT in
        `SERIAL_SUITES`. Its old `±0.05 s` band around a second read of a live
        monotonic clock was a genuine test bug — the HUD reads that clock once
        inside `finish_race()` and then does save-file I/O in `_submit_best_lap`,
        so the band measured the test's own latency plus disk I/O — and is now an
        exact bracket around the `finish_race()` call. Its problem was fixed, not
        isolated: nothing about parallel load can break it now.
      * gdUnit DOES write a JUnit `results.xml` per report dir, so merging is real.
      Flags, layout and false-green rules: `docs/GDUNIT_GATE.md`.
      STILL OPEN: shard balance is loose (walls 264/136/247/46 s — shard 1 is the
      critical path); the merged XML is NOT yet validated against a CI JUnit
      parser. Both are P1 (dynamic weights / Actions matrix).
      The runner launches N Godot processes at once: it is the ONE deliberate
      exception to "one Godot process at a time" — never run it beside another
      Godot process or another gate run.
    - **GDUnit CLI audit note:** `-a` with a value that matches nothing prints
      `Given directory or file does not exists:` and still exits 0. `--help`
      is `-help`; `-rd`/`-i` take exactly one value each (only `-a`/`-i`
      accumulate when repeated).
    GDUnit gotchas: it treats GDScript warnings as errors (e.g. `var x := some_func_returning_Variant()` fails to load) and its vector `is_equal_approx` requires a SAME-TYPE approx arg, not a float (`assert_that(vec).is_equal_approx(vec, Vector2(0.001, 0.001))`).

NOTE: if you run the GDUnit `-s` command ALONE (without the earlier headless
run), it may bail with exit 103/exit 1 "Headless mode is not supported". The
order above (plain --headless probe FIRST, then the -s run with the flag AFTER
the tool-script path) is what keeps it green. When in doubt, just run step 2
once, then step 3.

### Full-suite runs ALWAYS go to a background sub-agent (never block the main session)

The full suite takes ~10-15 min on the GTX 970. NEVER run it in the main
session's foreground and never wait on it: dispatch the gate (import probe then
one GDUnit `-s` run) as ONE background sub-agent, and dispatch the actual
feature work as OTHER sub-agents in PARALLEL in the same message — the main
session never blocks. One Godot process at a time: the import probe
(`--headless --import .` filter for `SCRIPT ERROR`/`Parse Error`) MUST run
before and inside the same background batch as the GDUnit `-s` run, and feature
sub-agents must NOT run Godot while the gate sub-agent is mid-suite. Both gate
commands run ONCE each — never loop or re-run "to confirm". Editing other files
while it runs is safe (the suite runs off the same tree but writes only
`_gdunit.txt`); read the gated result when the gate sub-agent reports back.

## BLENDER MCP (D4)

- Blender MCP bridges this session to a live Blender 4.5 (addon version [1,6],
  protocol 5). Tools are exposed as `blender-mcp_*` in sessions whose
  `opencode.json` includes the server; they appear AFTER opencode restarts.
- **This laptop (2026-09-18):** Blender 4.5.13 LTS is a portable ZIP at
  `C:\Blender\blender-4.5.13-windows-x64\blender.exe` (matches the reference box
  version; not installed to Program Files on this machine). The MCP bridge was
  renamed: the package is now **`mcp-for-blender`** (installed via
  `uvx mcp-for-blender`, uv at `C:\Users\IMOE001\.local\bin\uvx.exe`); the
  bundled addon was installed with
  `uvx mcp-for-blender install-addon --addons-dir "%APPDATA%\Blender Foundation\Blender\4.5\scripts\addons"`
  (module `blender_mcp`, verified: `addon_utils.enable('blender_mcp')` OK
  headless via `--background --python-expr`).
- MCP launcher entry (in `~/.config/opencode/opencode.jsonc`):
  `{"type":"local","command":["C:\\Users\\IMOE001\\.local\\bin\\uvx.exe","mcp-for-blender"],"environment":{"BLENDER_HOST":"localhost","BLENDER_PORT":"9876","DISABLE_TELEMETRY":"true"}}`.
  Env `BLENDER_HOST`/`BLENDER_PORT` default to localhost:9876.
- Verify with `opencode mcp list` (server should report Connected) and call
  `blender-mcp_get_addon_status` → expect `up_to_date`, protocol 5, Blender
  4.5.13. Check telemetry with `blender-mcp_get_addon_status` too.
  To CONNECT: launch `C:\Blender\blender-4.5.13-windows-x64\blender.exe`,
  enable "Interface: MCP for Blender" in Preferences→Add-ons, then in the 3D
  viewport `N` panel → MCP for Blender tab → Start MCP Server (port 9876).
- Known-good PNG → silhouette → model flow (used for the sports coupe &
  muscle/rally builds): generate in Blender via Hyper3D `rodin`, export glb to
  `assets/cars/`, consume as PackedScene.
- **CC0 car pipeline (2026-09-18):** handcrafted public-domain vehicles replace
  AI-scripted geometry (`docs/plans/cc0_car_assets_plan.md`). Kit at
  `assets/cars/cc0/kenney_car-kit/` (GLB only, `License.txt` = CC0). Integrated
  cars live at `assets/cars/cc0_*.glb` and resolve through `CarVisuals.
  WHEEL_GROUPS` (Kenney wheel nodes are top-level, named `wheel-front-left`,
  `wheel-back-right`, …), each with a `resources/cars/cc0_*.tres`. Kenney GLBs
  are nose-+Z in GLB space (same as the AI cars) and carry per-corner wheel
  meshes with an X axle — they use the stock `CAR_ORIENT` and wheel-spin
  conventions untouched. Gate: `tests/suites/test_cc0_cars.gd`.

## TERRAIN (D4)
- Mountain Pass ground is now a runtime-built `Terrain3D` (node named
  `GrassGround`): a 1024² height/color bake imported via `data.import_images()`
  anchored at region grid -512 (spacing 1.0, region_size 512) so the road loop
  (x/z ±80 m) sits inside regions -1..0. Every road point is recessed into a
  0.6 m "washbed" (SHOULDER_DISTANCE 8, BLEND_END_DISTANCE 40). Query heights
  with `Terrain3D.data.get_height()`. IMPORTANT: `import_images()` SNAPS its
  position to a region anchor (multiples of region_size), so a bake pane must
  start exactly on one — centered panes straddle a gap and return NaN half the
  loop (this bug was found + fixed in D4 in playtest).
- Foliage (`scripts/world/foliage.gd`) takes an optional
  `ground_height_provider: Callable(Vector2 -> float)` to sit on real terrain;
  falls back to Y 0 on flat circuits.

## OPEN WORLD SEEDING (D4/D5)
- `scenes/world/open_world_root.tscn` (WorldDriver root): runtime
  `Terrain3D` node + `TerrainSeeder` (`terrain_seeder.gd`). **Critical ordering:**
  setting `collision_mode` REINITIALIZES terrain data and RESETS region_size to
  256, so seeder._ready sets `collision_mode` FIRST, then
  `region_size = Terrain3D.SIZE_1024` (Terrain3DData has NO region_size property;
  data is null until node _ready). Hybrid async pipeline (D5): the PLAYER region
  sync-bakes on first push (~3.3 s as `_bake_sync`); neighbours stream from a
  worker Thread (Mutex/Semaphore), drained ≤ 2 regions/frame via `_process()`.
  `set_roads()` then `_push_player_position()` order matters so the bake
  conforms under roads BEFORE the first height lookup. Prefetch: `_prefetch_ring`
  (`PREFETCH_RADIUS 2`) re-primes after `set_roads()` resets `_ring_sig`.
  Region heats warp: never pass a >1-element `get_region_locations()` Array to a
  single `%s` format arg ("not all arguments converted"). Any script error
  during a headless diag leaves Godot hanging forever — always run a watchdog.
  NOTE: the Terrain3D `get_regionp`/`has_regionp`/`add_region_blankp`/
  `remove_regionp` signatures were VERIFIED green in D5 (streaming suite).
- `scripts/world/terrain_baker.gd` (pure RefCounted, deterministic): per-region
  seeded fBm base (region hash + 131/977, freq 0.003, 3 octaves), blended biome
  table (spawn/rolling/highland/fallback 2/6/20/1), alpine dome (5632,5632,
  amp 42, radius 5000), 3×3 blur, spawn plateau (128,128, r40, 2.2), clamp
  [-5,60]. Road conforming = `set_map(TYPE_HEIGHT)` bulk image path with
  **spatial clipping** (`_clip_chains`, AABB+margin) + per-texel segment-splat
  min (NOT a full-world O(cells×segments) field — that was the Wave 3 hang,
  126s/region → 2s). Roads are only wrapped as closed chambers when first/last
  points nearly touch (`_chain_is_closed`, ~2×avg spacing) so the open
  hub(128,128)→pass(3800,3200) connector never carves a phantom diagonal.
- Roads: `road_network.gd` (`add_road(points, width=8, closed=true)`,
  `get_roads()`, `is_on_road`) builds `track_builder.gd` meshes (`build_track`
  now takes `closed`; pass false for connector ribbons). `world_driver.gd`
  `_bootstrap_roads()` adds hub ring + pass connector + pass loop and calls
  `terrain_seeder.set_roads(...)` BEFORE the first `_push_player_position()`
  so the bake conforms under every road. `scenes/world/regions/mountain_pass_zone.tscn`
  is a lean instance of `mountain_pass.gd` with `build_own_ground`/
  `build_foliage`/`reposition_player` exports off (standalone scene defaults on).
- Cold open-world start used to be ≈ 35-40s (3×3×1024² sync bake, ~3.3s/region
  base floor); D5 made it ~3.3s to get driveable (player region sync) with the
  ring streaming async behind you. FastNoiseLite `get_image` bulk-noise is a
  possible ~4× cut but quantizes to 8-bit — not yet done.
- Minimap roads + pause map (D5): `scripts/ui/map_roads.gd` (static `MapRoads`:
  `resolve_road_source` finds the `road_network` group or tree-walks
  `get_roads()`, `compute_fit`, `world_to_screen`, `clip_circle`) is shared by
  `scripts/ui/minimap.gd` and `scripts/ui/world_map.gd` (class `WorldMap`, map
  overlay in `scenes/ui/pause_menu.tscn`). POI dots come from static
  `scripts/world/poi_registry.gd`. Roads silently no-op when no source exists.
- Open-world dressing: `scripts/world/prop_scatterer.gd` (PropScatterer —
  runtime MultiMesh props: guardrail/tent/power-pole/rock, built from fused
  primitives, rejection-sampled clear of roads via `is_on_road`, deterministic
  per seed) configurable per zone with `/self/` bridge presets.
- P0–P7 open-world seeding (2026-09-18/19) — **suite green at 263 tests / 0 errors /
  0 failures**. Plan: `docs/plans/open_world_seeding_plan.md` (§3.0 = execution
  contract, STATUS block at end of §2 = what shipped).

## GRAPHICS QUALITY (2026-09-18)
- The quality ladder in `scripts/ui/settings_menu.gd` (QUALITY_PRESETS: Low/
  Medium/High) is the single source of truth for environment + viewport quality.
- Scenes no longer bake in max post-FX: their `Environment` sub-resources ship
  OFF (SDFGI/SSAO/SSR/volumetric fog/glow), and `GameState` re-applies the
  ladder on boot and on every `change_scene` (`SettingsMenuScript.apply_to_scene_tree`).
- First-boot default is hardware-recommended: `SettingsMenuScript.default_quality_preset()`
  detects weak/integrated GPUs (Radeon iGPU, Intel UHD/HD, VGA/llvmpipe) → Low;
  discrete cards → Medium. `quality_preset` is persisted in the slot-0 save and
  restored in `GameState._ready`. Raising to High in Settings works on any machine.
  - **P3 surfaces:** `scripts/vehicle/surface_registry.gd` (class_name
    `SurfaceRegistry`) maps terrain/weather to a grip table the tyres read via
    `vehicle_physics.gd` / `tire_model.gd` hooks. Gate: `test_surface_grip`.
  - **P4 climate:** `autoload/day_night_driver.gd` (DayNightDriver autoload in
    project.godot — the game clock; `advance_time` uses **`fposmod`**, tests
    must assert with ≥0.01 tolerance) + `scripts/world/regional_climate.gd`
    (5 region bands, alpine year-round snow) + `weather_manager.gd` season/regional
    sampling. Gates: `test_regional_climate`, `test_weather_sun`.
  - **P5 discovery:** `scripts/world/world_discovery.gd` (WorldDiscovery —
    monotonic visited-segment bitset, XZ segment math, `is_revealed`,
    `try_snap_to_revealed`, SaveManager persistence under `SAVE_KEY`),
    `scripts/ui/map_roads.gd` (`MapRoads` adds `route_polyline`, `screen_to_world`,
    static `route_target`; from==to yields the full enclosing chain),
    `scripts/ui/world_map.gd` (grey→white reveal + click-to-fast-travel gated on
    revealed), `scripts/ui/minimap.gd`, `scripts/world/world_driver.gd` (teleport).
    Gates: `test_discovery`, `test_map_route`.
  - **P6 living-world:** `scripts/world/event_registry.gd` (EventRegistry.place —
    6 event families, time_attack_N per anchor), `scripts/world/living_world.gd`
    (traffic driver), `scripts/world/poi_registry.gd` (POIRegistry — base 5
    landmarks + 11 event markers appended lazily via `_load_events`; `0..6144`
    tile bounds check applies ONLY to base POIs — events sit on the real road net,
    x[−200..9702] z[−2944..8605]). `open_world_root.tscn` gets the `open_world`
    group. Gate: `test_event_placement`.
  - **P7 streaming dressing:** `scripts/world/region_dresser.gd` (RegionDresser —
    ring mirror with spawn/free budgeting, `band_density`, `band_visibility`
    culling via `visible_instance_count`), `scripts/world/terrain_seeder.gd`
    (region callbacks + `corridor_budget_locs` km→locs ladder, MAX 190),
    `scripts/world/prop_scatterer.gd` + `scripts/world/foliage.gd` per-region
    `configure_for_region` hooks. Gates: `test_streaming_dressing`.
  - **Gotcha:** foliages/props own several MultiMesh children (grass 700 + trees
    40 …); `get_instance_count()` / `get_visible_instance_count()` SUM across all
    children (first-child-only reads return 700 not 740). `RegionDresser.
    _apply_band_budget` builds `placed` from the summed counts.

## RACE LOOP (D6)
- `RaceManager` (autoload) owns race state: `queue_race(laps)` /
  `consume_pending_race()` bridge track-select (`laps_default` from the track
  registry) to the HUD — `race_ui.gd` consumes the pending lap count and calls
  `start_race(VehicleManager.get_all_cars(), laps)` on its first frame.
  Checkpoints are pooled from the `checkpoints` group through a cached
  `_all_checkpoints()` list invalidated on `GameState.scene_changed`.
- `checkpoint.gd` counts each vehicle once per armed cycle (an internal
  `_counted` map) instead of enter/leave edge detection; `reset()` re-arms.
  `lap_counter.gd` validates progression against the expected next index
  (wrap-around allowed) and tracks race/lap start times separately. Standings
  tie-break by lap, then checkpoint index, then distance to the next gate.
  Finish: `race_ui.gd` swaps the HUD to a FINISH banner with total time.
- Tested by `tests/suites/test_race_loop.gd` (14 tests) with `checkpoint_stub.gd`;
  kept leak-free via a suite `after_test` that sync-frees managed stub
  cars/checkpoints and resets RaceManager.

## PROJECT CONVENTIONS
- Runtime entry: `res://scenes/main.tscn`. Player on track:
  `res://scenes/vehicle/player_car.tscn` (VehiclePhysics, mass ~1100kg, 4×
  `Wheel*` children, `PlayerCarController` child with `_apply_visual()` swapping
  the CarBody glb per active car from `Garage.new_from_save().get_active_car()`).
- Cars are DOOM-style 3D: `assets/cars/*.glb` (sports_coupe, muscle_car,
  rally_hatch) each consumed as `PackedScene`; the player visual is the
  `SportsCoupe` instance with `CAR_ORIENT` (const Transform3D of a 180° Y
  rotation) so the nose faces forward. Chase camera: `scripts/camera/chase_camera.gd`.
- Career: `scripts/career/garage.gd` (Garage owns `_owned_cars`, `set_active_car`,
  saves via `SaveManager`). Garage UI: `scenes/ui/garage.tscn` + `scripts/ui/garage_ui.gd`.
- Progression classes: D/C/B/A/S via `car_config.gd` (`car_class`, mass, torque,
  gear_ratios, upshift/downshift kmh). Reverse (`-1`) is a real gear: drives
  backward, torque is flipped, capped at `max_reverse_speed_kmh` (25).
- Transmission (D5): `GameState.transmission_mode` is AUTO (default) or MANUAL
  (settings `%TransmissionOption`). Manual shifting on the controller:
  `shift_up` = physical button 3 (PS Triangle/Xbox Y), `shift_down` = button 0
  (PS X/Xbox A), keyboard E/Q; handbrake was moved to button 10 (RB/R1) to free
  the old Triangle binding. In MANUAL every gear change is player-input driven;
  in AUTO upshifts are RPM-based at `auto_shift_rpm_fraction` (0.92 × redline,
  so the rally car doesn't shift at ~2,850 rpm in 1st) and downshifts stay
  speed-table based; an over-rev guard rejects a downshift above `redline*1.05`.
- HUD: gauges are a Forza/GT-style cluster (`scripts/race/tachometer.gd`,
  `%Cluster` in `scenes/ui/hud.tscn`) driven by `scripts/race/race_ui.gd` from
  `car.get_drive_info()` (`speed_kmh`, `gear`, `rpm`) + config `idle_rpm`/
  `redline_rpm`/`car_class`.
- GDUnit structure: `functions` split into `pre_check`/`check_part_a`/`check_part_b`
  where the scene needs two frames; keep using `assert_that(...).is_equal`.
- The FUN files (the reasons the game exists) live in the playtest flows:
  garage→select car→drive; right-joystick orbit camera; FH5/GT7-style garage.
- Planning docs are version-controlled under `docs/` (gitignored `reports/`
  stays local): `docs/ROADMAP.md` (master roadmap; "No tech ceiling" — ambitions
  are never trimmed to Godot/current architecture, engine/tooling changes are in
  scope when they serve a goal), `docs/plans/*` (phase/feature gap-fill plans),
  `docs/research/*` (competitor + self-audit research). Read the roadmap section
  relevant to any new work before planning.
