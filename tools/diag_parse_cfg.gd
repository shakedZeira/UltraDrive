extends SceneTree

func _init() -> void:
	var res: Resource = load("res://scripts/vehicle/car_config.gd")
	print("car_config.gd load -> ", res)
	if res is GDScript:
		var err := (res as GDScript).reload()
		print("car_config.gd reload err=", err)
	var cfg: Resource = load("res://resources/cars/starter_car.tres")
	print("starter_car tres -> ", cfg)
	if cfg is Resource:
		var cfg_err := ResourceLoader.load("res://resources/cars/starter_car.tres", "Resource", ResourceLoader.CACHE_MODE_REUSE)
		print("re-cache starter -> ", cfg_err)
	quit()

func _process(_delta: float) -> bool:
	return false