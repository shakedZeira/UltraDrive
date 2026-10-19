extends GdUnitTestSuite

## Gate for the race-menu circuit map (docs/plans/race_menu_world_map_plan.md):
## the additive TrackRegistry pin table, the equirectangular projection, and the
## menu's pin<->card selection. Pure-data and projection tests need no scene;
## the menu tests mirror tests/test_track_system.gd (scene_runner + 2 frames).

const ISRAEL := TrackRegistry.REGION_ISRAEL
const WORLD := TrackRegistry.REGION_WORLD

# --- registry / data contract ------------------------------------------------

func test_pins_are_well_formed_and_point_at_real_layouts() -> void:
	var ids := TrackRegistry.get_pin_ids()
	assert_that(ids.size()).is_greater_equal(1)
	var seen: Dictionary = {}
	for pin_id: Variant in ids:
		var id := str(pin_id)
		assert_that(seen.has(id)).is_false()
		seen[id] = true
		var pin := TrackRegistry.get_pin(id)
		assert_that(str(pin.get("label", "")).is_empty()).is_false()
		var region_id := str(pin.get("region", ""))
		assert_that(TrackRegistry.has_region(region_id)).is_true()
		var lat := float(pin.get("lat", 1000.0))
		var lon := float(pin.get("lon", 1000.0))
		assert_that(lat).is_greater_equal(-90.0)
		assert_that(lat).is_less_equal(90.0)
		assert_that(lon).is_greater_equal(-180.0)
		assert_that(lon).is_less_equal(180.0)
		var track_id := str(pin.get("track_id", ""))
		assert_that(TrackRegistry.has_track(track_id)).is_true()
		assert_that(TrackRegistry.get_scene_path(track_id).is_empty()).is_false()

func test_every_layout_has_at_least_one_pin() -> void:
	# The pin table is many-to-one: several circuits share one fictional layout.
	# NOTE: the plan prose says "3 pins per layout", but its own pin TABLE yields
	# 4/3/2 (mountain_pass = Haifa + Silverstone + Spa + Nurburgring). The table
	# is the spec of record, so this asserts the contract that actually matters:
	# every shipped layout is reachable and no pin is orphaned.
	var covered := 0
	for track_id: String in TrackRegistry.get_track_ids():
		var pins := TrackRegistry.pins_for_track(track_id)
		assert_that(pins.size()).is_greater_equal(1)
		covered += pins.size()
	assert_that(covered).is_equal(TrackRegistry.get_pin_ids().size())

func test_default_region_is_israel_and_holds_at_least_three_pins() -> void:
	assert_that(TrackRegistry.DEFAULT_REGION).is_equal(ISRAEL)
	assert_that(TrackRegistry.pin_ids_for_region(ISRAEL).size()).is_greater_equal(3)
	# Every pin's placement actually lies inside its own region framing box.
	for pin_id: Variant in TrackRegistry.get_pin_ids():
		var pin := TrackRegistry.get_pin(str(pin_id))
		var bounds := TrackRegistry.region_bounds(str(pin.get("region", "")))
		assert_that(bounds.is_empty()).is_false()
		assert_that(float(pin.get("lon", 0.0))).is_greater_equal(float(bounds.get("min_lon", 0.0)))
		assert_that(float(pin.get("lon", 0.0))).is_less_equal(float(bounds.get("max_lon", 0.0)))
		assert_that(float(pin.get("lat", 0.0))).is_greater_equal(float(bounds.get("min_lat", 0.0)))
		assert_that(float(pin.get("lat", 0.0))).is_less_equal(float(bounds.get("max_lat", 0.0)))

# --- projection --------------------------------------------------------------

func test_lonlat_uv_round_trip() -> void:
	# Equirectangular, Y-DOWN to match the 360x180 world SVG (its own transform is
	# translate(180,90) scale(1,-1), i.e. v = (90 - lat) / 180). The plan's §4
	# corner literals were written Y-UP; the asset is y-down, so north is v=0 and
	# south is v=1. Everything else in the plan matches.
	assert_that(WorldMapProjection.lonlat_to_uv(-90.0, -180.0)).is_equal(Vector2(0.0, 1.0))
	assert_that(WorldMapProjection.lonlat_to_uv(90.0, 180.0)).is_equal(Vector2(1.0, 0.0))
	assert_that(WorldMapProjection.lonlat_to_uv(0.0, 0.0)).is_equal(Vector2(0.5, 0.5))
	var samples: Array[Vector2] = [
		Vector2(-90.0, -180.0), Vector2(32.794, 34.9896),
		Vector2(-23.7036, -46.6997), Vector2(90.0, 180.0),
	]
	for s: Vector2 in samples:
		var back := WorldMapProjection.uv_to_lonlat(WorldMapProjection.lonlat_to_uv(s.x, s.y))
		assert_that(back.x).is_equal_approx(s.y, 0.001)
		assert_that(back.y).is_equal_approx(s.x, 0.001)

