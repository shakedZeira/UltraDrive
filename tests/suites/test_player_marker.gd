# tests/suites/test_player_marker.gd
extends GdUnitTestSuite

## "Who am I on the map?" gate: the player marker must be unmistakable on the
## HUD minimap AND the open-world pause map. Both draw one shared white-and-cyan
## chevron (MapRoads marker statics) that rotates with the car's heading and
## pulses a cyan halo, so the player pops over every terrain tint and every POI
## pin. All geometry/colour assertions are pure MapRoads math (headless-safe);
## map-level tests inject a fake height provider and a stub player car, then
## assert the cached draw state exactly like test_world_map_terrain.gd.

const WORLD_MAP_SCRIPT := "res://scripts/ui/world_map.gd"
const MINIMAP_SCRIPT := "res://scripts/ui/minimap.gd"
const BIOME_HEIGHTS := [-8.0, -2.0, 2.0, 8.0, 25.0, 60.0, 100.0, 400.0, 600.0, 800.0]

var _managed: Array = []

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	for node in _managed:
		if is_instance_valid(node):
			node.free()
	_managed.clear()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

func _fake_height_provider(constant: float) -> Callable:
	return func(xz: Vector2) -> float:
		return constant

func _stub_player(pos: Vector3) -> VehiclePhysics:
	var car := VehiclePhysics.new()
	car.name = "StubPlayer"
	car.position = pos
	VehicleManager.register_player_car(car)
	_managed.append(car)
	return car

func _new_network() -> Dictionary:
	var root := Node.new()
	root.name = "MarkerRoot"
	add_child(root)
	_managed.append(root)
	var network := RoadNetwork.new()
	network.name = "RoadNetwork"
	network.add_road([
		Vector3(0.0, 0.0, 0.0),
		Vector3(300.0, 0.0, 0.0),
		Vector3(300.0, 0.0, 300.0),
	], 8.0, false)
	root.add_child(network)
	return {"root": root, "network": network}

func test_shared_marker_style_is_consistent_across_maps() -> void:
	var style: Dictionary = MapRoads.marker_style()
	var minimap_script: GDScript = load(MINIMAP_SCRIPT)
	var world_map_script: GDScript = load(WORLD_MAP_SCRIPT)
	# The bundle is the single source of truth...
	assert_that(style["core"]).is_equal(MapRoads.MARKER_CORE)
	assert_that(style["accent"]).is_equal(MapRoads.MARKER_ACCENT)
	assert_that(style["outline"]).is_equal(MapRoads.MARKER_OUTLINE)
	assert_that(style["halo"]).is_equal(MapRoads.MARKER_HALO)
	assert_that(style["size"]).is_equal(MapRoads.MARKER_SIZE)
	# ...and both maps alias the SAME constants, so the player reads as one
	# object on the HUD minimap and on the pause-map.
	assert_that(minimap_script.MARKER_ACCENT).is_equal(MapRoads.MARKER_ACCENT)
	assert_that(world_map_script.MARKER_ACCENT).is_equal(MapRoads.MARKER_ACCENT)
	assert_that(minimap_script.MARKER_CORE).is_equal(world_map_script.MARKER_CORE)
	assert_that(minimap_script.MARKER_ACCENT).is_equal(world_map_script.MARKER_ACCENT)
	assert_that(minimap_script.MARKER_OUTLINE).is_equal(world_map_script.MARKER_OUTLINE)

