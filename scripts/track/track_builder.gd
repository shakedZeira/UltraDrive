class_name TrackBuilder
extends Node3D

## Builds a road from a spline of points.
## Creates visual mesh + collision body for the road surface.

@export var road_width: float = 12.0
@export var road_height: float = 0.1

const LANE_DIVIDER_WIDTH := 0.18
const LANE_DIVIDER_COLOR := Color(0.90, 0.95, 1.0, 0.55)
const LANE_DASH_LENGTH := 3.0
const LANE_DASH_GAP := 3.0
const LANE_DASH_PERIOD := LANE_DASH_LENGTH + LANE_DASH_GAP
const RAIL_GAP := 0.6
const RAIL_HEIGHT := 0.75
const RAIL_THICKNESS := 0.18
const RAIL_GAP_RADIUS := 25.0

var _track_points: Array[Vector3] = []
var _track_closed := true
var _track_def: RoadDef = null
var _rail_gaps: Array = []  # Array of Dicts {"start": Vector3, "end": Vector3} or legacy Vector3 points
## Explicit per-point bank angles (radians, signed, see RoadDef.bank_angles) for
## the road currently built. build_track sets it ONLY when the def carries
## exactly one angle per point; otherwise it stays EMPTY and _frame falls back to
## the legacy `banking` x curvature math. Because _frame is the single frame
## supplier for the surface strip, the edge/divider meshes, the rails and the
## trimesh collision, this one member upgrades all of them consistently -- and
## configure_rails() rebuilds read the same member.
var _bank_angles := PackedFloat32Array()

## Edge strip colors per RoadDef.Tier key: [accent_edge, outer_edge].
## Out-of-range tiers (and the def == null default) fall back to ARTERIAL.
const TIER_EDGE_COLORS := {
    0: [Color(0.90, 0.90, 0.88), Color(0.90, 0.90, 0.88)],  # HIGHWAY
    1: [Color(0.82, 0.13, 0.13), Color(0.85, 0.85, 0.82)],  # ARTERIAL
    2: [Color(0.15, 0.45, 0.90), Color(0.85, 0.85, 0.82)],  # TOUGE
    3: [Color(0.10, 0.60, 0.75), Color(0.85, 0.85, 0.82)],  # COASTAL
    4: [Color(0.40, 0.29, 0.19), Color(0.30, 0.22, 0.15)],  # DIRT
}

## DIRT-tier road-surface profile (docs/plans/barcelona_dirt_surface_plan.md D1).
## The TIER is the semantic a player reads as "dirt"; the Surface value alone
## cannot carry it, because `RoadDef.default_surface(Tier.DIRT)` IS `GRAVEL` --
## so keying the carriageway look off `surface` alone renders a DIRT road as the
## exact same pale tan as a generic gravel road. A DIRT-tier road therefore gets
## this dark, saturated earth albedo at a fully matte roughness whatever its
## Surface says. Blast radius is DIRT-tier only: HIGHWAY / ARTERIAL / TOUGE /
## COASTAL keep the untouched `surface_albedo` / `surface_roughness` values, so
## every non-DIRT road is unchanged.
const DIRT_ALBEDO := Color(0.34, 0.24, 0.15, 1.0)
const DIRT_ROUGHNESS := 1.0

## Triplanar UV scale for the DIRT-only detail maps (D2). The road mesh carries
## NO UVs (`_build_mesh` emits VERTEX/INDEX/NORMAL only), so a texture map would
## sample at one constant UV and be inert. Triplanar projects the map from world
## position instead, which makes it actually vary without touching the vertex
## format -- and so without touching the collision trimesh or any existing road.
const DIRT_UV_SCALE := Vector3(0.08, 0.08, 0.08)

## Deterministic mottling noise for the DIRT albedo (fixed seed, never RNG), so
## the dirt reads as a mottled surface rather than a solid slab. The colour ramp
## keeps the multiplier in a [0.62, 1.00] band: mottled, never near-black.
const DIRT_NOISE_SEED := 20261017
const DIRT_NOISE_FREQUENCY := 0.35
const DIRT_NOISE_SIZE := 512

## Mixed-surface roads (RoadDef.point_surfaces): one shader blends asphalt and
## loose dirt per vertex row, so a circuit can switch surface mid-lap with a
## believable transition instead of two road meshes.
const MIXED_SURFACE_SHADER := preload("res://shaders/road_mixed_surface.gdshader")
## Dirt dragged onto the asphalt downstream of a loose section (m of arc over
## which the visual loose weight fades out), and the thinner dust lead-in on the
## asphalt before a loose section starts. Visual only: the physics surface
## switches at the profile's hard boundary.
const LOOSE_SPILL_M := 24.0
const LOOSE_LEAD_M := 6.0

