# tests/suites/test_map_road_labels.gd
extends GdUnitTestSuite

## Road NAMES on the pause map: the curated major-road set is real (every id is
## one the planner emits, every curated id resolves to a non-empty name through
## the table or the title-cased fallback), MapRoads.get_road_ids() is
## index-parallel with get_roads() -- real network AND duck-typed fallback, which
## is the invariant that keeps the discovery mask tinting the right road -- and
## the placement pass drops a name rather than overlapping one, drops one that
## would clip the frame, and follows the reveal state of the road it names.
## Finally the show_road_labels gate rides set_category_filters()'s PARTIAL
## update semantics and reset_category_filters(), and a map with no road source
## (or a degenerate chain, or a null font) yields no labels instead of a crash.
##
## Placement is asserted through the static seam (WorldMap.place_road_labels)
## with an injected measurer, so no canvas, no theme and no font resource is
## needed; the two map-level tests then drive a real WorldMap headlessly the way
## test_photo_mode does (build the tree, call _rebuild, read the cached set).
const WorldMapScript: GDScript = preload("res://scripts/ui/world_map.gd")

var _managed: Array = []

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	for entry in _managed:
		if is_instance_valid(entry):
			entry.free()
	_managed.clear()

func _new_root() -> Node:
	var root := Node.new()
	root.name = "TestRoot"
	_managed.append(root)
	add_child(root)
	return root

## The 19 road ids the shipped planner emits, keyed for membership tests.
func _planner_road_ids() -> Dictionary:
	var out := {}
	for def in CorridorPlanner.plan(CorridorPlanner.MASTER_SEED):
		out[def.id] = true
	return out

## The curated name the planner puts on the def for `road_id` -- i.e. what the map
## draws via MapRoads.get_road_names(). "" when the planner has no name for it,
## which is a failure the caller asserts on rather than papering over.
func _planner_road_name(road_id: String) -> String:
	for def in CorridorPlanner.plan(CorridorPlanner.MASTER_SEED):
		if def.id == road_id:
			return def.display_name()
	return ""

## A WorldMap over a real RoadNetwork carrying the FULL planned network, so the
## label set is the one the open world actually produces. _rebuild() only
## collects roads (and names) when a road source exists, which is what keeps the
## map roadless on circuits.
func _new_world_map(root: Node, map_size: Vector2 = Vector2(1024.0, 768.0)) -> WorldMap:
	var network := RoadNetwork.new()
	network.name = "LabelNetwork"
	add_child(network)
	_managed.append(network)
	for def in CorridorPlanner.plan(CorridorPlanner.MASTER_SEED):
		network.add_road_def(def)
	var world_map := WorldMapScript.new() as WorldMap
	world_map.name = "LabelMap"
	world_map.size = map_size
	root.add_child(world_map)
	_managed.append(world_map)
	return world_map

## A stub source that duck-types get_roads() and nothing else: exactly the
## tree-walked fallback shape resolve_road_source() can return.
func _duck_typed_source(chains: Array) -> Node:
	var stub := GDScript.new()
	stub.source_code = "extends Node\n\nvar chains: Array = []\n\nfunc get_roads() -> Array:\n\treturn chains\n"
	stub.reload()
	var node := Node.new()
	node.name = "DuckRoads"
	node.set_script(stub)
	node.set("chains", chains)
	return node

## A fixed-size measurer standing in for the font, so placement and collision
## are assertable with no canvas, no theme and no font resource.
func _fixed_measure(size: Vector2) -> Callable:
	return func(_text: String) -> Vector2:
		return size

# ---------------------------------------------------------------------------
# The curated set: real ids, real names, no blanks.
# ---------------------------------------------------------------------------

