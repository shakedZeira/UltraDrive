# scripts/race/post_race_cinematic.gd
class_name PostRaceCinematic
extends Node3D

## Thin Node3D adapter for the post-race cinematic (plan
## docs/plans/post_race_cinematic_exit_plan.md §4 Step 2). Owns one Camera3D and,
## when a player car exists and the track published a usable line, an
## AIController child on the player car so the pack keeps racing while the
## camera follows it. Every decision comes from CinematicDirector.
##
## PUBLIC SEAM (also the offline menu-clip recorder's entry point, plan §3.6 /
## §5 T10):
##   begin(standings, line)  arm the machine: enters FINISHED and starts the
##                           dwell clock. `line` is the racing line to cruise.
##   state                   CinematicDirector.State (int); RACING until armed.
##   dwell_seconds           set 0.0 before begin() to skip the dwell in a
##                           harness (the camera goes live on the first tick).
##   tick(delta)             deterministic advance; _process() calls this, so a
##                           harness can drive it frame-by-frame with no race.
##   camera / get_camera()   the owned Camera3D. Null before CINEMATIC and null
##                           when there is no Node3D track root (null-safe
##                           degradation, plan §3.3).
##   request_exit() / stop() teardown (restores the player + frees the driver).
## Signals: cinematic_started (the camera is live), cinematic_ended (the results
## card is due back), exit_requested (RaceUI navigates).
##
## Guarded everywhere: no player car, no track root, no line -> the state
## machine still runs, but no driver is attached and no camera is created.

signal cinematic_started
signal cinematic_ended
signal exit_requested

## Name of the owned camera; part of the recording seam (plan §5 T10).
const CAMERA_NODE_NAME := "CinematicCamera"
## Node name of the auto-driver attached to the player car.
const DRIVER_NODE_NAME := "PostRaceAIDriver"

## Gameplay rigs retired for the duration of the cinematic.
const RIG_NAMES: Array[String] = ["ChaseCamera", "OrbitCamera", "HoodCamera", "CockpitCamera"]

## Chase offset of the cinematic camera (m behind / above the followed car).
const CAMERA_DISTANCE := 9.0
const CAMERA_HEIGHT := 4.0
## Slow yaw drift of the beauty pass (turns per second).
const YAW_DRIFT_RPS := 0.12
## Relaxed cruise pace for the auto-driven player car (AIController clamps to
## 0.5-1.5, plan §3.2).
const CRUISE_SPEED_MULT := 0.55

## Current machine state (CinematicDirector.State). Read-only for callers.
var state: int = CinematicDirector.State.RACING
## Exposed so a harness can shorten or skip the dwell (set 0.0 before begin()).
var dwell_seconds: float = CinematicDirector.FINISHED_DWELL_SEC
## The owned cinematic camera. Null before CINEMATIC and when there is no track
## root to build it under.
var camera: Camera3D = null

## The racing line the auto-driver cruises (empty = no cinematic).
var _line: Array[Vector3] = []
## Standings snapshot passed to begin(); RaceManager.get_standings() is preferred
## per frame, this is the fallback when the autoload has no participants left.
var _standings: Array = []
var _dwell_elapsed: float = 0.0
var _holds_elapsed: float = 0.0
## True when the cinematic must never auto-start: no usable line, or the player
## cancelled it (Esc returns to the results card and stays there).
var _skip_cinematic: bool = false
var _player: VehiclePhysics = null
var _driver: AIController = null
var _track: Node3D = null
# Prior process state of each retired rig, so exit restores exactly what was on.
var _retired_rigs: Array[Node3D] = []
var _rig_prior_process: Array[bool] = []
var _rig_prior_physics: Array[bool] = []
## The rig camera that owned the viewport before the cinematic took it.
var _prev_current_camera: Camera3D = null

func _process(delta: float) -> void:
	tick(delta)

## Arm the cinematic: store the field + line, enter FINISHED and start the dwell
## clock. A line shorter than 2 points is nothing to drive along (solo races,
## flat test tracks), so the cinematic stays parked on the results card instead
## of attaching a driver that would sit still (plan §6).
func begin(standings: Array, line: Array[Vector3]) -> void:
	_standings = standings.duplicate()
	_line.assign(line)
	_dwell_elapsed = 0.0
	_holds_elapsed = 0.0
	_skip_cinematic = _line.size() < 2
	state = CinematicDirector.State.FINISHED

