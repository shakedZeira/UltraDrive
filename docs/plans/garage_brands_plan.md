# Plan — Garage: Group Owned Cars by Brand

Status: DONE (implemented 2026-10-16 — registry `scripts/career/car_brands.gd`,
13 emblems in `assets/ui/brands/`, `CarConfig.brand`/`brand_display_name`,
`garage.tscn` CarScroll/CarRail restructure, `garage_ui.gd` grouped rail +
owned-index meta + brand chip strip, new `tests/suites/test_garage_brands.gd`,
`test_audio_feel_layers.gd` rail fix). Deviations from the draft below are
listed at the end of this file.
Owner: garage/UI workstream
Gate suites (after implementation): `tests/suites/test_garage_brands.gd` (new),
`tests/suites/test_garage_tuning.gd`, `tests/suites/test_audio_feel_layers.gd`,
`tests/suites/test_car_default_setup.gd`, `tests/suites/test_cc0_cars.gd` (all
must stay green).

## 1. Goal

The garage currently shows one flat rail of cards, one per owned car
(`scripts/ui/garage_ui.gd::_build_rail`, lines 76–110). This plan restructures
the rail into per-brand sections: each section has a header (brand emblem +
brand name) and a row of that brand's car cards. Real-brand cars (e.g. the
bundled Nissan GT-R) group under their manufacturer; every fictional in-house
car (Striker, Thunderhead, Dirt Devil, Comet, Hooligan, Interceptor) groups
under one in-house brand, **"UltraDrive Motors"**, with an original monogram
emblem. Nothing about saving, loading, selection semantics, or the
track-select handoff changes.

## 2. Current state (verified, file:line)

- Catalog: 7 `CarConfig` resources in `resources/cars/` — `starter_car`,
  `muscle_car`, `rally_hatch` (the three `Garage.STARTER_CARS`,
  `scripts/career/garage.gd:13–15`) and the four CC0 imports
  `cc0_sedan_sports`, `cc0_hatchback_sports`, `cc0_van`, `cc0_race`.
  `Garage.new_from_save()` always grants the three starters owned; the CC0s are
  owned only when a save already grants them (`garage.gd:74–88`). There is no
  shop/dealership yet (roadmap AAA-10 is planned-only), so the owned roster is
  effectively 3–7 cars.
- `CarConfig` (`scripts/vehicle/car_config.gd`) has **no brand/manufacturer
  field** at all — `car_name` is display-only (`:8`).
- UI: `garage.tscn` `CarRail` is an `HBoxContainer` anchored `left_right = 360`
  (i.e. −360..+360, 720 px wide, `garage.tscn:409–413`). `_build_rail()` spawns
  one fixed-size card per owned car (`CARD_W 184`, `CARD_H 224`,
  `garage_ui.gd:14–15`) — 7 cards already overflow the 720 px rail with no
  scroll. There is no ScrollContainer.
- Card semantics that must survive: cards are mouse-only (`FOCUS_NONE`,
  `garage_ui.gd:82`) — the only focusable garage controls are `%Select` and
  `%Back` (`garage.tscn:208`, `:246`) — so keyboard/gamepad tab order is
  unaffected by rail contents and MUST stay that way.
- No brand/logo art exists anywhere (`assets/ui/` has only `hud/`). No brand
  string exists in scripts/resources (grep for `nissan|brand|emblem` across
  `scripts/` and `resources/` — only unrelated uses).
- `assets/cars/` also carries 13 unused real-brand GLBs committed as
  "Rivals as real GLBs" (`bfeee25`) that no `CarConfig` or `RIVAL_VISUALS`
  (`scripts/vehicle/car_visuals.gd:18–38`) entry references yet
  (`nissan_gt_r35_2017`, `bmw_m3_e30_1986`, `chevrolet_corvette_c7_2014`,
  `ford_mustang_1967`, `honda_nsx_1990`, `lamborghini_diablo_1990`,
  `mazda_rx7_fd_1995`, `mitsubishi_lancer_evolution_1997`,
  `porsche_911_gt3_2003`, `subaru_impreza_2004`, `toyota_ae86_1983`,
  `toyota_supra_mk4_1993`, `volkswagen_beetle_1967`). These are exactly the
  future real-brand roster; this plan pre-stages brand ids/emblems for them.
