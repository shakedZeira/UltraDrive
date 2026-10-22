# Fix: garage SELECT / BACK buttons are covered by the car rail

Status: IMPLEMENTED (2026-10-16) — see §9 for what shipped.
Owner files: `scenes/ui/garage.tscn`, `scripts/ui/garage_ui.gd`
Reported by player: *"The 'select/back' buttons in the garage are overlayed and
can't be pressed — maybe move them elsewhere?"*

---

## 1. Goal + player-verifiable acceptance criteria

**Goal.** Make the garage's primary actions (`SELECT`, `BACK`) reliably
clickable and never visually covered, while keeping the FH5/GT-style garage the
player already has (vehicle preview left, info/tuning column right, bottom car
rail). The rail and the buttons must simply stop occupying the same pixels.

**Acceptance criteria (player-verifiable, no debug UI):**

1. Entering the garage from the main menu, the gold `SELECT` and dark `BACK`
   buttons at the bottom of the info column are **fully visible** — no car card
   is drawn over them — and show their hover highlight when the mouse is over
   them.
2. Left-clicking `SELECT` activates the highlighted car (leaving and re-entering
   the garage shows that car as the active one). Left-clicking `BACK` returns to
   the main menu. Both work at **1920×1080** (the shipped default:
   `project.godot:19-21` — borderless fullscreen, 1920×1080, `canvas_items`
   stretch + `expand` aspect) and at smaller 16:9/16:10 windows
   (1280×720, 1366×768).
3. The car rail still renders every brand section, still scrolls when a brand
   row overflows, and every card in it is still selectable by click.
4. No other garage behaviour changes: turntable spin, Tune/Paint tabs, sliders,
   swatches, menu blip.

**Non-goal.** Redesigning the garage layout, changing the rail's content/style,
or moving the tuning UI.

---

## 2. Current state — VERIFIED (file:line)

### 2.1 The two relevant subtrees (node order inside the scene root)

`scenes/ui/garage.tscn` declares, in this order under the root `Garage` Control
(`garage.tscn:169`):

| # | node | line | notes |
|---|------|------|-------|
| 1 | `UiBlip` (AudioStreamPlayer) | 177 | |
| 2 | `Background` (ColorRect, full rect) | 180 | `mouse_filter = 2` (IGNORE), line 186 |
| 3 | `Gradient` (TextureRect, full rect) | 189 | `mouse_filter = 2`, line 195 |
| 4 | **`Margin`** (MarginContainer) | 199 | `offset_bottom = -96.0` (line 206) — the whole left/right UI column |
| 5 | `Footer` (Label, bottom-left) | 397 | `anchors_preset = 2`, x 28→400, y H-20→H-4 |
| 6 | **`CarScroll`** (ScrollContainer) | 410 | the bottom car rail |
| 6.1 | `CarRail` (VBoxContainer) | 423 | populated at runtime by `garage_ui.gd:83-110` |

Because `CarScroll` is declared **after** `Margin`, it is drawn last and is the
**first** candidate for GUI mouse input over its own rectangle (Godot GUI picking
walks controls in reverse tree/draw order; `z_index` does not change which
Control receives the event). No `z_index` is set anywhere in this scene.

### 2.2 Geometry: the rail's rectangle contains the buttons

* `CarScroll` (`garage.tscn:410-421`) is anchored **bottom-centre**
  (`anchors_preset = 7`, `anchor_left/anchor_right = 0.5`, `anchor_top/bottom =
  1.0`, lines 411-415) with
  `offset_left = -360.0` / `offset_top = -318.0` / `offset_right = 360.0` /
  `offset_bottom = -18.0` (lines 416-419).
  → rect = **x ∈ [W/2 − 360, W/2 + 360], y ∈ [H − 318, H − 18]**.
  At 1920×1080: `x ∈ [600, 1320]`, `y ∈ [762, 1062]`.
* The buttons are the last children of the Garage tab page:
  `Margin/MainRow/RightPanel/TuningTabs/Garage/ButtonsRow`
  (`ButtonsRow` at line 359, `SelectButton` at 362, `BackButton` at 376), each
  `custom_minimum_size = Vector2(160, 46)`.
