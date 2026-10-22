# tests/suites/test_traction_hud.gd
extends GdUnitTestSuite

## Roadmap #4 gate: the wheelspin "cone" lamp and the HP delta readout.
##
## The lamp signal is pure (WheelspinGauge reads only the wheel state
## VehiclePhysics already integrates) so the threshold behaviour is asserted
## directly, plus ONE integration pass over a real headless VehiclePhysics
## rig whose WheelPhysics children carry real wheel_angular_velocity /
## is_in_contact values. The HP readout is pure math over CarConfig's own
## torque curve. Nothing here touches transmission or grip physics.

const TEST_SPEED_MPS := 30.0

var _managed: Array = []

func before_test() -> void:
	_managed.clear()
	# Hermetic HUD read: no player car registered from an earlier suite, so the
	# power line has no config to read and must render its placeholder.
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

func after_test() -> void:
	for node in _managed:
		if is_instance_valid(node):
			node.free()
	_managed.clear()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

## A VehiclePhysics with the four WheelPhysics children its @onready handles
## require, so severity_for_car() can read real wheel nodes.
func _new_rig() -> VehiclePhysics:
	var car := VehiclePhysics.new()
	car.name = "TractionRig"
	for wheel_name in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		var wheel := WheelPhysics.new()
		wheel.name = wheel_name
		car.add_child(wheel)
	add_child(car)
	_managed.append(car)
	return car

func _rolling(speed_mps: float = TEST_SPEED_MPS) -> float:
	return WheelspinGauge.rolling_match(speed_mps)

## Four planted wheels at exactly the rolling match: the lamp must be dark.
func _planted() -> Array:
	var rolling := _rolling()
	return [rolling, rolling, rolling, rolling]

# --- Threshold behaviour --------------------------------------------------

func test_rolling_match_uses_the_shared_wheel_radius() -> void:
	assert_that(_rolling(0.0)).is_equal(0.0)
	assert_that(_rolling(-5.0)).is_equal(0.0)
	assert_that(_rolling(33.0)).is_equal(33.0 / WheelPhysics.WHEEL_RADIUS)

func test_planted_wheels_at_the_rolling_match_leave_the_lamp_off() -> void:
	assert_that(WheelspinGauge.severity_for_wheels(_planted(), [true, true, true, true], TEST_SPEED_MPS)).is_equal(0.0)

func test_lamp_lights_just_past_the_rolling_match_ratio() -> void:
	var rolling := _rolling()
	# 1.25x exactly is the threshold, and the established detection is a STRICT
	# ">" against it, so exactly 1.25x must still read as planted.
	assert_that(WheelspinGauge.is_spinning(rolling * 1.25, TEST_SPEED_MPS, true)).is_false()
	assert_that(WheelspinGauge.severity_for_wheels(
		[rolling * 1.25], [true], TEST_SPEED_MPS)).is_equal(0.0)
	# A quarter-percent past the match lights it.
	assert_that(WheelspinGauge.is_spinning(rolling * 1.26, TEST_SPEED_MPS, true)).is_true()
	assert_that(WheelspinGauge.severity_for_wheels(
		[rolling * 1.26], [true], TEST_SPEED_MPS)).is_greater(0.0)
	# A 3x spin is deep into the ramp but NOT yet saturated: the red end of the
	# lamp is pinned to SEVERITY_SLIP_FULL, so severity is
	# (3.0 - 1.25) / (3.25 - 1.25) = 0.875 here. Approx, not exact: the
	# division leaves float residue and gdUnit4's is_equal is bit-exact.
	assert_that(WheelspinGauge.severity_for_wheels(
		[rolling * 3.0], [true], TEST_SPEED_MPS)).is_equal_approx(0.875, 0.001)
	# Only a slip of SEVERITY_SLIP_FULL saturates it.
	assert_that(WheelspinGauge.severity_for_wheels(
		[rolling * WheelspinGauge.SEVERITY_SLIP_FULL], [true], TEST_SPEED_MPS)).is_equal_approx(1.0, 0.001)
	# Past the red end the lamp stays pinned, never extrapolates.
	assert_that(WheelspinGauge.severity_for_wheels(
		[rolling * 9.0], [true], TEST_SPEED_MPS)).is_equal_approx(1.0, 0.001)

