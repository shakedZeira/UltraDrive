# UltraDrive — Race Menu Map Expansion (shipped-layout pins + a full world calendar)

> **Extends** `docs/plans/race_menu_world_map_plan.md` (the map itself already
> shipped 2026-10-16). This plan fixes two playtest complaints against the
> shipped circuit map:
> 1. **"what happened to northern isle speedway track? cant see it"** — the 3
>    shipped layouts (`TrackRegistry.tracks`) only surfaced as a
>    `LAYOUT: <NAME>` token inside a card's meta line; every pin was labelled
>    with an INVENTED circuit name, so the game's own tracks became
>    unrecognisable.
> 2. **"there are a lot of tracks you missed on the map"** — the world tier had
>    only 6 real circuits.
>
> **Written:** 2026-10-16 · **Inputs:** playtest verbatim complaints, user
> decisions (3 shipped layouts get their OWN pins labelled with their exact
> `display_name`; the invented Israeli + world circuits STAY; the world tier
> grows to a ~30-circuit real calendar), `scripts/track/track_registry.gd`,
> `scripts/ui/track_select.gd`, `scripts/ui/track_map.gd`,
> `scripts/ui/world_map_projection.gd`, `scripts/ui/levant_outline.gd`,
> `scenes/ui/track_select.tscn`, `tests/suites/test_race_menu_map.gd`,
> `tests/test_track_system.gd`.
> **Format:** pin-table growth + one pure-function + one `.tscn` property +
> updated/new tests + a status line — **no new scripts required**.

---

## 0. Status block (update this as work lands)

| Item | State |
|---|---|
| Shipped-layout pins (`home_*`, exact `display_name` labels) | **SHIPPED** (pending gate) |
| World calendar grown to 30 real circuits | **SHIPPED** (pending gate) |
| Pure label de-clumping function | **SHIPPED** (pending gate) |
| `%CardScroll.follow_focus` for 36-card keyboard nav | **SHIPPED** (pending gate) |
| Supersedes `race_menu_world_map_plan.md §7` Q1 ("trim or extend the world list") | **EXTEND** (this plan) — Q1 marked RESOLVED in the base plan |

> **Gate:** code + tests landed 2026-10-16; the GDUnit suite run is **pending gate**
> (a separate gate agent owns it). Pin counts asserted registry-relative: 36 total,
> 6 Israel / 30 World, layout split oval 6 / mountain_pass 15 / northern_isle 15.

---

## 1. Current state (verified, with refs)

### Registry (`scripts/track/track_registry.gd`)
- `tracks` (L7-29) is FROZEN: exactly `oval` → "Sunset Oval",
  `mountain_pass` → "Mountain Pass", `northern_isle` → "Northern Isle
  Speedway". Tests assert `contains_exactly([...])` (order+size sensitive) and
  pause-map / GPS / best-lap consumers key off it. **Circuits are added ONLY
  via `pins`.**
- `pins` (L72-145) is the additive many-to-one table, insertion-ordered
  (= card order). Today **9 pins**: 3 invented Israeli (`haifa_coastal_ring`,
  `galilee_circuit`, `negev_speedway`, all `host: ""`) then 6 world
  (`silverstone`, `spa`, `nurburgring`, `monza`, `suzuka`, `interlagos`).
- `regions` (L150-157) framing boxes: `REGION_WORLD` = whole globe
  (`-180..180 / -90..90`); `REGION_ISRAEL` = `lon 33.0..36.5 / lat 28.8..34.2`.
- Accessors: `get_pin_ids`, `get_pin`, `has_pin`, `track_for_pin`,
  `pins_for_track`, `pin_ids_for_region`, `has_region`, `region_bounds`.

### Menu (`scripts/ui/track_select.gd`)
- `_build_cards()` (L84-124) makes one `Button` per **visible** pin
  (`track_map.visible_pin_ids()`, L90), each ≥92 px tall, `FOCUS_ALL`, blips
  wired; card text = badge `CLASS <difficulty>` + pin `label` +
  layout `circuit_type`.
- `select_pin()` (L156-165) is the primary entry; `select_track()` (L169-173)
  is the compat wrapper = **first pin in table order driving that layout**.
- `_update_pin_panel()` (L214-228) writes the name/meta/laps/best-lap; the meta
  line already carries `LAYOUT: <display_name.to_upper()>`, and best lap is
  labelled `BEST (LAYOUT):`.
- `_on_play_pressed()` (L275-282) — unchanged: `RaceManager.queue_race(laps)`
  → `launch_callback(scene_path)`.

### Map (`scripts/ui/track_map.gd`)
- `visible_pin_ids()` (L103-118) = CONTAINMENT in the region box (so `WORLD`
  shows **every** pin; `ISRAEL` shows only those inside the small box).
