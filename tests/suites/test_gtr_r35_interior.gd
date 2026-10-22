# tests/suites/test_gtr_r35_interior.gd
extends GdUnitTestSuite

const R35_CONFIG := "res://resources/cars/nissan_gt_r35_2017.tres"
const R35_COCKPIT := "res://scenes/vehicle/interiors/nissan_gt_r35_2017_cockpit.tscn"
const PlayerCarScene: PackedScene = preload("res://scenes/vehicle/player_car.tscn")
const CockpitCameraScript: GDScript = preload("res://scripts/camera/cockpit_camera.gd")
const HUD_SCENE: PackedScene = preload("res://scenes/ui/hud.tscn")

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

func _new_r35_car(root: Node) -> Node3D:
	var car := PlayerCarScene.instantiate() as Node3D
	car.set("config", load(R35_CONFIG) as CarConfig)
	_managed.append(car)
	root.add_child(car)
	return car

## P1: the authored R35 cockpit scene instantiates headless with the Sec 4.2
## anchors (SteeringWheel / Dash / SeatRoot) and the P2 gauge pods.
func test_r35_cockpit_scene_instantiates_with_anchors() -> void:
	var root := _new_root()
	var cockpit := (load(R35_COCKPIT) as PackedScene).instantiate() as Node3D
	_managed.append(cockpit)
	root.add_child(cockpit)

	assert_that(cockpit.get_node_or_null("SteeringWheel")).is_not_null()
	assert_that(cockpit.get_node_or_null("Dash")).is_not_null()
	assert_that(cockpit.get_node_or_null("SeatRoot")).is_not_null()
	assert_that(cockpit.get_node_or_null("GaugeRPM")).is_not_null()
	assert_that(cockpit.get_node_or_null("GaugeSpeed")).is_not_null()
	assert_that(cockpit.get_node_or_null("GaugeMFD")).is_not_null()

## P1 discipline: emissive-only flat material, no OmniLight, no SubViewport,
## shadow casting off on every mesh.
func test_r35_cockpit_is_light_free_shadowless_and_emissive() -> void:
	var root := _new_root()
	var cockpit := (load(R35_COCKPIT) as PackedScene).instantiate() as Node3D
	_managed.append(cockpit)
	root.add_child(cockpit)

	assert_that(cockpit.find_children("*", "OmniLight3D", true, false)).is_empty()
	assert_that(cockpit.find_children("*", "SubViewport", true, false)).is_empty()

	var meshes := cockpit.find_children("*", "MeshInstance3D", true, false)
	assert_that(meshes.is_empty()).is_false()
	for node: Node in meshes:
		assert_that((node as MeshInstance3D).cast_shadow).is_equal(
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)

	var wheel := cockpit.get_node("SteeringWheel") as MeshInstance3D
	var mat := wheel.mesh.material as StandardMaterial3D
	assert_that(mat).is_not_null()
	assert_that(mat.emission_enabled).is_true()
	assert_float(mat.emission_energy_multiplier).is_equal_approx(0.15, 0.0001)
	assert_float(mat.roughness).is_equal_approx(0.9, 0.05)
	assert_that(mat.albedo_color).is_equal(Color(0.1, 0.1, 0.13, 1))

## P1: right-hand drive — the driver door card sits on car-local -X and the
## centre stack riser on the driver's left (+X).
func test_r35_cockpit_is_right_hand_drive() -> void:
	var root := _new_root()
	var cockpit := (load(R35_COCKPIT) as PackedScene).instantiate() as Node3D
	_managed.append(cockpit)
	root.add_child(cockpit)

	var driver_door := cockpit.get_node_or_null("DoorCardRight") as Node3D
	var riser := cockpit.get_node_or_null("CentreStackRiser") as Node3D
	assert_that(driver_door).is_not_null()
	assert_that(riser).is_not_null()
	assert_that(driver_door.position.x).is_less(0.0)
	assert_that(riser.position.x).is_greater(0.0)

