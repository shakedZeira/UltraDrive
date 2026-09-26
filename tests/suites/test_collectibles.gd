# tests/suites/test_collectibles.gd
extends GdUnitTestSuite

## AAA-16 / ROADMAP 2.3 collectibles gate: FH-style bonus boards, speed traps
## and photo spots placed ON the classified road network, claimed exactly once
## per save, and paid through the shipped Money/CareerProfile economy.
##
## Three layers of gate, all headless-safe (no scene tree, no frames, no
## Terrain3D):
##  * PURE: Collectibles.place_data() / can_claim() / claim() are static or
##    instance RefCounted logic, so determinism, road anchoring, the under-speed
##    speed-trap rejection and the exactly-once payout are all asserted directly.
##  * REGISTRY + MAP DOTS: the whole speedtrap_0..7 family is present as
##    first-class POIs, in its own always-shown filter category, and both map
##    layers resolve the SAME family palette -- so a trap is the same loud red on
##    the pause map and the HUD minimap, and a banked one is dimmed on the pause
##    map / dropped from the minimap.
##  * SCENE: a bare CollectibleField with a stub car proves the wiring -- the
##    runtime picks up the POIRegistry entries, the physics tick pays through
##    Money/CareerProfile, and a save round-trip makes the claim survive a
##    restart (while other slot fields survive alongside it).

const WORLD_MAP_SCRIPT := "res://scripts/ui/world_map.gd"
const MINIMAP_SCRIPT := "res://scripts/ui/minimap.gd"

## The slot this suite writes. Every test that saves snapshots and restores it,
## so the suite never clobbers a real playthrough save.
const SLOT := 0
## Wallet balance seeded into the slot, so the payout assertions can prove the
## money really moved through the shipped Money path (not a local accumulator).
## Money.from_dict() derives credits from total_credited - total_spent, so all
## three fields are seeded.
const WALLET_BEFORE := 1_234

var _slot_backup: Dictionary = {}
var _slot_existed := false
var _managed: Array = []

# ---------------------------------------------------------------------------
# Fixtures.
# ---------------------------------------------------------------------------

func before_test() -> void:
	_managed.clear()
	_slot_existed = SaveManager.has_save(SLOT)
	_slot_backup = SaveManager.load_game(SLOT)
	SaveManager.save_career_money(SLOT, {
		"credits": WALLET_BEFORE,
		"total_credited": WALLET_BEFORE,
		"total_spent": 0,
	})
	# Start every test from an empty claim set, exactly like the wallet seed
	# above: a real playthrough save may already carry claimed boards, and
	# completion()/pending assertions must not depend on the player's history.
	# after_test restores the whole slot, so the seeded sections are temporary.
	SaveManager.save_collectibles(SLOT, {})

func after_test() -> void:
	# Sync-free any node a test left behind. A queue_free would still be parented
	# when the next test runs, so its "StubCar" would hold the name and the next
	# test's player_path would resolve a dead node instead of its own car. Only
	# the nodes this suite creates are swept -- gdUnit's own child nodes are
	# locked for the duration of this stage.
	for child in get_children():
		if child is CollectibleField or str(child.name).begins_with("StubCar"):
			child.free()
	for node in _managed:
		if is_instance_valid(node):
			node.free()
	_managed.clear()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()
	if _slot_existed:
		SaveManager.save_game(SLOT, _slot_backup)
		return
	# The slot did not exist before this suite touched it, so remove the file
	# rather than leaving a blank slot behind (mirrors SaveManager._slot_path).
	DirAccess.remove_absolute("user://saves/slot_%d.json" % (SLOT + 1))

func _defs() -> Array[RoadDef]:
	return CorridorPlanner.plan(CorridorPlanner.MASTER_SEED, Callable(), {})

## Minimal stand-in for VehiclePhysics: the only contract CollectibleField reads
## is global_position plus a km/h speed, and the field must not care which of the
## two shipped speed sources it comes from.
class StubCar extends Node3D:
	var current_speed_kmh: float = 0.0

# ---------------------------------------------------------------------------
# Placement: determinism, families, ids, road anchoring.
# ---------------------------------------------------------------------------

func test_place_data_returns_every_family_at_its_declared_count() -> void:
	var placed: Dictionary = Collectibles.place_data(_defs())
	var expected := 0
	for kind: String in Collectibles.FAMILY_COUNT.keys():
		var ids := Collectibles.ids_of_kind(placed, kind)
		assert_array(ids).has_size(int(Collectibles.FAMILY_COUNT[kind]))
		expected += int(Collectibles.FAMILY_COUNT[kind])
	assert_that(placed.size()).is_equal(expected)

func test_ids_are_the_deterministic_family_prefix_plus_index() -> void:
	var placed: Dictionary = Collectibles.place_data(_defs())
	for kind: String in Collectibles.FAMILY_COUNT.keys():
		var ids := Collectibles.ids_of_kind(placed, kind)
		var prefix := str(Collectibles.ID_PREFIX[kind])
		# ids_of_kind orders by the trailing INDEX, so bonus_2 precedes bonus_10.
		for i in ids.size():
			assert_that(ids[i]).is_equal("%s%d" % [prefix, i])

func test_same_master_seed_produces_identical_placement() -> void:
	var first: Dictionary = Collectibles.place_data(_defs())
	var second: Dictionary = Collectibles.place_data(_defs())
	assert_that(second).is_equal(first)

