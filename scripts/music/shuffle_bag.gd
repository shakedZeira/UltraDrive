# scripts/music/shuffle_bag.gd
class_name ShuffleBag
extends RefCounted

## No-repeat shuffle: a permutation of the track ids is played through, then
## refilled with a fresh shuffle. Guarantees
##   * every id exactly once per cycle,
##   * the first N draws after a refill differ from the last N played
##     (N = min(5, size / 2)),
##   * soft "same artist twice in a row" avoidance (up to 3 local swaps),
##   * seedable (RandomNumberGenerator) for deterministic tests.

const RECENT_WINDOW := 5
const ARTIST_SWAPS := 3

var _rng := RandomNumberGenerator.new()
var _ids: Array[String] = []
var _bag: Array[String] = []
var _artists: Dictionary = {}
var _recent: Array[String] = []
var _last_artist: String = ""

func _init(seed_value: int = 0) -> void:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()

## Replace the pool. Played-state is kept: ids already gone from the bag stay out
## until the next refill; brand-new ids are slipped into the bag at random spots.
func set_ids(ids: Array, artists: Dictionary = {}) -> void:
	var fresh: Array[String] = []
	for id in ids:
		fresh.append(String(id))
	_artists = artists
	var known := {}
	for id in _ids:
		known[id] = true
	var wanted := {}
	for id in fresh:
		wanted[id] = true
	var kept: Array[String] = []
	for id in _bag:
		if wanted.has(id):
			kept.append(id)
	_bag = kept
	if known.is_empty():
		_ids = fresh
		_bag = []
		if not _ids.is_empty():
			_refill()
		return
	for id in fresh:
		if not known.has(id):
			var at := _rng.randi_range(0, _bag.size())
			_bag.insert(at, id)
	_ids = fresh
	if _bag.is_empty() and not _ids.is_empty():
		_refill()

func size() -> int:
	return _ids.size()

func remaining() -> int:
	return _bag.size()

## Next id, or "" when the pool is empty (or every candidate is excluded).
## `exclude` is a Dictionary id -> true (bad tracks).
func draw(exclude: Dictionary = {}) -> String:
	if _ids.is_empty():
		return ""
	for _attempt in range(_ids.size() + 1):
		if _bag.is_empty():
			_refill()
		if _bag.is_empty():
			return ""
		_prefer_other_artist()
		var id: String = _bag.pop_front()
		if exclude.has(id):
			continue
		_note_played(id)
		return id
	return ""

func _note_played(id: String) -> void:
	_recent.append(id)
	var cap := maxi(RECENT_WINDOW, 1)
	while _recent.size() > cap:
		_recent.pop_front()
	_last_artist = String(_artists.get(id, ""))

func _refill() -> void:
	_bag = _ids.duplicate()
	# Fisher-Yates.
	for i in range(_bag.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: String = _bag[i]
		_bag[i] = _bag[j]
		_bag[j] = tmp
	# Keep the head of the new cycle away from what was just played.
	var n := mini(RECENT_WINDOW, _ids.size() >> 1)
	if n > 0 and not _recent.is_empty():
		var last_n: Array[String] = _recent.slice(maxi(0, _recent.size() - n))
		var head: Array[String] = []
		var tail: Array[String] = []
		for id in _bag:
			if head.size() < n and not last_n.has(id):
				head.append(id)
			else:
				tail.append(id)
		head.append_array(tail)
		_bag = head

func _prefer_other_artist() -> void:
	if _last_artist.is_empty() or _bag.size() < 2:
		return
	if String(_artists.get(_bag[0], "")) != _last_artist:
		return
	var limit := mini(ARTIST_SWAPS, _bag.size() - 1)
	for k in range(1, limit + 1):
		if String(_artists.get(_bag[k], "")) != _last_artist:
			var tmp: String = _bag[0]
			_bag[0] = _bag[k]
			_bag[k] = tmp
			return