## Surface albedo per RoadDef.Surface. ASPHALT is the historical default.
static func surface_albedo(surface: int) -> Color:
    match surface:
        RoadDef.Surface.CONCRETE:
            return Color(0.52, 0.52, 0.53, 1)
        RoadDef.Surface.GRAVEL:
            return Color(0.55, 0.48, 0.38, 1)
        RoadDef.Surface.SNOW:
            return Color(0.92, 0.94, 0.96, 1)
        _:
            return Color(0.16, 0.17, 0.19, 1)

## Surface roughness per RoadDef.Surface. ASPHALT is the historical default.
static func surface_roughness(surface: int) -> float:
    match surface:
        RoadDef.Surface.CONCRETE:
            return 0.85
        RoadDef.Surface.GRAVEL:
            return 0.95
        RoadDef.Surface.SNOW:
            return 0.75
        _:
            return 0.92

## Surface albedo for a road, honouring the DIRT tier overlay (D1). A DIRT-tier
## road is always earth regardless of its Surface (`DIRT_ALBEDO`); every other
## tier defers to `surface_albedo` unchanged.
static func tier_surface_albedo(tier: int, surface: int) -> Color:
    if tier == RoadDef.Tier.DIRT:
        return DIRT_ALBEDO
    return surface_albedo(surface)

## Surface roughness for a road, honouring the DIRT tier overlay (D1). A
## DIRT-tier road is fully matte regardless of its Surface; every other tier
## defers to `surface_roughness` unchanged.
static func tier_surface_roughness(tier: int, surface: int) -> float:
    if tier == RoadDef.Tier.DIRT:
        return DIRT_ROUGHNESS
    return surface_roughness(surface)

