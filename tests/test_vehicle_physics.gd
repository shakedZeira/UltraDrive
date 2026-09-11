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
