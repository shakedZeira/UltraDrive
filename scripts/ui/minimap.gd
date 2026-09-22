# scripts/ui/minimap.gd
extends Control

## Circular minimap showing player position and direction, plus nearby roads.
## Roads come from MapRoads.resolve_road_source(); when no road source exists
## (e.g. circuit race scenes) the road layer silently no-ops. Roads branch into
## visited (white/orange) vs unvisited (grey) segments when a WorldDiscovery
## source is present; without one every road is drawn in the visited color.

@export var minimap_radius: float = 100.0
@export var zoom: float = 0.2  # world units to pixel

@export var road_color := Color(0.5, 0.62, 0.85, 0.55)
@export var unvisited_road_color := Color(0.45, 0.47, 0.52, 0.4)
@export var route_color := Color(1.0, 0.58, 0.12, 0.9)
@export var road_width := 2.0
@export var ring_color := Color(0.3, 0.5, 0.85, 0.45)

## Shared player-marker accents (single source of truth in MapRoads, so the
## minimap and the pause map stay in lock-step).
const MARKER_CORE := MapRoads.MARKER_CORE
const MARKER_ACCENT := MapRoads.MARKER_ACCENT
const MARKER_OUTLINE := MapRoads.MARKER_OUTLINE
const MARKER_SIZE := MapRoads.MARKER_SIZE

const _CULL_OVERLAP := 1.1
const _ROUTE_CACHE_CELL := 25.0

var _player_car: VehiclePhysics
var _road_source: Node = null
var _road_signature := ""
var _scene_roads: Array = []  # cached chains for the current signature
var _discovery_source: WorldDiscovery = null
var _last_redraw_pos := Vector3(INF, INF, INF)
var _last_heading := INF
var _marker_angle := -PI / 2.0
var _pulse_time := 0.0
var _last_pulse_tick := -1
var _route_cache_key := ""
var _route_cache: Array[Vector3] = []

func _ready() -> void:
	_player_car = VehicleManager.get_player_car()
	_road_source = MapRoads.resolve_road_source(self) as Node
	_road_signature = MapRoads.signature(_road_source)
	_scene_roads = MapRoads.get_roads(_road_source)
	_discovery_source = MapRoads.resolve_discovery_source(self) as WorldDiscovery

func _draw() -> void:
	if _player_car == null:
		return

	var center := size / 2.0
	draw_circle(center, minimap_radius, Color(0.0, 0.0, 0.0, 0.3))
	_draw_roads(center)
	_draw_route(center)

	# Player chevron: the same marker the pause map uses, so the player reads as
	# one unmistakable object on the HUD minimap. Pointing the way the car faces.
	MapRoads.draw_player_marker(self, center, _marker_angle, _pulse_time, MARKER_SIZE)
	draw_arc(center, minimap_radius, 0.0, TAU, 64, ring_color, 1.5)

func _draw_roads(center: Vector2) -> void:
	if _road_source == null:
		return
	var player_pos := _player_car.global_position
	var player_xz := Vector2(player_pos.x, player_pos.z)
	var radius_world := minimap_radius / zoom * _CULL_OVERLAP
	var radius_world_sq := radius_world * radius_world
	for road_id in _scene_roads.size():
		var chain: Array = _scene_roads[road_id]
		if _chain_stays_outside(player_xz, chain, radius_world_sq):
			continue
		var mask: Array[bool] = []
		if _discovery_source != null:
			mask = _discovery_source.segment_visited_mask(road_id)
		if mask.is_empty() or (mask.size() != chain.size() - 1 and mask.size() != chain.size()):
			_draw_chain_polyline(player_pos, center, chain)
			continue
		_draw_chain_by_color_runs(player_pos, center, chain, mask, radius_world_sq)

func _chain_stays_outside(player_xz: Vector2, chain: Array, radius_world_sq: float) -> bool:
	for w in chain:
		if _point_inside(player_xz, w, radius_world_sq):
			return false
	return true

func _point_inside(player_xz: Vector2, w: Vector3, radius_world_sq: float) -> bool:
	var dx := w.x - player_xz.x
	var dz := w.z - player_xz.y
	return dx * dx + dz * dz <= radius_world_sq

