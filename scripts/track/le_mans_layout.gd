class_name LeMansLayout
extends RefCounted
## Pure-static geometry source of truth for the Le Mans No-Chicane circuit
## (docs/plans/track_le_mans_no_chicane.md, §3). Mirrors the BarcelonaRxLayout
## API shape: build once, cache, expose arc-space queries.
##
## Pipeline (plan §3.5): 51 OSM-trace anchors (§3.2, verbatim) -> straight-line
## subdivision so no leg exceeds ~250 m of chainage (§3.3, 85 anchors) -> closed
## centripetal (alpha 0.5) Catmull-Rom, dense-sampled at ~0.5 m -> Mulsanne kink
## sine (RECONSTRUCTED, §3.5) displaced along the local perpendicular ->
## uniform rescale so the perimeter is exactly TARGET_PERIMETER -> resample
## TOTAL_POINTS uniform-arc points -> Y per the bank profile (§3.3).
##
## HONESTY NOTE (plan §3.9, keep in the shipped docstring): this geometry is an
## OpenStreetMap centerline trace scaled to the published 13.626 km - it is
## APPROXIMATE. ±10-30 m lateral on straights, worse inside the corner complexes;
## the S/F line is ±100 m; the Dunlop bridge chainage is ±150 m; every chicane
## removal is a geometric chord, NOT the historic alignment; the Mulsanne kink is
## reconstructed from secondary sources. Elevation (2026-10-22) is REAL survey
## data, not a guess: NASA SRTM GL1 30 m (public domain) sampled every <= 50 m
## along the same OSM trace (`LeMansElevationData`, baked by
## tools/le_mans_fetch_elevation.py, cross-checked against EU-DEM v1.1), keyed by
## chainage and smoothed (ELEVATION_SMOOTH_HALF_M, 3 box passes) because SRTM is
## a surface model and the trace is +-10-30 m laterally. World Y is relative to
## the smoothed S/F height (`elevation_datum_asl()`), so the grid/line keep
## their v1 heights. © OpenStreetMap contributors, ODbL.


## Published lap length (m). The whole layout is rescaled to this exactly.
const TARGET_PERIMETER := 13626.0

## Carriageway width used by RoadDef/mesh/dressing (m).
const WIDTH_M := 12.0

## Uniform-arc centerline resolution. spacing() = 13626 / 4800 = 2.83875 m.
const TOTAL_POINTS := 4800

## Checkpoints every CP_STRIDE m of chainage -> CHECKPOINT_COUNT gates, with the
## start/finish line LAST in travel order at centerline index 0 (§3.6).
const CP_STRIDE := 200
const CHECKPOINT_COUNT := 24

## Grid slot: chainage 13,296.7 m (point 4684), 329 m behind the line, on the
## front straight and NOT on any checkpoint (frame-based counting, §3.6).
const GRID_INDEX := 4684

## Road surface base height and the flat v1 ground plane height (m).
const ROAD_BASE_Y := 0.15
const PLAIN_Y := -0.25

## Elevation smoothing: half-window (m of arc) of each of ELEVATION_SMOOTH_PASSES
## circular box filters over the per-point SRTM profile (3 passes ~ a Gaussian of
## sigma ~60 m). 60 m keeps relief ~37 m and the Dunlop climb, caps the grade at
## ~4.7 % and holds every Hunaudieres crest above R ~2,300 m (0.4 g of unload at
## 350 km/h -- no ski-jumps).
const ELEVATION_SMOOTH_HALF_M := 60.0
const ELEVATION_SMOOTH_PASSES := 3

## Peak bank angle for every bermed corner (deg). Flat straights, sine-eased
## banks in the big corners; sign convention = barcelona (positive = right turn,
## i.e. cross.y = -sin(bank) lowers the inside edge).
const BANK_MAX_DEG := 3.0

