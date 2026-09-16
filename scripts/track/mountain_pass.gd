extends Node3D

## Winding mountain-pass circuit: a climbing loop with tightening hairpins,
## built the same way as the test circuit (TrackBuilder + Checkpoint set).

## The terrain no longer sits far below the circuit as a flat plane. Instead a
## Terrain3D heightmap conforms to the road: every road point is carved into a
## shallow "washbed" UNDER the asphalt (WASHBED_DEPTH, kept between 0.4 and
## 0.8 m) so wheels always find reachable ground while no segment gets buried.
## The recess blends out through a shoulder into gentle rolling hills.
const WASHBED_DEPTH := 0.6

## The washbed floor blends up to the hill field between these distances (m)
## from the road centerline. SHOULDER_DISTANCE exceeds half the road width so
## the whole 11 m road strip stays over the recessed floor.
const SHOULDER_DISTANCE := 8.0
const BLEND_END_DISTANCE := 40.0

## Heightmap spans TERRAIN_SPAN metres at 1 m/pixel (1024 * 1024 image,
## region size 512). import_images() snaps its position to a region anchor
## (multiple of 512), so the pane must start exactly on one: -512 keeps the
## road loop (x/z reach about ±80 m) plus its blend skirt centred on the
## origin while covering regions -1..0 rather than straddling a gap.
const TERRAIN_SPAN := 1024.0
const TERRAIN_HALF := 512.0

## The road distance field is sampled once on this coarse grid; per-pixel the
## field only routes the bake to either the exact road scan or the hill field.
const FIELD_STEP := 8.0

## Coarse-field distance error absorbed before switching from the exact
## per-pixel road scan to the free hill field (see _terrain_height).
const EXACT_SCAN_MARGIN := 16.0

const GRASS_COLOR := Color(0.30, 0.36, 0.27)

## Centerline points used to build the road (exposed for tests).
var road_points: Array[Vector3] = []

## Export gates. Defaults keep the standalone scene (and its tests) behaving
## exactly as before; the open world's lean MountainPassZone turns all three
## off because the world already owns its ground, foliage and player spawn.
@export var build_own_ground: bool = true
@export var build_foliage: bool = true
@export var reposition_player: bool = true


func _ready() -> void:
	road_points = _generate_road_points()
	var terrain: Terrain3D = null
	if build_own_ground:
		terrain = _build_conforming_ground(road_points)

	var builder := TrackBuilder.new()
	builder.road_width = 11.0
	add_child(builder)
	builder.build_track(road_points)

	if build_foliage:
		var foliage := Foliage.new()
		foliage.radius = 150.0
		foliage.inner_clear_radius = 92.0
		foliage.ground_height_provider = _make_ground_height_provider(terrain)
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

	if reposition_player:
		_reposition_player_to_start(road_points)


## Keeps foliage grounded on the new terrain. The provider is handed to the
## Foliage node as a callable so grass/trees settle on the real surface.
func _make_ground_height_provider(terrain: Terrain3D) -> Callable:
	return func ground_height_at(pos: Vector2) -> float:
		return terrain.data.get_height(Vector3(pos.x, 0.0, pos.y))


## Builds the terrain under the circuit. The node keeps the historical
## "GrassGround" name so scenes/tests that look it up still find it, but it is
## now a Terrain3D (collidable heightmap) instead of a visual-only plane.
func _build_conforming_ground(points: Array[Vector3]) -> Terrain3D:
	var terrain := Terrain3D.new()
	terrain.name = "GrassGround"
	add_child(terrain)
	terrain.region_size = Terrain3D.SIZE_512

	var field := _build_distance_field(points)
	var stride := int(TERRAIN_SPAN / FIELD_STEP) + 1
	var size := int(TERRAIN_SPAN)
	var height_img := Image.create_empty(size, size, false, Image.FORMAT_RF)
	var color_img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for iz in range(size):
		var wz := -TERRAIN_HALF + float(iz)
		for ix in range(size):
			var wx := -TERRAIN_HALF + float(ix)
			var elevation := _terrain_height(field, stride, wx, wz)
			height_img.set_pixel(ix, iz, Color(elevation, 0.0, 0.0, 0.0))
			var shade := 0.82 + 0.36 * clampf((elevation + 12.0) / 24.0, 0.0, 1.0)
			color_img.set_pixel(ix, iz, Color(GRASS_COLOR * shade, 0.5))

	terrain.data.import_images(
		[height_img, null, color_img],
		Vector3(-TERRAIN_HALF, 0, -TERRAIN_HALF),
		0.0, 1.0)
	terrain.material.show_checkered = false
	terrain.material.show_colormap = true
	return terrain


