# tests/suites/test_race_rivals.gd
extends GdUnitTestSuite

## S5 production-roster gate: GameState.opponents / ai_difficulty drive a real
## field on a real track through the HUD's own start seam.
##
## Covers:
##   * the default roster builder (`RaceManager.configure_default_rivals`):
##     spec count matches GameState.opponents, tiers spread around the difficulty
##     anchor (slot 0 == anchor, all in Novice..Expert), personas attach, and a
##     0-opponent / no-centerline call is a no-op;
##   * the Northern Isle integration path: after the scene publishes its 304-point
##     centerline, the builder fills the roster and `start_race` spawns the field
##     ON the road (within half the track width), facing the tangent of travel;
##   * the cross-race leak fix: `clear_rival_config` (fired on scene_changed)
##     detaches + frees the previous grid and drops the stale roster/centerline;
##   * a bounded drive probe: the grid is committed, the ceremony is skipped, and
##     the field drives forward along the centerline over a FIXED number of
##     physics frames. It asserts only structural facts (still on the track, the
##     field advanced) and prints the measured numbers — never wall-clock or
##     lap-time (the `test_perf_gate` lesson: those are load-sensitive).
##
## Slots 0 and 1 are snapshotted before each test and restored afterwards so real
## player saves stay untouched (mirrors test_rival_personalities.gd).

const NI_SCENE := "res://scenes/track/northern_isle.tscn"
## The production rival vehicle (RaceManager's own default). No scene overrides
## it, so the integration tests must use it instead of leaving it null — a null
## scene AND no spawner makes `_spawn_configured_rivals` bail out spawning nothing.
const RIVAL_SCENE := "res://scenes/vehicle/rival_car.tscn"
const SETTLE_FRAMES := 60
const DRIVE_FRAMES := 300

var _slot_snapshots: Dictionary = {}
var _saved_opponents: int = 0
var _saved_difficulty: String = ""

func before_test() -> void:
	GameState.rubber_band_assist = true
	_saved_opponents = GameState.opponents
	_saved_difficulty = GameState.ai_difficulty
	RaceManager.rival_roster = []
	RaceManager.rival_centerline = []
	RaceManager.rival_vehicle_scene = load(RIVAL_SCENE) as PackedScene
	RaceManager.rival_spawner = Callable()
	RaceManager.roster_personas = []
	RaceManager._car_persona = {}
	RaceManager._recorded_results = {}
	for slot: int in [0, 1]:
		_slot_snapshots[slot] = _snapshot_slot(slot)

func after_test() -> void:
	RaceManager.clear_rival_config()
	# Restore the production rival scene (not null): a later suite in the same
	# shard expects RaceManager's own default to keep spawning rivals.
	RaceManager.rival_vehicle_scene = load(RIVAL_SCENE) as PackedScene
	RaceManager.rival_spawner = Callable()
	for child in RaceManager.get_children():
		if child is LapCounter or child is VehiclePhysics:
			child.free()
	RaceManager._spawned_rivals = []
	RaceManager._participants = []
	RaceManager._lap_counters = {}
	RaceManager.is_race_active = false
	RaceManager._checkpoints_dirty = true
	RaceManager._countdown = RaceCountdown.new()
	RaceManager.consume_pending_race()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()
	GameState.rubber_band_assist = true
	GameState.opponents = _saved_opponents
	GameState.ai_difficulty = _saved_difficulty
	for slot: int in [0, 1]:
		_restore_slot(slot)

# --- slot snapshot/restore (protects real saves) ---------------------------

func _slot_path(slot: int) -> String:
	return SaveManager.SAVE_DIR.path_join("slot_%d.json" % (slot + 1))

func _tmp_path(slot: int) -> String:
	return SaveManager.SAVE_DIR.path_join("slot_%d.json.tmp" % (slot + 1))

func _snapshot_slot(slot: int) -> Dictionary:
	var path := _slot_path(slot)
	var found := FileAccess.file_exists(path)
	var text := ""
	if found:
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			text = file.get_as_text()
			file.close()
	return {"found": found, "text": text}

func _restore_slot(slot: int) -> void:
	var path := _slot_path(slot)
	DirAccess.make_dir_recursive_absolute(SaveManager.SAVE_DIR)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var tmp := _tmp_path(slot)
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	var snap: Dictionary = _slot_snapshots[slot]
	if snap["found"]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(str(snap["text"]))
			file.close()

# --- geometry helpers ------------------------------------------------------

func _nearest_index(line: Array[Vector3], pos: Vector3) -> int:
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

func _lateral_distance_to(line: Array[Vector3], pos: Vector3) -> float:
	var p := line[_nearest_index(line, pos)]
	var dx := p.x - pos.x
	var dz := p.z - pos.z
	return sqrt(dx * dx + dz * dz)

