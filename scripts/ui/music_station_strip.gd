# scripts/ui/music_station_strip.gd
class_name MusicStationStrip
extends CanvasLayer

## FreeRoam radio station strip. Shown while the gamepad Back button is HELD
## (volume / station chord, see MusicInput) and for a moment after every station
## change (RB chord, Tab, settings). A row of station chips with the current one
## highlighted, plus a one-line control hint.
##
## Same shape as MusicToast / SpeedTrapHUD: its own CanvasLayer (38, under the
## toast at 39), PURE timing statics, a driven advance(delta), _process off at
## rest, no Tween, hidden while the tree is paused. Built in code so the scene
## stays a single node; instanced from open_world_root.tscn.

const LAYER := 38
## Back must be held this long before the strip appears, so a Back TAP (pause)
## does not flash it.
const HOLD_TO_SHOW_S := 0.25
const RISE_S := 0.15
const FALL_S := 0.35
## How long it stays after a station change when Back is not held.
const LINGER_S := 2.5
const MAX_CHIPS := 5
const TOP_PX := 104.0

var visible_alpha: float = 0.0
var held: bool = false
var held_for: float = 0.0
var linger_left: float = 0.0
var showing: bool = false
var _service: Node = null
var _wired: bool = false
var _panel: PanelContainer = null
var _row: HBoxContainer = null
var _hint: Label = null
var _paused_probe: Callable = Callable()

# ---------------------------------------------------------------------------
# Pure helpers.
# ---------------------------------------------------------------------------

## Indices of the stations to show: at most `size`, a window centred on `current`
## (clamped to the list ends, so the chip count stays constant).
static func window(count: int, current: int, size: int = MAX_CHIPS) -> Array[int]:
	var out: Array[int] = []
	if count <= 0:
		return out
	var n := mini(count, maxi(size, 1))
	var start := clampi(current - n / 2, 0, count - n)
	for i in range(n):
		out.append(start + i)
	return out

## True when the strip should be wanted at all: Back held long enough, or a
## station change is still lingering.
static func wanted(is_held: bool, held_s: float, linger_s: float) -> bool:
	return (is_held and held_s >= HOLD_TO_SHOW_S) or linger_s > 0.0

## One fade step: alpha moves toward 1 while wanted (RISE_S), toward 0 otherwise (FALL_S).
static func step_alpha(alpha: float, want: bool, delta: float) -> float:
	if want:
		return clampf(alpha + delta / RISE_S, 0.0, 1.0)
	return clampf(alpha - delta / FALL_S, 0.0, 1.0)

# ---------------------------------------------------------------------------
# Lifecycle.
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	set_process(false)
	call_deferred("_wire")

func _build() -> void:
	var holder := Control.new()
	holder.name = "Holder"
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.09, 0.86)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.offset_top = TOP_PX
	_panel.visible = false
	holder.add_child(_panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)
	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 8)
	box.add_child(_row)
	_hint = Label.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.text = "Vol  D-pad Up / Down      Station  RB      (Back held)"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 0.85))
	box.add_child(_hint)

func _wire() -> void:
	if _wired or not is_inside_tree():
		return
	var svc := get_node_or_null("/root/MusicService")
	if svc != null:
		bind(svc)

func bind(service: Node) -> void:
	if service == null or _wired:
		return
	_service = service
	_wired = true
	service.connect("chord_changed", _on_chord_changed)
	service.connect("station_changed", _on_station_changed)

func _on_chord_changed(is_held: bool) -> void:
	held = is_held
	held_for = 0.0
	if is_held:
		set_process(true)

func _on_station_changed(_station_name: String, _station_id: String) -> void:
	if _is_paused():
		return
	linger_left = LINGER_S
	if showing:
		_rebuild_chips()
	set_process(true)

# ---------------------------------------------------------------------------
# Driven step.
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if _is_paused():
		_hide_now()
		return
	if held:
		held_for += delta
	if linger_left > 0.0:
		linger_left = maxf(linger_left - delta, 0.0)
	var want := wanted(held, held_for, linger_left)
	if want and not showing:
		showing = true
		visible_alpha = 0.0
		_rebuild_chips()
		if _panel != null:
			_panel.visible = true
	if showing:
		visible_alpha = step_alpha(visible_alpha, want, delta)
		if _panel != null:
			_panel.modulate.a = visible_alpha
		if not want and visible_alpha <= 0.0:
			_hide_now()
	elif not held and linger_left <= 0.0:
		set_process(false)

func _hide_now() -> void:
	showing = false
	visible_alpha = 0.0
	linger_left = 0.0
	if _is_paused():
		held = false
	if _panel != null:
		_panel.visible = false
	set_process(held and not _is_paused())

func _is_paused() -> bool:
	if _paused_probe.is_valid():
		return bool(_paused_probe.call())
	return is_inside_tree() and get_tree().paused

## Rebuilds the chip row from the live station list (cheap: <= MAX_CHIPS labels).
func _rebuild_chips() -> void:
	if _row == null:
		return
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	if _service == null:
		return
	var lib: Variant = _service.get("library")
	var cur: Variant = _service.get("station")
	if lib == null:
		return
	var list: Array = lib.call("playable_stations")
	var at := 0
	for i in range(list.size()):
		if cur != null and list[i].id == cur.id:
			at = i
	for idx in window(list.size(), at):
		var st: MusicStation = list[idx]
		var chip := Label.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.text = st.display_name
		chip.custom_minimum_size = Vector2(96, 0)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		chip.clip_text = true
		if idx == at:
			chip.add_theme_font_size_override("font_size", 20)
			chip.add_theme_color_override("font_color", st.color.lightened(0.3))
		else:
			chip.add_theme_font_size_override("font_size", 15)
			chip.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9, 0.6))
		_row.add_child(chip)
