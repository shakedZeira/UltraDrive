# scripts/vehicle/car_visuals.gd
class_name CarVisuals
extends RefCounted

## Shared runtime car dresser. Walks an instanced GLB visual tree and injects
## per-part StandardMaterial3D surface overrides (paint, glass, lights, tires,
## rims, trim) by matching embedded material names, so every car reads as an
## FH5/GT7-style clearcoat-over-metallic paint. All overrides are runtime
## clones: embedded materials are NEVER mutated.

const CAR_ORIENT := Transform3D(Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0)), Vector3.ZERO)

## GT7/FH6-style clearcoat-over-colored-metallic paint. The moderate metallic
## blends the swatch albedo into the specular/reflections ("colored metal
## reflections" from the C2 reference) so body paint carries its color under the
## directional sun; the clearcoat layer adds the glossy showroom response.
## Rim uses StandardMaterial3D.rim_tint to push a soft albedo-colored grazing
## highlight toward the light. Roughness stays >= 0.25 to keep the response
## headless/test-stable across every quality preset.
const DEFAULT_PAINT := {
	"metallic": 0.25,
	"roughness": 0.35,
	"clearcoat": 1.0,
	"clearcoat_roughness": 0.08,
	"rim": 0.15,
	"rim_tint": 0.6,
	"glass_metallic": 0.9,
	"glass_roughness": 0.05,
	"tail_emission_strength": 5.0,
}

## Per-car body paint colors for the CC0/Kenney garage line. Any car id keyed
## here gets its albedo painted at runtime through paint_profile_for(); ids
## missing from this table keep their source (embedded) albedo untouched, so the
## AI-built cars (sports_coupe / muscle_car / rally_hatch) never change.
const PAINT_COLORS := {
	"cc0_sedan_sports": Color(0.78, 0.12, 0.16, 1.0),      # Comet — competition red
	"cc0_hatchback_sports": Color(0.07, 0.42, 0.88, 1.0), # Hooligan — rally blue
	"cc0_race": Color(0.94, 0.63, 0.05, 1.0),             # Interceptor — racing gold
}

## CC0 wheels are a single composite mesh (tire + rim baked into one surface);
## paint them as dark gunmetal so the rubber reads dark while the rim sculpt
## still shows under the chase cam.
const CC0_WHEEL_COLOR := Color(0.09, 0.09, 0.11, 1.0)

## S13 garage paint swatches. A paint_id is persisted per car in the garage
## tuning block and resolves to a color here, so the garage repaints any owned
## car live without touching its base albedo. The first entries mirror the
## stock PAINT_COLORS so a default swatch matches every comp's base paint.
const PAINT_SWATCHES: Array[Dictionary] = [
	{"id": "competition_red", "name": "Competition Red", "color": Color(0.78, 0.12, 0.16, 1.0)},
	{"id": "rally_blue", "name": "Rally Blue", "color": Color(0.07, 0.42, 0.88, 1.0)},
	{"id": "racing_gold", "name": "Racing Gold", "color": Color(0.94, 0.63, 0.05, 1.0)},
	{"id": "pearl_white", "name": "Pearl White", "color": Color(0.92, 0.92, 0.94, 1.0)},
	{"id": "midnight", "name": "Midnight", "color": Color(0.10, 0.10, 0.13, 1.0)},
	{"id": "slate", "name": "Slate", "color": Color(0.40, 0.44, 0.50, 1.0)},
]

## Resolves a swatch id to its albedo. Unknown ids fall back to a neutral
## titanium-gray so garage paint never errors on a corrupt/hand-edited save.
static func paint_color_for(paint_id: String) -> Color:
	for swatch in PAINT_SWATCHES:
		if swatch["id"] == paint_id:
			return swatch["color"]
	return Color(0.45, 0.47, 0.52, 1.0)

## Empty means "no custom paint saved" (use the car's stock PAINT_COLORS entry,
## which is what apply-time paint_profile_for already does).
static func default_paint_id(_car_id: String) -> String:
	return ""

