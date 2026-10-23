# scripts/world/road_chunk_mesher.gd
class_name RoadChunkMesher
extends RefCounted

## Streamed open-world road geometry (open_world_status.md section 9).
##
## `TrackBuilder` builds one road as a handful of meshes that span the whole
## road (a 25 km ring is one mesh, one AABB, always drawn, always in the shadow
## pass). For streaming, the network is cut into square cells and every road
## SEGMENT (point k -> k+1, plus the wrap segment n-1 -> 0 of a closed road)
## belongs to exactly one cell, the one holding its midpoint. A cell's geometry
## is every segment it owns, built from the very frames `TrackBuilder` uses
## (`TrackBuilder.frame_at`), so:
##   - the union of all cells is the road TrackBuilder would have built
##     (same triangles, same winding, same dash phase, same rail gaps);
##   - two neighbouring cells share the exact seam vertices (no gap, no step,
##     no overlap) in both the visual strips and the collision trimesh.
##
## Everything here is pure and thread-safe: `prepare_road` runs once per road on
## the main thread (it reads RoadDefs), `build_cell` / `build_far` only read the
## prepared tables and return packed arrays, so they run on WorkerThreadPool.
## `instantiate_cell` / `instantiate_far` (main thread) turn arrays into nodes
## with SHARED materials (one per surface/tier/colour), so a cell costs no
## texture generation and no new material.

## Visual "kinds" of a bucket. Painted lines (edge, divider) lie on the
## carriageway and never need to cast a shadow; carriageway and rails do.
const KIND_SURFACE := 0
const KIND_EDGE := 1
const KIND_DIVIDER := 2
const KIND_RAIL := 3

## The far LOD (whole network, surface + edge colours, no collision) sits this
## far under the streamed road so the full-detail road always wins the depth
## test where both exist. Reverse-Z depth resolves 6 cm far past the stream
## radius; up close the streamed road covers it completely.
const FAR_DROP := 0.06

const ROAD_FRICTION := 0.0
const RAIL_FRICTION := 0.2

static var _materials: Dictionary = {}
static var _road_phys: PhysicsMaterial = null
static var _rail_phys: PhysicsMaterial = null
static var _far_material: StandardMaterial3D = null

