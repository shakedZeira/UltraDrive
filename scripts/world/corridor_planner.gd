# scripts/world/corridor_planner.gd
class_name CorridorPlanner
extends RefCounted

## Deterministic blueprint -> RoadDef pipeline for the P2 open-world network.
## Given a master world seed this emits the full classified corridor list ready
## for RoadNetwork.add_road_def(). Pure and headless-safe: no scene access, no
## Terrain3D, no GDScript engine state — the same (seed, height_provider) pair
## always returns the same Array[RoadDef], so the terrain bake, the map and the
## tests all describe the same world.

## Master seed derived from the terrain's P1 fixed hash: 1337 * 1337 = 1787569.
## Multiplying TerrainBaker.NOISE_SEED (1337) by itself keeps every corridor in
## the same deterministic family as the heightfield (any fBm/dome lookup stays
## reproducible across runs and machines) while giving the corridor layer its
## own numeric identity so seed-space is never accidentally shared with test
## hashes.
const MASTER_SEED := TerrainBaker.NOISE_SEED * 1337

## Minimum drivable network length in kilometres (the P2 plan's 60-100 km
## target; tune via tier_defaults["km_target"] per call). The network is built
## to land comfortably above this value.
const KM_TARGET := 60.0

## Superelevation cap for the HIGHWAY tier (TrackBuilder derives left/right
## bank direction from curvature).
const HIGHWAY_BANKING := 0.35

## World-space anchor of the MountainPassZone node (open_world_root.tscn).
## The world-offset pass loop is generated from this + the scene's mountain
## pass ring formula so the whole 3-road bootstrap is reproducible headless.
const PASS_ZONE_POS := Vector3(3800.0, 14.0, 3200.0)

## Extra metres of ring-parallel merge lane the spawn ramp runs before its
## taper starts. Every access ramp gets the standard 14-vertex (~1.5 km) taper;
## the spawn ramp comes off the hub basin at a crawl, so it needs a longer
## constant-offset run to reach highway speed on ring grade.
const SPAWN_MERGE_RUN_M := 200.0

## The canonical player-facing name of EVERY corridor, keyed by id. This is the
## single source of truth: the pause map labels roads from RoadDef.name (via
## MapRoads.get_road_names), so a name added here shows up on the map without
## touching any UI code.
##
## Naming rules, so the set reads as one system rather than 19 inventions:
##   - The qualifier is what the road actually CONNECTS or what tier it is.
##     No invented flavour, no unverified geography.
##   - "<X> Link"     two networks joined by an arterial you drive end to end.
##   - "<X> On-Ramp"  leaves a sub-network and merges onto the highway ring.
##   - "<X> Return"   the reverse: leaves the ring for somewhere else.
##   - Loop/Ring/On-Ramp keep the road's shape or role, matching the curated
##     majors that were here first.
## Every id plan() emits MUST appear here. test_all_planned_roads_are_named
## fails loudly when a new corridor is added without one.
##
## coast-a / coast-b are the two arms of the SAME shoreline -- both wrap the same
## side of the sea, so a north/south split would be a fabrication. What actually
## separates them is east/west, and that is what they are named for: measured at
## MASTER_SEED against the sea centre (8200,-3400), coast-a spans x 5620..7745 and
## coast-b spans x 7972..9703 -- disjoint ranges.
const ROAD_NAMES := {
	# -- the seven curated majors (names predate this table; keep them verbatim)
	"hub-ring": "Hub Ring",
	"hub-pass": "Hub Pass Link",
	"pass-loop": "Mountain Pass Loop",
	"highway-ring": "Ring Highway",
	"hub-coast": "Coast Link",
	"touge-a": "Touge A",
	"touge-b": "Touge B",
	# -- links
	"hub-highway-ramp": "Hub On-Ramp",
	# -- touge loops and the shoreline arms
	"coast-a": "West Shore Road",
	"coast-b": "East Shore Road",
	# -- dirt cut-throughs
	"dirt-a": "Dirt Cut A",
	"dirt-b": "Dirt Cut B",
	# -- return connectors (ring -> sub-network)
	"highway-hub-ramp": "Highway Return",
	"highway-pass-ramp": "Pass Return",
	# -- access ramps (sub-network -> ring)
	"pass-highway-ramp": "Pass On-Ramp",
	"coast-highway-ramp": "Coast On-Ramp",
	"touge-highway-ramp": "Touge On-Ramp",
	"spawn-highway-ramp": "Spawn On-Ramp",
	# -- the spawn basin climb
	"hub-access-ramp": "Spawn Basin Ramp",
}

## Applies the canonical name for `def.id` in place. An id with no table entry is
## left with an empty name rather than a fabricated one -- RoadDef
## .display_name() still yields something printable, and the naming test reports
## the omission by id.
static func _apply_name(def: RoadDef) -> void:
	var lookup: Dictionary = ROAD_NAMES
	if lookup.has(def.id):
		def.name = str(lookup[def.id])

const _KILO := 1000.0

