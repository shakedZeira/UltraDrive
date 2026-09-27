# tests/suites/test_photo_mode.gd
extends GdUnitTestSuite

## AAA-3 acceptance gate: Photo Mode freezes the world (tree pause), hides the
## HUD layer and hands the viewport to the orbit camera; enter()/exit() round-trip
## restores all three exactly. FOV/aperture/filter sliders clamp and read back
## through get_photo_params(), free orbit reuses the orbit camera's own math and
## keeps the photo FOV pinned, and the screenshot exporter is headless-guarded
## (no render path, no file writes under the gdUnit gate). Map-side: the POI
## registry categorizes every entry into exactly {landmarks, events,
## collectibles}, the bucket and region/travel pure filters are exact, and
## world_map's _rebuild gates its POI dot set through set_category_filters +
## the injected travel gate. The collectibles bucket is the speed-trap fix:
## all eight traps are on the map by default, in the shared family red, at a
## larger pin radius than a landmark, and hiding the events layer cannot hide
## them.

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

## Gate #2 core: every registered POI belongs to exactly one of the three
## categories. Exhaustive and disjoint. The collectibles bucket is the
## speed-trap fix: a collectible is gameplay, not a calendar entry, so it can
## never be filtered away together with the events.
func test_poi_categories_are_exhaustive_and_disjoint() -> void:
	var all_ids: Array = POIRegistry.get_poi_ids()
	var buckets: Dictionary = POIRegistry.category_buckets()
	var landmarks: Array = buckets[POIRegistry.CATEGORY_LANDMARKS]
	var events: Array = buckets[POIRegistry.CATEGORY_EVENTS]
	var collectibles: Array = buckets[POIRegistry.CATEGORY_COLLECTIBLES]
	assert_that(all_ids.size()).is_greater(5)
	assert_that(landmarks.size()).is_equal(5)
	assert_that(collectibles.size()).is_greater(0)
	assert_that(landmarks.size() + events.size() + collectibles.size()).is_equal(all_ids.size())
	for poi_id in all_ids:
		var poi := POIRegistry.get_poi(poi_id)
		# The id is a fast path only: classification must agree with it and with
		# the entry itself, so the two can never disagree.
		var by_entry: String = POIRegistry.category_of(poi, poi_id)
		assert_that(by_entry).is_equal(POIRegistry.category_of(poi))
		if Collectibles.is_collectible_id(poi_id):
			assert_that(by_entry).is_equal(POIRegistry.CATEGORY_COLLECTIBLES)
		elif poi.has("kind"):
			assert_that(by_entry).is_equal(POIRegistry.CATEGORY_EVENTS)
		else:
			assert_that(by_entry).is_equal(POIRegistry.CATEGORY_LANDMARKS)

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
	assert_that(both.size()).is_less(POIRegistry.get_poi_ids().size())
	# The collectibles bucket is the boards/traps/photo spots on their own, and
	# every id in it really is one.
	var only_collectibles: Dictionary = POIRegistry.filter_by_category(
		[POIRegistry.CATEGORY_COLLECTIBLES])
	assert_that(only_collectibles.size()).is_greater(0)
	for poi_id in only_collectibles.keys():
		assert_that(Collectibles.is_collectible_id(poi_id)).is_true()
	var every: Dictionary = POIRegistry.filter_by_category([
		POIRegistry.CATEGORY_LANDMARKS,
		POIRegistry.CATEGORY_EVENTS,
		POIRegistry.CATEGORY_COLLECTIBLES,
	])
	assert_that(every.size()).is_equal(POIRegistry.get_poi_ids().size())

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
	world_map.reset_category_filters()
	world_map.call("_rebuild")
	var reset_size := (world_map.get("_poi_entries") as Array).size()
	assert_that(reset_size).is_equal(POIRegistry.get_poi_ids().size())

# ---------------------------------------------------------------------------
# Speed traps on the pause map: the whole family, in the family colour, and never
# hidden by the events layer.
# ---------------------------------------------------------------------------

## A world map over a real road network, because _rebuild() only collects POIs
## when a road source exists (that is what keeps the map roadless on circuits).
func _new_world_map(root: Node) -> WorldMap:
	var network := RoadNetwork.new()
	network.name = "FilterNetwork"
	network.add_road([Vector3(0.0, 0.0, 0.0), Vector3(100.0, 0.0, 0.0), Vector3(100.0, 0.0, 100.0), Vector3(0.0, 0.0, 100.0)])
	root.add_child(network)
	var world_map := WorldMapScript.new() as WorldMap
	world_map.name = "TrapMap"
	world_map.size = Vector2(512.0, 512.0)
	root.add_child(world_map)
	return world_map

## The authored speed traps, read from the SAME placement the registry merges,
## so this gate can never drift from the shipped set.
func _speed_trap_ids() -> Array[String]:
	var placed: Dictionary = Collectibles.place_data(
		CorridorPlanner.plan(CorridorPlanner.MASTER_SEED, Callable(), {}))
	return Collectibles.ids_of_kind(placed, Collectibles.KIND_SPEED_TRAP)

## Every one of the eight speed traps is on the map by default, projected inside
## the map rect, and drawn in the shared family red at a pin radius LARGER than a
## landmark's. A gameplay target that is easy to miss on the pause map is a target
## that is easy to miss in the world, so the dot set and the colour/radius
## contract are asserted together.
func test_world_map_draws_every_speed_trap_in_the_shared_family_red() -> void:
	var root := _new_root()
	var world_map := _new_world_map(root)
	world_map.call("_rebuild")
	var ids: Array[String] = world_map.poi_entry_ids()
	var trap_ids := _speed_trap_ids()
	assert_array(trap_ids).has_size(8)
	for trap_id in trap_ids:
		assert_array(ids).contains([trap_id])

	# Every collectible family draws its own palette colour, so a trap never comes
	# out in the road-tier colour of the corridor it happens to sit on.
	var rect := Rect2(Vector2.ZERO, world_map.size)
	var seen := 0
	for entry in (world_map.get("_poi_entries") as Array):
		var poi: Dictionary = (entry as Dictionary)["poi"]
		var poi_id := str(poi.get("id", ""))
		if not Collectibles.is_collectible_id(poi_id):
			continue
		seen += 1
		var expected: Color = Collectibles.KIND_DOT_COLOR[str(poi.get("kind", ""))]
		assert_that(world_map.poi_dot_color(poi)).is_equal(expected)
		var screen: Vector2 = (entry as Dictionary)["screen"]
		assert_that(rect.has_point(screen)).is_true()
	assert_that(seen).is_equal(28)

	# A collectible pin outranks a landmark pin in size, and the trap red is the
	# loud of the three (red channel dominant), never a road-blue or moss-green.
	assert_that(WorldMap.COLLECTIBLE_RADIUS).is_greater(WorldMap.POI_RADIUS)
	var red: Color = Collectibles.KIND_DOT_COLOR[Collectibles.KIND_SPEED_TRAP]
	assert_that(red.r).is_greater(red.g)
	assert_that(red.r).is_greater(red.b)

## Hiding the CALENDAR must not hide a gameplay target: collectibles carry their
## own always-on category, so events-off drops the time attacks while every
## landmark and all eight traps survive. Only the explicit collectibles gate
## removes them -- and because that gate is its own flag, it leaves the
## calendar alone -- and the shipped reset brings them back.
func test_world_map_keeps_speed_traps_when_the_events_layer_is_hidden() -> void:
	var root := _new_root()
	var world_map := _new_world_map(root)
	var trap_ids := _speed_trap_ids()

	world_map.set_category_filters({"events": false})
	world_map.call("_rebuild")
	var ids: Array[String] = world_map.poi_entry_ids()
	assert_array(ids).not_contains(["time_attack_0"])
	assert_array(ids).contains(["festival_hub"])
	for trap_id in trap_ids:
		assert_array(ids).contains([trap_id])

	# The collectibles gate is its OWN flag, so hiding the family must not take
	# the calendar with it. set_category_filters is a PARTIAL update by design
	# (reset_category_filters is the all-on reset), so the events layer this test
	# hid in the block above is switched back on in the same call: with it still
	# hidden the time-attack assertion below would only restate the events gate.
	world_map.set_category_filters({"events": true, "collectibles": false})
	world_map.call("_rebuild")
	ids = world_map.poi_entry_ids()
	for trap_id in trap_ids:
		assert_array(ids).not_contains([trap_id])
	assert_array(ids).contains(["time_attack_0"])

	world_map.reset_category_filters()
	world_map.call("_rebuild")
	ids = world_map.poi_entry_ids()
	for trap_id in trap_ids:
		assert_array(ids).contains([trap_id])

# ---------------------------------------------------------------------------
# POI identity: a drawn dot must be able to name itself.
# ---------------------------------------------------------------------------

## The map resolves the POI it is drawing from the id INSIDE the entry --
## poi_entry_ids(), the collectible family palette and the claimed dimming all
## read poi["id"], because the draw pass holds entries, not keys. The base
## landmarks and the event markers never carried one (only the collectibles did,
## from Collectibles._entry), so those dots reached the map as empty ids: named
## by nobody, addressable by no id-keyed gate, and indistinguishable from each
## other. The registry stamps each key into its own entry, which is what makes
## every dot addressable again -- pinned here for all three families at once.
func test_every_drawn_poi_carries_its_own_registry_id() -> void:
	var root := _new_root()
	var world_map := _new_world_map(root)
	world_map.call("_rebuild")
	var ids: Array[String] = world_map.poi_entry_ids()

	# One dot per registered POI, each under its own name, and never twice.
	assert_that(ids.size()).is_equal(POIRegistry.get_poi_ids().size())
	var drawn := {}
	for poi_id in ids:
		assert_that(poi_id).is_not_empty()
		assert_that(drawn.has(poi_id)).is_false()
		drawn[poi_id] = true
	for poi_id in POIRegistry.get_poi_ids():
		assert_that(drawn.has(str(poi_id))).is_true()

	# The two families that regressed are named explicitly.
	assert_array(ids).contains(["festival_hub"])
	assert_array(ids).contains(["time_attack_0"])
	# And the entry alone classifies: the map's fast path and the entry agree.
	for entry in (world_map.get("_poi_entries") as Array):
		var poi: Dictionary = (entry as Dictionary)["poi"]
		var poi_id := str(poi.get("id", ""))
		assert_that(POIRegistry.category_of(poi)).is_equal(POIRegistry.category_of(poi, poi_id))
