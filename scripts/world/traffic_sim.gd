# scripts/world/traffic_sim.gd
class_name TrafficSim
extends RefCounted

## Pure ambient-traffic simulation on a LaneGraph (traffic plan sections 4 and 6).
## No nodes: TrafficManager feeds it the player state and the camera view each
## physics tick and mirrors the slots onto pooled bodies. Everything is 1-D per car
## (lane, s, v); positions come from the lane polyline, so a car cannot leave the
## road. Deterministic for a given seed and input sequence.
##
## v1 behaviour:
## - Spawn ring 140-280 m around the player on road lanes, never inside the camera
##   cone closer than 230 m, min gap 14 m + 0.5 s of lane speed to cars on the same
##   lane, nothing within 8 m of any car, nothing within 40 m of a spawn made in the
##   last 0.5 s, <= 4 spawns/s swept every 0.25 s, density-limited per tier.
## - Despawn beyond 330 m, or behind the player beyond 200 m while off-screen;
##   <= 4/s except past 380 m. A > 400 m player jump clears and ramps back over 3 s.
## - Longitudinal: IDM (a_max, b, s0 = 2.5 m, T) with the target speed = min(car v0,
##   lane speed profile, braking allowance for the next connector). Leaders: the
##   car ahead on the lane, through a planned connector into its target lane, and
##   the player (lane projection plus a straight corridor check). TTC < 1.5 s =>
##   emergency 8 m/s^2. A hard clamp keeps >= 0.5 m bumper gap to any leader.
## - Junctions: exits are taken with 30 % probability (a lane's last exit group on
##   an open lane is mandatory); connector entry waits (<= 4 s, then proceeds) while
##   another car is on a different connector of the same junction or the target
##   lane has no gap (highway 25 m ahead / 15 m behind, else 12 / 8).

const SPAWN_MIN := 140.0
const SPAWN_MAX := 280.0
const CONE_EXTRA_DEG := 12.0
const CONE_CLEAR_DIST := 230.0
const DESPAWN_FAR := 330.0
const DESPAWN_FORCE := 380.0
const DESPAWN_BEHIND := 200.0
const SWEEP_INTERVAL := 0.25
const GAP_MIN := 14.0
const GAP_TIME := 0.5
const SPAWN_CLEARANCE := 8.0
const RECENT_RADIUS := 40.0
const RECENT_TIME := 0.5
const SPAWN_RATE := 4.0
const DESPAWN_RATE := 4.0
const TELEPORT_JUMP := 400.0
const RAMP_TIME := 3.0
const SPAWN_TRIES := 8
const S0 := 2.5
const B_COMFORT := 2.5
const EMERGENCY_DECEL := 8.0
const MAX_DECEL := 9.0
const LOOKAHEAD := 120.0
const TTC_EMERGENCY := 1.5
const TURN_PROB := 0.3
const JUNCTION_WAIT_MAX := 4.0
const HOLD_DIST := 40.0
const MIN_BUMPER_GAP := 0.5
const PLAYER_HALF_LEN := 2.3
const PLAYER_HALF_WID := 1.0
const PLAYER_CORRIDOR := 45.0
const PLAYER_PROJECT_DIST := 3.5
const PLAYER_PROJECT_INTERVAL := 0.1
const MERGE_AHEAD_HWY := 25.0
const MERGE_BEHIND_HWY := 15.0
const MERGE_AHEAD := 12.0
const MERGE_BEHIND := 8.0
const DECLINE_STEP := 0.01

var graph: LaneGraph
var cap := 24
var master_seed := 20261023
var spawn_rate := SPAWN_RATE
## Multiplier on the per-tier density (night, weather, settings).
var density_scale := 1.0
## Tiers whose lanes get no spawns (RoadNetwork seasonal closures).
var closed_tiers: Dictionary = {}
## Optional (pos: Vector3) -> bool gate, e.g. "road cell streamed in".
var spawn_filter: Callable = Callable()
## Vehicle types: {half_len, half_wid, v0_factor, a_max, weights: {tier: w}, default_weight}.
var models: Array = [{"half_len": 2.3, "half_wid": 0.95, "v0_factor": 1.0, "a_max": 2.0, "weights": {}, "default_weight": 1.0}]

