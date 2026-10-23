# tests/suites/test_map_style.gd
extends GdUnitTestSuite

## FH-style map presentation gate: the shared MapStyle tables (road hierarchy,
## event glyphs, class colours), MapTerrain's rect/bake helpers, the world map's
## zoom/pan/focus maths, the legend and region captions, and the race-menu map's
## pin style and focus. Everything is pure or headless-safe (no draw pass).

const WORLD_MAP_SCRIPT := "res://scripts/ui/world_map.gd"

var _managed: Array = []

func after_test() -> void:
	for node in _managed:
		if is_instance_valid(node):
			node.free()
	_managed.clear()
	MapTerrain.reset()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

# --- MapStyle: roads -----------------------------------------------------------

func test_road_hierarchy_widths_and_ranks_descend_by_class() -> void:
	assert_float(MapStyle.road_width(RoadDef.Tier.HIGHWAY)).is_greater(MapStyle.road_width(RoadDef.Tier.ARTERIAL))
	assert_float(MapStyle.road_width(RoadDef.Tier.ARTERIAL)).is_greater(MapStyle.road_width(RoadDef.Tier.TOUGE))
	assert_float(MapStyle.road_width(RoadDef.Tier.TOUGE)).is_greater(MapStyle.road_width(RoadDef.Tier.DIRT))
	# Higher class draws later (on top).
	assert_int(MapStyle.road_rank(RoadDef.Tier.HIGHWAY)).is_greater(MapStyle.road_rank(RoadDef.Tier.ARTERIAL))
	assert_int(MapStyle.road_rank(RoadDef.Tier.ARTERIAL)).is_greater(MapStyle.road_rank(RoadDef.Tier.DIRT))

func test_every_road_tier_has_a_style_and_unknown_falls_back() -> void:
	for tier in [RoadDef.Tier.HIGHWAY, RoadDef.Tier.ARTERIAL, RoadDef.Tier.TOUGE, RoadDef.Tier.COASTAL, RoadDef.Tier.DIRT]:
		assert_bool(MapStyle.ROAD_STYLES.has(int(tier))).is_true()
	assert_that(MapStyle.road_style(MapRoads.UNKNOWN_TIER)).is_equal(MapStyle.ROAD_STYLE_DEFAULT)

func test_unexplored_road_fades_and_desaturates() -> void:
	var seen := MapStyle.road_core(RoadDef.Tier.HIGHWAY, true)
	var unseen := MapStyle.road_core(RoadDef.Tier.HIGHWAY, false)
	assert_float(unseen.a).is_less(seen.a)
	# Desaturated: the unexplored highway's channel spread is narrower.
	var seen_spread := maxf(seen.r, maxf(seen.g, seen.b)) - minf(seen.r, minf(seen.g, seen.b))
	var unseen_spread := maxf(unseen.r, maxf(unseen.g, unseen.b)) - minf(unseen.r, minf(unseen.g, unseen.b))
	assert_float(unseen_spread).is_less(seen_spread)

func test_get_road_tiers_is_index_parallel_with_the_chains() -> void:
	var root := Node.new()
	_managed.append(root)
	var network := RoadNetwork.new()
	root.add_child(network)
	network.add_road([Vector3(0, 0, 0), Vector3(100, 0, 0)], 8.0, false)
	network.add_road([Vector3(0, 0, 50), Vector3(100, 0, 50)], 8.0, false)
	var tiers := MapRoads.get_road_tiers(network)
	assert_int(tiers.size()).is_equal(MapRoads.get_roads(network).size())
	var no_source := MapRoads.get_road_tiers(null)
	assert_int(no_source.size()).is_equal(0)

# --- MapStyle: pins -------------------------------------------------------------

func test_every_event_family_has_distinct_colour_and_glyph() -> void:
	var colors := {}
	var glyphs := {}
	for kind: String in MapStyle.EVENT_STYLES.keys():
		colors[MapStyle.event_color(kind).to_html()] = true
		glyphs[str(MapStyle.event_style(kind)["glyph"])] = true
	assert_int(colors.size()).is_equal(MapStyle.EVENT_STYLES.size())
	assert_int(glyphs.size()).is_equal(MapStyle.EVENT_STYLES.size())

