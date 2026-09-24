# scripts/ai/rival_persona.gd
class_name RivalPersona
extends RefCounted

## Nameable persistent rival personalities (A4). Turns the anonymous no-rubber-
## band rival roster into people: every rival spec carries a handle, a tier
## (always the same tier the RivalDriver races at, so presentation can never
## drift from pace), a signature trait, and a persistent W/L rivalry record.
##
## Pure + deterministic: no nodes, no scene access. Handles/traits are drawn
## from a fixed name pool seeded by a per-save seed (RandomNumberGenerator is
## explicitly seeded, never the global RNG), so the same seed always yields the
## same roster. Persistence follows the slot sub-dict schema under SAVE_KEY via
## SaveManager merge-writes (read-modify-write preserves every other slot key).

## Persisted slot sub-dict key (additive to the slot schema).
const SAVE_KEY := "rival_personas"
const DEFAULT_SLOT := 0

## Signature traits shown on the grid card / results rows.
const TRAITS: Array[String] = [
	"late-braker",
	"drafter",
	"qualifier",
	"wet-weather",
	"aggressive",
	"consistent",
]

## Deterministic name pool. Rotated by the per-save seed so a fresh save fields
## a new rival field while a restored save keeps its people (the "bowie knife99"
## lesson: players race names, not car 3).
const NAME_POOL: Array[String] = [
	"bowie knife99",
	"Night Fury",
	"Redline Rita",
	"Drift King",
	"Velocity Vega",
	"Apex Annie",
	"Gridlock Gus",
	"Tailwind Tessa",
	"Oversteer Ozzie",
	"Kerb Kicker",
	"Sixth Gear Sal",
	"Qualifier Quinn",
	"Pitwall Pete",
	"Slideways Sue",
	"Champagne Charlie",
	"Monza Mike",
	"Hairpin Hank",
	"Racing Line Ren",
	"Wetline Wes",
	"Slipstream Sly",
	"Late Brake Len",
	"Backmarker Bob",
]

var handle: String = ""
var tier: String = "Skilled"
var signature: String = "consistent"
var wins: int = 0
var losses: int = 0

## Names a persona on the roster. The tier is normalized through RacingLine so
## the presented tier is always exactly the tier the RivalDriver races at.
func configure(name: String, tier_value: String, trait_value: String) -> void:
	handle = name
	tier = RacingLine.normalize_tier(tier_value)
	signature = trait_value if trait_value in TRAITS else "consistent"

## Records one race result relative to the player (exactly once per finished
## rival per race — RaceManager guards the once).
func record_result(won: bool) -> void:
	if won:
		wins += 1
	else:
		losses += 1

## Shorthand rivalry record for grid/standings/results rows.
func get_record_string() -> String:
	return "%dW / %dL" % [wins, losses]

func to_dict() -> Dictionary:
	return {
		"handle": handle,
		"tier": tier,
		"trait": signature,
		"wins": wins,
		"losses": losses,
	}

## Restores a persona from a save payload, clamping invalid values.
func from_dict(data: Dictionary) -> void:
	var raw_handle: Variant = data.get("handle", "")
	handle = raw_handle if raw_handle is String else ""
	tier = RacingLine.normalize_tier(String(data.get("tier", "Skilled")))
	var raw_trait := String(data.get("trait", "consistent"))
	signature = raw_trait if raw_trait in TRAITS else "consistent"
	wins = maxi(int(data.get("wins", 0)), 0)
	losses = maxi(int(data.get("losses", 0)), 0)

## Deterministic persona assignment: shuffles the name pool with the seeded RNG
## (never the global one) and mints one persona per roster spec in order, wiring
## each back into spec["persona"] so RaceManager picks it up at spawn. Returns
## the ordered personas. Same specs + same seed -> identical field every time.
static func build_for_roster(specs: Array, seed: int) -> Array[RivalPersona]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pool := NAME_POOL.duplicate()
	_seeded_shuffle(pool, rng)
	var out: Array[RivalPersona] = []
	for i in range(specs.size()):
		var spec := specs[i] as Dictionary
		if spec == null:
			continue
		var persona := RivalPersona.new()
		persona.configure(
			pool[i % pool.size()],
			String(spec.get("tier", "Skilled")),
			TRAITS[rng.randi_range(0, TRAITS.size() - 1)])
		spec["persona"] = persona
		out.append(persona)
	return out

## Save payload for a persona roster: { SAVE_KEY_value: { seed, personas } }.
static func to_payload(personas: Array, seed: int) -> Dictionary:
	var items: Array[Dictionary] = []
	for persona in personas:
		var p := persona as RivalPersona
		if p != null:
			items.append(p.to_dict())
	return {"seed": seed, "personas": items}

## Restores a roster from a save payload -> { seed: int, personas: Array }.
static func from_payload(data: Dictionary) -> Dictionary:
	var out: Array[RivalPersona] = []
	var raw: Variant = data.get("personas", [])
	if raw is Array:
		for entry in raw:
			if entry is Dictionary:
				var persona := RivalPersona.new()
				persona.from_dict(entry)
				out.append(persona)
	return {"seed": int(data.get("seed", 0)), "personas": out}

## Slot contract: loads the persisted roster for `slot` when it still matches
## the configured spec count (restoring live W/L records), otherwise builds a
## fresh deterministic roster from `seed` and persists it. Returns
## { seed: int, personas: Array[RivalPersona] }.
static func contract_for_slot(specs: Array, slot: int, seed: int = 0) -> Dictionary:
	if SaveManager == null:
		return {"seed": seed, "personas": build_for_roster(specs, seed)}
	var payload := SaveManager.load_rival_personas(slot)
	if not payload.is_empty():
		var restored := from_payload(payload)
		var restored_personas: Array = restored["personas"]
		if restored_personas.size() == specs.size():
			for i in range(specs.size()):
				var spec := specs[i] as Dictionary
				if spec != null:
					spec["persona"] = restored_personas[i] as RivalPersona
			return restored
	var actual_seed := seed
	if actual_seed == 0:
		actual_seed = SaveManager.slot_created_at(slot)
		if actual_seed <= 0:
			actual_seed = int(Time.get_unix_time_from_system())
	var built := build_for_roster(specs, actual_seed)
	SaveManager.save_rival_personas(slot, to_payload(built, actual_seed))
	return {"seed": actual_seed, "personas": built}

## In-place Fisher-Yates via the SEEDED rng (Array.shuffle uses the global RNG
## and is therefore nondeterministic — never call it in a seeded path).
static func _seeded_shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp