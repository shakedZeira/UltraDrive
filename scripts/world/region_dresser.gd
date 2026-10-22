# scripts/world/region_dresser.gd
class_name RegionDresser
extends Node3D

## P7 region-streamed dressing manager for the open world. Keeps a
## `_dressed` set mirrored to the TerrainSeeder live ring plus the prefetch
## band (the same RING_RADIUS / PREFETCH_RADIUS geometry, expressed as region
## chebyshev distance), so dressing appears with the ground, survives into the
## prefetch band, is freed when a region falls out of it, and NEVER duplicates
## on re-stream: every region is dressed by exactly one node whose children are
## one PropScatterer and one Foliage instance.
##
## All spawn/band-change/free work is main-thread only and drained a bounded
## handful per frame (max_dresses_per_frame / max_frees_per_frame, mirroring
## TerrainSeeder.MAX_APPLY_PER_TICK and the _apply_ring_pass / _remove_far_regions
## cadence) so a ring shift can never stall a frame.
##
## Per-region placement is deterministic: the region seed is a pure hash of
## (master_seed, region loc) and the dressing zone is a pure function of the
## same, so re-entering a region is bit-identical placement (proven in
## test_streaming_dressing). Heights come from the seeder's baked cache (kept
## warm by the prefetch ring) or the live Terrain3D -- never from a worker
## thread; the optional `terrain_seeder` connection fences band changes via the
## seeder's region_entered/region_left signals.
##
## LOD is two-staged: generation-time density scaling on the prefetch band
## (prefetch_density instance counts) plus distance-banded instance culling
## (band_visibility of the placed instances drawn via
## MultiMesh.visible_instance_count). The live ring always generates at full
## density and draws everything.
##
## What a region gets (wired in open_world_root.tscn since 2026-10-22): a
## natural kit chosen by biome (region_zone / region_preset / ZONE_FOLIAGE),
## placed uniformly over its own 256 m cell (square mode, no overlap), with
## foliage kept off rock/snow, beach sand and the clear_zones landmark
## clearings. With a seeder attached a region waits for its terrain bake so
## everything sits on the real carved ground. Each batch has a draw distance
## (GRASS/PROPS/TREES_DRAW_DISTANCE) on top of per-region frustum culling.
##
## Observation modes (all converge idempotently):
##  1. sync_player_pos(world_pos) on the same cadence as
##     TerrainSeeder.sync_player_pos (typically from WorldDriver);
##  2. set `player` and the dresser mirrors it each _process;
##  3. assign `terrain_seeder` and let its signals fence band liveliness.

const BAND_LIVE := 0
const BAND_PREFETCH := 1
const DEFAULT_MASTER_SEED := 82731408
const DRESS_NODE_NAME := "Dress"
const PROPS_CHILD_NAME := "Props"
const FOLIAGE_CHILD_NAME := "Foliage"
const REGION_CELL := 256.0  # region-loc geometry is fixed at REGION_SIZE 256

## Prefetch-band culling: drawn = ceil(placed * (clamped prefetch_density *
## PREFETCH_VISIBILITY_RATIO)). The 1.25 factor makes the 0.5 prefetch band draw
## ~63% of its already-reduced counts -- clearly lighter than the live ring but
## not a jarring pop when a region goes live (density 1.0).
const PREFETCH_VISIBILITY_RATIO := 1.25

## Per-batch draw distances (GeometryInstance3D.visibility_range_end, metres
## from the camera). A region's grass batch is only submitted while the camera
## is near it and rocks/poles while they still read; trees stay up to the fog.
## Together with per-region MultiMesh frustum culling this keeps the 25-region
## band's draw calls to the handful of batches actually in view.
const GRASS_DRAW_DISTANCE := 140.0
const PROPS_DRAW_DISTANCE := 420.0
const TREES_DRAW_DISTANCE := 900.0
const DRAW_FADE_MARGIN := 20.0

## Biome thresholds for zone choice and the foliage filter, shared with the
## ground texture bake so trees stop where the rock/snow textures start and
## never stand on the beach sand.
const TREELINE_HEIGHT := TerrainBaker.CTRL_ALPINE_START + 60.0
const BEACH_WEIGHT_MAX := 0.35