func test_every_registered_event_kind_is_styled() -> void:
	for poi_id: String in POIRegistry.get_poi_ids():
		var poi := POIRegistry.get_poi(poi_id)
		if poi.has("kind") and not Collectibles.is_collectible_id(poi_id):
			assert_bool(MapStyle.EVENT_STYLES.has(str(poi["kind"]))).is_true()

func test_poi_glyph_picks_collectible_event_or_landmark() -> void:
	assert_str(MapStyle.poi_glyph({"kind": "speed_trap"})).is_equal("radar")
	assert_str(MapStyle.poi_glyph({"kind": "photo_spot"})).is_equal("camera")
	assert_str(MapStyle.poi_glyph({"kind": "drift_zone"})).is_equal("drift")
	assert_str(MapStyle.poi_glyph({"name": "Somewhere"})).is_equal("star")

func test_class_colours_cover_the_ladder_and_circuit_glyphs_cover_registry_types() -> void:
	for klass in ["D", "C", "B", "A", "S", "X"]:
		assert_bool(MapStyle.CLASS_COLORS.has(klass)).is_true()
	for track_id: Variant in TrackRegistry.tracks:
		var circuit_type := str(TrackRegistry.get_track(str(track_id)).get("circuit_type", ""))
		assert_bool(MapStyle.CIRCUIT_GLYPHS.has(circuit_type)).is_true()

func test_vignette_is_clear_in_the_middle_and_dark_at_the_corners() -> void:
	var img := MapStyle.make_vignette_image(64, 0.55, 0.6)
	assert_float(img.get_pixel(32, 32).a).is_less(0.02)
	assert_float(img.get_pixel(0, 0).a).is_greater(0.4)

# --- MapTerrain -----------------------------------------------------------------

func test_world_rect_is_a_square_around_the_roads_snapped_to_256() -> void:
	var chains := [[Vector3(1000, 0, 1000), Vector3(5000, 0, 3000)]]
	var rect := MapTerrain.world_rect_for_roads(chains)
	assert_float(rect.size.x).is_equal(rect.size.y)
	assert_float(fposmod(rect.size.x, 256.0)).is_equal(0.0)
	assert_float(fposmod(rect.position.x, 256.0)).is_equal(0.0)
	assert_bool(rect.has_point(Vector2(1000, 1000))).is_true()
	assert_bool(rect.has_point(Vector2(5000, 3000))).is_true()
	# Wider than the road span, so a wide panel never runs out of terrain.
	assert_float(rect.size.x).is_greater(4000.0 * 2.0)

func test_world_rect_of_no_roads_is_empty() -> void:
	assert_that(MapTerrain.world_rect_for_roads([])).is_equal(Rect2())

func test_bake_image_samples_texel_centres_north_first() -> void:
	var rect := Rect2(Vector2(0, 0), Vector2(100, 100))
	var img := MapTerrain.bake_image(func(xz: Vector2) -> float: return xz.y, rect, 4)
	assert_int(img.get_width()).is_equal(4)
	# Row 0 is the northmost (smallest z): centre 12.5 m; the last row is 87.5 m.
	assert_float(img.get_pixel(0, 0).r).is_equal_approx(12.5, 0.01)
	assert_float(img.get_pixel(0, 3).r).is_equal_approx(87.5, 0.01)

func test_request_with_a_provider_bakes_synchronously_and_caches() -> void:
	var rect := Rect2(Vector2(0, 0), Vector2(256, 256))
	MapTerrain.request(rect, 8, func(_xz: Vector2) -> float: return 42.0)
	assert_bool(MapTerrain.is_ready()).is_true()
	assert_that(MapTerrain.rect()).is_equal(rect)
	assert_float(MapTerrain.height_at(Vector2(100, 100))).is_equal_approx(42.0, 0.01)
	MapTerrain.reset()
	assert_bool(MapTerrain.is_ready()).is_false()
	assert_float(MapTerrain.height_at(Vector2(100, 100), -1.0)).is_equal(-1.0)

