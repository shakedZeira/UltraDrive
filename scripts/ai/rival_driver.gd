# scripts/ai/rival_driver.gd
class_name RivalDriver
extends AIController

## Race-rival AI driver (S5). Follows a full racing line per car class + skill
## tier. Pace comes from RacingLine (class band x tier) so it is rubber-band-
## free by construction; only low-tier / traffic drivers get the rubber-band
## assist, gated globally by GameState.rubber_band_assist (never the player).

var skill_tier: String = "Skilled"
var car_class: String = "D"

func configure(line: Array[Vector3], tier: String, car_class_name: String) -> void:
    skill_tier = RacingLine.normalize_tier(tier)
    car_class = RacingLine.clean_class(car_class_name)
    set_waypoints(line)

func get_tier() -> String:
    return skill_tier

func get_car_class() -> String:
    return car_class

func get_pace_multiplier() -> float:
    ## Rubber-band-free pace for this rival: class band x skill tier.
    return RacingLine.pace_for(car_class, skill_tier)

func _apply_control(steer: float, throttle: float, braking: float, delta: float) -> void:
    var mult := get_pace_multiplier() * AIRubberBanding.multiplier_for(
        rubber_band_category(), time_gap_seconds(), GameState.rubber_band_assist)
    _simulate_input(steer, throttle * mult, braking)

func rubber_band_category() -> String:
    if car != null and car == VehicleManager.get_player_car():
        return AIRubberBanding.CATEGORY_PLAYER
    return skill_tier

func time_gap_seconds() -> float:
    ## Positive = this rival ahead of the player. No counters (free roam) or
    ## identical cars -> no adjustment.
    var player := VehicleManager.get_player_car()
    if car == null or player == null or car == player:
        return 0.0
    var mine := RaceManager.get_lap_counter(car)
    var theirs := RaceManager.get_lap_counter(player)
    if mine == null or theirs == null:
        return 0.0
    return theirs.get_total_time() - mine.get_total_time()