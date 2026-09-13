# tests/suites/test_weather_sun.gd
extends GdUnitTestSuite

## Q6 WeatherManager sun driver — pure logic only (no scene runner). Sweeps the
## 24h clock against WorldDriver.sun_direction() / compute_sun_transform() and
## verifies the baked sun stays finite, stays above the horizon, stays
## orthonormal, and that applying it to a DirectionalLight3D never turns
## shadow_enabled off. Lights are built by hand and freed in after_test so the
## suite stays orphan-free (mirrors tests/suites/test_race_loop.gd).

const SAMPLE_STEP_HOURS := 0.25
const TOLERANCE := Vector3(0.001, 0.001, 0.001)

var _managed_lights: Array = []

func before_test() -> void:
	_managed_lights.clear()

func after_test() -> void:
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