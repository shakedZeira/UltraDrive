# UltraDrive — Race Tab: Track-Layout Preview + GT7-style Event Details

> **User report (2026-10-16):** *"Show the track layout when pressing on tracks in the
> 'race' tab, and also show the event itself like Gran Turismo (laps, track, rival
> cars…)."*
>
> **Scope:** the race tab is `scenes/ui/track_select.tscn` (reached from the main menu's
> RACE button, `scripts/ui/main_menu.gd:30-31`). Today it already shows a world/circuit
> map, a card list and a text line of meta info — but **no picture of the circuit shape**
> and **no event card** (laps / class / field). This plan adds:
> (a) a **track-layout preview** (the actual driven centerline of the selected layout),
> and (b) a **GT7-style event panel**: event name, layout, class, type, laps, best lap,
> AI difficulty, opponent count and the rival field.
>
> **Written:** 2026-10-16 · **Inputs:** the user report verbatim; `scripts/ui/track_select.gd`;
> `scenes/ui/track_select.tscn`; `scripts/ui/track_map.gd`; `scripts/ui/map_roads.gd`;
> `scripts/track/track_registry.gd` (READ ONLY); `autoload/race_manager.gd`;
> `scripts/race/race_ui.gd`; `scripts/track/*.gd` + `scripts/test_circuit.gd`;
> `scripts/vehicle/car_visuals.gd`; `autoload/game_state.gd`;
> `docs/plans/race_menu_world_map_plan.md` + `docs/plans/race_menu_map_expansion_plan.md`
> (the shipped circuit map this builds on); `docs/GDUNIT_GATE.md`; `AGENTS.md`.
>
> **Format:** 1 new editor tool + 1 new baked-data dir + 2 new UI scripts + 1 menu script
> edit + `.tscn` nodes + 1 new suite. **No** race-semantics, registry or track-geometry
> change.

---

## 1. Goal + player-verifiable acceptance criteria

Turn the race tab's selection into a GT7-style race-entry panel: pick a circuit, see the
circuit's shape and exactly what you are about to race.

Player-verifiable (each checkable by hand in the running game):

1. **Layout preview appears.** Opening the race tab shows a circuit-shape picture for the
   selected event; Sunset Oval / Northern Isle Speedway read as ovals, Mountain Pass as a
   wavy closed loop. Selecting another card or pin swaps the shape **on the same screen**
   (no scene change).
2. **Event facts are correct.** The panel names the event (pin label), the layout
   (`TrackRegistry` `display_name`), `CLASS <difficulty>`, the `circuit_type`, the laps
   (`laps_default`) and the best lap for that layout.
3. **The field is described honestly.** The panel shows AI difficulty (`GameState.ai_difficulty`),
   the opponent count (`GameState.opponents`, clamped 0–7) and, per grid slot, the car the
   player will see (grid visual) + its skill tier. When the chosen layout will field **no**
   rivals, the panel says so instead of advertising a grid (today only Northern Isle
   Speedway publishes a rival centerline — see §2).
4. **Race start is unchanged.** Pressing the start button still runs
   `RaceManager.queue_race(laps_default)` → scene launch; the HUD lap counter shows the same
   lap total as before this change.
5. **Nothing else regresses.** BACK still returns to the main menu; the card list is still
   the keyboard/controller path; the map pins still select.
6. **A layout with no baked preview still degrades gracefully** (the panel shows a
   "layout map unavailable" state, never a broken/blank draw or a crash).

---

## 2. Current state — VERIFIED with `file:line`

### 2.1 Race tab (the screen the user means)
- Entry: `scripts/ui/main_menu.gd:30-31` → `SceneTransition.flash_to_scene("res://scenes/ui/track_select.tscn")`.
- `scripts/ui/track_select.gd` (`class_name TrackSelect extends Control`):
  - `:19-22` palette consts (`ACCENT`, `CARD_DARK`, `CARD_ACTIVE`, `TEXT_MUTED`).
  - `:24-33` `@onready` `%TrackGrid`, `%TrackNameLabel`, `%MetaLabel`, `%LapsLabel`,
    `%BestLapLabel`, `%RegionButton`, `%TrackMap`, `%PlayButton`, `%BackButton`, `$UiBlip`.
  - `:59-82` `_ready()` — wires Play/Back/Region, builds cards, selects `_pin_ids[0]`,
    `grab_focus()` card 0 (with the documented blip-debounce reset on `:76`).
  - `:84-124` `_build_cards()` — one `Button` per **visible** pin (`track_map.visible_pin_ids()`,
    `:90`), `custom_minimum_size = Vector2(0, 92)` (`:97`), `FOCUS_ALL`, blips bound.
  - `:156-165` `select_pin()` (primary), `:169-173` `select_track()` (compat wrapper =
    first pin driving that layout), `:176-196` `set_region()`, `:214-228`
    `_update_pin_panel()` (writes name/meta/laps/best-lap), `:233-258` `_best_lap_text()`
    (per-layout, read-only), `:275-282` `_on_play_pressed()`
    (`RaceManager.queue_race(laps)` → `launch_callback(scene_path)`).
