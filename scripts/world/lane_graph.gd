# scripts/world/lane_graph.gd
class_name LaneGraph
extends RefCounted

## Lane-level graph of the open-world road network (traffic plan section 3.2).
## Pure and deterministic: built from RoadDef[] plus the RoadNetwork junction
## list (RoadGraph.build_topology output), no node or tree access, safe to build
## on a worker thread. Nothing here edits roads or junctions; whatever junctions
## the network reports are turned into lane connectors generically, so a change
## in road seeding or junction data flows straight through on the next build.
##
## Model:
## - Every road gets travel lanes per direction (`lanes_per_direction`), offset
##   from the centreline in the BANKED road frame (TrackBuilder.frame_at, the frame
##   the road mesh is built from), so lane points lie on the road surface and
##   follow its Y, banking and camber. One lane per direction sits at +-width/4,
##   two per direction at +-width/8 (inner) and +-3*width/8 (outer).
## - Direction +1 runs in the road's point order, -1 is the reversed array.
##   DRIVE_SIDE picks the side (Japan theme: left-hand traffic).
## - Lanes are polylines resampled to ~SAMPLE_SPACING m with arc length `s`, a unit
##   tangent, a surface normal and a speed profile (tier limit, lateral-accel
##   curve limit, then a backward braking pass).
## - Connectors are lanes too (short Bezier polylines through a junction). A lane
##   lists its EXITS as (at_s -> connector lane); a connector's single successor is
##   (to_lane, to_s). Exits within LANE_END_TOL of an open lane's end are that
##   lane's successors; open lanes with none get a U-turn connector into the
##   opposite direction, so every lane always has somewhere to go.
## - Same-direction neighbours on multi-lane roads (`lane_inner` / `lane_outer`)
##   give lane-change adjacency.
## - A 64 m XZ hash of road-lane segment runs answers `nearest_lane` and the
##   spawn planner's "which lanes are in this cell" queries.

const DRIVE_LEFT := -1
const DRIVE_RIGHT := 1
## Driving side. Japan theme => left-hand traffic (plan section 15, question 1).
const DRIVE_SIDE := DRIVE_LEFT

const SAMPLE_SPACING := 4.0
const CONNECTOR_SPACING := 2.0
const CELL_SIZE := 64.0
## Comfortable lateral acceleration for the curve speed limit (m/s^2).
const A_LAT_MAX := 3.0
## Comfortable braking used by the backward speed pass (m/s^2).
const B_COMFORT := 2.5
## Window (m, each side) over which curvature is measured; the resampled points
## are lerps between sparse road vertices, so a per-sample angle would put all of
## a vertex's turn on one 4 m step and read 3x too sharp.
const CURVE_WINDOW := 12.0
const CONNECTOR_KMH := 35.0
const UTURN_KMH := 15.0
## How far before / after the junction point (along each lane) a connector starts
## and ends.
const CONNECTOR_REACH := 9.0
## Exits within this distance of an open lane's end count as its successors.
const LANE_END_TOL := 25.0
## A lane must have at least this much road before (arriving) / after
## (departing) the junction point to take part in a connector.
const ARRIVE_MIN := 8.0
## Connectors turning more than this (heading change) are not built: they would
## be near U-turns across a merge.
const MAX_TURN_DEG := 120.0
## Turn limit where one road's dead end meets another road's start.
const MAX_HAIRPIN_DEG := 179.0
## Junctions whose two roads are further apart than this vertically are
## overpasses, not junctions.
const MAX_JUNCTION_DY := 3.0
const MAX_CONNECTOR_CHORD := 60.0
const KMH := 1.0 / 3.6

# --- Per lane (struct of arrays, index = lane id) -------------------------------
var lane_pts: Array[PackedVector3Array] = []
var lane_s: Array[PackedFloat32Array] = []
var lane_fwd: Array[PackedVector3Array] = []
var lane_up: Array[PackedVector3Array] = []
## Speed profile (m/s) per point: min(limit, curve speed), braking-pass applied.
var lane_vmax: Array[PackedFloat32Array] = []
## Road centreline parameter (m along the road's point order) of each point;
## -1 for connectors. Increasing for direction +1, decreasing for -1.
var lane_c: Array[PackedFloat32Array] = []
var lane_length := PackedFloat32Array()
var lane_road := PackedInt32Array()  # -1 for connectors
var lane_dir := PackedInt32Array()  # +1 / -1, 0 for connectors
var lane_index := PackedInt32Array()  # 0 = inner (next to the centre line)
var lane_closed := PackedByteArray()
var lane_tier := PackedInt32Array()
var lane_limit := PackedFloat32Array()  # m/s
var lane_density := PackedFloat32Array()  # cars per 100 m (0 for connectors)
var lane_inner := PackedInt32Array()  # same-direction neighbour toward the centre, -1
var lane_outer := PackedInt32Array()  # same-direction neighbour toward the edge, -1
var lane_is_connector := PackedByteArray()
## Exits per lane, sorted by at_s: positions and connector lane ids.
var lane_exit_s: Array[PackedFloat32Array] = []
var lane_exit_to: Array[PackedInt32Array] = []
# Connector-only fields (-1 / 0 on road lanes).
var conn_from_lane := PackedInt32Array()
var conn_from_s := PackedFloat32Array()
var conn_to_lane := PackedInt32Array()
var conn_to_s := PackedFloat32Array()
var conn_junction := PackedInt32Array()  # index into the junction list, -1 = U-turn

