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
##
## Road names (every named road -- see ROAD_LABELS): each road gets its name drawn
## along its own line at the arc-length midpoint, tinted like the road it names so
## an unrevealed road is not stamped as driven, and placed greedily longest-first
## with a collision pass, because readable names beat overlapping ones. Text comes
## from the curated RoadDef.name (CorridorPlanner.ROAD_NAMES) with road_label() as
## the fallback. show_road_labels turns the whole layer off without touching the
## lines.
##
## Live rivals: the RaceManager field draws as small orange heading triangles
## (MapRoads rival blips) over the cached content. This layer is deliberately
## NOT part of the cached rebuild -- rival positions are read live on every draw
## pass and _process re-queues a draw when a blip moves, so an open paused map
## can never show stale cars. The fit stays cached, so the zoom never jitters
## as the field spreads out.

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
## FH-style: the player is the biggest object on the map, so the pause map draws
## the shared chevron noticeably larger than the HUD minimap does.
const MARKER_SIZE := MapRoads.MARKER_SIZE * 1.8
## Shared rival-blip accents (same single-source-of-truth rule as the marker).
const RIVAL_FILL := MapRoads.RIVAL_FILL
const RIVAL_OUTLINE := MapRoads.RIVAL_OUTLINE
const RIVAL_SIZE := MapRoads.RIVAL_SIZE
const POI_COLOR := Color(0.75, 0.85, 1.0, 0.85)
const POI_OUTLINE := Color(0.02, 0.04, 0.09, 0.95)
const POI_CORE := Color(0.97, 0.97, 1.0, 0.95)
const POI_RADIUS := 4.0
## Collectible pins (bonus boards, speed traps, photo spots) draw a little
## LARGER than a landmark pin and HOLLOW instead of solid-cored, in the shared
## Collectibles.KIND_DOT_COLOR family palette. A landmark is a place you visit;
## a collectible is a thing you hit, and over a road-coloured 10 km network the
## difference between "another map dot" and "a gate I have to hit" is exactly a
## bigger ring in the family's own colour. The claimed look (below) is preserved:
## a banked pin keeps the ring but drops its brightness with the fill.
const COLLECTIBLE_RADIUS := 5.0
const COLLECTIBLE_RING := Color(1.0, 0.96, 0.94, 0.95)
const COLLECTIBLE_RING_WIDTH := 1.8
## AAA-16: a collectible the player has already banked keeps its dot (so the map
## still shows where it is) but reads as spent -- the family fill is lerped toward
## this tint, a landmark loses its bright core, and a collectible's inner ring
## turns to the tint instead of white -- which is the whole claimed/unclaimed
## visual state this milestone needs without any new UI plumbing.
const POI_CLAIMED_TINT := Color(0.5, 0.55, 0.65, 0.5)
const POI_CLAIMED_MIX := 0.62
const BACKDROP_COLOR := Color(0.05, 0.07, 0.13, 0.94)
const BORDER_COLOR := Color(0.3, 0.5, 0.85, 0.6)
const INSET := 32.0
## Cells per axis of the terrain grid. 64x64 = 4096 draw_rect calls per _draw
## pass, rebuilt only when the map reopens, so it stays cheap on any GPU.
const TERRAIN_CELLS := 64

## FH-style presentation (see MapStyle). Pin badge radii in px at zoom 1: a
## landmark is the biggest pin, an event next, a collectible the smallest, so
## the 5 places a player drives to outrank the ~30 things they hit on the way.
const BADGE_LANDMARK := 11.0
const BADGE_EVENT := 9.5
const BADGE_COLLECTIBLE := 7.5
const BADGE_ZOOM_GROWTH := 0.22
## View limits for the zoomable map. 1.0 is the plain fit and never zooms out.
const MIN_ZOOM := 1.0
const MAX_ZOOM := 8.0
const ZOOM_STEP := 1.3
## A press that moves further than this (px) is a PAN, not a click, so a plain
## click still fast-travels.
const DRAG_THRESHOLD_PX := 5.0
## Exponential smoothing rate (1/s) the displayed view uses to chase the target.
const VIEW_SMOOTHING := 14.0
const HOVER_RADIUS_PX := 14.0
const REGION_LABEL_SIZE := 17
const REGION_LABEL_TRACKING := 5.0
const VIGNETTE_STRENGTH := 0.55

## Road NAMES on the pause map. EVERY named road is a candidate now: the seven
## curated majors plus the ramps, returns, shoreline ribbons and dirt cuts that
## used to stay anonymous.
##
## Selection rule (the old one was "a ring/loop or a district connector, never a
## ramp stub, a dirt cut or a coastal dead-end") is GONE, and deliberately so:
## those twelve roads are the ones a player asks "what was that called?" about,
## and every corridor now carries a curated name (CorridorPlanner.ROAD_NAMES) so
## there is nothing to hide. What keeps the map readable at 19 labels is NOT a
## whitelist -- it is the existing greedy longest-first pass plus its collision
## test, so where roads converge the longest names win the space and the rest are
## simply not drawn. read _place_road_labels() before adding a label by hand.
##
## ROAD_LABELS remains the FALLBACK table for a road whose defs carry no name
## (a scene-authored or test-stubbed RoadDef with an empty `name`), which is why
## its seven entries are still the authoritative spelling for those ids.
const MAJOR_ROAD_IDS: Array[String] = [
	"hub-ring",
	"hub-pass",
	"pass-loop",
	"highway-ring",
	"touge-a",
	"touge-b",
	"hub-coast",
]
## Player-facing names for the roads above. These are READ, so they are spelled
## for a player ("Mountain Pass Loop") and never derived from the id; an id with
## no entry here still renders through road_label()'s title-cased fallback rather
## than as a blank or a raw slug.
const ROAD_LABELS := {
	"hub-ring": "Hub Ring",
	"hub-pass": "Hub Pass Link",
	"pass-loop": "Mountain Pass Loop",
	"highway-ring": "Ring Highway",
	"touge-a": "Touge A",
	"touge-b": "Touge B",
	"hub-coast": "Coast Link",
}
## Label typography. 14 px is deliberately small: this is a full-screen map where
## seven names must annotate the network, not compete with it. The outline reuses
## the road casing colour so a name stays readable over snow, water and the
## highway ring it may sit on. The font is the theme default (the engine
## fallback unless the UI theme ships one), so this feature adds no asset.
const ROAD_LABEL_FONT_SIZE := 14
const ROAD_LABEL_COLOR := Color(0.93, 0.96, 1.0, 0.95)
## An unrevealed road draws grey, and its name follows it: a road the player has
## never driven is not labelled as if they had. The name is still drawn -- the
## line it names is already on the map unrevealed, so the text spoils nothing.
const UNVISITED_ROAD_LABEL_COLOR := Color(0.72, 0.75, 0.80, 0.7)
const ROAD_LABEL_OUTLINE := ROAD_CASING
## Breathing room (pixels) kept around every label box, so two names that would
## merely touch still count as colliding and one of them is dropped.
const ROAD_LABEL_PADDING := 4.0
## A label whose box would cross the map border is dropped rather than clipped
## in half against the frame.
const ROAD_LABEL_EDGE_MARGIN := 2.0

