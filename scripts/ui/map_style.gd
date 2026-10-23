# scripts/ui/map_style.gd
class_name MapStyle
extends RefCounted

## One visual language for every 2D map (race-menu circuit map, pause world map,
## HUD minimap), modelled on the Forza Horizon map: a stylised satellite backdrop,
## thin light roads with a highway/arterial hierarchy, bold round pins with an
## event-type glyph, a bright route ribbon, a big player arrow, soft vignette.
##
## Pure statics and constants only. Drawing helpers take the CanvasItem they must
## be called from (inside that item's _draw), so the three maps share pixels, not
## copies of the code. Nothing here reads the scene tree, so every lookup is
## headless-testable.

# --- palette ---------------------------------------------------------------
const OCEAN_DEEP := Color(0.035, 0.105, 0.195)
const OCEAN_MID := Color(0.060, 0.185, 0.290)
const LAND_BASE := Color(0.390, 0.470, 0.290)
const PANEL_DARK := Color(0.035, 0.050, 0.085, 0.86)
const PANEL_EDGE := Color(1.0, 1.0, 1.0, 0.14)
const TEXT_LIGHT := Color(0.96, 0.97, 0.99)
const TEXT_DIM := Color(0.78, 0.82, 0.88, 0.85)
const SHADOW := Color(0.0, 0.0, 0.0, 0.42)
const PIN_RING := Color(1.0, 1.0, 1.0, 0.97)
const ACCENT := Color(1.0, 0.80, 0.18)

# --- road hierarchy ----------------------------------------------------------
## Style per RoadDef.Tier. Core is the visible line, casing the dark edge under
## it. Width is in screen px at zoom 1. Highways read thickest and warmest; the
## arterial net is white; touge/coastal are a notch thinner; dirt is sand.
## Order matters: lower `rank` draws first (under), so highways sit on top.
const ROAD_STYLES := {
	0: {"core": Color(1.0, 0.86, 0.45), "casing": Color(0.30, 0.20, 0.04, 0.85), "width": 4.2, "rank": 4, "name": "Highway"},
	1: {"core": Color(1.0, 1.0, 1.0), "casing": Color(0.05, 0.07, 0.10, 0.80), "width": 3.2, "rank": 3, "name": "Arterial"},
	2: {"core": Color(0.90, 0.95, 1.0), "casing": Color(0.05, 0.07, 0.10, 0.75), "width": 2.4, "rank": 2, "name": "Mountain road"},
	3: {"core": Color(0.82, 0.96, 1.0), "casing": Color(0.04, 0.10, 0.16, 0.75), "width": 2.4, "rank": 2, "name": "Coastal road"},
	4: {"core": Color(0.86, 0.76, 0.56), "casing": Color(0.12, 0.08, 0.03, 0.70), "width": 2.0, "rank": 1, "name": "Dirt track"},
}
const ROAD_STYLE_DEFAULT := {"core": Color(0.95, 0.97, 1.0), "casing": Color(0.05, 0.07, 0.10, 0.80), "width": 2.8, "rank": 2, "name": "Road"}
## An unexplored road keeps its hierarchy but fades back, like the FH fog of war.
const UNVISITED_FADE := 0.42
const UNVISITED_DESAT := 0.55

## The style dictionary for a RoadDef.Tier value (unknown tiers fall back).
static func road_style(tier: int) -> Dictionary:
	if ROAD_STYLES.has(tier):
		return ROAD_STYLES[tier]
	return ROAD_STYLE_DEFAULT

## Road core colour for an explored/unexplored road of this tier.
static func road_core(tier: int, visited: bool) -> Color:
	var core: Color = road_style(tier)["core"]
	if visited:
		return core
	var luma := core.r * 0.299 + core.g * 0.587 + core.b * 0.114
	var grey := Color(luma, luma, luma)
	var faded := core.lerp(grey, UNVISITED_DESAT)
	faded.a = UNVISITED_FADE
	return faded

static func road_casing(tier: int, visited: bool) -> Color:
	var casing: Color = road_style(tier)["casing"]
	if not visited:
		casing.a *= 0.55
	return casing

static func road_width(tier: int) -> float:
	return float(road_style(tier)["width"])

## Draw order: ascending rank, so a highway is drawn after (above) a dirt track.
static func road_rank(tier: int) -> int:
	return int(road_style(tier)["rank"])

# --- event families ------------------------------------------------------------
## Colour + glyph per EventRegistry kind. Every family has a distinct colour AND
## glyph so a pin never relies on colour alone.
const EVENT_STYLES := {
	"touge_duel": {"color": Color(0.30, 0.62, 1.00), "glyph": "duel", "label": "Touge Duel"},
	"drag_strip": {"color": Color(0.96, 0.30, 0.28), "glyph": "drag", "label": "Drag Strip"},
	"drift_zone": {"color": Color(0.70, 0.40, 0.95), "glyph": "drift", "label": "Drift Zone"},
	"night_street_loop": {"color": Color(0.38, 0.40, 0.92), "glyph": "moon", "label": "Night Loop"},
	"marathon_highway": {"color": Color(0.98, 0.58, 0.14), "glyph": "marathon", "label": "Highway Marathon"},
	"time_attack": {"color": Color(0.20, 0.80, 0.62), "glyph": "clock", "label": "Time Attack"},
	"outbreak": {"color": Color(0.64, 0.80, 0.20), "glyph": "outbreak", "label": "Outbreak"},
	"convoy": {"color": Color(0.96, 0.46, 0.66), "glyph": "convoy", "label": "Convoy"},
}
const EVENT_STYLE_DEFAULT := {"color": Color(0.30, 0.62, 1.00), "glyph": "flag", "label": "Event"}
const LANDMARK_STYLE := {"color": Color(0.99, 0.80, 0.22), "glyph": "star", "label": "Landmark"}
## Collectible glyphs; the colours stay in Collectibles.KIND_DOT_COLOR.
const COLLECTIBLE_GLYPHS := {
	"bonus_board": "board",
	"speed_trap": "radar",
	"photo_spot": "camera",
}

static func event_style(kind: String) -> Dictionary:
	if EVENT_STYLES.has(kind):
		return EVENT_STYLES[kind]
	return EVENT_STYLE_DEFAULT

static func event_color(kind: String) -> Color:
	return event_style(kind)["color"]

## The glyph id a POI dictionary draws with: collectible kind, event kind, or the
## landmark star.
static func poi_glyph(poi: Dictionary) -> String:
	var kind := str(poi.get("kind", ""))
	if COLLECTIBLE_GLYPHS.has(kind):
		return COLLECTIBLE_GLYPHS[kind]
	if poi.has("kind"):
		return str(event_style(kind)["glyph"])
	return str(LANDMARK_STYLE["glyph"])

# --- race-menu circuits ---------------------------------------------------------
## Class colours follow the Forza class ladder (D lowest).
const CLASS_COLORS := {
	"D": Color(0.20, 0.78, 0.92),
	"C": Color(1.00, 0.84, 0.20),
	"B": Color(1.00, 0.55, 0.14),
	"A": Color(0.96, 0.30, 0.30),
	"S": Color(0.66, 0.38, 0.96),
	"X": Color(0.45, 0.88, 0.32),
}
const CIRCUIT_GLYPHS := {
	"CIRCUIT": "flag",
	"OVAL": "oval",
	"DIRT RX": "dirt",
	"ENDURANCE": "clock",
}

static func class_color(difficulty: String) -> Color:
	if CLASS_COLORS.has(difficulty):
		return CLASS_COLORS[difficulty]
	return ACCENT

static func circuit_glyph(circuit_type: String) -> String:
	if CIRCUIT_GLYPHS.has(circuit_type):
		return CIRCUIT_GLYPHS[circuit_type]
	return "flag"

# --- drawing ---------------------------------------------------------------------

## Letter-spaced uppercase label centred on `center` (FH region captions): drawn
## glyph by glyph, with a dark outline so it survives any backdrop.
static func draw_spaced_label(canvas: CanvasItem, font: Font, text: String, center: Vector2,
		font_size: int, color: Color, tracking: float, outline: Color = Color(0, 0, 0, 0.55)) -> void:
	if font == null or text.is_empty():
		return
	var width := spaced_text_width(font, text, font_size, tracking)
	var x := center.x - width * 0.5
	var y := center.y + font.get_ascent(font_size) - font.get_height(font_size) * 0.5
	for i in text.length():
		var ch := text.substr(i, 1)
		canvas.draw_string_outline(font, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, outline)
		canvas.draw_string(font, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + tracking

static func spaced_text_width(font: Font, text: String, font_size: int, tracking: float) -> float:
	if font == null or text.is_empty():
		return 0.0
	var width := 0.0
	for i in text.length():
		width += font.get_string_size(text.substr(i, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return width + tracking * float(text.length() - 1)

## A pill label (dark rounded plate + text) anchored with its LEFT-CENTRE at `at`.
## Returns the plate rect so callers can hit-test or collide against it.
static func draw_pill_label(canvas: CanvasItem, font: Font, text: String, at: Vector2,
		font_size: int, text_color: Color = TEXT_LIGHT, plate: Color = PANEL_DARK) -> Rect2:
	if font == null or text.is_empty():
		return Rect2()
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad := Vector2(7.0, 3.0)
	var rect := Rect2(at - Vector2(0.0, text_size.y * 0.5 + pad.y), text_size + pad * 2.0)
	var box := StyleBoxFlat.new()
	box.bg_color = plate
	box.set_corner_radius_all(int(rect.size.y * 0.5))
	box.border_color = PANEL_EDGE
	box.set_border_width_all(1)
	canvas.draw_style_box(box, rect)
	canvas.draw_string(font, rect.position + pad + Vector2(0.0, font.get_ascent(font_size)), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
	return rect

## The circular badge every pin shares: drop shadow, white ring, colour fill,
## then the glyph. `r` is the fill radius in px.
static func draw_badge(canvas: CanvasItem, center: Vector2, r: float, fill: Color, glyph: String,
		glyph_color: Color = Color.WHITE, ring: Color = PIN_RING) -> void:
	canvas.draw_circle(center + Vector2(0.0, r * 0.22), r + 3.0, SHADOW)
	canvas.draw_circle(center, r + 2.0, ring)
	canvas.draw_circle(center, r, fill)
	# A light top-left sheen makes the badge read as a raised button.
	canvas.draw_arc(center, r - 1.2, PI * 1.05, PI * 1.75, 14, Color(1, 1, 1, 0.28), 1.6, true)
	draw_glyph(canvas, glyph, center, r * 0.58, glyph_color)

## Teardrop pin whose TIP sits at `tip` (race-menu circuits): a badge raised on a
## pointed tail. Returns the badge centre.
static func draw_teardrop(canvas: CanvasItem, tip: Vector2, r: float, fill: Color, glyph: String,
		glyph_color: Color = Color.WHITE, ring: Color = PIN_RING) -> Vector2:
	var center := tip + Vector2(0.0, -(r * 1.9))
	var half := r * 0.78
	var tail := PackedVector2Array([
		center + Vector2(-half, r * 0.45),
		center + Vector2(half, r * 0.45),
		tip,
	])
	var shade := PackedVector2Array()
	for p in tail:
		shade.append(p + Vector2(0.0, 2.0))
	canvas.draw_circle(tip, r * 0.32, Color(0, 0, 0, 0.35))
	canvas.draw_colored_polygon(tail, ring)
	canvas.draw_circle(center, r + 2.0, ring)
	var inner := PackedVector2Array([
		center + Vector2(-half + 2.0, r * 0.4),
		center + Vector2(half - 2.0, r * 0.4),
		tip + Vector2(0.0, -3.0),
	])
	canvas.draw_colored_polygon(inner, fill)
	canvas.draw_circle(center, r, fill)
	canvas.draw_arc(center, r - 1.2, PI * 1.05, PI * 1.75, 14, Color(1, 1, 1, 0.28), 1.6, true)
	draw_glyph(canvas, glyph, center, r * 0.58, glyph_color)
	return center

## Event/place glyphs, drawn inside a badge. `s` is the half-size in px; every
## glyph fits a 2s x 2s box so they are interchangeable.
static func draw_glyph(canvas: CanvasItem, glyph: String, c: Vector2, s: float, col: Color) -> void:
	var w := maxf(1.5, s * 0.34)
	match glyph:
		"flag":
			# Chequered flag: pole + 2x2 chequer.
			canvas.draw_line(c + Vector2(-s * 0.78, s), c + Vector2(-s * 0.78, -s), col, w * 0.8)
			var q := s * 0.62
			var o := c + Vector2(-s * 0.7, -s)
			for iy in 2:
				for ix in 2:
					if (ix + iy) % 2 == 0:
						canvas.draw_rect(Rect2(o + Vector2(ix * q, iy * q), Vector2(q, q)), col)
					else:
						canvas.draw_rect(Rect2(o + Vector2(ix * q, iy * q), Vector2(q, q)), col, false, 1.0)
		"oval":
			canvas.draw_arc(c, s * 0.92, 0.0, TAU, 20, col, w, true)
			canvas.draw_circle(c, s * 0.28, col)
		"dirt":
			var z := PackedVector2Array([
				c + Vector2(-s, s * 0.5), c + Vector2(-s * 0.35, -s * 0.5),
				c + Vector2(s * 0.2, s * 0.5), c + Vector2(s, -s * 0.5)])
			canvas.draw_polyline(z, col, w, true)
		"clock":
			canvas.draw_arc(c, s * 0.9, 0.0, TAU, 20, col, w, true)
			canvas.draw_line(c, c + Vector2(0.0, -s * 0.62), col, w * 0.8)
			canvas.draw_line(c, c + Vector2(s * 0.45, s * 0.2), col, w * 0.8)
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var ang := -PI * 0.5 + float(i) * PI * 0.2
				var rr := s * (1.05 if i % 2 == 0 else 0.46)
				pts.append(c + Vector2(cos(ang), sin(ang)) * rr)
			canvas.draw_colored_polygon(pts, col)
		"duel":
			# Two opposing chevrons: head-to-head.
			for dir in [-1.0, 1.0]:
				var base: float = dir * s * 0.95
				canvas.draw_polyline(PackedVector2Array([
					c + Vector2(base, -s * 0.7), c + Vector2(base - dir * s * 0.8, 0.0),
					c + Vector2(base, s * 0.7)]), col, w, true)
		"drag":
			# Straight-line burst: arrow with a launch bar.
			canvas.draw_line(c + Vector2(-s, 0.0), c + Vector2(s * 0.7, 0.0), col, w)
			canvas.draw_polyline(PackedVector2Array([
				c + Vector2(s * 0.15, -s * 0.65), c + Vector2(s * 0.95, 0.0),
				c + Vector2(s * 0.15, s * 0.65)]), col, w, true)
			canvas.draw_line(c + Vector2(-s, -s * 0.65), c + Vector2(-s, s * 0.65), col, w)
		"drift":
			# A sliding S-curve.
			canvas.draw_arc(c + Vector2(0.0, -s * 0.46), s * 0.5, PI * 0.1, PI * 1.5, 12, col, w, true)
			canvas.draw_arc(c + Vector2(0.0, s * 0.46), s * 0.5, PI * 1.1, PI * 2.5, 12, col, w, true)
		"moon":
			# A crescent is a thick arc: no need to carve a disc out of a disc.
			canvas.draw_arc(c + Vector2(s * 0.12, 0.0), s * 0.7, PI * 0.5, PI * 1.5, 16, col, w * 1.9, true)
		"marathon":
			# Three speed dashes: a long road.
			for i in 3:
				var y := (float(i) - 1.0) * s * 0.62
				canvas.draw_line(c + Vector2(-s + float(i) * s * 0.18, y), c + Vector2(s - float(2 - i) * s * 0.18, y), col, w)
		"outbreak":
			canvas.draw_circle(c, s * 0.3, col)
			canvas.draw_arc(c, s * 0.7, 0.0, TAU, 16, col, w * 0.8, true)
			canvas.draw_arc(c, s * 1.05, PI * 0.2, PI * 0.8, 8, col, w * 0.7, true)
			canvas.draw_arc(c, s * 1.05, PI * 1.2, PI * 1.8, 8, col, w * 0.7, true)
		"convoy":
			for i in 3:
				canvas.draw_circle(c + Vector2((float(i) - 1.0) * s * 0.78, 0.0), s * 0.34, col)
		"board":
			# Bonus board: a sign on a post.
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.9, -s * 0.9), Vector2(s * 1.8, s * 1.1)), col)
			canvas.draw_line(c + Vector2(0.0, s * 0.2), c + Vector2(0.0, s), col, w * 0.8)
		"radar":
			canvas.draw_circle(c + Vector2(0.0, s * 0.5), s * 0.24, col)
			canvas.draw_arc(c + Vector2(0.0, s * 0.5), s * 0.7, PI * 1.2, PI * 1.8, 8, col, w * 0.8, true)
			canvas.draw_arc(c + Vector2(0.0, s * 0.5), s * 1.15, PI * 1.2, PI * 1.8, 8, col, w * 0.8, true)
		"camera":
			canvas.draw_rect(Rect2(c + Vector2(-s, -s * 0.55), Vector2(s * 2.0, s * 1.35)), col)
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.35, -s * 0.9), Vector2(s * 0.7, s * 0.4)), col)
			canvas.draw_circle(c + Vector2(0.0, s * 0.12), s * 0.38, Color(0, 0, 0, 0.55))
		_:
			canvas.draw_circle(c, s * 0.5, col)

