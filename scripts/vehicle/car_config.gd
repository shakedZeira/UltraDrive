class_name CarConfig
extends Resource

## Defines all configurable parameters for a vehicle.
## Create .tres files per car to define different vehicles.

@export var car_name: String = "starter_car"
@export var car_class: String = "D"  # D, C, B, A, S
@export var visual_path: String = "res://assets/cars/sports_coupe.glb"  # 3D model shown & driven

# --- Economy (item 11) ---
@export var price: int = 0  # sticker price in career credits (0 = not purchasable)

# --- Procedural Engine Sound (timbre used by CarAudio PROFILES table) ---
@export_enum("sport", "muscle", "rally") var engine_timbre: String = "sport"

# --- Mass & Dimensions ---
@export var mass_kg: float = 1200.0
@export var wheelbase: float = 2.5     # distance between front and rear axles (m)
@export var track_width: float = 1.6   # distance between left and right wheels (m)
@export var center_of_mass_offset: Vector3 = Vector3(0.0, -0.3, 0.0)

# --- Engine ---
@export var max_torque: float = 300.0    # Nm at peak RPM
@export var peak_rpm: float = 6500.0
@export var redline_rpm: float = 7500.0
@export var idle_rpm: float = 800.0
@export var engine_brake_torque: float = 50.0  # Nm of engine braking

# --- Transmission ---
@export var gear_ratios: Array[float] = [3.5, 2.1, 1.4, 1.0, 0.75, 0.6]
@export var final_drive_ratio: float = 3.7
@export var reverse_ratio: float = 3.2
@export var max_reverse_speed_kmh: float = 25.0  # hard cap; reverse stays well below 1st gear
@export var shift_time: float = 0.15  # seconds to shift gears
@export var auto_shift_rpm_fraction: float = 0.92  # fraction of redline at which the auto-box upshifts

# --- Automatic transmission shift points (km/h) ---
# upshift_speeds_kmh[i] is the speed at which the auto-box shifts up from
# gear (i + 1) to gear (i + 2). downshift_speeds_kmh[i] is the speed below
# which it drops back from gear (i + 2) to gear (i + 1). Down points are
# lower than up points so the box does not hunt between gears.
@export var upshift_speeds_kmh: Array[float] = [25.0, 55.0, 85.0, 120.0, 160.0]
@export var downshift_speeds_kmh: Array[float] = [15.0, 38.0, 60.0, 90.0, 120.0]

# --- Differential ---
@export_enum("Open", "LSD", "Locked") var diff_type: int = 1
@export var lsd_preload: float = 50.0    # Nm (for LSD only)
@export var lsd_ramp_angle: float = 45.0  # degrees (for LSD only)

# --- Suspension ---
@export var spring_rate: float = 35000.0      # N/m
@export var damper_compression: float = 4000.0  # Ns/m
@export var damper_rebound: float = 5000.0    # Ns/m
@export var suspension_travel: float = 0.1    # meters (100mm)
@export var ride_height: float = 0.15         # meters
@export var anti_roll_bar: float = 10000.0    # N/m

# --- Tire (Pacejika Parameters) ---
@export var tire_B: float = 10.0   # Stiffness factor
@export var tire_C: float = 1.9    # Shape factor
@export var tire_D: float = 1.0    # Peak factor (mu)
@export var tire_E: float = 0.97   # Curvature factor
@export var tire_width: float = 0.225  # meters (for visual + grip calc)

# --- Brakes ---
@export var max_brake_torque: float = 2500.0  # Nm per wheel
@export var brake_bias: float = 0.65          # 0.0 = all rear, 1.0 = all front

# --- Steering ---
@export var max_steer_angle: float = 35.0  # degrees at low speed
@export var steer_speed: float = 3.0       # how fast steering responds (1-5)

# --- Aerodynamics ---
@export var drag_coefficient: float = 0.35
@export var frontal_area: float = 2.2  # m^2
@export var downforce_coefficient: float = 0.0  # read as a lift coefficient Cl: aero load = 0.5*rho*Cl*A*v^2, fed into the tire Pacejka D terms + applied as a chassis push-down. 0 = none.

