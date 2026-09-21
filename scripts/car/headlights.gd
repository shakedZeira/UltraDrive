class_name Headlights
extends Node

## Weather VFX (S12): headlight switch-over on the player car (and, via the
## shared player scene, traffic shares the same node). A small SpotLight pair
## points down the nose (-Z); each light toggles EXACTLY on
## WeatherManager.is_night() (sun_direction below the horizon). Lights are
## cheap enough to stay even headless; only particle systems are culled.

const LIGHT_ENERGY := 3.0
const LIGHT_RANGE := 60.0
const SPOT_ANGLE_DEG := 35.0
const LIGHT_NAME := "Headlight"

const POSITIONS: Array[Vector3] = [
	Vector3(-0.65, 0.7, -1.35),
	Vector3(0.65, 0.7, -1.35),
]

var _lights: Array[SpotLight3D] = []

## Pure toggle rule: headlights on exactly when it is night.
static func should_enable(is_night: bool) -> bool:
	return is_night

func _ready() -> void:
	_build_lights()
	if not WeatherManager.time_of_day_changed.is_connected(_on_time_of_day_changed):
		WeatherManager.time_of_day_changed.connect(_on_time_of_day_changed)
	set_night(WeatherManager.is_night())

func _exit_tree() -> void:
	if WeatherManager.time_of_day_changed.is_connected(_on_time_of_day_changed):
		WeatherManager.time_of_day_changed.disconnect(_on_time_of_day_changed)

## Public toggle (tests + traffic sync drive this directly). Applies
## should_enable to every light, so the flag is the single authority.
func set_night(night: bool) -> void:
	var enable := should_enable(night)
	for light in _lights:
		(light as SpotLight3D).visible = enable

func headlight_count() -> int:
	return _lights.size()

func _on_time_of_day_changed(_hour: float) -> void:
	set_night(WeatherManager.is_night())

func _build_lights() -> void:
	_lights.clear()
	for index in POSITIONS.size():
		var light := SpotLight3D.new()
		light.name = LIGHT_NAME if index == 0 else "%s%d" % [LIGHT_NAME, index + 1]
		light.position = POSITIONS[index]
		light.light_energy = LIGHT_ENERGY
		light.light_color = Color(1.0, 0.95, 0.86, 1.0)
		light.spot_range = LIGHT_RANGE
		light.spot_angle = SPOT_ANGLE_DEG
		light.visible = false
		add_child(light)
		_lights.append(light)