## Every curated id is a road the planner really emits, and every table id is
## curated (the table cannot drift into naming a road nobody labels).
##
## This suite used to ALSO pin the "majors only" policy: exactly seven ids, none
## of them a "-ramp", and the other twelve anonymous. That policy is deliberately
## gone -- all nineteen corridors are named now (CorridorPlanner.ROAD_NAMES), so
## the assertions are about agreement between the two naming sources, not about a
## whitelist. The shipped names themselves are still pinned below.
func test_curated_major_roads_are_real_planner_ids_and_are_labelled() -> void:
	var planned := _planner_road_ids()
	assert_array(WorldMap.MAJOR_ROAD_IDS).has_size(7)
	for road_id in WorldMap.MAJOR_ROAD_IDS:
		assert_that(planned.has(road_id)).is_true()
		assert_that(WorldMap.ROAD_LABELS.has(road_id)).is_true()
		assert_that(WorldMap.road_label(road_id)).is_not_empty()
	for table_id in WorldMap.ROAD_LABELS:
		assert_array(WorldMap.MAJOR_ROAD_IDS).contains([str(table_id)])

	# The table and the planner must AGREE on the seven, so a road reads the same
	# whether its label came from RoadDef.name or from the fallback table.
	for road_id in WorldMap.MAJOR_ROAD_IDS:
		assert_that(WorldMap.road_label(road_id)).is_equal(_planner_road_name(str(road_id)))

	# The twelve roads outside the table are the ramps, dirt cuts and shoreline
	# ribbons -- the ones that used to stay anonymous. They now carry a curated
	# name on the def itself, so they are named WITHOUT a ROAD_LABELS entry.
	var named_outside_table := 0
	for road_id in planned:
		if WorldMap.MAJOR_ROAD_IDS.has(str(road_id)):
			continue
		assert_that(WorldMap.ROAD_LABELS.has(str(road_id))).is_false()
		var def_name := _planner_road_name(str(road_id))
		assert_that(def_name).is_not_empty()
		assert_that(def_name).is_equal(str(def_name.strip_edges()))
		named_outside_table += 1
	assert_int(named_outside_table).is_equal(12)

## The shipped names are player-facing text, pinned here so a rename is a
## deliberate edit rather than a silent diff.
func test_shipped_road_names_are_the_curated_display_strings() -> void:
	assert_that(WorldMap.road_label("hub-ring")).is_equal("Hub Ring")
	assert_that(WorldMap.road_label("hub-pass")).is_equal("Hub Pass Link")
	assert_that(WorldMap.road_label("pass-loop")).is_equal("Mountain Pass Loop")
	assert_that(WorldMap.road_label("highway-ring")).is_equal("Ring Highway")
	assert_that(WorldMap.road_label("touge-a")).is_equal("Touge A")
	assert_that(WorldMap.road_label("touge-b")).is_equal("Touge B")
	assert_that(WorldMap.road_label("hub-coast")).is_equal("Coast Link")

## The fallback: an id with no table entry still names itself, title-cased from
## the slug, and never renders blank -- not for a real-but-unpromoted road, not
## for a road added to the planner after this map shipped, not for "".
func test_road_label_fallback_is_title_cased_and_never_blank() -> void:
	assert_that(WorldMap.road_label("coast-a")).is_equal("Coast A")
	assert_that(WorldMap.road_label("brand-new-coast-link")).is_equal("Brand New Coast Link")
	assert_that(WorldMap.road_label("dirt-b")).is_equal("Dirt B")
	assert_that(WorldMap.road_label("")).is_not_empty()
	assert_that(WorldMap.road_label("highway-pass-ramp")).is_equal("Highway Pass Ramp")
	for road_id in _planner_road_ids():
		assert_that(WorldMap.road_label(str(road_id))).is_not_empty()

# ---------------------------------------------------------------------------
# Identity reaching the map: get_road_ids() must stay index-parallel with
# get_roads(), because the discovery mask is keyed by CHAIN INDEX.
# ---------------------------------------------------------------------------