func test_lamp_is_off_while_slow_or_planted() -> void:
	var rolling := _rolling()
	# Crawling: an enormous omega is noise, not traction loss.
	assert_that(WheelspinGauge.is_spinning(500.0, 0.0, true)).is_false()
	assert_that(WheelspinGauge.severity_for_wheels([500.0], [true], 0.0)).is_equal(0.0)
	assert_that(WheelspinGauge.severity_for_wheels(
		[500.0], [true], WheelspinGauge.MIN_SPEED_MPS - 0.01)).is_equal(0.0)
	# Rolling but planted.
	assert_that(WheelspinGauge.severity_for_wheels(
		[rolling * 0.9, rolling * 1.1], [true, true], TEST_SPEED_MPS)).is_equal(0.0)
	# Just over the crawl floor a real spin still registers.
	assert_that(WheelspinGauge.severity_for_wheels(
		[500.0], [true], WheelspinGauge.MIN_SPEED_MPS)).is_greater(0.0)

func test_airborne_wheels_never_light_the_lamp() -> void:
	assert_that(WheelspinGauge.is_spinning(400.0, TEST_SPEED_MPS, false)).is_false()
	assert_that(WheelspinGauge.severity_for_wheels(
		[400.0, 400.0, 400.0, 400.0], [false, false, false, false], TEST_SPEED_MPS)).is_equal(0.0)
	# One airborne spinner among planted wheels stays dark.
	var rolling := _rolling()
	assert_that(WheelspinGauge.severity_for_wheels(
		[400.0, rolling, rolling, rolling], [false, true, true, true], TEST_SPEED_MPS)).is_equal(0.0)

func test_lamp_takes_the_worst_wheel_not_the_average() -> void:
	var rolling := _rolling()
	var mixed := WheelspinGauge.severity_for_wheels(
		[rolling, rolling, rolling, rolling * WheelspinGauge.SEVERITY_SLIP_FULL],
		[true, true, true, true], TEST_SPEED_MPS)
	assert_that(mixed).is_equal_approx(1.0, 0.001)
	var mild := WheelspinGauge.severity_for_wheels(
		[rolling, rolling, rolling, rolling * 1.3], [true, true, true, true], TEST_SPEED_MPS)
	assert_that(mild).is_greater(0.0)
	assert_that(mild).is_less(1.0)

func test_severity_ramps_monotonically_amber_to_red() -> void:
	var rolling := _rolling()
	var previous := -1.0
	for step in range(0, 13):
		var slip := WheelspinGauge.SPIN_RATIO + float(step) * 0.2
		var severity := WheelspinGauge.severity_for_wheels(
			[rolling * slip], [true], TEST_SPEED_MPS)
		assert_that(severity).is_greater_equal(previous)
		previous = severity
	# A brake lockup is signed omega, so the sign must not hide the slip.
	var reverse := WheelspinGauge.severity_for_wheels(
		[-(rolling * WheelspinGauge.SEVERITY_SLIP_FULL)], [true], TEST_SPEED_MPS)
	assert_that(reverse).is_equal_approx(1.0, 0.001)

func test_short_contact_array_reads_as_no_contact() -> void:
	var rolling := _rolling()
	assert_that(WheelspinGauge.severity_for_wheels(
		[rolling * 3.0], [], TEST_SPEED_MPS)).is_equal(0.0)
	assert_that(WheelspinGauge.severity_for_wheels([], [], TEST_SPEED_MPS)).is_equal(0.0)

func test_lamp_colour_spans_off_amber_red() -> void:
	assert_that(WheelspinGauge.lamp_color(0.0)).is_equal(WheelspinGauge.COLOR_OFF)
	# The ramp is AMBER -> RED, so the green channel is the one that falls. Blue
	# is deliberately close at both ends and is NOT a monotonic ramp axis.
	var off := WheelspinGauge.lamp_color(0.0)
	var lit := WheelspinGauge.lamp_color(0.001)
	assert_that(lit.r).is_equal_approx(1.0, 0.001)
	assert_that(lit.g).is_greater(0.5)
	assert_that(lit.b).is_less(0.3)
	var red := WheelspinGauge.lamp_color(1.0)
	assert_that(red.r).is_equal_approx(1.0, 0.001)
	assert_that(red.g).is_less(lit.g)
	assert_that(red.g).is_less(WheelspinGauge.COLOR_AMBER.g * 0.5)
	# The off-state is a dim grey-blue, clearly not a lit lamp.
	assert_that(off.g).is_less(lit.g)
	# The midpoint really is a blend between the two anchors.
	var mid := WheelspinGauge.lamp_color(0.5)
	assert_that(mid.g).is_between(red.g, lit.g)
	# Out-of-range severity is clamped, never extrapolated.
	assert_that(WheelspinGauge.lamp_color(5.0)).is_equal(WheelspinGauge.COLOR_RED)
	assert_that(WheelspinGauge.lamp_color(-3.0)).is_equal(WheelspinGauge.COLOR_OFF)

