# scripts/world/spline.gd
class_name Spline
extends RefCounted

## Pure spline/vault toolkit for the open-world corridor pipeline. Every
## helper is deterministic and scene-free (no nodes, no Terrain3D): the same
## inputs always produce the same output, so headless tests and the runtime
## terrain bake agree. The Catmull-Rom sampler mirrors world_driver.gd's
## `_catmull_rom_xz` exactly (clamped ends, XZ only, Y produced separately) so
## the "three bootstrap roads" contract keeps byte-identical geometry.

## Catmull-Rom spline sampled on XZ only (Y left at 0; assiged later by a
## gradient profile) with clamped end tangents, so the curve passes through
## every control point and the endpoints sit exactly on their control points.
## This mirrors world_driver.gd:_catmull_rom_xz (135-153) verbatim.
static func catmull_rom_xz(control: Array[Vector3], t: float) -> Vector3:
	var n := control.size()
	if n <= 1:
		return control[0] if n == 1 else Vector3.ZERO
	var seg := clampi(int(floorf(t * float(n - 1))), 0, n - 2)
	var f := clampf(t * float(n - 1) - float(seg), 0.0, 1.0)
	var p0: Vector3 = control[maxi(seg - 1, 0)]
	var p1: Vector3 = control[seg]
	var p2: Vector3 = control[seg + 1]
	var p3: Vector3 = control[mini(seg + 2, n - 1)]
	var f2 := f * f
	var f3 := f2 * f
	var x := 0.5 * (2.0 * p1.x + (-p0.x + p2.x) * f
		+ (2.0 * p0.x - 5.0 * p1.x + 4.0 * p2.x - p3.x) * f2
		+ (-p0.x + 3.0 * p1.x - 3.0 * p2.x + p3.x) * f3)
	var z := 0.5 * (2.0 * p1.z + (-p0.z + p2.z) * f
		+ (2.0 * p0.z - 5.0 * p1.z + 4.0 * p2.z - p3.z) * f2
		+ (-p0.z + 3.0 * p1.z - 3.0 * p2.z + p3.z) * f3)
	return Vector3(x, 0.0, z)

## Total horizontal arc length of a polyline (sum of 3D segment lengths).
static func arc_length(points: Array[Vector3]) -> float:
	var total := 0.0
	for i in points.size():
		if i > 0:
			total += points[i - 1].distance_to(points[i])
	return total

## Arc-length resampling of a dense polyline: every `spacing` metres along the
## centreline a point is emitted whose Y ramps linearly from y_from to end.y
## across the journey. The final `end` point is appended when the last sample
## sits more than 1 m from it, and the FIRST point is forced to (chain[0].x,
## y_from, chain[0].z) — all of which reproduces world_driver.gd
## `_pass_connector` (91-130) semantics exactly.
static func resample_by_arc(chain: PackedVector3Array, spacing: float, y_from: float, end: Vector3) -> Array[Vector3]:
	var road: Array[Vector3] = []
	if chain.is_empty():
		return road
	road.append(Vector3(chain[0].x, y_from, chain[0].z))
	var total := arc_length(chain)
	if total <= 0.0:
		return road
	var cumulative := PackedFloat32Array()
	cumulative.resize(chain.size())
	var acc := 0.0
	for i in chain.size():
		if i > 0:
			acc += chain[i - 1].distance_to(chain[i])
		cumulative[i] = acc
	var next_dist := spacing
	for seg in range(1, chain.size()):
		var a := chain[seg - 1]
		var b := chain[seg]
		var seg_start := cumulative[seg - 1]
		var seg_len := cumulative[seg] - seg_start
		while next_dist <= cumulative[seg]:
			var local := (next_dist - seg_start) / seg_len if seg_len > 0.0001 else 0.0
			var pos := a.lerp(b, local)
			var frac := next_dist / total
			road.append(Vector3(pos.x, lerpf(y_from, end.y, frac), pos.z))
			next_dist += spacing
	var last := road[road.size() - 1]
	if last.distance_to(end) > 1.0:
		road.append(end)
	return road