## P1: a player car whose config has the R35 InteriorResource resolves the
## authored cabin as a child named "Interior" and the steering-wheel spin seam
## drives the cabin wheel (mirrors test_cockpit_interior _recover_steer_spin).
func test_player_car_r35_config_resolves_interior_and_spins_wheel() -> void:
	var root := _new_root()
	var car := _new_r35_car(root)
	var rig := car.get_node_or_null("CockpitRig") as CockpitRig
	assert_that(rig).is_not_null()

	var interior := rig.get_node_or_null("Interior")
	assert_that(interior).is_not_null()
	var wheel := rig.find_child("SteeringWheel", true, false) as Node3D
	assert_that(wheel).is_not_null()
	if wheel == null:
		return
	assert_that(rig.get_steering_wheel()).is_same(wheel)
	var base := wheel.basis

	(car as VehiclePhysics)._steer_input = 0.5
	rig.call("_process", 1.0 / 60.0)

	var spin := _recover_steer_spin(base, wheel.basis)
	assert_float(spin).is_equal_approx(0.5 * CockpitRig.STEER_VISUAL_MAX_RAD_CABIN, 0.0001)
	assert_that(wheel.basis.y).is_equal_approx(base.y, Vector3(0.0001, 0.0001, 0.0001))

## P1: the interior visibility gate still follows cockpit-camera ownership for
## an override car — hidden for chase, visible only while the cockpit cam is
## current.
func test_r35_interior_visibility_follows_cockpit_camera() -> void:
	var root := _new_root()
	var car := _new_r35_car(root)
	var cockpit := CockpitCameraScript.new() as Node3D
	cockpit.name = "CockpitCamera"
	_managed.append(cockpit)
	root.add_child(cockpit)

	var rig := car.get_node_or_null("CockpitRig") as CockpitRig
	assert_that(rig).is_not_null()
	assert_that(rig.call("sync_visibility")).is_false()
	assert_that(rig.get("visible")).is_false()

	cockpit.call("set_view_active", true)
	assert_that(rig.call("sync_visibility")).is_true()
	assert_that(rig.get("visible")).is_true()

	cockpit.call("set_view_active", false)
	assert_that(rig.call("sync_visibility")).is_false()
	assert_that(rig.get("visible")).is_false()

## P2: the binnacle needles follow the pure clamped sweep
##   angle = -0.75 + 1.5 * clampf((value - lo) / (hi - lo), 0, 1)
## with lo/hi = idle/redline rpm (tach) and 0/face_max km-h (speedo), exactly as
## CockpitRig.gauge_rpm_angle / gauge_speed_angle encode. idle/redline come from
## the mounted R35 CarConfig (default idle 800, redline 7000).
func test_r35_gauge_needles_follow_clamped_sweep() -> void:
	var root := _new_root()
	var car := _new_r35_car(root)
	var rig := car.get_node_or_null("CockpitRig") as CockpitRig
	assert_that(rig).is_not_null()
	var rpm_needle := rig.get_rpm_needle()
	var speed_needle := rig.get_speed_needle()
	assert_that(rpm_needle).is_not_null()
	assert_that(speed_needle).is_not_null()
	if rpm_needle == null or speed_needle == null:
		return

	var idle := 800.0
	var redline := 7000.0

	# idle rpm / 0 km-h -> sweep start (-0.75), the formula's zero of the sweep.
	rig.call("apply_drive_info", {"steer": 0.0, "speed_kmh": 0.0, "rpm": idle})
	assert_float(rpm_needle.rotation.x).is_equal_approx(-0.75, 0.0001)
	assert_float(speed_needle.rotation.x).is_equal_approx(-0.75, 0.0001)

	# redline / face-max (320) -> sweep end (+0.75).
	rig.call("apply_drive_info", {"steer": 0.0, "speed_kmh": 320.0, "rpm": redline})
	assert_float(rpm_needle.rotation.x).is_equal_approx(0.75, 0.0001)
	assert_float(speed_needle.rotation.x).is_equal_approx(0.75, 0.0001)

	# Midpoints: (idle+redline)/2 and half the speed face -> 0.0.
	rig.call("apply_drive_info", {"steer": 0.0, "speed_kmh": 160.0, "rpm": 3900.0})
	assert_float(rpm_needle.rotation.x).is_equal_approx(0.0, 0.0001)
	assert_float(speed_needle.rotation.x).is_equal_approx(0.0, 0.0001)

	# Hard clamps on both ends (over-rev, negative speed).
	rig.call("apply_drive_info", {"steer": 0.0, "speed_kmh": 999.0, "rpm": 12000.0})
	assert_float(rpm_needle.rotation.x).is_equal_approx(0.75, 0.0001)
	assert_float(speed_needle.rotation.x).is_equal_approx(0.75, 0.0001)
	rig.call("apply_drive_info", {"steer": 0.0, "speed_kmh": -50.0, "rpm": 0.0})
	assert_float(rpm_needle.rotation.x).is_equal_approx(-0.75, 0.0001)
	assert_float(speed_needle.rotation.x).is_equal_approx(-0.75, 0.0001)

	# Cross-check a spread of rpm values against the static pure function.
	for rpm in [1000.0, 2500.0, 4800.0, 6000.0]:
		rig.call("apply_drive_info", {"steer": 0.0, "speed_kmh": 0.0, "rpm": rpm})
		assert_float(rpm_needle.rotation.x).is_equal_approx(
			CockpitRig.gauge_rpm_angle(rpm, idle, redline), 0.0001
		)
	for kmh in [40.0, 96.0, 200.0]:
		rig.call("apply_drive_info", {"steer": 0.0, "speed_kmh": kmh, "rpm": idle})
		assert_float(speed_needle.rotation.x).is_equal_approx(
			CockpitRig.gauge_speed_angle(kmh, 320.0), 0.0001
		)