func test_marker_rotation_matches_map_orientation() -> void:
	# Godot forward is -z; both maps are north-up with +z rendering downward
	# (world_to_local_points / compute_fit), so the heading appears on screen
	# along normalize(facing.x, facing.z): -z -> up, +x -> right, +z -> down.
	var north := Vector3(0.0, 0.0, -1.0)
	var east := Vector3(1.0, 0.0, 0.0)
	var south := Vector3(0.0, 0.0, 1.0)
	var west := Vector3(-1.0, 0.0, 0.0)
	assert_float(MapRoads.marker_world_angle(north)).is_equal_approx(-PI / 2.0, 0.0001)
	assert_float(MapRoads.marker_world_angle(east)).is_equal_approx(0.0, 0.0001)
	assert_float(MapRoads.marker_world_angle(south)).is_equal_approx(PI / 2.0, 0.0001)
	assert_float(MapRoads.marker_world_angle(west)).is_equal_approx(PI, 0.0001)
	# The minimap shares the same north-up convention (roads do not rotate).
	assert_float(MapRoads.marker_minimap_angle(north)).is_equal_approx(
		MapRoads.marker_world_angle(north), 0.0001)
	# The chevron direction equals where the point AHEAD of the player renders.
	var player := Vector3(10.0, 0.0, -20.0)
	var center := Vector2(50.0, 60.0)
	var zoom := 0.2
	var ahead := north * 100.0
	var screen_ahead: Vector2 = MapRoads.world_to_local_points(
		[player + ahead], player, center, zoom)[0] - center
	var draw_dir := Vector2(cos(MapRoads.marker_minimap_angle(ahead)),
		sin(MapRoads.marker_minimap_angle(ahead)))
	assert_that(draw_dir).is_equal_approx(screen_ahead.normalized() * draw_dir.length(),
		Vector2(0.0001, 0.0001))

func test_marker_chevron_geometry_points_along_heading() -> void:
	var center := Vector2(300.0, 240.0)
	var size := MapRoads.MARKER_SIZE
	var pts := MapRoads.marker_chevron(center,
		MapRoads.marker_world_angle(Vector3(0.0, 0.0, -1.0)), size)
	assert_that(pts.size()).is_equal(3)
	# Head north (-z): the tip points straight UP on the y-down screen.
	assert_that(pts[0]).is_equal_approx(center + Vector2(0.0, -size), Vector2(0.0001, 0.0001))
	assert_float(pts[0].distance_to(center)).is_equal_approx(size, 0.0001)
	# The wings trail behind the tip at the tail.
	assert_that(pts[1]).is_equal_approx(center + Vector2(size * 0.62, size * 0.4), Vector2(0.0001, 0.0001))
	assert_that(pts[2]).is_equal_approx(center + Vector2(-size * 0.62, size * 0.4), Vector2(0.0001, 0.0001))
	# Turning 90 degrees east swings the tip to screen-right.
	var east_pts := MapRoads.marker_chevron(center,
		MapRoads.marker_world_angle(Vector3(1.0, 0.0, 0.0)), size)
	assert_that(east_pts[0]).is_equal_approx(center + Vector2(size, 0.0), Vector2(0.0001, 0.0001))

func test_marker_palette_stands_out_from_terrain_biomes() -> void:
	var style: Dictionary = MapRoads.marker_style()
	var accent := style["accent"] as Color
	var outline := style["outline"] as Color
	assert_that(_luminance(outline)).is_less(0.05)
	for h in BIOME_HEIGHTS:
		var biome := MapRoads.biome_color(h)
		# The cyan accent differs by a big margin on at least one channel from
		# every biome tint (water blues, greens, browns, snow), so it cannot
		# vanish into the terrain composite.
		assert_that(_channel_delta(accent, biome)).is_greater(0.4)
		# The near-black under-pin stays distinct from every biome too (most
		# importantly the near-white snow cap above ROCK_SNOW).
		assert_that(_channel_delta(outline, biome)).is_greater(0.2)

func test_world_map_places_player_chevron_at_world_projection() -> void:
	VehicleManager.player_car = null
	var holder := _new_network()
	var root: Node = holder["root"]
	var player := _stub_player(Vector3(80.0, 1.0, 60.0))

	var map := Control.new()
	map.name = "WorldMap"
	map.size = Vector2(512.0, 384.0)
	map.set_script(load(WORLD_MAP_SCRIPT))
	map.height_provider = _fake_height_provider(12.0)
	root.add_child(map)
	await await_idle_frame()
	map._rebuild()

	assert_that(map._has_player).is_true()
	if not map._has_player:
		return
	# The chevron is placed exactly at world_to_screen(player position)...
	var expected: Vector2 = MapRoads.world_to_screen(player.global_position, map._fit)
	assert_that(map._player_screen).is_equal_approx(expected, Vector2(0.001, 0.001))
	# ...is rotated to the heading (stub identity basis -> forward -z -> up)...
	assert_float(map._player_angle).is_equal_approx(
		MapRoads.marker_world_angle(Vector3(0.0, 0.0, -1.0)), 0.0001)
	# ...and is drawn with the pause-map's enlarged chevron scale.
	var pts := MapRoads.marker_chevron(map._player_screen, map._player_angle, float(map.MARKER_SIZE))
	assert_float(pts[0].distance_to(map._player_screen)).is_equal_approx(float(map.MARKER_SIZE), 0.001)
	root.free()

