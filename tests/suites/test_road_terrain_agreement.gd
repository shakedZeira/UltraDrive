# tests/suites/test_road_terrain_agreement.gd
extends GdUnitTestSuite

## Bug 3e regression: every planned road must sit on the heightfield it is carved
## into. Before the fix touge-a / touge-b were ~1969 m under the alpine massifs,
## the highway ring ~1586 m under their skirt at (6160, 5530) and touge-highway-ramp
## ~1378 m, because the planner used free-floating Y profiles (flat 22 +/- 16, touge
## 115 +/- 85) and the P1 domes later grew to 1100 / 850 m. The terrain bake then
## turned the mismatch into km-deep 40 m wide canyons (live ring and vista alike).
##
## "Natural height" is TerrainBaker.natural_height_at, the field both the live ring
## and the vista bake before roads are carved into it.

## Largest the road may sit BELOW the raw ground (a cut) and ABOVE it (an
## embankment). The old network's worst in-bounds road was 63 m of cut (pass-loop)
## and 38 m of fill; the planner's own dead bands are 20 / 40 m on smoothed ground.
const MAX_CUT := 70.0
const MAX_FILL := 45.0
## Roads that used to be hundreds to thousands of metres under the ground.
const FORMER_CANYON_ROADS := ["highway-ring", "touge-a", "touge-b", "touge-highway-ramp",
		"pass-highway-ramp", "highway-pass-ramp"]

var _defs: Array[RoadDef] = []
var _tb: TerrainBaker

func before_test() -> void:
	_defs = CorridorPlanner.plan(CorridorPlanner.MASTER_SEED)
	_tb = TerrainBaker.new()

func _def(id: String) -> RoadDef:
	for d in _defs:
		if d.id == id:
			return d
	return null

## {"cut": worst ground-minus-road, "fill": worst road-minus-ground, "at": Vector3}
func _agreement(def: RoadDef) -> Dictionary:
	var cut := -INF
	var fill := -INF
	var at := Vector3.ZERO
	for p in def.points:
		var delta := _tb.natural_height_at(p.x, p.z) - p.y
		if delta > cut:
			cut = delta
			at = p
		fill = maxf(fill, -delta)
	return {"cut": cut, "fill": fill, "at": at}

## Max |dy| / run over any >= 100 m stretch of the centreline, in percent.
func _max_grade_pct(def: RoadDef) -> float:
	var pts: Array[Vector3] = def.points
	var n := pts.size()
	var worst := 0.0
	for i in n:
		var acc := 0.0
		var j := i
		while j + 1 < n and acc < 100.0:
			acc += Vector2(pts[j + 1].x - pts[j].x, pts[j + 1].z - pts[j].z).length()
			j += 1
		if acc >= 100.0:
			worst = maxf(worst, absf(pts[j].y - pts[i].y) / acc)
	return worst * 100.0

func test_every_road_stays_within_the_carve_tolerance_of_the_ground() -> void:
	for def in _defs:
		var a := _agreement(def)
		assert_float(a["cut"]).override_failure_message(
			"%s sits %.0f m under the ground at %s" % [def.id, a["cut"], a["at"]]).is_less_equal(MAX_CUT)
		assert_float(a["fill"]).override_failure_message(
			"%s sits %.0f m over the ground" % [def.id, a["fill"]]).is_less_equal(MAX_FILL)

func test_the_former_canyon_roads_follow_the_ground() -> void:
	for id in FORMER_CANYON_ROADS:
		var def := _def(id)
		assert_that(def).override_failure_message("missing road %s" % id).is_not_null()
		if def == null:
			continue
		var a := _agreement(def)
		assert_float(a["cut"]).override_failure_message(
			"%s still %.0f m under the ground at %s" % [id, a["cut"], a["at"]]).is_less(MAX_CUT)

