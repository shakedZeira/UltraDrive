# scripts/ui/world_map.gd
class_name WorldMap
extends Control

## Full-screen pause-map: north-up, fits all roads (plus POIs and the player)
## into its rect with a uniform scale. Content is cached per rebuild; the map
## only passes through _draw again when it is marked dirty (opened, resized).
## With a WorldDiscovery source, roads split into visited (white) and unvisited
## (grey) segments; without one every road draws in the visited color. Left-click
## a revealed road to fast-travel to it.
##
## Terrain composite (graphics-gap item 9): when a world terrain source exists
## (TerrainSeeder or a Terrain3D) the map preloads the deterministic TerrainBaker
## natural field once per open and tints a discrete grid of cells under the roads
## with MapRoads' satellite biome palette + NW hillshade, so the pause map reads
## like a satellite layer. Heights come from the preloaded full-world field --
## NOT the streamed ring -- so mountains are visible across the whole driveable
## world the moment the map opens and never pop in as the player approaches.
## terrain_cells() reuses the exact world_to_screen fit as the roads, keeping
## everything pixel-aligned. Without a source the composite is skipped and the
## map stays roads-only.

const ROAD_COLOR := Color(0.5, 0.62, 0.85, 0.88)
const UNVISITED_ROAD_COLOR := Color(0.42, 0.44, 0.48, 0.72)
const ROAD_CASING := Color(0.02, 0.03, 0.05, 0.85)
const ROUTE_COLOR := Color(1.0, 0.58, 0.12, 0.95)
const ROAD_WIDTH := 2.5
## Shared player-marker accents (single source of truth in MapRoads, so the
## minimap and the pause map stay in lock-step).
const MARKER_CORE := MapRoads.MARKER_CORE
const MARKER_ACCENT := MapRoads.MARKER_ACCENT
const MARKER_OUTLINE := MapRoads.MARKER_OUTLINE
const MARKER_SIZE := MapRoads.MARKER_SIZE * 1.15
const POI_COLOR := Color(0.75, 0.85, 1.0, 0.85)
const POI_OUTLINE := Color(0.02, 0.04, 0.09, 0.95)
const POI_CORE := Color(0.97, 0.97, 1.0, 0.95)
const POI_RADIUS := 4.0
const BACKDROP_COLOR := Color(0.05, 0.07, 0.13, 0.94)
const BORDER_COLOR := Color(0.3, 0.5, 0.85, 0.6)
const INSET := 32.0
## Cells per axis of the terrain grid. 64x64 = 4096 draw_rect calls per _draw
## pass, rebuilt only when the map reopens, so it stays cheap on any GPU.
const TERRAIN_CELLS := 64

var _dirty := true
var _fit := {}
var _paths: Array = []  # visited segments (each a 2-point PackedVector2Array)
var _grey_paths: Array = []  # unvisited segments
var _route_path := PackedVector2Array()
var _terrain_cells: Array = []  # each {"rect": Rect2, "color": Color}, row-major
var _poi_entries: Array = []  # each {"screen": Vector2, "poi": Dictionary}
var _player_screen := Vector2.ZERO
var _has_player := false
var _player_angle := -PI / 2.0
var _pulse_time := 0.0
var _last_pulse_tick := -1
var _discovery_source: WorldDiscovery = null

## AAA-3 map filters: per-category gates default to full visibility plus an
## optional region substring and travel-eligibility gate, so the shipped map
## renders exactly as before until a UI opts in. POI dots failing the active
## gates are excluded from the fit as well as the draw pass.
var show_pois: bool = true
var show_landmarks: bool = true
var show_events: bool = true
var show_travel: bool = true
var region_filter: String = ""
var _travel_gate: Callable = Callable()

## AAA-3 filter API: flags keys are "pois" / "landmarks" / "events" / "travel"
## (bools, the shipped all-on defaults) plus "region" (String substring on the
## POI's stage name, "" = any). Rebuilds on every call so the dot set always
## matches the active gates.
func set_category_filters(flags: Dictionary) -> void:
	if flags.has("pois"):
		show_pois = bool(flags["pois"])
	if flags.has("landmarks"):
		show_landmarks = bool(flags["landmarks"])
	if flags.has("events"):
		show_events = bool(flags["events"])
	if flags.has("travel"):
		show_travel = bool(flags["travel"])
	if flags.has("region"):
		region_filter = str(flags["region"])
	refresh()

## Travel-eligibility gate for the "travel" filter: a Callable(String poi_id) ->
## bool (typically "road revealed / reachable"). Empty callable = every POI is
## travel-eligible (the shipped default).
func set_travel_gate(gate: Callable) -> void:
	_travel_gate = gate

## Gate predicate applied to every registered POI during _rebuild. Matching is
## exact: a dot renders iff every active gate passes it.
func _poi_passes_filters(poi: Dictionary, poi_id: String) -> bool:
	if not show_pois:
		return false
	var category: String = POIRegistry.category_of(poi)
	if category == POIRegistry.CATEGORY_LANDMARKS and not show_landmarks:
		return false
	if category == POIRegistry.CATEGORY_EVENTS and not show_events:
		return false
	if show_travel and not POIRegistry.is_travel_eligible(poi_id, _travel_gate):
		return false
	if not region_filter.is_empty() and not POIRegistry.matches_region(poi, region_filter):
		return false
	return true

## Optional height reader override: Callable(Vector2 xz) -> float. Tests inject a
## fake here to assert the composite deterministically; when empty, _rebuild()
## falls back to the preloaded full-world field under _resolve_height_reader().
var height_provider: Callable = Callable()

## Preloaded full-world relief (no-pop-in requirement): a deterministic
## TerrainBaker.bake_full_height_image() frame covering the current fit's world
## AABB, baked once on the first open and reused for every rebuild that fit
## covers. The map reads THIS instead of the streamed ring, so distant mountains
## are visible from the moment the map opens.
var _preload_image: Image = null
var _preload_rect := Rect2()
var _preload_texel := Vector2.ONE
var _map_baker := TerrainBaker.new()

func refresh() -> void:
	_dirty = true
	queue_redraw()

func _ready() -> void:
	# The pause menu pauses the tree while the map is open; keep ticking so the
	# player marker's halo pulse stays alive on screen.
	process_mode = Node.PROCESS_MODE_ALWAYS

## Animates the player marker's halo while the pause map is open. Redraws are
## throttled to MapRoads.MARKER_PULSE_STEP so the pulse stays alive without
## re-running the full cached terrain draw every frame.
func _process(delta: float) -> void:
	if not _has_player or not is_visible_in_tree():
		return
	_pulse_time += delta
	var tick := int(_pulse_time / MapRoads.MARKER_PULSE_STEP)
	if tick != _last_pulse_tick:
		_last_pulse_tick = tick
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
	for cell in _terrain_cells:
		draw_rect(cell["rect"], cell["color"], true)
	for path in _grey_paths:
		if path.size() >= 2:
			_draw_road_path(path, UNVISITED_ROAD_COLOR, ROAD_WIDTH)
	for path in _paths:
		if path.size() >= 2:
			_draw_road_path(path, ROAD_COLOR, ROAD_WIDTH)
	if _route_path.size() >= 2:
		_draw_road_path(_route_path, ROUTE_COLOR, ROAD_WIDTH + 2.0)
	for entry in _poi_entries:
		_draw_poi(entry["screen"], entry["poi"])
	if _has_player:
		# The player has no reveal gate: draw the chevron over everything (it is
		# always known, so it must be the most obvious thing on the map).
		MapRoads.draw_player_marker(self, _player_screen, _player_angle, _pulse_time, MARKER_SIZE)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 2.0)

## Draws a road polyline with a dark casing underneath so the network stays
## readable over the terrain composite.
func _draw_road_path(path: PackedVector2Array, color: Color, width: float) -> void:
	draw_polyline(path, ROAD_CASING, width + 2.5)
	draw_polyline(path, color, width)

## Draws a POI as a small satellite-style pin: dark outline ring around a
## zone/tier-coloured fill with a bright core, readable over any terrain tint.
func _draw_poi(screen: Vector2, poi: Dictionary) -> void:
	var fill := _poi_fill_color(poi)
	draw_circle(screen, POI_RADIUS + 2.0, POI_OUTLINE)
	draw_circle(screen, POI_RADIUS, fill)
	draw_circle(screen, POI_RADIUS - 2.2, POI_CORE)