* `Margin` ends at `H − 96` (`offset_bottom = -96.0`, line 206) and
  `StatsBox` (`garage.tscn:347`, `size_flags_vertical = 3`) absorbs all surplus
  height, so `ButtonsRow` is pinned to the panel's bottom:
  → button rect ≈ **x ∈ [≈700, ≈1036], y ∈ [H − 146, H − 96]**
  (exact left edge depends on the TabContainer's content margin; the test must
  read the runtime rect, never hardcode it).
* `RightPanel` (`garage.tscn:291-296`) starts at **x ≈ 698** = `Margin` left
  inset 28 (`garage.tscn:203`) + `PreviewPanel` width 640
  (`custom_minimum_size = Vector2(640, 540)`, `garage.tscn:219`) + `MainRow`
  separation 30 (`garage.tscn:216`). `PreviewPanel` has **no** horizontal Expand
  flag, so it stays at its minimum width while `RightPanel`
  (`size_flags_horizontal = 3`) takes the rest — Godot's documented rule is
  *"Controls that don't expand will be pushed away by those that do"*
  (`docs.godotengine.org/en/stable/tutorials/ui/gui_containers.html`, "Sizing
  options → Expand").

Therefore, at 1920×1080 the buttons at
`x ∈ [≈700, ≈1036] (⊂ [600, 1320])` and `y ∈ [H−146, H−96] (⊂ [762, 1062])`
sit **entirely inside the rail's rectangle**. This holds at every width from
≈680 px to ≈2790 px (rail left edge `W/2 − 360` is always < 698 and rail right
edge `W/2 + 360` is always > 1036 in that range) — i.e. at every window size the
game can realistically run.

### 2.3 The rail swallows the clicks (this is the actionable cause)

`CarScroll` has **no `mouse_filter` property in the scene file** — contrast its
siblings, which all set it explicitly: `Background` (`garage.tscn:186`),
`Gradient` (`garage.tscn:195`), `PreviewViewport` (`garage.tscn:242`), all
`mouse_filter = 2` (= `MOUSE_FILTER_IGNORE`).

So `CarScroll` inherits `Control.MOUSE_FILTER_STOP` — the documented default
(`mouse_filter` default value `0` in the Godot 4.7 `Control` class reference,
same page as above). A `STOP` control consumes mouse events over its **whole
rectangle**, not just where its content is drawn. A `ScrollContainer` is
left at `STOP` deliberately (it needs the wheel/drag).

Result:
* the rail's rectangle blocks the buttons underneath for **every** click in
  `[600,1320] × [762,1062]`, and
* the rail's own cards (rendered inside that rectangle, `garage_ui.gd:83-110`,
  cards `150×62` at `garage_ui.gd:148`) are drawn **on top of** the buttons —
  which is the "overlayed" the player sees.

The two buttons never receive a hover either, which is why they look dead.

### 2.4 Ruled out (so nobody re-investigates)

* `select_button.disabled = true` only happens when the player owns **zero**
  cars (`garage_ui.gd:73`); `Garage.new_from_save()` seeds all seven
  `Garage.STARTER_CARS` (`scripts/career/garage.gd:10-18, 36-44`), so in the
  shipped build the button is enabled.
* The buttons are correctly wired: `garage_ui.gd:61-64` connects
  `pressed` → `_on_select_pressed` / `_on_back_pressed` (`garage_ui.gd:333-338`).
