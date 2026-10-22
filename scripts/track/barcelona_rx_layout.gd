class_name BarcelonaRxLayout
extends RefCounted

## THE geometry source of truth for Circuit de Barcelona-Catalunya — Rallycross
## (GT7 track build #2): a ~1,133 m closed DIRT rallycross circuit with two
## jumps, two sine-eased berms and a tight right-hand hairpin.
##
## Pure and static: no scene, no Resource, no engine state. Everything that
## needs "where is the road / how banked is it / where is the jump" (the track
## scene, the terrain bake, the dressing, the barrier colliders, the layout
## tests) reads it from here, so the mesh, the collision, the ground and the
## props can never drift apart.
##
## GENERATION — convex polygon + circular fillets, NOT Catmull-Rom.
## The plan (`docs/plans/track_barcelona_rallycross.md` §3.1) proposed a 14-point
## closed Catmull-Rom control table with a hairpin notch (its P7/P8/P9). That is
## geometrically incompatible with the plan's OWN acceptance criterion A3 and its
## direction test, which require `cross(t1,t2).y < 0` at EVERY in-corner sample
## (all right-hand turns): a simple closed curve whose every turn has the same
## sign is necessarily CONVEX, and a convex turn table cannot contain an inward
## hairpin notch. Building the authored spline verbatim would therefore fail the
## plan's own right-hand assertion. This class instead builds a CONVEX, all
## right-hand loop from 7 polygon vertices joined by circular fillets (the
## fillet's circle is the tangent-turn approximation of the polygon corner), so
## A3 holds by construction. The plan's dropped chicane and its P8 "hairpin"
## (reinterpreted as the tightest convex corner, V0 / T1) are recorded in the
## plan's STATUS block.
##
## LAYOUT (world XZ, Y up):
##   - 7 convex vertices V0..V6 (see VERTICES), travel order from the grid.
##   - each corner gets a fillet radius R_i driven by TFRAC[i] and the shorter of
##     its two adjacent edge lengths (so a corner never overruns its edges).
##   - the resulting closed walk (straights + arcs) is uniformly rescaled so its
##     length is exactly TARGET_PERIMETER, centred on its own mean, and given a
##     grid-relative parameterisation by OFF (grid at public arc 0, on the start
##     straight; start/finish line at arc 991.375, 141.62 m further on).
##   Corners are named T1..T7 in travel order (T1 = V0 = the tightest corner).
##
## SIGN CONVENTION (load-bearing — both the mesh and the ground bake depend on
## it): TrackBuilder._frame() computes right = forward x UP and rotates the
## cross-section by `angle`, so cross.y = -sin(angle). Every turn here is a RIGHT
## turn, so cross.y < 0, so every bank angle is POSITIVE. With
##   center_y = ROAD_BASE_Y + (WIDTH/2) * |sin(angle)|
## the ROAD-BASE (inner / right) edge rides at ROAD_BASE_Y everywhere, and the
## outfield (left) edge rises to ROAD_BASE_Y + WIDTH*sin(angle) at a bermed
## corner. The right/inner edge being the low one is the mirror of build #1's
## left-turn oval and is pinned by tests/suites/test_barcelona_rx_layout.gd.

