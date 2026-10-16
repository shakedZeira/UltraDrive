# scripts/ai/ai_controller.gd
class_name AIController
extends Node

## Drives a VehiclePhysics car along waypoints.
## Attach as sibling of VehiclePhysics.
##
## Steering is a wrap-safe pure-pursuit tracker: it aims at an arc-length
## lookahead point measured FORWARD from the waypoint nearest the car, so a car
## that has spun, fallen behind, or drifted off the line steers back onto it
## instead of chasing a stale index. (The old version chased one index that only
## ever advanced when the car reached it; a spun car faced a bearing past 90
## degrees, the sine-based steer saturated, and the brake-when-turning rule then
## pinned it to a permanent stop.)
##
## Longitudinal control adds bounded curvature-lookahead braking (never at
## creep speed) and a light, no-teleport stuck recovery that floors the throttle
## and tightens the aim point when the car genuinely stops making progress.

@onready var car: VehiclePhysics = get_parent() as VehiclePhysics

## Waypoint index the driver is currently seeking. Still advances with the
## capture radius (not the pure-pursuit aim point) so the stall signal, tests
## and any external readers keep a stable "next waypoint" meaning.
var waypoints: Array[Vector3] = []
var _current_target: int = 0
var _speed_multiplier: float = 1.0

# --- Pure-pursuit / recovery state ---
var _smooth_steer: float = 0.0
var _mean_spacing: float = 3.0
var _ever_moved: bool = false
var _first_nearest: int = -1
var _last_progress_index: int = -1
var _stall_seconds: float = 0.0
var _resought: bool = false
var _recovering: bool = false
var _corner_braking: bool = false

## Distance (m) at which the current waypoint index is considered captured and
## the driver advances to the next one. Progression signal for the stall check.
const CAPTURE_RADIUS := 8.0

# --- Steering ---
## Arc-length lookahead window shrinks toward this at a standstill so the aim
## point is always ahead of the nose.
const LOOKAHEAD_MIN_M := 7.0
## and grows with speed up to here (a longer lookahead damps the wheel at speed:
## the old 28 m cap at a 0.6 s time-constant was short enough that a car at
## ~70 km/h chased a point only ~11 m ahead, whose bearing swings violently as
## the body yaws -> a limit-cycle weave that periodically snapped into a spin).
const LOOKAHEAD_MAX_M := 34.0
## Lookahead arc = clamp(speed * this, LOOKAHEAD_MIN_M, LOOKAHEAD_MAX_M). Raised
## from 0.6 so the aim point sits ~0.85 s of travel ahead: gentler bearing for a
## given lateral offset, which is what damps the high-speed weave.
const LOOKAHEAD_SPEED_GAIN := 0.85
## Bearing at which the steer command saturates. PI/3 (60 deg) removes the
## 180-degree dead spot a fully spun car hits while staying near the old
## sin(bearing) response below 90 degrees.
const STEER_BEARING_SAT := PI / 3.0
## Bearing dead band: below this the wheel is centred (kills straight-line jitter).
const STEER_DEADBAND := 0.04
## Max change in steer command per second (slew limit -> smoother, less twitchy).
const STEER_SLEW_PER_S := 4.0
## Weight of the nose-vs-tangent heading error folded into the pure-pursuit
## bearing (rad of steer command per rad of heading error). Pure pursuit tracks a
## POINT: a car whose nose is already turned toward the line while its position
## is still beside it sees the bearing cancel to ~0, so it keeps the throttle on
## and keeps steering at nothing while the body yaws away -- the measured
## 7 -> 52 -> 114 degree weave that spun a rival out after a kerb strike. Feeding
## the heading error back in keeps steering until the car is ALIGNED with the
## line, not merely pointing at the aim point, which is what makes the two terms
## agree instead of fight (both are signed nose-to-path angles, near and far).
const HEADING_STEER_GAIN := 0.6

# --- Longitudinal ---
## Throttle cut per unit of |steer| while cornering or settling. Kept moderate
## on purpose: a hard cut (0.7) yanked the throttle off exactly during a
## high-speed correction, unloading the rear and snapping the car into lift-off
## oversteer (that is the 50->102->179 degree spin in the drive probe).
const STEER_THROTTLE_CUT := 0.4
## Throttle ceiling applied whenever a corner is within the curvature lookahead.
## Entering a turn on heavy throttle consumes the rear tyres' friction circle, so
## the AI pushes wide and can spin; the fastest tier (Expert, pace 0.66) hit this
## hard at the banked R=60 turn while the slower Novice (0.44) was already under
## the cap and handled it. Capping the corner throttle makes every tier enter on
## the corner-speed target instead of its tier pace — slow in, fast out.
const CORNER_THROTTLE_CEIL := 0.45
## Deeper cut applied while the car is genuinely stalled (no progress ~1 s).
const STALL_THROTTLE_CUT := 0.4
## Deeper still while recovering from a stuck stop.
const RECOVER_THROTTLE_CUT := 0.2
## Cornering acceleration budget (m/s^2) for the curvature lookahead target.
## Set with MARGIN on purpose: the measured rivals entered the track's R=60
## corner at 71-77 km/h against the old 7.0 budget's 73.8 km/h target, i.e.
## ~0.71 g with no reserve, and intermittently lost grip and spun (then wedged,
## having no reverse). 5.0 gives ~62 km/h through that corner (~0.51 g) so the
## cars brake for it instead of arriving at the limit.
const CORNER_LAT_ACCEL := 4.5
## Corner curvature is sampled this far ahead, scaled by speed.
const CORNER_LOOKAHEAD_MIN_M := 16.0
const CORNER_LOOKAHEAD_MAX_M := 60.0
const CORNER_LOOKAHEAD_GAIN := 1.5
## Hysteresis band (m/s) around the corner speed target so braking does not chatter.
const CORNER_SPEED_BAND_MPS := 1.0
## Overspeed (m/s) that maps to full braking once the band is exceeded.
const CORNER_BRAKE_RAMP_MPS := 4.0
## Braking is never commanded below this speed, so a slow/stopped car is not
## braked into a permanent stop.
const LOW_SPEED_BRAKE_FLOOR_MPS := 6.0
## Heading error (rad) at which the throttle starts being cut, and the error at
## which the cut is total (0.42 rad ~ 24 deg, 1.05 rad ~ 60 deg). Past the start
## the car is no longer tracking the line, and staying on the throttle loads the
## rear mid-correction and turns a spurious perturbation (a kerb strike, a nudge)
## into a spin: the probe shows the rival holding thr 0.66 while its heading error
## ran 7 -> 52 -> 114 degrees. Easing off lets it settle first. Never applied
## while recovering, where pulling the car out of a stop matters more.
const YAW_THROTTLE_CUT_START_RAD := 0.42
const YAW_THROTTLE_CUT_FULL_RAD := 1.05

# --- Stall / stuck detection ---
## No forward centreline progress for this long => re-seek the target FORWARD
## along the centreline (never at the player) and cut throttle.
const STALL_SECONDS := 1.6
## Only cars that have actually moved can be treated as stalled / recovering, so
## a car waiting on the grid is never "rescued" before the lights go out.
const STUCK_SPEED_MS := 3.0
## Stalled this long while near-stationary => latch the stuck recovery.
const STUCK_SECONDS := 1.6
## Throttle floor applied (post-pace) while recovering, so a stopped car pulls
## itself out without a teleport.
const RECOVER_THROTTLE_FLOOR := 0.6
## Speed (m/s) above which a latched recovery is released again -- deliberately
## ~2x STUCK_SPEED_MS so the two thresholds do not chatter. Recovery is meant for
## a car that is STOPPED (see STUCK_SPEED_MS); the only other way out was a
## forward index advance, but a car that digs SIDEWAYS keeps `nearest` frozen
## while its speed climbs. The probe measured exactly that: the Novice latched,
## then sat at 20-36 km/h with its index pinned, and RECOVER_THROTTLE_FLOOR held
## the throttle at 0.60 the whole way into InnerRailCollision5. A moving car is
## not stuck, so let it drive normally.
const RECOVER_EXIT_SPEED_MS := 6.0
## Recovery tightens the aim point to this arc so the car points at its tangent.
const RECOVER_LOOKAHEAD_M := 5.0

func _ready() -> void:
    # Scripted drivers shift themselves: tell the car the AUTO box may shift for
    # it. `GameState.transmission_mode` gates the PLAYER's manual choice, so an
    # AI car must opt out or it sits pinned at the 1st-gear redline forever.
    if car != null:
        car.set_scripted_driver(true)

