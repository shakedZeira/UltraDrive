# scripts/ai/racing_line.gd
class_name RacingLine
extends RefCounted

## Pure, deterministic racing-line builder (S5). Resamples a road centerline
## into an apex-shifted racing line per car class + skill tier: corner curvature
## drives a bounded left/right perturbation derived from the car-class pace
## band, so faster classes cut corners more aggressively while every point
## stays inside the road surface. No nodes, no scene access — headless-safe.

const MAX_OFFSET_FRACTION := 0.4
const CURVATURE_SCALE := 2.0
const SMOOTH_WINDOW := 5

## Skill-tier pace multipliers: strictly ordered Novice < Skilled < Expert.
const TIER_PACE := {
    "Novice": 0.8,
    "Skilled": 1.0,
    "Expert": 1.2,
}

## Car-class pace bands (D/C/B/A/S) and per-class apex shift fraction: faster
## classes carry more corner speed, so they cut a tighter line.
const CLASS_PACE := {
    "D": 0.55,
    "C": 0.68,
    "B": 0.80,
    "A": 0.92,
    "S": 1.05,
}
const CLASS_APEX := {
    "D": 0.22,
    "C": 0.28,
    "B": 0.34,
    "A": 0.40,
    "S": 0.46,
}

const CLASS_SEED := {"D": 11, "C": 23, "B": 37, "A": 41, "S": 53}
const TIER_SEED := {"Novice": 101, "Skilled": 201, "Expert": 307}

static func normalize_tier(tier: String) -> String:
    var t := tier.strip_edges().to_lower()
    match t:
        "novice":
            return "Novice"
        "expert":
            return "Expert"
        _:
            return "Skilled"

static func clean_class(car_class: String) -> String:
    var c := car_class.strip_edges().to_upper()
    return c if CLASS_PACE.has(c) else "D"

static func pace_band(car_class: String) -> float:
    return float(CLASS_PACE.get(clean_class(car_class), CLASS_PACE["D"]))

static func apex_fraction_for(car_class: String) -> float:
    return float(CLASS_APEX.get(clean_class(car_class), CLASS_APEX["D"]))

static func tier_pace(tier: String) -> float:
    return float(TIER_PACE.get(normalize_tier(tier), TIER_PACE["Skilled"]))

static func pace_for(car_class: String, tier: String) -> float:
    ## Combined rival pace: car-class pace band x skill tier. Rubber-band never
    ## enters this number, so pace (and thus standings) stays rubber-band-free.
    return pace_band(car_class) * tier_pace(tier)

static func seed_for(car_class: String, tier: String) -> int:
    var class_seed := int(CLASS_SEED.get(clean_class(car_class), 7))
    var tier_seed := int(TIER_SEED.get(normalize_tier(tier), 201))
    return class_seed * 1000 + tier_seed

static func build_racing_line(
        centerline: Array[Vector3], car_class: String, tier: String,
        road_width: float = 10.0, spacing: float = 4.0, seed: int = -1) -> Array[Vector3]:
    if centerline.size() < 3:
        return centerline.duplicate()
    var cls := clean_class(car_class)
    var t := normalize_tier(tier)
    var samples := resample_arc(centerline, spacing)
    if samples.size() < 3:
        return samples
    var curv := _smoothed_curvature(samples)
    var apex := apex_fraction_for(cls) * MAX_OFFSET_FRACTION * road_width * 0.5
    var rng := RandomNumberGenerator.new()
    rng.seed = seed if seed >= 0 else seed_for(cls, t)
    var phase := rng.randf() * TAU
    var harmonics := rng.randi_range(1, 3)
    var out: Array[Vector3] = []
    for i in range(samples.size()):
        var prev := samples[(i - 1 + samples.size()) % samples.size()]
        var nxt := samples[(i + 1) % samples.size()]
        var fwd := nxt - prev
        fwd.y = 0.0
        var right := Vector3.UP.cross(fwd).normalized() if fwd.length() > 0.0001 else Vector3.RIGHT
        var strength := clampf(absf(curv[i]) * CURVATURE_SCALE, 0.0, 1.0)
        var angle := float(i) / float(samples.size()) * TAU * float(harmonics) + phase
        var pulse := 0.6 + 0.4 * (0.5 + 0.5 * sin(angle))
        var offset := -signf(curv[i]) * apex * strength * pulse
        var center := samples[i]
        out.append(Vector3(center.x + right.x * offset, center.y, center.z + right.z * offset))
    return _smooth_xz(out, 3)

