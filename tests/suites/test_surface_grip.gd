# tests/suites/test_surface_grip.gd
extends GdUnitTestSuite

## P3 gate: the surface registry drives BOTH tire axes, detection is
## deterministic given (region biome band, position, tier), weather and surface
## compound correctly, and the lookup edges never divide by zero. Pure math and
## headless node construction only (no frames, no scene tree).
##
## Two contracts are locked here: EVERY off-road surface is GRASS in every
## biome band, and the road distance is the XZ distance to the road CENTERLINE
## (point-to-segment, not the nearest sparse polyline vertex) as reported by a
## live RoadNetwork through the real default_road_tier_provider.

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

func test_classify_maps_every_biome_band_off_road_to_grass() -> void:
	# ALL non-road ground is grass, in every band (alpine/lowland/highland no
	# longer swap in snow/mud/gravel -- the alpine snow VISUALS are
	# RegionalClimate/WeatherManager's business, this table is feel only).
	var bands: Array[int] = [
		SurfaceRegistry.BAND_SEA,
		SurfaceRegistry.BAND_PLAINS,
		SurfaceRegistry.BAND_ROLLING,
		SurfaceRegistry.BAND_LOWLAND,
		SurfaceRegistry.BAND_HIGHLAND,
		SurfaceRegistry.BAND_ALPINE,
		-1,
		99,
	]
	for band: int in bands:
		var offroad: Dictionary = SurfaceRegistry.classify(band, 80.0, RoadDef.Tier.DIRT)
		assert_that(offroad["surface_key"]).is_equal(SurfaceRegistry.GRASS)
		assert_float(float(offroad["lateral"])).is_equal(
			SurfaceRegistry.get_lateral(SurfaceRegistry.GRASS)
		)
		assert_float(float(offroad["longitudinal"])).is_equal(
			SurfaceRegistry.get_longitudinal(SurfaceRegistry.GRASS)
		)
	# Road closeness still beats the band (DIRT tier -> gravel).
	var near: Dictionary = SurfaceRegistry.classify(SurfaceRegistry.BAND_ALPINE, 1.0, RoadDef.Tier.DIRT)
	assert_that(near["surface_key"]).is_equal(SurfaceRegistry.GRAVEL)

func test_classify_road_topping_boundary_favours_road() -> void:
	assert_that(SurfaceRegistry.classify(SurfaceRegistry.BAND_ALPINE, SurfaceRegistry.ROAD_TOPPING, RoadDef.Tier.DIRT)["surface_key"]).is_equal(SurfaceRegistry.GRAVEL)
	assert_that(SurfaceRegistry.classify(SurfaceRegistry.BAND_ALPINE, SurfaceRegistry.ROAD_TOPPING + 0.01, RoadDef.Tier.DIRT)["surface_key"]).is_equal(SurfaceRegistry.GRASS)

func test_classify_uses_highway_width_for_outer_lane() -> void:
	var result: Dictionary = SurfaceRegistry.classify(
		SurfaceRegistry.BAND_ALPINE, 9.0, RoadDef.Tier.HIGHWAY, 24.0
	)
	assert_that(result["surface_key"]).is_equal(SurfaceRegistry.ASPHALT)

func test_classify_width_aware_road_topping_boundary() -> void:
	var highway_width: float = 24.0
	var topping: float = highway_width * 0.5 + SurfaceRegistry.ROAD_EDGE_MARGIN
	var on_road: Dictionary = SurfaceRegistry.classify(
		SurfaceRegistry.BAND_ALPINE, topping, RoadDef.Tier.HIGHWAY, highway_width
	)
	var off_road: Dictionary = SurfaceRegistry.classify(
		SurfaceRegistry.BAND_ALPINE, topping + 0.01, RoadDef.Tier.HIGHWAY, highway_width
	)
	assert_that(on_road["surface_key"]).is_equal(SurfaceRegistry.ASPHALT)
	assert_that(off_road["surface_key"]).is_equal(SurfaceRegistry.GRASS)

