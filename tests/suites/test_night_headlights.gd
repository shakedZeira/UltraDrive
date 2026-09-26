# tests/suites/test_night_headlights.gd
extends GdUnitTestSuite

## Roadmap #5: the car GLB only PAINTS its headlight/taillight materials, so
## this gate covers the real Light3D layer that lights the road at night —
## CarVisuals' pure clock-hour -> intensity map (day 0.0, midnight 1.0,
## monotonic dusk/dawn ramps), the lamp node structure the factory builds and
## aims along CAR_ORIENT's nose, the on/off switch, the X / Cross manual
## override (OFF -> ON -> AUTO, overriding the clock in both directions), and
## the player controller's ownership seam (rebuilt with the visual, driven by
## the DayNightDriver-owned WeatherManager clock). Pure math + hand-built nodes —
## no scene instantiation, no frames; the GLB-free path keeps it headless-stable.

const PlayerCarScript: GDScript = preload("res://scripts/player/player_car_controller.gd")

## Sample the whole 24h clock at this step (hours).
const SWEEP_STEP_HOURS := 0.25

## Dusk/dawn ramp window in hours, derived from the sun-elevation bounds. The
## clamp-free (strictly rising/falling) part of the fade is ~16:34-18:36 and
## ~05:25-07:25; these windows sit just INSIDE them so a monotonic sweep cannot
## trip over the flat 0.0 / 1.0 plateaus at either end.
const DUSK_RAMP_START := 16.6
const DUSK_RAMP_END := 18.55
const DAWN_RAMP_START := 5.45
const DAWN_RAMP_END := 7.4

var _managed_nodes: Array = []
var _prev_time_of_day: float = 12.0

func before_test() -> void:
	_managed_nodes.clear()
	_prev_time_of_day = WeatherManager.time_of_day

func after_test() -> void:
	WeatherManager.time_of_day = _prev_time_of_day
	for node in _managed_nodes:
		if is_instance_valid(node):
			node.free()
	_managed_nodes.clear()

func _sweep_hours() -> Array[float]:
	var hours: Array[float] = []
	var steps := int(roundf(24.0 / SWEEP_STEP_HOURS))
	for i in range(steps):
		hours.append(float(i) * SWEEP_STEP_HOURS)
	return hours

## Untyped on purpose: the controller script has no class_name, so the
## instance has to stay dynamically typed for the suite to drive it.
func _new_controller():
	var controller = PlayerCarScript.new()
	_managed_nodes.append(controller)
	return controller

func _new_body() -> Node3D:
	var body := Node3D.new()
	_managed_nodes.append(body)
	return body

# --- the intensity map ---

func test_intensity_is_zero_at_midday_and_one_at_midnight() -> void:
	assert_that(CarVisuals.headlight_intensity_for(12.0)).is_equal(0.0)
	assert_that(CarVisuals.headlight_intensity_for(0.0)).is_equal(1.0)
	assert_that(CarVisuals.headlight_intensity_for(24.0)).is_equal(1.0)
	assert_that(CarVisuals.headlight_intensity_for(13.5)).is_equal(0.0)
	assert_that(CarVisuals.headlight_intensity_for(2.0)).is_equal(1.0)

func test_sun_elevation_matches_the_weather_manager_arc() -> void:
	for hour in _sweep_hours():
		WeatherManager.set_time_of_day(hour)
		var expected := WeatherManager.get_computed_sun_position().y
		assert_float(CarVisuals.sun_elevation(hour)).is_equal_approx(expected, 0.001)
		assert_bool(CarVisuals.is_night_hour(hour)).is_equal(WeatherManager.is_night())

func test_intensity_is_point_seven_on_the_horizon_crossings() -> void:
	# 06:00 sunrise and 18:00 sunset are the WeatherManager.is_night() edges;
	# the ramp puts both at 0.7, i.e. already lit before dark.
	assert_float(CarVisuals.headlight_intensity_for(6.0)).is_equal_approx(0.7, 0.001)
	assert_float(CarVisuals.headlight_intensity_for(18.0)).is_equal_approx(0.7, 0.001)