## Precomputes everything a cell build needs for one road: per-point frames,
## per-segment lengths and dash phases, edge/divider/rail layout and the rail
## gap ranges in arc-length space. `rail_gaps` is what RoadNetwork.recompute_rails
## computed for this road (empty = rails without collision, like TrackBuilder,
## whose configure_rails() is a no-op for an empty list).
static func prepare_road(index: int, def: RoadDef, rail_gaps: Array) -> Dictionary:
	var points: Array[Vector3] = def.points
	var n := points.size()
	var table := {"index": index, "n": n, "valid": n >= 3}
	if n < 3:
		return table
	var closed := def.closed
	var width := def.width
	var banking := def.banking
	var bank := PackedFloat32Array()
	if def.bank_angles.size() == n:
		bank = def.bank_angles
	var mixed := def.has_surface_profile()
	var centers := PackedVector3Array()
	var crosses := PackedVector3Array()
	var forwards := PackedVector3Array()
	var ups := PackedVector3Array()
	centers.resize(n)
	crosses.resize(n)
	forwards.resize(n)
	ups.resize(n)
	var arc := PackedFloat32Array()
	arc.resize(n)
	var run := 0.0
	for i in n:
		var frame := TrackBuilder.frame_at(points, i, closed, banking, bank)
		centers[i] = frame["center"]
		crosses[i] = frame["cross"]
		forwards[i] = frame["forward"]
		ups[i] = TrackBuilder._frame_normal(frame)
		if i > 0:
			run += points[i - 1].distance_to(points[i])
		arc[i] = run
	var seg_count := n if closed else n - 1
	var seg_len := PackedFloat32Array()
	# Double precision, like TrackBuilder's running path_distance (the dash phase
	# at km 20 would drift in float32).
	var dash_start := PackedFloat64Array()
	seg_len.resize(seg_count)
	dash_start.resize(seg_count)
	var path_distance := 0.0
	for s in seg_count:
		var j := (s + 1) % n if closed else s + 1
		var length := points[s].distance_to(points[j])
		seg_len[s] = length
		dash_start[s] = path_distance
		# TrackBuilder._build_dashed_edge_mesh skips (and does not accumulate)
		# degenerate segments.
		if length > 0.0001:
			path_distance += length
	table["closed"] = closed
	table["width"] = width
	table["tier"] = def.tier
	table["surface"] = def.surface
	table["mixed"] = mixed
	table["loose"] = TrackBuilder.loose_weights(points, def.point_surfaces, closed) if mixed else PackedFloat32Array()
	table["arc"] = arc
	table["center"] = centers
	table["cross"] = crosses
	table["forward"] = forwards
	table["up"] = ups
	table["seg_count"] = seg_count
	table["seg_len"] = seg_len
	table["dash_start"] = dash_start
	# Edge lines (TrackBuilder: offset +-(w/2 - 0.5), 1 m wide, tier colours;
	# a mixed-surface road paints its own in the shader).
	var edges: Array = []
	if not mixed:
		var colors: Array = TrackBuilder.TIER_EDGE_COLORS.get(def.tier, TrackBuilder.TIER_EDGE_COLORS[RoadDef.Tier.ARTERIAL])
		edges.append([width * 0.5 - 0.5, colors[0] as Color])
		edges.append([-(width * 0.5 - 0.5), colors[1] as Color])
	table["edges"] = edges
	var dividers := PackedFloat32Array()
	if def.show_lane_dividers and not mixed:
		var lane_count: int = RoadDef.lane_count_for(width)
		for boundary in range(1, lane_count):
			dividers.append(-width * 0.5 + width * float(boundary) / float(lane_count))
	table["dividers"] = dividers
	# Rails: per enabled slot, offset and arc-length skip ranges.
	var rails: Array = []
	if def.rail_side_count() > 0:
		var rail_arc := PackedFloat32Array()
		rail_arc.resize(n)
		var total := 0.0
		for i in n:
			rail_arc[i] = total
			if closed:
				total += points[i].distance_to(points[(i + 1) % n])
			elif i + 1 < n:
				total += points[i].distance_to(points[i + 1])
		var mask := def.rail_sides_mask()
		var offsets: Array[float] = [width * 0.5 + TrackBuilder.RAIL_GAP, -(width * 0.5 + TrackBuilder.RAIL_GAP)]
		var laterals := PackedVector3Array()
		laterals.resize(n)
		for i in n:
			var lateral := Vector3.UP.cross(forwards[i]).normalized()
			if lateral.length_squared() < 0.0001:
				lateral = crosses[i]
			laterals[i] = lateral
		table["lateral"] = laterals
		table["rail_arc"] = rail_arc
		table["rail_total"] = total
		for slot in 2:
			if (mask & TrackBuilder.rail_side_bit(slot)) == 0:
				continue
			var open_ranges: Array = def.rail_open_ranges_for(TrackBuilder.rail_side_bit(slot))
			rails.append({
				"offset": offsets[slot],
				"ranges": _rail_gap_ranges(points, rail_arc, total, rail_gaps, open_ranges, closed),
			})
	table["rails"] = rails
	table["rail_collision"] = not rail_gaps.is_empty() and not rails.is_empty()
	return table