## Static entry point of the fixed P2a contract.
##   - master_seed: world hash; every seeded corridor derives from it.
##   - height_provider: optional Callable(Vector2 xz -> float) following the
##     ground_height_provider convention (foliage.gd/prop_scatterer.gd); empty
##     Callable => deterministic flat-Y fallback so headless tests need no
##     Terrain3D.
##   - tier_defaults: optional overrides, e.g. {"km_target": 80.0,
##     "highway_width": 18.0}.
## Returns Array[RoadDef] with the hard road-index invariant:
##   defs[0] = hub ring   (ARTERIAL, closed, w12, 96 samples, y 2.2)
##   defs[1] = hub->pass  (ARTERIAL, open, w10, Catmull-Rom + 10 m arc-length,
##                         Y ramp 2.2 -> loop start y, endpoint == pass loop[0])
##   defs[2] = pass loop  (ARTERIAL, closed, w11, world-offset mountain-pass ring)
## Followed by, in class order: highway perimeter, arterial connectors, touge
## switchback loops into the alpine domes, coastal shoreline ribbons and dirt
## cut-throughs.
static func plan(master_seed: int, height_provider: Callable = Callable(), tier_defaults: Dictionary = {}) -> Array[RoadDef]:
	var _km_target := float(tier_defaults.get("km_target", KM_TARGET))
	var rng := RandomNumberGenerator.new()
	rng.seed = master_seed
	var defs: Array[RoadDef] = []

	# -- Road-index invariant: defs 0..2 (byte-close to world_driver's
	#    bootstrap: hub ring, Catmull-Rom connector, world-offset pass loop).
	#    When the live MountainPassZone data is supplied (world_driver passes
	#    params["zone_road_points"]/params["zone_end"]) use it verbatim so the
	#    runtime equals the scene; otherwise fall back to the deterministic
	#    zone formula anchored at PASS_ZONE_POS.
	var pass_pts: Array[Vector3] = []
	var zone_pts: Array = tier_defaults.get("zone_road_points", [])
	var end := PASS_ZONE_POS
	if zone_pts.size() > 0:
		for p in zone_pts:
			pass_pts.append(p as Vector3)
		end = Vector3(tier_defaults.get("zone_end", pass_pts[0]))
	else:
		pass_pts = _pass_loop_points()
		end = pass_pts[0]
	defs.append(RoadDef.make(RoadDef.Tier.ARTERIAL, _hub_ring_points(), "hub-ring", true, 12.0))
	defs.append(RoadDef.make(RoadDef.Tier.ARTERIAL, _connector_points(end), "hub-pass", false, 10.0))
	defs.append(RoadDef.make(RoadDef.Tier.ARTERIAL, pass_pts, "pass-loop", true, 11.0))

	# -- HIGHWAY: perimeter long-arc circuit around the footprint. Seed-dependent
	#    Y phasing only, so the road-index invariant above stays stable.
	var ring := _highway_ring_points(rng)
	var highway := RoadDef.make(RoadDef.Tier.HIGHWAY, ring, "highway-ring", true,
		_width_for(RoadDef.Tier.HIGHWAY, tier_defaults))
	highway.banking = HIGHWAY_BANKING
	defs.append(highway)

	# -- ARTERIAL connectors: hub<->coast (lands on the coast ribbon) and the
	#    hub<->highway on-ramp (lands on the perimeter ring).
	var coast_a := _coast_ribbon(master_seed, 0)
	var coast_b := _coast_ribbon(master_seed, 1)
	defs.append(RoadDef.make(RoadDef.Tier.ARTERIAL, _coast_arterial(coast_b[0], height_provider), "hub-coast",
		false, _width_for(RoadDef.Tier.ARTERIAL, tier_defaults)))
	defs.append(RoadDef.make(RoadDef.Tier.ARTERIAL, _ramp_arterial(ring), "hub-highway-ramp",
		false, _width_for(RoadDef.Tier.ARTERIAL, tier_defaults)))

	# -- TOUGE: serrated switchback loops climbing the P1 alpine domes (closed).
	var dome_a: Vector2 = TerrainBaker.DOME_FAMILY[0]["center"]
	var dome_b: Vector2 = TerrainBaker.DOME_FAMILY[1]["center"]
	var touge_a := _touge_loop(dome_a, 820.0, master_seed, height_provider)
	var touge_b := _touge_loop(dome_b, 700.0, master_seed + 1, height_provider)
	defs.append(RoadDef.make(RoadDef.Tier.TOUGE, touge_a, "touge-a", true,
		_width_for(RoadDef.Tier.TOUGE, tier_defaults)))
	defs.append(RoadDef.make(RoadDef.Tier.TOUGE, touge_b, "touge-b", true,
		_width_for(RoadDef.Tier.TOUGE, tier_defaults)))

	# -- COASTAL ribbons hugging the P1 sea shoreline (open, dead-end tips).
	defs.append(RoadDef.make(RoadDef.Tier.COASTAL, coast_a, "coast-a", false,
		_width_for(RoadDef.Tier.COASTAL, tier_defaults)))
	defs.append(RoadDef.make(RoadDef.Tier.COASTAL, coast_b, "coast-b", false,
		_width_for(RoadDef.Tier.COASTAL, tier_defaults)))

	# -- DIRT cut-throughs: short, narrow, GRAVEL, crossing between networks.
	defs.append(RoadDef.make(RoadDef.Tier.DIRT, _dirt_cut(ring, 0), "dirt-a", false,
		_width_for(RoadDef.Tier.DIRT, tier_defaults)))
	defs.append(RoadDef.make(RoadDef.Tier.DIRT, _dirt_cut(ring, 1), "dirt-b", false,
		_width_for(RoadDef.Tier.DIRT, tier_defaults)))

	# -- RETURN CONNECTORS: highway ring back to hub/pass so you can reach the middle
	# Highway -> hub ring (reverse of spawn-highway-ramp)
	defs.append(RoadDef.make(RoadDef.Tier.ARTERIAL,
		_highway_to_hub_ramp(ring, 110),
		"highway-hub-ramp", false, _width_for(RoadDef.Tier.ARTERIAL, tier_defaults)))
	# Highway -> pass loop (reverse of pass-highway-ramp)
	defs.append(RoadDef.make(RoadDef.Tier.ARTERIAL,
		_highway_to_pass_ramp(ring, 65, pass_pts[12]),
		"highway-pass-ramp", false, _width_for(RoadDef.Tier.ARTERIAL, tier_defaults)))

	# -- ACCESS RAMPS (interchange): open paved spurs from the pass loop, the
	#    coast ribbon and the touge loop straight onto the perimeter highway
	#    ring, so every zone can merge onto the 24 m highway without backtracking
	#    through the hub. Each lands flush on a fixed ring anchor (XZ-identical
	#    vertex, Y from the ring point) so RoadGraph registers a zero-distance
	#    junction, exactly like the hub on-ramp (defs[5]) and dirt cuts.
	#    Each also runs its merge lane PARALLEL to the ring, so the side facing
	#    the carriageway is a wall across the join: every access ramp keeps BOTH
	#    rails and instead suppresses the carriageway-facing side PER INDEX over
	#    the alongside stretch (_with_merge_rail_open), which is the only way to
	#    stay open at both the approach and the merge lane.
	defs.append(_with_merge_rail_open(RoadDef.make(RoadDef.Tier.ARTERIAL,
		_access_ramp(pass_pts[12], ring, 65, Vector2(0.0, 350.0)),
		"pass-highway-ramp", false, _width_for(RoadDef.Tier.ARTERIAL, tier_defaults)), ring))
	defs.append(_with_merge_rail_open(RoadDef.make(RoadDef.Tier.ARTERIAL,
		_access_ramp(coast_b[0], ring, 174, Vector2(-320.0, 220.0)),
		"coast-highway-ramp", false, _width_for(RoadDef.Tier.ARTERIAL, tier_defaults)), ring))
	# Descent off a massif dome: alpine TOUGE tier (driveable ceiling 300, still
	# asphalt) because the taper from the touge-loop altitude to the ring's ~22 m
	# would exceed the ARTERIAL 120 m band.
	defs.append(_with_merge_rail_open(RoadDef.make(RoadDef.Tier.TOUGE,
		_access_ramp(touge_a[0], ring, 24, Vector2(-258.0, 153.0)),
		"touge-highway-ramp", false, _width_for(RoadDef.Tier.TOUGE, tier_defaults)), ring))
	# The spawn ramp runs the LONGEST merge lane: it comes off the hub basin and
	# then parallels the ring for an extra SPAWN_MERGE_RUN_M before its taper
	# starts, so the player gets a full on-ramp's worth of ring grade to build
	# speed on instead of dropping straight into a 1.5 km taper.
	defs.append(_with_merge_rail_open(RoadDef.make(RoadDef.Tier.ARTERIAL,
		_access_ramp(Vector3(128.0, 2.2, 128.0), ring, 96, Vector2(60.0, -16.0), SPAWN_MERGE_RUN_M),
		"spawn-highway-ramp", false, _width_for(RoadDef.Tier.ARTERIAL, tier_defaults)), ring))

	# -- HUB ACCESS RAMP: climbs out of the spawn basin at a low crown Y (-0.1),
	# 46 m out from the hub centre (clear of the r40 spawn plateau), and lands
	# FLUSH on the hub ring's north point (ring 72 = 128, 18) at the ring's own
	# Y 2.2, so RoadGraph registers a real zero-distance hub-ring junction. The
	# ramp is wired as a merge point, so the receiving hub ring clears its rail
	# across that junction and the ramp side carries no rails at all.
	var hub_access_start := Vector3(128.0, -0.1, 81.8)
	var hub_access_end := _hub_ring_point_at(72)
	var hub_access_mid := Vector3(128.0, 0.0, 49.9)
	var hub_access_control: Array[Vector3] = [hub_access_start, hub_access_mid, hub_access_end]
	defs.append(RoadDef.make(RoadDef.Tier.ARTERIAL,
		_open_chain(hub_access_control),
		"hub-access-ramp", false, _width_for(RoadDef.Tier.ARTERIAL, tier_defaults)))
	# Names are applied in ONE pass here rather than at 19 call sites: the table
	# stays the only place a name is written, and a corridor appended above
	# without one is reported by id instead of silently rendering blank.
	_align_shared_spawn_anchor(defs)
	for def in defs:
		_apply_name(def)
	return defs

