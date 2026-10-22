# Free-roam speed-trap HUD: screen flash + crossing banner — implementation plan

Status: PLANNED (2026-10-17). Scope: the **free-roam open world only**
(`scenes/world/open_world_root.tscn`). Godot 4.7.2, project root = res://.

User request: *"when I cross a speed trap in free roam, flash the screen and show
a bottom banner with the speed I crossed at and my best"*.

---

## 1. Goal + acceptance criteria

Add a **presentation-only** reward loop for speed traps in free roam: driving
through a trap gantry flashes the screen and pops a bottom banner reading the
crossing speed and the personal best for that trap. Nothing about money, claims
or the trap mesh changes.

Acceptance criteria (all must hold):

1. **Crossing the gantry at any speed** fires once per pass — the crossing rule
   is *radius-only* (`Collectibles.xz_distance <= Collectibles.claim_radius_of(poi)`),
   deliberately **independent of the money gate** `Collectibles.can_claim`
   (`collectibles.gd:340`) and of whether the trap was already claimed. A trap
   crossed at 40 km/h flashes just like one crossed at 220 km/h (the speed
   target only governs the *payout*, not "did I cross").
2. A single drive-through emits exactly ONE crossing; the banner does not
   flicker or re-fire while the car stays inside the gate radius.
3. Screen flash: a full-screen tint that fades in fast and out slower, then
   becomes fully invisible. No permanent overlay, no node leak, no stacking on a
   second crossing.
4. Bottom banner: one reusable panel, centred at the bottom, showing
   `SPEED TRAP — <n> km/h` plus the best (`· NEW BEST!` on an improvement, else
   `· BEST <n> km/h`), auto-hiding after its hold time.
5. Personal best per trap id is recorded monotonically (never decreases),
   survives a save/reload, and is **independent of the claim ledger** (a
   trap already claimed in an old save still accumulates a best).
6. **Free-roam gating:** the whole feature is inert during a race — no crossing
   emitted, no flash, no banner, no save write. It also never runs on circuit
   scenes (the nodes only exist in the open-world root).
7. **Headless-deterministic:** flash/banner timing and best-logic are pure
   functions the GDUnit suite can assert without a frame loop.
8. No new autoload, no edit to `hud.tscn` / `race_ui.gd` (both are being changed
   by a concurrent agent — see §7), no change to `collectibles.gd` or
   `collectible_field.gd` behaviour.

Non-goals: money/XP changes, new trap types, world-map/POI changes, race-mode
handling, changing the trap meshes or the existing claim flash
(`speed_trap_visuals.gd:374 mark_claimed`).

---

## 2. Current state (verified, file:line)

### How a speed trap is detected today — a ONE-TIME CLAIM, not a crossing

- `CollectibleField` (`scripts/world/collectible_field.gd`, `extends Node`) is
  the only runtime trigger. `_physics_process():74` → `simulate_step():83` →
  `claim_at():98` → `Collectibles.can_claim():340`. `claim_at` iterates
  `_pending` (UNCLAIMED entries only, `collectible_field.gd:39,66`) and on
  success `_award():112` removes the entry (`claim_at` line 105) and persists.
  **Consequence:** once a trap pays, it is gone from `_pending` forever and the
  signal never fires again for that id — so the existing path cannot drive a
  per-pass HUD.
- `can_claim():340-346` returns true only when in radius AND
  `speed_kmh >= Collectibles.speed_target_of(poi)` (`collectibles.gd:302`).
  That speed target is a **payout** condition (tier table
  `TIER_SPEED_TRAP_KMH`, `collectibles.gd:118`), not a crossing condition.
- The emitted signal carries **no speed**:
  `signal collectible_claimed(collectible_id: String, reward: int)`
  (`collectible_field.gd:23`). Speed exists only transiently in
  `_player_speed_kmh():126-133` (reads `current_speed_kmh`, else
  `get_drive_info()["speed_kmh"]`).
- **There is NO personal-best store anywhere** for traps. No
  `speed_traps`/`SpeedTrapRecords`/`SpeedTrapCrossing`/`SpeedTrapHUD` symbol
  exists in the tree.

### The trap data the feature must read

- Traps are authored as collectible POIs: `Collectibles.place_data(defs):144`
  builds `out[id]` for every family; traps get ids `speedtrap_<n>`
  (`ID_PREFIX`, `collectibles.gd:48-50`), a world `"position"`, `"kind"
  == KIND_SPEED_TRAP` (`:43`), and `"extra".claim_radius` (`_collectible():211`,
  `SPEED_TRAP_OFFSET_M == 0.0` at `:96` so a trap sits exactly on the road
  vertex). `CLAIM_RADIUS[KIND_SPEED_TRAP] == 18.0` (`:128-130`).
- Those POIs are merged into `POIRegistry` (`poi_registry.gd:54 get_poi_ids`,
  `:58 get_poi`) under `CATEGORY_COLLECTIBLES` (`:86 category_of`). This is the
  shared published set the pause map dots, the gate mesh and the claim trigger
  all read, so a new reader **cannot disagree** with them.