# --- Slots (struct of arrays) -----------------------------------------------------
var slot_count := 0
var active := PackedByteArray()
var car_lane := PackedInt32Array()
var car_s := PackedFloat32Array()
var car_v := PackedFloat32Array()
var car_a := PackedFloat32Array()
var car_v0f := PackedFloat32Array()
var car_T := PackedFloat32Array()
var car_amax := PackedFloat32Array()
var car_half_len := PackedFloat32Array()
var car_half_wid := PackedFloat32Array()
var car_model := PackedInt32Array()
var car_cursor := PackedInt32Array()
var car_exit_at := PackedFloat32Array()  # lane position of the decided exit group, -1 none
var car_exit_to := PackedInt32Array()  # connector chosen at that group, -1 = go straight on
var car_wait := PackedFloat32Array()
var car_uid := PackedInt32Array()
var car_braking := PackedByteArray()
var car_pos := PackedVector3Array()
var car_fwd := PackedVector3Array()
var car_up := PackedVector3Array()
var _car_rng: Array[RandomNumberGenerator] = []

## Slots spawned / despawned during the last step (consumers mirror these).
var spawned := PackedInt32Array()
var despawned := PackedInt32Array()
var time := 0.0
var player_lane := -1
var player_s := 0.0
var stats := {"spawns": 0, "despawns": 0, "rej_cone": 0, "rej_gap": 0, "rej_recent": 0, "rej_filter": 0, "rej_ring": 0, "holds": 0, "emergency": 0, "teleports": 0}
## Every spawn as [time, slot, lane, s] (determinism checks).
var spawn_log: Array = []
var keep_spawn_log := false

var _sweep_t := 0.0
var _sweep_index := 0
var _spawn_budget := 0.0
var _despawn_budget := 0.0
var _recent: Array = []  # [Vector3, time]
var _junction_occ: Dictionary = {}  # junction id -> PackedInt32Array of slots on its connectors
var _lane_cars: Dictionary = {}  # lane -> PackedInt32Array of slots (sorted by s)
var _last_player := Vector3.INF
var _ramp_start := -1000.0
var _uid_next := 1
var _proj_t := -1.0
var _rng := RandomNumberGenerator.new()
var _player_pos := Vector3.ZERO
var _player_vel := Vector3.ZERO
var _cand: Array = []
var _cand_cell := Vector2i(2147483647, 0)
var _cand_time := -100.0

func _init(lane_graph: LaneGraph = null, slots: int = 28, live_cap: int = 24) -> void:
	graph = lane_graph
	cap = live_cap
	_alloc(slots)

func _alloc(n: int) -> void:
	slot_count = n
	active.resize(n)
	car_braking.resize(n)
	car_lane.resize(n)
	car_s.resize(n)
	car_v.resize(n)
	car_a.resize(n)
	car_v0f.resize(n)
	car_T.resize(n)
	car_amax.resize(n)
	car_half_len.resize(n)
	car_half_wid.resize(n)
	car_model.resize(n)
	car_cursor.resize(n)
	car_exit_at.resize(n)
	car_exit_to.resize(n)
	car_wait.resize(n)
	car_uid.resize(n)
	car_pos.resize(n)
	car_fwd.resize(n)
	car_up.resize(n)
	_car_rng.clear()
	for i in n:
		active[i] = 0
		_car_rng.append(RandomNumberGenerator.new())

func live_count() -> int:
	var c := 0
	for i in slot_count:
		c += active[i]
	return c

func is_active(slot: int) -> bool:
	return active[slot] == 1

## World transform of a live car: nose +Z along the lane, up = road normal,
## origin on the lane surface.
func car_transform(slot: int) -> Transform3D:
	var z := car_fwd[slot]
	var y := car_up[slot]
	var x := y.cross(z)
	if x.length_squared() < 1e-8:
		x = Vector3.UP.cross(z)
	x = x.normalized()
	y = z.cross(x).normalized()
	return Transform3D(Basis(x, y, z), car_pos[slot])

# --- Public control --------------------------------------------------------------

func clear_all() -> void:
	for i in slot_count:
		if active[i] == 1:
			_despawn(i)

## Removes every car within `radius` (XZ) of `center` (fast travel, event starts).
func clear_area(center: Vector3, radius: float) -> void:
	for i in slot_count:
		if active[i] == 1 and _xz_dist(car_pos[i], center) <= radius:
			_despawn(i)

