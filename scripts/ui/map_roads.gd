# scripts/ui/map_roads.gd
class_name MapRoads
extends RefCounted

## Static helpers shared by the minimap and the pause-menu map so both answer
## "where are the roads" the same way, and both reuse the same world->screen
## math. No node required; every function is deterministic and headless-safe.

const ROAD_GROUP := "road_network"

## Shared GPS route state: the pause-map sets the destination, the minimap reads
## it. Static so both maps share one source of truth without needing a scene node.
static var route_target: Vector3 = Vector3.ZERO
static var has_route := false

static func set_route(target: Vector3) -> void:
	route_target = target
	has_route = true

static func clear_route() -> void:
	has_route = false
	route_target = Vector3.ZERO

## Best road source for the scene: the first node in the "road_network" group,
## else the first node anywhere in the tree that exposes get_roads().
static func resolve_road_source(node: Node) -> Object:
	if node == null:
		return null
	var tree := node.get_tree()
	if tree != null:
		var grouped := tree.get_first_node_in_group(ROAD_GROUP)
		if grouped != null and grouped.has_method("get_roads"):
			return grouped
		return _walk_for_roads(tree.root)
	return _walk_for_roads(node)

static func _walk_for_roads(root: Node) -> Object:
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var candidate: Node = pending.pop_back()
		if candidate.has_method("get_roads"):
			return candidate
		pending.append_array(candidate.get_children())
	return null

## Road chains (each an Array of Vector3 world points) from any source object
## that exposes get_roads(). Empty array when nothing is available.
static func get_roads(source: Object) -> Array:
	if source != null and source.has_method("get_roads"):
		var roads = source.get_roads()
		if roads != null and roads is Array:
			return roads
	return []

## Best discovery source for the scene: the first node in the
## "world_discovery" group (WorldDiscovery registers itself there). The maps
## fall back to drawing every road when this returns null.
static func resolve_discovery_source(node: Node) -> Object:
	if node == null or node.get_tree() == null:
		return null
	return node.get_tree().get_first_node_in_group(WorldDiscovery.GROUP_NAME)

## Cheap signature for "roads changed": chain count plus the first point of
## each chain. Roads are static after the open-world bootstrap, so comparing
## this string is enough to detect when the cached polylines are stale.
static func signature(source: Object) -> String:
	var roads := get_roads(source)
	var parts := PackedStringArray()
	parts.append(str(roads.size()))
	for chain in roads:
		if chain is Array and not chain.is_empty():
			var p: Vector3 = chain[0]
			parts.append("%.1f,%.1f" % [p.x, p.z])
	return "|".join(parts)

## World (x, z) -> screen local using the minimap convention: +x right,
## +z down, scaled by zoom around screen_center. Shared by the minimap.
static func world_to_local_points(chain: Array, center_world: Vector3, screen_center: Vector2, zoom: float) -> PackedVector2Array:
	var world_center := Vector2(center_world.x, center_world.z)
	var out := PackedVector2Array()
	out.resize(chain.size())
	for i in chain.size():
		var w: Vector3 = chain[i]
		out[i] = screen_center + (Vector2(w.x, w.z) - world_center) * zoom
	return out

## Fit the given world content into draw_size with a uniform scale, letterboxed
## and centered, north-up (world +x right, world +z down). Returns a Dictionary:
##   "origin": Vector2 - top-left of the fitted content in screen space
##   "scale": float   - identical on the x and z axes
##   "world_min"/"world_max": Vector2 - world-space AABB of the content
static func compute_fit(content_points: Array, fallback: Vector3, draw_size: Vector2, inset: float) -> Dictionary:
	var world_min := Vector2(fallback.x, fallback.z)
	var world_max := world_min
	var any_content := false
	for p in content_points:
		var w: Vector3 = p
		if not any_content:
			world_min = Vector2(w.x, w.z)
			world_max = world_min
			any_content = true
		else:
			world_min.x = minf(world_min.x, w.x)
			world_min.y = minf(world_min.y, w.z)
			world_max.x = maxf(world_max.x, w.x)
			world_max.y = maxf(world_max.y, w.z)
	var span := world_max - world_min
	span.x = maxf(span.x, 1.0)
	span.y = maxf(span.y, 1.0)
	var avail := Vector2(maxf(draw_size.x - inset * 2.0, 1.0), maxf(draw_size.y - inset * 2.0, 1.0))
	var scale := minf(avail.x / span.x, avail.y / span.y)
	if scale <= 0.0 or not is_finite(scale):
		scale = 1.0
	var content_size := span * scale
	return {
		"origin": (draw_size - content_size) * 0.5,
		"scale": scale,
		"world_min": world_min,
		"world_max": world_max,
	}

## World-space position -> screen position using a fit from compute_fit().
static func world_to_screen(world_pos: Vector3, fit: Dictionary) -> Vector2:
	var origin: Vector2 = fit["origin"]
	var scale: float = fit["scale"]
	var world_min: Vector2 = fit["world_min"]
	return origin + (Vector2(world_pos.x, world_pos.z) - world_min) * scale

