# tests/suites/test_menu_video_background.gd
extends GdUnitTestSuite

## Main-menu video background (plan docs/plans/main_menu_video_bg_plan.md §3A):
## the playlist logic is pure and file-free, the menu scene ships the always-
## safe structure (gradient Backdrop first, inert player, scrim on top), and
## the boot flow is untouched. Exercised headlessly WITHOUT add_child() so no
## video decode and no menu _ready side effects happen inside the unit test —
## every test here passes with ZERO .ogv clips on disk (the shipped state).

const MenuScene: PackedScene = preload("res://scenes/ui/main_menu.tscn")
const MenuScript: GDScript = preload("res://scripts/ui/main_menu.gd")
const MenuBgScript: GDScript = preload("res://scripts/ui/menu_video_background.gd")

## Follow-up clip gate (test 7): bounds wide enough for an encoder trim but
## failing a zero-length or truncated stream (mirrors test_intro_video).
const CLIP_LENGTH_MIN: float = 12.0
const CLIP_LENGTH_MAX: float = 22.0

## The six button destinations main_menu.gd must still target — five scene
## paths and the quit handler — so the video layer cannot silently decouple
## the menu from its flows.
const MENU_DESTINATIONS: Array[String] = [
	"res://scenes/ui/track_select.tscn",
	"res://scenes/world/open_world_root.tscn",
	"res://scenes/ui/garage.tscn",
	"res://scenes/test/test_track.tscn",
	"res://scenes/ui/settings_menu.tscn",
	"get_tree().quit()",
]

var _managed: Array = []

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	for obj in _managed:
		if obj is Node and is_instance_valid(obj):
			obj.free()
	_managed.clear()

func test_playlist_resolves_only_existing_clips() -> void:
	var candidates: Array[String] = ["a.ogv", "b.ogv", "c.ogv"]
	var found: Array[String] = MenuVideoPlaylist.resolve(
		candidates, func(path: String) -> bool: return path == "b.ogv")
	assert_that(found.size()).is_equal(1)
	assert_that(found[0]).is_equal("b.ogv")
	# The current tree: nothing exists -> empty playlist, gradient-only menu.
	var none: Array[String] = MenuVideoPlaylist.resolve(
		candidates, func(_path: String) -> bool: return false)
	assert_that(none.is_empty()).is_true()

func test_playlist_cycles_and_wraps() -> void:
	var names: Array[String] = ["a", "b", "c"]
	var three := MenuVideoPlaylist.new(names)
	assert_that(three.count()).is_equal(3)
	assert_that(three.is_empty()).is_false()
	assert_that(three.is_single()).is_false()
	assert_that(three.next_index(0)).is_equal(1)
	assert_that(three.next_index(1)).is_equal(2)
	assert_that(three.next_index(2)).is_equal(0)
	var only: Array[String] = ["solo"]
	var one := MenuVideoPlaylist.new(only)
	assert_that(one.is_single()).is_true()
	assert_that(one.next_index(0)).is_equal(0)
	var empty: Array[String] = []
	var none := MenuVideoPlaylist.new(empty)
	assert_that(none.is_empty()).is_true()
	assert_that(none.next_index(0)).is_equal(-1)

func test_main_menu_has_a_background_layer() -> void:
	var scene: Node = MenuScene.instantiate()
	_managed.append(scene)
	assert_that(scene).is_not_null()
	if scene == null:
		return
	var bg := scene.get_node_or_null("MenuVideoBackground") as Control
	assert_that(bg).is_not_null()
	if bg == null:
		return
	assert_that(bg.script).is_equal(MenuBgScript)
	assert_that(bg.get_node_or_null("VideoStreamPlayer")).is_not_null()
	assert_that(scene.get_node_or_null("Backdrop")).is_not_null()
	assert_that(scene.get_node_or_null("Scrim")).is_not_null()
	assert_that(MenuVideoPlaylist.CANDIDATE_CLIPS.size()).is_greater_equal(2)

func test_background_is_inert_without_clips() -> void:
	# The resolve-empty path (no .ogv on disk) yields nothing, and the scene
	# ships with the player hidden so the gradient Backdrop — the FIRST child —
	# is what the menu shows. Fallback never black-screens.
	var none: Array[String] = MenuVideoPlaylist.resolve(
		MenuVideoPlaylist.CANDIDATE_CLIPS, func(_path: String) -> bool: return false)
	assert_that(none.is_empty()).is_true()
	var scene: Node = MenuScene.instantiate()
	_managed.append(scene)
	var bg := scene.get_node_or_null("MenuVideoBackground") as Control
	assert_that(bg).is_not_null()
	if bg == null:
		return
	assert_that(String(scene.get_child(0).name)).is_equal("Backdrop")
	var player := bg.get_node_or_null("VideoStreamPlayer") as VideoStreamPlayer
	assert_that(player).is_not_null()
	if player == null:
		return
	assert_that(player.stream).is_null()
	assert_that(player.visible).is_false()

func test_background_covers_and_is_always_processing() -> void:
	var scene: Node = MenuScene.instantiate()
	_managed.append(scene)
	var bg := scene.get_node_or_null("MenuVideoBackground") as Control
	assert_that(bg).is_not_null()
	if bg == null:
		return
	assert_that(bg.clip_contents).is_true()
	assert_that(bg.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	assert_that(bg.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	var player := bg.get_node_or_null("VideoStreamPlayer") as VideoStreamPlayer
	assert_that(player).is_not_null()
	if player == null:
		return
	assert_that(player.expand).is_true()
	# Silent-by-construction: the clips are recorded silent and -an'd in post,
	# and the player is muted anyway so a stray track can never leak.
	assert_float(player.volume_db).is_less_equal(-60.0)

func test_menu_still_reaches_intro_boot() -> void:
	# Boot guard: the video layer is additive. main_scene still boots the intro
	# and main_menu.gd still targets all six button flows.
	var configured: String = String(ProjectSettings.get_setting("application/run/main_scene", ""))
	assert_that(configured).is_equal("res://scenes/ui/intro_video.tscn")
	var source: String = MenuScript.source_code
	for destination: String in MENU_DESTINATIONS:
		assert_that(destination in source).is_true()
	var scene: Node = MenuScene.instantiate()
	_managed.append(scene)
	var pressed: int = 0
	for connection: Dictionary in scene.get_incoming_connections():
		if String(connection["signal"].get_name()) == "pressed":
			pressed += 1
	assert_that(pressed).is_equal(6)

func test_recorded_clips_are_sane_theora_once_present() -> void:
	# Follow-up gate from the plan §4: once clips ship, every resolved candidate
	# must be a real Theora stream of sane length. With zero clips on disk —
	# the state this suite must stay green in — the loop body never runs.
	for path: String in MenuVideoPlaylist.CANDIDATE_CLIPS:
		if not ResourceLoader.exists(path):
			continue
		var stream: Resource = ResourceLoader.load(path)
		assert_that(stream).is_not_null()
		if stream == null:
			return
		assert_that(stream.get_class()).is_equal("VideoStreamTheora")
		var player := VideoStreamPlayer.new()
		_managed.append(player)
		player.stream = stream as VideoStream
		var length: float = player.get_stream_length()
		assert_float(length).is_greater(CLIP_LENGTH_MIN)
		assert_float(length).is_less(CLIP_LENGTH_MAX)