- `hit_test()` (L127-138) = nearest visible pin within `PIN_HIT_RADIUS_PX`
  (16 px).
- `_draw_pin()` (L209-236) draws the dot for every visible pin but **only draws
  the label when `is_selected`** (L227-236). There is no de-clumping today,
  because 9 pins never needed it.

### Projection / outline
- `world_map_projection.gd` — equirectangular, north-up (`-lat`), reuses
  `MapRoads.compute_fit/world_to_screen`; `build_fit(region, size, fallback)`.
- `levant_outline.gd` — stylized Levant land + Galilee/Dead Sea water rings, all
  `(lon, lat)`; only the ISRAEL tier uses it.

### Scene (`scenes/ui/track_select.tscn`)
- `load_steps=14`. `%CardScroll` (L236-239) is a `ScrollContainer` with
  `horizontal_scroll_mode = 0`, **`follow_focus` UNSET (default false)**;
  `%TrackGrid` (L241-247) is a `GridContainer` `columns = 1`,
  `size_flags_horizontal = 3`. Card `custom_minimum_size.y` = 92 (code).

### Tests that touch this (coupling map)
- `tests/suites/test_race_menu_map.gd` (12 tests): data contract + projection +
  menu. Literals that matter: L160-161 `visible_pin_ids().size() == 9`;
  L165-166 `== 3`; L188 `select_track("northern_isle") → "galilee_circuit"`.
- `tests/test_track_system.gd`: L22-42 `test_track_select_builds_one_card_per_pin`
  (no literal count; `pins[0]` scene); L63-76
  `test_track_select_highlight_updates_on_select` indexes `%TrackGrid` children
  with `get_pin_ids().find(selected)`; L44-61 `select_track("mountain_pass")` /
  `select_track("oval")` launch paths (authoritative, must stay green).
- `tests/suites/test_race_loop.gd` L391-400 `select_track("mountain_pass")` +
  `consume_pending_race() == 2`.
- `tests/suites/test_audio_feel_layers.gd` L194-224: play blip fires once;
  `%TrackGrid` child 0 is a `Button` with the blip wired (no count).
- `tests/suites/test_best_lap_records.gd` L51-59 and
  `tests/suites/test_northern_isle_track.gd` L269-278 key off `tracks` only —
  verified NOT pin-coupled.

---

## 2. Design decisions

### 2.1 The 3 shipped layouts get their own pins — labelled with the EXACT `display_name`

Three new pins are **prepended** to the `pins` table (before the invented
Israeli circuits), so:
- the default framed region (ISRAEL) shows them first, and `_pin_ids[0]` — the
  default selection — is a shipped track;
- `select_track(layout_id)` (the compat wrapper) now resolves to the shipped
  pin, not the invented one (**intended behaviour improvement**, see §2.7 / §4);
- each shipped pin's `label` **equals** `tracks[track_id].display_name`
  verbatim: `"Sunset Oval"`, `"Mountain Pass"`, `"Northern Isle Speedway"`.

`host` stays `""` for the Israeli pins (invented + home) to match the existing
convention; world pins keep their real country in `host`.

### 2.2 FULL pin table (paste-ready) — 36 pins over 3 layouts

Insert into `scripts/track/track_registry.gd`, **replacing** `pins` (L72-145).
`load_steps`/other statics untouched. Order is load-bearing (card order +
default selection).