- `Collectibles.ids_of_kind(source, kind):274`,
  `Collectibles.kind_of_id(id):254`, `Collectibles.is_collectible_id(id):260`,
  `Collectibles.claim_radius_of(poi):308`, `Collectibles.xz_distance(a,b):317`,
  `const DEFAULT_SLOT := 0` (`:36`).
- The gate mesh reader precedent: `speed_trap_visuals.gd:175` iterates
  `Collectibles.ids_of_kind(placed, Collectibles.KIND_SPEED_TRAP)`. Its class
  lives in group `speed_trap_visuals` (`:42`) and is bootstrapped by
  `world_driver.gd:289 _bootstrap_speed_trap_visuals()`.

### Free-roam gate

- `RaceManager.is_race_active: bool` (`autoload/race_manager.gd:22`), set true in
  `start_race():146` and false in `finish_race():420`. This is the canonical
  race-vs-free-roam flag.

### Precedents to copy

- **Driven-tick animation (headless-deterministic):**
  `SpeedTrapVisuals.tick(delta) -> bool` (`speed_trap_visuals.gd:405`), with the
  statics `FLASH_SECONDS := 1.5` / `FLASH_COLOR` (`:91-92`). It switches
  `set_process(false)` itself when idle (`:407`), and `:403-404` documents
  exactly why: *"Processing is switched off here rather than in `_process` so a
  driven `tick()` leaves the node in exactly the state a real frame would have
  left it in."* The new HUD follows this convention, NOT a `Tween`/`SceneTreeTimer`
  (which cannot be advanced deterministically headless).
- **Transient full-screen overlay:** `photo_mode.gd` `FILTER_LAYER := 50:33`,
  `_ensure_overlay():260` builds one lazily-reused `ColorRect`, `flash_message():295`
  drives a `Label`; `_free_overlay():276` is the teardown idiom.
- **Best-ledger persistence via the generic slot save:**
  `event_session.gd` `SAVE_KEY := "events":21`, `_record_best():221`
  (monotonic `if metric > prev`), `save_bests():234` does a read-modify-write
  `data[SAVE_KEY] = _bests; SaveManager.save_game(slot, data)` preserving every
  other field, `_load_bests():241` tolerates a missing/non-dict key.
- **Pause-only writes:** `CollectibleField._on_game_paused():135` and
  `WorldDriver._on_game_paused():194` both write through
  `GameState.game_paused` (signal at `autoload/game_state.gd:7`, emitted in
  `pause_game():162`).
- **Bare-value restore tolerance:** `Collectibles.restore():427-433` reads
  `data.get(SAVE_KEY, {})` and falls back to treating a bare list as the value.
  The new record store mirrors that for a bare `{trap_id: kmh}` map.
- **Slot-save accessors:** `save_manager.gd` `SAVE_DIR := "user://saves":11`,
  `_slot_path()` `"slot_%d.json" % (slot+1)` (`:254`), `load_game():78` /
  `save_game():46`, and the collectibles convenience pair
  `load_collectibles():238` / `save_collectibles():245`. The new feature uses the
  **generic** `load_game`/`save_game` pair (like `EventSession`) so
  `save_manager.gd` needs no new accessor.

### CanvasLayer z-order (measured)

| Layer | Owner |
|---|---|
| `0` (default) | `hud.tscn` root `HUD` (`scenes/ui/hud.tscn:101`) — cluster, minimap, FINISH `ResultsOverlay` |
| `10` | `scenes/ui/pause_menu.tscn:8` |
| `50` | `photo_mode.gd:33 FILTER_LAYER` |
| `100` | `scene_transition.gd:11` |
| `128` | `loading_screen_manager.gd:12` |

### Free-roam root nodes (where the feature attaches)

`scenes/world/open_world_root.tscn` (`[gd_scene load_steps=25 format=3]`):

- `HUD` instance of `hud.tscn` — line 157.
- `CollectibleField` (Script `20_collect`) — line 209.
- `SpeedTrapVisuals` (Script `21_trapvis`) — line 212.
- `PlayerCar` (instance `3_car`) — line 117 (`%PlayerCar` resolves).

### Safe HUD anchor geometry (reference 1920×1080)

- `ClusterBackdrop` (`hud.tscn:260-267`): anchored bottom-left, `x 16..592`,
  `y H-344..H-12`.
- `Minimap` (`hud.tscn:170-180`): anchored bottom-right, `x W-220..W-20`,
  `y H-710..H-510`.
- `NavWidget` (`hud.tscn:185-194`): `x 640..960`, `y H-560..H-300` (hidden by
  default).
- ⇒ At 1920×1080 a **bottom-centre** panel of ~560 px wide, bottom margin 24 px
  (`x ≈ 680..1240`, `y ≈ 992..1056`) is clear of all three.

---

## 3. Design decisions (options → chosen, trade-offs)

