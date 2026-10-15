class_name NorthernIsleLayout
extends RefCounted

## THE geometry source of truth for Northern Isle Speedway — GT7's smallest
## circuit (900 m, a flat banked left-turn / CCW speedway oval).
##
## Pure and static: no scene, no Resource, no engine state. Everything that
## needs "where is the road / how banked is it" (the track scene, the terrain
## bake, the dressing, the layout tests) reads it from here, so the mesh, the
## collision, the ground and the props can never drift apart.
##
## Layout (world XZ, Y up — see build_centerline() for the Y rule):
##   span A  [0.00, 130.75)  front straight, second half, travel +X
##   span B  [130.75, 319.25) turn 1 (T1, T2) around (+L/2, 0)
##   span C  [319.25, 580.75) back straight, travel -X
##   span D  [580.75, 769.25) turn 2 (T3, T4) around (-L/2, 0)
##   span E  [769.25, 900.00) front straight, first half, travel +X
## Travel is counter-clockwise seen from above (bottom-right, up the right
## side, across the top, down the left), so every turn is a LEFT turn and the
## oval's infield is always on the LEFT of travel.
##
## SIGN CONVENTION (load-bearing — both the mesh and the ground bake depend on
## it): TrackBuilder._frame() computes right = forward x UP and rotates the
## cross-section by `angle`, so cross.y = -sin(angle). A left turn (the only
## kind here) therefore needs a NEGATIVE angle, and the bank profile below
## stores signed radians in exactly that space. With
##   center_y = ROAD_BASE_Y + (WIDTH/2) * |sin(angle)|
## the LEFT (infield) edge lands on ROAD_BASE_Y and the RIGHT (outfield) edge
## rises to ROAD_BASE_Y + WIDTH*|sin(angle)| (~5.1 m at 18 deg). Changing one of
## those two without the other breaks road/ground contact — the invariant is
## pinned by tests/suites/test_northern_isle_layout.gd.

## Turn radius (m). Two 180 degree turns of this radius.
const TURN_RADIUS := 60.0
## Straight length (m). A stadium oval's two straights are necessarily equal
## (they span the same turn-center distance), so both straights use this.
const STRAIGHT_LENGTH := 261.5
## Track width (m): 3-4 NASCAR-style grooves.
const WIDTH := 16.0
## Total centerline points. 304 = 8 * 38 so every checkpoint lands exactly on a
## point, and the spacing is a uniform ~2.96 m of arc.
const TOTAL_POINTS := 304
## Point stride between checkpoints (TOTAL_POINTS / CHECKPOINT_COUNT).
const CP_STRIDE := 38
const CHECKPOINT_COUNT := 8
## Index of the start/finish line checkpoint: the LAST index, placed under the
## gantry. LapCounter ticks a lap when index (total - 1) is crossed, so the line
## MUST be the last checkpoint and the grid MUST sit on checkpoint 0 (see
## tests/suites/test_northern_isle_track.gd for the closed-loop proof).
const START_LINE_INDEX := 7
## Maximum banking (deg). Speedway-style; one constant to tune.
const BANK_MAX_DEG := 18.0
## Arc (m) over which the bank eases 0 -> BANK_MAX_DEG at each end of each turn.
const TRANSITION_ARC := 40.0
## Road base height: the infield (left) edge sits exactly here everywhere.
const ROAD_BASE_Y := 0.15
## Ground plain height outside the berm/shoulder blend (m).
const PLAIN_Y := -0.25
## Infield shoulder run: inner road edge -> plain (m).
const SHOULDER_RUN := 6.0
## Outfield embankment run: outer road edge -> plain (m). The bank sits on this
## berm, so only the outfield side needs it.
const EMBANK_RUN := 22.0

## Derived arc boundaries of the five spans (see the header comment).
const HALF_STRAIGHT := STRAIGHT_LENGTH * 0.5
const HALF_TURN_ARC := PI * TURN_RADIUS
const PERIMETER := 2.0 * STRAIGHT_LENGTH + TAU * TURN_RADIUS
const SPAN_A_END := HALF_STRAIGHT
const SPAN_B_END := SPAN_A_END + HALF_TURN_ARC
const SPAN_C_END := SPAN_B_END + STRAIGHT_LENGTH
const SPAN_D_END := SPAN_C_END + HALF_TURN_ARC

## Uniform arc-length spacing between two consecutive centerline points.
static func spacing() -> float:
	return PERIMETER / float(TOTAL_POINTS)

## Total centerline length (m). 523.0 + 376.99 = 899.99.
static func perimeter() -> float:
	return PERIMETER

## Arc length (m) from the grid (point 0) to point `index`.
static func arc_of_index(index: int) -> float:
	return float(index) * spacing()

## Bucket every centerline point into a rounded 3-decimal Vector3 so the
## determinism tests can compare two builds with is_equal().
static func build_centerline() -> Array[Vector3]:
	var points: Array[Vector3] = []
	var step := spacing()
	for i in TOTAL_POINTS:
		var s := float(i) * step
		var xz := _point_xz(s)
		var angle := _bank_rad_at_arc(s)
		var y := ROAD_BASE_Y + (WIDTH * 0.5) * absf(sin(angle))
		points.append(Vector3(xz.x, y, xz.y))
	return points

## Signed bank angle in radians per centerline point, in TrackBuilder._frame's
## sign space (negative = left turn). Zero across both straights, -18 deg
## through the middle of every turn, sine-eased over TRANSITION_ARC at each end.
static func build_bank_profile() -> PackedFloat32Array:
	var profile := PackedFloat32Array()
	profile.resize(TOTAL_POINTS)
	var step := spacing()
	for i in TOTAL_POINTS:
		profile[i] = _bank_rad_at_arc(float(i) * step)
	return profile