func test_fit_puts_north_up_and_west_left() -> void:
	var draw_size := Vector2(720.0, 360.0)
	var fit := WorldMapProjection.build_fit(WORLD, draw_size, {})
	var origin: Vector2 = fit["origin"]
	var world_min: Vector2 = fit["world_min"]
	var world_max: Vector2 = fit["world_max"]
	var scale: float = fit["scale"]
	var span := world_max - world_min
	# The full equirectangular box maps onto the fitted content rect exactly.
	assert_that(WorldMapProjection.lonlat_to_screen(90.0, -180.0, fit)).is_equal(origin)
	assert_that(WorldMapProjection.lonlat_to_screen(-90.0, 180.0, fit)).is_equal(origin + span * scale)
	# North-up (lat 90 above lat -90) and west-left (lon -180 left of lon 180).
	var north_east := WorldMapProjection.lonlat_to_screen(90.0, 180.0, fit)
	var south_west := WorldMapProjection.lonlat_to_screen(-90.0, -180.0, fit)
	assert_that(north_east.y).is_less(south_west.y)
	assert_that(south_west.x).is_less(north_east.x)

func test_israel_fit_zooms_past_the_world_fit() -> void:
	var draw_size := Vector2(720.0, 360.0)
	var world_fit := WorldMapProjection.build_fit(WORLD, draw_size, {})
	var israel_fit := WorldMapProjection.build_fit(ISRAEL, draw_size, {})
	var world_scale: float = world_fit["scale"]
	var israel_scale: float = israel_fit["scale"]
	assert_that(israel_scale).is_greater(world_scale)
	var rect := Rect2(Vector2.ZERO, draw_size)
	for pin_id: Variant in TrackRegistry.pin_ids_for_region(ISRAEL):
		var p := WorldMapProjection.project_pin(TrackRegistry.get_pin(str(pin_id)), israel_fit)
		assert_that(rect.has_point(p)).is_true()
	# Every NON-Israeli pin must fall outside the Israel rect. (The old loop was
	# pin_ids_for_region(WORLD); now WORLD is the all-circuits overview tier and
	# would include the 6 Israeli pins, so skip them explicitly.)
	for pin_id: Variant in TrackRegistry.get_pin_ids():
		var pin := TrackRegistry.get_pin(str(pin_id))
		if str(pin.get("region", "")) == ISRAEL:
			continue
		var p := WorldMapProjection.project_pin(pin, israel_fit)
		assert_that(rect.has_point(p)).is_false()

func test_screen_to_lonlat_is_the_inverse_of_project() -> void:
	var draw_size := Vector2(900.0, 500.0)
	var fit := WorldMapProjection.build_fit(ISRAEL, draw_size, {})
	for pin_id: Variant in TrackRegistry.pin_ids_for_region(ISRAEL):
		var pin := TrackRegistry.get_pin(str(pin_id))
		var screen := WorldMapProjection.project_pin(pin, fit)
		var lonlat := WorldMapProjection.screen_to_lonlat(screen, fit)
		assert_that(lonlat.x).is_equal_approx(float(pin.get("lon")), 0.01)
		assert_that(lonlat.y).is_equal_approx(float(pin.get("lat")), 0.01)

# --- menu --------------------------------------------------------------------

func test_menu_lists_one_card_per_visible_pin() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	var visible := scene.track_map.visible_pin_ids()
	assert_that(visible.size()).is_equal(TrackRegistry.pin_ids_for_region(ISRAEL).size())
	assert_that(scene.get_card_count()).is_equal(visible.size())
	var grid := scene.get_node("%TrackGrid") as GridContainer
	assert_that(grid.get_child_count()).is_equal(visible.size())
	var cards: Array = grid.get_children()
	for i in cards.size():
		var pin := TrackRegistry.get_pin(visible[i])
		var layout := TrackRegistry.get_track(TrackRegistry.track_for_pin(visible[i]))
		var card_text := _collect_label_text(cards[i])
		assert_that(card_text).contains(str(pin.get("label")))
		assert_that(card_text).contains("CLASS %s" % layout.get("difficulty"))

func test_pin_click_selects_the_pin() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	var map := scene.track_map
	map.size = Vector2(800.0, 600.0)
	var point := map.pin_screen_position("negev_speedway")
	assert_that(map.hit_test(point)).is_equal("negev_speedway")
	scene.select_pin(map.hit_test(point))
	assert_that(scene.get_selected_pin_id()).is_equal("negev_speedway")
	assert_that(scene.get_selected_scene_path()).is_equal(TrackRegistry.get_scene_path("oval"))

