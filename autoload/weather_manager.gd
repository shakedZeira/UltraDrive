# autoload/weather_manager.gd
extends Node

## Manages weather state, day/night cycle, and road conditions.

enum Weather { CLEAR, CLOUDY, RAIN, STORM, FOG, SNOW }

signal weather_changed(weather: Weather)
signal time_of_day_changed(hour: float)

var current_weather: Weather = Weather.CLEAR
var time_of_day: float = 12.0  # 0-24 hours

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

func get_computed_sun_position() -> Vector3:
    ## Returns sun direction based on time of day.
    var angle := deg_to_rad(time_of_day / 24.0 * 360.0 - 90.0)
    return Vector3(cos(angle), sin(angle), 0.3).normalized()