## Total centerline length (m). The plan pins 1,133 ± 10 (GT7's rank-2 shortest
## layout); the generator rescales the raw walk so `perimeter()` is exactly this.
const TARGET_PERIMETER := 1133.0
## Track width (m). A rallycross track is wide enough for side-by-side dirt
## running; 12 m gives 1 lane per `RoadDef.lane_count_for` (no lane dividers).
const WIDTH := 12.0
## Total centerline points. 400 = 8 * 50 so every checkpoint lands exactly on a
## point, at a uniform ~2.83 m of arc.
const TOTAL_POINTS := 400
## Point stride between checkpoints (TOTAL_POINTS / CHECKPOINT_COUNT).
const CP_STRIDE := 50
const CHECKPOINT_COUNT := 8
## Index of the start/finish line checkpoint: the LAST index, placed under the
## gantry. LapCounter ticks a lap when index (total - 1) is crossed, so the line
## MUST be the last checkpoint and the grid MUST sit on checkpoint 0.
const START_LINE_INDEX := 7
## Road base height: the inner (right) edge sits exactly here wherever the bank
## is non-zero (and the whole road sits here on the flat straights).
const ROAD_BASE_Y := 0.15
## Ground plain height outside the blend (m).
const PLAIN_Y := -0.25
## Shoulder/berm blend run from the road edge to the plain (m), both sides.
const BLEND_RUN := 18.0
## Visible lip the ground drops over at a road edge (m). Keeps a texel that
## straddles the edge from interpolating ABOVE the asphalt.
const EDGE_DROP := 0.10
## Maximum berm banking (deg). One constant to flatten the whole layout (0.0).
const BANK_MAX_DEG := 7.0
## Generation-arc position of the grid (public arc 0) along the start straight.
## Chosen so both the grid (gen arc 160) and the start/finish line (gen arc
## 18.38) sit on straights, clear of both jump regions.
const OFF := 160.0
## Which lateral side is the outfield (+1 = right of travel, -1 = left). A
## right-hand circuit's outfield is the LEFT, so this is -1: barrier lines sit at
## `OUTFIELD_SIDE * (WIDTH/2 + BARRIER_OFFSET)`.
const OUTFIELD_SIDE := -1.0

## Convex polygon vertices, XZ, in travel order (V0..V6). Travel is clockwise
## seen from above (the mirror of build #1's CCW oval), so every fillet is a
## right-hand turn and every fillet circle centre lies to the right of travel.
const VERTICES: Array[Vector2] = [
	Vector2(210.0, -175.0),  # V0 -> T1 (tightest corner)
	Vector2(225.0, 30.0),    # V1 -> T2 (bermed, 7 deg)
	Vector2(95.0, 175.0),    # V2 -> T3
	Vector2(-40.0, 195.0),   # V3 -> T4
	Vector2(-200.0, 100.0),  # V4 -> T5
	Vector2(-225.0, -60.0),  # V5 -> T6 (bermed, 7 deg)
	Vector2(-70.0, -185.0),  # V6 -> T7
]

## Fillet fraction per vertex: the tangent length trimmed off each edge at that
## corner is `TFRAC[i] * min(adjacent edge lengths)`. Tuned so no adjacent
## corners overrun each other on a shared edge and the loop stays convex.
const TFRAC: Array[float] = [0.10, 0.19, 0.16, 0.16, 0.20, 0.30, 0.10]

## Berm banking: sine-eased +/- half_arc around a corner's apex arc, sign always
## POSITIVE (every corner is a right turn). `corner` is 1-based (T-number).
const BANK_REGIONS: Array[Dictionary] = [
	{"corner": 2, "half_arc": 30.0, "deg": 7.0},
	{"corner": 6, "half_arc": 30.0, "deg": 7.0},
]

## Jumps: a raised-cosine crest over [from, to] (public arc), with an optional
## flat table of width `table` in the middle (table 0 = a single crest). Both
## regions sit on straights (see the generation-segment table).
const JUMP_REGIONS: Array[Dictionary] = [
	{"from": 12.0, "to": 40.0, "height": 1.0, "table": 10.0},   # table-top
	{"from": 108.0, "to": 130.0, "height": 0.8, "table": 0.0},  # single crest
]

## 1-based corners that carry a physical barrier line (the tightest corner plus
## the two bermed ones). The rest of the loop is open dirt with run-off.
const BARRIER_CORNERS: Array[int] = [1, 2, 6]

