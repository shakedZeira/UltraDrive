# tests/suites/test_drive_feel.gd
extends GdUnitTestSuite

## Item 9 gate: the drive-feel presentation trio. BodyRig is a pure additive
## pitch/roll rig (clamp targets to the plan's ± values, lerp the pose toward
## them, settle back to rest); %SpeedOverlay draws a vignette whose opacity is
## a monotonic pure function of player speed (anchored in hud.tscn); TireMarks
## pool handbrake quads under the rear axle with a hard mark cap and a lifetime
## (headless-culled so behaviour is asserted without a renderer). Plus the two
## compatibility contracts: chase transients stay OFF in the script default
## (test_chase_camera.gd already asserts that) but both player world scenes flip
## them ON, and vehicle_physics exposes a cheap handbrake reader for the marks.

const HUD_SCENE := "res://scenes/ui/hud.tscn"
const OPEN_WORLD_SCENE := "res://scenes/world/open_world_root.tscn"
const MOUNTAIN_PASS_SCENE := "res://scenes/track/mountain_pass.tscn"
const ChaseCameraScript: GDScript = preload("res://scripts/camera/chase_camera.gd")

var _managed: Array = []

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	for node in _managed:
		if is_instance_valid(node):
			node.free()
	_managed.clear()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

func _new_rig() -> BodyRig:
	var rig := BodyRig.new()
	_managed.append(rig)
	return rig

func _new_marks() -> TireMarks:
	var marks := TireMarks.new()
	_managed.append(marks)
	return marks

func test_body_rig_idle_rests_at_zero_pose() -> void:
	var rig := _new_rig()
	assert_that(rig.get_pitch_deg()).is_equal(0.0)
	assert_that(rig.get_roll_deg()).is_equal(0.0)
	assert_that(rig.get_target_pitch_deg()).is_equal(0.0)
	assert_that(rig.get_target_roll_deg()).is_equal(0.0)
	assert_that(rig.is_settled()).is_true()
	assert_that(rig.rotation).is_equal(Vector3.ZERO)

func test_body_rig_pitch_targets_accel_negative_brake_positive() -> void:
	var rig := _new_rig()
	rig.set_targets(1.0, 0.0, 0.0)
	assert_that(rig.get_target_pitch_deg()).is_equal(BodyRig.PITCH_ACCEL_DEG)
	rig.set_targets(0.0, 1.0, 0.0)
	assert_that(rig.get_target_pitch_deg()).is_equal(BodyRig.PITCH_BRAKE_DEG)

func test_body_rig_roll_targets_clamp_to_steer_extremes() -> void:
	var rig := _new_rig()
	rig.set_targets(0.0, 0.0, 1.0)
	assert_that(rig.get_target_roll_deg()).is_equal(BodyRig.ROLL_MAX_DEG)
	rig.set_targets(0.0, 0.0, -1.0)
	assert_that(rig.get_target_roll_deg()).is_equal(-BodyRig.ROLL_MAX_DEG)

func test_body_rig_targets_are_hard_clamped() -> void:
	var rig := _new_rig()
	rig.set_targets(2.0, 2.0, 5.0)
	assert_that(rig.get_target_pitch_deg()).is_greater_equal(BodyRig.PITCH_ACCEL_DEG)
	assert_that(rig.get_target_pitch_deg()).is_less_equal(BodyRig.PITCH_BRAKE_DEG)
	assert_that(rig.get_target_roll_deg()).is_less_equal(BodyRig.ROLL_MAX_DEG)
	assert_that(rig.get_target_roll_deg()).is_greater_equal(-BodyRig.ROLL_MAX_DEG)
	rig.set_targets(-3.0, 0.0, -5.0)
	assert_that(rig.get_target_pitch_deg()).is_greater_equal(BodyRig.PITCH_ACCEL_DEG)
	assert_that(rig.get_target_roll_deg()).is_greater_equal(-BodyRig.ROLL_MAX_DEG)

func test_body_rig_steps_toward_target_but_stays_within_bounds() -> void:
	var rig := _new_rig()
	rig.set_targets(1.0, 0.0, 1.0)
	for i in range(90):
		rig.step(1.0 / 60.0)
	assert_that(rig.get_pitch_deg()).is_less(0.0)
	assert_that(rig.get_pitch_deg()).is_greater(BodyRig.PITCH_ACCEL_DEG - 0.5)
	assert_that(rig.get_roll_deg()).is_greater(0.0)
	assert_that(rig.get_roll_deg()).is_less(BodyRig.ROLL_MAX_DEG + 0.5)
	assert_that(rig.get_pitch_deg()).is_less_equal(BodyRig.PITCH_BRAKE_DEG)
	assert_that(rig.get_roll_deg()).is_less_equal(BodyRig.ROLL_MAX_DEG)

func test_body_rig_settles_back_to_rest() -> void:
	var rig := _new_rig()
	rig.set_targets(1.0, 0.0, 1.0)
	for i in range(60):
		rig.step(1.0 / 60.0)
	assert_that(rig.is_settled()).is_false()
	rig.set_targets(0.0, 0.0, 0.0)
	for i in range(120):
		rig.step(1.0 / 60.0)
	assert_that(rig.is_settled()).is_true()
	assert_that(rig.get_pitch_deg()).is_between(-0.1, 0.1)
	assert_that(rig.get_roll_deg()).is_between(-0.1, 0.1)