## Places a car directly (tests, debugging). Returns the slot or -1.
func place_car(lane: int, s: float, v: float = -1.0, model: int = 0) -> int:
	var slot := _free_slot()
	if slot < 0:
		return -1
	_activate(slot, lane, s, model, v)
	return slot

## One simulation step. `view` = {origin, forward, half_angle (rad, horizontal)}
## or {} when there is no camera (no cone rule).
func step(dt: float, player_pos: Vector3, player_vel: Vector3, view: Dictionary = {}) -> void:
	spawned.resize(0)
	despawned.resize(0)
	if graph == null or dt <= 0.0:
		return
	time += dt
	_player_pos = player_pos
	_player_vel = player_vel
	if _last_player != Vector3.INF and _xz_dist(player_pos, _last_player) > TELEPORT_JUMP:
		clear_all()
		_ramp_start = time
		_recent.clear()
		stats["teleports"] += 1
	_last_player = player_pos
	if time - _proj_t >= PLAYER_PROJECT_INTERVAL:
		_proj_t = time
		_project_player()
	_index_lanes()
	for i in slot_count:
		if active[i] == 1:
			_drive(i, dt)
	for i in slot_count:
		if active[i] == 1:
			_refresh_pose(i)
	_despawn_pass(dt, view)
	_sweep_t += dt
	_spawn_budget = minf(_spawn_budget + dt * spawn_rate, 2.0)
	if _sweep_t >= SWEEP_INTERVAL:
		_sweep_t = 0.0
		_spawn_sweep(view)

# --- Player ---------------------------------------------------------------------

func _project_player() -> void:
	var heading := _player_vel if _player_vel.length() > 2.0 else Vector3.ZERO
	var hit := graph.nearest_lane(_player_pos, PLAYER_PROJECT_DIST, heading)
	if hit.is_empty():
		player_lane = -1
		return
	player_lane = int(hit["lane"])
	player_s = float(hit["s"])

## Player projected as a leader of `slot`: [gap, speed] or [] (none).
func _player_leader(slot: int, path: Array) -> Array:
	if car_pos[slot].distance_squared_to(_player_pos) > (LOOKAHEAD + 20.0) * (LOOKAHEAD + 20.0):
		return []
	var best_gap := INF
	var best_v := 0.0
	var hl := car_half_len[slot]
	if player_lane >= 0:
		for step_info: Array in path:
			if int(step_info[0]) != player_lane:
				continue
			var base: float = step_info[1]
			var from_s: float = step_info[2]
			var ds := player_s - from_s
			if graph.lane_closed[player_lane] == 1 and ds < 0.0:
				ds += graph.lane_length[player_lane]
			if ds >= 0.0 and base + ds < LOOKAHEAD:
				var g := base + ds - hl - PLAYER_HALF_LEN
				if g < best_gap:
					best_gap = g
					best_v = maxf(0.0, _player_vel.dot(car_fwd[slot]))
	var d := _player_pos - car_pos[slot]
	var f := car_fwd[slot]
	var along := d.dot(f)
	if along > 0.0 and along < PLAYER_CORRIDOR and absf(d.y) < 4.0:
		var lat := d - f * along
		lat.y = 0.0
		if lat.length() < car_half_wid[slot] + PLAYER_HALF_WID + 0.4:
			var g := along - hl - PLAYER_HALF_LEN
			if g < best_gap:
				best_gap = g
				best_v = maxf(0.0, _player_vel.dot(f))
	if best_gap == INF:
		return []
	return [best_gap, best_v]

# --- Driving --------------------------------------------------------------------

func _index_lanes() -> void:
	_lane_cars.clear()
	for i in slot_count:
		if active[i] == 0:
			continue
		var l := car_lane[i]
		var arr: PackedInt32Array = _lane_cars.get(l, PackedInt32Array())
		arr.append(i)
		_lane_cars[l] = arr
	for l in _lane_cars:
		var arr: PackedInt32Array = _lane_cars[l]
		if arr.size() > 1:
			var list: Array = Array(arr)
			list.sort_custom(func(a: int, b: int) -> bool: return car_s[a] < car_s[b])
			_lane_cars[l] = PackedInt32Array(list)

