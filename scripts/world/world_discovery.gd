# scripts/world/world_discovery.gd
class_name WorldDiscovery
extends Node

## P5 fog-of-war: per-road-segment visited bits fed as the player drives.
##
## Data model: for every road def registered through configure(), the visited
## unit is the *segment* between two consecutive centerline points (a closed
## chain wraps its final point back to the first, so a closed N-point road has
## N segments). Visited state is a Dictionary of road_id -> sorted
## Array[int] of visited segment indices, mutated only by monotonic reveal
## (bits are set, never cleared, and restore() only merges saved bits in).
##
## Pure + deterministic: no frames, no scene access required; every helper is
## plain XZ-plane segment math so the whole class is headless-testable.
##
## Save: store()/restore() serialize the visited dict (String keys, plain
## int Arrays for JSON); save_to_slot()/load_from_slot() bridge the 3-slot
## SaveManager schema under the additive "discovery" key.

const GROUP_NAME := "world_discovery"
const DEFAULT_SLOT := 0
const SAVE_KEY := "discovery"

const DEFAULT_REVEAL_RADIUS := 90.0
## Threshold for is_revealed()/try_snap_to_revealed(): a position counts as a
## valid "revealed road point" when the nearest revealed segment is within this
## XZ distance (map clicks are reverse-mapped to Y=0, so Y is ignored).
const DEFAULT_SNAP_DISTANCE := 30.0

var reveal_radius: float = DEFAULT_REVEAL_RADIUS

var _road_defs: Array[RoadDef] = []
var _visited: Dictionary = {}  # road_id(int) -> Array[int] of visited segment indices
var _visited_set: Dictionary = {}
var _fully_visited := false

func _ready() -> void:
	add_to_group(GROUP_NAME)

func configure(defs: Array[RoadDef]) -> void:
	_road_defs = defs.duplicate()
	_sanitize_visited()

## Marks every segment whose XZ distance from `position` is within
## reveal_radius as visited. Monotonic: already-visited bits are preserved.
func reveal_at(position: Vector3) -> void:
	reveal_at_radius(position, reveal_radius)

func reveal_at_radius(position: Vector3, radius: float) -> void:
	if radius <= 0.0 or _fully_visited:
		return
	for road_id in _road_defs.size():
		var add := PackedInt32Array()
		var segment_count := _segment_count(road_id)
		var visited_set: Dictionary = _visited_set.get(road_id, {})
		for seg in segment_count:
			if visited_set.has(seg):
				continue
			var a := _seg_start(road_id, seg)
			var b := _seg_end(road_id, seg)
			if WorldDiscovery.point_segment_distance_xz(position, a, b) <= radius:
				add.append(seg)
		_mark_visited(road_id, add)
	var all_complete := true
	for road_id in _road_defs.size():
		if _visited_set.get(road_id, {}).size() < _segment_count(road_id):
			all_complete = false
			break
	_fully_visited = all_complete

## True when the nearest road segment to `position` is visited and lies within
## `threshold` XZ distance (Y is ignored, matching the pause-map click space).
func is_revealed(position: Vector3, threshold: float = DEFAULT_SNAP_DISTANCE) -> bool:
	var nearest := _nearest_segment(position)
	if nearest["road_id"] < 0 or nearest["dist"] > threshold:
		return false
	var visited_mask: Array = _visited.get(nearest["road_id"], [])
	return nearest["segment_index"] in visited_mask

## Projects `position` onto the closest REVEALED segment (XZ), interpolating
## the road's real Y along that segment so teleports land on tarmac. Returns
## Vector3.INF when no revealed segment is within DEFAULT_SNAP_DISTANCE.
func try_snap_to_revealed(position: Vector3) -> Vector3:
	return try_snap_to_revealed_distance(position, DEFAULT_SNAP_DISTANCE)

