# tests/suites/test_camera_settings.gd
extends GdUnitTestSuite

## F5 accessibility & settings surface gate (XAG-117): the Camera-and-Feel
## knob dict persists through a SaveManager slot round-trip, merges additively
## over canonical defaults, first-boot defaults follow the quality ladder,
## defaults never ship a nausea knob at 1.0 and keep shake/bob/head-motion
## under 0.5, apply_camera_settings lands FOV/shake/bob onto live camera
## scripts via their sync_camera_settings seam (read backs + strength exports),
## motion blur stays off by default (4.7 removed the post-chain property, so
## apply is a guarded no-op), and the settings menu exposes the section without
## a mirror row (mirror is F4 territory, data-only here).

const SettingsMenuScript: GDScript = preload("res://scripts/ui/settings_menu.gd")
const ChaseCameraScript: GDScript = preload("res://scripts/camera/chase_camera.gd")
const OrbitCameraScript: GDScript = preload("res://scripts/camera/orbit_camera.gd")
const HoodCameraScript: GDScript = preload("res://scripts/camera/hood_camera.gd")
const CockpitCameraScript: GDScript = preload("res://scripts/camera/cockpit_camera.gd")
const SettingsMenuScene: PackedScene = preload("res://scenes/ui/settings_menu.tscn")

const ROUND_TRIP_SLOT := 1

var _managed: Array = []

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	for entry in _managed:
		if is_instance_valid(entry):
			entry.free()
	_managed.clear()

func _new_root() -> Node:
	var root := Node.new()
	root.name = "TestRoot"
	_managed.append(root)
	add_child(root)
	return root

func _new_target(root: Node, position: Vector3) -> Node3D:
	var target := Node3D.new()
	target.position = position
	root.add_child(target)
	_managed.append(target)
	return target

func _strength(camera: Node3D, key: String) -> float:
	return float(camera.get(key))

func _camera_fov(camera: Node3D) -> float:
	return (camera.get("_camera") as Camera3D).fov

## Round-trip through the exact additive sub-dict mechanism GameState.restore()
## uses for quality_preset — nothing beyond SaveManager + the merge helper.
func test_camera_settings_round_trip_through_slot() -> void:
	var wanted: Dictionary = SettingsMenuScript.camera_settings_defaults()
	wanted["cockpit_shake"] = 0.2
	wanted["cockpit_lean"] = 0.0
	wanted["camera_fov_cockpit"] = 0.5
	wanted["motion_blur"] = 2
	wanted["mirror_enabled"] = true
	SaveManager.save_game(ROUND_TRIP_SLOT, {SettingsMenuScript.CAMERA_SETTINGS_KEY: wanted})
	var loaded := SaveManager.load_game(ROUND_TRIP_SLOT)
	var restored: Dictionary = SettingsMenuScript.camera_settings_from_save(loaded)
	assert_that(float(restored["cockpit_shake"])).is_equal_approx(0.2, 0.001)
	assert_that(float(restored["cockpit_lean"])).is_equal_approx(0.0, 0.001)
	assert_that(float(restored["camera_fov_cockpit"])).is_equal_approx(0.5, 0.001)
	assert_that(restored["motion_blur"]).is_equal(2)
	assert_that(restored["mirror_enabled"]).is_true()
	# Unpinned keys fall back to the canonical defaults after the round-trip.
	assert_that(float(restored["cockpit_head_motion"])).is_equal_approx(0.4, 0.001)

## Save files are JSON: floats come back as floats but a hand-edited save could
## ship anything; the merge helper clamps every knob into range.
func test_camera_settings_from_save_clamps_out_of_range_values() -> void:
	var hostile := {
		SettingsMenuScript.CAMERA_SETTINGS_KEY: {
			"cockpit_shake": 1.7,
			"cockpit_lean": -0.3,
			"camera_fov_hood": 3.0,
			"motion_blur": 9,
			"mirror_enabled": "false",
		},
	}
	var restored: Dictionary = SettingsMenuScript.camera_settings_from_save(hostile)
	assert_that(float(restored["cockpit_shake"])).is_equal_approx(1.0, 0.001)
	assert_that(float(restored["cockpit_lean"])).is_equal_approx(0.0, 0.001)
	assert_that(float(restored["camera_fov_hood"])).is_equal_approx(1.0, 0.001)
	assert_that(restored["motion_blur"]).is_equal(2)
	assert_that(restored["mirror_enabled"]).is_false()

