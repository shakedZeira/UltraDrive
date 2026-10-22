# scripts/vehicle/rival_car_visual.gd
class_name RivalCarVisual
extends Node3D

## Runtime visual dresser for AI rival cars. Lives on the rival `CarBody` node
## (scenes/vehicle/rival_car.tscn) and is the exact structural twin of
## PlayerCarController._apply_visual(): it instances a real car GLB from
## assets/cars/ under this node, rotates it by CarVisuals.CAR_ORIENT so the
## GLB's +Z nose lands on the body's -Z, then paints it through the shared
## CarVisuals clearcoat pipeline. Rivals previously rendered as a placeholder
## BoxMesh; this swaps that for the same GLB/paint/wheel rig the player's car
## uses, while leaving the physics body, colliders and the four Wheel* nodes
## untouched.
##
## Each rival picks a distinct GLB via RaceManager._assign_rival_visual, so a
## grid reads as a mixed field instead of N identical boxes. The node's own
## exports give a bare scene a real default (sports coupe) even when nothing
## assigns one.

## Fallback GLB when no config/override supplies one. Matches the player's
## PlayerCarController.DEFAULT_VISUAL.
const DEFAULT_VISUAL := "res://assets/cars/sports_coupe.glb"
## Garage car id pairing with the DEFAULT_VISUAL wheel table (WHEEL_GROUPS).
const DEFAULT_CAR_ID := "starter_car"

## Box fallback shown ONLY if the GLB fails to load, so a rival never renders
## as an invisible/missing car (the player path has no such guard; a rival is
## one of N cars on track and dropping it is much more visible).
const FALLBACK_BOX_SIZE := Vector3(1.8, 0.55, 4.0)
const FALLBACK_BOX_Y := 0.45

## GLB to instance (a car from assets/cars/). Overridden per rival at spawn.
@export var visual_path: String = DEFAULT_VISUAL
## Car id used to resolve WHEEL_GROUPS + the paint profile. Overridden per rival.
@export var car_id: String = DEFAULT_CAR_ID
## Skill tier for the RIVAL_PALETTE tint ("" = stock paint). RaceManager sets
## this before the node enters the tree.
@export var tier: String = ""

var _visual_root: Node3D = null
var _wheels: Dictionary = {}
var _spin_angle: float = 0.0
var _paint_profile: Dictionary = {}
var _taillight_materials: Array[StandardMaterial3D] = []

func _ready() -> void:
	# RaceManager assigns visual_path/car_id/tier BEFORE add_child, so the
	# visual is already built in that case; this covers a bare scene instance.
	if _visual_root == null:
		build()

## One-shot assignment seam (used by RaceManager before the node joins the
## tree): records the GLB + car id + tier and builds immediately, so _ready
## sees a finished visual and skips a second build.
func apply_visual(path: String, id: String, tier_override: String = "") -> void:
	visual_path = path
	car_id = id
	tier = tier_override
	build()

## Tier-only repaint seam (GridSpawner.apply_tier_color routes here now that
## CarBody is a Node3D, not a MeshInstance3D). No-op when the tier is unchanged
## so a spawn that already set the tier does not rebuild a second time.
func set_tier(tier_override: String) -> void:
	if tier == tier_override:
		return
	tier = tier_override
	if _visual_root != null:
		build()

## The live GLB root (null before the first build, or if the GLB failed to
## load and the fallback box is up instead). Test-facing accessor.
func visual_root() -> Node3D:
	return _visual_root

## Paint profile the last build applied. Test-facing accessor.
func paint_profile() -> Dictionary:
	return _paint_profile

## Cached taillight material clones (plural: the R35 rear cluster is two
## nodes). Test-facing accessor.
func taillight_materials() -> Array[StandardMaterial3D]:
	return _taillight_materials

## Total resolved GLB wheel nodes across all four corners (0 = no visual).
func wheel_count() -> int:
	var count := 0
	for corner: Variant in _wheels.keys():
		var nodes: Array = _wheels.get(corner, [])
		count += nodes.size()
	return count

## Instances the GLB, orphans the previous one, and repaints. Mirrors
## PlayerCarController._apply_visual()'s clear-then-instance seam.
func build() -> void:
	_clear()
	var packed := load(visual_path) as PackedScene
	if packed == null:
		_build_fallback_box()
		return
	var instance: Node3D = packed.instantiate()
	instance.transform = CarVisuals.CAR_ORIENT
	add_child(instance)
	var profile := CarVisuals.rival_paint_profile(car_id, tier)
	CarVisuals.apply_paint(instance, profile)
	_paint_profile = profile
	_visual_root = instance
	_wheels = CarVisuals.resolve_wheel_nodes(instance, car_id)
	_taillight_materials = CarVisuals.find_named_materials(instance, "taillight")
	_spin_angle = 0.0

## Drives the GLB wheel spin/steer AND the rear lights from the parent
## VehiclePhysics readout — the same CarVisuals seam the player uses (brake
## ramp on every taillight clone, reverse white on gear < 0). Lights run even
## when no wheel nodes resolved, so a wheel-less visual still signals.
## Cheap: one get_drive_info() dict read per frame, skipped entirely for a
## visual-less body.
func _process(delta: float) -> void:
	var car := _find_car()
	if car == null or _visual_root == null:
		return
	var info := car.get_drive_info()
	var speed_kmh := float(info.get("speed_kmh", 0.0))
	var steer := float(info.get("steer", 0.0))
	if not _wheels.is_empty():
		_spin_angle = _spin_angle + CarVisuals.wheel_spin_rate(speed_kmh, CarVisuals.WHEEL_RADIUS) * delta
		CarVisuals.apply_wheel_visuals(_wheels, steer, _spin_angle)
	CarVisuals.apply_brake_glow_all(_taillight_materials, float(info.get("brake", 0.0)))
	CarVisuals.apply_reverse_glow(_taillight_materials, int(info.get("gear", 0)) < 0)

func _find_car() -> VehiclePhysics:
	var node := get_parent()
	while node != null:
		if node is VehiclePhysics:
			return node as VehiclePhysics
		node = node.get_parent()
	return null

func _clear() -> void:
	_visual_root = null
	_wheels = {}
	_taillight_materials = []
	for child in get_children():
		remove_child(child)
		child.queue_free()

## Last-resort visible body when the GLB cannot be loaded.
func _build_fallback_box() -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "FallbackBox"
	var mesh := BoxMesh.new()
	mesh.size = FALLBACK_BOX_SIZE
	var material := StandardMaterial3D.new()
	material.albedo_color = CarVisuals.RIVAL_PALETTE.get(RacingLine.normalize_tier(tier), CarVisuals.RIVAL_PALETTE["Skilled"])
	material.metallic = float(CarVisuals.DEFAULT_PAINT["metallic"])
	material.roughness = float(CarVisuals.DEFAULT_PAINT["roughness"])
	material.clearcoat_enabled = true
	material.clearcoat = float(CarVisuals.DEFAULT_PAINT["clearcoat"])
	material.clearcoat_roughness = float(CarVisuals.DEFAULT_PAINT["clearcoat_roughness"])
	mesh.surface_set_material(0, material)
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(0.0, FALLBACK_BOX_Y, 0.0)
	add_child(mesh_instance)
	_paint_profile = CarVisuals.rival_paint_profile(car_id, tier)
