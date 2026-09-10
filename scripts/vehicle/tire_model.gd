class_name TireModel
extends RefCounted

## Implements a simplified Pacejka "Magic Formula" tire model.
## F = D * sin(C * atan(B * x - E * (B * x - atan(B * x))))
## where x = slip angle (lateral) or slip ratio (longitudinal).

static func calculate_lateral_force(
	slip_angle_rad: float,
	normal_force: float,
	config: CarConfig,
	grip_multiplier: float = 1.0
) -> float:
	## Returns lateral tire force in Newtons.
	## slip_angle_rad: angle between wheel heading and velocity vector (radians)
	## normal_force: vertical load on tire (N)
	## grip_multiplier: handling mode modifier (arcade = 1.3, sim = 1.0)

	var B := config.tire_B
	var C := config.tire_C
	var D := normal_force * config.tire_D * grip_multiplier
	var E := config.tire_E

	var x := slip_angle_rad
	var force := D * sin(C * atan(B * x - E * (B * x - atan(B * x))))
	return force

static func calculate_longitudinal_force(
	slip_ratio: float,
	normal_force: float,
	config: CarConfig,
	grip_multiplier: float = 1.0
) -> float:
	## Returns longitudinal tire force in Newtons.
	## slip_ratio: (wheel_speed - road_speed) / max(wheel_speed, road_speed, 0.1)
	## Range: -1.0 (full lock) to 1.0 (full spin)

	var B := config.tire_B * 0.8  # longitudinal is usually less stiff
	var C := config.tire_C
	var D := normal_force * config.tire_D * grip_multiplier * 0.95
	var E := config.tire_E

	var x := slip_ratio
	var force := D * sin(C * atan(B * x - E * (B * x - atan(B * x))))
	return force

static func calculate_slip_angle(
	wheel_forward: Vector3,
	wheel_velocity: Vector3
) -> float:
	## Returns slip angle in radians.
	## wheel_forward: the direction the wheel is pointing (world space)
	## wheel_velocity: actual velocity of the wheel contact point

	var vel_along_wheel := wheel_forward.dot(wheel_velocity)
	var vel_perpendicular := wheel_forward.cross(wheel_velocity).length()

	# Determine sign of perpendicular velocity
	var cross := wheel_forward.cross(wheel_velocity)
	var sign := 1.0 if cross.y >= 0.0 else -1.0

	return atan2(vel_perpendicular * sign, maxf(absf(vel_along_wheel), 1.0))

static func calculate_slip_ratio(
	wheel_angular_velocity: float,
	forward_speed: float,
	wheel_radius: float = 0.33
) -> float:
	## Returns slip ratio [-1.0, 1.0].
	## 0 = no slip, positive = wheelspin, negative = lockup.

	var wheel_speed := wheel_angular_velocity * wheel_radius
	var denominator := maxf(maxf(absf(wheel_speed), absf(forward_speed)), 1.0)
	return clampf((wheel_speed - forward_speed) / denominator, -1.0, 1.0)

static func get_peak_slip_angle(config: CarConfig) -> float:
	## Returns the slip angle (in degrees) at which peak grip occurs.
	## Useful for AI and drift detection.
	return rad_to_deg(1.0 / config.tire_B) * 2.0
