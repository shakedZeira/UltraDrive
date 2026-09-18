# scripts/world/event_registry.gd
class_name EventRegistry
extends RefCounted

## Deterministic event placement by driving culture (P6). Every site is a pure
## function of the classifiable RoadDef network plus the POI anchors, so the
## same master seed always yields the same events headlessly ("same master-seed
## determinism"): touge_duel on the steepest TOUGE corridor, drag_strip on the
## longest straight highway run, drift_zone on the hairpin-heavy TOUGE fold,
## night_street_loop on the hub ring, marathon_highway on the full perimeter
## ring, and one time_attack landmark per POI anchor.

## A segment counts as "straight" when its heading change vs the previous
## segment stays under this many degrees.
const STRAIGHT_HEADING_LIMIT_DEG := 2.0

## Minimum mean gradient (m climb / m run) a TOUGE corridor must keep before it
## qualifies as a duel-grade touge.
const TOUGE_GRADIENT_MIN := 0.05

const DEFAULT_LAPS_STREET := 3
const MARATHON_LAPS := 1

## Pure entry point: defs = every classified corridor (CorridorPlanner.plan),
## anchors = base POI positions for the time-attack set. Returns
## { event_id -> { kind, name, stage, tier, road_id, position, extra } }.
static func place(defs: Array[RoadDef], anchors: Array[Vector3]) -> Dictionary:
    var events := {}
    events["touge_duel"] = _touge_duel(defs)
    events["drag_strip"] = _drag_strip(defs)
    events["drift_zone"] = _drift_zone(defs)
    events["night_street_loop"] = _night_street_loop(defs)
    events["marathon_highway"] = _marathon_highway(defs)
    for i in anchors.size():
        events["time_attack_%d" % i] = _time_attack(defs, anchors[i], i)
    return events

# ---------------------------------------------------------------------------
# Placement rules.
# ---------------------------------------------------------------------------

static func _touge_duel(defs: Array[RoadDef]) -> Dictionary:
    var picked := -1
    var picked_mean := 0.0
    for idx in defs.size():
        var def: RoadDef = defs[idx]
        if def.tier != RoadDef.Tier.TOUGE:
            continue
        var segs := _segment_count(def)
        var sum := 0.0
        for i in range(segs):
            sum += _segment_gradient(def, i)
        var mean := sum / float(segs) if segs > 0 else 0.0
        if picked < 0 or mean > picked_mean:
            picked = idx
            picked_mean = mean
    var chosen: RoadDef = defs[picked] if picked >= 0 else defs[0]
    var n := _segment_count(chosen)
    var best_i := 0
    var best_g := -1.0
    var site := Vector3.ZERO
    for i in range(n):
        var g := _segment_gradient(chosen, i)
        if g > best_g:
            best_g = g
            best_i = i
    if n > 0:
        site = (_segment_a(chosen, best_i) + _segment_b(chosen, best_i)) * 0.5
    var extra := {"mean_gradient": picked_mean, "max_gradient": best_g, "index": best_i}
    return _event("touge_duel", "Mountain Duel", chosen, site, extra)


static func _drag_strip(defs: Array[RoadDef]) -> Dictionary:
    var picked := -1
    var picked_len := 0.0
    var picked_site := Vector3.ZERO
    for idx in defs.size():
        var def: RoadDef = defs[idx]
        if def.tier != RoadDef.Tier.HIGHWAY:
            continue
        if def.points.size() < 2:
            continue
        var segs := _segment_count(def)
        var straight := PackedByteArray()
        straight.resize(segs)
        var heads := PackedFloat32Array()
        for i in range(segs):
            heads.append(_heading_deg(_segment_a(def, i), _segment_b(def, i)))
        for i in range(segs):
            var prev := (i - 1 + segs) % segs if def.closed else maxi(i - 1, 0)
            straight[i] = 1 if _turn_deg(heads[prev], heads[i]) <= STRAIGHT_HEADING_LIMIT_DEG else 0
        var run_len := 0.0
        var run_site := def.points[0]
        var best_len := 0.0
        for start in range(segs):
            if straight[start] == 0:
                continue
            var count := 0
            var acc := 0.0
            var idx_i := start
            while straight[idx_i % segs] == 1 and count < segs:
                acc += _segment_length(def, idx_i % segs)
                count += 1
                idx_i += 1
            if count > 0 and acc > best_len:
                best_len = acc
                run_site = _midpoint(def, start, count)
        if best_len > picked_len:
            picked_len = best_len
            picked_site = run_site
            picked = idx
    var extra := {"run_length_m": picked_len, "def_index": picked}
    var host: RoadDef = defs[picked] if picked >= 0 else defs[0]
    return _event("drag_strip", "Highland Drag", host, picked_site, extra)


