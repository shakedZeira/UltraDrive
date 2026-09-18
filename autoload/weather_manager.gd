# autoload/weather_manager.gd
extends Node

## Manages weather state, day/night cycle, and road conditions.

enum Weather { CLEAR, CLOUDY, RAIN, STORM, FOG, SNOW }

signal weather_changed(weather: Weather)
signal time_of_day_changed(hour: float)

var current_weather: Weather = Weather.CLEAR
var time_of_day: float = 12.0  # 0-24 hours
# Current season (RegionalClimate.Season id; SUMMER default for the existing
# fixed-weather corpus and any save without a season key).
var season: int = 2

var _regional_sampler: Callable = Callable()
var _sample_position := Vector2.ZERO

# Road grip multiplier per weather type
const ROAD_GRIP: Dictionary = {
    Weather.CLEAR: 1.0,
    Weather.CLOUDY: 0.98,
    Weather.RAIN: 0.8,
    Weather.STORM: 0.6,
    Weather.FOG: 0.95,
    Weather.SNOW: 0.45,
}

func set_weather(weather: Weather) -> void:
    if current_weather != weather:
        current_weather = weather
        weather_changed.emit(weather)

func get_time_of_day() -> float:
    return time_of_day

func get_road_grip_factor() -> float:
    return ROAD_GRIP.get(current_weather, 1.0)

func set_time_of_day(hour: float) -> void:
    time_of_day = fposmod(hour, 24.0)
    time_of_day_changed.emit(time_of_day)

func advance_time(delta_hours: float) -> void:
    set_time_of_day(time_of_day + delta_hours)

func set_season(value: int) -> void:
    season = value

func get_season() -> int:
    return season

## Registers a regional weather sampler. When set, refresh_regional_weather()
## replaces the global weather roll via the sampler Callable (see
## DayNightDriver._tick); the plain random roll is skipped while it is active.
func register_regional_sampler(sampler: Callable) -> void:
    _regional_sampler = sampler

func clear_regional_sampler() -> void:
    _regional_sampler = Callable()

func has_regional_sampler() -> bool:
    return _regional_sampler.is_valid()

func set_sample_position(pos: Vector2) -> void:
    _sample_position = pos

func get_sample_position() -> Vector2:
    return _sample_position

## Samples regional weather at the current sample position (world XZ), then
## applies the sampled weather id. Sampler contract: Callable(pos: Vector2,
## time_of_day: float, season: int) -> Dictionary with an int "weather" key
## (see RegionalClimate.sample).
func refresh_regional_weather() -> void:
    if not _regional_sampler.is_valid():
        return
    var result: Variant = _regional_sampler.call(_sample_position, time_of_day, season)
    if not (result is Dictionary):
        return
    var data: Dictionary = result
    if data.has("weather"):
        var weather_value: Variant = data["weather"]
        if weather_value is int:
            set_weather(weather_value as Weather)

func get_computed_sun_position() -> Vector3:
    ## Returns sun direction based on time of day.
    var angle := deg_to_rad(time_of_day / 24.0 * 360.0 - 90.0)
    return Vector3(cos(angle), sin(angle), 0.3).normalized()
