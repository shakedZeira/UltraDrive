# tests/suites/test_music_toast_timing.gd
extends GdUnitTestSuite

## MusicToast: pure alpha / slide statics, the driven advance(), processing off at
## rest, suppression while the tree is paused, the on/off setting, and the layer.

const ToastScene: PackedScene = preload("res://scenes/ui/music_toast.tscn")

var _toasts: Array = []

func after_test() -> void:
	for t in _toasts:
		if is_instance_valid(t):
			t.free()
	_toasts.clear()

func _new_toast() -> MusicToast:
	var toast: MusicToast = ToastScene.instantiate()
	add_child(toast)
	_toasts.append(toast)
	return toast

func test_alpha_envelope_rises_holds_and_falls() -> void:
	assert_that(MusicToast.toast_alpha(0.0)).is_equal(0.0)
	assert_that(MusicToast.toast_alpha(MusicToast.RISE_S * 0.5)).is_equal_approx(0.5, 0.001)
	assert_that(MusicToast.toast_alpha(MusicToast.RISE_S)).is_equal_approx(1.0, 0.001)
	assert_that(MusicToast.toast_alpha(MusicToast.RISE_S + 2.0)).is_equal(1.0)
	var fall_mid := MusicToast.RISE_S + MusicToast.HOLD_S + MusicToast.FALL_S * 0.5
	assert_that(MusicToast.toast_alpha(fall_mid)).is_equal_approx(0.5, 0.001)
	assert_that(MusicToast.toast_alpha(MusicToast.total())).is_equal(0.0)
	assert_that(MusicToast.toast_alpha(MusicToast.total() + 5.0)).is_equal(0.0)
	assert_that(MusicToast.toast_alpha(-1.0)).is_equal(0.0)

func test_slide_eases_in_then_rests_at_zero() -> void:
	assert_that(MusicToast.toast_slide(0.0)).is_equal(-MusicToast.SLIDE_PX)
	assert_that(MusicToast.toast_slide(MusicToast.RISE_S)).is_equal_approx(0.0, 0.001)
	assert_that(MusicToast.toast_slide(1.5)).is_equal(0.0)
	var mid := MusicToast.toast_slide(MusicToast.RISE_S * 0.5)
	assert_that(mid).is_between(-MusicToast.SLIDE_PX, 0.0)
	assert_that(MusicToast.toast_slide(MusicToast.total())).is_equal_approx(-MusicToast.SLIDE_PX * 0.5, 0.001)

func test_total_scales_with_hold() -> void:
	assert_that(MusicToast.total(1.6)).is_equal_approx(MusicToast.RISE_S + 1.6 + MusicToast.FALL_S, 0.0001)

func test_layer_sits_between_pause_menu_and_speed_trap() -> void:
	var toast := _new_toast()
	assert_that(toast.layer).is_equal(39)
	assert_that(toast.layer).is_less(SpeedTrapHUD.LAYER)
	assert_that(toast.layer).is_greater(10)

func test_idle_toast_is_hidden_and_not_processing() -> void:
	var toast := _new_toast()
	assert_that(toast.is_processing()).is_false()
	assert_that(toast.showing).is_false()
	var card := toast.get_node("Card") as Control
	assert_that(card.visible).is_false()

func test_show_track_fills_labels_and_runs_to_completion() -> void:
	var toast := _new_toast()
	toast.show_track({"id": "a.mp3", "title": "Nightcall", "artist": "Kavinsky", "album": "OutRun", "station_name": "Night Drive"})
	assert_that(toast.showing).is_true()
	assert_that(toast.is_processing()).is_true()
	assert_that((toast.get_node("Card/Title") as Label).text).is_equal("Nightcall")
	assert_that((toast.get_node("Card/Artist") as Label).text).contains("Kavinsky")
	assert_that((toast.get_node("Card/Artist") as Label).text).contains("OutRun")
	assert_that((toast.get_node("Card/Station") as Label).text).is_equal("NIGHT DRIVE")
	toast.advance(MusicToast.RISE_S)
	assert_that((toast.get_node("Card") as Control).modulate.a).is_equal_approx(1.0, 0.01)
	toast.advance(MusicToast.HOLD_S)
	assert_that(toast.showing).is_true()
	toast.advance(MusicToast.FALL_S + 0.1)
	assert_that(toast.showing).is_false()
	assert_that(toast.is_processing()).is_false()
	assert_that((toast.get_node("Card") as Control).visible).is_false()

func test_a_new_track_restarts_the_timer() -> void:
	var toast := _new_toast()
	toast.show_track({"id": "a", "title": "One"})
	toast.advance(3.0)
	toast.show_track({"id": "b", "title": "Two"})
	assert_that(toast.elapsed).is_equal(0.0)
	assert_that((toast.get_node("Card/Title") as Label).text).is_equal("Two")

func test_notice_cards_are_short() -> void:
	var toast := _new_toast()
	toast.show_text("Volume", "70%", "", true)
	assert_that(toast.hold_s).is_less(MusicToast.HOLD_S)
	toast.advance(MusicToast.total(toast.hold_s) + 0.1)
	assert_that(toast.showing).is_false()

func test_hidden_while_the_tree_is_paused() -> void:
	var toast := _new_toast()
	toast.show_track({"id": "a", "title": "One"})
	toast._paused_probe = func() -> bool: return true
	toast.advance(0.1)
	assert_that(toast.showing).is_false()
	assert_that((toast.get_node("Card") as Control).visible).is_false()
	toast.show_track({"id": "b", "title": "Two"}) # refused while paused
	assert_that(toast.showing).is_false()

func test_cover_applies_only_to_the_showing_track() -> void:
	var toast := _new_toast()
	toast.show_track({"id": "a", "title": "One"})
	var tex := ImageTexture.create_from_image(MusicCovers.make_tile("x"))
	toast._on_cover_ready("other", tex, Color.RED, false)
	assert_that((toast.get_node("Card/Cover") as TextureRect).texture).is_null()
	toast._on_cover_ready("a", tex, Color.RED, true)
	assert_that((toast.get_node("Card/Cover") as TextureRect).texture).is_not_null()
	assert_that((toast.get_node("Card/Cover/Letter") as Label).visible).is_true()

func test_toast_setting_off_suppresses_everything() -> void:
	var toast := _new_toast()
	var svc := Node.new()
	svc.set_script(load("res://tests/suites/music_toast_fake_service.gd"))
	svc.settings = {"toast": false}
	add_child(svc)
	_toasts.append(svc)
	toast.bind(svc)
	toast.show_track({"id": "a", "title": "Quiet"})
	assert_that(toast.showing).is_false()
	svc.settings = {"toast": true}
	toast.show_track({"id": "a", "title": "Loud"})
	assert_that(toast.showing).is_true()