## Centerline indices that carry a checkpoint, in travel order: 0, 38, ... 266.
static func checkpoint_indices() -> PackedInt32Array:
	var indices := PackedInt32Array()
	for i in CHECKPOINT_COUNT:
		indices.append(i * CP_STRIDE)
	return indices

## Arc length of the start/finish line (checkpoint START_LINE_INDEX).
static func start_line_arc() -> float:
	return arc_of_index(START_LINE_INDEX * CP_STRIDE)

## Corner names in travel order. T1/T2 are the two 90 degree halves of turn 1,
## T3/T4 the two halves of turn 2 (CCW oval convention; display only today).
static func corner_names() -> Array[String]:
	var names: Array[String] = []
	for i in 4:
		names.append("T%d" % (i + 1))
	return names

## Arc range [from, to) of each corner, in the same order as corner_names().
static func corner_arc_ranges() -> Array[Vector2]:
	var half_corner := HALF_TURN_ARC * 0.5
	var ranges: Array[Vector2] = [
		Vector2(SPAN_A_END, SPAN_A_END + half_corner),
		Vector2(SPAN_A_END + half_corner, SPAN_B_END),
		Vector2(SPAN_C_END, SPAN_C_END + half_corner),
		Vector2(SPAN_C_END + half_corner, SPAN_D_END),
	]
	return ranges

## Centerline point (Y included) at arc length `s`, wrapping around the loop.
static func point_at_arc(s: float) -> Vector3:
	var arc := fposmod(s, PERIMETER)
	var xz := _point_xz(arc)
	var angle := _bank_rad_at_arc(arc)
	return Vector3(xz.x, ROAD_BASE_Y + (WIDTH * 0.5) * absf(sin(angle)), xz.y)

## Road frame at arc `s`: the same center/forward/right/cross the mesh is built
## from, so dressing placed at `center + cross * offset` sits ON the banked
## cross-section. `cross` is the banked cross direction (cross.y = -sin(bank)).
static func frame_at_arc(s: float) -> Dictionary:
	var delta := 0.25
	var a := point_at_arc(s - delta)
	var b := point_at_arc(s + delta)
	var center := point_at_arc(s)
	var forward := (b - a).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var angle := _bank_rad_at_arc(s)
	var cross := right * cos(angle) - Vector3.UP * sin(angle)
	return {
		"center": center,
		"forward": forward,
		"right": right,
		"cross": cross,
		"bank": angle,
	}

## Signed bank angle (rad) at arc `s`: 0 on the straights, easing to
## -BANK_MAX_DEG inside each turn.
static func bank_rad_at_arc(s: float) -> float:
	return _bank_rad_at_arc(s)

## Plain XZ position at arc `s` (no Y rule). Wrap is handled by the caller-safe
## fposmod here.
static func _point_xz(s: float) -> Vector2:
	var arc := fposmod(s, PERIMETER)
	var half := HALF_STRAIGHT
	if arc < SPAN_A_END:
		# Front straight, second half: (0, +R) -> (+L/2, +R), travel +X.
		return Vector2(arc, TURN_RADIUS)
	if arc < SPAN_B_END:
		# Turn 1 around (+L/2, 0): alpha runs +90deg -> -90deg (left turn).
		var u := arc - SPAN_A_END
		var alpha := PI * 0.5 - u / TURN_RADIUS
		return Vector2(half + TURN_RADIUS * cos(alpha), TURN_RADIUS * sin(alpha))
	if arc < SPAN_C_END:
		# Back straight: (+L/2, -R) -> (-L/2, -R), travel -X.
		var u := arc - SPAN_B_END
		return Vector2(half - u, -TURN_RADIUS)
	if arc < SPAN_D_END:
		# Turn 2 around (-L/2, 0): alpha runs -90deg -> -270deg (left turn).
		var u := arc - SPAN_C_END
		var alpha := -PI * 0.5 - u / TURN_RADIUS
		return Vector2(-half + TURN_RADIUS * cos(alpha), TURN_RADIUS * sin(alpha))
	# Front straight, first half: (-L/2, +R) -> (0, +R), travel +X. Holds the
	# start/finish line (arc 787.5, 18 m past the T4 exit) and, 112.5 m further
	# on, the grid at arc 0/900.
	var u := arc - SPAN_D_END
	return Vector2(-half + u, TURN_RADIUS)

## Unclamped signed bank angle (rad) at arc `s`. Left turns are negative.
static func _bank_rad_at_arc(s: float) -> float:
	var arc := fposmod(s, PERIMETER)
	var t := -1.0
	if arc >= SPAN_A_END and arc <= SPAN_B_END:
		t = arc - SPAN_A_END
	elif arc >= SPAN_C_END and arc <= SPAN_D_END:
		t = arc - SPAN_C_END
	if t < 0.0:
		return 0.0
	var ramp_in := _ease(t / TRANSITION_ARC)
	var ramp_out := _ease((HALF_TURN_ARC - t) / TRANSITION_ARC)
	return -deg_to_rad(BANK_MAX_DEG) * ramp_in * ramp_out

## Sine smoothstep on [0, 1] (clamped): 0 -> 0, 1 -> 1, ease in and out.
static func _ease(x: float) -> float:
	var v := clampf(x, 0.0, 1.0)
	return 0.5 - 0.5 * cos(PI * v)
