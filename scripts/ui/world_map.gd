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
## Road names (the majors only -- see MAJOR_ROAD_IDS): each of the seven labelled
## roads gets its name drawn along its own line at the arc-length midpoint,
## tinted like the road it names so an unrevealed road is not stamped as driven,
## and placed greedily longest-first with a collision pass, because seven
## readable names beat seven overlapping ones. show_road_labels turns the whole
## layer off without touching the lines.

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

## Road NAMES on the pause map. The player asked for the majors only, so this is
## the seven planner ids a driver would actually name after the place they loop
## or connect: every CLOSED ring/loop (highway-ring, hub-ring, pass-loop,
## touge-a, touge-b) plus the two main CONNECTORS (hub-pass, hub-coast).
## Selection rule, for adding or dropping one: a road earns a label if it is a
## ring/loop or a district-to-district connector -- not if it is a ramp/merge
## stub onto another road, a dirt shortcut, or a dead-end coastal ribbon. The
## other twelve ids in the 19-road network stay anonymous, and this list is the
## only thing place_road_labels() ever offers to the greedy pass.
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
## Road names are their own gate for the same reason collectibles are: a player
## who wants the network clean can drop the text without losing the lines.
var show_road_labels: bool = true
var region_filter: String = ""
var _travel_gate: Callable = Callable()

## AAA-3 filter API: flags keys are "pois" / "landmarks" / "events" /
## "collectibles" / "travel" / "road_labels" (bools, the shipped all-on defaults)
## plus "region" (String substring on the POI's stage name, "" = any). Only the
## keys present are touched, so a partial update never silently resets another
## gate. Marks the map dirty and queues a redraw, so the dot set is rebuilt
## against the active gates on the next draw pass (headless gates call
## _rebuild() directly).
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
	_draw_road_labels()
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

## Draws the placed road names (see place_road_labels). Each name is centred on
## its own road, rotated to that road's screen angle so the text follows the
## line, and tinted by whether the road under it is revealed -- an unexplored
## road is named, not stamped as driven. The outline is the road casing colour,
## which is what keeps a name readable over snow, water and the highway ring.
## The canvas transform is reset afterwards, so the border and the player marker
## that draw later are unaffected.
func _draw_road_labels() -> void:
	var font := _label_font()
	if font == null:
		return
	for entry in _road_labels:
		var label: Dictionary = entry
		var text: String = label["text"]
		var text_size := label_text_size(font, text)
		if not _is_measurable(text_size):
			continue
		var color: Color = ROAD_LABEL_COLOR if bool(label["revealed"]) else UNVISITED_ROAD_LABEL_COLOR
		var at: Vector2 = label["screen"]
		# The draw origin is the BASELINE left, so the box centre plus the ascent
		# is what puts the glyphs in the middle of their own collision box.
		var origin := Vector2(-text_size.x * 0.5,
			-text_size.y * 0.5 + font.get_ascent(ROAD_LABEL_FONT_SIZE))
		draw_set_transform(at, float(label["angle"]), Vector2.ONE)
		draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			ROAD_LABEL_FONT_SIZE, 4, ROAD_LABEL_OUTLINE)
		draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			ROAD_LABEL_FONT_SIZE, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Draws a POI as a small satellite-style pin: dark outline ring around a
## zone/tier-coloured fill with a bright core, readable over any terrain tint.
## A claimed collectible (AAA-16) drops the bright core and fades, so banked and
## un-banked collectibles are distinguishable straight off the map.
##
## Collectibles get their own treatment: the family palette
## (Collectibles.KIND_DOT_COLOR) at COLLECTIBLE_RADIUS with a HOLLOW ring in
## place of the solid core, so a speed trap reads as a target to drive at rather
## than as one more landmark blob. A banked one keeps the ring in the dimmed
## claimed tint, so the spent state is still unmistakable.
func _draw_poi(screen: Vector2, poi: Dictionary) -> void:
	var collectible := _is_collectible_poi(poi)
	var claimed := _is_claimed_collectible(poi)
	var radius := COLLECTIBLE_RADIUS if collectible else POI_RADIUS
	draw_circle(screen, radius + 2.0, POI_OUTLINE)
	draw_circle(screen, radius, poi_dot_color(poi))
	if collectible:
		var ring := POI_CLAIMED_TINT if claimed else COLLECTIBLE_RING
		draw_arc(screen, maxf(radius - 2.6, 1.0), 0.0, TAU, 20, ring, COLLECTIBLE_RING_WIDTH, true)
		return
	if not claimed:
		draw_circle(screen, POI_RADIUS - 2.2, POI_CORE)

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
## a title-cased rendering of the id itself ("coast-a" -> "Coast A"). The
## fallback is what makes growing MAJOR_ROAD_IDS safe -- a newly promoted road
## reads as "Dirt A" until somebody names it properly, and never as a blank.
static func road_label(road_id: String) -> String:
	if ROAD_LABELS.has(road_id):
		return str(ROAD_LABELS[road_id])
	if road_id.is_empty():
		return "Unnamed Road"
	return _title_case(road_id)