## XAG-117: nausea defaults ship calmer than the F1 script baselines — shake,
## head-motion and bob default under 0.5, and no knob ever ships at 1.0 unless
## the player opts in. FOV-widen defaults stay 1.0 (shipped speed widening);
## lean rides F1's 0.7.
func test_defaults_satisfy_xag117() -> void:
	var d: Dictionary = SettingsMenuScript.camera_settings_defaults()
	assert_that(float(d["cockpit_shake"])).is_less(0.5)
	assert_that(float(d["cockpit_head_motion"])).is_less(0.5)
	assert_that(float(d["hood_bob"])).is_less(0.5)
	assert_that(float(d["cockpit_lean"])).is_less(1.0)
	assert_that(float(d["cockpit_shake"])).is_not_equal(1.0)
	assert_that(float(d["cockpit_head_motion"])).is_not_equal(1.0)
	assert_that(float(d["hood_bob"])).is_not_equal(1.0)
	assert_that(d["motion_blur"]).is_equal(0)
	assert_that(d["mirror_enabled"]).is_false()

## Quality-preset first-boot defaults (plan §5): shake small on Low/Med (iGPU
## safety), High allowed slightly more; mirror stays OFF at every preset.
func test_quality_preset_defaults_keep_shake_small_and_mirror_off() -> void:
	var low: Dictionary = SettingsMenuScript.camera_settings_for_quality_preset(0)
	var medium: Dictionary = SettingsMenuScript.camera_settings_for_quality_preset(1)
	var high: Dictionary = SettingsMenuScript.camera_settings_for_quality_preset(2)
	for preset in [low, medium, high]:
		assert_that(float(preset["cockpit_shake"])).is_less(0.5)
		assert_that(preset["mirror_enabled"]).is_false()
	assert_that(float(low["cockpit_shake"])).is_equal_approx(float(medium["cockpit_shake"]), 0.001)
	assert_that(float(high["cockpit_shake"])).is_greater_equal(float(low["cockpit_shake"]))
	assert_that(float(high["cockpit_shake"])).is_less(0.5)

## apply_camera_settings must NOP safely on a scene with no cameras (the
## settings menu itself) rather than crashing when find_children finds nothing.
func test_apply_camera_settings_tolerates_null_and_camera_less_root() -> void:
	SettingsMenuScript.apply_camera_settings({}, null)
	var root := _new_root()
	SettingsMenuScript.apply_camera_settings({}, root)
	assert_that(true).is_true()

## Cockpit seam: shake/head-motion/lean/FOV land on the strength exports, the
## lean-coupled look-into-turn follows at 3/7, and a pinned FOV reads back from
## get_cockpit_fov.
func test_apply_syncs_cockpit_exports_and_fov_readback() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)
	var cam := CockpitCameraScript.new() as Node3D
	cam.name = "CockpitCamera"
	cam.set("target", target)
	_managed.append(cam)
	root.add_child(cam)

	var settings: Dictionary = SettingsMenuScript.camera_settings_defaults()
	settings["cockpit_shake"] = 0.1
	settings["cockpit_head_motion"] = 0.2
	settings["cockpit_lean"] = 0.35
	settings["camera_fov_cockpit"] = 0.0
	SettingsMenuScript.apply_camera_settings(settings, root)

	assert_that(_strength(cam, "shake_strength")).is_equal_approx(0.1, 0.001)
	assert_that(_strength(cam, "pitch_strength")).is_equal_approx(0.2, 0.001)
	assert_that(_strength(cam, "steer_lean_strength")).is_equal_approx(0.35, 0.001)
	assert_that(_strength(cam, "look_turn_strength")).is_equal_approx(0.35 * (0.3 / 0.7), 0.001)
	assert_that(_strength(cam, "fov_strength")).is_equal_approx(0.0, 0.001)

	var fov_min: float = float(cam.get("fov_min"))
	cam.set("debug_speed_kmh", 200.0)
	for i in range(120):
		cam.call("_update_camera", 1.0 / 60.0)
	assert_that(_camera_fov(cam)).is_equal_approx(fov_min, 0.001)  # pinned: no widening

	# Re-apply with full FOV-widen: the same camera now climbs toward fov_max.
	var full: Dictionary = SettingsMenuScript.camera_settings_defaults()
	full["camera_fov_cockpit"] = 1.0
	SettingsMenuScript.apply_camera_settings(full, root)
	for i in range(120):
		cam.call("_update_camera", 1.0 / 60.0)
	assert_that(_camera_fov(cam)).is_greater_equal(67.9)

