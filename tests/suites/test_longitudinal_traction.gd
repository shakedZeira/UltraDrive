# tests/suites/test_longitudinal_traction.gd
extends GdUnitTestSuite

## Longitudinal traction gate: the Pacejka traction path is now the real slip-
## driven curve (not a raw torque-to-force ratio), the wheel-spin integrator
## produces true wheelspin/free-roll/lock behaviour (stable at 60 Hz), and the
## starter's peak-slip convention matches the 1.09/B threshold the code now
## returns. Pure math (no frames) plus one scene integration that launches the
## player car and checks the driven axle really out-rolls the free front axle.

const TEST_SCENE := "res://scenes/test/test_vehicle_physics.tscn"
const ARCADE_GRIP := 1.3
const DT := 1.0 / 60.0

var _managed_nodes: Array = []

func before_test() -> void:
	_managed_nodes.clear()

func after_test() -> void:
	for node in _managed_nodes:
		if is_instance_valid(node):
			node.free()
	_managed_nodes.clear()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

func _starter() -> CarConfig:
	return load("res://resources/cars/starter_car.tres") as CarConfig

# --- Slip-ratio semantics ---

func test_slip_ratio_zero_at_pure_rolling() -> void:
	var r := WheelPhysics.WHEEL_RADIUS
	assert_that(TireModel.calculate_slip_ratio(30.0, 30.0 * r, r)).is_equal_approx(0.0, 0.0001)

func test_slip_ratio_zero_at_standstill() -> void:
	var r := WheelPhysics.WHEEL_RADIUS
	assert_that(TireModel.calculate_slip_ratio(0.0, 0.0, r)).is_equal_approx(0.0, 0.0001)

func test_slip_ratio_positive_wheelspin_bounded() -> void:
	var r := WheelPhysics.WHEEL_RADIUS
	var v := 10.0  # road speed (m/s)
	var rolling := v / r  # rad/s at pure rolling
	# 10% wheelspin over the rolling match -> small positive slip in (0, 1).
	assert_that(TireModel.calculate_slip_ratio(rolling * 1.1, v, r)).is_between(0.05, 0.2)
	# Extreme wheelspin approaches the +1 cap from below (never jumps past it).
	assert_that(TireModel.calculate_slip_ratio(rolling * 3.0, v, r)).is_between(0.6, 0.7)
	assert_that(TireModel.calculate_slip_ratio(rolling * 500.0, v, r)).is_less(1.0)

func test_slip_ratio_negative_lockup_bounded() -> void:
	var r := WheelPhysics.WHEEL_RADIUS
	var v := 10.0  # road speed (m/s)
	var rolling := v / r  # rad/s at pure rolling
	# Wheel stopped while the road keeps moving = full lock, -1.0 exactly.
	assert_that(TireModel.calculate_slip_ratio(0.0, v, r)).is_equal(-1.0)
	# Wheel rolled BACKWARD against a forward-moving road pins the -1.0 cap.
	assert_that(TireModel.calculate_slip_ratio(-rolling, v, r)).is_equal(-1.0)
	# Mildly under-rolling = small negative slip (light drag, no lock).
	assert_that(TireModel.calculate_slip_ratio(rolling * 0.75, v, r)).is_between(-0.4, -0.2)

# --- Pacejka longitudinal curve geometry ---

func test_longitudinal_force_peak_geometry_matches_starter_tire() -> void:
	var cfg := _starter()
	var d := 5000.0 * cfg.tire_D * 1.0 * 0.95  # D at unit grip, normal 5000
	var best_x := 0.0
	var best_f := 0.0
	for k in range(1, 40):
		var s := k * 0.01
		var f := TireModel.calculate_longitudinal_force(s, 5000.0, cfg, 1.0, 1.0)
		if f > best_f:
			best_f = f
			best_x = s
	# Steering-free curve: peak force lands near ~24% slip and kisses D.
	assert_that(best_x).is_between(0.20, 0.28)
	assert_that(best_f).is_greater(d * 0.97)
	assert_that(best_f).is_less_equal(d + 0.5)

