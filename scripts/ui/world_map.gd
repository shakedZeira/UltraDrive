# scripts/ui/world_map.gd
class_name WorldMap
extends Control

## Full-screen pause-map: north-up, fits all roads (plus POIs and the player)
## into its rect with a uniform scale. Content is cached per rebuild; the map
## only passes through _draw again when it is marked dirty (opened, resized).
## With a WorldDiscovery source, roads split into visited (white) and unvisited
## (grey) segments; without one every road draws in the visited color. Left-click
## a revealed road to fast-travel to it.

const ROAD_COLOR := Color(0.5, 0.62, 0.85, 0.6)
const UNVISITED_ROAD_COLOR := Color(0.42, 0.44, 0.48, 0.6)
const ROUTE_COLOR := Color(1.0, 0.58, 0.12, 0.95)
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
var _paths: Array = []  # visited segments (each a 2-point PackedVector2Array)
var _grey_paths: Array = []  # unvisited segments
var _route_path := PackedVector2Array()
var _poi_screens: Array = []
var _player_screen := Vector2.ZERO
var _has_player := false
var _discovery_source: WorldDiscovery = null

func refresh() -> void:
	_dirty = true
	queue_redraw()

## Sets the GPS route destination (stored in MapRoads static state shared with
## the minimap) and rebuilds the map.
func set_route_destination(world_pos: Vector3) -> void:
	MapRoads.set_route(world_pos)
	refresh()

func clear_route() -> void:
	MapRoads.clear_route()
	refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_dirty = true

func _draw() -> void:
	if _dirty:
		_rebuild()
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP_COLOR)
	if _fit.is_empty():
		return
	for path in _grey_paths:
		if path.size() >= 2:
			draw_polyline(path, UNVISITED_ROAD_COLOR, ROAD_WIDTH)
	for path in _paths:
		if path.size() >= 2:
			draw_polyline(path, ROAD_COLOR, ROAD_WIDTH)
	if _route_path.size() >= 2:
		draw_polyline(_route_path, ROUTE_COLOR, ROAD_WIDTH + 2.0)
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
	_discovery_source = MapRoads.resolve_discovery_source(self) as WorldDiscovery

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
	_grey_paths = []
	for road_id in roads.size():
		var chain: Array = roads[road_id]
		var screens := PackedVector2Array()
		for p in chain:
			screens.append(MapRoads.world_to_screen(p, _fit))
		var mask: Array[bool] = []
		if _discovery_source != null:
			mask = _discovery_source.segment_visited_mask(road_id)
		if mask.is_empty() or (mask.size() != chain.size() - 1 and mask.size() != chain.size()):
			# No usable discovery data: draw the whole chain as one visited path.
			if screens.size() >= 2:
				_paths.append(screens)
			continue
		for seg in mask.size():
			var seg_next := seg + 1
			if seg_next >= screens.size():
				seg_next = 0  # closing segment on a closed chain
			var segment := PackedVector2Array([screens[seg], screens[seg_next]])
			if mask[seg]:
				_paths.append(segment)
			else:
				_grey_paths.append(segment)
	_route_path = PackedVector2Array()
	if MapRoads.has_route and with_world:
		var route := MapRoads.route_polyline(source, player_pos, MapRoads.route_target)
		var route_pts := PackedVector2Array()
		for p in route:
			route_pts.append(MapRoads.world_to_screen(p, _fit))
		if route_pts.size() >= 2:
			_route_path = route_pts
	_poi_screens = []
	for p in raw_pois:
		_poi_screens.append(MapRoads.world_to_screen(p, _fit))
	_player_screen = MapRoads.world_to_screen(player_pos, _fit) if _has_player else Vector2.ZERO

## Left-click on the visible pause map fast-travels to the clicked road point
## when the WorldDriver accepts it (the point must be on a revealed road).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_map_click(event as InputEventMouseButton)

func _handle_map_click(click: InputEventMouseButton) -> void:
	if not is_visible_in_tree() or _fit.is_empty():
		return
	var rect := get_global_rect()
	if not rect.has_point(click.position):
		return
	var world := MapRoads.screen_to_world(click.position - rect.position, _fit)
	_try_fast_travel(world)

func _try_fast_travel(world_pos: Vector3) -> void:
	var driver := _resolve_driver()
	if driver == null or not driver.fast_travel_to(world_pos):
		return
	# Successful teleport: close the pause UI and get back to driving.
	var overlay := get_parent()
	var menu := overlay.get_parent() if overlay != null else null
	if menu is CanvasItem:
		(menu as CanvasItem).visible = false
	if GameState != null:
		GameState.resume_game()

func _resolve_driver() -> WorldDriver:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group(WorldDriver.DRIVER_GROUP) as WorldDriver