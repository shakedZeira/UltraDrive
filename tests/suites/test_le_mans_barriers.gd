# tests/suites/test_le_mans_barriers.gd
extends GdUnitTestSuite

## Gate for the PHYSICAL Le Mans barriers (scripts/track/le_mans_dressing.gd
## `_build_barrier_colliders`). Before this wall existed the armco / tyre walls were
## MultiMesh visuals with no collision at all (`RailSide.NONE`), so a car drove
## straight through them.
##
## Objective proof, three layers (no wall clock anywhere):
##   * LAP PROBE -- rays cast from the carriageway across the barrier line at three
##     heights every 25 m of centreline on BOTH sides, and a dense 1 m horizontal
##     continuity sweep; every sample must hit the barrier collider (never pass
##     through, never stop on the terrain instead). A downward ray per sample checks
##     the wall top clears the (elevated) road edge and the terrain, and the probe
##     is shown to FAIL when the colliders are removed (a probe that cannot fail is
##     worthless).
##   * CRASH TEST -- plain RigidBody3D "cars" (the real car's 1.8 x 0.5 x 4.0 box, no
##     CCD, no gravity) fired at the wall at 30 / 60 / 90 m/s and 15 / 45 / 90 deg
##     from 18 places round the lap, both sides, must never get past the barrier line.
##   * STRUCTURE -- budget, layers, friction, thickness, overlap, determinism.

const SCENE_LE_MANS := "res://scenes/track/le_mans.tscn"

## Independent specs (NOT read from the script, so loosening it cannot loosen the gate).
const MIN_WALL_ABOVE_ROAD := 1.8      ## wall top over the road edge (m): the way over the top must
												## be longer than the deepest first-contact penetration (1.5 m at 90 m/s)
const MAX_WALL_ABOVE_ROAD := 3.0      ## ... and not an absurd invisible tower
const MIN_WALL_ABOVE_GROUND := 1.0
const MIN_THICKNESS := 3.0
const MAX_BOXES := 6000               ## collision-shape budget for the whole lap
const SAMPLE_M := 25.0
const DENSE_M := 1.0
const RAY_HEIGHTS: Array[float] = [0.15, 0.6, 1.0]

var _scene: Node3D = null
var _pts: Array[Vector3] = []
var _banks: PackedFloat32Array = PackedFloat32Array()


func after_test() -> void:
	RaceManager._checkpoints_dirty = true
	RaceManager.rival_centerline = []
	RaceManager.consume_pending_race()
	for child in get_children():
		if child is Checkpoint:
			child.free()


# --- helpers -------------------------------------------------------------------

func _load(runner_holder: Array) -> LeMansDressing:
	var runner := scene_runner(SCENE_LE_MANS)
	runner_holder.append(runner)
	await runner.simulate_frames(5)
	_scene = runner.scene() as Node3D
	return _scene.get_node_or_null("Dressing") as LeMansDressing


## Road frame at arc `s`, built with the ROAD MESH's own convention: the centre is
## INTERPOLATED between the two neighbouring centerline points (the mesh is linear
## between them, so the lerped centre lies on the asphalt), the tangent is the
## lerp of the two neighbour-to-neighbour tangents, the cross is banked. NOT snapped
## to the nearest point: the barrier line moves up to 0.4 m sideways per metre of
## arc where it flares out behind a sand trap, so a station that is 1.4 m off along
## the road is 0.5 m off sideways and a "0.2 m behind the line" probe lands in front
## of the wall. NOT `LeMansLayout.frame_at_arc` either: its +-0.25 m tangent differs
## by a few degrees in the Ford chicane (a 0.4 m lateral error at a 7.6 m offset).
func _sframe(s: float) -> Dictionary:
	if _pts.is_empty():
		_pts = LeMansLayout.build_centerline()
		_banks = LeMansLayout.build_bank_profile()
	var n := _pts.size()
	var idx := fposmod(s, LeMansLayout.perimeter()) / LeMansLayout.spacing()
	var i0 := int(idx) % n
	var i1 := (i0 + 1) % n
	var frac := idx - floorf(idx)
	var f0 := _pts[i1] - _pts[(i0 - 1 + n) % n]
	var f1 := _pts[(i1 + 1) % n] - _pts[i0]
	var forward := f0.lerp(f1, frac).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var bank := lerpf(float(_banks[i0]), float(_banks[i1]), frac)
	return {
		"center": _pts[i0].lerp(_pts[i1], frac),
		"forward": forward,
		"right": right,
		"cross": right * cos(bank) - Vector3.UP * sin(bank),
		"bank": bank,
	}


func _is_barrier(collider: Object) -> bool:
	var node := collider as Node
	if node == null:
		return false
	return String(node.name).begins_with("BarrierCollision_")


## Lateral (+ = right) of world point `p` relative to station `f`.
func _lateral_of(f: Dictionary, p: Vector3) -> float:
	var c: Vector3 = f["center"]
	var r: Vector3 = f["right"]
	return (p.x - c.x) * r.x + (p.z - c.z) * r.z


## One horizontal ray from `inner` m (lateral, signed) to `outer` m at height `h`
## above the road edge at arc `s`. Returns {"hit": bool, "barrier": bool, "lat": float}.
func _ray_across(space: PhysicsDirectSpaceState3D, s: float, side: float, h: float,
		dressing: LeMansDressing) -> Dictionary:
	var f := _sframe(s)
	var c: Vector3 = f["center"]
	var r: Vector3 = f["right"]
	var cross: Vector3 = f["cross"]
	var edge_y := c.y + cross.y * side * LeMansLayout.WIDTH_M * 0.5
	var off := absf(dressing.barrier_offset(s, side))
	var a := c + r * side * (LeMansLayout.WIDTH_M * 0.5 - 2.0)
	a.y = edge_y + h
	var b := c + r * side * (off + 3.0)
	b.y = edge_y + h
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	var res := space.intersect_ray(q)
	if res.is_empty():
		return {"hit": false, "barrier": false, "lat": INF}
	return {"hit": true, "barrier": _is_barrier(res["collider"]),
		"lat": absf(_lateral_of(f, res["position"])), "off": off}


## Runs the lap probe; returns counts + the list of failing (arc, side, kind).
func _probe_lap(space: PhysicsDirectSpaceState3D, dressing: LeMansDressing) -> Dictionary:
	var failures: Array[String] = []
	var samples := 0
	var hits := 0
	var perimeter := LeMansLayout.perimeter()
	var n := int(perimeter / SAMPLE_M)
	for k in n:
		var s := float(k) * SAMPLE_M
		for side: float in [1.0, -1.0]:
			for h in RAY_HEIGHTS:
				samples += 1
				var res := _ray_across(space, s, side, h, dressing)
				if bool(res["barrier"]):
					# Must hit the wall's face: at/inside the armco line, within 1 m of it.
					var off: float = res["off"]
					var lat: float = res["lat"]
					if lat <= off + 0.35 and lat >= off - 1.0:
						hits += 1
						continue
					failures.append("s=%.0f side=%+.0f h=%.2f wall face at %.2f (line %.2f)" % [s, side, h, lat, off])
				elif bool(res["hit"]):
					failures.append("s=%.0f side=%+.0f h=%.2f stopped by non-barrier (lat %.2f)" % [s, side, h, res["lat"]])
				else:
					failures.append("s=%.0f side=%+.0f h=%.2f NO HIT (through)" % [s, side, h])
	return {"samples": samples, "hits": hits, "failures": failures}


# --- structure ------------------------------------------------------------------

