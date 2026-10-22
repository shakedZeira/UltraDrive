# HANDOFF 2026-10-18 — GT-R R35 cockpit Phase 1 (texture-based dash)

**Topic:** make the GT-R R35 first-person cockpit read as a real R35 interior,
using the user's real interior photos as the texture source for a forward dash
billboard. **Plan:** `docs/plans/gtr_r35_cockpit_improvement_plan.md` —
**Phase 1 ONLY** (Phase 2 equirect panorama is deferred; handoff-17 §5's
photo-crop recipe SUPERSEDES plan step 4 — no Blender).
**Status: IN PROGRESS** — asset folder + two standing decisions landed; NO
texture, NO scene edits, NO test/capture/Gemini verification. Task was
interrupted and handed off deliberately; resume from §3 below.

---

## 1. What has actually landed (verified on disk 2026-10-18)

- `assets/interiors/r35/` (NEW, untracked) — created this session.
  - `reference/` — 5 photos copied from `.vision\refs\r35\` via Python
    `shutil` (cmd `copy` mangles the quoted paths, see §7):
    `File_The_interior_of_Nissan_GT-R_Premium_Edition_2017_year_model_at_Ni.jpg`,
    `File_Nissan_GT-R_Premium_edition_T-Spec__4BA-R35__interior.jpg.jpg`,
    `File_Nissan_GT-R_Premium_edition__4BA-R35__interior.jpg.jpg`,
    `File_2012_Nissan_GT-R_Egoist_interior.jpg.jpg`,
    `nc_12_Nissan-GT-R-2017-Interior.fdea9e67.jpg`
  - `License.txt` — HONEST provenance: user-supplied third-party photographs,
    original author/source NOT asserted, NOT own work, NOT CC0; redistribution
    caveat. **Flag in the final report** — do NOT rewrite it as an own-work
    claim. The refs in `assets/interiors/r35/reference/` ship beside it.
- **Decision recorded: the stray −0.32 root transform is KEEP** (evidence in §4).
- NOTHING else. No `r35_dash_forward.png`, no `tools/r35_prepare_dash_texture.py`,
  no `.tscn` edit, no deletions, no plan STATUS block, no test run, no capture.

## 2. Half-done / inconsistent state (check before touching)

- `scenes/vehicle/interiors/nissan_gt_r35_2017_cockpit.tscn` — modified vs git
  HEAD, but the ONLY diff is line 302: `transform = Transform3D(1,0,0, 0,1,0,
  0,0,1, 0,-0.32, 0)` on root `NissanGTR35Cockpit` (node at :301, `DashPad` at
  :304-308). Verdict = KEEP (§4); it is simply uncommitted, not wrong. All
  Phase-1 edits still go into this file (§3 step 3).
- `tools/_r35_crop_tmp.py` — NEW scratch file I created this session (temp
  probe that POSTs an image to a local ollama `/api/generate` for crop-band
  guidance; it fails right now with connection-refused, §7). **Delete together
  with the four known scratch files** (§3 step 5): `_r35_compare_tmp.py`,
  `_r35_downscale_tmp.py`, `_r35_inspect_tmp.py`, `_r35_gemini_pick.bat`.
- `tools/fetch_r35_refs.py` — pre-existing (not created this session, not on
  the delete list). Leave alone; note in the final report only.
- `AGENTS.md` shows `M` in `git status` — **pre-existing dirt from another
  task, NOT mine**; I made no AGENTS.md edit (see §6 for the still-TODO bullet).
- `.vision/captures/r35_cockpit_forward.png`,
  `r35_cockpit_binnacle_stack.png`, `r35_cockpit_console.png` — **STALE**
  (prior session, captured BEFORE this phase). Re-capture after the build
  (§3 step 7); do not critique these.
- Ollama: NOT running (`netstat :11434` empty, no `ollama.exe` in tasklist).
  A background `ollama serve` (vulkan) was spawned this session
  (`sh_14d4a7c7c001zvEChLz9N4hNAj`) and died/was killed; no cleanup left, but
  never start one for the Gemini critique — see §6.

## 3. What remains — execute in this order

1. **AGENTS.md bullet (§6)** — the one authorised AGENTS.md edit; not done yet.
2. **Crop-box determination.** Driver's-eye photo:
   `assets/interiors/r35/reference/File_The_interior_of_Nissan_GT-R_Premium_Edition_2017_year_model_at_Ni.jpg`
   (1920×1440). Need pixel bounds of the **upper dash band** — dash top, cowl,
   windscreen base, vents, binnacle surround — **strictly ABOVE the steering-wheel
   rim** (the wheel stays real 3D + animated; a baked wheel in the texture would
   double it). Plan/handoff give no coordinates. Vision-model probe was in
   flight when interrupted (`tools/_r35_crop_tmp.py` asks for two fractions of
   image height: wheel-rim top at frame centre, and windscreen-base/cowl). It
   needs a live ollama serve (§7) or any other means; manual eyeballing in an
   image editor is acceptable — the only hard requirement is "above the rim".
3. **Author + run `tools/r35_prepare_dash_texture.py`** (deterministic,
   re-runnable, `py`, PIL/numpy, stdlib only): crop the band → **mirror
   horizontally** (refs are LHD, the game R35 is RHD — `config._lateral = −0.36`,
   tests require `DoorCardRight.x < 0`, `CentreStackRiser.x > 0`) → colour-grade
   to the in-game **night** cabin (pre-graded; that is why NO runtime dimming
   and NO `cockpit_rig.gd` edit) → resize **2048×1152** →
   `assets/interiors/r35/r35_dash_forward.png`. Ignore ref photos `car101_*`
   (broken JPEGs), `mad_*` (icons), `nc_*exterior*`.
4. **Edit `nissan_gt_r35_2017_cockpit.tscn`** (keep the root −0.32 transform):
   - Repurpose `DashPad` (KEEP the node name) → `QuadMesh`/`PlaneMesh`
     ~2.00×0.50 m at **z = −0.80**, x centred, spanning eye-space y
     ∈ [−0.55, −0.05]; **top edge ≤ eye-space y −0.05** (this alone keeps
     `tests/suites/test_gtr_r35_sightline.gd` green with ZERO gate edits —
     never loosen `SIGHTLINE_BAND`/`WEDGE_TAN`). Float trap: local y + 0.25 +
     (−0.32) = −0.05 EXACTLY is risky; use local y ≈ 0.01 → eye top −0.06.
   - New subresource `mat_dash_billboard`: albedo = the png,
     `SHADING_MODE_UNSHADED`, `albedo_color = (1,1,1,1)`, `cast_shadow = 0`,
     opaque.
   - **`mat_interior` CANNOT be lifted as-is** — `tests/suites/test_gtr_r35_interior.gd:73-78`
     pins the WHEEL's material exactly (`wheel.mesh.material`; `mesh_wheel`
     uses `mat_interior`): emission on, energy 0.15±0.0001, roughness 0.9±0.05,
     albedo exactly `Color(0.1, 0.1, 0.13, 1)`. Create `mat_wheel` (copy of the
     current values), re-point `mesh_wheel` to it, THEN lift `mat_interior`
     for its other users (pillars, header, spokes, paddles, column, flat
     bottom, vent ring shells).
   - Lift the remaining near-black trim materials to plausible conservative
     GT-R cabin tones: `mat_leather`, `mat_alcantara`, `mat_carbon`,
     `mat_pad_black`, `mat_hub`, `mat_pad_amber` (albedo 0.028–0.1, emission
     0.15 today). Do NOT touch `mat_shift`/`mat_mfd` (rig isolates runtime
     copies at `scripts/vehicle/cockpit_rig.gd:198-244`; not in the lift list).
5. **Delete the scratch files**: `tools/_r35_compare_tmp.py`,
   `tools/_r35_downscale_tmp.py`, `tools/_r35_inspect_tmp.py`,
   `tools/_r35_gemini_pick.bat`, plus my `tools/_r35_crop_tmp.py`.
6. **Gate (targeted suites, never the full run):** import probe FIRST, then the
   five suites, chained with `&` — comma-joined `-a` is a false green
   (`AGENTS.md` GDUnit section):
   ```
   cmd /v:on /c "call godot_path.bat & set APPDATA=D:\AI Projects\UltraDrive\reports\godot_userdata & !GODOT_EXE_CONSOLE! --headless --import . 2>&1"
   cmd /v:on /c "call godot_path.bat & set APPDATA=D:\AI Projects\UltraDrive\reports\godot_userdata & !GODOT_EXE_CONSOLE! --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/suites/test_gtr_r35_sightline.gd -a res://tests/suites/test_gtr_r35_interior.gd -a res://tests/suites/test_gtr_cockpit_resources.gd -a res://tests/suites/test_cockpit_visibility.gd -a res://tests/suites/test_gtr_r35.gd > _gdunit.txt 2>&1"
   ```
   (`--ignoreHeadlessMode` MUST come AFTER the tool-script path. Check
   `_gdunit.txt` is not 0 bytes; a suite ABORTS at its first failure, so compare
   executed counts against the files' `func test_` counts. ONE Godot process at
   a time; never run in the main session's foreground — background it.)
7. **Visual verification** (windowed — `--headless` renders black):
   ```
   cmd /v:on /c "call godot_path.bat & set APPDATA=D:\AI Projects\UltraDrive\reports\godot_userdata & !GODOT_EXE_CONSOLE! --path . -s res://tools/r35_cockpit_capture.gd"
   ```
   → (re)writes `.vision/captures/r35_cockpit_forward.png`,
   `r35_cockpit_binnacle_stack.png` (yaw look-sweep — proves no void),
   `r35_cockpit_console.png`.
8. **Gemini critique** — downscale per §6 first, `≤5 images` per ask (3
   captures + 2 refs), `--timeout 400`; AC1 passes ONLY on an honest positive
   verdict. Iterate crop/grade/materials at least once more otherwise; append
   the verdict to `.vision/analysis.md`. **The user REJECTED Ollama /
   `analyze_image` / qwen2.5vl as the critique fallback** — if Gemini is
   unauthenticated, report that a manual `gemini_vision.bat login` is needed;
   do not substitute local vision. If `ask` fails ~1 in 3 ("I encountered an
   error…") re-run the same ask; a reply under ~100 chars is an error blob.
9. **STATUS block** appended to `docs/plans/gtr_r35_cockpit_improvement_plan.md`
   (Phase 1 landed / decisions / gaps), then the final report: shipped files,
   per-suite gate counts, the −0.32 keep-verdict + evidence, Gemini verdict or
   blocker, licensing flag (§1), residual gaps. Do not overstate.

## 4. Standing decision — the −0.32 root transform: KEEP (do not re-derive)

`Transform3D(1,0,0, 0,1,0, 0,0,1, 0,-0.32, 0)` on root `NissanGTR35Cockpit` is
INTENDED, just uncommitted:
- `tests/suites/test_gtr_r35_sightline.gd` is itself **UNTRACKED (new)**; its
  docstring (:15-25) says the interior root now carries a downward offset and
  the test is RED without it (17 meshes above the band) / GREEN with it.
- `docs/plans/fix_gtr_windshield_glass.md:240-244` prescribes exactly this
  transform line (Variant A, §4 step 2); :423 records it as landed.
- Seat-anchor maths (`test_gtr_r35_interior.gd:439-543`,
  `cockpit_rig.gd:376-387`, `_sync_to_seat_anchor` `:395-401`) only asserts
  rig/camera positions — unaffected.
Keeping it is also what makes the DashPad top-edge budget (≤ −0.05 eye space)
computable: eye y = local y + 0.25 (half-height) + (−0.32).

## 5. Hard constraints (Phase 1 — do not violate)

- NO `OmniLight3D`/`SpotLight3D`/`DirectionalLight3D`, NO `SubViewport`.
- Every `MeshInstance3D` keeps `cast_shadow = 0`.
- Never rename/remove a node pinned by `test_gtr_r35_interior.gd` (27 funcs;
  node/light/shadow/RHD pins at :56-96, :296-328) or `test_gtr_cockpit_resources.gd`.
- Never edit `scripts/vehicle/cockpit_rig.gd`, `cockpit_rig.tscn`,
  `cockpit_camera.gd`, `car_visuals.gd`, `project.godot`, the quality ladder.
- Never loosen `SIGHTLINE_BAND`/`WEDGE_TAN`; **do NOT edit
  `tests/suites/test_gtr_r35_sightline.gd`** — it must pass unmodified.
- Scope: only `assets/interiors/r35/**`, the cockpit `.tscn`,
  `tools/r35_prepare_dash_texture.py`, the scratch deletions, the plan STATUS
  block, `.vision/analysis.md`, plus the ONE authorised AGENTS.md bullet (§6).
- Never write to C:; `APPDATA=D:\AI Projects\UltraDrive\reports\godot_userdata`
  on every Godot run. One Godot process at a time. **Do NOT commit / `git add
  -A`** — the main session handles commits (`*.uid` are gitignored).

## 6. Gemini image-size rule (user addition 2026-10-18) — APPLY, and the AGENTS.md bullet is still TODO

**Rule:** before ANY `gemini_vision.bat ask`, downscale every upload — game
captures AND reference photos — to **~1280 px wide max** (keep aspect; captures
→ ~1280×720). Write the shrinks to `.vision/gemini_upload/` (does not exist
yet) and upload those, never the originals. Reported by the user ("I think"),
observed not root-caused; costs nothing if the limit is elsewhere.
**AGENTS.md bullet: NOT LANDED.** The authorised one-line bullet under
`### GEMINI VISION` (AGENTS.md :272, next to the `≤5 images per ask` bullet at
:305) was never written — I was interrupted first. Still TODO; it is the only
permitted AGENTS.md edit.

## 7. Gotchas hit this session (would otherwise be rediscovered the hard way)

- **`py -c "..."` inline scripts are BROKEN in this shell** (cmd.exe mangles
  quotes → `EOL while scanning string literal`). Always write a temp `.py`
  file, run it, delete it. Same for `copy` with quoted paths → Python `shutil`.
- **Local ollama vision is not usable right now:** port 11434 refuses
  connections, no `ollama.exe` process. `tools/ollama_vision.py` respawns
  `ollama serve` per invocation (model never warms) and a stale process dies
  with a PTX/`0xc0000409` crash (see AGENTS.md vision-bridge section for the
  vulkan-env recipe). Irrelevant for the critique anyway (Gemini-only), it was
  only being used for crop coordinates — if you want it back, spawn
  `ollama serve` with `OLLAMA_LLM_LIBRARY=vulkan` in the background yourself.
- **`netstat`/`tasklist | findstr` exit 1 on no match** — that means "absent",
  not "command failed".
- Godot: the GUI `Godot_v..._win64.exe` DETACHES under PowerShell and silently
  no-ops headless runs (false green) — always the `_console.exe` via
  `godot_path.bat` (recipe in §6 steps above).
- Prior-session captures in `.vision/captures/r35_*.png` look like ready-made
  critique input but are stale — re-capture after the scene edit.
- Shell helpers still apply: `tools\pick.bat grep "<pat>" <ABSOLUTE path>`,
  the `read`/`grep`/`glob` tools; NO POSIX utilities anywhere.