```gdscript
static var pins: Dictionary = {
	# --- HOME: the 3 shipped layouts, labelled with their registry display_name.
	# --- First so the default selection (pins[0]) is a shipped track.
	"home_sunset_oval": {
		"label": "Sunset Oval",
		"lat": 29.5500, "lon": 34.9500,
		"region": REGION_ISRAEL, "track_id": "oval", "host": "",
	},
	"home_mountain_pass": {
		"label": "Mountain Pass",
		"lat": 33.0500, "lon": 35.7500,
		"region": REGION_ISRAEL, "track_id": "mountain_pass", "host": "",
	},
	"home_northern_isle": {
		"label": "Northern Isle Speedway",
		"lat": 33.1000, "lon": 35.0200,
		"region": REGION_ISRAEL, "track_id": "northern_isle", "host": "",
	},
	# --- Invented Israeli circuits (ids/coords UNCHANGED) ---
	"haifa_coastal_ring": {
		"label": "Haifa Coastal Ring",
		"lat": 32.7940, "lon": 34.9896,
		"region": REGION_ISRAEL, "track_id": "mountain_pass", "host": "",
	},
	"galilee_circuit": {
		"label": "Sea of Galilee Circuit",
		"lat": 32.7167, "lon": 35.6167,
		"region": REGION_ISRAEL, "track_id": "northern_isle", "host": "",
	},
	"negev_speedway": {
		"label": "Negev Speedway",
		"lat": 31.2589, "lon": 34.7997,
		"region": REGION_ISRAEL, "track_id": "oval", "host": "",
	},
	# --- World calendar: 6 existing (unchanged) + 24 new = 30 ---
	"silverstone": {
		"label": "Silverstone Circuit, UK",
		"lat": 52.0786, "lon": -1.0169,
		"region": REGION_WORLD, "track_id": "mountain_pass", "host": "United Kingdom",
	},
	"spa": {
		"label": "Circuit de Spa-Francorchamps, BE",
		"lat": 50.4372, "lon": 5.9714,
		"region": REGION_WORLD, "track_id": "mountain_pass", "host": "Belgium",
	},
	"nurburgring": {
		"label": "Nurburgring Nordschleife, DE",
		"lat": 50.3356, "lon": 6.9475,
		"region": REGION_WORLD, "track_id": "mountain_pass", "host": "Germany",
	},
	"monza": {
		"label": "Autodromo Nazionale Monza, IT",
		"lat": 45.6156, "lon": 9.2811,
		"region": REGION_WORLD, "track_id": "northern_isle", "host": "Italy",
	},
	"suzuka": {
		"label": "Suzuka Circuit, JP",
		"lat": 34.8431, "lon": 136.5407,
		"region": REGION_WORLD, "track_id": "northern_isle", "host": "Japan",
	},
	"interlagos": {
		"label": "Autodromo Jose Carlos Pace, BR",
		"lat": -23.7036, "lon": -46.6997,
		"region": REGION_WORLD, "track_id": "oval", "host": "Brazil",
	},
	"monaco": {
		"label": "Circuit de Monaco, MC",
		"lat": 43.7347, "lon": 7.4206,
		"region": REGION_WORLD, "track_id": "mountain_pass", "host": "Monaco",
	},
	"imola": {
		"label": "Autodromo Enzo e Dino Ferrari, IT",
		"lat": 44.3439, "lon": 11.7167,
		"region": REGION_WORLD, "track_id": "mountain_pass", "host": "Italy",
	},
	"zandvoort": {
		"label": "Circuit Zandvoort, NL",
		"lat": 52.3888, "lon": 4.5409,
		"region": REGION_WORLD, "track_id": "mountain_pass", "host": "Netherlands",
	},
	"spielberg": {
		"label": "Red Bull Ring, AT",
		"lat": 47.2197, "lon": 14.7647,
		"region": REGION_WORLD, "track_id": "mountain_pass", "host": "Austria",
	},
	"portimao": {
		"label": "Autodromo Internacional do Algarve, PT",
		"lat": 37.2272, "lon": -8.6272,
		"region": REGION_WORLD, "track_id": "mountain_pass", "host": "Portugal",
	},
	"watkins_glen": {
		"label": "Watkins Glen International, US",
		"lat": 42.3369, "lon": -76.9272,
		"region": REGION_WORLD, "track_id": "mountain_pass", "host": "United States",
	},
	"laguna_seca": {
		"label": "WeatherTech Raceway Laguna Seca, US",
		"lat": 36.5844, "lon": -121.7533,
		"region": REGION_WORLD, "track_id": "mountain_pass", "host": "United States",
	},
	"bathurst": {
		"label": "Mount Panorama, AU",
		"lat": -33.4489, "lon": 149.5661,
		"region": REGION_WORLD, "track_id": "mountain_pass", "host": "Australia",
	},
	"kyalami": {
		"label": "Kyalami Grand Prix Circuit, ZA",
		"lat": -25.9894, "lon": 28.0669,
		"region": REGION_WORLD, "track_id": "mountain_pass", "host": "South Africa",
	},
	"hungaroring": {
		"label": "Hungaroring, HU",
		"lat": 47.5789, "lon": 19.2486,
		"region": REGION_WORLD, "track_id": "mountain_pass", "host": "Hungary",
	},
	"bahrain": {
		"label": "Bahrain International Circuit, BH",
		"lat": 26.0325, "lon": 50.5106,
		"region": REGION_WORLD, "track_id": "northern_isle", "host": "Bahrain",
	},
	"jeddah": {
		"label": "Jeddah Corniche Circuit, SA",
		"lat": 21.6319, "lon": 39.1044,
		"region": REGION_WORLD, "track_id": "northern_isle", "host": "Saudi Arabia",
	},
	"abu_dhabi": {
		"label": "Yas Marina Circuit, AE",
		"lat": 24.4672, "lon": 54.6031,
		"region": REGION_WORLD, "track_id": "northern_isle", "host": "United Arab Emirates",
	},
	"cota": {
		"label": "Circuit of the Americas, US",
		"lat": 30.1328, "lon": -97.6411,
		"region": REGION_WORLD, "track_id": "northern_isle", "host": "United States",
	},
	"miami": {
		"label": "Miami International Autodrome, US",
		"lat": 25.9581, "lon": -80.2389,
		"region": REGION_WORLD, "track_id": "northern_isle", "host": "United States",
	},
	"barcelona": {
		"label": "Circuit de Barcelona-Catalunya, ES",
		"lat": 41.5700, "lon": 2.2611,
		"region": REGION_WORLD, "track_id": "northern_isle", "host": "Spain",
	},
	"le_mans": {
		"label": "Circuit de la Sarthe (Le Mans), FR",
		"lat": 47.9500, "lon": 0.2086,
		"region": REGION_WORLD, "track_id": "northern_isle", "host": "France",
	},
	"brands_hatch": {
		"label": "Brands Hatch, UK",
		"lat": 51.3597, "lon": 0.2628,
		"region": REGION_WORLD, "track_id": "northern_isle", "host": "United Kingdom",
	},
	"fuji": {
		"label": "Fuji Speedway, JP",
		"lat": 35.3717, "lon": 138.9267,
		"region": REGION_WORLD, "track_id": "northern_isle", "host": "Japan",
	},
	"sepang": {
		"label": "Sepang International Circuit, MY",
		"lat": 2.7608, "lon": 101.7375,
		"region": REGION_WORLD, "track_id": "northern_isle", "host": "Malaysia",
	},
	"hockenheim": {
		"label": "Hockenheimring, DE",
		"lat": 49.3278, "lon": 8.5658,
		"region": REGION_WORLD, "track_id": "northern_isle", "host": "Germany",
	},
	"las_vegas": {
		"label": "Las Vegas Motor Speedway, US",
		"lat": 36.2711, "lon": -115.0114,
		"region": REGION_WORLD, "track_id": "oval", "host": "United States",
	},
	"daytona": {
		"label": "Daytona International Speedway, US",
		"lat": 29.1856, "lon": -81.0700,
		"region": REGION_WORLD, "track_id": "oval", "host": "United States",
	},
	"indianapolis": {
		"label": "Indianapolis Motor Speedway, US",
		"lat": 39.7950, "lon": -86.2347,
		"region": REGION_WORLD, "track_id": "oval", "host": "United States",
	},
}
```