## P2: the emissive shift-light strip stays at its dim base below 0.9 * redline
## and flips toward the red "shift now" state above it, then back (idempotent).
func test_r35_shift_light_toggles_above_ninety_percent_redline() -> void:
	var root := _new_root()
	var car := _new_r35_car(root)
	var rig := car.get_node_or_null("CockpitRig") as CockpitRig
	assert_that(rig).is_not_null()
	var mat := rig.get_shift_material()
	assert_that(mat).is_not_null()
	if mat == null:
		return

	rig.call("apply_drive_info", {"steer": 0.0, "speed_kmh": 0.0, "rpm": 5000.0})
	assert_that(rig.get_shift_light_on()).is_false()
	assert_float(mat.emission_energy_multiplier).is_equal_approx(0.15, 0.0001)
	var base_emission: Color = mat.emission

	# 0.95 * 7000 = 6650 rpm -> red shift state, brighter and red-dominant.
	rig.call("apply_drive_info", {"steer": 0.0, "speed_kmh": 0.0, "rpm": 6650.0})
	assert_that(rig.get_shift_light_on()).is_true()
	assert_float(mat.emission_energy_multiplier).is_greater(0.15)
	assert_that(mat.emission.r).is_greater(mat.emission.g)
	assert_that(mat.emission.r).is_greater(base_emission.r)

	# Dropping back below the threshold restores the base (idempotent).
	rig.call("apply_drive_info", {"steer": 0.0, "speed_kmh": 0.0, "rpm": 2000.0})
	assert_that(rig.get_shift_light_on()).is_false()
	assert_float(mat.emission_energy_multiplier).is_equal_approx(0.15, 0.0001)
	assert_that(mat.emission.r).is_equal(base_emission.r)

## P3 HUD coupling: the R35 InteriorResource ships suppress_hud_dash, so while
## the cockpit camera owns the viewport the 2D text panel stays HIDDEN but the
## %Cluster dim is untouched (still subtract-mode 0.2). Mirrors test_cockpit_hud.
func test_r35_suppress_hud_dash_hides_panel_keeps_cluster_dim() -> void:
	var root := _new_root()
	var cam := CockpitCameraScript.new() as Node3D
	cam.name = "CockpitCamera"
	_managed.append(cam)
	root.add_child(cam)
	cam.call("set_view_active", true)

	var hud := HUD_SCENE.instantiate()
	_managed.append(hud)
	root.add_child(hud)

	var car := _new_r35_car(root) as VehiclePhysics
	# PlayerCarController._ready() reloads car.config from the garage save once
	# the node enters the tree, clobbering the pre-add R35 config; re-assert it
	# so the live car (what the HUD reads) genuinely ships the R35 interior.
	car.config = load(R35_CONFIG) as CarConfig
	car.set_simulation_enabled(false)
	await get_tree().process_frame
	await get_tree().process_frame

	var dash := hud.get_node("CockpitDash") as CockpitDash
	assert_that(dash).is_not_null()
	if dash == null:
		return
	assert_that(VehicleManager.get_player_car()).is_same(car)
	assert_that(dash.sync_cockpit_mode()).is_true()
	assert_that(dash.panel.visible).is_false()
	var cluster := hud.get_node("Root/Cluster") as Control
	assert_that(cluster.modulate.a).is_equal_approx(0.2, 0.0001)