- Existing tests that touch the rail:
  - `test_audio_feel_layers.gd:226–244`
    (`test_garage_card_press_triggers_menu_blip_once`) presses
    `%CarRail.get_child(0) as Button` — **this breaks** under section
    wrappers; must be updated (§6).
  - `test_garage_tuning.gd` (assertion-heavy, never presses rail children) is
    unaffected.
  - `test_car_default_setup.gd:20` and `test_cc0_cars.gd:19` iterate the
    catalog via `DirAccess` globs — unaffected by new fields with defaults.

## 3. Design decisions

### 3.1 Brand registry — new `scripts/career/car_brands.gd`

`class_name CarBrands extends RefCounted` — pure static data + helpers, no
scene/engine dependencies, headless-testable. Single source of truth for
brand ids, display names, aliases, emblem paths, and the grouping order.

```gdscript
# scripts/career/car_brands.gd (sketch — implementation reference)
const HOUSE_ID := "ultradrive"
const HOUSE_NAME := "UltraDrive Motors"

const BRANDS := {
    "ultradrive": {
        "display_name": "UltraDrive Motors",
        "emblem": "res://assets/ui/brands/house_ultradrive.svg",
        "aliases": ["ultradrive", "ultradrive motors"],
    },
    "bmw":          {"display_name": "BMW",           "emblem": "res://assets/ui/brands/bmw.svg",           "aliases": ["bmw"]},
    "chevrolet":    {"display_name": "Chevrolet",     "emblem": "res://assets/ui/brands/chevrolet.svg",     "aliases": ["chevrolet", "chevy"]},
    "ford":         {"display_name": "Ford",          "emblem": "res://assets/ui/brands/ford.svg",          "aliases": ["ford"]},
    "honda":        {"display_name": "Honda",         "emblem": "res://assets/ui/brands/honda.svg",         "aliases": ["honda"]},
    "lamborghini":  {"display_name": "Lamborghini",   "emblem": "res://assets/ui/brands/lamborghini.svg",   "aliases": ["lamborghini"]},
    "mazda":        {"display_name": "Mazda",         "emblem": "res://assets/ui/brands/mazda.svg",         "aliases": ["mazda"]},
    "mitsubishi":   {"display_name": "Mitsubishi",    "emblem": "res://assets/ui/brands/mitsubishi.svg",    "aliases": ["mitsubishi"]},
    "nissan":       {"display_name": "Nissan",        "emblem": "res://assets/ui/brands/nissan.svg",        "aliases": ["nissan"]},
    "porsche":      {"display_name": "Porsche",       "emblem": "res://assets/ui/brands/porsche.svg",       "aliases": ["porsche"]},
    "subaru":       {"display_name": "Subaru",        "emblem": "res://assets/ui/brands/subaru.svg",        "aliases": ["subaru"]},
    "toyota":       {"display_name": "Toyota",        "emblem": "res://assets/ui/brands/toyota.svg",        "aliases": ["toyota"]},
    "volkswagen":   {"display_name": "Volkswagen",    "emblem": "res://assets/ui/brands/volkswagen.svg",    "aliases": ["volkswagen", "vw"]},
}

# House brand first, every other brand alphabetically by display name.
const CATEGORY_ORDER := ["ultradrive", "bmw", "chevrolet", "ford", "honda",
    "lamborghini", "mazda", "mitsubishi", "nissan", "porsche", "subaru",
    "toyota", "volkswagen"]

static func brand_ids() -> Array            # CATEGORY_ORDER copy
static func display_name(id: String) -> String   # unknown id -> HOUSE_NAME
static func emblem_path(id: String) -> String    # unknown id -> house emblem
static func resolve_brand_id(car: CarConfig) -> String  # see 3.2
static func group_owned(owned: Array) -> Array
    # -> Array of {"brand_id", "display_name", "emblem_path", "cars": Array[CarConfig]}
    # only brands that own >=1 car, ordered by CATEGORY_ORDER; empty input -> []
```

