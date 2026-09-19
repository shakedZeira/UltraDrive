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

# --- Internal ---
var _wheel_speed: float = 0.0  # m/s (set by VehiclePhysics)

## Start-gate rev override: when >= 0.0, update() forces engine_rpm toward the
## override fraction of the rev range (0 = idle, 1 = redline) and cuts drive
## torque so the car revs in place while controls are locked. -1 = inactive.
var rpm_override: float = -1.0

func update(delta: float, throttle: float, config: CarConfig) -> Dictionary:
    ## Main drivetrain update.
    ## throttle: [0.0, 1.0] from InputManager
    ## Returns: { engine_rpm, current_gear, drive_torque }

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

    # --- Reverse detection ---
    # _wheel_speed is signed: positive = forward, negative = backward. Engage
    # reverse whenever the car actually rolls backward and drop back to 1st the
    # moment it moves forward again (deadband prevents flicker at standstill).
    if current_gear >= 1:
        if _wheel_speed < -0.5:
            current_gear = -1
    elif _wheel_speed > 0.5:
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
    if throttle < 0.05:
        engine_torque = -config.engine_brake_torque * (engine_rpm / config.peak_rpm)

    # --- Apply gear ratio and final drive ---
    # gear_ratio already includes the final drive, so NO extra multiplication.
    if not is_shifting:
        drive_torque = engine_torque * absf(gear_ratio)
    else:
        drive_torque = 0.0  # no torque during shift

    # Reverse routes engine torque backward through the gearbox, so throttle
    # accelerates the car rearward and engine braking resists rearward roll.
    if current_gear < 0:
        drive_torque = -drive_torque

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

func shift_up(config: CarConfig) -> void:
    if current_gear >= 1 and current_gear < config.gear_ratios.size():
        current_gear += 1
        _start_shift(config)

func shift_down(config: CarConfig) -> void:
    # Over-rev guard: reject the drop if the lower gear would push the engine
    # past 105% of redline at the current wheel speed (protects manual shifts).
    if current_gear > 1:  # never drop below 1st; reverse (-1) is a separate state
        var gear_ratio := config.get_gear_ratio(current_gear - 1)
        var wheel_radius := 0.33
        var rpm_after := absf(_wheel_speed) / maxf(wheel_radius, 0.01) \
                        * gear_ratio * 60.0 / TAU
        if rpm_after > config.redline_rpm * 1.05:
            return
        current_gear -= 1
        _start_shift(config)

func _start_shift(config: CarConfig) -> void:
    is_shifting = true
    shift_timer = config.shift_time

func set_wheel_speed(speed: float) -> void:
    ## Called by VehiclePhysics to update wheel speed for RPM calculation.
    _wheel_speed = speed

func reset() -> void:
    engine_rpm = 800.0
    current_gear = 1
    drive_torque = 0.0
    is_shifting = false
    reverse_limiter_active = false
    rpm_override = -1.0
