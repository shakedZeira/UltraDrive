# tests/suites/test_cockpit_hud.gd
extends GdUnitTestSuite

## F4 cockpit-HUD gate: the dash-as-HUD readout panel mirrors the SAME drive
## feed race_ui.gd uses — car.get_drive_info()'s speed_kmh / gear / rpm, read
## only and NaN-safe — while the CockpitCamera owns the viewport; the
## "subtract cluster" HUD-dim toggle moderates the %Cluster canvas opacity in
## cockpit mode and restores it otherwise; the dash panel is OPTIONAL (ACC
## dash-removal seam); and the optional virtual rear-view mirror (SubViewport +
## ViewportTexture, UPDATE_WHEN_PARENT_VISIBLE, off by default) builds its
## viewport texture once with no leak. A SceneRunner frame test covers the real
## player scene end-to-end. Best-effort glass gate: hud.tscn ships no forced
## windshield tint/tint overlay in the cockpit paths.

const HUD_SCENE: PackedScene = preload("res://scenes/ui/hud.tscn")
const MIRROR_SCENE: PackedScene = preload("res://scenes/ui/rear_view_mirror.tscn")
const CAR_SCENE: PackedScene = preload("res://scenes/vehicle/player_car.tscn")
const CockpitCameraScript: GDScript = preload("res://scripts/camera/cockpit_camera.gd")

const TEST_TRACK_SCENE := "res://scenes/test/test_track.tscn"

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

func _new_cockpit_camera(root: Node, name: String = "CockpitCamera") -> Node3D:
	var cam := CockpitCameraScript.new() as Node3D
	cam.name = name
	_managed.append(cam)
	root.add_child(cam)
	return cam

func _new_hud(root: Node) -> Node:
	var hud := HUD_SCENE.instantiate()
	_managed.append(hud)
	root.add_child(hud)
	return hud

func _new_player_car(root: Node) -> VehiclePhysics:
	var car := CAR_SCENE.instantiate() as VehiclePhysics
	_managed.append(car)
	root.add_child(car)
	# Deterministic feed: the vehicle's physics step recomputes current_speed_kmh
	# from linear_velocity (vehicle_physics.gd:422), so stop simulation so the
	# injected speed/gear/rpm survive until the dash reads get_drive_info().
	car.set_simulation_enabled(false)
	return car

func _wait_for_dash() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func _set_drive_values(car: VehiclePhysics, speed_kmh: float, gear: int, rpm: float) -> void:
	car.current_speed_kmh = speed_kmh
	car._drivetrain.engine_rpm = rpm
	car._drivetrain.current_gear = gear

## Gate 1: the cockpit dash mirrors the SAME get_drive_info feed race_ui.gd
## drives the screen cluster from — speed_kmh / gear / rpm, read-only — into
## the panel text while the CockpitCamera owns the viewport, and never emits
## "nan"/"inf" for a non-finite drive value.
func test_cockpit_dash_reads_drive_info_into_text_no_nan() -> void:
	var root := _new_root()
	var cam := _new_cockpit_camera(root)
	cam.call("set_view_active", true)
	var hud := _new_hud(root)
	var car := _new_player_car(root)
	_set_drive_values(car, 88.7, 3, 4210.0)
	await get_tree().process_frame

	var dash := hud.get_node("CockpitDash") as CockpitDash
	assert_that(dash).is_not_null()
	if dash == null:
		return
	assert_that(dash.sync_cockpit_mode()).is_true()
	await _wait_for_dash()
	assert_that(dash.panel.visible).is_true()
	assert_that(dash.speed_label.text).is_equal("89")
	assert_that(dash.rpm_label.text).is_equal("4210")
	assert_that(dash.gear_label.text).is_equal("3")

	# Reverse gear renders "R", matching the tachometer convention.
	_set_drive_values(car, -8.0, -1, 900.0)
	await _wait_for_dash()
	assert_that(dash.gear_label.text).is_equal("R")

	# NaN / inf from the physics must never reach the UI as "nan".
	car.current_speed_kmh = NAN
	car._drivetrain.engine_rpm = INF
	await _wait_for_dash()
	assert_that(dash.speed_label.text).is_equal("0")
	assert_that(dash.rpm_label.text).is_equal("0")
	for label in [dash.speed_label.text, dash.rpm_label.text, dash.gear_label.text]:
		assert_that(label.contains("nan")).is_false()