var _dirty := true
var _fit := {}
var _paths: Array = []  # visited segments (each a 2-point PackedVector2Array)
var _grey_paths: Array = []  # unvisited segments
var _route_path := PackedVector2Array()
var _road_labels: Array = []  # placed names (each the place_road_labels() entry)
var _terrain_cells: Array = []  # each {"rect": Rect2, "color": Color}, row-major
var _poi_entries: Array = []  # each {"screen": Vector2, "poi": Dictionary}
var _player_screen := Vector2.ZERO
var _has_player := false
var _player_angle := -PI / 2.0
var _pulse_time := 0.0
var _last_pulse_tick := -1
var _discovery_source: WorldDiscovery = null
var _collectible_source: CollectibleField = null
## Road polylines with their class: each {"pts": PackedVector2Array, "tier": int,
## "visited": bool}, sorted so a highway draws over an arterial over a dirt track.
## `_paths` / `_grey_paths` above hold the same polylines split by reveal state.
var _road_runs: Array = []
var _terrain_layer: ColorRect = null
var _terrain_mat: ShaderMaterial = null
var _terrain_rect := Rect2()

## VIEW STATE. `_zoom`/`_pan` are the TARGET (what hit-tests and clicks read);
## `_view_zoom`/`_view_pan` are the DISPLAYED values that chase it each frame, so
## zoom, pan and focus glide instead of snapping. The base fit `_fit` is never
## touched by the view: with zoom 1 / pan 0 every position equals the old map.
var _zoom := 1.0
var _pan := Vector2.ZERO
var _view_zoom := 1.0
var _view_pan := Vector2.ZERO
var _press_pos := Vector2.ZERO
var _pressing := false
var _dragged := false
var _hover_poi_id := ""
var _hover_pos := Vector2.ZERO
var _route_goal_screen := Vector2.ZERO
var _has_route_goal := false
var _vignette_tex: Texture2D = null
var _region_labels: Array = []
## True while the shared relief for this map's rect is still baking on a worker.
var _terrain_waiting := false

## AAA-3 map filters: per-category gates default to full visibility plus an
## optional region substring and travel-eligibility gate, so the shipped map
## renders exactly as before until a UI opts in. POI dots failing the active
## gates are excluded from the fit as well as the draw pass.
##
## The collectibles gate is deliberately ITS OWN flag and not part of "events":
## a speed trap is a gameplay target, so hiding it is never a consequence of
## hiding the calendar markers. Shipped default: everything on.
var show_pois: bool = true
var show_landmarks: bool = true
var show_events: bool = true
var show_collectibles: bool = true
var show_travel: bool = true
## Live rivals are their own gate for the same reason collectibles are: a player
## who wants a clean solo map can drop the field without losing anything else.
var show_rivals: bool = true
## Road names are their own gate for the same reason collectibles are: a player
## who wants the network clean can drop the text without losing the lines.
var show_road_labels: bool = true
var region_filter: String = ""
var _travel_gate: Callable = Callable()

## Live rival source override: a Callable() -> Array of car nodes (tests inject
## one). Empty = MapRoads.live_rivals reads RaceManager's spawn grid.
var rival_source: Callable = Callable()
var _last_rival_sig := ""

## AAA-3 filter API: flags keys are "pois" / "landmarks" / "events" /
## "collectibles" / "travel" / "road_labels" / "rivals" (bools, the shipped
## all-on defaults) plus "region" (String substring on the POI's stage name,
## "" = any). Only the keys present are touched, so a partial update never
## silently resets another gate. Marks the map dirty and queues a redraw, so the
## dot set is rebuilt against the active gates on the next draw pass (headless
## gates call _rebuild() directly).
func set_category_filters(flags: Dictionary) -> void:
	if flags.has("pois"):
		show_pois = bool(flags["pois"])
	if flags.has("landmarks"):
		show_landmarks = bool(flags["landmarks"])
	if flags.has("events"):
		show_events = bool(flags["events"])
	if flags.has("collectibles"):
		show_collectibles = bool(flags["collectibles"])
	if flags.has("travel"):
		show_travel = bool(flags["travel"])
	if flags.has("rivals"):
		show_rivals = bool(flags["rivals"])
	if flags.has("road_labels"):
		show_road_labels = bool(flags["road_labels"])
	if flags.has("region"):
		region_filter = str(flags["region"])
	refresh()

## Every shipped gate explicitly ON -- the reset the map and the gate use after a
## partial update, since set_category_filters({}) is a no-op by design.
func reset_category_filters() -> void:
	set_category_filters({
		"pois": true,
		"landmarks": true,
		"events": true,
		"collectibles": true,
		"travel": true,
		"road_labels": true,
		"rivals": true,
		"region": "",
	})

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
	var category: String = POIRegistry.category_of(poi, poi_id)
	if category == POIRegistry.CATEGORY_LANDMARKS and not show_landmarks:
		return false
	if category == POIRegistry.CATEGORY_EVENTS and not show_events:
		return false
	if category == POIRegistry.CATEGORY_COLLECTIBLES and not show_collectibles:
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
	clip_contents = true
	_build_terrain_layer()

## The shared relief bake runs on a worker thread; leaving the tree must join it,
## or a process that quits mid-bake (a test run, a fast scene change) crashes.
func _exit_tree() -> void:
	MapTerrain.reset()

## The shader-shaded relief sits in a child that draws BEHIND this control's own
## _draw(), so roads, pins and labels land on top of it. Built in code, so the
## pause_menu scene needs no extra node.
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

## Animates the player marker's halo while the pause map is open and keeps the
## LIVE rival blips current. Redraws are throttled to MapRoads.MARKER_PULSE_STEP
## so the pulse stays alive without re-running the full cached terrain draw every
## frame; a roster that actually moved re-queues a draw on top of that.
func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _advance_view(delta):
		queue_redraw()
	if _terrain_waiting and MapTerrain.poll():
		_terrain_waiting = false
		queue_redraw()
	_pan_with_stick(delta)
	var rival_sig := _roster_signature() if show_rivals else ""
	var rivals_moved := rival_sig != _last_rival_sig
	_last_rival_sig = rival_sig
	if rivals_moved:
		queue_redraw()
	if not _has_player:
		return
	_pulse_time += delta
	# The beacon ring and the route chevrons are time-driven, so they redraw every
	# frame to glide; the pass is only polylines and ~100 badges now (the
	# 4,096-rect terrain grid is a shader), so that is cheap.
	_last_pulse_tick = int(_pulse_time / MapRoads.MARKER_PULSE_STEP)
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

# ---------------------------------------------------------------------------
# View: zoom / pan / focus. All of it is a screen-space affine on top of the base
# fit, so the cached content (roads, pins, labels) is never rebuilt by a view change.
# ---------------------------------------------------------------------------

## base map px -> view px for a zoom/pan pair (zoom about the control centre).
func _view_xform(zoom_value: float, pan_value: Vector2) -> Transform2D:
	var focus := size * 0.5
	return Transform2D(Vector2(zoom_value, 0.0), Vector2(0.0, zoom_value),
		focus * (1.0 - zoom_value) + pan_value)

## The pan limit that keeps the zoomed map covering the whole control (never a
## void past an edge). Zero at zoom 1, so the plain fit cannot be dragged at all.
func _clamp_pan(pan_value: Vector2, zoom_value: float) -> Vector2:
	var limit := size * 0.5 * maxf(zoom_value - 1.0, 0.0)
	return Vector2(clampf(pan_value.x, -limit.x, limit.x), clampf(pan_value.y, -limit.y, limit.y))

func get_zoom() -> float:
	return _zoom

## A base-fit screen position as the TARGET view shows it (what a click or a
## hit-test must use).
func base_to_view(base_pos: Vector2) -> Vector2:
	return _view_xform(_zoom, _pan) * base_pos

## Inverse of base_to_view: a screen position inside the control back to base-fit
## coordinates, which MapRoads.screen_to_world() understands.
func view_to_base(view_pos: Vector2) -> Vector2:
	return _view_xform(_zoom, _pan).affine_inverse() * view_pos

