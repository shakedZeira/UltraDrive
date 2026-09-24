# tests/suites/test_photo_mode.gd
extends GdUnitTestSuite

## AAA-3 acceptance gate: Photo Mode freezes the world (tree pause), hides the
## HUD layer and hands the viewport to the orbit camera; enter()/exit() round-trip
## restores all three exactly. FOV/aperture/filter sliders clamp and read back
## through get_photo_params(), free orbit reuses the orbit camera's own math and
## keeps the photo FOV pinned, and the screenshot exporter is headless-guarded
## (no render path, no file writes under the gdUnit gate). Map-side: the POI
## registry categorizes every entry into exactly {landmarks, events}, the bucket
## and region/travel pure filters are exact, and world_map's _rebuild gates its
## POI dot set through set_category_filters + the injected travel gate.

const PhotoModeScript: GDScript = preload("res://scripts/ui/photo_mode.gd")
const ChaseCameraScript: GDScript = preload("res://scripts/camera/chase_camera.gd")
const OrbitCameraScript: GDScript = preload("res://scripts/camera/orbit_camera.gd")
const WorldMapScript: GDScript = preload("res://scripts/ui/world_map.gd")

var _managed: Array = []

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	# Photo tests pause the tree in enter(); always force it back so the runner
	# and the next test never inherit a frozen world.
	get_tree().paused = false
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

## Photo rig: target -> chase "ChaseCamera" -> orbit "OrbitCamera" (chase path
## wired, so the orbit starts in CHASE like the real car) + CanvasLayer "HUD".
func _rig_photo(root: Node, position: Vector3) -> Dictionary:
	var target := _new_target(root, position)
	var chase := ChaseCameraScript.new() as Node3D
	chase.name = "ChaseCamera"
	chase.set("target", target)
	root.add_child(chase)
	_managed.append(chase)
	var orbit := OrbitCameraScript.new() as Node3D
	orbit.name = "OrbitCamera"
	orbit.set("target", target)
	orbit.set("chase_camera_path", NodePath("../ChaseCamera"))
	root.add_child(orbit)
	_managed.append(orbit)
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	root.add_child(hud)
	_managed.append(hud)
	var photo: PhotoMode = PhotoModeScript.new()
	photo.name = "PhotoMode"
	root.add_child(photo)
	_managed.append(photo)
	photo.set_orbit_camera(orbit)
	return {"target": target, "chase": chase, "orbit": orbit, "hud": hud, "photo": photo}

## Gate #1: enter/exit restores camera + HUD visibility (and the pause state).
func test_photo_round_trip_restores_camera_hud_and_pause() -> void:
	var rig := _rig_photo(_new_root(), Vector3.ZERO)
	var photo: PhotoMode = rig["photo"]
	var chase: Node3D = rig["chase"]
	var orbit: Node3D = rig["orbit"]
	var hud: CanvasLayer = rig["hud"]
	var orbit_cam := orbit.get("_camera") as Camera3D

	assert_that(photo.is_active()).is_false()
	assert_that(photo.enter()).is_true()
	assert_that(get_tree().paused).is_true()
	assert_that(hud.visible).is_false()
	assert_that(orbit_cam.is_current()).is_true()
	assert_that(chase.call("is_current_view")).is_false()

	assert_that(photo.exit()).is_true()
	assert_that(get_tree().paused).is_false()
	assert_that(hud.visible).is_true()
	assert_that(orbit_cam.is_current()).is_false()
	assert_that(chase.call("is_current_view")).is_true()
	assert_that(photo.is_active()).is_false()

