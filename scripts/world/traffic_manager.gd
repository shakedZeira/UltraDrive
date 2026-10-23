# scripts/world/traffic_manager.gd
class_name TrafficManager
extends Node3D

## Pooled kinematic ambient traffic for the open world (traffic plan sections 4-5,
## 9). Owns the LaneGraph (built on a worker thread from the RoadNetwork's defs and
## junctions), a TrafficSim, and a fixed pool of AnimatableBody3D cars created once:
## spawning = show + place, despawning = hide; nothing is instantiated or freed while
## driving. One loop per physics tick, no per-car _physics_process.
##
## Tiers by distance to the player (10 m hysteresis):
##   N (< 70 m, nearest `near_cap`): collision on (layer 4 Traffic, mask 1 Vehicles).
##   M (70-250 m): collision off, transform every tick.
##   F (> 250 m): collision off, transform every FAR_UPDATE_EVERY ticks.
## Cars are one merged mesh each (TrafficModelCatalog), one draw call.
##
## Driven by TrafficSpawner (the scene's facade) only inside the open world; race
## tracks have no TrafficSpawner and no WorldDriver, so they never run this.

## Master switch. false = no lane traffic anywhere (TrafficSpawner stays legacy-free).
const ENABLED := true
## Live car cap / near-tier cap / main-thread budget (ms) per quality preset (plan 9).
const CAP_BY_QUALITY := {0: 14, 1: 24, 2: 36}
const NEAR_BY_QUALITY := {0: 4, 1: 8, 2: 10}
const BUDGET_MS_BY_QUALITY := {0: 0.8, 1: 1.2, 2: 2.0}
const POOL_EXTRA := 4
const NEAR_DIST := 70.0
const MID_DIST := 250.0
const TIER_HYST := 10.0
const FAR_UPDATE_EVERY := 6
const TRAFFIC_LAYER := 1 << 3
const TRAFFIC_MASK := 1
const TIER_NONE := 0
const TIER_NEAR := 1
const TIER_MID := 2
const TIER_FAR := 3
## Self-profiling guard window (ticks) and how long p95 may sit over budget.
const GUARD_WINDOW := 120
const GUARD_HOLD_S := 2.0
const VISIBLE_RANGE := 360.0

@export var road_network: RoadNetwork
## -1 = GameState.quality_preset.
@export var quality := -1
@export var master_seed := 20261023
## Scales the per-tier density (1 = plan table).
@export var density_scale := 1.0

var graph: LaneGraph
var sim: TrafficSim
var models: Array = []
## Explicit camera view for tests/probes ({origin, forward, half_angle}); empty =
## the viewport's current Camera3D.
var view_override: Dictionary = {}
var cap := 24
var near_cap := 8
var budget_ms := 1.2

var _cars: Array[AnimatableBody3D] = []
var _meshes: Array[MeshInstance3D] = []
var _shapes: Array[CollisionShape3D] = []
var _tier := PackedByteArray()
var _enabled := true
var _tick := 0
var _last_pos := Vector3.INF
var _task := -1
var _task_graph: LaneGraph = null
var _road_count := -1
var _usec := PackedInt32Array()
var _usec_i := 0
var _over_s := 0.0
var _guard_level := 0
var _night := false
var stats := {"tick_usec": 0, "p95_usec": 0, "max_usec": 0, "graph_ms": 0.0, "near": 0, "mid": 0, "far": 0, "guard": 0}

func _ready() -> void:
	_apply_quality()

func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

func _apply_quality() -> void:
	var q := quality if quality >= 0 else int(GameState.quality_preset)
	cap = int(CAP_BY_QUALITY.get(q, CAP_BY_QUALITY[1]))
	near_cap = int(NEAR_BY_QUALITY.get(q, NEAR_BY_QUALITY[1]))
	budget_ms = float(BUDGET_MS_BY_QUALITY.get(q, BUDGET_MS_BY_QUALITY[1]))
	if sim != null:
		sim.cap = cap

func is_ready() -> bool:
	return sim != null

func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled and sim != null:
		sim.clear_all()
		_mirror_events()

func is_enabled() -> bool:
	return _enabled

## Night flag from the weather layer (density x0.4 at night; no car lights in v1).
func sync_headlights(night: bool) -> void:
	_night = night

func clear_area(center: Vector3, radius: float) -> void:
	if sim != null:
		sim.clear_area(center, radius)
		_mirror_events()