func test_intensity_stays_inside_zero_one_across_the_whole_clock() -> void:
	for hour in _sweep_hours():
		assert_float(CarVisuals.headlight_intensity_for(hour)).is_between(0.0, 1.0)

func test_dusk_ramp_rises_monotonically_from_day_into_night() -> void:
	var hours: Array[float] = []
	var steps := 8
	for i in range(steps + 1):
		hours.append(lerpf(DUSK_RAMP_START, DUSK_RAMP_END, float(i) / float(steps)))
	var previous := -1.0
	for hour in hours:
		var intensity := CarVisuals.headlight_intensity_for(hour)
		assert_float(intensity).is_greater(previous)
		previous = intensity
	assert_float(CarVisuals.headlight_intensity_for(DUSK_RAMP_START)).is_less(0.1)
	assert_float(CarVisuals.headlight_intensity_for(DUSK_RAMP_END)).is_greater(0.9)
	# Outside the ramp the map saturates instead of climbing past 1.0.
	assert_float(CarVisuals.headlight_intensity_for(16.0)).is_equal(0.0)
	assert_float(CarVisuals.headlight_intensity_for(19.0)).is_equal(1.0)

func test_dawn_ramp_falls_monotonically_from_night_into_day() -> void:
	var hours: Array[float] = []
	var steps := 8
	for i in range(steps + 1):
		hours.append(lerpf(DAWN_RAMP_START, DAWN_RAMP_END, float(i) / float(steps)))
	var previous := 2.0
	for hour in hours:
		var intensity := CarVisuals.headlight_intensity_for(hour)
		assert_float(intensity).is_less(previous)
		previous = intensity
	assert_float(CarVisuals.headlight_intensity_for(DAWN_RAMP_START)).is_greater(0.9)
	assert_float(CarVisuals.headlight_intensity_for(DAWN_RAMP_END)).is_less(0.1)
	assert_float(CarVisuals.headlight_intensity_for(4.0)).is_equal(1.0)
	# The far end of the dawn fade is below the on-threshold, so the lamps
	# really do switch off (not just dim) as the sun clears the horizon.
	assert_bool(CarVisuals.headlight_lights_on(CarVisuals.headlight_intensity_for(DAWN_RAMP_END))).is_false()

func test_intensity_wraps_like_the_fposmod_clock() -> void:
	assert_float(CarVisuals.headlight_intensity_for(-6.0)).is_equal(
		CarVisuals.headlight_intensity_for(18.0))
	assert_float(CarVisuals.headlight_intensity_for(30.0)).is_equal(
		CarVisuals.headlight_intensity_for(6.0))
	assert_float(CarVisuals.headlight_intensity_for(12.0 + 48.0)).is_equal(0.0)

func test_lights_switch_threshold_splits_day_from_dusk() -> void:
	assert_bool(CarVisuals.headlight_lights_on(0.0)).is_false()
	assert_bool(CarVisuals.headlight_lights_on(CarVisuals.HEADLIGHT_ON_THRESHOLD)).is_false()
	assert_bool(CarVisuals.headlight_lights_on(0.5)).is_true()
	assert_bool(CarVisuals.headlight_lights_on(1.0)).is_true()
	# Every hour the world calls night must be lit.
	for hour in _sweep_hours():
		if CarVisuals.is_night_hour(hour):
			assert_bool(CarVisuals.headlight_lights_on(CarVisuals.headlight_intensity_for(hour))).is_true()

# --- the lamp layer ---

func test_build_night_lamps_creates_two_spots_and_a_tail_omni() -> void:
	var lamps := CarVisuals.build_night_lamps()
	_managed_nodes.append(lamps)
	assert_that(lamps.name).is_equal(CarVisuals.NIGHT_LAMP_HOLDER)
	assert_int(CarVisuals.night_lamp_count(lamps)).is_equal(3)
	var left := lamps.get_node_or_null(CarVisuals.HEADLIGHT_L_NAME) as SpotLight3D
	var right := lamps.get_node_or_null(CarVisuals.HEADLIGHT_R_NAME) as SpotLight3D
	var tail := lamps.get_node_or_null(CarVisuals.TAIL_LAMP_NAME) as OmniLight3D
	assert_that(left).is_not_null()
	assert_that(right).is_not_null()
	assert_that(tail).is_not_null()
	# A freshly built layer is dark: the switch is the only thing that lights it.
	assert_bool(CarVisuals.night_lamps_active(lamps)).is_false()
	assert_float(left.light_energy).is_equal(0.0)
	assert_float(tail.light_energy).is_equal(0.0)
	# Shadows stay off -- a lighting cue, not a lighting authority.
	assert_bool(left.shadow_enabled).is_false()
	assert_bool(right.shadow_enabled).is_false()
	assert_bool(tail.shadow_enabled).is_false()

func test_lamps_aim_along_the_visual_nose_and_sit_mirrored() -> void:
	var forward := CarVisuals.headlight_forward()
	# CAR_ORIENT maps the GLB's +Z nose onto the body's -Z, which is also a
	# SpotLight3D's emission axis, so an unrotated spot emits down the road.
	assert_that(forward).is_equal(Vector3(0.0, 0.0, -1.0))
	var lamps := CarVisuals.build_night_lamps()
	_managed_nodes.append(lamps)
	var left := lamps.get_node_or_null(CarVisuals.HEADLIGHT_L_NAME) as SpotLight3D
	var right := lamps.get_node_or_null(CarVisuals.HEADLIGHT_R_NAME) as SpotLight3D
	var tail := lamps.get_node_or_null(CarVisuals.TAIL_LAMP_NAME) as OmniLight3D
	# A SpotLight3D emits along its own -Z.
	assert_that(-left.basis.z).is_equal(forward)
	assert_that(-right.basis.z).is_equal(forward)
	assert_float(left.spot_angle).is_equal_approx(CarVisuals.HEADLIGHT_SPOT_ANGLE_DEG, 0.001)
	assert_float(left.spot_range).is_greater(CarVisuals.HEADLIGHT_SPOT_RANGE * 0.9)
	# Mirrored across the car's centreline, mounted ahead of the tail.
	assert_float(left.position.z).is_equal(right.position.z)
	assert_float(left.position.x).is_equal(-right.position.x)
	assert_float(left.position.x).is_less(0.0)
	assert_float(right.position.x).is_greater(0.0)
	# GLB-space mount (nose +Z) becomes body-space -Z, so the spots sit at
	# negative body Z and the red rear cue at positive body Z.
	assert_float(left.position.z).is_less(0.0)
	assert_float(right.position.z).is_less(0.0)
	# The red rear cue sits behind both spots.
	assert_float(tail.position.z).is_greater(left.position.z)
	assert_that(tail.light_color).is_equal(CarVisuals.TAIL_LIGHT_COLOR)
	assert_float(tail.omni_range).is_equal_approx(CarVisuals.TAIL_LIGHT_RANGE, 0.001)

