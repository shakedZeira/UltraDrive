# tests/suites/test_rival_personalities.gd
extends GdUnitTestSuite

## A4 gate: nameable persistent rival personalities. Covers the pure RivalPersona
## roster builder (deterministic per seed, tiers mirror the roster spec, names
## come from the fixed pool), W/L recording (exactly once per finished rival,
## W ahead of the player / L behind, idempotent against a re-fired finish),
## save/load round-trip under the "rival_personas" slot sub-dict (records + seed
## survive, other slot keys preserved), RaceManager attaching personas to a
## roster, and the presentation surface (grid card + live standings + results
## read the handle/record). The rendezvous for rivals is the additive slot
## schema: slots are snapshotted before each test and restored in after_test so
## real player saves stay untouched (mirrors test_profile_slots.gd).
##
## The rival AI invariants (tier pacing, no rubber-band on the player) are
## re-asserted here at the logic level; test_rival_ai.gd still owns the full
## racing-line/pace gate and must stay green unchanged.

const RIVAL_SCENE := "res://scenes/vehicle/rival_car.tscn"
const CheckpointStub := preload("res://tests/suites/checkpoint_stub.gd")
const RING_POINTS := 48

var _managed_cars: Array = []
var _managed_stubs: Array = []
var _slot_snapshots: Dictionary = {}

func before_test() -> void:
	GameState.rubber_band_assist = true
	_managed_cars.clear()
	_managed_stubs.clear()
	RaceManager.rival_roster = []
	RaceManager.rival_centerline = []
	RaceManager.rival_vehicle_scene = null
	RaceManager.rival_spawner = Callable()
	RaceManager.roster_personas = []
	RaceManager._car_persona = {}
	RaceManager._recorded_results = {}
	for slot: int in [0, 1]:
		_slot_snapshots[slot] = _snapshot_slot(slot)

func after_test() -> void:
	for car in _managed_cars:
		if is_instance_valid(car):
			car.free()
	for stub in _managed_stubs:
		if is_instance_valid(stub):
			stub.free()
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
	RaceManager.rival_vehicle_scene = null
	RaceManager.rival_spawner = Callable()
	RaceManager.roster_personas = []
	RaceManager._car_persona = {}
	RaceManager._recorded_results = {}
	RaceManager._countdown = RaceCountdown.new()
	RaceManager.consume_pending_race()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()
	_managed_cars.clear()
	_managed_stubs.clear()
	for slot: int in [0, 1]:
		_restore_slot(slot)

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

func _build_ring() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in range(RING_POINTS):
		var angle := float(i) / float(RING_POINTS) * TAU
		points.append(Vector3(cos(angle) * 50.0, 0.0, sin(angle) * 50.0))
	return points

func _new_stub_car() -> VehiclePhysics:
	var car := (load(RIVAL_SCENE) as PackedScene).instantiate() as VehiclePhysics
	car.freeze = true
	car.gravity_scale = 0.0
	_managed_cars.append(car)
	return car

func _load_config(name: String) -> CarConfig:
	return load("res://resources/cars/%s.tres" % name) as CarConfig

func _specs() -> Array[Dictionary]:
	return [
		RaceManager.rival_spec(_load_config("starter_car"), "Novice"),
		RaceManager.rival_spec(_load_config("cc0_race"), "Expert"),
	]

func _add_stub_checkpoint(index: int) -> CheckpointStub:
	var stub := CheckpointStub.new()
	stub.index = index
	add_child(stub)
	_managed_stubs.append(stub)
	return stub

func _add_checkpoint_ring() -> Array[Checkpoint]:
	var cps: Array[Checkpoint] = []
	for i in range(3):
		cps.append(_add_stub_checkpoint(i))
	return cps

func _finish_counter(counter: LapCounter, car: VehiclePhysics, cps: Array, laps: int) -> void:
	for _lap in range(laps):
		for cp in cps:
			counter.update(car, cp)

