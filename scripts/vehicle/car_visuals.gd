# scripts/vehicle/car_visuals.gd
class_name CarVisuals
extends RefCounted

## Shared runtime car dresser. Walks an instanced GLB visual tree and injects
## per-part StandardMaterial3D surface overrides (paint, glass, lights, tires,
## rims, trim) by matching embedded material names, so every car reads as an
## FH5/GT7-style clearcoat-over-metallic paint. All overrides are runtime
## clones: embedded materials are NEVER mutated.

## CAR_ORIENT's basis, hoisted so the night-lamp mount math (headlight_forward /
## body_mount) folds a plain Basis instead of reaching into a Transform3D
## member. Rotates the GLB 180 deg about Y: the visual's +Z nose lands on the
## car body's -Z.
const CAR_ORIENT_BASIS := Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0))
const CAR_ORIENT := Transform3D(CAR_ORIENT_BASIS, Vector3.ZERO)

## GT7/FH6-style clearcoat-over-colored-metallic paint. The mid metallic
## blends the swatch albedo into the specular/reflections ("colored metal
## reflections" from the C2 reference) so body paint carries its color under
## the directional sun; metallic_specular lifts the dielectric fresnel lobe
## so panel edges catch a bright grazing highlight instead of reading matte;
## the clearcoat layer adds the glossy showroom response over a near-mirror
## coat roughness. The base splits into two deterministic roughness bands
## (sharp primary panels vs slightly rougher secondary bodywork) so a shell
## never reads as one uniform sheet. Rim uses StandardMaterial3D.rim_tint to
## push a soft albedo-colored grazing highlight toward the light. Both
## roughness bands stay >= 0.25 to keep the response headless/test-stable
## across every quality preset.
const DEFAULT_PAINT := {
	"metallic": 0.5,
	"roughness": 0.25,
	"roughness_secondary": 0.34,
	"clearcoat": 1.0,
	"clearcoat_roughness": 0.04,
	"metallic_specular": 0.75,
	"rim": 0.22,
	"rim_tint": 0.6,
	"glass_metallic": 0.0,
	"glass_roughness": 0.05,
	"tail_emission_strength": 5.0,
}

## Painted aero/secondary bodywork keywords. A surface whose material OR mesh
## node name contains one of these takes the profile's roughness_secondary
## band; everything else (hood, roof, doors, the main 'body' shell) takes the
## sharp roughness band. Pure case-insensitive name lookup — deterministic
## across runs, machines and quality presets, with no seeded randomness.
const SECONDARY_PAINT_PARTS: Array[String] = [
	"spoiler", "wing", "bumper", "splitter", "diffuser", "skirt", "valance"
]

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

## Rival GLB rotation list. Rivals cycle this at spawn (RaceManager
## _assign_rival_visual -> RivalCarVisual) so the grid reads as a mixed field
## rather than N identical boxes. Each entry pairs a real car GLB from
## assets/cars/ with the WHEEL_GROUPS id that names its corner wheel nodes.
const RIVAL_VISUALS: Array[Dictionary] = [
	{"visual_path": "res://assets/cars/sports_coupe.glb", "car_id": "starter_car"},
	{"visual_path": "res://assets/cars/muscle_car.glb", "car_id": "muscle_car"},
	{"visual_path": "res://assets/cars/rally_hatch.glb", "car_id": "rally_hatch"},
]

## Deterministic per-slot rival visual: wraps `index` over RIVAL_VISUALS, so
## grid slot 0..n gets a stable-but-varied GLB with no RNG anywhere.
static func rival_visual_for(index: int) -> Dictionary:
	var slot := posmod(index, RIVAL_VISUALS.size())
	return RIVAL_VISUALS[slot]

## Paint profile for a rival: the car's stock profile with the skill-tier
## RIVAL_PALETTE color layered on as the shell albedo. An empty/unknown tier
## falls back to the "Skilled" swatch so a rival is always concretely colored.
static func rival_paint_profile(car_id: String, tier: String) -> Dictionary:
	var profile := paint_profile_for(car_id)
	profile["color"] = RIVAL_PALETTE.get(RacingLine.normalize_tier(tier), RIVAL_PALETTE["Skilled"])
	return profile

## Applies a cycled rival GLB + tier paint to a spawned rival. Shared by
## RaceManager._spawn_rival_car and GridSpawner._build_car so every spawn path
## produces the same mixed, tier-colored grid. No-ops when the car exposes no
## RivalCarVisual body (a custom rival_spawner scene), keeping the seam safe.
static func assign_rival_visual(car: Node, index: int, tier: String) -> void:
	if car == null:
		return
	var body := car.get_node_or_null("CarBody")
	if body == null or not body.has_method("apply_visual"):
		return
	var visual := rival_visual_for(index)
	body.call("apply_visual", String(visual["visual_path"]), String(visual["car_id"]), tier)

