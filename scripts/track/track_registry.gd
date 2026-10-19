class_name TrackRegistry
extends RefCounted

## Static registry of every drivable track: id -> { display_name, scene_path,
## laps_default, difficulty, circuit_type }.

static var tracks: Dictionary = {
	"oval": {
		"display_name": "Sunset Oval",
		"scene_path": "res://scenes/test/test_track.tscn",
		"laps_default": 3,
		"difficulty": "D",
		"circuit_type": "CIRCUIT",
	},
	"mountain_pass": {
		"display_name": "Mountain Pass",
		"scene_path": "res://scenes/track/mountain_pass.tscn",
		"laps_default": 2,
		"difficulty": "B",
		"circuit_type": "CIRCUIT",
	},
	"northern_isle": {
		"display_name": "Northern Isle Speedway",
		"scene_path": "res://scenes/track/northern_isle.tscn",
		"laps_default": 5,
		"difficulty": "D",
		"circuit_type": "OVAL",
	},
	"barcelona_rx": {
		"display_name": "Barcelona Rallycross",
		"scene_path": "res://scenes/track/barcelona_rx.tscn",
		"laps_default": 3,
		"difficulty": "D",
		"circuit_type": "DIRT RX",
	},
	"le_mans": {
		"display_name": "Le Mans No-Chicane",
		"scene_path": "res://scenes/track/le_mans.tscn",
		"laps_default": 1,
		"difficulty": "A",
		"circuit_type": "ENDURANCE",
	},
}

static func get_track_ids() -> Array:
	return tracks.keys()

static func get_track(track_id: String) -> Dictionary:
	return tracks.get(track_id, {})

static func get_scene_path(track_id: String) -> String:
	return get_track(track_id).get("scene_path", "")

static func has_track(track_id: String) -> bool:
	return tracks.has(track_id)

# ---------------------------------------------------------------------------
# CIRCUIT PINS (additive — `tracks` above is deliberately untouched)
# ---------------------------------------------------------------------------
# `tracks` stays the single list of drivable LAYOUTS (a scene + default laps).
# `pins` below is a SEPARATE, many-to-one table: "where the shipped layouts are
# sold as circuits" (a real host location, or an invented Israeli circuit).
# Keeping them apart is the whole design:
#   * race_ui._resolve_track_id() returns the FIRST registry id whose scene_path
#     matches, so duplicate/padded `tracks` entries would silently mis-key
#     best-lap records; pins keep records keyed per LAYOUT, on purpose.
#   * `tracks` order/membership is load-bearing for tests (contains_exactly) and
#     for the pause-map / GPS registry consumers, so it must not grow here.
# Adding a circuit = one entry in `pins` and nothing else.

## Region framing ids. A pin's "region" picks which framing box (and which
## backdrop tier) shows it; it is presentation-only per-instance menu state and
## is never persisted.
##
## REGION_WORLD is the ALL-CIRCUITS overview tier: it frames the whole globe and
## its membership is EVERY pin (see pin_ids_for_region), so it is never a pin's
## stored `region`. The continent ids split the old single world list into small
## legible regions; each non-Israeli pin is tagged with exactly ONE of them
## (membership is the per-pin field, never box containment — continent boxes
## overlap over empty ocean/desert and that is harmless).
const REGION_ISRAEL: String = "israel"
const REGION_WORLD: String = "world"
const REGION_EUROPE: String = "europe"
const REGION_MIDDLE_EAST: String = "middle_east"
const REGION_NORTH_AMERICA: String = "north_america"
const REGION_ASIA: String = "asia"
const REGION_SOUTH_AMERICA: String = "south_america"
const REGION_AFRICA: String = "africa"
const REGION_OCEANIA: String = "oceania"
const DEFAULT_REGION: String = REGION_ISRAEL

