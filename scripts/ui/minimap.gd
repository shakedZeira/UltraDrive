# scripts/ui/minimap.gd
extends Control

## Circular minimap showing player position and direction, plus nearby roads.
## Roads come from MapRoads.resolve_road_source(); when no road source exists
## (e.g. circuit race scenes) the road layer silently no-ops. Roads branch into
## visited (white/orange) vs unvisited (grey) segments when a WorldDiscovery
## source is present; without one every road is drawn in the visited color.
## AAA-16: nearby unclaimed collectibles (bonus boards, speed traps, photo
## spots) draw as small dots over the roads; the layer no-ops with the road
## source, so it never shows on a circuit.

@export var minimap_radius: float = 100.0
@export var zoom: float = 0.2  # world units to pixel

@export var road_color := Color(0.5, 0.62, 0.85, 0.55)
@export var unvisited_road_color := Color(0.45, 0.47, 0.52, 0.4)
@export var route_color := Color(1.0, 0.58, 0.12, 0.9)
@export var road_width := 2.0
@export var ring_color := Color(0.3, 0.5, 0.85, 0.45)

## AAA-16 collectible dots. Per-family colours so a photo spot never reads as a
## speed trap at a glance; the values mirror Collectibles.KIND_DOT_COLOR, the
## shared table the pause map resolves through Collectibles.kind_color(), so the
## two maps can never drift apart. The dot is a filled circle with a dark rim at
## HUD scale, sized and ringed to stay legible on a 200 px disc.
@export var show_collectibles: bool = true
@export var collectible_dots := {
	Collectibles.KIND_BONUS: Color(0.98, 0.82, 0.28),
	Collectibles.KIND_SPEED_TRAP: Color(0.95, 0.42, 0.34),
	Collectibles.KIND_PHOTO: Color(0.55, 0.86, 0.98),
}
@export var collectible_dot_radius := 4.0
@export var collectible_dot_outline := Color(0.05, 0.06, 0.1, 0.9)
## Hollow ring inside the dot: a collectible is a target to drive AT, so at HUD
## scale it must never read as another blob of road.
@export var collectible_dot_ring := Color(1.0, 0.98, 0.96, 0.9)
@export var collectible_dot_ring_width := 1.4

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
## AAA-16 collectible layer. The POI list is resolved once (POIRegistry caches
## its one-shot corridor plan) and the claim state is read from the open-world
## CollectibleField, re-resolved lazily like the discovery source.
var _collectible_dots: Array = []  # each {"id", "kind", "position": Vector3}
var _collectible_source: CollectibleField = null

func _ready() -> void:
	_player_car = VehicleManager.get_player_car()
	_road_source = MapRoads.resolve_road_source(self) as Node
	_road_signature = MapRoads.signature(_road_source)
	_scene_roads = MapRoads.get_roads(_road_source)
	_discovery_source = MapRoads.resolve_discovery_source(self) as WorldDiscovery
	_collect_collectibles()

## Resolves the collectible half of the POI registry into a flat draw list.
## Gated on the road source so circuit scenes pay nothing.
func _collect_collectibles() -> void:
	_collectible_dots = []
	if _road_source == null:
		return
	for poi_id: String in POIRegistry.get_poi_ids():
		if not Collectibles.is_collectible_id(poi_id):
			continue
		var poi := POIRegistry.get_poi(poi_id)
		_collectible_dots.append({
			"id": poi_id,
			"kind": str(poi.get("kind", "")),
			"position": poi.get("position", Vector3.ZERO) as Vector3,
		})

func _draw() -> void:
	if _player_car == null:
		return

	var center := size / 2.0
	draw_circle(center, minimap_radius, Color(0.0, 0.0, 0.0, 0.3))
	_draw_roads(center)
	_draw_route(center)
	_draw_collectibles(center)

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

## AAA-16: unclaimed collectibles within the cull radius, as a filled dot with a
## dark rim and a hollow inner ring so they stay legible over the road
## polylines. Uses the same XZ->local mapping as MapRoads.world_to_local_points;
## a dot is simply culled rather than clipped because a point outside the disc
## has nothing to clip. Claimed ones are skipped (the pause map shows the spent
## state), so the list shrinks as you collect and the pass gets cheaper.
func _draw_collectibles(center: Vector2) -> void:
	if not show_collectibles or _collectible_dots.is_empty() or _player_car == null:
		return
	var player_pos := _player_car.global_position
	for entry in collectible_dots_in_range(Vector2(player_pos.x, player_pos.z)):
		var world_pos: Vector3 = entry["position"]
		var screen := center + Vector2(world_pos.x - player_pos.x, world_pos.z - player_pos.z) * zoom
		if screen.distance_to(center) > minimap_radius:
			continue
		draw_circle(screen, collectible_dot_radius + 1.0, collectible_dot_outline)
		draw_circle(screen, collectible_dot_radius, collectible_dot_color(str(entry["kind"])))
		draw_arc(
			screen,
			maxf(collectible_dot_radius - 2.4, 1.0),
			0.0,
			TAU,
			16,
			collectible_dot_ring,
			collectible_dot_ring_width,
			true
		)

## The collectible entries that _draw_collectibles would actually put a dot on
## for a player at `player_xz`, in draw order: claim-filtered (a banked one is
## skipped) then culled to the same radius the draw pass uses. Public so the
## headless gate can prove the layer produces a NON-EMPTY dot list for a nearby
## unclaimed speed trap and an EMPTY one once the field has banked it, without
## a render pass. Callers resolve the world position themselves; this takes XZ.
func collectible_dots_in_range(player_xz: Vector2) -> Array:
	var out: Array = []
	if not show_collectibles or _collectible_dots.is_empty():
		return out
	_resolve_collectible_source()
	var radius_world := minimap_radius / zoom * _CULL_OVERLAP
	for entry in _collectible_dots:
		var poi_id := str(entry["id"])
		if _collectible_source != null and _collectible_source.is_claimed(poi_id):
			continue
		var world_pos: Vector3 = entry["position"]
		if not _point_inside(player_xz, world_pos, radius_world * radius_world):
			continue
		out.append(entry)
	return out

## The fill colour a collectible dot draws with. This layer's own table wins when
## it names the family (so the HUD art can be tuned independently), otherwise it
## falls back to the SHARED Collectibles.KIND_DOT_COLOR palette the pause map
## resolves through Collectibles.kind_color() -- the default, same literals the
## world map sees. Unknown kinds keep the road colour, the pre-existing fallback.
func collectible_dot_color(kind: String) -> Color:
	var tint: Color = collectible_dots.get(kind, Collectibles.kind_color(kind, road_color))
	return tint

## The open-world collectible runtime (the group holder of banked ids), resolved
## lazily on first use: the field can be added after the HUD, and a circuit scene
## (or a headless gate with no world) simply has none, which is not an error.
## The cached handle is validity-checked on every pass because the HUD outlives
## the world it watches -- on a scene change the old field is freed, and without
## the re-resolve the layer would keep calling into a dead node (or, worse, keep
## believing every trap is still unbanked).
func _resolve_collectible_source() -> void:
	if not is_instance_valid(_collectible_source):
		_collectible_source = null
	if _collectible_source == null and get_tree() != null:
		_collectible_source = get_tree().get_first_node_in_group(CollectibleField.GROUP_NAME) as CollectibleField

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
	if _collectible_dots.is_empty() and _road_source != null:
		_collect_collectibles()
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