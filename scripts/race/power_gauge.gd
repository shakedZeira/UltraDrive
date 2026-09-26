# scripts/race/power_gauge.gd
class_name PowerGauge
extends RefCounted

## Pure horsepower readout for the HUD (roadmap #4). Power comes from the SAME
## engine the drivetrain already runs: the torque curve (CarConfig.
## get_engine_torque) evaluated at the RPM VehiclePhysics.get_drive_info()
## reports, times that RPM's angular rate. The rated peak is the MAXIMUM of
## that same curve over the rev range, so the delta can never read positive:
## it is 0 on the power peak and negative everywhere else. Note the max does
## NOT sit exactly on CarConfig.peak_rpm: torque falls off parabolically after
## the peak while rpm keeps climbing, so the product tops out slightly ABOVE
## peak_rpm. Rating the car at the peak_rpm sample would understate it and
## leave a permanently negative delta at the real power peak.
##
## Pure + headless-safe: no frames, no scene access.

## Mechanical horsepower (W per hp), the conventional 550 ft*lb/s definition.
const WATTS_PER_HP := 745.7

## Rpm step used to find the curve maximum. The power curve is smooth and
## broad near its top, so 25 rpm puts the sampled peak within a rounding of
## the true one for ~270 samples across the range — cheap enough to evaluate
## per frame.
const PEAK_SCAN_STEP_RPM := 25.0

## Instantaneous crank power (hp) at `rpm` for `config`. Zero for a null config
## and for a negative rpm, so the readout can never show a negative engine.
static func power_hp(config: CarConfig, rpm: float) -> float:
	if config == null:
		return 0.0
	var speed := maxf(rpm, 0.0)
	return config.get_engine_torque(speed) * speed * TAU / 60.0 / WATTS_PER_HP

## Rated peak power (hp) of the config's engine: the best crank power its own
## torque curve can make anywhere between idle and the redline.
static func peak_power_hp(config: CarConfig) -> float:
	if config == null:
		return 0.0
	var best := 0.0
	var rpm := maxf(config.idle_rpm, 0.0)
	var limit := config.redline_rpm
	while rpm <= limit:
		best = maxf(best, power_hp(config, rpm))
		rpm += PEAK_SCAN_STEP_RPM
	# The loop steps in whole steps from idle, so the final partial step before
	# the redline is only covered if it lands exactly; check the redline too.
	return maxf(best, power_hp(config, limit))

## Rpm at which the engine actually makes its rated peak power. The delta
## reads exactly 0.0 here, which is what makes the readout trustworthy.
static func max_power_rpm(config: CarConfig) -> float:
	if config == null:
		return 0.0
	var best_rpm := 0.0
	var best := -1.0
	var rpm := maxf(config.idle_rpm, 0.0)
	var limit := config.redline_rpm
	while rpm <= limit:
		var power := power_hp(config, rpm)
		if power > best:
			best = power
			best_rpm = rpm
		rpm += PEAK_SCAN_STEP_RPM
	var last := power_hp(config, limit)
	if last > best:
		best_rpm = limit
	return best_rpm

## Signed hp gap between the current rpm and the rated peak. Negative while the
## engine is off its power peak, 0.0 when the peak cannot be derived.
static func hp_delta_hp(config: CarConfig, rpm: float) -> float:
	var peak := peak_power_hp(config)
	if peak <= 0.0:
		return 0.0
	return power_hp(config, rpm) - peak

## Explicit sign rendering: GDScript's %-formatting sign flag is avoided so the
## emitted text is byte-identical everywhere (no "-0" / "+0" locale surprises).
static func signed_hp(value: float) -> String:
	var rounded := roundi(value)
	return ("+%d" % rounded) if rounded >= 0 else str(rounded)

## HUD line: "<current> hp  <signed delta>". The trailing signed token is the
## delta, so the number reads at a glance like a data logger.
static func format_text(config: CarConfig, rpm: float) -> String:
	if config == null:
		return "-- hp"
	return "%d hp  %s" % [roundi(power_hp(config, rpm)), signed_hp(hp_delta_hp(config, rpm))]
