# tests/suites/test_world_flora.gd
extends GdUnitTestSuite

## FH6-look pass (2026-10-23): procedural vegetation / rocks / roadside
## furniture (FloraMeshes, Flora), the RegionDresser Flora wiring and quality
## hook, the atmosphere grade and the landmark placement rule. Headless-safe:
## no renderer reads, synthetic ground providers, nodes freed in after_test.

const REGION := 256.0

var _nodes: Array[Node] = []

func after_test() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()

## Builds a Flora over a synthetic region: flat ground at 5 m, every texel the
## given control bits (or the callable's answer).
func _flora(zone: String, bits: int, detail: int = 1, ctl: Callable = Callable()) -> Flora:
	var f := Flora.new()
	f.zone = zone
	f.seed = 4242
	f.detail = detail
	f.half_extent = REGION * 0.5
	f.height_provider = func(_xz: Vector2) -> float: return 5.0
	f.control_provider = ctl if ctl.is_valid() else func(_xz: Vector2) -> int: return bits
	add_child(f)
	_nodes.append(f)
	f.build_now()
	return f

func _grass_bits() -> int:
	return TerrainTexturing.encode_control(TerrainTexturing.ID_GRASS, TerrainTexturing.ID_MEADOW, 0.45)

# -- meshes ---------------------------------------------------------------------------

func test_every_mesh_builds_inside_its_triangle_budget() -> void:
	for key: String in FloraMeshes.KEYS:
		var m := FloraMeshes.get_mesh(key)
		assert_that(m).is_not_null()
		var tris := FloraMeshes.triangle_count(m)
		assert_int(tris).is_greater(0)
		var cap := FloraMeshes.MAX_PROP_TRIS
		if key in Flora.MESH_TREE:
			cap = FloraMeshes.MAX_TREE_TRIS
		elif key in ["bush", "shrub"]:
			cap = FloraMeshes.MAX_BUSH_TRIS
		elif key in ["grass", "dune_grass", "flowers"]:
			cap = FloraMeshes.MAX_GRASS_TRIS
		elif key in ["boulder", "slab", "crag"]:
			cap = FloraMeshes.MAX_ROCK_TRIS
		assert_int(tris).is_less_equal(cap)
	# Cached: the same mesh object every time.
	assert_that(FloraMeshes.get_mesh("oak")).is_same(FloraMeshes.get_mesh("oak"))

func test_trees_are_tree_sized_and_stand_on_their_base() -> void:
	for key: String in Flora.MESH_TREE:
		var aabb := FloraMeshes.get_mesh(key).get_aabb()
		assert_float(aabb.end.y).is_between(6.0, 13.0)
		assert_float(aabb.position.y).is_between(-1.0, 0.0)

func test_closed_meshes_wind_clockwise_from_outside() -> void:
	# Godot front faces are clockwise: for a closed blob the geometric normal
	# (b - a) x (c - a) must point INTO the mesh, the stored normal outward.
	var arrays := FloraMeshes.get_mesh("boulder").surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var bad := 0
	for k in range(0, idx.size(), 3):
		var a := v[idx[k]]
		var b := v[idx[k + 1]]
		var c := v[idx[k + 2]]
		var geo := (b - a).cross(c - a)
		if geo.dot(n[idx[k]]) > 0.0:
			bad += 1
	assert_int(bad).is_equal(0)

# -- kits / biome selection -------------------------------------------------------------

func test_kits_per_zone_follow_the_biome() -> void:
	var keys := func(zone: String) -> Array:
		var out := []
		for e: Dictionary in Flora.kit_for(zone):
			out.append(e["key"])
		return out
	var low: Array = keys.call("lowlands")
	assert_array(low).contains(["oak", "birch", "maple", "bush", "grass", "flowers"])
	var coast: Array = keys.call("coast")
	assert_array(coast).contains(["dune_grass", "bush"])
	var alpine: Array = keys.call("alpine")
	assert_array(alpine).contains(["crag", "boulder"])
	for t: String in Flora.MESH_TREE:
		assert_array(alpine).not_contains([t])

func test_detail_ladder_scales_small_plants() -> void:
	var chance := func(detail: int, key: String) -> float:
		for e: Dictionary in Flora.kit_for("lowlands", detail):
			if e["key"] == key:
				return float(e["chance"])
		return -1.0
	assert_float(chance.call(0, "grass")).is_less(chance.call(1, "grass"))
	assert_float(chance.call(1, "grass")).is_less(chance.call(2, "grass"))
	assert_float(chance.call(0, "oak")).is_equal(chance.call(2, "oak"))

func test_ground_mask_decodes_base_and_strong_overlay() -> void:
	var g := TerrainTexturing.encode_control(TerrainTexturing.ID_GRASS, TerrainTexturing.ID_MEADOW, 0.1)
	assert_int(Flora.ground_mask(g)).is_equal(Flora.G_GRASS)
	var gm := TerrainTexturing.encode_control(TerrainTexturing.ID_GRASS, TerrainTexturing.ID_MEADOW, 0.45)
	assert_int(Flora.ground_mask(gm)).is_equal(Flora.G_GRASS | Flora.G_MEADOW)
	var road := TerrainTexturing.encode_control(TerrainTexturing.ID_GRAVEL, TerrainTexturing.ID_GRAVEL, 0.0)
	assert_int(Flora.ground_mask(road)).is_equal(0)
	assert_int(Flora.ground_mask(-1) & Flora.G_PLANT).is_equal(Flora.G_PLANT)

# -- placement --------------------------------------------------------------------------

func test_lowland_region_has_mixed_vegetation_within_budget() -> void:
	var f := _flora("lowlands", _grass_bits())
	assert_int(f.count_for("oak") + f.count_for("birch") + f.count_for("maple") + f.count_for("poplar")).is_between(20, 160)
	assert_int(f.count_for("bush") + f.count_for("shrub")).is_between(60, 600)
	assert_int(f.count_for("grass")).is_between(800, 3200)
	assert_int(f.count_for("flowers")).is_greater(100)
	# Region budget: instances and the triangles one full draw would submit.
	assert_int(f.get_instance_count()).is_less_equal(6000)
	assert_int(f.triangle_estimate()).is_less_equal(250000)
	# Every placement stays inside the region cell.
	for key: String in ["oak", "bush", "grass"]:
		for p: Vector3 in f.positions_for(key):
			assert_float(absf(p.x)).is_less(REGION * 0.5)
			assert_float(absf(p.z)).is_less(REGION * 0.5)

func test_placement_is_deterministic() -> void:
	var a := _flora("lowlands", _grass_bits())
	var b := _flora("lowlands", _grass_bits())
	for key: String in ["oak", "bush", "grass", "flowers"]:
		assert_that(a.positions_for(key)).is_equal(b.positions_for(key))
	# Time-sliced build gives the same result as one-shot.
	var c := Flora.new()
	c.zone = "lowlands"
	c.seed = 4242
	c.half_extent = REGION * 0.5
	c.height_provider = func(_xz: Vector2) -> float: return 5.0
	var bits := _grass_bits()
	c.control_provider = func(_xz: Vector2) -> int: return bits
	add_child(c)
	_nodes.append(c)
	c.begin()
	var guard := 0
	while not c.step(0) and guard < 100000:
		guard += 1
	assert_int(guard).is_greater(3)
	assert_that(c.positions_for("oak")).is_equal(a.positions_for("oak"))
	assert_that(c.positions_for("grass")).is_equal(a.positions_for("grass"))

func test_nothing_grows_on_roads_rock_snow_or_sand_except_rock_kit() -> void:
	var gravel := TerrainTexturing.encode_control(TerrainTexturing.ID_GRAVEL, TerrainTexturing.ID_GRAVEL, 0.0)
	assert_int(_flora("lowlands", gravel).get_instance_count()).is_equal(0)
	var snow := TerrainTexturing.encode_control(TerrainTexturing.ID_SNOW, TerrainTexturing.ID_SNOW, 0.0)
	var on_snow := _flora("alpine", snow)
	assert_int(on_snow.get_instance_count()).is_equal(on_snow.count_for("slab"))
	var rock := TerrainTexturing.encode_control(TerrainTexturing.ID_ROCK, TerrainTexturing.ID_ROCK, 0.0)
	var on_rock := _flora("lowlands", rock)
	assert_int(on_rock.count_for("oak") + on_rock.count_for("grass")).is_equal(0)
	assert_int(on_rock.count_for("crag")).is_greater(0)

func test_trees_keep_clear_of_the_road_shoulder() -> void:
	# A gravel band (road + shoulder) along local z in [-8, 8].
	var grass := _grass_bits()
	var gravel := TerrainTexturing.encode_control(TerrainTexturing.ID_GRAVEL, TerrainTexturing.ID_GRAVEL, 0.0)
	var ctl := func(xz: Vector2) -> int: return gravel if absf(xz.y) < 8.0 else grass
	var f := _flora("lowlands", 0, 1, ctl)
	for key: String in Flora.MESH_TREE:
		for p: Vector3 in f.positions_for(key):
			assert_float(absf(p.z)).is_greater(8.0 + 9.0)
	for p: Vector3 in f.positions_for("grass"):
		assert_float(absf(p.z)).is_greater_equal(8.0)

func test_clear_zone_keeps_trees_out_and_small_plants_off_its_core() -> void:
	var f := Flora.new()
	f.zone = "lowlands"
	f.seed = 4242
	f.half_extent = REGION * 0.5
	f.height_provider = func(_xz: Vector2) -> float: return 5.0
	var bits := _grass_bits()
	f.control_provider = func(_xz: Vector2) -> int: return bits
	f.clear_zones = [Vector3(0.0, 0.0, 100.0)]
	add_child(f)
	_nodes.append(f)
	f.build_now()
	for p: Vector3 in f.positions_for("oak"):
		assert_float(Vector2(p.x, p.z).length()).is_greater_equal(100.0)
	for p: Vector3 in f.positions_for("grass"):
		assert_float(Vector2(p.x, p.z).length()).is_greater_equal(100.0 * Flora.SMALL_CLEAR_SHARE)

func test_small_plants_batch_per_patch_with_short_draw_distance() -> void:
	var f := _flora("lowlands", _grass_bits())
	var small := 0
	for child in f.get_children():
		var mmi := child as MultiMeshInstance3D
		assert_that(mmi).is_not_null()
		assert_bool(mmi.multimesh.use_custom_data).is_true()
		if String(mmi.name).begins_with("grass_"):
			small += 1
			assert_float(mmi.visibility_range_end).is_less_equal(150.0)
			assert_int(mmi.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_int(small).is_greater_equal(9)

# -- roadside furniture -----------------------------------------------------------------

func _road_net(points: Array[Vector3], tier: int, closed: bool) -> RoadNetwork:
	var net := RoadNetwork.new()
	add_child(net)
	_nodes.append(net)
	var def := RoadDef.make(tier, points, "test-road", closed)
	def.rail_sides = RoadDef.RailSide.NONE
	net.add_road_def(def)
	return net

func test_roadside_posts_stand_off_the_carriageway_and_chevrons_on_bends() -> void:
	# A straight run then a tight 90 degree bend, all inside one region cell.
	var pts: Array[Vector3] = []
	for i in 9:
		pts.append(Vector3(-100.0 + 12.0 * float(i), 5.0, -60.0))
	for i in range(1, 9):
		var a := -PI * 0.5 + PI * 0.5 * float(i) / 8.0
		pts.append(Vector3(-4.0 + cos(a) * 30.0, 5.0, -30.0 + sin(a) * 30.0))
	for i in range(1, 6):
		pts.append(Vector3(26.0, 5.0, -30.0 + 12.0 * float(i)))
	var net := _road_net(pts, RoadDef.Tier.COASTAL, false)
	var f := Flora.new()
	f.zone = "coast"
	f.seed = 1
	f.half_extent = REGION * 0.5
	f.road_network = net
	f.kit = [{"key": "grass", "kind": "small", "cell": 1000.0, "chance": 0.0, "grove": 0.0, "ground": 0, "scale": Vector2.ONE, "road_clear": 0.0, "tints": [Color.WHITE], "autumn": 0.0}]
	add_child(f)
	_nodes.append(f)
	f.build_now()
	var posts := f.positions_for("delineator")
	assert_int(posts.size()).is_greater(4)
	var half := net.get_road_def(0).width * 0.5
	for p: Vector3 in posts:
		var hit: Dictionary = net.nearest_road_lookup(p)
		assert_float(float(hit["distance"])).is_greater(half + 0.5)
	var chev := f.positions_for("chevron")
	assert_int(chev.size()).is_greater(0)
	# Outside of the bend: farther from the bend centre (-4, -30) than the road.
	for p: Vector3 in chev:
		assert_float(Vector2(p.x + 4.0, p.z + 30.0).length()).is_greater(30.0)

# -- dresser wiring ---------------------------------------------------------------------

func test_dresser_adds_flora_only_when_enabled_and_hooks_detail() -> void:
	var d := RegionDresser.new()
	d.set_process(false)
	add_child(d)
	_nodes.append(d)
	d.sync_player_pos(Vector3(128, 0, 128))
	for _i in 40:
		d.drain_pending()
	assert_that(d.region_node(Vector2i(0, 0)).get_node_or_null("Flora")).is_null()
	assert_bool(d.is_in_group("world_detail")).is_true()
	var e := RegionDresser.new()
	e.set_process(false)
	e.flora_enabled = true
	e.zone_conifer_scale = {"lowlands": 0.25}
	add_child(e)
	_nodes.append(e)
	e.sync_player_pos(Vector3(2048, 0, 2048))
	for _i in 4000:
		e.drain_pending()
		if e.pending_spawn_count() == 0 and e.pending_flora_count() == 0:
			break
	assert_int(e.pending_flora_count()).is_equal(0)
	var loc := Vector2i(8, 8)
	var flora := e.region_node(loc).get_node_or_null("Flora") as Flora
	assert_that(flora).is_not_null()
	assert_bool(flora.is_built()).is_true()
	assert_int(flora.get_instance_count()).is_greater(0)
	var foliage := e.region_node(loc).get_node("Foliage") as Foliage
	var zone := RegionDresser.region_zone(0, loc)
	var base: int = int(RegionDresser.ZONE_FOLIAGE[zone]["trees"])
	assert_int(foliage.tree_count).is_equal(int(round(float(base) * float(e.zone_conifer_scale.get(zone, 1.0)))))
	# Prefetch-band regions get no Flora build.
	var pref := e.region_node(loc + Vector2i(2, 0)).get_node_or_null("Flora") as Flora
	assert_bool(pref.is_built()).is_false()
	# Quality hook rebuilds at the new level.
	SettingsMenuScript.apply_world_detail(self, 0)
	assert_int(e.world_detail).is_equal(0)
	assert_int(e.pending_flora_count()).is_greater(0)

const SettingsMenuScript: GDScript = preload("res://scripts/ui/settings_menu.gd")

func test_quality_presets_carry_world_detail() -> void:
	assert_int(int(SettingsMenuScript.preset_for(0)["world_detail"])).is_equal(0)
	assert_int(int(SettingsMenuScript.preset_for(1)["world_detail"])).is_equal(1)
	assert_int(int(SettingsMenuScript.preset_for(2)["world_detail"])).is_equal(2)

# -- atmosphere / landmarks -------------------------------------------------------------

func test_sun_grade_is_warm_low_neutral_high_and_dim_at_night() -> void:
	var noon: Dictionary = WorldAtmosphere.sun_grade(12.0)
	var dusk: Dictionary = WorldAtmosphere.sun_grade(17.6)
	var night: Dictionary = WorldAtmosphere.sun_grade(0.0)
	var nc: Color = noon["color"]
	var dc: Color = dusk["color"]
	assert_float(dc.b / dc.r).is_less(nc.b / nc.r)
	assert_float(float(dusk["energy"])).is_less(float(noon["energy"]))
	assert_float(float(night["energy"])).is_less(float(dusk["energy"]))
	var ng: Color = night["color"]
	assert_float(ng.b).is_greater(ng.r)

func test_haze_is_light_denser_by_the_coast_thinner_up_high() -> void:
	var hub := WorldAtmosphere.haze_for(Vector3(128, 2, 128))
	assert_float(hub).is_between(0.0002, 0.0008)
	assert_float(WorldAtmosphere.haze_for(Vector3(8200, 2, -1800))).is_greater(hub)
	assert_float(WorldAtmosphere.haze_for(Vector3(6000, 1500, 6000))).is_less(hub)

func test_landmark_sites_are_moved_clear_of_roads() -> void:
	var pts: Array[Vector3] = [Vector3(-500, 0, 0), Vector3(500, 0, 0)]
	var net := _road_net(pts, RoadDef.Tier.ARTERIAL, false)
	var on_road := WorldLandmarks.resolve_site(Vector2(0, 5), net)
	var hit: Dictionary = net.nearest_road_lookup(Vector3(on_road.x, 0, on_road.y))
	assert_float(float(hit["distance"]) - net.get_road_def(0).width * 0.5).is_greater(WorldLandmarks.ROAD_CLEARANCE)
	var far := Vector2(0, 300)
	assert_that(WorldLandmarks.resolve_site(far, net)).is_equal(far)