# --- Drift ---
@export var handbrake_grip_reduction: float = 0.3  # 0.0 = no grip, 1.0 = full grip
@export var countersteer_assist: float = 800.0  # max Nm of stability-yaw damping (damps angular_velocity toward the GRIP-achievable yaw target v*tan(steer)/wheelbase clamped to mu*g/v, ramps in above ~70 km/h, off while handbraking)

# --- Handling Mode Modifiers ---
@export var arcade_mode: Dictionary = {
    "grip_multiplier": 1.3,
    "weight_transfer_scale": 0.6,
    "anti_flip": true,
    "max_speed_modifier": 1.1,
}
@export var simulation_mode: Dictionary = {
    "grip_multiplier": 1.0,
    "weight_transfer_scale": 1.0,
    "anti_flip": false,
    "max_speed_modifier": 1.0,
}

# --- Helper Functions ---

## Returns a NEW CarConfig with the given tuning overrides applied on top of
## this base, leaving the base untouched (controllers can hold both the stock
## and a tuned variant from the same resource). Recognized override keys:
## gear_ratios (Array[float]), final_drive_ratio, mass_kg. Unknown keys and
## wrong-typed values are ignored, so the clone is always safe to drive.
func with_overrides(overrides: Dictionary) -> CarConfig:
    var clone := duplicate(true) as CarConfig
    if overrides.has("gear_ratios") and overrides["gear_ratios"] is Array:
        clone.gear_ratios.assign(overrides["gear_ratios"])
    if overrides.has("final_drive_ratio") and overrides["final_drive_ratio"] is float:
        clone.final_drive_ratio = overrides["final_drive_ratio"]
    if overrides.has("mass_kg") and overrides["mass_kg"] is float:
        clone.mass_kg = overrides["mass_kg"]
    return clone

func get_engine_torque(rpm: float) -> float:
    ## Returns engine torque at given RPM using a simplified torque curve.
    if rpm < idle_rpm:
        return max_torque * 0.5
    if rpm > redline_rpm:
        return 0.0
    if rpm <= peak_rpm:
        # Linear ramp from half torque at idle to full torque at peak RPM
        var t := (rpm - idle_rpm) / (peak_rpm - idle_rpm)
        return max_torque * (0.5 + 0.5 * t)
    else:
        # Parabolic drop to zero torque at redline
        var t2 := (rpm - peak_rpm) / (redline_rpm - peak_rpm)
        return max_torque * (1.0 - t2 * t2)

func get_gear_ratio(gear: int) -> float:
    ## Returns the combined gear ratio (gear x final drive) for a 1-based
    ## gear: 1 = 1st, 2 = 2nd, ... , gear_ratios.size() = top gear, -1 = reverse.
    ## gear_ratios[] is 0-indexed, so the array index is gear - 1.
    if gear < 0:
        return reverse_ratio * final_drive_ratio
    var idx := clampi(gear - 1, 0, gear_ratios.size() - 1)
    return gear_ratios[idx] * final_drive_ratio

func get_upshift_speed_kmh(gear: int) -> float:
    ## Speed at which the automatic transmission upshifts out of `gear`
    ## (1-based; from `gear` to `gear + 1`). Gear numbers past the end of the
    ## table clamp to the last entry.
    var idx := clampi(gear - 1, 0, upshift_speeds_kmh.size() - 1)
    return upshift_speeds_kmh[idx]

func get_downshift_speed_kmh(gear: int) -> float:
    ## Speed below which the automatic transmission downshifts out of `gear`
    ## (1-based; from `gear` to `gear - 1`).
    var idx := clampi(gear - 2, 0, downshift_speeds_kmh.size() - 1)
    return downshift_speeds_kmh[idx]

func get_max_speed() -> float:
    ## Approximate top speed in m/s based on highest gear ratio.
    var top_gear_ratio := gear_ratios[gear_ratios.size() - 1] * final_drive_ratio
    var wheel_radius := 0.33  # approximate
    return (peak_rpm / top_gear_ratio) * wheel_radius * TAU / 60.0
