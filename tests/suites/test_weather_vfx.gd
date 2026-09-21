# tests/suites/test_weather_vfx.gd
extends GdUnitTestSuite

## Item 12 gate: weather VFX + night switch-over + wet-road feel. The rule set
## already lives in WeatherManager (ROAD_GRIP, time_of_day); this pins the FEEL
## layer that reads it: wet overlay intensity is a monotonic pure function of
## the grip factor, headlights toggle exactly on WeatherManager.is_night(),
## the windshield droplet shader only runs in chase-cam mode while rain is up,
## rain particles are headless-culled (state machine still runs), and the
## weather ambience bed maps weather -> volume on a fixed monotonic ladder
## without touching AudioServer (no bus leak).

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
	WeatherManager.set_weather(_saved_weather)
	WeatherManager.set_time_of_day(_saved_tod)

func _new_root() -> Node:
	var root := Node.new()
	root.name = "TestRoot"
	_managed.append(root)
	add_child(root)
	return root

func test_wet_intensity_zero_at_dry_grip() -> void:
	assert_float(WetSurface.wet_intensity(1.0)).is_equal(0.0)
	assert_float(WetSurface.wet_intensity(1.5)).is_equal(0.0)

func test_wet_intensity_full_at_wettest_grip() -> void:
	assert_float(WetSurface.wet_intensity(0.45)).is_equal(1.0)
	assert_float(WetSurface.wet_intensity(0.2)).is_equal(1.0)
	assert_float(WetSurface.wet_intensity(0.0)).is_equal(1.0)

func test_wet_intensity_monotonic_with_grip_factor() -> void:
	var prev := 0.0
	for value in range(105, -1, -5):
		var intensity := WetSurface.wet_intensity(float(value) / 100.0)
		assert_float(intensity).is_greater_equal(prev - 0.0001)
		assert_float(intensity).is_less_equal(1.0)
		prev = intensity

func test_wet_intensity_midpoint_is_half() -> void:
	assert_float(WetSurface.wet_intensity(0.725)).is_equal_approx(0.5, 0.001)

func test_wet_tint_needs_wetness_and_night_or_storm() -> void:
	assert_that(WetSurface.tint_active(0.0, false, false)).is_false()
	assert_that(WetSurface.tint_active(0.0, true, false)).is_false()
	assert_that(WetSurface.tint_active(0.0, false, true)).is_false()
	assert_that(WetSurface.tint_active(0.5, false, false)).is_false()
	assert_that(WetSurface.tint_active(0.5, true, false)).is_true()
	assert_that(WetSurface.tint_active(0.5, false, true)).is_true()

func test_wet_overlay_alpha_scales_with_intensity() -> void:
	var overlay := WetSurface.build_overlay()
	_managed.append(overlay)
	assert_that(overlay.visible).is_false()
	WetSurface.apply_intensity(overlay, 0.5, true, false)
	assert_that(overlay.visible).is_true()
	assert_float(overlay.color.a).is_equal_approx(0.5 * WetSurface.OVERLAY_ALPHA_MAX, 0.001)
	WetSurface.apply_intensity(overlay, 1.0, false, true)
	assert_float(overlay.color.a).is_equal_approx(WetSurface.OVERLAY_ALPHA_MAX, 0.001)

func test_wet_overlay_hides_when_rule_gates() -> void:
	var overlay := WetSurface.build_overlay()
	_managed.append(overlay)
	WetSurface.apply_intensity(overlay, 0.5, false, false)
	assert_that(overlay.visible).is_false()
	assert_float(overlay.color.a).is_equal(0.0)
	WetSurface.apply_intensity(overlay, 0.0, true, false)
	assert_that(overlay.visible).is_false()

func test_headlights_should_enable_is_night_exact() -> void:
	assert_that(Headlights.should_enable(true)).is_true()
	assert_that(Headlights.should_enable(false)).is_false()

func test_headlights_build_two_low_lights() -> void:
	var root := _new_root()
	var lights := Headlights.new()
	_managed.append(lights)
	root.add_child(lights)
	assert_that(lights.headlight_count()).is_equal(2)
	assert_that(lights.get_child_count()).is_equal(2)

func test_headlights_toggle_exactly_on_is_night() -> void:
	var root := _new_root()
	var lights := Headlights.new()
	_managed.append(lights)
	root.add_child(lights)
	for hour in [0.0, 6.0, 12.0, 18.0, 23.0]:
		WeatherManager.set_time_of_day(hour)
		var expect := WeatherManager.is_night()
		assert_that(Headlights.should_enable(expect)).is_equal(expect)
		for light in lights.get_children():
			assert_that((light as SpotLight3D).visible).is_equal(expect)

func test_headlights_set_night_is_authoritative() -> void:
	var root := _new_root()
	var lights := Headlights.new()
	_managed.append(lights)
	root.add_child(lights)
	lights.set_night(true)
	for light in lights.get_children():
		assert_that((light as SpotLight3D).visible).is_true()
	lights.set_night(false)
	for light in lights.get_children():
		assert_that((light as SpotLight3D).visible).is_false()

func test_weather_manager_is_night_follows_raw_sun_arc() -> void:
	WeatherManager.set_time_of_day(12.0)
	assert_that(WeatherManager.is_night()).is_false()
	WeatherManager.set_time_of_day(0.0)
	assert_that(WeatherManager.is_night()).is_true()

