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
	return defs

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

## Perimeter highway: a closed long-arc ellipse around the footprint
## (hub+pass inside, the P1 alpine domes outside, and keeping > 400 m clear of
## the P1 sea interior). Y is a gentle two-cycle bank (22 +/- 16) so the ring
## never drops below the driveable band. Seed-dependent Y phasing only.
static func _highway_ring_points(rng: RandomNumberGenerator) -> Array[Vector3]:
	const CENTER := Vector2(4400.0, 2250.0)
	const AXIS_X := 4600.0
	const AXIS_Z := 3550.0
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