# --- Integration over a real headless vehicle -----------------------------

func test_null_car_keeps_the_lamp_dark() -> void:
	assert_that(WheelspinGauge.severity_for_car(null)).is_equal(0.0)

func test_car_without_wheel_nodes_keeps_the_lamp_dark() -> void:
	# A bare VehiclePhysics never entered the tree has null @onready handles.
	var car := VehiclePhysics.new()
	_managed.append(car)
	assert_that(WheelspinGauge.severity_for_car(car)).is_equal(0.0)

func test_lamp_reads_real_wheel_physics_nodes_on_a_headless_vehicle() -> void:
	var car := _new_rig()
	await get_tree().process_frame
	var rolling := _rolling()
	for wheel: WheelPhysics in [car.wheel_fl, car.wheel_fr, car.wheel_rl, car.wheel_rr]:
		wheel.is_in_contact = true
		wheel.wheel_angular_velocity = rolling
	assert_that(car.wheel_fl).is_not_null()
	assert_that(car.wheel_rr).is_not_null()
	# Planted: dark.
	car.linear_velocity = Vector3(0.0, 0.0, TEST_SPEED_MPS)
	assert_that(WheelspinGauge.severity_for_car(car)).is_equal(0.0)
	# One wheel off its rolling match: lit.
	car.wheel_rr.wheel_angular_velocity = rolling * 3.0
	assert_that(WheelspinGauge.severity_for_car(car)).is_greater(0.0)
	# Airborne again: dark.
	car.wheel_rr.is_in_contact = false
	assert_that(WheelspinGauge.severity_for_car(car)).is_equal(0.0)
	# And with the car stopped the same spin is noise again.
	car.wheel_rr.is_in_contact = true
	car.linear_velocity = Vector3.ZERO
	assert_that(WheelspinGauge.severity_for_car(car)).is_equal(0.0)

# --- The lamp widget ------------------------------------------------------

func test_traction_lamp_hides_itself_when_planted_and_lights_when_spinning() -> void:
	var lamp := TractionLamp.new()
	add_child(lamp)
	_managed.append(lamp)
	await get_tree().process_frame
	assert_that(lamp.visible).is_false()
	assert_that(lamp.get_severity()).is_equal(0.0)
	lamp.set_severity(0.4)
	assert_that(lamp.get_severity()).is_equal(0.4)
	assert_that(lamp.visible).is_true()
	# Out-of-range severity is clamped into the 0..1 the widget draws.
	lamp.set_severity(9.0)
	assert_that(lamp.get_severity()).is_equal(1.0)
	lamp.set_severity(-2.0)
	assert_that(lamp.get_severity()).is_equal(0.0)
	assert_that(lamp.visible).is_false()

