# HANDOFF — Barcelona Rallycross (GT7 track build #2)

**Status: STOPPED 2026-10-17 00:32 — the implementation sub-agent was CANCELLED
by the user with the build's FILES ~done (P0/P1/P3) and its VERIFICATION 0% done.**
See §4 for the live-verified checklist: layout, track script, scene, dressing,
`barcelona_rx` registry entry + 3 pins and the `_layout` suite are all on disk.
Still owed when it was killed: the `_track` / `_dressing` / `_barriers` suites,
P2 verification, P4 and P5. **No Godot run happened after the last file was
written, so none of it has ever been compiled, imported or executed**, and
**nothing is committed**. The layout bake the shared race-tab task depends on has
**never produced a single JSON** (§7) — `resources/ui/track_layouts/` is empty
while **four** layouts are registered.

**Resume point:** read §4 (what exists, and what is unverified), then §5 → §6 →
§7. Treat §7 as the first thing to fix, not the last: the race-tab suites are
expected to be RED *before* Barcelona's own tests even run.

- Repo: `https://github.com/shakedZeira/UltraDrive.git`, branch `master`
- Working dir on this machine: `D:\AI Projects\UltraDrive`
- Engine: Godot **4.7.2.stable.official** (always resolve via `godot_path.bat`,
  use `%GODOT_EXE_CONSOLE%` — the GUI binary detaches and false-greens)