## Photo mode is a strict no-op (no state touched) without an orbit camera, and
## enter/exit are idempotent while already in their respective state.
func test_photo_enter_requires_orbit_and_is_idempotent() -> void:
	var root := _new_root()
	var photo: PhotoMode = PhotoModeScript.new()
	photo.name = "PhotoMode"
	root.add_child(photo)
	_managed.append(photo)

	assert_that(photo.enter()).is_false()  # no orbit anywhere in the tree
	assert_that(get_tree().paused).is_false()

	var rig := _rig_photo(root, Vector3.ZERO)
	var orbit: Node3D = rig["orbit"]
	photo.set_orbit_camera(orbit)
	assert_that(photo.enter()).is_true()
	assert_that(photo.enter()).is_false()  # already active
	assert_that(photo.is_active()).is_true()
	assert_that(photo.exit()).is_true()
	assert_that(photo.exit()).is_false()  # already exited
	assert_that(photo.is_active()).is_false()

## FOV/aperture/filter sliders clamp into their canonical ranges and read back
## through get_photo_params() exactly like the F5 settings knobs. FOV maps the
## photo range [55, 100] onto the orbit camera; filters paint the ColorRect.
func test_photo_fov_aperture_filter_sliders() -> void:
	var rig := _rig_photo(_new_root(), Vector3.ZERO)
	var photo: PhotoMode = rig["photo"]
	var orbit: Node3D = rig["orbit"]
	var orbit_cam := orbit.get("_camera") as Camera3D

	assert_that(photo.enter()).is_true()
	photo.set_fov_strength(0.0)
	assert_that(orbit_cam.fov).is_equal(PhotoModeScript.FOV_MIN)
	photo.set_fov_strength(1.0)
	assert_that(orbit_cam.fov).is_equal(PhotoModeScript.FOV_MAX)
	photo.set_fov_strength(0.5)
	assert_float(orbit_cam.fov).is_equal_approx(
		lerpf(PhotoModeScript.FOV_MIN, PhotoModeScript.FOV_MAX, 0.5), 0.001)
	photo.set_fov_strength(3.0)  # clamps to 1.0
	assert_that(photo.get_photo_params()["fov_strength"]).is_equal(1.0)
	photo.set_fov_strength(-1.0)  # clamps to 0.0
	assert_that(photo.get_photo_params()["fov_strength"]).is_equal(0.0)

	photo.set_aperture(22.0)
	assert_that(photo.get_photo_params()["aperture"]).is_equal(PhotoModeScript.APERTURE_MAX)
	photo.set_aperture(0.5)
	assert_that(photo.get_photo_params()["aperture"]).is_equal(PhotoModeScript.APERTURE_MIN)
	photo.set_aperture(5.5)
	assert_float(photo.get_photo_params()["aperture"]).is_equal_approx(5.5, 0.001)

	photo.set_filter("warm")
	assert_that(photo.get_photo_params()["filter"]).is_equal("warm")
	assert_that(photo.get_filter_overlay()).is_not_null()
	if photo.get_filter_overlay() != null:
		assert_that(photo.get_filter_overlay().color).is_equal(PhotoModeScript.FILTERS["warm"])
	assert_that(photo.is_filter_overlay_visible()).is_true()
	photo.set_filter("cool")
	if photo.get_filter_overlay() != null:
		assert_that(photo.get_filter_overlay().color).is_equal(PhotoModeScript.FILTERS["cool"])
	photo.set_filter("nonsense")  # falls back to "none"
	assert_that(photo.get_photo_params()["filter"]).is_equal(PhotoModeScript.DEFAULT_FILTER)
	assert_that(photo.is_filter_overlay_visible()).is_false()

	assert_that(photo.exit()).is_true()