## Arc-length skip ranges of one rail slot, exactly as TrackBuilder._build_rail_mesh
## derives them (junction gaps by nearest point, per-side chain-index ranges).
static func _rail_gap_ranges(points: Array[Vector3], arc: PackedFloat32Array, total: float, gaps: Array, open_ranges: Array, closed: bool) -> Array:
	var n := points.size()
	var out: Array = []
	for gap in gaps:
		if gap is Dictionary and gap.has("start") and gap.has("end"):
			var start_dist := arc[_nearest_index(points, gap["start"])]
			var end_dist := arc[_nearest_index(points, gap["end"])]
			if closed and end_dist < start_dist:
				end_dist += total
			out.append([start_dist, end_dist])
		elif gap is Vector3:
			var gap_dist := arc[_nearest_index(points, gap)]
			out.append([gap_dist - TrackBuilder.RAIL_GAP_RADIUS, gap_dist + TrackBuilder.RAIL_GAP_RADIUS])
	for r in open_ranges:
		var from_i: int = clampi(int(r[0]), 0, n - 1)
		var to_i: int = clampi(int(r[1]), 0, n - 1)
		if to_i < from_i:
			var swap := from_i
			from_i = to_i
			to_i = swap
		var start_d: float = arc[from_i]
		var end_d: float = arc[to_i]
		if closed and to_i == 0 and from_i > 0:
			end_d += total
		elif to_i < n - 1:
			end_d = (arc[to_i] + arc[to_i + 1]) * 0.5
		else:
			end_d = total
		out.append([start_d, end_d])
	return out

