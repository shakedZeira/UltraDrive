extends Node

## Controls the player's car. Attach as child of VehiclePhysics.

const CAR_ORIENT := Transform3D(Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0)), Vector3.ZERO)
const DEFAULT_VISUAL := "res://assets/cars/sports_coupe.glb"

@onready var car: VehiclePhysics = get_parent()

func _ready() -> void:
	VehicleManager.register_player_car(car)
	var active := Garage.new_from_save().get_active_car()
	if active != "":
		var car_path := "res://resources/cars/%s.tres" % active
		if ResourceLoader.exists(car_path):
			car.config = load(car_path) as CarConfig
	_apply_visual()

func _apply_visual() -> void:
	var config := car.config as CarConfig
	var visual_path: String = DEFAULT_VISUAL
	if config != null and not config.visual_path.is_empty():
		visual_path = config.visual_path
	var body := car.get_node_or_null("CarBody") as Node3D
	if body == null:
		return
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var visual := load(visual_path) as PackedScene
	if visual == null:
		return
	var instance: Node3D = visual.instantiate()
	instance.transform = CAR_ORIENT
	body.add_child(instance)
	CarVisuals.apply_paint(instance, CarVisuals.DEFAULT_PAINT)
