# tests/suites/test_cockpit_visibility.gd
extends GdUnitTestSuite

## D6 cockpit-visibility gate ("I just see the red interior"): first-person
## driving must be able to SEE OUT. Root cause on the Comet (cc0_sedan_sports):
## its Kenney GLB carries NO glass mesh — the 'body' shell, painted red through
## the CC0 colormap fallback, IS the windshield, and it is OPAQUE doubleSided,
## so from the cockpit the red backfaces fill the view. The generic case
## (sports_coupe etc.) does carry a Glass mesh; the paint pipeline now ships it
## tinted TRANSPARENT (TRANSPARENCY_ALPHA at DEFAULT_GLASS_COLOR.a), and the
## cockpit pass still owns it from any baseline (transparency + alpha are
## value-snapshotted per material), dropping it to COCKPIT_GLASS_ALPHA.
##
## Fix under test (mode-driven, headless-safe, mirroring the existing
## CockpitRig ownership probe): while the CockpitCamera owns the viewport,
## CockpitRig.sync_shell_view() hides the SHELL meshes (Comet body/spoiler) and
## flips GLASS surfaces to TRANSPARENCY_ALPHA at COCKPIT_GLASS_ALPHA; leaving
## cockpit restores every original flag so chase / hood / orbit render
## unchanged. Wheels are never touched.

const PlayerCarScene: PackedScene = preload("res://scenes/vehicle/player_car.tscn")
const CometConfig: CarConfig = preload("res://resources/cars/cc0_sedan_sports.tres")
const R35Config: CarConfig = preload("res://resources/cars/nissan_gt_r35_2017.tres")
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

## Instantiates the real player scene, repoints it to the GT-R R35 config by name
## (res://resources/cars/nissan_gt_r35_2017.tres), and rebuilds the visual so the
## nissan_gt-r_r35_2017 GLB (Body + Headlight/Taillight/DarkTrim dressing + a real
## Glass windscreen) is live under CarBody. Mirrors _build_comet_car.
func _build_r35_car(root: Node) -> Node3D:
	var car := PlayerCarScene.instantiate() as Node3D
	_managed.append(car)
	root.add_child(car)
	var controller := car.get_node_or_null("PlayerCarController")
	assert_that(controller).is_not_null()
	car.set("config", R35Config)
	controller.set("_car_id", "nissan_gt_r35_2017")
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

