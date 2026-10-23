extends GdUnitTestSuite

## SidecarLoader (ultradrive_library.json + m3u8) and its integration with the
## scanner / library: playlists become stations, the sidecar only fills fields the
## embedded tags left empty, bad input never crashes, paths cannot leave the root.

const U = preload("res://tests/suites/music_test_util.gd")

var _dir: String = ""
var _index: String = ""

func before_test() -> void:
	_dir = U.temp_dir("side")
	_index = _dir + "_index.json"

func after_test() -> void:
	U.remove_dir(_dir)
	DirAccess.remove_absolute(_index)

func _write_text(path: String, text: String) -> void:
	U.write_file(path, text.to_utf8_buffer())

func _wav() -> PackedByteArray:
	return MusicStreams.make_sine_wav(1.0)

func _scan() -> MusicLibrary:
	var scanner := MusicScanner.new()
	scanner.run_sync(_dir, _index, 0.0)
	var lib := MusicLibrary.new()
	for m in scanner.poll():
		var msg: Dictionary = m
		match String(msg["type"]):
			"meta":
				lib.set_sidecar(msg.get("sidecar", {}))
				lib.set_folder_meta(msg["meta"])
			"tracks":
				lib.add_tracks(msg["tracks"])
	return lib

# --- pure parsing ----------------------------------------------------------

func test_valid_json_parses_tracks_and_playlists() -> void:
	var text := JSON.stringify({
		"schema": 1,
		"playlists": [{"name": "Night Drive", "cover": "covers/n.jpg", "tracks": ["AbC123", "Sub/Other.OGG"]}],
		"tracks": {"AbC123": {"title": "Nightcall", "artists": ["Kavinsky", "Lovefoxxx"], "album": "OutRun", "duration_ms": 258000}},
		"mystery": 42,
	})
	var side := SidecarLoader.parse_json(text)
	assert_that(side["playlists"].size()).is_equal(1)
	var pl: Dictionary = side["playlists"][0]
	assert_that(pl["name"]).is_equal("Night Drive")
	assert_that(pl["keys"]).is_equal(["abc123", "sub/other.ogg"])
	assert_that(pl["cover"]).is_equal("covers/n.jpg")
	var t: Dictionary = side["tracks"]["abc123"]
	assert_that(t["title"]).is_equal("Nightcall")
	assert_that(t["artist"]).is_equal("Kavinsky, Lovefoxxx")
	assert_that(t["duration_s"]).is_equal_approx(258.0, 0.001)

func test_wrong_schema_bad_json_and_garbage_are_ignored() -> void:
	assert_that(SidecarLoader.parse_json("")).is_empty()
	assert_that(SidecarLoader.parse_json("not json {")).is_empty()
	assert_that(SidecarLoader.parse_json("[1,2,3]")).is_empty()
	assert_that(SidecarLoader.parse_json('{"schema": 2, "tracks": {"a": {"title": "x"}}}')).is_empty()
	assert_that(SidecarLoader.parse_json('{"tracks": {"a": {"title": "x"}}}')).is_empty()
	assert_that(SidecarLoader.parse_json('{"schema": 1}')).is_empty()
	# Wrong value types inside a valid shell do not crash and are skipped.
	var side := SidecarLoader.parse_json('{"schema": 1, "tracks": {"a": 5, "b": {"title": 7, "duration_ms": "x"}}, "playlists": [3, {"name": 1, "tracks": "no"}]}')
	assert_that(side["playlists"]).is_empty()
	assert_that(side["tracks"]["b"]["title"]).is_equal("")

func test_paths_cannot_escape_the_root() -> void:
	assert_that(SidecarLoader.safe_rel("../x.ogg")).is_equal("")
	assert_that(SidecarLoader.safe_rel("a/../../x.ogg")).is_equal("")
	assert_that(SidecarLoader.safe_rel("/etc/passwd")).is_equal("")
	assert_that(SidecarLoader.safe_rel("C:/Windows/x.ogg")).is_equal("")
	assert_that(SidecarLoader.safe_rel("res://x.ogg")).is_equal("")
	assert_that(SidecarLoader.safe_rel("a\\b\\.\\c.ogg")).is_equal("a/b/c.ogg")
	var side := SidecarLoader.parse_json('{"schema":1,"playlists":[{"name":"P","tracks":["../evil.ogg","ok.ogg"]}]}')
	assert_that(side["playlists"][0]["keys"]).is_equal(["ok.ogg"])

func test_m3u8_extinf_and_relative_paths() -> void:
	var text := "#EXTM3U\r\n#EXTINF:215,Kavinsky - Nightcall\r\nsongs/a.mp3\r\n#EXTINF:100,Just A Title\r\n..\\evil.mp3\r\nb.ogg\r\n"
	var pl := SidecarLoader.parse_m3u8(text, "Mixes", "Chill")
	assert_that(pl["name"]).is_equal("Chill")
	assert_that(pl["keys"]).is_equal(["mixes/songs/a.mp3", "mixes/b.ogg"])
	var t: Dictionary = pl["tracks"]["mixes/songs/a.mp3"]
	assert_that(t["artist"]).is_equal("Kavinsky")
	assert_that(t["title"]).is_equal("Nightcall")
	assert_that(t["duration_s"]).is_equal_approx(215.0, 0.001)
	assert_that(SidecarLoader.parse_m3u8("#EXTM3U\n", "", "Empty")).is_empty()

