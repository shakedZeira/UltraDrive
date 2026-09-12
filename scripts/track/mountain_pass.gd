extends Node3D

## Winding mountain-pass circuit: a climbing loop with tightening hairpins,
## built the same way as the test circuit (TrackBuilder + Checkpoint set).

func _ready() -> void:
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(420, 420)
	var ground_instance := MeshInstance3D.new()
	ground_instance.mesh = ground_mesh
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.30, 0.36, 0.27)
	ground_material.roughness = 1.0
	var grass_roughness := _make_noise_texture(77, 0.05)
	ground_material.roughness_texture = grass_roughness
	ground_material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	ground_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ground_instance.material_override = ground_material
	ground_instance.position = Vector3(0, -3, 0)
	add_child(ground_instance)

	var builder := TrackBuilder.new()
	builder.road_width = 11.0
	add_child(builder)

	var points: Array[Vector3] = []
	var segments := 36
	for i in range(segments):
		var t := float(i) / segments
		var angle := TAU * t
		var radius := 54.0 + 24.0 * sin(angle * 2.0 + 0.7)
		var x := cos(angle) * radius
		var z := sin(angle) * radius * 0.8
		var y := 8.0 * sin(angle + 1.4) + 3.0 * sin(angle * 3.0)
		points.append(Vector3(x, y, z))
	builder.build_track(points)

	var foliage := Foliage.new()
	foliage.radius = 150.0
	foliage.inner_clear_radius = 92.0
	add_child(foliage)

	var checkpoint_count := 8
	var step := segments / checkpoint_count
	for i in range(checkpoint_count):
		var point := points[i * step]
		var cp := Checkpoint.new()
		cp.index = i
		cp.position = point + Vector3(0, 0.5, 0)
		var area_shape := BoxShape3D.new()
		area_shape.size = Vector3(10.0, 6.0, 10.0)
		var area_col := CollisionShape3D.new()
		area_col.shape = area_shape
		cp.add_child(area_col)
		cp.body_entered.connect(_on_checkpoint_body_entered.bind(cp.index))
		add_child(cp)

	_reposition_player_to_start(points)

func _reposition_player_to_start(points: Array[Vector3]) -> void:
	var player := get_node_or_null("%PlayerCar") as Node3D
	if player != null:
		var start := points[0] + Vector3(0, 1.0, 0)
		player.global_position = start
		player.global_rotation = Vector3.ZERO

func _on_checkpoint_body_entered(body: Node3D, index: int) -> void:
	if body is VehiclePhysics:
		print("[Track] Mountain Pass checkpoint %d passed by %s" % [index, body.name])

func _make_noise_texture(noise_seed: int, frequency: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = frequency
	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.width = 512
	texture.height = 512
	return texture