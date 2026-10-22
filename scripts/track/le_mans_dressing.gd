class_name LeMansDressing
extends Node3D

## Circuit dressing for the Le Mans No-Chicane circuit (plan
## docs/plans/track_le_mans_no_chicane.md §3.8, extended by
## docs/plans/le_mans_visual_realism_plan.md WS-A/C/D/E/F). SELF-CONTAINED: this
## class never extends or reuses `RxDressing`, whose `rx_dressing.gd` is on the
## v1 plan's do-not-touch list and whose kit is sized for a 1.1 km circuit.
##
## WHAT IT BUILDS
##   v1 (§3.8):
##   * gantry  — 1 fused portal (posts + beam + neutral, UN-LETTERED banner) at
##       the S/F line (arc 0). No text at all (§7 gotcha 8, no trademarks).
##   * paint   — 1 generated 8x2 checker slab on the carriageway at the line.
##   * arch    — 1 Dunlop-bridge-shaped arch at chainage 869, neutral banner.
##   * hedge   — lumpy hedgerow blocks along the Mulsanne, 2,000-7,300 m.
##   * tyre    — tyre-stack braking markers at the five §3.8 braking zones.
##   * kerb    — red/white apex kerbs on the INNER edge of every sharp corner.
##   * post    — marshal post towers on a 1,500 m cadence, alternating sides.
##   Visual-realism plan:
##   * WS-A trap / runoff — sand/gravel traps (ragged ribbon meshes with a
##       grass-blended fringe) behind paved run-off aprons on the OUTSIDE of
##       Tertre Rouge, Mulsanne, Indianapolis, Arnage and the Ford chicane, plus
##       sausage kerbs at the Ford chicane. Every trap/apron polygon is also
##       registered in `SurfaceRegistry` (SAND / ASPHALT) while the dressing is
##       in the tree -- visuals and grip from ONE source of truth.
##   * WS-C armco (FULL LAP, both sides, W-beam profile; pushed out behind the
##       traps; gaps at the marshal posts), catch fence (chain-link,
##       alpha-scissor + visibility range) at corner complexes and the S/F
##       straight, double tyre walls + blue/white barrier panels at braking
##       corners.
##   * WS-D ad boards (unbranded, three colour sets), countdown boards before
##       the braking corners, TV camera towers, service-road dirt tracks.
##   * WS-E tree lines: a near forest edge (30-65 m) along the lap with real
##       gaps, a far canopy ring (300-1,100 m) for horizon depth, and low
##       landmark silhouettes (works, church spire, hangar, walls).
##   * WS-F wear decals: braking streaks, corner-exit rubber, oil patches, dirt
##       spill — Godot `Decal`s with generated textures, projected ONLY onto the
##       road/ground layer (`DECAL_LAYER`, never the cars) and gated per quality
##       preset by `settings_menu.gd` (Forward+/Mobile only; Low = off).
##
## Every instanced kind is MultiMesh, split into `CHUNK_M` spatial chunks so the
## renderer can frustum-cull a 13.6 km lap and each chunk carries a per-kind
## visibility range (small props pop out where fog already hides them).
##
## MESH FRAMES (the source of most off-by-one bugs here, stated once):
##   `_basis_along`   -> local X ALONG the road, Z across  (barriers/props)
##   `_basis_span`    -> local X ACROSS the road, Z along  (gantry/arch/paint)
##   `_basis_surface` -> local X along the road, Y the banked surface normal
##
## DETERMINISM: no RNG, no wall clock, every placement is arc/constant/hash
## driven, so two `build()` runs on the same configuration produce bit-identical
## transform sets (pinned by test_le_mans_track.gd).
##
## USABLE WITH NO SCENE: `configure()` then `build()`. Nothing here reads a
## scene or a `RoadNetwork`; `height_provider` is an optional
## `Callable(Vector3) -> float`; without it props sit on `LeMansLayout.PLAIN_Y`.

## Kinds the builder can place, in build order.
const KIND_GANTRY := "gantry"
const KIND_PAINT := "paint"
const KIND_ARCH := "arch"
const KIND_ARMCO := "armco"
const KIND_CATCH_FENCE := "catch_fence"
const KIND_TYRE_WALL := "tyre_wall"
const KIND_BARRIER_PANEL := "barrier_panel"
const KIND_HEDGE := "hedge"
const KIND_TYRE := "tyre"
const KIND_KERB := "kerb"
const KIND_SAUSAGE_KERB := "sausage_kerb"
const KIND_POST := "post"
const KIND_DISTANCE_BOARD := "distance_board"
const KIND_AD_BOARD := "ad_board"
const KIND_CAMERA_TOWER := "camera_tower"
const KIND_SERVICE_TRACK := "service_track"
const KIND_DECAL := "decal"
const KIND_TRAP := "trap"
const KIND_RUNOFF := "runoff"
const KIND_TREELINE := "treeline"
const KIND_FOREST_WALL := "forest_wall"
const KIND_GRANDSTAND := "grandstand"
const KIND_PIT_BUILDING := "pit_building"
const KIND_FAR_TREELINE := "far_treeline"
const KIND_SILHOUETTE_INDUSTRIAL := "silhouette_industrial"
const KIND_SILHOUETTE_CHURCH := "silhouette_church"
const KIND_SILHOUETTE_HANGAR := "silhouette_hangar"
## Brand-free on purpose: the neutral-banner contract (test_le_mans_track.gd)
## bans trademarked tokens in ANY node name the dressing emits, and the node
## name is derived from this kind string.
const KIND_SILHOUETTE_WALLS := "silhouette_walls"

## Sharp-corner threshold (deg) shared by armco/kerbs/fences; the layout's own
## default argument (restated so a default change cannot drift silently).
const SHARP_TURN_DEG := 40.0
## The corner-direction probe half-window (m of arc) for outside/inside calls.
const CORNER_PROBE_M := 30.0

## Render layer (bit 11) the wear decals project onto. le_mans.gd adds it to the
## road surface, verge and ground; the dressing adds it to traps/aprons. Cars
## stay on layer 1 only, so a decal box a car drives through never paints it.
const DECAL_LAYER := 1 << 10

## MultiMesh spatial chunk edge (m).
const CHUNK_M := 400.0
## Per-kind visibility range end (m); kinds not listed are never range-culled.
const VIS_RANGE: Dictionary = {
	"armco": 650.0, "catch_fence": 320.0, "tyre_wall": 420.0,
	"barrier_panel": 420.0, "hedge": 1400.0, "tyre": 380.0, "kerb": 520.0,
	"sausage_kerb": 300.0, "post": 900.0, "distance_board": 600.0,
	"ad_board": 700.0, "camera_tower": 1500.0, "service_track": 600.0,
	"treeline": 2200.0, "forest_wall": 2600.0, "grandstand": 2500.0, "pit_building": 2500.0,
}
## Kinds that never cast shadows (far/flat things the 140 m shadow range would
## never reach anyway, so skip the shadow pass cost).
const NO_SHADOW_KINDS: Array[String] = [
	"far_treeline", "forest_wall", "silhouette_industrial", "silhouette_church",
	"silhouette_hangar", "silhouette_walls", "service_track", "paint", "kerb",
	"trap", "runoff",
]

## The centerline + bank profile the road mesh was built from (set by
## `configure()`; `build()` refuses to run without them).
var road_points: Array[Vector3] = []
var bank_profile: PackedFloat32Array = PackedFloat32Array()
var road_width: float = LeMansLayout.WIDTH_M
var height_provider: Callable = Callable()

var _built := false
## kind -> Array[Transform3D] of every placed instance.
var _transforms: Dictionary = {}
## kind -> PackedColorArray of per-instance colours (kinds that tint only).
var _colors: Dictionary = {}
## kind -> the Mesh each instance of that kind draws.
var _meshes: Dictionary = {}
var _dropped: Array[String] = []
var _perim := -1.0
## Trap / apron polygons this dressing registers in SurfaceRegistry:
## Array of {"poly": PackedVector2Array, "surface": String}.
var _zones: Array[Dictionary] = []
## Spatial grid of a subsampled centerline for "is this spot near ANY part of
## the circuit" queries (the loop folds back on itself).
var _grid: Dictionary = {}
var _bbox := Rect2()
## TRAP_CHAINAGES resolved once per build: Array of {"arc": float, "side": float}.
var _trap_windows: Array[Dictionary] = []

## --- §3.8 tuning table (all constants; no magic numbers below) ---------------

## Portals (span frames: X across the road).
const GANTRY_POST_OFFSET := 2.2
const GANTRY_POST_SIZE := Vector3(0.5, 6.2, 0.5)
const GANTRY_BEAM_Y := 6.45
const GANTRY_BANNER_Y := 5.45
const ARCH_POST_OFFSET := 2.0
const ARCH_POST_SIZE := Vector3(0.7, 5.6, 0.7)
const ARCH_BEAM_Y := 5.85
const ARCH_BANNER_Y := 4.95
## S/F checker paint (span frame: X across, Z along the road).
const CHECKER_CELLS_X := 8
const CHECKER_CELLS_Y := 2
const CHECKER_CELL_PX := 12
const CHECKER_LENGTH := 1.5
const CHECKER_LIFT := 0.02
## Armco (visual only -- RoadDef rails stay NONE, §8.3(f)).
const ARMCO_PITCH_M := 5.0
const ARMCO_OFFSET := 1.6                ## beyond the road edge on a plain straight
const ARMCO_SEGMENT_LENGTH := 5.15       ## overlaps at the 5 m pitch: reads continuous
## W-beam profile (local Z, Y) and posts.
## Humps bulge toward the road (local -Z; the posts sit behind at +Z).
const ARMCO_PROFILE: Array[Vector2] = [
	Vector2(0.0, 0.44), Vector2(-0.05, 0.48), Vector2(-0.065, 0.53),
	Vector2(-0.02, 0.59), Vector2(-0.065, 0.65), Vector2(-0.05, 0.70),
	Vector2(0.0, 0.74),
]
const ARMCO_POST_SIZE := Vector3(0.12, 0.74, 0.1)
const ARMCO_POST_BACK := 0.09            ## post behind the beam (away from road)

## --- Physical barriers (collision) ---------------------------------------------
## The armco/tyre walls are MultiMesh visuals with no collision of their own, so
## `_build_barrier_colliders` lays a continuous chain of oriented boxes along the
## SAME barrier line (`barrier_offset`, samples on the armco's own 5 m pitch,
## ground from the same height provider). Long straight runs merge into one box;
## bends/climbs split so the chain never strays from the line by more than
## BARRIER_STRAIGHT_TOL_M or from the grade by more than BARRIER_VERTICAL_TOL_M.
@export var build_barrier_colliders: bool = true
const BARRIER_MAX_SEGMENT_M := 30.0
const BARRIER_STRAIGHT_TOL_M := 0.10
const BARRIER_VERTICAL_TOL_M := 0.35
## Front face of the wall, metres toward the road from the armco line (the beam
## bulges 0.065 m toward the road).
const BARRIER_FRONT_INSET := 0.12
## Depth of the wall behind the front face (m). Deliberately thick: at 60 Hz a car
## moving 60-100 m/s covers 1-1.7 m per step, and when it lands deeper than HALF a
## thin wall's depth the solver's cheapest way out is the BACK face (the car is
## "pushed through"). Measured: a 1 m wall let a 76 m/s perpendicular crash through;
## everything behind the armco line is unreachable ground, so depth costs nothing.
const BARRIER_THICKNESS := 4.0
## Top of the wall above the local ground / above the road edge (m). Not just
## "taller than the car": a discrete-step solver resolves a penetration along its
## SHORTEST axis, and a car arriving at 90 m/s (1.5 m per 60 Hz step) is up to
## 1.5 m INTO the wall face on first contact. If the way over the top is shorter
## than that (wall top - car underside), the car is shoved UP and launched across
## the wall (measured: 90 m/s side-on, wall 1.2 m over the road, vy +8.7 m/s).
## 2.2 m over the road keeps the vertical exit (>= 1.8 m for a car hovering
## 0.35 m up) longer than the worst horizontal depth, so the face wins.
const BARRIER_RISE := 2.3
const BARRIER_ROAD_RISE := 2.2
## The box reaches this far BELOW the local ground so no gap opens under it.
const BARRIER_DROP_BELOW := 1.0
## Each box is lengthened this much at both ends so a bend leaves no seam.
const BARRIER_END_OVERLAP := 0.6
const BARRIER_FRICTION := 0.2
const BARRIER_BOXES_PER_BODY := 48
## Tyre-wall zones: the wall face is the tyres' (and panels') front, further
## toward the road than the armco, so an extra run fills in front of the base.
const TYRE_WALL_COLLIDER_FRONT := TYRE_WALL_FRONT + TYRE_WALL_RADIUS + 0.05
## Hedgerows along the Mulsanne (§3.8 chainage window, literal; along frame).
const HEDGE_CHAINAGE_FROM := 2000.0
const HEDGE_CHAINAGE_TO := 7300.0
const HEDGE_PITCH_M := 10.0
const HEDGE_OFFSET := 5.0
const HEDGE_SIZE := Vector3(9.0, 2.1, 1.9)
const HEDGE_H_WOBBLE := 0.14
## Tyre stacks: the five §3.8 braking-zone chainages, verbatim.
const TYRE_ZONE_CHAINAGES: Array[float] = [1450.0, 7300.0, 9600.0, 9950.0, 13020.0]
const TYRE_STACKS_PER_ZONE := 4
const TYRE_PER_STACK := 3
const TYRE_STACK_PITCH := 1.4
const TYRE_OFFSET := 2.2
const TYRE_RADIUS := 0.34
## Braking-marker stacks stand this far in front of the barrier line (clear of
## the tyre wall and its panels).
const TYRE_MARKER_FRONT := 1.5
const TYRE_HEIGHT := 0.22
## Apex kerbs at the sharp corners (surface frame: X along road, Z across).
const KERB_WINDOW_M := 15.0
const KERB_PITCH_M := 5.0
const KERB_INSET := 0.55
const KERB_SIZE := Vector3(4.6, 0.06, 0.5)
const KERB_SURFACE_LIFT := 0.03
## Ford-chicane sausage kerbs: the chicane is a left-right flick around
## LANDMARK_FORD (13,094), too short for the 40 deg sharp-corner detector, so
## its two apexes are pinned by chainage; the inside of each is probed locally.
const SAUSAGE_CHAINAGES: Array[float] = [13066.0, 13122.0]
const SAUSAGE_PROBE_M := 12.0
const SAUSAGE_WINDOW_M := 9.0
const SAUSAGE_PITCH_M := 3.2
const SAUSAGE_LENGTH := 3.0
const SAUSAGE_RADIUS := 0.13
const SAUSAGE_OFFSET := 0.45
## Marshal posts (along frame).
const POST_CADENCE_M := 1500.0
const POST_OFFSET := 10.0
const POST_LEG_SIZE := Vector3(0.12, 2.4, 0.12)
const POST_DECK_Y := 2.45
const POST_DECK_SIZE := Vector3(1.2, 0.1, 1.6)
const POST_ROOF_Y := 3.35
const POST_ROOF_SIZE := Vector3(1.5, 0.08, 1.9)

## WS-C: catch fencing / tyre walls / barrier panels.
const CATCH_FENCE_WINDOW_M := 70.0
const CATCH_FENCE_SF_WINDOW_M := 260.0
const CATCH_FENCE_PITCH_M := 4.0
const CATCH_FENCE_BEHIND := 1.0          ## behind the armco line
const CATCH_FENCE_PANEL := Vector2(4.0, 3.2)
const CATCH_FENCE_MESH_M := 0.12         ## chain-link diamond pitch (m)
const TYRE_WALL_ZONE_CHAINAGES: Array[float] = [
	1450.0, 7300.0, 9600.0, 9950.0, 13020.0, 1885.0, 6236.0, 8689.0,
]
const TYRE_WALL_STACKS := 24
const TYRE_WALL_PER_STACK := 4
const TYRE_WALL_PITCH := 0.74
const TYRE_WALL_FRONT := 0.45            ## in front of the armco line
const TYRE_WALL_RADIUS := 0.36
const TYRE_WALL_HEIGHT := 0.24
const BARRIER_PANEL_WIDTH := 2.2
const BARRIER_PANEL_HEIGHT := 1.0
const BARRIER_PANEL_PITCH := 2.25
const BARRIER_PANEL_FRONT := 0.9         ## covering the tyre wall face
const BARRIER_PANEL_Y := 0.52

## WS-D: ad boards / countdown boards / towers / service tracks.
const AD_BOARD_CADENCE_M := 160.0
const AD_BOARD_SF_WINDOW_M := 300.0
const AD_BOARD_SF_PITCH_M := 5.0
const AD_BOARD_BEHIND := 1.4             ## behind the armco line
const AD_BOARD_SIZE := Vector3(4.8, 1.0, 0.1)
const AD_BOARD_Y := 1.25
const AD_BOARD_COLORS: Array[Color] = [
	Color(0.78, 0.14, 0.11), Color(0.12, 0.30, 0.66), Color(0.93, 0.78, 0.12),
	Color(0.92, 0.92, 0.90), Color(0.10, 0.48, 0.30),
]
const COUNTDOWN_METRES: Array[float] = [300.0, 200.0, 100.0]
const COUNTDOWN_OFFSET := 2.0            ## beyond the armco line
const CAMERA_TOWER_CHAINAGES: Array[float] = [869.0, 4630.0, 7508.0, 13094.0]
const CAMERA_TOWER_OFFSET := 16.0
const CAMERA_TOWER_LEG := Vector3(0.24, 9.0, 0.24)
const CAMERA_TOWER_DECK := Vector3(4.0, 0.18, 4.0)
const CAMERA_TOWER_Y := 7.2
## S/F landmarks: grandstand modules (outside) and pit building (inside).
const GRANDSTAND_MODULE_M := 48.0
const GRANDSTAND_HALF_M := 192.0
const GRANDSTAND_STEPS := 9
const PIT_MODULE_M := 40.0
const PIT_HALF_M := 200.0
const SERVICE_TRACK_WIDTH := 4.0
const SERVICE_TRACK_LENGTH := 13.0
const SERVICE_TRACK_PITCH := 12.0
const SERVICE_TRACK_BEHIND := 4.0
const SERVICE_TRACK_LIFT := 0.01

## WS-A: sand/gravel traps + paved run-off aprons (outside of each corner).
const TRAP_CHAINAGES: Array[float] = [
	LeMansLayout.LANDMARK_TERTRE_ROUGE,
	LeMansLayout.LANDMARK_MULSANNE_CORNER,
	LeMansLayout.LANDMARK_INDY,
	LeMansLayout.LANDMARK_ARNAGE,
	LeMansLayout.LANDMARK_FORD,
]
const TRAP_HALF_WINDOW_M := 55.0         ## +- arc around the corner chainage
const TRAP_STEP_M := 3.0
const APRON_WIDTH_M := 2.6               ## paved strip between road and trap
const TRAP_WIDTH_M := 8.0                ## sand width at the window centre
const TRAP_FRINGE_M := 1.4               ## sand-to-grass blend row
const TRAP_RAGGED_M := 0.6               ## deterministic +- torn-edge jitter
const TRAP_LIFT := 0.08
const RUNOFF_LIFT := 0.06
## How far the barrier line moves out behind a trap at the window centre.
const TRAP_BARRIER_EXTRA := APRON_WIDTH_M + TRAP_WIDTH_M + TRAP_FRINGE_M + 0.6

## WS-E: tree lines and silhouettes.
const TREELINE_PITCH_M := 8.0
const TREELINE_MIN_OFFSET := 24.0
const TREELINE_MAX_OFFSET := 44.0
## Continuous forest mass behind the clumps (a jagged-top vertical sheet with a
## world-space leaf-noise albedo): what turns a row of trees into a wood edge.
const FOREST_WALL_STEP_M := 9.0
const FOREST_WALL_OFFSET := 50.0
const FOREST_WALL_OFFSET_VAR := 9.0
const FOREST_WALL_HEIGHT := 12.0
const FOREST_WALL_HEIGHT_VAR := 6.0
const FOREST_WALL_CLEARANCE := 34.0
const TREELINE_CLEARANCE := 24.0         ## from ANY part of the circuit
const TREELINE_GAP_BLOCK_M := 150.0      ## field-opening granularity
const TREELINE_GAP_FRACTION := 0.2
const TREELINE_SF_CLEAR_M := 220.0
const FAR_TREE_BAND_MIN := 300.0
const FAR_TREE_BAND_MAX := 1100.0
const FAR_TREE_PITCH_M := 36.0
const FAR_TREE_ROWS := 2
const FAR_TREE_CLEARANCE := 150.0
## Ground-plane safety margin: nothing is placed further than this outside the
## layout bbox (le_mans.gd's 6 x 7 km plane leaves ~790 m in Z).
const PLANE_MARGIN := 650.0
const SILHOUETTE_CHAINAGES: Array[float] = [869.0, 4630.0, 7508.0, 13094.0]
const SILHOUETTE_OFFSETS: Array[float] = [700.0, 600.0, 500.0, 420.0, 340.0]
const SILHOUETTE_CLEARANCE := 160.0

## Real elevation: how far footprint-wide props are sunk below the ground at
## their origin so no edge floats on a slope (trees, buildings; m).
const TREE_BURY := 0.4
const BUILDING_BURY := 0.5

## WS-F wear decals.
const DECAL_FADE_BEGIN := 140.0
const DECAL_FADE_LENGTH := 50.0
const DECAL_LIFT := 0.04


## Wire-up hook called by `le_mans.gd` BEFORE `build()`.
func configure(points: Array[Vector3], banks: PackedFloat32Array, width: float,
		p_height_provider: Callable = Callable()) -> void:
	road_points = points
	bank_profile = banks
	road_width = width
	height_provider = p_height_provider
	_perim = -1.0
	_built = false


func is_built() -> bool:
	return _built


func dropped_kinds() -> Array:
	return _dropped


func count_of(kind: String) -> int:
	return (_transforms.get(kind, []) as Array).size()


func prop_mesh(kind: String) -> Mesh:
	return _meshes.get(kind) as Mesh


func transforms_of(kind: String) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for t: Transform3D in (_transforms.get(kind, []) as Array):
		out.append(t)
	return out