func test_structure_budget_layers_and_determinism() -> void:
	var probe := LeMansDressing.new()
	probe.configure(LeMansLayout.build_centerline(), LeMansLayout.build_bank_profile(),
		LeMansLayout.WIDTH_M)
	probe.build()
	var count := probe.barrier_box_count()
	print("[le_mans_barriers] boxes=%d" % count)
	assert_int(count).is_greater(500)
	assert_int(count).is_less(MAX_BOXES)
	var root := probe.barrier_root()
	assert_that(root).is_not_null()
	if root == null:
		probe.free()
		return
	var shapes := 0
	var min_thick := INF
	var min_h := INF
	for body in root.get_children():
		var sb := body as StaticBody3D
		assert_that(sb).is_not_null()
		assert_int(sb.collision_layer).is_equal(1)
		assert_int(sb.collision_mask).is_equal(1)
		assert_that(sb.physics_material_override).is_not_null()
		for cs in sb.get_children():
			var box := (cs as CollisionShape3D).shape as BoxShape3D
			assert_that(box).is_not_null()
			shapes += 1
			min_thick = minf(min_thick, box.size.x)
			min_h = minf(min_h, box.size.y)
	assert_int(shapes).is_equal(count)
	assert_float(min_thick).is_greater_equal(MIN_THICKNESS)
	assert_float(min_h).is_greater_equal(MIN_WALL_ABOVE_GROUND + 0.5)
	# Deterministic: a second build emits the identical wall.
	var probe2 := LeMansDressing.new()
	probe2.configure(LeMansLayout.build_centerline(), LeMansLayout.build_bank_profile(),
		LeMansLayout.WIDTH_M)
	probe2.build()
	assert_int(probe2.barrier_box_count()).is_equal(count)
	# Rebuilding in place replaces (never stacks) the wall.
	probe.build()
	assert_int(probe.barrier_box_count()).is_equal(count)
	assert_int(probe.get_child_count()).is_equal(
		probe2.get_child_count())
	probe2.free()
	probe.free()
	# The export gate really disables it.
	var off := LeMansDressing.new()
	off.build_barrier_colliders = false
	off.configure(LeMansLayout.build_centerline(), LeMansLayout.build_bank_profile(),
		LeMansLayout.WIDTH_M)
	off.build()
	assert_int(off.barrier_box_count()).is_equal(0)
	assert_that(off.barrier_root()).is_null()
	off.free()


# --- lap probe -------------------------------------------------------------------

func test_every_lap_sample_has_a_solid_wall_on_both_sides() -> void:
	var holder: Array = []
	var dressing := await _load(holder)
	assert_that(dressing).is_not_null()
	if dressing == null:
		return
	assert_that(dressing.barrier_root()).is_not_null()
	var space: PhysicsDirectSpaceState3D = _scene.get_world_3d().direct_space_state

	# Control: with the wall removed the SAME probe must report failures, otherwise
	# it proves nothing. (Done on a duplicate-free basis: toggle the bodies' layer.)
	var bodies: Array[StaticBody3D] = []
	for b in dressing.barrier_root().get_children():
		bodies.append(b as StaticBody3D)
	for b in bodies:
		b.collision_layer = 0
	await get_tree().physics_frame
	await get_tree().physics_frame
	var without := _probe_lap(space, dressing)
	for b in bodies:
		b.collision_layer = 1
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("[le_mans_barriers] BEFORE (no wall): %d/%d samples hit a barrier" % [
		without["hits"], without["samples"]])
	assert_int(without["hits"]).is_equal(0)

	var with_wall := _probe_lap(space, dressing)
	var failures: Array = with_wall["failures"]
	print("[le_mans_barriers] AFTER: %d/%d samples hit the wall, %d failures" % [
		with_wall["hits"], with_wall["samples"], failures.size()])
	for i in mini(failures.size(), 25):
		print("[le_mans_barriers]   FAIL ", failures[i])
	assert_int(failures.size()).is_equal(0)
	assert_int(with_wall["hits"]).is_equal(with_wall["samples"])


