extends SceneTree

## Pinpoint the real compile error in car_config.gd by parsing its raw source
## text (no global-class dependency resolution, so the reported line/col is
## the true location instead of a cascade).

func _init() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/vehicle/car_config.gd")
	print("=== car_config.gd bytes=", src.length())
	var s := GDScript.new()
	s.source_code = src
	var err := s.reload()
	print("=== reload err=", err, " (15 = Parse Error)")
	if err:
		var report: Dictionary = s.get_message_logs()  # not valid on GDScript
	quit()

func _process(_delta: float) -> bool:
	quit()
	return true