## Over the last RETURN_ANCHOR_MATCH_M of `highway-hub-ramp` before it reaches
## the spawn anchor, blend its Y onto `spawn-highway-ramp`'s.
##
## Both roads share the anchor (128, 2.2, 128) and leave/arrive it within a few
## degrees of each other, so for the first ~70 m their 10 m-wide roadbeds
## OVERLAP in plan view -- measured centreline separation 1.97 m per 12 m step,
## well inside the 10.5 m overlap threshold. They did not agree in Y there: the
## return ramp descends from the ring at ~3.8% while the spawn ramp leaves at
## ~1.75%, so the return ramp's mesh floated up to 1.22 m ABOVE the spawn ramp's
## carriageway. That higher mesh is a step lying across the on-ramp's left half
## right where the player starts driving, and the conformed terrain bridges to it,
## so it is what strands a car leaving the spawn.
##
## Note the fix is on the HIGHER road: spawn-highway-ramp is already the lower of
## the pair at every shared point, so lowering IT would only widen the step.
## Blending by arc length measured back from the shared anchor (rather than by
## index) keeps the two profiles registered regardless of how many points each
## resampling step produced.
const RETURN_ANCHOR_MATCH_M := 165.0
## Arc length over which the two roadbeds are genuinely on top of each other.
## The centreline separation grows 1.97 m per 12 m step out of the shared anchor,
## so the 10.5 m overlap threshold is crossed at ~64 m; 75 m covers it with
## margin. The weight is held at a flat 1.0 across this stretch -- the roadbeds
## are literally the same surface here, so any residual is a step you can see and
## snag a wheel on -- and only then eased back to 0 so the return ramp recovers
## its own steeper descent without a kink.
const RETURN_ANCHOR_FLUSH_M := 75.0

static func _align_shared_spawn_anchor(defs: Array[RoadDef]) -> void:
	var ret := _def_by_id(defs, "highway-hub-ramp")
	var spawn := _def_by_id(defs, "spawn-highway-ramp")
	if ret == null or spawn == null:
		return
	var spawn_ref := _arc_from_anchor(spawn.points, false)
	if spawn_ref.is_empty():
		return
	var n := ret.points.size()
	var dists := _arc_from_anchor(ret.points, true)
	for i in n:
		var s: float = dists[i]
		if s <= 0.0 or s >= RETURN_ANCHOR_MATCH_M:
			continue
		var w := 1.0
		if s > RETURN_ANCHOR_FLUSH_M:
			w = 1.0 - (s - RETURN_ANCHOR_FLUSH_M) / (RETURN_ANCHOR_MATCH_M - RETURN_ANCHOR_FLUSH_M)
		var target := _y_at_arc(spawn_ref, spawn.points, s)
		if is_nan(target):
			continue
		var p: Vector3 = ret.points[i]
		p.y = lerpf(p.y, target, w)
		ret.points[i] = p

## Cumulative 3D arc length for every point, measured from the END of the chain
## when `from_end`, otherwise from the start. Returns [] for a chain too short to
## sample.
static func _arc_from_anchor(points: Array[Vector3], from_end: bool) -> Array[float]:
	var n := points.size()
	var out: Array[float] = []
	if n < 2:
		return out
	out.resize(n)
	out[0] = 0.0
	for i in range(1, n):
		out[i] = out[i - 1] + points[i].distance_to(points[i - 1])
	if not from_end:
		return out
	var total: float = out[n - 1]
	for i in n:
		out[i] = total - out[i]
	return out