Notes:
- The house brand is always present in the returned groups when `owned` is
  non-empty (the starters are always owned), so the UI never needs a
  "miscellaneous" bucket.
- `emblem_path()` returns the path even if the file is missing; the UI
  TextureRect simply shows nothing when the texture fails to load (the
  importer creates a placeholder by default), so a missing/renamed SVG
  degrades to "no emblem" rather than an error.

### 3.2 Car→brand resolution and the `CarConfig` data model

`CarConfig` gains two optional exported fields (near the top of
`scripts/vehicle/car_config.gd`, after `car_name`):

```gdscript
@export var brand: String = ""              # brand id, e.g. "nissan"; "" = derive
@export var brand_display_name: String = "" # optional override for display only
```

Resolution order inside `CarBrands.resolve_brand_id(car)` — first hit wins:

1. `car.brand` non-empty → match against `BRANDS` ids, else against
   `aliases` (exact, case-insensitive); an unrecognized non-empty value falls
   through to rule 2 (never hard-fails).
2. Basename of `car.resource_path` (e.g. `nissan_gt_r35_2017`) and basename of
   `car.visual_path` (e.g. `cc0_sedan_sports`) — **whole-token** alias match:
   split the basename on `_` and match a token against every brand's aliases,
   scanning left to right, first brand with any matching token wins.
   - Verified non-collisions: `cc0`, `starter`, `muscle`, `rally`, `car`,
     `hatch`, `sedan`, `sports`, `van`, `race` are not aliases of any brand;
     the GT-R resolves via token `nissan`; future real-brand configs resolve
     via their model-name token (e.g. `..._supra_mk4_1993` → `toyota` only if
     the config sets `brand`, since "supra" is not an alias — see the staged
     table below, where every future real config is expected to set `brand`
     explicitly and the token rule is only a safety net).
3. `car.car_name` (display name, spaces split) — same whole-token alias match
   (e.g. a config literally named "Nissan GT-R R35").
4. Default: `CarBrands.HOUSE_ID` — every fictional car lands in the in-house
   brand with zero configuration, and an unknown future car is never
   invisible.

Display name: `car.brand_display_name` if set, else `display_name(resolve_brand_id(car))`.

Why a field + derivation instead of a hard-coded map in the UI: future
configs (real rivals, shop cars, DLC) declare their brand once in the resource
and everything downstream (garage sections, shop cards, car-select headers)
just works; old saves and fieldless configs still resolve via the path rule.

### 3.3 Initial car→brand mapping (the 7 live configs)

| Resource (`resources/cars/`) | `car_name` | Brand id | Section |
|---|---|---|---|
| `starter_car.tres`     | Striker     | `ultradrive` | UltraDrive Motors |
| `muscle_car.tres`      | Thunderhead | `ultradrive` | UltraDrive Motors |
| `rally_hatch.tres`     | Dirt Devil  | `ultradrive` | UltraDrive Motors |
| `cc0_sedan_sports.tres`  | Comet      | `ultradrive` | UltraDrive Motors |
| `cc0_hatchback_sports.tres` | Hooligan | `ultradrive` | UltraDrive Motors |
| `cc0_race.tres`        | Interceptor | `ultradrive` | UltraDrive Motors |
| `cc0_van.tres`         | (van)       | `ultradrive` | UltraDrive Motors |
| `nissan_gt_r35_2017.tres`* | GT-R R35 | `nissan`     | Nissan |

\* the Nissan GT-R currently exists only as a GLB (`assets/cars/
nissan_gt_r35_2017.glb`), not as a `.tres` config. It is NOT part of this
task's scope to add configs; the brand table/emblem are pre-staged so the
first real-brand config (shop/rivals work, roadmap AAA-10/AI-26) slots in by
adding `brand = "nissan"` to its resource. **Exception:** if the implementer
finds a one-line-safe moment to add a `nissan_gt_r35_2017.tres` (copy an
existing `.tres`, swap `visual_path`/name/stats), it is welcome but optional —
the tests below must not depend on it existing.

