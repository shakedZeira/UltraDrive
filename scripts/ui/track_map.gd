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
## Teardrop badge radii (px): the world overview is crowded, so its pins are smaller.
const PIN_BADGE: float = 12.0
const PIN_BADGE_WORLD: float = 8.5
## Exponential smoothing rate (1/s) the drawn view uses to chase the zoom/pan target.
const VIEW_SMOOTHING: float = 14.0
const LAND_SHADER_PATH := "res://shaders/ui/map_land.gdshader"
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
		focus_on_pin(value)
		queue_redraw()

var _hovered_pin_id: String = ""
## The framing fit for the current region/size BEFORE zoom/pan. `_fit` is always
## clamp_pan(pan_fit(zoom_fit(_base_fit, _zoom, size/2), _pan), size).
var _base_fit: Dictionary = {}
var _fit: Dictionary = {}
var _last_size := Vector2(-1.0, -1.0)
## DISPLAYED view (chases `_fit`): origin/scale animate so zoom and pan glide.
var _view_origin := Vector2.ZERO
var _view_scale := 0.0
## The fit the current draw pass uses (set at the top of _draw()).
var _df: Dictionary = {}
var _ocean_layer: TextureRect = null
var _land_layer: ColorRect = null
var _land_mat: ShaderMaterial = null
var _vignette_tex: Texture2D = null
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
	_build_layers()
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
	# A region switch or resize re-frames the map: show it at once, no glide.
	snap_view()

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
		var tip := pin_screen_position(pin_id)
		# The badge floats above the tip, so clicking either one picks the pin.
		var d := minf(tip.distance_to(screen_pos), pin_badge_center(tip).distance_to(screen_pos))
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

## Pin presentation: the circuit type picks the glyph (chequered flag, oval,
## dirt zigzag, stopwatch) and the layout's class picks the colour (D cyan ...
## S violet), so a pin tells you what it is without its label.
func pin_style(pin_id: String) -> Dictionary:
	var layout := TrackRegistry.get_track(TrackRegistry.track_for_pin(pin_id))
	return {
		"glyph": MapStyle.circuit_glyph(str(layout.get("circuit_type", ""))),
		"color": MapStyle.class_color(str(layout.get("difficulty", ""))),
	}

## Badge radius (px) of a pin at the current zoom: smaller on the crowded world
## overview, growing a little as the view zooms in.
func pin_badge_radius() -> float:
	var base := PIN_BADGE_WORLD if region == TrackRegistry.REGION_WORLD else PIN_BADGE
	return base * (1.0 + 0.10 * minf(_zoom - 1.0, 4.0))

## Where the badge sits for a pin whose TIP is at `tip` (the badge floats above it).
func pin_badge_center(tip: Vector2) -> Vector2:
	return tip + Vector2(0.0, -pin_badge_radius() * 1.9)

## Gently bring a pin into view. With `zoom_level` > 0 the view zooms there first.
## At the plain fit nothing moves (the whole region is already on screen).
func focus_on_pin(pin_id: String, zoom_level: float = -1.0) -> void:
	_ensure_projection()
	if _fit.is_empty() or not TrackRegistry.has_pin(pin_id):
		return
	if zoom_level > 0.0:
		set_zoom(zoom_level, size * 0.5)
	if _zoom <= MIN_ZOOM + 0.001:
		return
	pan_by(size * 0.5 - pin_screen_position(pin_id))

## Jump the displayed view to the target (region switch, tests, captures).
func snap_view() -> void:
	if _fit.is_empty():
		return
	_view_origin = _fit["origin"]
	_view_scale = float(_fit["scale"])
	queue_redraw()

## The fit the DRAW pass uses: the displayed (animated) origin/scale on top of the
## target fit's world bounds. Hit-tests and every public read stay on `_fit`.
func _view_fit() -> Dictionary:
	if _fit.is_empty() or _view_scale <= 0.0:
		return _fit
	var out := _fit.duplicate()
	out["origin"] = _view_origin
	out["scale"] = _view_scale
	return out