| # | Decision | Choice | Rationale / rejected option |
|---|---|---|---|
| D1 | Where the crossing is detected | **New node `SpeedTrapCrossing`** (`extends Node`) added to the open-world root, reading `POIRegistry` `speedtrap_*` entries | Rejected: extending `CollectibleField`. Its `_pending` list is *claims*, its signal carries no speed, and it is the money path — hooking a per-pass HUD into it would mean re-plumbing a shipped, gated trigger and widening its blast radius. A new reader of the **same published POIs** cannot disagree with the gates/dots, and is trivially gated. |
| D2 | Cross condition | **Radius only** (`xz_distance <= claim_radius_of(poi)`), independent of `can_claim`/speed target and of claim state | The user asked for "the speed I crossed at and my best" — that must fire on every pass, including under-speed and already-claimed traps. The money rule stays exactly where it is (`collectibles.gd`), untouched. |
| D3 | Re-fire guard | **Per-trap hysteresis latch**: fire on entering `r = claim_radius_of` (18 m); do not re-arm until the car is outside `r × 1.6` (28.8 m) | Simple, direction-agnostic (works reversing too), one bool per trap, no timers. Hysteresis > plus a margin over the enter radius prevents jitter on the boundary. Rejected: a cooldown timer (arbitrary, can eat a genuine second pass) and edge-detection via "was outside last frame" (re-arms inside the jitter band). |
| D4 | Crossing speed source | Mirror `CollectibleField._player_speed_kmh():126-133`: `current_speed_kmh` if present, else `get_drive_info()["speed_kmh"]`, else `0.0` | Identical contract means the headless test uses the same `StubCar` shape as `test_collectibles.gd:86`. |
| D5 | Best store | **New `SpeedTrapRecords`** (`extends RefCounted`, `class_name`), owned by the crossing node | A separate value object keeps the ledger pure and testable with no scene, exactly as `Collectibles` backs `CollectibleField`. |
| D6 | Persistence key + shape | New top-level slot key `"speed_traps"`, value `{"best": {trap_id: kmh}}`; written with the **generic** `SaveManager.load_game`/`save_game` read-modify-write (the `EventSession.save_bests():234` pattern) | No `save_manager.gd` edit (a concurrent agent is not touching it, but adding an accessor is unnecessary surface). Read-modify-write preserves every other slot field. |
| D7 | Legacy/shape tolerance | `restore` accepts `{"best": {...}}` **and** a bare `{trap_id: kmh}` map | Mirrors `Collectibles.restore():432` ("tolerate a bare list … so no claim is lost"). Costs two lines, kills a whole migration class. |
| D8 | Write cadence | **Pause-only** (`GameState.game_paused`), like `CollectibleField`/`WorldDiscovery`; in-memory best updates immediately | A disk write inside a physics tick is unacceptable. Pausing already means "the run is safe to persist". |
| D9 | Flash rendering | One **reused** full-screen `ColorRect` on the new `CanvasLayer`, alpha driven by a pure envelope; warm-white `Color(1.0, 0.96, 0.88)`, peak alpha `0.5`, rise `0.06 s`, fall `0.30 s` | Reuse (never spawn per crossing) ⇒ no leak, no stacking. Warm white reads as a "flashbulb", not a UI tint. Rejected: `Tween` (non-deterministic headless), `SceneTreeTimer` (same), screen-shader `CanvasItem` material (overkill, off-budget). |
| D10 | Banner rendering | One **reused** `Panel`+`Label`, bottom-centre, width 560, height 64, bottom margin 24, alpha envelope rise `0.15 s` / hold `1.8 s` / fall `0.45 s` (total 2.4 s) | Single node ⇒ a second crossing restarts the same banner cleanly. Timings: fast enough to feel immediate, long enough to read a speed + best. |
| D11 | Animation driver | Public `advance(delta) -> bool` on the HUD **plus** `_process` calling it, and `set_process(false)` when idle | Exactly the `SpeedTrapVisuals.tick():405` convention, and it is what makes the timing assertions possible headless. |
| D12 | Banner text | Pure static `SpeedTrapRecords.banner_text(speed, best, is_new_best)`: `"SPEED TRAP — 143 km/h · NEW BEST!"` / `"SPEED TRAP — 143 km/h · BEST 151 km/h"` / `"SPEED TRAP — 143 km/h"` when `best <= 0` | One pure function owns every string ⇒ unit-testable and impossible to desync from the best logic. |
| D13 | Z-order | New `CanvasLayer.layer = 40` | Above base HUD (`0`) and pause (`10`) so the banner is not covered by the cluster backdrop where they graze on narrow windows; below photo filter/transition/loading. The race FINISH overlay (`hud.tscn` `ResultsOverlay`, layer `0`) would sit *under* us — mitigated by D14. |
| D14 | Race-mode suppression | Crossing emits nothing while `RaceManager.is_race_active`; HUD also cancels/ignores playback while a race is active | Belt-and-suspenders. FINISH and a speed-trap banner can then never coexist, so the layer-40-vs-0 ordering conflict is theoretical. Also satisfies the "free-roam only" requirement. |
| D15 | Where it attaches | `open_world_root.tscn` only (new `SpeedTrapCrossing` node + new `SpeedTrapHUD` instance) | Circuit scenes have no traps and no `CollectibleField`; not instancing there is the cheapest possible gating (matches the `CollectibleField` "absent off-world" contract, `collectible_field.gd:9-10`). |
| D16 | Wiring | HUD finds the crossing via group `speed_trap_crossing`, **deferred one frame**; plus a public `bind(crossing)` for tests | `HUD` is earlier in the scene tree (line 157) than `SpeedTrapCrossing` (~213), so at `HUD._ready` the crossing has not yet joined its group; a deferred `_wire()` runs after every `_ready`. `bind()` keeps the suite scene-free. |