static func _nearest_index(points: Array[Vector3], target: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in points.size():
		var d := points[i].distance_squared_to(target)
		if d < best_d:
			best_d = d
			best = i
	return best

## Whether rail segment `s` of `table` is cut by any of `ranges` (inclusive
## test, TrackBuilder's rule).
static func _rail_segment_skipped(table: Dictionary, s: int, ranges: Array) -> bool:
	var n: int = table["n"]
	var j := (s + 1) % n
	var arc: PackedFloat32Array = table["rail_arc"]
	var seg_start := arc[s]
	var seg_end := arc[j]
	if bool(table["closed"]) and j == 0:
		seg_end += float(table["rail_total"])
	for r in ranges:
		if seg_end >= float(r[0]) and seg_start <= float(r[1]):
			return true
	return false

## Cell of a world XZ position.
static func cell_of(pos: Vector3, cell_size: float) -> Vector2i:
	return Vector2i(floori(pos.x / cell_size), floori(pos.z / cell_size))

## Segment -> cell assignment of one prepared road: { Vector2i: PackedInt32Array }
## with the segment indices in ascending order. A segment belongs to the cell of
## its midpoint, so every segment is in exactly one cell.
static func cell_segments(table: Dictionary, cell_size: float) -> Dictionary:
	var out := {}
	if not bool(table.get("valid", false)):
		return out
	var n: int = table["n"]
	var centers: PackedVector3Array = table["center"]
	for s in int(table["seg_count"]):
		var j := (s + 1) % n
		var mid := (centers[s] + centers[j]) * 0.5
		var cell := cell_of(mid, cell_size)
		var segs: PackedInt32Array = out.get(cell, PackedInt32Array())
		segs.append(s)
		out[cell] = segs
	return out

static func _bucket(buckets: Dictionary, key: String, spec: Dictionary) -> Dictionary:
	if not buckets.has(key):
		var b := spec.duplicate()
		b["v"] = PackedVector3Array()
		b["nrm"] = PackedVector3Array()
		b["idx"] = PackedInt32Array()
		b["col"] = PackedColorArray()
		b["uv"] = PackedVector2Array()
		buckets[key] = b
	return buckets[key]

## Builds one cell. `entries` = [[road_index, PackedInt32Array segments], ...];
## `tables` = every prepared road (indexed by road index). Returns
## { "buckets": {key: {kind, mat..., v, nrm, idx, col, uv}},
##   "road_faces": PackedVector3Array, "rail_faces": PackedVector3Array,
##   "segments": int, "usec": int }.
static func build_cell(tables: Array, entries: Array) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var buckets := {}
	var road_faces := PackedVector3Array()
	var rail_faces := PackedVector3Array()
	var seg_total := 0
	for entry in entries:
		var table: Dictionary = tables[int(entry[0])]
		if not bool(table.get("valid", false)):
			continue
		var segs: PackedInt32Array = entry[1]
		seg_total += segs.size()
		_emit_surface(table, segs, buckets, road_faces)
		_emit_edges(table, segs, buckets)
		_emit_dividers(table, segs, buckets)
		_emit_rails(table, segs, buckets, rail_faces)
	return {
		"buckets": buckets,
		"road_faces": _snap_faces(road_faces),
		"rail_faces": _snap_faces(rail_faces),
		"segments": seg_total,
		"usec": Time.get_ticks_usec() - t0,
	}

static func _emit_surface(table: Dictionary, segs: PackedInt32Array, buckets: Dictionary, faces: PackedVector3Array) -> void:
	var n: int = table["n"]
	var closed: bool = table["closed"]
	var width: float = table["width"]
	var mixed: bool = table["mixed"]
	var centers: PackedVector3Array = table["center"]
	var crosses: PackedVector3Array = table["cross"]
	var ups: PackedVector3Array = table["up"]
	var seg_len: PackedFloat32Array = table["seg_len"]
	var key := ""
	var spec := {}
	if mixed:
		key = "m:%s" % width
		spec = {"kind": KIND_SURFACE, "mat": "mixed", "width": width}
	else:
		key = "s:%d:%d" % [int(table["surface"]), int(table["tier"])]
		spec = {"kind": KIND_SURFACE, "mat": "surface", "surface": int(table["surface"]), "tier": int(table["tier"])}
	var b := _bucket(buckets, key, spec)
	var v: PackedVector3Array = b["v"]
	var nrm: PackedVector3Array = b["nrm"]
	var idx: PackedInt32Array = b["idx"]
	var col: PackedColorArray = b["col"]
	var uv: PackedVector2Array = b["uv"]
	var loose: PackedFloat32Array = table["loose"]
	var arc: PackedFloat32Array = table["arc"]
	for s in segs:
		var j := (s + 1) % n
		var l0 := centers[s] - crosses[s] * width * 0.5
		var r0 := centers[s] + crosses[s] * width * 0.5
		var l1 := centers[j] - crosses[j] * width * 0.5
		var r1 := centers[j] + crosses[j] * width * 0.5
		var base := v.size()
		v.append(l0)
		v.append(r0)
		v.append(l1)
		v.append(r1)
		nrm.append(ups[s])
		nrm.append(ups[s])
		nrm.append(ups[j])
		nrm.append(ups[j])
		if mixed:
			var c0 := Color(loose[s], 0.0, 0.0, 1.0)
			var c1 := Color(loose[j], 0.0, 0.0, 1.0)
			col.append(c0)
			col.append(c0)
			col.append(c1)
			col.append(c1)
			uv.append(Vector2(-1.0, arc[s]))
			uv.append(Vector2(1.0, arc[s]))
			uv.append(Vector2(-1.0, arc[j]))
			uv.append(Vector2(1.0, arc[j]))
		TrackBuilder._append_up_quad(idx, base, base + 1, base + 2, base + 3)
		# Collision: same vertices and winding; TrackBuilder's collision strip
		# skips segments shorter than 0.5 m on open roads only.
		if not closed and seg_len[s] < 0.5:
			continue
		# _append_up_quad order: (l1, r0, l0), (l1, r1, r0).
		faces.append(l1)
		faces.append(r0)
		faces.append(l0)
		faces.append(l1)
		faces.append(r1)
		faces.append(r0)
	b["v"] = v
	b["nrm"] = nrm
	b["idx"] = idx
	b["col"] = col
	b["uv"] = uv

static func _emit_edges(table: Dictionary, segs: PackedInt32Array, buckets: Dictionary) -> void:
	var edges: Array = table["edges"]
	if edges.is_empty():
		return
	var n: int = table["n"]
	var centers: PackedVector3Array = table["center"]
	var crosses: PackedVector3Array = table["cross"]
	var ups: PackedVector3Array = table["up"]
	for edge in edges:
		var offset: float = edge[0]
		var color: Color = edge[1]
		var b := _bucket(buckets, "e:" + color.to_html(), {"kind": KIND_EDGE, "mat": "edge", "color": color})
		var v: PackedVector3Array = b["v"]
		var nrm: PackedVector3Array = b["nrm"]
		var idx: PackedInt32Array = b["idx"]
		for s in segs:
			var j := (s + 1) % n
			# TrackBuilder._build_edge_mesh: line_center = center + UP*0.012 + cross*offset,
			# then -+ cross * width(1.0) * 0.5.
			var lc0 := centers[s] + Vector3.UP * 0.012 + crosses[s] * offset
			var lc1 := centers[j] + Vector3.UP * 0.012 + crosses[j] * offset
			var base := v.size()
			v.append(lc0 - crosses[s] * 1.0 * 0.5)
			v.append(lc0 + crosses[s] * 1.0 * 0.5)
			v.append(lc1 - crosses[j] * 1.0 * 0.5)
			v.append(lc1 + crosses[j] * 1.0 * 0.5)
			nrm.append(ups[s])
			nrm.append(ups[s])
			nrm.append(ups[j])
			nrm.append(ups[j])
			TrackBuilder._append_up_quad(idx, base, base + 1, base + 2, base + 3)
		b["v"] = v
		b["nrm"] = nrm
		b["idx"] = idx

static func _emit_dividers(table: Dictionary, segs: PackedInt32Array, buckets: Dictionary) -> void:
	var dividers: PackedFloat32Array = table["dividers"]
	if dividers.is_empty():
		return
	var n: int = table["n"]
	var centers: PackedVector3Array = table["center"]
	var crosses: PackedVector3Array = table["cross"]
	var seg_len: PackedFloat32Array = table["seg_len"]
	var dash_start: PackedFloat64Array = table["dash_start"]
	var b := _bucket(buckets, "d", {"kind": KIND_DIVIDER, "mat": "divider"})
	var v: PackedVector3Array = b["v"]
	var nrm: PackedVector3Array = b["nrm"]
	var idx: PackedInt32Array = b["idx"]
	var width := TrackBuilder.LANE_DIVIDER_WIDTH
	for offset in dividers:
		for s in segs:
			var segment_length := seg_len[s]
			if segment_length <= 0.0001:
				continue
			var j := (s + 1) % n
			var center_a := centers[s]
			var center_b := centers[j]
			var cross_a := crosses[s]
			var cross_b := crosses[j]
			var path_distance := dash_start[s]
			var cursor := 0.0
			# Same loop as TrackBuilder._build_dashed_edge_mesh, seeded with this
			# segment's path distance so the dash phase runs on across cells.
			while cursor < segment_length - 0.0001:
				var phase := fposmod(path_distance + cursor, TrackBuilder.LANE_DASH_PERIOD)
				var boundary_distance := TrackBuilder.LANE_DASH_PERIOD - phase if phase >= TrackBuilder.LANE_DASH_LENGTH else TrackBuilder.LANE_DASH_LENGTH - phase
				var next_cursor := minf(cursor + boundary_distance, segment_length)
				if phase < TrackBuilder.LANE_DASH_LENGTH and next_cursor > cursor:
					var t0 := cursor / segment_length
					var t1 := next_cursor / segment_length
					var center0 := center_a.lerp(center_b, t0)
					var center1 := center_a.lerp(center_b, t1)
					var cross0 := cross_a.lerp(cross_b, t0).normalized()
					var cross1 := cross_a.lerp(cross_b, t1).normalized()
					var line0 := center0 + Vector3.UP * 0.014 + cross0 * offset
					var line1 := center1 + Vector3.UP * 0.014 + cross1 * offset
					var base := v.size()
					v.append(line0 - cross0 * width * 0.5)
					v.append(line0 + cross0 * width * 0.5)
					v.append(line1 - cross1 * width * 0.5)
					v.append(line1 + cross1 * width * 0.5)
					var dash_up := TrackBuilder._frame_normal({"cross": cross0, "forward": (center1 - center0).normalized()})
					for _k in 4:
						nrm.append(dash_up)
					TrackBuilder._append_up_quad(idx, base, base + 1, base + 2, base + 3)
				if next_cursor <= cursor:
					cursor += 0.0001
				else:
					cursor = next_cursor
	b["v"] = v
	b["nrm"] = nrm
	b["idx"] = idx

static func _emit_rails(table: Dictionary, segs: PackedInt32Array, buckets: Dictionary, faces: PackedVector3Array) -> void:
	var rails: Array = table["rails"]
	if rails.is_empty():
		return
	var n: int = table["n"]
	var centers: PackedVector3Array = table["center"]
	var crosses: PackedVector3Array = table["cross"]
	var laterals: PackedVector3Array = table["lateral"]
	var collide: bool = table["rail_collision"]
	var b := _bucket(buckets, "r", {"kind": KIND_RAIL, "mat": "rail"})
	var v: PackedVector3Array = b["v"]
	var nrm: PackedVector3Array = b["nrm"]
	var idx: PackedInt32Array = b["idx"]
	for rail in rails:
		var offset: float = rail["offset"]
		var ranges: Array = rail["ranges"]
		for s in segs:
			if _rail_segment_skipped(table, s, ranges):
				continue
			var j := (s + 1) % n
			var base := v.size()
			for p in [s, j]:
				var lateral := laterals[p]
				var rail_center := centers[p] + crosses[p] * offset
				var half_thickness := lateral * TrackBuilder.RAIL_THICKNESS * 0.5
				var bottom := rail_center
				var top := rail_center + Vector3.UP * TrackBuilder.RAIL_HEIGHT
				var inner_normal := (-lateral + Vector3.UP).normalized()
				var outer_normal := (lateral + Vector3.UP).normalized()
				v.append(bottom - half_thickness)
				v.append(bottom + half_thickness)
				v.append(top - half_thickness)
				v.append(top + half_thickness)
				nrm.append(inner_normal)
				nrm.append(outer_normal)
				nrm.append(inner_normal)
				nrm.append(outer_normal)
			# TrackBuilder._build_rail_mesh index pattern with base = s*4,
			# next_base = j*4; here the segment's own 8 vertices.
			var nb := base + 4
			var tri := PackedInt32Array([
				base, base + 2, nb,
				nb, base + 2, nb + 2,
				base + 1, nb + 1, base + 3,
				nb + 1, nb + 3, base + 3,
				base + 2, nb + 3, nb + 2,
				nb + 3, base + 3, nb + 2,
			])
			idx.append_array(tri)
			if collide:
				for k in tri:
					faces.append(v[k])
	b["v"] = v
	b["nrm"] = nrm
	b["idx"] = idx

## Far LOD of the whole network: per point, three strips (left edge, carriageway,
## right edge) in vertex colour, dropped by FAR_DROP. No collision, no shadow.
static func build_far(tables: Array) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	var drop := Vector3.UP * FAR_DROP
	for table: Dictionary in tables:
		if not bool(table.get("valid", false)):
			continue
		var n: int = table["n"]
		var width: float = table["width"]
		var centers: PackedVector3Array = table["center"]
		var crosses: PackedVector3Array = table["cross"]
		var ups: PackedVector3Array = table["up"]
		var tier: int = table["tier"]
		var edge_colors: Array = TrackBuilder.TIER_EDGE_COLORS.get(tier, TrackBuilder.TIER_EDGE_COLORS[RoadDef.Tier.ARTERIAL])
		var surface_color := TrackBuilder.surface_albedo(RoadDef.Surface.ASPHALT) if bool(table["mixed"]) \
			else TrackBuilder.tier_surface_albedo(tier, int(table["surface"]))
		var right_color: Color = edge_colors[0]
		var left_color: Color = edge_colors[1]
		if bool(table["mixed"]):
			right_color = surface_color
			left_color = surface_color
		var half := width * 0.5
		var inner := maxf(half - 1.0, 0.0)
		var first := v.size()
		# Strip offsets (along cross) and colours, 6 vertices per point.
		var cuts := [-half, -inner, -inner, inner, inner, half]
		var colors := [left_color, left_color, surface_color, surface_color, right_color, right_color]
		for i in n:
			for k in 6:
				v.append(centers[i] + crosses[i] * float(cuts[k]) - drop)
				nrm.append(ups[i])
				col.append(colors[k])
		for s in int(table["seg_count"]):
			var j := (s + 1) % n
			var a := first + s * 6
			var c := first + j * 6
			for strip in 3:
				var l := strip * 2
				TrackBuilder._append_up_quad(idx, a + l, a + l + 1, c + l, c + l + 1)
	return {"v": v, "nrm": nrm, "col": col, "idx": idx, "usec": Time.get_ticks_usec() - t0}

## --- main thread ---------------------------------------------------------

## Creates every material the prepared roads can ask for, so no cell ever pays
## for one on the main thread mid-drive (a surface material builds a 512 px
## NoiseTexture2D, the DIRT tier two: up to ~150 ms the first time). Keys and
## specs are the ones the _emit_* functions use. Returns the number of keys.
static func warm_materials(tables: Array) -> int:
	var keys := material_specs(tables)
	for key: String in keys:
		material_for(key, keys[key])
	return keys.size()

## One tiny, far-away MeshInstance3D per material, in the vertex format the
## cells use (mixed surfaces carry COLOR + UV) and with the cells' shadow
## setting. Creating a material is cheap; the first instance that DRAWS with it
## compiles its shader/pipelines on the main thread (measured 160 ms for the
## DIRT tier's triplanar variant, at a fast-travel). Added at load, these move
## that cost into the loading screen. They stay (14 one-quad instances, culled).
static func warm_instances(tables: Array, flat_shadows: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "RoadMaterialWarm"
	var specs := material_specs(tables)
	for key: String in specs:
		var spec: Dictionary = specs[key]
		var b := {
			"v": PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1)]),
			"nrm": PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]),
			"idx": PackedInt32Array(),
		}
		TrackBuilder._append_up_quad(b["idx"], 0, 1, 2, 3)
		if String(spec["mat"]) == "mixed":
			b["col"] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
			b["uv"] = PackedVector2Array([Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)])
		var mi := MeshInstance3D.new()
		mi.name = "Warm_" + key.replace(":", "_")
		mi.mesh = _array_mesh(b)
		mi.material_override = material_for(key, spec)
		var kind: int = spec["kind"]
		if (kind == KIND_EDGE or kind == KIND_DIVIDER) and not flat_shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(0.0, -20000.0, 0.0)
		root.add_child(mi)
	return root