## A real RoadNetwork: one id per chain, in add order, each naming the chain at
## the same index (checked against that chain's own first point, not just the
## count). This is the invariant that keeps the grey/white reveal state -- and
## therefore the label tint -- on the road it belongs to.
func test_get_road_ids_is_index_parallel_with_get_roads() -> void:
	var network := RoadNetwork.new()
	add_child(network)
	_managed.append(network)
	var ring: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(100.0, 0.0, 0.0)]
	var touge: Array[Vector3] = [
		Vector3(10.0, 0.0, 10.0),
		Vector3(20.0, 0.0, 20.0),
		Vector3(30.0, 0.0, 10.0),
	]
	network.add_road_def(RoadDef.make(RoadDef.Tier.ARTERIAL, ring, "hub-ring", true))
	# The legacy shim takes no id: RoadNetwork stamps one, and the map must see
	# that stamped id rather than a blank.
	network.add_road([Vector3(0.0, 0.0, 100.0), Vector3(50.0, 0.0, 200.0)], 8.0, false)
	network.add_road_def(RoadDef.make(RoadDef.Tier.TOUGE, touge, "touge-a", true))

	var roads := MapRoads.get_roads(network)
	var ids := MapRoads.get_road_ids(network)
	assert_that(ids.size()).is_equal(roads.size())
	assert_that(ids.size()).is_equal(3)
	assert_that(str(ids[0])).is_equal("hub-ring")
	assert_that(str(ids[2])).is_equal("touge-a")
	assert_that(str(ids[1])).is_not_empty()
	assert_that(str(ids[1])).is_not_equal(MapRoads.UNKNOWN_ROAD_ID)

	# Chain-level parity, not just count parity: the chain each id names is the
	# chain at the same index.
	for i in roads.size():
		var chain: Array = roads[i]
		var first: Vector3 = chain[0]
		if str(ids[i]) == "hub-ring":
			assert_that(first).is_equal(Vector3(0.0, 0.0, 0.0))
		elif str(ids[i]) == "touge-a":
			assert_that(first).is_equal(Vector3(10.0, 0.0, 10.0))
		else:
			assert_that(first).is_equal(Vector3(0.0, 0.0, 100.0))

## The fallback source (get_roads() and nothing else) still gets one slot per
## chain, so the map's mask indexing cannot shift; the entries are UNKNOWN and
## therefore simply unnamed. Null and method-less sources are empty, and neither
## accessor regresses the other.
func test_get_road_ids_handles_a_duck_typed_fallback_source() -> void:
	var ring: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(100.0, 0.0, 0.0)]
	var spur: Array[Vector3] = [Vector3(0.0, 0.0, 50.0), Vector3(50.0, 0.0, 90.0)]
	var chains: Array = [ring, spur]
	var stub := _duck_typed_source(chains)
	_managed.append(stub)

	var roads := MapRoads.get_roads(stub)
	var ids := MapRoads.get_road_ids(stub)
	assert_that(roads.size()).is_equal(2)
	assert_that(ids.size()).is_equal(roads.size())
	for road_id in ids:
		assert_that(str(road_id)).is_equal(MapRoads.UNKNOWN_ROAD_ID)

	# Names follow the SAME index-parity contract and fall back to blank (NOT to
	# an id-derived guess) when the source has no defs to read a name from.
	var names := MapRoads.get_road_names(stub)
	assert_that(names.size()).is_equal(roads.size())
	for road_name in names:
		assert_that(str(road_name)).is_equal(MapRoads.UNKNOWN_ROAD_ID)

	# Null source and an object without the road API: every accessor agrees, and
	# none throws.
	assert_that(MapRoads.get_road_ids(null).is_empty()).is_true()
	assert_that(MapRoads.get_roads(null).is_empty()).is_true()
	assert_that(MapRoads.get_road_names(null).is_empty()).is_true()
	var plain := RefCounted.new()
	assert_that(MapRoads.get_road_ids(plain).is_empty()).is_true()
	assert_that(MapRoads.get_roads(plain).is_empty()).is_true()
	assert_that(MapRoads.get_road_names(plain).is_empty()).is_true()