## Per-zone foliage counts for a live region (prefetch scales by density).
## Grass is half the hub Foliage's 700: the textured ground carries the look
## now, grass only draws within GRASS_DRAW_DISTANCE, and it is the costliest
## batch to place (~8 us per tuft on the main thread, measured 2026-10-22).
const ZONE_FOLIAGE := {
	"lowlands": {"grass": 350, "trees": 40},
	"highlands": {"grass": 250, "trees": 70},
	"coast": {"grass": 150, "trees": 12},
	"alpine": {"grass": 0, "trees": 14},
}

@export var terrain_seeder: TerrainSeeder
@export var terrain: Terrain3D
@export var road_network: RoadNetwork
@export var traffic_spawner: TrafficSpawner
@export var player: Node3D
@export var region_size: float = REGION_CELL
@export var live_ring_radius: int = 1
@export var prefetch_band_radius: int = 2
@export var max_dresses_per_frame: int = 2
@export var max_frees_per_frame: int = 2
@export var prefetch_density: float = 0.5
@export var master_seed: int = DEFAULT_MASTER_SEED
## Landmark clearings: each entry is (world x, world z, radius). Region foliage
## never grows inside one, so the hand-placed hub kit (its own Foliage ring and
## festival props) is not double-dressed. Region props still may.
@export var clear_zones: Array[Vector3] = []
## Build each region's grass batch on a later drain than its props + trees,
## and only on a drain that dressed nothing else, so no single frame pays for
## a whole region (grass is the costliest batch). pending_grass_count() tracks it.
@export var defer_grass: bool = true
## Grass slots placed per idle drain (~8-12 us each on the main thread, so the
## default keeps a grass slice near 1-1.5 ms; a live lowland region takes 3).
@export var grass_tufts_per_frame: int = 120
## Multiplier on ZONE_FOLIAGE grass. The open-world scene sets 0: Foliage's
## grass tuft is a flat PlaneMesh that reads as bright green squares lying on
## the textured ground (captures 2026-10-22), so region grass stays off until a
## real grass-card mesh exists; the textured ground carries the grass look.
@export var region_grass_scale: float = 1.0

var _player_region := Vector2i(1 << 30, 1 << 30)
## Main-thread natural-height fallback for samples whose region has no cached
## bake yet (the dresser never reads Terrain3D or the cache off the main thread).
var _baker := TerrainBaker.new()
## loc (Vector2i) -> {"band": int, "node": Node3D}. The dressed set mirrored to
## the live ring + prefetch band around the player.
var _dressed: Dictionary = {}
var _spawn_queue: Array = []
var _band_queue: Array = []
var _free_queue: Array = []
## Regions whose grass batch is still to be built (defer_grass).
var _grass_queue: Array[Vector2i] = []
var _offsets_cache: Array[Vector2i] = []
var _offsets_radius := -1

## Test-visible counters (strictly bookkeeping).
var dress_count: int = 0
var free_count: int = 0

func _ready() -> void:
	if terrain_seeder != null:
		if not terrain_seeder.region_entered.is_connected(_on_region_entered):
			terrain_seeder.region_entered.connect(_on_region_entered)
		if not terrain_seeder.region_left.is_connected(_on_region_left):
			terrain_seeder.region_left.connect(_on_region_left)

func _exit_tree() -> void:
	if terrain_seeder != null:
		if terrain_seeder.region_entered.is_connected(_on_region_entered):
			terrain_seeder.region_entered.disconnect(_on_region_entered)
		if terrain_seeder.region_left.is_connected(_on_region_left):
			terrain_seeder.region_left.disconnect(_on_region_left)

## Poll observation mode: mirrors the ring on every frame, then drains a bounded
## handful of pending jobs. Wired always; with `player` unset it only services
## manual sync_player_pos() callers.
func _process(_delta: float) -> void:
	if player != null:
		sync_player_pos(player.global_position)
	drain_pending()

## Re-mirrors the dressed set to the band around a world position and runs the
## TrafficSpawner ring update. Idempotent: repeated calls for the same position
## enqueue nothing new. Frees are queued before spawns so a shift never grows
## the dressed set past the band size, matching the _remove_far_regions cadence.
func sync_player_pos(player_pos: Vector3) -> void:
	if traffic_spawner != null:
		traffic_spawner.update(player_pos)
	var new_region := Vector2i(floori(player_pos.x / region_size), floori(player_pos.z / region_size))
	_player_region = new_region
	# Nearest-first (the player's own region, then the live ring, then the
	# prefetch band), so queued spawns and deferred grass dress what is in view first.
	var desired := {}
	for off: Vector2i in _band_offsets():
		var loc := new_region + off
		desired[loc] = _band_for(loc, new_region)
	for loc in _dressed.keys():
		if not desired.has(loc):
			_queue_free(loc)
	for loc in desired:
		var band: int = desired[loc]
		if not _dressed.has(loc):
			_queue_spawn(loc, band)
		elif int((_dressed[loc] as Dictionary)["band"]) != band:
			_queue_band(loc, band)

