# Fix plan — MANUAL respawn affects every car + reverse has no power on slopes

**Status:** PLANNING COMPLETE — ready for implementation (no code changed yet).
**Scope:** 2 playtest bugs, 2 files edited, 2 new GDUnit suites.
**Rule for the implementer:** this document is the contract. The "Do NOT touch"
list (§6) is as binding as the steps (§3). All file:line references are
**pre-edit** — re-locate by context after the first edit shifts lines.

---

## 0. Decisions at a glance

| | Bug 1 — "respawn everyone" | Bug 2 — reverse has no power on slopes |
|---|---|---|
| Root cause | `vehicle_physics.gd:241` fires `respawn_at()` for **every** `VehiclePhysics` on the reset key; identity is never checked | Reverse combined ratio is 51% of 1st, engine is pinned to idle torque at rest, the analog curve squares partial pedal, and nothing compensates gravity — so grade demand beats available force at partial throttle, and traction kills low-grip slopes outright |
| Fix | Two seams: `can_manual_respawn()` (player-car identity + override check) and `try_manual_respawn(reset_pressed, controls_locked)`; fall-through-world safety at `:213` stays universal | Two data-driven knobs in `CarConfig`: `reverse_torque_multiplier` 1.5 → 2.2, plus a new low-speed **reverse grade assist** force that cancels a configured fraction of gravity along the chassis while in R under throttle |
| Files | `scripts/vehicle/vehicle_physics.gd` | `scripts/vehicle/car_config.gd`, `scripts/vehicle/vehicle_physics.gd` |
| NOT changed | `respawn_at()`, fall safety, input bindings | `drivetrain.gd` (all of it), forward gears, `reverse_ratio`, analog curve |

---

## 1. Root cause analysis

### Bug 1 — "When I respawn, don't respawn everyone, just me"

* `scripts/vehicle/vehicle_physics.gd:241-243` — inside the shared
  `_physics_process()` of **every** car (player, rivals, traffic):

  ```gdscript
  # --- Reset car ---
  if not controls_locked and InputManager.is_reset():
      respawn_at(_spawn_point)
      return
  ```

  The gate checks only *key state* and *race lock* — never **which car** is
  asking. Every `VehiclePhysics` on the map polls the same global key and
  teleports itself to its own `_spawn_point` (per-car, set at
  `vehicle_physics.gd:126` in `_ready`), so one keypress snaps the whole
  traffic field back to spawn.
* Key plumbing: `autoload/input_manager.gd:35-36`
  (`is_reset() == Input.is_action_just_pressed("reset_car")`; action bound at
  `project.godot:74`). A repo-wide grep shows this is the action's **only**
  consumer, and `respawn_at()` (`vehicle_physics.gd:755-771`) is called from
  exactly two sites: the fall safety (`:214`) and this key branch (`:242`).
* Player identity already exists: `scripts/player/player_car_controller.gd:23`
  → `VehicleManager.register_player_car()` (`autoload/vehicle_manager.gd:11-15`),
  read back via `VehicleManager.get_player_car()` (`:27-28`,
  `var player_car` at `:8`). It is simply never consulted here.
* AI/traffic always drive through a **non-zero** `input_override`
  (`ai_controller.gd:238-240` refuses to write ZERO; `traffic_driver.gd:78-116`),
  so an identity-or-override check cleanly separates human cars from scripted
  ones.
* Pre-existing behaviour that must be **preserved**: the early returns at
  `vehicle_physics.gd:188-200` mean a frozen/`_awaiting_ground` car ignores
  the key (unchanged); the fall safety at `:213-215`
  (`global_position.y < -20.0 → respawn_at(_spawn_point)`) is a universal
  self-rescue and must keep firing for **all** cars regardless of identity or key
  state. `reset_car()` at `:748-753` is dead code (no callers) — leave it.

### Bug 2 — "Not enough power in reverse; stuck in corners with slopes"

Verified against the starter car **Striker** (`resources/cars/starter_car.tres`:
mass 1100 kg, max_torque 180 Nm, gear_ratios[0]=6.22, final_drive_ratio=3.8;
`reverse_ratio` 3.2 from `car_config.gd:55` — the .tres does not override it).
Wheel radius 0.33 m (`drivetrain.gd:103`). Grade demand = 1100·9.8·sin θ.

**(a) Reverse gearing delivers half the force of 1st.**
Combined ratios (`car_config.gd:196-203`): 1st = 6.22×3.8 = **23.64**,
R = 3.2×3.8 = **12.16** (51.5% of 1st). The existing multiplier
`reverse_torque_multiplier = 1.5` (`car_config.gd:56`, applied at
`drivetrain.gd:157-158`) only partially closes the gap.