func test_region_toggle_switches_pins_and_backdrop() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	assert_that(scene.region).is_equal(ISRAEL)
	assert_that(scene.track_map.is_vector_backdrop()).is_true()
	scene.set_region(WORLD)
	assert_that(scene.track_map.visible_pin_ids().size()).is_equal(TrackRegistry.get_pin_ids().size())  # WORLD box = whole globe
	assert_that(scene.get_card_count()).is_equal(TrackRegistry.get_pin_ids().size())
	assert_that(scene.track_map.is_vector_backdrop()).is_false()
	assert_that(scene.track_map.visible_pin_ids().has(scene.get_selected_pin_id())).is_true()
	scene.set_region(ISRAEL)
	assert_that(scene.track_map.visible_pin_ids().size()).is_equal(TrackRegistry.pin_ids_for_region(ISRAEL).size())
	assert_that(scene.get_card_count()).is_equal(TrackRegistry.pin_ids_for_region(ISRAEL).size())
	assert_that(scene.track_map.is_vector_backdrop()).is_true()
	assert_that(scene.track_map.visible_pin_ids().has(scene.get_selected_pin_id())).is_true()

func test_play_queues_the_selected_pins_laps() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	var launched: Array[String] = []
	scene.launch_callback = func(path: String) -> void: launched.append(path)
	scene.select_pin("spa")
	assert_that(scene.get_selected_scene_path()).is_equal(TrackRegistry.get_scene_path("mountain_pass"))
	scene._on_play_pressed()
	assert_that(launched).is_equal([TrackRegistry.get_scene_path("mountain_pass")])
	assert_that(RaceManager.consume_pending_race()).is_equal(2)
	RaceManager.consume_pending_race()

func test_legacy_select_track_still_resolves_a_pin() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	scene.select_track("northern_isle")
	# Intended improvement: the shipped `home_*` pins precede the invented
	# Israeli ones, so the compat wrapper now lands on the pin whose LABEL is the
	# layout's own display_name ("Northern Isle Speedway"), not "galilee_circuit".
	# Records still key per LAYOUT, so the scene path is unchanged.
	assert_that(scene.get_selected_pin_id()).is_equal("home_northern_isle")
	assert_that(scene.get_selected_scene_path()).is_equal(TrackRegistry.get_scene_path("northern_isle"))

# --- expansion: data contract ------------------------------------------------

func test_shipped_layouts_have_a_pin_labelled_with_their_display_name() -> void:
	# Complaint-1 lock: every shipped layout must be recognisable on the map, so
	# some pin driving it carries the layout's EXACT display_name as its label.
	for track_id: String in TrackRegistry.get_track_ids():
		var display := str(TrackRegistry.get_track(track_id).get("display_name", ""))
		var found := false
		for pin_id: Variant in TrackRegistry.pins_for_track(track_id):
			if str(TrackRegistry.get_pin(str(pin_id)).get("label", "")) == display:
				found = true
				break
		assert_that(found).is_true()

func test_shipped_layout_pins_are_the_first_table_entries() -> void:
	# The first three pins must be the shipped layouts, so the default selection
	# (pins[0]) is a real game track, not an invented circuit.
	var ids := TrackRegistry.get_pin_ids()
	assert_that(ids.size()).is_greater_equal(3)
	for i in 3:
		var pin := TrackRegistry.get_pin(str(ids[i]))
		assert_that(str(pin.get("region", ""))).is_equal(ISRAEL)
		assert_that(TrackRegistry.has_track(str(pin.get("track_id", "")))).is_true()

func test_layout_distribution_is_balanced() -> void:
	# Every layout reachable (floor) and no layout over half the calendar (cap).
	var total := TrackRegistry.get_pin_ids().size()
	assert_that(total).is_greater(0)
	for track_id: String in TrackRegistry.get_track_ids():
		var n := TrackRegistry.pins_for_track(track_id).size()
		assert_that(n).is_greater_equal(3)
		assert_that(float(n) / float(total)).is_less_equal(0.5)

func test_world_region_has_a_full_calendar() -> void:
	assert_that(TrackRegistry.pin_ids_for_region(WORLD).size()).is_greater_equal(30)

# --- expansion: pure label de-clumping ---------------------------------------

func test_select_label_ids_always_keeps_priority_pins() -> void:
	var anchors: Array = [
		{"id": "a", "pos": Vector2(0.0, 0.0)},
		{"id": "b", "pos": Vector2(10.0, 0.0)},
	]
	var priority := PackedStringArray(["b"])
	var ids := TrackMap.select_label_ids(anchors, 64.0, priority)
	assert_that(ids).contains("b")
	assert_that(ids.size()).is_equal(1)

