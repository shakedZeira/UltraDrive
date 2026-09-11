extends GdUnitTestSuite

func test_race_manager_starts_clean() -> void:
    var cars: Array[VehiclePhysics] = []
    RaceManager.start_race(cars, 3)
    assert_that(RaceManager.is_race_active).is_true()
    assert_that(RaceManager.total_laps).is_equal(3)

func test_rubber_banding_values_valid() -> void:
    assert_that(AIRubberBanding.calculate_speed_multiplier(5.0)).is_equal(0.95)
    assert_that(AIRubberBanding.calculate_speed_multiplier(-5.0)).is_equal(1.05)
    assert_that(AIRubberBanding.calculate_speed_multiplier(1.0)).is_equal(1.0)
