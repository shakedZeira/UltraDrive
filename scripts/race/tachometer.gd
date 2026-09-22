# scripts/race/tachometer.gd
class_name Tachometer
extends Control

## Forza Horizon / Gran Turismo style gauge cluster: an arc tachometer with a
## colored sweep and needle, redline zone + shift light, big gear digit, big
## speed readout and car-class badge, all on a dark translucent panel.

@onready var gear_value: Label = %GearValue
@onready var rpm_value: Label = %RpmValue
@onready var speed_value: Label = %SpeedValue
@onready var class_badge: Label = %ClassBadge

const DESIGN_SIZE := Vector2(560.0, 330.0)
const GAUGE_CENTER := Vector2(185.0, 135.0)
const GAUGE_RADIUS := 118.0
const GAUGE_THICKNESS := 16.0
const START_ANGLE_DEG := 130.0
const END_ANGLE_DEG := 410.0
const REDLINE_ARC_DEG := 55.0
const MAJOR_TICKS := 6
const MINOR_PER_MAJOR := 4

const COLOR_PANEL := Color(0.04, 0.06, 0.11, 0.82)
const COLOR_PANEL_BORDER := Color(0.3, 0.5, 0.8, 0.35)
const COLOR_TRACK := Color(1.0, 1.0, 1.0, 0.1)
const COLOR_FILL := Color(0.93, 0.96, 1.0, 0.95)
const COLOR_FILL_GLOW := Color(0.35, 0.62, 1.0, 0.2)
const COLOR_REDLINE := Color(0.95, 0.22, 0.15, 0.95)
const COLOR_NEEDLE := Color(0.94, 0.3, 0.18, 1.0)
const COLOR_TICK := Color(0.8, 0.88, 1.0, 0.85)

var _idle_rpm := 800.0
var _redline_rpm := 7500.0
var _target_rpm := 800.0
var _display_rpm := 800.0
var _gear := 1
var _car_class := "D"
var _over_red := false

var _panel_box := StyleBoxFlat.new()
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font
	_panel_box.bg_color = COLOR_PANEL
	_panel_box.border_color = COLOR_PANEL_BORDER
	_panel_box.set_border_width_all(1)
	_panel_box.set_corner_radius_all(26)
	var player := VehicleManager.get_player_car()
	if player != null and player.config != null:
		set_engine_range(player.config.idle_rpm, player.config.redline_rpm)
		set_car_class(player.config.car_class)
	gear_value.text = _gear_to_string(_gear)
	rpm_value.text = "0"
	speed_value.text = "0"
	class_badge.text = _car_class

func set_engine_range(idle_rpm: float, redline_rpm: float) -> void:
	if is_equal_approx(idle_rpm, _idle_rpm) and is_equal_approx(redline_rpm, _redline_rpm):
		return
	_idle_rpm = idle_rpm
	_redline_rpm = maxf(redline_rpm, idle_rpm + 1.0)
	_target_rpm = clampf(_target_rpm, _idle_rpm, _redline_rpm)
	_display_rpm = clampf(_display_rpm, _idle_rpm, _redline_rpm)
	queue_redraw()

func set_car_class(cls: String) -> void:
	if cls != _car_class:
		_car_class = cls
		class_badge.text = cls

func set_rpm(rpm: float) -> void:
	_target_rpm = rpm
	rpm_value.text = "%d" % roundi(rpm)

func set_gear(gear: int) -> void:
	if gear != _gear:
		_gear = gear
		gear_value.text = _gear_to_string(gear)

func set_speed_kmh(kmh: float) -> void:
	speed_value.text = "%d" % roundi(kmh)

func _process(delta: float) -> void:
	var prev := _display_rpm
	# Ease the needle toward the target (frame-rate independent). The display
	# lags the target, so prev != _display_rpm while converging and the redraw
	# below fires every frame the gauge is actually moving.
	var rate := 1.0 - exp(-10.0 * delta)
	_display_rpm = lerpf(_display_rpm, _target_rpm, rate)
	if _display_rpm != _target_rpm and absf(_display_rpm - _target_rpm) < 5.0:
		_display_rpm = _target_rpm
	var over_red := _display_rpm >= _redline_rpm
	if over_red != _over_red:
		_over_red = over_red
		rpm_value.add_theme_color_override("font_color", Color(1.0, 0.3, 0.22) if over_red else Color(0.93, 0.96, 1.0))
	if _over_red or prev != _display_rpm:
		queue_redraw()