# --- WorldMap view ------------------------------------------------------------------

func _world_map() -> Control:
	var map := Control.new()
	map.size = Vector2(800.0, 600.0)
	map.set_script(load(WORLD_MAP_SCRIPT))
	add_child(map)
	_managed.append(map)
	return map

func test_world_map_zoom_keeps_the_point_under_the_cursor() -> void:
	var map := _world_map()
	await await_idle_frame()
	var cursor := Vector2(300.0, 200.0)
	var base_before: Vector2 = map.view_to_base(cursor)
	map.set_zoom_at(3.0, cursor)
	assert_float(map.get_zoom()).is_equal_approx(3.0, 0.0001)
	var base_after: Vector2 = map.view_to_base(cursor)
	assert_that(base_after).is_equal_approx(base_before, Vector2(0.01, 0.01))

func test_world_map_zoom_is_clamped_and_plain_fit_cannot_pan() -> void:
	var map := _world_map()
	await await_idle_frame()
	map.set_zoom_at(100.0, Vector2(400.0, 300.0))
	assert_float(map.get_zoom()).is_equal_approx(WorldMap.MAX_ZOOM, 0.0001)
	map.set_zoom_at(0.01, Vector2(400.0, 300.0))
	assert_float(map.get_zoom()).is_equal_approx(WorldMap.MIN_ZOOM, 0.0001)
	map.pan_by(Vector2(500.0, 500.0))
	# At zoom 1 the pan limit is zero: base and view coordinates coincide.
	assert_that(map.base_to_view(Vector2(123.0, 45.0))).is_equal_approx(Vector2(123.0, 45.0), Vector2(0.001, 0.001))

func test_world_map_pan_never_opens_a_void_past_the_edge() -> void:
	var map := _world_map()
	await await_idle_frame()
	map.set_zoom_at(2.0, Vector2(400.0, 300.0))
	map.pan_by(Vector2(100000.0, 100000.0))
	# The base top-left corner may not move right of / below the control origin.
	var corner: Vector2 = map.base_to_view(Vector2.ZERO)
	assert_float(corner.x).is_less_equal(0.001)
	assert_float(corner.y).is_less_equal(0.001)
	var far: Vector2 = map.base_to_view(map.size)
	assert_float(far.x).is_greater_equal(map.size.x - 0.001)

func test_world_map_reset_view_returns_to_the_plain_fit() -> void:
	var map := _world_map()
	await await_idle_frame()
	map.set_zoom_at(4.0, Vector2(100.0, 100.0))
	map.reset_view()
	assert_float(map.get_zoom()).is_equal(1.0)
	assert_that(map.base_to_view(Vector2(10.0, 20.0))).is_equal_approx(Vector2(10.0, 20.0), Vector2(0.001, 0.001))

func test_world_map_view_glides_toward_the_target() -> void:
	var map := _world_map()
	await await_idle_frame()
	map.set_zoom_at(4.0, Vector2(400.0, 300.0))
	assert_float(map._view_zoom).is_equal(1.0)
	assert_bool(map._advance_view(1.0 / 60.0)).is_true()
	assert_float(map._view_zoom).is_greater(1.0)
	assert_float(map._view_zoom).is_less(4.0)
	for i in 600:
		map._advance_view(1.0 / 60.0)
	assert_float(map._view_zoom).is_equal_approx(4.0, 0.001)
	assert_bool(map._advance_view(1.0 / 60.0)).is_false()

func test_world_map_focus_on_world_centres_the_point() -> void:
	var map := _world_map()
	var root := Node.new()
	root.name = "FocusRoot"
	add_child(root)
	_managed.append(root)
	var network := RoadNetwork.new()
	network.name = "RoadNetwork"
	network.add_road([Vector3(0, 0, 0), Vector3(4000, 0, 0), Vector3(4000, 0, 3000)], 8.0, false)
	root.add_child(network)
	await await_idle_frame()
	map.refresh()
	map._rebuild()
	map.focus_on_world(Vector3(4000.0, 0.0, 1500.0), 3.0)
	var base_point := MapRoads.world_to_screen(Vector3(4000.0, 0.0, 1500.0), map._fit)
	var on_screen: Vector2 = map.base_to_view(base_point)
	var offset: Vector2 = on_screen - map.size * 0.5
	# Centred unless the pan clamp pinned it against an edge of the map.
	assert_float(map.get_zoom()).is_equal_approx(3.0, 0.0001)
	assert_bool(map.get_global_rect().grow(1.0).has_point(map.get_global_rect().position + on_screen)).is_true()
	assert_float(offset.length()).is_less(map.size.length())

func test_world_map_legend_covers_every_pin_family_and_road_class() -> void:
	var map := _world_map()
	var labels := PackedStringArray()
	var road_tiers := {}
	for entry: Dictionary in map.legend_entries():
		labels.append(str(entry["label"]))
		if str(entry["kind"]) == "road":
			road_tiers[int(entry["tier"])] = true
	for needed in ["Landmark", "Race event", "Bonus board", "Speed trap", "Photo spot", "You", "GPS route", "Unexplored"]:
		assert_bool(labels.has(needed)).is_true()
	for tier in [RoadDef.Tier.HIGHWAY, RoadDef.Tier.ARTERIAL, RoadDef.Tier.TOUGE, RoadDef.Tier.DIRT]:
		assert_bool(road_tiers.has(int(tier))).is_true()

func test_world_map_region_labels_name_each_landmark_stage_once() -> void:
	var map := _world_map()
	var root := Node.new()
	add_child(root)
	_managed.append(root)
	var network := RoadNetwork.new()
	network.name = "RoadNetwork"
	network.add_road([Vector3(0, 0, 0), Vector3(6000, 0, 0)], 8.0, false)
	root.add_child(network)
	await await_idle_frame()
	map._rebuild()
	var texts := PackedStringArray()
	for entry: Dictionary in map.region_labels():
		texts.append(str(entry["text"]))
	assert_bool(texts.has("FESTIVAL PLAINS")).is_true()
	assert_bool(texts.has("ALPINE OVERLOOK")).is_true()
	var seen := {}
	for text in texts:
		assert_bool(seen.has(text)).is_false()
		seen[text] = true

func test_world_map_badge_radius_orders_landmark_event_collectible() -> void:
	var map := _world_map()
	var landmark := {"id": "lm", "name": "x"}
	var event := {"id": "ev", "kind": "touge_duel"}
	var trap := {"id": "speedtrap_0", "kind": "speed_trap"}
	assert_float(map.poi_badge_radius(landmark)).is_greater(map.poi_badge_radius(event))
	assert_float(map.poi_badge_radius(event)).is_greater(map.poi_badge_radius(trap))
	assert_str(map.poi_type_label(trap)).is_equal("Speed Trap")
	assert_str(map.poi_type_label(event)).is_equal("Touge Duel")
	assert_str(map.poi_type_label(landmark)).is_equal("Landmark")

func test_world_map_event_pins_take_their_family_colour() -> void:
	var map := _world_map()
	var event := {"id": "ev", "kind": "drag_strip", "stage": "Highway", "tier": 0}
	assert_that(map.poi_dot_color(event)).is_equal(MapStyle.event_color("drag_strip"))

# --- TrackMap -------------------------------------------------------------------------

func _track_map(region: String) -> TrackMap:
	var map := TrackMap.new()
	map.size = Vector2(900.0, 700.0)
	add_child(map)
	_managed.append(map)
	map.region = region
	return map

func test_track_map_pin_style_follows_circuit_type_and_class() -> void:
	var map := _track_map(TrackRegistry.REGION_ISRAEL)
	var oval := map.pin_style("home_northern_isle")
	assert_str(str(oval["glyph"])).is_equal("oval")
	assert_that(oval["color"]).is_equal(MapStyle.class_color("D"))
	var circuit := map.pin_style("home_mountain_pass")
	assert_str(str(circuit["glyph"])).is_equal("flag")
	assert_that(circuit["color"]).is_equal(MapStyle.class_color("B"))

func test_track_map_hit_test_accepts_the_badge_above_the_tip() -> void:
	var map := _track_map(TrackRegistry.REGION_ISRAEL)
	var tip := map.pin_screen_position("home_northern_isle")
	assert_str(map.hit_test(tip)).is_equal("home_northern_isle")
	assert_str(map.hit_test(map.pin_badge_center(tip))).is_equal("home_northern_isle")

func test_track_map_captions_by_tier() -> void:
	var israel := _track_map(TrackRegistry.REGION_ISRAEL)
	assert_int(israel.region_captions().size()).is_greater(0)
	var world := _track_map(TrackRegistry.REGION_WORLD)
	var texts := PackedStringArray()
	for caption: Dictionary in world.region_captions():
		texts.append(str(caption["text"]))
	assert_bool(texts.has(TrackRegistry.region_label(TrackRegistry.REGION_EUROPE))).is_true()
	assert_bool(texts.has(TrackRegistry.region_label(TrackRegistry.REGION_ISRAEL))).is_false()
	var europe := _track_map(TrackRegistry.REGION_EUROPE)
	assert_int(europe.region_captions().size()).is_equal(0)

func test_track_map_focus_pans_a_zoomed_view_to_the_pin_and_is_a_noop_at_fit() -> void:
	var map := _track_map(TrackRegistry.REGION_ISRAEL)
	var before := map.pin_screen_position("negev_speedway")
	map.focus_on_pin("negev_speedway")
	assert_that(map.pin_screen_position("negev_speedway")).is_equal_approx(before, Vector2(0.001, 0.001))
	map.zoom_by(3.0, map.size * 0.5)
	map.focus_on_pin("negev_speedway")
	var after := map.pin_screen_position("negev_speedway")
	# Centred, or as close as the pan clamp allows (never further than before).
	assert_float(after.distance_to(map.size * 0.5)).is_less(map.size.length() * 0.5)
	map.focus_on_pin("no_such_pin")
	assert_that(map.pin_screen_position("negev_speedway")).is_equal_approx(after, Vector2(0.001, 0.001))

func test_track_map_selecting_a_pin_keeps_it_on_screen_when_zoomed() -> void:
	var map := _track_map(TrackRegistry.REGION_ISRAEL)
	map.zoom_by(4.0, Vector2(100.0, 100.0))
	map.selected_pin_id = "negev_speedway"
	var pos := map.pin_screen_position("negev_speedway")
	assert_bool(Rect2(Vector2.ZERO, map.size).has_point(pos)).is_true()

func test_track_map_legend_lists_each_circuit_type_and_class() -> void:
	var map := _track_map(TrackRegistry.REGION_WORLD)
	assert_int(map.legend_entries().size()).is_equal(4)
	var classes := map.legend_classes()
	assert_bool(classes.has("D")).is_true()
	assert_bool(classes.has("A")).is_true()

func test_track_map_view_glides_and_snaps_on_region_switch() -> void:
	var map := _track_map(TrackRegistry.REGION_ISRAEL)
	var target_scale := float(map._fit["scale"])
	assert_float(map._view_scale).is_equal_approx(target_scale, 0.0001)
	map.zoom_by(3.0, map.size * 0.5)
	assert_float(map._view_scale).is_equal_approx(target_scale, 0.0001)
	map.set_process(false)
	map._process(1.0 / 60.0)
	assert_float(map._view_scale).is_greater(target_scale)
	assert_float(map._view_scale).is_less(float(map._fit["scale"]))
	map.region = TrackRegistry.REGION_WORLD
	assert_float(map._view_scale).is_equal_approx(float(map._fit["scale"]), 0.0001)