## Build track from array of Vector3 points. By default the points are a
## closed loop (the strip wraps back to point 0). Pass closed=false for an
## open-ended road (e.g. the hub->pass connector) so the mesh, edge lines and
## collision strip use plain segment adjacency and never draw a closing strip
## back across the map. An optional RoadDef overrides width, surface material,
## edge tier colors and cross-slope banking; without one the historic defaults
## (ASPHALT material, ARTERIAL red/white edges, flat cross-section) apply.
## rail_gaps: Array of Dicts {"start": Vector3, "end": Vector3} for gap segments,
## or Array[Vector3] for legacy single-point gaps.
func build_track(points: Array[Vector3], closed: bool = true, def: RoadDef = null, rail_gaps: Array = []) -> void:
    if points.size() < 3:
        return

    _track_points = points.duplicate()
    _track_closed = closed
    _track_def = def
    _rail_gaps = rail_gaps.duplicate()

    var width: float = def.width if def != null else road_width
    var surface: int = def.surface if def != null else RoadDef.Surface.ASPHALT
    var tier: int = def.tier if def != null else RoadDef.Tier.ARTERIAL
    var banking: float = def.banking if def != null else 0.0
    var rails_enabled: bool = def.rail_side_count() > 0 if def != null else false

    # Per-point bank profile: honoured only when the def carries EXACTLY one
    # angle per centerline point (a wrong-sized array is ignored and leaves the
    # legacy curvature path byte-identical). _frame reads this member.
    _bank_angles = PackedFloat32Array()
    if def != null and def.bank_angles.size() == points.size():
        _bank_angles = def.bank_angles

    # Mixed-surface profile: honoured only with exactly one entry per point
    # (RoadDef.has_surface_profile); otherwise the road is one uniform surface.
    var loose := PackedFloat32Array()
    var mixed: bool = def != null and def.has_surface_profile()
    if mixed:
        loose = loose_weights(points, def.point_surfaces, closed)

    var road_mesh := _build_mesh(points, closed, width, banking, 0.0, loose)
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = "RoadSurface"
    mesh_instance.mesh = road_mesh

    if mixed:
        mesh_instance.material_override = _mixed_surface_material(width)
    else:
        mesh_instance.material_override = _surface_material(surface, tier)
    add_child(mesh_instance)

    var edge_offsets: Array[float] = [
        width * 0.5 - 0.5,
        -(width * 0.5 - 0.5),
    ]
    var edge_colors: Array = TIER_EDGE_COLORS.get(tier, TIER_EDGE_COLORS[RoadDef.Tier.ARTERIAL])
    # A mixed-surface road paints its own edge lines on the asphalt sections in
    # the shader (a loose section has none), so the 1 m tier strips are skipped.
    for e in range(0 if mixed else edge_offsets.size()):
        var edge_mesh := _build_edge_mesh(points, edge_offsets[e], 1.0, closed, banking)
        var edge_instance := MeshInstance3D.new()
        edge_instance.name = "RoadEdgeRight" if e == 0 else "RoadEdgeLeft"
        edge_instance.mesh = edge_mesh
        var edge_material := StandardMaterial3D.new()
        edge_material.albedo_color = edge_colors[e] as Color
        edge_material.roughness = 0.5
        edge_material.cull_mode = BaseMaterial3D.CULL_DISABLED
        edge_instance.material_override = edge_material
        add_child(edge_instance)

    var lane_count: int = RoadDef.lane_count_for(width)
    if def == null or (def.show_lane_dividers and not mixed):
        for boundary in range(1, lane_count):
            var divider_offset := -width * 0.5 + width * float(boundary) / float(lane_count)
            var divider_mesh := _build_dashed_edge_mesh(points, divider_offset, LANE_DIVIDER_WIDTH, closed, banking)
            var divider_instance := MeshInstance3D.new()
            divider_instance.name = "LaneDivider%d" % (boundary - 1)
            divider_instance.mesh = divider_mesh
            divider_instance.material_override = _lane_divider_material()
            add_child(divider_instance)

    if rails_enabled:
        _build_rails(points, closed, banking, width, rail_gaps, not rail_gaps.is_empty())

    var track_phys_mat := PhysicsMaterial.new()
    track_phys_mat.friction = 0.0

    # Create a single continuous trimesh collision from the exact same
    # triangles as the visual mesh (same vertices, same up-facing winding --
    # Jolt only collides with front faces). Per-segment boxes left seam sawtooth edges that snagged
    # the chassis (invisible walls / stuck), and a naively duplicated
    # closing point left a non-manifold X-fold with a traction hole right
    # at the respawn point. The strip below closes the loop by sharing the
    # seam vertices, so the surface is flat, gapless, and watertight.
    # For open roads, skip degenerate first/last segments (length < 0.5 m)
    # that can create invisible collision walls at the approach.
    var body := StaticBody3D.new()
    body.name = "CollisionBody"
    var coll_mesh := _build_mesh(points, closed, width, banking, 0.5)
    var trimesh_shape: ConcavePolygonShape3D = coll_mesh.create_trimesh_shape()
    var collision := CollisionShape3D.new()
    collision.shape = trimesh_shape
    body.add_child(collision)
    body.physics_material_override = track_phys_mat
    add_child(body)

func configure_rails(gaps: Array) -> void:
    if gaps.is_empty() or _track_points.size() < 3 or _track_def == null:
        return
    if _track_def.rail_side_count() == 0:
        return
    _remove_rail_children()
    _build_rails(_track_points, _track_closed, _track_def.banking, _track_def.width, gaps, true)
    _rail_gaps = gaps.duplicate()

func _remove_rail_children() -> void:
    for child in get_children():
        var child_name := String(child.name)
        if child_name.begins_with("RoadRail") or child_name.begins_with("RailCollision"):
            remove_child(child)
            child.free()

## The per-side rail mask of the road being built. _track_def is assigned by
## build_track (and already live when configure_rails calls back in), so both
## entry points read the SAME mask -- a road that drops one side drops it on the
## initial build and on every later gap recompute.
func _rail_mask() -> int:
    if _track_def == null:
        return RoadDef.RailSide.NONE
    return _track_def.rail_sides_mask()

## Whether slot `index` (0 = RIGHT = the +cross side, 1 = LEFT) is built.
func _rail_slot_enabled(index: int) -> bool:
    return (_rail_mask() & rail_side_bit(index)) != 0

## The mask bit a rail slot corresponds to. Slot order is fixed and matches
## rail_names/rail_offsets below.
static func rail_side_bit(index: int) -> int:
    return RoadDef.RailSide.RIGHT if index == 0 else RoadDef.RailSide.LEFT