func test_world_map_keeps_player_visible_when_world_locked() -> void:
	VehicleManager.player_car = null
	var root := Node.new()
	root.name = "LockedRoot"
	add_child(root)
	_managed.append(root)
	var chain: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(300.0, 0.0, 0.0)]
	var network := RoadNetwork.new()
	network.name = "RoadNetwork"
	network.add_road(chain, 8.0, false)
	root.add_child(network)
	# Fresh discovery, NOTHING revealed: the whole road locks grey.
	var discovery := WorldDiscovery.new()
	discovery.configure([RoadDef.make(RoadDef.Tier.HIGHWAY, chain, "locked_x", false)])
	root.add_child(discovery)
	var player := _stub_player(Vector3(50.0, 0.0, 40.0))

	var map := Control.new()
	map.name = "WorldMap"
	map.size = Vector2(512.0, 384.0)
	map.set_script(load(WORLD_MAP_SCRIPT))
	map.height_provider = _fake_height_provider(12.0)
	root.add_child(map)
	await await_idle_frame()
	map._rebuild()

	# The world really is locked: the only road draws grey, not visited.
	assert_that(map._grey_paths.size()).is_greater_equal(1)
	# But the player marker has NO reveal gate - it is always drawn.
	assert_that(map._has_player).is_true()
	if not map._has_player:
		return
	var expected: Vector2 = MapRoads.world_to_screen(player.global_position, map._fit)
	assert_that(map._player_screen).is_equal_approx(expected, Vector2(0.001, 0.001))
	# POIs keep their existing behaviour: still listed, untouched by the marker
	# (the base 5 landmarks, plus lazily-derived event markers).
	assert_that(map._poi_entries.size()).is_greater_equal(5)
	root.free()

func test_minimap_chevron_tracks_player_heading_and_pulse() -> void:
	VehicleManager.player_car = null
	var root := Node.new()
	root.name = "MinimapRoot"
	add_child(root)
	_managed.append(root)
	var player := _stub_player(Vector3(120.0, 0.0, -40.0))

	var minimap := Control.new()
	minimap.name = "Minimap"
	minimap.size = Vector2(200.0, 200.0)
	minimap.set_script(load(MINIMAP_SCRIPT))
	root.add_child(minimap)
	await await_idle_frame()
	await await_idle_frame()

	# The minimap picked up the registered player car...
	assert_that(minimap._player_car).is_same(player)
	# ...rotates the chevron to the heading (identity basis -> forward -z -> up)
	# on the shared north-up convention, at the player-centred projection.
	var expected_angle := MapRoads.marker_minimap_angle(Vector3(0.0, 0.0, -1.0))
	assert_float(minimap._marker_angle).is_equal_approx(expected_angle, 0.0001)
	var center := minimap.size * 0.5
	var pts := MapRoads.marker_chevron(center, minimap._marker_angle, float(MapRoads.MARKER_SIZE))
	assert_that(pts[0]).is_equal_approx(center + Vector2(0.0, -float(MapRoads.MARKER_SIZE)), Vector2(0.0001, 0.0001))
	# The halo pulse is live: advancing fake time crosses redraw ticks.
	var tick_before: int = minimap._last_pulse_tick
	minimap._process(0.2)
	minimap._process(0.2)
	assert_that(minimap._last_pulse_tick).is_greater(tick_before)
	assert_that(minimap._last_pulse_tick).is_equal(int(minimap._pulse_time / MapRoads.MARKER_PULSE_STEP))
	root.free()

static func _channel_delta(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))

static func _luminance(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b