Pre-staged future mappings (for the 13 unused GLBs, documented here so the
rivals/shop work inherits them): `bmw_m3_e30_1986`→`bmw`,
`chevrolet_corvette_c7_2014`→`chevrolet`, `ford_mustang_1967`→`ford`,
`honda_nsx_1990`→`honda`, `lamborghini_diablo_1990`→`lamborghini`,
`mazda_rx7_fd_1995`→`mazda`, `mitsubishi_lancer_evolution_1997`→`mitsubishi`,
`nissan_gt_r35_2017`→`nissan`, `porsche_911_gt3_2003`→`porsche`,
`subaru_impreza_2004`→`subaru`, `toyota_ae86_1983`/`toyota_supra_mk4_1993`→
`toyota`, `volkswagen_beetle_1967`→`volkswagen`.

### 3.4 Emblems — 13 original fictional SVGs in `assets/ui/brands/`

Every emblem is hand-authored original geometry: a distinct brand-specific
container silhouette plus a single-letter or abstract monogram. NOTHING
resembles a real manufacturer's logo — no real wordmarks, no copied mark
geometry (no BMW roundel quadrants, no Nissan circle-and-bar, no Toyota
overlapping ellipses, etc.). Each mark is a distinct letter or shape, drawn
from scratch.

Technical spec (mandatory, because `.gitignore` ignores `*.import` so we
cannot pin SVG import settings in the repo):

- Canvas `viewBox="0 0 64 64"`, artwork inset to a ~4..60 safe area so a
  default import scaled to any square size stays fully visible.
- Palette: fill `#131C2E` (dark slate, matches card panel),
  stroke `#E6B23C` (gold, matches accent), stroke-width 4, round caps/joins.
  Monoline stroke-only art (plus the dark container fill) — **no `<text>`
  elements** (Godot's SVG importer has no font support).
- One `<svg>` root, no `width`/`height` attributes (viewBox only), no external
  refs, no filters/gradients, ASCII only.
- Legibility target: distinct silhouettes + bold monogram readable at 32–48 px
  (the in-game render height).

Silhouette + monogram assignments (all original):

| Brand | Container silhouette | Monogram / shape |
|---|---|---|
| UltraDrive Motors (house) | Hexagon | Stylised **U** whose right stem extends into a speed chevron |
| BMW | Circle roundel | Single thick lightning **B** wedge (angular, not the letter-in-quarters form) |
| Chevrolet | Crossless bowtie **X** built from two tapered bars | abstract bowtie-derived X |
| Ford | Horizontal oval | Script-style **F** swash (single stroke) |
| Honda | Rounded trapezoid badge | Angular **H** with a bar-topped cross |
| Lamborghini | Shield (pointed base) | Bulge-shouldered **L** forming a shield corner |
| Mazda | Rounded-square badge | Diamond **M** drawn as one continuous folded stroke |
| Mitsubishi | Diamond (rotated square) | Three separate solid lozenges arranged around the centre (diamond triad) |
| Nissan | Rectangle bar | Block **N** inside a horizontal bar frame |
| Porsche | Crest shape | Vertical-centre **P** stem over a small crown notch |
| Subaru | Oval | Star polygon (single 5-point star) |
| Toyota | Rounded capsule | Three stacked chevrons forming an abstract **T** |
| Volkswagen | Circle roundel | Stacked **V** over **W** as two chevrons sharing one stroke |

### 3.5 Garage UI restructure (`garage_ui.gd` + `garage.tscn`)

Scene (`scenes/ui/garage.tscn`):
- Wrap the rail in a scroll area and re-type it for vertical stacking:
  - New `CarScroll: ScrollContainer` takes over the current `CarRail` rect
    (anchors `left_right = 360`, horizontal scroll on, vertical off).
- `CarRail` becomes its child, re-typed from `HBoxContainer` to
    `VBoxContainer` (`theme_override_constants/separation = 28`) so brand
    sections stack vertically.
- Each brand section is a `VBoxContainer` (header + `HBoxContainer` card
    row) appended to `CarRail`.
- Section header row: `HBoxContainer` with (a) `TextureRect` emblem
  (`custom_minimum_size = Vector2(40, 40)`, `expand_mode =
  EXPAND_IGNORE_SIZE`, `stretch_mode = KEEP_ASPECT_CENTERED` — mandatory so a
  differently-sized SVG import cannot blow up the layout), (b) `Label` brand
  name using the existing `%CarNameLabel` font overrides (font size 34) and
  the accent colour. **No focusable controls** — headers must never enter the
  tab order (cards are `FOCUS_NONE`; only `%Select`/`%Back` are focusable).
- Card row: `HBoxContainer` (`theme_override_constants/separation = 16`), the
  card-scene children exactly as today.
- Net node change is additions + the `CarRail` type swap; `load_steps` in the
  `.tscn` header stays valid (no new sub-resources; new nodes only). If adding
  nodes makes the editor rewrite `load_steps`, update line 1 accordingly.

Script (`scripts/ui/garage_ui.gd`):
- `_build_rail()` (lines 76–110): free existing children; call
  `CarBrands.group_owned(owned)`; for each group build the header (emblem
  TextureRect + Label) and a card-row `HBoxContainer`; cards are created by the
  same `_create_card(car)` helper extracted from today's loop body (button,
  TextureRect with `car.get_preview()`, name label, class chip — unchanged
  visuals). Append the header+row even when the group has one car.
