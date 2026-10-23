# scripts/ui/music_toast.gd
class_name MusicToast
extends CanvasLayer

## FreeRoam now-playing toast (cover, title, artist, station chip, progress bar).
## Its OWN CanvasLayer (39: above the HUD 0 and the pause menu 10, just under the
## speed-trap banner 40), instanced from open_world_root.tscn - the same shape as
## SpeedTrapHUD: PURE timing statics, a driven advance(delta), and _process
## switched OFF at rest. No Tween. Hidden while the tree is paused (it would
## otherwise float over the pause menu).

const LAYER := 39
const RISE_S := 0.25
const HOLD_S := 4.0
const FALL_S := 0.5
const SLIDE_PX := 24.0

@onready var _card: Panel = get_node_or_null("Card") as Panel
@onready var _cover: TextureRect = get_node_or_null("Card/Cover") as TextureRect
@onready var _letter: Label = get_node_or_null("Card/Cover/Letter") as Label
@onready var _title: Label = get_node_or_null("Card/Title") as Label
@onready var _artist: Label = get_node_or_null("Card/Artist") as Label
@onready var _station: Label = get_node_or_null("Card/Station") as Label
@onready var _accent: ColorRect = get_node_or_null("Card/Accent") as ColorRect
@onready var _bar_bg: ColorRect = get_node_or_null("Card/BarBg") as ColorRect
@onready var _bar: ColorRect = get_node_or_null("Card/BarBg/Bar") as ColorRect

var elapsed: float = 0.0
var showing: bool = false
var showing_track_id: String = ""
var hold_s: float = HOLD_S
var _rest_left: float = 20.0
var _wired: bool = false
var _service: Node = null
var _paused_probe: Callable = Callable()

# ---------------------------------------------------------------------------
# Pure timing.
# ---------------------------------------------------------------------------

static func total(hold: float = HOLD_S) -> float:
	return RISE_S + hold + FALL_S

## 0 at t <= 0, rises to 1 over RISE_S, holds, falls to 0, 0 after total().
static func toast_alpha(t: float, hold: float = HOLD_S) -> float:
	if t <= 0.0 or t >= total(hold):
		return 0.0
	if t < RISE_S:
		return t / RISE_S
	if t < RISE_S + hold:
		return 1.0
	return 1.0 - (t - RISE_S - hold) / FALL_S

## Horizontal slide offset in px: slides in from -SLIDE_PX (ease-out), rests at 0,
## drifts back to -SLIDE_PX / 2 while fading out.
static func toast_slide(t: float, hold: float = HOLD_S) -> float:
	if t <= 0.0:
		return -SLIDE_PX
	if t < RISE_S:
		var k := t / RISE_S
		return -SLIDE_PX * pow(1.0 - k, 3.0)
	if t < RISE_S + hold:
		return 0.0
	var f := clampf((t - RISE_S - hold) / FALL_S, 0.0, 1.0)
	return -SLIDE_PX * 0.5 * f

# ---------------------------------------------------------------------------
# Lifecycle.
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _card != null:
		_rest_left = _card.position.x
		_card.visible = false
	set_process(false)
	call_deferred("_wire")

## Connects to the MusicService autoload (idempotent; a no-op without it).
func _wire() -> void:
	if _wired or not is_inside_tree():
		return
	var svc := get_node_or_null("/root/MusicService")
	if svc == null:
		return
	bind(svc)

func bind(service: Node) -> void:
	if service == null or _wired:
		return
	_service = service
	_wired = true
	service.connect("track_changed", _on_track_changed)
	service.connect("station_changed", _on_station_changed)
	service.connect("notice", _on_notice)
	if service.has_signal("info_requested"):
		service.connect("info_requested", _on_track_changed)
	service.connect("cover_ready", _on_cover_ready)

func _enabled() -> bool:
	if _service != null:
		var s: Variant = _service.get("settings")
		if s is Dictionary and not bool(s.get("toast", true)):
			return false
	return true

func _on_track_changed(meta: Dictionary) -> void:
	show_track(meta)

func _on_station_changed(station_name: String, _station_id: String) -> void:
	show_text(station_name, "Radio station", "")

func _on_notice(title: String, subtitle: String) -> void:
	show_text(title, subtitle, "", true)

func _on_cover_ready(track_id: String, texture: Texture2D, accent: Color, generated: bool) -> void:
	if track_id != showing_track_id:
		return
	apply_cover(texture, accent, generated)

# ---------------------------------------------------------------------------
# Showing.
# ---------------------------------------------------------------------------

func show_track(meta: Dictionary) -> void:
	if not _enabled():
		return
	var album := String(meta.get("album", ""))
	var artist := String(meta.get("artist", ""))
	var sub := artist if album.is_empty() else "%s  -  %s" % [artist, album]
	showing_track_id = String(meta.get("id", ""))
	_set_labels(String(meta.get("title", "")), sub, String(meta.get("station_name", "")))
	if _letter != null:
		_letter.text = String(meta.get("title", "")).substr(0, 1).to_upper()
		_letter.visible = false
	if _cover != null:
		_cover.texture = null
	_start()

## Plain text card (station switch, volume, pause). `quick` shortens the hold.
func show_text(title: String, subtitle: String, station_name: String, quick: bool = false) -> void:
	if not _enabled():
		return
	showing_track_id = ""
	_set_labels(title, subtitle, station_name)
	if _letter != null:
		_letter.visible = false
	hold_s = 1.6 if quick else HOLD_S
	_start(quick)

func apply_cover(texture: Texture2D, accent: Color, generated: bool) -> void:
	if _cover != null:
		_cover.texture = texture
	if _letter != null:
		_letter.visible = generated
	if _accent != null:
		_accent.color = accent
	if _station != null:
		_station.add_theme_color_override("font_color", accent.lightened(0.35))

func _set_labels(title: String, sub: String, station_name: String) -> void:
	if _title != null:
		_title.text = title
	if _artist != null:
		_artist.text = sub
	if _station != null:
		_station.text = station_name.to_upper()

func _start(quick: bool = false) -> void:
	if not quick:
		hold_s = HOLD_S
	if _is_paused():
		return
	elapsed = 0.0
	showing = true
	if _card != null:
		_card.visible = true
	_apply()
	set_process(true)

func _process(delta: float) -> void:
	advance(delta)

## One driven step. Cancels (hides) while the tree is paused.
func advance(delta: float) -> void:
	if not showing:
		set_process(false)
		return
	if _is_paused():
		hide_now()
		return
	elapsed += delta
	if elapsed >= total(hold_s):
		hide_now()
		return
	_apply()

## True while the pause menu is up (tests may inject a probe).
func _is_paused() -> bool:
	if _paused_probe.is_valid():
		return bool(_paused_probe.call())
	return is_inside_tree() and get_tree().paused

func hide_now() -> void:
	showing = false
	elapsed = 0.0
	if _card != null:
		_card.visible = false
	set_process(false)

func _apply() -> void:
	if _card == null:
		return
	_card.modulate.a = toast_alpha(elapsed, hold_s)
	_card.position.x = _rest_left + toast_slide(elapsed, hold_s)
	if _bar != null and _bar_bg != null:
		var frac := 0.0
		if _service != null and _service.has_method("playback_fraction"):
			frac = float(_service.call("playback_fraction"))
		_bar.size.x = _bar_bg.size.x * clampf(frac, 0.0, 1.0)