## The full planned network, through the real accessor: 19 chains, 19 ids, every
## id matching its own RoadDef.
func test_get_road_ids_matches_the_whole_planned_network() -> void:
	var network := RoadNetwork.new()
	add_child(network)
	_managed.append(network)
	var defs: Array[RoadDef] = CorridorPlanner.plan(CorridorPlanner.MASTER_SEED)
	for def in defs:
		network.add_road_def(def)
	var roads := MapRoads.get_roads(network)
	var ids := MapRoads.get_road_ids(network)
	assert_that(roads.size()).is_equal(defs.size())
	assert_that(ids.size()).is_equal(roads.size())
	for i in defs.size():
		assert_that(str(ids[i])).is_equal(defs[i].id)
	var planned: Dictionary = _planner_road_ids()
	for road_id in ids:
		assert_that(planned.has(str(road_id))).is_true()

# ---------------------------------------------------------------------------
# Placement: midpoint, upright angle, greedy collision, reveal tint.
# ---------------------------------------------------------------------------

## A single long road with a measurer: exactly one label, sitting at the
## ARC-LENGTH midpoint (the chain is sampled unevenly, so the vertex midpoint
## would be somewhere else entirely), carrying the curated display name.
func test_label_sits_at_the_arc_length_midpoint_of_its_road() -> void:
	var chain: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(10.0, 0.0, 0.0),
		Vector3(100.0, 0.0, 0.0),
	]
	var fit := MapRoads.compute_fit([chain[0], chain[2]], Vector3.ZERO,
		Vector2(400.0, 400.0), 20.0)
	var placed := WorldMap.place_road_labels([chain], ["highway-ring"], fit,
		_fixed_measure(Vector2(60.0, 12.0)), Rect2(0.0, 0.0, 400.0, 400.0))
	assert_that(placed.size()).is_equal(1)
	if placed.size() != 1:
		return
	var entry: Dictionary = placed[0]
	assert_that(str(entry["id"])).is_equal("highway-ring")
	assert_that(str(entry["text"])).is_equal("Ring Highway")
	assert_that(bool(entry["revealed"])).is_true()
	# 10 m + 90 m of road: the halfway point is 50 m along, i.e. x = 50.
	var expected: Vector2 = MapRoads.world_to_screen(Vector3(50.0, 0.0, 0.0), fit)
	var at: Vector2 = entry["screen"]
	assert_float(at.x).is_equal_approx(expected.x, 0.001)
	assert_float(at.y).is_equal_approx(expected.y, 0.001)

## A name is never drawn upside-down. A road authored right-to-left is labelled
## along its own line with the text reversed, not turned over, so the folded
## angle comes out the same as the forward-authored chain; a purely vertical road
## is a legal 90-degree label at the edge of the upright half-turn.
func test_labels_are_folded_upright_never_upside_down() -> void:
	var forward: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(100.0, 0.0, 100.0)]
	var backward: Array[Vector3] = [Vector3(100.0, 0.0, 100.0), Vector3(0.0, 0.0, 0.0)]
	var vertical: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 200.0)]
	var content: Array = [Vector3(0.0, 0.0, 0.0), Vector3(100.0, 0.0, 100.0),
		Vector3(0.0, 0.0, 200.0)]
	var fit := MapRoads.compute_fit(content, Vector3.ZERO, Vector2(600.0, 600.0), 20.0)
	var rect := Rect2(0.0, 0.0, 600.0, 600.0)
	var measure := _fixed_measure(Vector2(40.0, 10.0))
	var ahead := WorldMap.place_road_labels([forward], ["hub-ring"], fit, measure, rect)
	var behind := WorldMap.place_road_labels([backward], ["hub-ring"], fit, measure, rect)
	var upright := WorldMap.place_road_labels([vertical], ["hub-ring"], fit, measure, rect)
	assert_that(ahead.size()).is_equal(1)
	assert_that(behind.size()).is_equal(1)
	assert_that(upright.size()).is_equal(1)
	if ahead.size() != 1 or behind.size() != 1 or upright.size() != 1:
		return
	var a: float = (ahead[0] as Dictionary)["angle"]
	var b: float = (behind[0] as Dictionary)["angle"]
	var v: float = (upright[0] as Dictionary)["angle"]
	# The diagonal renders at 45 degrees in both authoring directions.
	assert_float(a).is_equal_approx(PI * 0.25, 0.001)
	assert_float(b).is_equal_approx(PI * 0.25, 0.001)
	# Nothing is ever outside the upright half-turn.
	assert_float(absf(a)).is_less_equal(PI * 0.5 + 0.001)
	assert_float(absf(b)).is_less_equal(PI * 0.5 + 0.001)
	assert_float(absf(v)).is_less_equal(PI * 0.5 + 0.001)
	assert_float(v).is_equal_approx(-PI * 0.5, 0.001)

