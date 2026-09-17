class_name TrackBuilder
extends Node3D

## Builds a road from a spline of points.
## Creates visual mesh + collision body for the road surface.

@export var road_width: float = 12.0
@export var road_height: float = 0.1

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
func build_track(points: Array[Vector3], closed: bool = true, def: RoadDef = null) -> void:
    if points.size() < 3:
        return

    var width: float = def.width if def != null else road_width
    var surface: int = def.surface if def != null else RoadDef.Surface.ASPHALT
    var tier: int = def.tier if def != null else RoadDef.Tier.ARTERIAL
    var banking: float = def.banking if def != null else 0.0

    # Create visual mesh
    var road_mesh := _build_mesh(points, false, closed, width, banking)
    var mesh_instance := MeshInstance3D.new()
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
        edge_instance.mesh = edge_mesh
        var edge_material := StandardMaterial3D.new()
        edge_material.albedo_color = edge_colors[e] as Color
        edge_material.roughness = 0.5
        edge_material.cull_mode = BaseMaterial3D.CULL_DISABLED
        edge_instance.material_override = edge_material
        add_child(edge_instance)

    var track_phys_mat := PhysicsMaterial.new()
    track_phys_mat.friction = 0.0

    # Create a single continuous trimesh collision from the exact same
    # vertices as the visual mesh (winding flipped so the front face is up
    # for Jolt). Per-segment boxes left seam sawtooth edges that snagged
    # the chassis (invisible walls / stuck), and a naively duplicated
    # closing point left a non-manifold X-fold with a traction hole right
    # at the respawn point. The strip below closes the loop by sharing the
    # seam vertices, so the surface is flat, gapless, and watertight.
    var body := StaticBody3D.new()
    var coll_mesh := _build_mesh(points, true, closed, width, banking)
    var trimesh_shape: ConcavePolygonShape3D = coll_mesh.create_trimesh_shape()
    var collision := CollisionShape3D.new()
    collision.shape = trimesh_shape
    body.add_child(collision)
    body.physics_material_override = track_phys_mat
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

func _build_mesh(points: Array[Vector3], flip_winding: bool, closed: bool, width: float, banking: float) -> ArrayMesh:
    ## Builds a single triangle-strip mesh following the points. When closed,
    ## the strip wraps around so the last segment connects back to the first
    ## one, sharing the seam vertices (no gap, no fold). When open, the strip
    ## runs to the last point with its tangent clamped at the ends.
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