func test_select_label_ids_drops_anchors_within_min_separation() -> void:
	var anchors: Array = [
		{"id": "a", "pos": Vector2(0.0, 0.0)},
		{"id": "b", "pos": Vector2(30.0, 0.0)},
		{"id": "c", "pos": Vector2(60.0, 0.0)},
	]
	var ids := TrackMap.select_label_ids(anchors, 64.0, PackedStringArray())
	var expected: Array[String] = ["a"]
	assert_that(ids).is_equal(expected)

func test_select_label_ids_accepts_well_spaced_anchors() -> void:
	var anchors: Array = [
		{"id": "a", "pos": Vector2(0.0, 0.0)},
		{"id": "b", "pos": Vector2(100.0, 0.0)},
		{"id": "c", "pos": Vector2(200.0, 0.0)},
	]
	var ids := TrackMap.select_label_ids(anchors, 64.0, PackedStringArray())
	var expected: Array[String] = ["a", "b", "c"]
	assert_that(ids).is_equal(expected)

func test_select_label_ids_is_deterministic() -> void:
	var anchors: Array = [
		{"id": "a", "pos": Vector2(0.0, 0.0)},
		{"id": "b", "pos": Vector2(30.0, 0.0)},
		{"id": "c", "pos": Vector2(200.0, 0.0)},
	]
	var first := TrackMap.select_label_ids(anchors, 64.0, PackedStringArray(["c"]))
	var second := TrackMap.select_label_ids(anchors, 64.0, PackedStringArray(["c"]))
	assert_that(first).is_equal(second)

func test_world_tier_labels_never_collide() -> void:
	# The invariant, on real data: every pair of accepted labels is >= the min
	# separation apart (the greedy pass guarantees it; one priority pin cannot
	# break it because it is accepted before any greedy anchor).
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	var map := scene.track_map
	map.size = Vector2(1000.0, 640.0)
	scene.set_region(WORLD)
	var positions: Array[Vector2] = []
	for pin_id: String in map.labelled_pin_ids():
		positions.append(map.pin_screen_position(pin_id))
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			assert_that(positions[i].distance_to(positions[j])).is_greater_equal(TrackMap.LABEL_MIN_SEP_PX)

# --- expansion: menu ---------------------------------------------------------

func test_default_selection_drives_a_shipped_layout() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	assert_that(TrackRegistry.get_track_ids().has(scene.get_selected_track_id())).is_true()
	var grid := scene.get_node("%TrackGrid") as GridContainer
	var cards: Array = grid.get_children()
	assert_that(cards.size()).is_greater_equal(1)
	assert_that(_collect_label_text(cards[0])).contains("Sunset Oval")

func test_shipped_pins_are_reachable() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	scene.select_pin("home_northern_isle")
	assert_that(scene.get_selected_scene_path()).is_equal(TrackRegistry.get_scene_path("northern_isle"))
	scene.select_pin("home_mountain_pass")
	assert_that(scene.get_selected_scene_path()).is_equal(TrackRegistry.get_scene_path("mountain_pass"))
	scene.select_pin("home_sunset_oval")
	assert_that(scene.get_selected_scene_path()).is_equal(TrackRegistry.get_scene_path("oval"))

# --- continents + zoom (docs/plans/race_menu_regions_zoom_plan.md) -----------

# --- regions: data contract --------------------------------------------------

func test_every_pin_has_a_continent_region() -> void:
	# Every pin is tagged with a REAL region id, and never with the WORLD
	# overview tier (WORLD membership is derived, never a stored pin region).
	for pin_id: Variant in TrackRegistry.get_pin_ids():
		var region_id := str(TrackRegistry.get_pin(str(pin_id)).get("region", ""))
		assert_that(TrackRegistry.has_region(region_id)).is_true()
		assert_that(region_id == WORLD).is_false()

func test_region_ids_are_complete() -> void:
	var expected: Array = [
		WORLD,
		TrackRegistry.REGION_ISRAEL,
		TrackRegistry.REGION_EUROPE,
		TrackRegistry.REGION_MIDDLE_EAST,
		TrackRegistry.REGION_NORTH_AMERICA,
		TrackRegistry.REGION_ASIA,
		TrackRegistry.REGION_SOUTH_AMERICA,
		TrackRegistry.REGION_AFRICA,
		TrackRegistry.REGION_OCEANIA,
	]
	# Order-sensitive: insertion order is the menu tab order.
	assert_that(TrackRegistry.get_region_ids()).contains_exactly(expected)
	for region_id: Variant in TrackRegistry.get_region_ids():
		var meta := TrackRegistry.region_meta(str(region_id))
		assert_that(meta.is_empty()).is_false()
		assert_that(float(meta.get("min_lon", 0.0))).is_less(float(meta.get("max_lon", 0.0)))
		assert_that(float(meta.get("min_lat", 0.0))).is_less(float(meta.get("max_lat", 0.0)))

