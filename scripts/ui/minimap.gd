# scripts/ui/minimap.gd
extends Control

## Circular minimap showing player position and direction.

@export var minimap_radius: float = 100.0
@export var zoom: float = 0.2  # world units to pixel

var _player_car: VehiclePhysics

func _ready() -> void:
	_player_car = VehicleManager.get_player_car()

func _draw() -> void:
	if _player_car == null:
		return

	var center := size / 2.0
	draw_circle(center, minimap_radius, Color(0.0, 0.0, 0.0, 0.3))

	# Player arrow (triangle pointing in facing direction)
	var car_facing: Vector3 = -_player_car.global_basis.z
	var angle := atan2(car_facing.x, car_facing.z)
	var tip := center + Vector2(sin(angle), -cos(angle)) * 10.0
	var left := center + Vector2(sin(angle + TAU / 3), -cos(angle + TAU / 3)) * 6.0
	var right := center + Vector2(sin(angle - TAU / 3), -cos(angle - TAU / 3)) * 6.0
	draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(1, 1, 1))

func _process(_delta: float) -> void:
	_player_car = VehicleManager.get_player_car()
	queue_redraw()
