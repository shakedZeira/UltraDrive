# tests/suites/test_terrain_biomes.gd
extends GdUnitTestSuite

## P1 biome-gate: elevation band monotonicity, biome base ordering, height-band
## ordering across region hashes, colour determinism, sea-level mask consistency
## and road-recess check carried over from test_terrain_baker conventions.

const IMAGE_WIDTH := 1024
const REGION_SIZE := 1024.0
const LOOP_CENTER := Vector2(3800.0, 3200.0)

func _bake(region: Vector2i, roads: Array = []) -> Image:
	return TerrainBaker.new().bake_region(region, 1.0, IMAGE_WIDTH, roads)

func _bake_color(region: Vector2i, roads: Array = []) -> Image:
	return TerrainBaker.new().bake_region_color(region, 1.0, IMAGE_WIDTH, roads)

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

## (1) elevation_band() is monotonically non-decreasing in height: every
## higher input must produce a band index >= the previous one.
func test_elevation_band_monotonic() -> void:
	var samples := [-10.0, -8.0, -5.0, -1.0, -0.001, 0.0, 0.5, 5.0, 10.0, 15.0, 30.0, 59.0, 60.0, 100.0, 199.0, 200.0, 300.0, 599.0, 600.0, 900.0, 1500.0, 2000.0]
	var prev_band := -1
	for h in samples:
		var band: int = TerrainBaker.elevation_band(h)
		assert_that(band).is_greater_equal(prev_band)
		prev_band = band

## (2) Biome base ordering: the ELEVATION_BANDS table is strictly
## non-decreasing in its lower bounds so bands never overlap.
func test_elevation_band_bounds_non_decreasing() -> void:
	var prev_min := -INF
	for band_def in TerrainBaker.ELEVATION_BANDS:
		assert_that(band_def["min"]).is_greater_equal(prev_min)
		prev_min = band_def["min"]

## (3) Height-band ordering monotonic across region hashes: for each of a set
## of region hashes, _biome_base at the biome centres must classify into
## non-decreasing band indices. The ramp follows the true elevation grade of
## the ordered biome table: spawn→rolling→highland→lowland→highland-plateau
## (the pass-region highland base stays ~35 m per the driveable-corridor
## tuning, so it sits between rolling and the forested lowland mass).
func test_biome_base_monotonic_across_regions() -> void:
	var region_hashes := [Vector2i(0, 0), Vector2i(2, 2), Vector2i(4, 4), Vector2i(6, 6), Vector2i(7, 7)]
	var ordered_biomes := [
		TerrainBaker.BIOME_SPAWN_CENTER,
		TerrainBaker.BIOME_ROLLING_CENTER,
		TerrainBaker.BIOME_HIGHLAND_CENTER,
		TerrainBaker.BIOME_LOWLAND_CENTER,
		TerrainBaker.BIOME_HIGHLAND_PLATEAU_CENTER,
	]
	for rh in region_hashes:
		var baker := TerrainBaker.new()
		# Bake the region once so the base lookup runs with a real region hash.
		baker.bake_region(rh)
		var prev_band := -1
		for center in ordered_biomes:
			var base: float = baker._biome_base(center.x, center.y)
			var band: int = TerrainBaker.elevation_band(base)
			assert_that(band).is_greater_equal(prev_band)
			prev_band = band

## (4) Determinism: same seed → two colour bakes byte-identical; different
## region → different pixels.
func test_color_bake_deterministic() -> void:
	var img_a := _bake_color(Vector2i(1, 1))
	var img_b := _bake_color(Vector2i(1, 1))
	assert_that(img_a.get_data()).is_equal(img_b.get_data())
	var img_c := _bake_color(Vector2i(5, 5))
	assert_that(img_a.get_data()).is_not_equal(img_c.get_data())

## (5) Sea-level mask: at the SEA biome centre the height is below 0 and the
## elevation band classifies as SEA.
func test_sea_level_mask() -> void:
	var baker := TerrainBaker.new()
	baker.bake_region(Vector2i(8, -4))
	var h: float = baker._natural_height(TerrainBaker.BIOME_SEA_CENTER.x, TerrainBaker.BIOME_SEA_CENTER.y)
	assert_that(h).is_less(0.0)
	var band: int = TerrainBaker.elevation_band(h)
	assert_that(band).is_equal(TerrainBaker.BAND_SEA)

## (6) Road corridors still recess: carved height at a road point matches the
## road centreline y within 0.5 m (carried from test_terrain_baker).
func test_road_corridors_recess() -> void:
	var region := Vector2i(3, 3)
	var loop := _build_loop(LOOP_CENTER)
	var road_list: Array = [loop]
	var carved := _bake(region, road_list)
	for i in loop.size():
		var p: Vector3 = loop[i]
		var y := _height_at(carved, region, p.x, p.z)
		assert_that(y).is_between(p.y - 0.5, p.y + 0.5)