## Clip a polyline to a circle of radius around center. Boundary-crossing
## segments are preserved by inserting the exact on-circle points, so every
## returned point satisfies distance(center) <= radius and the roads remain
## contiguous where they enter/leave the minimap.
static func clip_circle(points: PackedVector2Array, center: Vector2, radius: float) -> PackedVector2Array:
	if points.is_empty():
		return points
	var out := PackedVector2Array()
	var prev: Vector2 = points[0]
	var prev_hit := prev.distance_to(center) <= radius
	if prev_hit:
		out.append(prev)
	for i in range(1, points.size()):
		var curr: Vector2 = points[i]
		var curr_hit := curr.distance_to(center) <= radius
		if prev_hit and curr_hit:
			out.append(curr)
		elif prev_hit and not curr_hit:
			var exit_point: Variant = _segment_circle_hit(prev, curr, center, radius, false)
			if exit_point != null:
				out.append(exit_point)
		elif curr_hit and not prev_hit:
			var entry_point: Variant = _segment_circle_hit(prev, curr, center, radius, true)
			if entry_point != null:
				out.append(entry_point)
			out.append(curr)
		else:
			var crossing: Variant = _segment_circle_hit(prev, curr, center, radius, true)
			if crossing != null:
				out.append(crossing)
		prev = curr
		prev_hit = curr_hit
	return out

## Intersection of segment (prev, curr) with the circle. Returns the on-circle
## Vector2 closest to prev when want_first is true, else the one closest to
## curr; null when the segment does not touch the disk.
static func _segment_circle_hit(prev: Vector2, curr: Vector2, center: Vector2, radius: float, want_first: bool) -> Variant:
	var d := curr - prev
	var f := prev - center
	var a := d.dot(d)
	if a <= 0.000001:
		return null
	var b := 2.0 * f.dot(d)
	var c := f.dot(f) - radius * radius
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return null
	var sqrt_disc := sqrt(disc)
	var ta := (-b - sqrt_disc) / (2.0 * a)
	var tb := (-b + sqrt_disc) / (2.0 * a)
	if want_first:
		var t := ta if ta >= 0.0 else tb
		if t < 0.0 or t > 1.0:
			return null
		return prev + d * t
	var t_exit := tb if tb <= 1.0 else ta
	if t_exit < 0.0 or t_exit > 1.0:
		return null
	return prev + d * t_exit

## Inverse of world_to_screen(): screen position -> world XZ (Y=0) using a fit
## from compute_fit(). Used by the pause-map to map a mouse click to a world
## position for fast-travel and route-setting.
static func screen_to_world(screen_pos: Vector2, fit: Dictionary) -> Vector3:
	var origin: Vector2 = fit["origin"]
	var scale: float = fit["scale"]
	var world_min: Vector2 = fit["world_min"]
	var wx := (screen_pos.x - origin.x) / scale + world_min.x
	var wz := (screen_pos.y - origin.y) / scale + world_min.y
	return Vector3(wx, 0.0, wz)

## Concatenate a hop-route into a single world-space polyline. `source` is any
## object exposing get_roads(), nearest_road_id() and route() (i.e. RoadNetwork).
## From the concatenated chain sequence the direct sub-route between the nearest
## on-chain point to `from_pos` and the nearest on-chain point to `to_pos` is
## extracted, with no degenerate duplicate points at chain junctions.
## Returns an empty Array when the route is impossible or trivial (< 2 points).
static func route_polyline(source: Object, from_pos: Vector3, to_pos: Vector3) -> Array[Vector3]:
	if source == null:
		return []
	if not (source.has_method("get_roads") and source.has_method("nearest_road_id") and source.has_method("route")):
		return []
	var from_id: int = source.nearest_road_id(from_pos)
	var to_id: int = source.nearest_road_id(to_pos)
	if from_id < 0 or to_id < 0:
		return []
	var chain_seq: PackedInt32Array = source.route(from_id, to_id)
	if chain_seq.is_empty():
		return []
	var roads: Array = source.get_roads()
	# Concatenate chains, deduplicate exact junction points.
	var concat: Array[Vector3] = []
	for road_id in chain_seq:
		var chain: Array = roads[road_id]
		for wp_v in chain:
			var wp: Vector3 = wp_v
			if concat.size() > 0 and wp.distance_squared_to(concat[concat.size() - 1]) < 0.001:
				continue
			concat.append(wp)
	if concat.size() < 2:
		return concat
	# Find nearest indices to from_pos and to_pos along the concatenated polyline.
	var fi := _nearest_concat_index(concat, from_pos)
	var ti := _nearest_concat_index(concat, to_pos)
	# Extract the sub-route between fi and ti.
	var same_chain := chain_seq.size() == 1
	var out: Array[Vector3] = []
	if fi == ti:
		# from == to (same nearest point, e.g. tapping the road you are on): the
		# GPS shows the whole enclosing chain so the route line is meaningful.
		return _dedup_points(concat)
	elif same_chain:
		if fi <= ti:
			for i in range(fi, ti + 1):
				out.append(concat[i])
		else:
			for i in range(ti, fi + 1):
				out.append(concat[i])
			out.reverse()
	else:
		if ti >= fi:
			for i in range(fi, ti + 1):
				out.append(concat[i])
		else:
			for i in range(fi, concat.size()):
				out.append(concat[i])
			for i in range(0, ti + 1):
				out.append(concat[i])
	# Final dedup of any residual consecutive duplicates.
	return _dedup_points(out)

static func _nearest_concat_index(concat: Array[Vector3], world_pos: Vector3) -> int:
	var best := 0
	var best_sq := INF
	for i in concat.size():
		var sq := Vector2(world_pos.x - concat[i].x, world_pos.z - concat[i].z).length_squared()
		if sq < best_sq:
			best_sq = sq
			best = i
	return best

static func _dedup_points(points: Array[Vector3]) -> Array[Vector3]:
	if points.size() < 2:
		return points
	var out: Array[Vector3] = [points[0]]
	for i in range(1, points.size()):
		if points[i].distance_squared_to(out[out.size() - 1]) > 0.001:
			out.append(points[i])
	return out