- `scenes/ui/track_select.tscn` (`load_steps=14`, `:1`):
  - Left: `Margin/Row/MapPanel` (`:163-168`, `custom_minimum_size = Vector2(1000, 640)`) →
    `%TrackMap` (`:170-181`).
  - Right: `Margin/Row/RightColumn` (`:183-186`, `custom_minimum_size = Vector2(430, 0)`,
    `separation = 10`) → `TitleLabel` (`:188`), `%RegionButton` (`:195`),
    `%TrackNameLabel` (`:206`), `%MetaLabel` (`:214`), `%LapsLabel` (`:222`),
    `%BestLapLabel` (`:229`), `%CardScroll` (`:236-240`, `follow_focus = true`) →
    `%TrackGrid` (`:242-248`, `columns = 1`), `ButtonsRow` (`:250`) → `%PlayButton`
    (`:255`) / `%BackButton` (`:270`). `Footer` (`:284-295`).
- Map: `scripts/ui/track_map.gd` — pins + labels; the **headless discipline** to copy is
  `:23-26` (compute everything outside `_draw()`) and `:88-94` `_ensure_projection()`.

### 2.2 Registry (source of truth — consume dynamically, never edit)
- `scripts/track/track_registry.gd:7-29` `tracks`: `oval` / `mountain_pass` /
  `northern_isle` with `display_name`, `scene_path`, `laps_default`, `difficulty`,
  `circuit_type`. `:31-41` accessors.
- `:72-257` `pins`: 36 circuits → layouts (many-to-one; `home_*` first).
- `:271-308` accessors (`get_pin_ids`, `track_for_pin`, `pins_for_track`, …).
- **A concurrent task is adding a new track entry / track scenes** — this plan must never
  hardcode ids or lists.

### 2.3 Race flow + where the field comes from
- `autoload/race_manager.gd:99-102` `queue_race(laps)`; `:119-122` `consume_pending_race()`.
- `scripts/race/race_ui.gd:120-134` the HUD commits the pending race on its first frame and
  calls `RaceManager.configure_default_rivals()` **only when `rival_roster` is empty**
  (`:130-131`), then `start_race(VehicleManager.get_all_cars(), laps)` (`:132`).
- `autoload/race_manager.gd:267-293` `configure_default_rivals()`:
  `count = GameState.clamp_opponents(GameState.opponents)` (`:270`), anchor
  `GameState.normalize_difficulty(GameState.ai_difficulty)` (`:277`), then **one spec per
  slot, all with the PLAYER's config** (`:276-280`, `_player_config` `:307-310`, starter-car
  fallback) and tier `_tier_for_slot(anchor, i)` (`:295-303`, `_TIER_SPREAD` `:20`).
- **Critical truth (verified by grep):** the roster is only built when the track published a
  rival centerline — `:268-269` returns early when `rival_centerline.size() < 2`, and
  `set_rival_centerline` is called from **exactly one place in the tree**:
  `scripts/track/northern_isle.gd:131`. So **oval (test_track) and mountain_pass field no
  rivals today**; only Northern Isle Speedway does.
- Grid **visuals** cycle a real-car GLB roster: `scripts/vehicle/car_visuals.gd:106-110`
  `RIVAL_VISUALS` (starter_coupe / muscle_car / rally_hatch) via
  `rival_visual_for(index)` `:114-116`; tier colours `:94-100` `RIVAL_PALETTE`. The rival's
  **physics** config is the player's (`race_manager.gd:276-280`) — the panel must say the
  grid is visuals, not that the field out-classes the player.
- `autoload/vehicle_manager.gd:8-9` `player_car`/`all_cars`, `:30-31` `get_all_cars()`.
- `autoload/game_state.gd:27-31` `DEFAULT_OPPONENTS = 5`, `MAX_OPPONENTS = 7`,
  `AI_DIFFICULTIES = ["Novice","Skilled","Expert"]`; `:55-56` live values; `:92-102`
  `clamp_opponents` / `normalize_difficulty`.
- Player's car id for the panel: `scripts/career/garage.gd:36` `new_from_save()`,
  `:66` `get_active_car()` (read-only) — falls back to `starter_car` exactly like
  `race_manager._player_config` (`:305-310`). Car display fields:
  `scripts/vehicle/car_config.gd:7` `car_name`, `:8` `car_class`, `:17` `brand_display_name`;
  catalog `resources/cars/*.tres` (8 files today).

### 2.4 Where a layout's shape can come from (the hard part)
The three shipped layouts each build their centerline differently, and **two of them are not
reachable without running the scene**:

| layout | source | reachable off-tree? |
|---|---|---|
| `mountain_pass` | `scripts/track/mountain_pass.gd:201-212` `_generate_road_points()` — pure, no instance state (36 pts, deterministic) | ✅ call the method on an off-tree instance |
| `northern_isle` | `scripts/track/northern_isle.gd:108` `road_points = NorthernIsleLayout.build_centerline()`; the builder is static — `scripts/track/northern_isle_layout.gd:1,88` | ⚠️ static on a **separate** class (needs per-layout knowledge) |
| `oval` (test_track) | `scripts/test_circuit.gd:36-42` — points built **inline in `_ready()`** | ❌ not exposed anywhere |

- `scripts/track/track_builder.gd:20` retains `_track_points` (copied at `:80`) — reachable
  from a built scene's `TrackBuilder` child (`o:98-103` names the mesh child), so a scene
  that HAS run `_ready` can be mined for its centerline.
