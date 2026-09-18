# tests/suites/test_regional_climate.gd
extends GdUnitTestSuite

## P4 regional weather & time-of-day gate: day/night driver clock mechanics,
## RegionalClimate sampler determinism and season/band mechanics, WeatherManager
## regional-sampler API integration and RoadNetwork seasonal tier-closure gate.

const SPAWN_POS := Vector2(128.0, 128.0)
const FARMLAND_POS := Vector2(2048.0, 400.0)
const COAST_POS := Vector2(8200.0, -1800.0)
const LOWLAND_POS := Vector2(4600.0, 4700.0)
const HIGHLAND_POS := Vector2(5000.0, 5600.0)
const ALPINE_POS := Vector2(7800.0, 6400.0)

var _managed_nodes: Array[Node] = []
var _signal_count := 0
var _prev_weather: WeatherManager.Weather = WeatherManager.Weather.CLEAR
var _prev_tod: float = 0.0
var _prev_season: int = 2
var _prev_mode: GameState.GameMode = GameState.GameMode.MAIN_MENU

func _on_tod(_hour: float) -> void:
	_signal_count += 1

func before_test() -> void:
	_managed_nodes.clear()
	_signal_count = 0
	_prev_weather = WeatherManager.current_weather
	_prev_tod = WeatherManager.time_of_day
	_prev_season = WeatherManager.season
	_prev_mode = GameState.current_mode

func after_test() -> void:
	WeatherManager.set_weather(_prev_weather)
	WeatherManager.set_time_of_day(_prev_tod)
	WeatherManager.season = _prev_season
	WeatherManager.clear_regional_sampler()
	GameState.current_mode = _prev_mode
	for node in _managed_nodes:
		if is_instance_valid(node):
			node.free()
	_managed_nodes.clear()

func _track(node: Node) -> void:
	_managed_nodes.append(node)

func _new_driver():
	var driver = preload("res://autoload/day_night_driver.gd").new()
	_track(driver)
	add_child(driver)
	return driver

func test_driver_tick_advances_clock_by_rate_and_emits() -> void:
	var driver = _new_driver()
	WeatherManager.set_time_of_day(12.0)
	WeatherManager.time_of_day_changed.connect(_on_tod)
	driver._tick(60.0)
	WeatherManager.time_of_day_changed.disconnect(_on_tod)
	assert_int(_signal_count).is_equal(1)
	var expected := fposmod(12.0 + 60.0 * DayNightDriver.HOURS_PER_SECOND, 24.0)
	assert_float(WeatherManager.time_of_day).is_equal_approx(expected, 0.01)

func test_driver_tick_wraps_clock() -> void:
	var driver = _new_driver()
	WeatherManager.set_time_of_day(23.95)
	driver._tick(60.0)
	var expected := fposmod(23.95 + 60.0 * DayNightDriver.HOURS_PER_SECOND, 24.0)
	assert_float(WeatherManager.time_of_day).is_equal_approx(expected, 0.01)
	assert_that(WeatherManager.time_of_day).is_less(24.0)

func test_driver_process_noop_without_world_group() -> void:
	var driver = preload("res://autoload/day_night_driver.gd").new()
	_track(driver)
	add_child(driver)
	var before := WeatherManager.time_of_day
	driver._process(60.0)
	assert_float(WeatherManager.time_of_day).is_equal_approx(before, 0.001)
	GameState.current_mode = GameState.GameMode.FREE_ROAM
	driver._process(60.0)
	assert_float(WeatherManager.time_of_day).is_equal_approx(before, 0.001)

func test_driver_weighted_pick_bias_clears_gt_storms() -> void:
	var driver = preload("res://autoload/day_night_driver.gd").new()
	_track(driver)
	driver._rng.seed = 99
	var counts := {}
	for key in DayNightDriver.WEATHER_WEIGHTS:
		counts[int(key)] = 0
	for _i in 2000:
		var pick: int = driver._weighted_pick()
		counts[pick] = counts[pick] + 1
	assert_int(counts[WeatherManager.Weather.CLEAR]).is_greater(counts[WeatherManager.Weather.STORM])