## Zone-aware POI colour: base land- mark stages map to their region, event sites
## fall back to their road tier colour so they never blend into the terrain.
func _poi_fill_color(poi: Dictionary) -> Color:
	var stage := str(poi.get("stage", "")).to_lower()
	if stage.contains("festival") or stage.contains("plains"):
		return Color(0.96, 0.72, 0.2)
	if stage.contains("lowland"):
		return Color(0.34, 0.62, 0.3)
	if stage.contains("coast") or stage.contains("lake"):
		return Color(0.24, 0.58, 0.64)
	if stage.contains("highland") or stage.contains("forest"):
		return Color(0.86, 0.5, 0.2)
	if stage.contains("alpine"):
		return Color(0.42, 0.68, 0.95)
	match int(poi.get("tier", -1)):
		RoadDef.Tier.HIGHWAY:
			return Color(0.7, 0.45, 0.85)
		RoadDef.Tier.ARTERIAL:
			return Color(0.95, 0.6, 0.25)
		RoadDef.Tier.TOUGE, RoadDef.Tier.COASTAL:
			return Color(0.4, 0.7, 0.92)
		_:
			return POI_COLOR

func _rebuild() -> void:
	_dirty = false
	var source := MapRoads.resolve_road_source(self)
	var with_world := source != null
	var roads := MapRoads.get_roads(source)
	var car := VehicleManager.get_player_car()
	_has_player = car != null
	var player_pos := Vector3.ZERO
	var player_facing := Vector3.ZERO
	if car != null:
		player_pos = car.global_position
		player_facing = -car.global_basis.z
	_player_angle = MapRoads.marker_world_angle(player_facing)
	_discovery_source = MapRoads.resolve_discovery_source(self) as WorldDiscovery

	var content: Array = []
	var raw_pois: Array = []
	var raw_poi_dicts: Array = []
	for chain in roads:
		for p in chain:
			content.append(p)
	if _has_player:
		content.append(player_pos)
	# POIs only make sense in the open world (i.e. when a road source exists).
	if with_world:
		for poi_id in POIRegistry.get_poi_ids():
			var poi := POIRegistry.get_poi(poi_id)
			if not _poi_passes_filters(poi, poi_id):
				continue
			var pos: Vector3 = poi.get("position", Vector3.ZERO)
			content.append(pos)
			raw_pois.append(pos)
			raw_poi_dicts.append(poi)

	_fit = MapRoads.compute_fit(content, player_pos, size, INSET)
	# Terrain composite: sample the height grid BEFORE the road culling below so
	# the same _fit drives both; roads/nothing else changes the fit.
	_terrain_cells = []
	var provider := height_provider
	if not provider.is_valid():
		provider = _resolve_height_reader()
	if provider.is_valid():
		_terrain_cells = MapRoads.terrain_cells(_fit, provider, TERRAIN_CELLS, TERRAIN_CELLS)
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
	_poi_entries = []
	for i in raw_pois.size():
		_poi_entries.append({
			"screen": MapRoads.world_to_screen(raw_pois[i], _fit),
			"poi": raw_poi_dicts[i],
		})
	_player_screen = MapRoads.world_to_screen(player_pos, _fit) if _has_player else Vector2.ZERO

## Height reader (Callable(Vector2 xz) -> float) for the pause-map composite.
## Preloads the deterministic TerrainBaker natural field once per fit (64x64
## texels over the fit AABB, ~10ms on CPU) and serves the whole map from that
## cache, so elevations are identical everywhere the moment the map opens -- no
## seeder/live-ring streaming, no pop-in as the player approaches. Gated on a
## world terrain source (TerrainSeeder or a Terrain3D) matching the old reader;
## without one the map stays roads-only.
func _resolve_height_reader() -> Callable:
	if get_tree() == null:
		return Callable()
	if MapRoads.resolve_seeder(self) == null and not MapRoads.height_from_terrain(self).is_valid():
		return Callable()
	if _fit.is_empty():
		return Callable()
	var world_min: Vector2 = _fit["world_min"]
	var world_max: Vector2 = _fit["world_max"]
	var want := Rect2(world_min, world_max - world_min)
	if not _preload_rect.encloses(want):
		_preload_rect = want
		_preload_texel = Vector2(
			maxf(want.size.x / float(TERRAIN_CELLS), 0.001),
			maxf(want.size.y / float(TERRAIN_CELLS), 0.001))
		_preload_image = _map_baker.bake_full_height_image(
			world_min, world_max, TERRAIN_CELLS, TERRAIN_CELLS)
	return MapRoads.height_from_image(_preload_image, _preload_rect.position, _preload_texel)

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