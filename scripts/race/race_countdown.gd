class_name RaceCountdown
extends RefCounted

## Ceremony gate for race starts: a deterministic "3 / 2 / 1 / GO!" phase
## machine that locks player controls and drives engine-rev anticipation while
## the race is fully armed. Pure state, no nodes or time sources, so it is
## headless-testable with exact delta stepping.

const PHASE_SECONDS: float = 1.0
const GO_SECONDS: float = 0.8
const TOTAL_SECONDS: float = PHASE_SECONDS * 3.0 + GO_SECONDS

## Normalized rev target (0 = idle, 1 = redline) ramps inside each phase.
const REV_RAMP: Array[float] = [0.0, 0.5, 0.85, 1.0]

var _time: float = 0.0

func start() -> void:
	_time = 0.0

func advance(delta: float) -> String:
	_time = maxf(0.0, _time + delta)
	return phase()

func phase() -> String:
	if _time < PHASE_SECONDS:
		return "3"
	if _time < PHASE_SECONDS * 2.0:
		return "2"
	if _time < PHASE_SECONDS * 3.0:
		return "1"
	if _time < TOTAL_SECONDS:
		return "GO"
	return "RACE"

func controls_locked() -> bool:
	return _time < TOTAL_SECONDS

func rev_rpm_override() -> float:
	if _time < PHASE_SECONDS:
		return REV_RAMP[0]
	if _time < PHASE_SECONDS * 2.0:
		return lerpf(REV_RAMP[0], REV_RAMP[1], (_time - PHASE_SECONDS) / PHASE_SECONDS)
	if _time < PHASE_SECONDS * 3.0:
		return lerpf(REV_RAMP[1], REV_RAMP[2], (_time - PHASE_SECONDS * 2.0) / PHASE_SECONDS)
	if _time < TOTAL_SECONDS:
		return lerpf(REV_RAMP[2], REV_RAMP[3], (_time - PHASE_SECONDS * 3.0) / GO_SECONDS)
	return 0.0

func progress() -> float:
	return clampf(_time / TOTAL_SECONDS, 0.0, 1.0)