func _draw_chain_polyline(player_pos: Vector3, center: Vector2, chain: Array) -> void:
	var local := MapRoads.world_to_local_points(chain, player_pos, center, zoom)
	var clipped := MapRoads.clip_circle(local, center, minimap_radius)
	if clipped.size() >= 2:
		draw_polyline(clipped, road_color, road_width)

func _draw_chain_by_color_runs(player_pos: Vector3, center: Vector2, chain: Array, mask: Array[bool], radius_world_sq: float) -> void:
	var player_xz := Vector2(player_pos.x, player_pos.z)
	var run_start := 0
	while run_start < mask.size():
		var visited := mask[run_start]
		var run_end := run_start + 1
		while run_end < mask.size() and mask[run_end] == visited:
			run_end += 1
		_draw_chain_run(player_pos, player_xz, center, chain, run_start, run_end, visited, radius_world_sq)
		run_start = run_end

func _draw_chain_run(player_pos: Vector3, player_xz: Vector2, center: Vector2, chain: Array, from_seg: int, to_seg: int, visited: bool, radius_world_sq: float) -> void:
	var idxs := PackedInt32Array()
	for i in range(from_seg, to_seg):
		idxs.append(i)
	idxs.append(_seg_next(to_seg - 1, chain.size()))
	var first_in := -1
	var last_in := -1
	for i in idxs.size():
		if _point_inside(player_xz, chain[idxs[i]], radius_world_sq):
			if first_in < 0:
				first_in = i
			last_in = i
	if first_in < 0:
		return
	var lo := maxi(first_in - 1, 0)
	var hi := mini(last_in + 1, idxs.size() - 1)
	var sub: Array[Vector3] = []
	for i in range(lo, hi + 1):
		sub.append(chain[idxs[i]])
	var local := MapRoads.world_to_local_points(sub, player_pos, center, zoom)
	var clipped := MapRoads.clip_circle(local, center, minimap_radius)
	if clipped.size() >= 2:
		draw_polyline(clipped, road_color if visited else unvisited_road_color, road_width)

func _seg_next(seg: int, point_count: int) -> int:
	return seg + 1 if seg + 1 < point_count else 0

func _draw_route(center: Vector2) -> void:
	if _road_source == null or _player_car == null:
		return
	if not MapRoads.has_route:
		return
	var route := _cached_route_world()
	if route.size() < 2:
		return
	var local := MapRoads.world_to_local_points(route, _player_car.global_position, center, zoom)
	var clipped := MapRoads.clip_circle(local, center, minimap_radius)
	if clipped.size() >= 2:
		draw_polyline(clipped, route_color, road_width + 1.5)

func _cached_route_world() -> Array[Vector3]:
	var player := _player_car.global_position
	var bucket := Vector2i(roundi(player.x / _ROUTE_CACHE_CELL), roundi(player.z / _ROUTE_CACHE_CELL))
	var key := "%s|%.0f,%.0f|%d,%d" % [_road_signature, MapRoads.route_target.x, MapRoads.route_target.z, bucket.x, bucket.y]
	if key != _route_cache_key:
		_route_cache_key = key
		_route_cache = MapRoads.route_polyline(_road_source, player, MapRoads.route_target)
	return _route_cache

func _process(delta: float) -> void:
	_player_car = VehicleManager.get_player_car()
	if _road_source == null:
		_road_source = MapRoads.resolve_road_source(self) as Node
	if _discovery_source == null and get_tree() != null:
		_discovery_source = MapRoads.resolve_discovery_source(self) as WorldDiscovery
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
	_marker_angle = MapRoads.marker_minimap_angle(car_facing)
	# Redraw only when the player moved enough or turned, or when the halo pulse
	# crossed its redraw cadence, so the marker stays live without rebuilding
	# the road polylines every frame.
	_pulse_time += delta
	var tick := int(_pulse_time / MapRoads.MARKER_PULSE_STEP)
	if _last_redraw_pos.distance_to(pos) > 4.0 or absf(heading - _last_heading) > 0.05 \
			or tick != _last_pulse_tick:
		_last_redraw_pos = pos
		_last_heading = heading
		_last_pulse_tick = tick
		queue_redraw()