## Forward (wrapping) arc distance along `line` from index `from_idx` to
## `to_idx`, using the layout's uniform spacing.
func _forward_arc(from_idx: int, to_idx: int) -> float:
	var n := NorthernIsleLayout.TOTAL_POINTS
	var steps := (to_idx - from_idx + n) % n
	return float(steps) * NorthernIsleLayout.spacing()

# --- default roster builder ------------------------------------------------

func test_configure_default_rivals_builds_field_with_tier_spread() -> void:
	RaceManager.set_rival_centerline(NorthernIsleLayout.build_centerline())
	GameState.opponents = 5
	GameState.ai_difficulty = "Skilled"
	RaceManager.configure_default_rivals(null, 0)
	assert_int(RaceManager.rival_roster.size()).is_equal(5)
	var personas := RaceManager.get_personas()
	assert_int(personas.size()).is_equal(5)
	# Slot 0 is the anchor itself; every tier is a valid AI_DIFFICULTIES entry.
	assert_that(personas[0].tier).is_equal("Skilled")
	for persona in personas:
		assert_that(GameState.AI_DIFFICULTIES.has(persona.tier)).is_true()
	# The spread ladder [0, -1, 1, 0, -1] around "Skilled"(1) -> [1,0,2,1,0].
	assert_that(personas[1].tier).is_equal("Novice")
	assert_that(personas[2].tier).is_equal("Expert")

func test_configure_default_rivals_respects_difficulty_anchor() -> void:
	RaceManager.set_rival_centerline(NorthernIsleLayout.build_centerline())
	GameState.opponents = 3
	GameState.ai_difficulty = "Novice"
	RaceManager.configure_default_rivals(null, 0)
	var personas := RaceManager.get_personas()
	assert_int(personas.size()).is_equal(3)
	# Novice anchor with spread [0, -1, 1] clamps to [Novice, Novice, Skilled].
	assert_that(personas[0].tier).is_equal("Novice")
	assert_that(personas[1].tier).is_equal("Novice")
	assert_that(personas[2].tier).is_equal("Skilled")
	var specs := RaceManager.rival_roster
	for spec in specs:
		assert_that(spec.has("car_config")).is_true()
		assert_that((spec["car_config"] as CarConfig)).is_not_null()

func test_configure_default_rivals_is_noop_at_zero_or_without_centerline() -> void:
	# Solo practice: 0 opponents builds nothing.
	RaceManager.set_rival_centerline(NorthernIsleLayout.build_centerline())
	GameState.opponents = 0
	RaceManager.configure_default_rivals(null, 0)
	assert_int(RaceManager.rival_roster.size()).is_equal(0)
	# No published centerline: free roam / most scenes are untouched.
	RaceManager.set_rival_centerline([])
	GameState.opponents = 5
	RaceManager.configure_default_rivals(null, 0)
	assert_int(RaceManager.rival_roster.size()).is_equal(0)

# --- Northern Isle integration ---------------------------------------------

func test_northern_isle_race_fields_on_road_rivals() -> void:
	var runner := scene_runner(NI_SCENE)
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return
	# The scene published its centerline to RaceManager.
	assert_int(RaceManager.rival_centerline.size()).is_equal(NorthernIsleLayout.TOTAL_POINTS)
	var player := VehicleManager.get_player_car()
	assert_that(player).is_not_null()
	# The HUD's own start seam path: build the default field, then commit.
	GameState.opponents = 5
	GameState.ai_difficulty = "Skilled"
	RaceManager.configure_default_rivals(player, 0)
	assert_int(RaceManager.rival_roster.size()).is_equal(5)
	RaceManager.start_race(VehicleManager.get_all_cars(), 3)
	var spawned := RaceManager.get_spawned_rivals()
	assert_int(spawned.size()).is_equal(5)
	var line: Array[Vector3] = RaceManager.rival_centerline
	var half_width := NorthernIsleLayout.WIDTH * 0.5
	for car in spawned:
		# On the road: within half the track width of the centerline.
		assert_float(_lateral_distance_to(line, car.global_position)).is_less_equal(half_width)
		# Facing the tangent of travel.
		var car_forward := -car.global_basis.z
		car_forward.y = 0.0
		var idx := _nearest_index(line, car.global_position)
		var tangent := line[(idx + 1) % line.size()] - line[idx]
		tangent.y = 0.0
		assert_float(car_forward.normalized().dot(tangent.normalized())).is_greater(0.9)
	# Every rival is a standings participant with a distinct persona.
	assert_int(RaceManager.get_standings().size()).is_equal(6)
	var personas := RaceManager.get_personas()
	assert_int(personas.size()).is_equal(5)
	for car in spawned:
		assert_that(RaceManager.get_persona_for(car)).is_not_null()