## road id -> PackedInt32Array of its lanes (dir +1 lanes first, inner to outer).
var road_lanes: Array[PackedInt32Array] = []
## Vector2i cell -> PackedInt32Array of (lane, seg_from, seg_to) triples; segment k
## runs from point k to point k+1 (a closed lane's last segment wraps to 0).
var cells: Dictionary = {}
var junction_count := 0
var build_usec := 0
## When true, _build records why each junction lane pair got no connector.
var debug := false
var debug_log: PackedStringArray = PackedStringArray()

## Travel lanes per direction by tier (plan 3.2).
static func lanes_per_direction(tier: int) -> int:
	return 2 if tier == RoadDef.Tier.HIGHWAY else 1

static func speed_limit_kmh(tier: int) -> float:
	match tier:
		RoadDef.Tier.HIGHWAY:
			return 110.0
		RoadDef.Tier.ARTERIAL:
			return 80.0
		RoadDef.Tier.COASTAL:
			return 70.0
		RoadDef.Tier.TOUGE:
			return 60.0
		RoadDef.Tier.DIRT:
			return 40.0
	return 60.0

## Daytime cars per 100 m of lane at Medium (plan 3.3).
static func density_per_100m(tier: int) -> float:
	match tier:
		RoadDef.Tier.HIGHWAY:
			return 0.9
		RoadDef.Tier.ARTERIAL:
			return 0.7
		RoadDef.Tier.COASTAL:
			return 0.4
		RoadDef.Tier.TOUGE:
			return 0.15
		RoadDef.Tier.DIRT:
			return 0.05
	return 0.5

