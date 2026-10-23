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
## Live rivals: RaceManager's spawned field draws as small orange heading
## triangles (MapRoads rival blips) under the player chevron, sourced live each
## frame — an empty roster / free roam simply draws nothing.

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

## Shared rival-blip accents (same single-source-of-truth rule as the marker).
const RIVAL_FILL := MapRoads.RIVAL_FILL
const RIVAL_OUTLINE := MapRoads.RIVAL_OUTLINE
const RIVAL_SIZE := MapRoads.RIVAL_SIZE

## Road width on the HUD disc relative to the pause map widths.
const MINIMAP_ROAD_SCALE := 0.72
## Relief is dimmed and slightly desaturated so the white road net owns the eye.
const RELIEF_DIM := 0.80
const RELIEF_SATURATION := 0.85
const _CULL_OVERLAP := 1.1
const _ROUTE_CACHE_CELL := 25.0
## Cell size (m) of the per-chain spatial index used to WINDOW a chain before the
## per-frame world->screen transform + circle clip. Big on purpose: the minimap
## sees a ~550 m radius, so a coarse cell keeps the "which indices are in view"
## query to a few dozen cells while still enumerating every in-view vertex.
const _CHAIN_INDEX_CELL := 256.0

var _player_car: VehiclePhysics
var _road_source: Node = null
var _road_signature := ""
var _scene_roads: Array = []  # cached chains for the current signature
## RoadDef.Tier per cached chain (index-parallel with _scene_roads): the class that
## picks each road width and colour (highway > main road > mountain > dirt).
var _scene_tiers: Array = []
## Road pieces gathered by one draw pass: each {"pts", "tier", "visited"}. They are
## drawn together (all casings, then all cores) so crossings stay clean.
var _frame_runs: Array = []
## Shared shader relief under the roads (see MapTerrain). Built in code; it draws
## behind this control so the roads, pins and marker land on top of it.
var _terrain_layer: ColorRect = null
var _terrain_mat: ShaderMaterial = null
var _relief_checked := false
var _relief_rect := Rect2()
## One PointGridIndex per `_scene_roads` chain (XZ vertex grid), rebuilt beside
## `_scene_roads`. Used to cull the per-redraw transform to the visible span.
var _chain_indexes: Array = []
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

## Live rival layer. `rival_source` is an optional Callable() -> Array of car
## nodes (tests inject one); when empty the roster comes from RaceManager's
## spawn grid via MapRoads.live_rivals. The cached `_rivals` handle is refreshed
## every frame and the metre-rounded `_rival_sig` is what decides whether a
## rival moved, so the roads/route pass is never rebuilt just to move a blip.
@export var show_rivals: bool = true
var rival_source: Callable = Callable()
var _rivals: Array = []
var _rival_sig := ""

func _ready() -> void:
	_player_car = VehicleManager.get_player_car()
	_road_source = MapRoads.resolve_road_source(self) as Node
	_road_signature = MapRoads.signature(_road_source)
	_scene_roads = MapRoads.get_roads(_road_source)
	_scene_tiers = MapRoads.get_road_tiers(_road_source)
	_rebuild_chain_indexes()
	_build_terrain_layer()
	_discovery_source = MapRoads.resolve_discovery_source(self) as WorldDiscovery
	_collect_collectibles()
	_rivals = MapRoads.live_rivals(rival_source)
	_rival_sig = _roster_signature(_rivals)

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
	var relief_on := _sync_terrain_layer(center)
	# Soft drop shadow so the disc lifts off the 3D scene, and a dark base for the
	# roads-only case (no shader relief: a circuit scene, or the bake not done yet).
	draw_circle(center + Vector2(0.0, 3.0), minimap_radius + 3.0, Color(0.0, 0.0, 0.0, 0.35))
	if not relief_on:
		draw_circle(center, minimap_radius, Color(0.03, 0.06, 0.11, 0.62))
	_draw_roads(center)
	_draw_route(center)
	_draw_collectibles(center)
	_draw_rivals(center)

	# Player chevron: the same marker the pause map uses, so the player reads as
	# one unmistakable object on the HUD minimap. Pointing the way the car faces.
	var accent := MapRoads.MARKER_ACCENT
	draw_circle(center, MARKER_SIZE * 1.9, Color(accent.r, accent.g, accent.b, 0.13))
	MapRoads.draw_player_marker(self, center, _marker_angle, _pulse_time, MARKER_SIZE)
	_draw_bezel(center)

