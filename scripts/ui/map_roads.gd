# scripts/ui/map_roads.gd
class_name MapRoads
extends RefCounted

## Static helpers shared by the minimap and the pause-menu map so both answer
## "where are the roads" the same way, and both reuse the same world->screen
## math. No node required; every function is deterministic and headless-safe.

const ROAD_GROUP := "road_network"
const OPEN_WORLD_GROUP := "open_world"

## World-map terrain composite: the pause map samples a height provider on a
## discrete grid and tints each cell by elevation (satellite-map look, FH6-style)
## plus a subtle NW-light hillshade. Everything below is pure/deterministic, so
## headless tests can assert exact channel orderings without a Terrain3D.
const HILLSHADE_STRENGTH := 0.3
const WATER_LEVEL := 0.0
const WATER_DEEP := -8.0
const VEGETATED_LOW := 15.0
const VEGETATED_HIGH := 60.0
const ALPINE_LOW := 250.0
const ROCK_SNOW := 700.0
const COLOR_ABYSS := Color(0.06, 0.13, 0.32)
const COLOR_WATER := Color(0.12, 0.26, 0.50)
const COLOR_LOWLAND := Color(0.16, 0.42, 0.13)
const COLOR_MIDLAND := Color(0.35, 0.45, 0.18)
const COLOR_HIGHLAND := Color(0.60, 0.30, 0.16)
const COLOR_ROCK := Color(0.58, 0.48, 0.40)
const COLOR_SNOW := Color(0.86, 0.87, 0.90)

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

## Shared "where am I" marker: the minimap and the pause map draw the player as
## the same white-and-cyan chevron so it is unmistakable over every terrain tint
## and POI pin. All constants below are the single source of truth both maps
## read; marker_style() bundles them so tests can lock the two maps to one look.
const MARKER_CORE := Color(1.0, 1.0, 1.0, 1.0)          # pure-white chevron body
const MARKER_ACCENT := Color(0.0, 0.9, 1.0, 1.0)        # cyan rim + halo ring
const MARKER_OUTLINE := Color(0.01, 0.02, 0.06, 1.0)    # near-black under-pin
const MARKER_HALO := Color(0.0, 0.9, 1.0, 0.30)
const MARKER_SIZE := 10.0                 # tip distance from the chevron centre
const MARKER_PULSE_PERIOD := 2.6          # seconds per full halo pulse
const MARKER_PULSE_STEP := 0.12           # redraw cadence for the pulse (seconds)

static func marker_style() -> Dictionary:
	return {
		"core": MARKER_CORE,
		"accent": MARKER_ACCENT,
		"outline": MARKER_OUTLINE,
		"halo": MARKER_HALO,
		"size": MARKER_SIZE,
		"pulse_period": MARKER_PULSE_PERIOD,
	}

## Screen-space draw angle (radians, y-down) of a world heading `facing` on the
## north-up pause map: world +x renders right, world +z renders down, so the
## on-screen direction of the heading is normalize(facing.x, facing.z).
static func marker_world_angle(facing: Vector3) -> float:
	return atan2(facing.z, facing.x)

## Same conversion for the minimap. The minimap is north-up too (player-centred,
## roads fixed; see world_to_local_points()), so its chevron runs along the same
## screen orientation as the pause map. The name stays separate because a future
## rotating/car-up minimap would need a different (heading-offset) conversion.
static func marker_minimap_angle(facing: Vector3) -> float:
	return atan2(facing.z, facing.x)

## The chevron's three corners (tip, left wing, right wing) for a marker centred
## at `center` pointing along `draw_angle` with `size` = tip distance. Pure
## geometry so tests can pin the arrow to the map's orientation headlessly.
static func marker_chevron(center: Vector2, draw_angle: float, size: float = MARKER_SIZE) -> PackedVector2Array:
	var dir := Vector2(cos(draw_angle), sin(draw_angle))
	var perp := Vector2(-dir.y, dir.x)
	var tip := center + dir * size
	var tail := center - dir * size * 0.4
	return PackedVector2Array([
		tip,
		tail + perp * size * 0.62,
		tail - perp * size * 0.62,
	])

