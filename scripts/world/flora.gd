# scripts/world/flora.gd
class_name Flora
extends Node3D

## Biome vegetation, rocks and roadside furniture for ONE streamed 256 m region
## (FH6-look pass, 2026-10-23). A child of the RegionDresser's region node, next
## to the legacy Props (PropScatterer) and Foliage (conifer) children.
##
## Placement is a jittered grid per kit entry: every grid cell decides with an
## integer hash of (region seed, entry, cell), so the result is a pure function
## of the region and never depends on processing order or slice size. A world-
## space "grove" noise clusters trees into stands and leaves open fields between
## them. Ground rules come from the region's baked ground control map (the same
## texture ids the terrain draws: grass / meadow / forest floor / rock / sand /
## snow / gravel shoulder), so plants grow where their ground is drawn, never on
## the road or its shoulder.
##
## Work is time-sliced (step(budget_usec)) because a lowland region places a few
## thousand instances; the dresser drains it on idle frames. Instances are kept
## in side arrays (never read back from a MultiMesh: 4.7.2 read-back bug) and
## written to each MultiMesh through its buffer in one call.
##
## Batches: trees / bushes / rocks / roadside props are one MultiMesh per mesh
## for the region (frustum-culled per region); grass and flowers are split into
## SMALL_CHUNK sub-cells so their short draw distance is per patch, not per region.

const SMALL_CHUNK := 64.0
const MESH_TREE := ["oak", "poplar", "birch", "maple"]

## Ground classes a kit entry may require (decoded from the control map).
const G_GRASS := 1
const G_MEADOW := 2
const G_FOREST := 4
const G_ROCK := 8
const G_SAND := 16
const G_SNOW := 32
const G_DIRT := 64
const G_PLANT := G_GRASS | G_MEADOW | G_FOREST
const G_ANY_SOFT := G_PLANT | G_DIRT

## Draw distances (m from the camera to the batch origin) per batch kind.
const DRAW_DISTANCE := {
	"tree": 900.0, "bush": 320.0, "rock": 650.0, "crag": 1400.0,
	"small": 130.0, "prop": 420.0,
}

## Leaf tints (multiplied into the tintable vertex colours).
const LEAF_TINTS := [
	Color(1.0, 1.0, 1.0), Color(0.86, 1.0, 0.92), Color(1.12, 1.08, 0.84),
	Color(0.8, 0.9, 0.76), Color(1.05, 1.12, 0.9),
]
const AUTUMN_TINTS := [Color(2.0, 0.78, 0.42), Color(1.9, 1.05, 0.45), Color(1.55, 1.25, 0.5)]
const PETAL_TINTS := [
	Color(1.0, 0.9, 0.28), Color(0.96, 0.96, 0.94), Color(0.72, 0.5, 0.95),
	Color(1.0, 0.55, 0.68), Color(0.95, 0.38, 0.26),
]
const ROCK_TINTS := [Color(1.0, 1.0, 1.0), Color(0.9, 0.95, 0.84), Color(1.06, 1.0, 0.94), Color(0.82, 0.82, 0.84)]
const GRASS_TINTS := [Color(1.0, 1.0, 1.0), Color(1.1, 1.05, 0.85), Color(0.9, 1.0, 0.92)]

var region_key := Vector2i.ZERO
var seed := 0
var zone := "lowlands"
## World detail level from the quality ladder: 0 Low, 1 Medium, 2 High.
var detail := 1
var half_extent := 128.0
## Optional ground lookups in NODE-LOCAL xz (fallback path, tests): height (float)
## and raw control bits (int, -1 = unknown => every ground class allowed).
var height_provider: Callable = Callable()
var control_provider: Callable = Callable()
## Fast path: the region's baked maps, {"height": PackedFloat32Array,
## "control": PackedByteArray, "width": int}, covering exactly this node's cell.
var maps: Dictionary = {}
var road_network: RoadNetwork = null
## World-space clearings (x, z, radius): no trees / bushes inside; small plants
## only outside radius * SMALL_CLEAR_SHARE.
var clear_zones: Array[Vector3] = []
const SMALL_CLEAR_SHARE := 0.55

