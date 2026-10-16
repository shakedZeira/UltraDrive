# scripts/race/race_gap_tracker.gd
class_name RaceGapTracker
extends RefCounted

## Live per-rival time-gap estimator for the HUD standings ("virtual
## checkpoints"). Pure and deterministic: no nodes, no scene, no engine state,
## so it is headless-safe and unit-testable on its own.
##
## A fixed-arc-length grid of VIRTUAL checkpoints is laid over the racing line /
## track centreline (one every `spacing` metres). Each frame every car's
## continuous progress S along the loop is projected onto the polyline, and the
## elapsed times at the grid points it sweeps past are interpolated from the
## previous frame's (S, t) sample. A rival's gap to the player is the difference
## of the two cars' elapsed times AT THE SAME progress S, taken at whichever car
## is further back so both have already recorded that point:
##
##     gap = time_at(rival, S_min) - time_at(player, S_min)     S_min = min(S)
##
## Positive = the rival needed longer to reach that point (behind); negative =
## the rival reached it sooner (ahead). Because virtual-checkpoint crossings are
## interpolated between frames, the number moves smoothly instead of stepping
## once per real checkpoint.
##
## Same-lap only: when the two cars are on different laps the splits no longer
## describe the same loop, so the gap is reported as NAN and the HUD hides it.

## A path shorter than this cannot define a loop.
const MIN_PATH_POINTS := 3
## Sub-millimetre / sub-millisecond floor used for every "did it move?" test.
const MIN_ARC := 0.01

## The loop geometry.
var _pts: PackedVector3Array = PackedVector3Array()
## Cumulative arc from _pts[0] to _pts[i] (the closing segment is not included;
## it lives between _cum[last] and _total).
var _cum: PackedFloat64Array = PackedFloat64Array()
var _total: float = 0.0
var _step: float = 1.0
var _vcp_count: int = 0
var _active: bool = false

## Per-car sample state, keyed by the car instance (Object). Streams in
## parallel, so no per-frame allocation and no ordering assumptions.
var _splits: Dictionary = {}  # car -> PackedFloat64Array(_vcp_count), -1 = not crossed
var _lap: Dictionary = {}     # car -> int (0-based lap index)
var _prev_u: Dictionary = {}  # car -> float unwrapped arc (monotonic)
var _prev_t: Dictionary = {}  # car -> float elapsed at _prev_u
var _cur_s: Dictionary = {}   # car -> float current wrapped S
var _cur_t: Dictionary = {}   # car -> float current elapsed

func is_active() -> bool:
	return _active

func vcp_count() -> int:
	return _vcp_count

func path_length() -> float:
	return _total

## Builds the virtual-checkpoint grid over `path` (a closed loop of at least
## MIN_PATH_POINTS points) at `spacing` metres, and clears all per-car samples.
## Any invalid input (too few points, non-positive spacing, zero length)
## deactivates the tracker so `gap_seconds` returns NAN and the HUD shows
## nothing.
func configure(path: Array[Vector3], spacing: float = 5.0) -> void:
	reset()
	_active = false
	_pts = PackedVector3Array()
	_cum = PackedFloat64Array()
	_total = 0.0
	_vcp_count = 0
	if spacing <= 0.0 or path.size() < MIN_PATH_POINTS:
		return
	for p in path:
		_pts.append(p)
	var n := _pts.size()
	_cum.resize(n)
	var acc := 0.0
	for i in range(n):
		if i > 0:
			acc += _xz_dist(_pts[i - 1], _pts[i])
		_cum[i] = acc
	_total = acc + _xz_dist(_pts[n - 1], _pts[0])
	if _total <= MIN_ARC:
		return
	_step = spacing
	_vcp_count = maxi(2, int(ceil(_total / _step)))
	_active = true

## Clears every per-car sample (lap/history), keeping the geometry. Used when a
## new race starts so the previous race's splits cannot leak in.
func reset() -> void:
	_splits.clear()
	_lap.clear()
	_prev_u.clear()
	_prev_t.clear()
	_cur_s.clear()
	_cur_t.clear()

## Continuous progress of `pos` along the loop, in [0, total): the XZ projection
## onto the closest of the two polyline segments touching the nearest vertex.
## Projecting onto a segment (not snapping to a vertex) is what keeps S smooth
## frame to frame.
func progress_of(pos: Vector3) -> float:
	if not _active:
		return 0.0
	var n := _pts.size()
	var best_i := 0
	var best_d2 := INF
	for i in range(n):
		var dx := _pts[i].x - pos.x
		var dz := _pts[i].z - pos.z
		var d2 := dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best_i = i
	var best_s := _cum[best_i]
	var best_seg := INF
	for k in 2:
		var start := wrapi(best_i - 1, 0, n) if k == 0 else best_i
		var a := _pts[start]
		var b := _pts[(start + 1) % n]
		var abx := b.x - a.x
		var abz := b.z - a.z
		var len2 := abx * abx + abz * abz
		if len2 <= 0.000001:
			continue
		var t := ((pos.x - a.x) * abx + (pos.z - a.z) * abz) / len2
		t = clampf(t, 0.0, 1.0)
		var px := a.x + abx * t
		var pz := a.z + abz * t
		var dx2 := px - pos.x
		var dz2 := pz - pos.z
		var d2 := dx2 * dx2 + dz2 * dz2
		if d2 < best_seg:
			best_seg = d2
			best_s = _cum[start] + t * sqrt(len2)
	return fposmod(best_s, _total)

