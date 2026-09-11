# scripts/career/license_system.gd
class_name LicenseSystem
extends Node

## Tracks player's license tier and test results.

const TIERS := ["B", "A", "S", "Race", "Elite"]
const RATINGS := ["Bronze", "Silver", "Gold"]

var results: Dictionary = {}  # tier_name -> best_rating

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
	# Keep best result
	if not results.has(tier) or _rating_rank(rating) > _rating_rank(results[tier]):
		results[tier] = rating
		save()

func get_best_rating(tier: String) -> String:
	return results.get(tier, "")

func is_car_unlocked(car_class: String) -> bool:
	var tier := get_license_tier()
	var tier_index := TIERS.find(tier)
	var class_index := ["D", "C", "B", "A", "S"].find(car_class)
	return class_index <= tier_index + 1

func _rating_rank(rating: String) -> int:
	return RATINGS.find(rating)

func save() -> void:
	var data := SaveManager.load_game(0)
	data["license_results"] = results
	SaveManager.save_game(0, data)
