# tests/suites/test_track_builder_winding.gd
extends GdUnitTestSuite

## Regression gate for the near-black road (every TrackBuilder track: Sunset
## Oval, Mountain Pass, Northern Isle, Barcelona RX, the open world).
##
## Root cause: TrackBuilder emitted the visible road strip (and the edge lines
## and lane dividers) with COUNTER-clockwise winding seen from above. Godot's
## front face is CLOCKWISE, so the top of the road was a BACK face; the
## materials are `cull_disabled`, and Godot flips the normal of a back face, so
## the asphalt was lit from below -- near-black under the sun. The collision
## strip was the only mesh built with the up-facing order (its `flip_winding`).
##
## This suite pins: every road triangle faces up (geometric normal and vertex
## normal), the visual strip and the trimesh collision are the SAME triangles
## in the SAME order, and a front-face-only ray from above hits the road (the
## physics side still works), on flat, banked, sloped/open and mixed-surface
## roads.
##
## Godot convention used throughout: a front face seen from above has
## `(v1 - v0).cross(v2 - v0).y < 0`.

var _managed: Array[Node] = []

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	for node in _managed:
		if is_instance_valid(node):
			node.free()
	_managed.clear()

func _ring(n: int, radius: float, y: float = 0.0) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(Vector3(cos(a) * radius, y, sin(a) * radius * 0.6))
	return pts

## An open, climbing S-bend (slope + both turn directions).
func _open_hill() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for i in 40:
		var t := float(i)
		pts.append(Vector3(t * 6.0, t * 0.35, sin(t * 0.25) * 25.0))
	return pts

func _build(points: Array[Vector3], closed: bool, def: RoadDef) -> TrackBuilder:
	var builder := TrackBuilder.new()
	_managed.append(builder)
	add_child(builder)
	builder.build_track(points, closed, def)
	return builder

## Faces of a mesh instance as a flat vertex list (3 per triangle).
func _faces(mi: MeshInstance3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var arrays := (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var idx := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	for k in idx:
		out.append(verts[k])
	return out

## Number of triangles whose front face does NOT point up.
func _down_faces(faces: PackedVector3Array) -> int:
	var down := 0
	for t in range(0, faces.size(), 3):
		var nrm := (faces[t + 1] - faces[t]).cross(faces[t + 2] - faces[t])
		if nrm.y >= 0.0:
			down += 1
	return down

## Every flat mesh child (surface, edge lines, lane dividers) faces up and its
## vertex normals agree with the geometric (front-face) normal.
func _assert_all_strips_face_up(builder: TrackBuilder) -> void:
	var checked := 0
	for child in builder.get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var child_name := String(mi.name)
		if not (child_name == "RoadSurface" or child_name.begins_with("RoadEdge") \
				or child_name.begins_with("LaneDivider")):
			continue
		var arrays := (mi.mesh as ArrayMesh).surface_get_arrays(0)
		var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		var idx := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		assert_int(idx.size()).is_greater(0)
		assert_int(_down_faces(_faces(mi))).override_failure_message(
			"%s has back faces on top" % child_name).is_equal(0)
		var worst := 1.0
		for t in range(0, idx.size(), 3):
			var geo := -(verts[idx[t + 1]] - verts[idx[t]]).cross(verts[idx[t + 2]] - verts[idx[t]])
			if geo.length_squared() < 1e-10:
				continue
			geo = geo.normalized()
			for m in 3:
				worst = minf(worst, geo.dot(normals[idx[t + m]]))
		assert_float(worst).override_failure_message(
			"%s vertex normals disagree with the front face" % child_name).is_greater(0.95)
		checked += 1
	assert_int(checked).is_greater_equal(2)

func test_flat_closed_road_faces_up_everywhere() -> void:
	var def := RoadDef.make(RoadDef.Tier.HIGHWAY, _ring(48, 120.0), "w-flat", true, 16.0)
	var builder := _build(def.points, true, def)
	_assert_all_strips_face_up(builder)
	# A 16 m highway has lane dividers, so they were covered too.
	assert_bool(builder.get_node_or_null("LaneDivider0") != null).is_true()

func test_banked_road_faces_up_and_normals_follow_the_bank() -> void:
	var pts := _ring(48, 120.0)
	var def := RoadDef.make(RoadDef.Tier.ARTERIAL, pts, "w-bank", true, 12.0)
	var bank := PackedFloat32Array()
	for i in pts.size():
		bank.append(0.30)
	def.bank_angles = bank
	var builder := _build(pts, true, def)
	_assert_all_strips_face_up(builder)
	# The surface normal is tilted by the bank (no longer a flat UP).
	var mi := builder.get_node("RoadSurface") as MeshInstance3D
	var normals := (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_NORMAL] as PackedVector3Array
	assert_float(normals[0].y).is_equal_approx(cos(0.30), 0.01)

func test_open_sloped_road_faces_up() -> void:
	var def := RoadDef.make(RoadDef.Tier.TOUGE, _open_hill(), "w-hill", false, 10.0)
	var builder := _build(def.points, false, def)
	_assert_all_strips_face_up(builder)

func test_legacy_no_def_builder_faces_up() -> void:
	# The Sunset Oval / Mountain Pass path: build_track(points) with no RoadDef.
	var builder := _build(_ring(32, 60.0, 0.1), true, null)
	_assert_all_strips_face_up(builder)

## The physics side uses the visual strip's own triangles: same vertices, same
## order, so what you see is exactly what the wheels ride on.
func test_collision_trimesh_is_the_visual_strip() -> void:
	var pts := _ring(48, 120.0)
	var def := RoadDef.make(RoadDef.Tier.ARTERIAL, pts, "w-coll", true, 12.0)
	var builder := _build(pts, true, def)
	var visual := _faces(builder.get_node("RoadSurface") as MeshInstance3D)
	var body := builder.get_node("CollisionBody") as StaticBody3D
	var shape := (body.get_child(0) as CollisionShape3D).shape as ConcavePolygonShape3D
	var coll := shape.get_faces()
	assert_int(coll.size()).is_equal(visual.size())
	var worst := 0.0
	for i in mini(coll.size(), visual.size()):
		worst = maxf(worst, coll[i].distance_to(visual[i]))
	assert_float(worst).is_less(0.0001)
	assert_int(_down_faces(coll)).is_equal(0)

## Front-face-only rays from above land on the road on a flat and a banked
## loop, with an upward hit normal: the trimesh still collides from the top.
func test_front_face_ray_from_above_hits_the_road() -> void:
	var pts := _ring(48, 120.0)
	var def := RoadDef.make(RoadDef.Tier.ARTERIAL, pts, "w-ray", true, 12.0)
	var bank := PackedFloat32Array()
	for i in pts.size():
		bank.append(0.2 if i < 24 else 0.0)
	def.bank_angles = bank
	var builder := _build(pts, true, def)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := builder.get_world_3d().direct_space_state
	var hits := 0
	for i in [0, 6, 12, 30, 40]:
		var p: Vector3 = pts[i]
		var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 5.0, p + Vector3.DOWN * 5.0)
		query.hit_back_faces = false
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			hits += 1
			assert_float((hit["normal"] as Vector3).y).is_greater(0.9)
	assert_int(hits).is_equal(5)

## Mixed-surface road (RoadDef.point_surfaces): the loose weight lives in the
## vertex colour, the strip still faces up, and the edge strips are left to the
## shader (none built).
func test_mixed_surface_road_faces_up_and_carries_loose_weights() -> void:
	var pts := _ring(240, 150.0)
	var def := RoadDef.make(RoadDef.Tier.DIRT, pts, "w-mixed", true, 12.0, RoadDef.Surface.GRAVEL, RoadDef.RailSide.NONE)
	var profile := PackedByteArray()
	for i in pts.size():
		profile.append(RoadDef.Surface.GRAVEL if i >= 80 and i < 160 else RoadDef.Surface.ASPHALT)
	def.point_surfaces = profile
	var builder := _build(pts, true, def)
	var mi := builder.get_node("RoadSurface") as MeshInstance3D
	assert_int(_down_faces(_faces(mi))).is_equal(0)
	assert_bool(mi.material_override is ShaderMaterial).is_true()
	assert_that(builder.get_node_or_null("RoadEdgeRight")).is_null()
	var colors := (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
	assert_int(colors.size()).is_equal(pts.size() * 2)
	# Deep inside the loose section: fully loose; far from it: clean asphalt.
	assert_float(colors[120 * 2].r).is_equal_approx(1.0, 0.001)
	assert_float(colors[20 * 2].r).is_equal_approx(0.0, 0.001)
	# Downstream of the dirt exit the tarmac carries a fading dirt spill.
	assert_float(colors[160 * 2].r).is_greater(colors[162 * 2].r)
	assert_float(colors[162 * 2].r).is_greater(0.0)
	# Weights are a pure function of the profile (deterministic rebuild); the mesh
	# stores COLOR as 8-bit unorm, hence the 1/255 tolerance.
	var again := TrackBuilder.loose_weights(pts, profile, true)
	for i in pts.size():
		assert_float(again[i]).is_equal_approx(colors[i * 2].r, 0.005)