## Y at a given arc distance along a chain whose arc lengths were measured from
## its START (the spawn ramp leaves the anchor, so its table is forward). NaN when
## `s` falls outside the chain.
static func _y_at_arc(arcs: Array[float], points: Array[Vector3], s: float) -> float:
	var n := points.size()
	if n < 2 or s < 0.0 or s > float(arcs[n - 1]):
		return NAN
	for i in range(1, n):
		if s <= float(arcs[i]):
			var span := float(arcs[i]) - float(arcs[i - 1])
			var t := 0.0 if span <= 0.0 else (s - float(arcs[i - 1])) / span
			return lerpf(points[i - 1].y, points[i].y, t)
	return points[n - 1].y

static func _def_by_id(defs: Array[RoadDef], id: String) -> RoadDef:
	for d in defs:
		if d.id == id:
			return d
	return null

## Drivable length of a corridor in metres (sum of 3D segment lengths).
static func chain_length_m(points: Array[Vector3]) -> float:
	var total := 0.0
	for i in points.size():
		if i > 0:
			total += points[i - 1].distance_to(points[i])
	return total

## Deterministic, overflow-safe content hash of a corridor chain. Used by the
## seeding tests to prove same-seed reproducibility and cross-seed divergence.
static func chain_hash(points: Array[Vector3]) -> int:
	var h := 0
	for p in points:
		h += int(p.x * 10.0) * 1009 + int(p.y * 10.0) * 1013 + int(p.z * 10.0) * 1019
	return h

# ---------------------------------------------------------------------------
# Road-index invariant builders (byte-close to world_driver.gd's bootstrap).
# ---------------------------------------------------------------------------

## Hub festival ring: 96 samples, centered (128,128), radius 110, Y 2.2.
static func _hub_ring_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for i in 96:
		var ang := TAU * float(i) / 96.0
		pts.append(Vector3(128.0 + cos(ang) * 110.0, 2.2, 128.0 + sin(ang) * 110.0))
	return pts

## Hub ring point i (0..96), for junction anchors.
static func _hub_ring_point_at(idx: int) -> Vector3:
	var ang := TAU * float(idx % 96) / 96.0
	return Vector3(128.0 + cos(ang) * 110.0, 2.2, 128.0 + sin(ang) * 110.0)

## Mountain-pass loop as emitted by MountainPassZone (mountain_pass.gd
## _generate_road_points) world-offset by the zone anchor (3800,14,3200):
## 36 points, radius 54..78, Y 8..16 local, XZ x-scale 0.8. Its first point is
## the connector's endpoint (the "pass start").
static func _pass_loop_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for i in 36:
		var t := float(i) / 36.0
		var ang := TAU * t
		var r := 54.0 + 24.0 * sin(ang * 2.0 + 0.7)
		pts.append(Vector3(
			PASS_ZONE_POS.x + cos(ang) * r,
			PASS_ZONE_POS.y + 8.0 * sin(ang + 1.4) + 3.0 * sin(ang * 3.0),
			PASS_ZONE_POS.z + sin(ang) * r * 0.8))
	return pts

## Hub(238,128) -> pass-loop start connector: Catmull-Rom XZ through the four
## control points, dense-sampled 96, then 10 m arc-length resample with Y
## ramp 2.2 -> end.y exactly like world_driver.gd:_pass_connector.
static func _connector_points(end: Vector3) -> Array[Vector3]:
	var control: Array[Vector3] = [
		Vector3(238.0, 0.0, 128.0),
		Vector3(1500.0, 0.0, 128.0),
		Vector3(3200.0, 0.0, 1800.0),
		end,
	]
	var chain := PackedVector3Array()
	const DENSE := 96
	for i in DENSE + 1:
		chain.append(Spline.catmull_rom_xz(control, float(i) / float(DENSE)))
	chain[DENSE] = end
	return Spline.resample_by_arc(chain, 10.0, 2.2, end)

# ---------------------------------------------------------------------------
# New-class builders.
# ---------------------------------------------------------------------------

## The perimeter highway's footprint. Shared by the ring builder and by every
## access-ramp measurement (merge side, keep-out clearance, rail side) so the
## ramp logic can never measure against a different ellipse than the one the
## ring was sampled from.
const RING_CENTER := Vector2(4400.0, 2250.0)
const RING_AXIS_X := 4600.0
const RING_AXIS_Z := 3550.0

## Which side of the highway ring an access ramp's merge lane is held on:
## -1.0 when `source` sits INSIDE the ellipse, +1.0 when it sits outside.
## Resolved RELATIVE TO THE SOURCE, not "away from the ring centre": a ramp
## whose source is inside (the pass loop) has to run its lane on the inside,
## otherwise its approach would have to cross the carriageway to reach it. A
## source outside (coast / touge / spawn) keeps the lane outside. This is the
## single test every access-ramp side decision is made from, so the lane, the
## keep-out and the rail mask can never disagree about which side they are on.
static func _merge_side_for(source: Vector3) -> float:
	var src_nx := (source.x - RING_CENTER.x) / RING_AXIS_X
	var src_nz := (source.z - RING_CENTER.y) / RING_AXIS_Z
	return -1.0 if (src_nx * src_nx + src_nz * src_nz) < 1.0 else 1.0

## How close (in XZ, metres) a ramp point must be to the ring centreline before
## it counts as running ALONGSIDE the carriageway, and therefore before the rail
## on the ring-facing side has to go. Measured on the shipped plan: the
## alongside stretch sits 17-24 m out (that is MERGE_CLEARANCE plus the taper),
## while the first point clear of the carriageway is 63 m away and the ramp
## source is 440 m away. 40 m therefore separates the two populations with a wide
## margin on both sides, so this does not depend on a knife-edge threshold.
const MERGE_BAND_M := 40.0

