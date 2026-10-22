# tests/suites/test_garage_layout.gd
extends GdUnitTestSuite

## Acceptance gate for docs/plans/fix_garage_buttons_overlay.md: the garage car
## rail (%CarScroll) was re-anchored to the vehicle-preview column so it can no
## longer cover the SELECT / BACK buttons (the player's "overlayed and can't be
## pressed" report).
##
## The assertions are PURE GEOMETRY (zero flake): they read the runtime rects of
## the live scene two frames after it loads, exactly like existing suites already
## do - tests/suites/test_hud_contrast.gd:48 asserts
## `backdrop.get_rect().encloses(cluster.get_rect())` and
## tests/suites/test_boost_gauge.gd:85 asserts `gauge.size.x > 0.0` on a real
## scene, so Control layout (and therefore get_global_rect()) is real headless.
## The rail's size comes straight from its offsets, so it is fixed at 640 x 300
## regardless of the runner's window width - the invariant is width-independent.
##
## The plan's strongest gate - a real mouse click through the viewport
## (docs/plans/fix_garage_buttons_overlay.md section 5.1 item 3) - CANNOT run in
## this gate: the headless run passes --ignoreHeadlessMode and gdUnit itself
## documents that "tests that use UI interaction do not work correctly in
## headless mode ... Godot 'InputEvents' are not transported by the Godot engine"
## (addons/gdUnit4/src/core/runners/GdUnitTestCIRunner.gd:359-361). Per plan
## section 5.1 that click path is therefore covered by the manual playtest in
## section 5.3, and test 1 is deliberately NOT weakened to compensate.
##
## Instancing garage.tscn runs Garage.new_from_save() (scripts/ui/garage_ui.gd:60),
## which seeds missing starter cars and writes user://saves/slot_0.json, so slot 0
## is snapshotted in before_test and restored in after_test (mirrors
## tests/suites/test_garage_brands.gd / test_garage_tuning.gd). The suite is also
## listed in tools/gdunit_parallel.py CONTENDED_SUITES for the
## --no-isolate-user-data path.
##
## gdUnit treats GDScript warnings as errors -> every local is typed.

const _GARAGE_SCENE := "res://scenes/ui/garage.tscn"
const _RAIL_PATH := "CarScroll"
const _RIGHT_PANEL_PATH := "Margin/MainRow/RightPanel"
const _PREVIEW_PATH := "Margin/MainRow/PreviewPanel"

var _slot_snapshot: Dictionary = {}

func before_test() -> void:
	_slot_snapshot = SaveManager.load_game(0)

func after_test() -> void:
	var slot := 0
	var path = SaveManager.SAVE_DIR.path_join("slot_%d.json" % (slot + 1))
	if _slot_snapshot.is_empty() and not SaveManager.has_save(slot):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	else:
		SaveManager.save_game(slot, _slot_snapshot)

## Rebuilds the garage and returns the scene root after two frames (all
## containers sorted). Returns null when the scene failed to load.
func _garage_scene(runner: GdUnitSceneRunner) -> Control:
	var scene := runner.scene() as Control
	assert_that(scene).is_not_null()
	return scene

func test_garage_actions_not_covered_by_car_rail() -> void:
	var runner := scene_runner(_GARAGE_SCENE)
	await runner.simulate_frames(2)
	var scene := _garage_scene(runner)
	if scene == null:
		return
	var rail := scene.get_node_or_null(_RAIL_PATH) as ScrollContainer
	var select_button := scene.get_node_or_null("%SelectButton") as Button
	var back_button := scene.get_node_or_null("%BackButton") as Button
	assert_that(rail).is_not_null()
	assert_that(select_button).is_not_null()
	assert_that(back_button).is_not_null()
	if rail == null or select_button == null or back_button == null:
		return
	# Guard against a false green from a degenerate rect: the rail's width is
	# fixed by its offsets, so a zero-sized rail would mean the layout never ran.
	assert_that(rail.size.x).is_greater(0.0)
	assert_that(select_button.size.x).is_greater(0.0)
	# The regression guard: before the fix the rail rect contained both buttons.
	var rail_rect := rail.get_global_rect()
	assert_that(rail_rect.intersects(select_button.get_global_rect())).is_false()
	assert_that(rail_rect.intersects(back_button.get_global_rect())).is_false()

func test_garage_rail_stays_left_of_the_info_column() -> void:
	var runner := scene_runner(_GARAGE_SCENE)
	await runner.simulate_frames(2)
	var scene := _garage_scene(runner)
	if scene == null:
		return
	var rail := scene.get_node_or_null(_RAIL_PATH) as Control
	var right_panel := scene.get_node_or_null(_RIGHT_PANEL_PATH) as Control
	var preview := scene.get_node_or_null(_PREVIEW_PATH) as Control
	assert_that(rail).is_not_null()
	assert_that(right_panel).is_not_null()
	assert_that(preview).is_not_null()
	if rail == null or right_panel == null or preview == null:
		return
	var rail_rect := rail.get_global_rect()
	# The rail ends where the info column begins (a MainRow separation gutter)
	# and is exactly as wide as the preview panel above it.
	assert_that(rail_rect.end.x).is_less_equal(right_panel.get_global_rect().position.x)
	assert_that(rail_rect.end.x).is_less_equal(preview.get_global_rect().end.x)
	assert_that(absf(rail_rect.position.x - preview.get_global_rect().position.x)).is_less(1.0)

func test_garage_rail_clears_the_action_column() -> void:
	var runner := scene_runner(_GARAGE_SCENE)
	await runner.simulate_frames(2)
	var scene := _garage_scene(runner)
	if scene == null:
		return
	var rail := scene.get_node_or_null(_RAIL_PATH) as Control
	var select_button := scene.get_node_or_null("%SelectButton") as Button
	var back_button := scene.get_node_or_null("%BackButton") as Button
	assert_that(rail).is_not_null()
	assert_that(select_button).is_not_null()
	assert_that(back_button).is_not_null()
	if rail == null or select_button == null or back_button == null:
		return
	# Strict HORIZONTAL separation, not merely "no vertical overlap": the rail
	# must finish before the action column starts. This is what fails if the rail
	# is ever re-centred (it would then still sit under the info column even if
	# it happened to clear the buttons vertically).
	var rail_end: float = rail.get_global_rect().end.x
	assert_that(rail_end).is_less_equal(select_button.get_global_rect().position.x)
	assert_that(rail_end).is_less_equal(back_button.get_global_rect().position.x)
