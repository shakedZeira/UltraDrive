# scripts/world/world_driver.gd
class_name WorldDriver
extends Node3D

## Feeds the player car's global position into the ChunkStreamer and the
## TerrainSeeder every physics tick so chunks and Terrain3D regions stream
## in/out around the driver. Also pushes once on ready so the first frame
## already has ground under the car.

## RoadNetwork and MountainPassZone are children of this root; they exist
## before WorldDriver._ready() runs, so _bootstrap_roads() can hand every road
## centerline to the TerrainSeeder ahead of the first ground bake.
@export var road_network_path: NodePath = NodePath("RoadNetwork")
@export var mountain_pass_zone_path: NodePath = NodePath("MountainPassZone")

## Suns in the "sun" group are driven from WeatherManager's computed sun
## position (Q6). Standalone scenes without a WorldDriver attach the
## SunDriver companion script to their DirectionalLight3D instead.
const SUN_GROUP := "sun"
const SUN_MIN_ELEVATION := 0.08
const SUN_TRANSFORM_LERP_FACTOR := 0.35

## WorldDriver registers itself in this group so the pause-map (scripts/ui/
## world_map.gd) can resolve the driver for fast-travel without a scene node.
const DRIVER_GROUP := "world_driver"

## Static open-world ReflectionProbes (Task 6): one over the hub ring, one over
## the mountain pass. UPDATE_ONCE so each bakes once and never re-renders; with
## the single per-car UPDATE_ALWAYS probe the blended total is 3, under the
## project's 4-probe reflection probe blend cap.
const HUB_PROBE_ORIGIN := Vector3(128.0, 2.0, 128.0)
const PASS_PROBE_ORIGIN := Vector3(3800.0, 14.0, 3200.0)
const STATIC_PROBE_SIZE := Vector3(60.0, 30.0, 60.0)

var _streamer: ChunkStreamer
var _terrain_seeder: TerrainSeeder
var _player: Node3D
var _discovery: WorldDiscovery

func _ready() -> void:
	add_to_group(DRIVER_GROUP)
	_streamer = get_node_or_null("ChunkStreamer") as ChunkStreamer
	_terrain_seeder = get_node_or_null("TerrainSeeder") as TerrainSeeder
	_player = get_node_or_null("%PlayerCar") as Node3D
	_bootstrap_roads()
	_bootstrap_discovery()
	_push_player_position()
	_bootstrap_sun_driver()
	_bootstrap_static_probes()

func _physics_process(_delta: float) -> void:
	if _player == null:
		_player = get_node_or_null("%PlayerCar") as Node3D
	if _streamer == null or _player == null:
		return
	_push_player_position()
	if _discovery != null:
		_discovery.reveal_at(_player.global_position)

func _push_player_position() -> void:
	if _streamer == null or _player == null:
		return
	var player_pos := _player.global_position
	_streamer.set_player_position(player_pos)
	if _terrain_seeder != null:
		_terrain_seeder.sync_player_pos(player_pos)

## P5 discovery bridge: creates (or reuses) the off-limits-autoload
## WorldDiscovery state node, configures it with the seeded road defs so it can
## answer visited queries, auto-reveals the spawn so fast-travel works from the
## first frame, then restores any saved discovery data. Runs after
## _bootstrap_roads() so __road_defs are ready; __player is resolved first so the
## spawn reveal covers the car's spawn.
func _bootstrap_discovery() -> void:
	_discovery = get_tree().get_first_node_in_group(WorldDiscovery.GROUP_NAME) as WorldDiscovery
	if _discovery == null:
		_discovery = WorldDiscovery.new()
		_discovery.name = "WorldDiscovery"
		add_child(_discovery)
	var network := get_node_or_null(road_network_path) as RoadNetwork
	if network != null:
		_discovery.configure(network.get_road_defs())
	if _player != null:
		_discovery.reveal_at(_player.global_position)
	_discovery.load_from_slot(WorldDiscovery.DEFAULT_SLOT)
	if not GameState.game_paused.is_connected(_on_game_paused):
		GameState.game_paused.connect(_on_game_paused)

func _on_game_paused() -> void:
	if _discovery != null:
		_discovery.save_to_slot(WorldDiscovery.DEFAULT_SLOT)

## P5 fast travel: teleports the player car to the closest revealed road point
## within the discovery snap distance of the given world position. Rejects
## positions the player has not yet discovered. The car and the chase camera are
## settled in place (no velocity, no physics interpolation residual) and the
## streaming position is re-pushed so ground loads around the target.
func fast_travel_to(world_pos: Vector3) -> bool:
	if _player == null:
		_player = get_node_or_null("%PlayerCar") as Node3D
	if _player == null or _discovery == null:
		return false
	if not _discovery.is_revealed(world_pos):
		return false
	var target := _discovery.try_snap_to_revealed(world_pos)
	if target == Vector3.INF:
		return false
	_settle_car(target)
	_settle_chase_camera()
	_push_player_position()
	return true

## Moves the car to an absolute position and zeroes its motion, snapping its
## physics-interpolation so the viewport does not smear a leftover velocity.
func _settle_car(target: Vector3) -> void:
	_player.global_position = target
	if _player.has_method("reset_physics_interpolation"):
		_player.call("reset_physics_interpolation")
	if _player is RigidBody3D:
		var body := _player as RigidBody3D
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