## Mulsanne kink (plan §3.5): absent from OSM, reconstructed here and NOT baked
## into the anchor table. Lateral offset A*sin(2*pi*(ch - s0)/L) over
## [s0 - 150, s0 + 150]; zero at both window ends so the sine joins the straight
## tangent-continuously. Tunables exposed per plan.
const MULSANNE_KINK_CHAINAGE := 4630.0
const MULSANNE_KINK_LATERAL_M := 30.0
const MULSANNE_KINK_WAVELENGTH_M := 300.0
const MULSANNE_KINK_RECONSTRUCTED := true
const MULSANNE_KINK_HALF_WINDOW_M := MULSANNE_KINK_WAVELENGTH_M * 0.5

## Dense Catmull-Rom sampling step (m) before uniform resampling.
const DENSE_STEP_M := 0.5

## §3.3: subdivide any leg whose chainage span exceeds this (m) -> 85 anchors.
const MAX_ANCHOR_SPACING_M := 250.0

## Landmark chainages (§3.4): anchor within ±30 m of each.
const LANDMARK_DUNLOP_BRIDGE := 869.0
const LANDMARK_TERTRE_ROUGE := 1885.0
const LANDMARK_MULSANNE_CORNER := 7508.0
const LANDMARK_INDY := 9653.0
const LANDMARK_ARNAGE := 9987.0
const LANDMARK_FORD := 13094.0

## The 51 control points (§3.2, APPROXIMATE, world XZ, chainage m from S/F).
## Verbatim from the plan - do not "improve" without re-running A2/A3/A4.
const ANCHORS: Array[Vector2] = [
	Vector2(-630.0, -844.0), Vector2(-624.0, -1016.0), Vector2(-582.0, -1223.0),
	Vector2(-528.0, -1331.0), Vector2(-275.0, -1569.0), Vector2(-260.0, -1579.0),
	Vector2(-214.0, -1612.0), Vector2(-121.0, -1718.0), Vector2(-60.0, -1742.0),
	Vector2(87.0, -1758.0), Vector2(116.0, -1791.0), Vector2(131.0, -1873.0),
	Vector2(156.0, -1909.0), Vector2(254.0, -1977.0), Vector2(413.0, -2034.0),
	Vector2(540.0, -1963.0), Vector2(621.0, -1893.0), Vector2(856.0, -1523.0),
	Vector2(2034.0, 2095.0), Vector2(2111.0, 3283.0), Vector2(2104.0, 3364.0),
	Vector2(2084.0, 3390.0), Vector2(1346.0, 3196.0), Vector2(850.0, 2947.0),
	Vector2(370.0, 2589.0), Vector2(336.0, 2543.0), Vector2(294.0, 2411.0),
	Vector2(272.0, 2391.0), Vector2(239.0, 2393.0), Vector2(-14.0, 2490.0),
	Vector2(-35.0, 2480.0), Vector2(-178.0, 1907.0), Vector2(-375.0, 1508.0),
	Vector2(-481.0, 1353.0), Vector2(-523.0, 1268.0), Vector2(-525.0, 1210.0),
	Vector2(-512.0, 1170.0), Vector2(-403.0, 1040.0), Vector2(-382.0, 974.0),
	Vector2(-401.0, 819.0), Vector2(-503.0, 710.0), Vector2(-526.0, 635.0),
	Vector2(-510.0, 559.0), Vector2(-429.0, 475.0), Vector2(-407.0, 423.0),
	Vector2(-434.0, 205.0), Vector2(-422.0, 84.0), Vector2(-539.0, -353.0),
	Vector2(-586.0, -393.0), Vector2(-607.0, -486.0), Vector2(-642.0, -514.0),
]

## Chainage (m) of each anchor above; the closing leg rp50 -> rp0 spans
## 13,296 -> 13,626 (the 330 m front straight) and is added by the subdivision.
const ANCHOR_CHAINAGES: Array[float] = [
	0.0, 172.0, 384.0, 504.0, 852.0, 869.0, 927.0, 1067.0, 1133.0, 1281.0,
	1324.0, 1408.0, 1452.0, 1571.0, 1740.0, 1885.0, 1992.0, 2430.0, 6236.0,
	7426.0, 7508.0, 7541.0, 8303.0, 8859.0, 9457.0, 9514.0, 9653.0, 9683.0,
	9716.0, 9987.0, 10010.0, 10601.0, 11046.0, 11234.0, 11329.0, 11387.0,
	11428.0, 11598.0, 11668.0, 11823.0, 11972.0, 12051.0, 12129.0, 12245.0,
	12301.0, 12521.0, 12642.0, 13094.0, 13157.0, 13252.0, 13296.0,
]