func test_persona_assignment_is_deterministic_per_seed() -> void:
	var specs_a := _specs()
	var personas_a := RivalPersona.build_for_roster(specs_a, 42)
	var specs_b := _specs()
	var personas_b := RivalPersona.build_for_roster(specs_b, 42)
	assert_that(personas_a.size()).is_equal(2)
	# Every spec received its embedded persona.
	for i in range(specs_a.size()):
		assert_that((specs_a[i] as Dictionary)["persona"]).is_equal(personas_a[i])
	# Same seed -> identical field every time (handle, trait, tier).
	for i in range(2):
		assert_that(personas_a[i].handle).is_equal(personas_b[i].handle)
		assert_that(personas_a[i].signature).is_equal(personas_b[i].signature)
		assert_that(personas_a[i].tier).is_equal(personas_b[i].tier)
	# Tiers mirror the roster specs, names come from the fixed pool, no dupes.
	assert_that(personas_a[0].tier).is_equal("Novice")
	assert_that(personas_a[1].tier).is_equal("Expert")
	assert_that(RivalPersona.NAME_POOL.has(personas_a[0].handle)).is_true()
	assert_that(RivalPersona.NAME_POOL.has(personas_a[1].handle)).is_true()
	assert_that(personas_a[0].handle).is_not_equal(personas_a[1].handle)
	assert_that(RivalPersona.TRAITS.has(personas_a[0].signature)).is_true()

func test_wl_record_updates_exactly_once_per_finished_rival() -> void:
	var player := _new_stub_car()
	VehicleManager.register_player_car(player)
	add_child(player)
	var cps := _add_checkpoint_ring()
	var specs := _specs()
	var personas := RivalPersona.build_for_roster(specs, 1337)
	RaceManager.set_rival_vehicle_scene(load(RIVAL_SCENE) as PackedScene)
	RaceManager.set_rival_centerline(_build_ring())
	RaceManager.set_rival_roster(specs)
	RaceManager.set_personas(personas)
	RaceManager.start_race([player], 2)
	var rivals := RaceManager.get_spawned_rivals()
	assert_that(rivals.size()).is_equal(2)
	var persona_a := RaceManager.get_persona_for(rivals[0])
	var persona_b := RaceManager.get_persona_for(rivals[1])
	assert_that(persona_a).is_not_null()
	assert_that(persona_b).is_not_null()
	# Only rival A finishes (player stalls): A lands exactly one win.
	var counter_a: LapCounter = RaceManager.get_lap_counter(rivals[0])
	_finish_counter(counter_a, rivals[0], cps, 2)
	assert_that(counter_a.is_finished()).is_true()
	RaceManager.finish_race()
	assert_that(persona_a.wins).is_equal(1)
	assert_that(persona_a.losses).is_equal(0)
	assert_that(persona_b.wins + persona_b.losses).is_equal(0)
	# A re-fired finish never double-counts.
	RaceManager.finish_race()
	assert_that(persona_a.wins + persona_a.losses).is_equal(1)
	# B finishing later lands its record exactly once too; A stays put.
	var counter_b: LapCounter = RaceManager.get_lap_counter(rivals[1])
	_finish_counter(counter_b, rivals[1], cps, 2)
	RaceManager.finish_race()
	RaceManager.finish_race()
	assert_that(persona_a.wins + persona_a.losses).is_equal(1)
	assert_that(persona_b.wins + persona_b.losses).is_equal(1)

func test_finished_rival_behind_player_records_loss() -> void:
	var player := _new_stub_car()
	VehicleManager.register_player_car(player)
	add_child(player)
	var cps := _add_checkpoint_ring()
	var specs := _specs()
	var personas := RivalPersona.build_for_roster(specs, 7)
	RaceManager.set_rival_vehicle_scene(load(RIVAL_SCENE) as PackedScene)
	RaceManager.set_rival_centerline(_build_ring())
	RaceManager.set_rival_roster(specs)
	RaceManager.set_personas(personas)
	RaceManager.start_race([player], 2)
	var rival := RaceManager.get_spawned_rivals()[0]
	var persona := RaceManager.get_persona_for(rival)
	# Both cross the line: the player wins the distance tie-break by sitting on
	# the next checkpoint, the finished rival ranks second.
	var player_counter: LapCounter = RaceManager.get_lap_counter(player)
	_finish_counter(player_counter, player, cps, 2)
	player.global_position = cps[0].global_position
	var rival_counter: LapCounter = RaceManager.get_lap_counter(rival)
	_finish_counter(rival_counter, rival, cps, 2)
	rival.global_position = cps[0].global_position + Vector3(60.0, 0.0, 0.0)
	var standings := RaceManager.get_standings()
	assert_that(standings[0]).is_equal(player)
	RaceManager.finish_race()
	assert_that(persona.wins).is_equal(0)
	assert_that(persona.losses).is_equal(1)
	RaceManager.finish_race()
	assert_that(persona.wins + persona.losses).is_equal(1)

