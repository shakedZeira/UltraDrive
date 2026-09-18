# autoload/save_manager.gd
extends Node

## Persists game data to user:// (mapped to AppData on Windows).

const SAVE_DIR := "user://saves"
const MAX_SLOTS := 3

const DISCOVERY_KEY := "discovery"

func _ready() -> void:
    DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func save_game(slot: int, data: Dictionary) -> bool:
    if slot < 0 or slot >= MAX_SLOTS:
        return false
    var path := SAVE_DIR.path_join("slot_%d.json" % (slot + 1))
    var json := JSON.stringify(data, "\t")
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(json)
    file.close()
    return true

func load_game(slot: int) -> Dictionary:
    if slot < 0 or slot >= MAX_SLOTS:
        return {}
    var path := SAVE_DIR.path_join("slot_%d.json" % (slot + 1))
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var json: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    return json if json is Dictionary else {}

func has_save(slot: int) -> bool:
    var path := SAVE_DIR.path_join("slot_%d.json" % (slot + 1))
    return FileAccess.file_exists(path)

## Read-only accessor for the "discovery" sub-dict inside a save slot.
## Used by WorldDiscovery.load_from_slot() so the save contract stays
## additive to the existing slot schema.
func load_discovery(slot: int) -> Dictionary:
    var data := load_game(slot)
    var d: Variant = data.get(DISCOVERY_KEY, {})
    return d if d is Dictionary else {}

## Merge-write the discovery sub-dict into an existing save slot
## (read-modify-write: preserves other slot fields like owned_cars,
## active_car, quality_preset, season, etc).
func save_discovery(slot: int, discovery: Dictionary) -> bool:
    var data := load_game(slot)
    data[DISCOVERY_KEY] = discovery
    return save_game(slot, data)