func test_classify_three_argument_calls_keep_fixed_topping() -> void:
	var off_road: Dictionary = SurfaceRegistry.classify(
		SurfaceRegistry.BAND_ALPINE,
		SurfaceRegistry.ROAD_TOPPING + 0.01,
		RoadDef.Tier.DIRT
	)
	var near_highway: Dictionary = SurfaceRegistry.classify(
		SurfaceRegistry.BAND_ALPINE, 1.0, RoadDef.Tier.HIGHWAY
	)
	assert_that(off_road["surface_key"]).is_equal(SurfaceRegistry.GRASS)
	assert_that(near_highway["surface_key"]).is_equal(SurfaceRegistry.ASPHALT)

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

	# The biome provider can no longer change the off-road surface.
	var alpine_provider := func(_pos: Vector3) -> int:
		return SurfaceRegistry.BAND_ALPINE
	var alpine_classifier := SurfaceRegistry.build_classifier(far_provider, alpine_provider)
	var alpine: Dictionary = alpine_classifier.call(Vector3.ZERO)
	assert_that(alpine["surface_key"]).is_equal(SurfaceRegistry.GRASS)

func test_classifier_uses_reported_width_and_preserves_missing_width_fallback() -> void:
	var width_provider := func(_pos: Vector3) -> Dictionary:
		return {"tier": RoadDef.Tier.HIGHWAY, "distance": 9.0, "width": 24.0}
	var width_classifier := SurfaceRegistry.build_classifier(width_provider, Callable())
	var on_road: Dictionary = width_classifier.call(Vector3.ZERO)
	assert_that(on_road["surface_key"]).is_equal(SurfaceRegistry.ASPHALT)

	var legacy_provider := func(_pos: Vector3) -> Dictionary:
		return {"tier": RoadDef.Tier.HIGHWAY, "distance": 9.0}
	var legacy_classifier := SurfaceRegistry.build_classifier(legacy_provider, Callable())
	var off_road: Dictionary = legacy_classifier.call(Vector3.ZERO)
	assert_that(off_road["surface_key"]).is_equal(SurfaceRegistry.GRASS)

func test_vehicle_surface_provider_is_settable() -> void:
	var car := _new_car()
	var stub := func(_pos: Vector3) -> Dictionary:
		return SurfaceRegistry.classify(SurfaceRegistry.BAND_ALPINE, 9.0, RoadDef.Tier.ARTERIAL)
	car.set_surface_provider(stub)
	var result := car.resolve_surface_factors()
	assert_that(result["surface_key"]).is_equal(SurfaceRegistry.GRASS)
	assert_that(car.get_surface_key()).is_equal(SurfaceRegistry.GRASS)

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

# --- Road-distance wiring ---------------------------------------------------
# Regression gate for "the highway still feels like dirt": the road distance fed
# to classify() must be the XZ distance to the road CENTERLINE (point-to-
# segment), not the distance to the nearest sparse polyline vertex. The 25 km
# perimeter ring has ~130 m between its 192 vertices, so the old lookup reported
# 60+ m for a car driving down a 24 m carriageway and classified it grass (0.65
# grip + dust). These go through the real default_road_tier_provider + a live
# RoadNetwork, i.e. the exact wiring VehiclePhysics uses.

const HIGHWAY_WIDTH := 24.0
const SPAN := 240.0

func _new_road_network() -> RoadNetwork:
	var net := RoadNetwork.new()
	add_child(net)
	_managed_nodes.append(net)
	return net

## Two vertices SPAN metres apart on one flat carriageway, so the mid-span
## queries below are >100 m from ANY vertex (the shape that broke before).
func _span_road_points() -> Array[Vector3]:
	return [Vector3(0.0, 20.0, 0.0), Vector3(SPAN, 20.0, 0.0)]

func test_midspan_highway_lane_classifies_as_asphalt() -> void:
	var net := _new_road_network()
	net.add_road_def(RoadDef.make(
		RoadDef.Tier.HIGHWAY, _span_road_points(), "test-highway", false, HIGHWAY_WIDTH
	))
	var provider := SurfaceRegistry.default_road_tier_provider(self)
	var mid := Vector3(SPAN * 0.5, 20.0, 0.0)
	var report: Dictionary = provider.call(mid + Vector3(0.0, 0.0, 9.0))
	assert_that(int(report["tier"])).is_equal(RoadDef.Tier.HIGHWAY)
	assert_float(float(report["width"])).is_equal_approx(HIGHWAY_WIDTH, 0.001)
	# The reported distance is the true lane offset, NOT the ~120 m to the
	# nearest vertex the old vertex-walk returned.
	assert_float(float(report["distance"])).is_equal_approx(9.0, 0.001)
	var classifier := SurfaceRegistry.build_classifier(provider, Callable())
	var on_road: Dictionary = classifier.call(mid + Vector3(0.0, 0.0, 9.0))
	assert_that(on_road["surface_key"]).is_equal(SurfaceRegistry.ASPHALT)
	assert_that(float(on_road["lateral"])).is_equal(1.0)
	assert_that(float(on_road["longitudinal"])).is_equal(1.0)