func test_save_load_round_trip_preserves_records_and_slot_keys() -> void:
	var specs := _specs()
	var built := RivalPersona.build_for_roster(specs, 77)
	built[0].record_result(true)
	built[1].record_result(false)
	built[1].record_result(true)
	var payload := RivalPersona.to_payload(built, 77)
	assert_that(SaveManager.save_rival_personas(0, payload)).is_true()
	# Merge-write schema: other slot keys survive alongside the new sub-dict.
	var data := SaveManager.load_game(0)
	data["money"] = 100
	assert_that(SaveManager.save_game(0, data)).is_true()
	# A fresh contract for the same slot restores the exact people + records.
	var fresh_specs := _specs()
	var contract := RivalPersona.contract_for_slot(fresh_specs, 0, 0)
	var restored_personas: Array = contract["personas"]
	assert_that(restored_personas.size()).is_equal(2)
	assert_that((restored_personas[0] as RivalPersona).handle).is_equal(built[0].handle)
	assert_that((restored_personas[0] as RivalPersona).wins).is_equal(1)
	assert_that((restored_personas[0] as RivalPersona).losses).is_equal(0)
	assert_that((restored_personas[1] as RivalPersona).wins).is_equal(1)
	assert_that((restored_personas[1] as RivalPersona).losses).is_equal(1)
	assert_that((fresh_specs[0] as Dictionary)["persona"]).is_equal(restored_personas[0])
	var slot_data := SaveManager.load_game(0)
	assert_that(slot_data.has(SaveManager.RIVAL_PERSONAS_KEY)).is_true()
	assert_that(slot_data.get("money")).is_equal(100.0)
	# Pure payload round-trip is lossless.
	var round := RivalPersona.from_payload(payload)
	var round_personas: Array = round["personas"]
	assert_that(int(round["seed"])).is_equal(77)
	for i in range(2):
		var p := round_personas[i] as RivalPersona
		assert_that(p.to_dict()).is_equal(built[i].to_dict())

func test_fresh_slot_builds_roster_from_seed_then_reloads() -> void:
	var specs := _specs()
	var contract := RivalPersona.contract_for_slot(specs, 1, 999)
	assert_that(int(contract["seed"])).is_equal(999)
	var built: Array = contract["personas"]
	assert_that(built.size()).is_equal(2)
	var saved: Dictionary = SaveManager.load_game(1)
	assert_that(saved.has(SaveManager.RIVAL_PERSONAS_KEY)).is_true()
	# Reload with a different seed arg is ignored: the persisted seed rules.
	var reloaded := RivalPersona.contract_for_slot(_specs(), 1, 4242)
	var reload_personas: Array = reloaded["personas"]
	assert_that(int(reloaded["seed"])).is_equal(999)
	for i in range(2):
		assert_that((reload_personas[i] as RivalPersona).handle).is_equal((built[i] as RivalPersona).handle)

