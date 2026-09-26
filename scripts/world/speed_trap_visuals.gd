# scripts/world/speed_trap_visuals.gd
class_name SpeedTrapVisuals
extends Node3D

## VISIBLE speed-trap dressing for the AAA-16 collectibles. Collectibles places
## every `speedtrap_N` exactly ON a road vertex (offset 0) and
## collectible_field.gd pays it on radius + speed, but until now the trap existed
## only as data: nothing in the 3D world told the player where the money was.
## This node builds one gantry per UNCLAIMED `speedtrap_*` POI from the SAME
## published placement data the trigger reads (CollectibleField.placed(), else
## the deterministic Collectibles.place_data plan) -- it never re-plans sites, so
## a mesh and a trigger can never disagree.
##
## One gate is one Node3D named "Gate_speedtrap_3" carrying two MeshInstance3D
## children, both built at runtime from fused BoxMesh primitives (the
## prop_scatterer.gd / foliage.gd convention: no external assets, no collision
## body, no top-level transform):
##   Structure -- two thin posts + their base plates + the overhead crossbar +
##                the protruding camera box, fused into ONE ArrayMesh in a dark
##                metal material (60 triangles, shadow casting off);
##   Glint     -- a thin emissive strip under the crossbar, i.e. the "this trap
##                is live" tell.
## The gate's local +Z is the road tangent at the anchor, so the posts straddle
## the carriageway at +/-(road_width / 2 + POST_CLEARANCE) and the player drives
## straight THROUGH the gate. On claim the structure swaps to a dimmed grey
## material, the glint goes bright green and a short-lived OmniLight3D fades out
## over FLASH_SECONDS before freeing itself.
##
## Cost discipline: eight gates, ~12 boxes total, built once. The only per-frame
## work is the flash timer, and the node turns its own processing back off the
## moment no flash is in flight. No physics bodies and no physics queries.

# ---------------------------------------------------------------------------
# Naming.
# ---------------------------------------------------------------------------

const GATE_NAME_PREFIX := "Gate_%s"
const STRUCTURE_NAME := "Structure"
const GLINT_NAME := "Glint"
const FLASH_LIGHT_NAME := "Flash"
## Group the pause map / debug tooling can resolve to read gate state from.
const GROUP_NAME := "speed_trap_visuals"
## RoadNetwork's own group, the shared whole-map road source MapRoads resolves.
const ROAD_GROUP := "road_network"

# ---------------------------------------------------------------------------
# Gate geometry (metres, gate-local: X = across the lane, Z = road tangent).
# ---------------------------------------------------------------------------

const POST_THICK := 0.18
## Base plate width. Wider than the post on both axes, so it is also what sets a
## gate's X bounds -- the span read back in gate_post_offset() relies on that.
const FOOT_WIDEN := 0.54
## Post height above the anchor, INCLUDING the sink margin below it, so a post
## standing on a shoulder a few cm higher than the road vertex never floats.
const POST_HEIGHT := 5.8
const POST_SINK := 0.6
const BAR_HEIGHT := 5.0
const BAR_THICK := 0.3
const BAR_DEPTH := 0.24
const CAMERA_SIZE := Vector3(0.52, 0.44, 0.8)
const CAMERA_Y := 4.6
## How far the camera box reaches upstream (-Z, towards the oncoming car).
const CAMERA_REACH := 0.5
const GLINT_Y := 4.25
const GLINT_THICK := 0.1
const GLINT_DEPTH := 0.06
const GLINT_INSET := 0.4

# ---------------------------------------------------------------------------
# Road alignment.
# ---------------------------------------------------------------------------

## Extra metres from the carriageway edge to each post, so the player really
## drives between them instead of clipping one.
const POST_CLEARANCE := 1.5
## Never narrower than this on a single-lane dirt track.
const MIN_POST_OFFSET := 5.0
## Post offset when the host road (and therefore its width) is unknown.
const DEFAULT_POST_OFFSET := 7.0
## How close (XZ) the resolved segment endpoints must be to the POI for the
## placement's own `point_index` hint to be trusted.
const ANCHOR_SNAP_M := 2.0
## Heading used when no host road def resolves: straight ahead, local -Z.
const FALLBACK_FORWARD := Vector3(0.0, 0.0, -1.0)