## Draws the shared player chevron on a canvas (call ONLY from that canvas' own
## _draw(), like Control/Control2D does). Layered back-to-front: a dim pulsing
## cyan halo ring, a near-black under-pin triangle, a cyan accent triangle, and
## the pure-white core chevron. `draw_angle` comes from marker_world_angle() /
## marker_minimap_angle(); `time` (seconds) drives the subtle halo pulse. Pure
## static: no scene access, so both maps' markers stay pixel-identical.
static func draw_player_marker(canvas: CanvasItem, center: Vector2, draw_angle: float, time: float, size: float = MARKER_SIZE) -> void:
	if canvas == null:
		return
	var pulse := 0.5 + 0.5 * sin(TAU * time / MARKER_PULSE_PERIOD)
	var halo := Color(MARKER_HALO.r, MARKER_HALO.g, MARKER_HALO.b,
		clampf(MARKER_HALO.a * (0.55 + 0.45 * pulse), 0.0, 1.0))
	canvas.draw_arc(center, size * (1.45 + 0.35 * pulse), 0.0, TAU, 40, halo, 2.5, true)
	_draw_marker_layer(canvas, center, draw_angle, size, 1.3, MARKER_OUTLINE)
	_draw_marker_layer(canvas, center, draw_angle, size, 1.16, MARKER_ACCENT)
	_draw_marker_layer(canvas, center, draw_angle, size, 1.0, MARKER_CORE)

static func _draw_marker_layer(canvas: CanvasItem, center: Vector2, draw_angle: float, size: float, grow: float, color: Color) -> void:
	var corners := marker_chevron(center, draw_angle, size)
	var points := PackedVector2Array()
	for i in 3:
		points.append(center + (corners[i] - center) * grow)
	canvas.draw_colored_polygon(points, color)

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

## Height source for the pause-map terrain composite: the Terrain3D node of the
## open world. Resolved via the "open_world" group first, else a tree-walk that
## duck-types a node exposing `data.get_height()` (Terrain3DData). The world map
## additionally prefers TerrainSeeder's baked corridor cache (see
## resolve_seeder()), so heights are known even for regions that have not been
## baked on the live Terrain3D yet. Returns an empty Callable when neither a
## Terrain3D nor a seeder is present, which keeps the map deterministic and
## headless-safe: without terrain the map simply draws roads-only.
static func resolve_seeder(node: Node) -> Object:
	if node == null or node.get_tree() == null:
		return null
	var root: Node = node.get_tree().root
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var candidate: Node = pending.pop_back()
		if candidate.has_method("baked_region_height"):
			return candidate
		pending.append_array(candidate.get_children())
	return null

static func _find_terrain(node: Node) -> Object:
	if node == null or node.get_tree() == null:
		return null
	var grouped := node.get_tree().get_first_node_in_group(OPEN_WORLD_GROUP)
	if grouped != null:
		var found := _walk_for_terrain(grouped)
		if found != null:
			return found
	return _walk_for_terrain(node.get_tree().root)

static func _walk_for_terrain(root: Node) -> Object:
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var candidate: Node = pending.pop_back()
		if _is_terrain(candidate):
			return candidate
		pending.append_array(candidate.get_children())
	return null

static func _is_terrain(candidate: Node) -> bool:
	if candidate == null:
		return false
	var data = candidate.get("data")
	return data != null and data.has_method("get_height")

## Discrete-grid sampler contract: a Callable(Vector2 xz) -> float that returns
## the world height at (x, 0, z). This is what terrain_cells() multiples.
static func height_from_terrain(node: Node) -> Callable:
	var terrain := _find_terrain(node)
	if terrain == null:
		return Callable()
	var terrain_ref: Object = terrain
	return func(xz: Vector2) -> float:
		var data = terrain_ref.get("data")
		if data == null:
			return 0.0
		var h := float(data.get_height(Vector3(xz.x, 0.0, xz.y)))
		return h if is_finite(h) else 0.0

## Satellite-biome color for a height, sampled from a deterministic palette:
## deep water -> shore -> vegetated lowlands -> highland browns -> rock -> snow.
## Channel orderings: blue in water, green dominant in the vegetated band, red
## dominant on the alpine/rock highlands.
static func biome_color(height: float) -> Color:
	if not is_finite(height):
		return COLOR_WATER
	if height < WATER_LEVEL:
		var t := clampf((height - WATER_DEEP) / (WATER_LEVEL - WATER_DEEP), 0.0, 1.0)
		return COLOR_ABYSS.lerp(COLOR_WATER, t)
	if height < VEGETATED_LOW:
		return COLOR_WATER.lerp(COLOR_LOWLAND, clampf(height / VEGETATED_LOW, 0.0, 1.0))
	if height < VEGETATED_HIGH:
		return COLOR_LOWLAND.lerp(COLOR_MIDLAND, (height - VEGETATED_LOW) / (VEGETATED_HIGH - VEGETATED_LOW))
	if height < ALPINE_LOW:
		return COLOR_MIDLAND.lerp(COLOR_HIGHLAND, (height - VEGETATED_HIGH) / (ALPINE_LOW - VEGETATED_HIGH))
	if height < ROCK_SNOW:
		return COLOR_HIGHLAND.lerp(COLOR_ROCK, (height - ALPINE_LOW) / (ROCK_SNOW - ALPINE_LOW))
	return COLOR_SNOW

