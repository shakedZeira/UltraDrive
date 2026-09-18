# tests/suites/test_weather_sun.gd
extends GdUnitTestSuite

## Q6 WeatherManager sun driver — pure logic only (no scene runner). Sweeps the
## 24h clock against WorldDriver.sun_direction() / compute_sun_transform() and
## verifies the baked sun stays finite, stays above the horizon, stays
## orthonormal, and that applying it to a DirectionalLight3D never turns
## shadow_enabled off. Lights and a DayNightDriver instance are built by hand
## and freed in after_test so the suite stays orphan-free (mirrors
## tests/suites/test_race_loop.gd). The driver-tick test drives the real clock
## path (Time advance + time_of_day_changed) and checks the baked sun follows
## it, so P4 clock mechanics are pinned end-to-end with the sun math.

const SAMPLE_STEP_HOURS := 0.25
const TOLERANCE := Vector3(0.001, 0.001, 0.001)

var _managed_lights: Array = []
var _managed_nodes: Array = []
var _tod_signal_count := 0
var _prev_tod: float = 12.0

func _on_tod(_hour: float) -> void:
	_tod_signal_count += 1

func before_test() -> void:
	_managed_lights.clear()
	_managed_nodes.clear()
	_tod_signal_count = 0
	_prev_tod = WeatherManager.time_of_day

func after_test() -> void:
	WeatherManager.time_of_day = _prev_tod
	for node in _managed_nodes:
		if is_instance_valid(node):
			node.free()
	_managed_nodes.clear()
	for light in _managed_lights:
		if is_instance_valid(light):
			light.free()
	_managed_lights.clear()

func _sweep_hours() -> Array[float]:
	var hours: Array[float] = []
	var steps := int(roundf(24.0 / SAMPLE_STEP_HOURS))
	for i in range(steps + 1):
		hours.append(float(i) * SAMPLE_STEP_HOURS)
	return hours

func _is_finite_vec(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

func _is_finite_basis(b: Basis) -> bool:
	return _is_finite_vec(b.x) and _is_finite_vec(b.y) and _is_finite_vec(b.z)

func test_sun_direction_is_finite_across_24h() -> void:
	for hour in _sweep_hours():
		var dir := WorldDriver.sun_direction(hour)
		assert_that(_is_finite_vec(dir)).is_true()

func test_sun_direction_stays_above_horizon_across_24h() -> void:
	for hour in _sweep_hours():
		var dir := WorldDriver.sun_direction(hour)
		assert_float(dir.y).is_greater(0.0)
		assert_float(dir.y).is_greater(WorldDriver.SUN_MIN_ELEVATION - 0.001)

func test_sun_direction_matches_weather_manager_at_noon() -> void:
	var expected := WeatherManager.get_computed_sun_position()
	var dir := WorldDriver.sun_direction(12.0)
	assert_that(dir).is_equal_approx(expected, TOLERANCE)

func test_compute_sun_transform_basis_is_orthonormal_across_24h() -> void:
	for hour in _sweep_hours():
		var transform := WorldDriver.compute_sun_transform(hour)
		var basis := transform.basis
		assert_that(_is_finite_basis(basis)).is_true()
		assert_float(basis.x.length()).is_equal_approx(1.0, 0.001)
		assert_float(basis.y.length()).is_equal_approx(1.0, 0.001)
		assert_float(basis.z.length()).is_equal_approx(1.0, 0.001)
		assert_float(basis.x.dot(basis.y)).is_equal_approx(0.0, 0.001)
		assert_float(basis.y.dot(basis.z)).is_equal_approx(0.0, 0.001)
		assert_float(basis.z.dot(basis.x)).is_equal_approx(0.0, 0.001)

func test_compute_sun_transform_z_axis_points_at_sun_dir() -> void:
	for hour in _sweep_hours():
		var transform := WorldDriver.compute_sun_transform(hour)
		assert_that(transform.basis.z).is_equal_approx(
			WorldDriver.sun_direction(hour), TOLERANCE)

func test_apply_sun_transform_snaps_and_keeps_shadow_enabled() -> void:
	var sun := DirectionalLight3D.new()
	_managed_lights.append(sun)
	sun.shadow_enabled = true
	WorldDriver.apply_sun_transform(sun, 12.0, true)
	assert_bool(sun.shadow_enabled).is_true()
	assert_float(sun.transform.basis.z.y).is_greater(0.0)
	assert_that(_is_finite_basis(sun.transform.basis)).is_true()

func test_apply_sun_transform_lerps_toward_target_without_pop() -> void:
	var sun := DirectionalLight3D.new()
	_managed_lights.append(sun)
	sun.shadow_enabled = true
	sun.transform = WorldDriver.compute_sun_transform(0.0)
	# A large noonday jump, eased in: every intermediate sun stays finite,
	# above the horizon, and shadow_enabled is never touched.
	for _i in 8:
		WorldDriver.apply_sun_transform(sun, 12.0, false)
		assert_bool(sun.shadow_enabled).is_true()
		assert_float(sun.transform.basis.z.y).is_greater(0.0)
		assert_that(_is_finite_basis(sun.transform.basis)).is_true()

func test_driver_tick_advances_clock_signals_and_moves_sun() -> void:
	var driver = preload("res://autoload/day_night_driver.gd").new()
	_managed_nodes.append(driver)
	add_child(driver)
	driver._weather_timer = 9999.0
	WeatherManager.set_time_of_day(12.0)
	WeatherManager.time_of_day_changed.connect(_on_tod)
	driver._tick(60.0)
	WeatherManager.time_of_day_changed.disconnect(_on_tod)
	assert_int(_tod_signal_count).is_equal(1)
	var expected := fposmod(12.0 + 60.0 * DayNightDriver.HOURS_PER_SECOND, 24.0)
	assert_float(WeatherManager.time_of_day).is_equal_approx(expected, 0.01)
	var transform := WorldDriver.compute_sun_transform(WeatherManager.time_of_day)
	assert_that(_is_finite_basis(transform.basis)).is_true()
	assert_float(transform.basis.z.y).is_greater(0.0)