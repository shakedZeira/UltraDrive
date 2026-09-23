class_name CameraMath
extends RefCounted

## Pure camera math shared by the chase/orbit/cockpit cameras and their tests:
## the speed-tied FOV ramp and the chase->orbit->cockpit cycle state machine.

enum Mode { CHASE = 0, ORBIT = 1, COCKPIT = 2 }
const MODE_COUNT := 3

static func fov_for_speed(speed_kmh: float, fov_min: float, fov_max: float) -> float:
	return lerpf(fov_min, fov_max, clampf(speed_kmh / 200.0, 0.0, 1.0))

static func next_mode(index: int, mode_pressed: bool, stick_grabbed: bool) -> int:
	if mode_pressed:
		return (index + 1) % MODE_COUNT
	if stick_grabbed and index != Mode.ORBIT and index != Mode.COCKPIT:
		return Mode.ORBIT
	return index