extends GdUnitTestSuite

## Tests for the optional manual transmission and the RPM-based auto upshift.
## Rally config: redline 8200, auto upshift at 0.92 * 8200 = 7544 rpm. At 24
## km/h in 1st the engine is at ~2850 rpm (~35% of redline), so the old
## speed-table shift point must no longer trigger a gear change.

const RALLY_CONFIG: CarConfig = preload("res://resources/cars/rally_hatch.tres")
const AUTO_SHIFT_RPM: float = 7544.0

func _new_drivetrain() -> Drivetrain:
    var dt := Drivetrain.new()
    dt.manual_mode = false
    return dt

func _simulate(dt: Drivetrain, config: CarConfig, wheel_speed_ms: float, frames: int) -> void:
    dt.set_wheel_speed(wheel_speed_ms)
    for _i in range(frames):
        dt.update(1.0 / 60.0, 1.0, config)

func test_auto_does_not_upshift_at_old_speed_table_point() -> void:
    # 24 km/h == 6.667 m/s (~2850 rpm in 1st) used to trigger an upshift on the
    # rally car via upshift_speeds_kmh[0] = 24; must now stay in 1st gear.
    var dt := _new_drivetrain()
    _simulate(dt, RALLY_CONFIG, 24.0 / 3.6, 120)
    assert_that(dt.current_gear).is_equal(1)
    assert_that(dt.is_shifting).is_false()
    assert_that(dt.engine_rpm).is_less(AUTO_SHIFT_RPM)

func test_auto_upshifts_when_rpm_reaches_redline_fraction() -> void:
    # 18 m/s in 1st (ratio 3.6 * 4.1 = 14.76) yields ~7688 rpm >= 7544 rpm.
    var dt := _new_drivetrain()
    _simulate(dt, RALLY_CONFIG, 18.0, 60)
    assert_that(dt.current_gear).is_equal(2)

func test_manual_does_not_auto_upshift_at_high_rpm() -> void:
    var dt := _new_drivetrain()
    dt.manual_mode = true
    _simulate(dt, RALLY_CONFIG, 18.0, 60)
    assert_that(dt.current_gear).is_equal(1)
    assert_that(dt.is_shifting).is_false()
    assert_that(dt.engine_rpm).is_greater(AUTO_SHIFT_RPM)

func test_manual_explicit_shift_up_moves_to_second() -> void:
    var dt := _new_drivetrain()
    dt.manual_mode = true
    dt.shift_up(RALLY_CONFIG)
    assert_that(dt.current_gear).is_equal(2)
    assert_that(dt.is_shifting).is_true()

func test_manual_shift_up_at_top_gear_is_noop() -> void:
    var dt := _new_drivetrain()
    dt.manual_mode = true
    dt.current_gear = RALLY_CONFIG.gear_ratios.size()
    dt.shift_up(RALLY_CONFIG)
    assert_that(dt.current_gear).is_equal(RALLY_CONFIG.gear_ratios.size())
    assert_that(dt.is_shifting).is_false()

func test_manual_shift_down_at_first_gear_is_noop() -> void:
    var dt := _new_drivetrain()
    dt.manual_mode = true
    dt.shift_down(RALLY_CONFIG)
    assert_that(dt.current_gear).is_equal(1)
    assert_that(dt.is_shifting).is_false()

func test_manual_shift_down_rejected_when_over_rev() -> void:
    # In 5th (ratio 1.1 * 4.1) at 70 m/s, 4th (1.4 * 4.1) would spin to ~11627
    # rpm > 1.05 * 8200 = 8610 rpm, so the downshift must be rejected.
    var dt := _new_drivetrain()
    dt.manual_mode = true
    dt.current_gear = 5
    dt.set_wheel_speed(70.0)
    dt.shift_down(RALLY_CONFIG)
    assert_that(dt.current_gear).is_equal(5)
    assert_that(dt.is_shifting).is_false()

func test_manual_shift_down_succeeds_at_low_speed() -> void:
    var dt := _new_drivetrain()
    dt.manual_mode = true
    dt.current_gear = 2
    dt.set_wheel_speed(2.0)
    dt.shift_down(RALLY_CONFIG)
    assert_that(dt.current_gear).is_equal(1)
    assert_that(dt.is_shifting).is_true()

func test_shift_actions_are_defined() -> void:
    assert_that(InputMap.has_action("shift_up")).is_true()
    assert_that(InputMap.has_action("shift_down")).is_true()

func test_shift_up_action_binds_joypad_button_three() -> void:
    assert_that(_action_has_joypad_button("shift_up", 3)).is_true()

func test_shift_down_action_binds_joypad_button_zero() -> void:
    assert_that(_action_has_joypad_button("shift_down", 0)).is_true()

func test_handbrake_binds_joypad_button_one_circle() -> void:
    assert_that(_action_has_joypad_button("handbrake", 3)).is_false()
    assert_that(_action_has_joypad_button("handbrake", 10)).is_false()
    assert_that(_action_has_joypad_button("handbrake", 1)).is_true()

func _action_has_joypad_button(action: String, index: int) -> bool:
    for event in InputMap.action_get_events(action):
        if event is InputEventJoypadButton and event.button_index == index:
            return true
    return false