## Kit override (tests); empty = kit_for(zone, detail).
var kit: Array = []

var _job: Dictionary = {}
var _placed: Dictionary = {}  # batch name -> {"key", "kind", "xf": Array[Transform3D], "tint": Array[Color]}
var _positions: Dictionary = {}  # batch name -> PackedVector3Array (node-local)
var _built := false
static var _grove := FastNoiseLite.new()
static var _grove_ready := false
static var _mat_cache: Dictionary = {}

# -- kits ------------------------------------------------------------------------

## Pure: the placement kit for a dressing zone at a world detail level. Every
## entry: key (FloraMeshes key), kind (tree/bush/rock/crag/small), cell (grid
## spacing m), chance (per cell, before grove modulation), grove (0 = uniform,
## 1 = only inside stands), ground (G_* mask the texel must match), scale
## (min, max), road_clear (m, tree-like entries test the shoulder around them),
## tints (Array[Color]) and optional autumn (share of warm-tinted instances).
static func kit_for(p_zone: String, p_detail: int = 1) -> Array:
	var k: Array = []
	match p_zone:
		"lowlands", "festival":
			k = [
				_e("oak", "tree", 20.0, 0.62, 0.95, G_PLANT, Vector2(0.75, 1.25), 11.0),
				_e("maple", "tree", 38.0, 0.30, 0.6, G_PLANT, Vector2(0.8, 1.2), 10.0, 0.35),
				_e("birch", "tree", 28.0, 0.34, 0.85, G_PLANT, Vector2(0.8, 1.15), 10.0),
				_e("poplar", "tree", 52.0, 0.18, 0.3, G_PLANT, Vector2(0.85, 1.15), 10.0),
				_e("bush", "bush", 11.0, 0.32, 0.6, G_PLANT, Vector2(0.7, 1.45), 4.5),
				_e("shrub", "bush", 9.0, 0.20, 0.3, G_ANY_SOFT, Vector2(0.7, 1.3), 4.0),
				_e("grass", "small", 4.6, 0.62, 0.0, G_PLANT, Vector2(0.8, 1.5), 0.0),
				_e("flowers", "small", 5.0, 0.7, 0.0, G_MEADOW, Vector2(0.8, 1.3), 0.0),
				_e("boulder", "rock", 44.0, 0.10, 0.0, G_ANY_SOFT, Vector2(0.6, 1.4), 6.0),
				_e("crag", "crag", 30.0, 0.45, 0.0, G_ROCK, Vector2(1.6, 3.2), 8.0),
			]
		"highlands":
			k = [
				_e("oak", "tree", 30.0, 0.24, 0.8, G_PLANT, Vector2(0.75, 1.15), 11.0),
				_e("birch", "tree", 30.0, 0.32, 0.8, G_PLANT, Vector2(0.8, 1.2), 10.0),
				_e("maple", "tree", 46.0, 0.2, 0.6, G_PLANT, Vector2(0.75, 1.1), 10.0, 0.5),
				_e("bush", "bush", 12.0, 0.28, 0.6, G_PLANT, Vector2(0.7, 1.3), 4.5),
				_e("shrub", "bush", 10.0, 0.26, 0.2, G_ANY_SOFT | G_ROCK, Vector2(0.6, 1.2), 4.0),
				_e("grass", "small", 5.0, 0.5, 0.0, G_PLANT, Vector2(0.8, 1.4), 0.0),
				_e("flowers", "small", 6.0, 0.55, 0.0, G_MEADOW, Vector2(0.8, 1.2), 0.0),
				_e("boulder", "rock", 26.0, 0.22, 0.0, G_ANY_SOFT | G_ROCK, Vector2(0.7, 1.8), 6.0),
				_e("slab", "rock", 34.0, 0.18, 0.0, G_ANY_SOFT | G_ROCK, Vector2(0.8, 1.8), 6.0),
				_e("crag", "crag", 26.0, 0.5, 0.0, G_ROCK, Vector2(1.8, 3.6), 8.0),
			]
		"coast":
			k = [
				_e("oak", "tree", 40.0, 0.16, 0.7, G_PLANT, Vector2(0.65, 1.0), 11.0),
				_e("maple", "tree", 50.0, 0.12, 0.6, G_PLANT, Vector2(0.7, 1.0), 10.0),
				_e("bush", "bush", 10.0, 0.34, 0.5, G_PLANT | G_SAND, Vector2(0.6, 1.3), 4.5),
				_e("shrub", "bush", 9.0, 0.24, 0.3, G_ANY_SOFT | G_SAND, Vector2(0.6, 1.1), 4.0),
				_e("grass", "small", 5.0, 0.5, 0.0, G_PLANT, Vector2(0.8, 1.4), 0.0),
				_e("dune_grass", "small", 4.5, 0.5, 0.0, G_SAND, Vector2(0.7, 1.4), 0.0),
				_e("flowers", "small", 7.0, 0.4, 0.0, G_MEADOW, Vector2(0.8, 1.2), 0.0),
				_e("boulder", "rock", 36.0, 0.12, 0.0, G_SAND | G_ANY_SOFT, Vector2(0.6, 1.5), 6.0),
				_e("crag", "crag", 28.0, 0.45, 0.0, G_ROCK, Vector2(1.6, 3.2), 8.0),
			]
		"alpine":
			k = [
				_e("shrub", "bush", 12.0, 0.26, 0.4, G_PLANT, Vector2(0.5, 1.0), 4.0),
				_e("grass", "small", 6.0, 0.35, 0.0, G_PLANT, Vector2(0.7, 1.2), 0.0),
				_e("boulder", "rock", 18.0, 0.34, 0.0, G_ANY_SOFT | G_ROCK, Vector2(0.8, 2.2), 6.0),
				_e("slab", "rock", 26.0, 0.2, 0.0, G_ANY_SOFT | G_ROCK | G_SNOW, Vector2(1.0, 2.2), 6.0),
				_e("crag", "crag", 24.0, 0.5, 0.0, G_ROCK, Vector2(2.0, 4.0), 8.0),
			]
	# Detail ladder: Low thins small plants hard and bushes a little; High adds grass.
	var small_scale: float = [0.35, 1.0, 1.4][clampi(p_detail, 0, 2)]
	var bush_scale: float = [0.7, 1.0, 1.15][clampi(p_detail, 0, 2)]
	for e: Dictionary in k:
		if e["kind"] == "small":
			e["chance"] = minf(float(e["chance"]) * small_scale, 0.95)
		elif e["kind"] == "bush":
			e["chance"] = float(e["chance"]) * bush_scale
	return k

