# scripts/ui/grid_spawner.gd
class_name GridSpawner
extends Node

## Runtime rival grid builder (S5). Attach as a child of the race scene root and
## call build_grid() once a rival roster is configured: it instantiates a rival
## vehicle per spec, paints it with the tier color, attaches a RivalDriver
## configured for that tier + car class, and places each car into a staggered
## start grid ahead of the player. Concrete-node based (no physics-server
## hacks), so spawned cars behave exactly like runtime rivals — and it can be
## reused as the RaceManager.rival_spawner callback: spawner.call(config, tier).

const GRID_COLUMNS := 2
const ROW_SPACING := 6.0
const COL_SPACING := 3.0
const ANCHOR_AHEAD := 8.0
const START_Y := 0.3

var scene: PackedScene = preload("res://scenes/vehicle/rival_car.tscn")
var line_source: Callable = Callable()

static func build_spec(car_config: CarConfig, tier: String) -> Dictionary:
	return {"car_config": car_config, "tier": tier}

func build_grid(
		player: VehiclePhysics,
		specs: Array[Dictionary],
		centerline: Array[Vector3]) -> Array[VehiclePhysics]:
	var cars: Array[VehiclePhysics] = []
	if player == null or specs.is_empty():
		return cars
	for i in range(specs.size()):
		var row := i / GRID_COLUMNS
		var col := i % GRID_COLUMNS
		var offset := Vector3(
			(float(col) - 0.5) * COL_SPACING,
			START_Y,
			ANCHOR_AHEAD + float(row) * ROW_SPACING)
		var car := _build_car(specs[i], player.global_position + offset, i)
		if car != null:
			cars.append(car)
	return cars

func _build_car(spec: Dictionary, position: Vector3, index: int = 0) -> VehiclePhysics:
	if scene == null:
		return null
	var cfg := spec.get("car_config") as CarConfig
	var tier := String(spec.get("tier", "Skilled"))
	var car := scene.instantiate() as VehiclePhysics
	if car == null:
		return null
	if cfg != null:
		car.config = cfg
	# Real car GLB, cycled per grid slot so the field is mixed (not N boxes).
	# Before add_child, so RivalCarVisual builds once in its _ready.
	CarVisuals.assign_rival_visual(car, index, tier)
	car.global_position = position
	car.global_rotation = Vector3.ZERO
	add_child(car)
	_apply_tier_color(car, tier)
	var driver := RivalDriver.new()
	var line: Array[Vector3] = []
	if line_source.is_valid():
		line = line_source.call(cfg, tier)
	driver.configure(line, tier, cfg.car_class if cfg != null else "D")
	car.add_child(driver)
	return car

func _apply_tier_color(car: VehiclePhysics, tier: String) -> void:
	apply_tier_color(car, tier)

## Paints a rival car's body with its skill-tier color (shared by the spawner
## path and RaceManager's own rival spawn). Static so RaceManager can color the
## cars it builds directly without instantiating a GridSpawner child.
##
## CarBody is a RivalCarVisual (a Node3D hosting a real car GLB), so the tier
## tint is applied through that node's paint profile. The legacy MeshInstance3D
## branch is kept for any custom scene that still ships a box body.
static func apply_tier_color(car: VehiclePhysics, tier: String) -> void:
	if car == null:
		return
	var body_node := car.get_node_or_null("CarBody")
	var visual := body_node as RivalCarVisual
	if visual != null:
		visual.set_tier(tier)
		return
	var body := body_node as MeshInstance3D
	if body == null or body.mesh == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = CarVisuals.RIVAL_PALETTE.get(RacingLine.normalize_tier(tier), CarVisuals.RIVAL_PALETTE["Skilled"])
	material.metallic = CarVisuals.DEFAULT_PAINT["metallic"]
	material.roughness = CarVisuals.DEFAULT_PAINT["roughness"]
	material.clearcoat_enabled = true
	material.clearcoat = CarVisuals.DEFAULT_PAINT["clearcoat"]
	material.clearcoat_roughness = CarVisuals.DEFAULT_PAINT["clearcoat_roughness"]
	body.material_override = material