## P3 contract: an interior-less car (interior == null) keeps today's exact
## panel behaviour — suppress_hud_dash is R35-only.
func test_non_r35_car_keeps_hud_dash_panel() -> void:
	var root := _new_root()
	var cam := CockpitCameraScript.new() as Node3D
	cam.name = "CockpitCamera"
	_managed.append(cam)
	root.add_child(cam)
	cam.call("set_view_active", true)

	var hud := HUD_SCENE.instantiate()
	_managed.append(hud)
	root.add_child(hud)

	var car := PlayerCarScene.instantiate() as VehiclePhysics
	_managed.append(car)
	root.add_child(car)
	car.set_simulation_enabled(false)
	await get_tree().process_frame
	await get_tree().process_frame

	var dash := hud.get_node("CockpitDash") as CockpitDash
	assert_that(dash).is_not_null()
	if dash == null:
		return
	assert_that(VehicleManager.get_player_car()).is_same(car)
	assert_that(dash.sync_cockpit_mode()).is_true()
	assert_that(dash.panel.visible).is_true()
	assert_that(dash.call("_hud_dash_suppressed")).is_false()

## P3: the GT-R wheel keeps the local-Y axle (the spin seam right-multiplies a
## Y rotation), its torus rim stays in the ~0.18 m band, and one paddle leaf
## sits on each side of the hub (eye-local +/-X relative to the hub origin).
func test_r35_wheel_rim_paddles_and_spin_axle() -> void:
	var root := _new_root()
	var car := _new_r35_car(root)
	var rig := car.get_node_or_null("CockpitRig") as CockpitRig
	assert_that(rig).is_not_null()
	var wheel := rig.get_steering_wheel()
	assert_that(wheel).is_not_null()
	if wheel == null:
		return

	var torus := wheel.mesh as TorusMesh
	assert_that(torus).is_not_null()
	assert_float(torus.outer_radius).is_greater_equal(0.16)
	assert_float(torus.outer_radius).is_less_equal(0.20)

	assert_that(wheel.get_node_or_null("WheelHub")).is_not_null()
	assert_that(wheel.get_node_or_null("Badge")).is_not_null()
	assert_that(wheel.get_node_or_null("FlatBottom")).is_not_null()
	var left := wheel.get_node_or_null("PaddleLeft") as Node3D
	var right := wheel.get_node_or_null("PaddleRight") as Node3D
	assert_that(left).is_not_null()
	assert_that(right).is_not_null()
	if left != null and right != null:
		var left_x := wheel.to_local(left.global_position).x
		var right_x := wheel.to_local(right.global_position).x
		assert_that(left_x * right_x).is_less(0.0)

	var base := wheel.basis
	(car as VehiclePhysics)._steer_input = -0.7
	rig.call("_process", 1.0 / 60.0)
	var spin := _recover_steer_spin(base, wheel.basis)
	assert_float(spin).is_equal_approx(-0.7 * CockpitRig.STEER_VISUAL_MAX_RAD_CABIN, 0.0001)
	assert_that(wheel.basis.y).is_equal_approx(base.y, Vector3(0.0001, 0.0001, 0.0001))

func _recover_steer_spin(base: Basis, current: Basis) -> float:
	var rel := base.transposed() * current
	return atan2(rel.z.x, rel.x.x)

## P4: the twin-screen centre stack plus every console control — carbon patch,
## metallic shift surround with R/N/D blocks, red start button and ring, the
## Display Command rotary — and every console mesh stays shadowless.
func test_r35_centre_stack_has_twin_screens_and_console_controls() -> void:
	var root := _new_root()
	var cockpit := (load(R35_COCKPIT) as PackedScene).instantiate() as Node3D
	_managed.append(cockpit)
	root.add_child(cockpit)

	assert_that(cockpit.get_node_or_null("GaugeMFD/MFDScreen")).is_not_null()
	assert_that(cockpit.get_node_or_null("NavScreen")).is_not_null()

	var console := cockpit.get_node_or_null("CentreConsole")
	assert_that(console).is_not_null()
	if console == null:
		return
	for node_name: String in [
		"ConsolePatch", "ShiftSurround", "ShiftInset",
		"SelectorR", "SelectorN", "SelectorD",
		"StartButton", "StartButtonRing", "DisplayCommandDial",
	]:
		assert_that(console.get_node_or_null(node_name)).is_not_null()

	# R / N / D read left-to-right along the console (+X = car-left in eye space).
	var selector_r := console.get_node("SelectorR") as Node3D
	var selector_n := console.get_node("SelectorN") as Node3D
	var selector_d := console.get_node("SelectorD") as Node3D
	assert_that(selector_r.position.x).is_less(selector_n.position.x)
	assert_that(selector_n.position.x).is_less(selector_d.position.x)

	for node: Node in console.find_children("*", "MeshInstance3D", true, false):
		assert_that((node as MeshInstance3D).cast_shadow).is_equal(
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)

