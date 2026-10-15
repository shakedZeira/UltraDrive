# tests/suites/test_intro_video.gd
extends GdUnitTestSuite

## Boot intro scene (run/main_scene): it instantiates, carries a VideoStreamPlayer
## auto-playing the transcoded Ogg Theora clip with a sane length, and its
## skip/end path targets the main menu through the project's own
## SceneTransition convention. Exercised headlessly WITHOUT add_child() so no
## video decode and no scene swap happens inside the unit test.

const IntroScene: PackedScene = preload("res://scenes/ui/intro_video.tscn")
const IntroScript: GDScript = preload("res://scripts/ui/intro_video.gd")

## ffprobe on the shipped source clip: 17.714 s. The bounds are wide enough for
## an encoder trim but fail a zero-length or truncated stream.
const EXPECTED_LENGTH_MIN: float = 16.0
const EXPECTED_LENGTH_MAX: float = 20.0

var _managed: Array = []

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	for obj in _managed:
		if obj is Node and is_instance_valid(obj):
			obj.free()
	_managed.clear()

func test_intro_scene_has_a_video_player_playing_a_real_theora_stream() -> void:
	var scene: Node = IntroScene.instantiate()
	_managed.append(scene)
	assert_that(scene).is_not_null()
	if scene == null:
		return
	var player := scene.get_node_or_null("VideoStreamPlayer") as VideoStreamPlayer
	assert_that(player).is_not_null()
	if player == null:
		return
	assert_that(player.stream).is_not_null()
	if player.stream == null:
		return
	assert_that(player.stream.get_class()).is_equal("VideoStreamTheora")
	assert_that(player.autoplay).is_true()
	var length: float = player.get_stream_length()
	assert_float(length).is_greater(EXPECTED_LENGTH_MIN)
	assert_float(length).is_less(EXPECTED_LENGTH_MAX)

func test_video_player_scales_the_clip_to_its_own_rect() -> void:
	# Regression guard: VideoStreamPlayer scales the clip to the control's rect
	# ONLY while `expand` is on. With it off Godot blits the clip at its native
	# pixel size into the rect's top-left corner, which is exactly what made the
	# intro look "not fullscreen" (a 1280x720 blit in a 1920x1080 screen).
	var scene: Node = IntroScene.instantiate()
	_managed.append(scene)
	var player := scene.get_node_or_null("VideoStreamPlayer") as VideoStreamPlayer
	assert_that(player).is_not_null()
	if player == null:
		return
	assert_that(player.expand).is_true()
	# A full-rect black backdrop sits behind the clip for the letterbox bars.
	assert_that(scene.get_node_or_null("Backdrop")).is_not_null()

func test_skip_and_end_paths_lead_to_the_main_menu() -> void:
	assert_that(IntroScript.DEST_SCENE_PATH).is_equal("res://scenes/ui/main_menu.tscn")
	var scene: Node = IntroScene.instantiate()
	_managed.append(scene)
	assert_that(scene.has_method("_leave_to_main_menu")).is_true()
	assert_that(scene.has_method("_unhandled_input")).is_true()

func test_boot_main_scene_is_the_intro() -> void:
	var configured: String = String(ProjectSettings.get_setting("application/run/main_scene", ""))
	assert_that(configured).is_equal("res://scenes/ui/intro_video.tscn")
