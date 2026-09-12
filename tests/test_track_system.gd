extends GdUnitTestSuite

func test_registry_contains_expected_tracks() -> void:
	var ids := TrackRegistry.get_track_ids()
	assert_array(ids).contains_exactly(["oval", "mountain_pass"])
	for track_id: String in ids:
		var data := TrackRegistry.get_track(track_id)
		assert_that(data.has("display_name")).is_true()
		assert_that(data.has("scene_path")).is_true()
		assert_that(data.has("laps_default")).is_true()
		assert_that(data.has("difficulty")).is_true()
		assert_that(data.has("circuit_type")).is_true()
		assert_that(TrackRegistry.has_track(track_id)).is_true()
	assert_that(TrackRegistry.has_track("missing_track")).is_false()

func test_registry_scene_files_exist() -> void:
	for track_id: String in TrackRegistry.get_track_ids():
		var scene_path := TrackRegistry.get_scene_path(track_id)
		assert_that(scene_path.is_empty()).is_false()
		assert_file(scene_path).exists()

func test_track_select_builds_one_card_per_track() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	assert_that(scene.get_card_count()).is_equal(TrackRegistry.get_track_ids().size())
	var grid := scene.get_node("%TrackGrid") as GridContainer
	assert_that(grid.get_child_count()).is_equal(TrackRegistry.get_track_ids().size())
	var cards: Array = grid.get_children()
	for i in cards.size():
		var track_id: String = TrackRegistry.get_track_ids()[i]
		var data := TrackRegistry.get_track(track_id)
		var card_text := _collect_label_text(cards[i])
		assert_that(card_text).contains(str(data.get("display_name")))
		assert_that(card_text).contains("CLASS %s" % data.get("difficulty"))
		assert_that(card_text).contains(str(data.get("circuit_type")))
	assert_that(scene.get_selected_scene_path()).is_equal(
		TrackRegistry.get_scene_path(TrackRegistry.get_track_ids()[0]))

func test_track_select_play_loads_selected_scene() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	var launched: Array[String] = []
	scene.launch_callback = func(path: String) -> void: launched.append(path)
	scene.select_track("mountain_pass")
	scene._on_play_pressed()
	assert_that(launched).is_equal([TrackRegistry.get_scene_path("mountain_pass")])
	scene.select_track("oval")
	scene._on_play_pressed()
	assert_that(launched).is_equal([
		TrackRegistry.get_scene_path("mountain_pass"),
		TrackRegistry.get_scene_path("oval"),
	])
	scene._on_back_pressed()
	assert_that(launched[launched.size() - 1]).is_equal("res://scenes/ui/main_menu.tscn")

func test_track_select_highlight_updates_on_select() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	scene.select_track("mountain_pass")
	assert_that(scene.get_selected_scene_path()).is_equal(
		TrackRegistry.get_scene_path("mountain_pass"))
	var cards: Array = scene.get_node("%TrackGrid").get_children()
	var selected_index := TrackRegistry.get_track_ids().find("mountain_pass")
	assert_that((cards[selected_index] as Button).button_pressed).is_true()
	var other_index := (selected_index + 1) % cards.size()
	assert_that((cards[other_index] as Button).button_pressed).is_false()

func test_mountain_pass_has_checkpoints_and_spawn() -> void:
	var runner := scene_runner("res://scenes/track/mountain_pass.tscn")
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	var checkpoints := scene.get_tree().get_nodes_in_group("checkpoints")
	assert_that(checkpoints.size()).is_greater_equal(1)
	var spawn := scene.get_node_or_null("PlayerCar") as Node3D
	assert_that(is_instance_valid(spawn)).is_true()
	if spawn != null:
		assert_that(spawn.global_position != Vector3.ZERO).is_true()

func test_mountain_pass_road_sits_above_terrain_floor() -> void:
	var runner := scene_runner("res://scenes/track/mountain_pass.tscn")
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	var ground := scene.get_node("GrassGround") as MeshInstance3D
	assert_that(ground).is_not_null()
	var floor_y: float = ground.global_position.y
	var points: Array = scene.get("road_points")
	assert_that(points.size()).is_equal(36)
	for i in points.size():
		var center: Vector3 = points[i]
		assert_that(center.y).is_greater(floor_y + 0.5)

func _collect_label_text(card: Node) -> String:
	var parts: Array[String] = []
	_collect_labels(card, parts)
	return " ".join(parts)

func _collect_labels(node: Node, parts: Array[String]) -> void:
	if node is Label:
		parts.append((node as Label).text)
	for child in node.get_children():
		_collect_labels(child, parts)