## Racing-line rival body colors keyed by skill tier: concrete colors make the
## start grid read instantly (silver = Novice, blue = Skilled, red = Expert).
const RIVAL_PALETTE := {
	"Novice": Color(0.78, 0.78, 0.82, 1.0),
	"Skilled": Color(0.16, 0.51, 0.87, 1.0),
	"Expert": Color(0.88, 0.24, 0.12, 1.0),
}

## Tint + transparency applied to CC0 glass that arrives flat-white through the
## Kenney 'colormap' fallback (the integrated GLBs carry no real glass mesh, but
## future kit cars may).
const CC0_GLASS_COLOR := Color(0.70, 0.82, 0.92, 0.55)

## Dark rubber tint for CC0 tire-surfaces reached via the 'colormap' fallback.
const CC0_TIRE_COLOR := Color(0.04, 0.04, 0.05, 1.0)

# --- Wheel dynamics / brake-glow (Task 4) ---

## Wheel radius (m) shared by every car visual; matches the physics tire
## radius hard-coded in VehiclePhysics (0.33 m).
const WHEEL_RADIUS := 0.33

## Maximum visual steering angle (rad), applied to the front wheels from the
## normalized -1..1 steer exposed by get_drive_info().
const STEER_VISUAL_MAX_RAD := 0.35

## Taillight emission_energy_multiplier range: idle running lights at
## BRAKE_GLOW_MIN, full brake at BRAKE_GLOW_MAX.
const BRAKE_GLOW_MIN := 1.8
const BRAKE_GLOW_MAX := 5.0

# --- Per-car gameplay ReflectionProbe (Task 6) ---

## Full box extents (m) for the car-body probe. Larger than the mesh so
## reflections read from every chase-cam angle without clipping the box.
const CAR_PROBE_SIZE := Vector3(8.0, 4.0, 8.0)

## Cubemap face resolution (px). 256 keeps UPDATE_ALWAYS cheap enough for the
## single per-car probe mandated by the project's 4-probe blend budget.
const CAR_PROBE_RESOLUTION := 256

## Moves the probe's capture camera above the body center so the world, not
## the car's own roof, dominates the cubemap. Must lie inside CAR_PROBE_SIZE.
const CAR_PROBE_ORIGIN_OFFSET := Vector3(0.0, 0.8, 0.0)

## Deterministic toggle. enabled=true: visible, UPDATE_ALWAYS (live cubemap so
## paint reflects the world every frame). enabled=false: hidden, UPDATE_ONCE
## (a hidden probe contributes nothing to the blend budget and never re-renders).
static func refresh_probe(probe: ReflectionProbe, enabled: bool) -> void:
	if probe == null:
		return
	if enabled:
		probe.visible = true
		probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
	else:
		probe.visible = false
		probe.update_mode = ReflectionProbe.UPDATE_ONCE

## Per-car wheel node-name table keyed off Garage car ids. "starter_car"
## renders the sports_coupe GLB. muscle_car and rally_hatch split each corner
## into separate Rim/Tire meshes. Corner shorthand: fl/fr/rl/rr.
const WHEEL_GROUPS := {
	"starter_car": {
		"fl": ["Wheel_FL"],
		"fr": ["Wheel_FR"],
		"rl": ["Wheel_RL"],
		"rr": ["Wheel_RR"],
	},
	"muscle_car": {
		"fl": ["MCW_Rim_FL", "MCW_Tire_FL"],
		"fr": ["MCW_Rim_FR", "MCW_Tire_FR"],
		"rl": ["MCW_Rim_RL", "MCW_Tire_RL"],
		"rr": ["MCW_Rim_RR", "MCW_Tire_RR"],
	},
	"rally_hatch": {
		"fl": ["Rim_LF", "Tire_LF"],
		"fr": ["Rim_RF", "Tire_RF"],
		"rl": ["Rim_LR", "Tire_LR"],
		"rr": ["Rim_RR", "Tire_RR"],
	},
	## Kenney Car Kit CC0 models (single wheel mesh per corner, named by side).
	"cc0_sedan_sports": {
		"fl": ["wheel-front-left"],
		"fr": ["wheel-front-right"],
		"rl": ["wheel-back-left"],
		"rr": ["wheel-back-right"],
	},
	"cc0_hatchback_sports": {
		"fl": ["wheel-front-left"],
		"fr": ["wheel-front-right"],
		"rl": ["wheel-back-left"],
		"rr": ["wheel-back-right"],
	},
	"cc0_race": {
		"fl": ["wheel-front-left"],
		"fr": ["wheel-front-right"],
		"rl": ["wheel-back-left"],
		"rr": ["wheel-back-right"],
	},
}

