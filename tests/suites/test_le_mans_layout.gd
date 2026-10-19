# tests/suites/test_le_mans_layout.gd
extends GdUnitTestSuite

## P0 gate for Le Mans No-Chicane geometry
## (scripts/track/le_mans_layout.gd — docs/plans/track_le_mans_no_chicane.md P0,
## acceptance A2/A3/A4 plus the layout-level A5 constants).
##
## PURE MATH: no scene, no engine state, no wall clock. The layout is the single
## source of truth every later phase reads (mesh, checkpoints, ground, dressing),
## so every assertion below pins a plan constant or invariant:
##   * the §3.5 contract table (13,626 m / 12 m / 4,800 pts / 24 gates / grid);
##   * A2: closed simple loop, perimeter 13,626, no reversals/duplicates/spikes,
##     clockwise winding, sane footprint;
##   * A2 kink: the RECONSTRUCTED Mulsanne sine is zero at the window ends,
##     peaks at ±30 m, and displaces the BUILT curve by ~30 m at the apex while
##     re-joining the straight tangentially;
##   * A3: the six §3.4 landmarks land within ±30 m of their chainage;
##   * A4: the six named-window lengths (incl. the wrapped pit straight);
##   * bank: magnitude <= 3 deg, sign tilts INTO each corner, zero off-region;
##   * checkpoints/grid: 24 gates, line LAST, grid 329.295 m behind the line and
##     off every gate -> lap 1 = 13,955.295 m, laps 2+ = 13,626 m;
##   * Y rule, frame contract, determinism.

const POSITION_EPS := 0.001
const PERIMETER_TOL := 2.0  # A2: chain perimeter within [13624, 13628]

## §3.4 landmark chainages, in the order A3 lists them.
const LANDMARKS := {
	"dunlop_bridge": 869.0,
	"tertre_rouge": 1885.0,
	"mulsanne_corner": 7508.0,
	"indianapolis": 9653.0,
	"arnage": 9987.0,
	"ford_chicane": 13094.0,
}

## A4: {name, from, to, expected m, tolerance m, wraps}.
const NAMED_WINDOWS := [
	["mulsanne", 1910.0, 7357.0, 5447.0, 100.0, false],
	["mulsanne_to_indy", 7541.0, 9649.0, 2108.0, 80.0, false],
	["indy_to_arnage", 9649.0, 9984.0, 335.0, 40.0, false],
	["arnage_to_ford", 9984.0, 13044.0, 3060.0, 100.0, false],
	["dunlop_to_tertre", 546.0, 1523.0, 977.0, 100.0, false],
	["raccordement_to_lachapelle", 13297.0, 1007.0, 1336.0, 100.0, true],
]


# --- helpers -----------------------------------------------------------------


func _points() -> Array[Vector3]:
	return LeMansLayout.build_centerline()


## Signed shoelace area in the (x, z) plane. With x right and z UP on the plot,
## positive = counter-clockwise; the plan's v9 map (z DOWN, the minimap
## convention) calls the same orientation "clockwise".
func _signed_area(pts: Array[Vector3]) -> float:
	var area := 0.0
	var n := pts.size()
	for i in n:
		var p := pts[i]
		var q := pts[(i + 1) % n]
		area += p.x * q.z - q.x * p.z
	return area * 0.5


func _index_dist(a: int, b: int, n: int) -> int:
	var d := absi(a - b)
	return mini(d, n - d)


func _orient(a: Vector3, b: Vector3, c: Vector3) -> float:
	return (b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x)