- **Adding a track scene to the tree at runtime from the menu is unsafe:** every track scene
  instances `scenes/ui/hud.tscn` (`scenes/track/mountain_pass.tscn:7`,
  `scenes/track/northern_isle.tscn:7`, `scenes/test/test_track.tscn:7`), and
  `race_ui._ready()` **consumes the pending race** (`scripts/race/race_ui.gd:106-107`) —
  a menu-side instantiation could eat the queued laps; it would also register a phantom
  player car in `VehicleManager` and, for Mountain Pass, trigger the ~3.3 s terrain bake
  (`scripts/track/mountain_pass.gd:48-52`).
- Reusable 2D projection to draw the shape: `scripts/ui/map_roads.gd:441-469`
  `compute_fit(content_points, fallback, draw_size, inset)` and `:472-476`
  `world_to_screen(world_pos, fit)` — the same pair `world_map.gd`/`minimap.gd` use. No
  preview/thumbnail tech exists today (grep for preview/thumbnail in `scripts/ui/` finds
  only the garage's 3D car preview, `scripts/ui/garage_ui.gd:235,319` — unrelated, and the
  garage is owned by another task).

### 2.5 Tests that must stay green
- `tests/test_track_system.gd:22-42` `test_track_select_builds_one_card_per_pin` (card count
  == visible pins; card label text contains label/`CLASS x`/type; first-pin scene path).
- `tests/test_track_system.gd:44-61` play/back launch paths; `:63-76`
  highlight-by-pin-index.
- `tests/suites/test_race_menu_map.gd` — 12 + expansion tests; menu ones at `:124-193` and
  `:292-311` (region toggle counts, `select_track` → `home_northern_isle`, play queues 2 laps).
- `tests/suites/test_audio_feel_layers.gd:194-224` — play blip fires **exactly once**;
  `%TrackGrid` child 0 is a `Button` with the blip bound.
- `tests/suites/test_menu_video_background.gd:24` — loads `track_select.tscn` as one of the
  menu scenes (node-presence expectations).
- `tests/suites/test_race_loop.gd:391-400` — `select_track("mountain_pass")` →
  `consume_pending_race() == 2`.
- `tests/suites/test_race_rivals.gd:140-182` pins the roster/tier-spread contract the panel
  will display (field size 5 at default, tier spread, no-op without a centerline).

---

## 3. Design decisions (options considered → chosen)

### 3.1 Where the detail view lives → **in-place detail panel in `RightColumn`** (chosen)
- **Option A (chosen): enrich the existing right column.** Add the layout preview + event
  rows above the card list. Keeps `%PlayButton` / `%BackButton` / `%TrackGrid` /
  `%TrackNameLabel` and the whole `select_pin` → `_on_play_pressed` flow intact, so every
  test in §2.5 keeps passing verbatim and the keyboard path is unchanged.
- **Option B (rejected for MVP, noted in §7): a separate entry sub-screen**
  (`scenes/ui/race_event.tscn`) opened by a card press, like GT7's actual event screen.
  It is more faithful but changes the card-press semantics (`test_track_system.gd:44-61`
  calls `_on_play_pressed()` straight after `select_track`), needs a new scene-change path
  through `GameState`/`scene_transition` (both do-not-touch), and doubles the UI surface.
  The panel in A already answers the user's request on the screen they are looking at, so B
  is a follow-up, not a blocker.
- Layout: preview at the **top of the right column** (it is the "hero" element, GT7-style),
  event rows under it, rival rows under those, card list scroll below as today.

### 3.2 How the layout preview is generated → **baked preview data + a runtime resolver**
Chosen because no single runtime path can serve all three layouts (§2.4), and running track
scenes inside the menu is unsafe (§2.4).

- **Bake once, offline.** New editor tool `tools/gen_track_layouts.gd` (a `SceneTree` script
  run via `--headless -s`, one Godot process, `%GODOT_EXE_CONSOLE%`):
  for **every id in `TrackRegistry.get_track_ids()`** — no id literals anywhere — it
  instantiates the scene into the tree, waits 2 frames, then extracts the centerline with a
  documented capability chain:
  1. `root.get("road_points")` when present and `size() >= 3` (mountain_pass
     `mountain_pass.gd:38`, northern_isle `northern_isle.gd:63`);
  2. else the first child that `is TrackBuilder` → `_track_points` (`track_builder.gd:20`)
     — this is what covers the oval (`test_circuit.gd:32-42`);
  3. else → record `"has_layout": false` (never guess).
  It also records `"rival_centerline": RaceManager.rival_centerline.size() >= 2` read right
  after the frames — the ground truth for §2.3 — then frees the scene and writes
  `resources/ui/track_layouts/<track_id>.json` (`{ "scene_path", "points": [[x,y,z]…],
  "closed", "has_layout", "rival_centerline", "generated" }`). Output dir created with
  `DirAccess.make_dir_recursive_absolute`.
- **Read at runtime.** New `scripts/ui/track_layout_source.gd`
  (`class_name TrackLayoutSource extends RefCounted`, static-only + in-memory cache):
  `points(track_id) -> Array[Vector3]`, `has_rival_centerline(track_id) -> bool`,
  `has_layout(track_id) -> bool`, `preview_path(track_id) -> String`. JSON first; if the file
  is missing (a track added after the last bake), fall back to the **documented convention
  probe**: `load(scene_path).instantiate()` **off-tree only**, and if it
  `has_method("_generate_road_points")` call it (no tree entry, no `_ready`, no bake, no HUD);
  else return `[]` → the UI shows the "layout map unavailable" state.
