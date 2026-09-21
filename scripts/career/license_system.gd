# scripts/career/license_system.gd
class_name LicenseSystem
extends RefCounted

## Tracks player's license tier and test results. `results` mirrors the slot
## save's "license_results" key; discipline results persist alongside under
## "license_discipline_results" so the schema stays additive.

const TIERS := ["B", "A", "S", "Race", "Elite"]
const RATINGS := ["Bronze", "Silver", "Gold"]
const DISCIPLINES := ["Circuit", "Rally", "Drift"]

var results: Dictionary = {}  # tier_name -> best_rating
var discipline_results: Dictionary = {}  # discipline -> tier_name -> best_rating

func get_license_tier() -> String:
	## Returns highest license tier earned. Starts at "B".
	var current := "B"
	for tier in TIERS:
		if results.has(tier):
			current = tier
		else:
			break
	return current

func complete_test(tier: String, rating: String) -> void:
	if tier not in TIERS or rating not in RATINGS:
		return
	# Keep best result; a new best also banks license XP.
	if not results.has(tier) or _rating_rank(rating) > _rating_rank(results[tier]):
		results[tier] = rating
		save()
		CareerProfile.grant_xp(CareerProfile.LICENSE_TEST_XP)

func get_best_rating(tier: String) -> String:
	return results.get(tier, "")

func is_car_unlocked(car_class: String) -> bool:
	var tier := get_license_tier()
	var tier_index := TIERS.find(tier)
	var class_index := ["D", "C", "B", "A", "S"].find(car_class)
	return class_index <= tier_index + 1

func complete_discipline_test(discipline: String, tier: String, rating: String) -> void:
	if discipline not in DISCIPLINES or tier not in TIERS or rating not in RATINGS:
		return
	var by_tier: Dictionary = discipline_results.get(discipline, {})
	if not by_tier.has(tier) or _rating_rank(rating) > _rating_rank(by_tier[tier]):
		by_tier[tier] = rating
		discipline_results[discipline] = by_tier
		save()

func get_discipline_tier(discipline: String) -> String:
	## Highest discipline tier earned, using the same ordered ladder rule:
	## a tier only counts once every earlier tier in the discipline is passed.
	if discipline not in DISCIPLINES:
		return ""
	var current := ""
	for tier in TIERS:
		if _discipline_has_result(discipline, tier):
			current = tier
		else:
			break
	return current

func is_discipline_passed(discipline: String, tier: String) -> bool:
	return _discipline_has_result(discipline, tier)

func _discipline_has_result(discipline: String, tier: String) -> bool:
	var by_tier: Variant = discipline_results.get(discipline, {})
	return by_tier is Dictionary and by_tier.has(tier)

func _rating_rank(rating: String) -> int:
	return RATINGS.find(rating)

func save() -> void:
	var data := SaveManager.load_game(0)
	data["license_results"] = results
	data["license_discipline_results"] = discipline_results
	SaveManager.save_game(0, data)

## Rehydrates a LicenseSystem from the slot save. Defaults to a fresh license
## (tier "B") when no data exists.
static func load_from_save(slot: int = 0) -> LicenseSystem:
	var license := LicenseSystem.new()
	license.restore(SaveManager.load_game(slot))
	return license

func restore(data: Dictionary) -> void:
	var res: Variant = data.get("license_results", {})
	if res is Dictionary:
		results = res
	var disc: Variant = data.get("license_discipline_results", {})
	if disc is Dictionary:
		discipline_results = disc