## { bucket key: spec } of every material the prepared roads can produce.
static func material_specs(tables: Array) -> Dictionary:
	var keys := {}
	for table: Dictionary in tables:
		if not bool(table.get("valid", false)):
			continue
		if bool(table["mixed"]):
			var width: float = table["width"]
			keys["m:%s" % width] = {"kind": KIND_SURFACE, "mat": "mixed", "width": width}
		else:
			keys["s:%d:%d" % [int(table["surface"]), int(table["tier"])]] = {"kind": KIND_SURFACE, "mat": "surface", "surface": int(table["surface"]), "tier": int(table["tier"])}
		for edge in table["edges"]:
			var color: Color = edge[1]
			keys["e:" + color.to_html()] = {"kind": KIND_EDGE, "mat": "edge", "color": color}
		if not (table["dividers"] as PackedFloat32Array).is_empty():
			keys["d"] = {"kind": KIND_DIVIDER, "mat": "divider"}
		if not (table["rails"] as Array).is_empty():
			keys["r"] = {"kind": KIND_RAIL, "mat": "rail"}
	return keys

## Shared material for a bucket spec (created once per key, reused by every cell).
static func material_for(key: String, spec: Dictionary) -> Material:
	if _materials.has(key):
		return _materials[key]
	var mat: Material = null
	var scratch := TrackBuilder.new()
	match String(spec.get("mat", "")):
		"surface":
			mat = scratch._surface_material(int(spec["surface"]), int(spec["tier"]))
		"mixed":
			mat = scratch._mixed_surface_material(float(spec["width"]))
		"edge":
			var edge := StandardMaterial3D.new()
			edge.albedo_color = spec["color"] as Color
			edge.roughness = 0.5
			edge.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat = edge
		"divider":
			mat = scratch._lane_divider_material()
		_:
			mat = scratch._rail_material()
	scratch.free()
	_materials[key] = mat
	return mat

