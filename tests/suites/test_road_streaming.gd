# tests/suites/test_road_streaming.gd
extends GdUnitTestSuite

## Open-world road streaming (open_world_status.md section 9).
##
## RoadNetwork.stream_geometry cuts the road network into square cells and builds
## only the cells around the car (RoadChunkMesher), instead of one TrackBuilder
## per whole road at load. These tests pin:
##   - exactness: the union of every cell is the road TrackBuilder builds
##     (surface, edge lines, dashes, rails, carriageway + rail collision, same
##     winding), so streaming changes nothing the car or the eye can tell;
##   - seams: neighbouring cells share bit-identical seam vertices;
##   - streaming: cells load around the car, free past the keep radius, the 3x3
##     block under the car exists the moment the car arrives (fast travel), and a
##     car driving the road always has collision under and ahead of it;
##   - the circuits keep the old path (stream_geometry defaults to off);
##   - the open-world scene streams.

const OPEN_WORLD_SCENE := "res://scenes/world/open_world_root.tscn"

var _managed: Array[Node] = []

func after_test() -> void:
	for n in _managed:
		if is_instance_valid(n):
			n.free()
	_managed.clear()

func _keep(n: Node) -> Node:
	_managed.append(n)
	return n

# --- fixtures -----------------------------------------------------------------

## Closed banked ring with rails on both sides.
func _ring_def() -> RoadDef:
	var pts: Array[Vector3] = []
	for i in 120:
		var a := TAU * float(i) / 120.0
		pts.append(Vector3(400.0 + cos(a) * 300.0, 4.0 + sin(a * 3.0) * 6.0, 300.0 + sin(a) * 300.0))
	var def := RoadDef.make(RoadDef.Tier.ARTERIAL, pts, "ring", true, 12.0)
	def.banking = 0.3
	return def

## Open four-lane highway (3 dashed dividers) with a < 0.5 m segment in it
## (TrackBuilder drops that one from the collision strip only).
func _highway_def() -> RoadDef:
	var pts: Array[Vector3] = []
	var x := -200.0
	for i in 60:
		pts.append(Vector3(x, 2.0 + float(i) * 0.3, 40.0 * sin(x * 0.01)))
		x += 17.0 if i != 30 else 0.3
	return RoadDef.make(RoadDef.Tier.HIGHWAY, pts, "hw", false, 24.0)

## Open dirt track (no rails, no dividers, dirt material).
func _dirt_def() -> RoadDef:
	var pts: Array[Vector3] = []
	for i in 40:
		pts.append(Vector3(100.0 + float(i) * 11.0, 1.0, -150.0 + 30.0 * cos(float(i) * 0.2)))
	return RoadDef.make(RoadDef.Tier.DIRT, pts, "dirt", false)

## Mixed asphalt/gravel closed road with a one-side rail suppression range.
func _mixed_def() -> RoadDef:
	var pts: Array[Vector3] = []
	for i in 64:
		var a := TAU * float(i) / 64.0
		pts.append(Vector3(-300.0 + cos(a) * 120.0, 0.5, -300.0 + sin(a) * 90.0))
	var def := RoadDef.make(RoadDef.Tier.ARTERIAL, pts, "mixed", true, 11.0)
	var surf := PackedByteArray()
	surf.resize(64)
	for i in 64:
		surf[i] = RoadDef.Surface.GRAVEL if i >= 20 and i < 34 else RoadDef.Surface.ASPHALT
	def.point_surfaces = surf
	def.rail_open_ranges = [{"side": RoadDef.RailSide.LEFT, "from": 40, "to": 48}]
	return def

func _gaps_for(def: RoadDef) -> Array:
	if def.id == "ring":
		return [{"start": def.points[10], "end": def.points[24]}, {"start": def.points[100], "end": def.points[3]}]
	return []

## TrackBuilder exactly as RoadNetwork builds it (+ configure_rails).
func _full(def: RoadDef, gaps: Array) -> TrackBuilder:
	var b := TrackBuilder.new()
	b.road_width = def.width
	b.build_track(def.points, def.closed, def)
	if not gaps.is_empty():
		b.configure_rails(gaps)
	_keep(b)
	return b

static func _vkey(v: Vector3) -> String:
	return "%.3f,%.3f,%.3f" % [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]

