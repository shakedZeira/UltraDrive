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

var _player_region := Vector2i(1 << 30, 1 << 30)
## loc (Vector2i) -> {"band": int, "node": Node3D}. The dressed set mirrored to
## the live ring + prefetch band around the player.
var _dressed: Dictionary = {}
var _spawn_queue: Array = []
var _band_queue: Array = []
var _free_queue: Array = []

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
	var desired := {}
	for dx in range(-prefetch_band_radius, prefetch_band_radius + 1):
		for dz in range(-prefetch_band_radius, prefetch_band_radius + 1):
			var loc := new_region + Vector2i(dx, dz)
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
	while not _spawn_queue.is_empty() and dresses < max_dresses_per_frame:
		var job: Dictionary = _spawn_queue.pop_front()
		_spawn_region(job)
		dresses += 1

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
func _spawn_region(job: Dictionary) -> void:
	var loc: Vector2i = job["loc"]
	var band: int = int(job["band"])
	if band != BAND_LIVE and band != BAND_PREFETCH:
		band = _band_for(loc, _player_region)
	if _dressed.has(loc):
		return
	var seed: int = region_seed(master_seed, loc)
	var zone: String = region_zone(master_seed, loc)
	var preset: Dictionary = PropScatterer.default_preset(zone)
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
	foliage.configure_for_region(loc, seed, density)
	foliage.ground_height_provider = _make_ground_provider(loc)
	foliage.road_network = road_network
	node.add_child(foliage)
	_apply_band_budget(props, foliage, band)
	_dressed[loc] = {"band": band, "node": node}
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
	entry["band"] = band
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

## Deterministic dressing zone for a region (one of PropScatterer's
## default_preset zones: festival / lowlands / coast / highlands / alpine).
## Pure function of (master_seed, loc): near-spawn regions run festival /
## lowlands, mid-distance lowlands/coast, far highlands/alpine -- with a
## seeded roll breaking ties so a single master_seed maps the whole world.
static func region_zone(master: int, loc: Vector2i) -> String:
	var roll := absi(region_seed(master, loc) % 100)
	var world := Vector2(float(loc.x) * REGION_CELL + REGION_CELL * 0.5, float(loc.y) * REGION_CELL + REGION_CELL * 0.5)
	var dist := world.distance_to(TerrainBaker.BIOME_SPAWN_CENTER)
	if dist < 2500.0:
		return "festival" if roll < 40 else "lowlands"
	if dist < 6000.0:
		return "lowlands" if roll < 55 else "coast"
	if dist < 10000.0:
		return "highlands" if roll < 60 else "coast"
	return "alpine" if roll < 85 else "highlands"

## Region-anchored ground-height provider for a dressing node. The
## PropScatterer/Foliage contract hands the provider node-LOCAL XZ, so this
## translates by the region anchor, prefers the seeder's baked cache (the
## prefetch ring keeps it warm before a region goes live), then the live
## Terrain3D, then flat Y0. Main thread only -- the dresser never touches
## Terrain3D or the bake cache off the main thread.
func _make_ground_provider(loc: Vector2i) -> Callable:
	var anchor := Vector3(float(loc.x) * region_size + region_size * 0.5, 0.0, float(loc.y) * region_size + region_size * 0.5)
	var seeder: TerrainSeeder = terrain_seeder
	var terrain_src: Terrain3D = terrain
	return func(xz: Vector2) -> float:
		var world := Vector3(anchor.x + xz.x, 0.0, anchor.z + xz.y)
		if seeder != null:
			return seeder.baked_region_height(loc, world)
		if terrain_src != null and terrain_src.data != null:
			return float(terrain_src.data.get_height(world))
		return 0.0