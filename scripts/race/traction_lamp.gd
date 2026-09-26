# scripts/race/traction_lamp.gd
class_name TractionLamp
extends Control

## The HUD "cone" traction-loss lamp that lives inside the gauge cluster: an
## amber triangle with an exclamation stem that ramps amber -> red with the slip
## severity WheelspinGauge computes, plus a soft pulse and a severity-scaled
## halo so a light slip is a whisper and a committed spin blazes. The lamp hides
## itself entirely (visible = false) whenever the car is planted, which keeps
## the cluster's clean look exactly as it was before this feature.
##
## Presentation only — it consumes a severity float and never reads physics
## itself, so the HUD stays the single place the wheels are polled.

const PULSE_HZ := 3.0

var _severity: float = 0.0
var _pulse: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

## severity 0 = planted (lamp hidden), > 0 = traction lost (lamp lit).
func set_severity(severity: float) -> void:
	var next := clampf(severity, 0.0, 1.0)
	if is_equal_approx(next, _severity):
		return
	_severity = next
	visible = _severity > 0.0
	queue_redraw()

func get_severity() -> float:
	return _severity

## A lit lamp pulses, so it redraws while it is on and costs nothing while the
## car is planted.
func _process(delta: float) -> void:
	if not visible:
		return
	_pulse = fmod(_pulse + delta * PULSE_HZ, 1.0)
	queue_redraw()

func _draw() -> void:
	var color := WheelspinGauge.lamp_color(_severity)
	var pulse := 0.5 + 0.5 * sin(_pulse * TAU)
	var lit := Color(color.r, color.g, color.b, (0.72 + 0.28 * pulse) * color.a)
	var shell := Color(color.r * 0.35, color.g * 0.35, color.b * 0.35, lit.a * 0.5)
	var center := size * 0.5
	var half := minf(size.x, size.y) * 0.42
	var top := center - Vector2(0.0, half)
	var bottom_l := center + Vector2(-half * 0.92, half * 0.8)
	var bottom_r := center + Vector2(half * 0.92, half * 0.8)

	draw_circle(center, half * (1.25 + 0.5 * _severity), Color(lit.r, lit.g, lit.b, 0.16 * _severity))
	draw_colored_polygon(PackedVector2Array([top, bottom_r, bottom_l]), lit)
	draw_polyline(PackedVector2Array([top, bottom_l, bottom_r, top]), shell, 2.0, true)
	draw_line(center - Vector2(0.0, half * 0.12), center + Vector2(0.0, half * 0.34), shell, 3.0, true)
	draw_circle(center + Vector2(0.0, half * 0.5), 1.8, shell)