func test_placement_follows_the_road_network_it_is_given() -> void:
	# Guards the determinism gate above: the placement has to come FROM the
	# network, so dropping a corridor must move the sites, and no site may ever
	# name a corridor that is not in the network.
	var defs := _defs()
	var trimmed: Array[RoadDef] = []
	var host_ids: Array[String] = []
	for def: RoadDef in defs:
		if def.id == "dirt-b":
			continue
		trimmed.append(def)
		host_ids.append(def.id)
	var full: Dictionary = Collectibles.place_data(defs)
	var cut: Dictionary = Collectibles.place_data(trimmed)
	assert_that(cut).is_not_equal(full)
	assert_array(cut.keys()).has_size(full.size())
	for collectible_id: String in cut.keys():
		assert_array(host_ids).contains([String(cut[collectible_id]["road_id"])])

func test_every_collectible_is_classified_with_a_finite_position() -> void:
	var placed: Dictionary = Collectibles.place_data(_defs())
	for collectible_id: String in placed.keys():
		var poi: Dictionary = placed[collectible_id]
		assert_that(poi.has("kind")).is_true()
		assert_that(poi.has("name")).is_true()
		assert_that(poi.has("stage")).is_true()
		assert_that(poi.has("road_id")).is_true()
		assert_that(String(poi["road_id"]).is_empty()).is_false()
		assert_that(Collectibles.reward_of(poi)).is_greater(0)
		var pos := poi["position"] as Vector3
		assert_that(is_finite(pos.x)).is_true()
		assert_that(is_finite(pos.y)).is_true()
		assert_that(is_finite(pos.z)).is_true()
		# The stage string is the human name of the host road's own tier.
		assert_that(String(poi["stage"])).is_equal(RoadDef.tier_name(int(poi["tier"])))

func test_every_collectible_sits_on_its_host_road() -> void:
	# The core placement rule: no collectible floats in a field. Boards and traps
	# sit exactly on the centreline (their verb is "drive through / cross the
	# line"), photo spots on a fixed shoulder offset beside it.
	var defs := _defs()
	var placed: Dictionary = Collectibles.place_data(defs)
	var by_road := {}
	for def: RoadDef in defs:
		by_road[def.id] = def
	for collectible_id: String in placed.keys():
		var poi: Dictionary = placed[collectible_id]
		var host: RoadDef = by_road[String(poi["road_id"])]
		assert_that(host).is_not_null()
		var distance := Collectibles.distance_to_road(host, poi["position"] as Vector3)
		var kind := str(poi["kind"])
		if kind == Collectibles.KIND_PHOTO:
			assert_that(distance).is_less_equal(Collectibles.PHOTO_OFFSET_M + 0.001)
		else:
			# On the centreline itself.
			assert_that(distance).is_less(0.001)

func test_collectibles_are_spread_over_the_whole_network() -> void:
	# A placement that bunches into one corner of the map is worthless, so assert
	# the family really uses the whole footprint: at least a third of a family's
	# sites land beyond the half-way mark of the network bounding box, and the
	# hosts span at least half the corridors.
	var defs := _defs()
	var placed: Dictionary = Collectibles.place_data(defs)
	var host_ids := {}
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for def: RoadDef in defs:
		for p in def.points:
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
			min_z = minf(min_z, p.z)
			max_z = maxf(max_z, p.z)
	for collectible_id: String in placed.keys():
		host_ids[String(placed[collectible_id]["road_id"])] = true
	var mid_x := (min_x + max_x) * 0.5
	var mid_z := (min_z + max_z) * 0.5
	var far := 0
	for collectible_id: String in placed.keys():
		var pos := placed[collectible_id]["position"] as Vector3
		if pos.x > mid_x or pos.z > mid_z:
			far += 1
	assert_that(float(far) / float(placed.size())).is_greater_equal(1.0 / 3.0)
	assert_that(host_ids.size()).is_greater_equal(defs.size() / 2)

func test_boards_and_traps_sit_exactly_on_a_road_vertex() -> void:
	# "Drive through it / cross the line" only works if the marker IS a road
	# point, not a spot a few metres off the carriageway.
	var defs := _defs()
	var placed: Dictionary = Collectibles.place_data(defs)
	var by_road := {}
	for def: RoadDef in defs:
		by_road[def.id] = def
	for kind: String in [Collectibles.KIND_BONUS, Collectibles.KIND_SPEED_TRAP]:
		for collectible_id: String in Collectibles.ids_of_kind(placed, kind):
			var poi: Dictionary = placed[collectible_id]
			var chain: Array[Vector3] = by_road[String(poi["road_id"])].points
			var pos := poi["position"] as Vector3
			var on_vertex := false
			for p in chain:
				if p.distance_to(pos) < 0.001:
					on_vertex = true
					break
			assert_that(on_vertex).is_true()
			assert_that(Collectibles.claim_radius_of(poi)).is_greater(0.0)