## Tint + transparency applied to CC0 glass that arrives flat-white through the
## Kenney 'colormap' fallback (the integrated GLBs carry no real glass mesh, but
## future kit cars may).
const CC0_GLASS_COLOR := Color(0.70, 0.82, 0.92, 0.55)

## Default cool-tinted, semi-transparent glass for cars whose paint profile
## carries no glass_color (builder/AI cars). alpha < 1 is the whole point: the
## pane must transmit, not mirror. TRANSPARENCY_ALPHA only transmits while
## albedo_color.a < 1, so a profile-supplied glass_color MUST keep alpha < 1.
const DEFAULT_GLASS_COLOR := Color(0.42, 0.50, 0.58, 0.45)

## Dark rubber tint for CC0 tire-surfaces reached via the 'colormap' fallback.
const CC0_TIRE_COLOR := Color(0.04, 0.04, 0.05, 1.0)

# --- Wheel dynamics / brake-glow (Task 4) ---

## Wheel radius (m) shared by every car visual; matches the physics tire
## radius hard-coded in VehiclePhysics (0.33 m).
const WHEEL_RADIUS := 0.33

## Maximum visual steering angle (rad), applied to the front wheels from the
## normalized -1..1 steer exposed by get_drive_info().
const STEER_VISUAL_MAX_RAD := 0.35

## Local-position epsilon (m) below which a resolved wheel node is considered to
## sit at its parent's origin — i.e. the corner is NOT carried by the node
## transform (see _normalize_wheel_origin).
const WHEEL_ORIGIN_EPS := 0.001

## Mesh-AABB center offset (m) beyond which such an origin-less wheel node is
## treated as corner-BAKED (vertices authored in car space around the corner, as
## in muscle_car.glb's MCW_* and rally_hatch.glb's Rim_*/Tire_* wheels). A real
## hub-centred wheel mesh hugs its own origin far below this.
const BAKED_WHEEL_CORNER_MIN := 0.25

## Taillight emission_energy_multiplier range: idle running lights at
## BRAKE_GLOW_MIN, full brake at BRAKE_GLOW_MAX.
const BRAKE_GLOW_MIN := 1.8
const BRAKE_GLOW_MAX := 5.0

# --- Reverse glow (existing rear lamps, brightened white) ---
#
# The reverse cue rides the car's EXISTING taillight materials: while reverse is
# engaged they glow this bright white; on release the GLB-authored base emissive
# colour is restored so the red brake ramp resumes. No geometry is built — an
# earlier pass added a white lamp mesh and a playtest read it as an extra light
# (see the REVISION note in docs/plans/gtr_r35_lights_glass_plan.md).
const REVERSE_LIGHT_COLOR := Color(1.0, 0.98, 0.92, 1.0)
const REVERSE_LIGHT_ENERGY := 6.0
## Meta key holding a material's GLB-authored base emission while the reverse
## white is applied; its absence means "not currently whitened".
const REVERSE_GLOW_META := "ud_reverse_base_emission"

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
	## Builder-generated car: one Wheel_* hub empty per corner (the game
	## overwrites hub.rotation with (spin, steer, 0), so all corner geometry
	## lives under the hub).
	"nissan_gt_r35_2017": {
		"fl": ["Wheel_FL"],
		"fr": ["Wheel_FR"],
		"rl": ["Wheel_RL"],
		"rr": ["Wheel_RR"],
	},
}

## Resolves the wheel Node3D groups for a car under a visual root. Returns a
## Dictionary of corner -> Array[Node3D] with only the corners whose nodes
## actually exist; never errors on missing nodes or unknown car ids.
##
## Depth-independent ON PURPOSE: Godot wraps a single-root glTF scene in an
## extra root node, so a wheel authored as that scene's root node sits one level
## BELOW the instance root (`sports_coupe.glb` -> `sports_coupe` -> `SportsCoupe`
## -> `Wheel_FL`; likewise `muscle_car.glb` and `rally_hatch.glb`). Cars whose
## glTF scene has several root nodes (R35, the CC0 Kimmi kits) put their wheels
## directly under the instance root. A plain `get_node_or_null()` therefore
## found NO wheel for the player's starter car / muscle / rally cars, which
## silently killed their wheel spin and steering. Exact name first (cheap), then
## a recursive search so authoring depth cannot break the lookup.
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
			if node == null:
				node = visual_root.find_child(node_name, true, false) as Node3D
			if node != null:
				_normalize_wheel_origin(node)
				nodes.append(node)
		if not nodes.is_empty():
			wheels[corner] = nodes
	return wheels

