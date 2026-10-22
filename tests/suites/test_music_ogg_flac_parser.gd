# tests/suites/test_music_ogg_flac_parser.gd
extends GdUnitTestSuite

## Ogg Vorbis comment + FLAC block parsers, built from generated header bytes.

const U = preload("res://tests/suites/music_test_util.gd")

func test_vorbis_comments_case_insensitive_keys() -> void:
	var bytes := U.ogg_vorbis(["title=Lower Case", "ARTIST=Band", "Album=The Album", "tracknumber=4/10", "AlbumArtist=Various"])
	var tags := OggCommentParser.parse(bytes)
	assert_that(tags["title"]).is_equal("Lower Case")
	assert_that(tags["artist"]).is_equal("Band")
	assert_that(tags["album"]).is_equal("The Album")
	assert_that(tags["track"]).is_equal(4)
	assert_that(tags["album_artist"]).is_equal("Various")
	assert_that(tags["sample_rate"]).is_equal(44100)
	assert_that(tags["channels"]).is_equal(2)

func test_multiple_artist_entries_are_joined() -> void:
	var tags := OggCommentParser.parse(U.ogg_vorbis(["ARTIST=A", "ARTIST=B"]))
	assert_that(tags["artist"]).is_equal("A, B")

func test_comment_packet_spanning_pages() -> void:
	# ~140 KB of comment data -> three pages (65025-byte chunks).
	var filler := "x".repeat(140000)
	var bytes := U.ogg_vorbis(["COMMENT=" + filler, "TITLE=After The Gap", "ARTIST=Late Artist"])
	var tags := OggCommentParser.parse(bytes)
	assert_that(tags["title"]).is_equal("After The Gap")
	assert_that(tags["artist"]).is_equal("Late Artist")

func test_metadata_block_picture_base64() -> void:
	var png := U.png_bytes(8, 8)
	var block := U.flac_picture_block("image/png", 3, png)
	var b64 := Marshalls.raw_to_base64(block)
	var bytes := U.ogg_vorbis(["TITLE=With Art", "METADATA_BLOCK_PICTURE=" + b64])
	var plain := OggCommentParser.parse(bytes, false)
	assert_that(plain["has_cover"]).is_true()
	assert_that(plain["cover_mime"]).is_equal("image/png")
	assert_that(plain.has("cover")).is_false()
	var full := OggCommentParser.parse(bytes, true)
	assert_bool((full["cover"] as PackedByteArray) == png).is_true()

func test_oversize_picture_is_rejected() -> void:
	var block := U.flac_picture_block("image/png", 3, PackedByteArray([1, 2, 3]))
	# Declare an absurd data length (> 8 MB) in the last 4 header bytes.
	var data_len_at := block.size() - 3 - 4
	var huge := U.u32be(OggCommentParser.MAX_COVER_BYTES + 1)
	for i in range(4):
		block[data_len_at + i] = huge[i]
	var tags := OggCommentParser.parse(U.ogg_vorbis(["METADATA_BLOCK_PICTURE=" + Marshalls.raw_to_base64(block)]), true)
	assert_that(tags.has("cover")).is_false()
	assert_that(tags.has("has_cover")).is_false()

func test_last_granule_gives_duration() -> void:
	var bytes := U.ogg_vorbis(["TITLE=T"], 48000, 48000 * 95)
	var tail := bytes.slice(maxi(0, bytes.size() - 64))
	assert_that(OggCommentParser.last_granule(tail)).is_equal(48000 * 95)
	assert_that(OggCommentParser.last_granule(PackedByteArray([1, 2, 3]))).is_equal(0)

func test_truncated_and_garbage_input_never_throws() -> void:
	var bytes := U.ogg_vorbis(["TITLE=Survivor", "ARTIST=Cut Off"])
	for cut in [0, 5, 20, 27, 40, 80, bytes.size() - 3]:
		OggCommentParser.parse(bytes.slice(0, cut), true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for _i in range(30):
		var junk := PackedByteArray([0x4F, 0x67, 0x67, 0x53])
		for _j in range(300):
			junk.append(rng.randi_range(0, 255))
		OggCommentParser.parse(junk, true)
	assert_that(OggCommentParser.parse(PackedByteArray()).is_empty()).is_true()

func test_truncated_comment_packet_keeps_leading_comments() -> void:
	var bytes := U.ogg_vorbis(["TITLE=Early", "COMMENT=" + "y".repeat(3000)])
	var tags := OggCommentParser.parse(bytes.slice(0, 175))
	assert_that(tags.get("title", "")).is_equal("Early")

func test_flac_streaminfo_duration_and_comments() -> void:
	var bytes := U.flac_file(["TITLE=Lossless", "ARTIST=Studio"], 44100, 44100 * 200)
	var tags := FlacParser.parse(bytes)
	assert_that(tags["title"]).is_equal("Lossless")
	assert_that(tags["artist"]).is_equal("Studio")
	assert_that(tags["sample_rate"]).is_equal(44100)
	assert_that(float(tags["duration_s"])).is_equal_approx(200.0, 0.01)

func test_flac_picture_block() -> void:
	var jpg := U.jpg_bytes(8, 8)
	var bytes := U.flac_file(["TITLE=Pic"], 44100, 44100, U.flac_picture_block("image/jpeg", 3, jpg))
	var tags := FlacParser.parse(bytes, true)
	assert_that(tags["has_cover"]).is_true()
	assert_that(tags["cover_mime"]).is_equal("image/jpeg")
	assert_bool((tags["cover"] as PackedByteArray) == jpg).is_true()

func test_flac_truncated_and_non_flac() -> void:
	var bytes := U.flac_file(["TITLE=Cut"], 44100, 44100)
	FlacParser.parse(bytes.slice(0, 30), true)
	assert_that(FlacParser.parse(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])).is_empty()).is_true()