## Collision avoidance, end to end: two parallel majors whose arc-length
## midpoints project a few pixels apart, so both want the same strip of the frame
## and only one name is drawn -- the LONGER road's, because a ring the player
## drives for twenty minutes outranks a connector for the last few pixels. No
## two placed boxes may ever intersect, and a frame with room gives both back in
## length order.
func test_longer_road_wins_the_contested_space() -> void:
	var long_road: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(400.0, 0.0, 0.0)]
	var short_road: Array[Vector3] = [Vector3(180.0, 0.0, 10.0), Vector3(220.0, 0.0, 10.0)]
	var roads: Array = [short_road, long_road]
	var ids: Array = ["hub-pass", "highway-ring"]
	var measure := _fixed_measure(Vector2(30.0, 10.0))

	# Tight frame: the 400 m ring and the 40 m connector both want the middle.
	var tight_fit := MapRoads.compute_fit(
		[Vector3(0.0, 0.0, 0.0), Vector3(400.0, 0.0, 10.0)], Vector3.ZERO,
		Vector2(300.0, 120.0), 4.0)
	var tight := WorldMap.place_road_labels(roads, ids, tight_fit, measure,
		Rect2(0.0, 0.0, 300.0, 120.0))
	assert_that(tight.size()).is_equal(1)
	if tight.size() != 1:
		return
	# The short road was listed FIRST on purpose: array order is not priority,
	# chain length is.
	assert_that(str((tight[0] as Dictionary)["id"])).is_equal("highway-ring")

	# A frame with room: both are placed, longest first, boxes disjoint.
	var roomy_fit := MapRoads.compute_fit(
		[Vector3(0.0, 0.0, 0.0), Vector3(400.0, 0.0, 10.0)], Vector3.ZERO,
		Vector2(900.0, 900.0), 20.0)
	var roomy := Rect2(0.0, 0.0, 900.0, 900.0)
	var both := WorldMap.place_road_labels(roads, ids, roomy_fit, measure, roomy)
	assert_that(both.size()).is_equal(2)
	if both.size() != 2:
		return
	assert_that(str((both[0] as Dictionary)["id"])).is_equal("highway-ring")
	assert_that(str((both[1] as Dictionary)["id"])).is_equal("hub-pass")
	var a: Rect2 = (both[0] as Dictionary)["box"]
	var b: Rect2 = (both[1] as Dictionary)["box"]
	assert_that(a.intersects(b)).is_false()
	assert_that(roomy.encloses(a)).is_true()
	assert_that(roomy.encloses(b)).is_true()

