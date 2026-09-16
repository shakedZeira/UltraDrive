# tests/test_terrain_baker.gd
extends GdUnitTestSuite

const IMAGE_WIDTH := 1024
const REGION_SIZE := 1024.0
const LOOP_CENTER := Vector2(3800.0, 3200.0)

func _bake(region: Vector2i, roads: Array = []) -> Image:
	return TerrainBaker.new().bake_region(region, 1.0, IMAGE_WIDTH, roads)

func _height_at(img: Image, region: Vector2i, wx: float, wz: float) -> float:
	var step := REGION_SIZE / float(img.get_width())
	var origin := Vector2(region.x * REGION_SIZE, region.y * REGION_SIZE)
	var px := clampi(int(floorf((wx - origin.x) / step - 0.5)), 0, img.get_width() - 1)
	var pz := clampi(int(floorf((wz - origin.y) / step - 0.5)), 0, img.get_height() - 1)
	return img.get_pixel(px, pz).r

func _build_loop(center: Vector2) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var segments := 36
	for i in range(segments):
		var t := float(i) / float(segments)
		var angle := TAU * t
		var radius := 54.0 + 24.0 * sin(angle * 2.0 + 0.7)
		points.append(Vector3(
			center.x + cos(angle) * radius,
			12.0 + 4.0 * sin(angle + 1.4),
			center.y + sin(angle) * radius * 0.8))
	return points

func test_bake_region_is_deterministic() -> void:
	var img_a := _bake(Vector2i.ZERO)
	var img_b := _bake(Vector2i.ZERO)
	assert_that(img_a.get_data()).is_equal(img_b.get_data())

func test_spawn_plateau_guard_wins_and_natural_heights_survive() -> void:
	var baker := TerrainBaker.new()
	var img := baker.bake_region(Vector2i.ZERO)
	var spawn_y := _height_at(img, Vector2i.ZERO, 128.0, 128.0)
	assert_that(spawn_y).is_between(2.18, 2.22)
	var far_y := _height_at(img, Vector2i.ZERO, 1000.0, 1000.0)
	assert_that(absf(far_y - baker._natural_height(1000.0, 1000.0))).is_less(0.5)
	assert_that(far_y).is_not_equal(2.2)
	assert_that(far_y).is_not_equal(1.0)

func test_road_conforming_carves_loop_and_relaxes_to_natural() -> void:
	var region := Vector2i(3, 3)
	var loop := _build_loop(LOOP_CENTER)
	var road_list: Array = [loop]
	var carved := _bake(region, road_list)
	var natural := _bake(region)
	for i in loop.size():
		var p: Vector3 = loop[i]
		var y := _height_at(carved, region, p.x, p.z)
		assert_that(y).is_between(p.y - 0.5, p.y + 0.5)
		var out := (Vector2(p.x, p.z) - LOOP_CENTER).normalized()
		var lateral := Vector3(p.x + out.x * 120.0, 0.0, p.z + out.y * 120.0)
		var carved_side := _height_at(carved, region, lateral.x, lateral.z)
		var natural_side := _height_at(natural, region, lateral.x, lateral.z)
		assert_that(absf(carved_side - natural_side)).is_less(3.0)