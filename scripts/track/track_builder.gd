class_name TrackBuilder
extends Node3D

## Builds a road from a spline of points.
## Creates visual mesh + collision body for the road surface.

@export var road_width: float = 12.0
@export var road_height: float = 0.1

## Build track from array of Vector3 points (closed loop).
func build_track(points: Array[Vector3]) -> void:
    if points.size() < 3:
        return

    # Create visual mesh
    var road_mesh := _build_mesh(points, false)
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.mesh = road_mesh

    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.45, 0.45, 0.48)
    material.roughness = 0.9
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    mesh_instance.material_override = material
    add_child(mesh_instance)

    var edge_offsets: Array[float] = [
        road_width * 0.5 - 0.5,
        -(road_width * 0.5 - 0.5),
    ]
    var edge_colors: Array[Color] = [
        Color(0.72, 0.12, 0.12),
        Color(0.85, 0.85, 0.82),
    ]
    for e in range(edge_offsets.size()):
        var edge_mesh := _build_edge_mesh(points, edge_offsets[e], 1.0)
        var edge_instance := MeshInstance3D.new()
        edge_instance.mesh = edge_mesh
        var edge_material := StandardMaterial3D.new()
        edge_material.albedo_color = edge_colors[e]
        edge_material.roughness = 0.7
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
    var coll_mesh := _build_mesh(points, true)
    var trimesh_shape: ConcavePolygonShape3D = coll_mesh.create_trimesh_shape()
    var collision := CollisionShape3D.new()
    collision.shape = trimesh_shape
    body.add_child(collision)
    body.physics_material_override = track_phys_mat
    add_child(body)

func _build_mesh(points: Array[Vector3], flip_winding: bool) -> ArrayMesh:
    ## Builds a single closed triangle-strip mesh following the points.
    ## The strip wraps around so the last segment connects back to the
    ## first one, sharing the seam vertices (no gap, no fold).
    var n := points.size()
    var vertices := PackedVector3Array()
    var indices := PackedInt32Array()
    var normals := PackedVector3Array()

    # Vertex pair per path point (left / right of the centerline)
    for i in range(n):
        var p := points[i]
        var prev := points[(i - 1 + n) % n]
        var next := points[(i + 1) % n]
        var forward := (next - prev).normalized()
        var right := forward.cross(Vector3.UP).normalized()

        vertices.append(p - right * road_width * 0.5)
        vertices.append(p + right * road_width * 0.5)
        normals.append(Vector3.UP)
        normals.append(Vector3.UP)

    # Closed quad strip (triangle strip)
    for i in range(n):
        var j := (i + 1) % n
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

func _build_edge_mesh(points: Array[Vector3], offset: float, width: float) -> ArrayMesh:
    var n := points.size()
    var vertices := PackedVector3Array()
    var indices := PackedInt32Array()
    var normals := PackedVector3Array()

    for i in range(n):
        var p := points[i]
        var prev := points[(i - 1 + n) % n]
        var next := points[(i + 1) % n]
        var forward := (next - prev).normalized()
        var right := forward.cross(Vector3.UP).normalized()
        var center := p + Vector3.UP * 0.012 + right * offset

        vertices.append(center - right * width * 0.5)
        vertices.append(center + right * width * 0.5)
        normals.append(Vector3.UP)
        normals.append(Vector3.UP)

    for i in range(n):
        var j := (i + 1) % n
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