- **Index remap (required):** `_update_cards()` (lines 121–127) currently
  assumes `_cards[j]` maps to `owned[j]`. After grouping that is false.
  Fix: in `_create_card`, `card.set_meta("owned_index", i)`; `_update_cards()`
  reads `int(card.get_meta("owned_index", j))`. `_show_car(i)` (lines
  133–148) keeps its owned-index semantics untouched.
- Layout: with section headers (~56 px each) the vertical stack of two rows
  fits the 524 px rail height; the horizontal ScrollContainer fixes the
  pre-existing 7-card overflow (7×184+6×16 = 1224 px content vs 720 px
  viewport). Set `CarScroll` horizontal scroll so the active card is visible
  optionally (nice-to-have, not required; default scroll behaviour is fine).
- Optional (include it — cheap and sells the feature): a brand chip strip
  under `%CarNameLabel` — small `HBoxContainer` of 20 px emblems, one per
  brand present, reusing the same TextureRect settings; clicking a chip is NOT
  required (mouse users scroll; no new focusable nodes).
- No changes to `%Select`/`%Back` handlers, `_show_car`, save reads/writes, or
  `race_ui` integration.

### 3.6 What explicitly does NOT change

- Save format: `Garage` persists `_owned_car_ids` + `active_car_id` via
  `SaveManager` (`garage.gd:59–70`); no new persisted keys, no migration.
- `Garage.set_active_car` / `consume_active_car()` contract and the
  track-select consumption path (`race_ui.gd:37–42`).
- Card mouse-only selection, `%Select`/`%Back` focus, pause-menu focus
  behaviour.
- `CarVisuals` / rival visuals / track-select previews.
- The 7 existing `.tres` files' gameplay stats; the only optional `.tres` edit
  is adding `brand = "..."` (and it is redundant thanks to the derivation
  rule — recommended for the Nissan config only, when it exists).

## 4. Implementation steps

1. **Brand registry** — create `scripts/career/car_brands.gd` per §3.1
   (static only; no engine calls in `resolve_brand_id` beyond string work so
   it is trivially headless-testable).
2. **Emblems** — author the 13 SVGs in `assets/ui/brands/` per §3.4
   (`house_ultradrive.svg`, `bmw.svg`, `chevrolet.svg`, `ford.svg`,
   `honda.svg`, `lamborghini.svg`, `mazda.svg`, `mitsubishi.svg`,
   `nissan.svg`, `porsche.svg`, `subaru.svg`, `toyota.svg`,
   `volkswagen.svg`).
