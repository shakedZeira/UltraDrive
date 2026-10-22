# tests/suites/test_post_race_cinematic.gd
extends GdUnitTestSuite

## Gate for the post-race cinematic + EXIT button
## (docs/plans/post_race_cinematic_exit_plan.md §5). Two layers under test:
##
##  * CinematicDirector — the PURE decision core (state machine, target cycling,
##    camera offset). No scene, so those cases are plain synchronous asserts.
##  * PostRaceCinematic / RaceUI — the thin adapters. The shell is exercised on a
##    fake Node3D track root with real rigs + a real rival_car.tscn car; the HUD
##    is exercised through scene_runner with its launch_callback spy.
##
## Leak discipline mirrors test_race_results.gd / test_rival_ai.gd: every node and
## car this suite touches is tracked and freed in after_test, and the RaceManager
## / VehicleManager autoload state (which outlives a scene) is reset there.

const HUD_SCENE := "res://scenes/ui/hud.tscn"
const RIVAL_SCENE := "res://scenes/vehicle/rival_car.tscn"
const TRACK_SELECT_SCENE := "res://scenes/ui/track_select.tscn"
const RING_POINTS := 32

var _managed_nodes: Array = []
var _managed_cars: Array = []

func before_test() -> void:
	_managed_nodes.clear()
	_managed_cars.clear()

func after_test() -> void:
	for node in _managed_nodes:
		if is_instance_valid(node):
			node.free()
	for car in _managed_cars:
		if is_instance_valid(car):
			car.free()
	_managed_nodes.clear()
	_managed_cars.clear()
	for child in RaceManager.get_children():
		if child is LapCounter or child is VehiclePhysics:
			child.free()
	RaceManager._spawned_rivals = []
	RaceManager._participants = []
	RaceManager._lap_counters = {}
	RaceManager._checkpoints_dirty = true
	RaceManager.is_race_active = false
	RaceManager.rival_centerline = []
	RaceManager.rival_roster = []
	RaceManager.rival_vehicle_scene = null
	RaceManager._countdown = RaceCountdown.new()
	RaceManager.consume_pending_race()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

# --- Fixtures ----------------------------------------------------------------

## A circle of waypoints (y = 0). The cinematic only needs a loop to cruise, so
## the exact shape is irrelevant; the radius keeps the points well separated.
func _build_ring() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in range(RING_POINTS):
		var angle := float(i) / float(RING_POINTS) * TAU
		points.append(Vector3(cos(angle) * 50.0, 0.0, sin(angle) * 50.0))
	return points

## A fully-formed vehicle (real wheels), frozen so no physics tick moves it
## mid-assert — the same fixture test_rival_ai.gd uses.
func _new_car() -> VehiclePhysics:
	var car := (load(RIVAL_SCENE) as PackedScene).instantiate() as VehiclePhysics
	car.freeze = true
	car.gravity_scale = 0.0
	_managed_cars.append(car)
	return car

func _new_root() -> Node3D:
	var root := Node3D.new()
	add_child(root)
	_managed_nodes.append(root)
	return root

## Put a car on the track, on the ring, and register it as the player.
func _stage_player(line: Array[Vector3]) -> VehiclePhysics:
	var car := _new_car()
	add_child(car)
	car.global_position = line[0]
	VehicleManager.register_player_car(car)
	return car

func _new_cinematic(root: Node3D, dwell: float) -> PostRaceCinematic:
	var cine := PostRaceCinematic.new()
	root.add_child(cine)
	_managed_nodes.append(cine)
	cine.dwell_seconds = dwell
	return cine

# --- CinematicDirector: pure core (§5 T1-T4) ---------------------------------

func test_state_machine_transitions_are_pure() -> void:
	var racing := CinematicDirector.State.RACING
	var finished := CinematicDirector.State.FINISHED
	var cinematic := CinematicDirector.State.CINEMATIC
	var exit_state := CinematicDirector.State.EXIT
	var finish := CinematicDirector.Event.FINISH
	var dwell := CinematicDirector.Event.DWELL_ELAPSED
	var cancel := CinematicDirector.Event.CANCEL
	var exit_event := CinematicDirector.Event.EXIT
	# The four legal edges.
	assert_int(CinematicDirector.advance(racing, finish, 0.0, 6.0)).is_equal(finished)
	assert_int(CinematicDirector.advance(finished, dwell, 6.0, 6.0)).is_equal(cinematic)
	assert_int(CinematicDirector.advance(cinematic, cancel, 0.0, 6.0)).is_equal(finished)
	assert_int(CinematicDirector.advance(finished, exit_event, 0.0, 6.0)).is_equal(exit_state)
	assert_int(CinematicDirector.advance(cinematic, exit_event, 0.0, 6.0)).is_equal(exit_state)
	# Every other (state, event) pair is the identity — a pure, total function.
	for state: int in [racing, finished, cinematic, exit_state]:
		for event: int in [finish, dwell, cancel, exit_event]:
			var expected: int = state
			if event == finish and state == racing:
				expected = finished
			elif event == dwell and state == finished:
				expected = cinematic
			elif event == cancel and state == cinematic:
				expected = finished
			elif event == exit_event and (state == finished or state == cinematic):
				expected = exit_state
			var elapsed := 99.0 if event == dwell else 0.0
			assert_int(CinematicDirector.advance(state, event, elapsed, 6.0)).is_equal(expected)
	# EXIT is absorbing: no event can move off it.
	assert_int(CinematicDirector.advance(exit_state, finish, 99.0, 6.0)).is_equal(exit_state)
	assert_int(CinematicDirector.advance(exit_state, dwell, 99.0, 6.0)).is_equal(exit_state)
	assert_int(CinematicDirector.advance(exit_state, cancel, 99.0, 6.0)).is_equal(exit_state)