## Dense 1 m continuity sweep (one mid-height ray per metre of arc, both sides):
## a gap narrower than the 25 m lap sample (a join, a taper, the lap seam, the S/F
## line, a trap window edge) cannot hide.
func test_no_gap_anywhere_along_either_side() -> void:
	var holder: Array = []
	var dressing := await _load(holder)
	if dressing == null:
		assert_that(dressing).is_not_null()
		return
	var space: PhysicsDirectSpaceState3D = _scene.get_world_3d().direct_space_state
	var perimeter := LeMansLayout.perimeter()
	var n := int(perimeter / DENSE_M)
	var gaps: Array[String] = []
	var tested := 0
	for k in n:
		var s := float(k) * DENSE_M
		for side: float in [1.0, -1.0]:
			tested += 1
			var res := _ray_across(space, s, side, 0.6, dressing)
			if not bool(res["barrier"]):
				gaps.append("s=%.0f side=%+.0f" % [s, side])
	print("[le_mans_barriers] dense sweep: %d rays, %d gaps" % [tested, gaps.size()])
	for i in mini(gaps.size(), 25):
		print("[le_mans_barriers]   GAP ", gaps[i])
	assert_int(gaps.size()).is_equal(0)


## The wall top clears the elevated road edge and the local terrain by a car's
## height at every lap sample (a downward ray along the barrier line).
func test_wall_height_follows_the_elevated_road() -> void:
	var holder: Array = []
	var dressing := await _load(holder)
	if dressing == null:
		assert_that(dressing).is_not_null()
		return
	var space: PhysicsDirectSpaceState3D = _scene.get_world_3d().direct_space_state
	var perimeter := LeMansLayout.perimeter()
	var n := int(perimeter / SAMPLE_M)
	var bad: Array[String] = []
	var min_above_road := INF
	var max_above_road := -INF
	for k in n:
		var s := float(k) * SAMPLE_M
		for side: float in [1.0, -1.0]:
			var f := _sframe(s)
			var c: Vector3 = f["center"]
			var r: Vector3 = f["right"]
			var cross: Vector3 = f["cross"]
			var off := dressing.barrier_offset(s, side)
			var p := c + r * (off + side * 0.6)   # 0.6 m behind the armco line (inside the wall)
			var edge_y := c.y + cross.y * side * LeMansLayout.WIDTH_M * 0.5
			var ground_y: float = _scene.call("terrain_height", p.x, p.z)
			var q := PhysicsRayQueryParameters3D.create(
				Vector3(p.x, edge_y + 6.0, p.z), Vector3(p.x, edge_y - 3.0, p.z), 1)
			var res := space.intersect_ray(q)
			if res.is_empty() or not _is_barrier(res["collider"]):
				bad.append("s=%.0f side=%+.0f no wall top under the line (%s)" % [
					s, side, "nothing" if res.is_empty() else str((res["collider"] as Node).get_path())])
				continue
			var top: float = (res["position"] as Vector3).y
			min_above_road = minf(min_above_road, top - edge_y)
			max_above_road = maxf(max_above_road, top - edge_y)
			if top - edge_y < MIN_WALL_ABOVE_ROAD or top - ground_y < MIN_WALL_ABOVE_GROUND \
					or top - edge_y > MAX_WALL_ABOVE_ROAD:
				bad.append("s=%.0f side=%+.0f top %.2f over road, %.2f over ground" % [
					s, side, top - edge_y, top - ground_y])
	print("[le_mans_barriers] wall top over road edge: min %.2f max %.2f" % [
		min_above_road, max_above_road])
	for i in mini(bad.size(), 25):
		print("[le_mans_barriers]   HEIGHT ", bad[i])
	assert_int(bad.size()).is_equal(0)


# --- crash test --------------------------------------------------------------------

