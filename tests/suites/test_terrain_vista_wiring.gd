# tests/suites/test_terrain_vista_wiring.gd
extends GdUnitTestSuite

## TerrainVista controller and its open-world wiring: a static Terrain3D (1024
## px regions at 8 m, no collision, no shadows) whose regions are all added
## blank at start, then filled off the main thread one map per frame, nearest
## region first; the live terrain's flat background switched off; the
## open-world cameras get a far plane that reaches the vista while the tracks
## keep 4000.

const SCENE := "res://scenes/world/open_world_root.tscn"

func _await_until(condition: Callable, timeout_s: float) -> bool:
	var loops := int(timeout_s / 0.1)
	for _i in loops:
		if condition.call():
			return true
		await get_tree().create_timer(0.1).timeout
	return condition.call()

func test_vista_builds_static_regions_one_per_frame_nearest_first() -> void:
	var live := Terrain3D.new()
	add_child(live)
	live.region_size = Terrain3D.SIZE_256
	TerrainTexturing.apply(live)
	var vista := TerrainVista.new()
	vista.live_terrain = live
	vista.bake_in_headless = true
	add_child(vista)
	await get_tree().process_frame
	var road: Array[Vector3] = [Vector3(-300.0, 2.0, 1000.0), Vector3(300.0, 2.0, 1000.0)]
	var locs: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(0, 0)]
	assert_that(vista.start([road], Vector3(128.0, 2.0, 128.0), locs)).is_true()
	assert_that(vista.start([road], Vector3(128.0, 2.0, 128.0), locs)).is_false()
	var t := vista.terrain
	assert_that(t).is_not_null()
	assert_that(t.collision_mode).is_equal(0)
	assert_that(t.cast_shadows).is_equal(0)
	assert_that(t.region_size).is_equal(Terrain3D.SIZE_1024)
	assert_that(t.vertex_spacing).is_equal(TerrainVista.VERTEX_SPACING)
	assert_that(t.assets).is_same(live.assets)
	assert_that(t.material.world_background).is_equal(Terrain3DMaterial.WorldBackground.NONE)
	assert_that(live.material.world_background).is_equal(Terrain3DMaterial.WorldBackground.NONE)
	assert_that(t.data.get_region_locations().size()).is_equal(2)
	assert_that(vista.applied_count).is_equal(0)
	var done := await _await_until(func() -> bool: return vista.is_complete(), 120.0)
	assert_that(done).is_true()
	assert_that(vista.apply_order).is_equal([Vector2i(0, 0), Vector2i(-1, 0)] as Array[Vector2i])
	assert_that(vista.max_steps_per_frame).is_equal(1)
	assert_that(vista.apply_frames).is_equal(6)
	var data: Terrain3DData = t.data
	assert_that(data.get_region_locations().size()).is_equal(2)
	assert_that(data.has_regionp(Vector3(4096.0, 0.0, 4096.0))).is_true()
	assert_that(data.has_regionp(Vector3(-4096.0, 0.0, 4096.0))).is_true()
	var h := data.get_height(Vector3(128.0, 0.0, 128.0))
	assert_that(h).is_equal_approx(TerrainBaker.SPAWN_HEIGHT + TerrainVistaBaker.BIAS, 0.05)
	var far_h := data.get_height(Vector3(-2000.0, 0.0, 3000.0))
	var ring_h := TerrainBaker.new().natural_height_at(-2000.0 + 0.5, 3000.0 + 0.5)
	assert_that(absf(far_h - (ring_h + TerrainVistaBaker.BIAS))).is_less(0.5)
	assert_that(live.data.get_region_locations().size()).is_equal(0)
	var color: Image = t.data.get_regionp(Vector3(4096.0, 0.0, 4096.0)).get_map(Terrain3DRegion.TYPE_COLOR)
	assert_that(color.has_mipmaps()).is_true()
	vista.queue_free()
	live.queue_free()

func test_vista_stops_its_thread_when_freed_mid_build() -> void:
	var vista := TerrainVista.new()
	vista.bake_in_headless = true
	add_child(vista)
	await get_tree().process_frame
	assert_that(vista.start([], Vector3.ZERO)).is_true()
	await get_tree().create_timer(0.3).timeout
	remove_child(vista)
	vista.free()
	assert_that(true).is_true()

func test_vista_is_off_in_headless_unless_asked() -> void:
	var vista := TerrainVista.new()
	add_child(vista)
	await get_tree().process_frame
	assert_that(vista.is_enabled()).is_equal(DisplayServer.get_name() != "headless")
	if not vista.is_enabled():
		assert_that(vista.start([], Vector3.ZERO)).is_false()
		assert_that(vista.terrain).is_null()
	vista.queue_free()

func test_open_world_scene_wires_the_vista_and_far_cameras() -> void:
	var packed := load(SCENE) as PackedScene
	var state := packed.get_state()
	var found_vista := false
	var far := {}
	for i in state.get_node_count():
		var name := String(state.get_node_name(i))
		for p in state.get_node_property_count(i):
			var prop := String(state.get_node_property_name(i, p))
			var val: Variant = state.get_node_property_value(i, p)
			if name == "TerrainVista" and prop == "script":
				found_vista = (val as Script).resource_path == "res://scripts/world/terrain_vista.gd"
			if prop == "far_clip":
				far[name] = val
	assert_that(found_vista).is_true()
	for cam in ["ChaseCamera", "OrbitCamera", "HoodCamera", "CockpitCamera"]:
		assert_that(far.get(cam, 0.0)).override_failure_message("%s far_clip" % cam).is_equal(24000.0)

func test_track_cameras_keep_the_default_far_plane() -> void:
	for path in ["res://scripts/camera/chase_camera.gd", "res://scripts/camera/orbit_camera.gd", "res://scripts/camera/hood_camera.gd", "res://scripts/camera/cockpit_camera.gd"]:
		var cam: Node3D = (load(path) as GDScript).new()
		assert_that(cam.get("far_clip")).is_equal(4000.0)
		cam.free()

func test_chase_camera_applies_far_clip() -> void:
	var cam: Node3D = (load("res://scripts/camera/chase_camera.gd") as GDScript).new()
	cam.set("far_clip", 24000.0)
	var target := Node3D.new()
	add_child(target)
	cam.set("target", target)
	add_child(cam)
	await get_tree().process_frame
	var c := cam.get("_camera") as Camera3D
	assert_that(c.far).is_equal(24000.0)
	cam.queue_free()
	target.queue_free()
