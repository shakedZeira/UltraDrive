class_name TrackMap
extends Control

## The circuit-map Control for the race menu: an equirectangular world map with
## one clickable pin per TrackRegistry pin, framed by a region tier.
##
## The region's own presentation record (TrackRegistry.region_meta) chooses the
## backdrop and the graticule step:
##   backdrop "world"  -> the CC0 360x180 world SVG raster
##   backdrop "vector" -> the hand-authored vector Levant silhouette (ISRAEL)
## Pins, labels, hit-testing and the selection state are backdrop-agnostic: ONE
## projection (WorldMapProjection) and ONE pin layer serve every tier, so
## swapping the world tier for runtime-vector land later is an internal change
## to this script and nothing else.
##
## VIEW STATE: a scalar zoom in [MIN_ZOOM, MAX_ZOOM] plus a screen-space pan,
## applied by re-deriving the single fit Dictionary (`_fit`) that every read
## already goes through (pin_screen_position, hit_test, the backdrops, the
## graticule). Pan/zoom never touch WorldMapProjection or MapRoads. Region
## switch and resize both REBASE (zoom 1.0, pan zero).
##
## Labels are de-clumped by `select_label_ids()`: a DOT is drawn for EVERY
## visible pin, but the name only for a pairwise-separated subset (plus the
## selected/hovered pin, which is always named). At world scale the dense
## European cluster collapses into tens of px, so many labels drop BY DESIGN.
## Zooming spreads pins apart, so more labels auto-appear. The CARD LIST
## beside the map is the guaranteed, deterministic path to every circuit (and
## the info panel names the selection), so dropping a label never hides a track
## — do NOT "fix" this by shrinking the hit radius.
##
## Headless note: `_draw()` never runs under gdUnit, so every pin position is
## computed in `_update_projection()` (from `_ready()`/resize, plus lazily
## whenever `size` changed). Tests can therefore read pin positions and
## hit-test without a single draw pass.
##
## Dateline: no pin sits near +/-180, so no wrap handling is needed here.

signal pin_clicked(pin_id: String)
signal pin_hovered(pin_id: String)

## Zoom-independent click radius: a pin is this many px wide as a target.
const PIN_HIT_RADIUS_PX: float = 16.0
## Minimum screen distance between two accepted labels (see select_label_ids):
## a 13 px label is ~40-90 px wide, so 64 px keeps most pairs legible.
const LABEL_MIN_SEP_PX: float = 64.0

## Zoom bounds: 1.0 is the region framing fit (never zoom out past the framing
## box), 10.0 is the ceiling. One wheel notch / button / key press is ZOOM_STEP.
const MIN_ZOOM: float = 1.0
const MAX_ZOOM: float = 10.0
const ZOOM_STEP: float = 1.25
## A press that moves further than this (px) becomes a PAN and no longer counts
## as a click, so a plain click still selects a pin.
const PAN_DRAG_THRESHOLD_PX: float = 4.0

const OCEAN_COLOR := Color(0.055, 0.075, 0.13)
const LAND_COLOR := Color(0.19, 0.235, 0.32)
const WATER_COLOR := Color(0.06, 0.085, 0.15)
## Modulate for the world SVG (its landmasses are flat #444444 on transparency).
const WORLD_TINT := Color(0.66, 0.74, 0.90)
const GRATICULE_COLOR := Color(1.0, 1.0, 1.0, 0.055)
const PIN_OUTLINE := Color(0.03, 0.04, 0.07)
const PIN_FILL := Color(0.902, 0.698, 0.235)
const PIN_SELECTED_FILL := Color(1.0, 0.83, 0.38)
const PIN_HOVER_FILL := Color(1.0, 0.94, 0.68)
const PIN_RADIUS: float = 6.0
const PIN_SELECTED_RADIUS: float = 9.0
const LABEL_COLOR := Color(0.95, 0.96, 0.98)

const WORLD_SVG_PATH := "res://assets/ui/world_map_equirectangular.svg"
## Fallback rasterizer scale only (used when the .import is missing). Matches the
## shipped .import, which is pinned to svg/scale=8.0 -> 2880x1440.
const WORLD_SVG_RASTER_SCALE: float = 8.0

var region: String = TrackRegistry.DEFAULT_REGION:
	set(value):
		if value == region:
			return
		region = value
		_update_projection()
		queue_redraw()

var selected_pin_id: String = "":
	set(value):
		if value == selected_pin_id:
			return
		selected_pin_id = value
		queue_redraw()

var _hovered_pin_id: String = ""
## The framing fit for the current region/size BEFORE zoom/pan. `_fit` is always
## clamp_pan(pan_fit(zoom_fit(_base_fit, _zoom, size/2), _pan), size).
var _base_fit: Dictionary = {}
var _fit: Dictionary = {}
var _last_size := Vector2(-1.0, -1.0)
var _world_texture: Texture2D = null
## View state. `_zoom` is the scalar (>= MIN_ZOOM); `_pan` is a screen-space
## offset added to the centred-zoom fit. `_recompute_fit()` folds any pan clamp
## back into `_pan`, so the pair always describes the current view exactly.
var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _dragged: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _press_button: int = MOUSE_BUTTON_NONE

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_update_projection()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_projection()
		queue_redraw()

## Recomputes the fit when `size` was set directly (tests do exactly that) even
## if a resize notification was missed. Called lazily by every public read so a
## stale fit can never produce a wrong pin position.
func _ensure_projection() -> void:
	if _last_size != size:
		_update_projection()

## Rebase: rebuild `_base_fit` for the current region/size and RESET the view.
## Called on region switch, on resize, and lazily when `size` changed directly.
## (R3: if preserving zoom across a resize is ever wanted, re-apply `_zoom`
## about the centre here instead of resetting.)
func _update_projection() -> void:
	_last_size = size
	_base_fit = WorldMapProjection.build_fit(region, size, _fallback_pin())
	reset_view()

## Rebuilds `_fit` from `_base_fit`, `_zoom` and `_pan`, then folds the pan clamp
## back into `_pan` so the pair stays an exact (unclamped-equivalent) view.
func _recompute_fit() -> void:
	var focused := zoom_fit(_base_fit, _zoom, size * 0.5)
	_fit = clamp_pan(pan_fit(focused, _pan), size)
	if not focused.is_empty() and not _fit.is_empty():
		var fit_origin: Vector2 = _fit["origin"]
		var focused_origin: Vector2 = focused["origin"]
		_pan = fit_origin - focused_origin

# --- pure view math -----------------------------------------------------------

## Scale the fit by `factor` ABOUT the screen point `focus`: the map point whose
## screen position is `focus` keeps that position, and its screen distance from
## `focus` grows by `factor`. world_min/world_max are untouched.
static func zoom_fit(base: Dictionary, factor: float, focus: Vector2) -> Dictionary:
	if base.is_empty():
		return base
	var base_origin: Vector2 = base["origin"]
	var out := base.duplicate()
	out["origin"] = focus + (base_origin - focus) * factor
	out["scale"] = float(base["scale"]) * factor
	return out

## Translate the fit by a screen-space `delta` (world bounds unchanged).
static func pan_fit(fit: Dictionary, delta: Vector2) -> Dictionary:
	if fit.is_empty():
		return fit
	var origin: Vector2 = fit["origin"]
	var out := fit.duplicate()
	out["origin"] = origin + delta
	return out

## Keep the fitted content inside the viewport: when an axis' content is smaller
## than the view it is CENTRED on that axis; when it is larger the origin is
## clamped so no gap opens at either edge.
static func clamp_pan(fit: Dictionary, view: Vector2) -> Dictionary:
	if fit.is_empty():
		return fit
	var out := fit.duplicate()
	var origin: Vector2 = fit["origin"]
	var world_min: Vector2 = fit["world_min"]
	var world_max: Vector2 = fit["world_max"]
	var content: Vector2 = (world_max - world_min) * float(fit["scale"])
	var clamped := origin
	if content.x <= view.x:
		clamped.x = (view.x - content.x) * 0.5
	else:
		clamped.x = clampf(origin.x, view.x - content.x, 0.0)
	if content.y <= view.y:
		clamped.y = (view.y - content.y) * 0.5
	else:
		clamped.y = clampf(origin.y, view.y - content.y, 0.0)
	out["origin"] = clamped
	return out

# --- public view API ---------------------------------------------------------

func get_zoom() -> float:
	return _zoom

