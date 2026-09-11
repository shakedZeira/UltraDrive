# tests/test_save_manager.gd
extends GdUnitTestSuite

func test_save_and_load_roundtrip() -> void:
    var test_data := {"money": 1000, "cars": ["striker"], "license": "B"}
    var result := SaveManager.save_game(0, test_data)
    assert_that(result).is_true()
    var loaded := SaveManager.load_game(0)
    assert_that(loaded.get("money")).is_equal(1000.0)
    assert_that(loaded.get("license")).is_equal("B")

func test_load_missing_slot_returns_empty() -> void:
    var loaded := SaveManager.load_game(2)
    assert_that(loaded).is_equal({})

func test_has_save() -> void:
    assert_that(SaveManager.has_save(0)).is_true()