## Distance along `lane` from a to b going forward (wraps on closed lanes, -1 if b
## is behind a on an open lane).
func _ahead_dist(lane: int, from_s: float, to_s: float) -> float:
	var ds := to_s - from_s
	if ds < 0.0:
		if graph.lane_closed[lane] == 1:
			ds += graph.lane_length[lane]
		else:
			return -1.0
	return ds

## Distance to the decided exit group, INF when none.
func _exit_dist(slot: int) -> float:
	if car_exit_at[slot] < 0.0:
		return INF
	var d := _ahead_dist(car_lane[slot], car_s[slot], car_exit_at[slot])
	return d if d >= 0.0 else INF

## Lanes the car will drive next: [[lane, base_dist, lane_s_at_base], ...]
func _path(slot: int) -> Array:
	var lane := car_lane[slot]
	var path: Array = [[lane, 0.0, car_s[slot]]]
	var ed := _exit_dist(slot)
	if graph.is_connector(lane):
		var rest := graph.lane_length[lane] - car_s[slot]
		path.append([graph.conn_to_lane[lane], rest, graph.conn_to_s[lane]])
	elif car_exit_to[slot] >= 0 and ed < LOOKAHEAD:
		var c := car_exit_to[slot]
		path.append([c, ed, 0.0])
		path.append([graph.conn_to_lane[c], ed + graph.lane_length[c], graph.conn_to_s[c]])
	return path

## Nearest car ahead along the path: [gap, speed] or [].
func _car_leader(slot: int, path: Array) -> Array:
	var hl := car_half_len[slot]
	for k in path.size():
		var step_info: Array = path[k]
		var lane: int = step_info[0]
		var base: float = step_info[1]
		var from_s: float = step_info[2]
		if base > LOOKAHEAD:
			break
		var limit := INF
		if k == 0 and path.size() > 1:
			limit = float(path[1][1])  # only up to where the path leaves this lane
		var best := INF
		var best_slot := -1
		var arr: PackedInt32Array = _lane_cars.get(lane, PackedInt32Array())
		for j in arr:
			if j == slot:
				continue
			var ds := _ahead_dist(lane, from_s, car_s[j])
			if ds < 0.0:
				continue
			if ds == 0.0 and car_uid[j] < car_uid[slot]:
				continue
			if base + ds > limit + car_half_len[j]:
				continue
			if ds < best:
				best = ds
				best_slot = j
		if best_slot >= 0:
			return [base + best - hl - car_half_len[best_slot], car_v[best_slot]]
	return []

## Virtual stopped leader at the exit when the junction or the merge is not free.
func _hold_leader(slot: int) -> Array:
	var c := car_exit_to[slot]
	if c < 0 or graph.is_connector(car_lane[slot]):
		return []
	var ed := _exit_dist(slot)
	if ed > HOLD_DIST or car_wait[slot] >= JUNCTION_WAIT_MAX:
		return []
	var blocked := false
	var j := graph.conn_junction[c]
	if j >= 0 and _junction_occ.has(j):
		for other in (_junction_occ[j] as PackedInt32Array):
			if other != slot and car_lane[other] != c:
				blocked = true
				break
	if not blocked:
		var m := graph.conn_to_lane[c]
		var to_s := graph.conn_to_s[c]
		var hwy := graph.lane_tier[m] == RoadDef.Tier.HIGHWAY
		var ahead := MERGE_AHEAD_HWY if hwy else MERGE_AHEAD
		var behind := MERGE_BEHIND_HWY if hwy else MERGE_BEHIND
		for other in (_lane_cars.get(m, PackedInt32Array()) as PackedInt32Array):
			var fwd := _ahead_dist(m, to_s, car_s[other])
			var back := _ahead_dist(m, car_s[other], to_s)
			if (fwd >= 0.0 and fwd < ahead) or (back >= 0.0 and back < behind):
				blocked = true
				break
	if not blocked:
		return []
	return [ed - car_half_len[slot] - 0.5, 0.0]