func try_snap_to_revealed_distance(position: Vector3, threshold: float) -> Vector3:
	var best_road := -1
	var best_seg := -1
	var best_dist := INF
	for road_id in _road_defs.size():
		var mask: Array = _visited.get(road_id, [])
		var segment_count := _segment_count(road_id)
		for seg in segment_count:
			if seg not in mask:
				continue
			var a := _seg_start(road_id, seg)
			var b := _seg_end(road_id, seg)
			var d := WorldDiscovery.point_segment_distance_xz(position, a, b)
			if d < best_dist:
				best_dist = d
				best_road = road_id
				best_seg = seg
	if best_road < 0 or best_dist > threshold:
		return Vector3.INF
	return WorldDiscovery.closest_point_on_segment(
		position, _seg_start(best_road, best_seg), _seg_end(best_road, best_seg))

## The centerline points of `road_def` that anchor at least one visited
## segment, in chain order with consecutive duplicates merged. Returns an
## empty Array when the def is not registered or has nothing visited.
func revealed_points_for(road_def: RoadDef) -> Array[Vector3]:
	var road_id := _road_id_of(road_def)
	if road_id < 0:
		return []
	return _revealed_points_for_id(road_id)

func _revealed_points_for_id(road_id: int) -> Array[Vector3]:
	if road_id < 0 or road_id >= _road_defs.size():
		return []
	var chain: Array[Vector3] = _road_defs[road_id].points
	var mask: Array = _visited.get(road_id, [])
	var out: Array[Vector3] = []
	var segment_count := _segment_count(road_id)
	for seg in segment_count:
		if seg not in mask:
			continue
		var start := _seg_start(road_id, seg)
		var end := _seg_end(road_id, seg)
		if out.is_empty() or (out[out.size() - 1] - start).length_squared() > 0.0001:
			out.append(start)
		var last: Vector3 = out[out.size() - 1]
		if (last - end).length_squared() > 0.0001:
			out.append(end)
	return out

## Sorted list of visited segment indices for a road (a copy; the map layers
## use segment_visited_mask() to colour chains segment-by-segment).
func visited_indices(road_id: int) -> Array[int]:
	var raw: Array = _visited.get(road_id, [])
	var out: Array[int] = []
	for i in raw:
		out.append(int(i))
	return out

## Per-segment visited flags for road_id, sized N-1 for an open chain and N for
## a closed chain (segments 0..N-1 with the last wrapping to point 0). Returns
## an empty Array for unknown roads so callers can fall back to "all visited".
func segment_visited_mask(road_id: int) -> Array[bool]:
	if road_id < 0 or road_id >= _road_defs.size():
		return []
	var count := _segment_count(road_id)
	var mask: Array = _visited.get(road_id, [])
	var out: Array[bool] = []
	for seg in count:
		out.append(seg in mask)
	return out

## Serializes visited state for the save file: { "visited": { road_id: [...] } }
## with String keys because JSON object keys are strings.
func store() -> Dictionary:
	var visited_json := {}
	for road_id: int in _visited:
		visited_json[str(road_id)] = _visited[road_id]
	return {SAVE_KEY: visited_json}

## Merges saved discovery data into the live state. Monotonic: only adds bits,
## and unknown roads or out-of-range indices are ignored.
func restore(data: Dictionary) -> void:
	var visited_json: Dictionary = {}
	var raw: Variant = data.get(SAVE_KEY, {})
	if raw is Dictionary:
		visited_json = raw
	for key in visited_json:
		var road_id := int(key)
		if road_id < 0 or road_id >= _road_defs.size():
			continue
		var indices: Array = visited_json[key]
		var max_seg := _segment_count(road_id)
		var keep := PackedInt32Array()
		for idx_v in indices:
			var idx := int(idx_v)
			if idx >= 0 and idx < max_seg:
				keep.append(idx)
		if keep.size() > 0:
			_mark_visited(road_id, keep)

func save_to_slot(slot: int = DEFAULT_SLOT) -> bool:
	if SaveManager == null:
		return false
	return SaveManager.save_discovery(slot, store())

func load_from_slot(slot: int = DEFAULT_SLOT) -> bool:
	if SaveManager == null:
		return false
	var data: Dictionary = SaveManager.load_discovery(slot)
	if data.is_empty():
		return false
	restore(data)
	return true