## Gate 2: the HUD-dim toggle moderates the %Cluster canvas opacity exactly in
## cockpit mode and restores full opacity the moment the cockpit camera loses
## the viewport (or the player toggles the dim off).
func test_hud_dim_toggle_toggles_cluster_opacity() -> void:
	var root := _new_root()
	var cam := _new_cockpit_camera(root)
	cam.call("set_view_active", true)
	var hud := _new_hud(root)
	await _wait_for_dash()

	var cluster := hud.get_node("Root/Cluster") as Control
	assert_that(cluster).is_not_null()
	var dash := hud.get_node("CockpitDash") as CockpitDash
	assert_that(cluster.modulate.a).is_equal_approx(0.2, 0.0001)

	# The toggle: dim off keeps the cluster full even in cockpit mode.
	dash.set_hud_dim_enabled(false)
	assert_that(cluster.modulate.a).is_equal_approx(1.0, 0.0001)
	dash.set_hud_dim_enabled(true)
	assert_that(cluster.modulate.a).is_equal_approx(0.2, 0.0001)

	# Leaving cockpit mode (any other camera) restores the cluster to full.
	cam.call("set_view_active", false)
	await _wait_for_dash()
	assert_that(cluster.modulate.a).is_equal_approx(1.0, 0.0001)

## Gate 3: the dash panel is OPTIONAL — the ACC dash-removal seam hides the
## readout panel in cockpit mode without touching the F2a rig geometry, while
## the cluster dim stays independent.
func test_dash_hud_optionality_toggle_hides_panel_only() -> void:
	var root := _new_root()
	var cam := _new_cockpit_camera(root)
	cam.call("set_view_active", true)
	var hud := _new_hud(root)
	var car := _new_player_car(root)
	_set_drive_values(car, 60.0, 2, 3000.0)
	await _wait_for_dash()

	var dash := hud.get_node("CockpitDash") as CockpitDash
	assert_that(dash.get_dash_hud_enabled()).is_true()
	assert_that(dash.panel.visible).is_true()

	dash.set_dash_hud_enabled(false)
	assert_that(dash.panel.visible).is_false()
	# The cluster dim is a separate toggle: still dimmed while hidden.
	var cluster := hud.get_node("Root/Cluster") as Control
	assert_that(cluster.modulate.a).is_equal_approx(0.2, 0.0001)

	dash.set_dash_hud_enabled(true)
	assert_that(dash.panel.visible).is_true()

## Gate 4: without a cockpit camera (or with one that does not own the view)
## the dash panel stays hidden and the cluster is untouched — the chase-only
## test_vehicle_physics clone keeps its clean HUD.
func test_dash_hidden_without_cockpit_camera_and_cluster_full() -> void:
	var root := _new_root()
	var hud := _new_hud(root)
	var car := _new_player_car(root)
	_set_drive_values(car, 55.0, 4, 2500.0)
	await _wait_for_dash()

	var dash := hud.get_node("CockpitDash") as CockpitDash
	assert_that(dash.sync_cockpit_mode()).is_false()
	assert_that(dash.panel.visible).is_false()
	var cluster := hud.get_node("Root/Cluster") as Control
	assert_that(cluster.modulate.a).is_equal_approx(1.0, 0.0001)

	# A cockpit camera that does not own the viewport behaves the same.
	var cam := _new_cockpit_camera(root)
	await _wait_for_dash()
	assert_that(dash.sync_cockpit_mode()).is_false()
	assert_that(dash.panel.visible).is_false()
	assert_that(cluster.modulate.a).is_equal_approx(1.0, 0.0001)

## Gate 5: the mirror is DISABLED BY DEFAULT — no SubViewport is ever built and
## the panel stays hidden until cockpit mode. The hud.tscn instance carries the
## mirror already-off (F5 can drive mirror_enabled later without editing HUD).
func test_mirror_disabled_by_default_builds_no_viewport() -> void:
	var root := _new_root()
	var hud := _new_hud(root)
	var mirror := hud.get_node("RearViewMirror") as RearViewMirror
	assert_that(mirror).is_not_null()
	assert_that(mirror.get_mirror_enabled()).is_false()
	assert_that(mirror.is_mirror_built()).is_false()
	assert_that(mirror.get_mirror_viewport()).is_null()
	assert_that(mirror.visible).is_false()
	# owned=false: the runtime-built SubViewport is add_child'd (owner == null),
	# so an owned=true search would never match it — and here none exists at all.
	var subviews := mirror.find_children("*", "SubViewport", false, false)
	assert_that(subviews.is_empty()).is_true()

	var standalone := MIRROR_SCENE.instantiate() as RearViewMirror
	_managed.append(standalone)
	root.add_child(standalone)
	await get_tree().process_frame
	assert_that(standalone.get_mirror_enabled()).is_false()
	assert_that(standalone.is_mirror_built()).is_false()
	standalone.call("sync_visibility")
	assert_that(standalone.visible).is_false()