func test_world_region_is_the_full_overview() -> void:
	assert_that(TrackRegistry.pin_ids_for_region(WORLD).size()).is_equal(TrackRegistry.get_pin_ids().size())

func test_pin_regions_partition_the_pin_table() -> void:
	# The eight non-WORLD regions partition the pin table: the union covers every
	# pin and no pin appears in two regions. Each region has a real framing box
	# and at least one member.
	var seen: Dictionary = {}
	var union: Array = []
	for region_id: Variant in TrackRegistry.get_region_ids():
		var rid := str(region_id)
		if rid == WORLD:
			continue
		assert_that(TrackRegistry.region_bounds(rid).is_empty()).is_false()
		var members := TrackRegistry.pin_ids_for_region(rid)
		assert_that(members.size()).is_greater_equal(1)
		for pin_id: Variant in members:
			var id := str(pin_id)
			assert_that(seen.has(id)).is_false()
			seen[id] = true
			union.append(id)
	assert_that(union.size()).is_equal(TrackRegistry.get_pin_ids().size())

func test_continent_membership_is_stable() -> void:
	# Locked membership AND order (contains_exactly is order-sensitive): each
	# continent frames a fixed set in pin-table order, so a retag cannot silently
	# move a circuit to a different region.
	var expected: Dictionary = {
		TrackRegistry.REGION_EUROPE: [
			"silverstone", "spa", "nurburgring", "monza", "monaco", "imola",
			"zandvoort", "spielberg", "portimao", "hungaroring", "barcelona",
			"holjes", "loheac", "le_mans", "brands_hatch", "hockenheim",
		],
		TrackRegistry.REGION_MIDDLE_EAST: ["bahrain", "jeddah", "abu_dhabi"],
		TrackRegistry.REGION_NORTH_AMERICA: [
			"watkins_glen", "laguna_seca", "cota", "miami", "las_vegas",
			"daytona", "indianapolis", "sebring",
		],
		TrackRegistry.REGION_ASIA: ["suzuka", "fuji", "sepang"],
		TrackRegistry.REGION_SOUTH_AMERICA: ["interlagos"],
		TrackRegistry.REGION_AFRICA: ["kyalami"],
		TrackRegistry.REGION_OCEANIA: ["bathurst"],
		TrackRegistry.REGION_ISRAEL: [
			"home_sunset_oval", "home_mountain_pass", "home_northern_isle",
			"haifa_coastal_ring", "galilee_circuit", "negev_speedway",
		],
	}
	for region_id: Variant in expected.keys():
		assert_that(TrackRegistry.pin_ids_for_region(str(region_id))).contains_exactly(expected[region_id])
	assert_that(TrackRegistry.pin_ids_for_region(WORLD)).contains_exactly(TrackRegistry.get_pin_ids())

# --- zoom: pure statics ------------------------------------------------------

func test_zoom_fit_at_factor_one_is_identity() -> void:
	var base := WorldMapProjection.build_fit(WORLD, Vector2(720.0, 360.0), {})
	var zoomed := TrackMap.zoom_fit(base, 1.0, Vector2(360.0, 180.0))
	var base_origin: Vector2 = base["origin"]
	var base_min: Vector2 = base["world_min"]
	var base_max: Vector2 = base["world_max"]
	var zoom_origin: Vector2 = zoomed["origin"]
	var zoom_min: Vector2 = zoomed["world_min"]
	var zoom_max: Vector2 = zoomed["world_max"]
	assert_that(zoom_origin).is_equal_approx(base_origin, Vector2(0.0001, 0.0001))
	assert_that(float(zoomed["scale"])).is_equal_approx(float(base["scale"]), 0.0001)
	assert_that(zoom_min).is_equal_approx(base_min, Vector2(0.0001, 0.0001))
	assert_that(zoom_max).is_equal_approx(base_max, Vector2(0.0001, 0.0001))

func test_zoom_fit_scales_about_focus() -> void:
	var base := WorldMapProjection.build_fit(WORLD, Vector2(720.0, 360.0), {})
	# Anchor on the point under the cursor: Silverstone's screen position.
	var focus := WorldMapProjection.lonlat_to_screen(52.0786, -1.0169, base)
	var zoomed := TrackMap.zoom_fit(base, 2.0, focus)
	assert_that(float(zoomed["scale"])).is_equal_approx(float(base["scale"]) * 2.0, 0.0001)
	assert_that(WorldMapProjection.lonlat_to_screen(52.0786, -1.0169, zoomed)).is_equal_approx(focus, Vector2(0.001, 0.001))