## Test "cars": the real car's collision box, no gravity, no CCD (pessimistic).
func _crash_body(host: Node3D, s: float, side: float, speed: float, angle_deg: float,
		dressing: LeMansDressing) -> RigidBody3D:
	var f := _sframe(s)
	var c: Vector3 = f["center"]
	var fwd: Vector3 = f["forward"]
	fwd.y = 0.0
	fwd = fwd.normalized()
	var r: Vector3 = f["right"]
	var body := RigidBody3D.new()
	body.mass = 1100.0
	# Gravity ON: the car rides the (banked, climbing) road surface, so the wall is
	# met at the height a real car meets it, not at a fixed level above the centre.
	body.linear_damp = 0.0
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 0.5, 4.0)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var a := deg_to_rad(angle_deg)
	var dir := fwd * cos(a) + r * side * sin(a)
	body.position = Vector3(c.x, c.y + 0.6, c.z)
	body.basis = Basis(Vector3.UP, atan2(-dir.x, -dir.z))
	host.add_child(body)
	body.linear_velocity = dir * speed
	body.set_meta("start_y", c.y)
	body.set_meta("start_s", s)
	body.set_meta("side", side)
	return body


func test_crash_test_car_is_stopped_at_30_60_90_ms() -> void:
	var holder: Array = []
	var dressing := await _load(holder)
	if dressing == null:
		assert_that(dressing).is_not_null()
		return
	var host := Node3D.new()
	host.name = "CrashHost"
	_scene.add_child(host)
	var pts: Array[Vector3] = LeMansLayout.build_centerline()
	var n := pts.size()
	var step := LeMansLayout.spacing()
	var perimeter := LeMansLayout.perimeter()
	# 18 places: every 1/12 lap + the corner landmarks (traps, bends, climbs).
	var arcs: Array[float] = []
	for i in 12:
		arcs.append(perimeter * (float(i) + 0.37) / 12.0)
	for ch in [LeMansLayout.LANDMARK_DUNLOP_BRIDGE, LeMansLayout.LANDMARK_TERTRE_ROUGE,
			LeMansLayout.LANDMARK_MULSANNE_CORNER, LeMansLayout.LANDMARK_INDY,
			LeMansLayout.LANDMARK_ARNAGE, LeMansLayout.LANDMARK_FORD]:
		arcs.append(LeMansLayout.arc_at_chainage(ch))
	var combos: Array[Vector2] = [Vector2(30.0, 15.0), Vector2(60.0, 45.0), Vector2(90.0, 90.0),
		Vector2(60.0, 15.0), Vector2(90.0, 45.0), Vector2(45.0, 90.0)]
	var escapes: Array[String] = []
	var total := 0
	for combo in combos:
		var bodies: Array[RigidBody3D] = []
		for s in arcs:
			for side: float in [1.0, -1.0]:
				# The two sides start 40 m apart along the road: bodies spawned fully
				# interpenetrated shove each other away (the historical flake of the
				# Barcelona pusher test) and would read as a false "escape".
				bodies.append(_crash_body(host, s + (0.0 if side > 0.0 else 40.0), side,
					combo.x, combo.y, dressing))
		var max_lat: Dictionary = {}
		var max_dy: Dictionary = {}
		for _frame_i in 45:
			await get_tree().physics_frame
			for body in bodies:
				var s0: float = body.get_meta("start_s")
				var side: float = body.get_meta("side")
				var i0 := int(s0 / step)
				var best := INF
				var best_i := i0
				for d in range(-140, 141):
					var j := ((i0 + d) % n + n) % n
					var dd := Vector2(pts[j].x - body.position.x, pts[j].z - body.position.z).length_squared()
					if dd < best:
						best = dd
						best_i = j
				var fwd3 := (pts[(best_i + 1) % n] - pts[(best_i - 1 + n) % n])
				var right3 := fwd3.cross(Vector3.UP).normalized()
				var lat := ((body.position.x - pts[best_i].x) * right3.x
					+ (body.position.z - pts[best_i].z) * right3.z) * side
				var key := body.get_instance_id()
				max_lat[key] = maxf(float(max_lat.get(key, -INF)), lat)
				max_dy[key] = maxf(float(max_dy.get(key, -INF)),
					body.position.y - float(body.get_meta("start_y")))
		for body in bodies:
			total += 1
			var s1: float = body.get_meta("start_s")
			var side1: float = body.get_meta("side")
			var limit := absf(dressing.barrier_offset(s1, side1)) + 0.3
			# NB: measured at the body CENTRE; the box is 0.9 m half-width so a held
			# car's centre stays >= 0.9 m inside the wall's front face.
			var reached: float = max_lat[body.get_instance_id()]
			if reached > limit or not body.position.is_finite() or body.position.y < float(body.get_meta("start_y")) - 5.0:
				escapes.append("v=%.0f ang=%.0f s=%.0f side=%+.0f reached lat %.2f (limit %.2f) max rise %.2f" % [
					combo.x, combo.y, s1, side1, reached, limit, float(max_dy[body.get_instance_id()])])
			body.queue_free()
		await get_tree().physics_frame
	print("[le_mans_barriers] crash test: %d runs, %d escapes" % [total, escapes.size()])
	for e in escapes:
		print("[le_mans_barriers]   ESCAPE ", e)
	assert_int(escapes.size()).is_equal(0)
	assert_int(total).is_equal(arcs.size() * 2 * combos.size())
	host.queue_free()


