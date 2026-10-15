# tests/suites/test_turbo_boost.gd
extends GdUnitTestSuite

## Turbo boost simulation gate (R35 v1, presentation-only): Drivetrain's
## update_boost() must build toward full boost at wide-open throttle, vent to
## zero on lift, dip during an upshift only when a wastegate is fitted, stay
## pinned at zero for NA configs (and never skip a frame behind the
## rpm_override early-return), zero both public vars on reset(), and surface
## the three additive get_drive_info() keys (boost_bar / boost_fraction /
## has_turbo) without touching the existing ten. Pure/headless: direct
## Drivetrain.new() + update() calls, plus an off-tree VehiclePhysics.new().

const DT := 1.0 / 60.0
const NA_CONFIG: CarConfig = preload("res://resources/cars/starter_car.tres")
const GTR_CONFIG: CarConfig = preload("res://resources/cars/nissan_gt_r35_2017.tres")

func _turbo_config(wastegate: bool = true) -> CarConfig:
	var cfg := CarConfig.new()
	cfg.turbo_max_boost_bar = 1.8
	cfg.turbo_spool_time = 0.85
	cfg.turbo_blowdown_time = 0.35
	cfg.turbo_has_wastegate = wastegate
	return cfg

## Wheel speed (m/s) that spins the engine at redline in the given gear at the
## current wheel speed (mirrors Drivetrain's rpm_from_wheels math).
func _speed_for_redline_gear(config: CarConfig, gear: int) -> float:
	var gear_ratio := config.get_gear_ratio(gear)
	return config.redline_rpm * 0.33 * TAU / (60.0 * gear_ratio)

func _build_to_full_boost(dt: Drivetrain, config: CarConfig, frames: int = 400) -> void:
	var speed := _speed_for_redline_gear(config, 1)
	for _i in range(frames):
		dt.set_wheel_speed(speed)
		dt.update(DT, 1.0, config)

func test_boost_builds_toward_one_at_wot() -> void:
	var cfg := _turbo_config()
	var dt := Drivetrain.new()
	dt.manual_mode = true
	_build_to_full_boost(dt, cfg)
	assert_that(dt.boost_fraction).is_greater(0.9)
	assert_that(dt.boost_fraction).is_less_equal(1.0)
	assert_that(dt.boost_bar).is_equal_approx(1.8 * dt.boost_fraction, 0.001)
	assert_that(dt.boost_bar).is_less_equal(1.8)

func test_boost_vents_to_zero_on_lift() -> void:
	var cfg := _turbo_config()
	var dt := Drivetrain.new()
	dt.manual_mode = true
	_build_to_full_boost(dt, cfg)
	var speed := _speed_for_redline_gear(cfg, 1)
	for _i in range(250):
		dt.set_wheel_speed(speed)
		dt.update(DT, 0.0, cfg)
	assert_that(dt.boost_fraction).is_less(0.01)
	assert_that(dt.boost_bar).is_less(0.02)

func test_upshift_dips_boost_with_wastegate() -> void:
	var cfg_w := _turbo_config(true)
	var cfg_n := _turbo_config(false)
	cfg_w.shift_time = 0.5
	cfg_n.shift_time = 0.5
	var dt_w := Drivetrain.new()
	dt_w.manual_mode = true
	var dt_n := Drivetrain.new()
	dt_n.manual_mode = true
	_build_to_full_boost(dt_w, cfg_w)
	_build_to_full_boost(dt_n, cfg_n)
	assert_that(dt_w.boost_fraction).is_greater(0.9)
	assert_that(dt_n.boost_fraction).is_greater(0.9)
	var speed := _speed_for_redline_gear(cfg_w, 1)
	dt_w.shift_up(cfg_w)
	dt_n.shift_up(cfg_n)
	assert_that(dt_w.is_shifting).is_true()
	for _i in range(20):
		dt_w.set_wheel_speed(speed)
		dt_n.set_wheel_speed(speed)
		dt_w.update(DT, 1.0, cfg_w)
		dt_n.update(DT, 1.0, cfg_n)
	# Still mid-shift, so the wastegate dip is active: the wastegate car has
	# dumped a large share of its boost while the open-access car holds far
	# more of it (its only loss is the lower post-shift rpm target).
	assert_that(dt_w.is_shifting).is_true()
	assert_that(dt_w.boost_fraction).is_less(dt_n.boost_fraction * 0.75)
	assert_that(dt_w.boost_fraction).is_less(0.7)