## Gate #3 core: while free-orbit ticks yaw/pitch (clamped), the orbit camera
## stays current and the photo FOV beat is re-pinned every tick.
func test_photo_free_orbit_pins_fov_and_keeps_camera_current() -> void:
	var rig := _rig_photo(_new_root(), Vector3.ZERO)
	var photo: PhotoMode = rig["photo"]
	var orbit: Node3D = rig["orbit"]
	var orbit_cam := orbit.get("_camera") as Camera3D

	var yaw0 := float(orbit.get("yaw"))
	var pitch0 := float(orbit.get("pitch"))
	var pitch_min := float(orbit.get("pitch_min"))
	var pitch_max := float(orbit.get("pitch_max"))
	assert_that(photo.enter()).is_true()
	photo.orbit_delta(0.5, -0.2, 1.0 / 60.0)
	assert_float(float(orbit.get("yaw"))).is_equal_approx(yaw0 + 0.5, 0.001)
	# The rig's orbit sits at the world origin, so _preserve_orbit_angles can
	# leave pitch above pitch_max; the delta must apply AND clamp in that case.
	assert_float(float(orbit.get("pitch"))).is_equal_approx(
		clampf(pitch0 - 0.2, pitch_min, pitch_max), 0.001)
	photo.orbit_delta(0.0, 50.0, 1.0 / 60.0)  # slammed up -> clamped to pitch_max
	assert_float(float(orbit.get("pitch"))).is_equal_approx(pitch_max, 0.001)

	photo.set_fov_strength(0.25)
	var pinned := lerpf(PhotoModeScript.FOV_MIN, PhotoModeScript.FOV_MAX, 0.25)
	photo.orbit_delta(0.1, 0.1, 1.0 / 60.0)
	assert_float(orbit_cam.fov).is_equal_approx(pinned, 0.001)
	assert_that(orbit_cam.is_current()).is_true()
	assert_that(photo.exit()).is_true()

## Gate #3: the screenshot exporter writes PNGs only outside headless mode; under
## the gdUnit gate it resolves to written=false without any render-path call.
func test_photo_screenshot_headless_guard() -> void:
	var root := _new_root()
	var photo: PhotoMode = PhotoModeScript.new()
	photo.name = "PhotoMode"
	root.add_child(photo)
	_managed.append(photo)

	assert_that(PhotoModeScript.build_screenshot_path(3)).is_equal("user://screenshots/ultradrive_003.png")
	assert_that(PhotoModeScript.build_screenshot_path(-1)).is_equal("user://screenshots/ultradrive_000.png")
	if photo.is_headless():
		var shot: Dictionary = photo.capture_screenshot(2)
		assert_that(shot["written"]).is_false()
		assert_that(str(shot["reason"])).is_equal("headless")
		assert_that(str(shot["path"])).is_equal("")
	else:
		var shot: Dictionary = photo.capture_screenshot(2)
		assert_that(shot["written"]).is_true()
		if bool(shot["written"]):
			var written_path := str(shot["path"])
			assert_that(written_path).is_not_empty()
			DirAccess.remove_absolute(ProjectSettings.globalize_path(written_path))

## Gate #2 core: every registered POI belongs to exactly one category ג€” the base
## five landmarks vs the event markers (kind-keyed) ג€” exhaustive and disjoint.
func test_poi_categories_are_exhaustive_and_disjoint() -> void:
	var all_ids: Array = POIRegistry.get_poi_ids()
	var buckets: Dictionary = POIRegistry.category_buckets()
	var landmarks: Array = buckets[POIRegistry.CATEGORY_LANDMARKS]
	var events: Array = buckets[POIRegistry.CATEGORY_EVENTS]
	assert_that(all_ids.size()).is_greater(5)
	assert_that(landmarks.size()).is_equal(5)
	assert_that(events.size()).is_equal(all_ids.size() - 5)
	for poi_id in all_ids:
		var poi := POIRegistry.get_poi(poi_id)
		var category: String = POIRegistry.category_of(poi)
		if poi.has("kind"):
			assert_that(category).is_equal(POIRegistry.CATEGORY_EVENTS)
		else:
			assert_that(category).is_equal(POIRegistry.CATEGORY_LANDMARKS)

## filter_by_category keeps exactly the requested categories (and nothing else).
func test_poi_filter_by_category_is_exact() -> void:
	var only_landmarks: Dictionary = POIRegistry.filter_by_category(
		[POIRegistry.CATEGORY_LANDMARKS])
	assert_that(only_landmarks.size()).is_equal(5)
	for poi_id in only_landmarks.keys():
		var category: String = POIRegistry.category_of(only_landmarks[poi_id])
		assert_that(category).is_equal(POIRegistry.CATEGORY_LANDMARKS)
	var both: Dictionary = POIRegistry.filter_by_category(
		[POIRegistry.CATEGORY_LANDMARKS, POIRegistry.CATEGORY_EVENTS])
	assert_that(both.size()).is_equal(POIRegistry.get_poi_ids().size())

