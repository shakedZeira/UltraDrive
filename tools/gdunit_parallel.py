#!/usr/bin/env python3
"""Parallel GDUnit4 runner for UltraDrive (phase P0 of
docs/plans/gdunit_parallel_execution_plan.md).

Shards the discovered GDUnit4 suites across N headless Godot processes,
merges the per-shard JUnit XML into one report, and hard-fails on the
false greens this toolchain is famous for.

Suite weights come from RUNTIME DISCOVERY, not a static table: ``tests/``
is walked recursively and every ``*.gd`` file with at least one
``func test_`` is a suite, weighted by that count. Discovery is the single
source of truth, so adding or removing a suite needs no edit here (the
plan doc's 95-entry SUITE_WEIGHTS table was already stale, missed the 11
suites in the ``tests/`` root, and carried a duplicate key). The empty
``STATIC_WEIGHTS`` dict is an optional override consulted only for keys
that discovery actually found; it exists for P1's measured-duration
feedback and defaults to nothing so discovery stays authoritative.

GdUnit4 CLI facts this depends on (audited in addons/gdUnit4):
  * ``-a <path>`` is repeatable and accumulates into one command; a
    comma-joined value is NOT split and becomes one literal path.
  * An unknown ``-a`` path prints "Given directory or file does not
    exists:", discovers zero tests and exits 0 -- a false green.
  * Reports land in ``<-rd>/report_<N>/results.xml`` (JUnit, root element
    ``<testsuites>``), so every shard gets its own ``-rd``, the shard's own
    report dir is wiped before launch, and the XML is always globbed.
  * Exit codes: 0 clean, 100 failures/errors, 101 orphans only (a warning;
    our baseline has 20), 103 headless guard, 105 script errors.
  * Fail-fast is ON by default and truncates a suite's remaining cases,
    so ``-c`` is passed unless ``--fail-fast`` is given.
  * ``--ignoreHeadlessMode`` must come AFTER the tool-script path and a
    plain ``--headless --import .`` must succeed once before any ``-s``
    run, otherwise the engine bails 103; this tool runs the probe itself.
  * ``godot_path.bat`` exports GODOT_EXE_CONSOLE. The GUI-subsystem binary
    silently detaches under ``subprocess`` and returns nothing, so the
    resolved path is sanity-checked with ``--version`` before any shard
    launches. No drive letter is ever hardcoded.

Isolation: every shard gets a private ``user://`` tree by overriding APPDATA in
its child env. Verified on this box -- Godot resolves ``user://`` to
``%APPDATA%/Godot/app_userdata/<application/config/name>`` and does no
canonicalisation, so a per-child absolute APPDATA redirects it with zero
project changes. That matters twice over: it removes the save-slot contention
that autoload/save_manager.gd would otherwise cause (13 suites write
``user://saves/slot_N.json`` through one shared, fixed .tmp name), and it keeps
every byte off C:, which the un-overridden default would not. Pass
``--no-isolate-user-data`` to fall back to serializing CONTENDED_SUITES into one
trailing shard.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import re
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

# --- CONTENTION ---
# Suites that write user://saves/slot_N.json (directly or via autoload
# SaveManager / GameState setters / Garage / BestLapRecords). Only consulted when
# --no-isolate-user-data is given; with the default per-shard APPDATA redirect
# they are safe to run concurrently.
CONTENDED_SUITES: set[str] = {
    "test_best_lap_records",
    "test_camera_settings",
    "test_career_economy",
    "test_collectibles",
    "test_discovery",
    "test_event_rewards",
    "test_garage_tuning",
    "test_manual_transmission_default",
    "test_profile_slots",
    "test_reflection_probes",
    "test_rival_personalities",
    "test_save_manager",
    "test_speed_trap_visuals",
}

STATIC_WEIGHTS: dict[str, int] = {}

PROJECT_ROOT = Path(__file__).resolve().parent.parent
TESTS_DIR = PROJECT_ROOT / "tests"
GDUNIT_TOOL = "res://addons/gdUnit4/bin/GdUnitCmdTool.gd"
GODOT_PATH_BAT = "godot_path.bat"
DEFAULT_REPORTS_ROOT = "reports/parallel"
USER_DATA_SUBDIR = "userdata"

TEST_FUNC_RE = re.compile(r"^[ \t]*func[ \t]+test_", re.MULTILINE)
REPORT_DIR_RE = re.compile(r"^report_(\d+)$")
GODOT_VERSION_RE = re.compile(r"\b4\.\d")
SCRIPT_ERROR_MARKERS = ("SCRIPT ERROR", "Parse Error", "Failed to load")
MISSING_PATH_MARKER = "Given directory or file does not exists:"
NO_TESTS_MARKER = "No test cases found"

GDUNIT_EXIT_SUCCESS = 0
GDUNIT_EXIT_FAILURES = 100
GDUNIT_EXIT_ORPHANS = 101
GDUNIT_EXIT_HEADLESS = 103
GDUNIT_EXIT_SCRIPT_ERRORS = 105
GDUNIT_CLEAN_EXITS = (GDUNIT_EXIT_SUCCESS, GDUNIT_EXIT_ORPHANS)

EXIT_OK = 0
EXIT_TEST_FAILURES = 1
EXIT_PROBLEM = 2

MIN_JOBS = 1
MAX_JOBS = 8
SERIALIZED_SHARD = 0
STALE_XML_SLACK_SECONDS = 120.0
RULE = "=" * 78


@dataclass(frozen=True)
class Suite:
    name: str
    rel_path: str
    weight: int

    @property
    def stem(self) -> str:
        return self.name[:-3] if self.name.endswith(".gd") else self.name

    @property
    def res_path(self) -> str:
        return "res://" + self.rel_path.replace("\\", "/")

    @property
    def contended(self) -> bool:
        return self.stem in CONTENDED_SUITES


@dataclass
class Shard:
    index: int
    suites: list[Suite] = field(default_factory=list)
    serialized: bool = False

    @property
    def weight(self) -> int:
        return sum(suite.weight for suite in self.suites)

    @property
    def suites_run(self) -> int:
        return len(self.suites)

    @property
    def mode(self) -> str:
        return "serialized" if self.serialized else "parallel"


@dataclass
class JunitCounts:
    tests: int = 0
    failures: int = 0
    errors: int = 0
    skipped: int = 0
    time: float = 0.0

    def add_suite(self, element: ET.Element) -> None:
        self.tests += _int_attr(element, "tests")
        self.failures += _int_attr(element, "failures")
        self.errors += _int_attr(element, "errors")
        self.skipped += _int_attr(element, "skipped")
        self.time += _float_attr(element, "time")


@dataclass
class ShardResult:
    index: int
    serialized: bool
    suite_names: list[str]
    weight: int
    ran: bool = False
    timed_out: bool = False
    exit_code: int | None = None
    wall_seconds: float = 0.0
    counts: JunitCounts = field(default_factory=JunitCounts)
    results_xml: str | None = None
    log_path: str = ""
    false_green: bool = False
    false_green_reasons: list[str] = field(default_factory=list)

    @property
    def mode(self) -> str:
        return "serialized" if self.serialized else "parallel"

    @property
    def suites_run(self) -> int:
        return len(self.suite_names)

    def status(self) -> str:
        if not self.ran:
            return "skipped: no suites"
        if self.false_green:
            return "!! FALSE GREEN"
        if self.timed_out:
            return "TIMEOUT"
        if self.exit_code == GDUNIT_EXIT_ORPHANS:
            return "ok (orphans warn)"
        return "ok"


def _int_attr(element: ET.Element, name: str) -> int:
    raw = element.get(name)
    if raw is None:
        return 0
    try:
        return int(float(raw))
    except (TypeError, ValueError):
        return 0


def _float_attr(element: ET.Element, name: str) -> float:
    raw = element.get(name)
    if raw is None:
        return 0.0
    try:
        return float(raw)
    except (TypeError, ValueError):
        return 0.0


def discover_suites(tests_dir: Path) -> list[Suite]:
    suites: list[Suite] = []
    if not tests_dir.is_dir():
        return suites
    for path in sorted(tests_dir.rglob("*.gd"), key=lambda p: str(p).lower()):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        count = len(TEST_FUNC_RE.findall(text))
        if count < 1:
            continue
        rel_path = path.relative_to(PROJECT_ROOT)
        weight = count
        override = STATIC_WEIGHTS.get(path.name, STATIC_WEIGHTS.get(path.stem))
        if override is not None and override > 0:
            weight = int(override)
        suites.append(Suite(name=path.name, rel_path=str(rel_path), weight=weight))
    suites.sort(key=lambda suite: (-suite.weight, suite.name))
    return suites


def warn_static_weight_drift(suites: list[Suite]) -> None:
    known = {suite.name for suite in suites} | {suite.stem for suite in suites}
    stale = sorted(key for key in STATIC_WEIGHTS if key not in known)
    if stale:
        print(f"!! STATIC_WEIGHTS has {len(stale)} key(s) discovery did not find, "
              f"ignoring them: {', '.join(stale)}")


def select_only(suites: list[Suite], spec: str) -> list[Suite]:
    requested = [token.strip() for token in spec.split(",") if token.strip()]
    if not requested:
        raise ValueError("--only needs at least one suite filename")
    by_key: dict[str, Suite] = {}
    for suite in suites:
        for key in (suite.name, suite.stem, suite.rel_path.replace("\\", "/")):
            by_key[key.lower()] = suite
    picked: list[Suite] = []
    missing: list[str] = []
    for token in requested:
        suite = by_key.get(token.lower()) or by_key.get(token.lower().replace("\\", "/"))
        if suite is None:
            missing.append(token)
        elif suite not in picked:
            picked.append(suite)
    if missing:
        raise ValueError("--only did not match any discovered suite: "
                         + ", ".join(missing))
    picked.sort(key=lambda suite: (-suite.weight, suite.name))
    return picked


def build_shards(suites: list[Suite], jobs: int,
                 isolate_user_data: bool) -> list[Shard]:
    if isolate_user_data:
        pool = list(suites)
    else:
        contended = [suite for suite in suites if suite.contended]
        pool = [suite for suite in suites if not suite.contended]
    ordered = sorted(pool, key=lambda suite: (-suite.weight, suite.name))
    shards: list[Shard] = [Shard(index=index) for index in range(1, jobs + 1)]
    for suite in ordered:
        lightest = min(shards, key=lambda shard: (shard.weight, shard.index))
        lightest.suites.append(suite)
    shards = [shard for shard in shards if shard.suites]
    if not isolate_user_data:
        contended = [suite for suite in suites if suite.contended]
        serialized = Shard(index=SERIALIZED_SHARD, serialized=True)
        serialized.suites = sorted(contended,
                                   key=lambda suite: (-suite.weight, suite.name))
        if serialized.suites:
            shards.append(serialized)
    return sorted(shards, key=lambda shard: shard.index)


def shard_user_data_dir(user_data_root: Path | None, shard_index: int) -> Path | None:
    if user_data_root is None:
        return None
    return (user_data_root / f"shard_{shard_index}").resolve()


def build_shard_env(user_data_dir: Path | None) -> dict[str, str] | None:
    if user_data_dir is None:
        return None
    env = dict(os.environ)
    env["APPDATA"] = str(user_data_dir)
    return env


def resolve_godot(explicit: str | None) -> Path:
    if explicit:
        candidate = Path(explicit).expanduser()
        if candidate.is_file() or shutil.which(explicit):
            return candidate
        raise RuntimeError(f"--godot path does not exist: {explicit}")
    env_value = os.environ.get("GODOT_EXE_CONSOLE", "").strip()
    if env_value:
        candidate = Path(env_value).expanduser()
        if candidate.is_file():
            return candidate
        raise RuntimeError(f"GODOT_EXE_CONSOLE is set but not a file: {env_value}")
    if not (PROJECT_ROOT / GODOT_PATH_BAT).is_file():
        raise RuntimeError(
            f"cannot resolve Godot: no --godot, no GODOT_EXE_CONSOLE and "
            f"{GODOT_PATH_BAT} is missing from {PROJECT_ROOT}")
    command = ['cmd', '/v:on', '/c',
               f'call {GODOT_PATH_BAT} & echo !GODOT_EXE_CONSOLE!']
    completed = subprocess.run(command, cwd=str(PROJECT_ROOT),
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               encoding="utf-8", errors="replace", timeout=120)
    for line in (completed.stdout or "").splitlines():
        token = line.strip().strip('"')
        if token and Path(token).is_file():
            return Path(token)
    raise RuntimeError(
        "godot_path.bat did not export a usable GODOT_EXE_CONSOLE "
        f"(stdout was {(completed.stdout or '').strip()!r})")


def verify_godot(godot: Path) -> str:
    try:
        completed = subprocess.run([str(godot), "--version"], cwd=str(PROJECT_ROOT),
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   encoding="utf-8", errors="replace", timeout=120)
    except (OSError, subprocess.SubprocessError) as exc:
        raise RuntimeError(f"could not execute {godot} --version: {exc}") from exc
    banner = (completed.stdout or "").strip()
    if not banner or not GODOT_VERSION_RE.search(banner):
        raise RuntimeError(
            f"{godot} --version returned {banner!r} instead of a Godot 4.x "
            "banner; the GUI-subsystem binary detaches under subprocess and "
            "silently no-ops, which is a known false-green trap. Point "
            "--godot at the *_console.exe twin.")
    return banner.splitlines()[0].strip()


def run_import_probe(godot: Path, logs_dir: Path,
                     env: dict[str, str] | None = None) -> tuple[int, list[str], int]:
    log_path = logs_dir / "import_probe.log"
    command = [str(godot), "--headless", "--import", "."]
    try:
        completed = subprocess.run(command, cwd=str(PROJECT_ROOT),
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   encoding="utf-8", errors="replace", timeout=3600,
                                   env=env)
        output = completed.stdout or ""
        exit_code = completed.returncode
    except subprocess.TimeoutExpired as exc:
        output = _as_text(exc.stdout)
        exit_code = -1
    log_path.write_text(output, encoding="utf-8", errors="replace")
    hits = [line for line in output.splitlines()
            if any(marker in line for marker in SCRIPT_ERROR_MARKERS)]
    print("--- IMPORT PROBE ---")
    print(f"  {' '.join(command)}")
    print(f"  exit code : {exit_code}")
    print(f"  log       : {log_path}")
    if not output.strip():
        print("  !! probe produced NO output; suspect a detached GUI binary")
    if hits:
        print(f"  !! {len(hits)} SCRIPT ERROR / Parse Error line(s):")
        for line in hits[:20]:
            print(f"     {line.strip()}")
        if len(hits) > 20:
            print(f"     ... and {len(hits) - 20} more")
    else:
        print("  script errors : none")
    return exit_code, hits, len(output)


def _as_text(stream: object) -> str:
    if stream is None:
        return ""
    if isinstance(stream, bytes):
        return stream.decode("utf-8", errors="replace")
    return str(stream)


def find_results_xml(shard_dir: Path) -> Path | None:
    matches: list[tuple[int, Path]] = []
    for candidate in shard_dir.glob("report_*/results.xml"):
        found = REPORT_DIR_RE.match(candidate.parent.name)
        if found is None:
            continue
        matches.append((int(found.group(1)), candidate))
    if not matches:
        return None
    return max(matches, key=lambda item: item[0])[1]


def build_shard_command(shard: Shard, godot: Path, report_base: Path,
                        continue_on_failure: bool) -> list[str]:
    command = [str(godot), "--headless", "-s", GDUNIT_TOOL, "--ignoreHeadlessMode"]
    if continue_on_failure:
        command.append("-c")
    for suite in shard.suites:
        command += ["-a", suite.res_path]
    command += ["-rd", report_base.as_posix()]
    return command


def run_shard(shard: Shard, godot: Path, reports_root: Path,
              continue_on_failure: bool, timeout: float,
              user_data_root: Path | None = None) -> ShardResult:
    result = ShardResult(index=shard.index, serialized=shard.serialized,
                         suite_names=[suite.name for suite in shard.suites],
                         weight=shard.weight)
    if not shard.suites:
        return result
    shard_dir = reports_root / f"shard_{shard.index}"
    logs_dir = reports_root / "logs"
    log_path = logs_dir / f"shard_{shard.index}.log"
    shutil.rmtree(shard_dir, ignore_errors=True)
    shard_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)
    result.log_path = str(log_path)
    env = build_shard_env(shard_user_data_dir(user_data_root, shard.index))
    command = build_shard_command(shard, godot, shard_dir, continue_on_failure)
    started = time.time()
    print(f"[shard {shard.index}] launch ({shard.mode}) {result.suites_run} suites, "
          f"est {result.weight} tests", flush=True)
    timed_out = False
    try:
        completed = subprocess.run(command, cwd=str(PROJECT_ROOT),
                                   stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT,
                                   encoding="utf-8", errors="replace",
                                   timeout=timeout, env=env)
        output = completed.stdout or ""
        exit_code: int | None = completed.returncode
    except subprocess.TimeoutExpired as exc:
        output = _as_text(exc.stdout)
        exit_code = None
        timed_out = True
    except OSError as exc:
        output = f"orchestrator could not launch Godot: {exc}"
        exit_code = None
    wall = time.time() - started
    results_xml = None if timed_out else find_results_xml(shard_dir)
    if results_xml is not None and not _xml_is_fresh(results_xml, started):
        output += ("\n[orchestrator] results.xml predates this shard's launch, "
                   "treating it as absent\n")
        results_xml = None
    log_path.write_text(output, encoding="utf-8", errors="replace")
    result.ran = True
    result.timed_out = timed_out
    result.exit_code = exit_code
    result.wall_seconds = wall
    if results_xml is not None:
        result.results_xml = str(results_xml)
        result.counts = parse_junit(results_xml)
    result.false_green_reasons = detect_false_green(result, output)
    result.false_green = bool(result.false_green_reasons)
    print(f"[shard {shard.index}] done in {wall:.1f}s exit={exit_code} "
          f"tests={result.counts.tests} fail={result.counts.failures} "
          f"err={result.counts.errors} status={result.status()}", flush=True)
    return result


def _xml_is_fresh(results_xml: Path, started: float) -> bool:
    try:
        return results_xml.stat().st_mtime >= started - STALE_XML_SLACK_SECONDS
    except OSError:
        return False


def parse_junit(results_xml: Path) -> JunitCounts:
    counts = JunitCounts()
    try:
        root = ET.parse(results_xml).getroot()
    except (OSError, ET.ParseError):
        return counts
    for element in root:
        if element.tag == "testsuite":
            counts.add_suite(element)
    return counts


def detect_false_green(result: ShardResult, output: str) -> list[str]:
    reasons: list[str] = []
    if not result.ran:
        return reasons
    if result.timed_out:
        return reasons
    if result.results_xml is None:
        reasons.append("no results.xml was written under the shard report dir")
    elif result.counts.tests == 0:
        reasons.append("results.xml reports 0 tests")
    exit_code = result.exit_code
    if exit_code not in GDUNIT_CLEAN_EXITS:
        if exit_code is None:
            reasons.append("process produced no exit code")
        elif exit_code == GDUNIT_EXIT_FAILURES \
                and result.counts.failures == 0 and result.counts.errors == 0:
            reasons.append("exit 100 but the XML shows 0 failures and 0 errors "
                           "(bad CLI arguments, not real results)")
        elif exit_code in (GDUNIT_EXIT_HEADLESS, GDUNIT_EXIT_SCRIPT_ERRORS):
            reasons.append(f"environment error: exit {exit_code} "
                           + ("(headless guard tripped)" if exit_code == GDUNIT_EXIT_HEADLESS
                              else "(script errors during discovery)"))
        else:
            reasons.append(f"unexpected exit code {exit_code}")
    if MISSING_PATH_MARKER in output:
        reasons.append(f"'{MISSING_PATH_MARKER}' in shard output: an -a path "
                       "was rejected by the gdUnit scanner")
    if NO_TESTS_MARKER in output:
        reasons.append(f"'{NO_TESTS_MARKER}' in shard output")
    unique: list[str] = []
    for reason in reasons:
        if reason not in unique:
            unique.append(reason)
    return unique


def merge_junit(sources: list[Path], output: Path) -> tuple[JunitCounts, int]:
    merged = ET.Element("testsuites")
    merged.set("name", "ultradrive-gdunit-parallel")
    totals = JunitCounts()
    suite_nodes = 0
    for source in sources:
        try:
            root = ET.parse(source).getroot()
        except (OSError, ET.ParseError):
            continue
        for element in root:
            if element.tag != "testsuite":
                continue
            totals.add_suite(element)
            merged.append(element)
            suite_nodes += 1
    merged.set("tests", str(totals.tests))
    merged.set("failures", str(totals.failures))
    merged.set("errors", str(totals.errors))
    merged.set("skipped", str(totals.skipped))
    merged.set("time", f"{totals.time:.3f}")
    output.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(merged).write(output, encoding="utf-8", xml_declaration=True)
    return totals, suite_nodes


def wrap_names(names: list[str], indent: str, width: int = 76) -> list[str]:
    lines: list[str] = []
    current = ""
    for name in names:
        piece = name if not current else f"{current}  {name}"
        if current and len(indent) + 2 + len(piece) > width:
            lines.append(f"{indent}  {current}")
            current = name
        else:
            current = piece
    if current:
        lines.append(f"{indent}  {current}")
    return lines


def print_plan(shards: list[Shard], suites: list[Suite]) -> None:
    print("--- SHARD PLAN ---")
    for shard in shards:
        tag = f"shard {shard.index}"
        print(f"{tag}  [{shard.mode}]  {shard.suites_run} suites  "
              f"est {shard.weight} tests")
        for line in wrap_names([s.name for s in shard.suites], "      "):
            print(line)
    print(f"TOTAL  {len(suites)} suites  est {sum(s.weight for s in suites)} tests  "
          f"in {len(shards)} shard(s)")


def print_results(results: list[ShardResult], totals: JunitCounts,
                  wall_seconds: float, sources: int, merged_xml: Path,
                  summary_json: Path) -> None:
    print("--- SHARD RESULTS ---")
    header = (f"{'shard':<7}{'mode':<12}{'suites':>7}{'weight':>8}{'wall':>10}"
              f"{'tests':>8}{'fail':>6}{'err':>6}{'exit':>7}  status")
    print(header)
    print("-" * len(header))
    for result in results:
        exit_text = "n/a" if result.exit_code is None else str(result.exit_code)
        print(f"{result.index:<7}{result.mode:<12}{result.suites_run:>7}"
              f"{result.weight:>8}{result.wall_seconds:>9.1f}s"
              f"{result.counts.tests:>8}{result.counts.failures:>6}"
              f"{result.counts.errors:>6}{exit_text:>7}  {result.status()}")
    false_greens = [r for r in results if r.false_green]
    timeouts = [r for r in results if r.timed_out]
    print("-" * len(header))
    print(f"OVERALL  {len(results)} shard(s)  tests {totals.tests}  "
          f"failures {totals.failures}  errors {totals.errors}  "
          f"skipped {totals.skipped}  xml-time {totals.time:.1f}s  "
          f"wall {wall_seconds:.1f}s")
    print(f"         false greens {len(false_greens)}  timeouts {len(timeouts)}  "
          f"source XMLs merged {sources}")
    print(f"MERGED   {merged_xml}")
    print(f"SUMMARY  {summary_json}")


def build_summary(results: list[ShardResult], totals: JunitCounts,
                  wall_seconds: float, sources: int, merged_xml: Path,
                  summary_json: Path, exit_code: int,
                  godot: Path, version: str, probe: dict) -> dict:
    return {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "godot": str(godot),
        "godot_version": version,
        "project_root": str(PROJECT_ROOT),
        "merged_results_xml": str(merged_xml),
        "source_xml_count": sources,
        "totals": {
            "tests": totals.tests,
            "failures": totals.failures,
            "errors": totals.errors,
            "skipped": totals.skipped,
            "time": round(totals.time, 3),
            "wall_seconds": round(wall_seconds, 1),
        },
        "false_greens": len([r for r in results if r.false_green]),
        "timeouts": len([r for r in results if r.timed_out]),
        "exit_code": exit_code,
        "import_probe": probe,
        "shards": [
            {
                "index": result.index,
                "mode": result.mode,
                "ran": result.ran,
                "suites": result.suites_run,
                "suite_names": result.suite_names,
                "weight": result.weight,
                "wall_seconds": round(result.wall_seconds, 1),
                "exit_code": result.exit_code,
                "timed_out": result.timed_out,
                "tests": result.counts.tests,
                "failures": result.counts.failures,
                "errors": result.counts.errors,
                "skipped": result.counts.skipped,
                "xml_time": round(result.counts.time, 3),
                "results_xml": result.results_xml,
                "log": result.log_path,
                "false_green": result.false_green,
                "false_green_reasons": result.false_green_reasons,
                "status": result.status(),
            }
            for result in results
        ],
    }


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="gdunit_parallel",
        description="Shard UltraDrive's GDUnit4 suites across parallel headless "
                    "Godot processes and merge the JUnit XML.")
    parser.add_argument("-j", "--jobs", type=int, default=4,
                        help=f"parallel shards (clamped {MIN_JOBS}..{MAX_JOBS}, "
                             "plus one serialized shard)")
    parser.add_argument("--shard", type=int, default=None,
                        help="run ONLY this shard index (for a CI matrix)")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the shard plan and exit without launching Godot")
    parser.add_argument("--only", default=None,
                        help="comma-separated suite filenames to run (smoke subset)")
    parser.add_argument("--reports-root", default=DEFAULT_REPORTS_ROOT,
                        help=f"report base dir, default {DEFAULT_REPORTS_ROOT}")
    parser.add_argument("--timeout", type=float, default=3600.0,
                        help="per-shard timeout in seconds, default 3600")
    parser.add_argument("--godot", default=None,
                        help="path to the Godot *_console.exe binary; default "
                             "GODOT_EXE_CONSOLE or godot_path.bat")
    parser.add_argument("--no-import", dest="run_import", action="store_false",
                        default=True,
                        help="skip the --headless --import probe (it is required "
                             "once before any -s run or the engine bails 103)")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--continue", dest="continue_on_failure", action="store_true",
                      default=True,
                      help="pass -c so a suite runs every case after a failure "
                           "(default)")
    mode.add_argument("--fail-fast", dest="continue_on_failure",
                      action="store_false",
                      help="omit -c; gdUnit stops a suite at its first failure")
    user_data = parser.add_mutually_exclusive_group()
    user_data.add_argument("--isolate-user-data", dest="isolate_user_data",
                           action="store_true", default=True,
                           help="give every shard a private user:// by overriding "
                                "APPDATA in its child env (default)")
    user_data.add_argument("--no-isolate-user-data", dest="isolate_user_data",
                           action="store_false",
                           help="share one user:// and serialize the "
                                "save-contention suites into a trailing shard")
    return parser.parse_args(argv)


def resolve_reports_root(value: str) -> Path:
    candidate = Path(value).expanduser()
    if not candidate.is_absolute():
        candidate = PROJECT_ROOT / candidate
    resolved = candidate.resolve()
    if PROJECT_ROOT not in resolved.parents and resolved != PROJECT_ROOT:
        print(f"!! --reports-root {resolved} is outside the project root; "
              "reports and logs will be written there")
    return resolved


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    print(RULE)
    print(" GDUnit4 parallel runner - UltraDrive")
    print(RULE)
    print(f" project root  : {PROJECT_ROOT}")
    print(f" tests root    : {TESTS_DIR}")
    reports_root = resolve_reports_root(args.reports_root)
    print(f" reports root  : {reports_root}")
    jobs = max(MIN_JOBS, min(MAX_JOBS, args.jobs))
    if jobs != args.jobs:
        print(f" jobs          : {args.jobs} clamped to {jobs}")
    elif args.isolate_user_data:
        print(f" jobs          : {jobs} parallel shards, no serialized shard")
    else:
        print(f" jobs          : {jobs} parallel + 1 serialized")
    print(f" fail-fast     : {'disabled (-c passed)' if args.continue_on_failure else 'ENABLED (omit -c)'}")
    print(f" import probe  : {'skipped (--no-import)' if args.run_import else 'enabled'}")
    user_data_root: Path | None = None
    if args.isolate_user_data:
        user_data_root = (reports_root / USER_DATA_SUBDIR).resolve()
        print(f" user://       : isolated per shard under {user_data_root}")
    else:
        print(f" user://       : SHARED; {len(CONTENDED_SUITES)} save-touching "
              f"suite(s) serialize into shard {SERIALIZED_SHARD}")

    suites = discover_suites(TESTS_DIR)
    if not suites:
        print("!! no suites discovered under "
              f"{TESTS_DIR} (no *.gd with func test_); nothing to do")
        return EXIT_PROBLEM
    if args.only:
        try:
            suites = select_only(suites, args.only)
        except ValueError as exc:
            print(f"!! {exc}")
            return EXIT_PROBLEM
    else:
        warn_static_weight_drift(suites)
    print(f" suites        : {len(suites)} discovered, "
          f"{sum(s.weight for s in suites)} test functions")
    contended_count = len([s for s in suites if s.contended])
    if args.isolate_user_data:
        print(f" contended     : {contended_count} save-touching suite(s) "
              f"-> all safe to parallelize (APPDATA isolated)")
    else:
        print(f" contended     : {contended_count} save-touching suite(s) -> shard "
              f"{SERIALIZED_SHARD} (runs alone, LAST)")

    shards = build_shards(suites, jobs, args.isolate_user_data)
    print_plan(shards, suites)
    if args.dry_run:
        print("dry run: nothing launched")
        return EXIT_OK
    if args.shard is not None:
        valid = [shard.index for shard in shards]
        if args.shard not in valid:
            print(f"!! --shard {args.shard} does not exist for -j {jobs}; "
                  f"valid shard indices: {valid} (use the same -j in every CI job)")
            return EXIT_PROBLEM
        selected = [shard for shard in shards if shard.index == args.shard]
        if args.shard == SERIALIZED_SHARD:
            print(f"running only shard {SERIALIZED_SHARD}: the serialized "
                  "save-contention shard")
        print(f"running only shard {args.shard}: {selected[0].suites_run} suites, "
              f"est {selected[0].weight} tests")
        shards = selected

    try:
        godot = resolve_godot(args.godot)
        version = verify_godot(godot)
    except RuntimeError as exc:
        print(f"!! {exc}")
        return EXIT_PROBLEM
    print(f" godot         : {godot}")
    print(f"   --version  : {version}")

    reports_root.mkdir(parents=True, exist_ok=True)
    logs_dir = reports_root / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)
    if user_data_root is not None:
        shutil.rmtree(user_data_root, ignore_errors=True)
        user_data_root.mkdir(parents=True, exist_ok=True)
    probe_env = build_shard_env(
        (user_data_root / "probe").resolve() if user_data_root else None)
    probe = {"ran": False}
    if args.run_import:
        probe_exit, probe_hits, probe_bytes = run_import_probe(godot, logs_dir,
                                                               env=probe_env)
        probe = {"ran": True, "exit_code": probe_exit,
                 "script_error_lines": len(probe_hits),
                 "output_bytes": probe_bytes,
                 "log": str(logs_dir / "import_probe.log")}
        if probe_hits:
            print(f"   note: {len(probe_hits)} script-error line(s) above. Shard "
                  "exit codes are the authority -- a shard that actually trips "
                  "105 is reported as FALSE GREEN. Editor-plugin-only errors "
                  "(e.g. addons/terrain_3d) are benign.")

    parallel = [shard for shard in shards if not shard.serialized]
    serialized = [shard for shard in shards if shard.serialized]
    results: list[ShardResult] = []
    started = time.time()
    if parallel:
        print(f"--- LAUNCH {len(parallel)} shard(s) CONCURRENTLY "
              f"(threads driving subprocesses) ---")
        with concurrent.futures.ThreadPoolExecutor(
                max_workers=len(parallel)) as pool:
            futures = [pool.submit(run_shard, shard, godot, reports_root,
                                   args.continue_on_failure, args.timeout,
                                   user_data_root)
                       for shard in parallel]
            for future in concurrent.futures.as_completed(futures):
                results.append(future.result())
    else:
        print("--- no parallel shards to launch ---")
    if serialized:
        print("--- now the SERIALIZED save-contention shard, alone (nothing else "
              "is running: these suites share user://saves/slot_N.json) ---")
        for shard in serialized:
            results.append(run_shard(shard, godot, reports_root,
                                     args.continue_on_failure, args.timeout,
                                     user_data_root))
    wall_seconds = time.time() - started
    results.sort(key=lambda result: result.index)

    sources: list[Path] = []
    for result in results:
        if result.results_xml:
            sources.append(Path(result.results_xml))
    merged_xml = reports_root / "merged-results.xml"
    totals, suite_nodes = merge_junit(sources, merged_xml)
    summary_json = reports_root / "summary.json"

    false_greens = [result for result in results if result.false_green]
    timed_out = [result for result in results if result.timed_out]
    for result in false_greens:
        print(RULE)
        print(f" !! FALSE GREEN  shard {result.index} ({result.mode})")
        print(f"    log        : {result.log_path}")
        print(f"    exit code  : {result.exit_code}")
        print(f"    xml        : {result.results_xml}")
        for reason in result.false_green_reasons:
            print(f"    reason     : {reason}")
        print(RULE)
    for result in results:
        if result.timed_out:
            print(f"!! shard {result.index} TIMED OUT after "
                  f"{result.wall_seconds:.0f}s (--timeout {args.timeout:.0f}); "
                  "it was killed and its results are untrustworthy")

    print_results(results, totals, wall_seconds, len(sources), merged_xml,
                  summary_json)
    print(f"         merged <testsuite> nodes {suite_nodes}")

    if false_greens or timed_out or totals.tests == 0 or suite_nodes == 0:
        exit_code = EXIT_PROBLEM
    elif totals.failures > 0 or totals.errors > 0:
        exit_code = EXIT_TEST_FAILURES
    else:
        exit_code = EXIT_OK

    summary = build_summary(results, totals, wall_seconds, len(sources),
                            merged_xml, summary_json, exit_code, godot, version,
                            probe)
    summary["user_data_isolation"] = (
        str(user_data_root) if user_data_root is not None else "shared")
    summary_json.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(f"EXIT {exit_code}"
          + ("" if exit_code == EXIT_OK else
             "  (1 = test failures, 2 = false green / environment problem)"))
    return exit_code


if __name__ == "__main__":
    sys.exit(main())