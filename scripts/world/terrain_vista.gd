# scripts/world/terrain_vista.gd
class_name TerrainVista
extends Node3D

## Static far terrain past the live 3x3 ring (docs/plans/terrain_vista_plan.md).
## Owns a second Terrain3D node: 3x3 regions of 1024 px at 8 m per vertex
## (x/z [-8192, 16384)), no collision, no shadows, the same ground textures and
## lightweight shader as the live terrain. Built once per load, never streamed.
##
## start(roads, player_pos) launches one coordinator Thread. For each region,
## nearest to the player first, it runs TerrainVistaBaker's height/colour bands
## and then its control bands on WorkerThreadPool (pool_tasks at a time), joins
## them into Terrain3D images and queues the record.
##
## Main thread: start() adds all nine regions blank at once (flat at y = 0,
## like the live terrain's old background) and switches the live terrain's
## world background to NONE, so the live mesh ends at its last region. Adding
## a region later would make Terrain3D re-create its whole map texture arrays
## (measured 43-82 ms per region); with the region set fixed, each map write
## only updates its own layer. _process writes one map per frame
## (MAX_STEPS_PER_FRAME): height, then colour, then control. The height
## image is handed to its region on the coordinator thread, because
## Terrain3DRegion.set_map(TYPE_HEIGHT) scans the whole image (19-28 ms for
## 1024^2 on the main thread); nothing reads a vista region's CPU images
## meanwhile (no collision, no height queries, region not marked edited).
##
## Vista heights sit TerrainVistaBaker.BIAS below the live field, so wherever
## the ring is loaded the ring wins the depth test.

const MAX_STEPS_PER_FRAME := 1
const STEP_HEIGHT := 0
const STEP_COLOR := 1
const STEP_CONTROL := 2
const VERTEX_SPACING := 8.0

@export var live_terrain: Terrain3D
@export var pool_tasks: int = 3
## Headless runs (tests, tools) skip the bake unless this is set.
@export var bake_in_headless: bool = false

var terrain: Terrain3D
var applied_count: int = 0
var apply_frames: int = 0
var max_steps_per_frame: int = 0
var max_step_ms: float = 0.0
var step_max_ms := PackedFloat32Array([0.0, 0.0, 0.0])
var setup_ms: float = 0.0
var apply_order: Array[Vector2i] = []
var bake_ms: Dictionary = {}
var apply_ms: Dictionary = {}

var _baker := TerrainVistaBaker.new()
var _thread: Thread
var _lock := Mutex.new()
var _ready_records: Array = []
var _current: Dictionary = {}
var _regions: Dictionary = {}
var _step := 0
var _exit := false
var _started := false
var _expected := 0
var _order: Array[Vector2i] = []
var _roads: Array = []
var _job_loc := Vector2i.ZERO
var _job_chains: Array[PackedVector3Array] = []
var _job_heights := PackedFloat32Array()
var _job_edge := PackedByteArray()
var _job_bands: Array = []
var _job_controls: Array = []
var _start_ms := 0
var _done_ms := -1

func _ready() -> void:
	if live_terrain == null:
		live_terrain = get_node_or_null("../Terrain3D") as Terrain3D
	set_process(false)

func _exit_tree() -> void:
	stop()

## True when this run should bake at all (headless runs opt in).
func is_enabled() -> bool:
	return bake_in_headless or DisplayServer.get_name() != "headless"

## Creates the static Terrain3D and starts the background build. roads: the
## centreline arrays the seeder carves with (RoadNetwork.get_roads()). locs
## defaults to all nine regions; tests pass a subset.
func start(roads: Array, player_pos: Vector3, locs: Array[Vector2i] = []) -> bool:
	if _started or not is_enabled():
		return false
	_started = true
	_roads = roads
	_make_terrain()
	var order := TerrainVistaBaker.order_locs(Vector2(player_pos.x, player_pos.z))
	if not locs.is_empty():
		order = order.filter(func(l: Vector2i) -> bool: return locs.has(l))
	_order = order
	_expected = _order.size()
	_start_ms = Time.get_ticks_msec()
	_add_blank_regions()
	_thread = Thread.new()
	_thread.start(_build_all, Thread.PRIORITY_LOW)
	set_process(true)
	return true

## All requested regions are applied.
func is_complete() -> bool:
	return _started and applied_count >= _expected

func stats() -> Dictionary:
	return {"applied": applied_count, "expected": _expected, "order": apply_order, "bake_ms": bake_ms, "apply_ms": apply_ms, "max_step_ms": max_step_ms, "step_max_ms": step_max_ms, "setup_ms": setup_ms, "total_ms": _done_ms}

func stop() -> void:
	_exit = true
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null

func _make_terrain() -> void:
	terrain = Terrain3D.new()
	terrain.name = "VistaTerrain3D"
	add_child(terrain)
	terrain.collision_mode = 0
	terrain.cast_shadows = 0
	terrain.region_size = Terrain3D.SIZE_1024
	terrain.vertex_spacing = VERTEX_SPACING
	terrain.show_checkered = false
	terrain.show_colormap = false
	var shared: Terrain3DAssets = live_terrain.assets if live_terrain != null else null
	TerrainTexturing.apply(terrain, TerrainTexturing.QUALITY_LITE, shared)
	if terrain.material != null:
		terrain.material.world_background = Terrain3DMaterial.WorldBackground.NONE

