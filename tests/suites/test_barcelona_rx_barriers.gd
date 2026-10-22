# tests/suites/test_barcelona_rx_barriers.gd
extends GdUnitTestSuite

## Gate for the Circuit de Barcelona-Catalunya — Rallycross PHYSICAL barriers
## (the red barrier line around corners T1/T2/T6) built by
## `scripts/track/barcelona_rx.gd::_build_barrier_colliders()`
## (docs/plans/track_barcelona_rallycross.md §3.4 / §5 suite 3).
##
## Why the collider exists at all: the barrier MESH is a `RxDressing` MultiMesh
## with no collision whatsoever, and `TrackBuilder` only adds rail collision when
## its junction gap list is non-empty — which a standalone circuit never has — so
## without this chain a car drives straight through the red barrier off the dirt.
##
## Proof is in two layers (the `test_northern_isle_barriers.gd` pattern):
##   * structure — the chain is built into a suite-owned Node3D through the same
##     builder the scene calls, and the real scene's `_ready` is checked to wire
##     it (node present, chunked bodies, the outfield lateral line, the vehicle
##     collision layers, the friction, the visual-top cap);
##   * behaviour — a plain RigidBody3D pusher (NO car scene, so this suite never
##     fights concurrent work on the vehicle/HUD scripts) fired radially inward at
##     the T1 chain cannot reach the carriageway, while a matched control fired
##     outward proves the simulation actually integrates.
##
## No wall-clock assertions anywhere (the `test_perf_gate` lesson).

const SCENE_BARCELONA := "res://scenes/track/barcelona_rx.tscn"
const SCRIPT_BARCELONA := "res://scripts/track/barcelona_rx.gd"

## Independent spec for the chain's vertical cap (the invisible-wall audit): a
## chain box may stand at most this far (m) above the TOP of the visual it
## guards. Deliberately NOT read from `barcelona_rx.gd`'s own margin constant, so
## loosening the script cannot loosen the gate. 0.20 passes today's 0.10 with room
## and still fails a chain that towers over the 1.57 m barrier.
const MAX_TOP_MARGIN := 0.20
## Visual top of the red barrier GLB at `RxDressing.BARRIER_SCALE` (m), the same
## figure both `rx_dressing.gd` and `barcelona_rx.gd` name. The GLB exposes no
## constant.
const RED_BARRIER_VISUAL_TOP := 1.57
## Friction the chain must carry (matches `TrackBuilder` rail collision).
const BARRIER_FRICTION := 0.2

## Pusher physics (see `_pusher`). Zero gravity keeps the box inside the barrier's
## vertical span; the velocity is radial (toward or away from the centreline).
const PUSH_SPEED := 12.0
const PUSH_FRAMES := 45
const PUSH_Y := 1.0
const BODY_HALF := 0.5
## How far outfield of the centreline a pusher starts (m): 4.4 m beyond the
## barrier line at `W/2 + BARRIER_OFFSET` = 7.6.
const PUSH_OUTFIELD := 12.0
## The pusher must never come within this of the centreline: the road half-width
## is 6, so reaching it would mean it crossed the barrier and got onto the dirt.
const ROAD_EDGE_CLEARANCE := 6.5

## The scene is stripped of everything this suite must not run (the car, the
## cameras that target it, the HUD/pause menu) before it enters the tree, leaving
## `_ready` to do its centreline/road/checkpoint/barrier-collider wiring.
const SCENE_STRIP: Array[String] = [
	"PlayerCar", "ChaseCamera", "OrbitCamera", "HoodCamera", "CockpitCamera",
	"HUD", "PauseMenu",
]

var _host: Node3D = null
var _scene: Node3D = null
var _frames: Array[Dictionary] = []

func before_test() -> void:
	RaceManager._checkpoints_dirty = true

func after_test() -> void:
	if _host != null and is_instance_valid(_host):
		_host.free()
	_host = null
	if _scene != null and is_instance_valid(_scene):
		_scene.free()
	_scene = null
	# The scene test's checkpoints died with the scene; make sure RaceManager
	# re-scans the group next time (the test_northern_isle_track hygiene).
	RaceManager._checkpoints_dirty = true
	RaceManager.rival_centerline = []
	RaceManager.consume_pending_race()
	for child in get_children():
		if child is Checkpoint:
			child.free()

## A bare `barcelona_rx.gd` instance that has never entered the tree, so `_ready`
## (ground bake, road, checkpoints, dressing) never runs. The barrier builder only
## reads `BarcelonaRxLayout`, so this is enough to exercise it in isolation.
func _offline_builder() -> Node3D:
	var script := load(SCRIPT_BARCELONA) as GDScript
	var builder := script.new() as Node3D
	builder.set("road_points", BarcelonaRxLayout.build_centerline())
	builder.set("bank_profile", BarcelonaRxLayout.build_bank_profile())
	return builder

## Builds the chain the way `_ready` does, into a suite-owned host.
func _build_into_host() -> Node3D:
	_host = Node3D.new()
	add_child(_host)
	var builder := _offline_builder()
	builder.call("_build_barrier_colliders", _host, Callable())
	builder.free()
	return _host

func _bodies_with_prefix(root: Node3D, prefix: String) -> Array[StaticBody3D]:
	var out: Array[StaticBody3D] = []
	for child in root.get_children():
		var body := child as StaticBody3D
		if body != null and String(body.name).begins_with(prefix):
			out.append(body)
	return out

func _shapes_of(body: StaticBody3D) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for child in body.get_children():
		var shape := child as CollisionShape3D
		if shape != null:
			out.append(shape)
	return out

func _all_shapes(root: Node3D) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for child in root.get_children():
		var body := child as StaticBody3D
		if body != null:
			out.append_array(_shapes_of(body))
	return out

## Signed lateral offset of a world XZ point from the centreline (positive = right
## of travel, i.e. the INNER side of a right-hand turn), measured against the
## layout's own frames. Cached: 400 frames.
func _lateral_offset(p: Vector3) -> float:
	if _frames.is_empty():
		for i in BarcelonaRxLayout.TOTAL_POINTS:
			_frames.append(BarcelonaRxLayout.frame_at_arc(BarcelonaRxLayout.arc_of_index(i)))
	var best := INF
	var best_s := 0.0
	for frame: Dictionary in _frames:
		var center: Vector3 = frame["center"]
		var dx := p.x - center.x
		var dz := p.z - center.z
		var d := dx * dx + dz * dz
		if d < best:
			best = d
			var right: Vector3 = frame["right"]
			best_s = dx * right.x + dz * right.z
	return best_s

## One box per `BarcelonaRxLayout.spacing()` step across every barrier arc range
## (T1/T2/T6), the real count the builder emits.
func _expected_box_count() -> int:
	var step := BarcelonaRxLayout.spacing()
	var total := 0
	for r: Vector2 in BarcelonaRxLayout.barrier_arc_ranges():
		total += int(ceil((r.y - r.x) / step))
	return total

## A plain (car-free) pusher box. Zero gravity keeps it inside the barrier's
## vertical span; it starts `PUSH_OUTFIELD` outfield of the centreline and moves
## `direction` along the frame's horizontal right (positive = inward at a corner).
## `along` shifts the start along the road (m): the inward pusher and the
## outward control used to spawn at the SAME point, fully interpenetrated, so
## the depenetration impulse between the two boxes randomly shoved one of them
## -- the historical flake of `test_pusher_cannot_cross_the_barrier`.
func _pusher(frame: Dictionary, direction: float, along: float = 0.0) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "Pusher"
	var box := BoxShape3D.new()
	box.size = Vector3(2.0 * BODY_HALF, 2.0 * BODY_HALF, 2.0 * BODY_HALF)
	var collision := CollisionShape3D.new()
	collision.shape = box
	body.add_child(collision)
	body.gravity_scale = 0.0
	body.linear_damp = 0.0
	body.continuous_cd = true
	var center: Vector3 = frame["center"]
	var right: Vector3 = frame["right"]
	var forward: Vector3 = frame["forward"]
	forward.y = 0.0
	body.position = center + right * BarcelonaRxLayout.OUTFIELD_SIDE * PUSH_OUTFIELD \
		+ forward.normalized() * along + Vector3(0.0, PUSH_Y - center.y, 0.0)
	body.linear_velocity = right * direction * PUSH_SPEED
	_host.add_child(body)
	return body

# --- structure --------------------------------------------------------------