## MIXED SURFACE -- the single source of truth for where the circuit is loose.
## The real Barcelona-Catalunya rallycross course is ~60 % asphalt (borrowed from
## the F1 circuit) and ~40 % loose gravel/dirt (the infield rallycross section).
## Here that is ONE loose section by public arc (m from the grid), [from, to):
## it starts on the exit of the T1 hairpin (72.1 m) -- the cars leave the tarmac
## hairpin onto the dirt -- carries the single-crest jump (108-130), the T2 berm
## and T3, and rejoins the asphalt on the exit of T4 (522.7 m). Everything else
## (T5, the T6 berm, T7, the S/F line, the grid, the table-top jump and the T1
## hairpin) is asphalt. 453 m of 1,133 = 40.0 % loose.
##
## Consumers, all reading THIS table (never a copy):
##   * `build_surface_profile()` -> `RoadDef.point_surfaces` -> TrackBuilder's
##     mixed asphalt/dirt road material AND SurfaceRegistry's per-segment grip
##     (Surface.GRAVEL -> the GRAVEL grip contract, 0.85 / 0.80);
##   * the scene's ground bake (loose verge colour beside the dirt section).
## The layout has no joker branch: a joker needs an alternative route + a
## per-car joker counter, which this single-loop layout does not model.
const DIRT_SECTIONS: Array[Vector2] = [
	Vector2(72.0, 525.0),
]

## --- static build cache (build once, deterministic, no engine state) ---------

static var _built := false
static var _raw: Array[Dictionary] = []
static var _p_raw := 0.0
static var _scale := 1.0
static var _mean_raw := Vector2.ZERO
## Public arc of each corner's arc start and its arc length, indexed by vertex.
static var _corner_from := PackedFloat32Array()
static var _corner_len := PackedFloat32Array()


## Uniform arc-length spacing between two consecutive centerline points.
static func spacing() -> float:
	return TARGET_PERIMETER / float(TOTAL_POINTS)


## Total centerline length (m). Exactly TARGET_PERIMETER by construction.
static func perimeter() -> float:
	return TARGET_PERIMETER


## Arc length (m) from the grid (point 0) to point `index`.
static func arc_of_index(index: int) -> float:
	return float(index) * spacing()


## Centerline points (Y included) at every uniform arc step. Deterministic: the
## same build twice is element-wise identical (the determinism test relies on it).
static func build_centerline() -> Array[Vector3]:
	_ensure_built()
	var points: Array[Vector3] = []
	var step := spacing()
	for i in TOTAL_POINTS:
		var s := float(i) * step
		points.append(_make_point(s))
	return points


## Signed bank angle (radians) per centerline point, in TrackBuilder._frame's
## sign space (POSITIVE = right turn). Zero outside every BANK_REGIONS arc.
static func build_bank_profile() -> PackedFloat32Array:
	_ensure_built()
	var profile := PackedFloat32Array()
	profile.resize(TOTAL_POINTS)
	var step := spacing()
	for i in TOTAL_POINTS:
		profile[i] = _bank_rad_at_arc(float(i) * step)
	return profile


## Centerline indices that carry a checkpoint, in travel order: 0, 50, ... 350.
static func checkpoint_indices() -> PackedInt32Array:
	var indices := PackedInt32Array()
	for i in CHECKPOINT_COUNT:
		indices.append(i * CP_STRIDE)
	return indices


## Arc length of the start/finish line (checkpoint START_LINE_INDEX): 991.375 m.
static func start_line_arc() -> float:
	return arc_of_index(START_LINE_INDEX * CP_STRIDE)


## Corner names in travel order: T1..T7 (T1 = the tightest, at V0).
static func corner_names() -> Array[String]:
	var names: Array[String] = []
	for i in VERTICES.size():
		names.append("T%d" % (i + 1))
	return names


## Arc range [from, to) of each corner, in the same order as corner_names().
## None of these wrap around the grid.
static func corner_arc_ranges() -> Array[Vector2]:
	_ensure_built()
	var ranges: Array[Vector2] = []
	for i in VERTICES.size():
		ranges.append(Vector2(_corner_from[i], _corner_from[i] + _corner_len[i]))
	return ranges