func _gear_to_string(gear: int) -> String:
	if gear == -1:
		return "R"
	return str(gear)

func _draw() -> void:
	var scale := Vector2(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	var center := GAUGE_CENTER * scale
	var radius := GAUGE_RADIUS * scale.x
	var thickness := GAUGE_THICKNESS * scale.x
	var inner := radius - thickness

	draw_style_box(_panel_box, Rect2(Vector2.ZERO, size))

	var start := deg_to_rad(START_ANGLE_DEG)
	var end := deg_to_rad(END_ANGLE_DEG)
	var sweep := end - start
	var red_start := end - deg_to_rad(REDLINE_ARC_DEG)
	var red_mid := (red_start + end) * 0.5

	draw_arc(center, radius, start, end, 128, COLOR_TRACK, thickness, true)
	draw_arc(center, radius, red_start, end, 64, COLOR_REDLINE, thickness, true)

	var progress := clampf((_display_rpm - _idle_rpm) / maxf(_redline_rpm - _idle_rpm, 1.0), 0.0, 1.0)
	var fill_end := start + sweep * progress
	if fill_end > start + 0.001:
		draw_arc(center, radius, start, fill_end, 96, COLOR_FILL_GLOW, thickness + 8.0, true)
		draw_arc(center, radius, start, fill_end, 96, COLOR_FILL, thickness, true)

	_draw_ticks(center, inner, start, sweep)
	_draw_needle(center, inner, start, sweep, progress)
	_draw_hub(center)
	if _display_rpm >= _redline_rpm:
		_draw_shift_light(center, radius, red_mid)

func _draw_ticks(center: Vector2, inner: float, start: float, sweep: float) -> void:
	var step := 1.0 / float((MAJOR_TICKS - 1) * MINOR_PER_MAJOR)
	for i in range(MAJOR_TICKS):
		var p := float(i) / float(MAJOR_TICKS - 1)
		var ang := start + sweep * p
		var dir := Vector2.from_angle(ang)
		_draw_tick(center, dir, inner - 2.0, inner - 16.0, COLOR_TICK, 2.0)
		var rpm := _idle_rpm + p * (_redline_rpm - _idle_rpm)
		var text := "%d" % int(round(rpm / 1000.0))
		var pos := center + dir * (inner - 38.0)
		draw_string(_font, pos - Vector2(24.0, 0.0), text, HORIZONTAL_ALIGNMENT_CENTER, 48.0, 14, COLOR_TICK)
		if i < MAJOR_TICKS - 1:
			for j in range(1, MINOR_PER_MAJOR):
				var mang := start + sweep * (p + float(j) * step)
				_draw_tick(center, Vector2.from_angle(mang), inner - 2.0, inner - 10.0, Color(COLOR_TICK, 0.5), 1.5)

func _draw_tick(center: Vector2, dir: Vector2, from_r: float, to_r: float, color: Color, width: float) -> void:
	draw_line(center + dir * from_r, center + dir * to_r, color, width, true)

func _draw_needle(center: Vector2, inner: float, start: float, sweep: float, progress: float) -> void:
	var ang := start + sweep * progress
	var dir := Vector2.from_angle(ang)
	var perp := Vector2.from_angle(ang + PI * 0.5)
	var tip := center + dir * (inner - 4.0)
	var base := center + dir * 12.0
	draw_colored_polygon(PackedVector2Array([
		base + perp * 7.0,
		tip + perp * 1.5,
		tip - perp * 1.5,
		base - perp * 7.0,
	]), COLOR_NEEDLE)

func _draw_hub(center: Vector2) -> void:
	draw_circle(center, 12.0, Color(0.07, 0.09, 0.16))
	draw_arc(center, 12.0, 0.0, TAU, 24, Color(0.92, 0.96, 1.0, 0.65), 2.0, true)
	draw_circle(center, 5.0, COLOR_NEEDLE)

func _draw_shift_light(center: Vector2, radius: float, red_mid: float) -> void:
	var pulse := 0.45 + 0.45 * sin(Time.get_ticks_msec() * 0.015)
	var pos := center + Vector2.from_angle(red_mid) * (radius + 10.0)
	draw_circle(pos, 5.0 + pulse * 2.0, Color(1.0, 0.22, 0.15, 0.35 + pulse * 0.4))
	draw_arc(center, radius + 8.0, red_mid - 0.35, red_mid + 0.35, 16, Color(1.0, 0.3, 0.2, 0.2 + pulse * 0.3), 4.0, true)