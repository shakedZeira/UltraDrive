# tests/suites/test_highspeed_stability.gd
extends GdUnitTestSuite

## High-speed stability gate. Two mechanisms, both speed-gated, neither
## touching the low-speed arcade envelope:
## (1) Aero downforce is quadratic in speed and feeds the Pacejka D term, so at
##     the same slip angle a 200 km/h car produces measurably MORE lateral
##     force than the static-weight baseline - the grip margin high-speed was
##     missing. Aero cars (starter/race/sedan/muscle) carry a higher
##     downforce_coefficient than the arcade rally/hatch cars.
## (2) The yaw assist chases the KINEMATIC rate v*tan(steer)/wheelbase, which at
##     speed demands 10x+ more rotation than the tires can sustain (Pacejka
##     saturates) and slammed the full assist torque into over-rotating the
##     body. The target is now clamped into the achievable envelope mu*g/v, so
##     the assist only guides yaw up to what the tires can hold and otherwise
##     damps the excess (real countersteer). Pure headless math - no scene
##     tree, no frames, no timestamp-dependent values.

func _aero_config() -> CarConfig:
	var cfg := CarConfig.new()
	cfg.downforce_coefficient = 0.5
	cfg.frontal_area = 2.2
	cfg.mass_kg = 1100.0
	cfg.tire_D = 1.0
	return cfg

# --- Aero downforce: v^2 grip margin + Pacejka D effect ---

func test_aero_load_is_zero_at_rest() -> void:
	var cfg := _aero_config()
	assert_that(VehiclePhysics.compute_aero_load(0.0, cfg)).is_equal(0.0)
	assert_that(VehiclePhysics.compute_aero_load(-0.0, cfg)).is_equal(0.0)

func test_aero_load_scales_with_speed_squared() -> void:
	var cfg := _aero_config()
	var slow := VehiclePhysics.compute_aero_load(20.0, cfg)
	var fast := VehiclePhysics.compute_aero_load(40.0, cfg)
	assert_that(slow).is_greater(0.0)
	assert_that(fast).is_equal_approx(slow * 4.0, 0.01)

func test_aero_load_at_highway_speed_is_material_against_static_weight() -> void:
	var cfg := _aero_config()
	var load: float = VehiclePhysics.compute_aero_load(55.6, cfg)
	var static_weight := cfg.mass_kg * 9.8
	# 55.6 m/s == 200 km/h; the load must be a meaningful fraction of the car's
	# weight (the whole point of raising the aero cars), but small enough that a
	# flatter aero car is nowhere near doubling its grip.
	assert_that(load).is_greater(static_weight * 0.15)
	assert_that(load).is_less(static_weight * 0.30)

func test_high_speed_aero_raises_lateral_capacity_at_same_slip() -> void:
	var cfg := _aero_config()
	var static_normal := cfg.mass_kg * 9.8 / 4.0
	var aero_per_wheel := VehiclePhysics.compute_aero_load(55.6, cfg) / 4.0
	var baseline: float = TireModel.calculate_lateral_force(0.06, static_normal, cfg, 1.3, 1.0)
	var with_aero: float = TireModel.calculate_lateral_force(0.06, static_normal + aero_per_wheel, cfg, 1.3, 1.0)
	var expected: float = baseline * ((static_normal + aero_per_wheel) / static_normal)
	# Pacejka lateral force is linear in the D term, which is linear in normal
	# load, so the aero uplift scales the same slip-angle output exactly.
	assert_that(with_aero).is_greater(baseline)
	assert_that(with_aero).is_equal_approx(expected, 0.5)

func test_aero_cars_carry_more_downforce_than_rally_cars() -> void:
	var race := load("res://resources/cars/cc0_race.tres") as CarConfig
	var rally := load("res://resources/cars/rally_hatch.tres") as CarConfig
	var hatch := load("res://resources/cars/cc0_hatchback_sports.tres") as CarConfig
	var starter := load("res://resources/cars/starter_car.tres") as CarConfig
	var sedan := load("res://resources/cars/cc0_sedan_sports.tres") as CarConfig
	var muscle := load("res://resources/cars/muscle_car.tres") as CarConfig
	assert_that(race).is_not_null()
	assert_that(rally).is_not_null()
	assert_that(hatch).is_not_null()
	assert_that(starter).is_not_null()
	assert_that(sedan).is_not_null()
	assert_that(muscle).is_not_null()
	if race == null or rally == null or hatch == null or starter == null or sedan == null or muscle == null:
		return
	# The aero ladder (coupe/race/sedan/muscle) must out-carry the arcade
	# rally/hatch cars, so high-speed grip margin is a real differentiator.
	assert_that(starter.downforce_coefficient).is_greater(rally.downforce_coefficient)
	assert_that(race.downforce_coefficient).is_greater(rally.downforce_coefficient)
	assert_that(sedan.downforce_coefficient).is_greater(rally.downforce_coefficient)
	assert_that(muscle.downforce_coefficient).is_greater(rally.downforce_coefficient)
	assert_that(hatch.downforce_coefficient).is_less_equal(rally.downforce_coefficient)

