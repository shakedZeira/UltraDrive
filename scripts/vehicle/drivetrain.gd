class_name Drivetrain
extends RefCounted

## Simulates engine, transmission, and differential.
## Call update() every physics frame.
## Gears are 1-based (1 = 1st, ... , gear_ratios.size() = top gear), reverse
## is -1. There is no neutral/0: this is an automatic arcade car that shifts
## itself, so it always sits in a drive gear and never shows "0" or "N".

# --- State ---
var engine_rpm: float = 800.0
var current_gear: int = 1  # 1-based: 1 = 1st, ... , -1 = reverse (no neutral)
var drive_torque: float = 0.0
var is_shifting: bool = false
var shift_timer: float = 0.0
var reverse_limiter_active: bool = false
var manual_mode: bool = false  # true = driver shifts via shift_up/shift_down

# --- Turbo boost state (presentation-only, v1) ---
## Live manifold boost. boost_bar is the pressure in bar (0 for NA cars);
## boost_fraction is 0..1 of the config's turbo_max_boost_bar and drives the
## EngineAudio turbo voices / HUD gauge. Both are computed by update_boost()
## at the TOP of update() so the rpm_override start-gate early-return can
## never skip a frame of boost physics, and both are zeroed by reset().
var boost_bar: float = 0.0
var boost_fraction: float = 0.0

## Wastegate upshift dip: while a shift is in progress on a turbo car that
## has a wastegate, a boost level above this fraction dips toward
## TURBO_SHIFT_DIP_SCALE of its pre-shift value (the boost drops out during
## the shift like a real wastegate/bypass opening).
const TURBO_SHIFT_DIP_FRACTION := 0.5
const TURBO_SHIFT_DIP_SCALE := 0.15
## Boost target curve floor: at idle (rpm_norm 0) WOT still targets this
## fraction of max boost; the rpm term carries it to 1.0 at redline. Spool
## SPEED comes from the config time constants, not from this curve.
const TURBO_RPM_CURVE_MIN := 0.5

# --- Lateral-load downshift veto (AAA-6) ---
## Lateral acceleration (G) of the body, reported by VehiclePhysics each frame
## via set_lateral_g(); 0.0 at rest and on a straight line. Pure-drivetrain
## users never set it, so the veto below is inert by default.
var lateral_g: float = 0.0

## Forced-downshift veto threshold (lateral acceleration, G). Above this, a
## drop is rejected because the engine braking + shorter ratio would spike
## grip mid-corner. Arcade-compatible: 1.0 G sits above what cruise and
## corner-entry sustain, and 0 G (rest / straight) always allows.
const LATERAL_DOWNSHIFT_VETO_G := 1.0

# --- Internal ---
var _wheel_speed: float = 0.0  # m/s (set by VehiclePhysics)
var _axle_speed: float = 0.0  # m/s - driven-axle spin (set by VehiclePhysics)

## Start-gate rev override: when >= 0.0, update() forces engine_rpm toward the
## override fraction of the rev range (0 = idle, 1 = redline) and cuts drive
## torque so the car revs in place while controls are locked. -1 = inactive.
var rpm_override: float = -1.0