---

## 4. Implementation steps (ordered)

### Step 0 — create `scripts/world/speed_trap_records.gd` (NEW)

`class_name SpeedTrapRecords` / `extends RefCounted`. Header doc: the per-trap
best ledger, pure statics for the best rule and the banner string, persisted
under `SAVE_KEY` in the slot save.

```gdscript
const SAVE_KEY := "speed_traps"
const DEFAULT_SLOT := 0

var _best: Dictionary = {}   # trap_id (String) -> best km/h (float)
var _dirty := false

# Pure rules (no state) — the whole testable core.
static func is_new_best(prev_best: float, speed_kmh: float) -> bool:
	return speed_kmh > prev_best

static func merged_best(prev_best: float, speed_kmh: float) -> float:
	return maxf(prev_best, speed_kmh)

static func banner_text(speed_kmh: float, best_kmh: float, is_new_best: bool) -> String:
	var speed := "%d km/h" % roundi(speed_kmh)
	if is_new_best:
		return "SPEED TRAP — %s · NEW BEST!" % speed
	if best_kmh <= 0.0:
		return "SPEED TRAP — %s" % speed
	return "SPEED TRAP — %s · BEST %d km/h" % [speed, roundi(best_kmh)]

# State.
func best_of(trap_id: String) -> float:
	return float(_best.get(trap_id, 0.0))

func record(trap_id: String, speed_kmh: float) -> bool:
	var before := best_of(trap_id)
	var after := merged_best(before, speed_kmh)
	if after == before:
		return false
	_best[trap_id] = after
	_dirty = true
	return true

func best_map() -> Dictionary:
	return _best.duplicate()

# Persistence — the EventSession.save_bests read-modify-write, generic accessors.
func store() -> Dictionary:
	return {"best": _best.duplicate()}

func restore(data: Dictionary) -> void:
	var raw: Variant = data.get(SAVE_KEY, {})
	var best: Variant = raw
	if raw is Dictionary and (raw as Dictionary).has("best"):
		best = (raw as Dictionary)["best"]
	if not best is Dictionary:
		return
	var map: Dictionary = best
	for key: Variant in map.keys():
		var id := str(key)
		var value := float(map[key])
		if value > best_of(id):
			_best[id] = value
			_dirty = true

func save_to_slot(slot: int = DEFAULT_SLOT) -> bool:
	if SaveManager == null:
		return false
	var data: Dictionary = SaveManager.load_game(slot)
	data[SAVE_KEY] = store()
	return SaveManager.save_game(slot, data)

func load_from_slot(slot: int = DEFAULT_SLOT) -> bool:
	if SaveManager == null:
		return false
	restore(SaveManager.load_game(slot))
	return true
```

Notes: keep every local explicitly typed (gdUnit treats warnings as errors);
`float(map[key])` guards a JSON number that comes back as `int`. `record`
returns whether it improved (the crossing node uses this instead of calling
`is_new_best` twice). No `queue_free`, no tree access — pure value object.

### Step 1 — create `scripts/world/speed_trap_crossing.gd` (NEW)

`class_name SpeedTrapCrossing` / `extends Node`.

```gdscript
signal speed_trap_crossed(trap_id: String, speed_kmh: float, best_kmh: float, is_new_best: bool)

const GROUP_NAME := "speed_trap_crossing"
const HYSTERESIS := 1.6          # exit radius = enter radius * this
const save_on_pause := true      # keep the CollectibleField option shape

var _traps: Array[Dictionary] = []   # published trap POIs (id/position/extra)
var _records := SpeedTrapRecords.new()
var _inside: Dictionary = {}         # trap_id -> true while latched (cannot re-fire)
var _player: Node3D
var _enabled := true
```

- `_ready()`: `add_to_group(GROUP_NAME)`; build `_traps` from `POIRegistry`
  (`for poi_id: String in POIRegistry.get_poi_ids(): if Collectibles.kind_of_id(poi_id) == Collectibles.KIND_SPEED_TRAP: _traps.append(POIRegistry.get_poi(poi_id))`);
  `_records.load_from_slot(SpeedTrapRecords.DEFAULT_SLOT)`; connect
  `GameState.game_paused` → `_on_game_paused` when `save_on_pause`.
- `_exit_tree()`: disconnect the pause handler (mirror
  `collectible_field.gd:50-52`).
- `_physics_process(_delta)`: `if _enabled: simulate_step()`.
- `simulate_step() -> int` (public, headless-drivable like
  `CollectibleField.simulate_step():83`):