func test_photo_spots_are_a_pull_out_with_the_widest_claim_radius() -> void:
	# A photo spot is a parking spot, not a gate: it is offset from the centreline
	# (PHOTO_OFFSET_M) and gives you the most generous claim radius of the three
	# families, so you can park and walk around the shot.
	var defs := _defs()
	var placed: Dictionary = Collectibles.place_data(defs)
	var by_road := {}
	for def: RoadDef in defs:
		by_road[def.id] = def
	assert_that(Collectibles.PHOTO_OFFSET_M).is_greater(0.0)
	var board_radius := 0.0
	for collectible_id: String in Collectibles.ids_of_kind(placed, Collectibles.KIND_BONUS):
		board_radius = maxf(board_radius, Collectibles.claim_radius_of(placed[collectible_id]))
	for collectible_id: String in Collectibles.ids_of_kind(placed, Collectibles.KIND_PHOTO):
		var poi: Dictionary = placed[collectible_id]
		var host: RoadDef = by_road[String(poi["road_id"])]
		var distance := Collectibles.distance_to_road(host, poi["position"] as Vector3)
		assert_that(distance).is_less_equal(Collectibles.PHOTO_OFFSET_M + 0.001)
		assert_that(Collectibles.claim_radius_of(poi)).is_greater(board_radius)

func test_a_faster_road_pays_more_for_the_same_family() -> void:
	# Reward scales with the host tier, so the reward field is load-bearing rather
	# than a flat per-kind constant.
	assert_that(Collectibles.reward_for_kind(Collectibles.KIND_BONUS, RoadDef.Tier.HIGHWAY)) \
		.is_greater(Collectibles.reward_for_kind(Collectibles.KIND_BONUS, RoadDef.Tier.DIRT))
	assert_that(Collectibles.reward_for_kind(Collectibles.KIND_SPEED_TRAP, RoadDef.Tier.HIGHWAY)) \
		.is_greater(Collectibles.reward_for_kind(Collectibles.KIND_SPEED_TRAP, RoadDef.Tier.ARTERIAL))
	# The full ladder, strongest road first: highway > arterial > touge == coastal
	# (a scenic back road is worth the same as the descent) > dirt.
	assert_that(Collectibles.reward_for_kind(Collectibles.KIND_PHOTO, RoadDef.Tier.HIGHWAY)) \
		.is_greater(Collectibles.reward_for_kind(Collectibles.KIND_PHOTO, RoadDef.Tier.ARTERIAL))
	assert_that(Collectibles.reward_for_kind(Collectibles.KIND_PHOTO, RoadDef.Tier.ARTERIAL)) \
		.is_greater(Collectibles.reward_for_kind(Collectibles.KIND_PHOTO, RoadDef.Tier.TOUGE))
	assert_that(Collectibles.reward_for_kind(Collectibles.KIND_PHOTO, RoadDef.Tier.TOUGE)) \
		.is_equal(Collectibles.reward_for_kind(Collectibles.KIND_PHOTO, RoadDef.Tier.COASTAL))
	assert_that(Collectibles.reward_for_kind(Collectibles.KIND_PHOTO, RoadDef.Tier.COASTAL)) \
		.is_greater(Collectibles.reward_for_kind(Collectibles.KIND_PHOTO, RoadDef.Tier.DIRT))

func test_kind_of_id_separates_collectibles_from_every_other_poi() -> void:
	assert_that(Collectibles.kind_of_id("bonus_0")).is_equal(Collectibles.KIND_BONUS)
	assert_that(Collectibles.kind_of_id("speedtrap_3")).is_equal(Collectibles.KIND_SPEED_TRAP)
	assert_that(Collectibles.kind_of_id("photospot_7")).is_equal(Collectibles.KIND_PHOTO)
	for other_id in ["festival_hub", "alpine_overlook", "touge_duel", "time_attack_0", "outbreak", "convoy"]:
		assert_that(Collectibles.kind_of_id(other_id)).is_empty()
		assert_that(Collectibles.is_collectible_id(other_id)).is_false()

# ---------------------------------------------------------------------------
# Registry: the collectibles must show up on the maps as first-class POIs.
# ---------------------------------------------------------------------------

func test_collectibles_resolve_as_poi_registry_markers() -> void:
	var placed: Dictionary = Collectibles.place_data(_defs())
	var ids := POIRegistry.get_poi_ids()
	for collectible_id: String in placed.keys():
		assert_that(ids.has(collectible_id)).is_true()
		assert_that(POIRegistry.has_poi(collectible_id)).is_true()
		var poi: Dictionary = POIRegistry.get_poi(collectible_id)
		assert_that(poi.has("position")).is_true()
		assert_that(poi.has("name")).is_true()
		assert_that(poi.has("stage")).is_true()

func test_collectibles_get_their_own_always_shown_map_category() -> void:
	# The pause map filters on category, and a collectible is a gameplay TARGET,
	# not a calendar entry -- so it gets its own bucket instead of riding the
	# events one. That is the whole speed-trap fix: hiding the event markers can
	# never take a speed trap off the map. The partition stays exhaustive and
	# disjoint, so every shipped gate still has a complete, unambiguous set.
	var buckets: Dictionary = POIRegistry.category_buckets()
	var all_ids: Array = POIRegistry.get_poi_ids()
	var landmarks: Array = buckets[POIRegistry.CATEGORY_LANDMARKS]
	var events: Array = buckets[POIRegistry.CATEGORY_EVENTS]
	var collectibles: Array = buckets[POIRegistry.CATEGORY_COLLECTIBLES]
	assert_that(landmarks.size()).is_equal(5)
	assert_that(collectibles.size()).is_equal(Collectibles.place_data(_defs()).size())
	assert_that(landmarks.size() + events.size() + collectibles.size()).is_equal(all_ids.size())
	for collectible_id: String in Collectibles.place_data(_defs()).keys():
		assert_that(POIRegistry.category_of(POIRegistry.get_poi(collectible_id))) \
			.is_equal(POIRegistry.CATEGORY_COLLECTIBLES)
		assert_array(collectibles).contains([collectible_id])
		# An event marker is still an event: the new bucket did not swallow them.
		assert_array(events).not_contains([collectible_id])
	assert_array(events).contains(["time_attack_0"])

