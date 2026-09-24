# tests/suites/test_audio_feel_layers.gd
extends GdUnitTestSuite

## AAA-1 acceptance gate: the additive daily-feel audio beds (squeal/skid, wind,
## impact one-shots, shift blurts) and the headless-guarded UI blip player. The
## 3-bed crossfade core must stay intact; squeal must be monotonic with slip,
## wind monotonic with speed and silent at rest, impact fires exactly once per
## VehiclePhysics.impact emission, and a headless run must instantiate no
## blocking feel players (mirror test_car_audio stub discipline).

var _managed: Array = []
var _impact_count: int = 0

func before_test() -> void:
	_managed.clear()
	_impact_count = 0

func after_test() -> void:
	for node in _managed:
		if is_instance_valid(node):
			node.free()
	_managed.clear()
	for child in RaceManager.get_children():
		if child is LapCounter:
			child.free()
	RaceManager.is_race_active = false
	RaceManager._participants = []
	RaceManager._lap_counters = {}
	RaceManager._checkpoints_dirty = true
	RaceManager._countdown = RaceCountdown.new()
	RaceManager.consume_pending_race()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

## Headless-safe UiBlip stand-in: records which blip kinds were requested
## without touching the AudioServer. Swap it into the ui_blip slot of a loaded
## menu/HUD scene to assert "a blip fires here" as data, not sound.
class UiBlipSpy:
	extends UiBlip

	var menu_count: int = 0
	var hud_count: int = 0

	func play_blip(kind: String) -> void:
		if kind == "menu":
			menu_count += 1
		elif kind == "hud":
			hud_count += 1

func _new_car_audio() -> CarAudio:
	var audio := CarAudio.new()
	_managed.append(audio)
	return audio

func _on_test_impact(_strength: float) -> void:
	_impact_count += 1