**Coordinates** are well-known published circuit lat/lon; a few tenths of a
degree of error is deliberately acceptable (placement, not survey accuracy —
same rule as the shipped plan §5.11). Tests only ever assert range/containment,
never exact values.

**Track-id balance rule (stated):**
- `oval` ← ovals / superspeedways / tri-ovals (only 3 real ones exist in a
  coherent calendar, plus Interlagos kept as-is).
- `mountain_pass` ← circuits defined by elevation change, twistiness, or
  street/mountain character.
- `northern_isle` ← flat permanent road courses / parkland / desert-permanent
  circuits.

Resulting distribution (**36 pins**):

| layout | Israel | World | TOTAL | share |
|---|---|---|---|---|
| `oval` | 2 (`home_sunset_oval`, `negev_speedway`) | 4 (`interlagos`, `las_vegas`, `daytona`, `indianapolis`) | **6** | 17% |
| `mountain_pass` | 2 (`home_mountain_pass`, `haifa_coastal_ring`) | 13 | **15** | 42% |
| `northern_isle` | 2 (`home_northern_isle`, `galilee_circuit`) | 13 | **15** | 42% |

Every layout ≥ 3 pins and no layout > 50% — the `oval` bucket is the thinnest
because the real world simply has few ovals; that skew is deliberate and is
what the balance test encodes (a floor + a share cap), not an exact third each.

### 2.3 Israel region geometry — NO box change needed

`regions[REGION_ISRAEL]` is already `lon 33.0..36.5 / lat 28.8..34.2`. All six
Israeli pins above lie inside it:

| pin | lat | lon | in box |
|---|---|---|---|
| home_sunset_oval | 29.55 | 34.95 | ✅ |
| home_mountain_pass | 33.05 | 35.75 | ✅ |
| home_northern_isle | 33.10 | 35.02 | ✅ |
| haifa_coastal_ring | 32.7940 | 34.9896 | ✅ |
| galilee_circuit | 32.7167 | 35.6167 | ✅ |
| negev_speedway | 31.2589 | 34.7997 | ✅ |

The existing test `test_default_region_is_israel_and_holds_at_least_three_pins`
asserts **every** pin sits in its region box, so no new box literal is needed.
Every world pin is far outside the Israel box (the nearest, `jeddah` at
lon 39.10, is well east of 36.5), so `test_israel_fit_zooms_past_the_world_fit`
(greater Israel scale + all world pins project OUTSIDE the Israel rect) stays
true without edits.

### 2.4 Label de-clumping — a PURE, deterministic, unit-testable function