## Drains the pending spawn/band/free work a bounded handful per frame. Frees
## get their own budget; spawns and band re-generations share the dress budget
## (2 per frame by default, mirroring the seeder's MAX_APPLY_PER_TICK).
func drain_pending() -> void:
	var freed := 0
	while not _free_queue.is_empty() and freed < max_frees_per_frame:
		var loc: Vector2i = _free_queue.pop_front()
		_free_region(loc)
		freed += 1
	var dresses := 0
	while not _band_queue.is_empty() and dresses < max_dresses_per_frame:
		var job: Dictionary = _band_queue.pop_front()
		_apply_band(job["loc"] as Vector2i, int(job["band"]))
		dresses += 1
	# Spawns wait for the region's terrain bake (with a seeder attached) so the
	# dressing is placed on the real carved ground, never on a fallback height
	# that would leave trees floating over a road cut. Waiting jobs rotate to
	# the back; each job is looked at once per drain at most.
	var scanned := 0
	var queued := _spawn_queue.size()
	while not _spawn_queue.is_empty() and dresses < max_dresses_per_frame and scanned < queued:
		var job: Dictionary = _spawn_queue.pop_front()
		scanned += 1
		if not _ground_ready(job["loc"] as Vector2i):
			_spawn_queue.append(job)
			continue
		_spawn_region(job)
		dresses += 1
	if dresses == 0:
		_drain_one_grass()

## Builds the next pending grass batch (nearest region first, by queue order).
## Regions freed or regenerated meanwhile are skipped / rebuilt idempotently.
func _drain_one_grass() -> void:
	while not _grass_queue.is_empty():
		var loc: Vector2i = _grass_queue[0]
		var node: Node3D = (_dressed[loc] as Dictionary)["node"] if _dressed.has(loc) else null
		var foliage: Foliage = node.get_node_or_null(FOLIAGE_CHILD_NAME) as Foliage if node != null else null
		if foliage == null:
			_grass_queue.pop_front()
			continue
		if not foliage.grass_job_active():
			foliage.begin_grass()
		# Time-sliced: grass_tufts_per_frame slots per idle drain.
		if not foliage.step_grass(grass_tufts_per_frame):
			return
		_grass_queue.pop_front()
		var props: PropScatterer = node.get_node_or_null(PROPS_CHILD_NAME) as PropScatterer
		if props != null:
			_apply_band_budget(props, foliage, int((_dressed[loc] as Dictionary)["band"]))
		_apply_draw_distances(node)
		return

func _queue_grass(loc: Vector2i) -> void:
	if not defer_grass or _grass_queue.has(loc) or not _dressed.has(loc):
		return
	var node: Node3D = (_dressed[loc] as Dictionary)["node"]
	var foliage: Foliage = node.get_node_or_null(FOLIAGE_CHILD_NAME) as Foliage
	if foliage == null or foliage.grass_count <= 0:
		return  # nothing to build (e.g. alpine regions, or region_grass_scale 0)
	_grass_queue.append(loc)

func pending_grass_count() -> int:
	return _grass_queue.size()

## Band offsets sorted nearest-first (Chebyshev ring, then x, then y), cached
## per prefetch_band_radius.
func _band_offsets() -> Array[Vector2i]:
	if _offsets_radius == prefetch_band_radius:
		return _offsets_cache
	_offsets_cache = []
	for dx in range(-prefetch_band_radius, prefetch_band_radius + 1):
		for dz in range(-prefetch_band_radius, prefetch_band_radius + 1):
			_offsets_cache.append(Vector2i(dx, dz))
	_offsets_cache.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ra := maxi(absi(a.x), absi(a.y))
		var rb := maxi(absi(b.x), absi(b.y))
		if ra != rb:
			return ra < rb
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y
	)
	_offsets_radius = prefetch_band_radius
	return _offsets_cache

