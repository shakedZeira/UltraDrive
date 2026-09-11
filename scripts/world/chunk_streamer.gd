# scripts/world/chunk_streamer.gd
class_name ChunkStreamer
extends Node

## Streams terrain chunks in/out based on player position.
## Uses OWDB for object streaming; this manages terrain mesh chunks.

@export var chunk_size: float = 256.0
@export var load_radius: int = 2  # chunks around player to load
@export var chunk_scene: PackedScene  # scene to instance per chunk

var _loaded_chunks: Dictionary = {}  # key: "x,z", value: Node

func clear() -> void:
    for chunk in _loaded_chunks.values():
        chunk.queue_free()
    _loaded_chunks.clear()

func set_player_position(player_pos: Vector3) -> void:
    var player_chunk_x := int(floor(player_pos.x / chunk_size))
    var player_chunk_z := int(floor(player_pos.z / chunk_size))

    # Load chunks within radius
    for dx in range(-load_radius, load_radius + 1):
        for dz in range(-load_radius, load_radius + 1):
            var cx := player_chunk_x + dx
            var cz := player_chunk_z + dz
            var key := "%d,%d" % [cx, cz]
            if not _loaded_chunks.has(key):
                _load_chunk(cx, cz)

    # Unload distant chunks
    var to_remove: Array[String] = []
    for key in _loaded_chunks:
        var parts: PackedStringArray = key.split(",")
        var cx := int(parts[0])
        var cz := int(parts[1])
        if abs(cx - player_chunk_x) > load_radius + 1 or abs(cz - player_chunk_z) > load_radius + 1:
            to_remove.append(key)

    for key in to_remove:
        _loaded_chunks[key].queue_free()
        _loaded_chunks.erase(key)

func _load_chunk(cx: int, cz: int) -> void:
    var chunk: Node3D
    if chunk_scene:
        chunk = chunk_scene.instantiate()
    else:
        chunk = _create_flat_chunk()
    chunk.name = "Chunk_%d_%d" % [cx, cz]
    chunk.position = Vector3(cx * chunk_size, 0, cz * chunk_size)
    add_child(chunk)
    _loaded_chunks["%d,%d" % [cx, cz]] = chunk

func _create_flat_chunk() -> Node3D:
    var chunk := Node3D.new()

    var mesh_instance := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(chunk_size, chunk_size)
    plane.subdivide_width = 16
    plane.subdivide_depth = 16
    mesh_instance.mesh = plane
    chunk.add_child(mesh_instance)

    var body := StaticBody3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(chunk_size, 0.1, chunk_size)
    var collision := CollisionShape3D.new()
    collision.shape = shape
    collision.position.y = -0.05
    body.add_child(collision)
    chunk.add_child(body)

    return chunk