## Bermed corners: sine-eased +/-half around `chainage`, peak BANK_MAX_DEG*deg.
## Sign is derived at build time from the built curvature at each apex so the
## bank always tilts INTO the turn (positive = right turn, barcelona space).
const BANK_REGIONS: Array[Dictionary] = [
	{"name": "dunlop", "chainage": 350.0, "half": 190.0, "deg": 1.0},
	{"name": "tertre_rouge", "chainage": 1717.0, "half": 190.0, "deg": 1.0},
	{"name": "mulsanne", "chainage": 7508.0, "half": 90.0, "deg": 1.0},
	{"name": "indianapolis", "chainage": 9686.0, "half": 40.0, "deg": 1.0},
	{"name": "arnage", "chainage": 9999.0, "half": 60.0, "deg": 1.0},
	{"name": "ford_chicanes", "chainage": 13110.0, "half": 70.0, "deg": 1.0},
]


## --- static build cache (deterministic, no engine state) ---------------------

static var _built := false
## Final 4,800 centerline points (XZ uniform arc, Y per bank).
static var _centerline: Array[Vector3] = []
## Chainage label of each final point (monotone 0..~13,623; the wrap segment
## carries 13,623 -> 13,626). This is the arc<->chainage map A3/A4 query.
static var _labels := PackedFloat64Array()
## Signed bank (rad) per final point.
static var _bank := PackedFloat32Array()
## The real build's uniform-rescale factor (reused by the no-kink hook).
static var _real_scale := -1.0
## Apex arc of each BANK_REGION (computed from the label map at build).
static var _bank_apex := PackedFloat32Array()
## Sign of each BANK_REGION's built curvature (+1/-1).
static var _bank_sign := PackedFloat32Array()
## Smoothed elevation per final point, metres ABOVE SEA LEVEL.
static var _elev_asl := PackedFloat32Array()
## Smoothed elevation at the S/F line (m ASL): world Y 0-offset.
static var _datum_asl := 0.0


## Uniform arc-length spacing between two consecutive centerline points.
static func spacing() -> float:
	return TARGET_PERIMETER / float(TOTAL_POINTS)


## Total centerline length (m). Exactly TARGET_PERIMETER by construction.
static func perimeter() -> float:
	return TARGET_PERIMETER


## Arc length (m) from the start/finish line (point 0) to point `index`.
static func arc_of_index(index: int) -> float:
	return float(index) * spacing()


## Grid arc (m): 4684 * 2.83875 = 13,296.705 - 329.295 m behind the line.
static func grid_arc() -> float:
	return arc_of_index(GRID_INDEX)


## Arc length (m) of the start/finish line: 0 by definition (rp0).
static func start_line_arc() -> float:
	return 0.0


## Centerline indices carrying a checkpoint, in travel order:
## [200, 400, ..., 4600, 0] - the line LAST (frame-based lap counting, §3.6).
static func checkpoint_indices() -> PackedInt32Array:
	var indices := PackedInt32Array()
	for i in CHECKPOINT_COUNT - 1:
		indices.append((i + 1) * CP_STRIDE)
	indices.append(0)
	return indices


## Lateral kink offset (m) at chainage `ch`: the RECONSTRUCTED Mulsanne sine,
## exactly 0 at both window ends so the straight is joined tangentially.
static func kink_lateral_at_chainage(ch: float) -> float:
	var lo := MULSANNE_KINK_CHAINAGE - MULSANNE_KINK_HALF_WINDOW_M
	var hi := MULSANNE_KINK_CHAINAGE + MULSANNE_KINK_HALF_WINDOW_M
	if ch <= lo or ch >= hi:
		return 0.0
	var wave := TAU * (ch - MULSANNE_KINK_CHAINAGE) / MULSANNE_KINK_WAVELENGTH_M
	return MULSANNE_KINK_LATERAL_M * sin(wave)