- **Why not runtime-only:** the oval's points live inside `_ready()` and northern_isle's
  builder is a separate static class, so runtime-only would need id literals (banned) or an
  unsafe tree entry. **Why not a static shape table in the UI:** it would drift from the real
  geometry and hardcode layouts. **Why not edit track scripts to expose points:** do-not-touch
  (a concurrent task owns `scripts/track/**`, `scenes/track/**` and the registry).

### 3.3 Where rival data comes from → **mirror `RaceManager` read-only + the baked
`rival_centerline` flag**
- Count/anchor: `GameState.clamp_opponents(GameState.opponents)` and
  `GameState.normalize_difficulty(GameState.ai_difficulty)`.
- Per-slot tier: read-only call `RaceManager._tier_for_slot(anchor, i)` — **deliberate**: it
  is the same ladder `configure_default_rivals()` uses (`race_manager.gd:280,295-303`), so
  duplicating `_TIER_SPREAD` in UI code would be a guaranteed drift bug. The call is pure
  (no state, no RNG) and GDScript exposes it; a comment records the intent.
- Per-slot car: `CarVisuals.rival_visual_for(i)` (`car_visuals.gd:114-116`) → `car_id` →
  `load("res://resources/cars/%s.tres" % car_id)` for `car_name`/`car_class`; fall back to
  the raw id when a `.tres` is missing. Labelled `GRID VISUALS` so nobody reads it as the
  rival's physics spec.
- **Gate:** the rival block only renders as a field when
  `TrackLayoutSource.has_rival_centerline(track_id)` is true; otherwise it prints
  `AI FIELD: NONE ON THIS LAYOUT` plus the difficulty/opponent settings that *would* apply.
  This prevents the panel from promising a grid the race will not build (§2.3).

### 3.4 Preview drawing
- New `scripts/ui/track_layout_preview.gd` (`class_name TrackLayoutPreview extends Control`),
  a sibling of `TrackMap` in the right column:
  - `set_layout(track_id: String)` — pulls points from `TrackLayoutSource`, computes the fit
    **in the setter** (`MapRoads.compute_fit(points, fallback, size, INSET)`), stores it, and
    `queue_redraw()`; `_notification(NOTIFICATION_RESIZED)` recomputes. Same headless rule as
    `track_map.gd:23-26` — nothing depends on `_draw()` having run.
  - `projected_points() -> PackedVector2Array` (testable), `has_layout() -> bool`,
    `layout_id() -> String`.
  - `_draw()`: panel background (reuse the palette), the **closed centerline** as a
    `draw_polyline` (2–3 px, `ACCENT`), a start/finish tick at `points[0]`, and a dim
    "no layout" caption when `has_layout()` is false.
- Style: ACCENT line on a `CARD_DARK` panel, consistent with the existing palette and card
  styling (`track_select.gd:19-22,126-133`).

### 3.5 Event panel content (GT7-style, all from real state)
`%TrackNameLabel` stays the event name; keep `%MetaLabel` / `%LapsLabel` / `%BestLapLabel`
as-is; add rows: `DIFFICULTY: SKILLED · OPPONENTS: 5` (`%FieldSummaryLabel`) and the rival
rows (`%RivalsBox`), and `%PlayButton` text becomes `START RACE` (name unchanged — tests
look the button up by `%PlayButton`, not by text).

---

## 4. Implementation steps (ordered; exact paths / nodes / functions)

Never run two Godot processes at once; read `docs/GDUNIT_GATE.md` before the first headless
run; resolve the console binary via `godot_path.bat` (`AGENTS.md` false-green trap).

