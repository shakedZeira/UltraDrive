# scripts/music/filename_parser.gd
class_name FilenameParser
extends RefCounted

## "01 - Artist - Title", "1. Title", "[03] Title", "01-Title", "Artist - Title"
## -> { artist, title, track }. Pure, never throws. Used only when the embedded
## tags are empty. A stem that is only digits ("1984") stays a title.

static var _lead_bracket: RegEx = null
static var _lead_sep: RegEx = null
static var _lead_zero: RegEx = null

static func _compile() -> void:
	if _lead_bracket != null:
		return
	_lead_bracket = RegEx.create_from_string("^\\s*[\\[(](\\d{1,3})[\\])]\\s*[-.]?\\s*")
	_lead_sep = RegEx.create_from_string("^\\s*(\\d{1,3})\\s*[-.)]\\s*")
	_lead_zero = RegEx.create_from_string("^\\s*(0\\d{1,2})\\s+")

static func parse(stem: String) -> Dictionary:
	_compile()
	var out := {"artist": "", "title": "", "track": 0}
	var s := stem.replace("_", " ").strip_edges()
	if s.is_empty():
		return out
	var rest := s
	for rx in [_lead_bracket, _lead_sep, _lead_zero]:
		var m: RegExMatch = (rx as RegEx).search(rest)
		if m != null:
			var remainder := rest.substr(m.get_end()).strip_edges()
			if remainder.is_empty():
				continue
			out["track"] = int(m.get_string(1))
			rest = remainder
			break
	# Split on the first " - " (also en/em dash with spaces).
	var cut := -1
	var sep_len := 3
	for sep in [" - ", " – ", " — "]:
		var at := rest.find(sep)
		if at >= 0 and (cut < 0 or at < cut):
			cut = at
			sep_len = sep.length()
	if cut > 0:
		var left := rest.substr(0, cut).strip_edges()
		var right := rest.substr(cut + sep_len).strip_edges()
		if not left.is_empty() and not right.is_empty():
			out["artist"] = left
			out["title"] = right
			return out
	out["title"] = rest
	return out
