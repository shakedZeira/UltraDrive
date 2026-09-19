# scripts/events/event_scoring.gd
class_name EventScoring
extends RefCounted

## Pure, deterministic ladder from event metric -> grade -> reward. Timed
## objectives (RACE_TIME / TIME_TRIAL / HEAD_TO_HEAD) grade computed seconds
## against target_time; drift objectives grade a DriftScorer total against
## target_score. No scene access, fixed bands, floats in S/A/B/C out, so the
## rewards route ([drift] DriftScorer tally, [time/marathon] race-manager
## elapsed) and the acceptance suite agree bit-for-bit.

const GRADES: Array[String] = ["S", "A", "B", "C"]

const TIME_S_BAND := 0.90
const TIME_A_BAND := 1.00
const TIME_B_BAND := 1.20
const SCORE_S_BAND := 2.0
const SCORE_A_BAND := 1.5
const SCORE_B_BAND := 1.0

const GRADE_MULTIPLIERS: Dictionary = {"S": 2.0, "A": 1.5, "B": 1.0, "C": 0.5}

## Grade a completed run. Unfinished metrics (zero / non-finite) land on the
## participation grade C; a run that clears the finishing bar grades against
## the objective's own band.
static func grade(def: EventDef, metric: float) -> String:
	if def == null or not def.is_finished(metric):
		return "C"
	if def.is_score_objective():
		return grade_score(metric, def.grade_target())
	return grade_time(metric, def.target_time)

## Lower time is better: ≤0.90 × target = S, ≤1.00 = A, ≤1.20 = B, else C.
static func grade_time(seconds: float, target: float) -> String:
	var band := target if target > 0.0 else 1.0
	var ratio := seconds / band
	if ratio <= TIME_S_BAND:
		return "S"
	if ratio <= TIME_A_BAND:
		return "A"
	if ratio <= TIME_B_BAND:
		return "B"
	return "C"

## Higher score is better: ≥2.0 × target = S, ≥1.5 = A, ≥1.0 = B, else C.
static func grade_score(points: float, target: float) -> String:
	var band := target if target > 0.0 else 1.0
	var ratio := points / band
	if ratio >= SCORE_S_BAND:
		return "S"
	if ratio >= SCORE_A_BAND:
		return "A"
	if ratio >= SCORE_B_BAND:
		return "B"
	return "C"

## Credit award for a grade: base payout scaled by the grade multiplier.
static func reward(def: EventDef, grade: String) -> int:
	var points := def.payout if def != null else 0
	var multiplier := float(GRADE_MULTIPLIERS.get(grade, 1.0))
	return maxi(roundi(points * multiplier), 1)

static func is_valid_grade(grade: String) -> bool:
	return GRADES.has(grade)