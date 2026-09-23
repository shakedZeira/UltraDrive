# tests/suites/test_cockpit_visibility.gd
extends GdUnitTestSuite

## D6 cockpit-visibility gate ("I just see the red interior"): first-person
## driving must be able to SEE OUT. Root cause on the Comet (cc0_sedan_sports):
## its Kenney GLB carries NO glass mesh — the 'body' shell, painted red through
## the CC0 colormap fallback, IS the windshield, and it is OPAQUE doubleSided,
## so from the cockpit the red backfaces fill the view. The generic case
## (sports_coupe etc.) does carry a Glass mesh, but the paint pipeline ships it
## OPAQUE too, so the pane blocks the driver exactly the same way.
##
## Fix under test (mode-driven, headless-safe, mirroring the existing
## CockpitRig ownership probe): while the CockpitCamera owns the viewport,
## CockpitRig.sync_shell_view() hides the SHELL meshes (Comet body/spoiler) and
## flips GLASS surfaces to TRANSPARENCY_ALPHA at COCKPIT_GLASS_ALPHA; leaving
## cockpit restores every original flag so chase / hood / orbit render
## unchanged. Wheels are never touched.

const PlayerCarScene: PackedScene = preload("res://scenes/vehicle/player_car.tscn")
const CometConfig: CarConfig = preload("res://resources/cars/cc0_sedan_sports.tres")
const ChaseCameraScript: GDScript = preload("res://scripts/camera/chase_camera.gd")
const OrbitCameraScript: GDScript = preload("res://scripts/camera/orbit_camera.gd")
const HoodCameraScript: GDScript = preload("res://scripts/camera/hood_camera.gd")
const CockpitCameraScript: GDScript = preload("res://scripts/camera/cockpit_camera.gd")

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

func _new_cockpit_camera(root: Node) -> Node3D:
	var cam := CockpitCameraScript.new() as Node3D
	cam.name = "CockpitCamera"
	_managed.append(cam)
	root.add_child(cam)
	return cam

## Instantiates the real player scene, repoints it to the Comet config by name
## (res://resources/cars/cc0_sedan_sports.tres), and rebuilds the visual so the
## red cc0_sedan_sports GLB is live under CarBody.
func _build_comet_car(root: Node) -> Node3D:
	var car := PlayerCarScene.instantiate() as Node3D
	_managed.append(car)
	root.add_child(car)
	var controller := car.get_node_or_null("PlayerCarController")
	assert_that(controller).is_not_null()
	car.set("config", CometConfig)
	controller.set("_car_id", "cc0_sedan_sports")
	controller.call("_apply_visual")
	await get_tree().process_frame  # flush the queue_freed default GLB + probe
	return car

## The live GLB visual root under CarBody: the newest Node3D child that is not
## the BodyRig suspension rig, not the runtime reflection probe, and not a
## queue-freed leftover from a car swap.
func _visual_root(car: Node3D) -> Node3D:
	var body := car.get_node_or_null("CarBody") as Node3D
	if body == null:
		return null
	for child: Node in body.get_children():
		if child is BodyRig or child is ReflectionProbe or child.is_queued_for_deletion():
			continue
		if child is Node3D:
			return child as Node3D
	return null

## Root cause on the Comet, pinned as a structural fact: ZERO glass surfaces and
## a non-empty shell (body + spoiler) that the cockpit pass must hide so the
## driver sees out through the painted body shell.
func test_comet_has_no_glass_mesh_so_shell_is_the_windshield() -> void:
	var root := _new_root()
	var car := await _build_comet_car(root)
	var visual := _visual_root(car)
	assert_that(visual).is_not_null()
	if visual == null:
		return

	var roles: Dictionary = CarVisuals.cockpit_roles(visual)
	var glass: Array = roles["glass"]
	var shell: Array = roles["shell"]
	assert_that(glass.is_empty()).is_true()   # the Comet has no glass mesh
	assert_that(shell.is_empty()).is_false()  # body + spoiler = the shell
	assert_that(shell.size()).is_greater_equal(2)

	var has_body: bool = false
	var has_spoiler: bool = false
	for shell_node_variant: Variant in shell:
		var shell_mesh := shell_node_variant as MeshInstance3D
		assert_that(shell_mesh).is_not_null()
		assert_that(shell_mesh.visible).is_true()  # untouched outside cockpit
		if shell_mesh.name == "body":
			has_body = true
		if shell_mesh.name == "spoiler":
			has_spoiler = true
	assert_that(has_body).is_true()
	assert_that(has_spoiler).is_true()