### Phase 0 — bake tool + data
1. **New** `tools/gen_track_layouts.gd` (`extends SceneTree`, `--headless -s` runnable):
   - `_initialize()`: `DirAccess.make_dir_recursive_absolute("res://resources/ui/track_layouts")`;
     for each `track_id` in `TrackRegistry.get_track_ids()`:
     `var packed: PackedScene = load(TrackRegistry.get_scene_path(track_id))`, `var root := packed.instantiate()`,
     `get_root().add_child(root)`, `await process_frame` ×2, extract (`road_points` →
     `size() >= 3`, else first `TrackBuilder` child's `_track_points`), capture
     `RaceManager.rival_centerline.size() >= 2`, `root.queue_free()`, await a frame.
   - Write `resources/ui/track_layouts/<track_id>.json` with
     `{"scene_path", "points", "closed": true, "has_layout", "rival_centerline", "generated"}`;
     `print` a per-track summary; `quit(0)`.
   - Full type annotations (gdUnit-style hygiene; the tool is not a suite but stays
     warning-clean so `--import` stays quiet).
2. **Run it once** (`%GODOT_EXE_CONSOLE% --headless -s res://tools/gen_track_layouts.gd`),
   confirm one JSON per registry layout and that the oval's points are a 32-point ring while
   mountain_pass has 36 — the tool's own numbers are the smoke test.
3. Commit the JSON (they are small, deterministic artifacts; `resources/**` is versioned).

### Phase 1 — runtime resolver
4. **New** `scripts/ui/track_layout_source.gd`:
   - `const PREVIEW_DIR := "res://resources/ui/track_layouts"`.
   - `static func preview_path(track_id: String) -> String`, `static func has_layout(track_id) -> bool`,
     `static func points(track_id: String) -> Array[Vector3]` (cache in a `static var _cache`),
     `static func has_rival_centerline(track_id: String) -> bool`.
   - JSON read via `FileAccess.get_file_as_string` + `JSON.parse_string`; validate
     `points[i]` is an `Array` of 3 numbers before building `Vector3` (never trust the file shape).
   - Live fallback probe (off-tree only) exactly as §3.2; guard the whole function so a bad
     scene can never throw into the menu (`is_instance_valid` + `free()`).

### Phase 2 — preview Control + scene
5. **New** `scripts/ui/track_layout_preview.gd` (`class_name TrackLayoutPreview extends Control`)
   with the API of §3.4 (`set_layout`, `has_layout`, `layout_id`, `projected_points`,
   `get_fit()`), constants `INSET_PX`, `LINE_WIDTH`, `LINE_COLOR`, `BG_COLOR`, `EMPTY_TEXT`.
6. **Edit** `scenes/ui/track_select.tscn`: insert into `Margin/Row/RightColumn` (after
   `%BestLapLabel`, before `%CardScroll`) a `PreviewPanel` (`Panel`, `custom_minimum_size =
   Vector2(0, 240)`, `panel_box` style) containing `%LayoutPreview` (full-rect `Control`,
   script = the new file) and `%PreviewCaption` (small muted label, e.g.
   `LAYOUT PREVIEW`); then `%FieldSummaryLabel` + `%RivalsBox` (`VBoxContainer`).
   Add the two new `ext_resource` script entries and update **`load_steps` to resources + 1**
   (14 → 15; `AGENTS.md`/base plan rule: only new resources bump it). Keep every existing
   `%` name untouched.

### Phase 3 — menu wiring
7. **Edit** `scripts/ui/track_select.gd`:
   - `@onready` the new nodes; `_ready()` binds their initial state (no new blips).
   - `_update_pin_panel(pin)` (`:214-228`) additionally calls
     `_refresh_preview(track_id)` and `_refresh_field(track_id)`, and sets
     `play_button.text = "START RACE"`.
   - `_refresh_preview(track_id: String) -> void` → `layout_preview.set_layout(track_id)` +
     `preview_caption.text` (`LAYOUT PREVIEW` / `LAYOUT MAP UNAVAILABLE`).
   - `_refresh_field(track_id: String) -> void` → clear `%RivalsBox` children, then:
     `var count := GameState.clamp_opponents(GameState.opponents)`,
     `var anchor := GameState.normalize_difficulty(GameState.ai_difficulty)`;
     summary text; if `count <= 0` → `SOLO`, if
     `not TrackLayoutSource.has_rival_centerline(track_id)` → the honesty line; else one row
     per slot from `RaceManager._tier_for_slot(anchor, i)` + `CarVisuals.rival_visual_for(i)`
     → `_rival_row_text(slot, car_id, tier) -> String` (resolves the `.tres` display name).
   - Keep `_on_play_pressed()` **byte-identical** (§3.1) — no race-semantics change.
8. Mouse/touch: a left-click on the preview does nothing (it is informational); the card
   list and pins remain the selection inputs — no new input path.

### Phase 4 — tests (§5), Phase 5 — docs
9. Add `tests/suites/test_race_layout_preview.gd` (§5).
10. Docs: note this work in `docs/plans/race_menu_map_expansion_plan.md` §7 or a status line,
    and refresh the stale `docs/research/ultradrive_features.md:115` track-select description
    in the same PR. `docs/ROADMAP.md` has the race-mode/event lines (`:144-146`,
    `:159` rivals shipped) — add one line under the GT7-authenticity cluster when the work lands.

### Verification gates (each ONCE, never re-run "to confirm")
- `--headless --import .` filtered for `SCRIPT ERROR` / `Parse Error` (expect zero; time it).
- The bake tool run, then targeted suites (`-a` per suite, never comma-joined):
  `test_race_layout_preview`, `test_race_menu_map`, `test_track_system`,
  `test_audio_feel_layers`, `test_race_loop`, `test_menu_video_background`, `test_race_rivals`.
- Then the full `py tools\gdunit_parallel.py -j 4` as ONE background sub-agent; read
  `reports/parallel/summary.json` + `merged-results.xml`.
- `graphify update .` after the code change (GDScript is not in the graph; the plan doc is).

---

## 5. Test plan (GDUnit4)

New suite `tests/suites/test_race_layout_preview.gd` (pure tests need no scene; menu tests
mirror `tests/test_track_system.gd:22-42`: `scene_runner(...)` + `await
runner.simulate_frames(2)`). gdUnit treats warnings as errors → full type annotations, never
`var x := <Variant-returning call>`; `assert_that(...).is_equal` style.

Pure / data:
1. `test_every_registry_layout_has_baked_preview_data` — for each id in
   `TrackRegistry.get_track_ids()`, `TrackLayoutSource.has_layout(id)` is true and
   `points(id).size() >= 8`. **Deliberate canary:** a concurrent task adding a track fails
   this with a clear message ("re-run tools/gen_track_layouts.gd") — the fallback keeps the
   UI alive meanwhile.
2. `test_preview_points_are_finite_and_flat` — every point `is_finite()`, and the layout is a
   closed ring (first/last within the track's own spacing; assert the XZ span is > 40 m so a
   degenerate 2-point "line" can never pass).
3. `test_unknown_track_returns_empty_and_no_line` — `TrackLayoutSource.points("no_such_track")`
   is empty, `has_layout` false (the graceful-degrade contract).
4. `test_rival_centerline_flag_matches_the_shipped_tracks` — `has_rival_centerline`
   is true for `northern_isle` and false for the others **expressed generically**: assert the
   flag is a bool for every registry id, and that at least one layout is false (so the honesty
   branch is exercised). (Do not hardcode which — the concurrent task may add a track that
   publishes one.)

Preview control (scene, size set explicitly — headless `_draw()` never runs):
5. `test_preview_projects_the_selected_layout_inside_its_rect` — set `size` explicitly,
   `set_layout("mountain_pass")`, assert `has_layout()`, every `projected_points()` vertex is
   inside `Rect2(Vector2.ZERO, size)`, and count == `TrackLayoutSource.points(...).size()`.
6. `test_preview_switches_layout_without_a_scene_change` — `set_layout("oval")` then
   `set_layout("mountain_pass")` → `layout_id()`/point count change and both fit inside.
7. `test_preview_without_data_reports_no_layout` — `set_layout("no_such_track")` →
   `has_layout()` false and `projected_points()` empty (no crash).

Menu (scene):
8. `test_default_event_panel_shows_laps_and_field_summary` — default selection:
   `%LapsLabel` text contains `"%d LAPS" % laps_default`, `%FieldSummaryLabel` contains the
   clamped opponent count and the difficulty anchor, `%PlayButton` text is `START RACE`.
9. `test_selecting_an_event_updates_preview_and_field` — `select_pin("home_northern_isle")` →
   `%LayoutPreview.layout_id() == "northern_isle"`, the rival box has
   `GameState.clamp_opponents(GameState.opponents)` rows; `select_pin("home_sunset_oval")` →
   preview is `oval` and the field block shows the no-rivals line.
10. `test_rival_rows_name_real_cars_with_tiers` — with `GameState.opponents = 3` and
    `GameState.ai_difficulty = "Expert"` (restore after), the fist row names a car from
    `CarVisuals.RIVAL_VISUALS` and its tier is `Expert` (slot 0 == anchor, per
    `race_manager.gd:297`). Restore `GameState.opponents`/`ai_difficulty` at the end.
11. `test_play_still_queues_the_selected_laps` — mirror of
    `test_race_menu_map.gd:170-181` (end with `RaceManager.consume_pending_race()`); the
    regression lock that the new panel changed nothing about the start contract.

Regression checks (verify, do not edit): `tests/test_track_system.gd` (all 3 menu tests),
`tests/suites/test_race_menu_map.gd`, `test_audio_feel_layers.gd:194-224` (the blip still
fires once — the new panel adds **no** buttons and binds **no** new blips), and
`test_menu_video_background.gd`.

---

## 6. Risks / gotchas

1. **Baked data staleness.** If a concurrent task changes an existing track's geometry (or
   adds one), the JSON is stale/missing. Mitigation: the canary test (1) fails loudly with a
   re-run instruction, the runtime fallback (3.2) keeps the UI working, and the JSON records
   `scene_path` + `generated` so a reviewer can see the age.
