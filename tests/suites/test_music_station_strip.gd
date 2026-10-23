extends GdUnitTestSuite

## MusicStationStrip: pure window / wanted / step_alpha statics, hold-to-show (a
## Back TAP must not flash it), linger after a station change, hidden while the
## tree is paused, processing off at rest, layer order, and the open-world wiring.

const StripScene: PackedScene = preload("res://scenes/ui/music_station_strip.tscn")
const ServiceScript: GDScript = preload("res://scripts/music/music_service.gd")

var _nodes: Array = []

func after_test() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()

func _strip() -> MusicStationStrip:
	var strip: MusicStationStrip = StripScene.instantiate()
	add_child(strip)
	_nodes.append(strip)
	return strip

## A real MusicService (no autoload, no I/O) with three fake stations.
func _service() -> Node:
	var svc: Node = ServiceScript.new()
	svc.persist = false
	svc.auto_start = false
	svc.sync_loading = true
	add_child(svc)
	_nodes.append(svc)
	for n in ["Alpha", "Beta", "Gamma"]:
		var st := MusicStation.new()
		st.id = "f:" + n
		st.display_name = n
		st.track_ids = ["%s/1.ogg" % n]
		svc.library.stations.append(st)
	return svc

func test_window_is_centred_and_clamped() -> void:
	assert_that(MusicStationStrip.window(0, 0)).is_empty()
	assert_that(MusicStationStrip.window(3, 1)).is_equal([0, 1, 2])
	assert_that(MusicStationStrip.window(10, 0, 5)).is_equal([0, 1, 2, 3, 4])
	assert_that(MusicStationStrip.window(10, 5, 5)).is_equal([3, 4, 5, 6, 7])
	assert_that(MusicStationStrip.window(10, 9, 5)).is_equal([5, 6, 7, 8, 9])
	assert_that(MusicStationStrip.window(10, 5, 5).size()).is_equal(MusicStationStrip.MAX_CHIPS)

func test_wanted_needs_a_hold_or_a_linger() -> void:
	assert_that(MusicStationStrip.wanted(false, 5.0, 0.0)).is_false()
	assert_that(MusicStationStrip.wanted(true, 0.1, 0.0)).is_false() # a tap
	assert_that(MusicStationStrip.wanted(true, MusicStationStrip.HOLD_TO_SHOW_S, 0.0)).is_true()
	assert_that(MusicStationStrip.wanted(false, 0.0, 0.5)).is_true()

func test_step_alpha_rises_and_falls() -> void:
	assert_that(MusicStationStrip.step_alpha(0.0, true, MusicStationStrip.RISE_S)).is_equal_approx(1.0, 0.001)
	assert_that(MusicStationStrip.step_alpha(1.0, false, MusicStationStrip.FALL_S)).is_equal_approx(0.0, 0.001)
	assert_that(MusicStationStrip.step_alpha(0.5, true, 10.0)).is_equal(1.0)
	assert_that(MusicStationStrip.step_alpha(0.5, false, 10.0)).is_equal(0.0)

func test_layer_is_under_the_toast_and_over_the_pause_menu() -> void:
	var strip := _strip()
	assert_that(strip.layer).is_equal(MusicStationStrip.LAYER)
	assert_that(strip.layer).is_less(MusicToast.LAYER)
	assert_that(strip.layer).is_greater(10)

func test_idle_strip_is_hidden_and_not_processing() -> void:
	var strip := _strip()
	assert_that(strip.is_processing()).is_false()
	assert_that(strip.showing).is_false()
	assert_that((strip.get_node("Holder/Panel") as Control).visible).is_false()

func test_back_tap_does_not_flash_the_strip() -> void:
	var strip := _strip()
	var svc := _service()
	strip.bind(svc)
	svc.chord_changed.emit(true)
	strip.advance(0.1)
	svc.chord_changed.emit(false)
	strip.advance(0.1)
	assert_that(strip.showing).is_false()
	assert_that(strip.is_processing()).is_false()

func test_holding_back_shows_station_chips_and_release_hides() -> void:
	var strip := _strip()
	var svc := _service()
	strip.bind(svc)
	svc.station = svc.library.station_by_id("f:Beta")
	svc.chord_changed.emit(true)
	assert_that(strip.is_processing()).is_true()
	strip.advance(MusicStationStrip.HOLD_TO_SHOW_S + 0.01)
	assert_that(strip.showing).is_true()
	var row := strip.get_node("Holder/Panel").get_child(0).get_child(0) as HBoxContainer
	assert_that(row.get_child_count()).is_equal(3)
	assert_that((row.get_child(1) as Label).text).is_equal("Beta")
	strip.advance(MusicStationStrip.RISE_S)
	assert_that((strip.get_node("Holder/Panel") as Control).modulate.a).is_equal_approx(1.0, 0.01)
	svc.chord_changed.emit(false)
	strip.advance(MusicStationStrip.FALL_S + 0.05)
	assert_that(strip.showing).is_false()
	assert_that(strip.is_processing()).is_false()

func test_station_change_lingers_then_fades() -> void:
	var strip := _strip()
	var svc := _service()
	strip.bind(svc)
	svc.station = svc.library.station_by_id("f:Alpha")
	svc.station_changed.emit("Alpha", "f:Alpha")
	strip.advance(0.1)
	assert_that(strip.showing).is_true()
	strip.advance(MusicStationStrip.LINGER_S)
	strip.advance(MusicStationStrip.FALL_S + 0.05)
	assert_that(strip.showing).is_false()
	assert_that(strip.is_processing()).is_false()

func test_hidden_while_the_tree_is_paused() -> void:
	var strip := _strip()
	var svc := _service()
	strip.bind(svc)
	svc.station_changed.emit("Alpha", "f:Alpha")
	strip.advance(0.1)
	assert_that(strip.showing).is_true()
	strip._paused_probe = func() -> bool: return true
	strip.advance(0.1)
	assert_that(strip.showing).is_false()
	svc.station_changed.emit("Beta", "f:Beta") # refused while paused
	assert_that(strip.linger_left).is_equal(0.0)

func test_open_world_scene_instances_the_strip_under_the_toast_layer() -> void:
	var text := FileAccess.get_file_as_string("res://scenes/world/open_world_root.tscn")
	assert_that(text).contains("music_station_strip.tscn")
	assert_that(text).contains("MusicStationStrip")
