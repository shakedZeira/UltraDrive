# scripts/race/best_lap_records.gd
class_name BestLapRecords
extends RefCounted

## Cross-session best-lap records (roadmap #7). Records are keyed per
## (track id, car class) so a D-class record on Sunset Oval never bleeds into
## the B-class record on Mountain Pass, and persisted as its OWN additive
## SaveManager section — exactly the WorldDiscovery pattern: store()/restore()
## own the pure dict format, save_to_slot()/load_from_slot() bridge the 3-slot
## schema, and restore() MERGES by keeping the faster time so a load can never
## degrade a record or clobber another section of the same slot.
##
## Pure RefCounted: no frames, no scene access, every helper headless-testable.

## Save-slot sub-dict key. Mirrored by SaveManager.BEST_LAPS_KEY; the wrapper
## form ({SAVE_KEY: {...}}) matches WorldDiscovery.store() so the on-disk
## layout reads the same as every other section.
const SAVE_KEY := "best_laps"
const DEFAULT_SLOT := 0

## Fallback identities for a run with no registered track scene or no car
## config (free roam, a scene not in TrackRegistry, a headless harness). They
## are stable strings so those laps still get their own bucket instead of
## collapsing into one shared "any track" record.
const UNKNOWN_TRACK := "unknown"
const UNKNOWN_CAR_CLASS := "D"

## "<track>|<class>" -> best lap seconds (float, > 0).
var _records: Dictionary = {}

## Slot key for a (track, class) pair. Track ids are used verbatim; car classes
## are upper-cased so "d" and "D" can never split a record.
static func key_for(track_id: String, car_class: String) -> String:
	return "%s|%s" % [normalize_track(track_id), normalize_class(car_class)]

static func normalize_track(track_id: String) -> String:
	var trimmed := track_id.strip_edges()
	return trimmed if trimmed != "" else UNKNOWN_TRACK

static func normalize_class(car_class: String) -> String:
	var trimmed := car_class.strip_edges().to_upper()
	return trimmed if trimmed != "" else UNKNOWN_CAR_CLASS

## The stored record for a pair, or 0.0 when the pair has never been set.
func get_record(track_id: String, car_class: String) -> float:
	return float(_records.get(key_for(track_id, car_class), 0.0))

## True when `lap_time` would beat the stored record for the pair.
func is_improvement(track_id: String, car_class: String, lap_time: float) -> bool:
	if lap_time <= 0.0:
		return false
	var current := get_record(track_id, car_class)
	return current <= 0.0 or lap_time < current

## In-memory submit: keeps the faster of the stored record and `lap_time`.
## Returns true only when `lap_time` became the new record. Non-positive lap
## times are rejected outright (an unset lap is not a record).
func record_lap(track_id: String, car_class: String, lap_time: float) -> bool:
	if lap_time <= 0.0:
		return false
	return _merge_best(key_for(track_id, car_class), lap_time)

func _merge_best(key: String, seconds: float) -> bool:
	var current := float(_records.get(key, 0.0))
	if current > 0.0 and current <= seconds:
		return false
	_records[key] = seconds
	return true

## Serialized form for the slot: { SAVE_KEY: { "<track>|<class>": seconds } }
## with String keys, because JSON object keys are strings.
func store() -> Dictionary:
	return {SAVE_KEY: _records.duplicate()}

## Merges saved records in, keeping the faster time per key. Monotonic in the
## same spirit as WorldDiscovery.restore(): garbage values (non-positive,
## missing, wrong-typed) are dropped rather than poisoning a record.
func restore(data: Dictionary) -> void:
	var raw: Variant = data.get(SAVE_KEY, {})
	if not (raw is Dictionary):
		return
	var records: Dictionary = raw
	for key: Variant in records:
		var seconds := float(records[key])
		if seconds <= 0.0:
			continue
		_merge_best(String(key), seconds)

func clear() -> void:
	_records.clear()

func size() -> int:
	return _records.size()

func keys() -> Array:
	return _records.keys()

func save_to_slot(slot: int = DEFAULT_SLOT) -> bool:
	if SaveManager == null:
		return false
	return SaveManager.save_best_laps(slot, store())

func load_from_slot(slot: int = DEFAULT_SLOT) -> bool:
	if SaveManager == null:
		return false
	var data: Dictionary = SaveManager.load_best_laps(slot)
	if data.is_empty():
		return false
	restore(data)
	return true

## One-shot read: the persisted best for a pair, or 0.0 when never set. Used by
## the HUD at session start to seed the best-lap readout.
static func load_record(track_id: String, car_class: String, slot: int = DEFAULT_SLOT) -> float:
	if SaveManager == null:
		return 0.0
	var records := BestLapRecords.new()
	if not records.load_from_slot(slot):
		return 0.0
	return records.get_record(track_id, car_class)

## Load / compare / write round trip against the slot — the whole persistence
## flow the race-finish path uses. Returns true when `lap_time` beat the stored
## record AND was written back. A non-positive lap time never writes, a worse
## lap never overwrites, and the section merge leaves every other (track, class)
## pair (and every other slot field) untouched.
static func submit_lap(
	track_id: String, car_class: String, lap_time: float, slot: int = DEFAULT_SLOT
) -> bool:
	if lap_time <= 0.0 or SaveManager == null:
		return false
	var records := BestLapRecords.new()
	records.load_from_slot(slot)
	if not records.record_lap(track_id, car_class, lap_time):
		return false
	return records.save_to_slot(slot)
