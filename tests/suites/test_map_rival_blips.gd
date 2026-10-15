# tests/suites/test_map_rival_blips.gd
extends GdUnitTestSuite

## "Where are the rivals?" gate for the HUD minimap AND the pause map.
##
## The field is sourced live (RaceManager's spawn grid, or an injected
## Callable() -> Array for the gate), projected with the SAME world->screen math
## the roads use (minimap: player-relative zoom; pause map: the cached fit),
## carries a heading angle from each car's -Z basis, and the whole layer is an
## empty list — never a crash, never a divide-by-zero — with no roster, no
## player car, no world, or show_rivals off.
##
## Pure MapRoads math is asserted headlessly; the map-level tests inject a stub
## roster and read the public data path (rival_blips) exactly like
## test_player_marker.gd / test_world_map_terrain.gd do for the player chevron.

const WORLD_MAP_SCRIPT := "res://scripts/ui/world_map.gd"
const MINIMAP_SCRIPT := "res://scripts/ui/minimap.gd"

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

## A plain rival node: a bare VehiclePhysics added ON the tree (the same staging
## test_traffic_driving._new_stub_car uses) so global_position / global_basis are
## the real world transform the blip projection reads. An OFF-tree read returns
## identity and logs "Condition !is_inside_tree()", which is what made an
## earlier cut of this gate assert zeros.
func _stub_rival(pos: Vector3, yaw: float = 0.0) -> VehiclePhysics:
	var car := VehiclePhysics.new()
	car.name = "StubRival"
	_stage_stub(car, pos)
	car.rotation = Vector3(0.0, yaw, 0.0)
	return car

func _stub_player(pos: Vector3) -> VehiclePhysics:
	var car := VehiclePhysics.new()
	car.name = "StubPlayer"
	_stage_stub(car, pos)
	VehicleManager.register_player_car(car)
	return car

## Puts a bare car on the tree and moves it to `pos`, then freezes its update so
## the absent Wheel* children are never stepped (_ready runs synchronously on
## add_child; _physics_process early-returns while _awaiting_ground, and the
## disabled process flags mean no frame can reach the wheels at all).
func _stage_stub(car: VehiclePhysics, pos: Vector3) -> void:
	add_child(car)
	car.set_physics_process(false)
	car.set_process(false)
	car.position = pos
	_managed.append(car)

func _new_network() -> Node:
	var root := Node.new()
	root.name = "RivalBlipRoot"
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
	return root

# --- shared MapRoads statics -------------------------------------------------

func test_live_rivals_sources_the_grid_and_filters_entries() -> void:
	# The default path reads the RaceManager spawn grid (an autoload; both sides
	# are the SAME roster, so a stale field left by another suite still agrees).
	var live: Array = MapRoads.live_rivals(Callable())
	assert_that(live).is_equal(RaceManager.get_spawned_rivals())
	# An injected source wins (tests / future non-race rival sources)...
	var a := _stub_rival(Vector3(10.0, 0.0, 20.0), 0.0)
	var b := _stub_rival(Vector3(30.0, 0.0, 40.0), PI * 0.5)
	var injected := func() -> Array: return [a, null, b]
	assert_int(MapRoads.live_rivals(injected).size()).is_equal(3)
	# ...and a source that returns junk degrades to an empty roster, not a crash.
	assert_that(MapRoads.live_rivals(func() -> Variant: return 7).is_empty()).is_true()
	# Entry filtering: null / non-Node3D roster members are skipped, so a stale
	# or malformed roster can never crash a draw pass.
	var entries := MapRoads.rival_entries(MapRoads.live_rivals(injected))
	assert_int(entries.size()).is_equal(2)
	var first: Dictionary = entries[0]
	var first_pos: Vector3 = first["position"]
	assert_that(first_pos).is_equal(Vector3(10.0, 0.0, 20.0))
	# Facing is the car's -Z basis: identity yaw -> north (-Z), +90 deg -> -X.
	var first_facing: Vector3 = first["facing"]
	assert_float(first_facing.dot(Vector3(0.0, 0.0, -1.0))).is_equal_approx(1.0, 0.001)
	var second: Dictionary = entries[1]
	var second_facing: Vector3 = second["facing"]
	assert_float(second_facing.dot(Vector3(-1.0, 0.0, 0.0))).is_equal_approx(1.0, 0.001)
	assert_that(MapRoads.rival_entries([RefCounted.new(), null, 42]).is_empty()).is_true()

