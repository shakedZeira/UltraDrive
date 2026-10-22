# scripts/world/speed_trap_records.gd
class_name SpeedTrapRecords
extends RefCounted

## Per-trap personal-best ledger for the free-roam speed-trap HUD.
##
## A PURE value object: no scene, no tree, no frame loop. The monotonic best
## rule and the banner string are static, so the headless gate can assert the
## whole core without instantiating anything.
##
## Persistence is additive to the existing slot schema: the best map lives under
## the new top-level "speed_traps" key as {"best": {trap_id: kmh}}, written with
## the GENERIC SaveManager.load_game/save_game read-modify-write pair (the
## EventSession.save_bests pattern), so no new SaveManager accessor is needed and
## every other slot field survives a write.
##
## The ledger is deliberately independent of the collectible CLAIM ledger: a
## trap already banked by an old save still accumulates a best on later passes
## (the money path pays once; a personal best is per pass forever).

const SAVE_KEY := "speed_traps"
const DEFAULT_SLOT := 0

## trap_id (String) -> best km/h (float). Never decreases.
var _best: Dictionary = {}
var _dirty := false

# ---------------------------------------------------------------------------
# Pure rules (no state) — the whole testable core.
# ---------------------------------------------------------------------------

## Strict improvement: only a strictly faster crossing sets a new best, so an
## identical speed is not reported as "NEW BEST!".
static func is_new_best(prev_best: float, speed_kmh: float) -> bool:
	return speed_kmh > prev_best

## The monotonic merge rule: a best never decreases.
static func merged_best(prev_best: float, speed_kmh: float) -> float:
	return maxf(prev_best, speed_kmh)

## The one place a banner string is built, so the text and the best logic can
## never desync. `improved` is the crossing's is_new_best() verdict.
static func banner_text(speed_kmh: float, best_kmh: float, improved: bool) -> String:
	var speed := "%d km/h" % roundi(speed_kmh)
	if improved:
		return "SPEED TRAP — %s · NEW BEST!" % speed
	if best_kmh <= 0.0:
		return "SPEED TRAP — %s" % speed
	return "SPEED TRAP — %s · BEST %d km/h" % [speed, roundi(best_kmh)]

# ---------------------------------------------------------------------------
# State.
# ---------------------------------------------------------------------------

## Recorded best for a trap, or 0.0 when it has never been crossed.
func best_of(trap_id: String) -> float:
	return float(_best.get(trap_id, 0.0))

## Merges a crossing into the ledger and returns whether it IMPROVED. The
## crossing node uses the verdict so is_new_best() is never evaluated twice.
func record(trap_id: String, speed_kmh: float) -> bool:
	var before := best_of(trap_id)
	var after := merged_best(before, speed_kmh)
	if after == before:
		return false
	_best[trap_id] = after
	_dirty = true
	return true

func best_map() -> Dictionary:
	var out: Dictionary = _best.duplicate()
	return out

func is_dirty() -> bool:
	return _dirty

# ---------------------------------------------------------------------------
# Persistence — the EventSession.save_bests read-modify-write, generic accessors.
# ---------------------------------------------------------------------------

func store() -> Dictionary:
	return {"best": _best.duplicate()}

## Monotonic merge from a slot payload. Tolerates:
##  * the shipped shape {"best": {trap_id: kmh}};
##  * a bare {trap_id: kmh} map (a hand-edited or older save), shipped for the
##    same reason Collectibles.restore() tolerates a bare list: no best is lost;
##  * a missing / non-dictionary key (fresh save) — a clean no-op.
## JSON may hand a number back as an int, so every value is floated before the
## comparison.
func restore(data: Dictionary) -> void:
	var raw: Variant = data.get(SAVE_KEY, {})
	var best: Variant = raw
	if raw is Dictionary and (raw as Dictionary).has("best"):
		best = (raw as Dictionary)["best"]
	if not best is Dictionary:
		return
	var map: Dictionary = best
	for key: Variant in map.keys():
		var id := str(key)
		var value := float(map[key])
		if value > best_of(id):
			_best[id] = value
			_dirty = true

## Reads the slot, then merge-writes this ledger back under SAVE_KEY. Every
## other top-level slot field is preserved (read-modify-write).
func save_to_slot(slot: int = DEFAULT_SLOT) -> bool:
	if SaveManager == null:
		return false
	var data: Dictionary = SaveManager.load_game(slot)
	data[SAVE_KEY] = store()
	return SaveManager.save_game(slot, data)

func load_from_slot(slot: int = DEFAULT_SLOT) -> bool:
	if SaveManager == null:
		return false
	restore(SaveManager.load_game(slot))
	return true
