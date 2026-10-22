# scripts/career/car_brands.gd
class_name CarBrands
extends RefCounted

## Static brand registry for the garage rail: brand ids, display names, aliases,
## emblem paths and the section order. Pure data + string helpers (no scene or
## engine dependencies) so it is trivially headless-testable and safe to call
## from any UI layer.
##
## A car's brand is resolved in this order (first hit wins):
##   1. a non-empty CarConfig.brand (brand id or alias, case-insensitive),
##   2. the basename of resource_path / visual_path, whole-token alias match,
##   3. the same whole-token alias scan over car_name,
##   4. the in-house default (CarBrands.HOUSE_ID).
## Every fictional in-house car therefore lands in UltraDrive Motors with zero
## configuration, and configs / saves without the brand fields keep working.

const HOUSE_ID: String = "ultradrive"
const HOUSE_NAME: String = "UltraDrive Motors"

## The 12 rival emblems are the REAL manufacturers' trademarked logos, fetched
## from Wikimedia Commons at download time (the game never touches the network).
## They are shown exactly as downloaded - original colours and shapes, never
## recoloured or tinted - and assets/ui/brands/SOURCES.md records each file's
## Commons source page, thumbnail URL, retrieval date and licence. Only the
## house emblem is an original hand-authored monogram (UltraDrive Motors is
## fictional).
const BRANDS: Dictionary = {
	"ultradrive": {
		"display_name": "UltraDrive Motors",
		"emblem": "res://assets/ui/brands/house_ultradrive.svg",
		"aliases": ["ultradrive", "ultradrive motors"],
	},
	"bmw": {
		"display_name": "BMW",
		"emblem": "res://assets/ui/brands/bmw.png",
		"aliases": ["bmw"],
	},
	"chevrolet": {
		"display_name": "Chevrolet",
		"emblem": "res://assets/ui/brands/chevrolet.png",
		"aliases": ["chevrolet", "chevy"],
	},
	"ford": {
		"display_name": "Ford",
		"emblem": "res://assets/ui/brands/ford.png",
		"aliases": ["ford"],
	},
	"honda": {
		"display_name": "Honda",
		"emblem": "res://assets/ui/brands/honda.png",
		"aliases": ["honda"],
	},
	"lamborghini": {
		"display_name": "Lamborghini",
		"emblem": "res://assets/ui/brands/lamborghini.png",
		"aliases": ["lamborghini"],
	},
	"mazda": {
		"display_name": "Mazda",
		"emblem": "res://assets/ui/brands/mazda.png",
		"aliases": ["mazda"],
	},
	"mitsubishi": {
		"display_name": "Mitsubishi",
		"emblem": "res://assets/ui/brands/mitsubishi.png",
		"aliases": ["mitsubishi"],
	},
	"nissan": {
		"display_name": "Nissan",
		"emblem": "res://assets/ui/brands/nissan.png",
		"aliases": ["nissan"],
	},
	"porsche": {
		"display_name": "Porsche",
		"emblem": "res://assets/ui/brands/porsche.png",
		"aliases": ["porsche"],
	},
	"subaru": {
		"display_name": "Subaru",
		"emblem": "res://assets/ui/brands/subaru.png",
		"aliases": ["subaru"],
	},
	"toyota": {
		"display_name": "Toyota",
		"emblem": "res://assets/ui/brands/toyota.png",
		"aliases": ["toyota"],
	},
	"volkswagen": {
		"display_name": "Volkswagen",
		"emblem": "res://assets/ui/brands/volkswagen.png",
		"aliases": ["volkswagen", "vw"],
	},
}

## House brand first, every other brand alphabetically by display name. Groups
## are emitted in this order so the garage rail is stable across saves.
const CATEGORY_ORDER: Array[String] = [
	"ultradrive", "bmw", "chevrolet", "ford", "honda", "lamborghini", "mazda",
	"mitsubishi", "nissan", "porsche", "subaru", "toyota", "volkswagen",
]

## All known brand ids as a fresh array in section order.
static func brand_ids() -> Array:
	return CATEGORY_ORDER.duplicate()

