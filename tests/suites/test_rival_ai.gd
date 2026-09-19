# tests/suites/test_rival_ai.gd
extends GdUnitTestSuite

## S5 race-rival AI gates. Covers the pure racing-line builder (finite, smooth,
## resampled, deterministic per class+tier+seed), the strictly-ordered skill
## tier / car-class pace tables, rubber-band scope (never the player; only
## Novice / traffic when GameState.rubber_band_assist is on), the RivalDriver
## control path writing input_override, the start_race configured-roster grid
## spawn in roster order, and rival standings membership with the existing
## lap->checkpoint->distance tie-break. Headless-safe: everything asserts
## synchronously; after_test frees every spawned/managed node and resets the
## autoload state.

const RIVAL_SCENE := "res://scenes/vehicle/rival_car.tscn"
const RING_POINTS := 48
const CheckpointStub := preload("res://tests/suites/checkpoint_stub.gd")

var _managed_cars: Array = []
var _managed_drivers: Array = []
var _managed_stubs: Array = []

func before_test() -> void:
	GameState.rubber_band_assist = true
	RaceManager.rival_roster = []
	RaceManager.rival_centerline = []
	RaceManager.rival_vehicle_scene = null
	RaceManager.rival_spawner = Callable()
	_managed_cars.clear()
	_managed_drivers.clear()
	_managed_stubs.clear()

func after_test() -> void:
	for car in _managed_cars:
		if is_instance_valid(car):
			car.free()
	for driver in _managed_drivers:
		if is_instance_valid(driver):
			driver.free()
	for stub in _managed_stubs:
		if is_instance_valid(stub):
			stub.free()
	for child in RaceManager.get_children():
		if child is LapCounter or child is VehiclePhysics:
			child.free()
	RaceManager._spawned_rivals = []
	RaceManager._participants = []
	RaceManager._lap_counters = {}
	RaceManager.is_race_active = false
	RaceManager._checkpoints_dirty = true
	RaceManager.rival_roster = []
	RaceManager.rival_centerline = []
	RaceManager.rival_vehicle_scene = null
	RaceManager.rival_spawner = Callable()
	RaceManager._countdown = RaceCountdown.new()
	RaceManager.consume_pending_race()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()
	GameState.rubber_band_assist = true
	_managed_cars.clear()
	_managed_drivers.clear()
	_managed_stubs.clear()

func _build_ring() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in range(RING_POINTS):
		var angle := float(i) / float(RING_POINTS) * TAU
		points.append(Vector3(cos(angle) * 50.0, 0.0, sin(angle) * 50.0))
	return points

func _new_stub_car() -> VehiclePhysics:
	## Fully-formed vehicle (rival scene) so wheel nodes exist; staged at the
	## origin but frozen so no physics tick moves it mid-assert.
	var car := (load(RIVAL_SCENE) as PackedScene).instantiate() as VehiclePhysics
	car.freeze = true
	car.gravity_scale = 0.0
	_managed_cars.append(car)
	return car

func _new_rival_driver(car: VehiclePhysics, line: Array[Vector3], tier: String, car_class: String) -> RivalDriver:
	var driver := RivalDriver.new()
	driver.configure(line, tier, car_class)
	car.add_child(driver)
	_managed_drivers.append(driver)
	return driver

func _load_config(name: String) -> CarConfig:
	return load("res://resources/cars/%s.tres" % name) as CarConfig

func _find_driver(car: VehiclePhysics) -> RivalDriver:
	for child in car.get_children():
		if child is RivalDriver:
			return child as RivalDriver
	return null

func _count_in(items: Array, needle: VehiclePhysics) -> int:
	var n := 0
	for item in items:
		if item == needle:
			n += 1
	return n

func _add_stub_checkpoint(index: int) -> CheckpointStub:
	var stub := CheckpointStub.new()
	stub.index = index
	add_child(stub)
	_managed_stubs.append(stub)
	return stub