## Snaps the chase camera to the ideal chase position for the (now settled)
## player and re-orients it. Duck-typed: only cameras whose `target` is this
## driver's player and that expose chase camera_distance/camera_height are
## handled, so orbit cameras and other players are untouched.
func _settle_chase_camera() -> void:
	for candidate in get_children():
		if not candidate is Node3D:
			continue
		if candidate.get("target") != _player:
			continue
		if not ("camera_distance" in candidate and "camera_height" in candidate):
			continue
		var camera_distance := 6.0
		var camera_height := 2.5
		if typeof(candidate.get("camera_distance")) == TYPE_FLOAT:
			camera_distance = float(candidate.get("camera_distance"))
		if typeof(candidate.get("camera_height")) == TYPE_FLOAT:
			camera_height = float(candidate.get("camera_height"))
		var ideal := _player.global_position + _player.global_basis.z * camera_distance + Vector3.UP * camera_height
		(candidate as Node3D).global_position = ideal
		if candidate.has_method("_update_camera"):
			candidate.call("_update_camera", 1.0 / 60.0)
		return

## Seeds the road network before the first terrain push so Terrain3D carves
## recessed ground under every road on its first bake. CorridorPlanner emits
## the full classified network (hub ring, connector, pass loop, then new
## highway/touge/coastal/dirt corridors) and each def is registered before
## the first height lookup (critical ordering from AGENTS.md).
func _bootstrap_roads() -> void:
	var network := get_node_or_null(road_network_path) as RoadNetwork
	if network == null:
		return
	var zone := get_node_or_null(mountain_pass_zone_path) as Node3D
	var end := Vector3(3800.0, 14.0, 3200.0)
	var zone_roads: Array[Vector3] = []
	if zone != null:
		var zone_points: Array = zone.get("road_points") as Array
		if zone_points != null and zone_points.size() > 0:
			for p in zone_points:
				zone_roads.append(zone.global_position + (p as Vector3))
			end = zone_roads[0]
	var params := {}
	if zone_roads.size() > 0:
		params["zone_road_points"] = zone_roads
		params["zone_end"] = end
	var corridor_defs := CorridorPlanner.plan(CorridorPlanner.MASTER_SEED, Callable(), params)
	for def in corridor_defs:
		network.add_road_def(def)
	if _terrain_seeder != null:
		_terrain_seeder.set_roads(network.get_roads(), network.get_road_defs())

## WeatherManager sun portal (Q6). These helpers are the single source of
## truth for baking a DirectionalLight3D sun transform; WeatherManager itself
## stays untouched — only its computed position is portaled into the suns.

func _bootstrap_sun_driver() -> void:
	if WeatherManager.time_of_day_changed.is_connected(_on_time_of_day_changed) == false:
		WeatherManager.time_of_day_changed.connect(_on_time_of_day_changed)
	_drive_suns(WeatherManager.get_time_of_day(), true)

## Bakes static UPDATE_ONCE ReflectionProbes at the hub and the mountain pass.
## Called after the first terrain bake so the probes capture settled ground.
func _bootstrap_static_probes() -> void:
	add_child(WorldDriver.make_static_probe(HUB_PROBE_ORIGIN, STATIC_PROBE_SIZE))
	add_child(WorldDriver.make_static_probe(PASS_PROBE_ORIGIN, STATIC_PROBE_SIZE))

## Factory for a static (UPDATE_ONCE) ReflectionProbe at an absolute world
## origin with AMBIENT_ENVIRONMENT ambient sampled from the sky. Exposed as a
## static helper so tests can assert the config without needing a world.
static func make_static_probe(origin: Vector3, size: Vector3) -> ReflectionProbe:
	var probe := ReflectionProbe.new()
	probe.position = origin
	probe.size = size
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
	return probe

func _on_time_of_day_changed(hour: float) -> void:
	_drive_suns(hour, false)

func _drive_suns(hour: float, snap: bool) -> void:
	for sun in get_tree().get_nodes_in_group(SUN_GROUP):
		WorldDriver.apply_sun_transform(sun as DirectionalLight3D, hour, snap)

## Re-derives WeatherManager.get_computed_sun_position() for an explicit hour
## (same arc: angle = hour/24*360 - 90, direction (cos(angle), sin(angle), 0.3))
## and clamps the elevation to SUN_MIN_ELEVATION so the sun never falls under
## the ground during the night hours.
static func sun_direction(hour: float) -> Vector3:
	var angle := deg_to_rad(fposmod(hour, 24.0) / 24.0 * 360.0 - 90.0)
	var dir := Vector3(cos(angle), sin(angle), 0.3).normalized()
	if dir.y < SUN_MIN_ELEVATION:
		var horizontal := sqrt(maxf(1.0 - SUN_MIN_ELEVATION * SUN_MIN_ELEVATION, 0.0))
		dir = Vector3(dir.x, 0.0, dir.z).normalized() * horizontal
		dir.y = SUN_MIN_ELEVATION
	return dir

## Bakes a DirectionalLight3D transform pointing from the sun at the world: the
## local -Z is the direction the light rays travel (toward the ground), so
## basis.z is the clamped sun direction. Origin stays at zero because a
## DirectionalLight3D ignores its position.
static func compute_sun_transform(hour: float) -> Transform3D:
	var z := sun_direction(hour)
	var x := Vector3(1.0, 0.0, 0.0)
	var y := z.cross(x).normalized()
	if y.length() < 0.0001:
		x = Vector3(0.0, 0.0, -1.0)
		y = z.cross(x).normalized()
	x = y.cross(z).normalized()
	return Transform3D(x, y, z, Vector3.ZERO)

## Applies the baked transform to a sun light, lerping toward the target so a
## time-of-day change never pops, and re-asserts shadows stay enabled.
static func apply_sun_transform(sun: DirectionalLight3D, hour: float, snap: bool = false) -> void:
	if sun == null:
		return
	var target := compute_sun_transform(hour)
	if snap:
		sun.transform = target
	else:
		sun.transform = sun.transform.interpolate_with(target, SUN_TRANSFORM_LERP_FACTOR)
	sun.shadow_enabled = true