36 pins cannot all carry labels. Add to `TrackMap`:

- `const LABEL_MIN_SEP_PX: float = 64.0` (screen-space; a 13 px label is
  ~40-90 px wide, so 64 px keeps most pairs legible — tunable).
- **Static pure function** (no node/time/state):

```gdscript
## Pure label de-clumping. `anchors` is an ordered Array (pin-table order) of
## {"id": String, "pos": Vector2}. `priority_ids` are always labelled. Accepts
## every priority anchor first, then greedily accepts a remaining anchor iff its
## position is >= min_sep_px from ALL already-accepted anchors. Deterministic:
## depends only on (anchors order, min_sep_px, priority_ids).
static func select_label_ids(anchors: Array, min_sep_px: float, priority_ids: PackedStringArray) -> Array[String]:
	var accepted_ids: Array[String] = []
	var accepted_pos: Array[Vector2] = []
	for want: String in priority_ids:
		for i in anchors.size():
			var d: Dictionary = anchors[i]
			if str(d.get("id", "")) == want:
				accepted_ids.append(want)
				accepted_pos.append(d.get("pos", Vector2.ZERO))
				break
	for i in anchors.size():
		var d: Dictionary = anchors[i]
		var id: String = str(d.get("id", ""))
		if accepted_ids.has(id):
			continue
		var p: Vector2 = d.get("pos", Vector2.ZERO)
		var ok: bool = true
		for q: Vector2 in accepted_pos:
			if p.distance_to(q) < min_sep_px:
				ok = false
				break
		if ok:
			accepted_ids.append(id)
			accepted_pos.append(p)
	return accepted_ids
```

- **Instance helper** (feeds the draw pass; scene-level tests can read it):

```gdscript
func labelled_pin_ids() -> Array[String]:
	var anchors: Array = []
	for pin_id: String in visible_pin_ids():
		anchors.append({"id": pin_id, "pos": pin_screen_position(pin_id)})
	var priority := PackedStringArray()
	if selected_pin_id != "":
		priority.append(selected_pin_id)
	if _hovered_pin_id != "" and _hovered_pin_id != selected_pin_id:
		priority.append(_hovered_pin_id)
	return select_label_ids(anchors, LABEL_MIN_SEP_PX, priority)
```

- **Rendering rule:** the DOT is always drawn for every visible pin (unchanged);
  the LABEL is drawn **only** if the pin is in `labelled_pin_ids()`. Refactor
  `_draw_pin(pin_id)` → `_draw_pin(pin_id, labelled: bool)`, compute the set
  once in `_draw()` (as a `Dictionary` set for O(1) membership), keep the
  selected/hovered fill + halo exactly as today, and replace the
  `if is_selected:` label block with `if labelled:`.
- **ISRAEL tier (6 pins in a ~3.5° × 5.4° box):** at ~1000×640 px that is
  ~110 px/degree, so pins sit 30-90 px apart. Expect 4-6 labels; the
  selected/hovered pin is ALWAYS named. The card list + info panel name all 6
  regardless, so the shipped tracks are never unnamed on screen.
- **WORLD tier (36 pins on the whole globe):** ~2.8 px/degree of longitude →
  Europe's ~20 pins collapse into tens of px. Expect a sparse label set (~8-12,
  always including the selected/hovered); the DOT + the card list + the info
  panel carry the rest. Collision-proofing is by construction (accepted anchors
  are pairwise ≥ `min_sep_px`).

### 2.5 Card list at 36 entries — one `.tscn` property

`%CardScroll` already scrolls vertically (`size_flags_vertical = 3`; vertical
scroll mode default **auto**; horizontal disabled). 36 cards × 92 px + 35 × 10 px
separation ≈ 3.9 k px of scrollable content — the container handles it with no
layout restructure. **One required `.tscn` edit:** keyboard/controller nav to a
card below the fold will NOT auto-scroll while `follow_focus` is false, so add
`follow_focus = true` to `%CardScroll`:

```tscn
[node name="CardScroll" type="ScrollContainer" parent="Margin/Row/RightColumn"]
layout_mode = 2
size_flags_vertical = 3
horizontal_scroll_mode = 0
follow_focus = true
```

**`load_steps` arithmetic:** this is a property on an EXISTING node — no new
`ext_resource`/`sub_resource` — so the header stays `load_steps=14` (resources
+ 1). Do not renumber it. Font sizes, column count (1), grid flags and card
height stay as-is (see the `follow_focus` note in test `test_audio_feel_layers`:
`%TrackGrid` child 0 must remain a `Button`).

### 2.6 Selection / records semantics — keep, but state it

- **Region toggle keeps "never selected-but-hidden"** (unchanged): `set_region`
  re-selects the same pin when still visible, else `_pin_ids[0]`.