func live_count() -> int:
	return sim.live_count() if sim != null else 0

func car_node(slot: int) -> AnimatableBody3D:
	return _cars[slot] if slot >= 0 and slot < _cars.size() else null

func tier_of(slot: int) -> int:
	return _tier[slot] if slot >= 0 and slot < _tier.size() else TIER_NONE

## Builds the graph synchronously (tests, probes). The game uses the worker path.
func build_now() -> void:
	var net := _network()
	if net == null:
		return
	_finish_graph(LaneGraph.build(net.get_road_defs(), net.get_junctions()))

func _network() -> RoadNetwork:
	if road_network == null and is_inside_tree():
		road_network = get_tree().get_first_node_in_group("road_network") as RoadNetwork
	return road_network

## Starts (or polls) the background graph build. True once the sim exists.
func _ensure_graph() -> bool:
	if sim != null:
		return true
	var net := _network()
	if net == null:
		return false
	if _task < 0:
		var defs := net.get_road_defs()
		if defs.is_empty():
			return false
		var junctions := net.get_junctions()
		_road_count = defs.size()
		_task = WorkerThreadPool.add_task(_build_task.bind(defs, junctions), false, "LaneGraph")
		return false
	if not WorkerThreadPool.is_task_completed(_task):
		return false
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_finish_graph(_task_graph)
	_task_graph = null
	return sim != null

func _build_task(defs: Array, junctions: Array) -> void:
	_task_graph = LaneGraph.build(defs, junctions)

func _finish_graph(g: LaneGraph) -> void:
	if g == null:
		return
	graph = g
	stats["graph_ms"] = g.build_usec / 1000.0
	if models.is_empty():
		models = TrafficModelCatalog.load_models()
	_build_pool(cap + POOL_EXTRA)
	sim = TrafficSim.new(graph, _cars.size(), cap)
	sim.master_seed = master_seed
	sim.models = TrafficModelCatalog.sim_models(models)
	var net := _network()
	if net != null and net.stream_geometry:
		sim.spawn_filter = func(pos: Vector3) -> bool: return net.is_cell_loaded(net.stream_cell_of(pos))
	if _road_count < 0 and net != null:
		_road_count = net.get_road_defs().size()

func _build_pool(n: int) -> void:
	if _cars.size() >= n:
		return
	for i in range(_cars.size(), n):
		var body := AnimatableBody3D.new()
		body.name = "TrafficCar%d" % i
		# Placed directly every tick. sync_to_physics would hand the car's velocity
		# to bodies it pushes, but a pooled body switched into it keeps a stale
		# physics transform (measured: near cars hundreds of metres off their lane),
		# and it lags one physics step. Contacts are resolved by depenetration; the
		# plan's crash-pool swap (5.3) is the proper fix for the hit feel.
		body.sync_to_physics = false
		body.collision_layer = 0
		body.collision_mask = 0
		body.visible = false
		var shape := CollisionShape3D.new()
		shape.shape = models[0]["shape"]
		body.add_child(shape)
		var mi := MeshInstance3D.new()
		mi.mesh = models[0]["mesh"]
		mi.visibility_range_end = VISIBLE_RANGE
		body.add_child(mi)
		add_child(body)
		body.global_position = Vector3(0.0, -10000.0 - float(i) * 10.0, 0.0)
		_cars.append(body)
		_meshes.append(mi)
		_shapes.append(shape)
	_tier.resize(n)

## One traffic tick (called from TrafficSpawner.update in the physics step).
func update(player_pos: Vector3, delta: float) -> void:
	if not ENABLED or not _enabled:
		return
	if not _ensure_graph():
		return
	var t0 := Time.get_ticks_usec()
	_tick += 1
	var vel := Vector3.ZERO
	if _last_pos != Vector3.INF and delta > 0.0:
		vel = (player_pos - _last_pos) / delta
	_last_pos = player_pos
	if _tick % 60 == 1:
		_refresh_context()
	sim.step(delta, player_pos, vel, _view())
	_mirror_events()
	_update_tiers(player_pos)
	_write_transforms()
	_guard(Time.get_ticks_usec() - t0, delta)

func _refresh_context() -> void:
	var net := _network()
	if net != null:
		var closed := {}
		for t in net.get_closed_tiers():
			closed[t] = true
		sim.closed_tiers = closed
	var scale := density_scale
	if _night:
		scale *= 0.4
	if WeatherManager.current_weather == WeatherManager.Weather.STORM:
		scale *= 0.6
	sim.density_scale = scale