static func _e(key: String, kind: String, cell: float, chance: float, grove: float, ground: int, scale: Vector2, road_clear: float, autumn: float = 0.0) -> Dictionary:
	var tints: Array = LEAF_TINTS
	match kind:
		"rock", "crag":
			tints = ROCK_TINTS
		"small":
			tints = PETAL_TINTS if key == "flowers" else GRASS_TINTS
	return {"key": key, "kind": kind, "cell": cell, "chance": chance, "grove": grove, "ground": ground,
		"scale": scale, "road_clear": road_clear, "tints": tints, "autumn": autumn}

## Ground class bit (G_*) of raw control bits, from the base id, or from the
## overlay when it carries at least 40 % of the blend. -1 => every class.
static func ground_mask(bits: int) -> int:
	if bits < 0:
		return 0x7FFFFFFF
	var m := _id_mask(TerrainTexturing.decode_base(bits))
	if TerrainTexturing.decode_blend(bits) >= 0.4:
		m |= _id_mask(TerrainTexturing.decode_overlay(bits))
	return m

static func _id_mask(id: int) -> int:
	match id:
		TerrainTexturing.ID_GRASS: return G_GRASS
		TerrainTexturing.ID_MEADOW: return G_MEADOW
		TerrainTexturing.ID_FOREST: return G_FOREST
		TerrainTexturing.ID_ROCK: return G_ROCK
		TerrainTexturing.ID_SAND: return G_SAND
		TerrainTexturing.ID_SNOW: return G_SNOW
		TerrainTexturing.ID_DIRT: return G_DIRT
	return 0  # gravel (road + shoulder) and unknown ids grow nothing