- **Best laps stay keyed per LAYOUT** (unchanged): `race_ui._resolve_track_id()`
  resolves by SCENE PATH, so clicking "Monza" and "Suzuka" shows the same
  `northern_isle` record. The card already says `LAYOUT: NORTHERN ISLE` in the
  meta line and `BEST (LAYOUT):`, so the sharing is explicit and unambiguous —
  **keep the wording as-is; add nothing.** (The plan considered appending the
  layout name to the best-lap line; it is redundant with the meta line, so it is
  rejected as noise.)
- **`select_track(track_id)` now resolves to a shipped pin** because `home_*`
  pins precede `galilee_circuit` etc. in the table. This is the intended
  improvement: opening the race menu from a "race this layout" caller now lands
  on the pin whose LABEL is the layout's own name.

### 2.7 Touch-point summary (files/functions)

| File | Change |
|---|---|
| `scripts/track/track_registry.gd` | replace `pins` table ($2.2). Nothing else. |
| `scripts/ui/track_map.gd` | add `LABEL_MIN_SEP_PX`, `select_label_ids()`, `labelled_pin_ids()`; refactor `_draw_pin()` for dot-vs-label. |
| `scenes/ui/track_select.tscn` | `follow_focus = true` on `%CardScroll`. |
| `tests/suites/test_race_menu_map.gd` | update 3 assertions; add 7 tests (§4). |
| `docs/plans/race_menu_world_map_plan.md` | status note pointing here (Q1 resolved). |
| `docs/plans/race_menu_map_expansion_plan.md` | this file (status block). |

`scripts/ui/track_select.gd`, `world_map_projection.gd`, `levant_outline.gd`
need **no code change** (they already read `pins` generically). The card meta
line already prints the layout name for shipped pins too
(`LAYOUT: SUNSET OVAL`), which is exactly the recognition fix the user asked
for.

---

## 3. Implementation steps

Ordered; each phase ends with a gate. Never run two Godot processes at once;
read `docs/GDUNIT_GATE.md` before any run.

**Phase 1 — data (registry).**
1. Replace `pins` in `scripts/track/track_registry.gd` with the §2.2 table.
   Touch nothing else in the file (`tracks`, `regions`, accessors all stand).

**Phase 2 — map de-clumping.**
2. `scripts/ui/track_map.gd`: add `LABEL_MIN_SEP_PX` +
   `select_label_ids()` + `labelled_pin_ids()`; update the class doc comment
   (it currently says "one clickable pin per TrackRegistry pin" and that labels
   draw only when selected).
3. Refactor `_draw_pin(pin_id)` → `_draw_pin(pin_id, labelled: bool)`; in
   `_draw()`, build `var labelled := labelled_pin_ids()` once, convert to a
   `Dictionary` set, and pass `set.has(pin_id)`. Keep the pulse halo, outline
   and fill logic verbatim.

**Phase 3 — scene.**
4. Add `follow_focus = true` to `%CardScroll`; leave `load_steps=14`.

**Phase 4 — tests.** See §4. Update the 3 existing assertions, add the new
tests.

**Phase 5 — docs.**
5. Add a status line to `race_menu_world_map_plan.md §7` (Q1 → resolved by this
   plan) and set this plan's §0 status table to SHIPPED with the gate numbers.
   `docs/ROADMAP.md` has **no** circuit-map line today (verified), so no ROADMAP
   edit is required; optionally refresh
   `docs/research/ultradrive_features.md` L18 (`Track Select (two maps)` is
   stale) — cosmetic, same PR.

**Verification gates (each ONCE, never re-run "to confirm"):**
- `--headless --import .` filtered for `SCRIPT ERROR`/`Parse Error` (expect
  zero), then the GDUnit `-s` run — inline or one background sub-agent per
  `AGENTS.md`.
- Targeted suites first: `test_race_menu_map`, `test_track_system`,
  `test_race_loop`, `test_audio_feel_layers`, `test_best_lap_records`,
  `test_northern_isle_track`.
- Then `py tools\gdunit_parallel.py -j 4` (background), read
  `reports/parallel/summary.json`.
- `graphify update .` after the code change (GDScript is not in the graph; the
  plan doc is).

---

## 4. Tests

### Existing assertions that CHANGE (enumerated exactly)

`tests/suites/test_race_menu_map.gd`:
1. **L160-161** `test_region_toggle_switches_pins_and_backdrop` —
   `visible_pin_ids().size()` and `get_card_count()` change **9 → 36**. Express
   it registry-relative, not as a literal:
   ```gdscript
   assert_that(scene.track_map.visible_pin_ids().size()).is_equal(
       TrackRegistry.get_pin_ids().size())   # WORLD box = whole globe
   assert_that(scene.get_card_count()).is_equal(TrackRegistry.get_pin_ids().size())
   ```
