# tests/suites/test_race_layout_preview.gd
extends GdUnitTestSuite

## Race tab: layout preview + GT7-style event details
## (docs/plans/race_tab_track_layout_event_details.md §5).
##
## Pure/data tests read the baked layout source; control tests exercise
## TrackLayoutPreview with an explicit `size` (headless `_draw()` never runs);
## menu tests drive the real `track_select.tscn`.
##
## TEST 1 IS A DELIBERATE CANARY: it fails when a registry layout has no baked
## data, pointing at the fix (`re-run tools/gen_track_layouts.gd`). The runtime
## degrades gracefully without a bake (see test 3 / test 7), so the UI stays
## alive meanwhile.
##
## gdUnit treats GDScript warnings as errors -> every local is typed.

## Snapshot/restore the mutable GameState race settings so this suite never
## leaks a fields setting into a sibling suite in the same shard.
var _saved_opponents: int = 0
var _saved_difficulty: String = ""

func before_test() -> void:
	_saved_opponents = GameState.opponents
	_saved_difficulty = GameState.ai_difficulty

func after_test() -> void:
	GameState.opponents = _saved_opponents
	GameState.ai_difficulty = _saved_difficulty
	RaceManager.consume_pending_race()

# --- pure / data -------------------------------------------------------------

func test_every_registry_layout_has_baked_preview_data() -> void:
	var ids: Array = TrackRegistry.get_track_ids()
	assert_that(ids.is_empty()).is_false()
	for track_id: String in ids:
		assert_that(TrackLayoutSource.has_layout(track_id)).override_failure_message(
			"no baked layout for '%s' - re-run tools/gen_track_layouts.gd" % track_id).is_true()
		assert_that(TrackLayoutSource.points(track_id).size()).is_greater_equal(8)

func test_preview_points_are_finite_and_flat() -> void:
	for track_id: String in TrackRegistry.get_track_ids():
		var pts := TrackLayoutSource.points(track_id)
		assert_that(pts.size()).is_greater_equal(8)
		var min_xz := Vector2(INF, INF)
		var max_xz := Vector2(-INF, -INF)
		for p: Vector3 in pts:
			assert_that(p.is_finite()).is_true()
			min_xz.x = minf(min_xz.x, p.x)
			min_xz.y = minf(min_xz.y, p.z)
			max_xz.x = maxf(max_xz.x, p.x)
			max_xz.y = maxf(max_xz.y, p.z)
		var span := max_xz - min_xz
		# A degenerate 2-point "line" or an un-baked empty set can never pass.
		assert_that(maxf(span.x, span.y)).is_greater(40.0)
		# Closed ring: first and last are one segment apart, not the far ends.
		var mean_spacing := _mean_spacing(pts)
		assert_that(pts[0].distance_to(pts[pts.size() - 1])).is_less_equal(3.0 * mean_spacing)

func test_unknown_track_returns_empty_and_no_line() -> void:
	assert_that(TrackLayoutSource.points("no_such_track").is_empty()).is_true()
	assert_that(TrackLayoutSource.has_layout("no_such_track")).is_false()
	assert_that(TrackLayoutSource.preview_path("no_such_track")).is_equal(
		"res://resources/ui/track_layouts/no_such_track.json")

func test_rival_centerline_flag_matches_the_shipped_tracks() -> void:
	# Generic on purpose: the concurrent registry task may add a track that
	# publishes one. What matters is (a) the flag is always a defined bool and
	# (b) the honesty branch is exercised (at least one layout fields no rivals).
	var seen_false := false
	for track_id: String in TrackRegistry.get_track_ids():
		var flag := TrackLayoutSource.has_rival_centerline(track_id)
		assert_that(typeof(flag)).is_equal(TYPE_BOOL)
		if not flag:
			seen_false = true
	assert_that(seen_false).is_true()

# --- preview control (size set explicitly: _draw never runs headless) --------

func test_preview_projects_the_selected_layout_inside_its_rect() -> void:
	var preview := auto_free(TrackLayoutPreview.new()) as TrackLayoutPreview
	preview.size = Vector2(320.0, 200.0)
	preview.set_layout("mountain_pass")
	assert_that(preview.has_layout()).is_true()
	var projected := preview.projected_points()
	assert_that(projected.size()).is_equal(TrackLayoutSource.points("mountain_pass").size())
	var rect := Rect2(Vector2.ZERO, preview.size)
	for i in projected.size():
		assert_that(rect.has_point(projected[i])).is_true()