* No other overlay exists in `garage.tscn` (`Footer` is 28→400 × H-20→H-4,
  i.e. ≥ 698 px away from the buttons horizontally, and only 2 px of vertical
  contact with the rail's bottom edge).
* No custom GUI theme is configured (`project.godot` has no `gui/theme/*` entry
  and there is no `*.tres` theme), so the default theme applies: the
  `ScrollContainer` panel is empty/transparent and only the cards draw. That
  matches the report that the *cards* are what overlays the buttons.
* `garage_ui.gd` has no `_input` / `_gui_input` / `_unhandled_input`, and the
  preview is not mouse-interactive (`PreviewViewport` is IGNORE), so nothing in
  the rail's area becomes unclickable as a result of this fix.

---

## 3. Design decisions

Options considered:

| # | Option | Verdict |
|---|--------|---------|
| A | Set `mouse_filter = 2` (IGNORE) on `CarScroll` so clicks fall through the empty part of the rail | **Rejected.** Fixes clicks only where no card is; where a card covers a button the card wins the click (cards are children of the rail and are picked before it). The cards still *draw over* the buttons — the player's actual complaint stays. |
| B | Move `SELECT`/`BACK` elsewhere: (B1) a bottom-right action bar on the root, (B2) reorder `ButtonsRow` above `StatsBox` inside the Garage tab VBox | **Rejected as primary.** B1 does not fit at 1280×720 (the free strip right of the rail, `x > W/2 + 360`, is only 252 px wide but the row needs 334 px). B2 works at any size (the row would sit under the class badge, far above `H−318`) but abandons the FH/GT-style bottom action position that the layout was built around. Kept as the fallback if the rail must stay centred — see §4 step 4. |
| C | **Keep the buttons where they are; confine the car rail to the vehicle-preview column (left-aligned, 640 px wide)** | **CHOSEN.** The rail was sized/centred without accounting for the info column, which already starts at x ≈ 698 (< rail right edge 1320 at 1920×1080). Anchoring the rail to the left edge of `Margin` (offset 28) with the same width as `PreviewPanel` puts it exactly under the preview, leaves the 30 px `MainRow` gutter as clearance, and is **width-independent** (the preview column is a fixed 640 px and `RightPanel` never starts left of 698, at any window size). It is a 5-line change in one node, touches no script, and preserves both the bottom rail and the bottom action buttons. |

Additional decisions:

* **Keep the rail's vertical band unchanged** (`offset_top = -318`,
  `offset_bottom = -18`). Only the horizontal anchoring changes, so the visual
  result is "the rail slides from centre-bottom to preview-bottom".
* **Do not touch `CarScroll.mouse_filter`.** After the fix the rail no longer
  overlaps anything interactive; leaving it at the default `STOP` keeps wheel
  and drag scrolling over the rail working (the documented reason
  `ScrollContainer` uses `STOP`).
* **Fallback `mouse_filter` hardening is not added**, because the geometry test
  in §5 is the real guard and a `STOP→IGNORE` change would silently break
  rail scrolling/drag in exchange for nothing.

---

## 4. Implementation steps (ordered)

### Step 1 — `scenes/ui/garage.tscn`: re-anchor `CarScroll` (lines 410-421)

Replace:

```
[node name="CarScroll" type="ScrollContainer" parent="."]
anchors_preset = 7
anchor_left = 0.5
anchor_top = 1.0
anchor_right = 0.5
anchor_bottom = 1.0
offset_left = -360.0
offset_top = -318.0
offset_right = 360.0
offset_bottom = -18.0
grow_horizontal = 2
grow_vertical = 0
```

with:

```
[node name="CarScroll" type="ScrollContainer" parent="."]
anchors_preset = 2
anchor_top = 1.0
anchor_bottom = 1.0
offset_left = 28.0
offset_top = -318.0
offset_right = 668.0
offset_bottom = -18.0
grow_horizontal = 2
grow_vertical = 0
```

Notes for whoever applies it:

* `anchors_preset = 2` is `PRESET_BOTTOM_LEFT`. `anchor_left`/`anchor_right` are
  omitted because `0.0` is their default — this is exactly the pattern the
  existing `Footer` node already uses (`garage.tscn:397-408`), so the loader
  sees a consistent preset + anchor/offset set (the `.tscn` only stores the
  explicit anchors/offsets; keep the preset hint in sync with them).
* `offset_left = 28.0` = `Margin.offset_left` (`garage.tscn:203`) so the rail is
  flush with the UI column; `offset_right = 668.0` = 28 + 640 =
  `PreviewPanel`'s right edge (`garage.tscn:219`) so the rail is exactly as wide
  as the preview above it.
  → new rect: **x ∈ [28, 668]** (unchanged vertically: y ∈ [H−318, H−18]).
  → clearance to `RightPanel` (x ≈ 698) = **30 px = the `MainRow` separation**.
* `grow_horizontal`/`grow_vertical` are left as they are: a `ScrollContainer`
  reports 0 minimum size on any axis whose scroll mode is not `DISABLED`
  (default is `SCROLL_MODE_AUTO`, `garage.tscn:410` sets neither), so the node
  can never outgrow the offsets.
* Doing this in the Godot editor (select `CarScroll` → Layout → Anchors
  Preset → Bottom Left, then set the four offsets) is equivalent and preferable
  if a GUI is available; the hand-edit above is exact.

Expected result at 1920×1080: rail `[28,668] × [762,1062]`, buttons
`≈[700,1036] × [938,984]` → **no intersection**; at 1280×720 the rail is
`[28,668] × [402,702]` and the buttons `≈[700,1036] × [578,624]` → still clear
(30 px gutter is constant because the columns are, too).

