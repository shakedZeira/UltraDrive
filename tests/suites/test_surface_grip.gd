# tests/suites/test_surface_grip.gd
extends GdUnitTestSuite

## P3 gate: the surface registry drives BOTH tire axes, detection is
## deterministic given (region biome band, position, tier), weather and surface
## compound correctly, and the lookup edges never divide by zero. Pure math and
## headless node construction only (no frames, no scene tree).

## Snow-weather grip factor mirrors WeatherManager.ROAD_GRIP[SNOW]; kept as a
## literal so the suite stays deterministic without touching the autoload.
const SNOW_WEATHER_GRIP := 0.45

var _managed_nodes: Array = []

func before_test() -> void:
	_managed_nodes.clear()

func after_test() -> void:
	for node in _managed_nodes:
		if is_instance_valid(node):
			node.free()
	_managed_nodes.clear()

func _new_config() -> CarConfig:
	return CarConfig.new()

func _new_car() -> VehiclePhysics:
	var car := VehiclePhysics.new()
	_managed_nodes.append(car)
	return car

func test_grip_table_defines_all_six_surfaces() -> void:
	assert_that(SurfaceRegistry.SURFACE_GRIP.size()).is_equal(SurfaceRegistry.SURFACE_COUNT)
	for surface_key: Variant in SurfaceRegistry.SURFACE_GRIP.keys():
		var grip: Dictionary = SurfaceRegistry.SURFACE_GRIP[surface_key] as Dictionary
		assert_that(grip.has("lateral")).is_true()
		assert_that(grip.has("longitudinal")).is_true()
		assert_that(float(grip["lateral"])).is_between(0.0, 1.0)
		assert_that(float(grip["longitudinal"])).is_between(0.0, 1.0)
	assert_that(SurfaceRegistry.get_lateral(SurfaceRegistry.ASPHALT)).is_equal(1.0)
	assert_that(SurfaceRegistry.get_longitudinal(SurfaceRegistry.ASPHALT)).is_equal(1.0)

func test_lateral_grip_strictly_decreases_from_asphalt_to_snow() -> void:
	var order: Array[String] = [
		SurfaceRegistry.ASPHALT, SurfaceRegistry.GRAVEL, SurfaceRegistry.DIRT,
		SurfaceRegistry.GRASS, SurfaceRegistry.MUD, SurfaceRegistry.SNOW,
	]
	var prev := SurfaceRegistry.SURFACE_COUNT + 1.0
	for key in order:
		var lat := SurfaceRegistry.get_lateral(key)
		assert_that(lat).is_less(prev)
		prev = lat

func test_default_surface_factor_preserves_existing_calls() -> void:
	var cfg := _new_config()
	var lateral_default := TireModel.calculate_lateral_force(0.1, 5000.0, cfg, 1.0, 1.0)
	var lateral_plain := TireModel.calculate_lateral_force(0.1, 5000.0, cfg, 1.0)
	assert_that(lateral_default).is_equal_approx(lateral_plain, 0.001)
	var long_default := TireModel.calculate_longitudinal_force(0.3, 5000.0, cfg, 1.0, 1.0)
	var long_plain := TireModel.calculate_longitudinal_force(0.3, 5000.0, cfg, 1.0)
	assert_that(long_default).is_equal_approx(long_plain, 0.001)
	assert_that(lateral_plain).is_greater(0.0)
	assert_that(long_plain).is_greater(0.0)

func test_surface_factor_scales_both_axes_for_every_surface() -> void:
	var cfg := _new_config()
	var base_lateral := TireModel.calculate_lateral_force(0.1, 5000.0, cfg, 1.0, 1.0)
	var base_longitudinal := TireModel.calculate_longitudinal_force(0.3, 5000.0, cfg, 1.0, 1.0)
	for surface_key: Variant in SurfaceRegistry.SURFACE_GRIP.keys():
		var surface: String = String(surface_key)
		var grip: Dictionary = SurfaceRegistry.SURFACE_GRIP[surface] as Dictionary
		var lateral := TireModel.calculate_lateral_force(0.1, 5000.0, cfg, 1.0, float(grip["lateral"]))
		var longitudinal := TireModel.calculate_longitudinal_force(0.3, 5000.0, cfg, 1.0, float(grip["longitudinal"]))
		assert_that(lateral).is_equal_approx(base_lateral * float(grip["lateral"]), 0.001)
		assert_that(longitudinal).is_equal_approx(base_longitudinal * float(grip["longitudinal"]), 0.001)

