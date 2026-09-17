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

func _ready() -> void:
	_streamer = get_node_or_null("ChunkStreamer") as ChunkStreamer
	_terrain_seeder = get_node_or_null("TerrainSeeder") as TerrainSeeder
	_player = get_node_or_null("%PlayerCar") as Node3D
	_bootstrap_roads()
	_push_player_position()
	_bootstrap_sun_driver()
	_bootstrap_static_probes()

func _physics_process(_delta: float) -> void:
	if _player == null:
		_player = get_node_or_null("%PlayerCar") as Node3D
	if _streamer == null or _player == null:
		return
	_push_player_position()

func _push_player_position() -> void:
	if _streamer == null or _player == null:
		return
	var player_pos := _player.global_position
	_streamer.set_player_position(player_pos)
	if _terrain_seeder != null:
		_terrain_seeder.sync_player_pos(player_pos)

## Seeds the road network before the first terrain push so Terrain3D carves
## recessed ground under every road on its first bake: the hub ring, the
## Catmull-Rom connector to the pass, and the pass loop itself (world-offset).
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
	network.add_road(_hub_ring(), 12.0)
	network.add_road(_pass_connector(end), 10.0, false)
	if zone_roads.size() > 0:
		network.add_road(zone_roads, 11.0)
	if _terrain_seeder != null:
		_terrain_seeder.set_roads(network.get_roads())

func _hub_ring() -> Array[Vector3]:
	var ring: Array[Vector3] = []
	for i in 96:
		var ang := TAU * float(i) / 96.0
		ring.append(Vector3(128.0 + cos(ang) * 110.0, 2.2, 128.0 + sin(ang) * 110.0))
	return ring

## Catmull-Rom connector from the hub to the pass-loop start. Y ramps from the
## hub height (2.2) up to end.y across the journey. Sampled every ~10 m.
func _pass_connector(end: Vector3) -> Array[Vector3]:
	var control: Array[Vector3] = [
		Vector3(238.0, 0.0, 128.0),
		Vector3(1500.0, 0.0, 128.0),
		Vector3(3200.0, 0.0, 1800.0),
		end,
	]
	var chain := PackedVector3Array()
	const DENSE := 96
	for i in DENSE + 1:
		chain.append(_catmull_rom_xz(control, float(i) / float(DENSE)))
	chain[DENSE] = end
	var cumulative := PackedFloat32Array()
	cumulative.resize(chain.size())
	var total := 0.0
	for i in chain.size():
		if i > 0:
			total += chain[i - 1].distance_to(chain[i])
		cumulative[i] = total
	var road: Array[Vector3] = []
	road.append(Vector3(chain[0].x, 2.2, chain[0].z))
	if total <= 0.0:
		return road
	const SAMPLE_DIST := 10.0
	var next_dist := SAMPLE_DIST
	for seg in range(1, chain.size()):
		var a := chain[seg - 1]
		var b := chain[seg]
		var seg_start := cumulative[seg - 1]
		var seg_len := cumulative[seg] - seg_start
		while next_dist <= cumulative[seg]:
			var local := (next_dist - seg_start) / seg_len if seg_len > 0.0001 else 0.0
			var pos := a.lerp(b, local)
			var frac := next_dist / total
			road.append(Vector3(pos.x, lerpf(2.2, end.y, frac), pos.z))
			next_dist += SAMPLE_DIST
	var last := road[road.size() - 1]
	if last.distance_to(end) > 1.0:
		road.append(end)
	return road

## Catmull-Rom spline sampled on XZ only (Y is ramped separately) with clamped
## end tangents, so the curve passes through every control point and the
## endpoints (hub and pass-loop start) sit exactly on their control points.
func _catmull_rom_xz(control: Array[Vector3], t: float) -> Vector3:
	var n := control.size()
	if n <= 1:
		return control[0] if n == 1 else Vector3.ZERO
	var seg := clampi(int(floorf(t * float(n - 1))), 0, n - 2)
	var f := clampf(t * float(n - 1) - float(seg), 0.0, 1.0)
	var p0: Vector3 = control[maxi(seg - 1, 0)]
	var p1: Vector3 = control[seg]
	var p2: Vector3 = control[seg + 1]
	var p3: Vector3 = control[mini(seg + 2, n - 1)]
	var f2 := f * f
	var f3 := f2 * f
	var x := 0.5 * (2.0 * p1.x + (-p0.x + p2.x) * f
		+ (2.0 * p0.x - 5.0 * p1.x + 4.0 * p2.x - p3.x) * f2
		+ (-p0.x + 3.0 * p1.x - 3.0 * p2.x + p3.x) * f3)
	var z := 0.5 * (2.0 * p1.z + (-p0.z + p2.z) * f
		+ (2.0 * p0.z - 5.0 * p1.z + 4.0 * p2.z - p3.z) * f2
		+ (-p0.z + 3.0 * p1.z - 3.0 * p2.z + p3.z) * f3)
	return Vector3(x, 0.0, z)

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