## FH-style bezel: a dark ring, a hairline light edge and a fixed "N" tag at the
## top (the map is north-up, so north never moves).
func _draw_bezel(center: Vector2) -> void:
	draw_arc(center, minimap_radius - 1.5, 0.0, TAU, 72, Color(0.02, 0.04, 0.08, 0.92), 3.5, true)
	draw_arc(center, minimap_radius - 3.5, 0.0, TAU, 72, Color(1.0, 1.0, 1.0, 0.22), 1.0, true)
	draw_arc(center, minimap_radius, 0.0, TAU, 72, ring_color, 1.5, true)
	var font := get_theme_default_font()
	if font != null:
		var tag := center + Vector2(0.0, -minimap_radius + 11.0)
		draw_circle(tag, 8.0, Color(0.02, 0.04, 0.08, 0.92))
		draw_string(font, tag + Vector2(-4.2, 4.4), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.45, 0.40))

## Join the shared relief bake before the HUD goes (see WorldMap._exit_tree).
func _exit_tree() -> void:
	MapTerrain.reset()

func _build_terrain_layer() -> void:
	if _terrain_layer != null:
		return
	_terrain_layer = ColorRect.new()
	_terrain_layer.name = "TerrainLayer"
	_terrain_layer.color = Color.WHITE
	_terrain_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain_layer.show_behind_parent = true
	_terrain_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_terrain_layer.visible = false
	_terrain_mat = MapTerrain.make_material()
	_terrain_layer.material = _terrain_mat
	add_child(_terrain_layer, false, Node.INTERNAL_MODE_FRONT)

## Ask for the shared relief once a road source exists, but only where a world
## terrain source exists too (the open world): circuit scenes stay roads-only and
## never start a bake. The scene-tree walks happen ONCE here, not per frame.
func _request_relief() -> void:
	if _relief_checked or _road_source == null or get_tree() == null:
		return
	_relief_checked = true
	if MapRoads.resolve_seeder(self) == null and not MapRoads.height_from_terrain(self).is_valid():
		return
	_relief_rect = MapTerrain.world_rect_for_roads(_scene_roads)
	MapTerrain.request(_relief_rect)

## Aim the shader at the player: world xz under the control's top-left px is the
## player minus the centre offset, at `zoom` px per metre. Returns whether the
## relief is on screen.
func _sync_terrain_layer(center: Vector2) -> bool:
	if _terrain_layer == null:
		return false
	var ok := _relief_rect.size.x > 0.0 and MapTerrain.is_ready() and MapTerrain.rect() == _relief_rect
	_terrain_layer.visible = ok
	if not ok:
		return false
	var p := _player_car.global_position
	MapTerrain.apply_view(_terrain_mat, size, Vector2(p.x, p.z) - center / zoom, zoom,
		minimap_radius, RELIEF_DIM, RELIEF_SATURATION, 1.0)
	return true

## Live rival blips: the shared orange heading triangle at the SAME world->screen
## mapping the roads use (MapRoads.minimap_point_screen is a single-vertex
## world_to_local_points), culled to the disc. The layer sits under the player
## chevron on purpose: the player must always dominate its own minimap.
func _draw_rivals(center: Vector2) -> void:
	for entry in rival_blips(center):
		var blip: Dictionary = entry
		var screen: Vector2 = blip["screen"]
		var angle := float(blip["angle"])
		MapRoads.draw_rival_blip(self, screen, angle)

## The rival blips the draw pass would put on the minimap for the current
## roster, as {"screen": Vector2, "angle": float} entries in draw order.
## Public so the headless gate can assert the projection (screen position and
## heading angle) and the graceful skips without a render pass. No player car,
## no roster, or show_rivals off => an empty list, never a crash.
func rival_blips(center: Vector2) -> Array:
	var out: Array = []
	if not show_rivals or _player_car == null:
		return out
	var player_pos := _player_car.global_position
	var player_xz := Vector2(player_pos.x, player_pos.z)
	var radius_world := minimap_radius / zoom * _CULL_OVERLAP
	var radius_world_sq := radius_world * radius_world
	for entry in MapRoads.rival_entries(_rivals):
		var world_pos: Vector3 = entry["position"]
		if not _point_inside(player_xz, world_pos, radius_world_sq):
			continue
		var screen := MapRoads.minimap_point_screen(world_pos, player_pos, center, zoom)
		if screen.distance_to(center) > minimap_radius:
			continue
		out.append({
			"screen": screen,
			"angle": MapRoads.marker_minimap_angle(entry["facing"] as Vector3),
		})
	return out