func _process(delta: float) -> void:
	if not is_visible_in_tree() or _fit.is_empty():
		return
	var target_origin: Vector2 = _fit["origin"]
	var target_scale := float(_fit["scale"])
	if _view_scale <= 0.0:
		snap_view()
	var k := 1.0 - exp(-VIEW_SMOOTHING * maxf(delta, 0.0))
	_view_origin = _view_origin.lerp(target_origin, k)
	_view_scale = lerpf(_view_scale, target_scale, k)
	if _view_origin.distance_to(target_origin) < 0.05 and absf(_view_scale - target_scale) < 0.00001 * maxf(target_scale, 1.0):
		_view_origin = target_origin
		_view_scale = target_scale
	# Selected-pin pulse is time driven, so it redraws every frame (cheap: the
	# land is a shader layer, the rest is ~40 pins).
	queue_redraw()

func _draw() -> void:
	if _last_size != size:
		_update_projection()
	if _fit.is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), OCEAN_COLOR)
		return
	_df = _view_fit()
	var vector_tier := is_vector_backdrop()
	_sync_layers(not vector_tier)
	if vector_tier:
		_draw_levant_backdrop()
	_draw_graticule()
	_draw_captions()
	_draw_vignette()
	var labelled_ids := labelled_pin_ids()
	var labelled: Dictionary = {}
	for id: String in labelled_ids:
		labelled[id] = true
	# Back-to-front by screen y so a lower pin overlaps the one behind it; the
	# selected and hovered pins always draw last (on top).
	var order: Array[String] = visible_pin_ids()
	order.sort_custom(func(a: String, b: String) -> bool:
		return _pin_draw_pos(a).y < _pin_draw_pos(b).y)
	for pin_id: String in order:
		if pin_id != selected_pin_id and pin_id != _hovered_pin_id:
			_draw_pin(pin_id, labelled.has(pin_id))
	if _hovered_pin_id != "" and _hovered_pin_id != selected_pin_id:
		_draw_pin(_hovered_pin_id, true)
	if selected_pin_id != "" and TrackRegistry.has_pin(selected_pin_id):
		_draw_pin(selected_pin_id, true)
	_draw_legend()

func _pin_draw_pos(pin_id: String) -> Vector2:
	return WorldMapProjection.project_pin(TrackRegistry.get_pin(pin_id), _df)

## The ocean and (world tier only) land layers are children that draw BEHIND this
## control, so they must be positioned before the pins and captions draw on top.
func _sync_layers(world_tier: bool) -> void:
	if _ocean_layer != null:
		_ocean_layer.visible = true
	if _land_layer == null:
		return
	var texture := _ensure_world_texture() if world_tier else null
	_land_layer.visible = texture != null
	if texture == null:
		return
	var rects := world_backdrop_draw_rects(texture.get_size())
	var dest := _content_rect_of(_df)
	var src: Rect2 = rects["src"]
	var tex_size := texture.get_size()
	_land_layer.position = dest.position
	_land_layer.size = dest.size
	var bounds := TrackRegistry.region_bounds(region)
	var uv := Vector4(src.position.x / tex_size.x, src.position.y / tex_size.y,
		src.size.x / tex_size.x, src.size.y / tex_size.y)
	_land_mat.set_shader_parameter("land_tex", texture)
	_land_mat.set_shader_parameter("src_uv", uv)
	_land_mat.set_shader_parameter("px_uv", Vector2(uv.z / maxf(dest.size.x, 1.0), uv.w / maxf(dest.size.y, 1.0)))
	_land_mat.set_shader_parameter("lat_top", float(bounds.get("max_lat", 90.0)))
	_land_mat.set_shader_parameter("lat_bottom", float(bounds.get("min_lat", -90.0)))
	_land_mat.set_shader_parameter("lon_left", float(bounds.get("min_lon", -180.0)))
	_land_mat.set_shader_parameter("lon_right", float(bounds.get("max_lon", 180.0)))