## Hood seam: hood FOV + bob land on bob_strength / fov_strength exports and
## get_hood_fov reads the applied widening back.
func test_apply_syncs_hood_fov_and_bob() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)
	var cam := HoodCameraScript.new() as Node3D
	cam.name = "HoodCamera"
	cam.set("target", target)
	_managed.append(cam)
	root.add_child(cam)

	var settings: Dictionary = SettingsMenuScript.camera_settings_defaults()
	settings["camera_fov_hood"] = 0.0
	settings["hood_bob"] = 0.0
	SettingsMenuScript.apply_camera_settings(settings, root)
	assert_that(_strength(cam, "fov_strength")).is_equal_approx(0.0, 0.001)
	assert_that(_strength(cam, "bob_strength")).is_equal_approx(0.0, 0.001)

	var fov_min: float = float(cam.get("fov_min"))
	cam.set("debug_speed_kmh", 200.0)
	for i in range(120):
		cam.call("_update_camera", 1.0 / 60.0)
	assert_that(_camera_fov(cam)).is_equal_approx(fov_min, 0.001)
	assert_that((cam.call("get_bob_offset") as Vector3).length()).is_equal(0.0)

	var full: Dictionary = SettingsMenuScript.camera_settings_defaults()
	full["camera_fov_hood"] = 1.0
	full["hood_bob"] = 1.0
	SettingsMenuScript.apply_camera_settings(full, root)
	assert_that(_strength(cam, "bob_strength")).is_equal_approx(1.0, 0.001)
	for i in range(120):
		cam.call("_update_camera", 1.0 / 60.0)
	assert_that(cam.call("get_hood_fov")).is_greater_equal(74.9)
	assert_that((cam.call("get_bob_offset") as Vector3).length()).is_greater(0.0)

## Chase + orbit seam: the FOV-widen knob lands on the fov_strength exports and
## sync resets each camera back to fov_min (deterministic readback).
func test_apply_syncs_chase_and_orbit_fov() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)
	for cls in [ChaseCameraScript, OrbitCameraScript]:
		var cam := cls.new() as Node3D
		cam.name = "OrbitCamera" if cls == OrbitCameraScript else "ChaseCamera"
		cam.set("target", target)
		_managed.append(cam)
		root.add_child(cam)

	var settings: Dictionary = SettingsMenuScript.camera_settings_defaults()
	settings["camera_fov_chase"] = 1.0
	settings["camera_fov_orbit"] = 1.0
	SettingsMenuScript.apply_camera_settings(settings, root)
	for node in root.find_children("*", "Node3D", true, false):
		if node.has_method("sync_camera_settings"):
			assert_that(_strength(node as Node3D, "fov_strength")).is_equal_approx(1.0, 0.001)

	var pinned: Dictionary = SettingsMenuScript.camera_settings_defaults()
	pinned["camera_fov_chase"] = 0.0
	pinned["camera_fov_orbit"] = 0.0
	SettingsMenuScript.apply_camera_settings(pinned, root)
	for node in root.find_children("*", "Node3D", true, false):
		if node.has_method("sync_camera_settings"):
			var cam := node as Node3D
			assert_that(_strength(cam, "fov_strength")).is_equal_approx(0.0, 0.001)
			assert_that(_camera_fov(cam)).is_equal_approx(float(cam.get("fov_min")), 0.001)

