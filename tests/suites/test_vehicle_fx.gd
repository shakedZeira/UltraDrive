# tests/suites/test_vehicle_fx.gd
extends GdUnitTestSuite

## S8 gate: the pooled VehicleFX GPUParticles3D layer plus the VehiclePhysics
## impact seam. Headless-safe by construction - the player-car scene carries
## the FX slot but the _ready emitter cull builds zero GPUParticles3D nodes, so
## budget/node caps are checked as constants and via a white-box emitter build,
## dust fires only off-asphalt, drift drives smoke, exhaust is a small
## throttle/idle-gated tailpipe puff, and the impact threshold is pure math
## over a stub velocity delta. All live nodes are freed in after_test so the
## run stays orphan-free.

var _managed_nodes: Array = []

func before_test() -> void:
	_managed_nodes.clear()

func after_test() -> void:
	for node in _managed_nodes:
		if is_instance_valid(node):
			node.free()
	_managed_nodes.clear()

func _new_fx() -> VehicleFX:
	var fx := VehicleFX.new()
	_managed_nodes.append(fx)
	return fx

func _new_car() -> VehiclePhysics:
	var car := VehiclePhysics.new()
	_managed_nodes.append(car)
	return car

func test_headless_scene_instantiates_zero_particle_nodes() -> void:
	var car := (load("res://scenes/vehicle/player_car.tscn") as PackedScene).instantiate()
	add_child(car)
	_managed_nodes.append(car)
	var particles := car.find_children("*", "GPUParticles3D", true, false)
	assert_that(particles.size()).is_equal(0)
	var fx := car.get_node_or_null("VehicleFX") as VehicleFX
	assert_that(fx).is_not_null()
	assert_that(fx.emitter_count()).is_equal(0)

func test_headless_fx_ready_culls_the_emitter_build() -> void:
	var fx := _new_fx()
	add_child(fx)
	assert_that(fx.emitter_count()).is_equal(0)
	assert_that(fx.get_child_count()).is_equal(0)

func test_emitter_node_budget_is_five() -> void:
	assert_that(VehicleFX.EMITTER_COUNT).is_equal(5)
	assert_that(VehicleFX.emitter_budget()).is_equal(5)

func test_channel_budget_caps_and_total() -> void:
	assert_that(VehicleFX.TOTAL_BUDGET).is_equal(
		VehicleFX.SMOKE_AMOUNT_CAP + VehicleFX.DUST_AMOUNT_CAP
		+ VehicleFX.SPARK_AMOUNT_CAP + VehicleFX.NITRO_AMOUNT_CAP
		+ VehicleFX.EXHAUST_AMOUNT_CAP
	)
	assert_that(VehicleFX.SMOKE_AMOUNT_CAP).is_greater(0)
	assert_that(VehicleFX.DUST_AMOUNT_CAP).is_greater(0)
	assert_that(VehicleFX.SPARK_AMOUNT_CAP).is_greater(0)
	assert_that(VehicleFX.NITRO_AMOUNT_CAP).is_greater(0)
	assert_that(VehicleFX.EXHAUST_AMOUNT_CAP).is_greater(0)

func test_channel_amounts_clamp_to_their_caps() -> void:
	assert_that(VehicleFX.clamped_channel_amount(VehicleFX.CHANNEL_SMOKE, 999999)).is_equal(VehicleFX.SMOKE_AMOUNT_CAP)
	assert_that(VehicleFX.clamped_channel_amount(VehicleFX.CHANNEL_DUST, -10)).is_equal(0)
	assert_that(VehicleFX.channel_cap(VehicleFX.CHANNEL_SPARKS)).is_equal(VehicleFX.SPARK_AMOUNT_CAP)
	assert_that(VehicleFX.clamped_channel_amount(VehicleFX.CHANNEL_EXHAUST, 999)).is_equal(VehicleFX.EXHAUST_AMOUNT_CAP)
	assert_that(VehicleFX.channel_cap("bogus")).is_equal(0)

func test_built_emitters_respect_the_node_and_amount_caps() -> void:
	var fx := _new_fx()
	fx._build_emitters()
	assert_that(fx.emitter_count()).is_equal(VehicleFX.emitter_budget())
	assert_that(fx.get_child_count()).is_equal(VehicleFX.emitter_budget())
	var limits := fx.emission_limits()
	var channels: Array = [
		VehicleFX.CHANNEL_SMOKE, VehicleFX.CHANNEL_DUST,
		VehicleFX.CHANNEL_SPARKS, VehicleFX.CHANNEL_FLAME,
		VehicleFX.CHANNEL_EXHAUST,
	]
	for channel: Variant in channels:
		var key := String(channel)
		var cap := int(limits[key])
		assert_that(cap).is_greater(0)
		var emitter := fx._emitters[key] as GPUParticles3D
		assert_that(emitter).is_not_null()
		assert_that(emitter.amount).is_greater(0)
		assert_that(emitter.amount).is_less_equal(cap)

func test_drift_smoke_channel_tracks_drift_state() -> void:
	var fx := _new_fx()
	assert_that(bool(fx.emission_channels()[VehicleFX.CHANNEL_SMOKE])).is_false()
	fx.set_drifting(true)
	assert_that(bool(fx.emission_channels()[VehicleFX.CHANNEL_SMOKE])).is_true()
	fx.set_drifting(false)
	assert_that(bool(fx.emission_channels()[VehicleFX.CHANNEL_SMOKE])).is_false()

func test_dust_channel_fires_only_off_asphalt() -> void:
	var fx := _new_fx()
	fx.set_surface_key(SurfaceRegistry.ASPHALT)
	assert_that(bool(fx.emission_channels()[VehicleFX.CHANNEL_DUST])).is_false()
	var offroad: Array[String] = [
		SurfaceRegistry.GRAVEL, SurfaceRegistry.DIRT, SurfaceRegistry.GRASS,
		SurfaceRegistry.MUD, SurfaceRegistry.SNOW,
	]
	for surface in offroad:
		fx.set_surface_key(surface)
		assert_that(bool(fx.emission_channels()[VehicleFX.CHANNEL_DUST])).is_true()
	assert_that(fx.get_surface_key()).is_equal(SurfaceRegistry.SNOW)

func test_nitro_flame_channel_is_gated_off_by_default() -> void:
	var fx := _new_fx()
	assert_that(bool(fx.emission_channels()[VehicleFX.CHANNEL_FLAME])).is_false()
	fx.set_nitro_active(true)
	assert_that(bool(fx.emission_channels()[VehicleFX.CHANNEL_FLAME])).is_true()
	fx.set_nitro_active(false)
	assert_that(bool(fx.emission_channels()[VehicleFX.CHANNEL_FLAME])).is_false()

func test_exhaust_channel_gates_on_throttle_or_idle() -> void:
	var fx := _new_fx()
	assert_that(bool(fx.emission_channels()[VehicleFX.CHANNEL_EXHAUST])).is_false()
	fx.set_throttle(0.5)
	assert_that(bool(fx.emission_channels()[VehicleFX.CHANNEL_EXHAUST])).is_true()
	fx.set_throttle(0.0)
	assert_that(bool(fx.emission_channels()[VehicleFX.CHANNEL_EXHAUST])).is_false()
	fx.set_speed_kmh(2.0)
	assert_that(bool(fx.emission_channels()[VehicleFX.CHANNEL_EXHAUST])).is_true()
	fx.set_speed_kmh(60.0)
	assert_that(bool(fx.emission_channels()[VehicleFX.CHANNEL_EXHAUST])).is_false()
	fx.set_throttle(-0.5)
	assert_that(bool(fx.emission_channels()[VehicleFX.CHANNEL_EXHAUST])).is_true()

func test_spark_burst_is_gated_by_minimum_strength_and_bounded() -> void:
	var fx := _new_fx()
	fx.on_impact(VehicleFX.SPARK_MIN_STRENGTH * 0.9)
	assert_that(bool(fx.emission_channels()[VehicleFX.CHANNEL_SPARKS])).is_false()
	fx.on_impact(VehicleFX.SPARK_MIN_STRENGTH * 2.0)
	var active_frames := 0
	for i in range(VehicleFX.SPARK_BURST_FRAMES + 4):
		var channel := bool(fx.emission_channels()[VehicleFX.CHANNEL_SPARKS])
		fx._process(1.0 / 60.0)
		if channel:
			active_frames += 1
	assert_that(active_frames).is_equal(VehicleFX.SPARK_BURST_FRAMES)
	assert_that(bool(fx.emission_channels()[VehicleFX.CHANNEL_SPARKS])).is_false()

func test_impact_threshold_math_over_a_stub_velocity_delta() -> void:
	var dt := 1.0 / 60.0
	var sharp := VehiclePhysics.impact_strength(Vector3(20.0, 0.0, 0.0), Vector3.ZERO, dt)
	assert_that(sharp).is_equal_approx(1200.0, 0.001)
	assert_that(VehiclePhysics.is_impact_strength(sharp)).is_true()
	var gentle := VehiclePhysics.impact_strength(Vector3(1.0, 0.0, 0.0), Vector3.ZERO, dt)
	assert_that(gentle).is_equal_approx(60.0, 0.001)
	assert_that(VehiclePhysics.is_impact_strength(gentle)).is_false()
	assert_that(VehiclePhysics.impact_strength(Vector3(20.0, 0.0, 0.0), Vector3(20.0, 0.0, 0.0), dt)).is_equal(0.0)
	assert_that(VehiclePhysics.impact_strength(Vector3(20.0, 0.0, 0.0), Vector3.ZERO, 0.0)).is_equal(0.0)

func test_impact_signal_and_clean_lap_seam_fire_once_per_spike() -> void:
	var car := _new_car()
	var strengths: Array = []
	car.impact.connect(func(strength: float) -> void: strengths.append(strength))
	var impacts_before := GameState.session_stats.get_lap_impacts()
	var dt := 1.0 / 60.0
	car._prev_linear_velocity = Vector3(20.0, 0.0, 0.0)
	car.linear_velocity = Vector3.ZERO
	car._detect_impact(dt)
	assert_that(strengths.size()).is_equal(1)
	assert_that(float(strengths[0])).is_equal_approx(1200.0, 0.001)
	assert_that(GameState.session_stats.get_lap_impacts()).is_equal(impacts_before + 1)
	# A sustained pin keeps the delta above threshold but emits exactly once.
	car._detect_impact(dt)
	assert_that(strengths.size()).is_equal(1)
	assert_that(GameState.session_stats.get_lap_impacts()).is_equal(impacts_before + 1)
	# Recovery below the threshold re-arms the edge.
	car._prev_linear_velocity = Vector3.ZERO
	car.linear_velocity = Vector3(1.0, 0.0, 0.0)
	car._detect_impact(dt)
	assert_that(strengths.size()).is_equal(1)
	# A fresh sharp spike emits again and reaches the clean-lap counter.
	car._prev_linear_velocity = Vector3(20.0, 0.0, 0.0)
	car.linear_velocity = Vector3.ZERO
	car._detect_impact(dt)
	assert_that(strengths.size()).is_equal(2)
	assert_that(GameState.session_stats.get_lap_impacts()).is_equal(impacts_before + 2)