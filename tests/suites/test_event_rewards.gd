# tests/suites/test_event_rewards.gd
extends GdUnitTestSuite

## S7 playable-loop gate: the 8 event families (6 placed + outbreak + convoy)
## expose a full scoring contract, every placed event is startable and
## finishable through the EventSession seam, each completion emits exactly one
## credit award (banked into the S7 Money ledger), a full session is zero-sum
## (credited == spent, credits == credited - spent), timed/head-to-head runs
## grade by EventScoring time bands, drift grades by DriftScorer total, drag
## arms launch-start lights, best results persist hermetically in slot 0, and
## event mode pauses ambient traffic + the day-night clock while the player
## stays inside the event bounds. Headless-safe: no frames, no Terrain3D.

const ANCHORS: Array[Vector3] = [
	Vector3(128.0, 2.2, 128.0),
	Vector3(1536.0, 6.0, 1536.0),
	Vector3(5888.0, 2.5, 1536.0),
	Vector3(3840.0, 10.0, 2304.0),
	Vector3(5632.0, 35.0, 5632.0),
]

const EVENT_KINDS := ["touge_duel", "drag_strip", "drift_zone", "night_street_loop", "marathon_highway", "outbreak", "convoy"]

func _defs() -> Array[RoadDef]:
	return CorridorPlanner.plan(CorridorPlanner.MASTER_SEED, Callable(), {})

func _defs_map() -> Dictionary:
	return EventRegistry.place_defs(_defs(), ANCHORS)

func _new_session() -> EventSession:
	var session := EventSession.new()
	add_child(session)
	return session

## A metric that clears an event's finishing bar (S-band): 0.9 × target_time
## for timed runs, 1.2 × target_score for drift.
func _passing_metric(def: EventDef) -> float:
	if def.is_score_objective():
		return def.grade_target() * 1.2
	return def.target_time * 0.9

func after_test() -> void:
	RaceManager.consume_pending_race()
	for child in get_children():
		if child is EventSession:
			child.free()

func test_place_defs_exposes_all_eight_event_types() -> void:
	var defs := _defs_map()
	assert_that(defs.size()).is_equal(EVENT_KINDS.size() + ANCHORS.size())
	for kind in EVENT_KINDS:
		assert_that(defs.has(kind)).is_true()
	for i in ANCHORS.size():
		assert_that(defs.has("time_attack_%d" % i)).is_true()

func test_every_event_has_a_scoring_contract() -> void:
	var defs := _defs_map()
	for event_id: String in defs.keys():
		var def := defs[event_id] as EventDef
		assert_that(EventDef.Objective.values().has(def.objective)).is_true()
		assert_that(def.payout).is_greater(0)
		assert_that(def.checkpoints.size()).is_greater_equal(2)
		assert_that(def.target_time).is_greater_equal(0.0)
		var grade := EventScoring.grade(def, _passing_metric(def))
		assert_that(EventScoring.is_valid_grade(grade)).is_true()
		assert_that(EventScoring.reward(def, grade)).is_greater(0)

func test_every_placed_event_is_startable_and_finishable() -> void:
	var session := _new_session()
	for event_id: String in _defs_map().keys():
		assert_that(session.start_event(event_id)).is_true()
		assert_that(session.is_event_active()).is_true()
		var result := session.submit_result(_passing_metric(session.get_active_event()))
		assert_that(result.has("grade")).is_true()
		assert_that(result.has("reward")).is_true()
		assert_that(session.is_event_active()).is_false()

func test_timed_objectives_grade_by_time_bands() -> void:
	var defs := _defs_map()
	for event_id: String in ["touge_duel", "night_street_loop", "marathon_highway", "outbreak", "convoy"]:
		var def := defs[event_id] as EventDef
		assert_that(def.is_score_objective()).is_false()
		assert_that(EventScoring.grade(def, def.target_time * 0.85)).is_equal("S")
		assert_that(EventScoring.grade(def, def.target_time)).is_equal("A")
		assert_that(EventScoring.grade(def, def.target_time * 1.1)).is_equal("B")
		assert_that(EventScoring.grade(def, def.target_time * 1.5)).is_equal("C")

func test_drift_objective_grades_by_score_bands() -> void:
	var defs := _defs_map()
	var def := defs["drift_zone"] as EventDef
	assert_that(def.is_score_objective()).is_true()
	var target := def.grade_target()
	assert_that(target).is_greater(0.0)
	assert_that(EventScoring.grade(def, target * 2.0)).is_equal("S")
	assert_that(EventScoring.grade(def, target * 1.75)).is_equal("A")
	assert_that(EventScoring.grade(def, target * 1.0)).is_equal("B")
	assert_that(EventScoring.grade(def, target * 0.5)).is_equal("C")

func test_every_completion_emits_exactly_one_credit_award() -> void:
	var session := _new_session()
	var awards: Array[int] = []
	session.event_completed.connect(func(_def: EventDef, _grade: String, reward: int) -> void:
		awards.append(reward))
	for event_id: String in _defs_map().keys():
		assert_that(session.start_event(event_id)).is_true()
		var result: Dictionary
		if session.get_active_event().is_score_objective():
			session.tick_drift(0.5, 30.0, true)
			result = session.complete_drift()
		else:
			result = session.submit_result(_passing_metric(session.get_active_event()))
		assert_that(result.has("reward")).is_true()
	assert_that(awards.size()).is_equal(_defs_map().size())
	var credited := 0
	for reward in awards:
		credited += reward
	assert_that(session.money.get_total_credited()).is_equal(credited)
	assert_that(session.money.get_credits()).is_equal(credited)

func test_ledger_balances_zero_sum_across_a_full_session() -> void:
	var session := _new_session()
	assert_that(session.money.is_accounting_consistent()).is_true()
	var total := 0
	for event_id: String in _defs_map().keys():
		assert_that(session.start_event(event_id)).is_true()
		var result := session.submit_result(_passing_metric(session.get_active_event()))
		total += int(result["reward"])
	assert_that(session.money.get_credits()).is_equal(total)
	assert_that(session.money.is_accounting_consistent()).is_true()
	assert_that(session.money.spend(total)).is_true()
	assert_that(session.money.balances_to_zero()).is_true()
	assert_that(session.money.is_accounting_consistent()).is_true()

func test_unknown_and_double_starts_are_rejected() -> void:
	var session := _new_session()
	assert_that(session.start_event("ghost_event")).is_false()
	assert_that(session.start_event("night_street_loop")).is_true()
	assert_that(session.start_event("marathon_highway")).is_false()
	session.fail_event()
	assert_that(session.is_event_active()).is_false()

func test_drift_zone_grades_from_drift_scorer_total() -> void:
	var session := _new_session()
	assert_that(session.start_event("drift_zone")).is_true()
	session.tick_drift(1.0, 45.0, true)
	session.tick_drift(1.0, 45.0, true)
	assert_that(session.get_drift_score()).is_greater(0)
	var result := session.complete_drift()
	assert_that(result.has("grade")).is_true()
	assert_that(result.has("reward")).is_true()
	assert_that(session.is_event_active()).is_false()

func test_timed_events_request_the_countdown_race_seam() -> void:
	var session := _new_session()
	RaceManager.consume_pending_race()
	var defs := _defs_map()
	for event_id: String in defs.keys():
		var def := defs[event_id] as EventDef
		if def.is_score_objective():
			continue
		assert_that(session.start_event(event_id)).is_true()
		assert_that(RaceManager.consume_pending_race()).is_equal(def.laps())
		session.submit_result(_passing_metric(session.get_active_event()))

func test_drag_strip_launches_start_lights() -> void:
	var session := _new_session()
	assert_that(session.start_event("drag_strip")).is_true()
	assert_that(session.startlights_state()).is_equal("3")
	assert_that(session.startlights_advance(1.0)).is_equal("2")
	assert_that(session.startlights_advance(1.0)).is_equal("1")
	assert_that(session.startlights_advance(1.0)).is_equal("GO")
	assert_that(session.startlights_advance(0.8)).is_equal("RACE")

func test_best_time_and_score_persist_in_the_slot_save() -> void:
	var slot := EventSession.DEFAULT_SLOT
	var snapshot: Dictionary = SaveManager.load_game(slot)
	var session := _new_session()
	var def := session.get_event_def("drag_strip")
	assert_that(session.start_event("drag_strip")).is_true()
	var best := def.target_time * 0.8
	session.submit_result(best)
	assert_that(session.get_best("drag_strip")).is_equal_approx(best, 0.001)
	assert_that(session.save_bests()).is_true()

	var after := EventSession.new()
	add_child(after)
	assert_that(after.get_best("drag_strip")).is_equal_approx(best, 0.001)

	after.free()
	session.free()
	var path = SaveManager.SAVE_DIR.path_join("slot_%d.json" % (slot + 1))
	if snapshot.is_empty() and not SaveManager.has_save(slot):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	else:
		SaveManager.save_game(slot, snapshot)

func test_event_mode_pauses_ambient_traffic_and_clock() -> void:
	var session := _new_session()
	var living := LivingWorld.new()
	add_child(living)
	var traffic := TrafficSpawner.new()
	add_child(traffic)
	session.living_world_path = session.get_path_to(living)
	session.traffic_path = session.get_path_to(traffic)
	assert_that(session.start_event("night_street_loop")).is_true()
	assert_that(living.is_enabled()).is_false()
	assert_that(traffic.is_enabled()).is_false()
	assert_that(DayNightDriver.is_enabled()).is_false()
	session.submit_result(_passing_metric(session.get_active_event()))
	assert_that(living.is_enabled()).is_true()
	assert_that(traffic.is_enabled()).is_true()
	assert_that(DayNightDriver.is_enabled()).is_true()

func test_event_mode_gate_toggles_are_idempotent() -> void:
	var living := LivingWorld.new()
	add_child(living)
	assert_that(living.is_enabled()).is_true()
	living.set_enabled(false)
	living.set_enabled(false)
	assert_that(living.is_enabled()).is_false()
	living.set_enabled(true)
	assert_that(living.is_enabled()).is_true()

	var traffic := TrafficSpawner.new()
	add_child(traffic)
	assert_that(traffic.is_enabled()).is_true()
	traffic.set_enabled(false)
	assert_that(traffic.is_enabled()).is_false()
	traffic.set_enabled(true)
	assert_that(traffic.is_enabled()).is_true()

	DayNightDriver.set_enabled(false)
	assert_that(DayNightDriver.is_enabled()).is_false()
	DayNightDriver.set_enabled(true)
	assert_that(DayNightDriver.is_enabled()).is_true()

func test_event_bounds_gate_fails_an_out_of_bounds_run() -> void:
	var session := _new_session()
	session.set_bounds_radius(100.0)
	assert_that(session.start_event("drift_zone")).is_true()
	var def := session.get_active_event()
	assert_that(session.is_player_outside_bounds(def.position + Vector3(200.0, 0.0, 0.0))).is_true()
	assert_that(session.is_player_outside_bounds(def.position + Vector3(50.0, 0.0, 0.0))).is_false()
	var result := session.fail_event()
	assert_that(result["grade"]).is_equal("C")
	assert_that(session.is_event_active()).is_false()
	assert_that(session.money.get_credits()).is_greater(0)