3. **CarConfig fields** — add `brand` / `brand_display_name` exports to
   `scripts/vehicle/car_config.gd` (after `car_name`, ~line 9).
4. **(Optional) Nissan config** — if done, `resources/cars/
   nissan_gt_r35_2017.tres` cloned from an existing config with
   `brand = "nissan"`, `visual_path = "res://assets/cars/
   nissan_gt_r35_2017.glb"`, a sensible display name and class-A stats.
5. **Scene** — restructure the rail per §3.5 (`CarScroll` ScrollContainer →
   `CarRail` VBoxContainer); keep every other node untouched.
6. **Script** — rewrite `_build_rail()`, extract `_create_card()`, add
   `owned_index` meta + fix `_update_cards()`, add the optional brand chip
   strip. Keep `class_name GarageUI` and all `%` node references valid.
7. **Tests** — new suite + one test fix (§5).
8. **Docs** — brief note in `docs/ROADMAP.md` garage line + this plan's status
   flip to DONE.
9. **Graph** — `graphify update .` after code changes (per AGENTS.md).

## 5. Test plan

New `tests/suites/test_garage_brands.gd` (GDUnit4; follow the repo rules:
`assert_that(...).is_equal`, no bare `assert`, no `:=` from Variant-returning
calls — gdUnit treats warnings as errors; save/restore `user://` slot 0 like
`test_garage_tuning.gd` does):

1. `test_brand_table_is_complete` — every `CarBrands.BRANDS` key appears in
   `CATEGORY_ORDER` exactly once; `CATEGORY_ORDER` has the house id first and
   the rest strictly alphabetical by display name; each brand's `emblem`
   path is under `res://assets/ui/brands/` and `FileAccess.file_exists` is
   true for all 13.
2. `test_resolve_brand_id_falls_back_to_house` — a `CarConfig` with empty
   `brand`, a `resource_path` of `""` (or a scratch path) and a `car_name`
   like "Comet" resolves to `CarBrands.HOUSE_ID`; explicit `brand = "nissan"`
   resolves to `nissan`.
3. `test_resolve_brand_id_derives_from_resource_path` — build two scratch
   configs via `ConfigFile.save()` into `user://` (or set `resource_path`
   indirectly is not possible — instead rely on the `.tres` catalog):
   `res://resources/cars/starter_car.tres` → house, and (only if step 4 of
   §4 shipped) `nissan_gt_r35_2017.tres` → `nissan`; also assert `cc0_*`
   configs all resolve to the house brand (guards the token rule against
   false positives).
4. `test_group_owned_is_ordered_and_partitioned` — feed `Garage.new_from_save`
   's owned list (or a synthetic array of catalog configs): every owned car
   appears exactly once across groups, group order follows
   `CATEGORY_ORDER`, each group's `display_name`/`emblem_path` match the
   table, empty input returns `[]`.
5. `test_garage_ui_builds_one_section_per_brand` — load
   `res://scenes/ui/garage.tscn` into a scene-tree context, instantiate the
   UI, await one frame; assert `CarRail` child count == number of non-empty
   groups, every section's first child is a header `HBoxContainer` whose
   TextureRect texture is non-null when the emblem file exists, and the
   section's card count equals that brand's owned count; assert NO node in
   the rail has `focus_mode != FOCUS_NONE` (tab-order guard). Tear down the
   scene in `after_test`.
6. `test_garage_card_mapping_survives_grouping` — with ≥2 brands present (add
   a scratch owned id for a non-house config if the catalog lacks one; skip
   gracefully otherwise via `mark_skipped`), pressing the k-th card in DOM
   order selects the car whose `owned_index` meta says it should — assert via
   `_show_car` side effects (selected texture/label), no audio needed.