func test_pan_fit_translates_only() -> void:
	var base := WorldMapProjection.build_fit(WORLD, Vector2(720.0, 360.0), {})
	var delta := Vector2(30.0, -20.0)
	var panned := TrackMap.pan_fit(base, delta)
	var base_origin: Vector2 = base["origin"]
	var base_min: Vector2 = base["world_min"]
	var base_max: Vector2 = base["world_max"]
	var pan_origin: Vector2 = panned["origin"]
	var pan_min: Vector2 = panned["world_min"]
	var pan_max: Vector2 = panned["world_max"]
	assert_that(pan_origin).is_equal_approx(base_origin + delta, Vector2(0.0001, 0.0001))
	assert_that(float(panned["scale"])).is_equal_approx(float(base["scale"]), 0.0001)
	assert_that(pan_min).is_equal_approx(base_min, Vector2(0.0001, 0.0001))
	assert_that(pan_max).is_equal_approx(base_max, Vector2(0.0001, 0.0001))

func test_clamp_pan_centres_when_content_is_small() -> void:
	# content = (100, 50) at scale 1 < view (1000, 600) -> centred on both axes.
	var fit: Dictionary = {
		"origin": Vector2(500.0, 500.0),
		"scale": 1.0,
		"world_min": Vector2.ZERO,
		"world_max": Vector2(100.0, 50.0),
	}
	var clamped := TrackMap.clamp_pan(fit, Vector2(1000.0, 600.0))
	var clamped_origin: Vector2 = clamped["origin"]
	assert_that(clamped_origin).is_equal_approx(Vector2(450.0, 275.0), Vector2(0.0001, 0.0001))

func test_clamp_pan_bounds_when_content_is_large() -> void:
	# content = (2000, 1000) at scale 10 > view (1000, 600): no gap at an edge.
	var view := Vector2(1000.0, 600.0)
	var fit: Dictionary = {
		"origin": Vector2(500.0, 500.0),
		"scale": 10.0,
		"world_min": Vector2.ZERO,
		"world_max": Vector2(200.0, 100.0),
	}
	var top_left: Vector2 = TrackMap.clamp_pan(fit, view)["origin"]
	assert_that(top_left).is_equal_approx(Vector2.ZERO, Vector2(0.0001, 0.0001))
	fit["origin"] = Vector2(-5000.0, -5000.0)
	var bottom_right: Vector2 = TrackMap.clamp_pan(fit, view)["origin"]
	assert_that(bottom_right).is_equal_approx(Vector2(-1000.0, -400.0), Vector2(0.0001, 0.0001))

func test_zoom_is_clamped() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	var map := scene.track_map
	for _i in 20:
		map.zoom_by(10.0, map.size * 0.5)
	assert_that(map.get_zoom()).is_equal_approx(TrackMap.MAX_ZOOM, 0.0001)
	for _i in 40:
		map.zoom_by(0.1, map.size * 0.5)
	assert_that(map.get_zoom()).is_equal_approx(TrackMap.MIN_ZOOM, 0.0001)

func test_zoom_spreads_pin_positions() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	var map := scene.track_map
	map.size = Vector2(1000.0, 640.0)
	scene.set_region(TrackRegistry.REGION_EUROPE)
	var ids := map.visible_pin_ids()
	assert_that(ids.size()).is_greater_equal(2)
	var before := map.pin_screen_position(ids[0]).distance_to(map.pin_screen_position(ids[1]))
	map.zoom_by(TrackMap.ZOOM_STEP, map.size * 0.5)
	var after := map.pin_screen_position(ids[0]).distance_to(map.pin_screen_position(ids[1]))
	assert_that(after).is_greater(before)

func test_region_switch_resets_view() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	var map := scene.track_map
	map.size = Vector2(1000.0, 640.0)
	map.zoom_by(TrackMap.ZOOM_STEP, map.size * 0.5)
	assert_that(map.get_zoom()).is_greater(TrackMap.MIN_ZOOM)
	scene.set_region(TrackRegistry.REGION_EUROPE)
	assert_that(map.get_zoom()).is_equal_approx(TrackMap.MIN_ZOOM, 0.0001)

func test_resize_resets_view() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	var map := scene.track_map
	map.size = Vector2(1000.0, 640.0)
	map.zoom_by(TrackMap.ZOOM_STEP, map.size * 0.5)
	assert_that(map.get_zoom()).is_greater(TrackMap.MIN_ZOOM)
	map.size = Vector2(900.0, 600.0)
	# Force the lazy rebase in case the resize notification is deferred:
	# pin_screen_position -> _ensure_projection -> _update_projection.
	map.pin_screen_position(map.visible_pin_ids()[0])
	assert_that(map.get_zoom()).is_equal_approx(TrackMap.MIN_ZOOM, 0.0001)