## Arc range of the barrier line, in BARRIER_CORNERS order (T1, T2, T6).
static func barrier_arc_ranges() -> Array[Vector2]:
	var all := corner_arc_ranges()
	var ranges: Array[Vector2] = []
	for corner in BARRIER_CORNERS:
		ranges.append(all[corner - 1])
	return ranges


## Total arc length (m) covered by the barrier line.
static func barrier_arc_length() -> float:
	var total := 0.0
	for r in barrier_arc_ranges():
		total += r.y - r.x
	return total


## Arc range [from, to] of each jump, in JUMP_REGIONS order.
static func jump_arc_ranges() -> Array[Vector2]:
	var ranges: Array[Vector2] = []
	for r in JUMP_REGIONS:
		ranges.append(Vector2(r["from"], r["to"]))
	return ranges


## True when public arc `s` (wrapped) lies on a loose (dirt/gravel) section.
static func is_loose_at_arc(s: float) -> bool:
	var arc := fposmod(s, TARGET_PERIMETER)
	for r in DIRT_SECTIONS:
		if arc >= r.x and arc < r.y:
			return true
	return false


## `RoadDef.Surface` at public arc `s`: GRAVEL on a DIRT_SECTIONS range, else
## ASPHALT.
static func surface_at_arc(s: float) -> int:
	return RoadDef.Surface.GRAVEL if is_loose_at_arc(s) else RoadDef.Surface.ASPHALT


## The `SurfaceRegistry` key a car ON the road reports at public arc `s`.
static func surface_key_at_arc(s: float) -> String:
	return SurfaceRegistry.GRAVEL if is_loose_at_arc(s) else SurfaceRegistry.ASPHALT


## One `RoadDef.Surface` per centerline point = the surface of the segment that
## STARTS at that point (`RoadDef.point_surfaces` semantics), sampled at the
## segment MIDPOINT so a section boundary is honoured to within half a spacing
## (1.4 m). Deterministic.
static func build_surface_profile() -> PackedByteArray:
	var profile := PackedByteArray()
	profile.resize(TOTAL_POINTS)
	var step := spacing()
	for i in TOTAL_POINTS:
		profile[i] = surface_at_arc((float(i) + 0.5) * step)
	return profile


## Total loose arc length (m) over every DIRT_SECTIONS range.
static func dirt_arc_length() -> float:
	var total := 0.0
	for r in DIRT_SECTIONS:
		total += r.y - r.x
	return total


## Public arc of a corner's apex (the midpoint of its arc), 1-based `corner`.
static func corner_apex_arc(corner: int) -> float:
	_ensure_built()
	var i := corner - 1
	return fposmod(_corner_from[i] + _corner_len[i] * 0.5, TARGET_PERIMETER)


## Centerline point (Y included) at arc length `s`, wrapping around the loop.
static func point_at_arc(s: float) -> Vector3:
	_ensure_built()
	return _make_point(fposmod(s, TARGET_PERIMETER))


## Road frame at arc `s`: the same center/forward/right/cross the mesh is built
## from, so dressing placed at `center + cross * offset` sits ON the banked
## cross-section. `cross` is the banked cross direction (cross.y = -sin(bank)).
static func frame_at_arc(s: float) -> Dictionary:
	var delta := 0.25
	var a := point_at_arc(s - delta)
	var b := point_at_arc(s + delta)
	var center := point_at_arc(s)
	var forward := (b - a).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var angle := _bank_rad_at_arc(s)
	var cross := right * cos(angle) - Vector3.UP * sin(angle)
	return {
		"center": center,
		"forward": forward,
		"right": right,
		"cross": cross,
		"bank": angle,
	}


## Signed bank angle (rad) at arc `s`: 0 outside every BANK_REGIONS arc, sine-
## eased to +BANK_MAX_DEG at each bermed corner's apex.
static func bank_rad_at_arc(s: float) -> float:
	return _bank_rad_at_arc(s)


