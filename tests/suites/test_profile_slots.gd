# tests/suites/test_profile_slots.gd
extends GdUnitTestSuite

## P2-2 gate (match_fh6_gt7 item 17): save robustness + profile split.
## Covers the corruption ratchet (temp-then-rename atomic write, corrupt slots
## surface as "present but corrupt" instead of reading back as fresh), per-slot
## profile namespacing (name/created_at metadata, no cross-slot bleed), sub-dict
## merge-writes that preserve other keys even when a dict grows, and an
## oversized write that fails cleanly without touching the previous target.
## Slots 0-2 are snapshotted byte-for-byte before each test and restored in
## after_test so real player saves stay untouched.

var _slot_snapshots: Dictionary = {}

func before_test() -> void:
	for slot: int in [0, 1, 2]:
		_slot_snapshots[slot] = _snapshot_slot(slot)

func after_test() -> void:
	for slot: int in [0, 1, 2]:
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

func _write_raw(slot: int, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(SaveManager.SAVE_DIR)
	var file := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()

func _profile_name(data: Dictionary) -> String:
	var p: Variant = data.get(SaveManager.PROFILE_KEY, {})
	if p is Dictionary:
		var n: Variant = p.get("name", "")
		if n is String:
			return n
	return ""

func test_round_trip_preserves_the_slot_schema() -> void:
	var data := {"money": 1000, "license": "B", "owned_cars": ["starter_car"]}
	assert_that(SaveManager.save_game(0, data)).is_true()
	var loaded := SaveManager.load_game(0)
	assert_that(loaded.get("money")).is_equal(1000.0)
	assert_that(loaded.get("license")).is_equal("B")
	var full := SaveManager.load_game_full(0)
	assert_that(bool(full["ok"])).is_true()
	assert_that(int(full["state"])).is_equal(SaveManager.SlotState.VALID)
	assert_that(SaveManager.slot_state(0)).is_equal(SaveManager.SlotState.VALID)
	assert_that(SaveManager.has_save(0)).is_true()

func test_atomic_save_leaves_no_tmp_residue() -> void:
	assert_that(SaveManager.save_game(0, {"a": 1})).is_true()
	assert_that(FileAccess.file_exists(_tmp_path(0))).is_false()
	assert_that(FileAccess.file_exists(_slot_path(0))).is_true()
	# A pre-existing target is replaced in place, with no temp file leftover.
	assert_that(SaveManager.save_game(0, {"a": 2, "b": [1, 2, 3]})).is_true()
	assert_that(FileAccess.file_exists(_tmp_path(0))).is_false()
	var loaded := SaveManager.load_game(0)
	assert_that(int(loaded.get("a"))).is_equal(2)
	assert_that(loaded.get("b")).is_equal([1.0, 2.0, 3.0])

func test_corrupt_slot_is_present_but_corrupt() -> void:
	_write_raw(0, "this is not json {{{")
	assert_that(SaveManager.has_save(0)).is_true()
	assert_that(SaveManager.slot_state(0)).is_equal(SaveManager.SlotState.CORRUPT)
	var full := SaveManager.load_game_full(0)
	assert_that(bool(full["ok"])).is_false()
	assert_that(int(full["state"])).is_equal(SaveManager.SlotState.CORRUPT)
	# Compatibility surface still reads a corrupt slot as {}.
	assert_that(SaveManager.load_game(0)).is_equal({})
	# A healthy slot sits on the opposite branch: ok, VALID, data preserved.
	assert_that(SaveManager.save_game(1, {"k": "v"})).is_true()
	var ok_full := SaveManager.load_game_full(1)
	assert_that(bool(ok_full["ok"])).is_true()
	assert_that(int(ok_full["state"])).is_equal(SaveManager.SlotState.VALID)
	var d: Dictionary = ok_full["data"]
	assert_that(str(d.get("k"))).is_equal("v")

func test_non_dictionary_json_reads_as_corrupt() -> void:
	_write_raw(0, "[1, 2, 3]")
	assert_that(SaveManager.has_save(0)).is_true()
	assert_that(SaveManager.slot_state(0)).is_equal(SaveManager.SlotState.CORRUPT)
	var full := SaveManager.load_game_full(0)
	assert_that(bool(full["ok"])).is_false()
	assert_that(int(full["state"])).is_equal(SaveManager.SlotState.CORRUPT)

func test_missing_slot_reads_as_missing_not_corrupt() -> void:
	# Slot 2 is forced absent so the MISSING branch is deterministic; after_test
	# restores whatever was there before.
	var path := _slot_path(2)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	assert_that(SaveManager.has_save(2)).is_false()
	assert_that(SaveManager.slot_state(2)).is_equal(SaveManager.SlotState.MISSING)
	var full := SaveManager.load_game_full(2)
	assert_that(bool(full["ok"])).is_false()
	assert_that(int(full["state"])).is_equal(SaveManager.SlotState.MISSING)
	assert_that(SaveManager.load_game(2)).is_equal({})

func test_slot_profiles_namespaced_per_slot() -> void:
	assert_that(SaveManager.create_slot(0, "First")).is_true()
	assert_that(SaveManager.create_slot(1, "Second")).is_true()
	assert_that(SaveManager.slot_name(0)).is_equal("First")
	assert_that(SaveManager.slot_name(1)).is_equal("Second")
	assert_that(SaveManager.slot_created_at(0)).is_greater(0)
	assert_that(SaveManager.slot_created_at(1)).is_greater(0)
	var used := SaveManager.slots_in_use()
	assert_that(used.has(0)).is_true()
	assert_that(used.has(1)).is_true()
	# Metadata really landed in each slot's own file, not a shared store.
	assert_that(_profile_name(SaveManager.load_game(0))).is_equal("First")
	assert_that(_profile_name(SaveManager.load_game(1))).is_equal("Second")
	assert_that(_profile_name(SaveManager.load_game(2))).is_equal("")

func test_create_slot_refuses_occupied_and_empty_names() -> void:
	assert_that(SaveManager.create_slot(0, "Driver One")).is_true()
	assert_that(SaveManager.create_slot(0, "Sneaky Overwrite")).is_false()
	assert_that(SaveManager.last_error).is_equal("slot_occupied")
	assert_that(SaveManager.slot_name(0)).is_equal("Driver One")
	assert_that(SaveManager.create_slot(1, "   ")).is_false()
	assert_that(SaveManager.last_error).is_equal("invalid_name")
	assert_that(SaveManager.slot_name(1)).is_equal("")

func test_create_slot_can_recover_a_corrupt_slot() -> void:
	_write_raw(0, "garbage{{{")
	assert_that(SaveManager.create_slot(0, "Reborn")).is_true()
	assert_that(SaveManager.slot_name(0)).is_equal("Reborn")
	assert_that(SaveManager.slot_state(0)).is_equal(SaveManager.SlotState.VALID)

func test_slots_stay_independent_on_reload() -> void:
	assert_that(SaveManager.save_game(0, {"money": 100, "owned_cars": ["a"]})).is_true()
	assert_that(SaveManager.save_game(1, {"money": 999, "owned_cars": ["b"]})).is_true()
	# Merge-writers hit their own slot's file only.
	assert_that(SaveManager.save_discovery(0, {"0": [0, 1]})).is_true()
	assert_that(SaveManager.save_career_profile(1, {"level": 5})).is_true()
	var s0: Dictionary = SaveManager.load_game(0)
	var s1: Dictionary = SaveManager.load_game(1)
	assert_that(s0.get("money")).is_equal(100.0)
	assert_that(s1.get("money")).is_equal(999.0)
	assert_that(SaveManager.load_discovery(0).has("0")).is_true()
	assert_that(SaveManager.load_discovery(1).is_empty()).is_true()
	assert_that(SaveManager.load_career_profile(1).get("level")).is_equal(5.0)
	assert_that(SaveManager.load_career_profile(0).is_empty()).is_true()

func test_subdict_merge_preserves_keys_under_growth() -> void:
	assert_that(SaveManager.save_game(0, {"money": 100, "license": "B"})).is_true()
	var big_discovery := {}
	for i in 5000:
		big_discovery[str(i)] = [i, i + 1]
	assert_that(SaveManager.save_discovery(0, big_discovery)).is_true()
	var grown: Dictionary = SaveManager.load_game(0)
	assert_that(grown.has("money")).is_true()
	assert_that(str(grown.get("license"))).is_equal("B")
	assert_that(SaveManager.load_discovery(0).size()).is_equal(5000)
	# A later merge-write of a different sub-dict must not clobber the growth.
	assert_that(SaveManager.save_career_money(0, {"credits": 42})).is_true()
	var merged: Dictionary = SaveManager.load_game(0)
	assert_that(merged.has("money")).is_true()
	assert_that(merged.has("license")).is_true()
	assert_that(SaveManager.load_discovery(0).size()).is_equal(5000)
	assert_that(SaveManager.load_career_money(0).get("credits")).is_equal(42.0)

func test_oversized_write_fails_cleanly() -> void:
	assert_that(SaveManager.save_game(0, {"money": 100})).is_true()
	var huge := {"blob": "x".repeat(SaveManager.MAX_SAVE_BYTES + 1024)}
	assert_that(SaveManager.save_game(0, huge)).is_false()
	assert_that(SaveManager.last_error).is_equal("save_too_large")
	assert_that(FileAccess.file_exists(_tmp_path(0))).is_false()
	# The previous good target is untouched: no truncation, no replacement.
	var loaded := SaveManager.load_game(0)
	assert_that(loaded.get("money")).is_equal(100.0)
	assert_that(SaveManager.slot_state(0)).is_equal(SaveManager.SlotState.VALID)
	# Merge-writers route through the same cap.
	var big_blob := {"0": "x".repeat(SaveManager.MAX_SAVE_BYTES + 1)}
	assert_that(SaveManager.save_discovery(0, big_blob)).is_false()
	assert_that(SaveManager.last_error).is_equal("save_too_large")
	assert_that(FileAccess.file_exists(_tmp_path(0))).is_false()
	assert_that(FileAccess.file_exists(_slot_path(0))).is_true()
	assert_that(SaveManager.load_game(0).get("money")).is_equal(100.0)