func origins_of(kind: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	for t: Transform3D in (_transforms.get(kind, []) as Array):
		out.append(t.origin)
	return out


## The trap/apron polygons (world XZ) and their SurfaceRegistry surface keys.
func surface_zones() -> Array[Dictionary]:
	return _zones


## Signed lateral (m, + = right of travel) of the barrier line at arc `s` on
## `side` (+1 right / -1 left): the road edge + ARMCO_OFFSET, pushed out behind
## a trap where one exists. Public so tests can check armco coverage.
func barrier_offset(s: float, side: float) -> float:
	return side * (road_width * 0.5 + ARMCO_OFFSET + TRAP_BARRIER_EXTRA * _trap_taper(s, side))


func build() -> void:
	_clear_children()
	_barrier_root = null
	_barrier_box_total = 0
	_transforms = {}
	_colors = {}
	_meshes = {}
	_dropped = []
	_zones = []
	_trap_windows = []
	_built = false
	if road_points.size() < 3:
		return
	_build_grid()
	_trap_windows = []
	for ch in TRAP_CHAINAGES:
		var arc := LeMansLayout.arc_at_chainage(ch)
		_trap_windows.append({"arc": arc, "side": float(_outside_side(arc))})

	_build_gantry()
	_build_checker_paint()
	_build_arch()
	_build_armco()
	_build_catch_fences()
	_build_tyre_walls()
	_build_barrier_panels()
	_build_hedges()
	_build_tyres()
	_build_kerbs()
	_build_sausage_kerbs()
	_build_marshal_posts()
	_build_distance_boards()
	_build_ad_boards()
	_build_camera_towers()
	_build_start_finish_buildings()
	_build_service_tracks()
	_build_traps_and_runoff()
	_build_treeline()
	_build_far_treeline()
	_build_silhouettes()
	_build_wear_decals()
	if build_barrier_colliders:
		_build_barrier_colliders()
	_built = true
	if is_inside_tree():
		_register_zones()


func _enter_tree() -> void:
	if _built:
		_register_zones()


## Zones are global (static) state in SurfaceRegistry: they exist only while a
## built Le Mans dressing is in the tree, so a freed probe or a scene change can
## never leave sand grip lying over another map's coordinates.
func _exit_tree() -> void:
	SurfaceRegistry.clear_zones()


func _register_zones() -> void:
	SurfaceRegistry.clear_zones()
	for z: Dictionary in _zones:
		SurfaceRegistry.add_zone(Array(z["poly"] as PackedVector2Array), String(z["surface"]))

## --- item builders -----------------------------------------------------------

## S/F gantry: one fused portal straddling the carriageway at the line.
func _build_gantry() -> void:
	var st := _station(LeMansLayout.start_line_arc())
	var half := road_width * 0.5 + GANTRY_POST_OFFSET
	var steel := _mat(Color(0.62, 0.65, 0.70), 0.55, null, 0.4)
	var banner := _mat(Color(0.86, 0.87, 0.88), 0.7)
	var entries: Array = [
		{"size": GANTRY_POST_SIZE, "offset": Vector3(-half, GANTRY_POST_SIZE.y * 0.5, 0.0)},
		{"size": GANTRY_POST_SIZE, "offset": Vector3(half, GANTRY_POST_SIZE.y * 0.5, 0.0)},
		{"size": Vector3(half * 2.0 + 0.5, 0.7, 0.7), "offset": Vector3(0.0, GANTRY_BEAM_Y, 0.0)},
		# Neutral banner slab: deliberately UN-LETTERED (§7 gotcha 8).
		{"size": Vector3(half * 1.6, 0.9, 0.16), "offset": Vector3(0.0, GANTRY_BANNER_Y, 0.0), "mat": banner},
	]
	var mesh := _fused_mesh(entries, steel)
	_emit_single(KIND_GANTRY, mesh, _xform_ground(st, _basis_span(st), 0.0))


## The 8x2 start checker: a thin slab ON the carriageway at the line.
func _build_checker_paint() -> void:
	var st := _station(LeMansLayout.start_line_arc())
	var mesh := _slab_mesh(Vector3(road_width * 0.96, CHECKER_LIFT * 0.5, CHECKER_LENGTH),
		_mat(Color.WHITE, 0.95, _checker_texture()))
	var t := _xform_on_road(st, _basis_span_pitched(st), Vector3.ZERO)
	var c: Vector3 = st["center"]
	t.origin.y = c.y + CHECKER_LIFT
	_emit_single(KIND_PAINT, mesh, t)


## The Dunlop-bridge-shaped arch at chainage 869 with a NEUTRAL banner.
func _build_arch() -> void:
	var st := _station(LeMansLayout.arc_at_chainage(LeMansLayout.LANDMARK_DUNLOP_BRIDGE))
	var half := road_width * 0.5 + ARCH_POST_OFFSET
	var concrete := _mat(Color(0.70, 0.70, 0.68), 0.85)
	var banner := _mat(Color(0.24, 0.36, 0.52), 0.65)
	var entries: Array = [
		{"size": ARCH_POST_SIZE, "offset": Vector3(-half, ARCH_POST_SIZE.y * 0.5, 0.0)},
		{"size": ARCH_POST_SIZE, "offset": Vector3(half, ARCH_POST_SIZE.y * 0.5, 0.0)},
		{"size": Vector3(half * 2.0 + 0.4, 0.6, 0.6), "offset": Vector3(0.0, ARCH_BEAM_Y, 0.0)},
		# Neutral banner slab, un-lettered by design (no Dunlop trademark).
		{"size": Vector3(half * 1.5, 0.8, 0.14), "offset": Vector3(0.0, ARCH_BANNER_Y, 0.0), "mat": banner},
	]
	var mesh := _fused_mesh(entries, concrete)
	_emit_single(KIND_ARCH, mesh, _xform_ground(st, _basis_span(st), 0.0))


## WS-C full-lap armco: both sides, every ARMCO_PITCH_M, a galvanised W-beam on
## posts, following `barrier_offset` (out behind the traps). CONTINUOUS (no
## marshal-post gap: the wall collider behind it is continuous too, so a visible
## gap would be an invisible wall). The physical wall is `_build_barrier_colliders`.
func _build_armco() -> void:
	var beam := _mat(Color(0.66, 0.68, 0.70), 0.42, null, 0.55)
	beam.cull_mode = BaseMaterial3D.CULL_DISABLED
	var post := _mat(Color(0.40, 0.41, 0.43), 0.6, null, 0.3)
	var acc := _acc_new()
	_acc_add_profile(acc, ARMCO_PROFILE, ARMCO_SEGMENT_LENGTH)
	var posts := _acc_new()
	for px: float in [-ARMCO_SEGMENT_LENGTH * 0.25, ARMCO_SEGMENT_LENGTH * 0.25]:
		_acc_add_box(posts, ARMCO_POST_SIZE,
			Vector3(px, ARMCO_POST_SIZE.y * 0.5, ARMCO_POST_BACK))
	_meshes[KIND_ARMCO] = _mesh_from([{"acc": acc, "mat": beam}, {"acc": posts, "mat": post}])
	var perimeter := _perimeter()
	var count := int(perimeter / ARMCO_PITCH_M)
	for side: float in [1.0, -1.0]:
		for k in count:
			var s := float(k) * ARMCO_PITCH_M
			var st := _station(s)
			var basis := _basis_along_pitched(st)
			# Local +Z of `_basis_along` is the road's RIGHT; turn the beam so its
			# posts (local +Z) are always on the side AWAY from the road.
			if side < 0.0:
				basis = basis * Basis(Vector3.UP, PI)
			_record(KIND_ARMCO, _xform_ground(st, basis, barrier_offset(s, side)))
	_flush(KIND_ARMCO)


## --- physical barriers ----------------------------------------------------------

var _barrier_box_total := 0
var _barrier_root: Node3D = null


## Number of collision boxes the last build emitted (0 when disabled).
func barrier_box_count() -> int:
	return _barrier_box_total


## The `BarrierColliders` node (null when not built).
func barrier_root() -> Node3D:
	return _barrier_root


## Builds the solid wall behind/under every armco and tyre wall: a continuous box
## chain on BOTH sides of the whole lap. Same barrier line as the visuals
## (`barrier_offset`), same samples as the armco (ARMCO_PITCH_M), same ground
## (`_ground_y`), so collider and mesh cannot diverge. Layer/mask 1 is what the
## cars and the ground already use.
func _build_barrier_colliders() -> void:
	_barrier_box_total = 0
	_barrier_root = null
	if road_points.size() < 3:
		return
	var root := Node3D.new()
	root.name = "BarrierColliders"
	add_child(root)
	_barrier_root = root
	var perimeter := _perimeter()
	var boxes: Array[Dictionary] = []
	# Base wall: every metre of the lap, both sides, behind the armco face.
	for side: float in [1.0, -1.0]:
		_barrier_run(side, 0.0, perimeter, ARMCO_PITCH_M, BARRIER_FRONT_INSET,
			BARRIER_THICKNESS - BARRIER_FRONT_INSET, boxes)
	# Tyre-wall zones: extra boxes from the tyre face back to the base wall.
	var tyre_half := float(TYRE_WALL_STACKS - 1) * 0.5 * TYRE_WALL_PITCH + TYRE_WALL_RADIUS
	for ch in TYRE_WALL_ZONE_CHAINAGES:
		var arc := LeMansLayout.arc_at_chainage(ch)
		var side2 := float(_outside_side(arc))
		_barrier_run(side2, arc - tyre_half, arc + tyre_half, 2.0, TYRE_WALL_COLLIDER_FRONT,
			BARRIER_THICKNESS, boxes)
	var material := PhysicsMaterial.new()
	material.friction = BARRIER_FRICTION
	var body: StaticBody3D = null
	for i in boxes.size():
		if i % BARRIER_BOXES_PER_BODY == 0:
			body = StaticBody3D.new()
			body.name = "BarrierCollision_%d" % (i / BARRIER_BOXES_PER_BODY)
			body.collision_layer = 1
			body.collision_mask = 1
			body.physics_material_override = material
			root.add_child(body)
		var box: Dictionary = boxes[i]
		var shape := BoxShape3D.new()
		shape.size = box["size"]
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(box["basis"], box["origin"])
		body.add_child(cs)
	_barrier_box_total = boxes.size()


## One polyline of the wall on `side` from arc `s0` to `s1`, sampled every `pitch`
## m, merged greedily into long boxes and appended to `out`. The wall spans from
## `front` m toward the road to `back` m away from it, measured from the armco line.
func _barrier_run(side: float, s0: float, s1: float, pitch: float, front: float,
		back: float, out: Array[Dictionary]) -> void:
	var count := maxi(int(ceil((s1 - s0) / pitch)), 1)
	var shift := side * (back - front) * 0.5
	var pts: Array[Dictionary] = []
	for k in count + 1:
		var s := minf(s0 + float(k) * pitch, s1)
		var st := _station(s)
		var lateral := barrier_offset(s, side) + shift
		var center: Vector3 = st["center"]
		var right: Vector3 = st["right"]
		var cross: Vector3 = st["cross"]
		var ground := _ground_y(st, lateral)
		var edge_y := center.y + cross.y * side * road_width * 0.5
		pts.append({
			"x": center.x + right.x * lateral,
			"z": center.z + right.z * lateral,
			"g": ground,
			"top": maxf(ground + BARRIER_RISE, edge_y + BARRIER_ROAD_RISE),
		})
	var thickness := front + back
	var a := 0
	while a < pts.size() - 1:
		var b := a + 1
		while b + 1 < pts.size() and _barrier_can_extend(pts, a, b + 1):
			b += 1
		var box := _barrier_box(pts, a, b, thickness)
		if not box.is_empty():
			out.append(box)
		a = b


## True when one box from sample `a` to sample `c` still hugs the polyline: every
## in-between sample within BARRIER_STRAIGHT_TOL_M of the chord in plan, and the
## ground / required top within BARRIER_VERTICAL_TOL_M of the chord's height.
func _barrier_can_extend(pts: Array[Dictionary], a: int, c: int) -> bool:
	var pa := Vector2(pts[a]["x"], pts[a]["z"])
	var pc := Vector2(pts[c]["x"], pts[c]["z"])
	var chord := pc - pa
	var length := chord.length()
	if length > BARRIER_MAX_SEGMENT_M or length < 0.001:
		return false
	var dir := chord / length
	var ya: float = pts[a]["g"]
	var yc: float = pts[c]["g"]
	var lo_g := 0.0
	var hi_g := 0.0
	var lo_t := 0.0
	var hi_t := 0.0
	for k in range(a, c + 1):
		var pk := Vector2(pts[k]["x"], pts[k]["z"])
		var rel := pk - pa
		if absf(rel.x * dir.y - rel.y * dir.x) > BARRIER_STRAIGHT_TOL_M:
			return false
		var t := clampf(rel.dot(dir) / length, 0.0, 1.0)
		var cy := lerpf(ya, yc, t)
		var dg: float = float(pts[k]["g"]) - cy
		var dt: float = float(pts[k]["top"]) - cy
		if k == a:
			lo_g = dg
			hi_g = dg
			lo_t = dt
			hi_t = dt
		else:
			lo_g = minf(lo_g, dg)
			hi_g = maxf(hi_g, dg)
			lo_t = minf(lo_t, dt)
			hi_t = maxf(hi_t, dt)
	return hi_g - lo_g <= BARRIER_VERTICAL_TOL_M and hi_t - lo_t <= BARRIER_VERTICAL_TOL_M


## Box for samples a..b: oriented along the 3D chord (so it pitches with a climb),
## vertically spanning from DROP_BELOW under the lowest ground to the highest
## required top, lengthened at both ends so neighbours overlap.
func _barrier_box(pts: Array[Dictionary], a: int, b: int, thickness: float) -> Dictionary:
	var pa := Vector3(pts[a]["x"], pts[a]["g"], pts[a]["z"])
	var pb := Vector3(pts[b]["x"], pts[b]["g"], pts[b]["z"])
	var dir := pb - pa
	var length := dir.length()
	if length < 0.001:
		return {}
	var zaxis := dir / length
	var xaxis := Vector3.UP.cross(zaxis).normalized()
	var yaxis := zaxis.cross(xaxis)
	var lo := INF
	var hi := -INF
	for k in range(a, b + 1):
		var t := float(k - a) / float(b - a)
		var cy := lerpf(pa.y, pb.y, t)
		lo = minf(lo, float(pts[k]["g"]) - cy - BARRIER_DROP_BELOW)
		hi = maxf(hi, float(pts[k]["top"]) - cy)
	return {
		"basis": Basis(xaxis, yaxis, zaxis),
		"origin": (pa + pb) * 0.5 + Vector3.UP * ((lo + hi) * 0.5),
		"size": Vector3(thickness, hi - lo, length + 2.0 * BARRIER_END_OVERLAP),
	}


## WS-C catch fencing: chain-link panels (alpha scissor, texture-mipped so it
## fades to a faint haze with distance) on posts, behind the armco at every
## corner complex (outside) and along the S/F straight (both sides).
func _build_catch_fences() -> void:
	var link := _mat(Color(0.62, 0.64, 0.66), 0.5, _chainlink_texture(), 0.5)
	link.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	link.alpha_scissor_threshold = 0.35
	link.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	link.cull_mode = BaseMaterial3D.CULL_DISABLED
	link.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var steel := _mat(Color(0.46, 0.48, 0.50), 0.55, null, 0.5)
	var panel := _acc_new()
	var w := CATCH_FENCE_PANEL.x
	var h := CATCH_FENCE_PANEL.y
	_acc_add_quad_xy(panel, w, h, Vector2(w / CATCH_FENCE_MESH_M * 0.5, h / CATCH_FENCE_MESH_M * 0.5))
	var frame := _acc_new()
	_acc_add_box(frame, Vector3(0.08, h + 0.2, 0.08), Vector3(-w * 0.5, (h + 0.2) * 0.5, 0.0))
	_acc_add_box(frame, Vector3(w, 0.05, 0.05), Vector3(0.0, h, 0.0))
	_meshes[KIND_CATCH_FENCE] = _mesh_from([{"acc": panel, "mat": link}, {"acc": frame, "mat": steel}])
	var windows: Array[Dictionary] = []
	for ch in LeMansLayout.sharp_corner_chainages(SHARP_TURN_DEG):
		var arc := LeMansLayout.arc_at_chainage(ch)
		windows.append({"arc": arc, "half": CATCH_FENCE_WINDOW_M, "side": float(_outside_side(arc))})
	var sf := LeMansLayout.start_line_arc()
	windows.append({"arc": sf, "half": CATCH_FENCE_SF_WINDOW_M, "side": 1.0})
	windows.append({"arc": sf, "half": CATCH_FENCE_SF_WINDOW_M, "side": -1.0})
	for win: Dictionary in windows:
		var arc0: float = win["arc"]
		var half_w: float = win["half"]
		var side: float = win["side"]
		var count := int(half_w * 2.0 / CATCH_FENCE_PITCH_M) + 1
		for k in count:
			var s := arc0 - half_w + float(k) * CATCH_FENCE_PITCH_M
			var st := _station(s)
			var lateral := barrier_offset(s, side) + side * CATCH_FENCE_BEHIND
			_record(KIND_CATCH_FENCE, _xform_ground(st, _basis_along_pitched(st), lateral))
	_flush(KIND_CATCH_FENCE)


## WS-C tyre walls: a continuous four-high wall in front of the armco at every
## braking/corner zone, mostly black with painted white/red marker tyres.
func _build_tyre_walls() -> void:
	var tyre_mat := _mat(Color.WHITE, 0.92)
	tyre_mat.vertex_color_use_as_albedo = true
	_meshes[KIND_TYRE_WALL] = _cylinder_mesh(TYRE_WALL_RADIUS, TYRE_WALL_HEIGHT, tyre_mat)
	for ch in TYRE_WALL_ZONE_CHAINAGES:
		var arc := LeMansLayout.arc_at_chainage(ch)
		var side := float(_outside_side(arc))
		for s_i in TYRE_WALL_STACKS:
			var s := arc + (float(s_i) - float(TYRE_WALL_STACKS - 1) * 0.5) * TYRE_WALL_PITCH
			var st := _station(s)
			var lateral := barrier_offset(s, side) - side * TYRE_WALL_FRONT
			var ground := _ground_y(st, lateral)
			var painted := s_i % 6 == 0
			for level in TYRE_WALL_PER_STACK:
				var t := _xform_ground(st, _basis_along(st), lateral)
				t.origin.y = ground + TYRE_WALL_HEIGHT * 0.5 + float(level) * TYRE_WALL_HEIGHT
				var c := Color(0.05, 0.05, 0.055)
				if painted:
					c = Color(0.85, 0.85, 0.85) if level % 2 == 0 else Color(0.70, 0.10, 0.08)
				_record(KIND_TYRE_WALL, t, c)
	_flush(KIND_TYRE_WALL)


## WS-C blue/white barrier panels strapped over the tyre-wall face.
func _build_barrier_panels() -> void:
	var panel_mat := _mat(Color.WHITE, 0.55, _panel_texture())
	panel_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var acc := _acc_new()
	_acc_add_quad_xy(acc, BARRIER_PANEL_WIDTH, BARRIER_PANEL_HEIGHT, Vector2.ONE,
		Vector3(0.0, BARRIER_PANEL_Y - BARRIER_PANEL_HEIGHT * 0.5, 0.0))
	_meshes[KIND_BARRIER_PANEL] = _mesh_from([{"acc": acc, "mat": panel_mat}])
	var span := float(TYRE_WALL_STACKS - 1) * TYRE_WALL_PITCH
	var count := int(span / BARRIER_PANEL_PITCH) + 1
	for ch in TYRE_WALL_ZONE_CHAINAGES:
		var arc := LeMansLayout.arc_at_chainage(ch)
		var side := float(_outside_side(arc))
		for k in count:
			var s := arc - span * 0.5 + (float(k) + 0.5) * BARRIER_PANEL_PITCH
			var st := _station(s)
			var lateral := barrier_offset(s, side) - side * BARRIER_PANEL_FRONT
			_record(KIND_BARRIER_PANEL, _xform_ground(st, _basis_along_pitched(st), lateral))
	_flush(KIND_BARRIER_PANEL)


## Hedgerow blocks along the Mulsanne window, both sides: lumpy (three squashed
## lobes) instead of a box, with a deterministic height wobble and per-block
## green variation (an integer sine of the block index -- no RNG anywhere).
func _build_hedges() -> void:
	var leaf := _leaf_mat()
	var acc := _acc_new()
	var lx := HEDGE_SIZE.x / 3.0
	for j in 3:
		_acc_add_sphere(acc, Vector3(lx * 1.35, HEDGE_SIZE.y * (1.05 if j == 1 else 0.92), HEDGE_SIZE.z),
			Vector3((float(j) - 1.0) * lx, HEDGE_SIZE.y * 0.42, 0.0), 8, 5)
	_meshes[KIND_HEDGE] = _mesh_from([{"acc": acc, "mat": leaf}])
	var a0 := LeMansLayout.arc_at_chainage(HEDGE_CHAINAGE_FROM)
	var a1 := LeMansLayout.arc_at_chainage(HEDGE_CHAINAGE_TO)
	var blocks := int((a1 - a0) / HEDGE_PITCH_M)
	for k in blocks + 1:
		var st := _station(a0 + float(k) * HEDGE_PITCH_M)
		for side: float in [-1.0, 1.0]:
			var t := _xform_ground(st, _basis_along_pitched(st), side * (road_width * 0.5 + HEDGE_OFFSET))
			var wobble := 1.0 + HEDGE_H_WOBBLE * sin(float(k) * 1.7)
			t.basis = t.basis * Basis.from_scale(Vector3(1.0, wobble, 1.0))
			_record(KIND_HEDGE, t, _leaf_color(k * 2 + int(side > 0.0), 0.85))
	_flush(KIND_HEDGE)


## Tyre-stack braking markers at the five §3.8 zone chainages, now standing in
## front of the barrier line (so they never sit in a trap or an apron).
func _build_tyres() -> void:
	_meshes[KIND_TYRE] = _cylinder_mesh(TYRE_RADIUS, TYRE_HEIGHT, _mat(Color(0.08, 0.08, 0.09), 0.95))
	for ch in TYRE_ZONE_CHAINAGES:
		var arc := LeMansLayout.arc_at_chainage(ch)
		var side := float(_outside_side(arc))
		for s_i in TYRE_STACKS_PER_ZONE:
			var s := arc + (float(s_i) - float(TYRE_STACKS_PER_ZONE - 1) * 0.5) * TYRE_STACK_PITCH
			var st := _station(s)
			var lateral := maxf(absf(barrier_offset(s, side)) - TYRE_MARKER_FRONT,
				road_width * 0.5 + TYRE_OFFSET) * side
			var ground := _ground_y(st, lateral)
			for level in TYRE_PER_STACK:
				var t := _xform_ground(st, _basis_along(st), lateral)
				t.origin.y = ground + TYRE_HEIGHT * 0.5 + float(level) * TYRE_HEIGHT
				_record(KIND_TYRE, t)
	_flush(KIND_TYRE)


## Red/white apex kerb slabs on the INNER edge of every sharp corner.
func _build_kerbs() -> void:
	_meshes[KIND_KERB] = _slab_mesh(KERB_SIZE, _mat(Color.WHITE, 0.85, _stripe_texture()))
	for ch in LeMansLayout.sharp_corner_chainages(SHARP_TURN_DEG):
		var arc := LeMansLayout.arc_at_chainage(ch)
		var side := -float(_outside_side(arc))
		var count := int(KERB_WINDOW_M * 2.0 / KERB_PITCH_M) + 1
		for k in count:
			var st := _station(arc - KERB_WINDOW_M + float(k) * KERB_PITCH_M)
			var cross: Vector3 = st["cross"]
			var normal: Vector3 = st["normal"]
			_record(KIND_KERB, _xform_on_road(st, _basis_surface(st),
				cross * (side * (road_width * 0.5 - KERB_INSET)) + normal * KERB_SURFACE_LIFT))
	_flush(KIND_KERB)


## WS-A sausage kerbs at the Ford chicane: low yellow cylinders lying along the
## road just off the INSIDE edge of each chicane apex (they punish cut lines).
func _build_sausage_kerbs() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = SAUSAGE_RADIUS
	cyl.bottom_radius = SAUSAGE_RADIUS
	cyl.height = SAUSAGE_LENGTH
	cyl.radial_segments = 10
	var acc := _acc_new()
	# Cylinder axis is local Y; lay it along local X (the along-road axis).
	_acc_add_arrays(acc, cyl.surface_get_arrays(0),
		Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3(0.0, SAUSAGE_RADIUS * 0.4, 0.0)))
	_meshes[KIND_SAUSAGE_KERB] = _mesh_from([{"acc": acc, "mat": _mat(Color(0.92, 0.76, 0.10), 0.6)}])
	for ch in SAUSAGE_CHAINAGES:
		var arc := LeMansLayout.arc_at_chainage(ch)
		var t1: Vector3 = _station(arc - SAUSAGE_PROBE_M)["forward"]
		var t2: Vector3 = _station(arc + SAUSAGE_PROBE_M)["forward"]
		var side := -1.0 if t1.cross(t2).y > 0.0 else 1.0
		var count := int(SAUSAGE_WINDOW_M * 2.0 / SAUSAGE_PITCH_M) + 1
		for k in count:
			var st := _station(arc - SAUSAGE_WINDOW_M + float(k) * SAUSAGE_PITCH_M)
			_record(KIND_SAUSAGE_KERB, _xform_ground(st, _basis_along_pitched(st),
				side * (road_width * 0.5 + SAUSAGE_OFFSET)))
	_flush(KIND_SAUSAGE_KERB)


