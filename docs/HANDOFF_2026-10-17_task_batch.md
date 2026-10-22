# HANDOFF — 2026-10-17 task batch (5 fixes + plugin migration, gate + commit pending)

> **Read this whole file first.** It is the continuation record for the batch started
> 2026-10-17. The original session was cut short: three sub-agents were cancelled and
> **Gemini Vision is not signed in**, so visual verification could not run.
> Companion doc for shell/engine rules: `AGENTS.md` (unchanged, authoritative).

---

## 0. One-screen status

| # | Task | State |
|---|---|---|
| 1 | opencode plugin V2 migration | **DONE + verified live** (plan: `docs/plans/opencode_plugin_v2_migration_plan.md`) |
| 2 | Barcelona rallycross dirt look | **CODE + TESTS LANDED, not verified** (no Godot run) |
| 3 | Race menu regions + zoom | **CODE + TESTS LANDED, not verified** |
| 4 | Post-race cinematic (auto-drive) + EXIT button | **CODE + TESTS LANDED, not verified** — but see §4, the HUD is currently BROKEN in-game |
| 5 | Speed-trap flash + bottom banner + PB | **CODE + TESTS LANDED, not verified** |
| 6 | GT-R R35 cockpit rework | **NOT DONE** — cancelled agent left 1 stray line (§5) |
| 7 | **Live bug: HUD readouts all dead** | **OPEN, highest priority** (§4) |
| — | Full GDUnit gate | **NOT RUN YET** (§7) |
| — | `git commit` + `push` | **NOT DONE** (§8) — user asked for it explicitly |

Plans written by the research pass (all `PROPOSED`/`IMPLEMENTED` per file):
`docs/plans/barcelona_dirt_surface_plan.md`,
`docs/plans/race_menu_regions_zoom_plan.md`,
`docs/plans/post_race_cinematic_exit_plan.md`,
`docs/plans/gtr_r35_cockpit_improvement_plan.md`,
`docs/plans/speed_trap_hud_plan.md`,
`docs/plans/opencode_plugin_v2_migration_plan.md`.

---

## 1. Decisions the user already made — DO NOT re-ask

- **Cockpit image source:** *"option 1, you already have reference images for the r-35
  inside: `D:\AI Projects\UltraDrive\.vision\refs\r35`"* → use the user-supplied photos
  (plan §3.5 sanctions this as "user-owned photo"; record provenance in `License.txt`).
- **Race-menu map:** bump `svg/scale` **4.0 → 8.0**; `MAX_ZOOM = 10.0`; reset view on resize.
- **Post-race cinematic:** **auto-starts ~6 s after the finish**, **Esc skips**; not
  button-triggered. EXIT returns to the **race menu** (`scenes/ui/track_select.tscn`).
- **Commit:** *"after you're done, commit and push everything"*.
- **Vision tooling:** the user wants **Gemini Vision** for image critique — **not**
  Ollama/`analyze_image`/`ollama_vision.py`. Ollama was tried by a sub-agent and the user
  rejected it ("the cockpit engine kept using ollama vision, while I wanted gemini").

---

## 2. Environment rules that cost this session time (from `AGENTS.md`, still true)

- Shell on this PC is **cmd.exe**, not bash. No `head/tail/cat/grep/ls/wc/sed/awk/&&`-after-pipe.
  Use `tools\pick.bat …`, or the read/edit/grep/glob tools. `pick grep` patterns must not
  contain `|` or `<`/`>` (cmd eats them → "Illegal characters in path").
- Resolve Godot through `godot_path.bat`; for any headless/redirection use
  **`%GODOT_EXE_CONSOLE%`** (the GUI exe detaches and produces a false green).
- **Never write to C:.** Every run sets `APPDATA` to an absolute path under the project
  root (e.g. `D:\AI Projects\UltraDrive\reports\godot_userdata`).
- **ONE Godot process at a time** (the parallel gdUnit runner is the only exception).
- `*.uid` is gitignored — never `git add -A`.
- GDUnit: warnings are errors (type every `var`); `-a` is repeatable but **never
  comma-joined**; a suite **aborts at its first failure**; `--ignoreHeadlessMode` must come
  AFTER the tool-script path. Read `docs/GDUNIT_GATE.md` before running the gate.