**(b) At rest the engine can never rev — torque is frozen at idle value.**
`drivetrain.gd:111-112`: `engine_rpm = move_toward(..., max(rpm_from_wheels, idle_rpm), ...)`
— wheel speed 0 ⇒ rpm settles at idle 800 ⇒ `get_engine_torque(800)` returns
`max_torque * 0.5 = 90 Nm` (`car_config.gd:183-190`, linear ramp starts at
half torque). Rest, full pedal axle force:

| Gear | axle torque | tire force |
|---|---|---|
| 1st | 90 × 23.64 = 2127 Nm | **6446 N** |
| R @ multiplier 1.5 | 90 × 12.16 × 1.5 = 1642 Nm | **4974 N** |
| R @ multiplier 2.2 (planned) | 90 × 12.16 × 2.2 = 2408 Nm | **7296 N** |

Grade demand: 12° → 2241 N, 15° → 2790 N, 20° → 3689 N.

**(c) The analog curve squares the pedal — feathered throttle stalls instantly.**
`vehicle_physics.gd:232-234` runs player throttle through
`apply_analog_response` (`:558`, power 2.0 from `ANALOG_RESPONSE_POWER` `:50`).
Half trigger → ~0.25 throttle → old R force ≈ 1244 N → **stalls on any slope
steeper than ≈6.6°**. This is the exact "stuck in corners" feel: on corner
exit you are never at full pedal, and lateral grip load consumes the traction
budget on top of that.

**(d) Low-grip slopes are traction-limited, not torque-limited.**
Measured during investigation (rear-axle share, arcade grip): dry asphalt
≈6551 N longitudinal capacity, snow (μ 0.30) ≈1916 N. Snow at 15° demands
2790 N > 1916 N ⇒ **no torque multiplier can ever fix it** — the force has to
come from somewhere traction cannot gate. That is what the grade assist
(§2-D5) is for.

**(e) Known residual (out of scope):** `drivetrain.gd:96-97` pops R → 1
whenever `_wheel_speed > 0.5` (forward). On a slope a gravity slide can
cross 0.5 m/s forward, ejecting R so reverse inputs drive 1st instead. This
behaviour is **deliberately pinned** by
`tests/suites/test_brake_stop_holds_first.gd:77` and
`tests/suites/test_manual_transmission_default.gd:186` (both feed 0.6 m/s and
expect gear 1). Changing the threshold means consciously rewriting those
tests — deferred, see §5-R6.

**Verified non-causes:** the multiplier *is* applied on the throttle path
(`drivetrain.gd:157-158`, gated only by `engine_braking = throttle < 0.05`,
`:125`); `reverse_ratio` *is* used (`car_config.gd:200-201`); no `.tres`
overrides either. Nothing is "broken" — the numbers are simply too small.

---

## 2. Design decisions & rationale

**D1 — Gate MANUAL respawn on player-car identity, via two small seams.**
`can_manual_respawn()` + `try_manual_respawn(reset_pressed, controls_locked)`.
Taking the key/lock state as **parameters** makes the seam unit-testable
without mocking the `Input` singleton — the caller keeps polling
`InputManager.is_reset()` exactly as before, so live key behaviour is
byte-identical for the player.

**D2 — Identity rule: registered player car AND `input_override == ZERO`; if no
player is registered at all, fall back to `input_override == ZERO`.**
Rationale: (i) identity alone would let a player-controlled car that is
temporarily scripted (autopilot-style `input_override`) be teleported by a
human keypress — the override check forbids that; (ii) the null-player
fallback keeps the key working in bare test scenes / registration gaps for a
genuinely human-driven car; (iii) scripted rivals can never hit the fallback
because AI/traffic always hold a non-zero override. Net effect: exactly the
player's car respawns in every real game state.

**D3 — Fall-through-world safety (`:213-215`) stays universal and untouched.**
It is a self-rescue, not a player command; gating it would strand broken
rivals in the void. Its per-car `_spawn_point` semantics are unchanged.

**D4 — Raise `reverse_torque_multiplier` 1.5 → 2.2 in `CarConfig` only; do NOT
touch gearing.** Rejected alternatives: raising `reverse_ratio` squeezes the
headroom that `tests/test_vehicle_physics.gd:69-73` requires (reverse combined
< 1st) and changes reverse top-end character; changing the torque curve/idle
behaviour (`drivetrain.gd:111-112`) is shared with forward launch and has a
huge regression surface; changing `ANALOG_RESPONSE_POWER` alters brake/steer
feel too. The multiplier is a single per-car number, already understood by the
codebase, and 2.2 lifts rest full-pedal reverse force to 7296 N — above 1st's
6446 N, which is safe because reverse is speed-capped at 30 km/h
(`drivetrain.gd:163-167` zeroes torque above the cap regardless).