## XZ-plane distance from a point to a finite segment (closest-point on the
## segment in 2D). Pure, headless-safe.
static func point_segment_distance_xz(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab_x := b.x - a.x
	var ab_z := b.z - a.z
	var px := point.x - a.x
	var pz := point.z - a.z
	var len_sq := ab_x * ab_x + ab_z * ab_z
	if len_sq <= 0.000001:
		return Vector2(px, pz).length()
	var t := clampf((px * ab_x + pz * ab_z) / len_sq, 0.0, 1.0)
	return Vector2(px - ab_x * t, pz - ab_z * t).length()

## Closest point on a segment to `point`, preserving the segment's real-world
## Y (linearly interpolated at the closest XZ parameter).
static func closest_point_on_segment(point: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var len_sq := dir.length_squared()
	if len_sq <= 0.000001:
		return a
	var t := clampf((Vector2(point.x - a.x, point.z - a.z).dot(Vector2(dir.x, dir.z))) / len_sq, 0.0, 1.0)
	return Vector3(a.x + dir.x * t, a.y + (b.y - a.y) * t, a.z + dir.z * t)

func _nearest_segment(position: Vector3) -> Dictionary:
	var best_road := -1
	var best_seg := -1
	var best_dist := INF
	var best_a := Vector3.ZERO
	var best_b := Vector3.ZERO
	for road_id in _road_defs.size():
		var segment_count := _segment_count(road_id)
		for seg in segment_count:
			var a := _seg_start(road_id, seg)
			var b := _seg_end(road_id, seg)
			var d := WorldDiscovery.point_segment_distance_xz(position, a, b)
			if d < best_dist:
				best_dist = d
				best_road = road_id
				best_seg = seg
				best_a = a
				best_b = b
	return {
		"road_id": best_road,
		"segment_index": best_seg,
		"seg_a": best_a,
		"seg_b": best_b,
		"dist": best_dist,
	}

func _mark_visited(road_id: int, indices: PackedInt32Array) -> void:
	var current: Array = _visited.get(road_id, [])
	var set: Dictionary = _visited_set.get(road_id, {})
	indices.sort()
	for idx in indices:
		if idx not in current:
			current.append(idx)
			set[idx] = true
	current.sort()
	_visited[road_id] = current
	_visited_set[road_id] = set

## Drops stored bits that no longer describe the configured roads (Runs after
## configure() and is intentionally additive elsewhere, so the save merge is
## safe even when the world grew or an older save has stale indices).
func _sanitize_visited() -> void:
	var keep := {}
	var keep_set := {}
	for road_id: int in _visited:
		if road_id < 0 or road_id >= _road_defs.size():
			continue
		var max_seg := _segment_count(road_id)
		var current: Array = _visited[road_id]
		var pruned: Array[int] = []
		var pruned_set := {}
		for i in current:
			var idx := int(i)
			if idx >= 0 and idx < max_seg:
				pruned.append(idx)
				pruned_set[idx] = true
		if pruned.size() > 0:
			keep[road_id] = pruned
			keep_set[road_id] = pruned_set
	_visited = keep
	_visited_set = keep_set
	_fully_visited = false

func _road_id_of(road_def: RoadDef) -> int:
	if road_def == null:
		return -1
	for i in _road_defs.size():
		if _road_defs[i] == road_def:
			return i
	return -1

func _segment_count(road_id: int) -> int:
	if road_id < 0 or road_id >= _road_defs.size():
		return 0
	var chain: Array[Vector3] = _road_defs[road_id].points
	var n := chain.size()
	if n < 2:
		return 0
	if _road_defs[road_id].closed:
		return n
	return n - 1

func _seg_start(road_id: int, seg: int) -> Vector3:
	var chain: Array[Vector3] = _road_defs[road_id].points
	return chain[seg]

func _seg_end(road_id: int, seg: int) -> Vector3:
	var chain: Array[Vector3] = _road_defs[road_id].points
	return chain[(seg + 1) % chain.size()] if _road_defs[road_id].closed else chain[seg + 1]