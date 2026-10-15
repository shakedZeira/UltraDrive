# tests/suites/test_awd_drive.gd
extends GdUnitTestSuite

## Per-car drivetrain layout gate. VehiclePhysics now splits the Drivetrain's
## total drive torque across the front/rear axles from CarConfig.drivetrain_layout
## (RWD keeps the historical all-rear flow byte-for-byte; AWD honours
## awd_front_torque_split; FWD drives the front only). The GT-R R35 ships as a
## rear-biased AWD (0.3 front / 0.7 rear) so its 634 Nm doesn't slam two rear
## wheels past grip off the line - the "slips like crazy" fix.
## Pure/headless: static math + a live Drivetrain, no scene tree (WheelPhysics
## nodes are bare spin vectors only, freed in after_test).

const GTR_CONFIG_PATH := "res://resources/cars/nissan_gt_r35_2017.tres"
const DT := 1.0 / 60.0

var _managed_nodes: Array = []

func before_test() -> void:
	_managed_nodes.clear()

func after_test() -> void:
	for node in _managed_nodes:
		if is_instance_valid(node):
			node.free()
	_managed_nodes.clear()

func _rwd_config() -> CarConfig:
	var cfg := CarConfig.new()
	cfg.drivetrain_layout = CarConfig.DRIVETRAIN_RWD
	return cfg

func _awd_config(front_split: float) -> CarConfig:
	var cfg := CarConfig.new()
	cfg.drivetrain_layout = CarConfig.DRIVETRAIN_AWD
	cfg.awd_front_torque_split = front_split
	return cfg

func _fwd_config() -> CarConfig:
	var cfg := CarConfig.new()
	cfg.drivetrain_layout = CarConfig.DRIVETRAIN_FWD
	return cfg

func _bare_wheel(spin_rad_s: float) -> WheelPhysics:
	var wheel := WheelPhysics.new()
	wheel.wheel_angular_velocity = spin_rad_s
	_managed_nodes.append(wheel)
	return wheel

# --- Defaults: the new field must not change any existing car ---

func test_rwd_is_the_script_default() -> void:
	var cfg := CarConfig.new()
	assert_that(cfg.drivetrain_layout).is_equal(CarConfig.DRIVETRAIN_RWD)

func test_rwd_split_is_all_rear() -> void:
	var split := VehiclePhysics.drive_split_for(_rwd_config())
	assert_that(split).is_equal_approx(Vector2(0.0, 1.0), Vector2(0.0001, 0.0001))

func test_rwd_rear_wheels_get_legacy_torque_and_fronts_none() -> void:
	var split := VehiclePhysics.drive_split_for(_rwd_config())
	var torque := 1000.0
	for i in range(2):
		assert_float(VehiclePhysics.wheel_drive_torque(torque, i, split)).is_equal_approx(0.0, 0.0001)
	for i in range(2, 4):
		assert_float(VehiclePhysics.wheel_drive_torque(torque, i, split)).is_equal_approx(torque / 2.0, 0.0001)
	var sum_torque := 0.0
	for i in range(4):
		sum_torque += VehiclePhysics.wheel_drive_torque(torque, i, split)
	# ... and the four wheels together carry exactly the driveshaft torque.
	assert_float(sum_torque).is_equal_approx(torque, 0.0001)

# --- AWD: torque reaches all four wheels at the configured split ---

func test_awd_split_routes_torque_to_all_four_wheels() -> void:
	var split := VehiclePhysics.drive_split_for(_awd_config(0.3))
	assert_that(split).is_equal_approx(Vector2(0.3, 0.7), Vector2(0.0001, 0.0001))
	var torque := 8914.0  # ~GT-R 1st gear × final drive at peak torque
	for i in range(4):
		assert_float(VehiclePhysics.wheel_drive_torque(torque, i, split)).is_greater(0.0)
	assert_float(VehiclePhysics.wheel_drive_torque(torque, 0, split)).is_equal_approx(torque * 0.3 / 2.0, 0.001)
	assert_float(VehiclePhysics.wheel_drive_torque(torque, 1, split)).is_equal_approx(torque * 0.3 / 2.0, 0.001)
	assert_float(VehiclePhysics.wheel_drive_torque(torque, 2, split)).is_equal_approx(torque * 0.7 / 2.0, 0.001)
	assert_float(VehiclePhysics.wheel_drive_torque(torque, 3, split)).is_equal_approx(torque * 0.7 / 2.0, 0.001)

func test_awd_rear_wheel_ratio_matches_the_split() -> void:
	var split := VehiclePhysics.drive_split_for(_awd_config(0.3))
	var rear := VehiclePhysics.wheel_drive_torque(1000.0, 2, split)
	var front := VehiclePhysics.wheel_drive_torque(1000.0, 0, split)
	assert_float(front / rear).is_equal_approx(0.3 / 0.7, 0.001)
	# Rear-biased by design: rear wheels carry more than the fronts.
	assert_that(rear).is_greater(front)

