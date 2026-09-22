# tests/suites/test_garage_tuning.gd
extends GdUnitTestSuite

## S13 acceptance gate: Garage depth (tune / paint / dyno). Covers the
## CarConfig.with_overrides() clone helper (getter parity, base untouched), the
## TuningProfile clamped override dict (gear / final drive / mass bounds, slider
## band, round-trip through a corrupt save), paint-id + tuning persistence in
## the per-car garage save block, the is_car_unlocked edit gate (non-owned and
## license-locked cars are read-only), the pure-static dyno readout, and a cheap
## scene_runner probe that garage.tscn still wires the three tabs. Every save
## test snapshots slot 0 and restores it in after_test (mirrors
## test_career_economy) so the real save stays untouched.

const STARTER_CONFIG_PATH := "res://resources/cars/starter_car.tres"

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

## Forces the persisted license back to its fresh tier-B baseline so edit-gate
## tests are deterministic regardless of the player's real licence progress.
func _reset_license() -> void:
	var data := SaveManager.load_game(0)
	data["license_results"] = {}
	data["license_discipline_results"] = {}
	SaveManager.save_game(0, data)

func _load_starter() -> CarConfig:
	return load(STARTER_CONFIG_PATH) as CarConfig

func test_with_overrides_clone_parity_and_base_untouched() -> void:
	var base := _load_starter()
	assert_that(base).is_not_null()
	var stock_ratios: Array[float] = base.gear_ratios.duplicate()
	var stock_final := base.final_drive_ratio
	var stock_mass := base.mass_kg
	var overrides := {
		"gear_ratios": [base.gear_ratios[0] * 1.2, base.gear_ratios[1] * 0.85, base.gear_ratios[2], base.gear_ratios[3], base.gear_ratios[4]],
		"final_drive_ratio": base.final_drive_ratio * 1.1,
		"mass_kg": base.mass_kg * 0.85,
	}
	var tuned := base.with_overrides(overrides)
	assert_that(tuned).is_not_null()
	assert_that(tuned).is_not_same(base)
	assert_that(tuned.final_drive_ratio).is_equal_approx(overrides["final_drive_ratio"], 0.01)
	assert_that(tuned.mass_kg).is_equal_approx(overrides["mass_kg"], 0.01)
	assert_that(base.final_drive_ratio).is_equal_approx(stock_final, 0.01)
	assert_that(base.mass_kg).is_equal_approx(stock_mass, 0.01)
	var tuned_ratios: Array = tuned.gear_ratios
	var override_ratios: Array = overrides["gear_ratios"]
	assert_that(tuned_ratios.size()).is_equal(override_ratios.size())
	for i in override_ratios.size():
		assert_that(tuned_ratios[i]).is_equal_approx(override_ratios[i], 0.01)
		assert_that(base.gear_ratios[i]).is_equal_approx(stock_ratios[i], 0.01)
	assert_that(tuned.redline_rpm).is_equal_approx(base.redline_rpm, 0.01)
	assert_that(tuned.max_torque).is_equal_approx(base.max_torque, 0.01)
	assert_that(tuned.car_class).is_equal(base.car_class)
	assert_that(tuned.price).is_equal(base.price)

func test_with_overrides_ignores_unknown_and_wrong_typed_keys() -> void:
	var base := _load_starter()
	var before := base.final_drive_ratio
	var clone := base.with_overrides({
		"no_such_prop": "nope",
		"final_drive_ratio": "not_a_float",
		"gear_ratios": "not_an_array",
		"mass_kg": false,
	})
	assert_that(clone.final_drive_ratio).is_equal_approx(before, 0.01)
	assert_that(clone.mass_kg).is_equal_approx(base.mass_kg, 0.01)
	assert_that(Array(clone.gear_ratios)).is_equal(Array(base.gear_ratios))

