# tests/suites/test_music_shuffle_bag.gd
extends GdUnitTestSuite

## ShuffleBag (no-repeat shuffle) and StationQueue (history + forward stack).

func _ids(n: int) -> Array:
	var out: Array = []
	for i in range(n):
		out.append("t%02d" % i)
	return out

func test_every_track_exactly_once_per_cycle() -> void:
	var bag := ShuffleBag.new(42)
	bag.set_ids(_ids(20))
	for _cycle in range(3):
		var seen := {}
		for _i in range(20):
			var id := bag.draw()
			assert_that(seen.has(id)).is_false()
			seen[id] = true
		assert_that(seen.size()).is_equal(20)

func test_no_repeat_across_refill_boundary() -> void:
	for seed_value in range(1, 30):
		var bag := ShuffleBag.new(seed_value)
		bag.set_ids(_ids(12))
		var last: Array[String] = []
		for _i in range(12):
			last.append(bag.draw())
		var n := mini(ShuffleBag.RECENT_WINDOW, 6)
		var tail: Array = last.slice(12 - n)
		for _i in range(n):
			assert_that(tail.has(bag.draw())).is_false()

func test_same_artist_not_twice_in_a_row_when_avoidable() -> void:
	var ids: Array = []
	var artists := {}
	for i in range(10):
		var id := "a%d" % i
		ids.append(id)
		artists[id] = "Alpha"
	for i in range(10):
		var id := "b%d" % i
		ids.append(id)
		artists[id] = "Beta"
	var bag := ShuffleBag.new(5)
	bag.set_ids(ids, artists)
	var prev := ""
	var repeats := 0
	for _i in range(20):
		var id := bag.draw()
		if prev != "" and artists[prev] == artists[id]:
			repeats += 1
		prev = id
	# 3 local swaps cannot always fix a streak, but they must beat blind shuffle.
	assert_that(repeats).is_less(6)

func test_seeded_shuffle_is_deterministic() -> void:
	var a := ShuffleBag.new(1234)
	var b := ShuffleBag.new(1234)
	a.set_ids(_ids(15))
	b.set_ids(_ids(15))
	for _i in range(30):
		assert_that(a.draw()).is_equal(b.draw())

func test_empty_one_and_two_track_pools() -> void:
	var empty := ShuffleBag.new(1)
	empty.set_ids([])
	assert_that(empty.draw()).is_equal("")
	var one := ShuffleBag.new(1)
	one.set_ids(["only"])
	for _i in range(4):
		assert_that(one.draw()).is_equal("only")
	var two := ShuffleBag.new(1)
	two.set_ids(["x", "y"])
	var got: Array = [two.draw(), two.draw()]
	got.sort()
	assert_that(got).is_equal(["x", "y"])

func test_excluded_ids_are_skipped_and_all_bad_returns_empty() -> void:
	var bag := ShuffleBag.new(3)
	bag.set_ids(["a", "b", "c"])
	var bad := {"b": true}
	for _i in range(9):
		assert_that(bag.draw(bad)).is_not_equal("b")
	var all_bad := {"a": true, "b": true, "c": true}
	assert_that(bag.draw(all_bad)).is_equal("")

func test_set_ids_merges_new_tracks_without_resetting_the_cycle() -> void:
	var bag := ShuffleBag.new(8)
	bag.set_ids(_ids(6))
	var played := {}
	for _i in range(3):
		played[bag.draw()] = true
	var more := _ids(6)
	more.append("late")
	bag.set_ids(more)
	var rest := {}
	for _i in range(4):
		rest[bag.draw()] = true
	assert_that(rest.has("late")).is_true()
	for id in played:
		assert_that(rest.has(id)).is_false()

# --- StationQueue --------------------------------------------------------

func test_queue_previous_then_next_replays_the_same_sequence() -> void:
	var q := StationQueue.new(7)
	q.set_tracks(_ids(10))
	var a := q.next()
	var b := q.next()
	var c := q.next()
	assert_that(q.previous(0.5)).is_equal(b)
	assert_that(q.previous(0.5)).is_equal(a)
	assert_that(q.next()).is_equal(b)
	assert_that(q.next()).is_equal(c)
	var d := q.next() # past the forward stack: a fresh draw
	assert_that(d).is_not_equal("")
	assert_that(q.history_size()).is_equal(4)

func test_previous_after_three_seconds_restarts_the_track() -> void:
	var q := StationQueue.new(7)
	q.set_tracks(_ids(10))
	var a := q.next()
	var b := q.next()
	assert_that(q.previous(5.0)).is_equal(b)
	assert_that(q.restarted).is_true()
	assert_that(q.previous(1.0)).is_equal(a)
	assert_that(q.restarted).is_false()
	# At the very start of the history it restarts instead of going nowhere.
	assert_that(q.previous(1.0)).is_equal(a)
	assert_that(q.restarted).is_true()

func test_queue_peek_matches_next_and_does_not_consume() -> void:
	var q := StationQueue.new(9)
	q.set_tracks(_ids(10))
	q.next()
	var peeked := q.peek_next()
	assert_that(q.peek_next()).is_equal(peeked)
	assert_that(q.next()).is_equal(peeked)

func test_queue_history_is_capped() -> void:
	var q := StationQueue.new(2)
	q.set_tracks(_ids(5))
	for _i in range(StationQueue.HISTORY_CAP + 40):
		q.next()
	assert_that(q.history_size()).is_equal(StationQueue.HISTORY_CAP)
	assert_that(q.current()).is_not_equal("")

func test_unshuffled_station_plays_list_order_and_loops() -> void:
	var q := StationQueue.new(1)
	q.set_tracks(["a", "b", "c"], {}, false)
	var got: Array[String] = []
	for _i in range(7):
		got.append(q.next())
	assert_that(got).is_equal(["a", "b", "c", "a", "b", "c", "a"])

func test_queue_edge_sizes_and_bad_tracks() -> void:
	var empty := StationQueue.new(1)
	empty.set_tracks([])
	assert_that(empty.next()).is_equal("")
	assert_that(empty.previous()).is_equal("")
	var one := StationQueue.new(1)
	one.set_tracks(["solo"])
	assert_that(one.next()).is_equal("solo")
	assert_that(one.next()).is_equal("solo")
	var q := StationQueue.new(4)
	q.set_tracks(["x", "y", "z"], {}, false)
	q.mark_bad("y")
	var got: Array[String] = [q.next(), q.next(), q.next()]
	assert_that(got).is_equal(["x", "z", "x"])

func test_jump_to_drops_the_forward_stack() -> void:
	var q := StationQueue.new(6)
	q.set_tracks(_ids(8))
	q.next()
	q.next()
	q.next()
	q.previous(0.1)
	assert_that(q.has_forward()).is_true()
	q.jump_to("t03")
	assert_that(q.current()).is_equal("t03")
	assert_that(q.has_forward()).is_false()