## A name is dropped, never clipped in half, when its box would cross the frame.
func test_labels_that_would_clip_the_frame_are_dropped() -> void:
	var chain: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(400.0, 0.0, 0.0)]
	var fit := MapRoads.compute_fit([chain[0], chain[1]], Vector3.ZERO,
		Vector2(400.0, 400.0), 4.0)
	var roomy := Rect2(0.0, 0.0, 400.0, 400.0)
	var measure := _fixed_measure(Vector2(60.0, 12.0))
	var placed := WorldMap.place_road_labels([chain], ["hub-ring"], fit, measure, roomy)
	assert_that(placed.size()).is_equal(1)
	if placed.size() != 1:
		return
	var at: Vector2 = (placed[0] as Dictionary)["screen"]
	var box: Rect2 = (placed[0] as Dictionary)["box"]
	assert_that(roomy.has_point(at)).is_true()
	assert_that(roomy.encloses(box)).is_true()

	# A frame that cannot hold the whole name yields no name at all.
	var tiny := Rect2(0.0, 0.0, 20.0, 8.0)
	var clipped := WorldMap.place_road_labels([chain], ["hub-ring"], fit, measure, tiny)
	assert_that(clipped.is_empty()).is_true()

## A label follows the road it names: the entry carries the reveal state of the
## piece of road it sits on, so an unvisited road is not stamped as driven. The
## road itself is still drawn unrevealed, so the name spoils nothing.
func test_label_tint_follows_the_reveal_state_of_its_road() -> void:
	var visited: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(200.0, 0.0, 0.0)]
	var hidden: Array[Vector3] = [Vector3(0.0, 0.0, 300.0), Vector3(200.0, 0.0, 300.0)]
	var fit := MapRoads.compute_fit(
		[Vector3(0.0, 0.0, 0.0), Vector3(200.0, 0.0, 300.0)], Vector3.ZERO,
		Vector2(800.0, 800.0), 20.0)
	var rect := Rect2(0.0, 0.0, 800.0, 800.0)
	var measure := _fixed_measure(Vector2(50.0, 10.0))
	var only_first_driven := func(road_index: int, _segment: int) -> bool:
		return road_index == 0
	var placed := WorldMap.place_road_labels([visited, hidden],
		["hub-ring", "touge-a"], fit, measure, rect, only_first_driven)
	assert_that(placed.size()).is_equal(2)
	if placed.size() != 2:
		return
	var by_id := {}
	for entry in placed:
		by_id[str((entry as Dictionary)["id"])] = entry as Dictionary
	assert_that(bool(by_id["hub-ring"]["revealed"])).is_true()
	assert_that(bool(by_id["touge-a"]["revealed"])).is_false()

	# No discovery source at all: everything reads as revealed, matching the
	# road draw pass.
	var no_source := WorldMap.place_road_labels([visited, hidden],
		["hub-ring", "touge-a"], fit, measure, rect)
	assert_that(no_source.size()).is_equal(2)
	for entry in no_source:
		assert_that(bool((entry as Dictionary)["revealed"])).is_true()

# ---------------------------------------------------------------------------
# Degenerate inputs: no crash, no garbage, no label.
# ---------------------------------------------------------------------------