## Zoom to an absolute factor about `focus`, clamped to [MIN_ZOOM, MAX_ZOOM].
func set_zoom(value: float, focus: Vector2) -> void:
	var target := clampf(value, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(target, _zoom):
		return
	var k := target / _zoom
	_pan = _pan * k + (1.0 - k) * (focus - size * 0.5)
	_zoom = target
	_recompute_fit()
	queue_redraw()

## Multiply the zoom by `factor` about `focus` (already-clamped at the limits).
func zoom_by(factor: float, focus: Vector2) -> void:
	if factor <= 0.0:
		return
	set_zoom(_zoom * factor, focus)

## Back to the plain region framing fit (zoom 1.0, no pan).
func reset_view() -> void:
	_zoom = 1.0
	_pan = Vector2.ZERO
	_recompute_fit()
	queue_redraw()

## Drag the map by a screen-space `delta` (clamped by clamp_pan).
func pan_by(delta: Vector2) -> void:
	_pan += delta
	_recompute_fit()
	queue_redraw()

func _fallback_pin() -> Dictionary:
	if TrackRegistry.has_pin(selected_pin_id):
		return TrackRegistry.get_pin(selected_pin_id)
	var raw := TrackRegistry.pin_ids_for_region(region)
	if raw.is_empty():
		return {}
	return TrackRegistry.get_pin(str(raw[0]))

## True when this region is drawn from hand-authored vectors (the ISRAEL zoom),
## false when it uses the world SVG raster. Data-driven off the region record's
## "backdrop" key so a new tier only needs a registry entry. The pin layer is
## identical either way -- this exists so a test can assert the backdrop tier
## swapped.
func is_vector_backdrop() -> bool:
	return str(TrackRegistry.region_meta(region).get("backdrop", "world")) == "vector"

## The pins that BELONG to the current region, in pin-table order. This is
## MEMBERSHIP (the pin's own `region` field, via TrackRegistry.pin_ids_for_region)
## so the map draws/hit-tests exactly what the card list shows -- including the
## WORLD overview tier, whose membership is every pin. (It used to be box
## CONTAINMENT, which disagreed with pin_ids_for_region for WORLD.)
func visible_pin_ids() -> Array[String]:
	var out: Array[String] = []
	for pin_id: Variant in TrackRegistry.pin_ids_for_region(region):
		out.append(str(pin_id))
	return out

func pin_screen_position(pin_id: String) -> Vector2:
	_ensure_projection()
	if _fit.is_empty():
		return Vector2(-10000.0, -10000.0)
	return WorldMapProjection.project_pin(TrackRegistry.get_pin(pin_id), _fit)

## Nearest visible pin within PIN_HIT_RADIUS_PX of screen_pos, or "".
func hit_test(screen_pos: Vector2) -> String:
	_ensure_projection()
	if _fit.is_empty():
		return ""
	var best_id := ""
	var best_d := PIN_HIT_RADIUS_PX
	for pin_id: String in visible_pin_ids():
		var d := pin_screen_position(pin_id).distance_to(screen_pos)
		if d <= best_d:
			best_d = d
			best_id = pin_id
	return best_id

## Pure label de-clumping. `anchors` is an ordered Array (pin-table order) of
## {"id": String, "pos": Vector2}. `priority_ids` are always labelled. Accepts
## every priority anchor first, then greedily accepts a remaining anchor iff its
## position is >= min_sep_px from ALL already-accepted anchors. Deterministic:
## depends only on (anchors order, min_sep_px, priority_ids).
static func select_label_ids(anchors: Array, min_sep_px: float, priority_ids: PackedStringArray) -> Array[String]:
	var accepted_ids: Array[String] = []
	var accepted_pos: Array[Vector2] = []
	for want: String in priority_ids:
		for i in anchors.size():
			var d: Dictionary = anchors[i]
			if str(d.get("id", "")) == want:
				accepted_ids.append(want)
				var priority_pos: Vector2 = d.get("pos", Vector2.ZERO)
				accepted_pos.append(priority_pos)
				break
	for i in anchors.size():
		var d: Dictionary = anchors[i]
		var id: String = str(d.get("id", ""))
		if accepted_ids.has(id):
			continue
		var p: Vector2 = d.get("pos", Vector2.ZERO)
		var ok: bool = true
		for q: Vector2 in accepted_pos:
			if p.distance_to(q) < min_sep_px:
				ok = false
				break
		if ok:
			accepted_ids.append(id)
			accepted_pos.append(p)
	return accepted_ids

## The pin ids whose labels are currently drawn: the visible pins de-clumped by
## LABEL_MIN_SEP_PX, with the selected and hovered pins always named. Pure read
## off `visible_pin_ids()` + `pin_screen_position()`, so it works headless.
func labelled_pin_ids() -> Array[String]:
	var anchors: Array = []
	for pin_id: String in visible_pin_ids():
		anchors.append({"id": pin_id, "pos": pin_screen_position(pin_id)})
	var priority := PackedStringArray()
	if selected_pin_id != "":
		priority.append(selected_pin_id)
	if _hovered_pin_id != "" and _hovered_pin_id != selected_pin_id:
		priority.append(_hovered_pin_id)
	return select_label_ids(anchors, LABEL_MIN_SEP_PX, priority)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)