func test_longitudinal_force_grows_to_peak_then_falls() -> void:
	var cfg := _starter()
	assert_that(TireModel.calculate_longitudinal_force(0.0, 5000.0, cfg, 1.0, 1.0)).is_equal_approx(0.0, 0.01)
	# Rising toward the ~0.24 peak, then decaying past it (slowly - the curve
	# stays well above 90% of D all the way to full spin).
	assert_that(TireModel.calculate_longitudinal_force(0.12, 5000.0, cfg, 1.0, 1.0)).is_greater(
		TireModel.calculate_longitudinal_force(0.05, 5000.0, cfg, 1.0, 1.0)
	)
	assert_that(TireModel.calculate_longitudinal_force(0.24, 5000.0, cfg, 1.0, 1.0)).is_greater(
		TireModel.calculate_longitudinal_force(0.12, 5000.0, cfg, 1.0, 1.0)
	)
	assert_that(TireModel.calculate_longitudinal_force(0.24, 5000.0, cfg, 1.0, 1.0)).is_greater(
		TireModel.calculate_longitudinal_force(0.7, 5000.0, cfg, 1.0, 1.0)
	)

func test_longitudinal_force_symmetric_under_slip_side() -> void:
	var cfg := _starter()
	var fwd := TireModel.calculate_longitudinal_force(0.2, 5000.0, cfg, 1.0, 1.0)
	var rev := TireModel.calculate_longitudinal_force(-0.2, 5000.0, cfg, 1.0, 1.0)
	assert_that(rev).is_equal_approx(-fwd, 0.01)

func test_longitudinal_force_zero_without_normal_load() -> void:
	var cfg := _starter()
	for s: float in [0.0, 0.1, 0.4, 1.0, -1.0]:
		assert_that(TireModel.calculate_longitudinal_force(s, 0.0, cfg, 1.3, 1.0)).is_equal_approx(0.0, 0.001)

func test_longitudinal_force_scales_with_load_and_grip() -> void:
	var cfg := _starter()
	var at_2500 := TireModel.calculate_longitudinal_force(0.1, 2500.0, cfg, 1.0, 1.0)
	var at_5000 := TireModel.calculate_longitudinal_force(0.1, 5000.0, cfg, 1.0, 1.0)
	assert_that(at_5000).is_equal_approx(at_2500 * 2.0, 0.5)
	var a_grip := TireModel.calculate_longitudinal_force(0.1, 5000.0, cfg, ARCADE_GRIP, 1.0)
	assert_that(a_grip).is_equal_approx(
		TireModel.calculate_longitudinal_force(0.1, 5000.0, cfg, 1.0, 1.0) * ARCADE_GRIP, 0.5
	)

# --- Peak-slip-angle convention (drift/AI/rivals) ---

func test_peak_slip_angle_uses_109_over_b() -> void:
	var cfg := _starter()
	var expected := rad_to_deg(1.09 / cfg.tire_B)
	assert_that(TireModel.get_peak_slip_angle(cfg)).is_equal_approx(expected, 0.001)
	assert_that(TireModel.get_peak_slip_angle(cfg)).is_between(6.0, 7.5)

func test_peak_slip_angle_force_stays_near_curve_max() -> void:
	var cfg := _starter()
	var peak_deg := TireModel.get_peak_slip_angle(cfg)
	var peak_force := TireModel.calculate_lateral_force(deg_to_rad(peak_deg), 5000.0, cfg, 1.0, 1.0)
	var best := 0.0
	for k in range(4, 41):
		var s := deg_to_rad(k * 0.5)
		best = maxf(best, TireModel.calculate_lateral_force(s, 5000.0, cfg, 1.0, 1.0))
	# 1.09/B sits within 5% of the actual curve maximum for the starter shape.
	assert_that(peak_force).is_greater(best * 0.95)