## Marshal-post towers on the 1,500 m cadence, alternating sides.
func _build_marshal_posts() -> void:
	var white := _mat(Color(0.82, 0.83, 0.84), 0.75)
	var orange := _mat(Color(0.88, 0.42, 0.10), 0.7)
	_meshes[KIND_POST] = _fused_mesh([
		{"size": POST_LEG_SIZE, "offset": Vector3(0.0, POST_LEG_SIZE.y * 0.5, -0.55)},
		{"size": POST_LEG_SIZE, "offset": Vector3(0.0, POST_LEG_SIZE.y * 0.5, 0.55)},
		{"size": POST_DECK_SIZE, "offset": Vector3(0.0, POST_DECK_Y, 0.0)},
		{"size": Vector3(1.2, 0.8, 0.05), "offset": Vector3(0.0, POST_DECK_Y + 0.45, 0.78), "mat": orange},
		{"size": POST_ROOF_SIZE, "offset": Vector3(0.0, POST_ROOF_Y, 0.0)},
	], white)
	var posts := int(_perimeter() / POST_CADENCE_M)
	for k in posts:
		var st := _station(_post_arc(k))
		_record(KIND_POST, _xform_ground(st, _basis_along(st),
			_post_side(k) * (road_width * 0.5 + POST_OFFSET)))
	_flush(KIND_POST)


func _post_arc(k: int) -> float:
	return float(k) * POST_CADENCE_M + POST_CADENCE_M * 0.5


func _post_side(k: int) -> float:
	return 1.0 if k % 2 == 0 else -1.0


## WS-D countdown boards (300 / 200 / 100 m) before each braking corner, just
## behind the barrier on the outside: white boards with a dark diagonal bar,
## no numerals or text.
func _build_distance_boards() -> void:
	var face := _mat(Color.WHITE, 0.6, _countdown_texture())
	face.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pole := _mat(Color(0.35, 0.36, 0.38), 0.6)
	var board := _acc_new()
	_acc_add_quad_xy(board, 1.4, 1.0, Vector2.ONE, Vector3(0.0, 1.6, 0.0))
	var poles := _acc_new()
	_acc_add_box(poles, Vector3(0.08, 1.6, 0.08), Vector3(0.0, 0.8, 0.04))
	_meshes[KIND_DISTANCE_BOARD] = _mesh_from([{"acc": board, "mat": face}, {"acc": poles, "mat": pole}])
	for ch in TRAP_CHAINAGES:
		var arc := LeMansLayout.arc_at_chainage(ch)
		var side := float(_outside_side(arc))
		for metres in COUNTDOWN_METRES:
			var s := arc - TRAP_HALF_WINDOW_M - metres
			var st := _station(s)
			var basis := _basis_along(st) * Basis(Vector3.UP, PI * 0.5)
			_record(KIND_DISTANCE_BOARD, _xform_ground(st, basis,
				barrier_offset(s, side) + side * COUNTDOWN_OFFSET))
	_flush(KIND_DISTANCE_BOARD)


## WS-D unbranded ad hoardings: plain colour panels from five colour sets on a
## dark frame, behind the armco -- a dense run along the S/F straight (both
## sides) plus one every AD_BOARD_CADENCE_M on the outside elsewhere.
func _build_ad_boards() -> void:
	var face := _mat(Color.WHITE, 0.55, _board_texture())
	face.vertex_color_use_as_albedo = true
	face.cull_mode = BaseMaterial3D.CULL_DISABLED
	var frame := _mat(Color(0.16, 0.17, 0.19), 0.7)
	# The printed face is a UV'd quad (a BoxMesh face only samples one cell of
	# its 3x2 UV atlas), on a dark backing box with two legs.
	var face_acc := _acc_new()
	_acc_add_quad_xy(face_acc, AD_BOARD_SIZE.x, AD_BOARD_SIZE.y, Vector2.ONE,
		Vector3(0.0, AD_BOARD_Y - AD_BOARD_SIZE.y * 0.5, -AD_BOARD_SIZE.z * 0.5 - 0.005))
	var leg_h := AD_BOARD_Y - AD_BOARD_SIZE.y * 0.5
	var frame_acc := _acc_new()
	_acc_add_box(frame_acc, AD_BOARD_SIZE, Vector3(0.0, AD_BOARD_Y, 0.0))
	_acc_add_box(frame_acc, Vector3(AD_BOARD_SIZE.x, 0.1, 0.14), Vector3(0.0, leg_h - 0.05, 0.0))
	_acc_add_box(frame_acc, Vector3(0.1, leg_h, 0.1), Vector3(-AD_BOARD_SIZE.x * 0.45, leg_h * 0.5, 0.0))
	_acc_add_box(frame_acc, Vector3(0.1, leg_h, 0.1), Vector3(AD_BOARD_SIZE.x * 0.45, leg_h * 0.5, 0.0))
	_meshes[KIND_AD_BOARD] = _mesh_from([{"acc": face_acc, "mat": face}, {"acc": frame_acc, "mat": frame}])
	var perimeter := _perimeter()
	var sf := LeMansLayout.start_line_arc()
	var n_sf := int(AD_BOARD_SF_WINDOW_M * 2.0 / AD_BOARD_SF_PITCH_M) + 1
	var idx := 0
	for side: float in [1.0, -1.0]:
		for k in n_sf:
			var s := sf - AD_BOARD_SF_WINDOW_M + float(k) * AD_BOARD_SF_PITCH_M
			_place_ad_board(s, side, idx)
			idx += 1
	var corners := LeMansLayout.sharp_corner_chainages(SHARP_TURN_DEG)
	var count := int(perimeter / AD_BOARD_CADENCE_M)
	for k in count:
		var s := float(k) * AD_BOARD_CADENCE_M + AD_BOARD_CADENCE_M * 0.25
		if absf(fposmod(s - sf + perimeter * 0.5, perimeter) - perimeter * 0.5) < AD_BOARD_SF_WINDOW_M + 10.0:
			continue
		var is_corner := false
		for ch in corners:
			var d := absf(fposmod(s - LeMansLayout.arc_at_chainage(ch) + perimeter * 0.5, perimeter) - perimeter * 0.5)
			if d < 60.0:
				is_corner = true
				break
		if is_corner:
			continue
		var side := float(_outside_side(s))
		_place_ad_board(s, side, idx)
		idx += 1
	_flush(KIND_AD_BOARD)