## The road's own chain-index suppression ranges for rail slot `index`
## (0 = RIGHT, 1 = LEFT), or [] when it declares none. _track_def is read exactly
## like _rail_mask() reads it, so a range added after the initial build only takes
## effect on the next configure_rails() rebuild.
func _rail_open_ranges_for_slot(index: int) -> Array:
    if _track_def == null:
        return []
    return _track_def.rail_open_ranges_for(rail_side_bit(index))

func _build_rails(points: Array[Vector3], closed: bool, banking: float, width: float, gaps: Array, add_collision: bool) -> void:
    var rail_offsets: Array[float] = [
        width * 0.5 + RAIL_GAP,
        -(width * 0.5 + RAIL_GAP),
    ]
    var rail_names: Array[String] = ["RoadRailRight", "RoadRailLeft"]
    var collision_names: Array[String] = ["RailCollisionRight", "RailCollisionLeft"]
    var rail_material := _rail_material()
    var rail_physics_material := PhysicsMaterial.new()
    rail_physics_material.friction = 0.2
    for edge in range(rail_offsets.size()):
        if not _rail_slot_enabled(edge):
            continue
        # Per-side suppression ranges, in the same chain-index space _rail_open_ranges
        # uses. Empty for every road that has not opted in, so the common path is
        # unchanged. Passed alongside the junction `gaps` (which cut BOTH sides)
        # because these cut only the one side they name.
        var open_ranges := _rail_open_ranges_for_slot(edge)
        var rail_mesh := _build_rail_mesh(points, rail_offsets[edge], closed, banking, gaps, open_ranges)
        var rail_instance := MeshInstance3D.new()
        rail_instance.name = rail_names[edge]
        rail_instance.mesh = rail_mesh
        rail_instance.material_override = rail_material
        add_child(rail_instance)

        if add_collision:
            var body := StaticBody3D.new()
            body.name = collision_names[edge]
            body.physics_material_override = rail_physics_material
            var collision := CollisionShape3D.new()
            collision.shape = rail_mesh.create_trimesh_shape()
            body.add_child(collision)
            add_child(body)

## Mixed asphalt/dirt road material (shaders/road_mixed_surface.gdshader). The
## colours are the SAME constants the uniform materials use, so a mixed road's
## asphalt matches every other asphalt road and its dirt matches a DIRT road.
func _mixed_surface_material(width: float) -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = MIXED_SURFACE_SHADER
    material.set_shader_parameter("half_width", width * 0.5)
    material.set_shader_parameter("asphalt_color", surface_albedo(RoadDef.Surface.ASPHALT))
    material.set_shader_parameter("asphalt_roughness", surface_roughness(RoadDef.Surface.ASPHALT))
    material.set_shader_parameter("dirt_color", DIRT_ALBEDO)
    material.set_shader_parameter("dirt_roughness", DIRT_ROUGHNESS)
    material.set_shader_parameter("gravel_color", surface_albedo(RoadDef.Surface.GRAVEL))
    return material

## True for the RoadDef.Surface values that render (and grip) as LOOSE.
static func is_loose_surface(surface: int) -> bool:
    return surface == RoadDef.Surface.GRAVEL

## Per-point visual loose weight for a mixed-surface road: 1 on every point
## whose segment is loose (`surfaces[i]` = the segment starting at point i),
## 0 on clean asphalt, and on asphalt next to a loose section a fading weight --
## a long dirt spill DOWNSTREAM of a section exit (LOOSE_SPILL_M, the dirt the
## tyres drag onto the tarmac) and a short dust lead-in UPSTREAM of an entry
## (LOOSE_LEAD_M). Pure and deterministic (tests rebuild it). Closed roads wrap.
static func loose_weights(points: Array[Vector3], surfaces: PackedByteArray, closed: bool) -> PackedFloat32Array:
    var n := points.size()
    var out := PackedFloat32Array()
    out.resize(n)
    if n == 0 or surfaces.size() != n:
        return out
    var loose := PackedByteArray()
    loose.resize(n)
    var any := false
    for i in n:
        loose[i] = 1 if is_loose_surface(int(surfaces[i])) else 0
        any = any or loose[i] == 1
    if not any:
        return out
    var passes := 2 * n if closed else n
    # Forward pass: arc distance since the last loose point (spill).
    var since := PackedFloat32Array()
    since.resize(n)
    since.fill(INF)
    var run := INF
    for k in passes:
        var i := k % n
        if loose[i] == 1:
            run = 0.0
        elif k > 0:
            run += points[(i - 1 + n) % n].distance_to(points[i])
        if k >= passes - n:
            since[i] = run
    # Backward pass: arc distance until the next loose point (lead-in).
    var until := PackedFloat32Array()
    until.resize(n)
    until.fill(INF)
    run = INF
    for k in passes:
        var i := n - 1 - (k % n)
        if loose[i] == 1:
            run = 0.0
        elif k > 0:
            run += points[i].distance_to(points[(i + 1) % n])
        if k >= passes - n:
            until[i] = run
    for i in n:
        if loose[i] == 1:
            out[i] = 1.0
            continue
        var spill := pow(clampf(1.0 - since[i] / LOOSE_SPILL_M, 0.0, 1.0), 1.6)
        var lead := pow(clampf(1.0 - until[i] / LOOSE_LEAD_M, 0.0, 1.0), 1.6)
        out[i] = maxf(spill, lead)
    return out