func test_personas_attach_to_roster_and_surface_on_grid_and_standings() -> void:
	var player := _new_stub_car()
	VehicleManager.register_player_car(player)
	add_child(player)
	var specs := _specs()
	var personas := RivalPersona.build_for_roster(specs, 21)
	RaceManager.set_rival_vehicle_scene(load(RIVAL_SCENE) as PackedScene)
	RaceManager.set_rival_centerline(_build_ring())
	RaceManager.set_rival_roster(specs)
	RaceManager.set_personas(personas)
	RaceManager.queue_race(2)
	var runner := scene_runner("res://scenes/ui/hud.tscn")
	await runner.simulate_frames(3)
	var scene := runner.scene() as RaceUI
	# Personas attach to the spawned cars through RaceManager.
	var spawned := RaceManager.get_spawned_rivals()
	for i in range(spawned.size()):
		assert_that(RaceManager.get_persona_for(spawned[i])).is_equal(personas[i])
	# Grid card names the field during the ceremony.
	var grid := scene.get_node("%GridCard") as VBoxContainer
	assert_that(grid.visible).is_true()
	assert_that(grid.get_child_count()).is_greater_equal(2)
	var first := grid.get_child(0) as Label
	assert_that(first.text).contains("P1")
	assert_that(first.text).contains(personas[0].handle)
	assert_that(first.text).contains(personas[0].signature)
	# After the countdown, the live standings list races that same field.
	var countdown := RaceManager.get_countdown()
	countdown.advance(3.2)
	await runner.simulate_frames(1)
	var standings_panel := scene.get_node("%StandingsPanel") as Control
	assert_that(standings_panel.visible).is_true()
	var list := scene.get_node("%StandingsList") as VBoxContainer
	assert_that(list.get_child_count()).is_greater_equal(3)
	var found_handle := false
	var found_you := false
	for child in list.get_children():
		if child is Label:
			var text := (child as Label).text
			if text.contains(personas[0].handle):
				found_handle = true
			if text.contains("YOU"):
				found_you = true
	assert_that(found_handle).is_true()
	assert_that(found_you).is_true()

func test_persona_free_roster_keeps_existing_spawn_and_pace_invariants() -> void:
	var player := _new_stub_car()
	VehicleManager.register_player_car(player)
	add_child(player)
	RaceManager.set_rival_vehicle_scene(load(RIVAL_SCENE) as PackedScene)
	RaceManager.set_rival_centerline(_build_ring())
	RaceManager.set_rival_roster([
		RaceManager.rival_spec(_load_config("starter_car"), "Novice"),
		RaceManager.rival_spec(_load_config("cc0_race"), "Expert"),
	])
	var specs := RaceManager.rival_roster
	RaceManager.set_personas(RivalPersona.build_for_roster(specs, 5))
	RaceManager.start_race([player], 2)
	var rivals := RaceManager.get_spawned_rivals()
	assert_that(rivals.size()).is_equal(2)
	# Personas mapped by ordered roster index even when specs carried none.
	assert_that(RaceManager.get_persona_for(rivals[0])).is_not_null()
	# The racing logic surface is untouched: class x tier pacing still holds and
	# the rubber-band assist never enters the player's pace.
	assert_float(RacingLine.pace_for("D", "Novice")).is_equal_approx(0.8 * 0.55, 0.0001)
	assert_float(RacingLine.pace_for("A", "Expert")).is_equal_approx(1.2 * 0.92, 0.0001)
	assert_that(AIRubberBanding.multiplier_for(AIRubberBanding.CATEGORY_PLAYER, 12.0, true)).is_equal(1.0)
	assert_that(AIRubberBanding.multiplier_for(AIRubberBanding.CATEGORY_PLAYER, -12.0, false)).is_equal(1.0)

func test_results_rows_read_name_and_record() -> void:
	var player := _new_stub_car()
	VehicleManager.register_player_car(player)
	add_child(player)
	var cps := _add_checkpoint_ring()
	var specs := _specs()
	var personas := RivalPersona.build_for_roster(specs, 3)
	RaceManager.set_rival_vehicle_scene(load(RIVAL_SCENE) as PackedScene)
	RaceManager.set_rival_centerline(_build_ring())
	RaceManager.set_rival_roster(specs)
	RaceManager.set_personas(personas)
	RaceManager.start_race([player], 2)
	var rival := RaceManager.get_spawned_rivals()[0]
	var rival_counter: LapCounter = RaceManager.get_lap_counter(rival)
	_finish_counter(rival_counter, rival, cps, 2)
	var standings := RaceManager.get_standings()
	RaceManager.finish_race()
	var ui := RaceUI.new()
	var rows := ui._build_persona_finish_rows(standings)
	ui.free()
	var winner_row := rows[0] as Dictionary
	assert_that(str(winner_row.get("label"))).contains(personas[0].handle)
	assert_that(str(winner_row.get("label"))).contains("P1")
	assert_that(str(winner_row.get("value"))).contains(personas[0].get_record_string())
	assert_that(standings.size()).is_equal(3)