## Everything that can be empty, short, or missing: no road source at all, an
## empty chain, a single-point chain, a chain that is not an array, a garbage
## element inside a chain, an id array shorter than the chains, a measurer that
## returns nothing, no fit, a zero-size frame, an invalid measurer and a null
## font. None may throw; the ones that cannot be named must yield no label.
func test_degenerate_road_setups_yield_no_labels() -> void:
	var fit := MapRoads.compute_fit([Vector3.ZERO, Vector3(10.0, 0.0, 10.0)],
		Vector3.ZERO, Vector2(400.0, 400.0), 20.0)
	var rect := Rect2(0.0, 0.0, 400.0, 400.0)
	var measure := _fixed_measure(Vector2(50.0, 10.0))
	var one_point: Array[Vector3] = [Vector3(5.0, 0.0, 5.0)]
	var real: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(10.0, 0.0, 10.0)]

	assert_that(WorldMap.place_road_labels([], [], fit, measure, rect).is_empty()).is_true()
	assert_that(WorldMap.place_road_labels([[]], ["hub-ring"], fit, measure, rect).is_empty()).is_true()
	assert_that(WorldMap.place_road_labels([one_point], ["hub-ring"], fit, measure, rect).is_empty()).is_true()

	# Not an array at all, and a garbage element inside an array.
	assert_that(WorldMap.place_road_labels(["nope"], ["hub-ring"], fit, measure, rect).is_empty()).is_true()
	assert_that(WorldMap.place_road_labels([[Vector3.ZERO, 42]], ["hub-ring"], fit, measure, rect).is_empty()).is_true()

	# Fewer ids than chains: the unnamed tail is skipped, the named head survives.
	assert_that(WorldMap.place_road_labels([real, real], ["hub-ring"], fit, measure, rect).size()).is_equal(1)

	# No measurable text, no fit, no frame, no measurer.
	assert_that(WorldMap.place_road_labels([real], ["hub-ring"], fit,
		_fixed_measure(Vector2.ZERO), rect).is_empty()).is_true()
	assert_that(WorldMap.place_road_labels([real], ["hub-ring"], {},
		measure, rect).is_empty()).is_true()
	assert_that(WorldMap.place_road_labels([real], ["hub-ring"], fit,
		measure, Rect2(0.0, 0.0, 0.0, 0.0)).is_empty()).is_true()
	assert_that(WorldMap.place_road_labels([real], ["hub-ring"], fit,
		Callable(), rect).is_empty()).is_true()

	# A null font measures as zero rather than crashing the measurement call.
	assert_that(WorldMap.label_text_size(null, "Hub Ring")).is_equal(Vector2.ZERO)

	# A chain whose vertices all sit on one spot has no direction and no length:
	# the name is still drawn, but unrotated at that spot rather than at an
	# arbitrary angle.
	var collapsed: Array[Vector3] = [Vector3(5.0, 0.0, 5.0), Vector3(5.0, 0.0, 5.0)]
	var stacked := WorldMap.place_road_labels([collapsed], ["hub-ring"], fit, measure, rect)
	assert_that(stacked.size()).is_equal(1)
	if stacked.size() == 1:
		assert_float(float((stacked[0] as Dictionary)["angle"])).is_equal_approx(0.0, 0.001)
		assert_float(float((stacked[0] as Dictionary)["length"])).is_equal_approx(0.0, 0.001)

	# And the whole map with no road source anywhere: no labels, no fit, no throw.
	var root := _new_root()
	var roadless := WorldMapScript.new() as WorldMap
	roadless.name = "RoadlessMap"
	roadless.size = Vector2(512.0, 512.0)
	root.add_child(roadless)
	_managed.append(roadless)
	roadless.call("_rebuild")
	assert_that(roadless.road_label_ids().is_empty()).is_true()

	# A frame, so a real draw pass runs the label draw over an empty label set.
	await await_idle_frame()
	roadless.set_category_filters({"road_labels": false})
	roadless.call("_rebuild")
	assert_that(roadless.road_label_ids().is_empty()).is_true()

# ---------------------------------------------------------------------------
# The gate: show_road_labels through the PARTIAL filter API.
# ---------------------------------------------------------------------------