func test_midspan_point_past_the_canopy_is_off_road_grass() -> void:
	var net := _new_road_network()
	net.add_road_def(RoadDef.make(
		RoadDef.Tier.HIGHWAY, _span_road_points(), "test-highway", false, HIGHWAY_WIDTH
	))
	var provider := SurfaceRegistry.default_road_tier_provider(self)
	var classifier := SurfaceRegistry.build_classifier(provider, Callable())
	var mid := Vector3(SPAN * 0.5, 20.0, 0.0)
	var canopy: float = HIGHWAY_WIDTH * 0.5 + SurfaceRegistry.ROAD_EDGE_MARGIN
	var at_canopy: Dictionary = classifier.call(mid + Vector3(0.0, 0.0, canopy))
	assert_that(at_canopy["surface_key"]).is_equal(SurfaceRegistry.ASPHALT)
	# 20 m off the same mid-span segment is past the canopy: grass again.
	var shoulder := Vector3(SPAN * 0.5, 20.0, 20.0)
	assert_float(float(provider.call(shoulder)["distance"])).is_equal_approx(20.0, 0.001)
	var off_road: Dictionary = classifier.call(shoulder)
	assert_that(off_road["surface_key"]).is_equal(SurfaceRegistry.GRASS)
	assert_float(float(off_road["lateral"])).is_equal(SurfaceRegistry.get_lateral(SurfaceRegistry.GRASS))
	assert_float(float(off_road["lateral"])).is_less(1.0)

## The real seeded perimeter highway, sampled between its own vertices: the
## carriageway (and both shoulders up to the 14.5 m canopy) is asphalt all the
## way round, and 20 m out is grass.
func test_real_perimeter_highway_is_asphalt_between_its_vertices() -> void:
	var defs := CorridorPlanner.plan(CorridorPlanner.MASTER_SEED)
	var ring: RoadDef = defs[3]
	assert_that(ring.id).is_equal("highway-ring")
	assert_that(ring.tier).is_equal(RoadDef.Tier.HIGHWAY)
	assert_float(ring.width).is_equal_approx(HIGHWAY_WIDTH, 0.001)
	var points: Array[Vector3] = ring.points
	assert_that(points.size()).is_greater_equal(64)
	var net := _new_road_network()
	net.add_road_def(ring)
	var provider := SurfaceRegistry.default_road_tier_provider(self)
	var classifier := SurfaceRegistry.build_classifier(provider, Callable())
	for idx: int in [0, 47, 96, 150]:
		var a: Vector3 = points[idx]
		var b: Vector3 = points[(idx + 1) % points.size()]
		var dir := (Vector2(b.x, b.z) - Vector2(a.x, a.z)).normalized()
		# The reported bug: vertices on this ring are >100 m apart.
		assert_float(Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))).is_greater(100.0)
		var normal := Vector2(-dir.y, dir.x)
		var mid := a.lerp(b, 0.5)
		for lateral: float in [0.0, 6.0, 9.0, 12.0]:
			var p := Vector3(mid.x + normal.x * lateral, mid.y, mid.z + normal.y * lateral)
			assert_float(float(provider.call(p)["distance"])).is_equal_approx(lateral, 0.01)
			assert_that(classifier.call(p)["surface_key"]).is_equal(SurfaceRegistry.ASPHALT)
		var off := Vector3(mid.x + normal.x * 20.0, mid.y, mid.z + normal.y * 20.0)
		assert_float(float(provider.call(off)["distance"])).is_equal_approx(20.0, 0.01)
		assert_that(classifier.call(off)["surface_key"]).is_equal(SurfaceRegistry.GRASS)