## The route ribbon: soft glow, white edge, bright core. All three share the one
## polyline so the shape is identical; widths are screen px.
static func draw_route_ribbon(canvas: CanvasItem, path: PackedVector2Array, core: Color,
		width: float, time: float = 0.0) -> void:
	if path.size() < 2:
		return
	canvas.draw_polyline(path, Color(core.r, core.g, core.b, 0.20), width + 9.0, true)
	canvas.draw_polyline(path, Color(0.04, 0.05, 0.08, 0.85), width + 4.0, true)
	canvas.draw_polyline(path, Color(1.0, 1.0, 1.0, 0.96), width + 2.0, true)
	canvas.draw_polyline(path, core, width, true)
	# Direction chevrons marching along the ribbon (time-driven, cheap).
	var spacing := maxf(width * 7.0, 28.0)
	var offset := fposmod(time * spacing * 0.8, spacing)
	var travelled := 0.0
	var next_mark := offset
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var seg := a.distance_to(b)
		if seg <= 0.001:
			continue
		var dir := (b - a) / seg
		var perp := Vector2(-dir.y, dir.x)
		while next_mark <= travelled + seg:
			var p := a + dir * (next_mark - travelled)
			var k := width * 0.55
			canvas.draw_polyline(PackedVector2Array([p - dir * k + perp * k, p + dir * k * 0.4, p - dir * k - perp * k]),
				Color(1, 1, 1, 0.9), maxf(1.2, width * 0.28), true)
			next_mark += spacing
		travelled += seg

## The destination flag at the end of a route.
static func draw_destination(canvas: CanvasItem, at: Vector2, color: Color, r: float = 10.0) -> void:
	draw_teardrop(canvas, at, r, color, "flag")

# --- vignette ---------------------------------------------------------------------

## A square white-to-black radial alpha ramp used as the soft screen vignette
## (drawn stretched over a rect with a dark modulate). `strength` is the edge
## alpha, `inner` the radius fraction where the darkening starts.
static func make_vignette_image(px: int = 128, inner: float = 0.55, strength: float = 0.62) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var half := float(px) * 0.5
	for y in px:
		for x in px:
			# Squared-distance in normalised space keeps corners darker than edges,
			# which is what a screen vignette looks like on a wide rect.
			var d := Vector2((float(x) + 0.5 - half) / half, (float(y) + 0.5 - half) / half)
			var r := maxf(absf(d.x), absf(d.y)) * 0.55 + d.length() * 0.45
			var t := clampf((r - inner) / (1.0 - inner + 0.35), 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, t * strength))
	return img
