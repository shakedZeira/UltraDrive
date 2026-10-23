# scripts/world/road_graph.gd
class_name RoadGraph
extends RefCounted

## Pure, deterministic road-network topology: distance-based adjacency derived
## from per-road point polylines plus unweighted hop-count routing. No node or
## tree access; mirrors the static-pure pattern of MapRoads.

static func build_topology(defs: Array, link_threshold: float) -> Dictionary:
	var adjacency := {}
	var junction_list: Array = []
	for i in defs.size():
		adjacency[i] = PackedInt32Array()
	# Per-road segment boxes and a coarse XZ grid of them, built once and shared
	# by every pair (see _closest_segments_near: same answer as the full
	# all-pairs scan whenever the pair links, at a fraction of the cost; the
	# open-world network took 21 s on the main thread before).
	var boxes: Array = []
	var grids: Array = []
	for i in defs.size():
		var d := defs[i] as RoadDef
		if d == null or d.points.is_empty():
			boxes.append(PackedFloat32Array())
			grids.append({})
			continue
		var bx := _segment_boxes(d.points)
		boxes.append(bx)
		grids.append(_segment_grid(bx, link_threshold + NEAR_EPS))
	for i in range(defs.size()):
		for j in range(i + 1, defs.size()):
			var def_a := defs[i] as RoadDef
			var def_b := defs[j] as RoadDef
			if def_a == null or def_b == null:
				continue
			var a: Array[Vector3] = def_a.points
			var b: Array[Vector3] = def_b.points
			if a.is_empty() or b.is_empty():
				continue
			var closest := _closest_segments_near(a, b, boxes[i], boxes[j], grids[j], link_threshold)
			var dist: float = closest["dist"]
			if dist < link_threshold:
				var ia: PackedInt32Array = adjacency[i]
				var ib: PackedInt32Array = adjacency[j]
				ia.append(j)
				ib.append(i)
				adjacency[i] = ia
				adjacency[j] = ib
				junction_list.append({
					"road_a": i,
					"road_b": j,
					"segment_a": closest["seg_a"],
					"segment_b": closest["seg_b"],
					"point": (closest["on_a"] + closest["on_b"]) * 0.5,
					"dist": dist,
				})
	for key: int in adjacency.keys():
		var arr: PackedInt32Array = adjacency[key]
		arr.sort()
		adjacency[key] = arr
	var cmp := func(a: Dictionary, b: Dictionary) -> bool:
		var a_min: int = mini(a["road_a"], a["road_b"])
		var b_min: int = mini(b["road_a"], b["road_b"])
		if a_min != b_min:
			return a_min < b_min
		return maxi(a["road_a"], a["road_b"]) < maxi(b["road_a"], b["road_b"])
	junction_list.sort_custom(cmp)
	return {"adjacency": adjacency, "junctions": junction_list}

static func route(adjacency: Dictionary, from_id: int, to_id: int) -> PackedInt32Array:
	if from_id == to_id:
		return PackedInt32Array([from_id])
	if not adjacency.has(from_id) or not adjacency.has(to_id):
		return PackedInt32Array()
	var prev := {}
	prev[from_id] = -1
	var frontier: Array[int] = [from_id]
	var head := 0
	while head < frontier.size():
		var current: int = frontier[head]
		head += 1
		if current == to_id:
			break
		var neighbors: PackedInt32Array = adjacency[current]
		neighbors.sort()
		for nb in neighbors:
			if not prev.has(nb):
				prev[nb] = current
				frontier.append(nb)
	if not prev.has(to_id):
		return PackedInt32Array()
	var path: Array[int] = []
	var node := to_id
	while node != -1:
		path.append(node)
		node = prev[node]
	path.reverse()
	var out := PackedInt32Array()
	for n in path:
		out.append(n)
	return out

static func chain_distance(a: Array[Vector3], b: Array[Vector3]) -> float:
	if a.is_empty() or b.is_empty():
		return INF
	var best := INF
	var count_a := _segment_count(a)
	var count_b := _segment_count(b)
	for ia in count_a:
		for ib in count_b:
			var data := _segment_data(_seg_start(a, ia), _seg_end(a, ia), _seg_start(b, ib), _seg_end(b, ib))
			var d: float = data["dist"]
			if d < best:
				best = d
	return best