2. **L165-166** same test, after `set_region(ISRAEL)` — **3 → 6**:
   ```gdscript
   assert_that(scene.track_map.visible_pin_ids().size()).is_equal(
       TrackRegistry.pin_ids_for_region(ISRAEL).size())
   assert_that(scene.get_card_count()).is_equal(
       TrackRegistry.pin_ids_for_region(ISRAEL).size())
   ```
3. **L188** `test_legacy_select_track_still_resolves_a_pin` — expected pin
   changes `"galilee_circuit"` → **`"home_northern_isle"`** (the shipped pin now
   precedes it). The scene-path assertion on L189 is unchanged. Add a comment
   recording that this is the intended improvement (records still key per
   layout).

`tests/test_track_system.gd`: **no assertion changes** — verify only. Justify:
- L22-42 `test_track_select_builds_one_card_per_pin`: `pins[0]` is now
  `home_sunset_oval` → `oval` scene, and the ready-selection is also
  `home_sunset_oval`, so `get_selected_scene_path() ==
  get_scene_path(track_for_pin(pins[0]))` still holds.
- L63-76 `test_track_select_highlight_updates_on_select`: `select_track(
  "mountain_pass")` → `home_mountain_pass` at pin-table index **1**; the ISRAEL
  card list is the first 6 pins in order, so `cards[1]` still matches the
  selected pin (index alignment holds because every pin before it is
  Israel-visible). Add a comment that this alignment depends on the `home_*`
  pins being the first table entries.
- L44-61 play/back launch paths are layout-based — unchanged.

`tests/suites/test_race_loop.gd` L391-400, `test_audio_feel_layers.gd`
L194-224, `test_best_lap_records.gd` L51-59, `test_northern_isle_track.gd`
L269-278: **unchanged** — verified not pin-table-order-coupled (race_loop uses
`select_track`, which still resolves `mountain_pass`).

### NEW tests (append to `tests/suites/test_race_menu_map.gd`)

Data contract (no scene):
4. `test_shipped_layouts_have_a_pin_labelled_with_their_display_name` — for
   each `track_id` in `get_track_ids()`, some pin with that `track_id` has
   `label == get_track(track_id).display_name` (the complaint-1 lock).
5. `test_shipped_layout_pins_are_the_first_table_entries` — `get_pin_ids()`
   `[0..2]` all have `region == ISRAEL` and `track_id` in `get_track_ids()`
   (so the default selection is a shipped track).
6. `test_layout_distribution_is_balanced` — every layout has ≥ 3 pins AND
   `float(n)/float(total) <= 0.5` for each.
7. `test_world_region_has_a_full_calendar` —
   `pin_ids_for_region(WORLD).size() >= 30`.
8. `test_every_pin_has_a_distinct_id_and_label_is_nonempty` — already covered
   by `test_pins_are_well_formed...`; no new test needed (note it).

Label de-clumping (pure, no scene):
9. `test_select_label_ids_always_keeps_priority_pins` — two anchors 10 px apart;
   priority `["b"]` → result contains `"b"`, size 1.
10. `test_select_label_ids_drops_anchors_within_min_separation` — three anchors
    chained < min_sep (e.g. 0/30/60 px, min_sep 64) → only the first accepted.
11. `test_select_label_ids_accepts_well_spaced_anchors` — anchors 100 px apart,
    min_sep 64 → all accepted (order preserved).
12. `test_select_label_ids_is_deterministic` — same input twice → equal arrays.
13. `test_world_tier_labels_never_collide` — build anchors from the real WORLD
    projection (`scene_runner`, size set explicitly), call `labelled_pin_ids()`,
    assert every pair of accepted anchors is ≥ `LABEL_MIN_SEP_PX` apart (the
    invariant, on real data).

Menu (scene, `scene_runner` + `simulate_frames(2)`):
14. `test_default_selection_drives_a_shipped_layout` —
    `get_track_ids()` contains `scene.get_selected_track_id()`, and the first
    card's text contains `"Sunset Oval"`.
15. `test_shipped_pins_are_reachable` — `select_pin("home_northern_isle")` →
    `get_selected_scene_path() == get_scene_path("northern_isle")`; same for
    `home_mountain_pass`/`home_sunset_oval`.

### Conventions to honour
`assert_that(...).is_equal`; gdUnit treats warnings as ERRORS → full type
annotations, never `var x := some_variant_returning_call()`; vector
`is_equal_approx` needs a SAME-TYPE epsilon arg; scene suites need
`await runner.simulate_frames(2)`; any test that queues a race must end with
`RaceManager.consume_pending_race()`.

---

## 5. Risks / gotchas