## Deterministic advance of the machine + camera pose. Split out of `_process`
## so a harness (and the tests) can drive it frame-by-frame without a scene.
## Returns the resulting state.
func tick(delta: float) -> int:
	if state == CinematicDirector.State.FINISHED and not _skip_cinematic:
		_dwell_elapsed += delta
		var next := CinematicDirector.advance(
			state, CinematicDirector.Event.DWELL_ELAPSED, _dwell_elapsed, dwell_seconds)
		if next != state:
			state = next
			_enter_cinematic()
	if state == CinematicDirector.State.CINEMATIC:
		_holds_elapsed += delta
		_pose_camera()
	return state

## Teardown for a caller that is NOT exiting (a new race ceremony, a scene
## change). Idempotent, emits no exit signal.
func stop() -> void:
	if state == CinematicDirector.State.CINEMATIC:
		_leave_cinematic()
	_skip_cinematic = true
	state = CinematicDirector.State.RACING

## EXIT: tear the cinematic down, then tell RaceUI to navigate. The machine
## moves FINISHED/CINEMATIC -> EXIT (illegal from RACING, which is the identity).
func request_exit() -> void:
	var next := CinematicDirector.advance(
		state, CinematicDirector.Event.EXIT, 0.0, dwell_seconds)
	if state == CinematicDirector.State.CINEMATIC:
		_leave_cinematic()
	state = next
	exit_requested.emit()

func get_camera() -> Camera3D:
	return camera

## Esc skips/cancels the cinematic and returns to the results card. Reuses the
## existing `ui_cancel` action (no new input actions, plan §4 Step 2).
func _unhandled_input(event: InputEvent) -> void:
	if state != CinematicDirector.State.CINEMATIC:
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	var next := CinematicDirector.advance(
		state, CinematicDirector.Event.CANCEL, 0.0, dwell_seconds)
	if next == state:
		return
	# Latch: a cancelled cinematic must not auto-restart off the stale dwell
	# clock (the player chose the results card).
	_skip_cinematic = true
	_leave_cinematic()
	get_viewport().set_input_as_handled()

## Defensive teardown if the tree releases this node mid-cinematic (scene change
## with the player car still alive). The driver is a child of the CAR, not of
## this node, so it would otherwise outlive the cinematic.
func _exit_tree() -> void:
	if state == CinematicDirector.State.CINEMATIC:
		_leave_cinematic()

# --- Entering / leaving ------------------------------------------------------

func _enter_cinematic() -> void:
	_holds_elapsed = 0.0
	_player = VehicleManager.get_player_car()
	_track = _track_root()
	if _player != null and _line.size() >= 2:
		_attach_driver(_player)
	# Record + clear the gameplay rigs' viewport BEFORE taking it, so exit can
	# restore exactly the camera that was current (plan §6 Camera handoff).
	_retire_gameplay_rigs()
	_build_camera()
	cinematic_started.emit()

func _attach_driver(player: VehiclePhysics) -> void:
	var driver: AIController = AIController.new()
	driver.name = DRIVER_NODE_NAME
	# Child of the car so it ticks with the car's physics (plan §6).
	player.add_child(driver)
	_driver = driver
	driver.set_waypoints(
		_line, CinematicDirector.nearest_index(_line, player.global_position))
	driver.set_speed_multiplier(CRUISE_SPEED_MULT)

func _build_camera() -> void:
	# No Node3D track root -> no camera work at all (headless / HUD-only).
	if _track == null:
		return
	if camera == null or not is_instance_valid(camera):
		camera = Camera3D.new()
		camera.name = CAMERA_NODE_NAME
		add_child(camera)
	camera.current = true
	_pose_camera()