## XZ projection of `p` onto the ring polyline: {"d": distance to the
## centreline, "x"/"z": the projected point}. Brute force over the ring's 192
## vertices; the planner already does comparable per-point ring work to build the
## ramp, and this runs once per ramp at plan time, not per frame.
static func _ring_station(ring: Array[Vector3], p: Vector3) -> Dictionary:
	var best_d := INF
	var best_x := 0.0
	var best_z := 0.0
	var n := ring.size()
	for i in n:
		var a := ring[i]
		var b := ring[(i + 1) % n]
		var dx := b.x - a.x
		var dz := b.z - a.z
		var len2 := dx * dx + dz * dz
		var t := 0.0 if len2 <= 0.0 else clampf(((p.x - a.x) * dx + (p.z - a.z) * dz) / len2, 0.0, 1.0)
		var qx := a.x + dx * t
		var qz := a.z + dz * t
		var d := Vector2(qx - p.x, qz - p.z).length()
		if d < best_d:
			best_d = d
			best_x = qx
			best_z = qz
	return {"d": best_d, "x": best_x, "z": best_z}

## The raw geometric answer: which side the ring lies on at chain index `i`, or
## NONE when this point is not alongside the ring, or when the question is
## undefined -- a point sitting exactly ON the carriageway has no direction to
## it. Travel order matches TrackBuilder exactly: right = forward x UP, which in
## XZ is (-forward.z, forward.x).
static func _ring_facing_side(points: Array[Vector3], i: int, ring: Array[Vector3]) -> int:
	var n := points.size()
	if n < 2 or i < 0 or i >= n:
		return RoadDef.RailSide.NONE
	var st := _ring_station(ring, points[i])
	if float(st["d"]) > MERGE_BAND_M:
		return RoadDef.RailSide.NONE
	var prev := points[maxi(i - 1, 0)]
	var next := points[mini(i + 1, n - 1)]
	var fwd := Vector2(next.x - prev.x, next.z - prev.z)
	if fwd.length_squared() < 0.000001:
		return RoadDef.RailSide.NONE
	fwd = fwd.normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var to_ring := Vector2(float(st["x"]) - points[i].x, float(st["z"]) - points[i].z)
	if to_ring.length_squared() < 0.000001:
		return RoadDef.RailSide.NONE
	to_ring = to_ring.normalized()
	return RoadDef.RailSide.RIGHT if right.dot(to_ring) > 0.0 else RoadDef.RailSide.LEFT

## The open side at chain index `i`, resolving the undeterminable case by looking
## BACK a few indices for the last alongside point that did answer.
##
## This matters at the landing: a ramp lands ON a ring vertex, so its final point
## is at distance ~0 and the direction to the ring is undefined. Returning NONE
## there would leave a rail stub sitting exactly across the merge the whole
## suppression exists to open. The merge continues in the same sense as the
## approach, so the nearest determinable neighbour is the right answer.
static func _open_rail_side_at(points: Array[Vector3], i: int, ring: Array[Vector3]) -> int:
	var direct := _ring_facing_side(points, i, ring)
	if direct != RoadDef.RailSide.NONE:
		return direct
	# Only inherit when THIS point is genuinely alongside (the merge lane reaches
	# the carriageway), never when it has simply left the band.
	if float(_ring_station(ring, points[i])["d"]) > MERGE_BAND_M:
		return RoadDef.RailSide.NONE
	for j in range(i - 1, maxi(i - 5, -1), -1):
		var inherited := _ring_facing_side(points, j, ring)
		if inherited != RoadDef.RailSide.NONE:
			return inherited
	return RoadDef.RailSide.NONE