func test_racing_line_is_finite_and_stays_on_road() -> void:
	var ring := _build_ring()
	var reference := RacingLine.resample_arc(ring, 1.0)
	for tier: String in ["Novice", "Skilled", "Expert"]:
		for cls: String in ["D", "C", "B", "A", "S"]:
			var line := RacingLine.build_racing_line(ring, cls, tier, 10.0, 4.0)
			assert_that(RacingLine.all_finite(line)).is_true()
			assert_that(line.size()).is_greater_equal(RING_POINTS)
			assert_float(RacingLine.max_lateral_deviation(line, reference)).is_less_equal(2.01)
			assert_float(RacingLine.max_segment_length(line)).is_greater(0.0)

func test_racing_line_is_smooth_and_regularly_spaced() -> void:
	var ring := _build_ring()
	var line := RacingLine.build_racing_line(ring, "B", "Expert", 10.0, 4.0)
	assert_float(RacingLine.max_turn_angle(line)).is_less(0.9)
	var ideal := 50.0 * TAU / float(RING_POINTS)
	assert_float(RacingLine.max_segment_length(line)).is_less(ideal * 1.6)

func test_racing_line_is_deterministic_per_config_and_seed() -> void:
	var ring := _build_ring()
	var a := RacingLine.build_racing_line(ring, "B", "Skilled", 10.0, 4.0)
	var b := RacingLine.build_racing_line(ring, "B", "Skilled", 10.0, 4.0)
	assert_that(a).is_equal(b)
	var expert := RacingLine.build_racing_line(ring, "B", "Expert", 10.0, 4.0)
	assert_that(a).is_not_equal(expert)
	var c := RacingLine.build_racing_line(ring, "B", "Skilled", 10.0, 4.0, 777)
	var d := RacingLine.build_racing_line(ring, "B", "Skilled", 10.0, 4.0, 777)
	assert_that(c).is_equal(d)
	var e := RacingLine.build_racing_line(ring, "B", "Skilled", 10.0, 4.0, 778)
	assert_that(c).is_not_equal(e)

func test_racing_line_ignores_undersized_centerline() -> void:
	var two: Array[Vector3] = [Vector3.ZERO, Vector3.RIGHT]
	assert_that(RacingLine.build_racing_line(two, "B", "Expert", 10.0, 4.0).size()).is_equal(2)
	var ring := _build_ring()
	var degenerate: Array[Vector3] = [ring[0], ring[1], ring[0]]
	var line := RacingLine.build_racing_line(degenerate, "B", "Skilled", 10.0, 4.0)
	assert_that(RacingLine.all_finite(line)).is_true()

func test_tier_paces_strictly_ordered() -> void:
	assert_float(RacingLine.tier_pace("Novice")).is_less(RacingLine.tier_pace("Skilled"))
	assert_float(RacingLine.tier_pace("Skilled")).is_less(RacingLine.tier_pace("Expert"))

func test_class_pace_bands_ordered_d_to_s() -> void:
	assert_float(RacingLine.pace_band("D")).is_less(RacingLine.pace_band("C"))
	assert_float(RacingLine.pace_band("C")).is_less(RacingLine.pace_band("B"))
	assert_float(RacingLine.pace_band("B")).is_less(RacingLine.pace_band("A"))
	assert_float(RacingLine.pace_band("A")).is_less(RacingLine.pace_band("S"))
	assert_float(RacingLine.pace_band("c")).is_greater(RacingLine.pace_band("D"))

func test_rubber_band_never_applies_to_player() -> void:
	assert_that(AIRubberBanding.multiplier_for(AIRubberBanding.CATEGORY_PLAYER, -12.0, true)).is_equal(1.0)
	assert_that(AIRubberBanding.multiplier_for(AIRubberBanding.CATEGORY_PLAYER, 12.0, true)).is_equal(1.0)
	assert_that(AIRubberBanding.multiplier_for(AIRubberBanding.CATEGORY_PLAYER, -12.0, false)).is_equal(1.0)