## Closest segments (as indices into each chain's segment list), closest points
## and their distance for the two polylines.
static func _closest_segments(a: Array[Vector3], b: Array[Vector3]) -> Dictionary:
	var best_dist := INF
	var best_seg_a := 0
	var best_seg_b := 0
	var best_on_a := Vector3.ZERO
	var best_on_b := Vector3.ZERO
	var count_a := _segment_count(a)
	var count_b := _segment_count(b)
	for ia in count_a:
		for ib in count_b:
			var data := _segment_data(_seg_start(a, ia), _seg_end(a, ia), _seg_start(b, ib), _seg_end(b, ib))
			var d: float = data["dist"]
			if d < best_dist:
				best_dist = d
				best_seg_a = ia
				best_seg_b = ib
				best_on_a = data["on_a"]
				best_on_b = data["on_b"]
	return {
		"dist": best_dist,
		"seg_a": best_seg_a,
		"seg_b": best_seg_b,
		"on_a": best_on_a,
		"on_b": best_on_b,
	}

## Cell size (m) of the per-road segment grid used by build_topology.
const NEAR_CELL := 64.0
## Safety margin on the box rejection so float rounding can never skip a pair
## whose true distance is just under the threshold.
const NEAR_EPS := 0.01

## Axis-aligned box per segment: [minx, miny, minz, maxx, maxy, maxz] * count.
static func _segment_boxes(pts: Array[Vector3]) -> PackedFloat32Array:
	var count := _segment_count(pts)
	var out := PackedFloat32Array()
	out.resize(count * 6)
	for s in count:
		var p := _seg_start(pts, s)
		var q := _seg_end(pts, s)
		out[s * 6] = minf(p.x, q.x)
		out[s * 6 + 1] = minf(p.y, q.y)
		out[s * 6 + 2] = minf(p.z, q.z)
		out[s * 6 + 3] = maxf(p.x, q.x)
		out[s * 6 + 4] = maxf(p.y, q.y)
		out[s * 6 + 5] = maxf(p.z, q.z)
	return out

## { Vector2i XZ cell -> PackedInt32Array segment indices }: each segment is
## registered in every cell its XZ box, grown by `pad`, touches.
static func _segment_grid(boxes: PackedFloat32Array, pad: float) -> Dictionary:
	var grid := {}
	for s in boxes.size() / 6:
		var x0 := floori((boxes[s * 6] - pad) / NEAR_CELL)
		var z0 := floori((boxes[s * 6 + 2] - pad) / NEAR_CELL)
		var x1 := floori((boxes[s * 6 + 3] + pad) / NEAR_CELL)
		var z1 := floori((boxes[s * 6 + 5] + pad) / NEAR_CELL)
		for cz in range(z0, z1 + 1):
			for cx in range(x0, x1 + 1):
				var key := Vector2i(cx, cz)
				var list: PackedInt32Array = grid.get(key, PackedInt32Array())
				list.append(s)
				grid[key] = list
	return grid

## Distance between two segment boxes (a lower bound of the segment distance).
static func _box_gap(ba: PackedFloat32Array, ia: int, bb: PackedFloat32Array, ib: int) -> float:
	var dx := maxf(0.0, maxf(ba[ia * 6] - bb[ib * 6 + 3], bb[ib * 6] - ba[ia * 6 + 3]))
	var dy := maxf(0.0, maxf(ba[ia * 6 + 1] - bb[ib * 6 + 4], bb[ib * 6 + 1] - ba[ia * 6 + 4]))
	var dz := maxf(0.0, maxf(ba[ia * 6 + 2] - bb[ib * 6 + 5], bb[ib * 6 + 2] - ba[ia * 6 + 5]))
	return sqrt(dx * dx + dy * dy + dz * dz)

