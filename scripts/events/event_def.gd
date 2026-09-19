# scripts/events/event_def.gd
class_name EventDef
extends Resource

## S7 playable event contract. One resource per placed event family: identity
## (type = the placement kind, e.g. "touge_duel"), the scoring objective that
## grades a run (RACE_TIME / TIME_TRIAL / DRIFT_SCORE / HEAD_TO_HEAD), the
## checkpoint chain the run routes through, the target_time / target_score
## band and the base payout EventScoring scales by grade. Pure data: no scene
## access, headless-safe.

enum Objective {
	RACE_TIME = 0,
	TIME_TRIAL = 1,
	DRIFT_SCORE = 2,
	HEAD_TO_HEAD = 3,
}

@export var id: String = ""
@export var type: String = ""
@export var objective: int = Objective.RACE_TIME
@export var name: String = ""
@export var stage: String = ""
@export var tier: int = RoadDef.Tier.ARTERIAL
@export var road_id: String = ""
@export var position: Vector3 = Vector3.ZERO
@export var checkpoints: PackedVector3Array = PackedVector3Array()
@export var target_time: float = 0.0
@export var payout: int = 0
@export var extra: Dictionary = {}

## Laps for countdown-race objectives (night loop / marathon), 1 otherwise.
func laps() -> int:
	return int(extra.get("laps", 1))

func is_score_objective() -> bool:
	return objective == Objective.DRIFT_SCORE

## Finishing condition: any finite, positive result (seconds for time / head-
## to-head runs, DriftScorer points for drift) counts as a completed run.
func is_finished(metric: float) -> bool:
	return is_finite(metric) and metric > 0.0

## The threshold the metric is graded against: target_time for every timed
## objective, extra["target_score"] for drift.
func grade_target() -> float:
	if is_score_objective():
		return float(extra.get("target_score", 0.0))
	return target_time

## Builds an EventDef from the placement dictionary EventRegistry emits
## (place_data / EventDef.all_from keeps the same shape).
static func from_data(event_id: String, data: Dictionary) -> EventDef:
	var def := EventDef.new()
	def.id = event_id
	def.type = String(data.get("kind", event_id))
	def.name = String(data.get("name", event_id))
	def.stage = String(data.get("stage", ""))
	def.tier = int(data.get("tier", RoadDef.Tier.ARTERIAL))
	def.road_id = String(data.get("road_id", ""))
	def.position = data.get("position", Vector3.ZERO) as Vector3
	def.objective = int(data.get("objective_type", Objective.RACE_TIME))
	def.target_time = float(data.get("target_time", 0.0))
	def.payout = int(data.get("payout", 0))
	var raw_cps: Variant = data.get("checkpoints", [])
	if raw_cps is PackedVector3Array:
		def.checkpoints = raw_cps
	elif raw_cps is Array:
		def.checkpoints = PackedVector3Array(raw_cps)
	var raw_extra: Variant = data.get("extra", {})
	def.extra = raw_extra.duplicate() if raw_extra is Dictionary else {}
	return def