# tests/suites/test_rival_car_audio.gd
extends GdUnitTestSuite

## Rival engine audio gate. Opponents used to be 100% silent: the player scene
## carries an EngineAudio node but scenes/vehicle/rival_car.tscn carried none
## and neither spawn seam created one, so a race grid made no sound. This suite
## locks the fix and its contract:
##   * the rival scene ships a positional (AudioStreamPlayer3D) EngineAudio node
##     with rivals-grade spatial/cull settings (trim < 0, max_distance 60,
##     auto-cull 150 m);
##   * the node builds the same five looping band children as the player;
##   * the extra rival trim lowers the per-band target exactly and stays inside
##     the MUTE_FLOOR_DB..6 dB clamp;
##   * rivals spawned through RaceManager's own seam have the node on Master;
##   * pitch/volume still follow get_drive_info() (the mapping actually runs);
##   * the auto-cull LOD sits BEFORE the _culled early-return, so a culled
##     emitter can still be un-culled (the §6.1 deadlock trap);
##   * a rival never takes the player's shared Master-bus low-pass filter;
##   * the player scene's audio defaults are numerically unchanged (the player
##     mix stays byte-identical).
##
## Headless-safe: the display server is "headless", so the turbo layer is never
## created; only structural/configuration facts are asserted (a test cannot hear
## sound). Every managed node is freed in after_test and the RaceManager /
## VehicleManager autoload state is reset.

const RIVAL_SCENE := "res://scenes/vehicle/rival_car.tscn"
const PLAYER_SCENE := "res://scenes/vehicle/player_car.tscn"
const STARTER_CONFIG := "res://resources/cars/starter_car.tres"

var _managed_cars: Array = []

func before_test() -> void:
	GameState.rubber_band_assist = true
	_managed_cars.clear()
	RaceManager.rival_roster = []
	RaceManager.rival_centerline = []
	RaceManager.rival_vehicle_scene = load(RIVAL_SCENE) as PackedScene
	RaceManager.rival_spawner = Callable()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

func after_test() -> void:
	for car in _managed_cars:
		if is_instance_valid(car):
			car.free()
	_managed_cars.clear()
	for child in RaceManager.get_children():
		if child is LapCounter or child is VehiclePhysics:
			child.free()
	RaceManager._spawned_rivals = []
	RaceManager._participants = []
	RaceManager._lap_counters = {}
	RaceManager.is_race_active = false
	RaceManager._checkpoints_dirty = true
	RaceManager.rival_roster = []
	RaceManager.rival_centerline = []
	# Restore the production rival scene (not null): a later suite in the same
	# shard expects RaceManager's own default to keep spawning rivals.
	RaceManager.rival_vehicle_scene = load(RIVAL_SCENE) as PackedScene
	RaceManager.rival_spawner = Callable()
	RaceManager._countdown = RaceCountdown.new()
	RaceManager.consume_pending_race()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()
	GameState.rubber_band_assist = true

## Awaits `n` PHYSICS frames (fixed 1/60 s steps), the cadence EngineAudio's
## mapping runs at.
func _physics_frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

## Fully-formed rival vehicle, frozen at the origin so no physics tick moves it
## mid-assert (the same staging test_rival_ai uses).
func _new_stub_car() -> VehiclePhysics:
	var car: VehiclePhysics = (load(RIVAL_SCENE) as PackedScene).instantiate() as VehiclePhysics
	car.freeze = true
	car.gravity_scale = 0.0
	_managed_cars.append(car)
	return car

## A registered, in-tree vehicle used as the reference "player" for the
## distance-lookup paths. Its own EngineAudio is detached + freed so the stand-in
## can never install the shared Master-bus LPF or emit into the suite.
func _new_player_stub(pos: Vector3) -> VehiclePhysics:
	var car: VehiclePhysics = _new_stub_car()
	add_child(car)
	car.global_position = pos
	var own: EngineAudio = car.get_node_or_null("EngineAudio") as EngineAudio
	if own != null:
		car.remove_child(own)
		own.free()
	VehicleManager.register_player_car(car)
	return car

# --- the scene edit ---------------------------------------------------------

func test_rival_scene_ships_engine_audio_node() -> void:
	var car: VehiclePhysics = auto_free((load(RIVAL_SCENE) as PackedScene).instantiate()) as VehiclePhysics
	assert_that(car).is_not_null()
	if car == null:
		return
	var audio: EngineAudio = car.get_node_or_null("EngineAudio") as EngineAudio
	assert_that(audio).is_not_null()
	if audio == null:
		return
	# Positional (criterion 2's basis) and player-visible, not a flat bus voice.
	assert_that(audio is AudioStreamPlayer3D).is_true()
	assert_float(audio.extra_trim_db).is_less(0.0)
	assert_that(audio.spatial_max_distance).is_equal_approx(60.0, 0.0001)
	assert_float(audio.auto_cull_range).is_greater(0.0)

func test_rival_audio_builds_five_band_children_with_streams() -> void:
	var car: VehiclePhysics = _new_stub_car()
	add_child(car)
	var audio: EngineAudio = car.get_node_or_null("EngineAudio") as EngineAudio
	assert_that(audio).is_not_null()
	if audio == null:
		return
	# Headless: no turbo children, so the five band players are the whole set.
	assert_int(audio.get_child_count()).is_equal(5)
	for i in range(5):
		var player: AudioStreamPlayer3D = audio.get_child(i) as AudioStreamPlayer3D
		assert_that(player).is_not_null()
		if player == null:
			continue
		assert_that(player.stream is AudioStream).is_true()
		# loop_mode lives on AudioStreamWAV, not the AudioStream base: cast first.
		var wav := player.stream as AudioStreamWAV
		assert_that(wav).is_not_null()
		if wav == null:
			continue
		assert_that(wav.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
		assert_float(player.volume_db).is_less_equal(EngineAudio.MUTE_FLOOR_DB)

# --- trim math --------------------------------------------------------------

func test_band_targets_include_extra_trim() -> void:
	## The production band target is
	##   clampf(band_gain_db(...) + _trim_db + extra_trim_db, MUTE_FLOOR_DB, 6.0)
	## so a negative rival trim must lower the result by exactly that amount and
	## can never push it outside the floor/ceiling.
	var trim := -4.0
	var weights: Array[float] = [1.0, 0.5, 0.1]
	for w: float in weights:
		var base: float = EngineAudio.band_gain_db(w, 0.0, 0.0)
		var trimmed: float = clampf(base + trim, EngineAudio.MUTE_FLOOR_DB, 6.0)
		assert_float(trimmed).is_equal_approx(base + trim, 0.0001)
		assert_float(trimmed).is_between(EngineAudio.MUTE_FLOOR_DB, 6.0)
	# Monotonic in weight, trim applied uniformly.
	var quiet: float = clampf(EngineAudio.band_gain_db(0.1, 0.0, 0.0) + trim, EngineAudio.MUTE_FLOOR_DB, 6.0)
	var loud: float = clampf(EngineAudio.band_gain_db(0.9, 0.0, 0.0) + trim, EngineAudio.MUTE_FLOOR_DB, 6.0)
	assert_float(loud).is_greater(quiet)
	# The floor wins over the trim...
	var floored: float = clampf(EngineAudio.band_gain_db(0.0, 0.0, 0.0) + trim, EngineAudio.MUTE_FLOOR_DB, 6.0)
	assert_float(floored).is_equal_approx(EngineAudio.MUTE_FLOOR_DB, 0.0001)
	# ...and the ceiling is never breached.
	var hot: float = clampf(EngineAudio.band_gain_db(1.0, EngineAudio.LOAD_GAIN_DB, 20.0) + 4.0, EngineAudio.MUTE_FLOOR_DB, 6.0)
	assert_float(hot).is_equal_approx(6.0, 0.0001)

# --- spawned-rival integration ---------------------------------------------

func test_spawned_rivals_have_engine_audio() -> void:
	var player: VehiclePhysics = _new_player_stub(Vector3.ZERO)
	var centerline: Array[Vector3] = NorthernIsleLayout.build_centerline()
	player.global_position = centerline[0] + Vector3(0.0, 1.0, 0.0)
	var cfg: CarConfig = load(STARTER_CONFIG) as CarConfig
	RaceManager.set_rival_centerline(centerline)
	RaceManager.set_rival_roster([
		RaceManager.rival_spec(cfg, "Novice"),
		RaceManager.rival_spec(cfg, "Skilled"),
		RaceManager.rival_spec(cfg, "Expert"),
	])
	RaceManager.start_race([player], 1)
	var spawned: Array[VehiclePhysics] = RaceManager.get_spawned_rivals()
	assert_int(spawned.size()).is_equal(3)
	for car in spawned:
		var audio: EngineAudio = car.get_node_or_null("EngineAudio") as EngineAudio
		assert_that(audio).is_not_null()
		if audio == null:
			continue
		assert_that(audio is AudioStreamPlayer3D).is_true()
		# Master-bus-only wiring (criterion 6): the settings slider scales rivals.
		assert_that(String(audio.bus)).is_equal("Master")
		assert_float(audio.auto_cull_range).is_greater(0.0)

func test_rival_audio_pitch_volume_follow_drive_info() -> void:
	# A bare rival scene ships no config; assign the starter so the mapping has a
	# real bed family / redline to track (production assigns it from the roster
	# spec in _spawn_rival_car, which the spawned-rival test covers separately).
	var car: VehiclePhysics = _new_stub_car()
	car.config = load(STARTER_CONFIG) as CarConfig
	add_child(car)
	await _physics_frames(10)
	var audio: EngineAudio = car.get_node_or_null("EngineAudio") as EngineAudio
	assert_that(audio).is_not_null()
	if audio == null:
		return
	assert_int(audio._band_players.size()).is_equal(5)
	assert_that(car.config).is_not_null()
	if car.config == null:
		return
	# The mapping RAN against the live drive info: band 0's pitch equals the
	# documented rpm/band-rpm ladder value, and its gain climbed off the -80 dB
	# mute floor (the scene default is MUTE_FLOOR_DB).
	var info: Dictionary = car.get_drive_info()
	var rpm: float = float(info.get("rpm", 0.0))
	var timbre: String = car.config.get_engine_bed_set()
	var band_rpms: Array[float] = EngineAudio.band_rpms_for_timbre(timbre)
	var pitch_window: Vector2 = EngineAudio.pitch_window_for_timbre(timbre)
	var expected: float = EngineAudio.band_pitch_scale_window(
		rpm, band_rpms[0], pitch_window.x, pitch_window.y)
	var band0: AudioStreamPlayer3D = audio._band_players[0]
	assert_float(band0.pitch_scale).is_equal_approx(expected, 0.05)
	assert_float(band0.volume_db).is_greater(EngineAudio.MUTE_FLOOR_DB + 6.0)

# --- LOD ordering + LPF isolation ------------------------------------------

func test_auto_cull_culls_far_and_unculls_when_player_returns() -> void:
	var rival: VehiclePhysics = _new_stub_car()
	add_child(rival)
	var audio: EngineAudio = rival.get_node_or_null("EngineAudio") as EngineAudio
	assert_that(audio).is_not_null()
	if audio == null:
		return
	# Shrink the LOD range so the test drives the distance decisively.
	audio.auto_cull_range = 10.0
	var player: VehiclePhysics = _new_player_stub(Vector3(100.0, 0.0, 0.0))
	await _physics_frames(3)
	assert_that(audio._culled).is_true()
	# The deadlock trap (§6.1): the distance check must sit BEFORE the _culled
	# early-return, or a culled emitter could never re-activate -- this un-cull
	# is the regression assertion.
	player.global_position = Vector3.ZERO
	await _physics_frames(3)
	assert_that(audio._culled).is_false()
	assert_float(audio._band_players[0].volume_db).is_greater(EngineAudio.MUTE_FLOOR_DB)

func test_rival_audio_is_not_player_lpf_path() -> void:
	# The stand-in player sits close (inside the rival's 150 m LOD) so the full
	# mapping path runs, proving _is_player stays false for a different car.
	var player: VehiclePhysics = _new_player_stub(Vector3(5.0, 0.0, 0.0))
	assert_that(player).is_not_null()
	var rival: VehiclePhysics = _new_stub_car()
	add_child(rival)
	await _physics_frames(10)
	var audio: EngineAudio = rival.get_node_or_null("EngineAudio") as EngineAudio
	assert_that(audio).is_not_null()
	if audio == null:
		return
	assert_that(audio._is_player).is_false()
	# Rivals must never add effects to the shared Master bus (single-owner LPF).
	assert_that(audio._lpf_added).is_false()

# --- player regression lock + idempotent helper -----------------------------

func test_player_scene_audio_defaults_unchanged() -> void:
	var car: VehiclePhysics = auto_free((load(PLAYER_SCENE) as PackedScene).instantiate()) as VehiclePhysics
	assert_that(car).is_not_null()
	if car == null:
		return
	var audio: EngineAudio = car.get_node_or_null("EngineAudio") as EngineAudio
	assert_that(audio).is_not_null()
	if audio == null:
		return
	# The player path must stay numerically identical: its own spatial values.
	assert_float(audio.spatial_unit_size).is_equal_approx(2.0, 0.0001)
	assert_float(audio.spatial_max_distance).is_equal_approx(80.0, 0.0001)
	assert_float(audio.extra_trim_db).is_equal_approx(0.0, 0.0001)
	assert_float(audio.auto_cull_range).is_equal_approx(0.0, 0.0001)
	# ...and the inherited values the player scene has always serialized.
	assert_float(audio.unit_size).is_equal_approx(2.0, 0.0001)
	assert_float(audio.max_distance).is_equal_approx(80.0, 0.0001)

func test_ensure_for_is_idempotent_and_configures_rivals() -> void:
	# Creation path: a car with no EngineAudio child gets exactly one, rivals-grade.
	var bare: VehiclePhysics = auto_free(VehiclePhysics.new())
	var created: EngineAudio = EngineAudio.ensure_for(bare)
	assert_that(created).is_not_null()
	if created == null:
		return
	assert_float(created.extra_trim_db).is_equal_approx(-4.0, 0.0001)
	assert_float(created.spatial_max_distance).is_equal_approx(60.0, 0.0001)
	assert_float(created.auto_cull_range).is_equal_approx(150.0, 0.0001)
	var again: EngineAudio = EngineAudio.ensure_for(bare)
	assert_that(again).is_same(created)
	var bare_count := 0
	for child in bare.get_children():
		if child is EngineAudio:
			bare_count += 1
	assert_int(bare_count).is_equal(1)
	# No-op path: a car that already ships the node keeps its own instance.
	var rival: VehiclePhysics = _new_stub_car()
	var shipped: EngineAudio = rival.get_node_or_null("EngineAudio") as EngineAudio
	assert_that(shipped).is_not_null()
	var same: EngineAudio = EngineAudio.ensure_for(rival)
	assert_that(same).is_same(shipped)
	var rival_count := 0
	for child in rival.get_children():
		if child is EngineAudio:
			rival_count += 1
	assert_int(rival_count).is_equal(1)