func test_lamp_energy_ramps_with_intensity_and_drops_to_zero_by_day() -> void:
	var lamps := CarVisuals.build_night_lamps()
	_managed_nodes.append(lamps)
	var left := lamps.get_node_or_null(CarVisuals.HEADLIGHT_L_NAME) as SpotLight3D
	var tail := lamps.get_node_or_null(CarVisuals.TAIL_LAMP_NAME) as OmniLight3D

	CarVisuals.apply_lamp_intensity(lamps, 0.0)
	assert_bool(CarVisuals.night_lamps_active(lamps)).is_false()
	assert_float(left.light_energy).is_equal(0.0)
	assert_float(tail.light_energy).is_equal(0.0)

	CarVisuals.apply_lamp_intensity(lamps, 0.5)
	assert_bool(CarVisuals.night_lamps_active(lamps)).is_true()
	assert_float(left.light_energy).is_equal_approx(CarVisuals.HEADLIGHT_MAX_ENERGY * 0.5, 0.001)
	assert_float(tail.light_energy).is_equal_approx(CarVisuals.TAIL_LIGHT_MAX_ENERGY * 0.5, 0.001)

	CarVisuals.apply_lamp_intensity(lamps, 1.0)
	assert_float(left.light_energy).is_equal_approx(CarVisuals.HEADLIGHT_MAX_ENERGY, 0.001)
	assert_float(tail.light_energy).is_equal_approx(CarVisuals.TAIL_LIGHT_MAX_ENERGY, 0.001)

	# Over-driving the map clamps instead of blowing the light budget.
	CarVisuals.apply_lamp_intensity(lamps, 4.0)
	assert_float(left.light_energy).is_equal_approx(CarVisuals.HEADLIGHT_MAX_ENERGY, 0.001)

	# Idempotent: re-applying the same state never drifts.
	CarVisuals.apply_lamp_intensity(lamps, 4.0)
	assert_float(left.light_energy).is_equal_approx(CarVisuals.HEADLIGHT_MAX_ENERGY, 0.001)

func test_null_lamp_holder_is_a_safe_no_op() -> void:
	CarVisuals.apply_lamp_intensity(null, 1.0)
	assert_int(CarVisuals.night_lamp_count(null)).is_equal(0)
	assert_bool(CarVisuals.night_lamps_active(null)).is_false()

# --- controller ownership seam ---

func test_controller_builds_lamps_on_the_body_and_lights_them_at_night() -> void:
	var controller = _new_controller()
	var body := _new_body()
	controller.ensure_night_lamps(body)
	assert_int(controller.night_lamp_count()).is_equal(3)
	assert_that(body.get_node_or_null(CarVisuals.NIGHT_LAMP_HOLDER)).is_not_null()
	assert_bool(controller.night_lamps_active()).is_false()

	controller.set_headlight_time(0.0)
	assert_float(controller.headlight_intensity()).is_equal(1.0)
	assert_bool(controller.night_lamps_active()).is_true()

	controller.set_headlight_time(12.0)
	assert_float(controller.headlight_intensity()).is_equal(0.0)
	assert_bool(controller.night_lamps_active()).is_false()

	# Dusk sits between: lit, at a partial intensity.
	controller.set_headlight_time(17.5)
	assert_float(controller.headlight_intensity()).is_between(0.2, 0.7)
	assert_bool(controller.night_lamps_active()).is_true()

func test_controller_polls_the_day_night_driver_clock() -> void:
	var controller = _new_controller()
	var body := _new_body()
	controller.ensure_night_lamps(body)

	# Night: the per-frame poll (same call _process makes) lights the lamps
	# straight off the DayNightDriver-owned WeatherManager clock.
	WeatherManager.set_time_of_day(23.0)
	controller._sync_night_lamps()
	assert_float(controller.headlight_intensity()).is_equal(1.0)
	assert_bool(controller.night_lamps_active()).is_true()

	# Midday: same poll kills them again.
	WeatherManager.set_time_of_day(12.0)
	controller._sync_night_lamps()
	assert_float(controller.headlight_intensity()).is_equal(0.0)
	assert_bool(controller.night_lamps_active()).is_false()

func test_controller_rebuild_is_idempotent_across_visual_swaps() -> void:
	var controller = _new_controller()
	var body := _new_body()
	controller.ensure_night_lamps(body)
	controller.ensure_night_lamps(body)
	# _apply_visual() clears every CarBody child before re-instancing the GLB,
	# so the holder is dropped and rebuilt: exactly one layer survives.
	var holders := 0
	for child: Node in body.get_children():
		if child.name == CarVisuals.NIGHT_LAMP_HOLDER:
			holders += 1
	assert_int(holders).is_equal(1)
	assert_int(controller.night_lamp_count()).is_equal(3)