func test_season_for_week_rotates_13_week_seasons() -> void:
	assert_int(RegionalClimate.season_for_week(0)).is_equal(RegionalClimate.Season.WINTER)
	assert_int(RegionalClimate.season_for_week(12)).is_equal(RegionalClimate.Season.WINTER)
	assert_int(RegionalClimate.season_for_week(13)).is_equal(RegionalClimate.Season.SPRING)
	assert_int(RegionalClimate.season_for_week(25)).is_equal(RegionalClimate.Season.SPRING)
	assert_int(RegionalClimate.season_for_week(26)).is_equal(RegionalClimate.Season.SUMMER)
	assert_int(RegionalClimate.season_for_week(38)).is_equal(RegionalClimate.Season.SUMMER)
	assert_int(RegionalClimate.season_for_week(39)).is_equal(RegionalClimate.Season.FALL)
	assert_int(RegionalClimate.season_for_week(51)).is_equal(RegionalClimate.Season.FALL)
	assert_int(RegionalClimate.season_for_week(52)).is_equal(RegionalClimate.Season.WINTER)
	assert_int(RegionalClimate.season_for_week(-1)).is_equal(RegionalClimate.Season.FALL)

func test_region_band_matches_terrain_baker_for_anchor_positions() -> void:
	assert_int(RegionalClimate.region_band(SPAWN_POS)).is_equal(TerrainBaker.BAND_PLAINS)
	assert_int(RegionalClimate.region_band(FARMLAND_POS)).is_equal(TerrainBaker.BAND_PLAINS)
	assert_int(RegionalClimate.region_band(COAST_POS)).is_equal(TerrainBaker.BAND_PLAINS)
	assert_int(RegionalClimate.region_band(LOWLAND_POS)).is_equal(TerrainBaker.BAND_LOWLAND)
	assert_int(RegionalClimate.region_band(HIGHLAND_POS)).is_equal(TerrainBaker.BAND_HIGHLAND)
	assert_int(RegionalClimate.region_band(ALPINE_POS)).is_equal(TerrainBaker.BAND_ALPINE)

func test_sample_returns_required_keys_and_determinism() -> void:
	var rc := RegionalClimate.new()
	var a := rc.sample(SPAWN_POS, 12.5, RegionalClimate.Season.SUMMER)
	var b := rc.sample(SPAWN_POS, 12.5, RegionalClimate.Season.SUMMER)
	assert_that(a).is_equal(b)
	assert_dict(a).contains_keys("weather", "band", "snowline", "grip_mod", "pass_locked")
	assert_int(a["band"]).is_equal(RegionalClimate.region_band(SPAWN_POS))
	assert_float(a["snowline"]).is_equal_approx(RegionalClimate.SNOWLINE[RegionalClimate.Season.SUMMER], 0.001)

func test_plains_profile_dry_only() -> void:
	var rc := RegionalClimate.new()
	var valid := {WeatherManager.Weather.CLEAR: true, WeatherManager.Weather.CLOUDY: true, WeatherManager.Weather.STORM: true}
	for season in 4:
		for hour in 24:
			var result: Dictionary = rc.sample(SPAWN_POS, float(hour), season)
			assert_dict(valid).contains_keys(int(result["weather"]))

func test_coast_profile_no_snow_or_fog() -> void:
	var rc := RegionalClimate.new()
	var valid := {WeatherManager.Weather.CLEAR: true, WeatherManager.Weather.CLOUDY: true, WeatherManager.Weather.RAIN: true, WeatherManager.Weather.STORM: true}
	for season in 4:
		for hour in 24:
			var result: Dictionary = rc.sample(COAST_POS, float(hour), season)
			assert_dict(valid).contains_keys(int(result["weather"]))

func test_lowland_profile_set() -> void:
	var rc := RegionalClimate.new()
	var valid := {WeatherManager.Weather.FOG: true, WeatherManager.Weather.CLOUDY: true, WeatherManager.Weather.RAIN: true, WeatherManager.Weather.CLEAR: true}
	for season in 4:
		for hour in 24:
			var result: Dictionary = rc.sample(LOWLAND_POS, float(hour), season)
			assert_dict(valid).contains_keys(int(result["weather"]))

func test_highland_winter_can_snow_and_allows_correct_set() -> void:
	var rc := RegionalClimate.new()
	var valid := {WeatherManager.Weather.SNOW: true, WeatherManager.Weather.STORM: true, WeatherManager.Weather.CLOUDY: true}
	var saw_snow := false
	for hour in 24:
		var result: Dictionary = rc.sample(HIGHLAND_POS, float(hour), RegionalClimate.Season.WINTER)
		assert_dict(valid).contains_keys(int(result["weather"]))
		if int(result["weather"]) == WeatherManager.Weather.SNOW:
			saw_snow = true
	assert_bool(saw_snow).is_true()