# --- Yaw assist: grip-limited target + true countersteer damping ---

func test_kinematic_yaw_demand_is_unachievable_at_speed() -> void:
	# 200 km/h at ~10.5 deg lock (max after the speed taper): the kinematic
	# demand v*tan(steer)/L is ~4 rad/s; at arcade grip 1.3 the tires can only
	# deliver mu*g/v ~0.23 rad/s (>17x less). This is the over-demand the
	# pre-fix assist chased, cold.
	var forward := 55.6
	var steer := 0.183
	var grip := 1.3
	var kinematic := forward * tan(steer) / 2.5
	var cap := VehiclePhysics.max_achievable_yaw_rate(forward, grip)
	assert_that(cap).is_between(0.2, 0.25)
	assert_that(kinematic).is_greater(cap * 10.0)

func test_yaw_assist_target_is_clamped_to_achievable_envelope() -> void:
	var forward := 55.6
	var steer := 0.183
	var wheelbase := 2.5
	var grip := 1.3
	var cap := VehiclePhysics.max_achievable_yaw_rate(forward, grip)
	var target := VehiclePhysics.compute_stability_yaw_target(forward, steer, wheelbase, grip)
	assert_that(target).is_equal(cap)
	# Zero steer at speed still damps toward rest yaw (straight-line stability).
	assert_that(VehiclePhysics.compute_stability_yaw_target(forward, 0.0, wheelbase, grip)).is_equal(0.0)
	# Negative steer clamps symmetrically.
	assert_that(VehiclePhysics.compute_stability_yaw_target(forward, -steer, wheelbase, grip)).is_equal(-cap)
	# Near-rest: the achievable envelope is huge, so low-speed assistance keeps
	# the plain kinematic rate (arcade drift feel untouched).
	var low_target := VehiclePhysics.compute_stability_yaw_target(2.0, 0.3, wheelbase, grip)
	var low_kin := 2.0 * tan(0.3) / wheelbase
	assert_that(low_kin).is_less(VehiclePhysics.max_achievable_yaw_rate(2.0, grip))
	assert_that(low_target).is_equal_approx(low_kin, 0.0001)

func test_yaw_assist_torque_opposes_spin_and_is_zero_at_target() -> void:
	var target := 0.23
	assert_that(VehiclePhysics.stability_yaw_torque(target, 0.5, 800.0)).is_less(0.0)
	assert_that(VehiclePhysics.stability_yaw_torque(target, target, 800.0)).is_equal(0.0)
	assert_that(VehiclePhysics.stability_yaw_torque(target, 0.1, 800.0)).is_greater(0.0)
	# An outright spin (2x the achievable envelope) returns a large damping N*m.
	assert_that(VehiclePhysics.stability_yaw_torque(target, 0.8, 800.0)).is_less(-200.0)

func test_high_speed_entry_torque_is_smaller_with_grip_cap() -> void:
	# Same simulated high-speed corner entry: the pre-fix torque clamped to the
	# full 800 N*m (pushing for 4.1 rad/s the tires cannot produce); with the
	# grip cap the same entry is guided with ~100 N*m - enough to reach the
	# achievable cornering yaw, an order of magnitude shy of the old slam.
	var forward := 55.6
	var steer := 0.183
	var wheelbase := 2.5
	var grip := 1.3
	var current_yaw := 0.1
	var kinematic_target := forward * tan(steer) / wheelbase
	var old_demand := minf(800.0 * (kinematic_target - current_yaw), 800.0)
	var capped_target := VehiclePhysics.compute_stability_yaw_target(forward, steer, wheelbase, grip)
	var capped_torque := VehiclePhysics.stability_yaw_torque(capped_target, current_yaw, 800.0)
	assert_that(old_demand).is_equal(800.0)
	assert_that(capped_torque).is_greater(0.0)
	assert_that(capped_torque).is_less_equal(800.0)
	assert_that(capped_torque).is_less(old_demand * 0.5)
	assert_that(capped_torque).is_equal_approx(800.0 * (capped_target - current_yaw), 0.01)