## Zoom the TARGET view to `value` (clamped) keeping the map point under `focus`
## (a control-local px) where it is.
func set_zoom_at(value: float, focus: Vector2) -> void:
	var target := clampf(value, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(target, _zoom):
		return
	var base_point := view_to_base(focus)
	_zoom = target
	_pan = _clamp_pan(focus - base_point * target - size * 0.5 * (1.0 - target), target)
	queue_redraw()

func zoom_by(factor: float, focus: Vector2) -> void:
	if factor > 0.0:
		set_zoom_at(_zoom * factor, focus)

func pan_by(delta: Vector2) -> void:
	_pan = _clamp_pan(_pan + delta, _zoom)
	queue_redraw()

func reset_view() -> void:
	_zoom = 1.0
	_pan = Vector2.ZERO
	queue_redraw()

## Jump the displayed view straight to the target (tests, first open, captures).
func snap_view() -> void:
	_view_zoom = _zoom
	_view_pan = _pan
	queue_redraw()

## Glide to a world position at `zoom_level`: that point ends centred in the map.
func focus_on_world(world_pos: Vector3, zoom_level: float = 3.0) -> void:
	if _dirty:
		_rebuild()
	if _fit.is_empty():
		return
	var base_point := MapRoads.world_to_screen(world_pos, _fit)
	_zoom = clampf(zoom_level, MIN_ZOOM, MAX_ZOOM)
	_pan = _clamp_pan(_zoom * (size * 0.5 - base_point), _zoom)
	queue_redraw()

func focus_on_player(zoom_level: float = 3.0) -> void:
	var car := VehicleManager.get_player_car()
	if car != null:
		focus_on_world(car.global_position, zoom_level)

## Focus a registered POI by id (unknown ids are ignored).
func focus_on_poi(poi_id: String, zoom_level: float = 3.5) -> void:
	if not POIRegistry.has_poi(poi_id):
		return
	focus_on_world(POIRegistry.get_poi(poi_id).get("position", Vector3.ZERO) as Vector3, zoom_level)

## Chase the target view. True while the displayed view still moves.
func _advance_view(delta: float) -> bool:
	var dz := _zoom - _view_zoom
	var dp := _pan - _view_pan
	if absf(dz) < 0.0005 and dp.length() < 0.2:
		if _view_zoom == _zoom and _view_pan == _pan:
			return false
		_view_zoom = _zoom
		_view_pan = _pan
		return true
	var k := 1.0 - exp(-VIEW_SMOOTHING * maxf(delta, 0.0))
	_view_zoom += dz * k
	_view_pan += dp * k
	return true

func _pan_with_stick(delta: float) -> void:
	if _zoom <= 1.0:
		return
	var axis := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if axis.length() < 0.25:
		return
	pan_by(-axis * 720.0 * delta)

# ---------------------------------------------------------------------------
# Draw
# ---------------------------------------------------------------------------

func _draw() -> void:
	if _dirty:
		_rebuild()
	if _fit.is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), MapStyle.OCEAN_DEEP)
		return
	var xf := _view_xform(_view_zoom, _view_pan)
	var terrain_on := _sync_terrain_layer(xf)
	# The shader layer draws BEHIND this control, so the flat ocean fill is only
	# laid down when there is no relief (it would cover the layer otherwise).
	if not terrain_on:
		draw_rect(Rect2(Vector2.ZERO, size), MapStyle.OCEAN_DEEP)
	if not terrain_on and not _terrain_waiting_for_relief():
		# No shader relief (no baked image: a headless gate, a stubbed reader):
		# keep the legacy cell grid so the map still reads as terrain.
		draw_set_transform_matrix(xf)
		for cell in _terrain_cells:
			draw_rect(cell["rect"], cell["color"], true)
		draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_roads(xf)
	if _route_path.size() >= 2:
		MapStyle.draw_route_ribbon(self, xf * _route_path, ROUTE_COLOR, 4.5, _pulse_time)
		if _has_route_goal:
			MapStyle.draw_destination(self, xf * _route_goal_screen, ROUTE_COLOR, 11.0)
	_draw_vignette()
	_draw_region_labels(xf)
	_draw_road_labels(xf)
	_draw_pois(xf)
	# Live rival blips: read from the CURRENT roster on every pass (never cached
	# with the content above), drawn under the player marker so the player still
	# reads as the most obvious object on the map.
	for entry in rival_blips():
		var blip: Dictionary = entry
		var screen: Vector2 = xf * (blip["screen"] as Vector2)
		MapRoads.draw_rival_blip(self, screen, float(blip["angle"]), MapRoads.RIVAL_SIZE * 1.5)
	if _has_player:
		_draw_player(xf * _player_screen)
	_draw_hover_card()
	_draw_overlay_ui()
	draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 2.0)

## True while a worker bake is running and there is nothing but the ocean to draw.
func _terrain_waiting_for_relief() -> bool:
	return _terrain_rect.size.x > 0.0 and MapTerrain.is_pending()

## Point the shader layer at the current displayed view. Visible only when the
## shared relief for THIS map's world rect is baked.
func _sync_terrain_layer(xf: Transform2D) -> bool:
	if _terrain_layer == null:
		return false
	var ok := _terrain_rect.size.x > 0.0 and MapTerrain.is_ready() and MapTerrain.rect() == _terrain_rect
	_terrain_layer.visible = ok
	if not ok:
		return false
	var base_origin := xf.affine_inverse() * Vector2.ZERO
	var fit_scale := float(_fit["scale"])
	var world_min: Vector2 = _fit["world_min"]
	var fit_origin: Vector2 = _fit["origin"]
	var view_world_min := world_min + (base_origin - fit_origin) / fit_scale
	MapTerrain.apply_view(_terrain_mat, size, view_world_min, fit_scale * _view_zoom,
		0.0, 1.0, 1.0, 1.0)
	return true

## Roads in two passes (all casings, then all cores) so a crossing never gets a
## dark seam cut through it, drawn lowest class first so highways ride on top.
## Widths grow gently with zoom but are compensated for the canvas scale.
func _draw_roads(xf: Transform2D) -> void:
	var z := _view_zoom
	var grow := (1.0 + 0.22 * (z - 1.0)) / z
	draw_set_transform_matrix(xf)
	for pass_index in 2:
		for run in _road_runs:
			var tier := int(run["tier"])
			var visited := bool(run["visited"])
			var pts: PackedVector2Array = run["pts"]
			if pts.size() < 2:
				continue
			var width := MapStyle.road_width(tier) * grow
			if pass_index == 0:
				draw_polyline(pts, MapStyle.road_casing(tier, visited), width + 2.6 * grow, true)
			else:
				draw_polyline(pts, MapStyle.road_core(tier, visited), width, true)
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_vignette() -> void:
	if _vignette_tex == null:
		_vignette_tex = ImageTexture.create_from_image(MapStyle.make_vignette_image(128, 0.55, VIGNETTE_STRENGTH))
	draw_texture_rect(_vignette_tex, Rect2(Vector2.ZERO, size), false)

## The player: a pulsing beacon (so the eye finds it across the whole island), then
## the shared white-and-cyan chevron at pause-map size.
func _draw_player(at: Vector2) -> void:
	var pulse := 0.5 + 0.5 * sin(TAU * _pulse_time / MapRoads.MARKER_PULSE_PERIOD)
	var beacon := MARKER_SIZE * (1.9 + 0.9 * pulse)
	var accent := MapRoads.MARKER_ACCENT
	draw_circle(at, beacon, Color(accent.r, accent.g, accent.b, 0.10 + 0.08 * (1.0 - pulse)))
	draw_arc(at, beacon, 0.0, TAU, 48, Color(1, 1, 1, 0.55 * (1.0 - pulse) + 0.15), 2.0, true)
	draw_circle(at, MARKER_SIZE * 1.25, Color(0.0, 0.0, 0.0, 0.35))
	MapRoads.draw_player_marker(self, at, _player_angle, _pulse_time, MARKER_SIZE)

