# scripts/world/collectibles.gd
class_name Collectibles
extends RefCounted

## AAA-16 / ROADMAP 2.3 collectibles: FH-style bonus boards, speed traps and
## photo spots placed ON the classified road network, claimed exactly once per
## save, and paid through the SHIPPED economy (Money.wallet_add +
## CareerProfile.grant_xp) so collectible income stacks with race/event income.
##
## Two halves, deliberately one file:
##  * PLACEMENT (static, pure): place_data(defs) -> { collectible_id -> poi } in
##    the exact {name, stage, position} + {kind, tier, road_id, extra, reward}
##    shape POIRegistry already merges event markers in, so the pause-map and
##    minimap dot layers pick the collectibles up for free from
##    POIRegistry.get_poi_ids().
##  * CLAIM LEDGER (instance): the monotonic claimed-id set with the same
##    store/restore/save_to_slot shape WorldDiscovery uses, under the additive
##    "collectibles" save key.
##
## Placement is pure INDEX MATH on the corridor defs — no RNG, no frames, no
## scene access — so the same master-seeded network always yields the same
## collectibles headlessly, exactly like EventRegistry. The three families are
## spread EVENLY ALONG THE WHOLE DRIVABLE NETWORK (one site every
## total_length / count metres, each family phase-offset) rather than
## per-corridor, so they cover the map instead of bunching into the first few
## defs of the plan, and no two share a site.
##
## Collectibles are NOT bound by the 0..6144 base-POI tile bounds: like the
## event markers they ride the real road net (x[-200..9702] z[-2944..8605]).

const GROUP_NAME := "collectible_field"

## Save contract: the claimed-id set lives beside the "discovery" section in the
## slot save, written by SaveManager.save_collectibles().
const SAVE_KEY := "collectibles"
const DEFAULT_SLOT := 0

# ---------------------------------------------------------------------------
# Family taxonomy.
# ---------------------------------------------------------------------------

const KIND_BONUS := "bonus_board"
const KIND_SPEED_TRAP := "speed_trap"
const KIND_PHOTO := "photo_spot"

## Deterministic id prefixes, one per family, mirroring the event marker scheme
## (time_attack_N): "<prefix><0-based index>".
const ID_PREFIX: Dictionary = {
	KIND_BONUS: "bonus_",
	KIND_SPEED_TRAP: "speedtrap_",
	KIND_PHOTO: "photospot_",
}

const KIND_LABEL: Dictionary = {
	KIND_BONUS: "Bonus Board",
	KIND_SPEED_TRAP: "Speed Trap",
	KIND_PHOTO: "Photo Spot",
}

## Per-family MAP DOT colour: the single source of truth both maps resolve
## through kind_color() -- world_map.gd's POI pin fill and minimap.gd's
## collectible_dots table -- so a speed trap is the same red on the pause map
## and on the HUD minimap, and a photo spot never reads as a trap at a glance.
## The trap red is deliberately the loudest of the three: it is the family the
## player has to AIM at, so over a road-coloured network it must never blend in.
const KIND_DOT_COLOR: Dictionary = {
	KIND_BONUS: Color(0.98, 0.82, 0.28),
	KIND_SPEED_TRAP: Color(0.95, 0.42, 0.34),
	KIND_PHOTO: Color(0.55, 0.86, 0.98),
}

## Per-family site count. Twelve bonus boards / eight traps / eight photo spots
## is the honest "dozen-plus" the AAA-16 plan calls for, and matches the order of
## magnitude of the 12 event markers already on the map.
const FAMILY_COUNT: Dictionary = {
	KIND_BONUS: 12,
	KIND_SPEED_TRAP: 8,
	KIND_PHOTO: 8,
}

## Phase salt so a family never starts on the point a sibling family used.
const FAMILY_SALT: Dictionary = {
	KIND_BONUS: 11,
	KIND_SPEED_TRAP: 29,
	KIND_PHOTO: 47,
}

# ---------------------------------------------------------------------------
# Tuning.
# ---------------------------------------------------------------------------

## Perpendicular offset from the road centreline, in metres. Bonus boards and
## speed traps sit dead centre (offset 0) because their whole verb is "drive
## through / over the line"; photo spots are a pull-out beside the tarmac.
const BONUS_OFFSET_M := 0.0
const SPEED_TRAP_OFFSET_M := 0.0
const PHOTO_OFFSET_M := 10.0

## Base credit payout per family before the road-tier multiplier.
const REWARDS: Dictionary = {
	KIND_BONUS: 150,
	KIND_SPEED_TRAP: 400,
	KIND_PHOTO: 250,
}