func _place_ad_board(s: float, side: float, idx: int) -> void:
	var st := _station(s)
	var lateral := barrier_offset(s, side) + side * AD_BOARD_BEHIND
	# Runs of 3-6 boards share a colour so the hoarding reads as sponsor blocks.
	var block := int(floor(float(idx) / (3.0 + float(_hash_i(idx >> 2, 3) % 4))))
	var c: Color = AD_BOARD_COLORS[_hash_i(block, 11) % AD_BOARD_COLORS.size()]
	var basis := _basis_along_pitched(st)
	# The printed face is on local -Z, which is the road side only for a board
	# on the right; turn left-side boards round.
	if side < 0.0:
		basis = basis * Basis(Vector3.UP, PI)
	_record(KIND_AD_BOARD, _xform_ground(st, basis, lateral), c)


## WS-D: TV camera towers at vantage points.
func _build_camera_towers() -> void:
	var tower_mat := _mat(Color(0.48, 0.50, 0.54), 0.7, null, 0.3)
	var mesh := _fused_mesh([
		{"size": CAMERA_TOWER_LEG, "offset": Vector3(-1.2, CAMERA_TOWER_LEG.y * 0.5, -1.2)},
		{"size": CAMERA_TOWER_LEG, "offset": Vector3(1.2, CAMERA_TOWER_LEG.y * 0.5, -1.2)},
		{"size": CAMERA_TOWER_LEG, "offset": Vector3(-1.2, CAMERA_TOWER_LEG.y * 0.5, 1.2)},
		{"size": CAMERA_TOWER_LEG, "offset": Vector3(1.2, CAMERA_TOWER_LEG.y * 0.5, 1.2)},
		{"size": CAMERA_TOWER_DECK, "offset": Vector3(0.0, CAMERA_TOWER_Y, 0.0)},
		{"size": Vector3(2.2, 0.8, 2.2), "offset": Vector3(0.0, CAMERA_TOWER_Y + 0.5, 0.0)},
	], tower_mat)
	_meshes[KIND_CAMERA_TOWER] = mesh
	for ch in CAMERA_TOWER_CHAINAGES:
		var arc := LeMansLayout.arc_at_chainage(ch)
		var side := float(_outside_side(arc))
		var st := _station(arc)
		var lateral := maxf(absf(barrier_offset(arc, side)) + 6.0, road_width * 0.5 + CAMERA_TOWER_OFFSET)
		_record(KIND_CAMERA_TOWER, _xform_ground(st, _basis_along(st), side * lateral))
	_flush(KIND_CAMERA_TOWER)


## WS-E route-memory landmarks at the S/F straight: stepped, roofed grandstand
## modules on the OUTSIDE of the loop and a long two-storey pit building on the
## INSIDE (the side facing the layout centre), behind the fence. Plain massing,
## no signage, no names.
func _build_start_finish_buildings() -> void:
	var concrete := _mat(Color(0.62, 0.62, 0.60), 0.9)
	var seats := _mat(Color(0.30, 0.38, 0.55), 0.7)
	var roof := _mat(Color(0.86, 0.87, 0.88), 0.6, null, 0.3)
	var glass := _mat(Color(0.30, 0.36, 0.42), 0.12, null, 0.5)
	var steps := _acc_new()
	var risers := _acc_new()
	var cover := _acc_new()
	var module_len := GRANDSTAND_MODULE_M - 4.0
	for j in GRANDSTAND_STEPS:
		var z := 1.0 + float(j) * 0.85
		var y := 0.6 + float(j) * 0.5
		_acc_add_box(steps, Vector3(module_len, 0.12, 0.85), Vector3(0.0, y, z))
		_acc_add_box(risers, Vector3(module_len, y, 0.85), Vector3(0.0, y * 0.5 - 0.06, z))
	var back_z := 1.0 + float(GRANDSTAND_STEPS) * 0.85
	var top_y := 0.6 + float(GRANDSTAND_STEPS) * 0.5
	_acc_add_box(risers, Vector3(module_len, top_y + 3.2, 0.4), Vector3(0.0, (top_y + 3.2) * 0.5, back_z))
	_acc_add_box(cover, Vector3(module_len + 2.0, 0.25, back_z + 1.5), Vector3(0.0, top_y + 3.3, back_z * 0.5 - 0.2))
	_meshes[KIND_GRANDSTAND] = _mesh_from([{"acc": risers, "mat": concrete},
		{"acc": steps, "mat": seats}, {"acc": cover, "mat": roof}])
	var walls := _acc_new()
	var windows := _acc_new()
	var top := _acc_new()
	_acc_add_box(walls, Vector3(PIT_MODULE_M - 1.0, 7.0, 14.0), Vector3(0.0, 3.5, 7.0))
	_acc_add_box(windows, Vector3(PIT_MODULE_M - 3.0, 2.2, 0.2), Vector3(0.0, 4.9, -0.05))
	_acc_add_box(windows, Vector3(PIT_MODULE_M - 3.0, 2.6, 0.2), Vector3(0.0, 1.5, -0.05))
	_acc_add_box(top, Vector3(PIT_MODULE_M, 0.5, 15.0), Vector3(0.0, 7.2, 7.0))
	_meshes[KIND_PIT_BUILDING] = _mesh_from([{"acc": walls, "mat": concrete},
		{"acc": windows, "mat": glass}, {"acc": top, "mat": roof}])
	var sf := LeMansLayout.start_line_arc()
	var st0 := _station(sf)
	var c0: Vector3 = st0["center"]
	var r0: Vector3 = st0["right"]
	var to_mid := Vector2(_bbox.get_center().x - c0.x, _bbox.get_center().y - c0.z)
	var inside := 1.0 if to_mid.dot(Vector2(r0.x, r0.z)) > 0.0 else -1.0
	for kind: String in [KIND_GRANDSTAND, KIND_PIT_BUILDING]:
		var side := -inside if kind == KIND_GRANDSTAND else inside
		var module := GRANDSTAND_MODULE_M if kind == KIND_GRANDSTAND else PIT_MODULE_M
		var half := GRANDSTAND_HALF_M if kind == KIND_GRANDSTAND else PIT_HALF_M
		var count := int(half * 2.0 / module)
		for k in count:
			var s := sf - half + (float(k) + 0.5) * module
			var st := _station(s)
			var basis := _basis_along_pitched(st)
			if side < 0.0:
				basis = basis * Basis(Vector3.UP, PI)
			var lateral := barrier_offset(s, side) + side * (CATCH_FENCE_BEHIND + 3.0)
			var t := _xform_ground(st, basis, lateral)
			t.origin.y -= BUILDING_BURY
			_record(kind, t)
		_flush(kind)


## WS-D: service-road dirt tracks behind the barriers at the trap corners.
func _build_service_tracks() -> void:
	var track_mat := _mat(Color(0.36, 0.31, 0.24), 0.97)
	_meshes[KIND_SERVICE_TRACK] = _slab_mesh(Vector3(SERVICE_TRACK_LENGTH, SERVICE_TRACK_LIFT, SERVICE_TRACK_WIDTH), track_mat)
	for ch in TRAP_CHAINAGES:
		var arc := LeMansLayout.arc_at_chainage(ch)
		var side := float(_outside_side(arc))
		var span := TRAP_HALF_WINDOW_M * 2.4
		var count := int(span / SERVICE_TRACK_PITCH) + 1
		for k in count:
			var s := arc - span * 0.5 + float(k) * SERVICE_TRACK_PITCH
			var st := _station(s)
			var lateral := barrier_offset(arc, side) + side * (SERVICE_TRACK_BEHIND + SERVICE_TRACK_WIDTH * 0.5)
			var t := _xform_ground(st, _basis_along_pitched(st), lateral)
			t.origin.y = _ground_y(st, lateral) + SERVICE_TRACK_LIFT
			_record(KIND_SERVICE_TRACK, t)
	_flush(KIND_SERVICE_TRACK)


## 0..1 trap profile at arc `s` on `side`: a smooth bump over each trap window
## (outside of the corner only), 0 elsewhere. Shared by the trap/apron ribbons
## AND `barrier_offset`, so the armco always clears the sand.
func _trap_taper(s: float, side: float) -> float:
	var perimeter := _perimeter()
	var best := 0.0
	for win in _trap_windows:
		var arc: float = win["arc"]
		if float(win["side"]) != side:
			continue
		var d := fposmod(s - arc + perimeter * 0.5, perimeter) - perimeter * 0.5
		if absf(d) >= TRAP_HALF_WINDOW_M:
			continue
		var t := (d + TRAP_HALF_WINDOW_M) / (TRAP_HALF_WINDOW_M * 2.0)
		best = maxf(best, pow(sin(PI * t), 0.6))
	return best


## WS-A: one sand trap + one paved apron per TRAP_CHAINAGES corner, outside of
## the turn. Both are ribbon meshes on the plain using `le_mans_gravel.gdshader`
## (UV = world XZ, COLOR.a = 1 inside / 0 on the fringe row) so the trap edge is
## torn and blends into the very grass the plain draws. Each station also
## records a KIND_TRAP / KIND_RUNOFF transform (query API + determinism tests)
## and each trap/apron's solid rows become one SurfaceRegistry polygon.
func _build_traps_and_runoff() -> void:
	var trap_rows: Array[Dictionary] = []
	var apron_rows: Array[Dictionary] = []
	for ti in TRAP_CHAINAGES.size():
		var arc := LeMansLayout.arc_at_chainage(TRAP_CHAINAGES[ti])
		var side := float(_outside_side(arc))
		var steps := int(TRAP_HALF_WINDOW_M * 2.0 / TRAP_STEP_M)
		var trap_inner := PackedVector3Array()
		var trap_outer := PackedVector3Array()
		var trap_fringe := PackedVector3Array()
		var apron_inner := PackedVector3Array()
		var apron_outer := PackedVector3Array()
		var apron_fringe := PackedVector3Array()
		for k in steps + 1:
			var s := arc - TRAP_HALF_WINDOW_M + float(k) * TRAP_STEP_M
			var st := _station(s)
			var taper := _trap_taper(s, side)
			var rag := TRAP_RAGGED_M * (sin(float(k) * 1.31 + float(ti)) * 0.6 + sin(float(k) * 0.47 + 2.0 * float(ti)) * 0.4)
			var rag2 := TRAP_RAGGED_M * sin(float(k) * 0.83 + 0.5 * float(ti))
			var edge := road_width * 0.5
			var apron_w := APRON_WIDTH_M * minf(taper * 1.6, 1.0)
			var trap_in := edge + apron_w - 0.3
			var trap_out := trap_in + 0.3 + TRAP_WIDTH_M * taper + rag * taper
			var fringe := trap_out + TRAP_FRINGE_M * (0.6 + 0.4 * taper) + rag2
			apron_inner.append(_ground_point(st, side * (edge - 0.05), RUNOFF_LIFT))
			apron_outer.append(_ground_point(st, side * (edge + apron_w), RUNOFF_LIFT))
			apron_fringe.append(_ground_point(st, side * (edge + apron_w + 0.5 * taper), RUNOFF_LIFT))
			trap_inner.append(_ground_point(st, side * trap_in, TRAP_LIFT))
			trap_outer.append(_ground_point(st, side * trap_out, TRAP_LIFT))
			trap_fringe.append(_ground_point(st, side * fringe, TRAP_LIFT))
			_record(KIND_TRAP, _xform_ground(st, _basis_along(st), side * (trap_in + trap_out) * 0.5))
			_record(KIND_RUNOFF, _xform_ground(st, _basis_along(st), side * (edge + apron_w * 0.5)))
		trap_rows.append({"rows": [trap_inner, trap_outer, trap_fringe], "alpha": [1.0, 1.0, 0.0]})
		apron_rows.append({"rows": [apron_inner, apron_outer, apron_fringe], "alpha": [1.0, 1.0, 0.0]})
		_zones.append({"poly": _zone_poly(trap_inner, trap_outer), "surface": SurfaceRegistry.SAND})
	for ar: Dictionary in apron_rows:
		var rows: Array = ar["rows"]
		_zones.append({"poly": _zone_poly(rows[0] as PackedVector3Array, rows[1] as PackedVector3Array),
			"surface": SurfaceRegistry.ASPHALT})
	_meshes[KIND_TRAP] = _ribbon_mesh(trap_rows, LeMansSurfaces.gravel_material(0.0))
	_meshes[KIND_RUNOFF] = _ribbon_mesh(apron_rows, LeMansSurfaces.gravel_material(1.0))
	_emit_mesh_node(KIND_TRAP)
	_emit_mesh_node(KIND_RUNOFF)


## Closed XZ polygon: inner row forward, outer row backward.
func _zone_poly(inner: PackedVector3Array, outer: PackedVector3Array) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for p in inner:
		poly.append(Vector2(p.x, p.z))
	for i in range(outer.size() - 1, -1, -1):
		poly.append(Vector2(outer[i].x, outer[i].z))
	return poly


