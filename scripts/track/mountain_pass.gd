extends Node3D

## Winding mountain-pass circuit: a climbing loop with tightening hairpins,
## built the same way as the test circuit (TrackBuilder + Checkpoint set).

## Vertical clearance kept between the lowest road surface point and the
## terrain floor, so no road segment is buried underneath the ground.
const GROUND_CLEARANCE := 2.0

## Centerline points used to build the road (exposed for tests).
var road_points: Array[Vector3] = []

func _ready() -> void:
	road_points = _generate_road_points()
	var floor_y := road_points[0].y
	for p: Vector3 in road_points:
		floor_y = minf(floor_y, p.y)
	floor_y -= GROUND_CLEARANCE

	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(420, 420)
	var ground_instance := MeshInstance3D.new()
	ground_instance.name = "GrassGround"
	ground_instance.mesh = ground_mesh
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.30, 0.36, 0.27)
	ground_material.roughness = 1.0
	var grass_roughness := _make_noise_texture(77, 0.05)
	ground_material.roughness_texture = grass_roughness
	ground_material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	ground_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ground_instance.material_override = ground_material
	ground_instance.position = Vector3(0, floor_y, 0)
	add_child(ground_instance)

	var builder := TrackBuilder.new()
	builder.road_width = 11.0
	add_child(builder)
	builder.build_track(road_points)

	var foliage := Foliage.new()
	foliage.radius = 150.0
	foliage.inner_clear_radius = 92.0
	add_child(foliage)

	var checkpoint_count := 8
	var step := road_points.size() / checkpoint_count
	for i in range(checkpoint_count):
		var point := road_points[i * step]
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

	_reposition_player_to_start(road_points)

func _generate_road_points() -> Array[Vector3]:
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
	return points

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