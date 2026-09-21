# scripts/world/traffic_driver.gd
class_name TrafficDriver
extends RefCounted

## Drives a spawned traffic vehicle along its road chain via input_override
## (the same seam as rivals). Pure value type: the spawner owns one per live
## vehicle, calls update() each tick, and drops the reference on despawn so
## this frees itself -- no Node lifecycle, no orphan risk.
##
## S6 additions: player-proximity slow/stop on the traffic-forward axis,
## a parked (never-drives) mode, and a stuck-teleport rescue that jumps a
## car that has not advanced 2 m in 5 s to a road point on its own chain.

## Arc distance in metres the driver aims at measured forward along the chain.
const LOOKAHEAD_DISTANCE := 18.0
## Cruise speed for traffic vehicles (no car-class grip: ambient traffic only).
const CRUISE_KMH := 55.0
## Corner sharpness scales cruise down this far (full lock -> fraction).
const CORNER_SPEED_RATIO := 0.45
## Held throttle at cruise so the override stays non-zero while tracking input
## (VehiclePhysics treats the exact Vector2.ZERO override as "player input").
const HOLD_THROTTLE := 0.12
## Dead band below/above corner-scaled cruise before throttle/brake kick in.
const SPEED_BAND_KMH := 6.0
## Overspeed in km/h that maps to full braking.
const BRAKE_RAMP_KMH := 15.0

## Player-proximity band: the traffic car starts tapering speed once the gap
## ahead of the player shrinks below SLOW_GAP metres, holds a full stop at
## STOP_GAP, and only rolls again after the gap reopens past RESUME_GAP
## (hysteresis so the stop never oscillates at the boundary).
const SLOW_GAP := 10.0
const STOP_GAP := 5.0
const RESUME_GAP := 12.0
## Brake hold while latched-stopped or parked (stays non-zero for the override).
const HOLD_BRAKE := 0.4
## Above this speed a proximity stop commands full brake; below it, the hold.
const HOLD_STOP_SPEED_KMH := 1.0

## Stuck-teleport rescue: no movement beyond STUCK_MOVE_M within STUCK_TIME_S
## seconds jumps the car to a random road point (seeded RNG, reproducible).
const STUCK_MOVE_M := 2.0
const STUCK_TIME_S := 5.0

var _car: VehiclePhysics = null
var _points: Array[Vector3] = []
var _closed := true
var _cruise_kmh := CRUISE_KMH
var _dir := 1
var _last_target := Vector3.ZERO
var _parked := false
var _suspended := false
var _stop_latched := false
var _rng := RandomNumberGenerator.new()
var _stuck_anchor := Vector3.ZERO
var _stuck_time := 0.0
var _rescue_count := 0

func configure(vehicle: VehiclePhysics, road_points: Array[Vector3], is_closed: bool = true, cruise_kmh: float = CRUISE_KMH) -> void:
	_car = vehicle
	_points = road_points.duplicate()
	_closed = is_closed
	_cruise_kmh = cruise_kmh
	_dir = 1
	_last_target = Vector3.ZERO
	_stop_latched = false
	_rescue_count = 0
	_stuck_time = 0.0
	_stuck_anchor = _car.global_position
	_rng.seed = _seed_from_points()

func update(player_pos: Vector3, delta: float = 1.0 / 60.0) -> void:
	if _car == null:
		return
	if _parked:
		# Static/drivable visual: never drive itself, never steer. Brake hold
		# keeps the override non-zero so VehiclePhysics stays AI-side.
		_car.set_input_override(Vector2(0.0, -HOLD_BRAKE))
		return
	if _points.size() < 2:
		# No usable chain: stay inert without falling back to player input.
		_car.set_input_override(Vector2(0.0, HOLD_THROTTLE))
		return

	var gap := _player_gap(player_pos)
	_update_stop_latch(gap)
	if not _suspended:
		_track_stuck(delta)

	_update_aim()
	var forward := -_car.global_basis.z
	var to_target := _last_target - _car.global_position
	to_target.y = 0.0
	var steer := 0.0
	if to_target.length() > 0.001:
		# Convergent law: positive steer = left turn, target on the left gives a
		# positive Y cross term (the negation used by AIController diverges).
		steer = clampf(forward.cross(to_target.normalized()).y, -1.0, 1.0)

	var corner_target := lerpf(_cruise_kmh, _cruise_kmh * CORNER_SPEED_RATIO, absf(steer))
	var diff := _car.current_speed_kmh - _effective_target(corner_target, gap)
	var longitudinal := HOLD_THROTTLE
	if _stop_latched:
		longitudinal = _stop_longitudinal(_car.current_speed_kmh)
	elif diff < -SPEED_BAND_KMH:
		longitudinal = 1.0
	elif diff > SPEED_BAND_KMH:
		longitudinal = -clampf((diff - SPEED_BAND_KMH) / BRAKE_RAMP_KMH, 0.0, 1.0)
	_car.set_input_override(Vector2(steer, longitudinal))