func test_controller_without_a_visual_owns_no_lamps() -> void:
	var controller = _new_controller()
	assert_int(controller.night_lamp_count()).is_equal(0)
	assert_bool(controller.night_lamps_active()).is_false()
	assert_that(controller.get_night_lamps()).is_null()
	# The clock poll must stay inert (not build anything) with no visual.
	WeatherManager.set_time_of_day(1.0)
	controller._sync_night_lamps()
	assert_int(controller.night_lamp_count()).is_equal(0)

# --- manual override (X / Cross) ---

func test_lamp_mode_cycle_runs_off_then_on_then_back_to_auto() -> void:
	# One X press from a fresh car only ever REDUCES what the clock asked for;
	# the second forces the lamps and the third hands them back to time-of-day.
	var mode: CarVisuals.LampMode = CarVisuals.LampMode.AUTO
	mode = CarVisuals.next_lamp_mode(mode)
	assert_that(mode).is_equal(CarVisuals.LampMode.OFF)
	mode = CarVisuals.next_lamp_mode(mode)
	assert_that(mode).is_equal(CarVisuals.LampMode.ON)
	mode = CarVisuals.next_lamp_mode(mode)
	assert_that(mode).is_equal(CarVisuals.LampMode.AUTO)
	# ...and the cycle is closed: three more presses return to the same start.
	for _press in range(3):
		mode = CarVisuals.next_lamp_mode(mode)
	assert_that(mode).is_equal(CarVisuals.LampMode.AUTO)

func test_manual_off_beats_midnight_and_manual_on_beats_noon() -> void:
	assert_float(CarVisuals.resolve_lamp_intensity(CarVisuals.LampMode.OFF, 0.0)).is_equal(0.0)
	assert_float(CarVisuals.resolve_lamp_intensity(CarVisuals.LampMode.OFF, 23.5)).is_equal(0.0)
	assert_float(CarVisuals.resolve_lamp_intensity(CarVisuals.LampMode.ON, 12.0)).is_equal(1.0)
	assert_float(CarVisuals.resolve_lamp_intensity(CarVisuals.LampMode.ON, 7.0)).is_equal(1.0)
	# AUTO is the clock map, untouched by the override layer.
	assert_float(CarVisuals.resolve_lamp_intensity(CarVisuals.LampMode.AUTO, 0.0)).is_equal(1.0)
	assert_float(CarVisuals.resolve_lamp_intensity(CarVisuals.LampMode.AUTO, 12.0)).is_equal(0.0)
	assert_float(CarVisuals.resolve_lamp_intensity(CarVisuals.LampMode.AUTO, 17.5)).is_equal(
		CarVisuals.headlight_intensity_for(17.5))

func test_every_mode_stays_inside_zero_one_across_the_whole_clock() -> void:
	var modes: Array[CarVisuals.LampMode] = [
		CarVisuals.LampMode.AUTO, CarVisuals.LampMode.OFF, CarVisuals.LampMode.ON,
	]
	for mode: CarVisuals.LampMode in modes:
		for hour in _sweep_hours():
			assert_float(CarVisuals.resolve_lamp_intensity(mode, hour)).is_between(0.0, 1.0)

