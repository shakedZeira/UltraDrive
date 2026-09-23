# Braking-to-a-stop must not engage reverse (D? playtest bug)

STATUS: Plan — not yet executed.

## Bug

After braking down to a stop, the car sometimes immediately starts
reversing by itself, without the player shifting into reverse. In AUTO the
player expects braking to a stop to hold in 1st (or creep), never to pick
reverse.

## Suspected root cause

`scripts/vehicle/drivetrain.gd` `update()` (~lines 50-62):

```gdscript
if current_gear >= 1:
    if _wheel_speed < -0.5 and not manual_mode:
        current_gear = -1
elif _wheel_speed > 0.5:
    current_gear = 1
```

In AUTO mode reverse is auto-selected whenever `_wheel_speed < -0.5 m/s`.
The deadband is meant to prevent flicker at standstill, but a hard brake to
zero can overshoot / briefly push wheel speed past -0.5 m/s (tire scrub,
spring-back, or a final jounce), selecting reverse — so the car starts
rolling backward on the next idle/throttle input.

MANUAL already gates reverse behind the player's `shift_down` from 1st
(the single entry path), so this bug is AUTO-only by design.

## Fix direction (implementer to confirm details)

- Raise/rework the auto-reverse gate so it cannot trigger from a
  brake-to-zero transient. Ideas:
  - Require reverse only when travel stays backward persistently, e.g.
    `_wheel_speed < -0.5` for N consecutive frames (or a small dwell), OR
  - Require the player to be explicitly off-brake (brake input == 0 AND
    _brake_input == 0) AND actually throttling backward / rolling back on a
    slope before auto-shifting to R, OR
  - Keep reverse fully player-initiated in AUTO too (shift_down from 1st)
    and drop the roll-back auto-select entirely — check docs/AGENTS.md
    convention that AUTO reaches reverse via roll-back is a recent change.
- Whatever the gate, the brake-to-stop trajectory must end in 1st gear at
  rest with no reverse engage and no creep-into-reverse on the next frame.
- Reverse still reachable from a genuine standstill backward roll or a
  toggle, so the off-road / parking cases keep working.

## Test gates (add)

- `tests/suites/` (mirror `test_manual_transmission_default.gd` /
  `test_low_speed_reverse_handling.gd` style):
  1. AUTO: hard brake from forward speed to 0 → `current_gear` stays 1, car
     never rolls backward (no reverse engage).
  2. AUTO: `_wheel_speed` dips just past -0.5 for one frame then returns →
     no reverse engage (transient immunity).
  3. AUTO: genuine sustained backward roll (e.g. slope roll-back, no brake)
     still reaches reverse.
  4. Existing reverse-handling suites stay green.

## Notes

- Verify current AUTO-vs-MANUAL behavior in `drivetrain.gd` before editing;
  the `test_manual_transmission_default.gd` "auto still reaches reverse"
  test explicitly asserts legacy roll-back → R logic and MUST be updated to
  the new contract.