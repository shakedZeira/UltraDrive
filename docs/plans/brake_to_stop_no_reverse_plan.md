# Braking-to-a-stop must not engage reverse (D? playtest bug)

STATUS: Executed.

## Bug

After braking down to a stop, the car sometimes immediately starts
reversing by itself, without the player shifting into reverse. In AUTO the
player expects braking to a stop to hold in 1st (or creep), never to pick
reverse.

## Root cause (confirmed in code)

`scripts/vehicle/drivetrain.gd` `update()`:

```gdscript
if current_gear >= 1:
    if _wheel_speed < -0.5 and not manual_mode:
        current_gear = -1
elif _wheel_speed > 0.5:
    current_gear = 1
```

In AUTO mode reverse was auto-selected whenever `_wheel_speed < -0.5 m/s`.
The deadband is meant to prevent flicker at standstill, but a hard brake to
zero can overshoot / briefly push wheel speed past -0.5 m/s (tire scrub,
spring-back, or a final jounce), selecting reverse - so the car starts
rolling backward on the next idle/throttle input.

## Fix direction (chosen: player-initiated reverse in ALL modes)

Reverse is now PLAYER-INITIATED in every mode - the explicit `shift_down`
from 1st is the single entry path (`drivetrain.gd` `shift_down`, over-rev
guard intact), matching what MANUAL already did:

- **Dropped** the AUTO roll-back auto-select entirely: `_wheel_speed < -0.5`
  no longer ever flips gear to -1. A brake-to-zero transient ends in 1st at
  rest; a genuine sustained backward roll in AUTO also stays in the forward
  gear until the player shifts down.
- **Kept** the forward-roll return from R to 1st in AUTO (`_wheel_speed >
  0.5` flips gear back to 1) - the real-world "shift out of R when rolling
  forward", active in both modes, and never re-enters R.
- **Gate**: `vehicle_physics.gd` no longer restricts player `shift_up` /
  `shift_down` routing to MANUAL, so AUTO honors the explicit 1st->R
  downshift (the `controls_locked` and `input_override == Vector2.ZERO`
  guards stay, so AI/traffic cars - which drive through non-zero
  `input_override` and never shift manually - are unaffected).
- **`shift_up`** from R returns to 1st for AUTO-selected R as well (was
  MANUAL-only).
- **Reverse stays fully functional** once player-selected: reverse speed cap,
  throttle torque flip, travel-keyed engine brake all untouched.
- **Slope parking note**: with no auto-reverse, rolling backward on an
  uphill/downhill slope while parked now holds in 1st with engine braking
  resisting the roll (the travel-keyed brake opposes travel in forward
  gears), exactly like MANUAL already behaved.

## Test gates (added)

- `tests/suites/test_brake_stop_holds_first.gd` (new):
  1. AUTO hard brake from +8 m/s to 0 with a -0.4/-0.7 m/s jounce transient -
     `current_gear` stays 1 on every frame, never -1.
  2. AUTO genuine sustained backward roll (120 frames at -2.0 m/s) still does
     NOT auto-select R; a player `shift_down` at standstill DOES select R.
  3. AUTO in R rolling forward (`_wheel_speed = 0.6`) returns to 1st.
  4. AUTO reverse functionality kept: over-rev guard rejects fast 1st->R,
     `shift_up` leaves R, reverse speed cap still holds.
- `tests/suites/test_manual_transmission_default.gd`:
  `test_auto_mode_still_reaches_reverse_per_existing_logic` rewritten to
  `test_auto_mode_reverse_is_player_initiated_not_roll_back` (old AUTO
  roll-back -> R assert removed; asserts the new player-initiated contract).
- Existing reverse-handling suites verified compatible:
  `test_low_speed_reverse_handling.gd` and `test_release_engine_brake.gd`
  use `manual_mode = true` drivetrains (and/or set `current_gear` directly),
  so the AUTO-removal is inert to them.

## Notes

- `tests/test_vehicle_physics.gd` (lines ~75-114) still asserts the legacy
  AUTO roll-back -> R behavior on a `manual_mode == false` drivetrain; it is
  OUT of this plan's test-file ownership and needs a parent reconciliation
  (or a later pass) to match the new contract.