func _queue_spawn(loc: Vector2i, band: int) -> void:
	if _dressed.has(loc):
		return
	for job: Dictionary in _spawn_queue:
		if job["loc"] == loc:
			return
	_spawn_queue.append({"loc": loc, "band": band})

func _queue_band(loc: Vector2i, band: int) -> void:
	if not _dressed.has(loc):
		_queue_spawn(loc, band)
		return
	for job: Dictionary in _band_queue:
		if job["loc"] == loc:
			return
	_band_queue.append({"loc": loc, "band": band})

func _queue_free(loc: Vector2i) -> void:
	if not _dressed.has(loc):
		return
	for job: Vector2i in _free_queue:
		if job == loc:
			return
	_free_queue.append(loc)

## Creates the DressedRegion node for a loc: one PropScatterer + one Foliage,
## both configured with the deterministic per-region seed, the band density and
## the region-anchored ground-height provider, then relies on their _ready to
## generate the MultiMesh batches on this (main) thread when parented.
##
## The dresser's own `road_network` is handed to each scatterer as-is: it is
## the SHARED whole-map network (roads run through many regions, and every
## scatterer samples its own slice of the full corridor set for roadside
## dressing), never a region-local subset. The scatterer still bounds its
## roadside pull to its own radius, so a region only ever dresses its own patch.
func _spawn_region(job: Dictionary) -> void:
	var loc: Vector2i = job["loc"]
	var band: int = int(job["band"])
	if band != BAND_LIVE and band != BAND_PREFETCH:
		band = _band_for(loc, _player_region)
	if _dressed.has(loc):
		return
	var seed: int = region_seed(master_seed, loc)
	var zone: String = region_zone(master_seed, loc)
	var preset: Dictionary = region_preset(zone, region_size)
	preset["seed"] = seed
	var density: float = band_density(band)
	var node := Node3D.new()
	node.name = "%s %d,%d" % [DRESS_NODE_NAME, loc.x, loc.y]
	node.position = Vector3(loc.x * region_size + region_size * 0.5, 0.0, loc.y * region_size + region_size * 0.5)
	add_child(node)
	var props := PropScatterer.new()
	props.name = PROPS_CHILD_NAME
	props.road_network = road_network
	props.configure(preset)
	props.configure_for_region(loc, seed, density)
	props.ground_height_provider = _make_ground_provider(loc)
	node.add_child(props)
	var foliage := Foliage.new()
	foliage.name = FOLIAGE_CHILD_NAME
	var counts: Dictionary = ZONE_FOLIAGE.get(zone, ZONE_FOLIAGE["lowlands"])
	foliage.grass_count = int(round(float(counts["grass"]) * maxf(region_grass_scale, 0.0)))
	foliage.tree_count = int(counts["trees"])
	foliage.square_half_extent = region_size * 0.5
	foliage.inner_clear_radius = 0.0
	foliage.radius = region_size * 0.5
	foliage.configure_for_region(loc, seed, density)
	foliage.defer_grass = defer_grass
	foliage.ground_height_provider = _make_ground_provider(loc)
	foliage.placement_filter = _make_foliage_filter(loc)
	if terrain_seeder != null:
		foliage.grass_filter = _make_grass_filter(loc)
	foliage.road_network = road_network
	node.add_child(foliage)
	_apply_band_budget(props, foliage, band)
	_apply_draw_distances(node)
	node.visible = band_shown(band)
	_dressed[loc] = {"band": band, "node": node}
	_queue_grass(loc)
	dress_count += 1

## Regenerates a dressed region's batches at a different band density
## (live <-> prefetch). Same seed, same zone: only the density changes, so
## upgrading restores the full instance set bit-identically. Idempotent.
func _apply_band(loc: Vector2i, band: int) -> void:
	if not _dressed.has(loc):
		_queue_spawn(loc, band)
		return
	var entry: Dictionary = _dressed[loc]
	if int(entry["band"]) == band:
		return
	var node: Node3D = entry["node"]
	var props: PropScatterer = node.get_node_or_null(PROPS_CHILD_NAME) as PropScatterer
	var foliage: Foliage = node.get_node_or_null(FOLIAGE_CHILD_NAME) as Foliage
	var seed: int = region_seed(master_seed, loc)
	var density: float = band_density(band)
	if props != null:
		props.configure_for_region(loc, seed, density)
		props.generate()
	if foliage != null:
		foliage.configure_for_region(loc, seed, density)
		foliage.generate()
	if props != null and foliage != null:
		_apply_band_budget(props, foliage, band)
	_apply_draw_distances(node)
	node.visible = band_shown(band)
	entry["band"] = band
	_queue_grass(loc)
	dress_count += 1