## Display name for a brand id; unknown ids fall back to the house name.
static func display_name(id: String) -> String:
	if BRANDS.has(id):
		return String(BRANDS[id]["display_name"])
	return HOUSE_NAME

## Emblem path for a brand id; unknown ids fall back to the house emblem. The
## path is returned even if the file is missing - the UI simply shows no emblem
## when the texture fails to load.
static func emblem_path(id: String) -> String:
	if BRANDS.has(id):
		return String(BRANDS[id]["emblem"])
	return String(BRANDS[HOUSE_ID]["emblem"])

## Emblem path for a car: the emblem of its resolved brand.
static func emblem_for_car(car: CarConfig) -> String:
	return emblem_path(resolve_brand_id(car))

## Resolves a car to a brand id. Never returns an empty string: an unrecognized
## car still lands in the in-house brand, so no owned car is ever invisible.
static func resolve_brand_id(car: CarConfig) -> String:
	if car == null:
		return HOUSE_ID
	var explicit := car.brand.strip_edges().to_lower()
	if not explicit.is_empty():
		if BRANDS.has(explicit):
			return explicit
		var by_alias := _alias_brand_id(explicit)
		if not by_alias.is_empty():
			return by_alias
	var from_path := _brand_from_tokens(_basename_tokens(car.resource_path))
	if from_path.is_empty():
		from_path = _brand_from_tokens(_basename_tokens(car.visual_path))
	if not from_path.is_empty():
		return from_path
	var from_name := _brand_from_tokens(car.car_name.replace(" ", "_"))
	if not from_name.is_empty():
		return from_name
	return HOUSE_ID

## Display-only brand name for a car: the per-car override when set, else the
## resolved brand's display name.
static func brand_display_name(car: CarConfig) -> String:
	if car != null:
		var override := car.brand_display_name.strip_edges()
		if not override.is_empty():
			return override
	return display_name(resolve_brand_id(car))

## Partitions owned cars into ordered brand groups:
## [{"brand_id", "display_name", "emblem_path", "cars": Array[CarConfig]}, ...]
## Only brands owning >=1 car are returned, in CATEGORY_ORDER; empty -> [].
static func group_owned(owned: Array) -> Array:
	var buckets: Dictionary = {}
	for entry in owned:
		var car := entry as CarConfig
		if car == null:
			continue
		var brand_id := resolve_brand_id(car)
		var bucket: Array = buckets.get(brand_id, [])
		bucket.append(car)
		buckets[brand_id] = bucket
	var groups: Array = []
	for ordered_id: String in CATEGORY_ORDER:
		if not buckets.has(ordered_id):
			continue
		groups.append({
			"brand_id": ordered_id,
			"display_name": display_name(ordered_id),
			"emblem_path": emblem_path(ordered_id),
			"cars": buckets[ordered_id],
		})
	return groups

# --- internals ---------------------------------------------------------------

## Brand id whose alias list contains `alias_l` (already lower-cased); "" when
## no brand claims the token. Single pass over CATEGORY_ORDER keeps the result
## deterministic.
static func _alias_brand_id(alias_l: String) -> String:
	for brand_id: String in CATEGORY_ORDER:
		var aliases: Array = BRANDS[brand_id]["aliases"]
		for alias in aliases:
			if String(alias).to_lower() == alias_l:
				return brand_id
	return ""

## First brand alias found while scanning the `_`-separated tokens of `text`
## left to right. Whole-token matching only, so "forward" never matches "ford".
static func _brand_from_tokens(text: String) -> String:
	if text.is_empty():
		return ""
	for raw in text.split("_"):
		var token := String(raw).strip_edges().to_lower()
		if token.is_empty():
			continue
		var brand_id := _alias_brand_id(token)
		if not brand_id.is_empty():
			return brand_id
	return ""

## "res://assets/cars/nissan_gt_r35_2017.glb" -> "nissan_gt_r35_2017".
static func _basename_tokens(path: String) -> String:
	if path.is_empty():
		return ""
	return path.get_file().get_basename()
