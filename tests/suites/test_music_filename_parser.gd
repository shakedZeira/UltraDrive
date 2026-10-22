# tests/suites/test_music_filename_parser.gd
extends GdUnitTestSuite

func test_track_number_artist_and_title() -> void:
	var r := FilenameParser.parse("01 - Daft Punk - Around the World")
	assert_that(r["track"]).is_equal(1)
	assert_that(r["artist"]).is_equal("Daft Punk")
	assert_that(r["title"]).is_equal("Around the World")

func test_dotted_number_prefix() -> void:
	var r := FilenameParser.parse("1. Some Title")
	assert_that(r["track"]).is_equal(1)
	assert_that(r["title"]).is_equal("Some Title")
	assert_that(r["artist"]).is_equal("")

func test_bracketed_number_prefix() -> void:
	var r := FilenameParser.parse("[03] Midnight City")
	assert_that(r["track"]).is_equal(3)
	assert_that(r["title"]).is_equal("Midnight City")

func test_number_with_dash_no_spaces() -> void:
	var r := FilenameParser.parse("07-Heat Waves")
	assert_that(r["track"]).is_equal(7)
	assert_that(r["title"]).is_equal("Heat Waves")

func test_zero_padded_number_with_space() -> void:
	var r := FilenameParser.parse("02 Take Me Out")
	assert_that(r["track"]).is_equal(2)
	assert_that(r["title"]).is_equal("Take Me Out")

func test_titles_starting_with_a_number_are_kept() -> void:
	var r := FilenameParser.parse("99 Problems")
	assert_that(r["track"]).is_equal(0)
	assert_that(r["title"]).is_equal("99 Problems")

func test_underscores_become_spaces() -> void:
	var r := FilenameParser.parse("Artist_Name - Song_Title")
	assert_that(r["artist"]).is_equal("Artist Name")
	assert_that(r["title"]).is_equal("Song Title")

func test_no_separator_is_all_title() -> void:
	var r := FilenameParser.parse("Just A Title")
	assert_that(r["artist"]).is_equal("")
	assert_that(r["title"]).is_equal("Just A Title")

func test_only_digits_stays_a_title() -> void:
	var r := FilenameParser.parse("1984")
	assert_that(r["title"]).is_equal("1984")
	assert_that(r["track"]).is_equal(0)

func test_spotify_id_stem_is_an_opaque_title() -> void:
	var r := FilenameParser.parse("4uLU6hMCjMI75M1A2tKUQC")
	assert_that(r["title"]).is_equal("4uLU6hMCjMI75M1A2tKUQC")
	assert_that(r["artist"]).is_equal("")

func test_unicode_and_empty() -> void:
	var r := FilenameParser.parse("05 - Björk - Jóga")
	assert_that(r["artist"]).is_equal("Björk")
	assert_that(r["title"]).is_equal("Jóga")
	var e := FilenameParser.parse("")
	assert_that(e["title"]).is_equal("")
	assert_that(e["track"]).is_equal(0)

func test_dash_without_spaces_is_not_a_separator() -> void:
	var r := FilenameParser.parse("Spider-Man Theme")
	assert_that(r["artist"]).is_equal("")
	assert_that(r["title"]).is_equal("Spider-Man Theme")