2. **`load_steps` arithmetic** in `track_select.tscn`: adding two `ext_resource` script
   entries means `load_steps` 14 → 15 (resources + 1). Wrong number = the scene silently
   fails to load at import, which the `--import` gate catches.
3. **Headless draw.** `_draw()` never runs under gdUnit: the preview fit and
   `projected_points()` must be computed in `set_layout()`/`_notification` (mirror
   `track_map.gd:23-26,88-94`), and tests must set `size` explicitly.
4. **`%`-name and node coupling.** `%TrackGrid`, `%PlayButton`, `%BackButton`,
   `%TrackNameLabel`, `%MapPanel`/TrackMap and `UiBlip` are load-bearing for the tests in
   §2.5 and for `tools/menu_autopilot.gd`'s reporter. Add nodes, never rename/remove.
5. **Blip-count test.** `test_audio_feel_layers.gd:194-224` asserts the play blip fires once
   and that `%TrackGrid` child 0 is a blip-wired `Button`. The new nodes are passive Labels /
   a non-focusable `Control` → no blips, no buttons; re-run the suite anyway after touching
   `_ready()`/`_build_cards()`.
6. **Do not run track scenes from the menu at runtime.** The live fallback probe is
   **off-tree only**; instancing into the tree would consume the pending race
   (`race_ui.gd:106-107`), pollute `VehicleManager`, and bake Mountain Pass terrain
   (`mountain_pass.gd:48-52`). Any future "just load the scene to read its road" shortcut is
   the bug this section exists to stop.
7. **`_`-prefixed read-only calls.** `RaceManager._tier_for_slot` is used deliberately (see
   §3.3) — it must stay a pure read (no roster writes, no `configure_default_rivals()` call
   from the menu: building a roster in the menu would be clobbered/ghost-spawn on the next
   scene change and is race-semantics territory).
8. **Honesty of the rival list.** Rival *physics* uses the player's config
   (`race_manager.gd:276-280`); only grid *visuals* vary (`car_visuals.gd:106-110`). The
   panel labels the block `GRID VISUALS`; do not "improve" it by claiming distinct rival
   machines.