## pin_id -> { label, lat, lon, region, track_id, host }.
##   label    - circuit name shown on the pin and the circuit card.
##   lat/lon  - real-world placement (degrees). Positional, not survey accuracy.
##   region   - EXACTLY ONE of REGION_ISRAEL + the seven continent ids (never
##              REGION_WORLD, which is the all-circuits overview tier).
##   track_id - MUST exist in `tracks`: the fictional layout actually driven.
##   host     - "" for invented circuits, else the real host's country flavour.
## Order is insertion order (Godot Dictionaries keep it) = the menu's card order;
## the Israeli pins come first so the default selection is Israeli.
static var pins: Dictionary = {
	# --- HOME: the 3 shipped layouts, labelled with their registry display_name.
	# --- First so the default selection (pins[0]) is a shipped track.
	"home_sunset_oval": {
		"label": "Sunset Oval",
		"lat": 29.5500, "lon": 34.9500,
		"region": REGION_ISRAEL, "track_id": "oval", "host": "",
	},
	"home_mountain_pass": {
		"label": "Mountain Pass",
		"lat": 33.0500, "lon": 35.7500,
		"region": REGION_ISRAEL, "track_id": "mountain_pass", "host": "",
	},
	"home_northern_isle": {
		"label": "Northern Isle Speedway",
		"lat": 33.1000, "lon": 35.0200,
		"region": REGION_ISRAEL, "track_id": "northern_isle", "host": "",
	},
	# --- Invented Israeli circuits (ids/coords UNCHANGED) ---
	"haifa_coastal_ring": {
		"label": "Haifa Coastal Ring",
		"lat": 32.7940, "lon": 34.9896,
		"region": REGION_ISRAEL, "track_id": "mountain_pass", "host": "",
	},
	"galilee_circuit": {
		"label": "Sea of Galilee Circuit",
		"lat": 32.7167, "lon": 35.6167,
		"region": REGION_ISRAEL, "track_id": "northern_isle", "host": "",
	},
	"negev_speedway": {
		"label": "Negev Speedway",
		"lat": 31.2589, "lon": 34.7997,
		"region": REGION_ISRAEL, "track_id": "oval", "host": "",
	},
	# --- Global calendar: 6 existing (unchanged) + 24 later = 30, plus the two
	# --- rallycross venue pins added with build #2 (holjes, loheac) = 32;
	# --- sebring (stand-in -> le_mans) added with Le Mans No-Chicane = 33.
	# --- Each is tagged with exactly one continent region (see D3 of
	# --- docs/plans/race_menu_regions_zoom_plan.md).
	"silverstone": {
		"label": "Silverstone Circuit, UK",
		"lat": 52.0786, "lon": -1.0169,
		"region": REGION_EUROPE, "track_id": "mountain_pass", "host": "United Kingdom",
	},
	"spa": {
		"label": "Circuit de Spa-Francorchamps, BE",
		"lat": 50.4372, "lon": 5.9714,
		"region": REGION_EUROPE, "track_id": "mountain_pass", "host": "Belgium",
	},
	# `nurburgring` carries the `le_mans` layout: the plan (§4 step 8) named the
	# `spa` pin for this "swap a lie for a truth", but `spa` is a fixture in TWO
	# existing suites (`test_race_menu_map.gd` and `test_race_layout_preview.gd`
	# both `select_pin("spa")` and expect `mountain_pass` + 2 laps). A9 requires
	# `test_race_menu_map` UNMODIFIED and §4 forbids touching existing assertions,
	# so the identical swap lands on the next European ENDURANCE venue instead
	# (Nurburgring 24h), leaving every existing test's setup and asserts intact.
	"nurburgring": {
		"label": "Nurburgring Nordschleife, DE",
		"lat": 50.3356, "lon": 6.9475,
		"region": REGION_EUROPE, "track_id": "le_mans", "host": "Germany",
	},
	"monza": {
		"label": "Autodromo Nazionale Monza, IT",
		"lat": 45.6156, "lon": 9.2811,
		"region": REGION_EUROPE, "track_id": "northern_isle", "host": "Italy",
	},
	"suzuka": {
		"label": "Suzuka Circuit, JP",
		"lat": 34.8431, "lon": 136.5407,
		"region": REGION_ASIA, "track_id": "northern_isle", "host": "Japan",
	},
	"interlagos": {
		"label": "Autodromo Jose Carlos Pace, BR",
		"lat": -23.7036, "lon": -46.6997,
		"region": REGION_SOUTH_AMERICA, "track_id": "oval", "host": "Brazil",
	},
	"monaco": {
		"label": "Circuit de Monaco, MC",
		"lat": 43.7347, "lon": 7.4206,
		"region": REGION_EUROPE, "track_id": "mountain_pass", "host": "Monaco",
	},
	"imola": {
		"label": "Autodromo Enzo e Dino Ferrari, IT",
		"lat": 44.3439, "lon": 11.7167,
		"region": REGION_EUROPE, "track_id": "mountain_pass", "host": "Italy",
	},
	"zandvoort": {
		"label": "Circuit Zandvoort, NL",
		"lat": 52.3888, "lon": 4.5409,
		"region": REGION_EUROPE, "track_id": "mountain_pass", "host": "Netherlands",
	},
	"spielberg": {
		"label": "Red Bull Ring, AT",
		"lat": 47.2197, "lon": 14.7647,
		"region": REGION_EUROPE, "track_id": "mountain_pass", "host": "Austria",
	},
	"portimao": {
		"label": "Autodromo Internacional do Algarve, PT",
		"lat": 37.2272, "lon": -8.6272,
		"region": REGION_EUROPE, "track_id": "mountain_pass", "host": "Portugal",
	},
	"watkins_glen": {
		"label": "Watkins Glen International, US",
		"lat": 42.3369, "lon": -76.9272,
		"region": REGION_NORTH_AMERICA, "track_id": "mountain_pass", "host": "United States",
	},
	"laguna_seca": {
		"label": "WeatherTech Raceway Laguna Seca, US",
		"lat": 36.5844, "lon": -121.7533,
		"region": REGION_NORTH_AMERICA, "track_id": "mountain_pass", "host": "United States",
	},
	"bathurst": {
		"label": "Mount Panorama, AU",
		"lat": -33.4489, "lon": 149.5661,
		"region": REGION_OCEANIA, "track_id": "mountain_pass", "host": "Australia",
	},
	"kyalami": {
		"label": "Kyalami Grand Prix Circuit, ZA",
		"lat": -25.9894, "lon": 28.0669,
		"region": REGION_AFRICA, "track_id": "mountain_pass", "host": "South Africa",
	},
	"hungaroring": {
		"label": "Hungaroring, HU",
		"lat": 47.5789, "lon": 19.2486,
		"region": REGION_EUROPE, "track_id": "mountain_pass", "host": "Hungary",
	},
	"bahrain": {
		"label": "Bahrain International Circuit, BH",
		"lat": 26.0325, "lon": 50.5106,
		"region": REGION_MIDDLE_EAST, "track_id": "northern_isle", "host": "Bahrain",
	},
	"jeddah": {
		"label": "Jeddah Corniche Circuit, SA",
		"lat": 21.6319, "lon": 39.1044,
		"region": REGION_MIDDLE_EAST, "track_id": "northern_isle", "host": "Saudi Arabia",
	},
	"abu_dhabi": {
		"label": "Yas Marina Circuit, AE",
		"lat": 24.4672, "lon": 54.6031,
		"region": REGION_MIDDLE_EAST, "track_id": "northern_isle", "host": "United Arab Emirates",
	},
	"cota": {
		"label": "Circuit of the Americas, US",
		"lat": 30.1328, "lon": -97.6411,
		"region": REGION_NORTH_AMERICA, "track_id": "northern_isle", "host": "United States",
	},
	"miami": {
		"label": "Miami International Autodrome, US",
		"lat": 25.9581, "lon": -80.2389,
		"region": REGION_NORTH_AMERICA, "track_id": "northern_isle", "host": "United States",
	},
	"barcelona": {
		"label": "Barcelona Rallycross",
		"lat": 41.5700, "lon": 2.2611,
		"region": REGION_EUROPE, "track_id": "barcelona_rx", "host": "Spain",
	},
	"holjes": {
		"label": "Holjes Rallycross, SE",
		"lat": 60.0500, "lon": 13.2400,
		"region": REGION_EUROPE, "track_id": "barcelona_rx", "host": "Sweden",
	},
	"loheac": {
		"label": "Loheac Rallycross, FR",
		"lat": 47.9397, "lon": -2.0061,
		"region": REGION_EUROPE, "track_id": "barcelona_rx", "host": "France",
	},
	"le_mans": {
		"label": "Le Mans No-Chicane",
		"lat": 47.9500, "lon": 0.2086,
		"region": REGION_EUROPE, "track_id": "le_mans", "host": "France",
	},
	"brands_hatch": {
		"label": "Brands Hatch, UK",
		"lat": 51.3597, "lon": 0.2628,
		"region": REGION_EUROPE, "track_id": "northern_isle", "host": "United Kingdom",
	},
	"fuji": {
		"label": "Fuji Speedway, JP",
		"lat": 35.3717, "lon": 138.9267,
		"region": REGION_ASIA, "track_id": "northern_isle", "host": "Japan",
	},
	"sepang": {
		"label": "Sepang International Circuit, MY",
		"lat": 2.7608, "lon": 101.7375,
		"region": REGION_ASIA, "track_id": "northern_isle", "host": "Malaysia",
	},
	"hockenheim": {
		"label": "Hockenheimring, DE",
		"lat": 49.3278, "lon": 8.5658,
		"region": REGION_EUROPE, "track_id": "northern_isle", "host": "Germany",
	},
	"las_vegas": {
		"label": "Las Vegas Motor Speedway, US",
		"lat": 36.2711, "lon": -115.0114,
		"region": REGION_NORTH_AMERICA, "track_id": "oval", "host": "United States",
	},
	"daytona": {
		"label": "Daytona International Speedway, US",
		"lat": 29.1856, "lon": -81.0700,
		"region": REGION_NORTH_AMERICA, "track_id": "oval", "host": "United States",
	},
	"indianapolis": {
		"label": "Indianapolis Motor Speedway, US",
		"lat": 39.7950, "lon": -86.2347,
		"region": REGION_NORTH_AMERICA, "track_id": "oval", "host": "United States",
	},
	# The sebring pin is a STAND-IN: it drives the `le_mans` layout because the
	# game has no Sebring layout yet (same stand-in class as the old `spa` lie
	# this replaced, §8.4 -- revisit when a real Sebring layout exists).
	"sebring": {
		"label": "Sebring, US",
		"lat": 27.4500, "lon": -81.3500,
		"region": REGION_NORTH_AMERICA, "track_id": "le_mans", "host": "United States",
	},
}

## Framing + presentation data per region. The four min/max keys are a plain
## lon/lat box; the map contain-fits it (the zoom/pan VIEW state lives in
## TrackMap, not here). Membership is NOT this box: it is each pin's own
## `region` field (see pin_ids_for_region), so a box may overlap a neighbour
## over empty ocean/desert, and may be widened for framing, without ever
## silently re-homing a circuit.
##   display_name    - the menu tab label.
##   graticule_step  - degrees between grid lines when this region is drawn.
##   backdrop        - "world" (equirectangular SVG raster) | "vector".
## REGION_ISRAEL's box is the pin-coverage box grown ~1.5 degrees.
## Insertion order = menu tab order = get_region_ids() order.
static var regions: Dictionary = {
	REGION_WORLD: {
		"display_name": "ALL CIRCUITS",
		"min_lon": -180.0, "min_lat": -90.0, "max_lon": 180.0, "max_lat": 90.0,
		"graticule_step": 30.0, "backdrop": "world",
	},
	REGION_ISRAEL: {
		"display_name": "ISRAEL",
		"min_lon": 33.0, "min_lat": 28.8, "max_lon": 36.5, "max_lat": 34.2,
		"graticule_step": 1.0, "backdrop": "vector",
	},
	REGION_EUROPE: {
		"display_name": "EUROPE",
		"min_lon": -25.0, "min_lat": 34.0, "max_lon": 45.0, "max_lat": 72.0,
		"graticule_step": 10.0, "backdrop": "world",
	},
	REGION_MIDDLE_EAST: {
		"display_name": "MIDDLE EAST",
		"min_lon": 36.5, "min_lat": 10.0, "max_lon": 62.0, "max_lat": 42.0,
		"graticule_step": 10.0, "backdrop": "world",
	},
	REGION_NORTH_AMERICA: {
		"display_name": "N. AMERICA",
		"min_lon": -170.0, "min_lat": 10.0, "max_lon": -50.0, "max_lat": 75.0,
		"graticule_step": 10.0, "backdrop": "world",
	},
	REGION_ASIA: {
		"display_name": "ASIA",
		"min_lon": 60.0, "min_lat": -12.0, "max_lon": 180.0, "max_lat": 75.0,
		"graticule_step": 10.0, "backdrop": "world",
	},
	REGION_SOUTH_AMERICA: {
		"display_name": "S. AMERICA",
		"min_lon": -85.0, "min_lat": -56.0, "max_lon": -30.0, "max_lat": 13.0,
		"graticule_step": 10.0, "backdrop": "world",
	},
	REGION_AFRICA: {
		"display_name": "AFRICA",
		"min_lon": -20.0, "min_lat": -36.0, "max_lon": 60.0, "max_lat": 36.0,
		"graticule_step": 10.0, "backdrop": "world",
	},
	REGION_OCEANIA: {
		"display_name": "OCEANIA",
		"min_lon": 110.0, "min_lat": -50.0, "max_lon": 180.0, "max_lat": -10.0,
		"graticule_step": 10.0, "backdrop": "world",
	},
}

