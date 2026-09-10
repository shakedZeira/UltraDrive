class_name Drivetrain
extends RefCounted

## Simulates engine, transmission, and differential.
## Call update() every physics frame.

# --- State ---
var engine_rpm: float = 800.0
var current_gear: int = 0  # 0 = 1st, -1 = reverse
var drive_torque: float = 0.0
var is_shifting: bool = false
var shift_timer: float = 0.0

# --- Internal ---
var _wheel_speed: float = 0.0  # m/s (set by VehiclePhysics)

func update(delta: float, throttle: float, config: CarConfig) -> Dictionary:
    ## Main drivetrain update.
    ## throttle: [0.0, 1.0] from InputManager
    ## Returns: { engine_rpm, current_gear, drive_torque }

    # --- Shift timer ---
    if is_shifting:
        shift_timer -= delta
        if shift_timer <= 0.0:
            is_shifting = false

    # --- Calculate engine RPM from wheel speed ---
    var gear_ratio := config.get_gear_ratio(current_gear)
    var wheel_radius := 0.33
    var rpm_from_wheels := absf(_wheel_speed) / maxf(wheel_radius, 0.01) \
                         * gear_ratio * 60.0 / TAU

    # Blend RPM with throttle response (engine spins up faster with throttle)
    var target_rpm := lerpf(config.idle_rpm, rpm_from_wheels, throttle)
    engine_rpm = move_toward(engine_rpm, target_rpm, config.peak_rpm * delta * 2.0)

    # --- Auto-clamp RPM ---
    engine_rpm = clampf(engine_rpm, config.idle_rpm * 0.8, config.redline_rpm)

    # --- Engine torque ---
    var engine_torque := config.get_engine_torque(engine_rpm) * throttle

    # --- Engine braking (when off throttle) ---
    if throttle < 0.05:
        engine_torque = -config.engine_brake_torque * (engine_rpm / config.peak_rpm)

    # --- Apply gear ratio and final drive ---
    if not is_shifting:
        drive_torque = engine_torque * absf(gear_ratio) * config.final_drive_ratio
    else:
        drive_torque = 0.0  # no torque during shift

    # --- Auto-shift (simple RPM-based) ---
    if not is_shifting and current_gear >= 0:
        if engine_rpm >= config.redline_rpm * 0.95 and current_gear < config.gear_ratios.size() - 1:
            shift_up(config)
        elif engine_rpm < config.idle_rpm * 1.2 and current_gear > 0:
            shift_down(config)

    return {
        "engine_rpm": engine_rpm,
        "current_gear": current_gear,
        "drive_torque": drive_torque,
    }

func shift_up(config: CarConfig) -> void:
    if current_gear < config.gear_ratios.size() - 1:
        current_gear += 1
        _start_shift(config)

func shift_down(config: CarConfig) -> void:
    if current_gear > -1:  # -1 = reverse
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
    current_gear = 0
    drive_torque = 0.0
    is_shifting = false
