# tests/suites/test_northern_isle_barriers.gd
extends GdUnitTestSuite

## Gate for the Northern Isle PHYSICAL barriers (catch fence line, red barrier
## line, inner road rail) added by `northern_isle.gd::_build_barrier_colliders()`.
##
## Why the collider exists at all: the barrier visuals are meshes only.
## `OvalDressing` builds no collision whatsoever, and `TrackBuilder` adds rail
## collision only when its junction gap list is non-empty — which a standalone
## oval never has — so a car used to drive straight through the fence and the
## rails off the tarmac.
##
## Proof is in two layers:
##   * structure — the chain is built into a suite-owned Node3D through the same
##     builder the scene calls, and the real scene's `_ready` is checked to wire
##     it (node present, chunked bodies, both sides of the centreline, vehicle
##     collision layers);
##   * behaviour — plain RigidBody3D pushers (NO car scenes, so this suite never
##     fights concurrent work on the vehicle/HUD scripts) fired at the chains
##     cannot cross them.
##
## No wall-clock assertions anywhere (the `test_perf_gate` lesson).

const SCENE_NORTHERN_ISLE := "res://scenes/track/northern_isle.tscn"
const SCRIPT_NORTHERN_ISLE := "res://scripts/track/northern_isle.gd"

## Pusher physics (see `_pusher`): 30 m/s is ~108 km/h at the barrier, 40 frames
## is 0.667 s at the project's 60 Hz tick, and zero gravity keeps the box in the
## wall's vertical span.
const PUSH_SPEED := 30.0
const PUSH_FRAMES := 40
## On the front straight: bank 0, travel +X, outfield +Z (so z = TURN_RADIUS).
const PUSH_X := 60.0
const PUSH_Y := 1.0
const BODY_HALF := 0.5

## Independent spec for the chain's vertical cap (the invisible-wall audit): a
## chain box may stand at most this far (m) above the TOP of the visual it
## guards. Deliberately NOT read from `northern_isle.gd`'s own margin constant,
## so loosening the script cannot loosen the gate.
##
## Picked between the two ends that matter: the builder's `BARRIER_TOP_MARGIN`
## is 0.10, and the SMALLEST over-height this suite exists to catch is the red
## barrier's original 0.33 (1.9 above a 1.57 visual). Anything >= 0.33 would have
## passed the original defect outright; 0.20 passes today at 0.10 with real room
## and still fails the original fence (0.40), red (0.33) and rail (0.85) rises.
const MAX_TOP_MARGIN := 0.20
## Visual top of the red barrier GLB at `OvalDressing.BARRIER_SCALE` (m), the
## same figure `northern_isle.gd` names. The GLB exposes no constant.
const RED_BARRIER_VISUAL_TOP := 1.57

## The scene is stripped of everything this suite must not run (the car, the
## cameras that target it, the HUD/pause menu) and of the heavy builders, leaving
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

## A bare `northern_isle.gd` instance that has never entered the tree, so
## `_ready` (ground bake, road, checkpoints, dressing) never runs; only the two
## members the barrier builder reads are populated.
func _offline_builder() -> Node3D:
	var script := load(SCRIPT_NORTHERN_ISLE) as GDScript
	var builder := script.new() as Node3D
	builder.set("road_points", NorthernIsleLayout.build_centerline())
	builder.set("bank_profile", NorthernIsleLayout.build_bank_profile())
	return builder

## Builds the chains the way `_ready` does, into a suite-owned host.
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

## Signed lateral offset of a world XZ point from the centreline (positive =
## outfield), measured against the layout's own frames. Cached: 304 frames.
func _lateral_offset(p: Vector3) -> float:
	if _frames.is_empty():
		for i in NorthernIsleLayout.TOTAL_POINTS:
			_frames.append(NorthernIsleLayout.frame_at_arc(NorthernIsleLayout.arc_of_index(i)))
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