**D5 — New `reverse_grade_assist`: a low-speed FORCE cancelling a fraction of
gravity along the chassis, only in gear −1, only under throttle, only grounded,
speed-faded to zero at 20 km/h.** This is the only lever that helps the
traction-limited case (D4/d above): applied to the **body** via
`apply_central_force`, it is not gated by tire μ, yet it can never *add*
energy beyond cancelling gravity (fraction clamped to [0,1]). Design points,
each with a reason:
- **Cancels gravity along the chassis axis** (`Vector3.DOWN · forward`), so it
  is orientation-independent and exactly **zero on flat ground** — flat-circuit
  and all forward behaviour stay byte-identical.
- **Gate on `throttle >= 0.05` but do NOT scale by throttle magnitude** — the
  failure case is *feathered* pedal; a half-pedal hill-start must get the full
  configured fraction. The 0.05 threshold mirrors `engine_braking` at
  `drivetrain.gd:125` exactly, so assist and multiplier switch on/off on the
  same pedal position (off-throttle coasting and engine-brake feel untouched).
- **Grounded gate (any wheel `is_in_contact`, `wheel_physics.gd:45`)** — in the
  air there is no grade to cancel; without this the assist would be an
  unintended flight-buff.
- **Speed fade to 0 at `reverse_grade_assist_max_speed_kmh` (20 < 30 cap)** —
  assist exists for hill starts / corner exits ≤ ~20 km/h; the reverse top
  speed and any high-speed feel are structurally unaffected.
- **Never fires for rivals** — gear R is player-selected only
  (`drivetrain.gd:86-97`; shift inputs route only when
  `input_override == ZERO`, `vehicle_physics.gd:272-276`), so AI/traffic never
  reach `current_gear < 0`. The gear check in the wrapper enforces it anyway.
- **Data lives in `CarConfig`** (two new `@export`s) — per-car tunable,
  `.tres`-overridable, `with_overrides()` clones via `duplicate(true)`
  (`car_config.gd:171-179`) so tuned/event cars inherit it automatically, and
  tests can assert numbers deterministically.

**D6 — Pure static core + thin instance wrapper.**
`static func reverse_grade_assist_force(forward, mass, fraction, throttle,
speed_kmh, max_speed_kmh) -> Vector3` holds all math (testable with zero scene
setup); `compute_reverse_grade_assist(throttle, forward_speed)` wraps it with
the gear/ground gates and reads `config`/`mass`/`global_basis`. The call site
stays a two-liner.

**D7 — Apply in `_physics_process` right after `_drivetrain.update(...)`** as
`apply_central_force` (Newtons, every tick — matching the existing aero force
pattern at `vehicle_physics.gd:437`), NOT `apply_impulse` (frame-rate
dependent).

**D8 — Two new suites land together with the code** (they reference new
methods and would not parse otherwise). Both follow the house style:
`_managed_nodes` + `VehicleManager.player_car = null` cleanup,
`assert_that(...).is_equal`, scene_runner only where a body is genuinely
needed.

---

## 3. Step-by-step implementation

> Steps 1→2→3 must land in one change-set; step 4 is the gate.

### Step 1 — `scripts/vehicle/car_config.gd`

1a. Line 56, raise the multiplier (keep the comment honest):

```gdscript
@export var reverse_torque_multiplier: float = 2.2  # extra torque multiplier for reverse on steep climbs
```

1b. Directly after line 57 (`max_reverse_speed_kmh`), add:

```gdscript
## Fraction of gravity ALONG THE CHASSIS cancelled by the reverse grade
## assist while reversing under throttle (0 = off, 1 = full gravity cancel).
## Force-based and body-applied, so it works where tire traction cannot move
## the car (low-grip slopes); clamped to [0,1] internally so it can never add
## energy beyond cancelling gravity. Zero on flat ground.
@export var reverse_grade_assist: float = 0.5
## Speed in km/h at which the reverse grade assist has faded to zero. Kept
## below max_reverse_speed_kmh (30) so the reverse cap and top-speed feel are
## untouched — the assist only covers hill starts / corner exits.
@export var reverse_grade_assist_max_speed_kmh: float = 20.0
```

No other car file changes. No `.tres` edits (defaults flow to every car;
per-car overrides remain possible later).

### Step 2 — `scripts/vehicle/vehicle_physics.gd`, respawn seams

2a. **Replace lines 240-243** (the `# --- Reset car ---` block) with:

```gdscript
    # --- Reset car (MANUAL respawn is PLAYER-only; the fall-through-world
    # safety above stays universal) ---
    if try_manual_respawn(InputManager.is_reset(), controls_locked):
        return
```

2b. **Add both seams directly above `respawn_at()`** (before current line 755):