func test_beds_exist_and_crossfade_without_breaking_existing_3_bed_asserts() -> void:
	var beds := CarAudio.build_beds(CarAudio.PROFILES["sport"])
	assert_that(beds.size()).is_equal(3)
	for bed: Dictionary in beds:
		var wav: AudioStreamWAV = bed["wav"]
		assert_that(wav.format).is_equal(AudioStreamWAV.FORMAT_16_BITS)
		assert_that(wav.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
		assert_that(wav.loop_begin).is_equal(0)
		assert_that(wav.loop_end).is_equal(int(wav.data.size() / 2.0))
		assert_that(wav.data.size() > 0).is_true()
	assert_that(CarAudio.WIND_SPEED_FULL_KMH).is_greater(CarAudio.WIND_SPEED_START_KMH)
	assert_that(CarAudio.SQUEAL_MAX_SLIP).is_greater(CarAudio.SQUEAL_SLIP_THRESHOLD)

func test_drive_info_exposes_slip_and_handbrake() -> void:
	var car: VehiclePhysics = auto_free(VehiclePhysics.new())
	var info := car.get_drive_info()
	assert_that(info.has("slip")).is_true()
	assert_that(info.has("handbrake")).is_true()
	assert_that(float(info["slip"])).is_equal(0.0)
	assert_that(bool(info["handbrake"])).is_false()

func test_squeal_intensity_monotonic_with_slip() -> void:
	var prev := CarAudio.get_squeal_intensity(0.0, SurfaceRegistry.ASPHALT)
	assert_that(prev).is_between(0.0, 0.001)
	for slip: float in [0.1, 0.2, 0.4, 0.6, 0.8, 1.0]:
		var cur := CarAudio.get_squeal_intensity(slip, SurfaceRegistry.ASPHALT)
		assert_that(cur).is_greater_equal(prev)
		prev = cur
	assert_that(CarAudio.get_squeal_intensity(0.5, SurfaceRegistry.ASPHALT)).is_greater(0.0)

func test_wind_bed_monotonic_with_speed_and_silent_at_rest() -> void:
	assert_that(CarAudio.get_wind_intensity(0.0)).is_equal_approx(0.0, 0.0001)
	var prev := CarAudio.get_wind_intensity(0.0)
	for s: float in [20.0, 40.0, 60.0, 80.0, 100.0, 120.0, 160.0, 200.0]:
		var cur := CarAudio.get_wind_intensity(s)
		assert_that(cur).is_greater_equal(prev)
		prev = cur
	assert_that(CarAudio.get_wind_intensity(60.0)).is_greater(0.0)
	assert_that(CarAudio.get_wind_intensity(200.0)).is_less_equal(1.0)

func test_impact_one_shot_fires_exactly_once_per_impact_emission() -> void:
	var audio := _new_car_audio()
	var car: VehiclePhysics = auto_free(VehiclePhysics.new())
	audio._car = car
	audio.impact_fired.connect(_on_test_impact)
	audio.hook_car_impacts()
	car.impact.emit(0.5)
	assert_that(_impact_count).is_equal(1)
	car.impact.emit(1.0)
	assert_that(_impact_count).is_equal(2)
	audio.hook_car_impacts()
	car.impact.emit(0.8)
	assert_that(_impact_count).is_equal(3)

func test_headless_run_instantiates_no_feel_players() -> void:
	var audio: CarAudio = auto_free(CarAudio.new())
	add_child(audio)
	assert_that(audio.is_player_creation_culled()).is_true()
	assert_that(audio.get_child_count()).is_equal(3)
	assert_that(audio.get_node_or_null("Squeal")).is_null()
	assert_that(audio.get_node_or_null("Wind")).is_null()
	assert_that(audio.get_node_or_null("Impact")).is_null()
	assert_that(audio.get_node_or_null("Shift")).is_null()

func test_ui_blip_wav_valid_and_headless_culled() -> void:
	var wav := UiBlip.build_blip(UiBlip.MENU_FREQ_HZ, UiBlip.BLIP_SECONDS)
	assert_that(wav.format).is_equal(AudioStreamWAV.FORMAT_16_BITS)
	assert_that(wav.data.size() > 0).is_true()
	var blip: UiBlip = auto_free(UiBlip.new())
	add_child(blip)
	assert_that(blip.is_playback_disabled()).is_true()

func test_main_menu_wires_every_button_to_menu_blip() -> void:
	var runner := scene_runner("res://scenes/ui/main_menu.tscn")
	await runner.simulate_frames(1)
	var scene: Control = runner.scene() as Control
	assert_that(scene).is_not_null()
	var blip := scene.get_node_or_null("UiBlip") as UiBlip
	assert_that(blip).is_not_null()
	assert_that(blip.is_playback_disabled()).is_true()
	var spy := UiBlipSpy.new()
	_managed.append(spy)
	scene.ui_blip = spy
	var layout := scene.get_node("MenuLayout") as VBoxContainer
	assert_that(layout).is_not_null()
	for child: Node in layout.get_children():
		if child is Button:
			var button := child as Button
			assert_that(button.pressed.is_connected(scene._menu_blip)).is_true()
			assert_that(button.focus_entered.is_connected(scene._menu_blip)).is_true()
	scene._menu_blip()
	assert_that(spy.menu_count).is_equal(1)
	scene._menu_blip()
	assert_that(spy.menu_count).is_equal(1)

func test_pause_menu_resume_press_triggers_menu_blip_once() -> void:
	var runner := scene_runner("res://scenes/ui/pause_menu.tscn")
	await runner.simulate_frames(1)
	var menu := runner.scene().get_node("Menu")
	assert_that(menu).is_not_null()
	var blip := menu.get_node_or_null("UiBlip") as UiBlip
	assert_that(blip).is_not_null()
	assert_that(blip.is_playback_disabled()).is_true()
	var spy := UiBlipSpy.new()
	_managed.append(spy)
	menu.ui_blip = spy
	var resume := menu.get_node("Panel/VBox/ResumeButton") as Button
	assert_that(resume.pressed.is_connected(menu._menu_blip)).is_true()
	resume.pressed.emit()
	assert_that(spy.menu_count).is_equal(1)
	resume.pressed.emit()
	assert_that(spy.menu_count).is_equal(1)

func test_settings_menu_binds_controls_to_menu_blip() -> void:
	var runner := scene_runner("res://scenes/ui/settings_menu.tscn")
	await runner.simulate_frames(1)
	var scene: Control = runner.scene() as Control
	assert_that(scene).is_not_null()
	var blip := scene.get_node_or_null("UiBlip") as UiBlip
	assert_that(blip).is_not_null()
	assert_that(blip.is_playback_disabled()).is_true()
	var spy := UiBlipSpy.new()
	_managed.append(spy)
	scene.ui_blip = spy
	var back := scene.get_node("CenterLayout/Scroll/Content/BackButton") as Button
	assert_that(back).is_not_null()
	assert_that(back.pressed.is_connected(scene._menu_blip)).is_true()
	assert_that(back.focus_entered.is_connected(scene._menu_blip)).is_true()
	var volume := scene.get_node("%VolumeSlider") as HSlider
	assert_that(volume).is_not_null()
	assert_that(volume.focus_entered.is_connected(scene._menu_blip)).is_true()
	scene._menu_blip()
	assert_that(spy.menu_count).is_equal(1)
	scene._menu_blip()
	assert_that(spy.menu_count).is_equal(1)

func test_track_select_play_triggers_menu_blip_once() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene: Control = runner.scene() as Control
	assert_that(scene).is_not_null()
	var blip := scene.get_node_or_null("UiBlip") as UiBlip
	assert_that(blip).is_not_null()
	assert_that(blip.is_playback_disabled()).is_true()
	var spy := UiBlipSpy.new()
	_managed.append(spy)
	scene.ui_blip = spy
	var launched: Array[String] = []
	scene.launch_callback = func(_path: String) -> void:
		launched.append(_path)
	var play := scene.get_node("%PlayButton") as Button
	assert_that(play.pressed.is_connected(scene._menu_blip)).is_true()
	play.pressed.emit()
	assert_that(spy.menu_count).is_equal(1)
	assert_that(launched.size()).is_equal(1)

func test_track_select_card_wires_menu_blip() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene: Control = runner.scene() as Control
	assert_that(scene).is_not_null()
	var grid := scene.get_node("%TrackGrid") as GridContainer
	assert_that(grid.get_child_count() > 0).is_true()
	if grid.get_child_count() > 0:
		var card := grid.get_child(0) as Button
		assert_that(card).is_not_null()
		assert_that(card.pressed.is_connected(scene._menu_blip)).is_true()

func test_garage_card_press_triggers_menu_blip_once() -> void:
	var runner := scene_runner("res://scenes/ui/garage.tscn")
	await runner.simulate_frames(3)
	var scene: Control = runner.scene() as Control
	assert_that(scene).is_not_null()
	var blip := scene.get_node_or_null("UiBlip") as UiBlip
	assert_that(blip).is_not_null()
	assert_that(blip.is_playback_disabled()).is_true()
	var spy := UiBlipSpy.new()
	_managed.append(spy)
	scene.ui_blip = spy
	var rail := scene.get_node("%CarRail") as HBoxContainer
	assert_that(rail.get_child_count() > 0).is_true()
	if rail.get_child_count() > 0:
		var card := rail.get_child(0) as Button
		assert_that(card).is_not_null()
		assert_that(card.pressed.is_connected(scene._menu_blip)).is_true()
		card.pressed.emit()
		assert_that(spy.menu_count).is_equal(1)

func test_hud_lap_completion_triggers_hud_blip_once() -> void:
	var car := VehiclePhysics.new()
	_managed.append(car)
	VehicleManager.player_car = car
	VehicleManager.all_cars.append(car)
	RaceManager.start_race([car], 3)
	var runner := scene_runner("res://scenes/ui/hud.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	var spy := UiBlipSpy.new()
	_managed.append(spy)
	scene._ui_blip = spy
	var counter := RaceManager.get_lap_counter(car)
	assert_that(counter).is_not_null()
	if counter != null:
		counter.lap_completed.emit(car, 1, 12.5)
		assert_that(spy.hud_count).is_equal(1)
		assert_that(spy.menu_count).is_equal(0)