func test_rival_blip_style_is_shared_and_dominated_by_the_player_marker() -> void:
	var style: Dictionary = MapRoads.rival_style()
	assert_that(style["fill"]).is_equal(MapRoads.RIVAL_FILL)
	assert_that(style["outline"]).is_equal(MapRoads.RIVAL_OUTLINE)
	assert_that(style["size"]).is_equal(MapRoads.RIVAL_SIZE)
	# Both maps alias the SAME accents, exactly like the MARKER_* constants...
	var minimap_script: GDScript = load(MINIMAP_SCRIPT)
	var world_map_script: GDScript = load(WORLD_MAP_SCRIPT)
	assert_that(minimap_script.RIVAL_FILL).is_equal(MapRoads.RIVAL_FILL)
	assert_that(world_map_script.RIVAL_FILL).is_equal(MapRoads.RIVAL_FILL)
	assert_that(minimap_script.RIVAL_OUTLINE).is_equal(world_map_script.RIVAL_OUTLINE)
	# ...the near-black under-pin stays near-black...
	assert_float(MapRoads.RIVAL_OUTLINE.r + MapRoads.RIVAL_OUTLINE.g + MapRoads.RIVAL_OUTLINE.b).is_less(0.1)
	# ...and the rival triangle is STRICTLY smaller than the player chevron, so
	# the player marker always wins the hierarchy on both maps.
	assert_float(MapRoads.RIVAL_SIZE).is_less(float(MapRoads.MARKER_SIZE))

func test_minimap_point_screen_matches_single_vertex_chain_mapping() -> void:
	var center := Vector2(100.0, 100.0)
	var player := Vector3.ZERO
	var rival := Vector3(50.0, 0.0, 10.0)
	var via_point: Vector2 = MapRoads.minimap_point_screen(rival, player, center, 0.2)
	# The roads' own one-point mapping must agree exactly (same convention).
	var via_chain: PackedVector2Array = MapRoads.world_to_local_points([rival], player, center, 0.2)
	assert_that(via_point).is_equal_approx(center + Vector2(10.0, 2.0), Vector2(0.001, 0.001))
	assert_that(via_point).is_equal_approx(via_chain[0], Vector2(0.001, 0.001))

# --- minimap ----------------------------------------------------------------

func test_minimap_projects_rival_blips_and_skips_gracefully() -> void:
	VehicleManager.player_car = null
	var root := Node.new()
	root.name = "RivalMinimapRoot"
	add_child(root)
	_managed.append(root)
	var player := _stub_player(Vector3(120.0, 0.0, -40.0))
	var rival := _stub_rival(Vector3(170.0, 0.0, -30.0))  # +50x, +10z of the player

	var minimap := Control.new()
	minimap.name = "Minimap"
	minimap.size = Vector2(200.0, 200.0)
	minimap.set_script(load(MINIMAP_SCRIPT))
	root.add_child(minimap)
	minimap.rival_source = func() -> Array: return [rival]
	# _ready() ran synchronously on add_child; this manual tick re-reads the
	# injected roster, so no idle frame is needed (and therefore no physics frame
	# can step the wheels-less stub).
	minimap._process(0.05)

	var center: Vector2 = minimap.size * 0.5
	var blips: Array = minimap.rival_blips(center)
	assert_int(blips.size()).is_equal(1)
	var blip: Dictionary = blips[0]
	var screen: Vector2 = blip["screen"]
	# zoom 0.2: (50, 10) world offset -> (10, 2) pixels from the disc centre,
	# i.e. the exact projection the road pass uses for the same vertex.
	assert_that(screen).is_equal_approx(center + Vector2(10.0, 2.0), Vector2(0.001, 0.001))
	var via_chain: PackedVector2Array = MapRoads.world_to_local_points(
		[rival.global_position], player.global_position, center, minimap.zoom)
	assert_that(screen).is_equal_approx(via_chain[0], Vector2(0.001, 0.001))
	# Heading: identity yaw -> -Z forward -> straight up on the north-up minimap.
	var angle := float(blip["angle"])
	assert_float(angle).is_equal_approx(-PI / 2.0, 0.0001)

	# Live refresh: _process re-reads the roster and a moved rival re-projects
	# with NO player movement and NO road rebuild.
	rival.position = Vector3(200.0, 0.0, -40.0)  # +80x of the player
	minimap._process(0.05)
	assert_int(minimap._rivals.size()).is_equal(1)
	var moved: Array = minimap.rival_blips(center)
	var moved_blip: Dictionary = moved[0]
	var moved_screen: Vector2 = moved_blip["screen"]
	assert_that(moved_screen).is_equal_approx(center + Vector2(16.0, 0.0), Vector2(0.001, 0.001))
	assert_that(moved_screen.is_equal_approx(screen)).is_false()

	# A rival outside the cull disc is dropped rather than drawn off-map.
	rival.position = Vector3(4000.0, 0.0, 0.0)
	assert_that(minimap.rival_blips(center).is_empty()).is_true()

	# Graceful skips, all of them: an empty roster, no player car, and the
	# show_rivals gate each yield NO blips and never touch the roads.
	rival.position = Vector3(170.0, 0.0, -30.0)
	minimap.rival_source = func() -> Array: return []
	minimap._process(0.05)
	assert_that(minimap.rival_blips(center).is_empty()).is_true()
	minimap.rival_source = func() -> Array: return [rival]
	minimap._process(0.05)
	assert_int(minimap._rivals.size()).is_equal(1)
	minimap._player_car = null
	assert_that(minimap.rival_blips(center).is_empty()).is_true()
	minimap._player_car = player
	assert_int(minimap.rival_blips(center).size()).is_equal(1)
	minimap.show_rivals = false
	assert_that(minimap.rival_blips(center).is_empty()).is_true()
	root.free()

# --- pause map --------------------------------------------------------------

func test_world_map_projects_rival_blips_on_the_cached_fit() -> void:
	VehicleManager.player_car = null
	var root := _new_network()
	_stub_player(Vector3(80.0, 1.0, 60.0))
	var rival := _stub_rival(Vector3(200.0, 0.0, 60.0), 0.0)

	var map := Control.new()
	map.name = "WorldMap"
	map.size = Vector2(512.0, 384.0)
	map.set_script(load(WORLD_MAP_SCRIPT))
	map.rival_source = func() -> Array: return [rival]
	root.add_child(map)
	await await_idle_frame()
	map._rebuild()

	assert_that(map._has_player).is_true()
	var blips: Array = map.rival_blips()
	assert_int(blips.size()).is_equal(1)
	var blip: Dictionary = blips[0]
	var screen: Vector2 = blip["screen"]
	# Placed exactly at world_to_screen(rival), the same projection as the roads.
	var expected: Vector2 = MapRoads.world_to_screen(rival.global_position, map._fit)
	assert_that(screen).is_equal_approx(expected, Vector2(0.001, 0.001))
	assert_float(float(blip["angle"])).is_equal_approx(
		MapRoads.marker_world_angle(Vector3(0.0, 0.0, -1.0)), 0.0001)

	# LIVE: moving a rival moves its blip on the SAME cached fit, with no rebuild
	# requested (the fit is what keeps the zoom from jittering as the field
	# spreads out; only the cars are re-read).
	var scale_before: float = map._fit["scale"]
	assert_that(map._dirty).is_false()
	rival.position = Vector3(10.0, 0.0, 250.0)
	var moved: Array = map.rival_blips()
	var moved_blip: Dictionary = moved[0]
	var moved_screen: Vector2 = moved_blip["screen"]
	var moved_expected: Vector2 = MapRoads.world_to_screen(rival.global_position, map._fit)
	assert_that(moved_screen).is_equal_approx(moved_expected, Vector2(0.001, 0.001))
	assert_that(moved_screen.is_equal_approx(screen)).is_false()
	assert_float(float(map._fit["scale"])).is_equal_approx(scale_before, 0.0001)
	assert_that(map._dirty).is_false()

	# show_rivals off and an empty roster both drop the layer (free roam / solo).
	map.show_rivals = false
	assert_that(map.rival_blips().is_empty()).is_true()
	map.show_rivals = true
	map.rival_source = func() -> Array: return []
	assert_that(map.rival_blips().is_empty()).is_true()
	root.free()

func test_world_map_blips_survive_no_world_and_no_player() -> void:
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()
	var rival := _stub_rival(Vector3(12.0, 0.0, -8.0))

	var map := Control.new()
	map.name = "WorldMap"
	map.size = Vector2(512.0, 384.0)
	map.set_script(load(WORLD_MAP_SCRIPT))
	map.rival_source = func() -> Array: return [rival]
	add_child(map)
	_managed.append(map)
	await await_idle_frame()
	map._rebuild()

	# Free roam: no roads, no player. The fallback fit is still finite...
	assert_that(map._fit.is_empty()).is_false()
	assert_that(map._has_player).is_false()
	# ...so the rival still projects (the divide-by-zero guard lives in
	# compute_fit, which is why this path must not crash) instead of vanishing.
	var blips: Array = map.rival_blips()
	assert_int(blips.size()).is_equal(1)
	var blip: Dictionary = blips[0]
	var screen: Vector2 = blip["screen"]
	assert_that(is_finite(screen.x) and is_finite(screen.y)).is_true()
	var expected: Vector2 = MapRoads.world_to_screen(rival.global_position, map._fit)
	assert_that(screen).is_equal_approx(expected, Vector2(0.001, 0.001))
	# An empty roster in the same no-world state is an empty list, never an error.
	map.rival_source = func() -> Array: return []
	assert_that(map.rival_blips().is_empty()).is_true()
	map.free()
