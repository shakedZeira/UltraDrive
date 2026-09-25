# tests/suites/test_brake_stop_holds_first.gd
extends GdUnitTestSuite

## Regression gate for the "brake to 0 suddenly starts reversing in 1st" bug
## (docs/plans/brake_to_stop_no_reverse_plan.md). Reverse (-1) is
## player-initiated in EVERY mode: braking to a stop must end in 1st at rest,
## a hard-brake transient that jounces wheel speed negative must never select
## R, and even a genuine sustained backward roll in AUTO stays in the forward
## gear until the player explicitly shift_downs from 1st. Leaving R is still
## automatic (rolling forward returns to 1st) and the reverse speed cap keeps
## working for AUTO-selected R.
## Pure/headless: direct Drivetrain.new() + update() calls.

const STARTER_CONFIG: CarConfig = preload("res://resources/cars/starter_car.tres")
const RALLY_CONFIG: CarConfig = preload("res://resources/cars/rally_hatch.tres")
const DT := 1.0 / 60.0

func _new_auto_drivetrain() -> Drivetrain:
	var dt := Drivetrain.new()
	dt.manual_mode = false
	return dt

# --- AUTO brake-to-zero: wheel-speed jounce must never select reverse ---

func test_brake_to_stop_never_selects_reverse_in_auto() -> void:
	# Hard-brake-from-speed trajectory: +8 m/s falls through 0, dips briefly
	# past -0.5 (tire scrub / spring-back jounce), then settles at rest. The
	# gear must be 1 on EVERY frame - never -1.
	var dt := _new_auto_drivetrain()
	var trajectory: Array[float] = [8.0, 6.0, 4.0, 2.0, 0.8, 0.3, -0.4, -0.7, -0.3, 0.0]
	for speed in trajectory:
		dt.set_wheel_speed(speed)
		dt.update(DT, 0.0, STARTER_CONFIG)
		assert_that(dt.current_gear).is_equal(1)

func test_single_frame_dip_past_minus_0_5_does_not_select_reverse() -> void:
	var dt := _new_auto_drivetrain()
	dt.set_wheel_speed(-0.7)
	dt.update(DT, 0.0, STARTER_CONFIG)
	assert_that(dt.current_gear).is_equal(1)
	dt.update(DT, 0.0, STARTER_CONFIG)
	assert_that(dt.current_gear).is_equal(1)

# --- AUTO genuine backward roll: still player-initiated only ---

func test_auto_sustained_backward_roll_does_not_select_reverse() -> void:
	var dt := _new_auto_drivetrain()
	for _i in range(120):
		dt.set_wheel_speed(-2.0)
		dt.update(DT, 1.0, STARTER_CONFIG)
		assert_that(dt.current_gear).is_equal(1)
	assert_that(dt.current_gear).is_equal(1)

func test_auto_shift_down_from_first_selects_reverse() -> void:
	var dt := _new_auto_drivetrain()
	dt.set_wheel_speed(0.0)
	dt.shift_down(STARTER_CONFIG)
	assert_that(dt.current_gear).is_equal(-1)
	assert_that(dt.is_shifting).is_true()

func test_auto_shift_down_from_first_rejected_over_rev_at_speed() -> void:
	# Same over-rev guard as MANUAL: at 30 m/s forward, 1st -> R would spin
	# past 1.05 * redline, so the player's AUTO downshift is rejected too.
	var dt := _new_auto_drivetrain()
	dt.set_wheel_speed(30.0)
	dt.shift_down(RALLY_CONFIG)
	assert_that(dt.current_gear).is_equal(1)
	assert_that(dt.is_shifting).is_false()

# --- Leaving R is automatic (all modes) ---

func test_auto_reverse_returns_to_first_on_forward_roll() -> void:
	var dt := _new_auto_drivetrain()
	dt.shift_down(STARTER_CONFIG)
	assert_that(dt.current_gear).is_equal(-1)
	dt.is_shifting = false
	dt.set_wheel_speed(0.6)
	dt.update(DT, 1.0, STARTER_CONFIG)
	assert_that(dt.current_gear).is_equal(1)

func test_auto_shift_up_from_reverse_returns_to_first() -> void:
	var dt := _new_auto_drivetrain()
	dt.shift_down(STARTER_CONFIG)
	assert_that(dt.current_gear).is_equal(-1)
	dt.shift_up(STARTER_CONFIG)
	assert_that(dt.current_gear).is_equal(1)
	assert_that(dt.is_shifting).is_true()

func test_auto_reverse_speed_cap_still_holds() -> void:
	var dt := _new_auto_drivetrain()
	dt.shift_down(STARTER_CONFIG)
	dt.is_shifting = false
	var cap_ms := STARTER_CONFIG.max_reverse_speed_kmh / 3.6
	dt.set_wheel_speed(-(cap_ms + 0.5))
	dt.update(DT, 1.0, STARTER_CONFIG)
	assert_that(dt.current_gear).is_equal(-1)
	assert_that(dt.reverse_limiter_active).is_true()
	assert_that(dt.drive_torque).is_equal(0.0)