# ---------------------------------------------------------------------------
# Claim flash.
# ---------------------------------------------------------------------------

const FLASH_SECONDS := 1.5
const FLASH_COLOR := Color(0.35, 1.0, 0.45, 1.0)
const FLASH_ENERGY := 4.0
const FLASH_RANGE := 16.0
const FLASH_LIGHT_Y := 4.2

@export var field_path: NodePath = NodePath("../CollectibleField")
@export var road_network_path: NodePath = NodePath("../RoadNetwork")
## Ground surface Y at a world (x, z) as Vector2, the prop_scatterer.gd /
## foliage.gd provider contract. Unset (the shipped scene): the gate stands on
## the road vertex Y the POI already carries, which is exactly the Y TrackBuilder
## meshed the carriageway at, so the posts always meet the tarmac.
var ground_height_provider: Callable = Callable()
## When true a rebuild (re)builds the ALREADY-CLAIMED traps in their dimmed
## claimed look instead of leaving them out of the world. The shipped default is
## false: a trap you already banked has no reason to still stand across the road.
@export var keep_claimed_gates := false

## collectible_id -> gate Node3D.
var _gates: Dictionary = {}
## collectible_id -> true, for every trap resolved as claimed (live or loaded).
var _claimed: Dictionary = {}
## collectible_id -> OmniLight3D currently fading out.
var _flashing: Dictionary = {}
var _flash_left := 0.0
var _field: CollectibleField = null
var _pending_boot := false
var _booted := false

## Shared singletons: one material per look, so a claim is a single
## material_override assignment and never allocates.
var _structure_mat: StandardMaterial3D = null
var _structure_claimed_mat: StandardMaterial3D = null
var _glint_active_mat: StandardMaterial3D = null
var _glint_claimed_mat: StandardMaterial3D = null
var _glint_flash_mat: StandardMaterial3D = null

# ---------------------------------------------------------------------------
# Lifecycle.
# ---------------------------------------------------------------------------

func _ready() -> void:
	add_to_group(GROUP_NAME)
	_ensure_materials()
	# The CollectibleField is a sibling that populates itself from POIRegistry in
	# ITS _ready, and the runtime RoadNetwork is not handed its defs until
	# WorldDriver._ready (which runs after every child _ready). So the first build
	# is deferred to the next frame; anything that needs the alignment sooner
	# (WorldDriver) calls rebuild() explicitly.
	_pending_boot = true
	set_process(true)

func _exit_tree() -> void:
	_disconnect_field()

func _process(delta: float) -> void:
	if _pending_boot:
		_pending_boot = false
		_booted = true
		rebuild()
	if not tick(delta):
		set_process(false)

# ---------------------------------------------------------------------------
# Build.
# ---------------------------------------------------------------------------

## Drops every gate and rebuilds the unclaimed set from the published
## collectible data, resolving each gate's claimed state from the field (or, with
## no field, from nothing: everything then counts as live). Idempotent -- the
## node never stacks duplicate gates, so re-running it on a scene load, or after
## the roads land, is free of side effects.
func rebuild() -> void:
	_pending_boot = false
	_booted = true
	var field := _resolve_field()
	var placed := _resolve_placed(field)
	var defs := _road_defs()
	for child in get_children():
		child.free()
	_gates.clear()
	_claimed.clear()
	_flashing.clear()
	_flash_left = 0.0
	for collectible_id: String in Collectibles.ids_of_kind(placed, Collectibles.KIND_SPEED_TRAP):
		var poi: Dictionary = placed[collectible_id]
		var claimed := field != null and field.is_claimed(collectible_id)
		if claimed:
			_claimed[collectible_id] = true
			if not keep_claimed_gates:
				continue
		_gates[collectible_id] = _build_gate(collectible_id, poi, defs, claimed)
	set_process(false)

func _build_gate(collectible_id: String, poi: Dictionary, defs: Array[RoadDef], claimed: bool) -> Node3D:
	var frame := frame_for(poi, defs)
	var forward: Vector3 = frame["forward"]
	var half_span := post_offset_for(float(frame["width"]))
	var gate := Node3D.new()
	gate.name = GATE_NAME_PREFIX % collectible_id
	gate.transform = Transform3D(Basis(Vector3.UP, atan2(forward.x, forward.z)), _origin_for(poi))
	add_child(gate)
	var structure := MeshInstance3D.new()
	structure.name = STRUCTURE_NAME
	structure.mesh = _fuse(_structure_parts(half_span))
	structure.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if claimed:
		structure.material_override = _structure_claimed_mat
	else:
		structure.material_override = _structure_mat
	gate.add_child(structure)
	var glint := MeshInstance3D.new()
	glint.name = GLINT_NAME
	glint.mesh = _glint_mesh(half_span)
	glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if claimed:
		glint.material_override = _glint_claimed_mat
	else:
		glint.material_override = _glint_active_mat
	gate.add_child(glint)
	return gate

## The five box parts of a gate, in gate-local space: two posts (each sunk
## POST_SINK below the anchor so the feet never float off a raised shoulder) with
## a base plate, the overhead crossbar, and the camera box reaching upstream.
func _structure_parts(half_span: float) -> Array:
	var post := BoxMesh.new()
	post.size = Vector3(POST_THICK, POST_HEIGHT, POST_THICK)
	var foot := BoxMesh.new()
	foot.size = Vector3(FOOT_WIDEN, POST_SINK * 0.5, FOOT_WIDEN)
	var bar := BoxMesh.new()
	bar.size = Vector3(half_span * 2.0 + POST_THICK, BAR_THICK, BAR_DEPTH)
	var camera := BoxMesh.new()
	camera.size = CAMERA_SIZE
	var parts: Array = []
	for side: float in [-1.0, 1.0]:
		parts.append([post, Transform3D(Basis.IDENTITY,
			Vector3(side * half_span, POST_HEIGHT * 0.5 - POST_SINK, 0.0))])
		parts.append([foot, Transform3D(Basis.IDENTITY,
			Vector3(side * half_span, -POST_SINK * 0.5, 0.0))])
	parts.append([bar, Transform3D(Basis.IDENTITY, Vector3(0.0, BAR_HEIGHT, 0.0))])
	parts.append([camera, Transform3D(Basis.IDENTITY, Vector3(0.0, CAMERA_Y, -CAMERA_REACH))])
	return parts

func _glint_mesh(half_span: float) -> ArrayMesh:
	var strip := BoxMesh.new()
	strip.size = Vector3(maxf(half_span * 2.0 - GLINT_INSET, 0.4), GLINT_THICK, GLINT_DEPTH)
	var parts: Array = [[strip, Transform3D(Basis.IDENTITY, Vector3(0.0, GLINT_Y, -BAR_DEPTH))]]
	return _fuse(parts)