func test_awd_signed_torque_keeps_the_split_in_reverse_and_engine_brake() -> void:
	var split := VehiclePhysics.drive_split_for(_awd_config(0.3))
	var negative := -8914.0  # reverse throttle / engine braking
	for i in range(4):
		assert_float(VehiclePhysics.wheel_drive_torque(negative, i, split)).is_less(0.0)
	assert_float(VehiclePhysics.wheel_drive_torque(negative, 0, split)).is_equal_approx(negative * 0.3 / 2.0, 0.001)
	assert_float(VehiclePhysics.wheel_drive_torque(negative, 3, split)).is_equal_approx(negative * 0.7 / 2.0, 0.001)

func test_awd_front_split_is_clamped_to_unit_interval() -> void:
	assert_that(VehiclePhysics.drive_split_for(_awd_config(1.5))).is_equal_approx(Vector2(1.0, 0.0), Vector2(0.0001, 0.0001))
	assert_that(VehiclePhysics.drive_split_for(_awd_config(-0.2))).is_equal_approx(Vector2(0.0, 1.0), Vector2(0.0001, 0.0001))
	assert_that(VehiclePhysics.drive_split_for(_awd_config(0.0))).is_equal_approx(Vector2(0.0, 1.0), Vector2(0.0001, 0.0001))

# --- FWD: front only ---

func test_fwd_split_is_all_front() -> void:
	assert_that(VehiclePhysics.drive_split_for(_fwd_config())).is_equal_approx(Vector2(1.0, 0.0), Vector2(0.0001, 0.0001))
	var torque := 2000.0
	for i in range(2):
		assert_float(VehiclePhysics.wheel_drive_torque(torque, i, VehiclePhysics.drive_split_for(_fwd_config()))).is_equal_approx(torque / 2.0, 0.0001)
	for i in range(2, 4):
		assert_float(VehiclePhysics.wheel_drive_torque(torque, i, VehiclePhysics.drive_split_for(_fwd_config()))).is_equal_approx(0.0, 0.0001)

# --- Axle speed for engine-brake scaling follows the layout ---

func test_driven_axle_speed_follows_layout_axles() -> void:
	var w0 := _bare_wheel(10.0)
	var w1 := _bare_wheel(20.0)
	var w2 := _bare_wheel(30.0)
	var w3 := _bare_wheel(40.0)
	var wheels: Array[WheelPhysics] = [w0, w1, w2, w3]
	var r := WheelPhysics.WHEEL_RADIUS
	assert_float(VehiclePhysics.driven_axle_speed(wheels, VehiclePhysics.drive_split_for(_rwd_config()))).is_equal_approx(35.0 * r, 0.001)
	assert_float(VehiclePhysics.driven_axle_speed(wheels, VehiclePhysics.drive_split_for(_awd_config(0.3)))).is_equal_approx(25.0 * r, 0.001)
	assert_float(VehiclePhysics.driven_axle_speed(wheels, VehiclePhysics.drive_split_for(_fwd_config()))).is_equal_approx(15.0 * r, 0.001)

# --- GT-R R35: shipped rear-biased AWD ---

func test_gt_r35_config_is_rear_biased_awd() -> void:
	var cfg := load(GTR_CONFIG_PATH) as CarConfig
	assert_that(cfg).is_not_null()
	if cfg == null:
		return
	assert_that(cfg.drivetrain_layout).is_equal(CarConfig.DRIVETRAIN_AWD)
	assert_float(cfg.awd_front_torque_split).is_equal_approx(0.3, 0.001)
	assert_that(VehiclePhysics.drive_split_for(cfg)).is_equal_approx(Vector2(0.3, 0.7), Vector2(0.0001, 0.0001))

func test_gt_r35_throttle_drive_torque_reaches_all_four_wheels() -> void:
	var cfg := load(GTR_CONFIG_PATH) as CarConfig
	assert_that(cfg).is_not_null()
	if cfg == null:
		return
	var dt := Drivetrain.new()
	dt.manual_mode = true
	dt.current_gear = 1
	dt.set_wheel_speed(0.0)
	var info := dt.update(DT, 1.0, cfg)
	var total := float(info["drive_torque"])
	# Fresh Drivetrain sits at idle; engine torque there = max_torque * 0.5,
	# through 1st gear (3.8) and the final drive (3.7).
	assert_float(total).is_equal_approx(634.0 * 0.5 * (3.8 * 3.7), 1.0)
	var split := VehiclePhysics.drive_split_for(cfg)
	assert_float(VehiclePhysics.wheel_drive_torque(total, 0, split)).is_greater(0.0)
	assert_float(VehiclePhysics.wheel_drive_torque(total, 3, split)).is_greater(0.0)
	assert_float(VehiclePhysics.wheel_drive_torque(total, 3, split)).is_greater(
		VehiclePhysics.wheel_drive_torque(total, 0, split)
	)