## A plain (car-free) pusher box. Zero gravity keeps it inside the barrier's
## vertical span; the velocity is straight at the chain along -Z or +Z.
func _pusher(z: float, direction: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "Pusher"
	var box := BoxShape3D.new()
	box.size = Vector3(2.0 * BODY_HALF, 2.0 * BODY_HALF, 2.0 * BODY_HALF)
	var collision := CollisionShape3D.new()
	collision.shape = box
	body.add_child(collision)
	body.gravity_scale = 0.0
	body.linear_damp = 0.0
	body.position = Vector3(PUSH_X, PUSH_Y, z)
	body.linear_velocity = Vector3(0.0, 0.0, direction * PUSH_SPEED)
	_host.add_child(body)
	return body

# --- structure --------------------------------------------------------------

## The builder emits one box per layout step for three chains (fence, red
## barrier, inner rail), chunked into bodies on the vehicle collision layers.
func test_builder_creates_box_chains_on_both_sides() -> void:
	var host := _build_into_host()
	# Idempotent rebuild: a second call replaces the first, so a re-run cannot
	# stack duplicate walls.
	var builder := _offline_builder()
	var added: int = builder.call("_build_barrier_colliders", host, Callable())
	builder.free()
	assert_int(added).is_equal(3 * NorthernIsleLayout.TOTAL_POINTS)

	var root := host.get_node_or_null("BarrierColliders") as Node3D
	assert_that(root).is_not_null()
	if root == null:
		return
	assert_int(_all_shapes(root).size()).is_equal(3 * NorthernIsleLayout.TOTAL_POINTS)

	var half := NorthernIsleLayout.WIDTH * 0.5
	var fence_line := half + OvalDressing.FENCE_OFFSET
	var red_line := half + OvalDressing.BARRIER_OFFSET
	var rail_line := half + TrackBuilder.RAIL_GAP

	var min_s := INF
	var max_s := -INF
	var on_fence := 0
	var on_red := 0
	var on_rail := 0
	for shape in _all_shapes(root):
		var s := _lateral_offset(shape.global_position)
		min_s = minf(min_s, s)
		max_s = maxf(max_s, s)
		# The chain follows the BANKED cross-section, so the XZ lateral offset is
		# offset*cos(bank) — exact on the straights (the majority of the loop).
		if absf(s - fence_line) <= 0.05:
			on_fence += 1
		if absf(s - red_line) <= 0.05:
			on_red += 1
		if absf(s + rail_line) <= 0.05:
			on_rail += 1

	# Both edges of the circuit, outermost line reached: the infield rail and the
	# outfield red barrier are the extremes.
	assert_float(max_s).is_greater_equal(red_line - 0.1)
	assert_float(min_s).is_less_equal(-(rail_line) + 0.1)
	assert_int(on_fence).is_greater_equal(150)
	assert_int(on_red).is_greater_equal(150)
	assert_int(on_rail).is_greater_equal(150)

	# Each body is a vehicle-collidable static body holding only box shapes, and
	# each box out-tops the visual it guards yet towers no more than
	# `MAX_TOP_MARGIN` above it (the invisible-wall regression: the chain is a
	# physics proxy for a mesh, not a taller hidden wall).
	var expected_spacing := NorthernIsleLayout.spacing()
	# The buried depth is collider geometry, not the thing under test, so read it
	# to recover each box's actual RISE above its base line.
	var ni_consts: Dictionary = (load(SCRIPT_NORTHERN_ISLE) as GDScript).get_script_constant_map()
	var drop_below: float = ni_consts.get("BARRIER_DROP_BELOW", 1.0)
	for prefix: String in ["FenceCollision", "RedBarrierCollision", "InnerRailCollision"]:
		var bodies := _bodies_with_prefix(root, prefix)
		assert_int(bodies.size()).is_greater_equal(2)
		var shapes: Array[CollisionShape3D] = []
		for body in bodies:
			assert_int(body.collision_layer).is_equal(1)
			assert_int(body.collision_mask).is_equal(1)
			shapes.append_array(_shapes_of(body))
		assert_int(shapes.size()).is_equal(NorthernIsleLayout.TOTAL_POINTS)
		var min_top := INF
		var max_rise := -INF
		for shape in shapes:
			var box := shape.shape as BoxShape3D
			assert_that(box).is_not_null()
			if box == null:
				continue
			# Long enough to overlap its neighbour: no seam at a curve.
			assert_float(box.size.z).is_greater(expected_spacing)
			# Thick enough to be a wall, thin enough not to intrude on tarmac.
			assert_float(box.size.x).is_between(0.1, 0.6)
			min_top = minf(min_top, box.size.y)
			max_rise = maxf(max_rise, box.size.y - drop_below)
		if prefix == "FenceCollision":
			assert_float(min_top).is_greater_equal(OvalDressing.FENCE_PANEL_TOP)
			assert_float(max_rise).is_between(OvalDressing.FENCE_PANEL_TOP, OvalDressing.FENCE_PANEL_TOP + MAX_TOP_MARGIN)
		elif prefix == "RedBarrierCollision":
			assert_float(min_top).is_greater_equal(1.5)
			assert_float(max_rise).is_between(RED_BARRIER_VISUAL_TOP, RED_BARRIER_VISUAL_TOP + MAX_TOP_MARGIN)
		else:
			assert_float(min_top).is_greater_equal(TrackBuilder.RAIL_HEIGHT)
			assert_float(max_rise).is_between(TrackBuilder.RAIL_HEIGHT, TrackBuilder.RAIL_HEIGHT + MAX_TOP_MARGIN)

# --- wiring -----------------------------------------------------------------

## The real scene's `_ready` must actually build the colliders (the builder test
## above would happily pass with the call deleted from `_ready`).
func test_scene_ready_builds_barrier_colliders() -> void:
	var packed := load(SCENE_NORTHERN_ISLE) as PackedScene
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
	assert_int(_all_shapes(root).size()).is_equal(3 * NorthernIsleLayout.TOTAL_POINTS)
	for prefix: String in ["FenceCollision", "RedBarrierCollision", "InnerRailCollision"]:
		var shapes := _bodies_with_prefix(root, prefix)
		assert_bool(shapes.is_empty()).is_false()

# --- behaviour --------------------------------------------------------------

## Three pushers fired at the three chains cannot cross them, and a control
## pusher fired outward proves the simulation actually integrates (no false
## green from a physics-less tree).
func test_pushers_cannot_cross_the_barriers() -> void:
	_build_into_host()

	var road_z := NorthernIsleLayout.TURN_RADIUS
	var fence_z := road_z + NorthernIsleLayout.WIDTH * 0.5 + OvalDressing.FENCE_OFFSET
	var red_z := road_z + NorthernIsleLayout.WIDTH * 0.5 + OvalDressing.BARRIER_OFFSET
	var rail_z := road_z - (NorthernIsleLayout.WIDTH * 0.5 + TrackBuilder.RAIL_GAP)

	# Beyond the red barrier, pushed inward at the track.
	var outside := _pusher(red_z + 1.8, -1.0)
	# In the 0.6 m gap between the fence line and the red barrier, pushed inward:
	# only the catch fence can stop this one.
	var in_gap := _pusher(fence_z + 0.8, -1.0)
	# Infield side of the rail, pushed outward at the track.
	var infield := _pusher(rail_z - 2.4, 1.0)
	# Outward into open ground: nothing to hit, so it must travel freely.
	var control := _pusher(red_z + 4.8, 1.0)

	for _i in PUSH_FRAMES:
		await get_tree().physics_frame

	# ~20 m of travel at 60 Hz if unimpeded: the simulation really did run.
	assert_float(control.global_position.z).is_greater_equal(red_z + 4.8 + 10.0)
	# The red barrier held the outer pusher before its own lateral line.
	assert_float(outside.global_position.z).is_greater_equal(red_z - BODY_HALF)
	# The catch fence held the gap pusher before the fence line.
	assert_float(in_gap.global_position.z).is_greater_equal(fence_z - 0.2)
	# The inner rail held the infield pusher before it could reach the tarmac:
	# contact sits at ~rail_z - 0.3, through-the-rail would be > rail_z + BODY_HALF.
	assert_float(infield.global_position.z).is_less_equal(rail_z + BODY_HALF)
	# And it did move toward the rail (not teleported/never integrated).
	assert_float(infield.global_position.z).is_greater(rail_z - 1.5)