Update `tests/suites/test_audio_feel_layers.gd:226–244`
(`test_garage_card_press_triggers_menu_blip_once`): replace
`%CarRail.get_child(0) as Button` with the first real card found via
`%CarRail.find_children("*", "Button", true, false)` (recursive, first hit is
the first card), plus a guard `if card == null: return` so the blip test
degrades gracefully if the rail layout ever changes again.

Unchanged suites that must remain green: `test_garage_tuning.gd`,
`test_car_default_setup.gd`, `test_cc0_cars.gd`, `test_car_select.gd`,
`test_race_loop.gd` (RaceManager handoff).

## 6. Risks and gotchas

- **`*.import` is gitignored** — SVG import settings cannot be pinned; hence
  the strict SVG authoring spec (§3.4) and `EXPAND_IGNORE_SIZE` +
  fixed `custom_minimum_size` on every emblem TextureRect so default imports
  can never stretch the layout.
- **gdUnit warnings-as-errors** — avoid `:=` with `get_node`/`find_children`
  (Variant), unused variables, and shadowed names in the new test suite.
- **`_update_cards()` index bug** — the single highest-risk regression; the
  `owned_index` meta must be set for every card and read with a fallback.
- **Focus regressions** — never make headers/chips focusable; verify with
  test 5's tab-order guard.
- **`cc0_van` naming** — its `car_name` may contain brand-adjacent tokens in
  future edits; the whole-token left-to-right rule plus house default keeps
  it safe.
- **One Godot process at a time**; run the gate headless per AGENTS.md
  (import probe, then `GdUnitCmdTool.gd --ignoreHeadlessMode`), and prefer
  `py tools\gdunit_parallel.py -j 4` on the PC.
- **Blender/Gemini side-chains** — irrelevant to this task; do not launch
  them.

## 7. Do NOT touch

- `scripts/career/garage.gd` save/persistence and `STARTER_CARS`.
- `scripts/race/race_ui.gd` race-start consumption of the active car.
- `scripts/vehicle/car_visuals.gd`, `rival_car_visual.gd`,
  `scenes/vehicle/player_car.tscn`, chase camera.
- Any `.tres` gameplay stat (mass, torque, gears) — new fields only.
- `assets/cars/cc0/kenney_car-kit/**` and the 13 rival GLBs (importers only).
- Pause-menu / settings focus code, HUD scripts.
- `tools/gdunit_parallel.py`, `tools/pick.ps1`, `godot_path.bat`.

## 8. Implementation deviations (2026-10-16)

Refs drifted from the draft; the code was trusted and the plan adapted:

1. **`nissan_gt_r35_2017.tres` already exists** (draft §2/§3.3 said GLB-only), so
   the optional step 4 config was NOT written — the token rule resolves it
   anyway (`nissan_gt-r_r35_2017` → `nissan`). The `.tres` was left untouched
   (out of scope); adding `brand = "nissan"` to it remains a redundant
   follow-up.
2. **`cc0_van.tres` does not exist** in `resources/cars/`; the live catalog is
   7 configs, and `Garage.STARTER_CARS` grants all 7 (including the GT-R).
   Roster in practice: 6 house cars + the Nissan.
3. **`CarRail` rect is 720×64 px**, not 524 px tall as the draft assumed
   (`garage.tscn` offsets were `-82..-18`). The `CarScroll` viewport was grown
   to 300 px (`-318..-18`) so two brand sections fit; it still keeps the old
   bottom-centre anchor, width and footer clearance, and defaults to auto
   scrollbars (horizontal for the 6-card house row, vertical as a safety net).
4. **Card size is `Vector2(150, 62)`** in the live code (the draft's `CARD_W
   184`/`CARD_H 224` consts do not exist); card visuals were carried over
   verbatim into `_create_card()`.
5. **`test_audio_feel_layers.gd` also needed the rail cast changed**
   (`as HBoxContainer` → `as VBoxContainer`) — not just the `get_child(0)`
   → `find_children()` swap, since the rail's type changed.
6. `garage_ui.gd` has no `class_name GarageUI`; `CarBrands` was free (grepped).
7. `graphify update .` was intentionally NOT run (performed centrally).