## `_closest_segments` restricted to segment pairs that can be closer than
## `threshold`. Whenever the true closest distance is below `threshold` the
## result is IDENTICAL to `_closest_segments` (same pair, same points, same
## first-minimum tie-break): pairs are visited in the same (seg_a, seg_b)
## order and a skipped pair is provably >= threshold away (its boxes are; the
## grid only drops pairs whose XZ boxes are more than threshold apart). When
## nothing is that close it returns dist = INF; callers only test `< threshold`.
static func _closest_segments_near(a: Array[Vector3], b: Array[Vector3], boxes_a: PackedFloat32Array, boxes_b: PackedFloat32Array, grid_b: Dictionary, threshold: float) -> Dictionary:
	var best_dist := INF
	var best_seg_a := 0
	var best_seg_b := 0
	var best_on_a := Vector3.ZERO
	var best_on_b := Vector3.ZERO
	var count_a := _segment_count(a)
	var reject := threshold + NEAR_EPS
	var cand := PackedInt32Array()
	for ia in count_a:
		cand.resize(0)
		var x0 := floori(boxes_a[ia * 6] / NEAR_CELL)
		var z0 := floori(boxes_a[ia * 6 + 2] / NEAR_CELL)
		var x1 := floori(boxes_a[ia * 6 + 3] / NEAR_CELL)
		var z1 := floori(boxes_a[ia * 6 + 5] / NEAR_CELL)
		for cz in range(z0, z1 + 1):
			for cx in range(x0, x1 + 1):
				var key := Vector2i(cx, cz)
				if grid_b.has(key):
					cand.append_array(grid_b[key] as PackedInt32Array)
		if cand.is_empty():
			continue
		cand.sort()
		var prev := -1
		for ib in cand:
			if ib == prev:
				continue
			prev = ib
			if _box_gap(boxes_a, ia, boxes_b, ib) > reject:
				continue
			var data := _segment_data(_seg_start(a, ia), _seg_end(a, ia), _seg_start(b, ib), _seg_end(b, ib))
			var d: float = data["dist"]
			if d < best_dist:
				best_dist = d
				best_seg_a = ia
				best_seg_b = ib
				best_on_a = data["on_a"]
				best_on_b = data["on_b"]
	return {
		"dist": best_dist,
		"seg_a": best_seg_a,
		"seg_b": best_seg_b,
		"on_a": best_on_a,
		"on_b": best_on_b,
	}

## A 1-point chain is one degenerate (point) segment; an N-point chain has N-1.
static func _segment_count(pts: Array[Vector3]) -> int:
	return maxi(pts.size() - 1, 1)

static func _seg_start(pts: Array[Vector3], i: int) -> Vector3:
	return pts[i]

static func _seg_end(pts: Array[Vector3], i: int) -> Vector3:
	return pts[i + 1] if i + 1 < pts.size() else pts[i]

## Closest distance and closest points for two finite segments (Ericson's
## closest-point algorithm); degenerate point segments fall out naturally.
static func _segment_data(a_from: Vector3, a_to: Vector3, b_from: Vector3, b_to: Vector3) -> Dictionary:
	var d1 := a_to - a_from
	var d2 := b_to - b_from
	var r := a_from - b_from
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var c := d1.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-12 and e <= 1e-12:
		s = 0.0
		t = 0.0
	elif a <= 1e-12:
		s = 0.0
		t = clampf(f / e, 0.0, 1.0)
	elif e <= 1e-12:
		t = 0.0
		s = clampf(-c / a, 0.0, 1.0)
	else:
		var b := d1.dot(d2)
		var denom := a * e - b * b
		if denom > 1e-12:
			s = clampf((b * f - c * e) / denom, 0.0, 1.0)
		else:
			s = 0.0
		t = (b * s + f) / e
		if t < 0.0:
			t = 0.0
			s = clampf(-c / a, 0.0, 1.0)
		elif t > 1.0:
			t = 1.0
			s = clampf((b - c) / a, 0.0, 1.0)
	return {
		"dist": (a_from + d1 * s).distance_to(b_from + d2 * t),
		"on_a": a_from + d1 * s,
		"on_b": b_from + d2 * t,
	}