func test_rain_system_headless_culls_particles() -> void:
	var root := _new_root()
	var rain := RainSystem.new()
	_managed.append(rain)
	root.add_child(rain)
	assert_that(rain.particle_count()).is_equal(0)
	assert_that(rain.get_child_count()).is_equal(0)

func test_rain_active_weather() -> void:
	assert_that(RainSystem.rain_active(WeatherManager.Weather.RAIN)).is_true()
	assert_that(RainSystem.rain_active(WeatherManager.Weather.STORM)).is_true()
	assert_that(RainSystem.rain_active(WeatherManager.Weather.CLEAR)).is_false()
	assert_that(RainSystem.rain_active(WeatherManager.Weather.CLOUDY)).is_false()
	assert_that(RainSystem.rain_active(WeatherManager.Weather.FOG)).is_false()
	assert_that(RainSystem.rain_active(WeatherManager.Weather.SNOW)).is_false()

func test_rain_state_machine_tracks_weather_headlessly() -> void:
	var root := _new_root()
	var rain := RainSystem.new()
	_managed.append(rain)
	root.add_child(rain)
	WeatherManager.set_weather(WeatherManager.Weather.CLEAR)
	assert_that(rain.is_raining()).is_false()
	WeatherManager.set_weather(WeatherManager.Weather.RAIN)
	assert_that(rain.is_raining()).is_true()
	WeatherManager.set_weather(WeatherManager.Weather.STORM)
	assert_that(rain.is_raining()).is_true()
	WeatherManager.set_weather(WeatherManager.Weather.SNOW)
	assert_that(rain.is_raining()).is_false()

func test_windshield_active_chase_gate() -> void:
	assert_that(WindshieldFX.active(true, true)).is_true()
	assert_that(WindshieldFX.active(true, false)).is_false()
	assert_that(WindshieldFX.active(false, true)).is_false()
	assert_that(WindshieldFX.active(false, false)).is_false()

func test_windshield_overlay_visible_only_when_active() -> void:
	var overlay := WindshieldFX.build_overlay()
	_managed.append(overlay)
	assert_that(overlay.visible).is_false()
	assert_that(overlay.material).is_not_null()
	WindshieldFX.apply(overlay, true, true)
	assert_that(overlay.visible).is_true()
	WindshieldFX.apply(overlay, true, false)
	assert_that(overlay.visible).is_false()

func test_weather_audio_gain_ladder_monotonic() -> void:
	assert_float(WeatherAudio.gain_for(WeatherManager.Weather.CLEAR)).is_equal(0.0)
	assert_float(WeatherAudio.gain_for(WeatherManager.Weather.CLOUDY)).is_equal(0.0)
	assert_float(WeatherAudio.gain_for(WeatherManager.Weather.STORM)).is_equal(1.0)
	assert_float(WeatherAudio.gain_for(WeatherManager.Weather.STORM)).is_greater_equal(
		WeatherAudio.gain_for(WeatherManager.Weather.RAIN)
	)
	assert_float(WeatherAudio.gain_for(WeatherManager.Weather.RAIN)).is_greater_equal(
		WeatherAudio.gain_for(WeatherManager.Weather.SNOW)
	)
	assert_float(WeatherAudio.gain_for(WeatherManager.Weather.SNOW)).is_greater_equal(
		WeatherAudio.gain_for(WeatherManager.Weather.FOG)
	)
	assert_float(WeatherAudio.gain_for(WeatherManager.Weather.FOG)).is_greater_equal(
		WeatherAudio.gain_for(WeatherManager.Weather.CLEAR)
	)

func test_weather_audio_volume_monotonic_with_intensity() -> void:
	var prev := -100.0
	for value in range(0, 11):
		var intensity := float(value) / 10.0
		var volume := WeatherAudio.volume_for(intensity)
		assert_float(volume).is_greater_equal(prev)
		prev = volume
	assert_float(WeatherAudio.volume_for(0.0)).is_equal(WeatherAudio.VOLUME_MIN_DB)
	assert_float(WeatherAudio.volume_for(1.0)).is_equal(WeatherAudio.VOLUME_MAX_DB)

func test_weather_audio_node_builds_bed_and_sets_volume() -> void:
	var root := _new_root()
	var audio := WeatherAudio.new()
	_managed.append(audio)
	root.add_child(audio)
	assert_that(audio.stream).is_not_null()
	WeatherManager.set_weather(WeatherManager.Weather.CLEAR)
	assert_float(audio.get_intensity()).is_equal(0.0)
	assert_float(audio.volume_db).is_equal(WeatherAudio.VOLUME_MIN_DB)
	WeatherManager.set_weather(WeatherManager.Weather.STORM)
	assert_float(audio.get_intensity()).is_equal(1.0)
	assert_float(audio.volume_db).is_equal(WeatherAudio.VOLUME_MAX_DB)
	WeatherManager.set_weather(WeatherManager.Weather.RAIN)
	assert_float(audio.volume_db).is_equal_approx(
		WeatherAudio.volume_for(WeatherAudio.gain_for(WeatherManager.Weather.RAIN)),
		0.001
	)

func test_weather_audio_node_frees_cleanly() -> void:
	var root := _new_root()
	var audio := WeatherAudio.new()
	root.add_child(audio)
	var child_count := root.get_child_count()
	audio.free()
	assert_that(root.get_child_count()).is_equal(child_count - 1)