# --- cross-race leak fix ----------------------------------------------------

func test_clear_rival_config_frees_grid_and_drops_state() -> void:
	var runner := scene_runner(NI_SCENE)
	await runner.simulate_frames(3)
	if runner.scene() == null:
		return
	GameState.opponents = 3
	RaceManager.configure_default_rivals(VehicleManager.get_player_car(), 0)
	RaceManager.start_race(VehicleManager.get_all_cars(), 3)
	var spawned := RaceManager.get_spawned_rivals()
	assert_int(spawned.size()).is_equal(3)
	for car in spawned:
		assert_that(car.is_inside_tree()).is_true()
	RaceManager.clear_rival_config()
	for car in spawned:
		# Immediately detached from RaceManager (deferred free completes later).
		assert_that(car.get_parent()).is_null()
	assert_int(RaceManager.get_spawned_rivals().size()).is_equal(0)
	assert_int(RaceManager.rival_roster.size()).is_equal(0)
	assert_int(RaceManager.rival_centerline.size()).is_equal(0)
	assert_int(RaceManager.get_personas().size()).is_equal(0)

# --- bounded drive probe ----------------------------------------------------

## Awaits `n` PHYSICS frames (fixed 1/60 s steps). `simulate_frames` awaits IDLE
## frames instead, and headless idle frames run faster than 60 Hz, so an
## idle-frame budget silently buys far less simulated time — and a much weaker
## progress signal — than its name implies.
func _simulate_physics_frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func test_rivals_drive_forward_along_centerline_within_bounded_frames() -> void:
	var runner := scene_runner(NI_SCENE)
	await runner.simulate_frames(3)
	if runner.scene() == null:
		return
	GameState.opponents = 3
	GameState.ai_difficulty = "Skilled"
	RaceManager.configure_default_rivals(VehicleManager.get_player_car(), 0)
	RaceManager.start_race(VehicleManager.get_all_cars(), 3)
	# Skip the 3-2-1-GO ceremony: controls stay locked (globally, for every car)
	# until the countdown elapses, and a locked car zeroes the scripted
	# input_override, so nothing would move otherwise. Jump past TOTAL_SECONDS.
	RaceManager.get_countdown().advance(RaceCountdown.TOTAL_SECONDS + 0.5)
	var line: Array[Vector3] = RaceManager.rival_centerline
	var rivals := RaceManager.get_spawned_rivals()
	assert_int(rivals.size()).is_equal(3)
	# Let the field settle out of the grid (turn back onto the racing line), then
	# measure forward progress over a FIXED physics-frame budget. The grid sits
	# just ahead of waypoint 0, so the drivers first turn onto the line —
	# measuring after the settle window isolates actual lap progress from that.
	await _simulate_physics_frames(SETTLE_FRAMES)
	var start_index: Dictionary = {}
	for car in rivals:
		start_index[car] = _nearest_index(line, car.global_position)
	await _simulate_physics_frames(DRIVE_FRAMES)
	var total := 0.0
	var best := 0.0
	var moving := 0
	var max_speed := 0.0
	# More than half a lap of "forward" arc in a few seconds is impossible; it can
	# only mean a car drifted BACKWARD across the wrap and the wrapping arc
	# wrapped around. Treat that as zero progress so a stalled field cannot pass.
	var artifact := NorthernIsleLayout.perimeter() * 0.5
	for car in rivals:
		var advanced := _forward_arc(start_index[car], _nearest_index(line, car.global_position))
		var lateral := _lateral_distance_to(line, car.global_position)
		var speed := car.linear_velocity.length()
		if advanced > artifact:
			advanced = 0.0
		print("[race_rivals] rival advance=%.1f m lateral=%.1f m speed=%.1f m/s" % [
			advanced, lateral, speed])
		total += advanced
		best = maxf(best, advanced)
		max_speed = maxf(max_speed, speed)
		if advanced > 5.0:
			moving += 1
		# The field stayed on the track (did not spin off into the grass).
		assert_float(lateral).is_less_equal(NorthernIsleLayout.WIDTH * 0.5 + 1.0)
	print("[race_rivals] drive: best=%.1f m total=%.1f m max_speed=%.1f m/s moving=%d/%d" % [
		best, total, max_speed, moving, rivals.size()])
	# Bounded, structural assertions only — the printed numbers are the honest
	# report; no wall-clock / lap-time is asserted (load-insensitive).
	assert_float(best).is_greater(5.0)
	assert_that(moving).is_greater_equal(2)
	assert_float(total).is_greater(15.0)