## Records one frame of a car's motion. `elapsed` is the car's race-elapsed time
## (any shared monotonic clock works, as long as every car uses the same one).
func sample(car: Object, pos: Vector3, elapsed: float) -> void:
	if not _active or car == null:
		return
	var s := progress_of(pos)
	if not _splits.has(car):
		_init_car(car, s, elapsed)
		return
	var lap: int = _lap[car]
	var prev_u: float = _prev_u[car]
	var prev_t: float = _prev_t[car]
	var u := float(lap) * _total + s
	if u + MIN_ARC < prev_u and prev_u - u > _total * 0.5:
		# Forward wrap: the car crossed the start/finish line into a new lap.
		var u_new := float(lap + 1) * _total + s
		var span := u_new - prev_u
		var t_line := prev_t
		if span > MIN_ARC:
			t_line = prev_t + (float(lap + 1) * _total - prev_u) / span * (elapsed - prev_t)
		_lap[car] = lap + 1
		var arr := PackedFloat64Array()
		arr.resize(_vcp_count)
		arr.fill(-1.0)
		_splits[car] = arr
		_fill_range(car, float(lap + 1) * _total, t_line, u_new, elapsed)
		arr[0] = t_line
		_prev_u[car] = u_new
		_prev_t[car] = elapsed
	elif u > prev_u + MIN_ARC:
		_fill_range(car, prev_u, prev_t, u, elapsed)
		_prev_u[car] = u
		_prev_t[car] = elapsed
	_cur_s[car] = s
	_cur_t[car] = elapsed

## Signed gap in seconds between `car` and `reference` (the player): positive =
## `car` behind, negative = `car` ahead, NAN = not comparable yet (no samples,
## different laps, or an unknown split).
func gap_seconds(car: Object, reference: Object) -> float:
	if not _active or car == null or reference == null or car == reference:
		return NAN
	if not _splits.has(car) or not _splits.has(reference):
		return NAN
	var lap_car: int = _lap.get(car, 0)
	var lap_ref: int = _lap.get(reference, 0)
	if lap_car != lap_ref:
		return NAN
	var s_car: float = _cur_s[car]
	var s_ref: float = _cur_s[reference]
	var s := minf(s_car, s_ref)
	var t_car := _time_at(car, s, s_car)
	var t_ref := _time_at(reference, s, s_ref)
	if is_nan(t_car) or is_nan(t_ref):
		return NAN
	return t_car - t_ref

# --- internals --------------------------------------------------------------

static func _xz_dist(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return sqrt(dx * dx + dz * dz)

func _init_car(car: Object, s: float, elapsed: float) -> void:
	var arr := PackedFloat64Array()
	arr.resize(_vcp_count)
	arr.fill(-1.0)
	var upto := mini(int(floor(s / _step)) + 1, _vcp_count)
	for k in range(upto):
		arr[k] = elapsed
	_splits[car] = arr
	_lap[car] = 0
	_prev_u[car] = s
	_prev_t[car] = elapsed
	_cur_s[car] = s
	_cur_t[car] = elapsed

## Interpolates the crossing time of every virtual checkpoint whose (unwrapped)
## arc falls in `(s0, s1]`, linearly between (s0, t0) and (s1, t1). `base_lap`
## is derived from s0 so a wrap fill lands on the new lap's vcp indices.
func _fill_range(car: Object, s0: float, t0: float, s1: float, t1: float) -> void:
	if s1 <= s0 + MIN_ARC:
		return
	var arr: PackedFloat64Array = _splits[car]
	var span := s1 - s0
	var base_lap := int(floor(s0 / _total + 0.000001))
	var k := int(floor((s0 - float(base_lap) * _total) / _step)) + 1
	var guard := 0
	while guard <= _vcp_count + 2:
		guard += 1
		var a := float(base_lap) * _total + float(k) * _step
		if a > s1 + MIN_ARC:
			break
		if k >= 0 and k < _vcp_count:
			arr[k] = t0 + (a - s0) / span * (t1 - t0)
		k += 1

## A car's elapsed time when it was at progress `target_s`, interpolated from
## the virtual-checkpoint splits. `car_s` is the car's current S, used as the
## forward anchor when the NEXT checkpoint has not been recorded yet (the car is
## still inside the current interval).
func _time_at(car: Object, target_s: float, car_s: float) -> float:
	if target_s < -MIN_ARC or not _splits.has(car):
		return NAN
	var arr: PackedFloat64Array = _splits[car]
	if arr.is_empty():
		return NAN
	var j := int(floor(target_s / _step))
	j = clampi(j, 0, _vcp_count - 1)
	var s_j := float(j) * _step
	var t_j := arr[j]
	if t_j < 0.0:
		return NAN
	if j + 1 < _vcp_count:
		var t_j1 := arr[j + 1]
		if t_j1 >= 0.0:
			var frac := clampf((target_s - s_j) / _step, 0.0, 1.0)
			return t_j + frac * (t_j1 - t_j)
	var cur_t: float = _cur_t[car]
	if car_s > target_s + 0.01:
		var denom := car_s - s_j
		if denom > 0.0001:
			var frac2 := clampf((target_s - s_j) / denom, 0.0, 1.0)
			return t_j + frac2 * (cur_t - t_j)
	return cur_t