## Gradient-profile ramping: plants deterministic Y along an open chain so the
## road neither cliffs nor cuts under the terrain. With no height_provider the
## Ys lerp from y_from to y_to by chain index (flat-safe). When a provider is
## given it follows the `ground_height_provider: Callable(Vector2 -> float)`
## convention (foliage.gd/prop_scatterer.gd); the sampled heights are clamped
## to y_max and the endpoints are pinned so the corridor always meets its
## neighbours at the planned elevation.
static func gradient_ramp(points: Array[Vector3], y_from: float, y_to: float, height_provider: Callable = Callable(), y_max: float = 300.0) -> Array[Vector3]:
	var n := points.size()
	var out: Array[Vector3] = []
	if n == 0:
		return out
	var start_h := y_from
	var end_h := y_to
	if height_provider.is_valid():
		start_h = clampf(float(height_provider.call(Vector2(points[0].x, points[0].z))), -8.0, y_max)
		end_h = clampf(float(height_provider.call(Vector2(points[n - 1].x, points[n - 1].z))), -8.0, y_max)
	for i in n:
		var t := float(i) / float(maxi(n - 1, 1))
		out.append(Vector3(points[i].x, lerpf(start_h, end_h, t), points[i].z))
	return out

## Touge serration: folds a corridor polyline into hairpin switchbacks. A
## segment is folded when its horizontal run exceeds max_step or its local
## slope exceeds slope_budget ("exceeds the slope budget"). Each folded
## segment becomes three zigzag waypoints leaning alternately left/right of
## the segment axis; their Y interpolates the existing gradient so the profile
## stays smooth. Deterministic: the fold offset amplitude is jittered by a PRNG
## seeded from fold_seed.
static func hairpin_fold(points: Array[Vector3], max_step: float, slope_budget: float, hairpin_offset: float, fold_seed: int = 0) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if points.size() < 2:
		return points.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = fold_seed
	out.append(points[0])
	for s in points.size() - 1:
		var a: Vector3 = points[s]
		var b: Vector3 = points[s + 1]
		var d := b - a
		var xz_len := Vector2(d.x, d.z).length()
		var slope := absf(d.y) / xz_len if xz_len > 0.0001 else 0.0
		if xz_len > max_step or slope > slope_budget:
			var perp := Vector2(d.z, -d.x)
			if perp.length_squared() > 0.0001:
				perp = perp.normalized()
			var off := hairpin_offset * (0.8 + rng.randf() * 0.4)
			for k in 3:
				var f := float(k + 1) / 3.0
				var c := a.lerp(b, f)
				var sgn := 1.0 if k % 2 == 0 else -1.0
				out.append(Vector3(c.x + perp.x * off * sgn, c.y, c.z + perp.y * off * sgn))
		out.append(b)
	return out

## Coast-hugging conformer: re-expresses a corridor chain so every point lands
## inside a tolerance band around the shoreline (radius sea_radius of
## sea_center, sampled at the P1 sea band, i.e. the height~0 crossing). Each
## point is pushed to sea_radius + a seeded wobble torn between +/- tolerance
## and given a low coastal Y. Deterministic for hug_seed.
static func coast_hug(points: Array[Vector3], sea_center: Vector2, sea_radius: float, tolerance: float, y_base: float, hug_seed: int = 0) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hug_seed
	for p in points:
		var rel := Vector2(p.x, p.z) - sea_center
		if rel.length_squared() <= 0.0001:
			continue
		var dir := rel.normalized()
		var wobble := (rng.randf() - 0.5) * 2.0 * tolerance
		var r := sea_radius + wobble
		if r < sea_radius - tolerance + 0.5:
			r = sea_radius - tolerance + 0.5
		var q := sea_center + dir * r
		var y := y_base + 4.0 * sin(p.x * 0.01 + p.z * 0.008)
		out.append(Vector3(q.x, y, q.y))
	return out