## A faster road is worth more: the same board on the perimeter highway pays
## more than the same board on a gravel cut-through.
const TIER_REWARD_MULT: Dictionary = {
	RoadDef.Tier.HIGHWAY: 1.5,
	RoadDef.Tier.ARTERIAL: 1.25,
	RoadDef.Tier.TOUGE: 1.0,
	RoadDef.Tier.COASTAL: 1.0,
	RoadDef.Tier.DIRT: 0.75,
}

## Speed-trap target in km/h per road tier: cross the line ABOVE this and the
## trap pays, otherwise it is just a painted stripe.
const TIER_SPEED_TRAP_KMH: Dictionary = {
	RoadDef.Tier.HIGHWAY: 180.0,
	RoadDef.Tier.ARTERIAL: 150.0,
	RoadDef.Tier.TOUGE: 110.0,
	RoadDef.Tier.COASTAL: 130.0,
	RoadDef.Tier.DIRT: 90.0,
}

## XZ claim radius per family (metres). Boards and traps are tight (you hit
## them), photo spots are generous (you park and walk around the shot).
const CLAIM_RADIUS: Dictionary = {
	KIND_BONUS: 12.0,
	KIND_SPEED_TRAP: 18.0,
	KIND_PHOTO: 22.0,
}

const DEFAULT_CLAIM_RADIUS := 15.0
const DEFAULT_SPEED_TRAP_KMH := 120.0

# ---------------------------------------------------------------------------
# Placement (static, pure).
# ---------------------------------------------------------------------------

## { collectible_id -> poi } for all three families on the given corridor defs.
## Pure index math on `defs`, so the same master-seeded network always produces
## the same dictionary (same ids, same positions, same rewards).
static func place_data(defs: Array[RoadDef]) -> Dictionary:
	var out: Dictionary = {}
	for kind: String in ID_PREFIX.keys():
		var sites := _candidate_sites(kind, defs, int(FAMILY_COUNT.get(kind, 0)))
		for i in sites.size():
			var entry := _collectible(kind, i, defs, sites[i])
			out[str(entry["id"])] = entry
	return out