```gdscript
## Whether THIS car may respond to the manual reset key. Only the registered
## player car respawns on demand (the key used to teleport EVERY VehiclePhysics
## on the map); a scripted car (input_override != ZERO) never does, even if it
## currently holds the player identity. If NO player is registered (bare test
## scene, registration gap) fall back to the input check so a human-driven car
## can still be rescued by the key - scripted cars always carry a non-zero
## override, so they can never match that fallback either.
func can_manual_respawn() -> bool:
    if input_override != Vector2.ZERO:
        return false
    var player := VehicleManager.get_player_car()
    if player == null:
        return true
    return player == self

## Seam for the reset key: key/lock state are parameters so tests drive it
## without mocking the Input singleton. Returns true when it actually
## respawned (the caller then stops the frame).
func try_manual_respawn(reset_pressed: bool, controls_locked: bool) -> bool:
    if not reset_pressed or controls_locked:
        return false
    if not can_manual_respawn():
        return false
    respawn_at(_spawn_point)
    return true
```

Fall safety at `:213-215` is **not** touched.

### Step 3 — `scripts/vehicle/vehicle_physics.gd`, grade assist

3a. **Static core** — add next to the other statics, right after
`apply_analog_response()` (~line 558):

```gdscript
## Cancels `fraction` of gravity projected on `forward` (the chassis nose
## direction), so a reversing car can hold/creep up grades whose gravity
## component beats its idle-revved engine. Pure and orientation-independent:
## exactly ZERO on flat ground (forward.y == 0), below the 0.05 throttle gate
## (mirrors Drivetrain's engine-braking gate), at/above max_speed_kmh (linear
## fade), or when fraction <= 0; `fraction` is clamped to [0, 1] so the assist
## can never inject energy beyond cancelling gravity.
static func reverse_grade_assist_force(
        forward: Vector3, mass: float, fraction: float,
        throttle: float, speed_kmh: float, max_speed_kmh: float) -> Vector3:
    var f := clampf(fraction, 0.0, 1.0)
    if f <= 0.0 or throttle < 0.05 or max_speed_kmh <= 0.0:
        return Vector3.ZERO
    var speed_scale := 1.0 - clampf(absf(speed_kmh) / max_speed_kmh, 0.0, 1.0)
    if speed_scale <= 0.0:
        return Vector3.ZERO
    var fwd := forward.normalized()
    var gravity_along_fwd := Vector3.DOWN.dot(fwd) * 9.8  # signed m/s^2
    return -fwd * (mass * gravity_along_fwd * f * speed_scale)
```

Sign check (the case that matters): nose pointing **down**-slope
(`fwd.y < 0`) ⇒ `gravity_along_fwd > 0` (gravity pushes the car away, downhill)
⇒ result = `-fwd · positive` = up-slope, the reverse direction. Nose
up-slope ⇒ the result cancels gravity's *help* instead — symmetric grade
flattening, never an energy source (magnitude ≤ `mass·9.8·|fwd.y|` always).

3b. **Instance wrapper + grounded helper** — directly after the static:

```gdscript
func _any_wheel_grounded() -> bool:
    if _wheels == null:
        return false
    for wheel in _wheels:
        if wheel.is_in_contact:
            return true
    return false
```

```gdscript
## Instance seam for the reverse grade assist: gear + ground gates, then the
## pure core fed from config/body state. forward_speed is the signed chassis
## speed (m/s) - abs() inside the core fades the assist out either direction.
func compute_reverse_grade_assist(throttle: float, forward_speed: float) -> Vector3:
    if _drivetrain.current_gear >= 0:
        return Vector3.ZERO
    if not _any_wheel_grounded():
        return Vector3.ZERO
    return reverse_grade_assist_force(
        -global_basis.z, mass, config.reverse_grade_assist,
        throttle, forward_speed * 3.6,
        config.reverse_grade_assist_max_speed_kmh)
```

(`_wheels: Array[WheelPhysics]` is declared at `:94`. Use the body's `mass`
property — gravity acts on body mass, and config/body masses are synced.)

3c. **Call site** — insert immediately after line 277
(`var drive_info := _drivetrain.update(delta, throttle, config)`), before the
surface/grip block:

```gdscript
    # --- Reverse grade assist: cancel `fraction` of gravity along the chassis
    # while reversing under throttle, grounded and below the speed fade, so
    # slope starts the idle-revved engine cannot hold become climbable. Zero
    # on flat ground; rivals never enter gear -1 (player-selected only).
    var grade_assist := compute_reverse_grade_assist(_throttle_input, forward_speed)
    if grade_assist != Vector3.ZERO:
        apply_central_force(grade_assist)
```

`forward_speed` (computed at `:256`) and `_throttle_input` (set at `:235`,
post-curve, clamped 0..1) are both in scope. `controls_locked` needs no extra
check: throttle is 0 while locked (`:222`), so the 0.05 gate already excludes
race countdown.

### Step 4 — verification (see §7) + `graphify update .` + STATUS flip here.

---

## 4. New / updated GDUnit tests (`tests/suites/`)