## P4: both screens are emissive StandardMaterial3D quads and the subtree ships
## no dynamic light and no SubViewport — the quality-ladder Low-preset contract.
func test_r35_screens_are_emissive_and_the_subtree_is_light_free() -> void:
	var root := _new_root()
	var cockpit := (load(R35_COCKPIT) as PackedScene).instantiate() as Node3D
	_managed.append(cockpit)
	root.add_child(cockpit)

	assert_that(cockpit.find_children("*", "OmniLight3D", true, false)).is_empty()
	assert_that(cockpit.find_children("*", "SpotLight3D", true, false)).is_empty()
	assert_that(cockpit.find_children("*", "DirectionalLight3D", true, false)).is_empty()
	assert_that(cockpit.find_children("*", "SubViewport", true, false)).is_empty()
	assert_that(cockpit.find_children("*", "SubViewportContainer", true, false)).is_empty()

	for screen_name: String in ["MFDScreen", "NavScreen"]:
		var screen := cockpit.find_child(screen_name, true, false) as MeshInstance3D
		assert_that(screen).is_not_null()
		if screen == null:
			continue
		var prim := screen.mesh as PrimitiveMesh
		assert_that(prim).is_not_null()
		if prim == null:
			continue
		var mat := prim.material as StandardMaterial3D
		assert_that(mat).is_not_null()
		if mat == null:
			continue
		assert_that(mat.emission_enabled).is_true()
		assert_float(mat.emission_energy_multiplier).is_greater(0.0)

## P4: set_mfd_mode swaps ONLY the MFD's emissive colour (its isolated material
## copy) — the nav screen and the shift light keep their own emission — and mode
## 0 restores the authored colour exactly.
func test_r35_set_mfd_mode_changes_only_the_mfd_emission() -> void:
	var root := _new_root()
	var car := _new_r35_car(root)
	var rig := car.get_node_or_null("CockpitRig") as CockpitRig
	assert_that(rig).is_not_null()

	var mfd := rig.get_mfd_material()
	assert_that(mfd).is_not_null()
	if mfd == null:
		return
	var mfd_base: Color = mfd.emission

	var shift := rig.get_shift_material()
	var shift_base: Color = shift.emission if shift != null else Color.BLACK
	var nav := rig.find_child("NavScreen", true, false) as MeshInstance3D
	var nav_mat: StandardMaterial3D = null
	if nav != null:
		var nav_prim := nav.mesh as PrimitiveMesh
		if nav_prim != null:
			nav_mat = nav_prim.material as StandardMaterial3D
	assert_that(nav_mat).is_not_null()
	if nav_mat == null:
		return
	var nav_base: Color = nav_mat.emission

	rig.set_mfd_mode(1)
	assert_that(mfd.emission.is_equal_approx(mfd_base)).is_false()
	if shift != null:
		assert_that(shift.emission).is_equal(shift_base)
	assert_that(nav_mat.emission).is_equal(nav_base)

	rig.set_mfd_mode(0)
	assert_that(mfd.emission).is_equal(mfd_base)

## P5: the R35 .tres carries the three cockpit seat overrides — the real-car
## driver eye relative to the exterior GLB (height 1.08 above the ground plane,
## 0.18 m AFT of mid-wheelbase => forward -0.18, lateral -0.36 on car-local -X)
## — and the shared helper reads them, negative forward included.
func test_r35_config_carries_cockpit_seat_overrides() -> void:
	var cfg := load(R35_CONFIG) as CarConfig
	assert_that(cfg).is_not_null()
	if cfg == null:
		return
	assert_float(cfg.cockpit_seat_height).is_equal_approx(1.08, 0.0001)
	assert_float(cfg.cockpit_seat_forward).is_equal_approx(-0.18, 0.0001)
	assert_float(cfg.cockpit_seat_lateral).is_equal_approx(-0.36, 0.0001)

	var seat := CockpitRig.seat_anchor_for(cfg, 0.55, 0.55)
	assert_that(seat).is_equal(Vector3(1.08, -0.18, -0.36))

