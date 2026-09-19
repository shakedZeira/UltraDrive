# scripts/race/drift_scorer.gd
class_name DriftScorer
extends RefCounted

## Scores drift segments based on angle, speed, and duration.

var is_drifting := false
var _drift_angle_accum: float = 0.0
var _drift_time: float = 0.0
var _total_score: int = 0
var _drift_depth := 5  # seconds of history

var _drift_history: Array[float] = []  # recent angles

func update(delta: float, slip_angle_deg: float, drifting: bool) -> float:
    ## Call every physics frame. Returns per-frame score contribution.
    if drifting:
        is_drifting = true
        _drift_time += delta
        _drift_angle_accum += slip_angle_deg

        # Track history for combo
        _drift_history.append(slip_angle_deg)
        if _drift_history.size() > _drift_depth:
            _drift_history.pop_front()

        # Score = angle * time bonus
        var angle_bonus := clampf(slip_angle_deg / 45.0, 0.0, 1.0)
        var time_bonus := 1.0 + _drift_time * 0.5
        var frame_score := angle_bonus * time_bonus * 2.0
        _total_score += int(frame_score)
        return frame_score
    else:
        # End of drift
        if is_drifting:
            is_drifting = false
            _drift_angle_accum = 0.0
            _drift_time = 0.0
            _drift_history.clear()
        return 0.0

func get_total_score() -> int:
    return _total_score

func get_drift_time() -> float:
    return _drift_time

func reset() -> void:
    _total_score = 0
    _drift_time = 0.0
    _drift_angle_accum = 0.0
    _drift_history.clear()
    is_drifting = false
