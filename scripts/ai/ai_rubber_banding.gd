# scripts/ai/ai_rubber_banding.gd
class_name AIRubberBanding
extends RefCounted

## Calculates AI speed multiplier based on time gap to player.

const BASE_GAP := 2.0   # seconds
const AHEAD_MULT := 0.95  # slightly slower when ahead
const BEHIND_MULT := 1.05  # slightly faster when behind

static func calculate_speed_multiplier(time_gap_seconds: float) -> float:
    ## time_gap_seconds: positive = AI ahead of player, negative = AI behind.
    if time_gap_seconds > BASE_GAP:
        return AHEAD_MULT
    elif time_gap_seconds < -BASE_GAP:
        return BEHIND_MULT
    else:
        return 1.0  # close race, run at base pace