## Centerline points (Y included) at every uniform arc step. Deterministic: the
## same build twice is element-wise identical (the determinism test relies on it).
static func build_centerline() -> Array[Vector3]:
	_ensure_built()
	var points: Array[Vector3] = []
	points.assign(_centerline)
	return points


## Centerline WITHOUT the kink, rescaled with the SAME scale factor as the real
## build so the two curves differ only by the kink displacement field. Test/
## diagnostic hook for A2's kink-deviation assertion; do not ship geometry
## from this.
static func build_centerline_no_kink() -> Array[Vector3]:
	_ensure_built()
	return _resample_uniform(_build_dense(0.0, _real_scale))


## Signed bank angle (radians) per centerline point, in TrackBuilder._frame's
## sign space (POSITIVE = right turn). Zero outside every BANK_REGION.
static func build_bank_profile() -> PackedFloat32Array:
	_ensure_built()
	return _bank.duplicate()


## Signed bank angle (rad) at public arc `s`, wrapping around the loop.
static func bank_rad_at_arc(s: float) -> float:
	_ensure_built()
	var arc := fposmod(s, TARGET_PERIMETER)
	var total := 0.0
	for r in BANK_REGIONS:
		var apex: float = _bank_apex[_region_index(String(r["name"]))]
		var half: float = r["half"]
		var d := arc - apex
		if absf(d) > half:
			continue
		var peak := deg_to_rad(BANK_MAX_DEG) * float(r["deg"]) * _bank_sign[_region_index(String(r["name"]))]
		total += peak * sin(PI * (0.5 + d / (2.0 * half)))
	return total


## Smoothed real elevation per centerline point, world-relative (m above the
## S/F datum): what every point's Y carries on top of ROAD_BASE_Y + bank lift.
static func build_elevation_profile() -> PackedFloat32Array:
	_ensure_built()
	var out := PackedFloat32Array()
	out.resize(TOTAL_POINTS)
	for i in TOTAL_POINTS:
		out[i] = _elev_asl[i] - _datum_asl
	return out


## Smoothed S/F elevation (m ASL) -- the world-Y datum.
static func elevation_datum_asl() -> float:
	_ensure_built()
	return _datum_asl


## World-relative elevation (m) at arc `s`, linear between points, wrapping.
static func elevation_at_arc(s: float) -> float:
	return elevation_asl_at_arc(s) - _datum_asl


## Smoothed elevation (m ASL) at arc `s`.
static func elevation_asl_at_arc(s: float) -> float:
	_ensure_built()
	var idx := fposmod(s, TARGET_PERIMETER) / spacing()
	var i0 := int(idx) % TOTAL_POINTS
	var i1 := (i0 + 1) % TOTAL_POINTS
	return lerpf(_elev_asl[i0], _elev_asl[i1], idx - floorf(idx))


## Height of the ground beside the road at arc `s` (the v1 PLAIN_Y relation,
## 0.40 m under the road edge, carried up and down the real profile).
static func ground_y_at_arc(s: float) -> float:
	return PLAIN_Y + elevation_at_arc(s)


## Centerline point (Y included) at arc `s`, wrapping around the loop.
static func point_at_arc(s: float) -> Vector3:
	_ensure_built()
	var arc := fposmod(s, TARGET_PERIMETER)
	var idx := arc / spacing()
	var i0 := int(idx) % TOTAL_POINTS
	var i1 := (i0 + 1) % TOTAL_POINTS
	var frac := idx - floorf(idx)
	var xz := _centerline[i0].lerp(_centerline[i1], frac)
	return Vector3(xz.x, _make_y(arc), xz.z)


## Road frame at arc `s`: the same center/forward/right/cross the mesh is built
## from (barcelona convention), so dressing placed at `center + cross * offset`
## sits ON the banked cross-section. `cross.y = -sin(bank)`.
static func frame_at_arc(s: float) -> Dictionary:
	var delta := 0.25
	var a := point_at_arc(s - delta)
	var b := point_at_arc(s + delta)
	var center := point_at_arc(s)
	var forward := (b - a).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var angle := bank_rad_at_arc(s)
	var cross := right * cos(angle) - Vector3.UP * sin(angle)
	return {
		"center": center,
		"forward": forward,
		"right": right,
		"cross": cross,
		"bank": angle,
	}


