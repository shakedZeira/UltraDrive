class_name SpeedOverlay
extends Control

## Speed vignette + streak overlay drawn on the HUD. Opacity rises monotonically
## with the player car's speed_kmh (the intensity math is a static pure
## function); self-pumps from VehicleManager.get_player_car(). Headless-safe:
## the display won't render off a real renderer but the intensity math still
## runs, so tests assert behaviour not pixels.

const FULL_SPEED_KMH := 220.0
const MAX_ALPHA := 0.32
const STREAK_ALPHA := 0.15
const EDGE_BAND_MIN := 28.0
const EDGE_BAND_MAX := 150.0
const STREAK_COUNT := 6

var _speed_kmh := 0.0
var _last_draw_intensity := -1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if DisplayServer.get_name() == "headless":
		set_process(false)

func _process(_delta: float) -> void:
	var car := VehicleManager.get_player_car()
	_speed_kmh = car.get_speed_kmh() if car != null else 0.0
	_redraw_if_visible_change()

## Public seam used by the HUD and the tests.
func set_speed_kmh(speed_kmh: float) -> void:
	_speed_kmh = maxf(speed_kmh, 0.0)
	_redraw_if_visible_change()

func get_speed_kmh() -> float:
	return _speed_kmh

## Pure, monotonic opacity for a given speed. Clamped to [0,1]; the vignette
## reaches full strength at FULL_SPEED_KMH and stays pinned there higher.
static func vignette_intensity(speed_kmh: float) -> float:
	return clampf(speed_kmh / FULL_SPEED_KMH, 0.0, 1.0)

func get_intensity() -> float:
	return vignette_intensity(_speed_kmh)

func _redraw_if_visible_change() -> void:
	var intensity := get_intensity()
	if absf(intensity - _last_draw_intensity) >= 0.01:
		_last_draw_intensity = intensity
		queue_redraw()

func _draw() -> void:
	var intensity := get_intensity()
	if intensity <= 0.001:
		return
	var band := lerpf(EDGE_BAND_MIN, EDGE_BAND_MAX, intensity)
	_draw_edge_bands(band, MAX_ALPHA * intensity)
	_draw_streaks(band, STREAK_ALPHA * intensity)

func _draw_edge_bands(band: float, alpha: float) -> void:
	var color := Color(0.0, 0.0, 0.0, alpha)
	var left := Rect2(0.0, 0.0, band, size.y)
	var right := Rect2(size.x - band, 0.0, band, size.y)
	var top := Rect2(0.0, 0.0, size.x, band)
	var bottom := Rect2(0.0, size.y - band, size.x, band)
	draw_rect(left, color)
	draw_rect(right, color)
	draw_rect(top, color)
	draw_rect(bottom, color)

func _draw_streaks(band: float, alpha: float) -> void:
	if STREAK_COUNT <= 0:
		return
	var color := Color(0.9, 0.95, 1.0, alpha)
	var spacing := band / float(STREAK_COUNT)
	for i in range(1, STREAK_COUNT + 1):
		var y := band * 0.25 + float(i) * spacing
		var x0 := band
		var x1 := size.x - band
		draw_line(Vector2(x0, y), Vector2(x1, y), color, 2.0, true)
		draw_line(Vector2(x0, size.y - y), Vector2(x1, size.y - y), color, 2.0, true)