## Deterministic integer hash -> [0, 1).
static func cell_hash(ix: int, iz: int, salt: int) -> float:
	var h := (ix * 73856093) ^ (iz * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0

## World-space grove density in [0, 1] (stands of trees ~80 m across).
static func grove_at(wx: float, wz: float) -> float:
	if not _grove_ready:
		_grove.seed = 9071
		_grove.frequency = 0.011
		_grove.fractal_type = FastNoiseLite.FRACTAL_FBM
		_grove.fractal_octaves = 2
		_grove_ready = true
	return clampf(_grove.get_noise_2d(wx, wz) * 0.9 + 0.5, 0.0, 1.0)

# -- build ---------------------------------------------------------------------------

## Starts (or restarts) the placement job. Removes any previous batches.
func begin() -> void:
	for child in get_children():
		child.free()
	_placed.clear()
	_positions.clear()
	_built = false
	var entries: Array = kit if not kit.is_empty() else kit_for(zone, detail)
	_job = {"entries": entries, "entry": 0, "cell": 0, "roadside": road_network != null}

## Drops all batches and any running job (detail change, rebuild later).
func reset() -> void:
	for child in get_children():
		child.free()
	_placed.clear()
	_positions.clear()
	_built = false
	_job = {}

func job_active() -> bool:
	return not _job.is_empty()

func is_built() -> bool:
	return _built

## Advances placement for about `budget_usec` microseconds; returns true (and
## creates the MultiMesh batches) once everything is placed.
func step(budget_usec: int = 2000) -> bool:
	if _job.is_empty():
		return true
	var t0 := Time.get_ticks_usec()
	var entries: Array = _job["entries"]
	var anchor := _anchor()
	while int(_job["entry"]) < entries.size():
		var e: Dictionary = entries[int(_job["entry"])]
		var cell: float = e["cell"]
		var n := maxi(int(ceilf(half_extent * 2.0 / cell)), 1)
		var total := n * n
		var c: int = _job["cell"]
		var salt: int = seed ^ (int(_job["entry"]) * 7919 + 17)
		while c < total:
			_place_cell(e, c % n, c / n, n, cell, salt, anchor)
			c += 1
			if (c & 31) == 0 and Time.get_ticks_usec() - t0 > budget_usec:
				_job["cell"] = c
				return false
		_job["entry"] = int(_job["entry"]) + 1
		_job["cell"] = 0
	if bool(_job["roadside"]):
		_job["roadside"] = false
		_place_roadside(anchor)
		if Time.get_ticks_usec() - t0 > budget_usec:
			return false
	_job = {}
	_make_batches()
	_built = true
	return true

## Builds everything at once (tests, tools).
func build_now() -> void:
	begin()
	step(1 << 30)

func _anchor() -> Vector2:
	var gt := global_transform if is_inside_tree() else transform
	return Vector2(gt.origin.x, gt.origin.z)

func _place_cell(e: Dictionary, ix: int, iz: int, n: int, cell: float, salt: int, anchor: Vector2) -> void:
	var gx := floori((anchor.x - half_extent) / cell) + ix
	var gz := floori((anchor.y - half_extent) / cell) + iz
	var roll := cell_hash(gx, gz, salt)
	var chance: float = e["chance"]
	if roll >= chance:
		return
	var lx := (float(ix) + 0.15 + 0.7 * cell_hash(gx, gz, salt + 1)) * cell - half_extent
	var lz := (float(iz) + 0.15 + 0.7 * cell_hash(gx, gz, salt + 2)) * cell - half_extent
	if absf(lx) >= half_extent or absf(lz) >= half_extent:
		return
	var wx := anchor.x + lx
	var wz := anchor.y + lz
	var grove: float = e["grove"]
	if grove > 0.0:
		# roll is uniform in [0, chance): keep it when it falls under the grove share.
		# Sharpened grove field: woods and open fields, not an even orchard.
		var g := smoothstep(0.38, 0.7, grove_at(wx, wz))
		if roll >= chance * lerpf(1.0, g, grove):
			return
	var kind: String = e["kind"]
	if not _clear_of_zones(wx, wz, kind == "small"):
		return
	var mask := ground_mask(_control_local(lx, lz))
	if (mask & int(e["ground"])) == 0:
		return
	var road_clear: float = e["road_clear"]
	if road_clear > 0.0 and not _shoulder_clear(lx, lz, road_clear):
		return
	var h := _height_local(lx, lz)
	var sc: Vector2 = e["scale"]
	var s := lerpf(sc.x, sc.y, cell_hash(gx, gz, salt + 3))
	var yaw := cell_hash(gx, gz, salt + 4) * TAU
	var tints: Array = e["tints"]
	var tint: Color = tints[int(cell_hash(gx, gz, salt + 5) * tints.size()) % tints.size()]
	var autumn: float = e.get("autumn", 0.0)
	if autumn > 0.0 and cell_hash(gx, gz, salt + 6) < autumn:
		tint = AUTUMN_TINTS[int(cell_hash(gx, gz, salt + 7) * AUTUMN_TINTS.size()) % AUTUMN_TINTS.size()]
	var sy := s
	var sink := 0.0
	match kind:
		"crag":
			sy = s * lerpf(0.6, 1.1, cell_hash(gx, gz, salt + 8))
			sink = 0.2 * sy
		"rock":
			sink = 0.15 * s
		"tree":
			sy = s * lerpf(0.9, 1.12, cell_hash(gx, gz, salt + 8))
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, sy, s))
	var origin := Vector3(lx, h - sink, lz)
	var batch: String = e["key"]
	if kind == "small":
		var cx := clampi(int(floorf((lx + half_extent) / SMALL_CHUNK)), 0, 63)
		var cz := clampi(int(floorf((lz + half_extent) / SMALL_CHUNK)), 0, 63)
		batch = "%s_%d_%d" % [e["key"], cx, cz]
	_add(batch, e["key"], kind, Transform3D(basis, origin), tint)

func _add(batch: String, key: String, kind: String, xf: Transform3D, tint: Color) -> void:
	if not _placed.has(batch):
		var xfs: Array[Transform3D] = []
		var tints: Array[Color] = []
		_placed[batch] = {"key": key, "kind": kind, "xf": xfs, "tint": tints}
	var rec: Dictionary = _placed[batch]
	(rec["xf"] as Array).append(xf)
	(rec["tint"] as Array).append(tint)

func _clear_of_zones(wx: float, wz: float, small: bool) -> bool:
	for z: Vector3 in clear_zones:
		var r := z.z * (SMALL_CLEAR_SHARE if small else 1.0)
		var dx := wx - z.x
		var dz := wz - z.y
		if dx * dx + dz * dz < r * r:
			return false
	return true

## No road / shoulder (gravel) texel at the spot or `r` metres around it.
func _shoulder_clear(lx: float, lz: float, r: float) -> bool:
	for o: Vector2 in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r),
			Vector2(r * 0.7, r * 0.7), Vector2(-r * 0.7, r * 0.7), Vector2(r * 0.7, -r * 0.7), Vector2(-r * 0.7, -r * 0.7)]:
		var bits := _control_local(lx + o.x, lz + o.y)
		if bits < 0:
			continue
		if TerrainTexturing.decode_base(bits) == TerrainTexturing.ID_GRAVEL:
			return false
		if TerrainTexturing.decode_overlay(bits) == TerrainTexturing.ID_GRAVEL and TerrainTexturing.decode_blend(bits) > 0.2:
			return false
	return true

func _texel(lx: float, lz: float) -> int:
	var w: int = maps["width"]
	var ix := clampi(int(floorf((lx + half_extent) / (half_extent * 2.0) * float(w))), 0, w - 1)
	var iz := clampi(int(floorf((lz + half_extent) / (half_extent * 2.0) * float(w))), 0, w - 1)
	return iz * w + ix

func _height_local(lx: float, lz: float) -> float:
	if maps.has("height"):
		return (maps["height"] as PackedFloat32Array)[_texel(lx, lz)]
	if height_provider.is_valid():
		return float(height_provider.call(Vector2(lx, lz)))
	return 0.0

func _control_local(lx: float, lz: float) -> int:
	if maps.has("control"):
		return (maps["control"] as PackedByteArray).decode_u32(_texel(lx, lz) * 4)
	if control_provider.is_valid():
		return int(control_provider.call(Vector2(lx, lz)))
	return -1

# -- roadside furniture -------------------------------------------------------------

const DELINEATOR_SPACING := 40.0
const CHEVRON_SPACING := 18.0
const CHEVRON_TURN := deg_to_rad(16.0)  # heading change over CURVE_PROBE metres
const CURVE_PROBE := 30.0
const SIGN_SPACING := 700.0
const FENCE_BAY := 4.0

## Delineator posts where a road has no guard rail, chevron boards on the
## outside of tight bends, route signs along highways / arterials and wooden
## fences along lowland country roads. Pure function of the shared road defs
## and this region's cell (segments are assigned to the cell of their midpoint,
## like the streamed road meshes).
func _place_roadside(anchor: Vector2) -> void:
	if road_network == null:
		return
	var lo := anchor - Vector2(half_extent, half_extent)
	var hi := anchor + Vector2(half_extent, half_extent)
	var defs := road_network.get_road_defs()
	for di in defs.size():
		var def: RoadDef = defs[di]
		var pts := def.points
		var count := pts.size()
		if count < 2:
			continue
		var segs := count if def.closed else count - 1
		var dist := 0.0
		var rails := def.rails_enabled()
		var fence_ok := zone == "lowlands" and def.tier != RoadDef.Tier.HIGHWAY
		for k in segs:
			var a: Vector3 = pts[k]
			var b: Vector3 = pts[(k + 1) % count]
			var seg := b - a
			seg.y = 0.0
			var length := seg.length()
			if length < 0.01:
				continue
			var mid := (a + b) * 0.5
			var inside := mid.x >= lo.x and mid.x < hi.x and mid.z >= lo.y and mid.z < hi.y
			if inside:
				_roadside_segment(def, di, k, a, b, dist, length, rails, fence_ok, anchor)
			dist += length

func _roadside_segment(def: RoadDef, di: int, k: int, a: Vector3, b: Vector3, s0: float, length: float, rails: bool, fence_ok: bool, anchor: Vector2) -> void:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z) / length
	var right := Vector3(-d.z, 0.0, d.x)
	var half := def.width * 0.5
	var mask := def.rail_sides_mask_at(k) if rails else RoadDef.RailSide.NONE
	var salt := seed ^ (di * 4099 + 31)
	# Delineators: one pair every DELINEATOR_SPACING of arc length, rail-free sides only.
	var first := ceilf(s0 / DELINEATOR_SPACING) * DELINEATOR_SPACING
	var s := first
	while s < s0 + length:
		var t := (s - s0) / length
		var p := a.lerp(b, t)
		for side in [1, -1]:
			var bit := RoadDef.RailSide.RIGHT if side == 1 else RoadDef.RailSide.LEFT
			if (mask & bit) != 0:
				continue
			var q: Vector3 = p + right * float(side) * (half + 0.9)
			_add_prop("delineator", q, d, p.y, 1.0, Color(1, 1, 1), anchor)
		s += DELINEATOR_SPACING
	# Chevrons on the outside of a tight bend.
	var turn := _turn_at(def, k, CURVE_PROBE)
	if absf(turn) > CHEVRON_TURN:
		# The outside of a right-hand bend is the left side and vice versa.
		var out_side := -1.0 if turn > 0.0 else 1.0
		s = ceilf(s0 / CHEVRON_SPACING) * CHEVRON_SPACING
		while s < s0 + length:
			var t2 := (s - s0) / length
			var p2 := a.lerp(b, t2)
			var q2: Vector3 = p2 + right * out_side * (half + 2.2)
			_add_prop("chevron", q2, -d, p2.y, 1.0, Color(1, 1, 1), anchor)
			s += CHEVRON_SPACING
	# Route signs on the big roads.
	if def.tier == RoadDef.Tier.HIGHWAY or def.tier == RoadDef.Tier.ARTERIAL:
		var sign_s := ceilf((s0 + 150.0 * float(di % 4)) / SIGN_SPACING) * SIGN_SPACING - 150.0 * float(di % 4)
		if sign_s >= s0 and sign_s < s0 + length and absf(turn) < CHEVRON_TURN:
			var p3 := a.lerp(b, (sign_s - s0) / length)
			_add_prop("route_sign", p3 + right * (half + 3.5), -d, p3.y, 1.0, Color(1, 1, 1), anchor)
	# Farm fences along lowland country roads, in runs picked by a coarse hash.
	if fence_ok:
		var run := int(floorf(s0 / 160.0))
		if cell_hash(di, run, salt) < 0.45:
			var fs := ceilf(s0 / FENCE_BAY) * FENCE_BAY
			while fs < s0 + length:
				var p4 := a.lerp(b, (fs - s0) / length)
				for side in [1, -1]:
					var q4: Vector3 = p4 + right * float(side) * (half + 7.0)
					var gy := _height_local(q4.x - anchor.x, q4.z - anchor.y)
					_add_prop("fence", q4, d, gy, 1.0, Color(1, 1, 1), anchor, true)
				fs += FENCE_BAY

## Signed heading change (radians, + = bending toward the right side) over
## `probe` metres before and after point k of a road.
func _turn_at(def: RoadDef, k: int, probe: float) -> float:
	var pts := def.points
	var n := pts.size()
	var i0 := k
	var acc := 0.0
	while acc < probe:
		var j := i0 - 1
		if j < 0:
			if not def.closed:
				break
			j = n - 1
		acc += Vector2(pts[i0].x - pts[j].x, pts[i0].z - pts[j].z).length()
		i0 = j
		if i0 == k:
			break
	var i1 := (k + 1) % n
	acc = 0.0
	while acc < probe:
		var j2 := i1 + 1
		if j2 >= n:
			if not def.closed:
				break
			j2 = 0
		acc += Vector2(pts[j2].x - pts[i1].x, pts[j2].z - pts[i1].z).length()
		i1 = j2
		if i1 == k:
			break
	var d0 := Vector2(pts[k].x - pts[i0].x, pts[k].z - pts[i0].z)
	var d1 := Vector2(pts[i1].x - pts[k].x, pts[i1].z - pts[k].z)
	if d0.length() < 0.01 or d1.length() < 0.01:
		return 0.0
	# In (x, z) a positive angle turns from +x toward +z, i.e. toward the
	# road's RIGHT side ((-dz, 0, dx), RoadDef.RailSide.RIGHT).
	return d0.angle_to(d1)

## Adds one roadside prop (world-space position, facing `facing` along +Z, or
## along +X for fences) to the "prop" batch of its mesh.
func _add_prop(key: String, world: Vector3, facing: Vector3, y: float, scale: float, tint: Color, anchor: Vector2, along_x: bool = false) -> void:
	var lx := world.x - anchor.x
	var lz := world.z - anchor.y
	if absf(lx) >= half_extent + 4.0 or absf(lz) >= half_extent + 4.0:
		return
	var yaw := atan2(-facing.z, facing.x) if along_x else atan2(facing.x, facing.z)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
	_add(key, key, "prop", Transform3D(basis, Vector3(lx, y, lz)), tint)

# -- batches ---------------------------------------------------------------------------