## Final arc (m) at which the built curve carries chainage `ch`. The chainage
## label of every final point is tracked through subdivision/CR/kink/rescale,
## so this map is the built curve's own arc<->chainage correspondence (A3/A4).
## Wraps: chainages past the last labeled point interpolate to (13626 -> 13626).
static func arc_at_chainage(ch: float) -> float:
	_ensure_built()
	var c := fposmod(ch, TARGET_PERIMETER)
	var n := _labels.size()
	if c >= _labels[n - 1]:
		var last_arc := arc_of_index(n - 1)
		var tail := TARGET_PERIMETER - _labels[n - 1]
		if tail <= 0.0:
			return last_arc
		return last_arc + (c - _labels[n - 1]) / tail * (TARGET_PERIMETER - last_arc)
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if _labels[mid] <= c:
			lo = mid
		else:
			hi = mid
	var span := _labels[hi] - _labels[lo]
	if span <= 0.0:
		return arc_of_index(lo)
	return arc_of_index(lo) + (c - _labels[lo]) / span * spacing()


## Landmark name -> final arc (m) for every §3.4 landmark (A3's table).
static func landmark_arcs() -> Dictionary:
	return {
		"dunlop_bridge": arc_at_chainage(LANDMARK_DUNLOP_BRIDGE),
		"tertre_rouge": arc_at_chainage(LANDMARK_TERTRE_ROUGE),
		"mulsanne_corner": arc_at_chainage(LANDMARK_MULSANNE_CORNER),
		"indianapolis": arc_at_chainage(LANDMARK_INDY),
		"arnage": arc_at_chainage(LANDMARK_ARNAGE),
		"ford_chicane": arc_at_chainage(LANDMARK_FORD),
	}


## Chainages (m) of the sharp-corner apexes: heading change between consecutive
## ANCHOR chords above `min_turn_deg`, apex reported at the middle anchor's
## chainage (plan §3.4/v9 cross-check: 7 anchors turn >40°). A per-SAMPLE turn at
## the 2.84 m centerline spacing cannot reach 40° for any driveable radius
## (R ≈ 4 m would be needed), so the anchor polyline is the correct metric.
static func sharp_corner_chainages(min_turn_deg: float = 40.0) -> PackedFloat64Array:
	_ensure_built()
	var anchors := _subdivide_anchors()
	var m := anchors.size()
	var out := PackedFloat64Array()
	for i in m:
		var c0: Vector2 = anchors[i]["pos"]
		var c1: Vector2 = anchors[(i + 1) % m]["pos"]
		var c2: Vector2 = anchors[(i + 2) % m]["pos"]
		var t1 := (c1 - c0).normalized()
		var t2 := (c2 - c1).normalized()
		if rad_to_deg(acos(clampf(t1.dot(t2), -1.0, 1.0))) > min_turn_deg:
			out.append(fposmod(float(anchors[(i + 1) % m]["chainage"]), TARGET_PERIMETER))
	out.sort()
	return out


## Off-tree probe in the TrackLayoutSource convention: the generated road
## points, ready for RoadNetwork.add_road(). The scene script calls this.
static func generate_road_points() -> Array[Vector3]:
	return build_centerline()


# --- build internals ----------------------------------------------------------


static func _ensure_built() -> void:
	if _built:
		return
	var dense := _build_dense(MULSANNE_KINK_LATERAL_M, -1.0)
	_real_scale = float(dense["scale"])
	_centerline = _resample_uniform(dense)
	_labels = PackedFloat64Array()
	for i in TOTAL_POINTS:
		_labels.append(_label_at(dense, float(i) * spacing() / _real_scale))
	_built = true # before _build_bank: it queries arc_at_chainage (re-entrant)
	_build_bank()
	_build_elevation()
	for i in TOTAL_POINTS:
		_centerline[i].y = _make_y(arc_of_index(i))