func test_every_speed_trap_resolves_from_the_registry_with_its_road() -> void:
	# speedtrap_0..7 are the reason this milestone exists, so pin the whole family
	# down by id: each one resolves, carries the shared map colour source, and
	# still names the corridor it is anchored to (the map and the field agree).
	var red: Color = Collectibles.KIND_DOT_COLOR[Collectibles.KIND_SPEED_TRAP]
	for i in 8:
		var trap_id := "speedtrap_%d" % i
		assert_that(POIRegistry.has_poi(trap_id)).is_true()
		var poi := POIRegistry.get_poi(trap_id)
		assert_that(str(poi.get("id", ""))).is_equal(trap_id)
		assert_that(str(poi.get("kind", ""))).is_equal(Collectibles.KIND_SPEED_TRAP)
		assert_that(Collectibles.kind_color(str(poi["kind"]), Color.BLACK)).is_equal(red)
		assert_that(String(poi.get("road_id", "")).is_empty()).is_false()
		var pos := poi.get("position", Vector3.ZERO) as Vector3
		assert_that(is_finite(pos.x) and is_finite(pos.z)).is_true()

func test_collectibles_are_not_bound_by_the_base_landmark_tile_bounds() -> void:
	# Base landmarks must stay inside the 0..6144 map footprint (checked in
	# test_traffic_spawner), but the collectibles ride the real road net like the
	# event markers do, so only "on a real road" is asserted for them.
	var poi := POIRegistry.get_poi("bonus_0")
	var pos := poi["position"] as Vector3
	assert_that(pos.x).is_greater_equal(-200.0)
	assert_that(pos.x).is_less_equal(9702.0)
	assert_that(pos.z).is_greater_equal(-2944.0)
	assert_that(pos.z).is_less_equal(8605.0)

# ---------------------------------------------------------------------------
# Detection: proximity, plus the speed gate that makes a speed trap a speed trap.
# ---------------------------------------------------------------------------

func test_bonus_board_claims_on_proximity_at_any_speed() -> void:
	var poi := Collectibles.place_data(_defs())["bonus_0"] as Dictionary
	var at := poi["position"] as Vector3
	assert_that(Collectibles.can_claim(poi, at, 0.0)).is_true()
	assert_that(Collectibles.can_claim(poi, at, 240.0)).is_true()

func test_photo_spot_claims_on_proximity_at_any_speed() -> void:
	var poi := Collectibles.place_data(_defs())["photospot_0"] as Dictionary
	var at := poi["position"] as Vector3
	assert_that(Collectibles.can_claim(poi, at, 0.0)).is_true()

func test_out_of_range_never_claims() -> void:
	var placed: Dictionary = Collectibles.place_data(_defs())
	for collectible_id: String in ["bonus_0", "photospot_0", "speedtrap_0"]:
		var poi := placed[collectible_id] as Dictionary
		var far: Vector3 = poi["position"] as Vector3 + Vector3(400.0, 0.0, 400.0)
		assert_that(Collectibles.can_claim(poi, far, 999.0)).is_false()

func test_detection_ignores_height_so_a_car_above_the_road_still_claims() -> void:
	# XZ-only distance (the map click space convention), so a bridge over a
	# roadside spot is still "at" it.
	var poi := Collectibles.place_data(_defs())["bonus_0"] as Dictionary
	var above: Vector3 = poi["position"] as Vector3 + Vector3(0.0, 40.0, 0.0)
	assert_that(Collectibles.can_claim(poi, above, 0.0)).is_true()

func test_speed_trap_pays_only_above_its_target_speed() -> void:
	var poi := Collectibles.place_data(_defs())["speedtrap_0"] as Dictionary
	var at := poi["position"] as Vector3
	var target := Collectibles.speed_target_of(poi)
	assert_that(target).is_greater(0.0)
	assert_that(Collectibles.can_claim(poi, at, target - 1.0)).is_false()
	assert_that(Collectibles.can_claim(poi, at, target)).is_true()
	assert_that(Collectibles.can_claim(poi, at, target + 40.0)).is_true()

func test_every_speed_trap_carries_a_tier_scaled_target() -> void:
	var placed: Dictionary = Collectibles.place_data(_defs())
	for collectible_id: String in Collectibles.ids_of_kind(placed, Collectibles.KIND_SPEED_TRAP):
		var poi: Dictionary = placed[collectible_id]
		var expected := float(Collectibles.TIER_SPEED_TRAP_KMH[int(poi["tier"])])
		assert_that(Collectibles.speed_target_of(poi)).is_equal(expected)
		assert_that(Collectibles.claim_radius_of(poi)).is_greater(0.0)

# ---------------------------------------------------------------------------
# Exactly-once claims (the ledger) and the wallet payout.
# ---------------------------------------------------------------------------

func test_a_claim_pays_once_and_never_twice() -> void:
	var placed: Dictionary = Collectibles.place_data(_defs())
	var ledger := Collectibles.new()
	var collectible_id := Collectibles.ids_of_kind(placed, Collectibles.KIND_BONUS)[0]
	var first := ledger.claim(placed, collectible_id)
	assert_that(first).is_equal(Collectibles.reward_of(placed[collectible_id] as Dictionary))
	assert_that(ledger.is_claimed(collectible_id)).is_true()
	for _again in 5:
		assert_that(ledger.claim(placed, collectible_id)).is_equal(0)
	assert_that(ledger.claimed_count()).is_equal(1)

func test_claiming_an_unknown_id_pays_nothing_and_records_nothing() -> void:
	var placed: Dictionary = Collectibles.place_data(_defs())
	var ledger := Collectibles.new()
	assert_that(ledger.claim(placed, "bonus_9999")).is_equal(0)
	assert_that(ledger.claim(placed, "festival_hub")).is_equal(0)
	assert_that(ledger.claimed_count()).is_equal(0)

func test_claims_are_monotonic_so_completion_never_drops() -> void:
	var placed: Dictionary = Collectibles.place_data(_defs())
	var ledger := Collectibles.new()
	assert_that(ledger.completion(placed)).is_equal(0.0)
	ledger.claim(placed, Collectibles.ids_of_kind(placed, Collectibles.KIND_BONUS)[0])
	var after_one := ledger.completion(placed)
	assert_that(after_one).is_greater(0.0)
	ledger.claim(placed, Collectibles.ids_of_kind(placed, Collectibles.KIND_SPEED_TRAP)[0])
	assert_that(ledger.completion(placed)).is_greater(after_one)
	# A restore can only add claims.
	ledger.restore({Collectibles.SAVE_KEY: {"claimed": []}})
	assert_that(ledger.completion(placed)).is_greater(after_one)

func test_completion_reaches_one_when_everything_is_claimed() -> void:
	var placed: Dictionary = Collectibles.place_data(_defs())
	var ledger := Collectibles.new()
	for collectible_id: String in placed.keys():
		ledger.claim(placed, collectible_id)
	assert_that(ledger.completion(placed)).is_equal(1.0)
	assert_that(ledger.claimed_in(placed)).is_equal(placed.size())

func test_claim_reachable_respects_both_proximity_and_the_speed_gate() -> void:
	# The bulk path the runtime tick uses: a speed trap sitting under the player at
	# crawl speed is skipped however close the player is to it.
	var placed: Dictionary = Collectibles.place_data(_defs())
	var ledger := Collectibles.new()
	var trap_id := Collectibles.ids_of_kind(placed, Collectibles.KIND_SPEED_TRAP)[0]
	var trap: Dictionary = placed[trap_id]
	var at := trap["position"] as Vector3
	assert_array(ledger.claim_reachable(placed, at, 0.0)).not_contains([trap_id])
	assert_that(ledger.is_claimed(trap_id)).is_false()
	var paid := ledger.claim_reachable(placed, at, Collectibles.speed_target_of(trap) + 30.0)
	assert_array(paid).contains([trap_id])

# ---------------------------------------------------------------------------
# Persistence: the exactly-once guarantee has to survive a restart.
# ---------------------------------------------------------------------------

func test_claims_round_trip_through_the_slot_save() -> void:
	var placed: Dictionary = Collectibles.place_data(_defs())
	var ledger := Collectibles.new()
	var all_bonus := Collectibles.ids_of_kind(placed, Collectibles.KIND_BONUS)
	var claimed: Array[String] = []
	for i in 3:
		claimed.append(all_bonus[i])
	for collectible_id: String in claimed:
		ledger.claim(placed, collectible_id)
	assert_that(ledger.save_to_slot(SLOT)).is_true()

	var restored := Collectibles.new()
	assert_that(restored.load_from_slot(SLOT)).is_true()
	assert_array(restored.claimed_ids()).contains_exactly(claimed)
	assert_that(restored.completion(placed)).is_equal(3.0 / float(placed.size()))

func test_a_reloaded_ledger_refuses_to_pay_a_restored_claim_again() -> void:
	# The whole point of persisting: the board you already banked is still banked.
	var placed: Dictionary = Collectibles.place_data(_defs())
	var ledger := Collectibles.new()
	var collectible_id := Collectibles.ids_of_kind(placed, Collectibles.KIND_SPEED_TRAP)[0]
	ledger.claim(placed, collectible_id)
	ledger.save_to_slot(SLOT)

	var restored := Collectibles.new()
	restored.load_from_slot(SLOT)
	assert_that(restored.is_claimed(collectible_id)).is_true()
	assert_that(restored.claim(placed, collectible_id)).is_equal(0)

func test_collectible_save_preserves_the_rest_of_the_slot() -> void:
	# Additive save contract: a claim write must not clobber the other slot
	# sections (garage, discovery, wallet, ...).
	SaveManager.save_game(SLOT, {"custom_keep": "survivor"})
	SaveManager.save_career_money(SLOT, {
		"credits": 7, "total_credited": 7, "total_spent": 0,
	})
	var placed: Dictionary = Collectibles.place_data(_defs())
	var ledger := Collectibles.new()
	ledger.claim(placed, Collectibles.ids_of_kind(placed, Collectibles.KIND_BONUS)[0])
	ledger.save_to_slot(SLOT)
	var data := SaveManager.load_game(SLOT)
	assert_that(str(data.get("custom_keep", ""))).is_equal("survivor")
	assert_that(data.has(Collectibles.SAVE_KEY)).is_true()
	assert_that(data.has(SaveManager.CAREER_MONEY_KEY)).is_true()
	assert_that(int((data[SaveManager.CAREER_MONEY_KEY] as Dictionary).get("credits", 0))).is_equal(7)

func test_restore_tolerates_an_empty_or_older_save() -> void:
	var placed: Dictionary = Collectibles.place_data(_defs())
	var ledger := Collectibles.new()
	ledger.restore({})
	assert_that(ledger.claimed_count()).is_equal(0)
	# A bare list (hand-edited / older shape) still restores, so no claim is lost.
	ledger.restore({Collectibles.SAVE_KEY: ["bonus_0", "speedtrap_1", 42]})
	assert_array(ledger.claimed_ids()).contains_exactly(["bonus_0", "speedtrap_1"])
	assert_that(ledger.claimed_in(placed)).is_equal(2)

# ---------------------------------------------------------------------------
# Runtime scene: the field picks the registry up, pays through Money, and stops
# claiming once everything is banked.
# ---------------------------------------------------------------------------

## Field with the live physics tick switched off, so every assertion here drives
## the trigger deliberately (simulate_step / claim_at) instead of racing gdUnit's
## own frame pumps. test_field_physics_tick_pays_on_contact covers the live path.
func _make_field() -> CollectibleField:
	var field := CollectibleField.new()
	field.save_on_pause = false
	add_child(field)
	field.set_physics_process(false)
	return field

## The persistent wallet as the save slot reads it back -- the only balance a
## collectible award can move.
func _credits() -> int:
	return Money.load_wallet(SLOT).credits

func test_field_publishes_the_registry_collectibles() -> void:
	var field := _make_field()
	assert_array(field.placed().keys()).has_size(Collectibles.place_data(_defs()).size())
	assert_that(field.has_pending()).is_true()
	assert_that(field.completion()).is_equal(0.0)
	field.free()

func test_field_pays_through_the_shipped_wallet_exactly_once() -> void:
	var car := StubCar.new()
	car.name = "StubCar"
	add_child(car)
	var field := _make_field()
	field.player_path = NodePath("../" + car.name)
	car.global_position = Vector3(6000.0, 0.0, 6000.0)

	# Walk the field onto a bonus board, slowly: proximity alone must be enough.
	var target: String = Collectibles.ids_of_kind(field.placed(), Collectibles.KIND_BONUS)[0]
	var poi: Dictionary = field.placed()[target]
	car.global_position = poi["position"] as Vector3
	car.current_speed_kmh = 0.0
	assert_array(field.claim_at(car.global_position, 0.0)).contains([target])
	assert_that(field.is_claimed(target)).is_true()
	# >= because two road networks can cross within a claim radius; what matters
	# is that the board's own reward is in the wallet.
	var banked := _credits()
	assert_that(banked).is_greater_equal(WALLET_BEFORE + Collectibles.reward_of(poi))

	# Re-entering the same spot pays nothing more.
	assert_array(field.claim_at(car.global_position, 0.0)).is_empty()
	assert_that(_credits()).is_equal(banked)

	field.free()
	car.free()

func test_field_physics_tick_claims_a_board_the_car_is_sitting_on() -> void:
	# The shipped path: _physics_process -> simulate_step, no direct call.
	var car := StubCar.new()
	car.name = "StubCar"
	add_child(car)
	var field := CollectibleField.new()
	field.save_on_pause = false
	add_child(field)
	field.player_path = NodePath("../" + car.name)
	var target: String = Collectibles.ids_of_kind(field.placed(), Collectibles.KIND_BONUS)[0]
	var poi: Dictionary = field.placed()[target]
	car.global_position = poi["position"] as Vector3
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_that(field.is_claimed(target)).is_true()
	assert_that(_credits()).is_greater_equal(WALLET_BEFORE + Collectibles.reward_of(poi))
	field.free()
	car.free()

func test_field_grants_career_xp_alongside_the_credits() -> void:
	# The award mirrors the event/race economy path, which pays XP too.
	var field := _make_field()
	var target := Collectibles.ids_of_kind(field.placed(), Collectibles.KIND_BONUS)[0]
	var before := CareerProfile.load_profile(SLOT).xp
	field.claim_at(field.placed()[target]["position"] as Vector3, 0.0)
	assert_that(CareerProfile.load_profile(SLOT).xp).is_greater(before)
	field.free()

func test_field_respects_the_speed_trap_gate() -> void:
	var field := _make_field()
	var trap_id := Collectibles.ids_of_kind(field.placed(), Collectibles.KIND_SPEED_TRAP)[0]
	var trap: Dictionary = field.placed()[trap_id]
	var at := trap["position"] as Vector3
	var target_kmh := Collectibles.speed_target_of(trap)

	# Crawling over the line pays nothing, and the trap stays pending.
	assert_array(field.claim_at(at, 0.0)).not_contains([trap_id])
	assert_that(field.is_claimed(trap_id)).is_false()

	# Over the target it pays exactly once.
	assert_array(field.claim_at(at, target_kmh + 25.0)).contains([trap_id])
	assert_that(field.is_claimed(trap_id)).is_true()
	var banked := _credits()
	assert_array(field.claim_at(at, target_kmh + 25.0)).not_contains([trap_id])
	assert_that(_credits()).is_equal(banked)
	field.free()

func test_field_skips_claimed_collectibles_and_stops_when_drained() -> void:
	var field := _make_field()
	var placed: Dictionary = field.placed()
	var boards := Collectibles.ids_of_kind(placed, Collectibles.KIND_BONUS)
	for collectible_id: String in boards:
		field.claim_at(placed[collectible_id]["position"] as Vector3, 0.0)
	for collectible_id: String in boards:
		assert_that(field.is_claimed(collectible_id)).is_true()
	# Traps and photo spots are still out there, so the field keeps polling, and
	# completion is partial rather than complete.
	assert_that(field.has_pending()).is_true()
	assert_that(field.completion()).is_greater(0.0)
	assert_that(field.completion()).is_less(1.0)
	field.free()

func test_field_is_loop_free_once_everything_is_claimed() -> void:
	var field := _make_field()
	var placed: Dictionary = field.placed()
	for collectible_id: String in placed.keys():
		var poi: Dictionary = placed[collectible_id]
		var speed := 999.0 if Collectibles.kind_of_id(collectible_id) == Collectibles.KIND_SPEED_TRAP else 0.0
		field.claim_at(poi["position"] as Vector3, speed)
	assert_that(field.completion()).is_equal(1.0)
	assert_that(field.has_pending()).is_false()
	assert_that(field.simulate_step()).is_equal(0)
	field.free()

func test_field_state_survives_a_field_rebuild_from_the_same_save() -> void:
	var field := _make_field()
	var target := Collectibles.ids_of_kind(field.placed(), Collectibles.KIND_BONUS)[0]
	field.claim_at(field.placed()[target]["position"] as Vector3, 0.0)
	assert_that(field.save_to_slot()).is_true()
	field.free()

	var reloaded := _make_field()
	assert_that(reloaded.is_claimed(target)).is_true()
	assert_array(reloaded.claim_at(reloaded.placed()[target]["position"] as Vector3, 0.0)).is_empty()
	reloaded.free()

func test_disabled_field_stops_polling() -> void:
	# Event-mode parity: pausing the trigger takes it off the physics loop, and a
	# disabled field never banks a board.
	var field := _make_field()
	assert_that(field.is_enabled()).is_true()
	field.set_enabled(false)
	assert_that(field.is_enabled()).is_false()
	assert_that(field.is_physics_processing()).is_false()
	assert_that(field.simulate_step()).is_equal(0)
	field.set_enabled(true)
	assert_that(field.is_physics_processing()).is_true()
	field.free()

# ---------------------------------------------------------------------------
# Map dot layers: the two maps share one family palette, and both agree with the
# live claim state. This is the layer that makes a speed trap findable.
# ---------------------------------------------------------------------------

## A root holding a road network, because both map layers only resolve their
## POI lists when a road source exists (that is what keeps a circuit map roadless).
func _new_map_root() -> Node:
	var root := Node.new()
	root.name = "CollectibleMapRoot"
	add_child(root)
	_managed.append(root)
	var network := RoadNetwork.new()
	network.name = "RoadNetwork"
	network.add_road([
		Vector3(0.0, 0.0, 0.0),
		Vector3(300.0, 0.0, 0.0),
		Vector3(300.0, 0.0, 300.0),
	], 8.0, false)
	root.add_child(network)
	return root

## A player car at `pos`, registered the way the HUD reads it. Kept OUT of the
## tree on purpose: the maps only ever read global_position, and an unparented
## RigidBody3D cannot start simulating physics inside a headless gate.
func _stub_player(pos: Vector3) -> VehiclePhysics:
	VehicleManager.player_car = null
	var car := VehiclePhysics.new()
	car.name = "StubCar"
	car.position = pos
	VehicleManager.register_player_car(car)
	_managed.append(car)
	return car

func _new_world_map(root: Node) -> Control:
	var map := Control.new()
	map.name = "WorldMap"
	map.size = Vector2(512.0, 384.0)
	map.set_script(load(WORLD_MAP_SCRIPT))
	root.add_child(map)
	return map

func _new_minimap(root: Node) -> Control:
	var minimap := Control.new()
	minimap.name = "Minimap"
	minimap.size = Vector2(200.0, 200.0)
	minimap.set_script(load(MINIMAP_SCRIPT))
	root.add_child(minimap)
	return minimap

## The collectible ids the HUD layer would put a dot on for a player at `at_xz`.
func _minimap_dot_ids(minimap: Control, at_xz: Vector2) -> Array[String]:
	var out: Array[String] = []
	for entry in minimap.collectible_dots_in_range(at_xz):
		out.append(str((entry as Dictionary)["id"]))
	return out

## One palette, two maps: the pause map's pin fill and the HUD dot resolve the
## SAME Collectibles.KIND_DOT_COLOR entry, so a trap cannot be red on one layer
## and road-blue on the other. Asserted on detached instances (no tree needed --
## with no CollectibleField nothing is banked, so the fill is the pure family
## colour) to keep the contract independent of any render pass.
func test_both_maps_resolve_one_shared_family_palette() -> void:
	var minimap := Control.new()
	minimap.set_script(load(MINIMAP_SCRIPT))
	var world_map := Control.new()
	world_map.set_script(load(WORLD_MAP_SCRIPT))
	var placed: Dictionary = Collectibles.place_data(_defs())
	for kind: String in Collectibles.KIND_DOT_COLOR.keys():
		var shared: Color = Collectibles.KIND_DOT_COLOR[kind]
		var ids := Collectibles.ids_of_kind(placed, kind)
		assert_array(ids).is_not_empty()
		var poi: Dictionary = placed[ids[0]]
		assert_that(minimap.collectible_dot_color(kind)).is_equal(shared)
		assert_that(world_map.poi_dot_color(poi)).is_equal(shared)
	# The trap red is the loud one, and a photo spot is cool: the families must be
	# tellable apart at a glance on either map, not by shape alone.
	var red: Color = Collectibles.KIND_DOT_COLOR[Collectibles.KIND_SPEED_TRAP]
	var photo: Color = Collectibles.KIND_DOT_COLOR[Collectibles.KIND_PHOTO]
	assert_that(red.r).is_greater(red.b)
	assert_that(photo.b).is_greater(photo.r)
	minimap.free()
	world_map.free()