func test_classify_near_road_uses_tier_surface() -> void:
	var tier_surfaces: Dictionary = {
		RoadDef.Tier.HIGHWAY: SurfaceRegistry.ASPHALT,
		RoadDef.Tier.ARTERIAL: SurfaceRegistry.ASPHALT,
		RoadDef.Tier.TOUGE: SurfaceRegistry.ASPHALT,
		RoadDef.Tier.COASTAL: SurfaceRegistry.ASPHALT,
		RoadDef.Tier.DIRT: SurfaceRegistry.GRAVEL,
	}
	for tier: Variant in tier_surfaces.keys():
		var near: Dictionary = SurfaceRegistry.classify(SurfaceRegistry.BAND_ALPINE, 1.0, int(tier))
		assert_that(near["surface_key"]).is_equal(tier_surfaces[tier])
	# Unknown tier falls back to asphalt.
	var unknown_tier: Dictionary = SurfaceRegistry.classify(SurfaceRegistry.BAND_ALPINE, 1.0, 999)
	assert_that(unknown_tier["surface_key"]).is_equal(SurfaceRegistry.ASPHALT)

func test_classify_maps_biome_bands_to_offroad_surfaces() -> void:
	var band_surfaces: Dictionary = {
		SurfaceRegistry.BAND_SEA: SurfaceRegistry.GRASS,
		SurfaceRegistry.BAND_PLAINS: SurfaceRegistry.GRASS,
		SurfaceRegistry.BAND_ROLLING: SurfaceRegistry.GRASS,
		SurfaceRegistry.BAND_LOWLAND: SurfaceRegistry.MUD,
		SurfaceRegistry.BAND_HIGHLAND: SurfaceRegistry.GRAVEL,
		SurfaceRegistry.BAND_ALPINE: SurfaceRegistry.SNOW,
	}
	for band: Variant in band_surfaces.keys():
		var offroad: Dictionary = SurfaceRegistry.classify(int(band), 80.0, RoadDef.Tier.DIRT)
		assert_that(offroad["surface_key"]).is_equal(band_surfaces[band])
	# Road closeness beats even the alpine band.
	var near: Dictionary = SurfaceRegistry.classify(SurfaceRegistry.BAND_ALPINE, 1.0, RoadDef.Tier.DIRT)
	assert_that(near["surface_key"]).is_equal(SurfaceRegistry.GRAVEL)

func test_classify_road_topping_boundary_favours_road() -> void:
	assert_that(SurfaceRegistry.classify(SurfaceRegistry.BAND_ALPINE, SurfaceRegistry.ROAD_TOPPING, RoadDef.Tier.DIRT)["surface_key"]).is_equal(SurfaceRegistry.GRAVEL)
	assert_that(SurfaceRegistry.classify(SurfaceRegistry.BAND_ALPINE, SurfaceRegistry.ROAD_TOPPING + 0.01, RoadDef.Tier.DIRT)["surface_key"]).is_equal(SurfaceRegistry.SNOW)

func test_classify_is_deterministic() -> void:
	var a := SurfaceRegistry.classify(SurfaceRegistry.BAND_LOWLAND, 3.5, RoadDef.Tier.DIRT)
	var b := SurfaceRegistry.classify(SurfaceRegistry.BAND_LOWLAND, 3.5, RoadDef.Tier.DIRT)
	assert_that(a["surface_key"]).is_equal(b["surface_key"])
	assert_that(float(a["lateral"])).is_equal(float(b["lateral"]))
	assert_that(float(a["longitudinal"])).is_equal(float(b["longitudinal"]))

func test_weather_surface_compound_is_ordered_by_surface() -> void:
	var snow_surface: Dictionary = SurfaceRegistry.SURFACE_GRIP[SurfaceRegistry.SNOW] as Dictionary
	var dirt: Dictionary = SurfaceRegistry.SURFACE_GRIP[SurfaceRegistry.DIRT] as Dictionary
	var asphalt: Dictionary = SurfaceRegistry.SURFACE_GRIP[SurfaceRegistry.ASPHALT] as Dictionary
	var snow_total := float(snow_surface["lateral"]) * SNOW_WEATHER_GRIP
	var dirt_total := float(dirt["lateral"]) * SNOW_WEATHER_GRIP
	var asphalt_total := float(asphalt["lateral"]) * SNOW_WEATHER_GRIP
	assert_that(snow_total).is_greater(0.0)
	assert_that(snow_total).is_less(dirt_total)
	assert_that(dirt_total).is_less(asphalt_total)

func test_tire_force_compounds_weather_and_surface() -> void:
	var cfg := _new_config()
	var base := TireModel.calculate_lateral_force(0.15, 5000.0, cfg, 1.0, 1.0)
	# Snow weather on asphalt (road-close) vs snow weather on snow surface.
	var asphalt_road := TireModel.calculate_lateral_force(0.15, 5000.0, cfg, SNOW_WEATHER_GRIP, 1.0)
	var snow_surface := TireModel.calculate_lateral_force(
		0.15, 5000.0, cfg, SNOW_WEATHER_GRIP, SurfaceRegistry.get_lateral(SurfaceRegistry.SNOW)
	)
	assert_that(asphalt_road).is_equal_approx(base * SNOW_WEATHER_GRIP, 0.01)
	assert_that(snow_surface).is_equal_approx(base * SNOW_WEATHER_GRIP * SurfaceRegistry.get_lateral(SurfaceRegistry.SNOW), 0.01)
	assert_that(snow_surface).is_less(asphalt_road)

func test_lookup_edges_never_divide_by_zero() -> void:
	for edge_dist: float in [0.0, SurfaceRegistry.ROAD_TOPPING, SurfaceRegistry.ROAD_TOPPING + 0.01, 1.0e9]:
		var result: Dictionary = SurfaceRegistry.classify(SurfaceRegistry.BAND_ALPINE, edge_dist, RoadDef.Tier.DIRT)
		assert_that(result["surface_key"]).is_not_empty()
		assert_that(float(result["lateral"])).is_greater(0.0)
		assert_that(float(result["lateral"])).is_less_equal(1.0)
		assert_that(float(result["longitudinal"])).is_greater(0.0)
	for surface_key: Variant in SurfaceRegistry.SURFACE_GRIP.keys():
		assert_that(SurfaceRegistry.get_lateral(String(surface_key))).is_between(0.0, 1.0)
		assert_that(SurfaceRegistry.get_longitudinal(String(surface_key))).is_between(0.0, 1.0)
	# Unknown surface key falls back to asphalt instead of erroring.
	assert_that(SurfaceRegistry.get_lateral("ICETOP")).is_equal(1.0)
	assert_that(SurfaceRegistry.get_longitudinal("ICETOP")).is_equal(1.0)

func test_classifier_falls_back_to_asphalt_without_network() -> void:
	var classifier := SurfaceRegistry.build_classifier(Callable(), Callable())
	for _i in range(2):
		var result: Dictionary = classifier.call(Vector3(999.0, 0.0, 999.0))
		assert_that(result["surface_key"]).is_equal(SurfaceRegistry.ASPHALT)
		assert_that(float(result["lateral"])).is_equal(1.0)
		assert_that(float(result["longitudinal"])).is_equal(1.0)

func test_classifier_uses_injected_providers() -> void:
	var dirt_provider := func(_pos: Vector3) -> Dictionary:
		return {"tier": RoadDef.Tier.DIRT, "distance": 2.0}
	var near_classifier := SurfaceRegistry.build_classifier(dirt_provider, Callable())
	var near: Dictionary = near_classifier.call(Vector3.ZERO)
	assert_that(near["surface_key"]).is_equal(SurfaceRegistry.GRAVEL)

	var far_provider := func(_pos: Vector3) -> Dictionary:
		return {"tier": RoadDef.Tier.DIRT, "distance": 80.0}
	var far_classifier := SurfaceRegistry.build_classifier(far_provider, Callable())
	# No biome provider -> BAND_PLAINS -> GRASS off-road.
	var far: Dictionary = far_classifier.call(Vector3.ZERO)
	assert_that(far["surface_key"]).is_equal(SurfaceRegistry.GRASS)

	var alpine_provider := func(_pos: Vector3) -> int:
		return SurfaceRegistry.BAND_ALPINE
	var snow_classifier := SurfaceRegistry.build_classifier(far_provider, alpine_provider)
	var snow: Dictionary = snow_classifier.call(Vector3.ZERO)
	assert_that(snow["surface_key"]).is_equal(SurfaceRegistry.SNOW)

func test_vehicle_surface_provider_is_settable() -> void:
	var car := _new_car()
	var stub := func(_pos: Vector3) -> Dictionary:
		return SurfaceRegistry.classify(SurfaceRegistry.BAND_ALPINE, 9.0, RoadDef.Tier.ARTERIAL)
	car.set_surface_provider(stub)
	var result := car.resolve_surface_factors()
	assert_that(result["surface_key"]).is_equal(SurfaceRegistry.SNOW)
	assert_that(car.get_surface_key()).is_equal(SurfaceRegistry.SNOW)

func test_vehicle_surface_provider_missing_falls_back_to_asphalt() -> void:
	var car := _new_car()
	car.set_surface_provider(Callable())
	var result := car.resolve_surface_factors()
	assert_that(result["surface_key"]).is_equal(SurfaceRegistry.ASPHALT)
	assert_that(float(result["lateral"])).is_equal(1.0)
	assert_that(float(result["longitudinal"])).is_equal(1.0)
	assert_that(car.get_surface_key()).is_equal(SurfaceRegistry.ASPHALT)

func test_drive_info_includes_surface_key() -> void:
	var car := _new_car()
	var info := car.get_drive_info()
	assert_that(info.has("surface")).is_true()
	assert_that(info["surface"]).is_equal(SurfaceRegistry.ASPHALT)