9. **Right-column height.** 1080p with the panel margins leaves ≈1 020 px; the added preview
   (≈240) + rows (≈140) leaves ≈4 visible cards in `%CardScroll`. Keep `follow_focus = true`
   (`track_select.tscn:240`) so controller navigation to card 20 still scrolls into view.
10. **Concurrent work.** `scripts/track/**`, `scenes/track/**`, `scripts/track/track_registry.gd`,
    car assets/materials, camera scripts, `scenes/ui/garage.tscn` + `scripts/ui/garage_ui.gd`
    and vehicle audio are owned by other tasks — read only. The registry must be consumed
    dynamically (iterate `get_track_ids()`/`get_pin_ids()`), never as literals.
11. **Shell/gate hygiene.** The bake tool and every suite run must use
    `%GODOT_EXE_CONSOLE%` (the GUI PE detaches and false-greens), one Godot process at a time,
    artifacts on `D:` only (`AGENTS.md`).

---

## 7. Do NOT touch (owned by concurrent tasks / out of scope)

- **Registry and track geometry:** `scripts/track/track_registry.gd` (READ the pin/track
  tables, never edit), `scripts/track/**` (all layout scripts incl.
  `northern_isle.gd`, `northern_isle_layout.gd`, `mountain_pass.gd`, `track_builder.gd`),
  `scenes/track/**`, `scenes/test/test_track.tscn`, `scripts/test_circuit.gd`. A concurrent
  task adds a new track entry — this plan's UI consumes the registry dynamically.
- **Car assets / materials + camera scripts:** `assets/cars/**`, `resources/cars/**`,
  `resources/materials/**`, `scripts/vehicle/car_visuals.gd` (READ `RIVAL_VISUALS` and
  `RIVAL_PALETTE` only), `scripts/camera/**`, `scripts/vehicle/rival_car_visual.gd`.
- **Garage:** `scenes/ui/garage.tscn`, `scripts/ui/garage_ui.gd` (and its 3D preview); the
  `Garage` API is read-only for the panel's player-car name.
- **Vehicle audio:** `scripts/audio/**`, engine/turbo voice code, `resources/audio/**`.
- **Race semantics:** `autoload/race_manager.gd` (read-only: the panel mirrors
  `_tier_for_slot` / `clamp_opponents`), `scripts/race/race_ui.gd`, `scripts/race/checkpoint.gd`,
  `scripts/race/lap_counter.gd`, `scripts/race/best_lap_records.gd`, `autoload/save_manager.gd`,
  `autoload/game_state.gd`, `autoload/vehicle_manager.gd` (no new keys/schema/signatures).
