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

## Edge strip colors per RoadDef.Tier key: [accent_edge, outer_edge].
## Out-of-range tiers (and the def == null default) fall back to ARTERIAL.
const TIER_EDGE_COLORS := {
    0: [Color(0.90, 0.90, 0.88), Color(0.90, 0.90, 0.88)],  # HIGHWAY
    1: [Color(0.82, 0.13, 0.13), Color(0.85, 0.85, 0.82)],  # ARTERIAL
    2: [Color(0.15, 0.45, 0.90), Color(0.85, 0.85, 0.82)],  # TOUGE
    3: [Color(0.10, 0.60, 0.75), Color(0.85, 0.85, 0.82)],  # COASTAL
    4: [Color(0.55, 0.40, 0.28), Color(0.60, 0.55, 0.48)],  # DIRT
}

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
    var rails_enabled: bool = def.rails_enabled() if def != null else false

    var road_mesh := _build_mesh(points, false, closed, width, banking, 0.0)
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = "RoadSurface"
    mesh_instance.mesh = road_mesh

    var material := _surface_material(surface)
    mesh_instance.material_override = material
    add_child(mesh_instance)

    var edge_offsets: Array[float] = [
        width * 0.5 - 0.5,
        -(width * 0.5 - 0.5),
    ]
    var edge_colors: Array = TIER_EDGE_COLORS.get(tier, TIER_EDGE_COLORS[RoadDef.Tier.ARTERIAL])
    for e in range(edge_offsets.size()):
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
    # vertices as the visual mesh (winding flipped so the front face is up
    # for Jolt). Per-segment boxes left seam sawtooth edges that snagged
    # the chassis (invisible walls / stuck), and a naively duplicated
    # closing point left a non-manifold X-fold with a traction hole right
    # at the respawn point. The strip below closes the loop by sharing the
    # seam vertices, so the surface is flat, gapless, and watertight.
    # For open roads, skip degenerate first/last segments (length < 0.5 m)
    # that can create invisible collision walls at the approach.
    var body := StaticBody3D.new()
    body.name = "CollisionBody"
    var coll_mesh := _build_mesh(points, true, closed, width, banking, 0.5)
    var trimesh_shape: ConcavePolygonShape3D = coll_mesh.create_trimesh_shape()
    var collision := CollisionShape3D.new()
    collision.shape = trimesh_shape
    body.add_child(collision)
    body.physics_material_override = track_phys_mat
    add_child(body)

func configure_rails(gaps: Array) -> void:
    if gaps.is_empty() or _track_points.size() < 3 or _track_def == null:
        return
    if not _track_def.rails_enabled():
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
        var rail_mesh := _build_rail_mesh(points, rail_offsets[edge], closed, banking, gaps)
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

func _surface_material(surface: int) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = surface_albedo(surface)
    material.roughness = surface_roughness(surface)
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
    return material

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
func _frame(points: Array[Vector3], i: int, closed: bool, banking: float) -> Dictionary:
    var n := points.size()
    var p := points[i]
    var prev := points[(i - 1 + n) % n] if closed else points[maxi(i - 1, 0)]
    var next := points[(i + 1) % n] if closed else points[mini(i + 1, n - 1)]
    var forward := (next - prev).normalized()
    var right := forward.cross(Vector3.UP).normalized()
    var angle := 0.0
    if banking > 0.0:
        var t1 := (p - prev).normalized()
        var t2 := (next - p).normalized()
        var curvature := -t1.cross(t2).y
        angle += clampf(curvature, -1.0, 1.0) * banking
    return {
        "center": p,
        "forward": forward,
        "cross": right * cos(angle) - Vector3.UP * sin(angle),
    }

func _build_mesh(points: Array[Vector3], flip_winding: bool, closed: bool, width: float, banking: float, min_segment_length: float = 0.0) -> ArrayMesh:
    ## Builds a single triangle-strip mesh following the points. When closed,
    ## the strip wraps around so the last segment connects back to the first
    ## one, sharing the seam vertices (no gap, no fold). When open, the strip
    ## runs to the last point with its tangent clamped at the ends.
    ## If min_segment_length > 0, segments shorter than this are skipped
    ## (prevents invisible collision walls from degenerate triangles on open roads).
    var n := points.size()
    var vertices := PackedVector3Array()
    var indices := PackedInt32Array()
    var normals := PackedVector3Array()

    # Vertex pair per path point (left / right of the centerline)
    for i in range(n):
        var frame := _frame(points, i, closed, banking)
        var center: Vector3 = frame["center"]
        var cross: Vector3 = frame["cross"]

        vertices.append(center - cross * width * 0.5)
        vertices.append(center + cross * width * 0.5)
        normals.append(Vector3.UP)
        normals.append(Vector3.UP)

    # Closed quad strip (triangle strip)
    for i in range(n if closed else n - 1):
        var j := (i + 1) % n if closed else i + 1
        if min_segment_length > 0.0 and not closed:
            var seg_len := points[i].distance_to(points[j])
            if seg_len < min_segment_length:
                continue
        var base := i * 2
        var next_base := j * 2
        if flip_winding:
            indices.append(next_base)
            indices.append(base + 1)
            indices.append(base)
            indices.append(next_base)
            indices.append(next_base + 1)
            indices.append(base + 1)
        else:
            indices.append(base)
            indices.append(base + 1)
            indices.append(next_base)
            indices.append(base + 1)
            indices.append(next_base + 1)
            indices.append(next_base)

    var mesh := ArrayMesh.new()
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_INDEX] = indices
    arrays[Mesh.ARRAY_NORMAL] = normals
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
                normals.append(Vector3.UP)
                normals.append(Vector3.UP)
                normals.append(Vector3.UP)
                normals.append(Vector3.UP)
                indices.append(base)
                indices.append(base + 1)
                indices.append(base + 2)
                indices.append(base + 1)
                indices.append(base + 3)
                indices.append(base + 2)
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

func _build_rail_mesh(points: Array[Vector3], offset: float, closed: bool, banking: float, rail_gaps: Array = []) -> ArrayMesh:
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

        vertices.append(line_center - cross * width * 0.5)
        vertices.append(line_center + cross * width * 0.5)
        normals.append(Vector3.UP)
        normals.append(Vector3.UP)

    for i in range(n if closed else n - 1):
        var j := (i + 1) % n if closed else i + 1
        var base := i * 2
        var next_base := j * 2
        indices.append(base)
        indices.append(base + 1)
        indices.append(next_base)
        indices.append(base + 1)
        indices.append(next_base + 1)
        indices.append(next_base)

    var mesh := ArrayMesh.new()
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_INDEX] = indices
    arrays[Mesh.ARRAY_NORMAL] = normals
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh