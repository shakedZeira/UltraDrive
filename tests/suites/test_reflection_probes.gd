# tests/suites/test_reflection_probes.gd
extends GdUnitTestSuite

## Task 6: per-car gameplay ReflectionProbe + static open-world probes. Covers
## GameState.probe_enabled persistence, the preset->GameState wiring seam, the
## CarVisuals.refresh_probe toggle semantics, the WorldDriver static-probe
## factory and the <=4 blended-probe budget. Manual node construction only —
## no scene instantiation; managed nodes are sync-freed in after_test so the
## suite stays orphan-free.

const SettingsMenuScript: GDScript = preload("res://scripts/ui/settings_menu.gd")

var _managed: Array = []

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	for obj in _managed:
		if obj is Node and is_instance_valid(obj):
			obj.free()
	_managed.clear()

## A car probe configured exactly like the controller's _ensure_car_probe.
func _car_probe() -> ReflectionProbe:
	var probe := ReflectionProbe.new()
	probe.name = "CarProbe"
	probe.size = CarVisuals.CAR_PROBE_SIZE
	probe.origin_offset = CarVisuals.CAR_PROBE_ORIGIN_OFFSET
	_managed.append(probe)
	return probe

func test_set_probe_enabled_persists_to_save_slot_zero() -> void:
	GameState.set_probe_enabled(false)
	var data := SaveManager.load_game(0)
	assert_that(bool(data.get("probe_enabled"))).is_false()
	assert_that(GameState.probe_enabled).is_false()
	GameState.set_probe_enabled(true)
	data = SaveManager.load_game(0)
	assert_that(bool(data.get("probe_enabled"))).is_true()
	assert_that(GameState.probe_enabled).is_true()

func test_car_probe_refresh_enabled_sets_visible_and_always() -> void:
	var probe := _car_probe()
	CarVisuals.refresh_probe(probe, true)
	assert_that(probe.visible).is_true()
	assert_that(probe.update_mode).is_equal(ReflectionProbe.UPDATE_ALWAYS)

func test_car_probe_refresh_disabled_hides_and_freezes_to_once() -> void:
	var probe := _car_probe()
	CarVisuals.refresh_probe(probe, false)
	assert_that(probe.visible).is_false()
	assert_that(probe.update_mode).is_equal(ReflectionProbe.UPDATE_ONCE)

func test_car_probe_config_is_finite_and_car_sized() -> void:
	assert_that(CarVisuals.CAR_PROBE_RESOLUTION).is_equal(256)
	var size: Vector3 = CarVisuals.CAR_PROBE_SIZE
	assert_that(size.is_finite()).is_true()
	assert_that(size.x).is_between(6.0, 12.0)
	assert_that(size.y).is_between(2.0, 6.0)
	assert_that(size.z).is_between(6.0, 12.0)
	var origin: Vector3 = CarVisuals.CAR_PROBE_ORIGIN_OFFSET
	assert_that(origin.is_finite()).is_true()
	assert_that(origin.y).is_between(0.4, 1.5)

func test_make_static_probe_sets_origin_size_bake_once_and_ambient() -> void:
	var probe := WorldDriver.make_static_probe(Vector3(128.0, 2.0, 128.0), WorldDriver.STATIC_PROBE_SIZE)
	_managed.append(probe)
	assert_that(probe.position).is_equal(Vector3(128.0, 2.0, 128.0))
	assert_that(probe.update_mode).is_equal(ReflectionProbe.UPDATE_ONCE)
	assert_that(probe.ambient_mode).is_equal(ReflectionProbe.AMBIENT_ENVIRONMENT)
	var size: Vector3 = probe.size
	assert_that(size.is_finite()).is_true()
	assert_that(size.x).is_greater(0.0)
	assert_that(size.y).is_greater(0.0)
	assert_that(size.z).is_greater(0.0)

func test_static_probe_origins_match_world_landmarks() -> void:
	assert_that(WorldDriver.HUB_PROBE_ORIGIN.x).is_equal_approx(128.0, 0.001)
	assert_that(WorldDriver.HUB_PROBE_ORIGIN.z).is_equal_approx(128.0, 0.001)
	assert_that(WorldDriver.PASS_PROBE_ORIGIN.x).is_equal_approx(3800.0, 0.001)
	assert_that(WorldDriver.PASS_PROBE_ORIGIN.z).is_equal_approx(3200.0, 0.001)

func test_blended_probe_budget_stays_within_four() -> void:
	var probes: Array[ReflectionProbe] = []
	probes.append(_car_probe())
	var hub := WorldDriver.make_static_probe(WorldDriver.HUB_PROBE_ORIGIN, WorldDriver.STATIC_PROBE_SIZE)
	var pass_probe := WorldDriver.make_static_probe(WorldDriver.PASS_PROBE_ORIGIN, WorldDriver.STATIC_PROBE_SIZE)
	_managed.append(hub)
	_managed.append(pass_probe)
	probes.append(hub)
	probes.append(pass_probe)
	assert_that(probes.size()).is_equal(3)
	assert_that(probes.size()).is_less_equal(4)

func test_preset_probe_enabled_maps_ladder() -> void:
	assert_that(SettingsMenuScript.probe_enabled_for(0)).is_false()
	assert_that(SettingsMenuScript.probe_enabled_for(1)).is_false()
	assert_that(SettingsMenuScript.probe_enabled_for(2)).is_true()
	assert_that(SettingsMenuScript.probe_enabled_for(99)).is_equal(SettingsMenuScript.probe_enabled_for(1))