# tests/suites/test_weather_fx_bootstrap.gd
extends GdUnitTestSuite

## Regression gate for the per-frame script-error spam out of
## world_driver._sync_weather_state(): the day_night_driver autoload emits
## time_of_day_changed from frame 1, but _wet_overlay / _windshield_overlay are
## only built by _bootstrap_weather_fx() — step 7 of the await-chained _ready() —
## so the clock signal reached the switch-over while both overlays were still
## Nil and every frame raised "Invalid assignment of property or key 'visible'
## ... on a base object of type 'Nil'". The step-5 clock wiring therefore lives
## two steps ahead of the step-7 overlay build. This pins both halves: a bare
## headless driver whose overlays are still Nil syncs with no runtime error, and
## once the bootstrap has built them the guarded calls still drive them.
##
## The phase split mirrors the production ordering: pre_check = the step-5/step-7
## window, check_part_a = the reported DayNightDriver._tick stack inside that
## window, check_part_b = the same signal path after the step-7 bootstrap.

## Untyped on purpose: the autoload script has no class_name, so the instance
## stays dynamically typed like the clock instance in test_weather_sun.gd.
const DayNightDriverScript: GDScript = preload("res://autoload/day_night_driver.gd")

## Frames needed to walk WorldDriver._ready() through its await-chained steps
## up to and past _bootstrap_weather_fx() (step 7) — the 8th frame resumes it.
const BOOTSTRAP_FRAMES := 10

## One frame of the shipped clock rate (DayNightDriver.HOURS_PER_SECOND == 0.01).
const HOURS_PER_FRAME := 0.01

var _managed: Array = []
var _saved_weather: WeatherManager.Weather = WeatherManager.Weather.CLEAR
var _saved_tod: float = 12.0

func before_test() -> void:
	_managed.clear()
	_saved_weather = WeatherManager.current_weather
	_saved_tod = WeatherManager.time_of_day

func after_test() -> void:
	for node in _managed:
		if is_instance_valid(node):
			node.free()
	_managed.clear()
	# Direct field writes, not set_weather()/set_time_of_day(), so teardown
	# cannot re-emit into every other suite's still-connected world driver.
	WeatherManager.current_weather = _saved_weather
	WeatherManager.time_of_day = _saved_tod

## Bare headless driver, mirroring test_map_route.gd: _ready() runs up to its
## first await, so the weather FX bootstrap has NOT happened yet.
func _new_driver() -> WorldDriver:
	var driver := WorldDriver.new()
	driver.name = "WeatherFXDriver"
	_managed.append(driver)
	add_child(driver)
	return driver

## Walks the real _ready() step chain, one time_of_day_changed emit per frame,
## so every resumed step (and the per-frame clock tick in the shipped game) is
## preceded by a real signal that runs _sync_weather_state.
func _run_bootstrap() -> void:
	for _i in BOOTSTRAP_FRAMES:
		WeatherManager.advance_time(HOURS_PER_FRAME)
		await get_tree().process_frame

## The reported stack: _process -> _tick -> WeatherManager.advance_time ->
## set_time_of_day -> time_of_day_changed -> _on_time_of_day_changed ->
## _sync_weather_state, plus the _on_weather_changed hop, both with the
## overlays still Nil.
func _sync_with_nil_overlays(clock: Variant, driver: WorldDriver) -> void:
	clock._tick(60.0)
	driver.call("_on_weather_changed", WeatherManager.current_weather)

## The two WeatherManager signal hops into the switch-over, on a driver that
## has finished the weather FX bootstrap.
func _drive_signals(weather: WeatherManager.Weather, hour: float) -> void:
	WeatherManager.set_weather(weather)
	WeatherManager.set_time_of_day(hour)

func test_pre_check_overlays_are_nil_while_the_clock_signal_is_live() -> void:
	var driver := _new_driver()
	# Step 5 of _ready() connects the clock signal; step 7 builds the overlays.
	# Calling the production step directly reproduces that exact window.
	driver.call("_bootstrap_sun_driver")

	assert_that(
		WeatherManager.time_of_day_changed.is_connected(driver._on_time_of_day_changed)
	).is_true()
	assert_object(driver._fx_layer).is_null()
	assert_object(driver._wet_overlay).is_null()
	assert_object(driver._windshield_overlay).is_null()

func test_check_part_a_clock_tick_sync_is_error_free_before_bootstrap() -> void:
	var driver := _new_driver()
	driver.call("_bootstrap_sun_driver")
	var rain := RainSystem.new()
	rain.name = "RainSystem"
	_managed.append(rain)
	driver.add_child(rain)
	driver._rain_system = rain
	var clock = DayNightDriverScript.new()
	_managed.append(clock)
	add_child(clock)
	clock._weather_timer = 9999.0
	# Night + storm: the wet tint rule is armed, so the unguarded calls would
	# have written .visible onto a Nil ColorRect.
	WeatherManager.current_weather = WeatherManager.Weather.STORM
	WeatherManager.time_of_day = 0.0

	await assert_error(_sync_with_nil_overlays.bind(clock, driver)).is_success()

	# The guarded nil entries must not have taken the rest of the switch-over
	# with them: the rain half of the same call still ran.
	assert_that(rain.is_raining()).is_true()
	assert_object(driver._wet_overlay).is_null()
	assert_object(driver._windshield_overlay).is_null()

func test_check_part_b_bootstrapped_overlays_are_still_driven() -> void:
	var driver := _new_driver()
	driver.call("_bootstrap_sun_driver")
	driver.call("_bootstrap_weather_fx")
	var wet := driver._wet_overlay
	var shield := driver._windshield_overlay
	assert_object(driver._fx_layer).is_not_null()
	assert_object(wet).is_not_null()
	assert_object(shield).is_not_null()

	# Night + storm over the real signal paths: the wet tint rule fires and
	# both overlays are driven exactly as they were before the guards.
	await assert_error(
		_drive_signals.bind(WeatherManager.Weather.STORM, 0.0)
	).is_success()
	var intensity := WetSurface.wet_intensity(WeatherManager.get_road_grip_factor())
	assert_float(intensity).is_greater(0.0)
	assert_that(wet.visible).is_true()
	assert_float(wet.color.a).is_equal_approx(
		WetSurface.OVERLAY_ALPHA_MAX * intensity, 0.001
	)
	# No rain system on this driver and no forward-view camera, so the
	# windshield overlay parks invisible.
	assert_that(shield.visible).is_false()

	# Dry day: both overlays park invisible and the wet alpha returns to zero.
	await assert_error(
		_drive_signals.bind(WeatherManager.Weather.CLEAR, 12.0)
	).is_success()
	assert_that(wet.visible).is_false()
	assert_float(wet.color.a).is_equal(0.0)
	assert_that(shield.visible).is_false()

## The shipped ordering end to end: the await-chained _ready() resumes through
## its eight steps while the clock keeps emitting, and no step in between (nor
## after the step-7 bootstrap) raises a runtime error.
func test_bootstrap_frames_never_sync_a_nil_overlay() -> void:
	var driver := _new_driver()
	WeatherManager.current_weather = WeatherManager.Weather.STORM
	WeatherManager.time_of_day = 0.0
	assert_object(driver._wet_overlay).is_null()

	await assert_error(_run_bootstrap).is_success()

	# Step 7 has run by now, so the overlays exist and live under the FX layer.
	assert_object(driver._wet_overlay).is_not_null()
	assert_object(driver._windshield_overlay).is_not_null()
	assert_object(driver._fx_layer).is_not_null()
	assert_that(driver._wet_overlay.visible).is_true()