## Recentres a wheel whose corner is baked into its MESH vertices instead of the
## node transform (node origin therefore sits at the car centre — the GLB node
## carries no translation, as authored in muscle_car.glb's MCW_* and
## rally_hatch.glb's Rim_*/Tire_* wheels). apply_wheel_visuals rotates the
## resolved node about ITS OWN origin, so an un-normalized baked wheel orbits
## the whole car body instead of spinning on its axle. Normalisation moves the
## node onto the corner and translates a runtime mesh COPY by -aabb_center,
## making the node origin the wheel centre exactly like the coupe/CC0 hubs.
## No-op for already-centred hubs (sports_coupe, the cc0 kits, the R35) and for
## mesh-less stub nodes; the embedded GLB mesh is duplicated first, matching the
## paint pipeline's clone-only "never mutate the source" rule.
static func _normalize_wheel_origin(wheel: Node3D) -> void:
	if wheel == null or wheel.position.length() > WHEEL_ORIGIN_EPS:
		return
	var mesh_instance := wheel as MeshInstance3D
	if mesh_instance == null:
		return
	var mesh := mesh_instance.mesh
	if mesh == null:
		return
	var center := mesh.get_aabb().get_center()
	if center.length() < BAKED_WHEEL_CORNER_MIN:
		return
	var recentered := _mesh_translated(mesh, -center)
	if recentered == null or recentered.get_surface_count() == 0:
		return
	mesh_instance.mesh = recentered
	wheel.position = center

## ArrayMesh copy of `mesh` with every vertex offset by `offset` (per-surface
## array rewrite; a translation leaves normals unchanged, and embedded surface
## materials are carried over so the paint pipeline's fallback lookup still
## finds them). Returns null for non-ArrayMesh primitives, which
## _normalize_wheel_origin then leaves untouched.
static func _mesh_translated(mesh: Mesh, offset: Vector3) -> ArrayMesh:
	var array_mesh := mesh as ArrayMesh
	if array_mesh == null:
		return null
	var out := ArrayMesh.new()
	for surface_index in range(array_mesh.get_surface_count()):
		var arrays := array_mesh.surface_get_arrays(surface_index)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in range(positions.size()):
			positions[i] = positions[i] + offset
		arrays[Mesh.ARRAY_VERTEX] = positions
		out.add_surface_from_arrays(array_mesh.surface_get_primitive_type(surface_index), arrays)
		var embedded := array_mesh.surface_get_material(surface_index)
		if embedded != null:
			out.surface_set_material(out.get_surface_count() - 1, embedded)
	return out

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

## DFS for EVERY StandardMaterial3D whose resource_name contains name_filter
## (case-insensitive), deduped by instance. Surface overrides are checked first
## so the live clones produced by apply_paint() are found. Sibling of
## find_named_material(), which is kept as the "first match" convenience. The
## plural form exists because a rear cluster can span TWO mesh nodes (the R35
## has Taillight_L + Taillight_R, each cloning the shared GLB material) — a
## single-match cache would only ever ramp one half of the four lamps.
static func find_named_materials(root: Node3D, name_filter: String) -> Array[StandardMaterial3D]:
	var out: Array[StandardMaterial3D] = []
	if root == null:
		return out
	_collect_named_materials(root, name_filter.to_lower(), out, {})
	return out