## Raised-cosine jump lift (m) at public arc `s`, wrapping around the loop.
## Zero outside both JUMP_REGIONS; `height` at each crest; flat `table` in the
## middle of region 1 so a table-top jump can be cleared cleanly.
static func jump_lift(s: float) -> float:
	var arc := fposmod(s, TARGET_PERIMETER)
	var total := 0.0
	for r in JUMP_REGIONS:
		var lo: float = r["from"]
		var hi: float = r["to"]
		if hi <= lo or arc < lo or arc > hi:
			continue
		var h: float = r["height"]
		var table: float = r["table"]
		var center := (lo + hi) * 0.5
		if table > 0.0 and absf(arc - center) <= table * 0.5:
			total += h
			continue
		var ramp := maxf((hi - lo - table) * 0.5, 0.0001)
		var u := 0.0
		if arc < center:
			u = clampf((arc - lo) / ramp, 0.0, 1.0)
		else:
			u = clampf((hi - arc) / ramp, 0.0, 1.0)
		total += h * (0.5 - 0.5 * cos(PI * u))
	return total


## Centerline point (Y included) at an already-wrapped public arc.
static func _make_point(s: float) -> Vector3:
	var xz := _point_xz(s)
	var angle := _bank_rad_at_arc(s)
	var y := ROAD_BASE_Y + (WIDTH * 0.5) * absf(sin(angle)) + jump_lift(s)
	return Vector3(xz.x, y, xz.y)


## Plain XZ position at public arc `s` (no Y rule). `s` is wrapped by the caller.
static func _point_xz(s: float) -> Vector2:
	return _gen_point(fposmod(s + OFF, TARGET_PERIMETER))


## Unclamped signed bank angle (rad) at public arc `s`. Right turns are POSITIVE.
static func _bank_rad_at_arc(s: float) -> float:
	var arc := fposmod(s, TARGET_PERIMETER)
	var total := 0.0
	for r in BANK_REGIONS:
		var apex := corner_apex_arc(int(r["corner"]))
		var half: float = r["half_arc"]
		var lo := apex - half
		var hi := apex + half
		if hi <= lo or arc < lo or arc > hi:
			continue
		var u := (arc - lo) / (hi - lo)
		# Sine ease in to the apex, ease out after it (build #1's ramp idiom).
		var ease := _ease(u * 2.0) if u <= 0.5 else _ease((1.0 - u) * 2.0)
		total += deg_to_rad(float(r["deg"])) * ease
	return total


## Sine smoothstep on [0, 1] (clamped): 0 -> 0, 1 -> 1, ease in and out.
static func _ease(x: float) -> float:
	var v := clampf(x, 0.0, 1.0)
	return 0.5 - 0.5 * cos(PI * v)


## --- generator internals ----------------------------------------------------

## Builds the fillet table, the raw segment walk, the uniform rescale and the
## centring offset exactly once. Idempotent and deterministic.
static func _ensure_built() -> void:
	if _built:
		return
	var segs := _build_fillets()
	_raw = _build_raw(segs)
	_p_raw = 0.0
	for seg in _raw:
		_p_raw += _seg_len(seg)
	_scale = TARGET_PERIMETER / _p_raw

	var acc := Vector2.ZERO
	for i in TOTAL_POINTS:
		acc += _raw_point(float(i) * _p_raw / float(TOTAL_POINTS))
	_mean_raw = acc / float(TOTAL_POINTS)

	var n := VERTICES.size()
	_corner_from.resize(n)
	_corner_len.resize(n)
	var gen := 0.0
	for seg in _raw:
		var length := _seg_len(seg) * _scale
		if seg["k"] == "A":
			var vi: int = seg["i"]
			_corner_from[vi] = fposmod(gen - OFF, TARGET_PERIMETER)
			_corner_len[vi] = length
		gen += length

	_built = true


