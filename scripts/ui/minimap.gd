# scripts/ui/minimap.gd
extends Control

## Circular minimap showing player position and direction, plus nearby roads.
## Roads come from MapRoads.resolve_road_source(); when no road source exists
## (e.g. circuit race scenes) the road layer silently no-ops.

@export var minimap_radius: float = 100.0
@export var zoom: float = 0.2  # world units to pixel

@export var road_color := Color(0.5, 0.62, 0.85, 0.55)
@export var road_width := 2.0
@export var ring_color := Color(0.3, 0.5, 0.85, 0.45)

var _player_car: VehiclePhysics
var _road_source: Node = null
var _road_signature := ""
var _scene_roads: Array = []  # cached chains for the current signature
var _last_redraw_pos := Vector3(INF, INF, INF)
var _last_heading := INF

func _ready() -> void:
	_player_car = VehicleManager.get_player_car()
	_road_source = MapRoads.resolve_road_source(self) as Node
	_road_signature = MapRoads.signature(_road_source)
	_scene_roads = MapRoads.get_roads(_road_source)

func _draw() -> void:
	if _player_car == null:
		return

	var center := size / 2.0
	draw_circle(center, minimap_radius, Color(0.0, 0.0, 0.0, 0.3))
	_draw_roads(center)

	# Player arrow (triangle pointing in facing direction)
	var car_facing: Vector3 = -_player_car.global_basis.z
	var angle := atan2(car_facing.x, car_facing.z)
	var tip := center + Vector2(sin(angle), -cos(angle)) * 10.0
	var left := center + Vector2(sin(angle + TAU / 3), -cos(angle + TAU / 3)) * 6.0
	var right := center + Vector2(sin(angle - TAU / 3), -cos(angle - TAU / 3)) * 6.0
	draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(1, 1, 1))
	draw_arc(center, minimap_radius, 0.0, TAU, 64, ring_color, 1.5)

func _draw_roads(center: Vector2) -> void:
	if _road_source == null:
		return
	var player_pos := _player_car.global_position
	for chain in _scene_roads:
		var local := MapRoads.world_to_local_points(chain, player_pos, center, zoom)
		var clipped := MapRoads.clip_circle(local, center, minimap_radius)
		if clipped.size() >= 2:
			draw_polyline(clipped, road_color, road_width)

func _process(_delta: float) -> void:
	_player_car = VehicleManager.get_player_car()
	if _road_source == null:
		_road_source = MapRoads.resolve_road_source(self) as Node
	var current_signature := MapRoads.signature(_road_source)
	if current_signature != _road_signature:
		_road_signature = current_signature
		_scene_roads = MapRoads.get_roads(_road_source)
	if _player_car == null:
		_last_redraw_pos = Vector3(INF, INF, INF)
		_last_heading = INF
		queue_redraw()
		return
	var pos := _player_car.global_position
	var car_facing: Vector3 = -_player_car.global_basis.z
	var heading := atan2(car_facing.x, car_facing.z)
	# Redraw only when the player moved enough or turned, so the arrow stays
	# live without rebuilding road polylines every frame.
	if _last_redraw_pos.distance_to(pos) > 4.0 or absf(heading - _last_heading) > 0.05:
		_last_redraw_pos = pos
		_last_heading = heading
		queue_redraw()