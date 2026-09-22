# tests/test_terrain_baker.gd
extends GdUnitTestSuite

const IMAGE_WIDTH := 256
const REGION_SIZE := 256.0
const LOOP_CENTER := Vector2(3712.0, 3200.0)

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
	var far_y := _height_at(img, Vector2i.ZERO, 250.0, 250.0)
	assert_that(absf(far_y - baker._natural_height(250.0, 250.0))).is_less(0.5)
	assert_that(far_y).is_not_equal(2.2)
	assert_that(far_y).is_not_equal(1.0)

func test_road_conforming_carves_loop_and_relaxes_to_natural() -> void:
	var region := Vector2i(14, 12)
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

## P1 colour-map: bake_region_color is deterministic (two calls identical),
## colour image matches height image dimensions, SEA centre is < 0 with band
## SEA, and ALPINE dome peak is >= 600 (ALPINE band).
func test_bake_region_color_is_deterministic() -> void:
	var baker := TerrainBaker.new()
	var img_a := baker.bake_region_color(Vector2i(1, 1), 1.0, IMAGE_WIDTH, [])
	var img_b := baker.bake_region_color(Vector2i(1, 1), 1.0, IMAGE_WIDTH, [])
	assert_that(img_a.get_data()).is_equal(img_b.get_data())

func test_color_image_matches_height_dimensions() -> void:
	var baker := TerrainBaker.new()
	var height_img := baker.bake_region(Vector2i(0, 0), 1.0, IMAGE_WIDTH, [])
	var color_img := baker.bake_region_color(Vector2i(0, 0), 1.0, IMAGE_WIDTH, [])
	assert_that(color_img.get_width()).is_equal(height_img.get_width())
	assert_that(color_img.get_height()).is_equal(height_img.get_height())

func test_sea_center_height_below_zero_and_band_sea() -> void:
	var baker := TerrainBaker.new()
	baker.bake_region(Vector2i(8, -4))
	var h := baker._natural_height(TerrainBaker.BIOME_SEA_CENTER.x, TerrainBaker.BIOME_SEA_CENTER.y)
	assert_that(h).is_less(0.0)
	var band: int = TerrainBaker.elevation_band(h)
	assert_that(band).is_equal(TerrainBaker.BAND_SEA)

func test_alpine_dome_peak_in_alpine_band() -> void:
	var baker := TerrainBaker.new()
	baker.bake_region(Vector2i(7, 6))
	var peak_x: float = TerrainBaker.DOME_FAMILY[0]["center"].x
	var peak_z: float = TerrainBaker.DOME_FAMILY[0]["center"].y
	var h := baker._natural_height(peak_x, peak_z)
	assert_that(h).is_greater_equal(600.0)
	var band: int = TerrainBaker.elevation_band(h)
	assert_that(band).is_equal(TerrainBaker.BAND_ALPINE)

## P1 colour-map road tint: on a baked region with a road, a texel at the road
## centreline is asphalt-tinted (colour differs from a texel 200 m away).
func test_road_tint_differs_from_natural_color() -> void:
	var region := Vector2i(14, 12)
	var loop := _build_loop(LOOP_CENTER)
	var road_list: Array = [loop]
	var color_img := TerrainBaker.new().bake_region_color(region, 1.0, IMAGE_WIDTH, road_list)
	var p: Vector3 = loop[0]
	var step := REGION_SIZE / float(IMAGE_WIDTH)
	var origin := Vector2(region.x * REGION_SIZE, region.y * REGION_SIZE)
	var road_px := clampi(int(floorf((p.x - origin.x) / step - 0.5)), 0, IMAGE_WIDTH - 1)
	var road_pz := clampi(int(floorf((p.z - origin.y) / step - 0.5)), 0, IMAGE_WIDTH - 1)
	var road_col := color_img.get_pixel(road_px, road_pz)
	var out := (Vector2(p.x, p.z) - LOOP_CENTER).normalized()
	var far_x := p.x + out.x * 200.0
	var far_z := p.z + out.y * 200.0
	var far_px := clampi(int(floorf((far_x - origin.x) / step - 0.5)), 0, IMAGE_WIDTH - 1)
	var far_pz := clampi(int(floorf((far_z - origin.y) / step - 0.5)), 0, IMAGE_WIDTH - 1)
	var far_col := color_img.get_pixel(far_px, far_pz)
	assert_that(road_col).is_not_equal(far_col)