func _drive(slot: int, dt: float) -> void:
	var lane := car_lane[slot]
	var v := car_v[slot]
	car_cursor[slot] = graph.seek(lane, car_s[slot], car_cursor[slot])
	var v0 := graph.lane_limit[lane] * car_v0f[slot]
	var vt := minf(v0, graph.lane_vmax[lane][car_cursor[slot]])
	var ed := _exit_dist(slot)
	if car_exit_to[slot] >= 0 and ed < INF:
		var vc := graph.lane_vmax[car_exit_to[slot]][0]
		vt = minf(vt, sqrt(vc * vc + 2.0 * B_COMFORT * ed))
	vt = maxf(vt, 0.5)
	var path := _path(slot)
	var gap := INF
	var vl := 0.0
	var holding := false
	var hold := _hold_leader(slot)
	for cand: Array in [_car_leader(slot, path), _player_leader(slot, path), hold]:
		if cand.is_empty():
			continue
		if float(cand[0]) < gap:
			gap = float(cand[0])
			vl = float(cand[1])
	if not hold.is_empty() and float(hold[0]) <= gap + 1e-3:
		holding = true
	var amax := car_amax[slot]
	var r := v / vt
	var a := amax * (1.0 - r * r * r * r)
	car_braking[slot] = 0
	if gap < INF:
		var gg := maxf(gap, 0.1)
		var s_star := maxf(S0 + v * car_T[slot] + v * (v - vl) / (2.0 * sqrt(amax * B_COMFORT)), 0.0)
		a -= amax * (s_star / gg) * (s_star / gg)
		if v > vl + 0.1 and gap / (v - vl) < TTC_EMERGENCY:
			a = minf(a, -EMERGENCY_DECEL)
			stats["emergency"] += 1
	a = clampf(a, -MAX_DECEL, amax)
	if a < -1.0:
		car_braking[slot] = 1
	var nv := maxf(0.0, v + a * dt)
	var advance := nv * dt
	if gap < INF:
		var room := maxf(0.0, gap - MIN_BUMPER_GAP + maxf(0.0, vl - MAX_DECEL * dt) * dt)
		if advance > room:
			advance = room
			nv = minf(nv, vl)
	car_a[slot] = a
	car_v[slot] = nv
	if holding and nv < 0.5:
		car_wait[slot] += dt
		stats["holds"] += 1
	elif not holding:
		car_wait[slot] = 0.0
	_advance(slot, advance)

## Moves a car `ds` metres along its path, through exits and connectors.
func _advance(slot: int, ds: float) -> void:
	var guard := 0
	while ds > 0.0 and guard < 8:
		guard += 1
		var lane := car_lane[slot]
		if graph.is_connector(lane):
			var rest := graph.lane_length[lane] - car_s[slot]
			if ds < rest:
				car_s[slot] += ds
				return
			ds -= rest
			_leave_connector(slot)
			continue
		var ed := _exit_dist(slot)
		if ed <= ds:
			ds -= ed
			var at := car_exit_at[slot]
			if car_exit_to[slot] >= 0:
				_enter_connector(slot, car_exit_to[slot])
				continue
			# Declined: step just past the group and look at the next one.
			car_s[slot] = graph.wrap_s(lane, at + DECLINE_STEP)
			ds = maxf(0.0, ds - DECLINE_STEP)
			_decide_exit(slot, car_s[slot])
			continue
		var ns := car_s[slot] + ds
		var length := graph.lane_length[lane]
		if graph.lane_closed[lane] == 1:
			if ns >= length:
				ns -= length
			car_s[slot] = ns
			if car_exit_at[slot] < 0.0:
				_decide_exit(slot, ns)
		else:
			car_s[slot] = minf(ns, length)
			if ns >= length:
				# Open lane end with no exit left (should not happen: every open lane
				# ends in an exit group, see LaneGraph.has_end_successor).
				_despawn(slot)
		return
	if guard >= 8:
		return

func _enter_connector(slot: int, c: int) -> void:
	car_lane[slot] = c
	car_s[slot] = 0.0
	car_cursor[slot] = 0
	car_exit_at[slot] = -1.0
	car_exit_to[slot] = -1
	car_wait[slot] = 0.0
	var j := graph.conn_junction[c]
	if j >= 0:
		var occ: PackedInt32Array = _junction_occ.get(j, PackedInt32Array())
		if not occ.has(slot):
			occ.append(slot)
		_junction_occ[j] = occ

func _leave_connector(slot: int) -> void:
	var c := car_lane[slot]
	_release_junction(slot, graph.conn_junction[c])
	var m := graph.conn_to_lane[c]
	car_lane[slot] = m
	car_s[slot] = graph.conn_to_s[c]
	car_cursor[slot] = -1
	_decide_exit(slot, car_s[slot])