## The real network names its majors by default; hiding the gate drops the names
## and leaves every other filter EXACTLY as it was (partial-update semantics),
## and reset_category_filters() brings the names back. The POI dot set is
## untouched throughout -- the gate is about text, never about layers.
func test_world_map_road_label_gate_follows_partial_filter_updates() -> void:
	var root := _new_root()
	var world_map := _new_world_map(root)
	world_map.call("_rebuild")
	var labelled := world_map.road_label_ids()
	assert_that(labelled.is_empty()).is_false()
	assert_int(labelled.size()).is_greater_equal(1)
	# No whitelist any more: every label is drawn from a NAMED road, and the
	# count is bounded by the network, not by MAJOR_ROAD_IDS. The greedy
	# longest-first pass still drops names that would collide, so this is an
	# upper bound, not a floor.
	assert_int(labelled.size()).is_less_equal(19)
	var pois_before := world_map.poi_entry_ids().size()
	for road_id in labelled:
		# Whatever got placed is a real planned road with a curated name -- the
		# twelve non-major roads (ramps, cuts, shore ribbons) are candidates too.
		assert_that(_planner_road_name(str(road_id))).is_not_empty()

	# The whole point of the change: the set is no longer capped at the seven
	# majors. Collision drops can shrink it, so assert on what did get drawn --
	# including at least one road that used to be anonymous -- rather than on a
	# count the greedy pass controls.
	var texts := world_map.road_label_texts()
	assert_that(texts.size()).is_equal(labelled.size())
	var drawn := {}
	for text in texts:
		drawn[str(text)] = true
	# All seven curated majors draw: they sort ahead of everything else, so the
	# twelve newly-named roads can only take space the majors left over. This is
	# the invariant that broke when the pass was ranked on length alone.
	for major_id in WorldMap.MAJOR_ROAD_IDS:
		var major_text := WorldMap.road_label(str(major_id))
		assert_bool(drawn.has(major_text)).append_failure_message(
			"curated major not drawn; drew %s" % str(texts)).is_true()
	# And more than the seven now fit -- the point of naming the other twelve.
	assert_int(texts.size()).is_greater(WorldMap.MAJOR_ROAD_IDS.size())
	# A road that has no ROAD_LABELS entry can ONLY appear if the def's curated
	# name is being used, so this one assertion covers the new data path.
	var from_def := 0
	for road_id in labelled:
		if not WorldMap.ROAD_LABELS.has(str(road_id)):
			from_def += 1
	assert_bool(from_def > 0).is_true()

	# Partial update: only the road-label key is present.
	world_map.set_category_filters({"road_labels": false})
	world_map.call("_rebuild")
	assert_that(world_map.show_road_labels).is_false()
	assert_that(world_map.road_label_ids().is_empty()).is_true()

	# Nothing else moved.
	assert_that(world_map.show_pois).is_true()
	assert_that(world_map.show_landmarks).is_true()
	assert_that(world_map.show_events).is_true()
	assert_that(world_map.show_collectibles).is_true()
	assert_that(world_map.show_travel).is_true()
	assert_that(world_map.region_filter).is_equal("")
	assert_that(world_map.poi_entry_ids().size()).is_equal(pois_before)

	# A partial update that does not mention the key at all leaves it alone.
	world_map.set_category_filters({"region": "coast"})
	world_map.call("_rebuild")
	assert_that(world_map.show_road_labels).is_false()
	assert_that(world_map.road_label_ids().is_empty()).is_true()

	# The shipped all-on reset restores the names.
	world_map.reset_category_filters()
	world_map.call("_rebuild")
	assert_that(world_map.show_road_labels).is_true()
	assert_that(world_map.region_filter).is_equal("")
	assert_int(world_map.road_label_ids().size()).is_greater_equal(1)
	assert_that(world_map.poi_entry_ids().size()).is_equal(pois_before)

	# An empty update is a no-op by design, labels included.
	var before := world_map.road_label_ids()
	world_map.set_category_filters({})
	world_map.call("_rebuild")
	assert_array(world_map.road_label_ids()).contains_exactly(before)

## Toggling the gate marks the map dirty exactly like every other filter, so the
## cached label set is rebuilt on the next draw pass (the shipped map only draws
## when dirty).
func test_road_label_toggle_marks_the_map_dirty() -> void:
	var root := _new_root()
	var world_map := _new_world_map(root)
	world_map.call("_rebuild")
	assert_int(world_map.road_label_ids().size()).is_greater_equal(1)
	assert_that(bool(world_map.get("_dirty"))).is_false()

	world_map.set_category_filters({"road_labels": false})
	assert_that(bool(world_map.get("_dirty"))).is_true()
	world_map.call("_rebuild")
	assert_that(bool(world_map.get("_dirty"))).is_false()

	world_map.set_category_filters({"road_labels": true})
	assert_that(bool(world_map.get("_dirty"))).is_true()
	world_map.call("_rebuild")
	assert_int(world_map.road_label_ids().size()).is_greater_equal(1)