## Frees a dressed region immediately (main thread). The node and all its
## MultiMesh children are owned by the dresser, so eviction is leak-free and the
## region leaves _dressed the same frame -- dressing mirrors
## _remove_far_regions, it never lags behind the live terrain set.
func _free_region(loc: Vector2i) -> void:
	if not _dressed.has(loc):
		return
	var entry: Dictionary = _dressed[loc]
	_dressed.erase(loc)
	var node: Node3D = entry["node"]
	if node != null and is_instance_valid(node) and node.get_parent() == self:
		node.free()
	free_count += 1

## Seeder signal: a region's bake entered the live ring. Dress it at live
## density; if it is already dressed (re-entered ring region), just upgrade it.
func _on_region_entered(loc: Vector2i) -> void:
	if _dressed.has(loc):
		_queue_band(loc, BAND_LIVE)
	else:
		_queue_spawn(loc, BAND_LIVE)

## Seeder signal: a region left the live ring. Keep it dressed at prefetch
## density while the dresser's own band still covers it; beyond the band the
## dresser's sync diff frees it (regions at prefetch-only distance never fire
## this signal, since the seeder only ever removes live-ring regions).
func _on_region_left(loc: Vector2i) -> void:
	if _dressed.has(loc):
		_queue_band(loc, BAND_PREFETCH)

## Whether a band's dressing is drawn. With a seeder attached only the live
## ring is shown: Terrain3D regions exist only there (the prefetch band is
## cached bakes, the world past the ring is a flat y=0 background), so
## prefetch-band trees would stand at their real heights over flat ground. The
## band stays generated, so a region going live just turns visible. Without a
## seeder (flat scenes, unit tests) every band is shown.
func band_shown(band: int) -> bool:
	return band == BAND_LIVE or terrain_seeder == null

## LOD density for a band: full instance counts on the live ring, prefetch_density
## on the prefetch band (generation-time reduced counts).
func band_density(band: int) -> float:
	return 1.0 if band == BAND_LIVE else maxf(prefetch_density, 0.0)

## Distance-banded culling fraction: every placed instance is drawn on the
## live ring; the prefetch band draws a fraction of its (already reduced)
## placed set via visible_instance_count.
func band_visibility(band: int) -> float:
	if band == BAND_LIVE:
		return 1.0
	return clampf(maxf(prefetch_density, 0.1) * PREFETCH_VISIBILITY_RATIO, 0.2, 1.0)

## Distance-banded instance culling: caps the drawn instances of both batches
## to the band's visibility budget (all placed instances on the live ring,
## band_visibility of them on the prefetch band). Pure visibility, no rebuild.
func _apply_band_budget(props: PropScatterer, foliage: Foliage, band: int) -> void:
	var placed := props.get_instance_count() + foliage.get_instance_count()
	if placed <= 0:
		return
	var visible := ceili(float(placed) * band_visibility(band))
	props.set_visible_instance_count(visible)
	foliage.set_visible_instance_count(visible)

func dressed_region_count() -> int:
	return _dressed.size()

func is_dressed(loc: Vector2i) -> bool:
	return _dressed.has(loc)

func region_band(loc: Vector2i) -> int:
	return int((_dressed[loc] as Dictionary)["band"]) if _dressed.has(loc) else -1

func region_node(loc: Vector2i) -> Node3D:
	return _dressed[loc]["node"] as Node3D if _dressed.has(loc) else null

func pending_spawn_count() -> int:
	return _spawn_queue.size()

func pending_free_count() -> int:
	return _free_queue.size()

## Tears the whole dressed set down (world teardown and tests).
func clear_all() -> void:
	_spawn_queue.clear()
	_band_queue.clear()
	_free_queue.clear()
	_grass_queue.clear()
	for loc in _dressed.keys():
		_free_region(loc)

func _band_for(loc: Vector2i, player_region: Vector2i) -> int:
	var reach := maxi(absi(loc.x - player_region.x), absi(loc.y - player_region.y))
	return BAND_LIVE if reach <= live_ring_radius else BAND_PREFETCH

## Deterministic per-region seed: pure hash of the master seed + region loc,
## using the same 131/977 prime mix as TerrainBaker's per-region noise so the
## dressing family matches the terrain family. Re-entering a region reproduces
## the exact same placement stream.
static func region_seed(master: int, loc: Vector2i) -> int:
	var h := master
	h = (h ^ (loc.x * 131)) * 1000003
	h = (h ^ (loc.y * 977)) * 1000003
	return h

## Deterministic dressing zone for a region (one of the zone names
## festival / lowlands / coast / highlands / alpine; the dresser never picks
## festival, that kit is the hub's static landmark). Pure function of the loc:
## the natural terrain height at the region centre and the coast biome weight,
## with the same thresholds the ground texture bake uses (beach sand -> coast,
## treeline/rock -> alpine, forest-floor band -> highlands). `master` is kept
## for signature stability; the biome map is not seeded per save.
static func region_zone(_master: int, loc: Vector2i) -> String:
	var cx := (float(loc.x) + 0.5) * REGION_CELL
	var cz := (float(loc.y) + 0.5) * REGION_CELL
	var h := TerrainBaker.new().natural_height_at(cx, cz)
	if TerrainBaker.coast_weight(cx, cz) > 0.4 and h < 12.0:
		return "coast"
	if h >= TerrainBaker.CTRL_ALPINE_START:
		return "alpine"
	if h >= TerrainBaker.CTRL_LOW_TOP:
		return "highlands"
	return "lowlands"

## Natural-only PropScatterer kit for one streamed region of `zone`. The racing
## kit (barriers, rails, grandstands, tents) belongs to the static landmark
## scatterers, not to every 256 m of countryside. Square placement covers the
## region cell exactly (no overlap with neighbours); radius is its half
## diagonal so the roadside sampler can reach the region's corners.
static func region_preset(zone: String, cell: float = REGION_CELL) -> Dictionary:
	var half := cell * 0.5
	var preset := {
		"radius": half * 1.4143, "inner_clear_radius": 0.0, "seed": 1002,
		"road_threshold": 8.0, "roadside_fraction": 0.5,
		"roadside_max_dist": 22.0, "square_half_extent": half,
	}
	match zone:
		"coast":
			preset["props"] = {
				"rock": {"count": 10, "min_spacing": 18.0, "scale": Vector2(1.2, 2.2)},
				"power_pole": {"count": 2, "min_spacing": 70.0, "scale": Vector2(0.9, 1.1)},
			}
		"highlands":
			preset["props"] = {
				"rock": {"count": 10, "min_spacing": 16.0, "scale": Vector2(1.0, 2.0)},
				"power_pole": {"count": 3, "min_spacing": 70.0, "scale": Vector2(0.9, 1.1)},
			}
		"alpine":
			preset["props"] = {
				"rock": {"count": 14, "min_spacing": 16.0, "scale": Vector2(1.2, 2.4)},
			}
		_:
			preset["props"] = {
				"rock": {"count": 6, "min_spacing": 20.0, "scale": Vector2(0.8, 1.6)},
				"power_pole": {"count": 4, "min_spacing": 60.0, "scale": Vector2(0.9, 1.1)},
			}
	return preset

## True when a region may be dressed now: always without a seeder (unit tests,
## flat scenes), otherwise once the seeder has its bake cached, so placement
## heights come from the real carved terrain.
func _ground_ready(loc: Vector2i) -> bool:
	if terrain_seeder == null:
		return true
	return terrain_seeder.has_baked_region(loc)

## World-space ground height for dressing at (wx, wz), main thread only:
## the seeder's cached bake of WHICHEVER region contains the point (a region's
## kit reaches into its neighbours' cells at the edges), then the live
## Terrain3D, then the baker's natural height (no road carve) as a last resort.
func ground_height_at(wx: float, wz: float) -> float:
	var world := Vector3(wx, 0.0, wz)
	if terrain_seeder != null:
		var cell := Vector2i(floori(wx / region_size), floori(wz / region_size))
		if terrain_seeder.has_baked_region(cell):
			return terrain_seeder.baked_region_height(cell, world)
	if terrain != null and terrain.data != null:
		var h := float(terrain.data.get_height(world))
		if not is_nan(h):
			return h
	return _baker.natural_height_at(wx, wz)

