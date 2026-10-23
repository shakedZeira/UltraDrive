# scripts/world/world_landmarks.gd
class_name WorldLandmarks
extends Node3D

## FH6-look pass (2026-10-23): a handful of region landmarks with distinct
## silhouettes, visible from the highway: a wind farm on the highland shelf, a
## lighthouse on the coast, a red shrine gate near the hub, a red/white radio
## mast on the rolling hills, a farm (barn + silo) in the lowland fields and an
## observatory on the alpine shoulder. Built from primitive meshes at load
## (~70 nodes, < 5k triangles each); placed on the natural ground and nudged
## clear of every road (resolve_site). Visuals only, no collision, no POI hook.

const ROAD_CLEARANCE := 40.0
const DRAW_DISTANCE := 9000.0

## kind, world xz, yaw (deg). Positions are requests: resolve_site moves a site
## off the roads.
const SITES := [
	{"kind": "torii", "pos": Vector2(470.0, -40.0), "yaw": 30.0},
	{"kind": "farm", "pos": Vector2(1850.0, 620.0), "yaw": 15.0},
	{"kind": "mast", "pos": Vector2(2600.0, 2500.0), "yaw": 0.0},
	{"kind": "turbine", "pos": Vector2(6300.0, 2700.0), "yaw": 200.0},
	{"kind": "turbine", "pos": Vector2(6520.0, 2560.0), "yaw": 200.0},
	{"kind": "turbine", "pos": Vector2(6740.0, 2420.0), "yaw": 200.0},
	{"kind": "turbine", "pos": Vector2(6960.0, 2300.0), "yaw": 200.0},
	{"kind": "turbine", "pos": Vector2(6150.0, 2920.0), "yaw": 200.0},
	{"kind": "lighthouse", "pos": Vector2(8650.0, -2050.0), "yaw": 0.0},
	{"kind": "observatory", "pos": Vector2(5150.0, 5050.0), "yaw": 0.0},
]

var road_network: RoadNetwork
var _rotors: Array[Node3D] = []
var _baker := TerrainBaker.new()
static var _mats: Dictionary = {}

func _ready() -> void:
	for site: Dictionary in SITES:
		var p := resolve_site(site["pos"], road_network)
		var root := Node3D.new()
		root.name = "%s_%d_%d" % [site["kind"], int(p.x), int(p.y)]
		add_child(root)
		root.global_position = Vector3(p.x, _ground(p), p.y)
		root.rotation.y = deg_to_rad(float(site["yaw"]))
		_build(String(site["kind"]), root)

func _process(delta: float) -> void:
	for r in _rotors:
		r.rotate_object_local(Vector3.FORWARD, delta * 1.4)

## Ground under a site: the lowest natural height over a 12 m footprint, so a
## base never floats on a slope.
func _ground(p: Vector2) -> float:
	var h := INF
	for o: Vector2 in [Vector2.ZERO, Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6)]:
		h = minf(h, _baker.natural_height_at(p.x + o.x, p.y + o.y))
	return h

## Pure: the requested site if no road is within ROAD_CLEARANCE, else the first
## of 16 candidates on growing rings (40..240 m) that is clear. Deterministic.
static func resolve_site(pos: Vector2, network: RoadNetwork) -> Vector2:
	if network == null:
		return pos
	if _clear(pos, network):
		return pos
	for ring in range(1, 7):
		for k in 8:
			var a := TAU * float(k) / 8.0
			var c := pos + Vector2(cos(a), sin(a)) * 40.0 * float(ring)
			if _clear(c, network):
				return c
	return pos

static func _clear(p: Vector2, network: RoadNetwork) -> bool:
	var hit: Dictionary = network.nearest_road_lookup(Vector3(p.x, 0.0, p.y), ROAD_CLEARANCE + 20.0)
	var d: float = hit.get("distance", INF)
	var w := 0.0
	var id: int = hit.get("id", -1)
	if id >= 0:
		w = network.get_road_def(id).width * 0.5
	return d - w > ROAD_CLEARANCE

# -- geometry --------------------------------------------------------------------

static func _mat(name: String, col: Color, rough: float = 0.8, emissive := Color.BLACK) -> StandardMaterial3D:
	if _mats.has(name):
		return _mats[name]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	if emissive != Color.BLACK:
		m.emission_enabled = true
		m.emission = emissive
	_mats[name] = m
	return m

func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.visibility_range_end = DRAW_DISTANCE
	parent.add_child(mi)
	return mi

