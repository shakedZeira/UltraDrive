# scripts/ui/speed_trap_hud.gd
class_name SpeedTrapHUD
extends CanvasLayer

## Free-roam speed-trap presentation: a one-shot full-screen flash plus a
## bottom-centre banner reading the crossing speed and the personal best.
##
## Deliberately its OWN CanvasLayer scene, not part of hud.tscn: the banner and
## flash are free-roam furniture with their own z-order, and the race HUD is
## owned by race_ui.gd (whose FINISH overlay sits at layer 0). Keeping them
## apart means neither can disturb the other.
##
## Timing is PURE and driven, never a Tween/SceneTreeTimer (which cannot be
## advanced deterministically headless). flash_alpha()/banner_alpha() are
## statics; advance(delta) moves one driven step and is what _process calls.
## Processing is switched OFF at rest and back on only while a banner/flash is
## in flight, so an idle world pays nothing (the SpeedTrapVisuals.tick()
## convention).
##
## Race suppression is belt-and-suspenders: the crossing emits nothing while a
## race is active (D14) and play()/advance() also refuse/cancel, so the FINISH
## banner and a speed-trap banner can never coexist.

## Above the base HUD (0) and the pause menu (10) so the banner is not covered
## where the cluster backdrop and the minimap graze on narrow windows; below the
## photo filter (50), the scene transition (100) and the loading screen (128).
const LAYER := 40

## Flash: warm white "flashbulb", rises fast, falls slower.
const FLASH_COLOR := Color(1.0, 0.96, 0.88)
const FLASH_RISE := 0.06
const FLASH_FALL := 0.30
const FLASH_PEAK_ALPHA := 0.5

## Banner: rise, hold long enough to read a speed + best, slide/fade out.
const BANNER_RISE := 0.15
const BANNER_HOLD := 1.8
const BANNER_FALL := 0.45

@onready var _flash: ColorRect = $Flash
@onready var _banner: Panel = $Banner
@onready var _label: Label = $Banner/BannerLabel

var _t := 0.0
var _playing := false
var _wired := false

# ---------------------------------------------------------------------------
# Pure timing (no state) — the whole testable core of the presentation layer.
# ---------------------------------------------------------------------------

static func flash_total() -> float:
	return FLASH_RISE + FLASH_FALL

static func banner_total() -> float:
	return BANNER_RISE + BANNER_HOLD + BANNER_FALL

## Flash alpha envelope: 0 at t <= 0, rising to FLASH_PEAK_ALPHA at
## t == FLASH_RISE, falling back to 0 at t == flash_total(), 0 after.
static func flash_alpha(elapsed: float) -> float:
	if elapsed <= 0.0 or elapsed >= flash_total():
		return 0.0
	if elapsed < FLASH_RISE:
		return FLASH_PEAK_ALPHA * (elapsed / FLASH_RISE)
	return FLASH_PEAK_ALPHA * (1.0 - (elapsed - FLASH_RISE) / FLASH_FALL)

## Banner alpha envelope: rise to 1, hold at 1, fall back to 0.
static func banner_alpha(elapsed: float) -> float:
	if elapsed <= 0.0 or elapsed >= banner_total():
		return 0.0
	if elapsed < BANNER_RISE:
		return elapsed / BANNER_RISE
	if elapsed < BANNER_RISE + BANNER_HOLD:
		return 1.0
	return 1.0 - (elapsed - BANNER_RISE - BANNER_HOLD) / BANNER_FALL

# ---------------------------------------------------------------------------
# Lifecycle.
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = LAYER
	if _flash != null:
		_flash.visible = false
	if _banner != null:
		_banner.visible = false
	set_process(false)
	# The HUD precedes the crossing in the open-world root, so at this instant
	# the crossing has not joined its group yet. One deferred frame later it has.
	call_deferred("_wire")

## Resolves the crossing from its group and connects. Idempotent, and safe to
## call when there is no crossing (a circuit, or a bare test instance).
func _wire() -> void:
	if _wired or not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var crossing := tree.get_first_node_in_group(SpeedTrapCrossing.GROUP_NAME)
	if crossing == null:
		return
	bind(crossing)

## Explicit wiring hook (the tests use it; _wire() resolves the group for the
## shipped scene). Connecting twice is a no-op.
func bind(crossing: Node) -> void:
	if crossing == null or not is_instance_valid(crossing):
		return
	if not crossing.has_signal(SpeedTrapCrossing.SIGNAL_NAME):
		return
	if not crossing.is_connected(SpeedTrapCrossing.SIGNAL_NAME, _on_crossed):
		crossing.connect(SpeedTrapCrossing.SIGNAL_NAME, _on_crossed)
	_wired = true

func _on_crossed(_trap_id: String, speed_kmh: float, best_kmh: float, is_new_best: bool) -> void:
	play(speed_kmh, best_kmh, is_new_best)

## Starts (or restarts) the one-shot flash + banner. Free-roam only.
func play(speed_kmh: float, best_kmh: float, is_new_best: bool) -> void:
	if RaceManager.is_race_active:
		return
	if _label != null:
		_label.text = SpeedTrapRecords.banner_text(speed_kmh, best_kmh, is_new_best)
	if _flash != null:
		_flash.visible = true
		_flash.color = Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, 0.0)
	if _banner != null:
		_banner.visible = true
		_banner.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_t = 0.0
	_playing = true
	set_process(true)

func _process(delta: float) -> void:
	advance(delta)

## One driven animation step; returns whether it is still playing. Switching
## processing off here (not only in _process) leaves a driven advance() in
## exactly the state a real frame would have left it in.
func advance(delta: float) -> bool:
	if not _playing:
		set_process(false)
		return false
	if RaceManager.is_race_active:
		_cancel()
		return false
	_t += delta
	if _flash != null:
		var fa := flash_alpha(_t)
		_flash.visible = fa > 0.0
		_flash.color = Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, fa)
	if _banner != null:
		var ba := banner_alpha(_t)
		_banner.visible = ba > 0.0
		_banner.modulate = Color(1.0, 1.0, 1.0, ba)
	if _t >= banner_total():
		_cancel()
		return false
	return true

func _cancel() -> void:
	if _flash != null:
		_flash.visible = false
	if _banner != null:
		_banner.visible = false
	_t = 0.0
	_playing = false
	set_process(false)

# ---------------------------------------------------------------------------
# Test surface.
# ---------------------------------------------------------------------------

func is_playing() -> bool:
	return _playing

func elapsed() -> float:
	return _t

func is_wired() -> bool:
	return _wired
