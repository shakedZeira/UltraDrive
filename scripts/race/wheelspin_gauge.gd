# scripts/race/wheelspin_gauge.gd
class_name WheelspinGauge
extends RefCounted

## Pure traction-loss signal behind the HUD "cone" lamp (roadmap #4). Reads
## ONLY the wheel state VehiclePhysics already integrates
## (wheel_angular_velocity, is_in_contact) plus the body speed, and uses the
## SAME rolling-match test the player controller uses for its real spin visuals
## (player_car_controller._has_real_wheelspin: |omega| > rolling * 1.25 while the
## wheel bears weight), so the lamp and the wheel-spin visuals can never
## disagree. No physics field is added and nothing here feeds back into the
## tire model — presentation only.
##
## Pure + headless-safe: every helper is a plain function over floats.

## |omega| must exceed the rolling match by this ratio before the lamp lights.
const SPIN_RATIO := 1.25
## Body speed (m/s) below which no wheel counts as spinning: a car at a crawl
## cannot be losing traction, and a resting wheel's residual omega is noise.
const MIN_SPEED_MPS := 0.5
## Slip multiple that reads as a FULL red lamp. SPIN_RATIO is the amber floor,
## so the ramp spans SPIN_RATIO..SEVERITY_SLIP_FULL.
const SEVERITY_SLIP_FULL := 3.25

const COLOR_OFF := Color(0.24, 0.28, 0.34, 0.55)
const COLOR_AMBER := Color(1.0, 0.68, 0.12, 1.0)
const COLOR_RED := Color(1.0, 0.22, 0.14, 1.0)

## The rolling match (rad/s) the tire would need to track the road at this
## speed. Floored through WheelPhysics.WHEEL_RADIUS, the same radius the tire
## model and the drivetrain use.
static func rolling_match(speed_mps: float) -> float:
	return maxf(speed_mps, 0.0) / WheelPhysics.WHEEL_RADIUS

## How far a wheel's spin is off its rolling match, as a multiple of that match:
## 1.0 while planted, SPIN_RATIO at the threshold, higher while the wheel is
## genuinely off. Signed omega is folded to a magnitude, so a brake lockup and
## a throttle spin read the same. Pure, headless-safe.
static func slip_ratio(omega: float, speed_mps: float) -> float:
	var rolling := rolling_match(speed_mps)
	if rolling <= 0.0:
		return 0.0
	return absf(omega) / rolling

## True when this one wheel is spinning off its rolling match. A wheel must be
## in contact (a resting/airborne wheel never shakes the lamp) and the car must
## actually be rolling.
static func is_spinning(omega: float, speed_mps: float, in_contact: bool) -> bool:
	if not in_contact or speed_mps < MIN_SPEED_MPS:
		return false
	return slip_ratio(omega, speed_mps) > SPIN_RATIO

## 0..1 lamp intensity for a slip multiple: 0 below the threshold, 1 at
## SEVERITY_SLIP_FULL, linear in between.
static func severity_from_slip(slip: float) -> float:
	return clampf((slip - SPIN_RATIO) / (SEVERITY_SLIP_FULL - SPIN_RATIO), 0.0, 1.0)

## Lamp intensity for one wheel. 0 unless that wheel is genuinely spinning.
static func wheel_severity(omega: float, speed_mps: float, in_contact: bool) -> float:
	if not is_spinning(omega, speed_mps, in_contact):
		return 0.0
	return severity_from_slip(slip_ratio(omega, speed_mps))

## The lamp takes the WORST wheel on the car, so a single locked or spinning
## corner is never averaged away by three planted wheels. Arrays are parallel
## (omegas[i] belongs to contacts[i]) and a short contacts array reads as "no
## contact", which keeps a partially built rig dark instead of erroring.
static func severity_for_wheels(omegas: Array, contacts: Array, speed_mps: float) -> float:
	var worst := 0.0
	for i in omegas.size():
		var contact := false
		if i < contacts.size():
			contact = bool(contacts[i])
		worst = maxf(worst, wheel_severity(float(omegas[i]), speed_mps, contact))
	return worst

## Same signal read straight off a live car. The four wheel handles are @onready
## properties, so a car that never entered the tree has no wheel nodes at all;
## those read as 0 rad/s out of contact and keep the lamp dark.
static func severity_for_car(car: VehiclePhysics) -> float:
	if car == null:
		return 0.0
	var omegas: Array = []
	var contacts: Array = []
	for handle: Variant in [car.wheel_fl, car.wheel_fr, car.wheel_rl, car.wheel_rr]:
		var wheel := handle as WheelPhysics
		if wheel == null:
			omegas.append(0.0)
			contacts.append(false)
		else:
			omegas.append(wheel.wheel_angular_velocity)
			contacts.append(wheel.is_in_contact)
	return severity_for_wheels(omegas, contacts, car.linear_velocity.length())

## Amber -> red across the severity range; the dim off-state for a dark lamp.
static func lamp_color(severity: float) -> Color:
	if severity <= 0.0:
		return COLOR_OFF
	return COLOR_AMBER.lerp(COLOR_RED, clampf(severity, 0.0, 1.0))