## Resolves the wheel Node3D groups for a car under a visual root. Returns a
## Dictionary of corner -> Array[Node3D] with only the corners whose nodes
## actually exist; never errors on missing nodes or unknown car ids.
static func resolve_wheel_nodes(visual_root: Node3D, car_id: String) -> Dictionary:
	var wheels := {}
	if visual_root == null:
		return wheels
	var table: Dictionary = WHEEL_GROUPS.get(car_id, {})
	for corner: String in ["fl", "fr", "rl", "rr"]:
		var names: Array = table.get(corner, [])
		var nodes: Array[Node3D] = []
		for raw_name: Variant in names:
			var node_name := String(raw_name)
			var node := visual_root.get_node_or_null(node_name) as Node3D
			if node != null:
				nodes.append(node)
		if not nodes.is_empty():
			wheels[corner] = nodes
	return wheels

## Spins every wheel around its local axle (X) by spin_angle and steers the
## front pair (fl/fr) around the vertical axis (Y) by steer (-1..1). Wheels
## roll forward by rotating negatively about +X (car nose faces +Z in GLB
## space; the axle runs along local X per the GLB wheel geometry).
static func apply_wheel_visuals(wheels: Dictionary, steer: float, spin_angle: float) -> void:
	var steer_rad := clampf(steer, -1.0, 1.0) * STEER_VISUAL_MAX_RAD
	for corner: Variant in wheels.keys():
		var corner_name := String(corner)
		var nodes: Array = wheels.get(corner, [])
		var front_pair: bool = corner_name == "fl" or corner_name == "fr"
		for node: Variant in nodes:
			var wheel := node as Node3D
			if wheel == null:
				continue
			wheel.rotation = Vector3(-spin_angle, steer_rad if front_pair else 0.0, 0.0)

## Revolutions-per-second-esque angular spin rate (rad/s) for a moving wheel.
## speed_kmh is translated to m/s and divided by the wheel radius.
static func wheel_spin_rate(speed_kmh: float, wheel_radius: float) -> float:
	if wheel_radius <= 0.0:
		return 0.0
	return speed_kmh / 3.6 / wheel_radius

## Depth-first search for the first StandardMaterial3D whose resource_name
## contains name_filter (case-insensitive). Checks surface override materials
## first so the live clone produced by apply_paint() is found.
static func find_named_material(root: Node3D, name_filter: String) -> StandardMaterial3D:
	if root == null:
		return null
	var needle := name_filter.to_lower()
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		var mesh: Mesh = mesh_instance.mesh
		if mesh != null:
			for surface_index in range(mesh.get_surface_count()):
				var material: Material = mesh_instance.get_surface_override_material(surface_index)
				if material == null:
					material = mesh.surface_get_material(surface_index)
				if material is StandardMaterial3D and material.resource_name.to_lower().contains(needle):
					return material as StandardMaterial3D
	for child: Variant in root.get_children():
		if child is Node3D:
			var found: StandardMaterial3D = find_named_material(child as Node3D, name_filter)
			if found != null:
				return found
	return null

