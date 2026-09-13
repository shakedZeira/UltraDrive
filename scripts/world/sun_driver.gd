# scripts/world/sun_driver.gd
extends DirectionalLight3D

## Q6 companion sun driver for gameplay scenes WITHOUT a WorldDriver
## (mountain_pass, test_track). Portals WeatherManager's computed sun position
## into this sun's transform on ready and on every time-of-day change. The
## transform math lives as pure statics on WorldDriver so it stays unit-testable.

func _ready() -> void:
	if WeatherManager.time_of_day_changed.is_connected(_on_time_of_day_changed) == false:
		WeatherManager.time_of_day_changed.connect(_on_time_of_day_changed)
	WorldDriver.apply_sun_transform(self, WeatherManager.get_time_of_day(), true)

func _on_time_of_day_changed(hour: float) -> void:
	WorldDriver.apply_sun_transform(self, hour, false)