func test_hud_wires_the_lamp_power_and_torque_lines_from_a_stub_car() -> void:
	var runner := scene_runner("res://scenes/ui/hud.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as RaceUI
	var lamp := scene.get_node("%TractionLamp") as TractionLamp
	var power := scene.get_node("%PowerValue") as Label
	var torque := scene.get_node("%TorqueValue") as Label
	assert_that(lamp).is_not_null()
	assert_that(power).is_not_null()
	assert_that(torque).is_not_null()
	assert_that(lamp.visible).is_false()
	# No player car registered -> a config-less car yields both placeholder
	# lines and an off lamp, never a crash.
	assert_that(power.text).is_equal(PowerGauge.format_text(null, 0.0))
	assert_that(power.text).is_equal("-- hp")
	assert_that(torque.text).is_equal(PowerGauge.format_torque_text(null, 0.0))
	assert_that(torque.text).is_equal("-- Nm")
	# Drive the lamp directly the way _refresh_traction_lamp does.
	lamp.set_severity(0.75)
	assert_that(lamp.visible).is_true()
	lamp.set_severity(WheelspinGauge.severity_for_car(null))
	assert_that(lamp.visible).is_false()

## A registered stub car (never added to the tree, so its drivetrain stays null
## and get_drive_info() reports rpm 0) must drive BOTH cluster readouts from
## the live rpm — and neither may ever carry a minus sign.
func test_hud_power_and_torque_lines_track_a_registered_stub_car() -> void:
	var car := VehiclePhysics.new()
	car.config = CarConfig.new()
	car.config.max_torque = 500.0
	_managed.append(car)
	VehicleManager.register_player_car(car)
	var runner := scene_runner("res://scenes/ui/hud.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as RaceUI
	var power := scene.get_node("%PowerValue") as Label
	var torque := scene.get_node("%TorqueValue") as Label
	# Expectations come from the SAME info the HUD reads, not hard-coded hp.
	var rpm := float(car.get_drive_info().get("rpm", 0.0))
	assert_that(rpm).is_equal(0.0)
	assert_that(power.text).is_equal(PowerGauge.format_text(car.config, rpm))
	assert_that(torque.text).is_equal(PowerGauge.format_torque_text(car.config, rpm))
	# rpm 0 is below idle, so the spec curve reads "0 hp" / "250 Nm" (half of
	# the 500 Nm max_torque) — both positive, no sign token anywhere.
	assert_that(power.text).is_equal("0 hp")
	assert_that(torque.text).is_equal("250 Nm")
	# THE user-facing contract: no leading minus on either readout.
	assert_that(power.text.begins_with("-")).is_false()
	assert_that(torque.text.contains("-")).is_false()
	VehicleManager.remove_car(car)

# --- HP + torque readout --------------------------------------------------

func test_rated_peak_is_the_max_of_the_torque_curve_not_the_peak_rpm_sample() -> void:
	var cfg := CarConfig.new()
	cfg.max_torque = 300.0
	cfg.peak_rpm = 6500.0
	cfg.idle_rpm = 800.0
	cfg.redline_rpm = 7500.0
	# The rated peak is the curve's own maximum...
	var at_peak := PowerGauge.max_power_rpm(cfg)
	var expected := cfg.get_engine_torque(at_peak) * at_peak * TAU / 60.0 / PowerGauge.WATTS_PER_HP
	assert_that(PowerGauge.peak_power_hp(cfg)).is_equal_approx(expected, 0.001)
	# ...which is NOT the peak_rpm sample: torque falls parabolically while rpm
	# keeps climbing, so the product tops out a little above peak_rpm. Rating
	# the car at peak_rpm would understate it and leave a negative delta at the
	# real power peak.
	assert_that(at_peak).is_greater(cfg.peak_rpm)
	assert_that(at_peak).is_less(cfg.redline_rpm)
	assert_that(PowerGauge.peak_power_hp(cfg)).is_greater(
		PowerGauge.power_hp(cfg, cfg.peak_rpm))
	# ~275 hp for the stock 300 Nm engine.
	assert_that(PowerGauge.peak_power_hp(cfg)).is_between(250.0, 300.0)

func test_delta_is_zero_at_the_power_peak_and_negative_elsewhere() -> void:
	var cfg := CarConfig.new()
	var at_peak := PowerGauge.max_power_rpm(cfg)
	assert_that(PowerGauge.hp_delta_hp(cfg, at_peak)).is_equal_approx(0.0, 0.001)
	assert_that(PowerGauge.hp_delta_hp(cfg, cfg.idle_rpm)).is_less(0.0)
	assert_that(PowerGauge.hp_delta_hp(cfg, cfg.peak_rpm)).is_less(0.0)
	assert_that(PowerGauge.hp_delta_hp(cfg, cfg.redline_rpm)).is_less(0.0)
	# A bigger-engine car is rated higher, so the same rpm is a smaller gap.
	var fast := CarConfig.new()
	fast.max_torque = 600.0
	assert_that(PowerGauge.peak_power_hp(fast)).is_greater(PowerGauge.peak_power_hp(cfg))
	assert_that(PowerGauge.hp_delta_hp(fast, cfg.idle_rpm)).is_less(PowerGauge.hp_delta_hp(cfg, cfg.idle_rpm))

func test_power_never_exceeds_the_rated_peak_across_the_rev_range() -> void:
	var cfg := CarConfig.new()
	var peak := PowerGauge.peak_power_hp(cfg)
	var rpm := cfg.idle_rpm
	while rpm <= cfg.redline_rpm + 500.0:
		assert_that(PowerGauge.power_hp(cfg, rpm)).is_less_equal(peak + 0.001)
		assert_that(PowerGauge.hp_delta_hp(cfg, rpm)).is_less_equal(0.001)
		rpm += 250.0
	# A fine sweep on the scan grid too, so a bad peak search cannot hide.
	rpm = cfg.idle_rpm
	while rpm <= cfg.redline_rpm:
		assert_that(PowerGauge.power_hp(cfg, rpm)).is_less_equal(peak + 0.001)
		rpm += PowerGauge.PEAK_SCAN_STEP_RPM
	# Above the redline the torque curve is zero, so the readout is too.
	assert_that(PowerGauge.power_hp(cfg, cfg.redline_rpm + 1.0)).is_equal(0.0)
	assert_that(PowerGauge.power_hp(cfg, 0.0)).is_equal(0.0)
	assert_that(PowerGauge.power_hp(cfg, -100.0)).is_equal(0.0)

func test_null_config_is_safe_everywhere() -> void:
	assert_that(PowerGauge.power_hp(null, 5000.0)).is_equal(0.0)
	assert_that(PowerGauge.peak_power_hp(null)).is_equal(0.0)
	assert_that(PowerGauge.hp_delta_hp(null, 5000.0)).is_equal(0.0)
	assert_that(PowerGauge.format_text(null, 5000.0)).is_equal("-- hp")
	assert_that(PowerGauge.torque_nm(null, 5000.0)).is_equal(0.0)
	assert_that(PowerGauge.format_torque_text(null, 5000.0)).is_equal("-- Nm")

func test_format_text_renders_current_hp_with_no_sign_token() -> void:
	var cfg := CarConfig.new()
	var at_peak := PowerGauge.max_power_rpm(cfg)
	# Exactly "<n> hp": current crank power, no delta, no sign.
	assert_that(PowerGauge.format_text(cfg, at_peak)).is_equal(
		"%d hp" % roundi(PowerGauge.peak_power_hp(cfg)))
	assert_that(PowerGauge.format_text(cfg, cfg.idle_rpm)).is_equal(
		"%d hp" % roundi(PowerGauge.power_hp(cfg, cfg.idle_rpm)))
	# Above the redline the curve is zero, and it must read "0 hp" not "-<n>".
	assert_that(PowerGauge.format_text(cfg, cfg.redline_rpm + 500.0)).is_equal("0 hp")
	# The placeholder contract is unchanged (also asserted by the wiring test).
	assert_that(PowerGauge.format_text(null, 5000.0)).is_equal("-- hp")
	# No sign character can appear anywhere in a rendered line.
	assert_that(PowerGauge.format_text(cfg, cfg.idle_rpm).contains("-")).is_false()
	assert_that(PowerGauge.format_text(cfg, at_peak).contains("+")).is_false()
	assert_that(PowerGauge.signed_hp(12.4)).is_equal("+12")
	assert_that(PowerGauge.signed_hp(-12.6)).is_equal("-13")
	assert_that(PowerGauge.signed_hp(0.0)).is_equal("+0")

func test_torque_nm_reads_the_spec_sheet_curve_in_newton_metres() -> void:
	var cfg := CarConfig.new()
	cfg.max_torque = 300.0
	cfg.peak_rpm = 6500.0
	cfg.idle_rpm = 800.0
	cfg.redline_rpm = 7500.0
	# At peak_rpm the curve is exactly max_torque (the .tres spec figure).
	assert_that(PowerGauge.torque_nm(cfg, cfg.peak_rpm)).is_equal_approx(300.0, 0.01)
	# The displayed hp and Nm are the same curve sample: P = tau * omega.
	var rpm := cfg.idle_rpm
	while rpm <= cfg.redline_rpm:
		var expected_hp := PowerGauge.torque_nm(cfg, rpm) * rpm * TAU / 60.0 / PowerGauge.WATTS_PER_HP
		assert_that(PowerGauge.power_hp(cfg, rpm)).is_equal_approx(expected_hp, 0.001)
		assert_that(PowerGauge.format_torque_text(cfg, rpm)).is_equal(
			"%d Nm" % roundi(PowerGauge.torque_nm(cfg, rpm)))
		rpm += 500.0
	# Past the redline the curve is zero -> "0 Nm", never a negative number.
	assert_that(PowerGauge.torque_nm(cfg, cfg.redline_rpm + 500.0)).is_equal(0.0)
	assert_that(PowerGauge.format_torque_text(cfg, cfg.redline_rpm + 500.0)).is_equal("0 Nm")
	# A bigger engine shows more torque (spec-sheet monotonicity).
	var fast := CarConfig.new()
	fast.max_torque = 600.0
	assert_that(PowerGauge.torque_nm(fast, fast.peak_rpm)).is_greater(
		PowerGauge.torque_nm(cfg, cfg.peak_rpm))