## Fuses primitives into ONE ArrayMesh surface (the prop_scatterer.gd::_fuse /
## foliage.gd::_build_tree_mesh approach), so a gate is two draw calls.
func _fuse(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Array in parts:
		st.append_from(part[0] as Mesh, 0, part[1] as Transform3D)
	var mesh: ArrayMesh = st.commit()
	return mesh

## Gate origin: the published POI position, optionally re-seated on the ground
## height provider when one is wired (the prop_scatterer/foliage contract). A
## non-finite provider answer (a Terrain3D region that is not streamed in yet)
## is ignored rather than sinking the gate into the void.
func _origin_for(poi: Dictionary) -> Vector3:
	var pos: Vector3 = poi.get("position", Vector3.ZERO) as Vector3
	if not ground_height_provider.is_valid():
		return pos
	var height := float(ground_height_provider.call(Vector2(pos.x, pos.z)))
	if is_finite(height):
		pos.y = height
	return pos

# ---------------------------------------------------------------------------
# Road frame (static + pure, so the alignment is asserted headless).
# ---------------------------------------------------------------------------

## Placement frame for one collectible POI against the road defs: the unit XZ
## tangent of the centreline segment it sits on (local +Z of the gate) and that
## road's own width. `known` is false when the host road cannot be resolved, in
## which case the heading falls back to straight ahead (-Z) and the width to 0.
static func frame_for(poi: Dictionary, defs: Array[RoadDef]) -> Dictionary:
	var road_id := str(poi.get("road_id", ""))
	var host := find_def(defs, road_id)
	if host == null:
		return {"forward": FALLBACK_FORWARD, "width": 0.0, "known": false}
	var segment := _segment_index_at(host, poi)
	if segment < 0:
		return {"forward": FALLBACK_FORWARD, "width": host.width, "known": false}
	var points: Array[Vector3] = host.points
	var a: Vector3 = points[segment]
	var b: Vector3 = points[(segment + 1) % points.size()]
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if dir.length_squared() <= 0.000001:
		return {"forward": FALLBACK_FORWARD, "width": host.width, "known": false}
	return {"forward": dir.normalized(), "width": host.width, "known": true}

## The host road def for a `road_id` string (RoadDef id, the human metadata the
## collectible dict stores). Null when the defs do not carry it.
static func find_def(defs: Array[RoadDef], road_id: String) -> RoadDef:
	if road_id.is_empty():
		return null
	for def: RoadDef in defs:
		if def != null and def.id == road_id:
			return def
	return null

## Segment of `def` the POI sits on. The placement's own `point_index` is used
## when it is in range AND both of its endpoints are within ANCHOR_SNAP_M of the
## POI (the registry plan and the live network can hold a differently-sampled
## chain for the same road); otherwise the nearest centreline segment wins.
static func _segment_index_at(def: RoadDef, poi: Dictionary) -> int:
	var points: Array[Vector3] = def.points
	if points.size() < 2:
		return -1
	var segments := _segment_count(points, def.closed)
	var pos: Vector3 = poi.get("position", Vector3.ZERO) as Vector3
	var extra: Dictionary = poi.get("extra", {}) as Dictionary
	if extra.has("point_index"):
		var hinted := int(extra["point_index"])
		if hinted >= 0 and hinted < segments and _segment_holds(points, def.closed, hinted, pos):
			return hinted
	return _nearest_segment(points, def.closed, pos)

static func _segment_count(points: Array[Vector3], closed: bool) -> int:
	var n := points.size()
	if n < 2:
		return 0
	return n - 1 + (1 if closed and n > 2 else 0)

## True when the segment's own endpoints both sit on the POI (XZ), i.e. the
## placement hint still describes this chain.
static func _segment_holds(points: Array[Vector3], closed: bool, index: int, pos: Vector3) -> bool:
	var a: Vector3 = points[index]
	var b: Vector3 = points[(index + 1) % points.size()]
	return Collectibles.xz_distance(a, pos) <= ANCHOR_SNAP_M \
		and Collectibles.xz_distance(b, pos) <= ANCHOR_SNAP_M

static func _nearest_segment(points: Array[Vector3], closed: bool, pos: Vector3) -> int:
	var best := -1
	var best_distance := INF
	for index in _segment_count(points, closed):
		var a: Vector3 = points[index]
		var b: Vector3 = points[(index + 1) % points.size()]
		var distance := Collectibles.xz_distance(_closest_point_xz(a, b, pos), pos)
		if distance < best_distance:
			best_distance = distance
			best = index
	return best

## Closest point to `pos` on segment a->b, in XZ only.
static func _closest_point_xz(a: Vector3, b: Vector3, pos: Vector3) -> Vector3:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var len2 := ab.length_squared()
	if len2 <= 0.0001:
		return a
	var t := clampf(Vector2(pos.x - a.x, pos.z - a.z).dot(ab) / len2, 0.0, 1.0)
	return Vector3(a.x + ab.x * t, 0.0, a.z + ab.y * t)

## Half-distance from the lane centre to each post: the host road's half width
## plus POST_CLEARANCE, never narrower than MIN_POST_OFFSET, and the
## DEFAULT_POST_OFFSET stand-in when the road is unknown.
static func post_offset_for(road_width: float) -> float:
	if road_width <= 0.0:
		return DEFAULT_POST_OFFSET
	return maxf(road_width * 0.5 + POST_CLEARANCE, MIN_POST_OFFSET)

# ---------------------------------------------------------------------------
# Claim path.
# ---------------------------------------------------------------------------

## CollectibleField.collectible_claimed: a paid speed trap goes to its claimed
## look in place (dimmed posts, green glint, fading flash light). Non-trap
## collectibles are ignored -- bonus boards and photo spots have no gate.
func _on_collectible_claimed(collectible_id: String, _reward: int) -> void:
	if Collectibles.kind_of_id(collectible_id) != Collectibles.KIND_SPEED_TRAP:
		return
	mark_claimed(collectible_id)

## Swaps one gate to the claimed look and starts the flash. Public so the headless
## gate can drive the exact same path the signal does. No-op for an unknown or
## already-claimed id (and for a trap the field had already claimed before this
## node built, which never got a gate at all).
func mark_claimed(collectible_id: String) -> void:
	if _claimed.has(collectible_id):
		return
	_claimed[collectible_id] = true
	var gate := _gates.get(collectible_id) as Node3D
	if gate == null or not is_instance_valid(gate):
		return
	_ensure_materials()
	var structure := gate.get_node_or_null(STRUCTURE_NAME) as MeshInstance3D
	if structure != null:
		structure.material_override = _structure_claimed_mat
	var glint := gate.get_node_or_null(GLINT_NAME) as MeshInstance3D
	if glint != null:
		glint.material_override = _glint_flash_mat
	var light := OmniLight3D.new()
	light.name = FLASH_LIGHT_NAME
	light.light_color = FLASH_COLOR
	light.light_energy = FLASH_ENERGY
	light.omni_range = FLASH_RANGE
	light.shadow_enabled = false
	gate.add_child(light)
	light.position = Vector3(0.0, FLASH_LIGHT_Y, 0.0)
	_flashing[collectible_id] = light
	_flash_left = FLASH_SECONDS
	set_process(true)

## Advances the flash fade by `delta` seconds; returns true while a flash is
## still in flight. The only per-frame work in this node, and the reason it
## switches processing off when idle: no flash, no ticks. Processing is switched
## off here rather than in _process so a driven tick() leaves the node in exactly
## the state a real frame would have left it in.
func tick(delta: float) -> bool:
	if _flash_left <= 0.0 or _flashing.is_empty():
		set_process(false)
		return false
	_flash_left = maxf(_flash_left - delta, 0.0)
	var ratio := _flash_left / FLASH_SECONDS
	for collectible_id: String in _flashing.keys():
		var light := _flashing[collectible_id] as OmniLight3D
		if light != null and is_instance_valid(light):
			light.light_energy = FLASH_ENERGY * ratio
	if _flash_left <= 0.0:
		_finish_flash()
		set_process(false)
		return false
	return true

## The flash has burnt out: free the lights and settle the glint on the steady
## claimed green. Immediate free (not queue_free) so the state is exact the same
## call, the same way prop_scatterer.generate() reclaims its own children.
func _finish_flash() -> void:
	for collectible_id: String in _flashing.keys():
		var light := _flashing[collectible_id] as OmniLight3D
		if light != null and is_instance_valid(light):
			light.free()
		var gate := _gates.get(collectible_id) as Node3D
		if gate != null and is_instance_valid(gate):
			var glint := gate.get_node_or_null(GLINT_NAME) as MeshInstance3D
			if glint != null:
				glint.material_override = _glint_claimed_mat
	_flashing.clear()
	_flash_left = 0.0

# ---------------------------------------------------------------------------
# Field / road resolution.
# ---------------------------------------------------------------------------

## The CollectibleField this node dresses, resolved by the exported path and then
## by the field's group, connecting the claim signal on first sight. Null is a
## supported state (a bare dressing node, a test): the gates then all read live.
func _resolve_field() -> CollectibleField:
	if _field != null and is_instance_valid(_field):
		return _field
	_field = null
	if not field_path.is_empty():
		_field = get_node_or_null(field_path) as CollectibleField
	if _field == null and is_inside_tree():
		for candidate: Node in get_tree().get_nodes_in_group(CollectibleField.GROUP_NAME):
			var field := candidate as CollectibleField
			if field != null:
				_field = field
				break
	if _field != null and not _field.collectible_claimed.is_connected(_on_collectible_claimed):
		_field.collectible_claimed.connect(_on_collectible_claimed)
	return _field

func _disconnect_field() -> void:
	if _field == null or not is_instance_valid(_field):
		_field = null
		return
	if _field.collectible_claimed.is_connected(_on_collectible_claimed):
		_field.collectible_claimed.disconnect(_on_collectible_claimed)
	_field = null

## The published collectible entries. The field is the single source while it
## exists (its placed() IS the registry set it triggers on); without one the
## deterministic plan POIRegistry merged in is regenerated, which is index math
## over the same master-seeded network and therefore the same sites.
func _resolve_placed(field: CollectibleField) -> Dictionary:
	if field != null:
		var data := field.placed()
		if not data.is_empty():
			return data
	return Collectibles.place_data(_road_defs())

## The road defs the gates align to: the LIVE network when it already carries its
## corridors (the runtime carriageway the player drives), else the deterministic
## master-seeded plan the collectibles were placed from.
func _road_defs() -> Array[RoadDef]:
	var network := road_network()
	if network != null:
		var defs: Array[RoadDef] = network.get_road_defs()
		if not defs.is_empty():
			return defs
	return CorridorPlanner.plan(CorridorPlanner.MASTER_SEED, Callable(), {})

func road_network() -> RoadNetwork:
	if not road_network_path.is_empty():
		var network := get_node_or_null(road_network_path) as RoadNetwork
		if network != null:
			return network
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(ROAD_GROUP) as RoadNetwork

# ---------------------------------------------------------------------------
# Materials (shared singletons).
# ---------------------------------------------------------------------------

func _ensure_materials() -> void:
	if _structure_mat != null:
		return
	_structure_mat = _metal(Color(0.16, 0.17, 0.19), 0.75, 0.35)
	_structure_claimed_mat = _metal(Color(0.33, 0.34, 0.35), 0.15, 0.95)
	_glint_active_mat = _emissive(Color(0.9, 0.3, 0.05), 2.0)
	_glint_claimed_mat = _emissive(Color(0.2, 0.85, 0.3), 1.0)
	_glint_flash_mat = _emissive(FLASH_COLOR, 4.0)

static func _metal(albedo: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.metallic = metallic
	mat.roughness = roughness
	return mat

static func _emissive(tint: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = energy
	return mat

# ---------------------------------------------------------------------------
# Public state surface (map / debug / tests).
# ---------------------------------------------------------------------------

## Gate nodes currently standing, keyed by collectible id.
func gates() -> Dictionary:
	return _gates.duplicate()

func gate_count() -> int:
	return _gates.size()

## Standing gate ids in id-INDEX order (speedtrap_0 .. speedtrap_2, never
## lexicographic), mirroring Collectibles.ids_of_kind.
func gate_ids() -> Array[String]:
	var out: Array[String] = []
	for collectible_id: String in _gates.keys():
		out.append(collectible_id)
	out.sort_custom(_id_index_less)
	return out

static func _id_index_less(a: String, b: String) -> bool:
	return _id_index(a) < _id_index(b)

static func _id_index(collectible_id: String) -> int:
	var prefix := str(Collectibles.ID_PREFIX.get(Collectibles.KIND_SPEED_TRAP, ""))
	if prefix.is_empty():
		return 0
	return int(collectible_id.trim_prefix(prefix))

func has_gate(collectible_id: String) -> bool:
	return _gates.has(collectible_id)

func gate_node(collectible_id: String) -> Node3D:
	return _gates.get(collectible_id) as Node3D

## True when the id resolved as claimed -- a gate standing in its claimed look, or
## (the shipped rebuild) a gate left out of the world entirely.
func is_claimed(collectible_id: String) -> bool:
	return _claimed.has(collectible_id)

## The look a gate is wearing: "flash" while the claim flash is burning, then
## "claimed" (dimmed posts, steady green glint); "active" while it is still
## waiting to be paid, and "" when no gate stands for the id. Read from the
## assigned material rather than tracked separately, so it can never disagree
## with what the player sees.
func gate_look(collectible_id: String) -> String:
	var gate := gate_node(collectible_id)
	if gate == null:
		return ""
	var glint := gate.get_node_or_null(GLINT_NAME) as MeshInstance3D
	if glint == null:
		return "active"
	if glint.material_override == _glint_flash_mat:
		return "flash"
	if glint.material_override == _glint_claimed_mat:
		return "claimed"
	return "active"

## Triangle budget of one gate's built structure, so the cost claim (a handful of
## boxes per gate) is asserted rather than assumed.
func gate_triangle_count(collectible_id: String) -> int:
	var gate := gate_node(collectible_id)
	if gate == null:
		return 0
	var structure := gate.get_node_or_null(STRUCTURE_NAME) as MeshInstance3D
	if structure == null:
		return 0
	var mesh := structure.mesh
	if mesh == null:
		return 0
	var total := 0
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.size() > 0:
			total += indices.size() / 3
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += vertices.size() / 3
	return total

## Half-distance from the lane centre to this gate's posts, 0.0 when no gate.
## Recovered from the built crossbar rather than kept in a side table, so the
## reported span can never drift from the mesh the player sees.
func gate_post_offset(collectible_id: String) -> float:
	var gate := gate_node(collectible_id)
	if gate == null:
		return 0.0
	var structure := gate.get_node_or_null(STRUCTURE_NAME) as MeshInstance3D
	if structure == null:
		return 0.0
	var mesh := structure.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return 0.0
	# The base plates (FOOT_WIDEN) are the widest thing across the lane, so the
	# AABB half-width is the post offset plus half a foot; take the foot off to
	# read back the offset the frame actually asked for.
	var bounds := mesh.get_aabb()
	return maxf(bounds.size.x - FOOT_WIDEN, 0.0) * 0.5

## Unit XZ forward of a gate (the road tangent it was aligned to), zero for an
## unknown id.
func gate_forward(collectible_id: String) -> Vector3:
	var gate := gate_node(collectible_id)
	if gate == null:
		return Vector3.ZERO
	var basis := gate.global_transform.basis
	return Vector3(basis.z.x, 0.0, basis.z.z).normalized()

## { collectible_id -> global Transform3D } of every standing gate, the
## determinism fingerprint.
func gate_transforms() -> Dictionary:
	var out: Dictionary = {}
	for collectible_id: String in _gates.keys():
		var gate := _gates[collectible_id] as Node3D
		if gate != null and is_instance_valid(gate):
			out[collectible_id] = gate.global_transform
	return out

## The fading claim light of one gate, or null when its flash is over.
func flash_light(collectible_id: String) -> OmniLight3D:
	return _flashing.get(collectible_id) as OmniLight3D

func flash_count() -> int:
	return _flashing.size()

## Seconds left on the shared flash timer (0 when idle).
func flash_time_left() -> float:
	return _flash_left

## True once the deferred first build has run.
func is_booted() -> bool:
	return _booted