func _physics_process(delta: float) -> void:
    if car == null or waypoints.size() < 2:
        return
    var n := waypoints.size()

    var pos := car.global_position
    var nearest := _nearest_index(pos)
    var speed := _planar_speed()

    _update_progress(nearest, speed, delta)

    # Keep the seek index ahead of the car. Pure pursuit (below) is what actually
    # steers, but a target that has fallen BEHIND the car -- after a spin, a shove
    # off line, a hit -- can never be "captured" again (its distance only grows),
    # so the index would freeze for the rest of the race even while the car drives
    # on. Snap it back onto the nearest point in that case; never at the player.
    if _current_target != nearest and wrapi(_current_target - nearest, 0, n) > n / 2:
        _current_target = nearest

    # --- Stall re-seek: aim FORWARD along the centreline, never at the player ---
    if _ever_moved and _stall_seconds >= STALL_SECONDS and not _resought:
        _current_target = wrapi(nearest + _lookahead_steps(RECOVER_LOOKAHEAD_M), 0, n)
        _resought = true

    # --- Waypoint capture (progression signal) ---
    var to_target := waypoints[_current_target] - pos
    to_target.y = 0.0
    if to_target.length() < CAPTURE_RADIUS:
        _current_target = wrapi(_current_target + 1, 0, n)

    # --- Pure-pursuit aim point (wrap-safe, always ahead of `nearest`) ---
    var aim_arc := RECOVER_LOOKAHEAD_M if _recovering else _lookahead_arc(speed)
    var aim := waypoints[wrapi(nearest + _lookahead_steps(aim_arc), 0, n)]

    # Nose-vs-centreline heading error, used by both the steer command (so the
    # car aligns with the line, not just with the aim point) and the throttle cut
    # below (so it does not power into a growing yaw error).
    var head_err := _heading_error(nearest)
    var steer := _steer_toward(pos, aim, delta, head_err)

    # --- Curvature-lookahead braking (never at creep speed) ---
    var throttle := 1.0
    var braking := 0.0
    if speed > LOW_SPEED_BRAKE_FLOOR_MPS:
        var target := _corner_speed_target(nearest, speed)
        if _corner_braking:
            if speed <= target - CORNER_SPEED_BAND_MPS:
                _corner_braking = false
        elif speed > target + CORNER_SPEED_BAND_MPS:
            _corner_braking = true
        if _corner_braking:
            braking = clampf((speed - target) / CORNER_BRAKE_RAMP_MPS, 0.0, 1.0)
            throttle = 0.0
        elif is_finite(target):
            # A corner lies inside the lookahead: cap the throttle so a fast car
            # cannot power through the turn (see CORNER_THROTTLE_CEIL).
            throttle = minf(throttle, CORNER_THROTTLE_CEIL)
    if throttle > 0.0:
        var cut := STEER_THROTTLE_CUT
        if _recovering:
            cut = RECOVER_THROTTLE_CUT
        elif _stall_seconds >= STALL_SECONDS * 0.6:
            cut = STALL_THROTTLE_CUT
        throttle *= (1.0 - absf(steer) * cut)
        if not _recovering and absf(head_err) > YAW_THROTTLE_CUT_START_RAD:
            throttle *= 1.0 - clampf(
                (absf(head_err) - YAW_THROTTLE_CUT_START_RAD)
                    / (YAW_THROTTLE_CUT_FULL_RAD - YAW_THROTTLE_CUT_START_RAD),
                0.0, 1.0)

    _apply_control(steer, throttle, braking, delta)

func _apply_control(steer: float, throttle: float, braking: float, delta: float) -> void:
    # Throttle/brake are scaled by rubber-banding multiplier
    var adj_throttle := throttle * _speed_multiplier
    _simulate_input(steer, adj_throttle, braking)

func _simulate_input(steer: float, throttle: float, braking: float) -> void:
    ## Drives the car by re-routing input through the physics controller.
    ## This bypasses InputManager (which is player-only).
    var value := throttle - braking
    if _recovering:
        # Throttle floor so a stuck car pulls itself out; braking cannot win here.
        value = maxf(value, RECOVER_THROTTLE_FLOOR)
    # VehiclePhysics treats the EXACT Vector2.ZERO override as "no override" and
    # falls through to player keyboard input. Scripted drivers must never emit it.
    if absf(steer) < 0.0001 and absf(value) < 0.0001:
        value = 0.01
    car.set_input_override(Vector2(steer, value))

## True while the car is latched in stuck recovery (test/telemetry seam).
func is_recovering() -> bool:
    return _recovering

func set_waypoints(points: Array[Vector3], start_index: int = 0) -> void:
    waypoints = points.duplicate()
    _current_target = clampi(start_index, 0, maxi(0, waypoints.size() - 1))
    _mean_spacing = _compute_mean_spacing()
    _first_nearest = -1
    _last_progress_index = -1
    _ever_moved = false
    _stall_seconds = 0.0
    _resought = false
    _recovering = false
    _corner_braking = false
    _smooth_steer = 0.0

func set_speed_multiplier(mult: float) -> void:
    _speed_multiplier = clampf(mult, 0.5, 1.5)

# --- Progress / stall / stuck ------------------------------------------------