---

## 3. What landed (CODE LANDED, NOTHING VERIFIED — no Godot was run by anyone)

### 3.1 Barcelona dirt (`docs/plans/barcelona_dirt_surface_plan.md`)
Root cause: `Tier` never reached the carriageway material; DIRT only tinted the 1 m edge
strips, so the 12 m carriageway rendered `surface_albedo(GRAVEL) = 0.55,0.48,0.38` — a flat
pale-tan strip that reads as asphalt.

- `scripts/track/track_builder.gd`: `DIRT_ALBEDO = Color(0.34,0.24,0.15)`,
  `DIRT_ROUGHNESS = 1.0`, `DIRT_UV_SCALE = Vector3(0.08,0.08,0.08)`, triplanar on;
  `tier_surface_albedo()` / `tier_surface_roughness()` wrappers (fallback to the unchanged
  `surface_*` for every non-DIRT tier); `_surface_material(surface, tier)` call-site change
  (`:279`, `:145`, `:281-282`); new `_apply_dirt_surface_detail()` (`:305-322`, DIRT-gated
  at `:293-294`) adds a mottling `NoiseTexture2D` albedo (seed `20261017`, freq `0.35`,
  FBM 4 octaves, ramp `0.62→1.0` grey) so it is dirt, not flat brown;
  `TIER_EDGE_COLORS[4]` → `[Color(0.40,0.29,0.19), Color(0.30,0.22,0.15)]`.
- **D4 (ground/foliage tint in `barcelona_rx.gd`) deliberately deferred** — plan marks it
  optional; `scripts/track/barcelona_rx.gd` is **unmodified**.
- Tests: `tests/suites/test_road_graph.gd` (2 tests, incl. the new
  `test_track_builder_tier_overlay_changes_only_dirt` blast-radius gate),
  `tests/suites/test_barcelona_rx_track.gd` (new
  `test_scene_road_surface_reads_as_dirt_not_pale_gravel`, reads the live
  `RoadNetwork → TrackBuilder → RoadSurface.material_override`).