## Dense-sampled curve (XZ + chainage labels + cumulative arc) at ~DENSE_STEP_M:
## subdivided anchors -> closed centripetal Catmull-Rom -> kink displacement.
## `kink_amp` scales the RECONSTRUCTED sine (0 = base curve); `forced_scale` > 0
## reuses the real build's scale factor so base/built curves stay comparable.
static func _build_dense(kink_amp: float, forced_scale: float) -> Dictionary:
	var anchors := _subdivide_anchors()
	var m := anchors.size()
	var dx := PackedVector2Array()
	var dl := PackedFloat64Array()
	# Closed centripetal (alpha 0.5) Catmull-Rom, Barry-Goldman pyramidal form.
	for i in m:
		var p0: Vector2 = anchors[(i - 1 + m) % m]["pos"]
		var p1: Vector2 = anchors[i]["pos"]
		var p2: Vector2 = anchors[(i + 1) % m]["pos"]
		var p3: Vector2 = anchors[(i + 2) % m]["pos"]
		var l1: float = anchors[i]["chainage"]
		var l2: float = anchors[(i + 1) % m]["chainage"]
		if i == m - 1:
			l2 = TARGET_PERIMETER # closing leg labels run 13,461 -> 13,626, not -> 0
		var d1 := maxf(p0.distance_to(p1), 0.000001) ** 0.5
		var d2 := maxf(p1.distance_to(p2), 0.000001) ** 0.5
		var d3 := maxf(p2.distance_to(p3), 0.000001) ** 0.5
		# Estimate the segment length coarsely, then sample at DENSE_STEP_M.
		var est := 0.0
		var prev := p1
		for k in 24:
			var pu := d1 + d2 * float(k + 1) / 24.0
			var pp := _cr_point(p0, p1, p2, p3, d1, d2, d3, pu)
			est += prev.distance_to(pp)
			prev = pp
		var steps := clampi(int(ceil(est / DENSE_STEP_M)), 8, 40000)
		for k in steps:
			var u := d1 + d2 * float(k) / float(steps)
			var frac := (u - d1) / d2
			dx.append(_cr_point(p0, p1, p2, p3, d1, d2, d3, u))
			dl.append(lerpf(l1, l2, frac))
	# Kink displacement along the local perpendicular, keyed on the base
	# chainage label (§3.5: applied before resampling). Tangents MUST come from a
	# pristine snapshot: the 30 m displacement dwarfs the 0.5 m base step, so
	# reading already-displaced neighbours makes the tangent flip and zig-zags
	# the curve (measured: 13.7 km -> 29.6 km before this fix).
	if kink_amp != 0.0:
		var n := dx.size()
		var base := dx.duplicate()
		for i in n:
			var lat := kink_amp / MULSANNE_KINK_LATERAL_M * kink_lateral_at_chainage(dl[i])
			if lat == 0.0:
				continue
			var prv := base[(i - 1 + n) % n]
			var nxt := base[(i + 1) % n]
			var tangent := (nxt - prv).normalized()
			dx[i] = dx[i] + Vector2(-tangent.y, tangent.x) * lat
	# Cumulative arc of the (displaced) dense polyline.
	var arc := PackedFloat64Array()
	var total := 0.0
	arc.append(0.0)
	for i in range(1, dx.size()):
		total += dx[i - 1].distance_to(dx[i])
		arc.append(total)
	total += dx[dx.size() - 1].distance_to(dx[0])
	var scale := TARGET_PERIMETER / total
	if forced_scale > 0.0:
		scale = forced_scale
	var centroid := Vector2.ZERO
	for p in dx:
		centroid += p
	centroid /= float(dx.size())
	return {
		"pos": dx, "label": dl, "arc": arc, "total": total,
		"scale": scale, "centroid": centroid,
	}


