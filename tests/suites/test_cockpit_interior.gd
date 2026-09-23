# tests/suites/test_cockpit_interior.gd
extends GdUnitTestSuite

## F2a cockpit interior gate: player_car.tscn now carries a CockpitRig as a
## SIBLING of CarBody (a direct child of the VehiclePhysics root), so
## PlayerCarController._apply_visual()'s clear-and-rebuild never wipes it
## across car swaps. The rig hides in chase/hood/orbit and shows only while
## the CockpitCamera owns the viewport, stays hidden when no cockpit camera
## exists (test_vehicle_physics.tscn clone), instantiates clean headless with
## its primitive geometry, and the windshield gate
## world_driver._is_forward_view() is UNCHANGED by the rig (chase/hood/cockpit
## true, orbit false). Frames are driven directly through sync_visibility() /
## cycle_mode_for_test — no physics loop, no real Input events.

const PlayerCarScene: PackedScene = preload("res://scenes/vehicle/player_car.tscn")
const CockpitRigScene: PackedScene = preload("res://scenes/vehicle/cockpit_rig.tscn")
const ChaseCameraScript: GDScript = preload("res://scripts/camera/chase_camera.gd")
const OrbitCameraScript: GDScript = preload("res://scripts/camera/orbit_camera.gd")
const HoodCameraScript: GDScript = preload("res://scripts/camera/hood_camera.gd")
const CockpitCameraScript: GDScript = preload("res://scripts/camera/cockpit_camera.gd")

const TEST_VEHICLE_SCENE := "res://scenes/test/test_vehicle_physics.tscn"

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

func _new_player_car(root: Node) -> Node3D:
	var car := PlayerCarScene.instantiate() as Node3D
	_managed.append(car)
	root.add_child(car)
	return car

## Gate 1: a player_car.tscn instance carries a CockpitRig as a sibling of
## CarBody (NOT a CarBody child), normally hidden.
func test_player_car_contains_cockpit_rig_sibling_of_carbody() -> void:
	var root := _new_root()
	var car := _new_player_car(root)

	var rig := car.get_node_or_null("CockpitRig")
	assert_that(rig).is_not_null()
	assert_that(rig is CockpitRig).is_true()
	var body := car.get_node_or_null("CarBody")
	assert_that(body).is_not_null()
	assert_that(rig.get_parent()).is_same(car)
	assert_that(body.get_node_or_null("CockpitRig")).is_null()
	assert_that(rig.get("visible")).is_false()

## Placement proof: the rig survives _apply_visual() re-runs (car swaps),
## because it is a sibling of CarBody, not a body child that gets cleared.
func test_cockpit_rig_survives_apply_visual_car_swap_rebuild() -> void:
	var root := _new_root()
	var car := _new_player_car(root)
	var controller := car.get_node_or_null("PlayerCarController")
	assert_that(controller).is_not_null()

	controller.call("_apply_visual")
	await get_tree().process_frame  # flush the queue_freed GLB/probe from the rebuild

	var rig := car.get_node_or_null("CockpitRig")
	assert_that(rig).is_not_null()
	assert_that(rig.get_parent()).is_same(car)
	assert_that(rig.get("visible")).is_false()

## Gate 2: the rig shows only while the CockpitCamera owns the viewport and
## hides in every other camera mode. Driven first by the full C-cycle, then by
## the F1 set_view_active(true/false) switch directly.
func test_rig_visibility_toggles_with_camera_ownership() -> void:
	var root := _new_root()
	var car := _new_player_car(root)

	var chase := ChaseCameraScript.new() as Node3D
	chase.name = "ChaseCamera"
	_managed.append(chase)
	root.add_child(chase)
	var hood := HoodCameraScript.new() as Node3D
	hood.name = "HoodCamera"
	_managed.append(hood)
	root.add_child(hood)
	var cockpit := CockpitCameraScript.new() as Node3D
	cockpit.name = "CockpitCamera"
	_managed.append(cockpit)
	root.add_child(cockpit)
	var orbit := OrbitCameraScript.new() as Node3D
	orbit.name = "OrbitCamera"
	orbit.set("chase_camera_path", NodePath("../ChaseCamera"))
	orbit.set("hood_camera_path", NodePath("../HoodCamera"))
	orbit.set("cockpit_camera_path", NodePath("../CockpitCamera"))
	_managed.append(orbit)
	root.add_child(orbit)

	var rig := car.get_node_or_null("CockpitRig") as CockpitRig
	assert_that(rig).is_not_null()

	# Default: chase owns the view — interior hidden.
	assert_that(rig.call("sync_visibility")).is_false()

	orbit.call("cycle_mode_for_test")  # orbit
	assert_that(rig.call("sync_visibility")).is_false()

	orbit.call("cycle_mode_for_test")  # hood
	assert_that(rig.call("sync_visibility")).is_false()

	orbit.call("cycle_mode_for_test")  # cockpit — interior visible
	assert_that(rig.call("sync_visibility")).is_true()

	orbit.call("cycle_mode_for_test")  # chase again — hidden
	assert_that(rig.call("sync_visibility")).is_false()

	# Direct F1 camera ownership switch drives the gate too.
	cockpit.call("set_view_active", true)
	assert_that(rig.call("sync_visibility")).is_true()

	cockpit.call("set_view_active", false)
	assert_that(rig.call("sync_visibility")).is_false()

## Gate 2 / no-cam case: chase-only rig (test_vehicle_physics.tscn clone) has
## no cockpit camera, so the interior stays hidden no matter what.
func test_rig_hidden_when_no_cockpit_camera_exists() -> void:
	var root := _new_root()
	var car := _new_player_car(root)

	var chase := ChaseCameraScript.new() as Node3D
	chase.name = "ChaseCamera"
	_managed.append(chase)
	root.add_child(chase)

	var rig := car.get_node_or_null("CockpitRig") as CockpitRig
	assert_that(rig).is_not_null()
	assert_that(rig.call("sync_visibility")).is_false()
	assert_that(rig.get("visible")).is_false()

## Gate 2 via the real chase-only scene: player_car's rig stays hidden inside
## test_vehicle_physics.tscn across simulated frames (its _process polls the
## gate and finds no cockpit camera).
func test_vehicle_physics_scene_runs_with_rig_hidden() -> void:
	var runner := scene_runner(TEST_VEHICLE_SCENE)
	await runner.simulate_frames(5)
	var car := runner.scene().get_node("PlayerCar") as Node3D
	assert_that(car).is_not_null()
	if car == null:
		return
	var rig := car.get_node_or_null("CockpitRig") as CockpitRig
	assert_that(rig).is_not_null()
	assert_that(rig.get("visible")).is_false()

## Gate 3: the cockpit rig scene itself instantiates clean headless with all
## its primitive pieces (dash / L+R pillars / header / wheel).
func test_cockpit_rig_scene_instantiates_with_primitive_geometry() -> void:
	var root := _new_root()
	var rig := CockpitRigScene.instantiate() as CockpitRig
	_managed.append(rig)
	root.add_child(rig)

	assert_that(rig is CockpitRig).is_true()
	assert_that(rig.get("visible")).is_false()
	assert_that(rig.has_node("Dashboard")).is_true()
	assert_that(rig.has_node("PillarLeft")).is_true()
	assert_that(rig.has_node("PillarRight")).is_true()
	assert_that(rig.has_node("HeaderBar")).is_true()
	assert_that(rig.has_node("SteeringWheel")).is_true()
	var dash := rig.get_node_or_null("Dashboard") as MeshInstance3D
	assert_that(dash).is_not_null()
	assert_that(dash.mesh).is_not_null()

## Gate 4: world_driver._is_forward_view() is unchanged by the rig —
## chase / hood / cockpit are forward views (droplets show), orbit is not.
func test_windshield_forward_view_gate_unchanged_by_rig() -> void:
	var driver := WorldDriver.new()
	driver.name = "Driver"
	var chase := ChaseCameraScript.new() as Node3D
	chase.name = "ChaseCamera"
	driver.add_child(chase)
	var orbit := OrbitCameraScript.new() as Node3D
	orbit.name = "OrbitCamera"
	orbit.set("chase_camera_path", NodePath("../ChaseCamera"))
	orbit.set("hood_camera_path", NodePath("../HoodCamera"))
	orbit.set("cockpit_camera_path", NodePath("../CockpitCamera"))
	driver.add_child(orbit)
	var hood := HoodCameraScript.new() as Node3D
	hood.name = "HoodCamera"
	driver.add_child(hood)
	var cockpit := CockpitCameraScript.new() as Node3D
	cockpit.name = "CockpitCamera"
	driver.add_child(cockpit)
	_managed.append(driver)
	add_child(driver)

	assert_that(driver.call("_is_forward_view")).is_true()  # chase by default

	orbit.call("cycle_mode_for_test")  # orbit
	assert_that(driver.call("_is_forward_view")).is_false()

	orbit.call("cycle_mode_for_test")  # hood — droplets still show
	assert_that(driver.call("_is_forward_view")).is_true()

	orbit.call("cycle_mode_for_test")  # cockpit — first-person carries droplets
	assert_that(driver.call("_is_forward_view")).is_true()

	orbit.call("cycle_mode_for_test")  # chase again
	assert_that(driver.call("_is_forward_view")).is_true()