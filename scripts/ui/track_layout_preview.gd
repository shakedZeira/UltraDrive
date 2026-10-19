class_name TrackLayoutPreview
extends Control

## The selected layout's centerline, drawn as a 2D shape — the race menu's
## "hero" element (GT7-style race entry).
##
## Headless discipline (mirrors TrackMap): `_draw()` never runs under gdUnit, so
## the projection is computed in `set_layout()` and on RESIZE, and every public
## read re-ensures it. Tests can set `size` explicitly and read
## `projected_points()` with no draw pass. Projection reuses the shared
## `MapRoads.compute_fit` / `MapRoads.world_to_screen` pair the minimap and
## pause map use, so the shape matches the in-game map orientation (north-up).
##
## Missing data is a first-class state: `has_layout()` is false, the shape is not
## drawn and a dim caption says so (the menu also flips `%PreviewCaption`).

## Uniform inset (px) from the Control's rect, absorbed by compute_fit.
const INSET_PX: float = 14.0
const LINE_WIDTH: float = 2.5
const LINE_COLOR := Color(0.902, 0.698, 0.235)
const BG_COLOR := Color(0.075, 0.095, 0.16)
const CAPTION_COLOR := Color(0.62, 0.66, 0.74)
const EMPTY_TEXT := "LAYOUT MAP UNAVAILABLE"
const TICK_COLOR := Color(0.95, 0.96, 0.98)
const TICK_WIDTH: float = 3.0
const TICK_HALF: float = 7.0

var _track_id: String = ""
var _points: Array[Vector3] = []
var _projected := PackedVector2Array()
var _fit: Dictionary = {}
var _last_size := Vector2(-1.0, -1.0)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rebuild()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_rebuild()
		queue_redraw()

## Select a layout by TrackRegistry id and recompute the fit IMMEDIATELY (never
## lazily from `_draw()`).
func set_layout(track_id: String) -> void:
	_track_id = track_id
	_points = TrackLayoutSource.points(track_id)
	_rebuild()
	queue_redraw()

func layout_id() -> String:
	return _track_id

func has_layout() -> bool:
	return _points.size() >= 3

## Screen-space (Control-local) vertices for the selected layout; empty when
## there is no data. Recomputed if `size` changed since the last build.
func projected_points() -> PackedVector2Array:
	_ensure()
	return _projected

## The MapRoads fit Dictionary currently in force.
func get_fit() -> Dictionary:
	_ensure()
	return _fit

func _ensure() -> void:
	if _last_size != size:
		_rebuild()

func _rebuild() -> void:
	_last_size = size
	var fallback := Vector3.ZERO
	if not _points.is_empty():
		fallback = _points[0]
	_fit = MapRoads.compute_fit(_points, fallback, size, INSET_PX)
	_projected = PackedVector2Array()
	if _points.is_empty():
		return
	var projected := PackedVector2Array()
	projected.resize(_points.size())
	for i in _points.size():
		projected[i] = MapRoads.world_to_screen(_points[i], _fit)
	_projected = projected

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR, true)
	if not has_layout():
		var font: Font = get_theme_default_font()
		if font != null:
			var font_size := 13
			var text_size := font.get_string_size(EMPTY_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
			var pos := (size - text_size) * 0.5 + Vector2(0.0, text_size.y)
			draw_string(font, pos, EMPTY_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, CAPTION_COLOR)
		return
	var line := PackedVector2Array(_projected)
	if line.size() >= 3:
		line.append(line[0])
	draw_polyline(line, LINE_COLOR, LINE_WIDTH, true)
	if _projected.size() >= 2:
		_draw_start_tick()

## A short tick across the line at the first centerline point (start/finish).
func _draw_start_tick() -> void:
	var p0 := _projected[0]
	var dir := _projected[1] - p0
	if dir.length_squared() <= 0.0001:
		return
	dir = dir.normalized()
	var perp := Vector2(-dir.y, dir.x)
	draw_line(p0 - perp * TICK_HALF, p0 + perp * TICK_HALF, TICK_COLOR, TICK_WIDTH, true)
