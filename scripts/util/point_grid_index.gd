# scripts/util/point_grid_index.gd
class_name PointGridIndex
extends RefCounted

## Exact spatial acceleration index over a STATIC list of world points, keyed on
## the XZ plane (Y is ignored, matching every road / racing-line query it
## serves). A uniform grid maps each vertex to the single cell its XZ falls in.
##
## Queries expand in Chebyshev rings around the query cell and stop as soon as
## no unscanned cell can hold a closer vertex, so a ring-limited answer is
## bit-identical to the brute-force scan it replaces while touching a handful of
## cells instead of every point. Built once per point list; the lists it serves
## (racing lines, roadmap chains) are static after the scene bootstraps.
##
## Two shapes are provided:
##   * `nearest_index`  - the nearest vertex, first-minimal index on a tie,
##                        exactly the old `for i: if d2 < best` loop.
##   * `min_max_within` - the [min,max] index span of every vertex inside a
##                        radius, exactly the set a brute-force enumeration
##                        would collect (used to window a polyline before a
##                        transform + clip).

## Cell size (m) tuned for a racing line at ~3 m point spacing: a cell holds a
## handful of points, so a car sitting on the line resolves in ring 0.
const DEFAULT_CELL_M := 32.0

## Source points (read-only). Either Array or PackedVector3Array; assigned by
## reference so the index never copies the point list.
var _pts = []
var _cell: float = DEFAULT_CELL_M
## { Vector2i cell -> PackedInt32Array of vertex indices }
var _index: Dictionary = {}
var _min := Vector2i.ZERO
var _max := Vector2i.ZERO
var _built := false
var _scratch := PackedInt32Array()

func build(points, cell_m: float = DEFAULT_CELL_M) -> void:
	_pts = points
	_cell = maxf(cell_m, 1.0)
	_index.clear()
	_built = false
	if _pts.is_empty():
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in _pts.size():
		var p: Vector3 = _pts[i]
		lo.x = minf(lo.x, p.x)
		lo.y = minf(lo.y, p.z)
		hi.x = maxf(hi.x, p.x)
		hi.y = maxf(hi.y, p.z)
		var key := _cell_of(Vector2(p.x, p.z))
		var bucket: PackedInt32Array = _index.get(key, PackedInt32Array())
		bucket.append(i)
		_index[key] = bucket
	_min = Vector2i(floori(lo.x / _cell), floori(lo.y / _cell)) - Vector2i.ONE
	_max = Vector2i(floori(hi.x / _cell), floori(hi.y / _cell)) + Vector2i.ONE
	_built = true

func is_ready() -> bool:
	return _built and not _index.is_empty()

func source_size() -> int:
	return _pts.size()

## True when the index was built over exactly `count` points. Lets a caller that
## may have had its point list swapped underneath it fall back to a brute-force
## scan instead of trusting a stale index.
func matches(count: int) -> bool:
	return is_ready() and _pts.size() == count

func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / _cell), floori(p.y / _cell))

## Nearest vertex index (XZ), first-lowest on an exact distance tie -- identical
## to the brute-force `best_index` scan. Returns -1 when the index is not ready.
func nearest_index(pos: Vector3) -> int:
	if not is_ready():
		return -1
	var q := Vector2(pos.x, pos.z)
	var base := _cell_of(q)
	var max_ring := maxi(
		maxi(_max.x - base.x, base.x - _min.x),
		maxi(_max.y - base.y, base.y - _min.y)) + 1
	var best_i := -1
	var best_d2 := INF
	var ring := 0
	while ring <= max_ring:
		_gather_ring(base, ring)
		for i: int in _scratch:
			var p: Vector3 = _pts[i]
			var dx := p.x - pos.x
			var dz := p.z - pos.z
			var d2 := dx * dx + dz * dz
			if d2 < best_d2 or (d2 == best_d2 and (best_i < 0 or i < best_i)):
				best_d2 = d2
				best_i = i
		if best_i >= 0:
			var inner := _ring_inner_dist(q, base, ring)
			if best_d2 <= inner * inner:
				break
		ring += 1
	return best_i

## (min_index, max_index) over every vertex within `radius` (XZ) of `center`, or
## (-1, -1) when none / not ready. Exact: the grid AABB covers the whole disk, so
## no inside vertex is missed.
func min_max_within(center: Vector2, radius: float) -> Vector2i:
	if not is_ready():
		return Vector2i(-1, -1)
	var r2 := radius * radius
	var lo_cell := _cell_of(center - Vector2(radius, radius))
	var hi_cell := _cell_of(center + Vector2(radius, radius))
	lo_cell.x = maxi(lo_cell.x, _min.x)
	lo_cell.y = maxi(lo_cell.y, _min.y)
	hi_cell.x = mini(hi_cell.x, _max.x)
	hi_cell.y = mini(hi_cell.y, _max.y)
	var mn := -1
	var mx := -1
	for cy in range(lo_cell.y, hi_cell.y + 1):
		for cx in range(lo_cell.x, hi_cell.x + 1):
			var bucket: PackedInt32Array = _index.get(Vector2i(cx, cy), PackedInt32Array())
			for i: int in bucket:
				var p: Vector3 = _pts[i]
				var dx := p.x - center.x
				var dz := p.z - center.y
				if dx * dx + dz * dz <= r2:
					if mn < 0 or i < mn:
						mn = i
					if i > mx:
						mx = i
	return Vector2i(mn, mx)

## Appends every cell on Chebyshev ring `k` around `base` into `_scratch`. Ring 0
## is the base cell; outer rings are the square perimeters, so no cell is visited
## twice across rings.
func _gather_ring(base: Vector2i, k: int) -> void:
	_scratch.resize(0)
	if k == 0:
		_gather_cell(base)
		return
	var min_x := base.x - k
	var max_x := base.x + k
	var min_y := base.y - k
	var max_y := base.y + k
	if max_x < _min.x or min_x > _max.x or max_y < _min.y or min_y > _max.y:
		return
	var x0 := maxi(min_x, _min.x)
	var x1 := mini(max_x, _max.x)
	var y0 := maxi(min_y, _min.y)
	var y1 := mini(max_y, _max.y)
	for cx in range(x0, x1 + 1):
		_gather_cell(Vector2i(cx, y0))
		if y1 != y0:
			_gather_cell(Vector2i(cx, y1))
	for cy in range(y0 + 1, y1):
		_gather_cell(Vector2i(x0, cy))
		if x1 != x0:
			_gather_cell(Vector2i(x1, cy))

func _gather_cell(key: Vector2i) -> void:
	if _index.has(key):
		_scratch.append_array(_index[key] as PackedInt32Array)

## Lower bound (m) on the distance from `q` to any cell NOT yet covered when the
## scanned square spans Chebyshev radius `k` around `base`. `q` lies inside its
## own base cell, so this is the distance to the nearest edge of the square.
func _ring_inner_dist(q: Vector2, base: Vector2i, k: int) -> float:
	var x_min := float(base.x - k) * _cell
	var x_max := float(base.x + k + 1) * _cell
	var y_min := float(base.y - k) * _cell
	var y_max := float(base.y + k + 1) * _cell
	return minf(
		minf(q.x - x_min, x_max - q.x),
		minf(q.y - y_min, y_max - q.y))
