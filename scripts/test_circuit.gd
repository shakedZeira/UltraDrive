extends Node3D

func _ready() -> void:
    # Add a large ground plane for visual contrast under the track
    var ground_mesh := PlaneMesh.new()
    ground_mesh.size = Vector2(300, 300)
    var ground_instance := MeshInstance3D.new()
    ground_instance.mesh = ground_mesh
    var ground_material := StandardMaterial3D.new()
    ground_material.albedo_color = Color(0.24, 0.34, 0.19)
    ground_material.roughness = 1.0

    # PBR grass look: noise-driven roughness variation plus a subtle bumpy
    # normal map so the plain stays variegated instead of a flat green void.
    var grass_roughness := _make_noise_texture(99, 0.05)
    ground_material.roughness_texture = grass_roughness
    ground_material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED

    var grass_normal := _make_noise_texture(101, 0.08)
    grass_normal.as_normal_map = true
    grass_normal.bump_strength = 0.5
    ground_material.normal_enabled = true
    ground_material.normal_texture = grass_normal
    ground_material.normal_scale = 0.15

    ground_material.cull_mode = BaseMaterial3D.CULL_DISABLED
    ground_instance.material_override = ground_material
    ground_instance.position = Vector3(0, 0, 0)
    add_child(ground_instance)

    # Build an oval track
    var builder := TrackBuilder.new()
    builder.road_width = 12.0
    add_child(builder)

    var points: Array[Vector3] = []
    var radius := 60.0
    var segments := 32
    for i in range(segments):
        var angle := TAU * i / segments
        points.append(Vector3(cos(angle) * radius, 0.1, sin(angle) * radius * 0.6))
    builder.build_track(points)

    # Scatter countryside foliage (grass tufts + low-poly trees) around the oval
    var foliage := Foliage.new()
    add_child(foliage)

    # Add checkpoints around the track
    for i in range(8):
        var angle := TAU * i / 8
        var cp := Checkpoint.new()
        cp.index = i
        cp.position = Vector3(cos(angle) * radius, 0.5, sin(angle) * radius * 0.6)

        # Give the checkpoint a detection volume (Checkpoint Area3D has no shape by default)
        var area_shape := BoxShape3D.new()
        area_shape.size = Vector3(8.0, 5.0, 8.0)
        var area_col := CollisionShape3D.new()
        area_col.shape = area_shape
        cp.add_child(area_col)

        cp.body_entered.connect(_on_checkpoint_body_entered.bind(cp.index))
        add_child(cp)

func _on_checkpoint_body_entered(body: Node3D, index: int) -> void:
    if body is VehiclePhysics:
        print("[Track] Checkpoint %d passed by %s" % [index, body.name])

func _make_noise_texture(noise_seed: int, frequency: float) -> NoiseTexture2D:
    var noise := FastNoiseLite.new()
    noise.seed = noise_seed
    noise.frequency = frequency
    var texture := NoiseTexture2D.new()
    texture.noise = noise
    texture.width = 512
    texture.height = 512
    return texture