## Cheap "did any rival move" signature: roster size plus each blip's
## metre-rounded XZ, the same trick MapRoads.signature() uses for roads. A
## metre of rounding is what keeps a stationary field from redrawing the HUD
## every frame while a moving one still updates the moment it goes.
func _roster_signature(cars: Array) -> String:
	var parts := PackedStringArray()
	parts.append(str(cars.size()))
	for entry in MapRoads.rival_entries(cars):
		var p: Vector3 = entry["position"]
		parts.append("%d,%d" % [roundi(p.x), roundi(p.z)])
	return "|".join(parts)

func _rebuild_chain_indexes() -> void:
	_chain_indexes = []
	for chain in _scene_roads:
		var grid := PointGridIndex.new()
		grid.build(chain, _CHAIN_INDEX_CELL)
		_chain_indexes.append(grid)

## The [first,last] index span of `chain` that lies within `radius_world` of the
## player, or (-1,-1) when none does. Exact: the index enumerates every in-view
## vertex, so the span covers them all (a single contiguous slice can be drawn
## and clipped in place of the whole loop). Falls back to a full brute-force scan
## -- and, when the chain is entirely out of view, to the old early-out -- while
## no index is available.
func _chain_window(road_id: int, chain: Array, player_xz: Vector2, radius_world: float) -> Vector2i:
	if road_id < _chain_indexes.size():
		var grid: PointGridIndex = _chain_indexes[road_id]
		if grid != null and grid.matches(chain.size()):
			return grid.min_max_within(player_xz, radius_world)
	# No index (rare pre-bootstrap frame): keep the old behaviour -- skip a chain
	# with nothing in view, otherwise draw the whole thing.
	if _chain_stays_outside(player_xz, chain, radius_world * radius_world):
		return Vector2i(-1, -1)
	return Vector2i(0, chain.size() - 1)

func _draw_roads(center: Vector2) -> void:
	if _road_source == null:
		return
	var player_pos := _player_car.global_position
	var player_xz := Vector2(player_pos.x, player_pos.z)
	var radius_world := minimap_radius / zoom * _CULL_OVERLAP
	var radius_world_sq := radius_world * radius_world
	_frame_runs = []
	for road_id in _scene_roads.size():
		var chain: Array = _scene_roads[road_id]
		# Only the in-view span is transformed and clipped: the whole 13.6 km
		# Le Mans loop is ~4,800 points but the minimap shows ~1.1 km of it, so
		# slicing to the visible span (plus one segment either side, so the
		# boundary crossing points are preserved) is what keeps the redraw cheap.
		# A (-1,-1) span means the chain is entirely out of view -> nothing drawn.
		var win := _chain_window(road_id, chain, player_xz, radius_world)
		if win.x < 0:
			continue
		var tier := int(_scene_tiers[road_id]) if road_id < _scene_tiers.size() else MapRoads.UNKNOWN_TIER
		var mask: Array[bool] = []
		if _discovery_source != null:
			mask = _discovery_source.segment_visited_mask(road_id)
		if mask.is_empty() or (mask.size() != chain.size() - 1 and mask.size() != chain.size()):
			_draw_chain_polyline(player_pos, center, chain, win.x, win.y, tier)
			continue
		_draw_chain_by_color_runs(player_pos, center, chain, mask, radius_world_sq, tier)
	_flush_runs()

func _chain_stays_outside(player_xz: Vector2, chain: Array, radius_world_sq: float) -> bool:
	for w in chain:
		if _point_inside(player_xz, w, radius_world_sq):
			return false
	return true

func _point_inside(player_xz: Vector2, w: Vector3, radius_world_sq: float) -> bool:
	var dx := w.x - player_xz.x
	var dz := w.z - player_xz.y
	return dx * dx + dz * dz <= radius_world_sq

func _draw_chain_polyline(player_pos: Vector3, center: Vector2, chain: Array, from_i: int, to_i: int, tier: int = MapRoads.UNKNOWN_TIER) -> void:
	# One point outside the span on each side keeps the circle entry/exit
	# crossing point a full-chain clip would have inserted on the boundary
	# segment, so the drawn polyline is identical to clipping the whole chain.
	var lo := maxi(from_i - 1, 0)
	var hi := mini(to_i + 1, chain.size() - 1)
	var sub: Array = []
	for i in range(lo, hi + 1):
		sub.append(chain[i])
	var local := MapRoads.world_to_local_points(sub, player_pos, center, zoom)
	var clipped := MapRoads.clip_circle(local, center, minimap_radius)
	if clipped.size() >= 2:
		_frame_runs.append({"pts": clipped, "tier": tier, "visited": true})