- **Shared map tech (mirror, don't modify):** `scripts/ui/map_roads.gd`,
  `scripts/ui/world_map.gd`, `scripts/ui/minimap.gd`, `scripts/ui/track_map.gd`,
  `scripts/ui/world_map_projection.gd`, `scripts/ui/levant_outline.gd`,
  `scripts/ui/pause_menu.gd`, `scripts/ui/scene_transition.gd`, `scenes/ui/main_menu.tscn`.
- **Tooling/infra:** `tools/gdunit_parallel.py`, `tools/menu_autopilot.gd`, `addons/**`,
  `graphify-out/**` (only the hook rebuilds it). New files this plan owns:
  `tools/gen_track_layouts.gd`, `resources/ui/track_layouts/**`,
  `scripts/ui/track_layout_source.gd`, `scripts/ui/track_layout_preview.gd`,
  `scripts/ui/track_select.gd` (+ its `.tscn`), `tests/suites/test_race_layout_preview.gd`.

### Optional follow-ups (explicitly not MVP)
- GT7-style full-screen entry sub-screen (Option B of §3.1) instead of the in-place panel.
- Draw the start line + sector marks on the preview; add a mini map of the AI grid on the
  preview when rivals are available.
- Server/records-backed "event" object (name, entry requirements, payouts) — depends on the
  ROADMAP event-framework stream (`docs/ROADMAP.md:144-146`), out of scope here.

---

## 9. STATUS — implemented (2026-10-16)

All five phases are implemented in the working tree. The bake tool is **written but NOT
run** (see §9.3) — the runtime degrades gracefully without it, so the tests that do not
depend on baked data pass before the bake, and test 1 is a deliberate canary that fails
loudly until the bake runs.

### 9.1 Files created

| File | Role |
|---|---|
| `tools/gen_track_layouts.gd` | One-shot offline bake (WRITTEN, not run). Iterates `TrackRegistry.get_track_ids()`, extracts each driven centerline via the documented capability chain (`road_points` → descendant `TrackBuilder._track_points` → `has_layout:false`), reads `RaceManager.rival_centerline` per scene, writes `resources/ui/track_layouts/<id>.json`. |
| `scripts/ui/track_layout_source.gd` | `class_name TrackLayoutSource extends RefCounted` — the ONLY runtime reader. Static, in-memory cache; reads the baked JSON; falls back to an **off-tree** `instantiate()` + pure `_generate_road_points()` convention probe; otherwise returns empty data (graceful degrade). Never enters a track scene into the tree. |
| `scripts/ui/track_layout_preview.gd` | `class_name TrackLayoutPreview extends Control` — draws the projected centerline (reuses `MapRoads.compute_fit` / `world_to_screen`); `set_layout`, `has_layout`, `layout_id`, `projected_points`, `get_fit`. Fit is computed in `set_layout()` / `NOTIFICATION_RESIZED` (never lazily in `_draw()`), so it works headless. |
| `tests/suites/test_race_layout_preview.gd` | 11 GDUnit tests (see §9.4). |

### 9.2 Files edited

- `scenes/ui/track_select.tscn` — `load_steps` 14 → **15**; ONE new `ext_resource`
  (`4_layout_preview` → `track_layout_preview.gd`); new `PreviewPanel` (`Panel`) with
  `LayoutPreview` + `PreviewCaption`, plus `FieldSummaryLabel` and `RivalsBox`, inserted
  after `BestLapLabel` and **before** `CardScroll`. `%TrackGrid` order/content untouched
  (child 0 is still the first blip-wired card `Button`).
- `scripts/ui/track_select.gd` — new `@onready` members; `_refresh_preview()`,
  `_refresh_field()`, `_make_field_row()`, `_rival_row_text()`, `_clear_detail_panel()`.
  `_update_pin_panel()` now also refreshes the preview + field and sets
  `play_button.text = "START RACE"`. The empty-region branches of `_ready()` /
  `set_region()` call `_clear_detail_panel()`.
  **`_on_play_pressed()` is byte-identical** (still
  `queue_race(laps_default)` → `launch_callback(scene_path)`), and
  `select_pin → select_track → _on_play_pressed` semantics are unchanged.

### 9.3 Bake command (run ONCE, main session — not a test, not the gate)

```bat
cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE! --headless -s res://tools/gen_track_layouts.gd"
```

Expected: one JSON per registry layout under `resources/ui/track_layouts/` — today
`oval.json` (32 pts), `mountain_pass.json`, `northern_isle.json`; only `northern_isle.json`
carries `"rival_centerline": true` (it is the sole caller of
`RaceManager.set_rival_centerline`). After the bake, run the normal `--headless --import .`
probe and the targeted suites: `test_race_layout_preview`, `test_race_menu_map`,
`test_track_system`, `test_audio_feel_layers`, `test_race_loop`, `test_menu_video_background`,
`test_race_rivals`.

### 9.4 Tests added (`tests/suites/test_race_layout_preview.gd`)

1. `test_every_registry_layout_has_baked_preview_data` — **canary**; fails until the bake,
   with an override message naming `tools/gen_track_layouts.gd`.
2. `test_preview_points_are_finite_and_flat` — finite points, span > 40 m, closed ring.
3. `test_unknown_track_returns_empty_and_no_line` — graceful degrade (no data).
4. `test_rival_centerline_flag_matches_the_shipped_tracks` — flag is always a `bool` and the
   "no rivals" honesty branch is exercised.
5. `test_preview_projects_the_selected_layout_inside_its_rect` — projection stays in-rect.
6. `test_preview_switches_layout_without_a_scene_change` — no scene reload on selection change.
7. `test_preview_without_data_reports_no_layout` — empty/false, no crash.
8. `test_default_event_panel_shows_laps_and_field_summary` — laps + difficulty/opponents
   summary + `START RACE`.
9. `test_selecting_an_event_updates_preview_and_field` — `%RivalsBox` is `count` rows for a
   rival layout, 1 "NONE ON THIS LAYOUT" row otherwise.
10. `test_rival_rows_name_real_cars_with_tiers` — row 0 names the slot-0 rival visual and the
    difficulty anchor tier.
11. `test_play_still_queues_the_selected_laps` — `_on_play_pressed` still queues the selected
    layout's `laps_default` and launches its scene path.

Suite hygiene: `before_test`/`after_test` snapshot+restore `GameState.opponents` /
`ai_difficulty` and drain `RaceManager.consume_pending_race()`; all locals typed (gdUnit
treats warnings as errors).

### 9.5 Open risks / notes

1. **Bake is required for the full green.** Tests 1, 2, 9, 10 read baked data and fail until
   the main session runs §9.3. Tests 3, 7, 11 (and 4, and the mountain_pass fallback in 5/6)
   pass without it, proving the degrade path.
2. **Bake tool is not gate-safe by design** — instancing every track scene runs terrain bakes
   and HUD/`pause_menu` `_ready()`; it stays a one-shot editor step, never a suite.
3. **`load_steps` arithmetic.** The plan text anticipated "two `ext_resource` entries"; only
   ONE is required (`track_layout_source.gd` is code-only, it is never a scene node). Final
   count: 4 ext + 10 sub = 14 resources → `load_steps = 15`. A wrong value silently breaks
   the scene at import; the `--import` gate catches it.
4. **Baked-data staleness from concurrent work.** `scripts/track/**` is owned by another task.
   If a track's geometry changes, its JSON is stale — re-run §9.3. The canary (test 1) plus
   the runtime fallback keep the menu working meanwhile.
5. **Rival honesty.** Only the grid *visuals* vary (`CarVisuals.RIVAL_VISUALS`); rival physics
   uses the player's config. The block is labelled `GRID VISUALS` and must not be "improved"
   into a claim of distinct machines.
6. **Right-column height.** 1080p leaves ≈1 020 px; preview (≈240) + rows reduce visible
   cards in `%CardScroll`. `follow_focus` stays `true` so controller navigation still scrolls
   the focused card into view.
7. **All changes uncommitted** in a working tree that also carries unrelated prior-session
   work. No `git add` / `git commit` was performed (per instructions).