## Resample a dense curve at TOTAL_POINTS uniform arcs (centered, scaled).
static func _resample_uniform(dense: Dictionary) -> Array[Vector3]:
	var dx: PackedVector2Array = dense["pos"]
	var arc: PackedFloat64Array = dense["arc"]
	var scale: float = dense["scale"]
	var centroid: Vector2 = dense["centroid"]
	var m := dx.size()
	var total: float = dense["total"]
	var out: Array[Vector3] = []
	var cursor := 0
	for i in TOTAL_POINTS:
		# `arc` is raw (unscaled) length; divide the target so a forced scale
		# (no-kink hook) still covers the WHOLE curve, not a truncated prefix.
		var target := float(i) * spacing() / scale
		while cursor + 1 < m and arc[cursor + 1] <= target:
			cursor += 1
		var seg := arc[(cursor + 1) % m] - arc[cursor]
		if seg <= 0.0:
			seg += total
		var t := (target - arc[cursor]) / seg
		if t < 0.0:
			t = 0.0
		var a := dx[cursor]
		var b := dx[(cursor + 1) % m]
		var p := centroid + (a.lerp(b, t) - centroid) * scale
		out.append(Vector3(p.x, 0.0, p.y))
	return out


## Chainage label at arc `s` of a dense curve (arc-linear per segment).
static func _label_at(dense: Dictionary, s: float) -> float:
	var arc: PackedFloat64Array = dense["arc"]
	var dl: PackedFloat64Array = dense["label"]
	var m := arc.size()
	var total: float = dense["total"]
	var target := fposmod(s, total)
	# Wrap tail: past the last dense sample, interpolate to the closing leg.
	if target >= arc[m - 1]:
		var span2 := total - arc[m - 1]
		if span2 <= 0.0:
			return dl[m - 1]
		return lerpf(dl[m - 1], TARGET_PERIMETER, (target - arc[m - 1]) / span2)
	var lo := 0
	var hi := m - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if arc[mid] <= target:
			lo = mid
		else:
			hi = mid
	var seg := arc[hi] - arc[lo]
	if seg <= 0.0:
		return dl[lo]
	return lerpf(dl[lo], dl[hi], clampf((target - arc[lo]) / seg, 0.0, 1.0))


## Straight-line subdivision so no leg exceeds MAX_ANCHOR_SPACING_M of
## chainage (§3.3): 51 -> 85 anchors, straight-line interpolated (the real
## Mulsanne straight IS straight). Includes the closing rp50 -> rp0 leg.
static func _subdivide_anchors() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var m := ANCHORS.size()
	for i in m:
		var a := ANCHORS[i]
		var b := ANCHORS[(i + 1) % m]
		var ca := ANCHOR_CHAINAGES[i]
		var cb := ANCHOR_CHAINAGES[(i + 1) % m]
		if i == m - 1:
			cb = TARGET_PERIMETER # closing front-straight leg 13,296 -> 13,626
		var span := cb - ca
		var parts := maxi(1, int(ceil(span / MAX_ANCHOR_SPACING_M)))
		for k in parts:
			var t := float(k) / float(parts)
			out.append({"pos": a.lerp(b, t), "chainage": lerpf(ca, cb, t)})
	return out


## Barry-Goldman evaluation of the closed centripetal Catmull-Rom through
## p0..p3 at knot position u in [d1, d1+d2].
static func _cr_point(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		d1: float, d2: float, d3: float, u: float) -> Vector2:
	var a1 := ((d1 - u) * p0 + u * p1) / d1
	var a2 := ((d1 + d2 - u) * p1 + (u - d1) * p2) / d2
	var a3 := ((d1 + d2 + d3 - u) * p2 + (u - d1 - d2) * p3) / d3
	var b1 := ((d1 + d2 - u) * a1 + u * a2) / (d1 + d2)
	var b2 := ((d1 + d2 + d3 - u) * a2 + (u - d1) * a3) / (d2 + d3)
	return ((d1 + d2 - u) * b1 + (u - d1) * b2) / d2


