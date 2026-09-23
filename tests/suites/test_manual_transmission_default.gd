# tests/suites/test_manual_transmission_default.gd
extends GdUnitTestSuite

## Acceptance gate for three vehicle-behavior changes:
## 1) Fresh installs default to MANUAL transmission (a persisted explicit choice
##    still wins on load; the settings option reflects the new default).
## 2) In MANUAL, reverse (-1) is entered ONLY by downshifting from 1st - no code
##    path auto-selects R (rolling backward / standstill / slow forward stay in
##    the forward gear). The 1st->R drop keeps the existing over-rev guard, the
##    reverse speed cap still holds, shift_up returns R to 1st, and AUTO mode's
##    reverse behavior is untouched.
## 3) Speed-sensitive steering: the low-speed steer lock exceeds the high-speed
##    lock, the low-speed min turning radius shrinks vs the legacy constant, and
##    high-speed steer amount is unchanged (stability preserved).
##
## Pure/headless: Drivetrain + VehiclePhysics statics + the settings scene's
## _ready wiring. Slot-0 saves are snapshotted in before_test and restored in
## after_test so the real save never sees test writes.

const SettingsMenuScene: PackedScene = preload("res://scenes/ui/settings_menu.tscn")
const GameStateScript: GDScript = preload("res://autoload/game_state.gd")
const STARTER_CONFIG: CarConfig = preload("res://resources/cars/starter_car.tres")
const RALLY_CONFIG: CarConfig = preload("res://resources/cars/rally_hatch.tres")

var _managed: Array = []
var _slot_snapshot: Dictionary = {}
var _prev_transmission: GameState.TransmissionMode = GameState.TransmissionMode.AUTO

func before_test() -> void:
	_managed.clear()
	_slot_snapshot = SaveManager.load_game(0)
	_prev_transmission = GameState.transmission_mode

func after_test() -> void:
	for entry in _managed:
		if is_instance_valid(entry):
			entry.free()
	_managed.clear()
	GameState.transmission_mode = _prev_transmission
	var slot := 0
	var path: String = SaveManager.SAVE_DIR.path_join("slot_%d.json" % (slot + 1))
	if _slot_snapshot.is_empty() and not SaveManager.has_save(slot):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	else:
		SaveManager.save_game(slot, _slot_snapshot)

func _new_manual_drivetrain() -> Drivetrain:
	var dt := Drivetrain.new()
	dt.manual_mode = true
	return dt

# --- Changes 1: manual is the fresh default, persisted choice still wins ---

func test_fresh_game_state_defaults_to_manual() -> void:
	# Fresh-install seam: no save key at all (new installs and pre-feature
	# saves never persisted the mode) -> MANUAL.
	assert_that(GameState.transmission_mode_from_save({})).is_equal(GameState.TransmissionMode.MANUAL)
	assert_that(GameState.transmission_mode_from_save({"transmission_mode": 1})).is_equal(GameState.TransmissionMode.MANUAL)

func test_fresh_game_state_instance_declares_manual_default() -> void:
	var fresh: Object = GameStateScript.new()
	_managed.append(fresh)
	assert_that(int(fresh.get("transmission_mode"))).is_equal(GameState.TransmissionMode.MANUAL)

func test_persisted_transmission_preference_round_trips_and_overrides_default() -> void:
	GameState.set_transmission_mode(GameState.TransmissionMode.AUTO)
	assert_that(GameState.transmission_mode).is_equal(GameState.TransmissionMode.AUTO)
	var data: Dictionary = SaveManager.load_game(0)
	assert_that(data.has(GameState.TRANSMISSION_SAVE_KEY)).is_true()
	assert_that(int(data[GameState.TRANSMISSION_SAVE_KEY])).is_equal(GameState.TransmissionMode.AUTO)
	# The fresh-boot loader honors the explicit AUTO choice over the MANUAL default.
	assert_that(GameState.transmission_mode_from_save(data)).is_equal(GameState.TransmissionMode.AUTO)
	GameState.set_transmission_mode(GameState.TransmissionMode.MANUAL)
	data = SaveManager.load_game(0)
	assert_that(GameState.transmission_mode_from_save(data)).is_equal(GameState.TransmissionMode.MANUAL)