# --- the real car -----------------------------------------------------------------

## The shipped player car (VehiclePhysics RigidBody + raycast wheels), thrown at the
## wall from several places on both sides. It must never get past the wall (every
## combo). Moderate hits (<= 40 m/s) must also leave it on the ground side of sanity:
## shed speed and not be bounced high. The 50 m/s / 35 deg hit only has to be held:
## the car's own tyre grip rolls it over at ~28 m/s of lateral speed, which is the
## car's physics, not the wall.
func test_real_player_car_is_stopped_and_not_launched() -> void:
	var holder: Array = []
	var dressing := await _load(holder)
	if dressing == null:
		assert_that(dressing).is_not_null()
		return
	var car := _scene.get_node_or_null("%PlayerCar") as VehiclePhysics
	assert_that(car).is_not_null()
	if car == null:
		return
	var runner: GdUnitSceneRunner = holder[0]
	var perimeter := LeMansLayout.perimeter()
	var pts: Array[Vector3] = LeMansLayout.build_centerline()
	var n := pts.size()
	var step := LeMansLayout.spacing()
	var arcs: Array[float] = [perimeter * 0.1, perimeter * 0.33, perimeter * 0.58, perimeter * 0.8,
		LeMansLayout.arc_at_chainage(LeMansLayout.LANDMARK_ARNAGE)]
	# x = speed (m/s), y = angle to the road (deg), z = 1 when the "sane" checks apply.
	var combos: Array[Vector3] = [Vector3(40.0, 25.0, 1.0), Vector3(30.0, 45.0, 1.0),
		Vector3(50.0, 35.0, 0.0)]
	var bad: Array[String] = []
	var runs := 0
	for combo in combos:
		for s in arcs:
			for side: float in [1.0, -1.0]:
				var f := _sframe(s)
				var c: Vector3 = f["center"]
				var fwd: Vector3 = f["forward"]
				fwd.y = 0.0
				fwd = fwd.normalized()
				var r: Vector3 = f["right"]
				var dir := fwd * cos(deg_to_rad(combo.y)) + r * side * sin(deg_to_rad(combo.y))
				car.freeze = false
				car.global_position = c + Vector3(0.0, 0.8, 0.0)
				car.global_rotation = Vector3(0.0, atan2(-dir.x, -dir.z), 0.0)
				car.linear_velocity = dir * combo.x
				car.angular_velocity = Vector3.ZERO
				var line := absf(dressing.barrier_offset(s, side))
				var max_lat := -INF
				var max_rise := -INF
				var i0 := int(s / step)
				for _i in 150:
					await runner.simulate_frames(1)
					# Lateral / height relative to the NEAREST centreline point (the car
					# slides tens of metres along a road that bends and climbs).
					var best := INF
					var best_i := i0
					for d in range(-140, 141):
						var j := ((i0 + d) % n + n) % n
						var dd := Vector2(pts[j].x - car.global_position.x, pts[j].z - car.global_position.z).length_squared()
						if dd < best:
							best = dd
							best_i = j
					var right3 := (pts[(best_i + 1) % n] - pts[(best_i - 1 + n) % n]).cross(Vector3.UP).normalized()
					var lat := ((car.global_position.x - pts[best_i].x) * right3.x
						+ (car.global_position.z - pts[best_i].z) * right3.z) * side
					max_lat = maxf(max_lat, lat)
					max_rise = maxf(max_rise, car.global_position.y - pts[best_i].y)
				runs += 1
				var speed_after := car.linear_velocity.length()
				print("[le_mans_barriers] real car v=%.0f ang=%.0f s=%.0f side=%+.0f: max lat %.2f (line %.2f) max rise %.2f speed after %.1f" % [
					combo.x, combo.y, s, side, max_lat, line, max_rise, speed_after])
				var held := max_lat <= line + 0.3 and car.global_position.is_finite()
				var sane := combo.z < 0.5 or (max_rise <= 3.0 and speed_after <= combo.x - 1.0)
				if not (held and sane):
					bad.append("v=%.0f ang=%.0f s=%.0f side=%+.0f lat %.2f line %.2f rise %.2f speed %.1f" % [
						combo.x, combo.y, s, side, max_lat, line, max_rise, speed_after])
	for b in bad:
		print("[le_mans_barriers]   REAL-CAR ESCAPE ", b)
	assert_int(runs).is_equal(combos.size() * arcs.size() * 2)
	assert_int(bad.size()).is_equal(0)