## Per-index rail suppression for an access ramp: over every stretch that runs
## alongside the carriageway, open whichever side actually faces the ring. The
## road keeps BOTH rails everywhere else, so the field side is always guarded.
## Adjacent indices with the same open side collapse into one range.
static func _access_rail_open_ranges(points: Array[Vector3], ring: Array[Vector3]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := points.size()
	var run_from := -1
	var run_side := RoadDef.RailSide.NONE
	for i in n:
		var side := _open_rail_side_at(points, i, ring)
		if side != run_side:
			if run_side != RoadDef.RailSide.NONE and run_from >= 0:
				out.append({"from": run_from, "to": i - 1, "side": run_side})
			run_side = side
			run_from = i if side != RoadDef.RailSide.NONE else -1
	if run_side != RoadDef.RailSide.NONE and run_from >= 0:
		out.append({"from": run_from, "to": n - 1, "side": run_side})
	return out

## Give an access ramp both rails plus the per-index suppression ranges that open
## whichever side faces the carriageway. Keeping `rail_sides` at BOTH (rather than
## masking one side off for the whole road) is what lets the field side stay
## railed along the ENTIRE ramp while the carriageway side is open everywhere it
## actually runs alongside the highway -- including the merge lane, where the
## carriageway is on the opposite side to the approach.
static func _with_merge_rail_open(def: RoadDef, ring: Array[Vector3]) -> RoadDef:
	def.rail_sides = RoadDef.RailSide.BOTH
	def.rail_open_ranges = _access_rail_open_ranges(def.points, ring)
	return def

## Unit XZ vector pointing away from the ring centre at ring vertex `idx`. The
## ring is an ellipse sampled by parametric angle, so this is exact for it.
static func _ring_outward(ring: Array[Vector3], idx: int) -> Vector2:
	var rp2d := Vector2(ring[idx].x, ring[idx].z)
	var to_center := RING_CENTER - rp2d
	if to_center.length_squared() > 0.0001:
		return -to_center.normalized()
	var ang := TAU * float(idx) / float(ring.size())
	return Vector2(cos(ang), sin(ang))

## Perimeter highway: a closed long-arc ellipse around the footprint
## (hub+pass inside, the P1 alpine domes outside, and keeping > 400 m clear of
## the P1 sea interior). Y is a gentle two-cycle bank (22 +/- 16) so the ring
## never drops below the driveable band. Seed-dependent Y phasing only.
static func _highway_ring_points(rng: RandomNumberGenerator) -> Array[Vector3]:
	const CENTER := RING_CENTER
	const AXIS_X := RING_AXIS_X
	const AXIS_Z := RING_AXIS_Z
	const N := 192
	var phase := rng.randf_range(0.0, TAU)
	var pts: Array[Vector3] = []
	for i in N:
		var ang := TAU * float(i) / float(N)
		pts.append(Vector3(
			CENTER.x + cos(ang) * AXIS_X,
			22.0 + 16.0 * sin(ang * 2.0 + 1.1 + phase),
			CENTER.y + sin(ang) * AXIS_Z))
	return pts

## Open Catmull-Rom chain through `control` with a 12 m arc-length resample and
## a linear Y ramp from control[0].y to the final control's y (the endpoint is
## appended exactly, so junction anchors land flush).
static func _open_chain(control: Array[Vector3]) -> Array[Vector3]:
	var chain := PackedVector3Array()
	const DENSE := 96
	for i in DENSE + 1:
		chain.append(Spline.catmull_rom_xz(control, float(i) / float(DENSE)))
	var last: Vector3 = control[control.size() - 1]
	chain[DENSE] = last
	return Spline.resample_by_arc(chain, 12.0, control[0].y, last)

## hub ring point 60 -> the coast-b shoreline start, approached from LAND over
## the north shore (controls sit >= 2700 m from the sea centre and the final
## chord stays >= 2400 m, so the arterial never carves through the P1 sea
## interior). Lands flush on the ribbon start so the arterial and the coastal
## network form a real junction.
static func _coast_arterial(coast_start: Vector3, height_provider: Callable) -> Array[Vector3]:
	var hub_start := _hub_ring_point_at(60)
	var end_y := coast_start.y
	var end := coast_start
	if height_provider.is_valid():
		end_y = clampf(float(height_provider.call(Vector2(coast_start.x, coast_start.z))), -8.0, 120.0)
		end = Vector3(coast_start.x, end_y, coast_start.z)
	var control: Array[Vector3] = [
		hub_start,
		Vector3(2400.0, 0.0, 400.0),
		Vector3(5500.0, 0.0, 500.0),
		Vector3(8200.0, 0.0, -400.0),
		end,
	]
	return _open_chain(control)

## hub ring point 24 -> perimeter ring point 160 (the hub's highway on-ramp).
static func _ramp_arterial(ring: Array[Vector3]) -> Array[Vector3]:
	var hub_start := _hub_ring_point_at(24)
	var ring_end := ring[160]
	var mid := Vector3(
		(hub_start.x + ring_end.x) * 0.5,
		0.0,
		(hub_start.z + ring_end.z) * 0.5 + 400.0)
	var control: Array[Vector3] = [
		hub_start,
		mid,
		Vector3(ring_end.x, ring_end.y, ring_end.z),
	]
	return _open_chain(control)

## Interchange access ramp: a from-point on a sub-network (pass loop / coast
## ribbon / touge loop) to a fixed highway ring anchor. The ramp builds a
## merge/acceleration lane that runs PARALLEL alongside the highway ring (at
## the ring's Y, offset off the carriageway by MERGE_CLEARANCE or more),
## tapering in so the ramp lands flush on ring[ring_idx] from the side — never
## passing under the roadbed. The lane and the whole approach are held on the
## source's side of the ring ellipse, so no access road ever crosses the
## highway: an inside source (pass) keeps the lane inside, an outside source
## (coast / touge / spawn) keeps it outside.
## The endpoint is the ring point verbatim (XZ and Y) so RoadGraph registers
## the ramp<->ring junction at zero distance.
## `runner_extra_m` grows the parallel merge lane further back along the ring
## before the taper starts, for a ramp that needs a longer run beside the
## highway; 0.0 leaves the geometry below byte-identical.
static func _access_ramp(source: Vector3, ring: Array[Vector3], ring_idx: int, bulge: Vector2, \
		runner_extra_m: float = 0.0) -> Array[Vector3]:
	var ring_end := ring[ring_idx]
	var N := ring.size()
	
	# Build the merge runner: the 14 ring points immediately PRECEDING ring_idx,
	# each offset off the ring by a taper that starts at TAPER_START and shrinks
	# to 0 at ring[ring_idx]. Ring vertices are ~134 m apart (N=192 on the
	# 4600x3550 ellipse), so this parallels the highway for ~1.9 km.
	# The side is _merge_side_for(source) (see there): the lane is held on the
	# source's own side of the ring, so no access road ever crosses the
	# carriageway. TAPER_START exceeds MERGE_CLEARANCE so the two roadbeds never
	# overlap: the ring is 24 m wide (12 m half) and this ramp 10 m (5 m half).
	const RUNNER_COUNT := 14
	const TAPER_START := 24.0
	const MERGE_CLEARANCE := 17.0
	# Belt-and-braces bound on the extra-run walk below. The walk always either
	# consumes metres or breaks, but a planner that could spin forever would hang
	# every test that plans a corridor, so it is capped as well.
	const MAX_EXTRA_STEPS := 64
	var runner_pts: Array[Vector3] = []
	var runner_ys: Array[float] = []
	var ring_center := RING_CENTER

	var merge_side := _merge_side_for(source)
	
	for k in range(RUNNER_COUNT, -1, -1):
		var idx := (ring_idx - k) % N
		if idx < 0:
			idx += N
		var rp := ring[idx]
		var outward := _ring_outward(ring, idx)
		var taper := TAPER_START * float(k) / float(RUNNER_COUNT) * merge_side
		runner_pts.append(Vector3(rp.x + outward.x * taper, rp.y, rp.z + outward.y * taper))
		runner_ys.append(rp.y)
	
	# Extra parallel run: keep walking BACK along the ring from the runner's
	# outer end, holding the offset at TAPER_START, until runner_extra_m of XZ
	# arc is used up. The ring is CLOSED, so the walk simply continues past
	# ring[ring_idx - RUNNER_COUNT]; the taper above and the landing are
	# untouched, and because every existing taper is TAPER_START * k/14 the
	# series just gains a constant-offset prefix. The last step is usually a
	# PARTIAL ring segment, so the lane gains exactly runner_extra_m of length
	# instead of rounding up to a whole vertex.
	var extra_pts: Array[Vector3] = []
	var extra_ys: Array[float] = []
	var extra_idx := (ring_idx - RUNNER_COUNT) % N
	if extra_idx < 0:
		extra_idx += N
	var extra_left := runner_extra_m
	var extra_steps := 0
	while extra_left > 0.0 and extra_steps < MAX_EXTRA_STEPS:
		extra_steps += 1
		var prev_idx := (extra_idx - 1 + N) % N
		var a := ring[extra_idx]
		var b := ring[prev_idx]
		var seg_xz := Vector2(b.x - a.x, b.z - a.z).length()
		if seg_xz <= 0.0:
			break
		var t := 1.0 if seg_xz <= extra_left else extra_left / seg_xz
		# Interpolate the ring position (XZ AND Y, so the lane stays at ring
		# grade across the partial step) then push it off the ring by the same
		# outward radial the taper uses, at this vertex's angle.
		var rp := a.lerp(b, t)
		var outward := _ring_outward(ring, extra_idx)
		var offset := TAPER_START * merge_side
		extra_pts.append(Vector3(rp.x + outward.x * offset, rp.y, rp.z + outward.y * offset))
		extra_ys.append(rp.y)
		extra_idx = prev_idx
		extra_left -= minf(seg_xz, extra_left)
	
	if not extra_pts.is_empty():
		# Collected innermost-first; the lane travels outward-to-inward, so flip.
		extra_pts.reverse()
		extra_ys.reverse()
		var merged_pts: Array[Vector3] = []
		var merged_ys: Array[float] = []
		merged_pts.append_array(extra_pts)
		merged_pts.append_array(runner_pts)
		merged_ys.append_array(extra_ys)
		merged_ys.append_array(runner_ys)
		runner_pts = merged_pts
		runner_ys = merged_ys
	
	# Build the approach control points: source -> bulged mid -> runner[0]
	# The bulge is tuned per ramp; the keep-out below then holds the resampled
	# chain on the source's side of the highway ellipse.
	var approach_mid := Vector3(
		(source.x + runner_pts[0].x) * 0.5 + bulge.x,
		0.0,
		(source.z + runner_pts[0].z) * 0.5 + bulge.y)
	var approach_control: Array[Vector3] = [
		Vector3(source.x, source.y, source.z),
		approach_mid,
		Vector3(runner_pts[0].x, runner_pts[0].y, runner_pts[0].z),
	]
	
	# Dense-sample the approach XZ via Catmull-Rom, then resample by arc (XZ only).
	var approach_chain := PackedVector3Array()
	const DENSE := 96
	for i in DENSE + 1:
		approach_chain.append(Spline.catmull_rom_xz(approach_control, float(i) / float(DENSE)))
	approach_chain[DENSE] = Vector3(runner_pts[0].x, 0.0, runner_pts[0].z)
	var approach_resampled := Spline.resample_by_arc(approach_chain, 12.0, 0.0, Vector3(runner_pts[0].x, 0.0, runner_pts[0].z))
	
	# Snap the resampled approach's last point exactly onto runner_pts[0] — the
	# outer end of the merge lane, offset TAPER_START off the ring. Overwriting
	# rather than appending: resample_by_arc can stop a fraction of a metre
	# short, and appending the exact point would leave a sub-metre segment
	# between the two.
	if approach_resampled.size() > 0:
		approach_resampled[approach_resampled.size() - 1] = Vector3(runner_pts[0].x, 0.0, runner_pts[0].z)
	
	# Keep the whole approach on the source's side of the highway ellipse, so an
	# access road can never cut across the ring's carriageway. For each resampled
	# point past the source, measure the SIGNED distance to the ring ellipse
	# along that point's own ray: positive outside, negative inside. The
	# requirement is MERGE_CLEARANCE at the source, growing linearly to
	# TAPER_START where the approach meets the merge lane, so the lane and the
	# approach meet at the same offset. A point short of the requirement slides
	# along its own ray onto the required locus, so the chain keeps its shape
	# instead of being shoved sideways. Index 0 is the source and stays
	# untouched: its junction with the sub-network is a hard anchor.
	var approach_len := approach_resampled.size()
	for i in range(1, approach_len):
		var p := approach_resampled[i]
		var radial := Vector2(p.x, p.z) - ring_center
		var radial_len := radial.length()
		if radial_len < 0.0001:
			continue
		var ray := radial / radial_len
		# Distance from the ring centre to the ellipse locus along this ray.
		var locus := 1.0 / sqrt(pow(ray.x / RING_AXIS_X, 2.0) + pow(ray.y / RING_AXIS_Z, 2.0))
		var signed_off := radial_len - locus
		var required := maxf(MERGE_CLEARANCE, TAPER_START * float(i + 1) / float(approach_len))
		if merge_side * signed_off < required:
			var want := locus + merge_side * required
			approach_resampled[i] = Vector3(
				ring_center.x + ray.x * want,
				0.0,
				ring_center.y + ray.y * want)
	
	# Now build the full XZ path: approach_resampled + runner_pts[1..]
	var full_xz: Array[Vector3] = []
	for p in approach_resampled:
		full_xz.append(Vector3(p.x, 0.0, p.z))
	for i in range(1, runner_pts.size()):
		full_xz.append(Vector3(runner_pts[i].x, 0.0, runner_pts[i].z))
	
	# Build Y array matching full_xz:
	# - approach segment: climb to ring Y. A ramp whose source is INSIDE the
	#   highway ring ellipse (pass) climbs AGGRESSIVE (1/3 of the approach) then
	#   holds at ring Y. A source OUTSIDE (coast, touge, spawn) uses the gradual
	#   halfway climb, which preserves the 3D adjacency geometry with the hub ramps.
	# - runner segment: runner_ys[1..] (already at ring Y)
	var full_ys: Array[float] = []
	var highway_base_y: float = 22.0
	var min_ring_y: float = INF
	for y in runner_ys:
		if y < min_ring_y:
			min_ring_y = y
	var climb_target_y: float = maxf(highway_base_y, runner_ys[0])
	var min_allowed_y: float = min_ring_y - 1.0
	var merge_zone_len: int = 16
	if approach_len < 16:
		merge_zone_len = approach_len
	var climb_end_idx := maxi(approach_len / 3, 1) if merge_side < 0.0 else maxi(approach_len / 2, 1)
	var use_aggressive := merge_side < 0.0
	for i in range(approach_len):
		if use_aggressive:
			if i <= climb_end_idx:
				var t := float(i) / float(climb_end_idx)
				var y := lerpf(source.y, climb_target_y, t)
				if i >= approach_len - merge_zone_len:
					y = maxf(y, min_allowed_y)
				full_ys.append(y)
			else:
				var y := climb_target_y
				if i >= approach_len - merge_zone_len:
					y = maxf(y, min_allowed_y)
				full_ys.append(y)
		else:
			# Original gradual climb profile (halfway)
			var halfway: int = maxi(approach_len / 2, 1)
			if i <= halfway:
				var t := float(i) / float(halfway)
				var y := lerpf(source.y, climb_target_y, t)
				if i >= approach_len - merge_zone_len:
					y = maxf(y, min_allowed_y)
				full_ys.append(y)
			else:
				var t := float(i - halfway) / float(maxi(approach_len - halfway - 1, 1))
				var y := lerpf(climb_target_y, runner_ys[0], t)
				if i >= approach_len - merge_zone_len:
					y = maxf(y, min_allowed_y)
				full_ys.append(y)
	for i in range(1, runner_ys.size()):
		full_ys.append(runner_ys[i])
	
	# Combine XZ + Y into final chain
	var final_chain: Array[Vector3] = []
	for i in range(full_xz.size()):
		var y_val := full_ys[i] if i < full_ys.size() else runner_ys[-1]
		final_chain.append(Vector3(full_xz[i].x, y_val, full_xz[i].z))
	
	# Ensure exact endpoint match (zero-distance junction)
	final_chain[final_chain.size() - 1] = ring_end
	return final_chain

## Return connector: highway ring -> hub ring (reverse of spawn-highway-ramp).
## Starts at ring[ring_idx] and runs straight to hub center (128, 128) at Y 2.2.
static func _highway_to_hub_ramp(ring: Array[Vector3], ring_idx: int) -> Array[Vector3]:
	var start := ring[ring_idx]
	var end := Vector3(128.0, 2.2, 128.0)
	var mid := Vector3(
		(start.x + end.x) * 0.5,
		(start.y + end.y) * 0.5,
		(start.z + end.z) * 0.5)
	var control: Array[Vector3] = [start, mid, end]
	return _open_chain(control)

## Return connector: highway ring -> pass loop (reverse of pass-highway-ramp).
## Starts at ring[ring_idx] and runs to pass_start (on pass loop).
static func _highway_to_pass_ramp(ring: Array[Vector3], ring_idx: int, pass_start: Vector3) -> Array[Vector3]:
	var start := ring[ring_idx]
	var end := pass_start
	var mid := Vector3(
		(start.x + end.x) * 0.5,
		(start.y + end.y) * 0.5,
		(start.z + end.z) * 0.5)
	var control: Array[Vector3] = [start, mid, end]
	return _open_chain(control)

## Touge loop: a serrated closed circuit over an alpine dome. 36 base points on
## a radius ring with a two-cycle Y profile (115 +/- 85, always driveable and
## <= 300), folded into hairpin switchbacks by hairpin_fold (slope budget) and
## closed back onto the first point. With a height_provider the Ys are instead
## sampled from the terrain (clamped to the touge ceiling).
static func _touge_loop(center: Vector2, radius: float, fold_seed: int, height_provider: Callable) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var n := 36
	for i in n:
		var ang := TAU * float(i) / float(n)
		var p := Vector3(
			center.x + cos(ang) * radius,
			115.0 + 85.0 * sin(ang * 2.0 + 1.4),
			center.y + sin(ang) * radius * 1.15)
		if height_provider.is_valid():
			p.y = clampf(float(height_provider.call(Vector2(p.x, p.z))), 20.0, 300.0)
		pts.append(p)
	var folded := Spline.hairpin_fold(pts, 420.0, 0.18, 28.0, fold_seed)
	folded.append(pts[0])
	return folded

## Coastal ribbon: an open chain of shoreline-hugging points over a sweep of
## angles around the P1 sea center, re-expressed through Spline.coast_hug so
## every point stays inside a small tolerance band of the shoreline. Both tips
## are open dead-ends / overlooks (no phantom closing chord). The arcs sit on
## the NORTH rim (variant 0: 100-170°) and the EAST-NORTH rim (variant 1:
## 55-95°) so the neighbour arterial lands on the 55° start over dry land.
static func _coast_ribbon(base_seed: int, variant: int) -> Array[Vector3]:
	var sea: Vector2 = TerrainBaker.BIOME_SEA_CENTER
	var r: float = TerrainBaker.BIOME_SEA_RADIUS
	var lo := deg_to_rad(100.0) if variant == 0 else deg_to_rad(55.0)
	var hi := deg_to_rad(170.0) if variant == 0 else deg_to_rad(95.0)
	var steps := 26
	var pts: Array[Vector3] = []
	for i in steps:
		var u := float(i) / float(maxi(steps - 1, 1))
		var ang := lerpf(lo, hi, u)
		pts.append(Vector3(sea.x + cos(ang) * (r + 20.0), 4.0, sea.y + sin(ang) * (r + 20.0)))
	return Spline.coast_hug(pts, sea, r + 6.0, 26.0, 6.0, base_seed * 31 + variant * 17)

## Dirt cut-through: a short open gravel cross-country chain from a hub ring
## point across to a perimeter ring point (two networks otherwise far apart).
static func _dirt_cut(ring: Array[Vector3], variant: int) -> Array[Vector3]:
	var a_idx := 16 if variant == 0 else 64
	var b_idx := 140 if variant == 0 else 112
	var a := _hub_ring_point_at(a_idx)
	var b := ring[b_idx]
	var mid := Vector3(
		(a.x + b.x) * 0.5 + 320.0,
		0.0,
		(a.z + b.z) * 0.5 - 240.0)
	var control: Array[Vector3] = [
		Vector3(a.x, a.y, a.z),
		mid,
		Vector3(b.x, b.y, b.z),
	]
	return _open_chain(control)

## Tier width: explicit tier_defaults override else RoadDef's tier default.
static func _width_for(tier: int, tier_defaults: Dictionary) -> float:
	var keys := {
		RoadDef.Tier.HIGHWAY: "highway_width",
		RoadDef.Tier.ARTERIAL: "arterial_width",
		RoadDef.Tier.TOUGE: "touge_width",
		RoadDef.Tier.COASTAL: "coastal_width",
		RoadDef.Tier.DIRT: "dirt_width",
	}
	return float(tier_defaults.get(keys[tier], RoadDef.default_width(tier)))