static func _drift_zone(defs: Array[RoadDef]) -> Dictionary:
    var picked := -1
    var picked_turn := 0.0
    var picked_site := Vector3.ZERO
    for idx in defs.size():
        var def: RoadDef = defs[idx]
        if def.tier != RoadDef.Tier.TOUGE:
            continue
        var segs := _segment_count(def)
        if segs < 2:
            continue
        var heads := PackedFloat32Array()
        for i in range(segs):
            heads.append(_heading_deg(_segment_a(def, i), _segment_b(def, i)))
        var best_turn := 0.0
        var best_site := Vector3.ZERO
        for i in range(segs):
            if not def.closed and i == 0:
                continue
            var prev := (i - 1 + segs) % segs if def.closed else i - 1
            var turn := _turn_deg(heads[prev], heads[i])
            if turn > best_turn:
                best_turn = turn
                best_site = _segment_a(def, i)
        if best_turn > picked_turn:
            picked_turn = best_turn
            picked_site = best_site
            picked = idx
    var extra := {"turn_deg": picked_turn, "def_index": picked}
    var host: RoadDef = defs[picked] if picked >= 0 else defs[0]
    return _event("drift_zone", "Switchback Drift", host, picked_site, extra)


static func _night_street_loop(defs: Array[RoadDef]) -> Dictionary:
    var hub := -1
    for idx in defs.size():
        var def: RoadDef = defs[idx]
        if def.id == "hub-ring":
            hub = idx
            break
    if hub < 0:
        for idx in defs.size():
            var def: RoadDef = defs[idx]
            if def.tier == RoadDef.Tier.ARTERIAL and def.closed:
                hub = idx
                break
    if hub < 0:
        hub = 0
    var host: RoadDef = defs[hub]
    var site := host.points[0] if host.points.size() > 0 else Vector3.ZERO
    return _event("night_street_loop", "Festival Street Loop", host, site,
            {"laps": DEFAULT_LAPS_STREET})


static func _marathon_highway(defs: Array[RoadDef]) -> Dictionary:
    var picked := -1
    var picked_len := 0.0
    for idx in defs.size():
        var def: RoadDef = defs[idx]
        if def.tier != RoadDef.Tier.HIGHWAY:
            continue
        var length := CorridorPlanner.chain_length_m(def.points)
        if length > picked_len:
            picked_len = length
            picked = idx
    if picked < 0:
        picked = 0
        picked_len = CorridorPlanner.chain_length_m(defs[0].points)
    var host: RoadDef = defs[picked]
    var site := host.points[0] if host.points.size() > 0 else Vector3.ZERO
    return _event("marathon_highway", "Perimeter Marathon", host, site,
            {"length_m": picked_len, "laps": MARATHON_LAPS})


static func _time_attack(defs: Array[RoadDef], anchor: Vector3, idx: int) -> Dictionary:
    var nearest := -1
    var best := INF
    for i in defs.size():
        var pts: Array[Vector3] = defs[i].points
        for p in pts:
            var d := anchor.distance_to(p)
            if d < best:
                best = d
                nearest = i
    var road := defs[nearest] if nearest >= 0 else defs[0]
    var site := anchor
    return _event("time_attack", "Time Attack %d" % (idx + 1), road, site,
            {"anchor_index": idx, "road_clearance_m": best})


# ---------------------------------------------------------------------------
# Shared builders / metrics.
# ---------------------------------------------------------------------------

static func _event(kind: String, name: String, def: RoadDef, site: Vector3, extra: Dictionary) -> Dictionary:
    return {
        "kind": kind,
        "name": name,
        "stage": RoadDef.tier_name(def.tier),
        "tier": def.tier,
        "road_id": def.id,
        "position": site,
        "extra": extra,
    }

static func _segment_count(def: RoadDef) -> int:
    var n := def.points.size()
    if n < 2:
        return 0
    return n - 1 + (1 if def.closed else 0)

static func _segment_a(def: RoadDef, i: int) -> Vector3:
    var pts: Array[Vector3] = def.points
    return pts[i % pts.size()]

static func _segment_b(def: RoadDef, i: int) -> Vector3:
    var pts: Array[Vector3] = def.points
    return pts[(i + 1) % pts.size()]

static func _segment_length(def: RoadDef, i: int) -> float:
    return _segment_a(def, i).distance_to(_segment_b(def, i))

static func _segment_gradient(def: RoadDef, i: int) -> float:
    return _gradient(_segment_a(def, i), _segment_b(def, i))

static func _gradient(a: Vector3, b: Vector3) -> float:
    var dx := b.x - a.x
    var dz := b.z - a.z
    var horizontal := sqrt(dx * dx + dz * dz)
    if horizontal < 0.0001:
        return 0.0
    return absf(b.y - a.y) / horizontal

static func _heading_deg(a: Vector3, b: Vector3) -> float:
    return rad_to_deg(atan2(b.z - a.z, b.x - a.x))

static func _turn_deg(from_heading: float, to_heading: float) -> float:
    var d := absf(from_heading - to_heading)
    d = fposmod(d, 360.0)
    if d > 180.0:
        d = 360.0 - d
    return d

## World position halfway along the arc from segment start through `count`
## straight segments (closed chains wrap). Needs count > 0.
static func _midpoint(def: RoadDef, start: int, count: int) -> Vector3:
    var segs := _segment_count(def)
    var target := 0.0
    for i in range(count):
        target += _segment_length(def, (start + i) % segs)
    target *= 0.5
    var acc := 0.0
    for i in range(count):
        var seg := (start + i) % segs
        var len := _segment_length(def, seg)
        if acc + len >= target or i == count - 1:
            var frac := clampf((target - acc) / len if len > 0.0001 else 0.0, 0.0, 1.0)
            return _segment_a(def, seg).lerp(_segment_b(def, seg), frac)
        acc += len
    return _segment_a(def, start)