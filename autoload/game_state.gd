# autoload/game_state.gd
extends Node

## Manages global game state, scene transitions, and pause.

signal scene_changed(scene_path: String)
signal game_paused
signal game_resumed

const SettingsMenuScript: GDScript = preload("res://scripts/ui/settings_menu.gd")

enum GameMode { MAIN_MENU, FREE_ROAM, RACE, LICENSE_TEST, GARAGE }
enum TransmissionMode { AUTO, MANUAL }

## Save key for the transmission preference (AUTO=0 / MANUAL=1) inside the
## slot-0 save. Missing key == fresh install (or a pre-feature save that never
## persisted the mode) -> MANUAL, the new default.
const TRANSMISSION_SAVE_KEY := "transmission_mode"

var current_mode: GameMode = GameMode.MAIN_MENU
var transmission_mode: TransmissionMode = TransmissionMode.MANUAL
var quality_preset: int = 1
var probe_enabled: bool = true
## F5 camera-and-feel settings surface (XAG-117). The persisted knob dict,
## restored from the slot-0 save (or first-boot quality-ladder defaults) and
## re-applied onto every scene transition like quality_preset.
var camera_settings: Dictionary = {}
var season: int = RegionalClimate.Season.SUMMER
var is_paused: bool = false
var session_stats: SessionStats = SessionStats.new()
var nav_assist_enabled: bool = true
## Race demo S5: global on/off for the rubber-band assist. When on, only
## Novice / traffic AI get a multiplier offset — the player and Skilled/Expert
## racers always run their exact no-rubber-band pace.
var rubber_band_assist: bool = true

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    var data := SaveManager.load_game(0)
    if data.has("quality_preset"):
        quality_preset = clamp(int(data["quality_preset"]), 0, SettingsMenuScript.QUALITY_PRESETS.size() - 1)
    else:
        quality_preset = SettingsMenuScript.default_quality_preset()
    if data.has("probe_enabled"):
        probe_enabled = bool(data["probe_enabled"])
    if data.has(SettingsMenuScript.CAMERA_SETTINGS_KEY):
        camera_settings = SettingsMenuScript.camera_settings_from_save(data)
    else:
        camera_settings = SettingsMenuScript.camera_settings_for_quality_preset(quality_preset)
    if data.has("season"):
        season = clamp(int(data["season"]), 0, RegionalClimate.SEASON_COUNT - 1)
    else:
        season = _default_season()
    transmission_mode = transmission_mode_from_save(data)
    WeatherManager.set_season(season)
    call_deferred("_apply_quality_to_current_scene")

## Fresh-install default is MANUAL; a saved explicit choice in the slot save
## overrides it. New saves lack the key and so land on the new default; old
## saves never persisted the mode, so they do too (existing data is never
## interpreted as an AUTO preference it never recorded).
static func transmission_mode_from_save(data: Dictionary) -> TransmissionMode:
    if data.has(TRANSMISSION_SAVE_KEY):
        return TransmissionMode.MANUAL if int(data[TRANSMISSION_SAVE_KEY]) == 1 else TransmissionMode.AUTO
    return TransmissionMode.MANUAL

## Season from the system's real-world week number (P4): the 52-week year
## rotates through WINTER/SPRING/SUMMER/FALL.
static func _default_season() -> int:
    var unix_time := Time.get_unix_time_from_system()
    var week := posmod(int(floorf(unix_time / 604800.0)), RegionalClimate.SEASON_WEEKS)
    return RegionalClimate.season_for_week(week)

func get_season() -> int:
    return season

func set_season(value: int) -> void:
    season = clamp(value, 0, RegionalClimate.SEASON_COUNT - 1)
    WeatherManager.set_season(season)
    var data := SaveManager.load_game(0)
    data["season"] = season
    SaveManager.save_game(0, data)

func change_scene(scene_path: String) -> void:
    get_tree().change_scene_to_file(scene_path)
    # Set mode from destination so the pause guard in _unhandled_input works
    if "main_menu" in scene_path:
        current_mode = GameMode.MAIN_MENU
    else:
        current_mode = GameMode.FREE_ROAM
    is_paused = false
    scene_changed.emit(scene_path)
    call_deferred("_apply_quality_to_current_scene")

## Pushes the saved quality preset onto whichever scene is current so bootstrap
## timing disagrees with the scene's baked (max) environment. change_scene is
## deferred engine-side, so wait a frame before touching the new tree.
func _apply_quality_to_current_scene() -> void:
    await get_tree().process_frame
    if not is_inside_tree():
        return
    var scene := get_tree().current_scene
    if scene == null:
        return
    SettingsMenuScript.apply_to_scene_tree(quality_preset, scene, get_tree().root)
    SettingsMenuScript.apply_camera_settings(camera_settings, scene)

func pause_game() -> void:
    if is_paused:
        return
    is_paused = true
    get_tree().paused = true
    game_paused.emit()

func resume_game() -> void:
    if not is_paused:
        return
    is_paused = false
    get_tree().paused = false
    game_resumed.emit()

func toggle_pause() -> void:
    if is_paused:
        resume_game()
    else:
        pause_game()

func set_mode(mode: GameMode) -> void:
    current_mode = mode

func set_transmission_mode(mode: TransmissionMode) -> void:
    transmission_mode = mode
    var data := SaveManager.load_game(0)
    data[TRANSMISSION_SAVE_KEY] = int(mode)
    SaveManager.save_game(0, data)

func set_quality_preset(preset: int) -> void:
    quality_preset = preset
    var data := SaveManager.load_game(0)
    data["quality_preset"] = quality_preset
    SaveManager.save_game(0, data)

func set_probe_enabled(enabled: bool) -> void:
    probe_enabled = enabled
    var data := SaveManager.load_game(0)
    data["probe_enabled"] = probe_enabled
    SaveManager.save_game(0, data)

## F5 camera-and-feel accessors: read a single knob (falling back to the
## canonical default) and persist a change to the slot-0 save the same additive
## way quality_preset is saved — the settings menu (and F4's mirror) write
## through here, and image-depth bookkeeping never touches the rest of the slot.
func get_camera_setting(key: String) -> Variant:
    if camera_settings.has(key):
        return camera_settings[key]
    return SettingsMenuScript.CAMERA_SETTINGS_DEFAULTS.get(key, null)

func set_camera_setting(key: String, value: Variant) -> void:
    camera_settings[key] = value
    var data := SaveManager.load_game(0)
    data[SettingsMenuScript.CAMERA_SETTINGS_KEY] = camera_settings
    SaveManager.save_game(0, data)

func _physics_process(_delta: float) -> void:
    if current_mode == GameMode.MAIN_MENU:
        return
    if Input.is_action_just_pressed("pause"):
        toggle_pause()