## Ordered triangle keys (winding matters for Jolt) from vertex + index arrays.
static func _tri_keys(v: PackedVector3Array, idx: PackedInt32Array, into: Dictionary) -> void:
	for t in range(0, idx.size(), 3):
		var k := _vkey(v[idx[t]]) + "|" + _vkey(v[idx[t + 1]]) + "|" + _vkey(v[idx[t + 2]])
		into[k] = int(into.get(k, 0)) + 1

static func _face_keys(faces: PackedVector3Array, into: Dictionary) -> void:
	for t in range(0, faces.size(), 3):
		var k := _vkey(faces[t]) + "|" + _vkey(faces[t + 1]) + "|" + _vkey(faces[t + 2])
		into[k] = int(into.get(k, 0)) + 1

## TrackBuilder triangles grouped by kind: surface / edge / divider / rail /
## road collision / rail collision.
func _builder_tris(b: TrackBuilder) -> Dictionary:
	var out := {"surface": {}, "edge": {}, "divider": {}, "rail": {}, "road_coll": {}, "rail_coll": {}}
	for c in b.get_children():
		var n := String(c.name)
		if c is MeshInstance3D:
			var mesh := (c as MeshInstance3D).mesh
			if mesh == null or mesh.get_surface_count() == 0:
				continue
			var arrays := mesh.surface_get_arrays(0)
			var kind := "surface"
			if n.begins_with("RoadEdge"):
				kind = "edge"
			elif n.begins_with("LaneDivider"):
				kind = "divider"
			elif n.begins_with("RoadRail"):
				kind = "rail"
			_tri_keys(arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_INDEX], out[kind])
		elif c is StaticBody3D:
			var shape := (c.get_child(0) as CollisionShape3D).shape as ConcavePolygonShape3D
			_face_keys(shape.get_faces(), out["rail_coll" if n.begins_with("RailCollision") else "road_coll"])
	return out

const _KIND_NAMES := {0: "surface", 1: "edge", 2: "divider", 3: "rail"}

## The same groups from every cell of a chunked build.
func _chunk_tris(def: RoadDef, gaps: Array, cell_size: float) -> Dictionary:
	var out := {"surface": {}, "edge": {}, "divider": {}, "rail": {}, "road_coll": {}, "rail_coll": {}, "cells": 0}
	var table := RoadChunkMesher.prepare_road(0, def, gaps)
	var cells := RoadChunkMesher.cell_segments(table, cell_size)
	out["cells"] = cells.size()
	for cell: Vector2i in cells:
		var r := RoadChunkMesher.build_cell([table], [[0, cells[cell]]])
		var buckets: Dictionary = r["buckets"]
		for key: String in buckets:
			var b: Dictionary = buckets[key]
			_tri_keys(b["v"], b["idx"], out[_KIND_NAMES[int(b["kind"])]])
		_face_keys(r["road_faces"], out["road_coll"])
		_face_keys(r["rail_faces"], out["rail_coll"])
	return out

func _assert_same(full: Dictionary, chunked: Dictionary, label: String) -> void:
	for kind in ["surface", "edge", "divider", "rail", "road_coll", "rail_coll"]:
		var a: Dictionary = full[kind]
		var b: Dictionary = chunked[kind]
		var tri_a := 0
		var tri_b := 0
		for k in a:
			tri_a += int(a[k])
		for k in b:
			tri_b += int(b[k])
		assert_int(tri_b).override_failure_message("%s %s: %d chunk triangles vs %d full" % [label, kind, tri_b, tri_a]).is_equal(tri_a)
		var missing := 0
		for k in a:
			if int(b.get(k, 0)) != int(a[k]):
				missing += 1
		assert_int(missing).override_failure_message("%s %s: %d triangles differ" % [label, kind, missing]).is_equal(0)

# --- exactness ----------------------------------------------------------------

func test_cells_rebuild_the_full_track_builder_road_exactly() -> void:
	for def: RoadDef in [_ring_def(), _highway_def(), _dirt_def(), _mixed_def()]:
		var gaps := _gaps_for(def)
		var full := _builder_tris(_full(def, gaps))
		# Small cells force many seams; a huge cell is the one-chunk case.
		for cell_size in [64.0, 4096.0]:
			var chunked := _chunk_tris(def, gaps, cell_size)
			if cell_size == 64.0:
				assert_int(int(chunked["cells"])).is_greater(3)
			_assert_same(full, chunked, "%s@%d" % [def.id, int(cell_size)])