## The live rival blips in screen space ({"screen": Vector2, "angle": float}),
## recomputed from the CURRENT roster on every draw pass: the fit is cached, the
## cars are not. Public so the headless gate can assert the projection (same
## world_to_screen as the roads), the heading angle and the empty-roster skip
## without a render pass. No fit yet, no roster, or show_rivals off => [].
func rival_blips() -> Array:
	var out: Array = []
	if not show_rivals or _fit.is_empty():
		return out
	for entry in MapRoads.rival_entries(MapRoads.live_rivals(rival_source)):
		var world_pos: Vector3 = entry["position"]
		out.append({
			"screen": MapRoads.world_to_screen(world_pos, _fit),
			"angle": MapRoads.marker_world_angle(entry["facing"] as Vector3),
		})
	return out

## Cheap "did any rival move" signature: roster size plus each blip's
## metre-rounded XZ, the same trick MapRoads.signature() uses for roads. Rounding
## to whole metres is what keeps a parked field from re-queueing the full cached
## terrain draw every frame while a moving one still updates immediately.
func _roster_signature() -> String:
	var parts := PackedStringArray()
	var cars := MapRoads.live_rivals(rival_source)
	parts.append(str(cars.size()))
	for entry in MapRoads.rival_entries(cars):
		var p: Vector3 = entry["position"]
		parts.append("%d,%d" % [roundi(p.x), roundi(p.z)])
	return "|".join(parts)

## Draws the placed road names (see place_road_labels). Each name is centred on
## its own road, rotated to that road's screen angle so the text follows the
## line, and tinted by whether the road under it is revealed -- an unexplored
## road is named, not stamped as driven. The outline is the road casing colour,
## which is what keeps a name readable over snow, water and the highway ring.
## Positions go through the view transform; the glyphs themselves stay at their
## native size, so zooming never blurs or inflates the text. The canvas transform
## is reset afterwards, so the pins and the player marker that draw later are
## unaffected.
func _draw_road_labels(xf: Transform2D = Transform2D.IDENTITY) -> void:
	var font := _label_font()
	if font == null:
		return
	var bounds := Rect2(Vector2(-40.0, -40.0), size + Vector2(80.0, 80.0))
	for entry in _road_labels:
		var label: Dictionary = entry
		var text: String = label["text"]
		var text_size := label_text_size(font, text)
		if not _is_measurable(text_size):
			continue
		var color: Color = ROAD_LABEL_COLOR if bool(label["revealed"]) else UNVISITED_ROAD_LABEL_COLOR
		var at: Vector2 = xf * (label["screen"] as Vector2)
		if not bounds.has_point(at):
			continue
		# The draw origin is the BASELINE left, so the box centre plus the ascent
		# is what puts the glyphs in the middle of their own collision box.
		var origin := Vector2(-text_size.x * 0.5,
			-text_size.y * 0.5 + font.get_ascent(ROAD_LABEL_FONT_SIZE))
		draw_set_transform(at, float(label["angle"]), Vector2.ONE)
		draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			ROAD_LABEL_FONT_SIZE, 5, ROAD_LABEL_OUTLINE)
		draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			ROAD_LABEL_FONT_SIZE, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Region captions: each named stage (Festival Plains, Alpine Overlook, ...) as a
## big letter-spaced uppercase caption above its landmark, the way FH names its
## biomes on the map. Derived from the landmark POIs, so a new stage reaches the map
## with no UI change. Base-fit coordinates; the view transform is applied at draw.
func region_labels() -> Array:
	return _region_labels

func _compute_region_labels() -> Array:
	var out: Array = []
	var seen := {}
	for poi_id: String in POIRegistry.get_poi_ids():
		var poi := POIRegistry.get_poi(poi_id)
		if poi.has("kind") or Collectibles.is_collectible_id(poi_id):
			continue
		var stage := str(poi.get("stage", "")).strip_edges()
		if stage.is_empty() or seen.has(stage):
			continue
		seen[stage] = true
		out.append({
			"text": stage.to_upper(),
			"screen": MapRoads.world_to_screen(poi.get("position", Vector3.ZERO) as Vector3, _fit),
		})
	return out

func _draw_region_labels(xf: Transform2D) -> void:
	var font := _label_font()
	if font == null:
		return
	var bounds := Rect2(Vector2(-80.0, -40.0), size + Vector2(160.0, 80.0))
	var font_size := REGION_LABEL_SIZE + int(roundf(minf(_view_zoom - 1.0, 3.0) * 1.5))
	for entry in _region_labels:
		var at: Vector2 = xf * (entry["screen"] as Vector2) + Vector2(0.0, -36.0 - 4.0 * minf(_view_zoom, 3.0))
		if not bounds.has_point(at):
			continue
		MapStyle.draw_spaced_label(self, font, str(entry["text"]), at, font_size,
			Color(1.0, 1.0, 1.0, 0.82), REGION_LABEL_TRACKING, Color(0.02, 0.05, 0.10, 0.65))

## Layer a POI draws on: collectibles under events under landmarks.
func _poi_layer(poi: Dictionary) -> int:
	if _is_collectible_poi(poi):
		return 0
	if poi.has("kind"):
		return 1
	return 2

## Badge radius (px, at the current zoom) of a POI's pin.
func poi_badge_radius(poi: Dictionary, zoom_value: float = 1.0) -> float:
	var base := BADGE_COLLECTIBLE
	match _poi_layer(poi):
		1:
			base = BADGE_EVENT
		2:
			base = BADGE_LANDMARK
	return base * (1.0 + BADGE_ZOOM_GROWTH * minf(zoom_value - 1.0, 3.0))

func _draw_pois(xf: Transform2D) -> void:
	var bounds := Rect2(Vector2(-30.0, -30.0), size + Vector2(60.0, 60.0))
	for layer in 3:
		for entry in _poi_entries:
			var poi: Dictionary = entry["poi"]
			if _poi_layer(poi) != layer:
				continue
			var at: Vector2 = xf * (entry["screen"] as Vector2)
			if bounds.has_point(at):
				_draw_poi(at, poi)

## Draws a POI as a bold FH-style badge: white ring, family-coloured fill and an
## event-type glyph (chequered flag, duel chevrons, drift S, radar, camera, ...),
## so a pin never depends on colour alone. A landmark is the biggest, an event the
## next size, a collectible the smallest.
##
## A claimed collectible (AAA-16) keeps its badge but drops its brightness: the
## fill is the dimmed family tint, the ring is the muted tint and the glyph fades,
## so banked and un-banked collectibles read apart straight off the map.
func _draw_poi(screen: Vector2, poi: Dictionary) -> void:
	var claimed := _is_claimed_collectible(poi)
	var radius := poi_badge_radius(poi, _view_zoom)
	var hovered := str(poi.get("id", "")) == _hover_poi_id and not _hover_poi_id.is_empty()
	if hovered:
		radius += 2.5
	var ring := POI_CLAIMED_TINT if claimed else MapStyle.PIN_RING
	var glyph_color := Color(1, 1, 1, 0.55) if claimed else Color.WHITE
	MapStyle.draw_badge(self, screen, radius, poi_dot_color(poi), MapStyle.poi_glyph(poi), glyph_color, ring)
	if hovered:
		draw_arc(screen, radius + 5.0, 0.0, TAU, 32, Color(1, 1, 1, 0.8), 1.6, true)