func _make_batches() -> void:
	var names := _placed.keys()
	names.sort()
	for name: String in names:
		var rec: Dictionary = _placed[name]
		var xfs: Array = rec["xf"]
		if xfs.is_empty():
			continue
		var tints: Array = rec["tint"]
		var kind: String = rec["kind"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = FloraMeshes.get_mesh(String(rec["key"]))
		mm.instance_count = xfs.size()
		# A small batch covers one SMALL_CHUNK patch: its node sits at the
		# patch centre so the draw distance is measured to the patch, not to
		# the region centre.
		var centre := Vector3.ZERO
		if kind == "small":
			for t: Transform3D in xfs:
				centre += t.origin
			centre /= float(xfs.size())
			centre.y = 0.0
		var buf := PackedFloat32Array()
		buf.resize(xfs.size() * 16)
		var pos := PackedVector3Array()
		pos.resize(xfs.size())
		for i in xfs.size():
			var t: Transform3D = xfs[i]
			var c: Color = tints[i]
			var o := i * 16
			buf[o] = t.basis.x.x; buf[o + 1] = t.basis.y.x; buf[o + 2] = t.basis.z.x; buf[o + 3] = t.origin.x - centre.x
			buf[o + 4] = t.basis.x.y; buf[o + 5] = t.basis.y.y; buf[o + 6] = t.basis.z.y; buf[o + 7] = t.origin.y
			buf[o + 8] = t.basis.x.z; buf[o + 9] = t.basis.y.z; buf[o + 10] = t.basis.z.z; buf[o + 11] = t.origin.z - centre.z
			buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = 1.0
			pos[i] = t.origin
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.name = name
		mmi.multimesh = mm
		mmi.position = centre
		mmi.material_override = material_for(kind)
		mmi.cast_shadow = _shadow_for(kind)
		mmi.visibility_range_end = float(DRAW_DISTANCE.get(kind, 400.0))
		mmi.visibility_range_end_margin = 20.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		_positions[name] = pos
		add_child(mmi)

func _shadow_for(kind: String) -> GeometryInstance3D.ShadowCastingSetting:
	match kind:
		"tree", "crag":
			return GeometryInstance3D.SHADOW_CASTING_SETTING_ON if detail >= 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"rock", "prop":
			return GeometryInstance3D.SHADOW_CASTING_SETTING_ON if detail >= 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Shared materials per batch kind (one shader each for closed meshes and for
## grass / flowers).
static func material_for(kind: String) -> ShaderMaterial:
	if _mat_cache.has(kind):
		return _mat_cache[kind]
	var mat := ShaderMaterial.new()
	if kind == "small":
		mat.shader = load("res://shaders/flora_grass.gdshader") as Shader
	else:
		mat.shader = load("res://shaders/flora.gdshader") as Shader
		var wind := 0.0
		match kind:
			"tree": wind = 0.25
			"bush": wind = 0.08
		mat.set_shader_parameter("wind_strength", wind)
	_mat_cache[kind] = mat
	return mat

# -- queries (tests, dresser) -------------------------------------------------------------

func get_instance_count() -> int:
	var total := 0
	for name: String in _positions:
		total += (_positions[name] as PackedVector3Array).size()
	return total

func count_for(key: String) -> int:
	var total := 0
	for name: String in _placed:
		if String((_placed[name] as Dictionary)["key"]) == key:
			total += ((_placed[name] as Dictionary)["xf"] as Array).size()
	return total

## Node-local origins of every instance of a mesh key (side arrays).
func positions_for(key: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	var names := _placed.keys()
	names.sort()
	for name: String in names:
		var rec: Dictionary = _placed[name]
		if String(rec["key"]) != key:
			continue
		for t: Transform3D in rec["xf"]:
			out.append(t.origin)
	return out

func batch_names() -> PackedStringArray:
	var out := PackedStringArray()
	for c in get_children():
		out.append(String(c.name))
	return out

## Triangles one full draw of this region would submit (all batches).
func triangle_estimate() -> int:
	var total := 0
	for name: String in _placed:
		var rec: Dictionary = _placed[name]
		total += FloraMeshes.triangle_count(FloraMeshes.get_mesh(String(rec["key"]))) * (rec["xf"] as Array).size()
	return total