## The HUD minimap's own dot table must not drift from the shared palette. It
## exists as an override hook (so HUD art can be retuned without touching world
## code), but today it is required to hold the SAME literals: a trap that is red
## on the pause map and orange on the HUD is the exact bug this milestone fixes.
## An unknown kind falls back through the shared table and then to the road
## colour, so a newly added family can never come out un-drawable.
func test_minimap_dot_table_matches_the_shared_palette() -> void:
	var minimap := Control.new()
	minimap.set_script(load(MINIMAP_SCRIPT))
	for kind: String in Collectibles.KIND_DOT_COLOR.keys():
		assert_that(minimap.collectible_dots[kind]) \
			.is_equal(Collectibles.KIND_DOT_COLOR[kind])
	assert_that(minimap.collectible_dot_color("not_a_family")).is_equal(minimap.road_color)
	minimap.free()

## The trap dot is bigger than the old 3 px blob and carries a visible inner ring,
## because a target the player has to drive at has to out-rank a place you merely
## visit once the roads are drawn under it.
func test_minimap_trap_dot_is_larger_than_a_plain_dot() -> void:
	var minimap := Control.new()
	minimap.set_script(load(MINIMAP_SCRIPT))
	assert_float(float(minimap.collectible_dot_radius)).is_greater(3.0)
	assert_float(float(minimap.collectible_dot_ring_width)).is_greater(0.0)
	assert_float(float((minimap.collectible_dot_ring as Color).a)).is_greater(0.0)
	minimap.free()

## A speed trap is findable on the HUD and it disappears once banked: the player
## sits ON the trap, so the dot list must contain it, and the cull is local by
## design (a couple of km away there is nothing to show). Claiming it through the
## real field removes the dot, and freeing the field entirely (scene change /
## circuit) puts it back rather than leaving a dead reference behind.
func test_minimap_shows_a_nearby_unclaimed_trap_then_drops_it_once_banked() -> void:
	var field := _make_field()
	var root := _new_map_root()
	var trap := POIRegistry.get_poi("speedtrap_0")
	var at := trap["position"] as Vector3
	_stub_player(at)
	var minimap := _new_minimap(root)
	await await_idle_frame()
	await await_idle_frame()

	var here := Vector2(at.x, at.z)
	var ids := _minimap_dot_ids(minimap, here)
	assert_array(ids).contains(["speedtrap_0"])
	# The layer is LOCAL, not a whole-world overlay: far away the trap is culled.
	assert_array(_minimap_dot_ids(minimap, here + Vector2(2000.0, 0.0))).not_contains(["speedtrap_0"])

	# Bank it over the speed gate, exactly as a player would.
	assert_array(field.claim_at(at, Collectibles.speed_target_of(trap) + 25.0)).contains(["speedtrap_0"])
	assert_array(_minimap_dot_ids(minimap, here)).not_contains(["speedtrap_0"])
	# The sibling traps are untouched -- banking one is not a family wipe.
	var sibling := POIRegistry.get_poi("speedtrap_1")["position"] as Vector3
	assert_array(_minimap_dot_ids(minimap, Vector2(sibling.x, sibling.z))).contains(["speedtrap_1"])

	# No field at all (a circuit, or the world torn down under the HUD) must be a
	# clean no-op: nothing is banked, so the dot comes back and nothing errors.
	field.free()
	assert_array(_minimap_dot_ids(minimap, here)).contains(["speedtrap_0"])

## The pause map's claimed look: the trap keeps its pin and its position but reads
## as spent (the one shipped dim formula), while the rest of the family stays
## bright. Asserted against the exact formula so the map keeps ONE claimed look.
func test_world_map_dims_a_banked_trap_and_leaves_the_others_bright() -> void:
	var root := _new_map_root()
	var world_map := _new_world_map(root)
	var red: Color = Collectibles.KIND_DOT_COLOR[Collectibles.KIND_SPEED_TRAP]
	var trap := POIRegistry.get_poi("speedtrap_0")
	# No CollectibleField yet (a circuit scene, or a headless run): nothing is
	# banked, so the pin is the plain family red.
	world_map._rebuild()
	assert_that(world_map.poi_dot_color(trap)).is_equal(red)

	var field := _make_field()
	var at := trap["position"] as Vector3
	assert_array(field.claim_at(at, Collectibles.speed_target_of(trap) + 25.0)).contains(["speedtrap_0"])
	world_map._rebuild()
	var dimmed: Color = world_map.poi_dot_color(trap)
	assert_that(dimmed).is_not_equal(red)
	assert_that(dimmed).is_equal(red.lerp(WorldMap.POI_CLAIMED_TINT, WorldMap.POI_CLAIMED_MIX))
	# Only the banked one is spent.
	assert_that(world_map.poi_dot_color(POIRegistry.get_poi("speedtrap_1"))).is_equal(red)
	# ...and a landmark / event marker is never dimmed by a collectible claim.
	var landmark := POIRegistry.get_poi("festival_hub")
	assert_that(world_map.poi_dot_color(landmark)) \
		.is_equal(world_map._poi_fill_color(landmark))
	field.free()
