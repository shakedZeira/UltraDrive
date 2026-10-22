# UltraDrive — Race Menu as a Global Circuit Map

> Turn the track-select screen (`scenes/ui/track_select.tscn`) into a **world map of
> circuits**: every circuit is a pin at a real-world lat/long (a famous real track,
> or an invented Israeli circuit), the driven layout is one of the game's three
> existing fictional tracks, and **Israel is the default framed region**.
> Pin click → circuit card (name / layout / class / laps / best lap) → PLAY, wired
> into the **existing** `RaceManager.queue_race()` → HUD flow with **no changes to
> race semantics**.
>
> **Written:** 2026-10-16 · **Inputs:** user request ("show the circuits as clickable
> locations on a global map, based on the real tracks locations (created non-real
> tracks: default 'israel')"), `scripts/ui/track_select.gd`,
> `scripts/track/track_registry.gd`, `scripts/ui/map_roads.gd`,
> `scripts/ui/world_map.gd`, `AGENTS.md` (shell/gate/registry rules) ·
> **Format:** 1 new CC0 asset + 3 new scripts + 1 optional data script + menu rework
> + 1 updated legacy suite + 1 new gate suite.

---

## 1. Current state (verified, with refs)

### Race menu
- `scripts/ui/track_select.gd` — `class_name TrackSelect extends Control`.
  - `_build_cards()` (L49-87) iterates `TrackRegistry.get_track_ids()` (L53) and makes
    one toggle `Button` per registry entry: badge `CLASS <difficulty>`, `display_name`,
    `circuit_type`. Cards are `focus_mode = FOCUS_NONE` (L58) → **mouse-only today**.
  - Selection: `select_track(track_id)` (L106-114) sets `_selected_id`, updates
    `%TrackNameLabel`, highlight (L116-122). `_on_card_pressed` (L124) delegates.
  - Launch: `_on_play_pressed()` (L128-134) → `RaceManager.queue_race(laps_default)`
    (L133) → `launch_callback.call(scene_path)` (L134). Default callback
    `_default_launch` = `SceneTransition.flash_to_scene` (L139-140).
    `_on_back_pressed()` → `res://scenes/ui/main_menu.tscn` (L137).
    `launch_callback` is a public seam tests stub (L35).
  - Audio: `UiBlip` + `_menu_blip()`/`_bind_menu_blip()` (L13-30) on play/back/cards.
- `scenes/ui/track_select.tscn` — full-rect `Control` → `Background` ColorRect +
  `Gradient` TextureRect + `Center/Panel(720x480)` → `Layout` VBox:
  `TitleLabel` (L169), `%TrackNameLabel` (L175), `%TrackGrid` GridContainer (L181),
  `ButtonsRow` → `%PlayButton` (L194) / `%BackButton` (L208), and a `Footer` label
  (L221). Palette: ACCENT `Color(0.902,0.698,0.235)`, panel bg `0.07,0.09,0.145`.
- Entry: `scripts/ui/main_menu.gd:31` → `SceneTransition.flash_to_scene("res://scenes/ui/track_select.tscn")`.
- Scene change: `scripts/ui/scene_transition.gd:34-35` → `GameState.change_scene()`
  (`autoload/game_state.gd:133-142`, sets mode + re-applies the quality ladder).

### Track registry (source of truth)
- `scripts/track/track_registry.gd` — `static var tracks: Dictionary` with exactly
  **3** entries (L7-29): `oval` (Sunset Oval, `res://scenes/test/test_track.tscn`,
  3 laps, D, CIRCUIT), `mountain_pass` (Mountain Pass,
  `res://scenes/track/mountain_pass.tscn`, 2 laps, B, CIRCUIT), `northern_isle`
  (Northern Isle Speedway, `res://scenes/track/northern_isle.tscn`, 5 laps, D, OVAL).
  Accessors: `get_track_ids()` L31, `get_track()` L34, `get_scene_path()` L37,
  `has_track()` L40. **No location metadata exists anywhere.**

### Race flow (unchanged by this plan)
- `RaceManager` autoload: `queue_race(laps)` / `consume_pending_race()`;
  `scripts/race/race_ui.gd` (HUD) latches the pending race on its first frame and
  calls `start_race(VehicleManager.get_all_cars(), laps)`.
- Best laps: `scripts/race/best_lap_records.gd` — keys are `"<track>|<class>"`
  (`key_for()` L33), per-slot JSON section `best_laps` (L18), read helper
  `load_record(track_id, car_class)` L114. The HUD's track id is reverse-looked-up
  from the instanced scene path: `race_ui._resolve_track_id()` (L440-450) **returns
  the FIRST registry id whose `scene_path` matches**, so records are keyed per
  **layout**, not per circuit location.

### Reusable map tech (mirror, don't modify)
- `scripts/ui/map_roads.gd` — static math, headless-safe:
  `compute_fit(content_points, fallback, draw_size, inset) -> {origin, scale,
  world_min, world_max}` (L441-469), `world_to_screen(world_pos, fit)` (L472-476),
  `screen_to_world(screen_pos, fit)` (L542-548), `clip_circle` (L482),
  marker/pin draw idioms: `draw_player_marker` (L105) with pulsing halo, `MARKER_*`
  consts (L54-60), POI pin style `world_map.gd` L412. All operate on `Vector3(x,·,z)`.
- `scripts/ui/world_map.gd` (open-world pause map) — the UI patterns to copy:
  dirty-flag rebuild (`_dirty` L138, `refresh()` L260, `_notification` L299),
  `_draw()` layering (L303-321), click → `screen_to_world` → action
  (`_unhandled_input` L899-911), `show_*` filter flags (L162-173),
  `region_filter` (L173) — an exact precedent for a REGION toggle.
- Tests that pin this behaviour: `tests/suites/test_world_map_features.gd`
  (fit/world_to_screen assertions), `tests/suites/test_map_route.gd`
  (`screen_to_world` inverse), `tests/suites/test_world_map_terrain.gd`.

### Tests that touch this menu (must stay green or be updated deliberately)
- `tests/test_track_system.gd` (root-level suite — `tools/gdunit_parallel.py:308`
  discovers `tests/**/*.gd` recursively, so it IS sharded and run):
  - L3-14 `test_registry_contains_expected_tracks` — `assert_array(ids)
    .contains_exactly(["oval","mountain_pass","northern_isle"])`.
    **`contains_exactly` is ORDER- AND SIZE-sensitive** (verified in
    `addons/gdUnit4/src/asserts/GdUnitArrayAssertImpl.gd:130-152`: "same content in
    same order"; `contains_exactly_in_any_order` is the lenient sibling).
  - L16-20 `test_registry_scene_files_exist` — loops ids, `assert_file(...)`.
  - L22-38 `test_track_select_builds_one_card_per_track` — card count == registry
    size, card text contains registry `display_name` / `CLASS x` / `circuit_type`,
    and `get_selected_scene_path() == scene_path(get_track_ids()[0])`.
  - L40-57 `test_track_select_play_loads_selected_scene` — `select_track("mountain_pass")`
    → `_on_play_pressed()` → launched path; then `oval`; then back → main_menu;
    ends `RaceManager.consume_pending_race()`.
  - L59-70 `test_track_select_highlight_updates_on_select` — indexes `%TrackGrid`
    children with `get_track_ids().find("mountain_pass")`.
- `tests/suites/test_race_loop.gd:391-400` — `select_track("mountain_pass")` +
  `_on_play_pressed()` + `consume_pending_race() == 2`.
- `tests/suites/test_audio_feel_layers.gd:194-224` — `%PlayButton` pressed blips once;
  `%TrackGrid` child 0 is a `Button` with the blip wired.
- Untouched-but-related: `tests/suites/test_best_lap_records.gd:51-59` (distinct keys
  per registry id).

---

## 2. Design decisions

### 2.1 Where do pins live? → **additive `TrackRegistry.pins`; `tracks` untouched**

`TrackRegistry` gains a **second static dict** (`pins`) + accessors
(`get_pin_ids/get_pin/has_pin/track_for_pin/pins_for_track/region_bounds/REGION_*`).
`tracks`, `get_track_ids()`, `get_track()`, `get_scene_path()`, `has_track()` are
**not modified at all**.

Why not one registry entry per circuit: `race_ui._resolve_track_id()`
(`race_ui.gd:440-450`) returns the **first** id whose scene path matches, so padded
duplicate entries would make best-lap attribution order-dependent (a silent trap),
while `tracks` would also grow (breaking `contains_exactly` L5 and changing the
pause-map/GPS registry consumers). Keeping `tracks` = "the layouts we ship" and
`pins` = "where they are sold as circuits" keeps 3 layouts / N circuits clean, and
makes records key per **layout** (documented, not accidental).

Per the user's framing, `TrackRegistry` remains the **single source of truth** — pins
just live in the same file, additively.

### 2.2 Data model

```
# additive in scripts/track/track_registry.gd
const REGION_ISRAEL := "israel"
const REGION_WORLD  := "world"
const DEFAULT_REGION := REGION_ISRAEL

static var pins: Dictionary = {
  "<pin_id>": {
     "label": String,     # circuit name shown on the pin + card
     "lat": float, "lon": float,
     "region": String,    # REGION_ISRAEL | REGION_WORLD
     "track_id": String,  # MUST exist in `tracks`  (pin -> layout, explicit)
     "host": String,      # "" or the real circuit's country/name flavour text
  }, ...
}
# region framing boxes in lon/lat (min corner + size), presentation data
static var regions: Dictionary = {
  REGION_WORLD:  {"min_lon": -180.0, "min_lat": -90.0, "max_lon": 180.0, "max_lat": 90.0},
  REGION_ISRAEL: {"min_lon":  33.0, "min_lat": 28.8, "max_lon":  36.5, "max_lat": 34.2},
}
```
`REGION_ISRAEL`'s box is the pin-coverage box grown ~1.5°, tunable.

### 2.3 Pin table — 9 pins / 3 layouts (explicit many-to-one, documented)

**Israel (default region; invented circuits, no real host):**

| pin_id | label | lat | lon | layout (`track_id`) | laps |
|---|---|---|---|---|---|
| `haifa_coastal_ring` | Haifa Coastal Ring | 32.7940 | 34.9896 | `mountain_pass` | 2 |
| `galilee_circuit` | Sea of Galilee Circuit | 32.7167 | 35.6167 | `northern_isle` | 5 |
| `negev_speedway` | Negev Speedway | 31.2589 | 34.7997 | `oval` | 3 |

**World (famous real circuit locations; labels are the real circuits, the driven
layout is our fictional one):**

| pin_id | label (real host) | lat | lon | layout (`track_id`) |
|---|---|---|---|---|
| `silverstone` | Silverstone Circuit, UK | 52.0786 | -1.0169 | `mountain_pass` |
| `spa` | Circuit de Spa-Francorchamps, BE | 50.4372 | 5.9714 | `mountain_pass` |
| `nurburgring` | Nürburgring Nordschleife, DE | 50.3356 | 6.9475 | `mountain_pass` |
| `monza` | Autodromo Nazionale Monza, IT | 45.6156 | 9.2811 | `northern_isle` |
| `suzuka` | Suzuka Circuit, JP | 34.8431 | 136.5407 | `northern_isle` |
| `interlagos` | Autódromo José Carlos Pace, BR | -23.7036 | -46.6997 | `oval` |

- Every layout is reachable (3 pins each); every pin resolves to a real scene.
- Pin order = dictionary insertion order (Godot Dictionaries keep insertion order) =
  UI/card order; `haifa_coastal_ring` is first → **default selection is Israeli**.
- The card shows BOTH: pin `label` as the circuit, plus the layout name from
  `tracks[track_id].display_name` tagged "FICTIONAL LAYOUT" — honest about "created
  non-real tracks".
- Adding a *real* Israeli layout later = add a `tracks` entry + repoint that pin.
  (Authoring new layouts is out of scope; see §7 open questions.)

### 2.4 Map asset → **download CC0/PD equirectangular SVG (verified); procedural
backdrop for the Israel zoom**

**Chosen asset: `BlankMap-Equirectangular.svg` (Wikimedia Commons).**
- License: **Creative Commons CC0 1.0 Universal Public Domain Dedication** (verified
  on the file page: "This file is made available under the Creative Commons CC0 1.0
  Universal Public Domain Dedication"), source data Natural Earth, author
  Tom Patterson / Nathaniel Vaughn Kelso / Bjørn Sandvik, 2012-02-09, 1,469,626 bytes.
- Page: `https://commons.wikimedia.org/wiki/File:BlankMap-Equirectangular.svg`
- Direct download (redirect follows to `upload.wikimedia.org`):
  `https://commons.wikimedia.org/wiki/Special:FilePath/BlankMap-Equirectangular.svg`
- **Verified header** (fetched during planning):
  `width="360" height="180" viewBox="0 0 360 180"` → **exact equirectangular world
  bounds, 1 map unit = 1 degree**, 2:1. No projection fudge, no bound guessing.
- Install as `assets/ui/world_map_equirectangular.svg`; write
  `assets/ui/License.txt` (same convention as `assets/track_props/License.txt`):
  source URL, author, "CC0 1.0 Universal Public Domain Dedication", retrieval date.
  CC0 needs no attribution; the file is for the record.

Rejected: `Equirectangular projection world map without borders.svg` (CC-BY-SA 4.0 —
license debt), `Blank world map Equal Earth projection.svg` and
`BlankMap-World-150E Equal Earth.svg` (CC0 but **Equal Earth**, not equirectangular →
linear lat/lon→UV math wrong), `NED worldmap 110m.svg` (equirectangular + PD-self but
its viewBox could not be verified, and it is border-heavy).

**Backdrop rendering, two tiers (this is the important decision):**

- **WORLD region** → the SVG as a texture backdrop. Godot 4's SVG importer rasterizes
  it (`scale` import param); use **`scale=4` → 1440×720** (≈4 MB RGBA, latest enough
  for a world view; do NOT chase a big scale — a world raster can never survive the
  Israel zoom, see below). Style it editorially with a small `CanvasItem` shader that
  keys the SVG's flat fills → dark navy ocean / desaturated slate landmass, or (lower
  effort, acceptable MVP) `modulate` + a `ColorRect` overlay with
  `BLEND_MODE_MUL` for a duotone wash + vignette. **Read the SVG's actual `fill`
  values during implementation and key off them; do not guess.**
- **ISRAEL region** → **procedurally drawn stylized landmass** from authored lon/lat
  rings (`scripts/ui/levant_outline.gd`), filled with
  `draw_colored_polygon`/`draw_polyline`. Reason: Israel is ~1.7° of longitude; on a
  1440-wide world raster that is **7 pixels** — a raster zoom is physically incapable
  of showing Israel. Vector-drawn local shapes are crisp at any panel size, zero
  license risk, and the editorial look is exactly what a racing game wants.
  Rings to author (stylized, ~60 points total, tune in-editor):
  - Levant coastline + eastern border ring (anchors: Rosh Hanikra 33.09/35.10 →
    Acre 32.93/35.07 → Haifa 32.82/34.99 → Atlit 32.70/34.94 → Netanya 32.32/34.85 →
    Tel Aviv 32.07/34.76 → Ashdod 31.80/34.64 → Gaza 31.50/34.45 → Rafah 31.30/34.25 →
    El Arish 31.13/33.80 → Port Said 31.26/32.30 → Suez 29.97/32.55 → Aqaba/Eilat
    29.55/34.95 → Wadi Araba 30.40/35.00 → Dead Sea S 31.05/35.40 → E. border 31.77/35.55
    → Jordan R. 32.22/35.55 → Golan 33.00/35.75 → back to Rosh Hanikra).
  - Sea of Galilee ring (~5 pts, 32.68-32.88 N / 35.57-35.65 E).
  - Dead Sea ring (~7 pts, 31.05-31.77 N / 35.40-35.58 E).
  - Graticule (1° lines in the Israel view, 30° in the world view) drawn from the
    same projection, so the two tiers can never disagree about position.
- The backdrop is chosen only by `region`; **all pins, labels, hit-testing and the
  card panel are backdrop-agnostic** (one projection, one pin layer). Swapping the
  world tier for runtime-vector land later (Natural Earth GeoJSON, PD) is then an
  internal change to one script — noted as Phase 5, not MVP.

### 2.5 Coordinate system (testable, one formula)

Equirectangular, exact, no offsets needed because the asset is 360×180 units:

```
u = (lon + 180) / 360          v = (90 - lat) / 180        # uv, y down
```
For screen math we reuse `MapRoads.compute_fit()` / `world_to_screen()` /
`screen_to_world()` by mapping lon/lat onto the `(x, z)` plane with **negated
latitude** so north is up:

```
map_point(lat, lon) -> Vector3(lon, 0.0, -lat)     # x = lon, z = -lat
lonlat_of(p)        -> Vector2(p.x, -p.z)          # (lon, lat)
```
`compute_fit()` then gives `world_min.z = -max_lat` → `world_to_screen` yields a
smaller y for a larger lat = north at the top ✅ (this inversion is the single most
likely bug; it gets its own test). Callers never touch `-lat` directly — they use
`WorldMapProjection`.

Region framing = `compute_fit(region_corners(region), fallback_pin, draw_size, inset)`
— a plain contain-fit, so no zoom/pan state machine in the MVP. Pin/click positions
go through `world_to_screen`; map clicks come back through `screen_to_world` →
`lonlat_of` (free for a future pan/zoom).

### 2.6 Interaction model

- **Pins are drawn** in `TrackMap._draw()` (glowing editorial style, mirroring
  `MapRoads.draw_player_marker`'s halo idiom + `world_map.gd` POI pin): pulse halo,
  dark outline ring, fill; selected pin larger + `label` text; hovered pin
  brightened. Constant **16 px** screen-space hit radius (zoom-independent).
- **Mouse/touch**: click → nearest visible pin within the radius → `pin_clicked(pin_id)`
  → card panel updates (same path as the list).
- **Controller/keyboard**: the `%TrackGrid` card list is the deterministic focus path —
  **flip cards to `focus_mode = FOCUS_ALL`** (today `FOCUS_NONE`, `track_select.gd:58`)
  and `grab_focus()` the selected card on ready. Pins also get focus neighbours via
  the list (Select/`ui_accept` on a focused card = select; PLAY starts). This satisfies
  "pins focusable OR list fallback selectable" with the smaller diff and no hand-built
  focus graph. The map Control stays `mouse_filter = STOP` for clicks; the card list
  is always visible (right column), so a circuit is never mouse-only.
- Pins and cards are **one selection state**: pin click → `select_pin()`, card press →
  `select_pin()`, both re-highlight the other. Region switch keeps the selection
  selected-and-visible (if the selected pin is outside the new region's framing, fall
  back to the first pin of that region — never "selected but invisible").

### 2.7 Circuit card

Existing `%TrackNameLabel` becomes the circuit name; new **additive** nodes:
`%MetaLabel` (`CLASS B  •  ROAD CIRCUIT  •  LAYOUT: MOUNTAIN PASS` + `FICTIONAL LAYOUT`
tag for world pins), `%LapsLabel` (`2 LAPS`), `%BestLapLabel` (`BEST —` when unset).
Best lap is **read-only**, computed in the menu (no `BestLapRecords` change):
`BestLapRecords.new()` + `load_from_slot(0)` + scan `keys()` for `"<track_id>|"`,
take the min across classes, format `m:ss.mmm`. Label it `BEST (LAYOUT)` because the
record is per layout (`race_ui._resolve_track_id`), not per circuit location.

### 2.8 Race-flow wiring — unchanged

`select_pin()` → `_selected_id` (pin) → `_on_play_pressed()` uses
`TrackRegistry.get_track(pin.track_id).laps_default` → `RaceManager.queue_race(laps)`
→ `launch_callback(scene_path)` (unchanged lines 128-134). `select_track(track_id)`
is **kept as a compatibility wrapper** that selects the first pin whose `track_id`
matches → `tests/test_track_system.gd:40-57` and `tests/suites/test_race_loop.gd:391`
keep passing verbatim. No `RaceManager`, `race_ui`, save-file or GameState change.

---

## 3. Implementation steps

Ordered; each phase ends with a gate. **Never run two Godot processes at once**; the
full suite goes to a background sub-agent per `AGENTS.md`, and read
`docs/GDUNIT_GATE.md` before the first run.

**Phase 0 — asset + license (no code).**
1. Download the CC0 SVG to `assets/ui/world_map_equirectangular.svg` (create the dir;
   `assets/ui/` does not exist yet — `assets/*` today holds cars/trees/rocks/track_props).
2. Write `assets/ui/License.txt` (source URL, author, CC0 1.0, date). Confirm the
   header still reads `viewBox="0 0 360 180"` in the downloaded copy.
3. `--headless --import .`, filter for `SCRIPT ERROR`/`Parse Error`, and **time it**
   (a 1.4 MB / multi-path SVG rasterized by ThorVG is the one unknown here). If import
   is slow or the raster is wrong, fall back to committing a pre-rasterized PNG
   (rasterize once with `Image.load_svg_from_buffer(buf, 4.0)` in a throwaway
   `--headless -s` script, save PNG, delete the SVG from the import path) and say so
   in the plan/log. Record the imported texture size in the PR note.

**Phase 1 — pure projection + data (headless, no scene).**
4. New `scripts/ui/world_map_projection.gd` (`class_name WorldMapProjection extends
   RefCounted`): `lonlat_to_map_point`, `lonlat_of`, `lonlat_to_uv`, `uv_to_lonlat`,
   `region_corners(region_id)`, `build_fit(region_id, draw_size, fallback_pin)`,
   `project_pin(pin, fit) -> Vector2`. Pure statics, `MapRoads` reused for fit/screen
   math, `WorldMapProjection` owns the `-lat` inversion.
5. `scripts/track/track_registry.gd` — additive `pins`, `regions`, `REGION_*`,
   `DEFAULT_REGION`, and accessors. Touch nothing that already exists.
6. New `scripts/ui/levant_outline.gd` (`class_name LevantOutline extends RefCounted`):
   the three authored rings + `rings()` / `water_rings()` helpers, each ring a
   `PackedVector2Array` of `(lon, lat)`.

**Phase 2 — map Control.**
7. New `scripts/ui/track_map.gd` (`class_name TrackMap extends Control`):
   `region`, `selected_pin_id` (setters → `_update_projection()` + `queue_redraw()`),
   `visible_pin_ids()`, `pin_screen_position(pin_id)`, `hit_test(screen_pos)`,
   signals `pin_clicked(pin_id)` / `pin_hovered(pin_id)`, `_dirty`/`refresh()` pattern
   from `world_map.gd:260-321`, `_notification(NOTIFICATION_RESIZED)` → recompute fit.
   `_update_projection()` must run from `_ready()`/resize only — **never depend on
   `_draw()` having run**, or headless tests can't read pin positions.

**Phase 3 — menu rework.**
8. `scenes/ui/track_select.tscn` — restructure to a wide layout (1080p target, window
   is 1920×1080): `HBox` → left `%MapPanel` (`%TrackMap`, ~1150×740) / right `VBox`
   (`%RegionButton`, `%TrackNameLabel`, `%MetaLabel`, `%LapsLabel`, `%BestLapLabel`,
   `ScrollContainer > %TrackGrid`, `ButtonsRow` with `%PlayButton`/`%BackButton`).
   **Keep `%TrackGrid`, `%PlayButton`, `%BackButton`, `%TrackNameLabel` and `UiBlip`
   as-is** (existing tests look them up by name), keep the ACCENT/panel palette.
9. `scripts/ui/track_select.gd` —
   `_build_cards()` iterates **pins of the active region** (card text = pin `label` +
   `CLASS <layout difficulty>` + layout `circuit_type`), cards `FOCUS_ALL` + blips;
   `select_pin(pin_id)` (new primary) + `select_track(track_id)` (compat wrapper);
   `get_selected_pin_id()`; `set_region(region_id)` + `%RegionButton` toggling
   WORLD ⇄ ISRAEL (default ISRAEL); card/pin sync; card panel updates incl. read-only
   best lap; `_on_play_pressed()` unchanged apart from reading `laps_default` off the
   selected pin's layout; `grab_focus()` the selected card on ready.

**Phase 4 — tests (see §4).**

**Phase 5 — later, explicitly not MVP:** pan/zoom gestures, runtime-vector world land,
per-circuit best-lap records (needs race-semantics work), real Israeli layouts.

**Verification gates (each once, never re-run "to confirm"):**
- `--headless --import .` filtered for `SCRIPT ERROR`/`Parse Error` (expect zero).
- Targeted suites via `-a` (one flag per suite), then the full
  `py tools\gdunit_parallel.py -j 4` in a background sub-agent, read from
  `reports/parallel/summary.json` + `merged-results.xml`.
- `graphify update .` after the code changes (GDScript is not in the graph; the plan
  doc is).

---

## 4. Tests

### New — `tests/suites/test_race_menu_map.gd` (headless, no engine frames where possible)

Registry/data contract (no scene):
1. `test_pins_are_well_formed_and_point_at_real_layouts` — pin ids unique; every pin
   has non-empty `label`/`region`; `lat ∈ [-90, 90]`; `lon ∈ [-180, 180]`;
   `TrackRegistry.has_track(pin.track_id)` for **every** pin; `get_scene_path()` resolves.
2. `test_every_layout_has_at_least_one_pin` — for each id in `get_track_ids()`,
   `pins_for_track(id).size() >= 1` (the many-to-one coverage contract; pins sharing a
   layout are asserted explicitly: 3 pins per layout today).
3. `test_default_region_is_israel_and_holds_at_least_three_pins` —
   `DEFAULT_REGION == REGION_ISRAEL`; Israel pins ≥ 3; every pin's lat/lon inside
   `region_bounds(pin.region)` (the framing box actually contains its pins).

Projection (no scene):
4. `test_lonlat_uv_round_trip` — `lonlat_to_uv(-90, -180) == Vector2(0, 0)`;
   `lonlat_to_uv(90, 180) == Vector2(1, 1)`; `lonlat_to_uv(0, 0) == Vector2(0.5, 0.5)`;
   `uv_to_lonlat(lonlat_to_uv(...))` within `0.001` for a few points.
5. `test_fit_puts_north_up_and_west_left` — build the world fit over a 2:1 draw size;
   `project_pin({lat: 90, lon: -180})` == top-left of the fitted content,
   `{lat: -90, lon: 180}` == bottom-right (locks the `-lat` inversion).
6. `test_israel_fit_zooms_past_the_world_fit` — `build_fit(ISRAEL, ...).scale >
   build_fit(WORLD, ...).scale`; all 3 Israel pins project inside the draw rect and the
   6 world pins project outside it (proves the framing, not just the numbers).
7. `test_screen_to_lonlat_is_the_inverse_of_project` — `screen_to_world` +
   `WorldMapProjection.lonlat_of` round-trips a pin position within `0.01°`.

Menu (scene, `scene_runner` + `simulate_frames(2)`, mirroring
`tests/test_track_system.gd:22-38`):
8. `test_menu_lists_one_card_per_visible_pin` — card count == `visible_pin_ids().size()`
   == Israel pin count by default; card text contains the pin label and its layout's
   `CLASS x`.
9. `test_pin_click_selects_the_pin` — set the map size explicitly, `pin_screen_position
   ("negev_speedway")`, feed that point to `hit_test()`/the click handler →
   `get_selected_pin_id() == "negev_speedway"` and
   `get_selected_scene_path() == TrackRegistry.get_scene_path("oval")`.
10. `test_region_toggle_switches_pins_and_backdrop` — `set_region(WORLD)` → 9 visible
    pins, `set_region(ISRAEL)` → 3, default Israel; selection never invisible.
11. `test_play_queues_the_selected_pins_laps` — `select_pin("spa")` →
    `_on_play_pressed()` → launched path is `mountain_pass` scene and
    `RaceManager.consume_pending_race() == 2`; end with `consume_pending_race()`.
12. `test_legacy_select_track_still_resolves_a_pin` — `select_track("northern_isle")`
    → selected pin is `galilee_circuit` (first pin of that layout) and the scene path
    is unchanged (compatibility lock for `test_race_loop.gd:391`).

### Updated — `tests/test_track_system.gd` (2 functions, deliberate)
- `test_track_select_builds_one_card_per_track` → rename/intent to
  *builds one card per pin*: card count == Israel pin count in the default region, card
  text contains the pin `label` + `CLASS <layout difficulty>` + layout `circuit_type`,
  and `get_selected_scene_path()` == the layout scene of the **first** pin.
- `test_track_select_highlight_updates_on_select` → index cards by
  `get_pin_ids().find(...)` (pin order), not `get_track_ids()`.
- **Leave `test_registry_contains_expected_tracks` (L3-14),
  `test_registry_scene_files_exist` (L16-20) and
  `test_track_select_play_loads_selected_scene` (L40-57) untouched** — they must stay
  green, they are the regression proof that `tracks` was not mutated.
- No change needed in `test_race_loop.gd`, `test_audio_feel_layers.gd`,
  `test_best_lap_records.gd` (verify, don't edit).

Conventions to honour (they bite): `assert_that(...).is_equal` style; warnings are
errors under gdUnit so keep full type annotations (`var track_id: String = ...`) and
never assign a `Variant`-returning call to an inferred `:=`; scene suites need
`await runner.simulate_frames(2)`; `RaceManager` state must be drained
(`consume_pending_race()`) at the end of any test that queues a race.

---

## 5. Risks / gotchas

1. **Positional/registry breakage (AGENTS.md history).** `contains_exactly` is
   order+size sensitive (`GdUnitArrayAssertImpl.gd:130-152`) — adding a `tracks` entry
   would break `tests/test_track_system.gd:5`. The additive `pins` dict avoids it
   entirely; do not "helpfully" add tracks.
2. **`_resolve_track_id()` first-match (race_ui:440-450).** Duplicate `scene_path`
   values across registry entries would silently mis-key best laps. Pins are therefore
   in a separate table; the card labels best lap `BEST (LAYOUT)` and shares it across
   pins with the same layout (documented, intentional).
3. **Latitude sign inversion.** `-lat` in `map_point()` is the whole north-up story;
   test 5 locks it. Symptom if broken: Africa on top.
4. **SVG import cost.** A 1.4 MB multi-path SVG must be rasterized by Godot/ThorVG at
   import; measure in Phase 0 and keep `scale=4`. Fallback (pre-rasterized PNG) is in
   the steps so a slow import cannot block the feature. Do not import at scale ≥ 16
   (memory) and do not expect a world raster to survive the Israel zoom.
5. **Israel zoom needs vector, not raster.** Decided in §2.4: procedural locally-authored
   rings. If someone "simplifies" by scaling the world texture up, the result is 7-pixel
   Israel — reject that in review.
6. **Headless draw.** `_draw()` never runs in headless gdUnit; pin positions must be
   computed in `_update_projection()` (called from `_ready`/resize), and tests must set
   `Control.size` explicitly. A design that only fills a `_draw()`-time cache is
   untestable and will produce false greens.
7. **Control sizing in tests.** The scene-renderer viewport has its own size; assert
   against `map.size`, not the 1920×1080 project size.
8. **`%`-node and name coupling.** `%TrackGrid`, `%PlayButton`, `%BackButton`,
   `%TrackNameLabel`, `UiBlip`, `launch_callback` are load-bearing for existing tests
   and for `tools/menu_autopilot.gd` (which only clicks main_menu, but the reporter
   dumps node names). Keep them.
9. **Blip count tests.** `test_audio_feel_layers.gd:194-211` asserts the play blip fires
   **exactly once**. The new `grab_focus()` on ready must happen before any test spy is
   installed (it will, in `_ready`) and the new `%RegionButton` needs `_bind_menu_blip`
   like every other button, but the region toggle must not be triggered in that test.
   Re-run the suite after touching focus.
10. **New region/framing state must not leak between scenes.** No autoload writes, no
    save-file schema change — the region is per-instance menu state only (avoids the
    SaveManager `.tmp` collision class of bug noted in AGENTS.md).
11. **Coordinate precision is cosmetic.** Pin lat/longs are for placement, not survey
    accuracy; tests only assert ranges/containment, never exact published coordinates.
12. **Dateline.** No pin is near ±180°, so no wrap handling is needed; note the
    limitation in the script header if a Pacific pin is ever added.
13. **Asset/license.** CC0 only; the SVG page was verified during planning. If the
    asset is swapped later, re-verify the license and update `assets/ui/License.txt` —
    a CC-BY-SA or photo-real replacement would add license debt the project does not
    currently carry.
14. **Docs drift.** `docs/research/ultradrive_features.md:115` describes track_select as
    a "grid of preview tiles"; update that line in the same PR.

---

## 6. Do NOT touch

- `scripts/track/track_registry.gd :: tracks` and `get_track_ids/get_track/
  get_scene_path/has_track` — additive only (new `pins`/`regions` + new accessors).
- `autoload/race_manager.gd` — no signature or semantic change (`queue_race` /
  `consume_pending_race` are the contract).
- `scripts/race/race_ui.gd` — HUD start, `_resolve_track_id()`, record submission.
- `scripts/race/best_lap_records.gd` / `autoload/save_manager.gd` — read-only use; no
  new keys, no schema change.
- `scripts/ui/map_roads.gd` — reuse `compute_fit`/`world_to_screen`/`screen_to_world`
  as-is; do not add lat/lon concepts to it (that lives in `WorldMapProjection`).
- `scripts/ui/world_map.gd`, `scripts/ui/minimap.gd`, `scripts/ui/pause_menu.gd` — the
  open-world maps are a different coordinate space; copy their patterns, don't edit.
- `scripts/ui/main_menu.gd` — entry point already correct.
- `scripts/ui/scene_transition.gd`, `autoload/game_state.gd` — no new scene-change paths.
- `scenes/test/test_track.tscn`, `scenes/track/mountain_pass.tscn`,
  `scenes/track/northern_isle.tscn`, and any track/layout geometry — the layouts are
  used as-is (mapped many-to-one).
- Existing assets under `assets/**` (cars/trees/rocks/track_props/videos) — only the new
  `assets/ui/` dir is added.
- `tools/gdunit_parallel.py`, `tools/menu_autopilot.gd`, `addons/**`.

## 7. Open questions (decide before/while implementing)

- Trim the world pin list (6 real circuits) or extend it? The table is the seam; each
  added pin is one dict entry + no code.
  **RESOLVED 2026-10-16 (EXTEND):** `docs/plans/race_menu_map_expansion_plan.md` grew the
  world tier to a 30-circuit calendar (36 pins total) and gave the 3 shipped layouts their
  own `home_*` pins labelled with their exact `display_name`. This plan's 9-pin table is
  superseded; the seam held — no code change was needed to add pins.
- Does the intended end state include **new Israeli track layouts** (not just pins)?
  This plan deliberately ships pins over the 3 existing layouts (as the request allows);
  real layouts are a separate track-authoring stream that plugs into the same `pins`
  table by adding a `tracks` entry.
- Should WORLD-view pins be visually distinguished from Israel pins (e.g. a "home
  region" ring)? Cheap, and a nice-to-have.
- Pan/zoom beyond region framing stays Phase 5.
