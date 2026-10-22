# tests/suites/test_music_id3_parser.gd
extends GdUnitTestSuite

## ID3v2.2 / 2.3 / 2.4 + ID3v1 parser gate. All tags are generated in code by
## MusicTestUtil (no binary fixtures, no real music).

const U = preload("res://tests/suites/music_test_util.gd")

func _v3_basic(enc: int = 1) -> PackedByteArray:
	return U.id3_tag(3, [
		U.frame(3, "TIT2", U.text_payload(enc, "Nightcall")),
		U.frame(3, "TPE1", U.text_payload(enc, "Kavinsky")),
		U.frame(3, "TALB", U.text_payload(enc, "OutRun")),
		U.frame(3, "TRCK", U.text_payload(enc, "3/12")),
	])

func test_v23_utf16_bom_text_frames() -> void:
	var tags := Id3Parser.parse(_v3_basic(1))
	assert_that(tags["title"]).is_equal("Nightcall")
	assert_that(tags["artist"]).is_equal("Kavinsky")
	assert_that(tags["album"]).is_equal("OutRun")
	assert_that(tags["track"]).is_equal(3)
	assert_that(tags["version"]).is_equal(3)

func test_v24_utf8_and_syncsafe_frame_sizes() -> void:
	# A 300-byte title makes the syncsafe size need two bytes (> 127).
	var long_title := "T".repeat(300)
	var tag := U.id3_tag(4, [
		U.frame(4, "TIT2", U.text_payload(3, long_title)),
		U.frame(4, "TPE1", U.text_payload(3, "Beyoncé")),
	])
	var tags := Id3Parser.parse(tag)
	assert_that(String(tags["title"]).length()).is_equal(300)
	assert_that(tags["artist"]).is_equal("Beyoncé")

func test_v22_three_char_frames_and_pic() -> void:
	var png := U.png_bytes()
	var tag := U.id3_tag(2, [
		U.frame(2, "TT2", U.text_payload(0, "Old Song")),
		U.frame(2, "TP1", U.text_payload(0, "Old Band")),
		U.frame(2, "TAL", U.text_payload(0, "Old Album")),
		U.frame(2, "TRK", U.text_payload(0, "7")),
		U.frame(2, "PIC", U.apic_payload("PNG", 3, png, true)),
	])
	var tags := Id3Parser.parse(tag, true)
	assert_that(tags["title"]).is_equal("Old Song")
	assert_that(tags["artist"]).is_equal("Old Band")
	assert_that(tags["album"]).is_equal("Old Album")
	assert_that(tags["track"]).is_equal(7)
	assert_that(tags["has_cover"]).is_true()
	assert_that(tags["cover_mime"]).is_equal("image/png")
	assert_that((tags["cover"] as PackedByteArray).size()).is_equal(png.size())

func test_text_encodings_latin1_utf16be_utf16le() -> void:
	for enc in [0, 1, 2, 3]:
		var tag := U.id3_tag(3, [U.frame(3, "TIT2", U.text_payload(enc, "Café del Mar"))])
		assert_that(Id3Parser.parse(tag)["title"]).is_equal("Café del Mar")

func test_utf16_surrogate_pair() -> void:
	var s := "Fire " + String.chr(0x1F525)
	var tag := U.id3_tag(3, [U.frame(3, "TIT2", U.text_payload(1, s))])
	assert_that(Id3Parser.parse(tag)["title"]).is_equal(s)

func test_multi_value_artist_is_joined() -> void:
	var payload := PackedByteArray([3])
	payload.append_array("Daft Punk".to_utf8_buffer())
	payload.append(0)
	payload.append_array("Pharrell".to_utf8_buffer())
	var tag := U.id3_tag(4, [U.frame(4, "TPE1", payload)])
	assert_that(Id3Parser.parse(tag)["artist"]).is_equal("Daft Punk, Pharrell")

func test_unsynchronisation_is_undone() -> void:
	var png := PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0xFF, 0x00, 0xFF, 0xE0, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
	var tag := U.id3_tag(3, [
		U.frame(3, "TIT2", U.text_payload(3, "Sync")),
		U.frame(3, "APIC", U.apic_payload("image/png", 3, png)),
	], 0x80)
	var tags := Id3Parser.parse(tag, true)
	assert_that(tags["title"]).is_equal("Sync")
	assert_bool((tags["cover"] as PackedByteArray) == png).is_true()

