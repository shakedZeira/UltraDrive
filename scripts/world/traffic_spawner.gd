# scripts/world/traffic_spawner.gd
class_name TrafficSpawner
extends Node

## Spawns and manages traffic vehicles that follow roads.

@export var vehicle_scene: PackedScene
@export var max_traffic: int = 15
@export var spawn_radius: float = 300.0
## Fraction (0.0..1.0) of spawns that are parked: static, never-driving visuals
## that still count toward the ring and despawn normally.
@export var parked_ratio: float = 0.0
@export var road_network: RoadNetwork

var _traffic: Array[VehiclePhysics] = []
var _drivers: Dictionary = {}  # VehiclePhysics -> TrafficDriver
var _enabled := true

## Default tick when called outside the live physics loop (existing 1-arg call
## sites / tests keep working).
const DEFAULT_DELTA := 1.0 / 60.0

## Event-mode pause gate: while an event runs no traffic spawns/despawns or
## drives; resume with set_enabled(true).
func set_enabled(enabled: bool) -> void:
    _enabled = enabled

func is_enabled() -> bool:
    return _enabled

func update(player_pos: Vector3, delta: float = DEFAULT_DELTA) -> void:
    if not _enabled:
        return
    # Remove far traffic: drop the driver first so the RefCounted frees itself
    # even if queue_free() is deferred, then queue the vehicle.
    for vehicle in _traffic.duplicate():
        if vehicle.global_position.distance_to(player_pos) > spawn_radius + 100:
            var driver: TrafficDriver = _drivers.get(vehicle)
            _drivers.erase(vehicle)
            vehicle.queue_free()
            _traffic.erase(vehicle)

    # Distance-cull engine audio so distant cars don't each run a full
    # multi-bed loop (see EngineAudio.TRAFFIC_AUDIO_RANGE).
    for vehicle in _traffic:
        var audio := vehicle.get_node_or_null("EngineAudio") as EngineAudio
        if audio != null:
            audio.cull_by_distance(player_pos, EngineAudio.TRAFFIC_AUDIO_RANGE)

    # Drive every live vehicle through its TrafficDriver (input_override).
    # player_pos is the consumer-supplied proximity probe (traffic-forward axis
    # slow/stop against the player).
    for vehicle in _traffic:
        var driver: TrafficDriver = _drivers.get(vehicle)
        if driver != null:
            driver.update(player_pos, delta)

    # Spawn new traffic if under max
    if _traffic.size() < max_traffic:
        _spawn_vehicle(player_pos)

func _spawn_vehicle(player_pos: Vector3) -> void:
    if vehicle_scene == null:
        return
    var spawn_pos := player_pos
    if road_network == null:
        spawn_pos = player_pos + _random_offset()
    else:
        var placed := false
        for _attempt in 8:
            var candidate := player_pos + _random_offset()
            if road_network.is_on_road(candidate, 10.0):
                spawn_pos = road_network.get_nearest_road_pos(candidate)
                placed = true
                break
        if not placed:
            return
    var vehicle := vehicle_scene.instantiate() as VehiclePhysics
    _deprivilege_vehicle(vehicle)
    add_child(vehicle)
    vehicle.global_position = spawn_pos
    _traffic.append(vehicle)
    _drivers[vehicle] = _make_driver(vehicle)

## Weather VFX night switch (S12): drives every live traffic vehicle's shared
## Headlights node from the authoritative night flag (defensive -- traffic uses
## the same player scene, so rivals get headlights exactly like the player).
func sync_headlights(night: bool) -> void:
    for vehicle in _traffic:
        var lights := vehicle.get_node_or_null("Headlights") as Node
        if lights != null and lights.has_method("set_night"):
            lights.call("set_night", night)

## Traffic must never become the "player". A scene whose root rig carries a
## PlayerCarController (player_car.tscn) would re-register itself as
## VehicleManager.player_car on _ready and null that slot on despawn, so the
## free-roam HUD cluster ends up reading a traffic car's gauges (or null) and
## races would draft traffic cars into the grid. Strip the controller before
## add_child so its _ready never runs; that also drops the per-car real-time
## reflection probe the controller builds, which is the biggest per-vehicle
## GPU cost a traffic car carries.
func _deprivilege_vehicle(vehicle: VehiclePhysics) -> void:
    var controller := vehicle.get_node_or_null("PlayerCarController") as Node
    if controller == null:
        return
    vehicle.remove_child(controller)
    controller.free()

func _make_driver(vehicle: VehiclePhysics) -> TrafficDriver:
    var driver := TrafficDriver.new()
    driver.set_parked(randf() < parked_ratio)
    if road_network == null:
        return driver
    var road_id := road_network.nearest_road_id(vehicle.global_position)
    if road_id < 0:
        return driver
    var defs := road_network.get_road_defs()
    if road_id >= defs.size():
        return driver
    var def := defs[road_id] as RoadDef
    driver.configure(vehicle, def.points, def.closed, _traffic_speed_kmh())
    return driver

func _traffic_speed_kmh() -> float:
    return randf_range(TrafficDriver.CRUISE_KMH * 0.75, TrafficDriver.CRUISE_KMH * 1.25)

func _random_offset() -> Vector3:
    return Vector3(
        randf_range(-spawn_radius, spawn_radius),
        0,
        randf_range(-spawn_radius, spawn_radius))