## The id of the POI pin under a control-local `view_pos`, "" when none. Reads the
## TARGET view (the one clicks use) and prefers the bigger pin where two overlap.
func poi_at(view_pos: Vector2) -> String:
	var best := ""
	var best_score := INF
	for entry in _poi_entries:
		var poi: Dictionary = entry["poi"]
		var at := base_to_view(entry["screen"] as Vector2)
		var reach := maxf(HOVER_RADIUS_PX, poi_badge_radius(poi, _zoom) + 4.0)
		var d := at.distance_to(view_pos)
		if d > reach:
			continue
		var score := d - float(_poi_layer(poi)) * 3.0
		if score < best_score:
			best_score = score
			best = str(poi.get("id", ""))
	return best

## Human type of a POI for the hover card ("Speed Trap", "Touge Duel", "Landmark").
func poi_type_label(poi: Dictionary) -> String:
	var kind := str(poi.get("kind", ""))
	if Collectibles.KIND_LABEL.has(kind):
		return str(Collectibles.KIND_LABEL[kind])
	if poi.has("kind"):
		return str(MapStyle.event_style(kind)["label"])
	return str(MapStyle.LANDMARK_STYLE["label"])

func _draw_hover_card() -> void:
	if _hover_poi_id.is_empty():
		return
	var font := _label_font()
	if font == null:
		return
	for entry in _poi_entries:
		var poi: Dictionary = entry["poi"]
		if str(poi.get("id", "")) != _hover_poi_id:
			continue
		var at := base_to_view(entry["screen"] as Vector2)
		var radius := poi_badge_radius(poi, _zoom)
		var text := "%s  -  %s" % [str(poi.get("name", _hover_poi_id)), poi_type_label(poi)]
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 14.0
		var anchor := at + Vector2(radius + 8.0, 0.0)
		if anchor.x + width > size.x - 8.0:
			anchor.x = at.x - radius - 8.0 - width
		MapStyle.draw_pill_label(self, font, text, anchor, 14)
		return

# ---------------------------------------------------------------------------
# Legend, compass, controls hint (screen-fixed overlay).
# ---------------------------------------------------------------------------

## The legend rows, in draw order: two columns, pins on the left and line work
## on the right. Public so the gate can assert the legend covers every pin family
## the map can draw and every road class.
func legend_entries() -> Array:
	return [
		{"col": 0, "kind": "pin", "label": "Landmark", "glyph": "star", "color": MapStyle.LANDMARK_STYLE["color"]},
		{"col": 0, "kind": "pin", "label": "Race event", "glyph": "flag", "color": MapStyle.event_color("touge_duel")},
		{"col": 0, "kind": "pin", "label": "Bonus board", "glyph": "board", "color": Collectibles.kind_color(Collectibles.KIND_BONUS, POI_COLOR)},
		{"col": 0, "kind": "pin", "label": "Speed trap", "glyph": "radar", "color": Collectibles.kind_color(Collectibles.KIND_SPEED_TRAP, POI_COLOR)},
		{"col": 0, "kind": "pin", "label": "Photo spot", "glyph": "camera", "color": Collectibles.kind_color(Collectibles.KIND_PHOTO, POI_COLOR)},
		{"col": 0, "kind": "player", "label": "You", "glyph": "", "color": MapRoads.MARKER_ACCENT},
		{"col": 1, "kind": "road", "label": "Highway", "tier": RoadDef.Tier.HIGHWAY, "visited": true},
		{"col": 1, "kind": "road", "label": "Main road", "tier": RoadDef.Tier.ARTERIAL, "visited": true},
		{"col": 1, "kind": "road", "label": "Mountain road", "tier": RoadDef.Tier.TOUGE, "visited": true},
		{"col": 1, "kind": "road", "label": "Dirt track", "tier": RoadDef.Tier.DIRT, "visited": true},
		{"col": 1, "kind": "road", "label": "Unexplored", "tier": RoadDef.Tier.ARTERIAL, "visited": false},
		{"col": 1, "kind": "route", "label": "GPS route", "glyph": "", "color": ROUTE_COLOR},
	]

const LEGEND_ROW_H := 23.0
const LEGEND_COL_W := 142.0
const LEGEND_PAD := 11.0