## Gate 6: when enabled the mirror creates its SubViewport + ViewportTexture
## ONCE (repeat _ensure_mirror calls are no-ops), the display carries the
## texture, and freeing the node leaves nothing behind (the GDUnit orphan count
## catches leaks).
func test_mirror_enabled_creates_viewport_once_no_leak() -> void:
	var root := _new_root()
	var mirror := MIRROR_SCENE.instantiate() as RearViewMirror
	mirror.set("mirror_enabled", true)
	_managed.append(mirror)
	root.add_child(mirror)
	await get_tree().process_frame

	assert_that(mirror.is_mirror_built()).is_true()
	var viewport := mirror.get_mirror_viewport()
	assert_that(viewport).is_not_null()
	assert_that(viewport.size).is_equal(Vector2i(256, 144))
	assert_that(viewport.render_target_update_mode).is_equal(
		SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	)
	assert_that(mirror.get_mirror_camera()).is_not_null()
	var display := mirror.get_node("Frame/Display") as TextureRect
	assert_that(display).is_not_null()
	assert_that(display.texture).is_not_null()

	# Second construction attempt is a no-op: still exactly one SubViewport.
	assert_that(mirror.call("_ensure_mirror")).is_false()
	assert_that(mirror.get_mirror_viewport()).is_same(viewport)
	# owned=false matches the runtime-add_child'd SubViewport (owner == null).
	var subviews := mirror.find_children("*", "SubViewport", false, false)
	assert_that(subviews.size()).is_equal(1)

## Gate 7: the mirror camera sits behind the car (local +Z tail) and looks back
## along the vehicle heading, so the panel mirrors what is genuinely behind.
func test_mirror_camera_aims_behind_car_along_heading() -> void:
	var root := _new_root()
	var car := _new_player_car(root)
	var mirror := MIRROR_SCENE.instantiate() as RearViewMirror
	mirror.set("mirror_enabled", true)
	mirror.set("target", car)
	_managed.append(mirror)
	root.add_child(mirror)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var cam := mirror.get_mirror_camera()
	assert_that(cam).is_not_null()
	if cam == null:
		return
	var dist := cam.global_position.distance_to(car.global_position)
	assert_that(dist).is_greater(1.2)
	assert_that(dist).is_less_equal(2.4)
	# Behind = along the car's local +Z (its rearward axis).
	var from_car := cam.global_position - car.global_position
	assert_that(from_car.dot(car.global_basis.z.normalized())).is_greater(0.5)

## Gate 8 (SceneRunner): the real player scene test_track.tscn runs its HUD,
## and cycling the 4-mode C-cycle into cockpit dims the %Cluster, shows the
## dash with live drive values, and leaves the off-by-default mirror unbuilt.
func test_player_scene_cockpit_cycle_dims_cluster_and_shows_dash() -> void:
	var runner := scene_runner(TEST_TRACK_SCENE)
	await runner.simulate_frames(5)
	var scene := runner.scene()

	var hud := scene.get_node_or_null("HUD")
	assert_that(hud).is_not_null()
	if hud == null:
		return
	var cluster := scene.get_node("HUD/Root/Cluster") as Control
	var dash := hud.get_node("CockpitDash") as CockpitDash
	var mirror := hud.get_node("RearViewMirror") as RearViewMirror
	assert_that(dash).is_not_null()
	assert_that(mirror).is_not_null()
	assert_that(cluster.modulate.a).is_equal_approx(1.0, 0.0001)
	assert_that(dash.panel.visible).is_false()

	var orbit := scene.get_node_or_null("OrbitCamera")
	assert_that(orbit).is_not_null()
	if orbit == null:
		return
	# chase -> orbit -> hood -> cockpit
	for i in range(3):
		orbit.call("cycle_mode_for_test")
	await runner.simulate_frames(4)

	assert_that(cluster.modulate.a).is_equal_approx(0.2, 0.01)
	assert_that(dash.panel.visible).is_true()
	assert_that(dash.speed_label.text.is_empty()).is_false()
	for label in [dash.speed_label.text, dash.rpm_label.text, dash.gear_label.text]:
		assert_that(label.contains("nan")).is_false()
	# The off-by-default mirror is never built, even in cockpit mode.
	assert_that(mirror.is_mirror_built()).is_false()

	# Cycling onward to chase restores the cluster.
	orbit.call("cycle_mode_for_test")
	await runner.simulate_frames(2)
	assert_that(cluster.modulate.a).is_equal_approx(1.0, 0.0001)

## Gate 9 (best-effort glass audit, plan §4 "no fake windshield tint"): the
## cockpit HUD ships no forced full-screen tint/glass filter — the dash panel
## is a translucent panel + text (no ColorRect overlays), and the disabled
## mirror leaks no render layer. Combined with the opaque glass materials on
## the car GLBs (audited separately), cockpit glass stays clean.
func test_cockpit_hud_ships_no_forced_tint_or_glass_filter() -> void:
	var root := _new_root()
	var hud := _new_hud(root)
	var dash := hud.get_node("CockpitDash") as CockpitDash
	var color_rects := dash.find_children("*", "ColorRect", true, false)
	assert_that(color_rects.is_empty()).is_true()
	var mirror := hud.get_node("RearViewMirror") as RearViewMirror
	assert_that(mirror.visible).is_false()
	assert_that(mirror.is_mirror_built()).is_false()