## Restore the player's own control and free the auto-driver. Called on CANCEL,
## on request_exit() and on tear-down; the caller owns the resulting `state`.
func _leave_cinematic() -> void:
	if _driver != null and is_instance_valid(_driver):
		# free() (not queue_free()) so the teardown is observable in the same
		# frame; it is only ever reached from input/signal context, never from
		# inside the driver's own callback.
		_driver.free()
	_driver = null
	if _player != null and is_instance_valid(_player):
		# Never leave the exact Vector2.ZERO unset or scripted_driver latched:
		# the pair is what returns the car to the player (plan §6).
		_player.set_input_override(Vector2.ZERO)
		_player.set_scripted_driver(false)
	_player = null
	_restore_gameplay_rigs()
	if camera != null and is_instance_valid(camera):
		camera.current = false
	state = CinematicDirector.State.FINISHED
	cinematic_ended.emit()

# --- Camera posing -----------------------------------------------------------

func _pose_camera() -> void:
	if camera == null or not is_instance_valid(camera):
		return
	var target := _resolve_target()
	if target == null:
		return
	var yaw := CinematicDirector.yaw_drift(_holds_elapsed, YAW_DRIFT_RPS)
	camera.global_transform = CinematicDirector.chase_transform(
		target.global_position, target.global_basis, CAMERA_DISTANCE, CAMERA_HEIGHT, yaw)

## The car the cinematic follows right now. Prefers RaceManager's live standings
## (leader first) and falls back to the snapshot from begin(); frees are
## filtered out. Null only when there is nothing to follow.
func _resolve_target() -> VehiclePhysics:
	var pool := _live_standings()
	if pool.is_empty():
		if is_instance_valid(_player):
			return _player
		return null
	var index := CinematicDirector.target_index(
		pool.size(), _holds_elapsed, CinematicDirector.CINEMATIC_TARGET_HOLD_SEC)
	var target: VehiclePhysics = pool[clampi(index, 0, pool.size() - 1)]
	return target

func _live_standings() -> Array:
	var source: Array = RaceManager.get_standings()
	if source.is_empty():
		source = _standings
	var out: Array = []
	for entry in source:
		if is_instance_valid(entry) and entry is VehiclePhysics:
			out.append(entry)
	return out

# --- Rig handoff -------------------------------------------------------------

## Nearest Node3D ancestor of this node (the track root the cinematic was added
## under), else a Node3D current scene; null when neither exists.
func _track_root() -> Node3D:
	var node: Node = get_parent()
	while node != null:
		if node is Node3D:
			return node as Node3D
		node = node.get_parent()
	if not is_inside_tree():
		return null
	var scene: Node = get_tree().current_scene
	if scene is Node3D:
		return scene as Node3D
	return null

## Retire the four gameplay rigs exactly as MenuClipRecorder._setup_pan does
## (disable process + clear every descendant Camera3D.current), remembering each
## rig's prior flags and the camera that owned the viewport.
func _retire_gameplay_rigs() -> void:
	if _track == null:
		return
	_retired_rigs.clear()
	_rig_prior_process.clear()
	_rig_prior_physics.clear()
	_prev_current_camera = null
	for rig_name in RIG_NAMES:
		var rig: Node3D = _track.get_node_or_null(rig_name) as Node3D
		if rig == null:
			continue
		_retired_rigs.append(rig)
		_rig_prior_process.append(rig.is_processing())
		_rig_prior_physics.append(rig.is_physics_processing())
		rig.set_process(false)
		rig.set_physics_process(false)
		for cam in rig.find_children("*", "Camera3D", false, false):
			var rig_camera: Camera3D = cam as Camera3D
			if rig_camera == null:
				continue
			if rig_camera.current:
				_prev_current_camera = rig_camera
			rig_camera.current = false

## Inverse of _retire_gameplay_rigs: put each rig's flags back and hand the
## viewport to whichever camera had it. Without this a cancel leaves the player
## with no camera (plan §6).
func _restore_gameplay_rigs() -> void:
	for i in range(_retired_rigs.size()):
		var rig := _retired_rigs[i]
		if not is_instance_valid(rig):
			continue
		rig.set_process(_rig_prior_process[i])
		rig.set_physics_process(_rig_prior_physics[i])
	_retired_rigs.clear()
	_rig_prior_process.clear()
	_rig_prior_physics.clear()
	if _prev_current_camera != null and is_instance_valid(_prev_current_camera):
		_prev_current_camera.current = true
	_prev_current_camera = null