### Step 2 — verify the rail's own behaviour is unchanged

`CarRail` (`garage.tscn:423`, `alignment = 1`) is built at runtime by
`garage_ui.gd:83-110`; card sizes/separations (`150×62` and `separation 16`,
`garage_ui.gd:148`, `garage_ui.gd:102`) are untouched, so a brand row wider than
the rail simply uses the `ScrollContainer`'s horizontal scrollbar — behaviour
that already exists today for any row of 5+ cards (5×150 + 4×16 = 814 > the old
720 px rail). No script change is required.

### Step 3 — (optional polish, only if the reviewer asks) tighten the row gap

At 640 px a 4-card row is 648 px (4×150 + 3×16), so it shows a horizontal
scrollbar. If that is unwanted, do **one** of:

* widen the rail to `offset_right = 692.0` (664 px; still 6 px clear of
  `RightPanel` at ≈698), or
* change `garage_ui.gd:102` `row.add_theme_constant_override("separation", 16)`
  to `12` (4 cards → 636 px, and the rail stays exactly aligned to the preview).

Do **not** do both. Default: accept the scrollbar (it is the shipped behaviour
for bigger rosters).

### Step 4 — fallback (only if the owner rejects moving the rail)

Move `ButtonsRow` (`garage.tscn:359-387`, a whole subtree) so it is **not** the
last child of `Margin/MainRow/RightPanel/TuningTabs/Garage`: paste it directly
after `BadgeRow` (`garage.tscn:321-345`), i.e. before `StatsBox`
(`garage.tscn:347`). With `StatsBox` retaining `size_flags_vertical = 3`, the
row then sits right below the class badge, far above the rail band at every
window height. `%SelectButton` / `%BackButton` keep resolving (unique names are
scene-wide), `garage_ui.gd` needs no change, and no test references the row's
parent path.

### Step 5 — housekeeping

* Run `graphify update .` after the change (AST-only, no API cost). A large
  rewrite of `graphify-out/graph.json` is expected, not churn.
* Do **not** commit `.uid` files (`git status --short` must not list `*.uid`).

---

## 5. Test plan

### 5.1 New suite — `tests/suites/test_garage_layout.gd`

`extends GdUnitTestSuite`, house style copied from
`tests/suites/test_garage_brands.gd` (`scene_runner("res://scenes/ui/garage.tscn")`
+ `await runner.simulate_frames(2)`, `assert_that(...).is_equal` /
`is_false` / `is_true`). **gdUnit treats GDScript warnings as errors**
(`var x := some_func_returning_Variant()` will fail the suite load), so every
`get_node(...)` result must be typed explicitly. Run each test through
`assert_that(node).is_not_null()` + an early `return` before dereferencing, as
`test_garage_brands.gd:139-145` does.

1. **`test_garage_actions_not_covered_by_car_rail`** — the regression guard.
   Get `select_button := scene.get_node("%SelectButton") as Button`,
   `back_button := scene.get_node("%BackButton") as Button`,
   `rail := scene.get_node("CarScroll") as ScrollContainer`, then:
   ```gdscript
   assert_that(rail.get_global_rect().intersects(select_button.get_global_rect())).is_false()
   assert_that(rail.get_global_rect().intersects(back_button.get_global_rect())).is_false()
   ```
   (`Rect2.intersects(other, include_borders = false)`.) This fails on today's
   tree (the rail contains both buttons) and passes after step 1 — at *any*
   window size the suite runs at, because the fix is width-independent.
2. **`test_garage_rail_stays_left_of_the_info_column`** — asserts the chosen
   invariant rather than the magic numbers:
   ```gdscript
   var rail := scene.get_node("CarScroll") as Control
   var right_panel := scene.get_node("Margin/MainRow/RightPanel") as Control
   var preview := scene.get_node("Margin/MainRow/PreviewPanel") as Control
   assert_that(rail.get_global_rect().end.x).is_less_equal(right_panel.get_global_rect().position.x)
   assert_that(rail.get_global_rect().end.x).is_less_equal(preview.get_global_rect().end.x)
   assert_that(is_equal_approx(rail.get_global_rect().position.x, preview.get_global_rect().position.x)).is_true()
   ```
   (Use a tolerance-friendly comparison if `is_equal_approx` on floats is
   preferred; gdUnit's vector `is_equal_approx` needs a **same-type** approx
   argument.)
