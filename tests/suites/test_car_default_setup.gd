# tests/suites/test_car_default_setup.gd
extends GdUnitTestSuite

## AAA-6 acceptance gate: every resources/cars/*.tres ships a staged
## default_setup block (springs/dampers/diff/balance baselines + design intent)
## whose numeric keys mirror real CarConfig export names, sit inside the valid
## config bounds, and match the shipped physics baseline the player actually
## feels; and the Drivetrain lateral-load downshift veto rejects a forced drop
## under hard lateral G while always allowing at rest / straight-line (including
## the AUTO speed-table path, which funnels through the same shift_down site).
## Pure/headless: RefCounted only (CarConfig, Drivetrain) - no nodes to leak.

const RALLY_CONFIG: CarConfig = preload("res://resources/cars/rally_hatch.tres")

const SETUP_NUMERIC_KEYS: Array[String] = [
	"spring_rate",
	"damper_compression",
	"damper_rebound",
	"suspension_travel",
	"ride_height",
	"anti_roll_bar",
	"diff_type",
	"lsd_preload",
	"lsd_ramp_angle",
	"brake_bias",
]

## Valid config bounds (min, max) for each setup key. These are the ranges the
## acceptance gate enforces so setup data can never ship a physically absurd
## value (negative spring, >2 diff enum, >1 brake bias, etc.).
const SETUP_BOUNDS: Dictionary = {
	"spring_rate": Vector2(1000.0, 1000000.0),
	"damper_compression": Vector2(100.0, 200000.0),
	"damper_rebound": Vector2(100.0, 200000.0),
	"suspension_travel": Vector2(0.01, 0.5),
	"ride_height": Vector2(0.01, 1.0),
	"anti_roll_bar": Vector2(0.0, 1000000.0),
	"diff_type": Vector2(0.0, 2.0),
	"lsd_preload": Vector2(0.0, 2000.0),
	"lsd_ramp_angle": Vector2(0.0, 90.0),
	"brake_bias": Vector2(0.0, 1.0),
}

## Every car .tres currently in the folder (future cars must ship a block too,
## so discover by glob rather than a frozen list).
func _car_paths() -> Array[String]:
	var dir := DirAccess.open("res://resources/cars")
	var paths: Array[String] = []
	if dir == null:
		return paths
	for name: String in dir.get_files():
		if name.ends_with(".tres"):
			paths.append("res://resources/cars/" + name)
	paths.sort()
	return paths

func test_every_car_tres_exposes_valid_default_setup() -> void:
	var paths := _car_paths()
	assert_that(paths.size()).is_greater_equal(6)
	for path: String in paths:
		var config := load(path) as CarConfig
		assert_that(config).is_not_null()
		var setup: Dictionary = config.default_setup
		assert_that(setup.is_empty()).is_false()
		assert_that(setup.has("design_intent")).is_true()
		var intent := str(setup.get("design_intent", ""))
		assert_that(intent.is_empty()).is_false()
		for key: String in SETUP_NUMERIC_KEYS:
			assert_that(setup.has(key)).is_true()
			var value: float = float(setup.get(key, -1.0))
			var bounds: Vector2 = SETUP_BOUNDS[key]
			assert_that(value).is_greater_equal(bounds.x)
			assert_that(value).is_less_equal(bounds.y)

func test_default_setup_documents_shipped_baseline() -> void:
	# The setup block must be a setup sheet, not fiction: every numeric key has
	# to match the effective CarConfig value the car actually drives (the .tres
	# override or the script default). Retuning a car without touching its block
	# fails here on purpose - that is the AAA-6 cadence discipline.
	for path: String in _car_paths():
		var config := load(path) as CarConfig
		var setup: Dictionary = config.default_setup
		for key: String in SETUP_NUMERIC_KEYS:
			var shipped: float = float(config.get(key))
			var staged: float = float(setup.get(key))
			assert_that(staged).is_equal_approx(shipped, 0.01)

func test_downshift_veto_rejects_under_hard_lateral_g() -> void:
	var dt := Drivetrain.new()
	dt.manual_mode = true
	dt.current_gear = 2
	dt.set_wheel_speed(2.0)
	dt.set_lateral_g(1.4)
	dt.shift_down(RALLY_CONFIG)
	assert_that(dt.current_gear).is_equal(2)
	assert_that(dt.is_shifting).is_false()

func test_downshift_veto_below_threshold_allows() -> void:
	var dt := Drivetrain.new()
	dt.manual_mode = true
	dt.current_gear = 2
	dt.set_wheel_speed(2.0)
	dt.set_lateral_g(0.9)
	dt.shift_down(RALLY_CONFIG)
	assert_that(dt.current_gear).is_equal(1)
	assert_that(dt.is_shifting).is_true()

func test_downshift_veto_allows_straight_line_downshift() -> void:
	var dt := Drivetrain.new()
	dt.manual_mode = true
	dt.current_gear = 2
	dt.set_wheel_speed(2.0)
	dt.set_lateral_g(0.0)
	dt.shift_down(RALLY_CONFIG)
	assert_that(dt.current_gear).is_equal(1)
	assert_that(dt.is_shifting).is_true()

func test_downshift_veto_allows_reverse_at_rest() -> void:
	# At-rest 1st -> R (the manual reverse entry) must never be blocked.
	var dt := Drivetrain.new()
	dt.manual_mode = true
	dt.set_lateral_g(0.0)
	dt.shift_down(RALLY_CONFIG)
	assert_that(dt.current_gear).is_equal(-1)
	assert_that(dt.is_shifting).is_true()

func test_auto_downshift_is_vetoed_under_hard_lateral_g() -> void:
	# 5 m/s (~18 km/h) is below the rally 34 km/h 3rd->2nd speed point, so the
	# AUTO box would normally drop a gear - the lateral veto must stop it too.
	var dt := Drivetrain.new()
	dt.manual_mode = false
	dt.current_gear = 3
	dt.set_wheel_speed(5.0)
	dt.set_lateral_g(1.4)
	dt.update(1.0 / 60.0, 1.0, RALLY_CONFIG)
	assert_that(dt.current_gear).is_equal(3)

func test_auto_downshift_happens_without_lateral_load() -> void:
	var dt := Drivetrain.new()
	dt.manual_mode = false
	dt.current_gear = 3
	dt.set_wheel_speed(5.0)
	dt.set_lateral_g(0.0)
	dt.update(1.0 / 60.0, 1.0, RALLY_CONFIG)
	assert_that(dt.current_gear).is_equal(2)

func test_lateral_g_setter_clamps_negative() -> void:
	var dt := Drivetrain.new()
	dt.set_lateral_g(-0.5)
	assert_that(dt.lateral_g).is_equal_approx(0.0, 0.001)

func test_reset_clears_lateral_g() -> void:
	var dt := Drivetrain.new()
	dt.set_lateral_g(1.4)
	dt.reset()
	assert_that(dt.lateral_g).is_equal_approx(0.0, 0.001)

func test_lateral_g_veto_feed_is_zero_on_straight_line_and_scales_with_speed() -> void:
	assert_that(VehiclePhysics.lateral_g_for_shift_veto(0.0, 50.0)).is_equal_approx(0.0, 0.001)
	assert_that(VehiclePhysics.lateral_g_for_shift_veto(0.2, 50.0)).is_greater(1.0)