func update(delta: float, throttle: float, config: CarConfig) -> Dictionary:
    ## Main drivetrain update.
    ## throttle: [0.0, 1.0] from InputManager
    ## Returns: { engine_rpm, current_gear, drive_torque }

    # Boost is integrated FIRST so the rpm_override early-return below (start-
    # gate revving) cannot skip a frame of build/vent. Presentation-only in v1.
    update_boost(delta, throttle, config)

    if rpm_override >= 0.0:
        var target := lerpf(config.idle_rpm, config.redline_rpm, clampf(rpm_override, 0.0, 1.0))
        engine_rpm = move_toward(engine_rpm, target, config.peak_rpm * delta * 2.0)
        engine_rpm = clampf(engine_rpm, config.idle_rpm * 0.8, config.redline_rpm)
        drive_torque = 0.0
        return {
            "engine_rpm": engine_rpm,
            "current_gear": current_gear,
            "drive_torque": drive_torque,
        }

    # --- Shift timer ---
    if is_shifting:
        shift_timer -= delta
        if shift_timer <= 0.0:
            is_shifting = false

    # --- Reverse selection ---
    # _wheel_speed is signed: positive = forward, negative = backward. Reverse
    # (-1) is PLAYER-SELECTED only, in EVERY mode: the explicit downshift from
    # 1st (shift_down) is the single entry path, and the AUTO box no longer
    # auto-selects R on backward roll. That gate caused the brake-to-zero bug:
    # a hard brake can jounce wheel speed past the old -0.5 m/s threshold for a
    # frame (tire scrub, spring-back), selecting R and rolling the car backward
    # out of a clean stop. Leaving R is automatic and works in both modes:
    # rolling forward returns to 1st (the real-world "shift out of R" roll), and
    # nothing ever re-enters R on its own.
    if current_gear < 0 and _wheel_speed > 0.5:
        current_gear = 1

    # --- Calculate engine RPM from wheel speed ---
    # get_gear_ratio() returns the combined ratio (gear x final drive),
    # which correctly relates wheel speed to engine RPM.
    var gear_ratio := config.get_gear_ratio(current_gear)
    var wheel_radius := 0.33
    var rpm_from_wheels := absf(_wheel_speed) / maxf(wheel_radius, 0.01) \
                         * gear_ratio * 60.0 / TAU

    # Blend RPM with throttle response (engine spins up faster with throttle).
    # Engine speed always tracks wheel speed (even off-throttle) so the
    # transmission only downshifts when road speed genuinely falls, and does
    # not slam into 1st gear from highway speed when the throttle is lifted.
    var target_rpm := maxf(rpm_from_wheels, config.idle_rpm)
    engine_rpm = move_toward(engine_rpm, target_rpm, config.peak_rpm * delta * 2.0)

    # --- Auto-clamp RPM ---
    engine_rpm = clampf(engine_rpm, config.idle_rpm * 0.8, config.redline_rpm)

    # --- Engine torque ---
    var engine_torque := config.get_engine_torque(engine_rpm) * throttle

    # --- Engine braking (when off throttle) ---
    # Direction opposes TRAVEL, not the selected gear: a car rolling backward in
    # a forward gear (MANUAL never auto-flips to R) must have its "engine brake"
    # resist the reverse roll, not amplify it into a runaway. At exact rest the
    # legacy gear-opposing sign is kept (parked) so a parked car never nudges.
    var engine_braking := throttle < 0.05
    if engine_braking:
        # Scale braking off the HIGHER of the engine/body speed and the actual
        # driven-axle spin. During a launch/standing wheelspin the body stays
        # slow (engine_rpm ~ idle) while the wheels scream, so ECU-style body
        # speed gave ~7% of max engine brake and the residual spin bled out
        # slowly - the car kept pulling long after lift-off. The axle is what
        # the engine is really driving, so a burned wheel now snaps back to
        # rolling instead of coasting the pull. In normal driving axle == body
        # speed, so feel is identical; only the wheelspin case changes.
        var axle_rpm := absf(_axle_speed) / maxf(wheel_radius, 0.01) \
                        * gear_ratio * 60.0 / TAU
        var brake_rpm := clampf(maxf(engine_rpm, axle_rpm), config.idle_rpm, config.redline_rpm)
        var mag := config.engine_brake_torque * (brake_rpm / config.peak_rpm)
        var gear_sign := -1.0 if current_gear < 0 else 1.0
        if _wheel_speed > 0.0:
            engine_torque = -mag
        elif _wheel_speed < 0.0:
            engine_torque = mag
        else:
            engine_torque = -gear_sign * mag

    # --- Apply gear ratio and final drive ---
    # gear_ratio already includes the final drive, so NO extra multiplication.
    if not is_shifting:
        drive_torque = engine_torque * absf(gear_ratio)
    else:
        drive_torque = 0.0  # no torque during shift

    # Reverse routes THROTTLE torque backward through the gearbox, so throttle
    # accelerates the car rearward. Engine-brake torque is already travel-keyed
    # above (absolute axle direction), so it must NOT be flipped again.
    if current_gear < 0 and not engine_braking:
        drive_torque = -drive_torque * config.reverse_torque_multiplier

    # --- Reverse speed limiter ---
    # Hard cap so reverse can never out-accelerate or out-top-speed 1st gear;
    # drive torque cuts out once the cap is reached (low-speed creep is fine).
    if current_gear < 0:
        var reverse_speed_kmh := absf(_wheel_speed) * 3.6
        reverse_limiter_active = reverse_speed_kmh >= config.max_reverse_speed_kmh
        if reverse_limiter_active:
            drive_torque = 0.0
    else:
        reverse_limiter_active = false

    # --- Auto-shift (automatic transmission only) ---
    # Upshifts are RPM-based so cars climb to redline before changing gear; the
    # old speed tables shifted at ~35% of redline. Downshifts stay speed-based.
    # Manual mode never auto-shifts; reverse (-1) is never auto-shifted.
    if not manual_mode and not is_shifting and current_gear > 0:
        var auto_shift_rpm: float = config.redline_rpm * config.auto_shift_rpm_fraction
        var speed_kmh := absf(_wheel_speed) * 3.6
        var max_gear := config.gear_ratios.size()
        if current_gear < max_gear and engine_rpm >= auto_shift_rpm:
            shift_up(config)
        elif current_gear > 1 \
                and speed_kmh < config.get_downshift_speed_kmh(current_gear):
            shift_down(config)

    return {
        "engine_rpm": engine_rpm,
        "current_gear": current_gear,
        "drive_torque": drive_torque,
    }