func test_no_sidecar_returns_empty() -> void:
	U.write_file(_dir + "/a.wav", _wav())
	assert_that(SidecarLoader.load_root(_dir)).is_empty()
	assert_that(SidecarLoader.load_root(_dir + "/missing")).is_empty()

# --- integration -----------------------------------------------------------

func test_playlists_become_ordered_stations_and_fill_empty_tags() -> void:
	U.write_file(_dir + "/37i9dQ/AAA111.wav", _wav())
	U.write_file(_dir + "/37i9dQ/BBB222.wav", _wav())
	U.write_file(_dir + "/standalone/CCC333.wav", _wav())
	U.write_file(_dir + "/37i9dQ/DDD444.wav", _wav())
	_write_text(_dir + "/ultradrive_library.json", JSON.stringify({
		"schema": 1,
		"playlists": [
			{"name": "Night Drive", "tracks": ["BBB222", "AAA111", "missing999"]},
			{"name": "Solo", "tracks": ["CCC333"]},
		],
		"tracks": {"AAA111": {"title": "Nightcall", "artists": ["Kavinsky"], "album": "OutRun"}},
	}))
	var lib := _scan()
	var names: Array[String] = []
	for s in lib.stations:
		names.append(s.display_name)
	# All Songs, the playlists in listed order, then the folder leftover (DDD444).
	assert_that(names).is_equal(["All Songs", "Night Drive", "Solo", "37i9dQ"])
	var night := lib.station_by_id("pl:Night Drive")
	assert_that(night.track_ids).is_equal(["37i9dQ/BBB222.wav", "37i9dQ/AAA111.wav"])
	assert_that(lib.station_by_id(MusicStation.ALL_ID).track_ids.size()).is_equal(4)
	assert_that(lib.station_by_id("f:37i9dQ").track_ids).is_equal(["37i9dQ/DDD444.wav"])
	var t := lib.get_track("37i9dQ/AAA111.wav")
	assert_that(t["title"]).is_equal("Nightcall")
	assert_that(t["artist"]).is_equal("Kavinsky")
	assert_that(t["album"]).is_equal("OutRun")

func test_embedded_tags_win_over_the_sidecar() -> void:
	var data := U.id3_tag(3, [U.frame(3, "TIT2", U.text_payload(0, "Tag Title"))])
	data.append_array(U.fake_mp3_frames(100))
	U.write_file(_dir + "/p/ID1.mp3", data)
	_write_text(_dir + "/ultradrive_library.json", JSON.stringify({
		"schema": 1, "tracks": {"ID1": {"title": "Sidecar Title", "artists": ["Side Artist"]}},
	}))
	var t := _scan().get_track("p/ID1.mp3")
	assert_that(t["title"]).is_equal("Tag Title")
	assert_that(t["artist"]).is_equal("Side Artist") # tag had none: sidecar fills it

func test_m3u8_playlists_become_stations() -> void:
	U.write_file(_dir + "/songs/one.wav", _wav())
	U.write_file(_dir + "/songs/two.wav", _wav())
	_write_text(_dir + "/Favourites.m3u8", "#EXTM3U\n#EXTINF:1,Artist X - Song Two\nsongs/two.wav\nsongs/one.wav\n")
	var lib := _scan()
	var fav := lib.station_by_id("pl:Favourites")
	assert_that(fav).is_not_null()
	assert_that(fav.track_ids).is_equal(["songs/two.wav", "songs/one.wav"])
	var t := lib.get_track("songs/two.wav")
	assert_that(t["title"]).is_equal("Song Two")
	assert_that(t["artist"]).is_equal("Artist X")

func test_cover_from_sidecar_when_no_other_cover_exists() -> void:
	U.write_file(_dir + "/p/ID9.wav", _wav())
	U.write_file(_dir + "/covers/c.png", U.png_bytes())
	_write_text(_dir + "/ultradrive_library.json", JSON.stringify({
		"schema": 1, "tracks": {"ID9": {"title": "T", "cover": "covers/c.png"}},
	}))
	var t := _scan().get_track("p/ID9.wav")
	assert_that(t["cover_file"]).is_equal("covers/c.png")

func test_json_sidecar_beats_m3u8_and_bad_json_falls_back_to_m3u8() -> void:
	U.write_file(_dir + "/one.wav", _wav())
	_write_text(_dir + "/ultradrive_library.json", "{ broken")
	_write_text(_dir + "/List.m3u8", "one.wav\n")
	var side := SidecarLoader.load_root(_dir)
	assert_that(side["playlists"][0]["name"]).is_equal("List")