## The planner's default elevation source is the canonical field, so a caller that
## passes nothing (world_driver, event_session) and one that passes it explicitly
## get the same network. (hub-coast is the one exception: its legacy end-Y reads a
## CALLER-supplied provider only, so it sits on the coast ribbon's Y by default.)
func test_default_height_provider_is_the_canonical_field() -> void:
	var explicit := CorridorPlanner.plan(CorridorPlanner.MASTER_SEED,
			CorridorPlanner.canonical_height_provider(), {})
	assert_int(explicit.size()).is_equal(_defs.size())
	for i in _defs.size():
		if _defs[i].id == "hub-coast":
			continue
		assert_that(explicit[i].points).override_failure_message(_defs[i].id).is_equal(_defs[i].points)

## The corrected roads must stay drivable, not just under the ground: the ring and
## the touge on-ramp keep the grade of a mountain highway (the old km-deep canyons
## were the opposite failure, a vertical wall). Where the ring climbs the highland
## shelf's edge the terrain itself rises ~15 %, so 20 % is the ceiling.
func test_ring_and_touge_ramp_keep_a_driveable_grade() -> void:
	for id in ["highway-ring", "touge-highway-ramp"]:
		var g := _max_grade_pct(_def(id))
		assert_float(g).override_failure_message("%s grade %.1f%%" % [id, g]).is_less_equal(20.0)

## Outside the deflection window the ring is still the exact ellipse, so the ramps
## anchored at ring 65 / 96 / 110 / 160 / 174 keep the geometry they were built
## against; inside it the ring never leaves the ellipse outward.
func test_ring_deflection_is_confined_to_its_window() -> void:
	var ring: Array[Vector3] = _def("highway-ring").points
	for i in ring.size():
		var nx := (ring[i].x - CorridorPlanner.RING_CENTER.x) / CorridorPlanner.RING_AXIS_X
		var nz := (ring[i].z - CorridorPlanner.RING_CENTER.y) / CorridorPlanner.RING_AXIS_Z
		var r2 := nx * nx + nz * nz
		if i < CorridorPlanner.RING_DEFLECT_FIRST - 1 or i > CorridorPlanner.RING_DEFLECT_LAST + 1:
			assert_float(r2).override_failure_message("ring %d left the ellipse (r2=%.4f)" % [i, r2]).is_equal_approx(1.0, 0.0005)
		else:
			assert_float(r2).override_failure_message("ring %d outside the ellipse (r2=%.4f)" % [i, r2]).is_less_equal(1.0005)

## End to end: bake the live ring's region under road vertices that used to be
## canyons with the real network carved in. The carved surface at the road must be
## within the tolerance of the natural ground (no canyon, no spire).
func test_the_carve_leaves_no_canyon_under_the_former_canyon_roads() -> void:
	var roads: Array = []
	for d in _defs:
		roads.append(d.points)
	var probes: Array[Vector3] = []
	for id in ["highway-ring", "touge-a", "touge-b", "touge-highway-ramp"]:
		var pts: Array[Vector3] = _def(id).points
		for k in [pts.size() / 5, pts.size() / 2, pts.size() * 4 / 5]:
			probes.append(pts[k])
	var seen := {}
	for p in probes:
		var loc := Vector2i(floori(p.x / 256.0), floori(p.z / 256.0))
		if not seen.has(loc):
			seen[loc] = _tb.bake_region(loc, 1.0, 256, roads)
		var img: Image = seen[loc]
		var ix := clampi(int(p.x - float(loc.x) * 256.0), 0, 255)
		var iz := clampi(int(p.z - float(loc.y) * 256.0), 0, 255)
		var carved := img.get_pixel(ix, iz).r
		var natural := _tb.natural_height_at(p.x, p.z)
		assert_float(natural - carved).override_failure_message(
			"canyon of %.0f m under road vertex %s (ground %.0f, carved %.0f)" % [natural - carved, p, natural, carved]).is_less_equal(MAX_CUT + 5.0)
		assert_float(carved - natural).override_failure_message(
			"spire of %.0f m under road vertex %s" % [carved - natural, p]).is_less_equal(MAX_FILL + 5.0)
