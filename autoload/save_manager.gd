# autoload/save_manager.gd
extends Node

## Persists game data to user:// (mapped to AppData on Windows).

const SAVE_DIR := "user://saves"
const MAX_SLOTS := 3

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