## Out-of-bounds recovery: the walls make leaving the lap impossible, so the only
## remaining recovery is the car's own reset (reset key / fall below y=-20). That
## must put the car back ON THE ROAD at the grid, not at the scene's authored node
## position. (`VehiclePhysics._spawn_point` is captured in the car's own _ready,
## BEFORE `le_mans.gd` moves the car to the grid.)
func test_reset_returns_the_car_to_the_grid_on_the_road() -> void:
	var holder: Array = []
	var dressing := await _load(holder)
	if dressing == null:
		assert_that(dressing).is_not_null()
		return
	var car := _scene.get_node_or_null("%PlayerCar") as VehiclePhysics
	assert_that(car).is_not_null()
	if car == null:
		return
	var pts: Array[Vector3] = LeMansLayout.build_centerline()
	var grid: Vector3 = pts[LeMansLayout.GRID_INDEX]
	var spawn: Vector3 = car.get("_spawn_point")
	print("[le_mans_barriers] car spawn point %s, grid %s" % [spawn, grid])
	assert_float(Vector2(spawn.x - grid.x, spawn.z - grid.z).length()).is_less(2.0)
	assert_float(absf(spawn.y - grid.y)).is_less(3.0)
	# And the actual reset: throw the car far off, press reset, it lands on the grid.
	car.freeze = false
	car.global_position = grid + Vector3(300.0, 40.0, 300.0)
	# A direct global_position write only reaches the physics server on the next
	# step: flush it, or it lands after the respawn's server-side write and undoes it.
	for _i in 2:
		await get_tree().physics_frame
	assert_bool(car.try_manual_respawn(true, false)).is_true()
	for _i in 5:
		await get_tree().physics_frame
	var after := car.global_position
	assert_float(Vector2(after.x - grid.x, after.z - grid.z).length()).is_less(3.0)
	assert_float(absf(after.y - grid.y)).is_less(5.0)