func test_no_upshift_dip_when_wastegate_disabled() -> void:
	var cfg := _turbo_config(false)
	cfg.shift_time = 0.5
	var dt := Drivetrain.new()
	dt.manual_mode = true
	_build_to_full_boost(dt, cfg)
	var pre_shift: float = dt.boost_fraction
	var speed := _speed_for_redline_gear(cfg, 1)
	dt.shift_up(cfg)
	for _i in range(6):
		dt.set_wheel_speed(speed)
		dt.update(DT, 1.0, cfg)
	# Without a wastegate the boost never takes the ~0.15x dip; at most it
	# eases down with the lower post-shift rpm target (blowdown, not a dump).
	assert_that(dt.boost_fraction).is_greater(pre_shift * 0.5)
	assert_that(dt.boost_fraction).is_greater(0.7)

func test_na_config_stuck_at_zero() -> void:
	var dt := Drivetrain.new()
	dt.manual_mode = true
	var speed := _speed_for_redline_gear(NA_CONFIG, 1)
	for _i in range(200):
		dt.set_wheel_speed(speed)
		dt.update(DT, 1.0, NA_CONFIG)
	assert_that(dt.boost_fraction).is_equal(0.0)
	assert_that(dt.boost_bar).is_equal(0.0)

func test_boost_updates_behind_the_rpm_override_early_return() -> void:
	var cfg := _turbo_config()
	var dt := Drivetrain.new()
	dt.manual_mode = true
	dt.rpm_override = 0.5
	for _i in range(120):
		dt.update(DT, 1.0, cfg)
	assert_that(dt.engine_rpm).is_greater(cfg.idle_rpm)
	assert_that(dt.boost_fraction).is_greater(0.0)

func test_reset_zeroes_boost_state() -> void:
	var cfg := _turbo_config()
	var dt := Drivetrain.new()
	dt.manual_mode = true
	_build_to_full_boost(dt, cfg)
	assert_that(dt.boost_fraction).is_greater(0.0)
	dt.reset()
	assert_that(dt.boost_fraction).is_equal(0.0)
	assert_that(dt.boost_bar).is_equal(0.0)

func test_boost_target_fraction_static() -> void:
	var cfg := _turbo_config()
	assert_that(Drivetrain.boost_target_fraction(1.0, cfg.redline_rpm, cfg)).is_equal(1.0)
	assert_that(Drivetrain.boost_target_fraction(0.0, cfg.redline_rpm, cfg)).is_equal(0.0)
	assert_that(Drivetrain.boost_target_fraction(1.0, cfg.redline_rpm, NA_CONFIG)).is_equal(0.0)
	assert_that(Drivetrain.boost_target_fraction(1.0, cfg.redline_rpm, null)).is_equal(0.0)

func test_drive_info_carries_the_three_turbo_keys_on_na_default() -> void:
	var car := VehiclePhysics.new()
	var info := car.get_drive_info()
	assert_that(info.has("boost_bar")).is_true()
	assert_that(info.has("boost_fraction")).is_true()
	assert_that(info.has("has_turbo")).is_true()
	assert_that(float(info["boost_bar"])).is_equal(0.0)
	assert_that(float(info["boost_fraction"])).is_equal(0.0)
	assert_that(bool(info["has_turbo"])).is_false()
	car.free()

func test_drive_info_has_turbo_true_for_the_r35_config() -> void:
	var car := VehiclePhysics.new()
	car.config = GTR_CONFIG
	assert_that(bool(car.get_drive_info()["has_turbo"])).is_true()
	car.free()