func _build_layers() -> void:
	if _ocean_layer != null:
		return
	clip_contents = true
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.075, 0.215, 0.330))
	gradient.set_color(1, OCEAN_COLOR)
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.45)
	tex.fill_to = Vector2(1.05, 1.05)
	tex.width = 256
	tex.height = 256
	_ocean_layer = TextureRect.new()
	_ocean_layer.name = "OceanLayer"
	_ocean_layer.texture = tex
	_ocean_layer.stretch_mode = TextureRect.STRETCH_SCALE
	_ocean_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ocean_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ocean_layer.show_behind_parent = true
	_ocean_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_ocean_layer, false, Node.INTERNAL_MODE_FRONT)
	_land_layer = ColorRect.new()
	_land_layer.name = "LandLayer"
	_land_layer.color = Color.WHITE
	_land_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_land_layer.show_behind_parent = true
	_land_layer.visible = false
	_land_mat = ShaderMaterial.new()
	_land_mat.shader = load(LAND_SHADER_PATH) as Shader
	_land_layer.material = _land_mat
	add_child(_land_layer, false, Node.INTERNAL_MODE_FRONT)

func _draw_vignette() -> void:
	if _vignette_tex == null:
		_vignette_tex = ImageTexture.create_from_image(MapStyle.make_vignette_image(128, 0.50, 0.66))
	draw_texture_rect(_vignette_tex, Rect2(Vector2.ZERO, size), false)

## The exact rects _draw_world_backdrop() used to feed to draw_texture_rect_region():
##   "dest" - the fitted content rect (the region framing box in screen space),
##            over which the cropped raster is stretched;
##   "src"  - that same box as a texture-pixel crop of the world raster.
## Split out as a pure read of `region` + `_fit` so tests can lock the crop
## without a draw pass (gdUnit headless never runs _draw()). The land layer now
## consumes the same two rects.
func world_backdrop_draw_rects(texture_size: Vector2) -> Dictionary:
	_ensure_projection()
	var uv := WorldMapProjection.uv_rect_of_bounds(TrackRegistry.region_bounds(region))
	return {
		"dest": _content_rect(),
		"src": Rect2(uv.position * texture_size, uv.size * texture_size),
	}

## The hand-authored Levant tier: shelf glow, a land fill graded from green in the
## north to desert tan in the south, a pale coast line and the two inland seas.
func _draw_levant_backdrop() -> void:
	var land_ll := LevantOutline.land_ring()
	var land := _screen_ring(land_ll)
	if land.size() < 3:
		return
	var closed := land.duplicate()
	closed.append(land[0])
	for glow in [[34.0, 0.07], [22.0, 0.09], [12.0, 0.12], [5.0, 0.16]]:
		draw_polyline(closed, Color(0.22, 0.60, 0.68, float(glow[1])), float(glow[0]), true)
	var colors := PackedColorArray()
	for vertex: Vector2 in land_ll:
		colors.append(_levant_land_color(vertex.y, vertex.x))
	draw_polygon(land, colors)
	draw_polyline(closed, Color(0.93, 0.95, 0.86, 0.75), 1.8, true)
	for water: PackedVector2Array in LevantOutline.water_rings():
		var poly := _screen_ring(water)
		if poly.size() >= 3:
			draw_colored_polygon(poly, Color(0.14, 0.40, 0.55))
			var edge := poly.duplicate()
			edge.append(poly[0])
			draw_polyline(edge, Color(0.80, 0.92, 0.90, 0.6), 1.4, true)

## North green, centre olive, south desert, with the Jordan rift a touch drier.
static func _levant_land_color(lat: float, lon: float) -> Color:
	var green := Color(0.33, 0.50, 0.27)
	var olive := Color(0.52, 0.55, 0.31)
	var tan := Color(0.78, 0.68, 0.47)
	var c := tan.lerp(olive, clampf((lat - 30.4) / 1.4, 0.0, 1.0))
	c = c.lerp(green, clampf((lat - 31.9) / 1.2, 0.0, 1.0))
	if lon > 35.3:
		c = c.lerp(tan, 0.18)
	return c

func _draw_graticule() -> void:
	var bounds := TrackRegistry.region_bounds(region)
	if bounds.is_empty() or _df.is_empty():
		return
	var min_lon := float(bounds.get("min_lon", -180.0))
	var min_lat := float(bounds.get("min_lat", -90.0))
	var max_lon := float(bounds.get("max_lon", 180.0))
	var max_lat := float(bounds.get("max_lat", 90.0))
	var step := float(TrackRegistry.region_meta(region).get("graticule_step", 10.0))
	var lon := ceilf(min_lon / step) * step
	while lon <= max_lon + 0.0001:
		var a := WorldMapProjection.lonlat_to_screen(max_lat, lon, _df)
		var b := WorldMapProjection.lonlat_to_screen(min_lat, lon, _df)
		draw_line(a, b, GRATICULE_COLOR, 1.0)
		lon += step
	var lat := ceilf(min_lat / step) * step
	while lat <= max_lat + 0.0001:
		var a := WorldMapProjection.lonlat_to_screen(lat, min_lon, _df)
		var b := WorldMapProjection.lonlat_to_screen(lat, max_lon, _df)
		draw_line(a, b, GRATICULE_COLOR, 1.0)
		lat += step

## Region captions: continent names on the world overview, editorial sea/desert
## names on the Israel tier -- big, letter-spaced, low contrast so they read as part
## of the map and never fight the pins.
func region_captions() -> Array:
	var out: Array = []
	if is_vector_backdrop():
		for caption: Dictionary in LevantOutline.captions():
			out.append({"text": str(caption["text"]), "lat": float(caption["lat"]), "lon": float(caption["lon"]), "size": 16})
		return out
	if region != TrackRegistry.REGION_WORLD:
		return out
	for region_id: Variant in TrackRegistry.get_region_ids():
		var id := str(region_id)
		if id == TrackRegistry.REGION_WORLD or id == TrackRegistry.REGION_ISRAEL:
			continue
		var b := TrackRegistry.region_bounds(id)
		out.append({
			"text": TrackRegistry.region_label(id),
			"lat": (float(b.get("min_lat", 0.0)) + float(b.get("max_lat", 0.0))) * 0.5,
			"lon": (float(b.get("min_lon", 0.0)) + float(b.get("max_lon", 0.0))) * 0.5,
			"size": 20,
		})
	return out

func _draw_captions() -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	for caption: Dictionary in region_captions():
		var at := WorldMapProjection.lonlat_to_screen(float(caption["lat"]), float(caption["lon"]), _df)
		if not Rect2(Vector2(-100.0, -40.0), size + Vector2(200.0, 80.0)).has_point(at):
			continue
		MapStyle.draw_spaced_label(self, font, str(caption["text"]), at, int(caption["size"]),
			Color(1.0, 1.0, 1.0, 0.55), 6.0, Color(0.02, 0.06, 0.12, 0.5))

func _draw_pin(pin_id: String, labelled: bool) -> void:
	var tip := _pin_draw_pos(pin_id)
	var is_selected := pin_id == selected_pin_id
	var is_hovered := pin_id == _hovered_pin_id
	var style := pin_style(pin_id)
	var r := pin_badge_radius()
	var ring := MapStyle.PIN_RING
	if is_selected:
		r += 4.0
		ring = Color(1.0, 0.92, 0.55)
		# Pulsing ground ring at the pin tip, mirroring the minimap marker idiom.
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.005)
		draw_circle(tip, r * 1.0 + pulse * 6.0, Color(1.0, 0.90, 0.45, 0.14 + 0.10 * (1.0 - pulse)))
		draw_arc(tip, r * 1.0 + pulse * 6.0, 0.0, TAU, 40, Color(1.0, 0.92, 0.55, 0.7 * (1.0 - pulse) + 0.2), 2.0, true)
	elif is_hovered:
		r += 2.0
	var center := MapStyle.draw_teardrop(self, tip, r, style["color"], str(style["glyph"]), Color.WHITE, ring)
	if not labelled:
		return
	var font := get_theme_default_font()
	if font == null:
		return
	var label := str(TrackRegistry.get_pin(pin_id).get("label", pin_id))
	if is_selected or is_hovered:
		MapStyle.draw_pill_label(self, font, label.to_upper() if is_selected else label,
			center + Vector2(r + 8.0, 0.0), 13)
	else:
		var at := center + Vector2(r + 7.0, 5.0)
		draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, 4, Color(0.02, 0.05, 0.10, 0.85))
		draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, LABEL_COLOR)

## Legend: the four circuit types (glyph) and the class ladder (colour), bottom-left.
func legend_entries() -> Array:
	var out: Array = []
	for circuit_type: String in ["CIRCUIT", "OVAL", "DIRT RX", "ENDURANCE"]:
		out.append({"glyph": MapStyle.circuit_glyph(circuit_type), "label": circuit_type.capitalize() if circuit_type != "DIRT RX" else "Rallycross"})
	return out

func legend_classes() -> Array[String]:
	var seen: Array[String] = []
	for track_id: Variant in TrackRegistry.tracks:
		var klass := str(TrackRegistry.get_track(str(track_id)).get("difficulty", ""))
		if klass != "" and not seen.has(klass):
			seen.append(klass)
	seen.sort()
	seen.reverse()
	return seen

func _draw_legend() -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var entries := legend_entries()
	var classes := legend_classes()
	var row_h := 24.0
	var panel := Rect2(Vector2(14.0, size.y - (float(entries.size()) * row_h + 56.0) - 14.0),
		Vector2(150.0, float(entries.size()) * row_h + 56.0))
	var box := StyleBoxFlat.new()
	box.bg_color = MapStyle.PANEL_DARK
	box.border_color = MapStyle.PANEL_EDGE
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	draw_style_box(box, panel)
	var y := panel.position.y + 18.0
	for entry in entries:
		MapStyle.draw_badge(self, Vector2(panel.position.x + 22.0, y), 8.0, MapStyle.ACCENT.darkened(0.15), str(entry["glyph"]))
		draw_string(font, Vector2(panel.position.x + 40.0, y + 5.0), str(entry["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MapStyle.TEXT_LIGHT)
		y += row_h
	draw_string(font, Vector2(panel.position.x + 14.0, y + 10.0), "CLASS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MapStyle.TEXT_DIM)
	var x := panel.position.x + 58.0
	for klass in classes:
		draw_circle(Vector2(x, y + 6.0), 8.0, MapStyle.class_color(klass))
		draw_string(font, Vector2(x - 4.0, y + 10.5), klass, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.05, 0.07, 0.10))
		x += 21.0

func _content_rect() -> Rect2:
	return _content_rect_of(_fit)

func _content_rect_of(fit: Dictionary) -> Rect2:
	# Mirror the map_roads.gd indexing idiom; compute_fit() always sets these.
	var origin: Vector2 = fit["origin"]
	var world_min: Vector2 = fit["world_min"]
	var world_max: Vector2 = fit["world_max"]
	var scale: float = fit["scale"]
	return Rect2(origin, (world_max - world_min) * scale)

func _screen_ring(lonlat: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for vertex: Vector2 in lonlat:
		out.append(WorldMapProjection.lonlat_to_screen(vertex.y, vertex.x, _df))
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
