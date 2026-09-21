extends Node

## Controls the player's car. Attach as child of VehiclePhysics.

const CAR_ORIENT := Transform3D(Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0)), Vector3.ZERO)
const DEFAULT_VISUAL := "res://assets/cars/sports_coupe.glb"

@onready var car: VehiclePhysics = get_parent()

var _car_id: String = ""
var _spin_angle: float = 0.0
var _visual_wheels: Dictionary = {}
var _taillight_material: StandardMaterial3D = null
var _visual_ready: bool = false
var _probe: ReflectionProbe = null
var _probe_synced_enabled: bool = true

func _ready() -> void:
	VehicleManager.register_player_car(car)
	var active := Garage.new_from_save().get_active_car()
	_car_id = active
	if active != "":
		var car_path := "res://resources/cars/%s.tres" % active
		if ResourceLoader.exists(car_path):
			car.config = load(car_path) as CarConfig
	_apply_visual()

## The car is freed on scene swaps but VehicleManager keeps stale refs (its
## remove_car() had no callers), so all_cars/player_car could point at a freed
## body that a later start_race() then calls release_ground_lock() on. Unregister
## when this controller leaves the tree (children exit before parents, so the
## car body is still valid here).
func _exit_tree() -> void:
	if is_instance_valid(car):
		VehicleManager.remove_car(car)

func _process(delta: float) -> void:
	if not _visual_ready:
		return
	var info := car.get_drive_info()
	var speed_kmh: float = info["speed_kmh"]
	var steer: float = info["steer"]
	var brake: float = info["brake"]
	_spin_angle = _spin_angle + CarVisuals.wheel_spin_rate(speed_kmh, CarVisuals.WHEEL_RADIUS) * delta
	CarVisuals.apply_wheel_visuals(_visual_wheels, steer, _spin_angle)
	CarVisuals.apply_brake_glow(_taillight_material, brake)
	_sync_probe()

## Rebuilds the per-car ReflectionProbe under the visual body after its
## children were cleared in _apply_visual. Centered on the body (so it follows
## the car), sized to the mesh, real-time when GameState.probe_enabled.
func _ensure_car_probe(body: Node3D) -> void:
	var probe := ReflectionProbe.new()
	probe.name = "CarProbe"
	probe.size = CarVisuals.CAR_PROBE_SIZE
	probe.origin_offset = CarVisuals.CAR_PROBE_ORIGIN_OFFSET
	probe.box_projection = true
	body.add_child(probe)
	_probe = probe
	_probe_synced_enabled = GameState.probe_enabled
	CarVisuals.refresh_probe(probe, _probe_synced_enabled)

## Mirrors GameState.probe_enabled onto the live probe whenever it changes at
## runtime (e.g. quality preset switched mid-drive). Polled per frame; the
## single bool compare is negligible vs. the probe's own update cost.
func _sync_probe() -> void:
	if _probe == null:
		return
	var enabled := GameState.probe_enabled
	if enabled == _probe_synced_enabled:
		return
	_probe_synced_enabled = enabled
	CarVisuals.refresh_probe(_probe, enabled)

func _apply_visual() -> void:
	var config := car.config as CarConfig
	var visual_path: String = DEFAULT_VISUAL
	if config != null and not config.visual_path.is_empty():
		visual_path = config.visual_path
	var body := car.get_node_or_null("CarBody") as Node3D
	if body == null:
		return
	for child in body.get_children():
		if child is BodyRig:
			continue
		body.remove_child(child)
		child.queue_free()
	var visual := load(visual_path) as PackedScene
	if visual == null:
		return
	var instance: Node3D = visual.instantiate()
	instance.transform = CAR_ORIENT
	body.add_child(instance)
	CarVisuals.apply_paint(instance, CarVisuals.paint_profile_for(_car_id))
	_cache_visuals(instance)
	_ensure_car_probe(body)

func _cache_visuals(instance: Node3D) -> void:
	_visual_wheels = CarVisuals.resolve_wheel_nodes(instance, _car_id)
	_taillight_material = CarVisuals.find_named_material(instance, "taillight")
	_spin_angle = 0.0
	_visual_ready = true
