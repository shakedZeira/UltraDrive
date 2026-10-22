# tests/suites/test_exhaust_backfire.gd
extends GdUnitTestSuite

## Exhaust backfire VFX gate: flames spawn at the exhaust tip positions when a
## pop is fired, the pool is bounded and recycled, nothing shows while the engine
## is off, loudness scales the flame, and the node frees cleanly with its car.
## Headless-safe (MeshInstance3D / OmniLight3D only, no GPUParticles3D) and no
## wall-clock assertions: time is advanced by calling _process(delta) directly.

var _nodes: Array = []


## Minimal stand-in for VehiclePhysics: only the get_drive_info seam the
## backfire node reads.
class StubCar:
	extends Node3D
	var rpm: float = 0.0

	func get_drive_info() -> Dictionary:
		return {"rpm": rpm}


func after_test() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()


## A bare Node3D "car" with `tip_count` Marker3D tips (names ExhaustTip*), the
## backfire node and the engine forced on. Returns [car, backfire].
func _make_car(tip_count: int) -> Array:
	var car := Node3D.new()
	add_child(car)
	_nodes.append(car)
	for i in range(tip_count):
		var m := Marker3D.new()
		m.name = "ExhaustTip%d" % i
		m.position = Vector3(-0.3 + 0.2 * float(i), 0.3, 2.2)
		car.add_child(m)
	var bf := ExhaustBackfire.new()
	bf.engine_state_override = 1
	car.add_child(bf)
	return [car, bf]


## Appends a closed box (8 verts, 12 tris) spanning x0..x1, 0.2..0.3, z0..z1.
func _add_box(verts: PackedVector3Array, idx: PackedInt32Array, x0: float, x1: float, z0: float, z1: float) -> void:
	var b := verts.size()
	var corners: Array[Vector3] = [
		Vector3(x0, 0.2, z0), Vector3(x1, 0.2, z0), Vector3(x1, 0.3, z0), Vector3(x0, 0.3, z0),
		Vector3(x0, 0.2, z1), Vector3(x1, 0.2, z1), Vector3(x1, 0.3, z1), Vector3(x0, 0.3, z1)]
	for c in corners:
		verts.append(c)
	var faces: Array[PackedInt32Array] = [
		PackedInt32Array([0, 1, 2]), PackedInt32Array([0, 2, 3]), PackedInt32Array([4, 6, 5]), PackedInt32Array([4, 7, 6]),
		PackedInt32Array([0, 4, 5]), PackedInt32Array([0, 5, 1]), PackedInt32Array([3, 2, 6]), PackedInt32Array([3, 6, 7]),
		PackedInt32Array([1, 5, 6]), PackedInt32Array([1, 6, 2]), PackedInt32Array([0, 3, 7]), PackedInt32Array([0, 7, 4])]
	for f in faces:
		idx.append(b + f[0])
		idx.append(b + f[1])
		idx.append(b + f[2])


func _mesh_of(verts: PackedVector3Array, idx: PackedInt32Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func test_marker_tips_are_found_in_car_space() -> void:
	var parts := _make_car(4)
	var bf := parts[1] as ExhaustBackfire
	assert_that(bf.tip_count()).is_equal(4)
	var tips := bf.tip_positions()
	assert_that(tips[0].is_equal_approx(Vector3(-0.3, 0.3, 2.2))).is_true()
	assert_that(tips[3].is_equal_approx(Vector3(0.3, 0.3, 2.2))).is_true()


func test_car_without_markers_falls_back_to_a_rear_pair() -> void:
	var car := Node3D.new()
	add_child(car)
	_nodes.append(car)
	var bf := ExhaustBackfire.new()
	bf.engine_state_override = 1
	car.add_child(bf)
	assert_that(bf.tip_count()).is_equal(2)
	var tips := bf.tip_positions()
	assert_float(tips[0].x).is_less(0.0)
	assert_float(tips[1].x).is_greater(0.0)
	assert_float(tips[0].z).is_greater(1.0)
	assert_that(bf.trigger_pop(1.0)).is_equal(2)


func test_cluster_tips_splits_touching_tubes_and_finds_rear_ends() -> void:
	# Four boxes with a 0.015 gap in X, like the R35 quad tips.
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	_add_box(verts, idx, -0.814, -0.694, 2.20, 2.30)
	_add_box(verts, idx, -0.674, -0.554, 2.21, 2.31)
	_add_box(verts, idx, 0.554, 0.674, 2.21, 2.31)
	_add_box(verts, idx, 0.694, 0.814, 2.20, 2.30)
	var tips := ExhaustBackfire.cluster_tips(_mesh_of(verts, idx), Transform3D.IDENTITY)
	assert_that(tips.size()).is_equal(4)
	assert_float(tips[0].x).is_equal_approx(-0.754, 0.002)
	assert_float(tips[1].x).is_equal_approx(-0.614, 0.002)
	assert_float(tips[3].z).is_equal_approx(2.30, 0.002)
	assert_float(tips[2].z).is_equal_approx(2.31, 0.002)


func test_tip_mesh_in_car_tree_is_discovered() -> void:
	var car := Node3D.new()
	add_child(car)
	_nodes.append(car)
	var body := Node3D.new()
	body.name = "CarBody"
	car.add_child(body)
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	_add_box(verts, idx, -0.45, -0.35, 2.0, 2.2)
	_add_box(verts, idx, 0.35, 0.45, 2.0, 2.2)
	var mi := MeshInstance3D.new()
	mi.name = "Exhaust_Tips"
	mi.mesh = _mesh_of(verts, idx)
	body.add_child(mi)
	var bf := ExhaustBackfire.new()
	bf.engine_state_override = 1
	car.add_child(bf)
	assert_that(bf.tip_count()).is_equal(2)
	assert_float(bf.tip_positions()[1].z).is_equal_approx(2.2, 0.002)


func test_loud_pop_spawns_one_flame_per_tip_at_the_tip_positions() -> void:
	var parts := _make_car(4)
	var bf := parts[1] as ExhaustBackfire
	var spawned := bf.trigger_pop(1.0)
	assert_that(spawned).is_equal(4)
	assert_that(bf.active_flame_count()).is_equal(4)
	var tips := bf.tip_positions()
	var flames := bf.active_flame_positions()
	for t in tips:
		var hit := false
		for f in flames:
			if f.distance_to(t) < 0.05:
				hit = true
		assert_that(hit).is_true()
	assert_that(bf.active_ember_count()).is_greater(0)
	assert_that(bf.light_node()).is_not_null()


func test_single_tip_index_lights_only_that_tip() -> void:
	var parts := _make_car(4)
	var bf := parts[1] as ExhaustBackfire
	assert_that(bf.trigger_pop(0.5, 2)).is_equal(1)
	assert_that(bf.active_flame_count()).is_equal(1)
	assert_float(bf.active_flame_positions()[0].distance_to(bf.tip_positions()[2])).is_less(0.05)


func test_no_flame_when_engine_is_off() -> void:
	var parts := _make_car(4)
	var bf := parts[1] as ExhaustBackfire
	bf.engine_state_override = 0
	assert_that(bf.trigger_pop(1.0)).is_equal(0)
	bf.trigger_burst(1.0, 6, 0.5)
	assert_that(bf.pending_count()).is_equal(0)
	assert_that(bf.active_flame_count()).is_equal(0)
	assert_that(bf.active_ember_count()).is_equal(0)


func test_car_reporting_zero_rpm_counts_as_engine_off() -> void:
	var car := StubCar.new()
	add_child(car)
	_nodes.append(car)
	var bf := ExhaustBackfire.new()
	car.add_child(bf)
	assert_that(bf.engine_running()).is_false()
	assert_that(bf.trigger_pop(1.0)).is_equal(0)
	assert_that(bf.active_flame_count()).is_equal(0)
	car.rpm = 3000.0
	assert_that(bf.engine_running()).is_true()
	assert_that(bf.trigger_pop(1.0)).is_greater(0)


func test_pending_burst_is_dropped_when_engine_dies() -> void:
	var parts := _make_car(2)
	var bf := parts[1] as ExhaustBackfire
	bf.trigger_burst(1.0, 8, 0.8)
	assert_that(bf.pending_count()).is_greater(0)
	bf.engine_state_override = 0
	bf._process(0.01)
	assert_that(bf.pending_count()).is_equal(0)


func test_flames_expire_and_light_goes_dark() -> void:
	var parts := _make_car(4)
	var bf := parts[1] as ExhaustBackfire
	bf.trigger_pop(1.0)
	bf._process(0.016)
	assert_that(bf.light_node().visible).is_true()
	assert_float(bf.light_node().light_energy).is_greater(0.0)
	for i in range(12):
		bf._process(0.016)
	assert_that(bf.active_flame_count()).is_equal(0)
	assert_that(bf.light_node().visible).is_false()
	for i in range(40):
		bf._process(0.016)
	assert_that(bf.active_ember_count()).is_equal(0)
	assert_that(bf.light_node().visible).is_false()


func test_flame_duration_stays_inside_the_60_to_150_ms_window() -> void:
	var parts := _make_car(1)
	var bf := parts[1] as ExhaustBackfire
	bf.trigger_pop(1.0)
	var steps := 0
	while bf.active_flame_count() > 0 and steps < 100:
		bf._process(0.01)
		steps += 1
	# 10 ms steps: gone no earlier than ~50 ms and no later than ~170 ms.
	assert_that(steps).is_between(5, 17)


func test_louder_pops_make_longer_flames() -> void:
	var parts := _make_car(1)
	var bf := parts[1] as ExhaustBackfire
	var soft := bf.spawn_flame(0, 0.2)
	var soft_len := bf._flames[soft].transform.basis.z.length()
	bf._process(1.0)
	var loud := bf.spawn_flame(0, 1.0)
	var loud_len := bf._flames[loud].transform.basis.z.length()
	assert_float(loud_len).is_greater(soft_len)
	assert_float(loud_len).is_less(1.3)
	assert_float(soft_len).is_greater(0.2)


func test_pool_is_bounded_and_recycled_under_spam() -> void:
	var parts := _make_car(4)
	var bf := parts[1] as ExhaustBackfire
	bf.trigger_pop(1.0)
	var children_before := bf.get_child_count()
	for i in range(300):
		bf.trigger_pop(1.0)
		bf.trigger_burst(1.0, 24, 0.9)
		if i % 3 == 0:
			bf._process(0.016)
	assert_that(bf.get_child_count()).is_equal(children_before)
	assert_that(bf.pool_flame_count()).is_equal(ExhaustBackfire.MAX_FLAMES)
	assert_that(bf.pool_ember_count()).is_equal(ExhaustBackfire.MAX_EMBERS)
	assert_that(bf.active_flame_count()).is_less_equal(ExhaustBackfire.MAX_FLAMES)
	assert_that(bf.pending_count()).is_less_equal(ExhaustBackfire.MAX_PENDING)


func test_burst_schedules_pops_over_time() -> void:
	var parts := _make_car(2)
	var bf := parts[1] as ExhaustBackfire
	bf.trigger_burst(1.0, 9, 0.9)
	var scheduled := bf.pending_count()
	assert_that(scheduled).is_between(2, 9)
	for i in range(80):
		bf._process(0.016)
	assert_that(bf.pending_count()).is_equal(0)
	assert_that(bf.pops_fired()).is_equal(scheduled)


func test_audio_signal_handler_and_pop_player_start_fire_flames() -> void:
	var parts := _make_car(4)
	var bf := parts[1] as ExhaustBackfire
	bf._on_audio_pop(1.0)
	assert_that(bf.active_flame_count()).is_greater(0)
	for i in range(30):
		bf._process(0.016)
	var player := AudioStreamPlayer3D.new()
	_nodes.append(player)
	player.stream = EngineAudio.build_pop_burst("bang", 0.9, 1.0, 22050, 7)
	player.volume_db = -6.0
	bf._on_pop_player_started(player)
	assert_that(bf.pending_count()).is_greater(0)
	bf._process(0.0)
	assert_that(bf.pops_fired()).is_greater(1)
	assert_that(bf.active_flame_count()).is_greater(0)


func test_silent_pop_does_nothing() -> void:
	var parts := _make_car(4)
	var bf := parts[1] as ExhaustBackfire
	assert_that(bf.trigger_pop(0.0)).is_equal(0)
	assert_that(bf.active_flame_count()).is_equal(0)


func test_freeing_the_car_frees_the_whole_pool() -> void:
	var parts := _make_car(4)
	var car := parts[0] as Node3D
	var bf := parts[1] as ExhaustBackfire
	bf.trigger_pop(1.0)
	var light := bf.light_node()
	car.free()
	_nodes.clear()
	assert_that(is_instance_valid(bf)).is_false()
	assert_that(is_instance_valid(light)).is_false()


func test_player_scene_wires_the_node_without_particles() -> void:
	var car := (load("res://scenes/vehicle/player_car.tscn") as PackedScene).instantiate()
	add_child(car)
	_nodes.append(car)
	var bf := car.get_node_or_null("ExhaustBackfire") as ExhaustBackfire
	assert_that(bf).is_not_null()
	assert_that(car.find_children("*", "GPUParticles3D", true, false).size()).is_equal(0)
	# No visual loaded in the bare scene: falls back to the rear pair.
	assert_that(bf.tip_count()).is_equal(2)