func _update_progress(nearest: int, speed: float, delta: float) -> void:
    var n := waypoints.size()
    if _first_nearest < 0:
        _first_nearest = nearest
    if not _ever_moved and speed > 1.5:
        _ever_moved = true
    if not _ever_moved and nearest != _first_nearest:
        # Moved along the line without a live speed read (frozen/test cars).
        _ever_moved = true

    var forward := true
    if _last_progress_index < 0:
        _last_progress_index = nearest
    else:
        # Wrap-safe: a real advance is 1..n/2 steps forward, anything else (a
        # jump across the seam, or no movement at all) is not progress.
        var steps := wrapi(nearest - _last_progress_index, 0, n)
        if steps >= 1 and steps <= n / 2:
            _last_progress_index = nearest
        else:
            forward = false

    if forward:
        _stall_seconds = 0.0
        _resought = false
        _recovering = false
    elif _ever_moved:
        _stall_seconds += delta

    if _ever_moved and speed < STUCK_SPEED_MS and _stall_seconds >= STUCK_SECONDS:
        _recovering = true
    elif _recovering and speed > RECOVER_EXIT_SPEED_MS:
        # Hysteresis on the way out (see RECOVER_EXIT_SPEED_MS): a car that is
        # moving again is no longer stuck, even if its index has not advanced.
        _recovering = false

# --- Steering ----------------------------------------------------------------

func _steer_toward(pos: Vector3, aim: Vector3, delta: float, head_err: float) -> float:
    var car_forward := -car.global_basis.z
    car_forward.y = 0.0
    var to_aim := aim - pos
    to_aim.y = 0.0
    var steer_input := 0.0
    if car_forward.length() > 0.001:
        var f := car_forward.normalized()
        var command := 0.0
        if to_aim.length() > 0.001:
            var t := to_aim.normalized()
            # Signed bearing from nose to aim; positive = aim to the LEFT (positive
            # steer). atan2 removes the 180-degree dead spot the bare cross-product
            # sine hit, while matching its sign below 90 degrees.
            var cross_y := f.z * t.x - f.x * t.z
            var dot := f.x * t.x + f.z * t.z
            command = atan2(cross_y, dot)
        # Same signed-angle convention, nose vs the centreline TANGENT: this term
        # still steers when the bearing to the aim point has cancelled (see
        # HEADING_STEER_GAIN), and counter-steers a car whose nose has been rotated
        # past the line.
        command += head_err * HEADING_STEER_GAIN
        steer_input = clampf(command / STEER_BEARING_SAT, -1.0, 1.0)
    if absf(steer_input) < STEER_DEADBAND:
        steer_input = 0.0
    _smooth_steer = move_toward(_smooth_steer, steer_input, STEER_SLEW_PER_S * delta)
    return _smooth_steer

## Signed angle (rad) from the nose to the centreline TANGENT at `nearest`,
## positive when the tangent lies to the LEFT of the nose -- the same convention
## as the bearing in _steer_toward, so the two terms add instead of cancelling.
## A nose left of the line therefore yields a negative (right) correction, which
## is also the correct counter-steer once the rear has stepped out.
func _heading_error(nearest: int) -> float:
    var n := waypoints.size()
    var car_forward := -car.global_basis.z
    car_forward.y = 0.0
    var tangent := waypoints[wrapi(nearest + 1, 0, n)] - waypoints[nearest]
    tangent.y = 0.0
    if car_forward.length() < 0.001 or tangent.length() < 0.001:
        return 0.0
    var f := car_forward.normalized()
    var t := tangent.normalized()
    return atan2(f.z * t.x - f.x * t.z, f.x * t.x + f.z * t.z)

# --- Corner-speed lookahead --------------------------------------------------

func _corner_speed_target(nearest: int, speed: float) -> float:
    var arc := clampf(
        speed * CORNER_LOOKAHEAD_GAIN, CORNER_LOOKAHEAD_MIN_M, CORNER_LOOKAHEAD_MAX_M)
    var k := RacingLine.lookahead_curvature(waypoints, nearest, arc)
    if k <= 0.000001:
        return INF
    return sqrt(CORNER_LAT_ACCEL / k)

# --- Geometry helpers --------------------------------------------------------

func _lookahead_arc(speed: float) -> float:
    return clampf(speed * LOOKAHEAD_SPEED_GAIN, LOOKAHEAD_MIN_M, LOOKAHEAD_MAX_M)

func _lookahead_steps(arc_m: float) -> int:
    var spacing := maxf(_mean_spacing, 0.5)
    return maxi(1, int(round(arc_m / spacing)))

func _planar_speed() -> float:
    return Vector2(car.linear_velocity.x, car.linear_velocity.z).length()

func _compute_mean_spacing() -> float:
    var n := waypoints.size()
    if n < 2:
        return maxf(_mean_spacing, 1.0)
    var total := 0.0
    for i in n:
        total += waypoints[i].distance_to(waypoints[(i + 1) % n])
    return maxf(total / float(n), 0.5)

func _nearest_index(pos: Vector3) -> int:
    var n := waypoints.size()
    var best_index := 0
    var best_dist := INF
    for i in n:
        var p := waypoints[i]
        var dx := p.x - pos.x
        var dz := p.z - pos.z
        var d := dx * dx + dz * dz
        if d < best_dist:
            best_dist = d
            best_index = i
    return best_index
