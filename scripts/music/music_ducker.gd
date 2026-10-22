# scripts/music/music_ducker.gd
class_name MusicDucker
extends RefCounted

## Explicit ducking (Godot has no bus sidechain). Sources are one-shot (hold,
## then release) or sustained (until cleared). Overlapping sources combine by the
## DEEPEST duck (min), never by summing, clamped to MAX_DUCK_DB.

const MAX_DUCK_DB := -18.0
const ATTACK_S := 0.15
const RELEASE_S := 1.2

## m/s^2, mirrors VehiclePhysics.IMPACT_ACCEL_THRESHOLD (impact() only fires above it).
const CRASH_THRESHOLD := 320.0
const SPEED_TRAP_DB := -5.0
const SPEED_TRAP_HOLD_S := 2.5

# source -> { db, hold, release, age, sustained }
var _sources: Dictionary = {}

## Crash duck depth by impact strength: -6 dB at the threshold .. -12 dB at 3x it.
## 0.0 = no duck (below threshold).
static func crash_duck_db(strength: float) -> float:
	if strength < CRASH_THRESHOLD:
		return 0.0
	var t := clampf((strength - CRASH_THRESHOLD) / (CRASH_THRESHOLD * 2.0), 0.0, 1.0)
	return lerpf(-6.0, -12.0, t)

## Deepest of several duck depths (all <= 0), clamped to MAX_DUCK_DB.
static func combine(depths: Array) -> float:
	var deepest := 0.0
	for d in depths:
		deepest = minf(deepest, float(d))
	return maxf(deepest, MAX_DUCK_DB)

## Move `current_db` toward `target_db`: fast attack (down), slow release (up).
## Rates are expressed against MAX_DUCK_DB so the full range takes ATTACK_S/RELEASE_S.
static func slew_db(current_db: float, target_db: float, delta: float, attack_s: float = ATTACK_S, release_s: float = RELEASE_S) -> float:
	var span := absf(MAX_DUCK_DB)
	if target_db < current_db:
		return maxf(current_db - span / maxf(attack_s, 0.001) * delta, target_db)
	return minf(current_db + span / maxf(release_s, 0.001) * delta, target_db)

## One-shot duck: holds `db` for hold_s, then releases linearly over release_s.
func trigger(source: String, db: float, hold_s: float, release_s: float = 1.5) -> void:
	if db >= 0.0:
		return
	var existing: Dictionary = _sources.get(source, {})
	# A stronger (deeper) duck replaces a weaker running one; same-or-weaker only
	# restarts the hold when it is at least as deep as what remains.
	if not existing.is_empty() and not bool(existing["sustained"]):
		var cur := _level(existing)
		if db > cur:
			return
	_sources[source] = {"db": db, "hold": hold_s, "release": maxf(release_s, 0.001), "age": 0.0, "sustained": false}

## Sustained duck (pause menu, photo mode) until clear().
func hold(source: String, db: float) -> void:
	if db >= 0.0:
		_sources.erase(source)
		return
	_sources[source] = {"db": db, "hold": 0.0, "release": 0.0, "age": 0.0, "sustained": true}

func clear(source: String) -> void:
	_sources.erase(source)

func clear_all() -> void:
	_sources.clear()

func is_active() -> bool:
	return not _sources.is_empty()

func advance(delta: float) -> void:
	var dead: Array[String] = []
	for key in _sources:
		var s: Dictionary = _sources[key]
		if bool(s["sustained"]):
			continue
		s["age"] = float(s["age"]) + delta
		if float(s["age"]) >= float(s["hold"]) + float(s["release"]):
			dead.append(String(key))
	for key in dead:
		_sources.erase(key)

## Deepest current duck across all sources, clamped (<= 0).
func target_db() -> float:
	var depths: Array = []
	for key in _sources:
		depths.append(_level(_sources[key]))
	return combine(depths)

static func _level(s: Dictionary) -> float:
	if bool(s["sustained"]):
		return float(s["db"])
	var age: float = s["age"]
	var hold_s: float = s["hold"]
	if age <= hold_s:
		return float(s["db"])
	var rel: float = s["release"]
	return lerpf(float(s["db"]), 0.0, clampf((age - hold_s) / rel, 0.0, 1.0))