## Region-anchored ground-height provider for a dressing node. The
## PropScatterer/Foliage contract hands the provider node-LOCAL XZ, so this
## translates by the region anchor and resolves through ground_height_at().
func _make_ground_provider(loc: Vector2i) -> Callable:
	var anchor := Vector2(float(loc.x) * region_size + region_size * 0.5, float(loc.y) * region_size + region_size * 0.5)
	return func(xz: Vector2) -> float:
		return ground_height_at(anchor.x + xz.x, anchor.y + xz.y)

## Foliage placement rule for a region (node-local XZ in): nothing above the
## treeline (rock and snow textures), nothing on beach sand, nothing inside a
## landmark clearing.
func _make_foliage_filter(loc: Vector2i) -> Callable:
	var anchor := Vector2(float(loc.x) * region_size + region_size * 0.5, float(loc.y) * region_size + region_size * 0.5)
	return func(xz: Vector2) -> bool:
		return foliage_allowed_at(anchor.x + xz.x, anchor.y + xz.y)

## Grass tuft rule for a region (node-local XZ in): see grass_allowed_at.
func _make_grass_filter(loc: Vector2i) -> Callable:
	var anchor := Vector2(float(loc.x) * region_size + region_size * 0.5, float(loc.y) * region_size + region_size * 0.5)
	return func(xz: Vector2) -> bool:
		return grass_allowed_at(anchor.x + xz.x, anchor.y + xz.y)

## Grass grows only where the baked ground texture is grass-family (grass,
## meadow, forest floor): the control map already encodes roads + gravel
## shoulders, rock, sand and snow, so one cached-texel read replaces a road
## query per tuft. Falls back to the tree rule plus the road check when the
## region has no cached control map.
func grass_allowed_at(wx: float, wz: float) -> bool:
	for zone: Vector3 in clear_zones:
		var dx := wx - zone.x
		var dz := wz - zone.y
		if dx * dx + dz * dz < zone.z * zone.z:
			return false
	if terrain_seeder != null:
		var cell := Vector2i(floori(wx / region_size), floori(wz / region_size))
		var bits := terrain_seeder.baked_region_control(cell, Vector3(wx, 0.0, wz))
		if bits >= 0:
			var base := TerrainTexturing.decode_base(bits)
			return base == TerrainTexturing.ID_GRASS or base == TerrainTexturing.ID_MEADOW or base == TerrainTexturing.ID_FOREST
	if not foliage_allowed_at(wx, wz):
		return false
	return road_network == null or PropScatterer.is_clear_of_road(Vector3(wx, 0.0, wz), road_network)

func foliage_allowed_at(wx: float, wz: float) -> bool:
	for zone: Vector3 in clear_zones:
		var dx := wx - zone.x
		var dz := wz - zone.y
		if dx * dx + dz * dz < zone.z * zone.z:
			return false
	var h := ground_height_at(wx, wz)
	if h >= TREELINE_HEIGHT:
		return false
	if TerrainBaker.coast_weight(wx, wz) * smoothstep(8.0, 3.0, h) > BEACH_WEIGHT_MAX:
		return false
	return true

## Gives every MultiMesh batch of a dressed region its draw distance (see
## GRASS/PROPS/TREES_DRAW_DISTANCE) with a short fade margin.
func _apply_draw_distances(node: Node3D) -> void:
	var props := node.get_node_or_null(PROPS_CHILD_NAME)
	if props != null:
		for child in props.get_children():
			_set_draw_distance(child as GeometryInstance3D, PROPS_DRAW_DISTANCE)
	var foliage := node.get_node_or_null(FOLIAGE_CHILD_NAME)
	if foliage != null:
		for child in foliage.get_children():
			var dist := GRASS_DRAW_DISTANCE if String(child.name) == "GrassMMI" else TREES_DRAW_DISTANCE
			_set_draw_distance(child as GeometryInstance3D, dist)

static func _set_draw_distance(gi: GeometryInstance3D, dist: float) -> void:
	if gi == null:
		return
	gi.visibility_range_end = dist
	# Hysteresis margin only; no dithered fade (it would push every batch through
	# the alpha-hash path for a pop that fog already hides at these distances).
	gi.visibility_range_end_margin = DRAW_FADE_MARGIN
	gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED