# tests/suites/test_terrain_vista_baker.gd
extends GdUnitTestSuite

## TerrainVistaBaker: the static far-terrain field must be the live ring's
## field minus the bias. The z-fight guarantee is tested against the real ring
## bake (TerrainBaker.bake_region at 1 m): at every live vertex inside a vista
## quad, the vista surface (either triangle split of the 8 m quad) stays below
## the live surface, in regions with roads, dome slopes, the biome edge and the
## sea. The vista must also track the ring (no gap at the ring edge).

const RING_PX := 256
const RING_SIZE := 256.0
const STEP := TerrainVistaBaker.STEP
const MIN_CLEARANCE := 0.1
const MAX_TRACK_ERROR := 0.6

## A road cut into a hill near the hub: 20 m below the natural ground at its
## middle, so the carve, the cut slopes and the sag allowance are all exercised.
func _cut_road() -> Array:
	var tb := TerrainBaker.new()
	var pts: Array[Vector3] = []
	for i in 41:
		var x := 1024.0 + float(i) * 8.0
		var z := 1100.0 + float(i) * 3.0
		pts.append(Vector3(x, tb.natural_height_at(x, z) - 20.0, z))
	return [pts]

## Same road on a 15 m embankment (fill).
func _fill_road() -> Array:
	var tb := TerrainBaker.new()
	var pts: Array[Vector3] = []
	for i in 41:
		var x := 1024.0 + float(i) * 8.0
		var z := 1100.0 + float(i) * 3.0
		pts.append(Vector3(x, tb.natural_height_at(x, z) + 15.0, z))
	return [pts]

## Vista vertex grid covering one live region: rows/cols of vista vertices from
## the live region origin to one vertex past its far edge.
func _vista_patch(live_loc: Vector2i, roads: Array) -> Dictionary:
	var baker := TerrainVistaBaker.new()
	var ox := float(live_loc.x) * RING_SIZE
	var oz := float(live_loc.y) * RING_SIZE
	var vloc := Vector2i(floori(ox / TerrainVistaBaker.REGION_WORLD), floori(oz / TerrainVistaBaker.REGION_WORLD))
	var vo := TerrainVistaBaker.region_origin(vloc)
	var chains := TerrainVistaBaker.region_chains(roads, vloc)
	var row0 := int((oz - vo.y) / STEP)
	var col0 := int((ox - vo.x) / STEP)
	var n := int(RING_SIZE / STEP)
	var w := TerrainVistaBaker.REGION_PX
	var band := row0 / TerrainVistaBaker.BAND_ROWS
	var full := PackedFloat32Array()
	full.resize(w * w)
	var edge := PackedByteArray()
	edge.resize(w * w)
	for b in range(maxi(band - 1, 0), mini(band + 1, TerrainVistaBaker.BAND_COUNT - 1) + 1):
		var out := baker.bake_band(vloc, b, chains)
		var h: PackedFloat32Array = out["height"]
		var e: PackedByteArray = out["edge"]
		for i in h.size():
			full[b * TerrainVistaBaker.BAND_ROWS * w + i] = h[i]
			edge[b * TerrainVistaBaker.BAND_ROWS * w + i] = e[i]
	var final := TerrainVistaBaker.erode_rows(full, edge, row0, n)
	var vals := PackedFloat32Array()
	vals.resize(n * n)
	for j in n:
		for i in n:
			vals[j * n + i] = final[j * w + col0 + i]
	return {"n": n, "vals": vals}

## Max over both triangle splits of the quad (Terrain3D alternates diagonals).
func _quad_max(h00: float, h10: float, h01: float, h11: float, u: float, v: float) -> float:
	var a := h00 + (h10 - h00) * u + (h01 - h00) * v if u + v <= 1.0 else h11 + (h01 - h11) * (1.0 - u) + (h10 - h11) * (1.0 - v)
	var b := h10 + (h00 - h10) * (1.0 - u) + (h11 - h10) * v if (1.0 - u) + v <= 1.0 else h01 + (h11 - h01) * u + (h00 - h01) * (1.0 - v)
	return maxf(a, b)

## Returns {"clearance": min(ring - vista) over every live vertex inside a vista
## quad, "track": max |vista_vertex - (ring - 1)| at shared vertices away from
## roads and off the live-cell seam (where the vista deliberately takes the
## lower side), "mean_track": mean of the same}.
func _compare(live_loc: Vector2i, roads: Array) -> Dictionary:
	var ring := TerrainBaker.new().bake_region(live_loc, 1.0, RING_PX, roads).get_data().to_float32_array()
	var patch := _vista_patch(live_loc, roads)
	var n: int = patch["n"]
	var vals: PackedFloat32Array = patch["vals"]
	var k := int(STEP)
	var clearance := INF
	var track := 0.0
	var track_sum := 0.0
	var track_n := 0
	for j in n - 1:
		for i in n - 1:
			var h00 := vals[j * n + i]
			var h10 := vals[j * n + i + 1]
			var h01 := vals[(j + 1) * n + i]
			var h11 := vals[(j + 1) * n + i + 1]
			for dz in k + 1:
				for dx in k + 1:
					var lx := i * k + dx
					var lz := j * k + dz
					if lx >= RING_PX or lz >= RING_PX:
						continue
					var live := ring[lz * RING_PX + lx]
					var vista := _quad_max(h00, h10, h01, h11, float(dx) / float(k), float(dz) / float(k))
					clearance = minf(clearance, live - vista)
			var dev := absf(h00 - (ring[j * k * RING_PX + i * k] + TerrainVistaBaker.BIAS))
			if roads.is_empty() and i > 0 and j > 0:
				track = maxf(track, dev)
				track_sum += dev
				track_n += 1
	return {"clearance": clearance, "track": track, "mean_track": track_sum / float(maxi(track_n, 1))}

func test_nine_regions_cover_the_drivable_world_with_margin() -> void:
	var locs := TerrainVistaBaker.all_region_locs()
	assert_that(locs.size()).is_equal(9)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for loc in locs:
		var o := TerrainVistaBaker.region_origin(loc)
		lo = Vector2(minf(lo.x, o.x), minf(lo.y, o.y))
		hi = Vector2(maxf(hi.x, o.x + TerrainVistaBaker.REGION_WORLD), maxf(hi.y, o.y + TerrainVistaBaker.REGION_WORLD))
	assert_that(lo).is_equal(Vector2(-8192.0, -8192.0))
	assert_that(hi).is_equal(Vector2(16384.0, 16384.0))
	assert_that(-200.0 - lo.x).is_greater(4000.0)
	assert_that(-2944.0 - lo.y).is_greater(4000.0)
	assert_that(hi.x - 9702.0).is_greater(4000.0)
	assert_that(hi.y - 8605.0).is_greater(4000.0)
	assert_that(TerrainVistaBaker.region_center(Vector2i(0, 0))).is_equal(Vector3(4096.0, 0.0, 4096.0))

func test_regions_are_ordered_nearest_first() -> void:
	assert_that(TerrainVistaBaker.order_locs(Vector2(128.0, 128.0))[0]).is_equal(Vector2i(0, 0))
	assert_that(TerrainVistaBaker.order_locs(Vector2(-100.0, 50.0))[0]).is_equal(Vector2i(-1, 0))
	assert_that(TerrainVistaBaker.order_locs(Vector2(9000.0, -50.0))[0]).is_equal(Vector2i(1, -1))
	var order := TerrainVistaBaker.order_locs(Vector2(128.0, 128.0))
	assert_that(order.size()).is_equal(9)
	assert_that(order.slice(1, 4)).contains_exactly_in_any_order([Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)])

func test_bands_are_deterministic() -> void:
	var roads := _cut_road()
	var chains := TerrainVistaBaker.region_chains(roads, Vector2i(0, 0))
	var a := TerrainVistaBaker.new().bake_band(Vector2i(0, 0), 4, chains)
	var b := TerrainVistaBaker.new().bake_band(Vector2i(0, 0), 4, chains)
	assert_that(a["height"]).is_equal(b["height"])
	assert_that(a["color"]).is_equal(b["color"])
	assert_that((a["height"] as PackedFloat32Array).size()).is_equal(TerrainVistaBaker.BAND_ROWS * TerrainVistaBaker.REGION_PX)

func test_vista_stays_below_and_tracks_the_ring_in_open_country() -> void:
	for loc in [Vector2i(0, 0), Vector2i(8, 2), Vector2i(14, 12)]:
		var r := _compare(loc, [])
		assert_that(r["clearance"]).override_failure_message("clearance at %s = %s" % [loc, r["clearance"]]).is_greater(MIN_CLEARANCE)
		assert_that(r["track"]).override_failure_message("track at %s = %s" % [loc, r["track"]]).is_less(MAX_TRACK_ERROR)
		assert_that(r["mean_track"]).is_less(0.15)

func test_vista_stays_below_the_ring_on_dome_slopes_and_peaks() -> void:
	for loc in [Vector2i(30, 13), Vector2i(25, 30), Vector2i(19, 22)]:
		var r := _compare(loc, [])
		assert_that(r["clearance"]).override_failure_message("clearance at %s = %s" % [loc, r["clearance"]]).is_greater(MIN_CLEARANCE)
		assert_that(r["track"]).override_failure_message("track at %s = %s" % [loc, r["track"]]).is_less(MAX_TRACK_ERROR)

## The dome top reaches the 2000 m height clamp, where the vista takes the
## lowest of the ring's four coarse samples: safe, a few metres low at worst.
func test_vista_stays_below_the_ring_at_the_height_clamp() -> void:
	var r := _compare(Vector2i(30, 25), [])
	assert_that(r["clearance"]).override_failure_message("clearance = %s" % r["clearance"]).is_greater(MIN_CLEARANCE)
	assert_that(r["mean_track"]).is_less(1.0)

func test_vista_stays_below_the_ring_at_the_sea_and_the_biome_edge() -> void:
	for loc in [Vector2i(32, -14), Vector2i(36, 25), Vector2i(-6, 0), Vector2i(-3, 5)]:
		var r := _compare(loc, [])
		assert_that(r["clearance"]).override_failure_message("clearance at %s = %s" % [loc, r["clearance"]]).is_greater(MIN_CLEARANCE)

func test_vista_stays_below_a_carved_road_cut_and_fill() -> void:
	for roads in [_cut_road(), _fill_road()]:
		for loc in [Vector2i(4, 4), Vector2i(5, 4)]:
			var r := _compare(loc, roads)
			assert_that(r["clearance"]).override_failure_message("road clearance at %s = %s" % [loc, r["clearance"]]).is_greater(MIN_CLEARANCE)

func test_road_carve_reaches_the_vista() -> void:
	var roads := _cut_road()
	var pts: Array = roads[0]
	var mid: Vector3 = pts[20]
	var vloc := Vector2i(0, 0)
	var chains := TerrainVistaBaker.region_chains(roads, vloc)
	var row := int(roundf((mid.z - TerrainVistaBaker.SAMPLE_OFFSET) / STEP))
	var col := int(roundf((mid.x - TerrainVistaBaker.SAMPLE_OFFSET) / STEP))
	var band := row / TerrainVistaBaker.BAND_ROWS
	var carved: PackedFloat32Array = TerrainVistaBaker.new().bake_band(vloc, band, chains)["height"]
	var plain: PackedFloat32Array = TerrainVistaBaker.new().bake_band(vloc, band, [] as Array[PackedVector3Array])["height"]
	var i := (row - band * TerrainVistaBaker.BAND_ROWS) * TerrainVistaBaker.REGION_PX + col
	assert_that(plain[i] - carved[i]).is_greater(15.0)
	assert_that(carved[i]).is_less(mid.y - TerrainBaker.ROAD_TOPPING + TerrainVistaBaker.BIAS + 0.5)

func test_spawn_plateau_sits_one_bias_below_the_pad() -> void:
	var band: PackedFloat32Array = TerrainVistaBaker.new().bake_band(Vector2i(0, 0), 0, [] as Array[PackedVector3Array])["height"]
	var i := 16 * TerrainVistaBaker.REGION_PX + 16
	assert_that(band[i]).is_equal_approx(TerrainBaker.SPAWN_HEIGHT + TerrainVistaBaker.BIAS, 0.0001)

func test_colour_and_control_maps_are_valid() -> void:
	var baker := TerrainVistaBaker.new()
	var loc := Vector2i(0, 0)
	var chains := TerrainVistaBaker.region_chains([], loc)
	var bands: Array = []
	for b in TerrainVistaBaker.BAND_COUNT:
		bands.append({"height": PackedFloat32Array(), "color": PackedByteArray()})
	bands[25] = baker.bake_band(loc, 25, chains)
	bands[24] = baker.bake_band(loc, 24, chains)
	bands[26] = baker.bake_band(loc, 26, chains)
	var heights := PackedFloat32Array()
	heights.resize(TerrainVistaBaker.REGION_PX * TerrainVistaBaker.REGION_PX)
	for b in [24, 25, 26]:
		var h: PackedFloat32Array = bands[b]["height"]
		for i in h.size():
			heights[b * TerrainVistaBaker.BAND_ROWS * TerrainVistaBaker.REGION_PX + i] = h[i]
	var second := baker.bake_control_band(loc, 25, heights)
	var control: PackedByteArray = second["control"]
	assert_that((second["height"] as PackedFloat32Array).size()).is_equal(TerrainVistaBaker.BAND_ROWS * TerrainVistaBaker.REGION_PX)
	assert_that(control.size()).is_equal(TerrainVistaBaker.BAND_ROWS * TerrainVistaBaker.REGION_PX * 4)
	var ids := {}
	for i in range(0, control.size(), 4 * 97):
		var bits := control.decode_u32(i)
		assert_that(TerrainTexturing.decode_base(bits)).is_less(TerrainTexturing.LAYER_COUNT)
		assert_that(TerrainTexturing.decode_overlay(bits)).is_less(TerrainTexturing.LAYER_COUNT)
		ids[TerrainTexturing.decode_base(bits)] = true
	assert_that(ids.size()).is_greater(1)
	var color: PackedByteArray = bands[25]["color"]
	for i in range(0, color.size(), 4 * 131):
		assert_that(color[i]).is_greater(170)
		assert_that(color[i + 3]).is_between(100, 160)

func test_whole_region_images_have_terrain3d_formats() -> void:
	var rec := TerrainVistaBaker.make_images(_second(0.5), _bytes(4))
	var h: Image = rec["height"]
	assert_that(h.get_width()).is_equal(TerrainVistaBaker.REGION_PX)
	assert_that(h.get_format()).is_equal(Image.FORMAT_RF)
	assert_that((rec["color"] as Image).get_format()).is_equal(Image.FORMAT_RGBA8)
	assert_that((rec["control"] as Image).get_format()).is_equal(Image.FORMAT_RF)
	assert_that(rec["height_min"]).is_equal(0.5)
	assert_that(rec["height_max"]).is_equal(0.5)

func _bytes(per: int) -> PackedByteArray:
	var a := PackedByteArray()
	a.resize(TerrainVistaBaker.REGION_PX * TerrainVistaBaker.REGION_PX * per)
	return a

func _second(v: float) -> Array:
	var out: Array = []
	for b in TerrainVistaBaker.BAND_COUNT:
		var c := PackedByteArray()
		c.resize(TerrainVistaBaker.BAND_ROWS * TerrainVistaBaker.REGION_PX * 4)
		var h := PackedFloat32Array()
		h.resize(TerrainVistaBaker.BAND_ROWS * TerrainVistaBaker.REGION_PX)
		h.fill(v)
		out.append({"control": c, "height": h})
	return out