1. **`tracks` must stay frozen.** Adding a layout (to make e.g. "Monza" a real
   layout) would break `test_registry_contains_expected_tracks` and mis-key best
   laps (`race_ui._resolve_track_id` first-match). This plan adds circuits ONLY
   via `pins`.
2. **Insertion order is load-bearing.** `pins` order = card order = default
   selection = `select_track` first-match. The `home_*` pins MUST be the first
   three entries or the default-selection + legacy-select tests flip.
3. **Europe label density.** At world scale, ~20 European pins are within tens
   of px; labels drop by design and some pins are within the 16 px hit radius
   (`hit_test` returns the nearest, ties by table order). The card list remains
   the guaranteed selectable path for every circuit — state this in the header
   comment so it is not "fixed" by shrinking the hit radius.
4. **`follow_focus` is required, not cosmetic.** Without it, controller
   navigation to card 20 is invisible. It is a property edit on an existing
   node → `load_steps` stays 14.
5. **`.tscn` `load_steps` arithmetic.** Only add `load_steps` if a NEW
   `ext_resource`/`sub_resource` is added (none here). Header must equal
   resources + 1.
6. **Pure-function typing.** `select_label_ids` must use explicit types
   (`var d: Dictionary = anchors[i]`, `var p: Vector2 = d.get(...)`) — a
   `:=` from `Dictionary.get()` infers Variant and gdUnit fails the script.
7. **Headless draw.** `_draw()` never runs under gdUnit; `labelled_pin_ids()`
   must work off `_update_projection()` (called from `_ready`/resize), and
   tests must set `map.size` explicitly (project §5.6-5.7).
8. **`test_israel_fit_zooms_past_the_world_fit`** requires every WORLD pin to
   project OUTSIDE the Israel rect. All 30 world pins are outside the
   `33..36.5 / 28.8..34.2` box — keep any future "near-East" pin outside it, or
   update that test deliberately.
9. **54-enumeration drift** — `docs/research/ultradrive_features.md` L18 still
   says "Track Select (two maps)"; L115 is current. Cosmetic; fix in the same
   PR.
10. **Blip-count test.** Adding cards must not add a `_menu_blip` at ready;
    `_ready` still blips only via `grab_focus()` on card 0, and
    `test_audio_feel_layers` installs its spy AFTER `_ready` (unchanged
    behaviour). Re-run that suite after touching card construction.

---

## 6. Do NOT touch

- `scripts/track/track_registry.gd :: tracks` and
  `get_track_ids/get_track/get_scene_path/has_track` — additive `pins` only.
- **Race semantics**: `RaceManager` (`autoload/race_manager.gd`, no signature
  change), `scripts/race/race_ui.gd` (`_resolve_track_id`, HUD start, record
  submission), `scripts/race/checkpoint.gd`, `lap_counter.gd`, `tachometer.gd`.
- **Save code**: `autoload/save_manager.gd`, `scripts/race/best_lap_records.gd`
  (read-only use; no new keys, no schema change). Records remain per-layout.
- `scripts/ui/map_roads.gd` (reuse `compute_fit`/`world_to_screen`; no lat/lon
  concepts added here) and the open-world maps
  `scripts/ui/world_map.gd` / `minimap.gd` / `pause_menu.gd`.
- `scripts/ui/world_map_projection.gd`, `scripts/ui/levant_outline.gd`,
  `scripts/ui/track_select.gd` (no change needed — verify only).
- **Other workstreams**: cars (`scripts/vehicle/**`, `assets/cars/**`,
  `resources/cars/**`, `scripts/test_circuit.gd`), HUD (`scripts/race/race_ui.gd`
  + `scenes/ui/hud.tscn`), garage (`scripts/career/garage.gd`,
  `scripts/ui/garage_ui.gd`, `scenes/ui/garage.tscn`,
  `scripts/career/car_brands.gd`), main menu (`scripts/ui/main_menu.gd`,
  `scenes/ui/main_menu.tscn`).
- `scenes/test/test_track.tscn`, `scenes/track/mountain_pass.tscn`,
  `scenes/track/northern_isle.tscn` and any track geometry — layouts are used
  as-is (many-to-one).
- `tools/gdunit_parallel.py`, `tools/menu_autopilot.gd`, `addons/**`,
  `graphify-out/**` (only the hook rebuilds it).

---

## 7. Open questions (decide while implementing)

- Exact `LABEL_MIN_SEP_PX`: 64 is the start; tune in-editor at 1920×1080 and
  lock whatever reads best (test uses the constant, so tuning does not break
  tests).
- Should the world tier visually distinguish the 3 shipped-layout pins (a
  "home" ring)? Cheap; still a nice-to-have (inherited from the base plan §7).
- Optional: shrink card `custom_minimum_size.y` (92 → ~78) to show more rows per
  screen — a `track_select.gd` one-liner, deliberately NOT included here to keep
  the diff minimal.