func _release_junction(slot: int, j: int) -> void:
	if j < 0 or not _junction_occ.has(j):
		return
	var occ: PackedInt32Array = _junction_occ[j]
	var k := occ.find(slot)
	if k >= 0:
		occ.remove_at(k)
	if occ.is_empty():
		_junction_occ.erase(j)
	else:
		_junction_occ[j] = occ

## Picks the next exit group at or ahead of `from_s` (wrapping on a loop) and
## rolls whether to take it.
func _decide_exit(slot: int, from_s: float) -> void:
	var lane := car_lane[slot]
	car_exit_at[slot] = -1.0
	car_exit_to[slot] = -1
	var es: PackedFloat32Array = graph.lane_exit_s[lane]
	if es.is_empty():
		return
	var closed := graph.lane_closed[lane] == 1
	var k := -1
	for i in es.size():
		if es[i] >= from_s:
			k = i
			break
	if k < 0:
		if not closed:
			return
		k = 0
	var at := es[k]
	var group := PackedInt32Array()
	var last_group := true
	for i in range(k, es.size()):
		if absf(es[i] - at) < 1e-3:
			group.append(graph.lane_exit_to[lane][i])
		else:
			last_group = false
			break
	var mandatory := not closed and last_group
	var rng := _car_rng[slot]
	car_exit_at[slot] = at
	if mandatory or rng.randf() < TURN_PROB:
		car_exit_to[slot] = group[rng.randi_range(0, group.size() - 1)]

func _refresh_pose(slot: int) -> void:
	var lane := car_lane[slot]
	var s := graph.wrap_s(lane, car_s[slot])
	var k := graph.seek(lane, s, car_cursor[slot])
	car_cursor[slot] = k
	var k1 := graph._seg_end_index(lane, k)
	var t := graph._seg_t(lane, k, s)
	var pts: PackedVector3Array = graph.lane_pts[lane]
	var fw: PackedVector3Array = graph.lane_fwd[lane]
	var up: PackedVector3Array = graph.lane_up[lane]
	car_pos[slot] = pts[k].lerp(pts[k1], t)
	var f := fw[k].lerp(fw[k1], t)
	car_fwd[slot] = f.normalized() if f.length_squared() > 1e-8 else fw[k]
	var u := up[k].lerp(up[k1], t)
	car_up[slot] = u.normalized() if u.length_squared() > 1e-8 else Vector3.UP

# --- Spawning -------------------------------------------------------------------

func _free_slot() -> int:
	for i in slot_count:
		if active[i] == 0:
			return i
	return -1

func _activate(slot: int, lane: int, s: float, model: int, v: float) -> void:
	var m: Dictionary = models[clampi(model, 0, models.size() - 1)]
	active[slot] = 1
	car_lane[slot] = lane
	car_s[slot] = graph.wrap_s(lane, s)
	car_model[slot] = model
	car_uid[slot] = _uid_next
	_uid_next += 1
	var rng := _car_rng[slot]
	rng.seed = hash([master_seed, car_uid[slot]])
	var factor := rng.randf_range(0.85, 1.05) * float(m.get("v0_factor", 1.0))
	var roll := rng.randf()
	if roll < 0.05:
		factor *= 0.8  # slow driver
	elif roll > 0.95:
		factor *= 1.1  # fast driver
	car_v0f[slot] = factor
	car_T[slot] = rng.randf_range(1.2, 1.8)
	car_amax[slot] = float(m.get("a_max", 2.0)) * rng.randf_range(0.85, 1.15)
	car_half_len[slot] = float(m.get("half_len", 2.3))
	car_half_wid[slot] = float(m.get("half_wid", 0.95))
	car_cursor[slot] = -1
	car_wait[slot] = 0.0
	car_braking[slot] = 0
	car_a[slot] = 0.0
	var vstart := minf(graph.lane_limit[lane] * factor, graph.vmax_at(lane, car_s[slot]))
	car_v[slot] = vstart if v < 0.0 else v
	_decide_exit(slot, car_s[slot])
	_refresh_pose(slot)
	spawned.append(slot)
	stats["spawns"] += 1
	if keep_spawn_log:
		spawn_log.append([snappedf(time, 0.001), slot, lane, snappedf(car_s[slot], 0.01)])