func test_dwell_gates_finished_to_cinematic() -> void:
	var finished := CinematicDirector.State.FINISHED
	var cinematic := CinematicDirector.State.CINEMATIC
	var dwell := CinematicDirector.Event.DWELL_ELAPSED
	assert_int(CinematicDirector.advance(finished, dwell, 0.0, 6.0)).is_equal(finished)
	assert_int(CinematicDirector.advance(finished, dwell, 5.9, 6.0)).is_equal(finished)
	assert_int(CinematicDirector.advance(finished, dwell, 6.0, 6.0)).is_equal(cinematic)
	assert_int(CinematicDirector.advance(finished, dwell, 6.0001, 6.0)).is_equal(cinematic)
	# Cancel returns to the card from CINEMATIC, and only from CINEMATIC.
	assert_int(CinematicDirector.advance(cinematic, CinematicDirector.Event.CANCEL, 0.0, 6.0)).is_equal(finished)
	assert_int(CinematicDirector.advance(finished, CinematicDirector.Event.CANCEL, 0.0, 6.0)).is_equal(finished)

func test_target_index_cycles_the_field() -> void:
	assert_int(CinematicDirector.target_index(0, 0.0, 4.0)).is_equal(0)
	assert_int(CinematicDirector.target_index(3, 0.0, 4.0)).is_equal(0)
	assert_int(CinematicDirector.target_index(3, 3.9, 4.0)).is_equal(0)
	assert_int(CinematicDirector.target_index(3, 4.0, 4.0)).is_equal(1)
	assert_int(CinematicDirector.target_index(3, 7.9, 4.0)).is_equal(1)
	assert_int(CinematicDirector.target_index(3, 8.0, 4.0)).is_equal(2)
	assert_int(CinematicDirector.target_index(3, 12.0, 4.0)).is_equal(0)
	assert_int(CinematicDirector.target_index(3, 16.0, 4.0)).is_equal(1)
	# Degenerate inputs never divide by zero or index out of range.
	assert_int(CinematicDirector.target_index(3, 4.0, 0.0)).is_equal(0)
	assert_int(CinematicDirector.target_index(3, -1.0, 4.0)).is_equal(0)
	assert_int(CinematicDirector.target_index(-2, 4.0, 4.0)).is_equal(0)

func test_chase_transform_sits_behind_and_above() -> void:
	# The car sits at the origin facing -Z (identity basis -> forward = -basis.z).
	var target := Transform3D.IDENTITY
	var distance := 9.0
	var height := 4.0
	var shot := CinematicDirector.chase_transform(target.origin, target.basis, distance, height, 0.0)
	# Height is the pure vertical offset; the horizontal reach is `distance`.
	assert_float(shot.origin.y).is_equal_approx(height, 0.0001)
	var flat := Vector3(shot.origin.x, 0.0, shot.origin.z)
	assert_float(flat.length()).is_equal_approx(distance, 0.0001)
	# "Behind" a -Z-facing car is +Z.
	assert_float(flat.z).is_greater(0.0)
	# The camera looks along the car's forward: the basis -Z axis is the view dir.
	var view := -shot.basis.z
	assert_float(view.dot(Vector3(0.0, 0.0, -1.0))).is_greater(0.9)
	# The yaw drift orbits the shot at a constant radius + height (a beauty pass),
	# never changing the distance to the car.
	for yaw: float in [PI * 0.5, PI, PI * 1.5]:
		var drifted := CinematicDirector.chase_transform(target.origin, target.basis, distance, height, yaw)
		assert_float(drifted.origin.y).is_equal_approx(height, 0.0001)
		var d_flat := Vector3(drifted.origin.x, 0.0, drifted.origin.z)
		assert_float(d_flat.length()).is_equal_approx(distance, 0.0001)
	# yaw_drift wraps into [0, TAU).
	assert_float(CinematicDirector.yaw_drift(0.0, 0.12)).is_equal_approx(0.0, 0.0001)
	assert_float(CinematicDirector.yaw_drift(10000.0, 0.12)).is_less(TAU)
	assert_float(CinematicDirector.yaw_drift(10000.0, 0.12)).is_greater_equal(0.0)