static func _collect_named_materials(node: Node3D, needle: String,
		out: Array[StandardMaterial3D], seen: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh: Mesh = mesh_instance.mesh
		if mesh != null:
			for surface_index in range(mesh.get_surface_count()):
				var material: Material = mesh_instance.get_surface_override_material(surface_index)
				if material == null:
					material = mesh.surface_get_material(surface_index)
				if material is StandardMaterial3D \
						and material.resource_name.to_lower().contains(needle):
					var id := material.get_instance_id()
					if not seen.has(id):
						seen[id] = true
						out.append(material as StandardMaterial3D)
	for child: Node in node.get_children():
		if child is Node3D:
			_collect_named_materials(child as Node3D, needle, out, seen)

## First-match convenience over find_named_materials() — kept as the singular
## seam because existing call sites and tests resolve exactly one material
## (e.g. the CC0 glass or a single-node taillight).
static func find_named_material(root: Node3D, name_filter: String) -> StandardMaterial3D:
	var all := find_named_materials(root, name_filter)
	return all[0] if not all.is_empty() else null

## Ramps the taillight emission energy with brake (0..1): BRAKE_GLOW_MIN when
## coasting, BRAKE_GLOW_MAX at full brake. Enables emission if the material
## did not already keep it. Never allocates per call.
static func apply_brake_glow(material: StandardMaterial3D, brake: float) -> void:
	if material == null:
		return
	material.emission_enabled = true
	material.emission_energy_multiplier = lerpf(BRAKE_GLOW_MIN, BRAKE_GLOW_MAX, clampf(brake, 0.0, 1.0))

## Applies apply_brake_glow to every cached taillight material (the R35 rear
## cluster is TWO nodes / two clones). Never allocates.
static func apply_brake_glow_all(materials: Array[StandardMaterial3D], brake: float) -> void:
	for material in materials:
		apply_brake_glow(material, brake)

# --- Reverse glow switch (see REVERSE_* constants above) ---

## Idempotent reverse cue: while `active`, every EXISTING taillight material
## glows bright white (saving the GLB-authored base emissive colour first);
## when inactive the base colour is restored so the red brake ramp resumes.
## Never allocates per call; safe on null elements.
static func apply_reverse_glow(materials: Array[StandardMaterial3D], active: bool) -> void:
	for material in materials:
		if material == null:
			continue
		material.emission_enabled = true
		if active:
			if not material.has_meta(REVERSE_GLOW_META):
				material.set_meta(REVERSE_GLOW_META, material.emission)
			material.emission = REVERSE_LIGHT_COLOR
			material.emission_energy_multiplier = REVERSE_LIGHT_ENERGY
		elif material.has_meta(REVERSE_GLOW_META):
			var base: Color = material.get_meta(REVERSE_GLOW_META)
			material.emission = base
			material.remove_meta(REVERSE_GLOW_META)

# --- Night headlight/taillight layer (roadmap #5) ---
#
# apply_paint() only TINTS the GLB's headlight/taillight materials, so nothing
# actually lit the road at night. This section owns the real Light3D layer:
# a pure clock-hour -> intensity map (no scene, no autoload, no clock) plus a
# factory that builds the lamp nodes and a switch that ramps them. The player
# controller owns the node lifetime (rebuilt with the visual, see
# _ensure_night_lamps); the traffic Headlights class is the binary twin.

## Sun-elevation bounds of the dusk/dawn ramp. The DayNightDriver-owned clock
## drives WeatherManager's sun arc, whose NORMALIZED direction y climbs from
## -0.958 (midnight) through 0.0 (the 06:00 / 18:00 horizon crossings) to
## +0.958 (noon) -- see WeatherManager.get_computed_sun_position() -- so these
## two numbers ARE the ramp: at/above HEADLIGHT_RAMP_DAY the lamps are fully
## off, at/below HEADLIGHT_RAMP_NIGHT fully on, and the band between is the
## twilight fade. This is deliberately NOT WeatherManager.is_night()
## (elevation < 0): the lamps must come on BEFORE dark and off AFTER dawn.
const HEADLIGHT_RAMP_DAY := 0.35
const HEADLIGHT_RAMP_NIGHT := -0.15

## Mapped intensity above which the lamp nodes are switched on. A hair above
## zero so full daylight (intensity exactly 0.0) always reads as "off" and can
## never leave a stale visible light behind.
const HEADLIGHT_ON_THRESHOLD := 0.02

## Mapped-intensity delta that re-applies lamp energy. The clock wraps 24h per
## DAY_LENGTH_SECONDS (2400s), so one frame moves intensity by ~1.7e-5 -- far
## below this, which keeps the per-frame poll a bare float compare.
const HEADLIGHT_INTENSITY_EPSILON := 0.002

## Lamp energy at full night, matching the existing Headlights class so the two
## layers never disagree about brightness. Shadows stay off: these are a
## gameplay lighting cue, not a lighting authority, and two shadow-casting
## spots per car would blow the light budget.
const HEADLIGHT_MAX_ENERGY := 3.0
const HEADLIGHT_SPOT_ANGLE_DEG := 35.0
const HEADLIGHT_SPOT_RANGE := 60.0
const HEADLIGHT_COLOR := Color(1.0, 0.95, 0.86, 1.0)

## Rear tail cue: a short-range red omni so the car reads as lit from behind
## (and drops a red pool on the road) without a third spot.
const TAIL_LIGHT_MAX_ENERGY := 1.4
const TAIL_LIGHT_RANGE := 5.0
const TAIL_LIGHT_COLOR := Color(1.0, 0.12, 0.08)

## GLB-space (nose +Z) lamp mount points, ordered [left, right], plus the rear
## tail mount. Converted to car-body space by body_mount(). The GLB is authored
## nose +Z, so its +X is the car's left; CAR_ORIENT's 180 deg Y flip mirrors
## both axes and lands that entry on the body-space -X, which is where a -Z
## forward body puts the driver's left.
const HEADLIGHT_MOUNT_LOCALS: Array[Vector3] = [
	Vector3(0.65, 0.70, 1.35),
	Vector3(-0.65, 0.70, 1.35),
]
const TAIL_LIGHT_MOUNT_LOCAL := Vector3(0.0, 0.72, -1.45)

## Node names inside the built layer (also the lookup keys tests assert on).
const NIGHT_LAMP_HOLDER := "NightLamps"
const HEADLIGHT_L_NAME := "HeadlightL"
const HEADLIGHT_R_NAME := "HeadlightR"
const TAIL_LAMP_NAME := "TaillightGlow"

## Group tag on the built holder, so the layer is findable from the scene tree
## (get_first_node_in_group) without knowing which car body owns it.
const NIGHT_LAMP_GROUP := "night_lamps"

## Pure clock-hour -> sun elevation: the y component of WeatherManager's sun
## direction, re-derived here on the SAME normalized arc (angle =
## hour/24*360 - 90, then Vector3(cos, sin, 0.3).normalized()) so the mapping
## is scene-free, autoload-free and provably agrees with
## WeatherManager.is_night() -- the documented single night authority.
## fposmod keeps out-of-range hours (advance_time wraps at 24) on that arc.
static func sun_elevation(hour: float) -> float:
	var angle := deg_to_rad(fposmod(hour, 24.0) / 24.0 * 360.0 - 90.0)
	return Vector3(cos(angle), sin(angle), 0.3).normalized().y

## Same predicate as WeatherManager.is_night(), expressed on a raw hour so the
## suite can pin the below-horizon boundary without touching the autoload.
static func is_night_hour(hour: float) -> bool:
	return sun_elevation(hour) < 0.0

## Pure time-of-day -> headlight intensity: 0.0 in full daylight, 1.0 deep at
## night, linear across the dusk/dawn band. Deterministic by construction --
## the arc puts 0.0 from ~07:25 to ~16:35, 0.7 exactly on the horizon
## crossings (18:00 sunset / 06:00 sunrise) and 1.0 by ~18:35 / 05:25, so the
## lamps read as on before the road is dark and fade out after dawn.
static func headlight_intensity_for(hour: float) -> float:
	var elevation := sun_elevation(hour)
	var span := HEADLIGHT_RAMP_DAY - HEADLIGHT_RAMP_NIGHT
	return clampf((HEADLIGHT_RAMP_DAY - elevation) / span, 0.0, 1.0)

## Whether the lamp nodes should be lit at a mapped intensity.
static func headlight_lights_on(intensity: float) -> bool:
	return intensity > HEADLIGHT_ON_THRESHOLD

# --- Manual override (X / Cross) ---
#
# The driver-facing switch layered on top of the clock map: X / Cross cycles
# OFF -> ON -> AUTO, so the same button both forces the lamps and hands control
# back to time-of-day. Both helpers are pure (mode in, intensity out) so the
# whole decision is assertable without a car, a scene or a clock.

enum LampMode { AUTO = 0, OFF = 1, ON = 2 }

## The X / Cross cycle. AUTO first, so the very first press can only ever
## REDUCE what the world is asking for (silence the lamps at night); the second
## press forces them and the third hands them back to the clock.
static func next_lamp_mode(mode: LampMode) -> LampMode:
	match mode:
		LampMode.AUTO:
			return LampMode.OFF
		LampMode.OFF:
			return LampMode.ON
		LampMode.ON:
			return LampMode.AUTO
	return LampMode.AUTO

## Resolved lamp intensity for a mode at a raw clock hour: OFF is pinned to
## 0.0 and ON to 1.0 regardless of the hour, AUTO delegates to the day/night
## ramp above. In bounds by construction -- the manual pins ARE the bounds.
static func resolve_lamp_intensity(mode: LampMode, hour: float) -> float:
	match mode:
		LampMode.OFF:
			return 0.0
		LampMode.ON:
			return 1.0
		LampMode.AUTO:
			return headlight_intensity_for(hour)
	return headlight_intensity_for(hour)

## Forward (+nose) direction in car-body space. CAR_ORIENT maps the GLB's +Z
## nose onto the body's -Z, which is also a SpotLight3D's emission axis, so an
## unrotated lamp parented to the body already aims down the road.
static func headlight_forward() -> Vector3:
	return (CAR_ORIENT_BASIS * Vector3(0.0, 0.0, 1.0)).normalized()

## GLB-space mount point -> car-body space, so offsets authored against the
## nose-+Z visual stay pinned to the real bodywork. Note the 180 deg Y flip
## mirrors BOTH axes: GLB +X (car left) becomes body -X, GLB +Z (nose) becomes
## body -Z.
static func body_mount(local_point: Vector3) -> Vector3:
	return CAR_ORIENT_BASIS * local_point

## Builds the whole night layer: a holder Node3D carrying the two forward
## spots and the rear red omni, aimed along headlight_forward() and sitting on
## body_mount() offsets. Pure factory (no scene, no autoload) so the structure
## is assertable without a car. Lamps ship hidden at zero energy and are
## switched by apply_lamp_intensity().
static func build_night_lamps() -> Node3D:
	var holder := Node3D.new()
	holder.name = NIGHT_LAMP_HOLDER
	holder.add_to_group(NIGHT_LAMP_GROUP)
	for index in HEADLIGHT_MOUNT_LOCALS.size():
		var mount: Vector3 = HEADLIGHT_MOUNT_LOCALS[index]
		var spot := SpotLight3D.new()
		spot.name = HEADLIGHT_L_NAME if index == 0 else HEADLIGHT_R_NAME
		spot.position = body_mount(mount)
		spot.light_color = HEADLIGHT_COLOR
		spot.light_energy = 0.0
		spot.spot_angle = HEADLIGHT_SPOT_ANGLE_DEG
		spot.spot_range = HEADLIGHT_SPOT_RANGE
		spot.shadow_enabled = false
		spot.visible = false
		holder.add_child(spot)
	var tail := OmniLight3D.new()
	tail.name = TAIL_LAMP_NAME
	tail.position = body_mount(TAIL_LIGHT_MOUNT_LOCAL)
	tail.light_color = TAIL_LIGHT_COLOR
	tail.light_energy = 0.0
	tail.omni_range = TAIL_LIGHT_RANGE
	tail.shadow_enabled = false
	tail.visible = false
	holder.add_child(tail)
	return holder

## Switches a built night layer for a mapped intensity: hidden and zero-energy
## in daylight, energy ramping with the intensity through dusk, full at night.
## Idempotent and allocation-free, so the per-frame clock poll is just a float
## compare (see HEADLIGHT_INTENSITY_EPSILON).
static func apply_lamp_intensity(lamps: Node3D, intensity: float) -> void:
	if lamps == null:
		return
	var on := headlight_lights_on(intensity)
	var level := clampf(intensity, 0.0, 1.0)
	for child: Node in lamps.get_children():
		if child is SpotLight3D:
			var spot := child as SpotLight3D
			spot.light_energy = HEADLIGHT_MAX_ENERGY * level
			spot.visible = on
		elif child is OmniLight3D:
			var omni := child as OmniLight3D
			omni.light_energy = TAIL_LIGHT_MAX_ENERGY * level
			omni.visible = on

## Light-node count of a built night layer (2 spots + 1 omni).
static func night_lamp_count(lamps: Node3D) -> int:
	if lamps == null:
		return 0
	var count := 0
	for child: Node in lamps.get_children():
		if child is Light3D:
			count += 1
	return count

## True when any lamp in the layer is currently lit -- the "lights are on"
## state the controller exposes and the suite asserts.
static func night_lamps_active(lamps: Node3D) -> bool:
	if lamps == null:
		return false
	for child: Node in lamps.get_children():
		if child is Light3D and (child as Light3D).visible:
			return true
	return false

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
	var part_key := name + " " + String(mesh_instance.name).to_lower()
	if name.contains("paint") or standard.clearcoat_enabled:
		return _paint_clone(standard, profile, part_key)
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
	var cc0_override := _cc0_override(mesh_instance, name, standard, profile, part_key)
	if cc0_override != null:
		return cc0_override
	return null

## Kenney Car Kit GLBs bake every part under one flat-white 'colormap' material
## with no role keywords, so the material-name matcher alone leaves them plain
## white. Classify by mesh role instead: wheels are a composite tire+rim node,
## glass keeps the glass clone, and everything else on the shell is clearcoated
## paint. Gated on the 'colormap' material name, so AI-built cars (which never
## use it) are untouched.
static func _cc0_override(mesh_instance: MeshInstance3D, material_name: String, standard: StandardMaterial3D, profile: Dictionary, part_key: String) -> StandardMaterial3D:
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
	return _paint_clone(standard, profile, part_key)

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

## Deterministic per-surface paint roughness: primary body panels take the
## sharp profile["roughness"] band, secondary aero/bodywork (see
## SECONDARY_PAINT_PARTS) takes profile["roughness_secondary"]. Pure name
## lookup, so the same mesh always resolves to the same band.
static func paint_roughness_for(profile: Dictionary, part_key: String) -> float:
	if _is_secondary_paint_part(part_key):
		return float(profile.get("roughness_secondary", profile["roughness"]))
	return float(profile["roughness"])

static func _is_secondary_paint_part(part_key: String) -> bool:
	var key := part_key.to_lower()
	for keyword: String in SECONDARY_PAINT_PARTS:
		if key.contains(keyword):
			return true
	return false

static func _paint_clone(source: StandardMaterial3D, profile: Dictionary, part_key: String = "") -> StandardMaterial3D:
	var cloned: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	if profile.has("color"):
		cloned.albedo_color = profile["color"]
	cloned.clearcoat_enabled = true
	cloned.clearcoat = profile["clearcoat"]
	cloned.clearcoat_roughness = profile["clearcoat_roughness"]
	cloned.metallic = profile["metallic"]
	cloned.roughness = paint_roughness_for(profile, part_key)
	if profile.has("metallic_specular"):
		cloned.metallic_specular = profile["metallic_specular"]
	if profile.has("rim"):
		cloned.rim_enabled = true
		cloned.rim = profile["rim"]
	if profile.has("rim_tint"):
		cloned.rim_tint = profile["rim_tint"]
	return cloned

static func _glass_clone(source: StandardMaterial3D, profile: Dictionary) -> StandardMaterial3D:
	var cloned: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	cloned.albedo_color = profile.get("glass_color", DEFAULT_GLASS_COLOR)
	cloned.metallic = profile["glass_metallic"]
	cloned.roughness = profile["glass_roughness"]
	cloned.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloned.refraction_enabled = false
	return cloned

static func _light_clone(source: StandardMaterial3D) -> StandardMaterial3D:
	var cloned: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	cloned.metallic = 0.0
	cloned.roughness = 0.12
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
	cloned.metallic = 0.5
	cloned.roughness = 0.32
	cloned.clearcoat_enabled = true
	cloned.clearcoat = 0.85
	cloned.clearcoat_roughness = 0.12
	cloned.rim_enabled = true
	cloned.rim = 0.18
	cloned.rim_tint = 0.5
	return cloned

static func _trim_clone(source: StandardMaterial3D) -> StandardMaterial3D:
	var cloned: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	cloned.metallic = 0.85
	cloned.roughness = 0.45
	return cloned

# --- Cockpit see-through (D6): a mode-driven transparency pass so first-person
# --- driving can actually SEE OUT. The paint pipeline ships glass tinted and
# --- TRANSPARENT (DEFAULT_GLASS_COLOR, alpha 0.45) and the CC0/Kenney cars are
# --- doubleSided-bodied shells whose backfaces fill the windshield cavity from
# --- inside — the Comet (cc0_sedan_sports) has NO glass mesh at all, so its
# --- red 'body' shell IS the windshield. While the cockpit camera owns the
# --- viewport, Shell meshes are hidden and Glass surfaces drop to
# --- COCKPIT_GLASS_ALPHA; leaving cockpit restores every original flag
# --- (transparency + alpha are value-snapshotted per material), so the pass
# --- is baseline-agnostic and chase / hood / orbit render as authored.
# --- Shell = the paint body AND its non-glass dressing (grille / intake /
# --- splitter / vents / lights / trim / graphite): once the paint is hidden the
# --- dressing would otherwise float in the driver's forward view (the R35 GT-R
# --- fronts a near-black grille/headlight cluster over the horizon). Only the
# --- wheel assembly stays visible.

## Windshield alpha while the cockpit camera owns the viewport. Low and clean
## (no fake tint): the world reads straight through the glass.
const COCKPIT_GLASS_ALPHA := 0.18

enum CockpitRole { GLASS = 0, SHELL = 1, OTHER = 2 }

const META_GLASS_TRANSPARENCY_ORIG := "cockpit_glass_transparency_orig"
const META_GLASS_ALPHA_ORIG := "cockpit_glass_alpha_orig"
const META_SHELL_VISIBLE_ORIG := "cockpit_shell_visible_orig"

## Classifies a visual root's surfaces for the cockpit pass. Returns
## {"glass": Array[MeshInstance3D], "shell": Array[MeshInstance3D]} where glass
## = surfaces that read as a windshield/window (transparency targets) and shell
## = the surfaces that block a driver's forward view (hiding targets): the paint
## body AND its non-glass dressing (grille / intake / splitter / vents /
## headlights / taillights / trim / graphite), which would otherwise float in
## the forward view once the paint body is hidden. Only the wheel assembly
## (tires / rims / wheels / brakes / calipers) is neither and stays visible.
static func cockpit_roles(root: Node3D) -> Dictionary:
	var roles := {"glass": [], "shell": []}
	if root == null:
		return roles
	_collect_cockpit_roles(root, roles)
	return roles

## Mode-driven cockpit see-through: enabled=true while the cockpit camera owns
## the viewport — shell meshes hide (their doubleSided interior backfaces are
## the "red wall" seen from inside the Comet) and glass surfaces become
## transparent so the world shows through the windshield. enabled=false restores
## every original flag. Idempotent: repeated calls with the same state are
## no-ops. Only per-surface OVERRIDE clones (the paint pipeline's runtime
## duplicates) are touched; embedded/shared materials are never mutated.
static func set_cockpit_view(root: Node3D, enabled: bool) -> void:
	if root == null:
		return
	var roles := cockpit_roles(root)
	for glass_node: Variant in roles["glass"]:
		_set_glass_cockpit(glass_node as MeshInstance3D, enabled)
	for shell_node: Variant in roles["shell"]:
		_set_shell_cockpit(shell_node as MeshInstance3D, enabled)

static func _collect_cockpit_roles(node: Node, roles: Dictionary) -> void:
	if node is MeshInstance3D:
		var role := _mesh_cockpit_role(node as MeshInstance3D)
		if role == CockpitRole.GLASS:
			(roles["glass"] as Array).append(node)
		elif role == CockpitRole.SHELL:
			(roles["shell"] as Array).append(node)
	for child: Node in node.get_children():
		_collect_cockpit_roles(child, roles)

static func _mesh_cockpit_role(mesh_instance: MeshInstance3D) -> int:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return CockpitRole.OTHER
	var shell: bool = false
	for surface_index in range(mesh.get_surface_count()):
		var material := _resolved_surface_material(mesh_instance, mesh, surface_index) as StandardMaterial3D
		if material == null:
			continue
		var role := _material_cockpit_role(mesh_instance, material)
		if role == CockpitRole.GLASS:
			return CockpitRole.GLASS
		if role == CockpitRole.SHELL:
			shell = true
	return CockpitRole.SHELL if shell else CockpitRole.OTHER

## Mirrors the _make_override / _cc0_override classification: glass names win,
## CC0 'colormap' wheels stay OTHER, the non-glass body dressing (lights / trim /
## graphite) hides with the shell, and the wheel assembly stays OTHER.
static func _material_cockpit_role(mesh_instance: MeshInstance3D, material: StandardMaterial3D) -> int:
	var material_name := material.resource_name.to_lower() if not material.resource_name.is_empty() else ""
	var node_name := String(mesh_instance.name).to_lower()
	if _is_cockpit_glass_name(material_name, node_name):
		return CockpitRole.GLASS
	if material_name == "colormap":
		if node_name.contains("tire") or node_name.contains("rim") or node_name.contains("wheel"):
			return CockpitRole.OTHER
		return CockpitRole.SHELL
	# Body dressing hides with the paint shell so it cannot float in the forward
	# view once the paint is hidden. 'trim' MUST be tested before 'rim' — the
	# R35's 'DarkTrim' material contains both substrings.
	if material_name.contains("headlight") or material_name.contains("taillight") \
		or material_name.contains("trim") or material_name.contains("graphite") \
		or material_name.contains("reverse"):
		return CockpitRole.SHELL
	# The wheel assembly (tires / rims / brakes / calipers) stays visible.
	if material_name.contains("tire") or material_name.contains("rim") \
		or material_name.contains("brake") or material_name.contains("caliper"):
		return CockpitRole.OTHER
	return CockpitRole.SHELL

static func _is_cockpit_glass_name(material_name: String, node_name: String) -> bool:
	return material_name.contains("glass") or material_name.contains("window") \
		or material_name.contains("windshield") or node_name.contains("glass")

static func _set_glass_cockpit(mesh_instance: MeshInstance3D, enabled: bool) -> void:
	if mesh_instance == null:
		return
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return
	for surface_index in range(mesh.get_surface_count()):
		var material := mesh_instance.get_surface_override_material(surface_index) as StandardMaterial3D
		if material == null:
			continue
		if enabled:
			if not material.has_meta(META_GLASS_TRANSPARENCY_ORIG):
				material.set_meta(META_GLASS_TRANSPARENCY_ORIG, int(material.transparency))
				material.set_meta(META_GLASS_ALPHA_ORIG, float(material.albedo_color.a))
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var color := material.albedo_color
			color.a = COCKPIT_GLASS_ALPHA
			material.albedo_color = color
		elif material.has_meta(META_GLASS_TRANSPARENCY_ORIG):
			material.transparency = int(material.get_meta(META_GLASS_TRANSPARENCY_ORIG))
			var color := material.albedo_color
			color.a = float(material.get_meta(META_GLASS_ALPHA_ORIG))
			material.albedo_color = color
			material.remove_meta(META_GLASS_TRANSPARENCY_ORIG)
			material.remove_meta(META_GLASS_ALPHA_ORIG)

static func _set_shell_cockpit(mesh_instance: MeshInstance3D, enabled: bool) -> void:
	if mesh_instance == null:
		return
	if enabled:
		if not mesh_instance.has_meta(META_SHELL_VISIBLE_ORIG):
			mesh_instance.set_meta(META_SHELL_VISIBLE_ORIG, bool(mesh_instance.visible))
		mesh_instance.visible = false
	elif mesh_instance.has_meta(META_SHELL_VISIBLE_ORIG):
		mesh_instance.visible = bool(mesh_instance.get_meta(META_SHELL_VISIBLE_ORIG))
		mesh_instance.remove_meta(META_SHELL_VISIBLE_ORIG)

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