## Sites as (def_index, point_index) pairs, spread EVENLY OVER THE WHOLE
## DRIVABLE NETWORK: the concatenated centreline length is measured, then one
## site is taken every `total / want` metres, each family offset by its own phase
## so a sibling family never lands on the same spot. Unlike a per-corridor
## round-robin this cannot bunch into the first few defs of the plan (the hub
## ring / connector / pass loop) when there are more corridors than collectibles.
static func _candidate_sites(kind: String, defs: Array[RoadDef], want: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if want <= 0:
		return out
	var spans: Array = []
	var total := 0.0
	for def_index in defs.size():
		var def: RoadDef = defs[def_index]
		if def == null or def.points.size() < 2:
			continue
		var chain: Array[Vector3] = def.points
		for i in chain.size() - 1:
			var l := _xz_segment_length(chain[i], chain[i + 1])
			if l <= 0.0:
				continue
			spans.append({"def": def_index, "point": i, "start": total, "len": l})
			total += l
		if def.closed:
			var l := _xz_segment_length(chain[chain.size() - 1], chain[0])
			if l > 0.0:
				spans.append({"def": def_index, "point": chain.size() - 1, "start": total, "len": l})
				total += l
	if total <= 0.0 or spans.is_empty():
		return out
	var spacing := total / float(want)
	var phase := fmod(float(int(FAMILY_SALT.get(kind, 1))) * 0.0173, 1.0)
	for k in want:
		var site := _site_at(spans, (float(k) + phase) * spacing)
		if site.x >= 0:
			out.append(site)
	return out

## The (def, point) owning the centreline position `target` metres into the
## concatenated network; Vector2i(-1, -1) when the target is past the end.
static func _site_at(spans: Array, target: float) -> Vector2i:
	for entry in spans:
		var span := entry as Dictionary
		if target <= float(span["start"]) + float(span["len"]):
			return Vector2i(int(span["def"]), int(span["point"]))
	return Vector2i(-1, -1)

static func _xz_segment_length(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()

static func _collectible(kind: String, index: int, defs: Array[RoadDef], site: Vector2i) -> Dictionary:
	var def: RoadDef = defs[site.x]
	var chain: Array[Vector3] = def.points
	var anchor: Vector3 = chain[site.y]
	var offset := _offset_for(kind)
	var position := anchor
	if offset > 0.0:
		position = anchor + _perpendicular(chain, site.y) * offset
	var extra: Dictionary = {
		"target_kmh": float(TIER_SPEED_TRAP_KMH.get(def.tier, DEFAULT_SPEED_TRAP_KMH)),
		"claim_radius": float(CLAIM_RADIUS.get(kind, DEFAULT_CLAIM_RADIUS)),
		"point_index": site.y,
		"def_index": site.x,
	}
	return {
		"id": "%s%d" % [str(ID_PREFIX.get(kind, "collectible_")), index],
		"kind": kind,
		"name": "%s %d" % [str(KIND_LABEL.get(kind, "Collectible")), index + 1],
		"stage": RoadDef.tier_name(def.tier),
		"tier": def.tier,
		"road_id": def.id,
		"position": position,
		"extra": extra,
		"reward": reward_for_kind(kind, def.tier),
	}

static func _offset_for(kind: String) -> float:
	match kind:
		KIND_PHOTO:
			return PHOTO_OFFSET_M
		KIND_SPEED_TRAP:
			return SPEED_TRAP_OFFSET_M
		_:
			return BONUS_OFFSET_M

## Unit XZ perpendicular to the segment leaving chain[i] (left-hand normal).
static func _perpendicular(chain: Array[Vector3], i: int) -> Vector3:
	var n := chain.size()
	var a: Vector3 = chain[i % n]
	var b: Vector3 = chain[(i + 1) % n]
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if dir.length_squared() < 0.000001:
		return Vector3.RIGHT
	return Vector3(-dir.z, 0.0, dir.x).normalized()

# ---------------------------------------------------------------------------
# Id / metadata queries (static, pure).
# ---------------------------------------------------------------------------

## Family kind for a collectible id, or "" when the id is not a collectible
## (so a base landmark or an event marker is never mistaken for one).
static func kind_of_id(collectible_id: String) -> String:
	for kind: String in ID_PREFIX.keys():
		if collectible_id.begins_with(str(ID_PREFIX[kind])):
			return kind
	return ""

static func is_collectible_id(collectible_id: String) -> bool:
	return not kind_of_id(collectible_id).is_empty()

## The map dot colour for one family, or `fallback` for a kind this build does
## not know (a base landmark / event marker the map colours by zone or tier).
## Pure, so both maps and the headless gate resolve the identical colour for a
## given kind and the two layers can never drift apart.
static func kind_color(kind: String, fallback: Color) -> Color:
	var found: Color = KIND_DOT_COLOR.get(kind, fallback)
	return found

## Collectible ids of one family from a placed dictionary, in ID-INDEX order
## (bonus_0, bonus_1, ... bonus_11 -- NOT lexicographic, which would put
## bonus_10 before bonus_2).
static func ids_of_kind(source: Dictionary, kind: String) -> Array[String]:
	var out: Array[String] = []
	for collectible_id: String in source.keys():
		if kind_of_id(collectible_id) == kind:
			out.append(collectible_id)
	out.sort_custom(_id_index_less)
	return out

static func _id_index_less(a: String, b: String) -> bool:
	return _id_index(a) < _id_index(b)

## Trailing index of a collectible id, e.g. bonus_7 -> 7.
static func _id_index(collectible_id: String) -> int:
	var prefix := str(ID_PREFIX.get(kind_of_id(collectible_id), ""))
	if prefix.is_empty():
		return 0
	return int(collectible_id.trim_prefix(prefix))

static func reward_for_kind(kind: String, tier: int) -> int:
	var base := int(REWARDS.get(kind, 0))
	if base <= 0:
		return 0
	var mult := float(TIER_REWARD_MULT.get(tier, 1.0))
	return int(round(float(base) * mult))

static func reward_of(poi: Dictionary) -> int:
	return int(poi.get("reward", 0))

static func speed_target_of(poi: Dictionary) -> float:
	var extra := poi.get("extra", {}) as Dictionary
	if extra.has("target_kmh"):
		return float(extra["target_kmh"])
	return float(TIER_SPEED_TRAP_KMH.get(int(poi.get("tier", RoadDef.Tier.ARTERIAL)), DEFAULT_SPEED_TRAP_KMH))

static func claim_radius_of(poi: Dictionary) -> float:
	var extra := poi.get("extra", {}) as Dictionary
	if extra.has("claim_radius"):
		return float(extra["claim_radius"])
	return float(CLAIM_RADIUS.get(str(poi.get("kind", "")), DEFAULT_CLAIM_RADIUS))

## XZ-only distance (the map click space convention, matching
## WorldDiscovery.point_segment_distance_xz), so a car on a bridge above a
## roadside spot still counts as being at it.
static func xz_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## Distance from `position` to the nearest centreline point of `def` (XZ). Used
## by the placement gate: every collectible is ON its host road (bonus board /
## speed trap exactly on it) or a fixed shoulder offset away (photo spot).
static func distance_to_road(def: RoadDef, position: Vector3) -> float:
	if def == null:
		return INF
	var chain: Array[Vector3] = def.points
	var best := INF
	for p in chain:
		best = minf(best, xz_distance(position, p))
	return best

# ---------------------------------------------------------------------------
# Claim detection (static, pure) — the rules the runtime trigger and the tests
# share, so "under-speed pays nothing" can be asserted without a scene.
# ---------------------------------------------------------------------------

## True when the player at `position` travelling `speed_kmh` claims `poi`:
## inside the family claim radius, AND above the speed target for a speed trap.
## Bonus boards and photo spots only need the radius (speed is irrelevant).
static func can_claim(poi: Dictionary, position: Vector3, speed_kmh: float) -> bool:
	var target := poi.get("position", Vector3.ZERO) as Vector3
	if xz_distance(position, target) > claim_radius_of(poi):
		return false
	if str(poi.get("kind", "")) == KIND_SPEED_TRAP:
		return speed_kmh >= speed_target_of(poi)
	return true

# ---------------------------------------------------------------------------
# Claim ledger (instance state, monotonic).
# ---------------------------------------------------------------------------

var _claimed: Dictionary = {}

func is_claimed(collectible_id: String) -> bool:
	return _claimed.has(collectible_id)

## Sorted copy of every claimed id (a claim is never un-set: the set is
## monotonic, exactly like WorldDiscovery's visited bits).
func claimed_ids() -> Array[String]:
	var out: Array[String] = []
	for collectible_id: String in _claimed.keys():
		out.append(collectible_id)
	out.sort()
	return out

func claimed_count() -> int:
	return _claimed.size()

## Claims that still describe a placed collectible. `claimed_count()` is the raw
## set size (a save from a larger world can name ids this build no longer
## places), so the completion ratio is always computed against `source`.
func claimed_in(source: Dictionary) -> int:
	var count := 0
	for collectible_id: String in _claimed.keys():
		if source.has(collectible_id):
			count += 1
	return count

## Monotonic completion ratio over the placed collectibles: 0.0 with nothing in
## `source`, 1.0 only when every placed id is claimed. A claim never lowers it.
func completion(source: Dictionary) -> float:
	if source.is_empty():
		return 0.0
	return float(claimed_in(source)) / float(source.size())

## Pays `reward` for `collectible_id` EXACTLY ONCE. Returns the credits banked,
## or 0 when the id is unknown to `source` or was already claimed — the
## double-claim no-op. The caller routes the returned amount through the wallet.
func claim(source: Dictionary, collectible_id: String) -> int:
	if _claimed.has(collectible_id):
		return 0
	if not source.has(collectible_id):
		return 0
	var poi := source[collectible_id] as Dictionary
	var reward := reward_of(poi)
	if reward <= 0:
		return 0
	_claimed[collectible_id] = true
	return reward

## Claims every placed id whose rule `can_claim` accepts (pure; no wallet side
## effect). Returns the ids claimed in this pass, in `source` key order.
## The rule is checked BEFORE `claim()` on purpose: `claim()` is one-way, so an
## under-speed speed trap that was "paid" and then rejected would be burned for
## the rest of the session.
func claim_reachable(source: Dictionary, position: Vector3, speed_kmh: float) -> Array[String]:
	var paid: Array[String] = []
	for collectible_id: String in source.keys():
		if not can_claim(source[collectible_id] as Dictionary, position, speed_kmh):
			continue
		if claim(source, collectible_id) <= 0:
			continue
		paid.append(collectible_id)
	return paid

# ---------------------------------------------------------------------------
# Persistence — the WorldDiscovery save pattern under "collectibles".
# ---------------------------------------------------------------------------

## { SAVE_KEY: {"claimed": [ids...]}} with String ids (JSON object keys are
## strings, and the claimed set is a list so the schema stays stable).
func store() -> Dictionary:
	return {SAVE_KEY: {"claimed": claimed_ids()}}

## Monotonic merge: saved ids are only ever ADDED, so a restore can never
## un-claim a board claimed earlier in the session.
func restore(data: Dictionary) -> void:
	var raw: Variant = data.get(SAVE_KEY, {})
	if raw is Dictionary:
		_merge(raw.get("claimed", []))
		return
	# Tolerate a bare list (a hand-edited or older save) so no claim is lost.
	_merge(raw)

func _merge(list_v: Variant) -> void:
	if not list_v is Array:
		return
	var list: Array = list_v
	for id_v in list:
		if id_v is String and not _claimed.has(id_v):
			_claimed[id_v] = true

func save_to_slot(slot: int = DEFAULT_SLOT) -> bool:
	if SaveManager == null:
		return false
	return SaveManager.save_collectibles(slot, store())

func load_from_slot(slot: int = DEFAULT_SLOT) -> bool:
	if SaveManager == null:
		return false
	var data: Dictionary = SaveManager.load_collectibles(slot)
	if data.is_empty():
		return false
	restore(data)
	return true

func reset() -> void:
	_claimed.clear()
