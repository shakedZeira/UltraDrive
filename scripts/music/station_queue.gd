# scripts/music/station_queue.gd
class_name StationQueue
extends RefCounted

## Play order of one station: a ShuffleBag (or the plain list order when shuffle
## is off) plus a capped history with a forward stack, so
##   previous -> next replays the SAME sequence instead of drawing at random.
## Pure data structure (no audio, no nodes) - fully unit-testable.

const HISTORY_CAP := 100
## "Previous" after this many seconds restarts the current track instead.
const RESTART_AFTER_S := 3.0

var shuffle: bool = true
## True when the last previous() call restarted the current track.
var restarted: bool = false
## Tracks that failed to load this session (id -> true); never drawn again.
var bad: Dictionary = {}

var _bag: ShuffleBag
var _order: Array[String] = []
var _order_pos: int = -1
var _history: Array[String] = []
var _cursor: int = -1
var _peek: String = ""

func _init(seed_value: int = 0) -> void:
	_bag = ShuffleBag.new(seed_value)

## Replace the station's tracks. Keeps history and the current track.
func set_tracks(ids: Array, artists: Dictionary = {}, shuffle_on: bool = true) -> void:
	shuffle = shuffle_on
	var typed: Array[String] = []
	for id in ids:
		typed.append(String(id))
	_bag.set_ids(typed, artists)
	var cur := current()
	_order = typed
	_order_pos = _order.find(cur) if not cur.is_empty() else -1
	_peek = ""

func size() -> int:
	return _order.size()

func current() -> String:
	if _cursor < 0 or _cursor >= _history.size():
		return ""
	return _history[_cursor]

func history_size() -> int:
	return _history.size()

## True when next() would replay a previously played track (after previous()).
func has_forward() -> bool:
	return _cursor >= 0 and _cursor < _history.size() - 1

## The id next() will return, without consuming it ("" if none).
func peek_next() -> String:
	if has_forward():
		return _history[_cursor + 1]
	if _peek.is_empty():
		_peek = _draw()
	return _peek

func next() -> String:
	restarted = false
	var id := ""
	if has_forward():
		_cursor += 1
		return _history[_cursor]
	id = _peek if not _peek.is_empty() else _draw()
	_peek = ""
	if id.is_empty():
		return ""
	_push(id)
	return id

## Previous track. After RESTART_AFTER_S seconds into a track, or with nothing
## earlier in the history, the current track is returned (restarted = true).
func previous(elapsed_s: float = 0.0) -> String:
	restarted = false
	if _cursor < 0:
		return ""
	if elapsed_s > RESTART_AFTER_S or _cursor == 0:
		restarted = true
		return _history[_cursor]
	_cursor -= 1
	return _history[_cursor]

## Make `id` the current track (drops the forward part of the history).
func jump_to(id: String) -> void:
	if id.is_empty():
		return
	restarted = false
	_peek = ""
	_push(id)

func mark_bad(id: String) -> void:
	bad[id] = true
	if _peek == id:
		_peek = ""

func clear_history() -> void:
	_history.clear()
	_cursor = -1
	_peek = ""

func _push(id: String) -> void:
	if _cursor < _history.size() - 1:
		_history.resize(_cursor + 1)
	_history.append(id)
	_cursor = _history.size() - 1
	while _history.size() > HISTORY_CAP:
		_history.pop_front()
		_cursor -= 1
	var at := _order.find(id)
	if at >= 0:
		_order_pos = at

func _draw() -> String:
	if _order.is_empty():
		return ""
	if shuffle:
		return _bag.draw(bad)
	# List order, looping; skips bad tracks.
	var n := _order.size()
	var pos := _order_pos
	for _i in range(n):
		pos = (pos + 1) % n
		if not bad.has(_order[pos]):
			return _order[pos]
	return ""
