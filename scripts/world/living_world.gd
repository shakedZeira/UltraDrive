# scripts/world/living_world.gd
class_name LivingWorld
extends Node

## P6 living-world density driver. Dressing is wired deferred (end of the first
## frame) so every sibling `_ready` has already run: WorldDriver bootstrap roads
## into the RoadNetwork and the TerrainSeeder pushes the player region before
## this node configures and re-generates the per-zone PropScatterers and the
## Foliage. Each scatterer/folliage keeps an anchored ground-height provider
## (node-local sampling offset into world space, Terrain3D.data.get_height
## convention) and the road network for placement exclusion. Traffic is driven
## each physics tick against the player's current position. All guards are
## additive/load-safe: missing nodes simply no-op.

@export var terrain_path: NodePath = NodePath("../Terrain3D")
@export var road_network_path: NodePath = NodePath("../RoadNetwork")
@export var traffic_path: NodePath = NodePath("../TrafficSpawner")
@export var player_path: NodePath = NodePath("%PlayerCar")

var _terrain: Terrain3D = null
var _road_network: RoadNetwork = null
var _traffic_spawner: TrafficSpawner = null
var _enabled := true

func _ready() -> void:
    call_deferred("_setup")

## Event-mode pause gate: while an event runs the living world (traffic
## dressing tick) freezes; resume with set_enabled(true).
func set_enabled(enabled: bool) -> void:
    _enabled = enabled

func is_enabled() -> bool:
    return _enabled

func _physics_process(delta: float) -> void:
    if not _enabled or _traffic_spawner == null:
        return
    var player := get_node_or_null(player_path) as Node3D
    if player == null:
        return
    _traffic_spawner.update(player.global_position, delta)

func _setup() -> void:
    _terrain = get_node_or_null(terrain_path) as Terrain3D
    _road_network = get_node_or_null(road_network_path) as RoadNetwork
    _traffic_spawner = get_node_or_null(traffic_path) as TrafficSpawner
    var parent := get_parent()
    if parent == null:
        return
    for child in parent.get_children():
        if child == self:
            continue
        var scatterer := child as PropScatterer
        if scatterer != null:
            _dress_scatterer(scatterer)
            continue
        var foliage := child as Foliage
        if foliage != null:
            _dress_foliage(foliage)

func _dress_scatterer(scatterer: PropScatterer) -> void:
    scatterer.road_network = _road_network
    scatterer.ground_height_provider = _ground_provider(scatterer.global_transform.origin)
    scatterer.configure(PropScatterer.default_preset(_zone_from_name(scatterer.name)))
    scatterer.generate()

## Foliage has no road-exclusion field; ground it the same way and rebuild so
## the transient flat-Y `_ready` build is replaced before it is drawn.
func _dress_foliage(foliage: Foliage) -> void:
    foliage.ground_height_provider = _ground_provider(foliage.global_transform.origin)
    foliage.generate()

## Zone key hinted by the sibling node name ("PropsFestival" -> "festival") so
## the matching default_preset drives counts and seed. Unknown names fall back
## to the default_preset fallback (empty prop set, generic radius/seed).
static func _zone_from_name(node_name: String) -> String:
    return String(node_name).to_lower().trim_prefix("props")

## Ground-height lookup: scatterers and foliage sample in node-LOCAL space, so
## offset the local sample by the node origin into world space before the
## Terrain3D lookup. Falls back to Y 0 outside baked regions.
func _ground_provider(origin: Vector3) -> Callable:
    return func(local_pos: Vector2) -> float:
        return _height_at(origin.x + local_pos.x, origin.z + local_pos.y)

func _height_at(world_x: float, world_z: float) -> float:
    if _terrain == null:
        return 0.0
    var h := _terrain.data.get_height(Vector3(world_x, 0.0, world_z))
    if not is_finite(h):
        return 0.0
    return h