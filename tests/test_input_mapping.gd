extends GdUnitTestSuite

func test_throttle_returns_zero_when_no_input() -> void:
    assert_that(InputManager.get_throttle()).is_equal(0.0)

func test_brake_returns_zero_when_no_input() -> void:
    assert_that(InputManager.get_brake()).is_equal(0.0)

func test_steer_returns_zero_when_no_input() -> void:
    assert_that(InputManager.get_steer()).is_equal(0.0)

func test_handbrake_returns_false_when_no_input() -> void:
    assert_that(InputManager.is_handbrake()).is_equal(false)