func _handle_mouse_button(button: InputEventMouseButton) -> void:
	if not button.pressed:
		_handle_mouse_release(button)
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		zoom_by(ZOOM_STEP, button.position)
		accept_event()
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		zoom_by(1.0 / ZOOM_STEP, button.position)
		accept_event()
		return
	if button.button_index != MOUSE_BUTTON_LEFT and button.button_index != MOUSE_BUTTON_MIDDLE:
		return
	# Left or middle press: start a potential pan. Whether it was a pan or a
	# click is decided on motion (threshold) and on release.
	_dragging = true
	_dragged = false
	_press_pos = button.position
	_press_button = button.button_index

## A release ends the drag. A LEFT release that never crossed the drag threshold
## is still a plain click and selects the pin under the cursor, so adding pan
## does not break pin selection.
func _handle_mouse_release(button: InputEventMouseButton) -> void:
	if not _dragging or button.button_index != _press_button:
		return
	var dragged := _dragged
	var released := _press_button
	_dragging = false
	_dragged = false
	_press_button = MOUSE_BUTTON_NONE
	if dragged or released != MOUSE_BUTTON_LEFT:
		return
	var hit := hit_test(button.position)
	if hit != "":
		pin_clicked.emit(hit)

func _handle_mouse_motion(motion: InputEventMouseMotion) -> void:
	if _dragging and motion.button_mask != 0:
		if not _dragged and motion.position.distance_to(_press_pos) > PAN_DRAG_THRESHOLD_PX:
			_dragged = true
		if _dragged:
			pan_by(motion.relative)
			return
	var hovered := hit_test(motion.position)
	if hovered != _hovered_pin_id:
		_hovered_pin_id = hovered
		queue_redraw()
		pin_hovered.emit(hovered)

func _draw() -> void:
	if _last_size != size:
		_update_projection()
	draw_rect(Rect2(Vector2.ZERO, size), OCEAN_COLOR)
	if _fit.is_empty():
		return
	if is_vector_backdrop():
		_draw_levant_backdrop()
	else:
		_draw_world_backdrop()
	_draw_graticule()
	var labelled_ids := labelled_pin_ids()
	var labelled: Dictionary = {}
	for id: String in labelled_ids:
		labelled[id] = true
	for pin_id: String in visible_pin_ids():
		_draw_pin(pin_id, labelled.has(pin_id))

func _draw_world_backdrop() -> void:
	var texture := _ensure_world_texture()
	if texture == null:
		return
	# Draw the raster CROPPED to the region framing box (see
	# world_backdrop_draw_rects), not whole: the dest rect IS that box in screen
	# space, so stretching the entire globe into it left every non-WORLD tier
	# showing an unzoomed, aspect-squashed world while the pins/graticule
	# projected at region-relative positions -- the continent never appeared to
	# zoom and every pin sat off its landmass. With the crop, backdrop, pins,
	# graticule and the vector Levant tier all follow the same affine
	# lon/lat -> screen map, at every zoom/pan (the fit transforms them together).
	var rects := world_backdrop_draw_rects(texture.get_size())
	var dest: Rect2 = rects["dest"]
	var src: Rect2 = rects["src"]
	# NOTE the arg order: (texture, dest, src, modulate, tile, transpose) -- the
	# region variant puts modulate BEFORE tile, unlike draw_texture_rect().
	draw_texture_rect_region(texture, dest, src, WORLD_TINT, false)

## The exact rects _draw_world_backdrop() feeds to draw_texture_rect_region():
##   "dest" - the fitted content rect (the region framing box in screen space),
##            over which the cropped raster is stretched;
##   "src"  - that same box as a texture-pixel crop of the world raster.
## Split out as a pure read of `region` + `_fit` so tests can lock the crop
## without a draw pass (gdUnit headless never runs _draw()).
func world_backdrop_draw_rects(texture_size: Vector2) -> Dictionary:
	_ensure_projection()
	var uv := WorldMapProjection.uv_rect_of_bounds(TrackRegistry.region_bounds(region))
	return {
		"dest": _content_rect(),
		"src": Rect2(uv.position * texture_size, uv.size * texture_size),
	}