## Draws the gathered road pieces: lowest class first, all casings before all
## cores, so highways ride on top and a junction has no dark seam through it.
func _flush_runs() -> void:
	if _frame_runs.is_empty():
		return
	_frame_runs.sort_custom(func(a, b):
		if bool(a["visited"]) != bool(b["visited"]):
			return not bool(a["visited"])
		return MapStyle.road_rank(int(a["tier"])) < MapStyle.road_rank(int(b["tier"])))
	for pass_index in 2:
		for run in _frame_runs:
			var tier := int(run["tier"])
			var visited := bool(run["visited"])
			var pts: PackedVector2Array = run["pts"]
			var width := MapStyle.road_width(tier) * MINIMAP_ROAD_SCALE
			if pass_index == 0:
				draw_polyline(pts, MapStyle.road_casing(tier, visited), width + 2.0, true)
			else:
				draw_polyline(pts, MapStyle.road_core(tier, visited), width, true)
	_frame_runs = []

func _draw_chain_by_color_runs(player_pos: Vector3, center: Vector2, chain: Array, mask: Array[bool], radius_world_sq: float, tier: int = MapRoads.UNKNOWN_TIER) -> void:
	var player_xz := Vector2(player_pos.x, player_pos.z)
	var run_start := 0
	while run_start < mask.size():
		var visited := mask[run_start]
		var run_end := run_start + 1
		while run_end < mask.size() and mask[run_end] == visited:
			run_end += 1
		_draw_chain_run(player_pos, player_xz, center, chain, run_start, run_end, visited, radius_world_sq, tier)
		run_start = run_end

func _draw_chain_run(player_pos: Vector3, player_xz: Vector2, center: Vector2, chain: Array, from_seg: int, to_seg: int, visited: bool, radius_world_sq: float, tier: int = MapRoads.UNKNOWN_TIER) -> void:
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
		_frame_runs.append({"pts": clipped, "tier": tier, "visited": visited})

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
		var badge_r := collectible_dot_radius + 1.5
		MapStyle.draw_badge(self, screen, badge_r, collectible_dot_color(str(entry["kind"])),
			str(MapStyle.COLLECTIBLE_GLYPHS.get(str(entry["kind"]), "")), Color.WHITE)

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
		MapStyle.draw_route_ribbon(self, clipped, route_color, 3.4, _pulse_time)

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
	# Rivals are LIVE data: re-read the roster every frame so a race that spawns
	# its grid after the HUD (or a rival that is freed) is reflected at once.
	_rivals = MapRoads.live_rivals(rival_source)
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
		_scene_tiers = MapRoads.get_road_tiers(_road_source)
		_rebuild_chain_indexes()
		_relief_checked = false
	_request_relief()
	if _relief_rect.size.x > 0.0 and not MapTerrain.is_ready() and MapTerrain.poll():
		_last_redraw_pos = Vector3(INF, INF, INF)
	if _player_car == null:
		_last_redraw_pos = Vector3(INF, INF, INF)
		_last_heading = INF
		queue_redraw()
		return
	var pos := _player_car.global_position
	var car_facing: Vector3 = -_player_car.global_basis.z
	var heading := atan2(car_facing.x, car_facing.z)
	_marker_angle = MapRoads.marker_minimap_angle(car_facing)
	# Redraw only when the player moved enough or turned, when a rival moved, or
	# when the halo pulse crossed its redraw cadence, so the marker and the field
	# stay live without rebuilding the road polylines every frame.
	_pulse_time += delta
	var tick := int(_pulse_time / MapRoads.MARKER_PULSE_STEP)
	var rival_sig := _roster_signature(_rivals) if show_rivals else ""
	var rival_moved := rival_sig != _rival_sig
	_rival_sig = rival_sig
	if _last_redraw_pos.distance_to(pos) > 4.0 or absf(heading - _last_heading) > 0.05 \
			or tick != _last_pulse_tick or rival_moved:
		_last_redraw_pos = pos
		_last_heading = heading
		_last_pulse_tick = tick
		queue_redraw()