func test_settings_option_shows_manual_on_fresh_boot() -> void:
	GameState.transmission_mode = GameState.TransmissionMode.MANUAL
	var menu := SettingsMenuScene.instantiate() as Control
	_managed.append(menu)
	add_child(menu)
	var option := menu.get_node("%TransmissionOption") as OptionButton
	assert_that(option).is_not_null()
	assert_that(option.item_count).is_equal(2)
	assert_that(option.selected).is_equal(GameState.TransmissionMode.MANUAL)
	assert_that(option.get_item_text(option.selected)).is_equal("Manual")

func test_settings_option_shows_automatic_when_persisted_choice_is_auto() -> void:
	GameState.transmission_mode = GameState.TransmissionMode.AUTO
	var menu := SettingsMenuScene.instantiate() as Control
	_managed.append(menu)
	add_child(menu)
	var option := menu.get_node("%TransmissionOption") as OptionButton
	assert_that(option.selected).is_equal(GameState.TransmissionMode.AUTO)
	assert_that(option.get_item_text(option.selected)).is_equal("Automatic")

# --- Change 2: reverse is manual-only via downshift from 1st ---

func test_manual_downshift_from_first_enters_reverse() -> void:
	var dt := _new_manual_drivetrain()
	assert_that(dt.current_gear).is_equal(1)
	dt.shift_down(STARTER_CONFIG)
	assert_that(dt.current_gear).is_equal(-1)
	assert_that(dt.is_shifting).is_true()

func test_manual_reverse_is_not_auto_selected_by_standstill_or_backward_roll() -> void:
	# Standstill: still in 1st.
	var dt := _new_manual_drivetrain()
	dt.set_wheel_speed(0.0)
	dt.update(1.0 / 60.0, 1.0, STARTER_CONFIG)
	assert_that(dt.current_gear).is_equal(1)
	# Slow forward roller: no reverse either.
	dt.reset()
	dt.set_wheel_speed(0.4)
	dt.update(1.0 / 60.0, 1.0, STARTER_CONFIG)
	assert_that(dt.current_gear).is_equal(1)
	# Rolling backward in 1st: blocked (manual never auto-selects R).
	dt.reset()
	dt.set_wheel_speed(-2.0)
	dt.update(1.0 / 60.0, 1.0, STARTER_CONFIG)
	assert_that(dt.current_gear).is_equal(1)
	# Rolling backward in 2nd: stays in 2nd.
	dt.current_gear = 2
	dt.set_wheel_speed(-3.0)
	dt.update(1.0 / 60.0, 1.0, STARTER_CONFIG)
	assert_that(dt.current_gear).is_equal(2)

func test_manual_reverse_engagement_rejected_over_rev_at_speed() -> void:
	# Rally redline 8200; reverse ratio 3.2 * 4.1 = 13.12. At 30 m/s (108 km/h)
	# forward, engaging R would spin to ~11390 rpm > 8610 (1.05 * redline), so
	# the downshift from 1st must be rejected, mirroring the existing guard.
	var dt := _new_manual_drivetrain()
	dt.set_wheel_speed(30.0)
	dt.shift_down(RALLY_CONFIG)
	assert_that(dt.current_gear).is_equal(1)
	assert_that(dt.is_shifting).is_false()

func test_manual_reverse_engagement_allowed_at_creep() -> void:
	var dt := _new_manual_drivetrain()
	dt.set_wheel_speed(1.0)
	dt.shift_down(RALLY_CONFIG)
	assert_that(dt.current_gear).is_equal(-1)
	assert_that(dt.is_shifting).is_true()

func test_manual_shift_up_from_reverse_returns_to_first() -> void:
	var dt := _new_manual_drivetrain()
	dt.shift_down(STARTER_CONFIG)
	assert_that(dt.current_gear).is_equal(-1)
	dt.shift_up(STARTER_CONFIG)
	assert_that(dt.current_gear).is_equal(1)
	assert_that(dt.is_shifting).is_true()