static func _phys(friction: float) -> PhysicsMaterial:
	if friction == ROAD_FRICTION:
		if _road_phys == null:
			_road_phys = PhysicsMaterial.new()
			_road_phys.friction = ROAD_FRICTION
		return _road_phys
	if _rail_phys == null:
		_rail_phys = PhysicsMaterial.new()
		_rail_phys.friction = RAIL_FRICTION
	return _rail_phys

static func _array_mesh(b: Dictionary) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = b["v"]
	arrays[Mesh.ARRAY_NORMAL] = b["nrm"]
	arrays[Mesh.ARRAY_INDEX] = b["idx"]
	var col: PackedColorArray = b.get("col", PackedColorArray())
	if col.size() == (b["v"] as PackedVector3Array).size() and col.size() > 0:
		arrays[Mesh.ARRAY_COLOR] = col
	var uv: PackedVector2Array = b.get("uv", PackedVector2Array())
	if uv.size() == (b["v"] as PackedVector3Array).size() and uv.size() > 0:
		arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Mesh.create_trimesh_shape() (what TrackBuilder uses) welds its vertices on a
## 0.1 mm grid; the streamed faces get the same snap so the collision is the
## one the whole-road path produced, bit for bit.
const COLLISION_SNAP := Vector3(0.0001, 0.0001, 0.0001)