func _view() -> Dictionary:
	if not view_override.is_empty():
		return view_override
	var vp := get_viewport()
	if vp == null:
		return {}
	var cam := vp.get_camera_3d()
	if cam == null:
		return {}
	var size := vp.get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var half_v := deg_to_rad(cam.fov) * 0.5
	var half_h := atan(tan(half_v) * aspect)
	return {"origin": cam.global_position, "forward": -cam.global_basis.z, "half_angle": half_h}

func _mirror_events() -> void:
	for slot in sim.despawned:
		var body := _cars[slot]
		body.visible = false
		body.collision_layer = 0
		body.collision_mask = 0
		_tier[slot] = TIER_NONE
	for slot in sim.spawned:
		var m: Dictionary = models[clampi(sim.car_model[slot], 0, models.size() - 1)]
		_meshes[slot].mesh = m["mesh"]
		_shapes[slot].shape = m["shape"]
		_shapes[slot].position = Vector3(0.0, float(m["height"]) * 0.5, 0.0)
		var body := _cars[slot]
		body.global_transform = sim.car_transform(slot)
		body.visible = true
		_tier[slot] = TIER_MID
	sim.spawned.resize(0)
	sim.despawned.resize(0)

func _update_tiers(player_pos: Vector3) -> void:
	var near_list: Array = []
	var counts := [0, 0, 0, 0]
	for i in sim.slot_count:
		if sim.active[i] == 0:
			continue
		var d := TrafficSim._xz_dist(sim.car_pos[i], player_pos)
		var t := int(_tier[i])
		var near_lim := NEAR_DIST + (TIER_HYST if t == TIER_NEAR else 0.0)
		var far_lim := MID_DIST + (0.0 if t == TIER_FAR else TIER_HYST)
		if d < near_lim:
			near_list.append([d, i])
			t = TIER_MID
		elif d > far_lim:
			t = TIER_FAR
		else:
			t = TIER_MID
		_tier[i] = t
	near_list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var allowed := near_cap if _guard_level == 0 else maxi(int(near_cap * 0.5), 2)
	for k in near_list.size():
		var i: int = near_list[k][1]
		if k < allowed:
			_tier[i] = TIER_NEAR
	for i in sim.slot_count:
		if sim.active[i] == 0:
			continue
		var t := int(_tier[i])
		counts[t] += 1
		var body := _cars[i]
		var want_layer := TRAFFIC_LAYER if t == TIER_NEAR else 0
		if body.collision_layer != want_layer:
			body.collision_layer = want_layer
			body.collision_mask = TRAFFIC_MASK if t == TIER_NEAR else 0
	stats["near"] = counts[TIER_NEAR]
	stats["mid"] = counts[TIER_MID]
	stats["far"] = counts[TIER_FAR]

func _write_transforms() -> void:
	for i in sim.slot_count:
		if sim.active[i] == 0:
			continue
		if _tier[i] == TIER_FAR and (_tick + i) % FAR_UPDATE_EVERY != 0:
			continue
		_cars[i].global_transform = sim.car_transform(i)

## Measures its own tick; when p95 over the last GUARD_WINDOW ticks stays above the
## budget for GUARD_HOLD_S, halves the spawn rate and the near-tier count (plan 9).
func _guard(usec: int, delta: float) -> void:
	if _usec.size() < GUARD_WINDOW:
		_usec.resize(GUARD_WINDOW)
	_usec[_usec_i] = usec
	_usec_i = (_usec_i + 1) % GUARD_WINDOW
	stats["tick_usec"] = usec
	stats["max_usec"] = maxi(int(stats["max_usec"]), usec)
	if _tick % 30 != 0:
		return
	var sorted := _usec.duplicate()
	sorted.sort()
	var p95 := sorted[int(sorted.size() * 0.95)]
	stats["p95_usec"] = p95
	if float(p95) / 1000.0 > budget_ms:
		_over_s += delta * 30.0
	else:
		_over_s = 0.0
	var level := 1 if _over_s >= GUARD_HOLD_S else 0
	if level != _guard_level:
		_guard_level = level
		sim.spawn_rate = TrafficSim.SPAWN_RATE * (0.5 if level > 0 else 1.0)
		stats["guard"] = level
