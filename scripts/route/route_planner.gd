# scripts/route/route_planner.gd
class_name RoutePlanner
extends RefCounted

## RefCounted GPS helpers against any route-capable source (a RoadNetwork or a
## stub exposing get_roads()/nearest_road_id()/route()). snap() projects the
## player onto the active MapRoads route polyline and returns distance to the
## line plus the arc length along it; navigate_to() sets/clears the shared
## route state and doubles as the "Navigate to POI/event" seam (item 7). Pure
## math, deterministic, headless-safe.

const NO_ROUTE := {"road_id": -1, "dist": -1.0, "arc": 0.0}

var _source: Object = null

func _init(source: Object = null) -> void:
	_source = source

## Snap a world position onto the current route: nearest point on the route
## polyline, its distance from the player, and the arc length still to be
## travelled along the route to reach the destination (route_polyline re-roots
## its polyline at the player's nearest on-route point, so the route origin is
## the player itself and the meaningful arc is what remains ahead). Returns
## NO_ROUTE when no source or route exists.
func snap(player_pos: Vector3) -> Dictionary:
	if _source == null or not MapRoads.has_route:
		return NO_ROUTE.duplicate()
	var route := MapRoads.route_polyline(_source, player_pos, MapRoads.route_target)
	if route.size() < 2:
		return NO_ROUTE.duplicate()
	var cum := _cumulative_arcs(route)
	var total := cum[cum.size() - 1]
	var fi := _nearest_index(route, player_pos)
	var best_dist := INF
	var foot_arc := cum[fi]
	for seg in [_pair(fi - 1, fi), _pair(fi, fi + 1)]:
		var a: int = seg[0]
		var b: int = seg[1]
		if a < 0 or b >= route.size():
			continue
		var proj := _project_segment(player_pos, route[a], route[b], cum[a], cum[b])
		if proj["dist"] < best_dist:
			best_dist = proj["dist"]
			foot_arc = proj["arc"]
	return {
		"road_id": _nearest_road_id(player_pos),
		"dist": best_dist,
		"arc": clampf(total - foot_arc, 0.0, total),
	}

## Work-item 5 seam: set the shared GPS destination and validate that a route
## to it exists. False (with route state cleared) when unreachable or no source.
func navigate_to(player_pos: Vector3, target: Vector3) -> bool:
	if _source == null:
		return false
	MapRoads.set_route(target)
	if MapRoads.route_polyline(_source, player_pos, target).size() >= 2:
		return true
	MapRoads.clear_route()
	return false

static func _pair(a: int, b: int) -> Array[int]:
	return [a, b]

static func _cumulative_arcs(route: Array[Vector3]) -> Array[float]:
	var cum: Array[float] = [0.0]
	for i in range(1, route.size()):
		cum.append(cum[i - 1] + route[i - 1].distance_to(route[i]))
	return cum

static func _nearest_index(route: Array[Vector3], pos: Vector3) -> int:
	var best := 0
	var best_sq := INF
	for i in route.size():
		var dx := pos.x - route[i].x
		var dz := pos.z - route[i].z
		var sq := dx * dx + dz * dz
		if sq < best_sq:
			best_sq = sq
			best = i
	return best

static func _project_segment(pos: Vector3, a: Vector3, b: Vector3, arc_a: float, arc_b: float) -> Dictionary:
	var ab_x := b.x - a.x
	var ab_z := b.z - a.z
	var len_sq := ab_x * ab_x + ab_z * ab_z
	if len_sq <= 0.0001:
		var dx := pos.x - a.x
		var dz := pos.z - a.z
		return {"dist": sqrt(dx * dx + dz * dz), "arc": arc_a}
	var t := clampf(((pos.x - a.x) * ab_x + (pos.z - a.z) * ab_z) / len_sq, 0.0, 1.0)
	var proj := Vector3(a.x + ab_x * t, 0.0, a.z + ab_z * t)
	var dx := pos.x - proj.x
	var dz := pos.z - proj.z
	return {"dist": sqrt(dx * dx + dz * dz), "arc": arc_a + (arc_b - arc_a) * t}

func _nearest_road_id(pos: Vector3) -> int:
	if _source != null and _source.has_method("nearest_road_id"):
		return int(_source.nearest_road_id(pos))
	return -1