func test_hit_test_follows_the_zoom() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	var map := scene.track_map
	map.size = Vector2(1000.0, 640.0)
	scene.set_region(TrackRegistry.REGION_EUROPE)
	var before := map.pin_screen_position("spa")
	map.zoom_by(2.0, map.size * 0.5)
	var after := map.pin_screen_position("spa")
	assert_that(after.distance_to(before)).is_greater(1.0)
	# Hit-testing reads the SAME zoomed fit, so the pin is still pickable.
	assert_that(map.hit_test(after)).is_equal("spa")
	# ... and still resolves at BOTH zoom extremes.
	for _i in 20:
		map.zoom_by(10.0, map.size * 0.5)
	assert_that(map.hit_test(map.pin_screen_position("spa"))).is_equal("spa")
	for _i in 40:
		map.zoom_by(0.1, map.size * 0.5)
	assert_that(map.get_zoom()).is_equal_approx(TrackMap.MIN_ZOOM, 0.0001)
	assert_that(map.hit_test(map.pin_screen_position("spa"))).is_equal("spa")

func test_continent_region_shows_only_its_pins() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	scene.set_region(TrackRegistry.REGION_EUROPE)
	# _build_cards() queue_frees the old cards; flush it before counting children.
	await runner.simulate_frames(2)
	var members := TrackRegistry.pin_ids_for_region(TrackRegistry.REGION_EUROPE)
	assert_that(scene.get_card_count()).is_equal(members.size())
	assert_that(scene.track_map.visible_pin_ids().size()).is_equal(members.size())
	var grid := scene.get_node("%TrackGrid") as GridContainer
	var cards: Array = grid.get_children()
	assert_that(cards.size()).is_equal(members.size())
	for i in cards.size():
		var expected_label := str(TrackRegistry.get_pin(str(members[i])).get("label"))
		assert_that(_collect_label_text(cards[i])).contains(expected_label)

func test_region_tabs_match_the_registry() -> void:
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	var tabs := scene.region_tabs
	var region_ids := TrackRegistry.get_region_ids()
	assert_that(tabs.get_child_count()).is_equal(region_ids.size())
	for i in region_ids.size():
		var rid := str(region_ids[i])
		var tab := tabs.get_child(i) as Button
		assert_that(tab.text).is_equal(TrackRegistry.region_label(rid))
		# Exactly the active region's tab is highlighted.
		assert_that(tab.button_pressed).is_equal(rid == scene.region)

# --- region framing regression: zoom + backdrop/pin alignment ----------------
# (user report: clicking e.g. EUROPE did not zoom the map and the circuit pins
# sat at an offset from their landmasses -- track_map._draw_world_backdrop used
# to stretch the WHOLE 360x180 raster over the region's framing rect.)

func test_region_view_contains_its_own_pins() -> void:
	# Selecting a region must frame THAT region: the fit zooms past the
	# whole-globe fit, and every pin the region shows projects inside the fitted
	# content rect, which itself stays within the view minus the framing inset.
	var draw_size := Vector2(1150.0, 740.0)
	var inset := WorldMapProjection.INSET
	var world_scale := float(WorldMapProjection.build_fit(WORLD, draw_size, {})["scale"])
	for region_id: Variant in TrackRegistry.get_region_ids():
		var rid := str(region_id)
		var fit := WorldMapProjection.build_fit(rid, draw_size, {})
		var origin: Vector2 = fit["origin"]
		var world_min: Vector2 = fit["world_min"]
		var world_max: Vector2 = fit["world_max"]
		var scale: float = fit["scale"]
		# A region fit is strictly tighter than the globe fit = it zoomed in.
		# (WORLD is the baseline itself -- same call, so it must match exactly.)
		if rid == WORLD:
			assert_that(scale).is_equal(world_scale)
		else:
			assert_that(scale).is_greater(world_scale)
		var content := Rect2(origin, (world_max - world_min) * scale)
		assert_that(content.position.x).is_greater_equal(inset - 0.01)
		assert_that(content.position.y).is_greater_equal(inset - 0.01)
		assert_that(content.end.x).is_less_equal(draw_size.x - inset + 0.01)
		assert_that(content.end.y).is_less_equal(draw_size.y - inset + 0.01)
		var members := TrackRegistry.pin_ids_for_region(rid)
		assert_that(members.size()).is_greater_equal(1)
		for pin_id: Variant in members:
			var screen := WorldMapProjection.project_pin(TrackRegistry.get_pin(str(pin_id)), fit)
			assert_that(content.grow(0.01).has_point(screen)).is_true()