## The builder emits one box per layout step across the three barrier arcs, in
## chunked bodies on the vehicle collision layers, on the OUTFIELD lateral line.
func test_builder_creates_box_chain_on_the_outfield() -> void:
	var host := _build_into_host()
	# Idempotent rebuild: a second call replaces the first, so a re-run cannot
	# stack duplicate walls.
	var builder := _offline_builder()
	var added: int = builder.call("_build_barrier_colliders", host, Callable())
	builder.free()
	var expected := _expected_box_count()
	assert_int(added).is_equal(expected)

	var root := host.get_node_or_null("BarrierColliders") as Node3D
	assert_that(root).is_not_null()
	if root == null:
		return
	assert_int(_all_shapes(root).size()).is_equal(expected)

	# The barrier sits at OUTFIELD_SIDE * (W/2 + BARRIER_OFFSET) = -7.6 m: outside
	# the road edge (half width 6) on the LEFT of travel. Only T2/T6 berm (7 deg),
	# where the XZ offset is `line * cos(bank)`, so the whole set lands within
	# +-0.5 m of the line.
	var line := -1.0 * (BarcelonaRxLayout.WIDTH * 0.5 + RxDressing.BARRIER_OFFSET)
	var min_s := INF
	var max_s := -INF
	for shape in _all_shapes(root):
		var s := _lateral_offset(shape.global_position)
		min_s = minf(min_s, s)
		max_s = maxf(max_s, s)
		assert_float(absf(s - line)).is_less_equal(0.5)
	# Strictly outfield (never on the carriageway) and never out beyond the line.
	assert_float(max_s).is_less(0.0)
	assert_float(min_s).is_less_equal(line + 0.1)

	# Each body is a vehicle-collidable static body holding only box shapes, each
	# out-topping the visual it guards yet towering no more than `MAX_TOP_MARGIN`
	# above it (the invisible-wall regression: a physics proxy, not a hidden wall).
	var consts: Dictionary = (load(SCRIPT_BARCELONA) as GDScript).get_script_constant_map()
	var drop_below: float = consts.get("BARRIER_DROP_BELOW", 1.0)
	var expected_spacing := BarcelonaRxLayout.spacing()
	var bodies := _bodies_with_prefix(root, "RedBarrierCollision")
	assert_int(bodies.size()).is_greater_equal(2)
	var shapes: Array[CollisionShape3D] = []
	for body in bodies:
		assert_int(body.collision_layer).is_equal(1)
		assert_int(body.collision_mask).is_equal(1)
		assert_that(body.physics_material_override).is_not_null()
		if body.physics_material_override != null:
			assert_float(body.physics_material_override.friction).is_equal_approx(BARRIER_FRICTION, 0.001)
		shapes.append_array(_shapes_of(body))
	assert_int(shapes.size()).is_equal(expected)
	var min_top := INF
	var max_rise := -INF
	for shape in shapes:
		var box := shape.shape as BoxShape3D
		assert_that(box).is_not_null()
		if box == null:
			continue
		# Long enough to overlap its neighbour: no seam at a curve.
		assert_float(box.size.z).is_greater(expected_spacing)
		# Thick enough to be a wall, thin enough not to intrude on the dirt.
		assert_float(box.size.x).is_between(0.1, 0.6)
		min_top = minf(min_top, box.size.y)
		max_rise = maxf(max_rise, box.size.y - drop_below)
	assert_float(min_top).is_greater_equal(RED_BARRIER_VISUAL_TOP)
	assert_float(max_rise).is_between(RED_BARRIER_VISUAL_TOP, RED_BARRIER_VISUAL_TOP + MAX_TOP_MARGIN)

# --- wiring -----------------------------------------------------------------

## The real scene's `_ready` must actually build the colliders (the builder test
## above would happily pass with the call deleted from `_ready`).
func test_scene_ready_builds_barrier_colliders() -> void:
	var packed := load(SCENE_BARCELONA) as PackedScene
	assert_that(packed).is_not_null()
	if packed == null:
		return
	var scene := packed.instantiate() as Node3D
	assert_that(scene).is_not_null()
	if scene == null:
		return
	# Strip the pieces this suite must not run BEFORE the scene enters the tree,
	# so no vehicle/HUD script ever runs here.
	for node_name: String in SCENE_STRIP:
		var node := scene.get_node_or_null(node_name)
		if node != null:
			scene.remove_child(node)
			node.free()
	scene.set("build_own_ground", false)
	scene.set("build_foliage", false)
	scene.set("build_dressing", false)
	scene.set("reposition_player", false)
	_scene = scene
	add_child(scene)

	var root := scene.get_node_or_null("BarrierColliders") as Node3D
	assert_that(root).is_not_null()
	if root == null:
		return
	assert_that(scene.get_node_or_null("RoadNetwork")).is_not_null()
	assert_int(_all_shapes(root).size()).is_equal(_expected_box_count())
	var bodies := _bodies_with_prefix(root, "RedBarrierCollision")
	assert_bool(bodies.is_empty()).is_false()

# --- behaviour --------------------------------------------------------------

## A pusher fired radially inward at the T1 chain cannot reach the carriageway,
## while a matched control fired outward proves the simulation ran (no false green
## from a physics-less tree).
func test_pusher_cannot_cross_the_barrier() -> void:
	_build_into_host()
	# T1 is the tightest corner and carries a barrier line; it is NOT bermed, so
	# its frame's `right` is horizontal and the approach is face-on.
	var frame := BarcelonaRxLayout.frame_at_arc(BarcelonaRxLayout.corner_apex_arc(1))
	# Pushed inward (toward the centreline): the barrier must stop it.
	var inward := _pusher(frame, 1.0)
	# Pushed outward into open ground: nothing to hit, so it must travel freely.
	var control := _pusher(frame, -1.0, 6.0)

	for _i in PUSH_FRAMES:
		await get_tree().physics_frame

	var inward_s := absf(_lateral_offset(inward.global_position))
	var control_s := absf(_lateral_offset(control.global_position))
	# The control really travelled outward (the physics tree is live).
	assert_float(control_s).is_greater(PUSH_OUTFIELD + 3.0)
	# The barrier held the pusher off the carriageway.
	assert_float(inward_s).is_greater_equal(ROAD_EDGE_CLEARANCE)
	# And it did move inward (not teleported / never integrated).
	assert_float(inward_s).is_less(PUSH_OUTFIELD - 0.5)