func test_preview_switches_layout_without_a_scene_change() -> void:
	var preview := auto_free(TrackLayoutPreview.new()) as TrackLayoutPreview
	preview.size = Vector2(320.0, 200.0)
	preview.set_layout("oval")
	assert_that(preview.layout_id()).is_equal("oval")
	var oval_count := preview.projected_points().size()
	preview.set_layout("mountain_pass")
	assert_that(preview.layout_id()).is_equal("mountain_pass")
	var mountain_count := preview.projected_points().size()
	assert_that(mountain_count).is_equal(TrackLayoutSource.points("mountain_pass").size())
	assert_that(oval_count).is_not_equal(mountain_count)
	var rect := Rect2(Vector2.ZERO, preview.size)
	var projected := preview.projected_points()
	for i in projected.size():
		assert_that(rect.has_point(projected[i])).is_true()

func test_preview_without_data_reports_no_layout() -> void:
	var preview := auto_free(TrackLayoutPreview.new()) as TrackLayoutPreview
	preview.size = Vector2(320.0, 200.0)
	preview.set_layout("no_such_track")
	assert_that(preview.has_layout()).is_false()
	assert_that(preview.projected_points().is_empty()).is_true()

# --- menu --------------------------------------------------------------------

func test_default_event_panel_shows_laps_and_field_summary() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	assert_that(scene).is_not_null()
	var track_id := scene.get_selected_track_id()
	assert_that(track_id.is_empty()).is_false()
	var expected_laps := int(TrackRegistry.get_track(track_id).get("laps_default", 3))
	var laps_label := scene.get_node("%LapsLabel") as Label
	assert_that(laps_label.text).contains("%d LAPS" % expected_laps)
	var summary := scene.get_node("%FieldSummaryLabel") as Label
	assert_that(summary.text).contains(str(GameState.clamp_opponents(GameState.opponents)))
	assert_that(summary.text).contains(GameState.normalize_difficulty(GameState.ai_difficulty).to_upper())
	var play := scene.get_node("%PlayButton") as Button
	assert_that(play.text).is_equal("START RACE")

func test_selecting_an_event_updates_preview_and_field() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	GameState.opponents = 5
	GameState.ai_difficulty = "Skilled"
	scene.select_pin("home_northern_isle")
	var preview := scene.get_node("%LayoutPreview") as TrackLayoutPreview
	assert_that(preview.layout_id()).is_equal("northern_isle")
	assert_that(preview.has_layout()).is_true()
	var box := scene.get_node("%RivalsBox") as VBoxContainer
	# Only Northern Isle publishes a rival centerline, so it renders a field.
	assert_that(box.get_child_count()).is_equal(5)
	scene.select_pin("home_sunset_oval")
	assert_that(preview.layout_id()).is_equal("oval")
	assert_that(box.get_child_count()).is_equal(1)
	assert_that(_collect_label_text(box)).contains("NONE ON THIS LAYOUT")

func test_rival_rows_name_real_cars_with_tiers() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	GameState.opponents = 3
	GameState.ai_difficulty = "Expert"
	scene.select_pin("home_northern_isle")
	var box := scene.get_node("%RivalsBox") as VBoxContainer
	assert_that(box.get_child_count()).is_equal(3)
	var first_row := box.get_child(0) as Label
	assert_that(first_row).is_not_null()
	var visual := CarVisuals.rival_visual_for(0)
	var car_id := str(visual.get("car_id", ""))
	var config := load("res://resources/cars/%s.tres" % car_id) as CarConfig
	var expected_name := car_id
	if config != null and not config.car_name.is_empty():
		expected_name = config.car_name
	assert_that(first_row.text).contains(expected_name)
	# Slot 0 is always the difficulty anchor itself (race_manager.gd _tier_for_slot).
	assert_that(first_row.text).contains("Expert")

func test_play_still_queues_the_selected_laps() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	var launched: Array[String] = []
	scene.launch_callback = func(path: String) -> void: launched.append(path)
	scene.select_pin("spa")
	assert_that(scene.get_selected_scene_path()).is_equal(TrackRegistry.get_scene_path("mountain_pass"))
	scene._on_play_pressed()
	assert_that(launched).is_equal([TrackRegistry.get_scene_path("mountain_pass")])
	assert_that(RaceManager.consume_pending_race()).is_equal(2)

# --- helpers -----------------------------------------------------------------

func _mean_spacing(pts: Array[Vector3]) -> float:
	if pts.size() < 2:
		return 0.0
	var total := 0.0
	for i in pts.size():
		total += pts[i].distance_to(pts[(i + 1) % pts.size()])
	return total / float(pts.size())

func _collect_label_text(node: Node) -> String:
	var parts: Array[String] = []
	_collect_labels(node, parts)
	return " ".join(parts)

func _collect_labels(node: Node, parts: Array[String]) -> void:
	if node is Label:
		parts.append((node as Label).text)
	for child: Node in node.get_children():
		_collect_labels(child, parts)
