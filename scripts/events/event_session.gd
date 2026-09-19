# scripts/events/event_session.gd
class_name EventSession
extends Node

## S7 start/end bridge: "Start event" makes a placed EventDef playable, feeds
## a themed metric (drift: live DriftScorer total; time/head-to-head:
## completion seconds, marathon checkpoint-chain time) into EventScoring, and
## emits event_completed(event_def, grade, reward) — exactly one award per
## completed event, banked into the S7 stub Money ledger (item 11 swaps the
## ledger backend, the zero-sum accounting contract stays). Best time/score per
## event id persists under SAVE_KEY in the slot save. While an event is active,
## ambient traffic (LivingWorld / TrafficSpawner) and the day-night clock
## (DayNightDriver) are paused via set_enabled() and the player is gated to
## the event bounds. Every dependency is optional, so the node loads
## headlessly in an empty tree.

signal event_started(event_def: EventDef)
signal event_completed(event_def: EventDef, grade: String, reward: int)
signal event_bounds_left(event_def: EventDef)

const SAVE_KEY := "events"
const DEFAULT_SLOT := 0
const DEFAULT_BOUNDS_RADIUS := 900.0

## The base POI anchors EventRegistry.place derives time-attack sites from
## (same list POIRegistry seeds, kept explicit so get_defs() is pure).
const BASE_POI_IDS: Array[String] = [
	"festival_hub", "lowland_view", "dry_lake", "pass_entry", "alpine_overlook",
]

@export var living_world_path: NodePath = NodePath("../LivingWorld")
@export var traffic_path: NodePath = NodePath("../TrafficSpawner")
@export var player_path: NodePath = NodePath("%PlayerCar")

## S7 stub ledger (item 11 replaces the backend; the accounting contract is
## exercised by the acceptance suite).
var money := Money.new()

var _active: EventDef = null
var _scorer := DriftScorer.new()
var _startlights := RaceCountdown.new()
var _startlights_armed := false
var _bounds_radius := DEFAULT_BOUNDS_RADIUS
var _bests: Dictionary = {}
var _defs_cache: Dictionary = {}

func _ready() -> void:
	_bests = _load_bests()

# -- Placed-event lookup ------------------------------------------------------

## Lazy, cached EventDef taxonomy: all 8 families placed on the master-seeded
## road network. Detached from the scene tree, so headless tests never need a
## world instance.
func get_defs() -> Dictionary:
	if _defs_cache.is_empty():
		var corridor_defs: Array[RoadDef] = CorridorPlanner.plan(CorridorPlanner.MASTER_SEED, Callable(), {})
		_defs_cache = EventRegistry.place_defs(corridor_defs, _anchors())
	return _defs_cache

func get_event_ids() -> Array[String]:
	var ids: Array[String] = []
	for event_id: String in get_defs().keys():
		ids.append(event_id)
	return ids

func get_event_def(event_id: String) -> EventDef:
	return get_defs().get(event_id) as EventDef

func has_event(event_id: String) -> bool:
	return get_defs().has(event_id)

func _anchors() -> Array[Vector3]:
	var anchors: Array[Vector3] = []
	for poi_id: String in BASE_POI_IDS:
		var poi: Dictionary = POIRegistry.pois.get(poi_id, {})
		if poi.has("position"):
			anchors.append(poi["position"] as Vector3)
	return anchors

# -- Start / finish -----------------------------------------------------------

func is_event_active() -> bool:
	return _active != null

func get_active_event() -> EventDef:
	return _active

## "Start event": arms the placed EventDef, pauses ambient traffic/clock, and
## routes timed objectives through the RaceManager countdown seam (item 1's
## request_race). Drag arms launch startlights instead; drift needs no race
## ceremony, the live DriftScorer accumulates during play. Returns false when
## an event is already running or the id is unknown.
func start_event(event_id: String) -> bool:
	if _active != null:
		return false
	var def := get_event_def(event_id)
	if def == null:
		return false
	_active = def
	_scorer.reset()
	_startlights_armed = false
	_startlights = RaceCountdown.new()
	_pause_ambient(true)
	if not def.is_score_objective():
		RaceManager.request_race(def.laps())
		if def.type == "drag_strip":
			launch_startlights()
	event_started.emit(def)
	return true

## Drag-discipline start lights: a fresh RaceCountdown ceremony behind the
## request_race seam (minimal stub; the physics launch reaction is item 12+).
func launch_startlights() -> void:
	_startlights.start()
	_startlights_armed = true

## Current start-light phase ("3" / "2" / "1" / "GO" / "RACE"), "" when not
## armed. headless-testable with exact delta stepping like RaceCountdown.
func startlights_state() -> String:
	if not _startlights_armed:
		return ""
	return _startlights.phase()

func startlights_advance(delta: float) -> String:
	if not _startlights_armed:
		return ""
	return _startlights.advance(delta)

## Live feed while a DRIFT_SCORE event is active: forwards straight into the
## DriftScorer whose total grades the zone on completion.
func tick_drift(delta: float, slip_angle_deg: float, drifting: bool) -> void:
	if _active != null and _active.is_score_objective():
		_scorer.update(delta, slip_angle_deg, drifting)

func get_drift_score() -> int:
	return _scorer.get_total_score()

## Completion seam: any event that reached its finishing condition submits one
## metric (run seconds, or DriftScorer points for drift). Emits exactly one
## event_completed, banks the reward, persists the best result and resumes the
## ambient world. Returns {grade, reward} when an event was active, else {}.
func submit_result(metric: float) -> Dictionary:
	if _active == null:
		return {}
	var def := _active
	var grade := EventScoring.grade(def, metric)
	var reward := EventScoring.reward(def, grade)
	_active = null
	_startlights_armed = false
	_pause_ambient(false)
	_record_best(def, metric)
	money.add(reward)
	event_completed.emit(def, grade, reward)
	return {"grade": grade, "reward": reward}

## Drift shorthand: grades the active zone from the live DriftScorer total.
func complete_drift() -> Dictionary:
	if _active == null or not _active.is_score_objective():
		return {}
	return submit_result(float(_scorer.get_total_score()))

## Out-of-bounds / abandoned run: still a completion, participation grade C,
## still exactly one award (so the ledger and the signal stay one-to-one).
func fail_event() -> Dictionary:
	if _active == null:
		return {}
	return submit_result(0.0)

# -- Event bounds gate --------------------------------------------------------

func set_bounds_radius(radius: float) -> void:
	_bounds_radius = maxf(radius, 0.0)

func get_bounds_radius() -> float:
	return _bounds_radius

## True when the player has drifted outside the active event's bounds (event
## gating: leaving the corridor ends the run so checked-out runs never farm
## free rewards).
func is_player_outside_bounds(player_pos: Vector3) -> bool:
	if _active == null:
		return false
	return player_pos.distance_to(_active.position) > _bounds_radius

func _physics_process(_delta: float) -> void:
	if _active == null:
		return
	var player := get_node_or_null(player_path) as Node3D
	if player == null:
		return
	if is_player_outside_bounds(player.global_position):
		event_bounds_left.emit(_active)
		fail_event()

# -- Ambient world pause / resume ----------------------------------------------

## Event mode pauses ambient life: living-world traffic feed, the traffic
## spawner tick and the day-night clock all drop behind the set_enabled()
## no-op gates until the run ends.
func _pause_ambient(paused: bool) -> void:
	var enabled := not paused
	var living := get_node_or_null(living_world_path) as Node
	if living != null and living.has_method("set_enabled"):
		living.call("set_enabled", enabled)
	var traffic := get_node_or_null(traffic_path) as Node
	if traffic != null and traffic.has_method("set_enabled"):
		traffic.call("set_enabled", enabled)
	if DayNightDriver.has_method("set_enabled"):
		DayNightDriver.set_enabled(enabled)

# -- Best-result persistence ---------------------------------------------------

## Best metric per event id: fastest seconds for timed objectives, highest
## total for drift. 0.0 for events with no recorded run yet.
func get_best(event_id: String) -> float:
	return float(_bests.get(event_id, 0.0))

func _record_best(def: EventDef, metric: float) -> void:
	if not def.is_finished(metric):
		return
	if def.is_score_objective():
		if metric > float(_bests.get(def.id, 0.0)):
			_bests[def.id] = metric
	else:
		var prev := float(_bests.get(def.id, INF))
		if metric < prev:
			_bests[def.id] = metric

## Merge-writes the best-result table into the slot save under SAVE_KEY
## (read-modify-write, preserves every other slot field).
func save_bests() -> bool:
	if SaveManager == null:
		return false
	var data := SaveManager.load_game(DEFAULT_SLOT)
	data[SAVE_KEY] = _bests
	return SaveManager.save_game(DEFAULT_SLOT, data)

func _load_bests() -> Dictionary:
	if SaveManager == null:
		return {}
	var data := SaveManager.load_game(DEFAULT_SLOT)
	var stored: Variant = data.get(SAVE_KEY, {})
	return stored.duplicate() if stored is Dictionary else {}