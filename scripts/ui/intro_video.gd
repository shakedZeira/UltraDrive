# scripts/ui/intro_video.gd
extends Control

## Boot intro: plays the attract video (Ogg Theora) scaled up to fill the screen,
## letterboxed (black bars) instead of stretched when the screen is not the
## clip's aspect, and then hands off to the main menu. Any key / mouse / gamepad
## press skips immediately; the clip ending skips too. Both paths use the
## project's existing fade convention (SceneTransition.flash_to_scene ->
## GameState.change_scene) so the quality preset GameState re-applies on every
## scene change keeps working.

## Destination after the intro: input, skip, or the clip's natural end.
const DEST_SCENE_PATH: String = "res://scenes/ui/main_menu.tscn"

## How long the "skip" hint stays fully visible before it fades out.
const HINT_VISIBLE_SECONDS: float = 3.0
const HINT_FADE_SECONDS: float = 1.0

## Aspect used until the first decoded frame reports the clip's real one. The
## shipped clip is 1280x720, so this is exact for it and is only ever a
## one-frame placeholder.
const FALLBACK_ASPECT: float = 16.0 / 9.0

@onready var video: VideoStreamPlayer = $VideoStreamPlayer
@onready var skip_hint: Label = %SkipHint

var _leaving: bool = false
var _video_aspect: float = 0.0

func _ready() -> void:
	video.finished.connect(_leave_to_main_menu)
	# VideoStreamPlayer scales the clip to its own rect ONLY while `expand` is
	# on. With it off Godot blits the clip at its native pixel size at the
	# rect's top-left corner (a 1280x720 clip in a 1920x1080 screen looked
	# "not fullscreen"). So: expand on, and give the player a rect that covers
	# as much of the screen as the clip's aspect allows.
	video.expand = true
	get_viewport().size_changed.connect(_fit_video)
	_fit_video()
	_fade_out_hint()

func _process(_delta: float) -> void:
	if _video_aspect > 0.0:
		return
	var tex: Texture2D = video.get_video_texture()
	if tex == null:
		return
	var tex_size: Vector2 = tex.get_size()
	if tex_size.x > 0.0 and tex_size.y > 0.0:
		_video_aspect = tex_size.x / tex_size.y
		_fit_video()
		set_process(false)

## Size the player to the largest centred rect that both fills the screen and
## keeps the clip's aspect ratio, so a non-matching screen letterboxes (the
## black Backdrop shows through) rather than distorting the picture.
func _fit_video() -> void:
	if video == null:
		return
	var screen: Vector2 = get_viewport_rect().size
	if screen.x <= 0.0 or screen.y <= 0.0:
		return
	var aspect: float = _video_aspect if _video_aspect > 0.0 else FALLBACK_ASPECT
	var target: Vector2 = screen
	if not is_equal_approx(screen.x / screen.y, aspect):
		var fit_height: float = screen.x / aspect
		if fit_height > screen.y:
			fit_height = screen.y
		target = Vector2(floor(fit_height * aspect), floor(fit_height))
	video.size = target
	video.position = ((screen - target) * 0.5).floor()

func _unhandled_input(event: InputEvent) -> void:
	if _leaving or not event.is_pressed():
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		_leave_to_main_menu()

func _fade_out_hint() -> void:
	if skip_hint == null:
		return
	var tween := create_tween()
	tween.tween_interval(HINT_VISIBLE_SECONDS)
	tween.tween_property(skip_hint, "modulate:a", 0.0, HINT_FADE_SECONDS)

func _leave_to_main_menu() -> void:
	if _leaving:
		return
	_leaving = true
	if video != null:
		video.stop()
	SceneTransition.flash_to_scene(DEST_SCENE_PATH)