# --- Longitudinal stiffness (semi-implicit integrator slope) ---

func test_stiffness_matches_forward_difference() -> void:
	var cfg := _starter()
	var s := 0.04
	var h := 0.001
	var exact := TireModel.calculate_longitudinal_stiffness(s, 5000.0, cfg, 1.0, 1.0)
	var numeric := (
		TireModel.calculate_longitudinal_force(s + h, 5000.0, cfg, 1.0, 1.0)
		- TireModel.calculate_longitudinal_force(s - h, 5000.0, cfg, 1.0, 1.0)
	) / (2.0 * h)
	assert_that(exact).is_greater(0.0)
	assert_that(exact).is_equal_approx(numeric, absf(numeric) * 0.05 + 1.0)

func test_stiffness_sign_follows_curve() -> void:
	var cfg := _starter()
	assert_that(TireModel.calculate_longitudinal_stiffness(0.02, 5000.0, cfg, 1.0, 1.0)).is_greater(0.0)
	# Past the ~15% peak the slope goes negative: spin-away/lock region.
	assert_that(TireModel.calculate_longitudinal_stiffness(0.5, 5000.0, cfg, 1.0, 1.0)).is_less(0.0)

func test_stiffness_zero_without_normal_load() -> void:
	var cfg := _starter()
	for s: float in [0.0, 0.1, 0.5]:
		assert_that(TireModel.calculate_longitudinal_stiffness(s, 0.0, cfg, 1.0, 1.0)).is_equal_approx(0.0, 0.001)

# --- Wheel-spin integrator ---

func test_launch_wheelspin_spins_past_grip_peak() -> void:
	var cfg := _starter()
	var r := WheelPhysics.WHEEL_RADIUS
	var wheel := WheelPhysics.new()
	_managed_nodes.append(wheel)
	var omega := 0.0
	var torque := 3000.0  # per driven wheel, well above the tire's torque capacity
	for k in range(120):
		var slip := TireModel.calculate_slip_ratio(omega, 0.0, r)
		var f := TireModel.calculate_longitudinal_force(slip, 5000.0, cfg, ARCADE_GRIP, 1.0)
		var k_stiff := TireModel.calculate_longitudinal_stiffness(slip, 5000.0, cfg, ARCADE_GRIP, 1.0)
		omega = wheel.step_wheel_spin(DT, torque, 0.0, f, 0.0, true, k_stiff)
	# Torque beyond the tire's capacity -> sustained wheelspin: omega runs away
	# (real burnout count) and slip sits pinned at the cap (wheel pivot point).
	assert_that(is_finite(omega)).is_true()
	assert_that(omega).is_greater(5.0)
	var final_slip := TireModel.calculate_slip_ratio(omega, 0.0, r)
	assert_that(final_slip).is_greater(0.8)
	assert_that(TireModel.calculate_longitudinal_force(final_slip, 5000.0, cfg, ARCADE_GRIP, 1.0)).is_greater(0.0)

func test_airborne_wheel_spins_freely_twice_as_fast_as_grounded() -> void:
	var cfg := _starter()
	var r := WheelPhysics.WHEEL_RADIUS
	# Two independent wheels: each branch evolves from its OWN spin state.
	var grounded_wheel := WheelPhysics.new()
	var airborne_wheel := WheelPhysics.new()
	_managed_nodes.append(grounded_wheel)
	_managed_nodes.append(airborne_wheel)
	var grounded_omega := 0.0
	var airborne_omega := 0.0
	var torque := 1200.0  # below the tire's torque capacity (~1900 Nm), so the
	# grounded wheel reaches a traction equilibrium while the airborne wheel
	# keeps every newton to itself.
	for k in range(60):
		var slip := TireModel.calculate_slip_ratio(grounded_omega, 0.0, r)
		var f := TireModel.calculate_longitudinal_force(slip, 5000.0, cfg, ARCADE_GRIP, 1.0)
		var k_stiff := TireModel.calculate_longitudinal_stiffness(slip, 5000.0, cfg, ARCADE_GRIP, 1.0)
		grounded_omega = grounded_wheel.step_wheel_spin(DT, torque, 0.0, f, 0.0, true, k_stiff)
		airborne_omega = airborne_wheel.step_wheel_spin(DT, torque, 0.0, 0.0, 0.0, false, 0.0)
	assert_that(airborne_omega).is_greater(grounded_omega * 2.0)
	assert_that(is_finite(grounded_omega)).is_true()
	assert_that(is_finite(airborne_omega)).is_true()

