# Plan — Exhaust "Pops & Bangs" (overrun crackle / afterfire layer)

Status: **PLAN ONLY** (written 2026-10-19 by planner subagent; no game code
touched, no Godot run, no gate run).

Scope in one line: add an **opt-in, per-car, deterministic overrun exhaust layer**
— lift-off crackle, burble and bang — that rides on top of the existing
`EngineAudio` bed mix, triggers only on a real high-rpm throttle release, and
leaves every currently-shipped car byte-identical.

> **graphify note.** `graphify-out/graph.json` has **no GDScript extractor**, so
> all ~510 gameplay files under `scripts/**.gd` (and every `.tscn`/`.tres`) are
> **absent** from the graph. Every codebase claim below therefore comes from
> reading the GDScript source directly, with `file:line`. Do **not** spend time on
> `graphify query` for this feature — it cannot see the code involved.

---

## 1. Goal + acceptance criteria

**Goal:** when a car lifts off the throttle above a configurable RPM fraction,
its engine emits an **audible exhaust crackle/bang burst** for a short overrun
window, with the amplitude, pop count and spacing varied the way a real overrun
map does (irregular, decaying, never a machine-gun loop), authored per car
through `CarConfig`, fully deterministic for tests, and independent of frame
timing / load.

**Player-verifiable acceptance criteria** (any car whose config sets
`exhaust_pop_enabled = true`; the GT-R R35 is the intended first adopter):

1. **Fires on overrun:** a high-rpm throttle release (rev above
   `exhaust_pop_min_rpm_fraction × redline`, then throttle drops) produces an
   audible pop/crackle burst starting right at the lift.
2. **Does not fire otherwise:** steady throttle, a low-rpm lift, reverse, and
   `exhaust_pop_enabled = false` cars produce **no** burst — the engine sound is
   exactly as it is today.
3. **Irregular, decaying train:** the burst is several unevenly-spaced pops whose
   level decays over the window (not one menace-less click, not a metronome).
   Two consecutive lifts are audibly *not identical*.
4. **Style per car:** `exhaust_pop_style` selects an audibly distinct character
   (`burble` = few soft low pops, `crackle` = a dense sharp rattle, `bang` = one
   or two loud low booms).
5. **Layered, not replacing:** the steady engine bed, load shaping, gear-shift
   clutch catch, existing lift-off gain nudge, turbo spool/BOV/flutter all still
   behave exactly as before; the burst is additive on top.
6. **Settings intact:** Settings volume still scales everything (Master bus only).
7. **No regressions:** cars without the flag are byte-identical; the player
   Master-bus LPF behaviour is untouched; rival/traffic audio unchanged;
   headless runs create no pop players; targeted GDUnit gate green (§6).

---

## 2. Current state — VERIFIED (file:line)

### 2.1 The audio node this feature plugs into

- `scripts/audio/engine_audio.gd:1-2` — `class_name EngineAudio extends
  AudioStreamPlayer3D`. It is **self-driving**: `_ready()` (`:189-199`) resolves
  its parent as `VehiclePhysics`, loads five loop beds, creates **five child
  `AudioStreamPlayer3D` band players** (`_create_band_players`, `:239-249`) and
  plays them.
- `_physics_process(delta)` (`:320-415`) reads the parent's
  `VehiclePhysics.get_drive_info()` (`:354`), pulls `rpm`/`throttle`/`gear`
  (`:355-358`), and per frame writes `player.pitch_scale` (`:401`) and
  `player.volume_db` (`:402-405`).
- `scripts/vehicle/vehicle_physics.gd:490-514` — `get_drive_info()` keys:
  `rpm`, `gear`, `speed_kmh`, `handling_mode`, `throttle`, `brake`, `steer`,
  `surface`, `slip`, `handbrake`, `boost_bar`, `boost_fraction`, `has_turbo`.
  **There is no overrun / fuel-cut / declutch state** — an overrun trigger must be
  *derived* from the throttle edge + rpm + gear (§3.2).

### 2.2 What already occupies the "lift-off" space — MUST NOT be broken

- **Lift-off gain nudge (already ships):** `LIFT_ENV_SECONDS = 0.22` (`:114`),
  `LIFT_GAIN_DB = 3.0` (`:115`), member `_lift_env` (`:176`), trigger
  `_prev_throttle > 0.5 and throttle < 0.15` (`:377-379`), helpers `lift_pop()`
  (`:753-754`) + `transient_gain_db()` (`:759-763`), folded into the band target
  at `:397` / `:402`. This is a **gain bump on the real-bed mix, NOT a synthetic
  pop** (comment at `:111-113`). The new layer must **layer on top**, never
  replace or re-tune it (criterion 5).
- **Turbo BOV / wastegate flutter one-shots (already ship):** fired on the *same*
  lift edge in `_update_turbo()` — BOV `:306-308`, flutter `:313-316`; creation
  gate `should_create_turbo_players()` `:797-800` (turbo car AND not `"headless"`);
  load `load_turbo_assets()` `:808-825` (whine forced to `LOOP_FORWARD` with the
  QOA loop_end snap, one-shots left unlooped). `_update_turbo()` is deliberately
  called **before** the lift-edge block (`:369-375`) because it reads
  `_prev_throttle` (`:175`) which is overwritten at `:379`. **The new overrun
  updater must obey the same ordering rule** (insert at `:375`).