## Per-vertex tangent fillet: trims `T` off both adjacent edges, solves the
## fillet-circle centre from the two edge perpendiculars, and records the exact
## entry/exit points p1/p2 so consecutive raw segments stay continuous.
static func _build_fillets() -> Array[Dictionary]:
	var n := VERTICES.size()
	var edge_len := PackedFloat32Array()
	edge_len.resize(n)
	for i in n:
		edge_len[i] = (VERTICES[(i + 1) % n] - VERTICES[i]).length()

	var out: Array[Dictionary] = []
	for i in n:
		var a := VERTICES[(i - 1 + n) % n]
		var v := VERTICES[i]
		var b := VERTICES[(i + 1) % n]
		var u := (v - a).normalized()
		var w := (b - v).normalized()
		var d := acos(clampf(u.dot(w), -1.0, 1.0))
		var t := TFRAC[i] * minf(edge_len[(i - 1 + n) % n], edge_len[i])
		var p1 := v - u * t
		var p2 := v + w * t
		var n1 := Vector2(-u.y, u.x)
		var n2 := Vector2(-w.y, w.x)
		var diff := p2 - p1
		var det := n1.x * (-n2.y) - (-n2.x) * n1.y
		var aa := (diff.x * (-n2.y) - (-n2.x) * diff.y) / det
		var ctr := p1 + n1 * aa
		var r := (ctr - p1).length()
		var a1 := atan2(p1.y - ctr.y, p1.x - ctr.x)
		var a2 := atan2(p2.y - ctr.y, p2.x - ctr.x)
		var da := fposmod(a2 - a1 + PI, TAU) - PI
		out.append({
			"i": i, "d": d, "T": t, "R": r, "p1": p1, "p2": p2,
			"ctr": ctr, "a1": a1, "a2": a1 + da, "da": da,
		})
	return out


## Interleaves the fillet entries and exits with straight segments: for each
## vertex i, a straight from the previous exit to this entry, then the arc.
static func _build_raw(segs: Array[Dictionary]) -> Array[Dictionary]:
	var n := segs.size()
	var out: Array[Dictionary] = []
	for i in n:
		var prev_p2: Vector2 = segs[(i - 1 + n) % n]["p2"]
		var s: Dictionary = segs[i]
		out.append({"k": "S", "a": prev_p2, "b": s["p1"]})
		out.append({"k": "A", "i": i, "ctr": s["ctr"], "a1": s["a1"],
			"a2": s["a2"], "R": s["R"]})
	return out


## Arc length of a raw segment (straight or fillet arc).
static func _seg_len(seg: Dictionary) -> float:
	if seg["k"] == "S":
		var a: Vector2 = seg["a"]
		var b: Vector2 = seg["b"]
		return (b - a).length()
	return float(seg["R"]) * absf(float(seg["a2"]) - float(seg["a1"]))


## Raw (unscaled) XZ point at raw arc `arc`, wrapping around the walk.
static func _raw_point(arc: float) -> Vector2:
	var s := fposmod(arc, _p_raw)
	for seg in _raw:
		var l := _seg_len(seg)
		if s <= l:
			var u := 0.0 if l == 0.0 else s / l
			if seg["k"] == "S":
				var a: Vector2 = seg["a"]
				var b: Vector2 = seg["b"]
				return a + (b - a) * u
			var ctr: Vector2 = seg["ctr"]
			var ang := float(seg["a1"]) + (float(seg["a2"]) - float(seg["a1"])) * u
			return ctr + Vector2(cos(ang), sin(ang)) * float(seg["R"])
		s -= l
	var last: Dictionary = _raw[_raw.size() - 1]
	if last["k"] == "S":
		var b2: Vector2 = last["b"]
		return b2
	var ctr2: Vector2 = last["ctr"]
	return ctr2 + Vector2(cos(float(last["a2"])), sin(float(last["a2"]))) * float(last["R"])


## Public generation-arc point: raw point at `g / scale`, re-centred on the raw
## chain mean and uniformly scaled to the target perimeter. (Public arc s is
## `gen_point(s + OFF)` — see _point_xz.)
static func _gen_point(g: float) -> Vector2:
	var p := _raw_point(fposmod(g, TARGET_PERIMETER) / _scale)
	return (p - _mean_raw) * _scale