- Full plan (authoritative, 691 lines): **`docs/plans/track_barcelona_rallycross.md`**
- Precedent (read it, build #1): `docs/plans/track_northern_isle_speedway.md`
- Expected test baseline at plan time: **1,146 cases, all green** (RTK: gate on
  zero NEW failures, not on an absolute total)

---

## 1. What this work is

Ship the **next-shortest not-yet-implemented GT7 track** as a 4th
`TrackRegistry` layout. Northern Isle Speedway (rank 1, 900 m) shipped
2026-10-15, so the next in `docs/research/gt7_tracks.md` "Shortest tracks by
length" is:

> **Rank 2 — Circuit de Barcelona-Catalunya · Rallycross · Spain · Dirt · 1,133 m**
> (master-table row #15; one of only two rallycross layouts in GT7)

It is the **first track that rides on build #1's capabilities instead of
extending them**: `RoadDef.bank_angles` / `show_lane_dividers` already exist,
`Tier.DIRT` + `Surface.GRAVEL` already exist, so there is **no shared-tooling
phase and no shared-file change** (unlike build #1, which had to grow
`TrackBuilder._frame`).

---

## 2. The contract (do not drift from this)

| Key | Value |
|---|---|
| registry id | `barcelona_rx` |
| `display_name` | `Barcelona Rallycross` |
| `scene_path` | `res://scenes/track/barcelona_rx.tscn` |
| `laps_default` | `3` (~60 s dirt lap ⇒ ~3 min race) |
| `difficulty` | `D` |
| `circuit_type` | `DIRT RX` |

Geometry constants (asserted by the layout suite): `TARGET_PERIMETER = 1133.0`,
`WIDTH = 12.0`, `TOTAL_POINTS = 400`, `CP_STRIDE = 50`,
`CHECKPOINT_COUNT = 8`, `START_LINE_INDEX = 7`, `ROAD_BASE_Y = 0.15`.
Surface: `RoadDef.make(RoadDef.Tier.DIRT, road_points, "barcelona_rx-dirt", true, …)`
with `Surface.GRAVEL`, **no rails**, two jumps (crest 1.0 / 0.8) and two 7°
sine-eased berms declared as tables.

**Pins are load-bearing, not cosmetic** (three `test_race_menu_map.gd` tests go
red otherwise — plan §2.5/§6.8):

```gdscript
"barcelona": {  # REPOINTED + RELABELLED (was -> northern_isle)
    "label": "Barcelona Rallycross",
    "lat": 41.5700, "lon": 2.2611,
    "region": REGION_WORLD, "track_id": "barcelona_rx", "host": "Spain",
},
"holjes": { … "track_id": "barcelona_rx", "host": "Sweden" },   # NEW
"loheac": { … "track_id": "barcelona_rx", "host": "France" },   # NEW
```

Invariants that must hold: first three pins stay Israeli `home_*`; WORLD pins
30 → 32 (≥30); distribution oval 6 / mountain_pass 15 / northern_isle 14 /
barcelona_rx 3 of 38 (each ≥3, each ≤50 %); no other pin's `track_id` changes.
`tracks` and `pins` stay separate dictionaries (the `track_registry.gd:44-55`
design note).

---

## 3. Scope decisions already made (don't re-litigate)

- **Dirt grip is GRAVEL grip (0.85/0.80), not the table's `DIRT` key
  (0.80/0.75).** `TIER_SURFACE[4] = GRAVEL` is the only tier→surface path, so a
  road can never classify as `DIRT`. Shipping as-is is correct at zero
  shared-file cost; remapping the tier would re-feel **every** open-world dirt
  road. **Explicit non-goal** (plan §6.1) — do not "fix" the grip table here.
- **A dedicated `scripts/track/rx_dressing.gd`, not a refactor of
  `oval_dressing.gd`** — the latter is hard-wired to `NorthernIsleLayout`, and
  build #1's 4 suites must stay green (plan §2.4/§6.7).
- **Ground bake** = build #1's structure generalized to two blend sides (build
  #1 assumed a one-sign oval).
- **Do not touch** the consumers' code (plan §7): car assets/materials, camera
  scripts, garage UI, **track-select/race-menu UI**, vehicle audio,
  `scripts/world/spline.gd` (keep the closed Catmull-Rom sampler private to the
  new layout class). Those read the registry dynamically — the data is enough.

---

## 4. Live-verified state of the working tree (2026-10-17)

Checked directly, not assumed:

| Artifact | State |
|---|---|
| `docs/plans/track_barcelona_rallycross.md` | **PRESENT**; its §8 STATUS was hand-corrected at stop (the sub-agent never marked a phase) |
| `scripts/track/barcelona_rx_layout.gd` | **PRESENT** (17,662 B, 00:19) — **never compiled** |
| `tests/suites/test_barcelona_rx_layout.gd` | **PRESENT** (20,465 B, 00:20) — **never executed** |
| `scripts/track/barcelona_rx.gd` | **PRESENT** (24,471 B, 00:27) — **never compiled** |
| `scenes/track/barcelona_rx.tscn` | **PRESENT** (4,118 B, 00:28) — **never imported** |
| `scripts/track/rx_dressing.gd` | **PRESENT** (25,374 B, 00:31) — **never compiled** |
| `track_registry.gd` | **EDITED** — `"barcelona_rx"` entry at `:29` (3 laps / D / `DIRT RX`), `barcelona` repointed at `:220`, new `holjes` `:225` / `loheac` `:230` pins — i.e. §2's pin contract exactly |
| `tests/test_track_system.gd:5` | **EDITED** — `[oval, mountain_pass, northern_isle, barcelona_rx]` |
| `tests/suites/test_barcelona_rx_track.gd` / `_dressing.gd` / `_barriers.gd` | **not present** — the three suites P1/P3 are gated on were never written |
| `docs/ROADMAP.md` Barcelona note (P5) | **absent** (ROADMAP.md carries edits from earlier tasks, but no `barcelona` string) |
| P2 verification, P4 race-flow polish | **not started** |

Every one of those files was written **after** this session's last Godot run, so
**nothing has been parsed by the engine** — treat a load/parse error as likely,
not surprising. (File tails were spot-checked: not truncated.)

So: **the files for P0/P1/P3 exist; the verification for all of it is missing.**
First action on resume: run the import probe (§6) and the `_layout` suite against
what is on disk — the sub-agent only re-checked the geometry **offline, in
Python** (`_rx_verify.py`, a mirror of the layout math using the same constants
and control points; now parked at `reports\_rx_verify_layout_mirror.py` since it
was the only record of its measurements). Repair what fails, write the three
missing suites, then finish P2/P4/P5. If something exists that this table lists
as absent, verify it in place, and update the plan's §8 STATUS truthfully.

> **Working-tree warning:** this repo has a large amount of **uncommitted work
> from prior sessions** (garage brands, HUD power/torque, main-menu video bg,
> race-menu map, R35 glass/lights, and the four 2026-10-16 fix tasks below).
> Never `git add -A` (`.uid` files are gitignored), never revert files you don't
> own, and edit `track_registry.gd` / `tests/test_track_system.gd`
> **additively on top** of the existing modifications.
>
> **Scratch-file debt — CLEANED at the stop (2026-10-17 00:32).** The cancelled
> implementation sub-agent had left 15 `_rx_*` files in the repo ROOT
> (`_rx_probe.py`, `_rx_probe2..14.py`, `_rx_t.py`, `_rx_verify.py`) plus this
> session's `_bake2.txt` / `_st.txt` — none gitignored. All are deleted;
> `_rx_verify.py` (a Python mirror of `barcelona_rx_layout.gd`'s math — same
> constants, vertices and bank/jump tables, and **the only record of the
> sub-agent's geometry measurements**, since the layout itself was never compiled)
> was preserved to gitignored **`reports\_rx_verify_layout_mirror.py`**. If you
> want to trust the control points before running Godot, that file is where the
> offline check lives.
>
> **Landed after this handoff was first written (unrelated to Barcelona, do not
> revert):** `scripts/vehicle/car_visuals.gd` `resolve_wheel_nodes()` is now
> depth-independent (Godot wraps single-root glTF car scenes, which had silently
> broken wheel spin/steer for the starter/muscle/rally cars), and
> `tools/gen_track_layouts.gd` no longer references the `RaceManager` autoload by
> bare name (see §7).

---

## 5. Deliverables (from plan §4, phases P0–P5)

| Phase | Deliverable | Gate to run |
|---|---|---|
| **P0** | `scripts/track/barcelona_rx_layout.gd` — authored control points → closed Catmull-Rom, XZ-normalized to 1,133 m, arc-resampled to 400 pts | `tests/suites/test_barcelona_rx_layout.gd` (pure math, no scene) |
| **P1** | `scripts/track/barcelona_rx.gd` + `scenes/track/barcelona_rx.tscn` (node-for-node the build-#1 scene set) + registry entry + the 3 pin edits + `tests/test_track_system.gd:5` one-liner | `test_barcelona_rx_track.gd` (scene/registry half) |
| **P2** | `_build_ground()` / `_build_hint_field()` + foliage in `barcelona_rx.gd` | the ground half of `test_barcelona_rx_track.gd` |
| **P3** | `_build_barrier_colliders()` + `scripts/track/rx_dressing.gd` | `test_barcelona_rx_dressing.gd`, `test_barcelona_rx_barriers.gd` |
| **P4** | Race-flow polish (results overlay → best lap under `("barcelona_rx", class)` → restart) | manual playtest checklist (plan §5, bottom) |
| **P5** | Full gate + ROADMAP note + plan §8 STATUS + `graphify update .` | §6 below |

Test-suite contents are specified in plan §5 — copy the shape of the
`test_northern_isle_*` suites and honour: warnings are **errors** (type every
local), `assert_that(x).is_equal(y)`, vector `is_equal_approx` needs a
**same-type** approx arg, and `after_test` must reset `RaceManager`
(`_checkpoints_dirty`, `rival_roster`, `_participants`, `_lap_counters`,
`rival_centerline`), drain `RaceManager.consume_pending_race()`, and free
managed nodes.

**Existing suites needing edits (only these):**
- `tests/test_track_system.gd:5` — add `"barcelona_rx"` to `contains_exactly`.
- `tests/suites/test_race_menu_map.gd` — **no edit if** §2's pin plan lands
  (re-run it to prove the pin invariants); otherwise it goes red on
  `:197-207`, `:219-226`, `:228-229`.
- `test_best_lap_records.gd` — dynamic, no edit.

---

## 6. Commands

One Godot process at a time — never beside another Godot run, and never beside
the parallel gate.

```bat
REM 1. Resolve + import probe (expect ZERO "SCRIPT ERROR" / "Parse Error")
cmd /v:on /c "call godot_path.bat & set APPDATA=D:\AI Projects\UltraDrive\reports\userdata_handoff & !GODOT_EXE_CONSOLE! --headless --import . 2>&1"

REM 2. Target the new suites (repeat -a; comma-joined -a silently runs 0 tests)
cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE! --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/suites/test_barcelona_rx_layout.gd -a res://tests/suites/test_barcelona_rx_track.gd -a res://tests/suites/test_barcelona_rx_dressing.gd -a res://tests/suites/test_barcelona_rx_barriers.gd -a res://tests/suites/test_race_menu_map.gd -a res://tests/suites/test_northern_isle_layout.gd > _gdunit_rc.txt 2>&1"

REM 3. Whole tree (preferred: the parallel runner, PC uses `py`)
py tools\gdunit_parallel.py -j 4
```

Confirm `_gdunit.txt` / `_gdunit_rc.txt` is **not 0 bytes** before trusting it;
integrate the R35/garage/audio/race-tab fix tasks landing on 2026-10-16, so a
run may legitimately show those suites' new cases too.

**Verified runner — use this, not the raw commands above.**
`reports\_headless_verify.bat <godot args…>` (gitignored) resolves the console
binary through `godot_path.bat`, forces `APPDATA=D:\AI Projects\UltraDrive\reports\userdata_verify` (D:-only rule) and prints a `[helper]` banner. The `cmd /v:on /c "…"` forms above are correct in a real console but **the agent harness escapes their quotes**, so the .bat is what actually works:

```bat
reports\_headless_verify.bat --headless --import .
reports\_headless_verify.bat --headless -s res://tools/gen_track_layouts.gd > _bake.txt 2>&1
reports\_headless_verify.bat --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/suites/test_barcelona_rx_layout.gd > _gdunit_rc.txt 2>&1
```

**A headless GDScript error HANGS the process — it does not exit** (hit for real:
the bake aborted at `gen_track_layouts.gd:73` and then sat there until it was
killed). Run every Godot command as a background job with a timeout, check
`tasklist | findstr /i godot` before starting the next one so you never end up
with two engines at once, and keep
`taskkill /f /im Godot_v4.7.2-stable_win64_console.exe` ready.

**Stop state 2026-10-17 00:32:** no Godot process running; nothing committed; the
root scratch (`_rx_probe*.py`, `_rx_t.py`, `_bake2.txt`, `_st.txt`) has been
deleted and `_rx_verify.py` parked in gitignored `reports/`; `git status --short`
is back to "only the project's own uncommitted work". **`graphify update .` was
deferred** — run it once the tree is final (the `*.gd` files are outside the
graph anyway, but the handoff/plan/ROADMAP docs are in it).

---

## 7. CRITICAL cross-task integration note — re-run the layout bake

A concurrent 2026-10-16 task ("race tab track layout + event details",
`docs/plans/race_tab_track_layout_event_details.md`) added **baked per-layout
preview data** plus a **canary test** that asserts
**every `TrackRegistry` layout has baked preview data**.

Consequence: **the moment you register `barcelona_rx`, that canary goes red**
until you re-run the bake generator once:

```bat
cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE! --headless -s res://tools/gen_track_layouts.gd"
```

It writes `resources/ui/track_layouts/<track_id>.json` for every registry layout
(iterate order, no hardcoded ids). Run it **after** the registry entry exists,
then run `--headless --import .`, then
`tests/suites/test_race_layout_preview.gd`. Do this in the same session as the
final gate — the JSONs are generated artifacts and must match the shipped
registry, not the pre-Barcelona one.

> **Traps hit for real (2026-10-17) — the bake tool needed three fixes before it
> could run at all (and it has still never run successfully):**
> 1. It referenced the `RaceManager` autoload by **bare name**, which is a
>    **compile error in `-s` mode**: `Identifier not found: RaceManager`. In `-s`
>    mode Godot DOES instantiate the autoloads as `/root` children but does NOT
>    register their identifiers for compilation. The tool now reaches it via
>    `root.get_node_or_null("/root/RaceManager")` (and aborts rather than baking
>    bogus `rival_centerline: false` flags if it is ever missing).
> 2. It instantiates every track scene, so it runs real terrain bakes (the
>    mountain pass) — allow minutes and never run it beside another Godot process.
> 3. It called `RaceManager.set_rival_centerline([])`, but that parameter is
>    `Array[Vector3]` and a bare `[]` literal is an **untyped** Array → runtime
>    `Invalid type in function 'set_rival_centerline'`, aborting the script on
>    track 1 (`gen_track_layouts.gd:73`, seen 2026-10-17). Fixed by declaring a
>    typed local once (`var no_centerline: Array[Vector3] = []`) and reusing it
>    per track. **That fix has never been run** — the bake has not written a
>    single file yet; `resources/ui/track_layouts/` is still EMPTY. Expect to
>    iterate on the first real run.
>
> Before Barcelona registers, the bake covers the 3 existing layouts only; that
> is why the canary goes red the moment `barcelona_rx` lands and you must re-run
> it (one extra `-s` run, ~1 min). **Note the current state: `barcelona_rx` HAS
> now landed, so 4 layouts are registered and 0 JSONs exist** — so
> `test_race_layout_preview.gd` (and the JSON-dependent cases of
> `test_race_menu_map.gd` / `test_track_system.gd`) are expected to be RED
> *before* Barcelona's own suites are even written. Run the bake and re-verify
> the race-tab suites **first**; do not attribute those failures to Barcelona.

Also note `resources/ui/track_layouts/**` is **owned by the UI task** (do not
hand-edit it), and the UI reads the registry **dynamically** — no UI code change
is needed for a new track.

---

## 8. Resume prompt (paste into a fresh agent)

> Implement `docs/plans/track_barcelona_rallycross.md` (GT7 track build #2,
> `barcelona_rx`, 1,133 m dirt Rallycross). Read that plan **and**
> `docs/HANDOFF_BARCELONA_RALLYCROSS.md` first, then
> `docs/plans/track_northern_isle_speedway.md` as the template, then the shipped
> `scenes/track/northern_isle.tscn` + its scripts. Work the phases P0→P5 (§5 of
> the handoff / §4 of the plan).
> **Beware: a previous run was CANCELLED mid-flight and left P0+P1+P3 FILES on
> disk that have never been compiled or executed** —
> `scripts/track/barcelona_rx_layout.gd`, `scripts/track/barcelona_rx.gd`,
> `scenes/track/barcelona_rx.tscn`, `scripts/track/rx_dressing.gd`,
> `tests/suites/test_barcelona_rx_layout.gd`, plus the `barcelona_rx` registry
> entry (with the 3 pins) and the `tests/test_track_system.gd:5` edit. Start by
> running the import probe (§6) and the `_layout` suite against them; repair or
> rewrite what fails rather than starting from blank files. Then write the
> missing P1/P3 suites (`_track`, `_dressing`, `_barriers`) and finish P2, P4, P5.
> - **Fix the layout bake before anything else** (handoff §7): the generator has
>   **three** fixed-but-never-run bugs and `resources/ui/track_layouts/` is empty
>   while **4** layouts (including `barcelona_rx`, already registered) exist, so
>   the race-tab suites are red *independently* of Barcelona.
> **Do not edit** anything in the plan's §7 do-not-touch list. Edit
> `scripts/track/track_registry.gd` and `tests/test_track_system.gd`
> **additively** — both already carry unrelated uncommitted modifications (the
> `barcelona_rx` entry, 3 pins and the `test_track_system.gd:5` list are already
> in place, so verify them rather than re-adding). Re-run the layout bake (§7),
> then the import probe, then the full parallel gate. Report measured perimeter,
> files changed, tests added/updated, and any red. The root scratch is already
> cleaned — do not leave new `_*` files behind (§4).

---

## 9. Open risks carried from the plan (see §6 there for the full list)

1. Dirt grip = GRAVEL (0.85/0.80); the `DIRT` key is unreachable — **non-goal**.
2. Berm banking collapses to flat with `BANK_MAX_DEG = 0.0` (playtest knob).
3. Jump crests can snag the chassis / launch into barriers — keep ramp slope
   ≤ 20°, crest ≤ 1.0 m, verify by playtest. `TrackBuilder` writes flat `UP`
   normals (known cosmetic issue, deferred).
4. Control-point tuning can fold the spline — keep the bbox / min-segment /
   max-turn assertions, they are the guard rails.
5. Terrain pane must stay `SIZE_256` anchored at −256; layout must stay inside
   ±240 m (both asserted).
6. `laps_default` / `difficulty` are starting guesses.
7. Kenney GLB axes/scales are unverified; re-measure at implementation
   (build #1 did). `License.txt` stays CC0/read-only.
8. `.uid` files are created by `--import` and are gitignored — `git status
   --short` must not list them.
</content>
</invoke>
