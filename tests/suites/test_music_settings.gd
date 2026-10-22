# tests/suites/test_music_settings.gd
extends GdUnitTestSuite

## music_settings sanitising, folder rules and slot-0 persistence. Persistence
## runs against slot 2 (cleaned up) and never touches slot 0.

const SLOT := 2

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://saves/slot_%d.json" % (SLOT + 1)))

func test_defaults_are_complete_and_sane() -> void:
	var d := MusicSettings.defaults()
	for key in ["enabled", "folder", "volume", "station", "track_id", "shuffle", "crossfade_s", "toast", "duck", "streamer_safe"]:
		assert_that(d.has(key)).is_true()
	assert_that(d["enabled"]).is_true()
	assert_that(d["volume"]).is_equal(0.7)
	assert_that(d["crossfade_s"]).is_equal(2.5)
	assert_that(d["station"]).is_equal("all")
	assert_that(d["streamer_safe"]).is_false()

func test_values_are_clamped() -> void:
	var s := MusicSettings.sanitize({"volume": 9.0, "crossfade_s": -4.0})
	assert_that(s["volume"]).is_equal(1.0)
	assert_that(s["crossfade_s"]).is_equal(0.0)
	var t := MusicSettings.sanitize({"volume": -1, "crossfade_s": 99})
	assert_that(t["volume"]).is_equal(0.0)
	assert_that(t["crossfade_s"]).is_equal(8.0)

func test_corrupt_types_fall_back_to_defaults() -> void:
	var s := MusicSettings.sanitize({
		"enabled": "yes", "volume": "loud", "folder": 12, "station": null,
		"crossfade_s": [1], "toast": {}, "shuffle": 0, "bogus": 1,
	})
	assert_that(s["enabled"]).is_true() # string -> default
	assert_that(s["volume"]).is_equal(0.7)
	assert_that(s["folder"]).is_equal("")
	assert_that(s["station"]).is_equal("all")
	assert_that(s["crossfade_s"]).is_equal(2.5)
	assert_that(s["toast"]).is_true()
	assert_that(s["shuffle"]).is_false() # int 0 -> false
	assert_that(s.has("bogus")).is_false()
	assert_that(MusicSettings.sanitize("not a dict")).is_equal(MusicSettings.defaults())
	assert_that(MusicSettings.sanitize({"volume": NAN})["volume"]).is_equal(0.7)

func test_old_save_without_the_key_gets_defaults() -> void:
	var old_save := {"quality_preset": 2, "season": 1}
	assert_that(MusicSettings.from_save(old_save)).is_equal(MusicSettings.defaults())

func test_merge_into_save_preserves_every_other_key() -> void:
	var data := {"quality_preset": 2, "camera_settings": {"hood_bob": 0.3}, "profile": {"name": "Ana"}}
	var s := MusicSettings.defaults()
	s["volume"] = 0.4
	s["folder"] = "E:/Songs"
	var merged := MusicSettings.merge_into_save(data, s)
	assert_that(merged["quality_preset"]).is_equal(2)
	assert_that((merged["camera_settings"] as Dictionary)["hood_bob"]).is_equal(0.3)
	assert_that((merged["profile"] as Dictionary)["name"]).is_equal("Ana")
	assert_that((merged[MusicSettings.SAVE_KEY] as Dictionary)["volume"]).is_equal(0.4)
	assert_that(data.has(MusicSettings.SAVE_KEY)).is_false() # input untouched

func test_round_trip_through_a_real_slot_keeps_other_keys() -> void:
	SaveManager.save_game(SLOT, {"quality_preset": 1, "best_laps": {"x": 1.5}})
	var s := MusicSettings.defaults()
	s["volume"] = 0.35
	s["station"] = "f:Rock"
	s["streamer_safe"] = true
	SaveManager.save_game(SLOT, MusicSettings.merge_into_save(SaveManager.load_game(SLOT), s))
	var loaded := SaveManager.load_game(SLOT)
	assert_that(int(loaded["quality_preset"])).is_equal(1) # JSON loads whole numbers as floats
	assert_that((loaded["best_laps"] as Dictionary)["x"]).is_equal(1.5)
	var back := MusicSettings.from_save(loaded)
	assert_that(back["volume"]).is_equal_approx(0.35, 0.0001)
	assert_that(back["station"]).is_equal("f:Rock")
	assert_that(back["streamer_safe"]).is_true()

func test_folder_must_live_outside_the_project() -> void:
	assert_that(MusicSettings.is_inside_project("res://music")).is_true()
	assert_that(MusicSettings.is_inside_project(ProjectSettings.globalize_path("res://") + "assets/songs")).is_true()
	assert_that(MusicSettings.is_inside_project(ProjectSettings.globalize_path("res://").to_upper() + "x")).is_true()
	assert_that(MusicSettings.is_inside_project("D:/Music/UltraDrive")).is_false()
	assert_that(MusicSettings.is_inside_project("")).is_false()
	assert_that(MusicSettings.ensure_folder("res://music")).is_false()

func test_default_folder_and_effective_folder() -> void:
	var d := MusicSettings.defaults()
	assert_that(MusicSettings.effective_folder(d)).is_equal(MusicSettings.default_folder())
	d["folder"] = "  E:/Mine  "
	assert_that(MusicSettings.effective_folder(d)).is_equal("E:/Mine")
	if OS.get_name() == "Windows":
		assert_that(MusicSettings.default_folder()).is_equal("D:/Music/UltraDrive")
	assert_that(MusicSettings.is_inside_project(MusicSettings.default_folder())).is_false()

func test_ensure_folder_creates_a_missing_directory() -> void:
	var path := "user://music_test_ensure_%d/deep/er" % Time.get_ticks_usec()
	assert_that(MusicSettings.ensure_folder(path)).is_true()
	assert_that(DirAccess.dir_exists_absolute(path)).is_true()
	MusicTestUtil.remove_dir(path.get_base_dir().get_base_dir())