static func _snap_faces(faces: PackedVector3Array) -> PackedVector3Array:
	for i in faces.size():
		faces[i] = faces[i].snapped(COLLISION_SNAP)
	return faces

static func _body(body_name: String, faces: PackedVector3Array, friction: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.physics_material_override = _phys(friction)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	return body

## Turns a build_cell() result into a node: one MeshInstance3D per bucket
## (shared material), one StaticBody3D for the carriageway and one for the
## rails that collide. `flat_shadows` = whether the painted lines (edge lines,
## lane dashes) cast shadows (TrackBuilder's default ON; the stream turns it
## off). The carriageway and the rails always cast, as before.
static func instantiate_cell(cell: Vector2i, result: Dictionary, flat_shadows: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "RoadCell_%d_%d" % [cell.x, cell.y]
	var buckets: Dictionary = result["buckets"]
	var keys := buckets.keys()
	keys.sort()
	for key: String in keys:
		var b: Dictionary = buckets[key]
		if (b["idx"] as PackedInt32Array).is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Mesh_" + key.replace(":", "_")
		mi.mesh = _array_mesh(b)
		mi.material_override = material_for(key, b)
		var kind: int = b["kind"]
		# The carriageway keeps its shadow (an overpass or a ramp on a fill
		# shades the ground under it); paint lies 12-14 mm on the carriageway
		# and cannot cast anything visible.
		if (kind == KIND_EDGE or kind == KIND_DIVIDER) and not flat_shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var road_faces: PackedVector3Array = result["road_faces"]
	if not road_faces.is_empty():
		root.add_child(_body("RoadCollision", road_faces, ROAD_FRICTION))
	var rail_faces: PackedVector3Array = result["rail_faces"]
	if not rail_faces.is_empty():
		root.add_child(_body("RailCollision", rail_faces, RAIL_FRICTION))
	return root

static func instantiate_far(result: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "RoadFar"
	if (result["idx"] as PackedInt32Array).is_empty():
		return mi
	mi.mesh = _array_mesh(result)
	if _far_material == null:
		_far_material = StandardMaterial3D.new()
		_far_material.vertex_color_use_as_albedo = true
		_far_material.vertex_color_is_srgb = true
		_far_material.roughness = TrackBuilder.surface_roughness(RoadDef.Surface.ASPHALT)
		_far_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = _far_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
