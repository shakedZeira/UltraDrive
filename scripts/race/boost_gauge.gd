# scripts/race/boost_gauge.gd
class_name BoostGauge
extends Control

## Forza/GT-style turbo boost gauge: a compact arc that sweeps from -0.2 bar
## (vacuum) to the car's turbo_max_boost_bar peak, with the same needle easing,
## DESIGN_SIZE scaling and dark-translucent palette as the Tachometer cluster.
## Auto-hides for naturally aspirated cars: set_boost_bar() is the only entry
## point and drives visibility off max_bar > 0, so NA cars never draw it.

const DESIGN_SIZE := Vector2(100.0, 108.0)
const GAUGE_CENTER := Vector2(50.0, 56.0)
const GAUGE_RADIUS := 38.0
const GAUGE_THICKNESS := 8.0
const START_ANGLE_DEG := 150.0
const END_ANGLE_DEG := 390.0
const MAJOR_TICKS := 3
## Arc floor: the needle rests slightly below 0 at vacuum, GT-style.
const BAR_MIN := -0.2
## Display snap: below this bar gap the needle lands exactly on the target so
## _process() settles (and stops repainting) the same way the tach does.
const SNAP_BAR := 0.01

const COLOR_PANEL := Color(0.04, 0.06, 0.11, 0.82)
const COLOR_PANEL_BORDER := Color(0.3, 0.5, 0.8, 0.35)
const COLOR_TRACK := Color(1.0, 1.0, 1.0, 0.1)
const COLOR_FILL := Color(0.45, 0.9, 1.0, 0.95)
const COLOR_FILL_GLOW := Color(0.3, 0.75, 1.0, 0.2)
const COLOR_NEEDLE := Color(0.94, 0.3, 0.18, 1.0)
const COLOR_TICK := Color(0.8, 0.88, 1.0, 0.85)
const COLOR_LABEL := Color(0.31, 0.84, 1.0, 0.9)

var _max_bar := 0.0
var _target_bar := 0.0
var _display_bar := 0.0

var _panel_box := StyleBoxFlat.new()
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font
	_panel_box.bg_color = COLOR_PANEL
	_panel_box.border_color = COLOR_PANEL_BORDER
	_panel_box.set_border_width_all(1)
	_panel_box.set_corner_radius_all(12)
	# Hidden until a turbo car proves it has boost to show.
	visible = _max_bar > 0.0

## Feeds the live boost reading. max_bar <= 0 (NA car) hides the gauge and
## zeroes the needle; a turbo car eases its needle toward the clamped value.
func set_boost_bar(value: float, max_bar: float) -> void:
	_max_bar = maxf(max_bar, 0.0)
	visible = _max_bar > 0.0
	if _max_bar <= 0.0:
		_target_bar = 0.0
		_display_bar = 0.0
		queue_redraw()
		return
	_target_bar = clampf(value, BAR_MIN, _max_bar)
	_display_bar = clampf(_display_bar, BAR_MIN, _max_bar)

func _process(delta: float) -> void:
	if not visible:
		return
	var prev := _display_bar
	# Ease the needle toward the target (frame-rate independent), same envelope
	# as the tachometer so the two needles feel like one cluster.
	var rate := 1.0 - exp(-10.0 * delta)
	_display_bar = lerpf(_display_bar, _target_bar, rate)
	if absf(_display_bar - _target_bar) < SNAP_BAR:
		_display_bar = _target_bar
	if prev != _display_bar:
		queue_redraw()

func _draw() -> void:
	if _max_bar <= 0.0:
		return
	var scale := Vector2(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	var center := GAUGE_CENTER * scale
	var radius := GAUGE_RADIUS * scale.x
	var thickness := GAUGE_THICKNESS * scale.x
	var inner := radius - thickness

	draw_style_box(_panel_box, Rect2(Vector2.ZERO, size))

	var start := deg_to_rad(START_ANGLE_DEG)
	var end := deg_to_rad(END_ANGLE_DEG)
	var sweep := end - start

	draw_arc(center, radius, start, end, 64, COLOR_TRACK, thickness, true)

	var progress := clampf((_display_bar - BAR_MIN) / maxf(_max_bar - BAR_MIN, 0.001), 0.0, 1.0)
	var fill_end := start + sweep * progress
	if fill_end > start + 0.001:
		draw_arc(center, radius, start, fill_end, 64, COLOR_FILL_GLOW, thickness + 6.0, true)
		draw_arc(center, radius, start, fill_end, 64, COLOR_FILL, thickness, true)

	_draw_ticks(center, inner, start, sweep)
	_draw_needle(center, inner, start, sweep, progress)
	_draw_hub(center)
	var label := "bar"
	var label_width := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11).x
	draw_string(_font, Vector2(center.x - label_width * 0.5, size.y - 8.0),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, COLOR_LABEL)

func _draw_ticks(center: Vector2, inner: float, start: float, sweep: float) -> void:
	var step := 1.0 / float((MAJOR_TICKS - 1) * 2)
	for i in range(MAJOR_TICKS):
		var p := float(i) / float(MAJOR_TICKS - 1)
		var ang := start + sweep * p
		var dir := Vector2.from_angle(ang)
		_draw_tick(center, dir, inner - 2.0, inner - 10.0, COLOR_TICK, 2.0)
		if i < MAJOR_TICKS - 1:
			for j in range(1, 2):
				var mang := start + sweep * (p + float(j) * step)
				_draw_tick(center, Vector2.from_angle(mang), inner - 2.0, inner - 6.0, Color(COLOR_TICK, 0.5), 1.5)

func _draw_tick(center: Vector2, dir: Vector2, from_r: float, to_r: float, color: Color, width: float) -> void:
	draw_line(center + dir * from_r, center + dir * to_r, color, width, true)

func _draw_needle(center: Vector2, inner: float, start: float, sweep: float, progress: float) -> void:
	var ang := start + sweep * progress
	var dir := Vector2.from_angle(ang)
	var perp := Vector2.from_angle(ang + PI * 0.5)
	var tip := center + dir * (inner - 3.0)
	var base := center + dir * 8.0
	draw_colored_polygon(PackedVector2Array([
		base + perp * 4.5,
		tip + perp * 1.0,
		tip - perp * 1.0,
		base - perp * 4.5,
	]), COLOR_NEEDLE)

func _draw_hub(center: Vector2) -> void:
	draw_circle(center, 7.0, Color(0.07, 0.09, 0.16))
	draw_arc(center, 7.0, 0.0, TAU, 16, Color(0.92, 0.96, 1.0, 0.65), 1.5, true)
	draw_circle(center, 3.0, COLOR_NEEDLE)
