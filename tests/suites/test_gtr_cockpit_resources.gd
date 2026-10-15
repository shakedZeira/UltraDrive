# tests/suites/test_gtr_cockpit_resources.gd
extends GdUnitTestSuite

const RigScene: PackedScene = preload("res://scenes/vehicle/cockpit_rig.tscn")
const PlayerCarScene: PackedScene = preload("res://scenes/vehicle/player_car.tscn")

var _managed: Array = []

func before_test() -> void:
	_managed.clear()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

func after_test() -> void:
	for node in _managed:
		if is_instance_valid(node):
			node.free()
	_managed.clear()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

func _new_root() -> Node:
	var root := Node.new()
	root.name = "TestRoot"
	_managed.append(root)
	add_child(root)
	return root

func _new_player_car(root: Node, cfg: CarConfig = null) -> Node3D:
	var car := PlayerCarScene.instantiate() as Node3D
	if cfg != null:
		car.set("config", cfg)
	_managed.append(car)
	root.add_child(car)
	return car

## P0: a default InteriorResource reproduces the F2a trim: dark albedo, mild
## 0.15 emission, HUD dash kept (suppress false) and an empty gauge layout.
func test_default_interior_resource_equals_f2a_constants() -> void:
	var res := InteriorResource.new()
	assert_that(res.interior_scene).is_null()
	assert_that(res.trim_color).is_equal(Color(0.1, 0.1, 0.13, 1))
	assert_float(res.emission_energy).is_equal_approx(0.15, 0.0001)
	assert_that(res.suppress_hud_dash).is_false()
	assert_that(res.gauge_layout.is_empty()).is_true()

## P0: CarConfig carries the new exports with null / 0.0 defaults and round-
## trips a set InteriorResource plus the RHD lateral seat offset.
func test_car_config_round_trips_interior_and_lateral() -> void:
	var cfg := CarConfig.new()
	assert_that(cfg.interior).is_null()
	assert_float(cfg.cockpit_seat_lateral).is_equal_approx(0.0, 0.0001)

	var res := InteriorResource.new()
	res.suppress_hud_dash = true
	cfg.interior = res
	cfg.cockpit_seat_lateral = -0.36
	assert_that(cfg.interior).is_same(res)
	assert_float(cfg.cockpit_seat_lateral).is_equal_approx(-0.36, 0.0001)

## P0: interior == null keeps the literal cockpit_rig.tscn tree — the F2a
## anchors, wheel transform and no Interior child.
func test_null_interior_keeps_literal_default_rig_tree() -> void:
	var root := _new_root()
	var rig := RigScene.instantiate() as CockpitRig
	_managed.append(rig)
	root.add_child(rig)

	assert_that(rig.has_node("Dashboard")).is_true()
	assert_that(rig.has_node("PillarLeft")).is_true()
	assert_that(rig.has_node("PillarRight")).is_true()
	assert_that(rig.has_node("HeaderBar")).is_true()
	assert_that(rig.has_node("SteeringWheel")).is_true()
	assert_that(rig.get_node_or_null("Interior")).is_null()
	var wheel := rig.get_node_or_null("SteeringWheel") as Node3D
	assert_that(wheel).is_not_null()
	assert_float(wheel.position.z).is_equal_approx(-0.4, 0.0001)
	assert_float(wheel.position.y).is_equal_approx(-0.20, 0.0001)

## P0: a player car whose config has no interior uses the default rig tree —
## same anchors, captured wheel is the authored one.
func test_player_car_without_interior_uses_default_anchors() -> void:
	var root := _new_root()
	var car := _new_player_car(root)
	var rig := car.get_node_or_null("CockpitRig") as CockpitRig
	assert_that(rig).is_not_null()
	assert_that(rig.has_node("Dashboard")).is_true()
	assert_that(rig.has_node("SteeringWheel")).is_true()
	assert_that(rig.get_node_or_null("Interior")).is_null()
	assert_that(rig.get_steering_wheel()).is_same(rig.get_node("SteeringWheel"))

## P0: an InteriorResource whose interior_scene cannot instantiate degrades to
## the default rig with no crash and no Interior child.
func test_bogus_interior_scene_degrades_to_default() -> void:
	var cfg := CarConfig.new()
	var res := InteriorResource.new()
	res.interior_scene = PackedScene.new()
	cfg.interior = res

	var root := _new_root()
	var car := _new_player_car(root, cfg)
	var rig := car.get_node_or_null("CockpitRig") as CockpitRig
	assert_that(rig).is_not_null()
	assert_that(rig.get_node_or_null("Interior")).is_null()
	assert_that(rig.has_node("Dashboard")).is_true()
	assert_that(rig.has_node("SteeringWheel")).is_true()
	assert_that(rig.get_steering_wheel()).is_not_null()
