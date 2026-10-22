# UltraDrive — Race Menu: Continent Regions + Map Zoom

> **Extends** `docs/plans/race_menu_world_map_plan.md` (the map itself) and
> `docs/plans/race_menu_map_expansion_plan.md` (the pin table + label de-clumper).
> This plan fixes two playtest complaints against the shipped circuit map:
> 1. **"the world tier is one giant list — I can't find my circuit"** — the single
>    `REGION_WORLD` tier holds every non-Israeli pin at once, labelled on a
>    whole-globe fit, so ~32 pins collapse into a few clusters.
> 2. **"I want to zoom in on the map"** — the map is a fixed contain-fit with no
>    zoom/pan; `TrackMap` re-fits only on region switch or resize.
>
> **Written:** 2026-10-17 · **Inputs:** user request ("split the World region into
> continents/countries so picking is easier, and let me zoom in"),
> `scripts/track/track_registry.gd`, `scripts/ui/track_map.gd`,
> `scripts/ui/track_select.gd`, `scenes/ui/track_select.tscn`,
> `scripts/ui/world_map_projection.gd`, `scripts/ui/map_roads.gd`, `AGENTS.md`
> (shell/gate/registry rules).
> **Format:** registry retag + region-box growth + registry accessors; `TrackMap`
> membership read + pure zoom/pan statics; menu tab row + zoom controls + scene
> node addition; updated + new tests. **No new scripts, no new sub-resources.**

**DO NOT modify game code from this plan yet** — this document is the spec only.

---

## 1. GOAL + acceptance criteria

Split the single `REGION_WORLD` tier into real continent/country regions so a
player picks a small, legible set of circuits, and add interactive zoom/pan inside
any region. Nothing about race semantics changes.

### Region model

- `TrackRegistry` keeps `REGION_WORLD` as the top-level **"ALL CIRCUITS"**
  overview tier and adds seven continent regions: `EUROPE`, `MIDDLE_EAST`,
  `NORTH_AMERICA`, `ASIA`, `SOUTH_AMERICA`, `AFRICA`, `OCEANIA`.
- Each of the 38 pins is retagged from `REGION_WORLD` to **exactly one** continent
  (Israel's 6 stay `REGION_ISRAEL`). The pin table's **insertion order is
  unchanged**, so per-region card order stays a filtered subsequence of today's
  order (the `home_*` shipped layouts stay first in Israel).
- Each new region gets an AABB framing box that **contains every one of its
  members** (the existing invariant `test_default_region_is_israel_...` L52-59
  already forces this).

### Zoom model

- `TrackMap` gains an interactive view: mouse wheel **about the cursor**, an
  on-screen `− / ⟲ / +` control cluster, and keyboard `+` / `-` / `0`.
- Pan via **left-drag or middle-drag** (>4 px threshold, so a plain click still
  selects a pin).
- Region switch (and a map resize) **resets** zoom to 1.0 / pan to zero.
- The zoom is applied by **transforming the fit Dictionary** (`_fit`), so
  `pin_screen_position()`, `hit_test()`, `_content_rect()`, `_draw_graticule()`
  and the world-backdrop draw all follow automatically. `WorldMapProjection` and
  `MapRoads` are **not touched**.

### Acceptance criteria

1. A `%RegionTabs` row shows one toggle per region id; the active tab is
   highlighted; pressing a tab switches region + backdrop + card list.
2. In any region, the card list and the map draw/hit-test exactly
   `TrackRegistry.pin_ids_for_region(region)` (membership, not containment).
3. `REGION_WORLD` still shows **all** pins (overview tier).
4. Wheel/buttons/keyboard change zoom within `[MIN_ZOOM, MAX_ZOOM]`; the point
   under the cursor stays under the cursor on a wheel zoom about the cursor.
5. Zoom/pan are clamped so the fitted content never leaves a gap when it is
   larger than the viewport, and is centred when smaller.
6. Labels stay legible: reuse the existing pure `select_label_ids()` unchanged —
   at higher zoom pins spread out, so more labels auto-appear; selected/hovered
   pins are always named.
7. Existing suites stay green (see §5): `test_race_menu_map`,
   `test_track_system`, `test_race_layout_preview`, `test_audio_feel_layers`,
   `test_menu_video_background`.

---

## 2. CURRENT STATE (verified, with refs)

### Registry — `scripts/track/track_registry.gd`

- `tracks` (L7-36): 4 layouts — `oval`, `mountain_pass`, `northern_isle`,
  `barcelona_rx` (the last added with the rallycross work). FROZEN; do not grow.
- `pins` (L79-275): **38 entries** — 6 `REGION_ISRAEL` (L82-112) + **32**
  `REGION_WORLD` (L115-274). Every pin already carries a `region` field (L74
  documents it as `REGION_ISRAEL | REGION_WORLD`).
- Region consts (L67-69): only `REGION_ISRAEL`, `REGION_WORLD`,
  `DEFAULT_REGION = REGION_ISRAEL`.
- `regions` (L280-287): only `WORLD` (whole globe) and `ISRAEL`
  (lon 33.0-36.5, lat 28.8-34.2). Comment L277-279 says **"Presentation data
  only: the map contain-fits these corners, so there is no zoom/pan state."**
- Accessors: `get_pin_ids` (L289), `pin_ids_for_region` (L314-319, purely
  label-based), `has_region` (L321), `region_bounds` (L325).

### Map Control — `scripts/ui/track_map.gd`

- `region` setter (L56-62) → `_update_projection()` + redraw; `selected_pin_id`
  setter (L64-69).
- `_update_projection()` (L92-94): `_fit = WorldMapProjection.build_fit(region,
  size, _fallback_pin())`.
- `is_vector_backdrop()` (L107-108): `region != REGION_WORLD` (only Israel uses
  the vector Levant silhouette).
- `visible_pin_ids()` (L114-129): **box containment** — iterates all pins and
  keeps those inside `region_bounds(region)`. Because the WORLD box is the whole
  globe this returns **all 38** pins, while `pin_ids_for_region(WORLD)` returns
  the **32** labelled WORLD — the two disagree today.
- `pin_screen_position()` (L131-135), `hit_test()` (L138-149) — both read `_fit`.
- `select_label_ids()` (L156-181, pure static), `labelled_pin_ids()` (L186-195).
- `_gui_input()` (L197-211): hover + left-click only (no wheel, no drag).
- `_draw()` (L213-229), `_draw_graticule()` (L248-268, step L256 = `30.0 if
  WORLD else 1.0`), `_content_rect()` (L299-305).
- `LABEL_MIN_SEP_PX = 64.0` (L37), `PIN_HIT_RADIUS_PX = 16.0` (L34).

### Menu Control — `scripts/ui/track_select.gd`

- `@onready var region_button: Button = %RegionButton` (L29); bound in `_ready`
  (L66 `pressed`, L69 blip).
- `_build_cards()` (L89-129): `_pin_ids = track_map.visible_pin_ids()` (L95),
  one card per visible pin.
- `select_pin()` (L161-170): if the pin is not in `_pin_ids`, adopt its own
  `region` (L165-166) then select.
- `set_region()` (L181-202) → `_apply_region()` (L207-212, sets
  `region_button.text` at L210) → `_build_cards()`.
- `_on_region_pressed()` (L214-218): two-way WORLD⇄ISRAEL toggle.
- `_on_play_pressed()` (L347-354): **must stay byte-identical**.

### Scene — `scenes/ui/track_select.tscn`

- `load_steps=15` (L1) = 4 ext + 10 sub-resources + 1.
- `MapPanel` (L164-169) `Panel`, child `%TrackMap` (L171-182, anchored full-rect).
- `RightColumn` (L184) → `TitleLabel` (L189) → `%RegionButton` (L196-205, dark
  styles) → `%TrackNameLabel` ... → `%PlayButton` (L299) / `%BackButton` (L314,
  uses `btn_dark*` L323-326).

### Projection / fit (reused untouched)

- `WorldMapProjection.region_corners` (L47-60), `build_fit` (L66-69),
  `project_pin` (L71-73), `lonlat_to_screen` (L75-76), `screen_to_lonlat`
  (L81-82) — all delegate to `MapRoads.compute_fit` / `world_to_screen` /
  `screen_to_world` (L441-469 / L472-476 / L542-548). The fit Dictionary keys are
  `origin`, `scale`, `world_min`, `world_max` (L464-468).

### Tests that pin this behaviour

- `tests/suites/test_race_menu_map.gd`: pins well-formed (L13-33) — **uses
  `has_region(pin.region)`** (L24), so every new region must exist; Israel
  containment invariant (L48-59); `test_israel_fit_zooms_past_the_world_fit`
  (L97-110) — the WORLD loop L108-110 assumes WORLD excludes Israel; menu card
  count == visible (L124-139); region toggle (L153-168, L160 asserts WORLD
  visible == all pins, L165-166 assert ISRAEL == `pin_ids_for_region(ISRAEL)`);
  `test_world_region_has_a_full_calendar` (L228-229, `>= 30`); label tests
  (L233-288).
- `tests/test_track_system.gd`: `contains_exactly(["oval","mountain_pass",
  "northern_isle","barcelona_rx"])` (L5); card test reads
  `visible_pin_ids()` (L28) — registry-relative, **no change needed**.
- `tests/suites/test_race_layout_preview.gd` L178 `select_pin("spa")` — a world
  pin; relies on `select_pin` auto-adopting the pin's region.
- `tests/suites/test_audio_feel_layers.gd` L214-224 (card blip), L194-212 (play
  blip once) — unaffected by added tab/zoom buttons.
- `tests/suites/test_menu_video_background.gd` L24 only lists the scene path.

### Counts (registry-relative, do not hardcode historically)

**38 pins total = 6 Israel + 32 world.** Layout split: `mountain_pass` 15,
`northern_isle` 14, `oval` 6, `barcelona_rx` 3. (Prior plan docs say 36/6/30 —
stale; the 3 rallycross pins + `barcelona_rx` landed after.)

---

## 3. DESIGN DECISIONS

### D1 — Region membership: explicit per-pin `region` field (kept, not derived)

**Chosen: keep the existing per-pin `region` string and retag the 32 world pins to
their continent.** Rejected: deriving membership from lon/lat against the region
boxes at read time.

Why:
- The field is **already the spec of record** (L71-78) and **already what
  `pin_ids_for_region()` reads** (L314-319) — retagging is a pure data edit.
- One-region-per-pin is **deterministic**. AABB containment is ambiguous wherever
  continent boxes overlap (EUROPE/MIDDLE_EAST/AFRICA/ASIA overlap in the eastern
  Mediterranean / Red Sea / Arabia; see D2), and `near`-box pins would flip region
  with small coordinate edits.
- `regions` boxes stay **framing-only** (they keep the L277-279 "presentation data
  only" contract); membership never depends on them, so a box can be widened for
  framing without silently re-homing a circuit.

### D2 — The region set and boxes

`regions` gains seven entries (extra keys are backward-compatible: `region_bounds`
callers only read `min_lon/min_lat/max_lon/max_lat`).

| region id (const)   | `display_name` tab | min_lon | min_lat | max_lon | max_lat | graticule | backdrop |
|---------------------|--------------------|--------:|--------:|--------:|--------:|----------:|----------|
| `REGION_WORLD`      | ALL CIRCUITS       | -180.0  | -90.0   | 180.0   | 90.0    | 30°       | world    |
| `REGION_ISRAEL`     | ISRAEL             | 33.0    | 28.8    | 36.5    | 34.2    | 1°        | vector   |
| `REGION_EUROPE`     | EUROPE             | -25.0   | 34.0    | 45.0    | 72.0    | 10°       | world    |
| `REGION_MIDDLE_EAST`| MIDDLE EAST        | 36.5    | 10.0    | 62.0    | 42.0    | 10°       | world    |
| `REGION_NORTH_AMERICA`| N. AMERICA       | -170.0  | 10.0    | -50.0   | 75.0    | 10°       | world    |
| `REGION_ASIA`       | ASIA               | 60.0    | -12.0   | 180.0   | 75.0    | 10°       | world    |
| `REGION_SOUTH_AMERICA`| S. AMERICA       | -85.0   | -56.0   | -30.0   | 13.0    | 10°       | world    |
| `REGION_AFRICA`     | AFRICA             | -20.0   | -36.0   | 60.0    | 36.0    | 10°       | world    |
| `REGION_OCEANIA`    | OCEANIA            | 110.0   | -50.0   | 180.0   | -10.0   | 10°       | world    |

Insertion order = tab order = `get_region_ids()` order (WORLD first, ISRAEL
second so the default stays Israel). Boxes may overlap in empty ocean/desert;
that is harmless because **membership is not containment** (D1).

`REGION_WORLD` is the **overview tier**: keep the whole-globe box and define
`pin_ids_for_region(REGION_WORLD)` to return **all** pins (a documented
special case in the registry, D3). This preserves the "WORLD shows everything"
behaviour the tests already assert and forces `visible_pin_ids()` to agree with
`pin_ids_for_region()` for every region.

### D3 — Pin → region assignment (every pin, exactly one)

| region | count | pin ids |
|---|---:|---|
| ISRAEL | 6 | `home_sunset_oval`, `home_mountain_pass`, `home_northern_isle`, `haifa_coastal_ring`, `galilee_circuit`, `negev_speedway` |
| EUROPE | 16 | `silverstone`, `spa`, `nurburgring`, `monza`, `monaco`, `imola`, `zandvoort`, `spielberg`, `portimao`, `hungaroring`, `barcelona`, `holjes`, `loheac`, `le_mans`, `brands_hatch`, `hockenheim` |
| MIDDLE_EAST | 3 | `bahrain`, `jeddah`, `abu_dhabi` |
| NORTH_AMERICA | 7 | `watkins_glen`, `laguna_seca`, `cota`, `miami`, `las_vegas`, `daytona`, `indianapolis` |
| ASIA | 3 | `suzuka`, `fuji`, `sepang` |
| SOUTH_AMERICA | 1 | `interlagos` |
| AFRICA | 1 | `kyalami` |
| OCEANIA | 1 | `bathurst` |
| WORLD (overview) | 38 | all of the above (special case, never a pin's stored `region`) |

Total 6+16+3+7+3+1+1+1 = **38**. Notes: `barcelona` is the rallycross pin at
lat 41.57 / lon 2.26 (Spain) → EUROPE; `holjes` at lat 60.05 (Sweden) → EUROPE
(within the lat-72 cap). Every coordinate was checked against its row's box.

### D4 — Zoom mechanism: transform the fit Dictionary (Option Z3)

**Chosen: apply zoom/pan into the fit Dictionary.** Rejected: a `Camera2D`
(does not affect a `Control`'s `draw_*` calls at all), and scaling the map
`Control` (`scale`/`pivot` would scale hit-testing and the backdrop together but
blurs text and fights the container layout).

The fit Dictionary (L464-468) is the **single** transform everything already
reads, so transforming it is a one-line change to `_update_projection()` and
nothing else. New **pure statics** on `TrackMap`:

```
static func zoom_fit(base: Dictionary, factor: float, focus: Vector2) -> Dictionary
    # origin = focus + (base.origin - focus) * factor ; scale = base.scale * factor
    # world_min / world_max unchanged
static func pan_fit(fit: Dictionary, delta: Vector2) -> Dictionary
    # origin += delta
static func clamp_pan(fit: Dictionary, view: Vector2) -> Dictionary
    # per axis: if content <= view, origin = (view - content) / 2  (centre)
    #           else origin = clamp(origin, view - content, 0)     (no gap)
```

`zoom_fit` about `focus` keeps the map point under `focus` fixed by construction:
`new_screen(m) = focus + factor * (old_screen(m) - focus)`.

`_update_projection()` becomes: compute `_base_fit` (unchanged `build_fit` call),
then `_fit = clamp_pan(zoom_fit(_base_fit, _zoom, focus), size)` (focus = size/2
for resize/region rebase; the gesture supplies its own focus). State: `_zoom`
(scalar, `>= MIN_ZOOM`) and `_pan` (Vector2). **Region switch and resize reset
`_zoom = 1.0`, `_pan = Vector2.ZERO`** (see R3).

Because `screen_to_lonlat()` (L81-82) also reads the same fit, a future
click-to-lonlat feature gets zoom for free.

### D5 — Zoom controls, pan, focus target, bounds

- **Mouse wheel** (`_gui_input`, L197-211): `MOUSE_BUTTON_WHEEL_UP` →
  `zoom_by(ZOOM_STEP, event.position)`, `WHEEL_DOWN` → `zoom_by(1/ZOOM_STEP,
  event.position)`. **Focus = cursor** (the natural map idiom).
- **On-screen cluster** `%MapControls` (HBox, bottom-right overlay in `%TrackMap`):
  `%ZoomOutButton`, `%ZoomResetButton`, `%ZoomInButton` → focus = **viewport
  centre**. Reuses the `btn_dark*` sub-resources (no new resource).
- **Keyboard** (`TrackSelect._unhandled_key_input`): `+`/`=`/KP-add → zoom in,
  `-`/KP-subtract → zoom out, `0` → reset, all about the **viewport centre**.
  **Deliberately not arrow-keys**: cards are `FOCUS_ALL` and the `%CardScroll`
  has `follow_focus`, so arrows drive card navigation — avoid the conflict.
- **Pan**: left-drag **or** middle-drag. Track `_press_pos` on button-down; a drag
  past `PAN_DRAG_THRESHOLD_PX = 4` sets `_dragged`; motion while dragged calls
  `_pan += motion.relative`. On left-release with `not _dragged`, run the existing
  `hit_test()` → `pin_clicked` so a **plain click still selects a pin**.
- Bounds: `MIN_ZOOM = 1.0` (the region fit is the floor — never zoom out past the
  framing box), `MAX_ZOOM = 10.0`, `ZOOM_STEP = 1.25`. Clamp in `zoom_by()`.
- Public test seams: `get_zoom()`, `set_zoom(z, focus)`, `zoom_by(factor, focus)`,
  `reset_view()`, `pan_by(delta)`.

### D6 — Label legibility (reuse, do not re-tune)

`select_label_ids()` (L156-181) and `LABEL_MIN_SEP_PX = 64.0` (L37) are reused
**unchanged**. Zoom increases pin screen spacing, so the greedy pass naturally
accepts more labels; `labelled_pin_ids()` (L186-195) already force-includes the
selected + hovered pins. No per-zoom label logic is added.

### D7 — Backdrop by region

`is_vector_backdrop()` (L107-108) changes from `region != REGION_WORLD` to a
**data-driven** read: `regions[region].get("backdrop", "world") == "vector"`
(true only for ISRAEL). All continent tiers use the world raster, framed by their
box. **Open item (needs sign-off):** the SVG is imported at `svg/scale=4.0`
(`assets/ui/world_map_equirectangular.svg.import` L41 → 1440×720); upscaled to a
continent box it looks soft. Proposed: bump `svg/scale` to `8.0` (2880×1440,
~16 MB uncompressed / menu-only texture). Alternative: accept the softness (zoom
then reveals more detail only if the texture has it). **Flagged — do not do this
without the user's/reviewer's OK.**

### D8 — Region picker UX: segmented tab row

Replace `%RegionButton` with a **`%RegionTabs`** container (an `HFlowContainer`,
so it wraps if the window is narrow) at the top of the left `MapPanel`, above the
map. Tabs are built **programmatically** in `TrackSelect._build_region_tabs()`
(mirrors `_build_cards()`), one toggle per `get_region_ids()` using
`display_name`; the active tab highlights. `%RegionButton` is referenced **only**
in `track_select.gd` (L29/L66/L69/L210) and the scene (L196-205) — **no test
references it**, so it is safe to remove. `_on_region_pressed()` (L214-218) is
deleted; `_apply_region()` refreshes the tab highlight instead of
`region_button.text` (L210).

---

## 4. IMPLEMENTATION STEPS

### 4.1 `scripts/track/track_registry.gd`

1. After L68 add the seven continent consts (`REGION_EUROPE`,
   `REGION_MIDDLE_EAST`, `REGION_NORTH_AMERICA`, `REGION_ASIA`,
   `REGION_SOUTH_AMERICA`, `REGION_AFRICA`, `REGION_OCEANIA`). Keep
   `DEFAULT_REGION = REGION_ISRAEL` (L69).
2. Update the `region` doc comment (L71-78) to name the continent set.
3. **Retag** each `"region": REGION_WORLD` in L115-274 to the D3 continent. Do not
   reorder, rename, add or delete any pin — insertion order is card order.
4. Replace `regions` (L280-287) with the nine D2 entries; add
   `"display_name"`, `"graticule_step"`, `"backdrop"` keys. Extend the L277-279
   comment to note membership is the per-pin field, boxes are framing-only.
5. `pin_ids_for_region()` (L314-319): add `if region_id == REGION_WORLD: return
   pins.keys()` at the top, with a comment that WORLD is the all-circuits overview.
6. Add additive `static func get_region_ids() -> Array: return regions.keys()`
   (insertion order = tab order). Optionally `static func region_label(id) ->
   String` reading `display_name`.

### 4.2 `scripts/ui/track_map.gd`

1. New consts: `MIN_ZOOM 1.0`, `MAX_ZOOM 10.0`, `ZOOM_STEP 1.25`,
   `PAN_DRAG_THRESHOLD_PX 4.0`.
2. New state: `_base_fit: Dictionary`, `_zoom: float = 1.0`, `_pan: Vector2`,
   `_dragging: bool`, `_dragged: bool`, `_press_pos: Vector2`.
3. Add the pure statics `zoom_fit`/`pan_fit`/`clamp_pan` (§D4) and public
   `get_zoom`/`set_zoom`/`zoom_by`/`reset_view`/`pan_by`.
4. `_update_projection()` (L92-94): compute `_base_fit`, then
   `_fit = clamp_pan(zoom_fit(_base_fit, _zoom, size * 0.5), size)`; when called
   because of a region/resize, first reset `_zoom`/`_pan`.
5. `visible_pin_ids()` (L114-129): return `TrackRegistry.pin_ids_for_region(region)`
   as `Array[String]` (membership). Keep the doc comment accurate.
6. `is_vector_backdrop()` (L107-108): read the region's `backdrop` key.
7. `_draw_graticule()` (L256): step from the region's `graticule_step` key
   (fallback 10).
8. `_gui_input()` (L197-211): add wheel zoom about `event.position`, middle-drag
   pan, and left press/drag/release with the 4 px threshold (plain click still
   runs `hit_test` → `pin_clicked`).
9. `_ready()` (L76-78): keep `mouse_filter = STOP`; `clip_contents` is set in the
   scene (4.4).

### 4.3 `scripts/ui/track_select.gd`

1. Replace L29 `region_button` with `@onready var region_tabs: Container = %RegionTabs`
   and add `%ZoomInButton`/`%ZoomOutButton`/`%ZoomResetButton` onready refs.
2. `_ready()` (L63-87): call `_build_region_tabs()`; connect the zoom buttons +
   bind their blips; **drop** the `region_button` connect (L66) and blip (L69);
   keep `track_map.region = region` (L70) and the card focus logic.
3. `_apply_region()` (L207-212): replace `region_button.text = ...` with
   `_update_region_tabs()`; call `track_map.reset_view()` after setting the region.
4. Delete `_on_region_pressed()` (L214-218).
5. Add `_build_region_tabs()`, `_update_region_tabs()`, `_on_zoom_in/out/reset()`,
   and `_unhandled_key_input()` (§D5).
6. **Leave `_on_play_pressed()` (L347-354) byte-identical.**

### 4.4 `scenes/ui/track_select.tscn`

1. `MapPanel` (L164-169): add a `VBoxContainer` child; put `%RegionTabs`
   (`HFlowContainer`) first and **reparent** `%TrackMap` (L171-182) into the VBox
   with `size_flags_vertical = 3` and `clip_contents = true`. (`%` unique names
   resolve regardless of path, so tests are unaffected.)
2. Add `%MapControls` (HBoxContainer, anchored bottom-right inside `%TrackMap`,
   `mouse_filter = IGNORE`) containing `%ZoomOutButton`, `%ZoomResetButton`,
   `%ZoomInButton`, `mouse_filter = STOP`, reusing the `btn_dark*` sub-resources.
3. Delete the `RegionButton` node (L196-205). Its styles remain used by
   `%BackButton` (L323-326), so no sub-resource is orphaned.
4. **Keep `load_steps=15`** (L1) — no new ext/sub-resource is introduced.

---

## 5. TEST PLAN

### 5.1 Required edits (registry-relative, never literal-historical)

- `tests/suites/test_race_menu_map.gd`
  - **`test_israel_fit_zooms_past_the_world_fit` L108-110 — MUST change.**
    `pin_ids_for_region(WORLD)` now includes the 6 Israeli pins, so the
    "projects outside the Israel rect" loop would fail on them. Iterate
    `TrackRegistry.get_pin_ids()` and **skip pins whose `region == ISRAEL`**.
  - L160 / L165-166 (region toggle): **unchanged** — WORLD = all 38,
    ISRAEL = `pin_ids_for_region(ISRAEL)` = 6.
  - L228-229 (`test_world_region_has_a_full_calendar >= 30`): **unchanged**
    (38).
  - L13-33 pins well-formed: **unchanged** (needs `has_region` for every new
    region — satisfied by 4.1).
  - L48-59 Israel containment: **unchanged** — it now checks each continent box
    contains its members, which 4.1 guarantees.
- `tests/test_track_system.gd` — **no change** (`contains_exactly` L5 already
  lists `barcelona_rx`; card tests are registry-relative via `visible_pin_ids()`).
- `tests/suites/test_race_layout_preview.gd`, `tests/suites/test_audio_feel_layers.gd`,
  `tests/suites/test_menu_video_background.gd` — **no change**; re-run to confirm
  `select_pin("spa")` still auto-adopts EUROPE and blip counts are unchanged.

### 5.2 New tests (same suite, `test_race_menu_map.gd`)

Data contract:
- `test_every_pin_has_a_continent_region` — each pin's `region` is a real region
  and **not** `REGION_WORLD`.
- `test_pin_regions_partition_the_pin_table` — for every non-WORLD region, its
  box is non-empty; the union of `pin_ids_for_region(r)` over all non-WORLD
  regions equals `get_pin_ids()` with no pin appearing twice.
- `test_region_ids_are_complete` — `get_region_ids()` `contains_exactly` the 9 ids
  including WORLD; each has `min_lon < max_lon` and `min_lat < max_lat`.
- `test_world_region_is_the_full_overview` — `pin_ids_for_region(WORLD).size()
  == get_pin_ids().size()`.

Zoom (pure — no scene):
- `test_zoom_fit_at_factor_one_is_identity` — `zoom_fit(base, 1.0, f)` equals base
  (origin/scale/world_min/world_max).
- `test_zoom_fit_scales_about_focus` — for `f` and `factor 2.0`, the map point
  whose `world_to_screen` was `f` still maps to `f`, and `scale` doubled.
- `test_clamp_pan_centres_when_content_is_small` — content smaller than the view
  is centred on both axes.
- `test_clamp_pan_bounds_when_content_is_large` — a far-panned origin is clamped
  so the content edge does not leave a gap.

Zoom (menu, 2 frames):
- `test_zoom_is_clamped` — repeated `zoom_by(10.0, ...)` stops at `MAX_ZOOM`;
  repeated `zoom_by(0.1, ...)` stops at `MIN_ZOOM`.
- `test_zoom_spreads_pin_positions` — two visible pins' screen distance grows
  after `zoom_by(ZOOM_STEP)`.
- `test_region_switch_resets_view` — after zooming, `set_region(other)` →
  `get_zoom() == 1.0`.
- `test_continent_region_shows_only_its_pins` — `set_region(REGION_EUROPE)` →
  `get_card_count() == pin_ids_for_region(REGION_EUROPE).size()` and every card's
  pin is a EUROPE member.

### 5.3 Gate

Import probe (`--headless --import .`, zero `SCRIPT ERROR`/`Parse Error`) then the
parallel gate `py tools\gdunit_parallel.py -j 4` (or a serial `-c` run of the
touched suites). One Godot process at a time; artifacts on D: only. Target: the
touched suites green; compare the merged summary registry-relative. See
`docs/GDUNIT_GATE.md`.

---

## 6. RISKS / GOTCHAS

- **R1 — `visible_pin_ids()` semantics flip (containment → membership).** Today
  WORLD-visible = 38 while `pin_ids_for_region(WORLD)` = 32. After D3 both are 38.
  Any code/test that assumed the old pair must be re-checked; the only such
  assumption is the WORLD loop in `test_israel_fit_zooms_past_the_world_fit`
  (§5.1).
- **R2 — `select_pin()` region auto-adopt.** L165-166 adopts the pin's `region`;
  with continents this means `select_pin("spa")` now flips to EUROPE (was WORLD).
  This is **desired** and keeps the selection visible; verify
  `test_race_layout_preview.gd` L178 and `test_race_menu_map.gd` L176 still pass
  (both only check scene path + laps, not region).
- **R3 — zoom reset on resize.** `_update_projection()` fires on resize; if it
  resets `_zoom`, a window resize mid-session would drop the zoom. In the shipped
  layout the map panel sizes once at scene load, so this is invisible in practice.
  If preserving zoom across resize is wanted later, re-apply `_zoom` about the
  centre instead of resetting — note this in the code comment.
- **R4 — clip.** Zoomed drawing (backdrop, graticule, labels) can exceed the
  control; `clip_contents = true` on `%TrackMap` (4.4) is **required** so it does
  not spill into the right column.
- **R5 — raster softness at continent zoom.** See D7; the `svg/scale` bump is an
  explicit open decision — do not apply it silently.
- **R6 — `%RegionTabs` input.** If the tab container spans the map's top and has a
  non-IGNORE `mouse_filter`, it eats map hover in that strip. Build it inside the
  `MapPanel` VBox (above the map, not overlapping it) so there is no overlap at
  all.
- **R7 — adding buttons must not change blip counts.**
  `test_audio_feel_layers.gd` L194-212 asserts exactly one blip per play press;
  tab/zoom buttons only blip when *pressed*, so count stays 1. Bind them with the
  existing `_bind_menu_blip()` and re-run that suite.
- **R8 — GDScript typing.** `pin_ids_for_region()` returns an untyped `Array`;
  `visible_pin_ids()` returns `Array[String]` — convert element-wise (`str(...)`)
  as the current code does (L128). GDUnit treats warnings as errors.
- **R9 — `load_steps`.** Only bump if a new resource is added; building tabs
  programmatically and reusing `btn_dark*` for the zoom buttons keeps it at 15.

---

## 7. DO NOT TOUCH

Owned by concurrent work / otherwise out of scope — do **not** edit in this plan:

- **Registry core:** `TrackRegistry.tracks` (L7-36) — frozen membership/order
  (`contains_exactly`); **only** add consts, retag `pins[].region`, grow `regions`,
  and add accessors. Never reorder/rename `pins` (card order) or `tracks` ids.
- **Race semantics:** `TrackSelect._on_play_pressed()` (L347-354) and
  `RaceManager.queue_race()` / `consume_pending_race()` — byte-identical.
- **Projection + fit:** `scripts/ui/world_map_projection.gd` and
  `scripts/ui/map_roads.gd` (`compute_fit`/`world_to_screen`/`screen_to_world`) —
  reused as-is; the zoom transforms the fit Dictionary, it does not change these.
- **Shared map consumers:** `scripts/ui/world_map.gd`, `scripts/ui/minimap.gd`,
  `scripts/ui/pause_menu.gd` (they consume `MapRoads`).
- **Vector tier data:** `scripts/ui/levant_outline.gd` (ISRAEL backdrop, unchanged).
- **Barcelona/rallycross work:** `scripts/track/barcelona_rx*.gd`,
  `scenes/track/barcelona_rx.tscn`, `scripts/track/rx_dressing.gd`,
  `resources/materials/**`.
- **Race HUD / post-race:** `scripts/race/race_ui.gd`, `scenes/ui/hud.tscn`,
  `scripts/race/power_gauge.gd`; speed-trap HUD; cockpit view
  (`scripts/camera/cockpit_camera.gd`, `hood_camera.gd`,
  `scenes/vehicle/interiors/**`).
- **Tooling/infra:** `.opencode/**`, `graphify-out/**`, `addons/**`,
  `tools/gdunit_parallel.py`.
- **Do not** bump `assets/ui/world_map_equirectangular.svg.import` `svg/scale`
  without the D7 sign-off.
