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

    # Close the loop
    var closed_points := points.duplicate()
    closed_points.append(points[0])

    # Create visual mesh
    var road_mesh := _build_mesh(closed_points)
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.mesh = road_mesh

    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.25, 0.25, 0.27)
    material.roughness = 0.9
    mesh_instance.material_override = material
    add_child(mesh_instance)

    # Create collision body
    var body := StaticBody3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(road_width, road_height, _path_length(closed_points))
    var collision := CollisionShape3D.new()
    collision.shape = shape
    body.add_child(collision)
    add_child(body)

func _build_mesh(points: Array[Vector3]) -> ArrayMesh:
    ## Builds a triangle strip mesh following the points.
    var vertices := PackedVector3Array()
    var indices := PackedInt32Array()
    var normals := PackedVector3Array()

    # Triangle strip along the path
    for i in range(points.size()):
        var p := points[i]
        var forward := (points[min(i + 1, points.size() - 1)] - points[max(i - 1, 0)]).normalized()
        var right := forward.cross(Vector3.UP).normalized()

        vertices.append(p - right * road_width * 0.5)
        vertices.append(p + right * road_width * 0.5)

        if i < points.size() - 1:
            var base := i * 2
            indices.append(base)
            indices.append(base + 1)
            indices.append(base + 2)
            indices.append(base + 1)
            indices.append(base + 3)
            indices.append(base + 2)

        normals.append(Vector3.UP)
        normals.append(Vector3.UP)

    var mesh := ArrayMesh.new()
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_INDEX] = indices
    arrays[Mesh.ARRAY_NORMAL] = normals
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh

func _path_length(points: Array[Vector3]) -> float:
    var total := 0.0
    for i in range(1, points.size()):
        total += points[i - 1].distance_to(points[i])
    return total
