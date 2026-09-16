# scripts/ui/world_map.gd
class_name WorldMap
extends Control

## Full-screen pause-map: north-up, fits all roads (plus POIs and the player)
## into its rect with a uniform scale. Content is cached per rebuild; the map
## only passes through _draw again when it is marked dirty (opened, resized).

const ROAD_COLOR := Color(0.5, 0.62, 0.85, 0.6)
const ROAD_WIDTH := 2.5
const PLAYER_COLOR := Color(0.98, 0.98, 1.0, 1.0)
const PLAYER_RADIUS := 6.0
const POI_COLOR := Color(0.75, 0.85, 1.0, 0.85)
const POI_RADIUS := 4.0
const BACKDROP_COLOR := Color(0.05, 0.07, 0.13, 0.94)
const BORDER_COLOR := Color(0.3, 0.5, 0.85, 0.6)
const INSET := 32.0

var _dirty := true
var _fit := {}
var _paths: Array = []
var _poi_screens: Array = []
var _player_screen := Vector2.ZERO
var _has_player := false

func refresh() -> void:
	_dirty = true
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_dirty = true

func _draw() -> void:
	if _dirty:
		_rebuild()
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP_COLOR)
	if _fit.is_empty():
		return
	for path in _paths:
		if path.size() >= 2:
			draw_polyline(path, ROAD_COLOR, ROAD_WIDTH)
	for poi in _poi_screens:
		var p: Vector2 = poi
		draw_circle(p, POI_RADIUS, POI_COLOR)
	if _has_player:
		draw_circle(_player_screen, PLAYER_RADIUS, PLAYER_COLOR)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 2.0)

func _rebuild() -> void:
	_dirty = false
	var source := MapRoads.resolve_road_source(self)
	var with_world := source != null
	var roads := MapRoads.get_roads(source)
	var car := VehicleManager.get_player_car()
	_has_player = car != null
	var player_pos := Vector3.ZERO
	if car != null:
		player_pos = car.global_position

	var content: Array = []
	var raw_pois: Array = []
	for chain in roads:
		for p in chain:
			content.append(p)
	if _has_player:
		content.append(player_pos)
	# POIs only make sense in the open world (i.e. when a road source exists).
	if with_world:
		for poi_id in POIRegistry.get_poi_ids():
			var poi := POIRegistry.get_poi(poi_id)
			var pos: Vector3 = poi.get("position", Vector3.ZERO)
			content.append(pos)
			raw_pois.append(pos)

	_fit = MapRoads.compute_fit(content, player_pos, size, INSET)
	_paths = []
	for chain in roads:
		var pts := PackedVector2Array()
		for p in chain:
			pts.append(MapRoads.world_to_screen(p, _fit))
		if pts.size() >= 2:
			_paths.append(pts)
	_poi_screens = []
	for p in raw_pois:
		_poi_screens.append(MapRoads.world_to_screen(p, _fit))
	_player_screen = MapRoads.world_to_screen(player_pos, _fit) if _has_player else Vector2.ZERO