## Samples horizontal distance to the nearest road segment on a coarse grid.
## This field is only a routing hint: pixels close to the road re-scan exactly.
func _build_distance_field(points: Array[Vector3]) -> PackedFloat32Array:
	var stride := int(TERRAIN_SPAN / FIELD_STEP) + 1
	var dist := PackedFloat32Array()
	dist.resize(stride * stride)
	for i in stride:
		var wz := -TERRAIN_HALF + float(i) * FIELD_STEP
		for j in stride:
			var wx := -TERRAIN_HALF + float(j) * FIELD_STEP
			dist[i * stride + j] = sqrt(_nearest_road(points, wx, wz).x)
	return dist


## Distance² to the nearest road segment and the interpolated road elevation
## at that closest point (x = dist², y = elevation).
func _nearest_road(points: Array[Vector3], wx: float, wz: float) -> Vector2:
	var best_d2 := INF
	var best_e := 0.0
	for s in points.size():
		var a: Vector3 = points[s]
		var b: Vector3 = points[(s + 1) % points.size()]
		var abx := b.x - a.x
		var abz := b.z - a.z
		var len2 := abx * abx + abz * abz
		if len2 <= 0.0001:
			continue
		var t := clampf(((wx - a.x) * abx + (wz - a.z) * abz) / len2, 0.0, 1.0)
		var cx := a.x + abx * t
		var cz := a.z + abz * t
		var dx := wx - cx
		var dz := wz - cz
		var d2 := dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best_e = a.y + (b.y - a.y) * t
	return Vector2(best_d2, best_e)


## Bilinearly samples the coarse distance field at a world position.
func _distance_field_at(field: PackedFloat32Array, stride: int, wx: float, wz: float) -> float:
	var fx := (wx + TERRAIN_HALF) / FIELD_STEP
	var fz := (wz + TERRAIN_HALF) / FIELD_STEP
	var j0 := clampi(int(floorf(fx)), 0, stride - 1)
	var i0 := clampi(int(floorf(fz)), 0, stride - 1)
	var j1 := mini(j0 + 1, stride - 1)
	var i1 := mini(i0 + 1, stride - 1)
	var tx := clampf(fx - floorf(fx), 0.0, 1.0)
	var tz := clampf(fz - floorf(fz), 0.0, 1.0)
	var a00 := i0 * stride + j0
	var a10 := i0 * stride + j1
	var a01 := i1 * stride + j0
	var a11 := i1 * stride + j1
	return lerpf(lerpf(field[a00], field[a10], tx), lerpf(field[a01], field[a11], tx), tz)


## Gentle rolling-country backdrop used beyond the road's shoulder blend.
func _hill_height(wx: float, wz: float) -> float:
	return (2.5 * sin(wx * 0.045 + 1.7) * cos(wz * 0.038 - 0.9)
		+ 1.0 * sin(wx * 0.087 + 0.3) * sin(wz * 0.11 + 2.1)
		+ 0.5 * cos(wx * 0.13 - wz * 0.09))


## Final terrain elevation at a world position: a recessed floor under the road
## (road elevation minus WASHBED_DEPTH) blending into rolling hills across the
## shoulder. Near the road the nearest-segment scan repeats exactly so the
## washbed hugs the asphalt; far away the coarse field routes to the hills.
func _terrain_height(field: PackedFloat32Array, stride: int, wx: float, wz: float) -> float:
	if _distance_field_at(field, stride, wx, wz) > BLEND_END_DISTANCE + EXACT_SCAN_MARGIN:
		return _hill_height(wx, wz)
	var nearest := _nearest_road(road_points, wx, wz)
	var hill_distance := sqrt(nearest.x)
	var road_elevation := nearest.y
	var blend := smoothstep(SHOULDER_DISTANCE, BLEND_END_DISTANCE, hill_distance)
	return lerpf(road_elevation - WASHBED_DEPTH, _hill_height(wx, wz), blend)


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