## WS-E near forest edge: canopy clumps 30-65 m off both edges round the lap,
## with deterministic field openings (TREELINE_GAP_FRACTION of 180 m blocks per
## side stay open), the S/F area kept clear, and every clump at least
## TREELINE_CLEARANCE from ANY part of the circuit (the loop folds back).
func _build_treeline() -> void:
	var leaf := _leaf_mat()
	var trunk := _mat(Color(0.22, 0.17, 0.12), 0.95)
	var crown := _acc_new()
	_acc_add_sphere(crown, Vector3(1.0, 0.72, 1.0), Vector3(0.0, 0.52, 0.0), 8, 5)
	_acc_add_sphere(crown, Vector3(0.70, 0.50, 0.66), Vector3(0.26, 0.86, 0.12), 7, 4)
	_acc_add_sphere(crown, Vector3(0.62, 0.46, 0.62), Vector3(-0.30, 0.80, -0.16), 7, 4)
	_acc_add_sphere(crown, Vector3(0.58, 0.40, 0.55), Vector3(0.05, 1.02, -0.22), 6, 4)
	_acc_add_sphere(crown, Vector3(0.75, 0.42, 0.70), Vector3(-0.10, 0.30, 0.30), 6, 4)
	var stem := _acc_new()
	_acc_add_box(stem, Vector3(0.045, 0.3, 0.045), Vector3(0.0, 0.15, 0.0))
	_meshes[KIND_TREELINE] = _mesh_from([{"acc": crown, "mat": leaf}, {"acc": stem, "mat": trunk}])
	var perimeter := _perimeter()
	var count := int(perimeter / TREELINE_PITCH_M)
	for side: float in [1.0, -1.0]:
		for k in count:
			var s := float(k) * TREELINE_PITCH_M
			if _forest_gap(s, side):
				continue
			var h := _hash01(k * 2 + int(side > 0.0), 29)
			var lateral := side * maxf(TREELINE_MIN_OFFSET + (TREELINE_MAX_OFFSET - TREELINE_MIN_OFFSET) * h,
				absf(barrier_offset(s, side)) + 12.0)
			var st := _station(s)
			var t := _xform_ground(st, _basis_along(st), lateral)
			if not _clear_of_road(Vector2(t.origin.x, t.origin.z), TREELINE_CLEARANCE) or not _on_plane(t.origin):
				continue
			var w := 8.0 + 7.0 * _hash01(k, 31)
			var ht := 10.0 + 9.0 * _hash01(k, 37)
			t.basis = Basis(Vector3.UP, TAU * _hash01(k, 41)) * Basis.from_scale(Vector3(w, ht, w))
			t.origin.y -= TREE_BURY
			_record(KIND_TREELINE, t, _leaf_color(k, 0.6 + 0.25 * _hash01(k, 43)))
	_flush(KIND_TREELINE)
	_build_forest_wall()


## True when arc `s` on `side` is inside a deterministic field opening (or the
## open S/F area) -- shared by the clumps and the forest wall so gaps agree.
func _forest_gap(s: float, side: float) -> bool:
	var perimeter := _perimeter()
	var sf := LeMansLayout.start_line_arc()
	if absf(fposmod(s - sf + perimeter * 0.5, perimeter) - perimeter * 0.5) < TREELINE_SF_CLEAR_M:
		return true
	var block := int(s / TREELINE_GAP_BLOCK_M)
	return _hash01(block * 2 + int(side > 0.0), 17) < TREELINE_GAP_FRACTION


## The forest mass behind the clumps: a dense band of big, trunk-less canopy
## masses (overlapping low-poly lobes) FOREST_WALL_OFFSET (+- a slow wobble)
## off the road, broken at the same field openings as the clumps and wherever
## it would come within FOREST_WALL_CLEARANCE of any part of the circuit. It is
## what turns a row of trees into a wood edge. (A first version used one flat
## vertical sheet; up close from another leg of the lap it read as a painted
## wall, so it is instanced canopy like everything else.)
func _build_forest_wall() -> void:
	var leaf := _leaf_mat()
	leaf.uv1_scale = Vector3(0.12, 0.12, 0.12)
	var acc := _acc_new()
	_acc_add_sphere(acc, Vector3(1.0, 0.9, 0.85), Vector3(0.0, 0.42, 0.0), 7, 4)
	_acc_add_sphere(acc, Vector3(0.7, 0.62, 0.7), Vector3(0.32, 0.72, 0.15), 6, 4)
	_acc_add_sphere(acc, Vector3(0.65, 0.55, 0.62), Vector3(-0.35, 0.66, -0.12), 6, 4)
	_meshes[KIND_FOREST_WALL] = _mesh_from([{"acc": acc, "mat": leaf}])
	var perimeter := _perimeter()
	var count := int(perimeter / FOREST_WALL_STEP_M)
	for side: float in [1.0, -1.0]:
		for k in count:
			var s := float(k) * FOREST_WALL_STEP_M
			if _forest_gap(s, side):
				continue
			var key := k * 2 + int(side > 0.0)
			var wob := sin(s * 0.011 + side) * 0.6 + sin(s * 0.047 + 2.0 * side) * 0.4
			var lateral := side * maxf(FOREST_WALL_OFFSET + FOREST_WALL_OFFSET_VAR * wob
				+ 6.0 * (_hash01(key, 79) - 0.5), absf(barrier_offset(s, side)) + 22.0)
			var st := _station(s)
			var t := _xform_ground(st, _basis_along(st), lateral)
			if not _clear_of_road(Vector2(t.origin.x, t.origin.z), FOREST_WALL_CLEARANCE) or not _on_plane(t.origin):
				continue
			var w := 15.0 + 9.0 * _hash01(key, 83)
			var ht := FOREST_WALL_HEIGHT + FOREST_WALL_HEIGHT_VAR * _hash01(key, 89)
			t.basis = Basis(Vector3.UP, TAU * _hash01(key, 91)) * Basis.from_scale(Vector3(w, ht, w))
			t.origin.y -= TREE_BURY
			_record(KIND_FOREST_WALL, t, _leaf_color(key + 5000, 0.5 + 0.2 * _hash01(key, 93)))
	_flush(KIND_FOREST_WALL)


## WS-E far canopy ring: big low-poly clumps in a 300-1,100 m band either side
## of the lap (two staggered rows), cleared FAR_TREE_CLEARANCE from any part of
## the circuit and kept on the ground plane. Dark, unshadowed, never
## range-culled: this is the horizon the aerial-perspective fog works on.
func _build_far_treeline() -> void:
	var leaf := _leaf_mat()
	leaf.uv1_scale = Vector3(0.05, 0.05, 0.05)
	var acc := _acc_new()
	_acc_add_sphere(acc, Vector3(1.0, 0.9, 0.8), Vector3(0.0, 0.42, 0.0), 6, 3)
	_acc_add_sphere(acc, Vector3(0.6, 0.5, 0.6), Vector3(0.3, 0.8, 0.1), 6, 3)
	_meshes[KIND_FAR_TREELINE] = _mesh_from([{"acc": acc, "mat": leaf}])
	var perimeter := _perimeter()
	var count := int(perimeter / FAR_TREE_PITCH_M)
	for side: float in [1.0, -1.0]:
		for row in FAR_TREE_ROWS:
			for k in count:
				var key := (k * FAR_TREE_ROWS + row) * 2 + int(side > 0.0)
				var s := (float(k) + 0.5 * float(row)) * FAR_TREE_PITCH_M
				var band_t := (float(row) + _hash01(key, 53)) / float(FAR_TREE_ROWS)
				var lateral := side * (FAR_TREE_BAND_MIN + (FAR_TREE_BAND_MAX - FAR_TREE_BAND_MIN) * band_t)
				var st := _station(s)
				var t := _xform_ground(st, _basis_along(st), lateral)
				if not _clear_of_road(Vector2(t.origin.x, t.origin.z), FAR_TREE_CLEARANCE) or not _on_plane(t.origin):
					continue
				var w := 26.0 + 22.0 * _hash01(key, 59)
				var ht := 15.0 + 9.0 * _hash01(key, 61)
				t.basis = Basis(Vector3.UP, TAU * _hash01(key, 67)) * Basis.from_scale(Vector3(w, ht, w))
				t.origin.y -= TREE_BURY * 4.0
				_record(KIND_FAR_TREELINE, t, _leaf_color(key, 0.55 + 0.2 * _hash01(key, 71)))
	_flush(KIND_FAR_TREELINE)


## WS-E low landmark silhouettes (works sheds + chimney, a church with a spire,
## a round-roof hangar, a long wall), far out (340-700 m, first offset that is
## clear of the circuit and on the plane) so the fog reads them as distance.
func _build_silhouettes() -> void:
	var ind_mat := _mat(Color(0.40, 0.40, 0.42), 0.9)
	var brick := _mat(Color(0.46, 0.36, 0.30), 0.9)
	var roof := _mat(Color(0.30, 0.31, 0.34), 0.8)
	var stone := _mat(Color(0.62, 0.60, 0.55), 0.9)
	var works := _acc_new()
	_acc_add_box(works, Vector3(60.0, 12.0, 30.0), Vector3(0.0, 6.0, 0.0))
	_acc_add_box(works, Vector3(36.0, 18.0, 24.0), Vector3(40.0, 9.0, 8.0))
	var chimney := _acc_new()
	_acc_add_cylinder(chimney, 1.8, 2.4, 42.0, Vector3(-22.0, 21.0, 8.0))
	_meshes[KIND_SILHOUETTE_INDUSTRIAL] = _mesh_from([{"acc": works, "mat": ind_mat}, {"acc": chimney, "mat": brick}])
	var nave := _acc_new()
	_acc_add_box(nave, Vector3(30.0, 14.0, 13.0), Vector3(0.0, 7.0, 0.0))
	_acc_add_box(nave, Vector3(8.0, 26.0, 8.0), Vector3(-17.0, 13.0, 0.0))
	var spire := _acc_new()
	_acc_add_cylinder(spire, 0.0, 5.2, 18.0, Vector3(-17.0, 35.0, 0.0), 4)
	_acc_add_box(spire, Vector3(31.0, 1.2, 14.0), Vector3(0.0, 14.4, 0.0))
	_meshes[KIND_SILHOUETTE_CHURCH] = _mesh_from([{"acc": nave, "mat": stone}, {"acc": spire, "mat": roof}])
	var shed := _acc_new()
	_acc_add_box(shed, Vector3(60.0, 8.0, 40.0), Vector3(0.0, 4.0, 0.0))
	var vault := _acc_new()
	var vault_cyl := CylinderMesh.new()
	vault_cyl.top_radius = 20.0
	vault_cyl.bottom_radius = 20.0
	vault_cyl.height = 60.0
	vault_cyl.radial_segments = 16
	_acc_add_arrays(vault, vault_cyl.surface_get_arrays(0),
		Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5).scaled(Vector3(1.0, 0.35, 1.0)), Vector3(0.0, 8.0, 0.0)))
	_meshes[KIND_SILHOUETTE_HANGAR] = _mesh_from([{"acc": shed, "mat": ind_mat}, {"acc": vault, "mat": roof}])
	var wall := _acc_new()
	_acc_add_box(wall, Vector3(140.0, 7.0, 1.2), Vector3(0.0, 3.5, 0.0))
	_acc_add_box(wall, Vector3(30.0, 10.0, 18.0), Vector3(60.0, 5.0, 10.0))
	_meshes[KIND_SILHOUETTE_WALLS] = _mesh_from([{"acc": wall, "mat": stone}])
	var kinds: Array[String] = [KIND_SILHOUETTE_INDUSTRIAL, KIND_SILHOUETTE_CHURCH,
		KIND_SILHOUETTE_HANGAR, KIND_SILHOUETTE_WALLS]
	for i in SILHOUETTE_CHAINAGES.size():
		var arc := LeMansLayout.arc_at_chainage(SILHOUETTE_CHAINAGES[i])
		var st := _station(arc)
		var outside := float(_outside_side(arc))
		for off in SILHOUETTE_OFFSETS:
			var placed := false
			for side: float in [outside, -outside]:
				var t := _xform_ground(st, _basis_along(st), side * off)
				if _clear_of_road(Vector2(t.origin.x, t.origin.z), SILHOUETTE_CLEARANCE) and _on_plane(t.origin):
					t.basis = Basis(Vector3.UP, TAU * _hash01(i, 73)) * t.basis
					t.origin.y -= BUILDING_BURY * 4.0
					_record(kinds[i], t)
					placed = true
					break
			if placed:
				break
	for kind in kinds:
		_flush(kind)


## WS-F wear decals: braking streaks before and rubber after every sharp corner,
## oil patches at every third apex, dirt spilled from each trap onto the road
## edge, and the grid/launch rubber at the S/F line. Generated textures (no
## assets), projected only onto DECAL_LAYER, distance-faded, recorded under
## KIND_DECAL for the query API. Visibility is owned by the quality ladder
## (settings_menu.gd `decals_enabled`: Low off, Medium/High on).
func _build_wear_decals() -> void:
	var streak := _skid_texture()
	var blob := _blob_texture(false)
	var dirt := _blob_texture(true)
	var oil_orm := _oil_orm_texture()
	var sf := LeMansLayout.start_line_arc()
	for j in 2:
		var lane := (float(j) - 0.5) * road_width * 0.42
		_add_decal("WearDecal_StartFinish_%d" % j, sf - 14.0, lane, Vector3(2.6, 1.2, 22.0), streak, null, 0.85)
	var corners := LeMansLayout.sharp_corner_chainages(SHARP_TURN_DEG)
	for i in corners.size():
		var arc := LeMansLayout.arc_at_chainage(corners[i])
		var outside := float(_outside_side(arc))
		_add_decal("WearDecal_Brake_%d" % i, arc - 48.0, outside * road_width * 0.22,
			Vector3(3.4, 1.2, 26.0), streak, null, 0.9)
		_add_decal("WearDecal_Exit_%d" % i, arc + 32.0, outside * road_width * 0.26,
			Vector3(3.0, 1.2, 16.0), streak, null, 0.7)
		if i % 3 == 0:
			_add_decal("WearDecal_Oil_%d" % i, arc, -outside * road_width * 0.18,
				Vector3(2.2, 1.2, 2.8), blob, oil_orm, 0.8)
	for ti in TRAP_CHAINAGES.size():
		var arc2 := LeMansLayout.arc_at_chainage(TRAP_CHAINAGES[ti])
		var side := float(_outside_side(arc2))
		_add_decal("WearDecal_Dirt_%d" % ti, arc2 + 14.0, side * (road_width * 0.5 - 0.6),
			Vector3(4.5, 1.6, 10.0), dirt, null, 0.95)


