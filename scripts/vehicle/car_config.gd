class_name CarConfig
extends Resource

## Defines all configurable parameters for a vehicle.
## Create .tres files per car to define different vehicles.

@export var car_name: String = "starter_car"
@export var car_class: String = "D"  # D, C, B, A, S

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
@export var shift_time: float = 0.15  # seconds to shift gears

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
@export var downforce_coefficient: float = 0.0  # 0 = none, higher = more downforce

# --- Drift ---
@export var handbrake_grip_reduction: float = 0.3  # 0.0 = no grip, 1.0 = full grip
@export var countersteer_assist: float = 800.0     # Nm of yaw correction

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

func get_engine_torque(rpm: float) -> float:
    ## Returns engine torque at given RPM using a simplified torque curve.
    if rpm < idle_rpm:
        return max_torque * 0.5
    if rpm > redline_rpm:
        return 0.0
    # Parabolic torque curve peaking at peak_rpm
    var t := (rpm - idle_rpm) / (peak_rpm - idle_rpm)
    if t <= 1.0:
        return max_torque * (1.0 - pow(t - 1.0, 2.0))
    else:
        # Past peak, taper off
        var t2 := (rpm - peak_rpm) / (redline_rpm - peak_rpm)
        return max_torque * (1.0 - t2 * 0.8)

func get_gear_ratio(gear: int) -> float:
    ## Returns gear ratio for given gear index (0-based). Negative = reverse.
    if gear < 0:
        return reverse_ratio * final_drive_ratio
    if gear >= gear_ratios.size():
        return gear_ratios[gear_ratios.size() - 1] * final_drive_ratio
    return gear_ratios[gear] * final_drive_ratio

func get_max_speed() -> float:
    ## Approximate top speed in m/s based on highest gear ratio.
    var top_gear_ratio := gear_ratios[gear_ratios.size() - 1] * final_drive_ratio
    var wheel_radius := 0.33  # approximate
    return (peak_rpm / top_gear_ratio) * wheel_radius * TAU / 60.0