func test_rubber_band_scope_novice_traffic_only_when_assist_on() -> void:
	assert_that(AIRubberBanding.multiplier_for("Novice", -10.0, true)).is_equal(1.05)
	assert_that(AIRubberBanding.multiplier_for("Novice", 10.0, true)).is_equal(0.95)
	assert_that(AIRubberBanding.multiplier_for("Traffic", -10.0, true)).is_equal(1.05)
	assert_that(AIRubberBanding.multiplier_for("Skilled", -10.0, true)).is_equal(1.0)
	assert_that(AIRubberBanding.multiplier_for("Expert", 10.0, true)).is_equal(1.0)
	assert_that(AIRubberBanding.multiplier_for("Novice", -10.0, false)).is_equal(1.0)

func test_rival_pace_multiplier_is_class_band_times_tier() -> void:
	assert_float(RacingLine.pace_for("D", "Novice")).is_equal_approx(0.8 * 0.55, 0.0001)
	assert_float(RacingLine.pace_for("B", "Skilled")).is_equal_approx(0.8 * 1.0, 0.0001)
	assert_float(RacingLine.pace_for("A", "Expert")).is_equal_approx(1.2 * 0.92, 0.0001)
	assert_float(RacingLine.pace_for("S", "Expert")).is_equal_approx(1.2 * 1.05, 0.0001)
	assert_float(RacingLine.pace_for("D", "Expert")).is_less(RacingLine.pace_for("S", "Novice"))

func test_rival_control_writes_input_override_never_rubber_banded_for_player() -> void:
	var player := _new_stub_car()
	VehicleManager.register_player_car(player)
	player.freeze = true
	player.gravity_scale = 0.0
	add_child(player)
	var driver := _new_rival_driver(player, _build_ring(), "Novice", "B")
	driver._apply_control(0.5, 1.0, 0.0, 1.0 / 60.0)
	# Player-tagged rival always runs the exact (class x tier) pace, no gap knob.
	assert_float(driver.get_pace_multiplier()).is_equal_approx(0.8 * 0.8, 0.0001)
	assert_float(player.input_override.x).is_equal_approx(0.5, 0.0001)
	assert_float(player.input_override.y).is_equal_approx(0.8 * 0.8, 0.0001)

func test_rival_control_folds_rubber_band_only_for_novice() -> void:
	var player := _new_stub_car()
	VehicleManager.register_player_car(player)
	player.freeze = true
	player.gravity_scale = 0.0
	add_child(player)
	var novice_car := _new_stub_car()
	novice_car.freeze = true
	novice_car.gravity_scale = 0.0
	add_child(novice_car)
	var skilled_car := _new_stub_car()
	skilled_car.freeze = true
	skilled_car.gravity_scale = 0.0
	add_child(skilled_car)
	var novice := _new_rival_driver(novice_car, _build_ring(), "Novice", "B")
	var skilled := _new_rival_driver(skilled_car, _build_ring(), "Skilled", "B")
	RaceManager.start_race([player, novice_car, skilled_car], 3)
	var novice_counter: LapCounter = RaceManager.get_lap_counter(novice_car)
	var skilled_counter: LapCounter = RaceManager.get_lap_counter(skilled_car)
	# Put both rivals ~4 s ahead of the player (beyond BASE_GAP) by giving
	# them a _race_start_time 4 s LATER than the player's: the player's total
	# time exceeds the rival's by 4 s, so the ~0.95/1.05 gap knobs WOULD
	# apply... but only Novice actually gets them.
	var player_counter: LapCounter = RaceManager.get_lap_counter(player)
	var anchor := float(player_counter.get("_race_start_time"))
	novice_counter.set("_race_start_time", anchor + 4.0)
	skilled_counter.set("_race_start_time", anchor + 4.0)
	novice._apply_control(0.0, 1.0, 0.0, 1.0 / 60.0)
	assert_float(novice_car.input_override.y).is_equal_approx(0.8 * 0.8 * 0.95, 0.0001)
	skilled._apply_control(0.0, 1.0, 0.0, 1.0 / 60.0)
	assert_float(skilled_car.input_override.y).is_equal_approx(0.8 * 1.0, 0.0001)

func test_start_race_spawns_configured_rival_roster_in_grid_order() -> void:
	var player := _new_stub_car()
	VehicleManager.register_player_car(player)
	player.freeze = true
	player.gravity_scale = 0.0
	add_child(player)
	RaceManager.set_rival_vehicle_scene(load(RIVAL_SCENE) as PackedScene)
	RaceManager.set_rival_centerline(_build_ring())
	RaceManager.set_rival_roster([
		RaceManager.rival_spec(_load_config("starter_car"), "Novice"),
		RaceManager.rival_spec(_load_config("rally_hatch"), "Skilled"),
		RaceManager.rival_spec(_load_config("cc0_race"), "Expert"),
	])
	RaceManager.start_race([player], 3)
	var spawned := RaceManager.get_spawned_rivals()
	assert_that(spawned.size()).is_equal(3)
	assert_that(RaceManager._participants.size()).is_equal(4)
	# Grid order preserved: roster 0/1 share the front row, roster 2 the back row.
	assert_float(spawned[0].global_position.x).is_less(spawned[1].global_position.x)
	assert_float(spawned[0].global_position.z).is_less(spawned[2].global_position.z)
	# Each spawn carries a RivalDriver configured with the roster tier + class.
	assert_that(_find_driver(spawned[0]).get_tier()).is_equal("Novice")
	assert_that(_find_driver(spawned[0]).get_car_class()).is_equal("D")
	assert_that(_find_driver(spawned[1]).get_tier()).is_equal("Skilled")
	assert_that(_find_driver(spawned[1]).get_car_class()).is_equal("B")
	assert_that(_find_driver(spawned[2]).get_tier()).is_equal("Expert")
	assert_that(_find_driver(spawned[2]).get_car_class()).is_equal("A")
	# Standings members are the player plus exactly one of each rival.
	var standings := RaceManager.get_standings()
	assert_that(standings.size()).is_equal(4)
	for car in spawned:
		assert_that(_count_in(standings, car)).is_equal(1)
	assert_that(_count_in(standings, player)).is_equal(1)
	# Racing lines were wired into every rival driver.
	assert_that(_find_driver(spawned[0]).waypoints.size()).is_greater_equal(RING_POINTS)

func test_rival_roster_in_standings_with_checkpoint_tiebreak() -> void:
	var player := _new_stub_car()
	VehicleManager.register_player_car(player)
	player.freeze = true
	player.gravity_scale = 0.0
	add_child(player)
	var cp0 := _add_stub_checkpoint(0)
	cp0.overlaps = [player]
	RaceManager.set_rival_vehicle_scene(load(RIVAL_SCENE) as PackedScene)
	RaceManager.set_rival_centerline(_build_ring())
	RaceManager.set_rival_roster([
		RaceManager.rival_spec(_load_config("cc0_race"), "Expert"),
		RaceManager.rival_spec(_load_config("rally_hatch"), "Skilled"),
	])
	RaceManager.start_race([player], 2)
	RaceManager.reset_checkpoints()
	# Player crosses checkpoint 0 -> leads on the lap->checkpoint tie-break.
	var counter: LapCounter = RaceManager.get_lap_counter(player)
	counter.update(player, cp0)
	var standings := RaceManager.get_standings()
	assert_that(standings.size()).is_equal(3)
	assert_that(standings[0]).is_equal(player)
	for car in RaceManager.get_spawned_rivals():
		assert_that(standings.has(car)).is_true()