# --- PostRaceCinematic shell (§5 T5, T6, T8, T9, T10) ------------------------

func test_cinematic_attaches_auto_driver_and_overrides() -> void:
	var line := _build_ring()
	var car := _stage_player(line)
	var root := _new_root()
	var cine := _new_cinematic(root, 0.0)
	assert_int(cine.state).is_equal(CinematicDirector.State.RACING)
	cine.begin([car], line)
	assert_int(cine.state).is_equal(CinematicDirector.State.FINISHED)
	# A dwell of 0 s enters the cinematic on the first tick.
	assert_int(cine.tick(0.016)).is_equal(CinematicDirector.State.CINEMATIC)
	var driver := car.get_node_or_null(PostRaceCinematic.DRIVER_NODE_NAME) as AIController
	assert_that(driver).is_not_null()
	assert_int(driver.waypoints.size()).is_equal(line.size())
	assert_that(car.scripted_driver).is_true()
	# Force one physics tick of the driver: the car must take a non-zero override
	# (the exact Vector2.ZERO is reserved for "no override -> player input").
	driver._physics_process(0.016)
	assert_that(car.input_override).is_not_equal(Vector2.ZERO)

func test_cinematic_retires_gameplay_rigs() -> void:
	var line := _build_ring()
	var car := _stage_player(line)
	var root := _new_root()
	# Four gameplay rigs, each with a child camera, all processing.
	var rigs: Array[Node3D] = []
	for rig_name in PostRaceCinematic.RIG_NAMES:
		var rig := Node3D.new()
		rig.name = rig_name
		rig.set_process(true)
		rig.set_physics_process(true)
		var cam := Camera3D.new()
		rig.add_child(cam)
		root.add_child(rig)
		rigs.append(rig)
	# The chase rig currently owns the viewport.
	var prior_camera := rigs[0].get_child(0) as Camera3D
	prior_camera.current = true
	var cine := _new_cinematic(root, 0.0)
	cine.begin([car], line)
	cine.tick(0.016)
	assert_int(cine.state).is_equal(CinematicDirector.State.CINEMATIC)
	# Every rig retired: process off and no descendant camera current.
	for rig in rigs:
		assert_that(rig.is_processing()).is_false()
		assert_that(rig.is_physics_processing()).is_false()
		for cam in rig.find_children("*", "Camera3D", false, false):
			assert_that((cam as Camera3D).current).is_false()
	assert_that(cine.camera).is_not_null()
	assert_that(cine.camera.current).is_true()
	assert_that(String(cine.camera.name)).is_equal(PostRaceCinematic.CAMERA_NODE_NAME)
	# Cancel restores exactly what was on: process back, prior camera current.
	cine.stop()
	assert_that(rigs[0].is_processing()).is_true()
	assert_that(prior_camera.current).is_true()
	assert_that(cine.camera.current).is_false()

func test_leaving_cinematic_restores_player_control() -> void:
	var line := _build_ring()
	var car := _stage_player(line)
	var root := _new_root()
	var cine := _new_cinematic(root, 0.0)
	cine.begin([car], line)
	cine.tick(0.016)
	var driver := car.get_node_or_null(PostRaceCinematic.DRIVER_NODE_NAME) as AIController
	assert_that(driver).is_not_null()
	assert_that(car.scripted_driver).is_true()
	# Esc cancels the cinematic via the existing ui_cancel action (no new inputs).
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	cine._unhandled_input(esc)
	assert_int(cine.state).is_equal(CinematicDirector.State.FINISHED)
	assert_that(is_instance_valid(driver)).is_false()
	assert_that(car.input_override).is_equal(Vector2.ZERO)
	assert_that(car.scripted_driver).is_false()
	# The cancel latches: a later tick must not re-enter the cinematic.
	assert_int(cine.tick(CinematicDirector.FINISHED_DWELL_SEC * 2.0)).is_equal(CinematicDirector.State.FINISHED)
	assert_that(car.get_node_or_null(PostRaceCinematic.DRIVER_NODE_NAME)).is_null()

func test_cinematic_is_null_safe_without_track_root() -> void:
	# No Node3D ancestor and no player car: the machine still runs, but no camera
	# node is created and nothing errors (plan §3.3).
	var line := _build_ring()
	var holder := Node.new()
	add_child(holder)
	_managed_nodes.append(holder)
	var cine := PostRaceCinematic.new()
	holder.add_child(cine)
	_managed_nodes.append(cine)
	cine.dwell_seconds = 0.0
	cine.begin([], line)
	assert_int(cine.tick(0.016)).is_equal(CinematicDirector.State.CINEMATIC)
	assert_that(cine.state).is_equal(CinematicDirector.State.CINEMATIC)
	assert_that(cine.get_camera()).is_null()