## Unsigned lane-centre offsets from the centreline, inner lane first.
## n lanes per direction share one half of the road: (2k+1) * width / (4n).
static func lane_offsets(width: float, per_dir: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in per_dir:
		out.append(float(2 * k + 1) * width / (4.0 * float(per_dir)))
	return out

## Builds the graph. `junctions` is RoadNetwork.get_junctions() (or
## RoadGraph.build_topology(defs, ...)["junctions"]) for the same defs.
static func build(defs: Array, junctions: Array, debug_trace: bool = false) -> LaneGraph:
	var g := LaneGraph.new()
	g.debug = debug_trace
	var t0 := Time.get_ticks_usec()
	g._build(defs, junctions)
	g.build_usec = Time.get_ticks_usec() - t0
	return g

func lane_count() -> int:
	return lane_length.size()

func is_connector(lane: int) -> bool:
	return lane_is_connector[lane] == 1

## Lane-change targets of `lane` (same road, same direction, adjacent index).
func lane_change_targets(lane: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if lane_inner[lane] >= 0:
		out.append(lane_inner[lane])
	if lane_outer[lane] >= 0:
		out.append(lane_outer[lane])
	return out

## Lanes reachable from `lane` without a lane change: its exits' connectors, a
## connector's target lane, and itself for a closed loop.
func successors(lane: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if is_connector(lane):
		out.append(conn_to_lane[lane])
		return out
	if lane_closed[lane] == 1:
		out.append(lane)
	for c in lane_exit_to[lane]:
		out.append(c)
	return out

## True when an open lane has an exit at its end (or the lane is closed / a connector).
func has_end_successor(lane: int) -> bool:
	if is_connector(lane) or lane_closed[lane] == 1:
		return true
	var es: PackedFloat32Array = lane_exit_s[lane]
	return es.size() > 0 and es[es.size() - 1] >= lane_length[lane] - LANE_END_TOL

## Index k with s[k] <= s < s[k+1] (k in [0, n-1]); `hint` is a previous answer.
## Callers pass s already wrapped/clamped to [0, length].
func seek(lane: int, s: float, hint: int = -1) -> int:
	var ss: PackedFloat32Array = lane_s[lane]
	var n := ss.size()
	if n <= 1:
		return 0
	if hint >= 0 and hint < n:
		var k := hint
		# Short walks first: cars move < 1 sample per tick.
		for _i in 4:
			if ss[k] > s:
				if k == 0:
					return 0
				k -= 1
			elif k + 1 < n and ss[k + 1] <= s:
				k += 1
			else:
				return k
	var lo := 0
	var hi := n - 1
	if s >= ss[hi]:
		return hi
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if ss[mid] <= s:
			lo = mid
		else:
			hi = mid
	return lo

## Wraps (closed) or clamps (open) an arc position onto the lane.
func wrap_s(lane: int, s: float) -> float:
	var length := lane_length[lane]
	if lane_closed[lane] == 1:
		return fposmod(s, length)
	return clampf(s, 0.0, length)

## Segment end point of segment k (closed lanes wrap the last segment to 0).
func _seg_end_index(lane: int, k: int) -> int:
	var n := lane_pts[lane].size()
	if k + 1 < n:
		return k + 1
	return 0 if lane_closed[lane] == 1 else k

func _seg_t(lane: int, k: int, s: float) -> float:
	var ss: PackedFloat32Array = lane_s[lane]
	var s0 := ss[k]
	var s1 := ss[k + 1] if k + 1 < ss.size() else lane_length[lane]
	if s1 - s0 <= 1e-6:
		return 0.0
	return clampf((s - s0) / (s1 - s0), 0.0, 1.0)

func position_at(lane: int, s: float, hint: int = -1) -> Vector3:
	s = wrap_s(lane, s)
	var k := seek(lane, s, hint)
	var pts: PackedVector3Array = lane_pts[lane]
	return pts[k].lerp(pts[_seg_end_index(lane, k)], _seg_t(lane, k, s))

func forward_at(lane: int, s: float, hint: int = -1) -> Vector3:
	s = wrap_s(lane, s)
	var k := seek(lane, s, hint)
	var f: PackedVector3Array = lane_fwd[lane]
	var v := f[k].lerp(f[_seg_end_index(lane, k)], _seg_t(lane, k, s))
	return v.normalized() if v.length_squared() > 1e-8 else f[k]

func up_at(lane: int, s: float, hint: int = -1) -> Vector3:
	s = wrap_s(lane, s)
	var k := seek(lane, s, hint)
	var u: PackedVector3Array = lane_up[lane]
	var v := u[k].lerp(u[_seg_end_index(lane, k)], _seg_t(lane, k, s))
	return v.normalized() if v.length_squared() > 1e-8 else Vector3.UP

func vmax_at(lane: int, s: float, hint: int = -1) -> float:
	s = wrap_s(lane, s)
	var k := seek(lane, s, hint)
	var vm: PackedFloat32Array = lane_vmax[lane]
	return minf(vm[k], vm[_seg_end_index(lane, k)])

## Nearest ROAD lane (connectors excluded) to `pos` within `max_dist` (XZ), with
## |dy| <= max_dy. A non-zero `heading` keeps only lanes running the same way
## (tangent . heading >= 0.3 in XZ). Returns {} when nothing qualifies, else
## {lane, s, dist, seg}.
func nearest_lane(pos: Vector3, max_dist: float, heading: Vector3 = Vector3.ZERO, max_dy: float = 4.0) -> Dictionary:
	var h := Vector2(heading.x, heading.z)
	var use_heading := h.length_squared() > 1e-6
	if use_heading:
		h = h.normalized()
	var reach := max_dist + SAMPLE_SPACING
	var cx0 := floori((pos.x - reach) / CELL_SIZE)
	var cx1 := floori((pos.x + reach) / CELL_SIZE)
	var cz0 := floori((pos.z - reach) / CELL_SIZE)
	var cz1 := floori((pos.z + reach) / CELL_SIZE)
	var best_d := max_dist
	var best_lane := -1
	var best_seg := 0
	var best_t := 0.0
	var q := Vector2(pos.x, pos.z)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var key := Vector2i(cx, cz)
			if not cells.has(key):
				continue
			var runs: PackedInt32Array = cells[key]
			for r in range(0, runs.size(), 3):
				var lane := runs[r]
				var pts: PackedVector3Array = lane_pts[lane]
				for k in range(runs[r + 1], runs[r + 2] + 1):
					var a := pts[k]
					var b := pts[_seg_end_index(lane, k)]
					var a2 := Vector2(a.x, a.z)
					var ab := Vector2(b.x, b.z) - a2
					var len2 := ab.length_squared()
					var t := 0.0
					if len2 > 1e-9:
						t = clampf((q - a2).dot(ab) / len2, 0.0, 1.0)
					var p2 := a2 + ab * t
					var d := q.distance_to(p2)
					if d >= best_d:
						continue
					if absf(lerpf(a.y, b.y, t) - pos.y) > max_dy:
						continue
					if use_heading and len2 > 1e-9 and ab.normalized().dot(h) < 0.3:
						continue
					best_d = d
					best_lane = lane
					best_seg = k
					best_t = t
	if best_lane < 0:
		return {}
	var ss: PackedFloat32Array = lane_s[best_lane]
	var s0 := ss[best_seg]
	var s1 := ss[best_seg + 1] if best_seg + 1 < ss.size() else lane_length[best_lane]
	return {"lane": best_lane, "s": lerpf(s0, s1, best_t), "dist": best_d, "seg": best_seg}

## Road lanes with at least one segment in `cell` (sorted, unique).
func lanes_in_cell(cell: Vector2i) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not cells.has(cell):
		return out
	var runs: PackedInt32Array = cells[cell]
	for r in range(0, runs.size(), 3):
		if not out.has(runs[r]):
			out.append(runs[r])
	out.sort()
	return out

static func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / CELL_SIZE), floori(pos.z / CELL_SIZE))

## Order-sensitive hash of every array (determinism checks).
func checksum() -> int:
	var parts: Array = [lane_length, lane_road, lane_dir, lane_index, lane_closed, lane_tier, lane_inner,
		lane_outer, conn_from_lane, conn_from_s, conn_to_lane, conn_to_s, conn_junction]
	for i in lane_count():
		parts.append(lane_pts[i])
		parts.append(lane_vmax[i])
		parts.append(lane_exit_s[i])
		parts.append(lane_exit_to[i])
	var keys := cells.keys()
	keys.sort()
	for k in keys:
		parts.append(k)
		parts.append(cells[k])
	return hash(var_to_bytes(parts))

# --- Build ---------------------------------------------------------------------

func _build(defs: Array, junctions: Array) -> void:
	road_lanes.clear()
	var road_cum: Array[PackedFloat32Array] = []
	for road_id in defs.size():
		var def := defs[road_id] as RoadDef
		var ids := PackedInt32Array()
		var cum := PackedFloat32Array()
		if def != null and def.points.size() >= 2:
			cum = _cumulative(def.points)
			ids = _build_road_lanes(road_id, def, cum)
		road_lanes.append(ids)
		road_cum.append(cum)
	junction_count = junctions.size()
	for j in junctions.size():
		_build_junction(j, junctions[j] as Dictionary, defs, road_cum)
	for lane in lane_count():
		_sort_exits(lane)
	_build_uturns()
	for lane in lane_count():
		_sort_exits(lane)
	_build_cells()

static func _cumulative(pts: Array[Vector3]) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	cum.resize(pts.size())
	var acc := 0.0
	for i in pts.size():
		if i > 0:
			acc += pts[i - 1].distance_to(pts[i])
		cum[i] = acc
	return cum

func _new_lane() -> int:
	var id := lane_length.size()
	lane_pts.append(PackedVector3Array())
	lane_s.append(PackedFloat32Array())
	lane_fwd.append(PackedVector3Array())
	lane_up.append(PackedVector3Array())
	lane_vmax.append(PackedFloat32Array())
	lane_c.append(PackedFloat32Array())
	lane_length.append(0.0)
	lane_road.append(-1)
	lane_dir.append(0)
	lane_index.append(0)
	lane_closed.append(0)
	lane_tier.append(0)
	lane_limit.append(0.0)
	lane_density.append(0.0)
	lane_inner.append(-1)
	lane_outer.append(-1)
	lane_is_connector.append(0)
	lane_exit_s.append(PackedFloat32Array())
	lane_exit_to.append(PackedInt32Array())
	conn_from_lane.append(-1)
	conn_from_s.append(0.0)
	conn_to_lane.append(-1)
	conn_to_s.append(0.0)
	conn_junction.append(-1)
	return id

func _build_road_lanes(road_id: int, def: RoadDef, cum: PackedFloat32Array) -> PackedInt32Array:
	var pts: Array[Vector3] = def.points
	var n := pts.size()
	var closed := def.closed and n >= 3
	var bank := def.bank_angles if def.bank_angles.size() == n else PackedFloat32Array()
	var crosses := PackedVector3Array()
	crosses.resize(n)
	for i in n:
		var f: Dictionary = TrackBuilder.frame_at(pts, i, closed, def.banking, bank)
		crosses[i] = f["cross"]
	var per_dir := lanes_per_direction(def.tier)
	var mags := lane_offsets(def.width, per_dir)
	var ids := PackedInt32Array()
	var by_dir := {1: PackedInt32Array(), -1: PackedInt32Array()}
	for dir in [1, -1]:
		for k in per_dir:
			var offset := float(DRIVE_SIDE * dir) * mags[k]
			var lane := _new_lane()
			lane_road[lane] = road_id
			lane_dir[lane] = dir
			lane_index[lane] = k
			lane_closed[lane] = 1 if closed else 0
			lane_tier[lane] = def.tier
			lane_limit[lane] = speed_limit_kmh(def.tier) * KMH
			lane_density[lane] = density_per_100m(def.tier)
			_sample_road_lane(lane, pts, crosses, cum, closed, offset, dir)
			_finish_lane(lane, SAMPLE_SPACING)
			ids.append(lane)
			var arr: PackedInt32Array = by_dir[dir]
			arr.append(lane)
			by_dir[dir] = arr
	for dir in [1, -1]:
		var arr: PackedInt32Array = by_dir[dir]
		for k in arr.size():
			if k > 0:
				lane_inner[arr[k]] = arr[k - 1]
			if k + 1 < arr.size():
				lane_outer[arr[k]] = arr[k + 1]
	return ids

func _sample_road_lane(lane: int, pts: Array[Vector3], crosses: PackedVector3Array, cum: PackedFloat32Array, closed: bool, offset: float, dir: int) -> void:
	var n := pts.size()
	var seg_count := n if closed else n - 1
	var lp := PackedVector3Array()
	var lc := PackedFloat32Array()
	var lx := PackedVector3Array()
	for seg in seg_count:
		var i0 := seg
		var i1 := (seg + 1) % n
		var a := pts[i0] + crosses[i0] * offset
		var b := pts[i1] + crosses[i1] * offset
		var seg_len := pts[i0].distance_to(pts[i1])
		var parts := maxi(1, ceili(seg_len / SAMPLE_SPACING))
		for p in parts:
			var t := float(p) / float(parts)
			var q := a.lerp(b, t)
			if lp.size() > 0 and lp[lp.size() - 1].distance_squared_to(q) < 0.0025:
				continue
			lp.append(q)
			lc.append(cum[i0] + seg_len * t)
			lx.append(crosses[i0].lerp(crosses[i1], t))
	if not closed:
		var q := pts[n - 1] + crosses[n - 1] * offset
		if lp.is_empty() or lp[lp.size() - 1].distance_squared_to(q) >= 0.0025:
			lp.append(q)
			lc.append(cum[n - 1])
			lx.append(crosses[n - 1])
	elif lp.size() > 1 and lp[lp.size() - 1].distance_squared_to(lp[0]) < 0.0025:
		lp.resize(lp.size() - 1)
		lc.resize(lc.size() - 1)
		lx.resize(lx.size() - 1)
	if dir < 0:
		lp.reverse()
		lc.reverse()
		lx.reverse()
	lane_pts[lane] = lp
	lane_c[lane] = lc
	# Surface normal per point from the banked cross-section (TrackBuilder._frame_normal
	# rule: cross x forward, flipped to point up). Forward is filled by _finish_lane,
	# so store the cross here and convert there.
	lane_up[lane] = lx

## Arc length, tangents, normals (from the stored cross vectors) and the speed
## profile of a sampled lane.
func _finish_lane(lane: int, spacing: float) -> void:
	var pts: PackedVector3Array = lane_pts[lane]
	var n := pts.size()
	var closed := lane_closed[lane] == 1
	var ss := PackedFloat32Array()
	ss.resize(n)
	var acc := 0.0
	for i in n:
		if i > 0:
			acc += pts[i - 1].distance_to(pts[i])
		ss[i] = acc
	var length := acc + (pts[n - 1].distance_to(pts[0]) if closed and n > 1 else 0.0)
	lane_s[lane] = ss
	lane_length[lane] = length
	var fwd := PackedVector3Array()
	fwd.resize(n)
	for i in n:
		var prev := pts[(i - 1 + n) % n] if closed else pts[maxi(i - 1, 0)]
		var next := pts[(i + 1) % n] if closed else pts[mini(i + 1, n - 1)]
		var f := next - prev
		fwd[i] = f.normalized() if f.length_squared() > 1e-9 else (fwd[i - 1] if i > 0 else Vector3.FORWARD)
	lane_fwd[lane] = fwd
	var crosses: PackedVector3Array = lane_up[lane]
	var ups := PackedVector3Array()
	ups.resize(n)
	for i in n:
		var nrm := Vector3.UP
		if crosses.size() == n:
			var c := crosses[i]
			var u := c.cross(fwd[i])
			if u.length_squared() > 1e-8:
				nrm = u.normalized()
				if nrm.y < 0.0:
					nrm = -nrm
		ups[i] = nrm
	lane_up[lane] = ups
	_speed_profile(lane, spacing)

func _speed_profile(lane: int, spacing: float) -> void:
	var pts: PackedVector3Array = lane_pts[lane]
	var ss: PackedFloat32Array = lane_s[lane]
	var n := pts.size()
	var closed := lane_closed[lane] == 1
	var length := lane_length[lane]
	var limit := lane_limit[lane]
	var w := maxi(1, roundi(CURVE_WINDOW / spacing))
	var vm := PackedFloat32Array()
	vm.resize(n)
	for i in n:
		var ia := i - w
		var ib := i + w
		if closed:
			ia = posmod(ia, n)
			ib = posmod(ib, n)
		else:
			ia = maxi(ia, 0)
			ib = mini(ib, n - 1)
		var v := limit
		if ia != i and ib != i:
			var d1 := pts[i] - pts[ia]
			var d2 := pts[ib] - pts[i]
			var h1 := Vector2(d1.x, d1.z)
			var h2 := Vector2(d2.x, d2.z)
			var l1 := h1.length()
			var l2 := h2.length()
			if l1 > 1e-4 and l2 > 1e-4:
				var ang := absf(h1.angle_to(h2))
				var kappa := ang / (0.5 * (l1 + l2))
				if kappa > 1e-5:
					v = minf(v, sqrt(A_LAT_MAX / kappa))
		vm[i] = maxf(v, 3.0)
	# Backward braking pass so the profile can always be met at B_COMFORT.
	var passes := 2 if closed else 1
	for _p in passes:
		for j in range(n - 1, -1, -1):
			var nxt := j + 1
			var ds := 0.0
			if nxt >= n:
				if not closed:
					continue
				nxt = 0
				ds = length - ss[j]
			else:
				ds = ss[nxt] - ss[j]
			var cap := sqrt(vm[nxt] * vm[nxt] + 2.0 * B_COMFORT * ds)
			if cap < vm[j]:
				vm[j] = cap
	lane_vmax[lane] = vm

## Arc position on `lane` of the road centreline parameter `c` (interpolated on
## lane_c, which is monotonic: increasing for dir +1, decreasing for -1).
func _s_at_c(lane: int, c: float) -> float:
	var lc: PackedFloat32Array = lane_c[lane]
	var ss: PackedFloat32Array = lane_s[lane]
	var n := lc.size()
	if n == 0:
		return 0.0
	var inc := lane_dir[lane] > 0
	var best := 0
	# Binary search on the monotonic parameter.
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		var before := lc[mid] <= c if inc else lc[mid] >= c
		if before:
			lo = mid
		else:
			hi = mid
	best = lo
	var c0 := lc[best]
	var c1 := lc[best + 1] if best + 1 < n else c0
	if absf(c1 - c0) < 1e-6:
		return ss[best]
	var t := clampf((c - c0) / (c1 - c0), 0.0, 1.0)
	var s1 := ss[best + 1] if best + 1 < n else ss[best]
	return lerpf(ss[best], s1, t)

## Road parameter and point on road `road` closest to `p` within segment `seg`.
static func _road_param(pts: Array[Vector3], cum: PackedFloat32Array, seg: int, p: Vector3) -> Array:
	var i0 := clampi(seg, 0, pts.size() - 1)
	var i1 := mini(i0 + 1, pts.size() - 1)
	var a := pts[i0]
	var b := pts[i1]
	var ab := b - a
	var len2 := ab.length_squared()
	var t := 0.0
	if len2 > 1e-9:
		t = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return [cum[i0] + sqrt(len2) * t, a + ab * t]

func _build_junction(j: int, junction: Dictionary, defs: Array, road_cum: Array[PackedFloat32Array]) -> void:
	var ra := int(junction.get("road_a", -1))
	var rb := int(junction.get("road_b", -1))
	if ra < 0 or rb < 0 or ra >= defs.size() or rb >= defs.size() or ra == rb:
		return
	if road_lanes[ra].is_empty() or road_lanes[rb].is_empty():
		return
	var p: Vector3 = junction.get("point", Vector3.ZERO)
	var da := defs[ra] as RoadDef
	var db := defs[rb] as RoadDef
	var pa := _road_param(da.points, road_cum[ra], int(junction.get("segment_a", 0)), p)
	var pb := _road_param(db.points, road_cum[rb], int(junction.get("segment_b", 0)), p)
	if absf((pa[1] as Vector3).y - (pb[1] as Vector3).y) > MAX_JUNCTION_DY:
		if debug:
			debug_log.append("j%d overpass dy=%.1f" % [j, absf((pa[1] as Vector3).y - (pb[1] as Vector3).y)])
		return
	_connect_roads(j, ra, float(pa[0]), rb, float(pb[0]))
	_connect_roads(j, rb, float(pb[0]), ra, float(pa[0]))

## Connectors from road `rx`'s lanes arriving at centre parameter cx into road
## `ry`'s lanes departing from cy.
func _connect_roads(j: int, rx: int, cx: float, ry: int, cy: float) -> void:
	for lx in road_lanes[rx]:
		var sx := _s_at_c(lx, cx)
		var x_closed := lane_closed[lx] == 1
		var x_len := lane_length[lx]
		if not x_closed and sx < ARRIVE_MIN:
			if debug:
				debug_log.append("j%d lane %d does not arrive (s=%.1f)" % [j, lx, sx])
			continue
		var x_ends_here := not x_closed and x_len - sx < LANE_END_TOL
		# Through traffic leaves from the outer lane; a lane that ends at the junction
		# must leave from whichever lane it is.
		if lane_outer[lx] >= 0 and not x_ends_here:
			continue
		var from_s := sx - CONNECTOR_REACH
		if x_closed:
			from_s = fposmod(from_s, x_len)
		else:
			from_s = clampf(from_s, 0.0, x_len)
		for ly in road_lanes[ry]:
			if lane_outer[ly] >= 0:
				continue
			var sy := _s_at_c(ly, cy)
			var y_closed := lane_closed[ly] == 1
			var y_len := lane_length[ly]
			if not y_closed and y_len - sy < ARRIVE_MIN:
				if debug:
					debug_log.append("j%d lane %d does not depart (s=%.1f of %.1f)" % [j, ly, sy, y_len])
				continue
			var to_s := sy + CONNECTOR_REACH
			to_s = fposmod(to_s, y_len) if y_closed else clampf(to_s, 0.0, y_len)
			var p0 := position_at(lx, from_s)
			var p3 := position_at(ly, to_s)
			var t0 := forward_at(lx, from_s)
			var t3 := forward_at(ly, to_s)
			var h0 := Vector2(t0.x, t0.z)
			var h3 := Vector2(t3.x, t3.z)
			if h0.length_squared() < 1e-6 or h3.length_squared() < 1e-6:
				continue
			var turn := rad_to_deg(absf(h0.angle_to(h3)))
			# Two dead ends meeting (one road ends where the other starts, e.g. a
			# fork at the coast): a hairpin is the only way on, so allow it.
			var y_starts_here := not y_closed and sy < LANE_END_TOL
			var max_turn := MAX_HAIRPIN_DEG if x_ends_here and y_starts_here else MAX_TURN_DEG
			if turn > max_turn:
				if debug:
					debug_log.append("j%d %d->%d turn %.0f deg" % [j, lx, ly, rad_to_deg(absf(h0.angle_to(h3)))])
				continue
			var chord := p0.distance_to(p3)
			if chord < 1.0 or chord > MAX_CONNECTOR_CHORD:
				if debug:
					debug_log.append("j%d %d->%d chord %.1f" % [j, lx, ly, chord])
				continue
			var handle := chord * 0.4
			if turn > 90.0:
				handle = maxf(handle, 5.0)
			var limit := minf(CONNECTOR_KMH * KMH, minf(lane_limit[lx], lane_limit[ly]))
			_add_connector(j, lx, from_s, ly, to_s, p0, p0 + t0 * handle, p3 - t3 * handle, p3, limit, lane_up[lx][seek(lx, from_s)], lane_up[ly][seek(ly, to_s)])

func _add_connector(j: int, from_lane: int, from_s: float, to_lane: int, to_s: float, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, limit: float, up0: Vector3, up3: Vector3) -> int:
	var lane := _new_lane()
	var approx := p0.distance_to(p1) + p1.distance_to(p2) + p2.distance_to(p3)
	var steps := maxi(4, ceili(approx / CONNECTOR_SPACING))
	var lp := PackedVector3Array()
	var lx := PackedVector3Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		var u := 1.0 - t
		lp.append(p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t))
		lx.append(Vector3.ZERO)
	lane_pts[lane] = lp
	lane_closed[lane] = 0
	lane_is_connector[lane] = 1
	lane_tier[lane] = lane_tier[to_lane]
	lane_limit[lane] = limit
	lane_density[lane] = 0.0
	conn_from_lane[lane] = from_lane
	conn_from_s[lane] = from_s
	conn_to_lane[lane] = to_lane
	conn_to_s[lane] = to_s
	conn_junction[lane] = j
	lane_up[lane] = lx
	_finish_lane(lane, CONNECTOR_SPACING)
	# Normals: blend the two lanes' surface normals (the connector has no frame).
	var ups: PackedVector3Array = lane_up[lane]
	for i in ups.size():
		ups[i] = up0.lerp(up3, float(i) / float(maxi(ups.size() - 1, 1))).normalized()
	lane_up[lane] = ups
	# The connector must leave no faster than the lane it joins allows there.
	var vm: PackedFloat32Array = lane_vmax[lane]
	var join_v := vmax_at(to_lane, to_s)
	if vm.size() > 0 and vm[vm.size() - 1] > join_v:
		vm[vm.size() - 1] = join_v
		var ss: PackedFloat32Array = lane_s[lane]
		for k in range(vm.size() - 2, -1, -1):
			vm[k] = minf(vm[k], sqrt(vm[k + 1] * vm[k + 1] + 2.0 * B_COMFORT * (ss[k + 1] - ss[k])))
		lane_vmax[lane] = vm
	var es: PackedFloat32Array = lane_exit_s[from_lane]
	var et: PackedInt32Array = lane_exit_to[from_lane]
	es.append(from_s)
	et.append(lane)
	lane_exit_s[from_lane] = es
	lane_exit_to[from_lane] = et
	return lane