## P5: cockpit_camera.get_seat_anchor() includes the RHD lateral term
##   UP*height - forward*carZ + lateral*carX
## and the rig glues to exactly the same eye (Sec 4.4's single source).
func test_cockpit_camera_and_rig_share_the_rhd_lateral_anchor() -> void:
	var root := _new_root()
	var car := _new_r35_car(root)
	# PlayerCarController._ready() swaps car.config for the garage's active car
	# after CockpitRig has already loaded the R35 interior; re-assert it so the
	# LIVE config genuinely carries the overrides the anchor math reads.
	car.set("config", load(R35_CONFIG) as CarConfig)
	var rig := car.get_node_or_null("CockpitRig") as CockpitRig
	assert_that(rig).is_not_null()

	var cam := CockpitCameraScript.new() as Node3D
	cam.name = "CockpitCamera"
	_managed.append(cam)
	cam.set("target", car)
	root.add_child(cam)

	var anchor: Vector3 = cam.call("get_seat_anchor")
	var expected: Vector3 = car.global_position + Vector3.UP * 1.08 \
		- car.global_basis.z * -0.18 + car.global_basis.x * -0.36
	assert_that(anchor).is_equal_approx(expected, Vector3(0.0001, 0.0001, 0.0001))
	assert_float(anchor.x).is_equal_approx(car.global_position.x - 0.36, 0.0001)

	rig.call("_sync_to_seat_anchor")
	assert_that(rig.global_position).is_equal_approx(anchor, Vector3(0.0001, 0.0001, 0.0001))

## P5: raising cockpit_seat_height moves the camera eye, the rig and SeatRoot by
## the SAME delta — eye and interior stay glued through the shared helper.
func test_seat_height_delta_moves_camera_rig_and_seat_root_together() -> void:
	var root := _new_root()
	var car := _new_r35_car(root) as VehiclePhysics
	# Give this car its OWN config copy so the height override below can never
	# leak into the shared .tres cache (PlayerCarController._ready already
	# swapped car.config for the garage's active car on tree entry).
	var cfg := car.config.duplicate(true) as CarConfig
	car.config = cfg

	var rig := car.get_node_or_null("CockpitRig") as CockpitRig
	assert_that(rig).is_not_null()
	if rig == null:
		return
	var seat_root := rig.find_child("SeatRoot", true, false) as Node3D
	assert_that(seat_root).is_not_null()
	if seat_root == null:
		return

	var cam := CockpitCameraScript.new() as Node3D
	cam.name = "CockpitCamera"
	_managed.append(cam)
	cam.set("target", car)
	cam.set("debug_speed_kmh", 0.0)
	root.add_child(cam)

	rig.call("_sync_to_seat_anchor")
	cam.call("_update_camera", 1.0 / 60.0)
	var cam_before := cam.global_position
	var rig_before := rig.global_position
	var seat_before := seat_root.global_position

	cfg.cockpit_seat_height = 0.65
	rig.call("_sync_to_seat_anchor")
	cam.call("_update_camera", 1.0 / 60.0)

	var expected := car.global_basis.y * 0.1
	var cam_delta := cam.global_position - cam_before
	var rig_delta := rig.global_position - rig_before
	var seat_delta := seat_root.global_position - seat_before
	assert_that(cam_delta).is_equal_approx(expected, Vector3(0.0001, 0.0001, 0.0001))
	assert_that(rig_delta).is_equal_approx(cam_delta, Vector3(0.0001, 0.0001, 0.0001))
	assert_that(seat_delta).is_equal_approx(cam_delta, Vector3(0.0001, 0.0001, 0.0001))

## P5: a target without cockpit overrides keeps the exact F2a 0.55/0.55 anchor
## (lateral defaults 0) — test_cockpit_camera's math, unchanged.
func test_seat_anchor_without_overrides_keeps_zero_lateral() -> void:
	var root := _new_root()
	var target := Node3D.new()
	_managed.append(target)
	root.add_child(target)

	var cam := CockpitCameraScript.new() as Node3D
	_managed.append(cam)
	cam.set("target", target)
	root.add_child(cam)

	var anchor: Vector3 = cam.call("get_seat_anchor")
	var expected: Vector3 = target.global_position + Vector3.UP * 0.55 \
		- target.global_basis.z * 0.55
	assert_that(anchor).is_equal_approx(expected, Vector3(0.000001, 0.000001, 0.000001))

	var seat := CockpitRig.seat_anchor_for(null, 0.55, 0.55)
	assert_that(seat).is_equal(Vector3(0.55, 0.55, 0.0))