func _segments_intersect(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> bool:
	var o1 := _orient(a, b, c)
	var o2 := _orient(a, b, d)
	var o3 := _orient(c, d, a)
	var o4 := _orient(c, d, b)
	var ab := (o1 > 0.0 and o2 < 0.0) or (o1 < 0.0 and o2 > 0.0)
	var cd := (o3 > 0.0 and o4 < 0.0) or (o3 < 0.0 and o4 > 0.0)
	return ab and cd


## A2 self-crossing scan: spatial hash over ~80 m cells, non-adjacent segments.
func _has_self_intersection(pts: Array[Vector3]) -> bool:
	var cell := 80.0
	var buckets := {}
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var x0 := int(floor(minf(a.x, b.x) / cell))
		var x1 := int(floor(maxf(a.x, b.x) / cell))
		var z0 := int(floor(minf(a.z, b.z) / cell))
		var z1 := int(floor(maxf(a.z, b.z) / cell))
		for cx in range(x0, x1 + 1):
			for cz in range(z0, z1 + 1):
				var key := Vector2i(cx, cz)
				var bucket: Array = buckets.get(key, [])
				for j in bucket:
					var idx := int(j)
					if _index_dist(i, idx, n) <= 2:
						continue
					if _segments_intersect(a, b, pts[idx], pts[(idx + 1) % n]):
						return true
				bucket.append(i)
				buckets[key] = bucket
	return false


## Shortest XZ distance from `p` to a closed polyline (kink-deviation measure:
## invariant to the along-curve arc shift the sine causes).
func _dist_to_curve(p: Vector3, pts: Array[Vector3]) -> float:
	var best := INF
	var n := pts.size()
	var pq := Vector2(p.x, p.z)
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var l2 := ab.length_squared()
		var t := 0.0
		if l2 > 0.0:
			t = clampf(Vector2(p.x - a.x, p.z - a.z).dot(ab) / l2, 0.0, 1.0)
		var q := Vector2(a.x, a.z) + ab * t
		best = minf(best, q.distance_to(pq))
	return best


func _in_bank_window(arc: float) -> bool:
	for r in LeMansLayout.BANK_REGIONS:
		var apex := LeMansLayout.arc_at_chainage(float(r["chainage"]))
		var half: float = r["half"]
		if absf(arc - apex) <= half + 0.25:
			return true
	return false


# --- constants ----------------------------------------------------------------


func test_constant_table() -> void:
	assert_float(LeMansLayout.TARGET_PERIMETER).is_equal_approx(13626.0, 0.001)
	assert_float(LeMansLayout.WIDTH_M).is_equal_approx(12.0, 0.0001)
	assert_int(LeMansLayout.TOTAL_POINTS).is_equal(4800)
	assert_float(LeMansLayout.spacing()).is_equal_approx(2.83875, 0.000001)
	assert_int(LeMansLayout.CP_STRIDE).is_equal(200)
	assert_int(LeMansLayout.CHECKPOINT_COUNT).is_equal(24)
	assert_int(LeMansLayout.GRID_INDEX).is_equal(4684)
	assert_float(LeMansLayout.ROAD_BASE_Y).is_equal_approx(0.15, 0.0001)
	assert_float(LeMansLayout.PLAIN_Y).is_equal_approx(-0.25, 0.0001)
	assert_float(LeMansLayout.BANK_MAX_DEG).is_equal_approx(3.0, 0.0001)
	assert_int(LeMansLayout.ANCHORS.size()).is_equal(51)
	assert_int(LeMansLayout.ANCHOR_CHAINAGES.size()).is_equal(51)
	# Chainages strictly increasing, anchored at 0 and 13,296 (+330 closing leg).
	assert_float(LeMansLayout.ANCHOR_CHAINAGES[0]).is_equal_approx(0.0, 0.001)
	assert_float(LeMansLayout.ANCHOR_CHAINAGES[50]).is_equal_approx(13296.0, 0.001)
	for i in range(1, 51):
		assert_float(LeMansLayout.ANCHOR_CHAINAGES[i]).is_greater(LeMansLayout.ANCHOR_CHAINAGES[i - 1])
	assert_float(LeMansLayout.TARGET_PERIMETER - LeMansLayout.ANCHOR_CHAINAGES[50]).is_equal_approx(330.0, 0.001)
	# Kink contract (§3.5): marked RECONSTRUCTED, tunables exposed.
	assert_bool(LeMansLayout.MULSANNE_KINK_RECONSTRUCTED).is_true()
	assert_float(LeMansLayout.MULSANNE_KINK_CHAINAGE).is_equal_approx(4630.0, 0.001)
	assert_float(LeMansLayout.MULSANNE_KINK_LATERAL_M).is_equal_approx(30.0, 0.001)
	assert_float(LeMansLayout.MULSANNE_KINK_WAVELENGTH_M).is_equal_approx(300.0, 0.001)


# --- A2: shape, perimeter, reversals, crossings, winding ----------------------


func test_a2_centerline_shape_and_perimeter() -> void:
	var pts := _points()
	assert_int(pts.size()).is_equal(LeMansLayout.TOTAL_POINTS)
	assert_float(LeMansLayout.perimeter()).is_equal_approx(13626.0, 0.0001)
	var chain := 0.0
	var min_step := INF
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var d := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
		chain += d
		min_step = minf(min_step, d)
	assert_float(chain).is_between(13626.0 - PERIMETER_TOL, 13626.0 + PERIMETER_TOL)
	assert_float(min_step).is_greater(2.0)  # A2: no near-duplicate points
	# A2: no reversals - adjacent step tangents never oppose.
	var n := pts.size()
	var worst := 1.0
	for i in n:
		var a := Vector2(pts[(i + 1) % n].x - pts[i].x, pts[(i + 1) % n].z - pts[i].z).normalized()
		var b := Vector2(pts[(i + 2) % n].x - pts[(i + 1) % n].x, pts[(i + 2) % n].z - pts[(i + 1) % n].z).normalized()
		worst = minf(worst, a.dot(b))
	assert_float(worst).is_greater(0.0)
	# Footprint sanity (v9 bbox + kink + CR overshoot margin).
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo.x = minf(lo.x, p.x)
		lo.y = minf(lo.y, p.z)
		hi.x = maxf(hi.x, p.x)
		hi.y = maxf(hi.y, p.z)
	assert_float(lo.x).is_between(-1000.0, -400.0)
	assert_float(hi.x).is_between(1900.0, 2500.0)
	assert_float(lo.y).is_between(-2400.0, -1700.0)
	assert_float(hi.y).is_between(3100.0, 3800.0)


func test_a2_no_self_crossings_and_winding() -> void:
	var pts := _points()
	assert_bool(_has_self_intersection(pts)).is_false()
	var area := _signed_area(pts)
	# Non-convex loop: |area| is large but well under the bbox area (3,000x5,900).
	assert_float(absf(area)).is_greater(1000000.0)
	assert_float(area).is_greater(0.0)  # v9 "winding clockwise" (z-down map view)


# --- A2 kink ------------------------------------------------------------------


func test_kink_lateral_formula() -> void:
	# Zero at both window ends (the §6 test) and exact 0 outside the window.
	assert_float(LeMansLayout.kink_lateral_at_chainage(4480.0)).is_equal_approx(0.0, 0.000001)
	assert_float(LeMansLayout.kink_lateral_at_chainage(4780.0)).is_equal_approx(0.0, 0.000001)
	assert_float(LeMansLayout.kink_lateral_at_chainage(4000.0)).is_equal_approx(0.0, 0.000001)
	assert_float(LeMansLayout.kink_lateral_at_chainage(5000.0)).is_equal_approx(0.0, 0.000001)
	# Peaks: -30 m a quarter wave before 4630, +30 m a quarter wave after.
	assert_float(LeMansLayout.kink_lateral_at_chainage(4555.0)).is_equal_approx(-30.0, 0.001)
	assert_float(LeMansLayout.kink_lateral_at_chainage(4705.0)).is_equal_approx(30.0, 0.001)
	assert_float(LeMansLayout.kink_lateral_at_chainage(4630.0)).is_equal_approx(0.0, 0.000001)


func test_kink_displaces_built_curve_by_30m_and_rejoins() -> void:
	var built := _points()
	var base := LeMansLayout.build_centerline_no_kink()
	assert_int(base.size()).is_equal(built.size())
	# Perpendicular distance from built points (at their own chainage) to the
	# no-kink curve: invariant to the along-curve arc shift the sine causes.
	# §3.5's sine peaks A at the QUARTER-wave points (4555 / 4705) and is zero at
	# 4630, so both lobes are measured, plus the zero crossing between them.
	var left := 0.0
	for c in range(4540, 4571):
		var p := LeMansLayout.point_at_arc(LeMansLayout.arc_at_chainage(float(c)))
		left = maxf(left, _dist_to_curve(p, base))
	var right := 0.0
	for c in range(4690, 4721):
		var p := LeMansLayout.point_at_arc(LeMansLayout.arc_at_chainage(float(c)))
		right = maxf(right, _dist_to_curve(p, base))
	assert_float(left).is_between(28.5, 31.5)   # -A lobe (30 m * final rescale)
	assert_float(right).is_between(28.5, 31.5)  # +A lobe
	var at_inflection := LeMansLayout.point_at_arc(LeMansLayout.arc_at_chainage(4630.0))
	assert_float(_dist_to_curve(at_inflection, base)).is_less(1.0)
	# Ends re-join the straight: no measurable offset.
	for c in [4480.0, 4780.0]:
		var p := LeMansLayout.point_at_arc(LeMansLayout.arc_at_chainage(c))
		assert_float(_dist_to_curve(p, base)).is_less(1.0)


# --- A3 landmarks -------------------------------------------------------------


func test_a3_landmarks_within_30m() -> void:
	for landmark in LANDMARKS:
		var chainage: float = LANDMARKS[landmark]
		var arc := LeMansLayout.arc_at_chainage(chainage)
		assert_float(absf(arc - chainage)).is_less_equal(30.0)
	# The map is monotone and (near) 1:1 outside the seam.
	for c in range(0, 13500, 100):
		assert_float(LeMansLayout.arc_at_chainage(float(c + 100))).is_greater(
				LeMansLayout.arc_at_chainage(float(c)))


# --- A4 named windows ---------------------------------------------------------


func test_a4_named_window_lengths() -> void:
	for w in NAMED_WINDOWS:
		var from_c: float = w[1]
		var to_c: float = w[2]
		var expected: float = w[3]
		var tol: float = w[4]
		var wrapped: bool = w[5]
		var length := LeMansLayout.arc_at_chainage(to_c) - LeMansLayout.arc_at_chainage(from_c)
		if wrapped:
			length += LeMansLayout.TARGET_PERIMETER
		assert_float(length).is_between(expected - tol, expected + tol)


# --- checkpoints / grid / lap arithmetic --------------------------------------


func test_checkpoints_and_grid_contract() -> void:
	var idx := LeMansLayout.checkpoint_indices()
	assert_int(idx.size()).is_equal(LeMansLayout.CHECKPOINT_COUNT)
	for i in idx.size() - 1:
		assert_int(idx[i]).is_equal((i + 1) * LeMansLayout.CP_STRIDE)
	assert_int(idx[idx.size() - 1]).is_equal(0)  # line LAST in travel order
	for i in idx:
		assert_int(i).is_less(LeMansLayout.TOTAL_POINTS)
	for i in idx:
		assert_int(i).is_not_equal(LeMansLayout.GRID_INDEX)  # grid on no gate
	assert_float(LeMansLayout.grid_arc()).is_equal_approx(13296.705, 0.001)
	assert_float(LeMansLayout.start_line_arc()).is_equal_approx(0.0, 0.0001)
	# A5 arithmetic: standing start = 329.295 m run-up + one full lap.
	assert_float(LeMansLayout.TARGET_PERIMETER - LeMansLayout.grid_arc()).is_equal_approx(329.295, 0.001)
	assert_float(LeMansLayout.grid_arc() + (LeMansLayout.TARGET_PERIMETER - LeMansLayout.grid_arc())
			+ LeMansLayout.TARGET_PERIMETER).is_equal_approx(27252.0, 0.001)


# --- bank ---------------------------------------------------------------------


func test_bank_profile_contract() -> void:
	var pts := _points()
	var bank := LeMansLayout.build_bank_profile()
	assert_int(bank.size()).is_equal(LeMansLayout.TOTAL_POINTS)
	var max_rad := deg_to_rad(LeMansLayout.BANK_MAX_DEG)
	var positives := 0
	var negatives := 0
	for i in bank.size():
		assert_float(absf(bank[i])).is_less_equal(max_rad + 0.0001)
		# Y rule: centerline Y = base + (W/2)|sin(bank)| (inner-edge invariant).
		assert_float(pts[i].y).is_equal_approx(
				LeMansLayout.ROAD_BASE_Y + (LeMansLayout.WIDTH_M * 0.5) * absf(sin(bank[i])), 0.0001)
		assert_float(pts[i].y).is_greater_equal(LeMansLayout.ROAD_BASE_Y - 0.0001)
		if bank[i] > 0.000001:
			positives += 1
		elif bank[i] < -0.000001:
			negatives += 1
	assert_int(positives).is_greater(0)
	assert_int(negatives).is_greater(0)
	# Zero outside every bank window.
	for i in bank.size():
		var arc := LeMansLayout.arc_of_index(i)
		if not _in_bank_window(arc):
			assert_float(bank[i]).is_equal_approx(0.0, 0.0001)
	# Each region: apex magnitude = max, sign tilts INTO the built turn.
	# cross(t1, t2).y < 0 is a right turn; barcelona space banks it POSITIVELY.
	var n := pts.size()
	for r in LeMansLayout.BANK_REGIONS:
		var apex := LeMansLayout.arc_at_chainage(float(r["chainage"]))
		var ia := int(roundf(apex / LeMansLayout.spacing())) % n
		var t1 := Vector3(pts[ia].x - pts[(ia - 1 + n) % n].x, 0.0, pts[ia].z - pts[(ia - 1 + n) % n].z)
		var t2 := Vector3(pts[(ia + 1) % n].x - pts[ia].x, 0.0, pts[(ia + 1) % n].z - pts[ia].z)
		var cross_y := t1.z * t2.x - t1.x * t2.z
		var expected := 1.0 if cross_y <= 0.0 else -1.0
		var peak := deg_to_rad(LeMansLayout.BANK_MAX_DEG) * float(r["deg"])
		assert_float(bank[ia]).is_equal_approx(expected * peak, 0.0002)
	# Windows never overlap (a point may bank once only).
	var regions := LeMansLayout.BANK_REGIONS
	for i in regions.size():
		var ai := LeMansLayout.arc_at_chainage(float(regions[i]["chainage"]))
		var hi: float = regions[i]["half"]
		for j in range(i + 1, regions.size()):
			var aj := LeMansLayout.arc_at_chainage(float(regions[j]["chainage"]))
			var hj: float = regions[j]["half"]
			assert_float(absf(aj - ai)).is_greater(hi + hj)


# --- frame / sharp corners / determinism --------------------------------------


func test_frame_at_arc_contract() -> void:
	var samples := [0.0, 300.0, 4630.0, 7508.0, 13296.705, 13600.0]
	for s in samples:
		var f: Dictionary = LeMansLayout.frame_at_arc(float(s))
		var center: Vector3 = f["center"]
		var forward: Vector3 = f["forward"]
		var right: Vector3 = f["right"]
		var cross: Vector3 = f["cross"]
		var bank: float = f["bank"]
		var expect := LeMansLayout.point_at_arc(float(s))
		assert_float(center.distance_to(expect)).is_less(0.001)
		assert_float(forward.length()).is_equal_approx(1.0, 0.0001)
		assert_float(right.length()).is_equal_approx(1.0, 0.0001)
		assert_float(right.y).is_equal_approx(0.0, 0.0001)
		assert_float(right.dot(forward)).is_equal_approx(0.0, 0.0001)
		# cross.y = -sin(bank) (TrackBuilder._frame convention).
		assert_float(cross.y).is_equal_approx(-sin(bank), 0.0001)
		assert_float(absf(bank)).is_less_equal(deg_to_rad(LeMansLayout.BANK_MAX_DEG) + 0.0001)


func test_sharp_corners_are_found() -> void:
	var corners := LeMansLayout.sharp_corner_chainages(40.0)
	# v9 measured 7 turns > 40 deg; keep a loose band around it.
	assert_int(corners.size()).is_between(5, 12)
	var prev := -1000.0
	for c in corners:
		assert_float(c).is_between(0.0, LeMansLayout.TARGET_PERIMETER)
		assert_float(c - prev).is_greater(20.0)
		prev = c


func test_build_is_deterministic() -> void:
	var a := _points()
	var b := _points()
	assert_int(a.size()).is_equal(b.size())
	for i in range(0, a.size(), 24):
		assert_float(a[i].x).is_equal_approx(b[i].x, 0.0000001)
		assert_float(a[i].y).is_equal_approx(b[i].y, 0.0000001)
		assert_float(a[i].z).is_equal_approx(b[i].z, 0.0000001)
