extends GdUnitTestSuite

var car_config: CarConfig

func before_test() -> void:
    car_config = CarConfig.new()

func test_car_config_default_values() -> void:
    assert_that(car_config.car_name).is_equal("starter_car")
    assert_that(car_config.mass_kg).is_greater(0.0)
    assert_that(car_config.max_torque).is_greater(0.0)

func test_engine_torque_at_peak_rpm() -> void:
    var torque := car_config.get_engine_torque(car_config.peak_rpm)
    assert_that(torque).is_equal(car_config.max_torque)

func test_engine_torque_at_idle() -> void:
    var torque := car_config.get_engine_torque(car_config.idle_rpm)
    assert_that(torque).is_greater(0.0)

func test_engine_torque_at_redline() -> void:
    var torque := car_config.get_engine_torque(car_config.redline_rpm)
    assert_that(torque).is_equal(0.0)

func test_gear_ratio_first_gear() -> void:
    var ratio := car_config.get_gear_ratio(1)
    assert_that(ratio).is_equal(car_config.gear_ratios[0] * car_config.final_drive_ratio)

func test_gear_ratio_top_gear() -> void:
    var top: int = car_config.gear_ratios.size()
    var ratio := car_config.get_gear_ratio(top)
    assert_that(ratio).is_equal(car_config.gear_ratios[top - 1] * car_config.final_drive_ratio)

func test_gear_ratio_reverse() -> void:
    var ratio := car_config.get_gear_ratio(-1)
    assert_that(ratio).is_equal(car_config.reverse_ratio * car_config.final_drive_ratio)

func test_upshift_thresholds_rise_with_gears() -> void:
    var last := 0.0
    for i in range(car_config.upshift_speeds_kmh.size()):
        var s: float = car_config.get_upshift_speed_kmh(i + 1)
        assert_that(s).is_greater(last)
        last = s

func test_downshift_is_below_upshift() -> void:
    for i in range(min(car_config.downshift_speeds_kmh.size(), car_config.upshift_speeds_kmh.size())):
        var down: float = car_config.get_downshift_speed_kmh(i + 2)
        var up: float = car_config.get_upshift_speed_kmh(i + 1)
        assert_that(down).is_less(up)

func test_pacejika_returns_zero_at_zero_slip() -> void:
    var force := TireModel.calculate_lateral_force(0.0, 5000.0, car_config)
    assert_that(force).is_equal(0.0)

func test_pacejika_force_positive_for_positive_slip() -> void:
    var force := TireModel.calculate_lateral_force(0.1, 5000.0, car_config)
    assert_that(force).is_greater(0.0)

func test_pacejika_peak_near_configured_slip_angle() -> void:
    var peak_slip := deg_to_rad(TireModel.get_peak_slip_angle(car_config))
    var force := TireModel.calculate_lateral_force(peak_slip, 5000.0, car_config)
    assert_that(force).is_greater(4000.0)

func test_drivetrain_starts_in_first_gear() -> void:
    var dt := Drivetrain.new()
    assert_that(dt.engine_rpm).is_equal(800.0)
    assert_that(dt.current_gear).is_equal(1)

func test_drivetrain_reverse_ratio_is_weaker_than_first_gear() -> void:
    var reverse_ratio := car_config.get_gear_ratio(-1)
    var first_ratio := car_config.get_gear_ratio(1)
    assert_that(reverse_ratio).is_equal(car_config.reverse_ratio * car_config.final_drive_ratio)
    assert_that(reverse_ratio).is_less(first_ratio)

func test_drivetrain_does_not_auto_select_reverse_on_backward_roll() -> void:
    # Reverse is player-initiated in EVERY mode: a backward roll in AUTO stays
    # in 1st (the brake-to-stop fix). No code path auto-selects R.
    var dt := Drivetrain.new()
    dt.set_wheel_speed(-2.0)
    dt.update(1.0 / 60.0, 1.0, car_config)
    assert_that(dt.current_gear).is_equal(1)

func test_drivetrain_player_shift_down_selects_reverse() -> void:
    var dt := Drivetrain.new()
    dt.shift_down(car_config)
    assert_that(dt.current_gear).is_equal(-1)

func test_drivetrain_returns_to_first_gear_when_forward() -> void:
    var dt := Drivetrain.new()
    dt.shift_down(car_config)
    assert_that(dt.current_gear).is_equal(-1)
    dt.is_shifting = false
    dt.shift_timer = 0.0
    dt.set_wheel_speed(2.0)
    dt.update(1.0 / 60.0, 1.0, car_config)
    assert_that(dt.current_gear).is_equal(1)

func test_reverse_speed_limiter_cuts_drive_torque_at_cap() -> void:
    var dt := Drivetrain.new()
    dt.shift_down(car_config)
    dt.is_shifting = false
    dt.shift_timer = 0.0
    var cap_ms := car_config.max_reverse_speed_kmh / 3.6
    dt.set_wheel_speed(-(cap_ms + 0.1))
    dt.update(1.0 / 60.0, 1.0, car_config)
    assert_that(dt.current_gear).is_equal(-1)
    assert_that(dt.reverse_limiter_active).is_true()
    assert_that(dt.drive_torque).is_equal(0.0)

func test_reverse_limiter_inactive_below_cap() -> void:
    var dt := Drivetrain.new()
    dt.shift_down(car_config)
    dt.is_shifting = false
    dt.shift_timer = 0.0
    dt.set_wheel_speed(-1.0)
    dt.update(1.0 / 60.0, 1.0, car_config)
    assert_that(dt.reverse_limiter_active).is_false()
    assert_that(dt.drive_torque).is_less(0.0)

func test_forward_gears_never_shift_while_in_reverse() -> void:
    var dt := Drivetrain.new()
    dt.shift_down(car_config)
    dt.is_shifting = false
    dt.shift_timer = 0.0
    dt.set_wheel_speed(-20.0)
    dt.update(1.0 / 60.0, 1.0, car_config)
    assert_that(dt.current_gear).is_equal(-1)
    # A second frame keeps reverse locked even though -20 m/s (72 km/h) backward
    # would have upshifted a forward gear past 1st.
    dt.update(1.0 / 60.0, 1.0, car_config)
    assert_that(dt.current_gear).is_equal(-1)

func test_drive_info_exposes_brake_and_steer_keys() -> void:
    var car := VehiclePhysics.new()
    var info := car.get_drive_info()
    assert_that(info.has("brake")).is_true()
    assert_that(info.has("steer")).is_true()
    assert_that(info["brake"]).is_equal_approx(0.0, 0.001)
    assert_that(info["steer"]).is_equal_approx(0.0, 0.001)
    car.free()

func test_drive_info_keeps_existing_keys() -> void:
    var car := VehiclePhysics.new()
    var info := car.get_drive_info()
    assert_that(info.has("rpm")).is_true()
    assert_that(info.has("gear")).is_true()
    assert_that(info.has("speed_kmh")).is_true()
    assert_that(info.has("handling_mode")).is_true()
    assert_that(info.has("throttle")).is_true()
    car.free()