static func _cyl(r_top: float, r_bot: float, h: float, sides: int = 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = sides
	c.rings = 1
	return c

static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b

func _build(kind: String, root: Node3D) -> void:
	var white := _mat("white", Color(0.92, 0.92, 0.9), 0.6)
	var red := _mat("red", Color(0.78, 0.12, 0.08), 0.6)
	match kind:
		"turbine":
			_part(root, _cyl(1.2, 2.2, 80.0), white, Vector3(0, 40.0, 0))
			_part(root, _box(Vector3(2.6, 2.6, 7.0)), white, Vector3(0, 80.5, -0.5))
			var rotor := Node3D.new()
			rotor.position = Vector3(0, 80.5, 3.4)
			root.add_child(rotor)
			_part(rotor, _cyl(0.9, 1.2, 2.0), white, Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
			for k in 3:
				var blade := Node3D.new()
				blade.rotation.z = TAU * float(k) / 3.0
				rotor.add_child(blade)
				_part(blade, _box(Vector3(1.6, 34.0, 0.4)), white, Vector3(0, 18.0, 0))
			rotor.rotation.z = float(root.get_index()) * 0.7
			_rotors.append(rotor)
		"lighthouse":
			for i in 6:
				var m := red if i % 2 == 0 else white
				_part(root, _cyl(2.7 - 0.18 * float(i + 1), 2.7 - 0.18 * float(i), 4.0), m, Vector3(0, 2.0 + 4.0 * float(i), 0))
			_part(root, _cyl(1.6, 1.6, 3.0, 10), _mat("lamp", Color(1.0, 0.95, 0.7), 0.3, Color(1.0, 0.85, 0.5)), Vector3(0, 25.5, 0))
			_part(root, _cyl(0.2, 2.0, 2.0, 10), red, Vector3(0, 28.0, 0))
			_part(root, _box(Vector3(9.0, 4.0, 6.0)), white, Vector3(6.0, 2.0, 0))
			_part(root, _box(Vector3(9.6, 0.6, 6.6)), red, Vector3(6.0, 4.3, 0))
		"torii":
			var vermilion := _mat("vermilion", Color(0.85, 0.24, 0.1), 0.55)
			var black := _mat("black", Color(0.08, 0.07, 0.07), 0.7)
			_part(root, _cyl(0.45, 0.55, 9.0), vermilion, Vector3(-4.0, 4.5, 0))
			_part(root, _cyl(0.45, 0.55, 9.0), vermilion, Vector3(4.0, 4.5, 0))
			_part(root, _box(Vector3(10.5, 0.7, 0.9)), vermilion, Vector3(0, 7.2, 0))
			_part(root, _box(Vector3(13.0, 0.9, 1.3)), black, Vector3(0, 9.1, 0))
			_part(root, _box(Vector3(0.5, 1.6, 0.7)), vermilion, Vector3(0, 8.0, 0))
		"mast":
			for i in 8:
				var m2 := red if i % 2 == 0 else white
				_part(root, _cyl(0.8 - 0.07 * float(i + 1), 0.8 - 0.07 * float(i), 12.0, 6), m2, Vector3(0, 6.0 + 12.0 * float(i), 0))
			_part(root, _box(Vector3(5.0, 3.0, 4.0)), _mat("grey", Color(0.6, 0.6, 0.6), 0.8), Vector3(5.0, 1.5, 3.0))
			_part(root, _cyl(1.2, 1.2, 0.4), red, Vector3(0, 50.0, 0))
		"farm":
			var barn := _mat("barn", Color(0.55, 0.16, 0.1), 0.85)
			var roof := _mat("roof", Color(0.25, 0.27, 0.3), 0.7)
			_part(root, _box(Vector3(14.0, 7.0, 22.0)), barn, Vector3(0, 3.5, 0))
			var prism := PrismMesh.new()
			prism.size = Vector3(15.0, 5.0, 23.0)
			_part(root, prism, roof, Vector3(0, 9.5, 0))
			_part(root, _cyl(3.0, 3.0, 16.0), _mat("silo", Color(0.75, 0.76, 0.74), 0.5), Vector3(12.0, 8.0, -4.0))
			var dome := SphereMesh.new()
			dome.radius = 3.0
			dome.height = 3.0
			dome.is_hemisphere = true
			_part(root, dome, roof, Vector3(12.0, 16.0, -4.0))
			_part(root, _box(Vector3(8.0, 4.0, 8.0)), white, Vector3(-14.0, 2.0, 6.0))
		"observatory":
			_part(root, _cyl(7.0, 7.5, 9.0, 16), white, Vector3(0, 4.5, 0))
			var cap := SphereMesh.new()
			cap.radius = 7.0
			cap.height = 7.0
			cap.is_hemisphere = true
			cap.radial_segments = 20
			_part(root, cap, _mat("dome", Color(0.85, 0.86, 0.88), 0.25), Vector3(0, 9.0, 0))
			_part(root, _box(Vector3(1.6, 4.0, 7.2)), _mat("slit", Color(0.1, 0.1, 0.12), 0.6), Vector3(0, 13.0, 0))
			_part(root, _box(Vector3(12.0, 4.0, 8.0)), white, Vector3(12.0, 2.0, 0))