func _add_decal(decal_name: String, s: float, lateral: float, size: Vector3,
		albedo: Texture2D, orm: Texture2D, mix_amount: float) -> void:
	var st := _station(s)
	var cross: Vector3 = st["cross"]
	var t := _xform_on_road(st, _basis_span_pitched(st), cross * lateral)
	t.origin.y += DECAL_LIFT
	var d := Decal.new()
	d.name = decal_name
	d.size = size
	d.texture_albedo = albedo
	if orm != null:
		d.texture_orm = orm
	d.albedo_mix = mix_amount
	d.cull_mask = DECAL_LAYER
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.distance_fade_enabled = true
	d.distance_fade_begin = DECAL_FADE_BEGIN
	d.distance_fade_length = DECAL_FADE_LENGTH
	d.transform = t
	add_child(d)
	_record(KIND_DECAL, t)

## --- spatial helpers ---------------------------------------------------------

## Grid of every 3rd centerline point (~8.5 m) in 60 m cells.
func _build_grid() -> void:
	_grid = {}
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in range(0, road_points.size(), 3):
		var p := Vector2(road_points[i].x, road_points[i].z)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		var cell := Vector2i(floori(p.x / 60.0), floori(p.y / 60.0))
		if not _grid.has(cell):
			_grid[cell] = PackedVector2Array()
		var arr: PackedVector2Array = _grid[cell]
		arr.append(p)
		_grid[cell] = arr
	_bbox = Rect2(lo, hi - lo)


## True when `p` (world XZ) is at least `radius` from every centerline point.
func _clear_of_road(p: Vector2, radius: float) -> bool:
	var reach := int(ceil(radius / 60.0))
	var c := Vector2i(floori(p.x / 60.0), floori(p.y / 60.0))
	var r2 := radius * radius
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var key := Vector2i(c.x + dx, c.y + dz)
			if not _grid.has(key):
				continue
			var arr: PackedVector2Array = _grid[key]
			for q in arr:
				if p.distance_squared_to(q) < r2:
					return false
	return true


## Inside the layout bbox grown by PLANE_MARGIN (i.e. on le_mans.gd's plane).
func _on_plane(origin: Vector3) -> bool:
	return _bbox.grow(PLANE_MARGIN).has_point(Vector2(origin.x, origin.z))


## Deterministic integer hash -> [0, 1).
static func _hash01(i: int, salt: int) -> float:
	return float(_hash_i(i, salt) % 10007) / 10007.0


static func _hash_i(i: int, salt: int) -> int:
	var h := (i * 73856093) ^ (salt * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return absi(h)


## Foliage material: instance colour x a world-triplanar leaf-noise albedo, so
## low-poly canopy lobes break up into clumps instead of flat shaded facets.
func _leaf_mat() -> StandardMaterial3D:
	var m := _mat(Color.WHITE, 0.95, LeMansSurfaces.leaf_texture())
	m.vertex_color_use_as_albedo = true
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.35, 0.35, 0.35)
	return m


## A deterministic foliage green for instance `i`, scaled by `value`.
static func _leaf_color(i: int, value: float) -> Color:
	var h := _hash01(i, 97)
	var base := Color(0.13, 0.24, 0.09).lerp(Color(0.22, 0.30, 0.12), h)
	if _hash01(i, 101) < 0.12:
		base = Color(0.26, 0.28, 0.12)
	return Color(base.r * value, base.g * value, base.b * value)

## --- road-frame math (same neighbour-tangent + bank convention as the road
## --- mesh and `LeMansLayout.frame_at_arc`, so dressing and asphalt agree) ----

func _perimeter() -> float:
	if _perim < 0.0:
		var total := 0.0
		var n := road_points.size()
		for i in n:
			total += road_points[i].distance_to(road_points[(i + 1) % n])
		_perim = total if total > 0.0 else 1.0
	return _perim


func _spacing() -> float:
	var n := road_points.size()
	if n < 2:
		return 1.0
	return _perimeter() / float(n)


func _bank_at(i: int) -> float:
	if i < 0 or i >= bank_profile.size():
		return 0.0
	return float(bank_profile[i])


## Road frame at arc `s`: {center, forward, right, cross, normal, bank}.
##
## INTERPOLATED between centerline points (the road mesh is linear between
## them, so the lerped centre lies on the asphalt): a 5 m pitch over 2.84 m
## points must not snap to the nearest point, or consecutive armco/fence
## segments land 2.84 / 5.68 m apart and visibly gap and overlap.
func _station(s: float) -> Dictionary:
	var n := road_points.size()
	var idx := fposmod(s, _perimeter()) / _spacing()
	var i0 := int(idx) % n
	var i1 := (i0 + 1) % n
	var frac := idx - floorf(idx)
	var f0 := road_points[i1] - road_points[(i0 - 1 + n) % n]
	var f1 := road_points[(i1 + 1) % n] - road_points[i0]
	var forward := f0.lerp(f1, frac).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var angle := lerpf(_bank_at(i0), _bank_at(i1), frac)
	return {
		"center": road_points[i0].lerp(road_points[i1], frac),
		"forward": forward,
		"right": right,
		"cross": right * cos(angle) - Vector3.UP * sin(angle),
		"normal": Vector3.UP * cos(angle) + right * sin(angle),
		"bank": angle,
	}


## +1 when the corner at `s` turns LEFT (its outside is the right side), -1
## when it turns right.
func _outside_side(s: float) -> int:
	var t1: Vector3 = _station(s - CORNER_PROBE_M)["forward"]
	var t2: Vector3 = _station(s + CORNER_PROBE_M)["forward"]
	return 1 if (t1.cross(t2)).y > 0.0 else -1


func _ground_y(station: Dictionary, offset: float) -> float:
	var center: Vector3 = station["center"]
	var right: Vector3 = station["right"]
	if height_provider.is_valid():
		# The provider is asked at the prop's OWN XZ (not the road centre): on
		# real elevation the ground 30 m or 1 km out is not the ground at the
		# road, and le_mans.gd's provider is the terrain's own triangles.
		return float(height_provider.call(Vector3(
			center.x + right.x * offset, 0.0, center.z + right.z * offset)))
	# No provider (standalone probes): the road-corridor ground the scene's
	# terrain is built from -- ROAD_BASE_Y - PLAIN_Y under the inner edge.
	var bank: float = station["bank"]
	return center.y - (LeMansLayout.ROAD_BASE_Y - LeMansLayout.PLAIN_Y) \
		- (road_width * 0.5) * absf(sin(bank))


## World point `lateral` m right of the centerline at plain height + `lift`.
func _ground_point(station: Dictionary, lateral: float, lift: float) -> Vector3:
	var center: Vector3 = station["center"]
	var right: Vector3 = station["right"]
	return Vector3(center.x + right.x * lateral, _ground_y(station, lateral) + lift,
		center.z + right.z * lateral)

## --- transform helpers -------------------------------------------------------

func _basis_along(station: Dictionary) -> Basis:
	var f: Vector3 = station["forward"]
	var fwd := Vector3(f.x, 0.0, f.z).normalized()
	return Basis(fwd, Vector3.UP, fwd.cross(Vector3.UP))


## Along-road basis that FOLLOWS THE GRADE: local X is the (pitched) road
## tangent, Y the up vector orthogonalised against it. For long props laid along
## the road (armco, fences, hoardings, hedges, panels, kerbs, stands) so their
## ends meet the ground on a climb; vertical props keep `_basis_along`.
func _basis_along_pitched(station: Dictionary) -> Basis:
	var f: Vector3 = (station["forward"] as Vector3).normalized()
	var up := (Vector3.UP - f * Vector3.UP.dot(f)).normalized()
	return Basis(f, up, f.cross(up))


## `_basis_span` that follows the grade (local Z = -pitched tangent): decals and
## the S/F paint lie ON a climbing road.
func _basis_span_pitched(station: Dictionary) -> Basis:
	var f: Vector3 = (station["forward"] as Vector3).normalized()
	var fwd_h := Vector3(f.x, 0.0, f.z).normalized()
	var right := fwd_h.cross(Vector3.UP)
	var back := -f
	return Basis(right, back.cross(right), back)


func _basis_span(station: Dictionary) -> Basis:
	var f: Vector3 = station["forward"]
	var fwd := Vector3(f.x, 0.0, f.z).normalized()
	var right := fwd.cross(Vector3.UP)
	return Basis(right, Vector3.UP, -fwd)


func _basis_surface(station: Dictionary) -> Basis:
	var f: Vector3 = (station["forward"] as Vector3).normalized()
	var normal: Vector3 = station["normal"]
	# Orthogonalise against the PITCHED tangent (real elevation): the bank-only
	# normal is not perpendicular to a climbing road.
	normal = (normal - f * normal.dot(f)).normalized()
	return Basis(f, normal, f.cross(normal))


func _xform_on_road(station: Dictionary, basis: Basis, offset: Vector3) -> Transform3D:
	var center: Vector3 = station["center"]
	return Transform3D(basis, center + offset)


func _xform_ground(station: Dictionary, basis: Basis, offset: float) -> Transform3D:
	var center: Vector3 = station["center"]
	var right: Vector3 = station["right"]
	return Transform3D(basis, Vector3(
		center.x + right.x * offset, _ground_y(station, offset), center.z + right.z * offset))

## --- mesh accumulator ----------------------------------------------------------
## Geometry is gathered per MATERIAL into one surface (vertex/normal/uv/index
## arrays), so a fused prop costs one draw per material, not one per box.

func _acc_new() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(),
		"uv": PackedVector2Array(), "i": PackedInt32Array()}


## Append a primitive's surface arrays, transformed by `xf` (normals by its
## inverse-transpose so non-uniform scales stay correctly lit).
func _acc_add_arrays(acc: Dictionary, arrays: Array, xf: Transform3D) -> void:
	var v: PackedVector3Array = acc["v"]
	var n: PackedVector3Array = acc["n"]
	var uv: PackedVector2Array = acc["uv"]
	var idx: PackedInt32Array = acc["i"]
	var base := v.size()
	var src_v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var src_n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var src_uv: Variant = arrays[Mesh.ARRAY_TEX_UV]
	var src_i: Variant = arrays[Mesh.ARRAY_INDEX]
	var nb := xf.basis.inverse().transposed()
	for k in src_v.size():
		v.append(xf * src_v[k])
		n.append((nb * src_n[k]).normalized())
		if src_uv is PackedVector2Array and (src_uv as PackedVector2Array).size() > k:
			uv.append((src_uv as PackedVector2Array)[k])
		else:
			uv.append(Vector2.ZERO)
	if src_i is PackedInt32Array and (src_i as PackedInt32Array).size() > 0:
		for k in (src_i as PackedInt32Array):
			idx.append(base + k)
	else:
		for k in src_v.size():
			idx.append(base + k)
	acc["v"] = v
	acc["n"] = n
	acc["uv"] = uv
	acc["i"] = idx