- `docs/plans/track_barcelona_rallycross.md` corrected (it wrongly claimed "zero new
  material code").

### 3.2 Race menu regions + zoom (`docs/plans/race_menu_regions_zoom_plan.md`)
- `scripts/track/track_registry.gd`: 7 continent consts + `REGION_WORLD`, **all 32 world
  pins retagged with a `region`**, `regions` is now a 9-entry table
  (WORLD, ISRAEL, EUROPE, MIDDLE_EAST, NORTH_AMERICA, ASIA, SOUTH_AMERICA, AFRICA, OCEANIA)
  carrying `display_name`/`graticule_step`/`backdrop`; new `get_region_ids()`,
  `region_label()`, `region_meta()`; `pin_ids_for_region(WORLD)` now returns **every** pin.
- Membership: **ISRAEL 6, EUROPE 16, MIDDLE_EAST 3, NORTH_AMERICA 7, ASIA 3,
  SOUTH_AMERICA 1, AFRICA 1, OCEANIA 1 = 38** (+ WORLD = 38).
- `scripts/ui/track_map.gd` **NEW**: `MIN_ZOOM 1.0`, `MAX_ZOOM 10.0`, `ZOOM_STEP 1.25`,
  `PAN_DRAG_THRESHOLD_PX 4.0`; pure statics `zoom_fit` / `pan_fit` / `clamp_pan`;
  view API `get_zoom`/`set_zoom`/`zoom_by`/`reset_view`/`pan_by`; wheel-zoom about cursor,
  drag-pan, `visible_pin_ids()` membership filtering, backdrop/graticule driven off the
  region record, `WORLD_SVG_RASTER_SCALE 4.0 → 8.0`.
- `scripts/ui/track_select.gd` + `scenes/ui/track_select.tscn`: `%RegionTabs` row,
  `%MapControls` (`-` `0` `+`), keyboard (`+`/`=`/KP_ADD, `-`/KP_SUBTRACT, `0`/KP_0) and
  gamepad-shoulder zoom; view resets on region switch **and** on resize; `MapPanel` reworked
  to `MapColumn { RegionTabs, TrackMap(clipped), MapControls }` and the old
  `RegionButton` removed.
- `assets/ui/world_map_equirectangular.svg.import`: `svg/scale = 8.0` (source `.svg`
  untouched). `assets/ui/` is untracked as a whole.
- Tests: `tests/suites/test_race_menu_map.gd` — **40** `func test_` (24 pre-existing, one
  made region-aware, +16 new covering region membership/partition, zoom/pan statics,
  zoom clamping, pin-spread under zoom, resize/region reset, `hit_test` at
  `MAX_ZOOM`/`MIN_ZOOM`, continent filtering of cards, tab row ↔ registry).

### 3.3 Post-race cinematic + EXIT (`docs/plans/post_race_cinematic_exit_plan.md`)
- **NEW** `scripts/race/cinematic_director.gd` — `class_name CinematicDirector`,
  pure `RefCounted`, all static: `advance()` (RACING→FINISHED on FINISH;
  FINISHED→CINEMATIC on `dwell >= 6.0`; CINEMATIC→FINISHED on CANCEL;
  EXIT absorbing), `target_index()`, `chase_transform()`, `yaw_drift()`, `nearest_index()`.
- **NEW** `scripts/race/post_race_cinematic.gd` — `class_name PostRaceCinematic extends Node3D`,
  thin adapter: `begin`/`tick`/`stop`/`request_exit`/`camera`, signals
  `cinematic_started`/`cinematic_ended`/`exit_requested`, auto-driver = an `AIController`
  child on the player car (`set_speed_multiplier(0.55)`), retires/restores
  `ChaseCamera`/`OrbitCamera`/`HoodCamera`/`CockpitCamera`, `ui_cancel` = skip, null-safe.
- Constants: `FINISHED_DWELL_SEC 6.0`, `CINEMATIC_TARGET_HOLD_SEC 4.0`,
  `CAMERA_DISTANCE 9.0`, `CAMERA_HEIGHT 4.0`, `YAW_DRIFT_RPS 0.12`, `CRUISE_SPEED_MULT 0.55`.
- `scripts/race/race_ui.gd` **+119/−6**: `TRACK_SELECT_SCENE`,
  `%ExitButton` ref + connect, `_cinematic` / `_post_race_state`, `_start_cinematic()`,
  `_resolve_cinematic_root()`, `_on_cinematic_started/ended`, `_set_post_race_state()`,
  `_on_exit()`, `_stop_cinematic()`; state reset added to `_on_next_race` and
  `_on_return_free_roam`.
- `scenes/ui/hud.tscn` **+20**: `ExitButton` at **line 597** inside
  `Root/ResultsOverlay/Card/VBox/Buttons`, `unique_name_in_owner = true`, additive only.
- **Deliberate deviation from the plan:** `_on_exit()` calls `stop()` (no signal) instead of
  `request_exit()`, because `request_exit()` emits `exit_requested` which is wired back to
  `_on_exit` → infinite recursion. `request_exit()` remains the public harness seam.
- **Public verification seam (needed for the user's "I want to verify the cinematic")**:
  ```gdscript
  var cine := PostRaceCinematic.new()
  track_root.add_child(cine)     # omit for a camera-less (degraded) run
  cine.dwell_seconds = 0.0       # skip the 6 s dwell
  cine.begin([] /* standings */, line /* Array[Vector3] */)
  # per frame: var st := cine.tick(delta)   -> CinematicDirector.State
  var cam: Camera3D = cine.camera # node name "CinematicCamera"
  cine.stop()                    # teardown, no signal
  cine.request_exit()            # teardown + emits exit_requested
  ```
- Tests: **NEW** `tests/suites/test_post_race_cinematic.gd` — **12** funcs (T1–T12: pure
  transitions, dwell gate, target cycling, chase transform, auto-driver attach + input
  override, rig retire/restore, null-safety, rig reachability, EXIT → `track_select`,
  EXIT stops a live cinematic, next-race reset).

### 3.4 Speed-trap flash + banner (`docs/plans/speed_trap_hud_plan.md`)
- **NEW** `scripts/world/speed_trap_records.gd` — pure statics `is_new_best` /
  `merged_best` / `banner_text`, monotonic per-trap ledger (`best_of`/`record`/`is_dirty`),
  generic slot persistence. **Save key `"speed_traps"`, `DEFAULT_SLOT = 0`** (new top-level
  key; read-modify-write via `SaveManager.load_game`/`save_game`, other keys untouched).
- **NEW** `scripts/world/speed_trap_crossing.gd` — radius-only per-pass detector over
  `POIRegistry` `speedtrap_*` POIs, signal `speed_trap_crossed(trap_id, speed_kmh, best_kmh, is_new_best)`,
  `HYSTERESIS 1.6`, race gate, public `simulate_step()`, pause-only flush, test hooks.
- **NEW** `scripts/ui/speed_trap_hud.gd` + **NEW** `scenes/ui/speed_trap_hud.tscn` — its own
  `CanvasLayer` at **`LAYER 40`** (above HUD 0 / pause 10, below photo 50 / transition 100),
  **independent of `hud.tscn`** by design. Bottom-centre banner, offsets
  `-280,-88,+280,-24` → at 1920×1080 occupies **x 680…1240, y 992…1056**, clearing
  `ClusterBackdrop` (ends x 592) by 88 px and `Minimap` (starts x 1700) by 460 px.
  Flash `Color(1.0,0.96,0.88)`, rise `0.06` / fall `0.30` / peak alpha `0.5`.
  Banner rise `0.15` / hold `1.8` / fall `0.45`. `play()` no-ops while
  `RaceManager.is_race_active`. `set_process(false)` when idle.
- `scenes/world/open_world_root.tscn` **+9/−2**: `load_steps 25 → 27`, ext resources
  `22_crossing` / `23_traphud`, `SpeedTrapHUD` at line **161**, `SpeedTrapCrossing` at line **219**.
- Tests: **NEW** `tests/suites/test_speed_trap_hud.gd` — **16** funcs (group A records,
  B timing envelopes, C crossing/hysteresis/race-suppression/claimed-trap independence,
  D wiring/leak).
- **Known deviation to confirm:** `_on_game_paused` flushes **unconditionally** (matches the
  plan's own Step 1 and the shipped `CollectibleField` precedent). Acceptance criterion 6
  says "no save write during a race" — no crossing can be *recorded* during a race, but a
  paused race would still write an unchanged ledger. A reviewer may want an
  `is_dirty()`/race guard; `_dirty` is exposed for exactly that.

---

## 4. **OPEN BUG (do this first): HUD readouts all dead**

User's verbatim report:

> "something is wrong, the hud wiring probably failed because im at 0 km/h, 0 rpm, and no
> hp,nm are showing, also can't see my location (x,y,z)"

**Why this is one bug, not four:** `scripts/race/race_ui.gd` (attached to
`scenes/ui/hud.tscn` line 4) writes *all* of them — `%Cluster` from
`car.get_drive_info()` (`speed_kmh`/`gear`/`rpm`), the coords label (formatted every frame,
~`race_ui.gd:178`), and the power/torque readout (`_refresh_power_readout` → `PowerValue`,
~`race_ui.gd:470-475`). RPM reading **0 with no idle rpm** means the values are not being
written at all.

**Prime suspect — the just-added EXIT wiring in `_ready()`:** `race_ui.gd` grew **+119/−6**
for the post-race feature, including `@onready var exit_button: Button = %ExitButton` and
`exit_button.pressed.connect(_on_exit)`. If that unique-name lookup or connect throws, the
rest of `_ready()` never runs — including whatever assigns the car reference — and every
readout stays dark.

**Check in this order:**
1. `git diff scripts/race/race_ui.gd` — find the first statement in `_ready()` that can
   fail and everything after it that would then be skipped.
2. Parse error taking the whole script down: references to `PostRaceCinematic` /
   `CinematicDirector` (fresh `class_name`s) while the class cache is stale; or a
   `var x := f()` returning Variant (warnings are errors).
3. `car` resolution path (`VehicleManager` / `get_player_car`) — did it move below the new
   code, or into a branch that can now be skipped?
4. `_process()` early-return: `if _race_over: return` must still come *after* the gauge
   updates, and `_race_over` / `_post_race_state` must not be stuck truthy in free roam.
5. `git diff project.godot` (14 lines added) — autoload/order drift would break
   `VehicleManager`/`GameState`/`RaceManager`. Judge each hunk: intentional user work or breakage?
6. Frame-by-frame runtime error from the new code reading `_cinematic` / `exit_button` / `confetti` null.

**Constraint:** fix *minimally* — the EXIT button and the cinematic are required
deliverables; fix the wiring, do not delete the feature. The cockpit agent is cancelled, so
a single Godot run is now available if needed — but verify it is free first
(`tasklist /fi "IMAGENAME eq Godot_v4.7.2-stable_win64_console.exe"`).

Files this fix owns: `scripts/race/race_ui.gd`, `scripts/race/power_gauge.gd`,
`scenes/ui/hud.tscn`, `tests/suites/*.gd` pinning this HUD behaviour, `project.godot` only
with proof a hunk is breakage.

---

## 5. **OPEN: GT-R R35 cockpit (not started for real)**

Plan: `docs/plans/gtr_r35_cockpit_improvement_plan.md` (Phase 1 only; Phase 2 panorama
deferred — a single photo cannot make a correct equirect).

**State after two cancelled agents:**
- `assets/interiors/` **does not exist** — no texture, no `License.txt`, no reference copy.
- `tools/r35_prepare_dash_texture.py` **does not exist**.
- Scratch left behind (delete when done): `tools/_r35_compare_tmp.py`,
  `tools/_r35_downscale_tmp.py`, `tools/_r35_inspect_tmp.py`, `tools/_r35_gemini_pick.bat`.
- **STRAY EDIT to decide:** `scenes/vehicle/interiors/nissan_gt_r35_2017_cockpit.tscn` line
  302 gained `transform = Transform3D(1,0,0, 0,1,0, 0,0,1, 0,-0.32, 0)` on the root
  `NissanGTR35Cockpit` node. **git HEAD does NOT have this line**, but plan §6 claims the
  root "carries a −0.32 m Y offset". Resolve by evidence — read
  `tests/suites/test_gtr_r35_interior.gd` seat-anchor maths (`:439-543`),
  `tests/suites/test_gtr_r35_sightline.gd`, and `scripts/vehicle/cockpit_rig.gd`
  (`seat_anchor_for` / `_sync_to_seat_anchor`) — then keep or revert and record why.
  Do not trust the plan's line numbers blindly.

**Build (Phase 1):** crop the **upper dash band** (dash top, cowl, windscreen base, vents,
binnacle surround) from a driver's-eye ref — **above the steering-wheel rim**, so the baked
wheel is excluded (the wheel stays real 3D + animated) — **mirror horizontally** (refs are
LHD, the game R35 is RHD: config `_lateral = -0.36`; tests require `DoorCardRight.x < 0`,
`CentreStackRiser.x > 0`), colour-grade to the in-game night cabin (pre-graded, so no
`cockpit_rig.gd` edit), resize **2048×1152** → `assets/interiors/r35/r35_dash_forward.png`.
Then repurpose the `DashPad` node (keep the **node name**) into a quad at **z = −0.80**,
opaque, `SHADING_MODE_UNSHADED`, `cast_shadow = 0`, **top edge ≤ eye-space y −0.05** (that
is what keeps `test_gtr_r35_sightline.gd` green with zero gate edits — never loosen
`SIGHTLINE_BAND`/`WEDGE_TAN`). Lift the near-black shared trim materials
(`mat_interior`, `mat_leather`, `mat_alcantara`, `mat_carbon`, `mat_pad_black`, `mat_hub`,
`mat_pad_amber` — albedo 0.028–0.1, emission 0.15) to plausible GT-R cabin tones.

**Hard constraints:** no `OmniLight3D`/`SpotLight3D`/`DirectionalLight3D`, no `SubViewport`,
every `MeshInstance3D` `cast_shadow = 0`; never rename/remove a node pinned by
`test_gtr_r35_interior.gd` (27 funcs) or `test_gtr_cockpit_resources.gd`; do not touch
`cockpit_rig.gd`, `cockpit_rig.tscn`, `cockpit_camera.gd`, `car_visuals.gd`.
Append a **STATUS block** to the plan doc when Phase 1 lands.

**Reference images** (`.vision/refs/r35/`, gitignored — copy anything kept into
`assets/interiors/r35/reference/`):
- `File_The_interior_of_Nissan_GT-R_Premium_Edition_2017_year_model_at_Ni.jpg` (driver's-eye, good)
- `File_Nissan_GT-R_Premium_edition_T-Spec__4BA-R35__interior.jpg.jpg` (driver's-eye)
- `File_Nissan_GT-R_Premium_edition__4BA-R35__interior.jpg.jpg`
- `File_2012_Nissan_GT-R_Egoist_interior.jpg.jpg` (passenger view)
- `nc_12_Nissan-GT-R-2017-Interior.fdea9e67.jpg`
Ignore `car101_*.jpg` (not usable JPEGs), `mad_*.jpg` (icons), `nc_*exterior*`.

**Visual verification recipe** (windowed — `--headless` renders black; set `APPDATA` to a
project-absolute path):
```
cmd /v:on /c "call godot_path.bat & set APPDATA=D:\AI Projects\UltraDrive\reports\godot_userdata & !GODOT_EXE_CONSOLE! --path . -s res://tools/r35_cockpit_capture.gd"
```
→ `.vision/captures/r35_cockpit_forward.png`, `r35_cockpit_binnacle_stack.png`
(also does a right-stick look sweep → proves the yawed view has no void),
`r35_cockpit_console.png`.

---

## 6. **Gemini Vision is NOT signed in — fix this before any visual review**

Symptom: sub-agents could not get a critique back because the browser session is unauthenticated.

**Why it happens:** sign-in must occur **inside the automation profile**
`.vision/chrome_profile`. Chrome's App-Bound Encryption binds cookies to the profile path,
so a copied-in signed-in session is silently deleted on the next launch (auth rows 75 → 6 → 0).

**Fix (one-time, manual, needs the user at the keyboard):**
```
gemini_vision.bat sync-profile     <- copy real Chrome profile; Chrome must be CLOSED first
gemini_vision.bat login            <- one-time manual sign-in; waits <=300s, then closes itself
```
Then verify with `gemini_vision.bat probe`.

**Hard rules learned the hard way (from `AGENTS.md` — do not re-derive):**
- Never point automation at the real Chrome `User Data` dir or a junction to it — that wipes
  the **real** Chrome cookies. `.vision/chrome_real` was removed; do not recreate it.
- URL must be `.../app?hl=en` (the UI defaults to Hebrew and every English `aria-label`
  selector fails).
- Close Chrome before `sync-profile`/`ask` — one Chrome at a time.
- **≤5 images per `ask`**, `--timeout 400`, skip huge PNGs; a reply under ~100 chars is an
  error blob, not a critique; ~1-in-3 calls fail transiently → **just re-run**.
- Output convention: append verdicts to `.vision/analysis.md`; raw copies land in
  `.vision/gemini/feedback_*.md`.
- **Do not fall back to Ollama** (`analyze_image`, `tools/ollama_vision.py`,
  `qwen2.5vl:7b`) for these critiques — the user explicitly rejected that path.

---

## 7. Gate — run ONCE, after all fixes

Nothing in this batch has been executed under Godot. **Do not claim tests pass until this runs.**
Read `docs/GDUNIT_GATE.md` first (the forms below are the PC's working recipe).

1. Import probe (console exe, `APPDATA` on D:, expect **zero** `SCRIPT ERROR`/`Parse Error`):
   ```
   cmd /v:on /c "call godot_path.bat & set APPDATA=D:\AI Projects\UltraDrive\reports\godot_userdata & !GODOT_EXE_CONSOLE! --headless --import . 2>&1"
   ```
   This also rebuilds the `class_name` cache for `CinematicDirector`/`PostRaceCinematic`/
   `SpeedTrap*`/`TrackMap` — **run it before any gdUnit run that names those classes.**
2. Gate — prefer the parallel runner (**4.18× faster**, all-green at
   `1018 tests | 0 errors | 0 failures` on 2026-10-04):
   ```
   py tools\gdunit_parallel.py -j 4
   ```
   Artifacts under `reports/parallel/` (`merged-results.xml`, `summary.json`, `logs/`).
   Exit 0 = clean, 1 = real failures (trustworthy), 2 = **false green** (numbers unusable).
   It is the one deliberate exception to "one Godot process" — never run it beside another.
3. Serial fallback: `docs/GDUNIT_GATE.md`. One `-a` per suite, never comma-joined
   (comma-joined paths run **zero** tests and still exit 0).
4. Expected churn from this batch: +16 (race menu) +12 (post-race) +16 (speed trap)
   +3-ish (barcelona) new cases, so expect **~1060+ cases** and **4–5 new suites**.
5. Suites that must stay green and are worth running first while triaging §4:
   `test_race_results.gd`, `test_race_loop.gd`, `test_rival_ai.gd`, `test_cockpit_hud.gd`,
   `test_traction_hud.gd`, `test_road_graph.gd`, `test_barcelona_rx_track.gd`,
   `test_race_menu_map.gd`, `test_speed_trap_hud.gd`, `test_post_race_cinematic.gd`,
   `test_gtr_r35_sightline.gd`, `test_gtr_r35_interior.gd`, `test_gtr_cockpit_resources.gd`.
6. Hardware flake note: `test_perf_gate.gd` is two-mode now — read `[perf_gate] mode=...`
   before believing a perf failure (see `AGENTS.md`).

---

## 8. Commit + push (user asked: "after you're done, commit and push everything")

**Do this last**, after §4 fix and §7 gate.

The working tree is large and contains **pre-existing user work from before this batch** —
do **not** `git add -A` (it would also sweep `*.uid`, `.claude/`, `__pycache__`, etc.).
Triage at least these groups:

- **Batch work (commit):** the 4 landed tasks' files (§3), the 6 new plan docs, plus the
  cockpit work when it lands.
- **Plugin work (commit):** `.opencode/plugins/vision-bridge.js` (V2 port),
  the deletions/renames `D .opencode/plugins/token-slim.js`,
  `?? .opencode/plugins/token-slim.js.v1.bak`, `?? .opencode/plugins/vision-bridge.js.v1.bak`,
  `?? .opencode/plugins/graphify.js`, and whatever the global-config change was
  (`C:\Users\LotusSeven\.config\opencode\opencode.json` is **outside the repo** — not committable).
  Decide whether the `.v1.bak` files should be committed at all or gitignored.
- **User work, decide explicitly (do not silently drop):** `AGENTS.md`, `CLAUDE.md`,
  `.claude/`, `.opencode/skills/`, `.graphifyignore`, `project.godot`, `docs/ROADMAP.md`,
  `docs/research/ultradrive_features.md`, `graphify-out/`, `assets/videos/*.ogv`,
  `assets/ui/`, `resources/ui/`, `scenes/capture/`, `scripts/capture/`, `scripts/career/*`,
  `scripts/track/barcelona_rx*`, `scripts/ui/menu_video_*`, `scripts/ui/world_map_projection.gd`,
  `tools/gdunit_parallel.py`, `tools/record_menu_clips.py`, `_glb_aabb.py`, and the many
  untracked `docs/plans/*` + `tests/suites/*`.
- `graphify-out/graph.json` is rewritten whole on every build — a large diff there is
  expected, not churn. GDScript is **not** in the graph, so `graphify update .` adds little
  for `.gd` changes; run it only if you touch tooling/docs.

---

## 9. Suggested continuation order

1. §6 sign in to Gemini (needs the user).
2. §4 fix the dead HUD (highest user-visible priority; static `git diff` first).
3. §5 cockpit Phase 1, with the **Gemini** critique for verification.
4. §7 one gate run; fix anything red.
5. §8 commit + push.
6. Optional follow-ups deferred from this batch: cinematic → menu-background clip
   (`scenes/capture/post_race_cinematic_capture.tscn` + `tools/record_post_race_clip.py` →
   `assets/videos/menu_race_finish.ogv`, per plan §4 Step 6 — only after §7 is green);
   Barcelona D4 ground/foliage tint; speed-trap `_on_game_paused` race guard.

*Written 2026-10-17 from the original session. No Godot process was ever run in it.*