func _build_all() -> void:
	for loc in _order:
		if _exit:
			return
		var t0 := Time.get_ticks_msec()
		var record := _build_region(loc)
		if record.is_empty():
			return
		record["loc"] = loc
		var region: Terrain3DRegion = _regions.get(loc)
		if region != null:
			region.set_map(Terrain3DRegion.TYPE_HEIGHT, record["height"])
		record["bake_ms"] = Time.get_ticks_msec() - t0
		_lock.lock()
		_ready_records.append(record)
		_lock.unlock()

func _build_region(loc: Vector2i) -> Dictionary:
	_job_loc = loc
	_job_chains = TerrainVistaBaker.region_chains(_roads, loc)
	_job_bands = []
	_job_bands.resize(TerrainVistaBaker.BAND_COUNT)
	var gid := WorkerThreadPool.add_group_task(_height_band, TerrainVistaBaker.BAND_COUNT, maxi(pool_tasks, 1), false, "vista_height")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	if _exit:
		return {}
	_job_heights = TerrainVistaBaker.join_heights(_job_bands)
	_job_edge = TerrainVistaBaker.join_edges(_job_bands)
	var color := TerrainVistaBaker.join_colors(_job_bands)
	_job_bands = []
	_job_controls = []
	_job_controls.resize(TerrainVistaBaker.BAND_COUNT)
	gid = WorkerThreadPool.add_group_task(_control_band, TerrainVistaBaker.BAND_COUNT, maxi(pool_tasks, 1), false, "vista_control")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	if _exit:
		return {}
	var record := TerrainVistaBaker.make_images(_job_controls, color)
	_job_controls = []
	_job_heights = PackedFloat32Array()
	_job_edge = PackedByteArray()
	return record

func _height_band(band: int) -> void:
	if _exit:
		return
	var out := _baker.bake_band(_job_loc, band, _job_chains)
	_lock.lock()
	_job_bands[band] = out
	_lock.unlock()

func _control_band(band: int) -> void:
	if _exit:
		return
	var out: Dictionary = _baker.bake_control_band(_job_loc, band, _job_heights, _job_edge)
	_lock.lock()
	_job_controls[band] = out
	_lock.unlock()

func _add_blank_regions() -> void:
	var t0 := Time.get_ticks_usec()
	var data: Terrain3DData = terrain.data
	if data != null:
		for loc in _order:
			_regions[loc] = data.add_region_blankp(TerrainVistaBaker.region_center(loc), false)
		data.update_maps()
	if live_terrain != null and live_terrain.material != null:
		live_terrain.material.world_background = Terrain3DMaterial.WorldBackground.NONE
	setup_ms = float(Time.get_ticks_usec() - t0) / 1000.0

func _process(_delta: float) -> void:
	var n := 0
	while n < MAX_STEPS_PER_FRAME:
		if _current.is_empty():
			_lock.lock()
			_current = _ready_records.pop_front() if not _ready_records.is_empty() else {}
			_lock.unlock()
			_step = STEP_HEIGHT
			if _current.is_empty():
				break
		_apply_step()
		n += 1
	if n > 0:
		apply_frames += 1
		max_steps_per_frame = maxi(max_steps_per_frame, n)
	if is_complete():
		if _done_ms < 0:
			_done_ms = Time.get_ticks_msec() - _start_ms
		set_process(false)
		if _thread != null and _thread.is_started():
			_thread.wait_to_finish()
			_thread = null

## Writes one map of the current record into its (already added) region and
## updates only that region's layer.
func _apply_step() -> void:
	var t0 := Time.get_ticks_usec()
	var loc: Vector2i = _current["loc"]
	var data: Terrain3DData = terrain.data
	var region: Terrain3DRegion = data.get_regionp(TerrainVistaBaker.region_center(loc)) if data != null else null
	if region == null:
		push_warning("TerrainVista: region %s missing" % loc)
		_current = {}
		return
	region.set_edited(true)
	match _step:
		STEP_HEIGHT:
			region.update_height(_current["height_min"])
			region.update_height(_current["height_max"])
			data.update_maps(Terrain3DRegion.TYPE_HEIGHT, false)
		STEP_COLOR:
			region.set_map(Terrain3DRegion.TYPE_COLOR, _current["color"])
			data.update_maps(Terrain3DRegion.TYPE_COLOR, false)
		STEP_CONTROL:
			region.set_map(Terrain3DRegion.TYPE_CONTROL, _current["control"])
			data.update_maps(Terrain3DRegion.TYPE_CONTROL, false)
	region.set_edited(false)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	max_step_ms = maxf(max_step_ms, ms)
	step_max_ms[_step] = maxf(step_max_ms[_step], ms)
	apply_ms[loc] = float(apply_ms.get(loc, 0.0)) + ms
	_step += 1
	if _step > STEP_CONTROL:
		applied_count += 1
		apply_order.append(loc)
		bake_ms[loc] = _current.get("bake_ms", 0)
		_current = {}