## Parked mode: the vehicle never moves on its own and stays a static, still
## drivable visual (collisions still behave normally).
func set_parked(value: bool) -> void:
	_parked = value
	if _parked and _car != null:
		_car.set_input_override(Vector2(0.0, -HOLD_BRAKE))

func is_parked() -> bool:
	return _parked

func set_suspended(value: bool) -> void:
	_suspended = value
	if _suspended and _car != null:
		_stuck_time = 0.0
		_stuck_anchor = _car.global_position

func is_suspended() -> bool:
	return _suspended

## Number of stuck-rescues carried out (test seam; also exposed for telemetry).
func get_rescue_count() -> int:
	return _rescue_count

func set_cruise_kmh(value: float) -> void:
	_cruise_kmh = value

func get_cruise_kmh() -> float:
	return _cruise_kmh

func get_target_waypoint() -> Vector3:
	return _last_target

## Pure position math on the affected axis (traffic-forward vs player): the
## signed distance along the car's forward from its nose to the player.
## Negative (player behind) means no influence at all -> INF.
func _player_gap(player_pos: Vector3) -> float:
	var forward := -_car.global_basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return INF
	var offset := player_pos - _car.global_position
	offset.y = 0.0
	var ahead := offset.dot(forward.normalized())
	if ahead < 0.0:
		return INF
	return ahead

## Hysteresis around the stop: latch when the gap collapses to STOP_GAP,
## release only once it reopens to RESUME_GAP.
func _update_stop_latch(gap: float) -> void:
	if gap <= STOP_GAP:
		_stop_latched = true
	elif gap >= RESUME_GAP:
		_stop_latched = false

## Blends corner-scaled cruise down as the gap shrinks inside the slow band
## and forces zero while the stop is latched.
func _effective_target(corner_target: float, gap: float) -> float:
	if _stop_latched:
		return 0.0
	if gap < SLOW_GAP:
		var frac := inverse_lerp(STOP_GAP, SLOW_GAP, gap)
		return corner_target * clampf(frac, 0.0, 1.0)
	return corner_target

## Full brake when still rolling; a gentle hold once effectively stopped.
func _stop_longitudinal(speed_kmh: float) -> float:
	if speed_kmh > HOLD_STOP_SPEED_KMH:
		return -1.0
	return -HOLD_BRAKE

## No movement over 2 m within 5 s => teleport to a random road point from the
## chain and reset the counters. A proximity stop is never mistaken for stuck.
func _track_stuck(delta: float) -> void:
	if _stop_latched:
		_stuck_anchor = _car.global_position
		_stuck_time = 0.0
		return
	if delta <= 0.0:
		return
	if _car.global_position.distance_to(_stuck_anchor) >= STUCK_MOVE_M:
		_stuck_anchor = _car.global_position
		_stuck_time = 0.0
		return
	_stuck_time += delta
	if _stuck_time >= STUCK_TIME_S:
		_rescue_from_stuck()

func _rescue_from_stuck() -> void:
	if _car == null or _points.is_empty():
		_stuck_time = 0.0
		return
	var target := _points[_rng.randi_range(0, _points.size() - 1)]
	_car.global_position = target
	_car.linear_velocity = Vector3.ZERO
	_car.angular_velocity = Vector3.ZERO
	_stuck_anchor = target
	_stuck_time = 0.0
	_rescue_count += 1

## Chain content hash so each driver picks from its own road deterministically
## across runs (reproducible in tests, varied across different roads).
func _seed_from_points() -> int:
	if _points.is_empty():
		return 7
	var h := hash(_points)
	if h == 0:
		return 7
	return h

func _nearest_index(pos: Vector3) -> int:
	var best := 0
	var best_dist := INF
	for i in _points.size():
		var d := _points[i].distance_to(pos)
		if d < best_dist:
			best_dist = d
			best = i
	return best

## Walks the chain forward from `start` accumulating arc length up to the
## lookahead target. Closed chains wrap; open chains clamp at the ends so the
## vehicle shuttles back and forth on connectors and dead-end ribbons.
func _lookahead_from(start: int, dir: int) -> Vector3:
	var travelled := 0.0
	var idx := start
	var guard := 0
	while guard < _points.size():
		var next := idx + dir
		if _closed:
			next = posmod(next, _points.size())
		elif next < 0 or next >= _points.size():
			break
		travelled += _points[idx].distance_to(_points[next])
		idx = next
		if travelled >= LOOKAHEAD_DISTANCE:
			break
		if not _closed and (idx == 0 or idx == _points.size() - 1):
			break
		guard += 1
	return _points[idx]

func _update_aim() -> void:
	var nearest := _nearest_index(_car.global_position)
	if not _closed:
		if nearest <= 0:
			_dir = 1
		elif nearest >= _points.size() - 1:
			_dir = -1
	_last_target = _lookahead_from(nearest, _dir)