## Lean-cam off: a zeroed lean knob silences both the roll and the coupled
## look-into-turn yaw hint (F1 composition ratio 0.3/0.7 preserved).
func test_zero_lean_cam_also_silences_look_turn() -> void:
	var root := _new_root()
	var target := _new_target(root, Vector3.ZERO)
	var cam := CockpitCameraScript.new() as Node3D
	cam.name = "CockpitCamera"
	cam.set("target", target)
	_managed.append(cam)
	root.add_child(cam)

	var settings: Dictionary = SettingsMenuScript.camera_settings_defaults()
	settings["cockpit_lean"] = 0.0
	SettingsMenuScript.apply_camera_settings(settings, root)
	assert_that(_strength(cam, "steer_lean_strength")).is_equal_approx(0.0, 0.001)
	assert_that(_strength(cam, "look_turn_strength")).is_equal_approx(0.0, 0.001)

## Motion blur: default Off persists (round-trip) and apply is a guarded,
## no-crash no-op on this engine (4.7 removed the Environment post-chain
## property). forward-compatible: an engine exposing the property gets set.
func test_motion_blur_defaults_off_and_apply_is_safe() -> void:
	var d: Dictionary = SettingsMenuScript.camera_settings_defaults()
	assert_that(d["motion_blur"]).is_equal(0)

	var holder := Node.new()
	holder.name = "Holder"
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	holder.add_child(we)
	_managed.append(holder)

	var on: Dictionary = SettingsMenuScript.camera_settings_defaults()
	on["motion_blur"] = 1
	SettingsMenuScript.apply_camera_settings(on, holder)
	assert_that(true).is_true()  # reached without a script error

	SaveManager.save_game(ROUND_TRIP_SLOT, {SettingsMenuScript.CAMERA_SETTINGS_KEY: on})
	var restored: Dictionary = SettingsMenuScript.camera_settings_from_save(SaveManager.load_game(ROUND_TRIP_SLOT))
	assert_that(restored["motion_blur"]).is_equal(1)

## The menu scene exposes the section with labeled controls for the eight knobs
## + motion blur, and deliberately has NO mirror row (F4 owns mirror budget;
## F5 ships data-only mirror_enabled=false). OptionButton item counts are wired
## by _ready from GameState.
func test_settings_menu_exposes_camera_and_feel_section() -> void:
	var menu := SettingsMenuScene.instantiate() as Control
	_managed.append(menu)
	add_child(menu)
	assert_that(menu.get_node("%CameraFeelHeader")).is_not_null()
	assert_that(menu.get_node("%FOV_ChaseSlider")).is_not_null()
	assert_that(menu.get_node("%FOV_OrbitSlider")).is_not_null()
	assert_that(menu.get_node("%FOV_HoodSlider")).is_not_null()
	assert_that(menu.get_node("%FOV_CockpitSlider")).is_not_null()
	assert_that(menu.get_node("%ShakeSlider")).is_not_null()
	assert_that(menu.get_node("%HeadMotionSlider")).is_not_null()
	assert_that(menu.get_node("%HoodBobSlider")).is_not_null()
	assert_that(menu.get_node("%LeanSlider")).is_not_null()
	assert_that(menu.get_node("%MotionBlurOption")).is_not_null()
	var motion_blur := menu.get_node("%MotionBlurOption") as OptionButton
	assert_that(motion_blur.item_count).is_equal(3)
	var mirror := menu.find_children("*Mirror*", "", true, false)
	assert_that(mirror.size()).is_equal(0)
	# Sliders are configured in 0..1 (nausea knobs capped at full strength).
	var shake := menu.get_node("%ShakeSlider") as HSlider
	assert_that(shake.min_value).is_equal(0.0)
	assert_that(shake.max_value).is_equal(1.0)
	assert_that(shake.step).is_equal(0.05)