func test_fixture_roads_exercise_every_geometry_kind() -> void:
	var ring := _builder_tris(_full(_ring_def(), _gaps_for(_ring_def())))
	assert_int((ring["rail_coll"] as Dictionary).size()).is_greater(0)
	assert_int((ring["rail"] as Dictionary).size()).is_greater(0)
	var hw := _builder_tris(_full(_highway_def(), []))
	assert_int((hw["divider"] as Dictionary).size()).is_greater(0)
	assert_int((hw["rail_coll"] as Dictionary).size()).is_equal(0)
	# The short segment is in the visual strip but not in the collision strip.
	assert_int((hw["surface"] as Dictionary).size()).is_equal((hw["road_coll"] as Dictionary).size() + 2)

func test_every_segment_belongs_to_exactly_one_cell() -> void:
	for def: RoadDef in [_ring_def(), _highway_def()]:
		var table := RoadChunkMesher.prepare_road(0, def, [])
		var cells := RoadChunkMesher.cell_segments(table, 64.0)
		var seen := {}
		for cell: Vector2i in cells:
			for s in (cells[cell] as PackedInt32Array):
				assert_bool(seen.has(s)).is_false()
				seen[s] = true
		assert_int(seen.size()).is_equal(int(table["seg_count"]))

func test_neighbouring_cells_share_bit_identical_seam_vertices() -> void:
	var def := _ring_def()
	var table := RoadChunkMesher.prepare_road(0, def, [])
	var cells := RoadChunkMesher.cell_segments(table, 64.0)
	var owner := {}
	for cell: Vector2i in cells:
		for s in (cells[cell] as PackedInt32Array):
			owner[s] = cell
	var n: int = table["n"]
	var seams := 0
	for s in n:
		var nxt := (s + 1) % n
		if owner[s] == owner[nxt]:
			continue
		seams += 1
		# Cell A's last row of segment s and cell B's first row of segment s+1.
		var ra := RoadChunkMesher.build_cell([table], [[0, PackedInt32Array([s])]])
		var rb := RoadChunkMesher.build_cell([table], [[0, PackedInt32Array([nxt])]])
		var va: PackedVector3Array = (ra["buckets"] as Dictionary).values()[0]["v"]
		var vb: PackedVector3Array = (rb["buckets"] as Dictionary).values()[0]["v"]
		# Surface bucket rows: [l0, r0, l1, r1] per segment.
		assert_bool(va[2] == vb[0] and va[3] == vb[1]).override_failure_message("seam after segment %d moved" % s).is_true()
	assert_int(seams).is_greater(3)

# --- streaming ----------------------------------------------------------------

func _stream_net(defs: Array) -> RoadNetwork:
	var net := RoadNetwork.new()
	net.stream_geometry = true
	net.stream_cell_size = 128.0
	net.stream_radius = 1
	net.stream_keep_radius = 2
	add_child(net)
	_keep(net)
	for d: RoadDef in defs:
		net.add_road_def(d)
	net.recompute_rails()
	return net

func _process_frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame

func test_non_streaming_network_still_builds_track_builders() -> void:
	var net := RoadNetwork.new()
	add_child(net)
	_keep(net)
	net.add_road_def(_ring_def())
	assert_bool(net.stream_geometry).is_false()
	assert_int(net.get_child_count()).is_equal(1)
	assert_object(net.get_child(0)).is_instanceof(TrackBuilder)

func test_streaming_network_builds_no_whole_road_geometry() -> void:
	var net := _stream_net([_ring_def(), _highway_def()])
	for c in net.get_children():
		assert_bool(c is TrackBuilder).is_false()
	# Topology, nearest-road and the def list behave exactly as before.
	assert_int(net.get_road_defs().size()).is_equal(2)
	assert_float(net.nearest_road_distance(_ring_def().points[5])).is_less(0.01)
	# recompute_rails stores the very gaps the non-streamed path hands to
	# TrackBuilder.configure_rails.
	var plain := RoadNetwork.new()
	add_child(plain)
	_keep(plain)
	plain.add_road_def(_ring_def())
	plain.add_road_def(_highway_def())
	plain.recompute_rails()
	for i in 2:
		var b := plain.get_child(i) as TrackBuilder
		assert_int(net.stream_rail_gaps(i).size()).is_equal(b._rail_gaps.size())