func test_cruise_wheel_stays_stable_at_rolling_match() -> void:
	var cfg := _starter()
	var r := WheelPhysics.WHEEL_RADIUS
	var wheel := WheelPhysics.new()
	_managed_nodes.append(wheel)
	var v := 10.0  # m/s cruise
	var omega := 30.0
	var torque := 500.0
	for k in range(240):
		var slip := TireModel.calculate_slip_ratio(omega, v, r)
		var k_stiff := TireModel.calculate_longitudinal_stiffness(slip, 5000.0, cfg, ARCADE_GRIP, 1.0)
		var f := TireModel.calculate_longitudinal_force(slip, 5000.0, cfg, ARCADE_GRIP, 1.0)
		omega = wheel.step_wheel_spin(DT, torque, 0.0, f, v, true, k_stiff)
	# The semi-implicit update must NOT blow up: rolling match ~= v / r even at
	# initial wheelspin, 4 simulated seconds, constant torque.
	assert_that(is_finite(omega)).is_true()
	assert_that(omega).is_between(v / r * 0.5, v / r + 5.0)

func test_parked_wheel_pins_to_rolling_under_brake() -> void:
	var r := WheelPhysics.WHEEL_RADIUS
	var wheel := WheelPhysics.new()
	_managed_nodes.append(wheel)
	var omega := 10.0  # residual spin
	for k in range(60):
		omega = wheel.step_wheel_spin(DT, 0.0, 2000.0, 0.0, 0.0, true, 0.0)
	# Static hold: brake + grounded + |v| < 0.25 -> pins to rolling (0 here).
	assert_that(omega).is_equal_approx(0.0, 0.01)
	# Without a brake the wheel keeps whatever spin the axle gave it.
	var free := 0.0
	for k in range(30):
		free = wheel.step_wheel_spin(DT, 1200.0, 0.0, 0.0, 0.0, true, 0.0)
	assert_that(free).is_greater(5.0)

# --- Scene integration: real launch, driven axle out-rolls the front ---

func test_launch_spins_driven_rear_wheels_faster_than_front() -> void:
	var runner := scene_runner(TEST_SCENE)
	await runner.simulate_frames(5)
	var car := runner.scene().get_node("PlayerCar") as VehiclePhysics
	assert_that(car).is_not_null()
	if car == null:
		return
	assert_that(car.freeze).is_false()
	car.set_input_override(Vector2(0.0, 1.0))
	await runner.simulate_frames(240)
	var info := car.get_drive_info()
	assert_that(float(info["speed_kmh"])).is_greater(8.0)
	assert_that(float(info["rpm"])).is_greater(car.config.idle_rpm)
	# RWD: the driven axle spins faster than the free-rolling front axle, and
	# neither wheel speed is allowed to go NaN.
	var rear := maxf(absf(car.wheel_rl.wheel_angular_velocity), absf(car.wheel_rr.wheel_angular_velocity))
	var front := maxf(absf(car.wheel_fl.wheel_angular_velocity), absf(car.wheel_fr.wheel_angular_velocity))
	assert_that(is_finite(rear)).is_true()
	assert_that(is_finite(front)).is_true()
	assert_that(rear).is_greater(front)
	assert_that(rear).is_greater(1.0)