# scripts/career/career_profile.gd
class_name CareerProfile
extends RefCounted

## Item 11 progression: player level, XP curve and unlocked perks.
## Level-ups derive purely from accumulated XP (monotonic), and the profile
## persists under the "career_profile" key in the slot save.

const SAVE_KEY := "career_profile"
const DEFAULT_SLOT := 0

const BASE_XP_PER_LEVEL := 100

const LICENSE_TEST_XP := 50
const PODIUM_XP := 100
const EVENT_XP := 25
const RACE_LAP_XP := 10
const RACE_POSITION_XP: Array[int] = [50, 40, 30, 20, 10]

const BASE_PERKS: Array[String] = ["Speed Demon", "Money Magnet", "Gearhead"]

var level: int = 1
var xp: int = 0

var unlocked_perks: Array[String] = []

## XP required to advance from `level` to the next level.
func xp_to_next(level: int) -> int:
	return maxi(level, 1) * BASE_XP_PER_LEVEL

## XP granted for a 1-indexed race finish position (falls back to a floor
## amount for positions past the payout table).
static func race_position_xp(position: int) -> int:
	if position >= 1 and position <= RACE_POSITION_XP.size():
		return RACE_POSITION_XP[position - 1]
	return 5

## Monotonic lifetime XP: the sum of every previous level's requirement plus
## the current level's progress.
func get_total_xp() -> int:
	var total := 0
	for l in range(1, level):
		total += xp_to_next(l)
	return total + xp

## Banks XP and returns the number of levels gained. Level-ups are edge-triggered
## by crossing the current level's requirement.
func add_xp(amount: int) -> int:
	if amount <= 0:
		return 0
	xp += amount
	var levels_gained := 0
	while xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
		levels_gained += 1
	return levels_gained

func unlock_perk(perk_name: String) -> bool:
	if perk_name not in BASE_PERKS or perk_name in unlocked_perks:
		return false
	unlocked_perks.append(perk_name)
	return true

func is_perk_unlocked(perk_name: String) -> bool:
	return perk_name in unlocked_perks

# -- Persistence (item 11): same read-modify-write "career_profile" key.

func to_dict() -> Dictionary:
	return {
		"level": level,
		"xp": xp,
		"unlocked_perks": unlocked_perks,
	}

## Restores the profile clamping invalid values and sanitizing perks against
## the base perk table.
func from_dict(data: Dictionary) -> void:
	level = maxi(int(data.get("level", 1)), 1)
	xp = maxi(int(data.get("xp", 0)), 0)
	unlocked_perks.clear()
	var perks: Variant = data.get("unlocked_perks", [])
	if perks is Array:
		for perk in perks:
			if perk is String and perk in BASE_PERKS and perk not in unlocked_perks:
				unlocked_perks.append(perk)

func save_to_slot(slot: int = DEFAULT_SLOT) -> bool:
	if SaveManager == null:
		return false
	return SaveManager.save_career_profile(slot, to_dict())

func load_from_slot(slot: int = DEFAULT_SLOT) -> bool:
	if SaveManager == null:
		return false
	var data: Dictionary = SaveManager.load_career_profile(slot)
	if data.is_empty():
		return false
	from_dict(data)
	return true

## Loads the persistent profile (fresh profile with `grant_xp` bonus XP when
## no save exists yet or `grant_xp` is positive).
static func load_profile(slot: int = DEFAULT_SLOT, grant_xp: int = 0) -> CareerProfile:
	var profile := CareerProfile.new()
	profile.load_from_slot(slot)
	if grant_xp > 0:
		profile.add_xp(grant_xp)
	return profile

## Banks XP into the persistent profile and persists it.
static func grant_xp(amount: int, slot: int = DEFAULT_SLOT) -> bool:
	if amount <= 0 or SaveManager == null:
		return false
	var profile := load_profile(slot)
	profile.add_xp(amount)
	return profile.save_to_slot(slot)