static func get_pin_ids() -> Array:
	return pins.keys()

static func get_pin(pin_id: String) -> Dictionary:
	return pins.get(pin_id, {})

static func has_pin(pin_id: String) -> bool:
	return pins.has(pin_id)

## The layout (`tracks`) id a pin drives, or "" for an unknown pin.
static func track_for_pin(pin_id: String) -> String:
	var pin := get_pin(pin_id)
	return str(pin.get("track_id", "")) if not pin.is_empty() else ""

## Every pin id that drives the given layout, in pin-table order. This is the
## many-to-one contract made explicit (several circuits share one layout; e.g.
## mountain_pass is driven by Haifa + Silverstone + Spa + Nurburgring).
static func pins_for_track(track_id: String) -> Array:
	var out: Array = []
	for pin_id: Variant in pins:
		if track_for_pin(str(pin_id)) == track_id:
			out.append(pin_id)
	return out

## Pin ids that belong to a region, in pin-table order. REGION_WORLD is the
## ALL-CIRCUITS overview tier and is a documented special case: it returns EVERY
## pin, so the map's visible set and this read can never disagree.
static func pin_ids_for_region(region_id: String) -> Array:
	if region_id == REGION_WORLD:
		return pins.keys()
	var out: Array = []
	for pin_id: Variant in pins:
		if str(get_pin(str(pin_id)).get("region", "")) == region_id:
			out.append(pin_id)
	return out

static func has_region(region_id: String) -> bool:
	return regions.has(region_id)

## Every region id in menu tab order (WORLD overview first, then ISRAEL, then
## the continents).
static func get_region_ids() -> Array:
	return regions.keys()

## The menu tab label for a region ("ALL CIRCUITS", "EUROPE", ...), falling back
## to the upper-cased id when the region is unknown.
static func region_label(region_id: String) -> String:
	var meta: Dictionary = regions.get(region_id, {})
	if meta.is_empty():
		return region_id.to_upper()
	return str(meta.get("display_name", region_id.to_upper()))

## The full presentation record for a region: display_name, min_lon, min_lat,
## max_lon, max_lat, graticule_step, backdrop. {} for an unknown region.
static func region_meta(region_id: String) -> Dictionary:
	return regions.get(region_id, {})

## The lon/lat framing box for a region: {min_lon, min_lat, max_lon, max_lat}.
## Returns the same record as region_meta() (frame + presentation keys), so
## callers that only need the box read the four keys they know.
static func region_bounds(region_id: String) -> Dictionary:
	return regions.get(region_id, {})