func test_cinematic_rig_is_reachable_for_recording() -> void:
	# Guards the offline menu-clip capture seam (plan §3.6/§5 T10): a recorder
	# arms the shell and reads its camera by a fixed name. A rename here breaks
	# the follow-up capture harness silently, so it is asserted.
	assert_that(PostRaceCinematic.CAMERA_NODE_NAME).is_equal("CinematicCamera")
	assert_that(PostRaceCinematic.DRIVER_NODE_NAME).is_equal("PostRaceAIDriver")
	var cine := PostRaceCinematic.new()
	add_child(cine)
	_managed_nodes.append(cine)
	for method: String in ["begin", "tick", "stop", "request_exit", "get_camera"]:
		assert_that(cine.has_method(method)).is_true()
	assert_int(cine.state).is_equal(CinematicDirector.State.RACING)
	assert_float(cine.dwell_seconds).is_equal_approx(CinematicDirector.FINISHED_DWELL_SEC, 0.0001)
	# Usable offline: shorten the dwell, then advance frame-by-frame with no race.
	cine.dwell_seconds = 0.0
	cine.begin([], _build_ring())
	assert_int(cine.tick(0.016)).is_equal(CinematicDirector.State.CINEMATIC)
	assert_that(cine.get_camera()).is_null()

# --- RaceUI: EXIT button + teardown (§5 T7, T11, T12) ------------------------

func test_exit_button_launches_track_select() -> void:
	var runner := scene_runner(HUD_SCENE)
	await runner.simulate_frames(1)
	var scene := runner.scene() as RaceUI
	var exit_button := scene.get_node("%ExitButton") as Button
	assert_that(exit_button).is_not_null()
	assert_that(exit_button.text).is_equal("EXIT")
	var launched: Array[String] = []
	scene.launch_callback = func(path: String) -> void: launched.append(path)
	exit_button.emit_signal("pressed")
	assert_that(launched).is_equal([TRACK_SELECT_SCENE])
	assert_that((scene.get_node("%ResultsOverlay") as Control).visible).is_false()

func test_exit_stops_a_live_cinematic() -> void:
	var line := _build_ring()
	var car := _stage_player(line)
	RaceManager._participants.assign([car])
	RaceManager.rival_centerline = line
	var runner := scene_runner(HUD_SCENE)
	await runner.simulate_frames(1)
	var scene := runner.scene() as RaceUI
	var launched: Array[String] = []
	scene.launch_callback = func(path: String) -> void: launched.append(path)
	scene._start_cinematic()
	assert_that(scene._cinematic).is_not_null()
	scene._cinematic.dwell_seconds = 0.0
	scene._cinematic.tick(0.0)
	assert_int(scene._cinematic.state).is_equal(CinematicDirector.State.CINEMATIC)
	var driver := car.get_node_or_null(PostRaceCinematic.DRIVER_NODE_NAME)
	assert_that(driver).is_not_null()
	# EXIT must tear the driver down before the scene navigation fires.
	scene._on_exit()
	assert_that(launched).is_equal([TRACK_SELECT_SCENE])
	assert_that(is_instance_valid(driver)).is_false()
	assert_that(scene._cinematic).is_null()
	assert_that((scene.get_node("%ResultsOverlay") as Control).visible).is_false()

func test_next_race_resets_post_race_state() -> void:
	var line := _build_ring()
	var car := _stage_player(line)
	RaceManager._participants.assign([car])
	RaceManager.rival_centerline = line
	var runner := scene_runner(HUD_SCENE)
	await runner.simulate_frames(1)
	var scene := runner.scene() as RaceUI
	scene._start_cinematic()
	scene._cinematic.dwell_seconds = 0.0
	scene._cinematic.tick(0.0)
	assert_int(scene._post_race_state).is_equal(CinematicDirector.State.CINEMATIC)
	var driver := car.get_node_or_null(PostRaceCinematic.DRIVER_NODE_NAME)
	assert_that(driver).is_not_null()
	# NEXT RACE re-arms the ceremony: the post-race flow must be left behind, or
	# the new grid would inherit a scripted player car.
	(scene.get_node("%NextRaceButton") as Button).emit_signal("pressed")
	assert_int(scene._post_race_state).is_equal(CinematicDirector.State.RACING)
	assert_that(scene._cinematic).is_null()
	assert_that(is_instance_valid(driver)).is_false()
	assert_that(car.input_override).is_equal(Vector2.ZERO)
	assert_that(car.scripted_driver).is_false()
	RaceManager.consume_pending_race()
