# autoload/game_state.gd
extends Node

## Manages global game state, scene transitions, and pause.

signal scene_changed(scene_path: String)
signal game_paused
signal game_resumed

enum GameMode { MAIN_MENU, FREE_ROAM, RACE, LICENSE_TEST, GARAGE }

var current_mode: GameMode = GameMode.MAIN_MENU
var is_paused: bool = false

func change_scene(scene_path: String) -> void:
    get_tree().change_scene_to_file(scene_path)
    if current_mode != GameMode.MAIN_MENU:
        is_paused = false
    scene_changed.emit(scene_path)

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