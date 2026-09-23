extends SceneTree

func _init() -> void:
	var paths := [
		"res://scripts/vehicle/car_config.gd",
		"res://scripts/career/tuning_profile.gd",
		"res://scripts/career/garage.gd",
	]
	for p: String in paths:
		var gd: Variant = ResourceLoader.load(p, "GDScript", ResourceLoader.CACHE_MODE_REUSE)
		if gd is GDScript:
			var err := (gd as GDScript).reload()
			print("RELOAD ", p, " err=", err)
		else:
			print("NOT GDScript: ", p, " -> ", gd)
	quit()