func _acc_add_box(acc: Dictionary, size: Vector3, offset: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	_acc_add_arrays(acc, box.surface_get_arrays(0), Transform3D(Basis.IDENTITY, offset))


## Ellipsoid lobe: a unit-diameter low-poly sphere scaled by `scale` (full
## extents, m) at `offset`.
func _acc_add_sphere(acc: Dictionary, scale: Vector3, offset: Vector3, radial: int, rings: int) -> void:
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	sph.radial_segments = radial
	sph.rings = rings
	_acc_add_arrays(acc, sph.surface_get_arrays(0), Transform3D(Basis.from_scale(scale), offset))


func _acc_add_cylinder(acc: Dictionary, top_r: float, bottom_r: float, height: float,
		offset: Vector3, radial: int = 10) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = top_r
	cyl.bottom_radius = bottom_r
	cyl.height = height
	cyl.radial_segments = radial
	cyl.rings = 1
	_acc_add_arrays(acc, cyl.surface_get_arrays(0), Transform3D(Basis.IDENTITY, offset))


## A vertical quad in the local XY plane (normal +Z), `w` x `h`, bottom edge at
## `origin.y`, UV 0..`uv_scale`. Double-sided materials only.
func _acc_add_quad_xy(acc: Dictionary, w: float, h: float, uv_scale: Vector2,
		origin: Vector3 = Vector3.ZERO) -> void:
	var v: PackedVector3Array = acc["v"]
	var n: PackedVector3Array = acc["n"]
	var uv: PackedVector2Array = acc["uv"]
	var idx: PackedInt32Array = acc["i"]
	var base := v.size()
	v.append(origin + Vector3(-w * 0.5, 0.0, 0.0))
	v.append(origin + Vector3(w * 0.5, 0.0, 0.0))
	v.append(origin + Vector3(-w * 0.5, h, 0.0))
	v.append(origin + Vector3(w * 0.5, h, 0.0))
	for _k in 4:
		n.append(Vector3(0, 0, 1))
	uv.append(Vector2(0.0, uv_scale.y))
	uv.append(Vector2(uv_scale.x, uv_scale.y))
	uv.append(Vector2(0.0, 0.0))
	uv.append(Vector2(uv_scale.x, 0.0))
	LeMansSurfaces.append_quad_facing(idx, v, base, base + 1, base + 2, base + 3, Vector3(0, 0, 1))
	acc["v"] = v
	acc["n"] = n
	acc["uv"] = uv
	acc["i"] = idx


## Extrude a (z, y) profile polyline `length` m along local X (centred), flat
## normals per profile segment facing the road side (local -Z).
func _acc_add_profile(acc: Dictionary, profile: Array[Vector2], length: float) -> void:
	var v: PackedVector3Array = acc["v"]
	var n: PackedVector3Array = acc["n"]
	var uv: PackedVector2Array = acc["uv"]
	var idx: PackedInt32Array = acc["i"]
	var hx := length * 0.5
	for j in profile.size() - 1:
		var p0 := profile[j]
		var p1 := profile[j + 1]
		var d := p1 - p0
		var nrm := Vector3(0.0, d.x, -d.y).normalized()
		if nrm.z > 0.0:
			nrm = -nrm
		var base := v.size()
		v.append(Vector3(-hx, p0.y, p0.x))
		v.append(Vector3(hx, p0.y, p0.x))
		v.append(Vector3(-hx, p1.y, p1.x))
		v.append(Vector3(hx, p1.y, p1.x))
		for _k in 4:
			n.append(nrm)
		uv.append(Vector2(0, 0))
		uv.append(Vector2(1, 0))
		uv.append(Vector2(0, 1))
		uv.append(Vector2(1, 1))
		LeMansSurfaces.append_quad_facing(idx, v, base, base + 1, base + 2, base + 3, nrm)
	acc["v"] = v
	acc["n"] = n
	acc["uv"] = uv
	acc["i"] = idx


## ArrayMesh with one surface per {acc, mat} group.
func _mesh_from(groups: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for g: Dictionary in groups:
		var acc: Dictionary = g["acc"]
		var verts: PackedVector3Array = acc["v"]
		if verts.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = acc["n"]
		arrays[Mesh.ARRAY_TEX_UV] = acc["uv"]
		arrays[Mesh.ARRAY_INDEX] = acc["i"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, g["mat"] as Material)
	return mesh


## Ribbon mesh for traps/aprons: per entry, `rows` = Array of row point arrays
## (inner .. outer, all the same length), `alpha` = per-row COLOR.a. UV = world
## XZ (m); tangent +X; normal up; front faces up.
func _ribbon_mesh(entries: Array[Dictionary], mat: Material) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for e in entries:
		var rows: Array = e["rows"]
		var alpha: Array = e["alpha"]
		var row_count := rows.size()
		var row_len := (rows[0] as PackedVector3Array).size()
		var base := verts.size()
		for k in row_len:
			for r in row_count:
				var p: Vector3 = (rows[r] as PackedVector3Array)[k]
				verts.append(p)
				normals.append(Vector3.UP)
				tangents.append_array([1.0, 0.0, 0.0, 1.0])
				uvs.append(Vector2(p.x, p.z))
				colors.append(Color(1.0, 1.0, 1.0, float(alpha[r])))
		for k in row_len - 1:
			for r in row_count - 1:
				var a := base + k * row_count + r
				var c := base + (k + 1) * row_count + r
				LeMansSurfaces.append_quad_up(indices, verts, a, a + 1, c, c + 1)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	return mesh


## Fused box props: entries {size, offset[, mat]}; boxes sharing a material are
## merged into one surface.
func _fused_mesh(entries: Array, mat: Material) -> ArrayMesh:
	var groups: Array = []
	var by_mat: Dictionary = {}
	for e: Dictionary in entries:
		var m: Material = e.get("mat", mat) as Material
		if not by_mat.has(m):
			by_mat[m] = groups.size()
			groups.append({"acc": _acc_new(), "mat": m})
		var g: Dictionary = groups[int(by_mat[m])]
		_acc_add_box(g["acc"] as Dictionary, e["size"] as Vector3, e["offset"] as Vector3)
	return _mesh_from(groups)


func _slab_mesh(size: Vector3, mat: Material) -> ArrayMesh:
	return _fused_mesh([{"size": size, "offset": Vector3.ZERO}], mat)


func _cylinder_mesh(radius: float, height: float, mat: Material) -> ArrayMesh:
	var acc := _acc_new()
	_acc_add_cylinder(acc, radius, radius, height, Vector3.ZERO, 12)
	return _mesh_from([{"acc": acc, "mat": mat}])


func _mat(color: Color, roughness: float, texture: Texture2D = null, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if texture != null:
		m.albedo_texture = texture
	return m

## --- generated textures (deterministic; cached per process) ------------------

static var _tex_cache: Dictionary = {}


func _checker_texture() -> ImageTexture:
	if _tex_cache.has("checker"):
		return _tex_cache["checker"] as ImageTexture
	var img := Image.create(CHECKER_CELLS_X * CHECKER_CELL_PX, CHECKER_CELLS_Y * CHECKER_CELL_PX,
		false, Image.FORMAT_RGB8)
	for y in CHECKER_CELLS_Y:
		for x in CHECKER_CELLS_X:
			var dark := (x + y) % 2 == 1
			img.fill_rect(Rect2i(x * CHECKER_CELL_PX, y * CHECKER_CELL_PX,
				CHECKER_CELL_PX, CHECKER_CELL_PX),
				Color(0.06, 0.06, 0.07) if dark else Color(0.94, 0.94, 0.94))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["checker"] = tex
	return tex


func _stripe_texture() -> ImageTexture:
	if _tex_cache.has("stripe"):
		return _tex_cache["stripe"] as ImageTexture
	var img := Image.create(8 * 8, 8, false, Image.FORMAT_RGB8)
	for i in 8:
		img.fill_rect(Rect2i(i * 8, 0, 8, 8),
			Color(0.75, 0.10, 0.10) if i % 2 == 0 else Color(0.94, 0.94, 0.94))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["stripe"] = tex
	return tex


## Blue/white barrier-panel blocks (4 blocks across the panel).
func _panel_texture() -> ImageTexture:
	if _tex_cache.has("panel"):
		return _tex_cache["panel"] as ImageTexture
	var img := Image.create(64, 16, false, Image.FORMAT_RGB8)
	for i in 4:
		img.fill_rect(Rect2i(i * 16, 0, 16, 16),
			Color(0.10, 0.25, 0.62) if i % 2 == 0 else Color(0.92, 0.93, 0.95))
	img.fill_rect(Rect2i(0, 0, 64, 1), Color(0.2, 0.2, 0.22))
	img.fill_rect(Rect2i(0, 15, 64, 1), Color(0.2, 0.2, 0.22))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["panel"] = tex
	return tex


## Unbranded hoarding pattern in GREYSCALE (the instance colour tints it): a
## light field, a darker lower band and a bright block -- reads as a sponsor
## board from a distance without a single letter on it.
func _board_texture() -> ImageTexture:
	if _tex_cache.has("board"):
		return _tex_cache["board"] as ImageTexture
	var img := Image.create(64, 16, false, Image.FORMAT_RGB8)
	img.fill(Color(0.95, 0.95, 0.95))
	img.fill_rect(Rect2i(0, 11, 64, 5), Color(0.55, 0.55, 0.55))
	img.fill_rect(Rect2i(4, 3, 18, 6), Color(1.0, 1.0, 1.0))
	img.fill_rect(Rect2i(26, 4, 34, 2), Color(0.7, 0.7, 0.7))
	img.fill_rect(Rect2i(26, 7, 22, 2), Color(0.7, 0.7, 0.7))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["board"] = tex
	return tex


## White countdown board with a dark border and one diagonal bar (no text).
func _countdown_texture() -> ImageTexture:
	if _tex_cache.has("countdown"):
		return _tex_cache["countdown"] as ImageTexture
	var img := Image.create(32, 24, false, Image.FORMAT_RGB8)
	img.fill(Color(0.92, 0.92, 0.90))
	for x in 32:
		for y in 24:
			var border := x < 2 or x > 29 or y < 2 or y > 21
			var bar := absi(x - int(float(y) * 1.33)) < 4
			if border or bar:
				img.set_pixel(x, y, Color(0.08, 0.08, 0.09))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["countdown"] = tex
	return tex


## Chain-link diamonds: 2 px galvanised wire lines on a transparent field, one
## diamond per 32 px (mipmapped, so the fence thins to a haze with distance).
func _chainlink_texture() -> ImageTexture:
	if _tex_cache.has("chainlink"):
		return _tex_cache["chainlink"] as ImageTexture
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 64:
		for x in 64:
			if (x + y) % 32 < 2 or (x - y + 64) % 32 < 2:
				img.set_pixel(x, y, Color(0.75, 0.77, 0.80, 1.0))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["chainlink"] = tex
	return tex


## Rubber streaks along the road (V = along): dark lines of varying strength.
func _skid_texture() -> ImageTexture:
	if _tex_cache.has("skid"):
		return _tex_cache["skid"] as ImageTexture
	var noise := FastNoiseLite.new()
	noise.seed = 4242
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 1.0
	var w := 64
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var fy := float(y) / float(h - 1)
		var along := smoothstep(0.0, 0.15, fy) * (1.0 - smoothstep(0.7, 1.0, fy))
		for x in w:
			var fx := float(x) / float(w - 1)
			var across := smoothstep(0.0, 0.2, fx) * (1.0 - smoothstep(0.8, 1.0, fx))
			var n := noise.get_noise_2d(float(x) * 0.45, float(y) * 0.012) * 0.5 + 0.5
			var n2 := noise.get_noise_2d(float(x) * 0.09 + 50.0, float(y) * 0.03) * 0.5 + 0.5
			var a := smoothstep(0.45, 0.8, n) * (0.55 + 0.45 * n2) * along * across
			img.set_pixel(x, y, Color(0.03, 0.03, 0.035, clampf(a * 0.9, 0.0, 1.0)))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["skid"] = tex
	return tex


## Irregular blob: an oil patch (dark) or a dirt/sand spill (`dirt`).
func _blob_texture(dirt: bool) -> ImageTexture:
	var key := "dirt" if dirt else "oil"
	if _tex_cache.has(key):
		return _tex_cache[key] as ImageTexture
	var noise := FastNoiseLite.new()
	noise.seed = 777 if dirt else 999
	noise.frequency = 0.06
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var p := Vector2(float(x), float(y)) / float(size - 1) * 2.0 - Vector2.ONE
			var n := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var r := p.length() + (n - 0.5) * 0.7
			var a := 1.0 - smoothstep(0.35, 0.95, r)
			if dirt:
				var grain := noise.get_noise_2d(float(x) * 5.0, float(y) * 5.0) * 0.5 + 0.5
				a *= smoothstep(0.25, 0.6, grain + (1.0 - r) * 0.4)
				img.set_pixel(x, y, Color(0.58, 0.50, 0.37, clampf(a, 0.0, 1.0)))
			else:
				img.set_pixel(x, y, Color(0.015, 0.015, 0.02, clampf(a * 0.75, 0.0, 1.0)))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


## ORM for the oil patch: full AO, low roughness (glossy), non-metal.
func _oil_orm_texture() -> ImageTexture:
	if _tex_cache.has("oil_orm"):
		return _tex_cache["oil_orm"] as ImageTexture
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color(1.0, 0.18, 0.0))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["oil_orm"] = tex
	return tex

## --- recording + node emission ---------------------------------------------

func _record(kind: String, t: Transform3D, color: Variant = null) -> void:
	if not _transforms.has(kind):
		_transforms[kind] = []
	(_transforms[kind] as Array).append(t)
	if color != null:
		if not _colors.has(kind):
			_colors[kind] = PackedColorArray()
		var arr: PackedColorArray = _colors[kind]
		arr.append(color as Color)
		_colors[kind] = arr


## Build the MultiMeshInstance3D chunks for a recorded kind: instances are
## bucketed into CHUNK_M x CHUNK_M cells (first-seen order, deterministic) so
## frustum culling works on a 13.6 km lap, each chunk gets the kind's
## visibility range and shadow setting, and per-instance colours when the kind
## recorded them.
func _flush(kind: String) -> void:
	var list := _transforms.get(kind, []) as Array
	var mesh := _meshes.get(kind) as Mesh
	if list.is_empty() or mesh == null:
		if not list.is_empty():
			_dropped.append(kind)
		return
	var colors: PackedColorArray = _colors.get(kind, PackedColorArray()) as PackedColorArray
	var use_colors := colors.size() == list.size()
	var buckets: Dictionary = {}
	var order: Array[Vector2i] = []
	for i in list.size():
		var o: Vector3 = (list[i] as Transform3D).origin
		var cell := Vector2i(floori(o.x / CHUNK_M), floori(o.z / CHUNK_M))
		if not buckets.has(cell):
			buckets[cell] = PackedInt32Array()
			order.append(cell)
		var b: PackedInt32Array = buckets[cell]
		b.append(i)
		buckets[cell] = b
	var vis: float = float(VIS_RANGE.get(kind, 0.0))
	var chunk_i := 0
	for cell in order:
		var ids: PackedInt32Array = buckets[cell]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = use_colors
		mm.mesh = mesh
		mm.instance_count = ids.size()
		for j in ids.size():
			mm.set_instance_transform(j, list[ids[j]] as Transform3D)
			if use_colors:
				mm.set_instance_color(j, colors[ids[j]])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d" % [kind.to_pascal_case(), chunk_i]
		mmi.multimesh = mm
		if vis > 0.0:
			mmi.visibility_range_end = vis
			mmi.visibility_range_end_margin = vis * 0.1
		if NO_SHADOW_KINDS.has(kind):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		chunk_i += 1


## One plain MeshInstance3D for a non-instanced kind (trap / apron ribbons).
func _emit_mesh_node(kind: String) -> void:
	var mesh := _meshes.get(kind) as Mesh
	if mesh == null:
		_dropped.append(kind)
		return
	var mi := MeshInstance3D.new()
	mi.name = kind.to_pascal_case()
	mi.mesh = mesh
	mi.layers = mi.layers | DECAL_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _emit_single(kind: String, mesh: ArrayMesh, t: Transform3D) -> void:
	_meshes[kind] = mesh
	_record(kind, t)
	_flush(kind)


## Rebuild hygiene: drop every child node from a previous build immediately
## (`free()`, not `queue_free()`: a test may rebuild and re-count in one frame).
func _clear_children() -> void:
	for child in get_children():
		child.free()