## Region matching is a case-insensitive substring on the stage name, and the
## travel predicate honours an injected gate (empty gate = everyone is eligible).
func test_poi_region_and_travel_filters() -> void:
	assert_that(POIRegistry.matches_region(POIRegistry.get_poi("alpine_overlook"), "alpine")).is_true()
	assert_that(POIRegistry.matches_region(POIRegistry.get_poi("dry_lake"), "alpine")).is_false()
	assert_that(POIRegistry.matches_region(POIRegistry.get_poi("pass_entry"), "")).is_true()
	var alpine := POIRegistry.filter_by_region(
		POIRegistry.filter_by_category([POIRegistry.CATEGORY_LANDMARKS]), "alpine")
	assert_that(alpine.size()).is_equal(1)
	assert_that(alpine.has("alpine_overlook")).is_true()

	assert_that(POIRegistry.is_travel_eligible("alpine_overlook", Callable())).is_true()
	assert_that(POIRegistry.is_travel_eligible("alpine_overlook",
		func(id: String) -> bool: return id == "alpine_overlook")).is_true()
	assert_that(POIRegistry.is_travel_eligible("dry_lake",
		func(id: String) -> bool: return id == "alpine_overlook")).is_false()

## world_map's _rebuild gates its POI dot set through the AAA-3 filter flags:
## all-on draws every POI; landmarks-off drops the base five; a region substring
## keeps exactly the matching dot; the travel gate funnels to eligible ids.
func test_world_map_filters_gate_poi_dots() -> void:
	var root := _new_root()
	var network := RoadNetwork.new()
	network.name = "FilterNetwork"
	network.add_road([Vector3(0.0, 0.0, 0.0), Vector3(100.0, 0.0, 0.0), Vector3(100.0, 0.0, 100.0), Vector3(0.0, 0.0, 100.0)])
	root.add_child(network)
	var world_map := WorldMapScript.new() as Control
	world_map.name = "FilterMap"
	world_map.size = Vector2(512.0, 512.0)
	root.add_child(world_map)

	world_map.call("_rebuild")
	var all_entries: Array = world_map.get("_poi_entries")
	assert_that(all_entries.size()).is_equal(POIRegistry.get_poi_ids().size())

	world_map.set_category_filters({"landmarks": false})
	world_map.call("_rebuild")
	for entry in (world_map.get("_poi_entries") as Array):
		var poi: Dictionary = (entry as Dictionary)["poi"]
		assert_that(POIRegistry.category_of(poi)).is_not_equal(POIRegistry.CATEGORY_LANDMARKS)

	world_map.set_category_filters({"landmarks": true, "region": "alpine"})
	world_map.call("_rebuild")
	var region_entries: Array = world_map.get("_poi_entries")
	assert_that(region_entries.size()).is_equal(1)
	if region_entries.size() == 1:
		var poi: Dictionary = (region_entries[0] as Dictionary)["poi"]
		assert_that(str(poi["name"])).is_equal("Alpine Overlook")

	world_map.set_travel_gate(func(id: String) -> bool: return id == "alpine_overlook")
	world_map.set_category_filters({"travel": true, "region": ""})
	world_map.call("_rebuild")
	var travel_entries: Array = world_map.get("_poi_entries")
	assert_that(travel_entries.size()).is_equal(1)

	world_map.set_travel_gate(Callable())
	world_map.set_category_filters({})  # back to shipped all-on defaults
	world_map.call("_rebuild")
	var reset_size := (world_map.get("_poi_entries") as Array).size()
	assert_that(reset_size).is_equal(POIRegistry.get_poi_ids().size())
