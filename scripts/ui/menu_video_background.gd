# scripts/ui/menu_video_background.gd
class_name MenuVideoBackground
extends Control

## Main-menu background video layer. Plays the recorded open-world clips
## (MenuVideoPlaylist.CANDIDATE_CLIPS) behind the menu, one VideoStreamPlayer at
## a time, advancing on `finished`; a single resolved clip loops natively.
##
## Never a black screen: this Control is a transparent clip wrapper. The
## always-visible gradient `Backdrop` TextureRect sits UNDER this node in
## main_menu.tscn (D3), and the `Scrim` ColorRect sits over it (D4). When no
## clip exists on disk -- the state today, before any clip is recorded -- this
## node goes inert (player hidden, processing off) and the gradient shows.
##
## COVER, not letterbox: VideoStreamPlayer has no aspect control in Godot 4 and
## `expand` only stretches to the rect, so the player is sized to cover the
## viewport (overflow clipped by clip_contents) instead of distorting. The clip
## aspect is only known once the first frame decodes, hence the poll loop
## (mirrors scripts/ui/intro_video.gd).
##
## PROCESS_MODE_ALWAYS: entering the menu from the pause menu can leave the tree
## paused (GameState.change_scene clears is_paused, not get_tree().paused), and
## a pausable Control would freeze the clip behind the menu.

## Aspect assumed until the first decoded frame reports the real one. The clips
## are 1280x720, so this is exact for them and only ever a one-frame placeholder.
const FALLBACK_ASPECT: float = 16.0 / 9.0

## Belt-and-braces silence: the clips are recorded silent (and -an'd in post),
## but the player is muted anyway so a stray audio track can never leak.
const SILENT_VOLUME_DB: float = -80.0

@onready var video: VideoStreamPlayer = $VideoStreamPlayer

var _playlist: MenuVideoPlaylist = MenuVideoPlaylist.new()
var _index: int = 0
var _video_aspect: float = 0.0
var _playing: bool = false

func _ready() -> void:
	# The menu can be reached with get_tree().paused left true by the pause
	# menu's quit-to-menu path; keep the clip alive regardless.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_playlist = MenuVideoPlaylist.new(MenuVideoPlaylist.resolve(
		MenuVideoPlaylist.CANDIDATE_CLIPS,
		func(path: String) -> bool: return ResourceLoader.exists(path)))
	if video == null or _playlist.is_empty():
		_go_inert()
		return
	_playing = true
	video.expand = true
	video.volume_db = SILENT_VOLUME_DB
	video.loop = _playlist.is_single()
	if not video.finished.is_connected(_on_finished):
		video.finished.connect(_on_finished)
	get_viewport().size_changed.connect(_on_viewport_resized)
	_start_clip(0)

func _process(_delta: float) -> void:
	# Poll only until the first decoded frame reports the clip's real aspect.
	if _video_aspect > 0.0 or video == null:
		set_process(false)
		return
	var tex: Texture2D = video.get_video_texture()
	if tex == null:
		return
	var tex_size: Vector2 = tex.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	_video_aspect = tex_size.x / tex_size.y
	_cover()
	set_process(false)

## Empty-playlist path: leave the gradient Backdrop visible and stop working.
func _go_inert() -> void:
	if video != null:
		video.visible = false
	set_process(false)

## Assign and start the clip at `index`. Re-arms the aspect poll so the COVER
## rect is recomputed for the new clip.
func _start_clip(index: int) -> void:
	_index = index
	var path: String = _playlist.get_clip(index)
	if path.is_empty():
		_go_inert()
		return
	var stream: Resource = load(path)
	if stream == null:
		_go_inert()
		return
	video.stream = stream as VideoStream
	video.visible = true
	video.loop = _playlist.is_single()
	_video_aspect = 0.0
	set_process(true)
	video.play()
	_cover()

## Size and centre the player so the clip COVERS the viewport with its own
## aspect (scale = max needed to fill; overflow is clipped by clip_contents).
func _cover() -> void:
	if video == null:
		return
	var screen: Vector2 = get_viewport_rect().size
	if screen.x <= 0.0 or screen.y <= 0.0:
		return
	var aspect: float = _video_aspect if _video_aspect > 0.0 else FALLBACK_ASPECT
	var cover_h: float = maxf(screen.y, screen.x / aspect)
	var cover_w: float = cover_h * aspect
	video.size = Vector2(cover_w, cover_h)
	video.position = ((screen - Vector2(cover_w, cover_h)) * 0.5).floor()

func _on_finished() -> void:
	if not _playing or _playlist.is_empty():
		return
	_start_clip(_playlist.next_index(_index))

func _on_viewport_resized() -> void:
	_cover()