func _despawn(slot: int) -> void:
	if active[slot] == 0:
		return
	if graph.is_connector(car_lane[slot]):
		_release_junction(slot, graph.conn_junction[car_lane[slot]])
	active[slot] = 0
	car_v[slot] = 0.0
	despawned.append(slot)
	stats["despawns"] += 1

func in_view(pos: Vector3, view: Dictionary) -> bool:
	if view.is_empty():
		return false
	var o: Vector3 = view["origin"]
	var f: Vector3 = view["forward"]
	var to := Vector2(pos.x - o.x, pos.z - o.z)
	var fw := Vector2(f.x, f.z)
	if to.length_squared() < 1e-6 or fw.length_squared() < 1e-6:
		return true
	return absf(fw.angle_to(to)) < float(view["half_angle"]) + deg_to_rad(CONE_EXTRA_DEG)

func _heading_xz() -> Vector2:
	var h := Vector2(_player_vel.x, _player_vel.z)
	return h.normalized() if h.length() > 2.0 else Vector2.ZERO

func _despawn_pass(dt: float, view: Dictionary) -> void:
	_despawn_budget = minf(_despawn_budget + dt * DESPAWN_RATE, 4.0)
	var h := _heading_xz()
	if h == Vector2.ZERO and not view.is_empty():
		var f: Vector3 = view["forward"]
		h = Vector2(f.x, f.z).normalized()
	for i in slot_count:
		if active[i] == 0:
			continue
		var p := car_pos[i]
		var d := _xz_dist(p, _player_pos)
		if d > DESPAWN_FORCE:
			_despawn(i)
			continue
		if _despawn_budget < 1.0:
			continue
		var go := d > DESPAWN_FAR
		if not go and d > DESPAWN_BEHIND and h != Vector2.ZERO:
			var behind := Vector2(p.x - _player_pos.x, p.z - _player_pos.z).dot(h) < 0.0
			go = behind and not in_view(p, view)
		if go:
			_despawn(i)
			_despawn_budget -= 1.0

## Density-limited live target around the player (plan 3.3).
func _density_target(cand: Array) -> float:
	var total := 0.0
	for c: Array in cand:
		total += float(c[3])
	return total

func _spawn_sweep(view: Dictionary) -> void:
	_sweep_index += 1
	var i := 0
	while i < _recent.size():
		if time - float(_recent[i][1]) > RECENT_TIME:
			_recent.remove_at(i)
		else:
			i += 1
	var target := float(cap)
	if time - _ramp_start < RAMP_TIME:
		target *= clampf((time - _ramp_start) / RAMP_TIME, 0.0, 1.0)
	var live := live_count()
	if live >= int(target) or _spawn_budget < 1.0:
		return
	var pc := LaneGraph.cell_of(_player_pos)
	_rng.seed = hash([master_seed, pc, int(time / 10.0), _sweep_index])
	# Candidate runs only change with the player's 64 m cell (and closures).
	if pc != _cand_cell or time - _cand_time > 2.0:
		_cand = _candidate_runs(pc)
		_cand_cell = pc
		_cand_time = time
	var cand := _cand
	if cand.is_empty():
		return
	var dens := _density_target(cand) * density_scale
	target = minf(target, ceilf(dens))
	if live >= int(target):
		return
	var total_w := 0.0
	for c: Array in cand:
		total_w += float(c[3])
	while _spawn_budget >= 1.0 and live_count() < int(target):
		var placed := false
		for _t in SPAWN_TRIES:
			if _try_spawn(cand, total_w, view):
				placed = true
				break
		_spawn_budget -= 1.0
		if not placed:
			break