```gdscript
func simulate_step() -> int:
	if not _enabled or _traps.is_empty():
		return 0
	if RaceManager.is_race_active:          # free-roam only (D14)
		return 0
	if _player == null:
		_player = get_node_or_null("%PlayerCar") as Node3D
		if _player == null:
			return 0
	var pos := _player.global_position
	var crossed := 0
	for poi: Dictionary in _traps:
		var trap_id := str(poi.get("id", ""))
		if trap_id.is_empty():
			continue
		var enter := Collectibles.claim_radius_of(poi)
		var d := Collectibles.xz_distance(pos, poi.get("position", Vector3.ZERO))
		if _inside.has(trap_id):
			if d > enter * HYSTERESIS:
				_inside.erase(trap_id)      # re-arm once clear
			continue
		if d <= enter:
			_inside[trap_id] = true
			_emit_crossing(trap_id, _player_speed_kmh())
			crossed += 1
	return crossed
```

- `_emit_crossing(trap_id, speed_kmh)`:

```gdscript
func _emit_crossing(trap_id: String, speed_kmh: float) -> void:
	var prev := _records.best_of(trap_id)
	var is_best := SpeedTrapRecords.is_new_best(prev, speed_kmh)
	if is_best:
		_records.record(trap_id, speed_kmh)
	speed_trap_crossed.emit(trap_id, speed_kmh, SpeedTrapRecords.merged_best(prev, speed_kmh), is_best)
```

- `_player_speed_kmh() -> float`: copy of `collectible_field.gd:126-133`
  (`current_speed_kmh` then `get_drive_info()` fallback).
- `_on_game_paused()`: `_records.save_to_slot(SpeedTrapRecords.DEFAULT_SLOT)`.
- Public test surface: `records() -> SpeedTrapRecords`, `traps() -> Array[Dictionary]`,
  `set_enabled(value: bool)`, `erase_latch(trap_id)` (or `reset()` clearing
  `_inside`), so the suite can drive one crossing without a full pass.

No per-frame work beyond the trap loop (≤ ~8 traps worst case, each one
`xz_distance` — cheaper than the terrain push beside it, same argument as
`collectible_field.gd:19-21`).

### Step 2 — create `scripts/ui/speed_trap_hud.gd` (NEW)

`class_name SpeedTrapHUD` / `extends CanvasLayer`.

```gdscript
const LAYER := 40
const FLASH_COLOR := Color(1.0, 0.96, 0.88)
const FLASH_RISE := 0.06
const FLASH_FALL := 0.30
const FLASH_PEAK_ALPHA := 0.5
const BANNER_RISE := 0.15
const BANNER_HOLD := 1.8
const BANNER_FALL := 0.45

static func flash_total() -> float: return FLASH_RISE + FLASH_FALL
static func banner_total() -> float: return BANNER_RISE + BANNER_HOLD + BANNER_FALL

# Pure flash alpha envelope: 0 at t<=0, rises to FLASH_PEAK_ALPHA at
# t==FLASH_RISE, falls to 0 at t==flash_total(), 0 after.
static func flash_alpha(elapsed: float) -> float:
	if elapsed <= 0.0 or elapsed >= flash_total():
		return 0.0
	if elapsed < FLASH_RISE:
		return FLASH_PEAK_ALPHA * (elapsed / FLASH_RISE)
	return FLASH_PEAK_ALPHA * (1.0 - (elapsed - FLASH_RISE) / FLASH_FALL)

# Pure banner alpha envelope: rise, hold at 1, fall to 0.
static func banner_alpha(elapsed: float) -> float:
	if elapsed <= 0.0 or elapsed >= banner_total():
		return 0.0
	if elapsed < BANNER_RISE:
		return elapsed / BANNER_RISE
	if elapsed < BANNER_RISE + BANNER_HOLD:
		return 1.0
	return 1.0 - (elapsed - BANNER_RISE - BANNER_HOLD) / BANNER_FALL
```

- `@onready var _flash: ColorRect = $Flash`, `_banner: Panel = $Banner`,
  `_label: Label = $Banner/BannerLabel`.
- `_ready()`: `layer = LAYER`; hide both; `set_process(false)`;
  `call_deferred("_wire")`.
- `_wire()`: `var c := get_tree().get_first_node_in_group(SpeedTrapCrossing.GROUP_NAME)`;
  if non-null and not already connected, `c.speed_trap_crossed.connect(_on_crossed)`.
- `bind(crossing: Node) -> void`: connect explicitly (tests).
- `_on_crossed(trap_id, speed_kmh, best_kmh, is_new_best)` → `play(speed_kmh, best_kmh, is_new_best)`.
- `play(speed_kmh, best_kmh, is_new_best) -> void`: `if RaceManager.is_race_active: return`;
  set `_label.text = SpeedTrapRecords.banner_text(...)`; make both visible and
  reset `_t = 0.0`, `_playing = true`, `set_process(true)`.
- `_process(delta)`: `advance(delta)`.
- `advance(delta) -> bool`:

```gdscript
func advance(delta: float) -> bool:
	if not _playing:
		set_process(false)
		return false
	if RaceManager.is_race_active:      # a race started mid-animation: cancel
		_cancel()
		return false
	_t += delta
	if _flash != null:
		var fa := flash_alpha(_t)
		_flash.visible = fa > 0.0
		_flash.color = Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, fa)
	if _banner != null:
		var ba := banner_alpha(_t)
		_banner.visible = ba > 0.0
		_banner.modulate = Color(1.0, 1.0, 1.0, ba)
	if _t >= banner_total():
		_cancel()
		return false
	return true
```

- `_cancel()`: hide both, `_playing = false`, `_t = 0.0`, `set_process(false)`.
- `is_playing() -> bool` for tests.

### Step 3 — create `scenes/ui/speed_trap_hud.tscn` (NEW)

`[gd_scene load_steps=2 format=3]` with one `[ext_resource]` = the script.

```
[node name="SpeedTrapHUD" type="CanvasLayer"]
layer = 40
script = ExtResource("1")

[node name="Flash" type="ColorRect" parent="."]
visible = false
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
color = Color(1, 0.96, 0.88, 0)

[node name="Banner" type="Panel" parent="."]
visible = false
anchors_preset = 7
anchor_left = 0.5
anchor_top = 1.0
anchor_right = 0.5
anchor_bottom = 1.0
offset_left = -280.0
offset_top = -88.0
offset_right = 280.0
offset_bottom = -24.0
grow_horizontal = 2
grow_vertical = 0
mouse_filter = 2
theme_override_styles/panel = SubResource("StyleBoxFlat_trap_banner")

[node name="BannerLabel" type="Label" parent="Banner"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
horizontal_alignment = 1
vertical_alignment = 1
theme_override_colors/font_color = Color(1, 1, 1, 1)
theme_override_colors/font_outline_color = Color(0.02, 0.04, 0.09, 1)
theme_override_constants/outline_size = 6
theme_override_font_sizes/font_size = 28
mouse_filter = 2
```

One `StyleBoxFlat` sub-resource: dark translucent fill
`bg_color = Color(0.03, 0.05, 0.09, 0.82)`, `corner_radius_* = 10`,
`border_width_* = 2`, `border_color = Color(1.0, 0.72, 0.3, 0.9)` (a warm accent
so the banner reads as a "trap" banner, not a generic toast). No other
resources.

### Step 4 — edit `scenes/world/open_world_root.tscn` (node-only)

1. Header line 1 `load_steps=25` → **`load_steps=27`** (two new ext_resources).
2. Add after line 23:

```
[ext_resource type="Script" path="res://scripts/world/speed_trap_crossing.gd" id="22_crossing"]
[ext_resource type="PackedScene" path="res://scenes/ui/speed_trap_hud.tscn" id="23_traphud"]
```

3. Add `SpeedTrapHUD` right after the existing `HUD` node (after line 158):

```
[node name="SpeedTrapHUD" parent="." instance=ExtResource("23_traphud")]
```

4. Add `SpeedTrapCrossing` after `SpeedTrapVisuals` (after line 213):

```
[node name="SpeedTrapCrossing" type="Node" parent="."]
script = ExtResource("22_crossing")
```

Order note: `SpeedTrapHUD` appears before `SpeedTrapCrossing` in the file, so the
HUD cannot see the crossing's group at its own `_ready`; the deferred `_wire()`
(Step 2) resolves it one frame later. Do **not** "fix" this by moving the HUD
after the crossing unless you also verify the `_wire` defer — the defer is the
contract.

### Step 5 — tests (see §5), then gate

Add `tests/suites/test_speed_trap_hud.gd`. Run it plus the canaries
`test_collectibles.gd`, `test_speed_trap_visuals.gd` first via the
`docs/GDUNIT_GATE.md` headless recipe (import probe first,
`--ignoreHeadlessMode` AFTER the tool-script path). Full parallel gate only if
those are green — and per AGENTS.md dispatch the full gate as ONE background
sub-agent, never in the main session.

---

## 5. Test plan

New suite `tests/suites/test_speed_trap_hud.gd`, `extends GdUnitTestSuite`,
tabs, explicit types, `assert_that(...).is_equal/is_true/is_false/is_between`,
`is_equal_approx(v, 0.001)`. Slot-0 snapshot/restore in `before_test`/`after_test`
copied from `test_collectibles.gd:43-78` (save `SaveManager.load_game(SLOT)`,
restore or delete `user://saves/slot_%d.json`). `StubCar` for the crossing
tests is the `test_collectibles.gd:86` shape (`extends Node3D` +
`var current_speed_kmh: float`). All node creation goes on `_managed` and is
sync-freed in `after_test`.

**A. Pure record rules (`SpeedTrapRecords`)**

1. `test_is_new_best_is_strict_and_monotonic` — `is_new_best(0.0, 0.0)` false;
   `is_new_best(0.0, 1.0)` true; `is_new_best(150.0, 150.0)` false;
   `is_new_best(150.0, 149.9)` false; `is_new_best(150.0, 150.1)` true.
2. `test_merged_best_never_decreases` — `merged_best(150.0, 120.0) == 150.0`;
   `merged_best(150.0, 160.0) == 160.0`; and a fold over a descending+ascending
   series equals the running max.
3. `test_record_tracks_monotonic_best_and_reports_improvement` — `record` a
   140 → returns true, `best_of == 140`; record 130 → false, `best_of == 140`;
   record 151 → true, `best_of == 151`.