func _draw_overlay_ui() -> void:
	var font := _label_font()
	if font == null:
		return
	# Legend panel.
	var entries := legend_entries()
	var rows := [0, 0]
	for entry in entries:
		rows[int(entry["col"])] += 1
	var panel_h := float(maxi(rows[0], rows[1])) * LEGEND_ROW_H + LEGEND_PAD * 2.0 - 4.0
	var panel := Rect2(Vector2(14.0, size.y - panel_h - 14.0), Vector2(LEGEND_COL_W * 2.0 + LEGEND_PAD * 2.0 - 8.0, panel_h))
	var box := StyleBoxFlat.new()
	box.bg_color = MapStyle.PANEL_DARK
	box.border_color = MapStyle.PANEL_EDGE
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	draw_style_box(box, panel)
	var row_index := [0, 0]
	for entry in entries:
		var col := int(entry["col"])
		var y := panel.position.y + LEGEND_PAD + float(row_index[col]) * LEGEND_ROW_H + LEGEND_ROW_H * 0.5 - 2.0
		row_index[col] += 1
		var x := panel.position.x + LEGEND_PAD + float(col) * LEGEND_COL_W
		_draw_legend_row(font, entry, Vector2(x, y))
	# Compass, top-right.
	var c := Vector2(size.x - 40.0, 40.0)
	draw_circle(c, 22.0, MapStyle.PANEL_DARK)
	draw_arc(c, 22.0, 0.0, TAU, 32, MapStyle.PANEL_EDGE, 1.2, true)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, -17.0), c + Vector2(-5.0, 2.0), c + Vector2(5.0, 2.0)]), Color(0.96, 0.32, 0.30))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, 17.0), c + Vector2(-5.0, 2.0), c + Vector2(5.0, 2.0)]), Color(0.86, 0.90, 0.96, 0.8))
	draw_string(font, c + Vector2(-4.5, -26.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MapStyle.TEXT_LIGHT)
	# Controls hint, bottom-right.
	var hint := "SCROLL zoom    DRAG pan    CLICK fast travel    RIGHT-CLICK set GPS"
	var hint_w := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string_outline(font, Vector2(size.x - hint_w - 18.0, size.y - 16.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.6))
	draw_string(font, Vector2(size.x - hint_w - 18.0, size.y - 16.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MapStyle.TEXT_DIM)

func _draw_legend_row(font: Font, entry: Dictionary, at: Vector2) -> void:
	var text_x := at.x + 30.0
	match str(entry["kind"]):
		"pin":
			MapStyle.draw_badge(self, at + Vector2(9.0, 0.0), 7.0, entry["color"], str(entry["glyph"]))
		"player":
			MapRoads.draw_player_marker(self, at + Vector2(9.0, 0.0), -PI / 2.0, 0.0, 7.5)
		"road":
			var tier := int(entry["tier"])
			var visited := bool(entry["visited"])
			var line := PackedVector2Array([at + Vector2(-1.0, 3.0), at + Vector2(19.0, -3.0)])
			draw_polyline(line, MapStyle.road_casing(tier, visited), MapStyle.road_width(tier) + 2.6, true)
			draw_polyline(line, MapStyle.road_core(tier, visited), MapStyle.road_width(tier), true)
		"route":
			MapStyle.draw_route_ribbon(self, PackedVector2Array([at + Vector2(-1.0, 3.0), at + Vector2(19.0, -3.0)]), entry["color"], 3.0, 0.0)
	draw_string(font, Vector2(text_x, at.y + 5.0), str(entry["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MapStyle.TEXT_LIGHT)

## True for a collectible entry (bonus board / speed trap / photo spot): the
## three families that are permanent gameplay rather than a place to visit, so
## they carry the family palette, the larger hollow pin and the claimed dimming.
## Base landmarks and event markers return false and keep the zone/tier fill.
func _is_collectible_poi(poi: Dictionary) -> bool:
	return Collectibles.is_collectible_id(str(poi.get("id", "")))

## The exact fill colour a POI dot draws with, claim state included. Public so
## the headless gate can assert the map's per-family colour contract (a speed
## trap is the shared red; a banked one is the dimmed tint) without a render
## pass, and so _draw_poi has a single source for "what colour is this dot".
func poi_dot_color(poi: Dictionary) -> Color:
	var fill := _poi_fill_color(poi)
	if not _is_claimed_collectible(poi):
		return fill
	return fill.lerp(POI_CLAIMED_TINT, POI_CLAIMED_MIX)

## Ids of the POIs in the current dot set, in draw order. Public so the gate can
## assert the map really carries (say) speedtrap_0 without reaching into the
## cached _poi_entries.
func poi_entry_ids() -> Array[String]:
	var out: Array[String] = []
	for entry in _poi_entries:
		var poi: Dictionary = (entry as Dictionary)["poi"]
		out.append(str(poi.get("id", "")))
	return out

## True only for a collectible id the open-world CollectibleField has already
## paid. No field node (circuit scene, or headless with no world) => false, and
## base landmarks / event markers are never dimmed.
func _is_claimed_collectible(poi: Dictionary) -> bool:
	if not _is_collectible_poi(poi):
		return false
	return _collectible_source != null and _collectible_source.is_claimed(str(poi.get("id", "")))

## Zone-aware POI colour: base land- mark stages map to their region, event sites
## fall back to their road tier colour so they never blend into the terrain.
## Collectibles short-circuit to their FAMILY colour first: a speed trap on a
## touge must not come out road-blue just because the host corridor's tier colour
## is blue, which is exactly how a gameplay target disappears into the network.
func _poi_fill_color(poi: Dictionary) -> Color:
	if _is_collectible_poi(poi):
		return Collectibles.kind_color(str(poi.get("kind", "")), POI_COLOR)
	# An event marker takes its FAMILY colour (touge blue, drag red, drift violet...),
	# the same one its glyph and the legend use; a landmark keeps its stage colour.
	if poi.has("kind"):
		return MapStyle.event_color(str(poi.get("kind", "")))
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

# ---------------------------------------------------------------------------
# Road names: what to call a road, where to put the name, and which name wins
# the space when two roads converge.
# ---------------------------------------------------------------------------

## The name to print for `road_id`: the curated table when it has an entry, else
## a title-cased rendering of the id itself ("dirt-c" -> "Dirt C").
##
## This is the FALLBACK path. In the running game the primary source is the
## curated name on the RoadDef itself (RoadDef.name, from
## CorridorPlanner.ROAD_NAMES) -- see _road_label_candidates(), which prefers it.
## ROAD_LABELS still matters for roads whose defs carry no name (scene-authored
## or test-stubbed defs) and for nothing else; the table's seven entries are the
## same seven strings the planner now names those ids with, so the two paths agree
## and this table is what keeps them agreeing.
static func road_label(road_id: String) -> String:
	if ROAD_LABELS.has(road_id):
		return str(ROAD_LABELS[road_id])
	if road_id.is_empty():
		return "Unnamed Road"
	return _title_case(road_id)

## Title-case fallback rule: split on "-", capitalise each word, rejoin with
## single spaces. Its own function so the rule is one readable line instead of a
## loop buried inside a Dictionary lookup.
static func _title_case(road_id: String) -> String:
	var words := PackedStringArray()
	for part in road_id.split("-", false):
		words.append(part.substr(0, 1).to_upper() + part.substr(1))
	return " ".join(words)

## The font a map label is measured AND drawn with: the theme default, i.e. the
## engine fallback font unless the UI theme ships one. Null is a supported answer
## -- the map then places no labels at all rather than drawing unmeasured text.
func _label_font() -> Font:
	var font := get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	return font

## The single measurement used by BOTH the collision pass and the draw pass, so
## a placed box can never disagree with the glyphs it was sized for. A null font
## (or an empty name) measures as zero, which the placement pass reads as "cannot
## be placed" rather than as a zero-size box that collides with nothing.
static func label_text_size(font: Font, text: String) -> Vector2:
	if font == null or text.is_empty():
		return Vector2.ZERO
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, ROAD_LABEL_FONT_SIZE)

## Whether a measured size is usable for placement: finite and strictly positive
## on both axes.
static func _is_measurable(size: Vector2) -> bool:
	return is_finite(size.x) and is_finite(size.y) and size.x > 0.0 and size.y > 0.0

## Where a chain's name goes, computed once and used for both the draw and the
## collision box:
##   "screen"  - the ARC-LENGTH midpoint projected to screen (not the vertex
##               midpoint, so a densely sampled corner cannot drag a name into the
##               corner it happens to be sampled most often at)
##   "angle"   - the screen-space direction of the segment the midpoint is on
##   "segment" - that segment's index, so the caller can ask the discovery mask
##               whether the piece of road UNDER the name has been driven
##   "length"  - total XZ length, the greedy pass's priority key
## A chain of one point, or a chain whose vertices all sit on the same spot, has
## no direction and no length: the name is then unrotated at the first point
## instead of being thrown at an arbitrary angle.
static func chain_anchor(points: PackedVector3Array, fit: Dictionary) -> Dictionary:
	if points.is_empty():
		return {"screen": Vector2.ZERO, "angle": 0.0, "segment": 0, "length": 0.0}
	var first := MapRoads.world_to_screen(points[0], fit)
	if points.size() < 2:
		return {"screen": first, "angle": 0.0, "segment": 0, "length": 0.0}
	var steps: Array[float] = []
	var total := 0.0
	for i in range(1, points.size()):
		# XZ metres: Y is the terrain's business, not distance (same convention
		# as RoadNetwork.point_to_segment_xz).
		var step := Vector2(points[i].x - points[i - 1].x, points[i].z - points[i - 1].z).length()
		steps.append(step)
		total += step
	if total <= 0.0:
		return {"screen": first, "angle": 0.0, "segment": 0, "length": 0.0}
	var walked := 0.0
	for i in steps.size():
		var step: float = steps[i]
		if walked + step >= total * 0.5:
			var from_screen := MapRoads.world_to_screen(points[i], fit)
			var to_screen := MapRoads.world_to_screen(points[i + 1], fit)
			var t := 0.0 if step <= 0.0 else (total * 0.5 - walked) / step
			return {
				"screen": from_screen.lerp(to_screen, clampf(t, 0.0, 1.0)),
				"angle": (to_screen - from_screen).angle(),
				"segment": i,
				"length": total,
			}
		walked += step
	return {"screen": first, "angle": 0.0, "segment": 0, "length": total}

## Fold any screen angle into [-90, 90) degrees so a name is never drawn
## upside-down: a road running right-to-left is labelled along its own line with
## the text reversed, not turned over.
static func _upright_angle(angle: float) -> float:
	return fposmod(angle + PI * 0.5, PI) - PI * 0.5

## The axis-aligned box a label of `text_size`, centred on `center` and rotated
## by `angle`, actually covers. Rotating grows each axis by the other's extent,
## so this is exact -- the unrotated box would let two long names on crossing
## roads pass the collision test and then overlap on screen.
static func label_box(center: Vector2, text_size: Vector2, angle: float,
		padding: float = ROAD_LABEL_PADDING) -> Rect2:
	var half := text_size * 0.5
	var cos_a := absf(cos(angle))
	var sin_a := absf(sin(angle))
	var extent := Vector2(cos_a * half.x + sin_a * half.y,
		sin_a * half.x + cos_a * half.y) + Vector2.ONE * padding
	return Rect2(center - extent, extent * 2.0)

## The road names to draw, resolved headlessly from world-space geometry.
##
## `roads` and `road_ids` are index-parallel (MapRoads.get_roads /
## get_road_ids), `fit` is a compute_fit() dictionary, `measure` is a
## Callable(String) -> Vector2 and `revealed` a
## Callable(int road_index, int segment) -> bool. Both callables are injected so
## the placement rules are testable with no canvas, no theme and no font -- and
## so this function never has to know what a WorldDiscovery is.
##
## Greedy, one pass: candidates are ordered by CURATED MAJOR first, then by chain
## length (ties by chain index, so the result is stable for a given network), and
## each name is placed only if its box fits inside `rect` and clears every box
## already placed. Dropping a name is the correct outcome where roads converge --
## readable labels beat overlapping ones. The two-tier order matters now that all
## nineteen roads are candidates: ranking on length alone handed the compact
## Mountain Pass Loop's slot to a long access ramp, which is precisely backwards,
## so the seven majors keep the claim they had when they were the only candidates.
##
## Returns one entry per placed name: {"id", "text", "screen", "angle", "box",
## "revealed", "index", "length"}. Empty when there is nothing to name.
##
## `road_names` is optional and index-aligned with `roads` exactly like
## `road_ids` (MapRoads.get_road_names): where it has a non-empty entry that
## curated name wins, otherwise the text falls back to road_label(road_id). Pass
## [] to get the pure id-derived naming.
static func place_road_labels(roads: Array, road_ids: Array, fit: Dictionary,
		measure: Callable, rect: Rect2, revealed: Callable = Callable(),
		road_names: Array = []) -> Array:
	if fit.is_empty() or not measure.is_valid():
		return []
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return []
	var candidates: Array = []
	for index in roads.size():
		if index >= road_ids.size():
			break
		var road_id := str(road_ids[index])
		var points := _chain_points(roads[index])
		# A chain of one point is not a road: there is no length to order it by
		# and no direction to align a name to.
		if points.size() < 2:
			continue
		# Curated RoadDef.name first, id-derived fallback second. Every planned
		# corridor is named now, so the fallback only serves scene-authored or
		# stubbed defs that leave `name` empty.
		var text := road_label(road_id)
		if index < road_names.size():
			var curated := str(road_names[index])
			if not curated.is_empty():
				text = curated
		var text_size: Vector2 = measure.call(text)
		if not _is_measurable(text_size):
			continue
		var anchor := chain_anchor(points, fit)
		var center: Vector2 = anchor["screen"]
		var angle := _upright_angle(float(anchor["angle"]))
		candidates.append({
			"index": index,
			"id": road_id,
			# Curated majors (ROAD_LABELS) claim space BEFORE the twelve roads that
			# joined the candidate pool later. Ranking purely on length let a long
			# access ramp outrank the compact Mountain Pass Loop, which is the one
			# name a player most needs on the pass approach -- so the original
			# "majors first" intent is now an explicit sort key instead of an
			# accident of the whitelist being the only candidate list.
			"curated": MAJOR_ROAD_IDS.has(road_id),
			"text": text,
			"screen": center,
			"angle": angle,
			"box": label_box(center, text_size, angle),
			"length": float(anchor["length"]),
			"revealed": true if not revealed.is_valid()
				else bool(revealed.call(index, int(anchor["segment"]))),
		})
	candidates.sort_custom(func(a, b):
		# Curated majors first (see the "curated" key), then longest road, then
		# stable index order. The length tiebreak is what used to decide
		# everything on its own.
		var cur_a := bool(a["curated"])
		var cur_b := bool(b["curated"])
		if cur_a != cur_b:
			return cur_a
		var len_a := float(a["length"])
		var len_b := float(b["length"])
		if not is_equal_approx(len_a, len_b):
			return len_a > len_b
		return int(a["index"]) < int(b["index"]))
	var margin := minf(ROAD_LABEL_EDGE_MARGIN, minf(rect.size.x, rect.size.y) * 0.25)
	var bounds := rect.grow(-margin)
	var placed: Array = []
	var boxes: Array = []
	for candidate in candidates:
		var entry: Dictionary = candidate
		var box: Rect2 = entry["box"]
		if not bounds.encloses(box):
			continue
		var collides := false
		for taken in boxes:
			if (taken as Rect2).intersects(box):
				collides = true
				break
		if collides:
			continue
		placed.append(entry)
		boxes.append(box)
	return placed

## A chain as a flat PackedVector3Array, skipping anything that is not a point.
## A RoadNetwork chain is typed Array[Vector3] so this is a copy; a duck-typed
## source feeding garbage gets a shorter polyline rather than a cast error.
static func _chain_points(chain: Variant) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not (chain is Array):
		return out
	for entry in (chain as Array):
		if entry is Vector3:
			var point: Vector3 = entry
			out.append(point)
	return out

## The placed road labels for this rebuild, or [] when the gate is off. All the
## placement work is the static pass above; the map only supplies the two things
## that need a live node: the font that measures a name and the discovery mask
## that says whether the road under it has been driven.
func _place_road_labels(roads: Array, road_ids: Array, draw_size: Vector2,
		road_names: Array = []) -> Array:
	var font := _label_font()
	if font == null:
		return []
	var measure := func(text: String) -> Vector2:
		return label_text_size(font, text)
	var revealed := func(road_index: int, segment: int) -> bool:
		return _is_road_revealed(road_index, segment)
	return place_road_labels(roads, road_ids, _fit, measure,
		Rect2(Vector2.ZERO, draw_size), revealed, road_names)

## Whether the piece of road `segment` of chain `road_index` has been driven. No
## discovery source, an unknown road, or a mask that does not cover that segment
## all read as revealed -- the same fallback the road draw pass uses, so a name
## is never dimmer than the line under it.
func _is_road_revealed(road_index: int, segment: int) -> bool:
	if _discovery_source == null or segment < 0:
		return true
	var mask: Array[bool] = _discovery_source.segment_visited_mask(road_index)
	if mask.is_empty() or segment >= mask.size():
		return true
	return mask[segment]

## The road ids this rebuild actually managed to name, in draw order. Public so
## the headless gate can assert the label set -- and the gate behind it -- without
## reaching into the cached entries.
func road_label_ids() -> Array[String]:
	var out: Array[String] = []
	for entry in _road_labels:
		var label: Dictionary = entry
		out.append(str(label["id"]))
	return out

## The label strings this rebuild actually drew, in draw order. Public so the
## headless gate can assert WHICH name reached the map -- road_label_ids() only
## says which roads were named, and the whole point of curated RoadDef.name is
## that the drawn text is the curated one ("Spawn On-Ramp"), not an id-derived
## guess.
func road_label_texts() -> Array[String]:
	var out: Array[String] = []
	for entry in _road_labels:
		var label: Dictionary = entry
		out.append(str(label["text"]))
	return out

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
	_collectible_source = _resolve_collectible_field()

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
	# Smooth shader relief: only for a REAL world terrain source. An injected
	# `height_provider` (tests) keeps the legacy cell grid, so a stubbed field can
	# never leak into the shared, cached relief image.
	_terrain_rect = Rect2()
	_terrain_waiting = false
	if provider.is_valid() and not height_provider.is_valid():
		_terrain_rect = MapTerrain.world_rect_for_roads(roads)
		MapTerrain.request(_terrain_rect)
		_terrain_waiting = not MapTerrain.poll()
	_paths = []
	_grey_paths = []
	_road_runs = []
	_road_labels = []
	var tiers := MapRoads.get_road_tiers(source)
	for road_index in roads.size():
		var chain: Array = roads[road_index]
		var tier := int(tiers[road_index]) if road_index < tiers.size() else MapRoads.UNKNOWN_TIER
		var screens := PackedVector2Array()
		for p in chain:
			screens.append(MapRoads.world_to_screen(p, _fit))
		var mask: Array[bool] = []
		if _discovery_source != null:
			mask = _discovery_source.segment_visited_mask(road_index)
		if mask.is_empty() or (mask.size() != chain.size() - 1 and mask.size() != chain.size()):
			# No usable discovery data: draw the whole chain as one visited path.
			if screens.size() >= 2:
				_add_road_run(screens, tier, true)
			continue
		# Consecutive segments in the same reveal state merge into ONE polyline, so
		# a road is a continuous ribbon (joined corners) and not a string of
		# butt-capped two-point sticks with a gap at every vertex.
		var run := PackedVector2Array()
		var run_state := mask[0]
		for seg in mask.size():
			var seg_next := seg + 1
			if seg_next >= screens.size():
				seg_next = 0  # closing segment on a closed chain
			if mask[seg] != run_state and run.size() >= 2:
				_add_road_run(run, tier, run_state)
				run = PackedVector2Array()
				run_state = mask[seg]
			if run.is_empty():
				run.append(screens[seg])
			run.append(screens[seg_next])
		if run.size() >= 2:
			_add_road_run(run, tier, run_state)
	_road_runs.sort_custom(func(a, b):
		# Unexplored under explored, then low class under high class.
		if bool(a["visited"]) != bool(b["visited"]):
			return not bool(a["visited"])
		return MapStyle.road_rank(int(a["tier"])) < MapStyle.road_rank(int(b["tier"])))
	# Road NAMES, same pass: the ids AND the curated names come from the same
	# source in the same order as the chains (both index-aligned with `roads`, so
	# the discovery mask indexed by road_index above is the one the label tints
	# read). Names come from RoadDef.name via MapRoads.get_road_names, so every
	# planned corridor is a candidate -- not just the old seven majors -- and the
	# greedy pass in place_road_labels() decides which actually fit. Cached like
	# the rest, so labels appear on open and on resize without any per-frame work.
	if show_road_labels:
		_road_labels = _place_road_labels(roads, MapRoads.get_road_ids(source), size,
			MapRoads.get_road_names(source))
	_route_path = PackedVector2Array()
	if MapRoads.has_route and with_world:
		var route := MapRoads.route_polyline(source, player_pos, MapRoads.route_target)
		var route_pts := PackedVector2Array()
		for p in route:
			route_pts.append(MapRoads.world_to_screen(p, _fit))
		if route_pts.size() >= 2:
			_route_path = route_pts
	_has_route_goal = MapRoads.has_route and with_world and _route_path.size() >= 2
	_route_goal_screen = MapRoads.world_to_screen(MapRoads.route_target, _fit) if _has_route_goal else Vector2.ZERO
	_region_labels = _compute_region_labels() if with_world else []
	_poi_entries = []
	for i in raw_pois.size():
		_poi_entries.append({
			"screen": MapRoads.world_to_screen(raw_pois[i], _fit),
			"poi": raw_poi_dicts[i],
		})
	_player_screen = MapRoads.world_to_screen(player_pos, _fit) if _has_player else Vector2.ZERO

## One merged polyline of a road, in base-fit px, with its class and reveal
## state. `_paths` / `_grey_paths` keep the legacy visited / unvisited split.
func _add_road_run(points: PackedVector2Array, tier: int, visited: bool) -> void:
	if visited:
		_paths.append(points)
	else:
		_grey_paths.append(points)
	_road_runs.append({"pts": points, "tier": tier, "visited": visited})

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

## Pause-map input. Wheel zooms about the cursor; a left drag pans; a left CLICK
## (press and release without crossing DRAG_THRESHOLD_PX) fast-travels to the
## clicked road point when the WorldDriver accepts it (the point must be on a
## revealed road); a right click sets the GPS destination (right-clicking the
## flag clears it). +/-/0 zoom and reset, F finds the player, the shoulders zoom.
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventKey:
		_on_key(event as InputEventKey)
	elif event is InputEventJoypadButton:
		var pad := event as InputEventJoypadButton
		if pad.pressed and pad.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			zoom_by(ZOOM_STEP, size * 0.5)
			get_viewport().set_input_as_handled()
		elif pad.pressed and pad.button_index == JOY_BUTTON_LEFT_SHOULDER:
			zoom_by(1.0 / ZOOM_STEP, size * 0.5)
			get_viewport().set_input_as_handled()

func _on_mouse_button(button: InputEventMouseButton) -> void:
	var rect := get_global_rect()
	if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
		var was_click := _pressing and not _dragged
		_pressing = false
		_dragged = false
		if was_click:
			_handle_map_click(button)
		return
	if not rect.has_point(button.position) or not button.pressed:
		return
	var local := button.position - rect.position
	match button.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			zoom_by(ZOOM_STEP, local)
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / ZOOM_STEP, local)
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_LEFT:
			_pressing = true
			_dragged = false
			_press_pos = local
		MOUSE_BUTTON_RIGHT:
			_handle_route_click(local)

func _on_mouse_motion(motion: InputEventMouseMotion) -> void:
	var rect := get_global_rect()
	var local := motion.position - rect.position
	if _pressing and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if not _dragged and local.distance_to(_press_pos) > DRAG_THRESHOLD_PX:
			_dragged = true
		if _dragged:
			pan_by(motion.relative)
			get_viewport().set_input_as_handled()
			return
	var hovered := poi_at(local) if rect.has_point(motion.position) else ""
	if hovered != _hover_poi_id:
		_hover_poi_id = hovered
		_hover_pos = local
		queue_redraw()

func _on_key(key: InputEventKey) -> void:
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			zoom_by(ZOOM_STEP, size * 0.5)
		KEY_MINUS, KEY_KP_SUBTRACT:
			zoom_by(1.0 / ZOOM_STEP, size * 0.5)
		KEY_0, KEY_KP_0:
			reset_view()
		KEY_F:
			focus_on_player()
		_:
			return
	get_viewport().set_input_as_handled()

func _handle_map_click(click: InputEventMouseButton) -> void:
	if not is_visible_in_tree() or _fit.is_empty():
		return
	var rect := get_global_rect()
	if not rect.has_point(click.position):
		return
	var world := MapRoads.screen_to_world(view_to_base(click.position - rect.position), _fit)
	_try_fast_travel(world)

## Right click: drop a GPS destination at the clicked point, or clear the route
## when the click lands on the destination flag itself.
func _handle_route_click(local: Vector2) -> void:
	if _fit.is_empty():
		return
	if _has_route_goal and base_to_view(_route_goal_screen).distance_to(local) <= 14.0:
		clear_route()
		return
	set_route_destination(MapRoads.screen_to_world(view_to_base(local), _fit))

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

## The open-world collectible runtime, resolved once per rebuild (the map only
## rebuilds on open / filter change) so dot dimming never walks the tree per dot.
func _resolve_collectible_field() -> CollectibleField:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group(CollectibleField.GROUP_NAME) as CollectibleField