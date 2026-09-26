# tests/suites/test_best_lap_records.gd
extends GdUnitTestSuite

## Roadmap #7 gate: cross-session best-lap records. The (track, car class) key
## keeps records apart, a worse lap never overwrites a better one while a better
## lap does, the whole flow round-trips through its own additive SaveManager
## section without touching sibling slot fields, and the session accumulator
## seeds itself from the persisted value.
##
## Everything persistent uses slot 2 (snapshotted in before_test and restored in
## after_test) so the round-trip is hermetic and never disturbs the player's
## slot-0 records. The pure key/merge math needs no slot at all.

const SLOT := 2

var _slot_snapshot: Dictionary = {}
var _slot_had_save: bool = false

func before_test() -> void:
	_slot_snapshot = SaveManager.load_game(SLOT)
	_slot_had_save = SaveManager.has_save(SLOT)

func after_test() -> void:
	var path: String = SaveManager.SAVE_DIR.path_join("slot_%d.json" % (SLOT + 1))
	if _slot_snapshot.is_empty() and not _slot_had_save:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	else:
		SaveManager.save_game(SLOT, _slot_snapshot)

func _records() -> BestLapRecords:
	return BestLapRecords.new()

# --- Key separation -------------------------------------------------------

func test_key_separates_track_and_car_class() -> void:
	var oval_d := BestLapRecords.key_for("oval", "D")
	var pass_d := BestLapRecords.key_for("mountain_pass", "D")
	var oval_b := BestLapRecords.key_for("oval", "B")
	assert_that(oval_d).is_equal("oval|D")
	assert_that(oval_d).is_not_equal(pass_d)
	assert_that(oval_d).is_not_equal(oval_b)

func test_class_key_is_case_folded_and_empty_ids_get_a_stable_bucket() -> void:
	assert_that(BestLapRecords.key_for("oval", "d")).is_equal(BestLapRecords.key_for("oval", "D"))
	assert_that(BestLapRecords.key_for("", "")).is_equal(
		"%s|%s" % [BestLapRecords.UNKNOWN_TRACK, BestLapRecords.UNKNOWN_CAR_CLASS])
	assert_that(BestLapRecords.key_for("  ", "  ")).is_equal(
		BestLapRecords.key_for("", ""))

func test_registered_track_ids_produce_distinct_record_keys() -> void:
	var ids: Array[String] = []
	ids.assign(TrackRegistry.get_track_ids())
	assert_that(ids.size()).is_greater(1)
	var seen: Dictionary = {}
	for track_id in ids:
		var key := BestLapRecords.key_for(track_id, "D")
		assert_that(seen.has(key)).is_false()
		seen[key] = true

# --- In-memory merge semantics -------------------------------------------

func test_record_lap_keeps_the_faster_lap_only() -> void:
	var records := _records()
	assert_that(records.get_record("oval", "D")).is_equal(0.0)
	assert_that(records.record_lap("oval", "D", 95.0)).is_true()
	assert_that(records.record_lap("oval", "D", 88.5)).is_true()
	assert_that(records.record_lap("oval", "D", 92.0)).is_false()
	assert_that(records.get_record("oval", "D")).is_equal(88.5)
	assert_that(records.size()).is_equal(1)

func test_record_lap_rejects_non_positive_lap_times() -> void:
	var records := _records()
	assert_that(records.record_lap("oval", "D", 0.0)).is_false()
	assert_that(records.record_lap("oval", "D", -12.0)).is_false()
	assert_that(records.get_record("oval", "D")).is_equal(0.0)
	assert_that(records.size()).is_equal(0)

func test_is_improvement_matches_the_merge_decision() -> void:
	var records := _records()
	assert_that(records.is_improvement("oval", "D", 95.0)).is_true()
	records.record_lap("oval", "D", 90.0)
	assert_that(records.is_improvement("oval", "D", 89.0)).is_true()
	assert_that(records.is_improvement("oval", "D", 90.0)).is_false()
	assert_that(records.is_improvement("oval", "D", 91.0)).is_false()

func test_restore_merges_and_never_degrades_a_record() -> void:
	var stored := {"oval|D": 88.0, "oval|B": 74.0, "broken": -1.0}
	var live := _records()
	live.record_lap("oval", "D", 80.0)
	live.restore({BestLapRecords.SAVE_KEY: stored})
	# The slower stored value loses to the faster live one...
	assert_that(live.get_record("oval", "D")).is_equal(80.0)
	# ...a missing pair is merged in...
	assert_that(live.get_record("oval", "B")).is_equal(74.0)
	# ...and a garbage value is dropped instead of becoming a record.
	assert_that(live.size()).is_equal(2)

func test_store_round_trips_through_restore() -> void:
	var source := _records()
	source.record_lap("mountain_pass", "S", 61.25)
	var target := _records()
	target.restore(source.store())
	assert_that(target.get_record("mountain_pass", "S")).is_equal(61.25)
	assert_that(target.keys()).is_equal(source.keys())

# --- Slot round trip ------------------------------------------------------

func test_save_slot_round_trip_reloads_the_record() -> void:
	var records := _records()
	records.record_lap("mountain_pass", "B", 82.4)
	assert_that(records.save_to_slot(SLOT)).is_true()
	assert_that(SaveManager.load_game(SLOT).has(BestLapRecords.SAVE_KEY)).is_true()
	assert_that(SaveManager.load_game(SLOT).has(SaveManager.BEST_LAPS_KEY)).is_true()
	# A brand-new instance sees it, exactly like the next run after a restart.
	var reloaded := _records()
	assert_that(reloaded.load_from_slot(SLOT)).is_true()
	assert_that(reloaded.get_record("mountain_pass", "B")).is_equal(82.4)
	assert_that(BestLapRecords.load_record("mountain_pass", "B", SLOT)).is_equal(82.4)

func test_worse_lap_does_not_overwrite_and_better_lap_does() -> void:
	# First run sets the record...
	assert_that(BestLapRecords.submit_lap("oval", "D", 90.0, SLOT)).is_true()
	assert_that(BestLapRecords.load_record("oval", "D", SLOT)).is_equal(90.0)
	# ...a slower run must NOT overwrite it, and must report no improvement.
	assert_that(BestLapRecords.submit_lap("oval", "D", 95.0, SLOT)).is_false()
	assert_that(BestLapRecords.load_record("oval", "D", SLOT)).is_equal(90.0)
	# An identical lap is a no-op too.
	assert_that(BestLapRecords.submit_lap("oval", "D", 90.0, SLOT)).is_false()
	assert_that(BestLapRecords.load_record("oval", "D", SLOT)).is_equal(90.0)
	# A faster lap does overwrite it.
	assert_that(BestLapRecords.submit_lap("oval", "D", 87.25, SLOT)).is_true()
	assert_that(BestLapRecords.load_record("oval", "D", SLOT)).is_equal(87.25)

func test_submit_lap_ignores_non_positive_lap_times() -> void:
	assert_that(BestLapRecords.submit_lap("oval", "D", 0.0, SLOT)).is_false()
	assert_that(BestLapRecords.submit_lap("oval", "D", -5.0, SLOT)).is_false()
	assert_that(BestLapRecords.load_record("oval", "D", SLOT)).is_equal(0.0)

func test_slot_records_are_separated_per_track_and_per_class() -> void:
	assert_that(BestLapRecords.submit_lap("oval", "D", 90.0, SLOT)).is_true()
	assert_that(BestLapRecords.submit_lap("oval", "B", 80.0, SLOT)).is_true()
	assert_that(BestLapRecords.submit_lap("mountain_pass", "D", 70.0, SLOT)).is_true()
	# A second lap on one pair must not touch its siblings.
	assert_that(BestLapRecords.submit_lap("oval", "D", 95.0, SLOT)).is_false()
	var records := _records()
	records.load_from_slot(SLOT)
	assert_that(records.get_record("oval", "D")).is_equal(90.0)
	assert_that(records.get_record("oval", "B")).is_equal(80.0)
	assert_that(records.get_record("mountain_pass", "D")).is_equal(70.0)
	assert_that(records.size()).is_equal(3)

func test_section_is_additive_to_the_rest_of_the_slot() -> void:
	var seeded: Dictionary = SaveManager.load_game(SLOT)
	seeded["sibling_marker"] = "keep-me"
	seeded[BestLapRecords.SAVE_KEY] = {}
	SaveManager.save_game(SLOT, seeded)
	assert_that(BestLapRecords.submit_lap("oval", "D", 91.0, SLOT)).is_true()
	var after: Dictionary = SaveManager.load_game(SLOT)
	assert_that(after.get("sibling_marker")).is_equal("keep-me")
	assert_that(after.has(BestLapRecords.SAVE_KEY)).is_true()
	assert_that(after.has(SaveManager.BEST_LAPS_KEY)).is_true()
	assert_that(BestLapRecords.load_record("oval", "D", SLOT)).is_equal(91.0)