4. `test_banner_text_covers_new_best_best_and_no_best` —
   `banner_text(143.0, 151.0, false) == "SPEED TRAP — 143 km/h · BEST 151 km/h"`;
   `banner_text(151.0, 151.0, true) == "SPEED TRAP — 151 km/h · NEW BEST!"`;
   `banner_text(90.0, 0.0, false) == "SPEED TRAP — 90 km/h"` (no dangling "BEST 0").
   Also assert no banner string contains `"--"` or a negative sign.

**B. Pure timing envelopes (`SpeedTrapHUD` statics, no scene)**

5. `test_flash_alpha_envelope_is_bounded_and_peaks_at_rise` —
   `flash_alpha(-1.0) == 0.0`, `flash_alpha(0.0) == 0.0`;
   `is_equal_approx(flash_alpha(FLASH_RISE), FLASH_PEAK_ALPHA, 0.001)`;
   `flash_alpha(flash_total()) == 0.0`, `flash_alpha(999.0) == 0.0`;
   sample every 0.01 s across `[0, flash_total()]` and assert
   `0.0 <= a <= FLASH_PEAK_ALPHA`.
6. `test_banner_alpha_envelope_rises_holds_falls` —
   `banner_alpha(0.0) == 0.0`; `banner_alpha(BANNER_RISE) == 1.0`;
   `banner_alpha(BANNER_RISE + BANNER_HOLD) == 1.0` (end of hold);
   `banner_alpha(banner_total()) == 0.0`; `banner_alpha(banner_total() + 1.0) ==
   0.0`; monotone non-decreasing on the rise and non-increasing on the fall
   (sample loop).
7. `test_banner_is_longer_than_the_flash` — `banner_total() >
   flash_total()` (guards against a future inversion).

**C. Crossing detection (`SpeedTrapCrossing` + StubCar, no HUD)**

8. `test_crossing_fires_once_per_pass_with_hysteresis` — place one stub trap POI
   at origin (radius 18), stub car at z=0 → `simulate_step()` emits once (capture
   via a lambda/`connect` counting `speed_trap_crossed`); step again still inside
   → no second emit; move to 18·1.6 + 1 = 29.8 m away → step (no emit) then move
   back inside → emits again (re-armed). Assert exactly 2 emits over the pass.
9. `test_crossing_signal_carries_speed_best_and_new_best_flag` — first pass at
   120 km/h ⇒ `(id, 120.0, 120.0, true)`; after re-arm, second pass at 100 ⇒
   `(id, 100.0, 120.0, false)`; third at 130 ⇒ `(id, 130.0, 130.0, true)`.
10. `test_crossing_is_suppressed_while_a_race_is_active` — set
    `RaceManager.is_race_active = true`, drive the car through the trap radius →
    zero emits and no best recorded; restore the flag in a `finally`/`after_test`.
11. `test_crossing_does_not_require_the_money_speed_target` — drive through at
    5 km/h (below `speed_target_of`) ⇒ still emits (crossing ≠ payout), and the
    trap is not added to any claim ledger.
12. `test_already_claimed_trap_still_records_a_best` — seed slot 0 so the trap is
    "claimed" in the collectibles ledger (or simply ignore claims) and assert a
    crossing still emits and records (the ledger is independent).

**D. Wiring / no-leak (scene runner)**

13. `test_hud_binds_by_group_and_plays_on_crossing` — `scene_runner` the HUD
    scene, add a `SpeedTrapCrossing` to the same tree, `await
    runner.simulate_frames(2)` (lets the deferred `_wire` land), emit
    `speed_trap_crossed`, assert `is_playing()` and `advance(0.01)` returns true.
14. `test_advance_finishes_and_hides_both_overlays` — after `play`, drive
    `advance` in `banner_total()/0.05` steps; the last call returns false, both
    nodes are `visible == false`, `is_playing() == false`.
15. `test_play_does_not_stack_nodes` — call `play` three times back-to-back;
    `get_child_count()` is unchanged (single reused Flash/Banner) and
    `flash_alpha` starts from 0 with `_t` reset.
16. `test_hud_ignores_play_while_a_race_is_active` — set the flag, `play(...)` ⇒
    `is_playing() == false`, both hidden.

Determinism note: no test waits on wall-clock; every timing assertion calls the
pure statics or drives `advance(delta)` explicitly, so the suite is immune to
the `test_perf_gate`-class load flake.

---

## 6. Risks / gotchas

1. **Save coupling with the parallel gate.** The new key rides slot 0, which the
   parallel runner already isolates per shard by overriding `APPDATA` to an
   absolute path under `reports/parallel/userdata/` (so `user://` never leaves
   D:). The suite must still snapshot/restore slot 0 like
   `test_collectibles.gd:43-78` and must not assume `"speed_traps"` is absent.
   Writes are pause-only, so a test that never pauses touches nothing.
2. **Race vs free-roam HUD ownership.** The FINISH banner and `ResultsOverlay`
   are owned by `race_ui.gd` inside `hud.tscn` at layer 0
   (`race_ui.gd` `_on_race_finished():265`, `show_result():311`). Our layer 40
   would draw over them. Mitigation is the D14 gate (crossings suppressed and
   playback cancelled while `RaceManager.is_race_active`), so they cannot
   coexist. Do **not** try to fix this by lowering our layer below 0: the base
   HUD cluster/backdrop would then cover the banner where they graze on narrow
   windows.
