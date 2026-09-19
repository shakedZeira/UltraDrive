# scripts/route/brake_line.gd
class_name BrakeLine
extends RefCounted

## Curvature probe ahead along the GPS route. Samples the route polyline from
## the player's nearest on-route point out to PROBE_DISTANCE and accumulates the
## signed turn angle in a rolling WINDOW_METERS window, so a corner produces a
## decaying hint as it approaches and passes the player. Pure math, headless
## safe; result is {hint, arrow, distance_m, corner_angle}.

const PROBE_DISTANCE := 120.0
const SAMPLE_STEP := 5.0
const WINDOW_METERS := 30.0
const CORNER_ANGLE := 0.3
const BRAKE_ANGLE := 0.35
const HARD_BRAKE_ANGLE := 0.9
const HARD_BRAKE_DIST := 45.0

var _source: Object = null

func _init(source: Object = null) -> void:
	_source = source

## Returns {hint: none/brake/hard-brake, arrow: left/right/straight,
## distance_m, corner_angle}. hint and arrow are "none"/"straight" (and
## distance_m -1) when there is no route, no reachable route, or no corner
## within PROBE_DISTANCE.
func probe(player_pos: Vector3) -> Dictionary:
	if _source == null or not MapRoads.has_route:
		return _none()
	var route := MapRoads.route_polyline(_source, player_pos, MapRoads.route_target)
	if route.size() < 2:
		return _none()
	return _analyze(route)

func _none() -> Dictionary:
	return {"hint": "none", "arrow": "straight", "distance_m": -1.0, "corner_angle": 0.0}

func _analyze(route: Array[Vector3]) -> Dictionary:
	# Resample the polyline at fixed arc steps away from the start so the turn
	# accumulation is independent of vertex spacing along the road.
	var points := PackedVector3Array()
	var arcs := PackedFloat32Array()
	points.append(route[0])
	arcs.append(0.0)
	var cursor := route[0]
	var traveled := 0.0
	var next_arc := SAMPLE_STEP
	var idx := 0
	while idx < route.size() - 1 and traveled < PROBE_DISTANCE:
		var to := route[idx + 1]
		var seg_len := cursor.distance_to(to)
		if seg_len > 0.000001:
			while next_arc <= traveled + seg_len + 0.000001:
				points.append(cursor.lerp(to, (next_arc - traveled) / seg_len))
				arcs.append(next_arc)
				next_arc += SAMPLE_STEP
			traveled += seg_len
		cursor = to
		idx += 1
	if points.size() < 2:
		return _none()

	# Tangent per sample via a centered difference over the sampled polyline.
	var tangents := PackedVector3Array()
	tangents.resize(points.size())
	for i in points.size():
		var a: Vector3 = points[maxi(i - 1, 0)]
		var b: Vector3 = points[mini(i + 1, points.size() - 1)]
		var d := b - a
		tangents[i] = d.normalized() if d.length() > 1e-6 else Vector3.FORWARD

	# Signed turn angle between each pair of consecutive sample tangents (XZ).
	var steps := PackedFloat32Array()
	steps.resize(maxi(points.size() - 1, 0))
	for i in range(points.size() - 1):
		var t := tangents[i]
		var t2 := tangents[i + 1]
		steps[i] = atan2(t.x * t2.z - t.z * t2.x, t.x * t2.x + t.z * t2.z)

	# Rolling window centred on each sample; the strongest |sum| marks the apex
	# of the best corner ahead, and its centre distance is the corner distance.
	var half := WINDOW_METERS * 0.5
	var best_sum := 0.0
	var best_arc := -1.0
	for i in points.size():
		var d := arcs[i]
		var acc := 0.0
		for j in steps.size():
			if arcs[j] >= d - half - 0.001 and arcs[j + 1] <= d + half + 0.001:
				acc += steps[j]
		if absf(acc) > absf(best_sum):
			best_sum = acc
			best_arc = d

	var corner_angle := absf(best_sum)
	var hint := "none"
	var arrow := "straight"
	var distance_m := -1.0
	if corner_angle >= CORNER_ANGLE:
		arrow = "left" if best_sum > 0.0 else "right"
		distance_m = best_arc
		if corner_angle >= HARD_BRAKE_ANGLE and best_arc <= HARD_BRAKE_DIST:
			hint = "hard-brake"
		elif corner_angle >= BRAKE_ANGLE:
			hint = "brake"
	return {"hint": hint, "arrow": arrow, "distance_m": distance_m, "corner_angle": corner_angle}