## Dead ends: an open road lane with no exit near its end turns around into the
## opposite-direction lane of the same index.
func _build_uturns() -> void:
	var road_count := road_lanes.size()
	for road_id in road_count:
		for lane in road_lanes[road_id]:
			if lane_closed[lane] == 1 or has_end_successor(lane):
				continue
			var target := -1
			for other in road_lanes[road_id]:
				if lane_dir[other] != lane_dir[lane] and lane_index[other] == lane_index[lane]:
					target = other
					break
			if target < 0:
				continue
			var from_s := lane_length[lane]
			var p0 := position_at(lane, from_s)
			var p3 := position_at(target, 0.0)
			var t0 := forward_at(lane, from_s)
			var t3 := forward_at(target, 0.0)
			var handle := maxf(p0.distance_to(p3), 4.0) * 0.9
			var limit := minf(UTURN_KMH * KMH, lane_limit[lane])
			var up := lane_up[lane][lane_up[lane].size() - 1]
			_add_connector(-1, lane, from_s, target, 0.0, p0, p0 + t0 * handle, p3 - t3 * handle, p3, limit, up, up)

func _sort_exits(lane: int) -> void:
	var es: PackedFloat32Array = lane_exit_s[lane]
	if es.size() < 2:
		return
	var et: PackedInt32Array = lane_exit_to[lane]
	var order: Array = []
	for i in es.size():
		order.append([es[i], et[i]])
	order.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] < b[0]
		return a[1] < b[1])
	for i in order.size():
		es[i] = order[i][0]
		et[i] = order[i][1]
	lane_exit_s[lane] = es
	lane_exit_to[lane] = et

func _build_cells() -> void:
	cells.clear()
	for lane in lane_count():
		if is_connector(lane):
			continue
		var pts: PackedVector3Array = lane_pts[lane]
		var n := pts.size()
		var seg_count := n if lane_closed[lane] == 1 else n - 1
		var run_cell := Vector2i(2147483647, 0)
		var run_from := 0
		for k in seg_count:
			var mid := (pts[k] + pts[_seg_end_index(lane, k)]) * 0.5
			var c := cell_of(mid)
			if c != run_cell:
				if k > 0:
					_cells_add(run_cell, lane, run_from, k - 1)
				run_cell = c
				run_from = k
		if seg_count > 0:
			_cells_add(run_cell, lane, run_from, seg_count - 1)

func _cells_add(cell: Vector2i, lane: int, from_seg: int, to_seg: int) -> void:
	var arr: PackedInt32Array = cells.get(cell, PackedInt32Array())
	arr.append(lane)
	arr.append(from_seg)
	arr.append(to_seg)
	cells[cell] = arr