3. **Banner overlap with FINISH on narrow viewports.** At the reference
   1920×1080 the bottom-centre banner (x≈680..1240) clears the cluster backdrop
   (x≤592), minimap (x≥1700) and `NavWidget` (y≤780). Below ~1500 px width the
   banner's left edge can reach the cluster backdrop; the translucent panel
   background keeps it readable, but verify on a 1280×720 window during
   implementation and shrink `offset_left/right` if needed. Also note
   `NavWidget` (`x 640..960`, `y H-560..H-300`, `hud.tscn:185-194`) is hidden by
   default and never reaches the bottom band.
4. **HUD/crossing init order.** `SpeedTrapHUD` precedes `SpeedTrapCrossing` in
   the scene, so the group lookup at `_ready` misses. The deferred `_wire()` is
   load-bearing — a suite that instantiates only the HUD (no crossing) must call
   `bind()` explicitly (test 13 covers the group path).
5. **gdUnit treats warnings as errors.** Type every local
   (`var raw: Variant`, `var cross: Variant = ...` when reading untyped
   dictionaries), no `:=` on a Variant-returning call, tabs only. Vector
   `is_equal_approx` needs a same-type epsilon (not used here, but do not
   compare `float` to a `Vector3`).
6. **JSON round-trip numbers.** `SaveManager` JSON may return a best as `int`;
   `restore` must `float(map[key])` before comparing, or a `Dictionary` typed as
   `String -> float` will trip a runtime type error.
7. **A suite aborts at its first failure.** Order the tests pure-first (A/B) so
   the cheap deterministic layer runs before any scene runner; a failure in a
   later scene test must not hide the pure results in the local run.
8. **No per-frame cost when idle.** The HUD must `set_process(false)` at rest;
   the crossing loop is ≤ ~8 `xz_distance` calls per physics tick. Keep both,
   and do not add `queue_redraw()` per frame.
9. **`SpeedTrapVisuals` flash is unrelated.** That node's `mark_claimed():374`
   / `tick():405` drives the *gate* glow on a money claim. Do not merge the two
   flashes — a trap that already paid still needs the new HUD crossing on later
   passes, which `mark_claimed` explicitly no-ops (`:375-376`).
10. **`%PlayerCar` in the headless suite.** `get_node_or_null("%PlayerCar")`
    resolves only if the stub is named/parented accordingly; mirror
    `test_collectibles.gd` (add the `StubCar` as a child named to satisfy the
    `player_path`, or set `player_path`/expose a setter) rather than guessing.

---

## 7. Do NOT touch (owned by concurrent agents)

Uncommitted work in this checkout touches the following; leave them alone:

- **Power/torque HUD** — `scenes/ui/hud.tscn` (`%TorqueValue` label added at
  ~line 389, `load_steps` bumped) and `scripts/race/race_ui.gd`
  (`_refresh_power_readout`, `@onready var torque_value`). The new feature must
  NOT edit either file; it adds a *separate* `CanvasLayer` scene instead.
- **Race menu / world map UI** — `scripts/ui/track_select.gd`,
  `world_map_projection.gd`, `track_map.gd`, `levant_outline.gd`,
  `menu_video_*`.
- **Post-race cinematic / exit button** — the `%ResultsOverlay`,
  `%NextRaceButton`, `%ReturnFreeRoamButton` region of `hud.tscn` and
  `race_ui.gd`'s `show_result()`/`_on_race_finished()`.
- **Barcelona track** — `scenes/track/barcelona_rx.tscn`,
  `scripts/track/barcelona_rx*.gd`, `rx_dressing.gd`.
- **Cockpit** — `scenes/vehicle/interiors/*`, `scripts/camera/cockpit_camera.gd`,
  cockpit tests.
- **Plugins** — `.opencode/plugins/graphify.js` (and any plugin file).
- **Shared core the feature only READS:** `scripts/world/collectibles.gd`,
  `scripts/world/collectible_field.gd`, `scripts/world/speed_trap_visuals.gd`,
  `scripts/world/poi_registry.gd`, `autoload/save_manager.gd`,
  `autoload/race_manager.gd`, `autoload/game_state.gd`,
  `scripts/world/world_driver.gd`. If any of these needs a new method, stop and
  re-plan — the design deliberately needs none.
- Do not add an autoload, a `.tres`, or a new `SaveManager` accessor.

### Files this plan creates / edits (the whole blast radius)

- **NEW** `scripts/world/speed_trap_records.gd`
- **NEW** `scripts/world/speed_trap_crossing.gd`
- **NEW** `scripts/ui/speed_trap_hud.gd`
- **NEW** `scenes/ui/speed_trap_hud.tscn`
- **NEW** `tests/suites/test_speed_trap_hud.gd`
- **EDIT** `scenes/world/open_world_root.tscn` — 2 ext_resources, 2 nodes,
  `load_steps` 25 → 27 (node-only; no existing node changed)