## Ramps the taillight emission energy with brake (0..1): BRAKE_GLOW_MIN when
## coasting, BRAKE_GLOW_MAX at full brake. Enables emission if the material
## did not already keep it. Never allocates per call.
static func apply_brake_glow(material: StandardMaterial3D, brake: float) -> void:
	if material == null:
		return
	material.emission_enabled = true
	material.emission_energy_multiplier = lerpf(BRAKE_GLOW_MIN, BRAKE_GLOW_MAX, clampf(brake, 0.0, 1.0))

static func apply_paint(visual_root: Node3D, profile: Dictionary) -> void:
	if visual_root == null:
		return
	_paint_node(visual_root, profile)

## Returns the paint profile (DEFAULT_PAINT plus any extra CC0 albedo keys) for
## a garage car id. Cars without an entry in PAINT_COLORS get a bare DEFAULT_PAINT
## clone, so call sites can route every car through this helper risk-free.
## An optional paint_id (S13 garage swatch) overrides the albedo color, and any
## repainted car gets the CC0 glass/tire tinting so the new color reads across
## the whole shell. No paint_id = stock behavior unchanged.
static func paint_profile_for(car_id: String, paint_id: String = "") -> Dictionary:
	var profile: Dictionary = DEFAULT_PAINT.duplicate()
	if PAINT_COLORS.has(car_id):
		profile["color"] = PAINT_COLORS[car_id]
		profile["glass_color"] = CC0_GLASS_COLOR
		profile["tire_color"] = CC0_TIRE_COLOR
	if not paint_id.is_empty():
		profile["color"] = paint_color_for(paint_id)
		profile["glass_color"] = CC0_GLASS_COLOR
		profile["tire_color"] = CC0_TIRE_COLOR
	return profile

static func _paint_node(node: Node3D, profile: Dictionary) -> void:
	if node is MeshInstance3D:
		_paint_mesh_instance(node as MeshInstance3D, profile)
	for child in node.get_children():
		if child is Node3D:
			_paint_node(child as Node3D, profile)

static func _paint_mesh_instance(mesh_instance: MeshInstance3D, profile: Dictionary) -> void:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return
	var surface_count: int = mesh.get_surface_count()
	for surface_index in range(surface_count):
		var override_material: StandardMaterial3D = _make_override(mesh_instance, mesh, surface_index, profile)
		if override_material != null:
			mesh_instance.set_surface_override_material(surface_index, override_material)

static func _make_override(mesh_instance: MeshInstance3D, mesh: Mesh, surface_index: int, profile: Dictionary) -> StandardMaterial3D:
	var material: Material = _resolved_surface_material(mesh_instance, mesh, surface_index)
	if material == null:
		return null
	var standard: StandardMaterial3D = material as StandardMaterial3D
	if standard == null:
		return null
	var name := _surface_name(mesh_instance, mesh, surface_index)
	if name.contains("paint") or standard.clearcoat_enabled:
		return _paint_clone(standard, profile)
	if name.contains("glass") or name.contains("window") or name.contains("windshield"):
		return _glass_clone(standard, profile)
	if name.contains("headlight") or name.contains("taillight"):
		return _light_clone(standard)
	if name.contains("tire"):
		return _tire_clone(standard, profile)
	if name.contains("trim") or name.contains("graphite"):
		return _trim_clone(standard)
	if name.contains("rim"):
		return _rim_clone(standard)
	var cc0_override := _cc0_override(mesh_instance, name, standard, profile)
	if cc0_override != null:
		return cc0_override
	return null

## Kenney Car Kit GLBs bake every part under one flat-white 'colormap' material
## with no role keywords, so the material-name matcher alone leaves them plain
## white. Classify by mesh role instead: wheels are a composite tire+rim node,
## glass keeps the glass clone, and everything else on the shell is clearcoated
## paint. Gated on the 'colormap' material name, so AI-built cars (which never
## use it) are untouched.
static func _cc0_override(mesh_instance: MeshInstance3D, material_name: String, standard: StandardMaterial3D, profile: Dictionary) -> StandardMaterial3D:
	if material_name != "colormap":
		return null
	var node_name := String(mesh_instance.name).to_lower()
	if node_name.contains("glass"):
		return _glass_clone(standard, profile)
	if node_name.contains("tire"):
		return _tire_clone(standard, profile)
	if node_name.contains("rim"):
		return _rim_clone(standard)
	if node_name.contains("wheel"):
		return _cc0_wheel_clone(standard)
	return _paint_clone(standard, profile)

