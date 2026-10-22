# scripts/race/cinematic_director.gd
class_name CinematicDirector
extends RefCounted

## Pure decision core for the post-race cinematic (plan
## docs/plans/post_race_cinematic_exit_plan.md §3/§4 Step 1). No nodes, no tree
## access, so the state machine, the target cycling and the camera-offset math
## are all unit-testable without a scene — the codebase's RaceGapTracker /
## RacingLine / MenuVideoPlaylist pattern. PostRaceCinematic is the thin Node3D
## adapter that reads the tree and writes the camera/driver; every decision it
## makes comes from a function here.

enum State { RACING, FINISHED, CINEMATIC, EXIT }
enum Event { FINISH, DWELL_ELAPSED, CANCEL, EXIT }

## How long the results card stays up before the cinematic takes over, so the
## player reads the result first and the beauty pass starts on its own.
const FINISHED_DWELL_SEC := 6.0
## How long the cinematic follows one car before cutting to the next.
const CINEMATIC_TARGET_HOLD_SEC := 4.0

## The post-finish state machine, pure and total:
##   FINISH        RACING               -> FINISHED
##   DWELL_ELAPSED FINISHED (>= dwell)  -> CINEMATIC
##   CANCEL        CINEMATIC            -> FINISHED
##   EXIT          FINISHED | CINEMATIC -> EXIT
## Every other (state, event) pair is the identity, so EXIT is absorbing and an
## out-of-order event can never corrupt the machine.
static func advance(state: int, event: int, dwell_elapsed: float, dwell_sec: float) -> int:
	match event:
		Event.FINISH:
			if state == State.RACING:
				return State.FINISHED
		Event.DWELL_ELAPSED:
			if state == State.FINISHED and dwell_elapsed >= dwell_sec:
				return State.CINEMATIC
		Event.CANCEL:
			if state == State.CINEMATIC:
				return State.FINISHED
		Event.EXIT:
			if state == State.FINISHED or state == State.CINEMATIC:
				return State.EXIT
	return state

## Which car the cinematic follows after `elapsed` s: the field is cycled in
## standings order (leader first), one car per `hold_sec`. 0 when there is no
## field (or a degenerate hold). Pure, so the cut schedule is checkable without
## a scene.
static func target_index(count: int, elapsed: float, hold_sec: float) -> int:
	if count <= 0 or hold_sec <= 0.0 or elapsed < 0.0:
		return 0
	return floori(elapsed / hold_sec) % count

## Slow beauty-pass rotation, `fposmod`-wrapped into [0, TAU) so a long take
## cannot drift the yaw into precision loss (project convention: the game clock
## wraps with `fposmod` the same way, see AGENTS.md -> DayNightDriver).
static func yaw_drift(elapsed: float, rate_rps: float) -> float:
	return fposmod(elapsed * rate_rps, TAU)

## Camera transform for the "behind and above" chase: `distance` m behind the
## car along its flattened forward (rotated by `yaw` for the drift), `height` m
## above it, with the basis facing the car. Pure (no node), so the offset
## contract is testable without a viewport.
static func chase_transform(target_pos: Vector3, target_basis: Basis, distance: float, height: float, yaw: float) -> Transform3D:
	var forward := -target_basis.z
	forward.y = 0.0
	if forward.length() < 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var drifted := forward.rotated(Vector3.UP, yaw)
	var origin := target_pos - drifted * distance + Vector3.UP * height
	var to_target := target_pos - origin
	to_target.y = 0.0
	var look_dir := drifted
	if to_target.length() > 0.0001:
		look_dir = to_target.normalized()
	var right := look_dir.cross(Vector3.UP)
	if right.length() < 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	var up := right.cross(look_dir).normalized()
	return Transform3D(Basis(right, up, -look_dir), origin)

## Index of the `line` point nearest `pos` in XZ (Y ignored), mirroring
## RaceManager._nearest_centerline_index so the auto-driver is seeded at the
## car's own place on the loop instead of at index 0 (which would aim a car that
## finished ahead of the start line backwards into the first corner).
static func nearest_index(line: Array[Vector3], pos: Vector3) -> int:
	var best_index := 0
	var best_dist := INF
	for i in range(line.size()):
		var p := line[i]
		var dx := p.x - pos.x
		var dz := p.z - pos.z
		var d := dx * dx + dz * dz
		if d < best_dist:
			best_dist = d
			best_index = i
	return best_index