func _surface_material(surface: int, tier: int) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = tier_surface_albedo(tier, surface)
    material.roughness = tier_surface_roughness(tier, surface)
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    var noise := FastNoiseLite.new()
    noise.seed = 1337
    noise.frequency = 0.08
    var roughness_tex := NoiseTexture2D.new()
    roughness_tex.noise = noise
    roughness_tex.width = 512
    roughness_tex.height = 512
    material.roughness_texture = roughness_tex
    material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
    if tier == RoadDef.Tier.DIRT:
        _apply_dirt_surface_detail(material)
    return material

## DIRT-only surface detail (D2): the road mesh has no UVs, so enable triplanar
## projection and attach a deterministic mottling noise as the albedo map. This
## is what turns the dirt carriageway from a flat colour slab into a matte,
## visibly mottled earth surface -- and it is the ONLY reason the 1 m edge strips
## stop being the dominant "dirt" read.
##
## Strictly additive and DIRT-gated: nothing here runs for any other tier, so
## every non-DIRT road's material is byte-for-byte the one it had before.
func _apply_dirt_surface_detail(material: StandardMaterial3D) -> void:
    material.uv1_triplanar = true
    material.uv1_scale = DIRT_UV_SCALE

    var albedo_noise := FastNoiseLite.new()
    albedo_noise.seed = DIRT_NOISE_SEED
    albedo_noise.frequency = DIRT_NOISE_FREQUENCY
    albedo_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
    albedo_noise.fractal_octaves = 4
    var albedo_tex := NoiseTexture2D.new()
    albedo_tex.noise = albedo_noise
    albedo_tex.width = DIRT_NOISE_SIZE
    albedo_tex.height = DIRT_NOISE_SIZE
    var ramp := Gradient.new()
    ramp.offsets = PackedFloat32Array([0.0, 1.0])
    ramp.colors = PackedColorArray([Color(0.62, 0.62, 0.62), Color(1.0, 1.0, 1.0)])
    albedo_tex.color_ramp = ramp
    material.albedo_texture = albedo_tex

func _lane_divider_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = LANE_DIVIDER_COLOR
    material.roughness = 0.65
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.emission_enabled = false
    return material

func _rail_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.32, 0.35, 0.38, 1.0)
    material.roughness = 0.6
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material

## Per-vertex road frame: centerline point, forward tangent and the banked
## cross-section direction. cross is the (right, up) plane rotated about the
## forward axis by the signed curvature-scaled banking angle, so the vertex on
## the inside of a turn sits lower (cross.lift = -sin(angle) along the right
## edge), and banking <= 0 keeps the section flat.
##
## Precedence: when _bank_angles carries one entry per point (RoadDef.bank_angles,
## set by build_track) the angle is taken VERBATIM from the profile and the
## banking/curvature math below is skipped entirely -- so a profile banks a
## straight road and is independent of point spacing. Otherwise the legacy path
## runs, untouched.
func _frame(points: Array[Vector3], i: int, closed: bool, banking: float) -> Dictionary:
    var n := points.size()
    var p := points[i]
    var prev := points[(i - 1 + n) % n] if closed else points[maxi(i - 1, 0)]
    var next := points[(i + 1) % n] if closed else points[mini(i + 1, n - 1)]
    var forward := (next - prev).normalized()
    var right := forward.cross(Vector3.UP).normalized()
    var angle := 0.0
    if _bank_angles.size() > 0:
        angle = float(_bank_angles[i])
    elif banking > 0.0:
        var t1 := (p - prev).normalized()
        var t2 := (next - p).normalized()
        var curvature := -t1.cross(t2).y
        angle += clampf(curvature, -1.0, 1.0) * banking
    return {
        "center": p,
        "forward": forward,
        "cross": right * cos(angle) - Vector3.UP * sin(angle),
    }

