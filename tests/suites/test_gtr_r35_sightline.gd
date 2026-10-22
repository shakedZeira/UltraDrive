# tests/suites/test_gtr_r35_sightline.gd
extends GdUnitTestSuite

## R35 cockpit sightline gate (fix_gtr_windshield_glass.md sec 5.1).
##
## Root cause of the reported "black windshield": with the R35's glass tinted
## TRANSPARENT (pinned by test_gtr_r35), the driver's forward view is below the
## windscreen (its lowest point is ~+15 deg above the eye), so whatever interior
## geometry occupies the horizon is what the player sees. The authored R35 cabin
## used to straddle the eye's horizontal plane across the forward cone
## (BinnacleHood top +0.266, BinnacleBack +0.140, the gauge pods, the steering
## rim, the centre riser) and, being near-black, rendered as a black slab over
## the horizon.
##
## This suite instantiates the authored interior DIRECTLY and measures every
## mesh's AABB in EYE space. The interior root now carries a downward offset
## (sec 2.4/ step 2 of the plan: eye == rig origin, so the cabin is authored in
## eye space), therefore eye space is the interior root's PARENT space, not the
## root's own local space (a root-local measurement would cancel the offset and
## make the gate vacuous).
##
## Rule: any mesh whose AABB overlaps the forward cone must NOT straddle the
## eye's horizontal plane, i.e. (top_y <= -0.05) or (bottom_y >= +0.05).
## Cone overlap is the plan's wedge test: a point with z < 0 and
## |x| <= 0.3 * (-z) (a ~+-16.7 deg horizontal wedge).

const R35_COCKPIT: PackedScene = preload("res://scenes/vehicle/interiors/nissan_gt_r35_2017_cockpit.tscn")

## Horizontal half-angle tangent of the forward wedge (plan sec 5.1: |x| <= 0.3*(-z)).
const SIGHTLINE_WEDGE_TAN := 0.3
## The sightline keep-out band: a cone-overlapping mesh may not have any AABB
## point within +-0.05 m of the eye's horizontal plane.
const SIGHTLINE_BAND := 0.05

var _managed: Array = []

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	for node in _managed:
		if is_instance_valid(node):
			node.free()
	_managed.clear()

func _new_root() -> Node:
	var root := Node.new()
	root.name = "TestRoot"
	_managed.append(root)
	add_child(root)
	return root

## Adds the authored interior under an explicit identity "Eye" Node3D: the eye
## node's space IS eye space (the interior root's own offset is included, as it
## is in game where the rig's origin is the eye). Returns the eye node.
func _build_interior_under_eye(root: Node) -> Node3D:
	var eye := Node3D.new()
	eye.name = "Eye"
	_managed.append(eye)
	root.add_child(eye)
	var interior := R35_COCKPIT.instantiate() as Node3D
	_managed.append(interior)
	eye.add_child(interior)
	return eye

## A mesh instance's AABB expressed in eye space: the mesh-local AABB (Godot's
## PrimitiveMesh AABB is tight around the generated vertices) transformed by the
## node's transform relative to the eye node.
func _eye_aabb(mesh_instance: MeshInstance3D, eye: Node3D) -> AABB:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return AABB()
	var local_aabb: AABB = mesh.get_aabb()
	var to_eye: Transform3D = eye.global_transform.affine_inverse() * mesh_instance.global_transform
	var lo: Vector3 = local_aabb.position
	var hi: Vector3 = local_aabb.position + local_aabb.size
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for ix: int in range(2):
		for iy: int in range(2):
			for iz: int in range(2):
				var corner := Vector3(
					lo.x if ix == 0 else hi.x,
					lo.y if iy == 0 else hi.y,
					lo.z if iz == 0 else hi.z
				)
				var wp: Vector3 = to_eye * corner
				mn = Vector3(minf(mn.x, wp.x), minf(mn.y, wp.y), minf(mn.z, wp.z))
				mx = Vector3(maxf(mx.x, wp.x), maxf(mx.y, wp.y), maxf(mx.z, wp.z))
	return AABB(mn, mx - mn)

## True when the AABB has a point with z < 0 and |x| <= 0.3*(-z): the minimum of
## (|x| + 0.3*z) over the box is attained at the smallest z and the x closest to
## zero, so this is exact, not a sample.
func _overlaps_forward_wedge(aabb: AABB) -> bool:
	var z_min: float = aabb.position.z
	if z_min >= 0.0:
		return false
	var x_min: float = aabb.position.x
	var x_max: float = aabb.position.x + aabb.size.x
	var x_near: float = 0.0
	if not (x_min <= 0.0 and x_max >= 0.0):
		x_near = minf(absf(x_min), absf(x_max))
	return (x_near + SIGHTLINE_WEDGE_TAN * z_min) <= 0.0

## True when the AABB intersects the open band (-0.05, +0.05) around y = 0: the
## failure the plan forbids for any forward-cone mesh.
func _straddles_sightline(aabb: AABB) -> bool:
	var top: float = aabb.position.y + aabb.size.y
	var bottom: float = aabb.position.y
	return top > -SIGHTLINE_BAND and bottom < SIGHTLINE_BAND

## Regression guard: no forward-cone mesh may straddle the eye's horizontal
## plane. RED before the interior offset (17 meshes), GREEN after.
func test_r35_interior_no_mesh_straddles_the_sightline() -> void:
	var root := _new_root()
	var eye := _build_interior_under_eye(root)

	var mesh_count := 0
	var offenders: Array[String] = []
	for node: Node in eye.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		mesh_count += 1
		var aabb := _eye_aabb(mesh_instance, eye)
		if _overlaps_forward_wedge(aabb) and _straddles_sightline(aabb):
			offenders.append(String(mesh_instance.name))

	assert_that(mesh_count).is_greater(0)
	assert_that(offenders).is_empty()

## Named spot checks keep the intent readable: the near-field cluster that used
## to cover the horizon must sit below it (top <= -0.05 m in eye space).
func test_r35_cluster_tops_are_below_the_horizon() -> void:
	var root := _new_root()
	var eye := _build_interior_under_eye(root)

	for node_name: String in ["BinnacleHood", "BinnacleBack", "SteeringWheel"]:
		var mesh_instance := eye.find_child(node_name, true, false) as MeshInstance3D
		assert_that(mesh_instance).is_not_null()
		if mesh_instance == null:
			continue
		var aabb := _eye_aabb(mesh_instance, eye)
		var top: float = aabb.position.y + aabb.size.y
		assert_that(top).is_less_equal(-0.05)
