# autoload/day_night_driver.gd
extends Node

## P4 day/night clock driver. Tick is a strict no-op unless an `open_world`
## group member exists AND GameState.current_mode == FREE_ROAM, so every
## non-open-world session (menus and the headless GDUnit suite) keeps
## WeatherManager frozen and deterministic. All clock/season/weather state
## lives in WeatherManager; this node just nudges it. An optional regional
## sampler registered on WeatherManager is re-sampled each tick from the
## open-world player position, and the plain random weather roll is skipped
## while a regional sampler is active so the two never fight.

const WORLD_GROUP := "open_world"
const DAY_LENGTH_SECONDS := 2400.0  # full in-game day, ~40 real minutes
const HOURS_PER_SECOND := 24.0 / DAY_LENGTH_SECONDS
const MIN_WEATHER_INTERVAL_SECONDS := 30.0
const MAX_WEATHER_INTERVAL_SECONDS := 60.0

const WEATHER_WEIGHTS: Dictionary = {
    WeatherManager.Weather.CLEAR: 0.40,
    WeatherManager.Weather.CLOUDY: 0.25,
    WeatherManager.Weather.RAIN: 0.15,
    WeatherManager.Weather.STORM: 0.10,
    WeatherManager.Weather.FOG: 0.06,
    WeatherManager.Weather.SNOW: 0.04,
}

var _weather_timer: float = MIN_WEATHER_INTERVAL_SECONDS
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
    _rng.randomize()

func _process(delta: float) -> void:
    if _world_is_active():
        _tick(delta)

func _world_is_active() -> bool:
    if GameState.current_mode != GameState.GameMode.FREE_ROAM:
        return false
    return get_tree().get_first_node_in_group(WORLD_GROUP) != null

func _tick(delta: float) -> void:
    WeatherManager.set_season(GameState.season)
    WeatherManager.advance_time(delta * HOURS_PER_SECOND)
    _refresh_regional_weather()
    _weather_timer -= delta
    if _weather_timer <= 0.0:
        _weather_timer = _rng.randf_range(MIN_WEATHER_INTERVAL_SECONDS, MAX_WEATHER_INTERVAL_SECONDS)
        if not WeatherManager.has_regional_sampler():
            _roll_weather()

func _refresh_regional_weather() -> void:
    if not WeatherManager.has_regional_sampler():
        return
    WeatherManager.set_sample_position(_player_pos_xz())
    WeatherManager.refresh_regional_weather()

func _player_pos_xz() -> Vector2:
    var root := get_tree().get_first_node_in_group(WORLD_GROUP) as Node3D
    if root == null:
        return Vector2.ZERO
    var player := root.get_node_or_null("%PlayerCar") as Node3D
    if player == null:
        return Vector2.ZERO
    return Vector2(player.global_position.x, player.global_position.z)

func _roll_weather() -> void:
    for attempt in 8:
        var pick := _weighted_pick()
        if pick != WeatherManager.current_weather:
            WeatherManager.set_weather(pick)
            return

func _weighted_pick() -> WeatherManager.Weather:
    var roll := _rng.randf()
    var acc := 0.0
    for weather in WEATHER_WEIGHTS:
        var wk: int = weather
        var weight: float = WEATHER_WEIGHTS[weather]
        acc += weight
        if roll < acc:
            return wk as WeatherManager.Weather
    return WeatherManager.Weather.CLEAR