House rules every test must follow: **typed locals** (GDScript warnings are
errors — never `:=` from a Variant/Dictionary), `assert_that(...).is_equal`,
vector `is_equal_approx` needs a **same-type** epsilon
(`Vector3(0.01, 0.01, 0.01)`), split `functions` into
`pre_check`/`check_part_a`/`check_part_b` only when frames are needed, and
free managed nodes + clear `VehicleManager` in `after_test`.

### 4.1 NEW — `tests/suites/test_respawn_player_only.gd`

Header comment: bug repro ("pressing reset teleported every car on the map to
its spawn"), the seam (`can_manual_respawn` / `try_manual_respawn`), and the
invariant (fall safety stays universal).

Fixtures (mirror `test_ground_latch.gd`):

```gdscript
const TEST_SCENE := "res://scenes/test/test_vehicle_physics.tscn"
var _managed_nodes: Array = []

func _make_rival(spawn_pos: Vector3) -> VehiclePhysics:
    var holder := Node3D.new()
    get_tree().root.add_child(holder)
    _managed_nodes.append(holder)
    var car: VehiclePhysics = (load("res://scenes/vehicle/player_car.tscn") as PackedScene).instantiate() as VehiclePhysics
    var ctrl := car.get_node_or_null("PlayerCarController")
    if ctrl != null:
        ctrl.free()   # BEFORE add_child: otherwise it self-registers as player
    car.position = spawn_pos                      # _spawn_point captures this in _ready
    holder.add_child(car)
    return car
```

`after_test`: free `_managed_nodes`, `VehicleManager.player_car = null`,
`VehicleManager.all_cars.clear()`, **`Input.action_release("reset_car")`**
(a failed test must not leak a pressed key into later suites).

| # | Test | Arrange → Act → Assert |
|---|---|---|
| 1 | `test_player_car_respawns_on_manual_reset` | scene_runner, `simulate_frames(10)` (latch release), grab `PlayerCar`, explicit `VehicleManager.register_player_car(player)`; teleport to `(-20, 3, -20)`; call `try_manual_respawn(true, false)` → **true**; immediately: `linear_velocity == Vector3.ZERO` and `_last_valid_position` `is_equal_approx(_spawn_point + Vector3.UP, Vector3(0.01,0.01,0.01))` (exact — `respawn_at` writes it synchronously, `:768`); after `simulate_frames(1)`: `global_position.distance_to(_spawn_point + Vector3.UP) < 2.0`. |
| 2 | `test_rival_with_scripted_input_ignores_manual_reset` | scene car registered as player; rival at spawn `(30, 2, 0)`, `rival.set_input_override(Vector2(0.0, 0.5))`; teleport rival to `(-20, 3, 20)`; `try_manual_respawn(true, false)` → **false**; after 3 frames: `rival.global_position.distance_to(rival._spawn_point) > 40.0` (a respawn would put it within ~2 m of its spawn). |
| 3 | `test_non_player_human_car_ignores_reset_when_player_registered` | same as 2 but rival `input_override == ZERO` — proves the **identity** gate alone (a second human-driven car never eats the key). Same distance assert. |
| 4 | `test_player_with_scripted_input_ignores_manual_reset` | player registered but `set_input_override(Vector2(0.0, 0.8))` → `try_manual_respawn(true, false)` **false**, position unmoved. |
| 5 | `test_controls_locked_blocks_manual_reset` | player, `try_manual_respawn(true, true)` → **false**, unmoved. |
| 6 | `test_reset_not_pressed_returns_false` | player, `try_manual_respawn(false, false)` → **false**, unmoved. |
| 7 | `test_unregistered_human_car_respawns_when_no_player` | `VehicleManager.player_car = null`, car `input_override == ZERO` → **true** (documents the D2 fallback); and with non-zero override → **false**. |
| 8 | `test_reset_key_respawns_player_and_no_one_else` | **End-to-end wiring**: settle both cars (10 frames), register player, teleport player to `(-20,3,-20)` and rival (spawn `(30,2,0)`) to `(-20,3,20)`; `Input.action_press("reset_car")` → `simulate_frames(1)` → `Input.action_release("reset_car")` → 2 more frames; assert player `distance_to(_spawn_point + Vector3.UP) < 2.0` and rival `distance_to(_spawn_point) > 40.0`. |
| 9 | `test_fall_through_world_respawn_still_universal` | **Do-not-touch guard**: rival (not player, scripted override) → `rival.global_position.y = -30.0` → `simulate_frames(5)` → `rival.global_position.y > -5.0` (its own fall safety fired, ungated by identity/key). |

Pre-fix behaviour: 2, 3, 8, 9 differ on the old tree (rivals DID respawn —
9 passes pre-fix by definition; it guards the *fix* from over-reaching).
1, 4-7 pass pre-fix too (behaviour preservation for the player path).

### 4.2 NEW — `tests/suites/test_reverse_grade_power.gd`

Fixtures: `const STARTER_CONFIG: CarConfig = preload("res://resources/cars/starter_car.tres")`,
`const DT := 1.0 / 60.0`, `const WHEEL_RADIUS := 0.33  # mirrors drivetrain.gd`,
`_new_reverse_drivetrain()` helper: manual `Drivetrain`, `shift_down(STARTER_CONFIG)`,
`is_shifting = false`, per the existing `_new_manual_drivetrain()` pattern in
`test_low_speed_reverse_handling.gd:44-47`.

Pure tests (no scene):

| # | Test | Assertions |
|---|---|---|
| 1 | `test_starter_reverse_torque_multiplier_is_raised` | `assert_that(STARTER_CONFIG.reverse_torque_multiplier).is_equal(2.2)` — literal gate for the Bug-2(a) knob (fails pre-fix). |
| 2 | `test_reverse_drive_torque_floor_at_idle` | Drive the reverse drivetrain: `for i in range(30): dt.update(DT, 1.0, STARTER_CONFIG)` (rpm settles at idle), assert sign `drive_torque < 0`, wiring equality `absf(dt.drive_torque)` `is_equal_approx` `STARTER.get_engine_torque(dt.engine_rpm) * 1.0 * absf(STARTER.get_gear_ratio(-1)) * STARTER.reverse_torque_multiplier` (eps 1.0), **and** floor `absf(dt.drive_torque) >= 2400.0` Nm (90 × 12.16 × 2.2 = 2408; fails pre-fix at 1642). |
| 3 | `test_half_pedal_reverse_beats_assisted_fifteen_degree_grade` | **The budget gate for the bug.** `var pedal: float = VehiclePhysics.apply_analog_response(0.5)` (real post-curve value, power 2.0); `tire_n = STARTER.get_engine_torque(STARTER.idle_rpm) * pedal * absf(STARTER.get_gear_ratio(-1)) * STARTER.reverse_torque_multiplier / WHEEL_RADIUS`; `grade_n = STARTER.mass_kg * 9.8 * sin(deg_to_rad(15.0))`; `need_n = grade_n * (1.0 - clampf(STARTER.reverse_grade_assist, 0.0, 1.0))`; `assert_that(tire_n).is_greater_or_equal(need_n)` (≈1800 ≥ ≈1395; pre-fix ≈945 — fails). |
| 4 | `test_reverse_assist_config_defaults` | `assert_that(STARTER_CONFIG.reverse_grade_assist).is_equal(0.5)`, `assert_that(STARTER_CONFIG.reverse_grade_assist_max_speed_kmh).is_equal(20.0)`, and `is_less(STARTER_CONFIG.max_reverse_speed_kmh)` for the speed (fade must end below the 30 km/h cap). |
| 5 | `test_grade_assist_zero_on_flat_ground` | `reverse_grade_assist_force(Vector3(0, 0, -1), 1100.0, 0.5, 1.0, 0.0, 20.0)` → `Vector3.ZERO`. |
| 6 | `test_grade_assist_throttle_gate_mirrors_engine_brake_gate` | pitched forward, `throttle 0.0` → ZERO; `0.049` → ZERO; `0.05` → **non-zero** (exact mirror of `drivetrain.gd:125` so torque-multiplier and assist switch on together). |
| 7 | `test_grade_assist_speed_fade_is_linear_to_zero` | pitched, full throttle: `speed_kmh 10` → magnitude exactly 0.5× the `0.0` magnitude (`is_equal_approx`); `20` → ZERO; `25` → ZERO; `-25` (fast backward slide) → ZERO (`abs` in the core). |
| 8 | `test_grade_assist_opposes_gravity_at_12_degrees_downhill_nose` | `fwd = Vector3(0.0, -sin(12°), -cos(12°))`, mass 1100, fraction 0.4, throttle 1.0, speed 0: assert `force.dot(fwd) < 0` (points up-slope, i.e. the reverse direction), `force.length()` `is_equal_approx` `1100.0 * 9.8 * sin(12°) * 0.4` (eps 0.5), and cap invariant `force.length() <= 1100.0 * 9.8 * absf(fwd.y) + 0.001` (never exceeds the gravity component — no energy injection). |
| 9 | `test_grade_assist_flattens_grade_in_both_orientations` | For `fwd.y < 0` and `fwd.y > 0`: with `gravity_along = Vector3.DOWN.dot(fwd) * 9.8`, assert `force.dot(fwd) * gravity_along <= 0.0` (assist always *opposes* the gravity component along the chassis — symmetric flatten, never a push down-slope). |
| 10 | `test_grade_assist_fraction_is_clamped_to_unit` | `fraction 2.0` returns exactly the same vector as `fraction 1.0` (misconfigured car cannot over-cancel gravity). |

Scene tests (`scene_runner(TEST_SCENE)`, `simulate_frames(10)` for latch +
ground contact; body mutation happens **synchronously between awaits**):

| # | Test | Assertions |
|---|---|---|
| 11 | `test_vehicle_assist_requires_reverse_gear` | settle car; nose down: `car.global_basis = Basis(Vector3.RIGHT, deg_to_rad(-12.0))` (rotating −Z about +X by −12° gives `fwd.y = sin(−12°) < 0`); default gear 1 → `car.compute_reverse_grade_assist(1.0, 0.0) == Vector3.ZERO`; set `car._drivetrain.current_gear = -1` → **non-zero**, `dot(-car.global_basis.z) < 0`; set gear back to `1` → ZERO again. |
| 12 | `test_vehicle_assist_gates_on_throttle_speed_and_ground` | gear −1, pitched: `throttle 0.0` → ZERO; `throttle 1.0, forward_speed 6.0` (21.6 km/h > fade) → ZERO; then teleport `car.global_position.y = 50.0`, `simulate_frames(5)` (still airborne, well above the −20 m fall line), `compute_reverse_grade_assist(1.0, 0.0)` → ZERO (grounded gate); settled case with `throttle 1.0, speed 0.0` → non-zero (positive control). |

Pre-fix status: 1, 2, 3 fail on the old tree (that is the gate); 4-12 are new
APIs that only exist post-fix (they parse only with the implementation — tests
land in the same change-set, §2-D8).

### 4.3 Must-stay-green existing suites (regression surface of these edits)

- `tests/test_vehicle_physics.gd` — reverse ratio < 1st (`:69-73`), reverse
  cap (`:103`), shift selects R (`:83-91`); gear-ratio wiring (`:36`).
- `tests/suites/test_brake_stop_holds_first.gd` — R→1 pop-out at 0.6 m/s
  (`:77`), auto shift-down, caps.
- `tests/suites/test_manual_transmission_default.gd` — R selection, pop-out
  (`:186`), caps.
- `tests/suites/test_low_speed_reverse_handling.gd` — engine-brake/brake
  signs in R (sign-only ⇒ unaffected by the multiplier).
- `tests/suites/test_race_countdown.gd` — legacy engine-brake sign at
  standstill (multiplier path is gated by `not engine_braking`, untouched).
- `tests/suites/test_car_default_setup.gd`, `test_hardening.gd` — config
  cloning (`duplicate(true)` carries the new exports automatically) + caps.
- `tests/suites/test_ground_latch.gd` — forward launch/pattern source; also
  proves forward driving is untouched by the assist.
- No existing test pins the literal `1.5` for `reverse_torque_multiplier`
  (grep-verified) — the raise breaks no current assertion.

---

## 5. Risks & gotchas

1. **GDUnit warnings are errors.** Type every local
   (`var pedal: float = VehiclePhysics.apply_analog_response(0.5)` — the
   static has default args, return is float, but be explicit anyway); never
   `:=`-infer from `get_drive_info()` Dictionaries (`float(info["speed_kmh"])`).
2. **Vector `is_equal_approx` needs a same-type epsilon** —
   `assert_that(vec).is_equal_approx(vec2, Vector3(0.01, 0.01, 0.01))`.
3. **Never assert `global_position` in the same frame as `respawn_at()`** —
   the teleport goes through `PhysicsServer3D.body_set_state`
   (`vehicle_physics.gd:767`). Assert `_last_valid_position` immediately
   (written synchronously, `:768`) and `global_position` only after
   `simulate_frames(1)`.
4. **Rival fixture must free `PlayerCarController` BEFORE `add_child`** —
   `_ready` registration (`player_car_controller.gd:23`) would otherwise steal
   player identity mid-test. And every suite must null
   `VehicleManager.player_car` / clear `all_cars` in `after_test` — leaked
   registration poisons unrelated suites.
5. **Release `reset_car` in `after_test`** — `Input.action_press` persists;
   a failed end-to-end test would leak a held key into later suites.
6. **Known residual, do NOT "fix" casually:** the R→1 pop-out at
   `drivetrain.gd:96` (`_wheel_speed > 0.5`) can still eject reverse during a
   forward gravity-slide on a slope. It is pinned as intended behaviour by
   `test_brake_stop_holds_first.gd:77` and
   `test_manual_transmission_default.gd:186`. If playtesting still reports
   "reverse won't engage on slopes", raise this as a **separate** change that
   deliberately rewrites those two tests (e.g. threshold 0.5 → 1.5 m/s or
   throttle-gated), not a drive-by here.
7. **Assist on snow can exceed the tire μ ceiling by design** (body-applied
   force). It is still hard-bounded by `fraction × gravity`, so it can never
   out-accelerate free fall or fire off a slope. Reviewer: this is the
   intended arcade behaviour for D5/D6 low-grip zones — flag it only if
   playtests show cars "climbing impossible walls"; then lower
   `reverse_grade_assist` per-car in the .tres instead of changing code.
8. **Multiplier raise shortens time-to-cap in reverse** (30 km/h cap
   unchanged, `drivetrain.gd:163-167`): reverse now accelerates ~46% harder
   at rest. Intended (it is the bug), but expect tuning feedback; the knob is
   one line in `car_config.gd:56`.
9. **Suite abort semantics** — GDUnit stops a suite at its first failure, so a
   red new suite hides its remaining tests. Read "Executed test cases" vs the
   file's `func test_` count.
10. **Perf gate flake ≠ regression**: if the full gate reports
    `test_perf_gate.gd` failing, read the printed `mode=` line first
    (`ULTRADRIVE_PERF_MODE` two-mode gate, see `docs/GDUNIT_GATE.md`).
11. **Line numbers in this doc are pre-edit** — after Step 2a the old `:241`
    block is gone; locate the reset branch by its comment, and re-derive
    numbers before editing further.

---

## 6. Do NOT touch

- **`scripts/vehicle/drivetrain.gd` — the entire file.** Especially:
  `:96-97` R→1 pop-out (§5-R6), `:111-112` idle RPM pinning, `:125`
  engine-brake gate, `:157-158` multiplier application site (it already works),
  `:163-167` reverse cap, `:103` wheel radius.
- **Forward gearing**: `gear_ratios`, `final_drive_ratio`, auto up/down-shift
  tables — defaults *and* every `.tres`.
- **`reverse_ratio`** (`car_config.gd:55`) — capped by
  `tests/test_vehicle_physics.gd:69-73`.
- **Fall safety** `vehicle_physics.gd:213-215` — universal semantics, and the
  `_awaiting_ground`/freeze early returns at `:188-200`.
- **`respawn_at()` body** (`:755-771`) and dead `reset_car()` (`:748-753`).
- **Input plumbing**: `project.godot` `reset_car` binding, `InputManager`
  (`autoload/input_manager.gd`), the analog curve (`ANALOG_RESPONSE_POWER`
  `:50`, `apply_analog_response` `:558`) — Bug 2(c) is answered by the assist,
  not by rescaling every player input.
- **AI/traffic input machinery**: `ai_controller.gd`, `traffic_driver.gd`,
  `input_override` semantics, `scripted_driver`.
- **`RaceManager.controls_locked()`** semantics and race-countdown behaviour.
- **Existing tests** listed in §4.3 (they encode invariants this fix must
  respect — if one goes red, the *fix* is wrong, not the test).
- **`tests/suites/test_zzz_fall_probe.gd`** — unrelated throwaway probe.

---

## 7. Verification plan

1. **Import probe first** (cmd.exe, from project root — console binary, never
   the GUI one):
   `cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE! --headless --import . 2>&1"`
   → zero `SCRIPT ERROR` / `Parse Error` lines (a sub-second "clean" result =
   the GUI binary detached, re-run; see AGENTS.md false-green section).
2. **Targeted gate** (remember: `-a` is *repeatable*, comma-joined paths are a
   false green that runs NOTHING and exits 0):
   `... -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/suites/test_respawn_player_only.gd -a res://tests/suites/test_reverse_grade_power.gd -a res://tests/test_vehicle_physics.gd -a res://tests/suites/test_brake_stop_holds_first.gd -a res://tests/suites/test_manual_transmission_default.gd -a res://tests/suites/test_low_speed_reverse_handling.gd -a res://tests/suites/test_ground_latch.gd > _gdunit.txt 2>&1`
   → confirm `_gdunit.txt` is non-zero, read `Overall Summary:`, expect
   **21 new cases, 0 failures**.
3. **Full suite = one background sub-agent** (never the foreground; one Godot
   process at a time): import probe + `py tools\gdunit_parallel.py -j 4`.
   Baseline at last green run: `1018 test cases | 0 failures`; expected here
   ≈ `1039 | 0 failures`, exit 0 (101 = orphans-only also success).
4. **Manual playtest** (the two reported flows): (a) drive near an AI rival in
   free roam, press reset → only *your* car teleports; (b) mountain pass,
   reverse uphill out of a corner at ~50% throttle on snow/dirt → car climbs
   instead of stalling; also confirm a reverse *downhill* coast still feels
   natural (assist is off-throttle-gated) and forward driving feels unchanged.
5. `graphify update .` after the code lands (tooling-graph hygiene; GDScript
   itself is out of graph scope), then flip the STATUS block below.

---

## STATUS

- [x] Investigation + plan written (this doc)
- [ ] Step 1: `car_config.gd` knobs
- [ ] Step 2: respawn seams
- [ ] Step 3: grade assist
- [ ] Step 4: two new suites green + full parallel gate green
- [ ] Playtest of both reported flows