## Arc-length resampling of the centerline at fixed spacing. A closed loop
## (first == last within half a spacing) is traversed back to its start, then
## the duplicate closing sample is dropped so the result wraps cleanly: without
## this the seam would keep a multi-spacing gap, and smoothing across it would
## sag the racing line toward the missing arc.
static func resample_arc(centerline: Array[Vector3], spacing: float) -> Array[Vector3]:
    if centerline.size() < 2 or spacing <= 0.0:
        return centerline.duplicate()
    var total := 0.0
    for i in range(1, centerline.size()):
        total += centerline[i - 1].distance_to(centerline[i])
    if total <= 0.0:
        return centerline.duplicate()
    var closed := false
    if centerline.size() > 2:
        var typ := total / float(centerline.size() - 1)
        closed = centerline[0].distance_to(centerline[centerline.size() - 1]) < typ * 1.5
    if closed:
        total += centerline[centerline.size() - 1].distance_to(centerline[0])
    var out: Array[Vector3] = [centerline[0]]
    var cum := 0.0
    var next_dist := spacing
    var limit := centerline.size() + (1 if closed else 0)
    for idx in range(1, limit):
        var a := centerline[idx - 1]
        var b := centerline[idx] if idx < centerline.size() else centerline[0]
        var seg := a.distance_to(b)
        if seg > 0.0001:
            while next_dist <= cum + seg + 0.0001:
                var f := clampf((next_dist - cum) / seg, 0.0, 1.0)
                out.append(a.lerp(b, f))
                next_dist += spacing
        cum += seg
    while out.size() > 1 and out[out.size() - 1].distance_to(out[0]) < spacing * 0.5:
        out.remove_at(out.size() - 1)
    return out

static func all_finite(points: Array[Vector3]) -> bool:
    for p in points:
        if not _finite_scalar(p.x) or not _finite_scalar(p.y) or not _finite_scalar(p.z):
            return false
    return true

static func max_turn_angle(points: Array[Vector3]) -> float:
    if points.size() < 3:
        return 0.0
    var n := points.size()
    var best := 0.0
    for i in range(n):
        var a := points[(i - 1 + n) % n]
        var b := points[i]
        var c := points[(i + 1) % n]
        var t0 := b - a
        var t1 := c - b
        t0.y = 0.0
        t1.y = 0.0
        if t0.length() < 0.0001 or t1.length() < 0.0001:
            continue
        var ang := atan2(t0.x * t1.z - t0.z * t1.x, t0.x * t1.x + t0.z * t1.z)
        best = maxf(best, absf(ang))
    return best

static func max_segment_length(points: Array[Vector3]) -> float:
    var best := 0.0
    for i in range(1, points.size()):
        best = maxf(best, points[i - 1].distance_to(points[i]))
    if points.size() > 2:
        best = maxf(best, points[points.size() - 1].distance_to(points[0]))
    return best

## Farthest XZ distance from any racing-line point to the nearest centerline
## point; the acceptance bound for the apex-shift perturbation.
static func max_lateral_deviation(line: Array[Vector3], centerline: Array[Vector3]) -> float:
    var best := 0.0
    for p in line:
        var nearest := INF
        for q in centerline:
            var dx := p.x - q.x
            var dz := p.z - q.z
            nearest = minf(nearest, dx * dx + dz * dz)
        best = maxf(best, sqrt(nearest))
    return best

static func _smoothed_curvature(samples: Array[Vector3]) -> Array[float]:
    var raw: Array[float] = []
    raw.resize(samples.size())
    for i in range(samples.size()):
        raw[i] = _curvature_xz(samples[i], samples[(i - 1 + samples.size()) % samples.size()], samples[(i + 1) % samples.size()])
    return _smooth_float_array(raw, SMOOTH_WINDOW)

static func _curvature_xz(center: Vector3, prev: Vector3, nxt: Vector3) -> float:
    var t0 := center - prev
    var t1 := nxt - center
    t0.y = 0.0
    t1.y = 0.0
    if t0.length() < 0.0001 or t1.length() < 0.0001:
        return 0.0
    return atan2(t0.x * t1.z - t0.z * t1.x, t0.x * t1.x + t0.z * t1.z)

static func _smooth_float_array(vals: Array[float], window: int) -> Array[float]:
    var n := vals.size()
    if n < 2 or window < 2:
        return vals.duplicate()
    var half := window / 2
    var out: Array[float] = []
    out.resize(n)
    for i in range(n):
        var sum := 0.0
        var count := 0
        for k in range(-half, half + 1):
            sum += vals[wrapi(i + k, 0, n)]
            count += 1
        out[i] = sum / float(count)
    return out

static func _smooth_xz(points: Array[Vector3], window: int) -> Array[Vector3]:
    var n := points.size()
    if n < 2 or window < 2:
        return points.duplicate()
    var half := window / 2
    var out: Array[Vector3] = []
    out.resize(n)
    for i in range(n):
        var sum_x := 0.0
        var sum_z := 0.0
        var count := 0
        for k in range(-half, half + 1):
            var j := wrapi(i + k, 0, n)
            sum_x += points[j].x
            sum_z += points[j].z
            count += 1
        out[i] = Vector3(sum_x / float(count), points[i].y, sum_z / float(count))
    return out

static func _finite_scalar(value: float) -> bool:
    return is_finite(value)