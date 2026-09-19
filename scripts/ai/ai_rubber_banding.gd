# scripts/ai/ai_rubber_banding.gd
class_name AIRubberBanding
extends RefCounted

## Calculates AI speed multiplier based on time gap to player.

const BASE_GAP := 2.0   # seconds
const AHEAD_MULT := 0.95  # slightly slower when ahead
const BEHIND_MULT := 1.05  # slightly faster when behind

## Rubber-band assist driver category for the player (never scaled).
const CATEGORY_PLAYER := "Player"

## Driver categories that never receive a rubber-band multiplier. Skilled and
## Expert rivals run an exact no-rubber-band pace; traffic and Novice rivals
## are the only rubber-banded competition (when the assist is enabled).
const NO_RUBBER_CATEGORIES := ["Player", "Skilled", "Expert"]

static func multiplier_for(category: String, time_gap_seconds: float, assist_enabled: bool) -> float:
    ## Single entry point for rubber-band scope: returns 1.0 (no adjustment)
    ## unless the category is eligible AND the global assist is on.
    if not assist_enabled or category in NO_RUBBER_CATEGORIES:
        return 1.0
    return calculate_speed_multiplier(time_gap_seconds)

static func calculate_speed_multiplier(time_gap_seconds: float) -> float:
    ## time_gap_seconds: positive = AI ahead of player, negative = AI behind.
    if time_gap_seconds > BASE_GAP:
        return AHEAD_MULT
    elif time_gap_seconds < -BASE_GAP:
        return BEHIND_MULT
    else:
        return 1.0  # close race, run at base pace
