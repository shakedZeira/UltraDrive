# tests/suites/test_ai_corner_grip.gd
extends GdUnitTestSuite

## The AI's corner-speed target folds in surface grip (AIController._corner_grip):
## on a loose section (Barcelona RX dirt, GRAVEL 0.85) a rival targets
## sqrt(0.85) of its asphalt corner speed, it reads the surface at the corner
## AHEAD (so it brakes before reaching the dirt), and on asphalt the target is
## exactly the old one.

var _managed: Array[Node] = []

func after_test() -> void:
	for node in _managed:
		if is_instance_valid(node):
			node.free()
	_managed.clear()

func _ring(n: int, radius: float) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(Vector3(cos(a) * radius, 0.0, sin(a) * radius))
	return pts

func _driver(provider: Callable) -> AIController:
	var car := VehiclePhysics.new()
	_managed.append(car)
	car.surface_provider = provider
	var driver := AIController.new()
	_managed.append(driver)
	driver.car = car
	driver.set_waypoints(_ring(120, 60.0))
	return driver

func _grip_provider(lateral: float, from_x: float = -INF) -> Callable:
	return func(pos: Vector3) -> Dictionary:
		var lat := lateral if pos.x >= from_x else 1.0
		return {"surface_key": "TEST", "lateral": lat, "longitudinal": lat}

func test_asphalt_keeps_the_old_corner_target() -> void:
	var driver := _driver(_grip_provider(1.0))
	var k := RacingLine.lookahead_curvature(driver.waypoints, 0, 30.0)
	var expected := sqrt(AIController.CORNER_LAT_ACCEL / k)
	assert_float(driver._corner_speed_target(0, 20.0)).is_equal_approx(expected, 0.001)

func test_loose_corner_ahead_lowers_the_target_by_sqrt_grip() -> void:
	var asphalt := _driver(_grip_provider(1.0))
	var dirt := _driver(_grip_provider(0.85))
	var ratio := dirt._corner_speed_target(0, 20.0) / asphalt._corner_speed_target(0, 20.0)
	assert_float(ratio).is_equal_approx(sqrt(0.85), 0.001)

func test_grip_is_read_at_the_corner_ahead_not_only_under_the_car() -> void:
	# The car (unplaced, its own key = ASPHALT) looks 30 m ahead of index 0
	# (x = +60) to a point with x < 59, where this provider reports dirt.
	var driver := _driver(func(pos: Vector3) -> Dictionary:
		var lat := 0.85 if pos.x < 59.0 else 1.0
		return {"surface_key": "TEST", "lateral": lat, "longitudinal": lat})
	assert_float(driver._corner_grip(0, 30.0)).is_equal_approx(0.85, 0.001)
	# A floor keeps a near-zero reading from asking for a crawl.
	var ice := _driver(_grip_provider(0.05))
	assert_float(ice._corner_grip(0, 30.0)).is_equal_approx(AIController.MIN_CORNER_GRIP, 0.001)