- **CarConfig already has turbo knobs** at `scripts/vehicle/car_config.gd:48-58`
  (`turbo_max_boost_bar` default `0.0` = NA, `turbo_spool_time`,
  `turbo_blowdown_time`, `turbo_whine_gain`, `turbo_has_wastegate`). **No
  exhaust/overrun/pop flag exists anywhere** — this is the place to add one.
- `resources/cars/nissan_gt_r35_2017.tres:12-13,49-53` — the GT-R is
  `engine_timbre = "gtr"` / `engine_bed_set = "gtr"`, `turbo_max_boost_bar = 1.8`,
  `turbo_has_wastegate = true`. It is the natural first car to enable pops on.

### 2.3 Existing conventions the new layer should copy

- **Headless guard:** turbo players + `CarAudio` feel players are never created
  under the `"headless"` display server (`should_create_turbo_players`,
  `:797-800`). Any new audio-node creation must mirror this so headless tests stay
  cheap and safe (criterion 7).
- **Export trims:** `extra_trim_db` (`:153`, default `0.0` = player) and
  `auto_cull_range` (`:156`) exist as the per-node override channel — band target
  clamp is `MUTE_FLOOR_DB .. 6.0` (`:402`), turbo one-shot trims `:299,307,315`.
- **Single Master bus:** there is **no** `default_bus_layout.tres` and no bus keys
  in `project.godot`; all players inherit `Master`. Settings sets Master volume
  only (`scripts/ui/settings_menu.gd:599-600`). → **zero bus/menu work** for this
  feature (criterion 6 is free).
- **Master-bus LPF quirk:** only the **player's own** `EngineAudio` installs an
  `AudioEffectLowPassFilter` on `Master` (`_ensure_lpf`, `:843-860`), driven
  900→8000 Hz (`:412-415`); non-player instances must never take that path. The
  new layer must not add any bus effect.

### 2.4 Asset / synthesis reality (what a pop could be made of)

- The five steady beds are **externally synthesized** (enginesound v1.5.0, MIT)
  then shipped as WAVs — `assets/audio/engine/LICENSES.md:3-22,48-60`.
- The **gtr** family and the turbo one-shots are **in-repo synthesized** by
  **pure-Python-stdlib** tools: `tools/make_gtr_beds.py`,
  `tools/make_gtr_turbo.py` — `LICENSES.md:103-108,142-161`. Two recorded turbo
  voices came from user MP3s via `tools/make_wrx_turbo_loop.py` /
  `tools/make_sutu_flutter.py` (present in `tools/`).
- `scripts/vehicle/car_audio.gd` (`CarAudio`) synthesizes beds/one-shots **at
  runtime** in GDScript with a `RandomNumberGenerator` seeded to fixed constants
  (e.g. `_build_impact_bed` seed 731, `_build_shift_bed` seed 733) — a working
  in-tree precedent for deterministic procedural one-shots.
- **QOA loop trap:** Godot 4.7's WAV importer defaults to QOA, and QOA playback
  silently fails to start when `loop_end` is the `-1` sentinel;
  `load_beds_for()`/`load_turbo_assets()` snap `loop_end` to `frames - 1`
  (`:479-499`, `:808-825`). **Runtime-built `AudioStreamWAV`s avoid this trap
  entirely** (no import, no QOA), which is one reason the plan builds pops at
  runtime (§3.1).

### 2.5 Test style to mirror

- `tests/suites/test_turbo_audio.gd` — pure static gain tests (mute-floor at zero,
  monotonic + capped), creation-gate truth table, WAV existence, loop assertions,
  and a headless branch on `DisplayServer.get_name()`. Model the new suite on it.
- Sibling audio suites: `test_engine_audio.gd`, `test_car_audio.gd`,
  `test_audio_feel_layers.gd`, `test_rival_car_audio.gd`.
- gdUnit house traps: **warnings are errors** (declare explicit types; never `:=`
  from a `Variant`-returning call), a suite **aborts at its first failure**, `-a`
  is one-per-flag (comma-joined paths false-green), and **never assert wall-clock
  time**.

---

## 3. Design decisions (options → chosen, with rationale)

### 3.1 How the pop sound is produced

| # | Option | Verdict |
|---|--------|---------|
| A | **Runtime synthesis in GDScript** — build the burst `AudioStreamWAV`(s) from a seeded `RandomNumberGenerator`, cache statically, play as one-shots (mirrors `CarAudio`) | **CHOSEN.** No new binary assets, no import step, no QOA trap, deterministic seed → fully unit-testable, and per-event variation is cheap. |
| B | Offline **pure-Python-stdlib tool** (`tools/make_exhaust_pops.py`) shipping WAVs (mirrors `make_gtr_turbo.py`) | Rejected as primary: adds binary assets + import + a `check_*.py` gate for no functional gain, and bakes one fixed burst per file (less variation). Noted as the fallback if runtime synthesis ever fails to sound good. |
| C | Sample real pop recordings (user MP3s, like the wrx/sutu turbo voices) | Out of scope here (needs assets from the user); a future drop-in that would reuse the §4 event API unchanged. |
| D | Reuse `flutter_hits.wav` as the pop one-shot | Rejected: it is already turbo-car-only `flutter`; reusing it would duplicate the turbo layer and exclude NA cars (criterion 1). |

**Chosen synthesis recipe** (concrete, per pop; the executor may tune by ear but
must keep the determinism contract):

- Sample rate `22050` Hz, `FORMAT_16_BITS`, mono (pops are broadband/percussive;
  22050 is ample and halves memory vs the 48 kHz beds; Godot resamples on mix).