func test_tuning_profile_clamps_ratios_and_mass_to_bounds() -> void:
	var base := _load_starter()
	var profile := TuningProfile.new(base)
	assert_that(TuningProfile.slider_to_factor(0.0)).is_equal_approx(0.7, 0.01)
	assert_that(TuningProfile.slider_to_factor(1.0)).is_equal_approx(1.3, 0.01)
	assert_that(TuningProfile.factor_to_slider(0.7)).is_equal_approx(0.0, 0.01)
	assert_that(TuningProfile.factor_to_slider(1.3)).is_equal_approx(1.0, 0.01)
	profile.set_gear_ratio(0, 999.0)
	assert_that(profile.get_gear_ratio(0)).is_equal_approx(base.gear_ratios[0] * 1.3, 0.01)
	profile.set_gear_ratio(0, 0.001)
	assert_that(profile.get_gear_ratio(0)).is_equal_approx(base.gear_ratios[0] * 0.7, 0.01)
	profile.set_gear_ratio(2, base.gear_ratios[2])
	assert_that(profile.get_gear_ratio(2)).is_equal_approx(base.gear_ratios[2], 0.01)
	profile.set_final_drive(999.0)
	assert_that(profile.get_final_drive()).is_equal_approx(base.final_drive_ratio * 1.3, 0.01)
	profile.set_final_drive(0.001)
	assert_that(profile.get_final_drive()).is_equal_approx(base.final_drive_ratio * 0.7, 0.01)
	profile.set_mass(0.001)
	assert_that(profile.get_mass()).is_equal_approx(base.mass_kg * 0.7, 0.01)
	profile.set_mass(1000.0)
	assert_that(profile.get_mass()).is_equal_approx(1000.0, 0.01)

func test_tuning_profile_round_trip_and_corrupt_save_clamp() -> void:
	var base := _load_starter()
	var profile := TuningProfile.new(base)
	profile.set_gear_ratio(1, base.gear_ratios[1] * 1.2)
	profile.set_final_drive(base.final_drive_ratio * 1.1)
	profile.set_mass(base.mass_kg * 0.9)
	var restored := TuningProfile.new(base)
	restored.from_dict(profile.to_dict())
	assert_that(restored.get_gear_ratio(1)).is_equal_approx(base.gear_ratios[1] * 1.2, 0.01)
	assert_that(restored.get_final_drive()).is_equal_approx(base.final_drive_ratio * 1.1, 0.01)
	assert_that(restored.get_mass()).is_equal_approx(base.mass_kg * 0.9, 0.01)
	var applied := restored.applied()
	assert_that(applied.final_drive_ratio).is_equal_approx(base.final_drive_ratio * 1.1, 0.01)
	assert_that(base.final_drive_ratio).is_equal_approx(3.8, 0.01)
	assert_that(base.mass_kg).is_equal_approx(1100.0, 0.01)
	var corrupt := TuningProfile.new(base)
	corrupt.from_dict({
		"gear_ratios": [-5.0, 99.9, base.gear_ratios[2], base.gear_ratios[3], base.gear_ratios[4]],
		"final_drive_ratio": -3.0,
		"mass_kg": 2.0,
	})
	assert_that(corrupt.get_gear_ratio(0)).is_equal_approx(base.gear_ratios[0] * 0.7, 0.01)
	assert_that(corrupt.get_gear_ratio(1)).is_equal_approx(base.gear_ratios[1] * 1.3, 0.01)
	assert_that(corrupt.get_gear_ratio(2)).is_equal_approx(base.gear_ratios[2], 0.01)
	assert_that(corrupt.get_final_drive()).is_equal_approx(base.final_drive_ratio * 0.7, 0.01)
	assert_that(corrupt.get_mass()).is_equal_approx(base.mass_kg * 0.7, 0.01)

func test_garage_tuning_and_paint_round_trip_via_save() -> void:
	var garage := Garage.new()
	garage.load_data({"owned_cars": ["starter_car"], "active_car": "starter_car"})
	garage.set_car_tuning("starter_car", {"final_drive_ratio": 4.2, "mass_kg": 950.0})
	garage.set_car_paint("starter_car", "pearl_white")

	var reloaded := Garage.new()
	reloaded.load_data(SaveManager.load_game(0))
	assert_that(reloaded.get_car_overrides("starter_car")["final_drive_ratio"]).is_equal_approx(4.2, 0.01)
	assert_that(reloaded.get_car_overrides("starter_car")["mass_kg"]).is_equal_approx(950.0, 0.01)
	assert_that(reloaded.get_car_paint("starter_car")).is_equal("pearl_white")

	var from_save := Garage.new_from_save()
	assert_that(from_save.get_car_paint("starter_car")).is_equal("pearl_white")
	assert_that(from_save.get_car_overrides("starter_car").has("final_drive_ratio")).is_true()

	# Writes merge per car: a later tuning write must not wipe the saved paint id.
	garage.set_car_tuning("starter_car", {"gear_ratios": [6.5, 3.5, 2.5, 1.8, 1.0]})
	assert_that(garage.get_car_overrides("starter_car").has("gear_ratios")).is_true()
	var after_merge := Garage.new()
	after_merge.load_data(SaveManager.load_game(0))
	assert_that(after_merge.get_car_paint("starter_car")).is_equal("pearl_white")
	assert_that(after_merge.get_car_overrides("starter_car").has("final_drive_ratio")).is_true()

func test_is_car_unlocked_gates_non_owned_and_license_locked_edits() -> void:
	_reset_license()
	var garage := Garage.new()
	garage.load_data({"owned_cars": ["starter_car", "cc0_hatchback_sports"]})
	assert_that(garage.is_car_unlocked("starter_car")).is_true()
	assert_that(garage.is_car_unlocked("cc0_hatchback_sports")).is_false()
	assert_that(garage.is_car_unlocked("cc0_race")).is_false()

	# Non-owned car edits are silently rejected.
	garage.set_car_paint("cc0_race", "midnight")
	garage.set_car_tuning("cc0_race", {"mass_kg": 500.0, "final_drive_ratio": 9.9})
	# Owned but license-locked (class B above the default tier) is rejected too.
	garage.set_car_paint("cc0_hatchback_sports", "slate")
	garage.set_car_tuning("cc0_hatchback_sports", {"mass_kg": 800.0})

	var reloaded := Garage.new()
	reloaded.load_data(SaveManager.load_game(0))
	assert_that(reloaded.get_car_paint("cc0_race")).is_equal("")
	assert_that(reloaded.get_car_overrides("cc0_race")).is_equal({})
	assert_that(reloaded.get_car_paint("cc0_hatchback_sports")).is_equal("")
	assert_that(reloaded.get_car_overrides("cc0_hatchback_sports")).is_equal({})

	# The freely-owned unlocked starter accepts edits.
	garage.set_car_paint("starter_car", "midnight")
	garage.set_car_tuning("starter_car", {"mass_kg": 980.0})
	var editable := Garage.new()
	editable.load_data(SaveManager.load_game(0))
	assert_that(editable.get_car_paint("starter_car")).is_equal("midnight")
	assert_that(editable.get_car_overrides("starter_car")["mass_kg"]).is_equal_approx(980.0, 0.01)

func test_dyno_readout_tracks_ratios_and_is_static() -> void:
	var base := _load_starter()
	var samples := TuningProfile.dyno_samples(base, 16)
	assert_that(samples.size()).is_equal(16)
	assert_that(float(samples[0]["rpm"])).is_equal_approx(base.idle_rpm, 0.01)
	assert_that(float(samples[15]["rpm"])).is_equal_approx(base.redline_rpm, 0.01)
	assert_that(float(samples[15]["torque"])).is_equal_approx(0.0, 0.01)
	assert_that(base.get_engine_torque(base.peak_rpm)).is_equal_approx(base.max_torque, 0.01)
	for sample in samples:
		assert_that(float(sample["torque"])).is_greater_equal(0.0)
		assert_that(float(sample["power"])).is_greater_equal(0.0)
	assert_that(float(samples[7]["wheel_force"])).is_greater(0.0)
	assert_that(TuningProfile.peak_power_hp(base)).is_greater(0.0)

	# A taller final drive multiplies the road force at the same rotor speed.
	var taller := base.with_overrides({"final_drive_ratio": base.final_drive_ratio * 1.2})
	var base_force := float(samples[7]["wheel_force"])
	var taller_force := float(TuningProfile.dyno_samples(taller, 16)[7]["wheel_force"])
	assert_that(taller_force).is_equal_approx(base_force * 1.2, 0.01)

func test_garage_scene_wires_three_tabs() -> void:
	var runner := scene_runner("res://scenes/ui/garage.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as Control
	assert_that(scene).is_not_null()
	var tabs := scene.get_node("%TuningTabs") as TabContainer
	assert_that(tabs).is_not_null()
	assert_that(tabs.get_tab_count()).is_equal(3)
	assert_that(tabs.get_tab_title(0)).is_equal("Garage")
	assert_that(tabs.get_tab_title(1)).is_equal("Tune")
	assert_that(tabs.get_tab_title(2)).is_equal("Paint")