func test_region_backdrop_crop_matches_the_pin_projection() -> void:
	# The pixel the backdrop DEPICTS for (lat, lon) must land exactly where the
	# projection puts its pin, for every raster tier. (Stretching the whole
	# raster over the region rect instead put Silverstone ~170 px west of the
	# UK in the Europe view: same screen math, wrong picture underneath.)
	var draw_size := Vector2(1150.0, 740.0)
	for region_id: Variant in TrackRegistry.get_region_ids():
		var rid := str(region_id)
		var bounds := TrackRegistry.region_bounds(rid)
		var uv_rect := WorldMapProjection.uv_rect_of_bounds(bounds)
		if rid == WORLD:
			# The overview tier draws the WHOLE raster -- unchanged behaviour.
			assert_that(uv_rect.position).is_equal(Vector2.ZERO)
			assert_that(uv_rect.size).is_equal(Vector2.ONE)
		else:
			# Every continent is a strict crop of it, never the whole globe.
			assert_that(uv_rect.size.x).is_less(1.0)
			assert_that(uv_rect.size.y).is_less(1.0)
		var fit := WorldMapProjection.build_fit(rid, draw_size, {})
		var origin: Vector2 = fit["origin"]
		var world_min: Vector2 = fit["world_min"]
		var world_max: Vector2 = fit["world_max"]
		var content := Rect2(origin, (world_max - world_min) * float(fit["scale"]))
		# Sample every member pin plus the four framing-box corners (lat, lon).
		var samples: Array[Vector2] = []
		for pin_id: Variant in TrackRegistry.pin_ids_for_region(rid):
			var pin := TrackRegistry.get_pin(str(pin_id))
			samples.append(Vector2(float(pin.get("lat", 0.0)), float(pin.get("lon", 0.0))))
		var min_lon := float(bounds.get("min_lon", -180.0))
		var min_lat := float(bounds.get("min_lat", -90.0))
		var max_lon := float(bounds.get("max_lon", 180.0))
		var max_lat := float(bounds.get("max_lat", 90.0))
		samples.append(Vector2(max_lat, min_lon))
		samples.append(Vector2(max_lat, max_lon))
		samples.append(Vector2(min_lat, min_lon))
		samples.append(Vector2(min_lat, max_lon))
		for s: Vector2 in samples:
			var screen := WorldMapProjection.lonlat_to_screen(s.x, s.y, fit)
			var uv := WorldMapProjection.lonlat_to_uv(s.x, s.y)
			# Where draw_texture_rect_region(dest = content, src = uv_rect * tex)
			# paints that lon/lat -- must equal the pin's screen position.
			var on_backdrop := content.position + (uv - uv_rect.position) / uv_rect.size * content.size
			assert_that(on_backdrop.distance_to(screen)).is_less(0.05)

func test_selecting_a_region_frames_pins_and_crops_the_backdrop() -> void:
	# The same lock through the menu: click EUROPE, then check the view AND the
	# rects _draw_world_backdrop() consumes (headless never runs _draw()).
	var runner := scene_runner("res://scenes/ui/track_select.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as TrackSelect
	var map := scene.track_map
	map.size = Vector2(1150.0, 740.0)
	scene.set_region(TrackRegistry.REGION_EUROPE)
	var view := Rect2(Vector2.ZERO, map.size)
	var tex_size := Vector2(360.0, 180.0) * TrackMap.WORLD_SVG_RASTER_SCALE
	var rects := map.world_backdrop_draw_rects(tex_size)
	var dest: Rect2 = rects["dest"]
	var src: Rect2 = rects["src"]
	var members := map.visible_pin_ids()
	assert_that(members.size()).is_greater_equal(1)
	for pin_id: String in members:
		var screen := map.pin_screen_position(pin_id)
		assert_that(view.has_point(screen)).is_true()
		# ... and inside the rect the backdrop is drawn into, not beside it.
		assert_that(dest.grow(0.01).has_point(screen)).is_true()
	# The backdrop source is CROPPED to Europe's box (regression: it used to be
	# the full raster, so the continent never zoomed and pins sat off-map).
	var expected := WorldMapProjection.uv_rect_of_bounds(
		TrackRegistry.region_bounds(TrackRegistry.REGION_EUROPE))
	var expected_src := Rect2(expected.position * tex_size, expected.size * tex_size)
	assert_that(src.position).is_equal(expected_src.position)
	assert_that(src.size).is_equal(expected_src.size)
	assert_that(src.size.x).is_less(tex_size.x)
	# The ALL CIRCUITS overview still draws the whole raster, unchanged.
	scene.set_region(WORLD)
	var world_src: Rect2 = map.world_backdrop_draw_rects(tex_size)["src"]
	assert_that(world_src.position).is_equal(Vector2.ZERO)
	assert_that(world_src.size).is_equal(tex_size)

func _collect_label_text(card: Node) -> String:
	var parts: Array[String] = []
	_collect_labels(card, parts)
	return " ".join(parts)

func _collect_labels(node: Node, parts: Array[String]) -> void:
	if node is Label:
		parts.append((node as Label).text)
	for child in node.get_children():
		_collect_labels(child, parts)