func test_empty_and_foreign_sections_load_as_no_record() -> void:
	SaveManager.save_game(SLOT, {})
	assert_that(BestLapRecords.load_record("oval", "D", SLOT)).is_equal(0.0)
	var records := _records()
	assert_that(records.load_from_slot(SLOT)).is_false()
	# A slot carrying the key with a wrong type must not error or invent a record.
	SaveManager.save_game(SLOT, {BestLapRecords.SAVE_KEY: 7})
	assert_that(records.load_from_slot(SLOT)).is_false()
	assert_that(records.get_record("oval", "D")).is_equal(0.0)
	assert_that(BestLapRecords.submit_lap("oval", "D", 88.0, SLOT)).is_true()
	assert_that(BestLapRecords.load_record("oval", "D", SLOT)).is_equal(88.0)

# --- Session accumulator seeding -----------------------------------------

func test_session_stats_seeds_from_the_persisted_record() -> void:
	var stats := SessionStats.new()
	stats.seed_best_lap(90.0)
	assert_that(stats.get_best_lap()).is_equal(90.0)
	# A slower lap in the new run does not beat the record.
	stats.start_lap()
	stats.end_lap(95.0)
	assert_that(stats.get_best_lap()).is_equal(90.0)
	# A faster one does.
	stats.start_lap()
	stats.end_lap(85.0)
	assert_that(stats.get_best_lap()).is_equal(85.0)
	# Seeding again is a no-op once the session is faster.
	stats.seed_best_lap(90.0)
	assert_that(stats.get_best_lap()).is_equal(85.0)

func test_session_stats_seed_ignores_non_positive_and_empty_start() -> void:
	var stats := SessionStats.new()
	stats.seed_best_lap(0.0)
	stats.seed_best_lap(-3.0)
	assert_that(stats.get_best_lap()).is_equal(0.0)
	stats.start_lap()
	stats.end_lap(77.0)
	stats.seed_best_lap(0.0)
	assert_that(stats.get_best_lap()).is_equal(77.0)
	assert_that(stats.get_total_laps()).is_equal(1)

# --- HUD wording ----------------------------------------------------------

func test_best_lap_delta_text_signs_the_gap_against_the_record() -> void:
	# Slower than the record -> positive gap.
	assert_that(RaceUI.best_lap_delta_text(88.0, 90.5)).is_equal("THIS RUN +2.50")
	# Faster than the record -> negative gap.
	assert_that(RaceUI.best_lap_delta_text(88.0, 86.25)).is_equal("THIS RUN -1.75")
	# The record itself -> an explicit match line, not a "+0.00".
	assert_that(RaceUI.best_lap_delta_text(88.0, 88.0)).is_equal("MATCHES RECORD")
	# Nothing to compare (no record, or no lap this run) -> hidden.
	assert_that(RaceUI.best_lap_delta_text(0.0, 90.0)).is_equal("")
	assert_that(RaceUI.best_lap_delta_text(88.0, 0.0)).is_equal("")
	assert_that(RaceUI.best_lap_delta_text(0.0, 0.0)).is_equal("")

func test_hud_seeds_from_the_slot_and_files_a_finished_lap() -> void:
	# A record already on disk for this pair.
	var records := _records()
	records.record_lap("oval", "D", 80.0)
	records.save_to_slot(SLOT)
	var stats := SessionStats.new()
	stats.seed_best_lap(BestLapRecords.load_record("oval", "D", SLOT))
	assert_that(stats.get_best_lap()).is_equal(80.0)
	# The run's slower lap leaves the record alone...
	stats.start_lap()
	stats.end_lap(84.0)
	assert_that(BestLapRecords.submit_lap("oval", "D", stats.get_best_lap(), SLOT)).is_false()
	assert_that(BestLapRecords.load_record("oval", "D", SLOT)).is_equal(80.0)
	assert_that(RaceUI.best_lap_delta_text(80.0, 84.0)).is_equal("THIS RUN +4.00")
	# ...but a genuinely faster run-only lap does replace it.
	assert_that(BestLapRecords.submit_lap("oval", "D", 76.5, SLOT)).is_true()
	assert_that(BestLapRecords.load_record("oval", "D", SLOT)).is_equal(76.5)