func test_streamed_rail_gaps_match_the_whole_road_path_on_a_junction() -> void:
	# A spur that ends on the ring creates a junction, so the ring's rail is cut.
	var ring := _ring_def()
	var spur_pts: Array[Vector3] = []
	var land := ring.points[30]
	for i in 12:
		spur_pts.append(land + Vector3(0.0, 0.0, 10.0 * float(11 - i)))
	var spur := RoadDef.make(RoadDef.Tier.ARTERIAL, spur_pts, "spur", false)
	var net := _stream_net([ring, spur])
	assert_int(net.get_junctions().size()).is_greater(0)
	assert_int(net.stream_rail_gaps(0).size()).is_greater(0)
	var plain := RoadNetwork.new()
	add_child(plain)
	_keep(plain)
	plain.add_road_def(_ring_def())
	plain.add_road_def(RoadDef.make(RoadDef.Tier.ARTERIAL, spur_pts, "spur", false))
	plain.recompute_rails()
	var full := _builder_tris(plain.get_child(0) as TrackBuilder)
	var chunked := _chunk_tris(ring, net.stream_rail_gaps(0), 64.0)
	_assert_same(full, chunked, "ring+spur")

func test_cells_load_around_the_car_and_free_past_the_keep_radius() -> void:
	var ring := _ring_def()
	var net := _stream_net([ring])
	var start := ring.points[0]
	net.sync_player_pos(start)
	await _process_frames(20)
	var centre := net.stream_cell_of(start)
	var expected := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c := centre + Vector2i(dx, dz)
			if net.cell_has_roads(c):
				expected += 1
				assert_bool(net.is_cell_loaded(c)).override_failure_message("cell %s not loaded" % c).is_true()
	assert_int(net.loaded_cells().size()).is_equal(expected)
	# The far LOD covers the whole network, casts no shadow and has no collision.
	var far := net.far_lod_node()
	assert_object(far).is_not_null()
	assert_int(far.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_int(far.get_child_count()).is_equal(0)
	# Drive half way round: the start cells leave, the new ones arrive.
	var far_side := ring.points[60]
	net.sync_player_pos(far_side)
	await _process_frames(30)
	var new_centre := net.stream_cell_of(far_side)
	for c: Vector2i in net.loaded_cells():
		assert_int(maxi(absi(c.x - new_centre.x), absi(c.y - new_centre.y))).is_less_equal(net.stream_keep_radius)
	assert_bool(net.is_cell_loaded(centre)).is_false()
	assert_int(int(net.stream_stats()["freed"])).is_greater(0)

func test_cells_share_materials_and_only_paint_skips_the_shadow_pass() -> void:
	var ring := _ring_def()
	var net := _stream_net([ring])
	net.sync_player_pos(ring.points[0])
	var mats := {}
	var surfaces := 0
	var paints := 0
	for cell in net.loaded_cells():
		for c in net.cell_node(cell).get_children():
			if c is MeshInstance3D:
				var mi := c as MeshInstance3D
				var n := String(mi.name)
				if n.begins_with("Mesh_s_"):
					surfaces += 1
					mats[mi.material_override.get_instance_id()] = true
					# An overpass must still shade the road under it.
					assert_int(mi.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
				elif n == "Mesh_r":
					assert_int(mi.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
				elif n.begins_with("Mesh_e_") or n == "Mesh_d":
					paints += 1
					assert_int(mi.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_int(surfaces).is_greater(1)
	assert_int(paints).is_greater(1)
	assert_int(mats.size()).is_equal(1)

## Materials are created while the stream is prepared (load time), never by a
## cell mid-drive: every bucket any cell can produce has a pre-made material.
func test_every_cell_material_is_warmed_at_prepare_time() -> void:
	var defs: Array = [_ring_def(), _highway_def(), _dirt_def(), _mixed_def()]
	var tables: Array = []
	for i in defs.size():
		tables.append(RoadChunkMesher.prepare_road(i, defs[i], _gaps_for(defs[i])))
	var warmed := RoadChunkMesher.material_specs(tables)
	var seen := {}
	for i in tables.size():
		var cells := RoadChunkMesher.cell_segments(tables[i], 64.0)
		for cell: Vector2i in cells:
			var r := RoadChunkMesher.build_cell(tables, [[i, cells[cell]]])
			for key: String in (r["buckets"] as Dictionary):
				seen[key] = true
				assert_bool(warmed.has(key)).override_failure_message("cell bucket %s has no warmed material" % key).is_true()
	# surface x3 (asphalt arterial, asphalt highway, dirt), mixed, edges, dashes, rails.
	assert_int(seen.size()).is_greater_equal(7)
	var net := _stream_net(defs)
	net.sync_player_pos(defs[0].points[0])
	assert_int(int(net.stream_stats()["materials"])).is_equal(warmed.size())

func _ray_hits_road(from: Vector3) -> bool:
	var space := get_tree().root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 5.0, from + Vector3.DOWN * 5.0)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return false
	var body := hit["collider"] as Node
	return body != null and String(body.name) == "RoadCollision"

func test_fast_travel_target_has_collision_without_waiting_for_the_worker() -> void:
	var ring := _ring_def()
	var hw := _highway_def()
	var net := _stream_net([ring, hw])
	net.sync_player_pos(ring.points[0])
	await _process_frames(10)
	var target := hw.points[45]
	assert_bool(net.is_cell_loaded(net.stream_cell_of(target))).is_false()
	# One call, no frame in between: the whole 3x3 block is there.
	net.sync_player_pos(target)
	var centre := net.stream_cell_of(target)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c := centre + Vector2i(dx, dz)
			if net.cell_has_roads(c):
				assert_bool(net.is_cell_loaded(c)).is_true()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(_ray_hits_road(target)).is_true()

func test_driving_the_road_never_meets_a_missing_collision() -> void:
	var ring := _ring_def()
	var net := _stream_net([ring])
	var pts := ring.points
	var misses := 0
	var probes := 0
	var step := 0
	# 120 points ~ 15.7 m apart: "drive" two laps, a point per frame (~940 m/s
	# equivalent; far faster than any car), probing the road under the car and
	# 60 m ahead every step.
	var unloaded := 0
	var first_miss := ""
	for lap in 2:
		for i in pts.size():
			var here := pts[i]
			var ahead := pts[(i + 4) % pts.size()]
			var probe_pts := [here, (here + ahead) * 0.5, ahead]
			net.sync_player_pos(here)
			# The guarantee itself: right after the call, every cell under the
			# car and 60 m ahead of it exists (no frame, no worker in between).
			for p: Vector3 in probe_pts:
				if not net.is_cell_loaded(net.stream_cell_of(p)) and net.cell_has_roads(net.stream_cell_of(p)):
					unloaded += 1
			await get_tree().process_frame
			# A body added this frame reaches the physics space on the next step.
			await get_tree().physics_frame
			await get_tree().physics_frame
			for p: Vector3 in probe_pts:
				probes += 1
				if not _ray_hits_road(p):
					misses += 1
					if first_miss == "":
						first_miss = "step %d at %s (cell %s loaded=%s)" % [step, p, net.stream_cell_of(p), net.is_cell_loaded(net.stream_cell_of(p))]
			step += 1
	assert_int(probes).is_greater(600)
	assert_int(unloaded).is_equal(0)
	assert_int(misses).override_failure_message("%d of %d probes found no road collision; first: %s" % [misses, probes, first_miss]).is_equal(0)

func test_freed_scene_waits_for_in_flight_builds() -> void:
	var ring := _ring_def()
	var net := _stream_net([ring])
	net.sync_player_pos(ring.points[0])
	await get_tree().process_frame
	net.sync_player_pos(ring.points[60])
	await get_tree().process_frame
	# Jobs may be in flight now; freeing must not crash or leak a task.
	remove_child(net)
	net.free()
	_managed.erase(net)
	assert_bool(is_instance_valid(net)).is_false()

# --- the open world -----------------------------------------------------------

func test_open_world_streams_its_roads() -> void:
	var runner := scene_runner(OPEN_WORLD_SCENE)
	await runner.simulate_frames(5)
	var scene := runner.scene()
	var net := scene.get_node_or_null("RoadNetwork") as RoadNetwork
	assert_object(net).is_not_null()
	if net == null:
		return
	assert_bool(net.stream_geometry).is_true()
	for c in net.get_children():
		assert_bool(c is TrackBuilder).is_false()
	var player := scene.get_node_or_null("%PlayerCar") as Node3D
	var centre := net.stream_cell_of(player.global_position)
	assert_bool(net.cell_has_roads(centre)).is_true()
	assert_bool(net.is_cell_loaded(centre)).is_true()
	var stats := net.stream_stats()
	# Only the neighbourhood of the car is built, not the whole network.
	assert_int(int(stats["loaded"])).is_less(int(stats["cells_with_roads"]) / 4)
	assert_object(net.far_lod_node()).is_not_null()