3. **`test_select_and_back_receive_real_clicks`** — the strongest gate: a real
   GUI hit-test through the viewport, not a bare `pressed.emit()`.
   `GdUnitSceneRunnerImpl.simulate_mouse_move()` →
   `Input.warp_mouse()` + `Input.parse_input_event()` and
   `simulate_mouse_button_pressed()` → press+release
   (`addons/gdUnit4/src/core/GdUnitSceneRunnerImpl.gd:207-214, 245-248`), so the
   event goes through Godot's normal GUI picking and the topmost `STOP` control
   under the cursor receives it — i.e. this test fails today and passes after
   the fix.
   Recipe:
   ```gdscript
   var select_button := scene.get_node("%SelectButton") as Button
   var back_button := scene.get_node("%BackButton") as Button
   # Detach the live handlers first: BACK would change scene, SELECT writes a save.
   select_button.pressed.disconnect(Callable(scene, "_on_select_pressed"))
   back_button.pressed.disconnect(Callable(scene, "_on_back_pressed"))
   var hits := [0, 0]
   select_button.button_down.connect(func() -> void: hits[0] += 1)
   back_button.button_down.connect(func() -> void: hits[1] += 1)
   await runner.simulate_mouse_move(select_button.get_global_rect().get_center())
   await runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
   await runner.simulate_mouse_move(back_button.get_global_rect().get_center())
   await runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
   assert_that(hits[0]).is_equal(1)
   assert_that(hits[1]).is_equal(1)
   ```
   If headless event delivery proves unreliable on this box (godot docs are
   quiet about headless GUI picking; the runner warns it needs a foreground
   window — `GdUnitSceneRunnerImpl.gd:81-88`), keep tests 1-2 (pure geometry,
   zero flake) as the gate and note in the suite header that the click path is
   covered by the manual playtest in §5.3. Do **not** weaken test 1 to
   compensate.
4. **Optional `test_rail_card_still_clickable_after_move`** — same real-click
   mechanism against the first card in `%CarRail`, asserting the selection
   changed (`%CarNameLabel.text`), proving the narrowed rail did not break card
   input.

Add `"test_garage_layout"` to `CONTENDED_SUITES` in
`tools/gdunit_parallel.py:107-121` (instancing `garage.tscn` runs
`Garage.new_from_save()`, which seeds missing starter cars and therefore writes
`user://saves/slot_0.json` — same reason `test_garage_tuning` is listed; the
list is only consulted with `--no-isolate-user-data`, so this is defensive).

### 5.2 Suites to re-run (they already touch this scene)

| suite | what it asserts (must stay green) |
|-------|-----------------------------------|
| `tests/suites/test_garage_brands.gd:133` | `%CarRail` = one VBox section per brand, header emblem+label, one HBox row per section, **zero focusable controls inside the rail** (`:169-175`) |
| `tests/suites/test_garage_brands.gd:177` | card `owned_index` meta is a permutation of the owned roster; pressing a card selects by meta, not DOM order |
| `tests/suites/test_garage_tuning.gd:211` | `%TuningTabs` has exactly 3 pages titled `Garage` / `Tune` / `Paint` |
| `tests/suites/test_audio_feel_layers.gd:226` | a rail card press emits exactly one menu blip |

None of them assert the rail's or the buttons' geometry or parent paths, which
is why step 1 is safe; they are still the "did I break the garage" net.

### 5.3 Manual playtest (the player's own check)

```
play_game.bat            (or start_game.bat)
```
main menu → GARAGE → confirm §1 criteria 1-3 by hand, then optionally capture
the screen and look at it (`capture_game_window`, or `gemini_vision.bat ask
--image .vision/captures/garage.PNG --prompt "is any card drawn over the
SELECT/BACK buttons?"`).

### 5.4 Running the gate (cmd.exe, per `docs/GDUNIT_GATE.md`)

```bat
cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE! --headless --import . 2>&1" | findstr /i "SCRIPT ERROR Parse Error"
cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE! --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/suites/test_garage_layout.gd -a res://tests/suites/test_garage_brands.gd -a res://tests/suites/test_garage_tuning.gd -a res://tests/suites/test_audio_feel_layers.gd > _gdunit.txt 2>&1"
findstr /c:"Overall Summary:" _gdunit.txt
```