## Road-lane runs in cells overlapping the spawn annulus: [lane, seg_from, seg_to, weight].
func _candidate_runs(pc: Vector2i) -> Array:
	var out: Array = []
	var r := ceili(SPAWN_MAX / LaneGraph.CELL_SIZE) + 1
	var half_diag := LaneGraph.CELL_SIZE * 0.7072
	for cz in range(pc.y - r, pc.y + r + 1):
		for cx in range(pc.x - r, pc.x + r + 1):
			var key := Vector2i(cx, cz)
			if not graph.cells.has(key):
				continue
			var centre := Vector3((cx + 0.5) * LaneGraph.CELL_SIZE, 0.0, (cz + 0.5) * LaneGraph.CELL_SIZE)
			var d := _xz_dist(centre, _player_pos)
			if d < SPAWN_MIN - half_diag or d > SPAWN_MAX + half_diag:
				continue
			var runs: PackedInt32Array = graph.cells[key]
			for k in range(0, runs.size(), 3):
				var lane := runs[k]
				var dens := graph.lane_density[lane]
				if dens <= 0.0 or closed_tiers.has(graph.lane_tier[lane]):
					continue
				var segs := runs[k + 2] - runs[k + 1] + 1
				var w := float(segs) * LaneGraph.SAMPLE_SPACING * dens / 100.0
				out.append([lane, runs[k + 1], runs[k + 2], w])
	return out

func _try_spawn(cand: Array, total_w: float, view: Dictionary) -> bool:
	var pick := _rng.randf() * total_w
	var chosen: Array = cand[cand.size() - 1]
	for c: Array in cand:
		pick -= float(c[3])
		if pick <= 0.0:
			chosen = c
			break
	var lane: int = chosen[0]
	var seg := _rng.randi_range(int(chosen[1]), int(chosen[2]))
	var ss: PackedFloat32Array = graph.lane_s[lane]
	var s0 := ss[seg]
	var s1 := ss[seg + 1] if seg + 1 < ss.size() else graph.lane_length[lane]
	var s := lerpf(s0, s1, _rng.randf())
	if graph.lane_closed[lane] == 0:
		var es: PackedFloat32Array = graph.lane_exit_s[lane]
		if es.is_empty() or es[es.size() - 1] < s:
			stats["rej_ring"] += 1
			return false
	var pos := graph.position_at(lane, s)
	var d := _xz_dist(pos, _player_pos)
	if d < SPAWN_MIN or d > SPAWN_MAX:
		stats["rej_ring"] += 1
		return false
	# Prefer lanes ahead of the player's motion (60/40).
	var h := _heading_xz()
	if h != Vector2.ZERO and Vector2(pos.x - _player_pos.x, pos.z - _player_pos.z).dot(h) < 0.0 and _rng.randf() < 0.33:
		stats["rej_ring"] += 1
		return false
	if not view.is_empty() and in_view(pos, view) and _xz_dist(pos, view["origin"]) < CONE_CLEAR_DIST:
		stats["rej_cone"] += 1
		return false
	if spawn_filter.is_valid() and not bool(spawn_filter.call(pos)):
		stats["rej_filter"] += 1
		return false
	for r: Array in _recent:
		if (r[0] as Vector3).distance_to(pos) < RECENT_RADIUS:
			stats["rej_recent"] += 1
			return false
	var need := GAP_MIN + GAP_TIME * graph.lane_limit[lane]
	for j in slot_count:
		if active[j] == 0:
			continue
		if car_pos[j].distance_to(pos) < SPAWN_CLEARANCE:
			stats["rej_gap"] += 1
			return false
		if car_lane[j] == lane:
			var fwd := _ahead_dist(lane, s, car_s[j])
			var back := _ahead_dist(lane, car_s[j], s)
			if (fwd >= 0.0 and fwd < need) or (back >= 0.0 and back < need):
				stats["rej_gap"] += 1
				return false
	var slot := _free_slot()
	if slot < 0:
		return false
	_activate(slot, lane, s, _pick_model(graph.lane_tier[lane]), -1.0)
	# Do not start faster than a car close ahead on the same lane.
	for j in slot_count:
		if j != slot and active[j] == 1 and car_lane[j] == lane:
			var fwd := _ahead_dist(lane, s, car_s[j])
			if fwd >= 0.0 and fwd < 80.0:
				car_v[slot] = minf(car_v[slot], car_v[j])
	_recent.append([pos, time])
	return true

func _pick_model(tier: int) -> int:
	var total := 0.0
	for m: Dictionary in models:
		total += float((m.get("weights", {}) as Dictionary).get(tier, m.get("default_weight", 1.0)))
	if total <= 0.0:
		return 0
	var pick := _rng.randf() * total
	for k in models.size():
		var m: Dictionary = models[k]
		pick -= float((m.get("weights", {}) as Dictionary).get(tier, m.get("default_weight", 1.0)))
		if pick <= 0.0:
			return k
	return models.size() - 1

static func _xz_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