func test_apic_prefers_front_cover_over_first_picture() -> void:
	var back := U.png_bytes(4, 4)
	var front := U.jpg_bytes(6, 6)
	var tag := U.id3_tag(3, [
		U.frame(3, "APIC", U.apic_payload("image/png", 4, back)),
		U.frame(3, "APIC", U.apic_payload("image/jpeg", 3, front)),
	])
	var tags := Id3Parser.parse(tag, true)
	assert_that(tags["cover_mime"]).is_equal("image/jpeg")
	assert_bool((tags["cover"] as PackedByteArray) == front).is_true()

func test_without_want_cover_no_bytes_but_flag() -> void:
	var tag := U.id3_tag(3, [U.frame(3, "APIC", U.apic_payload("image/png", 3, U.png_bytes()))])
	var tags := Id3Parser.parse(tag, false)
	assert_that(tags["has_cover"]).is_true()
	assert_that(tags.has("cover")).is_false()

func test_extended_header_and_padding_are_skipped() -> void:
	# v2.3 extended header: size 6 (excl. itself) + flags + padding size + 0 crc bytes.
	var ext := U.u32be(6)
	ext.append_array(PackedByteArray([0, 0, 0, 0, 0, 0]))
	var tag := U.id3_tag(3, [U.frame(3, "TIT2", U.text_payload(0, "Ext"))], 0x40, 64, ext)
	assert_that(Id3Parser.parse(tag)["title"]).is_equal("Ext")

func test_truncated_tag_keeps_earlier_frames() -> void:
	var tag := U.id3_tag(3, [
		U.frame(3, "TIT2", U.text_payload(0, "Kept")),
		U.frame(3, "APIC", U.apic_payload("image/png", 3, U.png_bytes(64, 64))),
	])
	var cut := tag.slice(0, tag.size() - 40)
	var tags := Id3Parser.parse(cut)
	assert_that(tags["title"]).is_equal("Kept")
	assert_that(tags.has("has_cover")).is_false()

func test_garbage_and_short_input_return_empty() -> void:
	assert_that(Id3Parser.parse(PackedByteArray()).is_empty()).is_true()
	assert_that(Id3Parser.parse(PackedByteArray([1, 2, 3])).is_empty()).is_true()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for _i in range(40):
		var junk := PackedByteArray()
		for _j in range(200):
			junk.append(rng.randi_range(0, 255))
		Id3Parser.parse(junk, true) # must not throw
	var fake_header := PackedByteArray([0x49, 0x44, 0x33, 3, 0, 0, 0, 0, 0, 20, 0xFF, 0xFF, 0xFF, 0xFF, 1, 2, 3])
	assert_that(Id3Parser.parse(fake_header).has("title")).is_false()

func test_unknown_version_is_rejected() -> void:
	var tag := _v3_basic()
	tag[3] = 9
	assert_that(Id3Parser.parse(tag).is_empty()).is_true()
	assert_that(Id3Parser.tag_total_size(tag)).is_equal(0)

func test_tag_total_size_includes_header_and_footer() -> void:
	var tag := _v3_basic()
	assert_that(Id3Parser.tag_total_size(tag.slice(0, 10))).is_equal(tag.size())
	var v4 := U.id3_tag(4, [U.frame(4, "TIT2", U.text_payload(0, "x"))], 0x10)
	assert_that(Id3Parser.tag_total_size(v4.slice(0, 10))).is_equal(v4.size() + 10)

func test_id3v1_trailer() -> void:
	var v1 := U.id3v1("Old Title", "Old Artist", "Old Album", 5)
	var tags := Id3Parser.parse_v1(v1)
	assert_that(tags["title"]).is_equal("Old Title")
	assert_that(tags["artist"]).is_equal("Old Artist")
	assert_that(tags["album"]).is_equal("Old Album")
	assert_that(tags["track"]).is_equal(5)
	assert_that(Id3Parser.parse_v1(PackedByteArray([1, 2, 3])).is_empty()).is_true()

func test_tlen_is_read_in_milliseconds() -> void:
	var tag := U.id3_tag(3, [U.frame(3, "TLEN", U.text_payload(0, "258000"))])
	assert_that(Id3Parser.parse(tag)["length_ms"]).is_equal(258000)