static func _resolved_surface_material(mesh_instance: MeshInstance3D, mesh: Mesh, surface_index: int) -> Material:
	var override_material: Material = mesh_instance.get_surface_override_material(surface_index)
	if override_material != null:
		return override_material
	return mesh.surface_get_material(surface_index)

static func _surface_name(mesh_instance: MeshInstance3D, mesh: Mesh, surface_index: int) -> String:
	var material: Material = _resolved_surface_material(mesh_instance, mesh, surface_index)
	if material != null and not material.resource_name.is_empty():
		return material.resource_name.to_lower()
	var embedded: Material = mesh.surface_get_material(surface_index)
	if embedded != null and not embedded.resource_name.is_empty():
		return embedded.resource_name.to_lower()
	return ""

static func _paint_clone(source: StandardMaterial3D, profile: Dictionary) -> StandardMaterial3D:
	var cloned: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	if profile.has("color"):
		cloned.albedo_color = profile["color"]
	cloned.clearcoat_enabled = true
	cloned.clearcoat = profile["clearcoat"]
	cloned.clearcoat_roughness = profile["clearcoat_roughness"]
	cloned.metallic = profile["metallic"]
	cloned.roughness = profile["roughness"]
	if profile.has("rim"):
		cloned.rim_enabled = true
		cloned.rim = profile["rim"]
	if profile.has("rim_tint"):
		cloned.rim_tint = profile["rim_tint"]
	return cloned

static func _glass_clone(source: StandardMaterial3D, profile: Dictionary) -> StandardMaterial3D:
	var cloned: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	if profile.has("glass_color"):
		cloned.albedo_color = profile["glass_color"]
	cloned.metallic = profile["glass_metallic"]
	cloned.roughness = profile["glass_roughness"]
	cloned.refraction_enabled = false
	return cloned

static func _light_clone(source: StandardMaterial3D) -> StandardMaterial3D:
	var cloned: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	cloned.metallic = 0.0
	cloned.roughness = 0.4
	return cloned

static func _tire_clone(source: StandardMaterial3D, profile: Dictionary) -> StandardMaterial3D:
	var cloned: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	if profile.has("tire_color"):
		cloned.albedo_color = profile["tire_color"]
	cloned.metallic = 0.0
	cloned.roughness = 0.95
	return cloned

static func _rim_clone(source: StandardMaterial3D) -> StandardMaterial3D:
	var cloned: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	cloned.metallic = 0.9
	cloned.roughness = 0.15
	return cloned

static func _cc0_wheel_clone(source: StandardMaterial3D) -> StandardMaterial3D:
	var cloned: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	cloned.albedo_color = CC0_WHEEL_COLOR
	cloned.metallic = 0.35
	cloned.roughness = 0.4
	cloned.clearcoat_enabled = true
	cloned.clearcoat = 0.6
	cloned.clearcoat_roughness = 0.2
	return cloned

static func _trim_clone(source: StandardMaterial3D) -> StandardMaterial3D:
	var cloned: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	cloned.metallic = 0.85
	cloned.roughness = 0.45
	return cloned

static func paint_surface_count(root: Node3D) -> int:
	if root == null:
		return 0
	return _matching_surface_count(root)

static func _matching_surface_count(node: Node3D) -> int:
	var count := 0
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh: Mesh = mesh_instance.mesh
		if mesh != null:
			for surface_index in range(mesh.get_surface_count()):
				if mesh_instance.get_surface_override_material(surface_index) != null:
					count += 1
	for child in node.get_children():
		if child is Node3D:
			count += _matching_surface_count(child as Node3D)
	return count