## Bank per final point + apex arcs/signs per region. Sign derived from the
## built curvature: cross(t1, t2).y < 0 is a right turn, and the barcelona
## frame banks positively (inside edge down) for right turns, so the region
## sign is -sign(cross.y).
static func _build_bank() -> void:
	_bank = PackedFloat32Array()
	_bank.resize(TOTAL_POINTS)
	_bank_apex = PackedFloat32Array()
	_bank_sign = PackedFloat32Array()
	var max_bank := deg_to_rad(BANK_MAX_DEG)
	for r in BANK_REGIONS:
		var apex := arc_at_chainage(float(r["chainage"]))
		var half: float = r["half"]
		var ia := clampi(int(roundf(apex / spacing())) % TOTAL_POINTS, 0, TOTAL_POINTS - 1)
		var prev := _centerline[(ia - 1 + TOTAL_POINTS) % TOTAL_POINTS]
		var nxt := _centerline[(ia + 1) % TOTAL_POINTS]
		var t1 := Vector3(_centerline[ia].x - prev.x, 0.0, _centerline[ia].z - prev.z)
		var t2 := Vector3(nxt.x - _centerline[ia].x, 0.0, nxt.z - _centerline[ia].z)
		var cross_y := t1.z * t2.x - t1.x * t2.z
		var region_sign := 1.0 if cross_y <= 0.0 else -1.0
		_bank_apex.append(apex)
		_bank_sign.append(region_sign)
		var peak := max_bank * float(r["deg"]) * region_sign
		for i in TOTAL_POINTS:
			var d := arc_of_index(i) - apex
			if absf(d) > half:
				continue
			_bank[i] += peak * sin(PI * (0.5 + d / (2.0 * half)))


## Road surface Y at public arc `s`: the barcelona inner-edge invariant - the
## inner edge rides at ROAD_BASE_Y and the centerline sits (WIDTH/2)*|sin(bank)|
## above it, so the centerline height follows the angle exactly (not the angle
## in radians). The mesh and dressing read the cross-section through frame_at_arc.
static func _make_y(s: float) -> float:
	return ROAD_BASE_Y + elevation_at_arc(s) + (WIDTH_M * 0.5) * absf(sin(bank_rad_at_arc(s)))


## Per-point smoothed elevation (m ASL): the SRTM lap profile is keyed by the
## OSM chainage, so each final point reads it at its own chainage LABEL (the
## same arc<->chainage map the landmarks use), then ELEVATION_SMOOTH_PASSES
## circular box filters of +-ELEVATION_SMOOTH_HALF_M remove DEM/trace noise.
## Deterministic: constant table in, pure arithmetic out.
static func _build_elevation() -> void:
	var chs: Array[float] = LeMansElevationData.PROFILE_CHAINAGES
	var hs: Array[float] = LeMansElevationData.PROFILE_M
	var m := chs.size()
	var raw := PackedFloat32Array()
	raw.resize(TOTAL_POINTS)
	var j := 0
	for i in TOTAL_POINTS:
		var c := fposmod(_labels[i], TARGET_PERIMETER)
		while j + 1 < m and chs[j + 1] <= c:
			j += 1
		while j > 0 and chs[j] > c:
			j -= 1
		var c0 := chs[j]
		var c1 := chs[j + 1] if j + 1 < m else TARGET_PERIMETER
		var h1 := hs[j + 1] if j + 1 < m else hs[0]
		var t := clampf((c - c0) / maxf(c1 - c0, 0.001), 0.0, 1.0)
		raw[i] = lerpf(hs[j], h1, t)
	var half := maxi(int(roundf(ELEVATION_SMOOTH_HALF_M / spacing())), 1)
	for _pass in ELEVATION_SMOOTH_PASSES:
		var out := PackedFloat32Array()
		out.resize(TOTAL_POINTS)
		var sum := 0.0
		for k in range(-half, half + 1):
			sum += raw[(k + TOTAL_POINTS) % TOTAL_POINTS]
		var count := float(half * 2 + 1)
		for i in TOTAL_POINTS:
			out[i] = sum / count
			sum += raw[(i + half + 1) % TOTAL_POINTS] - raw[(i - half + TOTAL_POINTS) % TOTAL_POINTS]
		raw = out
	_elev_asl = raw
	_datum_asl = raw[0]


## Bank-region lookup by name (small const table; clarity over speed).
static func _region_index(region_name: String) -> int:
	for i in BANK_REGIONS.size():
		if String(BANK_REGIONS[i]["name"]) == region_name:
			return i
	return 0
