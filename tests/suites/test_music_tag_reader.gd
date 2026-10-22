# tests/suites/test_music_tag_reader.gd
extends GdUnitTestSuite

## TagReader: header-only reads from generated files, the field fallback chain
## (tag -> file name -> stem / folder), cover reads and the never-throws contract.

const U = preload("res://tests/suites/music_test_util.gd")

var _dir: String = ""

func before_test() -> void:
	_dir = U.temp_dir("tags")

func after_test() -> void:
	U.remove_dir(_dir)

func test_mp3_id3v23_tags_and_xing_duration() -> void:
	var data := U.id3_tag(3, [
		U.frame(3, "TIT2", U.text_payload(1, "Tagged Song")),
		U.frame(3, "TPE1", U.text_payload(1, "Tagged Artist")),
		U.frame(3, "TALB", U.text_payload(1, "Tagged Album")),
		U.frame(3, "APIC", U.apic_payload("image/png", 3, U.png_bytes())),
	])
	# 1000 MPEG-1 frames of 1152 samples at 44.1 kHz = 26.122 s
	data.append_array(U.fake_mp3_frames(1000))
	var path := _dir + "/song.mp3"
	U.write_file(path, data)
	var raw := TagReader.read_raw(path)
	assert_that(raw["title"]).is_equal("Tagged Song")
	assert_that(raw["artist"]).is_equal("Tagged Artist")
	assert_that(raw["album"]).is_equal("Tagged Album")
	assert_that(raw["has_cover"]).is_true()
	assert_that(float(raw["duration_s"])).is_equal_approx(1000.0 * 1152.0 / 44100.0, 0.01)

func test_mp3_cbr_duration_estimate_without_xing() -> void:
	var frames := PackedByteArray()
	for _i in range(100):
		var f := PackedByteArray([0xFF, 0xFB, 0x90, 0x00])
		f.resize(417)
		frames.append_array(f)
	var path := _dir + "/cbr.mp3"
	U.write_file(path, frames)
	var raw := TagReader.read_raw(path)
	# 41700 bytes at 128 kbps = 2.606 s
	assert_that(float(raw["duration_s"])).is_equal_approx(41700.0 * 8.0 / 128000.0, 0.01)

func test_mp3_id3v1_fills_gaps_when_no_v2() -> void:
	var data := U.fake_mp3_frames(10)
	data.append_array(U.id3v1("V1 Title", "V1 Artist", "V1 Album", 2))
	var path := _dir + "/old.mp3"
	U.write_file(path, data)
	var raw := TagReader.read_raw(path)
	assert_that(raw["title"]).is_equal("V1 Title")
	assert_that(raw["artist"]).is_equal("V1 Artist")
	assert_that(raw["track_no"]).is_equal(2)

func test_ogg_tags_and_duration() -> void:
	var bytes := U.ogg_vorbis(["TITLE=Ogg Song", "ARTIST=Ogg Band"], 44100, 44100 * 120)
	var path := _dir + "/track.ogg"
	U.write_file(path, bytes)
	var raw := TagReader.read_raw(path)
	assert_that(raw["title"]).is_equal("Ogg Song")
	assert_that(raw["artist"]).is_equal("Ogg Band")
	assert_that(float(raw["duration_s"])).is_equal_approx(120.0, 0.01)

func test_wav_duration_from_header() -> void:
	var path := _dir + "/tone.wav"
	U.write_file(path, MusicStreams.make_sine_wav(1.5, 440.0, 8000))
	var raw := TagReader.read_raw(path)
	assert_that(float(raw["duration_s"])).is_equal_approx(1.5, 0.01)
	assert_that(String(raw["title"])).is_equal("")

func test_flac_is_labelled_not_decoded() -> void:
	var path := _dir + "/lossless.flac"
	U.write_file(path, U.flac_file(["TITLE=FLAC Title", "ARTIST=FLAC Artist"], 44100, 44100 * 61))
	var raw := TagReader.read_raw(path)
	assert_that(raw["title"]).is_equal("FLAC Title")
	assert_that(float(raw["duration_s"])).is_equal_approx(61.0, 0.01)

func test_read_cover_extracts_embedded_picture() -> void:
	var png := U.png_bytes(6, 6)
	var data := U.id3_tag(3, [U.frame(3, "APIC", U.apic_payload("image/png", 3, png))])
	data.append_array(U.fake_mp3_frames(5))
	var path := _dir + "/art.mp3"
	U.write_file(path, data)
	var cover := TagReader.read_cover(path)
	assert_that(cover["mime"]).is_equal("image/png")
	assert_bool((cover["data"] as PackedByteArray) == png).is_true()
	assert_that(TagReader.read_cover(_dir + "/missing.mp3").is_empty()).is_true()

func test_never_throws_on_random_bytes_or_missing_files() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for ext in ["mp3", "ogg", "wav", "flac", "m4a"]:
		var junk := PackedByteArray()
		for _i in range(5000):
			junk.append(rng.randi_range(0, 255))
		var path := "%s/junk.%s" % [_dir, ext]
		U.write_file(path, junk)
		var raw := TagReader.read_raw(path)
		assert_that(raw.has("title")).is_true()
		TagReader.read_cover(path)
	var missing := TagReader.read_raw(_dir + "/nope.mp3")
	assert_that(float(missing["duration_s"])).is_equal(0.0)
	U.write_file(_dir + "/empty.mp3", PackedByteArray())
	assert_that(String(TagReader.read_raw(_dir + "/empty.mp3")["title"])).is_equal("")

# --- fallback chain (pure) ----------------------------------------------

func test_resolve_prefers_tag_over_filename() -> void:
	var raw := {"title": "Real Title", "artist": "Real Artist", "album": "Alb", "track_no": 9, "duration_s": 12.0, "has_cover": false, "cover_mime": ""}
	var r := TagReader.resolve(raw, "Rock/01 - File Artist - File Title.mp3")
	assert_that(r["title"]).is_equal("Real Title")
	assert_that(r["artist"]).is_equal("Real Artist")
	assert_that(r["track_no"]).is_equal(9)

func test_resolve_falls_back_to_filename_then_folder_then_placeholder() -> void:
	var empty := {"title": "", "artist": "", "album": "", "track_no": 0, "duration_s": 0.0, "has_cover": false, "cover_mime": ""}
	var from_name := TagReader.resolve(empty, "Rock/04 - Band - Song.mp3")
	assert_that(from_name["title"]).is_equal("Song")
	assert_that(from_name["artist"]).is_equal("Band")
	assert_that(from_name["track_no"]).is_equal(4)
	var folder_artist := TagReader.resolve(empty, "Chill Beats/just a title.ogg")
	assert_that(folder_artist["title"]).is_equal("just a title")
	assert_that(folder_artist["artist"]).is_equal("Chill Beats")
	var root_file := TagReader.resolve(empty, "lonely.wav")
	assert_that(root_file["title"]).is_equal("lonely")
	assert_that(root_file["artist"]).is_equal("Unknown Artist")

func test_resolve_uses_album_artist_when_artist_missing() -> void:
	var raw := {"title": "T", "artist": "", "album_artist": "Various Artists", "album": "", "track_no": 0, "duration_s": 0.0, "has_cover": false, "cover_mime": ""}
	assert_that(TagReader.resolve(raw, "x/t.mp3")["artist"]).is_equal("Various Artists")