func test_alpine_always_snow_and_grip_matches_season() -> void:
	var rc := RegionalClimate.new()
	for season in 4:
		for hour in 24:
			var result: Dictionary = rc.sample(ALPINE_POS, float(hour), season)
			assert_int(result["weather"]).is_equal(WeatherManager.Weather.SNOW)
			assert_float(result["grip_mod"]).is_equal_approx(RegionalClimate.ALPINE_GRIP[season], 0.001)
			assert_bool(result["pass_locked"]).is_equal(season == RegionalClimate.Season.WINTER)

func test_pass_locked_toggle_by_season_and_band() -> void:
	var rc := RegionalClimate.new()
	var highland_winter: Dictionary = rc.sample(HIGHLAND_POS, 12.0, RegionalClimate.Season.WINTER)
	assert_bool(highland_winter["pass_locked"]).is_true()
	var highland_summer: Dictionary = rc.sample(HIGHLAND_POS, 12.0, RegionalClimate.Season.SUMMER)
	assert_bool(highland_summer["pass_locked"]).is_false()
	var plains_winter: Dictionary = rc.sample(SPAWN_POS, 12.0, RegionalClimate.Season.WINTER)
	assert_bool(plains_winter["pass_locked"]).is_false()
	var alpine_winter: Dictionary = rc.sample(ALPINE_POS, 12.0, RegionalClimate.Season.WINTER)
	assert_bool(alpine_winter["pass_locked"]).is_true()

func test_snowline_matches_seasonal_constants() -> void:
	var rc := RegionalClimate.new()
	assert_float(rc.sample(SPAWN_POS, 0.0, RegionalClimate.Season.WINTER)["snowline"]).is_equal_approx(150.0, 0.001)
	assert_float(rc.sample(SPAWN_POS, 0.0, RegionalClimate.Season.SPRING)["snowline"]).is_equal_approx(300.0, 0.001)
	assert_float(rc.sample(SPAWN_POS, 0.0, RegionalClimate.Season.SUMMER)["snowline"]).is_equal_approx(500.0, 0.001)
	assert_float(rc.sample(SPAWN_POS, 0.0, RegionalClimate.Season.FALL)["snowline"]).is_equal_approx(250.0, 0.001)

func test_route_gate_blocks_closed_tier() -> void:
	var network := RoadNetwork.new()
	add_child(network)
	_track(network)
	var chain_arterial_0: Array[Vector3] = [Vector3(0, 0, 0), Vector3(10, 0, 0)]
	var chain_touge: Array[Vector3] = [Vector3(10, 0, 0), Vector3(26, 0, 0)]
	var chain_arterial_1: Array[Vector3] = [Vector3(26, 0, 0), Vector3(36, 0, 0)]
	network.add_road_def(RoadDef.make(RoadDef.Tier.ARTERIAL, chain_arterial_0))
	network.add_road_def(RoadDef.make(RoadDef.Tier.TOUGE, chain_touge))
	network.add_road_def(RoadDef.make(RoadDef.Tier.ARTERIAL, chain_arterial_1))
	assert_that(network.route(0, 2)).is_equal(PackedInt32Array([0, 1, 2]))
	assert_that(network.neighbor_roads(1)).is_equal(PackedInt32Array([0, 2]))
	network.set_closed_tiers([RoadDef.Tier.TOUGE])
	assert_that(network.route(0, 2)).is_empty()
	assert_that(network.neighbor_roads(1)).is_empty()
	network.clear_seasonal_closures()
	assert_that(network.route(0, 2)).is_equal(PackedInt32Array([0, 1, 2]))
	assert_that(network.neighbor_roads(1)).is_equal(PackedInt32Array([0, 2]))

func test_weather_manager_regional_sampler_drive() -> void:
	var rc := RegionalClimate.new()
	WeatherManager.register_regional_sampler(rc.sample)
	WeatherManager.set_sample_position(ALPINE_POS)
	WeatherManager.set_season(RegionalClimate.Season.WINTER)
	WeatherManager.refresh_regional_weather()
	assert_int(WeatherManager.current_weather).is_equal(WeatherManager.Weather.SNOW)
	WeatherManager.set_sample_position(SPAWN_POS)
	WeatherManager.set_season(RegionalClimate.Season.SUMMER)
	WeatherManager.refresh_regional_weather()
	assert_int(WeatherManager.current_weather).is_not_equal(WeatherManager.Weather.SNOW)
	WeatherManager.clear_regional_sampler()
	assert_bool(WeatherManager.has_regional_sampler()).is_false()