func test_controller_manual_off_darkens_a_night_drive() -> void:
	var controller = _new_controller()
	var body := _new_body()
	controller.ensure_night_lamps(body)
	WeatherManager.set_time_of_day(23.0)
	controller._sync_night_lamps()
	assert_float(controller.headlight_intensity()).is_equal(1.0)
	assert_bool(controller.night_lamps_active()).is_true()

	# Press 1: the driver silences the lamps even though the world wants them.
	controller.cycle_headlight_mode()
	assert_that(controller.lamp_mode()).is_equal(CarVisuals.LampMode.OFF)
	assert_float(controller.headlight_intensity()).is_equal(0.0)
	assert_bool(controller.night_lamps_active()).is_false()
	# ...and the per-frame poll must not relight them while the clock says night.
	controller._sync_night_lamps()
	assert_float(controller.headlight_intensity()).is_equal(0.0)
	assert_bool(controller.night_lamps_active()).is_false()

	# Press 2: forced on, and holding through the clock poll changes nothing.
	controller.cycle_headlight_mode()
	assert_that(controller.lamp_mode()).is_equal(CarVisuals.LampMode.ON)
	assert_float(controller.headlight_intensity()).is_equal(1.0)
	assert_bool(controller.night_lamps_active()).is_true()
	WeatherManager.set_time_of_day(12.0)
	controller._sync_night_lamps()
	assert_float(controller.headlight_intensity()).is_equal(1.0)
	assert_bool(controller.night_lamps_active()).is_true()

	# Press 3: back to the clock, so noon finally kills them.
	controller.cycle_headlight_mode()
	assert_that(controller.lamp_mode()).is_equal(CarVisuals.LampMode.AUTO)
	assert_float(controller.headlight_intensity()).is_equal(0.0)
	assert_bool(controller.night_lamps_active()).is_false()

func test_controller_manual_on_lights_a_noon_drive() -> void:
	var controller = _new_controller()
	var body := _new_body()
	controller.ensure_night_lamps(body)
	WeatherManager.set_time_of_day(12.0)
	controller._sync_night_lamps()
	assert_bool(controller.night_lamps_active()).is_false()
	controller.set_lamp_mode(CarVisuals.LampMode.ON)
	assert_float(controller.headlight_intensity()).is_equal(1.0)
	assert_bool(controller.night_lamps_active()).is_true()
	controller.set_lamp_mode(CarVisuals.LampMode.OFF)
	assert_float(controller.headlight_intensity()).is_equal(0.0)
	assert_bool(controller.night_lamps_active()).is_false()
	controller.set_lamp_mode(CarVisuals.LampMode.AUTO)
	assert_float(controller.headlight_intensity()).is_equal(0.0)

func test_controller_starts_in_auto_and_only_the_button_leaves_it() -> void:
	var controller = _new_controller()
	var body := _new_body()
	controller.ensure_night_lamps(body)
	assert_that(controller.lamp_mode()).is_equal(CarVisuals.LampMode.AUTO)
	# The idle poll (no button held) must not drift out of AUTO.
	controller._poll_headlight_toggle()
	assert_that(controller.lamp_mode()).is_equal(CarVisuals.LampMode.AUTO)
	# A visual swap keeps the driver's choice: the rebuilt layer honours it.
	WeatherManager.set_time_of_day(12.0)
	controller.set_lamp_mode(CarVisuals.LampMode.ON)
	controller.ensure_night_lamps(body)
	assert_that(controller.lamp_mode()).is_equal(CarVisuals.LampMode.ON)
	assert_bool(controller.night_lamps_active()).is_true()
	assert_int(controller.night_lamp_count()).is_equal(3)

func test_holder_is_tagged_for_scene_tree_lookups() -> void:
	var lamps := CarVisuals.build_night_lamps()
	_managed_nodes.append(lamps)
	assert_bool(lamps.is_in_group(CarVisuals.NIGHT_LAMP_GROUP)).is_true()
	# The tag survives parenting onto a body (the controller's real seam).
	var parented_body := _new_body()
	parented_body.add_child(lamps)
	assert_bool(lamps.is_in_group(CarVisuals.NIGHT_LAMP_GROUP)).is_true()
	# ...and the controller's own build is tagged too, so a tree walk finds
	# exactly one tagged holder per car body.
	var body := _new_body()
	var controller = _new_controller()
	controller.ensure_night_lamps(body)
	var found := 0
	for child: Node in body.get_children():
		if child.is_in_group(CarVisuals.NIGHT_LAMP_GROUP):
			found += 1
	assert_int(found).is_equal(1)