func _draw_levant_backdrop() -> void:
	var land := _screen_ring(LevantOutline.land_ring())
	if land.size() >= 3:
		draw_colored_polygon(land, LAND_COLOR)
	for water: PackedVector2Array in LevantOutline.water_rings():
		var poly := _screen_ring(water)
		if poly.size() >= 3:
			draw_colored_polygon(poly, WATER_COLOR)

func _draw_graticule() -> void:
	var bounds := TrackRegistry.region_bounds(region)
	if bounds.is_empty() or _fit.is_empty():
		return
	var min_lon := float(bounds.get("min_lon", -180.0))
	var min_lat := float(bounds.get("min_lat", -90.0))
	var max_lon := float(bounds.get("max_lon", 180.0))
	var max_lat := float(bounds.get("max_lat", 90.0))
	var step := float(TrackRegistry.region_meta(region).get("graticule_step", 10.0))
	var lon := ceilf(min_lon / step) * step
	while lon <= max_lon + 0.0001:
		var a := WorldMapProjection.lonlat_to_screen(max_lat, lon, _fit)
		var b := WorldMapProjection.lonlat_to_screen(min_lat, lon, _fit)
		draw_line(a, b, GRATICULE_COLOR, 1.0)
		lon += step
	var lat := ceilf(min_lat / step) * step
	while lat <= max_lat + 0.0001:
		var a := WorldMapProjection.lonlat_to_screen(lat, min_lon, _fit)
		var b := WorldMapProjection.lonlat_to_screen(lat, max_lon, _fit)
		draw_line(a, b, GRATICULE_COLOR, 1.0)
		lat += step

func _draw_pin(pin_id: String, labelled: bool) -> void:
	var screen := pin_screen_position(pin_id)
	var is_selected := pin_id == selected_pin_id
	var is_hovered := pin_id == _hovered_pin_id
	var radius := PIN_SELECTED_RADIUS if is_selected else PIN_RADIUS
	var fill := PIN_FILL
	if is_selected:
		fill = PIN_SELECTED_FILL
	elif is_hovered:
		fill = PIN_HOVER_FILL
	if is_selected:
		# Slow halo pulse on the selected pin, mirroring the minimap marker idiom.
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.006)
		var halo := Color(PIN_FILL.r, PIN_FILL.g, PIN_FILL.b, 0.10 + 0.08 * pulse)
		draw_circle(screen, radius + 6.0 + pulse * 4.0, halo)
	draw_circle(screen, radius + 2.0, PIN_OUTLINE)
	draw_circle(screen, radius, fill)
	draw_circle(screen, maxf(radius - 3.0, 1.5), Color(1.0, 1.0, 1.0, 0.85))
	if labelled:
		var label := str(TrackRegistry.get_pin(pin_id).get("label", pin_id))
		draw_string(
			get_theme_default_font(),
			screen + Vector2(radius + 6.0, -radius - 4.0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			13,
			LABEL_COLOR)

func _content_rect() -> Rect2:
	# Mirror the map_roads.gd indexing idiom; compute_fit() always sets these.
	var origin: Vector2 = _fit["origin"]
	var world_min: Vector2 = _fit["world_min"]
	var world_max: Vector2 = _fit["world_max"]
	var scale: float = _fit["scale"]
	return Rect2(origin, (world_max - world_min) * scale)

func _screen_ring(lonlat: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for vertex: Vector2 in lonlat:
		out.append(WorldMapProjection.lonlat_to_screen(vertex.y, vertex.x, _fit))
	return out

## The world SVG as a texture. Primary path is the normal imported texture (the
## project ships a .import pinned to svg/scale=8 -> 2880x1440). If it is not
## imported yet (fresh checkout), fall back to rasterizing the same CC0 file at
## runtime so the tier still renders instead of silently showing bare ocean.
func _ensure_world_texture() -> Texture2D:
	if _world_texture != null:
		return _world_texture
	if ResourceLoader.exists(WORLD_SVG_PATH):
		var resource: Resource = load(WORLD_SVG_PATH)
		if resource is Texture2D:
			_world_texture = resource as Texture2D
			return _world_texture
	_world_texture = _rasterize_svg(WORLD_SVG_PATH, WORLD_SVG_RASTER_SCALE)
	return _world_texture

static func _rasterize_svg(path: String, scale: float) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	if image.load_svg_from_buffer(bytes, scale) != OK:
		return null
	return ImageTexture.create_from_image(image)