## Surface normal of a road frame: perpendicular to both the travel direction
## and the banked cross-section, pointing up (cross x forward; for forward +X,
## cross +Z it is +Y). Follows the bank and the slope instead of a flat UP.
static func _frame_normal(frame: Dictionary) -> Vector3:
    var cross: Vector3 = frame["cross"]
    var forward: Vector3 = frame["forward"]
    var nrm := cross.cross(forward)
    if nrm.length_squared() < 1e-8:
        return Vector3.UP
    nrm = nrm.normalized()
    return nrm if nrm.y >= 0.0 else -nrm

## Appends the two triangles of one strip quad with the FRONT face up.
## (l0, r0) = left/right vertex of the row behind, (l1, r1) = the row ahead.
## Godot's front face is CLOCKWISE seen from the viewer, i.e. seen from above
## `(v1 - v0).cross(v2 - v0).y < 0`. The old visual order (l0, r0, l1) was
## counter-clockwise from above -- the visible top was a BACK face, which the
## cull_disabled materials then shaded with a flipped (downward) normal: the
## near-black road. Visual strips, edge lines, dividers and the trimesh
## collision all use this one order.
static func _append_up_quad(indices: PackedInt32Array, l0: int, r0: int, l1: int, r1: int) -> void:
    indices.append(l1)
    indices.append(r0)
    indices.append(l0)
    indices.append(l1)
    indices.append(r1)
    indices.append(r0)

func _build_mesh(points: Array[Vector3], closed: bool, width: float, banking: float, min_segment_length: float = 0.0, loose: PackedFloat32Array = PackedFloat32Array()) -> ArrayMesh:
    ## Builds a single triangle-strip mesh following the points. When closed,
    ## the strip wraps around so the last segment connects back to the first
    ## one, sharing the seam vertices (no gap, no fold). When open, the strip
    ## runs to the last point with its tangent clamped at the ends.
    ## If min_segment_length > 0, segments shorter than this are skipped
    ## (prevents invisible collision walls from degenerate triangles on open roads).
    ## `loose` (one weight per point, mixed-surface roads only) is written to
    ## COLOR.r, UV.x = -1 / +1 across the road and UV.y = arc length (m) for the
        ## mixed shader.
    var n := points.size()
    var vertices := PackedVector3Array()
    var indices := PackedInt32Array()
    var normals := PackedVector3Array()
    var mixed := loose.size() == n
    var colors := PackedColorArray()
    var uvs := PackedVector2Array()

    # Vertex pair per path point (left / right of the centerline)
    var arc := 0.0
    for i in range(n):
        var frame := _frame(points, i, closed, banking)
        var center: Vector3 = frame["center"]
        if i > 0:
            arc += points[i - 1].distance_to(points[i])
        var cross: Vector3 = frame["cross"]
        var up := _frame_normal(frame)

        vertices.append(center - cross * width * 0.5)
        vertices.append(center + cross * width * 0.5)
        normals.append(up)
        normals.append(up)
        if mixed:
            var c := Color(loose[i], 0.0, 0.0, 1.0)
            colors.append(c)
            colors.append(c)
            uvs.append(Vector2(-1.0, arc))
            uvs.append(Vector2(1.0, arc))

    # Closed quad strip (triangle strip)
    for i in range(n if closed else n - 1):
        var j := (i + 1) % n if closed else i + 1
        if min_segment_length > 0.0 and not closed:
            var seg_len := points[i].distance_to(points[j])
            if seg_len < min_segment_length:
                continue
        var base := i * 2
        var next_base := j * 2
        _append_up_quad(indices, base, base + 1, next_base, next_base + 1)

    var mesh := ArrayMesh.new()
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_INDEX] = indices
    arrays[Mesh.ARRAY_NORMAL] = normals
    if mixed:
        arrays[Mesh.ARRAY_COLOR] = colors
        arrays[Mesh.ARRAY_TEX_UV] = uvs
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh

func _build_dashed_edge_mesh(points: Array[Vector3], offset: float, width: float, closed: bool, banking: float) -> ArrayMesh:
    var n := points.size()
    var vertices := PackedVector3Array()
    var indices := PackedInt32Array()
    var normals := PackedVector3Array()
    var path_distance := 0.0

    for i in range(n if closed else n - 1):
        var j := (i + 1) % n if closed else i + 1
        var a := points[i]
        var b := points[j]
        var segment_length := a.distance_to(b)
        if segment_length <= 0.0001:
            continue
        var frame_a := _frame(points, i, closed, banking)
        var frame_b := _frame(points, j, closed, banking)
        var center_a: Vector3 = frame_a["center"]
        var center_b: Vector3 = frame_b["center"]
        var cross_a: Vector3 = frame_a["cross"]
        var cross_b: Vector3 = frame_b["cross"]
        var cursor := 0.0
        while cursor < segment_length - 0.0001:
            var phase := fposmod(path_distance + cursor, LANE_DASH_PERIOD)
            var boundary_distance := LANE_DASH_PERIOD - phase if phase >= LANE_DASH_LENGTH else LANE_DASH_LENGTH - phase
            var next_cursor := minf(cursor + boundary_distance, segment_length)
            if phase < LANE_DASH_LENGTH and next_cursor > cursor:
                var t0 := cursor / segment_length
                var t1 := next_cursor / segment_length
                var center0 := center_a.lerp(center_b, t0)
                var center1 := center_a.lerp(center_b, t1)
                var cross0 := cross_a.lerp(cross_b, t0).normalized()
                var cross1 := cross_a.lerp(cross_b, t1).normalized()
                var line0 := center0 + Vector3.UP * 0.014 + cross0 * offset
                var line1 := center1 + Vector3.UP * 0.014 + cross1 * offset
                var base := vertices.size()
                vertices.append(line0 - cross0 * width * 0.5)
                vertices.append(line0 + cross0 * width * 0.5)
                vertices.append(line1 - cross1 * width * 0.5)
                vertices.append(line1 + cross1 * width * 0.5)
                var dash_up := _frame_normal({"cross": cross0, "forward": (center1 - center0).normalized()})
                for _v in 4:
                    normals.append(dash_up)
                _append_up_quad(indices, base, base + 1, base + 2, base + 3)
            if next_cursor <= cursor:
                cursor += 0.0001
            else:
                cursor = next_cursor
        path_distance += segment_length

    var mesh := ArrayMesh.new()
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_INDEX] = indices
    arrays[Mesh.ARRAY_NORMAL] = normals
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh

func _build_rail_mesh(points: Array[Vector3], offset: float, closed: bool, banking: float, rail_gaps: Array = [], open_ranges: Array = []) -> ArrayMesh:
    var n := points.size()
    var vertices := PackedVector3Array()
    var indices := PackedInt32Array()
    var normals := PackedVector3Array()
    var arc_distances := PackedFloat32Array()
    arc_distances.resize(n)
    var total_distance := 0.0
    for i in range(n):
        arc_distances[i] = total_distance
        if closed:
            total_distance += points[i].distance_to(points[(i + 1) % n])
        elif i + 1 < n:
            total_distance += points[i].distance_to(points[i + 1])
    
    # Parse gaps into segments: each gap is either a legacy Vector3 (single point)
    # or a Dict with "start" and "end" keys (gap segment).
    # Convert to arc distance ranges [start_dist, end_dist] along the road.
    var gap_ranges: Array = []
    for gap in rail_gaps:
        if gap is Dictionary and gap.has("start") and gap.has("end"):
            # Gap segment: find arc distances for start and end points
            var start_dist := _find_nearest_arc_distance(points, arc_distances, total_distance, gap["start"], closed)
            var end_dist := _find_nearest_arc_distance(points, arc_distances, total_distance, gap["end"], closed)
            # Ensure start <= end (handle wrap-around for closed loops)
            if closed and end_dist < start_dist:
                end_dist += total_distance
            gap_ranges.append([start_dist, end_dist])
        elif gap is Vector3:
            # Legacy single-point gap: use radius around the point
            var gap_dist := _find_nearest_arc_distance(points, arc_distances, total_distance, gap, closed)
            gap_ranges.append([gap_dist - RAIL_GAP_RADIUS, gap_dist + RAIL_GAP_RADIUS])
    
    # Per-side open ranges arrive as chain-index [from, to] pairs. Convert them to
    # the same arc-distance space as the junction gaps so ONE skip test serves both.
    # The range spans [arc[from], arc[to]] plus the segment that STARTS at `to`,
    # matching the inclusive-end behaviour of the junction gaps above.
    for r in open_ranges:
        var from_i: int = clampi(int(r[0]), 0, n - 1)
        var to_i: int = clampi(int(r[1]), 0, n - 1)
        if to_i < from_i:
            var swap := from_i
            from_i = to_i
            to_i = swap
        var start_d: float = arc_distances[from_i]
        var end_d: float = arc_distances[to_i]
        if closed and to_i == 0 and from_i > 0:
            end_d += total_distance
        elif to_i < n - 1:
            end_d = (arc_distances[to_i] + arc_distances[to_i + 1]) * 0.5
        else:
            end_d = total_distance
        gap_ranges.append([start_d, end_d])
    
    for i in range(n):
        var frame := _frame(points, i, closed, banking)
        var center: Vector3 = frame["center"]
        var forward: Vector3 = frame["forward"]
        var cross: Vector3 = frame["cross"]
        var lateral := Vector3.UP.cross(forward).normalized()
        if lateral.length_squared() < 0.0001:
            lateral = cross
        var rail_center := center + cross * offset
        var half_thickness := lateral * RAIL_THICKNESS * 0.5
        var bottom := rail_center
        var top := rail_center + Vector3.UP * RAIL_HEIGHT
        var inner_normal := (-lateral + Vector3.UP).normalized()
        var outer_normal := (lateral + Vector3.UP).normalized()
        vertices.append(bottom - half_thickness)
        vertices.append(bottom + half_thickness)
        vertices.append(top - half_thickness)
        vertices.append(top + half_thickness)
        normals.append(inner_normal)
        normals.append(outer_normal)
        normals.append(inner_normal)
        normals.append(outer_normal)

    for i in range(n if closed else n - 1):
        var j := (i + 1) % n if closed else i + 1
        var skip := false
        var seg_start_dist := arc_distances[i]
        var seg_end_dist := arc_distances[j]
        # Handle wrap-around for closed loops
        if closed and j == 0:
            seg_end_dist += total_distance
        
        for range in gap_ranges:
            var range_start: float = range[0]
            var range_end: float = range[1]
            # Check if segment [seg_start_dist, seg_end_dist] overlaps with gap range.
            # Use INCLUSIVE end check (seg_start_dist <= range_end) so the segment
            # STARTING at the gap's end point (the junction) IS gapped.
            if seg_end_dist >= range_start and seg_start_dist <= range_end:
                skip = true
                break
        if skip:
            continue
        var base := i * 4
        var next_base := j * 4
        indices.append(base)
        indices.append(base + 2)
        indices.append(next_base)
        indices.append(next_base)
        indices.append(base + 2)
        indices.append(next_base + 2)
        indices.append(base + 1)
        indices.append(next_base + 1)
        indices.append(base + 3)
        indices.append(next_base + 1)
        indices.append(next_base + 3)
        indices.append(base + 3)
        indices.append(base + 2)
        indices.append(next_base + 3)
        indices.append(next_base + 2)
        indices.append(next_base + 3)
        indices.append(base + 3)
        indices.append(next_base + 2)

    var mesh := ArrayMesh.new()
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_INDEX] = indices
    arrays[Mesh.ARRAY_NORMAL] = normals
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh


func _find_nearest_arc_distance(points: Array[Vector3], arc_distances: PackedFloat32Array, total_distance: float, target: Vector3, closed: bool) -> float:
    var nearest_index := 0
    var nearest_distance := INF
    for i in range(points.size()):
        var distance := points[i].distance_squared_to(target)
        if distance < nearest_distance:
            nearest_distance = distance
            nearest_index = i
    return arc_distances[nearest_index]


func _build_edge_mesh(points: Array[Vector3], offset: float, width: float, closed: bool, banking: float) -> ArrayMesh:
    var n := points.size()
    var vertices := PackedVector3Array()
    var indices := PackedInt32Array()
    var normals := PackedVector3Array()

    for i in range(n):
        var frame := _frame(points, i, closed, banking)
        var center: Vector3 = frame["center"]
        var cross: Vector3 = frame["cross"]
        var line_center := center + Vector3.UP * 0.012 + cross * offset
        var up := _frame_normal(frame)

        vertices.append(line_center - cross * width * 0.5)
        vertices.append(line_center + cross * width * 0.5)
        normals.append(up)
        normals.append(up)

    for i in range(n if closed else n - 1):
        var j := (i + 1) % n if closed else i + 1
        _append_up_quad(indices, i * 2, i * 2 + 1, j * 2, j * 2 + 1)

    var mesh := ArrayMesh.new()
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_INDEX] = indices
    arrays[Mesh.ARRAY_NORMAL] = normals
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh
