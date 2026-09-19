# tests/suites/test_gps_route_follow.gd
extends GdUnitTestSuite

## S4 gate: GPS route + in-world drive assist. Route polyline agreement between
## the minimap path and the shared MapRoads route the world map also draws;
## RoutePlanner snap monotonic along a straight route + navigate_to gate;
## BrakeLine hint severity decaying as a corner recedes (and flipping on the
## mirrored bend) plus severity peaking/decaying and arrow-flipping across a
## closed clover loop; the HUD nav widget wired behind GameState.nav_assist_enabled.
## Pure math stubs where possible (RoutedSource), scene_runner for the widget
## like test_race_results.gd.

const MINIMAP_ZOOM := 0.2

func before_test() -> void:
	MapRoads.clear_route()
	GameState.nav_assist_enabled = true

func after_test() -> void:
	MapRoads.clear_route()
	GameState.nav_assist_enabled = true
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

# --- Geometry helpers -------------------------------------------------------

func _straight_chain(length: float, spacing: float = 10.0) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n := maxi(int(ceil(length / spacing)), 2)
	for i in n + 1:
		out.append(Vector3(float(i) * length / float(n), 0.0, 0.0))
	return out

func _translated_chain(base: Array[Vector3], dx: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in base:
		out.append(p + Vector3(dx, 0.0, 0.0))
	return out

func _l_bend_vertices() -> Array[Vector3]:
	return [
		Vector3(0.0, 0.0, 0.0),
		Vector3(100.0, 0.0, 0.0),
		Vector3(100.0, 0.0, 300.0),
		Vector3(100.0, 0.0, 400.0),
	]

func _dense(vertices: Array[Vector3], step: float = 5.0) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for k in range(vertices.size() - 1):
		var a := vertices[k]
		var b := vertices[k + 1]
		var n := maxi(int(ceil(a.distance_to(b) / step)), 1)
		for i in n:
			out.append(a.lerp(b, float(i) / float(n)))
	out.append(vertices[vertices.size() - 1])
	return out

func _mirror(pts: Array[Vector3]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in pts:
		out.append(Vector3(-p.x, p.y, p.z))
	return out

func _l_bend_chain() -> Array[Vector3]:
	return _dense(_l_bend_vertices())

func _clover_chain(points: int = 96, base: float = 80.0, wobble: float = 60.0) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for k in points:
		var phi := float(k) * TAU / float(points)
		var r := base + wobble * sin(3.0 * phi)
		out.append(Vector3(r * cos(phi), 0.0, r * sin(phi)))
	return out

func _probe_result(source: Object, player: Vector3, target: Vector3) -> Dictionary:
	MapRoads.set_route(target)
	return BrakeLine.new(source).probe(player)

# --- RoutePlanner -----------------------------------------------------------

func test_snap_arc_is_monotonic_decreasing_to_the_destination() -> void:
	var source := RoutedSource.new([_straight_chain(300.0)])
	var planner := RoutePlanner.new(source)
	MapRoads.set_route(Vector3(300.0, 0.0, 0.0))

	var arcs: Array[float] = []
	for x in [50.0, 120.0, 200.0, 270.0]:
		var snap := planner.snap(Vector3(x, 0.0, 0.0))
		arcs.append(float(snap["arc"]))
		assert_float(snap["dist"]).is_less(0.01)
	# arc is the route distance still remaining to the destination, so it shrinks
	# as the player gets closer (250 m remaining at x=50 -> 30 m at x=270).
	assert_float(arcs[0]).is_equal_approx(250.0, 0.01)
	for i in range(1, arcs.size()):
		assert_float(arcs[i]).is_less(arcs[i - 1])
	assert_float(arcs[arcs.size() - 1]).is_equal_approx(30.0, 0.01)

	# Past the route's end the snap clamps onto the terminal waypoint: no arc
	# remains and dist is the perpendicular offset from the last segment.
	var beyond := planner.snap(Vector3(400.0, 0.0, 5.0))
	assert_float(beyond["arc"]).is_equal_approx(0.0, 0.01)
	assert_float(beyond["dist"]).is_equal_approx(100.125, 0.05)

func test_snap_returns_no_route_sentinel_without_source_or_route() -> void:
	MapRoads.clear_route()
	var no_route_yet := RoutePlanner.new(RoutedSource.new([_straight_chain(100.0)]))
	var before := no_route_yet.snap(Vector3.ZERO)
	assert_that(before["road_id"]).is_equal(-1)
	assert_float(before["dist"]).is_equal(-1.0)
	assert_float(before["arc"]).is_equal(0.0)

	MapRoads.set_route(Vector3(50.0, 0.0, 0.0))
	var no_source := RoutePlanner.new(null)
	assert_that(no_source.snap(Vector3.ZERO)["road_id"]).is_equal(-1)

func test_navigate_to_gate_sets_and_clears_route() -> void:
	var planner := RoutePlanner.new(RoutedSource.new([_straight_chain(300.0)]))
	assert_that(planner.navigate_to(Vector3(20.0, 0.0, 0.0), Vector3(280.0, 0.0, 0.0))).is_true()
	assert_that(MapRoads.has_route).is_true()
	assert_that(MapRoads.route_target).is_equal(Vector3(280.0, 0.0, 0.0))

	# Destination off the connected graph is rejected and route state clears.
	var isolated := RoutedSource.new(
		[_straight_chain(200.0), _translated_chain(_straight_chain(200.0), 500.0)], false)
	var lonely := RoutePlanner.new(isolated)
	assert_that(lonely.navigate_to(Vector3(20.0, 0.0, 0.0), Vector3(520.0, 0.0, 0.0))).is_false()
	assert_that(MapRoads.has_route).is_false()
	assert_that(MapRoads.route_target).is_equal(Vector3.ZERO)

	assert_that(RoutePlanner.new(null).navigate_to(Vector3.ZERO, Vector3.ZERO)).is_false()

# --- MapRoads.minimap_route_path --------------------------------------------

func test_minimap_route_path_matches_the_shared_route_polyline() -> void:
	var source := RoutedSource.new([_straight_chain(1000.0)])
	var player := Vector3(100.0, 0.0, 0.0)
	var target := Vector3(900.0, 0.0, 0.0)
	MapRoads.set_route(target)
	var rect := Rect2(0.0, 0.0, 200.0, 200.0)
	var center := rect.get_center()

	# The world map draws route_polyline(...) through its own fit; the minimap
	# path must be exactly that same polyline through the minimap transform.
	var shared := MapRoads.route_polyline(source, player, target)
	var expected := MapRoads.clip_circle(
		MapRoads.world_to_local_points(shared, player, center, MINIMAP_ZOOM), center, 100.0)

	var path := MapRoads.minimap_route_path(rect, player, source, MINIMAP_ZOOM)
	assert_that(path.size() >= 2).is_true()
	assert_that(path.size()).is_equal(expected.size())
	for i in path.size():
		assert_that(path[i]).is_equal_approx(expected[i], Vector2(0.001, 0.001))
	for i in path.size():
		var p: Vector2 = path[i]
		assert_float(p.distance_to(center)).is_less_equal(100.0 + 0.001)

	MapRoads.clear_route()
	assert_that(MapRoads.minimap_route_path(rect, player, source, MINIMAP_ZOOM).is_empty()).is_true()
	assert_that(MapRoads.minimap_route_path(rect, player, null, MINIMAP_ZOOM).is_empty()).is_true()

# --- BrakeLine --------------------------------------------------------------

func test_brake_line_hint_severity_decays_as_the_corner_recedes() -> void:
	var source := RoutedSource.new([_l_bend_chain()])
	var target := Vector3(100.0, 0.0, 390.0)

	# 40 m before the 90-degree bend: hard-brake, left, within 30..60 m.
	var near := _probe_result(source, Vector3(60.0, 0.0, 0.0), target)
	assert_that(near["hint"]).is_equal("hard-brake")
	assert_that(near["arrow"]).is_equal("left")
	assert_that(near["distance_m"]).is_between(30.0, 60.0)
	assert_float(near["corner_angle"]).is_greater_equal(BrakeLine.HARD_BRAKE_ANGLE)

	# 90 m before it: still brake (beyond the hard-brake distance), same turn.
	var far := _probe_result(source, Vector3(10.0, 0.0, 0.0), target)
	assert_that(far["hint"]).is_equal("brake")
	assert_that(far["arrow"]).is_equal("left")
	assert_that(far["distance_m"]).is_between(70.0, 110.0)

	# Past the bend on the straight: the hint has fully decayed.
	var past := _probe_result(source, Vector3(100.0, 0.0, 260.0), target)
	assert_that(past["hint"]).is_equal("none")
	assert_that(past["arrow"]).is_equal("straight")
	assert_float(past["distance_m"]).is_equal(-1.0)

func test_brake_line_direction_flips_on_the_mirrored_bend() -> void:
	var source := RoutedSource.new([_mirror(_l_bend_chain())])
	var near := _probe_result(source, Vector3(-60.0, 0.0, 0.0), Vector3(-100.0, 0.0, 390.0))
	assert_that(near["hint"]).is_equal("hard-brake")
	assert_that(near["arrow"]).is_equal("right")

func test_brake_line_closed_loop_severity_peaks_and_arrow_flips() -> void:
	var chain := _clover_chain(96, 80.0, 60.0)
	var source := RoutedSource.new([chain])
	MapRoads.set_route(chain[0])
	var brake := BrakeLine.new(source)
	var max_angle := -1.0
	var max_hint := ""
	var min_angle := INF
	var saw_left := false
	var saw_right := false
	for k in chain.size():
		var res := brake.probe(chain[k])
		var angle := float(res["corner_angle"])
		var hint := str(res["hint"])
		var arrow := str(res["arrow"])
		if angle > max_angle:
			max_angle = angle
			max_hint = hint
		min_angle = minf(min_angle, angle)
		if hint != "none":
			saw_left = saw_left or arrow == "left"
			saw_right = saw_right or arrow == "right"
	# The tight lobe throat gives a hard-brake; somewhere on the same closed
	# loop the severity decays back below CORNER_ANGLE (a "none" hint), and both
	# turn directions appear, so the hint breaks/flips as the player laps.
	assert_that(max_hint).is_equal("hard-brake")
	assert_float(max_angle).is_greater_equal(BrakeLine.HARD_BRAKE_ANGLE)
	assert_float(min_angle).is_less(BrakeLine.CORNER_ANGLE)
	assert_that(saw_left).is_true()
	assert_that(saw_right).is_true()

func test_brake_line_no_route_or_null_source_is_a_no_op() -> void:
	# No active route (before_test cleared it): a fresh probe is a clean no-op.
	var no_route := BrakeLine.new(RoutedSource.new([_l_bend_chain()]))
	var res := no_route.probe(Vector3(60.0, 0.0, 0.0))
	assert_that(res["hint"]).is_equal("none")
	assert_that(res["arrow"]).is_equal("straight")
	assert_float(res["distance_m"]).is_equal(-1.0)

	MapRoads.set_route(Vector3(100.0, 0.0, 390.0))
	var null_source := BrakeLine.new(null)
	assert_that(null_source.probe(Vector3(60.0, 0.0, 0.0))["hint"]).is_equal("none")

# --- HUD nav widget (feature flag) ------------------------------------------

func test_nav_widget_hidden_without_route() -> void:
	MapRoads.clear_route()
	var runner := scene_runner("res://scenes/ui/hud.tscn")
	await runner.simulate_frames(1)
	var scene := runner.scene() as RaceUI
	var widget := scene.get_node("%NavWidget") as Control
	assert_that(widget.visible).is_false()

func test_nav_widget_shows_hard_brake_before_corner_and_flag_hides_it() -> void:
	MapRoads.clear_route()
	GameState.nav_assist_enabled = true
	var runner := scene_runner("res://scenes/ui/hud.tscn")
	await runner.simulate_frames(1)
	var scene := runner.scene() as RaceUI

	# Give the HUD a road source, a live route with a corner 40 m ahead, and a
	# standing player car (a VehiclePhysics subclass whose _ready is overridden
	# so it is safe to drop bare into the tree, mirroring the stub-car pattern).
	var network := RoadNetwork.new()
	network.name = "NavRoads"
	network.add_road(_l_bend_chain(), 8.0, false)
	scene.add_child(network)
	var player := NavCar.new()
	player.name = "NavPlayer"
	player.freeze = true
	player.gravity_scale = 0.0
	scene.add_child(player)
	player.global_position = Vector3(60.0, 0.0, 0.0)
	VehicleManager.register_player_car(player)
	MapRoads.set_route(Vector3(100.0, 0.0, 390.0))
	await runner.simulate_frames(3)

	var widget := scene.get_node("%NavWidget") as Control
	assert_that(widget.visible).is_true()
	assert_that((scene.get_node("%NavHint") as Label).text).is_equal("HARD BRAKE")
	var dist_text: String = (scene.get_node("%NavDistance") as Label).text
	assert_that(dist_text.ends_with(" m")).is_true()
	var meters := int(dist_text.trim_suffix(" m"))
	assert_that(meters).is_between(30, 60)

	# The GameState feature flag hides the widget even with the route live.
	GameState.nav_assist_enabled = false
	await runner.simulate_frames(2)
	assert_that(widget.visible).is_false()

	GameState.nav_assist_enabled = true
	await runner.simulate_frames(2)
	assert_that(widget.visible).is_true()

# --- Lightweight stubs ------------------------------------------------------

## Duck-typed RoadNetwork stand-in: holds point chains and an optional linear
## chain adjacency, exposing get_roads()/nearest_road_id()/route() so pure GPS
## math can be tested without building TrackBuilder meshes.
class RoutedSource:
	extends RefCounted

	var _chains: Array = []
	var _connect: bool = true

	func _init(roads: Array = [], linked: bool = true) -> void:
		_chains = roads
		_connect = linked

	func get_roads() -> Array:
		return _chains

	func nearest_road_id(pos: Vector3) -> int:
		var best_id := -1
		var best_sq := INF
		for i in _chains.size():
			var chain: Array = _chains[i]
			for v in chain:
				var p: Vector3 = v
				var dx := pos.x - p.x
				var dz := pos.z - p.z
				var sq := dx * dx + dz * dz
				if sq < best_sq:
					best_sq = sq
					best_id = i
		return best_id

	func route(from_id: int, to_id: int) -> PackedInt32Array:
		if from_id == to_id:
			return PackedInt32Array([from_id])
		if not _connect:
			return PackedInt32Array()
		var n := _chains.size()
		if from_id < 0 or to_id < 0 or from_id >= n or to_id >= n:
			return PackedInt32Array()
		var prev := {}
		prev[from_id] = -1
		var frontier: Array[int] = [from_id]
		var head := 0
		while head < frontier.size():
			var current: int = frontier[head]
			head += 1
			if current == to_id:
				break
			for nb in [current - 1, current + 1]:
				if nb >= 0 and nb < n and not prev.has(nb):
					prev[nb] = current
					frontier.append(nb)
		if not prev.has(to_id):
			return PackedInt32Array()
		var path: Array[int] = []
		var node := to_id
		while node != -1:
			path.append(node)
			node = prev[node]
		path.reverse()
		var out := PackedInt32Array()
		for v in path:
			out.append(v)
		return out

## Headless-safe player stand-in: VehiclePhysics _ready expects four wheel
## children, so this subclass carries a no-op _ready for dropping bare into a
## scene tree. config stays null, which makes get_drive_info() return zeros.
class NavCar:
	extends VehiclePhysics

	func _ready() -> void:
		pass