func test_vignette_intensity_is_monotonic_with_speed() -> void:
	var prev := 0.0
	for kmh in range(0, 261, 10):
		var intensity := SpeedOverlay.vignette_intensity(float(kmh))
		assert_that(intensity).is_greater_equal(prev)
		assert_that(intensity).is_less_equal(1.0)
		prev = intensity

func test_vignette_intensity_zero_at_rest_full_at_high_speed() -> void:
	assert_that(SpeedOverlay.vignette_intensity(0.0)).is_equal(0.0)
	assert_that(SpeedOverlay.vignette_intensity(-5.0)).is_equal(0.0)
	assert_that(SpeedOverlay.vignette_intensity(SpeedOverlay.FULL_SPEED_KMH)).is_equal(1.0)
	assert_that(SpeedOverlay.vignette_intensity(400.0)).is_equal(1.0)

func test_speed_overlay_instance_mirrors_speed_input() -> void:
	var overlay := SpeedOverlay.new()
	_managed.append(overlay)
	overlay.set_speed_kmh(110.0)
	assert_that(overlay.get_speed_kmh()).is_equal(110.0)
	assert_that(overlay.get_intensity()).is_equal_approx(0.5, 0.001)
	overlay.set_speed_kmh(0.0)
	assert_that(overlay.get_intensity()).is_equal(0.0)
	overlay.set_speed_kmh(-20.0)
	assert_that(overlay.get_intensity()).is_equal(0.0)

func test_hud_scene_has_unique_speed_overlay_node() -> void:
	var runner := scene_runner(HUD_SCENE)
	await runner.simulate_frames(2)
	var overlay := runner.scene().get_node("Root/SpeedOverlay") as SpeedOverlay
	assert_that(overlay).is_not_null()
	if overlay == null:
		return
	assert_that(overlay.get_node("%SpeedOverlay")).is_not_null()
	assert_that(overlay.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)

func test_tire_marks_headless_ready_culls_the_mesh_pool() -> void:
	var marks := _new_marks()
	add_child(marks)
	assert_that(marks.get_child_count()).is_equal(0)
	assert_that(marks.mark_cap()).is_greater(0)

func test_tire_marks_spawn_while_handbraked_at_speed() -> void:
	var marks := _new_marks()
	assert_that(marks.is_marking()).is_false()
	marks.update(1.0, true, 60.0)
	assert_that(marks.is_marking()).is_true()
	assert_that(marks.active_mark_count()).is_greater(0)

func test_tire_marks_do_not_spawn_without_handbrake_or_speed() -> void:
	var marks := _new_marks()
	marks.update(1.0, false, 60.0)
	assert_that(marks.is_marking()).is_false()
	assert_that(marks.active_mark_count()).is_equal(0)
	marks.update(1.0, true, TireMarks.MIN_SPEED_KMH - 1.0)
	assert_that(marks.is_marking()).is_false()
	assert_that(marks.active_mark_count()).is_equal(0)

func test_tire_marks_spawn_loop_never_exceeds_the_mark_cap() -> void:
	var marks := _new_marks()
	var peek := 0
	for i in range(800):
		marks.update(0.12, true, 60.0)
		peek = maxi(peek, marks.active_mark_count())
		assert_that(marks.active_mark_count()).is_less_equal(marks.mark_cap())
	assert_that(peek).is_greater(0)

func test_tire_marks_natural_population_fits_under_the_cap() -> void:
	assert_that(TireMarks.MARK_COUNT_CAP).is_greater_equal(int(TireMarks.MARK_LIFETIME / TireMarks.MARK_SPAWN_INTERVAL))

func test_tire_marks_despawn_within_lifetime() -> void:
	var marks := _new_marks()
	marks.update(0.5, true, 60.0)
	assert_that(marks.active_mark_count()).is_greater(0)
	for i in range(int(ceil(TireMarks.MARK_LIFETIME / 0.5)) + 1):
		marks.update(0.5, false, 0.0)
	assert_that(marks.active_mark_count()).is_equal(0)
	assert_that(marks.is_marking()).is_false()

func test_vehicle_physics_exposes_handbrake_read() -> void:
	var car := VehiclePhysics.new()
	_managed.append(car)
	assert_that(car.get_handbrake()).is_false()

func test_chase_camera_script_default_stays_transients_off() -> void:
	var cam := ChaseCameraScript.new() as Node3D
	_managed.append(cam)
	assert_that(cam.get("transients_enabled")).is_false()

func test_player_world_scenes_enable_chase_transients_by_default() -> void:
	for path in [OPEN_WORLD_SCENE, MOUNTAIN_PASS_SCENE]:
		var scene: PackedScene = load(path)
		assert_that(scene).is_not_null()
		if scene == null:
			continue
		var root := scene.instantiate()
		_managed.append(root)
		var cam := root.get_node_or_null("ChaseCamera")
		assert_that(cam).is_not_null()
		if cam != null:
			assert_that(cam.get("transients_enabled")).is_true()