## First-order turbo boost integration (presentation-only, v1). Target =
## throttle x boost_target_fraction's rpm curve; build rides turbo_spool_time,
## vent rides turbo_blowdown_time. A wastegate-equipped car (turbo_has_wastegate)
## dips the target toward TURBO_SHIFT_DIP_SCALE while a shift is in progress
## and boost is up. NA configs (turbo_max_boost_bar <= 0) are forced to 0.
func update_boost(delta: float, throttle: float, config: CarConfig) -> void:
    if config == null or config.turbo_max_boost_bar <= 0.0:
        boost_bar = 0.0
        boost_fraction = 0.0
        return
    var target := boost_target_fraction(throttle, engine_rpm, config)
    if is_shifting and config.turbo_has_wastegate and boost_fraction > TURBO_SHIFT_DIP_FRACTION:
        target *= TURBO_SHIFT_DIP_SCALE
    var tau := config.turbo_spool_time if target > boost_fraction else config.turbo_blowdown_time
    tau = maxf(tau, 0.01)
    boost_fraction = lerpf(boost_fraction, target, 1.0 - exp(-delta / tau))
    boost_fraction = clampf(boost_fraction, 0.0, 1.0)
    boost_bar = boost_fraction * config.turbo_max_boost_bar

## Steady-state boost target (0..1) for a throttle/rpm pair: throttle scaled
## by a curve that ramps TURBO_RPM_CURVE_MIN..1.0 between idle and redline.
## NA configs always target 0.
static func boost_target_fraction(throttle: float, rpm: float, config: CarConfig) -> float:
    if config == null or config.turbo_max_boost_bar <= 0.0:
        return 0.0
    var rpm_norm := clampf(
        (rpm - config.idle_rpm) / maxf(config.redline_rpm - config.idle_rpm, 1.0),
        0.0, 1.0
    )
    return clampf(throttle, 0.0, 1.0) * lerpf(TURBO_RPM_CURVE_MIN, 1.0, rpm_norm)

func shift_up(config: CarConfig) -> void:
    # An upshift out of reverse (-1) returns to 1st - the inverse of the
    # 1st->R downshift. Works for player-selected R in MANUAL and AUTO alike
    # (in AUTO the box never auto-selects R, so any time it is in R the player
    # chose it and may shift back out).
    if current_gear == -1:
        current_gear = 1
        _start_shift(config)
        return
    if current_gear >= 1 and current_gear < config.gear_ratios.size():
        current_gear += 1
        _start_shift(config)

func shift_down(config: CarConfig) -> void:
    # Lateral-load veto (AAA-6, sibling to the over-rev guard): reject a forced
    # drop under hard lateral G so engine braking + a shorter ratio cannot upset
    # the car mid-corner. Single decision site - MANUAL requests and the AUTO
    # speed-table path both route through here. At-rest / straight reads 0 G and
    # always allows, which is what keeps it arcade-friendly.
    if lateral_g >= LATERAL_DOWNSHIFT_VETO_G:
        return
    # Over-rev guard: reject the drop if the lower gear would push the engine
    # past 105% of redline at the current wheel speed. Dropping from 1st
    # selects reverse (-1): that is the ONLY way reverse engages, in EVERY mode
    # (rolling backward never auto-selects it - the brake-to-zero bug fix), and
    # the same over-rev guard applies so a fast forward roll cannot drop into R.
    if current_gear > 1:
        var gear_ratio := config.get_gear_ratio(current_gear - 1)
        var wheel_radius := 0.33
        var rpm_after := absf(_wheel_speed) / maxf(wheel_radius, 0.01) \
                        * gear_ratio * 60.0 / TAU
        if rpm_after > config.redline_rpm * 1.05:
            return
        current_gear -= 1
        _start_shift(config)
    elif current_gear == 1:
        var reverse_ratio := config.get_gear_ratio(-1)
        var wheel_radius := 0.33
        var rpm_after := absf(_wheel_speed) / maxf(wheel_radius, 0.01) \
                        * reverse_ratio * 60.0 / TAU
        if rpm_after > config.redline_rpm * 1.05:
            return
        current_gear = -1
        _start_shift(config)

func _start_shift(config: CarConfig) -> void:
    is_shifting = true
    shift_timer = config.shift_time

func set_wheel_speed(speed: float) -> void:
    ## Called by VehiclePhysics to update wheel speed for RPM calculation.
    _wheel_speed = speed

func set_axle_speed(speed: float) -> void:
    ## Called by VehiclePhysics with the driven axle's effective speed (mean of
    ## the driven wheels' spin x radius). Used to scale engine braking during
    ## wheelspin; 0.0 (default) keeps legacy behavior for direct-api users.
    _axle_speed = speed

func set_lateral_g(g: float) -> void:
    ## Feeds the lateral-load downshift veto (G units). Clamped so a bad sensor
    ## read can never yield a negative. VehiclePhysics calls this once per frame
    ## alongside set_wheel_speed()/set_axle_speed().
    lateral_g = maxf(g, 0.0)

func reset() -> void:
    engine_rpm = 800.0
    current_gear = 1
    drive_torque = 0.0
    is_shifting = false
    reverse_limiter_active = false
    rpm_override = -1.0
    _axle_speed = 0.0
    lateral_g = 0.0
    boost_bar = 0.0
    boost_fraction = 0.0