- Each pop = a short transient + a body tone, both shaped per style:
  - **transient**: exponentially-decaying **white noise** with a 1–3 ms attack,
    decay time-constant 25–90 ms, band-shaped by a one-pole filter — **high-pass
    ≈ 1.2–2.5 kHz** for `crackle` (sharp crack), **low-pass ≈ 600–1200 Hz** for
    `bang` (dull boom);
  - **body**: a decaying sine **60–130 Hz** (the "boom" thump), gain relative to
    the transient by style (`bang` strong, `crackle` low, `burble` mid);
  - optional 2-pole resonator ~200–800 Hz for the "thock" between the two.
- A **burst** string = N pops placed over `duration` with **jittered spacing**
  (Poisson-ish: gaps drawn from the seeded RNG around a style mean) and a
  **decaying global envelope**; final soft-clip caps the peak at `<= 0.95`.
- **Style constants (APPROXIMATE, ear-tuned, not measured fact):** `burble`
  ~2–4 pops over ~1.2 s, soft; `crackle` ~6–14 pops over ~0.9 s, sharp; `bang`
  ~1–3 pops over ~0.5 s, loud — see the source notes on how real overrun maps
  are rich-but-irregular [S2][S3][S4][S12].
- **Determinism contract:** *every* random draw comes from a supplied
  `RandomNumberGenerator` seeded with the caller's `seed`. Identical
  `(style, duration, intensity, sample_rate, seed)` ⇒ byte-identical
  `PackedByteArray`. This is what the §6 tests assert.

### 3.2 How "overrun" is detected (no overrun state exists)

`get_drive_info()` exposes no fuel-cut/declutch/tip-out flag (§2.1), and adding
physics state is out of scope. So the trigger is **derived, presentation-only**,
from signals already in hand:

**Fire when ALL hold:**

1. `exhaust_pop_enabled` (per car) **and** intensity > 0;
2. the existing **lift edge** `_prev_throttle > 0.5 and throttle < 0.15`
   (`:377`, shared with BOV/flutter/lift-nudge — reuse the same edge so a single
   lift produces one coherent event);
3. `rpm_norm >= exhaust_pop_min_rpm_fraction` (default `0.40` → on the GT-R's
   7000 redline that is ≈ 3280 rpm; real overrun pops need revs [S2][S12]);
4. `gear != -1` (no pops in reverse);
5. the **cooldown** has expired (`_pop_cooldown <= 0`) so rapid throttle taps
   cannot machine-gun the burst.

**Not** required (deliberately): a positive road speed (a stationary rev-and-drop
pops in most games too), and a negative `_rpm_deriv` (revs are obviously falling
after a lift; requiring it would only add a one-frame lag and fragility).

Rationale for the edge conditions: real pops come from **unburnt fuel igniting in
a hot exhaust on overrun** — i.e. high rpm + closed throttle + a hot pipe
[S1][S9][S12]; the tuning-map literature describes disabling overrun fuel cut and
retarding ignition ATDC exactly for that window [S2][S3][S4]. Anti-lag / off-
throttle exhaust blowing is the motorsport extreme of the same phenomenon
[S5][S6][S10][S11]. Fuel-cut catalyst over-temperature is the reason OEMs limit
it [S7][S8] — hence pops stay an explicitly opt-in flavour, not a default.

### 3.3 Variation without a machine-gun loop

A single repeated pop = the classic "metronome" immersion killer [S20]. Two
mechanisms, both deterministic:

- **Baked-in variation:** the burst already has jittered spacing + decaying level
  (§3.1).
- **Per-event variation:** a node-level `_pop_rng` picks a **variant index** and a
  small **pitch/level jitter** on each trigger, so two lifts differ. The RNG is a
  member seeded to a fixed default (`DEFAULT_POP_SEED`) for reproducible default
  behaviour, and **settable from tests** to assert a known sequence.

This follows the game-audio guidance to randomise pitch/level and avoid exact
repeats [S15][S18][S20][S22], and the granular/impulse-train framing of dense
overrun rattle [S17][S19][S21]. Where an exact numeric acoustic claim is used
(e.g. pop counts, decay times) it is marked **APPROXIMATE** here — no source
consulted pinned exhaust-crackle micro-timing to a measurement, so nothing in
§3.1 is presented as measured fact.

### 3.4 Load- and frame-rate-insensitivity

- **One stream per event.** The whole burst is synthesised as **one**
  `AudioStreamWAV` and played once on one dedicated player — no per-frame
  scheduling of individual pops. Once started, Godot mixes it sample-accurately,
  so the *sound* is identical at 30 or 500 fps.
- **Cooldown/state in seconds, stepped by `delta`** (`_pop_cooldown =
  maxf(_pop_cooldown - delta, 0.0)`), never by a frame counter.
- **Cache is shared:** the burst bank is built once per `(style, duration,
  intensity-bucket, seed)` and stored in a **static** dictionary, so N cars do
  not each re-synthesise identical PCM (the same reasoning that keeps
  `load_beds_for()` shared, §2.4).

### 3.5 Where the knobs live (per-car)

Add a new `# --- Exhaust overrun (pops & bangs) ---` block to
`scripts/vehicle/car_config.gd` next to the turbo block (`:48-58`), **all
defaults OFF / neutral** so every `.tres` in the tree keeps today's behaviour:

| Knob | Type / default | Meaning |
|---|---|---|
| `exhaust_pop_enabled` | `bool = false` | opt-in; `false` ⇒ zero behaviour change |
| `exhaust_pop_style` | `@export_enum("burble","crackle","bang") = "crackle"` | burst character (§3.1) |
| `exhaust_pop_intensity` | `float = 1.0`, clamp `[0,2]` | scales level + pop count |
| `exhaust_pop_min_rpm_fraction` | `float = 0.40`, clamp `[0,1]` | lift must exceed this × redline |
| `exhaust_pop_duration` | `float = 0.9` s, clamp `[0.1, 3.0]` | overrun burst window |
| `exhaust_pop_gain_db` | `float = -6.0` | layer trim, applied inside the `MUTE_FLOOR_DB..6.0` clamp (like turbo trims) |

Rejecting the alternatives: a **global** pop on all cars (ignores "no tech
ceiling" per-car identity and the OEM reality that pops are a tuned flavour
[S2][S4]); a **runtime `Settings` toggle only** (no per-car authoring); and
**deriving** the style from `engine_timbre` alone (a muscle V8 burbles and a
turbo-6 crackles, but the two axes are independent — a car may want a style that
its bed family does not imply).

---

## 4. Architecture — exact files, nodes, functions

### 4.1 Files owned by this plan

| File | Change |
|---|---|
| `scripts/vehicle/car_config.gd` | new `# --- Exhaust overrun ---` block (§3.5) — 6 exports |
| `scripts/audio/engine_audio.gd` | new consts + static builders + one player + `_update_overrun()` + `_ensure_pop_layer()`; **do not alter** existing bed/turbo/lift logic |
| `resources/cars/nissan_gt_r35_2017.tres` | author the new knobs (enable `crackle` on the R35) — the only `.tres` changed initially |
| `tests/suites/test_exhaust_pops.gd` | **new** suite (§6) |

### 4.2 `scripts/audio/engine_audio.gd` — additions (TAB indentation)

**New constants** (near the turbo block, after `:137`):

```gdscript
## Overrun exhaust layer (pops & bangs), presentation-only: a synthesized burst
## one-shot layered on the bed mix when a high-rpm throttle release is detected.
## Opt-in per car (CarConfig.exhaust_pop_enabled); never created under the
## headless display server (same guard as the turbo layer).
const POP_STYLES: Array[String] = ["burble", "crackle", "bang"]
const POP_SAMPLE_RATE: int = 22050
## Bank size per style (variants the per-event RNG chooses between).
const POP_VARIANTS: int = 4
const POP_GAIN_TRIM_DB: float = -6.0        # fallback if cfg.gain missing
const POP_COOLDOWN_SECONDS: float = 0.15
const POP_RELEASE_HI: float = 0.5           # matches the lift edge
const POP_RELEASE_LO: float = 0.15
const DEFAULT_POP_SEED: int = 90210
```

**New member state** (near `:186`):

```gdscript
var _pop_player: AudioStreamPlayer3D = null
var _pop_rng := RandomNumberGenerator.new()
var _pop_cooldown: float = 0.0
static var _pop_bank_cache: Dictionary = {}
```

**New pure static builders** (the testable core — place beside the other
statics, e.g. after `:790`). All deterministic; no engine/scene dependency:

```gdscript
static func normalize_pop_style(style: String) -> String            # unknown -> "crackle"
static func pop_count_for(style: String, intensity: float) -> int   # clamped, style-aware
static func pop_duration_for(style: String, duration: float) -> float
static func overrun_should_fire(prev_throttle: float, throttle: float,
        rpm_norm: float, gear: int, enabled: bool,
        min_rpm_fraction: float, cooldown: float) -> bool           # §3.2 truth
static func build_pop_burst(style: String, duration: float, intensity: float,
        sample_rate: int, seed: int) -> AudioStreamWAV              # §3.1 recipe
static func pop_bank_key(style: String, duration: float, intensity: float, seed: int) -> String
static func should_create_pop_players(cfg: CarConfig, display_name: String) -> bool
```

**New instance methods** (mirror the turbo layer):

```gdscript
func _ensure_pop_layer(cfg: CarConfig) -> void      # lazy create, ~ :278
func _update_overrun(cfg: CarConfig, info: Dictionary, rpm_norm: float,
        throttle: float, gear: int, delta: float) -> void
func _fire_overrun(cfg: CarConfig) -> void          # picks variant, sets pitch/vol, play()
```

**Call-site wiring inside `_physics_process`** — insert **exactly between** the
existing `_update_turbo(...)` call (`:375`) and the lift-edge block (`:377-379`),
so it sees the same `_prev_throttle` the turbo layer did:

```gdscript
_ensure_pop_layer(cfg)
_update_overrun(cfg, info, rpm_norm, throttle, gear, delta)   # NEW
if _prev_throttle > 0.5 and throttle < 0.15:                  # existing, unchanged
    _lift_env = LIFT_ENV_SECONDS
_prev_throttle = throttle
```

`_update_overrun()` internally: decay `_pop_cooldown` by `delta`; compute the
trigger via `overrun_should_fire(...)`; on fire, set `_pop_cooldown` and call
`_fire_overrun()`. `_fire_overrun()` looks up (or builds) the cached burst for the
car's style/duration/intensity, assigns it to `_pop_player.stream`, sets
`_pop_player.pitch_scale = pop_pitch_jitter(_pop_rng)` and
`volume_db = clampf(db + cfg.exhaust_pop_gain_db + extra_trim_db, MUTE_FLOOR_DB, 6.0)`,
then `_pop_player.play()`.

`_ensure_pop_layer()` is a no-op unless `should_create_pop_players(cfg,
DisplayServer.get_name())`. Uses `unit_size`/`max_distance` copied from the node
(like `_create_turbo_players`, `:252-268`), name `"ExhaustPop"`.