## Generic glass case: the AI cars DO carry a Glass mesh. The paint pipeline
## ships it tinted TRANSPARENT (TRANSPARENCY_ALPHA at the baseline alpha), and
## the cockpit pass must own that baseline exactly like it owned the old
## opaque one: while the cockpit camera is active the glass drops to
## COCKPIT_GLASS_ALPHA; leaving cockpit restores the tinted baseline (the
## transparency value no longer changes, only the alpha).
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
	# Baseline: the pipeline ships tinted TRANSPARENT glass (alpha = the
	# DEFAULT_GLASS_COLOR tint), not the old opaque mirror pane.
	assert_that(glass_mat.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)
	var baseline_alpha := glass_mat.albedo_color.a
	assert_that(baseline_alpha).is_equal_approx(CarVisuals.DEFAULT_GLASS_COLOR.a, 0.001)

	var cam := _new_cockpit_camera(root)
	rig.call("sync_shell_view")
	assert_that(glass_mat.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)

	cam.call("set_view_active", true)
	assert_that(rig.call("sync_visibility")).is_true()
	rig.call("sync_shell_view")
	assert_that(glass_mat.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_that(glass_mat.albedo_color.a).is_less(0.25)
	assert_that(glass_mat.albedo_color.a).is_equal_approx(CarVisuals.COCKPIT_GLASS_ALPHA, 0.001)

	cam.call("set_view_active", false)
	rig.call("sync_shell_view")
	assert_that(glass_mat.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)
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

## Step 3 of fix_gtr_windshield_glass.md: the R35 shell's NON-GLASS body dressing
## (headlights, taillights, the DarkTrim grille/intake/vents/splitter) is now
## SHELL, so it hides with the paint shell while the cockpit camera owns the
## viewport — otherwise, once the binnacle is lowered, it floats in the driver's
## forward view (sec 2.5). Every piece must come back EXACTLY when the camera
## releases the viewport, and the real Glass windscreen must stay visible and
## transparent.
func test_r35_exterior_dressing_hidden_only_while_cockpit_active() -> void:
	var root := _new_root()
	var car := await _build_r35_car(root)
	var rig := car.get_node_or_null("CockpitRig") as CockpitRig
	assert_that(rig).is_not_null()
	var cam := _new_cockpit_camera(root)
	var visual := _visual_root(car)
	assert_that(visual).is_not_null()
	if visual == null:
		return

	var roles: Dictionary = CarVisuals.cockpit_roles(visual)
	var shell: Array = roles["shell"]
	var glass: Array = roles["glass"]
	assert_that(shell.is_empty()).is_false()
	assert_that(glass.is_empty()).is_false()

	# The named dressing the R35 fronts over the horizon: two headlights, two
	# taillights and the DarkTrim grille / intake / vents / splitter. Each must be
	# SHELL (hidden in cockpit) and visible outside it.
	var dressing_names: Array[String] = [
		"Headlight_L", "Headlight_R", "Taillight_L", "Taillight_R",
		"UpperGrille", "FrontIntake", "FrontSplitter",
		"HoodVent_L", "HoodVent_R", "SideVent_L", "SideVent_R",
	]
	var dressing: Array[MeshInstance3D] = []
	for dressing_name: String in dressing_names:
		var dressing_mesh := visual.find_child(dressing_name, true, false) as MeshInstance3D
		assert_that(dressing_mesh).is_not_null()
		if dressing_mesh == null:
			continue
		assert_that(shell.has(dressing_mesh)).is_true()
		assert_that(dressing_mesh.visible).is_true()  # untouched outside cockpit
		dressing.append(dressing_mesh)
	assert_that(dressing.size()).is_equal(dressing_names.size())

	var windscreen := visual.find_child("Windscreen", true, false) as MeshInstance3D
	assert_that(windscreen).is_not_null()
	if windscreen == null:
		return
	assert_that(glass.has(windscreen)).is_true()
	assert_that(windscreen.visible).is_true()

	# Cockpit active: EVERY dressing mesh hides; the windscreen stays visible and
	# drops to the clean COCKPIT_GLASS_ALPHA.
	cam.call("set_view_active", true)
	assert_that(rig.call("sync_visibility")).is_true()
	rig.call("sync_shell_view")
	for dressing_mesh: MeshInstance3D in dressing:
		assert_that(dressing_mesh.visible).is_false()
	assert_that(windscreen.visible).is_true()
	var glass_mat: StandardMaterial3D = windscreen.get_surface_override_material(0) as StandardMaterial3D
	assert_that(glass_mat).is_not_null()
	if glass_mat != null:
		assert_that(glass_mat.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)
		assert_that(glass_mat.albedo_color.a).is_equal_approx(CarVisuals.COCKPIT_GLASS_ALPHA, 0.001)

	# Released: every dressing mesh is restored exactly.
	cam.call("set_view_active", false)
	assert_that(rig.call("sync_visibility")).is_false()
	rig.call("sync_shell_view")
	for dressing_mesh: MeshInstance3D in dressing:
		assert_that(dressing_mesh.visible).is_true()

## Step 3 must NOT touch the wheel branch: the Comet's CC0 'colormap'
## wheel-front-left and the AI starter car's two-surface (Tire + Rim) Wheel_FL
## both stay visible while the cockpit camera owns the viewport.
func test_wheel_assembly_stays_visible_in_cockpit() -> void:
	# CC0 Comet: single colormap wheel mesh, classified by node name.
	var comet_root := _new_root()
	var comet := await _build_comet_car(comet_root)
	var comet_rig := comet.get_node_or_null("CockpitRig") as CockpitRig
	var comet_cam := _new_cockpit_camera(comet_root)
	var comet_visual := _visual_root(comet)
	assert_that(comet_rig).is_not_null()
	assert_that(comet_visual).is_not_null()
	if comet_visual != null:
		var comet_shell: Array = CarVisuals.cockpit_roles(comet_visual)["shell"]
		var comet_wheel := comet_visual.get_node_or_null("wheel-front-left") as MeshInstance3D
		assert_that(comet_wheel).is_not_null()
		if comet_wheel != null:
			assert_that(comet_shell.has(comet_wheel)).is_false()
			comet_cam.call("set_view_active", true)
			comet_rig.call("sync_shell_view")
			assert_that(comet_wheel.visible).is_true()

	# AI starter car (sports_coupe): Wheel_FL is ONE mesh with TWO surfaces
	# (Tire + Rim) — the multi-surface wheel branch must resolve OTHER, not SHELL.
	var starter_root := _new_root()
	var starter := PlayerCarScene.instantiate() as Node3D
	_managed.append(starter)
	starter_root.add_child(starter)
	var starter_controller := starter.get_node_or_null("PlayerCarController")
	assert_that(starter_controller).is_not_null()
	starter.set("config", load("res://resources/cars/starter_car.tres"))
	starter_controller.set("_car_id", "starter_car")
	starter_controller.call("_apply_visual")
	await get_tree().process_frame
	var starter_rig := starter.get_node_or_null("CockpitRig") as CockpitRig
	var starter_cam := _new_cockpit_camera(starter_root)
	var starter_visual := _visual_root(starter)
	assert_that(starter_rig).is_not_null()
	assert_that(starter_visual).is_not_null()
	if starter_visual != null:
		var starter_shell: Array = CarVisuals.cockpit_roles(starter_visual)["shell"]
		# Resolve the corner through the PRODUCTION seam rather than a raw child
		# lookup: Godot wraps a single-root glTF scene, so this car's Wheel_FL sits
		# under the wrapper's `SportsCoupe` child (one level below the instance
		# root). resolve_wheel_nodes() is depth-independent on purpose.
		var starter_wheels: Dictionary = CarVisuals.resolve_wheel_nodes(starter_visual, "starter_car")
		assert_that(starter_wheels.size()).is_equal(4)
		var starter_fl: Array = starter_wheels.get("fl", [])
		assert_that(starter_fl).is_not_empty()
		if not starter_fl.is_empty():
			var starter_wheel := starter_fl[0] as MeshInstance3D
			assert_that(starter_wheel).is_not_null()
			assert_that(starter_shell.has(starter_wheel)).is_false()
			starter_cam.call("set_view_active", true)
			starter_rig.call("sync_shell_view")
			assert_that(starter_wheel.visible).is_true()