class_name TireModel
extends RefCounted

## Implements a simplified Pacejka "Magic Formula" tire model.
## F = D * sin(C * atan(B * x - E * (B * x - atan(B * x))))
## where x = slip angle (lateral) or slip ratio (longitudinal).

static func calculate_lateral_force(
	slip_angle_rad: float,
	normal_force: float,
	config: CarConfig,
	grip_multiplier: float = 1.0,
	surface_factor: float = 1.0
) -> float:
	## Returns lateral tire force in Newtons.
	## slip_angle_rad: angle between wheel heading and velocity vector (radians)
	## normal_force: vertical load on tire (N)
	## grip_multiplier: handling mode modifier (arcade = 1.3, sim = 1.0)
	## surface_factor: surface grip multiplier (asphalt 1.0, snow ~0.35)

	var B := config.tire_B
	var C := config.tire_C
	var D := normal_force * config.tire_D * grip_multiplier * surface_factor
	var E := config.tire_E

	var x := slip_angle_rad
	var force := D * sin(C * atan(B * x - E * (B * x - atan(B * x))))
	return force

static func calculate_longitudinal_force(
	slip_ratio: float,
	normal_force: float,
	config: CarConfig,
	grip_multiplier: float = 1.0,
	surface_factor: float = 1.0
) -> float:
	## Returns longitudinal tire force in Newtons.
	## slip_ratio: (wheel_speed - road_speed) / max(wheel_speed, road_speed, 0.1)
	## Range: -1.0 (full lock) to 1.0 (full spin)
	## surface_factor: surface grip multiplier, scales with grip_multiplier

	var B := config.tire_B * 0.8  # longitudinal is usually less stiff
	var C := config.tire_C
	var D := normal_force * config.tire_D * grip_multiplier * surface_factor * 0.95
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
	## Returns the slip angle (in degrees) at which the tire reaches ~peak usable
	## grip. Used for AI and drift detection.
	##
	## The "1.09 / B" constant is the textbook Pacejka peak-slip rule of thumb:
	## for a tire near the canonical C ~1.3-1.5 lateral band, sin(C*atan(...))
	## peaks almost exactly at B*x = 1.09. Our shipped C is higher (1.8-2.0),
	## which moves the mathematical sin() maximum a bit further out (~1.78/B for
	## the starter; only ~3% more force than at 1.09/B), so 1.09/B stays the
	## practical "flat, near-peak" slip for threshold grips - drift detection and
	## rivals threshold on the SAME constant, keeping feel consistent.
	return rad_to_deg(1.09 / config.tire_B)

## Derivative of calculate_longitudinal_force() with respect to slip_ratio
## (N per unit slip). Used by the wheel-spin integrator for a semi-implicit
## update: the predicted NEXT-frame ground reaction is folded back into the
## torque balance, which keeps the stiff Pacejka curve stable at 60 Hz without
## a separate physics step. Mirrors the exact B/C/D/E shape of
## calculate_longitudinal_force() (same *0.8 and *0.95 factors) so the slope
## matches the curve it linearizes.
static func calculate_longitudinal_stiffness(
	slip_ratio: float,
	normal_force: float,
	config: CarConfig,
	grip_multiplier: float = 1.0,
	surface_factor: float = 1.0
) -> float:
	## Returns dF/dx of the longitudinal magic formula at the given slip.
	## ~Linear ramp of the peak D for small |x|, crosses zero at the grip peak,
	## negative past it (spin-away / lockup region).

	var B := config.tire_B * 0.8
	var C := config.tire_C
	var D := normal_force * config.tire_D * grip_multiplier * surface_factor * 0.95
	var E := config.tire_E

	var x := slip_ratio
	var bx := B * x
	var atan_bx := atan(bx)
	var g := bx - E * (bx - atan_bx)
	var w := C * atan(g)
	# dg/dx = B - E * (B - B / (1 + (B x)^2))
	var dg := B - E * (B - B / (1.0 + bx * bx))
	# dF/dx = D * cos(w) * C / (1 + g^2) * dg
	return D * cos(w) * C / (1.0 + g * g) * dg