### 4.3 Do NOT touch (owned by other work / load-bearing)

- **The lift-off gain nudge** (`LIFT_ENV_SECONDS`, `LIFT_GAIN_DB`, `_lift_env`,
  `lift_pop()`, `transient_gain_db()`, `:111-115,:176,:377-397,:751-763`) — reuse
  the *edge condition* only; do not retune or repurpose it.
- **The turbo layer** — `TURBO_*` consts, `_update_turbo`, `load_turbo_assets`,
  `should_create_turbo_players`, the BOV/flutter one-shots. Pops must not
  duplicate or replace flutter.
- **The five band players / crossfade / pitch math** (`:239-249`, `:590-741`).
- **The Master-bus LPF path** (`_ensure_lpf`/`_remove_lpf`, `:843-873`) — the new
  layer adds **no** bus effect and never touches `_lpf_effect`.
- **`scenes/vehicle/player_car.tscn`** and **`rival_car.tscn`** — not edited at
  all; the layer is created lazily by the script, so no scene change is needed.
- **`scripts/vehicle/car_audio.gd`**, `scripts/ui/**`, `scripts/race/**`,
  `scripts/track/**` — untouched.

---

## 5. Phased implementation steps

Effort tags: **S** ≈ <30 min, **M** ≈ 0.5–1.5 h, **L** ≈ >1.5 h. Each phase is
independently verifiable and leaves the tree green.

**Phase 1 — CarConfig knobs (S).**
Add the §3.5 block to `scripts/vehicle/car_config.gd` after `:58`. All defaults
off/neutral. *Verify:* `test_exhaust_pops.gd` case "defaults are off" +
`test_car_sound_profiles`/`test_car_audio` still green (no config-consumer breaks).

**Phase 2 — pure static core in `engine_audio.gd` (M).**
Add the §4.2 constants and the static builders (`normalize_pop_style`,
`pop_count_for`, `pop_duration_for`, `overrun_should_fire`, `build_pop_burst`,
`pop_bank_key`, `should_create_pop_players`). No call sites yet — the feature is
inert. *Verify:* the static-builder and trigger-truth-table tests (§6 cases 1–7)
pass; the full audio suites are unaffected.

**Phase 3 — wire the layer into `_physics_process` (M).**
Add `_pop_player`/`_pop_rng`/`_pop_cooldown` state, `_ensure_pop_layer`,
`_update_overrun`, `_fire_overrun`, the insert at §4.2, and `_exit_tree`
teardown is automatic (child of the node). Pop players only exist for enabled,
non-headless cars. *Verify:* §6 cases 8–11 (creation gate, headless no-op,
integration: after entering the tree with an enabled config the `ExhaustPop`
child exists on a non-headless box, and its `stream` is a non-null
`AudioStreamWAV`).

**Phase 4 — author the first car (S).**
Set on `resources/cars/nissan_gt_r35_2017.tres`:
`exhaust_pop_enabled = true`, `exhaust_pop_style = "crackle"`,
`exhaust_pop_gain_db = -6.0`. *Verify:* a config-load test asserts the R35's
values; the file still loads (`--headless --import` import probe has **zero**
`SCRIPT ERROR`/`Parse Error`).

**Phase 5 — gate + housekeeping (S).**
Run the §6 targeted suites then the parallel gate as a **background** sub-agent
(per AGENTS.md), then `graphify update .` after code changes. Record the
`Overall Summary` delta. No global total is hard-coded.

---

## 6. Test plan (GDUnit4)

New suite: **`tests/suites/test_exhaust_pops.gd`** (model on
`test_turbo_audio.gd`). Determinism only — **no wall-clock assertions anywhere**.

1. `test_config_defaults_are_off_and_neutral` — a fresh `CarConfig.new()` reports
   `exhaust_pop_enabled == false`, `exhaust_pop_style == "crackle"`,
   `exhaust_pop_intensity == 1.0`, `exhaust_pop_min_rpm_fraction == 0.40`,
   `exhaust_pop_gain_db == -6.0`. Plus: `preload("res://resources/cars/starter_car.tres")`
   has the flag `false` (regression lock, criterion 7).
2. `test_overrun_trigger_truth_table` — pure `overrun_should_fire(...)`:
   fires only for (enabled) ∧ (edge `0.6→0.0`) ∧ (`rpm_norm ≥ min_fraction`) ∧
   (`gear != -1`) ∧ (`cooldown <= 0`); returns false for each violated clause
   (disabled, low-rpm lift, throttle still down, reverse, cooldown active).
3. `test_pop_burst_is_deterministic_for_a_seed` — `build_pop_burst("crackle",
   0.9, 1.0, 22050, 42)` twice ⇒ identical `data` `PackedByteArray` and identical
   `get_length()`; `FORMAT_16_BITS`; mono.
4. `test_pop_burst_varies_with_seed_and_style` — seed `42` vs `43` differ; and the
   three styles differ from each other (not byte-identical).
5. `test_pop_count_and_level_track_intensity` — `pop_count_for` monotonic
   non-decreasing in intensity, `0` ⇒ silent-but-valid (or empty) stream; burst
   peak is `<= 0.95` at any intensity; amplitude non-decreasing in intensity.
6. `test_pop_duration_is_bounded` — `pop_duration_for` clamps to `[0.1, 3.0]` and
   the built burst's `get_length()` lies within a small tolerance of the clamped
   duration.
7. `test_creation_gate_rejects_disabled_na_and_headless` —
   `should_create_pop_players` false for `null`, for `enabled = false`, and for
   `"headless"`; true for an enabled config on a dummy display.
8. `test_headless_instance_creates_no_pop_player` — branch on
   `DisplayServer.get_name()` (as `test_turbo_audio.gd:94-106`): headless ⇒
   `_pop_player == null` and `get_node_or_null("ExhaustPop") == null`.
9. `test_enabled_instance_creates_pop_player` — on a non-headless box: a car with
   an enabled config + `EngineAudio` child gets exactly one `ExhaustPop`
   `AudioStreamPlayer3D` after `_ensure_pop_layer`.
10. `test_overrun_fires_one_shot_on_lift_edge` — integration: drive
    `_update_overrun` with a scripted `(prev_throttle, throttle, rpm_norm, gear)`
    sequence; assert the player `is_playing()` right after the lift edge and
    **not** on a steady-throttle frame; assert a second lift inside the cooldown
    does **not** re-fire, and after the cooldown it does.
11. `test_cars_without_the_flag_are_unaffected` — instantiate `player_car.tscn`
    (or a bare `VehiclePhysics` with `starter_car.tres`) and assert no
    `ExhaustPop` child is ever created (criterion 7).

**Targeted gate after implementation** (each `-a` separate — see
`docs/GDUNIT_GATE.md`; comma-joined paths false-green): `test_exhaust_pops`
(new), `test_engine_audio`, `test_turbo_audio`, `test_car_audio`,
`test_audio_feel_layers`, `test_car_sound_profiles`, `test_rival_car_audio`.
Then the full suite via the background parallel gate
(`py tools\gdunit_parallel.py -j 4`). Baseline for comparison: AGENTS.md
parallel gate `1018 test cases | 0 errors | 0 failures | 20 orphans`; expect
roughly **+11** cases and no new `perf_gate` failure (read the `mode=` line —
this GTX 970 box runs relative mode).

**Playtest gate** (manual, cannot be automated): criteria 1–7 — audibly fire on
an R35 high-rpm lift, stay silent otherwise, sound irregular across two lifts,
and layer cleanly under the bed + turbo flutter.

---

## 7. Risks / gotchas

1. **Ordering vs `_prev_throttle`.** `_update_overrun()` reads `_prev_throttle`
   and must be called **before** `:379` overwrites it, exactly like
   `_update_turbo()` (comment at `:369-375`). Insert at `:375`; do not reorder.
2. **Do not disturb the lift nudge or the turbo BOV/flutter.** They share the same
   lift edge (`:306,313,377`). The pop layer is purely additive; a regression here
   breaks three existing features at once. `test_engine_audio` /
   `test_turbo_audio` are the guards.
3. **QOA loop-end trap.** Not a risk *if* pops are runtime-built
   `AudioStreamWAV`s (§3.1), which sidesteps the importer entirely. If the
   executor pivots to shipped WAVs (option B), it **must** follow
   `load_turbo_assets()` (`:808-825`) and leave one-shots at `loop_end = 0`
   (`LOOP_DISABLED`), or playback silently no-ops.
4. **gdUnit warnings-as-errors.** Declare explicit types (`var s := ... as
   AudioStreamWAV`, `var n: int = int(...)`); never `:=` from a `Variant`. A
   suite aborts at first failure — compare executed counts to `func test_`.
5. **Determinism vs variety.** Tests pin a seed to get byte-identical output; the
   runtime RNG must be a **member** (`_pop_rng`) that tests can seed, defaulting
   to `DEFAULT_POP_SEED` for reproducible default behaviour. Do not use the global
   `randi()` (non-deterministic across runs → flaky tests).
6. **Perf / voice count.** One extra `AudioStreamPlayer3D` per enabled car
   (vs 5 beds + up to 3 turbo already). The static bank cache means PCM is built
   once, not per car. `max_distance`/existing cull still bound 3D mixing. Watch
   the relative-mode `perf_gate` blind spot (AGENTS.md).
7. **Master-bus LPF.** The burst routes through the player's global LPF (it is
   unavoidable and correct); do **not** add a per-car bus effect — regression
   would be an audio-quality and teardown disaster (`_remove_lpf` assumes single
   ownership, `:863-873`).
8. **Headless guard.** Mirror `should_create_turbo_players` (`:797-800`) so no pop
   player exists under `"headless"` — otherwise headless suites pay for synthesis
   and can flake.
9. **Intensity clamping is load-bearing.** `exhaust_pop_intensity` must be clamped
   `[0,2]` inside the builders so a bad `.tres` cannot produce a clip or an
   unbounded pop count.

---

## 8. Open issues deferred to the user

1. **Which cars get it?** The plan enables `crackle` on the GT-R R35 only. Decide
   the wider rollout (other turbos? the rally hatch? muscle V8 → `burble`?).
2. **Volume taste.** Default `-6 dB` layer trim and the `bang` vs `crackle` split
   are ear-tuned starting points, not measurements — confirm by playtest.
3. **Real recordings.** If the user supplies pop/crackle audio (as they did for
   `wrx_turbo.mp3` / `sututututch.mp3`), swap option A for option C behind the
   same event API — no plan rework.
4. **Exhaust state coupling.** Real pops also depend on exhaust temperature and
   aftermarket valved exhausts; a future pass *could* gate intensity on a
   simulated cat/exhaust temperature. Explicitly out of scope here.

---

## 9. Execution contract

**Read first (in this order):** this plan; `scripts/audio/engine_audio.gd`
(whole file — the layer lives here); `scripts/vehicle/car_config.gd:48-58`;
`tests/suites/test_turbo_audio.gd` (the suite to model on);
`docs/GDUNIT_GATE.md` (the gate recipe); AGENTS.md (shell traps:
cmd.exe on the PC / PowerShell on the laptop, **no** `head`/`grep`/`ls`/`cat` —
use `tools\pick.bat` or the `read`/`grep`/`glob` tools).

**Evidence rules.**
- `graphify-out/graph.json` **cannot see GDScript** (§2 preamble) — go straight to
  the source; every claim must carry a `file:line`.
- **Never assert wall-clock time** in the new suite.
- Do not present APPROXIMATE tuning numbers (§3.1) as measured fact.
- Verify the anchors (`:375`, `:377-379`, `:402`, `car_config.gd:58`) on the live
  tree before editing — line numbers here are the verified baseline and may have
  drifted.

**Gate recipe** (see `docs/GDUNIT_GATE.md` for the cmd forms): resolve the
**console** binary via `godot_path.bat`, run the `--headless --import .` probe
**first** (zero `SCRIPT ERROR`/`Parse Error`), then each targeted suite with its
own `-a` (comma-joined paths false-green and exit 0), then the full suite via
`py tools\gdunit_parallel.py -j 4` as a **background** sub-agent. One Godot
process at a time; never run the gate beside another Godot process.

**Do not:** run Godot/the gate in this *planning* session (already done — nothing
was run); edit `.tscn` files; touch `scripts/ui/**` or `scripts/track/**`; run
`graphify update .` from this planning session (the executor does it after coding);
add a bus effect; or re-tune the existing lift/turbo logic.

---

## 10. STATUS — PHASES 1–4 DONE (targeted gate green); phase 5 partial

- [x] Phase 1 — CarConfig knobs (`scripts/vehicle/car_config.gd:60-70`, 6 new
      `@export`s: `exhaust_pop_enabled/style/intensity/min_rpm_fraction/duration/gain_db`;
      all OFF/neutral by default, so existing `.tres` are byte-identical).
- [x] Phase 2 — pure static builders in `scripts/audio/engine_audio.gd`
      (`POP_*` consts, `normalize_pop_style`, `pop_count_for`, `pop_duration_for`,
      `overrun_should_fire`, `pop_pitch_jitter`, `pop_bank_key`,
      `should_create_pop_players`, `build_pop_burst`; statics block at `:919-1111`).
- [x] Phase 3 — wired into `_physics_process` (`_ensure_pop_layer` `:313`,
      `_update_overrun` `:365`, `_fire_overrun` `:381`; calls at `:465-466`,
      between `_update_turbo()` and the lift-edge block so `_prev_throttle` is read
      before it is overwritten — same ordering rule as the turbo layer).
- [x] Phase 4 — GT-R R35 opted in (`resources/cars/nissan_gt_r35_2017.tres`:
      `exhaust_pop_enabled = true`, `exhaust_pop_style = "crackle"`,
      `exhaust_pop_gain_db = -6.0`; the other three knobs stay default).
- [x] Rollout (2026-10-20, user decision) — **rally hatch** opted in as the second
      car: `resources/cars/rally_hatch.tres` `exhaust_pop_enabled = true`,
      `exhaust_pop_style = "bang"` (anti-lag character, matching
      `engine_timbre = "rally"`), `exhaust_pop_gain_db = -6.0`. It ships **no**
      turbo flags, so the burst does not share the lift edge with a flutter
      one-shot; other knobs stay default. Locked by
      `test_exhaust_pops.gd > test_rally_config_enables_bang`. Remaining cars
      (`muscle_car`, `cc0_race`, the three stock CC0 cars) stay opted out.
- [~] Phase 5 — targeted gate GREEN; parallel gate + `graphify update .` + playtest
      owned by the main session / user (see evidence below).

**Evidence (targeted gate, `--headless --import .` probe then seven suites in one
`GdUnitCmdTool.gd` command, one `-a` each):**

- import probe: exit 0, no `SCRIPT ERROR`/`Parse Error` from project code (only the
  known-benign Terrain3D `double_slider.gd:25`).
- `test_exhaust_pops.gd` **12 cases | 0 failures** (new suite, `tests/suites/test_exhaust_pops.gd`).
- guards: `test_engine_audio` 55, `test_turbo_audio` 8, `test_car_audio` 18,
  `test_audio_feel_layers` 14, `test_car_sound_profiles` 20, `test_rival_car_audio` 9
  — all 0 failures.
- **Overall Summary: 136 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped |
  0 orphans** (136/136 executed), exit 0.

**Deviation from the plan (recorded):** `_update_overrun()` was authored as
`func _update_overrun(cfg, rpm_norm, throttle, gear, delta)` — the plan's `info`
parameter was dropped because it was unused and an unused parameter risks a
gdUnit warnings-as-errors abort. No behaviour change; the layer reads nothing it
does not need.

**Not yet done (by contract):** the full parallel gate (`py tools\gdunit_parallel.py
-j 4`) and `graphify update .` are the main session's job; the manual playtest
criteria (audible fire on an R35 high-rpm lift, silent otherwise, irregular across
two lifts, layers cleanly under bed + flutter) can only be judged by the user.

**STATUS: PHASES 1–4 SHIPPED — targeted gate green (136/136, exit 0).**

**Addendum (2026-10-20) — rollout extended to a second car, re-verified.**

- `test_exhaust_pops.gd` grew **12 → 13 cases** (`test_rally_config_enables_bang`
  locks the rollout). Re-run in one command with `test_car_sound_profiles` and
  `test_car_default_setup` after an import probe: **44/44 executed | 0 errors |
  0 failures**, exit 0; probe error list unchanged (only the Terrain3D
  `double_slider.gd:25` addon line).
- **Gate coverage caveat, stated plainly:** the last whole-tree parallel gate
  (1403 tests | 0 errors | 1 failure, the pre-existing `test_post_race_cinematic.gd:239`)
  ran **before** this rollout change and therefore does **not** include the new
  13th case. The tree is now 1404 tests and is unverified as a whole.
- Armed so far: GT-R R35 (`crackle`) and rally hatch (`bang`), both −6 dB.
  Everything else stays at the `false` default.


---

## Sources (cited inline)

Verdicts in §3 are engineering decisions; the sources below support the *physical
cause* and *technique* framing. Numeric values lifted from them are marked
APPROXIMATE and are ear-tuned starting points, not measurements.

- [S1] scienceabc — "How Do Cars Shoot Flames From Their Exhaust" (unburnt fuel
  igniting in a hot exhaust on decel). https://www.scienceabc.com/innovation/how-do-cars-shoot-flames-from-their-exhaust
- [S2] tuning-database.co.uk — "How Pops & Bangs Maps Actually Work" (ignition
  retard ATDC, overrun fuel-cut disable, fuel vs spark cut).
  https://www.tuning-database.co.uk/how-pops-bangs-maps-work-technical-breakdown
- [S3] finishlineremaps.co.uk — "Pops and Bangs Map Explained".
  https://finishlineremaps.co.uk/blog/pops-bangs-explained
- [S4] tempadrive.com — BMW pop/bang/crackle map guide (OEM deliberate pops;
  drive-mode dependence). https://tempadrive.com/en/blog/bmw-pop-bang-crackle-map-explained
- [S5] rs25.com — "Mysterious Anti-Lag Systems Explained".
  https://www.rs25.com/threads/mysterious-anti-lag-systems-explained.65532
- [S6] High Performance Academy — ALS fuel-limit vs spark-limit discussion.
  https://www.hpacademy.com/forum/motec-m1-software-tutorial/show/als-anti-lag-on-link-ecus
- [S7] SAE 2014-01-1504 — fuel-cut catalyst ageing / retardation.
  https://saemobilus-test.cld.sae.org/papers/a-comparison-fuel-cut-ageing-retardation-fuel-cut-acceleration-2014-01-1504
- [S8] TCEQ — catalytic-converter fire / over-temperature.
  https://www.tceq.texas.gov/airquality/mobilesource/vetech/catfire.html
- [S9] Wikipedia — "Back-fire".
  https://en.wikipedia.org/wiki/Back-fire
- [S10] Formula 1 Dictionary — off-throttle exhaust blowing.
  https://www.formula1-dictionary.net/f1-off-throttle-exhaust-blowing
- [S11] Autosport — "Banned: when exhaust-blown diffusers reigned supreme".
  https://www.autosport.com/f1/news/banned-when-exhaust-blown-diffusers-reigned-supreme-4982364/4982364/
- [S12] puresoundonly.com — deceleration exhaust-pop physics.
  https://puresoundonly.com/en/blog/exhaust-pop-crackle-deceleration
- [S13] BeamNG — Engine Sound Tuning (afterfire).
  https://documentation.beamng.com/modding/vehicle/sections/sounds/engine_audio/
- [S14] BeamNG — Exhaust node modifier (`afterFireAudioCoef` / `VolumeCoef` /
  `MufflingCoef`). https://documentation.beamng.com/modding/vehicle/sections/nodes/exhaust
- [S15] Gran Turismo 7 — GDC 2024 sound talk (PDF).
  https://s3.amazonaws.com/gran-turismo.com/pdi_publications/GDC_2024_GT7_SOUND.pdf
- [S16] LTU thesis — "Evaluation of Car Engine Sound Design Methods in Video
  Games" (PDF). https://ltu.diva-portal.org/smash/get/diva2%3A1557027/FULLTEXT01.pdf
- [S17] Audiokinetic — engine-sound modeling, sampling → granular synthesis.
  https://www.audiokinetic.com/en/community/blog/engine-sound-modeling-from-sampling-to-granular-synthesis-in-wwise
- [S18] designingsound.org — vehicle engine design for Project CARS / Forza / REV.
  https://designingsound.org/2014/08/11/vehicle-engine-design-project-cars-forza-motorsport-5-and-rev
- [S19] Wikipedia — "Granular synthesis".
  https://en.wikipedia.org/wiki/Granular_synthesis
- [S20] asoundeffect.com — game-audio immersion / avoiding repetition.
  https://www.asoundeffect.com/game-audio-immersion/
- [S21] sonusgearflow.com — procedural granular synthesis in game audio.
  https://sonusgearflow.com/sounddesign/procedural-granular-synthesis-in-game-audio
- [S22] forza.net — Forza Motorsport audio updates (layered/randomised engine
  audio). https://forza.net/news/forza-motorsport-audio-updates

**Explicitly not used as evidence:** a PubMed "crackle" study surfaced during
research (`https://pubmed.ncbi.nlm.nih.gov/6722363`) is about **lung** crackles in
fibrosing alveolitis (100–2000 Hz), **not** exhaust — it is unrelated and is
recorded here only so no future reader mistakes it for exhaust acoustic data.