## The Comet windshield IS the shell: while the cockpit camera owns the viewport
## the shell meshes must be hidden (unblocked), wheels stay visible, and the
## moment the cockpit camera loses the viewport the shell is restored.
func test_comet_shell_unblocked_only_while_cockpit_camera_active() -> void:
	var root := _new_root()
	var car := await _build_comet_car(root)
	var rig := car.get_node_or_null("CockpitRig") as CockpitRig
	assert_that(rig).is_not_null()
	var cam := _new_cockpit_camera(root)
	var visual := _visual_root(car)
	assert_that(visual).is_not_null()
	if visual == null:
		return
	var shell: Array = CarVisuals.cockpit_roles(visual)["shell"]
	var front_wheel := visual.get_node_or_null("wheel-front-left") as MeshInstance3D

	var any_hidden := func() -> bool:
		for shell_node_variant: Variant in shell:
			if not (shell_node_variant as MeshInstance3D).visible:
				return true
		return false

	assert_that(rig.call("sync_visibility")).is_false()
	rig.call("sync_shell_view")
	assert_that(any_hidden.call()).is_false()
	if front_wheel != null:
		assert_that(front_wheel.visible).is_true()

	cam.call("set_view_active", true)
	assert_that(rig.call("sync_visibility")).is_true()
	rig.call("sync_shell_view")
	assert_that(any_hidden.call()).is_true()  # shell unblocked -> see OUT
	for shell_node_variant: Variant in shell:
		var shell_mesh := shell_node_variant as MeshInstance3D
		assert_that(shell_mesh.visible).is_false()
	if front_wheel != null:
		assert_that(front_wheel.visible).is_true()  # wheels never hide

	cam.call("set_view_active", false)
	assert_that(rig.call("sync_visibility")).is_false()
	rig.call("sync_shell_view")
	assert_that(any_hidden.call()).is_false()
	for shell_node_variant: Variant in shell:
		assert_that((shell_node_variant as MeshInstance3D).visible).is_true()

## Generic glass case: the AI cars DO carry a Glass mesh, but the paint pipeline
## ships it OPAQUE, which blocks the driver exactly like the Comet's shell.
## While the cockpit camera is active the glass must flip to TRANSPARENCY_ALPHA
## with an alpha below the cleanliness threshold; leaving cockpit restores the
## original OPAQUE state exactly.
func test_ai_car_glass_is_transparent_only_while_cockpit_active() -> void:
	var root := _new_root()
	var car := PlayerCarScene.instantiate() as Node3D
	_managed.append(car)
	root.add_child(car)
	# Rebuild deterministically to the starter car (sports_coupe GLB has a real
	# Glass mesh) — the _ready path reads the persisted garage save otherwise.
	var controller := car.get_node_or_null("PlayerCarController")
	assert_that(controller).is_not_null()
	car.set("config", load("res://resources/cars/starter_car.tres"))
	controller.set("_car_id", "starter_car")
	controller.call("_apply_visual")
	await get_tree().process_frame
	var rig := car.get_node_or_null("CockpitRig") as CockpitRig
	assert_that(rig).is_not_null()
	var visual := _visual_root(car)
	assert_that(visual).is_not_null()
	if visual == null:
		return

	var glass: Array = CarVisuals.cockpit_roles(visual)["glass"]
	assert_that(glass.is_empty()).is_false()  # sports_coupe carries a real glass mesh
	var glass_mesh := glass[0] as MeshInstance3D
	var glass_mat: StandardMaterial3D = glass_mesh.get_surface_override_material(0) as StandardMaterial3D
	assert_that(glass_mat).is_not_null()
	if glass_mat == null:
		return
	assert_that(glass_mat.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_DISABLED)
	var baseline_alpha := glass_mat.albedo_color.a

	var cam := _new_cockpit_camera(root)
	rig.call("sync_shell_view")
	assert_that(glass_mat.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_DISABLED)

	cam.call("set_view_active", true)
	assert_that(rig.call("sync_visibility")).is_true()
	rig.call("sync_shell_view")
	assert_that(glass_mat.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_that(glass_mat.albedo_color.a).is_less(0.25)
	assert_that(glass_mat.albedo_color.a).is_equal_approx(CarVisuals.COCKPIT_GLASS_ALPHA, 0.001)

	cam.call("set_view_active", false)
	rig.call("sync_shell_view")
	assert_that(glass_mat.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_DISABLED)
	assert_that(glass_mat.albedo_color.a).is_equal_approx(baseline_alpha, 0.001)

## The full 4-mode C-cycle drives the flags: cockpit = rig visible + shell
## unblocked; chase / orbit / hood = rig hidden + shell restored. The interior
## gate (CockpitRig toggles with ownership) holds while the shell pass runs.
func test_shell_and_rig_flags_follow_camera_cycle() -> void:
	var root := _new_root()
	var car := await _build_comet_car(root)
	var rig := car.get_node_or_null("CockpitRig") as CockpitRig
	assert_that(rig).is_not_null()
	var visual := _visual_root(car)
	assert_that(visual).is_not_null()
	if visual == null:
		return
	var shell: Array = CarVisuals.cockpit_roles(visual)["shell"]

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

	var shells_hidden := func() -> bool:
		for shell_node_variant: Variant in shell:
			if not (shell_node_variant as MeshInstance3D).visible:
				return true
		return false

	# CHASE (default): rig hidden, shell visible.
	assert_that(rig.call("sync_visibility")).is_false()
	rig.call("sync_shell_view")
	assert_that(shells_hidden.call()).is_false()

	# ORBIT
	orbit.call("cycle_mode_for_test")
	assert_that(rig.call("sync_visibility")).is_false()
	rig.call("sync_shell_view")
	assert_that(shells_hidden.call()).is_false()

	# HOOD — interior still hidden (probe stays inside the shell).
	orbit.call("cycle_mode_for_test")
	assert_that(rig.call("sync_visibility")).is_false()
	rig.call("sync_shell_view")
	assert_that(shells_hidden.call()).is_false()

	# COCKPIT — interior visible AND the shell unblocked so the driver sees out.
	orbit.call("cycle_mode_for_test")
	assert_that(rig.call("sync_visibility")).is_true()
	rig.call("sync_shell_view")
	assert_that(shells_hidden.call()).is_true()

	# CHASE — full restore.
	orbit.call("cycle_mode_for_test")
	assert_that(rig.call("sync_visibility")).is_false()
	rig.call("sync_shell_view")
	assert_that(shells_hidden.call()).is_false()

## The F2a interior toggle is unchanged by the shell pass: the rig's visibility
## still follows the cockpit camera's set_view_active ownership directly.
func test_cockpit_rig_toggle_unchanged_by_shell_sync() -> void:
	var root := _new_root()
	var car := await _build_comet_car(root)
	var rig := car.get_node_or_null("CockpitRig") as CockpitRig
	assert_that(rig).is_not_null()
	var cam := _new_cockpit_camera(root)

	assert_that(rig.call("sync_visibility")).is_false()
	assert_that(rig.get("visible")).is_false()

	cam.call("set_view_active", true)
	rig.call("sync_shell_view")
	assert_that(rig.call("sync_visibility")).is_true()
	assert_that(rig.get("visible")).is_true()

	cam.call("set_view_active", false)
	rig.call("sync_shell_view")
	assert_that(rig.call("sync_visibility")).is_false()
	assert_that(rig.get("visible")).is_false()

## Headless smoke + restore-exactness: after a full cockpit on/off round trip
## EVERY MeshInstance3D under the visual returns to its authored visibility, and
## repeated sync calls stay idempotent (no script errors).
func test_headless_instantiation_restores_all_visibility_exactly() -> void:
	var root := _new_root()
	var car := await _build_comet_car(root)
	var rig := car.get_node_or_null("CockpitRig") as CockpitRig
	assert_that(rig).is_not_null()
	var cam := _new_cockpit_camera(root)
	var visual := _visual_root(car)
	assert_that(visual).is_not_null()
	if visual == null:
		return

	var baseline := {}
	for mesh_variant: Variant in visual.find_children("*", "MeshInstance3D", true, false):
		baseline[mesh_variant.get_path()] = (mesh_variant as MeshInstance3D).visible
	assert_that(baseline.is_empty()).is_false()

	cam.call("set_view_active", true)
	rig.call("sync_visibility")
	rig.call("sync_shell_view")
	cam.call("set_view_active", false)
	rig.call("sync_visibility")
	rig.call("sync_shell_view")

	for mesh_variant: Variant in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_variant as MeshInstance3D
		assert_that(mesh_instance.visible).is_equal(baseline[mesh_instance.get_path()])

	# Idempotent: repeated disabled syncs are no-ops and change nothing.
	rig.call("sync_shell_view")
	rig.call("sync_shell_view")
	for mesh_variant: Variant in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_variant as MeshInstance3D
		assert_that(mesh_instance.visible).is_equal(baseline[mesh_instance.get_path()])