Rules that still apply: import probe **first**; `-a` is repeatable but
comma-joined paths silently run 0 tests and still exit 0; a suite aborts at its
first failure, so compare the executed count with the number of `func test_` in
the file; use `%GODOT_EXE_CONSOLE%` and sanity-check `_gdunit.txt` is not
0 bytes. Full-suite runs go through `py tools\gdunit_parallel.py -j 4`
(GDUnit's perf-gate suite is a wall-clock benchmark and stays in its serialized
shard).

---

## 6. Risks / gotchas

* **`anchors_preset` vs anchors in a hand-edit.** The `.tscn` stores the preset
  hint *and* the explicit `anchor_*` / `offset_*` values; keep them consistent
  (`preset 2` = bottom-left ↔ `anchor_left/right = 0`, `anchor_top/bottom = 1`),
  exactly as `Footer` (`garage.tscn:397-408`) does. An inconsistent pair is the
  one case where the loader result depends on which property is applied last.
* **Fixed-width coupling.** The rail's 640 px mirrors `PreviewPanel`'s
  `custom_minimum_size.x` (`garage.tscn:219`). If someone later widens the
  preview column or adds an Expand flag to `PreviewPanel`, the rail would no
  longer match — test 2 (`assert_that(...).is_less_equal(...)`) is the tripwire.
* **Horizontal scrollbar at 4 cards/row.** 4×150 + 3×16 = 648 > 640. Already
  the shipped behaviour for 5+ card rows (814 > the old 720 rail width), so this
  is not a regression, but it is visible. Step 3 gives the two one-line ways to
  avoid it (choose one, not both).
* **Do not "fix" this with `mouse_filter`/`z_index` only.** `STOP→IGNORE` on the
  rail leaves the cards drawing over the buttons (player still can't click
  where a card covers one, and the visual complaint remains); raising the
  buttons' `z_index` moves the drawing but not the GUI hit test — Godot's
  `mouse_entered` docs explicitly note `z_index` does not decide which Control
  receives the event. The rects must stop overlapping.
* **`SELECT` writes the save.** `Garage.set_active_car` (`garage_ui.gd:335`)
  persists via `SaveManager`; test 3 therefore disconnects the live handlers
  before clicking, otherwise it reacts the same way the 13 save-touching suites
  do (fine, but unnecessary).
* **Anything above the buttons?** After step 1 the only controls between the
  buttons and the viewport are the buttons themselves (`Footer` and `CarScroll`
  never reach x ≥ 698, and ancestors are picked *after* their children). No
  extra guard is needed.
* **Do not chase the `Tune`/`Paint` tabs.** `TabContainer` shows one page at a
  time, so the buttons are only meant to be clickable on the `Garage` tab;
  that is unchanged.
* Godot may rewrite `garage.tscn` on the next editor save (reordering nothing,
  but normalising the numbers) — that is expected, keep the values, not the
  byte-for-byte diff.

---

## 7. Do NOT touch (owned by concurrent tasks)

* Car assets / materials / visuals: `assets/cars/**`, `resources/cars/**`,
  `scripts/vehicle/car_visuals.gd`, and any camera script
  (`scripts/camera/**`).
* Track-select / race-menu UI (`scenes/ui/track_select.tscn`,
  `scripts/ui/track_select.gd`, race HUD/menus).
* Vehicle audio (`scripts/audio/**`, `UiBlip` wiring beyond reading it).
* Track systems: `scripts/track/**`, `scenes/track/**`,
  `scripts/track/track_registry.gd`.
* Everything under `tests/` belongs to whoever adds the suite in §5.1; this plan
  only *proposes* the new file, it does not add it.

This task owns only `scenes/ui/garage.tscn` and `scripts/ui/garage_ui.gd`
(and, if the fallback in §4 step 4 is chosen, still only those two files).

---

## 9. STATUS — implemented (2026-10-16)

Option **C** was applied (keep the buttons, confine the rail to the
vehicle-preview column). The fallback in §4 step 4 was **not** used;
`scripts/ui/garage_ui.gd` was **not** touched.

### 9.1 Code change — `scenes/ui/garage.tscn` (`CarScroll`, now lines 410-419)

Exactly §4 step 1, byte-for-byte:

| property | before | after |
|----------|--------|-------|
| `anchors_preset` | `7` (bottom-centre) | `2` (bottom-left) |
| `anchor_left` | `0.5` | *(removed; defaults to `0.0`)* |
| `anchor_right` | `0.5` | *(removed; defaults to `0.0`)* |
| `offset_left` | `-360.0` | `28.0` |
| `offset_right` | `360.0` | `668.0` |
| `anchor_top` / `anchor_bottom` | `1.0` / `1.0` | unchanged |
| `offset_top` / `offset_bottom` | `-318.0` / `-18.0` | unchanged |
| `grow_horizontal` / `grow_vertical` | `2` / `0` | unchanged |

New rail rect: **x ∈ [28, 668]** (640 px, flush with `Margin`'s left inset and
exactly as wide as `PreviewPanel`), y band unchanged `[H−318, H−18]`. The
`MainRow` 30 px separation remains as the clearance to `RightPanel` (x ≈ 698), so
the SELECT/BACK row (x ∈ [≈700, ≈1036]) is never covered. `CarScroll.mouse_filter`
was deliberately **not** touched (stays `STOP`, so wheel/drag scrolling is
unchanged) and no `z_index` was used — see §3.

### 9.2 Test added — `tests/suites/test_garage_layout.gd`

New suite, house style from `test_garage_brands.gd`. It snapshots/restores
`user://saves/slot_0.json` in `before_test`/`after_test` (instancing
`garage.tscn` runs `Garage.new_from_save()`, which seeds starters and writes the
slot). Three deterministic **geometry** tests, each `scene_runner(garage.tscn)`
+ `await runner.simulate_frames(2)`:

1. `test_garage_actions_not_covered_by_car_rail` — the regression guard:
   `rail.get_global_rect().intersects(select|back_button.get_global_rect())` is
   `false` (fails pre-fix, passes post-fix), plus a non-degenerate-rect sanity
   check (`rail.size.x > 0`, `select_button.size.x > 0`).
2. `test_garage_rail_stays_left_of_the_info_column` —
   `rail.end.x ≤ RightPanel.position.x`, `rail.end.x ≤ PreviewPanel.end.x`, and
   `rail.position.x ≈ PreviewPanel.position.x` (the chosen invariant and the
   tripwire for the fixed-width coupling risk in §6).
3. `test_garage_rail_clears_the_action_column` — strict **horizontal**
   separation: `rail.end.x ≤ select|back_button.position.x`. Catches a future
   re-centring that clears the buttons vertically but still sits under the info
   column.

### 9.3 Why there is no real-click test

Plan §5.1 item 3 (a real mouse click through the viewport) **cannot run in this
gate**. The headless run passes `--ignoreHeadlessMode`, and gdUnit itself
documents that UI-interaction tests do not work headless: *"Godot 'InputEvents'
are not transported by the Godot engine in headless mode and therefore have no
effect in the test!"*
(`addons/gdUnit4/src/core/runners/GdUnitTestCIRunner.gd:359-361`). No existing
suite in the repo simulates mouse input for this reason. Per §5.1 the click path
is therefore covered by the manual playtest in §5.3, and test 1 was **not**
weakened to compensate. If a future gate runs gdUnit with a real window (no
`--headless`), §5.1 item 3 can be added verbatim.

### 9.4 Parallel-gate bookkeeping

`"test_garage_layout"` was added to `CONTENDED_SUITES` in
`tools/gdunit_parallel.py` (between `test_event_rewards` and `test_garage_tuning`,
line ~114) per §5.1: instancing the garage writes `user://saves/slot_0.json`. The
list is only consulted under `--no-isolate-user-data`, so this is defensive.

### 9.5 What the gate must confirm

* `test_garage_layout.gd` — 3/3 green.
* The "did I break the garage" net stays green: `test_garage_brands.gd`,
  `test_garage_tuning.gd`, `test_audio_feel_layers.gd` (none assert rail/button
  geometry or parent paths — see §5.2).
* Player check by hand (§5.3): main menu → GARAGE, SELECT/BACK are fully visible,
  hover-highlight, and clickable; the rail still shows every brand section and
  scrolls; cards still select.

### 9.6 Open risks / not covered here

* The 3 tests assert **disjoint rects and the column invariant**, not paint
  order. If someone later adds a `z_index`/overlay above the buttons, test 1
  would not catch it (the geometry would still be disjoint) — but no such
  overlay exists today and §3/§6 forbid that approach.
* Horizontal scrollbar at 4 cards/row (§6) is unchanged shipped behaviour;
  §4 step 3 was not applied (kept the rail aligned to the preview at 640 px).