## Whether `road_id` is one of the labelled majors (see MAJOR_ROAD_IDS).
static func is_major_road(road_id: String) -> bool:
	return MAJOR_ROAD_IDS.has(road_id)

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
## Greedy, one pass, longest road first: candidates are ordered by chain length
## (ties by chain index, so the result is stable for a given network) and each
## name is placed only if its box fits inside `rect` and clears every box already
## placed. Dropping a name is the correct outcome where roads converge -- seven
## readable labels beat seven overlapping ones -- and the big ring gets first
## claim on the space, which is the name a player most needs.
##
## Returns one entry per placed name: {"id", "text", "screen", "angle", "box",
## "revealed", "index", "length"}. Empty when there is nothing to name.
static func place_road_labels(roads: Array, road_ids: Array, fit: Dictionary,
		measure: Callable, rect: Rect2, revealed: Callable = Callable()) -> Array:
	if fit.is_empty() or not measure.is_valid():
		return []
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return []
	var candidates: Array = []
	for index in roads.size():
		if index >= road_ids.size():
			break
		var road_id := str(road_ids[index])
		if not is_major_road(road_id):
			continue
		var points := _chain_points(roads[index])
		# A chain of one point is not a road: there is no length to order it by
		# and no direction to align a name to.
		if points.size() < 2:
			continue
		var text := road_label(road_id)
		var text_size: Vector2 = measure.call(text)
		if not _is_measurable(text_size):
			continue
		var anchor := chain_anchor(points, fit)
		var center: Vector2 = anchor["screen"]
		var angle := _upright_angle(float(anchor["angle"]))
		candidates.append({
			"index": index,
			"id": road_id,
			"text": text,
			"screen": center,
			"angle": angle,
			"box": label_box(center, text_size, angle),
			"length": float(anchor["length"]),
			"revealed": true if not revealed.is_valid()
				else bool(revealed.call(index, int(anchor["segment"]))),
		})
	candidates.sort_custom(func(a, b):
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
func _place_road_labels(roads: Array, road_ids: Array, draw_size: Vector2) -> Array:
	var font := _label_font()
	if font == null:
		return []
	var measure := func(text: String) -> Vector2:
		return label_text_size(font, text)
	var revealed := func(road_index: int, segment: int) -> bool:
		return _is_road_revealed(road_index, segment)
	return place_road_labels(roads, road_ids, _fit, measure,
		Rect2(Vector2.ZERO, draw_size), revealed)

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
	_paths = []
	_grey_paths = []
	_road_labels = []
	for road_index in roads.size():
		var chain: Array = roads[road_index]
		var screens := PackedVector2Array()
		for p in chain:
			screens.append(MapRoads.world_to_screen(p, _fit))
		var mask: Array[bool] = []
		if _discovery_source != null:
			mask = _discovery_source.segment_visited_mask(road_index)
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
	# Road NAMES, same pass: the ids come from the same source in the same order
	# as the chains, so the discovery mask indexed by road_index above is the one
	# the label tints read. Cached like the rest, so labels appear on open and on
	# resize without any per-frame work.
	if show_road_labels:
		_road_labels = _place_road_labels(roads, MapRoads.get_road_ids(source), size)
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

## The open-world collectible runtime, resolved once per rebuild (the map only
## rebuilds on open / filter change) so dot dimming never walks the tree per dot.
func _resolve_collectible_field() -> CollectibleField:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group(CollectibleField.GROUP_NAME) as CollectibleField