func test_reverse_speed_cap_still_holds_in_manual() -> void:
	var dt := _new_manual_drivetrain()
	dt.shift_down(STARTER_CONFIG)
	assert_that(dt.current_gear).is_equal(-1)
	dt.is_shifting = false
	dt.shift_timer = 0.0
	var cap_ms := STARTER_CONFIG.max_reverse_speed_kmh / 3.6
	dt.set_wheel_speed(-(cap_ms + 0.5))
	dt.update(1.0 / 60.0, 1.0, STARTER_CONFIG)
	assert_that(dt.current_gear).is_equal(-1)
	assert_that(dt.reverse_limiter_active).is_true()
	assert_that(dt.drive_torque).is_equal(0.0)
	# Below the cap the limiter is off and the rear-drive torque flows again.
	dt.set_wheel_speed(-1.0)
	dt.update(1.0 / 60.0, 1.0, STARTER_CONFIG)
	assert_that(dt.reverse_limiter_active).is_false()
	assert_that(dt.drive_torque).is_less(0.0)

func test_auto_mode_still_reaches_reverse_per_existing_logic() -> void:
	# AUTO (manual_mode == false) keeps the legacy roll-backward -> R logic.
	var dt := Drivetrain.new()
	dt.set_wheel_speed(-2.0)
	dt.update(1.0 / 60.0, 1.0, STARTER_CONFIG)
	assert_that(dt.current_gear).is_equal(-1)
	dt.set_wheel_speed(0.6)
	dt.update(1.0 / 60.0, 1.0, STARTER_CONFIG)
	assert_that(dt.current_gear).is_equal(1)

# --- Change 3: low-speed steering radius ---

func test_low_speed_steer_lock_exceeds_high_speed_lock() -> void:
	var low: float = VehiclePhysics.steer_lock_deg(0.0, STARTER_CONFIG)
	var high: float = VehiclePhysics.steer_lock_deg(140.0, STARTER_CONFIG)
	assert_that(low).is_greater(high)
	# Bounded by the configured knobs: low at the low-speed lock, high >= old floor.
	assert_that(low).is_less_equal(STARTER_CONFIG.low_speed_steer_angle + 0.001)
	assert_that(high).is_greater_equal(STARTER_CONFIG.max_steer_angle * 0.3 - 0.001)

func test_high_speed_steer_lock_unchanged_from_legacy() -> void:
	# Above the low-speed taper the lock must sit on the legacy falloff curve
	# exactly: max_steer_angle * (1 - clampf(kmh / 200, 0, 0.7)).
	for kmh in [40.0, 70.0, 140.0, 250.0]:
		var legacy: float = STARTER_CONFIG.max_steer_angle * (1.0 - clampf(kmh / 200.0, 0.0, 0.7))
		assert_that(VehiclePhysics.steer_lock_deg(kmh, STARTER_CONFIG)).is_equal_approx(legacy, 0.001)
	# High-speed lock never exceeds the old value (stability preserved).
	assert_that(VehiclePhysics.steer_lock_deg(140.0, STARTER_CONFIG)).is_less_equal(STARTER_CONFIG.max_steer_angle * 0.3 + 0.001)

func test_min_turning_radius_at_low_speed_is_reduced_vs_legacy() -> void:
	var old_low: float = STARTER_CONFIG.max_steer_angle  # legacy constant low-speed lock
	var new_low: float = VehiclePhysics.steer_lock_deg(0.0, STARTER_CONFIG)
	var old_radius: float = STARTER_CONFIG.get_min_turning_radius_deg(old_low)
	var new_radius: float = STARTER_CONFIG.get_min_turning_radius_deg(new_low)
	assert_that(new_low).is_greater(old_low)
	# Measurably reduced vs the old constant (2.25 m vs 3.57 m on the 2.5 m
	# wheelbase) and exactly the ackermann value wheelbase / tan(steer).
	assert_that(new_radius).is_less(old_radius * 0.8)
	assert_that(new_radius).is_equal_approx(STARTER_CONFIG.wheelbase / tan(deg_to_rad(new_low)), 0.001)