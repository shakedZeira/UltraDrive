# scripts/ui/garage_ui.gd
extends Control

## Garage UI: view cars, select active car, see stats.

@onready var car_list: ItemList = %CarList
@onready var car_name_label: Label = %CarNameLabel
@onready var stats_label: Label = %StatsLabel
@onready var select_button: Button = %SelectButton

var _garage: Garage
var _selected_car: String = ""

func _ready() -> void:
	_garage = Garage.new_from_save()
	_load_car_list()
	select_button.pressed.connect(_on_select_pressed)
	car_list.item_selected.connect(_on_car_selected)

func _load_car_list() -> void:
	car_list.clear()
	for car_id in _garage.get_owned_cars():
		car_list.add_item(car_id)
	if car_list.item_count > 0:
		car_list.select(0)
		_on_car_selected(0)
	else:
		car_name_label.text = "No cars owned"
		stats_label.text = ""

func _on_car_selected(index: int) -> void:
	_selected_car = car_list.get_item_text(index)
	var car_path := "res://resources/cars/%s.tres" % _selected_car
	var config := load(car_path) as CarConfig
	if config:
		car_name_label.text = config.car_name
		stats_label.text = "Mass: %d kg\nTorque: %d Nm\nClass: %s" % [config.mass_kg, config.max_torque, config.car_class]

func _on_select_pressed() -> void:
	if _selected_car != "":
		_garage.set_active_car(_selected_car)

func _on_back_pressed() -> void:
	SceneTransition.flash_to_scene("res://scenes/ui/main_menu.tscn")