## NW-light hillshade: a cell rising toward the north or west (positive
## east_delta/south_delta slope away from the light) darkens; faces rising
## toward the light brighten. Bounded to [1 - strength, 1 + strength] via tanh so
## the map never goes black or blown out, and the factor is exactly 1.0 on flat
## ground. Apply it by multiplying a biome_color() result.
static func hillshade_energy(east_delta: float, south_delta: float, strength: float = HILLSHADE_STRENGTH) -> float:
	var facing := -(east_delta + south_delta)
	return 1.0 + tanh(facing * 0.5) * clampf(strength, 0.0, 1.0)

static func shade_color(color: Color, energy: float) -> Color:
	return Color(
		clampf(color.r * energy, 0.0, 1.0),
		clampf(color.g * energy, 0.0, 1.0),
		clampf(color.b * energy, 0.0, 1.0),
		color.a)

## XZ world coordinates -> the Terrain3D region grid location containing them.
static func region_loc(xz: Vector2, region_size: float = 256.0) -> Vector2i:
	return Vector2i(floori(xz.x / region_size), floori(xz.y / region_size))

## Sample a height provider on a uniform grid over a compute_fit() world AABB and
## produce the cell rectangles to draw under the road network. Cells are
## intentionally aligned to the SAME world_to_screen fit the roads use, so the
## terrain and the road polylines stay pixel-aligned on the rectangular pause
## map. Returns an Array of {"rect": Rect2, "color": Color} in row-major order.
static func terrain_cells(fit: Dictionary, provider: Callable, cells_x: int, cells_z: int, strength: float = HILLSHADE_STRENGTH) -> Array:
	if cells_x <= 0 or cells_z <= 0 or not provider.is_valid():
		return []
	var world_min: Vector2 = fit["world_min"]
	var world_max: Vector2 = fit["world_max"]
	var span := world_max - world_min
	span.x = maxf(span.x, 1.0)
	span.y = maxf(span.y, 1.0)
	var cw := span.x / float(cells_x)
	var ch := span.y / float(cells_z)
	var origin: Vector2 = fit["origin"]
	var scale: float = fit["scale"]
	var heights := PackedFloat32Array()
	heights.resize(cells_x * cells_z)
	for jz in cells_z:
		var wz := world_min.y + (float(jz) + 0.5) * ch
		var row := jz * cells_x
		for ix in cells_x:
			var wx := world_min.x + (float(ix) + 0.5) * cw
			var h := float(provider.call(Vector2(wx, wz)))
			heights[row + ix] = h if is_finite(h) else 0.0
	var out: Array = []
	for jz in cells_z:
		var row := jz * cells_x
		var row_south := mini(jz + 1, cells_z - 1) * cells_x
		for ix in cells_x:
			var h := heights[row + ix]
			var east := heights[row + mini(ix + 1, cells_x - 1)] - h
			var south := heights[row_south + ix] - h
			var energy := hillshade_energy(east, south, strength)
			var rect_px := Vector2(cw, ch) * scale
			var tl: Vector2 = origin + Vector2(float(ix) * cw, float(jz) * ch) * scale
			out.append({
				"rect": Rect2(tl, rect_px),
				"color": shade_color(biome_color(h), energy),
			})
	return out

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

## The route path the minimap draws: the SAME route polyline world_map uses
## (route_polyline on the shared static route), transformed with the minimap's
## car-up convention (world_to_local_points around the player) and clipped to
## the circular radius. Empty when there is no route or source. Both maps share
## one source of truth, so they can never disagree about the route.
static func minimap_route_path(rect: Rect2, player_pos: Vector3, source: Object = null, zoom: float = 0.2) -> PackedVector2Array:
	if source == null or not has_route:
		return PackedVector2Array()
	var route := route_polyline(source, player_pos, route_target)
	if route.size() < 2:
		return PackedVector2Array()
	var center := rect.get_center()
	var radius := minf(rect.size.x, rect.size.y) * 0.5
	var local := world_to_local_points(route, player_pos, center, zoom)
	return clip_circle(local, center, radius)